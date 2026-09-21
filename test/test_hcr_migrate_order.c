/* test_hcr_migrate_order.c — hot-reload actor migration: ordering, coverage,
 * drain deadline, and code-version pin lifetime
 * (specs/progress/2026-09-21-hcr-migrate-order-and-snapshot-cap.md).
 *
 * Drives REAL actor green threads through the real receive loop
 * (actor_green_thread) and the real activation entry point
 * (march_actor_publish_migrating, which runtime/march_reload.c calls), with C
 * stand-ins for the compiled <Actor>_dispatch v1/v2 and __migrate_<Actor>.
 *
 * State record layouts (the tag word tells them apart):
 *   v1: [rc][tag=1][count]
 *   v2: [rc][tag=2][sentinel][count]
 * Each dispatch checks the tag before touching a field and counts a layout
 * mismatch instead of reading out of bounds, which is what compiled code
 * would do.
 *
 * Before the fix, the activation published v2 and THEN appended a migrate
 * message to each mailbox: every message already queued ran v2 against the
 * v1 state (6 of 6 in case 1), and march_actor_broadcast_migrate's fixed
 * 2048-entry snapshot left 52 of case 2's 2100 actors unmigrated for good. */
#include "march_runtime.h"
#include "march_scheduler.h"
#include "march_dispatch.h"
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static int g_pass = 0, g_fail = 0;
#define CHECK(cond, name) \
    do { if (cond) { printf("  PASS  %s\n", name); g_pass++; } \
         else { printf("  FAIL  %s  (line %d)\n", name, __LINE__); g_fail++; } } while (0)

#define MSG_INC  ((void *)(intptr_t)3)
#define MSG_GATE ((void *)(intptr_t)5)

static _Atomic int g_gate_open;
static _Atomic long g_v1_handled, g_v2_handled, g_v1_mismatch, g_v2_mismatch;
static _Atomic long g_migrations;

static long now_ms(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static int64_t *state_of(void *actor) { return (int64_t *)(uintptr_t)((int64_t *)actor)[4]; }

static void v1_dispatch(void *actor, void *msg) {
    if (msg == MSG_GATE) {
        while (!atomic_load(&g_gate_open)) march_sched_yield();
        atomic_fetch_add(&g_v1_handled, 1);
        return;
    }
    int64_t *s = state_of(actor);
    if (s[1] != 1) { atomic_fetch_add(&g_v1_mismatch, 1); return; }
    s[2] += 1;
    atomic_fetch_add(&g_v1_handled, 1);
}

static void v2_dispatch(void *actor, void *msg) {
    if (msg == MSG_GATE) {
        while (!atomic_load(&g_gate_open)) march_sched_yield();
        return;
    }
    int64_t *s = state_of(actor);
    if (s[1] != 2) { atomic_fetch_add(&g_v2_mismatch, 1); return; }
    s[3] += 1;
    atomic_fetch_add(&g_v2_handled, 1);
}

static void v3_dispatch(void *actor, void *msg) { (void)actor; (void)msg; }

static void *migrate_v1_v2(void *old) {
    int64_t *o = (int64_t *)old;
    int64_t *n = (int64_t *)march_alloc(32);
    n[1] = 2; n[2] = 0xBEEF; n[3] = (o[1] == 1) ? o[2] : -1000;
    atomic_fetch_add(&g_migrations, 1);
    return n;
}

/* v2 -> v2 (a second deploy that keeps the layout): count it, keep state. */
static void *migrate_v2_v2(void *old) {
    atomic_fetch_add(&g_migrations, 1);
    return old;
}

static void *new_actor(uint32_t slot) {
    int64_t *a = (int64_t *)march_alloc(48);
    a[3] = 1;                                   /* $alive */
    int64_t *s = (int64_t *)march_alloc(24);
    s[1] = 1; s[2] = 0;
    a[4] = (int64_t)(uintptr_t)s;
    march_actor_set_dispatch_id(a, slot);
    march_spawn(a);
    return a;
}

static void send(void *actor, void *msg) { march_decrc(march_send(actor, msg)); }

static void wait_until(_Atomic long *ctr, long want, long timeout_ms) {
    long end = now_ms() + timeout_ms;
    while (atomic_load(ctr) < want && now_ms() < end) march_sched_yield();
}

static void wait_refs_zero(uint32_t slot, uint32_t version, long timeout_ms) {
    long end = now_ms() + timeout_ms;
    while (march_dispatch_refs(slot, version) != 0 && now_ms() < end)
        march_sched_yield();
}

static void sleep_ms(long ms) {
    long end = now_ms() + ms;
    while (now_ms() < end) march_sched_yield();
}

enum { SLOT_ORDER = 1, SLOT_MANY, SLOT_DRAIN, SLOT_BUSY, SLOT_DEATH, N_SLOTS };
#define N_MANY 2100   /* > the old 2048-entry snapshot cap */

static void reset(void) {
    atomic_store(&g_gate_open, 0);
    atomic_store(&g_v1_handled, 0); atomic_store(&g_v2_handled, 0);
    atomic_store(&g_v1_mismatch, 0); atomic_store(&g_v2_mismatch, 0);
    atomic_store(&g_migrations, 0);
}

/* The activation runtime/march_reload.c performs for a migrating deploy. */
static int activate(uint32_t slot, void *fn, int64_t drain_ms) {
    return march_actor_publish_migrating(slot, fn, "v2", NULL, MARCH_NATIVE, 0,
                                         migrate_v1_v2, drain_ms);
}

static void test_queued_messages_run_on_old_code(void) {
    printf("-- messages queued before a migrating activation --\n");
    reset();
    uint32_t old_v = march_dispatch_current(SLOT_ORDER);
    void *a = new_actor(SLOT_ORDER);
    send(a, MSG_GATE);                       /* holds the actor inside v1 */
    for (int i = 0; i < 5; i++) send(a, MSG_INC);   /* queued pre-switch */
    CHECK(activate(SLOT_ORDER, (void *)v2_dispatch, 0) >= 0, "activation published");
    for (int i = 0; i < 5; i++) send(a, MSG_INC);   /* queued post-switch */
    atomic_store(&g_gate_open, 1);
    wait_until(&g_v2_handled, 5, 5000);
    wait_refs_zero(SLOT_ORDER, old_v, 2000);
    int64_t *s = state_of(a);
    printf("     v1 handled=%ld v2 handled=%ld v1 mismatch=%ld v2 mismatch=%ld migrations=%ld\n",
           atomic_load(&g_v1_handled), atomic_load(&g_v2_handled),
           atomic_load(&g_v1_mismatch), atomic_load(&g_v2_mismatch),
           atomic_load(&g_migrations));
    CHECK(atomic_load(&g_v2_mismatch) == 0, "new code never sees an old-layout state");
    CHECK(atomic_load(&g_v1_handled) == 6, "gate + 5 pre-switch messages ran on v1");
    CHECK(atomic_load(&g_v2_handled) == 5, "5 post-switch messages ran on v2");
    CHECK(atomic_load(&g_migrations) == 1, "state migrated exactly once");
    CHECK(s[1] == 2 && s[3] == 10, "final v2 state counts all 10 increments");
    CHECK(march_dispatch_refs(SLOT_ORDER, old_v) == 0,
          "old version unpinned once the actor passed its marker");
}

static void test_every_actor_is_migrated(void) {
    printf("-- %d live actors (> old snapshot cap) --\n", N_MANY);
    reset();
    atomic_store(&g_gate_open, 1);
    static void *actors[N_MANY];
    for (int i = 0; i < N_MANY; i++) actors[i] = new_actor(SLOT_MANY);
    uint32_t old_v = march_dispatch_current(SLOT_MANY);
    CHECK(activate(SLOT_MANY, (void *)v2_dispatch, 0) >= 0, "activation published");
    wait_until(&g_migrations, N_MANY, 10000);
    for (int i = 0; i < N_MANY; i++) send(actors[i], MSG_INC);
    wait_until(&g_v2_handled, N_MANY, 10000);
    wait_refs_zero(SLOT_MANY, old_v, 2000);
    long unmigrated = 0;
    for (int i = 0; i < N_MANY; i++) if (state_of(actors[i])[1] != 2) unmigrated++;
    printf("     migrations=%ld unmigrated=%ld v2 mismatch=%ld\n",
           atomic_load(&g_migrations), unmigrated, atomic_load(&g_v2_mismatch));
    CHECK(atomic_load(&g_migrations) == N_MANY, "every live actor received its migration");
    CHECK(unmigrated == 0, "no actor is left on the old state layout");
    CHECK(atomic_load(&g_v2_mismatch) == 0, "new code never sees an old-layout state");
    CHECK(march_dispatch_refs(SLOT_MANY, old_v) == 0,
          "old version unpinned once every actor passed its marker");
}

static void test_drain_deadline_drops_old_messages(void) {
    printf("-- drain deadline --\n");
    reset();
    int64_t dropped0 = march_hcr_drain_dropped();
    void *a = new_actor(SLOT_DRAIN);
    send(a, MSG_GATE);
    for (int i = 0; i < 5; i++) send(a, MSG_INC);   /* will miss the deadline */
    CHECK(activate(SLOT_DRAIN, (void *)v2_dispatch, 50) >= 0, "activation published");
    for (int i = 0; i < 5; i++) send(a, MSG_INC);
    sleep_ms(200);                                  /* past the 50 ms deadline */
    atomic_store(&g_gate_open, 1);
    wait_until(&g_v2_handled, 5, 5000);
    int64_t *s = state_of(a);
    printf("     dropped=%lld v1 handled=%ld v2 handled=%ld\n",
           (long long)(march_hcr_drain_dropped() - dropped0),
           atomic_load(&g_v1_handled), atomic_load(&g_v2_handled));
    CHECK(march_hcr_drain_dropped() - dropped0 == 5,
          "the 5 pre-marker messages past the deadline were dropped and counted");
    CHECK(atomic_load(&g_v1_handled) == 1, "only the in-flight gate message ran on v1");
    CHECK(atomic_load(&g_v2_handled) == 5 && atomic_load(&g_v2_mismatch) == 0,
          "post-marker messages ran on v2 against migrated state");
    CHECK(atomic_load(&g_migrations) == 1 && s[1] == 2 && s[3] == 5,
          "state migrated once; count = the 5 post-switch increments");

    /* A second migration of the same actor, with no deadline, long after the
     * first one's deadline passed: the first deadline must not carry over. */
    atomic_store(&g_gate_open, 0);
    atomic_store(&g_v2_handled, 0);
    atomic_store(&g_migrations, 0);
    int64_t dropped1 = march_hcr_drain_dropped();
    send(a, MSG_GATE);
    for (int i = 0; i < 3; i++) send(a, MSG_INC);
    CHECK(march_actor_publish_migrating(SLOT_DRAIN, (void *)v2_dispatch, "v2b",
                                        NULL, MARCH_NATIVE, 0, migrate_v2_v2, 0) >= 0,
          "second activation published");
    atomic_store(&g_gate_open, 1);
    wait_until(&g_migrations, 1, 5000);
    wait_until(&g_v2_handled, 3, 5000);
    CHECK(march_hcr_drain_dropped() == dropped1,
          "a later migration does not inherit an expired drain deadline");
    CHECK(atomic_load(&g_v2_handled) == 3 && s[3] == 8,
          "its queued messages all ran on the old code");
}

static void test_second_deploy_waits_for_markers(void) {
    printf("-- second migrating deploy while the first is draining --\n");
    reset();
    uint32_t old_v = march_dispatch_current(SLOT_BUSY);
    void *a = new_actor(SLOT_BUSY);
    send(a, MSG_GATE);
    int idx = activate(SLOT_BUSY, (void *)v2_dispatch, 0);
    CHECK(idx >= 0, "first activation published");
    CHECK(activate(SLOT_BUSY, (void *)v3_dispatch, 0) < 0,
          "second migrating activation refused while an actor is still pinned");
    CHECK(march_dispatch_current(SLOT_BUSY) == (uint32_t)idx,
          "refused activation left the first one current");
    atomic_store(&g_gate_open, 1);
    wait_until(&g_migrations, 1, 5000);
    wait_refs_zero(SLOT_BUSY, old_v, 2000);
    CHECK(march_dispatch_refs(SLOT_BUSY, old_v) == 0, "refusal leaked no pin");
    /* After the marker, the old ring slot is reclaimable again. v2_dispatch
     * republished so the actor stays layout-consistent (migrate_v1_v2 on a
     * v2 state yields a -1000 count, not a crash). */
    CHECK(march_dispatch_publish(SLOT_BUSY, (void *)v2_dispatch, "v2b", NULL,
                                 MARCH_NATIVE) >= 0,
          "a publish succeeds once every actor passed its marker");
}

static void test_dead_actor_releases_pin(void) {
    printf("-- actor killed before reaching its marker --\n");
    reset();
    uint32_t old_v = march_dispatch_current(SLOT_DEATH);
    void *a = new_actor(SLOT_DEATH);
    send(a, MSG_GATE);
    for (int i = 0; i < 3; i++) send(a, MSG_INC);
    CHECK(activate(SLOT_DEATH, (void *)v2_dispatch, 0) >= 0, "activation published");
    CHECK(march_dispatch_refs(SLOT_DEATH, old_v) >= 1, "actor pinned to the old version");
    march_kill(a);
    atomic_store(&g_gate_open, 1);
    wait_refs_zero(SLOT_DEATH, old_v, 5000);
    CHECK(march_dispatch_refs(SLOT_DEATH, old_v) == 0,
          "a dead actor gives its pinned version back");
    CHECK(atomic_load(&g_v2_mismatch) == 0, "new code never sees an old-layout state");
}

static void test_main(void) {
    test_queued_messages_run_on_old_code();
    test_every_actor_is_migrated();
    test_drain_deadline_drops_old_messages();
    test_second_deploy_waits_for_markers();
    test_dead_actor_releases_pin();
    /* Every marker disposed by some path: nothing leaked. */
    long end = now_ms() + 2000;
    while (march_migrate_msgs_live() != 0 && now_ms() < end) march_sched_yield();
    CHECK(march_migrate_msgs_live() == 0, "no migrate marker leaked");
}

int main(void) {
    printf("=== HCR actor migration: ordering, coverage, drain, pin lifetime ===\n\n");
    static const char *names[N_SLOTS] = {
        NULL, "Ord_dispatch", "Many_dispatch", "Drain_dispatch",
        "Busy_dispatch", "Death_dispatch" };
    march_dispatch_init(N_SLOTS);
    for (uint32_t i = 1; i < N_SLOTS; i++) {
        march_dispatch_register_name(i, names[i]);
        march_dispatch_publish(i, (void *)v1_dispatch, "v1", NULL, MARCH_NATIVE);
    }
    march_spawn_main(test_main);
    march_run_scheduler();
    printf("\n=== Results: %d passed, %d failed ===\n", g_pass, g_fail);
    return g_fail ? 1 : 0;
}
