# `[P2]` rrb_vec and aho_corasick annotate `Array(a)` where the Array module returns `PVec(a)`

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
