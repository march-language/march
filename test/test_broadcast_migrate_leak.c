/* test_broadcast_migrate_leak.c — end-to-end regression test for the
 * march_actor_broadcast_migrate dead-target message leak
 * (specs/progress/2026-08-12-broadcast-migrate-dead-target-message-leak.md,
 * closed out per specs/todos/2026-08-18-broadcast-migrate-no-end-to-end-guard.md
 * option 2).
 *
 * The bug: Phase 2 of march_actor_broadcast_migrate (runtime/march_runtime.c)
 * malloc's a march_migrate_msg_t per snapshotted actor and march_sched_send's
 * it to that actor's green thread. If the target has already reached
 * PROC_DEAD in the snapshot-to-send window, march_sched_send returns
 * MARCH_SEND_DEAD without taking ownership, so the message must be freed by
 * the caller. The fix does exactly that, in march_actor_inject_migrate_msg.
 *
 * What this test drives: the REAL code, twice over.
 *   1. march_actor_inject_migrate_msg (Phase 2's per-target body, split out
 *      of the loop) against a proc driven to PROC_DEAD deterministically on
 *      this thread via the raw scheduler API — no background scheduler
 *      thread, no timing window.
 *   2. march_actor_broadcast_migrate itself: a fake actor record is given a
 *      dispatch id (so Phase 1's filter matches it) and, through the
 *      march_test_actor_bind_green_thread seam, a green_thread that IS the
 *      dead proc. Phase 1 snapshots it; Phase 2 sends to a dead target.
 * The leak oracle is march_migrate_msgs_live(): every allocation is counted
 * and every disposal path uncounts, so a leaked message is a non-zero
 * reading afterwards. Deleting the free-on-DEAD line from
 * march_actor_inject_migrate_msg turns every check below red (verified at
 * filing time; see the progress entry).
 */
#include "march_runtime.h"
#include "march_scheduler.h"
#include <assert.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>

static int g_pass = 0;
static int g_fail = 0;

#define CHECK(cond, name) \
    do { \
        if (cond) { printf("  PASS  %s\n", name); g_pass++; } \
        else      { printf("  FAIL  %s  (line %d)\n", name, __LINE__); g_fail++; } \
    } while (0)

/* A proc whose entry function returns immediately: the scheduler marks it
 * PROC_DEAD as soon as march_sched_run() dispatches and retires it. */
static void die_immediately(void *arg) { (void)arg; }

static void *fake_actor(void) {
    void *a = march_alloc(48);
    ((int64_t *)a)[3] = 1;          /* $alive */
    return a;
}

int main(void) {
    printf("=== march_actor_broadcast_migrate dead-target leak (end to end) ===\n\n");

    /* Deterministically, single-threadedly, drive `victim` to PROC_DEAD.
     * march_sched_run() runs to completion on THIS thread and returns only
     * once every proc is retired, so there is no window to race here. */
    march_sched_init();
    march_proc *victim = march_sched_spawn_daemon(die_immediately, NULL);
    march_sched_request_shutdown();
    march_sched_run();
    CHECK(atomic_load(&victim->status) == PROC_DEAD,
          "victim proc reached PROC_DEAD deterministically");

    CHECK(march_migrate_msgs_live() == 0, "no migrate messages live at start");

    /* 1. The real per-target body, on the DEAD path. */
    int st = march_actor_inject_migrate_msg(victim, NULL);
    CHECK(st == MARCH_SEND_DEAD,
          "inject to an already-PROC_DEAD target reports MARCH_SEND_DEAD");
    CHECK(march_migrate_msgs_live() == 0,
          "inject frees the migrate message on the DEAD path");

    for (int i = 0; i < 256; i++) march_actor_inject_migrate_msg(victim, NULL);
    CHECK(march_migrate_msgs_live() == 0,
          "256 injects against a dead target: no leak");

    /* 2. The real broadcast: Phase 1 must snapshot our fake actor (dispatch
     * id matches, actor and green_thread non-NULL), Phase 2 must hit DEAD
     * and free. Two actors under the same dispatch id, to exercise the loop
     * rather than a single iteration. */
    const uint32_t DISPATCH_ID = 7;
    void *a1 = fake_actor();
    void *a2 = fake_actor();
    march_actor_set_dispatch_id(a1, DISPATCH_ID);
    march_actor_set_dispatch_id(a2, DISPATCH_ID);
    march_test_actor_bind_green_thread(a1, victim);
    march_test_actor_bind_green_thread(a2, victim);

    march_actor_broadcast_migrate(DISPATCH_ID, NULL);
    CHECK(march_migrate_msgs_live() == 0,
          "broadcast_migrate over two dead-target actors leaks nothing");

    for (int i = 0; i < 64; i++) march_actor_broadcast_migrate(DISPATCH_ID, NULL);
    CHECK(march_migrate_msgs_live() == 0,
          "64 broadcasts over dead targets: no leak");

    /* A non-matching dispatch id must send nothing at all (and so allocate
     * nothing) — guards the counter against a Phase 1 filter regression
     * showing up as a false green. */
    march_actor_broadcast_migrate(DISPATCH_ID + 1, NULL);
    CHECK(march_migrate_msgs_live() == 0,
          "broadcast under an unmatched dispatch id allocates nothing");

    printf("\n=== Results: %d passed, %d failed ===\n", g_pass, g_fail);
    return g_fail ? 1 : 0;
}
