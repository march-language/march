# `[P2]` DONE rrb_vec and aho_corasick annotate `Array(a)` where the Array module returns `PVec(a)`

Filed 2026-09-22 from the stdlib internal-error sweep
(`2026-09-22-stdlib-internal-type-errors.md`). 30 errors: rrb_vec 19,
aho_corasick 11.

`stdlib/array.march` defines `ptype PVec(a) = PVec(Int, Int, TrieNode(a), List(a))`
and every `Array.*` function returns `PVec(a)`. Both callers instead write the
element type as `Array(a)`:

- `stdlib/rrb_vec.march:40`: `ptype Vec(a) = Vec(Array(a))`, so `Vec(Array.empty())`
  at :49 is "expected `Array(a1)` but got `PVec(b1)`", and so on through :255.
- `stdlib/aho_corasick.march:61`: `ptype Automaton = Automaton(Array(AcNode), Array(String))`,
  same mismatch at :282 through :387.

Decide first whether `Array(a)` is meant to be a public alias for `PVec(a)`
(then add the alias in array.march, which fixes both files at once and any user
code that copied the spelling) or whether both modules should just say
`PVec(a)`. Check what `Array`'s doc pages promise before choosing — the public
name users see matters more than the internal one.

## Resolution (2026-09-24): annotations changed to `Array.PVec(a)`; the alias was not possible

The owner-accepted plan was to make `Array(a)` a public alias for `PVec(a)` in
`stdlib/array.march`. It does not work, for a reason in the language rather
than in this module:

- **March has no type-alias syntax.** `Ast.TDAlias` exists and the typechecker
  honours it (`ty_aliases` in `lib/typecheck/typecheck_env.ml`), but the parser
  never builds one; the only aliases are generated (`@[endpoints]`'s `Entry`).
  `lib/refinecheck/refine_audit.ml`'s `walk_type_def` comment records the same
  thing. `type Array(a) = PVec(a)` parses as a new nominal variant with a
  constructor called `PVec`. Measured with a scratch module:
  `fn e(): Array(Int) do Array.empty() end` is "expected `Array(Int)` but got
  `PVec(j2)`". Worse, it would add a second `PVec` constructor to the flat
  constructor namespace.
- Even with a grammar for it, generated aliases register only under their
  qualified name (`Array.Array`), so the bare `Array(a)` the two files wrote
  would still not resolve without further typechecker work.

Adding alias syntax is a language change, outside this fix. The fallback:
both files now spell the type `Array.PVec(a)`. The bare `PVec(a)` does NOT
resolve from another module ("I cannot find `PVec`"), and the qualified
spelling unifies with what `Array.*` returns:

- `stdlib/rrb_vec.march`: `ptype Vec(a) = Vec(Array.PVec(a))`,
  `ptype Slice(a) = Slice(Array.PVec(a), Int, Int)`, and the public
  `from_array(xs : Array.PVec(a))` / `to_array(v) : Array.PVec(a)` (doc strings
  name the type).
- `stdlib/aho_corasick.march`: `ptype Automaton = Automaton(Array.PVec(AcNode), Array.PVec(String))`.

Public docs already call the type `PVec(a)` (`docs/stdlib.md`), so no user
documentation promised `Array(a)`.

Evidence:
- `march --check stdlib/rrb_vec.march`: 19 errors -> 0.
  `march --check stdlib/aho_corasick.march`: 11 -> 0.
- `test_stdlib_internal_errors_ratchet`: both rows removed.
- New `test_rrb_to_array_has_a_real_type_for_users` (test/test_compiler.ml): a
  user program annotating `Array.PVec(Int)` around `RRB.to_array` /
  `RRB.from_array` typechecks. Pre-fix the same program fails with "expected
  `PVec(Int)` but got `Array(Int)`" (run against origin/main's compiler and
  stdlib). A `String` annotation is still rejected, so the export's type did
  not become unconstrained.
- `march test test/stdlib/test_rrb_vec.march` (212 passed) and
  `test_aho_corasick.march` (170 passed); `test_stdlib_march.exe` groups
  `rrb_vec`, `aho_corasick` green.
