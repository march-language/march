/* march_scheduler.c — Phase 1 cooperative green-thread scheduler.
 *
 * Design
 * ──────
 * Each spawned process gets its own stack (mmap'd, with a PROT_NONE guard
 * page at the low end) and a ucontext_t save area.  The global scheduler
 * holds a FIFO run queue of READY processes.
 *
 * Scheduling policy: round-robin.
 *   1. Dequeue the next READY process.
 *   2. Reset its reduction budget to MARCH_REDUCTION_BUDGET.
 *   3. swapcontext(scheduler → process).
 *   4. Process runs until it calls march_sched_yield() or march_sched_tick()
 *      exhausts its budget, at which point it swapcontext(process → scheduler).
 *   5. If the process is still READY, re-enqueue it; if DEAD, free it.
 *   6. Repeat until the run queue is empty.
 *
 * Context switching
 * ─────────────────
 * ucontext_t / makecontext / swapcontext provide stackful coroutines.
 * Each process's ucontext points to its own mmap'd stack.  The trampoline
 * wraps the user function and calls march_sched_exit() on return.
 *
 * makecontext only accepts int-sized variadic arguments, so a 64-bit
 * pointer to the proc struct is passed as two 32-bit halves (hi, lo)
 * and reassembled in the trampoline.
 *
 * Phase 2+ extensions
 * ───────────────────
 * PROC_WAITING / mailbox fields are plumbed but unused in Phase 1.
 * Multi-thread (M>1) and work-stealing arrive in Phase 3.
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
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>   /* getpagesize */

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

static march_scheduler g_sched;
static int64_t         g_total_spawned = 0;

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

/* ── Mailbox spinlock (needed for Phase 3 thread safety, used from Phase 2) ── */

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
    proc->status = PROC_DEAD;
    swapcontext(&proc->ctx, &g_sched.sched_ctx);
    /* If we ever return here the OS context is gone — abort defensively. */
    abort();
}

/* ── Run-queue helpers (FIFO) ─────────────────────────────────────────── */

static void run_enqueue(march_proc *p) {
    p->next   = NULL;
    p->status = PROC_READY;
    if (g_sched.run_tail) {
        g_sched.run_tail->next = p;
    } else {
        g_sched.run_head = p;
    }
    g_sched.run_tail = p;
}

static march_proc *run_dequeue(void) {
    march_proc *p = g_sched.run_head;
    if (!p) return NULL;
    g_sched.run_head = p->next;
    if (!g_sched.run_head) g_sched.run_tail = NULL;
    p->next = NULL;
    return p;
}

/* ── Public API ───────────────────────────────────────────────────────── */

void march_sched_init(void) {
    memset(&g_sched, 0, sizeof(g_sched));
    g_total_spawned = 0;
    memset(g_proc_registry, 0, sizeof(g_proc_registry));
    g_proc_count = 0;
}

march_proc *march_sched_spawn(void (*fn)(void *), void *arg) {
    march_proc *p = (march_proc *)calloc(1, sizeof(march_proc));
    if (!p) {
        fputs("march_sched: out of memory (process alloc)\n", stderr);
        return NULL;
    }

    p->pid        = g_sched.next_pid++;
    p->status     = PROC_READY;
    p->priority   = PRIO_NORMAL;
    p->reductions = MARCH_REDUCTION_BUDGET;
    p->fn         = fn;
    p->arg        = arg;
    p->mailbox    = NULL;
    p->mbox_tail  = NULL;
    p->mbox_count = 0;
    p->mbox_lock  = 0;

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

    run_enqueue(p);
    registry_add(p);
    g_total_spawned++;
    return p;
}

void march_sched_run(void) {
    g_sched.running = 1;

    for (;;) {
        march_proc *p = run_dequeue();
        if (!p) {
            if (g_proc_count <= 0) break;
            break;  /* Deadlock: all WAITING; Phase 3 replaces this */
        }

        /* Start a new quantum: fresh budget, mark running, switch in. */
        p->status        = PROC_RUNNING;
        p->reductions    = MARCH_REDUCTION_BUDGET;
        g_sched.current  = p;

        swapcontext(&g_sched.sched_ctx, &p->ctx);

        /* Returned here after process called march_sched_yield() or died. */
        g_sched.current = NULL;

        if (p->status == PROC_READY) {
            /* Process voluntarily yielded — re-enqueue for the next turn. */
            run_enqueue(p);
        } else if (p->status == PROC_DEAD) {
            /* Process finished — release its resources. */
            registry_remove(p);
            stack_free(p->stack_base, p->stack_alloc);
            free(p);
        }
        /* PROC_WAITING: process parked itself; a wakeup call re-enqueues it. */
    }

    g_sched.running = 0;
}

void march_sched_yield(void) {
    march_proc *p = g_sched.current;
    if (!p) return; /* No-op when called outside a scheduled process. */
    p->status = PROC_READY;
    swapcontext(&p->ctx, &g_sched.sched_ctx);
    /* Execution resumes here after the scheduler re-schedules us. */
}

void march_sched_tick(void) {
    march_proc *p = g_sched.current;
    if (!p) return;
    p->reductions--;
    if (p->reductions <= 0) {
        march_sched_yield(); /* Budget exhausted — cooperative preemption. */
    }
}

void march_sched_exit(void) {
    march_proc *p = g_sched.current;
    if (!p) return;
    p->status = PROC_DEAD;
    swapcontext(&p->ctx, &g_sched.sched_ctx);
    abort(); /* Should never be reached. */
}

march_proc *march_sched_current(void) {
    return g_sched.current;
}

int64_t march_sched_total_spawned(void) {
    return g_total_spawned;
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
    int was_waiting = (atomic_load_explicit(&target->status, memory_order_acquire) == PROC_WAITING);
    mbox_lock_release(target);
    if (was_waiting) {
        march_sched_wake(target);
    }
    return 0;
}

void *march_sched_recv(void) {
    march_proc *p = g_sched.current;
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

    swapcontext(&p->ctx, &g_sched.sched_ctx);

    /* Resumed — a sender woke us. */
    return mbox_pop(p);
}

void *march_sched_try_recv(void) {
    march_proc *p = g_sched.current;
    if (!p) return NULL;
    return mbox_pop(p);
}

void march_sched_wake(march_proc *target) {
    if (!target || atomic_load_explicit(&target->status, memory_order_acquire) != PROC_WAITING)
        return;
    run_enqueue(target);  /* Sets status to PROC_READY */
}
