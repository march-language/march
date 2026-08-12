/* march_scheduler.c — M:N multi-thread green-thread scheduler with
 * work-stealing deques and mailbox message passing.
 *
 * Design
 * ──────
 * N OS threads each run a scheduler loop.  Each scheduler owns a Chase-Lev
 * work-stealing deque of RUNNABLE processes.  The owner pushes/pops from the
 * bottom (LIFO for cache locality).  Idle schedulers steal from others'
 * tops (FIFO for load balance).
 *
 * Scheduling policy: per-thread LIFO with work-stealing.
 *   1. Pop the next RUNNABLE process from the local deque.
 *   2. If empty, attempt to steal from a random other scheduler.
 *   3. If stolen or local: reset reduction budget, swapcontext into process.
 *   4. On return: if RUNNABLE, push back to local deque; if DEAD, leak-don't-free.
 *      If WAITING, leave parked — a sender will re-enqueue via wake.
 *   5. If all deques empty and g_live_procs == 0, set g_all_done and exit.
 *
 * Context switching
 * ─────────────────
 * ucontext_t / makecontext / swapcontext provide stackful coroutines.
 * Each process's ucontext points to its own mmap'd stack.  The trampoline
 * wraps the user function and calls march_sched_exit() on return.
 *
 * Each process stores an owner_sched pointer set by the scheduler before
 * swapcontext.  The trampoline uses this to return to the correct scheduler.
 */

/* _XOPEN_SOURCE must come before all system headers (see march_scheduler.h).
 * Also needed: _DARWIN_C_SOURCE on macOS to expose getpagesize without
 * relying on the deprecated extension path.
 * On Linux, _GNU_SOURCE exposes MAP_ANONYMOUS which _XOPEN_SOURCE=700 hides. */
#ifndef _XOPEN_SOURCE
#  define _XOPEN_SOURCE 700
#endif
#if defined(__APPLE__) && !defined(_DARWIN_C_SOURCE)
#  define _DARWIN_C_SOURCE
#endif
#if defined(__linux__) && !defined(_GNU_SOURCE)
#  define _GNU_SOURCE
#endif

#include "march_scheduler.h"
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>     /* nanosleep */
#include <unistd.h>   /* sysconf */

/* macOS spells it MAP_ANON; Linux spells it MAP_ANONYMOUS.  Both platforms
 * define MAP_ANON as well, so we only need the reverse fallback. */
#ifndef MAP_ANON
#  define MAP_ANON MAP_ANONYMOUS
#endif

/* Silence macOS deprecation warnings for ucontext functions (getcontext,
 * makecontext, swapcontext).  They are deprecated but still functional and
 * are the only portable way to implement stackful coroutines in C. */
#if defined(__APPLE__)
#  pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif

/* ASan is otherwise unaware that swapcontext() below hops between
 * independently-mmap'd stacks (the scheduler's own native stack and each
 * green thread's dedicated stack) — without telling it, it cannot correctly
 * track stack-use-after-return/stack-buffer-overflow across a switch, and
 * may misattribute or miss corruption entirely. Every swapcontext() call
 * site is paired with a _TO_PROC/_TO_SCHED before it and a _DONE after it,
 * except the three "never returns" call sites (proc_trampoline's normal
 * exit and march_sched_exit), which by design never resume this fiber. */
#ifdef MARCH_ASAN_BUILD
#  define MARCH_ASAN_SWITCH_TO_PROC(from_fiber, target_proc) \
      __sanitizer_start_switch_fiber(&(from_fiber)->asan_fake_stack, \
          (target_proc)->stack_mmap_base, (target_proc)->stack_alloc)
#  define MARCH_ASAN_SWITCH_TO_SCHED(from_fiber) \
      __sanitizer_start_switch_fiber(&(from_fiber)->asan_fake_stack, NULL, 0)
#  define MARCH_ASAN_SWITCH_DONE(fiber) \
      __sanitizer_finish_switch_fiber((fiber)->asan_fake_stack, NULL, NULL)
#else
#  define MARCH_ASAN_SWITCH_TO_PROC(from_fiber, target_proc) ((void)0)
#  define MARCH_ASAN_SWITCH_TO_SCHED(from_fiber) ((void)0)
#  define MARCH_ASAN_SWITCH_DONE(fiber) ((void)0)
#endif

/* TSan's fiber API is simpler than ASan's: one __tsan_switch_to_fiber call,
 * naming the fiber we are ABOUT to become, immediately before the actual
 * swapcontext() jump — no matching "done" call on the other side. Each
 * march_proc/march_scheduler owns a persistent fiber handle (created once,
 * at spawn / at the top of sched_loop respectively). */
#ifdef MARCH_TSAN_BUILD
#  define MARCH_TSAN_SWITCH_TO_PROC(target_proc) \
      __tsan_switch_to_fiber((target_proc)->tsan_fiber, 0)
#  define MARCH_TSAN_SWITCH_TO_SCHED(sched) \
      __tsan_switch_to_fiber((sched)->tsan_fiber, 0)
#else
#  define MARCH_TSAN_SWITCH_TO_PROC(target_proc) ((void)0)
#  define MARCH_TSAN_SWITCH_TO_SCHED(sched) ((void)0)
#endif

/* ── Global state ─────────────────────────────────────────────────────── */

static march_scheduler  g_scheds[MARCH_NUM_SCHEDULERS + 1];
static int              g_num_scheds = 0;
static _Atomic int64_t  g_next_pid   = 0;
static _Atomic int      g_all_done       = 0;
static _Atomic int64_t  g_live_procs     = 0;
static _Atomic int      g_sched_shutdown = 0;

/* Timer min-heap state (full definition + helpers near march_sched_wake,
 * below). Forward-declared here so march_sched_init can reset g_timer_len. */
typedef struct { int64_t deadline_ms; struct march_proc *proc; } march_timer_ent;
static pthread_mutex_t  g_timer_mu = PTHREAD_MUTEX_INITIALIZER;
static march_timer_ent *g_timer_heap = NULL;
static int              g_timer_len = 0, g_timer_cap = 0;

/* Live procs that are NOT daemons (main, task procs).  When this reaches 0
 * after shutdown is requested, only actor recv loops remain — the idle
 * branch of sched_loop then wakes parked daemons so they exit their loops
 * (recv returns MARCH_RECV_NO_MSG) and the scheduler can drain to 0. */
static _Atomic int64_t  g_live_nondaemon = 0;

/* Global run queue: the single cross-thread enqueue path, holding RUNNABLE
 * procs enqueued by a thread that is not the proc's local-deque owner.
 * Chase-Lev deques are single-owner for push/pop — only steal is a
 * sanctioned cross-thread operation — so EVERY cross-thread enqueue must
 * land here instead of in another thread's deque:
 *   - spawns from non-scheduler threads (e.g. the main OS thread), and
 *   - wakes (WAITING→RUNNABLE), which may execute on any thread.
 * Only same-thread enqueues (yield re-push, spawn from within a scheduler)
 * use the local deque.
 *
 * Implementation: a pthread_mutex-protected FIFO linked list
 * (march_proc::next is the intrusive link) — the same shape as Go's
 * sched.lock-protected global runq.  An earlier design reused the
 * pre-existing lock-free Treiber stack (then named g_ext_spawn_head), but
 * that stack is only MPMC-safe while each proc is pushed AT MOST ONCE (its
 * original external-spawn usage): once wakes re-push the same proc
 * repeatedly, the classic ABA race appears — a consumer that stalls between
 * reading `head` and CAS'ing it can find the same proc pointer re-pushed as
 * head with a DIFFERENT ->next, splice a stale node back in as the new
 * head, and thereby hand an already-RUNNING proc to a second scheduler
 * (the exact double-dispatch this queue exists to prevent).  A mutex FIFO
 * has no ABA hazard, gives FIFO wake fairness, and its critical sections
 * are a handful of instructions.
 *
 * g_runq_head is _Atomic solely so schedulers can PEEK emptiness without
 * taking the lock on every dispatch iteration; all mutations (including the
 * head store) happen under g_runq_mu. */
/* ── MARCH_DEBUG invariant tripwires ─────────────────────────────────── */
/* See the field docs in march_scheduler.h (march_proc.dbg_queued /
 * dbg_running_on).  All run-structure enqueues/dequeues and every dispatch
 * are funneled through these; a single-membership or single-dispatcher
 * violation aborts at the moment it happens instead of surfacing minutes
 * later as corrupted-stack garbage. */
#ifdef MARCH_DEBUG
static void dbg_mark_enqueued(march_proc *p, const char *site) {
    int prev = atomic_exchange_explicit(&p->dbg_queued, 1, memory_order_acq_rel);
    if (prev != 0) {
        fprintf(stderr,
                "march_sched[BUG]: double-enqueue of pid %lld at %s "
                "(status=%d, running_on=%d)\n",
                (long long)p->pid, site,
                (int)atomic_load_explicit(&p->status, memory_order_acquire),
                atomic_load_explicit(&p->dbg_running_on, memory_order_acquire));
        abort();
    }
}
static void dbg_mark_dequeued(march_proc *p, const char *site) {
    int prev = atomic_exchange_explicit(&p->dbg_queued, 0, memory_order_acq_rel);
    if (prev != 1) {
        fprintf(stderr,
                "march_sched[BUG]: dequeue of non-queued pid %lld at %s "
                "(status=%d, running_on=%d)\n",
                (long long)p->pid, site,
                (int)atomic_load_explicit(&p->status, memory_order_acquire),
                atomic_load_explicit(&p->dbg_running_on, memory_order_acquire));
        abort();
    }
}
static void dbg_mark_dispatched(march_proc *p, int sched_id) {
    int prev = atomic_exchange_explicit(&p->dbg_running_on, sched_id + 1,
                                        memory_order_acq_rel);
    if (prev != 0) {
        fprintf(stderr,
                "march_sched[BUG]: DOUBLE DISPATCH of pid %lld: scheduler %d "
                "claiming while already running on scheduler %d (status=%d)\n",
                (long long)p->pid, sched_id, prev - 1,
                (int)atomic_load_explicit(&p->status, memory_order_acquire));
        abort();
    }
}
static void dbg_mark_undispatched(march_proc *p) {
    atomic_store_explicit(&p->dbg_running_on, 0, memory_order_release);
}
#else
#  define dbg_mark_enqueued(p, site)     ((void)0)
#  define dbg_mark_dequeued(p, site)     ((void)0)
#  define dbg_mark_dispatched(p, sid)    ((void)0)
#  define dbg_mark_undispatched(p)       ((void)0)
#endif

static pthread_mutex_t       g_runq_mu   = PTHREAD_MUTEX_INITIALIZER;
static _Atomic(march_proc *) g_runq_head = NULL;
static march_proc           *g_runq_tail = NULL;

/* Instantaneous depth of the global run queue, exposed via march_sched_stat
 * index 2. Bumped alongside the push/pop above; both call sites already hold
 * g_runq_mu, but the counter is read unlocked by the stat reader so it uses
 * relaxed atomics rather than plain state. */
static _Atomic int64_t       g_runq_len  = 0;

static void global_runq_push(march_proc *p) {
    dbg_mark_enqueued(p, "global_runq_push");
    p->next = NULL;
    pthread_mutex_lock(&g_runq_mu);
    if (g_runq_tail) {
        g_runq_tail->next = p;
    } else {
        atomic_store_explicit(&g_runq_head, p, memory_order_release);
    }
    g_runq_tail = p;
    pthread_mutex_unlock(&g_runq_mu);
    atomic_fetch_add_explicit(&g_runq_len, 1, memory_order_relaxed);
}

static march_proc *global_runq_pop(void) {
    /* Lock-free fast path: empty queue (the common case on a busy scheduler).
     * A racing push that this stale load misses is picked up on the next
     * dispatch iteration — never lost (shutdown requires g_live_procs == 0,
     * and a queued proc still counts as live). */
    if (atomic_load_explicit(&g_runq_head, memory_order_acquire) == NULL)
        return NULL;
    pthread_mutex_lock(&g_runq_mu);
    march_proc *p = atomic_load_explicit(&g_runq_head, memory_order_relaxed);
    if (p) {
        atomic_store_explicit(&g_runq_head, p->next, memory_order_release);
        if (p->next == NULL) g_runq_tail = NULL;
        p->next = NULL;
    }
    pthread_mutex_unlock(&g_runq_mu);
    if (p) {
        dbg_mark_dequeued(p, "global_runq_pop");
        atomic_fetch_sub_explicit(&g_runq_len, 1, memory_order_relaxed);
    }
    return p;
}

/* Cross-file stat counters (indices 3-5 bumped from march_runtime.c /
 * later scheduler features). Exposed raw so new counters don't need new
 * symbols. See MARCH_STAT_* in march_scheduler.h. */
_Atomic int64_t march_stat_counters[8];

int64_t march_sched_stat(int64_t which) {
    switch (which) {
    case 0: return atomic_load_explicit(&g_live_procs, memory_order_relaxed);
    case 1: return atomic_load_explicit(&g_next_pid,   memory_order_relaxed);
    case 2: return atomic_load_explicit(&g_runq_len,   memory_order_relaxed);
    case 3: case 4: case 5:
        return atomic_load_explicit(&march_stat_counters[which],
                                    memory_order_relaxed);
    case 6: {
        pthread_mutex_lock(&g_timer_mu);
        int64_t n = g_timer_len;
        pthread_mutex_unlock(&g_timer_mu);
        return n;
    }
    default: return 0;
    }
}

static _Thread_local march_scheduler *tl_sched = NULL;

/* Definition of the sentinel exported via march_scheduler.h. */
int march_recv_no_msg_sentinel;

/* Cached OS page size — initialised once in march_sched_init().
 * Used by the SIGSEGV handler (sysconf is not async-signal-safe). */
static size_t g_page_size = 0;

/* ── Process registry (for march_sched_find) ──────────────────────────── */

#define MARCH_MAX_PROCS 65536

static march_proc *g_proc_registry[MARCH_MAX_PROCS];
static int64_t     g_proc_count = 0;

/* Guards registry slots against the walk-vs-free race: sched_loop removes a
 * DEAD proc from the registry (under this mutex) strictly BEFORE freeing it,
 * so a walker holding the mutex either sees the slot populated with a
 * not-yet-freed proc or sees NULL — never a dangling pointer.  Walkers:
 * march_sched_wait_idle and wake_idle_daemons. */
static pthread_mutex_t g_registry_mu = PTHREAD_MUTEX_INITIALIZER;

static void registry_add(march_proc *p) {
    pthread_mutex_lock(&g_registry_mu);
    if (p->pid < MARCH_MAX_PROCS) {
        g_proc_registry[p->pid] = p;
    }
    g_proc_count++;
    pthread_mutex_unlock(&g_registry_mu);
}

static void registry_remove(march_proc *p) {
    pthread_mutex_lock(&g_registry_mu);
    if (p->pid < MARCH_MAX_PROCS) {
        g_proc_registry[p->pid] = NULL;
    }
    g_proc_count--;
    pthread_mutex_unlock(&g_registry_mu);
}

/* ── Stack allocation helpers (Phase 4: lazy virtual-memory growth) ───── */

/*
 * Layout of the full mmap reservation (total = MARCH_STACK_MAX + page):
 *
 *   [mmap_base,              mmap_base + page)           PROT_NONE  — permanent guard
 *   [mmap_base + page,       mmap_base + MARCH_STACK_MAX) PROT_NONE  — reserved, grows down
 *   [mmap_base + MARCH_STACK_MAX, mmap_base + total)      PROT_R|W   — initial usable (4 KiB)
 *
 * stack_base   = mmap_base + MARCH_STACK_MAX  (initial bottom of usable region; decreases on growth)
 * stack_top    = mmap_base + total            (initial SP; never changes)
 *
 * On each guard-page fault the signal handler calls mprotect to extend the
 * usable region downward and updates p->stack_base.  The faulting instruction
 * is automatically retried by the CPU when the handler returns.
 *
 * Returns the initial stack_base (ss_sp for makecontext), or NULL on failure.
 * Sets *alloc_size to the total reservation size and *mmap_base_out to the
 * base of the mmap (for munmap on process death).
 */
static void *stack_alloc_lazy(size_t *alloc_size, void **mmap_base_out) {
    size_t page  = g_page_size;
    size_t total = MARCH_STACK_MAX + page;   /* guard page + max usable */

    /* Reserve the full range as PROT_NONE. */
    void *mem = mmap(NULL, total, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (mem == MAP_FAILED) return NULL;

    /* Make the top MARCH_STACK_INITIAL bytes read/write — the initial usable stack. */
    void *usable_start = (char *)mem + MARCH_STACK_MAX;   /* = mem + total - page */
    if (mprotect(usable_start, MARCH_STACK_INITIAL, PROT_READ | PROT_WRITE) != 0) {
        munmap(mem, total);
        return NULL;
    }

    *alloc_size    = total;
    *mmap_base_out = mem;
    return usable_start;   /* initial stack_base (bottom of usable region) */
}

/* ── Stack free-list (Task 12: recycle reservations on proc death) ─────
 *
 * Every dead proc used to leak its ~1MiB+guard mmap reservation forever
 * (see the "Deliberately NOT munmap ... / free(p)" comment on the PROC_DEAD
 * reap branch below for why the march_proc STRUCT still must leak). The
 * STACK mapping does not share that constraint: nothing outside the dead
 * proc's own execution ever dereferences its stack memory.
 *
 * Safety argument (also referenced from the PROC_DEAD reap branch):
 * after sched_loop observes PROC_DEAD for a reaped proc, that proc's stack
 * can never be touched again. The proc never runs again — PROC_DEAD is
 * terminal, and the dispatch CAS's DEAD→RUNNING exception applies only to
 * march_task_cancel_by_id's pre-completion store, which cannot occur after
 * the trampoline's own DEAD store because the proc has already exited by
 * then. Stale cross-thread readers of a leaked march_proc (march_actor_meta
 * .green_thread etc.) only ever touch p->status / p->pid / mailbox fields —
 * never the stack pointers or the mapped memory itself. The SIGSEGV handler
 * reads `s->current->stack_*` — only for the RUNNING proc on the handling
 * thread, so it can never observe a proc whose stack was just retired (a
 * proc must be RUNNING to fault on its own stack, and RUNNING procs are not
 * reaped). The MARCH_DEBUG fatal walker reads `q->stack_mmap_base` with no
 * lock; we NULL it before returning the mapping to the free-list, and the
 * walker already skips NULL entries (`if (!q || !q->stack_mmap_base)
 * continue;`), so a walker racing the retire either sees the old mapping
 * (still valid — mprotect/madvise below don't run until the pointer has
 * been claimed by a new spawn) or sees NULL and skips it.
 *
 * Reservations are uniform (MARCH_STACK_MAX + one guard page), so a plain
 * LIFO free-list suffices — no need to track per-entry sizes. Nodes are a
 * small malloc'd struct (one alloc per churn event, not per message), kept
 * deliberately separate from the mmap'd stack memory itself so we never
 * need to make any part of a PROT_NONE-by-default reservation temporarily
 * readable just to link it into a list. */
typedef struct stack_free_node {
    void *mmap_base;
    struct stack_free_node *next;
} stack_free_node;
static pthread_mutex_t  g_stack_free_mu = PTHREAD_MUTEX_INITIALIZER;
static stack_free_node *g_stack_free = NULL;

/* Pop a reservation off the free-list and re-arm it to the initial state
 * (guard page + PROT_NONE growable body + top MARCH_STACK_INITIAL
 * committed), exactly as stack_alloc_lazy would hand out a fresh one.
 * Returns NULL if the free-list is empty (caller falls back to a fresh
 * mmap via stack_alloc_lazy) or if re-arming fails (rare; we then munmap
 * the bad reservation outright rather than leave it half-configured on
 * the free-list). */
static void *stack_reuse(size_t *alloc_size, void **mmap_base_out) {
    pthread_mutex_lock(&g_stack_free_mu);
    stack_free_node *n = g_stack_free;
    if (n) g_stack_free = n->next;
    pthread_mutex_unlock(&g_stack_free_mu);
    if (!n) return NULL;

    void *mem = n->mmap_base;
    free(n);

    size_t page  = g_page_size;
    size_t total = MARCH_STACK_MAX + page;
    /* Re-protect the whole range PROT_NONE, then re-commit the top
     * MARCH_STACK_INITIAL window — mirrors stack_alloc_lazy's fresh-mmap
     * layout exactly, so nothing downstream can tell a recycled stack from
     * a new one. */
    if (mprotect(mem, total, PROT_NONE) != 0
            || mprotect((char *)mem + MARCH_STACK_MAX, MARCH_STACK_INITIAL,
                        PROT_READ | PROT_WRITE) != 0) {
        munmap(mem, total);
        return NULL;                      /* fall back to a fresh mmap */
    }
#ifdef MADV_FREE
    /* Advise the kernel it may reclaim the physical pages backing the
     * previous occupant's (now PROT_NONE) stack body immediately, rather
     * than waiting for memory pressure — the whole point of recycling is
     * to keep resident memory bounded under churn, not just VMA count. */
    madvise((char *)mem + page, MARCH_STACK_MAX - page, MADV_FREE);
#endif
    *alloc_size    = total;
    *mmap_base_out = mem;
    return (char *)mem + MARCH_STACK_MAX;
}

/* Return a dead proc's stack reservation to the free-list for reuse by a
 * future spawn. Never called under MARCH_ASAN_BUILD — see the call site. */
static void stack_retire(void *mmap_base) {
    stack_free_node *n = (stack_free_node *)malloc(sizeof *n);
    if (!n) {
        /* Can't record it on the free-list; don't leak the mapping either. */
        munmap(mmap_base, MARCH_STACK_MAX + g_page_size);
        return;
    }
    n->mmap_base = mmap_base;
    pthread_mutex_lock(&g_stack_free_mu);
    n->next = g_stack_free;
    g_stack_free = n;
    pthread_mutex_unlock(&g_stack_free_mu);
}

/* ── SIGSEGV handler for lazy stack growth ───────────────────────────── */

/*
 * Per-thread alternate signal stack.  Each scheduler OS-thread allocates one
 * in sched_loop() before running any green threads.  The SA_ONSTACK flag
 * directs SIGSEGV delivery here, which is necessary because the green
 * thread's own stack may be exhausted when the fault fires.
 */
#define MARCH_SIGALTSTACK_SIZE  (64 * 1024)   /* 64 KiB — plenty for the handler */

/* ASAN installs its own mmap'd alternate signal stack on every thread and, at
 * thread exit, AsanThread::Destroy → UnsetAlternateSignalStack blindly
 * munmap()s whatever altstack is then current.  If we replace it with our
 * malloc'd (non-page-aligned) buffer, that munmap fails with EINVAL and ASAN
 * aborts the process (SIGTRAP, exit 133) — after correct output, at teardown.
 * Under ASAN we therefore keep ASAN's altstack: it is SA_ONSTACK-capable and
 * large enough for the stack-growth handler, so lazy growth still works. */
#if defined(__has_feature)
#  if __has_feature(address_sanitizer)
#    define MARCH_ASAN 1
#  endif
#endif
#if !defined(MARCH_ASAN) && defined(__SANITIZE_ADDRESS__)
#  define MARCH_ASAN 1
#endif

static _Thread_local char *tl_alt_stack = NULL;

static void setup_alt_stack(void) {
#ifdef MARCH_ASAN
    return;   /* use ASAN's per-thread altstack; ours would break its teardown */
#else
    if (tl_alt_stack) return;   /* already set up for this thread */
    char *alt = (char *)malloc(MARCH_SIGALTSTACK_SIZE);
    if (!alt) { fputs("march_sched: OOM (sigaltstack)\n", stderr); abort(); }
    stack_t ss;
    ss.ss_sp    = alt;
    ss.ss_size  = MARCH_SIGALTSTACK_SIZE;
    ss.ss_flags = 0;
    if (sigaltstack(&ss, NULL) != 0) {
        perror("march_sched: sigaltstack");
        /* Non-fatal: stack growth will crash instead of growing, but the
         * scheduler itself still works for shallow stacks. */
    }
    tl_alt_stack = alt;
#endif
}

/*
 * SIGSEGV handler.  Called when a green thread touches a PROT_NONE page.
 *
 * If the fault address is in the growable region of the currently running
 * process's stack reservation, we extend the accessible window with mprotect
 * and return — the CPU retries the faulting instruction and succeeds.
 *
 * If the fault is outside any known stack reservation (a real bad pointer), we
 * terminate the process at the `fatal:` label below with _exit(128 + signo)
 * (see the long comment there for why re-raising the signal is unsafe from a
 * green-thread altstack context).
 */
static void march_sigsegv_handler(int sig, siginfo_t *info, void *uctx) {
    (void)uctx;

    /* A lazy-stack-growth fault lands on a PROT_NONE guard page inside a
     * green thread's reserved-but-not-yet-committed stack region.  How the
     * kernel classifies that access is NOT portable, so we must NOT gate on
     * si_code — the address-range check below is the real (and exact) safety
     * gate:
     *
     *   - Bare-metal / faithful-KVM Linux: SIGSEGV, si_code SEGV_ACCERR
     *     (the page exists but is PROT_NONE — an access-permission fault).
     *   - Virtualized / emulated x86-64 (qemu-user, and some hypervisor VM
     *     configurations — including CI runners): SIGSEGV, si_code
     *     SEGV_MAPERR ("address not mapped").  Verified: on this exact code an
     *     emulated x86-64 guest reports MAPERR for a PROT_NONE access while a
     *     native aarch64 host reports ACCERR for the identical mmap+access.
     *   - macOS: the Mach exception EXC_BAD_ACCESS / KERN_PROTECTION_FAILURE
     *     is translated to SIGBUS (not SIGSEGV), with a BUS_* si_code.
     *
     * The old `SIGSEGV && si_code != SEGV_ACCERR` gate handled only the first
     * case, so a stack that grew past its initial 4 KiB died with an
     * unhandled fault on any MAPERR-reporting Linux — flaky (whether a given
     * run recurses deep enough to grow the stack is timing/data-dependent, and
     * concurrent scheduling perturbs it) and Linux-only (macOS SIGBUS was
     * already accepted unconditionally).  That asymmetry — "passes on macOS,
     * intermittently SIGSEGVs on Linux" under stack-heavy parallel/distributed
     * workloads (List.pmap, msgpack RPC) — is exactly this bug.
     *
     * Fix: classify a stack-growth fault purely by the address-range check
     * below, for SIGSEGV and SIGBUS alike.  A genuine wild-pointer fault has an
     * address outside every proc's growable region and still `goto fatal`s; a
     * fault whose address is in range but whose backing mmap is somehow gone
     * makes the mprotect fail and also `goto fatal`s.  No si_code gate needed. */

    {
        size_t page       = g_page_size;
        char  *fault_addr = (char *)info->si_addr;

        /* Identify the running process on this scheduler thread. */
        march_scheduler *s = tl_sched;
        if (!s || !s->current) goto fatal;

        march_proc *p        = s->current;
        char       *mmap_base = (char *)p->stack_mmap_base;
        /* Growable region: above the permanent guard page, below current usable bottom. */
        char       *grow_lo  = mmap_base + page;          /* first growable address */
        char       *grow_hi  = (char *)p->stack_base;     /* current usable bottom  */

        if (fault_addr < grow_lo || fault_addr >= grow_hi) goto fatal;

        /* Align fault address down to a page boundary and extend from there
         * up to the current usable bottom in one mprotect call.  This covers
         * large stack frames (e.g. a 8 KiB local array) in a single fault. */
        char  *new_bottom = (char *)((uintptr_t)fault_addr & ~(page - 1));
        size_t grow_size  = (size_t)(grow_hi - new_bottom);

        if (mprotect(new_bottom, grow_size, PROT_READ | PROT_WRITE) != 0) goto fatal;

        /* Record the new usable bottom so future faults are classified correctly. */
        p->stack_base = new_bottom;
        return;   /* CPU retries faulting instruction */
    }

fatal:
#ifdef MARCH_DEBUG
    /* Debug-build fatal-fault triage: report where the fault landed relative
     * to every known green-thread stack, plus each involved proc's state.
     * fprintf is not async-signal-safe, but this is a crashing debug build —
     * the diagnostic value outweighs the formal UB. */
    {
        march_scheduler *s = tl_sched;
#if defined(__APPLE__) && defined(__aarch64__)
        if (uctx) {
            ucontext_t *uc = (ucontext_t *)uctx;
            extern intptr_t _dyld_get_image_vmaddr_slide(uint32_t);
            fprintf(stderr,
                    "march_sched[DBG-FATAL]: pc=%p lr=%p sp=%p fp=%p slide=0x%lx\n",
                    (void *)(uintptr_t)uc->uc_mcontext->__ss.__pc,
                    (void *)(uintptr_t)uc->uc_mcontext->__ss.__lr,
                    (void *)(uintptr_t)uc->uc_mcontext->__ss.__sp,
                    (void *)(uintptr_t)uc->uc_mcontext->__ss.__fp,
                    (unsigned long)_dyld_get_image_vmaddr_slide(0));
        }
#endif
        fprintf(stderr,
                "march_sched[DBG-FATAL]: sig=%d si_code=%d si_addr=%p sched=%d "
                "cur_pid=%lld cur_status=%d\n",
                sig, info->si_code, (void *)info->si_addr, s ? s->id : -1,
                (s && s->current) ? (long long)s->current->pid : (long long)-1,
                (s && s->current)
                    ? (int)atomic_load_explicit(&s->current->status, memory_order_acquire)
                    : -1);
        int64_t hi_pid = atomic_load_explicit(&g_next_pid, memory_order_acquire);
        if (hi_pid > MARCH_MAX_PROCS) hi_pid = MARCH_MAX_PROCS;
        for (int64_t i = 0; i < hi_pid; i++) {
            march_proc *q = g_proc_registry[i];
            if (!q || !q->stack_mmap_base) continue;
            char *lo = (char *)q->stack_mmap_base;
            char *hi = lo + q->stack_alloc;
            if ((char *)info->si_addr >= lo && (char *)info->si_addr < hi) {
                fprintf(stderr,
                        "  fault inside stack of pid %lld (status=%d "
                        "running_on=%d queued=%d mmap_base=%p usable_bottom=%p)\n",
                        (long long)q->pid,
                        (int)atomic_load_explicit(&q->status, memory_order_acquire),
                        atomic_load_explicit(&q->dbg_running_on, memory_order_acquire),
                        atomic_load_explicit(&q->dbg_queued, memory_order_acquire),
                        (void *)lo, (void *)q->stack_base);
            }
        }
        /* NOT abort(): abort() raises SIGABRT, whose default action wedges
         * the same way the fatal signal itself does over this alt-stack +
         * green-thread-ucontext state (see the non-debug path below).  Use
         * the same un-wedge-able _exit primitive so a MARCH_DEBUG crash also
         * always terminates. */
        _exit(128 + sig);
    }
#endif
    /* Not a stack-growth fault — terminate the process, un-wedge-ably.
     *
     * We deliberately do NOT re-raise the signal.  The obvious "reset to
     * SIG_DFL and raise(sig)" (or abort()) does NOT reliably kill here: the
     * interrupted context is a green thread's ucontext (swapcontext'd stack)
     * and this handler ran on the per-thread alternate signal stack, so the
     * kernel's default terminate-by-signal action — which walks the thread
     * state to generate a Mach exception / core dump — wedges the thread in
     * an UNINTERRUPTIBLE in-kernel wait (macOS `ps` state `UE`): pinned at
     * the faulting instruction, immune even to SIGKILL, unreapable without a
     * reboot.  Verified 2026-07-10 on the sort-RC-underflow family (a garbage
     * pointer reaching march_incrc from a lambda apply): the handler ran
     * (its diagnostic printed), then raise()/abort()/pthread_kill(self)
     * every one hung the process forever instead of killing it.  Because the
     * re-raise blocks in-kernel, any code AFTER it (an _exit backstop) never
     * runs — so the re-raise must be dropped entirely.
     *
     * _exit(2) is the only primitive that always works from here: a single
     * syscall that cannot fault, block, recurse, or be masked.  We exit with
     * the conventional 128+signo status (139 for SIGSEGV, 138 for SIGBUS),
     * exactly the code a shell reports for a signal death, so `$?`-based
     * callers still see "crashed."  The one thing lost vs a true signal death
     * is WIFSIGNALED / a core dump — an acceptable trade for a fault path
     * that must never hang.  The oracle sweep's is_divergence treats a
     * 128+fatal-signo exit as a crash divergence to match. */
    _exit(128 + sig);
}

static _Atomic int g_sigsegv_installed = 0;

static void install_stack_growth_handler(void) {
    int expected = 0;
    if (!atomic_compare_exchange_strong_explicit(
            &g_sigsegv_installed, &expected, 1,
            memory_order_acquire, memory_order_relaxed))
        return;   /* already installed */

    struct sigaction sa;
    sa.sa_sigaction = march_sigsegv_handler;
    sigemptyset(&sa.sa_mask);
    /* SA_SIGINFO: give us siginfo_t with si_addr.
     * SA_ONSTACK: run on the alt stack (green-thread stack may be full). */
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
    if (sigaction(SIGSEGV, &sa, NULL) != 0) {
        perror("march_sched: sigaction(SIGSEGV)");
    }
    /* macOS reports PROT_NONE guard-page hits as SIGBUS, not SIGSEGV, so the
     * lazy-stack-growth handler must cover SIGBUS as well or green stacks can
     * never grow past their initial size on Darwin. */
    if (sigaction(SIGBUS, &sa, NULL) != 0) {
        perror("march_sched: sigaction(SIGBUS)");
    }
}

/* ── Mailbox spinlock ────────────────────────────────────────────────── */

static inline void mbox_lock_acquire(march_proc *p) {
    int exp = 0;
    while (!atomic_compare_exchange_weak_explicit(
               &p->mbox_lock, &exp, 1,
               memory_order_acquire, memory_order_relaxed)) {
        exp = 0;
    }
}

static inline void mbox_lock_release(march_proc *p) {
    atomic_store_explicit(&p->mbox_lock, 0, memory_order_release);
}

/* ── Mailbox helpers (FIFO) ──────────────────────────────────────────── */

static march_mbox_node *mbox_node_new(void *msg) {
    march_mbox_node *node = malloc(sizeof(march_mbox_node));
    if (!node) { fputs("march_sched: OOM (mbox node)\n", stderr); abort(); }
    node->msg = msg;
    node->next = NULL;
    return node;
}

static void mbox_push_node(march_proc *p, march_mbox_node *node) {
    if (p->mbox_tail) {
        p->mbox_tail->next = node;
    } else {
        p->mailbox = node;
    }
    p->mbox_tail = node;
    atomic_fetch_add_explicit(&p->mbox_count, 1, memory_order_relaxed);
}

static void *mbox_pop(march_proc *p) {
    march_mbox_node *node = p->mailbox;
    if (!node) return NULL;
    void *msg = node->msg;
    p->mailbox = node->next;
    if (!p->mailbox) p->mbox_tail = NULL;
    atomic_fetch_sub_explicit(&p->mbox_count, 1, memory_order_relaxed);
    free(node);
    return msg;
}

/* ── Task 8: MARCH_MBOX_BLOCK sender-parking helpers ────────────────────
 *
 * Called by every receive-side call site (march_sched_recv,
 * march_sched_try_recv, march_sched_try_recv2, march_sched_recv_until)
 * immediately after a successful mbox_pop, and by sched_loop's PROC_DEAD
 * reap branch -- in ALL cases while STILL HOLDING p's own mbox_lock, and
 * NOT releasing it until this function returns. If that pop (or death)
 * crossed the BLOCK policy's low-water mark (depth <= limit/2, or the
 * proc died), unlinks the waiter list from p->mbox_send_waiters and wakes
 * every entry, ENTIRELY under the lock.
 *
 * Wake-ALL, not wake-one: every woken waiter re-enters march_sched_send's
 * retry loop and re-checks capacity there, re-parking if the mailbox
 * filled back up before it got scheduled. The resulting thundering herd is
 * bounded by the waiter count, which is simpler than a single-handoff
 * protocol (design locked in the task-8 brief).
 *
 * CORRECTNESS-CRITICAL: waking under the lock, not after releasing it.
 * An earlier version of this code detached the list under the lock but
 * called march_sched_wake on each entry AFTER releasing it, to avoid
 * holding mbox_lock across march_sched_wake's PROC_PARKED spin (a
 * liveness/performance concern, not a correctness one -- see the old
 * comment this replaced). That left a real, deterministic-once-triggered
 * race: a waiter can be woken by a source that has NOTHING to do with
 * this drain -- another sender targeting IT directly, a stale timer, a
 * supervised-death wake -- while it is still sitting in the JUST-DETACHED
 * (no longer reachable from p->mbox_send_waiters, but not yet fully
 * walked) local list. That waiter resumes, finds itself no longer
 * discoverable via ANY target's live mbox_send_waiters (this function
 * already NULLed p->mbox_send_waiters before any of this), concludes
 * (correctly, per mbox_unlink_send_waiter's contract) that it has nothing
 * to unlink, and retries -- possibly re-registering on a mailbox (this
 * one or a different one) and WRITING its own send_wait_next field at the
 * exact moment THIS function's traversal was still READING that same
 * field (`next = w->send_wait_next`) to find where to continue -- an
 * unsynchronized read/write race on send_wait_next that can sever the
 * remainder of the chain (orphaning every waiter after the raced-on node,
 * a silent lost wakeup) or hand back garbage.
 *
 * Doing the ENTIRE walk (read next, wake) under p's mbox_lock removes the
 * window: every node on this chain either (a) is genuinely PARKED/WAITING
 * and cannot touch its own send_wait_next until march_sched_wake actually
 * resumes it -- which THIS loop hasn't called yet for that node -- or (b)
 * is a proc trying to REGISTER on some mailbox, which requires acquiring
 * THAT mailbox's mbox_lock first. If the mailbox it wants to register on
 * is `p` itself, that acquire blocks until this function returns (we hold
 * p's lock the whole time). If it's registering on a DIFFERENT proc's
 * mailbox, that requires the OTHER proc's mbox_lock, which doesn't
 * synchronize with this one directly -- but a proc can only be READING or
 * WRITING send_wait_next while attempting to join/leave exactly ONE list
 * at a time, and mbox_unlink_send_waiter (called right after every park
 * returns, before any re-registration attempt) always tries to remove
 * itself from its PREVIOUS target first; since that previous target here
 * is `p`, and `p`'s lock is held for this whole function, that unlink
 * cannot proceed until we release it -- so the re-registration write
 * cannot happen until after this loop has moved past that node. This
 * cannot deadlock: march_sched_wake's own PROC_PARKED spin synchronizes
 * on the TARGET's status/wake_pending, not on p's mbox_lock, so it always
 * makes progress independent of whether we hold p's lock. The cost is
 * pure serialization -- other senders trying to register on p, or other
 * receive-side pops on p, wait for this loop to finish -- bounded by the
 * waiter count, same bound the wake-all design already accepts. */
static void mbox_wake_send_waiters_if_low(march_proc *p) {
    if (!p->mbox_send_waiters
            || !(p->mbox_limit == 0
                 || march_sched_mbox_count(p) <= p->mbox_limit / 2))
        return;
    march_proc *w = p->mbox_send_waiters;
    p->mbox_send_waiters = NULL;
    while (w) {
        march_proc *next = w->send_wait_next;
        w->send_wait_next = NULL;
        march_sched_wake(w);
        w = next;
    }
}

/* Remove `self` from `target->mbox_send_waiters` if it is still linked
 * there. MUST be called under target's mbox_lock (acquired by the
 * caller); does not itself acquire or release it. Called by
 * mbox_block_register_and_park immediately after march_sched_park_self
 * returns, UNCONDITIONALLY, before any retry/re-registration.
 *
 * self will usually already be absent: the common case is a normal
 * drain-triggered wake, and mbox_wake_send_waiters_if_low above already
 * fully unlinked (and NULLed the link field of) every waiter it woke,
 * entirely under this same lock, before ever calling march_sched_wake --
 * so by the time a normally-woken self resumes and gets here, there is
 * nothing left to do, and that is treated as success (a target that died
 * while we were parked -- see the PROC_DEAD reap branch in sched_loop --
 * also already ran this exact drain-and-wake, so it's the same case).
 *
 * self will be FOUND here only when park_self returned for a reason OTHER
 * than this target's own drain -- a spurious wake: another sender
 * targeting self directly, a stale march_sched_recv_until timer entry
 * firing late, or a supervised actor-death wake -- while self was still
 * genuinely linked in target->mbox_send_waiters, never drained. Without
 * this unconditional unlink, retrying while still linked would
 * re-register self ON TOP of its own still-present entry
 * (self->send_wait_next = target->mbox_send_waiters, which already
 * equals self or points through self), corrupting the chain into a
 * self-loop or an orphaned tail -- deterministic on the very first
 * spurious wake while linked, no race required to trigger it (distinct
 * from, and in addition to, the race mbox_wake_send_waiters_if_low's
 * comment above addresses). */
static void mbox_unlink_send_waiter(march_proc *target, march_proc *self) {
    march_proc **link = &target->mbox_send_waiters;
    while (*link) {
        if (*link == self) {
            *link = self->send_wait_next;
            self->send_wait_next = NULL;
            return;
        }
        link = &(*link)->send_wait_next;
    }
    /* Not found: already taken (and woken, under the same lock, by
     * mbox_wake_send_waiters_if_low or the PROC_DEAD reap branch) --
     * nothing to do. */
}

/* ── Trampoline ───────────────────────────────────────────────────────── */

/* makecontext() accepts only int-sized variadic arguments.  We split the
 * 64-bit proc pointer into high/low 32-bit halves for portability. */
static void proc_trampoline(int arg_hi, int arg_lo) {
    /* Reassemble the pointer without sign-extension hazards. */
    uintptr_t addr = ((uintptr_t)(uint32_t)arg_hi << 32)
                   | ((uintptr_t)(uint32_t)arg_lo);
    march_proc *proc = (march_proc *)(void *)addr;

    /* This proc's very first execution resumes here (via makecontext), not
     * at "the instruction after its own swapcontext-away call" like every
     * later resume — so it must complete the handoff that sched_loop's
     * MARCH_ASAN_SWITCH_TO_PROC started, exactly once, before it can safely
     * start its own switch-away later (else ASan sees back-to-back
     * start_switch_fiber calls with no finish in between and aborts with
     * "starting fiber switch while in fiber switch"). */
    MARCH_ASAN_SWITCH_DONE(proc);

    /* Run the user-supplied function. */
    proc->fn(proc->arg);

    /* Function returned — mark dead and hand control back to the scheduler.
     * This proc never resumes after this switch, so there is no matching
     * MARCH_ASAN_SWITCH_DONE call. */
    atomic_store_explicit(&proc->status, PROC_DEAD, memory_order_release);
    MARCH_ASAN_SWITCH_TO_SCHED(proc);
    MARCH_TSAN_SWITCH_TO_SCHED(proc->owner_sched);
    swapcontext(&proc->ctx, &proc->owner_sched->sched_ctx);
    /* If we ever return here the OS context is gone — abort defensively. */
    abort();
}

/* ── Public API ───────────────────────────────────────────────────────── */

void march_sched_init(void) {
    /* Cache the OS page size for use in the async-signal-safe SIGSEGV handler. */
    if (g_page_size == 0)
        g_page_size = (size_t)sysconf(_SC_PAGE_SIZE);

    atomic_store_explicit(&g_next_pid, 0, memory_order_relaxed);
    atomic_store_explicit(&g_all_done,       0, memory_order_relaxed);
    atomic_store_explicit(&g_live_procs,     0, memory_order_relaxed);
    atomic_store_explicit(&g_live_nondaemon, 0, memory_order_relaxed);
    atomic_store_explicit(&g_sched_shutdown, 0, memory_order_relaxed);
    atomic_store_explicit(&g_runq_head, (march_proc *)NULL, memory_order_relaxed);
    g_runq_tail = NULL;
    /* C harnesses (e.g. test_scheduler_mbox.c) call march_sched_init() and
     * then spawn/send without ever running the scheduler, so a prior test's
     * g_runq_len could still be nonzero here — reset it alongside head/tail
     * so march_sched_stat(2) starts each init at a known 0. */
    atomic_store_explicit(&g_runq_len, 0, memory_order_relaxed);
    memset(g_proc_registry, 0, sizeof(g_proc_registry));
    g_proc_count = 0;
    g_timer_len = 0;   /* keep the heap allocation; the mutex is static */

    /* g_stack_free (Task 12) is deliberately NOT reset here. Its entries are
     * mmap reservations, which are process-wide OS state — a re-init (e.g.
     * a C test harness calling march_sched_init() a second time in the same
     * process, as test_scheduler_churn.c's reuse phase does) runs in the
     * SAME address space, so a still-mapped reservation from before the
     * re-init is exactly as valid and reusable as one retired moments ago.
     * Clearing the list here would only turn already-reusable mappings back
     * into leaks with no safety benefit. */

    g_num_scheds = MARCH_NUM_SCHEDULERS > 0 ? MARCH_NUM_SCHEDULERS : 1;
    /* Runtime override: MARCH_NUM_SCHEDULERS=N caps the number of OS scheduler
     * threads, clamped to [1, compile-time max].  Setting it to 1 serializes
     * all green-thread execution onto a single OS thread (no concurrent March
     * code), which is the only configuration under which the current
     * non-atomic local refcounting is race-free. */
    {
        const char *env = getenv("MARCH_NUM_SCHEDULERS");
        if (env && *env) {
            int n = atoi(env);
            if (n >= 1 && n <= MARCH_NUM_SCHEDULERS) g_num_scheds = n;
        }
    }
    for (int i = 0; i < g_num_scheds; i++) {
        memset(&g_scheds[i], 0, sizeof(march_scheduler));
        march_deque_init(&g_scheds[i].local_queue);
        g_scheds[i].id = i;
    }

    /* Install the SIGSEGV handler that enables lazy stack growth.
     * Idempotent: a CAS inside ensures it runs at most once per process. */
    install_stack_growth_handler();
}

static march_proc *sched_spawn_common(void (*fn)(void *), void *arg, int is_daemon) {
    march_proc *p = (march_proc *)calloc(1, sizeof(march_proc));
    if (!p) {
        fputs("march_sched: out of memory (process alloc)\n", stderr);
        return NULL;
    }

    p->pid        = atomic_fetch_add_explicit(&g_next_pid, 1, memory_order_relaxed);
    p->is_daemon  = is_daemon;
    /* NEW→RUNNABLE: trivially single-winner (the proc is not yet published
     * to any other thread); the enqueue below is the one matching enqueue. */
    p->status     = PROC_RUNNABLE;
    p->priority   = PRIO_NORMAL;
    p->reductions = MARCH_REDUCTION_BUDGET;
    p->fn         = fn;
    p->arg        = arg;
    p->mailbox    = NULL;
    p->mbox_tail  = NULL;
    atomic_init(&p->mbox_count, 0);
    atomic_init(&p->mbox_lock, 0);
    p->owner_sched = NULL;
#ifdef MARCH_TSAN_BUILD
    p->tsan_fiber = __tsan_create_fiber(0);
#endif

    /* Allocate the stack: reserve MARCH_STACK_MAX virtual memory, make only
     * the top MARCH_STACK_INITIAL bytes read/write initially.  The rest grows
     * on demand via the SIGSEGV handler.
     *
     * Prefer recycling a retired reservation from the free-list (Task 12) —
     * under spawn-churn workloads this keeps live VMA/RSS bounded near the
     * concurrency level instead of growing 1:1 with total-procs-ever-
     * spawned. Not under MARCH_ASAN_BUILD: ASan's fake-stack machinery
     * tracks per-fiber shadow state keyed by the stack's address range, and
     * handing that same range to a new, unrelated fiber right after a prior
     * one used it is exactly the kind of reuse ASan's fiber annotation
     * assumes doesn't happen — so ASan builds always take the fresh-mmap
     * path and keep leaking, same as before this task (the leak is
     * bounded and diagnostic builds are not the workload this fixes). */
    p->stack_base = NULL;
#ifndef MARCH_ASAN_BUILD
    p->stack_base = stack_reuse(&p->stack_alloc, &p->stack_mmap_base);
#endif
    if (!p->stack_base)
        p->stack_base = stack_alloc_lazy(&p->stack_alloc, &p->stack_mmap_base);
    if (!p->stack_base) {
        fputs("march_sched: failed to allocate process stack\n", stderr);
        free(p);
        return NULL;
    }

    /* Build the execution context. */
    if (getcontext(&p->ctx) != 0) {
        fputs("march_sched: getcontext failed\n", stderr);
        munmap(p->stack_mmap_base, p->stack_alloc);
        free(p);
        return NULL;
    }
    p->ctx.uc_stack.ss_sp   = p->stack_base;
    p->ctx.uc_stack.ss_size = MARCH_STACK_INITIAL;
    p->ctx.uc_link          = NULL; /* Trampoline manages the return explicitly. */

    /* Pass the proc pointer as two 32-bit ints (makecontext portability). */
    uintptr_t addr  = (uintptr_t)(void *)p;
    int       arg_hi = (int)(uint32_t)(addr >> 32);
    int       arg_lo = (int)(uint32_t)(addr & 0xFFFFFFFFu);
    makecontext(&p->ctx, (void (*)(void))proc_trampoline, 2, arg_hi, arg_lo);

    registry_add(p);
    atomic_fetch_add_explicit(&g_live_procs, 1, memory_order_relaxed);
    if (!is_daemon)
        atomic_fetch_add_explicit(&g_live_nondaemon, 1, memory_order_relaxed);

    /* Push to the local deque if called from a scheduler thread (owner push,
     * Chase-Lev-legal).  From non-scheduler threads (e.g. the main OS
     * thread), push to the global run queue instead — pushing to a Chase-Lev
     * deque from a thread that is not the deque's owner races with the
     * owner's pop. */
    if (tl_sched) {
        dbg_mark_enqueued(p, "spawn_local_push");
        march_deque_push(&tl_sched->local_queue, p);
    } else {
        global_runq_push(p);
    }

    return p;
}

march_proc *march_sched_spawn(void (*fn)(void *), void *arg) {
    return sched_spawn_common(fn, arg, 0);
}

march_proc *march_sched_spawn_daemon(void (*fn)(void *), void *arg) {
    return sched_spawn_common(fn, arg, 1);
}

/* ── Per-thread scheduler loop with work-stealing ────────────────────── */

/* Wake every parked daemon proc that has an empty mailbox.  Called from the
 * idle branch of sched_loop once shutdown has been requested and no
 * non-daemon procs remain: the woken daemons' march_sched_recv returns
 * MARCH_RECV_NO_MSG, their loops (actor_green_thread) break, and they die —
 * letting g_live_procs drain to 0 so the scheduler can exit.  Daemons with
 * pending messages are left alone; the normal send/wake path handles them
 * and a later idle iteration picks them up once drained.
 * Returns the number of procs woken. */
static int wake_idle_daemons(void) {
    int woken = 0;
    pthread_mutex_lock(&g_registry_mu);
    int64_t hi = atomic_load_explicit(&g_next_pid, memory_order_acquire);
    if (hi > MARCH_MAX_PROCS) hi = MARCH_MAX_PROCS;
    for (int64_t i = 0; i < hi; i++) {
        march_proc *q = g_proc_registry[i];
        if (!q || !q->is_daemon) continue;
        if (atomic_load_explicit(&q->status, memory_order_acquire) == PROC_WAITING
                && atomic_load_explicit(&q->mbox_count, memory_order_relaxed) == 0) {
            march_sched_wake(q);
            woken++;
        }
    }
    pthread_mutex_unlock(&g_registry_mu);
    return woken;
}

/* Deferred Signal.watch drain.  The REAL implementation lives in
 * march_runtime.c (it runs pending March signal handlers) and is a STRONG
 * symbol, so it overrides this WEAK no-op whenever the full runtime is linked.
 * The weak fallback exists so the standalone scheduler unit tests
 * (test/test_scheduler{,_mt}.c, which link ONLY march_scheduler.c, not the rest
 * of the runtime) resolve the symbol instead of failing at link time — the same
 * weak-symbol discipline as g_http_shutdown in march_runtime.c.  Called from the
 * scheduler loop body — a normal C stack, never signal context. */
__attribute__((weak)) void march_signal_drain(void) { }

static void sched_loop(march_scheduler *sched) {
    /* Set up the per-thread alternate signal stack before running any green
     * threads.  The SIGSEGV handler for lazy stack growth requires SA_ONSTACK
     * so it can run even when the green thread's stack is exhausted. */
    setup_alt_stack();

#ifdef MARCH_TSAN_BUILD
    /* Capture this OS thread's own native execution as a TSan fiber, once,
     * so every swapcontext() that resumes it can name it explicitly. */
    sched->tsan_fiber = __tsan_get_current_fiber();
#endif

    /* Touch march_tls_reductions BEFORE publishing sched->running (which
     * makes the preemption daemon start signalling this thread).  On Darwin,
     * _Thread_local storage is materialized lazily on first access via
     * tlv_get_addr -> tlv_allocate_and_initialize -> MALLOC.  The SIGUSR1
     * preemption handler writes this TLS variable; if its first-ever access
     * on this thread happens INSIDE the signal handler, the handler calls
     * malloc mid-signal — async-signal-unsafe — and corrupts the allocator
     * state of whatever this thread was interrupted in (calloc'd proc
     * structs, mailbox nodes, March heap objects), which surfaced as wild
     * garbage ucontexts and heap-metadata crashes under actor churn. */
    march_tls_reductions = MARCH_REDUCTION_BUDGET;

    tl_sched = sched;
    atomic_store_explicit(&sched->running, 1, memory_order_release);
    unsigned int steal_seed = (unsigned int)sched->id;
    /* When the previous task cooperatively yielded (PROC_RUNNABLE after running),
     * try to steal work from another scheduler before re-running the yielded
     * task.  Without this, all workers can deadlock in a LIFO spin where each
     * pops its own yielded spin-waiter instead of running the leaf tasks that
     * would unblock them. */
    int last_yielded = 0;

    while (!atomic_load_explicit(&g_all_done, memory_order_acquire)) {
        /* Run any pending Signal.watch handlers on this normal stack before
         * dispatching green threads.  Cheap when idle (five atomic loads). */
        march_signal_drain();

        /* Check the global run queue FIRST, every iteration.  It is the only
         * path cross-thread enqueues (wakes, external spawns) arrive on, and
         * a scheduler whose local deque never drains — e.g. a wait_idle/
         * task_await spinner that yields and is re-pushed locally every
         * turn — would otherwise never look at it.  At MARCH_NUM_SCHEDULERS=1
         * that is a guaranteed livelock: main spins in its own deque forever
         * while the actor it woke starves in the global queue.  The check is
         * one lock-free acquire load when the queue is empty (the common
         * case); FIFO pop order doubles as wake fairness. */
        march_proc *p = global_runq_pop();
        int from_global = (p != NULL);
        (void)from_global;

        /* Single-scheduler: use steal (FIFO) for fairness and compatibility.
         * Multi-scheduler: use pop (LIFO) for cache locality; steal from others.
         * Exception: if the previous task yielded, try to steal first to avoid
         * the LIFO livelock described above. */
        if (p) {
            /* run the globally-queued proc */
        } else if (g_num_scheds <= 1) {
            p = (march_proc *)march_deque_steal(&sched->local_queue);
        } else if (last_yielded) {
            /* Yielded task goes back; steal from others to make progress. */
            p = NULL;
            for (int attempts = 0; attempts < g_num_scheds - 1; attempts++) {
                steal_seed = steal_seed * 1103515245 + 12345;
                int victim = (int)((steal_seed >> 16) % g_num_scheds);
                if (victim == sched->id) victim = (victim + 1) % g_num_scheds;
                p = (march_proc *)march_deque_steal(&g_scheds[victim].local_queue);
                if (p) break;
            }
            if (!p) p = (march_proc *)march_deque_pop(&sched->local_queue);
        } else {
            p = (march_proc *)march_deque_pop(&sched->local_queue);
        }
        last_yielded = 0;

        /* Try to steal from another scheduler if local deque is empty. */
        if (!p && g_num_scheds > 1) {
            for (int attempts = 0; attempts < g_num_scheds - 1; attempts++) {
                steal_seed = steal_seed * 1103515245 + 12345;
                int victim = (int)((steal_seed >> 16) % g_num_scheds);
                if (victim == sched->id) victim = (victim + 1) % g_num_scheds;
                p = (march_proc *)march_deque_steal(&g_scheds[victim].local_queue);
                if (p) break;
            }
        }

        if (p && !from_global) dbg_mark_dequeued(p, "local_pop_or_steal");

        if (!p) {
            if (atomic_load_explicit(&g_live_procs, memory_order_acquire) <= 0
                    && atomic_load_explicit(&g_sched_shutdown, memory_order_acquire)) {
                atomic_store_explicit(&g_all_done, 1, memory_order_release);
                break;
            }
            /* Shutdown endgame: only daemon procs (actor recv loops) remain
             * and nothing is runnable here.  Wake idle daemons so their
             * loops exit; without this, any program that ends main() while
             * an actor is still alive would hang forever right here. */
            if (atomic_load_explicit(&g_sched_shutdown, memory_order_acquire)
                    && atomic_load_explicit(&g_live_nondaemon, memory_order_acquire) <= 0
                    && wake_idle_daemons() > 0)
                continue;  /* woken procs are in the global runq — next
                            * iteration's global_runq_pop picks them up */
            /* No runnable process: sleep 1ms to avoid burning CPU at idle.
             * sched_yield() alone causes ~99% CPU on a waiting server. */
            struct timespec idle_sleep = { 0, 1000000 }; /* 1ms */
            nanosleep(&idle_sleep, NULL);
            continue;
        }

        /* Claim the proc with a CAS RUNNABLE→RUNNING before executing it.
         * Because enqueue is single-winner (every transition INTO RUNNABLE
         * is one atomic CAS/uncontended store whose winner alone enqueues,
         * and cross-thread pushes are gone), a dequeued proc is referenced
         * by this thread only — so this CAS should never lose.  It is a
         * backstop: if it ever fails with an unexpected state, the single-
         * membership invariant was violated and (in MARCH_DEBUG builds) we
         * abort at the moment it happens instead of corrupting a stack.
         *
         * One legitimate failure exists: march_task_cancel_by_id stores
         * PROC_DEAD cross-thread into a proc that may be sitting in a run
         * queue.  Pre-CAS dispatch ran such a proc anyway (the store was
         * blindly overwritten with RUNNING and the thunk completed,
         * setting the task's done flag); preserve exactly that behavior by
         * claiming DEAD→RUNNING and running it.  Dropping it instead would
         * strand g_live_procs above zero (shutdown hang) and leave
         * task_await spinning on a done flag that never gets set. */
        march_proc_status claim = PROC_RUNNABLE;
        if (!atomic_compare_exchange_strong_explicit(
                &p->status, &claim, PROC_RUNNING,
                memory_order_acq_rel, memory_order_acquire)) {
            if (claim == PROC_DEAD) {
                if (!atomic_compare_exchange_strong_explicit(
                        &p->status, &claim, PROC_RUNNING,
                        memory_order_acq_rel, memory_order_acquire)) {
                    /* DEAD moved under us — nothing else may own a dequeued
                     * proc; drop defensively (debug builds scream). */
#ifdef MARCH_DEBUG
                    fprintf(stderr,
                            "march_sched[BUG]: claim of dequeued pid %lld "
                            "failed twice (status=%d)\n",
                            (long long)p->pid, (int)claim);
                    abort();
#endif
                    continue;
                }
            } else {
#ifdef MARCH_DEBUG
                fprintf(stderr,
                        "march_sched[BUG]: dequeued pid %lld not RUNNABLE "
                        "at claim (status=%d, running_on=%d) — "
                        "single-membership violated\n",
                        (long long)p->pid, (int)claim,
                        atomic_load_explicit(&p->dbg_running_on,
                                             memory_order_acquire));
                abort();
#endif
                continue;   /* stale/duplicate reference: drop, never run */
            }
        }
        p->reductions   = MARCH_REDUCTION_BUDGET;
        p->owner_sched  = sched;
        sched->current  = p;

        dbg_mark_dispatched(p, sched->id);
        MARCH_ASAN_SWITCH_TO_PROC(sched, p);
        MARCH_TSAN_SWITCH_TO_PROC(p);
        swapcontext(&sched->sched_ctx, &p->ctx);
        MARCH_ASAN_SWITCH_DONE(sched);
        dbg_mark_undispatched(p);

        sched->current = NULL;

        march_proc_status st = atomic_load_explicit(&p->status, memory_order_acquire);
        if (st == PROC_RUNNABLE) {
            dbg_mark_enqueued(p, "yield_repush");
            march_deque_push(&sched->local_queue, p);
            last_yielded = 1;
        } else if (st == PROC_PARKED) {
            /* The process called march_sched_recv's slow path: it stored
             * PROC_PARKED then immediately called swapcontext.  Now that
             * swapcontext has returned here, the process's ucontext is fully
             * saved in p->ctx.  Transition to PROC_WAITING so that any
             * waker that was spin-waiting on PROC_PARKED can now safely CAS
             * WAITING→RUNNABLE and enqueue p without risk of another
             * thread resuming a process whose context isn't saved yet. */
            atomic_store_explicit(&p->status, PROC_WAITING, memory_order_release);
        } else if (st == PROC_DEAD) {
            registry_remove(p);
            atomic_fetch_sub_explicit(&g_live_procs, 1, memory_order_release);
            if (!p->is_daemon)
                atomic_fetch_sub_explicit(&g_live_nondaemon, 1, memory_order_release);
            /* Task 8: wake any senders parked under MARCH_MBOX_BLOCK
             * waiting for THIS proc's mailbox to drain below low-water --
             * it never will now, since p just died. Unconditional (not
             * gated on the low-water check mbox_wake_send_waiters_if_low
             * uses for the ordinary drain path -- every waiter needs
             * waking here, not just enough to cross a threshold), but the
             * SAME "walk and wake entirely under p's own mbox_lock"
             * discipline -- see mbox_wake_send_waiters_if_low's comment
             * for why waking after releasing the lock is a real,
             * deterministic-once-triggered race, not just a style choice.
             * This is also the release half of the dead-during-registration
             * race closed by the recheck in mbox_block_register_and_park --
             * see its comment for the full happens-before argument (this
             * release pairs with that acquire). */
            mbox_lock_acquire(p);
            march_proc *dead_w = p->mbox_send_waiters;
            p->mbox_send_waiters = NULL;
            while (dead_w) {
                march_proc *dead_next = dead_w->send_wait_next;
                dead_w->send_wait_next = NULL;
                march_sched_wake(dead_w);
                dead_w = dead_next;
            }
            mbox_lock_release(p);
            /* Recycle the STACK reservation (Task 12) — the proc STRUCT
             * itself still leaks; see the "Deliberately NOT munmap ...
             * / free(p)" comment immediately below for why that part is
             * unchanged (Task 2's timers and cross-thread actor-meta
             * readers depend on `p` staying valid forever). The stack
             * mapping has no such reader: see the safety argument on the
             * stack free-list definitions above (stack_reuse/stack_retire)
             * for the full case that nothing can touch a dead proc's stack
             * after this point. Not under MARCH_ASAN_BUILD — see the
             * comment at the stack_reuse call site in sched_spawn_common.
             *
             * After this point p->stack_mmap_base is NULL (so the
             * MARCH_DEBUG fatal walker, which reads it with no lock, skips
             * this proc) and p's ucontext/stack_base are stale/garbage;
             * both are fine because a DEAD proc is never dispatched or
             * grown again. */
#ifndef MARCH_ASAN_BUILD
            if (p->stack_mmap_base) {
                stack_retire(p->stack_mmap_base);
                p->stack_mmap_base = NULL;
                p->stack_base      = NULL;
                atomic_fetch_add_explicit(
                    &march_stat_counters[MARCH_STAT_STACKS_RECYCLED], 1,
                    memory_order_relaxed);
            }
#endif
            /* Deliberately NOT munmap(p->stack_mmap_base, ...) / free(p) here.
             *
             * march_actor_meta.green_thread (march_runtime.c) holds a
             * march_proc* that is read from OTHER OS threads (do_actor_death,
             * march_actor_broadcast_migrate, march_actor_call/reply) with NO
             * synchronization against this thread's registry_remove/free —
             * only the SEPARATE g_proc_registry array (walked by
             * march_sched_wait_idle / wake_idle_daemons, under g_registry_mu)
             * had that protection. A reader on another thread can therefore
             * still be mid-dereference of `p` (or about to dereference it)
             * at the exact moment this branch would have freed it and a
             * later spawn's calloc reused the same address for an unrelated
             * proc — confirmed via ThreadSanitizer as a genuine, not
             * benign, data race causing heap corruption (intermittent
             * SIGSEGV/SIGBUS/hangs) under supervision's kill-then-
             * immediately-respawn pattern, and reproducible with plain
             * kill()+spawn() with no supervision involved at all.
             *
             * Leaving `p` (and its stack mmap) allocated forever makes every
             * stale reader safe: p->status still correctly reads PROC_DEAD
             * (already-dead handling is required everywhere regardless, so
             * this adds no new cases to handle), and the memory is never
             * repurposed out from under a reader that hasn't yet noticed
             * the process died. This trades an unreclaimed-memory leak
             * (bounded by total actors ever spawned+killed over a program's
             * lifetime) for eliminating the crash; proper reclamation
             * (e.g. reference counting or an epoch/hazard-pointer scheme)
             * is a separate, larger undertaking — see specs/todos.md. */
        }
        /* PROC_WAITING: process parked itself; a wakeup call re-enqueues it. */
    }

    atomic_store_explicit(&sched->running, 0, memory_order_release);
    tl_sched = NULL;
}

static void *sched_thread_entry(void *arg) {
    march_scheduler *sched = (march_scheduler *)arg;
    sched_loop(sched);
    return NULL;
}

void march_sched_request_shutdown(void) {
    atomic_store_explicit(&g_sched_shutdown, 1, memory_order_release);
}

void march_sched_run(void) {
    atomic_store_explicit(&g_all_done, 0, memory_order_relaxed);

    /* Single-scheduler fast path: no worker threads needed.
     *
     * The preemption daemon IS still needed.  This path used to return without
     * ever calling march_sched_preempt_start(), so MARCH_NUM_SCHEDULERS=1 had
     * no timer preemption at all: the only thing that ever preempted a
     * CPU-bound green thread was compiled code's per-call reduction counter
     * hitting zero.  That made single-scheduler mode — the configuration used
     * to get deterministic, race-free runs — the one place where a green
     * thread could monopolise the scheduler if the counter were ever removed.
     * Caught by the starvation test: a CPU-bound TCO loop starved a sibling
     * green thread here while behaving correctly on >= 2 schedulers, where the
     * sibling merely ran on another OS thread (parallelism, not preemption). */
    if (g_num_scheds <= 1) {
        g_scheds[0].thread = pthread_self();
        march_sched_preempt_start();
        sched_loop(&g_scheds[0]);
        /* Final drain: a Signal.watch delivery that landed just before shutdown
         * (e.g. a synchronous self-raise right before main returns) may have set
         * its pending flag after the loop's last top-of-iteration drain but
         * before g_all_done was observed.  Run it now, on this normal stack. */
        march_signal_drain();
        march_sched_preempt_stop();
        return;
    }

    /* Scheduler 0 runs on the calling thread — record its pthread_t so the
     * preemption daemon can send SIGUSR1 to it like any other worker. */
    g_scheds[0].thread = pthread_self();

    /* Spawn N-1 worker threads; scheduler 0 runs on the calling thread. */
    for (int i = 1; i < g_num_scheds; i++) {
        pthread_create(&g_scheds[i].thread, NULL, sched_thread_entry, &g_scheds[i]);
    }

    /* Start the preemption daemon now that all pthread_t handles are stored. */
    march_sched_preempt_start();

    sched_loop(&g_scheds[0]);

    for (int i = 1; i < g_num_scheds; i++) {
        pthread_join(g_scheds[i].thread, NULL);
    }

    /* Final drain (see the single-scheduler path above): catch any Signal.watch
     * delivery that raced shutdown, now that all worker threads have joined and
     * this is the only thread running. */
    march_signal_drain();

    march_sched_preempt_stop();
}

/* NOINLINE — this is a green-thread MIGRATION BARRIER, and that attribute is
 * load-bearing, not a style choice.
 *
 * A green thread that yields here can be re-dispatched on a DIFFERENT OS
 * thread (work stealing / global-runq drain).  `tl_sched` is _Thread_local:
 * the C compiler assumes a function body executes on ONE thread and freely
 * caches the TLS slot address in a callee-saved register.  When this function
 * was inlinable, clang -O2 inlined it into march_sched_wait_idle's loop and
 * HOISTED the tlv_get_addr(tl_sched) out of the loop — so after the first
 * yield migrated the green thread to another OS thread, every subsequent
 * iteration read the ORIGINAL thread's tl_sched, grabbed the WRONG
 * scheduler's ->current (a different, possibly running proc), forced its
 * status to RUNNABLE mid-run, saved over its live ucontext, and resumed the
 * wrong scheduler's sched_ctx on this thread — putting two OS threads inside
 * one sched_loop frame.  Observed as intermittent SIGSEGV/SIGBUS with
 * sched_loop's `sched` register reading back NULL and pc landing inside
 * g_scheds under kill+respawn churn at MARCH_NUM_SCHEDULERS > 1 (verified by
 * disassembly of the miscompiled wait_idle loop, and by the crash vanishing
 * once yield calls re-derive TLS per call).
 *
 * noinline forces every caller through a fresh function entry, whose
 * tlv_get_addr executes on the CURRENT OS thread.  Inside this body there is
 * no TLS access after the swapcontext, so the body itself is
 * migration-safe.  Rule for all future scheduler code: never touch a
 * _Thread_local after a swapcontext that can migrate the green thread, and
 * never let a switch-crossing function be inlined into a loop that reads
 * thread-locals. */
__attribute__((noinline))
void march_sched_yield(void) {
    if (!tl_sched || !tl_sched->current) return;
    march_proc *p = tl_sched->current;
    /* Authorized RUNNING→RUNNABLE transition (single-winner enqueue rule):
     * only the running proc itself performs it, on its own scheduler
     * thread, and the matching enqueue is done exactly once by the owner
     * scheduler after swapcontext returns (post-swap RUNNABLE branch).
     * The only possible contender is march_task_cancel_by_id's cross-
     * thread DEAD store; if it raced us, deliberately overwrite it —
     * pre-CAS dispatch always did — so the cancelled thunk still runs to
     * completion and sets its task's done flag (dropping it here would
     * hang task_await and strand g_live_procs above zero). */
    march_proc_status expect = PROC_RUNNING;
    if (!atomic_compare_exchange_strong_explicit(
            &p->status, &expect, PROC_RUNNABLE,
            memory_order_acq_rel, memory_order_acquire)) {
        atomic_store_explicit(&p->status, PROC_RUNNABLE, memory_order_release);
    }
    MARCH_ASAN_SWITCH_TO_SCHED(p);
    MARCH_TSAN_SWITCH_TO_SCHED(tl_sched);
    swapcontext(&p->ctx, &tl_sched->sched_ctx);
    MARCH_ASAN_SWITCH_DONE(p);
    /* Execution resumes here after the scheduler re-schedules us — possibly
     * on a different OS thread than the one that called this function. */
}

/* Grace iterations before march_sched_wait_idle backs off to a 1ms poll, so a
 * genuinely-idle wait stops pegging a core (mirrors SCHED_WAKE_SPIN_GRACE). */
#define WAIT_IDLE_SPIN_GRACE 4096

void march_sched_wait_idle(void) {
    if (!tl_sched || !tl_sched->current) return;
    /* `self` is a proc pointer (stable across migrations); it is captured
     * BEFORE the first yield, on the correct thread.  Do NOT read tl_sched
     * anywhere in the loop below: after each march_sched_yield this green
     * thread may be running on a different OS thread, and a cached TLS
     * address would alias the original thread's slot (see the migration-
     * barrier comment on march_sched_yield — this loop is exactly where
     * that miscompilation caused the multi-scheduler stack corruption). */
    march_proc *self = tl_sched->current;
    int64_t spins = 0;   /* a local (stack, not TLS) — migration-safe */
    for (;;) {
        /* Give every other runnable proc a turn before checking. */
        march_sched_yield();
        int busy = 0;
        pthread_mutex_lock(&g_registry_mu);
        int64_t hi = atomic_load_explicit(&g_next_pid, memory_order_acquire);
        if (hi > MARCH_MAX_PROCS) hi = MARCH_MAX_PROCS;
        for (int64_t i = 0; i < hi && !busy; i++) {
            march_proc *q = g_proc_registry[i];
            if (!q || q == self) continue;
            march_proc_status st =
                atomic_load_explicit(&q->status, memory_order_acquire);
            if (st == PROC_RUNNABLE || st == PROC_RUNNING || st == PROC_PARKED) {
                busy = 1;
            } else if (st == PROC_WAITING
                       && atomic_load_explicit(&q->mbox_count, memory_order_relaxed) > 0) {
                /* Message enqueued but wake not yet delivered — transient. */
                busy = 1;
            }
        }
        pthread_mutex_unlock(&g_registry_mu);
        if (!busy) return;
        /* Still busy after yielding: the procs we wait on are runnable only on
         * other (possibly CPU-starved) scheduler threads, or are PARKED/WAITING
         * and not locally runnable — so march_sched_yield() returned with
         * nothing else to run here, and re-dispatched THIS proc immediately
         * (sched_loop's own idle-sleep never fires because we stay runnable).
         * That tight yield->scan loop pegs a core under oversubscription. After
         * a grace period, back off to a 1ms poll (the cadence sched_loop and
         * march_sched_wake already use). No timeout: this still returns only
         * once the system is quiescent, preserving wait-forever semantics. */
        if (spins < WAIT_IDLE_SPIN_GRACE) {
            spins++;
        } else {
            struct timespec ts = { 0, 1000000 }; /* 1ms */
            nanosleep(&ts, NULL);
        }
    }
}

void march_sched_tick(void) {
    if (!tl_sched || !tl_sched->current) return;
    march_proc *p = tl_sched->current;
    p->reductions--;
    if (p->reductions <= 0) {
        march_sched_yield(); /* Budget exhausted — cooperative preemption. */
    }
}

void march_sched_exit(void) {
    if (!tl_sched || !tl_sched->current) return;
    march_proc *p = tl_sched->current;
    atomic_store_explicit(&p->status, PROC_DEAD, memory_order_release);
    /* This proc never resumes after this switch, so there is no matching
     * MARCH_ASAN_SWITCH_DONE call. */
    MARCH_ASAN_SWITCH_TO_SCHED(p);
    MARCH_TSAN_SWITCH_TO_SCHED(tl_sched);
    swapcontext(&p->ctx, &tl_sched->sched_ctx);
    abort(); /* Should never be reached. */
}

march_proc *march_sched_current(void) {
    return tl_sched ? tl_sched->current : NULL;
}

/* Returns 1 if the calling OS thread is currently running inside the scheduler
 * loop (tl_sched is set), 0 otherwise.  Used by march_ensure_sched_started to
 * avoid launching a redundant background thread. */
int march_sched_in_scheduler(void) {
    return tl_sched != NULL;
}

/* self() builtin — returns the current green thread's proc pointer (the PID
 * value used as first arg to send/receive in the compiled binary). */
void *march_self(void) {
    return (void *)march_sched_current();
}

int64_t march_sched_total_spawned(void) {
    return atomic_load_explicit(&g_next_pid, memory_order_relaxed);
}

march_proc *march_sched_find(int64_t pid) {
    if (pid < 0 || pid >= MARCH_MAX_PROCS) return NULL;
    return g_proc_registry[pid];
}

/* ── Phase 4: compiled-code reduction counting ────────────────────────── */

/* Thread-local reduction budget.  No longer on the compiled hot path (see
 * march_preempt_request below); retained because march_yield_from_compiled
 * refills it and the `task_reductions()` builtin reads it.
 * volatile: zeroed by the SIGUSR1 preemption handler (see Phase 5A). */
volatile _Thread_local int64_t march_tls_reductions = MARCH_REDUCTION_BUDGET;

/* Preemption request flag read by every compiled function on entry.  Plain
 * global on purpose — see the long rationale on the declaration in
 * march_scheduler.h (TLS access is an indirect call per entry on both
 * Darwin/arm64 and Linux/arm64-PIE; this cost 1.75x on bench/fib.march). */
volatile int64_t march_preempt_request = 0;

void march_yield_from_compiled(void) {
    /* Clear the request FIRST.  If we cleared it after yielding, this thread
     * would re-enter compiled code, immediately observe the still-set flag,
     * and yield again in a tight loop until the daemon happened to clear it. */
    march_preempt_request = 0;
    /* Refill the budget before yielding so the process gets a fresh quantum
     * when it is rescheduled.  Do this unconditionally — if we are not inside
     * a scheduler context the yield below is a no-op, but the counter should
     * still be valid for future use (task_reductions() reads it). */
    march_tls_reductions = MARCH_REDUCTION_BUDGET;
    march_sched_yield();
}

/* Message disposer for dropped mailbox messages. The runtime registers a
 * real dtor (march_decrc / migrate-free) in Task 14; standalone scheduler
 * builds (and the default, before any caller opts in) leak the payload by
 * design — every message the current test corpus drops is a tagged
 * immediate or a raw C struct owned outside March's RC, not a March heap
 * value. */
static void (*g_mbox_dispose)(void *) = NULL;
void march_sched_set_msg_dtor(void (*fn)(void *)) { g_mbox_dispose = fn; }
static void march_mbox_dispose(void *msg) { if (g_mbox_dispose) g_mbox_dispose(msg); }

void march_sched_set_mbox_limit(march_proc *p, int64_t limit,
                                march_mbox_policy policy) {
    if (!p) return;
    mbox_lock_acquire(p);
    p->mbox_limit  = limit > 0 ? limit : 0;
    p->mbox_policy = (int32_t)policy;
    mbox_lock_release(p);
}

/* Register the CURRENT green thread as a MARCH_MBOX_BLOCK sender-waiter on
 * `target` (already locked by the caller; this releases the lock) and park
 * until woken. Returns MARCH_SEND_OK if the caller should retry the send
 * (capacity may have opened up, or this was a spurious/permit wake -- the
 * caller's own retry loop re-checks), or MARCH_SEND_DEAD if target died
 * before or during registration.
 *
 * NOINLINE: migration barrier -- same class of hazard as march_sched_recv /
 * march_sched_recv_until, but the fix has to live HERE, not on
 * march_sched_park_self. Marking park_self itself noinline (an earlier,
 * INSUFFICIENT attempt at this fix, caught by the Task 8 stress loop) only
 * stops the compiler from merging its OWN internal tl_sched read into a
 * caller across inlining -- it does nothing about a read of tl_sched that
 * lives in the CALLER's own loop body, like `self = tl_sched->current`
 * used to, directly inside march_sched_send's retry loop. Nothing IN
 * march_sched_send (or in park_self, seen whole by the optimizer even
 * un-inlined) ever WRITES tl_sched -- that write happens only in
 * sched_loop, on a different OS thread, invisible to this translation
 * unit's dataflow for this function -- so clang -O2 is free to treat
 * tl_sched as loop-invariant for the ENTIRE march_sched_send activation
 * and hoist `self`'s read out of the `for (;;)` loop ENTIRELY, reusing the
 * PRE-migration thread's stale scheduler/proc pointer on every later
 * iteration. Confirmed by a minimal standalone ucontext+pthread reproducer
 * (a _Thread_local read stuck at its first-resolved value across repeated
 * cross-thread swapcontext resumes, while pthread_self() correctly tracked
 * the real thread) and by the Task 8 stress loop still deadlocking with
 * park_self alone marked noinline. The fix that actually works follows the
 * SAME discipline march_sched_recv/recv_until already use for their own
 * loops (march_sched_wait_idle calling march_sched_yield in a loop is the
 * original instance of this exact bug, see march_sched_yield's own
 * noinline comment): put the tl_sched READ inside a dedicated noinline
 * function that the loop calls FRESH every iteration, so every iteration
 * is a real, opaque call boundary the optimizer cannot hoist a TLS read
 * across. */
__attribute__((noinline))
static int mbox_block_register_and_park(march_proc *target) {
    march_proc *self = tl_sched ? tl_sched->current : NULL;
    if (!self) {
        /* Genuine foreign OS thread (evloop etc.) -- tl_sched itself is
         * NULL here, meaning this is not a scheduler thread at all. (The
         * OTHER `self == NULL` case, a scheduler thread with no current
         * green thread, is intercepted by the caller BEFORE it ever
         * calls this function -- see the `tl_sched && !tl_sched->current`
         * check in march_sched_send's MARCH_MBOX_BLOCK case for why that
         * one needs different handling: it cannot safely sleep-poll.)
         * Cannot park a green thread that doesn't exist. Sleep-poll at
         * the scheduler's own idle cadence; safe here because some
         * OTHER, independent OS thread (a real scheduler) can still run
         * sched_loop and drain the mailbox while this one naps. */
        mbox_lock_release(target);
        struct timespec ts = { 0, 1000000 }; /* 1ms */
        nanosleep(&ts, NULL);
        return MARCH_SEND_OK;   /* caller retries unconditionally */
    }

    /* Dead-during-registration race (lost-wakeup audit): the PROC_DEAD reap
     * branch in sched_loop takes THIS SAME mbox_lock to drain and wake
     * target->mbox_send_waiters once, when target dies. Two cases:
     *
     *  (A) target dies AFTER we register below: reap acquires the lock
     *      after us, finds us already published in the waiter list
     *      (registration happened under the lock, same as mbox_pop's
     *      drain-side wake), and calls march_sched_wake(self) -- the
     *      wake_pending permit makes our imminent park return immediately.
     *      Ordinary case; no special handling needed.
     *
     *  (B) target died and was ALREADY reaped before we even reach this
     *      lock acquire: reap ran once, found an empty (or different)
     *      waiter list, and will never run again for this target
     *      (PROC_DEAD is terminal). If we blindly registered here, we'd
     *      park with no one left to ever wake us -- a genuine lost
     *      wakeup, NOT covered by the wake_pending permit (there is no
     *      wake left to arrive).
     *
     *  The recheck below closes (B): mbox_lock_acquire (by our caller)
     *  uses memory_order_acquire and the reap branch's mbox_lock_release
     *  uses memory_order_release, so if reap's critical section already
     *  ran and released the lock before we acquired it, this acquire
     *  synchronizes-with that release. Transitively, it also observes
     *  target's status=PROC_DEAD store, which happened in program order
     *  on target's own green thread (proc_trampoline) strictly BEFORE the
     *  swap back to the scheduler that triggers the reap -- so by the
     *  time we hold the lock, if reap already ran, we are guaranteed to
     *  see PROC_DEAD here rather than a stale "alive" read. We bail out
     *  instead of registering. */
    if (atomic_load_explicit(&target->status, memory_order_acquire) == PROC_DEAD) {
        mbox_lock_release(target);
        return MARCH_SEND_DEAD;
    }

    /* Register as waiter, release lock, park. */
    self->send_wait_next = target->mbox_send_waiters;
    target->mbox_send_waiters = self;
    mbox_lock_release(target);
    march_sched_park_self();

    /* UNCONDITIONALLY deregister self from target->mbox_send_waiters
     * before returning to the caller's retry, regardless of WHY
     * park_self returned. This is required, not optional cleanup: a
     * parked sender can be woken by a source that has nothing to do
     * with THIS target ever draining -- another sender targeting self
     * directly, a stale march_sched_recv_until timer entry firing late,
     * a supervised actor-death wake -- while self is still genuinely
     * linked in target->mbox_send_waiters (no drain has taken it yet).
     * If the caller's retry loop then re-checks capacity, finds it
     * still full, and calls back in here, this function would
     * re-register self ON TOP of its own still-present entry
     * (self->send_wait_next = target->mbox_send_waiters, which would
     * already equal self, or point through self) -- corrupting the
     * chain into a self-loop or an orphaned tail, deterministically, on
     * the very first spurious wake while still linked. No race is
     * needed to trigger this -- it is a straight-line logic bug in the
     * "just park and retry" shape without this step, caught by the
     * Task 8 code review before it ever needed a stress run to surface.
     *
     * In the common case (a normal drain-triggered wake, or the
     * PROC_DEAD reap branch) self is already gone from the list --
     * mbox_wake_send_waiters_if_low and the reap branch both fully
     * unlink (and NULL the link field of) every waiter they wake,
     * entirely under this same mbox_lock, before ever calling
     * march_sched_wake -- so this call finds nothing and is a no-op.
     * mbox_unlink_send_waiter's own comment has the full argument for
     * why "not found" is always safe to treat as "already handled". */
    mbox_lock_acquire(target);
    mbox_unlink_send_waiter(target, self);
    mbox_lock_release(target);
    return MARCH_SEND_OK;   /* caller retries unconditionally */
}

int march_sched_send(march_proc *target, void *msg) {
    /* Allocate the mailbox node ONCE before the retry loop and lock
     * acquisition, off the spinlock hot path. The node is freed on every
     * path that does not enqueue it (top-of-function DEAD return, DROP_NEW,
     * and BLOCK's dead-during-registration recheck); reused on BLOCK's
     * park-retry loop. */
    march_mbox_node *node = mbox_node_new(msg);

    /* Loop instead of the brief's literal `return march_sched_send(...)`
     * recursive retry: BLOCK's park/wake cycle can repeat an unbounded
     * number of times under sustained backpressure (or a spurious wake --
     * see the loop-tolerance note on the MARCH_MBOX_BLOCK case below), and
     * while every retry site here IS a tail call, C gives no TCO guarantee.
     * A green thread's initial stack is only MARCH_STACK_INITIAL (4 KiB);
     * an unbounded recursion depth on a pathological sender herd risks
     * exhausting it. `continue` re-enters this loop at the top instead,
     * for both the green-thread (parked) and foreign-thread (sleep-polled)
     * BLOCK paths. Deviation from the brief's literal snippet; behavior is
     * identical. */
    for (;;) {
        if (!target || atomic_load_explicit(&target->status, memory_order_acquire) == PROC_DEAD) {
            free(node);
            return MARCH_SEND_DEAD;
        }
        mbox_lock_acquire(target);
        if (target->mbox_limit > 0
                && march_sched_mbox_count(target) >= target->mbox_limit) {
            switch (target->mbox_policy) {
            case MARCH_MBOX_DROP_NEW:
                mbox_lock_release(target);
                atomic_fetch_add_explicit(&march_stat_counters[MARCH_STAT_MSGS_DROPPED],
                                          1, memory_order_relaxed);
                march_mbox_dispose(msg);          /* Task 14 dtor; counts-only until then */
                free(node);
                return MARCH_SEND_DROPPED;
            case MARCH_MBOX_DROP_OLD: {
                void *old = mbox_pop(target);     /* evict head, then fall through */
                atomic_fetch_add_explicit(&march_stat_counters[MARCH_STAT_MSGS_DROPPED],
                                          1, memory_order_relaxed);
                /* dispose OUTSIDE the lock is nicer but old is fully unlinked;
                 * dispose here is safe: march_mbox_dispose never re-enters mbox. */
                march_mbox_dispose(old);
                break;
            }
            case MARCH_MBOX_BLOCK: {
                /* Scheduler-thread self-deadlock guard: `tl_sched != NULL
                 * && tl_sched->current == NULL` means we are running ON a
                 * scheduler's own OS thread's C stack, but NOT inside any
                 * dispatched green thread -- e.g. march_signal_drain,
                 * called from sched_loop's own control-plane code between
                 * (or before) dispatching green threads, or any future
                 * code that calls march_sched_send directly from that
                 * context. This is a DIFFERENT case from a genuine
                 * foreign OS thread (evloop etc., where tl_sched itself
                 * is NULL) -- mbox_block_register_and_park's `!self`
                 * branch already handles that one correctly with a
                 * sleep-poll, because some OTHER, independent OS thread
                 * (a real scheduler) can still run sched_loop and drain
                 * the mailbox while a foreign thread naps.
                 *
                 * Here, THIS scheduler thread is the one that would need
                 * to run sched_loop's dispatch loop to ever schedule the
                 * receiver and drain this mailbox -- and it can't do that
                 * while parked in nanosleep (or, for a genuine green
                 * thread, in swapcontext) instead of returning to
                 * sched_loop. At MARCH_NUM_SCHEDULERS=1 there is no other
                 * thread at all: sleep-polling here is not a slow path,
                 * it is a PERMANENT, unrecoverable self-deadlock. Even at
                 * N>1 it wastes a whole scheduler thread indefinitely for
                 * no reason -- draining still requires the RECEIVER to be
                 * dispatched, which polling this thread doesn't help.
                 *
                 * Fix: bypass the capacity check entirely and fall
                 * through to the ordinary mbox_push below, exactly like
                 * MARCH_MBOX_DROP_OLD's `break` does after its eviction
                 * (mbox_lock is still held at this point; the shared
                 * epilogue pushes and releases it). This is a rare
                 * control-plane send (a signal-watcher closure delivering
                 * to a BLOCK-limited mailbox), so a bounded one-off
                 * overshoot past `limit` is an acceptable price for
                 * keeping BLOCK's actual promise: the sender can rely on
                 * delivery. Silently dropping instead (DROP_NEW's
                 * behavior) would violate that promise for a policy whose
                 * entire point is "never drop, only wait" -- worse than a
                 * depth spike this thread cannot cause again until it is
                 * next dispatched to run more control-plane code. */
                if (tl_sched && !tl_sched->current) {
                    break;
                }

                /* Registration, the dead-during-registration race, the
                 * park, and self-deregistration on return all live in a
                 * dedicated NOINLINE helper -- see
                 * mbox_block_register_and_park's own comment for why that
                 * split is load-bearing (not just style): the tl_sched
                 * read has to happen inside a function this loop calls
                 * fresh every iteration, or the optimizer can hoist it
                 * out of the loop entirely across the swapcontext
                 * migration. mbox_lock is ALWAYS released by the callee
                 * before it returns, on every path. */
                int r = mbox_block_register_and_park(target);
                if (r == MARCH_SEND_DEAD) {
                    free(node);
                    return MARCH_SEND_DEAD;
                }
                continue;   /* retry from the top */
            }
            default: break;
            }
        }
        mbox_push_node(target, node);
        march_proc_status st = atomic_load_explicit(&target->status, memory_order_acquire);
        mbox_lock_release(target);
        if (st == PROC_WAITING || st == PROC_PARKED) {
            march_sched_wake(target);
        }
        return MARCH_SEND_OK;
    }
}

int64_t march_sched_mbox_count(march_proc *p) {
    if (!p) return 0;
    return atomic_load_explicit(&p->mbox_count, memory_order_relaxed);
}

/* NOINLINE: migration barrier, same rationale as march_sched_yield — a proc
 * that parks here can be woken and re-dispatched on a different OS thread.
 * The body reads tl_sched only BEFORE the swapcontext (safe); noinline
 * guarantees no future same-TU caller can hoist those TLS reads across the
 * switch. */
__attribute__((noinline))
void *march_sched_recv(void) {
    march_proc *p = tl_sched ? tl_sched->current : NULL;
    if (!p) return MARCH_RECV_NO_MSG;

    /* Check the mailbox under lock, then park if truly empty. There used to
     * be an unlocked "fast path" here (`if (p->mailbox) return mbox_pop(p);`)
     * that bypassed the mbox_lock spinlock entirely. mbox_push (called by
     * senders, under the lock) and mbox_pop both read AND WRITE the shared
     * mailbox/mbox_tail/mbox_count linked-list state — the unlocked fast
     * path let a sender's locked mbox_push race against this receiver's
     * unlocked mbox_pop, corrupting the list (confirmed via
     * ThreadSanitizer: this was a genuine data race, not a benign one — it
     * caused intermittent heap corruption and crashes at unrelated,
     * seemingly-random locations under load). The lock is cheap when
     * uncontended (the common case), so always taking it here is the
     * correct, minimal fix. */
    mbox_lock_acquire(p);
    if (p->mailbox) {
        void *msg = mbox_pop(p);
        mbox_wake_send_waiters_if_low(p);
        mbox_lock_release(p);
        return msg;
    }
    /* PROC_PARKED: we're about to call swapcontext but haven't yet saved our
     * context.  Wakers that see PROC_PARKED must spin-wait until the
     * scheduler transitions us to PROC_WAITING (context saved) before
     * pushing us to a run-deque.  Without this, a waker could push us
     * while we are still executing, causing two schedulers to resume the
     * same process concurrently. */
    atomic_store_explicit(&p->status, PROC_PARKED, memory_order_release);
    mbox_lock_release(p);

    MARCH_ASAN_SWITCH_TO_SCHED(p);
    MARCH_TSAN_SWITCH_TO_SCHED(tl_sched);
    swapcontext(&p->ctx, &tl_sched->sched_ctx);
    MARCH_ASAN_SWITCH_DONE(p);
    /* Context is now saved.  The scheduler (sched_loop) transitions us from
     * PROC_PARKED to PROC_WAITING immediately after swapcontext returns on
     * its side, making it safe for a waker to push us to a deque. */

    /* Resumed — a sender woke us.  Pop under lock; return sentinel if empty
     * (the actor was woken for a reason other than a new message, e.g. kill). */
    mbox_lock_acquire(p);
    void *msg;
    if (p->mailbox) {
        msg = mbox_pop(p);
        mbox_wake_send_waiters_if_low(p);
    } else {
        msg = MARCH_RECV_NO_MSG;
    }
    mbox_lock_release(p);
    return msg;
}

void *march_sched_try_recv(void) {
    march_proc *p = tl_sched ? tl_sched->current : NULL;
    if (!p) return NULL;
    mbox_lock_acquire(p);
    void *msg = NULL;
    if (p->mailbox) {
        msg = mbox_pop(p);
        mbox_wake_send_waiters_if_low(p);
    }
    mbox_lock_release(p);
    return msg;
}

int march_sched_try_recv2(void **out) {
    march_proc *p = tl_sched ? tl_sched->current : NULL;
    if (!p) return 0;
    mbox_lock_acquire(p);
    if (!p->mailbox) {          /* node existence, not message value */
        mbox_lock_release(p);
        return 0;
    }
    *out = mbox_pop(p);
    mbox_wake_send_waiters_if_low(p);
    mbox_lock_release(p);
    return 1;
}

/* Grace period (in plain load-spins) before march_sched_wake's PARKED-wait
 * loop backs off to sleeping between polls.  See the comment inside
 * march_sched_wake for why this can't just call march_sched_yield(). */
#define SCHED_WAKE_SPIN_GRACE 4096

void march_sched_wake(march_proc *target) {
    if (!target) return;

    /* Deposit a wake permit BEFORE looking at `status`, so a target that is
     * still PROC_RUNNING (it has passed its own last condition-recheck but
     * has not reached its PROC_PARKED store yet) consumes the permit in
     * march_sched_park_self instead of parking.  seq_cst on this store and
     * the status load below, pairing with park_self's seq_cst exchange and
     * PROC_PARKED store: a Dekker-style store-then-load on two locations,
     * exactly like the task_wait_done pair — release/acquire is not enough
     * (see the store-buffering comment there). */
    atomic_store_explicit(&target->wake_pending, 1, memory_order_seq_cst);

    /* If the process is PROC_PARKED, its context has not yet been saved by
     * swapcontext.  We must wait until the scheduler transitions it to
     * PROC_WAITING before we can push it to a deque; otherwise two
     * scheduler threads would try to resume the same process simultaneously.
     * The transition is normally O(1) so this spin is extremely short — but
     * only if the target's owning OS thread actually gets CPU time from the
     * OS promptly.  Under host oversubscription (more runnable OS threads
     * than cores) that thread can itself be starved for an extended
     * stretch, and this call may run on a scheduler thread (blocking
     * whatever proc it's currently running) or a foreign thread, so we
     * can't cooperatively march_sched_yield() here.  After a grace period
     * of plain spinning, back off to a cheap sleep-based poll (same 1ms
     * idle-sleep sched_loop already uses) instead of spinning at 100% CPU
     * forever — we still cannot give up, since the CAS below requires the
     * target to reach WAITING first. */
    march_proc_status cur;
    int64_t spins = 0;
    do {
        cur = atomic_load_explicit(&target->status, memory_order_seq_cst);
        if (cur == PROC_DEAD || cur == PROC_RUNNABLE || cur == PROC_RUNNING)
            return; /* Not WAITING — the permit above covers the RUNNING case. */
        /* cur is PROC_PARKED or PROC_WAITING: keep looping until WAITING. */
        if (cur == PROC_PARKED) {
            if (spins < SCHED_WAKE_SPIN_GRACE) {
                spins++;
            } else {
                struct timespec ts = { 0, 1000000 }; /* 1ms */
                nanosleep(&ts, NULL);
            }
        }
    } while (cur == PROC_PARKED);

    /* Use CAS to atomically transition WAITING→RUNNABLE so that concurrent
     * senders cannot both succeed and enqueue the process twice.  Exactly one
     * waker wins; only the winner enqueues (single-membership invariant). */
    march_proc_status expected = PROC_WAITING;
    if (!atomic_compare_exchange_strong_explicit(
            &target->status, &expected, PROC_RUNNABLE,
            memory_order_acq_rel, memory_order_acquire))
        return; /* Not WAITING (already woken by another sender). */

    /* We won the race and are about to enqueue the target, so the permit
     * deposited above has been redeemed — clear it, otherwise it would linger
     * and spuriously cancel the target's NEXT park.  A permit deposited by
     * another waker between the CAS and this clear can be erased, but that
     * waker's own CAS necessarily failed (status is already RUNNABLE) and the
     * target is being enqueued regardless: it will run and re-evaluate its
     * wait condition, which is all that waker wanted.  Skipping a park is
     * always safe (every park site loops and rechecks); missing a wake is
     * not. */
    atomic_store_explicit(&target->wake_pending, 0, memory_order_relaxed);

    /* Enqueue to the GLOBAL run queue, never a deque.  Wake may execute on
     * any thread (another scheduler, or a non-scheduler thread such as a
     * network I/O thread); a Chase-Lev deque only tolerates push/pop from
     * its single owner thread.  The old `march_deque_push(&g_scheds[0]...)`
     * branch here was a cross-thread push that could corrupt scheduler 0's
     * `bottom` against its concurrent pop, handing the same proc to both a
     * pop and a steal — the confirmed double-dispatch stack corruption.
     * Even when the waker IS a scheduler thread we route through the global
     * runq ("wake always global"): it keeps the rule single-cased, and every
     * scheduler checks the global queue each dispatch iteration. */
    global_runq_push(target);
}

/* Park the calling green thread until woken.  See the header doc comment
 * for the contract; this mirrors march_sched_recv's park sequence (status
 * PARKED, swapcontext to the owning scheduler) minus the mailbox lock,
 * which recv needs and this generic version does not.
 *
 * NOINLINE, for consistency with every other swapcontext-capable primitive
 * in this file (march_sched_recv, march_sched_recv_until, march_yield) --
 * but note this alone is NOT what fixes Task 8's migration hazard.
 * march_sched_park_self's OWN body only reads tl_sched ONCE, before its
 * swapcontext call, exactly like its siblings; that read was never the
 * problem. The problem (see mbox_block_register_and_park's comment for the
 * full story, including how this was diagnosed) was a tl_sched read living
 * in a CALLER's own loop body, re-executed after calling this function --
 * marking THIS function noinline does nothing about that, since the read
 * that gets hoisted isn't inside here. This attribute is added because
 * march_sched_park_self was the one swapcontext-capable park primitive in
 * this file not already marked noinline (its only pre-Task-8 caller,
 * march_sched_park_self_until, never re-reads tl_sched after calling it,
 * so the gap was latent and harmless there), and there is no reason to
 * leave it as the odd one out now that a second caller exists. */
__attribute__((noinline))
void march_sched_park_self(void) {
    march_proc *p = tl_sched ? tl_sched->current : NULL;
    if (!p) return; /* not running inside the scheduler: nothing to park */

    /* Consume a wake permit instead of parking, if one was deposited while
     * we were still RUNNING (see march_sched_wake and the wake_pending
     * comment in march_scheduler.h).  Returning here is a "spurious wake"
     * from the caller's point of view, which every park site tolerates by
     * looping and re-checking its condition.  This first check is an
     * optimization only; the one that closes the race is the second check
     * below, after the PROC_PARKED store. */
    if (atomic_exchange_explicit(&p->wake_pending, 0, memory_order_seq_cst))
        return;

    /* PROC_PARKED: about to swapcontext but haven't yet saved our context.
     * A waker that sees PROC_PARKED must spin-wait until sched_loop
     * transitions us to PROC_WAITING (context saved) before re-enqueuing
     * us — march_sched_wake already implements exactly that handshake. */
    atomic_store_explicit(&p->status, PROC_PARKED, memory_order_seq_cst);

    /* Re-check the permit AFTER publishing PROC_PARKED — the half that makes
     * the handshake airtight.  A waker landing between the exchange above
     * and the PROC_PARKED store still reads `status` as PROC_RUNNING and
     * early-returns, but its permit deposit (seq_cst store before its
     * seq_cst status load) and our PROC_PARKED store (seq_cst before this
     * seq_cst exchange) interlock like any Dekker pair: either it sees our
     * PARKED store and takes the spin-to-WAITING path, or we see its permit
     * here and un-park.  Un-parking means restoring PROC_RUNNING, which is
     * race-free: only sched_loop moves PARKED -> WAITING, and only after
     * swapcontext returns control to it, which has not happened.  A waker
     * spinning on our PROC_PARKED observes PROC_RUNNING next iteration and
     * returns without enqueuing — correct, since we never parked. */
    if (atomic_exchange_explicit(&p->wake_pending, 0, memory_order_seq_cst)) {
        atomic_store_explicit(&p->status, PROC_RUNNING, memory_order_seq_cst);
        return;
    }

    MARCH_ASAN_SWITCH_TO_SCHED(p);
    MARCH_TSAN_SWITCH_TO_SCHED(tl_sched);
    swapcontext(&p->ctx, &tl_sched->sched_ctx);
    MARCH_ASAN_SWITCH_DONE(p);
    /* Resumed: some waker called march_sched_wake(p), which CAS'd us
     * WAITING->RUNNABLE; sched_loop's dispatch CAS'd RUNNABLE->RUNNING
     * before swapping back into our context.  Status is now RUNNING. */
}

/* ── Timers: binary min-heap of (deadline, proc) ─────────────────────── */
/* No cancellation by design: a stale fire is a spurious wake, which every
 * park site already tolerates by looping; procs are leak-don't-free so the
 * proc pointer is always dereferenceable (Task 12 recycles stacks ONLY).
 * State (g_timer_mu/g_timer_heap/g_timer_len/g_timer_cap) is forward-declared
 * near the other global state, above, so march_sched_init can reset it. */

int64_t march_now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void timer_heap_push(int64_t deadline_ms, march_proc *p) {
    pthread_mutex_lock(&g_timer_mu);
    if (g_timer_len == g_timer_cap) {
        g_timer_cap = g_timer_cap ? g_timer_cap * 2 : 64;
        g_timer_heap = realloc(g_timer_heap,
                               (size_t)g_timer_cap * sizeof(march_timer_ent));
        if (!g_timer_heap) { fputs("march_sched: OOM (timer)\n", stderr); abort(); }
    }
    int i = g_timer_len++;
    g_timer_heap[i] = (march_timer_ent){ deadline_ms, p };
    while (i > 0) {
        int par = (i - 1) / 2;
        if (g_timer_heap[par].deadline_ms <= g_timer_heap[i].deadline_ms) break;
        march_timer_ent t = g_timer_heap[par];
        g_timer_heap[par] = g_timer_heap[i];
        g_timer_heap[i] = t;
        i = par;
    }
    pthread_mutex_unlock(&g_timer_mu);
}

/* Pop every expired entry and wake its proc. Called from preempt_daemon. */
static void timer_service(int64_t now_ms) {
    for (;;) {
        march_proc *victim = NULL;
        pthread_mutex_lock(&g_timer_mu);
        if (g_timer_len > 0 && g_timer_heap[0].deadline_ms <= now_ms) {
            victim = g_timer_heap[0].proc;
            g_timer_heap[0] = g_timer_heap[--g_timer_len];
            int i = 0;
            for (;;) {
                int l = 2*i+1, r = 2*i+2, m = i;
                if (l < g_timer_len && g_timer_heap[l].deadline_ms < g_timer_heap[m].deadline_ms) m = l;
                if (r < g_timer_len && g_timer_heap[r].deadline_ms < g_timer_heap[m].deadline_ms) m = r;
                if (m == i) break;
                march_timer_ent t = g_timer_heap[m];
                g_timer_heap[m] = g_timer_heap[i];
                g_timer_heap[i] = t;
                i = m;
            }
        }
        pthread_mutex_unlock(&g_timer_mu);
        if (!victim) return;
        march_sched_wake(victim);   /* outside the lock: wake can spin */
    }
}

/* Definition of march_sched_park_self_until is below, after g_preempt_active
 * is declared (Phase 5A) — the fallback path needs to read that flag. */

/* ── Phase 5A: signal-based preemption ───────────────────────────────── */

/*
 * Design
 * ──────
 * A single daemon pthread wakes every MARCH_QUANTUM_US microseconds and
 * sends SIGUSR1 to each active scheduler thread via pthread_kill().  SIGUSR1
 * is delivered to the target thread, so the handler runs in that thread's
 * context and can safely write to its own march_tls_reductions (_Thread_local).
 *
 * The handler zeroes march_tls_reductions.  The scheduler thread's next call
 * to march_sched_tick() (or march_yield_from_compiled()) sees the zero budget
 * and calls march_sched_yield(), giving the green-thread scheduler a chance to
 * run another process.
 *
 * Limitations / known EINTR exposure
 * ───────────────────────────────────
 * Delivering SIGUSR1 to a thread that is blocked in a slow syscall (read,
 * nanosleep, etc.) will interrupt it with EINTR.  Callers of blocking syscalls
 * inside green threads must handle EINTR (retry loop).  This is standard POSIX
 * practice and is documented as a known trade-off of signal-based preemption.
 *
 * We install SIGUSR1 with SA_RESTART where the kernel supports it; this
 * auto-restarts interruptible syscalls on Linux.  On macOS SA_RESTART does not
 * cover all syscalls, so green-thread code that calls blocking I/O must loop
 * on EINTR.
 */

static _Atomic int  g_preempt_active = 0;
static pthread_t    g_preempt_thread;

/* noinline: same migration-barrier rationale as march_sched_yield above —
 * this function contains a swapcontext-capable call (march_sched_park_self),
 * so any caller looping around it (e.g. march_actor_call's deadline loop)
 * must not have its TLS reads hoisted across the switch by the optimizer. */
__attribute__((noinline))
int march_sched_park_self_until(int64_t deadline_ms) {
    march_proc *p = tl_sched ? tl_sched->current : NULL;
    if (!p) return MARCH_PARK_WOKEN;
    if (march_now_ms() >= deadline_ms) return MARCH_PARK_TIMEOUT;
    if (!atomic_load_explicit(&g_preempt_active, memory_order_acquire)) {
        /* No timer service running: degrade to plain yield so the caller's
         * condition/deadline loop still makes progress. */
        march_sched_yield();
        return MARCH_PARK_WOKEN;
    }
    timer_heap_push(deadline_ms, p);
    march_sched_park_self();
    return (march_now_ms() >= deadline_ms) ? MARCH_PARK_TIMEOUT
                                           : MARCH_PARK_WOKEN;
}

/* noinline: same migration-barrier rationale as march_sched_recv/
 * march_sched_park_self_until above — this function contains a
 * swapcontext-capable call, so no caller may have its TLS reads hoisted
 * across the switch. */
__attribute__((noinline))
void *march_sched_recv_until(int64_t deadline_ms) {
    march_proc *p = tl_sched ? tl_sched->current : NULL;
    if (!p) return MARCH_RECV_NO_MSG;

    /* Hold mbox_lock across BOTH the emptiness check and the PROC_PARKED
     * store — exactly march_sched_recv's discipline, and the fix for the
     * bug this primitive replaces: pairing march_sched_try_recv2 (which
     * takes and releases mbox_lock on its own) with
     * march_sched_park_self_until (which stores PROC_PARKED with no lock
     * at all) left a window between the two calls where march_sched_send
     * could observe this process as PROC_RUNNING — its wake is gated
     * `if (st == PROC_WAITING || st == PROC_PARKED)` — and skip the wake
     * entirely, so a reply landing in that window was only ever picked up
     * when the deadline timer fired. Locking across both steps here closes
     * that window: march_sched_send cannot observe PROC_RUNNING while
     * mbox_push has already happened but our PROC_PARKED store has not. */
    mbox_lock_acquire(p);
    if (p->mailbox) {
        void *msg = mbox_pop(p);
        mbox_wake_send_waiters_if_low(p);
        mbox_lock_release(p);
        return msg;
    }
    if (march_now_ms() >= deadline_ms) {
        mbox_lock_release(p);
        return MARCH_RECV_NO_MSG;
    }
    if (!atomic_load_explicit(&g_preempt_active, memory_order_acquire)) {
        /* No timer service running: degrade to plain yield (mirrors
         * march_sched_park_self_until's fallback) so the caller's
         * deadline loop still makes progress instead of parking with no
         * one able to service the timer heap. */
        mbox_lock_release(p);
        march_sched_yield();
        return MARCH_RECV_NO_MSG;
    }

    /* Register the deadline BEFORE releasing mbox_lock/parking, still
     * under the lock.
     *
     * Lock order: this acquires g_timer_mu (inside timer_heap_push) while
     * holding mbox_lock — order mbox_lock -> g_timer_mu. The only other
     * g_timer_mu holder is timer_service (called from preempt_daemon),
     * which takes g_timer_mu, pops expired entries, UNLOCKS g_timer_mu,
     * and only then calls march_sched_wake(victim) — march_sched_wake
     * itself never touches mbox_lock (it only reads/writes target->status
     * and target->wake_pending and pushes to the global run queue). So no
     * path ever holds g_timer_mu while trying to acquire mbox_lock; the
     * reverse order (g_timer_mu -> mbox_lock) never occurs, so this cannot
     * deadlock against timer_service. */
    timer_heap_push(deadline_ms, p);
    atomic_store_explicit(&p->status, PROC_PARKED, memory_order_release);
    mbox_lock_release(p);

    MARCH_ASAN_SWITCH_TO_SCHED(p);
    MARCH_TSAN_SWITCH_TO_SCHED(tl_sched);
    swapcontext(&p->ctx, &tl_sched->sched_ctx);
    MARCH_ASAN_SWITCH_DONE(p);
    /* Context is now saved.  The scheduler (sched_loop) transitions us from
     * PROC_PARKED to PROC_WAITING immediately after swapcontext returns on
     * its side, making it safe for a waker to push us to a deque. */

    mbox_lock_acquire(p);
    void *msg;
    if (p->mailbox) {
        msg = mbox_pop(p);
        mbox_wake_send_waiters_if_low(p);
    } else {
        msg = MARCH_RECV_NO_MSG;
    }
    mbox_lock_release(p);
    return msg;
}

/* SIGUSR1 handler: zero the local reduction counter.  The handler is
 * registered with SA_RESTART so that interruptible syscalls are retried
 * automatically on platforms that support it. */
static void march_preempt_signal_handler(int sig) {
    (void)sig;
    /* Both writes are async-signal-safe (volatile scalar stores).
     * march_preempt_request is what compiled code actually polls;
     * march_tls_reductions is kept in sync so task_reductions() and any
     * interpreter-side budget logic still see a spent quantum. */
    march_preempt_request = 1;
    march_tls_reductions  = 0;
}

static void *preempt_daemon(void *arg) {
    (void)arg;
    struct timespec ts;
    ts.tv_sec  = 0;
    ts.tv_nsec = (long)MARCH_QUANTUM_US * 1000L;   /* µs → ns */

    while (atomic_load_explicit(&g_preempt_active, memory_order_acquire)) {
        nanosleep(&ts, NULL);   /* sleeps until MARCH_QUANTUM_US has elapsed */

        if (!atomic_load_explicit(&g_preempt_active, memory_order_acquire))
            break;

        /* Signal every active scheduler thread. */
        for (int i = 0; i < g_num_scheds; i++) {
            if (atomic_load_explicit(&g_scheds[i].running, memory_order_acquire)
                    && g_scheds[i].thread) {
                pthread_kill(g_scheds[i].thread, SIGUSR1);
            }
        }

        timer_service(march_now_ms());
    }
    return NULL;
}

void march_sched_preempt_start(void) {
    /* Install the SIGUSR1 handler once, process-wide. */
    struct sigaction sa;
    sa.sa_handler = march_preempt_signal_handler;
    sigemptyset(&sa.sa_mask);
    /* SA_ONSTACK: deliver on the per-thread alternate signal stack.  Scheduler
     * threads run green threads on lazily-grown, guard-page-protected stacks; a
     * green thread's SP can sit right above a PROT_NONE guard page.  Without
     * SA_ONSTACK the kernel pushes the (large, FP-bearing) signal frame onto
     * that green stack, faulting into the guard page during signal delivery —
     * an unrecoverable crash on glibc/Linux (macOS masks it by mapping the
     * frame differently).  Delivering on the alt stack (set up per thread in
     * sched_loop) keeps preemption off the green stack. */
    sa.sa_flags = SA_RESTART | SA_ONSTACK;
    if (sigaction(SIGUSR1, &sa, NULL) != 0) {
        perror("march_sched: sigaction(SIGUSR1)");
        return;   /* preemption unavailable but scheduler still works */
    }

    atomic_store_explicit(&g_preempt_active, 1, memory_order_release);
    if (pthread_create(&g_preempt_thread, NULL, preempt_daemon, NULL) != 0) {
        perror("march_sched: pthread_create (preempt daemon)");
        atomic_store_explicit(&g_preempt_active, 0, memory_order_relaxed);
    }
}

void march_sched_preempt_stop(void) {
    if (!atomic_load_explicit(&g_preempt_active, memory_order_acquire))
        return;
    atomic_store_explicit(&g_preempt_active, 0, memory_order_release);
    /* Wake the daemon so it does not sleep through the entire remaining quantum. */
    pthread_kill(g_preempt_thread, SIGUSR1);
    pthread_join(g_preempt_thread, NULL);
}

/* ── Phase 5B: cancellation tokens ──────────────────────────────────── */

march_cancel_token *march_cancel_token_new(void) {
    march_cancel_token *tok = (march_cancel_token *)malloc(sizeof(march_cancel_token));
    if (!tok) {
        fputs("march_cancel_token: OOM\n", stderr);
        abort();
    }
    atomic_init(&tok->cancelled, 0);
    atomic_init(&tok->refcount, 1);
    return tok;
}

void march_cancel_token_cancel(march_cancel_token *tok) {
    if (!tok) return;
    atomic_store_explicit(&tok->cancelled, 1, memory_order_release);
}

int64_t march_cancel_token_is_cancelled(march_cancel_token *tok) {
    if (!tok) return 0;
    return (int64_t)atomic_load_explicit(&tok->cancelled, memory_order_acquire);
}

void march_cancel_token_ref(march_cancel_token *tok) {
    if (!tok) return;
    atomic_fetch_add_explicit(&tok->refcount, 1, memory_order_relaxed);
}

void march_cancel_token_unref(march_cancel_token *tok) {
    if (!tok) return;
    int prev = atomic_fetch_sub_explicit(&tok->refcount, 1, memory_order_acq_rel);
    if (prev == 1) {
        free(tok);
    }
}

/*
 * Cancel-aware process descriptor extension.
 *
 * We store the cancel token pointer in the proc's arg field is not possible
 * (arg is already used for the user function's argument).  Instead, we use a
 * thin wrapper: the real fn/arg are stored in a heap-allocated
 * march_cancel_wrap, which is passed as the arg to a trampoline.
 */
typedef struct {
    void               (*user_fn)(void *);
    void                *user_arg;
    march_cancel_token  *token;
} march_cancel_wrap;

static void cancel_trampoline(void *raw) {
    march_cancel_wrap *w = (march_cancel_wrap *)raw;
    void (*user_fn)(void *) = w->user_fn;
    void  *user_arg         = w->user_arg;
    march_cancel_token *tok = w->token;
    free(w);   /* wrapper no longer needed after we've unpacked it */

    /* Check immediately before starting — the scope may have already been
     * cancelled between spawn time and first execution. */
    if (tok && march_cancel_token_is_cancelled(tok)) {
        march_cancel_token_unref(tok);
        return;
    }

    user_fn(user_arg);

    if (tok) march_cancel_token_unref(tok);
}

march_proc *march_sched_spawn_with_cancel(void (*fn)(void *), void *arg,
                                          march_cancel_token *tok) {
    march_cancel_wrap *w = (march_cancel_wrap *)malloc(sizeof(march_cancel_wrap));
    if (!w) {
        fputs("march_sched_spawn_with_cancel: OOM\n", stderr);
        return NULL;
    }
    w->user_fn  = fn;
    w->user_arg = arg;
    w->token    = tok;
    if (tok) march_cancel_token_ref(tok);   /* wrap holds a reference */

    return march_sched_spawn(cancel_trampoline, w);
}
