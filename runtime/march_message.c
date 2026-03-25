/*
 * march_message.c — Cross-heap message copy and linear-type move.
 *
 * See march_message.h for design notes.
 */

#ifndef _XOPEN_SOURCE
#  define _XOPEN_SOURCE 700
#endif

#include "march_message.h"
#include "march_heap.h"
#include <stdlib.h>
#include <string.h>
#include <stdatomic.h>
#include <stdio.h>

/* ── march_hdr mirror (avoid circular include with march_runtime.h) ────── */
typedef struct { int64_t rc; int32_t tag; int32_t pad; } msg_hdr;

/* String layout: rc(8) + len(8) + data[len] (no trailing NUL required) */
typedef struct { int64_t rc; int64_t len; char data[]; } msg_string;

/* Tag value used to mark string objects (must match llvm_emit convention).
 * Strings use tag = -1 (0xFFFFFFFF as int32_t) as a sentinel. */
#define MARCH_STRING_TAG  (-1)

/* Values below one OS page are unboxed scalars (inttoptr-encoded integers). */
#define IS_HEAP_PTR(p)  ((uintptr_t)(p) >= 4096u)

/* ── Forwarding table (for deep copy of DAGs) ──────────────────────────── */
/*
 * We use a simple open-addressing hash table mapping src ptr → dst ptr.
 * This prevents exponential blowup on shared subgraphs and handles aliasing
 * correctly.  For the common case (tree-shaped messages, no sharing), the
 * table stays small.
 */

#define FWD_INITIAL_CAP  64

typedef struct {
    void *src;
    void *dst;
} fwd_entry;

typedef struct {
    fwd_entry *entries;
    size_t     cap;
    size_t     count;
} fwd_table;

static void fwd_init(fwd_table *t) {
    t->entries = (fwd_entry *)calloc(FWD_INITIAL_CAP, sizeof(fwd_entry));
    if (!t->entries) { fputs("march_msg_copy: OOM in fwd_table\n", stderr); exit(1); }
    t->cap   = FWD_INITIAL_CAP;
    t->count = 0;
}

static void fwd_destroy(fwd_table *t) {
    free(t->entries);
    t->entries = NULL;
}

static void *fwd_lookup(const fwd_table *t, void *src) {
    if (!t->count) return NULL;
    size_t h = (size_t)((uintptr_t)src * 2654435761u) & (t->cap - 1);
    for (size_t i = 0; i < t->cap; i++) {
        size_t idx = (h + i) & (t->cap - 1);
        if (!t->entries[idx].src) return NULL;
        if (t->entries[idx].src == src) return t->entries[idx].dst;
    }
    return NULL;
}

static void fwd_insert(fwd_table *t, void *src, void *dst) {
    /* Grow if >50% full. */
    if (t->count * 2 >= t->cap) {
        size_t new_cap = t->cap * 2;
        fwd_entry *new_entries = (fwd_entry *)calloc(new_cap, sizeof(fwd_entry));
        if (!new_entries) { fputs("march_msg_copy: OOM in fwd_table grow\n", stderr); exit(1); }
        for (size_t i = 0; i < t->cap; i++) {
            if (!t->entries[i].src) continue;
            size_t h = (size_t)((uintptr_t)t->entries[i].src * 2654435761u)
                       & (new_cap - 1);
            for (size_t j = 0; j < new_cap; j++) {
                size_t idx = (h + j) & (new_cap - 1);
                if (!new_entries[idx].src) {
                    new_entries[idx] = t->entries[i];
                    break;
                }
            }
        }
        free(t->entries);
        t->entries = new_entries;
        t->cap     = new_cap;
    }
    size_t h = (size_t)((uintptr_t)src * 2654435761u) & (t->cap - 1);
    for (size_t i = 0; i < t->cap; i++) {
        size_t idx = (h + i) & (t->cap - 1);
        if (!t->entries[idx].src) {
            t->entries[idx].src = src;
            t->entries[idx].dst = dst;
            t->count++;
            return;
        }
    }
    /* Should never reach here after grow. */
    abort();
}

/* ── copy_value (recursive) ────────────────────────────────────────────── */

static void *copy_value(march_heap_t *dst_heap, void *value, fwd_table *fwd);

static void *copy_string(march_heap_t *dst_heap, void *value) {
    msg_string *s = (msg_string *)value;
    /* Allocate: rc(8) + len(8) + data[len], 8-byte aligned. */
    size_t data_size = (size_t)s->len;
    size_t total_sz  = sizeof(int64_t) + sizeof(int64_t) + data_size;
    total_sz = (total_sz + 7u) & ~7u;
    /* Strings have their own layout — we allocate raw via march_process_alloc
     * using a size that fills the standard header (16 bytes) + extra.
     * We treat the string as an object with n_fields = (total_sz-16)/8
     * (may be 0 for short strings — the char data occupies the tail). */
    void *np = march_process_alloc(dst_heap, total_sz < 16 ? 16 : total_sz);
    /* Overwrite the standard header with string layout. */
    msg_string *ns = (msg_string *)np;
    ns->rc  = 1;
    ns->len = s->len;
    memcpy(ns->data, s->data, data_size);
    return ns;
}

static void *copy_value(march_heap_t *dst_heap, void *value, fwd_table *fwd) {
    if (!IS_HEAP_PTR(value)) return value;   /* unboxed scalar */
    if (!value) return NULL;

    /* Already copied? Return the forwarding pointer. */
    void *existing = fwd_lookup(fwd, value);
    if (existing) return existing;

    msg_hdr *h = (msg_hdr *)value;

    /* String objects have a different layout — detect by tag sentinel. */
    if (h->tag == MARCH_STRING_TAG) {
        void *ns = copy_string(dst_heap, value);
        fwd_insert(fwd, value, ns);
        return ns;
    }

    /* Recover field count from alloc_meta. */
    march_alloc_meta *meta = MARCH_ALLOC_META(value);
    uint32_t n_fields = meta->n_fields;
    size_t   obj_sz   = 16u + (size_t)n_fields * 8u;

    /* Allocate copy in dst_heap. */
    void *np = march_process_alloc(dst_heap, obj_sz);
    /* Copy header + fields. */
    memcpy(np, value, obj_sz);
    ((msg_hdr *)np)->rc = 1;   /* new object starts with rc=1 */

    /* Register forwarding pointer before recursing (handles cycles). */
    fwd_insert(fwd, value, np);

    /* Recursively copy pointer fields.
     * Fields start at offset 16.  We determine which fields are pointers
     * by checking whether the value passes IS_HEAP_PTR and points to a
     * plausible object (rc > 0).  This is conservative but safe for the
     * immutable-by-default March value model. */
    int64_t *fields = (int64_t *)((char *)np + 16);
    int64_t *src_fields = (int64_t *)((char *)value + 16);
    for (uint32_t i = 0; i < n_fields; i++) {
        void *fv = (void *)(uintptr_t)(uint64_t)src_fields[i];
        if (IS_HEAP_PTR(fv)) {
            /* Check if it plausibly looks like a heap object:
             * only recurse if the value has a meta header just before it
             * (i.e., was allocated via march_process_alloc).
             * We check the alloc_size field is non-zero as a sanity guard. */
            march_alloc_meta *fmeta = MARCH_ALLOC_META(fv);
            if (fmeta->alloc_size > 0 && fmeta->alloc_size < (1u << 24)) {
                void *copied_field = copy_value(dst_heap, fv, fwd);
                fields[i] = (int64_t)(uintptr_t)copied_field;
            }
        }
    }

    return np;
}

/* ── march_send_linear ─────────────────────────────────────────────────── */
/*
 * Forward declaration for the high-level actor send in march_runtime.c.
 * We use this to implement march_send_linear without a circular header dep.
 */
extern void *march_send(void *actor, void *msg);

void *march_send_linear(void *actor, void *msg) {
    /* Phase 5: the caller has transferred ownership (linear type guarantees
     * exactly one owner).  Currently we delegate to march_send which handles
     * the mailbox delivery.  Future integration with per-process heaps will
     * call march_msg_move here to update heap accounting before delivery. */
    return march_send(actor, msg);
}

/* ── march_msg_copy ────────────────────────────────────────────────────── */

void *march_msg_copy(march_heap_t *src_heap, march_heap_t *dst_heap,
                     void *value) {
    (void)src_heap;   /* not needed for the copy path */
    if (!IS_HEAP_PTR(value)) return value;

    fwd_table fwd;
    fwd_init(&fwd);
    void *result = copy_value(dst_heap, value, &fwd);
    fwd_destroy(&fwd);
    return result;
}

/* ── march_msg_move ────────────────────────────────────────────────────── */

void *march_msg_move(march_heap_t *src_heap, march_heap_t *dst_heap,
                     void *value) {
    if (!IS_HEAP_PTR(value)) return value;

    /* Recover size from alloc_meta. */
    march_alloc_meta *meta = MARCH_ALLOC_META(value);
    size_t alloc_size = meta->alloc_size;

    /* Update heap accounting: value logically moves from src to dst.
     * We only adjust live_bytes (not used_bytes — the memory stays in
     * src_heap's blocks until src_heap is destroyed or GC'd). */
    if (src_heap->live_bytes >= alloc_size)
        src_heap->live_bytes -= alloc_size;
    dst_heap->live_bytes += alloc_size;

    /* The pointer itself is unchanged — zero-copy. */
    return value;
}

/* ── MPSC Mailbox ──────────────────────────────────────────────────────── */

void march_mailbox_init(march_mailbox_t *mb) {
    atomic_store_explicit(&mb->inbox, NULL, memory_order_relaxed);
    mb->save_head = NULL;
    mb->save_tail = NULL;
    mb->pending   = NULL;
}

void march_mailbox_push(march_mailbox_t *mb, void *msg) {
    march_msg_node *node = (march_msg_node *)malloc(sizeof(march_msg_node));
    if (!node) { fputs("march_mailbox: OOM\n", stderr); exit(1); }
    node->msg  = msg;
    /* Lock-free push onto Treiber stack (inbox). */
    march_msg_node *old;
    do {
        old = atomic_load_explicit(&mb->inbox, memory_order_relaxed);
        node->next = old;
    } while (!atomic_compare_exchange_weak_explicit(
                  &mb->inbox, &old, node,
                  memory_order_release, memory_order_relaxed));
}

/* Reverse the inbox stack into the pending queue (delivery order). */
static void mailbox_flip(march_mailbox_t *mb) {
    /* Atomically take the whole inbox stack. */
    march_msg_node *stack = atomic_exchange_explicit(
        &mb->inbox, NULL, memory_order_acquire);
    /* Reverse it: inbox is LIFO; we want FIFO delivery. */
    while (stack) {
        march_msg_node *next = stack->next;
        stack->next  = mb->pending;
        mb->pending  = stack;
        stack        = next;
    }
}

void *march_mailbox_pop(march_mailbox_t *mb) {
    /* Selective receive: inbox (pending) is drained first; only when the
     * inbox is fully empty do we return previously saved messages.  This
     * matches the BEAM model where saved messages are re-examined after
     * all new messages have been tried, not before.
     *
     * Order:
     *   1. pending queue (already-flipped inbox, FIFO delivery order)
     *   2. flip inbox → pending, then deliver from pending
     *   3. only when pending is exhausted, drain save queue
     */

    /* 1. Check pending queue. */
    if (!mb->pending) mailbox_flip(mb);

    if (mb->pending) {
        march_msg_node *node = mb->pending;
        mb->pending = node->next;
        void *msg = node->msg;
        free(node);
        return msg;
    }

    /* 2. Inbox exhausted — return saved messages. */
    if (mb->save_head) {
        march_msg_node *node = mb->save_head;
        mb->save_head = node->next;
        if (!mb->save_head) mb->save_tail = NULL;
        void *msg = node->msg;
        free(node);
        return msg;
    }

    return NULL;
}

void march_mailbox_save(march_mailbox_t *mb, void *msg) {
    march_msg_node *node = (march_msg_node *)malloc(sizeof(march_msg_node));
    if (!node) { fputs("march_mailbox: OOM in save\n", stderr); exit(1); }
    node->msg  = msg;
    node->next = NULL;
    if (mb->save_tail) {
        mb->save_tail->next = node;
    } else {
        mb->save_head = node;
    }
    mb->save_tail = node;
}

size_t march_mailbox_count(march_mailbox_t *mb) {
    /* Count save queue. */
    size_t n = 0;
    for (march_msg_node *nd = mb->save_head; nd; nd = nd->next) n++;
    /* Count pending queue. */
    for (march_msg_node *nd = mb->pending; nd; nd = nd->next) n++;
    /* Count inbox (atomic read — may race but gives a snapshot). */
    march_msg_node *inbox = atomic_load_explicit(&mb->inbox, memory_order_relaxed);
    for (march_msg_node *nd = inbox; nd; nd = nd->next) n++;
    return n;
}

void march_mailbox_destroy(march_mailbox_t *mb) {
    /* Free save queue. */
    march_msg_node *nd = mb->save_head;
    while (nd) { march_msg_node *nx = nd->next; free(nd); nd = nx; }
    /* Free pending queue. */
    nd = mb->pending;
    while (nd) { march_msg_node *nx = nd->next; free(nd); nd = nx; }
    /* Take and free inbox stack. */
    nd = atomic_exchange_explicit(&mb->inbox, NULL, memory_order_acquire);
    while (nd) { march_msg_node *nx = nd->next; free(nd); nd = nx; }
    mb->save_head = mb->save_tail = mb->pending = NULL;
}
