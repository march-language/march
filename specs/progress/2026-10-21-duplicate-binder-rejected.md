`[P2]` A parameter list that binds one name twice means different things interpreted and compiled

Filed 2026-10-21 by the multi-arg review fixes
(`specs/progress/2026-10-21-abstract-multiarg-review-fixes.md`, finding C3). The
typechecker accepts a parameter list that names one binder twice, and the two
backends disagree about which argument the body's name is:

```march
mod Dup do
  needs IO.Console
  fn two(a : Int, a : Int) : Int do a end
  fn main(_c : Cap(IO.Console)) : () do
    let h = fn (a, a) -> a
    println(int_to_string(h(1, 2)))     -- interpreter 1, compiled 2
    let g = fn a -> fn a -> a
    let g1 = g(1)
    println(int_to_string(g1(2)))       -- 2 in both (the inner `a` shadows)
    println(int_to_string(two(1, 2)))   -- interpreter 1, compiled 2
  end
end
```

Measured 2026-10-21 at `591160909`: `march dup.march` prints `1 2 1`; `march
--compile -o dupc dup.march && ./dupc` prints `2 2 2`.

The refinement checker no longer reads such a list as a predicate or a
postcondition (it declines: `abstract-refinement-uninstantiated` "binds `x` twice",
and `postcond_of_declared` lends no fact for a relational return naming a doubled
formal), so no proof depends on either answer. The language should pick one: most
likely a hard error, "`a` is bound twice in this parameter list", at least for an
uncurried list (a curried chain's shadowing is ordinary lexical scope). Then the
checker's declines become unreachable for the uncurried case.

## Resolution (2026-10-22): rejected as `duplicate_binder`

**Status: DONE.** A name bound twice in ONE binding position is a typecheck
error, code `duplicate_binder` (`lib/errors/code.ml`), reported at the second
binder with a "first bound here" label at the first. `_` is exempt. Curried
lambdas, a lambda or match arm rebinding an enclosing name, and the
alternatives of an or-pattern (which must bind the same names) are separate
binding positions and stay legal.

### Divergence before the fix

Measured at `310531948` (origin/main) with `scripts/triage.sh` (private HOME,
`--opt 2`) on one program covering every shape; "no optional switch fixes it"
(`MARCH_NO_UNBOX`, `MARCH_NO_HOF_SPEC`, `MARCH_NO_INLINE_RC`, `--no-opt` all
still differ), so it is not an optimiser bug but the two backends' binding
order:

| shape | call | interpreter | compiled |
|---|---|---|---|
| `fn (a, a) -> a` | `h(1, 2)` | 1 | 2 |
| curried `fn a -> fn a -> a` | `g(1)(2)` | 2 | 2 (agree) |
| top-level `fn two(a : Int, a : Int)` | `two(1, 2)` | 1 | 2 |
| multi-clause `fn mc(0, a, a)` / `fn mc(_, a, a) … a + 100` | `mc(0, 1, 2)` | 2 | 1 |
| same, second head | `mc(5, 1, 2)` | 102 | 101 |
| `match (1, 2) do (a, a) -> a end` | | 2 | 1 |
| `let (b, b) = (3, 4)` | | 4 | 4 (agree) |
| `match Pair(5, 6) do Pair(x, x) -> x end` | | 6 | 5 |

So the interpreter takes the FIRST binder for a parameter list but the LAST for
a pattern, and compiled code does the opposite in each case (observed
behaviour; the mechanism was not traced, since the fix removes the program). Six of eight shapes
diverged; `let (b, b)` happened to agree and curried shadowing agrees by design.

### What was done

- `lib/typecheck/typecheck.ml`: `pattern_binders`, `report_duplicate_binders`
  and three entry points. `infer_pattern` checks each tuple / constructor /
  atom / record / `as` node across its immediate sub-patterns (a repeat inside
  one sub-pattern is that sub-pattern's own report, so each repeat is reported
  once). Parameter lists are checked in `bind_lam_params` (infer-mode lambdas
  and both local-`fn` paths), the check-mode `ELam` arm, `check_fn`'s clause
  parameters, actor `init` parameters and actor handler parameters. A
  multi-head function's heads reach the pattern check through desugar's merged
  `match` (each head becomes one tuple pattern). Errors that are re-derived
  (check-mode falling back to infer-mode) are dropped by `Errors.report`'s
  exact-repeat dedup.
- Explain page `specs/lang/errors/duplicate_binder.md`; the rule in
  `specs/lang/pattern-matching.md` (Wildcards and Variables); both regenerated
  into `docs/` by `scripts/gen-lang-docs.py`.
- Golden corpus `test/errors/duplicate_binder_{1..6}` (lambda, named fn,
  multi-head, match tuple, constructor, let tuple); `_1` is the explain page's
  program, the rest carry `-- EXPECT-ERROR:`. RED before the fix: `_1`
  "expected missing", `_2`..`_6` "the rendered output no longer contains its
  EXPECT-ERROR fragment".
- `test/test_compiler.ml` group `duplicate_binder`: the exact (line, col) of
  every report for nine reject shapes (including `as x` over an inner `x`, a
  local `fn g(a, a)`, and a triple `(a, a, a)` reporting both repeats), and five
  accept shapes with zero diagnostics. RED with the reporter disabled ("Expected
  `[(5, 19)]` Received `[]`").
- `test/test_codegen.ml` group `duplicate_binder`: an interp-vs-compiled
  parity control for the forms that stay legal (curried shadowing, a lambda
  shadowing a let, a match arm rebinding a parameter, `fn (_, _)`, an
  or-pattern binding `a` in both alternatives). Green before and after.

### Existing uses

None. `march --check` over every `.march` under stdlib/, test/ (incl.
test/native), specs/, examples/, bench/, forge/, lsp/, tree-sitter-march/
(2003 files, private HOME) reported `duplicate_binder` only for the six new
corpus files. Positive control: a `pfn dup_probe(a, a)` injected into
`stdlib/option.march` is reported when that file is checked (then reverted). A
regex grep for `(x, x)`-shaped binders over the same trees plus the OCaml
test sources found only expressions (`Big(n, n, n, n, n)`, `Pt(n, n)`),
literal tuples and comments.

### Refinement checker

Branch `claude/refine-multi-arg` makes the refinement checker decline a
lambda/parameter list that binds a name twice
(`abstract-refinement-uninstantiated` "binds `x` twice", and
`postcond_of_declared` lending no fact for a doubled formal). Once this lands,
those declines are unreachable for well-typed programs, since the typechecker
rejects such a list first; they stay as defence in depth. `lib/refinecheck`
was not touched.

### Not done

- The typing corpus (`specs/lang/types/reject/`) gets no fixture: per
  `specs/lang/types/INDEX.md`'s two-repo rule a new ERROR-level check is also
  a change to march-lean, which should mirror it (or ledger a skip) after this
  merges.
