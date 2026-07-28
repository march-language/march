# Single-Use Private-Function Inlining Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate one-use calls and dead definitions for small syntactically impure TIR functions without changing evaluation order, ownership operations, recursion, exports, or hot-reload behavior.

**Architecture:** Factor DCE's operational entry roots into one shared helper, then add a named `Single_use_inline` pass immediately after ordinary inlining. The pass performs lexically scoped top-level reference counting, selects only non-root, non-recursive, non-address-taken impure functions of at most 50 nodes, and reuses the ordinary inliner's alpha-renaming and ANF substitution before existing downstream DCE removes dead definitions.

**Tech Stack:** OCaml 5.3, March TIR, Alcotest, Dune, raw textual LLVM regressions, native March golden fixtures.

## Global Constraints

- Retain the existing 50-node threshold; do not introduce a second threshold.
- Admit every body for which `Purity.is_pure` is false, including RC, indirect-call, I/O, trap, reuse, and sequencing operations.
- Require exactly one total free top-level reference, and require that occurrence to be an arity-correct direct `EApp`.
- Count every atom position and respect lexical shadowing by parameters, lets, branch binders, and local recursive definitions.
- Exclude recursive SCCs, DCE roots, address-taken functions, collision-dispatch targets, and reloadable callees.
- Do not add a new IR or change Perceus, Borrow, the closure ABI, LLVM ownership conventions, language semantics, or source visibility.
- Reuse the existing inliner's alpha-renaming and ANF substitution; never synthesize, delete, combine, or reorder an RC operation.
- Let existing downstream DCE remove unreachable definitions.
- Do not claim runtime speedup from call-count or IR-size changes alone.

---

## File Structure

- Create `lib/tir/single_use_inline.ml`: scoped reference analysis, candidate selection, and one-use rewriting.
- Modify `lib/tir/dce.ml`: expose the exact operational entry-root names already used by reachability pruning.
- Modify `lib/tir/inline.ml`: expose one reloadability helper while preserving ordinary candidate behavior.
- Modify `lib/tir/opt.ml`: register the named pass after ordinary inline.
- Modify `lib/tir/dune`: add `single_use_inline` to the explicit library module list.
- Modify `test/test_codegen.ml`: focused root, selection, ordering, optimizer, and raw LLVM tests.
- Modify `test/test_hot_reload.ml`: one-use impure boundary coverage.
- Create `test/native/single_use_inline_rc.march`: compiled semantic and RC regression.
- Create `test/native/single_use_inline_rc.expected`: expected output.
- Modify `test/dune`: compile, execute, diff, and raw-LLVM-check the native fixture.
- Modify `specs/optimizations.md`: document the pass contract and placement.
- Modify `specs/progress.md`: record verified results and post-change measurements.

### Task 1: Share DCE Entry Roots

**Files:**
- Modify: `lib/tir/dce.ml`
- Test: `test/test_codegen.ml`

**Interfaces:**
- Produces: `Dce.root_names : Tir.tir_module -> string list`
- Consumes: `Tir.tm_exports`, `Tir.tm_tests`, `Tir_names.setup_fn_name`, `Tir_names.setup_all_fn_name`, and `Tir_names.is_migrate_fn_name`
- Invariant: `Dce.reachable_fns` must seed its queue exclusively from `root_names`

- [ ] **Step 1: Add failing root-set tests**

Add these tests beside `test_dce_unreachable_topfn`:

```ocaml
let test_dce_root_names () =
  let plain = mk_fn "plain" (March_tir.Tir.EAtom (ilit 0)) in
  let main = mk_fn "App.main" (March_tir.Tir.EAtom (ilit 0)) in
  let exported = mk_fn "rpc__rpc_stub" (March_tir.Tir.EAtom (ilit 0)) in
  let setup = mk_fn March_tir.Tir_names.setup_fn_name
      (March_tir.Tir.EAtom (ilit 0)) in
  let migrate = mk_fn "__migrate_Actor" (March_tir.Tir.EAtom (ilit 0)) in
  let module_ =
    { (mk_module [plain; main; exported; setup; migrate]) with
      March_tir.Tir.tm_exports = ["rpc__rpc_stub"];
      tm_tests = [("plain", "plain test")] }
  in
  let roots = March_tir.Dce.root_names module_ in
  List.iter
    (fun name ->
      Alcotest.(check bool) (name ^ " is rooted") true (List.mem name roots))
    ["plain"; "App.main"; "rpc__rpc_stub";
     March_tir.Tir_names.setup_fn_name; "__migrate_Actor"]

let test_dce_root_names_no_seed_falls_back_to_all () =
  let module_ =
    mk_module
      [mk_fn "a" (March_tir.Tir.EAtom (ilit 0));
       mk_fn "b" (March_tir.Tir.EAtom (ilit 1))]
  in
  Alcotest.(check (list string)) "all functions are roots"
    ["a"; "b"] (March_tir.Dce.root_names module_)
```

Register both under the existing `"dce"` group.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
dune exec test/run_codegen.exe -- test dce -e --color=never
```

Expected: compilation fails because `March_tir.Dce.root_names` does not exist.

- [ ] **Step 3: Implement `root_names` and reuse it**

In `lib/tir/dce.ml`, extract the seed rules from `reachable_fns`:

```ocaml
let root_names (m : Tir.tir_module) : string list =
  let roots = ref StringSet.empty in
  let add name = roots := StringSet.add name !roots in
  let is_main_name name =
    name = "main"
    || let suffix = ".main" in
       let name_len = String.length name
       and suffix_len = String.length suffix in
       name_len >= suffix_len
       && String.sub name (name_len - suffix_len) suffix_len = suffix
  in
  List.iter
    (fun (fn : Tir.fn_def) ->
      if is_main_name fn.Tir.fn_name then add fn.Tir.fn_name;
      if fn.Tir.fn_name = Tir_names.setup_fn_name
         || fn.Tir.fn_name = Tir_names.setup_all_fn_name
         || Tir_names.is_migrate_fn_name fn.Tir.fn_name
      then add fn.Tir.fn_name)
    m.Tir.tm_fns;
  List.iter add m.Tir.tm_exports;
  List.iter (fun (name, _) -> add name) m.Tir.tm_tests;
  if StringSet.is_empty !roots then
    List.iter (fun (fn : Tir.fn_def) -> add fn.Tir.fn_name) m.Tir.tm_fns;
  StringSet.elements !roots
```

Replace the duplicated queue-seeding block in `reachable_fns` with:

```ocaml
List.iter (fun name -> Queue.push name queue) (root_names m);
```

Do not alter collision-dispatch traversal inside the reachability loop.

- [ ] **Step 4: Run DCE and broad focused tests**

Run:

```bash
dune exec test/run_codegen.exe -- test dce -e --color=never
dune exec test/run_codegen.exe -- test inline -e --color=never
dune exec test/test_hot_reload.exe -- --color=never
```

Expected: all pass; existing unreachable-function behavior is unchanged.

- [ ] **Step 5: Commit**

```bash
git add lib/tir/dce.ml test/test_codegen.ml
git commit -m "refactor(tir): share DCE entry roots"
```

### Task 2: Implement Scoped Reference Analysis and Selection

**Files:**
- Create: `lib/tir/single_use_inline.ml`
- Modify: `lib/tir/dune`
- Modify: `lib/tir/inline.ml`
- Test: `test/test_codegen.ml`

**Interfaces:**
- Consumes: `Dce.root_names`, `Inline.node_count`, `Inline.inline_expr`, and the active `Inline.boundary_config`
- Produces: `Single_use_inline.run : changed:bool ref -> Tir.tir_module -> Tir.tir_module`
- Produces: `Inline.is_reloadable_name : string -> bool`
- Candidate threshold: exactly `Inline.inline_size_threshold`, currently 50

- [ ] **Step 1: Add the positive and reference-count RED tests**

Add helpers beside the existing inline tests:

```ocaml
let string_fn_ty =
  March_tir.Tir.TFn ([March_tir.Tir.TString], March_tir.Tir.TString)

let impure_identity name =
  let x = mk_var "x" March_tir.Tir.TString in
  { March_tir.Tir.fn_name = name;
    fn_params = [x];
    fn_ret_ty = March_tir.Tir.TString;
    fn_body =
      March_tir.Tir.ESeq
        (March_tir.Tir.EIncRC (March_tir.Tir.AVar x),
         March_tir.Tir.ESeq
           (March_tir.Tir.EDecRC (March_tir.Tir.AVar x),
            March_tir.Tir.EAtom (March_tir.Tir.AVar x)));
    fn_kind = March_tir.Tir.FnNormal }

let call_string name value =
  March_tir.Tir.EApp (mk_var name string_fn_ty, [value])

let body_of name module_ =
  module_.March_tir.Tir.tm_fns
  |> List.find (fun fn -> String.equal fn.March_tir.Tir.fn_name name)
  |> fun fn -> fn.March_tir.Tir.fn_body

let test_single_use_impure_inlined () =
  let helper = impure_identity "helper" in
  let main = mk_fn "main" (call_string "helper" (slit "seven")) in
  let changed = ref false in
  let result =
    March_tir.Single_use_inline.run ~changed (mk_module [helper; main])
  in
  Alcotest.(check bool) "changed" true !changed;
  match body_of "main" result with
  | March_tir.Tir.EApp (fn, _)
    when String.equal fn.March_tir.Tir.v_name "helper" ->
      Alcotest.fail "one-use impure helper remained a call"
  | _ -> ()

let test_single_use_two_calls_not_inlined () =
  let helper = impure_identity "helper" in
  let main =
    mk_fn "main"
      (March_tir.Tir.ESeq
         (call_string "helper" (slit "one"),
          call_string "helper" (slit "two")))
  in
  let changed = ref false in
  ignore (March_tir.Single_use_inline.run ~changed
            (mk_module [helper; main]));
  Alcotest.(check bool) "unchanged" false !changed

let test_single_use_address_taken_not_inlined () =
  let helper = impure_identity "helper" in
  let helper_value =
    March_tir.Tir.AVar (mk_var "helper" string_fn_ty)
  in
  let main =
    mk_fn "main"
      (March_tir.Tir.ESeq
         (March_tir.Tir.EAtom helper_value,
          call_string "helper" (slit "one")))
  in
  let changed = ref false in
  ignore (March_tir.Single_use_inline.run ~changed
            (mk_module [helper; main]));
  Alcotest.(check bool) "unchanged" false !changed
```

Register these under a new `"single_use_inline"` Alcotest group.

- [ ] **Step 2: Run the new group and verify RED**

Run:

```bash
dune exec test/run_codegen.exe -- test single_use_inline -e --color=never
```

Expected: compilation fails because `March_tir.Single_use_inline` does not
exist.

- [ ] **Step 3: Add the module and shared reloadability helper**

Add `single_use_inline` to `lib/tir/dune` after `inline`.

In `lib/tir/inline.ml`, add:

```ocaml
let is_reloadable_name name =
  match !boundary_config with
  | Some config ->
      Hot_reload.is_reloadable config (Hot_reload.module_of_name name)
  | None -> false
```

Change ordinary `Inline.run` to call this helper without changing its policy.

Create `lib/tir/single_use_inline.ml` with:

```ocaml
module SSet = Set.Make (String)

type occurrence =
  | DirectCall of { caller : string; arity : int }
  | NonDirect

type summary = {
  mutable count : int;
  mutable sole : occurrence option;
}
```

Implement an exhaustive expression/atom traversal carrying a `bound : SSet.t`.
For each free `AVar` or matching `ADefRef` whose name belongs to the module's
top-level name set, increment its summary. Record `DirectCall` only for the
free callee position of `EApp`; every other position records `NonDirect`.

When entering scopes:

- add top-level function parameters before traversing its body
- traverse an `ELet` RHS with the old bound set and its body with the variable added
- add all local `ELetRec` names before traversing every local body and continuation
- add case branch binders only for that branch

When a free callee is a dispatch sentinel, use
`Dispatch_registry.lookup` and add one synthetic `NonDirect` occurrence to
each implementation target.

- [ ] **Step 4: Implement candidate filtering and rewriting**

Build direct-call successors during the same scoped traversal and compute
recursive SCC membership. Reuse the Tarjan structure in `Inline` by extracting
a generic helper if doing so remains smaller than a second implementation;
otherwise keep the implementation private to `Single_use_inline`.

Select a function only when:

```ocaml
not (Purity.is_pure fn.Tir.fn_body)
&& Inline.node_count fn.Tir.fn_body <= Inline.inline_size_threshold
&& summary.count = 1
&& summary.sole = Some (DirectCall { arity; _ })
&& arity = List.length fn.Tir.fn_params
&& not (SSet.mem fn.Tir.fn_name recursive)
&& not (SSet.mem fn.Tir.fn_name roots)
&& not (Inline.is_reloadable_name fn.Tir.fn_name)
```

Put only selected definitions in an environment and return:

```ocaml
{ module_ with
  Tir.tm_fns =
    List.map
      (fun fn ->
        { fn with
          Tir.fn_body = Inline.inline_expr ~changed candidates fn.Tir.fn_body })
      module_.Tir.tm_fns }
```

- [ ] **Step 5: Add and pass the remaining focused safety tests**

Add tests for:

- two different callers
- local `ELet` shadowing a top-level name
- parameter and case-binder shadowing
- self recursion
- mutual recursion
- exactly 50 versus 51 nodes
- arity mismatch
- exported/test/setup/migration roots
- no-seed fallback roots every function
- closure allocation storing the apply pointer
- collision-dispatch target synthetic reference
- preserved nested `ESeq(EIncRC, ESeq(EDecRC, ...))` order

For the order assertion, compare `Tir.show_expr` against the expected expanded
shape after removing only gensym suffixes, or pattern-match the nested
`ELet`/`ESeq` constructors directly. Do not assert a process-global gensym
number.

Run:

```bash
dune exec test/run_codegen.exe -- test single_use_inline -e --color=never
dune exec test/run_codegen.exe -- test inline -e --color=never
dune exec test/run_codegen.exe -- test dce -e --color=never
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/tir/single_use_inline.ml lib/tir/dune lib/tir/inline.ml \
  test/test_codegen.ml
git commit -m "perf(tir): inline one-use impure functions"
```

### Task 3: Integrate the Named Pass and Hot-Reload Guard

**Files:**
- Modify: `lib/tir/opt.ml`
- Modify: `test/test_codegen.ml`
- Modify: `test/test_hot_reload.ml`

**Interfaces:**
- Consumes: `Single_use_inline.run`
- Produces: optimizer phase label `tir-opt-<iteration>-single-use-inline`
- Preserves: `Inline.boundary_config` for the entire `Opt.run` fixed-point lifetime

- [ ] **Step 1: Add RED optimizer-order and HCR tests**

In `test/test_codegen.ml`, add an optimizer integration test that:

1. constructs a one-use impure helper and `main`
2. calls `March_tir.Opt.run`
3. asserts `main` no longer contains `EApp helper`
4. asserts DCE removed the helper definition

Also run `Opt.run ~snap` and assert a label ending in
`"-single-use-inline"` is observed between `"-inline"` and `"-cprop"`.

In `test/test_hot_reload.ml`, create a one-use impure
`MyApp.B` called from `MyApp.A`. Add:

```ocaml
let run_single_use_with_config config module_ =
  March_tir.Inline.boundary_config := config;
  Fun.protect
    ~finally:(fun () -> March_tir.Inline.boundary_config := None)
    (fun () ->
      March_tir.Single_use_inline.run ~changed:(ref false) module_)
```

Assert:

- `Some (HR.default_config "MyApp")` preserves the call
- `None` removes the call
- excluding `MyApp.B` makes it eligible
- force-including an external callee makes it ineligible

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
dune exec test/run_codegen.exe -- test opt -e --color=never
dune exec test/test_hot_reload.exe -- --color=never
```

Expected: optimizer integration fails because the new pass is not registered;
direct single-pass HCR tests may already pass.

- [ ] **Step 3: Register the named pass**

In `lib/tir/opt.ml`, insert:

```ocaml
"single-use-inline", Single_use_inline.run;
```

immediately after:

```ocaml
"inline", Inline.run;
```

Do not move any other pass. Keep `Inline.boundary_config` set around the whole
fixed-point loop so the new pass reads the same active configuration.

- [ ] **Step 4: Run optimizer, HCR, TCO, and reduction tests**

Run:

```bash
dune exec test/run_codegen.exe -- test opt -e --color=never
dune exec test/run_codegen.exe -- test single_use_inline -e --color=never
dune exec test/test_hot_reload.exe -- --color=never
dune exec test/run_codegen.exe -- test mutual_tco_codegen -e --color=never
dune exec test/run_codegen.exe -- test phase4_reduction_codegen -e --color=never
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/tir/opt.ml test/test_codegen.ml test/test_hot_reload.ml
git commit -m "perf(tir): schedule single-use inlining"
```

### Task 4: Prove LLVM Elimination and Native Semantics

**Files:**
- Modify: `test/test_codegen.ml`
- Create: `test/native/single_use_inline_rc.march`
- Create: `test/native/single_use_inline_rc.expected`
- Modify: `test/dune`

**Interfaces:**
- Consumes: `Opt.run`, `Llvm_emit.emit_module`, and the native compiler driver
- Produces: deterministic raw-LLVM call/definition assertions and native output parity

- [ ] **Step 1: Add the raw-LLVM RED regression**

Construct a named `one_use_effect` function taking and returning `TString`
whose body contains `EIncRC` of its parameter, an impure `println` call,
`EDecRC` of the same parameter, and a return. Construct one caller from
`main` using a string literal. Keeping the RC operations on `TString` makes
the test representative of a genuinely reference-counted value.

Before `Opt.run`, assert raw emitted LLVM contains:

```text
call ... @one_use_effect(
define ... @one_use_effect(
```

After `Opt.run`, assert both strings are absent and the caller still contains
the expected `march_incrc`/`march_decrc` and runtime-effect calls in order.
Use substring positions rather than exact SSA names.

Register this test under `"single_use_inline"`.

- [ ] **Step 2: Verify RED**

Temporarily disable the `single-use-inline` entry in `Opt.named_passes` and run:

```bash
dune exec test/run_codegen.exe -- test single_use_inline -e --color=never
```

Expected: the new LLVM test fails because the named call and definition
remain. Restore the pass immediately before continuing.

- [ ] **Step 3: Add the native fixture**

Create `test/native/single_use_inline_rc.march`:

```march
mod SingleUseInlineRc do
  fn helper(xs : List(Int)) : Int do
    println("helper:start")
    let n = List.length(xs)
    println("helper:end")
    n
  end

  fn main() : Unit do
    let xs = [10, 20, 30]
    let n = helper(xs)
    println(n)
  end
end
```

Create `test/native/single_use_inline_rc.expected`:

```text
helper:start
helper:end
3
```

Add a `test/dune` compile-and-run rule following `native_newtype_counter`.
Depend on the compiler executable, runtime C/H files used by neighboring
native rules, the fixture, and `(source_tree ../stdlib)`. Add:

- a `runtest` diff against the expected output
- an `--emit-llvm` target
- a check that fails if `@helper(` appears in either a `call` or `define`

Use a fixture-specific alias such as `single_use_inline_rc`.

- [ ] **Step 4: Run GREEN semantic and LLVM checks**

Run:

```bash
dune exec test/run_codegen.exe -- test single_use_inline -e --color=never
dune build @test/single_use_inline_rc
dune runtest
```

If full `dune runtest` is unsuitable on the shared host because of documented
quarantined fixed-port node targets, run the exact fixture alias plus the full
Alcotest codegen suite and record the quarantine instead of claiming
`dune runtest` passed.

Expected: the focused group and fixture pass; raw LLVM has neither helper call
nor definition.

- [ ] **Step 5: Commit**

```bash
git add test/test_codegen.ml test/native/single_use_inline_rc.march \
  test/native/single_use_inline_rc.expected test/dune
git commit -m "test(codegen): pin one-use impure inlining"
```

### Task 5: Measure, Document, and Verify

**Files:**
- Modify: `specs/optimizations.md`
- Modify: `specs/progress.md`

**Interfaces:**
- Consumes: merged measurement baseline from the design spec
- Produces: post-change residual-call/definition report without a brittle golden

- [ ] **Step 1: Rerun the native-corpus measurement**

Build the compiler:

```bash
dune build bin/main.exe
```

For every sorted `test/native/*.march` file except `js_*`:

1. copy it into its own `mktemp -d` directory
2. run the built compiler with `--dump-phases --emit-llvm`
3. read the final phase's `body_size`, `rc_ops`, and call metadata
4. count LLVM definitions and direct calls to those definitions
5. compare totals with the baseline of 2,468 calls and 174 size-eligible
   opportunities
6. move the generated corpus to Trash after recording results; the previous
   run consumed approximately 17 GB

Record:

- fixture count and failures
- before/after residual direct calls
- removed named definitions
- fixtures affected
- body-size and RC distribution
- compiler-output result only; no runtime claim

- [ ] **Step 2: Update optimization documentation**

In `specs/optimizations.md`, add a section after ordinary function inlining
that states:

- pass order and 50-node limit
- exact-one-total-reference rule
- impure-body relocation rationale
- root, recursion, address-taking, collision-dispatch, and HCR exclusions
- Perceus/RC ordering invariant
- measured call/definition result

In `specs/progress.md`, add a dated entry with the verified tests and
measurement. Label any timing as command wall time and explicitly state that
no runtime speedup was measured.

- [ ] **Step 3: Run focused and full verification**

Run:

```bash
dune exec test/run_codegen.exe -- test single_use_inline -e --color=never
dune exec test/run_codegen.exe -- test inline -e --color=never
dune exec test/run_codegen.exe -- test dce -e --color=never
dune exec test/test_hot_reload.exe -- --color=never
dune exec test/run_codegen.exe -- test mutual_tco_codegen -e --color=never
dune exec test/run_codegen.exe -- test phase4_reduction_codegen -e --color=never
dune exec test/run_eval.exe -- test tir -e --color=never
dune exec test/test_properties.exe -- test 'tir pipeline|tir passes|tir pass invariants' -e --color=never
dune exec test/run_codegen.exe -- test -e --color=never
./specs/lang/golden/sanitize.sh
dune build @install
git diff --check origin/main...HEAD
git status --short
```

Expected:

- every focused and full suite exits zero
- native LLVM verifier corpus remains clean
- sanitizer gate exits zero
- installable compiler targets build
- no diff whitespace errors
- worktree is clean after the documentation commit

Do not use `dune build @all` as a success gate on this shared host: the
repository documents fixed-port quarantined node targets that `@all` still
executes and may hang.

- [ ] **Step 4: Commit**

```bash
git add specs/optimizations.md specs/progress.md
git commit -m "docs: record single-use inlining"
```

- [ ] **Step 5: Review the whole branch**

Run:

```bash
git log --oneline origin/main..HEAD
git diff --stat origin/main...HEAD
git diff --check origin/main...HEAD
git status --short --branch
```

Review the complete branch against
`docs/superpowers/specs/2026-07-26-single-use-private-function-inlining-design.md`.
Critical and important findings must be fixed and reverified before handoff.
