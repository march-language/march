(** forge ffi gen-c <file.march> [-o out.c]

    Generate a C shim skeleton from the `extern` blocks in a March file.  For
    each `extern fn`, emits a C function with the right signature and the
    marshalling boilerplate prefilled (borrow slices for String/Bytes params,
    Option/Result/resource hints, a typed return stub), leaving a TODO for the
    actual library call.  The "declare in March, generate the C glue" direction
    from specs/2026-06-19-c-ffi-abi-design.md §17.

    Type-directed codecs (§6.4): for each record/variant type reachable from an
    `extern` signature, emits a repr-C mirror struct plus `march_decode_T` /
    `march_encode_T` over the Phase 9 ABI accessors, and wires shim bodies to
    decode record/variant params and encode record/variant returns — so the
    author writes pure C over plain structs.  See
    specs/plans/2026-06-21-c-ffi-codecs.md. *)

module Ast = March_ast.Ast

let parse_file path : (Ast.decl list, string) result =
  try
    let ic  = open_in path in
    let src = really_input_string ic (in_channel_length ic) in
    close_in ic;
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
    let m = March_parser.Parser.module_
        (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
    Ok m.Ast.mod_decls
  with
  | Sys_error msg -> Error msg
  | exn -> Error (Printexc.to_string exn)

(* ── Type classification ─────────────────────────────────────────────────── *)

let con_name = function
  | Ast.TyCon ({ Ast.txt; _ }, _) -> Some txt
  | _ -> None

(* Ok payload of a Result(T, E) — for `raises` bindings, the bare C return. *)
let ok_payload (t : Ast.ty) : Ast.ty = match t with
  | Ast.TyCon ({ Ast.txt = "Result"; _ }, [a; _]) -> a
  | _ -> t

(* C type for an extern parameter / return position. *)
let c_type ~ret (t : Ast.ty) : string =
  match con_name t with
  | Some ("Int" | "Char" | "Bool") -> "int64_t"
  | Some "Float"                    -> "double"
  | Some "Unit" when ret           -> "void"
  | _                              -> "march_value"  (* String/Bytes/Option/Result/resource/record/variant *)

let is_string_ty t = match con_name t with Some ("String" | "Bytes") -> true | _ -> false

(* ── Codec type collection (§6.4) ────────────────────────────────────────────
   A "codec type" is a non-generic record or variant whose decode/encode we
   generate.  Recursive types (those reachable from themselves through other
   codec types) are excluded — a by-value mirror struct cannot represent them;
   they fall back to the `march_value` passthrough. *)

(* All non-generic record/variant decls in the file: name -> type_def. *)
let codec_candidates (decls : Ast.decl list) : (string * Ast.type_def) list =
  List.filter_map (function
    | Ast.DType (_, n, [], ((Ast.TDRecord _ | Ast.TDVariant _) as td), _) ->
      Some (n.Ast.txt, td)
    | _ -> None) decls

(* All type constructor names reachable in a type expression (incl. type args).
   This ensures Option(Point) pulls in Point for topo ordering. *)
let rec referenced_ty (t : Ast.ty) : string list =
  match t with
  | Ast.TyCon ({ Ast.txt = name; _ }, args) -> name :: List.concat_map referenced_ty args
  | _ -> []

(* Type names referenced by a record's fields / a variant's ctor args. *)
let referenced (td : Ast.type_def) : string list =
  match td with
  | Ast.TDRecord fields -> List.concat_map (fun f -> referenced_ty f.Ast.fld_ty) fields
  | Ast.TDVariant vars  ->
    List.concat_map (fun (v : Ast.variant) -> List.concat_map referenced_ty v.Ast.var_args) vars
  | Ast.TDAlias _ -> []

(* Drop candidates that are part of a cycle (T reachable from itself). *)
let acyclic_codecs (cands : (string * Ast.type_def) list)
  : (string * Ast.type_def) list =
  let names = List.map fst cands in
  let deps n = match List.assoc_opt n cands with
    | Some td -> List.filter (fun d -> List.mem d names) (referenced td)
    | None -> [] in
  (* transitive reachability from [start] *)
  let reaches start =
    let seen = Hashtbl.create 16 in
    let rec go n =
      List.iter (fun d ->
        if not (Hashtbl.mem seen d) then begin
          Hashtbl.replace seen d (); go d
        end) (deps n) in
    go start; Hashtbl.mem seen start in
  List.filter (fun (n, _) -> not (reaches n)) cands

(* ── Codec emission ──────────────────────────────────────────────────────── *)

(* `tbl` is the set of generated codec types (acyclic). A nested field is fully
   typed only if its type is in `tbl`; everything else is a march_value slot. *)

let is_codec tbl t = match con_name t with Some n -> List.mem_assoc n tbl | None -> false

(* A "leaf" payload usable inside Option/Result field codecs: mangled name,
   mirror-struct C type, and tagged-slot decode/encode functions.  Float and Unit
   are included here for use in Result(Float,E) fields (where the payload lives
   in field 0 of a boxed Result cell, so march_get_float(field) is correct).
   Option(Float) and Option(Unit) are handled specially in gen_opt_res because
   they need boxed/mixed semantics rather than the standard niche path. *)
let leaf_payload (t : Ast.ty)
  : (string * string * (string -> string) * (string -> string)) option =
  match con_name t with
  | Some "Int"    -> Some ("Int", "int64_t",
      (fun s -> Printf.sprintf "march_get_int(%s)" s),
      (fun v -> Printf.sprintf "march_make_int(%s)" v))
  | Some "Bool"   -> Some ("Bool", "int64_t",
      (fun s -> Printf.sprintf "march_get_bool(%s)" s),
      (fun v -> Printf.sprintf "march_make_bool((int)(%s))" v))
  | Some "Float"  -> Some ("Float", "double",
      (fun s -> Printf.sprintf "march_get_float(%s)" s),
      (fun v -> Printf.sprintf "march_make_float(%s)" v))
  | Some "Unit"   -> Some ("Unit", "int32_t",
      (fun _ -> "0"),
      (fun _ -> "0"))
  | Some "String" -> Some ("String", "march_slice",
      (fun s -> Printf.sprintf "march_str_borrow(%s)" s),
      (fun v -> Printf.sprintf "march_str_new(%s.ptr, %s.len)" v v))
  | Some "Bytes"  -> Some ("Bytes", "march_slice",
      (fun s -> Printf.sprintf "march_bytes_borrow(%s)" s),
      (fun v -> Printf.sprintf "march_bytes_new(%s.ptr, %s.len)" v v))
  | _ -> None

type opt_res = OROption of Ast.ty | ORResult of Ast.ty * Ast.ty

(* Recognize an Option(T)/Result(T,E) field whose payloads are supported leaves
   or codec types (when tbl is provided); returns (mangled name, structure). *)
let opt_res_of ?(tbl = []) (t : Ast.ty) : (string * opt_res) option =
  let name_of ty =
    match leaf_payload ty with
    | Some (m,_,_,_) -> Some m
    | None ->
      match con_name ty with
      | Some n when List.mem_assoc n tbl -> Some n
      | _ -> None in
  match t with
  | Ast.TyCon ({ Ast.txt = "Option"; _ }, [p]) ->
    (match name_of p with Some m -> Some ("Option_" ^ m, OROption p) | None -> None)
  | Ast.TyCon ({ Ast.txt = "Result"; _ }, [a; e]) ->
    (match name_of a, name_of e with
     | Some ma, Some me -> Some (Printf.sprintf "Result_%s_%s" ma me, ORResult (a, e))
     | _ -> None)
  | _ -> None

(* Element type of a List(T) field: leaf or codec. Returns
   (mangled_elem_name, C_elem_type, decode_slot_expr, encode_val_expr). *)
let list_elem_of tbl (t : Ast.ty)
  : (string * string * (string -> string) * (string -> string)) option =
  match t with
  | Ast.TyCon ({ Ast.txt = "List"; _ }, [elem]) ->
    (match leaf_payload elem with
     | Some x -> Some x
     | None ->
       (match con_name elem with
        | Some n when List.mem_assoc n tbl ->
          Some (n, n ^ "_c",
            (fun s -> Printf.sprintf "march_decode_%s(%s)" n s),
            (fun v -> Printf.sprintf "march_encode_%s(%s)" n v))
        | _ -> None))
  | _ -> None

(* C type of a record/ctor field in the mirror struct. *)
let field_c_type tbl (t : Ast.ty) : string =
  match opt_res_of ~tbl t with
  | Some (nm, _) -> nm ^ "_c"
  | None ->
  match list_elem_of tbl t with
  | Some (m, _, _, _) -> "List_" ^ m ^ "_c"
  | None ->
  match con_name t with
  | Some ("Int" | "Bool")   -> "int64_t"
  | Some "Float"            -> "double"
  | Some ("String"|"Bytes") -> "march_slice"
  | Some n when List.mem_assoc n tbl -> n ^ "_c"
  | _                       -> "march_value"

(* Read a slot value into its mirror-struct representation. *)
let decode_expr tbl (t : Ast.ty) (slot : string) : string =
  match opt_res_of ~tbl t with
  | Some (nm, _) -> Printf.sprintf "march_decode_%s(%s)" nm slot
  | None ->
  match list_elem_of tbl t with
  | Some (m, _, _, _) -> Printf.sprintf "march_decode_List_%s(%s)" m slot
  | None ->
  match con_name t with
  | Some ("Int" | "Bool")   -> slot
  | Some "Float"            -> Printf.sprintf "march_get_float(%s)" slot
  | Some ("String"|"Bytes") -> Printf.sprintf "march_str_borrow(%s)" slot
  | Some n when List.mem_assoc n tbl -> Printf.sprintf "march_decode_%s(%s)" n slot
  | _                       -> slot

(* Build a slot value from a mirror-struct field. *)
let encode_expr tbl (t : Ast.ty) (fld : string) : string =
  match opt_res_of ~tbl t with
  | Some (nm, _) -> Printf.sprintf "march_encode_%s(%s)" nm fld
  | None ->
  match list_elem_of tbl t with
  | Some (m, _, _, _) -> Printf.sprintf "march_encode_List_%s(%s)" m fld
  | None ->
  match con_name t with
  | Some ("Int" | "Bool")   -> fld
  | Some "Float"            -> Printf.sprintf "march_make_float(%s)" fld
  | Some ("String"|"Bytes") -> Printf.sprintf "march_str_new(%s.ptr, %s.len)" fld fld
  | Some n when List.mem_assoc n tbl -> Printf.sprintf "march_encode_%s(%s)" n fld
  | _                       -> fld

(* Shape descriptor kind char — must match shape_kind_char in llvm_emit.ml so the
   interned shape id matches March's own records of the same type. *)
let kind_char (t : Ast.ty) : char =
  match con_name t with
  | Some ("Int" | "Bool" | "Unit" | "Atom") -> 'i'
  | Some "Float" -> 'f'
  | None         -> 'g'   (* type variable *)
  | Some _       -> 'p'

(* "name:k;name:k;…" with fields sorted by name (March's record layout). *)
let shape_desc (fields : Ast.field list) : string =
  let sorted = List.sort
    (fun a b -> String.compare a.Ast.fld_name.Ast.txt b.Ast.fld_name.Ast.txt) fields in
  String.concat "" (List.map (fun f ->
    Printf.sprintf "%s:%c;" f.Ast.fld_name.Ast.txt (kind_char f.Ast.fld_ty)) sorted)

(* Mirror struct + decode + encode for one record type. *)
let gen_record tbl (name : string) (fields : Ast.field list) (b : Buffer.t) =
  let sorted = List.sort
    (fun a b -> String.compare a.Ast.fld_name.Ast.txt b.Ast.fld_name.Ast.txt) fields in
  let n = List.length sorted in
  (* struct *)
  Buffer.add_string b (Printf.sprintf "typedef struct {\n");
  List.iter (fun f ->
    Buffer.add_string b (Printf.sprintf "    %s %s;\n"
      (field_c_type tbl f.Ast.fld_ty) f.Ast.fld_name.Ast.txt)) sorted;
  Buffer.add_string b (Printf.sprintf "} %s_c;\n" name);
  (* decode *)
  Buffer.add_string b (Printf.sprintf "static %s_c march_decode_%s(march_value v) {\n" name name);
  Buffer.add_string b (Printf.sprintf "    %s_c o;\n" name);
  List.iteri (fun i f ->
    Buffer.add_string b (Printf.sprintf "    o.%s = %s;\n" f.Ast.fld_name.Ast.txt
      (decode_expr tbl f.Ast.fld_ty (Printf.sprintf "march_record_field(v, %d)" i)))) sorted;
  Buffer.add_string b "    return o;\n}\n";
  (* encode *)
  Buffer.add_string b (Printf.sprintf "static march_value march_encode_%s(%s_c o) {\n" name name);
  if n = 0 then
    Buffer.add_string b (Printf.sprintf "    return march_make_record(\"%s\", 0, (const march_value *)0);\n" (shape_desc sorted))
  else begin
    Buffer.add_string b (Printf.sprintf "    march_value f[%d];\n" n);
    List.iteri (fun i f ->
      Buffer.add_string b (Printf.sprintf "    f[%d] = %s;\n" i
        (encode_expr tbl f.Ast.fld_ty (Printf.sprintf "o.%s" f.Ast.fld_name.Ast.txt)))) sorted;
    Buffer.add_string b (Printf.sprintf "    return march_make_record(\"%s\", %d, f);\n" (shape_desc sorted) n)
  end;
  Buffer.add_string b "}\n"

(* Mirror struct + decode + encode for one variant type. *)
let gen_variant tbl (name : string) (vars : Ast.variant list) (b : Buffer.t) =
  let has_fields = List.exists (fun (v : Ast.variant) -> v.Ast.var_args <> []) vars in
  (* struct: tag + union of per-ctor field tuples (ctors with no args omitted). *)
  Buffer.add_string b "typedef struct {\n    int32_t tag;\n";
  if has_fields then begin
    Buffer.add_string b "    union {\n";
    List.iter (fun (v : Ast.variant) ->
      if v.Ast.var_args <> [] then begin
        Buffer.add_string b "        struct {";
        List.iteri (fun i a ->
          Buffer.add_string b (Printf.sprintf " %s f%d;" (field_c_type tbl a) i)) v.Ast.var_args;
        Buffer.add_string b (Printf.sprintf " } %s;\n" v.Ast.var_name.Ast.txt)
      end) vars;
    Buffer.add_string b "    } u;\n"
  end;
  Buffer.add_string b (Printf.sprintf "} %s_c;\n" name);
  (* decode *)
  Buffer.add_string b (Printf.sprintf "static %s_c march_decode_%s(march_value v) {\n" name name);
  Buffer.add_string b (Printf.sprintf "    %s_c o;\n    o.tag = march_variant_tag(v);\n" name);
  if has_fields then begin
    Buffer.add_string b "    switch (o.tag) {\n";
    List.iteri (fun tag (v : Ast.variant) ->
      if v.Ast.var_args <> [] then begin
        Buffer.add_string b (Printf.sprintf "      case %d:\n" tag);
        List.iteri (fun i a ->
          Buffer.add_string b (Printf.sprintf "        o.u.%s.f%d = %s;\n"
            v.Ast.var_name.Ast.txt i
            (decode_expr tbl a (Printf.sprintf "march_variant_field(v, %d)" i)))) v.Ast.var_args;
        Buffer.add_string b "        break;\n"
      end) vars;
    Buffer.add_string b "      default: break;\n    }\n"
  end;
  Buffer.add_string b "    return o;\n}\n";
  (* encode *)
  Buffer.add_string b (Printf.sprintf "static march_value march_encode_%s(%s_c o) {\n" name name);
  if has_fields then begin
    Buffer.add_string b "    switch (o.tag) {\n";
    List.iteri (fun tag (v : Ast.variant) ->
      let arity = List.length v.Ast.var_args in
      if arity = 0 then
        Buffer.add_string b (Printf.sprintf
          "      case %d: return march_make_variant(%d, 0, (const march_value *)0);\n" tag tag)
      else begin
        Buffer.add_string b (Printf.sprintf "      case %d: {\n        march_value f[%d];\n" tag arity);
        List.iteri (fun i a ->
          Buffer.add_string b (Printf.sprintf "        f[%d] = %s;\n" i
            (encode_expr tbl a (Printf.sprintf "o.u.%s.f%d" v.Ast.var_name.Ast.txt i)))) v.Ast.var_args;
        Buffer.add_string b (Printf.sprintf "        return march_make_variant(%d, %d, f);\n      }\n" tag arity)
      end) vars;
    Buffer.add_string b "    }\n"
  end;
  Buffer.add_string b "    return march_make_variant(o.tag, 0, (const march_value *)0);\n}\n"

(* Mirror struct + decode + encode for one synthetic Option(T)/Result(T,E) codec.
   Option niche (default): None=0, Some(x)=x in tagged/generic form.
   Option(Float): fully boxed (0.0 aliases None=0); Option(Unit): mixed (niche None, boxed Some).
   Option(nested codec type): niche — heap ptr is always non-zero.
   Result boxed: Ok=tag 0 / Err=tag 1, payload at field 0 (tagged/generic). *)
let gen_opt_res tbl ((nm, kind) : string * opt_res) (b : Buffer.t) =
  let get_codec ty =
    match leaf_payload ty with
    | Some x -> x
    | None ->
      (match con_name ty with
       | Some n when List.mem_assoc n tbl ->
         (n, n ^ "_c",
          (fun s -> Printf.sprintf "march_decode_%s(%s)" n s),
          (fun v -> Printf.sprintf "march_encode_%s(%s)" n v))
       | _ -> failwith ("gen_opt_res: unsupported payload type")) in
  match kind with
  | OROption p ->
    (match con_name p with
     | Some "Float" ->
       (* Fully boxed: 0.0 aliases None=0 in the niche, so both arms are heap cells *)
       Buffer.add_string b (Printf.sprintf
         "typedef struct { int32_t is_some; double value; } %s_c;\n" nm);
       Buffer.add_string b (Printf.sprintf
         "static %s_c march_decode_%s(march_value v) {\n    %s_c o;\n\
         \    if (march_variant_tag(v) == 0) o.is_some = 0;\n\
         \    else { o.is_some = 1; o.value = march_get_float(march_variant_field(v, 0)); }\n\
         \    return o;\n}\n" nm nm nm);
       Buffer.add_string b (Printf.sprintf
         "static march_value march_encode_%s(%s_c o) {\n\
         \    if (!o.is_some) return march_none_boxed();\n\
         \    return march_some_boxed(march_make_float(o.value));\n}\n" nm nm)
     | Some "Unit" ->
       (* Mixed: None=niche 0, Some(())=boxed heap cell; no value field *)
       Buffer.add_string b (Printf.sprintf
         "typedef struct { int32_t is_some; } %s_c;\n" nm);
       Buffer.add_string b (Printf.sprintf
         "static %s_c march_decode_%s(march_value v) {\n    %s_c o;\n\
         \    o.is_some = (v != 0);\n    return o;\n}\n" nm nm nm);
       Buffer.add_string b (Printf.sprintf
         "static march_value march_encode_%s(%s_c o) {\n\
         \    if (!o.is_some) return march_none();\n\
         \    return march_some_boxed(0);  /* Unit Some is boxed */\n}\n" nm nm)
     | Some n when List.mem_assoc n tbl ->
       (* Nested codec type: heap pointer — niche is safe (non-zero = Some(T)) *)
       Buffer.add_string b (Printf.sprintf
         "typedef struct { int32_t is_some; %s_c value; } %s_c;\n" n nm);
       Buffer.add_string b (Printf.sprintf
         "static %s_c march_decode_%s(march_value v) {\n    %s_c o;\n\
         \    if (v == 0) { o.is_some = 0; }\n\
         \    else { o.is_some = 1; o.value = march_decode_%s(v); }\n\
         \    return o;\n}\n" nm nm nm n);
       Buffer.add_string b (Printf.sprintf
         "static march_value march_encode_%s(%s_c o) {\n\
         \    if (!o.is_some) return march_none();\n\
         \    return march_some(march_encode_%s(o.value));\n}\n" nm nm n)
     | _ ->
       (* Niche path: None=0, Some(x)=x in tagged generic form *)
       let (_, cty, dec, enc) = get_codec p in
       Buffer.add_string b (Printf.sprintf
         "typedef struct { int32_t is_some; %s value; } %s_c;\n" cty nm);
       Buffer.add_string b (Printf.sprintf
         "static %s_c march_decode_%s(march_value v) {\n    %s_c o;\n\
         \    if (v == 0) o.is_some = 0;\n\
         \    else { o.is_some = 1; o.value = %s; }\n    return o;\n}\n"
         nm nm nm (dec "v"));
       Buffer.add_string b (Printf.sprintf
         "static march_value march_encode_%s(%s_c o) {\n\
         \    if (!o.is_some) return march_none();\n\
         \    return march_some(%s);\n}\n" nm nm (enc "o.value")))
  | ORResult (a, e) ->
    let (_, cta, deca, enca) = get_codec a in
    let (_, cte, dece, ence) = get_codec e in
    Buffer.add_string b (Printf.sprintf
      "typedef struct { int32_t is_ok; %s ok; %s err; } %s_c;\n" cta cte nm);
    Buffer.add_string b (Printf.sprintf "static %s_c march_decode_%s(march_value v) {\n" nm nm);
    Buffer.add_string b (Printf.sprintf
      "    %s_c o;\n    if (march_variant_tag(v) == 0) { o.is_ok = 1; o.ok = %s; }\n\
      \    else { o.is_ok = 0; o.err = %s; }\n    return o;\n}\n"
      nm (deca "march_variant_field(v, 0)") (dece "march_variant_field(v, 0)"));
    Buffer.add_string b (Printf.sprintf "static march_value march_encode_%s(%s_c o) {\n" nm nm);
    Buffer.add_string b (Printf.sprintf
      "    if (o.is_ok) return march_ok(%s);\n    return march_err(%s);\n}\n"
      (enca "o.ok") (ence "o.err"))

(* Mirror struct + decode + encode for one synthetic List(T) codec.
   The decoded struct is malloc-owned; the caller must free items. *)
let gen_list tbl (elem_ty : Ast.ty) (b : Buffer.t) =
  match list_elem_of tbl (Ast.TyCon ({ Ast.txt = "List"; Ast.span = Ast.dummy_span }, [elem_ty])) with
  | None -> ()
  | Some (m, cty, dec, enc) ->
    let nm = "List_" ^ m in
    Buffer.add_string b (Printf.sprintf
      "/* %s_c: malloc-owned array; caller must free items. */\n" nm);
    Buffer.add_string b (Printf.sprintf
      "typedef struct { %s *items; int32_t length; } %s_c;\n" cty nm);
    Buffer.add_string b (Printf.sprintf
      "static %s_c march_decode_%s(march_value v) {\n    %s_c o;\n\
      \    o.length = march_list_length(v);\n\
      \    o.items = o.length ? (%s *)malloc(o.length * sizeof(%s)) : 0;\n\
      \    for (int32_t i = 0; i < o.length; i++) {\n\
      \        o.items[i] = %s;\n\
      \        v = march_variant_field(v, 1);\n    }\n    return o;\n}\n"
      nm nm nm cty cty (dec "march_variant_field(v, 0)"));
    Buffer.add_string b (Printf.sprintf
      "static march_value march_encode_%s(%s_c o) {\n\
      \    march_value tail = march_list_nil();\n\
      \    for (int32_t i = o.length - 1; i >= 0; i--)\n\
      \        tail = march_list_cons(%s, tail);\n\
      \    return tail;\n}\n" nm nm (enc "o.items[i]"))

(* Collect opt-res and list codecs that need emitting for a given type_def. *)
let collect_opt_res tbl (records : (string * Ast.type_def) list) : (string * opt_res) list =
  let seen = Hashtbl.create 16 and order = ref [] in
  let add t = match opt_res_of ~tbl t with
    | Some (nm, k) -> if not (Hashtbl.mem seen nm) then (Hashtbl.replace seen nm (); order := (nm, k) :: !order)
    | None -> () in
  List.iter (fun (_, td) -> match td with
    | Ast.TDRecord fs  -> List.iter (fun (f : Ast.field) -> add f.Ast.fld_ty) fs
    | Ast.TDVariant vs -> List.iter (fun (v : Ast.variant) -> List.iter add v.Ast.var_args) vs
    | Ast.TDAlias _ -> ()) records;
  List.rev !order

(* Topologically order [needed] so a nested type is defined before its user. *)
let topo_order (tbl : (string * Ast.type_def) list) (needed : string list) : string list =
  let visited = Hashtbl.create 16 in
  let order = ref [] in
  let rec visit n =
    if not (Hashtbl.mem visited n) then begin
      Hashtbl.replace visited n ();
      (match List.assoc_opt n tbl with
       | Some td ->
         List.iter (fun d -> if List.mem_assoc d tbl then visit d) (referenced td)
       | None -> ());
      order := n :: !order
    end in
  List.iter visit needed;
  List.rev !order

(* ── Skeleton generation ─────────────────────────────────────────────────── *)

let gen_fn tbl (lib : string) (consumed : bool list) (ef : Ast.extern_fn) : string =
  let c_name = match ef.Ast.ef_symbol with
    | Some s -> s
    | None   -> lib ^ "_" ^ ef.Ast.ef_name.Ast.txt in
  let consumed_of i = match List.nth_opt consumed i with Some b -> b | None -> false in
  (* codec params take the raw march_value under a `_v` suffix; we decode below. *)
  let pname (n : Ast.name) t = if is_codec tbl t then n.Ast.txt ^ "_v" else n.Ast.txt in
  let params =
    List.map (fun (n, t) ->
      Printf.sprintf "%s %s" (c_type ~ret:false t) (pname n t)) ef.Ast.ef_params in
  (* A `raises` binding takes a hidden march_env* first param and returns the
     bare Ok payload (T of Result(T,E)); errors go via march_raise(env, e). *)
  let params = if ef.Ast.ef_raises then "march_env *env" :: params else params in
  let ret_ty_str =
    if ef.Ast.ef_raises then c_type ~ret:true (ok_payload ef.Ast.ef_ret_ty)
    else c_type ~ret:true ef.Ast.ef_ret_ty in
  let b = Buffer.create 256 in
  Buffer.add_string b (Printf.sprintf "/* %s%s%s(%s) : %s */\n"
    (if ef.Ast.ef_blocking then "blocking " else "")
    (if ef.Ast.ef_raises then "raises " else "")
    ef.Ast.ef_name.Ast.txt
    (String.concat ", " (List.map (fun (n,t) ->
       Printf.sprintf "%s : %s" n.Ast.txt (Ast.show_ty t)) ef.Ast.ef_params))
    (Ast.show_ty ef.Ast.ef_ret_ty));
  Buffer.add_string b (Printf.sprintf "%s %s(%s) {\n"
    ret_ty_str c_name (String.concat ", " params));
  (* Per-param marshalling. *)
  List.iteri (fun i (n, t) ->
    let nm = n.Ast.txt in
    if is_codec tbl t then
      (match con_name t with Some ty ->
        Buffer.add_string b (Printf.sprintf "    %s_c %s = march_decode_%s(%s_v);  (void)%s;\n"
          ty nm ty nm nm) | None -> ())
    else if is_string_ty t then
      Buffer.add_string b (Printf.sprintf
        "    march_slice %s_s = march_str_borrow(%s); (void)%s_s;  /* %s_s.ptr, %s_s.len */\n"
        nm nm nm nm nm)
    else (match con_name t with
      | Some ("Int" | "Char" | "Bool" | "Float" | "Option" | "Result") -> ()
      | Some other ->
        (* opaque/resource handle *)
        Buffer.add_string b (Printf.sprintf
          "    /* %s p = march_resource_get(%s, %s_TID);%s */\n"
          (other ^ " *") nm (String.uppercase_ascii other)
          (if consumed_of i then "  // consume: march_drop(" ^ nm ^ ") when done" else ""))
      | None -> ())
  ) ef.Ast.ef_params;
  Buffer.add_string b "    /* TODO: call the C library and build the result. */\n";
  (if ef.Ast.ef_raises then begin
     (* Return the bare Ok payload; raise out-of-band for the Err case. *)
     let t_ok = ok_payload ef.Ast.ef_ret_ty in
     Buffer.add_string b
       "    /* On error: march_raise(env, march_str_new((const uint8_t *)\"error\", 5)); return 0; */\n";
     (match con_name t_ok with
      | Some "Float" -> Buffer.add_string b "    return 0.0;\n"
      | _ when is_string_ty t_ok -> Buffer.add_string b
          "    return march_str_new((const uint8_t *)\"\", 0);\n"
      | _ -> Buffer.add_string b "    return 0;\n")
   end
   else if is_codec tbl ef.Ast.ef_ret_ty then
     (match con_name ef.Ast.ef_ret_ty with Some ty ->
        Buffer.add_string b (Printf.sprintf
          "    %s_c result = {0};\n    return march_encode_%s(result);\n" ty ty) | None -> ())
   else match con_name ef.Ast.ef_ret_ty with
   | Some "Unit"   -> ()
   | Some "Result" -> Buffer.add_string b
       "    return march_err(march_str_new((const uint8_t *)\"not implemented\", 15));  /* or march_ok(v) */\n"
   | Some "Option" ->
     (* Float/Unit payloads can't use the niche form (a 0-bit payload aliases
        None=0): Float uses a fully boxed Option; Unit uses boxed Some + niche None. *)
     (match (match ef.Ast.ef_ret_ty with Ast.TyCon (_, [p]) -> con_name p | _ -> None) with
      | Some "Float" -> Buffer.add_string b
          "    return march_none_boxed();  /* or march_some_boxed(march_make_float(x)) — Float Option is boxed */\n"
      | Some "Unit" -> Buffer.add_string b
          "    return march_none();  /* or march_some_boxed(0) — Unit Some is boxed, None is 0 */\n"
      | _ -> Buffer.add_string b "    return march_none();  /* or march_some(v) */\n")
   | _ when is_string_ty ef.Ast.ef_ret_ty -> Buffer.add_string b
       "    return march_str_new((const uint8_t *)\"\", 0);\n"
   | Some "Float"  -> Buffer.add_string b "    return 0.0;\n"
   | _             -> Buffer.add_string b "    return 0;\n");
  Buffer.add_string b "}\n";
  Buffer.contents b

let gen_c (decls : Ast.decl list) : string =
  (* Codec types reachable from extern signatures (acyclic only). *)
  let tbl = acyclic_codecs (codec_candidates decls) in
  let extern_type_names =
    List.concat_map (function
      | Ast.DExtern (edef, _) ->
        List.concat_map (fun (ef : Ast.extern_fn) ->
          ef.Ast.ef_ret_ty :: List.map snd ef.Ast.ef_params) edef.Ast.ext_fns
      | _ -> []) decls
    |> List.filter_map con_name
    |> List.filter (fun n -> List.mem_assoc n tbl) in
  let needed = topo_order tbl extern_type_names in
  (* Detect whether any List field codecs will be emitted (need stdlib.h). *)
  let needs_stdlib =
    List.exists (fun (_, td) -> match td with
      | Ast.TDRecord fs  -> List.exists (fun f -> list_elem_of tbl f.Ast.fld_ty <> None) fs
      | Ast.TDVariant vs -> List.exists (fun v -> List.exists (fun a -> list_elem_of tbl a <> None) v.Ast.var_args) vs
      | _ -> false) tbl in
  let b = Buffer.create 1024 in
  Buffer.add_string b
    "/* Generated by `forge ffi gen-c` — fill in the TODOs, then list this file\n\
    \   under [ffi] sources in forge.toml. */\n\
     #include \"march_ffi.h\"\n#include <stdint.h>\n";
  if needs_stdlib then Buffer.add_string b "#include <stdlib.h>\n";
  Buffer.add_char b '\n';
  if needed <> [] then begin
    Buffer.add_string b "/* ── Generated codecs (record/variant <-> repr-C mirror) ── */\n";
    (* Emit opt-res and list codecs interleaved with their record/variant types
       in topo order, so a nested type (e.g. Point_c) is always defined before
       any synthetic codec that references it (e.g. Option_Point_c). *)
    let emitted_or  = Hashtbl.create 8 in
    let emitted_lst = Hashtbl.create 8 in
    let emit_deps_for_td td =
      let field_types = match td with
        | Ast.TDRecord fs  -> List.map (fun f -> f.Ast.fld_ty) fs
        | Ast.TDVariant vs -> List.concat_map (fun v -> v.Ast.var_args) vs
        | _ -> [] in
      List.iter (fun ft ->
        (* opt-res synthetic codec for this field, if any *)
        (match opt_res_of ~tbl ft with
         | Some (nm, k) when not (Hashtbl.mem emitted_or nm) ->
           gen_opt_res tbl (nm, k) b; Buffer.add_char b '\n';
           Hashtbl.replace emitted_or nm ()
         | _ -> ());
        (* list codec for this field, if any *)
        (match list_elem_of tbl ft with
         | Some (m, _, _, _) when not (Hashtbl.mem emitted_lst m) ->
           (match ft with
            | Ast.TyCon (_, [elem]) -> gen_list tbl elem b; Buffer.add_char b '\n'
            | _ -> ());
           Hashtbl.replace emitted_lst m ()
         | _ -> ())
      ) field_types in
    List.iter (fun n -> match List.assoc_opt n tbl with
      | Some td ->
        emit_deps_for_td td;
        (match td with
         | Ast.TDRecord fs  -> gen_record tbl n fs b; Buffer.add_char b '\n'
         | Ast.TDVariant vs -> gen_variant tbl n vs b; Buffer.add_char b '\n'
         | _ -> ())
      | None -> ()) needed
  end;
  List.iter (function
    | Ast.DExtern (edef, _) ->
      List.iter (fun (ef : Ast.extern_fn) ->
        Buffer.add_string b (gen_fn tbl edef.Ast.ext_lib_name ef.Ast.ef_param_consumed ef);
        Buffer.add_char b '\n')
        edef.Ast.ext_fns
    | _ -> ()) decls;
  Buffer.contents b

(* ── forge ffi add-rust: scaffold a Rust binding crate ───────────────────── *)

let write_file path contents : (unit, string) result =
  try
    let oc = open_out path in
    output_string oc contents;
    close_out oc;
    Ok ()
  with Sys_error m -> Error m

(* Scaffold a Rust `staticlib` binding crate under <dir>/<name> using the `march`
   crate (#[march] / #[derive] / init!).  The Rust side is the only thing the
   author writes; `march::init!` generates the March extern block (run the
   `gen_extern` bin), and the staticlib links through forge.toml's [ffi] link. *)
let add_rust ~name ~dir ~march_path : (unit, string) result =
  let crate_dir = Filename.concat dir name in
  let lib_ident = String.map (fun c -> if c = '-' then '_' else c) name in
  let ( let* ) = Result.bind in
  let mkdir d = if not (Sys.file_exists d) then Unix.mkdir d 0o755 in
  let setup =
    try
      mkdir dir; mkdir crate_dir;
      mkdir (Filename.concat crate_dir "src");
      mkdir (Filename.concat crate_dir "src/bin");
      Ok ()
    with Unix.Unix_error (e, _, _) -> Error (Unix.error_message e) in
  let* () = setup in
  let cargo_toml = Printf.sprintf
    "[package]\n\
     name = \"%s\"\n\
     version = \"0.1.0\"\n\
     edition = \"2021\"\n\n\
     [lib]\n\
     name = \"%s\"\n\
     crate-type = [\"staticlib\", \"lib\"]\n\n\
     [dependencies]\n\
     march = { path = \"%s\" }   # the March FFI runtime crate (rust/march)\n\n\
     [profile.release]\n\
     panic = \"unwind\"   # #[march] catch_unwind needs unwinding\n"
    name lib_ident march_path in
  let lib_rs = Printf.sprintf
    "//! Rust binding for March via the `march` crate. Write idiomatic Rust; the\n\
     //! #[march] macro generates the extern \"C\" shim and `march::init!` the\n\
     //! March extern block (print it with `cargo run --bin gen_extern`).\n\n\
     use march::{march, Error};\n\
     // For records/variants, add: use march::{Encoder, Decoder};\n\n\
     #[march]\n\
     fn hello(name: &str) -> String {\n\
     \    format!(\"Hello, {}!\", name)\n\
     }\n\n\
     #[march]\n\
     fn checked_div(a: i64, b: i64) -> Result<i64, Error> {\n\
     \    if b == 0 { return Err(Error::msg(\"divide by zero\")); }\n\
     \    Ok(a / b)\n\
     }\n\n\
     // #[derive(Encoder, Decoder)] struct/enum <-> March record/variant.\n\n\
     march::init!(\"%s\", [hello, checked_div]);\n"
    name in
  let gen_extern_rs = Printf.sprintf
    "//! Prints the March `extern` block for this binding (paste into a .march\n\
     //! file, or redirect to one). Generated from the #[march] signatures.\n\
     fn main() { %s::march_print_extern_block(); }\n"
    lib_ident in
  let* () = write_file (Filename.concat crate_dir "Cargo.toml") cargo_toml in
  let* () = write_file (Filename.concat crate_dir "src/lib.rs") lib_rs in
  let* () = write_file (Filename.concat crate_dir "src/bin/gen_extern.rs") gen_extern_rs in
  Printf.printf
    "scaffolded Rust binding crate %s\n\
     next steps:\n\
    \  1. set the `march` path in %s/Cargo.toml\n\
    \  2. write your #[march] functions in %s/src/lib.rs\n\
    \  3. cargo build --release   (produces target/release/lib%s.a)\n\
    \  4. cargo run --bin gen_extern  >>  your_app.march   (the extern block)\n\
    \  5. link the .a via forge.toml:  [ffi] link = [\"%s/target/release/lib%s.a\"]\n"
    crate_dir crate_dir crate_dir lib_ident crate_dir lib_ident;
  Ok ()

let run ~file ~out : (unit, string) result =
  match parse_file file with
  | Error e -> Error e
  | Ok decls ->
    if not (List.exists (function Ast.DExtern _ -> true | _ -> false) decls) then
      Error (Printf.sprintf "no `extern` blocks found in %s" file)
    else begin
      let c = gen_c decls in
      (match out with
       | Some path ->
         let oc = open_out path in output_string oc c; close_out oc;
         Printf.printf "wrote %s\n" path
       | None -> print_string c);
      Ok ()
    end
