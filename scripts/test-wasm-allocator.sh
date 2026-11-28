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
    "$clang" --target=wasm32-unknown-unknown -ffreestanding -nostdlib -O2 \
        -Wl,--no-entry -Wl,--export-memory "$@" \
        runtime/march_runtime_wasm.c "$scratch/probe.c" -o "$scratch/$output.wasm"
}
build default
build external -DMARCH_WASM_EXTERNAL_ALLOC

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
console.log('wasm32 default and linked allocator modes passed');
JS
