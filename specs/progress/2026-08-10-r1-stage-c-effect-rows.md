# R1 stage C: per-function capability rows and grant discharge

Landed 2026-08-10. Design: `specs/2026-08-10-r1-stage-c-effect-rows-design.md`
(its "Corrections found during implementation" section records the two rules
this work proved wrong). Parent: `specs/2026-08-08-r1-no-ambient-io-design.md`;
stages A/B: `specs/progress/2026-08-09-r1-grant-check-stages-ab.md`.

## What this is, in one sentence

The guarantee stages A/B gave the whole program now composes per function:
`fn log(cap : Cap(IO.Console), msg : String)` is a discharge point, and `log`'s
transitive capability row must sit under `Cap(IO.Console)` no matter what the
module declares or whether any entry point opted in.

## The observation that made it small

`fn_transitive_capability_closures_tbl` was already SOUND and precise for
first-order code, for a reason easy to miss: reference edges come from
`free_vars_expr`, so a parameter contributes no edge — `List.map`'s entry is
the empty set, NOT a union over call sites — and a callback supplied by name
is charged to the supplier by the supplier's own edge. The feared "map's row
is the union of every argument it was ever passed" failure mode did not exist.

So stage C's actual hole was narrow: a function that RECEIVES a function value
and invokes it. Invisible at whole-program granularity (the creator is charged
and `main` reaches the creator), unsound at per-function discharge. That is
what the two new row components address, and it is why this did not become a
type-system project.

## Where it lives

- `lib/caps/cap_rows.ml{,i}` — the row scheme `{caps; deps; unknown}`, the
  seed walk, and the single fixpoint. Pure, no typecheck dependency.
- `Typecheck.fn_transitive_capability_closures_tbl` is now the **caps
  projection** of `Cap_rows.solve`, not a second implementation. Two
  independently-maintained capability tables is this codebase's established
  failure mode; a projection cannot exhibit it.
- `env.fn_row_seeds` recorded inside `record_fn_refs` itself — same
  `(params, body)` list, walked twice — so a declaration form that gains
  reference edges can never silently miss its row.
- `env.fn_grant_points` recorded in `check_module_needs` (which already owns
  the `cap_qname` convention and already recurses into nested modules);
  `Typecheck.check_fn_grants` checks them once at the end of
  `check_module_core`, beside `check_main_grant`.

## Decisions a future reader will want the reasons for

**No row syntax, and no printed-type change.** Rows are inferred-only. The
discharge surface is the existing `Cap(P)` parameter — the stage A/B corpus
showed every boundary was already spelled that way, so a second surface would
be a redundant spelling of the same fact. `ty`, `unify`, `generalize`,
`instantiate` and `pp_ty` are untouched.

**Generalization is sidestepped structurally, not solved.** The polymorphic
component (`deps`) is per-parameter and per-definition, not a quantified
variable in `ty`, so there is no interaction with HM let-generalization at
all. That was the largest named risk in the parent design; approach B retires
it rather than managing it. The price is bounded precision, paid as explicit
refusals rather than as unsoundness.

**`unknown` is a refusal, not a silent pass.** A function whose reach invokes
a value with no traceable creation site cannot be certified under a narrow
grant — same stance stage B takes on `IO.Foreign`, same reason: do not claim a
bound the analysis cannot see. Measured before shipping (below).

**Parameter caps only, and `main` excluded.** A returned `Cap(X)` is minting or
forwarding, not being handed one to spend. `main` stays `check_main_grant`'s
discharge point, or every whole-program violation would be reported twice
(pinned by a test that counts diagnostics, not just their presence).

**`Cap(a)` creates no discharge point.** A type VARIABLE names no lattice
point, so capability-polymorphic plumbing (`cap_narrow`'s own shape) grants
nothing and gates nothing.

**Typecheck-side, so both paths agree.** Verified, not assumed: the same
program is rejected identically by `march f.march` and `march --compile
f.march`. The REPL keeps R2's exemption by never reaching
`check_module_core`.

## Signature-only capabilities — the thing not to "fix"

Signature caps stay seeded into a function's own closure (`typecheck.ml`'s
`record_fn_caps qname sig_caps`), which is what makes them REQUIREMENTS on
callers and is why a discharge point trivially satisfies its own grant.
#225's exclusion of signature-only caps is a DIFFERENT mechanism, in the TIR
ceiling's used-set (`bin/main.ml`), and is untouched. The two are documented
side by side in the design doc precisely so nobody "fixes" one by breaking the
other.

## Verification

- `cap_fn_grant` group, 14 tests, RED first: both accept directions, the
  conditional-row property (invoking a parameter certifies) and its dual (the
  supplier is charged), the untraceable-invocation refusal and its `Cap(IO)`
  exemption, the `IO.Foreign` refusal, multi-cap-parameter grants, `Cap(a)`,
  dead code, no double-reporting for `main`, and **both real stdlib shapes** —
  a `DMod`-wrapped stdlib module and a FLATTENED prelude. That last one is the
  lesson of `specs/progress/2026-08-09-cap-shadowing-false-positive.md`: nine
  green unit tests built on `parse_and_desugar` once shipped a regression that
  silenced the most basic capability check in the system.
- Corpus sweep `specs/lang/types/check_types.sh`: **282 passed, 0 failed**,
  including new matched fixtures `accept/t170_fn_grant_proven_narrow` and
  `reject/t170_fn_grant_violated_by_helper` (whose manifest is deliberately
  perfect, pinning "declaring does not grant" at function level).
- `--check` over 304 files across examples/, bench/, test/native/,
  test/stdlib/, test/whole_program/: **zero** stage-C-attributable
  diagnostics. Proven non-vacuous by a positive control through the real
  binary, which produces the chained diagnostic.
- Full suite green; the flat closure's 21 cap-closure tests and stage A/B's 9
  cap_grant tests pass unchanged, which is the no-drift gate for turning the
  flat table into a projection.

## What the measurement found

`MARCH_DUMP_CAP_ROWS=1` dumps the solved table and exists so the refusal's
blast radius stays measurable after any change to the seed walk. Over a
stdlib-loaded program: 107 of 2453 functions carry a transitive `unknown`
(4.4%), clustered in `Seq`/`Flow` (a lazy sequence is a closure stored in a
constructor and invoked later), `Compress`'s streaming codecs, `Check`, and
`ChannelServer`. `List.map` comes back `caps=[] deps=[f]` — the row
polymorphism this stage exists for, confirmed rather than assumed.

## Known residual gap

A function that builds a `Flow` itself and consumes it is refused under a
narrow grant, even though everything it invokes was charged at construction.
Separating that from a `Flow` arriving from outside needs provenance tracking
through ADT payloads, which this approach deliberately does not do. Shipped as
an error anyway: 4.4% is rare, zero corpus programs hit it, and the
alternative is certifying a bound over an invocation nobody can see.

## Not built

Per-dependency capability budgets in `forge.toml` (rows are the substrate it
needed); in-`ty` rows as a future engine swap behind the `Cap_rows` boundary;
a written row annotation surface.
