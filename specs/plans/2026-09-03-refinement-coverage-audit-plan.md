# Plan: refinement coverage audit

Design: `specs/2026-09-03-refinement-coverage-audit-design.md`.
Branch: `claude/refinement-coverage-audit`. Base: `dc3361f9`.

Four tasks. Each ends in one commit, an independent review, and at most five fix
loops. The oracle baseline for the whole plan is `dc3361f9`.

## Shared facts

Established by exploration; verify each before relying on it, line numbers drift.

- `A.TyRefine of ty * name option * expr` (`lib/ast/ast.ml:136`) has **no span of
  its own**. Every site span must be synthesised from a neighbour: the parameter
  name span, the clause span, the function name span, the field name span, or the
  predicate expression's own span. Say which one you used in the site record.
- The existing whole-type traversal is `warn_predicate_ty`
  (`lib/refinecheck/refine_check.ml:668`), `ty_has_refinement` (`:685`),
  `warn_predicate_expr_tys` (`:799`), driven by `warn_predicate_decls` (`:856`),
  called last in `check_module` (`:1974`). `warn_predicate_decls` and
  `visit_decl` are **exhaustive over `A.decl` with no wildcard on purpose**, so a
  new declaration form breaks the build. Preserve that discipline in anything you
  fork from them.
- Two positions the warning walk skips and the enumerator must not:
  `A.DType`/`A.DAlwaysLinearType` field and variant-argument types (skipped at
  `:936` on the stated ground that a refinement in a type definition is checked
  where it is used, which the nested-refinement todo falsifies), and `A.DActor`
  handler parameter types (`:900`, which walks bodies but not `ah_params`).
- The extractors the checker actually uses, which the audit must call rather than
  reimplement: `refined_param_ty` (`lib/refinecheck/refine_scope.ml:344`),
  `refined_scope_ty` (`:441`), `return_refine_sorted` (`:369`),
  `return_refine_ext` (`lib/refinecheck/refine_post.ml:41`). All match only an
  outermost `A.TyRefine`. `refine_check` includes `refine_post` which includes the
  rest, so all are callable from the audit without a new dependency.
- A return refinement has a second enforcement path: `check_post_induction`
  (`refine_post.ml:624`), guarded on an ADT base that is not a record, a single
  clause, and no clause guard. A return site is enforced if `return_refine_ext`
  accepts it **or** that guard would match. Model both or the audit reports false
  holes for every ADT return contract.
- `--refine-report` is a `bool ref` in `bin/main.ml` registered at `:4250`, read
  at `:1052` and `:1747`, in two pipelines. `~measure_axioms` (`:1050`, `:1745`)
  is the precedent for threading an option into `check_module`.
- `--check` short-circuits on a warm CAS and exits before printing any report.
  `rm -rf .march/cas/artifacts-v2` before every measurement run, or you measure
  nothing. This has bitten this repo repeatedly.
- Test helpers in `test/test_refinecheck.ml`: `ledger_counts`, `ledger_counts3`,
  `skip_reasons`, `skip_reason_details`, `refine_error_text_d`, `contains`,
  `gated`. The `walk-coverage` group (`:5811`) is the closest existing apparatus
  for "did the walk reach this declaration form" and is the model for Task 1's
  tests.

## Task 1: enumerate every declared refinement occurrence

**Files:** new `lib/refinecheck/refine_audit.ml` (+ `.mli`); `test/test_refinecheck.ml`.

Produce `Refine_audit.sites : A.decl list -> site list` where

```ocaml
type position =
  | Param of string * int        (* function name, 0-based index *)
  | Return of string
  | Let_annot of string
  | Field of string * string     (* type name, field name *)
  | Variant_arg of string * string * int
  | Type_arg                     (* nested inside a TyCon argument *)
  | Arrow_domain | Arrow_codomain
  | Lambda_param of int
  | Expr_annot
  | Sig_fn of string | Extern_fn of string | Iface_method of string
  | Actor_handler_param of string * int

type nesting = Outermost | Nested   (* Nested = below the top of the declared type *)

type site =
  { span : A.span
  ; predicate : string
  ; origin : position    (* declaration-level, never relabelled *)
  ; position : position  (* immediate structural container *)
  ; nesting : nesting
  }
```

`origin` was added by Task 1's review. A sig or interface signature with any
argument is a `TyArrow`, so its refinement is always `Nested` and its `position`
is an arrow side. Without `origin`, Task 2 cannot tell a position the compiler
already warns about from a genuine hole.

`nesting` is the distinction the whole design turns on and it must come from the
traversal's own depth, not from re-inspecting the type afterwards.

**Tests** (new group `audit-sites`): one fixture module declaring a refinement in
every position the enumerator claims to cover, asserting the exact multiset of
`(position, nesting)` pairs. Then one negative fixture per position, deleting that
refinement, asserting the count drops by exactly one. A test that only asserts a
total is not discriminating; assert the multiset.

**Mutation:** delete the `DType` arm; the record-field fixture must redden. Delete
the `TyCon` argument recursion; the type-argument fixture must redden.

Commit: `refine: enumerate every declared refinement occurrence`.

## Task 2: classify each site

**Files:** `lib/refinecheck/refine_audit.ml`; `test/test_refinecheck.ml`.

Produce `Refine_audit.classify : ... -> site -> disposition` with

```ocaml
type disposition =
  | Enforced
  | Inert_warned of string      (* which warning already covers it *)
  | Unenforced of string        (* why nothing checks it *)
```

Rules, in this order:

1. `origin` is `Sig_fn`, `Extern_fn` or `Iface_method`: `Inert_warned`, naming the
   existing warning (`warn_sig_fn_refinement` and its siblings,
   `refine_check.ml:700-798`). This rule runs FIRST, before the nesting rule,
   because such a signature is always nested. Assert the warning really fires for
   that position rather than assuming it; if it does not, the site is
   `Unenforced`, which is a finding.
2. `nesting = Nested`: `Unenforced "below the outermost position of the declared
   type"`. Every extractor matches only an outermost `TyRefine`.
3. `Param` and `Lambda_param`: `Enforced` if `refined_param_ty` accepts the
   declared type, else `Unenforced` with the reason.
4. `Return`: `Enforced` if `return_refine_ext` accepts, or the
   `check_post_induction` guard would match. Else `Unenforced`.
5. `Let_annot`: `Enforced` if `refined_scope_ty` accepts.
6. `Field`, `Variant_arg`, `Type_arg`, `Arrow_*`, `Expr_annot`,
   `Actor_handler_param`: `Unenforced`, each with its own reason string. Do not
   collapse these into one message. The accepted precedent
   (`specs/progress/2026-07-31-refine-sig-and-extern-signature-refinements-inert.md`)
   is that a shared remedy gives wrong advice somewhere.

Call the extractors. Do not restate their rules inline. If an extractor cannot be
called for a position, the classifier must return `Unenforced` with a reason
saying the audit could not consult the checker, never a guess.

**Tests** (group `audit-classify`), each asserting the exact disposition:
- `fn f(n : {Int | _ > 0})` uncalled: `Enforced`. This is the false-positive case
  the design exists to avoid; it must be pinned.
- `fn f() : {String | _ == "a"}`: `Unenforced`.
- `fn f() : {Int | _ > 0}`: `Enforced`.
- an ADT return contract that `check_post_induction` proves today: `Enforced`.
- `type Box = { v : {Int | _ > 0} }`: `Unenforced`, nested.
- `List({Int | _ > 0})` as a parameter type: `Unenforced`, nested.
- a `sig` refinement with an argument (`fn put : Int -> {Int | _ > 0}`):
  `Inert_warned`. A nullary one is not enough; the arrow case is the one that
  breaks if the rules are ordered wrongly.
- an actor state field refinement: `Unenforced`.

**Mutation:** make rule 4 consult only `return_refine_ext`; the ADT fixture must
redden. Make rule 2 unconditional; the uncalled-parameter fixture must redden.
Swap rules 1 and 2; the `sig` arrow fixture must redden.

Commit: `refine: classify each declared refinement as enforced, inert or unenforced`.

## Task 3: the flag

**Files:** `lib/refinecheck/refine_check.ml` (call the audit at the join point and
expose the result), `bin/main.ml` (flag, printer, both pipelines);
`test/test_refinecheck.ml`.

Thread an option into `check_module` the way `~measure_axioms` is threaded, so the
audit runs only when asked. Register `--refine-audit` beside `--refine-report` and
print in both pipelines at the same point the report prints, on the same side of
the inference probes that reset the ledger.

Output: one line per `Unenforced` site, with the span, the position, the
predicate, and the reason. Then a three-line summary of the bucket counts. Slice
user code from stdlib the way the report does, since most declared refinements
live in the stdlib and a single number over both is unreadable.

The audit changes no verdict, emits no diagnostic, and does not escalate under
`cap verified`. Assert that: a fixture with an `Unenforced` site and `cap
verified` must still exit 0 with the audit off, and must still exit 0 with it on.

**Tests** (group `audit-flag`): the printed output for a small fixture, pinned
exactly. A test that the flag off produces no output. A test that verdicts are
identical with the flag on and off, over a fixture that proves, violates and skips.

Commit: `refine: add --refine-audit`.

## Task 4: baseline, ratchet, record

**Files:** `test/refine_audit/` (baseline), the test driver, `.github/workflows/ci.yml`,
`docs/refinement-types.md`, `specs/lang/refinement-types.md`, `CHANGELOG.md`,
`specs/progress/`, `specs/todos/`.

1. Run the audit over the corpus the refinement oracle walks
   (`test/native/*.march` and `stdlib/*.march`, about 300 files), under a private
   `HOME`, clearing `.march/cas/artifacts-v2` first. Record the bucket counts and
   the `Unenforced` sites grouped by position kind.
2. Commit that output as a baseline with a regeneration path modelled on the TIR
   snapshots (`UPDATE_SNAPSHOTS=1`), plus a test that diffs against it. Include
   the same vacuity guard the oracle has: refuse to record a baseline with
   implausibly few files or lines.
3. Add a CI step beside the existing refinement ratchet asserting the
   `Unenforced` count does not rise.
4. Docs: a section in both reference copies explaining what the audit asserts,
   what the three buckets mean, and why an uncalled refined parameter counts as
   enforced. Generate every quoted output from the compiler.
5. File one todo per position kind that appears in the `Unenforced` baseline and
   does not already have one, each with a runnable reproducer and its count.
   Cross-reference the two existing todos rather than duplicating them.
6. CHANGELOG under `### Added`. Progress record with the baseline table. Set the
   design status to landed.

Commit: `docs: record the refinement coverage audit and its baseline`.

## Gates for every task

`z3` on PATH. `rm -rf .march/cas/vc` once before a verdict run. One foreground
`./_build/default/test/test_refinecheck.exe -e`, one process, no polling.
`dune build --root .` always. `@types-check --force` and `@grammar-check --force`
with non-empty pass lines. `scripts/check-docs.sh`. Plain style in all prose, no
em dashes. Commit named files only, no attribution lines, no push.
