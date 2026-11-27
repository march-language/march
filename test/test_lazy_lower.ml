(** Lazy lowering of stdlib fn bodies ([Lower.lower_module ~lazy_bodies]):
    the stubs it leaves, the shared worklist ([Dce_pre_mono.walk]) and the
    prune's tripwire on a stub.

    The lowering cases build a program in process whose "stdlib" modules are
    parsed under file names registered as stdlib files, then lower it eagerly
    and lazily: a body lazy lowering lowers must be the very TIR eager
    lowering gives it.  specs/progress/2026-11-26-lazy-stdlib-lowering.md *)

open March_tir

(* ── Hand-built TIR ────────────────────────────────────────────────────── *)

let v name ty : Tir.var = { v_name = name; v_ty = ty; v_lin = Tir.Unr }
let int_fn = Tir.TFn ([], Tir.TInt)

let fn name body : Tir.fn_def =
  { fn_name = name; fn_params = []; fn_ret_ty = Tir.TInt;
    fn_body = body; fn_kind = Tir.FnNormal }

let call name = Tir.EApp (v name int_fn, [])
let lit n = Tir.EAtom (Tir.ALit (March_ast.Ast.LitInt n))
let stub name = fn name (Tir.EApp (v Tir_names.unlowered_marker int_fn, []))

let module_of fns : Tir.tir_module =
  { tm_name = "T"; tm_fns = fns; tm_types = []; tm_externs = [];
    tm_exports = []; tm_tests = []; tm_io_fns = [] }

let names (m : Tir.tir_module) = List.map (fun (fd : Tir.fn_def) -> fd.fn_name) m.tm_fns
let strs = Alcotest.(list string)
let sorted tbl = List.sort String.compare (Hashtbl.fold (fun k () acc -> k :: acc) tbl [])

let contains s sub =
  let n = String.length sub and l = String.length s in
  let rec go i = i + n <= l && (String.sub s i n = sub || go (i + 1)) in
  go 0

let test_walk_defs_once_and_extra () =
  (* [defs] is asked once per reached name, every definition of a duplicate
     is followed, [known] filters edges and [extra] adds some. *)
  let tbl = Hashtbl.create 8 in
  List.iter (fun (fd : Tir.fn_def) -> Hashtbl.add tbl fd.fn_name fd)
    [ fn "main" (Tir.ESeq (call "a", call "a"));
      fn "a" (call "b"); fn "a" (call "c");
      fn "b" (lit 1); fn "c" (call "not_a_fn"); fn "d" (lit 2); fn "e" (lit 3) ];
  let asked = Hashtbl.create 8 in
  let defs n =
    Hashtbl.replace asked n (1 + Option.value ~default:0 (Hashtbl.find_opt asked n));
    Hashtbl.find_all tbl n in
  let visited =
    Dce_pre_mono.walk ~iface_methods:(Hashtbl.create 0) ~known:(Hashtbl.mem tbl) ~defs
      ~extra:(fun fd -> if fd.Tir.fn_name = "b" then [ "e" ] else []) [ "main" ] in
  Alcotest.check strs "reached" [ "a"; "b"; "c"; "e"; "main" ] (sorted visited);
  Hashtbl.iter (fun n k ->
      Alcotest.(check int) (n ^ " asked once") 1 k) asked

let raises_mentioning mentions f =
  match f () with
  | _ -> Alcotest.fail "expected the prune to refuse"
  | exception Failure msg ->
    List.iter (fun s ->
        Alcotest.(check bool) (Printf.sprintf "message mentions %s: %s" s msg)
          true (contains msg s)) mentions

let test_prune_refuses_reached_stub () =
  let m = module_of [ stub "Lib.f"; fn "main" (call "Lib.f") ] in
  raises_mentioning [ "Lib.f"; "--disable-pass lazy-lower"; "report" ] (fun () ->
      Dce_pre_mono.prune ~extra_roots:[] ~fail_open:true m)

let test_prune_refuses_stub_behind_code () =
  (* A pass may put code in front of a stub's body (Vectorize_mark does). *)
  let m = module_of
      [ fn "Lib.f" (Tir.ESeq (call "__vectorize_marker_hard", (stub "x").fn_body));
        fn "main" (call "Lib.f") ] in
  raises_mentioning [ "Lib.f" ] (fun () ->
      Dce_pre_mono.prune ~extra_roots:[] ~fail_open:true m)

let test_prune_removes_unreached_stub () =
  let m = module_of [ stub "Lib.g"; fn "Lib.f" (lit 1); fn "main" (call "Lib.f") ] in
  let m', removed = Dce_pre_mono.prune ~extra_roots:[] ~fail_open:true m in
  Alcotest.check strs "kept" [ "Lib.f"; "main" ] (names m');
  (* In the removed set, so Mono's pruned-name tripwire covers a name Mono
     mints itself. *)
  Alcotest.check strs "removed" [ "Lib.g" ] (sorted removed)

(* ── Lowering a program with a pretend stdlib ──────────────────────────── *)

let parse_file ~file src : March_ast.Ast.module_ =
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <- { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = file };
  March_desugar.Desugar.desugar_module (March_parser.Parse.module_of_lexbuf lexbuf)

(* [std] are (file stem, source) of the pretend stdlib modules, in order;
   [prelude] is spliced in at the top level, as the real prelude is. *)
let with_program ?(prelude = "") ~std ~entry (k : March_ast.Ast.module_ -> 'a) : 'a =
  let files = List.map (fun (stem, _) -> "lazy_lower_test_std_" ^ stem ^ ".march") std in
  let pfile = "lazy_lower_test_std_prelude.march" in
  let saved = !March_typecheck.Typecheck_builtins.stdlib_source_files in
  March_typecheck.Typecheck_builtins.stdlib_source_files := pfile :: files @ saved;
  Fun.protect ~finally:(fun () ->
      March_typecheck.Typecheck_builtins.stdlib_source_files := saved)
    (fun () ->
       let mods = List.map2 (fun file (_, src) ->
           let s = parse_file ~file src in
           March_ast.Ast.DMod (s.mod_name, March_ast.Ast.Public, s.mod_decls,
                               March_ast.Ast.dummy_span)) files std in
       let pre = if prelude = "" then []
         else (parse_file ~file:pfile ("mod Prelude do\n" ^ prelude ^ "\nend")).mod_decls in
       let e = parse_file ~file:"lazy_lower_test_entry.march" entry in
       k { e with mod_decls = pre @ mods @ e.mod_decls })

let lower ?(extra = []) ~lazy_ (m : March_ast.Ast.module_) : Tir.tir_module =
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let lazy_bodies =
    if lazy_ then Some { Lower.lz_extra_roots = (fun () -> extra) } else None in
  Lower.lower_module ~type_map ?lazy_bodies m

let find (m : Tir.tir_module) name =
  match List.filter (fun (fd : Tir.fn_def) -> fd.fn_name = name) m.tm_fns with
  | [ fd ] -> fd
  | [] -> Alcotest.failf "no fn %s" name
  | _ -> Alcotest.failf "fn %s defined twice" name

let text m name = Pp.string_of_fn_def (find m name)
let is_stub m name = Dce_pre_mono.is_unlowered (find m name)

let lib_a = ("a", {|mod LzA do
  fn used(x : Int) : Int do helper(x) + 1 end
  fn helper(x : Int) : Int do x * 2 end
  fn unused(x : Int) : Int do x - 1 end
  fn minted(x : Int) : Int do x + 7 end
end|})

let test_reached_lowered_unreached_stubbed () =
  with_program ~std:[ lib_a ]
    ~entry:"mod T do\n  fn main() : Int do LzA.used(3) end\nend" (fun p ->
      let eager = lower ~lazy_:false p and lz = lower ~lazy_:true p in
      Alcotest.(check bool) "unused is a stub" true (is_stub lz "LzA.unused");
      Alcotest.(check bool) "an extra root nobody calls is a stub without it" true
        (is_stub lz "LzA.minted");
      List.iter (fun n ->
          Alcotest.(check bool) (n ^ " lowered") false (is_stub lz n);
          Alcotest.(check string) (n ^ ": the TIR eager lowering gives") (text eager n) (text lz n))
        [ "LzA.used"; "LzA.helper"; "main" ];
      Alcotest.check strs "every fn keeps its position" (names eager) (names lz);
      let pruned, removed = Dce_pre_mono.prune ~extra_roots:[] ~fail_open:true lz in
      Alcotest.check strs "the prune keeps the lowered bodies"
        [ "LzA.used"; "LzA.helper"; "main" ] (names pruned);
      Alcotest.(check bool) "and removes the stubs" true
        (Hashtbl.mem removed "LzA.unused" && Hashtbl.mem removed "LzA.minted"))

let test_extra_roots_lowered () =
  with_program ~std:[ lib_a ]
    ~entry:"mod T do\n  fn main() : Int do LzA.used(3) end\nend" (fun p ->
      let eager = lower ~lazy_:false p in
      let lz = lower ~extra:[ "LzA.minted" ] ~lazy_:true p in
      Alcotest.(check bool) "a name a later pass calls is lowered" false (is_stub lz "LzA.minted");
      Alcotest.(check string) "as eager lowering gives it" (text eager "LzA.minted")
        (text lz "LzA.minted");
      Alcotest.(check bool) "unused still a stub" true (is_stub lz "LzA.unused"))

let test_rootless_lowers_everything () =
  with_program ~std:[ lib_a ]
    ~entry:"mod T do\n  type Shape = Circle(Int) | Square(Int)\nend" (fun p ->
      let eager = lower ~lazy_:false p and lz = lower ~lazy_:true p in
      List.iter (fun (fd : Tir.fn_def) ->
          Alcotest.(check bool) (fd.fn_name ^ " lowered: the prune will fail open") false
            (Dce_pre_mono.is_unlowered fd);
          Alcotest.(check string) fd.fn_name (text eager fd.fn_name) (text lz fd.fn_name))
        lz.tm_fns)

let test_body_sees_aliases_as_declared () =
  (* [LzL.go] calls the prelude's [rev] by its bare name.  The entry's
     [import U] (whose [rev] differs) is processed after every stdlib module;
     lowered late against the live alias table, [go] called [U.rev]. *)
  with_program
    ~prelude:"  fn rev(x : Int) : Int do x + 100 end"
    ~std:[ ("l", "mod LzL do\n  fn go(x : Int) : Int do rev(x) end\nend") ]
    ~entry:{|mod T do
  mod U do
    fn rev(x : Int) : Int do x end
  end
  import U
  fn main() : Int do LzL.go(1) end
end|} (fun p ->
      let eager = lower ~lazy_:false p and lz = lower ~lazy_:true p in
      Alcotest.(check bool) "eager: the prelude's" false (contains (text eager "LzL.go") "U.rev");
      Alcotest.(check string) "lazy: the same body" (text eager "LzL.go") (text lz "LzL.go"))

let test_body_keeps_enclosing_scope () =
  (* [LzB]'s [import LzA2] puts [helper -> LzA2.helper] in the program-global
     alias table before [LzN] is declared.  [LzN.Inner.go]'s bare [helper] is
     its enclosing module's ([LzN.helper]); that scope must be reinstated
     when the body is lowered late, or the global alias wins. *)
  with_program
    ~std:[ ("a2", "mod LzA2 do\n  fn helper() : Int do 10 end\nend");
           ("b", "mod LzB do\n  import LzA2\n  fn b() : Int do 0 end\nend");
           ("n", {|mod LzN do
  fn helper() : Int do 1 end
  mod Inner do
    fn go() : Int do helper() end
  end
end|}) ]
    ~entry:"mod T do\n  fn main() : Int do LzN.Inner.go() end\nend" (fun p ->
      let eager = lower ~lazy_:false p and lz = lower ~lazy_:true p in
      let e = text eager "LzN.Inner.go" in
      Alcotest.(check bool) ("eager calls LzN.helper: " ^ e) true (contains e "LzN.helper");
      Alcotest.(check string) "lazy: the same body" e (text lz "LzN.Inner.go"))

let suites =
  [ ("lazy-lower",
     [ Alcotest.test_case "walk: defs once, duplicates, extra edges" `Quick
         test_walk_defs_once_and_extra;
       Alcotest.test_case "prune refuses a reached stub" `Quick test_prune_refuses_reached_stub;
       Alcotest.test_case "prune refuses a stub behind code" `Quick
         test_prune_refuses_stub_behind_code;
       Alcotest.test_case "prune removes an unreached stub" `Quick
         test_prune_removes_unreached_stub;
       Alcotest.test_case "reached lowered, unreached stubbed" `Quick
         test_reached_lowered_unreached_stubbed;
       Alcotest.test_case "extra roots are lowered" `Quick test_extra_roots_lowered;
       Alcotest.test_case "no root: every body lowered" `Quick test_rootless_lowers_everything;
       Alcotest.test_case "aliases as of the declaration" `Quick
         test_body_sees_aliases_as_declared;
       Alcotest.test_case "enclosing-module scope reinstated" `Quick
         test_body_keeps_enclosing_scope;
     ]) ]
