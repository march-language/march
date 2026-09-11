# Large-operand interpolation is quadratic again — needs `string_concat_n` (FIXED, 2026-09-09)

**Filed 2026-07-27, closed 2026-09-09.** `string_concat_n` landed; interpolation
is linear at every operand size. Everything below the original text is the
closing record.


`fceea07b` removed the `string_join` cons-list path, so every interpolation now
desugars to a `++` chain folded into three-way `string_concat3` calls. That is
the right call for the common case — measured here with SHORT (8-byte)
operands, the concat3 chain beats `string_join` at *every* size tested, with no
crossover up to 20 operands:

| operands | chain | join |
|---|---|---|
| 2  | 30ms  | 59ms  |
| 5  | 77ms  | 108ms |
| 8  | 121ms | 157ms |
| 20 | 302ms | 350ms |

But `string_concat3` still re-copies the accumulated prefix at every step, so
with LARGE operands the single remaining shape is quadratic, and the join path
that used to cover that band is gone:

| operands | chain (4KB operands) | join (4KB operands) |
|---|---|---|
| 4  | 16ms   | 13ms |
| 8  | 87ms   | 23ms |
| 16 | 356ms  | 49ms |
| 32 | 1236ms | 97ms |

Restoring a count-based threshold would not fix this: the parser knows operand
COUNT but not operand SIZE, and these two tables disagree about the right
choice at the same count. The fix that removes the tradeoff entirely is a
length-summing **`string_concat_n`** — sum all parts once, allocate once, copy
once — which would dominate both shapes at every size with no cons cells.
Blocked on the constraint that forced the fixed-arity `string_concat3` fold in
the first place: March builtin signatures are `Mono (TArrow ...)` and cannot be
variadic, so this needs either a variadic builtin mechanism or a
spread-into-array calling shape.

---

## Fixed 2026-09-09

### The blocker, and how it was resolved

The open question was whether to add a **variadic builtin mechanism** or a
**spread-into-array calling shape**. It turned out not to be a choice between
them — the answer uses one at each level, for different reasons.

**Variadic at the type level.** A spread-into-array *surface* shape needs an
array literal that is cheap to build, and March has none: `TypedArray` is
constructed by `typed_array_from_list` (which needs the cons list this is
trying to avoid) or by `typed_array_new` plus N `set` calls. Passing a
`List(String)` is exactly the `string_join` path this file already measured at
roughly 2x slower with short operands. And every alternative still needs the
typechecker to accept an N-ary application, because the application rule is the
only place a call's arity is known. Given that cost is unavoidable, the array
buys nothing and adds an intermediate structure.

So `Typecheck_builtins.variadic_builtins` is a table of
`(name, arg_ty, ret_ty, min_arity)`, consulted from `Typecheck`'s application
rule. A table, not a hardcoded name in the inference core, so the next variadic
builtin is a data change.

**What that mechanism deliberately does NOT require.** The application is typed
at its *actual* arity, so `Lower`, `Mono` and `Defun` see an ordinary N-argument
builtin call. Nothing downstream needs a variadic notion. This is what kept the
change tractable, and it is the reusable part.

**Spread-into-array at the ABI level.** `march_string_concat_n` takes
`(int64_t n, void **parts)` and codegen spreads the operands into an
`alloca [N x ptr]` in the calling frame — no heap allocation for the spread,
following `Llvm_calls.emit_blocking_call`'s existing precedent. A C variadic
would have worked, but arm64 passes variadic arguments differently from fixed
ones, and one explicit ABI on every target is worth more than the syntax.

### The fold boundary is not a tuning knob

`Desugar.fold_concat3` now emits, by operand count: 1 → itself, 2 → `++`,
3 → `string_concat3`, 4+ → `string_concat_n`.

This file argued a count-based threshold cannot work, and that is right about a
threshold *between the chain and `string_join`* — the parser knows operand count
but not operand size, and the two tables above disagree at the same count. This
is a different decision. `string_concat_n` is linear at every size, so the count
is not choosing between a fast case and a slow case; 1, 2 and 3 operands are
each already exactly one allocation and one copy of every byte, which is
optimal, and the only question is whether an N-ary call could beat that. Below
4 it cannot.

### Measured

Same box, interleaved before/after, warmup discarded, compiled `--opt 2`, CAS
cleared between builds. Every pair printed byte-identical output. Median of
three rounds, in seconds.

Short operands (8 bytes, 300,000 iterations) — the case that motivated
`string_concat3` and the one at risk of being quietly lost:

| operands | before | after |
|---:|---:|---:|
| 2 | 0.04 | 0.04 |
| 4 | 0.06 | 0.05 |
| 8 | 0.08 | 0.05 |
| 16 | 0.13 | 0.06 |
| 32 | 0.23 | 0.07 |

Large operands (4 KB, 20,000 iterations) — the quadratic case this item is
about:

| operands | before | after |
|---:|---:|---:|
| 2 | 0.01 | 0.01 |
| 4 | 0.015 | 0.01 |
| 8 | 0.02 | 0.015 |
| 16 | 0.14 | 0.03 |
| 32 | 0.54 | 0.06 |

**The short case did not regress at any size** — it improved, which the
original tables did not predict but which follows once the mechanism is clear:
even short operands were paying one allocation per `concat3` link plus the
prefix re-copy, and the n-ary form pays one allocation total.

The "after" Large column is linear in operand count. The "before" column is
not: 8 → 16 → 32 multiplies by 7 and then by 3.9.

### The invisible failure, and the RED control that found it

`march_string_concat_n` **borrows** every operand. `Borrow.extern_borrow_table`
is a fixed-length bool list per name and `List.nth_opt` answers `None` — i.e.
NOT borrowed — past its end, so it cannot describe a variadic builtin at all.
Without a separate rule, Perceus treats the call as consuming its arguments and
emits no drop for them.

Measured with `Borrow.all_args_borrowed_builtins` removed, on a program making
3,000,000 five-operand `concat_n` calls:

| build | printed answer | peak RSS |
|---|---|---:|
| with the rule | 112555590 | 3.0 MB |
| without it | 112555590 | 195.8 MB |

Identical output, 64x the memory. **No golden that checks stdout can catch
this**, which is why it is pinned by a direct assertion on
`Borrow.is_extern_borrowed` in `test_codegen.ml` rather than by the native
golden.

### The `~H` escaping hazard, handled

This file's sibling risk: `Desugar.decompose_concat` identifies a template's
dynamic parts per operand, and a concat shape it cannot see through collapses
the whole template into ONE opaque part — which silently disables HTML
auto-escaping while the page still renders. That has happened twice before, once
for `string_join` and once when `concat3` folding was added.

`string_concat_n` is a third shape. Arms were added to both decomposers
(`Desugar.decompose_concat` and `Ctxesc.Scan_templates.decompose`), and a new
`~H` test asserts escaped output at an operand count that folds to the n-ary
form.

### Sites touched

Runtime C and JS (3 copies of `march_runtime.mjs`); `typecheck_builtins` (+`.mli`)
and the application rule in `typecheck`; `desugar` (fold and decomposer);
`ctxesc/scan_templates`; `eval_builtins`; `borrow`; `defun`; `alloc_contract`
(both the allocates and the retains classification); `js_emit`; `builtin_name`
(+`.mli`); `llvm_builtins` (declare + PDeclare); `llvm_emit` (the arm, plus a
new `Bg_string` group in the exhaustiveness surface). Tests: the byte-identical
preamble golden and the `Builtin_name` constructor count in `test_codegen.ml`,
three new interpolation cases in `test_eval.ml`, the borrow assertion, and a new
native golden.

### Deliberately out of scope

- The mechanism supports no fixed prefix parameters and no polymorphism. Both
  are straightforward to add to the table and neither has a caller.
- `string_join` is untouched; it still takes a `List(String)` and a separator,
  which is a different API with a different shape.
- The interpreter's `string_concat_n` uses `String.concat`, which is already
  linear; no interpreter measurement was taken because there was nothing to fix.
