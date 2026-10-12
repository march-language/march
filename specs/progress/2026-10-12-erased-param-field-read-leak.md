# A lambda that read a field of its erased parameter leaked the record

**Fixed** 2026-10-12. Found by the LSan pass of the native sanitizer sweep
(`scripts/native-sanitize-sweep.sh -l`): `closure_bool_field` reported nine
40-byte records allocated in `march_main` (one per row, per predicate that
reads a field). Listed under "one-shot, in `march_main`" in
`specs/todos/2026-10-12-lsan-sweep-remaining-leaks.md`, but it is per call.

## The bug

`run(Bx(Cons(fn r -> r.age > 28, Nil)), rows)` stores the lambda in a
container whose element type is hidden (`type Box = Bx(List(b))`), so the
lambda is never specialised and its parameter stays erased (`TVar`). The apply
fn owns its parameter (every closure caller hands it a reference), but:

- Perceus's ordinary machinery never drops a PARAMETER whose only uses are
  `EField` reads (no binding site, no case scrutinee);
- `insert_owned_aggregate_param_drops`, which exists for exactly that case,
  only took parameters whose type is a record or tuple;
- `insert_dead_apply_param_drops` fires only when the body never mentions the
  parameter.

So `fn r -> true` released its argument and `fn r -> r.age > 28` leaked it,
once per call.

## The fix

`insert_owned_aggregate_param_drops` also takes an erased parameter that the
body projects a field out of (only a record or tuple has fields). Its tail
rebinding now dups a bare projection out of a candidate before the drop:
`dup_field_results` does that for every typed record, but cannot type a
projection out of a `TVar`, so `fn r -> r.name` returned the field un-dup'd
and freed the record under it (an RC underflow on the first try).

An erased record is released by a generic `dec_rc`, which frees one cell, so
a heap field of a record the lambda frees still leaks; filed as
`specs/progress/2026-10-12-erased-record-shallow-release.md` (fixed the same day).

## Verification

- `test/native/erased_param_field_read_leak_probe.march`: 200 iterations of a
  field-reading predicate over fresh scalar rows: 600 leaked objects before,
  0 after. A shared list of rows with String fields, walked by three
  predicates and a field-returning lambda and then read again: 600 before, 0
  after, same totals as the interpreter.
- Linux arm64 ASAN error pass and LSan pass on the probe and
  `closure_bool_field`: clean (`closure_bool_field` no longer reports).
