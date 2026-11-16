# Refinement must-reject corpus

Every program in `reject/` holds one obligation the refinement checker must report
**violated**, with a counterexample or the offending value in the diagnostic.
`check_refine.sh` runs them; CI's `conformance` job calls it.

`scripts/refine-oracle.sh` pins the diagnostics the checker prints today, and before this
corpus no fixture it swept had a violated obligation. A change that made the checker prove
everything left that oracle, and every other refinement gate in CI, green. This corpus is
the gate that goes red (shown in `specs/progress/2026-11-11-refine-must-reject-corpus.md`).
The typechecker's counterpart is `specs/lang/types/reject/` with `check_types.sh`.

## What a fixture declares

```march
-- EXPECT-VIOLATED: precondition need_pos
-- EXPECT-ERROR: for example, when `k` is
```

- `EXPECT-VIOLATED: <kind> <callee>` names the ledger row `march --check
  --refine-report-sites=all` must list as `violated` in user code. `<kind>` is one of
  `precondition`, `postcondition`, `division`, `overflow`; `<callee>` is the row's fifth
  column, spaces included (`let ys`).
- `EXPECT-ERROR: <text>` is a piece of the rendered diagnostic. Keep it free of a
  solver-chosen witness value where another value would be as good an answer.

A fixture passes only if `--check` exits 1, the row is listed and the text is printed. A
site that is proved, skipped or files no obligation fails. So a kind whose only failing
verdict is a skip cannot be in this corpus; see "Not here" below.

Each fixture runs from a fresh working directory under a private `HOME`. The VC cache lives
in `<cwd>/.march/cas`, and a warm one replays a stored counterexample without asking the
solver. z3 must be on `PATH`; the runner stops with a message if it is not.

```bash
specs/lang/refine/check_refine.sh                  # the corpus
REFINE_ONLY=k0,s03 specs/lang/refine/check_refine.sh   # by name prefix
```

## `k`: one fixture per obligation kind

| Fixture | Kind | Row |
|---|---|---|
| `k01_precondition` | a call argument against a parameter refinement | `precondition need_pos` |
| `k02_return_refinement` | a function body against its return refinement | `postcondition bad` |
| `k03_division_safety` | a divisor under `cap no_panic` | `division n` |
| `k04_int_overflow` | arithmetic under `cap no_panic` | `overflow +` |
| `k05_element_demand` | a container's elements against an element refinement | `precondition sum_pos` |
| `k06_lemma` | a `@[lemma]`'s theorem on a path of its body | `postcondition inc_small` |
| `k07_handler_ensures` | a two-state handler guarantee (`ensures`, `old`) | `postcondition Account.Steal.ensures` |
| `k08_message_payload` | an actor message's argument at the `send` | `precondition Add` |
| `k09_callable_domain` | a refined callable passed where a wider domain is expected | `precondition dec` |
| `k10_actor_invariant` | an actor's `@invariant` after a handler | `postcondition Account.Take` |

## `s`: one fixture per soundness bug already fixed

Each was reported **proved** before its fix. The header of each file names the progress
entry.

| Fixture | The false proof |
|---|---|
| `s01_element_demand_caller_namespace` | an element slot naming the callee's parameter was read against the caller's variable of that name |
| `s02_return_tail_inner_binder` | a `match` binder shadowing a refined parameter made the path contradictory |
| `s03_ctor_user_option_beside_builtin` | a user `type Option` beside the built-in: one constructor was taken to exhaust it |
| `s04_ctor_second_declaration_same_module` | a second `type` of one name in a module: the last declaration was taken to be all of it |
| `s05_let_annotation_unchecked` | a refined `let` annotation was assumed, never checked |
| `s06_division_in_impl_method` | `cap no_panic` did not read `impl` method bodies |
| `s07_caller_refinement_names_rebound` | a parameter's refinement naming `n` survived `let n = 0` |

Most fixed false proofs are **not** here, because the fix made the site a recorded skip, and
a skip does not pass this runner. Those are pinned under `cap verified`, where a skip is an
error, by `specs/lang/types/reject/` (`t327`-`t330`, `t363`, `t383`-`t385`, `t402` and
others) and by the `test_refinecheck` groups each progress entry names.

## `a`: known accepted

`known-accepted.txt` lists the fixtures the checker wrongly accepts today. Each has an open
todo. A listed fixture passes only while it is still accepted; when a fix makes it
violated the run fails until its line is removed and `KNOWN_ACCEPTED_MAX` in
`check_refine.sh` is lowered. The list may only shrink.

| Fixture | Todo |
|---|---|
| `a01_callback_param_element_demand` | `specs/todos/2026-10-18-callback-param-element-demands-unchecked.md` |
| `a02_multi_param_callable_domain` | `specs/todos/2026-10-18-multi-param-callable-domain-unobliged.md` |
| `a03_session_payload` | `specs/todos/2026-11-11-session-payload-refinement-unchecked.md` |

## Not here: kinds with no "violated" verdict

- **Fold invariant.** A fold whose base or step breaks the demanded or annotated invariant
  is a skip (`accumulator-base-unproved`, `accumulator-step-unproved`), never a violation
  (`specs/lang/refinement-types.md`, "Folds: an accumulator invariant"). Pinned under `cap
  verified` by `specs/lang/types/reject/t381`, `t382`.
- **Termination metric.** A recursive call that does not decrease its metric is a skip
  (`not-decreasing`) with a `termination_unproved` diagnostic, an error only under `cap
  total`. Pinned by `test/errors/termination_unproved_*`.
- **Protocol (session) payload refinement.** No obligation exists at all, so it is in the
  known-accepted list (`a03`). The actor-message form is `k08`.

## Adding a fixture

Name it `k`/`s`/`a` + the next number + a slug, give it the two `EXPECT` lines, and add a
row above. A new known-accepted entry needs its own todo and a deliberate raise of
`KNOWN_ACCEPTED_MAX`. The fixture is also swept by `scripts/refine-oracle.sh`, so a branch
that adds one shows it as a change there.
