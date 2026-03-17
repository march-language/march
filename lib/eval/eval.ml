(** March tree-walking interpreter.

    Evaluates a desugared [Ast.module_] directly, without any prior type
    information.  Useful for quick prototyping, REPL experimentation, and as
    a reference semantics for the compiler back-end.

    Design notes:
    - Values are OCaml heap objects; no explicit memory management.
    - Environments are association lists; later entries shadow earlier ones.
    - Two-pass module evaluation: pass 1 installs mutable stubs so that
      mutually-recursive top-level functions can reference each other; pass 2
      fills the stubs with real closures.
    - Pattern matching raises [Match_failure] when no branch matches. *)

open March_ast.Ast

(* ------------------------------------------------------------------ *)
(* Value type                                                          *)
(* ------------------------------------------------------------------ *)

type value =
  | VInt    of int
  | VFloat  of float
  | VString of string
  | VBool   of bool
  | VAtom   of string
  | VUnit
  | VTuple  of value list
  | VRecord of (string * value) list
  | VCon    of string * value list      (** Constructor: tag + payload *)
  | VClosure of env * string list * expr
  | VBuiltin of string * (value list -> value)

(** Association-list environment mapping names to values. *)
and env = (string * value) list

(* ------------------------------------------------------------------ *)
(* Exceptions                                                          *)
(* ------------------------------------------------------------------ *)

exception Match_failure of string
exception Eval_error of string

let eval_error fmt = Printf.ksprintf (fun s -> raise (Eval_error s)) fmt

(* ------------------------------------------------------------------ *)
(* Pattern matching                                                    *)
(* ------------------------------------------------------------------ *)

(** Try to match [v] against [pat].
    Returns [Some bindings] on success, [None] on failure.
    Bindings are accumulated in reverse order (callers reverse or prepend). *)
let rec match_pattern (v : value) (pat : pattern) : (string * value) list option =
  match pat, v with
  | PatWild _, _ -> Some []

  | PatVar n, _ -> Some [(n.txt, v)]

  | PatLit (LitInt i, _),    VInt j    when i = j   -> Some []
  | PatLit (LitFloat f, _),  VFloat g  when f = g   -> Some []
  | PatLit (LitString s, _), VString t when s = t   -> Some []
  | PatLit (LitBool b, _),   VBool c   when b = c   -> Some []
  | PatLit (LitAtom a, _),   VAtom b   when a = b   -> Some []
  | PatLit _,                _                       -> None

  | PatCon (n, pats), VCon (tag, args) when n.txt = tag ->
    if List.length pats <> List.length args then None
    else match_list pats args

  | PatCon _, _ -> None

  | PatAtom (a, pats, _), VAtom b when a = b && pats = [] -> Some []
  | PatAtom (a, pats, _), VCon (tag, args) when a = tag ->
    if List.length pats <> List.length args then None
    else match_list pats args
  | PatAtom _, _ -> None

  | PatTuple (pats, _), VTuple vs ->
    if List.length pats <> List.length vs then None
    else match_list pats vs

  | PatTuple _, _ -> None

  | PatRecord (fields, _), VRecord record_fields ->
    let bindings = List.fold_left (fun acc (fname, fpat) ->
        match acc with
        | None -> None
        | Some bs ->
          match List.assoc_opt fname.txt record_fields with
          | None -> None
          | Some fv ->
            match match_pattern fv fpat with
            | None -> None
            | Some new_bs -> Some (new_bs @ bs)
      ) (Some []) fields in
    bindings

  | PatRecord _, _ -> None

  | PatAs (inner, alias, _), _ ->
    (match match_pattern v inner with
     | None -> None
     | Some bs -> Some ((alias.txt, v) :: bs))

(** Match a list of patterns against a list of values. *)
and match_list (pats : pattern list) (vs : value list) : (string * value) list option =
  List.fold_left2 (fun acc p v ->
      match acc with
      | None -> None
      | Some bs ->
        match match_pattern v p with
        | None -> None
        | Some new_bs -> Some (new_bs @ bs)
    ) (Some []) pats vs

(* ------------------------------------------------------------------ *)
(* Built-in environment                                                *)
(* ------------------------------------------------------------------ *)

let arith_int op name = VBuiltin (name, function
    | [VInt a; VInt b] -> VInt (op a b)
    | _ -> eval_error "builtin %s: expected two ints" name)

let arith_num iop fop name = VBuiltin (name, function
    | [VInt a;   VInt b]   -> VInt   (iop a b)
    | [VFloat a; VFloat b] -> VFloat (fop a b)
    | _ -> eval_error "builtin %s: expected two numbers of the same type" name)

let cmp_op op_i op_f op_s op_b name = VBuiltin (name, function
    | [VInt a;    VInt b]    -> VBool (op_i a b)
    | [VFloat a;  VFloat b]  -> VBool (op_f a b)
    | [VString a; VString b] -> VBool (op_s a b)
    | [VBool a;   VBool b]   -> VBool (op_b a b)
    | _ -> eval_error "builtin %s: incompatible operand types" name)

(** Detect whether a VCon chain is a March list (Nil / Cons(h, t)). *)
let rec is_list_value = function
  | VCon ("Nil", []) -> true
  | VCon ("Cons", [_; t]) -> is_list_value t
  | _ -> false

let rec list_elems acc = function
  | VCon ("Nil", []) -> List.rev acc
  | VCon ("Cons", [h; t]) -> list_elems (h :: acc) t
  | v -> List.rev (v :: acc)  (* improper list — shouldn't happen *)

let rec value_to_string v =
  match v with
  | VInt n    -> string_of_int n
  | VFloat f  ->
    let s = string_of_float f in
    if String.contains s '.' || String.contains s 'e' then s
    else s ^ ".0"
  | VString s -> "\"" ^ String.escaped s ^ "\""
  | VBool b   -> string_of_bool b
  | VAtom a   -> ":" ^ a
  | VUnit     -> "()"
  | VTuple vs ->
    "(" ^ String.concat ", " (List.map value_to_string vs) ^ ")"
  | VRecord fields ->
    "{ " ^ String.concat ", "
      (List.map (fun (k, v) -> k ^ " = " ^ value_to_string v) fields)
    ^ " }"
  | VCon ("Nil", []) -> "[]"
  | VCon ("Cons", _) as v when is_list_value v ->
    "[" ^ String.concat ", " (List.map value_to_string (list_elems [] v)) ^ "]"
  | VCon (tag, []) -> tag
  | VCon (tag, args) ->
    tag ^ "(" ^ String.concat ", " (List.map value_to_string args) ^ ")"
  | VClosure _  -> "<fn>"
  | VBuiltin (n, _) -> "<builtin:" ^ n ^ ">"

(** print/println use a display form (no quotes around strings). *)
let value_display v =
  match v with
  | VString s -> s
  | _         -> value_to_string v

let base_env : env =
  [ (* Integer arithmetic *)
    ("+",  arith_num ( + ) ( +. ) "+")
  ; ("-",  arith_num ( - ) ( -. ) "-")
  ; ("*",  arith_num ( * ) ( *. ) "*")
  ; ("/",  VBuiltin ("/", function
        | [VInt a;   VInt b]   when b <> 0 -> VInt (a / b)
        | [VFloat a; VFloat b]             -> VFloat (a /. b)
        | [VInt _;   VInt 0]               -> eval_error "division by zero"
        | _ -> eval_error "builtin /: expected two numbers"))
  ; ("%",  VBuiltin ("%", function
        | [VInt a; VInt b] when b <> 0 -> VInt (a mod b)
        | _ -> eval_error "builtin %%: expected two non-zero ints"))
    (* Float arithmetic *)
  ; ("+.", VBuiltin ("+.", function
        | [VFloat a; VFloat b] -> VFloat (a +. b)
        | _ -> eval_error "builtin +.: expected two floats"))
  ; ("-.", VBuiltin ("-.", function
        | [VFloat a; VFloat b] -> VFloat (a -. b)
        | _ -> eval_error "builtin -.: expected two floats"))
  ; ("*.", VBuiltin ("*.", function
        | [VFloat a; VFloat b] -> VFloat (a *. b)
        | _ -> eval_error "builtin *.: expected two floats"))
  ; ("/.", VBuiltin ("/.", function
        | [VFloat a; VFloat b] -> VFloat (a /. b)
        | _ -> eval_error "builtin /.: expected two floats"))
    (* Comparisons *)
  ; ("==", cmp_op ( = )  ( = )  ( = )  ( = )  "==")
  ; ("!=", cmp_op ( <> ) ( <> ) ( <> ) ( <> ) "!=")
  ; ("<",  cmp_op ( < )  ( < )  ( < )  ( < )  "<")
  ; ("<=", cmp_op ( <= ) ( <= ) ( <= ) ( <= ) "<=")
  ; (">",  cmp_op ( > )  ( > )  ( > )  ( > )  ">")
  ; (">=", cmp_op ( >= ) ( >= ) ( >= ) ( >= ) ">=")
    (* Boolean *)
  ; ("&&", VBuiltin ("&&", function
        | [VBool a; VBool b] -> VBool (a && b)
        | _ -> eval_error "builtin &&: expected two bools"))
  ; ("||", VBuiltin ("||", function
        | [VBool a; VBool b] -> VBool (a || b)
        | _ -> eval_error "builtin ||: expected two bools"))
  ; ("not", VBuiltin ("not", function
        | [VBool b] -> VBool (not b)
        | _ -> eval_error "builtin not: expected bool"))
    (* String concatenation *)
  ; ("++", VBuiltin ("++", function
        | [VString a; VString b] -> VString (a ^ b)
        | _ -> eval_error "builtin ++: expected two strings"))
    (* I/O *)
  ; ("print", VBuiltin ("print", function
        | [v] -> print_string (value_display v); VUnit
        | vs  -> List.iter (fun v -> print_string (value_display v)) vs; VUnit))
  ; ("println", VBuiltin ("println", function
        | [v] -> print_endline (value_display v); VUnit
        | vs  -> List.iter (fun v -> print_string (value_display v)) vs;
                 print_newline (); VUnit))
  ; ("print_int", VBuiltin ("print_int", function
        | [VInt n] -> print_int n; VUnit
        | _ -> eval_error "print_int: expected int"))
  ; ("print_float", VBuiltin ("print_float", function
        | [VFloat f] -> print_float f; VUnit
        | _ -> eval_error "print_float: expected float"))
    (* Conversions *)
  ; ("int_to_string",  VBuiltin ("int_to_string", function
        | [VInt n] -> VString (string_of_int n)
        | _ -> eval_error "int_to_string: expected int"))
  ; ("float_to_string", VBuiltin ("float_to_string", function
        | [VFloat f] -> VString (string_of_float f)
        | _ -> eval_error "float_to_string: expected float"))
  ; ("string_to_int", VBuiltin ("string_to_int", function
        | [VString s] ->
          (try VCon ("Some", [VInt (int_of_string s)])
           with Failure _ -> VCon ("None", []))
        | _ -> eval_error "string_to_int: expected string"))
  ; ("string_length", VBuiltin ("string_length", function
        | [VString s] -> VInt (String.length s)
        | _ -> eval_error "string_length: expected string"))
    (* List helpers (using VCon "Cons"/"Nil") *)
  ; ("head", VBuiltin ("head", function
        | [VCon ("Cons", [h; _])] -> h
        | _ -> eval_error "head: expected non-empty list"))
  ; ("tail", VBuiltin ("tail", function
        | [VCon ("Cons", [_; t])] -> t
        | _ -> eval_error "tail: expected non-empty list"))
  ; ("is_nil", VBuiltin ("is_nil", function
        | [VCon ("Nil", [])] -> VBool true
        | [VCon ("Cons", _)] -> VBool false
        | _ -> eval_error "is_nil: expected list"))
    (* Negation *)
  ; ("negate", VBuiltin ("negate", function
        | [VInt n]   -> VInt (~- n)
        | [VFloat f] -> VFloat (~-. f)
        | _ -> eval_error "negate: expected number"))
  ]

(* ------------------------------------------------------------------ *)
(* Evaluation                                                          *)
(* ------------------------------------------------------------------ *)

let lookup name env =
  match List.assoc_opt name env with
  | Some v -> v
  | None   -> eval_error "unbound variable: %s" name

(** Extract parameter names from a single fn_clause (after desugaring,
    all params are FPNamed or FPPat(PatVar)). *)
let clause_params (clause : fn_clause) : string list =
  List.map (function
      | FPNamed p       -> p.param_name.txt
      | FPPat (PatVar n) -> n.txt
      | FPPat _         -> eval_error "unexpected pattern param after desugaring"
    ) clause.fc_params

(** Evaluate a block: return the value of the last expression.
    [ELet] bindings extend the environment for subsequent expressions. *)
let rec eval_block (env : env) (es : expr list) : value =
  match es with
  | []      -> VUnit
  | [e]     -> eval_expr env e
  | ELet (b, _) :: rest ->
    let v = eval_expr env b.bind_expr in
    let bindings = match match_pattern v b.bind_pat with
      | Some bs -> bs
      | None    -> raise (Match_failure
                            (Printf.sprintf "let binding pattern failed"))
    in
    eval_block (bindings @ env) rest
  | e :: rest ->
    let _ = eval_expr env e in
    eval_block env rest

(** Apply a callable value to a list of argument values. *)
and apply (fn_val : value) (args : value list) : value =
  match fn_val with
  | VClosure (closure_env, params, body) ->
    if List.length params <> List.length args then
      eval_error "arity mismatch: expected %d args, got %d"
        (List.length params) (List.length args);
    let env' = List.combine params args @ closure_env in
    eval_expr env' body

  | VBuiltin (_, f) -> f args

  | _ -> eval_error "applied non-function value: %s" (value_to_string fn_val)

(** Main expression evaluator. *)
and eval_expr (env : env) (e : expr) : value =
  match e with
  | ELit (LitInt n, _)    -> VInt n
  | ELit (LitFloat f, _)  -> VFloat f
  | ELit (LitString s, _) -> VString s
  | ELit (LitBool b, _)   -> VBool b
  | ELit (LitAtom a, _)   -> VAtom a

  | EVar n -> lookup n.txt env

  | EHole (name, _) ->
    let label = match name with Some n -> n.txt | None -> "?" in
    eval_error "typed hole ?%s evaluated at runtime" label

  | EApp (f, args, _) ->
    let fn_val = eval_expr env f in
    let arg_vals = List.map (eval_expr env) args in
    apply fn_val arg_vals

  | ECon (name, args, _) ->
    let arg_vals = List.map (eval_expr env) args in
    VCon (name.txt, arg_vals)

  | ELam (params, body, _) ->
    let param_names = List.map (fun p -> p.param_name.txt) params in
    VClosure (env, param_names, body)

  | EBlock (es, _) -> eval_block env es

  | ELet (b, _) ->
    (* Standalone let (outside a block) — evaluate and ignore bindings.
       This shouldn't appear after desugaring except inside EBlock. *)
    eval_expr env b.bind_expr

  | EMatch (scrut, branches, _) ->
    let v = eval_expr env scrut in
    eval_match env v branches

  | ETuple (es, _) ->
    VTuple (List.map (eval_expr env) es)

  | ERecord (fields, _) ->
    VRecord (List.map (fun (n, ex) -> (n.txt, eval_expr env ex)) fields)

  | ERecordUpdate (base, updates, _) ->
    let base_val = eval_expr env base in
    (match base_val with
     | VRecord fields ->
       let updated = List.map (fun (n, ex) -> (n.txt, eval_expr env ex)) updates in
       (* Merge: updated fields override existing ones *)
       let new_fields = List.map (fun (k, v) ->
           match List.assoc_opt k updated with
           | Some v' -> (k, v')
           | None    -> (k, v)
         ) fields in
       (* Add any fields in updated that weren't in the original *)
       let extra = List.filter (fun (k, _) ->
           not (List.mem_assoc k fields)) updated in
       VRecord (new_fields @ extra)
     | _ -> eval_error "record update on non-record value")

  | EField (ex, field, _) ->
    (match eval_expr env ex with
     | VRecord fields ->
       (match List.assoc_opt field.txt fields with
        | Some v -> v
        | None   -> eval_error "record has no field '%s'" field.txt)
     | _ -> eval_error "field access on non-record value")

  | EIf (cond, then_, else_, _) ->
    (match eval_expr env cond with
     | VBool true  -> eval_expr env then_
     | VBool false -> eval_expr env else_
     | _           -> eval_error "if condition must be a boolean")

  | EPipe _ ->
    eval_error "pipe expression reached evaluator (should be desugared)"

  | EAnnot (ex, _, _) -> eval_expr env ex

  | EAtom (a, [], _) -> VAtom a
  | EAtom (a, args, _) ->
    let arg_vals = List.map (eval_expr env) args in
    VCon (a, arg_vals)

  | ESend _ | ESpawn _ ->
    eval_error "actor primitives not yet supported by the interpreter"

(** Evaluate a match expression: try each branch until one matches. *)
and eval_match (env : env) (v : value) (branches : branch list) : value =
  match branches with
  | [] ->
    raise (Match_failure
             (Printf.sprintf "non-exhaustive match on value: %s"
                (value_to_string v)))
  | br :: rest ->
    (match match_pattern v br.branch_pat with
     | None -> eval_match env v rest
     | Some bindings ->
       let env' = bindings @ env in
       (* Check guard if present *)
       let guard_ok = match br.branch_guard with
         | None   -> true
         | Some g ->
           (match eval_expr env' g with
            | VBool b -> b
            | _       -> eval_error "guard must evaluate to a boolean")
       in
       if guard_ok
       then eval_expr env' br.branch_body
       else eval_match env v rest)

(* ------------------------------------------------------------------ *)
(* Module evaluation                                                   *)
(* ------------------------------------------------------------------ *)

(** A mutable stub: lets us install a forward reference for a name and
    later fill it with the real closure. *)
type stub = { mutable sv : value }

(** Evaluate a single declaration, extending [env].
    Returns the updated environment. *)
let rec eval_decl (env : env) (d : decl) : env =
  match d with
  | DFn (def, _) ->
    let clause = match def.fn_clauses with
      | [c] -> c
      | _   -> eval_error "fn %s: expected exactly one clause after desugaring"
                  def.fn_name.txt
    in
    let params = clause_params clause in
    (* Check if there's a stub already installed for this name *)
    (match List.assoc_opt def.fn_name.txt env with
     | Some (VClosure _) ->
       (* Patch the environment entry; since assoc lists are immutable we
          replace it.  For recursive stubs we rely on the stub mechanism. *)
       let closure = VClosure (env, params, clause.fc_body) in
       let env' = (def.fn_name.txt, closure)
                  :: List.remove_assoc def.fn_name.txt env in
       env'
     | _ ->
       let closure = VClosure (env, params, clause.fc_body) in
       (def.fn_name.txt, closure) :: env)

  | DLet (b, _) ->
    let v = eval_expr env b.bind_expr in
    (match match_pattern v b.bind_pat with
     | Some bs -> bs @ env
     | None    -> eval_error "top-level let binding pattern failed")

  | DType _ -> env   (* No runtime effect *)

  | DActor _ -> env  (* Actors not yet implemented *)

  | DMod (name, _, decls, _) ->
    (* Evaluate nested module; bindings are prefixed with "ModName." *)
    let mod_env = eval_decls env decls in
    (* Expose all bindings from the nested module prefixed by module name *)
    let prefixed = List.filter_map (fun (k, v) ->
        (* Only expose names that are new relative to the outer env *)
        if List.mem_assoc k env then None
        else Some (name.txt ^ "." ^ k, v)
      ) mod_env in
    prefixed @ env

  | DProtocol _ | DSig _ | DInterface _ | DImpl _ | DExtern _ -> env

and eval_decls (env : env) (decls : decl list) : env =
  List.fold_left eval_decl env decls

(** Two-pass module evaluation.

    Pass 1: For every top-level [DFn], install a stub closure in the
            environment.  This lets mutually-recursive functions refer
            to each other by name.

    Pass 2: Re-evaluate each [DFn] so that its closure captures the
            fully-populated environment (including all stubs). *)
let eval_module_env (m : module_) : env =
  (* Pass 1: stubs.  We use a ref cell shared across all stubs so that
     closures created in pass 2 can see the final environment. *)
  let env_ref : env ref = ref base_env in

  (* Install a placeholder for every top-level fn *)
  let install_stub = function
    | DFn (def, _) ->
      (* Placeholder that will be overwritten in pass 2 *)
      let stub = VBuiltin ("<stub:" ^ def.fn_name.txt ^ ">",
                           fun _ -> eval_error "stub %s called before initialisation"
                               def.fn_name.txt) in
      env_ref := (def.fn_name.txt, stub) :: !env_ref
    | _ -> ()
  in
  List.iter install_stub m.mod_decls;

  (* Pass 2: evaluate declarations in order, building up real closures.
     Each closure closes over [env_ref], which by the time any function
     is *called* will hold the full environment. *)
  let rec make_recursive_env decls env =
    match decls with
    | [] -> env
    | DFn (def, _) :: rest ->
      let clause = match def.fn_clauses with
        | [c] -> c
        | _   -> eval_error "fn %s: expected one clause after desugaring"
                     def.fn_name.txt
      in
      let params = clause_params clause in
      (* The closure environment is the ref itself; we use a trick:
         build a closure that looks up in [env_ref] at call time. *)
      let rec_closure = VBuiltin ("<rec:" ^ def.fn_name.txt ^ ">",
                                  fun args ->
                                    let call_env = !env_ref in
                                    let fn_v = VClosure (call_env, params, clause.fc_body) in
                                    apply fn_v args) in
      let env' = (def.fn_name.txt, rec_closure)
                 :: List.remove_assoc def.fn_name.txt env in
      env_ref := env';
      make_recursive_env rest env'

    | DLet (b, _) :: rest ->
      let v = eval_expr env b.bind_expr in
      let env' = match match_pattern v b.bind_pat with
        | Some bs -> bs @ env
        | None    -> eval_error "top-level let pattern failed"
      in
      env_ref := env';
      make_recursive_env rest env'

    | _ :: rest -> make_recursive_env rest env
  in

  let final_env = make_recursive_env m.mod_decls !env_ref in
  env_ref := final_env;
  final_env

(** Run the module: evaluate it, then call [main()] if it exists. *)
let run_module (m : module_) : unit =
  let env = eval_module_env m in
  match List.assoc_opt "main" env with
  | None   -> ()  (* Library module; no main to run *)
  | Some v ->
    let _ = apply v [] in
    ()
