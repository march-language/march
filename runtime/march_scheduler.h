#pragma once
/* _XOPEN_SOURCE must be defined before any system headers to enable ucontext_t
 * and related functions (makecontext, swapcontext, getcontext).  On macOS this
 * also silences the "deprecated ucontext routines" hard-error guard. */
#ifndef _XOPEN_SOURCE
#  define _XOPEN_SOURCE 700
#endif
#include <stdint.h>
#include <stddef.h>
#include <stdatomic.h>
#include <ucontext.h>
#include <pthread.h>

#include "march_deque.h"

/* ── Constants ────────────────────────────────────────────────────────── */

/* Initial usable stack per green thread (Phase 4: lazy growth).
 * Stacks start small and grow on demand via guard-page fault up to
 * MARCH_STACK_MAX.  The initial 4 KiB is enough for the trampoline
 * and shallow frames; deep frames trigger one mprotect per new page. */
#define MARCH_STACK_INITIAL     (4 * 1024)

/* Maximum usable stack per green thread (1 MiB).  The virtual-address
 * reservation is MARCH_STACK_MAX + one guard page.  Exceeding this limit
 * produces an unrecoverable stack-overflow crash. */
#define MARCH_STACK_MAX         (1024 * 1024)

/* Legacy alias — external code that references MARCH_STACK_SIZE still
 * compiles; the value is now the initial (not fixed) stack size. */
#define MARCH_STACK_SIZE        MARCH_STACK_INITIAL

/* Reduction budget per quantum.  A process is preempted (yielded) after
 * this many march_sched_tick() calls within a single scheduler turn. */
#define MARCH_REDUCTION_BUDGET  4000

/* Number of OS-thread schedulers.  Override at compile time with
 * -DMARCH_NUM_SCHEDULERS=N.  Default is 4. */
#ifndef MARCH_NUM_SCHEDULERS
#  define MARCH_NUM_SCHEDULERS 4
#endif

/* Preemption quantum in microseconds.  The preemption daemon sends SIGUSR1
 * to each scheduler thread every MARCH_QUANTUM_US µs, zeroing its reduction
 * counter and forcing a cooperative yield at the next march_sched_tick().
 * Override at compile time with -DMARCH_QUANTUM_US=N.  Default is 1000 (1 ms). */
#ifndef MARCH_QUANTUM_US
#  define MARCH_QUANTUM_US 1000
#endif

/* ── Process status ───────────────────────────────────────────────────── */
typedef enum {
    PROC_READY   = 0,  /* In run queue, waiting for a CPU turn              */
    PROC_RUNNING = 1,  /* Currently executing on the scheduler thread       */
    PROC_WAITING = 2,  /* Blocked on receive/I/O; not in run queue          */
    PROC_DEAD    = 3,  /* Finished; resources will be freed by the scheduler */
    PROC_PARKED  = 4   /* Transitioning to WAITING: status set but swapcontext
                        * not yet called.  Wakers must spin-wait on this state
                        * before pushing to a deque, to avoid resuming a process
                        * whose context has not yet been saved.              */
} march_proc_status;

/* ── Process priority ─────────────────────────────────────────────────── */
typedef enum {
    PRIO_NORMAL = 0,
    PRIO_HIGH   = 1
} march_proc_priority;

/* ── Mailbox node ────────────────────────────────────────────────────── */
typedef struct march_mbox_node {
    void                   *msg;
    struct march_mbox_node *next;
} march_mbox_node;

/* Forward-declare scheduler so march_proc can hold a pointer to it. */
struct march_scheduler;

/* ── Green thread process descriptor ─────────────────────────────────── */
typedef struct march_proc {
    int64_t                    pid;          /* Unique process ID (monotonic counter) */
    _Atomic march_proc_status  status;       /* Process lifecycle state (atomic)      */
    march_proc_priority        priority;
    int64_t                    reductions;   /* Remaining reduction budget this quantum */
    void                      *stack_mmap_base; /* Base of full mmap reservation (permanent guard page here) */
    void                      *stack_base;      /* Current bottom of usable stack region (grows downward) */
    size_t                     stack_alloc;     /* Total mmap size: MARCH_STACK_MAX + one guard page */
    march_mbox_node           *mailbox;      /* Head of message queue (FIFO)             */
    march_mbox_node           *mbox_tail;    /* Tail of message queue (for O(1) enqueue) */
    int64_t                    mbox_count;   /* Number of messages in mailbox            */
    _Atomic int                mbox_lock;    /* Spinlock for mailbox access              */
    ucontext_t                 ctx;          /* Saved execution context (makecontext/swap) */
    void                     (*fn)(void *);  /* Entry function */
    void                      *arg;          /* Argument passed to fn */
    struct march_proc         *next;         /* Intrusive link (unused with deque, kept for compat) */
    struct march_scheduler    *owner_sched;  /* Scheduler that last ran this process */
} march_proc;

/* ── Scheduler (per OS-thread) ───────────────────────────────────────── */
typedef struct march_scheduler {
    march_deque     local_queue;  /* Work-stealing deque of READY processes      */
    march_proc     *current;      /* Currently running process (NULL = in sched) */
    ucontext_t      sched_ctx;    /* Scheduler context; processes yield here     */
    int             running;      /* Non-zero while scheduler loop is active     */
    int             id;           /* Scheduler index (0..N-1)                    */
    pthread_t       thread;       /* OS thread handle (for schedulers 1..N-1)    */
} march_scheduler;

/* ── Public API ───────────────────────────────────────────────────────── */

/* Initialize the global scheduler.  Call once before any other sched fn. */
void         march_sched_init(void);

/* Run the scheduler loop until all spawned processes are DEAD.
 * Returns to the caller once all work drains.  Spawns N-1 worker threads
 * and runs scheduler 0 on the calling thread. */
void         march_sched_run(void);

/* Spawn a new green thread.  Returns the new process, or NULL on failure.
 * Safe to call from within a running process (nested spawn). */
march_proc  *march_sched_spawn(void (*fn)(void *), void *arg);

/* Cooperatively yield the CPU back to the scheduler. */
void         march_sched_yield(void);

/* Decrement the reduction counter; yield automatically if budget runs out.
 * Call once per "reduction" (function application, match arm, etc.) in
 * compiled code to implement cooperative preemption. */
void         march_sched_tick(void);

/* Mark the current process DEAD and return control to the scheduler.
 * The process entry function's trampoline calls this automatically on
 * return; user code may also call it for early exit. */
void         march_sched_exit(void);

/* Return the currently running process (NULL if in scheduler context). */
march_proc  *march_sched_current(void);

/* Return the total number of processes ever spawned since last init. */
int64_t      march_sched_total_spawned(void);

/* Send a message to a process. Enqueues msg and wakes the target if WAITING.
 * Safe to call from any process or from the scheduler context.
 * Returns 0 on success, -1 if target is NULL or DEAD. */
int          march_sched_send(march_proc *target, void *msg);

/* Receive the next message from the current process's mailbox.
 * If the mailbox is empty, parks the process as PROC_WAITING and yields
 * to the scheduler. Returns the message pointer on success, NULL if the
 * process was woken without a message (e.g., killed). */
void        *march_sched_recv(void);

/* Try to receive without blocking. Returns the message if available,
 * NULL if mailbox is empty. Does not yield. */
void        *march_sched_try_recv(void);

/* Wake a WAITING process and re-enqueue it. No-op if not WAITING.
 * Safe to call from any context. */
void         march_sched_wake(march_proc *target);

/* Return the process with the given PID, or NULL if not found.
 * O(1) array lookup by PID. */
march_proc  *march_sched_find(int64_t pid);

/* ── Phase 4: compiled-code reduction counting ────────────────────────── */

/* Thread-local reduction budget for LLVM-compiled code.
 * The LLVM backend emits a load/decrement/store of this variable at every
 * function prologue (or TCO loop header). Declared extern so the compiled
 * LLVM IR module can reference it as an external thread_local global.
 *
 * volatile: the preemption signal handler (SIGUSR1) zeroes this from within
 * the scheduler thread's signal context.  volatile prevents the compiler
 * from keeping the value in a register across the signal delivery point. */
extern volatile _Thread_local int64_t march_tls_reductions;

/* Called by compiled code when march_tls_reductions hits zero.
 * Resets the budget to MARCH_REDUCTION_BUDGET and cooperatively yields
 * back to the scheduler via march_sched_yield(). No-op outside a
 * scheduler context (e.g. when running without the green-thread runtime). */
void march_yield_from_compiled(void);

/* ── Phase 5A: signal-based preemption ───────────────────────────────── */

/* Start/stop the preemption daemon thread.  Called from march_sched_run().
 * The daemon sends SIGUSR1 to each active scheduler thread every
 * MARCH_QUANTUM_US microseconds, zeroing march_tls_reductions so that the
 * next march_sched_tick() triggers a cooperative yield.
 *
 * march_sched_preempt_start() must be called AFTER all scheduler pthread_t
 * handles have been stored (i.e. after spawning worker threads).
 * march_sched_preempt_stop() signals the daemon to exit and joins it. */
void march_sched_preempt_start(void);
void march_sched_preempt_stop(void);

/* ── Phase 5B: cancellation tokens ──────────────────────────────────── */

/* A cancellation token: a single atomic flag shared between a task group
 * and the tasks spawned within it.  When cancelled, tasks check
 * march_cancel_token_is_cancelled() at yield points and exit early.
 *
 * Tokens are heap-allocated and reference-counted (march_cancel_token_ref /
 * march_cancel_token_unref).  The initial refcount is 1. */
typedef struct march_cancel_token {
    _Atomic int   cancelled;  /* 0 = active, 1 = cancelled            */
    _Atomic int   refcount;   /* reference count                       */
} march_cancel_token;

/* Allocate a new cancel token (refcount=1, cancelled=0). */
march_cancel_token *march_cancel_token_new(void);

/* Atomically cancel the token.  All tasks holding a reference will see
 * march_cancel_token_is_cancelled() return 1 at their next check. */
void march_cancel_token_cancel(march_cancel_token *tok);

/* Return 1 if the token has been cancelled, 0 otherwise. */
int  march_cancel_token_is_cancelled(march_cancel_token *tok);

/* Increment reference count (for task spawn that copies the token pointer). */
void march_cancel_token_ref(march_cancel_token *tok);

/* Decrement reference count; frees the token when it reaches zero. */
void march_cancel_token_unref(march_cancel_token *tok);

/* Spawn a green thread with an associated cancel token.  The process stores a
 * reference to tok; the runtime checks the token at every yield point and
 * calls march_sched_exit() if it has been cancelled.
 * Returns the new process, or NULL on failure. */
march_proc *march_sched_spawn_with_cancel(void (*fn)(void *), void *arg,
                                          march_cancel_token *tok);
