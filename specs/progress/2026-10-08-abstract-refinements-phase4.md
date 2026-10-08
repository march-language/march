# Abstract refinements, phase 4: the `a[p]` / `Bool[p]` shorthand

Landed 2026-10-08. Plan: `specs/plans/2026-10-07-abstract-refinements-phase4-plan.md`.
Design: `specs/2026-09-20-abstract-refinements-design.md` (phase 4, the last).

## What a user sees

```march
fn filter(xs : List(a), pred : a -> Bool[p]) : {List(a[p]) | subset(elts(_), elts(xs))}
```

is now the stdlib's signature, and means exactly the spelled-out
`pred : ({x : a | true}) -> {Bool | _ == p(x)}` and `List({a | p(_)})`, which
are still accepted. The rules:
- `T[p]` anywhere is `{T | p(_)}`.
- `D -> Bool[p]` is the definer. A named domain binder is reused. A domain refined over `_`, or a tuple (several-argument) domain, is a parse error that says what to write.
- A curried `a -> b -> Bool[p]` is inert.

## What landed, per commit

| Commit | Change |
|---|---|
| `parser: the let?/let* annotation errors stop at the colon (11 -> 7 …)` | two error-only rules no longer parse a type; that ambiguity was 4 of the grammar's 11 conflicts. Message and caret unchanged. |
| `parser: T[p] is an abstract-refinement slot` | `ty_post`: `TyRefine (T, Some "_", p(_))`. The binder `_` is an unforgeable marker (`{_ : T \| …}` is a syntax error for users). |
| `parser: D -> Bool[p] is the definer form` | `abstract_definer_arrow` in the `ty ARROW ty` action. |
| `ast: show_ty prints the abstract-refinement shorthand back` | diagnostics print `List(a[p])`; the spelled-out form still prints as `{ a \| ... }` |
| `tree-sitter: abstract_refinement_type for T[p]` | grammar.js and the regenerated parser (0.26.7) |
| `stdlib: … use the a[p] / Bool[p] shorthand` | the four signatures, as the equivalence proof below |

## Pressure test, and what held

| Probe | Planned | Measured |
|---|---|---|
| menhir conflicts, before | 11 | 11 |
| after the error-rule fix | 7 | 7 |
| after `ty_post` and the arrow rewrite | 7 | 7 |
| `let?`/`let*` annotation error caret | unchanged | `run_errors` 287/287, `.expected` unchanged; `emit_core_ast` 12/12 |
| tree-sitter | generates; sugar parses | corpus 70/70; `check-tree-sitter.sh` ok (1518/1522, 4 known failures unchanged); self-test ok |

One test needed strengthening during D2. Phase 1's walker labels *every*
codomain occurrence a definer, so comparing role labels alone could not tell
`{Bool | p(_)}` from `{Bool | _ == p(x)}`, and the D3 equivalence test passed
before D3 existed. The role summary now also records whether a definer
applies `p` to the callback's own argument (`D=`), and that test was red
until D3.

## Equivalence proof (D6)

After rewriting `List.filter`, `List.find`, `List.take_while` and
`Option.filter` in the shorthand:
- `scripts/refine-oracle.sh check` reported **REFINEMENT DIAGNOSTICS IDENTICAL** (7986 lines over 491 fixtures). Every count line includes the phase 2/3 definition-side proofs of those four functions, so a shorthand that meant anything else would have moved them.
- The audit baselines (`test/refine_audit/*.baseline`) were **byte-identical**.

## Tests

- `test_refinecheck` group `abstract-sugar` (9 cases):
  - role equivalence with the long form;
  - the marker binder;
  - a shorthand-declared `filt` proves row n and is too-weak for n2;
  - named binder reuse;
  - the two parse errors;
  - an explicit `{Bool | p(_)}` stays untouched;
  - a curried callback proves and violates nothing;
  - `show_ty`.

  Disabling the arrow rewrite reddens exactly the five cases that need it.
- Grammar corpus: `p42` (parses, including a list literal after a `let`), `r18` (`T[p, q]`), `r19` (several-argument callback); 58/58.
- Typing corpus: `accept/t312` (a shorthand-declared combinator under `cap verified`: result demand and parameter slot) and `reject/t313` (too weak); 434/434.
- LSP: hovers render types through `Ast.show_ty`. There is no hover-on-signature test helper in `test_lsp`, so the `show_ty` unit test is the pin.

## Verification

Full `scripts/run-tests.sh`:
- Passed: compiler 1381, eval 288, codegen 702, stdlib_march 79, jit 33, lsp 383 + 5 + 37 + 10 + 8, refinecheck 1029, errors 287.
- `run_stdlib`: 892/894. The two failures are **pre-existing on `origin/main`**, checked in a temporary worktree built from main:
  - `track integration 6` ("cas cache hit") fails on main outright;
  - `adversarial-regressions 49` (MARCH_SANITIZE cache isolation) passes on a fresh checkout's first run and fails on every later run, on main too: it is not idempotent and leaves cache state behind.

  Neither touches the parser or refinements; filed separately.

## Abstract refinements: what is still open

- Two-argument predicates (`Map.filter`, a `fold_left` invariant): `2026-09-20-abstract-refinements-multi-arg-callbacks.md`.
- `List.partition` (`p` inside a tuple and under `not`).
- `Deque.filter`.
- A lambda body calling anything but a single eta-reducible call.
