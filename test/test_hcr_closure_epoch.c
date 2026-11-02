/* Escaping closures retain their creation epoch until their last reference. */
#include "march_runtime.h"
#include "march_scheduler.h"
#include "march_dispatch.h"
#include <assert.h>
#include <stdio.h>
extern void march_panic(void *);
static int old_fn(void) { return 11; }
static int new_fn(void) { return 22; }
static void *make_closure(void *apply) {
    void *p = march_alloc(24);
    *(void **)((char *)p + 16) = apply;
    march_clo_capture_epoch(p);
    return p;
}
static int64_t apply(void *clo, int64_t ignored) {
    (void)ignored;
    march_clo_frame_enter(clo);
    uint32_t v;
    int (*f)(void) = march_dispatch_enter_unit(1, &v);
    int value = f();
    march_dispatch_leave_unit(1, v);
    march_frame_leave();
    return value;
}
static int64_t panic_apply(void *clo, int64_t ignored) {
    (void)ignored;
    march_clo_frame_enter(clo);
    march_frame_own_closure(clo);
    /* Recursive self aliases can own another reference in the same frame. */
    march_incrc(clo);
    march_frame_own_closure(clo);
    march_panic(march_string_lit("closure panic", 13));
    return 0;
}
static void run(void) {
    int64_t before = march_epoch_pins(1);
    void *clo = make_closure((void *)apply);
    assert(march_epoch_pins(1) == before + 1);
    assert(march_epoch_reserve(2) == 0);
    assert(march_dispatch_publish_epoch(1, (void *)new_fn, "new", "new ABI", 0, 2) >= 0);
    march_epoch_advance(2);
    before--; /* activation releases the former global current-epoch pin */
    march_frame_enter(2);
    assert(march_sched_current_epoch() == 2);
    assert(apply(clo, 0) == 11);
    assert(march_sched_current_epoch() == 2);
    void *new_clo = make_closure((void *)apply);
    assert(apply(new_clo, 0) == 22);
    march_clo_release(new_clo);
    march_frame_leave();
    march_clo_release(clo);
    assert(march_epoch_pins(1) == before);
    /* Unwinding an apply frame releases that call's pin, not the closure's. */
    void *bad = make_closure((void *)panic_apply);
    int64_t held = march_epoch_pins(1);
    march_incrc(bad); /* retain the test's reference across the consuming call */
    void *mark = march_frame_mark();
    void *result = march_try_call_val(bad);
    assert(((march_hdr *)result)->tag == 1);
    assert(march_frame_mark() == mark);
    assert(march_epoch_pins(1) == held);
    assert(march_rc_peek(bad) == 1);
    march_clo_release(bad);
    assert(march_epoch_pins(1) == before);
    void *unique_bad = make_closure((void *)panic_apply);
    result = march_try_call_val(unique_bad);
    assert(((march_hdr *)result)->tag == 1);
    assert(march_epoch_pins(1) == before);
    puts("closure creation epochs, fresh work, lifetime and panic cleanup passed");
}
static void pressure(void) {
    /* No actor/main frame protects epoch 1 here: the escaping closure is its
     * only holder after advancing current. Recycle the other ring slots. */
    march_dispatch_init(2);
    march_epoch_reset_for_test();
    march_dispatch_publish(1, (void *)old_fn, "old", "old ABI", 0);
    void *clo = make_closure((void *)apply);
    for (uint32_t e = 2; e < 32; e++) {
        assert(march_epoch_reserve(e) == 0);
        assert(march_dispatch_publish_epoch(1, (void *)new_fn, "new", "new ABI", 0, e) >= 0);
        march_epoch_advance(e);
        assert(march_epoch_pins(1) == 1);
        assert(apply(clo, 0) == 11);
    }
    march_clo_release(clo);
    assert(march_epoch_pins(1) == 0);
    puts("escaping closure alone survives repeated ring reclamation pressure");
}
int main(void) {
    march_dispatch_init(2);
    march_dispatch_publish(1, (void *)old_fn, "old", "old ABI", 0);
    march_spawn_main(run);
    march_run_scheduler();
    pressure();
}
