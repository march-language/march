/* march_actor_caps returns an OWNED reference to the actor's spawn-site
 * capability record.
 *
 * In a --test build the spawn site stores a record of the actor's
 * capabilities on its runtime meta (march_set_actor_caps, which consumes the
 * record's one reference), and the dispatch reads it back on every message.
 * The dispatch's Perceus releases what it read in each arm that uses no
 * capability, so the read must hand out a reference of its own. It used to
 * return the meta's: the second message to such an actor freed the record and
 * a later one died with "RC underflow" (depot's Pool, in every compiled conduit
 * test that reached Postgres). test/cap_mock/cap_mock_actor_many drives the
 * same thing end to end, but a use-after-free only shows there when the freed
 * cell's rc word happens to still read 0; this checks the count itself.
 *
 * The actor is fake: march_actor_set_dispatch_id creates its meta entry, which
 * is all set/read need, so no scheduler runs. */
#include <assert.h>
#include <stdio.h>
#include <stdint.h>

#include "march_runtime.h"

int main(void) {
    void *actor = march_alloc(48);
    ((int64_t *)actor)[3] = 1;                      /* $alive */
    march_actor_set_dispatch_id(actor, 1, 0);

    /* No record attached yet: the read is None (NULL) and takes nothing. */
    assert(march_actor_caps(actor) == NULL);

    void *caps = march_alloc(16 + 8);               /* { $cap_IO_Console } */
    assert(march_rc_peek(caps) == 1);
    march_set_actor_caps(actor, caps);               /* consumes that one */
    assert(march_rc_peek(caps) == 1);

    /* Each read is a new reference; releasing it, as a dispatch arm does,
     * leaves the meta's reference alone, for any number of messages. */
    for (int msg = 0; msg < 100; msg++) {
        void *got = march_actor_caps(actor);
        assert(got == caps);
        assert(march_rc_peek(caps) == 2);
        march_decrc(got);
        assert(march_rc_peek(caps) == 1);
    }

    /* Two reads outstanding at once hold two references. */
    void *a = march_actor_caps(actor);
    void *b = march_actor_caps(actor);
    assert(march_rc_peek(caps) == 3);
    march_decrc(a);
    march_decrc(b);
    assert(march_rc_peek(caps) == 1);

    printf("test_actor_caps: OK\n");
    return 0;
}
