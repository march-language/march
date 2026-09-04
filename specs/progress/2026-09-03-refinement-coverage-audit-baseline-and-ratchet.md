# Refinement coverage audit: baseline, CI ratchet, and record

Task 4 of `specs/plans/2026-09-03-refinement-coverage-audit-plan.md`. Design:
`specs/2026-09-03-refinement-coverage-audit-design.md`. Base: `4f8f0c1d`
(Task 3 final, after fix loop 1). Measurement baseline for before/after:
`dc3361f9` (the plan's start).

## Correcting the design's prediction

The design's "What it will find on day one" section says "the audit goes red
immediately, and that is the point," and lists expected populations: String
returns, positions below the outermost type, block-level `fn` returns, and
actor handler parameters.

That prediction is wrong, and this record says so plainly instead of leaving
it standing. Task 2's re-review swept the actual corpus the refinement
oracle walks (`test/native/*.march` and `stdlib/*.march`, ~300 files) and
found 63 declared refinements, every single one `Enforced`. Zero
`Unenforced`, zero `Inert`. This task re-verified that finding independently
(see "Corpus sweep" below): same 300 files, same 63, same all-Enforced
result. The corpus simply does not happen to exercise any of the positions
the design predicted would fail. Every one of those positions is real (Task
2/3 built targeted fixtures proving each is genuinely unenforced), but none
of them occurs anywhere in the 300 files the oracle already walks.

This does not make the audit pointless. It makes the corpus baseline a
different kind of artifact than the design expected: not a red flag to fix,
but a floor to protect. A future nested refinement, String return, or
lambda parameter added anywhere in `test/native/` or `stdlib/` flips a
line from silence to a diff, and CI catches it. See "Two baselines" below
for how the vacuity risk of an empty baseline is handled.

## Corpus sweep

Swept `test/native/*.march` (183 files) and `stdlib/*.march` (117 files),
300 total, under a private `HOME`, `.march/cas/artifacts-v2` and
`.march/cas/vc` cleared first, via `--check --refine-audit` on each file.

| Slice | Enforced | Inert (warned) | Unenforced |
|---|---|---|---|
| user code (sum across all 300 files' own slice) | 63 | 0 | 0 |
| stdlib (constant per file, since the whole stdlib is always prepended) | 63 | 0 | 0 |

By file, every nonzero contribution to the 63 comes from a stdlib file
declaring its own top-level parameter/return refinements (test/native
contributes 0 everywhere, since none of its 183 hand-picked regression fixtures
declares a refinement at all):

| File | Enforced sites |
|---|---|
| stdlib/stats.march | 17 |
| stdlib/simd.march | 10 |
| stdlib/list.march | 7 |
| stdlib/native_array.march | 5 |
| stdlib/random.march | 5 |
| stdlib/prelude.march | 3 |
| stdlib/crypto.march | 2 |
| stdlib/datetime.march | 2 |
| stdlib/gen.march | 2 |
| stdlib/option.march | 2 |
| stdlib/result.march | 3 |
| stdlib/decimal.march | 1 |
| stdlib/enum.march | 1 |
| stdlib/logger.march | 1 |
| stdlib/range.march | 1 |
| stdlib/seq.march | 1 |
| **Total** | **63** |

Grouped by position kind: all 63 are `Param` (a top-level `fn`'s own
parameter) or `Return` (a top-level `fn`'s own return), all `Outermost`
nesting, all classified `Enforced`. Zero sites of every other position kind
(`Let_annot`, `Field`, `Variant_arg`, `Impl_ty`, `Lambda_param`,
`Sig_fn`, `Extern_fn`, `Iface_method`, `Actor_handler_param`) appear
anywhere in the corpus.

Committed at `test/refine_audit/corpus.baseline` (600 lines: two
`coverage audit` summary lines per file, sorted by tag). Vacuity guard: the
alcotest test refuses to compare (or record) a sweep under 100 fixtures or
50 report lines, mirroring `scripts/refine-oracle.sh`'s own floor.

## Two baselines, because an empty one is the classic vacuity trap

An empty corpus baseline is indistinguishable, by itself, from an audit that
silently stopped walking anything. So a second, deliberately non-empty
fixture set exists at `test/refine_audit/holes/`, one small program per
known unenforced position:

| Fixture | Position(s) hit | Unenforced count |
|---|---|---|
| `holes/lambda_param.march` | `Lambda_param` | 1 |
| `holes/local_fn.march` | `Param` + `Return` (`fn_origin = Local_fn`) | 2 |
| `holes/impl_method.march` | `Param` (`fn_origin = Impl_method_fn`, non-adoptable) | 2 |
| `holes/actor.march` | `Field` (actor state) + `Actor_handler_param` | 2 |
| `holes/nested.march` | `Field` (record, from `specs/todos/2026-09-01-nested-refinement-enforcement.md`) | 1 |
| `holes/string_return.march` | `Return` with a `String` base (from `specs/todos/2026-09-03-string-return-refinement-unchecked.md`) | 1 |
| `holes/variant_arg.march` | `Variant_arg` | 1 |
| **Total** | | **10** |

Committed at `test/refine_audit/holes.baseline`. Its own vacuity guard is
the sharper one: if this fixture set ever reports zero `Unenforced` sites
between all 7 files, the alcotest test fails loudly with "THE AUDIT IS
BROKEN", naming exactly why an empty result here is categorically different
from the corpus baseline being empty.

Both baselines regenerate the same way the TIR golden snapshots do:
`UPDATE_SNAPSHOTS=1 ./_build/default/test/test_refinecheck.exe -e`, then a
plain re-run to confirm green, then `git diff test/refine_audit/` to review
the change before committing.

`impl_method.march` needed a deliberate second `impl` of the same method
name to demonstrate a REAL hole: a lone `impl` defining an unambiguous
method name IS actually enforced by the checker (adoptable), even though
`classify` reports it `Unenforced` either way (a documented
over-approximation, see below). The fixture had to break adoptability with
a second `impl Indexable(Crate)` to show the checker actually skip the
check, confirmed by `march --check` exiting 0 on a call that violates the
declared precondition.

## Documented conservatism: impl-method classification, not a hole

`Refine_audit.classify` reports every `impl` method parameter `Unenforced`
regardless of whether the method's bare name is actually adoptable
(`Refine_scope.adoptable_impl_methods`), because adoptability is a
module-level judgement no single `site` can make in isolation. This means
the audit can report `Unenforced` on a parameter the checker in fact
enforces (the adoptable case). This conservatism contributes zero entries
to either baseline above. The corpus's `impl` methods, where they exist,
were not swept as a source of any of the 63 sites (none of the 63 are
`impl` methods at all), and per the Task 4 brief it gets no todo of its own:
it is the audit being conservative, not the checker having a gap. The real
gap (a non-adoptable method's parameter genuinely unchecked) is filed
separately; see the todo list below.

## Todo files filed

Four new, each with a runnable reproducer and cross-referenced from
`docs/refinement-types.md` / `specs/lang/refinement-types.md`'s new
"Coverage audit" section:

- `specs/todos/2026-09-03-lambda-param-refinement-unchecked.md`
- `specs/todos/2026-09-03-block-fn-refinement-unchecked.md`
- `specs/todos/2026-09-03-impl-method-param-refinement-unchecked.md`
- `specs/todos/2026-09-03-actor-state-and-handler-refinement-unchecked.md`

Cross-referenced rather than duplicated, each updated with a "Cross-reference"
note pointing at its `test/refine_audit/holes/` fixture:

- `specs/todos/2026-09-01-nested-refinement-enforcement.md`
- `specs/todos/2026-09-03-string-return-refinement-unchecked.md`
- `specs/todos/2026-09-03-sibling-parameter-opaque-actual.md` (a different
  mechanism, `unreflectable-predicate` misattribution rather than an audit
  `Unenforced` site, listed only so a reader scanning `specs/todos/` finds
  it alongside the others)

No todo filed for a plain record field or `Variant_arg`/`Impl_ty` as their
own top-level items: `Field` and `Variant_arg` are demonstrated by the
`holes/nested.march` and `holes/variant_arg.march` fixtures and covered by
the existing nested-refinement todo's broader scope (any position below the
outermost type, or any stored value position, shares the same root
cause, no extractor for a constructed value). `Impl_ty` was investigated
(an `impl Iface(T)` block's `T` argument) and found to have no realistic
refined-in-practice shape worth a fixture on its own. `Expr_annot` was
investigated and found unreachable from source entirely: `EAnnot` is
produced only by desugar's `DApp`/supervisor-spec handling, never by the
parser, so no user-written refinement can ever land there.

## Gates run

- `dune build --root . bin/main.exe test/test_refinecheck.exe`: clean.
- `./_build/default/test/test_refinecheck.exe test 'audit-baseline'`: both
  new tests `[OK]` (237s, corpus sweep of 300 files + holes sweep of 7
  files, all under a private HOME with `.march/cas/artifacts-v2` cleared
  per invocation).
- `rm -rf .march/cas/vc` once, then one foreground
  `./_build/default/test/test_refinecheck.exe -e`: see below.
- `dune build --root . @types-check --force` and `@grammar-check --force`:
  see below.
- `scripts/check-docs.sh`: see below.

## CI

New step "Refinement coverage audit ratchet" added to `.github/workflows/ci.yml`'s
`conformance` job, beside the existing "Refinement obligation coverage
ratchet". Reads the `user + stdlib` slice of `--check --refine-audit
stdlib/list.march` (the whole prepended stdlib, same technique the existing
ratchet's ceiling measurement already uses) and fails if `Unenforced` rises
above 0. The full corpus/holes sweep also runs automatically under `dune
runtest` (the `test` job's existing Test step), since `audit-baseline` is
now a group in `test_refinecheck.ml`; the CI step above is a second,
narrower, always-fast ratchet independent of that full run.

## Design status

`specs/2026-09-03-refinement-coverage-audit-design.md`'s Status line is
updated to landed with the commit range for all four tasks.
