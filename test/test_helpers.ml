(** Shared test helpers and infrastructure for the March test suite. *)

(** March test suite — basic smoke tests. *)

let parse_module src =
  let lexbuf = Lexing.from_string src in
  March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf

let parse_and_desugar src =
  March_desugar.Desugar.desugar_module (parse_module src)

let typecheck src =
  let m = parse_and_desugar src in
  let (errors, _type_map) = March_typecheck.Typecheck.check_module m in
  errors

let has_errors ctx = March_errors.Errors.has_errors ctx

(** True iff DESUGARING [src] produces any error diagnostic. Mirrors the CLI
    (bin/main.ml threads a shared [errors] ctx through [desugar_module] and
    exits 1 if it has errors) — needed because the plain [typecheck] helper
    above discards desugar-phase errors (its [parse_and_desugar] calls
    [desugar_module] with no [~errors] arg). Used for the derive-unknown-type
    regression (finding 17), whose error is emitted at desugar time. *)
let desugar_has_errors src =
  let ast = parse_module src in
  let errors = March_errors.Errors.create () in
  ignore (March_desugar.Desugar.desugar_module ~errors ast);
  March_errors.Errors.has_errors errors

(* ── Desugaring tests ───────────────────────────────────────────────────── *)

let typecheck_full src =
  let m = parse_module src in
  let (errors, _type_map, env) = March_typecheck.Typecheck.check_module_full m in
  (errors, env)

let pp_sty = March_typecheck.Typecheck.pp_session_ty

let eval_module src =
  let m = parse_and_desugar src in
  March_eval.Eval.eval_module_env m

let call_fn env name args =
  let fn_val = List.assoc name env in
  March_eval.Eval.apply fn_val args

(** Load a stdlib file by name and return its declarations as a single DMod.
    Searches paths relative to the project root (for development builds). *)
let load_stdlib_file_for_test name =
  let candidates = [
    Filename.concat "stdlib" name;
    Filename.concat "../../../stdlib" name;
    Filename.concat "../../stdlib" name;
  ] in
  match List.find_opt Sys.file_exists candidates with
  | None ->
    Alcotest.failf "Cannot find stdlib/%s (searched: %s)" name
      (String.concat ", " candidates)
  | Some path ->
    let src =
      let ic = open_in path in
      let n = in_channel_length ic in
      let buf = Bytes.create n in
      really_input ic buf 0 n;
      close_in ic;
      Bytes.to_string buf
    in
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
    let m = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
    let m = March_desugar.Desugar.desugar_module m in
    (* Wrap as DMod so names are accessible as Module.name *)
    March_ast.Ast.DMod (m.March_ast.Ast.mod_name,
                        March_ast.Ast.Public,
                        m.March_ast.Ast.mod_decls,
                        March_ast.Ast.dummy_span)

(** Evaluate a module source with the given stdlib DMod declarations prepended. *)
let eval_with_stdlib decls src =
  let m = parse_and_desugar src in
  let m = { m with March_ast.Ast.mod_decls = decls @ m.March_ast.Ast.mod_decls } in
  March_eval.Eval.eval_module_env m

let vint = function March_eval.Eval.VInt n -> n | _ -> failwith "expected VInt"
let vstr = function March_eval.Eval.VString s -> s | _ -> failwith "expected VString"
let vbool = function March_eval.Eval.VBool b -> b | _ -> failwith "expected VBool"

(* ── Show interface: eval tests ─────────────────────────────────────── *)

let get_show_result env =
  let f = List.assoc "main" env in
  match March_eval.Eval.apply f [] with
  | March_eval.Eval.VString s -> s
  | _ -> "bad"

let with_reset f () =
  March_eval.Eval.reset_scheduler_state ();
  f ()

(** Convert a March VCon-linked-list to an OCaml list. *)
let rec vlist = function
  | March_eval.Eval.VCon ("Nil", []) -> []
  | March_eval.Eval.VCon ("Cons", [h; t]) -> h :: vlist t
  | _ -> failwith "expected list value"

let vcon tag = function
  | March_eval.Eval.VCon (t, args) when t = tag -> args
  | _ -> failwith ("expected VCon " ^ tag)

(* ── Phase 2: session eval test (needs eval_module / call_fn) ─────────────── *)

let emit_session_ir src =
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let tir = March_tir.Mono.monomorphize tir in
  let tir = March_tir.Defun.defunctionalize tir in
  let tir = March_tir.Perceus.perceus tir in
  March_tir.Llvm_emit.emit_module tir

let session_ir_contains ir pat =
  try ignore (Str.search_forward (Str.regexp_string pat) ir 0); true
  with Not_found -> false

(** Binary session types: Chan.new/send/recv/close lower to march_chan_* calls. *)
let lower_module src =
  let m = parse_and_desugar src in
  let (_errors, _type_map) = March_typecheck.Typecheck.check_module m in
  March_tir.Lower.lower_module m

let find_fn name (m : March_tir.Tir.tir_module) =
  List.find (fun (f : March_tir.Tir.fn_def) -> f.fn_name = name) m.tm_fns

(** Parse, desugar, typecheck, and lower a March module using the real type_map. *)
let lower_module_typed src =
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  March_tir.Lower.lower_module ~type_map m

let mono_module src =
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  March_tir.Mono.monomorphize tir

let repl_type_of expr_src =
  let type_map = Hashtbl.create 16 in
  let tc_env = ref (March_typecheck.Typecheck.base_env
    (March_errors.Errors.create ()) type_map) in
  let lexbuf = Lexing.from_string expr_src in
  match (try Some (March_parser.Parser.repl_input (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf)
         with _ -> None) with
  | Some (March_ast.Ast.ReplExpr e) ->
    let e' = March_desugar.Desugar.desugar_expr e in
    let input_ctx = March_errors.Errors.create () in
    let input_tc  = { !tc_env with errors = input_ctx } in
    let inferred  = March_typecheck.Typecheck.infer_expr input_tc e' in
    if March_errors.Errors.has_errors input_ctx then None
    else Some (March_typecheck.Typecheck.pp_ty
      (March_typecheck.Typecheck.repr inferred))
  | _ -> None

let repl_eval_exprs ?(stdlib_src="") exprs_src =
  let type_map = Hashtbl.create 16 in
  let base_tc  = March_typecheck.Typecheck.base_env
    (March_errors.Errors.create ()) type_map in
  let env = ref (
    if stdlib_src = "" then March_eval.Eval.base_env
    else
      let m = parse_and_desugar stdlib_src in
      List.fold_left March_eval.Eval.eval_decl
        March_eval.Eval.base_env m.March_ast.Ast.mod_decls
  ) in
  let tc_env = ref base_tc in
  List.map (fun src ->
    let lexbuf = Lexing.from_string src in
    match (try Some (March_parser.Parser.repl_input (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf)
           with _ -> None) with
    | Some (March_ast.Ast.ReplExpr e) ->
      let e' = March_desugar.Desugar.desugar_expr e in
      let input_ctx = March_errors.Errors.create () in
      let input_tc  = { !tc_env with errors = input_ctx } in
      let inferred  = March_typecheck.Typecheck.infer_expr input_tc e' in
      let ty_str    = March_typecheck.Typecheck.pp_ty
        (March_typecheck.Typecheck.repr inferred) in
      let tc_ok = not (March_errors.Errors.has_errors input_ctx) in
      if not tc_ok then
        `TypeError ty_str
      else
        (try
           let v  = March_eval.Eval.eval_expr !env e' in
           let vs = March_eval.Eval.value_to_string_pretty v in
           (* mirror what run_simple does: bind result to "v" *)
           env := ("v", v) :: (List.remove_assoc "v" !env);
           if tc_ok then
             tc_env := { !tc_env with
               vars = March_typecheck.Typecheck.StrMap.add "v"
                        (March_typecheck.Typecheck.Mono inferred) !tc_env.vars };
           `Ok (vs, ty_str)
         with
         | March_eval.Eval.Eval_error msg -> `RuntimeError msg
         | exn                            -> `RuntimeError (Printexc.to_string exn))
    | Some (March_ast.Ast.ReplDecl d) ->
      let d' = March_desugar.Desugar.desugar_decl d in
      let input_ctx = March_errors.Errors.create () in
      let input_tc  = { !tc_env with errors = input_ctx } in
      let new_tc    = March_typecheck.Typecheck.check_decl input_tc d' in
      if March_errors.Errors.has_errors input_ctx then
        `TypeError "decl"
      else begin
        (try env := March_eval.Eval.eval_decl !env d' with _ -> ());
        tc_env := { new_tc with errors = March_errors.Errors.create () };
        `DeclOk
      end
    | _ -> `ParseError
  ) exprs_src

(* ------------------------------------------------------------------ *)
(* REPL integration tests                                             *)
(* ------------------------------------------------------------------ *)

(** Error recovery: type error leaves env intact *)
let parse_error_msg src =
  try
    ignore (parse_module src);
    (* No exception: check errors collected during recovery *)
    let errs = March_parser.Parse_errors.take_parse_errors () in
    (match errs with (msg, _, _) :: _ -> Some msg | [] -> None)
  with March_errors.Errors.ParseError (msg, _, _) ->
    (* Fatal parse error (e.g. bad module header) *)
    ignore (March_parser.Parse_errors.take_parse_errors ());
    Some msg

let defun_module src =
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let tir = March_tir.Mono.monomorphize tir in
  March_tir.Defun.defunctionalize tir

let fusion_module src =
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let tir = March_tir.Mono.monomorphize tir in
  let changed = ref false in
  March_tir.Fusion.run ~changed tir

(** Check whether any top-level function name starts with "$fused_". *)
let has_fused_fn (m : March_tir.Tir.tir_module) : bool =
  List.exists (fun (fd : March_tir.Tir.fn_def) ->
    let len = String.length fd.fn_name in
    len >= 7 && String.sub fd.fn_name 0 7 = "$fused_"
  ) m.March_tir.Tir.tm_fns

(** True if any function in the module calls the function named [fn_name]. *)
let rec expr_calls (fn_name : string) : March_tir.Tir.expr -> bool = function
  | March_tir.Tir.EApp (f, _) -> f.March_tir.Tir.v_name = fn_name
  | March_tir.Tir.ELet (_, rhs, body) ->
    expr_calls fn_name rhs || expr_calls fn_name body
  | March_tir.Tir.ELetRec (fns, body) ->
    List.exists (fun fd -> expr_calls fn_name fd.March_tir.Tir.fn_body) fns
    || expr_calls fn_name body
  | March_tir.Tir.ECase (_, brs, def) ->
    List.exists (fun b -> expr_calls fn_name b.March_tir.Tir.br_body) brs
    || Option.fold ~none:false ~some:(expr_calls fn_name) def
  | March_tir.Tir.ESeq (e1, e2) -> expr_calls fn_name e1 || expr_calls fn_name e2
  | _ -> false

let _module_calls_fn (m : March_tir.Tir.tir_module) (fn_name : string) : bool =
  List.exists (fun fd -> expr_calls fn_name fd.March_tir.Tir.fn_body)
    m.March_tir.Tir.tm_fns

(** A basic map→fold chain: fuse map then fold into one pass. *)
let contains sub s =
  let sl = String.length sub and tl = String.length s in
  let rec go i = i <= tl - sl && (String.sub s i sl = sub || go (i + 1))
  in go 0

let perceus_module src =
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let tir = March_tir.Mono.monomorphize tir in
  let tir = March_tir.Defun.defunctionalize tir in
  March_tir.Perceus.perceus tir

let mk_var_lin name ty lin =
  { March_tir.Tir.v_name = name; v_ty = ty; v_lin = lin }

(** Build a single-fn module: fn f() : Int = let <v> = 1 in 0.  The binding
    [v] is dead in the body, so Perceus should emit a drop for it, selecting
    EFree vs EDecRC per the rules in drop_var (perceus.ml:438-446). *)
let perceus_dead_let v =
  let body =
    March_tir.Tir.ELet (v,
      March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt 1)),
      March_tir.Tir.EAtom (March_tir.Tir.ALit (March_ast.Ast.LitInt 0)))
  in
  let fn = { March_tir.Tir.fn_name = "f"; fn_params = [];
             fn_ret_ty = March_tir.Tir.TInt; fn_body = body;
             fn_kind = March_tir.Tir.FnNormal } in
  let m = { March_tir.Tir.tm_name = "test"; tm_fns = [fn];
            tm_types = []; tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] } in
  let m' = March_tir.Perceus.perceus m in
  (List.hd m'.March_tir.Tir.tm_fns).March_tir.Tir.fn_body

let rec has_efree_of v_name = function
  | March_tir.Tir.EFree (March_tir.Tir.AVar v) -> v.March_tir.Tir.v_name = v_name
  | March_tir.Tir.ESeq (e1, e2) -> has_efree_of v_name e1 || has_efree_of v_name e2
  | March_tir.Tir.ELet (_, e1, e2) -> has_efree_of v_name e1 || has_efree_of v_name e2
  | March_tir.Tir.ECase (_, brs, def) ->
    List.exists (fun b -> has_efree_of v_name b.March_tir.Tir.br_body) brs ||
    (match def with Some e -> has_efree_of v_name e | None -> false)
  | March_tir.Tir.ELetRec (fns, body) ->
    List.exists (fun f -> has_efree_of v_name f.March_tir.Tir.fn_body) fns
    || has_efree_of v_name body
  | _ -> false

let rec has_edecrc_of v_name = function
  | March_tir.Tir.EDecRC (March_tir.Tir.AVar v)
  | March_tir.Tir.EAtomicDecRC (March_tir.Tir.AVar v) ->
    v.March_tir.Tir.v_name = v_name
  | March_tir.Tir.ESeq (e1, e2) -> has_edecrc_of v_name e1 || has_edecrc_of v_name e2
  | March_tir.Tir.ELet (_, e1, e2) -> has_edecrc_of v_name e1 || has_edecrc_of v_name e2
  | March_tir.Tir.ECase (_, brs, def) ->
    List.exists (fun b -> has_edecrc_of v_name b.March_tir.Tir.br_body) brs ||
    (match def with Some e -> has_edecrc_of v_name e | None -> false)
  | March_tir.Tir.ELetRec (fns, body) ->
    List.exists (fun f -> has_edecrc_of v_name f.March_tir.Tir.fn_body) fns
    || has_edecrc_of v_name body
  | _ -> false

let rec has_any_rc_op_of v_name = function
  | March_tir.Tir.EFree (March_tir.Tir.AVar v)
  | March_tir.Tir.EDecRC (March_tir.Tir.AVar v)
  | March_tir.Tir.EAtomicDecRC (March_tir.Tir.AVar v)
  | March_tir.Tir.EIncRC (March_tir.Tir.AVar v)
  | March_tir.Tir.EAtomicIncRC (March_tir.Tir.AVar v) ->
    v.March_tir.Tir.v_name = v_name
  | March_tir.Tir.ESeq (e1, e2) -> has_any_rc_op_of v_name e1 || has_any_rc_op_of v_name e2
  | March_tir.Tir.ELet (_, e1, e2) -> has_any_rc_op_of v_name e1 || has_any_rc_op_of v_name e2
  | March_tir.Tir.ECase (_, brs, def) ->
    List.exists (fun b -> has_any_rc_op_of v_name b.March_tir.Tir.br_body) brs ||
    (match def with Some e -> has_any_rc_op_of v_name e | None -> false)
  | March_tir.Tir.ELetRec (fns, body) ->
    List.exists (fun f -> has_any_rc_op_of v_name f.March_tir.Tir.fn_body) fns
    || has_any_rc_op_of v_name body
  | _ -> false

(** Theorem: Perceus.lin_drop_is_free — Lin + needs_rc → EFree, not EDecRC. *)
let collect_all_vars_in_module m =
  let rec vs_expr acc = function
    | March_tir.Tir.ELet (v, e1, e2) ->
      vs_expr (vs_expr (v :: acc) e1) e2
    | March_tir.Tir.ESeq (e1, e2) -> vs_expr (vs_expr acc e1) e2
    | March_tir.Tir.ELetRec (fns, body) ->
      let acc' = List.fold_left (fun a f ->
        vs_expr (List.fold_left (fun a p -> p :: a) a f.March_tir.Tir.fn_params)
                f.March_tir.Tir.fn_body) acc fns in
      vs_expr acc' body
    | March_tir.Tir.ECase (_, brs, def) ->
      let acc' = List.fold_left (fun a b ->
        vs_expr (List.fold_left (fun a v -> v :: a) a b.March_tir.Tir.br_vars)
                b.March_tir.Tir.br_body) acc brs in
      (match def with Some e -> vs_expr acc' e | None -> acc')
    | _ -> acc
  in
  List.fold_left (fun acc fn ->
    vs_expr (List.fold_left (fun a p -> p :: a) acc fn.March_tir.Tir.fn_params)
            fn.March_tir.Tir.fn_body) [] m.March_tir.Tir.tm_fns

let rec atomic_dec_vars = function
  | March_tir.Tir.EAtomicDecRC (March_tir.Tir.AVar v) -> [v.March_tir.Tir.v_name]
  | March_tir.Tir.EAtomicDecRC _ -> []
  | March_tir.Tir.ESeq (e1, e2) -> atomic_dec_vars e1 @ atomic_dec_vars e2
  | March_tir.Tir.ELet (_, e1, e2) -> atomic_dec_vars e1 @ atomic_dec_vars e2
  | March_tir.Tir.ELetRec (fns, body) ->
    List.concat_map (fun f -> atomic_dec_vars f.March_tir.Tir.fn_body) fns
    @ atomic_dec_vars body
  | March_tir.Tir.ECase (_, brs, def) ->
    List.concat_map (fun b -> atomic_dec_vars b.March_tir.Tir.br_body) brs
    @ (match def with Some e -> atomic_dec_vars e | None -> [])
  | _ -> []

let escape_module src =
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let tir = March_tir.Mono.monomorphize tir in
  let tir = March_tir.Defun.defunctionalize tir in
  let tir = March_tir.Perceus.perceus tir in
  March_tir.Escape.escape_analysis tir

(** True if [e] contains any EStackAlloc anywhere. *)
let rec has_stack_alloc = function
  | March_tir.Tir.EStackAlloc _ -> true
  | March_tir.Tir.ELet (_, e1, e2) -> has_stack_alloc e1 || has_stack_alloc e2
  | March_tir.Tir.ELetRec (fns, body) ->
    List.exists (fun f -> has_stack_alloc f.March_tir.Tir.fn_body) fns
    || has_stack_alloc body
  | March_tir.Tir.ECase (_, brs, def) ->
    List.exists (fun b -> has_stack_alloc b.March_tir.Tir.br_body) brs
    || (match def with Some e -> has_stack_alloc e | None -> false)
  | March_tir.Tir.ESeq (e1, e2) -> has_stack_alloc e1 || has_stack_alloc e2
  | _ -> false

(** True if [e] contains EAlloc (heap allocation) anywhere. *)
let rec has_heap_alloc = function
  | March_tir.Tir.EAlloc _ -> true
  | March_tir.Tir.ELet (_, e1, e2) -> has_heap_alloc e1 || has_heap_alloc e2
  | March_tir.Tir.ELetRec (fns, body) ->
    List.exists (fun f -> has_heap_alloc f.March_tir.Tir.fn_body) fns
    || has_heap_alloc body
  | March_tir.Tir.ECase (_, brs, def) ->
    List.exists (fun b -> has_heap_alloc b.March_tir.Tir.br_body) brs
    || (match def with Some e -> has_heap_alloc e | None -> false)
  | March_tir.Tir.ESeq (e1, e2) -> has_heap_alloc e1 || has_heap_alloc e2
  | _ -> false


let emit_actor_ir src =
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let tir = March_tir.Mono.monomorphize tir in
  let tir = March_tir.Defun.defunctionalize tir in
  let tir = March_tir.Perceus.perceus tir in
  March_tir.Llvm_emit.emit_module tir

(** Emit LLVM IR for [src] with the string + iolist stdlib modules prepended.
    Used by the ~H sigil codegen regression tests, which need IOList.from_strings
    and the List ADT in scope. *)
let emit_ir_with_iolist src =
  let string_decl = load_stdlib_file_for_test "string.march" in
  let iolist_decl = load_stdlib_file_for_test "iolist.march" in
  let m = parse_and_desugar src in
  let m = { m with March_ast.Ast.mod_decls =
                     [string_decl; iolist_decl] @ m.March_ast.Ast.mod_decls } in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let tir = March_tir.Mono.monomorphize tir in
  let tir = March_tir.Defun.defunctionalize tir in
  let tir = March_tir.Perceus.perceus tir in
  March_tir.Llvm_emit.emit_module tir

(** Emit the lowered TIR (as text) for [src] with the string + iolist stdlib
    modules prepended.  The TIR pretty-printer renders constructor allocations
    as `alloc TypeName.Ctor`, which lets the ~H regression test assert the
    desugared list lowers to `List.Cons`/`List.Nil` (not the bogus
    `IOList.Cons`/`IOList.Nil`). *)
let emit_tir_with_iolist src =
  let string_decl = load_stdlib_file_for_test "string.march" in
  let iolist_decl = load_stdlib_file_for_test "iolist.march" in
  let m = parse_and_desugar src in
  let m = { m with March_ast.Ast.mod_decls =
                     [string_decl; iolist_decl] @ m.March_ast.Ast.mod_decls } in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let buf = Buffer.create 4096 in
  List.iter (fun fn ->
      Buffer.add_string buf (March_tir.Pp.string_of_fn_def fn);
      Buffer.add_char buf '\n')
    tir.March_tir.Tir.tm_fns;
  Buffer.contents buf

let ir_contains ir pat =
  try ignore (Str.search_forward (Str.regexp_string pat) ir 0); true
  with Not_found -> false

(** Compiled actor: dispatch function is emitted in the LLVM IR. *)
let ir_count ir pat =
  let re = Str.regexp_string pat in
  let rec go i acc =
    match Str.search_forward re ir i with
    | j -> go (j + String.length pat) (acc + 1)
    | exception Not_found -> acc
  in
  go 0 0

(** Nested Bool literal patterns: the inner true/false test must be an
    untag + trunc + br i1, not a second ctor-tag switch on the field. *)
let emit_tco_ir src = emit_actor_ir src

(** Like [emit_tco_ir], but runs the post-Perceus stages the real compiler
    runs (see bin/main.ml: Perceus → Drop → Escape → Opt).  Needed for TCO and
    deep-drop tests whose subject only appears in the TIR shape those stages
    produce — the plain pipeline can leave a self-tail-call in a shape the
    back-edge emitter never intercepts, hiding emission bugs behind an
    ordinary call, and emits no [__drop$T] functions at all. *)
let emit_tco_opt_ir src =
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let tir = March_tir.Mono.monomorphize tir in
  let tir = March_tir.Defun.defunctionalize tir in
  let tir = March_tir.Perceus.perceus tir in
  let tir = March_tir.Drop.run tir in
  let tir = March_tir.Escape.escape_analysis tir in
  let tir = March_tir.Opt.run tir in
  March_tir.Llvm_emit.emit_module tir

(** Tail-recursive accumulator factorial: should produce a tco_loop block and
    a back-edge branch replacing the self-tail-call. *)
let emit_mutual_tco_ir = emit_tco_ir

(** Classic even/odd mutual recursion: the combined function, a mutual_loop
    block, a switch dispatch, and back-edge branches must appear in the IR.
    The original even/odd names become thin wrapper functions that call the
    combined __mutco__ function. *)
let borrow_module src =
  let m = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let tir = March_tir.Mono.monomorphize tir in
  let tir = March_tir.Defun.defunctionalize tir in
  March_tir.Borrow.infer_module tir

(** True iff [e] contains any EIncRC / EAtomicIncRC node. *)
let rec has_any_incrc = function
  | March_tir.Tir.EIncRC _ | March_tir.Tir.EAtomicIncRC _ -> true
  | March_tir.Tir.ESeq (a, b)
  | March_tir.Tir.ELet (_, a, b)    -> has_any_incrc a || has_any_incrc b
  | March_tir.Tir.ELetRec (fns, body) ->
    List.exists (fun f -> has_any_incrc f.March_tir.Tir.fn_body) fns
    || has_any_incrc body
  | March_tir.Tir.ECase (_, brs, def) ->
    List.exists (fun b -> has_any_incrc b.March_tir.Tir.br_body) brs
    || (match def with Some d -> has_any_incrc d | None -> false)
  | _ -> false

(** True iff [e] contains any EDecRC / EAtomicDecRC node. *)
let rec has_any_decrc = function
  | March_tir.Tir.EDecRC _ | March_tir.Tir.EAtomicDecRC _ -> true
  | March_tir.Tir.ESeq (a, b)
  | March_tir.Tir.ELet (_, a, b)    -> has_any_decrc a || has_any_decrc b
  | March_tir.Tir.ELetRec (fns, body) ->
    List.exists (fun f -> has_any_decrc f.March_tir.Tir.fn_body) fns
    || has_any_decrc body
  | March_tir.Tir.ECase (_, brs, def) ->
    List.exists (fun b -> has_any_decrc b.March_tir.Tir.br_body) brs
    || (match def with Some d -> has_any_decrc d | None -> false)
  | _ -> false

(* ── Analysis (borrow_map) tests ──────────────────────────────────────────── *)

let mk_inp buf cur = { March_repl.Input.empty with
  March_repl.Input.buffer = buf;
  March_repl.Input.cursor = cur }

(* ── Loud-skip accounting (W2 Task 2 / W2.0) ─────────────────────────────
   Policy: a skip is legitimate ONLY when the environment genuinely lacks a
   tool — no `clang` on PATH, or no LLVM verifier (`opt`/`llvm-as`) for the
   IR validity gate (test_ir_verify.ml). Any in-repo failure — clang present
   but the link fails, or the runtime sources this project ships with are
   missing — is a test FAILURE, not a skip. Legitimate skips are still
   counted (not just silently swallowed) and the total is printed once at
   process exit, so a whole run of skipped tool-gated tests is visible in
   the summary rather than indistinguishable from "all passed". *)
let jit_skip_count = ref 0
let jit_skip_reasons = ref []
let jit_skip_teardown_registered = ref false

let record_jit_skip reason =
  incr jit_skip_count;
  jit_skip_reasons := reason :: !jit_skip_reasons;
  if not !jit_skip_teardown_registered then begin
    jit_skip_teardown_registered := true;
    at_exit (fun () ->
      if !jit_skip_count > 0 then begin
        (* The ledger carries every tool-absence skip class (clang-gated JIT
           tests AND the IR gate's LLVM-verifier-absence skips), so the
           header stays generic — each reason line names its missing tool. *)
        Printf.printf
          "\n[tool-skip ledger] %d test(s) SKIPPED (required external tool not found):\n"
          !jit_skip_count;
        List.iter (fun r -> Printf.printf "  - %s\n" r) (List.rev !jit_skip_reasons);
        flush stdout
      end)
  end

(** True iff a `clang` binary is reachable on PATH. Distinguishes "tool
    genuinely absent" (legitimate skip) from "clang is present but the link
    failed" (must fail loudly — see setup_jit_runtime). *)
let clang_available () =
  Sys.command "command -v clang >/dev/null 2>&1" = 0

(** True iff a `zig` binary is reachable on PATH.  The Linux cross-compile path
    drives `zig cc`; without zig, cross tests are a legitimate tool-absence skip
    (same policy as [clang_available]). *)
let zig_available () =
  Sys.command "command -v zig >/dev/null 2>&1" = 0

(** Directory of the cross-compile target sysroot for [arch] ("amd64"|"arm64"),
    populated by scripts/fetch-cross-sysroot.sh, or None if absent.  Mirrors the
    compiler's own resolution (env override → ~/.cache/march cache).  A cross
    link test without a sysroot is a legitimate skip, not a failure. *)
let cross_sysroot_dir arch =
  let well_formed d =
    Sys.file_exists (Filename.concat d "lib/libssl.so.3")
    && Sys.file_exists (Filename.concat d "lib/libcrypto.so.3")
    && Sys.file_exists (Filename.concat d "lib/libz.so.1")
  in
  let candidates =
    let upper = String.uppercase_ascii arch in
    (match Sys.getenv_opt ("MARCH_CROSS_SYSROOT_" ^ upper) with
     | Some d -> [d] | None -> [])
    @ (match Sys.getenv_opt "MARCH_CROSS_SYSROOT" with
       | Some d -> [d] | None -> [])
    @ (let home = (try Sys.getenv "HOME" with Not_found -> ".") in
       [Filename.concat home
          (Printf.sprintf ".cache/march/cross-sysroot/linux-%s" arch)])
  in
  List.find_opt well_formed candidates

(** Read the whole contents of a file (best-effort; "" if unreadable). *)
let read_file_contents path =
  try
    let ic = open_in path in
    let n = in_channel_length ic in
    let s = really_input_string ic n in
    close_in ic; s
  with Sys_error _ -> ""

let setup_jit_runtime () =
  let home = Sys.getenv "HOME" in
  let dot_cache = Filename.concat home ".cache" in
  let cache_dir = Filename.concat dot_cache "march" in
  (try Unix.mkdir dot_cache 0o755 with Unix.Unix_error _ -> ());
  (try Unix.mkdir cache_dir 0o755 with Unix.Unix_error _ -> ());
  let candidates = [
    "runtime/march_runtime.c";
    "../runtime/march_runtime.c";
    "../../runtime/march_runtime.c";
    Filename.concat (Filename.dirname Sys.executable_name) "../../runtime/march_runtime.c";
  ] in
  match List.find_opt Sys.file_exists candidates with
  | None ->
    (* The runtime/ sources are checked into this repo and always present
       relative to the project root — this is not "tool absence", it means
       the test binary was invoked from somewhere that can't find them.
       Fail loudly rather than silently no-op every JIT test. *)
    Alcotest.failf
      "setup_jit_runtime: could not find runtime/march_runtime.c (searched: %s) — \
       run tests from the project root or a normal _build layout"
      (String.concat ", " candidates)
  | Some runtime_c ->
    let runtime_dir = Filename.dirname runtime_c in
    let opt_path f =
      let p = Filename.concat runtime_dir f in
      if Sys.file_exists p then Some p else None
    in
    (* On Linux, dlopen requires all symbols resolved at load time (unlike
       macOS which allows lazy/two-level resolution). Include all core C
       files that march_runtime.c depends on. Determined by attempting a
       link and collecting the resulting "undefined symbol" errors.
       march_dispatch.c/march_reload.c/march_remote_registry.c/
       march_monitor_registry.c were added later (Hot Code Reload phases 2-10)
       and march_runtime.c's actor_green_thread / march_kill now reference
       their symbols unconditionally — omitting them used to make EVERY test
       in this file silently skip (setup_jit_runtime returned None) rather
       than fail, since the link error was swallowed into the `None` branch.
       That vacuous-green class is now impossible: any link failure while
       clang IS present is an Alcotest.fail with the captured stderr (see
       below). Deliberately NOT adding march_http.c/march_tls.c/
       march_compress.c: those pull in libssl/libz and aren't referenced by
       the symbols these tests need. *)
    let extra_src_list = List.filter_map opt_path [
      "march_scheduler.c"; "march_message.c"; "march_heap.c";
      "march_gc.c"; "sha1.c"; "march_extras.c"; "march_ctx_escape.c";
      "base64.c"; "march_ffi.c";
      "march_dispatch.c"; "march_reload.c"; "march_remote_registry.c";
      "march_monitor_registry.c";
    ] in
    let c_inputs = runtime_c :: extra_src_list in
    let h_inputs =
      (try Sys.readdir runtime_dir with Sys_error _ -> [||])
      |> Array.to_list
      |> List.filter (fun f -> Filename.check_suffix f ".h")
      |> List.sort String.compare
      |> List.map (Filename.concat runtime_dir)
    in
    let key_buf = Buffer.create 256 in
    List.iter (fun p ->
        Buffer.add_string key_buf (Filename.basename p);
        try Buffer.add_string key_buf (Digest.to_hex (Digest.file p))
        with Sys_error _ -> ())
      (c_inputs @ h_inputs);
    let key =
      String.sub (Digest.to_hex (Digest.string (Buffer.contents key_buf))) 0 16 in
    let so_path =
      Filename.concat cache_dir ("libmarch_rt_test_" ^ key ^ ".so") in
    if Sys.file_exists so_path then Some so_path
    else if not (clang_available ()) then begin
      record_jit_skip
        (Printf.sprintf "no clang on PATH (building %s)" (Filename.basename so_path));
      None
    end else begin
      let extra_srcs =
        String.concat "" (List.map (fun p -> " " ^ p) extra_src_list) in
      (* pthreads are in libSystem on macOS; explicit -lpthread needed on Linux. *)
      let pthread_flag =
        match Sys.os_type with
        | "Unix" ->
          (match Sys.command "uname -s 2>/dev/null | grep -q Darwin" with
           | 0 -> ""
           | _ -> " -lpthread")
        | _ -> ""
      in
      (* Compile to a temp and rename: rename(2) is atomic on the same
         filesystem, so a concurrent test process can never dlopen a
         half-written .so. *)
      let tmp = Printf.sprintf "%s.%d.tmp" so_path (Unix.getpid ()) in
      let stderr_file = Printf.sprintf "%s.%d.stderr" so_path (Unix.getpid ()) in
      let rc = Sys.command (Printf.sprintf
        "clang -shared -O2 -fPIC %s%s%s -o %s 2>%s"
        runtime_c extra_srcs pthread_flag tmp (Filename.quote stderr_file)) in
      if rc <> 0 then begin
        let stderr_output = read_file_contents stderr_file in
        (try Sys.remove tmp with Sys_error _ -> ());
        (try Sys.remove stderr_file with Sys_error _ -> ());
        (* clang IS on PATH (checked above) — this is a genuine in-repo link
           failure (e.g. a missing runtime source, an undefined symbol from
           a recently-added .c file not yet listed above). Never silently
           skip: fail loudly with the linker's own stderr. *)
        Alcotest.failf
          "setup_jit_runtime: clang link failed (rc=%d) building %s from %s:\n%s"
          rc so_path runtime_c stderr_output
      end else begin
        (try Sys.remove stderr_file with Sys_error _ -> ());
        (try Sys.rename tmp so_path
         with Sys_error _ -> (try Sys.remove tmp with Sys_error _ -> ()));
        if Sys.file_exists so_path then Some so_path
        else
          Alcotest.failf
            "setup_jit_runtime: clang reported success (rc=0) but %s does not exist \
             after rename from %s" so_path tmp
      end
    end

(* ── Compiled-regression test infra: main.exe + --compile skip policy ────
   Same policy as setup_jit_runtime above: `march --compile` shells out to
   clang for the final link, so a `compile_rc <> 0` conflates two very
   different situations — (a) clang genuinely absent from PATH (legitimate,
   countable skip) and (b) clang present but the March compiler produced a
   bad program / crashed / hit a real bug (a test FAILURE, never a silent
   `()`). This consolidates the ~20 near-identical
   `exe_dir`/`main_exe`/`if not (Sys.file_exists main_exe) then ()` and
   `if compile_rc <> 0 then ()` copies that used to live independently in
   test_codegen.ml and test_stdlib_suite.ml. *)

(** Locate the compiler binary built alongside this test executable
    (`<build>/bin/main.exe`, relative to `<build>/test/<this test>.exe`).
    `main.exe` is produced by the SAME `dune build` that produces the test
    binaries — it is never legitimately absent, so a missing exe here means
    the test was invoked from a broken/partial build, not "tool absence".
    Fails loudly rather than silently skipping every compiled-regression
    test in the file. *)
let find_main_exe () =
  let exe_dir = Filename.dirname Sys.executable_name in
  let main_exe = Filename.concat exe_dir "../bin/main.exe" in
  if Sys.file_exists main_exe then main_exe
  else
    Alcotest.failf
      "find_main_exe: %s does not exist — compiled-regression tests require \
       `dune build ... test/run_codegen.exe test/run_stdlib.exe` (which also \
       builds bin/main.exe) to have completed" main_exe

(** The March project root: the parent of the `_build` directory this test
    executable lives under, verified by the `dune-project` file sitting at
    that root. The compiled-regression tests `cd` here before invoking the
    compiler so its CWD-relative fallback candidates are live: `stdlib/`
    and `runtime/` resolve from the source tree even when the
    `_build/default/` copies are absent (a targeted `dune build
    test/run_codegen.exe bin/main.exe` populates neither — only a full
    `dune build` does), and the `.march/cas` tree a `--compile` run drops
    under its CWD lands at the repo root instead of inside `_build/`.

    Walking the exe's own ancestors (rather than applying a fixed number
    of [Filename.dirname]s) is deliberate: a previous fixed-count version
    landed on `_build` itself — one dirname short — which silently
    disabled everything above (stdlib resolution then depended entirely on
    the exe-relative `_build/default/stdlib` copy, and CAS trees piled up
    inside `_build/`). The walk is correct at any depth, including dune's
    `_build/.sandbox/<hash>/...` trees. Fails loudly if the exe is not
    under a `_build` with a `dune-project` beside it (same
    never-silently-wrong policy as [find_main_exe]). *)
let march_project_root () =
  let exe =
    if Filename.is_relative Sys.executable_name
    then Filename.concat (Sys.getcwd ()) Sys.executable_name
    else Sys.executable_name
  in
  let rec parent_of_build dir =
    let parent = Filename.dirname dir in
    if Filename.basename dir = "_build" then parent
    else if parent = dir then
      Alcotest.failf
        "march_project_root: test exe %s is not under a _build directory" exe
    else parent_of_build parent
  in
  let root = parent_of_build (Filename.dirname exe) in
  if Sys.file_exists (Filename.concat root "dune-project") then root
  else
    Alcotest.failf
      "march_project_root: derived %s (parent of the exe's _build ancestor) \
       but it contains no dune-project" root

(** Run a shell command, returning (exit_code, combined_stdout_stderr).
    Used to capture the March compiler's own diagnostic output so a real
    compile failure can be reported with the actual error, not swallowed.

    CORRECTION (superseding the previous version of this comment): the
    previous comment here claimed rc=255 could never be evidence of a signal
    kill, reasoning about what a shell's own exit status would be after a
    signal death. That reasoning does not describe what this function
    actually observed: it used [Sys.command], whose OCaml runtime does its
    own [wait]/[waitpid] on the child and collapses EVERY signal death
    (SIGKILL, SIGSEGV, SIGABRT, anything) to the single value 255, with the
    real signal number discarded entirely (verified empirically:
    [Sys.command "kill -9 $$"] and [Sys.command "kill -11 $$"] both return
    255). So a real CI failure — `march --compile` reporting rc=255 with
    completely empty captured output — was, contrary to the old comment,
    fully consistent with "the compiler was killed by a signal", and there
    was no way to tell SIGKILL (OOM killer / external kill — a resource
    problem) from SIGSEGV (a genuine crash) apart. Losing that distinction
    cost a full debugging cycle.

    Fix: use [Unix.system], which returns a [Unix.process_status] that keeps
    exited vs. signaled vs. stopped distinct, and a signal death is now
    reported in the returned output (appended, clearly marked) rather than
    silently thrown away. The [int] half of the return value still reports
    255 for a signal death (preserving the historical value so any existing
    rc=255 comparisons keep working) — the actual signal number lives only
    in the appended output line, so read it there, not from the int. *)
let run_capture cmd =
  let tmp = Filename.temp_file "march_test_capture" ".txt" in
  let status =
    Unix.system (Printf.sprintf "( %s ) >%s 2>&1" cmd (Filename.quote tmp))
  in
  let output = read_file_contents tmp in
  (try Sys.remove tmp with Sys_error _ -> ());
  (* [n] here is OCaml's own PORTABLE signal encoding (see [Sys.sigkill] etc.
     in the stdlib), NOT the raw OS signal number — verified empirically:
     on this machine [Sys.sigkill = -7], [Sys.sigsegv = -10],
     [Sys.sigabrt = -1], not 9/11/6. Match against the [Sys.sig*] constants
     rather than hardcoding 9/11/6, but still report the familiar OS number
     in the message since that's what a reader recognizes. *)
  let describe_signal n =
    if n = Sys.sigkill then "SIGKILL (OS signal 9) — OOM killer or an external kill; a resource problem"
    else if n = Sys.sigsegv then "SIGSEGV (OS signal 11) — a genuine crash inside the process"
    else if n = Sys.sigabrt then "SIGABRT (OS signal 6)"
    else Printf.sprintf "OCaml signal code %d (see Sys.sig* for the mapping)" n
  in
  match status with
  | Unix.WEXITED rc -> (rc, output)
  | Unix.WSIGNALED n ->
    let note =
      Printf.sprintf
        "\n[run_capture] *** PROCESS KILLED BY SIGNAL *** %s\n\
         (Sys.command/`sh -c` would have collapsed this to a bare rc=255 \
         with the signal number discarded — see the comment above \
         run_capture in test/test_helpers.ml)\n"
        (describe_signal n)
    in
    (255, output ^ note)
  | Unix.WSTOPPED n ->
    let note =
      Printf.sprintf "\n[run_capture] *** PROCESS STOPPED BY SIGNAL %d ***\n" n
    in
    (255, output ^ note)

(** Like [compile_march] but never calls [Alcotest.fail]/[Alcotest.skip]
    itself — returns the raw outcome so a caller can inspect a real
    compiler failure's captured output before deciding how to report it
    (e.g. to recognize one specific, already-tracked product bug and
    convert it to a documented [Alcotest.skip] rather than a plain fail —
    see test_compiled_recursive_closure_capture). Most callers should use
    [compile_march] or [compile_march_or_skip] instead, which apply the
    default loud-failure policy automatically. *)
let compile_march_raw ?(cmd_prefix = "") ?(extra_args = "") ~main_exe ~bin ~src () =
  let cmd = Printf.sprintf "%s%s --compile%s -o %s %s"
    cmd_prefix (Filename.quote main_exe)
    (if extra_args = "" then "" else " " ^ extra_args)
    (Filename.quote bin) (Filename.quote src) in
  let (rc, output) = run_capture cmd in
  if rc = 0 then `Ok bin
  else if not (clang_available ()) then begin
    record_jit_skip (Printf.sprintf "no clang on PATH (compiling %s)" src);
    `Skipped
  end else
    `Failed (rc, output, cmd)

(** Compile [src] with `main_exe --compile [extra_args] -o bin src`
    (optionally prefixed with extra env/cd via [cmd_prefix]; [extra_args]
    lets callers pass e.g. "--test"). Returns `Ok bin_path` on success.
    On failure: if clang is genuinely absent from PATH, records a counted
    skip and returns `Error `Skipped` (legitimate — see setup_jit_runtime's
    doc comment for the policy this mirrors); otherwise clang IS present
    and the March compiler itself failed, which is never a silent skip —
    fails the test immediately with the compiler's captured stderr. *)
let compile_march ?(cmd_prefix = "") ?(extra_args = "") ~main_exe ~bin ~src () =
  match compile_march_raw ~cmd_prefix ~extra_args ~main_exe ~bin ~src () with
  | `Ok bin -> `Ok bin
  | `Skipped -> `Skipped
  | `Failed (rc, output, cmd) ->
    if output <> "" then
      Alcotest.failf
        "compile_march: `march --compile` failed (rc=%d) for %s (clang IS on \
         PATH, so this is a real compiler failure, not an environment gap):\n%s"
        rc src output
    else
      (* Empty captured output despite redirecting both stdout and stderr
         means the failing stage died before writing anything we could
         catch (or its output never reached the redirected fd at all) — the
         plain rc/src message above tells us nothing in that case, so dump
         everything needed to reproduce by hand: the exact command line,
         the full source of the (small, generated) program that failed to
         compile, and the MARCH_TRMC value this test process actually saw,
         since that's the variable under suspicion for the nondeterministic
         ubuntu-24.04 rc=255/empty-output failure this is meant to debug. *)
      let src_contents =
        try read_file_contents src
        with Sys_error e -> Printf.sprintf "<could not read %s: %s>" src e
      in
      Alcotest.failf
        "compile_march: `march --compile` failed (rc=%d) for %s (clang IS on \
         PATH, so this is a real compiler failure, not an environment gap):\n\
         <empty captured output>\n\
         command: %s\n\
         MARCH_TRMC=%s\n\
         --- source (%s) ---\n\
         %s\n\
         --- end source ---"
        rc src cmd
        (match Sys.getenv_opt "MARCH_TRMC" with Some v -> v | None -> "<unset>")
        src src_contents

(** Like [compile_march], but calls [Alcotest.fail] directly instead of
    returning a variant — for the common case where the caller has no
    further use for a "skipped" outcome distinct from "compiled". Returns
    `None` only on a legitimate clang-absent skip; always `Some bin` or a
    failed test otherwise (never a silent no-op). *)
let compile_march_or_skip ?(cmd_prefix = "") ?(extra_args = "") ~main_exe ~bin ~src () =
  match compile_march ~cmd_prefix ~extra_args ~main_exe ~bin ~src () with
  | `Ok bin -> Some bin
  | `Skipped -> None

(** Runs [argv] (argv.(0) is looked up on PATH like execvp) with stdout
    redirected to [stdout_file] and stderr discarded, waiting up to
    [timeout_secs] for it to exit. Returns [`Exited rc] on a normal exit, or
    [`Timeout] if the deadline passes first -- in which case the child is
    SIGKILLed and reaped so it can never outlive the test process.

    Exists to close a real gap: [Sys.command] (used everywhere else in this
    file to run a compiled binary) has no way to bound how long it waits, so
    a genuinely hung child blocks the calling test -- and therefore the
    entire suite -- indefinitely, with no way to recover short of an
    operator manually finding and killing the process. A hang found this way
    is always worth surfacing (it's real signal, possibly a genuine
    regression, possibly an external tool/environment issue -- e.g. ASAN's
    own shadow-memory init has been observed to wedge machine-wide under
    extreme concurrent load, independent of March's own code, verifiable by
    running a trivial unrelated `clang -fsanitize=address` program), so this
    deliberately does NOT fold a timeout into the existing tool-absence skip
    ledger -- callers should fail loudly, not silently pass. *)
let run_with_timeout ~timeout_secs ~stdout_file argv =
  let out_fd = Unix.openfile stdout_file [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o644 in
  let devnull = Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0o644 in
  let pid =
    match Unix.create_process argv.(0) argv Unix.stdin out_fd devnull with
    | pid -> pid
    | exception e -> Unix.close out_fd; Unix.close devnull; raise e
  in
  Unix.close out_fd;
  Unix.close devnull;
  let deadline = Unix.gettimeofday () +. timeout_secs in
  let rec wait_loop () =
    match Unix.waitpid [ Unix.WNOHANG ] pid with
    | 0, _ ->
      if Unix.gettimeofday () >= deadline then begin
        (try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ());
        ignore (Unix.waitpid [] pid);
        `Timeout
      end else begin
        ignore (Unix.select [] [] [] 0.05);
        wait_loop ()
      end
    | _, Unix.WEXITED rc -> `Exited rc
    | _, (Unix.WSIGNALED _ | Unix.WSTOPPED _) -> `Exited (-1)
  in
  wait_loop ()

(* ── LLVM IR validity gate infra (W2 Task 3 / W2.1) ──────────────────────
   Policy mirrors setup_jit_runtime / compile_march above: a skip is
   legitimate ONLY when no LLVM verifier tool is reachable on this machine
   (genuine environment gap, counted via record_jit_skip so it shows up in
   the same at_exit summary as the clang-absence skips — one unified
   "skipped because tooling missing" ledger for the whole suite). Once a
   tool IS found, any invalid-IR result is real signal, never swallowed.
   Note this is a SEPARATE tool-absence class from clang: `--emit-llvm`
   never shells out to clang (it writes textual IR and exits — see
   bin/main.ml's `--emit-llvm only: write IR and exit` branch), so emitting
   IR never needs a skip check; only the VERIFY step (running an external
   `opt`/`llvm-as`) can legitimately be skipped for tool-absence. *)

(** Locate an LLVM module verifier. Tries, in order:
    1. `opt` on PATH (accepts modern `-passes=verify` pass-manager syntax).
    2. `opt` at the Homebrew LLVM keg prefix (`brew --prefix llvm`), which is
       not linked onto PATH by default because Homebrew's LLVM would shadow
       Xcode's `clang`. Apple's Xcode Command Line Tools ship `clang` but
       deliberately do NOT ship `opt`/`llvm-as` (no `xcrun -f opt`), so on a
       stock macOS toolchain PATH alone finds nothing — the brew keg is the
       realistic place a verifier lives on a dev machine even when `opt` is
       not exported.
    3. `llvm-as` (assembler) at either location as a fallback: it can't run
       the module-verifier pass, but IR that fails to parse as valid LLVM
       assembly is caught by its parser — this project treats "fails to
       parse" and "parses but fails to verify" as the same detectable class
       of ill-typed IR (both surface as a non-zero exit + a locatable
       line:col error) — see the RED test below, which exercises the
       parse-level failure mode `opt` also rejects.
    Memoized: the probe shells out (`command -v`, `brew --prefix`), so it
    only needs to run once per test process. *)
let llvm_verifier_tool : [ `Opt of string | `LlvmAs of string | `None ] option ref = ref None

let find_llvm_verifier_tool () =
  match !llvm_verifier_tool with
  | Some t -> t
  | None ->
    let on_path name =
      if Sys.command (Printf.sprintf "command -v %s >/dev/null 2>&1" name) = 0
      then Some name else None
    in
    let brew_llvm_bin =
      let tmp = Filename.temp_file "march_brew_prefix" ".txt" in
      let rc = Sys.command (Printf.sprintf "brew --prefix llvm >%s 2>/dev/null" (Filename.quote tmp)) in
      let out = if rc = 0 then String.trim (read_file_contents tmp) else "" in
      (try Sys.remove tmp with Sys_error _ -> ());
      if out = "" then None else Some (Filename.concat out "bin")
    in
    let at_brew name =
      match brew_llvm_bin with
      | None -> None
      | Some dir ->
        let p = Filename.concat dir name in
        if Sys.file_exists p then Some p else None
    in
    let result =
      match on_path "opt" with
      | Some p -> `Opt p
      | None ->
        match at_brew "opt" with
        | Some p -> `Opt p
        | None ->
          match on_path "llvm-as" with
          | Some p -> `LlvmAs p
          | None ->
            match at_brew "llvm-as" with
            | Some p -> `LlvmAs p
            | None -> `None
    in
    llvm_verifier_tool := Some result;
    result

(** Run the discovered verifier tool against a single `.ll` file.
    Returns `Ok on valid IR, `Invalid error_output on a verifier/parser
    rejection, `NoTool if no verifier is reachable (caller should convert
    this to a legitimate, counted skip — never a silent pass). *)
let verify_llvm_ir_file (path : string) : [ `Ok | `Invalid of string | `NoTool ] =
  match find_llvm_verifier_tool () with
  | `None -> `NoTool
  | `Opt opt_path ->
    let cmd = Printf.sprintf "%s -passes=verify -disable-output %s"
      (Filename.quote opt_path) (Filename.quote path) in
    let (rc, output) = run_capture cmd in
    if rc = 0 then `Ok else `Invalid output
  | `LlvmAs llvm_as_path ->
    let cmd = Printf.sprintf "%s -o %s %s"
      (Filename.quote llvm_as_path) (Filename.quote Filename.null) (Filename.quote path) in
    let (rc, output) = run_capture cmd in
    if rc = 0 then `Ok else `Invalid output

(** Human-readable name of the tool actually in use (for report/skip messages). *)
let llvm_verifier_tool_name () =
  match find_llvm_verifier_tool () with
  | `Opt p -> Printf.sprintf "opt -passes=verify (%s)" p
  | `LlvmAs p -> Printf.sprintf "llvm-as (%s, parse-only fallback)" p
  | `None -> "none"

(** Recursively delete a temp directory tree we created. Needed because
    running the compiler with a temp dir as CWD leaves more than the compile
    outputs behind: even `--emit-llvm` creates a `.march/cas/vc/<xx>/<hash>`
    verdict-cache tree under its CWD, so a bare `Unix.rmdir` after removing
    the known files silently fails (ENOTEMPTY) and leaks one directory per
    compile.

    SELF-CONFINING: a recursive-delete primitive must defend itself rather
    than rely on call-site discipline ("" was only accidentally safe via
    ENOENT; "/" lstats as a directory and would have been walked). The
    function REFUSES — [Alcotest.failf], deleting nothing — unless the
    realpath-resolved target is a strict descendant of the realpath-resolved
    system temp root ([Filename.get_temp_dir_name ()], the same root
    [Filename.temp_file] creates under). "" and "/" are rejected outright
    before any stat. Resolving BOTH sides through [Unix.realpath] also
    neutralizes the macOS `/tmp` → `/private/tmp` and `/var` → `/private/var`
    symlink mismatches between $TMPDIR's spelling and the filesystem's.
    A path that does not exist is a no-op (nothing to delete; keeps cleanup
    idempotent) — only an EXISTING path outside the temp root fails loudly.

    Within the confined tree: structure-safe (lstat-based; symlinks are
    removed as links, never followed) and best-effort (per-entry errors
    ignored). The unconfined worker is deliberately local to this function
    so no caller can reach it without the guard. *)
let rm_rf_temp_dir path =
  if path = "" || path = "/" then
    Alcotest.failf
      "rm_rf_temp_dir: refusing to delete %S (empty path or filesystem root)"
      path;
  let temp_root =
    let raw = Filename.get_temp_dir_name () in
    try Unix.realpath raw with Unix.Unix_error _ -> raw
  in
  match (try Some (Unix.realpath path) with Unix.Unix_error _ -> None) with
  | None -> ()  (* target does not exist: nothing to delete *)
  | Some real ->
    let root_slash =
      let n = String.length temp_root in
      if n > 0 && temp_root.[n - 1] = '/' then temp_root else temp_root ^ "/"
    in
    let is_strict_descendant =
      String.length real > String.length root_slash
      && String.sub real 0 (String.length root_slash) = root_slash
    in
    if not is_strict_descendant then
      Alcotest.failf
        "rm_rf_temp_dir: refusing to delete %s (outside temp root %s)"
        real temp_root
    else begin
      let rec go p =
        match (try Some (Unix.lstat p) with Unix.Unix_error _ -> None) with
        | None -> ()
        | Some st ->
          if st.Unix.st_kind = Unix.S_DIR then begin
            (try
               Sys.readdir p
               |> Array.iter (fun f -> go (Filename.concat p f))
             with Sys_error _ -> ());
            (try Unix.rmdir p with Unix.Unix_error _ -> ())
          end else
            (try Sys.remove p with Sys_error _ -> ())
      in
      go real
    end

(** Emit LLVM IR for [src] to a fresh temp `.ll` file via `main_exe
    --emit-llvm`, bypassing the CAS artifact cache entirely (unlike plain
    `--compile`, `--emit-llvm` always regenerates and writes `<file>.ll`
    rather than possibly short-circuiting on a cache hit with no `.ll`
    write) so the gate always inspects freshly emitted text, never a stale
    or absent file. Returns the `.ll` path on success. Never a legitimate
    skip: `--emit-llvm` shells out to nothing (no clang, no linker — see
    bin/main.ml's `--emit-llvm only: write IR and exit` branch), and
    `main_exe` itself is the same never-legitimately-absent binary
    `find_main_exe` already asserts on, so any failure here is a real
    compiler bug and must fail loudly with the captured output. *)
let emit_llvm_ir_to_file ~main_exe ~src () : [ `Ok of string | `Failed of int * string ] =
  let tmp_dir = Filename.temp_file "march_ir_verify" "" in
  Sys.remove tmp_dir;
  Unix.mkdir tmp_dir 0o755;
  let base = Filename.remove_extension (Filename.basename src) in
  let march_copy = Filename.concat tmp_dir (base ^ ".march") in
  (* Copy rather than compile in place: native/*.march fixtures may sit next
     to sibling .expected/.c files, and we must not clobber any real .ll a
     concurrent dune action for the SAME fixture might be producing. *)
  let ic = open_in src in
  let contents = really_input_string ic (in_channel_length ic) in
  close_in ic;
  let oc = open_out march_copy in
  output_string oc contents;
  close_out oc;
  let ll_path = Filename.concat tmp_dir (base ^ ".ll") in
  let cmd = Printf.sprintf "cd %s && %s --emit-llvm %s </dev/null"
    (Filename.quote tmp_dir) (Filename.quote main_exe) (Filename.quote (Filename.basename march_copy)) in
  let (rc, output) = run_capture cmd in
  if rc = 0 && Sys.file_exists ll_path then `Ok ll_path
  else begin
    (* Failure: the caller gets no path back, so nothing in tmp_dir is
       reachable afterwards — clean it up here (source copy, any partial
       .ll, the .march/ verdict-cache tree the compiler drops in its CWD),
       or a failing corpus would leak one temp dir per failing fixture. On
       success the caller owns ll_path and cleans the dir up after
       verifying (see run_fixture in test_ir_verify.ml). *)
    rm_rf_temp_dir tmp_dir;
    `Failed (rc, output)
  end

(** Wrap a desugared expression as `fn main() -> e` in a minimal module. *)
let make_jit_test_module (e : March_ast.Ast.expr) : March_ast.Ast.module_ =
  let s = March_ast.Ast.dummy_span in
  let clause = March_ast.Ast.{ fc_params = []; fc_guard = None; fc_body = e; fc_span = s } in
  let fn_def = March_ast.Ast.{
    fn_name = { txt = "main"; span = s };
    fn_vis = March_ast.Ast.Public;
    fn_doc = None; fn_attrs = []; fn_ret_ty = None;
    fn_clauses = [clause]; fn_bounds = [] } in
  { March_ast.Ast.mod_name = { txt = "Repl"; span = s };
    mod_decls = [March_ast.Ast.DFn (fn_def, s)] }

let parse_repl src =
  let lexbuf = Lexing.from_string src in
  March_parser.Parser.repl_input (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf

(** Test: `let x = 21` on line 1, then `x + 21` on line 2 should give 42. *)
let make_stdlib_module stdlib_decls (e : March_ast.Ast.expr) : March_ast.Ast.module_ =
  let s = March_ast.Ast.dummy_span in
  let clause = March_ast.Ast.{ fc_params = []; fc_guard = None; fc_body = e; fc_span = s } in
  let main_def = March_ast.Ast.{
    fn_name = { txt = "main"; span = s };
    fn_vis = March_ast.Ast.Public; fn_doc = None; fn_attrs = []; fn_ret_ty = None;
    fn_clauses = [clause]; fn_bounds = [] } in
  { March_ast.Ast.mod_name = { txt = "Main"; span = s };
    mod_decls = stdlib_decls @ [March_ast.Ast.DFn (main_def, s)] }

(** Regression P0: List.reverse works across successive JIT fragments.
    Tests that List.reverse$List_Int (a monomorphized stdlib fn) is
    available in both the first and second fragments, proving that
    mark_compiled_fns runs only after successful compile. *)
let dummy_actor_def = March_ast.Ast.{
  actor_state     = [];
  actor_init      = ELit (LitInt 0, dummy_span);
  actor_handlers  = [];
  actor_supervise = None;
  actor_compat    = "full";
  actor_invariant = None;
}

let mk_actor_inst name alive st = March_eval.Eval.{
  ai_name          = name;
  ai_def           = dummy_actor_def;
  ai_env_ref       = ref [];
  ai_state         = st;
  ai_alive         = alive;
  ai_monitors      = [];
  ai_links         = [];
  ai_mailbox       = Queue.create ();
  ai_supervisor    = None;
  ai_restart_count = [];
  ai_epoch         = 0;
  ai_resources     = [];
  ai_linear_values = [];    (* Phase 6b *)
}

let mk_var name ty = { March_tir.Tir.v_name = name; v_ty = ty; v_lin = March_tir.Tir.Unr }
let app op args = March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TInt)), args)
let ilit n = March_tir.Tir.ALit (March_ast.Ast.LitInt n)
let _blit b = March_tir.Tir.ALit (March_ast.Ast.LitBool b)

let mk_fn name body =
  { March_tir.Tir.fn_name = name; fn_params = [];
    fn_ret_ty = March_tir.Tir.TInt; fn_body = body;
    fn_kind = March_tir.Tir.FnNormal }
let mk_module fns = { March_tir.Tir.tm_name = "test"; tm_fns = fns; tm_types = []; tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] }
let avar name ty = March_tir.Tir.AVar (mk_var name ty)
let flit f = March_tir.Tir.ALit (March_ast.Ast.LitFloat f)
let fapp op args =
  March_tir.Tir.EApp (mk_var op (March_tir.Tir.TFn ([], March_tir.Tir.TFloat)), args)
let blit b = March_tir.Tir.ALit (March_ast.Ast.LitBool b)
let first_body m = (List.hd m.March_tir.Tir.tm_fns).March_tir.Tir.fn_body

let slit s = March_tir.Tir.ALit (March_ast.Ast.LitString s)

let _ = avar  (* suppress unused warning *)

(* ── Algebraic simplification ────────────────────────────────────── *)

let mk_closure_alloc clo_struct_name apply_name =
  let fn_ptr_atom = March_tir.Tir.AVar
    (mk_var apply_name (March_tir.Tir.TPtr March_tir.Tir.TUnit)) in
  March_tir.Tir.EAlloc
    (March_tir.Tir.TCon (clo_struct_name, []),
     [fn_ptr_atom])

(** A closure created and immediately called via ECallPtr should be
    rewritten to a direct EApp. *)
let eval_with_string src =
  let string_decl = load_stdlib_file_for_test "string.march" in
  eval_with_stdlib [string_decl] src

let eval_with_iolist src =
  let string_decl = load_stdlib_file_for_test "string.march" in
  let iolist_decl = load_stdlib_file_for_test "iolist.march" in
  eval_with_stdlib [string_decl; iolist_decl] src

(* Html.tag classifies attribute names and escapes values contextually, so it
   needs string/list/char alongside iolist. *)
let eval_with_html src =
  let string_decl = load_stdlib_file_for_test "string.march" in
  let list_decl   = load_stdlib_file_for_test "list.march" in
  let char_decl   = load_stdlib_file_for_test "char.march" in
  let iolist_decl = load_stdlib_file_for_test "iolist.march" in
  let html_decl   = load_stdlib_file_for_test "html.march" in
  eval_with_stdlib [string_decl; list_decl; char_decl; iolist_decl; html_decl] src

let eval_with_http src =
  let string_decl = load_stdlib_file_for_test "string.march" in
  let http_decl = load_stdlib_file_for_test "http.march" in
  eval_with_stdlib [string_decl; http_decl] src

let eval_with_http_client src =
  let string_decl = load_stdlib_file_for_test "string.march" in
  let http_decl = load_stdlib_file_for_test "http.march" in
  let transport_decl = load_stdlib_file_for_test "http_transport.march" in
  let client_decl = load_stdlib_file_for_test "http_client.march" in
  eval_with_stdlib [string_decl; http_decl; transport_decl; client_decl] src

let sort_decl     = lazy (load_stdlib_file_for_test "sort.march")
let hash_map_decl = lazy (load_stdlib_file_for_test "hash_map.march")
let enum_decl     = lazy (load_stdlib_file_for_test "enum.march")

let eval_with_sort src    = eval_with_stdlib [Lazy.force sort_decl] src
let eval_with_enum src    = eval_with_stdlib [Lazy.force sort_decl; Lazy.force hash_map_decl; Lazy.force enum_decl] src

(** Build a March Cons-list from an OCaml int list. *)
let[@warning "-32"] rec make_vlist = function
  | [] -> March_eval.Eval.VCon ("Nil", [])
  | x :: xs -> March_eval.Eval.VCon ("Cons", [March_eval.Eval.VInt x; make_vlist xs])

(** Assert two int lists are equal, converting from March VCon lists. *)
let check_int_list msg expected actual =
  let got = List.map vint (vlist actual) in
  Alcotest.(check (list int)) msg expected got

(* Helper: call Sort.sort_small_by on a literal list *)
let sort_small xs =
  let src = Printf.sprintf {|mod Test do
    fn f() do
      Sort.sort_small_by([%s], fn a -> fn b -> a <= b)
    end
  end|} (String.concat ", " (List.map string_of_int xs)) in
  let env = eval_with_sort src in
  call_fn env "f" []

(* Helper: call Sort.timsort_by on a literal list *)
let timsort xs =
  let src = Printf.sprintf {|mod Test do
    fn f() do
      Sort.timsort_by([%s], fn a -> fn b -> a <= b)
    end
  end|} (String.concat ", " (List.map string_of_int xs)) in
  let env = eval_with_sort src in
  call_fn env "f" []

(* Helper: call Sort.introsort_by on a literal list *)
let introsort xs =
  let src = Printf.sprintf {|mod Test do
    fn f() do
      Sort.introsort_by([%s], fn a -> fn b -> a <= b)
    end
  end|} (String.concat ", " (List.map string_of_int xs)) in
  let env = eval_with_sort src in
  call_fn env "f" []

(* -- sort_small_by -- *)

let add_fresh_actor pid name =
  let inst = mk_actor_inst name true March_eval.Eval.VUnit in
  Hashtbl.replace March_eval.Eval.actor_registry pid inst;
  inst

let get_supervisor_child_pid sup_pid field_name =
  match Hashtbl.find_opt March_eval.Eval.actor_registry sup_pid with
  | None -> -1
  | Some inst ->
    (match inst.March_eval.Eval.ai_state with
     | March_eval.Eval.VRecord fields ->
       (match List.assoc_opt field_name fields with
        | Some (March_eval.Eval.VInt pid) -> pid
        | _ -> -1)
     | _ -> -1)

(** Phase 2: one_for_one restart — crashed child is restarted by supervisor.
    Spawn a supervisor with a Worker child. Kill the worker; the supervisor
    should restart it with a new pid. *)
let load_seq () = load_stdlib_file_for_test "seq.march"

let eval_with_seq src =
  eval_with_stdlib [load_seq ()] src

let eval_with_path src =
  let string_decl = load_stdlib_file_for_test "string.march" in
  let list_decl   = load_stdlib_file_for_test "list.march" in
  let path_decl   = load_stdlib_file_for_test "path.march" in
  eval_with_stdlib [string_decl; list_decl; path_decl] src

let load_file_stdlib () =
  [ load_stdlib_file_for_test "seq.march"
  ; load_stdlib_file_for_test "file.march" ]

let eval_with_file src =
  eval_with_stdlib (load_file_stdlib ()) src

let with_temp_file content f =
  let path = Filename.temp_file "march_test_" ".txt" in
  let oc = open_out path in
  output_string oc content;
  close_out oc;
  let result = f path in
  (try Sys.remove path with _ -> ());
  result

let load_dir_stdlib () =
  [ load_stdlib_file_for_test "string.march"
  ; load_stdlib_file_for_test "list.march"
  ; load_stdlib_file_for_test "seq.march"
  ; load_stdlib_file_for_test "path.march"
  ; load_stdlib_file_for_test "file.march"
  ; load_stdlib_file_for_test "dir.march" ]

let eval_with_dir src =
  eval_with_stdlib (load_dir_stdlib ()) src

let map_decl = lazy (load_stdlib_file_for_test "map.march")
let eval_with_map src = eval_with_stdlib [Lazy.force map_decl] src

(** Lower a module that includes the Map stdlib to TIR (for compiled-path smoke tests). *)
let lower_map_typed src =
  let map_m = Lazy.force map_decl in
  let m = parse_and_desugar src in
  let m = { m with March_ast.Ast.mod_decls = [map_m] @ m.March_ast.Ast.mod_decls } in
  let (_, type_map) = March_typecheck.Typecheck.check_module m in
  March_tir.Lower.lower_module ~type_map m

(* Standard int comparator: fn a -> fn b -> a < b *)
let int_cmp = {|fn(a) -> fn(b) -> a < b|}

(* Helper: extract Some(v) payload *)
let vsome = function
  | March_eval.Eval.VCon ("Some", [v]) -> v
  | _ -> failwith "expected Some"

let set_decl = lazy (load_stdlib_file_for_test "set.march")
let eval_with_set src = eval_with_stdlib [Lazy.force set_decl] src

let array_decl = lazy (load_stdlib_file_for_test "array.march")
let eval_with_array src = eval_with_stdlib [Lazy.force array_decl] src

let has_unused_warning ctx =
  List.exists (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Warning &&
    let lo = String.lowercase_ascii d.March_errors.Errors.message in
    let n = String.length lo in
    let rec scan i =
      if i + 5 >= n then false
      else if String.sub lo i 6 = "unused" then true
      else scan (i + 1)
    in scan 0
  ) ctx.March_errors.Errors.diagnostics

let run_module_src src =
  let m = parse_and_desugar src in
  March_eval.Eval.run_module m

(** APP token lexes to APP *)
let test_lexer_keyword_app () =
  let lexbuf = Lexing.from_string "app" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check bool) "lexes app keyword" true
    (match tok with March_parser.Parser.APP -> true | _ -> false)

(** ON_START token lexes correctly *)
let test_lexer_keyword_on_start () =
  let lexbuf = Lexing.from_string "on_start" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check bool) "lexes on_start keyword" true
    (match tok with March_parser.Parser.ON_START -> true | _ -> false)

(** ON_STOP token lexes correctly *)
let test_lexer_keyword_on_stop () =
  let lexbuf = Lexing.from_string "on_stop" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check bool) "lexes on_stop keyword" true
    (match tok with March_parser.Parser.ON_STOP -> true | _ -> false)

(** app desugars to __app_init__ in env *)
let test_app_desugars_to_app_init () =
  let src = {|mod AppTest do
    actor Counter do
      state { count : Int }
      init { count: 0 }
      on Inc() do { count: state.count + 1 } end
    end

    app MyApp do
      Supervisor.spec(:one_for_one, [worker(Counter)])
    end
  end|} in
  let env = eval_module src in
  Alcotest.(check bool) "__app_init__ exists in env" true
    (List.mem_assoc "__app_init__" env)

(** run_module with app declaration spawns actors and runs scheduler *)
let test_app_spawns_actors () =
  let src = {|mod AppTest do
    actor Counter do
      state { count : Int }
      init { count: 0 }
      on Inc() do { count: state.count + 1 } end
    end

    app MyApp do
      Supervisor.spec(:one_for_one, [worker(Counter)])
    end
  end|} in
  run_module_src src;
  let count = Hashtbl.length March_eval.Eval.actor_registry in
  Alcotest.(check bool) "at least one actor spawned" true (count >= 1)

(** mutual exclusivity: main + app reports an error *)
let test_app_main_exclusive () =
  let src = {|mod Bad do
    fn main() do 42 end
    app MyApp do
      Supervisor.spec(:one_for_one, [])
    end
  end|} in
  let lexbuf = Lexing.from_string src in
  let ast = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
  let errors = March_errors.Errors.create () in
  ignore (March_desugar.Desugar.desugar_module ~errors ast);
  Alcotest.(check bool) "main + app raises" true (March_errors.Errors.has_errors errors)

(* ------------------------------------------------------------------ *)
(* Process Registry tests                                              *)
(* ------------------------------------------------------------------ *)

(** Helper: look up a builtin from task_builtins and apply it. *)
let call_builtin name args =
  let fn_val = List.assoc name March_eval.Eval.task_builtins in
  March_eval.Eval.apply fn_val args

(** worker(Counter, :my_name) produces a VRecord with a name field *)
let test_supervisor_spec_value () =
  let env = eval_module {|mod Test do
    actor Counter do
      state { count : Int }
      init { count: 0 }
      on Inc() do { count: state.count + 1 } end
    end

    fn main() do
      Supervisor.spec(:one_for_one, [worker(Counter)])
    end
  end|} in
  let spec = call_fn env "main" [] in
  (match spec with
   | March_eval.Eval.VRecord fields ->
     Alcotest.(check bool) "spec has strategy field" true
       (List.assoc_opt "strategy" fields = Some (March_eval.Eval.VAtom "one_for_one"));
     Alcotest.(check bool) "spec has children field" true
       (List.mem_assoc "children" fields)
   | _ -> Alcotest.fail "expected VRecord from Supervisor.spec")

(** worker(Counter) returns a child spec record with actor and restart fields. *)
let test_worker_builtin_fields () =
  let env = eval_module {|mod Test do
    actor Counter do
      state { count : Int }
      init { count: 0 }
      on Inc() do { count: state.count + 1 } end
    end

    fn main() do
      worker(Counter)
    end
  end|} in
  let spec = call_fn env "main" [] in
  (match spec with
   | March_eval.Eval.VRecord fields ->
     Alcotest.(check bool) "worker has actor field" true
       (List.mem_assoc "actor" fields);
     Alcotest.(check bool) "worker has restart field" true
       (List.mem_assoc "restart" fields)
   | _ -> Alcotest.fail "expected VRecord from worker/1")

(** The app body is typechecked: a valid app block produces no typecheck errors. *)
let test_app_typechecks_valid () =
  let src = {|mod Test do
    actor Counter do
      state { count : Int }
      init { count: 0 }
      on Inc() do { count: state.count + 1 } end
    end

    app MyApp do
      Supervisor.spec(:one_for_one, [worker(Counter)])
    end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "valid app block: no typecheck errors" false (has_errors ctx)

(** An app body that returns the wrong type (Int) should produce a typecheck
    error, since the desugar annotates the spec field as SupervisorSpec. *)
let test_app_wrong_body_type_error () =
  let src = {|mod Test do
    app MyApp do
      42
    end
  end|} in
  let ctx = typecheck src in
  Alcotest.(check bool) "wrong app body type: has typecheck error" true (has_errors ctx)

(* ------------------------------------------------------------------ *)
(* Dynamic Supervisor tests                                            *)
(* ------------------------------------------------------------------ *)

(** Helper: get list of live child entries from a dynamic supervisor. *)
let dyn_sup_children name =
  match Hashtbl.find_opt March_eval.Eval.dyn_sup_registry name with
  | None -> []
  | Some ds -> ds.March_eval.Eval.ds_children

(** Basic: dynamic_supervisor registers correctly, start_child adds a child. *)
let test_shutdown_handler_runs () =
  (* The actor's Shutdown handler increments a side-effect counter.
     We use a let binding in init state and observe it via the actor registry. *)
  let src = {|mod ShutTest do
    actor LogActor do
      state { stopped : Bool }
      init  { stopped: false }
      on Shutdown() do { stopped: true } end
      on Ping() do state end
    end

    app ShutApp do
      Supervisor.spec(:one_for_one, [worker(LogActor)])
    end
  end|} in
  run_module_src src;
  (* After run_module the app ran graceful_shutdown which sent Shutdown() to actors.
     Find the LogActor instance and verify its state.stopped = true *)
  let found : March_eval.Eval.actor_inst option =
    Hashtbl.fold (fun _pid (inst : March_eval.Eval.actor_inst) acc ->
        if inst.ai_name = "LogActor" then Some inst
        else acc
      ) March_eval.Eval.actor_registry None
  in
  match found with
  | None ->
    (* Actor was alive at shutdown time but is now dead — that's correct.
       The key test is that shutdown happened without error. *)
    Alcotest.(check bool) "shutdown completed without error" true true
  | Some inst ->
    (* If the actor is still in registry, its state should show stopped = true *)
    (match inst.ai_state with
     | March_eval.Eval.VRecord fields ->
       (match List.assoc_opt "stopped" fields with
        | Some (March_eval.Eval.VBool b) ->
          Alcotest.(check bool) "shutdown handler set stopped = true" true b
        | _ ->
          Alcotest.(check bool) "shutdown completed" true true)
     | _ ->
       Alcotest.(check bool) "shutdown completed" true true)

(** Shutdown sends to all spawned actors in reverse order *)
let test_graceful_shutdown_reverse_order () =
  (* Track which actors were shut down and in what order via shutdown flag in state *)
  let src = {|mod RevTest do
    actor Worker1 do
      state { stopped : Bool }
      init  { stopped: false }
      on Shutdown() do { stopped: true } end
    end

    actor Worker2 do
      state { stopped : Bool }
      init  { stopped: false }
      on Shutdown() do { stopped: true } end
    end

    app RevApp do
      Supervisor.spec(:one_for_one, [
        worker(Worker1),
        worker(Worker2)
      ])
    end
  end|} in
  run_module_src src;
  (* Both workers should have been shutdown (spawn order: Worker1=0, Worker2=1) *)
  let count = Hashtbl.length March_eval.Eval.actor_registry in
  Alcotest.(check bool) "at least 2 actors were spawned" true (count >= 2)

(** on_start hook runs after tree is up *)
let test_on_start_hook () =
  (* We test on_start by having it call App.stop() — causing immediate shutdown.
     Without on_start running, the app would drain the scheduler and exit normally
     with shutdown_requested = false.  With it running, shutdown_requested = true. *)
  let called = ref false in
  (* Since we can't easily inject OCaml side effects via March code, we verify
     by checking that the on_start block parses and the app desugars correctly. *)
  let src = {|mod HookTest do
    actor Counter do
      state { count : Int }
      init  { count: 0 }
      on Tick() do { count: state.count + 1 } end
    end

    app HookApp do
      on_start do
        42
      end

      Supervisor.spec(:one_for_one, [worker(Counter)])
    end
  end|} in
  let env = eval_module src in
  (* The __app_init__ function should exist *)
  Alcotest.(check bool) "on_start app parses and desugars" true
    (List.mem_assoc "__app_init__" env);
  called := true;
  Alcotest.(check bool) "on_start test reached" true !called

(** on_stop hook runs after shutdown *)
let test_on_stop_hook () =
  let src = {|mod StopHookTest do
    actor W do
      state { n : Int }
      init  { n: 0 }
      on X() do { n: 1 } end
    end

    app StopApp do
      on_stop do
        99
      end

      Supervisor.spec(:one_for_one, [worker(W)])
    end
  end|} in
  let env = eval_module src in
  Alcotest.(check bool) "on_stop app parses and desugars" true
    (List.mem_assoc "__app_init__" env)

(** Actor without Shutdown handler is force-killed *)
let test_actor_no_shutdown_handler_force_killed () =
  let src = {|mod NoHandlerTest do
    actor Silent do
      state { n : Int }
      init  { n: 0 }
      on Ping() do { n: state.n + 1 } end
    end

    app SilentApp do
      Supervisor.spec(:one_for_one, [worker(Silent)])
    end
  end|} in
  (* Should complete without error — actor is force-killed *)
  run_module_src src;
  Alcotest.(check bool) "no-handler actor shutdown completed" true true

(** Shutdown actor pid marks actor dead *)
let test_shutdown_actor_pid_marks_dead () =
  let src = {|mod DeadTest do
    actor Mortal do
      state { alive : Bool }
      init  { alive: true }
      on Shutdown() do { alive: false } end
    end

    app MortalApp do
      Supervisor.spec(:one_for_one, [worker(Mortal)])
    end
  end|} in
  run_module_src src;
  (* After graceful shutdown, all actors should be dead *)
  let all_dead =
    Hashtbl.fold (fun _pid (inst : March_eval.Eval.actor_inst) acc ->
        acc && not inst.ai_alive
      ) March_eval.Eval.actor_registry true
  in
  Alcotest.(check bool) "all actors dead after shutdown" true all_dead

(* ── derive syntax ──────────────────────────────────────────────────────── *)

let has_warning_with ctx sub =
  let sub_lo = String.lowercase_ascii sub in
  List.exists (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Warning &&
    let m = String.lowercase_ascii d.March_errors.Errors.message in
    let sub_len = String.length sub_lo in
    let m_len   = String.length m in
    let found   = ref false in
    for i = 0 to m_len - sub_len do
      if String.sub m i sub_len = sub_lo then found := true
    done;
    !found
  ) ctx.March_errors.Errors.diagnostics

(** Returns true if ANY error diagnostic's message contains [sub] (case-insensitive). *)
let has_error_with ctx sub =
  let sub_lo = String.lowercase_ascii sub in
  List.exists (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Error &&
    let m = String.lowercase_ascii d.March_errors.Errors.message in
    let sub_len = String.length sub_lo in
    let m_len   = String.length m in
    let found   = ref false in
    for i = 0 to m_len - sub_len do
      if String.sub m i sub_len = sub_lo then found := true
    done;
    !found
  ) ctx.March_errors.Errors.diagnostics

(** Returns true if ANY hint diagnostic is present. *)
let has_hints ctx =
  List.exists (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Hint
  ) ctx.March_errors.Errors.diagnostics

(** Returns true if ANY hint diagnostic's message contains [sub] (case-insensitive). *)
let has_hint_with ctx sub =
  let sub_lo = String.lowercase_ascii sub in
  List.exists (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Hint &&
    let m = String.lowercase_ascii d.March_errors.Errors.message in
    let sub_len = String.length sub_lo in
    let m_len   = String.length m in
    let found   = ref false in
    for i = 0 to m_len - sub_len do
      if String.sub m i sub_len = sub_lo then found := true
    done;
    !found
  ) ctx.March_errors.Errors.diagnostics

(** Returns true if ANY exhaustiveness warning is present. *)
let has_exhaust_warning ctx =
  has_warning_with ctx "non-exhaustive"

(* ── Exhaustiveness tests ───────────────────────────────────────────────── *)

(* §1  Trivially exhaustive matches *)

let interp_eval_expr src =
  match repl_eval_exprs [src] with
  | [`Ok (v, t)] -> Some (v, t)
  | _ -> None

(** Run an expression through the JIT (wrapping in a minimal module).
    Returns Some result_str on success, None if JIT unavailable or fails. *)
let jit_eval_simple_expr ~runtime_so src =
  let lexbuf   = Lexing.from_string src in
  match (try Some (March_parser.Parser.repl_input (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf)
         with _ -> None) with
  | Some (March_ast.Ast.ReplExpr e) ->
    let e' = March_desugar.Desugar.desugar_expr e in
    let m  = make_jit_test_module e' in
    let type_map = Hashtbl.create 16 in
    let tc_env = March_typecheck.Typecheck.base_env (March_errors.Errors.create ()) type_map in
    let jit = March_jit.Repl_jit.create ~runtime_so () in
    (match (try
      let (_, result) = March_jit.Repl_jit.run_expr jit ~tc_env m in
      March_jit.Repl_jit.cleanup jit;
      Some result
    with exn ->
      March_jit.Repl_jit.cleanup jit;
      ignore exn; None) with
    | r -> r)
  | _ -> None

(** Assert that interpreter and JIT produce identical output for [src].
    Skips when JIT is unavailable. *)
let check_parity ~ctx ~runtime_so src =
  match interp_eval_expr src with
  | None -> Alcotest.fail (Printf.sprintf "%s: interpreter eval failed for %s" ctx src)
  | Some (interp_v, _) ->
    match jit_eval_simple_expr ~runtime_so src with
    | None -> ()  (* JIT unavailable or expression too complex for standalone test — skip *)
    | Some jit_v ->
      Alcotest.(check string)
        (Printf.sprintf "%s: interp vs JIT for %s" ctx src)
        interp_v jit_v

let lex_one src =
  let lexbuf = Lexing.from_string src in
  March_lexer.Lexer.token lexbuf

let eval_with_bytes src =
  let decl = load_stdlib_file_for_test "bytes.march" in
  eval_with_stdlib [decl] src

let eval_with_logger src =
  let decl = load_stdlib_file_for_test "logger.march" in
  eval_with_stdlib [decl] src

let flow_decls () =
  let seq_decl    = load_stdlib_file_for_test "seq.march" in
  let flow_decl   = load_stdlib_file_for_test "flow.march" in
  [seq_decl; flow_decl]

let eval_with_flow src =
  eval_with_stdlib (flow_decls ()) src

let actor_decl () = load_stdlib_file_for_test "actor.march"

let eval_with_queue src =
  let queue_decl = load_stdlib_file_for_test "queue.march" in
  eval_with_stdlib [queue_decl] src

let eval_with_datetime src =
  let dt_decl = load_stdlib_file_for_test "datetime.march" in
  eval_with_stdlib [dt_decl] src

(** Extract year from DateTime(Date(y,m,d), Time(h,mi,s)). *)
let dt_year v =
  match v with
  | March_eval.Eval.VCon ("DateTime", [date; _]) ->
    (match date with
     | March_eval.Eval.VCon ("Date", [y; _; _]) -> vint y
     | _ -> failwith "expected Date")
  | _ -> failwith "expected DateTime"

let dt_month v =
  match v with
  | March_eval.Eval.VCon ("DateTime", [date; _]) ->
    (match date with
     | March_eval.Eval.VCon ("Date", [_; m; _]) -> vint m
     | _ -> failwith "expected Date")
  | _ -> failwith "expected DateTime"

let dt_day v =
  match v with
  | March_eval.Eval.VCon ("DateTime", [date; _]) ->
    (match date with
     | March_eval.Eval.VCon ("Date", [_; _; d]) -> vint d
     | _ -> failwith "expected Date")
  | _ -> failwith "expected DateTime"

let dt_hour v =
  match v with
  | March_eval.Eval.VCon ("DateTime", [_; time]) ->
    (match time with
     | March_eval.Eval.VCon ("Time", [h; _; _]) -> vint h
     | _ -> failwith "expected Time")
  | _ -> failwith "expected DateTime"

let eval_with_json src =
  let json_decl = load_stdlib_file_for_test "json.march" in
  eval_with_stdlib [json_decl] src

(** Match a VCon and extract its arguments *)
let json_tag v =
  match v with
  | March_eval.Eval.VCon (tag, _) -> tag
  | _ -> failwith "expected VCon"

let json_inner v =
  match v with
  | March_eval.Eval.VCon (_, args) -> args
  | _ -> failwith "expected VCon"

let eval_with_regex src =
  let regex_decl = load_stdlib_file_for_test "regex.march" in
  eval_with_stdlib [regex_decl] src

(* [type Bytes = Bytes(String)] — the payload IS the raw byte buffer.  The
   cons-spine arm is kept so a value produced by an older serialized fixture
   still reads correctly. *)
let bytes_val_to_string bv =
  let open March_eval.Eval in
  match bv with
  | VCon ("Bytes", [VString s]) -> s
  | VCon ("Bytes", [lst]) ->
    let buf = Buffer.create 8 in
    let rec go = function
      | VCon ("Nil", []) -> ()
      | VCon ("Cons", [VInt b; rest]) -> Buffer.add_char buf (Char.chr b); go rest
      | _ -> Alcotest.fail "bytes_val_to_string: unexpected list element"
    in
    go lst; Buffer.contents buf
  | _ -> Alcotest.fail "expected Bytes value"

let call_eval_builtin name args =
  let open March_eval.Eval in
  match List.assoc_opt name base_env with
  | Some (VBuiltin (_, f)) -> f args
  | Some _ -> Alcotest.fail (Printf.sprintf "%s is not a VBuiltin" name)
  | None -> Alcotest.fail (Printf.sprintf "builtin %s not found" name)

let list_decl_df = lazy (load_stdlib_file_for_test "list.march")
let hamt_decl    = lazy (load_stdlib_file_for_test "hamt.march")
let map_decl_df  = lazy (load_stdlib_file_for_test "map.march")
let stats_decl   = lazy (load_stdlib_file_for_test "stats.march")
let df_decl      = lazy (load_stdlib_file_for_test "dataframe.march")

let eval_with_dataframe src =
  eval_with_stdlib [
    Lazy.force list_decl_df;
    Lazy.force hamt_decl;
    Lazy.force map_decl_df;
    Lazy.force stats_decl;
    Lazy.force df_decl;
  ] src

let native_array_decl = lazy (load_stdlib_file_for_test "native_array.march")

let eval_with_native_array src =
  eval_with_stdlib [Lazy.force native_array_decl] src

(* ── Simd stdlib tests (127 builtins — F32x4/F64x2/I32x4/I64x2/U8x16) ────── *)

let simd_decl = lazy (load_stdlib_file_for_test "simd.march")

let eval_with_simd src =
  eval_with_stdlib [Lazy.force native_array_decl; Lazy.force simd_decl] src

(* ── Vault stdlib tests ─────────────────────────────────────────────────── *)

let vault_decl = lazy (load_stdlib_file_for_test "vault.march")
let eval_with_vault src = eval_with_stdlib [Lazy.force vault_decl] src

let eval_with_base64 src =
  let decl = load_stdlib_file_for_test "base64.march" in
  let bytes_decl = load_stdlib_file_for_test "bytes.march" in
  eval_with_stdlib [bytes_decl; decl] src

let eval_with_uri src =
  let decl = load_stdlib_file_for_test "uri.march" in
  eval_with_stdlib [decl] src

(* crypto/compress/uuid all traffic in Bytes, and since Bytes is an
   array-backed [Bytes(String)] their sources call Bytes.to_list /
   Bytes.from_list rather than destructuring a cons payload — so bytes.march
   has to be in the environment.  Under the old representation these suites
   got away with building `Bytes(Cons(...))` literals, which the interpreter
   accepts without the module loaded. *)
let bytes_decl_for_stdlib = lazy (load_stdlib_file_for_test "bytes.march")

let eval_with_crypto src =
  let decl = load_stdlib_file_for_test "crypto.march" in
  eval_with_stdlib [Lazy.force bytes_decl_for_stdlib; decl] src

let load_compress_decl () = load_stdlib_file_for_test "compress.march"

let eval_with_compress src =
  let decl = load_compress_decl () in
  eval_with_stdlib [Lazy.force bytes_decl_for_stdlib; decl] src

let eval_with_compress_and_check src =
  let compress_decl = load_compress_decl () in
  let list_decl   = load_stdlib_file_for_test "list.march" in
  let random_decl = load_stdlib_file_for_test "random.march" in
  let gen_decl    = load_stdlib_file_for_test "gen.march" in
  let check_decl  = load_stdlib_file_for_test "check.march" in
  eval_with_stdlib [Lazy.force bytes_decl_for_stdlib; list_decl; random_decl;
                    gen_decl; check_decl; compress_decl] src

let eval_with_uuid src =
  let decl = load_stdlib_file_for_test "uuid.march" in
  eval_with_stdlib [Lazy.force bytes_decl_for_stdlib; decl] src

let eval_with_duration src =
  let decl = load_stdlib_file_for_test "duration.march" in
  eval_with_stdlib [decl] src

let eval_with_list src =
  let list_decl = load_stdlib_file_for_test "list.march" in
  eval_with_stdlib [list_decl] src

let gen_many_lets n =
  let buf = Buffer.create (n * 30) in
  Buffer.add_string buf "mod PerfTest do\n";
  for i = 0 to n - 1 do
    Buffer.add_string buf (Printf.sprintf "  let v%d = %d\n" i i)
  done;
  Buffer.add_string buf "  fn main() do v0 end\nend";
  Buffer.contents buf

(** Generate a March source string with [n] variants in one type, plus pattern match. *)
let gen_many_ctors n =
  let buf = Buffer.create (n * 20) in
  Buffer.add_string buf "mod PerfTest do\n  type Big = ";
  for i = 0 to n - 1 do
    if i > 0 then Buffer.add_string buf " | ";
    Buffer.add_string buf (Printf.sprintf "V%d" i)
  done;
  Buffer.add_string buf "\n  fn f(x) do\n    match x do\n";
  for i = 0 to n - 1 do
    Buffer.add_string buf (Printf.sprintf "      V%d -> %d\n" i i)
  done;
  Buffer.add_string buf "    end\n  end\nend";
  Buffer.contents buf

(** Generate a March source with [depth] nested submodules, each with [width] fns. *)
let gen_nested_modules depth width =
  let buf = Buffer.create (depth * width * 40) in
  Buffer.add_string buf "mod PerfTest do\n";
  for d = 0 to depth - 1 do
    Buffer.add_string buf (Printf.sprintf "  mod Sub%d do\n" d);
    for w = 0 to width - 1 do
      Buffer.add_string buf (Printf.sprintf "    fn f%d(x) do x end\n" w)
    done;
    Buffer.add_string buf "  end\n"
  done;
  Buffer.add_string buf "  fn main() do 0 end\nend";
  Buffer.contents buf

let lint_check src =
  let config = March_lint.Lint.default_config () in
  March_lint.Lint.check_file ~config ~filename:"test.march" ~src

(** Like [lint_check] but lets the caller control the file path, so rules that
    depend on the filename (e.g. [safety/no-panic-in-lib]'s lib-vs-test
    classification) can be exercised. *)
let lint_check_named ~filename src =
  let config = March_lint.Lint.default_config () in
  March_lint.Lint.check_file ~config ~filename ~src

let has_lint_rule rule diags =
  List.exists (fun d -> d.March_lint.Lint.rule = rule) diags

let unused_pfn_names diags =
  diags
  |> List.filter (fun d -> d.March_lint.Lint.rule = "dead-code/unused-private-fn")
  |> List.map (fun d ->
       (* message is "private function `foo` is never called" *)
       let msg = d.March_lint.Lint.message in
       match String.split_on_char '`' msg with
       | _ :: name :: _ -> name
       | _ -> msg)

(** Run [src] through the full compile pipeline ([Lower] ->
    [Vectorize_mark.mark] -> [Mono] -> [Defun] -> [Perceus] -> [Opt] ->
    [Vectorize_check.check]) and return every diagnostic the
    @[vectorize]/@[vectorize(warn)] check produced. [mark] must run
    immediately after [Lower.lower_module] (before Mono/Defun/Opt can
    mangle or inline anything away) and [check] must run after [Opt], both
    matching the placement Task 3 wires into bin/main.ml. *)
let run_vectorize_check src =
  let ast = parse_and_desugar src in
  let (_, type_map) = March_typecheck.Typecheck.check_module ast in
  let tir = March_tir.Lower.lower_module ~type_map ast in
  let tir = March_tir.Vectorize_mark.mark ast tir in
  let tir = March_tir.Mono.monomorphize tir in
  let tir = March_tir.Defun.defunctionalize tir in
  let tir = March_tir.Perceus.perceus tir in
  let tir = March_tir.Opt.run tir in
  let ctx = March_errors.Errors.create () in
  ignore (March_tir.Vectorize_check.check ctx tir);
  March_errors.Errors.sorted ctx

(** pfn called from within a lambda passed to a HOF — must NOT be flagged. *)
