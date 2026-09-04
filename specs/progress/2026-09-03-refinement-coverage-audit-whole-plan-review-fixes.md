# Refinement coverage audit: whole-plan review fix wave

Follows `specs/progress/2026-09-03-refinement-coverage-audit-baseline-and-ratchet.md`.
Review: `.superpowers/sdd/refinement-coverage-audit/whole-plan-review.md`.
Tree was clean at `7acf5423` before this wave.

## Root cause shared by findings 1 and 2

`Refine_audit.sites` walked only the POST-desugar declaration list, which
`Refine_check.check_module` always receives. Two desugar transforms
falsify the audit against that list:

- A multi-head function's clause merge (`Desugar.desugar_fn_def`'s general
  path, `mk_named_param`) rebuilds every parameter with `param_ty = None`
  before the audit ever runs. A declared refinement there has no site at
  all, not even `Unenforced` (finding 2, the more serious of the two).
- A default-argument function (`expand_defaults_decl`) survives only under
  mangled arity-variant names (`f$2`, `f$1`, ...). A refined parameter that
  lands on the surviving decl gets a real `Enforced` verdict from the
  checker's own extractor, but no plain call written under the original
  name can ever resolve to it (finding 1, a false `Enforced`).

## The fix: diff pre-desugar sites against post-desugar sites

`Refine_check.check_module` gained an optional `?pre_desugar_decls`
argument (`lib/refinecheck/refine_check.ml`/`.mli`). When given (bin/main.ml
passes the entry file's own decls, captured right after parsing and before
`Desugar.desugar_module` runs, at both CLI call sites), the audit sink now
computes:

```
post_sites = Refine_audit.sites m.mod_decls              (* as before *)
dropped    = Refine_audit.desugar_dropped
               ~pre:(Refine_audit.sites pre_desugar_decls) ~post:post_sites
result     = dropped as Unenforced ++ post_sites via classify
```

Omitting `?pre_desugar_decls` (every caller before this fix, including
every existing alcotest group that calls `check_module` directly) keeps
behavior byte-identical to before: `desugar_dropped` has nothing to
compare and returns nothing.

## The matching rule, and why it needed a Return exception

`desugar_dropped`'s key is `(origin, predicate)` for every position except
`Return`, which matches by `predicate` alone. Justification (also recorded
as a comment in `lib/refinecheck/refine_audit.ml`):

- **Span alone is not sufficient.** `expand_defaults_decl` keeps a
  stripped-default parameter's exact `A.ty` node, span included, on the
  surviving mangled decl. Matching by span would call the site "found" and
  reproduce finding 1 exactly.
- **Name (via `origin`) alone is not sufficient.** A multi-clause
  function's `walk_fn` emits one `Param(name, idx)` per clause, so two
  clauses could in principle refine the same parameter position
  differently; predicate text disambiguates without needing full span
  comparison.
- **Name IS the part that must be checked for `Param`,** because a
  parameter's precondition is enforced at CALL SITES, which is exactly
  what a rename with no matching call-site rewrite breaks.
- **Name must NOT be checked for `Return`,** because a postcondition is
  checked once against a function's OWN body
  (`check_fn_post_verdict`/`return_refine_ext`), with no notion of a
  caller. `expand_defaults_decl` renames the whole declaration but does
  not touch `fn_ret_ty` or the body; the postcondition is genuinely still
  enforced on the renamed survivor. Proven directly: `t9.march` (`fn f(a :
  Int, b : Int \\ 1) : {Int | _ > 0} do a - b end`, called `f(0, 5)`) still
  errors under `cap verified` (`f$2` does not satisfy its return type
  constraint) both before and after this fix, and the audit now correctly
  reports its Return site `Enforced`, not `Unenforced` -- this is the
  reviewer's requested "legitimate desugar rewrite that is genuinely still
  enforced" fixture, proven by re-running that exact program before
  writing the Return exception (it misclassified as `Unenforced`) and
  after (it classifies `Enforced`).

**False-negative risk:** a desugar transform that renames a declaration
AND rewrites every call site to the new name would be reported dropped by
the `Param` rule (name changed, so no match), even though it is genuinely
still enforced. No such transform exists in this compiler today for a
function carrying a `Param` refinement -- `expand_defaults_decl` is the
only name-mangling transform touching one, and it does NOT rewrite call
sites at all (that absence is finding 1 itself, not a counterexample).

**False-positive risk:** negligible for `Param`/`Return` today, for the
same reason. For `Return`'s predicate-only match specifically, two
unrelated functions sharing identical return-predicate text could mask a
genuinely dropped return elsewhere; no transform in this compiler drops a
`Return` site's predicate (neither the multi-head merge nor
`expand_defaults_decl` touches `fn_ret_ty`), so this is a documented
theoretical risk, not an observed one.

## Verification

| Fixture | Before this fix | After this fix |
|---|---|---|
| `t6e.march` (finding 1, default-arg param) | `1 enforced, 0 unenforced`, exit 0 despite violation | `1 enforced, 1 unenforced`, still exit 0 (checker hole remains; audit no longer hides it) |
| `t8c.march` (finding 2, multi-head param) | `0 enforced, 0 unenforced` (no site at all) | `0 enforced, 1 unenforced` (site now exists, correctly classified) |
| `t9.march` (default-arg RETURN, control) | `1 enforced, 0 unenforced`, exit 1 (real error) | unchanged: `1 enforced, 0 unenforced`, exit 1 |
| `plain.march` (unaffected control) | `1 enforced, 0 unenforced` | unchanged |

Corpus re-swept in full (300 files, `test/native/*.march` + `stdlib/*.march`):
byte-identical to the committed `test/refine_audit/corpus.baseline` (`diff`
empty). No corpus file uses a default argument or a multi-head function on
a refined declaration, so this fix changes nothing there, as expected.

`audit-flag` group (8 cases, shells to the real compiled driver): all still
`[OK]`, confirming the pinned fixtures' exact output is unaffected.

## New holes fixtures

Two for the blocking findings:

| Fixture | Demonstrates | Unenforced |
|---|---|---|
| `holes/default_param.march` | finding 1 | 1 |
| `holes/multi_head.march` | finding 2 | 1 |

Three for finding 4 (the design's fixture-coverage claim named these
positions as covered when they were not: only pinned by `audit-classify`
unit tests, no `holes/` fixture):

| Fixture | Position |
|---|---|
| `holes/type_arg.march` | `Type_arg` (`List({Int \| _ > 0})`) |
| `holes/arrow_domain.march` | `Arrow_domain` (a refined function-typed parameter's domain) |
| `holes/linear_wrapper.march` | nested under `TyLinear` |

`holes.baseline` regenerated (`UPDATE_SNAPSHOTS=1`), reviewed
(`git diff test/refine_audit/`: only additions, one block per new fixture,
`corpus.baseline` untouched), then re-run without the env var: green.

## Finding 3: CI ratchet gap closed

The CI step ("Refinement coverage audit ratchet") reads only
`stdlib/list.march`'s whole-program slice, so a rise in a `test/native`
fixture's own Unenforced count never moves it. `test/test_refinecheck.ml`'s
corpus-baseline case now also asserts `corpus_unenforced_ceiling` (0)
against the CURRENT sweep's summed `user code` Unenforced count, checked
UNCONDITIONALLY, including when `UPDATE_SNAPSHOTS=1` is set -- so
regenerating the baseline can never launder a real rise.

Proven RED: added a throwaway `test/native/zzz_simulated_ratchet_probe.march`
(a `linear {Int | _ > 0}` parameter) and ran `test 'audit-baseline'`:

```
FAIL: the corpus's own (user code) Unenforced count rose from 0 to 1. ...
2 failures! in 225.619s. 2 tests run.
```

(The holes case also failed as a side effect of the probe's exit code
interacting with the shared `home` sweep infrastructure in that run; the
ceiling assertion itself is what the review asked to be proven RED, and it
fired as designed.) Probe file removed (never committed) and confirmed
green again before proceeding.

## Finding 4: fixture-coverage sentence

Fixed by adding fixtures (`type_arg.march`, `arrow_domain.march`,
`linear_wrapper.march`) rather than only rewording, per the review's
preferred remedy. The design doc's correction paragraph now says so
explicitly, naming which fixtures were added and why.

## Finding 5: wrong `ty_has_refinement` pointer

Both comments (`lib/refinecheck/refine_check.ml`'s `?audit` block,
`bin/main.ml`'s `print_refine_audit` header) now say
`Refine_encode.ty_has_refinement`, matching where the function actually
lives.

## Finding 6: self-referential commit range

The design doc's Status line now reads "Commit range `5dbaf235..` through
the branch tip" instead of a fixed end hash, with a note explaining why
(the fixed-hash form was already wrong once, `b92ca446`, and went stale
again with `b92ca446` and `7acf5423` landing after the range naming them
was written).

## Finding 7 (LOW, not required): left open

The review flagged the two doc copies as paraphrases rather than
byte-identical text, explicitly marked "Not blocking." This wave's own
additions to both copies are ALSO paraphrases of each other (same claims,
different wording, matching the existing convention in both files) rather
than a byte-for-byte sync of the whole file, which was out of scope for
this fix wave and not requested by the coordinator's follow-up message.

## Docs

Both `docs/refinement-types.md` and `specs/lang/refinement-types.md` gained
a "Why the audit needs the pre-desugar AST too" subsection explaining the
mechanism, the Return exception, and pointing at the two blocking-finding
fixtures and the new todo.

## Todo filed

`specs/todos/2026-09-03-desugar-dropped-refinement-unchecked.md`: the
underlying checker hole (both shapes still exit 0 under `cap verified`
today; only the AUDIT's blind spot is fixed by this wave, not the
checker).

## Gates run

```
$ dune build --root . bin/main.exe test/test_refinecheck.exe
(clean)

$ dune build --root .
(clean, exit 0 -- full corpus/native golden build)

$ rm -rf .march/cas/vc
$ ./_build/default/test/test_refinecheck.exe -e
Test Successful in 560.491s. 693 tests run.
(693 [OK], 0 [FAIL], 0 [SKIP] -- z3 confirmed on PATH, /opt/homebrew/bin/z3)

$ dune build --root . @types-check --force
=== core-march-types: 303 passed, 0 failed ===

$ dune build --root . @grammar-check --force
=== grammar: 48 passed, 0 failed ===

$ ./scripts/check-docs.sh
doc-lint passed
```
