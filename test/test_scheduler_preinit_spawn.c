/* test_scheduler_preinit_spawn.c — a spawn BEFORE march_sched_init() gets a
 * correctly shaped stack reservation.
 *
 * march_hcr_drain arms its hard-deadline timer as a green proc
 * (march_sched_spawn_daemon_unpinned) from whatever thread runs the reload
 * server, and test_reload_activate4's harness never initialises the
 * scheduler.  The page size the stack helpers use was cached only by
 * march_sched_init(), so that spawn saw page 0: stack_alloc_lazy reserved
 * MARCH_STACK_MAX bytes with no guard page and mprotect'ed the page just
 * PAST the reservation read/write.  On Linux arm64 that page was the text
 * page of the hot patch the server had just dlopen'd (mmap is top-down), so
 * the next call into the patch (__march_init at the batch commit) died with
 * SIGSEGV on instruction fetch.
 *
 * Whether the overrun hits a live mapping depends on address-space layout;
 * the geometry it comes from does not, so that is what this asserts: the
 * reservation is MARCH_STACK_MAX plus one guard page, and the initial
 * window lies inside it.  Never runs the scheduler: nothing here executes on
 * the spawned stack. */

#include "march_scheduler.h"
#include <stdint.h>
#include <stdio.h>
#include <sys/mman.h>
#include <unistd.h>

static void nop(void *arg) { (void)arg; }

static int g_failed = 0;
#define CHECK(c, msg) do { \
    if (c) printf("  ok   %s\n", msg); \
    else { printf("  FAIL %s\n", msg); g_failed++; } } while (0)

int main(void) {
    /* Deliberately NO march_sched_init() before the spawns. */
    size_t page = (size_t)sysconf(_SC_PAGE_SIZE);
    march_proc *p = march_sched_spawn_daemon_unpinned(nop, NULL);
    CHECK(p != NULL, "a daemon spawn before march_sched_init succeeds");
    if (!p) return 1;

    char *base = (char *)p->stack_mmap_base;
    char *lo   = (char *)p->stack_base;
    CHECK(p->stack_alloc == (size_t)MARCH_STACK_MAX + page,
          "the reservation is MARCH_STACK_MAX plus one guard page");
    CHECK(lo == base + MARCH_STACK_MAX,
          "the initial window starts one guard page below the reservation top");
    CHECK(lo + MARCH_STACK_INITIAL <= base + p->stack_alloc,
          "the initial window lies inside the reservation");
    /* The window really is the reservation's own top page: an msync of the
     * whole reservation succeeds only if every byte of it is mapped. */
    CHECK(msync(base, p->stack_alloc, MS_ASYNC) == 0,
          "the whole reservation is mapped");

    /* A second pre-init spawn, and one after init, agree with the first. */
    march_proc *q = march_sched_spawn_daemon_unpinned(nop, NULL);
    CHECK(q && q->stack_alloc == p->stack_alloc, "a second pre-init spawn has the same shape");
    march_sched_init();
    march_proc *r = march_sched_spawn_daemon(nop, NULL);
    CHECK(r && r->stack_alloc == p->stack_alloc, "a post-init spawn has the same shape");

    if (g_failed) {
        fprintf(stderr, "test_scheduler_preinit_spawn: %d check(s) failed\n", g_failed);
        return 1;
    }
    printf("test_scheduler_preinit_spawn: all checks passed\n");
    return 0;
}
