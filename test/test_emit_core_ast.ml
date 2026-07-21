(** Golden test for `--emit-core-ast` (Task 3 of the emit-core-ast plan,
    specs/plans/2026-07-20-emit-core-ast-a0.md).

    This is a subprocess-based test modeled on [test_oracle.ml]'s idiom
    (locate the built `march` binary via MARCH_BIN / a couple of relative
    fallback paths, resolve MARCH_ROOT the same way) because the thing under
    test is the CLI binary's `--emit-core-ast` output, produced in
    [bin/main.ml] (an executable, not a library function) — so exercising
    the real binary end-to-end is the point, not re-deriving the
    parse/desugar/typecheck/verdict pipeline inline via library calls.

    Each fixture in [emit_core_ast/fixtures/*.expected.json] pins the EXACT
    stdout bytes `march --emit-core-ast <corpus file>` produced at the time
    the fixture was captured, for one of four representative
    `specs/lang/types/{accept,reject}/*.march` corpus programs (referenced
    in place — the .march source is NOT copied into this test's fixtures
    directory):

      - [t01_literals.march]        (accept) — a minimal accept case:
        literals (Int/Bool/String), `let` bindings, builtin calls.
      - [t07_generic_option_two_types.march] (accept) — an accept case
        touching a generic ADT (`type Box(a) = Full(a) | Vacant`),
        constructor application, and a `match` over variant patterns,
        instantiated at two different type arguments (Int, String).
      - [t01_int_vs_string.march]   (reject) — a reject case: a type
        mismatch (`Int` vs `String` at `++`) that produces diagnostics
        AND still emits its (pre-typecheck) desugared module tree.
      - [t70_letq_type_annotation.march] (reject) — a genuinely FATAL parse
        error (a `let?` binding with a type annotation, which the parser
        rejects outright rather than recovering from). This exercises the
        dedicated `emit_core_ast_parse_failure` short-circuit in
        [bin/main.ml] (no `Ast.module_` is ever produced), which emits
        `"module":null` instead of a desugared tree — the one case in the
        whole 170-file corpus that hits this path.

    The march process is always invoked with the corpus file path spelled
    RELATIVE to the project root, with the project root as the subprocess's
    cwd — never an absolute path. `--emit-core-ast`'s AST serializer embeds
    the as-given filename verbatim in every node's `"span":{"file":...}`, so
    an absolute path would bake this checkout's local filesystem location
    into the checked-in fixture and make it diff-fail on every other
    machine/CI worker. The relative-path + fixed-cwd invocation is what
    makes the fixture byte-for-byte portable.

    Regenerating a fixture after a DELIBERATE format change (e.g. a
    `format_version` bump, or a new AST node needing a new JSON shape):
    rebuild the compiler, rerun the invocation below for the affected corpus
    file with stdout redirected to the fixture path, and review the diff
    before committing — never hand-edit a fixture, and never silence a
    failing comparison by regenerating without reading what changed. *)

(* ------------------------------------------------------------------ *)
(* Locate march binary and project root (same idiom as test_oracle.ml)  *)
(* ------------------------------------------------------------------ *)

let realpath p =
  try Unix.realpath p
  with _ ->
    if Filename.is_relative p
    then Filename.concat (Sys.getcwd ()) p
    else p

let march_abs =
  let raw =
    match Sys.getenv_opt "MARCH_BIN" with
    | Some p -> p
    | None ->
      let candidates = [
        "_build/default/bin/main.exe";
        "../_build/default/bin/main.exe";
      ] in
      (match List.find_opt Sys.file_exists candidates with
       | Some p -> p
       | None ->
         Printf.eprintf "Cannot find march binary. Set MARCH_BIN env var.\n%!";
         exit 2)
  in
  realpath raw

let project_root =
  let has_dune_project d = Sys.file_exists (Filename.concat d "dune-project") in
  let from_env =
    match Sys.getenv_opt "MARCH_ROOT" with
    | Some p when has_dune_project p -> Some p
    | _ -> None
  in
  match from_env with
  | Some p -> p
  | None ->
    let rec up n d = if n = 0 then d else up (n - 1) (Filename.dirname d) in
    let found =
      List.find_opt has_dune_project
        (List.map (fun n -> up n march_abs) [4; 3; 5; 2])
    in
    (match found with
     | Some d -> d
     | None   -> Sys.getcwd ())

(* ------------------------------------------------------------------ *)
(* Subprocess runner: run march --emit-core-ast <rel_path>, cwd =        *)
(* project_root, capture stdout and exit code.                          *)
(* ------------------------------------------------------------------ *)

let read_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let buf = Bytes.create n in
  really_input ic buf 0 n;
  close_in ic;
  Bytes.to_string buf

(* Run march --emit-core-ast <rel_corpus_path> with cwd = project_root,
   capturing stdout to a temp file (stderr discarded) and the exit code. *)
let run_emit_core_ast rel_corpus_path =
  let q = Filename.quote in
  let tmp_out = Filename.temp_file "march_emit_core_ast" ".stdout" in
  let shell_cmd =
    Printf.sprintf "cd %s && %s --emit-core-ast %s > %s 2>/dev/null"
      (q project_root) (q march_abs) (q rel_corpus_path) (q tmp_out)
  in
  let exit_code = Sys.command shell_cmd in
  (* Sys.command on a `sh -c` invocation returns the raw wait-status-derived
     exit code for a normal exit (0-255); `--emit-core-ast` only ever exits 0
     or 1 (accept/reject), never via signal, so no WIFSIGNALED handling is
     needed here (unlike test_oracle.ml's general-purpose runner). *)
  let output = read_file tmp_out in
  (try Sys.remove tmp_out with _ -> ());
  (output, exit_code)

(* ------------------------------------------------------------------ *)
(* Fixture cases: (corpus file relative to project root, fixture path    *)
(* relative to this test's own directory, expected exit code)           *)
(* ------------------------------------------------------------------ *)

let fixtures_dir = Filename.concat (Filename.dirname Sys.argv.(0)) "emit_core_ast/fixtures"

(* Fall back to a path relative to project_root when running via `dune
   exec`/`dune test`, where Sys.argv.(0)'s directory is the sandboxed build
   dir for THIS executable (test/), which does contain emit_core_ast/ as a
   sibling directory since it's a dep of this test stanza — see test/dune. *)
let fixture_path name =
  let p1 = Filename.concat fixtures_dir name in
  if Sys.file_exists p1 then p1
  else Filename.concat project_root (Filename.concat "test/emit_core_ast/fixtures" name)

type case = {
  corpus_rel : string;      (* .march corpus file, relative to project_root *)
  fixture_name : string;    (* fixture file basename *)
  expected_exit : int;      (* 0 = accept, 1 = reject *)
  label : string;
}

let cases = [
  { corpus_rel = "specs/lang/types/accept/t01_literals.march";
    fixture_name = "t01_literals.expected.json";
    expected_exit = 0;
    label = "accept: literals + let bindings (t01_literals)" };
  { corpus_rel = "specs/lang/types/accept/t07_generic_option_two_types.march";
    fixture_name = "t07_generic_option_two_types.expected.json";
    expected_exit = 0;
    label = "accept: generic ADT ctor/match at two type args (t07_generic_option_two_types)" };
  { corpus_rel = "specs/lang/types/reject/t01_int_vs_string.march";
    fixture_name = "t01_int_vs_string.expected.json";
    expected_exit = 1;
    label = "reject: Int/String type mismatch (t01_int_vs_string)" };
  { corpus_rel = "specs/lang/types/reject/t70_letq_type_annotation.march";
    fixture_name = "t70_letq_type_annotation.expected.json";
    expected_exit = 1;
    label = "reject: fatal parse error, module is null (t70_letq_type_annotation)" };
]

(* v2 sanity: the envelope must be version 2 and carry annotations+witnesses.
   This is a lightweight structural check (independent of the byte-for-byte
   fixture comparison above) so a future accidental downgrade to v1 — or a
   regression that silently drops the resolved_ty/schemes tables — is caught
   with an explicit, readable assertion rather than only via an opaque full-
   string diff. *)
let assert_v2 (produced : string) =
  let has s =
    let hl = String.length produced and nl = String.length s in
    let rec go i = i + nl <= hl && (String.sub produced i nl = s || go (i+1)) in
    nl = 0 || go 0
  in
  Alcotest.(check bool) "format_version 2" true (has "\"format_version\":2" || has "\"format_version\": 2");
  Alcotest.(check bool) "has resolved_ty" true (has "resolved_ty");
  Alcotest.(check bool) "has schemes" true (has "schemes")

let test_case_matches_fixture case () =
  let expected = read_file (fixture_path case.fixture_name) in
  let (actual, exit_code) = run_emit_core_ast case.corpus_rel in
  Alcotest.(check int)
    (Printf.sprintf "%s: exit code" case.label)
    case.expected_exit exit_code;
  Alcotest.(check string)
    (Printf.sprintf "%s: --emit-core-ast stdout matches golden fixture %s"
       case.label case.fixture_name)
    expected actual;
  if case.fixture_name = "t01_literals.expected.json" then assert_v2 actual

let suite =
  List.map
    (fun case -> Alcotest.test_case case.label `Quick (test_case_matches_fixture case))
    cases

let () = Alcotest.run "march-emit-core-ast-golden" [ ("emit_core_ast", suite) ]
