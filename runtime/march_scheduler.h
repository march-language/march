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
#include <setjmp.h>

#include "march_deque.h"

/* Portable AddressSanitizer detection (clang's __has_feature vs. GCC's
 * __SANITIZE_ADDRESS__ define) — guards the fiber-switch annotations below. */
#if defined(__has_feature)
#  if __has_feature(address_sanitizer)
#    define MARCH_ASAN_BUILD 1
#  endif
#endif
#if defined(__SANITIZE_ADDRESS__) && !defined(MARCH_ASAN_BUILD)
#  define MARCH_ASAN_BUILD 1
#endif
#ifdef MARCH_ASAN_BUILD
#  include <sanitizer/common_interface_defs.h>
#endif

/* Portable ThreadSanitizer detection — same rationale as MARCH_ASAN_BUILD
 * above, but TSan has its own dedicated fiber API (__tsan_create_fiber /
 * __tsan_switch_to_fiber), distinct from ASan's start/finish_switch_fiber. */
#if defined(__has_feature)
#  if __has_feature(thread_sanitizer)
#    define MARCH_TSAN_BUILD 1
#  endif
#endif
#if defined(__SANITIZE_THREAD__) && !defined(MARCH_TSAN_BUILD)
#  define MARCH_TSAN_BUILD 1
#endif
#ifdef MARCH_TSAN_BUILD
#  include <sanitizer/tsan_interface.h>
#endif

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

/* DEFAULT number of OS-thread schedulers, used when the MARCH_NUM_SCHEDULERS
 * environment variable is unset or unusable.
 *
 * **0 means AUTO**: one scheduler per online CPU, clamped to
 * MARCH_MAX_SCHEDULERS.  That is the shipped default, and it is what a March
 * program gets unless someone says otherwise.
 *
 * A build may pin a specific count with -DMARCH_NUM_SCHEDULERS=N, and a pin
 * WINS over auto.  This is load-bearing, not a convenience: the C scheduler
 * harnesses in test/ pin themselves to 1 or 4 because their premise is a
 * specific number of threads (with one scheduler, pinning a proc is a
 * documented no-op), and on a single-core box an auto default would quietly
 * turn those tests into vacuous no-ops rather than failures.
 *
 * The default was a flat 4 on every machine until 2026-09-04 — four threads on
 * a 4-core laptop and four on a 96-core server — so 4 was the de-facto
 * parallelism limit of every March program that had not been told otherwise,
 * and nothing said so.  Written up in
 * specs/progress/2026-09-04-scheduler-default-tracks-cpu-count.md
 *
 * This is a DEFAULT, not a ceiling: the environment variable of the same name
 * may raise the count as well as lower it, up to MARCH_MAX_SCHEDULERS below.
 * (It was a silent ceiling until 2026-09; MARCH_NUM_SCHEDULERS=14 ran four
 * threads and said nothing, which made every parallel-scaling measurement on
 * a >4-core machine wrong.  Written up in
 * specs/progress/2026-09-04-scheduler-count-env-was-a-silent-ceiling.md) */
#ifndef MARCH_NUM_SCHEDULERS
#  define MARCH_NUM_SCHEDULERS 0   /* 0 = auto (one per online CPU) */
#endif

/* Hard upper bound on the scheduler count, i.e. the size of the statically
 * allocated scheduler table.  A larger request from the environment is
 * clamped to this and reported on stderr.
 *
 * Why static rather than sized-to-order at init: g_scheds is indexed on the
 * work-stealing hot path in march_sched_run, and a static array keeps that a
 * fixed-address index instead of a load-then-index through a global pointer.
 * The table is not free -- sizeof(march_scheduler) is dominated by the 4096-
 * slot Chase-Lev deque, ~32 KiB per entry, so 64 entries is ~2 MiB -- but it
 * lives in BSS and march_sched_init only ever touches the entries actually in
 * use, so unused slots are never faulted in and cost no resident memory.
 * Raise it at compile time with -DMARCH_MAX_SCHEDULERS=N on a machine with
 * more than 64 cores. */
#ifndef MARCH_MAX_SCHEDULERS
#  define MARCH_MAX_SCHEDULERS 64
#endif
/* A build that pins a default larger than the bound raises the bound with it.
 * (Vacuous for the auto default, which is 0.) */
#if MARCH_NUM_SCHEDULERS > MARCH_MAX_SCHEDULERS
#  undef  MARCH_MAX_SCHEDULERS
#  define MARCH_MAX_SCHEDULERS MARCH_NUM_SCHEDULERS
#endif

/* Preemption quantum in microseconds.  The preemption daemon sends SIGUSR1
 * to each scheduler thread every MARCH_QUANTUM_US µs, zeroing its reduction
 * counter and forcing a cooperative yield at the next march_sched_tick().
 * Override at compile time with -DMARCH_QUANTUM_US=N.  Default is 1000 (1 ms). */
#ifndef MARCH_QUANTUM_US
#  define MARCH_QUANTUM_US 1000
#endif

/* ── Process status ───────────────────────────────────────────────────── */
/* Queue-membership invariant (the heart of the scheduler's memory safety):
 *
 *   A march_proc is in AT MOST ONE run structure (one scheduler's local
 *   Chase-Lev deque, or the global run queue) at any instant.  Membership is
 *   authorized by exactly one atomic transition INTO PROC_RUNNABLE; only the
 *   thread that wins that transition performs the enqueue.  A scheduler runs
 *   a proc only after claiming it RUNNABLE→RUNNING; because a runnable proc
 *   is single-membership, no two OS threads can ever swapcontext into the
 *   same proc (= the same green-thread stack) concurrently.
 *
 *   State         | in a run queue? | meaning
 *   ------------- | --------------- | -------------------------------------
 *   PROC_RUNNABLE | yes, exactly one| Enqueued, waiting for a CPU.
 *   PROC_RUNNING  | no              | Claimed by one scheduler; that
 *                 |                 | scheduler is swapcontext-ed into it.
 *   PROC_WAITING  | no              | Parked on recv, context saved.  A
 *                 |                 | waker moves it WAITING→RUNNABLE.
 *   PROC_PARKED   | no              | Transient: recv set it, swapcontext
 *                 |                 | not yet returned to the scheduler.
 *   PROC_DEAD     | no              | Finished.  Never re-enqueued.
 *
 *   Authorized transitions into RUNNABLE (winner, and only winner, enqueues):
 *     NEW     → RUNNABLE   at spawn
 *     WAITING → RUNNABLE   at wake (message arrival, kill-wake, shutdown wake)
 *     RUNNING → RUNNABLE   at yield (only the running proc itself does this)
 */
typedef enum {
    PROC_RUNNABLE = 0, /* In exactly one run queue, waiting for a CPU turn  */
    PROC_RUNNING = 1,  /* Currently executing on one scheduler thread       */
    PROC_WAITING = 2,  /* Blocked on receive/I/O; not in any run queue      */
    PROC_DEAD    = 3,  /* Finished; never re-enqueued (leak-don't-free)     */
    PROC_PARKED  = 4   /* Transitioning to WAITING: status set but swapcontext
                        * not yet called.  Wakers must spin-wait on this state
                        * before enqueueing, to avoid resuming a process
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
    uint64_t                enqueue_seq; /* Per-mailbox global order across
                                            user and control planes. */
    struct march_mbox_node *next;
} march_mbox_node;

/* ── Mailbox capacity + overflow policy ─────────────────────────────────
 * mbox_limit == 0 means unbounded (today's behavior, unchanged default). */
typedef enum {
    MARCH_MBOX_UNBOUNDED  = 0,   /* default: today's behavior */
    MARCH_MBOX_DROP_NEW   = 1,   /* reject the incoming message */
    MARCH_MBOX_DROP_OLD   = 2,   /* evict the oldest queued message */
    MARCH_MBOX_BLOCK      = 3,   /* Task 8: park the sender */
} march_mbox_policy;

#define MARCH_SEND_OK       0
#define MARCH_SEND_DEAD    (-1)
#define MARCH_SEND_DROPPED  1    /* message NOT enqueued (DROP_NEW) */

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
    march_mbox_node           *control_mailbox; /* Reserved control-plane queue. Never
                                                   subject to user overflow policy. */
    march_mbox_node           *control_mbox_tail;
    uint64_t                   mbox_next_seq; /* Written only under mbox_lock. */
    _Atomic int64_t             mbox_count;  /* Total user + control messages. Atomic:
                                                 writers (mbox_push/mbox_pop) always run
                                                 under mbox_lock, but wake_idle_daemons /
                                                 march_sched_wait_idle / march_sched_mbox_count
                                                 read it from other OS threads without
                                                 the lock. */
    _Atomic int64_t             user_mbox_count; /* User messages only; mailbox limits and
                                                    BLOCK low-water checks use this count. */
    int64_t                    mbox_limit;   /* 0 = unbounded (default). Plain field: only
                                                 read/written under mbox_lock (set by
                                                 march_sched_set_mbox_limit, read by
                                                 march_sched_send). calloc in sched_spawn_common
                                                 zero-initializes this to 0 = unbounded. */
    int32_t                    mbox_policy;  /* march_mbox_policy. Same lock discipline as
                                                 mbox_limit above; calloc zero-inits to
                                                 MARCH_MBOX_UNBOUNDED (=0). */
    _Atomic int                mbox_lock;    /* Spinlock for mailbox access              */
    _Atomic int                mbox_wait_mode; /* 0=not mailbox-waiting, 1=receive any,
                                                  2=actor dispatch waiting for user only. */
    struct march_proc         *mbox_send_waiters; /* Task 8 (MARCH_MBOX_BLOCK): intrusive
                                                 singly-linked list of sender procs parked
                                                 on THIS proc's full mailbox, threaded
                                                 through send_wait_next below. Read/written
                                                 only under this proc's own mbox_lock (both
                                                 by senders registering in march_sched_send
                                                 and by the receive-side drain-wake in
                                                 mbox_take_waiters_if_low / the PROC_DEAD
                                                 reap branch in sched_loop). calloc
                                                 zero-inits to NULL. */
    struct march_proc         *send_wait_next;     /* Intrusive link for the above list on
                                                 THIS proc when IT is a parked sender
                                                 waiting on some OTHER proc's mailbox.
                                                 Deliberately NOT p->next (the global-runq
                                                 link) -- a blocked sender gets pushed to
                                                 the runq by march_sched_wake while still
                                                 linked into the target's waiter list, so
                                                 sharing one field would corrupt both
                                                 lists. */
    /* Wake permit (LockSupport/park-unpark style).  march_sched_wake deposits
     * one BEFORE it inspects `status`; march_sched_park_self consumes one
     * INSTEAD of parking.  Closes the wake-while-RUNNING window in lock-free
     * park sequences (task_wait_done): after the waiter's final done-recheck
     * but before its PROC_PARKED store, a wake that arrives sees status ==
     * PROC_RUNNING, takes wake's "not WAITING" early return, and would be
     * dropped — the waiter then parks with nobody left to wake it.  With the
     * permit, that wake instead cancels the waiter's next park.  Measured:
     * this was the residual 1-in-1000 task_burst_await hang remaining after
     * the seq_cst store-buffering fix in task_wait_done (which was the
     * dominant 1-in-20 cause; see the comment there).  march_sched_recv does
     * NOT need the permit — it holds mbox_lock across both its emptiness
     * check and its PROC_PARKED store, so a sender can never observe it as
     * RUNNING after seeing an empty mailbox. */
    _Atomic int                wake_pending;
    /* Task 16 fix-up (Important 1): bumped on every entry to and exit from
     * march_sched_park_self_until / march_sched_recv_until's real-park
     * branch (relaxed — this only needs to be a monotonically-increasing
     * tag, not a synchronization point; the actual synchronization is the
     * existing status/mbox_lock machinery). A march_timer_ent stamped with
     * the post-entry-increment value is LIVE only while this counter still
     * reads that same value — a wake for any other reason (a message
     * arriving, a spurious wake, or a later park call entirely) advances
     * this counter and makes the earlier timer entry a ghost. Lets
     * march_sched_wait_idle (and, optionally, timer_service) distinguish a
     * genuinely-still-parked proc from one that already woke early but
     * whose heap entry lingers until its original deadline (no-cancellation
     * heap by design — see the timer comment below). Without this, a
     * successfully-answered Actor.call(...,5000) that replies in 1ms would
     * still make run_until_idle() block for the full 5000ms. calloc
     * zero-inits this to 0, matching "never parked yet." */
    _Atomic int64_t             park_gen;
    ucontext_t                 ctx;          /* Saved execution context (makecontext/swap) */
    void                     (*fn)(void *);  /* Entry function */
    void                      *arg;          /* Argument passed to fn */
    struct march_proc         *next;         /* Intrusive link for the global run queue (mutex FIFO);
                                              * only valid while the proc is IN that queue. */
    struct march_scheduler    *owner_sched;  /* Scheduler that last ran this process */
    int                        is_daemon;    /* Daemon procs (actor recv loops) do not keep the
                                              * scheduler alive: at shutdown, once no non-daemon
                                              * procs remain and nothing is runnable, parked
                                              * daemons are woken without a message so their
                                              * loops exit and the process can terminate. */
    int                        pinned;       /* Non-zero: this proc may only ever be dispatched
                                              * by scheduler 0, which runs on the OS thread that
                                              * called march_sched_run (the process main thread
                                              * for a compiled binary).  Every enqueue of a
                                              * pinned proc goes to the scheduler-0-only run
                                              * queue instead of a Chase-Lev deque or the global
                                              * runq, so no worker can pop or steal it.  Set once
                                              * at spawn (march_sched_spawn_pinned), never
                                              * changed; calloc zero-inits to unpinned.  Ignored
                                              * when there is a single scheduler (everything
                                              * already runs on scheduler 0's thread). */
    /* Set (via march_sched_request_stop) by the ONLY two callers entitled to
     * end a blocking receive without delivering a message: the shutdown
     * endgame (wake_idle_daemons) and actor death (do_actor_death, i.e.
     * kill/crash/supervised stop). It is what makes MARCH_RECV_NO_MSG mean
     * "you were told to stop" rather than "you happened to wake with an
     * empty mailbox".
     *
     * Load-bearing: march_sched_send deposits a wake AFTER pushing, so two
     * senders racing one receiver can produce a SECOND wake whose message
     * the receiver already consumed on the first — it then resumes from a
     * fresh park with a legitimately empty mailbox. Without this flag the
     * untimed recv reported that as NO_MSG and actor_green_thread killed a
     * perfectly live actor (bench/actors/fanin_flood.march, ~4% of runs; see
     * specs/progress/2026-08-19-fanin-blocked-mailbox-spurious-actor-death.md).
     * march_sched_recv_mode now re-parks unless this is set. */
    _Atomic int                stop_requested;
    /* Compiled actor supervision: set (to a jmp_buf on THIS proc's own
     * green-thread stack) only while dispatching a message to an actor
     * that is a supervised child. march_panic longjmp's here instead of
     * exit(1)-ing the whole process. Deliberately stored on march_proc,
     * not as a _Thread_local — this scheduler is work-stealing across
     * MARCH_NUM_SCHEDULERS OS threads (march_deque_steal), so a proc can
     * resume on a DIFFERENT OS thread than the one that set the trap; a
     * thread-local would read the wrong (or another proc's) value after
     * such a migration. This field migrates with the proc itself. */
    jmp_buf                   *crash_jmp;
    char                      *crash_message; /* Panic text copied before crash_jmp fires;
                                                consumed by actor_green_thread. */
    size_t                     crash_message_len; /* Byte length; embedded NUL-safe. */
#ifdef MARCH_ASAN_BUILD
    /* ASan fiber-switch bookkeeping: this proc's own "fake stack" handle,
     * threaded through __sanitizer_start_switch_fiber/finish_switch_fiber
     * around every swapcontext() call that suspends or resumes it. Without
     * this, ASan is unaware that march's raw ucontext-based green threads
     * hop between independently-mmap'd stacks, and cannot correctly track
     * stack-use-after-return / stack-buffer-overflow across a switch. */
    void                       *asan_fake_stack;
#endif
#ifdef MARCH_TSAN_BUILD
    /* TSan fiber handle for this proc, created once (via __tsan_create_fiber)
     * at spawn time and passed to __tsan_switch_to_fiber before every
     * swapcontext() that resumes it. Same rationale as asan_fake_stack. */
    void                       *tsan_fiber;
#endif
#ifdef MARCH_DEBUG
    /* Regression tripwires for the single-owner run-queue invariant (build
     * with -DMARCH_DEBUG to arm; zero release-mode cost).  In the fixed
     * design these must NEVER fire:
     *   dbg_queued     — 1 while the proc sits in exactly one run structure
     *                    (a local deque or the global runq).  Enqueue sites
     *                    assert 0→1; dequeue sites assert 1→0, so a
     *                    double-enqueue aborts at the moment it happens.
     *   dbg_running_on — scheduler id + 1 while one scheduler is dispatched
     *                    (swapcontext-ed) into the proc, else 0.  A second
     *                    dispatcher aborts instead of corrupting the stack. */
    _Atomic int                 dbg_queued;
    _Atomic int                 dbg_running_on;
#endif
} march_proc;

/* ── Scheduler (per OS-thread) ───────────────────────────────────────── */
typedef struct march_scheduler {
    march_deque     local_queue;  /* Work-stealing deque of RUNNABLE processes   */
    march_proc     *current;      /* Currently running process (NULL = in sched) */
    ucontext_t      sched_ctx;    /* Scheduler context; processes yield here     */
    _Atomic int     running;      /* Non-zero while scheduler loop is active.
                                   * Atomic: written by the owning scheduler
                                   * thread, read concurrently by the preemption
                                   * daemon (preempt_daemon) to decide whom to
                                   * SIGUSR1 — a plain int there is a data race
                                   * (TSan: sched_loop write vs preempt_daemon
                                   * read). */
    int             id;           /* Scheduler index (0..N-1)                    */
    pthread_t       thread;       /* OS thread handle (for schedulers 1..N-1)    */
#ifdef MARCH_ASAN_BUILD
    /* ASan fiber-switch bookkeeping for THIS scheduler's own native-thread
     * "fiber" (see march_proc.asan_fake_stack for the full rationale). */
    void           *asan_fake_stack;
#endif
#ifdef MARCH_TSAN_BUILD
    /* TSan fiber handle for THIS scheduler's own native OS-thread execution,
     * captured once via __tsan_get_current_fiber() at the top of sched_loop. */
    void           *tsan_fiber;
#endif
} march_scheduler;

/* ── Public API ───────────────────────────────────────────────────────── */

/* Initialize the global scheduler.  Call once before any other sched fn. */
void         march_sched_init(void);

/* Number of OS scheduler threads this process resolved at march_sched_init:
 * the MARCH_NUM_SCHEDULERS environment request when it is usable, otherwise
 * the build's default (a compile-time pin, or one per online CPU), always
 * within [1, MARCH_MAX_SCHEDULERS].  Zero before the first march_sched_init. */
int          march_sched_num_schedulers(void);

/* How many CPUs this PROCESS may actually use: the machine's online CPUs,
 * narrowed by CPU affinity (docker --cpuset-cpus, k8s CPU pinning) and by the
 * cgroup CPU quota (docker --cpus, k8s CPU limits) where those apply.  At
 * least 1.  This is what the auto scheduler default is derived from, and it
 * is deliberately NOT sysconf(_SC_NPROCESSORS_ONLN), which reports the
 * machine and ignores both container mechanisms. */
int          march_sched_usable_cpus(void);

/* Run the scheduler loop until all spawned processes are DEAD.
 * Returns to the caller once all work drains.  Spawns N-1 worker threads
 * and runs scheduler 0 on the calling thread. */
void         march_sched_run(void);

/* Signal all scheduler workers to exit once the run-queue drains.
 * Must be called before march_sched_run() (inline path) or before
 * joining the background scheduler thread (background path). */
void         march_sched_request_shutdown(void);

/* Ask `p`'s blocking receive to give up and return MARCH_RECV_NO_MSG rather
 * than re-parking, then wake it so it observes that.  This is the ONLY way
 * to end an untimed march_sched_recv/_user without delivering a message:
 * plain march_sched_wake no longer suffices, because a wake with an empty
 * mailbox is indistinguishable from the benign send/consume race described
 * on march_proc.stop_requested and is therefore treated as spurious.
 * Idempotent; safe to call on a proc that is already dead or running. */
void         march_sched_request_stop(march_proc *p);

/* Spawn a new green thread.  Returns the new process, or NULL on failure.
 * Safe to call from within a running process (nested spawn). */
march_proc  *march_sched_spawn(void (*fn)(void *), void *arg);

/* Spawn a green thread pinned to scheduler 0 (see march_proc.pinned).  Used
 * for `main` when MARCH_PIN_MAIN=1 is set, so code that must run on the OS
 * main thread (Cocoa/GLFW window creation, some GUI toolkits) can be called
 * from `main` while the other scheduler workers keep running Tasks/pmap.
 * Procs spawned BY a pinned proc are not pinned. */
march_proc  *march_sched_spawn_pinned(void (*fn)(void *), void *arg);

/* Spawn a daemon green thread (see march_proc.is_daemon): daemons do not
 * keep the scheduler alive at shutdown.  Used for actor recv loops, which
 * park forever unless killed and must not prevent program exit once main
 * and all task procs have completed. */
march_proc  *march_sched_spawn_daemon(void (*fn)(void *), void *arg);

/* Cooperatively yield the CPU back to the scheduler. */
void         march_sched_yield(void);

/* Cooperatively yield until no OTHER process is runnable or mid-work
 * (RUNNABLE, RUNNING, PARKED, or WAITING with a non-empty mailbox).  This is
 * the in-scheduler implementation of run_until_idle(): callable only from
 * inside a green thread; a no-op otherwise. */
void         march_sched_wait_idle(void);

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

/* Return 1 if the calling OS thread is running inside the scheduler loop, 0 otherwise.
 * Used to avoid launching a redundant background scheduler thread. */
int          march_sched_in_scheduler(void);

/* Return the total number of processes ever spawned since last init. */
int64_t      march_sched_total_spawned(void);

/* Send a message to a process. Enqueues msg and wakes the target if WAITING.
 * Safe to call from any process or from the scheduler context.
 * Returns MARCH_SEND_OK (0) on success, MARCH_SEND_DEAD (-1) if target is
 * NULL or DEAD, or MARCH_SEND_DROPPED (1) if the target's mailbox is at
 * capacity under MARCH_MBOX_DROP_NEW (message was NOT enqueued). Every
 * pre-Task-7 caller treats the return as "!= 0 means didn't enqueue"/ignores
 * it outright; MARCH_SEND_DROPPED is only ever produced once a caller has
 * opted in via march_sched_set_mbox_limit. */
int          march_sched_send(march_proc *target, void *msg);

/* Enqueue a reserved runtime control value. The message bypasses every user
 * mailbox capacity/overflow policy and is stored outside the user FIFO, so a
 * later DROP_OLD send cannot evict it. Ownership matches march_sched_send. */
int          march_sched_send_control(march_proc *target, void *msg);

/* Set a mailbox capacity + overflow policy on a process. limit <= 0 means
 * unbounded (MARCH_MBOX_UNBOUNDED is the default set at spawn). Safe to call
 * while senders are concurrently active — both fields are written under
 * mbox_lock. */
void         march_sched_set_mbox_limit(march_proc *p, int64_t limit,
                                        march_mbox_policy policy);

/* Register the disposer called for a message dropped by mailbox-overflow
 * policies (DROP_NEW's rejected message, DROP_OLD's evicted message) and for
 * every message still queued in a dead proc's mailbox at reap time. The full
 * runtime (march_runtime.c) registers a real march_decrc-based dtor (Task
 * 14); until then, or in the standalone scheduler unit tests that link
 * march_scheduler.c alone, dropped/orphaned messages are leaked-with-count
 * (see MARCH_STAT_MSGS_DROPPED) rather than freed — the default is a no-op.
 *
 * Re-entrancy contract: the dtor MAY re-enter scheduler send/recv paths; it
 * is never called with any scheduler lock held. This is load-bearing, not a
 * nicety — march_decrc's free path can invoke an arbitrary FFI-registered C
 * dtor (march_run_resource_dtor), and a dtor that sends a message or
 * otherwise touches a mailbox on cleanup would deadlock (or, on a
 * non-reentrant spinlock, corrupt state) if it were called while this
 * module's own mbox_lock were held. Every call site collects the message(s)
 * to dispose under the lock, releases the lock, and only then invokes the
 * dtor. */
void         march_sched_set_msg_dtor(void (*fn)(void *));

/* Return the current mailbox depth (number of undelivered messages) for a
 * process. Relaxed atomic read — safe to call from any thread without
 * mbox_lock. Returns 0 if p is NULL. */
int64_t      march_sched_mbox_count(march_proc *p);

/* ── Cross-file stat counters (indices 3-5 of march_sched_stat) ─────────
 * Reserved slots bumped from outside march_scheduler.c (march_runtime.c and
 * later scheduler features) — exposed as a raw array so new counters don't
 * need new symbols, just a new reserved index. */
extern _Atomic int64_t march_stat_counters[8];
#define MARCH_STAT_STACK_FAIL       3
#define MARCH_STAT_MSGS_DROPPED     4
#define MARCH_STAT_STACKS_RECYCLED  5

/* Observability: a single raw stat read by index. See the index contract in
 * march_stat_counters' comment above and stdlib/scheduler.march's `stat`
 * doc. Unknown indices return 0 (forward-compatible with new counters). */
int64_t      march_sched_stat(int64_t which);

/* Sentinel returned by march_sched_recv when the process was woken without a
 * message (killed or spurious wakeup).  This is the address of a static C
 * variable — never a valid March heap object or tagged integer.
 *
 * March zero-arg constructors (e.g. Inc()) are legitimately represented as
 * the null pointer (inttoptr i64 0), so callers MUST test against
 * MARCH_RECV_NO_MSG rather than against NULL / 0. */
extern int march_recv_no_msg_sentinel;
#define MARCH_RECV_NO_MSG ((void *)&march_recv_no_msg_sentinel)

/* Receive the next message from the current process's mailbox.
 * If the mailbox is empty, parks the process as PROC_WAITING and yields
 * to the scheduler.
 *
 * Returns the message pointer on success (may be NULL for zero-arg
 * constructors!), or MARCH_RECV_NO_MSG if woken without a message. */
void        *march_sched_recv(void);

/* Receive user traffic only. Actor dispatch loops use this so reserved
 * control values remain available to an explicit language-level receive(). */
void        *march_sched_recv_user(void);

/* Try to receive without blocking. Returns the message if available,
 * NULL if mailbox is empty. Does not yield. */
void        *march_sched_try_recv(void);

/* Non-blocking receive that distinguishes "empty mailbox" from a legitimate
 * NULL message (zero-arg constructors are msg=NULL).  Returns 1 and writes
 * the message to *out if a mailbox node existed, else returns 0. */
int          march_sched_try_recv2(void **out);

/* Wake a WAITING process and re-enqueue it. No-op if not WAITING.
 * Safe to call from any context. */
void         march_sched_wake(march_proc *target);

/* Park the calling green thread: set PROC_PARKED and swapcontext back to its
 * owning scheduler, returning only once some other context has woken it via
 * march_sched_wake(march_sched_current()) (which transitions it back through
 * RUNNABLE -> RUNNING before resuming here).  A no-op if called outside the
 * scheduler (march_sched_current() == NULL).
 *
 * Unlike march_sched_recv, this does not touch the mailbox and registers no
 * wake condition itself — the caller is responsible for arranging, BEFORE
 * calling this, that something will eventually call march_sched_wake on the
 * current proc, and must re-check its own wait condition after this returns
 * (wakeups may be delayed by the PARKED->WAITING handshake but are never
 * spurious in current callers; still, don't assume the condition changed
 * without checking). */
void         march_sched_park_self(void);

#define MARCH_PARK_WOKEN   0
#define MARCH_PARK_TIMEOUT 1
/* CLOCK_MONOTONIC milliseconds. */
int64_t march_now_ms(void);
/* Park until woken or deadline (march_now_ms clock). Spurious returns
 * possible with either code; callers loop on their own condition. */
int march_sched_park_self_until(int64_t deadline_ms);

/* Like march_sched_recv, but bounded by a deadline (march_now_ms clock)
 * instead of blocking forever: holds the mailbox lock across BOTH the
 * emptiness check and the PROC_PARKED store (same discipline as
 * march_sched_recv) so a concurrent march_sched_send can never observe this
 * process as PROC_RUNNING in the gap between the two -- unlike pairing
 * march_sched_try_recv2 with march_sched_park_self_until, which has exactly
 * that lost-wakeup window.
 *
 * Returns the message pointer on success, or MARCH_RECV_NO_MSG if the
 * deadline passed OR the process was woken spuriously with an empty
 * mailbox before the deadline -- callers must re-check march_now_ms()
 * against their own deadline to tell the two apart and loop if time
 * remains (same contract as march_sched_park_self_until). */
void *march_sched_recv_until(int64_t deadline_ms);
void *march_sched_recv_user_until(int64_t deadline_ms);

/* Return the process with the given PID, or NULL if not found.
 * O(1) array lookup by PID. */
march_proc  *march_sched_find(int64_t pid);

/* ── send_after / cancel_timer (specs/progress/2026-08-12-language-level-
 * timers.md) — a SEND-kind entry in the same timer min-heap that already
 * backs march_sched_park_self_until/march_sched_recv_until, but firing
 * delivers a message (march_sched_send) instead of only waking a proc.
 *
 * Schedule `msg` for delivery to `target` at `deadline_ms` (march_now_ms
 * clock, absolute — same convention as march_sched_park_self_until/
 * march_sched_recv_until; the caller adds the delay). `target` may be NULL
 * (actor never spawned, or already known dead) -- treated uniformly with a
 * target that dies before the deadline: at fire time msg is disposed via
 * the registered message dtor (march_sched_set_msg_dtor) instead of sent.
 *
 * RC contract: receives exactly one owned reference to `msg` (same as
 * march_sched_send) and exactly one owned reference to `token` (may be
 * NULL, meaning "no cancellation support" -- the entry is simply never
 * checked for cancellation). Both are released exactly once, when
 * timer_service pops this entry -- fired, disposed, or skipped as
 * cancelled makes no difference to that release. `token`'s reference is
 * released via the registered ops (march_sched_set_timer_token_ops), never
 * by this module directly -- march_scheduler.c has no dependency on
 * March's GC (march_incrc/march_decrc); see march_sched_set_msg_dtor's own
 * doc comment for the identical rationale on the message side.
 *
 * Design decision: a pending SEND-kind entry does NOT count as "work
 * pending" for march_sched_wait_idle (unlike a WAKE-kind park/recv
 * deadline, which does). A long send_after would otherwise keep
 * run_until_idle() -- the test-harness idle-drain primitive -- from ever
 * returning; a real server drives its event loop via march_sched_run() (or
 * stays alive on non-daemon procs / other actors), which is unaffected by
 * this and still delivers the message on schedule regardless of what
 * wait_idle reports. See the timers_pending loop in
 * march_sched_wait_idle's body for the corresponding kind check. */
void march_sched_send_after(march_proc *target, void *msg, void *token,
                            int64_t deadline_ms);

/* march_timer_cancel (the March-facing cancel_timer builtin) is declared in
 * march_runtime.h, not here -- it needs march_decrc to release the token's
 * reference, which this module (march_scheduler.c) deliberately has no
 * dependency on; see this file's own module-level rationale for why. */

/* Register the callbacks used to check/release a SEND-kind timer entry's
 * cancellation token, mirroring march_sched_set_msg_dtor's indirection (and
 * re-entrancy contract: never called with any scheduler lock held) so this
 * module stays free of any direct dependency on March's GC. Until
 * registered (or in the standalone scheduler unit tests that link
 * march_scheduler.c alone), every SEND-kind entry is treated as
 * never-cancelled -- is_cancelled defaults to "always false" -- and
 * release is a no-op (token, if any, is simply not freed). */
void march_sched_set_timer_token_ops(int64_t (*is_cancelled)(void *token),
                                     void (*release)(void *token));

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

/* Preemption request flag — a PLAIN (deliberately non-thread-local) global,
 * read by every compiled function on entry.
 *
 * Why not march_tls_reductions?  Compiled code used to load/decrement/store
 * that _Thread_local counter on every call.  Thread-local access is not a
 * plain load on either supported platform: on Darwin/arm64 the symbol is a
 * TLV descriptor and each access compiles to `adrp; ldr; blr` — an INDIRECT
 * CALL into the resolver — and on Linux/arm64 PIE it goes through a TLSDESC
 * call.  A non-inlinable call on every function entry also forces a frame and
 * register spills a leaf-ish function would not otherwise need.  Measured on
 * bench/fib.march (330M calls): 0.63s with the TLS check vs 0.36s without,
 * i.e. the check cost 1.75x on call-dense recursive code.
 *
 * A plain global is `adrp; ldr` with no call, and — critically — it is only
 * ever READ on the hot path, so the cache line stays shared across scheduler
 * threads instead of ping-ponging on a per-call store.
 *
 * Set by the SIGUSR1 preemption handler on whichever scheduler threads the
 * daemon signals each quantum; cleared by march_yield_from_compiled().
 *
 * SEMANTIC NOTE — this is a per-process request, not a per-thread one.  The
 * daemon signals every scheduler thread each quantum, so previously each
 * thread yielded every quantum.  Now the first thread to observe the flag
 * clears it, so a given thread is preempted on average every
 * (num_schedulers x quantum) rather than every quantum.  Preemption remains
 * bounded and starvation-free in expectation; only the per-thread latency
 * relaxes.  The count-based trigger (yield every MARCH_REDUCTION_BUDGET
 * calls, independent of the timer) is intentionally gone: at 4000 calls it
 * fired within microseconds on call-dense code, vastly more often than the
 * 1ms quantum required, and it was pure overhead.
 *
 * volatile for the same reason as march_tls_reductions: the value must be
 * re-read rather than cached in a register across a signal delivery point. */
extern volatile int64_t march_preempt_request;

/* Called by compiled code when march_preempt_request is set.
 * Clears the request, refills the reduction budget, and cooperatively yields
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
int64_t march_cancel_token_is_cancelled(march_cancel_token *tok);

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
