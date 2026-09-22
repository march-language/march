/* test_preempt_signal.c — the preemption signal coexists with a host's use of it.
 *
 * March preempts green threads by signalling scheduler threads every ~1ms.
 * That signal used to be a hardcoded SIGUSR1 whose handler REPLACED whatever
 * the host process had installed and never gave it back: embedded in the BEAM
 * as a NIF, `kill -USR1 <beam>` stopped writing a crash dump (measured, see
 * specs/2026-08-02-nif-feasibility-assessment.md).  This pins the fix
 * (specs/todos -> progress 2026-09-21-preempt-signal-configurable):
 *
 *   1. host_handler_chained: a host SIGUSR1 handler installed before March
 *      keeps receiving other processes' SIGUSR1 while green threads run, never
 *      receives March's own ticks, preemption still fires, and the host
 *      handler is back in place after the scheduler stops.
 *   2. default_disposition_survives_stop: with SIGUSR1 at SIG_DFL (which
 *      terminates), stopping the scheduler restores SIG_DFL without a pending
 *      tick killing the process.
 *   3. env_moves_signal: MARCH_PREEMPT_SIGNAL=USR2 leaves SIGUSR1 untouched
 *      for the whole run and still preempts.
 *   4. env_rt_signal (Linux): MARCH_PREEMPT_SIGNAL=RTMIN+1 preempts too.
 *   5. bad_env_falls_back / api_rejects_bad_signal: an unusable signal is
 *      refused, with a warning for the env var.
 *
 * Every case runs in a fork()ed child: signal dispositions and the resolved
 * preemption signal are process-global, so isolation is by process.
 *
 * The "host" deliveries come from a SEPARATE process on purpose.  An in-process
 * kill() carries our own pid and can coalesce with a pending tick into one
 * delivery, which the runtime then (correctly) treats as its own; a delivery
 * from another pid is always chained, so the assertion below is exact.
 */
#ifndef _GNU_SOURCE
#  define _GNU_SOURCE 1
#endif
#ifndef _DARWIN_C_SOURCE
#  define _DARWIN_C_SOURCE 1
#endif
#include "../runtime/march_scheduler.h"
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define CHECK(cond, msg) do {                                               \
    if (!(cond)) {                                                          \
        fprintf(stderr, "  FAIL [%s:%d]: %s\n", __func__, __LINE__, (msg)); \
        _exit(1);                                                           \
    }                                                                       \
} while (0)

static double now_s(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

/* ── the host's handler ─────────────────────────────────────────────────── */
static volatile sig_atomic_t g_host_external = 0;  /* deliveries from another pid */
static volatile sig_atomic_t g_host_own_pid  = 0;  /* deliveries carrying our pid: leaked ticks */

static void host_handler(int sig, siginfo_t *si, void *uc) {
    (void)sig; (void)uc;
    if (si && si->si_pid != getpid()) g_host_external++;
    else                              g_host_own_pid++;
}

static void install_host_handler(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = host_handler;
    sa.sa_flags = SA_SIGINFO | SA_RESTART;
    sigemptyset(&sa.sa_mask);
    if (sigaction(SIGUSR1, &sa, NULL) != 0) { perror("sigaction"); _exit(2); }
}

static int usr1_is_host_handler(void) {
    struct sigaction cur;
    sigaction(SIGUSR1, NULL, &cur);
    return (cur.sa_flags & SA_SIGINFO) && cur.sa_sigaction == host_handler;
}

/* ── the green-thread workload ──────────────────────────────────────────── */
static _Atomic long g_preempts_seen = 0;   /* ticks observed by spinning workers */
static _Atomic int  g_usr1_changed  = 0;   /* SIGUSR1 disposition seen != host's */
static int          g_watch_usr1    = 0;   /* worker checks SIGUSR1 each spin */

static void spin_worker(void *arg) {
    double until = now_s() + (double)(intptr_t)arg / 1000.0;
    while (now_s() < until) {
        if (march_preempt_request) {
            march_preempt_request = 0;
            atomic_fetch_add(&g_preempts_seen, 1);
        }
        if (g_watch_usr1 && !usr1_is_host_handler())
            atomic_store(&g_usr1_changed, 1);
    }
}

static void run_green_threads(int n, int ms) {
    march_sched_init();
    for (int i = 0; i < n; i++) march_sched_spawn(spin_worker, (void *)(intptr_t)ms);
    march_sched_request_shutdown();   /* return once the workers finish */
    march_sched_run();
}

/* Another process sends `count` SIGUSR1s to `target`, `gap_ms` apart. */
static pid_t start_external_sender(pid_t target, int count, int gap_ms) {
    pid_t c = fork();
    if (c == 0) {
        struct timespec ts = { 0, (long)gap_ms * 1000000L };
        for (int i = 0; i < count; i++) { nanosleep(&ts, NULL); kill(target, SIGUSR1); }
        _exit(0);
    }
    return c;
}

/* ── cases ──────────────────────────────────────────────────────────────── */
static void host_handler_chained(void) {
    install_host_handler();
    pid_t sender = start_external_sender(getpid(), 20, 10);   /* over ~200 ms */
    run_green_threads(2, 400);
    waitpid(sender, NULL, 0);
    CHECK(atomic_load(&g_preempts_seen) > 0, "preemption still fires");
    CHECK(g_host_external > 0,
          "the host's handler received another process's SIGUSR1 while March ran");
    CHECK(g_host_own_pid == 0, "none of March's own ticks leaked into the host's handler");
    CHECK(usr1_is_host_handler(), "the host's handler is restored after the scheduler stops");
    printf("  PASS: host_handler_chained (external=%d preempts=%ld)\n",
           (int)g_host_external, atomic_load(&g_preempts_seen));
}

static void default_disposition_survives_stop(void) {
    /* SIGUSR1 at SIG_DFL (terminate).  Surviving to the checks at all is the
     * point: a tick left pending at stop would kill us here. */
    for (int round = 0; round < 20; round++) run_green_threads(2, 20);
    struct sigaction cur;
    sigaction(SIGUSR1, NULL, &cur);
    CHECK(!(cur.sa_flags & SA_SIGINFO) && cur.sa_handler == SIG_DFL,
          "SIG_DFL restored after the scheduler stops");
    CHECK(atomic_load(&g_preempts_seen) > 0, "preemption fired");
    printf("  PASS: default_disposition_survives_stop (20 start/stop rounds)\n");
}

static void env_moves_signal(void) {
    setenv("MARCH_PREEMPT_SIGNAL", "USR2", 1);
    install_host_handler();
    g_watch_usr1 = 1;
    run_green_threads(2, 200);
    CHECK(march_preempt_signal() == SIGUSR2, "MARCH_PREEMPT_SIGNAL=USR2 is honoured");
    CHECK(atomic_load(&g_usr1_changed) == 0, "SIGUSR1 untouched for the whole run");
    CHECK(g_host_own_pid == 0, "no delivery reached the SIGUSR1 host handler");
    CHECK(atomic_load(&g_preempts_seen) > 0, "preemption fires on SIGUSR2");
    printf("  PASS: env_moves_signal\n");
}

#ifdef SIGRTMIN
static void env_rt_signal(void) {
    setenv("MARCH_PREEMPT_SIGNAL", "RTMIN+1", 1);
    run_green_threads(2, 200);
    CHECK(march_preempt_signal() == SIGRTMIN + 1, "RTMIN+1 is honoured");
    CHECK(atomic_load(&g_preempts_seen) > 0, "preemption fires on a real-time signal");
    printf("  PASS: env_rt_signal\n");
}
#endif

static void bad_env_falls_back(void) {
    setenv("MARCH_PREEMPT_SIGNAL", "KILL", 1);
    CHECK(march_preempt_signal() == SIGUSR1, "an unusable signal falls back to SIGUSR1");
    printf("  PASS: bad_env_falls_back\n");
}

static void api_rejects_bad_signal(void) {
    CHECK(march_sched_set_preempt_signal(SIGKILL) == -1, "SIGKILL refused");
    CHECK(march_sched_set_preempt_signal(SIGSEGV) == -1, "SIGSEGV refused");
    CHECK(march_sched_set_preempt_signal(SIGUSR2) == 0, "SIGUSR2 accepted");
    CHECK(march_preempt_signal() == SIGUSR2, "the chosen signal is in effect");
    printf("  PASS: api_rejects_bad_signal\n");
}

static int run_case(const char *name, void (*fn)(void)) {
    fflush(stdout);
    pid_t c = fork();
    if (c == 0) { alarm(30); fn(); fflush(stdout); _exit(0); }   /* a hang fails, not wedges */
    int st = 0;
    waitpid(c, &st, 0);
    if (WIFEXITED(st) && WEXITSTATUS(st) == 0) return 0;
    if (WIFSIGNALED(st))
        fprintf(stderr, "  FAIL: %s killed by signal %d\n", name, WTERMSIG(st));
    else
        fprintf(stderr, "  FAIL: %s exited %d\n", name, WEXITSTATUS(st));
    return 1;
}

int main(void) {
    unsetenv("MARCH_PREEMPT_SIGNAL");
    int failed = 0;
    failed += run_case("host_handler_chained", host_handler_chained);
    failed += run_case("default_disposition_survives_stop", default_disposition_survives_stop);
    failed += run_case("env_moves_signal", env_moves_signal);
#ifdef SIGRTMIN
    failed += run_case("env_rt_signal", env_rt_signal);
#endif
    failed += run_case("bad_env_falls_back", bad_env_falls_back);
    failed += run_case("api_rejects_bad_signal", api_rejects_bad_signal);
    if (failed) { fprintf(stderr, "test_preempt_signal: %d case(s) failed\n", failed); return 1; }
    printf("test_preempt_signal: all cases passed\n");
    return 0;
}
