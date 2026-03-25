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

/* ── Process status ───────────────────────────────────────────────────── */
typedef enum {
    PROC_READY   = 0,  /* In run queue, waiting for a CPU turn              */
    PROC_RUNNING = 1,  /* Currently executing on the scheduler thread       */
    PROC_WAITING = 2,  /* Blocked on receive/I/O; not in run queue          */
    PROC_DEAD    = 3   /* Finished; resources will be freed by the scheduler */
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
 * LLVM IR module can reference it as an external thread_local global. */
extern _Thread_local int64_t march_tls_reductions;

/* Called by compiled code when march_tls_reductions hits zero.
 * Resets the budget to MARCH_REDUCTION_BUDGET and cooperatively yields
 * back to the scheduler via march_sched_yield(). No-op outside a
 * scheduler context (e.g. when running without the green-thread runtime). */
void march_yield_from_compiled(void);
