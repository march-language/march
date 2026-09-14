# `[P3]` Contract `Array.get` / `set` / `pop` with a bounds precondition

Filed 2026-09-13, when the blocker was removed
(`specs/progress/2026-09-13-measure-over-scalar-ctor-field.md`): a
`@[measure]` over `PVec`'s count field now reflects concretely on a literal
and is decided by a guard over `Array.length(v)` on an opaque value, which
is the `List.nth` treatment's precondition shape.

What is left is the contract itself and its consequences:

- tag `Array.length` `@[measure]` (it passes the M-b gate: total,
  terminating, pure) and give `Array.get` / `set` / `pop` a precondition
  `{Int | _ >= 0 && _ < Array.length(v)}` (`pop`: `Array.length(v) > 0`);
- add them to `Panic_surface_by_proof`'s covered set, which is fail-closed:
  every call under `cap no_panic` must then either prove its bound or be
  rejected, so an unguarded `Array.get(v, i)` in existing `cap no_panic`
  code becomes an error;
- run a full stdlib + ecosystem `--refine-report` sweep BEFORE landing and
  review every obligation that moves to VIOLATED: each is a real bug or a
  real false positive, and either blocks the change until understood.

Design: `specs/2026-09-13-refinement-p3-designs.md` §4, last paragraph.

## Landed 2026-09-14

### The contracts

`stdlib/array.march` gains a private measure and three preconditions:

```march
@[measure]
pfn pvec_length(v : PVec(a)) : Int do
  match v do
  PVec(n, _, _, _) -> n
  end
end

fn get(v : PVec(a), idx : {Int | _ >= 0 && _ < pvec_length(v)}) do ... end
fn set(v : PVec(a), idx : {Int | _ >= 0 && _ < pvec_length(v)}, val) do ... end
fn pop(v : {PVec(a) | pvec_length(_) > 0}) do ... end
```

The measure is a separate private `pvec_length`, not `@[measure]` on
`Array.length` itself as this file originally proposed: measures are keyed by
bare name, so a stdlib measure called `length` would collide with any user
`@[measure] fn length`. `Array.length(v)` in user code is aliased to
`pvec_length` instead (`Refine_encode.measure_alias` and
`Refine_check.qualified_measure_spelling`), gated by `stdlib_member_defs_ok`
exactly like `List.length` → `len`, so a user module shadowing `Array.length`
does not inherit the alias.

`Typecheck_modcaps`: `Array.get`/`set`/`pop` move from `panic_surface_stdlib`
(the syntactic ban list, now empty) to `panic_surface_contracted`, the
fail-closed proof-checked set. Under `cap no_panic` a guarded call is accepted
and an unguarded or off-by-one guarded call is still rejected.

### The solver fix it needed

With the contracts in place the first probe hung for minutes. Every
satisfiable query mentioning the quantified `pvec_length` axiom came back
`unknown (incomplete quantifiers)`, and only at the 3 s per-query timeout; the
stdlib's own `aho_corasick` calls to `Array.get` are checked in every program,
so a cold `--check` of a trivial file cost about a minute.

`Refine_encode.measure_definition`: a measure whose arms all translate with no
measure call (non-recursive) and whose result is Int is now emitted as a
quantifier-free `(define-fun name ((x ADT)) Int (ite ((_ is C) x) (let ((f (C_0 x)) …) body) …))`.
`build_measure_preamble` gives such a measure no `declare-fun`, no
non-negativity, base-case or recursion-equation axiom (all implied by the
definition). Recursive measures keep the axioms (induction needs them);
set-valued measures (landed separately the same week) keep them too. The
extracted query decides in ~28 ms, sat and unsat. This changes the encoding
of every non-recursive user measure, so the refine oracle was run over it
(see the PR).

### Sweep

Taken before landing, baseline compiler vs contracted compiler, over 1171
files: `stdlib/`, `test/native/`, `test/stdlib/`, and every git-tracked
`.march` file in eighteen local ecosystem repos (cube_forge, depot, envoy,
forgepm, conduit, sigil, scroll, march_doc, march-lean, perihelion, mgrep,
march-synth-demo, marathon, mrk, by_chase, sigil_blog, islands, bastion),
each file in a fresh cwd under a private HOME:

- **0 new violations, 0 exit-code changes.**
- Every program's `user + stdlib` ledger gains the 15 stdlib `Array`
  obligations (2 proved, 13 skipped at computed indices).
- `cube_forge`: +55 skipped (computed chunk indices), hint blocks 248 → 300
  per entry check. `march-synth-demo`: +2 skipped. `test/stdlib/test_array`:
  +15 hints.
- No `cap no_panic` code in the corpus calls `Array`, so the moved ban
  rejects nothing that compiled before.

The sweep ran on a87b5caf, before set refinements merged; the rebase onto
them only touched `build_measure_preamble` (set-valued measures excluded from
definitions) and the audit baselines (87 → 90 enforced).

### Tests

`test/test_refinecheck.ml`, run through the real typecheck → `Refine_check`
→ `Panic_surface_by_proof` pipeline with the real `stdlib/array.march` loaded:

- group `array-bounds-contracts`: guarded `get`/`set`/`pop` proved, unguarded
  and off-by-one (`<=`, `>= 0` for `pop`) not; under `cap no_panic` guarded
  calls admitted and unguarded/off-by-one rejected. Shown RED by moving
  `Array.get` back to the ban list, by dropping it from the contracted set
  (fail-open), and by deleting the `Array.length` alias.
- group `measure-definition`: a non-recursive user measure over `Box(Int,
  Int)` and a three-constructor ADT decides both proved and violated (with a
  counterexample); the preamble holds a `define-fun` and no `forall` for it,
  while a recursive control measure keeps its axioms. The preamble assertion
  is shown RED by disabling `measure_definition`; the verdict counts are NOT
  encoding-sensitive (the forall encoding still reaches `Violated` there, in
  9 s instead of 10 ms), which is why the preamble is asserted directly.
