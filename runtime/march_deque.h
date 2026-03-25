#pragma once
/* march_deque.h — Chase-Lev work-stealing deque.
 *
 * Lock-free bounded deque for work-stealing schedulers.
 * The owner pushes/pops from the bottom (LIFO).
 * Stealers steal from the top (FIFO).
 *
 * Reference: Chase & Lev, "Dynamic Circular Work-Stealing Deque" (SPAA 2005).
 */

#include <stdint.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#define MARCH_DEQUE_CAPACITY 4096

typedef struct {
    void *_Atomic items[MARCH_DEQUE_CAPACITY];
    _Atomic int64_t top;
    _Atomic int64_t bottom;
} march_deque;

static inline void march_deque_init(march_deque *d) {
    memset(d->items, 0, sizeof(d->items));
    atomic_init(&d->top, 0);
    atomic_init(&d->bottom, 0);
}

/* Owner pushes to bottom. Returns 0 on success, -1 if full. */
static inline int march_deque_push(march_deque *d, void *item) {
    int64_t b = atomic_load_explicit(&d->bottom, memory_order_relaxed);
    int64_t t = atomic_load_explicit(&d->top, memory_order_acquire);
    if (b - t >= MARCH_DEQUE_CAPACITY) return -1;
    atomic_store_explicit(&d->items[b % MARCH_DEQUE_CAPACITY], item,
                          memory_order_relaxed);
    atomic_thread_fence(memory_order_release);
    atomic_store_explicit(&d->bottom, b + 1, memory_order_relaxed);
    return 0;
}

/* Owner pops from bottom. Returns item or NULL if empty. */
static inline void *march_deque_pop(march_deque *d) {
    int64_t b = atomic_load_explicit(&d->bottom, memory_order_relaxed) - 1;
    atomic_store_explicit(&d->bottom, b, memory_order_relaxed);
    atomic_thread_fence(memory_order_seq_cst);
    int64_t t = atomic_load_explicit(&d->top, memory_order_relaxed);

    if (t <= b) {
        void *item = atomic_load_explicit(&d->items[b % MARCH_DEQUE_CAPACITY],
                                          memory_order_relaxed);
        if (t == b) {
            if (!atomic_compare_exchange_strong_explicit(
                    &d->top, &t, t + 1,
                    memory_order_seq_cst, memory_order_relaxed)) {
                item = NULL;
            }
            atomic_store_explicit(&d->bottom, b + 1, memory_order_relaxed);
        }
        return item;
    } else {
        atomic_store_explicit(&d->bottom, b + 1, memory_order_relaxed);
        return NULL;
    }
}

/* Stealer takes from top. Returns item or NULL if empty. */
static inline void *march_deque_steal(march_deque *d) {
    int64_t t = atomic_load_explicit(&d->top, memory_order_acquire);
    atomic_thread_fence(memory_order_seq_cst);
    int64_t b = atomic_load_explicit(&d->bottom, memory_order_acquire);
    if (t >= b) return NULL;

    void *item = atomic_load_explicit(&d->items[t % MARCH_DEQUE_CAPACITY],
                                      memory_order_relaxed);
    if (!atomic_compare_exchange_strong_explicit(
            &d->top, &t, t + 1,
            memory_order_seq_cst, memory_order_relaxed)) {
        return NULL;
    }
    return item;
}
