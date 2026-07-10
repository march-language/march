/* march_scheduler.c — M:N multi-thread green-thread scheduler with
 * work-stealing deques and mailbox message passing.
 *
 * Design
 * ──────
 * N OS threads each run a scheduler loop.  Each scheduler owns a Chase-Lev
 * work-stealing deque of READY processes.  The owner pushes/pops from the
 * bottom (LIFO for cache locality).  Idle schedulers steal from others'
 * tops (FIFO for load balance).
 *
 * Scheduling policy: per-thread LIFO with work-stealing.
 *   1. Pop the next READY process from the local deque.
 *   2. If empty, attempt to steal from a random other scheduler.
 *   3. If stolen or local: reset reduction budget, swapcontext into process.
 *   4. On return: if READY, push back to local deque; if DEAD, free.
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

/* ── Global state ─────────────────────────────────────────────────────── */

static march_scheduler  g_scheds[MARCH_NUM_SCHEDULERS + 1];
static int              g_num_scheds = 0;
static _Atomic int64_t  g_next_pid   = 0;
static _Atomic int      g_all_done       = 0;
static _Atomic int64_t  g_live_procs     = 0;
static _Atomic int      g_sched_shutdown = 0;

/* Live procs that are NOT daemons (main, task procs).  When this reaches 0
 * after shutdown is requested, only actor recv loops remain — the idle
 * branch of sched_loop then wakes parked daemons so they exit their loops
 * (recv returns MARCH_RECV_NO_MSG) and the scheduler can drain to 0. */
static _Atomic int64_t  g_live_nondaemon = 0;

/* Lock-free stack of procs enqueued from outside their target scheduler
 * thread: both foreign spawns (march_sched_spawn from a non-scheduler
 * thread) and foreign wakes (march_sched_wake called for a target whose
 * owner is not the calling thread).  Chase-Lev deques are owner-push-only,
 * so any push from another thread must go through this stack instead;
 * scheduler threads claim from it via try_claim_external(), checked every
 * sched_loop iteration.  Using march_proc::next as the intrusive link. */
static _Atomic(march_proc *) g_ext_spawn_head = NULL;

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
 * If the fault is outside any known stack reservation (real bad-pointer), we
 * restore the default SIGSEGV handler and re-raise so the program terminates
 * with the usual signal.
 */
static void march_sigsegv_handler(int sig, siginfo_t *info, void *uctx) {
    (void)uctx;

    /* A lazy-stack-growth fault is a protection fault on a PROT_NONE guard
     * page.  On Linux that is delivered as SIGSEGV with si_code SEGV_ACCERR.
     * On macOS the Mach exception EXC_BAD_ACCESS / KERN_PROTECTION_FAILURE is
     * translated to SIGBUS (not SIGSEGV), with a BUS_* si_code — so the old
     * `SIGSEGV && SEGV_ACCERR` gate rejected every macOS stack-growth fault,
     * leaving the thread to die with SIGBUS as soon as a green stack grew past
     * the initial 4 KiB.  Accept SIGBUS regardless of si_code; the address-range
     * check below is the real safety gate.  For SIGSEGV keep requiring
     * SEGV_ACCERR so genuine invalid-address faults still terminate. */
    if (sig == SIGSEGV && info->si_code != SEGV_ACCERR) goto fatal;

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
    /* Not a stack-growth fault — restore the default handler for the signal
     * that actually fired and re-raise it so the program terminates normally. */
    {
        struct sigaction sa;
        sa.sa_handler = SIG_DFL;
        sigemptyset(&sa.sa_mask);
        sa.sa_flags = 0;
        sigaction(sig, &sa, NULL);
        raise(sig);
    }
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

static void mbox_push(march_proc *p, void *msg) {
    march_mbox_node *node = (march_mbox_node *)malloc(sizeof(march_mbox_node));
    if (!node) { fputs("march_sched: OOM (mbox node)\n", stderr); abort(); }
    node->msg  = msg;
    node->next = NULL;
    if (p->mbox_tail) {
        p->mbox_tail->next = node;
    } else {
        p->mailbox = node;
    }
    p->mbox_tail = node;
    p->mbox_count++;
}

static void *mbox_pop(march_proc *p) {
    march_mbox_node *node = p->mailbox;
    if (!node) return NULL;
    void *msg = node->msg;
    p->mailbox = node->next;
    if (!p->mailbox) p->mbox_tail = NULL;
    p->mbox_count--;
    free(node);
    return msg;
}

/* ── Trampoline ───────────────────────────────────────────────────────── */

/* makecontext() accepts only int-sized variadic arguments.  We split the
 * 64-bit proc pointer into high/low 32-bit halves for portability. */
static void proc_trampoline(int arg_hi, int arg_lo) {
    /* Reassemble the pointer without sign-extension hazards. */
    uintptr_t addr = ((uintptr_t)(uint32_t)arg_hi << 32)
                   | ((uintptr_t)(uint32_t)arg_lo);
    march_proc *proc = (march_proc *)(void *)addr;

    /* Run the user-supplied function. */
    proc->fn(proc->arg);

    /* Function returned — mark dead and hand control back to the scheduler. */
    atomic_store_explicit(&proc->status, PROC_DEAD, memory_order_release);
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
    atomic_store_explicit(&g_ext_spawn_head, (march_proc *)NULL, memory_order_relaxed);
    memset(g_proc_registry, 0, sizeof(g_proc_registry));
    g_proc_count = 0;

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
    p->status     = PROC_READY;
    p->priority   = PRIO_NORMAL;
    p->reductions = MARCH_REDUCTION_BUDGET;
    p->fn         = fn;
    p->arg        = arg;
    p->mailbox    = NULL;
    p->mbox_tail  = NULL;
    p->mbox_count = 0;
    atomic_init(&p->mbox_lock, 0);
    p->owner_sched = NULL;

    /* Allocate the stack: reserve MARCH_STACK_MAX virtual memory, make only
     * the top MARCH_STACK_INITIAL bytes read/write initially.  The rest grows
     * on demand via the SIGSEGV handler. */
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

    /* Push to the local deque if called from a scheduler thread.
     * From non-scheduler threads (e.g. main thread), push to a lock-free
     * external stack instead — pushing to a Chase-Lev deque from a thread
     * that is not the deque's owner races with the owner's pop. */
    if (tl_sched) {
        march_deque_push(&tl_sched->local_queue, p);
    } else {
        march_proc *old_head;
        do {
            old_head = atomic_load_explicit(&g_ext_spawn_head, memory_order_relaxed);
            p->next  = old_head;
        } while (!atomic_compare_exchange_weak_explicit(
                     &g_ext_spawn_head, &old_head, p,
                     memory_order_release, memory_order_relaxed));
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
                && q->mbox_count == 0) {
            march_sched_wake(q);
            woken++;
        }
    }
    pthread_mutex_unlock(&g_registry_mu);
    return woken;
}

/* Claim one proc pushed by a non-scheduler thread (foreign spawn OR foreign
 * wake).  Chase-Lev deques are owner-push-only, so foreign threads enqueue
 * here and scheduler threads claim from it.  Checked every loop iteration
 * (one acquire load when empty) so foreign work is not starved while local
 * deques stay busy. */
static march_proc *try_claim_external(void) {
    march_proc *ext = atomic_load_explicit(&g_ext_spawn_head, memory_order_acquire);
    while (ext) {
        march_proc *nxt = ext->next;
        if (atomic_compare_exchange_weak_explicit(
                &g_ext_spawn_head, &ext, nxt,
                memory_order_acq_rel, memory_order_acquire)) {
            return ext;  /* claimed */
        }
        /* CAS failed; ext was refreshed by the failed CAS — retry. */
    }
    return NULL;
}

static void sched_loop(march_scheduler *sched) {
    /* Set up the per-thread alternate signal stack before running any green
     * threads.  The SIGSEGV handler for lazy stack growth requires SA_ONSTACK
     * so it can run even when the green thread's stack is exhausted. */
    setup_alt_stack();

    tl_sched = sched;
    sched->running = 1;
    unsigned int steal_seed = (unsigned int)sched->id;
    /* When the previous task cooperatively yielded (PROC_READY after running),
     * try to steal work from another scheduler before re-running the yielded
     * task.  Without this, all workers can deadlock in a LIFO spin where each
     * pops its own yielded spin-waiter instead of running the leaf tasks that
     * would unblock them. */
    int last_yielded = 0;

    while (!atomic_load_explicit(&g_all_done, memory_order_acquire)) {
        /* Foreign spawns/wakes first: they have no other path onto a
         * scheduler, and under load the old idle-only check starved them
         * (a busy worker never reached the idle branch, so a foreign wake
         * could sit on the external stack indefinitely). */
        march_proc *p = try_claim_external();

        /* Single-scheduler: use steal (FIFO) for fairness and compatibility.
         * Multi-scheduler: use pop (LIFO) for cache locality; steal from others.
         * Exception: if the previous task yielded, try to steal first to avoid
         * the LIFO livelock described above. */
        if (!p) {
            if (g_num_scheds <= 1) {
                p = (march_proc *)march_deque_steal(&sched->local_queue);
            } else if (last_yielded) {
                /* Yielded task goes back; steal from others to make progress. */
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
                continue;  /* woken procs are in our deque — run them now */
            /* No runnable process: sleep 1ms to avoid burning CPU at idle.
             * sched_yield() alone causes ~99% CPU on a waiting server. */
            struct timespec idle_sleep = { 0, 1000000 }; /* 1ms */
            nanosleep(&idle_sleep, NULL);
            continue;
        }

        atomic_store_explicit(&p->status, PROC_RUNNING, memory_order_release);
        p->reductions   = MARCH_REDUCTION_BUDGET;
        p->owner_sched  = sched;
        sched->current  = p;

        swapcontext(&sched->sched_ctx, &p->ctx);

        sched->current = NULL;

        march_proc_status st = atomic_load_explicit(&p->status, memory_order_acquire);
        if (st == PROC_READY) {
            march_deque_push(&sched->local_queue, p);
            last_yielded = 1;
        } else if (st == PROC_PARKED) {
            /* The process called march_sched_recv's slow path: it stored
             * PROC_PARKED then immediately called swapcontext.  Now that
             * swapcontext has returned here, the process's ucontext is fully
             * saved in p->ctx.  Transition to PROC_WAITING so that any
             * waker that was spin-waiting on PROC_PARKED can now safely CAS
             * WAITING→READY and push p to a deque without risk of another
             * thread resuming a process whose context isn't saved yet. */
            atomic_store_explicit(&p->status, PROC_WAITING, memory_order_release);
        } else if (st == PROC_DEAD) {
            registry_remove(p);
            atomic_fetch_sub_explicit(&g_live_procs, 1, memory_order_release);
            if (!p->is_daemon)
                atomic_fetch_sub_explicit(&g_live_nondaemon, 1, memory_order_release);
            munmap(p->stack_mmap_base, p->stack_alloc);
            free(p);
        }
        /* PROC_WAITING: process parked itself; a wakeup call re-enqueues it. */
    }

    sched->running = 0;
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

    /* Single-scheduler fast path: no threads needed. */
    if (g_num_scheds <= 1) {
        g_scheds[0].thread = pthread_self();
        sched_loop(&g_scheds[0]);
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

    march_sched_preempt_stop();
}

void march_sched_yield(void) {
    if (!tl_sched || !tl_sched->current) return;
    march_proc *p = tl_sched->current;
    atomic_store_explicit(&p->status, PROC_READY, memory_order_release);
    swapcontext(&p->ctx, &tl_sched->sched_ctx);
    /* Execution resumes here after the scheduler re-schedules us. */
}

void march_sched_wait_idle(void) {
    if (!tl_sched || !tl_sched->current) return;
    march_proc *self = tl_sched->current;
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
            if (st == PROC_READY || st == PROC_RUNNING || st == PROC_PARKED) {
                busy = 1;
            } else if (st == PROC_WAITING && q->mbox_count > 0) {
                /* Message enqueued but wake not yet delivered — transient. */
                busy = 1;
            }
        }
        pthread_mutex_unlock(&g_registry_mu);
        if (!busy) return;
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

/* Thread-local reduction budget for LLVM-compiled code.  Initialised to the
 * full budget so the first quantum runs immediately without an extra reset.
 * volatile: zeroed by the SIGUSR1 preemption handler (see Phase 5A). */
volatile _Thread_local int64_t march_tls_reductions = MARCH_REDUCTION_BUDGET;

void march_yield_from_compiled(void) {
    /* Refill the budget before yielding so the process gets a fresh quantum
     * when it is rescheduled.  Do this unconditionally — if we are not inside
     * a scheduler context the yield below is a no-op, but the counter should
     * still be valid for future use. */
    march_tls_reductions = MARCH_REDUCTION_BUDGET;
    march_sched_yield();
}

int march_sched_send(march_proc *target, void *msg) {
    if (!target || atomic_load_explicit(&target->status, memory_order_acquire) == PROC_DEAD)
        return -1;
    mbox_lock_acquire(target);
    mbox_push(target, msg);
    march_proc_status st = atomic_load_explicit(&target->status, memory_order_acquire);
    mbox_lock_release(target);
    if (st == PROC_WAITING || st == PROC_PARKED) {
        march_sched_wake(target);
    }
    return 0;
}

void *march_sched_recv(void) {
    march_proc *p = tl_sched ? tl_sched->current : NULL;
    if (!p) return MARCH_RECV_NO_MSG;

    /* Fast path: check node existence, not message value.
     * March zero-arg constructors are valid msg=NULL (inttoptr i64 0), so we
     * MUST NOT use "if (msg)" to detect "has message" — we use the node ptr. */
    if (p->mailbox) return mbox_pop(p);

    /* Slow path: check mailbox under lock, then park if truly empty. */
    mbox_lock_acquire(p);
    if (p->mailbox) {
        void *msg = mbox_pop(p);
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

    swapcontext(&p->ctx, &tl_sched->sched_ctx);
    /* Context is now saved.  The scheduler (sched_loop) transitions us from
     * PROC_PARKED to PROC_WAITING immediately after swapcontext returns on
     * its side, making it safe for a waker to push us to a deque. */

    /* Resumed — a sender woke us.  Pop under lock; return sentinel if empty
     * (the actor was woken for a reason other than a new message, e.g. kill). */
    mbox_lock_acquire(p);
    void *msg;
    if (p->mailbox) {
        msg = mbox_pop(p);
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
    void *msg = mbox_pop(p);
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
    mbox_lock_release(p);
    return 1;
}

void march_sched_wake(march_proc *target) {
    if (!target) return;

    /* If the process is PROC_PARKED, its context has not yet been saved by
     * swapcontext.  We must wait until the scheduler transitions it to
     * PROC_WAITING before we can push it to a deque; otherwise two
     * scheduler threads would try to resume the same process simultaneously.
     * The transition is O(1) so this spin is normally extremely short — but
     * it is not bounded: if the OS preempts the parking thread between its
     * PROC_PARKED store and its swapcontext call, a waker that busy-spins
     * here without yielding can starve the parking thread of the CPU time it
     * needs to reach swapcontext, livelocking both threads under thread
     * oversubscription (see specs/plans/2026-07-09-foreign-thread-actor-bridge.md,
     * "Diagnosis findings (Task 1)"). sched_yield() gives the parking thread
     * a chance to run. */
    march_proc_status cur;
    for (;;) {
        cur = atomic_load_explicit(&target->status, memory_order_acquire);
        if (cur == PROC_DEAD || cur == PROC_READY || cur == PROC_RUNNING)
            return; /* Not WAITING — no need to wake. */
        if (cur == PROC_WAITING) break;
        /* cur is PROC_PARKED: yield so the parking thread can get CPU time
         * and reach swapcontext — a bare spin here livelocks under thread
         * oversubscription. */
        sched_yield();
    }

    /* Use CAS to atomically transition WAITING→READY so that concurrent
     * senders cannot both succeed and push the process to the deque twice. */
    march_proc_status expected = PROC_WAITING;
    if (!atomic_compare_exchange_strong_explicit(
            &target->status, &expected, PROC_READY,
            memory_order_acq_rel, memory_order_acquire))
        return; /* Not WAITING (already woken by another sender). */
    if (tl_sched) {
        /* Called from a scheduler thread (possibly not target's owner —
         * that's fine, any scheduler thread may push onto its OWN local
         * deque; Chase-Lev only requires the push to come from the deque's
         * owner, not from target's owner). */
        march_deque_push(&tl_sched->local_queue, target);
    } else {
        /* Foreign thread (evloop pthread, FFI thread, main before scheduler):
         * deques are owner-push-only, so push onto the external ready stack.
         * Same protocol as the foreign-spawn path in sched_spawn_common. */
        march_proc *old_head;
        do {
            old_head = atomic_load_explicit(&g_ext_spawn_head, memory_order_relaxed);
            target->next = old_head;
        } while (!atomic_compare_exchange_weak_explicit(
                     &g_ext_spawn_head, &old_head, target,
                     memory_order_release, memory_order_relaxed));
    }
}

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

/* SIGUSR1 handler: zero the local reduction counter.  The handler is
 * registered with SA_RESTART so that interruptible syscalls are retried
 * automatically on platforms that support it. */
static void march_preempt_signal_handler(int sig) {
    (void)sig;
    march_tls_reductions = 0;
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
            if (g_scheds[i].running && g_scheds[i].thread) {
                pthread_kill(g_scheds[i].thread, SIGUSR1);
            }
        }
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
