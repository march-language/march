/* Registry semantics at the C level. Actors here are fake: the registry only
 * ever reads word 3 (the $alive flag) of the actor record, so a heap object
 * with word 3 set is a sufficient stand-in and keeps this test free of the
 * scheduler.
 *
 * NOTE on Option encoding: march_actor_whereis returns a NICHE-encoded
 * Option(ptr), matching march_vault_get's own convention (see the comment
 * above march_vault_update in runtime/march_extras.c): None = NULL, and
 * Some(actor) = the actor pointer itself, with no tag word to inspect. This
 * differs from a boxed Option (e.g. Option(Float)), which allocates a
 * [rc][tag][pad][payload] cell — that boxed shape does NOT apply here
 * because a heap actor pointer is always non-NULL, so NULL is a safe niche
 * for None. */
#include <assert.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

extern void   *march_alloc(int64_t);
extern void   *march_string_lit(const char *, int64_t);
extern int64_t march_actor_register(void *name, void *actor);
extern int64_t march_actor_unregister(void *name);
extern void   *march_actor_whereis(void *name);
extern void   *march_actor_registered(void);

static void *fake_actor(void) {
    void *a = march_alloc(48);
    ((int64_t *)a)[3] = 1;          /* $alive */
    return a;
}

static void *str(const char *s) {
    return march_string_lit(s, (int64_t)strlen(s));
}

/* niche encoding: NULL = None, non-NULL = Some(ptr) */
static int is_some(void *opt) { return opt != NULL; }

int main(void) {
    void *a = fake_actor();
    void *n = str("ledger");

    assert(march_actor_register(n, a) == 1);
    assert(is_some(march_actor_whereis(str("ledger"))));

    /* A second live registration under the same name must FAIL rather than
     * silently steal the name. */
    void *b = fake_actor();
    assert(march_actor_register(str("ledger"), b) == 0);

    /* A dead actor resolves to None even before cleanup runs — lookup checks
     * liveness, because cleanup and lookup race by nature. */
    ((int64_t *)a)[3] = 0;
    assert(!is_some(march_actor_whereis(str("ledger"))));

    /* And the name is now reusable by a different actor. */
    assert(march_actor_register(str("ledger"), b) == 1);
    assert(is_some(march_actor_whereis(str("ledger"))));

    assert(march_actor_unregister(str("ledger")) == 1);
    assert(!is_some(march_actor_whereis(str("ledger"))));
    assert(march_actor_unregister(str("ledger")) == 0);

    /* march_actor_registered() lists live names and excludes dead ones. */
    void *c = fake_actor();
    assert(march_actor_register(str("alpha"), c) == 1);
    void *d = fake_actor();
    assert(march_actor_register(str("beta"), d) == 1);
    ((int64_t *)d)[3] = 0;   /* beta's actor dies without unregistering */

    void *names = march_actor_registered();
    int seen_alpha = 0, seen_beta = 0;
    for (void *p = names; p && ((int32_t *)((char *)p + 8))[0] == 1;
         p = *(void **)((char *)p + 24)) {
        void *hs = *(void **)((char *)p + 16);
        /* march_string layout: [rc:8][tag:4][pad:4][len:8][data...] */
        int64_t len = *(int64_t *)((char *)hs + 16);
        const char *data = (const char *)hs + 24;
        if (len == 5 && memcmp(data, "alpha", 5) == 0) seen_alpha = 1;
        if (len == 4 && memcmp(data, "beta", 4) == 0) seen_beta = 1;
    }
    assert(seen_alpha);
    assert(!seen_beta);

    printf("test_actor_registry: all passed\n");
    return 0;
}
