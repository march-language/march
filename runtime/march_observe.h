/* march_observe.h — the node observe socket (R0 of
 * specs/plans/2026-09-28-observe-recon-shell-plan.md).
 *
 * A read-only control socket, SEPARATE from the hot-reload server
 * (march_reload.c serves one client at a time on one thread, so an observer
 * held open there would block a deploy).  It is started from
 * march_run_scheduler when MARCH_OBSERVE_SOCKET is set, or, when only
 * MARCH_HOT_RELOAD_SOCKET is set, at "<reload socket>.observe".
 *
 * Protocol: the client sends ONE line (a verb and its arguments), the server
 * answers ONE line of JSON and closes.  Every answer is an envelope:
 *
 *   {"proto":"march.observe/1","node":"…","at_ms":…,"took_us":…,
 *    "truncated":false,"data":…}
 *
 * or, on failure, the same envelope with "error":"<code>" in place of data.
 *
 * This file also declares the small JSON writer the verbs build their data
 * with (march_jw_*). */
#ifndef MARCH_OBSERVE_H
#define MARCH_OBSERVE_H

#include <stddef.h>
#include <stdint.h>

/* ── JSON writer ──────────────────────────────────────────────────────────
 * A growable buffer with a hard size limit.  Commas are inserted for you:
 * call jw_key before each object member's value, nothing between array
 * elements.  Once a write would pass [limit] bytes, the writer stops writing
 * and sets [truncated]; the partial buffer is then NOT valid JSON, and the
 * server replaces it with null and reports "truncated":true. */
/* Deep enough for TREE: two levels per supervision level (a node object and
 * its children array) times TREE_MAX_DEPTH (64), plus SNAPSHOT's wrapping
 * (march_observe_snapshot.c checks this at compile time).  At 32, a tree
 * only 15 supervisors deep blanked the whole reply. */
#define MARCH_JW_MAX_DEPTH 160

typedef struct march_jw {
    char   *buf;
    size_t  len;
    size_t  cap;
    size_t  limit;
    int     truncated;
    int     oom;
    int     depth;
    int     after_key;
    unsigned char first[MARCH_JW_MAX_DEPTH + 1];
} march_jw;

void march_jw_init(march_jw *w, size_t limit);
void march_jw_free(march_jw *w);
/* The NUL-terminated text written so far ("" if nothing). */
const char *march_jw_text(const march_jw *w);
/* True iff the text is complete and usable: not truncated, no allocation
 * failure, and every object/array closed. */
int march_jw_ok(const march_jw *w);

void march_jw_obj_begin(march_jw *w);
void march_jw_obj_end(march_jw *w);
void march_jw_arr_begin(march_jw *w);
void march_jw_arr_end(march_jw *w);
void march_jw_key(march_jw *w, const char *key);
void march_jw_str(march_jw *w, const char *s);
void march_jw_strn(march_jw *w, const char *s, size_t n);
void march_jw_i64(march_jw *w, int64_t v);
void march_jw_u64(march_jw *w, uint64_t v);
void march_jw_f64(march_jw *w, double v);   /* non-finite -> null */
void march_jw_bool(march_jw *w, int v);
void march_jw_null(march_jw *w);

/* ── Server ───────────────────────────────────────────────────────────── */

/* Start the server once, from the environment (see the file comment).  A
 * no-op when neither variable is set or on any later call.  Called from
 * march_run_scheduler on the main OS thread, before any green thread runs. */
void march_observe_maybe_start(void);

/* Start the server on [path].  Returns 0 on success, -1 on failure (bad or
 * too-long path, an existing non-socket file at [path], socket errors); the
 * reason is printed to stderr.  Never removes a file that is not a socket. */
int march_observe_server_start(const char *path);

/* Connections currently being served (for tests). */
int march_observe_active_conns(void);

/* Extra verbs, registered before the server starts.  The server itself
 * serves HELP and PING; march_observe_snapshot.c registers the snapshot
 * verbs (R1) from march_run_scheduler.  A verb writes its data into [w] and
 * returns NULL, or returns an error code ("bad_args", "not_found", ...) and
 * writes nothing.  [args] is the rest of the line after the verb and one
 * space, possibly "".  Verbs run on observe connection threads: never on a
 * scheduler or green thread, so they may block briefly on a leaf mutex but
 * must not call March code. */
typedef const char *(*march_observe_verb_fn)(march_jw *w, const char *args);

typedef struct march_observe_verb {
    const char            *name;
    const char            *tier;   /* "observe" | "debug" | "exec" */
    const char            *args;   /* human-readable argument synopsis */
    const char            *help;
    march_observe_verb_fn  fn;
} march_observe_verb;

/* Register [n] verbs (the array must outlive the process).  Returns 0, or -1
 * when the table is full or the server is already running. */
int march_observe_add_verbs(const march_observe_verb *v, size_t n);

/* Answer one request line in-process: [out] (initialised by the caller)
 * gets the same envelope a socket client would. */
void march_observe_handle(const char *line, size_t n, march_jw *out);

/* Register the R1 snapshot verbs (march_observe_snapshot.c).  Idempotent. */
void march_observe_snapshot_install(void);

/* ── Snapshot layer (R1) ──────────────────────────────────────────────────
 * One copy-out walk of the live actor table, done by march_runtime.c (where
 * the table lives) inside one reclamation critical section.  The rows are
 * plain data owned by the caller: nothing in them points into a meta or a
 * proc, so JSON is written after the section with no lock held.
 *
 * Deliberately absent: an actor's crash message (C7 of the plan: panic
 * strings can carry payloads; the observe tier reports the death KIND only). */
#define MARCH_OBS_TYPE_MAX 96

typedef struct march_obs_actor {
    int64_t  pid;             /* pid index */
    int64_t  cap_epoch;       /* capability epoch (bumped by supervised respawn) */
    char     type[MARCH_OBS_TYPE_MAX]; /* actor type, "" when unknown */
    int      status;          /* march_proc_status, or -1: not activated yet */
    int64_t  mbox;            /* user + control messages queued */
    int64_t  user_mbox;       /* user messages queued */
    int64_t  mbox_limit;      /* 0 = unbounded */
    int      mbox_policy;     /* march_mbox_policy */
    uint32_t code_epoch;
    int      sched;           /* scheduler that last ran it, -1 if none */
    int      pinned;
    int      draining;
    int64_t  parent;          /* supervisor's pid index, -1 when unsupervised */
    int      child_index;     /* slot in the parent's supervise block */
    int      num_children;    /* > 0: this actor is a supervisor */
    char   **names;           /* registered names (owned) */
    int      n_names;
    /* R2 counters (march_proc): cumulative since spawn. */
    uint64_t slices;          /* times dispatched */
    uint64_t msgs_in;         /* user messages received */
    uint64_t msgs_out;        /* messages sent and enqueued */
    int64_t  last_run_ms;     /* march_now_ms (monotonic) at the last dispatch, 0 = never */
    int64_t  held;            /* messages an Actor.call is holding off the mailbox */
    int      crashes;         /* crash-ring entries for this pid in the last hour */
    int64_t  spawned_by;      /* pid of the actor that spawned it, -1 if none */
    int64_t  tparent;         /* TREE's parent: supervisor, else spawner (verbs only) */
    int      child_crashes;   /* ... for its supervised children (a restarted child
                                 has a new pid, so its crashes count here)
                                 (both filled by the verbs, not the walk) */
} march_obs_actor;

/* Snapshot every live actor.  On success *rows is a malloc'd array of *n
 * rows (free with march_obs_actors_free) and 0 is returned; -1 on allocation
 * failure (nothing to free). */
int  march_obs_actors(march_obs_actor **rows, size_t *n);
void march_obs_actors_free(march_obs_actor *rows, size_t n);

/* Supervisor configuration and a dead actor's tombstone, for ACTOR <pid>. */
typedef struct march_obs_actor_extra {
    int      known;            /* pid was ever spawned */
    int      alive;            /* linked in the actor table */
    int      terminal_set;     /* dead and its death processed */
    int      terminal_reason;  /* march_death_reason (kind only, never text) */
    int64_t  cap_epoch;
    int      supervisor;       /* declares a supervise block */
    int      strategy;         /* 0 one_for_one, 1 one_for_all, 2 rest_for_one */
    int64_t  max_restarts;
    int64_t  window_secs;
    int      n_restarts;       /* restart timestamps held (pruned lazily) */
    int64_t  restart_age_ms[16]; /* newest first, at most 16 */
} march_obs_actor_extra;

/* Fill [out] for [pid].  Returns 0 (out->known says whether the pid exists). */
int march_obs_actor_extra_get(int64_t pid, march_obs_actor_extra *out);

/* ── Crash ring (R2) ──────────────────────────────────────────────────────
 * The last MARCH_CRASH_RING crashes, newest first.  The message is kept for
 * the debug tier (R4); observe-tier verbs never print it (C7). */
#define MARCH_CRASH_RING     256
#define MARCH_CRASH_MSG_MAX  512
enum { MARCH_CRASH_KIND_CRASH = 0,      /* a supervised child panicked */
       MARCH_CRASH_KIND_DRAINING = 1,   /* killed at a hot-reload drain's hard deadline */
       MARCH_CRASH_KIND_PANIC = 2 };    /* an unsupervised panic: the process exits */

typedef struct march_obs_crash {
    uint64_t seq;            /* 1, 2, ... over the process lifetime */
    int64_t  pid;            /* -1: not an actor (main, a task) */
    char     type[MARCH_OBS_TYPE_MAX];
    int      kind;
    uint32_t code_epoch;
    int64_t  supervisor;     /* supervisor pid, -1 when unsupervised */
    int      restart;        /* the child slot's crash streak after this crash (1, 2, ...); 0 = none */
    int64_t  at_ms;          /* wall clock, ms since the epoch */
    size_t   message_len;    /* bytes kept (truncated at MARCH_CRASH_MSG_MAX) */
    char     message[MARCH_CRASH_MSG_MAX + 1];
} march_obs_crash;

/* Copy up to [max] entries, newest first, into [out]; returns how many.
 * [*total] (if non-NULL) gets the number of crashes ever recorded. */
int march_obs_crashes(march_obs_crash *out, int max, uint64_t *total);

/* ── Debug tier (R4) ─────────────────────────────────────────────────────
 * Actor.inspect_state for a thread that is not a green thread (the observe
 * socket's STATE verb): sends the reserved inspect request to actor [pid]
 * and waits up to [timeout_ms] on a condition variable.  Returns 1 with the
 * rendered state in *out, or 0 with the reason in *out ("dead", "timeout",
 * "busy", "render failed: ...", ...).  *out is malloc'd either way (NULL
 * only on allocation failure); the caller frees it.  Defined in
 * march_runtime.c. */
int march_actor_inspect_external(int64_t pid, int64_t timeout_ms, char **out);

/* Register the signed debug verbs (march_observe_debug.c); called by
 * march_observe_snapshot_install. */
void march_observe_debug_install(void);

/* Most connections served at once; a further client gets "error":"busy". */
#define MARCH_OBSERVE_MAX_CONNS 8
/* Longest request line accepted, including arguments. */
#define MARCH_OBSERVE_LINE_MAX 4096

#endif /* MARCH_OBSERVE_H */
