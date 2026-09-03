# Allocation Contracts (`@[no_alloc]`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `@[no_alloc]` / `@[no_alloc(warn)]` / `@[no_alloc(assume)]` per-function allocation contract, checked on the final TIR immediately before LLVM emission, with LSP surface (diagnostic, lens, quick fix) and `forge fix --contracts` generation, per `specs/2026-09-03-allocation-contracts-design.md`.

**Architecture:** A new pure module `lib/tir/alloc_contract.ml` classifies every final-TIR node and builtin, computes the allocating-function set by fixpoint over `tm_fns`, and renders diagnostics. A new `lib/tir/contract_pipeline.ml` holds the post-lower pass sequence (TRMC → Mono → … → Native_map_inline → Alloc_contract.check) extracted mechanically from `bin/main.ml`, and both the driver and the LSP call it. Contract bookkeeping (attribute form + name span per function) is collected from the AST by name and matched to TIR functions by `Tir_names.strip_specialization_suffix`, never by mutating the TIR of annotated functions (the verdict must be the verdict of the code *as it compiles without the attribute*).

**Tech Stack:** OCaml 5.3 / dune, menhir, alcotest (`test/`, `lsp/test/`, `forge/test/`), the `march` compiler driver, `scripts/ir-oracle.sh`.

## Global Constraints

- Attribute strings in `Ast.fn_def.fn_attrs`: exactly `no_alloc`, `no_alloc:warn`, `no_alloc:assume` (the parser's `fn_attr` rule already produces `name ^ ":" ^ value`).
- No `@[in_place]`, no `opt`/`strict` payload. `@[no_alloc(<other>)]` is a parse error.
- Check runs on the FINAL TIR after `Native_map_inline`, before `Llvm_emit`. `EReuse`, `EAllocHole (Some _, …)`, `EStackAlloc` pass. `EAlloc`, `EAllocHole (None, …)`, non-empty `ETuple`, `ERecord`, `EUpdate`, closure structs, allocating builtins, `ECallPtr`, externs fail (the last two unless the enclosing function is `assume`). Float boxing counts.
- The allocating-builtin table is a TOTAL match over `Builtin_name.t` (compiler build error on an unclassified constructor). Every other builtin name is looked up in an explicit non-allocating allowlist; anything unlisted is allocating.
- Transitivity by fixpoint over `tm_fns` (pattern: `Policy_dce.panicky_fns_of_module`). No callee annotations.
- `--opt N` cannot affect the verdict. `--no-opt` downgrades a hard failure to a warning that names the flag. TRMC-off + `Trmc` verdict `Eligible` ⇒ one extra note line pointing at `--trmc`.
- Interpreted runs and `--check` ignore the attribute silently. `cap no_alloc` (`lib/refinecheck/no_alloc.ml`) is NOT changed.
- Pipeline-tail extraction moves NO IR: `scripts/ir-oracle.sh baseline` before, `check` after, under a private `HOME`, with a proven RED on a deliberate perturbation before trusting GREEN.
- Build: `dune build --root . <target>` from the worktree. Tests: `scripts/run-tests.sh` (full) before claiming done; never run it concurrently with another dune process. `dune build --root . @install` before any compiled end-to-end test (restages stdlib + runtime).
- Git: explicit `git add <paths>`; no stash; no attribution trailers; commit per task.
- Diagnostics follow the house style; texts are pinned in tests (substring match on the rendered output).

## Verified facts about the codebase (do not re-derive)

- `Ast.fn_def` has `fn_attrs : string list` and `fn_name : Ast.name` (`{ txt; span }`). `DFn (def, span)`; `DMod (name, _, inner, _)`; `DActor (vis, name, adef, span)`. Parser rules: `fn_attr` and `decl` at `lib/parser/parser.mly:304-340`; attrs before `actor_decl` are accepted (only `compat:` is read); attrs before `extern`/`type` are already a generic parse error.
- `Vectorize_mark.collect_attrs` (`lib/tir/vectorize_mark.ml`) walks `DFn`/`DMod` producing the module-qualified pre-Mono TIR name (`Inner.helper`). Copy that walk.
- `Tir_names.strip_specialization_suffix` (`lib/tir/tir_names.ml:302`) maps `f$Int` → `f`, `M.f$Int` → `M.f`, `f$2` (default-arg mangle) → `f`. `Tir_names.is_apply_fn` detects `<fn>$apply$<uid>`.
- `Mono.monomorphize` only seeds monomorphic fns + `main` + migrate fns; polymorphic originals never survive, only on-demand clones (`lib/tir/mono.ml:1268-1326`). Mono does not touch `tm_exports`.
- `Dce.root_names` roots `main`, setup/migrate fns, `tm_exports`, `tm_tests`; `extra_root` only applies when there are no other roots (`lib/tir/dce.ml:75-120`). `Opt.run` runs DCE internally with no `extra_root`. Therefore keeping an annotated function alive for the check = add its post-Mono name to `tm_exports` before `Opt.run`.
- `Policy_dce` (`lib/tir/policy_dce.ml`): `fold_expr`, `panicky_fns_of_module` (fixpoint pattern), `policies_of_fn` (Tagged params: `TCon ("Tagged", [_; TCon (policy, [])])`), `check_noalloc` (EAlloc/EStackAlloc), `audit` called at `bin/main.ml:2150` (prints `Error: %s`, exits 1). No other caller of `check_noalloc` exists (grep-verified).
- `Builtin_name.t` (`lib/tir/builtin_name.ml`) has 57 constructors; `to_string`/`of_string`.
- `Trmc` (`lib/tir/trmc.ml`): `type verdict = Eligible | Mixed | Non_trmc | Already_tail | No_recursion`, `analyze_module : tir_module -> fn_report list`, `verdict_of`, `report` (env-gated print), `enabled : bool ref`, `transform_module` (gated on `!enabled`). Runs on POST-LOWER, PRE-MONO TIR (`bin/main.ml:2018-2022`).
- `bin/main.ml` pipeline tail spans lines ~2018 (`Trmc.report`) to ~2512 (`snap_tir "tir-native-map-inline"`). Driver-only concerns interleaved in it: wasm island exports before/after Mono (2090-2125), `__rpc_stub` export pinning (2128-2143), Policy_dce audit + exit after Fusion (2150-2153), `pre_opt_tir` capture + cap attribution + `--cap-strict` exit before `Opt.run` (2222-2447), Vectorize diagnostics print + exit (2480-2502), JS-target gates (`is_js_target`: Vectorize_check, Native_map_inline, Drop), `hr_config ()` into `Opt.run`, `snap_tir`/`stamp` observers, `opt_enabled` gating Fusion/Known_call/Beta_adt/Join_points.run_pre/Simplify/Opt.run.
- `Vectorize_check.check : Errors.ctx -> tir_module -> tir_module` (strips sentinels; its return value MUST be used).
- LSP `run_tir_pass` (`lsp/lib/analysis.ml:3341-3520`) runs Lower → Mono → Defun → Known_call → Borrow.infer_module (pre-Perceus, for `consume_modes`) → Perceus → Escape, then computes `tir_fn_insights` (skipping `$`-prefixed fns), `code_lens_items` (title joined with ` · `), `tir_perf_insights`. Memoised in `tir_pass_cache` keyed by source hash. `a.def_map : (string, Ast.span) Hashtbl.t` maps fn name (and `Prefix.name`) → span. `diag_to_lsp ~filename (d : Err.diagnostic)` (`analysis.ml:104`) converts compiler diagnostics. `server.ml:340-354` republishes `a2.diagnostics` after the TIR pass when `a2 != a`.
- Code actions: `Code_actions_diag.code_actions_at (a : t) ~line ~character` (`lsp/lib/code_actions_diag.ml:23`); insert-edit precedent is `html_close_actions` (~line 968): `TextEdit.create ~range:(Range.create ~start:pos ~end_:pos) ~newText`. Test precedent: `lsp/test/test_lsp_perf.ml:656-680` (`pos_of src "…"`, `An.code_actions_at a ~line ~character:col ()`).
- LSP test harness: `Test_lsp_harness.analyse src` (`filename:"test.march"`), `An` = `March_lsp_lib.Analysis`; feature tests in `lsp/test/test_lsp_features.ml`, registered in `lsp/test/test_lsp.ml` (~line 480-490 block for TIR tests).
- `Errors.diagnostic` = `{ severity; span; message; labels; notes; code; fix }`; `Errors.render_diagnostic ~src ~filename d` prints `notes` as a trailing block; `Errors.render_diagnostic_json` emits the `--check-json` line shape with `"fix":{"kind":"insert","after_line":N,"text":…}`. `FInsert { after_line; text }` inserts `text` as a new line AFTER `after_line` (1-indexed), so "line before the declaration" = `after_line = decl_start_line - 1`.
- End-to-end compile helper: `Test_cap_ceiling.compile_with ~flags src_text : int * string` (`test/test_cap_ceiling.ml:105`; exe-relative `../bin/main.exe`, captures stdout+stderr, deletes the binary). `test/dune` lists test modules in the `march_test_compiler` library `modules` field (line 14); suites are registered in `test/test_compiler.ml` ~line 14865 as `("cap_ceiling", Test_cap_ceiling.tests)`.
- Forge: `Cmd_fix.run ?dry_run ()` (`forge/lib/cmd_fix.ml:172`) runs `march --check-json` per file via `collect_all_fixes ~lib_path_env files`, applies by file. CLI `fix_cmd` at `forge/bin/main.ml:203-215` (cmdliner). `Project.load_from` (`forge/lib/project.ml:220`) reads sections with `Toml.get_section doc "name"` / `Toml.get_string_list pairs key`. Hermetic forge test harness: `forge/test/test_build_check.ml` (`setup_hermetic_march`, `with_project`, `write_file`, `contains`).
- Forge builds pass `--opt 0` (debug) or `--opt 2` (release); never `--no-opt`, never `--trmc` (`forge/lib/cmd_build.ml:484-497`).
- `main.ml` flags: `opt_enabled : bool ref` (cleared by `--no-opt`, line 4268); `--trmc` sets `March_tir.Trmc.enabled := true` (4270); `MARCH_TRMC` env also enables it (4293). `--check-json` output loop at 1819. `--dump-tir` branch at ~2530 exits before emit.
- Float boxing (`march_alloc_float`) is emitted by `Llvm_ctx.coerce` for `("double","ptr")`: a `TFloat` value stored into a slot whose LLVM type is `ptr` — a constructor/record field whose declared type is not `TFloat` (e.g. a `TVar` payload such as `Some(a)` — see `llvm_emit_alloc.ml:190-228`, `field_ty = llvm_ty (List.nth entry.ce_fields i)`), an `ECallPtr` argument, or an argument of a direct apply-fn call (`llvm_emit_call.ml:130-160`, "Boundary B").
- `Tir.EAlloc (ty, args)`: `ty` is `TCon (ctor_name, _)` naming the CONSTRUCTOR (pretty-printed `alloc Cons(h, t)`); closure structs are `TCon ("$Clo_…", _)` (`Tir_names.is_clo_struct`). `Tir.ETuple []` is unit (emitted as `i64 0`, not an allocation).
- `tm_externs : extern_decl list` with `ed_march_name`.
- Docs to edit: `specs/lang/surface-syntax.md` ("Visibility & Doc/Attrs", ~line 720) + `docs/surface-syntax.md` (verify the file exists; if the served copy is under another name, `grep -rl "@\[deprecated\]" docs/`), `specs/lang/capabilities.md` (`### \`cap no_alloc\``, line 652), `specs/lang/memory-model.md` ("## Writing allocation-free code", line 186), `specs/features/compiler-pipeline.md` (pass-order note line 93 and pass table ~line 1226).

---

### Task 1: Attribute forms, parser rejection, and AST collection

**Files:**
- Create: `lib/tir/alloc_contract.ml` (only the attribute/collection half in this task)
- Modify: `lib/tir/dune` (add `alloc_contract` to `modules`)
- Modify: `lib/parser/parser.mly:315-340`
- Create: `test/test_alloc_contract.ml`; Modify: `test/dune:14`, `test/test_compiler.ml` (suite registration)

**Interfaces:**
- Produces:
  ```ocaml
  (* lib/tir/alloc_contract.ml *)
  type form = Hard | Warn | Assume
  val form_of_attrs : string list -> form option
  type decl_info = { d_name : string; (* module-qualified pre-Mono TIR name *)
                     d_form : form option;
                     d_name_span : March_ast.Ast.span;   (* the identifier *)
                     d_decl_span : March_ast.Ast.span }  (* whole DFn *)
  val collect : March_ast.Ast.module_ -> decl_info list  (* every DFn, nested DMod prefixed *)
  ```

- [ ] **Step 1: Write the failing tests** (new file `test/test_alloc_contract.ml`)

```ocaml
(* @[no_alloc] allocation contracts — lib/tir/alloc_contract.ml *)
open Test_helpers
module AC = March_tir.Alloc_contract

let attrs_of src fn =
  let m = parse_and_desugar src in
  let rec find = function
    | [] -> None
    | March_ast.Ast.DFn (d, _) :: _ when d.March_ast.Ast.fn_name.March_ast.Ast.txt = fn ->
      Some d.March_ast.Ast.fn_attrs
    | March_ast.Ast.DMod (_, _, inner, _) :: rest ->
      (match find inner with Some a -> Some a | None -> find rest)
    | _ :: rest -> find rest
  in
  find m.March_ast.Ast.mod_decls

let test_attr_forms_parse () =
  let src = {|mod T do
  @[no_alloc]
  fn a(x : Int) : Int do x end
  @[no_alloc(warn)]
  fn b(x : Int) : Int do x end
  @[no_alloc(assume)]
  fn c(x : Int) : Int do x end
end|} in
  Alcotest.(check (option (list string))) "hard" (Some ["no_alloc"]) (attrs_of src "a");
  Alcotest.(check (option (list string))) "warn" (Some ["no_alloc:warn"]) (attrs_of src "b");
  Alcotest.(check (option (list string))) "assume" (Some ["no_alloc:assume"]) (attrs_of src "c")

let test_form_of_attrs () =
  Alcotest.(check bool) "hard" true (AC.form_of_attrs ["no_alloc"] = Some AC.Hard);
  Alcotest.(check bool) "warn" true (AC.form_of_attrs ["vectorize"; "no_alloc:warn"] = Some AC.Warn);
  Alcotest.(check bool) "assume" true (AC.form_of_attrs ["no_alloc:assume"] = Some AC.Assume);
  Alcotest.(check bool) "none" true (AC.form_of_attrs ["vectorize"] = None)

let test_collect_qualifies_nested () =
  let m = parse_and_desugar {|mod T do
  mod Inner do
    @[no_alloc]
    fn helper(x : Int) : Int do x end
  end
  fn plain(x : Int) : Int do x end
end|} in
  let ds = AC.collect m in
  let find n = List.find_opt (fun d -> d.AC.d_name = n) ds in
  (match find "Inner.helper" with
   | Some d -> Alcotest.(check bool) "helper is Hard" true (d.AC.d_form = Some AC.Hard);
               Alcotest.(check int) "name span line" 4 d.AC.d_name_span.March_ast.Ast.start_line
   | None -> Alcotest.fail "Inner.helper not collected");
  (match find "plain" with
   | Some d -> Alcotest.(check bool) "plain has no form" true (d.AC.d_form = None)
   | None -> Alcotest.fail "plain not collected")

let test_bad_payload_is_parse_error () =
  let msg = parse_error_msg {|mod T do
  @[no_alloc(strict)]
  fn a(x : Int) : Int do x end
end|} in
  Alcotest.(check bool) "mentions no_alloc" true (contains "no_alloc" msg)

let test_no_alloc_on_actor_is_parse_error () =
  let msg = parse_error_msg {|mod T do
  @[no_alloc]
  actor Counter do
    state { value : Int }
    init { value: 0 }
    on Inc(n : Int) do { state with value: state.value + n } end
  end
end|} in
  Alcotest.(check bool) "mentions actors" true (contains "actor" msg)

let tests = [
  Alcotest.test_case "attribute forms parse"          `Quick test_attr_forms_parse;
  Alcotest.test_case "form_of_attrs"                  `Quick test_form_of_attrs;
  Alcotest.test_case "collect qualifies nested names" `Quick test_collect_qualifies_nested;
  Alcotest.test_case "bad payload is a parse error"   `Quick test_bad_payload_is_parse_error;
  Alcotest.test_case "no_alloc on actor is rejected"  `Quick test_no_alloc_on_actor_is_parse_error;
]
```

Check `Test_helpers.parse_error_msg` (`test/test_helpers.ml:225`) returns the message string of a `ParseError`; if it returns something else, adapt the two assertions to its actual shape.

Register: in `test/dune` line 14 add `test_alloc_contract` to the `modules` list; in `test/test_compiler.ml` next to `("cap_ceiling", Test_cap_ceiling.tests);` add `("alloc_contract", Test_alloc_contract.tests);`.

- [ ] **Step 2: Run to verify failure**

Run: `dune build --root . test/run_compiler.exe 2>&1 | head -20`
Expected: build error `Unbound module March_tir.Alloc_contract`.

- [ ] **Step 3: Implement**

`lib/tir/alloc_contract.ml` (first half):

```ocaml
(** @[no_alloc] allocation contracts — see
    specs/2026-09-03-allocation-contracts-design.md. *)

type form = Hard | Warn | Assume

let form_of_attrs (attrs : string list) : form option =
  if List.mem "no_alloc" attrs then Some Hard
  else if List.mem "no_alloc:warn" attrs then Some Warn
  else if List.mem "no_alloc:assume" attrs then Some Assume
  else None

type decl_info = {
  d_name      : string;
  d_form      : form option;
  d_name_span : March_ast.Ast.span;
  d_decl_span : March_ast.Ast.span;
}

(* Same walk as [Vectorize_mark.collect_attrs]: the module-qualified name is
   exactly what [Lower] gives the TIR fn_def before Mono mangles it. *)
let rec collect_prefixed (prefix : string) (decls : March_ast.Ast.decl list) : decl_info list =
  List.concat_map (function
      | March_ast.Ast.DFn (def, span) ->
        [ { d_name = prefix ^ def.March_ast.Ast.fn_name.March_ast.Ast.txt;
            d_form = form_of_attrs def.March_ast.Ast.fn_attrs;
            d_name_span = def.March_ast.Ast.fn_name.March_ast.Ast.span;
            d_decl_span = span } ]
      | March_ast.Ast.DMod (nm, _, inner, _) ->
        collect_prefixed (prefix ^ nm.March_ast.Ast.txt ^ ".") inner
      | _ -> [])
    decls

let collect (m : March_ast.Ast.module_) : decl_info list =
  collect_prefixed "" m.March_ast.Ast.mod_decls
```

Add `alloc_contract` to the `modules` list in `lib/tir/dune` (after `tir_names`, since it depends only on `Tir_names`, `Tir`, `Builtin_name`, `March_ast`, `March_errors`; the order in that list is not significant to dune, but keep it readable).

Parser (`lib/parser/parser.mly`): in the `attrs = nonempty_list(fn_attr); d = fn_decl` action, validate before building the DFn:

```ocaml
  | attrs = nonempty_list(fn_attr); d = fn_decl
    { List.iter (fun a ->
          if String.length a > 9 && String.sub a 0 9 = "no_alloc:"
             && a <> "no_alloc:warn" && a <> "no_alloc:assume" then
            error_raise
              (Printf.sprintf "I don't recognize `@[no_alloc(%s)]` — the forms are `@[no_alloc]`, `@[no_alloc(warn)]`, and `@[no_alloc(assume)]`."
                 (String.sub a 9 (String.length a - 9)))
              None $startpos(attrs)) attrs;
      match d with
      | DFn (def, span) -> DFn ({ def with fn_attrs = attrs }, span)
      | d -> d }
```

In BOTH actor rules that take `attrs = nonempty_list(fn_attr)` (lines 319 and 332), add first:

```ocaml
      if List.exists (fun a -> a = "no_alloc" || (String.length a > 9 && String.sub a 0 9 = "no_alloc:")) attrs then
        error_raise "`@[no_alloc]` only applies to `fn` and `pfn` declarations, not to actors." None $startpos(attrs);
```

Check how `error_raise` is defined at the top of `parser.mly` (signature `string -> string option -> Lexing.position -> 'a`) and match it.

- [ ] **Step 4: Run the tests**

Run: `dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe test alloc_contract`
Expected: 5 passing. Also `dune build --root . @grammar-check` is CI-only; run `dune build --root . bin/main.exe` to make sure menhir has no new conflicts (menhir prints conflict warnings on stderr — there must be none new; compare against `git stash`-free baseline by running the same build on `HEAD` in a scratch checkout if any appear).

- [ ] **Step 5: Commit**

```bash
git add lib/tir/alloc_contract.ml lib/tir/dune lib/parser/parser.mly test/test_alloc_contract.ml test/dune test/test_compiler.ml
git commit -m "feat(contracts): parse @[no_alloc] forms and collect them from the AST"
```

---

### Task 2: IR-oracle baseline and RED proof (before any pipeline change)

**Files:** none modified (scratch only). Uses `scripts/ir-oracle.sh`.

- [ ] **Step 1: Build the compiler and stage stdlib/runtime**

```bash
dune build --root . bin/main.exe @install 2>&1 | tail -3
```

- [ ] **Step 2: Record the baseline under a private HOME**

```bash
export ORACLE_HOME=/private/tmp/claude-502/-Users-80197052-code-march--claude-worktrees-interesting-liskov-08b3f6/d25b14d2-c731-4571-a325-4cd4ab06c623/scratchpad/oracle-home
mkdir -p "$ORACLE_HOME"
HOME="$ORACLE_HOME" scripts/ir-oracle.sh baseline "$ORACLE_HOME/ir-base" 2>&1 | tail -3
```
Expected: `baseline recorded … (N programs)` with N ≥ 100.

- [ ] **Step 3: Prove RED with a deliberate perturbation**

Temporarily edit `bin/main.ml` line ~2194: change `March_tir.Simplify.run ~pre_perceus:true` to `~pre_perceus:false` (skips the pre-Perceus concat folds). Rebuild `bin/main.exe`, then:

```bash
HOME="$ORACLE_HOME" scripts/ir-oracle.sh check "$ORACLE_HOME/ir-base" 2>&1 | head -5
```
Expected: `IR CHANGED — K differing lines` with K > 0, exit 1. If it says IDENTICAL, the oracle is vacuous — stop and find out why (stale exe? wrong HOME?) before continuing.

- [ ] **Step 4: Revert the perturbation and prove GREEN on the unchanged tree**

`git checkout bin/main.ml`, rebuild, `check` again. Expected: `IR IDENTICAL across N programs`. Record N in your notes; Task 3 must reproduce it.

---

### Task 3: Extract the pipeline tail into `Contract_pipeline.run`

**Files:**
- Create: `lib/tir/contract_pipeline.ml`
- Modify: `lib/tir/dune` (add `contract_pipeline` — it must come AFTER every pass module in the dependency sense; dune orders automatically), `lib/tir/trmc.ml` (`transform_module ?enabled`), `bin/main.ml:2018-2515`

**Interfaces:**
- Produces:
  ```ocaml
  (* lib/tir/contract_pipeline.ml *)
  type result = {
    pre_opt : Tir.tir_module;          (* snapshot taken right after Escape, before Opt.run *)
    final   : Tir.tir_module;          (* after Native_map_inline; ready for Llvm_emit *)
    vectorize_diags : March_errors.Errors.diagnostic list;
  }
  val run :
    ?snap:(string -> Tir.tir_module -> unit) ->   (* per-stage observer: same labels main.ml uses *)
    ?stamp:(string -> unit) ->
    ?after_fusion:(Tir.tir_module -> unit) ->     (* driver hook: Policy_dce audit *)
    ?before_perceus:(Tir.tir_module -> unit) ->   (* LSP hook: Borrow.infer_module *)
    ?before_opt:(Tir.tir_module -> unit) ->       (* driver hook: cap attribution / --cap-strict *)
    ?extra_roots:string list ->                   (* post-Mono fn names appended to tm_exports before Opt.run *)
    ?wasm_island:bool -> ?is_js:bool ->
    ?hot_reload:March_tir.Hot_reload.config option ->
    ?iface_methods:<type of Lower.get_iface_methods ()> ->
    opt:bool -> trmc:bool -> Tir.tir_module -> result
  ```
  (Read the type of `March_tir.Lower.get_iface_methods ()` and `Mono.monomorphize ~iface_methods` and use it verbatim; if the LSP passes none today, default `?iface_methods` to the empty table the LSP's call implies.)

- [ ] **Step 1: `Trmc.transform_module ?enabled`**

In `lib/tir/trmc.ml:470`: `let transform_module ?(enabled = !enabled) (m : Tir.tir_module) : Tir.tir_module = if not enabled then m else …`. Rebuild; no behaviour change.

- [ ] **Step 2: Write `contract_pipeline.ml`** — a mechanical copy of `bin/main.ml` 2018-2512 with the driver concerns replaced by the hooks. The body, in order, with the exact `snap` labels and `stamp` labels main.ml uses today:

```ocaml
(** The post-Lower TIR pipeline shared by the compiler driver and the LSP.
    Extracted mechanically from bin/main.ml (2026-09-03); proven IR-identical
    with scripts/ir-oracle.sh. Order matters — see
    specs/features/compiler-pipeline.md "Pass-order note". *)

type result = { pre_opt : Tir.tir_module; final : Tir.tir_module;
                vectorize_diags : March_errors.Errors.diagnostic list }

let island_suffixes = ["render"; "update"; "init"]

let run ?(snap = fun _ _ -> ()) ?(stamp = fun _ -> ())
    ?(after_fusion = fun _ -> ()) ?(before_perceus = fun _ -> ())
    ?(before_opt = fun _ -> ()) ?(extra_roots = [])
    ?(wasm_island = false) ?(is_js = false) ?(hot_reload = None)
    ?(iface_methods = Hashtbl.create 0) ~opt ~trmc (tir : Tir.tir_module) : result =
  Trmc.report tir;
  let tir = Trmc.transform_module ~enabled:trmc tir in
  (* wasm island exports BEFORE mono — verbatim from main.ml 2090-2103 *)
  let tir = if wasm_island then <copy the pre-mono exports block> else tir in
  let tir = Mono.monomorphize ~iface_methods tir in
  snap "tir-mono" tir; stamp "mono";
  let tir = if tir.Tir.tm_exports <> [] then <copy the post-mono island rename block 2110-2125> else tir in
  let tir = <copy the __rpc_stub pinning block 2128-2143> in
  let tir = if opt then Fusion.run ~changed:(ref false) tir else tir in
  snap "tir-fusion" tir; stamp "fusion";
  after_fusion tir;
  let tir = Defun.defunctionalize tir in
  snap "tir-defun" tir; stamp "defun";
  let tir = if opt then Known_call.run ~changed:(ref false) tir else tir in
  snap "tir-known-call" tir;
  let tir = if opt then Beta_adt.run ~changed:(ref false) tir else tir in
  snap "tir-beta-adt-pre" tir;
  let tir = if opt then Join_points.run_pre ~changed:(ref false) tir else tir in
  snap "tir-join-points-pre" tir;
  let tir = if opt then Simplify.run ~pre_perceus:true ~changed:(ref false) tir else tir in
  snap "tir-simplify-pre" tir;
  before_perceus tir;
  let tir = Perceus.perceus tir in
  snap "tir-perceus" tir; stamp "perceus";
  let tir = if is_js then tir else Drop.run tir in
  snap "tir-drop" tir; stamp "drop";
  let tir = Escape.escape_analysis tir in
  snap "tir-escape" tir; stamp "escape";
  let pre_opt = tir in
  before_opt pre_opt;
  let tir =
    if extra_roots = [] then tir
    else { tir with Tir.tm_exports = tir.Tir.tm_exports @ extra_roots } in
  let tir = if opt then Opt.run ~snap ~hot_reload tir else tir in
  let tir = Dce.prune_unreachable tir in
  let (tir, vectorize_diags) =
    if is_js then (tir, [])
    else
      let ctx = March_errors.Errors.create () in
      let tir' = Vectorize_check.check ctx tir in
      (tir', March_errors.Errors.sorted ctx) in
  let tir = if is_js then tir else Native_map_inline.run tir in
  snap "tir-native-map-inline" tir;
  if not opt then snap "tir-opt" tir;
  stamp "opt";
  { pre_opt; final = tir; vectorize_diags }
```

Note `Opt.run ~snap`: main.ml passes a snap that only records `phases` when `dump_phases`; main's `snap_tir` does the same thing plus `MARCH_DUMP_TXT`. Passing `snap` through to `Opt.run` changes only the *observer*, not the IR; confirm `Opt.run`'s `~snap` labels are distinct from the top-level ones so `MARCH_DUMP_TXT` output does not double up (read `lib/tir/opt.ml:45-80`). If Opt's snap labels are used by `march-phases/phases.json`, keep main's exact closure shapes by letting main pass `~snap` for the top-level labels and the SAME function is fine for Opt.

Copy the three "verbatim" blocks by cut-and-paste from main.ml, replacing `March_tir.` prefixes with bare module names (we are inside `march_tir`).

- [ ] **Step 3: Replace the block in `bin/main.ml`**

Replace lines from `March_tir.Trmc.report tir;` through `stamp "opt";` with:

```ocaml
    let is_wasm_island = (parse_target !target_str = March_tir.Llvm_emit.Wasm32Unknown) in
    let iface_methods = March_tir.Lower.get_iface_methods () in
    let policy_audit tir =
      let policy_violations = March_tir.Policy_dce.audit tir in
      List.iter (fun (_fn_name, msg) -> Printf.eprintf "Error: %s\n\n" msg) policy_violations;
      if policy_violations <> [] then exit 1
    in
    let cap_attrib_ref = ref [] and cap_decls_ref = ref [] in
    let before_opt pre_opt_tir =
      <the ENTIRE existing block from `let cap_attrib = …` through the end of `if !cap_strict then begin … end;`,
       unchanged, but ending with `cap_attrib_ref := cap_attrib; cap_decls_ref := cap_decls`>
    in
    let pipe =
      March_tir.Contract_pipeline.run
        ~snap:snap_tir ~stamp ~after_fusion:policy_audit ~before_opt
        ~wasm_island:is_wasm_island ~is_js:is_js_target ~hot_reload:(hr_config ())
        ~iface_methods ~opt:!opt_enabled ~trmc:!March_tir.Trmc.enabled tir
    in
    let pre_opt_tir = pipe.March_tir.Contract_pipeline.pre_opt in
    let tir = pipe.March_tir.Contract_pipeline.final in
    let cap_attrib = !cap_attrib_ref and cap_decls = !cap_decls_ref in
    let vectorize_diags = pipe.March_tir.Contract_pipeline.vectorize_diags in
    <keep the existing vectorize print loop + `exit 1` on Error unchanged>
```

Keep the actor-schema / `actor_compat_map` / `actor_invariant_map` / `ty_to_schema_str` blocks (2024-2080) where they are — they read `tir.tm_types` *pre-Mono*, so they must stay BEFORE the `Contract_pipeline.run` call (they only read, never rewrite `tir`). `rpc_impl_hashes` (2519-2527) reads `pre_opt_tir` — unchanged.

Watch `hr_config ()`: it is called once in main today for `Opt.run`; keep one call.

- [ ] **Step 4: Build and run the oracle GREEN**

```bash
dune build --root . bin/main.exe 2>&1 | head -30
HOME="$ORACLE_HOME" scripts/ir-oracle.sh check "$ORACLE_HOME/ir-base" 2>&1 | head -5
```
Expected: `IR IDENTICAL across N programs` with the same N as Task 2 Step 4. Any diff = the extraction moved behaviour; fix the extraction, never the baseline.

- [ ] **Step 5: Run the quick suites**

```bash
scripts/run-tests.sh -q compiler codegen
```
Expected: same counts as before this task (record them from a run at Task 1's commit if you have not already).

- [ ] **Step 6: Commit**

```bash
git add lib/tir/contract_pipeline.ml lib/tir/dune lib/tir/trmc.ml bin/main.ml
git commit -m "refactor(tir): extract the post-lower pipeline tail into Contract_pipeline.run (IR-oracle green)"
```

---

### Task 4: The LSP uses `Contract_pipeline.run`

**Files:**
- Modify: `lsp/lib/analysis.ml:3387-3417`
- Test: `lsp/test/test_lsp_features.ml` (existing TIR tests must stay green)

**Interfaces:**
- Consumes: `Contract_pipeline.run ?before_perceus ?extra_roots ~opt ~trmc`.

- [ ] **Step 1: Replace the hand-rolled pass list**

```ocaml
      let tir = March_tir.Lower.lower_module ~type_map:a.type_map desugared in
      let borrow_map = ref None in
      (* Root every function this file declares so the build's DCE inside
         Opt.run cannot prune a helper that main never calls — the lens must
         still describe it. Its BODY is optimised exactly as the build
         optimises it; only reachability differs. Names are post-Mono, so
         root the stems' clones by scanning tm_fns after Mono? No — Mono
         runs inside [run]; instead root by pre-Mono name AND rely on
         [Dce.root_names]'s tolerance of unknown names, and root clones via
         the base-name match below. *)
      let user_names = Hashtbl.fold (fun k _ acc -> k :: acc) a.def_map [] in
      let pipe =
        March_tir.Contract_pipeline.run
          ~before_perceus:(fun m -> borrow_map := Some (March_tir.Borrow.infer_module m, m))
          ~extra_roots:user_names
          ~opt:true ~trmc:!March_tir.Trmc.enabled tir
      in
      let consume_modes =
        match !borrow_map with
        | None -> []
        | Some (borrow_map, pre) -> <existing consume_modes computation over pre.Tir.tm_fns>
      in
      let tir = pipe.March_tir.Contract_pipeline.final in
```

`extra_roots` are appended to `tm_exports` *after* Mono in `run`, so a polymorphic user function's clones (`f$Int`) are NOT rooted by the bare name `f`. Handle that inside `Contract_pipeline.run`: expand `extra_roots` to every `tm_fns` name whose `Tir_names.strip_specialization_suffix` is in the set (do this in `run`, right before appending, so Task 6's contract roots get the same treatment). Rewrite the comment above accordingly.

- [ ] **Step 2: Run the LSP suites**

```bash
dune build --root . lsp/bin/main.exe lsp/test/test_lsp.exe lsp/test/test_incremental.exe && ./_build/default/lsp/test/test_lsp.exe -e && ./_build/default/lsp/test/test_incremental.exe -e
```
Expected: all green. If a lens-count assertion moves because Opt now inlines (e.g. `test_code_lens_consistent_with_tir_insights`), read the test: it must remain non-vacuous; adjust the fixture, not the assertion's meaning.

- [ ] **Step 3: Commit**

```bash
git add lsp/lib/analysis.ml lib/tir/contract_pipeline.ml
git commit -m "refactor(lsp): run the shared Contract_pipeline instead of a hand-rolled pass list"
```

---

### Task 5: Allocation classifier and transitive set (pure, unit-tested on hand-built TIR)

**Files:**
- Modify: `lib/tir/alloc_contract.ml`
- Test: `test/test_alloc_contract.ml`

**Interfaces:**
- Produces:
  ```ocaml
  type reason =
    | Ctor of string | Tuple | Record | Update | Closure
    | Builtin of string | FloatBox
    | UnknownClosure of string   (* ECallPtr on this variable *)
    | Extern of string
    | Callee of string * reason  (* callee display name, its first reason *)
  val describe : reason -> string
  val builtin_allocates : string -> bool     (* total over Builtin_name.t + allowlist; conservative *)
  val is_assume : decls:decl_info list -> string -> bool   (* by stripped base name *)
  val allocating_fns : decls:decl_info list -> Tir.tir_module -> (string, reason) Hashtbl.t
  val has_reuse_or_stack : Tir.expr -> bool   (* EReuse / EAllocHole (Some _) / EStackAlloc present *)
  ```

- [ ] **Step 1: Write the failing unit tests**

Add to `test/test_alloc_contract.ml` (helpers build TIR by hand; `mk_var` etc.):

```ocaml
module T = March_tir.Tir
let v n ty = { T.v_name = n; v_ty = ty; v_lin = T.Unr }
let fn name body = { T.fn_name = name; fn_params = []; fn_ret_ty = T.TInt; fn_body = body; fn_kind = T.FnNormal }
let modl fns = { T.tm_name = "M"; tm_fns = fns; tm_types = [T.TDVariant ("Box", [("Box", [T.TInt])])];
                 tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] }
let call f = T.EApp (v f T.TInt, [])
let decl ?form n = { AC.d_name = n; d_form = form; d_name_span = March_ast.Ast.dummy_span; d_decl_span = March_ast.Ast.dummy_span }

let test_builtin_table_total_and_conservative () =
  Alcotest.(check bool) "+ does not allocate" false (AC.builtin_allocates "+");
  Alcotest.(check bool) "++ allocates" true (AC.builtin_allocates "++");
  Alcotest.(check bool) "int_to_string allocates" true (AC.builtin_allocates "int_to_string");
  Alcotest.(check bool) "unknown name allocates" true (AC.builtin_allocates "totally_unknown_builtin");
  List.iter (fun c -> ignore (AC.builtin_allocates (March_tir.Builtin_name.to_string c)))
    March_tir.Builtin_name.all

let test_fixpoint_transitive () =
  let m = modl [ fn "g" (T.EAlloc (T.TCon ("Box", []), [T.ALit (March_ast.Ast.LitInt 1)]));
                 fn "f" (call "g"); fn "h" (T.EAtom (T.ALit (March_ast.Ast.LitInt 0))) ] in
  let set = AC.allocating_fns ~decls:[] m in
  Alcotest.(check bool) "g direct" true (Hashtbl.mem set "g");
  (match Hashtbl.find_opt set "f" with
   | Some (AC.Callee ("g", AC.Ctor "Box")) -> ()
   | _ -> Alcotest.fail "f should be Callee(g, Ctor Box)");
  Alcotest.(check bool) "h clean" false (Hashtbl.mem set "h")

let test_assume_removes_and_unseeds () =
  let m = modl [ fn "wrap" (T.ECallPtr (T.AVar (v "cb" (T.TPtr T.TUnit)), []));
                 fn "user" (call "wrap") ] in
  let set = AC.allocating_fns ~decls:[decl ~form:AC.Assume "wrap"] m in
  Alcotest.(check bool) "assume is clean" false (Hashtbl.mem set "wrap");
  Alcotest.(check bool) "caller of assume is clean" false (Hashtbl.mem set "user");
  let set2 = AC.allocating_fns ~decls:[] m in
  (match Hashtbl.find_opt set2 "wrap" with
   | Some (AC.UnknownClosure "cb") -> () | _ -> Alcotest.fail "ECallPtr without assume must fail")

let test_reuse_and_stack_pass_float_box_fails () =
  let x = v "x" T.TInt in
  let reuse = T.EReuse (T.AVar (v "o" (T.TCon ("Box", []))), T.TCon ("Box", []), [T.AVar x]) in
  let stack = T.EStackAlloc (T.TCon ("Box", []), [T.AVar x]) in
  let m = modl [ fn "r" reuse; fn "s" stack ] in
  let set = AC.allocating_fns ~decls:[] m in
  Alcotest.(check bool) "reuse clean" false (Hashtbl.mem set "r");
  Alcotest.(check bool) "stack clean" false (Hashtbl.mem set "s");
  (* Float into an erased (TVar) payload boxes even under reuse *)
  let m2 = { (modl [ fn "fb" (T.EReuse (T.AVar (v "o" (T.TCon ("Some", []))), T.TCon ("Some", []),
                                        [T.AVar (v "f" T.TFloat)])) ])
             with T.tm_types = [T.TDVariant ("Option", [("None", []); ("Some", [T.TVar "a"])])] } in
  (match Hashtbl.find_opt (AC.allocating_fns ~decls:[] m2) "fb" with
   | Some AC.FloatBox -> () | _ -> Alcotest.fail "Float into TVar payload must be FloatBox")

let test_spec_clone_resolves_to_decl () =
  let m = modl [ fn "wrap$Int" (T.ECallPtr (T.AVar (v "cb" (T.TPtr T.TUnit)), [])) ] in
  let set = AC.allocating_fns ~decls:[decl ~form:AC.Assume "wrap"] m in
  Alcotest.(check bool) "clone inherits assume" false (Hashtbl.mem set "wrap$Int")
```
Add the five cases to `tests`. Check `March_ast.Ast.dummy_span` exists (main.ml uses it); if it is named differently, use that name.

- [ ] **Step 2: Run to verify failure** — `dune build --root . test/run_compiler.exe` fails on unbound `AC.builtin_allocates` etc.

- [ ] **Step 3: Implement** (append to `alloc_contract.ml`)

```ocaml
type reason =
  | Ctor of string | Tuple | Record | Update | Closure
  | Builtin of string | FloatBox
  | UnknownClosure of string | Extern of string
  | Callee of string * reason

let rec describe = function
  | Ctor c -> Printf.sprintf "constructor `%s` is allocated here" c
  | Tuple -> "a tuple is allocated here"
  | Record -> "a record is allocated here"
  | Update -> "a record update allocates a new record here"
  | Closure -> "a closure is allocated here"
  | Builtin ("++" | "string_concat" | "string_concat3") -> "string concatenation"
  | Builtin b -> Printf.sprintf "`%s` allocates" b
  | FloatBox -> "a Float is boxed here (it crosses an erased slot)"
  | UnknownClosure x -> Printf.sprintf "call through an unknown closure `%s`" x
  | Extern e -> Printf.sprintf "call to the extern `%s`" e
  | Callee (g, r) -> Printf.sprintf "calls `%s`, which allocates (in `%s`: %s)" g g (describe r)

(* ── Builtins ─────────────────────────────────────────────────────────── *)

(* TOTAL over the closed codegen-dispatched set: adding a constructor to
   Builtin_name.t without a row here is a build error. Classification is by
   what the runtime does; unclear ⇒ allocating. *)
let named_builtin_allocates : Builtin_name.t -> bool = function
  | Builtin_name.Int_abs | Int_div | Int_div_euclid | Int_max_value | Int_min_value
  | Int_mod | Int_mod_euclid | Int_not | Int_popcount | Int_pow | Negate | Not
  | Pmap_threshold | Task_is_cancelled | Task_reductions | Record_has_key
  | Signal_raise_self | Task_yield -> false
  | Bool_to_string | Float_to_string | Int_to_string | To_string
  | Html_auto_escape | Html_escape_ctx
  | Actor_register | Actor_reply | Chan_choose | Chan_send | Get_work_pool
  | Mpst_send | Receive | Record_from_list | Record_get | Record_put
  | Remote_ref_hashes | Send | Signal_unwatch | Signal_watch
  | Task_await | Task_await_unwrap | Task_cancel | Task_cancel_by_id
  | Task_cancel_token_new | Task_spawn | Task_spawn_steal | Task_spawn_with_cancel
  | Vault_drop | Vault_get | Vault_incr | Vault_ns_drop | Vault_ns_get | Vault_ns_set
  | Vault_push_capped | Vault_put_new | Vault_set | Vault_set_ttl | Vault_update -> true
```
(Write every constructor explicitly — no `_` arm — so a new constructor is a non-exhaustive-match build error. `Record_get` returns an existing value but the runtime may wrap; keep it allocating = conservative. Reconsider `Task_yield`/`Signal_raise_self`: they perform no heap allocation in the runtime; verify by grepping `runtime/*.c` for their implementations (`march_task_yield`, `march_signal_raise_self`) and mark allocating if unsure.)

```ocaml
(* Non-allocating builtins that are NOT codegen-dispatched through
   Builtin_name (they go through the generic runtime-call fallback). Scalar
   arithmetic, comparisons, predicates, reads of existing cells. *)
let scalar_builtins = [
  "+"; "-"; "*"; "/"; "%"; "+."; "-."; "*."; "/."; "<"; ">"; "<="; ">="; "&&"; "||";
  "=="; "!="; "compare_int"; "compare_float"; "compare_string"; "int_and"; "int_or";
  "int_xor"; "int_shl"; "int_shr"; "int_to_float"; "float_to_int"; "float_abs";
  "float_ceil"; "float_floor"; "float_round"; "float_truncate"; "float_is_nan";
  "float_is_infinite"; "float_infinity"; "float_neg_infinity"; "float_nan"; "float_epsilon";
  "math_sqrt"; "math_cbrt"; "math_pow"; "math_exp"; "math_exp2"; "math_log"; "math_log2";
  "math_log10"; "math_sin"; "math_cos"; "math_tan"; "math_asin"; "math_acos"; "math_atan";
  "math_atan2"; "math_sinh"; "math_cosh"; "math_tanh";
  "char_is_alpha"; "char_is_digit"; "char_is_alphanumeric"; "char_is_whitespace";
  "char_is_uppercase"; "char_is_lowercase"; "char_to_int"; "char_from_int"; "byte_to_char";
  "char_to_uppercase"; "char_to_lowercase";
  "string_length"; "string_byte_length"; "string_byte_at"; "string_is_empty";
  "is_nil"; "head"; "tail";
  "native_int_arr_get"; "native_int_arr_length"; "native_int_arr_set"; "native_int_arr_sum";
  "native_float_arr_get"; "native_float_arr_length"; "native_float_arr_set"; "native_float_arr_sum";
  "native_f32_arr_get"; "native_f32_arr_length"; "native_f32_arr_set"; "native_f32_arr_sum";
  "native_i32_arr_get"; "native_i32_arr_length"; "native_i32_arr_set"; "native_i32_arr_sum";
  "native_u8_arr_get"; "native_u8_arr_length"; "native_u8_arr_set"; "native_u8_arr_sum";
  "native_int_arr_max"; "native_int_arr_min"; "native_float_arr_max"; "native_float_arr_min";
  "ring_buf_size"; "ring_buf_cap"; "is_alive"; "mailbox_size"; "unix_time"; "unix_time_ms";
  "sys_uptime_ms"; "live_allocs"; "peak_rss_bytes";
]
let scalar_set = List.fold_left (fun s n -> Hashtbl.replace s n (); s) (Hashtbl.create 128) scalar_builtins

let builtin_allocates (name : string) : bool =
  let base = Tir_names.strip_specialization_suffix name in
  match Builtin_name.of_string base with
  | Some c -> named_builtin_allocates c
  | None -> not (Hashtbl.mem scalar_set base)
```
Before finalising the allowlist, check each `native_*_arr_set`/`_get` and `head`/`tail` in `lib/tir/llvm_builtins.ml` / `runtime/` for allocation (e.g. `native_float_arr_get` on a boxed-Float array might box). Drop any doubtful entry — conservative wins.

Float-box rule and the walker:

```ocaml
let ty_of_atom = function
  | Tir.AVar v -> v.Tir.v_ty
  | Tir.ALit (March_ast.Ast.LitFloat _) -> Tir.TFloat
  | Tir.ALit (March_ast.Ast.LitInt _) -> Tir.TInt
  | _ -> Tir.TUnit

(* Declared field types of constructor [ctor] (TDVariant) or record type. *)
let ctor_fields (m : Tir.tir_module) (ty : Tir.ty) : Tir.ty list option =
  match ty with
  | Tir.TTuple ts -> Some ts
  | Tir.TRecord fs -> Some (List.map snd fs)
  | Tir.TCon (name, _) ->
    List.find_map (function
        | Tir.TDVariant (_, ctors) -> List.assoc_opt name ctors
        | Tir.TDRecord (n, fs) when n = name -> Some (List.map snd fs)
        | Tir.TDClosure (n, tys) when n = name -> Some tys
        | _ -> None) m.Tir.tm_types
  | _ -> None

(* A Float stored into a slot whose declared type is not TFloat is boxed by
   Llvm_ctx.coerce ("double","ptr") — march_alloc_float. *)
let stores_boxed_float m ty args =
  match ctor_fields m ty with
  | None -> false
  | Some fields ->
    List.exists2 (fun a f -> ty_of_atom a = Tir.TFloat && f <> Tir.TFloat)
      args (List.filteri (fun i _ -> i < List.length args) fields)
```
(Guard `List.exists2` against length mismatch: if `List.length fields <> List.length args`, return `false`; for `EAllocHole` the hole's field is absent from `args`, so compare positionally after removing the hole index from `fields`.)

```ocaml
let has_reuse_or_stack (e : Tir.expr) : bool =
  Policy_dce.fold_expr (fun acc e -> acc || (match e with
      | Tir.EReuse _ | Tir.EStackAlloc _ | Tir.EAllocHole (Some _, _, _, _) -> true
      | _ -> false)) false e
```
(`Policy_dce.fold_expr` is reusable and already exhaustive over sub-expressions; `alloc_contract` may depend on `policy_dce` — check `Policy_dce` will NOT need to depend back on `Alloc_contract` in Task 7; it won't.)

```ocaml
let base = Tir_names.strip_specialization_suffix
let decl_of decls name = List.find_opt (fun d -> d.d_name = base name) decls
let is_assume ~decls name =
  match decl_of decls name with Some { d_form = Some Assume; _ } -> true | _ -> false
let display_name name = base name   (* "M.f" / "f" *)

(* First direct reason in [body], if any. Order = evaluation order via fold_expr. *)
let direct_reason ~decls ~m ~assume (fn_name : string) (body : Tir.expr) : reason option =
  let fns = Hashtbl.create 64 in
  List.iter (fun fd -> Hashtbl.replace fns fd.Tir.fn_name ()) m.Tir.tm_fns;
  let externs = List.map (fun e -> e.Tir.ed_march_name) m.Tir.tm_externs in
  let found = ref None in
  let set r = if !found = None then found := Some r in
  ignore (Policy_dce.fold_expr (fun () e ->
      match e with
      | Tir.EAlloc (Tir.TCon (c, _), _) when Tir_names.is_clo_struct c -> set Closure
      | Tir.EAlloc (Tir.TCon (c, _), _) -> set (Ctor c)
      | Tir.EAlloc (_, _) -> set (Ctor "?")
      | Tir.EAllocHole (None, Tir.TCon (c, _), _, _) -> set (Ctor c)
      | Tir.ETuple (_ :: _) -> set Tuple
      | Tir.ERecord _ -> set Record
      | Tir.EUpdate _ -> set Update
      | Tir.EReuse (_, ty, args) | Tir.EStackAlloc (ty, args) when stores_boxed_float m ty args -> set FloatBox
      | Tir.EAllocHole (Some _, ty, args, hole) when stores_boxed_float_hole m ty args hole -> set FloatBox
      | Tir.ECallPtr (Tir.AVar f, _) when not assume -> set (UnknownClosure f.Tir.v_name)
      | Tir.ECallPtr (_, _) when not assume -> set (UnknownClosure "<closure>")
      | Tir.EApp (f, args) ->
        let n = f.Tir.v_name in
        if Hashtbl.mem fns n then begin
          if Tir_names.is_apply_fn n
             && List.exists (fun a -> ty_of_atom a = Tir.TFloat) args then set FloatBox
        end
        else if List.mem n externs then (if not assume then set (Extern n))
        else if builtin_allocates n then set (Builtin (base n))
      | _ -> ()) () body);
  !found

let allocating_fns ~decls (m : Tir.tir_module) : (string, reason) Hashtbl.t =
  let set : (string, reason) Hashtbl.t = Hashtbl.create 64 in
  List.iter (fun fd ->
      if not (is_assume ~decls fd.Tir.fn_name) then
        match direct_reason ~decls ~m ~assume:false fd.Tir.fn_name fd.Tir.fn_body with
        | Some r -> Hashtbl.replace set fd.Tir.fn_name r
        | None -> ()) m.Tir.tm_fns;
  let callees fd =
    Policy_dce.fold_expr (fun acc e -> match e with
        | Tir.EApp (f, _) -> f.Tir.v_name :: acc | _ -> acc) [] fd.Tir.fn_body |> List.rev in
  let rec fix () =
    let changed = ref false in
    List.iter (fun fd ->
        let n = fd.Tir.fn_name in
        if not (Hashtbl.mem set n) && not (is_assume ~decls n) then
          match List.find_opt (fun c -> Hashtbl.mem set c) (callees fd) with
          | Some c -> Hashtbl.replace set n (Callee (display_name c, Hashtbl.find set c)); changed := true
          | None -> ()) m.Tir.tm_fns;
    if !changed then fix () in
  fix ();
  set
```
Note the `assume` seed: a function marked `assume` is skipped entirely (never in the set, never checked). Its ECallPtr/extern do not seed, and — per spec — its *other* allocations are trusted away too ("removed from the set regardless of its body").

- [ ] **Step 4: Run** `./_build/default/test/run_compiler.exe test alloc_contract` → 10 passing.

- [ ] **Step 5: Commit**

```bash
git add lib/tir/alloc_contract.ml test/test_alloc_contract.ml
git commit -m "feat(contracts): allocation classifier and transitive allocating-function set"
```

---

### Task 6: `Alloc_contract.check`, pipeline wiring, driver diagnostics, end-to-end accept/reject/behaviour tests

**Files:**
- Modify: `lib/tir/alloc_contract.ml`, `lib/tir/contract_pipeline.ml`, `bin/main.ml`
- Test: `test/test_alloc_contract.ml`

**Interfaces:**
- Produces:
  ```ocaml
  (* alloc_contract.ml *)
  val check :
    decls:decl_info list -> opt:bool -> trmc:bool ->
    trmc_eligible:(string -> bool) ->   (* by pre-Mono name *)
    Tir.tir_module -> March_errors.Errors.diagnostic list
  (* contract_pipeline.ml: result gains *)
    contract_diags : March_errors.Errors.diagnostic list;
    allocating     : (string, Alloc_contract.reason) Hashtbl.t;  (* for reporting/LSP *)
  (* run gains *)  ?decls:Alloc_contract.decl_info list
  ```

- [ ] **Step 1: Write the failing end-to-end tests** (append to `test/test_alloc_contract.ml`). Helper:

```ocaml
let compile ?(flags = "") src = Test_cap_ceiling.compile_with ~flags src
(* Keeps the binary, runs it, and also runs the interpreter: compiled-parity. *)
let compile_and_run ?(flags = "") src =
  let exe = Test_cap_ceiling.compiler_exe in
  let f = Filename.temp_file "noalloc" ".march" in
  let oc = open_out f in output_string oc src; close_out oc;
  let bin = Filename.temp_file "noalloc" ".bin" in
  let log = Filename.temp_file "noalloc" ".log" in
  let rc = Sys.command (Printf.sprintf "%s %s --compile -o %s %s > %s 2>&1"
                          (Filename.quote exe) flags (Filename.quote bin) (Filename.quote f) (Filename.quote log)) in
  let read p = let ic = open_in p in let s = really_input_string ic (in_channel_length ic) in close_in ic; s in
  let compile_out = read log in
  let run_out = if rc = 0 then (ignore (Sys.command (Printf.sprintf "%s > %s 2>&1" (Filename.quote bin) (Filename.quote log))); read log) else "" in
  ignore (Sys.command (Printf.sprintf "%s %s > %s 2>&1" (Filename.quote exe) (Filename.quote f) (Filename.quote log)));
  let interp_out = read log in
  List.iter (fun p -> try Sys.remove p with _ -> ()) [f; bin; log];
  (rc, compile_out, run_out, interp_out)

let accepts name ?(flags = "") src expected_stdout =
  let (rc, out, run_out, interp_out) = compile_and_run ~flags src in
  if rc <> 0 then Alcotest.failf "%s: expected accept, got rc=%d:\n%s" name rc out;
  Alcotest.(check string) (name ^ ": compiled output") expected_stdout run_out;
  Alcotest.(check string) (name ^ ": interpreter parity") expected_stdout interp_out;
  Alcotest.(check bool) (name ^ ": no contract diagnostic") false (contains "no_alloc" out)

let rejects name ?(flags = "") src needle =
  let (rc, out) = compile ~flags src in
  if rc = 0 then Alcotest.failf "%s: expected reject, compiled fine" name;
  if not (contains needle out) then Alcotest.failf "%s: missing %S in:\n%s" name needle out
```

Fixtures (each is a full program with `main`; the constructor names and messages are pinned):

```ocaml
let tree_src = {|mod Main do
ptype Tree = Leaf(Int) | Node(Tree, Tree)
@[no_alloc]
fn inc_leaves(t : Tree) : Tree do
  match t do
    Leaf(n) -> Leaf(n + 1)
    Node(l, r) -> Node(inc_leaves(l), inc_leaves(r))
  end
end
fn sum(t : Tree) : Int do
  match t do Leaf(n) -> n  Node(l, r) -> sum(l) + sum(r) end
end
fn main() : Unit do println(int_to_string(sum(inc_leaves(Node(Leaf(1), Leaf(2)))))) end
end|}
let test_accept_fbip_tree () = accepts "fbip tree" tree_src "5\n"

let acc_src = {|mod Main do
@[no_alloc]
fn rev_inc(xs : List(Int), acc : List(Int)) : List(Int) do
  match xs do
    Nil -> acc
    Cons(h, t) -> rev_inc(t, Cons(h + 1, acc))
  end
end
fn main() : Unit do println(int_to_string(List.sum_int(rev_inc([1, 2, 3], Nil)))) end
end|}
let test_accept_accumulator_reuse () = accepts "accumulator" acc_src "9\n"

let trmc_src = {|mod Main do
@[no_alloc]
fn inc_all(xs : List(Int)) : List(Int) do
  match xs do
    Nil -> Nil
    Cons(h, t) -> Cons(h + 1, inc_all(t))
  end
end
fn main() : Unit do println(int_to_string(List.sum_int(inc_all([1, 2, 3])))) end
end|}
let test_accept_trmc_with_flag () = accepts "trmc" ~flags:"--trmc" trmc_src "9\n"
let test_reject_trmc_hint_when_off () =
  rejects "trmc off" trmc_src "`inc_all` is marked @[no_alloc] but allocates";
  rejects "trmc hint" trmc_src "This function is TRMC-eligible; compiling with --trmc turns the constructor into an in-place write"
let test_trmc_hint_absent_when_on () =
  (* with --trmc the function passes, so no hint text can appear *)
  let (rc, out) = compile ~flags:"--trmc" trmc_src in
  Alcotest.(check int) "rc" 0 rc; Alcotest.(check bool) "no hint" false (contains "TRMC-eligible" out)

let assume_src = {|mod Main do
@[no_alloc(assume)]
fn apply_twice(f : Int -> Int, x : Int) : Int do f(f(x)) end
@[no_alloc]
fn use_it(x : Int) : Int do apply_twice(fn y -> y + 1, x) end
fn main() : Unit do println(int_to_string(use_it(1))) end
end|}
let test_accept_assume_and_caller () = accepts "assume" assume_src "3\n"
```
The spec asks for `assume` on an extern wrapper; an extern needs a C source and `--ffi-link`, which the test harness cannot link portably. `apply_twice` exercises the same `assume` semantics on the other opaque call shape (ECallPtr); ALSO add a reject/accept pair for an `extern` block that only *typechecks and lowers* by asserting on the diagnostic text (`rejects "extern" … "calls the extern"`) — if `--compile` fails at link time for an unresolved extern before our check runs, note that in the test and keep only the ECallPtr pair.

```ocaml
let stack_src = {|mod Main do
@[no_alloc]
fn minmax(a : Int, b : Int) : Int do
  let p = if a < b do (a, b) else (b, a) end
  let (lo, hi) = p
  hi - lo
end
fn main() : Unit do println(int_to_string(minmax(7, 3))) end
end|}
let test_accept_stack_promoted_tuple () = accepts "stack tuple" stack_src "4\n"

let scalar_src = {|mod Main do
type Mode = Fast | Slow
ptype P = P(Int, Int)
@[no_alloc]
fn score(m : Mode, p : P) : Int do
  match p do P(x, y) -> (match m do Fast -> x * 2 + y  Slow -> x + y end) end
end
fn main() : Unit do println(int_to_string(score(Fast, P(3, 4)))) end
end|}
let test_accept_scalars_only () = accepts "scalars" scalar_src "10\n"

let live_src = {|mod Main do
ptype Box = Box(Int, Int)
@[no_alloc]
fn bump_copied(b : Box) : Int do
  match b do
    Box(x, y) ->
      let updated = Box(x + 1, y)
      let old_x = match b do Box(ox, _) -> ox end
      (match updated do Box(nx, _) -> nx end) + old_x
  end
end
fn main() : Unit do println(int_to_string(bump_copied(Box(1, 2)))) end
end|}
let test_reject_live_scrutinee () =
  rejects "live scrutinee" live_src "`bump_copied` is marked @[no_alloc] but allocates";
  rejects "names ctor" live_src "constructor `Box` is allocated here"

let trans_src = {|mod Main do
fn format_row(n : Int) : String do "row " ++ int_to_string(n) end
@[no_alloc]
fn render(n : Int) : String do format_row(n) end
fn main() : Unit do println(render(1)) end
end|}
let test_reject_transitive_names_callee () =
  rejects "transitive" trans_src "`render` calls `format_row`, which allocates (in `format_row`: string concatenation)"

let concat_src = {|mod Main do
@[no_alloc]
fn greet(s : String) : String do "hi " ++ s end
fn main() : Unit do println(greet("x")) end
end|}
let test_reject_string_concat () = rejects "concat" concat_src "string concatenation"

let callptr_src = {|mod Main do
@[no_alloc]
fn process(f : Int -> Int, x : Int) : Int do f(x) end
fn main() : Unit do println(int_to_string(process(fn y -> y, 1))) end
end|}
let test_reject_callptr_without_assume () =
  rejects "callptr" callptr_src "`process` is marked @[no_alloc] but calls through an unknown closure";
  rejects "callptr hint" callptr_src "mark `process` @[no_alloc(assume)]"

let floatbox_src = {|mod Main do
@[no_alloc]
fn bump(o : Option(Float)) : Option(Float) do
  match o do Some(x) -> Some(x +. 1.0)  None -> None end
end
fn main() : Unit do
  match bump(Some(1.5)) do Some(v) -> println(float_to_string(v))  None -> println("none") end
end
end|}
let test_reject_float_box () = rejects "float box" floatbox_src "a Float is boxed here"
let intbox_src = (* same shape with Int: passes — proves the Float rule is what fires *) …
let test_accept_int_option_reuse () = accepts "int option" intbox_src "3\n"

let warn_src = String.concat "\n" [ … live_src with "@[no_alloc(warn)]" … ]
let test_warn_form_exit_zero () =
  let (rc, out) = compile warn_src in
  Alcotest.(check int) "rc 0" 0 rc;
  Alcotest.(check bool) "warning printed" true (contains "warning" out && contains "is marked @[no_alloc] but allocates" out)

let test_no_opt_downgrades () =
  let (rc, out) = compile ~flags:"--no-opt" live_src in
  Alcotest.(check int) "rc 0 under --no-opt" 0 rc;
  Alcotest.(check bool) "names the flag" true (contains "(TIR optimisation was skipped by --no-opt; the normal build may pass.)" out)

let test_opt_level_does_not_change_verdict () =
  let (rc0, _) = compile ~flags:"--opt 0" live_src in
  let (rc2, _) = compile ~flags:"--opt 2" live_src in
  Alcotest.(check int) "both reject" rc0 rc2; Alcotest.(check bool) "nonzero" true (rc0 <> 0)

let test_interpreter_ignores_attribute () =
  let (_, _, _, interp_out) = compile_and_run live_src in
  Alcotest.(check string) "interpreted runs" "3\n" interp_out
```
Also `test_check_ignores_attribute`: `march --check` on `live_src` → rc 0, no "no_alloc" in output (`Sys.command` with `--check`; write a tiny helper).

Before trusting any ACCEPT fixture, verify its TIR shape once by hand so the test is not vacuous:
`MARCH_DUMP_TXT=tir-native-map-inline ./_build/default/bin/main.exe --compile -o /tmp/x <fixture> 2>&1 | grep -n "reuse\|stack_alloc\|alloc "` and confirm `reuse` (tree, accumulator, int-option), `reuse_hole` (trmc with `--trmc`), `stack_alloc` (stack tuple), and NO bare `alloc` in the annotated function. If a fixture does not produce the expected node, reshape the fixture (e.g. for the stack tuple, destructure without a `let p`), do not weaken the assertion. For `floatbox_src`, additionally `--emit-llvm` and `grep -c march_alloc_float` inside `@bump` must be ≥ 1.

- [ ] **Step 2: Run to verify failure** — build error on `AC.check` absence / the end-to-end cases fail with "expected reject, compiled fine".

- [ ] **Step 3: Implement `check`**

```ocaml
let diag ~severity ~span ~code ?(notes = []) message : March_errors.Errors.diagnostic =
  { March_errors.Errors.severity; span; message; labels = []; notes; code = Some code; fix = None }

let check ~decls ~opt ~trmc ~trmc_eligible (m : Tir.tir_module) =
  let set = allocating_fns ~decls m in
  (* One diagnostic per contract (source decl), from its FIRST failing clone. *)
  let seen = Hashtbl.create 16 in
  List.filter_map (fun fd ->
      let n = fd.Tir.fn_name in
      match decl_of decls n, Hashtbl.find_opt set n with
      | Some ({ d_form = Some (Hard | Warn as form); _ } as d), Some reason
        when not (Hashtbl.mem seen d.d_name) ->
        Hashtbl.replace seen d.d_name ();
        let name = d.d_name in
        let severity, suffix =
          match form, opt with
          | Warn, _ -> March_errors.Errors.Warning, ""
          | Hard, true -> March_errors.Errors.Error, ""
          | Hard, false -> March_errors.Errors.Warning,
                           " (TIR optimisation was skipped by --no-opt; the normal build may pass.)" in
        let trmc_note =
          match reason with
          | (Ctor _) when (not trmc) && trmc_eligible name ->
            [ "This function is TRMC-eligible; compiling with --trmc turns the constructor into an in-place write." ]
          | _ -> [] in
        let message =
          match reason with
          | UnknownClosure x ->
            Printf.sprintf "`%s` is marked @[no_alloc] but calls through an unknown closure.%s\n  I can't see what `%s` does. If you know it doesn't allocate, mark `%s` @[no_alloc(assume)]."
              name suffix x name
          | Extern e ->
            Printf.sprintf "`%s` is marked @[no_alloc] but calls the extern `%s`.%s\n  I can't see what `%s` does. If you know it doesn't allocate, mark `%s` @[no_alloc(assume)]."
              name e suffix e name
          | Callee (g, r) ->
            Printf.sprintf "`%s` is marked @[no_alloc] but allocates.%s\n  `%s` calls `%s`, which allocates (in `%s`: %s)."
              name suffix name g g (describe r)
          | r ->
            Printf.sprintf "`%s` is marked @[no_alloc] but allocates.%s\n  In `%s`: %s."
              name suffix name (describe r) in
        Some (diag ~severity ~span:d.d_name_span ~code:"no_alloc" ~notes:trmc_note message)
      | _ -> None) m.Tir.tm_fns
```
Mind `describe (Callee …)` vs the sentence above: for `Callee` the message is built inline, so `describe` on the INNER reason only. Adjust the `Callee` describe arm so nested chains read "calls `h`, which allocates (in `h`: …)".

Pipeline (`contract_pipeline.ml`): accept `?(decls = [])`; compute `trmc_eligible` from the POST-LOWER input before `Trmc.transform_module`:
```ocaml
  let eligible = Hashtbl.create 16 in
  List.iter (fun r -> if Trmc.verdict_of r = Trmc.Eligible then Hashtbl.replace eligible r.Trmc.r_fn ())
    (Trmc.analyze_module tir);
  let trmc_eligible n = Hashtbl.mem eligible n in
```
Contract roots: `extra_roots = extra_roots @ (decls with d_form = Some (Hard|Warn) |> names)` (base names; the clone expansion from Task 4 handles `f$Int`). After `Native_map_inline`: `let contract_diags = Alloc_contract.check ~decls ~opt ~trmc ~trmc_eligible tir in` and return `{ …; contract_diags; allocating = Alloc_contract.allocating_fns ~decls tir }` (compute the set ONCE and let `check` take it as an argument to avoid doing the fixpoint twice: give `check` an `~allocating` parameter instead of recomputing).

Driver (`bin/main.ml`): pass `~decls:(March_tir.Alloc_contract.collect desugared)` (the desugared module INCLUDING prepended stdlib is fine: stdlib fns have no attribute). After the vectorize print loop, print `contract_diags` with the identical render loop and `exit 1` if any has severity `Error`.

- [ ] **Step 4: Run** `dune build --root . bin/main.exe @install && ./_build/default/test/run_compiler.exe test alloc_contract`. All green. Then `scripts/run-tests.sh -q compiler codegen` — unchanged counts. Re-run the IR oracle `check` (still GREEN: unannotated programs must be byte-identical — the contract roots only apply to annotated functions).

- [ ] **Step 5: Commit**

```bash
git add lib/tir/alloc_contract.ml lib/tir/contract_pipeline.ml bin/main.ml test/test_alloc_contract.ml
git commit -m "feat(contracts): check @[no_alloc] on the final TIR with --no-opt downgrade and --trmc hint"
```

---

### Task 7: `Policy_dce` NoAlloc delegates to the contract checker

**Files:**
- Modify: `lib/tir/policy_dce.ml`, `lib/tir/alloc_contract.ml`
- Test: `test/test_alloc_contract.ml`

- [ ] **Step 1: Failing tests**

```ocaml
let policy_reuse_src = {|mod Main do
type NoAlloc = NoAlloc
ptype Box = Box(Int, Int)
fn bump(cap : Tagged(Int, NoAlloc), b : Box) : Box do
  match b do Box(x, y) -> Box(x + 1, y) end
end
fn main() : Unit do
  match bump(Tagged(0, NoAlloc), Box(1, 2)) do Box(x, _) -> println(int_to_string(x)) end
end
end|}
let test_policy_accepts_reused_ctor () = accepts "policy reuse" policy_reuse_src "2\n"
let policy_alloc_src = (* same with `let old = match b do Box(ox, _) -> ox end` after the rebuild, returning a tuple of both *) …
let test_policy_still_rejects_plain_alloc () =
  rejects "policy alloc" policy_alloc_src "is specialized to a NoAlloc policy but allocates"
```
Check how `Tagged` values are constructed in existing tests (`test/test_compiler.ml:7017-7050`) and use that spelling.

- [ ] **Step 2: Verify failure** (the policy-reuse case fails today with `Error: function … contains EAlloc`; the second case passes for the wrong message — the text must be the new one).

- [ ] **Step 3: Implement**

In `policy_dce.ml`: delete `check_noalloc`; in `audit`, the `NoAlloc` arm becomes `| NoAlloc -> None (* checked by Alloc_contract on the final TIR — see that module *)`. Update the module doc comment.

In `alloc_contract.ml`: `let policy_noalloc fd = List.exists (fun c -> c = Policy_dce.NoAlloc) (Policy_dce.policies_of_fn fd)`. In `check`, for a fn with `policy_noalloc fd` and no explicit contract, produce an Error at the decl's name span when known (`decl_of decls n`) else `March_ast.Ast.dummy_span`, message: ``"`%s` is specialized to a NoAlloc policy but allocates.\n  In `%s`: %s."`` (transitive/closure variants as above). The driver's dummy-span guard: main.ml's render loop reads the source file named in the span; with `dummy_span` file `<none>` it would fail — for a dummy span print `Printf.eprintf "Error: %s\n\n" d.message` instead (mirror the `cap_ceiling` dummy-span guard at main.ml:2395-2405).

- [ ] **Step 4: Run** the suite subset; also grep the test tree for the old message (`"specialized to a NoAlloc policy) contains"`) — none exists (verified), so nothing else to update.

- [ ] **Step 5: Commit** — `git add lib/tir/policy_dce.ml lib/tir/alloc_contract.ml test/test_alloc_contract.ml && git commit -m "feat(contracts): Tagged NoAlloc/Realtime policies defer to the final-TIR allocation check"`

---

### Task 8: LSP diagnostic, `✓ no_alloc` lens, and "Add `@[no_alloc]`" quick fix

**Files:**
- Modify: `lsp/lib/analysis_types.ml` (new field), `lsp/lib/analysis.ml` (`run_tir_pass`, the record literal at ~2406), `lsp/lib/code_actions_diag.ml`
- Test: `lsp/test/test_lsp_features.ml`, `lsp/test/test_lsp.ml`

**Interfaces:**
- `analysis_types.ml`: `no_alloc_candidates : (string * Ast.span * Ast.span) list` (fn name, name span, decl span) — functions the checker verified clean AND in default scope (`has_reuse_or_stack`) AND unannotated AND user-file AND not `$`-prefixed. Also extend `tir_pass_cache`'s tuple with it.

- [ ] **Step 1: Failing tests** (`lsp/test/test_lsp_features.ml`, register in `test_lsp.ml` under the TIR block)

```ocaml
let no_alloc_fail_src = {|mod Test do
  ptype Box = Box(Int, Int)
  @[no_alloc]
  fn bump(b : Box) : Int do
    match b do
      Box(x, y) ->
        let u = Box(x + 1, y)
        let o = match b do Box(ox, _) -> ox end
        (match u do Box(nx, _) -> nx end) + o
    end
  end
end|}
let test_no_alloc_diagnostic_at_name () =
  let a = An.run_tir_pass (analyse no_alloc_fail_src) in
  let (line, col) = pos_of no_alloc_fail_src "bump(b" in
  match List.find_opt (fun (d : Lsp.Types.Diagnostic.t) ->
      contains (match d.message with `String s -> s | _ -> "") "is marked @[no_alloc] but allocates") a.An.diagnostics with
  | None -> Alcotest.fail "expected the contract diagnostic"
  | Some d ->
    Alcotest.(check int) "line" line d.range.start.line;
    Alcotest.(check int) "col" col d.range.start.character;
    Alcotest.(check bool) "error" true (d.severity = Some Lsp.Types.DiagnosticSeverity.Error)

let no_alloc_ok_src = {|mod Test do
  ptype Box = Box(Int, Int)
  @[no_alloc]
  fn bump(b : Box) : Box do match b do Box(x, y) -> Box(x + 1, y) end end
  fn main() : Int do match bump(Box(1, 2)) do Box(x, _) -> x end end
end|}
let test_no_alloc_lens_when_holding () =
  let a = An.run_tir_pass (analyse no_alloc_ok_src) in
  Alcotest.(check bool) "lens" true
    (List.exists (fun (cl : An.code_lens_item) -> contains cl.An.cl_title "✓ no_alloc") a.An.code_lens_items)

let quickfix_src = {|mod Test do
  ptype Box = Box(Int, Int)
  fn bump(b : Box) : Box do match b do Box(x, y) -> Box(x + 1, y) end end
  fn add(a : Int, b : Int) : Int do a + b end
  fn main() : Int do match bump(Box(1, 2)) do Box(x, _) -> x + add(1, 2) end end
end|}
let test_quickfix_offered_on_reuse_fn () =
  let a = An.run_tir_pass (analyse quickfix_src) in
  let (line, col) = pos_of quickfix_src "bump(b" in
  let acts = An.code_actions_at a ~line ~character:col () in
  match List.find_opt (fun (ca : Lsp.Types.CodeAction.t) -> ca.title = "Add `@[no_alloc]`") acts with
  | None -> Alcotest.fail "expected Add @[no_alloc]"
  | Some ca ->
    (match ca.edit with
     | Some { changes = Some [ (_, [ e ]) ]; _ } ->
       Alcotest.(check string) "inserts the attribute" "@[no_alloc]\n  " e.newText;
       Alcotest.(check int) "at the decl line" line e.range.start.line;
       Alcotest.(check int) "at column 0" 0 e.range.start.character
     | _ -> Alcotest.fail "one insert edit expected")
let test_quickfix_not_offered_without_reuse () =
  let a = An.run_tir_pass (analyse quickfix_src) in
  let (line, col) = pos_of quickfix_src "add(a" in
  Alcotest.(check bool) "no action on plain fn" false
    (List.exists (fun (ca : Lsp.Types.CodeAction.t) -> ca.title = "Add `@[no_alloc]`") (An.code_actions_at a ~line ~character:col ()))
let test_quickfix_never_on_stdlib () =
  let a = An.run_tir_pass (analyse quickfix_src) in
  Alcotest.(check bool) "all candidates are in this file" true
    (List.for_all (fun (_, sp, _) -> sp.Ast.file = a.An.filename) a.An.no_alloc_candidates)
```
Adjust the insert `newText` expectation to what the implementation produces: `"@[no_alloc]\n" ^ String.make decl_start_col ' '` inserted at `(decl_line, decl_start_col)` — with the test's 2-space indent that is `"@[no_alloc]\n  "` at character 2, not 0. Fix the assertion to `2`.

- [ ] **Step 2: Verify failure** (build errors on the new field; then assertion failures).

- [ ] **Step 3: Implement**

`run_tir_pass`: pass `~decls:(March_tir.Alloc_contract.collect desugared)`; after the pipeline:
```ocaml
      let contract_diags = List.filter_map (diag_to_lsp ~filename:a.filename) pipe.contract_diags in
      let holds = (* decl names with Hard/Warn form and no diagnostic *) … in
      (* lens: append "✓ no_alloc" to the parts of a holding contract's function, or emit a lens alone *)
      let no_alloc_candidates =
        List.filter_map (fun (d : AC.decl_info) ->
            if d.d_form <> None || d.d_name_span.Ast.file <> a.filename || d.d_name = "" || d.d_name.[0] = '$' then None
            else
              let clones = List.filter (fun fd -> AC.base fd.Tir.fn_name = d.d_name) final.Tir.tm_fns in
              if clones = [] then None
              else if List.exists (fun fd -> Hashtbl.mem pipe.allocating fd.Tir.fn_name) clones then None
              else if List.exists (fun fd -> AC.has_reuse_or_stack fd.Tir.fn_body) clones
              then Some (d.d_name, d.d_name_span, d.d_decl_span) else None) decls in
```
Merge `contract_diags` into `a.diagnostics` (dedupe by message+range if the memo replays). Add the field to the cache tuple and to the `{ a with … }` results, and `no_alloc_candidates = []` in the initial record literal.

Put the candidate predicate in `alloc_contract.ml` as `val default_scope_candidates : decls:decl_info list -> allocating:(string, reason) Hashtbl.t -> is_user:(March_ast.Ast.span -> bool) -> Tir.tir_module -> decl_info list` so Task 9's `--report-contracts` uses the identical predicate (spec: "the editor offers the action exactly where forge fix would insert it"). Give it an extra `~globs:string list` argument for the opt-in scope (glob `*` matches any run of characters; match against `d_name`); a glob match puts a verified-clean function in scope even without reuse.

Quick fix (`code_actions_diag.ml`, before the final concatenation):
```ocaml
  let no_alloc_actions =
    List.filter_map (fun (_name, name_span, decl_span) ->
        if Pos.span_contains decl_span ~line ~character || Pos.span_contains name_span ~line ~character then begin
          let pos = Position.create ~line:(decl_span.Ast.start_line - 1) ~character:decl_span.Ast.start_col in
          let indent = String.make decl_span.Ast.start_col ' ' in
          let edit = TextEdit.create ~range:(Range.create ~start:pos ~end_:pos) ~newText:("@[no_alloc]\n" ^ indent) in
          let uri = DocumentUri.of_path a.filename in
          Some (CodeAction.create ~title:"Add `@[no_alloc]`" ~kind:CodeActionKind.QuickFix
                  ~edit:(WorkspaceEdit.create ~changes:[(uri, [edit])] ()) ())
        end else None) a.no_alloc_candidates
  in
```
and append `@ no_alloc_actions`. Confirm whether `Ast.span.start_col` is 0- or 1-based by reading `Pos.span_to_lsp_range`; use the same convention it uses.

- [ ] **Step 4: Run** the LSP suites (`test_lsp`, `test_incremental`, `test_jsonrpc` from the repo root with `lsp/bin/main.exe` built). Green.

- [ ] **Step 5: Commit** — `git add lsp/lib/analysis_types.ml lsp/lib/analysis.ml lsp/lib/code_actions_diag.ml lib/tir/alloc_contract.ml lsp/test/test_lsp_features.ml lsp/test/test_lsp.ml && git commit -m "feat(lsp): @[no_alloc] diagnostic, ✓ no_alloc lens, and Add @[no_alloc] quick fix"`

---

### Task 9: `march --compile --report-contracts` and `forge fix --contracts`

**Files:**
- Modify: `bin/main.ml` (flags `--report-contracts`, `--contract-scope <globs>`; emission after the check), `forge/lib/cmd_fix.ml`, `forge/lib/project.ml` (`[contracts] no_alloc`), `forge/bin/main.ml` (flag)
- Test: `test/test_alloc_contract.ml` (report), `forge/test/test_build_check.ml` (fix)

- [ ] **Step 1: Failing tests**

Compiler side:
```ocaml
let report_src = quickfix_src (* from Task 8, as a `mod Main` program with main *)
let test_report_contracts_emits_insert () =
  let (rc, out) = compile ~flags:"--report-contracts" report_src in
  Alcotest.(check int) "rc 0" 0 rc;
  let lines = List.filter (fun l -> contains l "\"fix\":{\"kind\":\"insert\"") (String.split_on_char '\n' out) in
  Alcotest.(check int) "exactly one insert (bump, not add)" 1 (List.length lines);
  Alcotest.(check bool) "names bump" true (contains (List.hd lines) "`bump`");
  Alcotest.(check bool) "text is the hard form" true (contains (List.hd lines) "\"text\":\"  @[no_alloc]\"")
let test_report_contracts_glob_scope () =
  let (_, out) = compile ~flags:"--report-contracts --contract-scope 'Main.add,ad*'" report_src in
  Alcotest.(check bool) "add now in scope" true (contains out "`add`")
let test_report_contracts_skips_annotated () =
  let (_, out) = compile ~flags:"--report-contracts" no_alloc_ok_src_as_main in
  Alcotest.(check bool) "no line for an annotated fn" false (contains out "\"fix\":{\"kind\":\"insert\"")
```
(`after_line` must equal the `fn` line minus one; assert it: `"after_line":2` for the fixture's `bump` on line 3.)

Forge side (`forge/test/test_build_check.ml`, using `with_project` + `setup_hermetic_march`):
```ocaml
let test_forge_fix_contracts_inserts_and_is_idempotent () =
  with_project (fun dir ->
      let f = Filename.concat (Filename.concat dir "lib") "dsp.march" in
      write_file f "mod Dsp do\nptype Box = Box(Int, Int)\nfn bump(b : Box) : Box do match b do Box(x, y) -> Box(x + 1, y) end end\nfn add(a : Int, b : Int) : Int do a + b end\nend\n";
      (match Cmd_fix.run ~contracts:true () with Ok _ -> () | Error e -> Alcotest.fail e);
      let s = read_file f in
      Alcotest.(check bool) "bump annotated" true (contains s "@[no_alloc]\nfn bump");
      Alcotest.(check bool) "add untouched" false (contains s "@[no_alloc]\nfn add");
      (match Cmd_fix.run ~contracts:true () with
       | Ok msg -> Alcotest.(check bool) "second run no-op" true (contains msg "no ")
       | Error e -> Alcotest.fail e);
      Alcotest.(check string) "file unchanged by second run" s (read_file f))
```
`--report-contracts` on a `Lib` file with no `main` relies on `Dce.prune_unreachable`'s fail-open (no roots ⇒ keep all) — confirm the report lists `bump` there; if the LSP-style `extra_roots` are needed, pass all user decl names as roots on the `--report-contracts` path too.

- [ ] **Step 2: Verify failure** (unknown flag; `Cmd_fix.run` has no `~contracts`).

- [ ] **Step 3: Implement**

`main.ml`: refs `report_contracts : bool ref`, `contract_scope : string ref` (comma-separated globs). After the contract diagnostics are printed (and only if no Error), when `!report_contracts`:
```ocaml
      let cands = March_tir.Alloc_contract.default_scope_candidates ~decls ~allocating:pipe.allocating
          ~globs:(String.split_on_char ',' !contract_scope |> List.filter ((<>) ""))
          ~is_user:(fun sp -> is_user_span sp)   (* the same user-file test used for diagnostics *)
          tir in
      List.iter (fun (d : March_tir.Alloc_contract.decl_info) ->
          let indent = String.make d.d_decl_span.March_ast.Ast.start_col ' ' in
          let diag = { March_errors.Errors.severity = Hint; span = d.d_name_span;
                       message = Printf.sprintf "`%s` is verified allocation-free; add @[no_alloc] to keep it that way." d.d_name;
                       labels = []; notes = []; code = Some "no_alloc_candidate";
                       fix = Some (March_errors.Errors.FInsert { after_line = d.d_decl_span.start_line - 1; text = indent ^ "@[no_alloc]" }) } in
          print_string (March_errors.Errors.render_diagnostic_json diag ^ "\n")) cands;
      exit 0
```
(`--report-contracts` implies `--compile` for flag validation; it exits before object emission, so no binary is written and no CAS entry is consulted — say so in the flag's help text.) The span's `start_col` convention: check whether the driver's `cap_ceiling_fix_indent` treats columns as 0-based and match it.

`project.ml`: field `contracts_no_alloc : string list` on `Project.t` (default `[]`), parsed via `Toml.get_string_list (Toml.get_section doc "contracts") "no_alloc"`. Update every literal construction of `Project.t` (grep `project_type =` in `forge/lib` and `forge/test`).

`cmd_fix.ml`: `let run ?(dry_run = false) ?(contracts = false) () = …`; when `contracts`, replace `collect_all_fixes` with a variant whose command is
`"%smarch --compile --report-contracts%s %s 2>/dev/null"` with `--contract-scope <globs>` appended when `proj.contracts_no_alloc <> []`. Everything downstream (parse → dedupe → apply) is unchanged.

`forge/bin/main.ml` `fix_cmd`: add `Arg.(value & flag & info ["contracts"] ~doc:"Insert @[no_alloc] on functions the compiler verified allocation-free (default scope: functions with in-place reuse or stack promotion; extend with [contracts] no_alloc globs in forge.toml)")`.

- [ ] **Step 4: Run** `dune build --root . @install bin/main.exe forge/bin/main.exe && ./_build/default/test/run_compiler.exe test alloc_contract` and `dune build --root . @forge/test/runtest --force` (or run `test_build_check.exe` with `MARCH_TEST_BIN` set as its dune rule does). Green.

- [ ] **Step 5: Commit** — `git add bin/main.ml forge/lib/cmd_fix.ml forge/lib/project.ml forge/bin/main.ml test/test_alloc_contract.ml forge/test/test_build_check.ml && git commit -m "feat(forge): --report-contracts and forge fix --contracts insert verified @[no_alloc]"`

---

### Task 10: Docs, changelog, spec bookkeeping, snapshots, full verification

**Files:**
- `specs/lang/surface-syntax.md` + `docs/surface-syntax.md` (or the served copy found by `grep -rl "@\[deprecated\]" docs/`), `specs/lang/capabilities.md`, `specs/lang/memory-model.md`, `specs/features/compiler-pipeline.md`, `CHANGELOG.md`
- `git mv specs/todos/2026-09-03-allocation-contracts.md specs/progress/`
- Create `specs/todos/2026-09-03-unify-cap-no-alloc-with-contract.md`

- [ ] **Step 1: Docs**
  - surface-syntax (both copies), in "Visibility & Doc/Attrs": add
    ```march
    @[no_alloc]           -- error if this function (or anything it calls) heap-allocates in the compiled build
    fn inc_leaves(t : Tree) : Tree do ... end
    @[no_alloc(warn)]     -- same check, warning only
    @[no_alloc(assume)]   -- never checked; callers trust it (for closure/extern wrappers)
    ```
    plus two sentences: checked on the final TIR after Perceus/escape analysis (reuse and stack promotion pass); ignored by the interpreter and `--check`; `fn`/`pfn` only.
  - capabilities.md under `### cap no_alloc`: one paragraph: `cap no_alloc` is syntactic and pre-optimisation (bans the constructs in the table, in every mode including the interpreter); `@[no_alloc]` is checked on the compiled program after Perceus, so in-place reuse and stack promotion pass, and it is transitive over callees. Use the contract when the question is "does the binary allocate", the cap when the question is "does the source construct heap values". Link the unification todo.
  - memory-model.md "Writing allocation-free code": add a step 4 to the practical loop: once a hot function shows only `♻`/`⚡`, pin it with `@[no_alloc]` (or let `forge fix --contracts` insert it); a later change that reintroduces an allocation then fails the build instead of silently regressing. Show the `bump_reused` example with the attribute.
  - compiler-pipeline.md: pass-order note gains `→ Native_map_inline → Alloc_contract.check` before Llvm_emit, and a sentence that the tail from Trmc onward lives in `lib/tir/contract_pipeline.ml` and is shared with the LSP; table rows `| Allocation contracts | lib/tir/alloc_contract.ml | ✓ Complete (@[no_alloc]; runs last, before Llvm_emit) |` and `| Shared pipeline tail | lib/tir/contract_pipeline.ml | ✓ Complete (driver + LSP) |`. Update the "LSP omitted …" correction note (line ~1347) to say the LSP now runs the shared tail.
  - `scripts/check-docs.sh` must pass.
- [ ] **Step 2: CHANGELOG** — under `## [Unreleased]` / `### Added`: "`@[no_alloc]` / `@[no_alloc(warn)]` / `@[no_alloc(assume)]` allocation contracts, checked on the final TIR so FBIP reuse and stack promotion pass; transitive over callees; LSP diagnostic, `✓ no_alloc` lens and quick fix; `march --compile --report-contracts` + `forge fix --contracts` insert the attribute on verified functions. `Tagged(_, NoAlloc)`/`Realtime` policies now use the same check."
- [ ] **Step 3: Spec bookkeeping** — `git mv` the todo to `specs/progress/` (tick the checkbox, add "Landed 2026-09-03" and the commit range). New todo `specs/todos/2026-09-03-unify-cap-no-alloc-with-contract.md`: `[P3]` — unify `cap no_alloc` with `@[no_alloc]` once an interpreter-mode answer exists; today the cap is AST-level/pre-optimisation and the contract is final-TIR; open question: what the cap should mean under `forge run`.
- [ ] **Step 4: Snapshots** — `dune build --root . test/run_snapshots.exe && ./_build/default/test/run_snapshots.exe -e`. Expected: green with NO regeneration. If any snapshot moved, the extraction or the contract roots changed IR for an unannotated program — that is a bug, not a regeneration case.
- [ ] **Step 5: Full verification** — `dune build --root . @install`, then `scripts/run-tests.sh` (full), `scripts/check-docs.sh`, the IR oracle `check` one final time, and the LSP `test_jsonrpc` from the repo root. Quote the real per-suite counts in the report.
- [ ] **Step 6: Commit**

```bash
git add specs/lang/surface-syntax.md docs/surface-syntax.md specs/lang/capabilities.md specs/lang/memory-model.md specs/features/compiler-pipeline.md CHANGELOG.md specs/progress/2026-09-03-allocation-contracts.md specs/todos/2026-09-03-unify-cap-no-alloc-with-contract.md specs/plans/2026-09-03-allocation-contracts-plan.md
git commit -m "docs(contracts): document @[no_alloc], close the todo, file the cap-unification follow-up"
```

## Self-review notes

- Spec coverage: syntax (T1), allocation table + builtin totality + float boxing (T5/T6), transitivity + assume (T5), check position + pipeline extraction + oracle (T2/T3/T6), build-config rules (T6), interpreter/--check silence (T6 test), LSP three additions (T8), forge generation + scope + never-list (T8 predicate, T9), diagnostics pinned (T6), policy delegation (T7), docs/changelog/todos (T10). The "because Perceus could not reuse" clause is omitted: `Perceus_fbip` records no decline reason and the hook is not trivial (spec permits ending after "allocated here").
- Deviation to record in the commit message of T6: `check` takes labelled `~decls ~opt ~trmc ~trmc_eligible` in front of the positional `tir_module` because the TIR carries no attribute information and the design forbids perturbing annotated functions' TIR; the positional shape `Tir.tir_module -> diagnostic list` is preserved.
- Type consistency: `decl_info` fields (`d_name`, `d_form`, `d_name_span`, `d_decl_span`) are used identically in T1, T5, T6, T8, T9; `Contract_pipeline.result` fields `pre_opt`, `final`, `vectorize_diags`, `contract_diags`, `allocating` are the names used in T3, T4, T6, T8, T9.
