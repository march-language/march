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

/* ── Constants ────────────────────────────────────────────────────────── */

/* Default usable stack size per green thread (64 KiB).
 * Phase 1: fixed-size stacks.  Stack growth via mremap is Phase 2+.
 * Note: the spec calls for 4 KiB, but 64 KiB is the practical minimum on
 * macOS/Linux where ucontext setup itself consumes several hundred bytes. */
#define MARCH_STACK_SIZE        (64 * 1024)

/* Reduction budget per quantum.  A process is preempted (yielded) after
 * this many march_sched_tick() calls within a single scheduler turn. */
#define MARCH_REDUCTION_BUDGET  4000

/* ── Process status ───────────────────────────────────────────────────── */
typedef enum {
    PROC_READY   = 0,  /* In run queue, waiting for a CPU turn              */
    PROC_RUNNING = 1,  /* Currently executing on the scheduler thread       */
    PROC_WAITING = 2,  /* Blocked on receive/I/O; not in run queue (Phase 2) */
    PROC_DEAD    = 3   /* Finished; resources will be freed by the scheduler */
} march_proc_status;

/* ── Process priority ─────────────────────────────────────────────────── */
typedef enum {
    PRIO_NORMAL = 0,
    PRIO_HIGH   = 1
} march_proc_priority;

/* ── Mailbox node (Phase 2: message passing) ──────────────────────────── */
typedef struct march_mbox_node {
    void                   *msg;
    struct march_mbox_node *next;
} march_mbox_node;

/* ── Green thread process descriptor ─────────────────────────────────── */
typedef struct march_proc {
    int64_t                   pid;          /* Unique process ID (monotonic counter) */
    _Atomic march_proc_status status;       /* Process lifecycle state (atomic for Phase 3) */
    march_proc_priority       priority;
    int64_t                   reductions;   /* Remaining reduction budget this quantum */
    void                     *stack_base;  /* Start of usable stack (after guard page) */
    size_t                    stack_alloc; /* Total mmap allocation size (incl. guard) */
    march_mbox_node          *mailbox;     /* Head of message queue (FIFO)             */
    march_mbox_node          *mbox_tail;   /* Tail of message queue (for O(1) enqueue) */
    int64_t                   mbox_count;  /* Number of messages in mailbox            */
    _Atomic int               mbox_lock;   /* Spinlock for mailbox access (Phase 3)    */
    ucontext_t                ctx;         /* Saved execution context (makecontext/swap) */
    void                    (*fn)(void *); /* Entry function */
    void                     *arg;         /* Argument passed to fn */
    struct march_proc        *next;        /* Intrusive run-queue link */
} march_proc;

/* ── Scheduler (single OS-thread, Phase 1) ───────────────────────────── */
typedef struct march_scheduler {
    march_proc *run_head;   /* FIFO run-queue head                           */
    march_proc *run_tail;   /* FIFO run-queue tail                           */
    march_proc *current;    /* Currently running process (NULL = in sched)   */
    ucontext_t  sched_ctx;  /* Scheduler context; processes yield back here  */
    int64_t     next_pid;   /* Next PID to assign (monotonic)                */
    int         running;    /* Non-zero while march_sched_run() is active    */
} march_scheduler;

/* ── Public API ───────────────────────────────────────────────────────── */

/* Initialize the global scheduler.  Call once before any other sched fn. */
void         march_sched_init(void);

/* Run the scheduler loop until all spawned processes are DEAD.
 * Returns to the caller once the run queue drains. */
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
