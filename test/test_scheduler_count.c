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
 * Built TWICE (see test/dune), both at -DMARCH_MAX_SCHEDULERS=8 so that
 * "above the default" (7) and "above the maximum" (9) are reachable without
 * spawning a hundred threads:
 *
 *   - UNPINNED, i.e. the shipped configuration.  MARCH_NUM_SCHEDULERS is 0
 *     there ("auto"), so an unset environment must resolve to the machine's
 *     online CPU count, clamped.
 *   - PINNED at -DMARCH_NUM_SCHEDULERS=3.  A build that names a count must
 *     still get exactly that count with the environment unset -- the C test
 *     harnesses that pin themselves to 1 or 4 depend on it, and on a
 *     single-core box an auto default would silently turn their
 *     multi-scheduler premise into a no-op.
 *
 * [expected_default] below is the single place that encodes which is which. */

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
#include <time.h>

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

/* What march_sched_init must resolve to when MARCH_NUM_SCHEDULERS is unset.
 *
 * A build that pins the macro to a positive value gets exactly that; the
 * shipped build leaves it 0 ("auto") and gets one scheduler per online CPU,
 * clamped to the table size. */
static int expected_default(void) {
    if (MARCH_NUM_SCHEDULERS > 0) return MARCH_NUM_SCHEDULERS;
    /* march_sched_usable_cpus(), not sysconf: inside a container the two
     * disagree, and the runtime is required to follow the container.  Asking
     * the runtime for the CPU count pins the RELATIONSHIP (default = usable
     * CPUs, clamped) without this test reimplementing cgroup and affinity
     * parsing, which would only test the copy.  That the probe itself is
     * right is verified end-to-end under docker --cpuset-cpus and --cpus; see
     * specs/progress/2026-09-04-scheduler-default-tracks-cpu-count.md. */
    int n = march_sched_usable_cpus();
    if (n < 1) n = 1;
    return (n > MARCH_MAX_SCHEDULERS) ? MARCH_MAX_SCHEDULERS : n;
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

/* Rounds of real work every worker does before it may finish, so the run is
 * not over before the last scheduler thread has even been created. */
#define FLOOR_ROUNDS  4

/* How long the workers stay runnable waiting for the last scheduler thread to
 * dispatch one of them.  This is a bound on a HANG, not a timing expectation:
 * a healthy run observes all seven within ~100 ms even with the machine
 * oversubscribed six times over, and leaves the wait the moment it does, so
 * the value costs nothing until something is really wrong.  It is wall-clock
 * and starts when the schedulers start, so it must dwarf any stall a shared
 * CI runner can impose on one thread; see the comment on worker_fn for the
 * 10-second version of this that did not.  Overridable so the negative
 * control (a runtime built one thread short) does not take two minutes. */
#ifndef SEEN_WAIT_S
#  define SEEN_WAIT_S 120.0
#endif

static pthread_t     g_seen[N_REQUESTED * 8];
static _Atomic int   g_seen_len   = 0;
static _Atomic int   g_seen_lock  = 0;
static _Atomic int   g_work_done  = 0;
static _Atomic int   g_gave_up    = 0;        /* workers that left the wait by deadline */
static double        g_seen_deadline = 0.0;   /* set before march_sched_run, read-only after */

static double mono_now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static void burn(int64_t iters) {
    volatile int64_t x = 0;
    for (int64_t i = 0; i < iters; i++) x += i;
}

/* The OS thread this green thread is on RIGHT NOW.  glibc declares
 * pthread_self `__attribute__((const))`, so an optimising compiler may call it
 * once per function and reuse the answer across a march_sched_yield() that
 * moved the green thread to another OS thread -- every worker would then
 * report only the thread that first ran it, and a scheduler that started
 * after the global run queue drained could never be observed.  The -O0 build
 * in test/dune does not do that (checked in the object code); the volatile
 * pointer keeps it true if the flags ever change. */
static pthread_t (*volatile current_os_thread)(void) = pthread_self;

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

/* Hold every worker runnable until each requested scheduler thread has been
 * observed dispatching a green thread.
 *
 * History, because this test has been wrong twice:
 *
 *  1. A fixed round count alone was a race, not a test: whether a scheduler
 *     thread ever dispatched anything depended on whether the OS scheduled it
 *     before the last worker finished ("distinct ... 5, requested 7").
 *
 *  2. The fix held the workers runnable until all seven were seen OR a 10 s
 *     deadline passed.  It still failed on the 4-CPU CI runner, twice in three
 *     days, reruns green ("... 6, requested 7").  That deadline was armed
 *     BEFORE the spawn loop and ran concurrently with a floor of
 *     224 x 40 x burn(200000) in an unoptimised build -- 2.3 s of wall clock
 *     on 4 fast CPUs with six copies contending, more on a slower runner that
 *     dune is sharing between test binaries -- so how much of the 10 s was
 *     ever spent WAITING was unknown, and the failure message's claim that
 *     the workers had waited SEEN_WAIT_S was not something the test could
 *     know.
 *
 *  3. With the wait measured alone and raised to 120 s it failed once more on
 *     the same runner ("... 6, requested 7; ran 120.0 s of a 120 s wait;
 *     224/224 workers left by deadline").  So it is not a late thread either:
 *     no OS scheduler withholds a runnable thread for two minutes.  Reading
 *     the runtime rules out the usual suspect -- there is no park/wake to
 *     lose; an idle scheduler polls every 1 ms and makes six steal attempts
 *     per poll against deques that hold ~37 procs each -- and a further 2000
 *     runs (arm64 and emulated amd64, cpuset and quota limits, 8x contention)
 *     did not fail once.  What the failure line could not say is what the
 *     seventh scheduler was DOING, so it now does: see report_thread_stats.
 *
 * The CI failure itself was never reproduced: 0 failures in about 500 runs of
 * the old test on 4 CPUs, most under 6x contention.  What those runs did
 * establish is that it is not work distribution.  The last thread is first
 * seen within 90 ms in 180/180 runs, and the seven threads' dispatch counts
 * stay within ~25% of each other: a scheduler that just ran a yielder steals
 * before it pops its own deque, so procs keep migrating and a thread that is
 * running cannot go without.  Nor did a thread fail to start: at the
 * time pthread_create's result was unchecked in march_sched_run, and a failed
 * create crashed in pthread_join rather than reporting 6 (confirmed under
 * `docker run --pids-limit 6`; the runtime now checks it, and reports the
 * shortfall on stderr).
 *
 * So: a small floor, then every worker stays RUNNABLE -- yielding, so it
 * stays stealable -- until all N_REQUESTED threads have dispatched one, or a
 * deadline that is long and that counts only this wait.  A thread that exists
 * cannot avoid being observed; a count that is genuinely short still fails
 * (after the wait), and the failure says how long was really waited. */
static void worker_fn(void *arg) {
    (void)arg;
    for (int round = 0; round < FLOOR_ROUNDS; round++) {
        seen_record(current_os_thread());
        burn(200000);
        march_sched_yield();
    }
    while (atomic_load_explicit(&g_seen_len, memory_order_relaxed) < N_REQUESTED) {
        if (mono_now() >= g_seen_deadline) {
            atomic_fetch_add(&g_gave_up, 1);
            break;
        }
        seen_record(current_os_thread());
        burn(20000);
        march_sched_yield();
    }
    seen_record(current_os_thread());
    atomic_fetch_add(&g_work_done, 1);
}

/* One line per scheduler saying how far it got, which separates the four ways
 * a thread can go unobserved: never created (started=0), created but never
 * reached its loop (entered=0), looping without ever finding work
 * (idle_polls in the tens of thousands, dispatches=0), or dispatching without
 * being recorded (dispatches>0 on all seven -- a bug in this file). */
static void report_thread_stats(void) {
    for (int i = 0; i < march_sched_num_schedulers(); i++)
        fprintf(stderr, "  (scheduler %d: started=%lld entered=%lld "
                        "dispatches=%lld idle_polls=%lld)\n", i,
                (long long)march_sched_thread_stat(i, MARCH_THREAD_STAT_STARTED),
                (long long)march_sched_thread_stat(i, MARCH_THREAD_STAT_ENTERED),
                (long long)march_sched_thread_stat(i, MARCH_THREAD_STAT_DISPATCHES),
                (long long)march_sched_thread_stat(i, MARCH_THREAD_STAT_IDLE_POLLS));
}

static void test_live_scheduler_threads_match_request(void) {
    char err[512];
    int n = init_with("7", err, sizeof err);
    TEST_ASSERT(n == N_REQUESTED, "setup: 7 schedulers requested");
    atomic_store(&g_seen_len, 0);
    atomic_store(&g_work_done, 0);
    atomic_store(&g_gave_up, 0);
    for (int i = 0; i < N_WORKERS; i++) march_sched_spawn(worker_fn, NULL);
    march_sched_request_shutdown();
    /* Armed here, not before the spawn loop: nothing runs until
     * march_sched_run, so this is when the wait can first begin. */
    double t0 = mono_now();
    g_seen_deadline = t0 + SEEN_WAIT_S;
    march_sched_run();
    double elapsed = mono_now() - t0;
    TEST_ASSERT(atomic_load(&g_work_done) == N_WORKERS, "all workers finished");
    int distinct = atomic_load(&g_seen_len);
    if (distinct != N_REQUESTED)
        fprintf(stderr, "  (distinct dispatching OS threads: %d, requested %d; "
                        "ran %.1f s of a %.0f s wait; %d/%d workers left by deadline; "
                        "usable CPUs %d)\n",
                distinct, N_REQUESTED, elapsed, (double)SEEN_WAIT_S,
                atomic_load(&g_gave_up), N_WORKERS, march_sched_usable_cpus());
    if (distinct != N_REQUESTED || getenv("SCHED_COUNT_STATS")) report_thread_stats();
    TEST_ASSERT(distinct == N_REQUESTED,
                "green threads must be dispatched by exactly as many OS threads as "
                "requested -- every worker stayed runnable for the whole of "
                "SEEN_WAIT_S waiting for the missing thread (see the line above), "
                "so this is a real shortfall, not a thread that merely started late");
    /* The runtime's own account must agree with what the workers saw. */
    for (int i = 0; i < N_REQUESTED; i++) {
        TEST_ASSERT(march_sched_thread_stat(i, MARCH_THREAD_STAT_STARTED) == 1,
                    "every requested scheduler thread was created");
        TEST_ASSERT(march_sched_thread_stat(i, MARCH_THREAD_STAT_DISPATCHES) > 0,
                    "every scheduler the workers saw has a non-zero dispatch count");
    }
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
    TEST_ASSERT(n == expected_default(),
                "an unset variable uses the build's default: the pinned count, "
                "or one per online CPU when the build did not pin one");
    TEST_ASSERT(err[0] == '\0', "the default path must not warn");
    TEST_PASS();
}

static void test_malformed_warns_and_uses_default(void) {
    char err[512];
    int n = init_with("banana", err, sizeof err);
    TEST_ASSERT(n == expected_default(), "a malformed value falls back to the default");
    TEST_ASSERT(err[0] != '\0', "a malformed value must be reported, not silently ignored");
    TEST_PASS();
}

static void test_zero_warns_and_uses_default(void) {
    char err[512];
    int n = init_with("0", err, sizeof err);
    TEST_ASSERT(n == expected_default(), "0 is not a legal scheduler count; use the default");
    TEST_ASSERT(err[0] != '\0', "0 must be reported");
    TEST_PASS();
}

/* ── 5. auto ───────────────────────────────────────────────────────────── */

static void test_auto_tracks_cpu_count(void) {
    char err[512];
    int n = init_with("auto", err, sizeof err);
    int expect = march_sched_usable_cpus();
    if (expect < 1) expect = 1;
    if (expect > MARCH_MAX_SCHEDULERS) expect = MARCH_MAX_SCHEDULERS;
    TEST_ASSERT(n == expect, "auto = usable CPUs, clamped to the maximum");
    /* A container narrows what this process may use; the machine's raw online
     * count is only ever an upper bound. Asserting that separately keeps the
     * probe honest if it ever starts reporting MORE than the machine has. */
    long online = sysconf(_SC_NPROCESSORS_ONLN);
    if (online >= 1)
        TEST_ASSERT(march_sched_usable_cpus() <= (int)online,
                    "usable CPUs never exceed the machine's online CPUs");
    TEST_ASSERT(err[0] == '\0', "auto is always satisfiable and must not warn");
    /* On the shipped (unpinned) build, "auto" and "unset" must be the SAME
     * thing -- if they ever diverge, the default stopped tracking the
     * machine and this suite would otherwise not notice. */
    if (MARCH_NUM_SCHEDULERS == 0)
        TEST_ASSERT(n == expected_default(),
                    "on an unpinned build, auto and an unset variable agree");
    TEST_PASS();
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    /* Report what march_sched_init ACTUALLY resolves, not what this file
     * predicts -- a banner printing the prediction would have agreed with
     * itself while the runtime disagreed, which is exactly how the container
     * case first looked fine. */
    unsetenv("MARCH_NUM_SCHEDULERS");
    march_sched_init();
    printf("=== March scheduler — thread-count request "
           "(build default %s; usable CPUs %d, online %ld; "
           "unset resolves to %d; max %d) ===\n",
           MARCH_NUM_SCHEDULERS > 0 ? "pinned" : "auto",
           march_sched_usable_cpus(), sysconf(_SC_NPROCESSORS_ONLN),
           march_sched_num_schedulers(), MARCH_MAX_SCHEDULERS);
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
