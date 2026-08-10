# R1 stage D — grant required: closing the ambient default

Status: DESIGN, nothing built. Written 2026-08-10, immediately after stage C
shipped (`specs/progress/2026-08-10-r1-stage-c-effect-rows.md`). Parent:
`specs/2026-08-08-r1-no-ambient-io-design.md`; ladder:
`specs/2026-08-04-provable-sandbox-design.md`.

## The gap this closes, stated exactly

After stages A–C, March can say:

> A March program that states its grant cannot exceed it.

It cannot say the sentence everyone will assume that means:

> A March program cannot perform IO without declaring a grant.

Because `file_read(p)` still compiles with no capability in scope. R1 shipped
as an OPT-IN GATE: `fn main()` with no capability parameter is ambient, which
is what let stages A/B land without breaking a single program. That adoption
contract has done its job; this stage retires it.

The entire gap is one line of `Typecheck.check_main_grant`:

```ocaml
match main_grant with
| None -> ()          (* <-- here *)
| Some (grant, span) -> ...
```

## What was measured before deciding

Across all 330 programs in `examples/`, `bench/`, `test/native/`,
`test/stdlib/`, `test/whole_program/` and `specs/lang/types/accept/` that
declare a `main`:

| | count |
|---|---|
| already declare a `Cap` parameter | 9 |
| parameterless **and pure** — pass a strict default unchanged | **212** |
| parameterless **and perform IO** — must migrate | **109** |

The 212 is why this is not the ecosystem event the ladder doc implies: most
programs are already clean, and a program with an empty closure satisfies an
empty grant.

Grants the migrating programs actually need (main corpora, excluding the
types corpus):

```
17  IO.Console
 6  IO.Console, IO.Spawn
 2  IO.Console, IO.Foreign
 1  IO.Console, IO.FileRead, IO.FileWrite, IO.NetListen
 1  IO.Clock, IO.Console, IO.Process, IO.Spawn
```

Every one of these is `caps(main)` — a value the compiler already computes.
That is what makes the autofix exact rather than a guess.

## Multi-capability `main` is a PREREQUISITE, not an enhancement

`Desugar.check_main_signature` (`desugar.ml:2569`) permits exactly one
`Cap(P)` parameter, and `check_main_grant` takes only the HEAD of
`caps_in_ty` (`g :: _`). So a program needing `IO.Console` AND `IO.Spawn`
cannot express a narrow grant at all — it must widen to `Cap(IO)`.

**8 of the 27 measured programs (30%) need ≥2 capabilities.** Flipping the
default without fixing this would push nearly a third of the ecosystem to the
full grant, earning a WORSE claim than we have today. This is the reason the
two changes ship together.

The fix is not novel: stage C's `check_fn_grants` already takes the union over
all of a function's cap parameters. `main` becomes the same rule.

## Design

### D1. Semantics

A program whose `main` declares no capability parameter is granted NOTHING. If
its transitive capability closure from `main` is non-empty, that is a compile
error naming the exact grant it should have declared. An empty closure passes.

Unchanged, and deliberately:

- `test`/`setup` bodies and the REPL stay exempt — R2 carved them out because
  neither has an entry point to be granted from, and every test file would
  otherwise fail its own purity check.
- A library with no `main` has no gate. Stage C is what covers a library's
  cap-parameter functions; this stage is about programs.
- Non-IO capability roots (`Ffi`, `LibC`) are skipped exactly as in stage B.

### D2. Multi-capability `main`

- `check_main_signature` accepts N ≥ 0 parameters, **every one of which must
  be a `Cap(P)`** with P a known point of the lattice. Unknown paths stay
  rejected here, as today. A non-capability parameter (`fn main(x : Int)`) is
  still rejected, and so is a MIXED list (`fn main(cap : Cap(IO), x : Int)`) —
  the relaxation is "one cap parameter" → "any number of cap parameters", not
  "arbitrary parameters". The existing error message needs rewording for the
  plural case; `reject/t*` witnesses for both shapes are part of the corpus
  work below.
- The grant is the UNION over all cap parameters — the identical rule
  `check_fn_grants` uses, not a second one.
- `check_main_grant` consumes the full list rather than `g :: _`.

**`IO.Foreign` follows stage C's rule, not stage B's.** Stage B refuses
`IO.Foreign` under any grant but `Cap(IO)`, which is right when `main` holds
exactly one capability: certifying a console bound over an extern block would
be a lie. Once `main` can hold a SET, a parameter of type `Cap(IO.Foreign)` is
an explicit grant of the unbounded thing, and whoever wrote the signature knows
what they authorized. So the refusal applies only where the grant does not
cover it — where it would otherwise be an ordinary violation and this message
is simply the more informative one. This is a deliberate change to stage B's
main-specific rule, for exactly the reason stage C already diverged from it.

### D3. The `unknown` refusal does NOT apply at `main`

Stage C refuses a narrow grant over a function whose reach invokes a value of
untraceable origin. That rule is correct per-FUNCTION and wrong per-PROGRAM,
and the reason is structural rather than a tolerance judgment:

`unknown` exists because a function can RECEIVE a closure from outside itself,
so no caller can be charged for what it does. At `main` the program is closed
— every closure it invokes was created somewhere inside it, and creation sites
are charged by the free-variable edge that has always driven the closure. The
two genuine "outside" routes are already handled elsewhere: FFI surfaces as
`IO.Foreign` (D2), and hot code reload is explicitly outside the claim (ladder
§R8 — a reload injects authority after the proof is discharged).

So `unknown` is a per-function concept. Stage A/B was right not to have one,
and stage D does not add one.

Measured, and consistent with the argument rather than the basis for it: 1 of
33 programs with a `main` row carries a transitive `unknown`
(`test/stdlib/csv_server.march`), and it does not need to break.

### D4. Diagnostic and autofix

The error names the exact grant, because the compiler computed it — the grant
it should have declared IS `caps(main)`:

```
-- ERROR ------------------------------------------- app.march

`main` performs IO but declares no grant. The program reaches
`IO.Console` and `IO.Spawn`; a `main` with no capability parameter
is granted nothing.

  3 |   fn main() : () do
        ^^^^^^^^^^^^^^^^^

help: declare the grant `main` actually needs —
        fn main(console : Cap(IO.Console), spawn : Cap(IO.Spawn)) : ()
      or grant everything with `fn main(cap : Cap(IO))`.
      `forge fix` can apply this.
```

It carries a JSON `fix` payload (an insert/replace keyed to `main`'s signature
span) so `forge fix` applies it. The direct-builtin `needs` route already emits
such a payload; the ceiling route does not, which is a filed Tier-2 loose end
(`specs/2026-08-09-cap-loose-ends-plan.md`). Doing it here closes half of that
item and establishes the shape for the other half.

Parameter naming for the generated signature: **`cap_` + the lattice leaf,
lowercased** (`IO.Console` → `cap_console`, `IO.FileRead` → `cap_file_read`,
`IO` → `cap_io`).

The prefix is not decoration. The obvious scheme — bare leaf name — was tried
first and produces UNPARSEABLE code: `IO.Spawn` → `spawn`, and `spawn` is a
reserved keyword (`ESpawn`, the `spawn(Actor)` form). That is not a corner
case, it is the second most common grant in the corpus (6 programs need
console + spawn), so the naive rule would have broken the migration at scale.
A fixed `cap_` prefix cannot collide with any keyword present or future, needs
no reserved-word table to be kept in sync with the lexer, and reads no worse.

### D5. Codegen — the risk area

Capabilities are erased, and `march_spawn_main` invokes the entry through a
bare `void (*)(void)`. A 1-parameter `main` is handled today by **a thin 0-arg
adapter** that supplies the erased `Cap(IO)` as a null pointer and forwards
into the real 1-arg mangled main. That adapter exists because the naive
version **SIGBUS'd** — see `test/native/main_cap_io.march`, whose header
comment is the incident report.

Stage D generalizes it from 1 null to N. That is mechanically small and
historically dangerous, and this codebase's record is full of compiled-only
bugs that typecheck-side tests cannot see. **Compiled-and-run tests at 0, 1, 2
and 3 cap parameters are mandatory**; a typecheck-only test would pass while
the binary crashes.

## Migration

109 in-repo files, each a one-line signature change, generated by the autofix
and verified by re-running the sweeps rather than by inspection. The 8
multi-cap programs gain narrow grants they could not previously express — a
strict improvement, not merely a port.

## Rollout: hard flip

No flag, no deprecation window. Parameterless `main` with a non-empty closure
is an error from the release this lands in.

Recorded because it was a live decision with a real cost: external programs
that perform IO break at upgrade. The fix is one line and `forge fix` applies
it, but there is no adaptation window. The alternative considered was the
`--cap-strict` path (#225: opt-in flag → migrate → flip default), which would
have given external code a release to adapt at the cost of a flag to retire
later. The warning-first path was rejected on this repo's own evidence: the
severity flip (#219) exists because capability warnings were not driving
migration.

## What the claim becomes

> A March program cannot perform IO without declaring the grant it performs it
> under.

Unqualified, at program level. The ladder's stage 2 becomes fully earned
rather than "opt-in only".

Still NOT earned, and must not be implied: "a function cannot perform IO
without holding authority." That is function-level R1a — every IO-performing
function taking a capability parameter, including across the 112-module
stdlib. Deferred deliberately; stage C's per-function grants plus real usage
data should inform whether it is worth its major-version cost.

## Testing plan

- `test_compiler.ml`, new `cap_grant_required` group, RED first: parameterless
  + IO errors and names every reached capability; parameterless + pure passes;
  multi-cap `main` accepted and its grant is the union; a violation under a
  multi-cap grant still errors; `Cap(IO.Foreign)` as an explicit parameter is
  accepted while `IO.Foreign` under a console-only grant is refused; test
  bodies and no-`main` libraries unaffected; a `main` with a non-capability
  parameter and a `main` with a MIXED parameter list are both still rejected;
  and at least one test against the real stdlib-prepended shape (the lesson of
  `specs/progress/2026-08-09-cap-shadowing-false-positive.md`).
- A regression witness for D3: a program whose `main` row carries a transitive
  `unknown` must still compile under a narrow grant.
  `test/stdlib/csv_server.march` is the live instance — if a future change
  makes it fail, that is D3 being silently reversed, which is exactly the kind
  of drift a passing suite would otherwise hide.
- `test_codegen.ml`: compiled-and-run at 0/1/2/3 cap parameters (D5).
- Corpus: matched accept/reject pair after t170, plus a multi-cap accept
  witness — the case that was previously inexpressible.
- The 109-file migration verified by `specs/lang/types/check_types.sh` and a
  full compile of examples/, bench/, test/native/, test/stdlib/ with the real
  binary, not by green alcotest alone.

## Out of scope

- Function-level R1a (above).
- A `forge.toml` `grant = [...]` key generating the `main` signature — still
  deferred, unchanged from the parent design.
- The other half of the Tier-2 fix payload work (the ceiling route).
