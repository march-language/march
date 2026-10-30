Refinement reflection, phase 0: the inert analysis, `--reflect-report`, `--refine-report-sites=all`
and `scripts/refine-oracle.sh monotone` (`specs/2026-10-29-refinement-reflection-design.md` §10,
phase 0; the design is on branch `claude/reflection-design`, PR #1036).

## What landed

- `lib/refinecheck/refine_reflect.ml` (new): the §2.1 rule R1-R9, R11 as a greatest fixpoint over
  `Refine_term`'s graph. One row per function: `reflected unfold` (with `(guard: …)` when a parameter
  is refined, §3.6) or `no R<k>:<reason> (<file:line:col>)`, the first blocker in R-order, ties broken
  by source position. Nothing in the compiler reads it except the report.
  - R1 reads the unit table (kind, `u_name = "main"`) and a declaration walk for origins (`impl`
    method, interface default, top-level `let`); a local `fn` that reads a value bound by an enclosing
    unit is `R1:captures k`.
  - R2 reads `Refine_term.last_certs` (the refinement walk's certificate), else the phase-1
    certificate; `structural` and `metric` pass. Certificates for undemanded SCCs come from a second
    refinement check that `--reflect-report` runs on the side with every user SCC demanded (as
    `--termination-report` demands them), under `Obligation.with_scratch` and a throwaway
    diagnostic context, so the real ledger is untouched (review fix 3, below). With
    `--termination-report` also given, the real check already demands them and is reused.
  - R3/R4/R6 classify every call SITE (new `Refine_term.graph.sites`: each callee name with what it
    resolved to and its span). Builtins are matched by resolved identity: a builtin, or a stdlib
    prelude function of the same name (`println` resolves to the prelude's). Effects are the
    typechecker's `builtin_cap_table` plus `Refine_term.event_builtins` plus actor primitives; failure
    is the `panic`/`todo`/`unreachable`/`exit` family; the §2.3 table is the rest of what is allowed.
  - R4's divisions read the ledger: a `/` or `%` by a non-zero literal passes, any other needs a
    `Division` obligation at that call span with verdict `Proved` (`Obligation.obligations_at`). Such
    obligations exist only in a `cap no_panic` module, so elsewhere a variable divisor always blocks,
    which is D6 as written. The report therefore prints after `Division_safety` runs.
  - R5 reads the typechecker's non-exhaustive spans, guarded matches included, through a new
    `Typecheck.last_nonexhaustive_match_spans` (set at the end of `check_module_core`; the `--check`
    path keeps no env). `match do` with no final `_ ->` is also R5.
  - R6 interface dispatch: `==`/`!=` require each reachable `impl Eq` to pass R2-R7 with its callees
    (§3.5, C4); any other dispatch (`show`, interpolation via `to_string`, `compare`, a user `<`)
    blocks. Comparisons pass only at `Int` or `Float` (from the type map).
  - R7, R8 (sorts per §3.2; a `Unit` result; a parameter refinement must use only predicate
    vocabulary, `Refine_encode.known_predicate_fn`), R9, R11 (`len`, `set_vocabulary`, `is_<Ctor>`).
  - A recursive SCC is kept or dropped as a whole.
- `--reflect-report` (`bin/flags.ml`, `bin/main.ml`, both pipelines), bypassing the early source-CAS
  exit like `--termination-report`.
- `--refine-report-sites=all`: one line per obligation of any verdict. A skip keeps the bare flag's
  columns; other verdicts print `verdict \t user|stdlib \t file:line:col \t kind \t callee \t
  predicate`. The bare flag is unchanged byte for byte (below). There is no `unknown` verdict in the
  ledger; an undecided query is a `skip` with reason `solver-undecided`. No `uses:` column (no stage 2).
- `scripts/refine-oracle.sh`: `baseline` also records `sites.txt` from the same sweep when the
  compiler has `=all` (the site rows are split off, so `refine.txt` is what it always was); new mode
  `monotone <dir>` compares per (fixture, site, kind, callee, predicate) with the §6.2 table.
- `test/test_refine_reflect.ml`, group `reflect-report` in `test/test_refinecheck.ml`: every row of
  the phase-0 table plus `report_sort` (R8), the main/summary row, a proved-`Division` control, two
  `sites_all` cases, and the pinned §0 probes: `test/refine/reflect/*.march` with `.expected`
  holding the user rows of `--refine-report-sites=all --reflect-report` (regenerate with
  `UPDATE_SNAPSHOTS=1`). The probes are a1-a6, b1-b2, c1-c4, g1-g4, h1-h3 and r1-r4 (r4 is the
  accept-side `letp.march`: a refutable pattern parameter, `mh(Cons(h, _))`, is R5). Their obligation
  verdicts match the §0 tables.
- Todos (one file each): F5 `2026-10-29-bool-measures-never-discharge.md`, F6
  `…-list-returning-measure-silently-ignored.md`, F7 `…-measure-gate-does-not-follow-callees.md`,
  F8/g3 `…-predicate-eq-structural-warning.md`, F21 `…-predicate-vocabulary-shadows-user-functions.md`,
  D8 `…-reflection-int-overflow.md`; and one found here,
  `…-not-at-block-start-parses-as-two-statements.md` (below).

## Rulings

- **Table rows that contradict R-order.** The rule is "first blocker in R-order". Where the phase-0
  table's expected text would need a later rule to win, the fixture was changed, not the order:
  `report_fnvalue`'s `h` passing `h` makes `h` a recursive SCC through a reference edge, so it is
  `R2:unproved:reference` (asserted as such); the R7 case is `h2` passing `inc`.
- **Probe r1 as written does not say what it means.** `else not p(n) end` parses as two block
  statements, `not` and `p(n)` (`--emit-core-ast`), so the r1 fixture's `p` is honestly
  `R7:names not as a value`. `report_domain` writes `not(p(n))` and is reflected with
  `guard: n >= 0`. Filed as a parser todo.
- **R11 uses the bare name everywhere**, so a stdlib `Set.empty` is blocked in every program, not only
  when `set.march` is the entry. Inside its own module a predicate spells it bare and gets the
  builtin (F21). Cost if wrong: about 12 stdlib functions (`empty`, `singleton`, `member`, …) not
  reflected that a qualified spelling could have reached.
- **Effects are a list, not an analysis.** R3 is the builtin capability table, the event builtins
  and the actor primitives; any other builtin outside §2.3 blocks under R6 instead. A missed effect
  can only move a function from R3 to R6, never into the reflected set.
- **Builtin ADTs.** `List`, `Option`, `Result` have a sort though `collect_types` does not see them
  (they are not declared in the stdlib source); other undeclared type constructors (`Atom`, `Map`'s
  internals, SIMD vectors) have none (R8).
- **The SCC rule exempts an `impl` method that passes R2-R7**: an `eq` in a recursive group with its
  caller does not drop the caller (it is what `==` needs, §3.5).

## Review fixes (fresh-context review of this branch)

Each fix landed test first; the new tests were run against the reviewed code (RED) and then the fix
(GREEN). Group `reflect-report` is 28 cases.

1. **`$len` by spelling (I3).** A callee whose `u_name` was `List.length` was taken as `$len` even
   when it was a user `mod List do fn length …`, so `f(xs) = List.length(xs)` was falsely
   `reflected`. Now the unit must live in the stdlib's `list.march` / `string.march`
   (`Typecheck_builtins.file_is_stdlib`) AND the encoder's own ownership gate must agree
   (`Refine_encode.list_length_is_stdlib` / `string_byte_size_is_stdlib`). RED: `f verdict` was
   `reflected`; GREEN: `R6:calls List.length, which is not reflected`
   (`report_len_shadow_module`, with a stdlib control that stays reflected).
2. **`=all` missed every `Division` obligation.** It printed before `Division_safety.check_module`
   filed them, so the monotone gate was blind to what R4 reads. It now prints after it, in both
   pipelines (the bare flag stays where it was; `Division_safety` records only `proved` /
   `violated`, never a skip, so its output cannot change). RED: no `proved … division` line in a
   `cap no_panic` module; GREEN: one proved and one violated division line
   (`sites_all: Division obligations are listed`). The monotone RED proof above predates this fix,
   so its listings have no division sites.
3. **`--reflect-report` changed the ledger it ran beside.** It used to set `Refine_term.check_all`
   for the real check, which files termination obligations: `--refine-report` counts and `=all`
   lines differed with the flag on, and the pinned fixtures carried those extra `termination` rows.
   Now the real check is untouched (option (a)): `print_reflect_report` re-runs
   `Refine_check.check_module` with `check_all` set, inside `Obligation.with_scratch`, into a
   throwaway `Errors.ctx`, keeps only the certificates, and restores `last_certs`. RED:
   `report_ledger`'s two listings differed; GREEN: identical `--refine-report
   --refine-report-sites=all` output with and without the flag, and `cnt` still reflected on its
   metric certificate. Fixtures regenerated: the `termination` rows of `c3b`, `h1` and `r1` (the
   undemanded SCCs) are gone; `r1`'s `q` keeps its rows because `@[decreases]` demands it. Cost: one
   more refinement check per run, only under the flag.
4. **R8 accepted a guard that does not translate.** A parameter refinement with `==` whose operand
   is the binder, at a type with a hand-written `impl Eq` (a derived impl has the synthetic
   `"<none>"` interface span), is now `R8:the refinement of p uses == at P, which has a hand-written
   Eq` (§3.5); `len(_) == 3` compares Ints and is unaffected, and a derived `Eq` keeps its guard.
   RED: g1's `need` was `reflected unfold (guard: p == P(1, 2))`; GREEN: R8
   (`report_eq_guard`; `g1`, `g3` fixtures regenerated). This is the §3.5 rule, not the encoder's
   translation: a guard the encoder rejects for another reason is still only vocabulary-checked.

Minor: a data type with a function-typed field, at any depth, has no sort (`report_fn_field`, RED
then GREEN); a report that names an unsolved type variable says "a type variable" instead of its
internal name (it printed `== at c3`); not covered by a test.

## RED perturbations (each rule's fixture)

Each perturbation was applied to `refine_reflect.ml`, rebuilt, and the group run:

| Perturbation | Goes RED |
|---|---|
| drop every R1 event | `report_local`, `report: main`, the probes |
| drop every R2 event | `report_diverge`, `report_trusted_cert`, `report_fnvalue` (`h`), the probes |
| drop every R3 event | `report_effect`, `report_eq_effect`, `report_chain`, `report_mutual`, the probes |
| drop every R4 event | `report_partial`, `report_div`, the probes |
| drop every R5 event | `report_guarded`, `report_partial`, the probes |
| drop every local R6 event | `report_dispatch`, the probes |
| drop every R7 event | `report_fnvalue`, the probes |
| drop every R8 event | `report_sort`, the probes |
| drop every R9 event | `report_trusted_nonrec` |
| drop every R11 event | `report_shadow`, the probes |
| R6 fixpoint off (every callee dependency met) | `report_shadow`, `report_eq_effect`, `report_chain`, `report_mutual`, `report_local`, the probes |
| R4 ignores the ledger (every division proved) | `report_div` |
| R5 allows guarded matches | `report_guarded`, the probes |
| SCC-as-a-whole off | nothing: every member of a recursive SCC depends on another member by a direct edge, so the fixpoint already drops it. Kept as the spec's stated rule; no fixture can isolate it |

## The monotone gate goes RED

Both perturbations were made in `lib/refine/refine.ml`'s `discharge` (the one entry every query
goes through), rebuilt, and run against a site baseline; the edit was reverted afterwards.

- **P1, every query undecided** (stage 1 dropped): `if ground_verified vc then Verified else`
  became `if false then …`, and the final `match result with Unsat -> Verified | …` became
  `ignore result; Unverified`. The full `monotone` sweep was cut off by an external stop after 427
  of 553 fixtures (all 418 `test/native` files and 9 stdlib files; the machine's load average was over
  380 from other sessions, and P1 is ~4x slower per file). The mode's own comparison, run on those
  427 fixtures against the matching baseline rows, exits 1:
  `RED: 73081` (46,607 `proved -> skip`, 11,529 `disappeared (proved)`, 14,945 `appeared (skip)`),
  for example `proved -> skip  native_actor_call_canonical stdlib/array.march:367:5 postcondition
  empty pvec_length(_) == 0`.
- **P2, an unconditional `false` fact**: `let vc = { vc with Smt.assumptions = Smt.BoolLit false ::
  vc.Smt.assumptions } in` at the top of `discharge`. Run on a 24-fixture subset (the 22
  `test/native` files with the most user-code sites, plus `stdlib/list.march` and
  `stdlib/json.march`) against an unperturbed run of the same subset: `new proofs: 903` (all
  `skip -> proved`, e.g. `stdlib/aho_corasick.march:102:10 precondition Array.get _ >= 0 && _ <
  pvec_length(v)`), `RED: 0`, `withdrawn violations: 0` (no violated site in the subset). That is
  what §6.2 asks of this perturbation: the vacuous proofs are listed for review, not silently
  accepted.
- **Control:** a second unperturbed run of the subset against the first: `RED: 0`, `new proofs: 0`,
  `new violations: 0`, `withdrawn violations: 0`.

A trap found on the way: the first full site baseline (`refine-oracle.sh check`, run with this
branch's compiler) was taken while `_build/default/stdlib` was still the copy staged before
45020b2e4 changed `stdlib/datetime.march` (`dune build bin/main.exe` does not restage the stdlib).
A later full build restaged it, and an unperturbed subset run then showed 2,405 RED rows, all stdlib
line shifts (`datetime.march:767` vs `:755`). The P2 and control runs above use a baseline taken
after the restage. The `baseline`/`check` and IR results below are unaffected: both sides of each
comparison read the same staged copy.

## Oracles (private HOME, z3 4.16.0 locally; CI runs 4.8.12)

Baselines were taken with origin/main's compiler (`5d78b341b`) before any edit, then checked with
this branch's:

- `scripts/refine-oracle.sh check`: `REFINEMENT DIAGNOSTICS IDENTICAL (8746 lines over 553
  fixtures)`. The check run already used `--refine-report-sites=all` and split the site rows off, so
  this also shows the split leaves `--refine-report`'s output exactly as it was.
- `scripts/ir-oracle.sh check`: `IR IDENTICAL across 498 programs`.
- `--check --refine-report --refine-report-sites` over the same 553 fixtures, unsorted and
  byte for byte: identical (30,892 lines). The bare flag and `--refine-report` are unchanged.

## Probe (d) reproduced

`--reflect-report` over every `stdlib/*.march` and `test/native/*.march` (one private HOME), counting
top-level functions (any `mod` depth; local `fn`s and `impl` methods excluded; `main` included, as
the spec's denominator does), compared with §0.5's script (`refl/reflectable.py`, re-run on its own
sweep to get its reflected set by name):

| | spec: functions | report: functions | spec: reflectable | report: reflected |
|---|---|---|---|---|
| stdlib | 3,947 | 3,947 | 817 | 717 (-12.2%) |
| test/native | 2,186 | 1,802 | 384 | 294 |

Stdlib is outside the ±10% by 2 points; every difference is attributed:

- **Stdlib, in the script only (105):** 65 are callers of a function dropped for one of the
  reasons below (R6 chain). The direct causes: 12 R11 (`empty` 9, `singleton` 2, `member` 1; the
  script has no R11); 6 R4 (a non-literal divisor outside `cap no_panic`, which §0.5 counted (8) but
  did not exclude); 7 R6 `==` at an `Option` instance (the stdlib `impl Eq(Option)` dispatches `==` on
  its payload to every `Eq` impl, itself included, so its SCC has no certificate:
  `unproved:no-int-parameter`); 4 R6 `<`/`>`/`>=` at `String` and 2 R6 `compare` dispatch at a type
  variable (the over-count §0.5 warns of: "comparisons … counted as encodable whatever their type");
  7 R8 (`Atom` parameter or result 4, `Unit` result 3); 2 R7 (a function-typed parameter the script's
  type walk missed).
- **Stdlib, in the report only (5):** `Gen.scale_float`, `Math.lerp`, `Plot.data_range`,
  `Stats.ab_of` use `+.`/`*.`, which §2.3 allows as opaque symbols and the script's table lacks;
  `Result.collect` calls `reverse` through a `use`, which the script's lexical resolution leaves
  unresolved (§0.5's "an undercount").
- **Native denominators:** the script counts 380 compiler-generated declarations (session-type
  expansion, no source span: `<none>:0`); the report filters rows to user spans exactly as
  `--termination-report` does, so they are not listed. On real spans the script has 1,806
  functions to the report's 1,802 (4 in fixtures that stop before the refinement pass).
- **Native reflected:** of the script's 355 distinct keys, 56 are those generated functions;
  278 agree; 21 are script-only (4 `compare` dispatch at a type variable, 3 `<` at `String`,
  4 `==` at `Option`/`List` (the uncertified `Eq` SCC above), 3 R6 chain, 2 SIMD `F32x4` results and
  3 other R8, 1 R11 `len`, 1 R4 divisor); 16 are report-only, all `Float` arithmetic (`+.`, `*.`) the
  script did not allow.

(This sweep ran on the pre-45020b2e4 staged stdlib described above; that commit only switched
`DateTime.from_timestamp` to the floor builtins and deleted `datetime.march`'s private
`floor_div`/`floor_mod`, so on the current stdlib that file has two fewer rows; the sweep was not
re-run.)

The D18 functions come out as §0.5 says: `List.append`, `reverse` (and `reverse/go`), `take`
(`take/go`), `drop` reflected; `filter` is `R7:takes a function-typed parameter pred`.
