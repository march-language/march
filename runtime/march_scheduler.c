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
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>   /* getpagesize, sysconf */

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

/* ── Stack allocation helpers ─────────────────────────────────────────── */

/* Allocate an mmap'd stack with a PROT_NONE guard page at the low end.
 * Returns a pointer to the *usable* stack area (guard page excluded).
 * Sets *alloc_size to the full allocation size (usable + guard page) so
 * the caller can munmap the correct range later. */
static void *stack_alloc(size_t usable_size, size_t *alloc_size) {
    size_t page  = (size_t)sysconf(_SC_PAGE_SIZE);
    size_t total = usable_size + page;
    void  *mem   = mmap(NULL, total,
                        PROT_READ | PROT_WRITE,
                        MAP_PRIVATE | MAP_ANON, -1, 0);
    if (mem == MAP_FAILED) return NULL;
    /* Make the lowest page inaccessible — catches stack overflows as SIGSEGV. */
    if (mprotect(mem, page, PROT_NONE) != 0) {
        munmap(mem, total);
        return NULL;
    }
    *alloc_size = total;
    return (char *)mem + page; /* Usable region starts after the guard page */
}

static void stack_free(void *stack_base, size_t alloc_size) {
    /* The guard page is immediately below stack_base. */
    void *mem = (char *)stack_base - (size_t)sysconf(_SC_PAGE_SIZE);
    munmap(mem, alloc_size);
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

    /* Allocate the stack. */
    p->stack_base = stack_alloc(MARCH_STACK_SIZE, &p->stack_alloc);
    if (!p->stack_base) {
        fputs("march_sched: failed to allocate process stack\n", stderr);
        free(p);
        return NULL;
    }

    /* Build the execution context. */
    if (getcontext(&p->ctx) != 0) {
        fputs("march_sched: getcontext failed\n", stderr);
        stack_free(p->stack_base, p->stack_alloc);
        free(p);
        return NULL;
    }
    p->ctx.uc_stack.ss_sp   = p->stack_base;
    p->ctx.uc_stack.ss_size = MARCH_STACK_SIZE;
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
        } else if (st == PROC_DEAD) {
            registry_remove(p);
            atomic_fetch_sub_explicit(&g_live_procs, 1, memory_order_release);
            stack_free(p->stack_base, p->stack_alloc);
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
        sched_loop(&g_scheds[0]);
        return;
    }

    /* Spawn N-1 worker threads; scheduler 0 runs on the calling thread. */
    for (int i = 1; i < g_num_scheds; i++) {
        pthread_create(&g_scheds[i].thread, NULL, sched_thread_entry, &g_scheds[i]);
    }

    sched_loop(&g_scheds[0]);

    for (int i = 1; i < g_num_scheds; i++) {
        pthread_join(g_scheds[i].thread, NULL);
    }
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

int march_sched_send(march_proc *target, void *msg) {
    if (!target || atomic_load_explicit(&target->status, memory_order_acquire) == PROC_DEAD)
        return -1;
    mbox_lock_acquire(target);
    mbox_push(target, msg);
    march_proc_status st = atomic_load_explicit(&target->status, memory_order_acquire);
    mbox_lock_release(target);
    if (st == PROC_WAITING) {
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
    atomic_store_explicit(&p->status, PROC_WAITING, memory_order_release);
    mbox_lock_release(p);

    swapcontext(&p->ctx, &tl_sched->sched_ctx);

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
    if (!target || atomic_load_explicit(&target->status, memory_order_acquire) != PROC_WAITING)
        return;
    atomic_store_explicit(&target->status, PROC_READY, memory_order_release);
    if (tl_sched) {
        march_deque_push(&tl_sched->local_queue, target);
    } else {
        march_deque_push(&g_scheds[0].local_queue, target);
    }
}
