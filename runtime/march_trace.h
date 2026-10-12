/* march_trace.h — bounded trace sessions for boundary calls (R8 of
 * specs/plans/2026-09-28-observe-recon-shell-plan.md; introspection design
 * specs/2026-09-23-per-actor-introspection-design.md §5, stage C1, narrowed
 * to boundary calls: see specs/progress/2026-10-11-observe-r8-tracing.md).
 *
 * A session watches a set of hot-reload dispatch slots (boundary functions,
 * by name).  Every entry into a watched slot writes one fixed-size event
 * {pid, name_id, epoch, at_ns} into the session's ring.  NO ARGUMENTS are
 * ever recorded: arguments can hold secrets.
 *
 * MANDATORY LIMITS.  A session cannot be created without one:
 *   Count(n)        records exactly n events, then stops itself;
 *   Rate(n, per_s)  records at most n events per window of per_s seconds
 *                   and drops (counts) the rest.
 * Whatever the limit, every session also ends by itself after
 * MARCH_TRACE_LIFETIME_S seconds, or MARCH_TRACE_IDLE_S seconds without a
 * drain.  There is no connection to bind a session to (the observe socket
 * serves one request per connection), so the session id plus these two
 * timers are what bound its life.
 *
 * Cost.  The dispatch fast path pays one relaxed load of the slot's `traced`
 * word (the cache line it has already loaded for `current`) and a
 * never-taken branch while no session watches that slot.  All the work is in
 * march_trace_hit, out of line.
 *
 * ACTOR EVENTS.  A session may also record what actors do: Sent, Received,
 * Spawned, Exited, Dropped (specs/progress/2026-10-12-observe-trace-actor-events.md).
 * An event is {kind, pid, peer, msg_tag, reason, epoch, at_ns}: pids, a
 * message's constructor tag, a reason code, a time.  NEVER a message's
 * contents or any argument.  An actor-event session is refused without a
 * pid filter (1..MARCH_TRACE_MAX_PIDS live actors): it records only events
 * whose subject or counterpart is one of them.  There is no "all actors"
 * form, because a node-wide stream makes every send on the node pay for the
 * tracer; the filter also lets the hooks decide with one load of a per-proc
 * mask (march_proc.trace_mask) before doing anything else.  The same Count /
 * Rate limit bounds the session's events, calls and actor events together.
 *
 * Cost of the hooks while no session records actor events: one relaxed load
 * of g_introspect_armed and a never-taken branch on the send path, one
 * relaxed load of the actor's own trace_mask per received message, the same
 * armed test at spawn, exit and the drop sites.  Everything else is out of
 * line in this file.
 *
 * Producers (any scheduler thread) are lock-free and never wait for a
 * consumer: a full ring drops the event and counts it.  The consumer
 * (drain) and control plane (start/stop) take one mutex. */
#ifndef MARCH_TRACE_H
#define MARCH_TRACE_H

#include <stdint.h>

#define MARCH_TRACE_MAX_SESSIONS   4
#define MARCH_TRACE_MAX_FNS        32
#define MARCH_TRACE_COUNT_MAX      65536     /* Count(n): 1..this */
#define MARCH_TRACE_RATE_MAX       100000    /* Rate(n, _): 1..this */
#define MARCH_TRACE_PER_S_MAX      3600      /* Rate(_, s): 1..this */
#define MARCH_TRACE_RING_DEFAULT   1024      /* Rate sessions' ring, slots */
#define MARCH_TRACE_RING_MAX       16384
#define MARCH_TRACE_LIFETIME_S     600
#define MARCH_TRACE_IDLE_S         60
#define MARCH_TRACE_DRAIN_MAX      4096      /* events per drain call */
#define MARCH_TRACE_NAME_MAX       96
#define MARCH_TRACE_MAX_PIDS       8         /* actor-event pid filter */
#define MARCH_TRACE_NONE           INT64_MIN /* an absent peer / tag */

/* Event kinds.  CALL is a boundary call (the R8 events); the rest are actor
 * events.  A session's kind mask has bit (1 << kind) set per kind it wants. */
typedef enum {
    MARCH_TRACE_EV_CALL = 0,
    MARCH_TRACE_EV_SENT = 1,       /* pid sent to peer */
    MARCH_TRACE_EV_RECEIVED = 2,   /* pid took a message off its mailbox to run it */
    MARCH_TRACE_EV_SPAWNED = 3,    /* pid spawned peer */
    MARCH_TRACE_EV_EXITED = 4,     /* pid died; reason: march_death_reason */
    MARCH_TRACE_EV_DROPPED = 5,    /* pid did not get a message from peer; reason below */
    MARCH_TRACE_EV_LAST = 5
} march_trace_ev_kind;
#define MARCH_TRACE_EVB(k) (1u << (k))
#define MARCH_TRACE_ACTOR_KINDS    (MARCH_TRACE_EVB(1) | MARCH_TRACE_EVB(2) | MARCH_TRACE_EVB(3) \
                                    | MARCH_TRACE_EVB(4) | MARCH_TRACE_EVB(5))

/* Dropped reasons. */
#define MARCH_TRACE_DROP_DEAD      0     /* the recipient is gone */
#define MARCH_TRACE_DROP_DRAINING  1     /* the recipient is shutting down */
#define MARCH_TRACE_DROP_FULL      2     /* mailbox full, DROP_NEW: this message refused */
#define MARCH_TRACE_DROP_EVICTED   3     /* mailbox full, DROP_OLD: the oldest message lost */
/* Exited reasons are march_death_reason: 0 normal, 1 killed, 2 crash. */

typedef enum { MARCH_TRACE_COUNT = 1, MARCH_TRACE_RATE = 2 } march_trace_kind;

typedef struct {
    int32_t  kind;      /* march_trace_ev_kind */
    int32_t  reason;    /* Exited / Dropped: the code above; else -1 */
    int64_t  peer;      /* the counterpart's pid index, -1 for a non-actor, or MARCH_TRACE_NONE */
    int64_t  tag;       /* Sent / Received / Dropped: the message's constructor tag, or
                           MARCH_TRACE_NONE (an immediate, or not applicable) */
    int64_t  pid;       /* the calling actor's pid index (what pid_to_int and Recon say);
                           -1 when the caller is not an actor (main, a task) */
    uint32_t name_id;
    uint32_t epoch;     /* code epoch of the version entered */
    uint64_t at_ns;     /* recorded: monotonic; drained: ns since the session started
                           (an absolute monotonic clock passes 2^53 ns, which a JSON
                           double cannot hold exactly, after about 104 days) */
} march_trace_event;

/* Actor-event options of a session.  [kinds] is a mask of MARCH_TRACE_EVB(k);
 * 0 means boundary calls only, and then [npids] must be 0.  With kinds,
 * [npids] must be 1..MARCH_TRACE_MAX_PIDS live actors (pid indices). */
typedef struct {
    uint32_t kinds;
    int      npids;
    int64_t  pids[MARCH_TRACE_MAX_PIDS];
} march_trace_actor_opts;

/* Start a session over the dispatch slots named in [names] (exact function
 * names; at most MARCH_TRACE_MAX_FNS; none is allowed when [ev] asks for actor
 * events).  [a] is n; [b] is per_s for a Rate;
 * [ring] is the Rate ring size in slots (<= 0: the default; ignored for
 * Count, whose ring holds exactly n).  [ev] may be NULL.  Returns NULL and
 * sets *id, or the error code: "limit_out_of_range", "bad_args",
 * "unknown_function", "pids_required", "unknown_pid", "too_many_sessions",
 * "out_of_memory". */
const char *march_trace_start(march_trace_kind kind, int64_t a, int64_t b,
                              int64_t ring, const char *const *names,
                              int nnames, const march_trace_actor_opts *ev,
                              int64_t *id);

typedef struct {
    uint64_t recorded;      /* events accepted into the ring so far */
    uint64_t dropped;       /* ring full */
    uint64_t rate_dropped;  /* over the Rate budget */
    uint64_t pending;       /* recorded and not yet drained */
    int      done;          /* the session has stopped recording */
    const char *why;        /* when done: "count" | "expired" | "idle" | NULL */
    uint64_t now_ns;        /* ns since the session started */
    uint32_t ev_kinds;      /* the session's actor-event kind mask (0: calls only) */
} march_trace_status;

/* Move up to [max] (<= MARCH_TRACE_DRAIN_MAX) published events into [out].
 * Returns the count (>= 0) or -1 when [id] names no live session. */
int march_trace_drain(int64_t id, int max, march_trace_event *out,
                      march_trace_status *st);
/* Stop and free a session.  0, or -1 when [id] names none. */
int march_trace_stop(int64_t id, march_trace_status *st);

/* Sessions currently allocated (for tests). */
int march_trace_sessions(void);

/* Runtime entry points the hooks and the control plane use (runtime.c). */
struct march_proc;
int64_t march_trace_proc_pid(struct march_proc *p);
int     march_trace_flag_pid(int64_t pid_index, uint32_t set, uint32_t clear);

/* Called by the dispatch table when a slot with a non-zero `traced` mask is
 * entered.  [mask] is the slot's session bit set. */
void march_trace_hit(uint32_t name_id, uint32_t mask, uint32_t epoch);

#endif
