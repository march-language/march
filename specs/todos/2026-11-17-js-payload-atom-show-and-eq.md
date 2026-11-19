`[P3]` - [ ] **JS target: `show`/`to_string` of an atom, and `==` on payload atoms.**

Filed 2026-11-17, found while fixing the native payload-atom match
(`specs/progress/2026-11-17-compiled-payload-atom-match.md`; matching now
agrees with the interpreter on `--target js`).

- `to_string(:ok)` (any atom) fails to compile for `--target js`: "builtin
  `atom_to_string` has no JavaScript-target implementation". A nullary atom is
  the JS string `":name"`. A payload atom is `{ $: "name", _0: … }` and should
  print `name(p, …)`, with payloads in repr form, as the interpreter does.
- `:a(1) == :a(1)` is `false` on JS (object identity) and `true` interpreted.
  The native fix is `march_atom_eq` (structural); JS needs the same comparison
  in `runtime/march_runtime.mjs`.

Repro: `if :a(1) == :a(1) do 1 else 0 end` prints 1 interpreted, 0 with
`--target js` under node.
