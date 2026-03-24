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

let () =
  Alcotest.run "march_search" [
    "levenshtein",   levenshtein_tests;
    "name_search",   name_search_tests;
    "type_search",   type_search_tests;
    "doc_search",    doc_search_tests;
    "combined",      combined_search_tests;
    "json",          json_tests;
    "integration",   integration_tests;
  ]
