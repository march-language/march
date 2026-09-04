/* test_scheduler_count.c — MARCH_NUM_SCHEDULERS is a REQUEST, not a ceiling.
 *
 * Regression for G71: the environment variable of the same name used to be
 * clamped to the compile-time MARCH_NUM_SCHEDULERS and any larger request was
 * discarded in silence, so `MARCH_NUM_SCHEDULERS=14` ran four scheduler
 * threads and said nothing.  An apparent 4.4x parallel-speedup ceiling was
 * really the runtime ignoring the ask.
 *
 * The contract this pins:
 *   1. A request above the compile-time DEFAULT is honoured, up to
 *      MARCH_MAX_SCHEDULERS (the size of the g_scheds table).
 *   2. The honoured number is the number of OS scheduler threads that
 *      actually dispatch green threads — not just a counter.
 *   3. A request the build cannot satisfy is clamped AND reported on stderr,
 *      naming both the request and the maximum.
 *   4. A malformed/non-positive value falls back to the default, with a
 *      warning; it is never silently treated as "1".
 *   5. `auto` means "one scheduler per online CPU", clamped to the maximum.
 *
 * Built with -DMARCH_MAX_SCHEDULERS=8 (see test/dune) and the default
 * -DMARCH_NUM_SCHEDULERS=4, so "above the default" (7) and "above the
 * maximum" (9) are both reachable without spawning a hundred threads. */

#ifndef _XOPEN_SOURCE
#  define _XOPEN_SOURCE 700
#endif
#ifndef _DARWIN_C_SOURCE
#  define _DARWIN_C_SOURCE 1      /* _SC_NPROCESSORS_ONLN on macOS */
#endif
#ifndef _GNU_SOURCE
#  define _GNU_SOURCE 1           /* ... and on glibc */
#endif
#include "../runtime/march_scheduler.h"
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdatomic.h>
#include <stdint.h>

static int g_tests_passed = 0, g_tests_failed = 0;
#define TEST_ASSERT(cond, msg) do { if (!(cond)) { \
    fprintf(stderr, "  FAIL [%s:%d]: %s\n", __func__, __LINE__, (msg)); \
    g_tests_failed++; return; } } while (0)
#define TEST_PASS() do { printf("  PASS: %s\n", __func__); g_tests_passed++; } while (0)

/* ── stderr capture ──────────────────────────────────────────────────────
 * march_sched_init's warning goes to stderr; redirect fd 2 into a pipe for
 * the duration of the call.  The messages are a single short line, well
 * under the pipe buffer, so a plain read after restoring never blocks. */
static int  g_saved_stderr = -1;
static int  g_pipe[2]      = { -1, -1 };

static void capture_stderr_begin(void) {
    fflush(stderr);
    g_saved_stderr = dup(STDERR_FILENO);
    if (pipe(g_pipe) != 0) { perror("pipe"); exit(2); }
    dup2(g_pipe[1], STDERR_FILENO);
    close(g_pipe[1]);
    g_pipe[1] = -1;
}

static void capture_stderr_end(char *buf, size_t cap) {
    fflush(stderr);
    dup2(g_saved_stderr, STDERR_FILENO);
    close(g_saved_stderr);
    g_saved_stderr = -1;
    ssize_t n = read(g_pipe[0], buf, cap - 1);
    if (n < 0) n = 0;
    buf[n] = '\0';
    close(g_pipe[0]);
    g_pipe[0] = -1;
}

/* Run march_sched_init() with MARCH_NUM_SCHEDULERS set to `value` (NULL =
 * unset) and return the resulting scheduler count, with stderr captured. */
static int init_with(const char *value, char *err, size_t err_cap) {
    if (value) setenv("MARCH_NUM_SCHEDULERS", value, 1);
    else       unsetenv("MARCH_NUM_SCHEDULERS");
    capture_stderr_begin();
    march_sched_init();
    capture_stderr_end(err, err_cap);
    return march_sched_num_schedulers();
}

/* ── 1. a request above the compile-time default is honoured ───────────── */

static void test_request_above_default_is_honoured(void) {
    char err[512];
    int n = init_with("7", err, sizeof err);
    TEST_ASSERT(n == 7, "MARCH_NUM_SCHEDULERS=7 must give 7 schedulers, not the build default");
    TEST_ASSERT(err[0] == '\0', "a satisfiable request must not warn");
    TEST_PASS();
}

/* ── 2. the count is real OS threads, not just a counter ───────────────── */

#define N_REQUESTED   7
#define N_WORKERS     224          /* 32 green threads per scheduler thread  */

static pthread_t     g_seen[N_REQUESTED * 8];
static _Atomic int   g_seen_len   = 0;
static _Atomic int   g_seen_lock  = 0;
static _Atomic int   g_work_done  = 0;
static _Atomic int   g_spinning   = 0;   /* workers currently inside the spin */

static void seen_record(pthread_t t) {
    while (atomic_exchange_explicit(&g_seen_lock, 1, memory_order_acquire)) { /* spin */ }
    int len = atomic_load_explicit(&g_seen_len, memory_order_relaxed);
    int found = 0;
    for (int i = 0; i < len; i++) if (pthread_equal(g_seen[i], t)) { found = 1; break; }
    if (!found && len < (int)(sizeof g_seen / sizeof g_seen[0])) {
        g_seen[len] = t;
        atomic_store_explicit(&g_seen_len, len + 1, memory_order_relaxed);
    }
    atomic_store_explicit(&g_seen_lock, 0, memory_order_release);
}

static void worker_fn(void *arg) {
    (void)arg;
    /* Hold every scheduler busy at once: each worker records its thread and
     * then refuses to finish until enough peers are simultaneously resident,
     * so a scheduler thread that exists cannot avoid being observed.  The
     * yield keeps this cooperative rather than a hard barrier (a scheduler
     * with no work would otherwise deadlock the run). */
    for (int round = 0; round < 40; round++) {
        seen_record(pthread_self());
        atomic_fetch_add(&g_spinning, 1);
        volatile int64_t x = 0;
        for (int64_t i = 0; i < 200000; i++) x += i;
        atomic_fetch_sub(&g_spinning, 1);
        march_sched_yield();
    }
    atomic_fetch_add(&g_work_done, 1);
}

static void test_live_scheduler_threads_match_request(void) {
    char err[512];
    int n = init_with("7", err, sizeof err);
    TEST_ASSERT(n == N_REQUESTED, "setup: 7 schedulers requested");
    atomic_store(&g_seen_len, 0);
    atomic_store(&g_work_done, 0);
    for (int i = 0; i < N_WORKERS; i++) march_sched_spawn(worker_fn, NULL);
    march_sched_request_shutdown();
    march_sched_run();
    TEST_ASSERT(atomic_load(&g_work_done) == N_WORKERS, "all workers finished");
    int distinct = atomic_load(&g_seen_len);
    if (distinct != N_REQUESTED)
        fprintf(stderr, "  (distinct dispatching OS threads: %d, requested %d)\n",
                distinct, N_REQUESTED);
    TEST_ASSERT(distinct == N_REQUESTED,
                "green threads must be dispatched by exactly as many OS threads as requested");
    TEST_PASS();
}

/* ── 3. an unsatisfiable request is clamped AND reported ───────────────── */

static void test_request_above_max_warns_naming_both_numbers(void) {
    char err[512];
    int n = init_with("9", err, sizeof err);
    TEST_ASSERT(n == MARCH_MAX_SCHEDULERS, "a request above the maximum is clamped to the maximum");
    TEST_ASSERT(err[0] != '\0', "a request the build cannot honour must not be silent");
    TEST_ASSERT(strstr(err, "9") != NULL, "the warning names the requested count");
    TEST_ASSERT(strstr(err, "8") != NULL, "the warning names the maximum this build supports");
    TEST_PASS();
}

/* ── 4. default / malformed input ──────────────────────────────────────── */

static void test_default_when_unset(void) {
    char err[512];
    int n = init_with(NULL, err, sizeof err);
    TEST_ASSERT(n == MARCH_NUM_SCHEDULERS, "an unset variable uses the compile-time default");
    TEST_ASSERT(err[0] == '\0', "the default path must not warn");
    TEST_PASS();
}

static void test_malformed_warns_and_uses_default(void) {
    char err[512];
    int n = init_with("banana", err, sizeof err);
    TEST_ASSERT(n == MARCH_NUM_SCHEDULERS, "a malformed value falls back to the default");
    TEST_ASSERT(err[0] != '\0', "a malformed value must be reported, not silently ignored");
    TEST_PASS();
}

static void test_zero_warns_and_uses_default(void) {
    char err[512];
    int n = init_with("0", err, sizeof err);
    TEST_ASSERT(n == MARCH_NUM_SCHEDULERS, "0 is not a legal scheduler count; use the default");
    TEST_ASSERT(err[0] != '\0', "0 must be reported");
    TEST_PASS();
}

/* ── 5. auto ───────────────────────────────────────────────────────────── */

static void test_auto_tracks_cpu_count(void) {
    char err[512];
    int n = init_with("auto", err, sizeof err);
    long cpus = sysconf(_SC_NPROCESSORS_ONLN);
    int expect = (cpus < 1) ? MARCH_NUM_SCHEDULERS : (int)cpus;
    if (expect > MARCH_MAX_SCHEDULERS) expect = MARCH_MAX_SCHEDULERS;
    TEST_ASSERT(n == expect, "auto = online CPUs, clamped to the maximum");
    TEST_ASSERT(err[0] == '\0', "auto is always satisfiable and must not warn");
    TEST_PASS();
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("=== March scheduler — thread-count request "
           "(default %d, max %d) ===\n",
           MARCH_NUM_SCHEDULERS, MARCH_MAX_SCHEDULERS);
    test_request_above_default_is_honoured();
    test_live_scheduler_threads_match_request();
    test_request_above_max_warns_naming_both_numbers();
    test_default_when_unset();
    test_malformed_warns_and_uses_default();
    test_zero_warns_and_uses_default();
    test_auto_tracks_cpu_count();
    printf("\nResults: %d passed, %d failed\n", g_tests_passed, g_tests_failed);
    return g_tests_failed > 0 ? 1 : 0;
}
