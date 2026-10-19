`[P4]` Refinement: annotated fold accumulators the phase-4 rule leaves inert

Filed 2026-10-18 with phase 4 of `specs/2026-10-18-fold-accumulator-invariants-design.md`
(`specs/progress/2026-10-18-fold-invariants-phase4.md`). The annotated accumulator
`fn (acc : {T | I}, x) -> step` is checked, assumed and carried only in one shape
(`annotated_acc_of`, `lib/refinecheck/refine_check.ml`): an inline lambda argument, a callee
whose declared return is a bare type variable `b`, parametric in it (P1/P2, not
`@[trusted]`/`@[assume]`/`impl`), exactly one `b`-typed parameter annotated, a scalar
refinement, and a lambda no pass site obliges. Everything else keeps the pre-phase-4
behaviour: the annotation is neither checked nor assumed (a skip-free silence, so `cap
verified` does not flag it), never a false proof. The declined shapes, each a possible
extension:

- **A container annotation** (`acc : List({Int | _ > 0})` with a list-building step): the
  phase-2 container hypothesis could take the annotation as the entry, `I` read as a
  `Container` demand. The result fact would then be a container-env entry for the `let`
  binder, not a scope fact (`postcond_of` carries scalars only).
- **A one-parameter lambda at a type-variable domain** (`iter(n, x : b, f : b -> b)` with
  `fn (k : {Int | _ > 0}) -> …`, and the OUTER lambda of a curried step,
  `Enum.fold(ys, 1, fn (a : {Int | _ > 0}) -> fn x -> …)`): the pass-site rule obliges it
  contravariantly and reports a VIOLATION (`b` does not imply `_ > 0`). Reading it as the
  invariant instead would need the pass-site rule to defer to this one for a parametric
  callee; until then the curried `Enum.fold` cannot take an annotated accumulator at all.
- **Two annotated `b`-typed parameters** (`fn (a : {Int | _ > 0}, c : {Int | _ > 0}) -> …`
  for `f : b -> b -> b`): equal annotations could be one invariant; different ones need a
  conjunction or a choice.
- **A callee whose return is a container of `b`** (`Enum.reduce : … : Option(a)`): the
  result fact would be an element fact of the `Option`.
- **A `let`-bound lambda passed by name** (`let f = fn (acc : I, x) -> …` then
  `foldl(ys, 1, f)`): its body is walked as a local function, not at the call.
- **An annotated accumulator passed to a non-parametric callee** (an impostor fold, a
  `@[trusted]` one): the annotation stays inert. Under `cap verified` it could instead be a
  recorded `parametric-source-unproved` skip naming the annotation, so a user who wrote it
  learns that nothing checks it; that would newly reject accepted modules, so it needs a sweep.
- **A return tail through a `let`** (`let s = foldl(…, fn (acc : I, …) -> …); s` against a
  declared return): the postcondition walk runs before the body walk that fills the fact
  table, so the tail `s` carries nothing there. A direct tail (`foldl(…)` as the last
  expression) is checked through the scalar demand entry and proves.
