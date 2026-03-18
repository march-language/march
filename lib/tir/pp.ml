(** Pretty-printer for TIR expressions and types. *)

open Tir

let rec string_of_ty = function
  | TInt -> "Int"
  | TFloat -> "Float"
  | TBool -> "Bool"
  | TString -> "String"
  | TUnit -> "Unit"
  | TTuple ts -> "(" ^ String.concat ", " (List.map string_of_ty ts) ^ ")"
  | TRecord fs ->
    "{ " ^ String.concat ", " (List.map (fun (n, t) -> n ^ " : " ^ string_of_ty t) fs) ^ " }"
  | TCon (name, []) -> name
  | TCon (name, args) -> name ^ "(" ^ String.concat ", " (List.map string_of_ty args) ^ ")"
  | TFn (params, ret) ->
    "(" ^ String.concat ", " (List.map string_of_ty params) ^ ") -> " ^ string_of_ty ret
  | TPtr t -> "Ptr(" ^ string_of_ty t ^ ")"
  | TVar name -> "'" ^ name

let string_of_linearity = function
  | Lin -> "linear"
  | Aff -> "affine"
  | Unr -> ""

let string_of_var v =
  let lin = match v.v_lin with Unr -> "" | l -> string_of_linearity l ^ " " in
  lin ^ v.v_name ^ " : " ^ string_of_ty v.v_ty

let string_of_atom = function
  | AVar v -> v.v_name
  | ALit (March_ast.Ast.LitInt n) -> string_of_int n
  | ALit (March_ast.Ast.LitFloat f) -> string_of_float f
  | ALit (March_ast.Ast.LitString s) -> "\"" ^ String.escaped s ^ "\""
  | ALit (March_ast.Ast.LitBool b) -> string_of_bool b
  | ALit (March_ast.Ast.LitAtom a) -> ":" ^ a

let rec string_of_expr = function
  | EAtom a -> string_of_atom a
  | EApp (f, args) ->
    f.v_name ^ "(" ^ String.concat ", " (List.map string_of_atom args) ^ ")"
  | ECallPtr (f, args) ->
    "call_ptr " ^ string_of_atom f ^ "(" ^ String.concat ", " (List.map string_of_atom args) ^ ")"
  | ELet (v, e1, e2) ->
    "let " ^ string_of_var v ^ " = " ^ string_of_expr e1 ^ " in\n" ^ string_of_expr e2
  | ELetRec (fns, body) ->
    "letrec [" ^ String.concat "; " (List.map (fun f -> f.fn_name) fns) ^ "] in\n" ^ string_of_expr body
  | ECase (scrut, branches, default) ->
    let brs = List.map (fun br ->
        br.br_tag ^ "(" ^ String.concat ", " (List.map (fun v -> v.v_name) br.br_vars) ^ ") -> " ^ string_of_expr br.br_body
      ) branches in
    let def = match default with
      | Some e -> ["_ -> " ^ string_of_expr e]
      | None -> []
    in
    "case " ^ string_of_atom scrut ^ " of\n  " ^ String.concat "\n  " (brs @ def)
  | ETuple atoms ->
    "(" ^ String.concat ", " (List.map string_of_atom atoms) ^ ")"
  | ERecord fields ->
    "{ " ^ String.concat ", " (List.map (fun (n, a) -> n ^ " = " ^ string_of_atom a) fields) ^ " }"
  | EField (a, name) -> string_of_atom a ^ "." ^ name
  | EUpdate (a, fields) ->
    "{ " ^ string_of_atom a ^ " with " ^
    String.concat ", " (List.map (fun (n, a) -> n ^ " = " ^ string_of_atom a) fields) ^ " }"
  | EAlloc (ty, args) ->
    "alloc " ^ string_of_ty ty ^ "(" ^ String.concat ", " (List.map string_of_atom args) ^ ")"
  | EFree a -> "free " ^ string_of_atom a
  | EIncRC a -> "inc_rc " ^ string_of_atom a
  | EDecRC a -> "dec_rc " ^ string_of_atom a
  | EReuse (a, ty, args) ->
    "reuse " ^ string_of_atom a ^ " as " ^ string_of_ty ty ^
    "(" ^ String.concat ", " (List.map string_of_atom args) ^ ")"
  | ESeq (e1, e2) ->
    string_of_expr e1 ^ ";\n" ^ string_of_expr e2

let string_of_fn_def fn =
  "fn " ^ fn.fn_name ^ "(" ^
  String.concat ", " (List.map string_of_var fn.fn_params) ^
  ") : " ^ string_of_ty fn.fn_ret_ty ^ " =\n  " ^ string_of_expr fn.fn_body
