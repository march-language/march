# Spec: NativeArray fold inline loop

**Date:** 2026-09-30
**Todo:** `specs/todos/2026-09-30-nativearray-fold-inline-loop.md`
**Parent plan:** `specs/plans/2026-09-28-nativearray-fusion-plan.md` (this is its
phase A, which ships on its own)
**Related:** `specs/plans/2026-09-30-float-closure-unboxing.md` reuses the unboxed
clone this spec adds; land this first.

## As built (2026-09-30)

The implementation is narrower than the design below in three places, each on
purpose:

- **Only scalar accumulators are inlined.** A fold takes the inline loop only
  when its callback is all-Float over a Float/f32 array (via the unboxed clone)
  or all-Int over an int/i32/u8 array. Every other fold (a String, record, tuple
  or generic accumulator, or an Int accumulator over a Float array) keeps the
  runtime path. The "boxed accumulator" inline path in the design was dropped:
  it would have had to reproduce `fold_release_prev_acc` for no measured need.
- **No Int clone.** Int folds call the ordinary apply fn through the tagged ptr
  ABI, like the Int map loop, and LLVM cancels the tag round trip after
  inlining. `is_all_int_signature` only gates eligibility.
- **Clone naming.** The Float clone reuses `unboxed_name_of`, so it is named
  `$mapfast$` rather than `$foldfast$`.
- **No builtin-table sites.** The synthetic `__native_<w>_arr_fold_inline(_unboxed)`
  names are created after Perceus and intercepted by the LLVM emitter before its
  general call path, exactly like the map names, so none of the nine builtin
  registration sites apply.

Code: `lib/tir/native_map_inline.ml` (`target_fold_names`, `fold_callback_kind`,
`find_target_call_fold`), `lib/tir/llvm_emit_nmap.ml`
(`decode_nfold_inline_call`, `emit_native_fold_inline_loop`), two dispatch arms
in `lib/tir/llvm_emit.ml`. Test: `test/native/native_arr_fold_inline.march`.

## Problem

`NativeArray.fold_*` is the one NativeArray higher-order operation with no inline
loop. It goes to a C loop in `runtime/march_runtime.c` (`native_int_arr_fold`,
`native_float_arr_fold`, and the f32/i32/u8 variants) that calls an opaque
closure per element through `call_closure_2`. For Float, every element is also
boxed (`march_alloc_float`) on the way in and the accumulator is boxed on the way
out.

Measured (2026-09-29, `bench/native_array_chains.march`, M3 Max, 4M elements):

| | ms | ns/element |
|---|---:|---:|
| `fold_float(a, 0.0, fn (s, x) -> s +. x *. 2.0)` | 187–188 | ~47 |
| `fold_int(a, 0, fn (s, x) -> s + x * 2)` | 8.4 | ~2.1 |
| inline `map_float` over the same array, for scale | 0.83 | ~0.2 |

## Goal

`fold_*` whose callback is a fresh single-use lambda compiles to a loop in the
caller's LLVM module that calls the callback's lifted function **directly**, so
LLVM can inline it. For concrete Float and Int signatures the loop carries the
accumulator in a register with no boxing. Every other fold keeps today's runtime
path unchanged.

Non-goals: fusion (parent plan, phase C); reassociating Float folds (strict order,
see "Semantics"); the REPL JIT and JS, which don't run `Native_map_inline`.

## Design

### Selection: `lib/tir/native_map_inline.ml`

Add a third target family beside `target_map_names` and `target_map2_names`:

```
target_fold_names = native_{int,float,f32,i32,u8}_arr_fold
```

Recognized shape (same bar as map and map2): the callback is a fresh closure,
used exactly once, as the fold's 3rd argument (`find_target_call*` /
`strip_alias_chain` walking past the `let f = clo` alias hop). Mind the argument
order: the stdlib wrapper `fold_int(arr, acc, f)` calls
`native_int_arr_fold(acc, arr, f)`, so the builtin's args are `(acc, arr, f)`.

Rewrite to synthetic names, following `inline_name_of`:

```
__native_<w>_arr_fold_inline            (acc, arr, apply_fn)          non-capturing
__native_<w>_arr_fold_inline            (acc, arr, apply_fn, clo)     capturing
__native_<w>_arr_fold_inline_unboxed    (same two shapes)             concrete signature
```

**Unboxed clone (`$foldfast$`).** Generalize `try_unboxed_variant`:

- Float widths (`float`, `f32`): the apply fn's params after `$clo` are
  `[TFloat; TFloat]` and it returns `TFloat`. That is `is_all_float_signature`
  unchanged, since it already checks "every param after the closure".
- Int widths (`int`, `i32`, `u8`): params `[TInt; TInt]`, returns `TInt`. Add an
  `is_all_int_signature` sibling. Int has no box, but the clone still drops the
  wire tagging at the boundary, which is what lets LLVM keep the accumulator in a
  register.
- Clone naming follows `unboxed_name_of`, with `$foldfast$` in place of
  `$mapfast$`. The clone's name must not contain `$apply$`, because
  `Tir_names.is_apply_fn` is what makes the emitter box.

Anything else (a generic `'a` accumulator, a record or tuple accumulator, a
String) takes the boxed inline loop: still a direct call, but through the erased
ptr ABI.

### Emission: `lib/tir/llvm_emit_nmap.ml`

Add `emit_native_fold_inline_loop` next to `emit_native_map2_inline_loop`,
dispatched from the same `llvm_emit.ml` arm that decodes `__native_*_inline`
names (`decode_nmap_inline_name` gains a fold flag).

Loop shape:

```
len = <w>_len_fn(arr)
acc0 = <entry accumulator>        unboxed: unbox Float / untag Int once
for i in 0..len:
  x   = load elem i               widen for f32/i32/u8 (nmap_widen)
  acc = call apply(clo_or_null, acc, x)     unboxed: raw double / raw i64
result = <re-box / re-tag acc>    once, after the loop
```

**RC contract.** Mirror the runtime loop exactly; the history here is the reason to
be careful (`specs/todos/2026-09-16-native-float-arr-fold-leaks-two-boxes-per-call.md`):

- `arr` is borrowed, as today (`borrow.ml` already lists the fold builtins).
- The closure: non-capturing means no closure and nothing to drop. Capturing means
  the loop owns one transferred reference and releases it once after the loop.
  The per-call `march_incrc(f)` in the C loop balances the callee's `$clo` drop, so
  the boxed inline path must reproduce that. The unboxed clone, like `$mapfast$`,
  is emitted as an ordinary function and does not drop `$clo`, so it needs no
  per-call increment. Confirm this against `$mapfast$`'s emitted IR before
  relying on it.
- The accumulator: unboxed paths have no RC at all (the entry box is released
  once after unboxing, the result is boxed once). The boxed path must implement
  `fold_release_prev_acc` exactly: release the previous accumulator only when it
  is a Float box and differs from the result.

### Builtin sites

Synthetic names are "builtins" to several tables. Walk the checklist in the
`project_new_builtin_nine_sites` memory, and mirror every place
`__native_float_arr_map2_inline` appears (`grep -rn map2_inline lib test`),
including `test/test_codegen.ml` and the REPL finalizers, even though the REPL
never emits these names.

## Semantics

- **Float order is strict** left to right, with no `reassoc`. The result is
  bit-identical to the runtime loop and to the interpreter.
- **Int** arithmetic keeps March's semantics: the clone body is the same TIR, so
  overflow behaviour is unchanged.
- **Panics** inside the callback happen at the same element and in the same order
  as today.
- Empty arrays return `acc` unchanged. The boxed path must not release it.

## Tests

- **Parity:** `test/native/native_arr_fold_inline.march`, covering 5 widths ×
  (non-capturing, capturing) × (unboxed, boxed accumulator), plus an empty array,
  one element, negative values, NaN and -0.0 for Float, and Int values near the
  overflow edge. Each case is compared with the interpreter.
- **Leak probe:** extend `test/native/native_arr_fold_acc_leak_probe.march` so its
  Float, String, identity and element-alias legs all run through the inline loop,
  and confirm they still hit the runtime path when forced off.
- **Structure:** an `--emit-llvm` check that the unboxed loop body has no
  `march_alloc_float` and no call to `native_*_arr_fold`. Remember the IR goes to
  `<source>.ll`, and that `--compile` on a warm cache writes no `.ll` at all.
- **Negative:** a fold whose callback is a parameter or is used twice stays on the
  runtime path.
- **ASAN** over the new fixtures. Accumulator ownership is exactly where earlier
  refcount changes hid use-after-free bugs that only ASAN found.
- **Oracle:** `scripts/ir-oracle.sh` shows byte-identical IR for every corpus
  program without a `fold_*` over a lambda literal.
- **Perturbation:** break the accumulator release on purpose and confirm the leak
  probe goes red.

## Benchmark and acceptance

Re-run `bench/native_array_chains.march` and `bench/array_numeric.march`, same box,
same binary build, inline path vs forced-off.

Accept when:
- the Float fold case drops at least 20×, and the Int fold case improves at all;
- no map, map2 or sum case regresses.

The expected Float result is about 1 to 2 ms (0.3 to 0.5 ns per element, since the
strict reduction won't vectorize), against about 188 ms today.

## Effort

About 1 to 2 days of agent work, bounded by ASAN runs and the leak probe, not by
writing code.
