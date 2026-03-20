(** CAS — Content-Addressed Store test suite.

    Tests follow the migration phases from specs/content_addressed_versioning.md:
    Phase 1: Canonical serialization
    Phase 2: BLAKE3 hashing
    Phase 3: CAS store
    Phase 4: SCC / Tarjan dependency analysis
*)

open March_tir.Tir

(* ──────────────────────────────────────────────────────────────────────────
   Phase 1: Canonical serialization
   ────────────────────────────────────────────────────────────────────────── *)

let test_serialize_int_is_deterministic () =
  let b1 = March_cas.Serialize.serialize_ty TInt in
  let b2 = March_cas.Serialize.serialize_ty TInt in
  Alcotest.(check bool) "same bytes each time" true (Bytes.equal b1 b2)

let test_serialize_distinct_types_produce_distinct_bytes () =
  let bint  = March_cas.Serialize.serialize_ty TInt in
  let bfloat = March_cas.Serialize.serialize_ty TFloat in
  let bbool  = March_cas.Serialize.serialize_ty TBool in
  Alcotest.(check bool) "Int ≠ Float" false (Bytes.equal bint bfloat);
  Alcotest.(check bool) "Int ≠ Bool"  false (Bytes.equal bint bbool);
  Alcotest.(check bool) "Float ≠ Bool" false (Bytes.equal bfloat bbool)

let test_serialize_tvar_includes_name () =
  let ba = March_cas.Serialize.serialize_ty (TVar "a") in
  let bb = March_cas.Serialize.serialize_ty (TVar "b") in
  Alcotest.(check bool) "TVar a ≠ TVar b" false (Bytes.equal ba bb)

let test_serialize_tuple_order_matters () =
  let t1 = March_cas.Serialize.serialize_ty (TTuple [TInt; TBool]) in
  let t2 = March_cas.Serialize.serialize_ty (TTuple [TBool; TInt]) in
  Alcotest.(check bool) "(Int,Bool) ≠ (Bool,Int)" false (Bytes.equal t1 t2)

let test_serialize_record_fields_sorted () =
  (* Records with same fields in different order must produce same bytes *)
  let r1 = March_cas.Serialize.serialize_ty (TRecord [("a", TInt); ("b", TBool)]) in
  let r2 = March_cas.Serialize.serialize_ty (TRecord [("b", TBool); ("a", TInt)]) in
  Alcotest.(check bool) "record field order normalised" true (Bytes.equal r1 r2)

let test_serialize_fn_def_deterministic () =
  let fd : fn_def = {
    fn_name   = "add";
    fn_params = [{ v_name = "x"; v_ty = TInt; v_lin = Unr };
                 { v_name = "y"; v_ty = TInt; v_lin = Unr }];
    fn_ret_ty = TInt;
    fn_body   = EAtom (AVar { v_name = "x"; v_ty = TInt; v_lin = Unr });
  } in
  let b1 = March_cas.Serialize.serialize_fn_def fd in
  let b2 = March_cas.Serialize.serialize_fn_def fd in
  Alcotest.(check bool) "fn_def serialization deterministic" true (Bytes.equal b1 b2)

let test_serialize_fn_def_body_changes_output () =
  let base : fn_def = {
    fn_name   = "id";
    fn_params = [{ v_name = "x"; v_ty = TInt; v_lin = Unr }];
    fn_ret_ty = TInt;
    fn_body   = EAtom (AVar { v_name = "x"; v_ty = TInt; v_lin = Unr });
  } in
  let changed = { base with fn_body = EAtom (ALit (March_ast.Ast.LitInt 0)) } in
  let b1 = March_cas.Serialize.serialize_fn_def base in
  let b2 = March_cas.Serialize.serialize_fn_def changed in
  Alcotest.(check bool) "different bodies → different bytes" false (Bytes.equal b1 b2)

let test_serialize_type_def_variant () =
  let td = TDVariant ("Option", [("None", []); ("Some", [TInt])]) in
  let b1 = March_cas.Serialize.serialize_type_def td in
  let b2 = March_cas.Serialize.serialize_type_def td in
  Alcotest.(check bool) "TDVariant deterministic" true (Bytes.equal b1 b2)

let test_serialize_sig_excludes_body () =
  (* sig serialization of the same fn but different bodies must produce same bytes *)
  let fd1 : fn_def = {
    fn_name   = "f";
    fn_params = [{ v_name = "x"; v_ty = TInt; v_lin = Unr }];
    fn_ret_ty = TBool;
    fn_body   = EAtom (ALit (March_ast.Ast.LitBool true));
  } in
  let fd2 = { fd1 with fn_body = EAtom (ALit (March_ast.Ast.LitBool false)) } in
  let s1 = March_cas.Serialize.serialize_fn_sig fd1 in
  let s2 = March_cas.Serialize.serialize_fn_sig fd2 in
  Alcotest.(check bool) "sig same despite body change" true (Bytes.equal s1 s2)

let test_serialize_sig_differs_on_param_type_change () =
  let fd1 : fn_def = {
    fn_name   = "f";
    fn_params = [{ v_name = "x"; v_ty = TInt; v_lin = Unr }];
    fn_ret_ty = TBool;
    fn_body   = EAtom (ALit (March_ast.Ast.LitBool true));
  } in
  let fd2 = { fd1 with fn_params = [{ v_name = "x"; v_ty = TFloat; v_lin = Unr }] } in
  let s1 = March_cas.Serialize.serialize_fn_sig fd1 in
  let s2 = March_cas.Serialize.serialize_fn_sig fd2 in
  Alcotest.(check bool) "sig changes on param type change" false (Bytes.equal s1 s2)

(* ──────────────────────────────────────────────────────────────────────────
   Phase 2: BLAKE3 hashing
   ────────────────────────────────────────────────────────────────────────── *)

let test_blake3_same_input_same_hash () =
  let h1 = March_cas.Blake3.hash (Bytes.of_string "hello") in
  let h2 = March_cas.Blake3.hash (Bytes.of_string "hello") in
  Alcotest.(check string) "same input → same hash" h1 h2

let test_blake3_different_inputs_different_hashes () =
  let h1 = March_cas.Blake3.hash (Bytes.of_string "hello") in
  let h2 = March_cas.Blake3.hash (Bytes.of_string "world") in
  Alcotest.(check bool) "different inputs → different hashes" false (String.equal h1 h2)

let test_blake3_output_is_64_hex_chars () =
  let h = March_cas.Blake3.hash (Bytes.of_string "test") in
  Alcotest.(check int) "hash is 64 hex chars (32 bytes)" 64 (String.length h)

let test_blake3_known_vector () =
  (* Known BLAKE3 hash of empty input *)
  let h = March_cas.Blake3.hash Bytes.empty in
  let expected = "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262" in
  Alcotest.(check string) "empty input hash matches known vector" expected h

let test_hash_fn_def () =
  let fd : fn_def = {
    fn_name   = "add";
    fn_params = [{ v_name = "x"; v_ty = TInt; v_lin = Unr };
                 { v_name = "y"; v_ty = TInt; v_lin = Unr }];
    fn_ret_ty = TInt;
    fn_body   = EAtom (AVar { v_name = "x"; v_ty = TInt; v_lin = Unr });
  } in
  let hashed = March_cas.Hash.hash_fn_def fd in
  Alcotest.(check int) "sig_hash is 64 hex chars"  64 (String.length hashed.March_cas.Hash.sig_hash);
  Alcotest.(check int) "impl_hash is 64 hex chars" 64 (String.length hashed.March_cas.Hash.impl_hash)

let test_impl_hash_changes_with_body () =
  let fd1 : fn_def = {
    fn_name   = "f";
    fn_params = [{ v_name = "x"; v_ty = TInt; v_lin = Unr }];
    fn_ret_ty = TInt;
    fn_body   = EAtom (AVar { v_name = "x"; v_ty = TInt; v_lin = Unr });
  } in
  let fd2 = { fd1 with fn_body = EAtom (ALit (March_ast.Ast.LitInt 42)) } in
  let h1 = March_cas.Hash.hash_fn_def fd1 in
  let h2 = March_cas.Hash.hash_fn_def fd2 in
  Alcotest.(check bool) "impl_hash changes with body"
    false (String.equal h1.March_cas.Hash.impl_hash h2.March_cas.Hash.impl_hash)

let test_sig_hash_stable_across_body_change () =
  let fd1 : fn_def = {
    fn_name   = "f";
    fn_params = [{ v_name = "x"; v_ty = TInt; v_lin = Unr }];
    fn_ret_ty = TInt;
    fn_body   = EAtom (AVar { v_name = "x"; v_ty = TInt; v_lin = Unr });
  } in
  let fd2 = { fd1 with fn_body = EAtom (ALit (March_ast.Ast.LitInt 42)) } in
  let h1 = March_cas.Hash.hash_fn_def fd1 in
  let h2 = March_cas.Hash.hash_fn_def fd2 in
  Alcotest.(check string) "sig_hash stable across body change"
    h1.March_cas.Hash.sig_hash h2.March_cas.Hash.sig_hash

(* ──────────────────────────────────────────────────────────────────────────
   Phase 3: CAS store
   ────────────────────────────────────────────────────────────────────────── *)

let with_tmpdir f =
  let dir = Filename.temp_file "march_cas_test" "" in
  Unix.unlink dir;
  Unix.mkdir dir 0o700;
  let cleanup () =
    let _ = Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)) in ()
  in
  Fun.protect ~finally:cleanup (fun () -> f dir)

let test_cas_store_and_lookup_def () =
  with_tmpdir @@ fun root ->
  let store = March_cas.Cas.create ~project_root:root in
  let fd : fn_def = {
    fn_name   = "id";
    fn_params = [{ v_name = "x"; v_ty = TInt; v_lin = Unr }];
    fn_ret_ty = TInt;
    fn_body   = EAtom (AVar { v_name = "x"; v_ty = TInt; v_lin = Unr });
  } in
  let hashed = March_cas.Hash.hash_fn_def fd in
  let hd : March_cas.Cas.hashed_def = {
    hd_sig_hash  = hashed.March_cas.Hash.sig_hash;
    hd_impl_hash = hashed.March_cas.Hash.impl_hash;
    hd_def       = March_cas.Cas.FnDef fd;
  } in
  March_cas.Cas.store_def store hd;
  let result = March_cas.Cas.lookup_def store hashed.March_cas.Hash.impl_hash in
  Alcotest.(check bool) "stored def can be looked up" true (Option.is_some result)

let test_cas_lookup_miss_returns_none () =
  with_tmpdir @@ fun root ->
  let store = March_cas.Cas.create ~project_root:root in
  let result = March_cas.Cas.lookup_def store (String.make 64 'a') in
  Alcotest.(check bool) "unknown hash returns None" true (Option.is_none result)

let test_cas_name_index () =
  with_tmpdir @@ fun root ->
  let store = March_cas.Cas.create ~project_root:root in
  let def_id = { March_cas.Cas.did_name = "List.map"; did_hash = String.make 64 'b' } in
  March_cas.Cas.update_index store [("List.map", def_id)];
  let result = March_cas.Cas.lookup_name store "List.map" in
  Alcotest.(check bool) "name resolves after update_index" true (Option.is_some result);
  let found = Option.get result in
  Alcotest.(check string) "resolves to correct hash" (String.make 64 'b') found.March_cas.Cas.did_hash

let test_cas_store_artifact_and_lookup () =
  with_tmpdir @@ fun root ->
  let store = March_cas.Cas.create ~project_root:root in
  let ch = March_cas.Cas.compilation_hash (String.make 64 'c')
             ~target:"aarch64-darwin" ~flags:["-O2"] in
  let fake_path = "/tmp/fake.o" in
  March_cas.Cas.store_artifact store ch fake_path;
  let result = March_cas.Cas.lookup_artifact store ch in
  Alcotest.(check bool) "artifact found after store" true (Option.is_some result);
  Alcotest.(check string) "artifact path correct" fake_path (Option.get result)

let test_cas_compilation_hash_differs_by_target () =
  let ch1 = March_cas.Cas.compilation_hash (String.make 64 'd')
              ~target:"aarch64-darwin" ~flags:[] in
  let ch2 = March_cas.Cas.compilation_hash (String.make 64 'd')
              ~target:"x86_64-linux" ~flags:[] in
  Alcotest.(check bool) "different targets → different compilation hashes"
    false (String.equal ch1 ch2)

let test_cas_gc_removes_unreferenced () =
  with_tmpdir @@ fun root ->
  let store = March_cas.Cas.create ~project_root:root in
  let fd : fn_def = {
    fn_name   = "foo";
    fn_params = [];
    fn_ret_ty = TUnit;
    fn_body   = EAtom (ALit (March_ast.Ast.LitAtom "unit"));
  } in
  let hashed = March_cas.Hash.hash_fn_def fd in
  let hd : March_cas.Cas.hashed_def = {
    hd_sig_hash  = hashed.March_cas.Hash.sig_hash;
    hd_impl_hash = hashed.March_cas.Hash.impl_hash;
    hd_def       = March_cas.Cas.FnDef fd;
  } in
  March_cas.Cas.store_def store hd;
  (* GC with empty keep list removes it *)
  let removed = March_cas.Cas.gc store ~keep_defs:[] ~keep_artifacts:[] in
  Alcotest.(check bool) "gc removed at least 1 object" true (removed > 0);
  let result = March_cas.Cas.lookup_def store hashed.March_cas.Hash.impl_hash in
  Alcotest.(check bool) "def gone after gc" true (Option.is_none result)

(* ──────────────────────────────────────────────────────────────────────────
   Phase 4: Dependency analysis and SCC detection (Tarjan's)
   ────────────────────────────────────────────────────────────────────────── *)

let test_scc_single_non_recursive () =
  (* fn f(x: Int): Int = x   — no references, single SCC *)
  let fd : fn_def = {
    fn_name   = "f";
    fn_params = [{ v_name = "x"; v_ty = TInt; v_lin = Unr }];
    fn_ret_ty = TInt;
    fn_body   = EAtom (AVar { v_name = "x"; v_ty = TInt; v_lin = Unr });
  } in
  let sccs = March_cas.Scc.compute_sccs [fd] in
  Alcotest.(check int) "one SCC for one fn" 1 (List.length sccs);
  match List.hd sccs with
  | March_cas.Scc.Single name -> Alcotest.(check string) "correct name" "f" name
  | March_cas.Scc.Group _     -> Alcotest.fail "expected Single"

let test_scc_self_recursive_is_single () =
  (* fn f(x: Int): Int = f(x)   — self-recursive, still a Single *)
  let fd : fn_def = {
    fn_name   = "f";
    fn_params = [{ v_name = "x"; v_ty = TInt; v_lin = Unr }];
    fn_ret_ty = TInt;
    fn_body   = EApp ({ v_name = "f"; v_ty = TFn ([TInt], TInt); v_lin = Unr },
                      [AVar { v_name = "x"; v_ty = TInt; v_lin = Unr }]);
  } in
  let sccs = March_cas.Scc.compute_sccs [fd] in
  Alcotest.(check int) "one SCC for self-recursive fn" 1 (List.length sccs);
  match List.hd sccs with
  | March_cas.Scc.Single name -> Alcotest.(check string) "correct name" "f" name
  | March_cas.Scc.Group _     -> Alcotest.fail "expected Single for self-recursive"

let test_scc_mutual_recursion_is_group () =
  (* fn even(n): Bool = if n=0 then true else odd(n-1)
     fn odd(n): Bool = if n=0 then false else even(n-1)
     Both belong to the same SCC group. *)
  let even_fd : fn_def = {
    fn_name   = "even";
    fn_params = [{ v_name = "n"; v_ty = TInt; v_lin = Unr }];
    fn_ret_ty = TBool;
    fn_body   = EApp ({ v_name = "odd"; v_ty = TFn ([TInt], TBool); v_lin = Unr },
                      [AVar { v_name = "n"; v_ty = TInt; v_lin = Unr }]);
  } in
  let odd_fd : fn_def = {
    fn_name   = "odd";
    fn_params = [{ v_name = "n"; v_ty = TInt; v_lin = Unr }];
    fn_ret_ty = TBool;
    fn_body   = EApp ({ v_name = "even"; v_ty = TFn ([TInt], TBool); v_lin = Unr },
                      [AVar { v_name = "n"; v_ty = TInt; v_lin = Unr }]);
  } in
  let sccs = March_cas.Scc.compute_sccs [even_fd; odd_fd] in
  Alcotest.(check int) "one SCC group for mutual recursion" 1 (List.length sccs);
  match List.hd sccs with
  | March_cas.Scc.Group members ->
    let sorted = List.sort String.compare members in
    Alcotest.(check (list string)) "group contains both" ["even"; "odd"] sorted
  | March_cas.Scc.Single _ -> Alcotest.fail "expected Group for mutual recursion"

let test_scc_topological_order () =
  (* g calls f, so f's SCC must come before g's SCC *)
  let f_fd : fn_def = {
    fn_name   = "f";
    fn_params = [{ v_name = "x"; v_ty = TInt; v_lin = Unr }];
    fn_ret_ty = TInt;
    fn_body   = EAtom (AVar { v_name = "x"; v_ty = TInt; v_lin = Unr });
  } in
  let g_fd : fn_def = {
    fn_name   = "g";
    fn_params = [{ v_name = "x"; v_ty = TInt; v_lin = Unr }];
    fn_ret_ty = TInt;
    fn_body   = EApp ({ v_name = "f"; v_ty = TFn ([TInt], TInt); v_lin = Unr },
                      [AVar { v_name = "x"; v_ty = TInt; v_lin = Unr }]);
  } in
  let sccs = March_cas.Scc.compute_sccs [g_fd; f_fd] in
  (* f must appear before g in topological order *)
  let names = List.map (function
    | March_cas.Scc.Single n -> n
    | March_cas.Scc.Group members -> String.concat "," members) sccs in
  let find_idx target lst =
    let rec go i = function
      | []                          -> failwith ("not found: " ^ target)
      | x :: _ when String.equal x target -> i
      | _ :: rest                   -> go (i + 1) rest
    in go 0 lst
  in
  let f_idx = find_idx "f" names in
  let g_idx = find_idx "g" names in
  Alcotest.(check bool) "f before g in topo order" true (f_idx < g_idx)

(* ──────────────────────────────────────────────────────────────────────────
   Phase 5: Hash-first name resolution (def_id, ADefRef in TIR)
   ────────────────────────────────────────────────────────────────────────── *)

let test_def_id_equality () =
  let d1 : March_cas.Cas.def_id = { did_name = "List.map"; did_hash = String.make 64 'a' } in
  let d2 : March_cas.Cas.def_id = { did_name = "List.map"; did_hash = String.make 64 'a' } in
  let d3 : March_cas.Cas.def_id = { did_name = "List.map"; did_hash = String.make 64 'b' } in
  Alcotest.(check bool) "same name+hash are equal" true
    (String.equal d1.did_hash d2.did_hash && String.equal d1.did_name d2.did_name);
  Alcotest.(check bool) "different hash → not equal" false
    (String.equal d1.did_hash d3.did_hash)

let test_adefref_serialize_encodes_hash () =
  let did : March_cas.Cas.def_id = { did_name = "add"; did_hash = String.make 64 'f' } in
  let atom = ADefRef did in
  let b = March_cas.Serialize.serialize_atom atom in
  (* First byte must be tag 0x80 for ADefRef *)
  Alcotest.(check int) "ADefRef tag is 0x80" 0x80 (Char.code (Bytes.get b 0))

let test_adefref_serializes_hash_not_name () =
  (* Two ADefRef atoms with same hash but different names must serialize identically
     — the hash is the identity, not the name. *)
  let did1 : March_cas.Cas.def_id = { did_name = "foo"; did_hash = String.make 64 'c' } in
  let did2 : March_cas.Cas.def_id = { did_name = "bar"; did_hash = String.make 64 'c' } in
  let b1 = March_cas.Serialize.serialize_atom (ADefRef did1) in
  let b2 = March_cas.Serialize.serialize_atom (ADefRef did2) in
  Alcotest.(check bool) "same hash → same bytes regardless of name" true (Bytes.equal b1 b2)

let test_adefref_distinct_hash_produces_distinct_bytes () =
  let did1 : March_cas.Cas.def_id = { did_name = "f"; did_hash = String.make 64 'a' } in
  let did2 : March_cas.Cas.def_id = { did_name = "f"; did_hash = String.make 64 'b' } in
  let b1 = March_cas.Serialize.serialize_atom (ADefRef did1) in
  let b2 = March_cas.Serialize.serialize_atom (ADefRef did2) in
  Alcotest.(check bool) "different hashes → different bytes" false (Bytes.equal b1 b2)

let test_impl_hash_changes_when_dependency_hash_changes () =
  (* fn g = ADefRef(did_v1 of f) vs fn g = ADefRef(did_v2 of f)
     The impl_hash of g must differ between the two. *)
  let did_v1 : March_cas.Cas.def_id = { did_name = "f"; did_hash = String.make 64 'a' } in
  let did_v2 : March_cas.Cas.def_id = { did_name = "f"; did_hash = String.make 64 'b' } in
  let g1 : fn_def = {
    fn_name   = "g";
    fn_params = [];
    fn_ret_ty = TInt;
    fn_body   = EAtom (ADefRef did_v1);
  } in
  let g2 = { g1 with fn_body = EAtom (ADefRef did_v2) } in
  let h1 = March_cas.Hash.hash_fn_def g1 in
  let h2 = March_cas.Hash.hash_fn_def g2 in
  Alcotest.(check bool) "impl_hash of g changes when dep hash changes"
    false (String.equal h1.March_cas.Hash.impl_hash h2.March_cas.Hash.impl_hash)

(* ──────────────────────────────────────────────────────────────────────────
   Phase 6: Cache-hit fast path (Pipeline module)
   ────────────────────────────────────────────────────────────────────────── *)

(* Helpers *)
let make_fn name body : fn_def =
  { fn_name = name; fn_params = []; fn_ret_ty = TInt; fn_body = body }

let int_atom n = EAtom (ALit (March_ast.Ast.LitInt n))

let test_scc_impl_hash_single () =
  (* scc_impl_hash of a Single returns the fn's impl_hash *)
  let fd = make_fn "f" (int_atom 1) in
  let hmod = March_cas.Pipeline.hash_module
               { tm_name = "T"; tm_fns = [fd]; tm_types = []; tm_externs = [] } in
  let h_scc = List.hd hmod in
  let impl_hash = March_cas.Pipeline.scc_impl_hash h_scc in
  Alcotest.(check int) "impl_hash is 64 hex chars" 64 (String.length impl_hash)

let test_scc_impl_hash_group () =
  (* Mutually recursive pair → Group → scc_impl_hash returns the group hash *)
  let even_fd = make_fn "even"
    (EApp ({ v_name = "odd"; v_ty = TFn ([], TInt); v_lin = Unr }, [])) in
  let odd_fd  = make_fn "odd"
    (EApp ({ v_name = "even"; v_ty = TFn ([], TInt); v_lin = Unr }, [])) in
  let hmod = March_cas.Pipeline.hash_module
               { tm_name = "T"; tm_fns = [even_fd; odd_fd]; tm_types = []; tm_externs = [] } in
  Alcotest.(check int) "one SCC for mutual recursion" 1 (List.length hmod);
  let h_scc = List.hd hmod in
  let impl_hash = March_cas.Pipeline.scc_impl_hash h_scc in
  Alcotest.(check int) "group impl_hash is 64 hex chars" 64 (String.length impl_hash)

let test_hash_module_independent_fns_two_sccs () =
  (* f and g are independent → two SCCs *)
  let f = make_fn "f" (int_atom 1) in
  let g = make_fn "g" (int_atom 2) in
  let hmod = March_cas.Pipeline.hash_module
               { tm_name = "T"; tm_fns = [f; g]; tm_types = []; tm_externs = [] } in
  Alcotest.(check int) "two independent fns → two SCCs" 2 (List.length hmod)

let test_compile_scc_cache_miss_calls_compiler () =
  (* First call: cache miss → compiler is invoked exactly once *)
  with_tmpdir @@ fun root ->
  let store = March_cas.Cas.create ~project_root:root in
  let fd = make_fn "f" (int_atom 42) in
  let hmod = March_cas.Pipeline.hash_module
               { tm_name = "T"; tm_fns = [fd]; tm_types = []; tm_externs = [] } in
  let h_scc = List.hd hmod in
  let calls = ref 0 in
  let fake_compile _scc = incr calls; "/tmp/f.o" in
  let _path = March_cas.Pipeline.compile_scc store ~target:"test" ~flags:[]
                ~compile:fake_compile h_scc in
  Alcotest.(check int) "compiler called once on cache miss" 1 !calls

let test_compile_scc_cache_hit_skips_compiler () =
  (* Second call with same hash: artifact already cached → compiler not called *)
  with_tmpdir @@ fun root ->
  let store = March_cas.Cas.create ~project_root:root in
  let fd = make_fn "f" (int_atom 42) in
  let hmod = March_cas.Pipeline.hash_module
               { tm_name = "T"; tm_fns = [fd]; tm_types = []; tm_externs = [] } in
  let h_scc = List.hd hmod in
  let calls = ref 0 in
  let fake_compile _scc = incr calls; "/tmp/f.o" in
  (* First call — populates cache *)
  let _ = March_cas.Pipeline.compile_scc store ~target:"test" ~flags:[]
            ~compile:fake_compile h_scc in
  (* Second call — should hit cache *)
  let _ = March_cas.Pipeline.compile_scc store ~target:"test" ~flags:[]
            ~compile:fake_compile h_scc in
  Alcotest.(check int) "compiler NOT called on cache hit (total calls = 1)" 1 !calls

let test_compile_scc_returns_artifact_path () =
  with_tmpdir @@ fun root ->
  let store = March_cas.Cas.create ~project_root:root in
  let fd = make_fn "f" (int_atom 7) in
  let hmod = March_cas.Pipeline.hash_module
               { tm_name = "T"; tm_fns = [fd]; tm_types = []; tm_externs = [] } in
  let h_scc = List.hd hmod in
  let expected = "/tmp/expected_path.o" in
  let path = March_cas.Pipeline.compile_scc store ~target:"test" ~flags:[]
               ~compile:(fun _ -> expected) h_scc in
  Alcotest.(check string) "returned path matches compiler output" expected path

let test_compile_scc_cache_hit_returns_cached_path () =
  (* After cache is warm, returned path is the originally stored path *)
  with_tmpdir @@ fun root ->
  let store = March_cas.Cas.create ~project_root:root in
  let fd = make_fn "f" (int_atom 7) in
  let hmod = March_cas.Pipeline.hash_module
               { tm_name = "T"; tm_fns = [fd]; tm_types = []; tm_externs = [] } in
  let h_scc = List.hd hmod in
  let original = "/tmp/original.o" in
  let _ = March_cas.Pipeline.compile_scc store ~target:"test" ~flags:[]
            ~compile:(fun _ -> original) h_scc in
  (* Second call with a *different* fake path — must still return original *)
  let hit_path = March_cas.Pipeline.compile_scc store ~target:"test" ~flags:[]
                   ~compile:(fun _ -> "/tmp/should_not_be_used.o") h_scc in
  Alcotest.(check string) "cache hit returns stored path" original hit_path

let test_changed_body_causes_cache_miss () =
  (* Two fns with same name but different bodies → different hashes → both miss *)
  with_tmpdir @@ fun root ->
  let store = March_cas.Cas.create ~project_root:root in
  let fd1 = make_fn "f" (int_atom 1) in
  let fd2 = make_fn "f" (int_atom 2) in
  let hmod1 = March_cas.Pipeline.hash_module
                { tm_name = "T"; tm_fns = [fd1]; tm_types = []; tm_externs = [] } in
  let hmod2 = March_cas.Pipeline.hash_module
                { tm_name = "T"; tm_fns = [fd2]; tm_types = []; tm_externs = [] } in
  let h_scc1 = List.hd hmod1 in
  let h_scc2 = List.hd hmod2 in
  let calls = ref 0 in
  let fake_compile _scc = incr calls; "/tmp/out.o" in
  let _ = March_cas.Pipeline.compile_scc store ~target:"test" ~flags:[]
            ~compile:fake_compile h_scc1 in
  let _ = March_cas.Pipeline.compile_scc store ~target:"test" ~flags:[]
            ~compile:fake_compile h_scc2 in
  Alcotest.(check int) "two different bodies → two cache misses" 2 !calls

let test_different_targets_cause_separate_cache_entries () =
  (* Same SCC, different target → different compilation_hash → two misses *)
  with_tmpdir @@ fun root ->
  let store = March_cas.Cas.create ~project_root:root in
  let fd = make_fn "f" (int_atom 5) in
  let hmod = March_cas.Pipeline.hash_module
               { tm_name = "T"; tm_fns = [fd]; tm_types = []; tm_externs = [] } in
  let h_scc = List.hd hmod in
  let calls = ref 0 in
  let fake_compile _scc = incr calls; "/tmp/out.o" in
  let _ = March_cas.Pipeline.compile_scc store ~target:"aarch64-darwin" ~flags:[]
            ~compile:fake_compile h_scc in
  let _ = March_cas.Pipeline.compile_scc store ~target:"x86_64-linux" ~flags:[]
            ~compile:fake_compile h_scc in
  Alcotest.(check int) "different targets → two cache entries" 2 !calls

(* ──────────────────────────────────────────────────────────────────────────
   Runner
   ────────────────────────────────────────────────────────────────────────── *)

let () =
  Alcotest.run "cas" [
    ("serialize", [
      Alcotest.test_case "TInt serializes deterministically"  `Quick test_serialize_int_is_deterministic;
      Alcotest.test_case "distinct types → distinct bytes"    `Quick test_serialize_distinct_types_produce_distinct_bytes;
      Alcotest.test_case "TVar name included"                 `Quick test_serialize_tvar_includes_name;
      Alcotest.test_case "tuple order matters"                `Quick test_serialize_tuple_order_matters;
      Alcotest.test_case "record fields sorted"               `Quick test_serialize_record_fields_sorted;
      Alcotest.test_case "fn_def deterministic"               `Quick test_serialize_fn_def_deterministic;
      Alcotest.test_case "fn_def body change → new bytes"     `Quick test_serialize_fn_def_body_changes_output;
      Alcotest.test_case "type_def variant deterministic"     `Quick test_serialize_type_def_variant;
      Alcotest.test_case "sig excludes body"                  `Quick test_serialize_sig_excludes_body;
      Alcotest.test_case "sig changes on param type change"   `Quick test_serialize_sig_differs_on_param_type_change;
    ]);
    ("blake3", [
      Alcotest.test_case "same input → same hash"             `Quick test_blake3_same_input_same_hash;
      Alcotest.test_case "different inputs → different hashes" `Quick test_blake3_different_inputs_different_hashes;
      Alcotest.test_case "output is 64 hex chars"             `Quick test_blake3_output_is_64_hex_chars;
      Alcotest.test_case "known empty-input vector"           `Quick test_blake3_known_vector;
      Alcotest.test_case "hash_fn_def produces hashes"        `Quick test_hash_fn_def;
      Alcotest.test_case "impl_hash changes with body"        `Quick test_impl_hash_changes_with_body;
      Alcotest.test_case "sig_hash stable across body change" `Quick test_sig_hash_stable_across_body_change;
    ]);
    ("cas_store", [
      Alcotest.test_case "store and lookup def"               `Quick test_cas_store_and_lookup_def;
      Alcotest.test_case "lookup miss returns None"           `Quick test_cas_lookup_miss_returns_none;
      Alcotest.test_case "name index"                         `Quick test_cas_name_index;
      Alcotest.test_case "store and lookup artifact"          `Quick test_cas_store_artifact_and_lookup;
      Alcotest.test_case "compilation hash differs by target" `Quick test_cas_compilation_hash_differs_by_target;
      Alcotest.test_case "gc removes unreferenced"            `Quick test_cas_gc_removes_unreferenced;
    ]);
    ("scc", [
      Alcotest.test_case "single non-recursive fn"            `Quick test_scc_single_non_recursive;
      Alcotest.test_case "self-recursive is Single"           `Quick test_scc_self_recursive_is_single;
      Alcotest.test_case "mutual recursion is Group"          `Quick test_scc_mutual_recursion_is_group;
      Alcotest.test_case "topological order respected"        `Quick test_scc_topological_order;
    ]);
    ("pipeline", [
      Alcotest.test_case "scc_impl_hash Single"               `Quick test_scc_impl_hash_single;
      Alcotest.test_case "scc_impl_hash Group"                `Quick test_scc_impl_hash_group;
      Alcotest.test_case "hash_module independent fns"        `Quick test_hash_module_independent_fns_two_sccs;
      Alcotest.test_case "cache miss calls compiler"          `Quick test_compile_scc_cache_miss_calls_compiler;
      Alcotest.test_case "cache hit skips compiler"           `Quick test_compile_scc_cache_hit_skips_compiler;
      Alcotest.test_case "returns compiler artifact path"     `Quick test_compile_scc_returns_artifact_path;
      Alcotest.test_case "cache hit returns cached path"      `Quick test_compile_scc_cache_hit_returns_cached_path;
      Alcotest.test_case "changed body causes cache miss"     `Quick test_changed_body_causes_cache_miss;
      Alcotest.test_case "different targets separate entries" `Quick test_different_targets_cause_separate_cache_entries;
    ]);
    ("def_id", [
      Alcotest.test_case "def_id equality via hash"           `Quick test_def_id_equality;
      Alcotest.test_case "ADefRef tag is 0x80"                `Quick test_adefref_serialize_encodes_hash;
      Alcotest.test_case "ADefRef uses hash not name"         `Quick test_adefref_serializes_hash_not_name;
      Alcotest.test_case "ADefRef distinct hash → distinct"   `Quick test_adefref_distinct_hash_produces_distinct_bytes;
      Alcotest.test_case "dep hash change → caller impl_hash" `Quick test_impl_hash_changes_when_dependency_hash_changes;
    ]);
  ]
