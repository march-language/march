`[P0]` Compiled `NativeArray.get_*` / `set_*` do no bounds check — safe March code can read and write arbitrary heap memory

Filed 2026-08-20, found while building the deliberate-out-of-bounds RED proof for
the SIMD/NativeArray extension of the ASAN gate
(`specs/lang/golden/sanitize.sh`). The gate extension itself is green; this bug
is reachable only with an out-of-range index, which no fixture in the corpus
uses, so the sweep does not surface it on its own.

## The bug

Every `NativeArray` element accessor in the C runtime is a raw load/store with
no bounds check:

```c
/* runtime/march_runtime.c:7417 */
int64_t native_int_arr_get(void *arr, int64_t i) {
    return *(int64_t *)((char *)arr + NATIVE_ARR_HDR + i * 8);
}
```

The compiled backend calls these directly — `lib/tir/llvm_builtins.ml:631`
emits `declare i64 @native_int_arr_get(ptr %arr, i64 %i)` and nothing wraps it —
so an out-of-range index is an unchecked heap access from *safe* March code.

Affected (all five element families, both directions):

| function | runtime/march_runtime.c |
|---|---|
| `native_int_arr_get` / `_set` | 7417 / 7442 |
| `native_float_arr_get` / `_set` | 7629 / 7636 |
| `native_f32_arr_get` / `_set` | 7950 / 7955 |
| `native_i32_arr_get` / `_set` | via `DEF_NARROW_INT_ARR`, 7837 / 7840 (inst. 7933) |
| `native_u8_arr_get` / `_set` | via `DEF_NARROW_INT_ARR`, 7837 / 7840 (inst. 7934) |

`_set` is the worse half: its FBIP unique-ownership fast path stores straight
into `arr + NATIVE_ARR_HDR + i * sizeof(CTYPE)`, and its copy path stores into
the freshly allocated `new_arr` at the same unchecked offset.

## This contradicts both the docs and the interpreter

`stdlib/native_array.march` documents a panic on all five getters — lines 73,
138, 206, 266, 326: *"Return the element at index [i] (0-based). Panics if out
of bounds."*

The interpreter honours that. `lib/eval/eval.ml:8196` (int) and `:8584` (u8),
and the corresponding `_set` cases at `:8203` / `:8591`, all range-check and
`eval_error`. So this is an interpreter-vs-compiled divergence as well as a
memory-safety hole — and one the oracle sweep cannot see, because
`test/test_oracle.ml` compares programs that stay in range.

## Reproduction (verified 2026-08-20, arm64 Darwin, commit 92286289)

```march
mod Oob do
  needs IO.Console
  fn main(_cap_console : Cap(IO.Console)) : () do
    let a = NativeArray.make_u8(4, 7)
    println(NativeArray.get_u8(a, 0))
    println(NativeArray.get_u8(a, 1000000))   -- 1 MB past a 4-byte payload
    println("survived")
  end
end
```

Interpreted — correct:

```
7
native_u8_arr_get: index 1000000 out of bounds (len=4)
rc=1
```

Compiled — silent OOB read, program continues:

```
7
0
survived
rc=0
```

The write side, same shape (`NativeArray.set_u8(a, 64, 255)` on a 4-element
array — 60 bytes past the payload): interpreted panics with
`native_u8_arr_set: index 64 out of bounds (len=4)`; compiled prints
`OOB WRITE survived, no panic` and exits 0.

For contrast, `Bytes.get` *is* checked in compiled mode — the same program
using `Bytes.get(b, 999999)` dies with `panic: Bytes.get: index out of bounds`.
So this is specific to the `NativeArray` family, not a blanket policy of
unchecked indexing.

## The fix, and why it should be cheap

The runtime already has exactly the right helper, written for the boxed `Array`
family with a comment that states this bug's consequence in as many words:

```c
/* runtime/march_runtime.c:7020 — Index bounds check shared by get/set.
 * Aborts with a clear message rather than silently reading or writing
 * adjacent heap memory. */
static void typed_array_check_bounds(int64_t i, int64_t len) { ... }
```

`NativeArray` simply never got it. The straightforward fix is to call the same
check (or a `native_arr_` twin of it, reading the length from offset 16) at the
top of each `get`/`set`, and once inside the `DEF_NARROW_INT_ARR` macro to cover
`i32`/`u8` in one edit.

Open question worth deciding before implementing: whether the check belongs in
the runtime function (simple, correct, one branch per access) or should be
elided by codegen when the index is provably in range. `NativeArray` exists for
tight numeric loops, so a per-element branch in `get`/`set` is a real cost —
but note the bulk operations (`sum`, `map`, `map2`, `fold`, `to_list`) all
iterate `0..len` internally and would need no check at all, so the hot paths are
mostly unaffected. Correctness first: land the unconditional check, then measure
`bench/binary_trees.march` and `bench/list_ops.march` and optimise if it shows.

## Guard to add with the fix

Two panic fixtures under `test/native/`, modelled on the existing
`simd_bounds_panic.march` / `native_arr_map2_inline_length_panic.march` (which
assert a compiled binary's stderr): one for an out-of-range `get`, one for an
out-of-range `set`. Note these will be *excluded* from
`specs/lang/golden/sanitize.sh`'s curated native list by the same rule the
existing panic fixtures are — that gate asserts a zero exit — which is fine;
their coverage is the stderr diff in `test/dune`.
