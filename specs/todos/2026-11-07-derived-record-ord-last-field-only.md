# Derived `Ord` on a record compares only the last field

**Logged:** 2026-11-07, found while fixing #1172
([2026-11-07-ord-operators-use-ord-impl.md](../progress/2026-11-07-ord-operators-use-ord-impl.md)).

`specs/lang/interfaces.md` documents derived `Ord` on a record as lexicographic
by field (declaration order). The derive (`Desugar_derive`, the `"Ord"` arm,
`TDRecord` case with two or more fields) builds the result with a
`List.fold_right` over the field list after `List.rev`, so the fold's outermost
step is the LAST field, which returns its own `_cmpN` outright; the earlier
fields' `if _cmpI != 0` tests end up nested in a branch that is never taken.
The result is just the last field's comparison, on every backend (interpreter,
native, JS all agree, so no golden test notices).

```march
type P2 = { a : Int, b : Int }
derive Eq, Ord for P2
compare({ a: 1, b: 9 }, { a: 2, b: 0 })   -- 1 today; documented order says -1
```

Fix: fold over the fields in declaration order (drop the `List.rev`), so the
first field's test is outermost and the last field is the innermost fallback;
delete the dead `result` / `final_cmp` bindings next to it. Add a golden case
where the fields disagree in direction, run on interpreter, native and JS.
Check `test/` and `stdlib/` for anything that relied on the current order
(e.g. a derived record used as a `Map` key or sorted with `compare`).
