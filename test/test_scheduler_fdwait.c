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

    printf("test_scheduler_fdwait: all passed\n");
    return 0;
}
