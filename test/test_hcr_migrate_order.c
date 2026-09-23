/* test_hcr_migrate_order.c -- hot-reload actor migration under the unified
 * epoch model (specs/plans/2026-09-21-distributed-authority-and-deploys-plan.md,
 * II.4; first slice specs/progress/2026-09-21-hcr-migrate-order-and-snapshot-cap.md).
 *
 * Drives REAL actor green threads through the real receive loop
 * (actor_green_thread) and the real activation (march_hcr_activate, which
 * runtime/march_reload.c calls), with C stand-ins for the compiled
 * <Actor>_dispatch v1/v2/v3, __migrate_<Actor> and __migrate_msg_<Actor>.
 *
 * State record layouts (the tag word tells them apart):
 *   v1: [rc][tag=1][count]
 *   v2: [rc][tag=2][sentinel][count]
 * Each dispatch checks the tag before touching a field and counts a layout
 * mismatch instead of reading out of bounds, which is what compiled code
 * would do.  Message formats: v1 reads MSG_INC; a "message-type change" deploy
 * (msgs_changed) makes v2 read MSG_INC2 instead, and v2 counts an MSG_INC as a
 * format mismatch.
 *
 * Cases: queued messages run on the pinned (old) version; 2100 actors all
 * advance; the soft drain deadline forces the marker (compatible messages run
 * on the new code, old-format ones are dropped and counted); a second deploy
 * while the first drains is accepted and the actor applies both migrations
 * in order; a held proc defers its marker and newer-format messages; a
 * sender that already advanced keeps FIFO through the early advance (D30);
 * migrate_msg converts old-format messages sent after the advance; a
 * DROP_NEW actor with a full mailbox at deploy time still runs its
 * pre-deploy messages on the old version (the #564 gap); the hard deadline
 * kills an actor pinned to the drained epoch; the counters report all of it;
 * a killed actor gives its pins back; no marker leaks. */
#include "march_runtime.h"
#include "march_scheduler.h"
#include "march_dispatch.h"
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* march_runtime.c; no header declaration. */
void march_actor_set_mbox_limit(void *actor, int64_t limit, int64_t policy);

static int g_pass = 0, g_fail = 0;
#define CHECK(cond, name) \
    do { if (cond) { printf("  PASS  %s\n", name); g_pass++; } \
         else { printf("  FAIL  %s  (line %d)\n", name, __LINE__); g_fail++; } } while (0)

#define MSG_INC     ((void *)(intptr_t)3)
#define MSG_GATE    ((void *)(intptr_t)5)
#define MSG_INC2    ((void *)(intptr_t)7)    /* the v2 message format */
#define MSG_HOLD    ((void *)(intptr_t)9)    /* handler takes an epoch hold */
#define MSG_RELEASE ((void *)(intptr_t)11)   /* handler releases it */

static _Atomic int g_gate_open;
static _Atomic long g_v1_handled, g_v2_handled, g_v1_mismatch, g_v2_mismatch;
static _Atomic long g_migrations, g_v2_fmt_mismatch;
static _Atomic int  g_v2_new_format;   /* 1: v2 reads MSG_INC2, not MSG_INC */

static long now_ms(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static int64_t *state_of(void *actor) { return (int64_t *)(uintptr_t)((int64_t *)actor)[4]; }

static int control_msg(void *msg) {
    if (msg == MSG_GATE) {
        while (!atomic_load(&g_gate_open)) march_sched_yield();
        return 1;
    }
    if (msg == MSG_HOLD)    { march_epoch_hold();    return 1; }
    if (msg == MSG_RELEASE) { march_epoch_release(); return 1; }
    return 0;
}

static void v1_dispatch(void *actor, void *msg) {
    if (control_msg(msg)) { atomic_fetch_add(&g_v1_handled, 1); return; }
    int64_t *s = state_of(actor);
    if (s[1] != 1 || msg != MSG_INC) { atomic_fetch_add(&g_v1_mismatch, 1); return; }
    s[2] += 1;
    atomic_fetch_add(&g_v1_handled, 1);
}

static void v2_dispatch(void *actor, void *msg) {
    if (control_msg(msg)) return;
    int64_t *s = state_of(actor);
    if (s[1] != 2) { atomic_fetch_add(&g_v2_mismatch, 1); return; }
    void *want = atomic_load(&g_v2_new_format) ? MSG_INC2 : MSG_INC;
    if (msg != want) { atomic_fetch_add(&g_v2_fmt_mismatch, 1); return; }
    s[3] += 1;
    atomic_fetch_add(&g_v2_handled, 1);
}

static void *migrate_v1_v2(void *old) {
    int64_t *o = (int64_t *)old;
    int64_t *n = (int64_t *)march_alloc(32);
    n[1] = 2; n[2] = 0xBEEF; n[3] = (o[1] == 1) ? o[2] : -1000;
    atomic_fetch_add(&g_migrations, 1);
    return n;
}

/* v2 -> v2 (a later deploy that keeps the layout): count it, keep state. */
static void *migrate_v2_v2(void *old) {
    atomic_fetch_add(&g_migrations, 1);
    return old;
}

/* __migrate_msg: MSG_INC (old format) -> MSG_INC2; anything else -> None. */
static void *migrate_msg_inc(void *msg, void *none) {
    return msg == MSG_INC ? MSG_INC2 : none;
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

static void sleep_ms(long ms) {
    long end = now_ms() + ms;
    while (now_ms() < end) march_sched_yield();
}

static void wait_pins_zero(uint32_t epoch, long timeout_ms) {
    long end = now_ms() + timeout_ms;
    while (march_epoch_pins(epoch) != 0 && now_ms() < end) march_sched_yield();
}

enum { SLOT_ORDER = 1, SLOT_MANY, SLOT_DRAIN, SLOT_DRAIN_FMT, SLOT_BUSY,
       SLOT_HOLD, SLOT_EARLY, SLOT_CONVERT, SLOT_FULL, SLOT_HARD, SLOT_DEATH,
       N_SLOTS };
#define N_MANY 2100   /* > the old 2048-entry snapshot cap */

static void reset(void) {
    atomic_store(&g_gate_open, 0);
    atomic_store(&g_v1_handled, 0); atomic_store(&g_v2_handled, 0);
    atomic_store(&g_v1_mismatch, 0); atomic_store(&g_v2_mismatch, 0);
    atomic_store(&g_migrations, 0); atomic_store(&g_v2_fmt_mismatch, 0);
    atomic_store(&g_v2_new_format, 0);
}

/* The activation runtime/march_reload.c performs, for one function. */
static int activate_ex(uint32_t slot, void *fn, void *(*mig)(void *),
                       int msgs_changed, void *(*mig_msg)(void *, void *),
                       int64_t soft_ms, int64_t hard_ms) {
    march_hcr_unit u = {
        .slot = slot, .fn = fn, .impl_hash = "v2", .sig_hash = NULL,
        .kind = MARCH_NATIVE, .migrate_fn = mig, .migrate_msg_fn = mig_msg,
        .state_changed = mig != NULL, .msgs_changed = msgs_changed,
        .handle = NULL, .ring_idx = -1 };
    return march_hcr_activate(&u, 1, 0, soft_ms, hard_ms, NULL);
}

static int activate(uint32_t slot, void *fn, int64_t soft_ms) {
    return activate_ex(slot, fn, migrate_v1_v2, 0, NULL, soft_ms, 0);
}

static void test_queued_messages_run_on_old_code(void) {
    printf("-- messages queued before a migrating activation --\n");
    reset();
    void *a = new_actor(SLOT_ORDER);
    send(a, MSG_GATE);                       /* holds the actor inside v1 */
    for (int i = 0; i < 5; i++) send(a, MSG_INC);   /* queued pre-switch */
    uint32_t old_e = march_epoch_current();
    int e = activate(SLOT_ORDER, (void *)v2_dispatch, 0);
    CHECK(e > (int)old_e, "activation advanced the epoch");
    for (int i = 0; i < 5; i++) send(a, MSG_INC);   /* queued post-switch */
    atomic_store(&g_gate_open, 1);
    wait_until(&g_v2_handled, 5, 5000);
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
}

static void test_every_actor_is_migrated(void) {
    printf("-- %d live actors (> old snapshot cap) --\n", N_MANY);
    reset();
    atomic_store(&g_gate_open, 1);
    static void *actors[N_MANY];
    for (int i = 0; i < N_MANY; i++) actors[i] = new_actor(SLOT_MANY);
    uint32_t old_e = march_epoch_current();
    CHECK(activate(SLOT_MANY, (void *)v2_dispatch, 0) > 0, "activation published");
    wait_until(&g_migrations, N_MANY, 10000);
    for (int i = 0; i < N_MANY; i++) send(actors[i], MSG_INC);
    wait_until(&g_v2_handled, N_MANY, 10000);
    long unmigrated = 0;
    for (int i = 0; i < N_MANY; i++) if (state_of(actors[i])[1] != 2) unmigrated++;
    printf("     migrations=%ld unmigrated=%ld v2 mismatch=%ld\n",
           atomic_load(&g_migrations), unmigrated, atomic_load(&g_v2_mismatch));
    CHECK(atomic_load(&g_migrations) == N_MANY, "every live actor received its migration");
    CHECK(unmigrated == 0, "no actor is left on the old state layout");
    CHECK(atomic_load(&g_v2_mismatch) == 0, "new code never sees an old-layout state");
    wait_pins_zero(old_e, 2000);
    CHECK(march_epoch_pins(old_e) == 0, "the old epoch retired once every actor advanced");
}

static void test_soft_deadline_forces_marker(void) {
    printf("-- soft drain deadline (compatible messages) --\n");
    reset();
    int64_t dropped0 = march_hcr_drain_dropped();
    march_hcr_counters c0; march_hcr_counters_get(&c0);
    void *a = new_actor(SLOT_DRAIN);
    send(a, MSG_GATE);
    for (int i = 0; i < 5; i++) send(a, MSG_INC);   /* will miss the deadline */
    CHECK(activate(SLOT_DRAIN, (void *)v2_dispatch, 50) > 0, "activation published");
    for (int i = 0; i < 5; i++) send(a, MSG_INC);
    sleep_ms(200);                                  /* past the 50 ms deadline */
    atomic_store(&g_gate_open, 1);
    wait_until(&g_v2_handled, 10, 5000);
    march_hcr_counters c1; march_hcr_counters_get(&c1);
    int64_t *s = state_of(a);
    printf("     dropped=%lld v1 handled=%ld v2 handled=%ld forced=%lld\n",
           (long long)(march_hcr_drain_dropped() - dropped0),
           atomic_load(&g_v1_handled), atomic_load(&g_v2_handled),
           (long long)(c1.forced - c0.forced));
    CHECK(c1.forced - c0.forced == 1, "the soft deadline forced the marker");
    CHECK(atomic_load(&g_v1_handled) == 1, "only the in-flight gate message ran on v1");
    CHECK(march_hcr_drain_dropped() == dropped0,
          "same-format messages are not dropped: they run on the new code");
    CHECK(atomic_load(&g_v2_handled) == 10 && atomic_load(&g_v2_mismatch) == 0,
          "all 10 increments ran on v2 against the migrated state");
    CHECK(atomic_load(&g_migrations) == 1 && s[1] == 2 && s[3] == 10,
          "state migrated once, before the first v2 message");
}

static void test_soft_deadline_drops_old_format(void) {
    printf("-- soft drain deadline (message type changed, no migrate_msg) --\n");
    reset();
    int64_t dropped0 = march_hcr_drain_dropped();
    void *a = new_actor(SLOT_DRAIN_FMT);
    send(a, MSG_GATE);
    for (int i = 0; i < 5; i++) send(a, MSG_INC);   /* old format, too late */
    CHECK(activate_ex(SLOT_DRAIN_FMT, (void *)v2_dispatch, migrate_v1_v2, 1,
                      NULL, 50, 0) > 0, "activation published");
    atomic_store(&g_v2_new_format, 1);
    for (int i = 0; i < 3; i++) send(a, MSG_INC2);  /* new format */
    sleep_ms(200);
    atomic_store(&g_gate_open, 1);
    wait_until(&g_v2_handled, 3, 5000);
    sleep_ms(50);
    int64_t *s = state_of(a);
    printf("     dropped=%lld v2 handled=%ld fmt mismatch=%ld\n",
           (long long)(march_hcr_drain_dropped() - dropped0),
           atomic_load(&g_v2_handled), atomic_load(&g_v2_fmt_mismatch));
    CHECK(march_hcr_drain_dropped() - dropped0 == 5,
          "the 5 old-format messages past the deadline were dropped and counted");
    CHECK(atomic_load(&g_v2_fmt_mismatch) == 0, "v2 never saw an old-format message");
    CHECK(atomic_load(&g_v2_handled) == 3 && s[3] == 3, "the 3 new-format messages ran on v2");
}

static void test_second_deploy_while_draining(void) {
    printf("-- a second migrating deploy while the first is draining --\n");
    reset();
    void *a = new_actor(SLOT_BUSY);
    send(a, MSG_GATE);
    for (int i = 0; i < 2; i++) send(a, MSG_INC);        /* before deploy 1 */
    int e1 = activate(SLOT_BUSY, (void *)v2_dispatch, 0);
    for (int i = 0; i < 2; i++) send(a, MSG_INC);        /* between deploys */
    int e2 = activate_ex(SLOT_BUSY, (void *)v2_dispatch, migrate_v2_v2, 0,
                         NULL, 0, 0);
    CHECK(e1 > 0 && e2 > e1,
          "the second deploy is accepted while the actor is still at epoch e1-1 (3 live versions)");
    for (int i = 0; i < 2; i++) send(a, MSG_INC);        /* after deploy 2 */
    atomic_store(&g_gate_open, 1);
    wait_until(&g_v2_handled, 4, 5000);
    wait_until(&g_migrations, 2, 5000);
    int64_t *s = state_of(a);
    printf("     v1 handled=%ld v2 handled=%ld migrations=%ld count=%lld\n",
           atomic_load(&g_v1_handled), atomic_load(&g_v2_handled),
           atomic_load(&g_migrations), (long long)s[3]);
    CHECK(atomic_load(&g_v1_handled) == 3, "gate + the 2 pre-deploy messages ran on v1");
    CHECK(atomic_load(&g_migrations) == 2, "both migrations ran, once each");
    CHECK(atomic_load(&g_v2_handled) == 4 && s[1] == 2 && s[3] == 6,
          "the rest ran on the new code; no increment lost");
    CHECK(atomic_load(&g_v2_mismatch) == 0, "new code never sees an old-layout state");
}

static void test_held_proc_defers_marker(void) {
    printf("-- a held proc defers its marker --\n");
    reset();
    atomic_store(&g_gate_open, 1);
    march_hcr_counters c0; march_hcr_counters_get(&c0);
    void *a = new_actor(SLOT_HOLD);
    send(a, MSG_HOLD);                        /* the actor takes a hold */
    sleep_ms(20);
    uint32_t old_e = march_epoch_current();
    CHECK(activate_ex(SLOT_HOLD, (void *)v2_dispatch, migrate_v1_v2, 1,
                      NULL, 30, 0) > 0, "message-type-changing activation published");
    /* Old-format messages from peers still at the old epoch (a session's
     * other party, say), after the marker. */
    for (int i = 0; i < 3; i++)
        march_decrc(march_hcr_test_send_stamped(a, MSG_INC, old_e));
    sleep_ms(150);                                   /* past the soft deadline */
    CHECK(atomic_load(&g_migrations) == 0,
          "held: no advance at the marker, nor at the soft deadline");
    CHECK(atomic_load(&g_v1_handled) == 4, "held: old messages keep running on v1");
    /* A sender at the new epoch (main is unpinned: it stamps current). */
    atomic_store(&g_v2_new_format, 1);
    send(a, MSG_INC2);
    sleep_ms(50);
    march_hcr_counters c1; march_hcr_counters_get(&c1);
    CHECK(c1.deferred - c0.deferred == 1,
          "a newer-format message to a held actor is deferred, not dispatched");
    CHECK(atomic_load(&g_v1_mismatch) == 0, "v1 never saw the new-format message");
    march_decrc(march_hcr_test_send_stamped(a, MSG_RELEASE, old_e));  /* last hold */
    wait_until(&g_v2_handled, 1, 5000);
    int64_t *s = state_of(a);
    CHECK(atomic_load(&g_migrations) == 1, "advanced once the last hold was released");
    CHECK(atomic_load(&g_v2_handled) == 1 && s[3] == 4,
          "the deferred message replayed on v2, after the migration");
}

/* Deploy for the early-advance case: in the window before the markers go
 * out, a sender already at the new epoch puts new-format messages in the
 * receiver's mailbox, ahead of its marker. */
static void *g_early_target = NULL;
static void early_hook(uint32_t epoch) {
    (void)epoch;
    atomic_store(&g_v2_new_format, 1);
    for (int i = 0; i < 2; i++) send(g_early_target, MSG_INC2);
}

static void test_early_advance_keeps_fifo(void) {
    printf("-- a sender that already advanced (D30 early advance) --\n");
    reset();
    march_hcr_counters c0; march_hcr_counters_get(&c0);
    void *a = new_actor(SLOT_EARLY);
    send(a, MSG_GATE);
    for (int i = 0; i < 3; i++) send(a, MSG_INC);   /* old format, pre-deploy */
    g_early_target = a;
    march_hcr_test_before_mark = early_hook;
    int e = activate_ex(SLOT_EARLY, (void *)v2_dispatch, migrate_v1_v2, 1, NULL, 0, 0);
    march_hcr_test_before_mark = NULL;
    CHECK(e > 0, "message-type-changing activation published");
    for (int i = 0; i < 2; i++) send(a, MSG_INC2);  /* after the marker */
    atomic_store(&g_gate_open, 1);
    wait_until(&g_v2_handled, 4, 5000);
    march_hcr_counters c1; march_hcr_counters_get(&c1);
    int64_t *s = state_of(a);
    printf("     v1 handled=%ld v2 handled=%ld early=%lld fmt mismatch=%ld\n",
           atomic_load(&g_v1_handled), atomic_load(&g_v2_handled),
           (long long)(c1.early - c0.early), atomic_load(&g_v2_fmt_mismatch));
    CHECK(atomic_load(&g_v1_handled) == 4, "gate + 3 old-format messages ran on v1, in order");
    CHECK(atomic_load(&g_v1_mismatch) == 0, "v1 never saw a new-format message");
    CHECK(c1.early - c0.early == 1, "the first new-format message advanced the actor early");
    CHECK(atomic_load(&g_v2_handled) == 4 && s[1] == 2 && s[3] == 7,
          "all 4 new-format messages ran on v2, after the migration; nothing dropped");
    CHECK(atomic_load(&g_migrations) == 1, "migrated once (the marker was a no-op)");
}

static void test_migrate_msg_converts(void) {
    printf("-- migrate_msg converts old-format messages sent after the advance --\n");
    reset();
    atomic_store(&g_gate_open, 1);
    march_hcr_counters c0; march_hcr_counters_get(&c0);
    void *a = new_actor(SLOT_CONVERT);
    uint32_t old_e = march_epoch_current();
    /* An old sender: a proc still pinned to the old epoch.  A second actor
     * held so that it never advances stands in for it. */
    void *sender = new_actor(SLOT_HOLD);
    send(sender, MSG_HOLD);
    sleep_ms(20);
    CHECK(activate_ex(SLOT_CONVERT, (void *)v2_dispatch, migrate_v1_v2, 1,
                      migrate_msg_inc, 0, 0) > 0, "activation with a migrate_msg");
    atomic_store(&g_v2_new_format, 1);
    wait_until(&g_migrations, 1, 5000);
    CHECK(march_epoch_pins(old_e) >= 1, "the held sender keeps the old epoch pinned");
    /* Messages stamped with the old epoch, as the old sender's would be. */
    for (int i = 0; i < 3; i++)
        march_decrc(march_hcr_test_send_stamped(a, MSG_INC, old_e));
    wait_until(&g_v2_handled, 3, 5000);
    march_hcr_counters c1; march_hcr_counters_get(&c1);
    int64_t *s = state_of(a);
    printf("     converted=%lld v2 handled=%ld fmt mismatch=%ld\n",
           (long long)(c1.converted - c0.converted), atomic_load(&g_v2_handled),
           atomic_load(&g_v2_fmt_mismatch));
    CHECK(c1.converted - c0.converted == 3, "3 old-format messages converted");
    CHECK(atomic_load(&g_v2_fmt_mismatch) == 0 && s[3] == 3,
          "they ran on v2 in the new format");
    march_decrc(march_hcr_test_send_stamped(sender, MSG_RELEASE, old_e));
}

static void test_full_drop_new_mailbox(void) {
    printf("-- DROP_NEW actor whose mailbox is full at deploy time --\n");
    reset();
    int64_t dropped0 = march_hcr_drain_dropped();
    void *a = new_actor(SLOT_FULL);
    march_actor_set_mbox_limit(a, 4, MARCH_MBOX_DROP_NEW);
    send(a, MSG_GATE);
    sleep_ms(20);                                   /* gate is being handled */
    for (int i = 0; i < 4; i++) send(a, MSG_INC);   /* fills the mailbox */
    send(a, MSG_INC);                                /* rejected by DROP_NEW */
    CHECK(activate(SLOT_FULL, (void *)v2_dispatch, 0) > 0, "activation published");
    atomic_store(&g_gate_open, 1);
    wait_until(&g_migrations, 1, 5000);
    sleep_ms(20);
    for (int i = 0; i < 2; i++) send(a, MSG_INC);
    wait_until(&g_v2_handled, 2, 5000);
    int64_t *s = state_of(a);
    printf("     v1 handled=%ld v2 handled=%ld migrations=%ld\n",
           atomic_load(&g_v1_handled), atomic_load(&g_v2_handled),
           atomic_load(&g_migrations));
    CHECK(atomic_load(&g_v1_handled) == 5,
          "gate + the 4 queued pre-deploy messages ran on the OLD version");
    CHECK(atomic_load(&g_migrations) == 1, "the marker got through a full mailbox");
    CHECK(atomic_load(&g_v2_handled) == 2 && s[3] == 6 && atomic_load(&g_v2_mismatch) == 0,
          "then migrated; later messages on v2");
    CHECK(march_hcr_drain_dropped() == dropped0, "no pre-deploy message was dropped");
}

static void test_hard_deadline_kills(void) {
    printf("-- the hard drain deadline kills an actor pinned to the old epoch --\n");
    reset();
    atomic_store(&g_gate_open, 1);
    march_hcr_counters c0; march_hcr_counters_get(&c0);
    void *a = new_actor(SLOT_HARD);
    send(a, MSG_HOLD);                         /* held for ever: never advances */
    sleep_ms(20);
    uint32_t old_e = march_epoch_current();
    CHECK(activate_ex(SLOT_HARD, (void *)v2_dispatch, migrate_v1_v2, 0, NULL,
                      20, 80) > 0, "activation with soft 20 ms, hard 80 ms");
    sleep_ms(40);
    CHECK(march_is_alive(a), "after the soft deadline a held actor is left alone");
    CHECK(march_hcr_epoch_draining(old_e), "the old epoch is draining");
    long end = now_ms() + 3000;
    while (march_is_alive(a) && now_ms() < end) march_sched_yield();
    march_hcr_counters c1; march_hcr_counters_get(&c1);
    CHECK(!march_is_alive(a), "the hard deadline killed it");
    CHECK(c1.killed - c0.killed == 1, "and counted the kill");
}

static void test_dead_actor_releases_pins(void) {
    printf("-- actor killed before reaching its marker --\n");
    reset();
    void *a = new_actor(SLOT_DEATH);
    send(a, MSG_GATE);
    for (int i = 0; i < 3; i++) send(a, MSG_INC);
    uint32_t old_e = march_epoch_current();
    int64_t before = march_epoch_pins(old_e);
    int e = activate(SLOT_DEATH, (void *)v2_dispatch, 0);
    CHECK(e > 0, "activation published");
    CHECK(march_epoch_pins(old_e) >= 1, "the actor keeps the old epoch pinned");
    march_kill(a);
    atomic_store(&g_gate_open, 1);
    long end = now_ms() + 5000;
    while (march_epoch_pins(old_e) >= before && now_ms() < end) march_sched_yield();
    CHECK(march_epoch_pins(old_e) < before, "a dead actor gives its epoch pin back");
    CHECK(atomic_load(&g_v2_mismatch) == 0, "new code never sees an old-layout state");
}

static void test_main(void) {
    test_queued_messages_run_on_old_code();
    test_every_actor_is_migrated();
    test_soft_deadline_forces_marker();
    test_soft_deadline_drops_old_format();
    test_second_deploy_while_draining();
    test_held_proc_defers_marker();
    test_early_advance_keeps_fifo();
    test_migrate_msg_converts();
    test_full_drop_new_mailbox();
    test_hard_deadline_kills();
    test_dead_actor_releases_pins();
    march_hcr_counters c; march_hcr_counters_get(&c);
    printf("-- counters: deferred=%lld converted=%lld dropped=%lld killed=%lld "
           "advances=%lld early=%lld forced=%lld lost=%lld --\n",
           (long long)c.deferred, (long long)c.converted, (long long)c.dropped,
           (long long)c.killed, (long long)c.advances, (long long)c.early,
           (long long)c.forced, (long long)c.markers_lost);
    CHECK(c.markers_lost == 0, "the lost-marker fallback was never needed");
    /* Every marker consumed or disposed: nothing leaked. */
    long end = now_ms() + 2000;
    while (march_hcr_markers_live() != 0 && now_ms() < end) march_sched_yield();
    CHECK(march_hcr_markers_live() == 0, "no epoch marker leaked");
    CHECK(march_migrate_msgs_live() == 0, "no legacy migrate message leaked");
}

int main(void) {
    printf("=== HCR epoch model: markers, drains, holds, early advance ===\n\n");
    static const char *names[N_SLOTS] = {
        NULL, "Ord_dispatch", "Many_dispatch", "Drain_dispatch",
        "DrainFmt_dispatch", "Busy_dispatch", "Hold_dispatch",
        "Early_dispatch", "Convert_dispatch", "Full_dispatch",
        "Hard_dispatch", "Death_dispatch" };
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
