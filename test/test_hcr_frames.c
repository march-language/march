/* Routing belongs to a running frame, including main, across yields/deploys. */
#include "march_scheduler.h"
#include "march_dispatch.h"
#include <assert.h>
#include <stdio.h>
static int old_fn(void) { return 11; }
static int new_fn(void) { return 22; }
static _Atomic int fresh_done;
void march_frame_drop_closure(void *closure) {
    assert(closure != NULL);
    assert(march_sched_current_epoch() == 2);
    march_sched_yield();
    assert(march_sched_current_epoch() == 2);
}
static void fresh(void *unused) {
    (void)unused;
    assert(march_sched_current_epoch() == 2);
    uint32_t v;
    int (*fn)(void) = march_dispatch_enter_unit(1, &v);
    assert(fn() == 22);
    march_frame_own_closure((void *)1);
    atomic_store(&fresh_done, 1);
    /* Deliberately terminate with a live dispatch frame: reap releases it. */
}
static void run(void *unused) {
    (void)unused;
    march_frame_enter(0);
    march_frame_disown_closure(NULL);
    march_frame_leave();
    uint32_t initial = march_sched_current_epoch();
    assert(initial == MARCH_EPOCH_BASE);
    uint32_t v;
    int (*fn)(void) = march_dispatch_enter_unit(1, &v);
    assert(fn() == 11);
    void *held_frame = march_frame_mark();
    uint32_t raw;
    assert(march_dispatch_enter_gen(1, initial, &raw));
    march_dispatch_leave(1, raw);
    assert(march_frame_mark() == held_frame);
    assert(march_epoch_reserve(2) == 0);
    assert(march_dispatch_publish_epoch(1, (void *)new_fn, "new", "new ABI", 0, 2) >= 0);
    march_epoch_advance(2);
    march_sched_spawn_current(fresh, NULL);
    void *outer = march_frame_mark();
    march_frame_enter(2);
    march_frame_own_closure((void *)1);
    assert(march_sched_current_epoch() == 2);
    assert(march_sched_send_epoch() == 2);
    march_frame_unwind(outer);
    assert(march_sched_send_epoch() == initial);
    for (int i = 0; i < 100; i++) march_sched_yield();
    uint32_t nested;
    fn = march_dispatch_enter_unit(1, &nested);
    assert(fn() == 11);
    march_dispatch_leave_unit(1, nested);
    assert(march_sched_current_epoch() == initial);
    march_dispatch_leave_unit(1, v);
    assert(march_sched_current_epoch() == initial);
    march_frame_enter(2);
    assert(march_epoch_reserve(3) == 0);
    assert(march_dispatch_publish_epoch(1, (void *)new_fn, "third", "third ABI", 0, 3) >= 0);
    march_epoch_advance(3);
    assert(!march_dispatch_can_stage(1)); /* main, frame 2, current 3 */
    march_frame_leave();
    while (!atomic_load(&fresh_done) || !march_dispatch_can_stage(1)) march_sched_yield();
    assert(march_sched_current_epoch() == initial);
}
static void replay_main(void *unused) {
    (void)unused;
    assert(march_sched_current_epoch() == MARCH_EPOCH_BASE);
    uint32_t v;
    int (*fn)(void) = march_dispatch_enter_unit(1, &v);
    assert(fn() == 11);
    march_dispatch_leave_unit(1, v);
}
int main(int argc, char **argv) {
    (void)argv;
    march_dispatch_init(2);
    march_dispatch_publish(1, (void *)old_fn, "old", "old ABI", 0);
    march_sched_init();
    if (argc > 1) {
        /* Simulate startup retaining the entry image while persisted
         * patches restore a newer current epoch before main is spawned. */
        march_dispatch_reserve_main();
        assert(march_epoch_reserve(2) == 0);
        march_dispatch_publish_epoch(1, (void *)new_fn, "replay", "new ABI", 0, 2);
        march_epoch_advance(2);
        march_sched_spawn_main(replay_main, NULL, 0);
        march_sched_request_shutdown();
        march_sched_run();
        assert(march_epoch_pins(1) == 0);
        puts("replayed main retains baseline ABI");
        return 0;
    }
    march_sched_spawn_main(run, NULL, 0);
    march_sched_request_shutdown();
    march_sched_run();
    assert(march_epoch_pins(1) == 0);
    assert(march_epoch_pins(2) == 0);
    assert(march_epoch_pins(3) == 1);
    for (uint32_t v = 0; v < MARCH_MAX_LIVE_VERSIONS; v++)
        assert(march_dispatch_refs(1, v) == 0);
    puts("frame routing passed");
}
