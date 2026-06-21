(** March TIR → ES module (JavaScript) emission.
    Consumes post-Mono TIR. Defun and Perceus must NOT have run.

    Constructor layout: {$: "CtorName", _0: field0, _1: field1, ...}
    The $ field holds the constructor tag; $ is not a valid March identifier.

    Runtime shim (march_runtime.mjs) must be co-located with the output .mjs.
    M4 will add --runtime-dir to control placement. *)

(* ── Context ─────────────────────────────────────────────────────── *)

type ctx = {
  buf          : Buffer.t;
  mutable indent : int;
  runtime_uses : (string, unit) Hashtbl.t;
  (* runtime function names referenced — imported at top of output *)
}

let create_ctx () = {
  buf          = Buffer.create 4096;
  indent       = 0;
  runtime_uses = Hashtbl.create 16;
}

let use_runtime ctx name = Hashtbl.replace ctx.runtime_uses name ()

(* ── Output helpers ──────────────────────────────────────────────── *)

let emit ctx s = Buffer.add_string ctx.buf s

let emit_indent ctx =
  for _ = 1 to ctx.indent do Buffer.add_string ctx.buf "  " done

let emitl ctx s =
  emit_indent ctx; Buffer.add_string ctx.buf s; Buffer.add_char ctx.buf '\n'

let with_indent ctx f =
  ctx.indent <- ctx.indent + 1; f (); ctx.indent <- ctx.indent - 1

(* ── Name mangling ───────────────────────────────────────────────── *)

(** March qualified names use '.'; JS identifiers cannot. Replace with '$'.
    E.g. "List.map" -> "List$map". *)
let mangle name =
  let b = Bytes.of_string name in
  Bytes.iteri (fun i c -> if c = '.' then Bytes.set b i '$') b;
  Bytes.to_string b

(* ── Atom emission ───────────────────────────────────────────────── *)

let emit_literal ctx lit =
  let open March_ast.Ast in
  match lit with
  | LitInt n    -> emit ctx (string_of_int n)
  | LitFloat f  ->
    let s = string_of_float f in
    emit ctx (if String.contains s '.' || String.contains s 'e' then s else s ^ ".0")
  | LitBool b   -> emit ctx (if b then "true" else "false")
  | LitString s -> emit ctx (Printf.sprintf "%S" s)
  | LitAtom a   -> emit ctx (Printf.sprintf "\":%s\"" a)

let emit_atom ctx = function
  | Tir.AVar v    -> emit ctx (mangle v.Tir.v_name)
  | Tir.ADefRef d -> emit ctx (mangle d.Tir.did_name)
  | Tir.ALit l    -> emit_literal ctx l

(* ── Builtin lowering ────────────────────────────────────────────── *)

(** Binary arithmetic/comparison builtins that inline as JS infix operators. *)
let inline_binop = function
  | "add_int" | "add_float"              -> Some "+"
  | "sub_int" | "sub_float"              -> Some "-"
  | "mul_int" | "mul_float"              -> Some "*"
  | "div_float"                          -> Some "/"
  | "eq_int" | "eq_float" | "eq_bool"
  | "eq_string" | "string_eq"            -> Some "==="
  | "neq_int" | "neq_float" | "neq_bool"
  | "neq_string"                         -> Some "!=="
  | "lt_int" | "lt_float"               -> Some "<"
  | "lte_int" | "lte_float"             -> Some "<="
  | "gt_int" | "gt_float"               -> Some ">"
  | "gte_int" | "gte_float"             -> Some ">="
  | "and_bool"                           -> Some "&&"
  | "or_bool"                            -> Some "||"
  | "string_concat" | "++"              -> Some "+"
  | _                                    -> None

(* ── Scrutinee type helpers ─────────────────────────────────────── *)

let atom_ty = function
  | Tir.AVar v    -> v.Tir.v_ty
  | Tir.ALit (March_ast.Ast.LitInt _)    -> Tir.TInt
  | Tir.ALit (March_ast.Ast.LitFloat _)  -> Tir.TFloat
  | Tir.ALit (March_ast.Ast.LitBool _)   -> Tir.TBool
  | Tir.ALit (March_ast.Ast.LitString _) -> Tir.TString
  | Tir.ALit (March_ast.Ast.LitAtom _)   -> Tir.TCon ("Atom", [])
  | Tir.ADefRef _                         -> Tir.TVar "_"

(** True when the scrutinee requires literal-equality (if/else) rather than
    constructor-tag (switch on .$). *)
let is_literal_scrutinee_ty = function
  | Tir.TBool | Tir.TInt | Tir.TFloat | Tir.TString
  | Tir.TCon ("Atom", []) -> true
  | _ -> false

(** JS comparison RHS for a branch tag in a literal if/else chain.
    lower.ml encodes:
      PatLit(LitInt n)    -> string_of_int n     e.g. "42"
      PatLit(LitBool b)   -> "true" / "false"    (lowercase)
      PatLit(LitString s) -> "\"s\""             (OCaml-quoted)
      PatLit(LitAtom a)   -> ":a"
      ECase on bool (if-lowering) -> "True" / "False"   (uppercase) *)
let literal_tag_js br_tag =
  match br_tag with
  | "True"  | "true"  -> "true"
  | "False" | "false" -> "false"
  | _ when br_tag <> "" && (br_tag.[0] = '-'
                             || (br_tag.[0] >= '0' && br_tag.[0] <= '9')) ->
    br_tag
  | _ when br_tag <> "" && br_tag.[0] = '"' ->
    br_tag  (* already an OCaml string literal including quotes *)
  | _ when br_tag <> "" && br_tag.[0] = ':' ->
    Printf.sprintf "%S" br_tag  (* atom: emit as JS string ":name" *)
  | _ -> Printf.sprintf "%S" br_tag

(* ── Forward declarations ────────────────────────────────────────── *)

let rec emit_val  ctx expr = emit_val_impl  ctx expr
and     emit_stmts ctx expr = emit_stmts_impl ctx expr
and     emit_case  ctx rv expr = emit_case_impl ctx rv expr
and     emit_fn_decl ctx fn = emit_fn_decl_impl ctx fn

(* ── Value emission ──────────────────────────────────────────────── *)

and emit_val_impl ctx expr =
  match expr with
  | Tir.EAtom a -> emit_atom ctx a

  | Tir.EApp (f, args) ->
    let name = f.Tir.v_name in
    begin match inline_binop name with
    | Some op when List.length args = 2 ->
      emit ctx "(";
      emit_atom ctx (List.nth args 0);
      emit ctx (" " ^ op ^ " ");
      emit_atom ctx (List.nth args 1);
      emit ctx ")"
    | _ ->
      begin match name, args with
      | "neg_int",   [a] -> emit ctx "(-"; emit_atom ctx a; emit ctx ")"
      | "neg_float", [a] -> emit ctx "(-"; emit_atom ctx a; emit ctx ")"
      | "not_bool",  [a] -> emit ctx "(!"; emit_atom ctx a; emit ctx ")"
      | "div_int",   [a; b] ->
        emit ctx "Math.trunc("; emit_atom ctx a;
        emit ctx " / "; emit_atom ctx b; emit ctx ")"
      | "mod_int",   [a; b] ->
        emit ctx "("; emit_atom ctx a; emit ctx " % "; emit_atom ctx b; emit ctx ")"
      | "int_to_float", [a] ->
        emit_atom ctx a
      | "float_to_int", [a] | "float_truncate", [a] ->
        emit ctx "Math.trunc("; emit_atom ctx a; emit ctx ")"
      | "int_to_string",   [a] ->
        emit ctx "String("; emit_atom ctx a; emit ctx ")"
      | "bool_to_string",  [a] ->
        emit ctx "String("; emit_atom ctx a; emit ctx ")"
      | "float_to_string", [a] ->
        use_runtime ctx "march_float_to_string";
        emit ctx "march_float_to_string("; emit_atom ctx a; emit ctx ")"
      | ("string_length" | "string_byte_length"), [a] ->
        use_runtime ctx "march_string_byte_length";
        emit ctx "march_string_byte_length("; emit_atom ctx a; emit ctx ")"
      | "string_grapheme_count", [a] ->
        use_runtime ctx "march_string_grapheme_count";
        emit ctx "march_string_grapheme_count("; emit_atom ctx a; emit ctx ")"
      | "string_is_empty", [a] ->
        emit ctx "("; emit_atom ctx a; emit ctx " === \"\")"
      | "println", [a] ->
        emit ctx "console.log("; emit_atom ctx a; emit ctx ")"
      | "print", [a] ->
        use_runtime ctx "march_print";
        emit ctx "march_print("; emit_atom ctx a; emit ctx ")"
      | "print_stderr", [a] ->
        emit ctx "console.error("; emit_atom ctx a; emit ctx ")"
      | ("panic" | "panic_" | "todo_" | "unreachable_"), _ ->
        let msg = if args = [] then "\"panic\""
                  else (let b = Buffer.create 16 in
                        emit_atom { ctx with buf = b } (List.hd args);
                        Buffer.contents b) in
        emit ctx (Printf.sprintf "(() => { throw new Error(%s); })()" msg)
      (* ADT structural equality: eq_TypeName / neq_TypeName *)
      | n, [a; b] when String.length n > 3 && String.sub n 0 3 = "eq_" ->
        let ty = mangle (String.sub n 3 (String.length n - 3)) in
        emit ctx (Printf.sprintf "__eq_%s(" ty);
        emit_atom ctx a; emit ctx ", "; emit_atom ctx b; emit ctx ")"
      | n, [a; b] when String.length n > 4 && String.sub n 0 4 = "neq_" ->
        let ty = mangle (String.sub n 4 (String.length n - 4)) in
        emit ctx (Printf.sprintf "(!__eq_%s(" ty);
        emit_atom ctx a; emit ctx ", "; emit_atom ctx b; emit ctx "))"
      (* Runtime-delegated builtins *)
      | n, _ when (match n with
          | "string_to_int" | "string_to_float" | "string_to_lowercase"
          | "string_to_uppercase" | "string_trim" | "string_trim_start"
          | "string_trim_end" | "string_reverse" | "string_chars"
          | "string_from_chars" | "string_join" | "string_contains"
          | "string_starts_with" | "string_ends_with" | "string_slice"
          | "string_split" | "string_split_first" | "string_replace"
          | "string_replace_all" | "string_repeat" | "string_pad_left"
          | "string_pad_right" | "string_index_of" | "string_last_index_of"
          | "char_from_int" | "byte_to_char" | "char_to_int"
          | "char_is_digit" | "char_is_alphanumeric" | "char_is_whitespace"
          | "list_append" | "list_concat" -> true | _ -> false) ->
        let rt = "march_" ^ n in
        use_runtime ctx rt;
        emit ctx (rt ^ "(");
        List.iteri (fun i a ->
          if i > 0 then emit ctx ", "; emit_atom ctx a) args;
        emit ctx ")"
      (* General call *)
      | _, _ ->
        emit ctx (mangle name ^ "(");
        List.iteri (fun i a ->
          if i > 0 then emit ctx ", "; emit_atom ctx a) args;
        emit ctx ")"
      end
    end

  | Tir.ETuple atoms ->
    emit ctx "[";
    List.iteri (fun i a ->
      if i > 0 then emit ctx ", "; emit_atom ctx a) atoms;
    emit ctx "]"

  | Tir.ERecord fields ->
    emit ctx "({ ";
    List.iteri (fun i (name, a) ->
      if i > 0 then emit ctx ", ";
      emit ctx (name ^ ": "); emit_atom ctx a) fields;
    emit ctx " })"

  | Tir.EField (a, field) ->
    emit_atom ctx a; emit ctx "."; emit ctx field

  | Tir.EUpdate (a, updates) ->
    emit ctx "({ ..."; emit_atom ctx a;
    List.iter (fun (name, v) ->
      emit ctx (", " ^ name ^ ": "); emit_atom ctx v) updates;
    emit ctx " })"

  | Tir.EAlloc (ty, args) ->
    let tag = match ty with Tir.TCon (t, _) -> t | _ -> "_" in
    emit ctx (Printf.sprintf "{ $: %S" tag);
    List.iteri (fun i a ->
      emit ctx (Printf.sprintf ", _%d: " i); emit_atom ctx a) args;
    emit ctx " }"

  | Tir.EStackAlloc (ty, args) ->
    let tag = match ty with Tir.TCon (t, _) -> t | _ -> "_" in
    emit ctx (Printf.sprintf "{ $: %S" tag);
    List.iteri (fun i a ->
      emit ctx (Printf.sprintf ", _%d: " i); emit_atom ctx a) args;
    emit ctx " }"

  (* RC nodes are no-ops in JS *)
  | Tir.EIncRC _ | Tir.EDecRC _ | Tir.EAtomicIncRC _ | Tir.EAtomicDecRC _
  | Tir.EFree _ | Tir.EReuse _ ->
    emit ctx "undefined"

  (* Complex forms in value position: wrap in IIFE *)
  | Tir.ECase _ | Tir.ELet _ | Tir.ELetRec _ | Tir.ESeq _ ->
    emit ctx "(() => {\n";
    ctx.indent <- ctx.indent + 1;
    emit_stmts ctx expr;
    ctx.indent <- ctx.indent - 1;
    emit_indent ctx; emit ctx "})()"

  | Tir.ECallPtr _ ->
    failwith "js_emit: ECallPtr found — Defun must not run before the JS target"

(* ── Statement emission ──────────────────────────────────────────── *)

and emit_stmts_impl ctx expr =
  match expr with

  | Tir.ELet (v, (Tir.ECase _ as case_expr), rest) ->
    (* let v = match ... — emit switch that assigns to v *)
    emitl ctx ("let " ^ mangle v.Tir.v_name ^ ";");
    emit_case ctx (Some (mangle v.Tir.v_name)) case_expr;
    emit_stmts ctx rest

  | Tir.ELet (v, e1, e2) ->
    emit_indent ctx;
    emit ctx ("const " ^ mangle v.Tir.v_name ^ " = ");
    emit_val ctx e1;
    emit ctx ";\n";
    emit_stmts ctx e2

  | Tir.ELetRec (fns, body) ->
    List.iter (emit_fn_decl ctx) fns;
    emit_stmts ctx body

  | Tir.ESeq (e1, e2) ->
    emit_indent ctx;
    emit_val ctx e1;
    emit ctx ";\n";
    emit_stmts ctx e2

  | Tir.ECase _ ->
    emit_case ctx None expr

  (* RC no-ops *)
  | Tir.EIncRC _ | Tir.EDecRC _ | Tir.EAtomicIncRC _ | Tir.EAtomicDecRC _
  | Tir.EFree _ | Tir.EReuse _ -> ()

  | e ->
    emit_indent ctx;
    emit ctx "return ";
    emit_val ctx e;
    emit ctx ";\n"

(* ── ECase: switch / if-else ─────────────────────────────────────── *)

and emit_case_impl ctx result_var expr =
  match expr with
  | Tir.ECase (scrutinee, branches, default) ->
    let s_ty = atom_ty scrutinee in
    (* Helper: emit the result assignment or return for a branch body *)
    let emit_result body =
      match result_var with
      | Some v ->
        emit_indent ctx;
        emit ctx (v ^ " = ");
        emit_val ctx body;
        emit ctx ";\n"
      | None ->
        emit_indent ctx;
        emit ctx "return ";
        emit_val ctx body;
        emit ctx ";\n"
    in
    if is_literal_scrutinee_ty s_ty then begin
      (* Literal/bool: if/else chain *)
      List.iteri (fun i br ->
        if i = 0 then (emit_indent ctx; emit ctx "if (")
        else (emit_indent ctx; emit ctx "} else if (");
        emit_atom ctx scrutinee;
        emit ctx (" === " ^ literal_tag_js br.Tir.br_tag ^ ") {\n");
        with_indent ctx (fun () ->
          (* bind branch vars (rare for literal patterns, but possible) *)
          List.iteri (fun j bv ->
            let scrut_name = match scrutinee with
              | Tir.AVar sv -> mangle sv.Tir.v_name | _ -> "_s" in
            emitl ctx (Printf.sprintf "const %s = %s._%d;"
              (mangle bv.Tir.v_name) scrut_name j)
          ) br.Tir.br_vars;
          emit_result br.Tir.br_body)
      ) branches;
      (match default with
       | Some d ->
         emit_indent ctx; emit ctx "} else {\n";
         with_indent ctx (fun () -> emit_result d);
         emit_indent ctx; emit ctx "}\n"
       | None ->
         if branches <> [] then (emit_indent ctx; emit ctx "}\n"))
    end else begin
      (* Constructor: switch on .$ *)
      emit_indent ctx; emit ctx "switch (";
      emit_atom ctx scrutinee;
      emit ctx ".$) {\n";
      List.iter (fun br ->
        emitl ctx (Printf.sprintf "  case %S: {" br.Tir.br_tag);
        with_indent ctx (fun () ->
          with_indent ctx (fun () ->
            (* Bind constructor fields to br_vars *)
            let scrut_name = match scrutinee with
              | Tir.AVar sv -> mangle sv.Tir.v_name
              | _ ->
                let tmp = "_scrut" in
                emit_indent ctx;
                emit ctx (Printf.sprintf "const %s = " tmp);
                emit_atom ctx scrutinee;
                emit ctx ";\n";
                tmp
            in
            List.iteri (fun i bv ->
              emitl ctx (Printf.sprintf "const %s = %s._%d;"
                (mangle bv.Tir.v_name) scrut_name i)
            ) br.Tir.br_vars;
            (match result_var with
             | Some rv ->
               emit_indent ctx;
               emit ctx (rv ^ " = ");
               emit_val ctx br.Tir.br_body;
               emit ctx ";\n";
               emitl ctx "break;"
             | None ->
               emit_stmts ctx br.Tir.br_body)
          )
        );
        emitl ctx "  }"
      ) branches;
      (match default with
       | Some d ->
         emitl ctx "  default: {";
         with_indent ctx (fun () ->
           with_indent ctx (fun () ->
             match result_var with
             | Some rv ->
               emit_indent ctx; emit ctx (rv ^ " = ");
               emit_val ctx d; emit ctx ";\n";
               emitl ctx "break;"
             | None -> emit_stmts ctx d
           )
         );
         emitl ctx "  }"
       | None -> ());
      emitl ctx "}"
    end
  | _ -> failwith "emit_case: expected ECase"

(* ── Function definition emission ───────────────────────────────── *)

and emit_fn_decl_impl ctx (fn : Tir.fn_def) =
  emit_indent ctx;
  emit ctx ("function " ^ mangle fn.Tir.fn_name ^ "(");
  List.iteri (fun i p ->
    if i > 0 then emit ctx ", ";
    emit ctx (mangle p.Tir.v_name)) fn.Tir.fn_params;
  emit ctx ") {\n";
  with_indent ctx (fun () -> emit_stmts ctx fn.Tir.fn_body);
  emit_indent ctx;
  emit ctx "}\n\n"

(* ── Structural equality ─────────────────────────────────────────── *)

(** Emit a per-type structural equality function __eq_TypeName(a, b). *)
let emit_eq_fn ctx (td : Tir.type_def) =
  let emit_field_cmp fname fty =
    match fty with
    | Tir.TInt | Tir.TFloat | Tir.TBool | Tir.TString ->
      emitl ctx (Printf.sprintf "if (a.%s !== b.%s) return false;" fname fname)
    | Tir.TCon (ty_name, _) ->
      emitl ctx (Printf.sprintf "if (!__eq_%s(a.%s, b.%s)) return false;"
        (mangle ty_name) fname fname)
    | _ ->
      emitl ctx (Printf.sprintf "if (a.%s !== b.%s) return false;" fname fname)
  in
  let emit_field_cmp_idx i fty =
    let fname = Printf.sprintf "_%d" i in
    match fty with
    | Tir.TInt | Tir.TFloat | Tir.TBool | Tir.TString ->
      emitl ctx (Printf.sprintf "if (a.%s !== b.%s) return false;" fname fname)
    | Tir.TCon (ty_name, _) ->
      emitl ctx (Printf.sprintf "if (!__eq_%s(a.%s, b.%s)) return false;"
        (mangle ty_name) fname fname)
    | _ ->
      emitl ctx (Printf.sprintf "if (a.%s !== b.%s) return false;" fname fname)
  in
  match td with
  | Tir.TDVariant (name, ctors) ->
    emitl ctx (Printf.sprintf "function __eq_%s(a, b) {" (mangle name));
    with_indent ctx (fun () ->
      emitl ctx "if (a.$ !== b.$) return false;";
      emitl ctx "switch (a.$) {";
      with_indent ctx (fun () ->
        List.iter (fun (ctor, fields) ->
          emitl ctx (Printf.sprintf "case %S: {" ctor);
          with_indent ctx (fun () ->
            List.iteri (fun i fty -> emit_field_cmp_idx i fty) fields;
            emitl ctx "return true;"
          );
          emitl ctx "}"
        ) ctors
      );
      emitl ctx "}";
      emitl ctx "return true;"
    );
    emitl ctx "}\n"
  | Tir.TDRecord (name, fields) ->
    emitl ctx (Printf.sprintf "function __eq_%s(a, b) {" (mangle name));
    with_indent ctx (fun () ->
      List.iter (fun (fname, fty) -> emit_field_cmp fname fty) fields;
      emitl ctx "return true;"
    );
    emitl ctx "}\n"
  | Tir.TDClosure _ -> ()

(* ── Module emission ─────────────────────────────────────────────── *)

let emit_module (m : Tir.tir_module) : string =
  let ctx = create_ctx () in
  (* Equality helpers before functions (needed by EApp eq_ calls) *)
  List.iter (emit_eq_fn ctx) m.Tir.tm_types;
  (* Top-level functions *)
  List.iter (emit_fn_decl ctx) m.Tir.tm_fns;
  let fns_js = Buffer.contents ctx.buf in
  (* Build runtime imports *)
  let imports =
    let names = Hashtbl.fold (fun k () acc -> k :: acc) ctx.runtime_uses [] in
    let sorted = List.sort String.compare names in
    if sorted = [] then ""
    else
      "import { " ^ String.concat ", " sorted
      ^ " } from \"./march_runtime.mjs\";\n\n"
  in
  (* Build ES exports *)
  let export_buf = Buffer.create 256 in
  let has_main = List.exists (fun fn -> fn.Tir.fn_name = "main") m.Tir.tm_fns in
  if has_main then
    Buffer.add_string export_buf "export { main };\n";
  List.iter (fun name ->
    if name <> "main" then
      Buffer.add_string export_buf
        (Printf.sprintf "export { %s };\n" (mangle name))
  ) m.Tir.tm_exports;
  imports ^ fns_js ^ Buffer.contents export_buf
