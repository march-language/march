(** March LSP tests: TIR pipeline, consuming-call and FBIP inlay hints, run/debug lenses, workspace symbols, UTF-16 encoding, ~H interpolation tiers, semantic tokens

    Moved verbatim out of [test_lsp.ml]; see [Test_lsp_harness]. *)

open Test_lsp_harness

(* ------------------------------------------------------------------ *)
(* Phase 3: TIR pipeline tests                                         *)
(* ------------------------------------------------------------------ *)

(** Test 1: run_tir_pass produces insights on clean source.

    This test used to assert [List.length ... >= 0], which is true of every
    list, over a source written with `-> Int` return syntax that March does not
    accept. So it proved nothing twice over: the pipeline bailed out on the
    parse error and returned the analysis untouched, and the assertions would
    have held even then. It now uses parseable source that allocates (so the
    pipeline has something to report) and asserts insights actually arrived. *)
let test_tir_pass_does_not_crash () =
  let src = {|
mod Test do
  fn build(n : Int) : List(Int) do
    Cons(n, Cons(n + 1, Nil))
  end

  fn main() : Int do
    List.length(build(1))
  end
end
|} in
  let a = analyse src in
  Alcotest.(check bool) "source typechecks (guards vacuity)" false
    (List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
         d.severity = Some Lsp.Types.DiagnosticSeverity.Error) a.An.diagnostics);
  let a2 = An.run_tir_pass a in
  Alcotest.(check bool) "the TIR pass produced per-function insights" true
    (a2.An.tir_fn_insights <> []);
  Alcotest.(check bool) "every insight names a function" true
    (List.for_all (fun (tfi : An.tir_fn_insight) ->
         String.length tfi.An.tfi_fn_name > 0) a2.An.tir_fn_insights)

(* ------------------------------------------------------------------ *)
(* Consuming-call inlay hints                                          *)
(* ------------------------------------------------------------------ *)

let hint_labels (hs : Lsp.Types.InlayHint.t list) =
  List.filter_map (fun (h : Lsp.Types.InlayHint.t) ->
      match h.label with `String s -> Some s | _ -> None) hs

let full_range () =
  Lsp.Types.Range.create
    ~start:(Lsp.Types.Position.create ~line:0 ~character:0)
    ~end_:(Lsp.Types.Position.create ~line:200 ~character:0)

(** `wrap` stores its argument into a returned list, so it takes ownership —
    borrow inference reports the parameter as owned, and the call site should
    say so. *)
let test_consume_hint_on_owning_call () =
  let src = {|mod Test do
  fn wrap(s : String) : List(String) do
    [s]
  end

  fn main() : Int do
    let msg = "hello"
    let boxed = wrap(msg)
    List.length(boxed)
  end
end|} in
  let a = An.run_tir_pass (analyse src) in
  (* Non-vacuity: the TIR pass bails out and returns the analysis untouched if
     the source failed to typecheck, which would make every assertion below
     pass for the wrong reason. Prove the pass actually ran and classified
     `wrap` before trusting the hint. *)
  Alcotest.(check bool) "TIR pass produced consume modes (guards vacuity)" true
    (a.An.consume_modes <> []);
  Alcotest.(check bool) "`wrap` records a consuming parameter" true
    (List.exists (fun (cm : An.consume_modes) ->
         cm.An.cm_fn_name = "wrap" && List.mem true cm.An.cm_consumes)
       a.An.consume_modes);
  let labels = hint_labels (An.inlay_hints_for a (full_range ())) in
  Alcotest.(check bool) "a consumed hint is emitted at the call site" true
    (List.exists (fun s -> s = "⊗ consumed") labels)

(** REGRESSION GUARD. The borrow map initialises every non-borrow-eligible
    parameter to "not borrowed", so an Int parameter reads as nominally owned.
    Without the needs_rc filter this hint would fire on every numeric argument
    in the file and drown the real signal. *)
let test_no_consume_hint_on_scalar_arg () =
  let src = {|mod Test do
  fn double(x : Int) : Int do
    x * 2
  end

  fn main() : Int do
    let n = 21
    double(n)
  end
end|} in
  let a = An.run_tir_pass (analyse src) in
  let labels = hint_labels (An.inlay_hints_for a (full_range ())) in
  (* The hint list must be non-empty (type hints exist), else "no consumed
     hint" would hold trivially on an empty analysis. *)
  Alcotest.(check bool) "hints were produced at all (guards vacuity)" true
    (labels <> []);
  Alcotest.(check bool) "no consumed hint on an Int argument" false
    (List.exists (fun s -> s = "⊗ consumed") labels)

(** A temporary has no name to lose, so annotating it is noise; the hint is
    restricted to plain variable arguments. *)
let test_no_consume_hint_on_temporary_arg () =
  let src = {|mod Test do
  fn wrap(s : String) : List(String) do
    [s]
  end

  fn main() : Int do
    let boxed = wrap("literal")
    List.length(boxed)
  end
end|} in
  let a = An.run_tir_pass (analyse src) in
  Alcotest.(check bool) "TIR pass ran (guards vacuity)" true
    (a.An.consume_modes <> []);
  let labels = hint_labels (An.inlay_hints_for a (full_range ())) in
  Alcotest.(check bool) "no consumed hint on a literal argument" false
    (List.exists (fun s -> s = "⊗ consumed") labels)

(** Test 2: run_tir_pass is idempotent (running twice gives the same result).

    Previously written with `-> Int` and `[x, ..rest]`, neither of which parses,
    so both passes ran on a failed analysis and returned it unchanged — two
    empty results compare equal, which is how the old bound (`<= n + 3`) held.
    Now the source parses and the check is equality, not a slack bound: a second
    pass must add nothing at all. *)
let test_tir_pass_idempotent () =
  let src = {|
mod Test do
  fn sum(xs : List(Int), acc : Int) : Int do
    match xs do
      Nil -> acc
      Cons(x, rest) -> sum(rest, acc + x)
    end
  end

  fn main() : Int do
    sum(Cons(1, Cons(2, Nil)), 0)
  end
end
|} in
  let a = analyse src in
  let a2 = An.run_tir_pass a in
  Alcotest.(check bool) "first pass produced insights (guards vacuity)" true
    (a2.An.tir_fn_insights <> []);
  let a3 = An.run_tir_pass a2 in
  Alcotest.(check int) "perf insights do not accumulate on a second pass"
    (List.length a2.An.perf_insights) (List.length a3.An.perf_insights);
  Alcotest.(check int) "fn insights are stable across passes"
    (List.length a2.An.tir_fn_insights) (List.length a3.An.tir_fn_insights)

(** Test 3: run_tir_pass on source with errors returns analysis unchanged. *)
let test_tir_pass_skipped_on_error () =
  (* The error must be the one this test is about — an unresolved name — not an
     incidental parse failure. The old source used `-> Int`, so it exercised the
     skip path via a syntax error while claiming to test a semantic one, and its
     else-branch asserted `true = true` if no error appeared at all. *)
  let src = {|
mod Test do
  fn broken() : Int do
    this_does_not_exist()
  end
end
|} in
  let a = analyse src in
  let has_errors = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
      d.severity = Some Lsp.Types.DiagnosticSeverity.Error
    ) a.An.diagnostics
  in
  Alcotest.(check bool) "the source really does error (guards vacuity)" true
    has_errors;
  let a2 = An.run_tir_pass a in
  Alcotest.(check bool) "TIR pass is skipped when the source has errors" true
    (a2.An.tir_fn_insights = [])

(** Test 4: HOF with function parameter produces indirect-call insight. *)
let test_tir_indirect_call_insight () =
  (* Calling a function-typed parameter dispatches through a pointer, which the
     TIR pass reports as an indirect call. The old version guarded the real
     assertion behind "if the pipeline produced data", and its source did not
     parse — so it always took the else branch and asserted `true = true`. *)
  let src = {|
mod Test do
  fn apply(f : Int -> Int, x : Int) : Int do
    f(x)
  end

  fn main() : Int do
    apply(fn n -> n + 1, 41)
  end
end
|} in
  let a = analyse src in
  let a2 = An.run_tir_pass a in
  Alcotest.(check bool) "the TIR pass ran (guards vacuity)" true
    (a2.An.tir_fn_insights <> []);
  Alcotest.(check bool) "a higher-order call yields an indirect-call insight" true
    (List.exists (fun (pi : An.perf_insight) ->
         match pi.An.pi_kind with
         | An.TirIndirectCall _ -> true
         | _ -> false)
       a2.An.perf_insights)

(** Test 5: tir_fn_insights field is populated correctly. *)
let test_tir_fn_insights_field_populated () =
  (* Old version: `-> Int` (unparseable) plus `List.length ... >= 0` and a
     [for_all] over what was necessarily the empty list — three assertions that
     could not fail. The source now allocates, so there is something to count,
     and the counts themselves are checked. *)
  let src = {|
mod Test do
  fn pair_up(n : Int) : List(Int) do
    Cons(n, Cons(n * 2, Nil))
  end

  fn main() : Int do
    List.length(pair_up(3))
  end
end
|} in
  let a = analyse src in
  let a2 = An.run_tir_pass a in
  Alcotest.(check bool) "insights were produced (guards vacuity)" true
    (a2.An.tir_fn_insights <> []);
  Alcotest.(check bool) "every insight names a function" true
    (List.for_all (fun (tfi : An.tir_fn_insight) ->
         String.length tfi.An.tfi_fn_name > 0) a2.An.tir_fn_insights);
  Alcotest.(check bool) "an allocating function reports heap allocations" true
    (List.exists (fun (tfi : An.tir_fn_insight) -> tfi.An.tfi_heap_allocs > 0)
       a2.An.tir_fn_insights)

(** Test 6: code_lens_items are consistent with tir_fn_insights. *)
let test_code_lens_consistent_with_tir_insights () =
  (* With the old unparseable source both lists were empty, so "0 <= 0" and a
     [for_all] over nothing both held regardless of the code under test. *)
  let src = {|
mod Test do
  fn apply(f : Int -> Int, x : Int) : Int do
    f(x)
  end

  fn main() : Int do
    apply(fn n -> n + 1, 41)
  end
end
|} in
  let a = analyse src in
  let a2 = An.run_tir_pass a in
  Alcotest.(check bool) "insights were produced (guards vacuity)" true
    (a2.An.tir_fn_insights <> []);
  (* Only the INFORMATIONAL lenses come from TIR insights. Actionable lenses
     (Run / Debug, which carry a command) are produced by [analyse] from the
     presence of a `main` or a test block and are unrelated to this bound — the
     original assertion compared against all lenses and only held because both
     counts were zero on source that never parsed. *)
  let perf_lenses =
    List.filter (fun (cl : An.code_lens_item) -> cl.An.cl_command = None)
      a2.An.code_lens_items in
  Alcotest.(check bool) "informational lens count <= insight count" true
    (List.length perf_lenses <= List.length a2.An.tir_fn_insights);
  Alcotest.(check bool) "every code lens item has a title" true
    (List.for_all (fun (cl : An.code_lens_item) ->
         String.length cl.An.cl_title > 0) a2.An.code_lens_items)

(* ------------------------------------------------------------------ *)
(* Actionable Run / Debug code lenses + executeCommand                  *)
(* ------------------------------------------------------------------ *)

(** Collect the command ids of all actionable lenses (cl_command = Some _). *)
let action_lens_commands (a : An.t) =
  List.filter_map (fun (cl : An.code_lens_item) -> cl.An.cl_command)
    a.An.code_lens_items

(** A test block yields a Run + Debug lens with the right command ids. *)
let test_action_lens_for_test_block () =
  let src = {|
mod Demo do
  test "adds numbers" do
    assert(1 + 1 == 2)
  end
end
|} in
  let a = analyse src in
  let cmds = action_lens_commands a in
  Alcotest.(check bool) "has march.runTest"   true (List.mem "march.runTest" cmds);
  Alcotest.(check bool) "has march.debugTest" true (List.mem "march.debugTest" cmds);
  (* test name must be carried as the second argument *)
  let run_lens =
    List.find (fun (cl : An.code_lens_item) -> cl.An.cl_command = Some "march.runTest")
      a.An.code_lens_items
  in
  let names =
    List.filter_map (function `String s -> Some s | _ -> None) run_lens.An.cl_args
  in
  Alcotest.(check bool) "run lens carries test name" true (List.mem "adds numbers" names)

(** fn main yields a Run + Debug lens with march.run / march.debug. *)
let test_action_lens_for_main () =
  let src = {|
mod App do
  fn main() do
    println("hi")
  end
end
|} in
  let a = analyse src in
  let cmds = action_lens_commands a in
  Alcotest.(check bool) "has march.run"   true (List.mem "march.run" cmds);
  Alcotest.(check bool) "has march.debug" true (List.mem "march.debug" cmds)

(** A file with no tests and no main yields no actionable lenses. *)
let test_action_lens_absent_without_runnables () =
  (* The absence assertion only means something if the file parsed: the old
     source used `-> Int`, so "no runnable lenses" held because there was no
     analysis at all, not because a library module lacks runnables. *)
  let src = {|
mod Lib do
  fn helper(x : Int) : Int do x + 1 end
end
|} in
  let a = analyse src in
  Alcotest.(check bool) "source typechecks (guards vacuity)" false
    (List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
         d.severity = Some Lsp.Types.DiagnosticSeverity.Error) a.An.diagnostics);
  Alcotest.(check bool) "the module's function was actually indexed" true
    (Hashtbl.mem a.An.def_map "helper");
  Alcotest.(check int) "no actionable lenses" 0 (List.length (action_lens_commands a))

(** Action lenses survive the TIR pass (must not be dropped by perf lenses). *)
let test_action_lens_survive_tir_pass () =
  let src = {|
mod App do
  fn main() do
    println("hi")
  end
  test "t" do
    assert(true)
  end
end
|} in
  let a  = analyse src in
  let a2 = An.run_tir_pass a in
  let cmds = action_lens_commands a2 in
  Alcotest.(check bool) "march.run survives"      true (List.mem "march.run" cmds);
  Alcotest.(check bool) "march.runTest survives"  true (List.mem "march.runTest" cmds)

(** resolve_lens_command maps debug commands to a non-blocking DebugEcho. *)
let test_resolve_debug_command_echoes () =
  let r =
    An.resolve_lens_command ~command:"march.debugTest"
      ~args:[ `String "file:///tmp/x.march"; `String "my test" ]
  in
  match r with
  | An.DebugEcho { debug_command; dap; _ } ->
    Alcotest.(check string) "echoes command id" "march.debugTest" debug_command;
    Alcotest.(check bool) "references march dap" true
      (let needle = "march dap" in
       let n = String.length needle and m = String.length dap in
       let rec scan i = i + n <= m && (String.sub dap i n = needle || scan (i+1)) in
       scan 0)
  | _ -> Alcotest.fail "expected DebugEcho for march.debugTest"

(** resolve_lens_command maps run commands to a forge shell invocation. *)
let test_resolve_run_command_builds_forge_shell () =
  let r =
    An.resolve_lens_command ~command:"march.runTest"
      ~args:[ `String "file:///tmp/x.march"; `String "my test" ]
  in
  match r with
  | An.RunShell { shell; _ } ->
    let contains hay needle =
      let n = String.length needle and m = String.length hay in
      let rec scan i = i + n <= m && (String.sub hay i n = needle || scan (i+1)) in
      n = 0 || scan 0
    in
    Alcotest.(check bool) "invokes forge test" true (contains shell "forge test");
    Alcotest.(check bool) "passes --filter"    true (contains shell "--filter")
  | _ -> Alcotest.fail "expected RunShell for march.runTest"

(** Unknown command ids resolve to Unknown rather than raising. *)
let test_resolve_unknown_command () =
  match An.resolve_lens_command ~command:"march.bogus" ~args:[] with
  | An.Unknown c -> Alcotest.(check string) "echoes unknown id" "march.bogus" c
  | _ -> Alcotest.fail "expected Unknown for unrecognised command"

(* ------------------------------------------------------------------ *)
(* Scope-aware symbol identity (Phase 3)                               *)
(* ------------------------------------------------------------------ *)

let test_scoped_shadow_distinct () =
  (* 'x' is a param of outer; the inner lambda shadows it with its own 'x'.
     The lambda-body use of x and the outer-body use of x must resolve to
     DIFFERENT binders. *)
  let src =
    "mod M do\n\
    \  fn outer(x: Int) : Int do\n\
    \    let inner = fn (x: Int) -> x + 1\n\
    \    x\n\
    \  end\n\
     end\n"
  in
  let a = An.analyse ~filename:"t.march" ~src in
  let lambda_x = An.local_symbol_at a ~line:2 ~character:31 in (* x in lambda body *)
  let outer_x  = An.local_symbol_at a ~line:3 ~character:4  in (* x in outer body *)
  Alcotest.(check bool) "lambda-body x resolves to a local" true (lambda_x <> None);
  Alcotest.(check bool) "outer-body x resolves to a local"  true (outer_x  <> None);
  Alcotest.(check bool) "shadowed x's are distinct binders" true (lambda_x <> outer_x)

let test_rename_respects_shadowing () =
  (* Renaming the inner (lambda) x must touch ONLY the lambda's binder+use
     (both on line 2), never the outer x (lines 1 and 3) — and vice versa.
     The old name-based rename mixed them. *)
  let src =
    "mod M do\n\
    \  fn outer(x: Int) : Int do\n\
    \    let inner = fn (x: Int) -> x + 1\n\
    \    x\n\
    \  end\n\
     end\n"
  in
  let a = An.analyse ~filename:"t.march" ~src in
  let start_lines es =
    List.sort compare
      (List.map (fun (e : Lsp.Types.TextEdit.t) ->
         e.Lsp.Types.TextEdit.range.Lsp.Types.Range.start.Lsp.Types.Position.line)
         es)
  in
  let lam = An.rename_at a ~line:2 ~character:31 ~new_name:"q" in
  let out = An.rename_at a ~line:3 ~character:4  ~new_name:"q" in
  Alcotest.(check (list int)) "lambda x rename stays in the lambda (line 2 only)"
    [2; 2] (start_lines lam);
  Alcotest.(check (list int)) "outer x rename hits outer def+use (lines 1,3) only"
    [1; 3] (start_lines out)

let test_prepare_rename_validates () =
  (* prepareRename accepts a local binding and rejects keywords/whitespace. *)
  let src =
    "mod M do\n\
    \  fn outer(x: Int) : Int do\n\
    \    let inner = fn (x: Int) -> x + 1\n\
    \    x\n\
    \  end\n\
     end\n"
  in
  let a = An.analyse ~filename:"t.march" ~src in
  Alcotest.(check bool) "a local variable is renameable"
    true  (An.prepare_rename_at a ~line:3 ~character:4 <> None);
  Alcotest.(check bool) "a keyword is not renameable"
    false (An.prepare_rename_at a ~line:1 ~character:2 <> None);
  Alcotest.(check bool) "whitespace is not renameable"
    false (An.prepare_rename_at a ~line:3 ~character:1 <> None)

(* ------------------------------------------------------------------ *)
(* Context-aware completion (Phase 4)                                  *)
(* ------------------------------------------------------------------ *)

let test_dot_completion_record_fields () =
  (* In 'r.x' where r : { x : Int, y : Int }, completion offers exactly the
     record's fields — not the whole keyword/var namespace. *)
  let src =
    "mod M do\n\
    \  fn f() : Int do\n\
    \    let r = { x: 1, y: 2 }\n\
    \    r.x\n\
    \  end\n\
     end\n"
  in
  let a = An.analyse ~filename:"t.march" ~src in
  let labels items =
    List.sort compare
      (List.map (fun (i : Lsp.Types.CompletionItem.t) ->
         i.Lsp.Types.CompletionItem.label) items)
  in
  let dot = An.completions_at a ~line:3 ~character:6 in
  Alcotest.(check (list string)) "dot-completion offers exactly the record fields"
    [ "x"; "y" ] (labels dot);
  (* A non-dot position still returns the general (much larger) list. *)
  let flat = An.completions_at a ~line:1 ~character:2 in
  Alcotest.(check bool) "non-dot context returns the general list"
    true (List.length flat > 2)

(* ------------------------------------------------------------------ *)
(* Workspace symbols (Phase 5)                                         *)
(* ------------------------------------------------------------------ *)

let test_workspace_index_cross_file () =
  let module W = March_lsp_lib.Workspace in
  let files =
    [ ("a.march",
       "mod A do\n  fn alpha() : Int do 1 end\n  type Color = Red | Green\nend\n");
      ("b.march", "mod B do\n  fn beta() : Int do 2 end\nend\n") ]
  in
  let idx = W.index_sources files in
  let names q =
    List.sort compare
      (List.map (fun (s : W.ws_symbol) -> s.W.wsy_name) (W.query_symbols idx q))
  in
  Alcotest.(check (list string)) "exact name finds the symbol" [ "alpha" ] (names "alpha");
  Alcotest.(check (list string)) "subsequence query matches" [ "Color" ] (names "Clr");
  Alcotest.(check int) "all five top-level symbols indexed across files"
    5 (List.length idx);
  let alpha = List.find (fun (s : W.ws_symbol) -> s.W.wsy_name = "alpha") idx in
  Alcotest.(check string) "alpha is indexed from its own file"
    "a.march" alpha.W.wsy_file

let test_workspace_cross_file_references () =
  let module W = March_lsp_lib.Workspace in
  let files =
    [ ("a.march", "mod A do\n  fn shared() : Int do 1 end\nend\n");
      ("b.march",
       "mod B do\n  fn use1() : Int do shared() end\n  fn use2() : Int do shared() + 1 end\nend\n") ]
  in
  let idx = W.index_full files in
  let refs = W.references_across idx "shared" in
  (* 1 definition in a.march + 2 uses in b.march. *)
  Alcotest.(check int) "all cross-file occurrences of 'shared'" 3 (List.length refs);
  let files_of =
    List.sort_uniq compare (List.map (fun (f, _) -> Filename.basename f) refs)
  in
  Alcotest.(check (list string)) "references span both files"
    [ "a.march"; "b.march" ] files_of

(* ------------------------------------------------------------------ *)
(* Query facade (Phase 2)                                              *)
(* ------------------------------------------------------------------ *)

let test_query_hover_record () =
  let src = "mod Test do\n  fn f() : Int do 41 end\nend\n" in
  let a = An.analyse ~filename:"t.march" ~src in
  (* 'f' is at line 1, UTF-16 column 5. *)
  let r = March_lsp_lib.Query.hover a ~line:1 ~utf16_char:5 in
  Alcotest.(check bool) "hover record carries a type"
    true (r.March_lsp_lib.Query.h_type <> None)

(* ------------------------------------------------------------------ *)
(* Document version guard (Phase 1)                                    *)
(* ------------------------------------------------------------------ *)

let test_version_guard () =
  let open March_lsp_lib.Server in
  let vt = make_version_table () in
  ignore (bump_version vt "u");   (* v = 1 *)
  ignore (bump_version vt "u");   (* v = 2 *)
  (* A fiber that started at v=1 must NOT publish once current is v=2. *)
  Alcotest.(check bool) "stale (v1) rejected"  false (is_current vt "u" 1);
  Alcotest.(check bool) "current (v2) accepted" true  (is_current vt "u" 2)

(* ------------------------------------------------------------------ *)
(* Error-resilient analysis (Phase 1)                                  *)
(* ------------------------------------------------------------------ *)

let test_resilient_keeps_last_good () =
  (* A broken edit that fails to parse must not blank out IDE features: the
     resilient analysis retains the last good symbol maps while reporting the
     new parse error. *)
  let good = "mod M do\n  fn f() : Int do 41 end\nend\n" in
  let a_good = An.analyse ~filename:"t.march" ~src:good in
  let broken = "mod M do\n  fn f() : Int do 41 end\n  fn g(\n" in
  let a = An.analyse_resilient ~prev:(Some a_good) ~filename:"t.march" ~src:broken in
  Alcotest.(check bool) "broken edit still reports diagnostics"
    true (a.An.diagnostics <> []);
  Alcotest.(check bool) "def map retained from last good analysis"
    true (Hashtbl.mem a.An.def_map "f")

(* ------------------------------------------------------------------ *)
(* Stdlib cache (Phase 1)                                              *)
(* ------------------------------------------------------------------ *)

let test_stdlib_cache_memoizes () =
  (* Two loads in the same process must return the *physically same* decls
     list — proving the parse/desugar is memoized, not repeated. When the
     stdlib is present (direct runs, CI) the lists are a shared non-empty cons
     cell; under dune's sandbox the stdlib dir may be unreachable and both are
     the empty list — physical equality holds either way, and a broken memo
     (fresh list per call) fails it whenever the stdlib is found. *)
  let d1 = March_lsp_lib.Stdlib_cache.load () in
  let d2 = March_lsp_lib.Stdlib_cache.load () in
  Alcotest.(check bool) "same cached decls (memoized)" true (d1 == d2)

(* ------------------------------------------------------------------ *)
(* UTF-16 position encoding (Phase 0)                                  *)
(* ------------------------------------------------------------------ *)

let has_sub s sub =
  let ls = String.length s and lsub = String.length sub in
  let rec go i = i + lsub <= ls && (String.sub s i lsub = sub || go (i + 1)) in
  go 0

let test_hover_after_unicode () =
  (* On line 2, '    let t = ("é", n)', the param 'n' sits AFTER a 2-byte char
     (é, 1 UTF-16 unit / 2 bytes). 'n' is at UTF-16 column 18 but byte column
     19. The query path must convert UTF-16->byte; otherwise the cursor lands
     one byte early (on the space inside the tuple) and reports the tuple type
     "(String, Int)" instead of the parameter's type "Int". *)
  let src =
    "mod Test do\n\
    \  fn f(n: Int) : Int do\n\
    \    let t = (\"\xc3\xa9\", n)\n\
    \    n\n\
    \  end\n\
     end\n"
  in
  let a = An.analyse ~filename:"t.march" ~src in
  match An.query_type_at a ~line:2 ~utf16_char:18 with
  | None -> Alcotest.fail "expected a type at the identifier 'n'"
  | Some s ->
    Alcotest.(check bool)
      "n resolves to Int (not the enclosing tuple) — UTF-16 column converted"
      true (has_sub s "Int" && not (has_sub s "String"))

let test_hover_in_h_interp () =
  let src = {|mod M do
  fn greet(name : String) : IOList do
    ~H"<p>${name}</p>"
  end
end|} in
  let a = An.analyse ~filename:"t.march" ~src in
  let (l, c) = pos_of src "name}" in
  (match An.query_type_at a ~line:l ~utf16_char:c with
   | None -> Alcotest.fail "TYPE: expected a type for the interpolation expr 'name'"
   | Some s -> Alcotest.(check bool) "interp 'name' resolves to String" true (has_sub s "String"));
  Alcotest.(check bool) "DEF inside interp resolves"
    true (An.query_definition_at a ~line:l ~utf16_char:c <> None);
  let comps = An.query_completions_at a ~line:l ~utf16_char:c in
  let labels = List.map (fun (it : Lsp.Types.CompletionItem.t) -> it.Lsp.Types.CompletionItem.label) comps in
  Alcotest.(check bool) "COMPLETION inside interp includes 'name'" true (List.mem "name" labels)

(* ------------------------------------------------------------------ *)
(* Tier 4 (a): attribute-value interpolation                           *)
(* ------------------------------------------------------------------ *)

let test_h_interp_attr_value () =
  (* url : String used as an attribute value expression — hover resolves to String *)
  let src = {|mod M do
  fn link(url : String) : IOList do
    ~H"<a href=${url}>click</a>"
  end
end|} in
  let a = An.analyse ~filename:"t.march" ~src in
  Alcotest.(check bool) "analysis non-empty (sanity)" true
    (Hashtbl.length a.An.type_map > 0);
  let (l, c) = pos_of src "url}>" in
  (match An.query_type_at a ~line:l ~utf16_char:c with
   | None -> Alcotest.fail "TYPE: expected String for url in attr-value interpolation"
   | Some s -> Alcotest.(check bool) "url resolves to String in attr-value interp"
       true (has_sub s "String"));
  Alcotest.(check bool) "DEF: url in attr-value interp resolves"
    true (An.query_definition_at a ~line:l ~utf16_char:c <> None)

(* ------------------------------------------------------------------ *)
(* Tier 4 (b): field access inside interpolation                       *)
(* ------------------------------------------------------------------ *)

let test_h_interp_field_access () =
  (* u.name inside ${u.name} — type at the field name resolves to String;
     def on 'u' (the object) finds the param.
     Use distinct substrings to avoid ambiguity with the record-type definition. *)
  let src = {|mod M do
  type User = { uname : String }
  fn show(u : User) : IOList do
    ~H"<p>${u.uname}</p>"
  end
end|} in
  let a = An.analyse ~filename:"t.march" ~src in
  Alcotest.(check bool) "analysis non-empty (sanity)" true
    (Hashtbl.length a.An.type_map > 0);
  (* "uname}" only appears in the interpolation — positions cursor at field name *)
  let (l, c) = pos_of src "uname}" in
  (match An.query_type_at a ~line:l ~utf16_char:c with
   | None -> Alcotest.fail "TYPE: expected String for u.uname field-access in interp"
   | Some s -> Alcotest.(check bool) "u.uname resolves to String"
       true (has_sub s "String"));
  (* position at 'u' to check the object variable def resolves to its param *)
  let (lu, cu) = pos_of src "u.uname}" in
  Alcotest.(check bool) "DEF: u inside field-access interp resolves to param"
    true (An.query_definition_at a ~line:lu ~utf16_char:cu <> None)

(* ------------------------------------------------------------------ *)
(* Tier 4 (c): let-bound local used in interpolation                   *)
(* ------------------------------------------------------------------ *)

let test_h_interp_let_binding () =
  (* let msg = "hi"; msg used in ~H — def should jump back to the let *)
  let src = {|mod M do
  fn page() : IOList do
    let msg = "hi"
    ~H"<p>${msg}</p>"
  end
end|} in
  let a = An.analyse ~filename:"t.march" ~src in
  Alcotest.(check bool) "analysis non-empty (sanity)" true
    (Hashtbl.length a.An.type_map > 0);
  let (l, c) = pos_of src "msg}" in
  (* type should be String (string literal assigned to msg) *)
  (match An.query_type_at a ~line:l ~utf16_char:c with
   | None -> Alcotest.fail "TYPE: expected String for let-bound 'msg' in interp"
   | Some s -> Alcotest.(check bool) "msg resolves to String"
       true (has_sub s "String"));
  (* def should resolve — the binding site of let msg *)
  let def_opt = An.query_definition_at a ~line:l ~utf16_char:c in
  Alcotest.(check bool) "DEF: msg in interp resolves to let binding"
    true (def_opt <> None);
  (* Verify it jumps to the let line — "let msg" is on a different line than ~H *)
  (match def_opt with
   | None -> ()
   | Some loc ->
     let def_line = loc.Lsp.Types.Location.range.Lsp.Types.Range.start.Lsp.Types.Position.line in
     let (let_line, _) = pos_of src "let msg" in
     Alcotest.(check int) "def of msg points to let-binding line" let_line def_line)

(* ------------------------------------------------------------------ *)
(* Tier 4 (d): multiple interpolations on one line                     *)
(* ------------------------------------------------------------------ *)

let test_h_interp_multiple_on_one_line () =
  (* ~H"<p>${a}-${b}</p>" — a:Int, b:String; each resolves to its own type *)
  let src = {|mod M do
  fn page(a : Int, b : String) : IOList do
    ~H"<p>${a}-${b}</p>"
  end
end|} in
  let a = An.analyse ~filename:"t.march" ~src in
  Alcotest.(check bool) "analysis non-empty (sanity)" true
    (Hashtbl.length a.An.type_map > 0);
  let (la, ca) = pos_of src "a}-" in
  let (lb, cb) = pos_of src "b}<" in
  (match An.query_type_at a ~line:la ~utf16_char:ca with
   | None -> Alcotest.fail "TYPE: expected Int for 'a' in first interpolation"
   | Some s -> Alcotest.(check bool) "first interp 'a' resolves to Int"
       true (has_sub s "Int" && not (has_sub s "String")));
  (match An.query_type_at a ~line:lb ~utf16_char:cb with
   | None -> Alcotest.fail "TYPE: expected String for 'b' in second interpolation"
   | Some s -> Alcotest.(check bool) "second interp 'b' resolves to String"
       true (has_sub s "String"))

(* ------------------------------------------------------------------ *)
(* Tier 4 (e): triple-quoted ~H sigil                                  *)
(* ------------------------------------------------------------------ *)

let test_h_interp_triple_quoted () =
  (* ~H"""<p>${name}</p>""" — triple-quoted form; hover resolves the same way *)
  let src = {|mod M do
  fn greet(name : String) : IOList do
    ~H"""<p>${name}</p>"""
  end
end|} in
  let a = An.analyse ~filename:"t.march" ~src in
  Alcotest.(check bool) "analysis non-empty (sanity)" true
    (Hashtbl.length a.An.type_map > 0);
  let (l, c) = pos_of src "name}<" in
  (match An.query_type_at a ~line:l ~utf16_char:c with
   | None -> Alcotest.fail "TYPE: expected String for 'name' in triple-quoted sigil"
   | Some s -> Alcotest.(check bool) "triple-quoted interp 'name' resolves to String"
       true (has_sub s "String"));
  Alcotest.(check bool) "DEF: triple-quoted interp 'name' def resolves"
    true (An.query_definition_at a ~line:l ~utf16_char:c <> None)

(* ------------------------------------------------------------------ *)
(* Task 2: diagnostic positions inside ${…}                            *)
(* ------------------------------------------------------------------ *)

let test_h_interp_diagnostic_position () =
  (* A type error inside ${1 + "x"} must produce a diagnostic whose range
     start line matches the interpolation expression's line, not column 0
     and not a collapsed sigil-start position. *)
  let src = {|mod M do
  fn bad() : IOList do
    ~H"<p>${1 + "x"}</p>"
  end
end|} in
  let a = An.analyse ~filename:"t.march" ~src in
  (* There must be at least one error diagnostic *)
  let errs = List.filter (fun (d : Lsp.Types.Diagnostic.t) ->
      d.severity = Some Lsp.Types.DiagnosticSeverity.Error) a.diagnostics in
  Alcotest.(check bool) "type error inside ${} produces a diagnostic"
    true (errs <> []);
  (* The interpolation expression is on the same line as ~H (line 2, 0-indexed).
     Find the ~H sigil line. *)
  let (sigil_line, _) = pos_of src {|~H"<p>|} in
  (* At least one error diagnostic must have its range start on the sigil line
     (the line that contains the interpolation expression). *)
  let on_interp_line = List.exists (fun (d : Lsp.Types.Diagnostic.t) ->
      d.range.Lsp.Types.Range.start.Lsp.Types.Position.line = sigil_line) errs in
  Alcotest.(check bool)
    "error diagnostic range-start is on the interpolation line (not collapsed to line 0)"
    true on_interp_line

(* ------------------------------------------------------------------ *)
(* Task 3: island props=${e} — hover/def work on the props expression  *)
(* ------------------------------------------------------------------ *)

let test_h_island_props_interp () =
  (* <island name='Counter' props=${someVar} /> — hover/def on someVar *)
  let src = {|mod M do
  mod Counter do
    fn create(n : Int) : Int do n end
    fn render(s : Int) : Int do s end
  end
  fn page(someVar : Int) : IOList do
    ~H"<island name='Counter' props=${someVar} />"
    0
  end
end|} in
  let a = An.analyse ~filename:"t.march" ~src in
  Alcotest.(check bool) "analysis non-empty (sanity)" true
    (Hashtbl.length a.An.type_map > 0);
  let (l, c) = pos_of src "someVar} " in
  (match An.query_type_at a ~line:l ~utf16_char:c with
   | None -> Alcotest.fail "TYPE: expected Int for someVar in island props interpolation"
   | Some s -> Alcotest.(check bool) "someVar in props=${} resolves to Int"
       true (has_sub s "Int"));
  Alcotest.(check bool) "DEF: someVar in props=${} resolves"
    true (An.query_definition_at a ~line:l ~utf16_char:c <> None)

(* ------------------------------------------------------------------ *)
(* Top-level resolution vs stdlib (Phase 5 fix)                        *)
(* ------------------------------------------------------------------ *)

let test_user_symbol_wins_over_stdlib_name () =
  (* A user fn named like a stdlib one ('abs') must resolve to the USER
     definition: (1) def_map user-win over stdlib, and (2) the position scan
     must filter stdlib spans that collide on (line,col). Go-to-def on the use
     lands in the user file at the user's definition line. *)
  let src =
    "mod M do\n  fn abs(x : Int) : Int do x end\n  fn caller() : Int do abs(1) end\nend\n"
  in
  let a = analyse src in
  let (ul, uc) = pos_of src "abs(1)" in
  match An.definition_at a ~line:ul ~character:uc with
  | None -> Alcotest.fail "expected a definition for the user 'abs'"
  | Some loc ->
    let uri = Lsp.Types.DocumentUri.to_string loc.Lsp.Types.Location.uri in
    Alcotest.(check bool) "resolves to the user file, not stdlib"
      true (has_sub uri "test.march" && not (has_sub uri "stdlib"));
    let (dl, _) = pos_of src "fn abs" in
    Alcotest.(check int) "jumps to the user definition line"
      dl loc.Lsp.Types.Location.range.Lsp.Types.Range.start.Lsp.Types.Position.line

(* ------------------------------------------------------------------ *)
(* implementation / typeDefinition / documentHighlight                 *)
(* ------------------------------------------------------------------ *)

let test_implementation () =
  let src = {|mod M do
  interface Drawable(a) do
    fn draw: a -> String
  end
  type Widget = Alpha | Beta
  impl Drawable(Widget) do
    fn draw(w) do "w" end
  end
end|} in
  let a = analyse src in
  let (il, ic) = pos_of src "interface Drawable" in
  (* cursor on the interface name "Drawable" (after "interface ") *)
  let locs = An.implementation_at a ~line:il ~character:(ic + 10) in
  Alcotest.(check int) "interface resolves to its single impl" 1 (List.length locs)

let test_type_definition () =
  let src = {|mod M do
  type Widget = Alpha | Beta
  fn f(w : Widget) : Widget do w end
end|} in
  let a = analyse src in
  let (wl, wc) = pos_of src "w end" in
  let (dl, _)  = pos_of src "type Widget" in
  (match An.type_definition_at a ~line:wl ~character:wc with
   | None -> Alcotest.fail "expected a type definition for the value"
   | Some l ->
     Alcotest.(check int) "jumps to the type declaration line"
       dl l.Lsp.Types.Location.range.Lsp.Types.Range.start.Lsp.Types.Position.line)

let test_document_highlight () =
  let src = {|mod M do
  fn f() : Int do
    let x = 1
    x + x
  end
end|} in
  let a = analyse src in
  let (xl, xc) = pos_of src "x + x" in
  let hls = An.document_highlights_at a ~line:xl ~character:xc in
  Alcotest.(check int) "highlights the binding and both uses" 3 (List.length hls)

let test_completion_scoped_locals () =
  let src = {|mod M do
  fn f(alpha : Int) : Int do
    let beta = 1
    HOLE
  end
  fn g(gamma : Int) : Int do gamma end
end|} in
  let a = analyse src in
  let (hl, hc) = pos_of src "HOLE" in
  let items  = An.completions_at a ~line:hl ~character:hc in
  let labels = List.map (fun (i : Lsp.Types.CompletionItem.t) ->
      i.Lsp.Types.CompletionItem.label) items in
  let has x = List.mem x labels in
  Alcotest.(check bool) "in-scope param offered"  true  (has "alpha");
  Alcotest.(check bool) "in-scope let offered"    true  (has "beta");
  Alcotest.(check bool) "out-of-scope local hidden" false (has "gamma");
  let alpha = List.find (fun (i : Lsp.Types.CompletionItem.t) ->
      i.Lsp.Types.CompletionItem.label = "alpha") items in
  Alcotest.(check (option string)) "locals rank first (sortText 0)"
    (Some "0") alpha.Lsp.Types.CompletionItem.sortText

(* ------------------------------------------------------------------ *)
(* Semantic tokens: ownership modifiers + use-site fidelity           *)
(* ------------------------------------------------------------------ *)

(* Decode the LSP flat delta-encoded token array into (tokenType,
   tokenModifiers) pairs — one per 5-int group. *)
let decode_semantic_tokens (arr : int array) =
  List.init (Array.length arr / 5) (fun i -> (arr.(i*5 + 3), arr.(i*5 + 4)))

let test_semantic_tokens_linear_modifier () =
  (* A binding DECLARED linear carries the linear modifier (bit 8). *)
  let src = {|mod M do
  fn f() : Int do
    linear let x = 42
    x
  end
end|} in
  let a = analyse src in
  let toks = decode_semantic_tokens (March_lsp_lib.Server.semantic_tokens_data a) in
  Alcotest.(check bool) "a `linear let` binding is marked linear" true
    (List.exists (fun (_, m) -> m land 8 <> 0) toks)

let test_semantic_tokens_affine_modifier () =
  (* A binding DECLARED affine carries the affine modifier (bit 16). *)
  let src = {|mod M do
  fn f() : Int do
    affine let x = 42
    x
  end
end|} in
  let a = analyse src in
  let toks = decode_semantic_tokens (March_lsp_lib.Server.semantic_tokens_data a) in
  Alcotest.(check bool) "an `affine let` binding is marked affine" true
    (List.exists (fun (_, m) -> m land 16 <> 0) toks)

let test_semantic_tokens_always_linear_type () =
  (* A parameter whose type is declared `always_linear type` is linear with no
     per-site annotation — the modifier must follow the type, not the syntax. *)
  let src = {|mod M do
  always_linear type Handle = Handle(Int)
  fn use_it(h : Handle) : Int do
    match h do
      Handle(n) -> n
    end
  end
end|} in
  let a = analyse src in
  let toks = decode_semantic_tokens (March_lsp_lib.Server.semantic_tokens_data a) in
  Alcotest.(check bool) "an always_linear-typed param is marked linear" true
    (List.exists (fun (_, m) -> m land 8 <> 0) toks)

let test_semantic_tokens_plain_binding_not_linear () =
  (* REGRESSION WITNESS. The modifier used to be derived from USE COUNTS, so an
     ordinary binding mentioned exactly once was painted `linear` and one never
     mentioned was painted `affine`. Neither is a linearity claim the compiler
     makes, and asserting one in the editor misrepresents the guarantee the
     reader is there to check. Both bindings below are unrestricted.

     The token-count assertion is load-bearing: if the embedded source ever
     stops parsing, the analysis silently yields NO tokens and the two
     "not marked" checks would pass vacuously. *)
  let src = {|mod M do
  fn f() : Int do
    let used_once = 42
    let never_used = 7
    used_once
  end
end|} in
  let a = analyse src in
  let toks = decode_semantic_tokens (March_lsp_lib.Server.semantic_tokens_data a) in
  Alcotest.(check bool) "analysis produced tokens (guards against vacuous pass)"
    true (List.length toks > 0);
  Alcotest.(check bool) "a once-used plain binding is NOT marked linear" false
    (List.exists (fun (_, m) -> m land 8 <> 0) toks);
  Alcotest.(check bool) "an unused plain binding is NOT marked affine" false
    (List.exists (fun (_, m) -> m land 16 <> 0) toks)

let test_semantic_tokens_use_site_ctor_fidelity () =
  (* The two declarations Red/Green produce 2 enumMember tokens; the use
     site of `Red` must add a 3rd (tagged enumMember, not variable). *)
  let src = {|mod M do
  type Color = Red | Green
  fn f() : Color do Red end
end|} in
  let a = analyse src in
  let toks = decode_semantic_tokens (March_lsp_lib.Server.semantic_tokens_data a) in
  let enum_count = List.length (List.filter (fun (t, _) -> t = 3) toks) in
  Alcotest.(check bool) "constructor use site tagged enumMember (decls + use)"
    true (enum_count >= 3)

(* ------------------------------------------------------------------ *)
(* FBIP performance inlay hints (reused / copied)                      *)
(* ------------------------------------------------------------------ *)

let inlay_labels a =
  let range = Lsp.Types.Range.create
      ~start:(Lsp.Types.Position.create ~line:0 ~character:0)
      ~end_:(Lsp.Types.Position.create ~line:1000 ~character:0) in
  List.filter_map (fun (h : Lsp.Types.InlayHint.t) ->
      match h.Lsp.Types.InlayHint.label with `String s -> Some s | _ -> None)
    (An.inlay_hints_for a range)

let test_inlay_reuse_hint () =
  (* `p` is an allocation (P(1,2)) consumed exactly once → FBIP reuse candidate. *)
  let src = {|mod M do
  type P = P(Int, Int)
  fn f() : Int do
    let p = P(1, 2)
    match p do
      P(a, b) -> a + b
    end
  end
end|} in
  let a = analyse src in
  Alcotest.(check bool) "single-use allocation gets a reuse inlay" true
    (List.exists (str_contains ~sub:"reused") (inlay_labels a))

let test_inlay_no_reuse_for_scalar () =
  (* A scalar binding (no allocation) must NOT get a reuse hint. *)
  let src = {|mod M do
  fn f() : Int do
    let x = 42
    x
  end
end|} in
  let a = analyse src in
  Alcotest.(check bool) "scalar binding has no reuse inlay" false
    (List.exists (str_contains ~sub:"reused") (inlay_labels a))

let test_inlay_copy_hint_wiring () =
  (* Every detected send-copy insight must surface as a 'copied' inlay.
     Vacuously holds when type resolution doesn't fire (sandbox), but guards
     the wiring whenever it does. *)
  let src = {|mod M do
  fn do_send(pid: Pid(W), items: List(Int)) : Unit do
    send(pid, items)
  end
end|} in
  let a = analyse src in
  let send_copies =
    List.length (List.filter (fun (pi : An.perf_insight) ->
        match pi.An.pi_kind with An.ActorSendCopy _ -> true | _ -> false)
      a.An.perf_insights) in
  let copied =
    List.length (List.filter (str_contains ~sub:"copied") (inlay_labels a)) in
  Alcotest.(check bool) "send-copies surfaced as inlays" true (copied >= send_copies)

(* ------------------------------------------------------------------ *)
(* Parameter-name inlay hints at call sites                            *)
(* ------------------------------------------------------------------ *)

(* Collect (label, line, character) for every Parameter-kind inlay hint. *)
let param_hints ?(param_names = true) a =
  let range = Lsp.Types.Range.create
      ~start:(Lsp.Types.Position.create ~line:0 ~character:0)
      ~end_:(Lsp.Types.Position.create ~line:1000 ~character:0) in
  List.filter_map (fun (h : Lsp.Types.InlayHint.t) ->
      match h.Lsp.Types.InlayHint.kind, h.Lsp.Types.InlayHint.label with
      | Some Lsp.Types.InlayHintKind.Parameter, `String s ->
        Some (s, h.position.line, h.position.character)
      | _ -> None)
    (An.inlay_hints_for ~param_names a range)

let test_param_hint_two_arg_call () =
  (* A 2-arg user call emits both `name:` hints, in order. *)
  let src = {|mod M do
  fn rect(width: Int, height: Int) : Int do width * height end
  fn caller() : Int do
    rect(10, 20)
  end
end|} in
  let a = analyse src in
  let labels = List.map (fun (s, _, _) -> s) (param_hints a) in
  Alcotest.(check bool) "width: hint present" true (List.mem "width:" labels);
  Alcotest.(check bool) "height: hint present" true (List.mem "height:" labels)

let test_param_hint_positions_at_arg_start () =
  (* Hints land at the START column of each argument expression. *)
  let src = {|mod M do
  fn rect(width: Int, height: Int) : Int do width * height end
  fn caller() : Int do
    rect(10, 20)
  end
end|} in
  let a = analyse src in
  let hs = param_hints a in
  (* "    rect(10, 20)" — 0-indexed: '1' of "10" at col 9, '2' of "20" at col 13. *)
  let width_pos = List.find_opt (fun (s, _, _) -> s = "width:") hs in
  let height_pos = List.find_opt (fun (s, _, _) -> s = "height:") hs in
  (match width_pos with
   | Some (_, _, c) -> Alcotest.(check int) "width: at arg start col" 9 c
   | None -> Alcotest.fail "missing width: hint");
  (match height_pos with
   | Some (_, _, c) -> Alcotest.(check int) "height: at arg start col" 13 c
   | None -> Alcotest.fail "missing height: hint")

let test_param_hint_suppress_redundant_identifier () =
  (* foo(width) where the var IS named width is redundant → suppressed.
     The second arg (a literal) keeps its hint. *)
  let src = {|mod M do
  fn rect(width: Int, height: Int) : Int do width * height end
  fn caller(width: Int) : Int do
    rect(width, 20)
  end
end|} in
  let a = analyse src in
  let labels = List.map (fun (s, _, _) -> s) (param_hints a) in
  Alcotest.(check bool) "redundant width: suppressed" false
    (List.mem "width:" labels);
  Alcotest.(check bool) "non-redundant height: kept" true
    (List.mem "height:" labels)

let test_param_hint_suppress_single_arg () =
  (* Single-argument calls add no value → suppressed. *)
  let src = {|mod M do
  fn inc(value: Int) : Int do value + 1 end
  fn caller() : Int do
    inc(41)
  end
end|} in
  let a = analyse src in
  let labels = List.map (fun (s, _, _) -> s) (param_hints a) in
  Alcotest.(check bool) "single-arg hint suppressed" false
    (List.mem "value:" labels)

let test_param_hint_toggle_off () =
  (* With param_names:false the hints disappear entirely. *)
  let src = {|mod M do
  fn rect(width: Int, height: Int) : Int do width * height end
  fn caller() : Int do
    rect(10, 20)
  end
end|} in
  let a = analyse src in
  let labels = List.map (fun (s, _, _) -> s) (param_hints ~param_names:false a) in
  Alcotest.(check int) "no parameter hints when toggled off" 0
    (List.length labels)

let test_param_hint_nested_in_cond () =
  (* A call nested inside an `if` branch body still gets parameter-name hints.
     Exercises the generic iter_expr traversal over the EIf form. *)
  let src = {|mod M do
  fn rect(width: Int, height: Int) : Int do width * height end
  fn caller(flag: Bool) : Int do
    if flag do
      rect(10, 20)
    else
      0
    end
  end
end|} in
  let a = analyse src in
  let labels = List.map (fun (s, _, _) -> s) (param_hints a) in
  Alcotest.(check bool) "width: hint inside if branch" true
    (List.mem "width:" labels);
  Alcotest.(check bool) "height: hint inside if branch" true
    (List.mem "height:" labels)

let test_param_hint_map_cached () =
  (* The param-name map is precomputed once and stored on the analysis record;
     repeated inlay-hint requests read the same cached table (identity-equal). *)
  let src = {|mod M do
  fn rect(width: Int, height: Int) : Int do width * height end
  fn caller() : Int do
    rect(10, 20)
  end
end|} in
  let a = analyse src in
  Alcotest.(check bool) "cached param_name_map has rect entry" true
    (Option.is_some (Hashtbl.find_opt a.March_lsp_lib.Analysis.param_name_map "rect"));
  (* Two requests yield identical labels, reusing the cached map. *)
  let labels1 = List.map (fun (s, _, _) -> s) (param_hints a) in
  let labels2 = List.map (fun (s, _, _) -> s) (param_hints a) in
  Alcotest.(check (list string)) "stable hints across requests" labels1 labels2

let test_param_hint_config_toggle_parse () =
  let parse = March_lsp_lib.Server.param_name_hints_from_settings in
  let nested =
    `Assoc [("march", `Assoc [("inlayHints",
      `Assoc [("parameterNames", `Bool false)])])] in
  Alcotest.(check (option bool)) "reads fully-qualified setting" (Some false)
    (parse nested);
  let stripped =
    `Assoc [("inlayHints", `Assoc [("parameterNames", `Bool true)])] in
  Alcotest.(check (option bool)) "reads prefix-stripped setting" (Some true)
    (parse stripped);
  Alcotest.(check (option bool)) "absent setting is None" None
    (parse (`Assoc [("other", `Int 1)]))

(* ------------------------------------------------------------------ *)
(* documentHighlight Read/Write kinds                                  *)
(* ------------------------------------------------------------------ *)

let test_document_highlight_read_write_kinds () =
  let src = {|mod M do
  fn f() : Int do
    let x = 1
    x + x
  end
end|} in
  let a = analyse src in
  let (xl, xc) = pos_of src "x + x" in
  let hls = An.document_highlights_at a ~line:xl ~character:xc in
  let kind_count k =
    List.length (List.filter (fun (h : Lsp.Types.DocumentHighlight.t) ->
        h.Lsp.Types.DocumentHighlight.kind = Some k) hls) in
  Alcotest.(check int) "binding site is a Write" 1
    (kind_count Lsp.Types.DocumentHighlightKind.Write);
  Alcotest.(check int) "both use sites are Reads" 2
    (kind_count Lsp.Types.DocumentHighlightKind.Read)

let test_tag_pair_highlight () =
  let src = {|mod M do
  fn page() : IOList do
    ~H"<div><span>x</span></div>"
  end
end|} in
  let a = analyse src in
  (* cursor on the 'd' of the opening <div>: pos_of "<div>" gives col of '<',
     +1 moves onto 'd' which is inside the open-tag name span *)
  let (l, c) = pos_of src "<div>" in
  let hls = An.document_highlights_at a ~line:l ~character:(c + 1) in
  Alcotest.(check int) "open + close div highlighted" 2 (List.length hls)

