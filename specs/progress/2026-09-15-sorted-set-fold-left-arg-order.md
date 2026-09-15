# `SortedSet` set-builders called `List.fold_left` with the wrong argument order

Fixed 2026-09-15.

## Symptom

`SortedSet.from_list([5, 3, 9, 3, 1], icmp)` panicked at run time, compiled and
interpreted, with `non-exhaustive pattern match: no branch matched the value
{ cmp: <fn>, tree: Leaf }`. A standalone
`rm -rf .march/cas/artifacts-v2 && march --check stdlib/sorted_set.march`
reported 17 type errors.

## Cause

`from_list`, `union`, `intersect` and `difference` called
`List.fold_left(acc, list, fn s -> fn v -> ...)`. The real signature is
`fold_left(xs : List(a), acc : b, f : b -> a -> b)`, list first, and `b -> a -> b`
is an uncurried two-argument function (`fn (acc, x) -> ...`). The set record was
being matched as a list.

## Fix

`stdlib/sorted_set.march`: the four public functions now call
`List.fold_left(list, acc, fn (s, v) -> ...)`. The change is confined to those
four functions; the tree helpers are untouched (the set-refinements branch is
editing them).

## Tests

- New `test/stdlib/test_sorted_set.march` (11 tests: from_list dedup/sort,
  size, empty, member; union; intersect; difference incl. asymmetry and the
  empty case), registered in `test/test_stdlib_march.ml`, with
  `sorted_set.march` added to that runner's stdlib load list (it was absent, so
  the module was unbound there).
- Red control: with the pre-fix `sorted_set.march` swapped into the staged
  stdlib, `march test test/stdlib/test_sorted_set.march` fails 11/11 with the
  reported panic; with the fix, 11/11 pass.
- `--check stdlib/sorted_set.march`: 17 errors before, 0 after.
- A compiled `--compile` program exercising all four prints the same, correct
  results as the interpreter.
