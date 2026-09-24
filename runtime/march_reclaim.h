#pragma once
/* march_reclaim — epoch-based reclamation for actor-lifetime structures.
 *
 * Design: specs/progress/2026-09-23-proc-struct-reclamation-metas.md, "Chosen
 * mechanism".  Procs are the first user (march_scheduler.c's PROC_DEAD reap);
 * actor metas are the second (a later PR).
 *
 * THE RULE every caller is read against:
 *
 *   A resolved pointer to a reclaimable structure (a `march_proc *` loaded
 *   from anything other than the caller's own running proc) is valid ONLY
 *   inside the critical section it was resolved in, and never across a
 *   context switch.
 *
 * The original corruption was a pointer that outlived the fact it named, not
 * a free.  Every holder converted for this module keeps an identity that does
 * not dangle (a pid) and resolves it inside a critical section.
 *
 * Two flavours of reader, one slot per OS thread:
 *
 *   - A SCHEDULER thread is quiescent-state based.  sched_loop announces a
 *     quiescent state at the top of every iteration, when no green thread is
 *     running and so no resolved pointer can be live, and goes offline while
 *     it idle-sleeps.  Everything a green thread does between two dispatches
 *     is implicitly inside a critical section; march_reclaim_enter/exit there
 *     only move a depth counter, which is what makes a violation (a critical
 *     section held across a park) detectable: every swapcontext that suspends
 *     a proc calls march_reclaim_check_switch first, which aborts on a
 *     non-zero depth.
 *   - Any OTHER thread (the preempt daemon, HTTP evloop threads, a REPL host,
 *     FFI workers, anything that calls march_send) is explicit: its slot is
 *     offline except between an outermost enter and exit.
 *
 * Slots are registered lazily on a thread's first enter (any thread), recycled
 * at thread exit through a pthread_key destructor, and never freed.
 *
 * Retired objects are freed once every online slot has announced an epoch
 * later than the one they were retired in.  Nothing ever WAITS for a grace
 * period: the retire list is polled (from march_reclaim_retire, amortised, and
 * from the preempt daemon's tick), so a reader can never deadlock a reclaimer
 * and a quiesced node drains completely. */

#include <stdint.h>

/* Enter / leave a read-side critical section.  Nestable.  On a scheduler
 * thread: a TLS depth counter.  Elsewhere: the outermost enter announces the
 * current epoch and issues a full fence (the announcement must be visible
 * before the loads it protects); the outermost exit is a release store. */
void    march_reclaim_enter(void);
void    march_reclaim_exit(void);

/* Current critical-section depth of the calling OS thread. */
int     march_reclaim_depth(void);

/* Abort (naming [site]) if the calling thread is inside a critical section.
 * Called before every swapcontext that suspends a proc: a resolved pointer
 * must never survive a context switch, because the scheduler thread announces
 * a quiescent state before it dispatches anything else. */
void    march_reclaim_check_switch(const char *site);

/* A path that must WAIT while inside a critical section (the MARCH_MBOX_BLOCK
 * sender's park, a foreign thread's sleep-poll) suspends it around the wait
 * and re-resolves every pointer by identity afterwards.  suspend returns the
 * depth to hand back to resume; resume may run on a different OS thread (a
 * green thread migrates across a park).  Both are noinline by construction
 * (they live in their own translation unit), so the TLS they touch is always
 * the CURRENT thread's. */
int     march_reclaim_suspend(void);
void    march_reclaim_resume(int depth);

/* Scheduler-thread hooks (march_scheduler.c's sched_loop only). */
void    march_reclaim_sched_attach(void);   /* sched_loop start: QSBR, online */
void    march_reclaim_quiescent(void);      /* top of every loop iteration    */
void    march_reclaim_offline(void);        /* before an idle sleep           */
void    march_reclaim_online(void);         /* after an idle sleep            */
void    march_reclaim_sched_detach(void);   /* sched_loop exit: explicit, offline */

/* Hand [p] to the reclaimer: [free_fn](p) runs once no thread can still hold a
 * pointer to it that it resolved before this call.  The caller must already
 * have made [p] unreachable to NEW readers (unlinked it from every structure a
 * reader can resolve it through). */
void    march_reclaim_retire(void *p, void (*free_fn)(void *));

/* Free whatever has passed its grace period.  Safe from any thread, including
 * one inside a critical section (its own announcement then holds back what it
 * could still be reading). */
void    march_reclaim_poll(void);

/* Observability: objects retired and freed since process start. */
int64_t march_reclaim_retired_count(void);
int64_t march_reclaim_freed_count(void);
