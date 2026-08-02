(** Tests for the March search index (march_search library). *)

module Search = March_search.Search

(* ------------------------------------------------------------------ *)
(* Levenshtein distance                                                *)
(* ------------------------------------------------------------------ *)

let test_levenshtein_identical () =
  Alcotest.(check int) "identical strings" 0
    (Search.levenshtein "hello" "hello")

let test_levenshtein_empty () =
  Alcotest.(check int) "empty vs non-empty" 5
    (Search.levenshtein "" "hello");
  Alcotest.(check int) "non-empty vs empty" 3
    (Search.levenshtein "map" "")

let test_levenshtein_insertion () =
  Alcotest.(check int) "one insertion" 1
    (Search.levenshtein "map" "maps")

let test_levenshtein_substitution () =
  Alcotest.(check int) "one substitution" 1
    (Search.levenshtein "map" "cap")

let test_levenshtein_deletion () =
  Alcotest.(check int) "one deletion" 1
    (Search.levenshtein "maps" "map")

let test_levenshtein_kitten_sitting () =
  Alcotest.(check int) "kitten->sitting" 3
    (Search.levenshtein "kitten" "sitting")

(* ------------------------------------------------------------------ *)
(* Reference tracking (forge search --callers)                        *)
(* ------------------------------------------------------------------ *)

module TC = March_typecheck.Typecheck
module Ast = March_ast.Ast

(** Parse + desugar a source string into decls wrapped in a DMod, mirroring
    [Search.parse_file]'s handling of a real .march file. *)
let decls_of_source ~(file : string) (mod_name : string) (src : string) : Ast.decl list =
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <- { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = file };
  let m = March_parser.Parser.module_
      (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  let m = March_desugar.Desugar.desugar_module m in
  ignore mod_name;
  [Ast.DMod (m.Ast.mod_name, Ast.Public, m.Ast.mod_decls, Ast.dummy_span)]

let check_refs (files : (string * string * string) list) : TC.ref_record list =
  (* [files] is (file, mod_name, src) list. *)
  let all_decls = List.concat_map (fun (file, mod_name, src) ->
      decls_of_source ~file mod_name src) files in
  let synth : Ast.module_ =
    { mod_name = { txt = "__test__"; span = Ast.dummy_span }; mod_decls = all_decls } in
  let (_errors, _type_map, refs) = TC.check_module_with_refs synth in
  refs

let test_call_ref_same_module () =
  let refs = check_refs [
    ("a.march", "A", "mod A do\n  fn helper() do 1 end\n  fn main() do helper() end\nend\n");
  ] in
  let calls = List.filter (fun (r : TC.ref_record) -> r.ref_kind = `Call) refs in
  Alcotest.(check bool) "helper call recorded" true
    (List.exists (fun (r : TC.ref_record) ->
         r.callee = "A.helper" && r.caller = "A.main") calls)

let test_call_ref_cross_module () =
  let refs = check_refs [
    ("b.march", "B", "mod B do\n  fn util() do 1 end\nend\n");
    ("a.march", "A", "mod A do\n  fn main() do B.util() end\nend\n");
  ] in
  let calls = List.filter (fun (r : TC.ref_record) -> r.ref_kind = `Call) refs in
  Alcotest.(check bool) "cross-module B.util call recorded" true
    (List.exists (fun (r : TC.ref_record) ->
         r.callee = "B.util" && r.caller = "A.main") calls)

(** A public top-level `let` (a [DLet], not a [DFn]) must never be recorded as
    a [`Call] reference, even when it is referenced through call syntax
    (`B.some_const()`) from another module. [DMod]'s export step binds a
    public [DLet] into the outer [env.vars] under "Mod.name" the exact same
    way it binds a public [DFn] (see [new_names] in the [Ast.DMod] arm of
    [check_decl]), so a bare "does this dotted name resolve" check cannot
    distinguish them — only [qual_fn_names] (populated exclusively from
    [DFn]s/registry [ExFn]s) can. Call syntax is used here (rather than a
    bare `B.some_const` value reference) because a qualified name only ever
    becomes an [Ast.EVar] — the code path this task's hook lives on — via the
    `Mod.member(args)` call-normalization in [infer_expr]; a bare qualified
    VALUE reference parses as [Ast.EField] instead, a wholly separate
    (unhooked, out-of-scope) code path. *)
let test_qualified_let_const_not_call_ref () =
  let refs = check_refs [
    ("b.march", "B", "mod B do\n  let some_const = 42\nend\n");
    ("a.march", "A", "mod A do\n  fn main() do B.some_const() end\nend\n");
  ] in
  let calls = List.filter (fun (r : TC.ref_record) -> r.ref_kind = `Call) refs in
  Alcotest.(check bool) "B.some_const (a DLet, not a DFn) never recorded as Call" false
    (List.exists (fun (r : TC.ref_record) -> r.callee = "B.some_const") calls)

(** A qualified interface-method call (`Show2.show(x)`) must still be
    recorded as a [`Call] reference. [prebind_interface_decl] binds an
    interface method's dot-qualified name ("Iface.method") directly into
    [env.vars] — a THIRD source of qualified names, independent of both
    [Ast.DMod] exports and registry [ExFn] entries (the two sources
    [qual_fn_names] was originally populated from). Pins the fix that
    registers interface-method qualified names into [qual_fn_names] too, so
    the [DLet]-exclusion gate (see [test_qualified_let_const_not_call_ref])
    doesn't also swallow this genuine function call as a false negative. *)
let test_qualified_iface_method_call_ref () =
  let refs = check_refs [
    ("b.march", "B",
     "mod B do\n\
     \  interface Show2(a) do\n\
     \    fn show: a -> String\n\
     \  end\n\
     \  impl Show2(Int) do\n\
     \    fn show(x) do \"n\" end\n\
     \  end\n\
      end\n");
    ("a.march", "A", "mod A do\n  fn main() do Show2.show(5) end\nend\n");
  ] in
  let calls = List.filter (fun (r : TC.ref_record) -> r.ref_kind = `Call) refs in
  Alcotest.(check bool) "Show2.show interface-method call recorded" true
    (List.exists (fun (r : TC.ref_record) ->
         r.callee = "Show2.show" && r.caller = "A.main") calls)

let test_ctor_ref_recorded () =
  let refs = check_refs [
    ("a.march", "A",
     "mod A do\n  type Box = Empty | Full(Int)\n  fn main() do Full(1) end\nend\n");
  ] in
  let ctors = List.filter (fun (r : TC.ref_record) -> r.ref_kind = `Ctor) refs in
  Alcotest.(check bool) "Full ctor use recorded" true
    (List.exists (fun (r : TC.ref_record) ->
         r.callee = "A.Full" && r.caller = "A.main") ctors)

(** A cross-module QUALIFIED constructor use (`B.Full(1)`) must be recorded
    with callee = "B.Full" — exercising the [String.contains name.txt '.']
    stripping branch in the [ECon] hook, which extracts the bare ctor name
    ("Full") from the already-dotted [name.txt] ("B.Full") before
    re-qualifying with [ci.ci_module] ("B"). Without the strip, this would
    double-qualify to "B.B.Full". *)
let test_ctor_ref_qualified_cross_module () =
  let refs = check_refs [
    ("b.march", "B", "mod B do\n  type Box = Full(Int)\nend\n");
    ("a.march", "A", "mod A do\n  fn main() do B.Full(1) end\nend\n");
  ] in
  let ctors = List.filter (fun (r : TC.ref_record) -> r.ref_kind = `Ctor) refs in
  Alcotest.(check bool) "B.Full qualified ctor use recorded without double-qualification" true
    (List.exists (fun (r : TC.ref_record) ->
         r.callee = "B.Full" && r.caller = "A.main") ctors)

(** A qualified type annotation (`w: B.Widget`) must be recorded as a
    [`TypeRef] reference. Bare (unqualified) type annotations are an
    explicitly accepted out-of-scope gap for this task — see the
    [Ast.TyCon] hook in [surface_ty]. *)
let test_typeref_qualified_recorded () =
  let refs = check_refs [
    ("b.march", "B", "mod B do\n  type Widget = Widget(Int)\nend\n");
    ("a.march", "A", "mod A do\n  fn make(w: B.Widget) do w end\nend\n");
  ] in
  let tyrefs = List.filter (fun (r : TC.ref_record) -> r.ref_kind = `TypeRef) refs in
  Alcotest.(check bool) "B.Widget annotation recorded" true
    (List.exists (fun (r : TC.ref_record) ->
         r.callee = "B.Widget" && r.caller = "A.make") tyrefs)

(* ------------------------------------------------------------------ *)
(* Build a small in-memory index for search tests                     *)
(* ------------------------------------------------------------------ *)

let make_entry ?(module_name = "List") ?(kind = Search.Fn)
    ?(signature = "") ?(doc = None) ?(file = "stdlib/list.march")
    ?(line = 1) ?(params = []) ?(return_type = None) name =
  Search.{ name; module_name; kind; signature; doc; file; line; params; return_type }

let sample_index () : Search.index =
  Search.{
    version      = 1;
    generated_at = "2026-01-01T00:00:00Z";
    entries      = [
      make_entry "map"
        ~signature:"List.map(xs: List(a), f: fn(a) -> b) -> List(b)"
        ~doc:(Some "Apply a function to each element of a list.")
        ~params:[("xs", "List(a)"); ("f", "fn(a) -> b")]
        ~return_type:(Some "List(b)");

      make_entry "filter"
        ~signature:"List.filter(xs: List(a), pred: fn(a) -> Bool) -> List(a)"
        ~doc:(Some "Keep only elements satisfying a predicate.")
        ~params:[("xs", "List(a)"); ("pred", "fn(a) -> Bool")]
        ~return_type:(Some "List(a)");

      make_entry "fold_left"
        ~signature:"List.fold_left(xs: List(a), acc: b, f: fn(b, a) -> b) -> b"
        ~doc:(Some "Left fold over a list.")
        ~params:[("xs", "List(a)"); ("acc", "b"); ("f", "fn(b, a) -> b")]
        ~return_type:(Some "b");

      make_entry "length"
        ~signature:"List.length(xs: List(a)) -> Int"
        ~doc:(Some "Return the number of elements in a list.")
        ~params:[("xs", "List(a)")]
        ~return_type:(Some "Int");

      make_entry "split"
        ~module_name:"String"
        ~signature:"String.split(s: String, sep: String) -> List(String)"
        ~doc:(Some "Split a string by a separator.")
        ~params:[("s", "String"); ("sep", "String")]
        ~return_type:(Some "List(String)")
        ~file:"stdlib/string.march";

      make_entry "to_string"
        ~module_name:"Int"
        ~signature:"Int.to_string(n: Int) -> String"
        ~doc:(Some "Convert an integer to its decimal string representation.")
        ~params:[("n", "Int")]
        ~return_type:(Some "String")
        ~file:"stdlib/int.march";

      make_entry "Option"
        ~kind:Search.Type_
        ~signature:"Option"
        ~module_name:"";

      make_entry "Some"
        ~kind:Search.Constructor
        ~signature:"Some(a)"
        ~return_type:(Some "Option")
        ~module_name:"";

      make_entry "None"
        ~kind:Search.Constructor
        ~signature:"None"
        ~return_type:(Some "Option")
        ~module_name:"";
    ];
  }

(* ------------------------------------------------------------------ *)
(* Name search                                                         *)
(* ------------------------------------------------------------------ *)

let test_name_exact () =
  let idx = sample_index () in
  let results = Search.search_name idx "map" in
  let names = List.map (fun (e, _) -> e.Search.name) results in
  Alcotest.(check bool) "map found" true (List.mem "map" names)

let test_name_substring () =
  let idx = sample_index () in
  let results = Search.search_name idx "fold" in
  let names = List.map (fun (e, _) -> e.Search.name) results in
  Alcotest.(check bool) "fold_left found via substring" true
    (List.mem "fold_left" names)

let test_name_fuzzy () =
  let idx = sample_index () in
  (* "lenght" is one transposition away from "length" *)
  let results = Search.search_name idx "lenght" in
  let names = List.map (fun (e, _) -> e.Search.name) results in
  Alcotest.(check bool) "length found via fuzzy" true
    (List.mem "length" names)

let test_name_no_query () =
  let idx = sample_index () in
  let results = Search.search_name idx "" in
  Alcotest.(check int) "empty query returns all" (List.length idx.Search.entries)
    (List.length results)

let test_name_sorted_by_score () =
  let idx = sample_index () in
  let results = Search.search_name idx "map" in
  match results with
  | [] -> Alcotest.fail "expected at least one result"
  | (top, score) :: _ ->
    Alcotest.(check string) "best match is map" "map" top.Search.name;
    Alcotest.(check bool) "score is 1.0 for exact" true (score = 1.0)

(* ------------------------------------------------------------------ *)
(* Type signature search                                               *)
(* ------------------------------------------------------------------ *)

let test_type_search_return_type () =
  let idx = sample_index () in
  let results = Search.search_type idx "-> Int" in
  let names = List.map (fun (e, _) -> e.Search.name) results in
  Alcotest.(check bool) "length (-> Int) found" true (List.mem "length" names)

let test_type_search_param_type () =
  let idx = sample_index () in
  let results = Search.search_type idx "String" in
  let names = List.map (fun (e, _) -> e.Search.name) results in
  Alcotest.(check bool) "split (String) found" true (List.mem "split" names)

let test_type_search_empty_query () =
  let idx = sample_index () in
  let results = Search.search_type idx "" in
  Alcotest.(check int) "empty type query returns 0" 0 (List.length results)

(* ------------------------------------------------------------------ *)
(* Doc search                                                          *)
(* ------------------------------------------------------------------ *)

let test_doc_search_keyword () =
  let idx = sample_index () in
  let results = Search.search_docs idx "separator" in
  let names = List.map (fun (e, _) -> e.Search.name) results in
  Alcotest.(check bool) "split found by doc keyword" true (List.mem "split" names)

let test_doc_search_multi_word () =
  let idx = sample_index () in
  let results = Search.search_docs idx "each element" in
  let names = List.map (fun (e, _) -> e.Search.name) results in
  Alcotest.(check bool) "map found by doc keywords" true (List.mem "map" names)

let test_doc_search_no_doc_entries () =
  let idx = sample_index () in
  (* "Option" type entry has no doc — searching "option" should not find it *)
  let results = Search.search_docs idx "type definition" in
  let names = List.map (fun (e, _) -> e.Search.name) results in
  Alcotest.(check bool) "Option (no doc) not returned" false (List.mem "Option" names)

(* ------------------------------------------------------------------ *)
(* Combined search                                                     *)
(* ------------------------------------------------------------------ *)

let test_combined_name_and_type () =
  let idx = sample_index () in
  (* Name "split" AND type contains "String" *)
  let results = Search.search_combined idx ~name:"split" ~type_sig:"String" () in
  let names = List.map (fun (e, _) -> e.Search.name) results in
  Alcotest.(check bool) "combined: split with String type" true
    (List.mem "split" names)

let test_combined_no_query () =
  let idx = sample_index () in
  let results = Search.search_combined idx () in
  Alcotest.(check int) "no query returns all" (List.length idx.Search.entries)
    (List.length results)

let test_combined_restrictive () =
  let idx = sample_index () in
  (* "map" by name AND "-> Int" by type: map returns List(b), not Int *)
  let results = Search.search_combined idx ~name:"map" ~type_sig:"-> Int" () in
  let names = List.map (fun (e, _) -> e.Search.name) results in
  (* "map" returns List(b), so this combination should NOT return map *)
  Alcotest.(check bool) "restrictive combined filters out map" false
    (List.mem "map" names)

(* ------------------------------------------------------------------ *)
(* JSON serialization roundtrip                                        *)
(* ------------------------------------------------------------------ *)

let test_json_roundtrip () =
  let idx = sample_index () in
  let json = Search.index_to_json idx in
  let idx2 = Search.index_from_json json in
  Alcotest.(check int) "same number of entries after roundtrip"
    (List.length idx.Search.entries)
    (List.length idx2.Search.entries);
  Alcotest.(check int) "same version" idx.Search.version idx2.Search.version;
  (* Check first entry name survives roundtrip *)
  let first = List.hd idx.Search.entries in
  let first2 = List.hd idx2.Search.entries in
  Alcotest.(check string) "first entry name" first.Search.name first2.Search.name

let test_json_entry_fields () =
  let entry = make_entry "map"
    ~signature:"List.map(xs: List(a)) -> List(b)"
    ~doc:(Some "Apply fn to list.")
    ~params:[("xs", "List(a)")]
    ~return_type:(Some "List(b)") in
  let json = Search.entry_to_json entry in
  let entry2 = Search.entry_of_json json in
  Alcotest.(check string)  "name"        entry.Search.name entry2.Search.name;
  Alcotest.(check string)  "signature"   entry.Search.signature entry2.Search.signature;
  Alcotest.(check (option string)) "doc" entry.Search.doc entry2.Search.doc;
  Alcotest.(check (option string)) "return_type"
    entry.Search.return_type entry2.Search.return_type

(* ------------------------------------------------------------------ *)
(* Integration: build index from stdlib and search                     *)
(* ------------------------------------------------------------------ *)

let test_stdlib_index_nonempty () =
  let idx = Search.build_stdlib_index () in
  Alcotest.(check bool) "stdlib index has entries" true
    (List.length idx.Search.entries > 0)

let test_stdlib_search_map () =
  let idx = Search.build_stdlib_index () in
  let results = Search.search_name idx "map" in
  Alcotest.(check bool) "found map in stdlib" true
    (List.length results > 0)

let test_stdlib_search_list_module () =
  let idx = Search.build_stdlib_index () in
  let results = Search.search_name idx "map" in
  let list_results =
    List.filter (fun (e, _) -> e.Search.module_name = "List") results
  in
  Alcotest.(check bool) "List.map found in stdlib" true
    (List.length list_results > 0)

(* ------------------------------------------------------------------ *)
(* Test suite registration                                             *)
(* ------------------------------------------------------------------ *)

let levenshtein_tests = [
  "identical",       `Quick, test_levenshtein_identical;
  "empty",           `Quick, test_levenshtein_empty;
  "insertion",       `Quick, test_levenshtein_insertion;
  "substitution",    `Quick, test_levenshtein_substitution;
  "deletion",        `Quick, test_levenshtein_deletion;
  "kitten_sitting",  `Quick, test_levenshtein_kitten_sitting;
]

let name_search_tests = [
  "exact",            `Quick, test_name_exact;
  "substring",        `Quick, test_name_substring;
  "fuzzy",            `Quick, test_name_fuzzy;
  "empty_query",      `Quick, test_name_no_query;
  "sorted_by_score",  `Quick, test_name_sorted_by_score;
]

let type_search_tests = [
  "return_type",   `Quick, test_type_search_return_type;
  "param_type",    `Quick, test_type_search_param_type;
  "empty_query",   `Quick, test_type_search_empty_query;
]

let doc_search_tests = [
  "keyword",          `Quick, test_doc_search_keyword;
  "multi_word",       `Quick, test_doc_search_multi_word;
  "no_doc_entries",   `Quick, test_doc_search_no_doc_entries;
]

let combined_search_tests = [
  "name_and_type",    `Quick, test_combined_name_and_type;
  "no_query",         `Quick, test_combined_no_query;
  "restrictive",      `Quick, test_combined_restrictive;
]

let json_tests = [
  "roundtrip",        `Quick, test_json_roundtrip;
  "entry_fields",     `Quick, test_json_entry_fields;
]

let integration_tests = [
  "stdlib_nonempty",      `Slow, test_stdlib_index_nonempty;
  "stdlib_search_map",    `Slow, test_stdlib_search_map;
  "stdlib_list_module",   `Slow, test_stdlib_search_list_module;
]

let references_tests = [
  "same-module call",              `Quick, test_call_ref_same_module;
  "cross-module call",             `Quick, test_call_ref_cross_module;
  "qualified let-const excluded",  `Quick, test_qualified_let_const_not_call_ref;
  "qualified interface-method call recorded",
                                    `Quick, test_qualified_iface_method_call_ref;
  "ctor use recorded",             `Quick, test_ctor_ref_recorded;
  "qualified cross-module ctor use recorded",
                                    `Quick, test_ctor_ref_qualified_cross_module;
  "qualified type-annotation recorded",
                                    `Quick, test_typeref_qualified_recorded;
]

let () =
  Alcotest.run "march_search" [
    "levenshtein",   levenshtein_tests;
    "name_search",   name_search_tests;
    "type_search",   type_search_tests;
    "doc_search",    doc_search_tests;
    "combined",      combined_search_tests;
    "json",          json_tests;
    "integration",   integration_tests;
    "references",    references_tests;
  ]
