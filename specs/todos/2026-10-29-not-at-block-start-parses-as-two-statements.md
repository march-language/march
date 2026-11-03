`[P1]` `else not p(n) end` parses as two block statements, `not` and `p(n)`, and returns `p(n)`.

Found while pinning probe r1 of `specs/2026-10-29-refinement-reflection-design.md` (§0.12;
`test/refine/reflect/r1_dom1.march`, and `--reflect-report` reports `p` as
`no R7:names not as a value`).

- `fn p(n : {Int | _ >= 0}) : Bool do if n >= 0 do true else not p(n) end end`: the `--emit-core-ast`
  of the else branch is `EBlock [EVar not; EApp (p, [n])]`. The branch's value is `p(n)`, not
  `not p(n)`, and the program typechecks with no diagnostic (the bare `not` is a discarded value).
- In expression position `not (n > 0)` is the `EApp (EVar not, [...])` of `parser.mly`'s `not`
  production, so the split happens only where a block body starts (after `else`, a match arm, `do`).
- The probe's measured certificate (`cert=metric`) is still right for the program as parsed; only its
  meaning differs from what was written. Writing `not(p(n))` gives the intended program.
- Fix in the parser / token filter (and `tree-sitter-march/grammar.js`), or at least warn on a bare
  function name as a non-final block statement.
