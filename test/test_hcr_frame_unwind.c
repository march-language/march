#include "march_runtime.h"
#include "march_scheduler.h"
#include "march_dispatch.h"
#include <assert.h>
#include <stdio.h>
extern void march_panic(void *);
static int old_fn(void) { return 11; }
static int64_t boom(void *clo, int64_t arg) {
    (void)clo; (void)arg;
    uint32_t v;
    assert(march_dispatch_enter_unit(1, &v));
    assert(march_dispatch_enter_unit(1, &v));
    march_panic(march_string_lit("frame panic", 11));
    return 0;
}
static void run(void) {
    uint32_t v;
    assert(march_dispatch_enter_unit(1, &v));
    void *outer = march_frame_mark();
    int64_t pins = march_epoch_pins(1);
    int64_t clo[] = {INT64_MAX, 0, (int64_t)(uintptr_t)boom};
    void *result = march_try_call_val(clo);
    assert(((march_hdr *)result)->tag == 1);
    assert(march_frame_mark() == outer);
    assert(march_dispatch_refs(1, v) == 1);
    assert(march_epoch_pins(1) == pins);
    march_dispatch_leave_unit(1, v);
}
int main(void) {
    march_dispatch_init(2);
    march_dispatch_publish(1, (void *)old_fn, "old", "sig", 0);
    march_spawn_main(run);
    march_run_scheduler();
    assert(march_epoch_pins(1) == 1);
    puts("caught panic restores outer frame and refs");
}
