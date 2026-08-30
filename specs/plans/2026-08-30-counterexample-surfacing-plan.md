# Counterexample Surfacing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Z3 models for failed refinement obligations into interpreter-validated, shrunk, source-syntax counterexamples (`clamp(0) returns -1`), per `specs/2026-08-30-counterexample-surfacing-design.md`.

**Architecture:** New `lib/refinecheck/witness.ml` (decode → execute → check → shrink) using `march_eval` as the validation oracle, with two small hooks added to the evaluator (a builtin guard for effect denial, fuel via the existing reduction-budget machinery). Wired into four sites: `refine_post.ml` return contracts, the `cap verified` message, `refine_call.ml` precondition cx, `division_safety.ml`.

**Tech Stack:** OCaml 5.3 / dune, alcotest (`test/test_refinecheck.ml`, Z3-`gated` cases), Z3 via `lib/refine`.

## Global Constraints

- Confirmed witnesses are **Errors** by default; unconfirmed candidates change **nothing** (today's verdicts and rendering stand).
- Every reported witness must be validated by execution AND must satisfy all declared parameter refinements (admissibility) — zero false positives.
- All witness search/shrink/battery orders are fixed and deterministic; no randomness, no `Random`, no time.
- Fuel-limited (~100k reductions per execution), effect-denied evaluation; any block/fuel-out/eval-error → fall back to today's behavior for that obligation.
- Build with `dune build --root . <target>` from the worktree (never bare `dune build` — it escapes to the main repo). Tests: `dune build --root . test/test_refinecheck.exe && ./_build/default/test/test_refinecheck.exe -e`.
- Full suite before finishing: `scripts/run-tests.sh`. Oracles under a **private HOME**; clear `.march/cas/vc` once before verdict runs.
- Git: stage files explicitly by name; no stash; commit per task.

## Verified facts about the codebase (do not re-derive)

- `Refine.discharge ~root ?preamble vc : outcome` with `Refuted of (string * string) list` (key → SMT value string) — `lib/refine/refine.ml:6-8`.
- Return-contract verdict logic: `lib/refinecheck/refine_post.ml:404-445`. `first` holds the `Refuted` model that is currently discarded unless the negated goal is valid (line 437). `emit_error` at 407 builds the message with `cx_block (model_of first)`.
- `cap verified` bare message: `refine_post.ml:223` ("cannot verify return type constraint").
- Call-site cx: `refine_call.ml:1888` (`format_cx (model_of first)` inside the "refinement violation" report).
- Division safety verdicts: `division_safety.ml:517-530` (`Refine.Refuted` arms report with **no** cx today).
- Rendering helpers (`pred_str`, `sexp_tokens`, `pretty_smt_value`, `format_cx`, `cx_block`, `model_of`, `ctor_of_tester`, `ctor_field_names`): `lib/refinecheck/refine_scope.ml:150-288`. No per-module `.mli` files except `refine_check.mli`, so these are callable from `witness.ml` as `Refine_scope.*`.
- Evaluator: `Eval.eval_module_env : module_ -> env` (`lib/eval/eval.ml:3564`) resets all global registries itself and is safe to call before a later real run (run_module calls it again). `Eval.apply : value -> value list -> value` (`eval.ml:1747`). `env = (string * value) list`; nested `DMod` members are also reachable (run_module finds `main` inside `mod Main` by bare `List.assoc`). `exception Eval_error of string` (`eval_prim.ml:16`). `exception Yield` (`eval.ml:765`).
- Fuel machinery exists: `Eval.reduction_ctx : Scheduler.reduction_ctx option ref`, `Eval.set_reduction_counting`, `check_reductions` raises `Yield` at EApp/EMatch/ESend when budget hits 0 (`eval.ml:790-812`). `Scheduler.reduction_ctx` is a record with mutable `remaining` (`lib/scheduler/scheduler.ml`, no mli → fields writable).
- Builtin chokepoint: `apply_inner`'s `VBuiltin (name, f)` arm in `eval.ml` (function starts line 1692) — every builtin call flows through it.
- Effectful-builtin roster: `Typecheck_builtins.builtin_cap_table : (string * string) list` (`lib/typecheck/typecheck_builtins.ml:91`); `march_refinecheck` already links `march_typecheck`.
- `Refine_check.check_module` receives the FULL desugared module including prepended stdlib decls (`bin/main.ml:1013-1027`), so `eval_module_env` on that module has stdlib available. It is called from two pipelines in `bin/main.ml` (~1026, ~1690); wiring inside `check_module` itself covers both. LSP does **not** link refinecheck.
- Test harness: `test/test_refinecheck.ml` — helpers `z3_available`, `gated name f` (skips without Z3), `refine_error_text_d`, `refine_hints`, `contains`; own exe (`test/dune:873`). `march_eval` is NOT currently in its dune `libraries`.
- Value type: `Eval_types.value` — `VInt`, `VFloat`, `VString`, `VBool`, `VUnit`, `VTuple`, `VRecord of (string*value) list`, `VCon of string * value list` (lists are `VCon("Cons",[h;t])`/`VCon("Nil",[])`), `VClosure`, `VBuiltin`, … (`lib/eval/eval_types.ml:24`).

---

### Task 0: Oracle baseline (before any code)

**Files:** none (scratchpad only)

- [ ] **Step 1:** Record the refine-oracle baseline at current HEAD:

```bash
SP=<scratchpad>; mkdir -p $SP/oracle-home $SP/refine-baseline
rm -rf .march/cas/vc
HOME=$SP/oracle-home scripts/refine-oracle.sh baseline $SP/refine-baseline
```

- [ ] **Step 2:** Prove it can go RED: temporarily edit one diagnostic string in `refine_call.ml` (e.g. change "refinement violation" to "refinement violationX"), rebuild, `HOME=$SP/oracle-home scripts/refine-oracle.sh check $SP/refine-baseline` → must FAIL. Revert the edit, rebuild, check → must PASS. Do not proceed on an unproven oracle.

---

### Task 1: Evaluator hooks — builtin guard + fuel harness

**Files:**
- Modify: `lib/eval/eval_prim.ml` (guard ref + exception, next to `apply_hook`)
- Modify: `lib/eval/eval.ml` (`apply_inner`'s `VBuiltin` arm, ~line 1710)
- Modify: `test/dune:873` block (add `march_eval`, `march_scheduler` to `test_refinecheck` libraries if absent)
- Test: `test/test_refinecheck.ml` (new "witness harness" section at the end)

**Interfaces:**
- Produces: `Eval_prim.Blocked_builtin of string` (exception), `Eval_prim.builtin_guard : (string -> unit) option ref` (default `None`; when set, called with the builtin's name before every `VBuiltin` application).
- Produces (Task 2 consumes): the fuel idiom — `Eval.set_reduction_counting true; (match !Eval.reduction_ctx with Some ctx -> ctx.remaining <- fuel | None -> ()); … catch Eval.Yield …; Eval.set_reduction_counting false`.

- [ ] **Step 1: Write failing tests** (in `test_refinecheck.ml`; these are plain Alcotest cases, not `gated` — no Z3 involved). Use the parse+desugar helpers already in the file (mirror how `refine_error_text_d` builds a module) to build an env:

```ocaml
(* witness harness: builtin guard blocks a named builtin through apply *)
let test_builtin_guard () =
  let m = parse_module {|mod M
  fn shout() : Unit do println("hi") end
end|} in   (* reuse the file's existing parse/desugar helper; adapt name *)
  let env = March_eval.Eval.eval_module_env m in
  let f = List.assoc "shout" env in
  March_eval.Eval_prim.builtin_guard :=
    Some (fun name -> if name = "println" then
            raise (March_eval.Eval_prim.Blocked_builtin name));
  let blocked =
    (try ignore (March_eval.Eval.apply f []); false
     with March_eval.Eval_prim.Blocked_builtin _ -> true) in
  March_eval.Eval_prim.builtin_guard := None;
  Alcotest.(check bool) "println blocked" true blocked

(* witness harness: fuel bounds a divergent function *)
let test_fuel () =
  let m = parse_module {|mod M
  fn spin(n : Int) : Int do spin(n) end
end|} in
  let env = March_eval.Eval.eval_module_env m in
  let f = List.assoc "spin" env in
  March_eval.Eval.set_reduction_counting true;
  (match !March_eval.Eval.reduction_ctx with
   | Some ctx -> ctx.March_scheduler.Scheduler.remaining <- 10_000
   | None -> ());
  let out =
    (try ignore (March_eval.Eval.apply f [March_eval.Eval_types.VInt 0]); false
     with March_eval.Eval.Yield -> true) in
  March_eval.Eval.set_reduction_counting false;
  Alcotest.(check bool) "fuel exhausted" true out
```

Adapt module-construction plumbing to whatever helper the file actually exposes (it parses source strings for every existing test; if the raw parse helper is private, add a tiny local one using `March_parser.Parser` + `March_desugar.Desugar` the same way the top of the file does). If `println` in a bare module fails the typecheck-free parse path, that is fine — these tests do not typecheck, they only parse/desugar/eval.

- [ ] **Step 2:** `dune build --root . test/test_refinecheck.exe` → expect a compile error (`Blocked_builtin` unbound). That is the failing state.

- [ ] **Step 3: Implement.** In `eval_prim.ml` next to `apply_hook`:

```ocaml
(* Witness-validation effect guard (lib/refinecheck/witness.ml). When set,
   called with the builtin's name before every VBuiltin application; the
   guard raises [Blocked_builtin] to veto effectful builtins during
   compile-time counterexample validation. [None] in normal runs. *)
exception Blocked_builtin of string
let builtin_guard : (string -> unit) option ref = ref None
```

In `eval.ml` `apply_inner`, at the top of the `VBuiltin (name, f)` arm:

```ocaml
| VBuiltin (name, f) ->
  (match !Eval_prim.builtin_guard with
   | Some g -> g name
   | None -> ());
  ...existing body...
```

- [ ] **Step 4:** Build and run: `./_build/default/test/test_refinecheck.exe -e` (or `test "witness"` filter) → both tests PASS. Also `scripts/run-tests.sh -q` to prove no eval regression.

- [ ] **Step 5: Commit** `lib/eval/eval_prim.ml lib/eval/eval.ml test/test_refinecheck.ml test/dune` — "feat(eval): builtin guard hook and fuel access for witness validation".

---

### Task 2: witness.ml — decode, predicate evaluator, renderer (pure parts)

**Files:**
- Create: `lib/refinecheck/witness.ml`
- Modify: `lib/refinecheck/dune` (add `witness` to `modules`, `march_eval` + `march_scheduler` to `libraries`)
- Test: `test/test_refinecheck.ml`

**Interfaces (produced; Tasks 3-8 consume — signatures are the contract):**

```ocaml
module A = March_ast.Ast
module V = March_eval.Eval_types

val set_module : A.module_ -> unit
(* Called once per check_module/division-safety run. Stores the module,
   resets the lazy env cache and per-module wall budget, rebuilds the
   type→constructors table from DType decls (walking nested DMods). *)

val zero_value : depth:int -> A.ty -> V.value option
(* Int→VInt 0, Float→VFloat 0.0, Bool→VBool false, String→VString "",
   Unit→VUnit, List _→VCon("Nil",[]), Tuple→VTuple of zeros,
   registered ADT/record→first ctor, recursing with depth-1 (None at 0).
   Unknown ty (incl. TArrow, TVar) → None. *)

val decode_model :
  params:(string * A.ty) list ->
  model:(string * string) list ->
  (string * V.value) list option
(* Model keys matching a param name decode by that param's BASE type
   (refinements stripped); `len$x` entries give string/list lengths
   (String.make n 'a' / n-element zero-fill). Params absent from the
   model zero-fill. Any single undecodable param → None. *)

val eval_pred :
  lookup:(string -> V.value option) ->
  A.expr -> bool option
(* Structural evaluator over the reflectable-and-then-some fragment:
   literals; EVar via lookup ("_" included); && || not; == != < <= > >=
   on VInt/VFloat/VBool/VString (structural equality for VCon/VRecord
   under ==/!=); + - * (and +. -. *. /.) on matching numeric values;
   len(e) on VString/VCon-lists; is_Ctor testers via
   Refine_scope.ctor_of_tester; EField on VRecord; ECon building VCon
   for comparisons. Anything else → None (NOT false). No function
   application in v1 — a predicate calling a user fn is unconfirmable. *)

val render_value : V.value -> string option
(* Source syntax: 42, -1, 3.5, true, "a" (String.escaped), (),
   [1, 2], Some(3), Ctor(x, y), { port: 0 }, (a, b).
   VClosure/VBuiltin/VPid/etc → None (caller drops the witness). *)

val render_call : string -> (string * V.value) list -> string option
(* "clamp(0)" / "scale(1, 1)" — None if any arg renders None. *)
```

- [ ] **Step 1: Write failing unit tests** in `test_refinecheck.ml` (plain, ungated): decode `[("x","(- 3)")]` with `x : Int` → `VInt (-3)`; decode `len$s = "2"` with `s : String` → `VString "aa"`; `len$xs = "2"` with `xs : List(Int)` → `[0, 0]` (via render); zero-fill an absent `Bool` param; `eval_pred` on `_ >= 0` with `_ ↦ VInt (-1)` → `Some false`; `eval_pred` with an unknown application → `None`; `render_value (VCon("Cons",[VInt 1; VCon("Cons",[VInt 2; VCon("Nil",[])])]))` → `"[1, 2]"`. Build predicate exprs by parsing tiny refinement annotations with the file's existing helpers, or construct `A.EApp`/`A.EVar` nodes directly with `Ast.dummy_span`.

- [ ] **Step 2:** Build → fails (module doesn't exist).

- [ ] **Step 3: Implement** `witness.ml` sections §1 decode / §2 eval_pred / §3 render (leave §4 execute for Task 3, with `set_module` storing state it will use). Reuse `Refine_scope.sexp_tokens` for model-string parsing; strip refinement types to base with the same base-type extraction refine_scope's `refined_param_ty` uses (an `A.TyRefine`-shaped node — copy the match, don't re-derive). Floats: accept plain `float_of_string`-parseable forms only; anything `(fp …)` → None.

- [ ] **Step 4:** Run the new tests → PASS.

- [ ] **Step 5: Commit** `lib/refinecheck/witness.ml lib/refinecheck/dune test/test_refinecheck.ml` — "feat(refinecheck): witness decode/predicate-eval/render core".

---

### Task 3: Execution harness + return-contract wiring (the clamp case)

**Files:**
- Modify: `lib/refinecheck/witness.ml` (§4 execute + confirm)
- Modify: `lib/refinecheck/refine_post.ml:404-445` (verdict logic) and its callers so `fn_def`'s param list reaches that point (it already has `fn_name`; thread `params:(string * A.ty) list` and the return binder through from `check_fn_post`'s `A.fn_def`)
- Modify: `lib/refinecheck/refine_check.ml` — call `Witness.set_module` at the top of `check_module`
- Test: `test/test_refinecheck.ml` (gated end-to-end fixtures)

**Interfaces:**
- Consumes: Task 1 hooks, Task 2 decode/eval_pred/render.
- Produces:

```ocaml
type exec_result =
  | Ret of V.value | Panicked of string
  | Blocked | FuelOut | ExecError

val call_fn : name:string -> args:V.value list -> exec_result
(* Lazy eval_module_env of the set_module module (cached; cache also
   guards against a module that itself fails to eval — ExecError forever
   after). Looks up [name] bare in the env, falling back to a "." ^ name
   suffix scan. Installs builtin_guard blocking every name in
   Typecheck_builtins.builtin_cap_table plus a fixed extra list (grep
   Eval_builtins.base_env / task_builtins at implementation time for:
   task/actor spawn+await, sleep/now/clock, random, tap, channel ops).
   Sets fuel = 100_000; decrements a per-module wall budget (start
   1_000_000; when exhausted, every call returns FuelOut). Fun.protect
   restores guard + reduction counting. Catches Yield→FuelOut,
   Blocked_builtin→Blocked, Eval_error m→Panicked m, other exn→ExecError. *)

val admissible : params:(string * A.ty) list -> (string * V.value) list -> bool
(* Every param whose declared type carries a refinement must eval_pred
   true on its value (binder and "_" bound to the value). Unevaluable
   (None) → NOT admissible. Params without refinements are admissible. *)

val confirm_post :
  fn_name:string -> params:(string * A.ty) list ->
  binder:string -> ret_pred:A.expr ->
  model:(string * string) list ->
  ((string * V.value) list * V.value) option
(* decode_model → admissible → call_fn → Ret v → eval_pred ret_pred with
   binder/"_" ↦ v (and params in scope for preds naming them) = Some false
   → Some (args, v). Every other path → None. *)
```

- [ ] **Step 1: Write failing gated fixtures** (each asserts EXACT witness text — this is the determinism test):

```ocaml
gated "return contract: confirmed witness becomes an error" (fun () ->
    let text = refine_error_text_d
      (decl "  fn clamp(x : Int) : {Int | _ >= 0} do x - 1 end") in
    Alcotest.(check bool) "violation reported" true
      (contains text "does not satisfy its return type constraint");
    Alcotest.(check bool) "executed witness" true
      (contains text "but clamp(0) returns -1"));

gated "spurious model is rejected, no error" (fun () ->
    (* x*x is unreflectable → the path condition is dropped → the raw
       model refutes via the unreachable else-branch. Validation runs
       weird(model) → returns 1 → predicate holds → NO error. *)
    let hints_or_silence = refine_error_text_d
      (decl "  fn weird(x : Int) : {Int | _ >= 0} do if x * x >= 0 do 1 else x end end") in
    Alcotest.(check bool) "no witness claim" false
      (contains hints_or_silence "but weird("));

gated "inadmissible zero-fill is not blamed" (fun () ->
    (* any witness must satisfy the param's own refinement *)
    let text = refine_error_text_d
      (decl "  fn f(x : {Int | _ > 0}) : {Int | _ >= 5} do x end") in
    (* if a witness appears it must name an admissible input, never x = 0 *)
    Alcotest.(check bool) "never blames x = 0" false
      (contains text "f(0)"));

gated "divergent witness input falls back silently" (fun () ->
    let text = refine_error_text_d
      (decl "  pfn spin(n : Int) : Int do spin(n) end\n\
            \  fn f(x : Int) : {Int | _ >= 0} do spin(x) end") in
    Alcotest.(check bool) "no witness claim" false (contains text "but f("));
```

Adapt the exact helper (`refine_error_text_d` may need a variant that also returns the no-error case as `""` — check how the "unverified hint" tests read hints and reuse that). If `clamp`'s Z3 model is not literally `x = 0` the exact-text assertion will fail — that is Task 4's shrink; for THIS task assert `contains text "but clamp("` and `contains text "returns -"` and tighten to the exact string in Task 4.

- [ ] **Step 2:** Run → new tests FAIL (no witness text yet, but also confirm the fixture programs parse/typecheck — fix March syntax first if a fixture errors for the wrong reason; the multi-`end` if-chain rule applies).

- [ ] **Step 3: Implement** §4 + wire `refine_post.ml`: in the `violated` computation (line ~431), in the non-record `else` branch, when the negated-goal discharge is NOT `Verified` and `first` is `Refuted model`, call `Witness.confirm_post`. On `Some (args, ret)`:
  - `note Obligation.Violated`
  - emit the existing message with the cx replaced: base message as at line 415-417 but instead of `cx_block …` append `Printf.sprintf "\n\nbut %s returns %s." (call) (Witness.render_value ret |> Option.get)` where `call = Witness.render_call fn args`. If `fn_name = None` or rendering returns `None`, fall back to the old `cx_block` path unchanged.
  On `None`: exactly today's behavior (`Skipped Solver_undecided`, silent).
  Also add `Witness.set_module m` at the top of `Refine_check.check_module`.

- [ ] **Step 4:** Run gated tests → PASS. Run the whole `test_refinecheck.exe -e` → no regressions (some existing fixtures may now legitimately gain witness errors — inspect each; update only where the new error is a TRUE confirmed violation, and say so in the commit message).

- [ ] **Step 5: Commit** — "feat(refinecheck): validated counterexamples for return contracts".

---

### Task 4: Shrink

**Files:**
- Modify: `lib/refinecheck/witness.ml`
- Test: `test/test_refinecheck.ml`

**Interfaces:**
- Produces: `val shrink : run:((string * V.value) list -> bool) -> (string * V.value) list -> (string * V.value) list` — `run` re-checks admissibility+execution+violation for a candidate (Task 3's pipeline refactored into a reusable closure). Deterministic order: for each arg position left-to-right, repeatedly try in order: `VInt n → 0` then `n/2` steps toward 0; `VFloat → 0.0` then halve; `VString → ""` then drop last char; lists → `[]` then drop head, then shrink elements pointwise; `VCon/VRecord/VTuple` → shrink fields pointwise; cap total `run` invocations at 64.
- `confirm_post` calls `shrink` before returning.

- [ ] **Step 1:** Tighten Task 3's clamp assertion to the exact minimal string: `contains text "but clamp(0) returns -1."`. Add a shrink-specific fixture:

```ocaml
gated "witness shrinks to zero" (fun () ->
    let text = refine_error_text_d
      (decl "  fn g(x : Int) : {Int | _ >= 10} do x end") in
    Alcotest.(check bool) "minimal witness" true
      (contains text "but g(0) returns 0."));
```

- [ ] **Step 2:** Run → FAIL if the raw model isn't already minimal (if clamp/g already come back minimal from Z3, force the point with `{Int | _ >= 10}`-style predicates until one is non-minimal; keep whichever fixture actually exercises shrink).
- [ ] **Step 3:** Implement `shrink`; wire into `confirm_post`.
- [ ] **Step 4:** Run → PASS; full `test_refinecheck.exe -e` green.
- [ ] **Step 5: Commit** — "feat(refinecheck): deterministic witness shrinking".

---

### Task 5: `cap verified` — append the confirmed violation

**Files:**
- Modify: `lib/refinecheck/refine_post.ml` (~line 215-230, the "cannot verify return type constraint" report)
- Test: `test/test_refinecheck.ml`

**Interfaces:** Consumes `Witness.confirm_post` unchanged.

- [ ] **Step 1: Failing fixture** (find the existing cap-verified helper in the file — search `cap verified` in test_refinecheck.ml and mirror it):

```ocaml
gated "cap verified: undecided obligation names the confirmed violation" (fun () ->
    let text = refine_error_text_cap_verified
      "  fn clamp(x : Int) : {Int | _ >= 0} do x - 1 end" in
    Alcotest.(check bool) "still the cannot-verify error" true
      (contains text "cannot verify return type constraint");
    Alcotest.(check bool) "and the confirmed fact" true
      (contains text "In fact the contract is violated: clamp(0) returns -1."));
```

- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** At the report site, when the skip reason is solver-undecided and a `Refuted` model was seen for this obligation (thread the model to the reporting point — it flows from the same discharge; if the current code path discards it before reaching line 223, carry it in the skip note or re-derive by calling `confirm_post` where the verdict is computed and stashing the result), append the sentence on success. **Note:** with Task 3 in place a confirmed violation already reports as a definite error even in cap-verified modules — if that error now fires INSTEAD of the cannot-verify message, this task reduces to asserting that (preferable: one error, the strong one). Check which happens first and pin the observed, better behavior in the fixture; update the design doc's site table if the "In fact…" append turns out to be dead.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5: Commit** — "feat(refinecheck): confirmed violations under cap verified".

---

### Task 6: Call-site preconditions — validate, shrink, render

**Files:**
- Modify: `lib/refinecheck/refine_call.ml` (~1888) and `lib/refinecheck/refine_scope.ml` (`format_cx` gains a validated variant or the site formats directly)
- Test: `test/test_refinecheck.ml`

**Interfaces:**
- Produces: `val confirm_precond : scope_types:(string * A.ty) list -> pred:A.expr -> model:(string * string) list -> (string * V.value) list option` in witness.ml — decode the model entries whose keys are scope variables (types from `scope_types`; entries with no known type or `$` keys other than `len$` are kept only if the value parses as a bare int/bool), check via `eval_pred` that the predicate is FALSE with the argument's binder bound (the model's entry for the checked argument — the site knows which scope var/argument the obligation is about; pass its key), shrink with `run` = "pred still false ∧ path conds unchanged truth-value where evaluable", render.
- The site keeps `format_cx (model_of first)` as the fallback whenever `confirm_precond` returns `None`.

- [ ] **Step 1: Failing fixture** — extend the EXISTING test at test_refinecheck.ml:188 ("violation keeps the solver counterexample"): it asserts `contains text "e.g. k = "`. Add:

```ocaml
gated "precondition cx is validated and minimal" (fun () ->
    let text = refine_error_text_d
      (decl "  fn f(k : {Int | _ < 0}) : Int do take_n(k) end") in
    (* take_n requires _ > 0 (see the file's shared prelude decl);
       k < 0 admits k = -1 as the minimal violating example *)
    Alcotest.(check bool) "minimal validated cx" true
      (contains text "e.g. k = -1"));
```

(Adjust the expected value to the actual minimal admissible one for the predicates in the file's shared prelude — read `take_n`'s declared precondition first.)

- [ ] **Step 2:** Run → FAIL (today shows the raw Z3 value).
- [ ] **Step 3:** Implement `confirm_precond`; at refine_call.ml:1888 try it first, fall back to `format_cx`. Scope types: the surrounding code has the caller's refined scope (the `scope` type in refine_scope.ml carries binder+pred per name; base types come from the same place the SMT decls were made — reuse what `check_call` already collected rather than re-inferring).
- [ ] **Step 4:** Run new + existing precondition tests → PASS (the old "e.g. k = " assertion must still pass — the shape is preserved).
- [ ] **Step 5: Commit** — "feat(refinecheck): validated call-site precondition examples".

---

### Task 7: Division safety — concrete failing input

**Files:**
- Modify: `lib/refinecheck/division_safety.ml` (~517-530)
- Test: `test/test_refinecheck.ml`

**Interfaces:**
- Consumes: `Witness.confirm_precond`-style validation: decode model against the enclosing fn's params, `eval_pred` the reflected divisor-≠-0 predicate (the site already has the divisor expr and the model), require FALSE (divisor = 0), shrink, render.

- [ ] **Step 1: Failing fixture** (mirror the file's existing `cap no_panic` division tests — search "no_panic" for the helper):

```ocaml
gated "division: counterexample names the concrete input" (fun () ->
    let text = no_panic_error_text
      "  fn f(a : Int, b : Int) : Int do a / b end" in
    Alcotest.(check bool) "concrete divisor witness" true
      (contains text "e.g. f(0, 0) reaches this division with b = 0"));
```

(Pin the exact wording after seeing the site's existing message; the required elements are the rendered call and `with <divisor-expr> = 0`.)

- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement: in the `Refine.Refuted model` arms, decode+validate+shrink; append the suffix to the existing message; fall back to the current text when unconfirmable.
- [ ] **Step 4:** Run → PASS; whole exe green.
- [ ] **Step 5: Commit** — "feat(refinecheck): concrete inputs on division-safety errors".

---

### Task 8: Enumerative battery for unreflectable return contracts

**Files:**
- Modify: `lib/refinecheck/witness.ml`, `lib/refinecheck/refine_post.ml` (the `smt_of … ret_pred → None` arm, line ~369)
- Test: `test/test_refinecheck.ml`

**Interfaces:**
- Produces: `val battery : params:(string * A.ty) list -> ((string * V.value) list) Seq.t` — fixed per-type candidate lists (`Int: [0;1;-1;2;10]`, `Float: [0.;1.;-1.]`, `Bool: [false;true]`, `String: [""; "a"]`, `List t: [[]; [z t]; [z t; z t]]`, ADTs: each ctor zero-filled), cartesian product in declaration order, truncated to the first 48 combinations. `confirm_enumerative ~fn_name ~params ~binder ~ret_pred : ((string * V.value) list * V.value) option` — filter by `admissible`, execute, `eval_pred`, first confirmed wins, then `shrink`.

- [ ] **Step 1: Failing fixture** — the spec's scale example:

```ocaml
gated "unreflectable contract: enumeration finds the witness" (fun () ->
    let text = refine_error_text_d
      (decl "  fn scale(x : {Int | _ > 0}, y : {Int | _ > 0}) : {Int | _ > 100} do x * y end") in
    Alcotest.(check bool) "violation" true
      (contains text "does not satisfy its return type constraint");
    Alcotest.(check bool) "admissible minimal witness" true
      (contains text "but scale(1, 1) returns 1."));
```

- [ ] **Step 2:** Run → FAIL (today: silent / unreflectable skip).
- [ ] **Step 3:** Implement; at the `None ->` arm in refine_post, run `confirm_enumerative` (same emit path as Task 3; on `None` keep `Skipped Unreflectable_predicate`).
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5: Commit** — "feat(refinecheck): enumeration witnesses for unreflectable contracts".

---

### Task 9: Full verification, oracle, docs, lifecycle

**Files:**
- Modify: `CHANGELOG.md` (`## [Unreleased]` → `### Added` bullet: validated counterexamples; `### Changed` bullet: some-input return-contract violations with a confirmed witness are now errors)
- Move: `git mv specs/todos/2026-08-30-counterexample-surfacing.md specs/progress/2026-08-30-counterexample-surfacing.md` (update its text to past tense, note key deviations)
- Modify: `specs/2026-08-30-counterexample-surfacing-design.md` (Status → implemented; record deviations, at minimum: effect denial is a builtin-name guard at the `apply_inner` chokepoint; division confirmation is divisor-evaluates-to-0 rather than executed panic; predicate evaluation does not apply user measure fns in v1)

- [ ] **Step 1:** Full suite: `scripts/run-tests.sh` (NOT `-q`). All green, and compare suite counts against a baseline run if anything looks off (stale `_build` copies manufacture fake failures — build `@install` before believing a pre-existing-failure theory).
- [ ] **Step 2:** Oracle: rebuild, `rm -rf .march/cas/vc`, `HOME=$SP/oracle-home scripts/refine-oracle.sh check $SP/refine-baseline`. Expect RED with a diff. **Review every diff line**: each must be one of the intentional new witness texts/errors; anything else is a bug — fix before proceeding. Record the reviewed diff summary in the progress file.
- [ ] **Step 3:** CI text guards: `dune build --root . @types-check --force` and assert on the LOG contents, not exit code; existing messages were only appended-to, but verify none of the pinned texts changed.
- [ ] **Step 4:** Docs/spec lifecycle edits above; run `scripts/check-docs.sh`.
- [ ] **Step 5: Commit** — "docs: counterexample surfacing shipped (changelog, spec lifecycle)".

## Self-review notes

- Spec coverage: model extraction (T3), rendering (T2/T3), four sites (T3/T5/T6/T7), enumeration (T8), shrink (T4), admissibility (T3), effect/fuel safety (T1), spurious rejection (T3 fixture), oracle+CI (T0/T9). Non-goals untouched.
- Known judgment points left to the implementer, on purpose: exact helper names inside `test_refinecheck.ml`, the extra blocked-builtin list (grep at T3), whether T5's append is subsumed by T3's error (pin observed behavior), exact minimal values in T6/T7 fixtures (read the shared prelude predicates first).
