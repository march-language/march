(* Witness validation for refinement counterexamples.

   When Z3 refutes an obligation, the model it returns is a CANDIDATE: the
   SMT encoding over-approximates (unreflectable path conditions are dropped
   before discharge), so a raw model may describe an input the program can
   never reach.  This module turns candidates into FACTS by executing them:

     decode  — SMT model strings -> March runtime values, typed by the
               function's parameter list, zero-filling Z3's don't-cares
     execute — call the function through the tree-walking interpreter,
               fuel-limited and with effectful builtins vetoed
               ([Eval_prim.builtin_guard])
     check   — evaluate the violated predicate against the actual result
     shrink  — deterministically minimise the confirmed witness

   Only a candidate that survives execute+check is ever reported, which is
   what makes it sound for refine_post/refine_call/division_safety to
   surface models the verdict logic previously had to discard.  Every
   failure inside this module (undecodable type, blocked effect, fuel out,
   panic en route, unevaluable predicate) collapses to [None] — "behave
   exactly as before this module existed".

   Design: specs/2026-08-30-counterexample-surfacing-design.md. *)

module A = March_ast.Ast
module V = March_eval.Eval_types

(* =================================================================
   §1  Module registration: type tables + lazy evaluation env
   ================================================================= *)

(* The module being checked, as handed to [Refine_check.check_module] /
   [Division_safety.check_module] — the FULL desugared program including
   prepended stdlib decls, i.e. exactly what [Eval.eval_module_env] needs. *)
let current_module : A.module_ option ref = ref None

(* ADT name -> constructors (name, arg types); record name -> fields. *)
let type_ctors : (string, (string * A.ty list) list) Hashtbl.t = Hashtbl.create 64
let record_fields : (string, (string * A.ty) list) Hashtbl.t = Hashtbl.create 64

(* Lazily built interpreter environment for [current_module].  [`Failed]
   latches: a module whose decls cannot even be evaluated is not going to
   start working on the next obligation. *)
let env_state : [ `Unset | `Ready of V.env | `Failed ] ref = ref `Unset

(* Per-module wall budget across ALL witness executions, so a pathological
   module cannot stall the compile.  Reset by [set_module]. *)
let wall_budget : int ref = ref 0

let initial_wall_budget = 1_000_000
let per_call_fuel = 100_000

let rec register_types (decls : A.decl list) : unit =
  List.iter
    (function
      | A.DType (_, name, _, A.TDVariant vs, _) ->
        Hashtbl.replace type_ctors name.A.txt
          (List.map (fun v -> (v.A.var_name.A.txt, v.A.var_args)) vs)
      | A.DType (_, name, _, A.TDRecord fs, _) ->
        Hashtbl.replace record_fields name.A.txt
          (List.map (fun f -> (f.A.fld_name.A.txt, f.A.fld_ty)) fs)
      | A.DMod (_, _, inner, _) -> register_types inner
      | _ -> ())
    decls

let set_module (m : A.module_) : unit =
  (match !current_module with
   | Some m' when m' == m -> ()   (* same run (check_module then division_safety) *)
   | _ ->
     current_module := Some m;
     env_state := `Unset;
     wall_budget := initial_wall_budget;
     Hashtbl.reset type_ctors;
     Hashtbl.reset record_fields;
     register_types m.A.mod_decls)

(* =================================================================
   §2  Zero values and model decoding
   ================================================================= *)

let rec strip_refine : A.ty -> A.ty = function
  | A.TyRefine (base, _, _) -> strip_refine base
  | A.TyLinear (_, t) -> strip_refine t
  | t -> t

let rec zero_value ~(depth : int) (ty : A.ty) : V.value option =
  if depth <= 0 then None
  else
    match strip_refine ty with
    | A.TyCon ({ A.txt = "Int"; _ }, []) -> Some (V.VInt 0)
    | A.TyCon ({ A.txt = "Float"; _ }, []) -> Some (V.VFloat 0.0)
    | A.TyCon ({ A.txt = "Bool"; _ }, []) -> Some (V.VBool false)
    | A.TyCon ({ A.txt = "String"; _ }, []) -> Some (V.VString "")
    | A.TyCon ({ A.txt = "Unit"; _ }, []) -> Some V.VUnit
    | A.TyCon ({ A.txt = "List"; _ }, [ _ ]) -> Some (V.VCon ("Nil", []))
    | A.TyCon ({ A.txt = "Option"; _ }, [ _ ]) -> Some (V.VCon ("None", []))
    | A.TyTuple ts ->
      let zs = List.map (zero_value ~depth:(depth - 1)) ts in
      if List.for_all Option.is_some zs then
        Some (V.VTuple (List.map Option.get zs))
      else None
    | A.TyCon ({ A.txt = name; _ }, _) ->
      (match Hashtbl.find_opt type_ctors name with
       | Some ctors ->
         (* First constructor whose payload zero-fills; declaration order,
            so the choice is deterministic. *)
         List.find_map
           (fun (cname, args) ->
             let zs = List.map (zero_value ~depth:(depth - 1)) args in
             if List.for_all Option.is_some zs then
               Some (V.VCon (cname, List.map Option.get zs))
             else None)
           ctors
       | None ->
         (match Hashtbl.find_opt record_fields name with
          | Some fields ->
            let zs =
              List.map (fun (f, t) -> (f, zero_value ~depth:(depth - 1) t)) fields
            in
            if List.for_all (fun (_, z) -> Option.is_some z) zs then
              Some (V.VRecord (List.map (fun (f, z) -> (f, Option.get z)) zs))
            else None
          | None -> None))
    | _ -> None

(* A list of [n] zero elements of type [elt]. *)
let zero_list ~(elt : A.ty) (n : int) : V.value option =
  match zero_value ~depth:3 elt with
  | None -> None
  | Some z ->
    let rec build k acc = if k <= 0 then acc else build (k - 1) (V.VCon ("Cons", [ z; acc ])) in
    Some (build n (V.VCon ("Nil", [])))

(* Parse one SMT model value string against an expected base type.  [None]
   means "cannot decode" — never guess. *)
let rec decode_smt (ty : A.ty) (s : string) : V.value option =
  let s = String.trim s in
  let tokens_of s =
    let n = String.length s in
    if n >= 2 && s.[0] = '(' && s.[n - 1] = ')' then
      Some (Refine_scope.sexp_tokens (String.sub s 1 (n - 2)))
    else None
  in
  match strip_refine ty with
  | A.TyCon ({ A.txt = "Int"; _ }, []) ->
    (match int_of_string_opt s with
     | Some n -> Some (V.VInt n)
     | None ->
       (match tokens_of s with
        | Some [ "-"; d ] ->
          Option.map (fun n -> V.VInt (-n)) (int_of_string_opt d)
        | _ -> None))
  | A.TyCon ({ A.txt = "Bool"; _ }, []) ->
    (match s with "true" -> Some (V.VBool true) | "false" -> Some (V.VBool false) | _ -> None)
  | A.TyCon ({ A.txt = "Float"; _ }, []) ->
    (match float_of_string_opt s with
     | Some f -> Some (V.VFloat f)
     | None ->
       (match tokens_of s with
        | Some [ "-"; d ] ->
          Option.map (fun f -> V.VFloat (-.f)) (float_of_string_opt d)
        | Some [ "/"; a; b ] ->
          (match float_of_string_opt a, float_of_string_opt b with
           | Some a, Some b when b <> 0.0 -> Some (V.VFloat (a /. b))
           | _ -> None)
        | _ -> None (* (fp …) bit patterns: refuse rather than misread *)))
  | A.TyCon ({ A.txt = "List"; _ }, [ elt ]) ->
    (match tokens_of s with
     | Some ("as" :: "nil" :: _) -> Some (V.VCon ("Nil", []))
     | Some [ ("insert" | "cons"); h; t ] ->
       (match decode_smt elt h, decode_smt ty t with
        | Some h, Some t -> Some (V.VCon ("Cons", [ h; t ]))
        | _ -> None)
     | _ -> if s = "nil" then Some (V.VCon ("Nil", [])) else None)
  | A.TyCon ({ A.txt = name; _ }, _) ->
    (match Hashtbl.find_opt type_ctors name with
     | Some ctors ->
       let by_ctor cname args =
         match List.assoc_opt cname ctors with
         | Some tys when List.length tys = List.length args ->
           let ds = List.map2 decode_smt tys args in
           if List.for_all Option.is_some ds then
             Some (V.VCon (cname, List.map Option.get ds))
           else None
         | _ -> None
       in
       (match tokens_of s with
        | Some (cname :: args) -> by_ctor cname args
        | None -> by_ctor s []
        | Some [] -> None)
     | None ->
       (match Hashtbl.find_opt record_fields name, tokens_of s with
        | Some fields, Some (_ctor :: args) when List.length fields = List.length args ->
          let ds = List.map2 (fun (f, t) a -> (f, decode_smt t a)) fields args in
          if List.for_all (fun (_, d) -> Option.is_some d) ds then
            Some (V.VRecord (List.map (fun (f, d) -> (f, Option.get d)) ds))
          else None
        | _ -> None))
  | _ -> None

(* The measure-length fact for [name] in the model, if any: "len$xs" -> 3. *)
let len_fact (model : (string * string) list) (name : string) : int option =
  match List.assoc_opt ("len$" ^ name) model with
  | Some s ->
    (match int_of_string_opt (String.trim s) with
     | Some n when n >= 0 -> Some n
     | _ -> None)
  | None -> None

let decode_model ~(params : (string * A.ty) list)
    ~(model : (string * string) list) : (string * V.value) list option =
  let decode_param (pname, ty) =
    let base = strip_refine ty in
    let direct =
      match List.assoc_opt pname model with
      | Some s -> decode_smt base s
      | None -> None
    in
    let v =
      match direct, base with
      | Some v, _ -> Some v
      | None, A.TyCon ({ A.txt = "String"; _ }, []) ->
        (* String model values are opaque Str!val!N witnesses; the usable
           fact is the length. *)
        (match len_fact model pname with
         | Some n -> Some (V.VString (String.make n 'a'))
         | None -> Some (V.VString ""))
      | None, A.TyCon ({ A.txt = "List"; _ }, [ elt ]) ->
        (match len_fact model pname with
         | Some n -> zero_list ~elt n
         | None -> zero_value ~depth:3 base)
      | None, _ -> zero_value ~depth:3 base
    in
    Option.map (fun v -> (pname, v)) v
  in
  let decoded = List.map decode_param params in
  if List.for_all Option.is_some decoded then Some (List.map Option.get decoded)
  else None

(* =================================================================
   §3  Predicate evaluation and structural equality
   ================================================================= *)

let rec value_eq (a : V.value) (b : V.value) : bool option =
  match a, b with
  | V.VInt a, V.VInt b -> Some (a = b)
  | V.VFloat a, V.VFloat b -> Some (a = b)
  | V.VBool a, V.VBool b -> Some (a = b)
  | V.VString a, V.VString b -> Some (String.equal a b)
  | V.VUnit, V.VUnit -> Some true
  | V.VCon (c1, a1), V.VCon (c2, a2) ->
    if c1 <> c2 then Some false
    else if List.length a1 <> List.length a2 then Some false
    else
      List.fold_left2
        (fun acc x y ->
          match acc, value_eq x y with
          | Some true, Some r -> Some r
          | Some false, _ -> Some false
          | _, None | None, _ -> None)
        (Some true) a1 a2
  | V.VTuple a, V.VTuple b when List.length a = List.length b ->
    value_eq (V.VCon ("", a)) (V.VCon ("", b))
  | V.VRecord a, V.VRecord b when List.length a = List.length b ->
    (try
       List.fold_left
         (fun acc (f, x) ->
           match acc, List.assoc_opt f b with
           | Some true, Some y -> value_eq x y
           | Some false, _ -> Some false
           | _, None -> None
           | None, _ -> None)
         (Some true) a
     with _ -> None)
  | _ -> None

let list_len (v : V.value) : int option =
  let rec go acc = function
    | V.VCon ("Nil", []) -> Some acc
    | V.VCon ("Cons", [ _; t ]) -> go (acc + 1) t
    | _ -> None
  in
  go 0 v

(* Evaluate a refinement predicate structurally over runtime values.
   Covers the reflectable fragment and a little more (nonlinear `*`);
   anything it does not recognise is [None] — unconfirmable, NEVER a
   silent true/false. *)
let rec eval_pred ~(lookup : string -> V.value option) (e : A.expr) : bool option =
  match e with
  | A.ELit (A.LitBool b, _) -> Some b
  | A.EApp (A.EVar { A.txt = "&&"; _ }, [ a; b ], _) ->
    (match eval_pred ~lookup a, eval_pred ~lookup b with
     | Some false, _ | _, Some false -> Some false
     | Some true, Some true -> Some true
     | _ -> None)
  | A.EApp (A.EVar { A.txt = "||"; _ }, [ a; b ], _) ->
    (match eval_pred ~lookup a, eval_pred ~lookup b with
     | Some true, _ | _, Some true -> Some true
     | Some false, Some false -> Some false
     | _ -> None)
  | A.EApp (A.EVar { A.txt = "not"; _ }, [ a ], _) ->
    Option.map not (eval_pred ~lookup a)
  | A.EApp (A.EVar { A.txt = ("==" | "!=" | "<" | "<=" | ">" | ">=") as op; _ }, [ a; b ], _) ->
    (match eval_operand ~lookup a, eval_operand ~lookup b with
     | Some va, Some vb ->
       (match op with
        | "==" -> value_eq va vb
        | "!=" -> Option.map not (value_eq va vb)
        | _ ->
          (match va, vb with
           | V.VInt x, V.VInt y ->
             Some (match op with "<" -> x < y | "<=" -> x <= y | ">" -> x > y | _ -> x >= y)
           | V.VFloat x, V.VFloat y ->
             Some (match op with "<" -> x < y | "<=" -> x <= y | ">" -> x > y | _ -> x >= y)
           | _ -> None))
     | _ -> None)
  (* A bare boolean-valued operand position: `{Bool | _}`-shaped or a tester. *)
  | _ ->
    (match eval_operand ~lookup e with
     | Some (V.VBool b) -> Some b
     | _ -> None)

and eval_operand ~(lookup : string -> V.value option) (e : A.expr) : V.value option =
  match e with
  | A.ELit (A.LitInt n, _) -> Some (V.VInt n)
  | A.ELit (A.LitFloat f, _) -> Some (V.VFloat f)
  | A.ELit (A.LitBool b, _) -> Some (V.VBool b)
  | A.ELit (A.LitString s, _) -> Some (V.VString s)
  | A.EVar { A.txt; _ } -> lookup txt
  | A.EField (recv, { A.txt = fname; _ }, _) ->
    (match eval_operand ~lookup recv with
     | Some (V.VRecord fields) -> List.assoc_opt fname fields
     | _ -> None)
  | A.ECon ({ A.txt = ctor; _ }, args, _) ->
    let vs = List.map (eval_operand ~lookup) args in
    if List.for_all Option.is_some vs then
      Some (V.VCon (ctor, List.map Option.get vs))
    else None
  | A.EApp (A.EVar { A.txt = ("len" | "List.length" | "String.length"); _ }, [ a ], _) ->
    (match eval_operand ~lookup a with
     | Some (V.VString s) -> Some (V.VInt (String.length s))
     | Some v -> Option.map (fun n -> V.VInt n) (list_len v)
     | None -> None)
  | A.EApp (A.EVar { A.txt = "negate"; _ }, [ a ], _) ->
    (match eval_operand ~lookup a with
     | Some (V.VInt n) -> Some (V.VInt (-n))
     | Some (V.VFloat f) -> Some (V.VFloat (-.f))
     | _ -> None)
  | A.EApp (A.EVar { A.txt = ("+" | "-" | "*") as op; _ }, [ a; b ], _) ->
    (match eval_operand ~lookup a, eval_operand ~lookup b with
     | Some (V.VInt x), Some (V.VInt y) ->
       Some (V.VInt (match op with "+" -> x + y | "-" -> x - y | _ -> x * y))
     | _ -> None)
  | A.EApp (A.EVar { A.txt = ("+." | "-." | "*." | "/.") as op; _ }, [ a; b ], _) ->
    (match eval_operand ~lookup a, eval_operand ~lookup b with
     | Some (V.VFloat x), Some (V.VFloat y) ->
       Some (V.VFloat (match op with "+." -> x +. y | "-." -> x -. y | "*." -> x *. y | _ -> x /. y))
     | _ -> None)
  | A.EApp (A.EVar { A.txt = m; _ }, [ a ], _)
    when Refine_scope.ctor_of_tester m <> None ->
    (match eval_operand ~lookup a, Refine_scope.ctor_of_tester m with
     | Some (V.VCon (c, _)), Some tc -> Some (V.VBool (String.equal c tc))
     | _ -> None)
  | _ -> None

(* =================================================================
   §4  Rendering: runtime value -> March source syntax
   ================================================================= *)

let render_float (f : float) : string =
  let s = Printf.sprintf "%.12g" f in
  if String.exists (fun c -> c = '.' || c = 'e' || c = 'E') s then s else s ^ ".0"

let rec render_value (v : V.value) : string option =
  match v with
  | V.VInt n -> Some (string_of_int n)
  | V.VFloat f -> Some (render_float f)
  | V.VBool b -> Some (if b then "true" else "false")
  | V.VString s -> Some ("\"" ^ String.escaped s ^ "\"")
  | V.VUnit -> Some "()"
  | V.VCon (("Nil" | "Cons"), _) ->
    let rec elems acc = function
      | V.VCon ("Nil", []) -> Some (List.rev acc)
      | V.VCon ("Cons", [ h; t ]) ->
        (match render_value h with Some s -> elems (s :: acc) t | None -> None)
      | _ -> None
    in
    Option.map (fun es -> "[" ^ String.concat ", " es ^ "]") (elems [] v)
  | V.VCon (c, []) -> Some c
  | V.VCon (c, args) ->
    let rs = List.map render_value args in
    if List.for_all Option.is_some rs then
      Some (c ^ "(" ^ String.concat ", " (List.map Option.get rs) ^ ")")
    else None
  | V.VTuple vs ->
    let rs = List.map render_value vs in
    if List.for_all Option.is_some rs then
      Some ("(" ^ String.concat ", " (List.map Option.get rs) ^ ")")
    else None
  | V.VRecord fields ->
    let rs = List.map (fun (f, v) -> Option.map (fun s -> f ^ ": " ^ s) (render_value v)) fields in
    if List.for_all Option.is_some rs then
      Some ("{ " ^ String.concat ", " (List.map Option.get rs) ^ " }")
    else None
  | _ -> None

let render_call (fn : string) (args : (string * V.value) list) : string option =
  let rs = List.map (fun (_, v) -> render_value v) args in
  if List.for_all Option.is_some rs then
    Some (fn ^ "(" ^ String.concat ", " (List.map Option.get rs) ^ ")")
  else None
