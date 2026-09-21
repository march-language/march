/* test_signal_watch.c — Signal.watch registration must not erase a delivery.
 *
 * march_signal_watch used to publish the watcher (g_signal_handlers exchange)
 * and THEN clear g_signal_pending/g_signal_seen.  On a re-watch the OS handler
 * is already march_signal_dispatch, so a signal landing between those two
 * steps set pending=1 for the NEW watcher and the trailing clear wiped it: one
 * delivery silently lost.  The window is a few instructions wide, so this test
 * lands the signal in it deterministically through the runtime's test hook,
 * which march_signal_watch calls right after publishing the watcher.
 *
 * SIGHUP (code 2) is used: watchable, and not Term/Int, so the shutdown flag
 * is irrelevant.  raise() runs the handler synchronously on this thread.
 */
#include "march_runtime.h"
#include <signal.h>
#include <stdint.h>
#include <stdio.h>

void march_signal_watch(int64_t code, void *clo);
void march_signal_unwatch(int64_t code);
void march_signal_drain(void);
extern void (*march_signal_watch_test_hook)(int64_t code);

static int g_failed = 0;
#define CHECK(cond, msg) do {                                               \
    if (!(cond)) {                                                          \
        fprintf(stderr, "  FAIL [%s:%d]: %s\n", __func__, __LINE__, (msg)); \
        g_failed++;                                                         \
    }                                                                       \
} while (0)

static int g_calls_a = 0, g_calls_b = 0;

/* Watcher apply fns (closure ABI: apply ptr at +16, called (clo, arg)).  The
 * drain incrc's before each call to balance a capturing watcher's per-call
 * $clo drop; mirror that drop here so the table's reference stays exact. */
static void *apply_a(void *clo, int64_t arg) { (void)arg; g_calls_a++; march_decrc(clo); return NULL; }
static void *apply_b(void *clo, int64_t arg) { (void)arg; g_calls_b++; march_decrc(clo); return NULL; }

static void *make_watcher(void *(*apply)(void *, int64_t)) {
    void *clo = march_alloc(24);
    *(void **)((char *)clo + 16) = (void *)apply;
    return clo;
}

static void raise_hup_hook(int64_t code) {
    if (code == 2) raise(SIGHUP);
}

static void test_delivery_in_registration_window_survives(void) {
    g_calls_a = g_calls_b = 0;
    march_signal_watch(2, make_watcher(apply_a));   /* installs march_signal_dispatch */

    /* Sanity: an ordinary delivery reaches watcher A. */
    raise(SIGHUP);
    march_signal_drain();
    CHECK(g_calls_a == 1, "plain delivery runs the watcher");

    /* Re-watch with B, delivering SIGHUP right after B is published. */
    march_signal_watch_test_hook = raise_hup_hook;
    march_signal_watch(2, make_watcher(apply_b));
    march_signal_watch_test_hook = NULL;
    march_signal_drain();
    CHECK(g_calls_b == 1, "a delivery landing after the new watcher is published is not erased");
    CHECK(g_calls_a == 1, "the replaced watcher is not run for it");

    /* A delivery right after watch returns also survives. */
    raise(SIGHUP);
    march_signal_drain();
    CHECK(g_calls_b == 2, "delivery after watch returns runs the watcher");

    march_signal_unwatch(2);
    if (g_failed == 0) printf("PASS: test_delivery_in_registration_window_survives\n");
}

int main(void) {
    test_delivery_in_registration_window_survives();
    if (g_failed == 0) { printf("test_signal_watch: all checks passed\n"); return 0; }
    fprintf(stderr, "test_signal_watch: %d check(s) failed\n", g_failed);
    return 1;
}
