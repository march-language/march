(** LLVM IR validity gate (Wave 2 Task 3 / W2.1).

    Emitted IR was never verified anywhere in this project: an ill-typed IR
    node (the `coerce` catch-all class, or any other emitter bug that
    produces textually-valid-looking but type-incorrect LLVM assembly) only
    ever surfaced as an opaque `clang` parse/verify error at `--compile`
    time, or — worse — as a `clang` MISCOMPILE / silent wrong-codegen if the
    ill-typed construct happened to still assemble (e.g. a pointer/i64
    mismatch clang's own frontend tolerates in some contexts). This module
    adds an explicit LLVM module-verifier pass over the textual IR for every
    fixture in `test/native/*.march`, so an ill-typed emission fails at TEST
    time with a locatable `file.ll:line:col` error instead of surfacing much
    later as an inscrutable clang or runtime failure.

    Design: a NEW file rather than growing test_codegen.ml (already ~6400
    lines) further — this is a distinct, corpus-scanning concern (walk a
    directory, shell out to an external verifier tool, aggregate a
    failure list) rather than a single-source-snippet IR assertion like the
    rest of test_codegen.ml's tests. Wired into the EXISTING `run_codegen.exe`
    runner (not a new dune test/`.exe`) per the task brief: `Test_codegen.
    codegen_suites` appends `Test_ir_verify.suites` at the end of its list,
    so `-e` semantics and the five-runner invocation recipe are unchanged —
    no sixth runner for callers to remember.

    Tool-availability policy (matches W2.0 / `test_helpers.ml`'s
    `setup_jit_runtime` doc comment): a skip is legitimate ONLY when no LLVM
    verifier tool (`opt` or `llvm-as`) is reachable on this machine at all —
    that is counted via `record_jit_skip` so it appears in the shared
    at_exit summary. Once a tool IS found, every other failure mode (the
    March compiler itself failing to emit IR, or the emitted IR failing
    verification) is a real, loud Alcotest failure — never a silent skip. *)

open Test_helpers

(** Locate `test/native/`. Tried in order:
    1. `test/native` relative to CWD — correct for BOTH mandated agent
       invocations: `dune runtest` (dune's CWD is the project root) and the
       direct-binary recipe `./_build/default/test/<t>.exe` (this project's
       CLAUDE.md requires running that from the project root too).
    2. [march_project_root]-relative, as a fallback for any other CWD —
       [march_project_root] derives the repo root from the test exe's own
       path (parent of its `_build` ancestor, verified by `dune-project`),
       so it resolves correctly no matter where the binary is invoked
       from; the CWD-relative lookup above is just the cheaper common
       case. *)
let native_dir () =
  let cwd_relative = "test/native" in
  if Sys.file_exists cwd_relative && Sys.is_directory cwd_relative then cwd_relative
  else Filename.concat (march_project_root ()) "test/native"

(* JS-target-only fixtures: test/dune only ever compiles these with
   `--target js` (producing a `.mjs`, never touching Llvm_emit at all — see
   bin/main.ml's JS-target branch, which returns before the LLVM/clang
   path). Compiling them natively (no `--target js`) still "succeeds" in the
   sense that --emit-llvm writes A .ll file, but that file declares externs
   using their raw JS-side names verbatim (e.g. `@node:path_dirname`,
   `@./foo.mjs_bar`), which contain characters ':' '.' '/' invalid in an
   LLVM identifier — a verifier/parse rejection under NATIVE emission that
   is not a real bug: these fixtures are never exercised as native IR by any
   existing test/dune rule, only as `.mjs`. Excluding them here mirrors
   actual usage instead of inventing a new "loud skip" for a scenario the
   corpus never puts them in.

   The exclusion is NOT silent (W2.0 policy: an invisible exclusion is
   indistinguishable from coverage). Two mechanisms keep it honest:
   1. The gate prints a one-line note at process exit naming every excluded
      fixture (see [note_exclusions]).
   2. A misclassification invariant ([assert_excluded_are_js_target_only]):
      every native compile-and-run rule in test/dune names its targets
      `native_<fixture>` — if that string ever appears for an excluded
      fixture, the `js_` prefix no longer implies JS-only and the exclusion
      would be hiding real native IR from the gate, so the gate FAILS
      telling the author to gate the fixture instead. *)
let is_js_only_fixture name =
  String.length name >= 3 && String.sub name 0 3 = "js_"

(** All `test/native/*.march` fixtures, partitioned into
    (gated, excluded-as-js-target-only); both sorted. *)
let list_native_fixtures_partitioned () =
  let dir = native_dir () in
  Sys.readdir dir
  |> Array.to_list
  |> List.filter (fun f -> Filename.check_suffix f ".march")
  |> List.sort String.compare
  |> List.partition (fun f ->
       not (is_js_only_fixture (Filename.remove_extension f)))

(** Print the exclusion list once, at process exit — the same mechanism the
    W2.0 skip ledger uses ([record_jit_skip]'s at_exit printer), so the note
    lands in the terminal AFTER alcotest's own summary; a mid-test print
    would be swallowed into alcotest's per-test capture log and never seen. *)
let exclusion_note_registered = ref false

let note_exclusions excluded =
  if excluded <> [] && not !exclusion_note_registered then begin
    exclusion_note_registered := true;
    at_exit (fun () ->
      Printf.printf
        "\n[ir-verify] excluded %d js_-prefixed fixture(s) from the LLVM IR \
         validity gate (JS-target-only per test/dune, never compiled natively): %s\n"
        (List.length excluded)
        (String.concat ", " (List.map Filename.remove_extension excluded));
      flush stdout)
  end

(** Misclassification invariant: an excluded fixture must genuinely be
    JS-target-only. If test/dune ever grows a native compile rule for one
    (target string "native_<fixture>", the convention every native
    compile-and-run rule in that file follows), the js_ name prefix no
    longer implies JS-only — fail loudly telling the author to gate it. *)
let assert_excluded_are_js_target_only excluded =
  let dune_path = Filename.concat (Filename.dirname (native_dir ())) "dune" in
  let dune_src = read_file_contents dune_path in
  if dune_src = "" then
    Alcotest.failf
      "ir-verify exclusion invariant: could not read %s to verify the js_ \
       exclusions are JS-target-only" dune_path;
  List.iter (fun f ->
    let base = Filename.remove_extension f in
    if ir_contains dune_src ("native_" ^ base) then
      Alcotest.failf
        "ir-verify exclusion invariant violated: test/native/%s is excluded \
         from the IR validity gate as JS-target-only (js_ prefix), but \
         test/dune contains a native compile rule for it (target \
         \"native_%s\") — it IS compiled natively, so its IR must be gated. \
         Remove it from the js_ exclusion in test/test_ir_verify.ml (or \
         rename the fixture if it is genuinely JS-only)."
        f base
  ) excluded

(* ── Step 2 (RED): hand-crafted invalid IR must be rejected ─────────────── *)

(** `add i64 %x, %f` where `%f` is a `double` — the brief's own example
    class ("add i64 %x, double 1.0"): a type mismatch the LL parser/verifier
    must reject. Written as a value-typed mismatch (rather than a literal
    `double 1.0`, which the LL PARSER itself already rejects before the
    verifier pass even runs) so this specifically exercises the case where
    a value of the wrong type flows into an `i64` operation — the general
    shape of the `coerce` catch-all bug class this gate defends against. *)
let hand_crafted_invalid_ir =
  String.concat "\n" [
    "define i64 @bad(i64 %x) {";
    "entry:";
    "  %f = fadd double 1.0, 2.0";
    "  %r = add i64 %x, %f";
    "  ret i64 %r";
    "}";
    "";
  ]

let hand_crafted_valid_ir =
  String.concat "\n" [
    "define i64 @good(i64 %x) {";
    "entry:";
    "  %r = add i64 %x, 2";
    "  ret i64 %r";
    "}";
    "";
  ]

let with_temp_ll contents f =
  let path = Filename.temp_file "march_ir_verify_red" ".ll" in
  let oc = open_out path in
  output_string oc contents;
  close_out oc;
  let result = (try `Ok (f path) with e -> `Exn e) in
  (try Sys.remove path with Sys_error _ -> ());
  match result with
  | `Ok r -> r
  | `Exn e -> raise e

(** RED: proves the verify helper actually detects invalid IR — a
    hand-crafted `.ll` with an i64/double type mismatch must be REJECTED. If
    this test doesn't fail on bad input, the corpus gate below would be
    vacuously green no matter what the compiler emits. *)
let test_verifier_rejects_invalid_ir () =
  match find_llvm_verifier_tool () with
  | `None ->
    record_jit_skip "no LLVM verifier tool (opt/llvm-as) on PATH or in brew --prefix llvm";
    Alcotest.skip ()
  | _ ->
    with_temp_ll hand_crafted_invalid_ir (fun path ->
      match verify_llvm_ir_file path with
      | `Ok ->
        Alcotest.fail
          "verify_llvm_ir_file accepted hand-crafted invalid IR (i64/double \
           mismatch) — the verifier gate would never detect a real emitter bug"
      | `Invalid _output -> ()  (* expected: rejected with a locatable error *)
      | `NoTool ->
        Alcotest.fail "find_llvm_verifier_tool found a tool but verify_llvm_ir_file did not use it")

(** Sanity converse: the verifier must ACCEPT well-typed IR (guards against a
    helper that rejects everything, which would make the RED test above a
    false positive for "detection" while actually just being permanently
    broken). *)
let test_verifier_accepts_valid_ir () =
  match find_llvm_verifier_tool () with
  | `None ->
    record_jit_skip "no LLVM verifier tool (opt/llvm-as) on PATH or in brew --prefix llvm";
    Alcotest.skip ()
  | _ ->
    with_temp_ll hand_crafted_valid_ir (fun path ->
      match verify_llvm_ir_file path with
      | `Ok -> ()
      | `Invalid output ->
        Alcotest.failf "verify_llvm_ir_file rejected well-typed IR:\n%s" output
      | `NoTool -> Alcotest.fail "unreachable: tool was found above")

(** Confinement: the recursive-delete helper backing the gate's temp-dir
    cleanup must defend itself — refuse "" and "/" outright, and refuse any
    existing path outside the system temp root, deleting NOTHING in each
    case. Verified with a sentinel file in a scratch dir under the CWD
    (assumed — true for both mandated invocation styles — not to be under
    $TMPDIR): the helper must raise AND the sentinel must survive. *)
let test_rm_rf_temp_dir_refuses_unconfined_paths () =
  let refused p =
    match rm_rf_temp_dir p with
    | () -> false            (* returned normally: did NOT refuse *)
    | exception _ -> true    (* raised (Alcotest failure): refused *)
  in
  Alcotest.(check bool) "refuses \"\"" true (refused "");
  Alcotest.(check bool) "refuses \"/\"" true (refused "/");
  (* An EXISTING directory outside the temp root: must refuse and leave its
     contents untouched. PID-suffixed to avoid concurrent-session clashes. *)
  let scratch =
    Filename.concat (Sys.getcwd ())
      (Printf.sprintf "_ir_verify_confinement_scratch.%d" (Unix.getpid ())) in
  (try Unix.mkdir scratch 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  let sentinel = Filename.concat scratch "sentinel.txt" in
  let oc = open_out sentinel in
  output_string oc "must survive rm_rf_temp_dir refusal";
  close_out oc;
  let refused_outside = refused scratch in
  let sentinel_survived = Sys.file_exists sentinel in
  (* Clean our scratch up with plain removes — NOT the helper under test. *)
  (try Sys.remove sentinel with Sys_error _ -> ());
  (try Unix.rmdir scratch with Unix.Unix_error _ -> ());
  Alcotest.(check bool) "refuses existing path outside temp root" true
    refused_outside;
  Alcotest.(check bool) "sentinel outside temp root survives the refusal" true
    sentinel_survived

(* ── Step 3/4: gate the real native/*.march corpus ───────────────────────
   One aggregated test case with per-file reporting (per the brief's
   preference): emits IR for every non-JS-only test/native/*.march fixture
   via `--emit-llvm`, verifies each, and collects ALL failures before
   asserting — so a run against the full corpus reports every bad fixture
   in one shot instead of stopping at the first. *)

type fixture_result =
  | Verified
  | EmitFailed of string * int * string   (* name, rc, compiler output *)
  | VerifyFailed of string * string       (* name, verifier output *)

let run_fixture main_exe name =
  let src = Filename.concat (native_dir ()) name in
  match emit_llvm_ir_to_file ~main_exe ~src () with
  | `Failed (rc, output) -> EmitFailed (name, rc, output)
    (* emit_llvm_ir_to_file cleans up its own temp dir on failure. *)
  | `Ok ll_path ->
    let result =
      match verify_llvm_ir_file ll_path with
      | `Ok -> Verified
      | `Invalid output -> VerifyFailed (name, output)
      | `NoTool -> Verified (* unreachable: caller already checked tool presence *)
    in
    (* Recursive cleanup: besides our .march copy and the emitted .ll, the
       compiler drops a .march/cas/vc/ verdict-cache tree in its CWD, so a
       flat remove + rmdir silently leaked one temp dir per fixture. *)
    rm_rf_temp_dir (Filename.dirname ll_path);
    result

(** GREEN on the real corpus: every test/native/*.march fixture (excluding
    JS-target-only ones — see [is_js_only_fixture]) emits verifier-clean
    LLVM IR. Aggregated: collects every failing fixture before reporting,
    rather than failing on the first. As of 2026-07-02 all 37 gated
    fixtures verify cleanly (see specs/todos.md — no findings filed for
    this task; if a future emitter change breaks one, this test will name
    it precisely instead of surfacing as an opaque clang/runtime failure). *)
let test_native_corpus_ir_is_verifier_clean () =
  match find_llvm_verifier_tool () with
  | `None ->
    record_jit_skip "no LLVM verifier tool (opt/llvm-as) on PATH or in brew --prefix llvm — IR validity gate SKIPPED for the whole native/*.march corpus";
    Alcotest.skip ()
  | _ ->
    let main_exe = find_main_exe () in
    let (fixtures, excluded) = list_native_fixtures_partitioned () in
    (* Loud exclusion note (terminal, at process exit) + misclassification
       invariant — an excluded fixture with a native dune rule FAILS here. *)
    note_exclusions excluded;
    assert_excluded_are_js_target_only excluded;
    Alcotest.(check bool) "at least one native fixture found to gate" true
      (List.length fixtures > 0);
    let results = List.map (run_fixture main_exe) fixtures in
    let emit_failures =
      List.filter_map (function
        | EmitFailed (name, rc, output) -> Some (name, rc, output)
        | _ -> None) results
    in
    let verify_failures =
      List.filter_map (function
        | VerifyFailed (name, output) -> Some (name, output)
        | _ -> None) results
    in
    if emit_failures <> [] || verify_failures <> [] then begin
      let buf = Buffer.create 1024 in
      Buffer.add_string buf
        (Printf.sprintf "\nLLVM IR validity gate: %d/%d fixtures failed (using %s; %d js_-only fixture(s) excluded: %s):\n"
           (List.length emit_failures + List.length verify_failures)
           (List.length fixtures) (llvm_verifier_tool_name ())
           (List.length excluded)
           (String.concat ", " (List.map Filename.remove_extension excluded)));
      List.iter (fun (name, rc, output) ->
        Buffer.add_string buf
          (Printf.sprintf "  [EMIT FAILED] %s (rc=%d):\n%s\n" name rc output))
        emit_failures;
      List.iter (fun (name, output) ->
        Buffer.add_string buf
          (Printf.sprintf "  [VERIFY FAILED] %s:\n%s\n" name output))
        verify_failures;
      Alcotest.fail (Buffer.contents buf)
    end

let suites =
  [
    ( "llvm_ir_validity_gate", [
        Alcotest.test_case "verifier rejects hand-crafted invalid IR (RED)" `Quick
          test_verifier_rejects_invalid_ir;
        Alcotest.test_case "verifier accepts hand-crafted valid IR" `Quick
          test_verifier_accepts_valid_ir;
        Alcotest.test_case "rm_rf_temp_dir refuses unconfined paths" `Quick
          test_rm_rf_temp_dir_refuses_unconfined_paths;
        Alcotest.test_case "native/*.march corpus emits verifier-clean LLVM IR (W2.1)" `Quick
          test_native_corpus_ir_is_verifier_clean;
      ] );
  ]
