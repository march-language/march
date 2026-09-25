# `NativeArray.sort_float`: the f64 width of the ipnsort-style sort

Landed 2026-09-24. Design, i64 measurements and the widths still open (f32,
i32, u8): `specs/progress/2026-09-25-native-array-sort-narrow-widths.md`. The i64 width
this reuses: `specs/progress/2026-09-16-native-array-sort-int-ipnsort.md`.

## What landed

`NativeArray.sort_float` / `native_float_arr_sort` in `runtime/march_runtime.c`.
Doubles sort by their IEEE 754 `totalOrder` key

    key(bits) = bits ^ (((int64_t)bits >> 63) & 0x7FFFFFFFFFFFFFFF)

compared as a signed i64, which gives
`-NaN < -Inf < ... < -0.0 < +0.0 < ... < +Inf < +NaN`. `key` leaves the sign
bit alone, so it is an involution. `nsort_f64` rewrites each element to its key
in place, calls the unchanged `nsort_i64`, and rewrites the keys back. The same
network (`nsort_net8`), heapsort and pattern-breaking step are shared by both
widths. None of them were copied.

Ownership is the same as `native_int_arr_sort`: the argument is owned and
consumed, sorted in place at `rc == 1`, and copied, sorted, then released at
`rc > 1`. It is in `borrow.ml`'s `extern_owned_builtins`.

The interpreter arm (`lib/eval/eval_builtins.ml`) sorts on the same key:
`Int64.bits_of_float`, key, `Int64.compare`, key back, `Int64.float_of_bits`.

## Transform in/out versus comparing through the key

The todo left the choice to a measurement. Both were added to
`bench/c/native_sort_bench.c` (`nsb f64`). The keyed variant is the same ipn
algorithm with every `<` routed through `fkey`. Both are `memcmp`-identical
to `qsort` with a totalOrder comparator across 21 sizes × 9 patterns × 3 reps,
and the placement of the specials is also asserted directly. At 5M elements,
min of 3, ms:

| pattern | qsort (totalOrder) | qsort (naive `<`) | **xform** (shipped) | keyed | xform vs qsort | keyed / xform |
|---|---|---|---|---|---|---|
| random | 480 | 503 | **72.6** | 81.4 | 6.6x | 1.12 |
| sorted | 15.9 | 15.7 | **2.88** | 2.49 | 5.5x | 0.86 |
| reversed | 70.0 | 69.3 | **3.82** | 3.46 | 18.3x | 0.91 |
| nearly | 119 | 119 | **62.0** | 68.7 | 1.9x | 1.11 |
| dist10 | 64.1 | 68.1 | **11.8** | 11.4 | 5.5x | 0.97 |
| sawtooth | 112 | 115 | **42.6** | 46.5 | 2.6x | 1.09 |
| organ | 176 | 177 | **66.9** | 76.1 | 2.6x | 1.14 |
| equal | 7.0 | 7.0 | **2.78** | 2.49 | 2.5x | 0.89 |
| specials (~6% NaN/±Inf/±0) | 457 | — | **68.7** | 78.0 | 6.7x | 1.14 |

At n = 100,000 the ratios are the same (random 7.00 → 1.10 ms, reversed 1.39
→ 0.072 ms). **The measurements were taken with load average ~22–25 on the box**
from other sessions' builds. Absolute ms are loose; the ratios held steady
between a quick run and a full run.

Transform in/out won. Comparing through the key is 9–14% slower on every
pattern where comparisons dominate (random, organ, nearly, sawtooth, specials).
It is 9–14% faster only on the patterns that are already O(n) (sorted,
reversed, equal). There the two extra passes are most of the runtime, but the
absolute cost is a fraction of a millisecond per million elements. Transform
in/out also keeps a single copy of the algorithm.

The naive-`<` qsort column is there for scale only. It is no faster than the
totalOrder comparator, so correct NaN handling costs nothing at the baseline
either. It is not a valid sort on NaN data and is not run on `specials`.

## `-0.0` versus `Float` comparison elsewhere: a documented difference

This check was left open in the todo. Probed interpreted and compiled on
2026-09-24:

| expression | interpreter | compiled |
|---|---|---|
| `-0.0 == 0.0` | `true` | `true` |
| `-0.0 < 0.0` | `false` | `false` |
| `compare(-0.0, 0.0)` | `0` | `0` |
| `compare(nan, 1.0)` | `-1` | `0` |
| `compare(1.0, nan)` | `1` | `0` |

The stdlib has no `Float` module and no `Float.compare`, so the builtin
`compare` is the relevant semantics. It treats `-0.0` and `0.0` as **equal**.
`sort_float` puts `-0.0` strictly **before** `0.0`. This is kept on purpose,
because totalOrder has to distinguish every bit pattern to be a total order.
The difference is stated in `sort_float`'s doc string. `float_to_string`
renders the two differently (`-0.` / `0.`), so the difference is observable.

A pre-existing divergence turned up that this PR does not fix: on NaN, builtin
`compare` itself disagrees between the backends. The interpreter uses OCaml's
`Float.compare` (NaN below everything), while compiled `march_compare_float`
is `(x > y) - (x < y)`, which returns 0 against everything. `sort_float` does
not go through `compare`, so it is unaffected.

## Tests (red first)

`test/native/native_arr_sort.march` gained f64 cases: all eight patterns at the
13 sizes, on signed fractional doubles, checked against `List.sort_by`. It
also gained an explicit specials line
(`-nan -inf -1. -0. 0. 1. inf +nan`), a `+NaN sorts last` line, specials mixed
into arrays of 9 to 5000 elements (expected order built from each element's
KIND, not by comparing values), and the f64 aliasing case. Floats are compared
through string renderings, because `==` cannot see NaN or the sign of zero.
A NaN is not rendered with `float_to_string`: libc prints a sign-bit-set NaN
as `-nan` on glibc but `nan` on macOS, which made the golden platform-dependent
(first CI run: ubuntu failed, macOS passed). The fixture instead names each NaN
by its bit pattern through `hash()` (raw-bits hash on both backends), as
`-nan` / `+nan`, so both platforms print the same line and the sign of each
NaN is checked explicitly rather than only through its position.

`test/dune` now runs the file three ways against the one golden:

- compiled;
- compiled with `MARCH_TEST_NSORT_DEPTH_LIMIT=0`, a new runtime test hook
  (`nsort_forced_limit`) that replaces the depth limit, so every segment above
  32 elements goes to `nsort_heap`. The heapsort fallback had no direct test
  before. The pattern-breaking step makes it unreachable from input;
- interpreted.

Red evidence:

- **main**: the new file fails with `unbound variable: native_float_arr_sort`.
- **Interpreter parity**: with an interpreter arm using OCaml's
  `Array.sort compare`, three lines go red. `specials` gives
  `nan nan -inf -1. -0. 0. 1. inf` (both NaNs first), `nan last` gives
  `nan -1. 1.`, and `mixed specials` scores 2 of 5. After the switch to the
  key, all three runs match the golden.
- **Perturbation.** Two perturbations were applied at once. Their effects can
  be told apart. The runtime was restaged through the rule, and a `PERTURB`
  marker was grepped in `_build/default/runtime`.
  - `native_float_arr_sort` always sorts in place: the plain compiled run
    fails on exactly one line, `f64 alias original intact`.
  - `nsort_heap` is made a no-op: the plain run shows nothing else. The
    forced-heapsort run fails 12 more lines across both widths (dist10,
    sawtooth, organ, random and nearly for i64 and f64, plus `idempotent`
    and `f64 mixed specials`).

  Both runs went back to green once the perturbations were reverted.

## Sites touched

`runtime/march_runtime.c` (`nsort_forced_limit`, `nsort_f64_key`, `nsort_f64`,
`native_float_arr_sort`), `lib/typecheck/typecheck_builtins.ml`,
`lib/eval/eval_builtins.ml`, `lib/tir/llvm_builtins.ml` (the table row and
`PDeclare`), `lib/tir/defun.ml`, `lib/tir/borrow.ml` (`extern_owned_builtins`),
`lib/tir/alloc_contract.ml`, `stdlib/native_array.march`,
`test/test_codegen.ml` (preamble golden),
`test/snapshots/{lower,perceus}/array_read_tco_loop.expected` (fn count 62 →
63, plus the new wrapper), `test/dune`, `test/native/native_arr_sort.*`,
`bench/c/native_sort_bench.c`. `lib/tir/purity.ml` is unchanged, because
builtins not on its impure list are pure by default.

## Seen in passing, not fixed

In the JIT REPL, `NativeArray.to_list_float(...)` renders garbage
(`[2.46879e-313, ...]`) for any float array, whether or not it was sorted.
Scalar reads (`get_float`, `sum_float`) are correct. This is why the
`sort_float` doctest reads one element instead of printing the list. The
native_array doctests are not in the pure-REPL allowlist, so none of them run
in CI.
