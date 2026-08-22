# Fold helpers: a heap NON-Float accumulator is released too

Closes `specs/todos/2026-08-20-fold-heap-accumulator-borrowed-return-leak.md`
(this file is that item, moved). Filed 2026-08-20 as the residual PR #313
deliberately did not take; fixed 2026-08-22.

## What still leaked

`fold_release_prev_acc` released the previous accumulator only when it carried
`MARCH_FLOAT_TAG`, so a **String / List / record** accumulator threaded through
any of the five fold helpers leaked one heap object per element, unbounded in
array length.

## Why the runtime could not decide this alone

The original filing framed it as "an apply fn does not return an owned
reference", and that is true, but it is only half the reason. The half that
decides the fix is on the ARGUMENT side:

* Perceus's documented `ECallPtr` convention is that **the closure-apply ABI
  consumes its arguments** (perceus.ml's `ECallPtr` case, verbatim). An apply
  fn with an OWNING use of the accumulator — `fn (acc, x) -> Cons(x, acc)` —
  stores the caller's reference into its result with no `EIncRC`. Releasing
  `prev` there frees the tail of the list being built.
* An apply fn whose accumulator parameter has NO owning use —
  `fn (acc, x) -> int_to_string(x)`, `fn (acc, x) -> string_concat(acc, s)` —
  neither consumes nor retains it. The loop still holds the only reference and
  must release it, or it leaks.

Both shapes are ordinary March, the runtime sees the same `void *f` for each,
and no dynamic test separates them: a fresh result and a borrowed alias are
both just pointers, and `rc == 1` is equally consistent with "solely mine" and
"solely the array's". A Float escapes this because the uniform-ptr ABI makes
every Float-typed return provably a fresh box — `MARCH_FLOAT_TAG` is a witness
the runtime can read off the VALUE. There is no such intrinsic witness for a
String.

## The fix: the compiler supplies the missing witness

Borrow inference already computes exactly the needed fact. The new
`Borrow.first_user_arg_borrowed` asks it directly (`owned_in` against the
converged map, **not** `is_borrowed`: `infer_module`'s `init` seeds a parameter
as borrowed only when `Rc_types.borrow_eligible` accepts its type, so a param
typed `TVar "_"` — what Lower gives most lifted-lambda params — reads back as
"owned" from the map even when the fixpoint found no owning use. That
conflation is harmless inside Perceus and exactly wrong here).

The answer travels to the runtime through the closure OBJECT:

| | |
|---|---|
| `lib/tir/clo_flags.ml` | new cross-pass side table, `Dispatch_registry` pattern: `reset` at the start of `Perceus.perceus`, populated there from the borrow map, read lazily at LLVM-emission time |
| `lib/tir/llvm_emit.ml` | stamps `MARCH_CLO_ARG0_BORROWED` into the closure object's header **pad** word (offset 12) at five sites — the capture-free static lambda, the capturing heap alloc, and the three `$clo_wrap` interning sites for a top-level fn used as a value. NOT at those three sites' `else` branches (the per-materialisation `march_alloc(24)` trampolines the REPL and hot reload take): those keep pad 0 on purpose, see below |
| `runtime/march_runtime.h` | `MARCH_CLO_ARG0_BORROWED` |
| `runtime/march_runtime.c` | `fold_release_prev_acc` takes `f` and releases on either witness |

Why the pad word rather than a call-site-keyed channel: the flag has to travel
with the VALUE. `NativeArray.fold_int` is a March wrapper around the builtin,
so at the emission site of the actual runtime call the callback is a plain
parameter with no statically-known apply fn — a call-site channel would fix
only folds whose lambda is written inline and leave every stdlib wrapper
leaking. The pad word is otherwise unused for a closure (its record-shape-id,
actor-id and SIMD-kind uses are all per-tag and none of those tags is a
closure's), and `march_alloc` zeroes it.

**Every failure mode is the safe one.** A missing flag only costs the
pre-existing leak: closures built by a path that does not stamp — REPL/JIT
fragments, hot reload, the cross-heap message copier — fall back to the
Float-tag-only release. The table is consulted only to ENABLE a release, never
to suppress one.

### The element-alias guard

`march_typed_array_fold` needed one more thing, and it is unique to that helper:
its `elem` is a pointer the ARRAY owns (the int/i32/u8 helpers wire-tag an
immediate; the f64/f32 helpers box a fresh one and release it themselves). A
closure that hands the element straight back — `fn (acc, x) -> x`, whose
accumulator IS borrowed, so the release is live — returns a reference the loop
does not own. It now takes one (`result == elem && result != prev`), which also
makes the value it finally returns to its caller owned, as the convention
requires.

## Measurement

`test/native/native_arr_fold_acc_leak_probe.march`, Darwin arm64,
`--compile --opt 2`, same fixture both sides:

| build | `live_allocs()` delta |
|---|---|
| 8897bb1a (Float half already in) | **1,000,018** |
| with this fix | **20** |

1,000,000 = exactly one leaked String per element over the two 500,000-element
String legs. **stdout is byte-identical in both builds** — the `.expected` diff
cannot catch this defect, only the delta can, which is why the threshold rule
exists.

## Guards added

Four legs on the existing fixture (its header explains why each shape is
load-bearing, in the fixture rather than here):

* `string_acc_typed_leg` / `string_acc_native_int_leg` — leak direction, one
  per fold family, both with a **heap** accumulator. An Int accumulator is an
  immediate and cannot exhibit this leak at all; that is precisely how it hid.
* `elem_alias_leg` — `fn (_acc, x) -> x` over a TypedArray of Strings, reading
  an element AND the returned value after the fold. Faults or prints garbage if
  the element-alias guard is removed.
* `consume_acc_leg` — `fn (acc, x) -> Cons(x, acc)`, the shape where the callee
  really did take the reference and the release must NOT happen.

## Known conservativeness (deliberate, not a bug)

The bit is set only when borrow inference can SEE that there is no owning use,
so it is cleared whenever the accumulator is passed to a callee whose modes are
not declared. `borrow.ml`'s `extern_borrow_table` lists the March-level name
`string_byte_length` but not `string_length`, so
`fn (acc, x) -> int_to_string(string_length(acc) + x)` still leaks. Adding that
entry is correct and worth doing — it flips a parameter from owned to borrowed
for every caller in the tree, which is a wider blast radius than this fix and
wants its own measurement, so it was left out deliberately rather than bolted
on here. The fixture header says so at the leg it affects.

## Still open, unchanged by this

`march_typed_array_fold` passes its borrowed element into a parameter the
callee may treat as OWNED. `fn (acc, x) -> Pair(x, x)` therefore stores two
references to an element the loop was only lent — a pre-existing hazard on the
element side, untouched here (the fix above covers the alias-return case
because a returned element is pointer-identical; a STORED element is not). It
wants the same treatment: a second bit for "argument 1 is borrowed", or an
`incrc` before the call when it is not.

## Verification

* Probe RED 1,000,018 → GREEN 20 (numbers above, same fixture, both measured
  on this machine with a file-copy swap — no `git stash`).
* Three more materialisation paths checked by hand at 200,000 elements each,
  because the probe only exercises the lambda ones: a top-level fn passed
  directly (`$clo_wrap` trampoline) → delta 4; a closure returning a string
  LITERAL, which is an immortal static cell and must survive being "released"
  → delta 3, literal read again afterwards; a capturing closure (heap alloc
  site) → delta 4. All three would read ~200,000 unstamped.
* `scripts/run-tests.sh` all five suites green; `dune build @runtest` green;
  TIR snapshots unchanged (this is an emission-level change);
  `scripts/check-docs.sh` green.
* **The ASAN gate did not run.** `specs/lang/golden/sanitize.sh` exits 0 on this
  Mac having compiled 0 programs (CrowdStrike Falcon hangs every ASAN binary);
  that is a SKIP, not a pass, and an over-release is exactly what it would have
  caught. Substitute, not equivalent: the same 71-program corpus (47 golden + 24
  curated `test/native`) compiled and RUN without ASAN — 71 clean. That does
  catch an over-release that drives a refcount negative, since `march_decrc`
  aborts on underflow; it does not catch a use-after-free that reads
  still-mapped memory. Run the real gate on CI or `ci/Dockerfile.ubuntu`.
* Benchmarks, compiled `--opt 2`, interleaved before/after on the same box
  (which had 5 other March builds on it at load ~16, so these bound the change
  rather than resolving a few percent; first round discarded as warmup):
  `list_ops` 0.107s → 0.100s, `tree_transform` 0.680s → 0.680s.
