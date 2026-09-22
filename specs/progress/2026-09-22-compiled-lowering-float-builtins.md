# Seven typechecked builtins now have compiled lowerings; a guard covers the class

**Landed 2026-09-22.** Closes the confirmed half of the todo filed 2026-09-13
(its original text is kept below the rule). The unconfirmed remainder of the
class moved to `specs/todos/2026-09-22-triage-interpreter-only-builtins.md`.

## What landed

- **`float_nan`, `float_infinity`, `float_neg_infinity`, `float_epsilon`**:
  inline LLVM double constants, emitted by new `Builtin_name` arms in
  `lib/tir/llvm_emit.ml` (next to `int_max_value`). The bits come from
  OCaml's own `Float.nan` / `Float.infinity` / `Float.neg_infinity` /
  `Float.epsilon`, which is exactly what the interpreter returns, so the two
  backends agree bit-for-bit. Note OCaml 5's `Float.nan` is
  `0x7FF8000000000001`, not the canonical `0x7FF8000000000000`; epsilon is
  `0x3CB0000000000000` (2^-52).
- **`float_is_nan`**: `fcmp uno x, x`; **`float_is_infinite`**:
  `fcmp oeq x, +inf` or `fcmp oeq x, -inf` (ordered, so NaN is false, as in
  OCaml). Both zext to an i64 0/1 Bool like the comparison operators. The
  operand is coerced to `double`, which unboxes a Float that crossed an
  erased slot (tested through `List.map` and a generic identity fn). No
  fast-math flags on either.
- The six are `Builtin_name` constructors, so `builtin_group` (Bg_arith) and
  both `Alloc_contract` classifiers (non-allocating, non-retaining) had to
  classify them; `test_codegen`'s constructor/arith counts went 58→64 / 16→22.
- **`typed_array_slice`**: `march_typed_array_slice` in
  `runtime/march_runtime.c` (table row + preamble declare in
  `lib/tir/llvm_builtins.ml`, header in `march_runtime.h`; the preamble golden
  in `test/test_codegen.ml` gained the declare line). It **copies** the range
  into a fresh array and `march_incrc`s each copied element. Bounds **clamp**
  exactly like `eval_builtins.ml`: `s = max 0 (min start alen)`,
  `e = max s (min (s + len) alen)`; nothing errors. `s + len` is computed
  without overflow in C (the interpreter's 63-bit ints wrap there, the only
  divergence, reachable only with `len` near max_int).
- **Borrow classification**: `("typed_array_slice", [true; false; false])` in
  `Borrow.extern_borrow_table`. The C neither stores nor frees the source
  array, and every TypedArray producer returns a fresh owned array, which
  are the two checks `specs/progress/2026-09-13-builtin-borrow-classification.md`
  requires. The rest of the typed-array family is still in the owned list,
  unaudited.
- **Guard**: `test/test_builtin_compiled_lowering.ml` (in `run_compiler`).
  Every name in `Typecheck_builtins.builtin_bindings` must be lowered by a
  codegen-table row, a `Builtin_name` constructor, the SIMD grid, a named
  `special_lowerings` route (short-circuit arms, lowering rewrites, prelude
  fns, `Lower_expr.interpreter_only_builtins`, same-named runtime C
  functions), or be listed in the test's `interpreter_only` allowlist (16
  names). The allowlist is also checked the other way: an entry that gains a
  lowering fails the test, so the list can only shrink.

## Verification

- **Red control**: `test/native/float_consts_typed_array_slice.march` compiled
  with the unchanged compiler failed at link:
  `Undefined symbols for architecture arm64: "_float_epsilon", "_float_infinity",
  "_float_is_infinite", "_float_is_nan", "_float_nan", "_float_neg_infinity",
  "_typed_array_slice"` / `march: clang failed (exit 1)`. After: it compiles, and
  the compiled output is byte-identical to the interpreter's (the `.expected`
  golden is the interpreter's output; dune rule
  `test/native_float_consts_typed_array_slice.out` + diff).
- **Borrow mutation**: with the `extern_borrow_table` entry removed the leak leg
  (10,000 slices of a fresh array) grew by exactly 10,000 objects and the golden
  printed `flat: false`. With it, the leak leg grew by 0.
- **Guard mutations**: adding an unlowered `zz_mutation_unlowered` binding to
  `builtin_bindings` failed the test (`1 typechecked builtin(s) have no compiled
  lowering: zz_mutation_unlowered`), and adding `float_nan` to `interpreter_only`
  failed the stale check (`Received: ["float_nan"]`).
- **Not observable, stated honestly**: removing the per-element `march_incrc`
  from `march_typed_array_slice` does NOT turn the golden red. TypedArray frees
  are shallow (`march_decrc` never walks slots) and the base reference of every
  element is never released under the current typed-array ownership, so no
  program can drive a sliced element to zero today. The incref keeps the slice
  correct under a future deep drop; the "slice outlives its source" leg guards
  the aliasing mistake (returning or sharing the source array), not the incref.
- The 7 remaining allowlisted names checked by hand (`char_is_alpha`,
  `char_to_uppercase`, `print_int`, `print_float`, `tap`, `respond`,
  `to_json`) each fail with `Undefined symbols: _<name>` when compiled.

---

# Builtins the typechecker accepts that a compiled program cannot link

Found 2026-09-13 while fixing `compare_string`
(`specs/progress/2026-09-13-compare-builtins-link-and-agree.md`). These run
interpreted and typecheck, but `--compile` fails at the link step with an
undefined symbol named after the builtin. No compiled lowering exists: no
`in_is_builtin` row in `lib/tir/llvm_builtins.ml`, no special case in the
emitter, and no C function in `runtime/`.

Each was confirmed by compiling a one-line call on `main` at `16e27ab1`:

| builtin | interpreted | compiled |
|---|---|---|
| `float_nan()` | `nan` | `_float_nan` undefined |
| `float_infinity()` | `inf` | `_float_infinity` undefined |
| `float_neg_infinity()` | `-inf` | `_float_neg_infinity` undefined |
| `float_epsilon()` | `2.22044604925e-16` | `_float_epsilon` undefined |
| `float_is_nan(x)` | works | `_float_is_nan` undefined |
| `float_is_infinite(x)` | works | `_float_is_infinite` undefined |
| `typed_array_slice(a, i, n)` | works | `_typed_array_slice` undefined |

The four constants and two predicates want inline LLVM (`0x7FF8000000000000`,
`fcmp uno`, and so on) or tiny C helpers. `typed_array_slice` wants a C
implementation. Mind element ownership, per
`specs/progress/2026-09-13-builtin-borrow-classification.md`: a slice that
shares elements must take a reference on each.

## The class, and the guard it needs

A static scan found 173 typechecker builtin names with none of: a compiled
row, a string literal naming them anywhere in `lib/tir`, or a stdlib `fn`. The
scan is noisy. SIMD builtins dispatch by name prefix, and network builtins may
be target-gated. So the list above is only what was **confirmed**.

The durable fix is a test in the shape of `test_cap_symbols.ml`. Every
`typecheck_builtins` entry must resolve through exactly one of: an
`in_is_builtin` row, a listed special lowering, or an explicit "interpreter
only" list that the driver rejects with a proper diagnostic instead of a
linker error. Candidates to triage first: the `logger_*` family,
`http_fetch`, `dns_resolve`, `ws_*`, `tap`, `to_json`, `try_finally`,
`uuid_v7`.
