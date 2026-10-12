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

typedef enum { MARCH_TRACE_COUNT = 1, MARCH_TRACE_RATE = 2 } march_trace_kind;

typedef struct {
    int64_t  pid;       /* the calling actor's pid index (what pid_to_int and Recon say);
                           -1 when the caller is not an actor (main, a task) */
    uint32_t name_id;
    uint32_t epoch;     /* code epoch of the version entered */
    uint64_t at_ns;     /* recorded: monotonic; drained: ns since the session started
                           (an absolute monotonic clock passes 2^53 ns, which a JSON
                           double cannot hold exactly, after about 104 days) */
} march_trace_event;

/* Start a session over the dispatch slots named in [names] (exact function
 * names; at most MARCH_TRACE_MAX_FNS).  [a] is n; [b] is per_s for a Rate;
 * [ring] is the Rate ring size in slots (<= 0: the default; ignored for
 * Count, whose ring holds exactly n).  Returns NULL and sets *id, or the
 * error code: "limit_out_of_range", "bad_args", "unknown_function",
 * "too_many_sessions", "out_of_memory". */
const char *march_trace_start(march_trace_kind kind, int64_t a, int64_t b,
                              int64_t ring, const char *const *names,
                              int nnames, int64_t *id);

typedef struct {
    uint64_t recorded;      /* events accepted into the ring so far */
    uint64_t dropped;       /* ring full */
    uint64_t rate_dropped;  /* over the Rate budget */
    uint64_t pending;       /* recorded and not yet drained */
    int      done;          /* the session has stopped recording */
    const char *why;        /* when done: "count" | "expired" | "idle" | NULL */
    uint64_t now_ns;        /* ns since the session started */
} march_trace_status;

/* Move up to [max] (<= MARCH_TRACE_DRAIN_MAX) published events into [out].
 * Returns the count (>= 0) or -1 when [id] names no live session. */
int march_trace_drain(int64_t id, int max, march_trace_event *out,
                      march_trace_status *st);
/* Stop and free a session.  0, or -1 when [id] names none. */
int march_trace_stop(int64_t id, march_trace_status *st);

/* Sessions currently allocated (for tests). */
int march_trace_sessions(void);

/* Called by the dispatch table when a slot with a non-zero `traced` mask is
 * entered.  [mask] is the slot's session bit set. */
void march_trace_hit(uint32_t name_id, uint32_t mask, uint32_t epoch);

#endif
