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
(* Canonical metavar-ID renumbering.                                     *)
(*
   Type-variable IDs are allocated from a single global counter (see
   lib/dump/ast_json.ml and bin/main.ml's schemes/instantiations
   emission) that carries no semantic meaning on its own -- only WHICH
   occurrences share the same ID matters. That counter's absolute values
   drift whenever anything upstream of --emit-core-ast allocates a
   different number of metavariables (e.g. a stdlib change), and may
   also differ across platforms. Comparing raw fixture bytes against
   that counter's current values is what made t01_literals and
   t07_generic_option_two_types fail on main independent of any real
   content change -- the drift is pre-existing, not caused by this
   branch.

   Verified against the serializer (lib/dump/ast_json.ml's TVar case and
   bin/main.ml's schemes_json/insts_json construction) that "id" and
   "ids" appear in EXACTLY these two JSON shapes and nowhere else in the
   emitted document:
     - {"kind":"TVar","id":N}
     - "ids":[N,N,...]              (in schemes[] and instantiations[])

   [canonicalize] walks the document left-to-right and renumbers every
   ID found in one of those two shapes: the first distinct raw ID seen
   becomes canonical 0, the next new raw ID becomes 1, etc.; every later
   occurrence of an already-seen raw ID is rewritten to that same
   canonical number. Applying this identically to both the produced
   output and the expected fixture, then comparing the canonical forms
   byte-for-byte, keeps the comparison exact about structure and ID
   SHARING (if two occurrences that used to share an ID diverge, or vice
   versa, the canonical forms differ and the test fails) while making
   the absolute numbering -- which carries no information -- irrelevant.
   This is deliberately NOT erasure: distinct IDs still become distinct
   canonical numbers, so sharing patterns are still checked exactly. *)
let canonicalize (s : string) : string =
  let n = String.length s in
  let buf = Buffer.create n in
  let table : (string, int) Hashtbl.t = Hashtbl.create 16 in
  let next = ref 0 in
  let canon raw =
    match Hashtbl.find_opt table raw with
    | Some c -> c
    | None ->
      let c = !next in
      Hashtbl.add table raw c;
      incr next;
      c
  in
  let is_digit c = c >= '0' && c <= '9' in
  let tvar_marker = "\"kind\":\"TVar\",\"id\":" in
  let tvar_len = String.length tvar_marker in
  let ids_marker = "\"ids\":[" in
  let ids_len = String.length ids_marker in
  let matches marker marker_len i =
    i + marker_len <= n && String.sub s i marker_len = marker
  in
  let i = ref 0 in
  while !i < n do
    if matches tvar_marker tvar_len !i then begin
      Buffer.add_string buf tvar_marker;
      i := !i + tvar_len;
      let start = !i in
      while !i < n && is_digit s.[!i] do incr i done;
      let raw = String.sub s start (!i - start) in
      Buffer.add_string buf (string_of_int (canon raw))
    end else if matches ids_marker ids_len !i then begin
      Buffer.add_string buf ids_marker;
      i := !i + ids_len;
      let continue_ = ref true in
      while !continue_ do
        let start = !i in
        while !i < n && is_digit s.[!i] do incr i done;
        if !i > start then begin
          let raw = String.sub s start (!i - start) in
          Buffer.add_string buf (string_of_int (canon raw))
        end;
        if !i < n && s.[!i] = ',' then begin
          Buffer.add_char buf ',';
          incr i
        end else
          continue_ := false
      done
      (* closing ']' is left for the outer loop to copy verbatim *)
    end else begin
      Buffer.add_char buf s.[!i];
      incr i
    end
  done;
  let result = Buffer.contents buf in
  (* Cheap hardening for the whitespace-free-JSON assumption above: the only
     shape this function treats specially is `"kind":"TVar","id":N` (matched
     as one fixed marker string with no whitespace between the key and its
     value). If the emitter ever inserted whitespace, or a NEW node/field
     also spelled its key "id" outside that exact `"kind":"TVar",` prefix,
     the digit-scan above would silently fail to canonicalize it and this
     function would degrade to (partial) identity -- which fails safe today
     (the byte comparison just fails loudly instead of silently passing),
     but is worth flagging explicitly rather than relying on that as an
     accident. So: every "id": occurrence in the OUTPUT must be immediately
     preceded by the `"kind":"TVar",` marker; anything else means this
     compact-JSON assumption no longer holds and canonicalize needs a look. *)
  let id_marker = "\"id\":" in
  let id_len = String.length id_marker in
  let kind_prefix = "\"kind\":\"TVar\"," in
  let kind_len = String.length kind_prefix in
  let rlen = String.length result in
  let j = ref 0 in
  while !j + id_len <= rlen do
    if String.sub result !j id_len = id_marker then begin
      if not (!j >= kind_len && String.sub result (!j - kind_len) kind_len = kind_prefix)
      then
        failwith
          (Printf.sprintf
             "canonicalize: found \"id\": at offset %d not immediately \
              preceded by \"kind\":\"TVar\", -- canonicalize assumes \
              whitespace-free JSON where \"id\" only ever appears as part \
              of that exact TVar shape; if the emitter's output format \
              changed, canonicalize (and this check) need updating."
             !j);
      j := !j + id_len
    end else incr j
  done;
  result

(* Replace the `module_caps` array's contents with a fixed placeholder, on
   both sides of the comparison.

   `module_caps` is a WHOLE-PROGRAM table: for these corpus files (none of
   which define a capability-bearing user module) it is just a snapshot of
   every stdlib module's declared `needs` — currently ~95 entries, the large
   majority of each fixture's bytes. That snapshot legitimately changes
   whenever anyone edits a stdlib module's `needs`, adds a stdlib module, or
   removes one — none of which has anything to do with the per-file AST these
   fixtures exist to pin. Left in the byte comparison it made three fixtures
   fail the moment unrelated stdlib commits landed on main.

   The emitter deliberately emits the FULL table (a missing entry would
   silently disable the Lean checker's Check 4 — a false accept), so the fix
   is here, not in the emitter: drop `module_caps` from the per-file byte
   comparison. Its structure and content are covered separately and precisely
   by `test_module_caps_and_v3`, which asserts the exact
   `{"module":"Store","needs":["IO.FileRead"]}` shape for a user module plus
   `format_version` 3. Applied to BOTH sides, so it is robust to a future
   regeneration re-introducing the key into a fixture. *)
let strip_module_caps (s : string) : string =
  let marker = "\"module_caps\":[" in
  let mlen = String.length marker in
  match
    (let n = String.length s in
     let rec find i = if i + mlen > n then None
       else if String.sub s i mlen = marker then Some i else find (i + 1)
     in find 0)
  with
  | None -> s  (* no module_caps (e.g. a hand-built string) — leave untouched *)
  | Some start ->
    (* find the matching close ']' — module_caps entries contain no nested
       arrays in the `needs` position beyond one level, so track bracket depth
       from the opening '[' the marker ends on. *)
    let n = String.length s in
    let depth = ref 0 in
    let i = ref (start + mlen - 1) in  (* the '[' of the marker *)
    let stop = ref (-1) in
    while !stop < 0 && !i < n do
      (match s.[!i] with
       | '[' -> incr depth
       | ']' -> decr depth; if !depth = 0 then stop := !i
       | _ -> ());
      incr i
    done;
    if !stop < 0 then s
    else
      String.sub s 0 start
      ^ "\"module_caps\":[<stripped>]"
      ^ String.sub s (!stop + 1) (n - !stop - 1)

(* The normalisation applied to both sides of every fixture comparison:
   canonical metavar-ID renumbering, then module_caps stripping. *)
let normalize_for_compare (s : string) : string =
  strip_module_caps (canonicalize s)

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

(* v3 sanity: the envelope must be version 3 and carry annotations+witnesses.
   This is a lightweight structural check (independent of the byte-for-byte
   fixture comparison above) so a future accidental downgrade to v1/v2 — or a
   regression that silently drops the resolved_ty/schemes tables — is caught
   with an explicit, readable assertion rather than only via an opaque full-
   string diff. *)
let assert_v3 (produced : string) =
  let has s =
    let hl = String.length produced and nl = String.length s in
    let rec go i = i + nl <= hl && (String.sub produced i nl = s || go (i+1)) in
    nl = 0 || go 0
  in
  Alcotest.(check bool) "format_version 3" true (has "\"format_version\":3" || has "\"format_version\": 3");
  Alcotest.(check bool) "has resolved_ty" true (has "resolved_ty");
  Alcotest.(check bool) "has schemes" true (has "schemes")

(* A3: the envelope must carry module_caps for the Lean checker's Check 4
   (transitive `use` coverage), and must declare format_version 3. This
   exercises a synthetic one-module source (not a fixture) rather than the
   byte-for-byte golden fixtures above, so it needs its own subprocess
   plumbing: write the source to a scratch .march file under project_root
   (so it can be passed to run_emit_core_ast as a project-relative path,
   matching this file's cwd-fixed subprocess idiom), run --emit-core-ast on
   it, and check the resulting JSON for the expected substrings. *)
let emit_core_ast_of_source source =
  let tmp = Filename.temp_file ~temp_dir:project_root "march_a3_module_caps_" ".march" in
  Fun.protect
    ~finally:(fun () -> try Sys.remove tmp with _ -> ())
    (fun () ->
      let oc = open_out tmp in
      output_string oc source;
      close_out oc;
      let rel = Filename.basename tmp in
      let (output, _exit_code) = run_emit_core_ast rel in
      output)

(* Same free-standing substring search assert_v3 above already uses inline;
   factored out here since this test needs it multiple times. *)
let has_substring haystack needle =
  let hl = String.length haystack and nl = String.length needle in
  let rec go i = i + nl <= hl && (String.sub haystack i nl = needle || go (i + 1)) in
  nl = 0 || go 0

let assert_contains produced needle =
  Alcotest.(check bool)
    (Printf.sprintf "output contains %s" needle) true (has_substring produced needle)

let test_module_caps_and_v3 () =
  (* module_caps is populated only when a DMod is checked as a NESTED
     sub-module (typecheck.ml:8736) -- confirmed empirically: a bare
     top-level `mod Store do ... end` (the brief's original Step 1 example)
     never appears in module_caps, because the file's own entry module is
     the thing being checked, not a sub-module of anything. This mirrors
     the real corpus shape module_caps is meant to serve (t39: `Main` uses
     the stdlib module `Vault`, and `Vault` -- not `Main` -- is what shows
     up in module_caps). So `Store` is nested inside a wrapper `Outer`
     module here to actually exercise that path. *)
  let json = emit_core_ast_of_source
    {|mod Outer do
  mod Store do
    needs IO.FileRead

    fn load(cap : Cap(IO.FileRead), path : String) : String do
      let _ = cap
      path
    end
  end

  fn main() do
    ()
  end
end|}
  in
  (* format_version is inserted as a raw (unquoted) JSON value, same as the
     existing "2" literal it replaces -- see assert_v3 above and
     lib/dump/dump.ml's json_obj, which does not quote already-encoded
     values. *)
  assert_contains json "\"format_version\":3";
  assert_contains json "\"module_caps\"";
  (* Store declared `needs IO.FileRead`, so it must appear with that cap.
     Assert the joined literal exactly as the emitter formats it (compact,
     no spaces -- see lib/dump/dump.ml's json_obj/json_list), not just the
     two substrings independently: `IO.FileRead` also appears elsewhere in
     the emitted document (inside the `module` tree's DNeeds node), so
     checking "module":"Store" and "IO.FileRead" as separate substrings
     would still pass even if module_caps regressed to emitting an empty
     `needs` array for Store. *)
  assert_contains json "{\"module\":\"Store\",\"needs\":[\"IO.FileRead\"]}"

let test_case_matches_fixture case () =
  let expected = read_file (fixture_path case.fixture_name) in
  let (actual, exit_code) = run_emit_core_ast case.corpus_rel in
  Alcotest.(check int)
    (Printf.sprintf "%s: exit code" case.label)
    case.expected_exit exit_code;
  Alcotest.(check string)
    (Printf.sprintf
       "%s: --emit-core-ast stdout matches golden fixture %s (metavar IDs \
        compared via canonical renumbering, module_caps stripped — see \
        normalize_for_compare above)"
       case.label case.fixture_name)
    (normalize_for_compare expected) (normalize_for_compare actual);
  if case.fixture_name = "t01_literals.expected.json" then assert_v3 actual

let suite =
  List.map
    (fun case -> Alcotest.test_case case.label `Quick (test_case_matches_fixture case))
    cases
  @ [ Alcotest.test_case
        "module_caps present + format_version 3 (A3)" `Quick test_module_caps_and_v3 ]

let () = Alcotest.run "march-emit-core-ast-golden" [ ("emit_core_ast", suite) ]
