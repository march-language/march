/* runtime/march_preempt.h — guard blocking syscalls against preemption signals.
 *
 * The scheduler preempts green threads by delivering SIGUSR1 to every scheduler
 * thread roughly every MARCH_QUANTUM_US (1ms); see runtime/march_scheduler.c.
 * That signal must NOT interrupt a blocking libc call, for three distinct
 * reasons:
 *
 *   - getaddrinfo() runs through libdispatch/libsystem_info on macOS and is not
 *     async-signal-safe.  A SIGUSR1 landing inside it (very likely, since
 *     resolving "localhost" takes several ms while preemption fires every 1ms)
 *     corrupts the dispatch state and aborts the whole process with SIGILL.
 *
 *   - recv()/send()/connect() would return EINTR, which most callers do not
 *     retry, surfacing as spurious "connection closed" errors or wedged reads.
 *
 *   - MOST SUBTLY, AND THE REASON READ DEADLINES NEED THIS: SIGUSR1 is installed
 *     with SA_RESTART (march_scheduler.c), so the kernel RESTARTS an interrupted
 *     recv() rather than failing it — and a restarted recv() restarts its
 *     SO_RCVTIMEO timer from zero.  With preemption firing every ~1ms and a
 *     deadline measured in hundreds of ms, the timer can never accumulate: the
 *     socket option is correctly set, reports correctly on getsockopt, and is
 *     silently defeated, leaving the read blocked forever.  Any read that must
 *     honour a deadline — plain recv() or an SSL_read() sitting on top of one —
 *     has to mask SIGUSR1 for its duration.
 *
 * Blocking SIGUSR1 for the duration of the call leaves the signal pending; the
 * kernel delivers it the instant the mask is lifted, so preemption is merely
 * deferred past the syscall, never lost.  A thread parked in a blocking syscall
 * is not burning its scheduling quantum anyway, so deferral is harmless.
 *
 * NOTE the scope limit called out in PR #320: pthread_sigmask is per-OS-thread
 * while green threads multiplex over those threads.  That is sound here because
 * the mask is taken and released around a single syscall on the thread actually
 * making it, with no yield point in between — do not hold it across anything
 * that can reschedule.
 */
#pragma once
#include <pthread.h>
#include <signal.h>

static inline void march_block_preempt(sigset_t *saved) {
    sigset_t blk;
    sigemptyset(&blk);
    sigaddset(&blk, SIGUSR1);
    pthread_sigmask(SIG_BLOCK, &blk, saved);
}

static inline void march_unblock_preempt(const sigset_t *saved) {
    pthread_sigmask(SIG_SETMASK, saved, NULL);
}
