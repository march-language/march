# Refinement Types A1 — Typechecker Wiring — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `{T | predicate}` refinement types parse, typecheck, and — for Int/Bool preconditions — be verified at call sites by the A0 Z3 bridge (`lib/refine/`), with violations reported as compile errors and a clean fallback when z3 is absent.

**Architecture:** Split into two shippable increments. **A1a** (this plan, executed first) adds the surface syntax and plumbing *behavior-preservingly*: `{T|p}` parses to a new `Ast.TyRefine`, every exhaustive `Ast.ty` match gains an arm that treats it as its base type, and `surface_ty` erases the predicate — so refined annotations are accepted and ignored, with the full existing suite staying green. **A1b** (outlined here, separate execution) carries the predicate into the internal type, emits verification conditions at call sites, discharges them through `Refine.discharge`, and reports counterexamples.

**Tech Stack:** OCaml 5.3, menhir, the existing `march_typecheck`/`march_ast`/`march_parser` libraries, and `march_refine` (the A0 bridge: `Smt`/`Solver`/`Vc_cache`/`Refine`).

---

## Verified structures (from codebase exploration)

- **Surface `ty`** — `lib/ast/ast.ml:32-46`: `TyCon | TyVar | TyArrow | TyTuple | TyRecord of (name*ty) list | TyLinear | TyNat | TyNatOp | TyChan`. Params: `param = { param_name; param_ty : ty option; param_lin }` (`ast.ml:110-114`).
- **Type grammar** — `lib/parser/parser.mly:816-851`. Record production at `:850-851`: `LBRACE; fields = separated_nonempty_list(COMMA, ty_record_field); RBRACE { TyRecord fields }`; `ty_record_field: lower_name COLON ty` (`:853-854`). Atom alternatives include `INT`, `LOWER_IDENT`, `upper_name`, `LINEAR/AFFINE ty_atom`, parens, tuples.
- **Tokens** — `LBRACE RBRACE PIPE COLON UNDERSCORE` already declared (parser.mly header; `lexer.mll:122-170`).
- **Internal `ty`** — `lib/typecheck/typecheck.ml:79-96`; `constraint_` at `:123-128`; `scheme = Mono | Poly of int list * constraint_ list * ty` at `:134-136`.
- **`surface_ty`** — `typecheck.ml:2058` (`let rec surface_ty env ~tvars s`), arms `:2060-2163`.
- **`unify`** — `typecheck.ml:1946`.
- **Call-arg checking** — `infer_app` at `typecheck.ml:3874-3898`; the key line: `check_expr env arg param_ty ~reason:(Some (RFnArg (span, idx)))` (`:3878-3879`).
- **Project root for cache** — `bin/main.ml:866`: `Sys.getcwd ()`. `check_module_full` invoked at `main.ml:1006`.
- **Erasure** — there is **no separate strip pass**; refinements are erased simply by `surface_ty` not carrying them into the internal `ty` (A1a) or by the lowering boundary dropping them (A1b). TIR (`lib/tir/tir.ml:1-24`) has no refinement representation, so nothing downstream changes.
- **Exhaustive `Ast.ty` match sites needing a new arm** (8 files): `lib/ast/ast.ml`, `lib/dump/dump.ml`, `lib/format/format.ml`, `lib/refactor/refactor.ml`, `lib/search/search.ml`, `lib/tir/lower.ml`, `lib/typecheck/typecheck.ml` (surface_ty + others), `lsp/lib/analysis.ml`.

All worktree builds use `dune build --root .` and run binaries directly (see `scripts/run-tests.sh`); judge by exit code.

---

# A1a — Surface syntax + behavior-preserving plumbing

## Task 1: Add `TyRefine` to the surface AST

**Files:**
- Modify: `lib/ast/ast.ml:32-46` (add constructor) and any `ty` helper matches in that file.

- [ ] **Step 1: Add the constructor**

In `lib/ast/ast.ml`, add to the `ty` type (after `TyChan`):

```ocaml
  | TyRefine of ty * name option * expr
    (** Refinement type: { T | predicate } or { v : T | predicate }.
        Second field is the binder name (None means the implicit `_`).
        The predicate reuses the expression grammar; it is validated against
        the decidable fragment in the typechecker, not the parser. *)
```

Note: `expr` is defined later in the same recursive `type ... and ...` block, so `TyRefine` referencing `expr` requires `ty` and `expr` to be in the same `type ... and` group. They already are (the AST is one big recursive group). Confirm by building.

- [ ] **Step 2: Build to discover every non-exhaustive match**

Run: `dune build --root . 2>&1 | grep -v "shift/reduce" | grep -A3 "not matched\|TyRefine\|Error" | head -60`
Expected: a list of `Warning 8 [partial-match]` / non-exhaustive errors at the 8 sites. This is the worklist for Step 3.

- [ ] **Step 3: Add an erasing arm at each exhaustive `ty` match**

For each non-exhaustive site reported, add an arm that treats the refinement as its base type. The exact form depends on what the function returns; the **rule** is: delegate to the same handling as `base`. Concretely:

- `lib/ast/ast.ml` (pp/equality helpers, if any): `| TyRefine (base, _, _) -> <recurse on base>`.
- `lib/format/format.ml`: render as the base type — `| TyRefine (base, _, _) -> format_ty base` (so the formatter doesn't lose the program; full `{T|p}` rendering is an A1b nicety).
- `lib/dump/dump.ml`: `| TyRefine (base, _, _) -> dump_ty base`.
- `lib/refactor/refactor.ml`, `lib/search/search.ml`, `lsp/lib/analysis.ml`: recurse into `base` with the surrounding function's logic.
- `lib/tir/lower.ml`: `| Ast.TyRefine (base, _, _) -> <convert base>` — lowering must see only the base type.
- `lib/typecheck/typecheck.ml` `surface_ty` (and any other `Ast.ty` match): handled in Task 3; for now add `| Ast.TyRefine (base, _, _) -> surface_ty env ~tvars base` so it compiles and erases.

- [ ] **Step 4: Build clean**

Run: `dune build --root . 2>&1 | grep -v "shift/reduce" | grep -iE "error|warning 8" | head`
Expected: no output (no errors, no partial-match warnings).

- [ ] **Step 5: Full regression (behavior unchanged — nothing constructs `TyRefine` yet)**

Run the direct-binary suites:
```bash
dune build --root . test/run_compiler.exe test/run_eval.exe test/run_codegen.exe test/test_refine.exe
for t in run_compiler run_eval run_codegen; do _build/default/test/$t.exe -e >/tmp/a1_$t.log 2>&1; echo "$t=$?"; done
_build/default/test/test_refine.exe >/dev/null 2>&1; echo "refine=$?"
```
Expected: all `=0`.

- [ ] **Step 6: Commit**

```bash
git add lib/ast/ast.ml lib/format/format.ml lib/dump/dump.ml lib/refactor/refactor.ml lib/search/search.ml lib/tir/lower.ml lib/typecheck/typecheck.ml lsp/lib/analysis.ml
git commit -m "feat(refine): add TyRefine AST node (erasing arms, behavior-preserving)"
```

## Task 2: Parse `{T | p}` and `{v : T | p}`

**Files:**
- Modify: `lib/parser/parser.mly` (type grammar around `:850`).
- Test: a new parser unit test (or reuse `test/test_compiler.ml`'s parse path).

- [ ] **Step 1: Add refinement productions to `ty_atom`**

The disambiguation challenge: the record production `LBRACE separated_nonempty_list(COMMA, ty_record_field) RBRACE` shares the `{ lower_name : ty ...` prefix with the binder form `{ v : T | p }`. Restructure the `LBRACE ... RBRACE` alternatives so the token *after the first `ty`/field* (PIPE vs COMMA/RBRACE) drives the LR(1) decision. Replace the single record alternative with:

```menhir
  | LBRACE; t = ty; PIPE; p = expr; RBRACE
    { TyRefine (t, None, p) }
  | LBRACE; name = lower_name; COLON; t = ty; PIPE; p = expr; RBRACE
    { TyRefine (t, Some name, p) }
  | LBRACE; fields = separated_nonempty_list(COMMA, ty_record_field); RBRACE
    { TyRecord fields }
```

The binder form `{ name : ty | p }` and a one-field record `{ name : ty }` share a prefix up to `ty`; menhir resolves on the lookahead (`PIPE` → refine, `COMMA`/`RBRACE` → record). The no-binder form `{ ty | p }` starts with `ty` (e.g. `Int`) which a record field never does (fields start `lower_name COLON`), so it is unambiguous.

- [ ] **Step 2: Build and inspect for new grammar conflicts**

Run: `dune build --root . 2>&1 | grep -iE "conflict|reduce/reduce|Error" | head`
Expected: no *new* reduce/reduce conflicts and no errors. (The pre-existing "56 shift/reduce conflicts ... arbitrarily resolved" line is fine; a new **reduce/reduce** conflict is NOT — if one appears, the binder/record split needs a left-factored helper nonterminal `lbrace_body` that parses `lower_name COLON ty` once then branches on `PIPE` vs `COMMA`-list. Stop and apply that refactor before continuing.)

- [ ] **Step 3: Write a parse test**

Add to `test/test_compiler.ml` (mirroring its existing parse-test style; `parse_module` helper lives in `test_helpers`):

```ocaml
let test_parse_refinement_types () =
  let src =
    "mod M do\n\
    \  fn f(i : {Int | _ >= 0 && _ < n}) : Int do i end\n\
    \  fn g(d : {v : Int | v != 0}) : Int do d end\n\
     end\n"
  in
  let m = Test_helpers.parse_module src in
  (* The bodies are irrelevant; success = it parses and the params carry
     TyRefine annotations.  Assert by walking to the first fn's first param. *)
  Alcotest.(check bool) "parsed refined params" true
    (Test_helpers.module_has_refined_param m)
```

If `module_has_refined_param` does not exist, instead assert parse success only:

```ocaml
let test_parse_refinement_types () =
  let src = "mod M do fn f(i : {Int | _ >= 0}) : Int do i end end\n" in
  ignore (Test_helpers.parse_module src);
  Alcotest.(check pass) "parsed" () ()
```

Register it in `compiler_suites` next to the other parser cases.

- [ ] **Step 4: Run the parse test**

Run: `dune build --root . test/run_compiler.exe && _build/default/test/run_compiler.exe -e 2>&1 | grep -iE "refinement|fail|tests run" | tail`
Expected: the new case passes; suite total +1.

- [ ] **Step 5: Full regression**

Run the three runner binaries + test_refine as in Task 1 Step 5. Expected: all `=0` (the grammar change must not break existing parses).

- [ ] **Step 6: Commit**

```bash
git add lib/parser/parser.mly test/test_compiler.ml
git commit -m "feat(refine): parse {T|p} and {v:T|p} refinement annotations"
```

## Task 3: Confirm erasure — refined params typecheck as their base

**Files:**
- Modify: `lib/typecheck/typecheck.ml` (verify the `surface_ty` arm from Task 1 Step 3 is `surface_ty env ~tvars base`).
- Test: `test/test_compiler.ml`.

- [ ] **Step 1: Write a typecheck-equivalence test**

A function with a refined param must typecheck exactly like the bare-base version (predicate ignored in A1a):

```ocaml
let test_refined_param_typechecks_as_base () =
  let refined = "mod M do fn f(i : {Int | _ >= 0}) : Int do i + 1 end\n\
                 \  fn main() : Int do f(5) end end\n" in
  let bare    = "mod M do fn f(i : Int) : Int do i + 1 end\n\
                 \  fn main() : Int do f(5) end end\n" in
  Alcotest.(check bool) "refined typechecks" true (Test_helpers.typechecks refined);
  Alcotest.(check bool) "bare typechecks"    true (Test_helpers.typechecks bare)
```

(If `Test_helpers.typechecks` does not exist, use whatever boolean "compiles cleanly" helper the suite already uses — check `test_helpers.ml` for the existing `check`/`typecheck` helper and mirror it.)

- [ ] **Step 2: Run it (red if the surface_ty arm is wrong)**

Run: `dune build --root . test/run_compiler.exe && _build/default/test/run_compiler.exe -e 2>&1 | grep -iE "refined_param|fail" | tail`
Expected: PASS. If it fails to typecheck, the Task-1 `surface_ty` arm is not delegating to `base` — fix it to `| Ast.TyRefine (base, _, _) -> surface_ty env ~tvars base`.

- [ ] **Step 3: Full regression + commit**

Run the runner suites (all `=0`), then:
```bash
git add lib/typecheck/typecheck.ml test/test_compiler.ml
git commit -m "test(refine): refined params typecheck as their base type (A1a erasure)"
```

## Task 4: A1a bookkeeping

- [ ] **Step 1: Update specs**

In `specs/progress.md` (refinement bullet) note: "A1a: `{T|p}` parses and erases to its base type; full pipeline accepts refined annotations (no checking yet)." In `specs/todos.md`, add an A1a Done line and an A1b TODO line.

- [ ] **Step 2: Commit**

```bash
git add specs/progress.md specs/todos.md
git commit -m "docs(refine): record A1a (refinement syntax + erasure)"
```

---

# A1b — VC emission (separate execution, outlined)

*Not specified to step-level depth here; gets its own plan once A1a lands. Shape:*

1. **Internal `TRefine`** — add `TRefine of ty * predicate` to `typecheck.ml`'s `ty` (`:79`), where `predicate` is a small internal IR (reuse `Smt.term` shape or a thin typed predicate). `surface_ty` builds it (translating the `expr` predicate into the internal predicate, validating the decidable fragment and sort/reflectability rules from the spec). `repr`/printing updated.
2. **`unify` strips predicates** — add `| TRefine (b, _), t | t, TRefine (b, _) -> unify ... b t` near the top of `unify` (`:1946`), so base-type inference is unchanged.
3. **Reflectability + fragment validation** — a checker that rejects non-Int/Bool predicates and unliftable terms (spec §Sorts), emitting a diagnostic at the predicate span.
4. **VC emission at call sites** — in `infer_app` (`:3874`), when `param_ty` is `TRefine(base, q)`, after `check_expr env arg base`, build the call-site VC (`path ∧ known_refinement(arg) ⇒ q[arg/_]`; §Call-Site Instantiation) and accumulate it on a new `pending_vcs` list (parallel to `pending_constraints`).
5. **Discharge** — at the `discharge_constraints` call sites (`:5767` etc.), also discharge pending VCs via `Refine.discharge ~root:(Sys.getcwd ()) vc`, mapping `Refuted model` → an error diagnostic (counterexample), `Unverified` → warning + (later) runtime-check insertion. Pass the project root threaded from `bin/main.ml`.
6. **Path context** — a stack of assumptions from `if`/`when`/scalar-`match`/`let`-postconditions (spec §Path context).
7. **Errors** — counterexample formatting in `errors.ml`.
8. **`--require-smt`** flag in `bin/main.ml`.

A1b exit criterion: `f(get(xs, i))`-style bounds and `divide(n, 0)` produce counterexample errors; valid uses pass; existing suite stays green; `MARCH_NO_Z3=1` degrades to warnings.

---

## Self-Review (A1a)

- **Coverage:** AST node (T1), parser (T2), erasure-equivalence (T3), specs (T4). Each A1a piece maps to a task.
- **Behavior preservation:** A1a never constructs an internal refinement and never emits a VC, so the only observable change is that previously-rejected `{T|p}` annotations now parse and are accepted as their base type. Every task ends with the full runner suite green.
- **Key risk (called out, not hidden):** the menhir grammar disambiguation in T2 Step 2 — a new reduce/reduce conflict triggers the left-factoring fallback before proceeding.
- **Placeholder check:** the only conditional code is the test-helper fallback in T2/T3 (use the suite's existing helper if the named one is absent) — explicit, with the concrete fallback given.
