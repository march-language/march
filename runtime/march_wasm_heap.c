/* Host-driven mark/sweep allocator for a single-threaded freestanding wasm32
 * module. Link it with march_runtime_wasm.c using MARCH_WASM_TRACING_HEAP. */
#include "march_wasm_heap.h"

#ifndef MARCH_WASM_HEAP_MAX_BYTES
#define MARCH_WASM_HEAP_MAX_BYTES (256u * 1024u * 1024u)
#endif

enum { PAGE_BYTES = 65536, ALIGNMENT = 8, BIN_COUNT = 32 };

_Static_assert(sizeof(uintptr_t) == 4, "March tracing heap requires wasm32");
_Static_assert(MARCH_WASM_HEAP_MAX_BYTES >= PAGE_BYTES &&
               MARCH_WASM_HEAP_MAX_BYTES <= UINT32_MAX &&
               MARCH_WASM_HEAP_MAX_BYTES % PAGE_BYTES == 0,
               "WASM heap limit must be a representable page multiple");

typedef enum { FREE, LIVE, MARKED } BlockState;

typedef struct Block {
    uint32_t size;
    BlockState state;
    struct Block *next; /* Free bin or tracing worklist. */
    struct Block *next_literal;
} Block;

_Static_assert(sizeof(Block) == 16, "March wasm32 heap header layout");

/* One bit per aligned address. Only allocated payload starts have set bits.
 * This filters arbitrary payload words before interpreting a block header. */
static unsigned char starts[MARCH_WASM_HEAP_MAX_BYTES / (ALIGNMENT * 8)];
static Block *free_bins[BIN_COUNT];
static Block *literal_roots;
static Block *pending;
static uintptr_t heap_base, heap_end, reserved_end;
static uint32_t live_bytes;

extern void *memset(void *dst, int byte, size_t count);

static unsigned start_mask(uintptr_t address) {
    return 1u << ((address / ALIGNMENT) % 8);
}

static void set_allocated(const Block *block, int allocated) {
    uintptr_t address = (uintptr_t)(block + 1);
    unsigned char *bits = &starts[address / (ALIGNMENT * 8)];
    if (allocated) *bits |= start_mask(address);
    else *bits &= ~start_mask(address);
}

static unsigned size_bin(uint32_t size) {
    return 31u - __builtin_clz(size);
}

static void insert_free(Block *block) {
    unsigned bin = size_bin(block->size);
    block->next = free_bins[bin];
    free_bins[bin] = block;
}

static Block *take_free(uint32_t size) {
    for (unsigned bin = size_bin(size); bin < BIN_COUNT; ++bin) {
        Block **slot = &free_bins[bin];
        while (*slot && (*slot)->size < size) slot = &(*slot)->next;
        if (*slot) {
            Block *block = *slot;
            *slot = block->next;
            return block;
        }
    }
    return NULL;
}

static Block *extend_heap(uint32_t size) {
    if (!heap_base) {
        size_t pages = __builtin_wasm_memory_size(0);
        if (pages == 0 || pages >= MARCH_WASM_HEAP_MAX_BYTES / PAGE_BYTES)
            __builtin_trap();
        heap_base = heap_end = reserved_end = pages * PAGE_BYTES;
    }
    uintptr_t span = sizeof(Block) + size;
    if (span > MARCH_WASM_HEAP_MAX_BYTES - heap_end) __builtin_trap();
    uintptr_t next = heap_end + span;
    if (next > reserved_end) {
        size_t pages = (next - reserved_end - 1) / PAGE_BYTES + 1;
        if (__builtin_wasm_memory_grow(0, pages) == (size_t)-1) __builtin_trap();
        reserved_end += pages * PAGE_BYTES;
    }
    Block *block = (Block *)heap_end;
    block->size = size;
    heap_end = next;
    return block;
}

void *march_alloc(int64_t bytes) {
    if (bytes < 0 || (uint64_t)bytes > MARCH_WASM_HEAP_MAX_BYTES - sizeof(Block))
        __builtin_trap();
    uint32_t size = bytes ? ((uint32_t)bytes + ALIGNMENT - 1) & ~(ALIGNMENT - 1u)
                          : ALIGNMENT;
    Block *block = take_free(size);
    if (!block) {
        block = extend_heap(size);
    } else if (block->size - size >= sizeof(Block) + ALIGNMENT) {
        Block *tail = (Block *)((unsigned char *)(block + 1) + size);
        tail->size = block->size - size - sizeof(Block);
        tail->state = FREE;
        insert_free(tail);
        block->size = size;
    }

    block->state = LIVE;
    set_allocated(block, 1);
    memset(block + 1, 0, block->size);
    return block + 1;
}

void march_wasm_heap_pin_literal(void *allocation) {
    Block *block = (Block *)allocation - 1;
    block->next_literal = literal_roots;
    literal_roots = block;
}

static void mark(Block *block) {
    if (block->state != LIVE) return;
    block->state = MARKED;
    block->next = pending;
    pending = block;
}

static void mark_candidate(uintptr_t address) {
    if (address < heap_base + sizeof(Block) || address >= heap_end ||
        address % ALIGNMENT != 0)
        return;
    if (starts[address / (ALIGNMENT * 8)] & start_mask(address))
        mark((Block *)address - 1);
}

static void sweep(void) {
    memset(free_bins, 0, sizeof free_bins);
    live_bytes = 0;
    Block *free_run = NULL;
    for (uintptr_t address = heap_base; address < heap_end;) {
        Block *block = (Block *)address;
        address += sizeof(Block) + block->size;
        if (block->state == MARKED) {
            if (free_run) insert_free(free_run);
            free_run = NULL;
            block->state = LIVE;
            live_bytes += block->size;
        } else {
            if (block->state == LIVE) set_allocated(block, 0);
            block->state = FREE;
            if (free_run) free_run->size += sizeof(Block) + block->size;
            else free_run = block;
        }
    }
    if (free_run) heap_end = (uintptr_t)free_run;
}

void march_wasm_heap_collect(void *const *roots, size_t count) {
    for (size_t i = 0; i < count; ++i) mark_candidate((uintptr_t)roots[i]);
    for (Block *block = literal_roots; block; block = block->next_literal) mark(block);
    while (pending) {
        Block *block = pending;
        pending = block->next;
        const unsigned char *data = (const unsigned char *)(block + 1);
        for (uint32_t offset = 0; offset < block->size; offset += sizeof(uintptr_t)) {
            uintptr_t candidate;
            __builtin_memcpy(&candidate, data + offset, sizeof candidate);
            mark_candidate(candidate);
        }
    }
    sweep();
}

uint32_t march_wasm_heap_live_bytes(void) {
    return live_bytes;
}
