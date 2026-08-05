(* Tests for the contextual-escaping table parser (lib/ctxesc).

   The .tbl file at specs/security/html-contexts.tbl is the source of truth for
   ~H's escaping decisions; these tests pin the parser that reads it. See
   specs/security/README.md for the format and
   specs/plans/2026-08-05-contextual-autoescaping.md for the plan. *)

module C = March_ctxesc.Context
module P = March_ctxesc.Tbl_parse

(* The repo has no `astring`; substring checks use a local helper, matching the
   convention in test_compiler.ml. *)
let contains_sub s sub =
  let n = String.length s and m = String.length sub in
  let rec go i = i + m <= n && (String.sub s i m = sub || go (i + 1)) in
  m = 0 || go 0

let with_tbl body contents =
  let tmp = Filename.temp_file "ctxesc" ".tbl" in
  let oc = open_out tmp in
  output_string oc contents;
  close_out oc;
  let r = body tmp in
  Sys.remove tmp;
  r

let parse_ok contents =
  with_tbl (fun f -> P.parse_file f) contents |> function
  | Ok t -> t
  | Error e -> Alcotest.failf "expected parse to succeed, got: %s" e

let parse_err contents =
  with_tbl (fun f -> P.parse_file f) contents |> function
  | Ok _ -> Alcotest.fail "expected parse to fail, but it succeeded"
  | Error e -> e

(* ── Basic shape ──────────────────────────────────────────────────────── *)

let test_parses_a_minimal_transition () =
  let t =
    parse_ok
      "# a comment\n\n[transitions]\npcdata,*,*,* | lit:\"<\" |  | tagname,=,=,= |\n"
  in
  Alcotest.(check int) "one row" 1 (List.length t.P.transitions);
  let r = List.hd t.P.transitions in
  Alcotest.(check bool) "literal pattern" true (r.P.pat = P.PLit "<")

let test_parses_classification_sections () =
  let t =
    parse_ok
      "[tags]\nscript | script\n* | normal\n\n\
       [attrs]\non* | script\nhref | url\n* | normal\n\n[transitions]\n"
  in
  Alcotest.(check int) "two tag rules" 2 (List.length t.P.tags);
  Alcotest.(check int) "three attr rules" 3 (List.length t.P.attrs)

(* ── Patterns ─────────────────────────────────────────────────────────── *)

let pat_of src =
  let t = parse_ok ("[transitions]\npcdata,*,*,* | " ^ src ^ " |  | =,=,=,= |\n") in
  (List.hd t.P.transitions).P.pat

let test_pattern_vocabulary () =
  Alcotest.(check bool) "lit"   true (pat_of "lit:\"<!--\"" = P.PLit "<!--");
  Alcotest.(check bool) "ilit"  true (pat_of "ilit:\"</SCRIPT\"" = P.PILit "</script");
  Alcotest.(check bool) "interp" true (pat_of "interp" = P.PInterp);
  Alcotest.(check bool) "any"   true (pat_of "any" = P.PAny);
  Alcotest.(check bool) "name"  true (pat_of "name" = P.PName);
  Alcotest.(check bool) "tag"   true (pat_of "tag" = P.PTag);
  Alcotest.(check bool) "until" true (pat_of "until:\"-->\"" = P.PUntil "-->");
  (match pat_of "cls:[a-c]" with
   | P.PClass cs -> Alcotest.(check (list char)) "cls range" ['a'; 'b'; 'c'] cs
   | _ -> Alcotest.fail "expected PClass");
  (match pat_of "cls+:[ \\t]" with
   | P.PClassPlus cs -> Alcotest.(check (list char)) "cls+ escapes" [' '; '\t'] cs
   | _ -> Alcotest.fail "expected PClassPlus")

(* ── Context patterns ─────────────────────────────────────────────────── *)

let test_wildcard_and_unchanged_contexts () =
  let t =
    parse_ok
      "[transitions]\npcdata,*,*,* | any |  | tagname,=,=,double |\n"
  in
  let r = List.hd t.P.transitions in
  Alcotest.(check bool) "from state is concrete" true
    (r.P.from_pat.P.f_state = Some C.Pcdata);
  Alcotest.(check bool) "from element is wildcard" true
    (r.P.from_pat.P.f_element = None);
  Alcotest.(check bool) "succ state is set" true
    (r.P.succ.P.s_state = Some C.Tagname);
  Alcotest.(check bool) "succ element is unchanged" true
    (r.P.succ.P.s_element = None);
  Alcotest.(check bool) "succ delim is set" true
    (r.P.succ.P.s_delim = Some C.DlDouble)

let test_substitution_and_diagnostic_are_read () =
  let t =
    parse_ok
      "[transitions]\n\
       beforeattrvalue,*,*,* | interp | \"\\\"\" | attrvalue,=,=,doublesubst |\n\
       beforeattrname,*,*,* | interp |  | =,=,=,= | Cannot interpolate an attribute name\n"
  in
  match t.P.transitions with
  | [ subst_row; diag_row ] ->
    Alcotest.(check (option string)) "substitution" (Some "\"") subst_row.P.subst;
    Alcotest.(check (option string)) "no diagnostic" None subst_row.P.diag;
    Alcotest.(check (option string)) "diagnostic"
      (Some "Cannot interpolate an attribute name") diag_row.P.diag
  | _ -> Alcotest.fail "expected exactly two rows"

(* ── Rejection: a typo must never be silently dropped ─────────────────── *)

let test_rejects_unknown_state () =
  let e =
    parse_err "[transitions]\nnotastate,*,*,* | any |  | pcdata,=,=,= |\n"
  in
  Alcotest.(check bool) "names the bad token" true (contains_sub e "notastate");
  Alcotest.(check bool) "names the line" true (contains_sub e "line 2")

let test_rejects_unknown_pattern () =
  let e = parse_err "[transitions]\npcdata,*,*,* | regex:\".*\" |  | =,=,=,= |\n" in
  Alcotest.(check bool) "names the bad pattern" true (contains_sub e "regex")

let test_rejects_unknown_class_name () =
  let e = parse_err "[attrs]\nhref | notaclass\n" in
  Alcotest.(check bool) "names the bad class" true (contains_sub e "notaclass")

let test_rejects_wrong_field_count () =
  let e = parse_err "[transitions]\npcdata,*,*,* | any |  | =,=,=,=\n" in
  Alcotest.(check bool) "explains the arity" true (contains_sub e "5 fields")

let test_rejects_row_outside_a_section () =
  let e = parse_err "pcdata,*,*,* | any |  | =,=,=,= |\n" in
  Alcotest.(check bool) "mentions the section" true (contains_sub e "section")

(* ── The real table must load ─────────────────────────────────────────── *)

let test_shipped_table_parses () =
  (* Runners are invoked both from the repo root (scripts/run-tests.sh) and
     from _build/default/test (dune runtest), so try both. *)
  let candidates =
    [ "specs/security/html-contexts.tbl";
      "../../specs/security/html-contexts.tbl";
      "../../../specs/security/html-contexts.tbl" ] in
  let path =
    match List.find_opt Sys.file_exists candidates with
    | Some p -> p
    | None ->
      Alcotest.failf "shipped table not found (cwd %s; tried %s)" (Sys.getcwd ())
        (String.concat ", " candidates)
  in
  match P.parse_file path with
  | Error e -> Alcotest.failf "shipped table failed to parse: %s" e
  | Ok t ->
    Alcotest.(check bool) "has transitions" true (List.length t.P.transitions > 20);
    Alcotest.(check bool) "has tag rules" true (t.P.tags <> []);
    Alcotest.(check bool) "has attr rules" true (t.P.attrs <> []);
    (* Every state must be reachable as a source, or a row is dead. *)
    let sources =
      List.filter_map (fun r -> r.P.from_pat.P.f_state) t.P.transitions in
    List.iter
      (fun st ->
         Alcotest.(check bool)
           (Printf.sprintf "state %s appears as a source" (C.state_name st))
           true
           (List.mem st sources))
      C.all_states

let tests =
  [ ("ctxesc table parser",
     [ Alcotest.test_case "minimal transition" `Quick test_parses_a_minimal_transition;
       Alcotest.test_case "tags/attrs sections" `Quick test_parses_classification_sections;
       Alcotest.test_case "pattern vocabulary" `Quick test_pattern_vocabulary;
       Alcotest.test_case "wildcard and unchanged" `Quick test_wildcard_and_unchanged_contexts;
       Alcotest.test_case "substitution + diagnostic" `Quick test_substitution_and_diagnostic_are_read;
       Alcotest.test_case "rejects unknown state" `Quick test_rejects_unknown_state;
       Alcotest.test_case "rejects unknown pattern" `Quick test_rejects_unknown_pattern;
       Alcotest.test_case "rejects unknown class" `Quick test_rejects_unknown_class_name;
       Alcotest.test_case "rejects wrong field count" `Quick test_rejects_wrong_field_count;
       Alcotest.test_case "rejects row outside section" `Quick test_rejects_row_outside_a_section;
       Alcotest.test_case "shipped table parses" `Quick test_shipped_table_parses ]) ]
