/* march_observe_snapshot.c — the observe socket's snapshot verbs (R1 of
 * specs/plans/2026-09-28-observe-recon-shell-plan.md).
 *
 *   ACTORS [sort] [n]  the live actors, sorted (mbox|status|epoch|pid), at most n
 *   ACTOR <pid>        one actor: its row, children, supervisor config, death kind
 *   TREE               the supervision tree, plus the unsupervised actors
 *   NAMES              registered name -> pid
 *   SCHED              per-scheduler and global scheduler counters
 *   MEM                RSS, peak RSS, live heap objects, queued messages
 *   EPOCHS             hot-reload epochs, pins, slots and delivery counters
 *   SNAPSHOT [s,...]   several of the above in one reply (default: all)
 *
 * Everything here reads data the runtime already keeps: no new counters, so
 * nothing on a scheduler's hot path changes.  The actor verbs work from ONE
 * copy-out walk (march_obs_actors, in march_runtime.c next to the actor
 * table); sorting, tree building and JSON all happen after that walk's
 * critical section, with no lock held.
 *
 * Observe tier: no verb here reports an actor's crash MESSAGE (panic text can
 * carry payloads, C7 of the plan), only the death kind. */
#define _GNU_SOURCE
#include "march_observe.h"
#include "march_runtime.h"
#include "march_scheduler.h"
#include "march_dispatch.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <mach/mach.h>
#endif

#define ACTORS_DEFAULT_N 100
#define ACTORS_MAX_N     10000
#define TREE_MAX_DEPTH   64
#define TREE_MAX_NODES   10000

/* TREE inside SNAPSHOT nests: snapshot object, tree object, roots array, then
 * a node object and its children array per level. */
_Static_assert(3 + 2 * TREE_MAX_DEPTH + 2 <= MARCH_JW_MAX_DEPTH,
               "the JSON writer must nest deeper than the deepest TREE");

/* ── Field renderers ──────────────────────────────────────────────────── */

static const char *status_name(int s) {
    switch (s) {
    case PROC_RUNNABLE: return "runnable";
    case PROC_RUNNING:  return "running";
    case PROC_WAITING:  return "waiting";
    case PROC_DEAD:     return "exiting";   /* proc finished, death not yet claimed */
    case PROC_PARKED:   return "waiting";   /* transient half of a park */
    default:            return "starting";  /* spawned, green thread not activated */
    }
}

static const char *policy_name(int p) {
    switch (p) {
    case MARCH_MBOX_DROP_NEW: return "drop_new";
    case MARCH_MBOX_DROP_OLD: return "drop_old";
    case MARCH_MBOX_BLOCK:    return "block";
    default:                  return "unbounded";
    }
}

static const char *death_kind(int reason) {
    switch (reason) {
    case MARCH_DEATH_KILLED: return "Killed";
    case MARCH_DEATH_CRASH:  return "Crash";
    default:                 return "Normal";
    }
}

static const char *strategy_name(int s) {
    switch (s) {
    case 1:  return "one_for_all";
    case 2:  return "rest_for_one";
    default: return "one_for_one";
    }
}

static void write_names(march_jw *w, const march_obs_actor *r) {
    march_jw_arr_begin(w);
    for (int k = 0; k < r->n_names; k++) march_jw_str(w, r->names[k]);
    march_jw_arr_end(w);
}

static void write_type(march_jw *w, const march_obs_actor *r) {
    if (r->type[0]) march_jw_str(w, r->type); else march_jw_null(w);
}

static void write_row(march_jw *w, const march_obs_actor *r) {
    march_jw_obj_begin(w);
    march_jw_key(w, "pid");         march_jw_i64(w, r->pid);
    march_jw_key(w, "type");        write_type(w, r);
    march_jw_key(w, "names");       write_names(w, r);
    march_jw_key(w, "status");      march_jw_str(w, status_name(r->status));
    march_jw_key(w, "mbox");        march_jw_i64(w, r->mbox);
    march_jw_key(w, "user_mbox");   march_jw_i64(w, r->user_mbox);
    march_jw_key(w, "mbox_limit");  march_jw_i64(w, r->mbox_limit);
    march_jw_key(w, "mbox_policy"); march_jw_str(w, policy_name(r->mbox_policy));
    march_jw_key(w, "code_epoch");  march_jw_u64(w, r->code_epoch);
    march_jw_key(w, "cap_epoch");   march_jw_i64(w, r->cap_epoch);
    march_jw_key(w, "sched");
    if (r->sched >= 0) march_jw_i64(w, r->sched); else march_jw_null(w);
    march_jw_key(w, "pinned");      march_jw_bool(w, r->pinned);
    march_jw_key(w, "draining");    march_jw_bool(w, r->draining);
    march_jw_key(w, "parent");
    if (r->parent >= 0) march_jw_i64(w, r->parent); else march_jw_null(w);
    march_jw_key(w, "children");    march_jw_i64(w, r->num_children);
    march_jw_obj_end(w);
}

/* ── Argument parsing ─────────────────────────────────────────────────── */

/* Next whitespace-separated word of *p into out (NUL-terminated); 0 if none
 * or too long. */
static int next_word(const char **p, char *out, size_t cap) {
    const char *s = *p;
    while (*s == ' ' || *s == '\t') s++;
    if (!*s) { *p = s; return 0; }
    size_t n = 0;
    while (s[n] && s[n] != ' ' && s[n] != '\t') n++;
    if (n >= cap) return 0;
    memcpy(out, s, n);
    out[n] = '\0';
    *p = s + n;
    return 1;
}

/* A non-negative decimal integer, whole word. */
static int parse_i64(const char *s, int64_t *out) {
    if (!*s) return 0;
    int64_t v = 0;
    for (; *s; s++) {
        if (*s < '0' || *s > '9') return 0;
        if (v > (INT64_MAX - 9) / 10) return 0;
        v = v * 10 + (*s - '0');
    }
    *out = v;
    return 1;
}

static int only_spaces(const char *s) {
    while (*s == ' ' || *s == '\t') s++;
    return *s == '\0';
}

/* ── ACTORS ───────────────────────────────────────────────────────────── */

enum { SORT_MBOX, SORT_STATUS, SORT_EPOCH, SORT_PID };

static int cmp_pid(const march_obs_actor *a, const march_obs_actor *b) {
    return a->pid < b->pid ? -1 : a->pid > b->pid;
}
static int cmp_mbox(const void *x, const void *y) {
    const march_obs_actor *a = x, *b = y;
    if (a->mbox != b->mbox) return a->mbox > b->mbox ? -1 : 1;   /* deepest first */
    return cmp_pid(a, b);
}
/* Running, runnable, then waiting: busiest first. */
static int status_rank(int s) {
    switch (s) {
    case PROC_RUNNING:  return 0;
    case PROC_RUNNABLE: return 1;
    case PROC_DEAD:     return 3;
    case -1:            return 4;
    default:            return 2;
    }
}
static int cmp_status(const void *x, const void *y) {
    const march_obs_actor *a = x, *b = y;
    int ra = status_rank(a->status), rb = status_rank(b->status);
    if (ra != rb) return ra < rb ? -1 : 1;
    return cmp_mbox(x, y);
}
/* Oldest code epoch first: the actors holding a drain back. */
static int cmp_epoch(const void *x, const void *y) {
    const march_obs_actor *a = x, *b = y;
    if (a->code_epoch != b->code_epoch) return a->code_epoch < b->code_epoch ? -1 : 1;
    return cmp_pid(a, b);
}
static int cmp_pid_q(const void *x, const void *y) { return cmp_pid(x, y); }

static const char *sort_names[] = { "mbox", "status", "epoch", "pid" };

static void write_actors(march_jw *w, march_obs_actor *rows, size_t n,
                         int sort, int64_t limit) {
    int (*cmp)(const void *, const void *) =
        sort == SORT_STATUS ? cmp_status : sort == SORT_EPOCH ? cmp_epoch
      : sort == SORT_PID ? cmp_pid_q : cmp_mbox;
    qsort(rows, n, sizeof *rows, cmp);
    size_t shown = (size_t)limit < n ? (size_t)limit : n;
    march_jw_obj_begin(w);
    march_jw_key(w, "total"); march_jw_u64(w, n);
    march_jw_key(w, "shown"); march_jw_u64(w, shown);
    march_jw_key(w, "sort");  march_jw_str(w, sort_names[sort]);
    march_jw_key(w, "actors");
    march_jw_arr_begin(w);
    for (size_t i = 0; i < shown; i++) write_row(w, &rows[i]);
    march_jw_arr_end(w);
    march_jw_obj_end(w);
}

static const char *verb_actors(march_jw *w, const char *args) {
    int sort = SORT_MBOX, have_sort = 0, have_limit = 0;
    int64_t limit = ACTORS_DEFAULT_N;
    char word[32];
    const char *p = args;
    for (int i = 0; i < 2 && next_word(&p, word, sizeof word); i++) {
        int64_t v;
        if (parse_i64(word, &v)) {
            if (v < 1 || v > ACTORS_MAX_N || have_limit++) return "bad_args";
            limit = v;
        } else {
            int found = 0;
            for (int s = 0; s < 4; s++)
                if (strcmp(word, sort_names[s]) == 0) { sort = s; found = 1; }
            if (!found || have_sort++) return "bad_args";
        }
    }
    if (!only_spaces(p)) return "bad_args";   /* a third word, or an over-long one */
    march_obs_actor *rows; size_t n;
    if (march_obs_actors(&rows, &n) != 0) return "out_of_memory";
    write_actors(w, rows, n, sort, limit);
    march_obs_actors_free(rows, n);
    return NULL;
}

/* ── ACTOR <pid> ──────────────────────────────────────────────────────── */

typedef struct { int slot; int64_t pid; } child_slot;

static int cmp_child_slot(const void *x, const void *y) {
    const child_slot *a = x, *b = y;
    if (a->slot != b->slot) return a->slot < b->slot ? -1 : 1;
    return a->pid < b->pid ? -1 : a->pid > b->pid;
}

static const char *verb_actor(march_jw *w, const char *args) {
    char word[32];
    const char *p = args;
    int64_t pid;
    if (!next_word(&p, word, sizeof word) || !parse_i64(word, &pid) || !only_spaces(p))
        return "bad_args";
    march_obs_actor_extra ex;
    march_obs_actor_extra_get(pid, &ex);
    if (!ex.known) return "not_found";
    march_obs_actor *rows = NULL; size_t n = 0;
    if (march_obs_actors(&rows, &n) != 0) return "out_of_memory";
    const march_obs_actor *self = NULL;
    for (size_t i = 0; i < n; i++) if (rows[i].pid == pid) { self = &rows[i]; break; }

    march_jw_obj_begin(w);
    march_jw_key(w, "pid");   march_jw_i64(w, pid);
    /* "alive" from the walk: the tombstone can say live while the walk, a
     * moment later, no longer finds it.  The row is what is reported. */
    march_jw_key(w, "alive"); march_jw_bool(w, self != NULL);
    march_jw_key(w, "cap_epoch"); march_jw_i64(w, self ? self->cap_epoch : ex.cap_epoch);
    march_jw_key(w, "actor");
    if (self) write_row(w, self); else march_jw_null(w);
    march_jw_key(w, "children");
    march_jw_arr_begin(w);
    if (self) {
        /* Children in supervise-block order: one pass, then sort by slot. */
        child_slot *kids = (child_slot *)malloc((n ? n : 1) * sizeof *kids);
        size_t k = 0;
        if (kids) {
            for (size_t i = 0; i < n; i++)
                if (rows[i].parent == pid)
                    kids[k++] = (child_slot){ rows[i].child_index, rows[i].pid };
            qsort(kids, k, sizeof *kids, cmp_child_slot);
            for (size_t i = 0; i < k; i++) march_jw_i64(w, kids[i].pid);
            free(kids);
        }
    }
    march_jw_arr_end(w);
    march_jw_key(w, "supervisor");
    if (self && ex.supervisor) {
        march_jw_obj_begin(w);
        march_jw_key(w, "strategy");     march_jw_str(w, strategy_name(ex.strategy));
        march_jw_key(w, "max_restarts"); march_jw_i64(w, ex.max_restarts);
        march_jw_key(w, "window_secs");  march_jw_i64(w, ex.window_secs);
        march_jw_key(w, "restarts_held"); march_jw_i64(w, ex.n_restarts);
        march_jw_key(w, "restart_ages_ms");
        march_jw_arr_begin(w);
        int k = ex.n_restarts < 16 ? ex.n_restarts : 16;
        for (int i = 0; i < k; i++) march_jw_i64(w, ex.restart_age_ms[i]);
        march_jw_arr_end(w);
        march_jw_obj_end(w);
    } else {
        march_jw_null(w);
    }
    /* Death KIND only: never the crash message (C7). */
    march_jw_key(w, "terminal");
    if (!self && ex.terminal_set) {
        march_jw_obj_begin(w);
        march_jw_key(w, "kind"); march_jw_str(w, death_kind(ex.terminal_reason));
        march_jw_obj_end(w);
    } else {
        march_jw_null(w);
    }
    march_jw_obj_end(w);
    march_obs_actors_free(rows, n);
    return NULL;
}

/* ── TREE ─────────────────────────────────────────────────────────────── */

typedef struct {
    march_obs_actor *rows;
    size_t           n;
    size_t           emitted;
    int              truncated;
} tree_ctx;

static int cmp_parent_slot(const void *x, const void *y) {
    const march_obs_actor *a = x, *b = y;
    if (a->parent != b->parent) return a->parent < b->parent ? -1 : 1;
    if (a->child_index != b->child_index) return a->child_index < b->child_index ? -1 : 1;
    return cmp_pid(a, b);
}

/* First row whose parent is [pid] in rows sorted by cmp_parent_slot. */
static size_t first_child(const march_obs_actor *rows, size_t n, int64_t pid) {
    size_t lo = 0, hi = n;
    while (lo < hi) {
        size_t mid = lo + (hi - lo) / 2;
        if (rows[mid].parent < pid) lo = mid + 1; else hi = mid;
    }
    return lo;
}

static void tree_node(march_jw *w, tree_ctx *t, const march_obs_actor *r, int depth) {
    t->emitted++;
    march_jw_obj_begin(w);
    march_jw_key(w, "pid");    march_jw_i64(w, r->pid);
    march_jw_key(w, "type");   write_type(w, r);
    march_jw_key(w, "names");  write_names(w, r);
    march_jw_key(w, "status"); march_jw_str(w, status_name(r->status));
    march_jw_key(w, "mbox");   march_jw_i64(w, r->mbox);
    march_jw_key(w, "children");
    march_jw_arr_begin(w);
    for (size_t i = first_child(t->rows, t->n, r->pid);
         i < t->n && t->rows[i].parent == r->pid; i++) {
        if (depth + 1 >= TREE_MAX_DEPTH || t->emitted >= TREE_MAX_NODES) {
            t->truncated = 1;
            break;
        }
        tree_node(w, t, &t->rows[i], depth + 1);
    }
    march_jw_arr_end(w);
    march_jw_obj_end(w);
}

static int pid_present(const march_obs_actor *rows, size_t n, int64_t pid) {
    /* rows sorted by parent: scan (TREE is not a hot path; n is bounded). */
    for (size_t i = 0; i < n; i++) if (rows[i].pid == pid) return 1;
    return 0;
}

static void write_tree(march_jw *w, march_obs_actor *rows, size_t n) {
    qsort(rows, n, sizeof *rows, cmp_parent_slot);
    tree_ctx t = { rows, n, 0, 0 };
    /* Mark which pids have children present, and which rows are orphans
     * (their supervisor is mid-restart or gone: listed at top level). */
    int64_t max_pid = -1;
    for (size_t i = 0; i < n; i++) if (rows[i].pid > max_pid) max_pid = rows[i].pid;
    unsigned char *present = (unsigned char *)calloc((size_t)(max_pid + 2), 1);
    unsigned char *has_kids = (unsigned char *)calloc((size_t)(max_pid + 2), 1);
    if (present && has_kids) {
        for (size_t i = 0; i < n; i++) present[rows[i].pid] = 1;
        for (size_t i = 0; i < n; i++)
            if (rows[i].parent >= 0 && rows[i].parent <= max_pid)
                has_kids[rows[i].parent] = 1;
    }
    #define PRESENT(p)  (present ? ((p) >= 0 && (p) <= max_pid && present[p]) : pid_present(rows, n, p))
    #define HAS_KIDS(r) (has_kids ? has_kids[(r)->pid] : ((r)->num_children > 0))

    march_jw_obj_begin(w);
    march_jw_key(w, "total"); march_jw_u64(w, n);
    /* Roots: unsupervised actors that supervise something present, and
     * children whose supervisor is not in this snapshot (orphans). */
    march_jw_key(w, "roots");
    march_jw_arr_begin(w);
    for (size_t i = 0; i < n; i++) {
        const march_obs_actor *r = &rows[i];
        int root = (r->parent < 0 && HAS_KIDS(r)) || (r->parent >= 0 && !PRESENT(r->parent));
        if (!root) continue;
        if (t.emitted >= TREE_MAX_NODES) { t.truncated = 1; break; }
        tree_node(w, &t, r, 0);
    }
    march_jw_arr_end(w);
    /* The synthetic root: bare-spawned actors, neither supervised nor
     * supervising. */
    march_jw_key(w, "unsupervised");
    march_jw_arr_begin(w);
    for (size_t i = 0; i < n; i++) {
        const march_obs_actor *r = &rows[i];
        if (r->parent >= 0 || HAS_KIDS(r)) continue;
        if (t.emitted >= TREE_MAX_NODES) { t.truncated = 1; break; }
        t.emitted++;
        march_jw_i64(w, r->pid);
    }
    march_jw_arr_end(w);
    march_jw_key(w, "truncated"); march_jw_bool(w, t.truncated);
    march_jw_obj_end(w);
    #undef PRESENT
    #undef HAS_KIDS
    free(present);
    free(has_kids);
}

static const char *verb_tree(march_jw *w, const char *args) {
    if (!only_spaces(args)) return "bad_args";
    march_obs_actor *rows; size_t n;
    if (march_obs_actors(&rows, &n) != 0) return "out_of_memory";
    write_tree(w, rows, n);
    march_obs_actors_free(rows, n);
    return NULL;
}

/* ── NAMES ────────────────────────────────────────────────────────────── */

typedef struct { const char *name; int64_t pid; } name_pid;

static int cmp_name(const void *x, const void *y) {
    return strcmp(((const name_pid *)x)->name, ((const name_pid *)y)->name);
}

static int write_names_section(march_jw *w, const march_obs_actor *rows, size_t n) {
    size_t total = 0;
    for (size_t i = 0; i < n; i++) total += (size_t)rows[i].n_names;
    name_pid *v = (name_pid *)malloc((total ? total : 1) * sizeof *v);
    if (!v) return -1;
    size_t k = 0;
    for (size_t i = 0; i < n; i++)
        for (int j = 0; j < rows[i].n_names; j++)
            v[k++] = (name_pid){ rows[i].names[j], rows[i].pid };
    qsort(v, k, sizeof *v, cmp_name);
    march_jw_obj_begin(w);
    march_jw_key(w, "names");
    march_jw_arr_begin(w);
    for (size_t i = 0; i < k; i++) {
        march_jw_obj_begin(w);
        march_jw_key(w, "name"); march_jw_str(w, v[i].name);
        march_jw_key(w, "pid");  march_jw_i64(w, v[i].pid);
        march_jw_obj_end(w);
    }
    march_jw_arr_end(w);
    march_jw_obj_end(w);
    free(v);
    return 0;
}

static const char *verb_names(march_jw *w, const char *args) {
    if (!only_spaces(args)) return "bad_args";
    march_obs_actor *rows; size_t n;
    if (march_obs_actors(&rows, &n) != 0) return "out_of_memory";
    int rc = write_names_section(w, rows, n);
    march_obs_actors_free(rows, n);
    return rc ? "out_of_memory" : NULL;
}

/* ── SCHED ────────────────────────────────────────────────────────────── */

static void write_sched(march_jw *w) {
    int ns = march_sched_num_schedulers();
    march_jw_obj_begin(w);
    march_jw_key(w, "schedulers"); march_jw_i64(w, ns);
    march_jw_key(w, "threads");
    march_jw_arr_begin(w);
    /* Per-thread counters are plain fields owned by their scheduler thread:
     * a racy snapshot by design until R2 makes them atomics. */
    for (int i = 0; i < ns; i++) {
        march_jw_obj_begin(w);
        march_jw_key(w, "id");         march_jw_i64(w, i);
        march_jw_key(w, "started");    march_jw_bool(w, march_sched_thread_stat(i, MARCH_THREAD_STAT_STARTED) > 0);
        march_jw_key(w, "entered");    march_jw_bool(w, march_sched_thread_stat(i, MARCH_THREAD_STAT_ENTERED) > 0);
        march_jw_key(w, "dispatches"); march_jw_i64(w, march_sched_thread_stat(i, MARCH_THREAD_STAT_DISPATCHES));
        march_jw_key(w, "idle_polls"); march_jw_i64(w, march_sched_thread_stat(i, MARCH_THREAD_STAT_IDLE_POLLS));
        march_jw_obj_end(w);
    }
    march_jw_arr_end(w);
    march_jw_key(w, "live_procs");         march_jw_i64(w, march_sched_stat(0));
    march_jw_key(w, "procs_spawned");      march_jw_i64(w, march_sched_stat(1));
    march_jw_key(w, "runq");               march_jw_i64(w, march_sched_stat(2));
    march_jw_key(w, "stack_failures");     march_jw_i64(w, march_sched_stat(MARCH_STAT_STACK_FAIL));
    march_jw_key(w, "msgs_dropped");       march_jw_i64(w, march_sched_stat(MARCH_STAT_MSGS_DROPPED));
    march_jw_key(w, "stacks_recycled");    march_jw_i64(w, march_sched_stat(MARCH_STAT_STACKS_RECYCLED));
    march_jw_key(w, "timers");             march_jw_i64(w, march_sched_stat(6));
    march_jw_key(w, "ctx_released");       march_jw_i64(w, march_sched_stat(MARCH_STAT_CTX_RELEASED));
    march_jw_key(w, "procs_freed");        march_jw_i64(w, march_sched_stat(MARCH_STAT_PROCS_FREED));
    march_jw_key(w, "procs_awaiting_free"); march_jw_i64(w, march_sched_stat(9));
    march_jw_key(w, "metas_freed");        march_jw_i64(w, march_sched_stat(MARCH_STAT_METAS_FREED));
    march_jw_key(w, "metas_awaiting_free"); march_jw_i64(w, march_sched_stat(11));
    march_jw_obj_end(w);
}

static const char *verb_sched(march_jw *w, const char *args) {
    if (!only_spaces(args)) return "bad_args";
    write_sched(w);
    return NULL;
}

/* ── MEM ──────────────────────────────────────────────────────────────── */

/* Resident set size now, in bytes; -1 if the platform will not say. */
static int64_t rss_now_bytes(void) {
#if defined(__APPLE__)
    mach_task_basic_info_data_t info;
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
                  (task_info_t)&info, &count) != KERN_SUCCESS)
        return -1;
    return (int64_t)info.resident_size;
#elif defined(__linux__)
    FILE *f = fopen("/proc/self/statm", "r");
    if (!f) return -1;
    long long size = 0, resident = 0;
    int ok = fscanf(f, "%lld %lld", &size, &resident) == 2;
    fclose(f);
    return ok ? (int64_t)resident * (int64_t)sysconf(_SC_PAGESIZE) : -1;
#else
    return -1;
#endif
}

static void write_mem(march_jw *w, const march_obs_actor *rows, size_t n) {
    int64_t queued = 0;
    for (size_t i = 0; i < n; i++) queued += rows[i].mbox;
    int64_t rss = rss_now_bytes();
    march_jw_obj_begin(w);
    march_jw_key(w, "rss_bytes");
    if (rss >= 0) march_jw_i64(w, rss); else march_jw_null(w);
    march_jw_key(w, "peak_rss_bytes");   march_jw_i64(w, march_peak_rss_bytes());
    /* The unconditional live-object gauge (C13): heap cells allocated and
     * not yet freed. */
    march_jw_key(w, "live_objects");     march_jw_i64(w, march_live_allocs());
    march_jw_key(w, "stacks_recycled");  march_jw_i64(w, march_sched_stat(MARCH_STAT_STACKS_RECYCLED));
    march_jw_key(w, "queued_messages");  march_jw_i64(w, queued);
    march_jw_key(w, "actors");           march_jw_u64(w, n);
    march_jw_obj_end(w);
}

static const char *verb_mem(march_jw *w, const char *args) {
    if (!only_spaces(args)) return "bad_args";
    march_obs_actor *rows; size_t n;
    if (march_obs_actors(&rows, &n) != 0) return "out_of_memory";
    write_mem(w, rows, n);
    march_obs_actors_free(rows, n);
    return NULL;
}

/* ── EPOCHS ───────────────────────────────────────────────────────────── */

/* The same accessors the reload server's VERSIONS_DETAIL and PINS verbs
 * format as text (march_reload.c); those verbs are untouched. */
static void write_epochs(march_jw *w) {
    uint32_t cur = march_epoch_current();
    march_jw_obj_begin(w);
    march_jw_key(w, "current"); march_jw_u64(w, cur);
    march_jw_key(w, "pins");
    march_jw_arr_begin(w);
    uint32_t eps[MARCH_EPOCH_PIN_SLOTS]; int64_t cnt[MARCH_EPOCH_PIN_SLOTS];
    int k = march_epoch_pin_table(eps, cnt, MARCH_EPOCH_PIN_SLOTS);
    for (int i = 0; i < k; i++) {
        march_jw_obj_begin(w);
        march_jw_key(w, "epoch");    march_jw_u64(w, eps[i]);
        /* The current epoch's count includes its one role pin (as PINS). */
        march_jw_key(w, "pins");     march_jw_i64(w, eps[i] == cur ? cnt[i] - 1 : cnt[i]);
        march_jw_key(w, "current");  march_jw_bool(w, eps[i] == cur);
        march_jw_key(w, "draining"); march_jw_bool(w, march_hcr_epoch_draining(eps[i]));
        march_jw_obj_end(w);
    }
    march_jw_arr_end(w);
    march_jw_key(w, "slots");
    march_jw_arr_begin(w);
    for (uint32_t i = 1; i < 65536; i++) {   /* 1-based; slot 0 = sentinel */
        const char *name = march_dispatch_id_to_name(i);
        if (!name) break;
        uint32_t v = march_dispatch_current(i);
        const char *h = march_dispatch_impl_hash(i, v);
        const char *sig = march_dispatch_signer_hex(i);
        march_jw_obj_begin(w);
        march_jw_key(w, "id");    march_jw_u64(w, i);
        march_jw_key(w, "name");  march_jw_str(w, name);
        march_jw_key(w, "impl_hash");
        if (h && h[0]) march_jw_str(w, h); else march_jw_null(w);
        march_jw_key(w, "epoch"); march_jw_u64(w, march_dispatch_epoch(i, v));
        march_jw_key(w, "activated_at_ms"); march_jw_i64(w, march_dispatch_activated_at(i));
        march_jw_key(w, "signer");
        if (sig && sig[0]) march_jw_str(w, sig); else march_jw_null(w);
        march_jw_obj_end(w);
    }
    march_jw_arr_end(w);
    march_hcr_counters c; march_hcr_counters_get(&c);
    march_jw_key(w, "counters");
    march_jw_obj_begin(w);
    march_jw_key(w, "deferred");     march_jw_i64(w, c.deferred);
    march_jw_key(w, "converted");    march_jw_i64(w, c.converted);
    march_jw_key(w, "dropped");      march_jw_i64(w, c.dropped);
    march_jw_key(w, "killed");       march_jw_i64(w, c.killed);
    march_jw_key(w, "stopped");      march_jw_i64(w, c.stopped);
    march_jw_key(w, "advances");     march_jw_i64(w, c.advances);
    march_jw_key(w, "early");        march_jw_i64(w, c.early);
    march_jw_key(w, "forced");       march_jw_i64(w, c.forced);
    march_jw_key(w, "markers_live"); march_jw_i64(w, march_hcr_markers_live());
    march_jw_key(w, "markers_lost"); march_jw_i64(w, c.markers_lost);
    march_jw_obj_end(w);
    march_jw_obj_end(w);
}

static const char *verb_epochs(march_jw *w, const char *args) {
    if (!only_spaces(args)) return "bad_args";
    write_epochs(w);
    return NULL;
}

/* ── SNAPSHOT [sections] ──────────────────────────────────────────────── */

enum { SEC_ACTORS = 1, SEC_TREE = 2, SEC_NAMES = 4, SEC_SCHED = 8,
       SEC_MEM = 16, SEC_EPOCHS = 32, SEC_ALL = 63 };
static const struct { const char *name; int bit; } sections[] = {
    { "actors", SEC_ACTORS }, { "tree", SEC_TREE }, { "names", SEC_NAMES },
    { "sched", SEC_SCHED }, { "mem", SEC_MEM }, { "epochs", SEC_EPOCHS },
};
#define N_SECTIONS (sizeof sections / sizeof sections[0])

/* Sections as words or a comma list: "actors,mem" or "actors mem". */
static int parse_sections(const char *args, int *mask) {
    *mask = 0;
    const char *p = args;
    while (*p) {
        while (*p == ' ' || *p == '\t' || *p == ',') p++;
        if (!*p) break;
        size_t n = 0;
        while (p[n] && p[n] != ' ' && p[n] != '\t' && p[n] != ',') n++;
        int found = 0;
        for (size_t i = 0; i < N_SECTIONS; i++)
            if (strlen(sections[i].name) == n && strncmp(p, sections[i].name, n) == 0) {
                *mask |= sections[i].bit;
                found = 1;
            }
        if (!found) return -1;
        p += n;
    }
    if (*mask == 0) *mask = SEC_ALL;
    return 0;
}

static const char *verb_snapshot(march_jw *w, const char *args) {
    int mask;
    if (parse_sections(args, &mask) != 0) return "bad_args";
    march_obs_actor *rows = NULL; size_t n = 0;
    int need_rows = mask & (SEC_ACTORS | SEC_TREE | SEC_NAMES | SEC_MEM);
    /* ONE walk for every actor section, so they agree with each other. */
    if (need_rows && march_obs_actors(&rows, &n) != 0) return "out_of_memory";
    march_jw_obj_begin(w);
    if (mask & SEC_NAMES) {   /* before the sorts below reorder rows (harmless) */
        march_jw_key(w, "names");
        if (write_names_section(w, rows, n) != 0) march_jw_null(w);
    }
    if (mask & SEC_MEM)    { march_jw_key(w, "mem");    write_mem(w, rows, n); }
    if (mask & SEC_ACTORS) {
        march_jw_key(w, "actors");
        write_actors(w, rows, n, SORT_MBOX, ACTORS_DEFAULT_N);
    }
    if (mask & SEC_TREE)   { march_jw_key(w, "tree");   write_tree(w, rows, n); }
    if (mask & SEC_SCHED)  { march_jw_key(w, "sched");  write_sched(w); }
    if (mask & SEC_EPOCHS) { march_jw_key(w, "epochs"); write_epochs(w); }
    march_jw_obj_end(w);
    march_obs_actors_free(rows, n);
    return NULL;
}

/* ── Registration ─────────────────────────────────────────────────────── */

static const march_observe_verb snapshot_verbs[] = {
    { "SNAPSHOT", "observe", "[actors,tree,names,sched,mem,epochs]",
      "several sections from one actor walk (default: all)", verb_snapshot },
    { "ACTORS", "observe", "[mbox|status|epoch|pid] [n]",
      "live actors, sorted, at most n (default 100, max 10000)", verb_actors },
    { "ACTOR", "observe", "<pid>",
      "one actor: row, children, supervisor config, death kind", verb_actor },
    { "TREE", "observe", "", "the supervision tree and the unsupervised actors", verb_tree },
    { "NAMES", "observe", "", "registered names and their pids", verb_names },
    { "SCHED", "observe", "", "scheduler threads and global scheduler counters", verb_sched },
    { "MEM", "observe", "", "RSS, peak RSS, live heap objects, queued messages", verb_mem },
    { "EPOCHS", "observe", "", "hot-reload epochs, pins, slots and counters", verb_epochs },
};

void march_observe_snapshot_install(void) {
    static int done;
    if (done) return;
    done = 1;
    (void)march_observe_add_verbs(snapshot_verbs,
                                  sizeof snapshot_verbs / sizeof snapshot_verbs[0]);
}
