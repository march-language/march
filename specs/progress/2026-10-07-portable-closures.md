# DONE 2026-10-07: portable closures at parallel boundaries

Item 3 of the OxCaml review. Design: `specs/2026-10-07-portable-closures-design.md`.

## What landed

- **`lib/tir/portable.ml`**: a closure passed to a many-call parallel
  combinator (`List.pmap`/`pmap_n`/`pfilter`/`preduce`, the `Parallel.*`
  family, `Task.async_stream`/`_n`) may not capture a value whose type reaches
  a `resource`, directly, through data (`Box(Acc, Int)`, `List(Acc)`), or
  through another closure it captures. User functions that forward a closure
  parameter to such a position become parallel positions themselves
  (fixpoint), so `wrapper(xs, f) = List.pmap(xs, f)` is checked at its call
  sites. Runs on TIR after Defun, so generic code is checked per instance.
  Reported at the enclosing named function as `portable_capture`, naming the
  variable, its type and the combinator (and the wrapper path).
- **`Kind.resource_free`** (+ `Kind.is_resource_name`): the table's deep
  "no resource reachable" fact. `reachable_has` no longer descends into `TFn`.
- **`--check` gate**: lowers when the program has a `@[no_alloc]` obligation
  or declares a `resource`.
- `task_spawn` / `Task.async` (one call) and I/O stay allowed, by decision.

## Tests

- `test/test_portable.ml` (`run_compiler`, group `portable_closures`): direct,
  through data, through a wrapper, inside a lambda, through a captured
  closure, a generic instance, `Task.async_stream`, a closure captured by a
  lambda that runs it in parallel, an alias, a parameter shadowing a
  top-level function, and a combinator specialised over a nested-module type
  are rejected; a per-task handle, a zero-argument extern, sequential
  `List.map`, and `task_spawn` are accepted, run compiled and interpreted.
  Disabling the check turns the rejects red; the pass's first version missed
  the nested-lambda, alias and shadowing cases.
- `test/test_kind.ml`: `resource_free`.

## Known gaps

A closure reaching a parallel position through a data structure, a call's
result, or an `if`/`match` is not traced; `--check` gates on a `resource` in
the entry module only. See the design doc.

## Found on the way

An extern referenced from inside a lambda fails to link natively (`use of
undefined value '@acc_push'`), on main too. Filed as a separate task; the
accept tests route extern calls through March wrappers meanwhile.
