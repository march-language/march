(** TIR golden-snapshot tests (Wave 2 Task 4 / W2.2).

    Nothing in the test suite previously pinned the SHAPE of the TIR itself:
    every lowering/monomorphization/defunctionalization/Perceus (RC-insertion)
    regression so far was only ever caught (or missed) indirectly, by a
    program's runtime behavior changing. This module dumps the TIR for a
    small, hand-picked corpus at two canonical pipeline stages —
    "post-lower" (immediately after [Lower.lower_module], before mono) and
    "post-perceus" (after [Lower] -> [Mono] -> [Defun] -> [Perceus], i.e.
    after RC insertion/FBIP-reuse) — and diffs the pretty-printed text
    against a committed `.expected` file per corpus program per stage.

    WORKFLOW:
      - Run normally: `./_build/default/test/run_snapshots.exe -e` (or via
        `dune runtest`) diffs every corpus program's current TIR dump against
        its committed `test/snapshots/{lower,perceus}/<name>.expected` file.
        A mismatch fails with a unified-diff-style readable report (expected
        vs actual, line by line) naming the corpus program and stage.
      - Regenerate deliberately after an intentional TIR-shape change:
        `UPDATE_SNAPSHOTS=1 ./_build/default/test/run_snapshots.exe -e`
        overwrites every `.expected` file with the current dump and the run
        itself passes (regeneration, not verification). Re-run WITHOUT the
        env var afterwards to confirm the new baseline is now green, and
        `git diff test/snapshots/` to review exactly what changed before
        committing — a snapshot diff IS the code review artifact for any
        lowering/Perceus/Defun change.
      - The printer is [March_tir.Pp] ([string_of_fn_def] / [string_of_type_def]),
        chosen over [Tir.show_*] (the compact S-expression form used for
        content-hash fingerprinting) specifically because these files are
        meant to be READ by a human reviewing a refactor diff, not just
        compared byte-for-byte.
      - Every corpus program's [tm_fns]/[tm_types] is FILTERED to just the
        program's own top-level definitions before printing: [Lower]
        unconditionally injects synthetic Eq/Ord/Show/Hash impls for
        Int/Float/String/Bool/Unit into every module's [tm_fns] (see
        lower.ml's "Pre-populate _iface_methods with standard interface
        builtins" block, ~line 1949), and 3 builtin ADTs (Option/Result/List)
        into [tm_types] (lower.ml's [builtin_type_defs]) — unfiltered, EVERY
        snapshot would carry the same ~16 lines of prelude noise ahead of
        the 1-3 lines actually being pinned. The filter excludes any fn name
        beginning with one of the 4 known prelude interface-impl prefixes
        ("Eq$", "Ord$", "Show$", "Hash$") and the 3 known builtin type names
        ("Option", "Result", "List") — everything else (including
        compiler-generated lambda/join-point/apply names like
        "$lam2$apply$0", which DO pin real lowering/defun shape) is kept.
      - Determinism: [Lower.lower_module] and [Perceus.perceus] each reset
        their own fresh-name counter at entry (see [Lower.reset_counter]/
        [_lower_counter] and [Perceus._rc_fresh_ctr]), but
        [Defun.lambda_counter] is intentionally a cross-call counter (so a
        REPL session never reuses a UID) and does NOT reset itself — so a
        test process compiling multiple corpus programs back-to-back would
        make later programs' "$Clo_name$N"/"name$apply$N" suffixes depend on
        how many lambdas every earlier program in the run defined. Each
        dump call below resets it explicitly
        ([March_tir.Defun.set_lambda_counter 0]) before defunctionalizing,
        so every corpus program's snapshot is independent of run order —
        verified by the Step-4 determinism check (3 repeated runs, byte
        identical, including a run with a fresh isolated $HOME). *)

let update_mode = Sys.getenv_opt "UPDATE_SNAPSHOTS" = Some "1"

(* ── Corpus ─────────────────────────────────────────────────────────────
   Each entry is (snapshot_name, path to .march source under
   test/snapshots/src/, relative to the project root). Kept in this
   explicit list (rather than directory-scanned) so adding a corpus program
   is a deliberate two-step: write the .march file, then list it here —
   an accidental extra file in src/ does not silently start being snapshotted
   (or silently NOT being snapshotted) without a code change showing up in
   review. *)
let corpus = [
  "guard_match",                     "guard_match.march";
  "float_arms",                      "float_arms.march";
  "tuple_atom_string_arms",          "tuple_atom_string_arms.march";
  "no_wildcard_panic",               "no_wildcard_panic.march";
  "closure_hof",                     "closure_hof.march";
  "mixed_owned_borrowed_args",       "mixed_owned_borrowed_args.march";
  "cross_branch_consumption",        "cross_branch_consumption.march";
  "borrowed_field_escape",           "borrowed_field_escape.march";
  "scrutinee_borrowed_conservatism", "scrutinee_borrowed_conservatism.march";
  "mutual_tco",                      "mutual_tco.march";
  "fbip_dead_binding_reuse",         "fbip_dead_binding_reuse.march";
  "record_update",                   "record_update.march";
  "self_tco_loop",                   "self_tco_loop.march";
  "nested_generic_adt",              "nested_generic_adt.march";
  "nested_cons_ctor_heap",           "nested_cons_ctor_heap.march";
  "interp_string_operand_rc",        "interp_string_operand_rc.march";
  "unboxed_aggregate",               "unboxed_aggregate.march";
  "borrowed_scrutinee_field_read",   "borrowed_scrutinee_field_read.march";
]

(* ── Path resolution ────────────────────────────────────────────────────
   Mirrors test_helpers.ml's find_main_exe/march_project_root pattern: works
   both under `dune runtest` (CWD = project root) and the direct-binary
   invocation `./_build/default/test/run_snapshots.exe` (CWD wherever the
   caller happens to be, per this project's agent-safe recipe). *)
let project_root () =
  let cwd_relative = "test/snapshots" in
  if Sys.file_exists cwd_relative && Sys.is_directory cwd_relative then "."
  else Test_helpers.march_project_root ()

let snapshots_dir () = Filename.concat (project_root ()) "test/snapshots"

let src_path name =
  Filename.concat (Filename.concat (snapshots_dir ()) "src") name

let expected_path stage name =
  Filename.concat (Filename.concat (snapshots_dir ()) stage) (name ^ ".expected")

let read_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let b = Bytes.create n in
  really_input ic b 0 n;
  close_in ic;
  Bytes.to_string b

let write_file path contents =
  let oc = open_out_bin path in
  output_string oc contents;
  close_out oc

(* ── Filtering: strip prelude/builtin noise, see module doc comment ──── *)

let prelude_iface_prefixes = ["Eq$"; "Ord$"; "Show$"; "Hash$"]
let builtin_type_names = ["Option"; "Result"; "List"]

let has_prefix p s =
  String.length s >= String.length p && String.sub s 0 (String.length p) = p

let is_prelude_fn (fn : March_tir.Tir.fn_def) =
  List.exists (fun p -> has_prefix p fn.March_tir.Tir.fn_name) prelude_iface_prefixes

let is_builtin_type (td : March_tir.Tir.type_def) =
  match td with
  | March_tir.Tir.TDVariant (n, _) -> List.mem n builtin_type_names
  | March_tir.Tir.TDRecord (n, _) -> List.mem n builtin_type_names
  | March_tir.Tir.TDClosure (n, _) -> List.mem n builtin_type_names

let user_fns (m : March_tir.Tir.tir_module) =
  List.filter (fun f -> not (is_prelude_fn f)) m.March_tir.Tir.tm_fns

let user_types (m : March_tir.Tir.tir_module) =
  List.filter (fun t -> not (is_builtin_type t)) m.March_tir.Tir.tm_types

(* ── Rendering: pp.ml's readable printer, sorted by name for a stable,
   diffable layout independent of internal list-build order. ─────────── *)

let render_module (m : March_tir.Tir.tir_module) =
  let types = user_types m in
  let fns =
    List.sort (fun (a : March_tir.Tir.fn_def) b -> String.compare a.fn_name b.fn_name)
      (user_fns m)
  in
  let buf = Buffer.create 1024 in
  Buffer.add_string buf (Printf.sprintf "-- types (%d) --\n" (List.length types));
  List.iter (fun t -> Buffer.add_string buf (March_tir.Pp.string_of_type_def t); Buffer.add_char buf '\n')
    types;
  Buffer.add_string buf (Printf.sprintf "-- fns (%d) --\n" (List.length fns));
  List.iter (fun (f : March_tir.Tir.fn_def) ->
    Buffer.add_string buf (Printf.sprintf "## %s\n" f.March_tir.Tir.fn_name);
    Buffer.add_string buf (March_tir.Pp.string_of_fn_def f);
    Buffer.add_string buf "\n\n"
  ) fns;
  Buffer.contents buf

(* ── Pipeline entry points ──────────────────────────────────────────────
   Same entry points test_helpers.ml's lower_module_typed/mono_module use;
   post-perceus composes Lower -> Mono -> Defun -> Perceus, mirroring
   test_helpers.ml's own emit_session_ir chain (the accepted precedent for
   this minimal 4-pass sequence in test code) rather than bin/main.ml's full
   pipeline, which also threads the opt_enabled-gated Fusion/Known_call/
   Beta_adt/Join_points/Simplify passes — deliberately excluded here so the
   snapshot pins core lowering/RC/FBIP behavior independent of optimizer
   on/off state. *)

let dump_post_lower src =
  March_tir.Defun.set_lambda_counter 0;
  render_module (Test_helpers.lower_module_typed src)

let dump_post_perceus src =
  March_tir.Defun.set_lambda_counter 0;
  let tir = Test_helpers.mono_module src in
  let tir = March_tir.Defun.defunctionalize tir in
  let tir = March_tir.Perceus.perceus tir in
  render_module tir

(* ── Diffing ────────────────────────────────────────────────────────────
   A minimal line-oriented "expected vs actual" report: not a true LCS
   diff, but for these small (<20-line source, correspondingly small TIR)
   corpus programs a line-by-line pairing is exactly as readable and much
   simpler than a full diff algorithm. *)

let readable_diff ~expected ~actual =
  let split s = String.split_on_char '\n' s in
  let exp_lines = Array.of_list (split expected) in
  let act_lines = Array.of_list (split actual) in
  let n = max (Array.length exp_lines) (Array.length act_lines) in
  let buf = Buffer.create 256 in
  for i = 0 to n - 1 do
    let e = if i < Array.length exp_lines then Some exp_lines.(i) else None in
    let a = if i < Array.length act_lines then Some act_lines.(i) else None in
    if e <> a then begin
      let show = function Some s -> s | None -> "<end of file>" in
      Buffer.add_string buf
        (Printf.sprintf "  line %d:\n    expected: %s\n    actual:   %s\n"
           (i + 1) (show e) (show a))
    end
  done;
  Buffer.contents buf

(* ── Test-case construction ─────────────────────────────────────────────
   One alcotest case per (corpus program, stage): a mismatch names exactly
   which program/stage regressed rather than failing an aggregate. In
   UPDATE_SNAPSHOTS=1 mode the same case regenerates the .expected file and
   always passes (Step 2's "second run green" requirement is then satisfied
   by re-running WITHOUT the env var). *)

let check_stage stage_dir_name dump_fn (name, src_file) () =
  let src = read_file (src_path src_file) in
  let actual = dump_fn src in
  let expected_file = expected_path stage_dir_name name in
  if update_mode then begin
    write_file expected_file actual
  end else begin
    if not (Sys.file_exists expected_file) then
      Alcotest.failf
        "snapshot missing: %s (run with UPDATE_SNAPSHOTS=1 to generate it)"
        expected_file
    else begin
      let expected = read_file expected_file in
      if expected <> actual then
        Alcotest.failf
          "TIR snapshot mismatch for %s (stage=%s):\n%s\n(regenerate with \
           UPDATE_SNAPSHOTS=1 if this change is intentional, then review \
           `git diff %s`)"
          name stage_dir_name (readable_diff ~expected ~actual) expected_file
    end
  end

let lower_cases =
  List.map (fun entry ->
    let (name, _) = entry in
    Alcotest.test_case (name ^ " (post-lower)") `Quick
      (check_stage "lower" dump_post_lower entry)
  ) corpus

let perceus_cases =
  List.map (fun entry ->
    let (name, _) = entry in
    Alcotest.test_case (name ^ " (post-perceus)") `Quick
      (check_stage "perceus" dump_post_perceus entry)
  ) corpus

(* ── Determinism canary ─────────────────────────────────────────────────
   Runs each stage TWICE in the same process (independent of alcotest's own
   ordering/repetition) and asserts byte-identical output — a fast in-
   process proxy for the Step-4 "run the whole suite 3x" determinism check,
   catching a counter-reset regression immediately rather than only via an
   external repeated-run diff. *)
let test_double_run_determinism () =
  List.iter (fun (name, src_file) ->
    let src = read_file (src_path src_file) in
    let l1 = dump_post_lower src and l2 = dump_post_lower src in
    Alcotest.(check bool) (name ^ " post-lower double-run stable") true (l1 = l2);
    let p1 = dump_post_perceus src and p2 = dump_post_perceus src in
    Alcotest.(check bool) (name ^ " post-perceus double-run stable") true (p1 = p2)
  ) corpus

let suites = [
  ("tir_snapshots_lower", lower_cases);
  ("tir_snapshots_perceus", perceus_cases);
  ("tir_snapshots_determinism", [
     Alcotest.test_case "dumps are stable across repeated in-process runs" `Quick
       test_double_run_determinism;
   ]);
]
