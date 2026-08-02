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

(** Fix round 1 regression: a qualified type used ONLY in an interface
    method signature — which has no enclosing function — must never be
    recorded with a [caller] borrowed from some unrelated function that
    happened to be checked earlier in the same module (see
    [with_no_caller]/the [`TyCon] hook's `caller <> ""` gate). Before the
    fix, `B.Widget` here was recorded twice: once with `caller = ""` (the
    lazy cross-module injection path) and once with `caller = "A.helper"`
    (the direct [DInterface] path, misattributed because [helper]'s body was
    the last thing checked before the interface). After the fix, no
    [`TypeRef] for `B.Widget` is recorded at all — a missing reference is
    honest; a wrong caller is not. *)
let test_typeref_interface_sig_no_stale_caller () =
  let refs = check_refs [
    ("b.march", "B", "mod B do\n  type Widget = Widget(Int)\nend\n");
    ("a.march", "A",
     "mod A do\n\
     \  fn helper() do 1 end\n\
     \  interface Foo(a) do\n\
     \    fn conv: a -> B.Widget\n\
     \  end\n\
      end\n");
  ] in
  let tyrefs = List.filter (fun (r : TC.ref_record) ->
      r.ref_kind = `TypeRef && r.callee = "B.Widget") refs in
  Alcotest.(check bool)
    "B.Widget in interface signature never attributed to A.helper" false
    (List.exists (fun (r : TC.ref_record) -> r.caller = "A.helper") tyrefs);
  Alcotest.(check int) "B.Widget in interface signature not recorded at all"
    0 (List.length tyrefs)

(** Final-review Critical 2: a Call reference in a top-level `let` body (a
    [DLet], never checked via [check_fn]) must never be attributed to
    whatever [DFn] happened to be checked last in module order. Before the
    fix, [env.current_decl] was set-and-never-restored by [check_fn], so it
    leaked across the rest of the module; this reference would have been
    wrongly recorded with caller = "A.unrelated" (the last fn checked before
    the `let`). *)
let test_call_ref_toplevel_let_no_stale_caller () =
  let refs = check_refs [
    ("a.march", "A",
     "mod A do\n\
     \  fn unrelated() do 1 end\n\
     \  fn helper() do 2 end\n\
     \  let x = helper()\n\
      end\n");
  ] in
  let calls = List.filter (fun (r : TC.ref_record) ->
      r.ref_kind = `Call && r.callee = "A.helper") refs in
  Alcotest.(check bool) "A.helper call from the top-level `let` never attributed to A.unrelated"
    false (List.exists (fun (r : TC.ref_record) -> r.caller = "A.unrelated") calls)

(** Same scenario, but cross-file/cross-module: a `let` in a SEPARATE module
    checked after another module's `fn` must not inherit that other
    module's function as its caller. This is the reviewer's reproduction of
    the leak crossing file boundaries in multi-file compilation. *)
let test_call_ref_toplevel_let_no_stale_caller_cross_module () =
  let refs = check_refs [
    ("a.march", "A", "mod A do\n  fn unrelated() do 1 end\nend\n");
    ("b.march", "B",
     "mod B do\n  fn helper() do 2 end\n  let x = helper()\nend\n");
  ] in
  let calls = List.filter (fun (r : TC.ref_record) ->
      r.ref_kind = `Call && r.callee = "B.helper") refs in
  Alcotest.(check bool)
    "B.helper call from B's top-level `let` never attributed to A.unrelated"
    false (List.exists (fun (r : TC.ref_record) -> r.caller = "A.unrelated") calls)

(** A recursive call from inside a top-level `fn` checked AFTER an unrelated
    `let` must still resolve to its own fn as caller (not "" and not the
    unrelated `let`'s non-existent caller) — proving the [check_fn]
    save/restore doesn't overcorrect into losing legitimate attribution. *)
let test_call_ref_fn_after_let_still_attributed () =
  let refs = check_refs [
    ("a.march", "A",
     "mod A do\n\
     \  let y = 1\n\
     \  fn helper() do 1 end\n\
     \  fn main() do helper() end\n\
      end\n");
  ] in
  let calls = List.filter (fun (r : TC.ref_record) -> r.ref_kind = `Call) refs in
  Alcotest.(check bool) "A.main -> A.helper still recorded after an unrelated `let`" true
    (List.exists (fun (r : TC.ref_record) ->
         r.callee = "A.helper" && r.caller = "A.main") calls)

(** Final-review Important 4: a function PARAMETER that shadows a top-level
    fn name must resolve as the local parameter, not the shadowed top-level
    fn — a bare-name Call reference here would otherwise be a textual match,
    not a resolution-based one (this feature's core precision constraint). *)
let test_call_ref_param_shadow_not_recorded_as_toplevel_call () =
  let refs = check_refs [
    ("a.march", "A",
     "mod A do\n\
     \  fn helper() do 1 end\n\
     \  fn wrapper(helper) do helper() end\n\
      end\n");
  ] in
  let calls = List.filter (fun (r : TC.ref_record) ->
      r.ref_kind = `Call && r.callee = "A.helper") refs in
  Alcotest.(check int)
    "wrapper's shadowed local `helper` param is never recorded as a call to A.helper"
    0 (List.length calls)

(** Companion positive case: with NO shadowing, the exact same call shape
    must still be recorded — pinning that the [bind_var]/[local_fns] fix
    only suppresses the shadowed case, not genuine top-level recursive/
    self-referential calls. *)
let test_call_ref_no_shadow_still_recorded () =
  let refs = check_refs [
    ("a.march", "A",
     "mod A do\n\
     \  fn helper() do 1 end\n\
     \  fn wrapper() do helper() end\n\
      end\n");
  ] in
  let calls = List.filter (fun (r : TC.ref_record) ->
      r.ref_kind = `Call && r.callee = "A.helper") refs in
  Alcotest.(check bool) "wrapper -> A.helper recorded when there is no shadowing" true
    (List.exists (fun (r : TC.ref_record) -> r.caller = "A.wrapper") calls)

(** Final-review Important 3: no recorded callee/caller should ever start
    with a literal "." (the tell for an empty-module ad-hoc
    `modname ^ "." ^ name` concatenation, e.g. a prelude ctor whose
    [ci_module] is "") nor contain the "__stdlib__" synthetic wrapper module
    name (see [Search.synthetic_module_name]) that [typecheck_decls]'s
    outer synthetic module can leak into a reference recorded from
    [prelude.march]'s deliberately-unwrapped top-level decls. Cheap,
    high-value regression guard the reviewer suggested directly. *)
let test_no_leading_dot_or_synthetic_module_in_refs () =
  let refs = check_refs [
    ("a.march", "A",
     "mod A do\n\
     \  fn main() do Some(1) end\n\
      end\n");
  ] in
  List.iter (fun (r : TC.ref_record) ->
      Alcotest.(check bool)
        (Printf.sprintf "callee %S does not start with '.'" r.callee)
        false (String.length r.callee > 0 && r.callee.[0] = '.');
      Alcotest.(check bool)
        (Printf.sprintf "caller %S does not start with '.'" r.caller)
        false (String.length r.caller > 0 && r.caller.[0] = '.');
      let contains_stdlib s =
        let needle = "__stdlib__" in
        let nlen = String.length needle in
        let slen = String.length s in
        let rec go i = i + nlen <= slen &&
                       (String.sub s i nlen = needle || go (i + 1)) in
        slen >= nlen && go 0
      in
      Alcotest.(check bool) "callee has no __stdlib__ leak" false (contains_stdlib r.callee);
      Alcotest.(check bool) "caller has no __stdlib__ leak" false (contains_stdlib r.caller)
    ) refs

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
    references   = Hashtbl.create 0;
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

      (* Structural-search fixture: a single-arg `String -> Int` entry,
         deliberately the reverse of `to_string`'s `Int -> String`, so
         order-sensitivity can be tested without ambiguity. *)
      make_entry "to_int"
        ~module_name:"String"
        ~signature:"String.to_int(s: String) -> Int"
        ~doc:(Some "Parse a string as an integer.")
        ~params:[("s", "String")]
        ~return_type:(Some "Int")
        ~file:"stdlib/string.march";

      (* Structural-search fixture: an `Int -> Int` entry, so a query of
         `Int -> Int` has a genuine positive match to find (and the old
         substring matcher would have also wrongly matched `to_string` /
         `to_int` here, since both signatures contain the substring "Int"). *)
      make_entry "negate"
        ~module_name:"Int"
        ~signature:"Int.negate(n: Int) -> Int"
        ~doc:(Some "Negate an integer.")
        ~params:[("n", "Int")]
        ~return_type:(Some "Int")
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

let test_type_search_return_only_mode () =
  let idx = sample_index () in
  (* Leading `->` = return-type-only query, matches at any arity. *)
  let results = Search.search_type idx "-> Int" in
  let names = List.map (fun (e, _) -> e.Search.name) results in
  Alcotest.(check bool) "length (-> Int) found" true (List.mem "length" names)

(** Was [test_type_search_param_type]: a bare `"String"` query used to match
    [split] via substring matching against its printed signature. Under
    structural matching a bare type with no `->` is a zero-argument query
    (see [test_type_search_zero_arg_not_return_only]), so this is rewritten
    as the full structural query that actually describes [split]'s
    signature: two `String` params returning `List(String)`. *)
let test_type_search_multi_arg_match () =
  let idx = sample_index () in
  let results = Search.search_type idx "String -> String -> List(String)" in
  let names = List.map (fun (e, _) -> e.Search.name) results in
  Alcotest.(check bool) "split (String, String) -> List(String) found" true
    (List.mem "split" names)

let test_type_search_empty_query () =
  let idx = sample_index () in
  let results = Search.search_type idx "" in
  Alcotest.(check int) "empty type query returns 0" 0 (List.length results)

let test_type_search_order_sensitive () =
  let idx = sample_index () in
  (* `to_string` is `Int -> String`; `to_int` is the reverse, `String ->
     Int`. Querying one order must not match the other. *)
  let results = Search.search_type idx "String -> Int" in
  let names = List.map (fun (e, _) -> e.Search.name) results in
  Alcotest.(check bool) "to_string (Int -> String) not matched by reversed query"
    false (List.mem "to_string" names);
  Alcotest.(check bool) "to_int (String -> Int) matched" true
    (List.mem "to_int" names)

let test_type_search_arity_discriminates () =
  let idx = sample_index () in
  (* A 1-arg query must not match a 2-arg entry, even if the types appear. *)
  let results = Search.search_type idx "String -> Int" in
  List.iter (fun (e, _) ->
      Alcotest.(check int) ("arity 1 for " ^ e.Search.name)
        1 (List.length e.Search.params))
    results

let test_type_search_no_substring_bleed () =
  let idx = sample_index () in
  (* `Int` must not match `Int64` / `Integer` / `List(Int)`, and the
     substring "Int" appearing in `Int.to_string`'s module prefix or
     `to_int`'s param must not leak either. *)
  let results = Search.search_type idx "Int -> Int" in
  Alcotest.(check bool) "negate (Int -> Int) matched" true
    (List.mem "negate" (List.map (fun (e, _) -> e.Search.name) results));
  List.iter (fun (e, _) ->
      Alcotest.(check bool) ("exact param type for " ^ e.Search.name)
        true (List.for_all (fun (_, t) -> t = "Int") e.Search.params))
    results

let test_type_search_unparseable_is_error () =
  match Search.parse_type_query "List( ->" with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "expected a parse error for a malformed type query"

let test_type_search_zero_arg_not_return_only () =
  (* A zero-argument query is QFull ([], _), NOT QReturnOnly — it must match
     only zero-argument entries, unlike the `-> T` form. *)
  match Search.parse_type_query "Int" with
  | Ok (Search.QFull ([], _)) -> ()
  | Ok (Search.QReturnOnly _) ->
    Alcotest.fail "bare `Int` must not be treated as a return-only query"
  | Ok _ -> Alcotest.fail "expected QFull ([], _) for a bare type"
  | Error m -> Alcotest.fail ("unexpected parse error: " ^ m)

(* ------------------------------------------------------------------ *)
(* Type parsing (standalone `ty_eof` start symbol)                     *)
(* ------------------------------------------------------------------ *)

let parse_ty_str (s : string) : March_ast.Ast.ty =
  let lexbuf = Lexing.from_string s in
  March_parser.Parser.ty_eof
    (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf

let test_parse_ty_eof_arrow () =
  match parse_ty_str "List(a) -> Int" with
  | March_ast.Ast.TyArrow (_, _) -> ()
  | _ -> Alcotest.fail "expected TyArrow for `List(a) -> Int`"

let test_pp_ast_ty_canonicalizes_vars () =
  (* `xs` and `acc` must print as `a` and `b`, matching make_ty_printer. *)
  let ty = parse_ty_str "List(xs) -> acc" in
  Alcotest.(check string) "author var names normalized"
    "List(a) -> b" (Search.pp_ast_ty ty)

(* ------------------------------------------------------------------ *)
(* AST-fallback signature building: shared renaming table              *)
(* ------------------------------------------------------------------ *)

(** Builds an index entirely through the AST-fallback path (an empty
    [type_map] — [Search.build_index]'s own default — means
    [resolve_fn_types] never finds a typechecker entry and falls straight
    through to the AST-rendered params/return pair unchanged). This exercises
    the real [collect_entries] call sites, not [pp_ast_ty] directly: a
    single-call recursive printer would already get "List(a) -> b" right
    (see [test_pp_ast_ty_canonicalizes_vars] above) even with no persistent
    table at all, because one recursive descent naturally shares its own
    local closure. What's only exercised by going through [build_index] is
    whether *two separate calls* through the same closure — here,
    [extract_fn_params]'s per-param renders and the later
    [Option.map ast_pp fn.fn_ret_ty] — agree on the letter for a variable
    that appears in both a parameter and the return type. *)
let test_ast_fallback_signature_shares_var_table () =
  let file = "fallback_share.march" in
  let decls =
    decls_of_source ~file "Test"
      "mod Test do\n  fn const_(x : a, y : b) : b do y end\nend\n"
  in
  let idx = Search.build_index [decls] ~source_files:[file] () in
  let entry =
    match List.find_opt (fun (e : Search.entry) -> e.name = "const_") idx.entries with
    | Some e -> e
    | None -> Alcotest.fail "const_ entry not found in AST-fallback index"
  in
  Alcotest.(check (list (pair string string))) "params: x renamed a, y renamed b"
    [("x", "a"); ("y", "b")] entry.params;
  Alcotest.(check (option string))
    "return type reuses y's letter (b), not a fresh table's a"
    (Some "b") entry.return_type

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
  (* Name "split" AND type is exactly (String, String) -> List(String) *)
  let results =
    Search.search_combined idx ~name:"split"
      ~type_sig:"String -> String -> List(String)" ()
  in
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

(** Final-review Important 3, exercised against the REAL stdlib build (the
    [check_refs] unit-test helper always wraps decls in a [DMod], so it can
    never reproduce the [prelude.march]-unwrapping leak path — only
    [Search.build_stdlib_index]'s real [typecheck_decls] call, which uses the
    actual "__stdlib__" synthetic wrapper module, can). No recorded
    callee/caller may start with "." or contain "__stdlib__". *)
let test_stdlib_refs_no_synthetic_module_leak () =
  let idx = Search.build_stdlib_index () in
  let contains_stdlib s =
    let needle = "__stdlib__" in
    let nlen = String.length needle in
    let slen = String.length s in
    let rec go i = i + nlen <= slen &&
                   (String.sub s i nlen = needle || go (i + 1)) in
    slen >= nlen && go 0
  in
  let bad = ref [] in
  Hashtbl.iter (fun callee entries ->
      if (String.length callee > 0 && callee.[0] = '.') || contains_stdlib callee then
        bad := ("callee:" ^ callee) :: !bad;
      List.iter (fun (e : Search.ref_entry) ->
          if (String.length e.caller > 0 && e.caller.[0] = '.') || contains_stdlib e.caller then
            bad := ("caller:" ^ e.caller) :: !bad
        ) entries
    ) idx.Search.references;
  Alcotest.(check (list string)) "no leading-dot or __stdlib__ leaks in stdlib references"
    [] (List.sort_uniq String.compare !bad)

let test_stdlib_search_list_module () =
  let idx = Search.build_stdlib_index () in
  let results = Search.search_name idx "map" in
  let list_results =
    List.filter (fun (e, _) -> e.Search.module_name = "List") results
  in
  Alcotest.(check bool) "List.map found in stdlib" true
    (List.length list_results > 0)

let test_index_references_roundtrip () =
  let refs : Search.ref_entry list = [
    { Search.callee = "A.helper"; caller = "A.main"; kind = "call"; file = "a.march"; line = 3 };
  ] in
  let idx = Search.{ (sample_index ()) with references = Search.references_of_list refs } in
  let json = Search.index_to_json idx in
  let idx2 = Search.index_from_json json in
  let looked_up = Search.callers_of idx2 "A.helper" in
  Alcotest.(check int) "one caller round-tripped" 1 (List.length looked_up)

let test_index_from_json_missing_references () =
  (* Old cache files predate the "references" key entirely. *)
  let idx = sample_index () in
  let json_without_refs = Search.index_to_json idx in
  (* index_to_json always includes "references" now; simulate an old cache by
     stripping the key so index_from_json's tolerance is actually exercised. *)
  let j = Yojson.Basic.from_string json_without_refs in
  let stripped = match j with
    | `Assoc kvs -> `Assoc (List.filter (fun (k, _) -> k <> "references") kvs)
    | other -> other
  in
  let idx2 = Search.index_from_json (Yojson.Basic.to_string stripped) in
  Alcotest.(check int) "missing references key yields empty table"
    0 (List.length (Search.callers_of idx2 "anything"))

let test_search_callers_bare_name_merges_modules () =
  let idx = Search.{
    (sample_index ()) with
    references = Search.references_of_list [
      { Search.callee = "A.helper"; caller = "A.main"; kind = "call"; file = "a.march"; line = 1 };
      { Search.callee = "B.helper"; caller = "B.main"; kind = "call"; file = "b.march"; line = 2 };
    ];
    entries = [
      make_entry "helper" ~module_name:"A";
      make_entry "helper" ~module_name:"B";
    ];
  } in
  let callers = Search.search_callers idx "helper" in
  let callers_names = List.map (fun (r : Search.ref_entry) -> r.caller) callers in
  Alcotest.(check int) "bare name merges both modules' callers" 2 (List.length callers);
  Alcotest.(check bool) "A.main present" true (List.mem "A.main" callers_names);
  Alcotest.(check bool) "B.main present" true (List.mem "B.main" callers_names)

(** Final-review Important 7: a type and a same-named constructor (the
    common `type Foo = Foo(...)` newtype pattern — ~80 occurrences in the
    real stdlib per the reviewer) are TWO separate [entries] that qualify to
    the same name. Before deduping the candidate list, [search_callers]
    called [callers_of] once per entry, so every reference to that one
    qualified name was double-counted in the output. *)
let test_search_callers_dedupes_type_and_ctor_same_name () =
  let idx = Search.{
    (sample_index ()) with
    references = Search.references_of_list [
      { Search.callee = "A.Widget"; caller = "A.main"; kind = "call"; file = "a.march"; line = 1 };
    ];
    entries = [
      make_entry "Widget" ~module_name:"A" ~kind:Search.Type_;
      make_entry "Widget" ~module_name:"A" ~kind:Search.Constructor;
    ];
  } in
  let callers = Search.search_callers idx "Widget" in
  Alcotest.(check int) "one reference to A.Widget is reported once, not twice"
    1 (List.length callers)

(** Regression guard for the class of bug on record in project memory
    (`project_ambiguous_ctor_current_module.md`): two modules that share a
    bare constructor name at different tags miscompiled because
    [lookup_ctor] didn't prefer the current module. This proves
    reference-tracking inherits that same current-module preference rather
    than reintroducing the bug at the reference layer — [Y.main]'s bare
    [Active] must resolve (and be recorded) as [Y.Active], never as the
    same-named [X.Active] from the other module. *)
let test_ambiguous_ctor_ref_prefers_current_module () =
  let refs = check_refs [
    ("x.march", "X", "mod X do\n  type Status = Active | Done\nend\n");
    ("y.march", "Y",
     "mod Y do\n  type Status = Active | Done\n  fn main() do Active end\nend\n");
  ] in
  let ctors = List.filter (fun (r : TC.ref_record) -> r.ref_kind = `Ctor) refs in
  Alcotest.(check bool) "Y.main's Active resolves to Y.Active, not X.Active" true
    (List.exists (fun (r : TC.ref_record) ->
         r.callee = "Y.Active" && r.caller = "Y.main") ctors);
  Alcotest.(check bool) "no false X.Active reference from Y.main" false
    (List.exists (fun (r : TC.ref_record) ->
         r.callee = "X.Active" && r.caller = "Y.main") ctors)

(** An unreferenced declaration must resolve to an empty caller list, not an
    error — consistent with the "no results" UX elsewhere in [forge search]. *)
let test_no_references_is_empty_not_error () =
  let refs = check_refs [
    ("a.march", "A", "mod A do\n  fn unused() do 1 end\n  fn main() do 2 end\nend\n");
  ] in
  let tbl = Search.references_of_list
      (List.map (fun (r : TC.ref_record) ->
           { Search.callee = r.callee; caller = r.caller;
             kind = Search.ref_kind_to_string r.ref_kind;
             file = r.ref_file; line = r.ref_line })
          refs) in
  Alcotest.(check int) "unused fn has zero recorded callers" 0
    (List.length (Search.callers_of { (sample_index ()) with Search.references = tbl } "A.unused"))

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
  "return_only_mode",       `Quick, test_type_search_return_only_mode;
  "multi_arg_match",        `Quick, test_type_search_multi_arg_match;
  "empty_query",            `Quick, test_type_search_empty_query;
  "order_sensitive",        `Quick, test_type_search_order_sensitive;
  "arity_discriminates",    `Quick, test_type_search_arity_discriminates;
  "no_substring_bleed",     `Quick, test_type_search_no_substring_bleed;
  "unparseable_is_error",   `Quick, test_type_search_unparseable_is_error;
  "zero_arg_not_return_only", `Quick, test_type_search_zero_arg_not_return_only;
]

let type_parsing_tests = [
  "ty_eof arrow",                `Quick, test_parse_ty_eof_arrow;
  "pp_ast_ty canonicalizes vars", `Quick, test_pp_ast_ty_canonicalizes_vars;
  "AST-fallback signature shares var table across params/return",
                                  `Quick, test_ast_fallback_signature_shares_var_table;
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
  "stdlib refs: no synthetic-module leak",
                           `Slow, test_stdlib_refs_no_synthetic_module_leak;
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
  "interface-signature type-ref has no stale caller",
                                    `Quick, test_typeref_interface_sig_no_stale_caller;
  "index references roundtrip",    `Quick, test_index_references_roundtrip;
  "index_from_json tolerates missing references key",
                                    `Quick, test_index_from_json_missing_references;
  "search_callers merges bare-name matches across modules",
                                    `Quick, test_search_callers_bare_name_merges_modules;
  "search_callers dedupes type+ctor same-name candidates",
                                    `Quick, test_search_callers_dedupes_type_and_ctor_same_name;
  "ambiguous ctor ref prefers current module",
                                    `Quick, test_ambiguous_ctor_ref_prefers_current_module;
  "no references is empty not error",
                                    `Quick, test_no_references_is_empty_not_error;
  "toplevel let: no stale caller from a prior unrelated fn",
                                    `Quick, test_call_ref_toplevel_let_no_stale_caller;
  "toplevel let: no stale caller across module/file boundary",
                                    `Quick, test_call_ref_toplevel_let_no_stale_caller_cross_module;
  "fn checked after an unrelated let still gets its own caller",
                                    `Quick, test_call_ref_fn_after_let_still_attributed;
  "param shadowing a top-level fn name is not recorded as a call",
                                    `Quick, test_call_ref_param_shadow_not_recorded_as_toplevel_call;
  "no shadowing: call still recorded",
                                    `Quick, test_call_ref_no_shadow_still_recorded;
  "no leading-dot or __stdlib__ leak in recorded refs",
                                    `Quick, test_no_leading_dot_or_synthetic_module_in_refs;
]

let () =
  Alcotest.run "march_search" [
    "levenshtein",   levenshtein_tests;
    "name_search",   name_search_tests;
    "type_search",   type_search_tests;
    "type_parsing",  type_parsing_tests;
    "doc_search",    doc_search_tests;
    "combined",      combined_search_tests;
    "json",          json_tests;
    "integration",   integration_tests;
    "references",    references_tests;
  ]
