/* march_sched_wait_fd: park a green thread on a socket instead of blocking
 * its scheduler thread.  Compiled standalone with march_scheduler.c only,
 * at ONE scheduler thread (-DMARCH_NUM_SCHEDULERS=1): every case here has
 * two green threads where one waits on a socket the other has yet to write,
 * so with a single OS thread the only way the writer ever runs is if the
 * waiter really parked.  A wait that blocked the thread would hang the case,
 * and alarm(30) turns that hang into a failure.
 * specs/progress/2026-09-16-park-socket-waits.md. */
#include "march_scheduler.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdatomic.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <netdb.h>
#include <stdlib.h>

static int g_sv[2];
static _Atomic int     g_result   = -99;
static _Atomic int64_t g_waited   = -1;
static _Atomic int     g_second   = -99;

/* A parking delay: park_self_until, never usleep (which would hold the one
 * scheduler thread and prove nothing). */
static void nap(int64_t ms) {
    int64_t until = march_now_ms() + ms;
    while (march_now_ms() < until) march_sched_park_self_until(until);
}

/* 1. Woken by a write that happens AFTER the wait began. */
static void waiter_woken(void *arg) {
    (void)arg;
    int64_t start = march_now_ms();
    int r = march_sched_wait_fd(g_sv[0], 0, march_now_ms() + 5000);
    atomic_store(&g_result, r);
    atomic_store(&g_waited, march_now_ms() - start);
}
static void late_writer(void *arg) {
    (void)arg;
    nap(60);
    char c = 'x';
    (void)write(g_sv[1], &c, 1);
}

/* 2. A silent peer: the deadline fires, and only the deadline. */
static void waiter_times_out(void *arg) {
    (void)arg;
    int64_t start = march_now_ms();
    int r = march_sched_wait_fd(g_sv[0], 0, march_now_ms() + 120);
    atomic_store(&g_result, r);
    atomic_store(&g_waited, march_now_ms() - start);
}

/* 3. Data already there before the wait: ready at once, no parking needed. */
static void waiter_ready_already(void *arg) {
    (void)arg;
    int64_t start = march_now_ms();
    int r = march_sched_wait_fd(g_sv[0], 0, march_now_ms() + 5000);
    atomic_store(&g_result, r);
    atomic_store(&g_waited, march_now_ms() - start);
}

/* 5. shutdown(2) on the fd another green thread is parked on wakes it:
 * what tcp_shutdown relies on to end a survivor's readers (a close() would
 * silently drop the poller registration and never wake anyone). */
static void late_shutdown(void *arg) {
    (void)arg;
    nap(60);
    (void)shutdown(g_sv[0], SHUT_RDWR);
}

/* 6. march_sched_wait_fds: two fds, the SECOND becomes readable. */
static int g_sv2[2];
static _Atomic int g_which = -99;
static void waiter_any(void *arg) {
    (void)arg;
    int fds[2] = { g_sv[0], g_sv2[0] };
    atomic_store(&g_which, march_sched_wait_fds(fds, 2, march_now_ms() + 5000));
}
static void late_writer_second(void *arg) {
    (void)arg;
    nap(60);
    char c = 'z';
    (void)write(g_sv2[1], &c, 1);
}

/* 7. march_sched_getaddrinfo parks: with the helper delayed 150 ms (test
 * hook), a sibling green thread that naps 30 ms finishes FIRST -- on one
 * scheduler thread that is only possible if the resolver parked. */
static _Atomic int64_t g_resolve_done_at = 0, g_sibling_done_at = 0;
static _Atomic int     g_resolve_rc = -99;
static void resolver(void *arg) {
    (void)arg;
    struct addrinfo hints, *res = NULL;
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_INET; hints.ai_socktype = SOCK_STREAM; hints.ai_flags = AI_NUMERICHOST;
    int rc = march_sched_getaddrinfo("127.0.0.1", "80", &hints, &res);
    atomic_store(&g_resolve_rc, rc == 0 && res ? 0 : (rc ? rc : -1));
    if (res) freeaddrinfo(res);
    atomic_store(&g_resolve_done_at, march_now_ms());
}
static void sibling(void *arg) {
    (void)arg;
    nap(30);
    atomic_store(&g_sibling_done_at, march_now_ms());
}

/* 4. Two waiters on one fd are both woken by one write. */
static void second_waiter(void *arg) {
    (void)arg;
    int r = march_sched_wait_fd(g_sv[0], 0, march_now_ms() + 5000);
    atomic_store(&g_second, r);
}

static void drain(int fd) {
    char buf[16];
    int fl = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, fl | O_NONBLOCK);
    while (recv(fd, buf, sizeof buf, 0) > 0) {}
    fcntl(fd, F_SETFL, fl);
}

static void fresh_pair(void) {
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, g_sv) == 0);
}

int main(void) {
    alarm(30);

    /* 1 */
    fresh_pair();
    march_sched_init();
    march_sched_spawn(waiter_woken, NULL);
    march_sched_spawn(late_writer, NULL);
    march_sched_request_shutdown();
    march_sched_run();
    assert(atomic_load(&g_result) == MARCH_FDWAIT_READY);
    {
        int64_t w = atomic_load(&g_waited);
        assert(w >= 40 && w < 2000);    /* woke for the write, not the deadline */
    }
    drain(g_sv[0]); close(g_sv[0]); close(g_sv[1]);

    /* 2 */
    fresh_pair();
    march_sched_init();
    march_sched_spawn(waiter_times_out, NULL);
    march_sched_request_shutdown();
    march_sched_run();
    assert(atomic_load(&g_result) == MARCH_FDWAIT_TIMEOUT);
    {
        int64_t w = atomic_load(&g_waited);
        assert(w >= 100 && w < 2000);
    }
    close(g_sv[0]); close(g_sv[1]);

    /* 3 */
    fresh_pair();
    { char c = 'y'; (void)write(g_sv[1], &c, 1); }
    march_sched_init();
    march_sched_spawn(waiter_ready_already, NULL);
    march_sched_request_shutdown();
    march_sched_run();
    assert(atomic_load(&g_result) == MARCH_FDWAIT_READY);
    assert(atomic_load(&g_waited) < 1000);
    drain(g_sv[0]); close(g_sv[0]); close(g_sv[1]);

    /* 4 */
    fresh_pair();
    atomic_store(&g_result, -99);
    atomic_store(&g_second, -99);
    march_sched_init();
    march_sched_spawn(waiter_woken, NULL);
    march_sched_spawn(second_waiter, NULL);
    march_sched_spawn(late_writer, NULL);
    march_sched_request_shutdown();
    march_sched_run();
    assert(atomic_load(&g_result) == MARCH_FDWAIT_READY);
    assert(atomic_load(&g_second) == MARCH_FDWAIT_READY);
    drain(g_sv[0]); close(g_sv[0]); close(g_sv[1]);

    /* 5 */
    fresh_pair();
    atomic_store(&g_result, -99);
    march_sched_init();
    march_sched_spawn(waiter_woken, NULL);
    march_sched_spawn(late_shutdown, NULL);
    march_sched_request_shutdown();
    march_sched_run();
    assert(atomic_load(&g_result) == MARCH_FDWAIT_READY);
    {
        int64_t w = atomic_load(&g_waited);
        assert(w >= 40 && w < 2000);    /* woke for the shutdown, not the deadline */
    }
    close(g_sv[0]); close(g_sv[1]);

    /* 6 */
    fresh_pair();
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, g_sv2) == 0);
    march_sched_init();
    march_sched_spawn(waiter_any, NULL);
    march_sched_spawn(late_writer_second, NULL);
    march_sched_request_shutdown();
    march_sched_run();
    assert(atomic_load(&g_which) == 2);    /* index 1, reported as index + 1 */
    drain(g_sv2[0]); close(g_sv[0]); close(g_sv[1]); close(g_sv2[0]); close(g_sv2[1]);

    /* 7 */
    setenv("MARCH_TEST_RESOLVE_DELAY_MS", "150", 1);
    march_sched_init();
    march_sched_spawn(resolver, NULL);
    march_sched_spawn(sibling, NULL);
    march_sched_request_shutdown();
    march_sched_run();
    unsetenv("MARCH_TEST_RESOLVE_DELAY_MS");
    assert(atomic_load(&g_resolve_rc) == 0);
    assert(atomic_load(&g_sibling_done_at) > 0);
    assert(atomic_load(&g_sibling_done_at) < atomic_load(&g_resolve_done_at));   /* the resolver parked */

    printf("test_scheduler_fdwait: all passed\n");
    return 0;
}
