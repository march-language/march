#!/usr/bin/env bash
# Requires Node and a wasm32-capable Clang. Set MARCH_WASM_CLANG to choose Clang.
set -euo pipefail

cd "$(dirname "$0")/.."
clang=${MARCH_WASM_CLANG:-clang}
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

cat > "$scratch/probe.c" <<'C'
#include <stddef.h>
#include <stdint.h>

#ifdef MARCH_WASM_EXTERNAL_ALLOC
_Alignas(8) static unsigned char arena[256];
static size_t used;
static unsigned calls;

void *march_alloc(int64_t size) {
    if (size < 0 || (uint64_t)size > sizeof arena) __builtin_trap();
    size_t padded = ((size_t)size + 7) & ~(size_t)7;
    if (padded > sizeof arena - used) __builtin_trap();
    void *result = arena + used;
    used += padded;
    calls++;
    return result;
}

__attribute__((export_name("allocation_count")))
unsigned allocation_count(void) { return calls; }
#endif

void *march_string_lit(const char *text, int64_t len);
void *march_string_lit_static(const char *text, int64_t len, void **cell);
int64_t march_string_eq(void *a, void *b);

#ifdef MARCH_WASM_TRACING_HEAP
#include "march_wasm_heap.h"

void *march_string_concat(void *a, void *b);

__attribute__((export_name("allocate")))
void *allocate(int64_t bytes) { return march_alloc(bytes); }

__attribute__((export_name("collect")))
uint32_t collect(void *a, void *b) {
    void *roots[] = {a, b};
    if (a || b) march_wasm_heap_collect(roots, 2);
    else march_wasm_heap_collect(NULL, 0);
    return march_wasm_heap_live_bytes();
}

static void *literal_cell;
__attribute__((export_name("cached")))
void *cached(void) { return march_string_lit_static("March", 5, &literal_cell); }

__attribute__((export_name("join")))
void *join(void *a, void *b) { return march_string_concat(a, b); }

__attribute__((export_name("normalized")))
int normalized(void *s) {
    return march_string_eq(s, march_string_lit("MarchMarch", 10));
}
#endif

__attribute__((export_name("literal_probe")))
int literal_probe(void) {
    static void *cell;
    void *cached = march_string_lit_static("March", 5, &cell);
    return cached == march_string_lit_static("March", 5, &cell)
        && march_string_eq(cached, march_string_lit("March", 5));
}
C

build() {
    local output=$1
    shift
    "$clang" --target=wasm32-unknown-unknown -ffreestanding -nostdlib -O2 -Iruntime \
        -Wl,--no-entry -Wl,--export-memory "$@" \
        runtime/march_runtime_wasm.c "$scratch/probe.c" -o "$scratch/$output.wasm"
}
build default
build external -DMARCH_WASM_EXTERNAL_ALLOC
build tracing -DMARCH_WASM_TRACING_HEAP -DMARCH_WASM_HEAP_MAX_BYTES=1048576 \
    runtime/march_wasm_heap.c

node - "$scratch" <<'JS'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const root = process.argv[2];
function load(name) {
  return new WebAssembly.Instance(new WebAssembly.Module(fs.readFileSync(`${root}/${name}.wasm`))).exports;
}
const normal = load('default');
const defaultSize = normal.memory.buffer.byteLength;
assert.equal(normal.literal_probe(), 1);
assert.ok(normal.memory.buffer.byteLength > defaultSize, 'default bump allocator should grow linear memory');

const external = load('external');
const externalSize = external.memory.buffer.byteLength;
assert.equal(external.literal_probe(), 1);
assert.equal(external.allocation_count(), 2);
assert.equal(external.literal_probe(), 1);
assert.equal(external.allocation_count(), 3);
assert.equal(external.memory.buffer.byteLength, externalSize);
const heap = load('tracing');
const offset = heap.memory.buffer.byteLength;
assert.equal(heap.collect(0, 0), 0, 'collection before allocation is empty');
assert.throws(() => heap.allocate(-1n), WebAssembly.RuntimeError);
assert.throws(() => heap.allocate(1n << 32n), WebAssembly.RuntimeError);
const a = heap.allocate(64n);
const b = heap.allocate(64n);
const c = heap.allocate(32n);
const d = heap.allocate(0n);
assert.ok(a >= offset && [a, b, c, d].every(p => (p & 7) === 0));
const data = new DataView(heap.memory.buffer);
data.setUint32(a + 4, d, true); // pointer at a 4-byte field boundary
data.setUint32(d, a, true);     // cycle
new Uint8Array(heap.memory.buffer, b, 64).fill(0xaa);
new Uint8Array(heap.memory.buffer, c, 32).fill(0xbb);
assert.equal(heap.collect(a, 0), 72, 'keeps a reachable cycle');
assert.equal(heap.allocate(112n), b, 'reuses adjacent unreachable blocks');
assert.ok(new Uint8Array(heap.memory.buffer, b, 112).every(byte => byte === 0));
assert.equal(heap.collect(a, b), 184, 'keeps both roots');
assert.equal(heap.collect(a, c), 72, 'drops a removed root and ignores the absorbed start');
assert.equal(heap.allocate(32n), b, 'splits a larger free block');
assert.equal(heap.allocate(64n), b + 48, 'reuses the split remainder');
assert.equal(heap.collect(b + 8, 0), 0, 'ignores interior candidates');
assert.equal(heap.allocate(8n), a, 'reuses the dropped tail');

const literal = heap.cached();
const joined = heap.join(literal, literal);
const retained = heap.collect(joined, 0);
assert.ok(retained > 32, 'keeps a reachable String and its data buffer');
const pages = heap.memory.buffer.byteLength;
for (let i = 0; i < 512; ++i) {
  heap.allocate(8192n);
  assert.equal(heap.collect(joined, 0), retained);
}
assert.equal(heap.memory.buffer.byteLength, pages, 'bounded steady state');
assert.equal(heap.normalized(joined), 1);
assert.equal(heap.collect(0, 0), 32, 'literal survives without an embedder root');
assert.equal(heap.cached(), literal, 'reuses the same literal cache cell');
assert.equal(heap.normalized(heap.join(literal, literal)), 1);

assert.throws(() => heap.allocate(1048576n), WebAssembly.RuntimeError);
assert.throws(() => heap.allocate(BigInt(1048576 - offset)), WebAssembly.RuntimeError);
const bounded = load('tracing');
const nearLimit = BigInt(1048576 - bounded.memory.buffer.byteLength - 64);
const large = bounded.allocate(nearLimit);
assert.equal(bounded.memory.buffer.byteLength, 1048576, 'can grow up to the configured limit');
assert.throws(() => bounded.allocate(64n), WebAssembly.RuntimeError);
assert.equal(bounded.collect(0, 0), 0, 'can collect after an allocation trap');
assert.equal(bounded.allocate(nearLimit), large, 'reuses memory at the limit');
console.log('wasm32 default, linked allocator, and tracing heap modes passed');
JS
