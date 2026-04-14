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
 * relying on the deprecated extension path. */
#ifndef _XOPEN_SOURCE
#  define _XOPEN_SOURCE 700
#endif
#if defined(__APPLE__) && !defined(_DARWIN_C_SOURCE)
#  define _DARWIN_C_SOURCE
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
static _Atomic int      g_all_done   = 0;
static _Atomic int64_t  g_live_procs = 0;

static _Thread_local march_scheduler *tl_sched = NULL;

/* Cached OS page size — initialised once in march_sched_init().
 * Used by the SIGSEGV handler (sysconf is not async-signal-safe). */
static size_t g_page_size = 0;

/* ── Process registry (for march_sched_find) ──────────────────────────── */

#define MARCH_MAX_PROCS 65536

static march_proc *g_proc_registry[MARCH_MAX_PROCS];
static int64_t     g_proc_count = 0;

static void registry_add(march_proc *p) {
    if (p->pid < MARCH_MAX_PROCS) {
        g_proc_registry[p->pid] = p;
    }
    g_proc_count++;
}

static void registry_remove(march_proc *p) {
    if (p->pid < MARCH_MAX_PROCS) {
        g_proc_registry[p->pid] = NULL;
    }
    g_proc_count--;
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

static _Thread_local char *tl_alt_stack = NULL;

static void setup_alt_stack(void) {
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
    (void)sig;
    (void)uctx;

    /* Only handle permission faults (SEGV_ACCERR), not invalid-address faults. */
    if (info->si_code != SEGV_ACCERR) goto fatal;

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
    /* Not a stack-growth fault — restore the default handler and re-raise. */
    {
        struct sigaction sa;
        sa.sa_handler = SIG_DFL;
        sigemptyset(&sa.sa_mask);
        sa.sa_flags = 0;
        sigaction(SIGSEGV, &sa, NULL);
        raise(SIGSEGV);
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
    atomic_store_explicit(&g_all_done, 0, memory_order_relaxed);
    atomic_store_explicit(&g_live_procs, 0, memory_order_relaxed);
    memset(g_proc_registry, 0, sizeof(g_proc_registry));
    g_proc_count = 0;

    g_num_scheds = MARCH_NUM_SCHEDULERS > 0 ? MARCH_NUM_SCHEDULERS : 1;
    for (int i = 0; i < g_num_scheds; i++) {
        memset(&g_scheds[i], 0, sizeof(march_scheduler));
        march_deque_init(&g_scheds[i].local_queue);
        g_scheds[i].id = i;
    }

    /* Install the SIGSEGV handler that enables lazy stack growth.
     * Idempotent: a CAS inside ensures it runs at most once per process. */
    install_stack_growth_handler();
}

march_proc *march_sched_spawn(void (*fn)(void *), void *arg) {
    march_proc *p = (march_proc *)calloc(1, sizeof(march_proc));
    if (!p) {
        fputs("march_sched: out of memory (process alloc)\n", stderr);
        return NULL;
    }

    p->pid        = atomic_fetch_add_explicit(&g_next_pid, 1, memory_order_relaxed);
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

    /* Push to the local deque if called from a scheduler thread, otherwise
     * round-robin across schedulers by PID. */
    if (tl_sched) {
        march_deque_push(&tl_sched->local_queue, p);
    } else if (g_num_scheds > 0) {
        int target = (int)(p->pid % g_num_scheds);
        march_deque_push(&g_scheds[target].local_queue, p);
    } else {
        march_deque_push(&g_scheds[0].local_queue, p);
    }

    return p;
}

/* ── Per-thread scheduler loop with work-stealing ────────────────────── */

static void sched_loop(march_scheduler *sched) {
    /* Set up the per-thread alternate signal stack before running any green
     * threads.  The SIGSEGV handler for lazy stack growth requires SA_ONSTACK
     * so it can run even when the green thread's stack is exhausted. */
    setup_alt_stack();

    tl_sched = sched;
    sched->running = 1;
    unsigned int steal_seed = (unsigned int)sched->id;

    while (!atomic_load_explicit(&g_all_done, memory_order_acquire)) {
        /* Single-scheduler: use steal (FIFO) for fairness and compatibility.
         * Multi-scheduler: use pop (LIFO) for cache locality; steal from others. */
        march_proc *p;
        if (g_num_scheds <= 1) {
            p = (march_proc *)march_deque_steal(&sched->local_queue);
        } else {
            p = (march_proc *)march_deque_pop(&sched->local_queue);
        }

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
            if (atomic_load_explicit(&g_live_procs, memory_order_acquire) <= 0) {
                atomic_store_explicit(&g_all_done, 1, memory_order_release);
                break;
            }
            sched_yield();
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
    if (!p) return NULL;

    /* Fast path: message already available. */
    void *msg = mbox_pop(p);
    if (msg) return msg;

    /* Slow path: check mailbox under lock, then park if truly empty. */
    mbox_lock_acquire(p);
    msg = mbox_pop(p);
    if (msg) {
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

    /* Resumed — a sender woke us. */
    mbox_lock_acquire(p);
    msg = mbox_pop(p);
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

void march_sched_wake(march_proc *target) {
    if (!target) return;

    /* If the process is PROC_PARKED, its context has not yet been saved by
     * swapcontext.  We must wait until the scheduler transitions it to
     * PROC_WAITING before we can push it to a deque; otherwise two
     * scheduler threads would try to resume the same process simultaneously.
     * The transition is O(1) so this spin is extremely short. */
    march_proc_status cur;
    do {
        cur = atomic_load_explicit(&target->status, memory_order_acquire);
        if (cur == PROC_DEAD || cur == PROC_READY || cur == PROC_RUNNING)
            return; /* Not WAITING — no need to wake. */
        /* cur is PROC_PARKED or PROC_WAITING: keep looping until WAITING. */
    } while (cur == PROC_PARKED);

    /* Use CAS to atomically transition WAITING→READY so that concurrent
     * senders cannot both succeed and push the process to the deque twice. */
    march_proc_status expected = PROC_WAITING;
    if (!atomic_compare_exchange_strong_explicit(
            &target->status, &expected, PROC_READY,
            memory_order_acq_rel, memory_order_acquire))
        return; /* Not WAITING (already woken by another sender). */
    if (tl_sched) {
        march_deque_push(&tl_sched->local_queue, target);
    } else {
        march_deque_push(&g_scheds[0].local_queue, target);
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
    sa.sa_flags = SA_RESTART;   /* auto-restart interruptible syscalls */
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

int march_cancel_token_is_cancelled(march_cancel_token *tok) {
    if (!tok) return 0;
    return atomic_load_explicit(&tok->cancelled, memory_order_acquire);
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
