#pragma once
/*
 * march_message.h — Cross-heap message copy and linear-type move.
 *
 * March actors use share-nothing heaps.  When a process sends a message to
 * another process, the value must cross heap boundaries.  Two operations:
 *
 *  march_msg_copy(src_heap, dst_heap, value)
 *    Deep-copy value (and all values it transitively references) from
 *    src_heap into dst_heap.  Returns a pointer to the new copy.
 *    Used for non-linear (unrestricted) values.
 *
 *  march_msg_move(src_heap, dst_heap, value)
 *    Zero-copy ownership transfer for linear values.  The value was
 *    allocated in src_heap but ownership is transferred to dst_heap.
 *    No data is copied; only the heap's accounting is updated.
 *    Returns the original pointer (same address, different owner).
 *
 * Design notes:
 *  - march_msg_copy handles nested structures recursively.
 *  - To detect already-copied objects (DAG sharing), a simple hash-table
 *    forwarding map is maintained during each copy operation.
 *  - march_msg_move just adjusts live_bytes on both heaps and returns the
 *    pointer unchanged.  The caller must ensure no further references to
 *    the moved value exist on src_heap (the linear type system guarantees
 *    this at the language level).
 */

#ifndef _XOPEN_SOURCE
#  define _XOPEN_SOURCE 700
#endif

#include <stdint.h>
#include <stddef.h>
#include "march_heap.h"

/* ── Public API ────────────────────────────────────────────────────────── */

/*
 * Deep-copy a heap value (and all transitively referenced values) from
 * src_heap into dst_heap.  The original value in src_heap is unchanged.
 *
 * Returns the new copy allocated in dst_heap.
 *
 * Behaviour for special values:
 *  - NULL          → returns NULL
 *  - Integer/bool  → the value is passed as an unboxed integer (inttoptr);
 *                    values below 4096 are returned unchanged (not heap ptrs)
 *  - Strings       → copied as raw bytes (the string layout is different
 *                    from the standard march_hdr layout — handled specially)
 *  - Cycles        → not possible in immutable-by-default March (values form
 *                    DAGs), but we defend with a visited set anyway.
 */
void *march_msg_copy(march_heap_t *src_heap, march_heap_t *dst_heap,
                     void *value);

/*
 * Zero-copy ownership transfer of a linear value between heaps.
 *
 * The value was allocated in src_heap.  After this call:
 *  - src_heap.live_bytes is decremented by the value's allocation size
 *  - dst_heap.live_bytes is incremented by the same amount
 *  - The pointer itself is unchanged (same address, now logically owned by
 *    dst_heap)
 *
 * Returns value (unchanged pointer).
 *
 * The caller is responsible for ensuring:
 *  1. No remaining references to value remain in src_heap after the move
 *     (guaranteed by the March linear type system at compile time).
 *  2. src_heap and dst_heap are accessed only by their respective processes
 *     (no cross-thread races).
 *
 * For NULL or non-heap-pointer values, this is a no-op that returns value.
 */
void *march_msg_move(march_heap_t *src_heap, march_heap_t *dst_heap,
                     void *value);

/*
 * march_send_linear — Send a linear (affine) message to an actor.
 *
 * This is the zero-copy counterpart to the default march_send.  The caller
 * guarantees that the message is a linear value (exactly one owner, which is
 * being transferred to the recipient).  The compiler emits this instead of
 * march_send when the message argument has v_lin = Lin in the TIR.
 *
 * In Phase 5 the implementation delegates to march_send after updating heap
 * accounting to reflect the ownership transfer.  A future phase will integrate
 * this with the green-thread scheduler's per-process heap pointers to perform
 * the transfer entirely in process-local memory without acquiring any locks.
 *
 * Declared here (defined in march_message.c) so that march_runtime.h is not
 * required — the LLVM-emitted code only needs this header.
 */
void *march_send_linear(void *actor, void *msg);

/* ── MPSC Mailbox with selective receive ───────────────────────────────── */

/*
 * march_mailbox_t — per-process MPSC mailbox.
 *
 * Messages are enqueued by senders (multiple producers) using an atomic
 * Treiber-stack style push.  The owning process dequeues them.
 *
 * Selective receive is supported via a "save pointer": when the process
 * examines a message and decides to skip it (because it doesn't match the
 * current receive pattern), the message is moved to the save queue.  On
 * the next receive call, already-saved messages are checked first before
 * pulling from the inbox.
 *
 * Invariants:
 *  - Producers push to inbox atomically (lock-free).
 *  - Consumer pops from save_head first, then inbox.
 *  - Consumer is always the owning process — no lock needed for dequeue.
 */

typedef struct march_msg_node {
    void                  *msg;
    struct march_msg_node *next;
} march_msg_node;

typedef struct {
    /* Inbox: producers push here (atomic). */
    _Atomic(march_msg_node *) inbox;

    /* Save queue: messages skipped by selective receive. */
    march_msg_node *save_head;
    march_msg_node *save_tail;

    /* Pending queue: reversed inbox, in delivery order. */
    march_msg_node *pending;
} march_mailbox_t;

/* Initialise a mailbox.  Must be called once before use. */
void   march_mailbox_init(march_mailbox_t *mb);

/* Push a message into the mailbox.  Safe to call from any thread. */
void   march_mailbox_push(march_mailbox_t *mb, void *msg);

/*
 * Pop the next message for the owning process.
 * Checks save_head first, then flips the inbox stack into delivery order.
 * Returns NULL if no messages are available.
 * NOT thread-safe for the producer side — only the owner may call this.
 */
void  *march_mailbox_pop(march_mailbox_t *mb);

/*
 * Save a message for later (selective receive).
 * The message is moved from the current delivery position to save_tail.
 * The next march_mailbox_pop will check save_head first.
 */
void   march_mailbox_save(march_mailbox_t *mb, void *msg);

/* Return the number of messages currently available (save + pending + inbox). */
size_t march_mailbox_count(march_mailbox_t *mb);

/* Free all nodes in the mailbox (does NOT free the msg payloads). */
void   march_mailbox_destroy(march_mailbox_t *mb);
