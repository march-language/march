(** The pre-mono reachability prune ([Dce_pre_mono]) and Mono's pruned-name
    tripwire.  Modules are built by hand so each case names exactly the edge
    it pins.  See specs/2026-11-24-stdlib-compile-floor-design.md. *)

open March_tir

let v name ty : Tir.var = { v_name = name; v_ty = ty; v_lin = Tir.Unr }
let int_fn = Tir.TFn ([], Tir.TInt)

let fn name ?(params = []) body : Tir.fn_def =
  { fn_name = name; fn_params = params; fn_ret_ty = Tir.TInt;
    fn_body = body; fn_kind = Tir.FnNormal }

let call name args = Tir.EApp (v name int_fn, args)
let lit n = Tir.EAtom (Tir.ALit (March_ast.Ast.LitInt n))

let module_of ?(tests = []) ?(exports = []) fns : Tir.tir_module =
  { tm_name = "T"; tm_fns = fns; tm_types = []; tm_externs = [];
    tm_exports = exports; tm_tests = tests; tm_io_fns = [] }

let prune ?iface_methods ?(extra_roots = []) ?(fail_open = true) m =
  Dce_pre_mono.prune ?iface_methods ~extra_roots ~fail_open m

let names (m : Tir.tir_module) =
  List.map (fun (fd : Tir.fn_def) -> fd.fn_name) m.tm_fns

let removed tbl = List.sort String.compare (Hashtbl.fold (fun k () acc -> k :: acc) tbl [])

let strs = Alcotest.(list string)

let test_keeps_main_closure () =
  let m = module_of
      [ fn "h" (lit 0); fn "g" (lit 1); fn "f" (call "g" []);
        fn "main" (call "f" []) ] in
  let m', gone = prune m in
  Alcotest.check strs "survivors keep their order" ["g"; "f"; "main"] (names m');
  Alcotest.check strs "removed" ["h"] (removed gone)

let test_follows_fn_used_as_value () =
  let m = module_of
      [ fn "k" (lit 1); fn "unused" (lit 0);
        fn "main" (Tir.EAtom (Tir.AVar (v "k" int_fn))) ] in
  Alcotest.check strs "k kept" ["k"; "main"] (names (fst (prune m)))

let test_follows_nested_lambda () =
  let lam = fn "lam" (call "inner" []) in
  let m = module_of
      [ fn "inner" (lit 1); fn "unused" (lit 0);
        fn "main" (Tir.ELetRec ([lam], call "lam" [])) ] in
  Alcotest.check strs "callee of a nested fn kept" ["inner"; "main"]
    (names (fst (prune m)))

let iface_tbl () =
  let tbl : (string, (string * string) list) Hashtbl.t = Hashtbl.create 4 in
  Hashtbl.replace tbl "show" [("Int", "Show$Int.show"); ("Foo", "Show$Foo.show")];
  Hashtbl.replace tbl "compare" [("$Tuple2", "Ord$Tuple2.compare")];
  tbl

let test_follows_iface_impls () =
  let x = Tir.AVar (v "x" Tir.TInt) in
  let m = module_of
      [ fn "Show$Int.show" (lit 1); fn "Show$Foo.show" (call "foo_helper" []);
        fn "foo_helper" (lit 2); fn "Eq$Foo.eq" (lit 3);
        fn "main" ~params:[v "x" Tir.TInt] (call "show" [x]) ] in
  let m', gone = prune ~iface_methods:(iface_tbl ()) m in
  Alcotest.check strs "every impl of the method, and what it calls"
    ["Show$Int.show"; "Show$Foo.show"; "foo_helper"; "main"] (names m');
  Alcotest.check strs "an impl of another interface goes" ["Eq$Foo.eq"] (removed gone)

let test_no_iface_table_follows_no_impls () =
  let m = module_of
      [ fn "Show$Int.show" (lit 1); fn "main" (call "show" []) ] in
  Alcotest.check strs "without a table there is no impl edge" ["main"]
    (names (fst (prune m)))

let ord_module () =
  let pair = Tir.TTuple [Tir.TInt; Tir.TInt] in
  let a = Tir.AVar (v "a" pair) and b = Tir.AVar (v "b" pair) in
  module_of
    [ fn "__ord_lt" ~params:[v "a" pair; v "b" pair]
        (Tir.ELet (v "c" Tir.TInt, call "compare" [a; b],
                   call "<" [Tir.AVar (v "c" Tir.TInt);
                             Tir.ALit (March_ast.Ast.LitInt 0)]));
      fn "__ord_le" (lit 0); fn "__ord_gt" (lit 0); fn "__ord_ge" (lit 0);
      fn "Ord$Tuple2.compare" (lit 0); fn "unused" (lit 0);
      fn "main" ~params:[v "a" pair; v "b" pair] (call "<" [a; b]) ]

let test_follows_ord_helpers () =
  let m', gone = prune ~iface_methods:(iface_tbl ()) (ord_module ()) in
  Alcotest.check strs "the operator's helper and the Ord impl it calls"
    ["__ord_lt"; "Ord$Tuple2.compare"; "main"] (names m');
  Alcotest.(check bool) "unused removed" true (Hashtbl.mem gone "unused")

let test_duplicate_names_union () =
  let m = module_of
      [ fn "a" (lit 1); fn "b" (lit 2); fn "c" (lit 3);
        fn "dup" (call "a" []); fn "dup" (call "b" []);
        fn "main" (call "dup" []) ] in
  let m', gone = prune m in
  Alcotest.check strs "both same-named bodies are followed"
    ["a"; "b"; "dup"; "dup"; "main"] (names m');
  Alcotest.check strs "removed" ["c"] (removed gone)

let test_no_main_keeps_tests () =
  let m = module_of ~tests:[("t1", "first"); ("t2", "second")]
      [ fn "helper" (lit 1); fn "unused" (lit 0);
        fn "t1" (call "helper" []); fn "t2" (lit 2) ] in
  Alcotest.check strs "tests are roots" ["helper"; "t1"; "t2"]
    (names (fst (prune m)))

let test_roots () =
  let m = module_of ~exports:["exported"]
      [ fn "exported" (lit 1); fn "pinned" (lit 2); fn "Svc.call__rpc_stub" (lit 3);
        fn "unused" (lit 0); fn "main" (lit 4) ] in
  Alcotest.check strs "exports, extra roots and rpc stubs are roots"
    ["exported"; "pinned"; "Svc.call__rpc_stub"; "main"]
    (names (fst (prune ~extra_roots:["pinned"] m)))

let test_fail_open () =
  let m = module_of [ fn "lib_a" (lit 1); fn "lib_b" (lit 2) ] in
  let m', gone = prune m in
  Alcotest.check strs "no roots: codegen keeps everything" ["lib_a"; "lib_b"] (names m');
  Alcotest.check strs "nothing removed" [] (removed gone);
  Alcotest.check strs "no roots: an analysis keeps nothing" []
    (names (fst (prune ~fail_open:false m)))

let tagged policy = Tir.TCon ("Tagged", [Tir.TInt; Tir.TCon (policy, [])])

let test_policy_fns_are_pinned () =
  (* The policy audit runs after Fusion and reads every Tagged function, and
     nothing calls one, so the prune must keep them and what they call. *)
  let m = module_of
      [ fn "np_helper" (lit 1); fn "unused" (lit 0);
        fn "np" ~params:[v "t" (tagged "NoPanic")] (call "np_helper" []);
        fn "nio" ~params:[v "t" (tagged "NoIO")] (lit 2);
        fn "na" ~params:[v "t" (tagged "NoAlloc")] (lit 3);
        fn "rt" ~params:[v "t" (tagged "Realtime")] (lit 4);
        fn "main" (lit 5) ] in
  let m', gone = prune m in
  Alcotest.check strs "every policy-tagged fn and its callees survive"
    ["np_helper"; "np"; "nio"; "na"; "rt"; "main"] (names m');
  Alcotest.check strs "removed" ["unused"] (removed gone)

let test_bound_local_keeps_top_level () =
  (* Mono resolves a fn-typed atom by name without checking shadowing, so a
     local named like a top-level function must keep that function. *)
  let local = v "shadow" int_fn in
  let m = module_of
      [ fn "shadow" (lit 1); fn "unused" (lit 0);
        fn "main" ~params:[local] (Tir.EAtom (Tir.AVar local)) ] in
  let m', pruned = prune m in
  Alcotest.check strs "the top-level namesake is kept" ["shadow"; "main"] (names m');
  let (_ : Tir.tir_module) = Mono.monomorphize ~pruned m' in
  ()

let test_remote_ref_target_is_root () =
  let str s = Tir.ALit (March_ast.Ast.LitString s) in
  let m = module_of
      [ fn "Svc.handler" (lit 1); fn "unused" (lit 0);
        fn "main" (call "remote_ref_hashes" [str "Svc"; str "handler"]) ] in
  Alcotest.check strs "a remote-ref target is kept" ["Svc.handler"; "main"]
    (names (fst (prune m)))

let raises_tripwire ~mentions f =
  match f () with
  | (_ : Tir.tir_module) -> Alcotest.fail "expected the pruned-name tripwire"
  | exception Failure msg ->
    let has s =
      let n = String.length s and l = String.length msg in
      let rec go i = i + n <= l && (String.sub msg i n = s || go (i + 1)) in
      go 0 in
    List.iter (fun s ->
        Alcotest.(check bool) (Printf.sprintf "message mentions %s: %s" s msg)
          true (has s)) mentions

let test_tripwire_fires_on_ord_helper () =
  let m = ord_module () in
  let pruned = Hashtbl.create 4 in
  Hashtbl.replace pruned "__ord_lt" ();
  let m = { m with Tir.tm_fns =
      List.filter (fun (fd : Tir.fn_def) -> fd.fn_name <> "__ord_lt") m.tm_fns } in
  raises_tripwire ~mentions:["__ord_lt"; "main"; "dce-pre-mono"] (fun () ->
      Mono.monomorphize ~iface_methods:(iface_tbl ()) ~pruned m)

let test_tripwire_fires_on_iface_impl () =
  let x = Tir.AVar (v "x" Tir.TInt) in
  let m = module_of [ fn "main" ~params:[v "x" Tir.TInt] (call "show" [x]) ] in
  let pruned = Hashtbl.create 4 in
  Hashtbl.replace pruned "Show$Int.show" ();
  raises_tripwire ~mentions:["Show$Int.show"; "main"] (fun () ->
      Mono.monomorphize ~iface_methods:(iface_tbl ()) ~pruned m)

let test_no_tripwire_without_pruned () =
  (* The same missing helper with no prune in effect is the old behaviour:
     the operator is left for the emitter. *)
  let m = ord_module () in
  let m = { m with Tir.tm_fns =
      List.filter (fun (fd : Tir.fn_def) -> fd.fn_name <> "__ord_lt") m.tm_fns } in
  let (_ : Tir.tir_module) = Mono.monomorphize ~iface_methods:(iface_tbl ()) m in
  ()

let test_pruned_module_monomorphizes () =
  let m, pruned = prune ~iface_methods:(iface_tbl ()) (ord_module ()) in
  let m' = Mono.monomorphize ~iface_methods:(iface_tbl ()) ~pruned m in
  Alcotest.(check bool) "main survives mono" true (List.mem "main" (names m'))

let suites =
  [ ("dce-pre-mono",
     [ Alcotest.test_case "keeps main's closure" `Quick test_keeps_main_closure;
       Alcotest.test_case "fn used as a value" `Quick test_follows_fn_used_as_value;
       Alcotest.test_case "callee of a nested fn" `Quick test_follows_nested_lambda;
       Alcotest.test_case "follows iface impls" `Quick test_follows_iface_impls;
       Alcotest.test_case "no iface table, no impl edges" `Quick
         test_no_iface_table_follows_no_impls;
       Alcotest.test_case "follows ord helpers" `Quick test_follows_ord_helpers;
       Alcotest.test_case "duplicate names union" `Quick test_duplicate_names_union;
       Alcotest.test_case "tests are roots" `Quick test_no_main_keeps_tests;
       Alcotest.test_case "exports, extra roots, rpc stubs" `Quick test_roots;
       Alcotest.test_case "fail open / closed" `Quick test_fail_open;
       Alcotest.test_case "policy-tagged fns are pinned" `Quick test_policy_fns_are_pinned;
       Alcotest.test_case "bound local keeps its namesake" `Quick
         test_bound_local_keeps_top_level;
       Alcotest.test_case "remote-ref target is a root" `Quick
         test_remote_ref_target_is_root;
       Alcotest.test_case "tripwire: ord helper" `Quick test_tripwire_fires_on_ord_helper;
       Alcotest.test_case "tripwire: iface impl" `Quick test_tripwire_fires_on_iface_impl;
       Alcotest.test_case "no tripwire without a prune" `Quick
         test_no_tripwire_without_pruned;
       Alcotest.test_case "pruned module monomorphizes" `Quick
         test_pruned_module_monomorphizes ]) ]
