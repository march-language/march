# SCC-Aware Inliner Candidate Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce residual direct calls in emitted LLVM by retaining small, pure functions in acyclic candidate chains while excluding recursive strongly connected components.

**Architecture:** `Inline.run` will build its existing purity/size/HCR candidate pool, derive a direct `EApp` graph over that pool, and use Tarjan SCC detection to remove only recursive components. The existing alpha-renaming, ANF substitution, one-level traversal, fixed-point coordinator, and DCE remain unchanged.

**Tech Stack:** OCaml, March TIR, Alcotest, LLVM text emission, Dune.

## Global Constraints

- Do not add a new IR node or annotation.
- Do not change March language semantics.
- Do not change ownership, Perceus, or RC behavior.
- Keep `inline_size_threshold = 50`.
- Preserve hot-reload boundary exclusions.
- Keep `inline_expr`, `alpha_rename`, and `subst_args` behavior unchanged.
- Build graph edges only from direct `EApp` calls; `ECallPtr` remains the responsibility of `Known_call`.
- Runtime speed is not a merge criterion; the named residual LLVM call and definition are.

---

### Task 1: Preserve acyclic candidates and reject recursive SCCs

**Files:**
- Modify: `lib/tir/inline.ml:20-205`
- Test: `test/test_codegen.ml:3360-3440`

**Interfaces:**
- Consumes: `(string, Tir.fn_def) Hashtbl.t`, the initial purity/size/HCR candidate pool.
- Produces: `recursive_candidate_names : (string, Tir.fn_def) Hashtbl.t -> SSet.t`.
- Produces: an `fn_env` containing every initial candidate not returned by `recursive_candidate_names`.

- [ ] **Step 1: Add a failing acyclic-chain unit test**

Add this helper near the existing inliner tests:

```ocaml
let direct_call_to name =
  March_tir.Tir.EApp
    (mk_var name
       (March_tir.Tir.TFn ([March_tir.Tir.TInt], March_tir.Tir.TInt)),
     [ilit 1])
```

Add a test that constructs `leaf`, `wrapper`, and `main`, where `wrapper`
directly calls `leaf` and `main` directly calls `wrapper`:

```ocaml
let test_inline_acyclic_candidate_chain () =
  let changed = ref false in
  let x = mk_var "x" March_tir.Tir.TInt in
  let leaf =
    { March_tir.Tir.fn_name = "leaf";
      fn_params = [x];
      fn_ret_ty = March_tir.Tir.TInt;
      fn_body = app "+" [March_tir.Tir.AVar x; ilit 1];
      fn_kind = March_tir.Tir.FnNormal }
  in
  let wrapper =
    { March_tir.Tir.fn_name = "wrapper";
      fn_params = [x];
      fn_ret_ty = March_tir.Tir.TInt;
      fn_body =
        March_tir.Tir.EApp
          (mk_var "leaf"
             (March_tir.Tir.TFn
                ([March_tir.Tir.TInt], March_tir.Tir.TInt)),
           [March_tir.Tir.AVar x]);
      fn_kind = March_tir.Tir.FnNormal }
  in
  let main =
    { March_tir.Tir.fn_name = "main";
      fn_params = [];
      fn_ret_ty = March_tir.Tir.TInt;
      fn_body = direct_call_to "wrapper";
      fn_kind = March_tir.Tir.FnNormal }
  in
  let result =
    March_tir.Inline.run ~changed (mk_module [leaf; wrapper; main])
  in
  let main_body =
    result.March_tir.Tir.tm_fns
    |> List.find (fun fn -> String.equal fn.March_tir.Tir.fn_name "main")
    |> fun fn -> fn.March_tir.Tir.fn_body
  in
  match main_body with
  | March_tir.Tir.EApp (fn, _)
    when String.equal fn.March_tir.Tir.v_name "wrapper" ->
    Alcotest.fail "acyclic wrapper remained excluded from candidates"
  | _ -> ()
```

Register it in the `"inline"` test group as `"acyclic_candidate_chain"`.

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
dune exec test/run_codegen.exe -- test inline -e --color=never
```

Expected: `acyclic_candidate_chain` fails because `main` remains an `EApp` to
`wrapper`. The four existing tests remain green.

- [ ] **Step 3: Add graph collection and Tarjan SCC detection**

In `lib/tir/inline.ml`, define:

```ocaml
module SSet = Set.Make (String)
```

Add `direct_candidate_calls` with the same recursive expression coverage as
the old `calls_other` closure:

```ocaml
let direct_candidate_calls candidates expr =
  let rec collect acc = function
    | Tir.EApp (fn, _) when Hashtbl.mem candidates fn.Tir.v_name ->
      SSet.add fn.Tir.v_name acc
    | Tir.ELet (_, rhs, body) ->
      collect (collect acc rhs) body
    | Tir.ELetRec (fns, body) ->
      let acc =
        List.fold_left
          (fun calls fn -> collect calls fn.Tir.fn_body)
          acc fns
      in
      collect acc body
    | Tir.ECase (_, branches, default) ->
      let acc =
        List.fold_left
          (fun calls branch -> collect calls branch.Tir.br_body)
          acc branches
      in
      Option.fold ~none:acc ~some:(collect acc) default
    | Tir.ESeq (e1, e2) ->
      collect (collect acc e1) e2
    | _ -> acc
  in
  collect SSet.empty expr
```

Add `recursive_candidate_names`. It must:

- precompute each candidate’s `SSet.t` successors;
- assign Tarjan `index` and `lowlink` values;
- maintain a stack and `on_stack` set;
- mark every component of size greater than one recursive; and
- mark a singleton recursive only when its successor set contains itself.

Use function names as graph identities and return one `SSet.t`; do not mutate
`fn_env` while Tarjan is traversing it.

- [ ] **Step 4: Replace conservative filtering**

Change `Inline.run` so the initial pool uses only purity, size, and HCR checks.
Remove the `calls_self` eligibility check and the entire “calls another
candidate” loop.

Then filter once:

```ocaml
let recursive = recursive_candidate_names fn_env in
SSet.iter (Hashtbl.remove fn_env) recursive;
```

Leave the final `inline_expr` mapping unchanged.

- [ ] **Step 5: Run unit tests and verify GREEN**

Run:

```bash
dune exec test/run_codegen.exe -- test inline -e --color=never
dune exec test/test_hot_reload.exe -- --color=never
```

Expected:

- five inliner tests pass;
- self-recursion remains un-inlined;
- mutual recursion remains un-inlined; and
- all hot-reload tests pass.

- [ ] **Step 6: Commit Task 1**

```bash
git add lib/tir/inline.ml test/test_codegen.ml
git commit -m "perf(tir): preserve acyclic inliner candidates"
```

---

### Task 2: Pin the emitted-LLVM residual-call reduction

**Files:**
- Test: `test/test_codegen.ml` in the inliner test section

**Interfaces:**
- Consumes: `March_tir.Opt.run` and `March_tir.Llvm_emit.emit_module`.
- Produces: a deterministic regression proving `@outer_growth` has neither a residual call nor a retained definition.

- [ ] **Step 1: Add a live wrapper-body builder**

Add a test-local builder whose arithmetic depends on its parameter so Fold,
Simplify, and DCE cannot collapse it:

```ocaml
let live_add_chain param count tail =
  let rec build index current =
    if index = count then tail current
    else
      let next = mk_var (Printf.sprintf "grow_%d" index) March_tir.Tir.TInt in
      March_tir.Tir.ELet
        (next,
         app "+" [March_tir.Tir.AVar current; March_tir.Tir.AVar param],
         build (index + 1) next)
  in
  build 0 param
```

Call `live_add_chain` with `count = 11`. Make `inner_growth` a nine-node body:
two live arithmetic `ELet` bindings followed by `EAtom`. The outer body is
then 46 nodes before inlining and 55 nodes after the inner call is replaced.
Assert `node_count inner_growth.fn_body = 9` and
`node_count outer_growth.fn_body = 46` so fixture drift fails loudly.

- [ ] **Step 2: Add the LLVM regression**

Construct:

- `inner_growth(x)`, a small pure arithmetic body;
- `outer_growth(x)`, the live addition chain ending in a call to
  `inner_growth`; and
- `main()`, which calls `outer_growth(1)`.

Run:

```ocaml
let optimized = March_tir.Opt.run module_ in
let ir = March_tir.Llvm_emit.emit_module optimized in
```

Add a local substring helper and assert:

```ocaml
Alcotest.(check bool)
  "no residual call to outer_growth" false
  (contains ir "call i64 @outer_growth(");
Alcotest.(check bool)
  "DCE removes outer_growth definition" false
  (contains ir "define i64 @outer_growth(")
```

Also count occurrences of `" call "` and record `String.length ir` before and
after optimization in the assertion labels or failure message. Do not gate on
an exact total-call count or exact IR byte size.

- [ ] **Step 3: Prove the regression detects the old behavior**

Temporarily restore the old “calls another candidate” filter or invert the new
acyclic-retention condition, then run:

```bash
dune exec test/run_codegen.exe -- test inline -e --color=never
```

Expected: the emitted-LLVM regression fails because `main` contains a call to
`@outer_growth` and its definition remains.

Restore the SCC-aware implementation immediately.

- [ ] **Step 4: Verify the regression passes**

Run:

```bash
dune exec test/run_codegen.exe -- test inline -e --color=never
```

Expected: all six inliner tests pass.

- [ ] **Step 5: Commit Task 2**

```bash
git add test/test_codegen.ml
git commit -m "test(codegen): pin acyclic wrapper call elimination"
```

---

### Task 3: Document and verify the optimization

**Files:**
- Modify: `specs/progress.md`

**Interfaces:**
- Consumes: the completed SCC-aware implementation and LLVM regression.
- Produces: source-grounded release notes and final verification evidence.

- [ ] **Step 1: Document the result**

Add a concise dated entry to `specs/progress.md` covering:

- the old conservative candidate filter;
- SCC-only recursive exclusion;
- the body-growth fixture;
- the named LLVM call and definition removed; and
- the measured before/after call count, LLVM byte size, and repeated fixture
  compile time.

Do not claim a runtime speedup.

- [ ] **Step 2: Run focused verification**

```bash
dune exec test/run_codegen.exe -- test inline -e --color=never
dune exec test/test_hot_reload.exe -- --color=never
dune exec test/run_eval.exe -- test tir -e --color=never
QCHECK_SEED=230208339 dune exec test/test_properties.exe -- test 'tir pipeline|tir passes|tir pass invariants' -e --color=never
QCHECK_SEED=446158617 dune exec test/test_properties.exe -- test 'tir pipeline|tir passes|tir pass invariants' -e --color=never
```

Expected: every command exits zero.

- [ ] **Step 3: Run full codegen verification**

```bash
dune exec test/run_codegen.exe -- test -e --color=never
git diff --check
```

Expected: 449 or more codegen tests pass, with zero failures, and
`git diff --check` emits no output.

- [ ] **Step 4: Commit documentation**

```bash
git add specs/progress.md
git commit -m "docs: record SCC-aware inliner selection"
```

- [ ] **Step 5: Review final branch**

```bash
git status --short
git log --oneline origin/main..HEAD
git diff --stat origin/main...HEAD
```

Expected: the worktree is clean and the branch contains the design, focused
implementation, regression, and documentation commits only.
