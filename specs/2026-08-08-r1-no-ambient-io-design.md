# R1 — no ambient IO: design sketch and sequencing

Status: DESIGN ONLY, nothing here is built. Written 2026-08-08, after the
capability ceiling became the default (#225), because R1 is now the only
load-bearing gap left below stage 3 of the sandbox ladder
(`specs/2026-08-04-provable-sandbox-design.md` §3) and it deserved more than
the one section the ladder doc gives it.

## Why R1 is the live item

Everything shipped in 2026-08 hardens the *declaration* side:

| shipped | what it guarantees |
|---|---|
| severity flip (#219) | a direct builtin call requires a `needs` line |
| ceiling default (#225) | a stdlib-mediated use requires a `needs` line |
| R3 (#198) | a `Cap` cannot be fabricated from data |
| R2 | the root is granted to `main`, not takeable by name |

None of it touches the *authority* side: `file_read(p)` executes for any
module that wrote (or was autofixed to) `needs IO.FileRead`. `needs` is
self-declared; nothing is granted. The honest statement of today's system is
**mandatory manifests, enforced end-to-end** — which is auditing, not
sandboxing. A hostile dependency declares `needs IO.Network` and exfiltrates,
and every check we have says the build is clean, because the declaration is
truthful.

R1 changes the claim to: **code that was not handed a capability cannot
perform the IO, no matter what it declares.** That is the sandbox.

## The two formulations, and why the ladder doc's pick stands

**R1a — explicit tokens.** `file_read : Cap(IO.FileRead) -> String -> ...`.
Every IO stdlib function grows a parameter; every caller threads it; `List.map`
over an effectful function needs the token, so `map` needs it, so everything
needs it. Unadoptable for a 112-module stdlib. Rejected in the ladder doc and
nothing since changes that.

**R1b — effect rows, inferred.** `read_config : () -> Config ! {IO.FileRead}`,
rows inferred everywhere, written only at boundaries, discharged exactly once
— at `main`, against the granted root. Still the recommendation.

**New since the ladder doc: most of R1b's semantic content now exists**, just
not in the type system. The per-function transitive capability closure
(`fn_transitive_capability_closures_tbl`) IS an inferred effect row — computed
to fixpoint over the reference graph, per function, stdlib-transparent. It
already drives Check 4 (import costs) and, since 2026-08-08, the
unused-`needs` suppression. What it lacks to be R1b:

1. **Polymorphism.** The closure is a flat set per function name. `map`'s row
   must be `e` of its argument (`(a -> b ! e) -> List(a) -> List(b) ! e`),
   not the union of every argument it was ever passed. This is the R5 line in
   the ladder doc, and it is the actual type-system work.
2. **A discharge point.** Rows must be *checked against a grant* at `main`,
   not merely recorded. Today the closure is descriptive.
3. **Denial semantics.** A row the grant does not cover must be a compile
   error naming the call chain — the ceiling's attribution machinery already
   produces exactly the needed "who reaches what through whom" evidence.

So R1b is no longer "starts from zero" (the ladder doc's words, true when
written): the inference exists and is load-bearing; the typing and the gate do
not.

## Sequencing (the R1/R2 question the ladder doc left open)

The ladder doc asked whether R1 and R2 are separable. They are, and R2's
shipped shape decides the order of R1's stages:

**Stage A — gate the root, not the builtins.** `main : Cap(IO) -> ()` is
already the only grant. Add: a program whose `main` takes NO capability
parameter gets an EMPTY grant, and a non-empty program-wide capability closure
against an empty grant is a compile error. This makes "pure `main`" a
machine-checked claim — the first R1 property, with no per-builtin change and
no stdlib migration. Estimated small; reuses the ceiling's flat set.

**Stage B — narrow grants.** `main : Cap(IO.Console) -> ()` grants only
console; the program-wide closure must sit under the granted lattice point.
Still no effect polymorphism needed — the check is program-global, so `map`
never needs its own row. This is R1 at whole-program granularity: coarse, but
it already delivers "this binary cannot touch the filesystem, proven at
compile time" for programs whose `main` says so.

**Stage C — per-function rows (R5).** Effect-polymorphic signatures so the
guarantee composes per function and per dependency, not per program. This is
the type-system project: row variables in `TArrow`, generalization at `let`,
row subsumption against the lattice. Only at this stage does the stdlib's
surface change, and only in inferred (unwritten) types — the major-version
risk the ladder doc flags lives here and nowhere earlier.

Stages A and B are buildable on today's machinery and neither breaks a single
existing program that declares what it uses (a `main()` taking no cap is
today's default and today gets ambient everything — stage A flips that ONLY
when the closure is non-empty, which the ceiling already requires be
declared). Programs migrated for #225 are exactly the programs stage B can
verify.

## Interactions to design for (found the hard way in 2026-08)

- **The interpreter has no attribution pass.** Stages A/B gate on the
  typecheck-side closure, which both paths share — do NOT gate on TIR
  attribution or `march file.march` and `march --compile` diverge (the
  unused-warning contradiction, again).
- **Test/REPL exemptions.** R2 left `test`/`setup` bodies and the REPL
  rootless by design. Stages A/B must treat them as fully granted or every
  test file fails its own purity check.
- **Signature-only capabilities.** #225 removed them from the ceiling's used
  set (erased ⇒ no emitted operation). A grant check must instead treat them
  as REQUIREMENTS on the caller — that is R4's direction and already checked;
  do not re-add them to the used set.
- **`IO.Foreign` stays outside.** What linked C does is not modellable; the
  grant check should refuse to certify (stage-B error) a program whose
  closure contains `IO.Foreign` under a narrow grant, rather than pretend to
  bound it.

## What this spec deliberately does not decide

Row syntax (`!{...}` vs annotation-free), whether stage C rows appear in
printed types by default, and whether `forge` should offer a
`grant = [...]` manifest key that generates the `main` signature. All three
are surface decisions that stage A/B experience should inform.
