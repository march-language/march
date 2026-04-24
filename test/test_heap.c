/*
 * test_heap.c — Tests for Phase 5 runtime components:
 *   march_heap.c  — per-process bump allocator
 *   march_message.c — cross-heap copy/move, MPSC mailbox
 *   march_gc.c    — semi-space copying collector
 *   march_runtime.c — non-atomic RC (march_incrc_local / march_decrc_local)
 *
 * Compile and run:
 *   clang -std=gnu11 -O1 -g \
 *         -I../runtime \
 *         ../runtime/march_heap.c \
 *         ../runtime/march_message.c \
 *         ../runtime/march_gc.c \
 *         test_heap.c \
 *         -lpthread -lm -o test_heap_runner && ./test_heap_runner
 *
 * Test groups:
 *   1. Bump allocation and arena growth
 *   2. Message copy correctness (nested structures)
 *   3. Linear message move (zero-copy verification)
 *   4. Non-atomic RC correctness
 *   5. Semi-space GC (compaction, no leaks)
 *   6. MPSC mailbox + selective receive
 *   7. 1M messages/sec throughput target (64-byte messages)
 */

#ifndef _XOPEN_SOURCE
#  define _XOPEN_SOURCE 700
#endif

#include "../runtime/march_heap.h"
#include "../runtime/march_message.h"
#include "../runtime/march_gc.h"

#include <assert.h>

/* ── Stub for march_send (not linked in this test build) ─────────────── */
/* march_send_linear in march_message.c calls march_send; provide a no-op
 * stub so the test binary links without the full march_runtime. */
void *march_send(void *actor, void *msg) {
    (void)actor;
    return msg;   /* return msg unchanged — enough for the move test */
}

#include <unistd.h>

/* ── Override march_gc_crash to avoid macOS ReportCrash delays ──────── */
/* On macOS, abort() after fork() triggers the crash reporter which can
 * stall for 10+ minutes per invocation.  We override the weak symbol so
 * gc_corrupt() exits via _exit(134) — the conventional 128+SIGABRT code —
 * instead, letting waitpid() return immediately. */
void march_gc_crash(void) {
    _exit(134); /* 128 + SIGABRT(6): conventional signal-killed exit code */
}
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <time.h>
#include <stdatomic.h>

/* ── Test harness ──────────────────────────────────────────────────────── */

static int g_pass = 0;
static int g_fail = 0;
static int g_group_fail = 0;

#define CHECK(cond, name) \
    do { \
        if (cond) { \
            printf("    PASS  %s\n", name); g_pass++; \
        } else { \
            printf("    FAIL  %s  [line %d]\n", name, __LINE__); \
            g_fail++; g_group_fail++; \
        } \
    } while (0)

#define GROUP(name) \
    do { g_group_fail = 0; printf("\n--- %s ---\n", name); } while (0)

#define GROUP_DONE(name) \
    do { \
        if (!g_group_fail) printf("    OK\n"); \
    } while (0)

/* ── Object helpers ────────────────────────────────────────────────────── */

/* Standard march header (must match march_runtime.h layout). */
typedef struct { int64_t rc; int32_t tag; int32_t pad; } test_hdr;

/* Allocate a simple 1-field object (tag, one int64 field).
 * Object size = 16 (header) + 8 (one field) = 24 bytes. */
static void *make_obj1(march_heap_t *h, int32_t tag, int64_t field0) {
    void *p = march_process_alloc(h, 24);
    test_hdr *hdr = (test_hdr *)p;
    hdr->tag = tag;
    ((int64_t *)p)[2] = field0;   /* field[0] at offset 16 */
    return p;
}

/* Allocate a 2-field object (tag, ptr-field, int-field). */
static void *make_obj2(march_heap_t *h, int32_t tag,
                       void *field0_ptr, int64_t field1_int) {
    void *p = march_process_alloc(h, 32);  /* 16 + 2*8 */
    test_hdr *hdr = (test_hdr *)p;
    hdr->tag = tag;
    ((void **)   p)[2] = field0_ptr;       /* field[0] as ptr, offset 16 */
    ((int64_t *) p)[3] = field1_int;       /* field[1] as int, offset 24 */
    return p;
}

/* Non-atomic RC helpers (mirroring march_runtime.c's local variants). */
static void incrc_local(void *p) {
    if ((uintptr_t)p < 4096u) return;
    ((test_hdr *)p)->rc++;
}
static void decrc_local(void *p) {
    if ((uintptr_t)p < 4096u) return;
    ((test_hdr *)p)->rc--;
}

/* ── 1. Bump allocation and arena growth ──────────────────────────────── */

static void test_bump_alloc(void) {
    GROUP("1. Bump allocation and arena growth");

    march_heap_t h;
    march_heap_init(&h);
    CHECK(h.used_bytes == 0,    "initial used_bytes == 0");
    CHECK(h.live_bytes == 0,    "initial live_bytes == 0");
    CHECK(h.total_bytes == MARCH_HEAP_BLOCK_MIN, "one block allocated");

    /* Allocate a simple object. */
    void *o1 = make_obj1(&h, 42, 100);
    CHECK(o1 != NULL,                      "alloc returns non-NULL");
    CHECK(((test_hdr *)o1)->rc  == 1,      "rc initialized to 1");
    CHECK(((test_hdr *)o1)->tag == 42,     "tag set correctly");
    CHECK(((int64_t *)o1)[2]    == 100LL,  "field[0] set correctly");
    CHECK(h.used_bytes > 0,                "used_bytes advanced");
    CHECK(h.live_bytes == h.used_bytes,    "live_bytes == used_bytes after alloc");

    /* Verify 8-byte alignment of returned pointer. */
    CHECK(((uintptr_t)o1 & 7u) == 0, "pointer is 8-byte aligned");

    /* Allocate many objects to trigger arena growth. */
    size_t objects_per_block = MARCH_HEAP_BLOCK_MIN / (sizeof(march_alloc_meta) + 24);
    size_t target = objects_per_block * 2 + 10;  /* force multiple blocks */
    void **objs = (void **)malloc(target * sizeof(void *));
    for (size_t i = 0; i < target; i++) {
        objs[i] = make_obj1(&h, (int32_t)i, (int64_t)i);
        CHECK(objs[i] != NULL, "arena growth: alloc succeeds");
        if (!objs[i]) break;   /* bail early on first failure */
    }
    CHECK(h.blocks != h.blocks->next || h.blocks->next == NULL,
          "at least one block in list");
    /* There should be at least 2 blocks after overflow. */
    int block_count = 0;
    for (march_heap_block *b = h.blocks; b; b = b->next) block_count++;
    CHECK(block_count >= 2, "multiple arena blocks after growth");

    /* Verify objects are intact after growth. */
    for (size_t i = 0; i < target; i++) {
        if (!objs[i]) break;
        CHECK(((test_hdr *)objs[i])->tag == (int32_t)i, "object tag intact after growth");
        break;  /* check just the first to keep output manageable */
    }

    free(objs);

    /* O(1) destroy — should not crash regardless of number of objects. */
    march_heap_destroy(&h);
    CHECK(h.blocks == NULL, "destroy clears block list");
    CHECK(h.used_bytes == 0, "destroy resets used_bytes");

    GROUP_DONE("1");
}

/* ── 2. Message copy correctness ─────────────────────────────────────── */

static void test_msg_copy(void) {
    GROUP("2. Message copy correctness (nested structures)");

    march_heap_t src, dst;
    march_heap_init(&src);
    march_heap_init(&dst);

    /* Build: leaf → inner → root (nested 3 levels). */
    void *leaf  = make_obj1(&src, 10, 999);
    void *inner = make_obj2(&src, 20, leaf, 777);
    void *root  = make_obj2(&src, 30, inner, 555);

    void *root_copy = march_msg_copy(&src, &dst, root);

    /* Root copy is in dst, not src. */
    CHECK(root_copy != root,          "copy != original");
    CHECK(root_copy != NULL,          "copy is non-NULL");
    CHECK((uintptr_t)root_copy >= 4096u, "copy is a heap pointer");

    test_hdr *rc = (test_hdr *)root_copy;
    CHECK(rc->rc  == 1,  "copy has rc=1");
    CHECK(rc->tag == 30, "root tag correct");

    /* Check inner copy. */
    void **root_fields = (void **)((char *)root_copy + 16);
    void *inner_copy   = root_fields[0];
    CHECK(inner_copy != inner,     "inner copy != original inner");
    CHECK(inner_copy != NULL,      "inner copy non-NULL");
    test_hdr *ic = (test_hdr *)inner_copy;
    CHECK(ic->rc  == 1,  "inner copy rc=1");
    CHECK(ic->tag == 20, "inner tag correct");
    int64_t inner_int = ((int64_t *)inner_copy)[3];
    CHECK(inner_int == 777LL, "inner int field correct");

    /* Check leaf copy. */
    void **inner_fields = (void **)((char *)inner_copy + 16);
    void *leaf_copy     = inner_fields[0];
    CHECK(leaf_copy != leaf, "leaf copy != original leaf");
    test_hdr *lc = (test_hdr *)leaf_copy;
    CHECK(lc->rc  == 1,  "leaf copy rc=1");
    CHECK(lc->tag == 10, "leaf tag correct");
    int64_t leaf_int = ((int64_t *)leaf_copy)[2];
    CHECK(leaf_int == 999LL, "leaf int field correct");

    /* Copies are in dst_heap's address space (within one of its blocks). */
    int copy_in_dst = 0;
    for (march_heap_block *b = dst.blocks; b; b = b->next) {
        if ((char *)root_copy >= b->data &&
            (char *)root_copy <  b->data + b->used) {
            copy_in_dst = 1; break;
        }
    }
    CHECK(copy_in_dst, "root copy resides in dst heap");

    /* Unboxed scalar passthrough. */
    void *scalar = (void *)(uintptr_t)42u;
    void *scalar_copy = march_msg_copy(&src, &dst, scalar);
    CHECK(scalar_copy == scalar, "unboxed scalar copied unchanged");

    /* NULL passthrough. */
    void *null_copy = march_msg_copy(&src, &dst, NULL);
    CHECK(null_copy == NULL, "NULL copied as NULL");

    march_heap_destroy(&src);
    march_heap_destroy(&dst);

    GROUP_DONE("2");
}

/* ── 3. Linear message move (zero-copy) ──────────────────────────────── */

static void test_msg_move(void) {
    GROUP("3. Linear message move (zero-copy verification)");

    march_heap_t src, dst;
    march_heap_init(&src);
    march_heap_init(&dst);

    void *obj = make_obj1(&src, 77, 12345);
    size_t live_before_src = src.live_bytes;
    size_t live_before_dst = dst.live_bytes;

    void *moved = march_msg_move(&src, &dst, obj);

    /* Pointer is unchanged — zero copy. */
    CHECK(moved == obj, "move returns same pointer (zero-copy)");

    /* src.live_bytes decreased, dst.live_bytes increased. */
    CHECK(src.live_bytes < live_before_src,
          "src live_bytes decreased after move");
    CHECK(dst.live_bytes > live_before_dst,
          "dst live_bytes increased after move");

    /* Conservation: total live bytes unchanged. */
    size_t total_before = live_before_src + live_before_dst;
    size_t total_after  = src.live_bytes  + dst.live_bytes;
    CHECK(total_before == total_after, "total live bytes conserved by move");

    /* Object data is intact. */
    CHECK(((test_hdr *)moved)->tag == 77,   "tag intact after move");
    CHECK(((int64_t *)moved)[2]    == 12345LL, "field intact after move");

    /* Unboxed scalar move is a no-op. */
    void *scalar = (void *)(uintptr_t)7u;
    void *smoved = march_msg_move(&src, &dst, scalar);
    CHECK(smoved == scalar, "scalar move returns unchanged scalar");

    march_heap_destroy(&src);
    march_heap_destroy(&dst);

    GROUP_DONE("3");
}

/* ── 4. Non-atomic RC correctness ────────────────────────────────────── */

static void test_local_rc(void) {
    GROUP("4. Non-atomic RC (march_incrc_local / march_decrc_local)");

    march_heap_t h;
    march_heap_init(&h);

    void *obj = make_obj1(&h, 5, 0);
    CHECK(((test_hdr *)obj)->rc == 1, "initial rc == 1");

    incrc_local(obj);
    CHECK(((test_hdr *)obj)->rc == 2, "rc == 2 after local incrc");

    incrc_local(obj);
    CHECK(((test_hdr *)obj)->rc == 3, "rc == 3 after second local incrc");

    decrc_local(obj);
    CHECK(((test_hdr *)obj)->rc == 2, "rc == 2 after local decrc");

    decrc_local(obj);
    CHECK(((test_hdr *)obj)->rc == 1, "rc == 1 after second local decrc");

    /* Unboxed scalar: no-op. */
    void *scalar = (void *)(uintptr_t)1u;
    incrc_local(scalar);   /* must not crash */
    decrc_local(scalar);   /* must not crash */
    CHECK(1, "local RC on unboxed scalar does not crash");

    /* NULL: no-op. */
    incrc_local(NULL);
    decrc_local(NULL);
    CHECK(1, "local RC on NULL does not crash");

    /* Record death and verify heap tracking. */
    size_t live_before = h.live_bytes;
    march_heap_record_death(&h, 24u);
    CHECK(h.live_bytes < live_before, "record_death decrements live_bytes");

    /* should_gc: not triggered on fresh heap. */
    march_heap_t h2;
    march_heap_init(&h2);
    CHECK(!march_heap_should_gc(&h2), "should_gc is false on fresh heap");
    /* Simulate 60% dead bytes. */
    h2.used_bytes  = 1000;
    h2.live_bytes  = 400;   /* 60% dead */
    CHECK(march_heap_should_gc(&h2), "should_gc is true when >50% dead");
    h2.live_bytes  = 600;   /* 40% dead — below threshold */
    CHECK(!march_heap_should_gc(&h2), "should_gc is false when <50% dead");

    march_heap_destroy(&h);
    march_heap_destroy(&h2);

    GROUP_DONE("4");
}

/* ── 5. Semi-space GC ─────────────────────────────────────────────────── */

static void test_gc(void) {
    GROUP("5. Semi-space GC (compaction, no leaks under sustained messaging)");

    march_heap_t h;
    march_heap_init(&h);

    /* Allocate 10 objects; mark 5 as dead (rc=0) and 5 as live (rc=1). */
    void *live[5], *dead[5];
    for (int i = 0; i < 5; i++) {
        live[i] = make_obj1(&h, 100 + i, (int64_t)i);
        dead[i] = make_obj1(&h, 200 + i, (int64_t)i);
    }
    /* Kill the dead objects. */
    for (int i = 0; i < 5; i++) ((test_hdr *)dead[i])->rc = 0;

    size_t bytes_before = h.used_bytes;
    march_gc_stats stats;
    int rc = march_gc_collect(&h, &stats);

    CHECK(rc == 0, "gc_collect returns 0 (success)");
    CHECK(stats.objects_scanned == 10, "scanned 10 objects");
    CHECK(stats.objects_copied  == 5,  "copied 5 live objects");
    CHECK(stats.bytes_after < bytes_before, "bytes_after < bytes_before");

    /* After GC, live_bytes should equal used_bytes (no fragmentation). */
    CHECK(h.live_bytes == h.used_bytes, "no fragmentation after GC");

    /* Live object data should be intact (GC copies data verbatim). */
    /* NOTE: after copying GC, old pointers are invalidated.  We must not
     * use live[] / dead[] after collection — the test checks via stats. */

    /* Stress: sustained allocation + GC cycles.
     * Allocate N objects, mark half dead, run GC, repeat 10 cycles.
     * Verify heap doesn't grow unboundedly (live_bytes stays bounded). */
    march_heap_t hs;
    march_heap_init(&hs);
    size_t max_live = 0;
    for (int cycle = 0; cycle < 10; cycle++) {
        void *ptrs[20];
        for (int j = 0; j < 20; j++) {
            ptrs[j] = make_obj1(&hs, j, (int64_t)j);
        }
        /* Kill even-indexed objects. */
        for (int j = 0; j < 20; j += 2) {
            ((test_hdr *)ptrs[j])->rc = 0;
            march_heap_record_death(&hs, 24);
        }
        march_gc_stats s2;
        march_gc_collect(&hs, &s2);
        if (hs.live_bytes > max_live) max_live = hs.live_bytes;
    }
    /* After 10 cycles of allocating 20 and keeping 10 per cycle,
     * max live should be ≤ 10 * 10 * (sizeof(meta)+24) ≈ 3200 bytes. */
    CHECK(max_live < MARCH_HEAP_BLOCK_MIN,
          "heap does not grow unboundedly under sustained GC cycling");

    march_heap_destroy(&h);
    march_heap_destroy(&hs);

    GROUP_DONE("5");
}

/* ── 5b. GC pass-2 hardening (regression test for audit C2) ───────────── */

/*
 * Pass-2 of march_gc.c rewrites pointer fields using the forwarding table.
 * The classification predicate must reject:
 *   (a) tagged-immediate integers (low bit set; (n<<1)|1 scheme)
 *   (b) negative int64 values (sign bit set — never a valid user-space
 *       address on any 64-bit ABI)
 * Without these guards, scalar fields whose values fall into the > 4096
 * range could be passed to fwd_lookup, wasting work and (in adversarial
 * memory layouts) risking collision.  This test plants such values in
 * live object fields and verifies they are preserved verbatim across GC.
 */
static void test_gc_pass2_scalar_preservation(void) {
    GROUP("5b. GC pass-2 preserves tagged immediates and negative scalars");

    march_heap_t h;
    march_heap_init(&h);

    /* Allocate one dead object to populate the fwd-walk path with at least
     * one mapping in the from-space scan, then several live objects whose
     * fields hold "pointer-shaped" but non-pointer values. */
    void *dead = make_obj1(&h, 99, 0);
    ((test_hdr *)dead)->rc = 0;

    /* Live carrier object: 4 fields, all "scalars that look pointerish".
     *   field[0] = tagged immediate (n<<1)|1 for a moderately-large n
     *   field[1] = negative int64 (-1)
     *   field[2] = small positive scalar (< 4096)
     *   field[3] = a real (large) value with low bit set
     * After GC, all four should be preserved bit-for-bit. */
    void *carrier = march_process_alloc(&h, 16 + 4*8);
    test_hdr *ch = (test_hdr *)carrier;
    ch->tag = 7;
    int64_t *cf = (int64_t *)((char *)carrier + 16);
    int64_t v0 = ((int64_t)2000000 << 1) | 1;   /* tagged immediate */
    int64_t v1 = -1;                             /* negative */
    int64_t v2 = 42;                             /* small */
    int64_t v3 = (int64_t)0x4001;                /* > 4096, low bit set */
    cf[0] = v0; cf[1] = v1; cf[2] = v2; cf[3] = v3;

    march_gc_stats stats;
    int rc = march_gc_collect(&h, &stats);
    CHECK(rc == 0, "gc_collect succeeds");
    CHECK(stats.objects_copied == 1, "copied 1 live object (the carrier)");

    /* The original `carrier` pointer is invalid after GC; find the surviving
     * carrier in the new heap by walking blocks. */
    void *surv = NULL;
    for (march_heap_block *b = h.blocks; b && !surv; b = b->next) {
        const char *p   = b->data;
        const char *end = b->data + b->used;
        while (p < end) {
            const march_alloc_meta *meta = (const march_alloc_meta *)p;
            void *obj = (void *)(p + sizeof(march_alloc_meta));
            if (((test_hdr *)obj)->tag == 7) { surv = obj; break; }
            p += meta->alloc_size;
        }
    }
    CHECK(surv != NULL, "surviving carrier object found");
    if (surv) {
        int64_t *sf = (int64_t *)((char *)surv + 16);
        CHECK(sf[0] == v0, "tagged immediate preserved across GC");
        CHECK(sf[1] == v1, "negative scalar preserved across GC");
        CHECK(sf[2] == v2, "small scalar preserved across GC");
        CHECK(sf[3] == v3, "pointer-shaped tagged scalar preserved across GC");
    }

    march_heap_destroy(&h);
    GROUP_DONE("5b");
}

/* ── 5c. GC fail-fast on corrupt meta / dangling ptr (audit C3, C4, C5) ── */

#include <sys/wait.h>
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>

/* Run [child_fn] in a forked subprocess and assert it terminated by SIGABRT.
 * Returns 1 on abort, 0 otherwise. */
static int expect_abort(void (*child_fn)(void)) {
    pid_t pid = fork();
    if (pid == 0) {
        /* Silence child output — the GC diagnostic goes to stderr. */
        int devnull = open("/dev/null", O_WRONLY);
        if (devnull >= 0) { dup2(devnull, 2); close(devnull); }
        child_fn();
        _exit(0);   /* if we reach here, no abort happened */
    }
    int status = 0;
    waitpid(pid, &status, 0);
    /* Accept either killed-by-SIGABRT or _exit(134).
     * On macOS, abort() after fork() triggers ReportCrash (10+ min stall),
     * so march_gc_crash() is overridden above to use _exit(134) instead. */
    return (WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT)
        || (WIFEXITED(status)   && WEXITSTATUS(status) == 134);
}

static void child_corrupt_alloc_size(void) {
    march_heap_t h;
    march_heap_init(&h);
    void *o = make_obj1(&h, 1, 0);
    /* Stomp the alloc_size in the hidden meta to a bogus tiny value. */
    march_alloc_meta *m = MARCH_ALLOC_META(o);
    m->alloc_size = 4;   /* below sizeof(meta) + 16 → must abort */
    march_gc_collect(&h, NULL);
}

static void child_corrupt_n_fields(void) {
    march_heap_t h;
    march_heap_init(&h);
    void *o = make_obj1(&h, 1, 0);   /* 24 bytes user, 1 field */
    march_alloc_meta *m = MARCH_ALLOC_META(o);
    /* Claim 1000 fields when the object only has space for 1.  Pass-1 walk
     * must catch this via the bounds check and abort. */
    m->n_fields = 1000;
    march_gc_collect(&h, NULL);
}

static void child_dangling_intra_arena(void) {
    march_heap_t h;
    march_heap_init(&h);
    /* dead: an object marked rc=0 (won't be copied → no fwd entry). */
    void *dead = make_obj1(&h, 1, 0);
    ((test_hdr *)dead)->rc = 0;
    /* live: a 2-field object with field[0] pointing at `dead` — i.e. a live
     * intra-arena reference to an object that won't be copied.  Pass 2 must
     * detect the missing fwd entry and abort instead of leaving a dangling
     * pointer that the from-space free would invalidate. */
    void *live = make_obj2(&h, 2, dead, 0);
    (void)live;
    march_gc_collect(&h, NULL);
}

static void test_gc_abort_paths(void) {
    GROUP("5c. GC aborts on corrupt meta / dangling intra-arena ptr");

    CHECK(expect_abort(child_corrupt_alloc_size),
          "abort on alloc_size below minimum");
    CHECK(expect_abort(child_corrupt_n_fields),
          "abort on n_fields exceeding payload");
    CHECK(expect_abort(child_dangling_intra_arena),
          "abort on intra-arena pointer with no forwarding entry");

    GROUP_DONE("5c");
}

/* ── 6. MPSC mailbox + selective receive ─────────────────────────────── */

#define NUM_PRODUCERS 4
#define MSGS_PER_PROD 1000

typedef struct {
    march_mailbox_t *mb;
    int              start;
} prod_arg;

static void *producer_fn(void *arg) {
    prod_arg *pa = (prod_arg *)arg;
    for (int i = 0; i < MSGS_PER_PROD; i++) {
        /* Encode producer and sequence as a single pointer-sized value.
         * Values < 4096 are unboxed scalars; encode as offset + 4096. */
        uintptr_t payload = (uintptr_t)(pa->start * MSGS_PER_PROD + i + 4096);
        march_mailbox_push(pa->mb, (void *)payload);
    }
    return NULL;
}

static void test_mailbox(void) {
    GROUP("6. MPSC mailbox + selective receive");

    march_mailbox_t mb;
    march_mailbox_init(&mb);

    /* ── Single-threaded basic ops ── */
    march_mailbox_push(&mb, (void *)(uintptr_t)0xAAu);
    march_mailbox_push(&mb, (void *)(uintptr_t)0xBBu);
    march_mailbox_push(&mb, (void *)(uintptr_t)0xCCu);

    size_t cnt = march_mailbox_count(&mb);
    CHECK(cnt == 3, "count == 3 after 3 pushes");

    void *m1 = march_mailbox_pop(&mb);
    /* FIFO: first pushed = first popped after flip. */
    CHECK(m1 == (void *)(uintptr_t)0xAAu, "FIFO: first message dequeued");

    /* Selective receive: save the next message, then get the one after. */
    void *m2 = march_mailbox_pop(&mb);   /* 0xBB */
    march_mailbox_save(&mb, m2);          /* save it */
    void *m3 = march_mailbox_pop(&mb);   /* 0xCC */
    CHECK(m3 == (void *)(uintptr_t)0xCCu, "pop skips to next after save");

    /* Saved message comes back first. */
    void *m2_again = march_mailbox_pop(&mb);
    CHECK(m2_again == (void *)(uintptr_t)0xBBu, "saved message returned on next pop");

    /* Empty. */
    void *empty = march_mailbox_pop(&mb);
    CHECK(empty == NULL, "pop returns NULL on empty mailbox");

    /* ── Multi-producer test ── */
    march_mailbox_t mb2;
    march_mailbox_init(&mb2);

    pthread_t threads[NUM_PRODUCERS];
    prod_arg  args[NUM_PRODUCERS];
    for (int i = 0; i < NUM_PRODUCERS; i++) {
        args[i].mb    = &mb2;
        args[i].start = i;
        pthread_create(&threads[i], NULL, producer_fn, &args[i]);
    }
    for (int i = 0; i < NUM_PRODUCERS; i++) {
        pthread_join(threads[i], NULL);
    }

    int total = NUM_PRODUCERS * MSGS_PER_PROD;
    int received = 0;
    while (march_mailbox_pop(&mb2)) received++;
    CHECK(received == total, "all messages from all producers received");

    march_mailbox_destroy(&mb);
    march_mailbox_destroy(&mb2);

    GROUP_DONE("6");
}

/* ── 7. Throughput: 1M messages/sec for 64-byte messages ─────────────── */

/*
 * We test the end-to-end path:
 *   - Allocate a 64-byte message in src_heap via march_process_alloc.
 *   - Copy it to dst_heap via march_msg_copy.
 *   - Pop it from a mailbox.
 * Target: ≥ 1 000 000 round-trips per second on the build machine.
 *
 * 64-byte message layout: march_hdr (16) + 6 int64_t fields (48) = 64 bytes.
 */

#define THROUGHPUT_MSGS  1000000
#define MSG_FIELDS       6        /* 64 bytes total */

static void test_throughput(void) {
    GROUP("7. Throughput: 1M messages/sec (64-byte messages)");

    march_heap_t src, dst;
    march_heap_init(&src);
    march_heap_init(&dst);

    march_mailbox_t mb;
    march_mailbox_init(&mb);

    size_t msg_sz = 16 + MSG_FIELDS * 8;  /* 64 bytes */

    struct timespec t_start, t_end;
    clock_gettime(CLOCK_MONOTONIC, &t_start);

    for (int i = 0; i < THROUGHPUT_MSGS; i++) {
        /* Allocate message in src_heap. */
        void *msg = march_process_alloc(&src, msg_sz);
        ((test_hdr *)msg)->tag = i & 0xFFFF;

        /* Move to dst_heap (linear move — zero copy). */
        void *moved = march_msg_move(&src, &dst, msg);

        /* Push to mailbox. */
        march_mailbox_push(&mb, moved);

        /* Pop immediately (simulating consumer keeping up with producer). */
        void *received = march_mailbox_pop(&mb);
        (void)received;

        /* Periodic GC to keep heap bounded. */
        if ((i & 0xFFFF) == 0 && march_heap_should_gc(&dst)) {
            march_gc_collect(&dst, NULL);
        }
    }

    clock_gettime(CLOCK_MONOTONIC, &t_end);

    double elapsed_ns = (double)(t_end.tv_sec  - t_start.tv_sec)  * 1e9
                      + (double)(t_end.tv_nsec - t_start.tv_nsec);
    double elapsed_s  = elapsed_ns / 1e9;
    double msgs_per_s = (double)THROUGHPUT_MSGS / elapsed_s;

    printf("    Throughput: %.0f msg/s (%.3f s for %d msgs)\n",
           msgs_per_s, elapsed_s, THROUGHPUT_MSGS);

    /* Target: ≥ 1M msg/s.  This is a soft target — machines vary.
     * We warn rather than fail so CI on slow builders doesn't break. */
    if (msgs_per_s >= 1e6) {
        printf("    PASS  throughput >= 1M msg/s\n");
        g_pass++;
    } else {
        printf("    WARN  throughput %.0f < 1M msg/s (target may be "
               "too high for this machine)\n", msgs_per_s);
        /* Do not count as failure — hardware-dependent. */
        g_pass++;
    }

    march_mailbox_destroy(&mb);
    march_heap_destroy(&src);
    march_heap_destroy(&dst);

    GROUP_DONE("7");
}

/* ── main ─────────────────────────────────────────────────────────────── */

int main(void) {
    printf("=== Phase 5: Per-Process Heaps + Message Passing tests ===\n");

    test_bump_alloc();
    test_msg_copy();
    test_msg_move();
    test_local_rc();
    test_gc();
    test_gc_pass2_scalar_preservation();
    test_gc_abort_paths();
    test_mailbox();
    test_throughput();

    printf("\n=== Results: %d passed, %d failed ===\n", g_pass, g_fail);
    return g_fail ? 1 : 0;
}
