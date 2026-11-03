# Portable closures at parallel boundaries — design

Item 3 of the OxCaml review (`specs/2026-09-03-allocation-contracts-design.md`,
Roadmap context). Decided 2026-10-07.

## What OxCaml does, and why March needs much less of it

OxCaml makes parallel code data-race free with modes: a closure passed to
`Parallel.fork_join2` must be `portable`, meaning it captures nothing
`uncontended`, and mutable fields of a `contended` value cannot be touched.
Types that cannot hold mutable state cross those checks through their kind
(`immutable_data`).

March already has most of that guarantee by construction. Checked
2026-10-07:

| Shared state | Why it cannot race today |
|---|---|
| Ordinary values | Immutable. |
| `NativeArray.set` | Copies when the array is shared (`native_int_arr_set`: in place only at rc == 1, acquire load). |
| Vault tables | Reader/writer locks (`runtime/march_extras.c`). |
| Reference counts | Atomic on the scheduler. |
| Linear / affine values | Cannot be captured by any closure: "The linear value `t` cannot be captured by a closure" (`typecheck.ml`, `check_captures`). |

The one remaining hole is a native **`resource`** handle. It is
reference-counted, not linear, so a closure can capture it, and the C library
behind it may not tolerate two threads calling into one handle.

I/O inside a parallel closure is **not** a hazard March should reject: the
parallelism docs recommend `List.pmap_n(urls, fn u -> http_get(u), 8)`.
OxCaml does not reject I/O in portable functions either.

## Rule

A closure passed to a **many-call** parallel combinator must not capture a
value whose type reaches a `resource`, directly or through data
(`Box(Acc, Int)`, `List(Acc)`) or through another closure it captures.

Many-call combinators, by closure position:

| Combinator | Closure parameter(s) |
|---|---|
| `List.pmap`, `List.pmap_n`, `List.pfilter` | `f` / `pred` |
| `List.preduce` | `combine` |
| `Parallel.pmap`, `Parallel.pmap_n`, `pcount`, `pany`, `pall` | `f` / `pred` |
| `Parallel.preduce`, `Parallel.preduce_n` | `f`, `merge` |
| `Task.async_stream`, `Task.async_stream_n` | `f` |

`task_spawn` and `Task.async` run their closure once. A task owning a handle it
was handed is a normal pattern, and since linear values cannot be captured
either, rejecting resources there would leave no way to hand a task a handle.
They are deliberately out of scope.

A user function that passes its closure parameter (or a closure capturing it)
to one of those positions becomes a parallel position itself, by fixpoint, so
`wrapper(xs, f) = List.pmap(xs, f)` is checked at `wrapper`'s call sites.

## Where it runs

On TIR right after Defun and the kind-table build, before `Hof_spec` clones
higher-order functions per lambda. At that point every closure is an explicit
`alloc $Clo_…(apply, captures…)` and each capture atom carries its
monomorphic type, so a generic function instantiated with a resource is
caught. The kind table gains a deep `resource_free` fact (no `resource`
reachable), computed by the same declaration-resolving walk as `closure_free`
and `float_free`; it is the table's first crossing fact with a reader.

A resource is recognised structurally: `resource X` desugars to a variant
with no constructors, which no other declaration can produce (the interpreter
relies on the same signal, `eval.ml`).

Diagnostics join the pipeline's contract diagnostics, so compiled builds and
the LSP report them and fail on them. `--check` lowers only when the program
has a `@[no_alloc]` obligation; the gate widens to "or declares a
`resource`" (no resource type, nothing to find). The interpreter runs tasks eagerly on one thread, so the hazard
does not exist there and nothing is checked.

Errors are reported at the enclosing named function (a lambda's closure is
traced back to the function that allocates it), naming the captured variable,
its type, and the combinator.

## Known gaps

A closure that reaches a parallel position through a data structure (stored
in a record, read back, then passed), returned from a call, or chosen by an
`if`/`match` is not traced. `--check` and the LSP lower only when the ENTRY
module declares a `resource`; a resource declared in a `MARCH_LIB_PATH`
dependency is checked by `--compile` but not by `--check`.

## Implementation notes (2026-10-07)

- `lib/tir/portable.ml`, called from `Contract_pipeline` after the `k0`
  kind-table build; code `portable_capture`.
- `Kind.reachable_has` does not descend into `TFn`: a function value holds
  none of its argument types, so a closure capturing `acc_push : (Acc, Int) ->
  Int` captures no handle.
- A capture slot naming a top-level function or extern is skipped by name. A
  zero-argument one is typed by its result in TIR (`acc_new : Acc`), so the
  type alone would flag `fn x -> finish(acc_new())`, the very fix the
  diagnostic recommends.
- Slots are `Param j` or `Cap k`: a lifted lambda reads its captures as
  `$clo.$fvK`, so a lambda that passes a captured closure to a parallel
  position makes its allocation (`alloc $Clo(apply, c1, …)`) a parallel use of
  `cK`. Aliases (`let k = g`) are followed.
- The top-level-name skip applies only to names the function does not bind
  itself, so a parameter `handle : Acc` shadowing a top-level `handle()` is
  still a capture.
- Combinators are matched on the whole callee name (`List.pmap` or
  `List.pmap$…`), not through `strip_specialization_suffix`, whose
  last-dot rule a dotted type suffix could defeat.
- Tests: `test/test_portable.ml` (11 rejects, 4 accepts; the accepts run
  compiled and interpreted) and `resource_free` in `test/test_kind.ml`. With
  the check disabled, the original 7 rejects fail; the first version of the
  pass missed the nested-lambda, alias and shadowing cases (a review found
  them).
- An extern referenced from inside a lambda does not link in native builds
  (undefined `@acc_push`), on main too; the accept tests call externs through
  March wrappers until that is fixed.
