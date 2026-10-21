(* Refinable slots for inference-lite
   (specs/2026-10-20-refinement-suggest-lite-design.md §1.1-§1.2).

   A slot is one position a refinement could be written at: a parameter, the
   return, an element of a container at either (repeated for nesting), or a
   tuple component on the way there.  The enumerator asks per slot, not per top
   constructor: `List({Int | _ > 0})` HAS a refined element even though its top
   constructor is `List`.  A position already refined is never a candidate —
   the tool proposes contracts, it does not second-guess declared ones. *)

module A = March_ast.Ast
module PI = Precond_infer

(* Outside-in: [Elem p] is the element slot of the container at [p];
   [Tuple (i, p)] is component [i] of the tuple at [p]. *)
type path =
  | Param of string
  | Return
  | Elem of path
  | Tuple of int * path
  | Lambda_param of { line : int; col : int; param : string }

type kind = K1 | K2 | K3 | K4 | K5 | K6 | K7

type slot = {
  fn : string;          (* qualified *)
  fd : A.fn_def;
  path : path;
  base : A.ty;          (* the type AT the slot *)
  kinds : kind list;
}

let kind_name = function
  | K1 -> "k1" | K2 -> "k2" | K3 -> "k3" | K4 -> "k4" | K5 -> "k5" | K6 -> "k6" | K7 -> "k7"

let rec root = function
  | (Param _ | Return | Lambda_param _) as r -> r
  | Elem p | Tuple (_, p) -> root p

let is_container (name : string) : bool =
  name = "List" || name = "Option" || Refine_scope.is_container_type name

let scalar (t : A.ty) : bool =
  match t with
  | A.TyCon ({ A.txt = "Int" | "Float" | "String"; _ }, []) -> true
  | _ -> false

(* A function that carries a contract that is not its body's never gets a
   proposal (§5.3). *)
let excluded (fd : A.fn_def) : bool =
  List.mem "trusted" fd.A.fn_attrs || List.mem "assume" fd.A.fn_attrs

let first_clause (fd : A.fn_def) = match fd.A.fn_clauses with c :: _ -> Some c | [] -> None

(* Slots below a root of type [t] at [p].  [elem_kind] is K3 under a
   parameter, K4 under the return; [rel] adds K5 when the function has another
   parameter a relational predicate could name. *)
let rec walk ~fn ~fd ~elem_kind ~rel (p : path) (t : A.ty) : slot list =
  let mk path base kinds = { fn; fd; path; base; kinds } in
  match t with
  | A.TyRefine _ -> []
  | A.TyLinear (_, t) -> walk ~fn ~fd ~elem_kind ~rel p t
  | A.TyTuple ts -> List.concat (List.mapi (fun i t -> walk ~fn ~fd ~elem_kind ~rel (Tuple (i, p)) t) ts)
  | A.TyCon ({ A.txt = c; _ }, ([ _ ] as args)) when is_container c ->
    List.concat_map
      (fun e ->
        match e with
        | A.TyRefine _ -> []
        | _ when scalar e || (match e with A.TyVar _ -> true | _ -> false) ->
          [ mk (Elem p) e (elem_kind :: (if rel then [ K5 ] else [])) ]
        | _ -> walk ~fn ~fd ~elem_kind ~rel (Elem p) e)
      args
  | _ -> []

let root_slots ~fn ~fd ~rel ~scalar_kind ~elem_kind (p : path) (t : A.ty) : slot list =
  match t with
  | A.TyRefine _ -> []
  | _ when scalar t -> [ { fn; fd; path = p; base = t; kinds = scalar_kind :: (if rel then [ K5 ] else []) } ]
  | A.TyCon ({ A.txt = "List"; _ }, [ _ ]) ->
    (* A list parameter/return itself: the `len(_) > 0` family (K1/K2). *)
    { fn; fd; path = p; base = t; kinds = [ scalar_kind ] }
    :: walk ~fn ~fd ~elem_kind ~rel p t
  | _ -> walk ~fn ~fd ~elem_kind ~rel p t

let slots_of_fn ~(fn : string) (fd : A.fn_def) : slot list =
  if excluded fd then []
  else
    match first_clause fd with
    | None -> []
    | Some c ->
      let params = PI.named_params c in
      let rel = List.length params >= 2 in
      let ps =
        List.concat_map
          (fun (n, t) -> root_slots ~fn ~fd ~rel ~scalar_kind:K1 ~elem_kind:K3 (Param n) t)
          params
      in
      let rs =
        match fd.A.fn_ret_ty with
        | Some t -> root_slots ~fn ~fd ~rel:(params <> []) ~scalar_kind:K2 ~elem_kind:K4 Return t
        | None -> []
      in
      ps @ rs

(* ── Re-spelling ─────────────────────────────────────────────────────────── *)

(* The whole annotation at the slot's root, with [pred] written at the slot.
   [None] when some part of the type has no surface rendering here. *)
let rec render ?(at : (path * string) option) (here : path) (t : A.ty) : string option =
  let all xs = if List.mem None xs then None else Some (List.map Option.get xs) in
  match at with
  | Some (target, pred) when target = here ->
    Option.map (fun b -> Printf.sprintf "{%s | %s}" b pred) (render here t)
  | _ -> (
    match t with
    | A.TyCon (n, []) -> Some n.A.txt
    | A.TyVar n -> Some n.A.txt
    | A.TyCon (n, args) ->
      Option.map
        (fun ps -> Printf.sprintf "%s(%s)" n.A.txt (String.concat ", " ps))
        (all (List.map (render ?at (Elem here)) args))
    | A.TyTuple ts ->
      Option.map
        (fun ps -> Printf.sprintf "(%s)" (String.concat ", " ps))
        (all (List.mapi (fun i t -> render ?at (Tuple (i, here)) t) ts))
    | A.TyArrow (a, b) -> (
      (* An arrow's two sides are not slot positions of their own here (the
         K6 callback is written as a whole annotation, Task 8). *)
      match render here a with
      | Some a' -> Option.map (fun b' -> Printf.sprintf "%s -> %s" a' b') (render here b)
      | None -> None)
    | A.TyRefine (b, binder, pred) ->
      Option.map
        (fun b' ->
          match binder with
          | None -> Printf.sprintf "{%s | %s}" b' (Refine_scope.pred_str pred)
          | Some n -> Printf.sprintf "{%s : %s | %s}" n.A.txt b' (Refine_scope.pred_str pred))
        (render here b)
    | _ -> None)

let root_ty (s : slot) : A.ty option =
  match root s.path with
  | Return -> s.fd.A.fn_ret_ty
  | Param n -> (
    match first_clause s.fd with
    | Some c -> List.assoc_opt n (PI.named_params c)
    | None -> None)
  | _ -> None

let respell (s : slot) ~(pred : string) : string option =
  match root_ty s with
  | Some t -> render ~at:(s.path, pred) (root s.path) t
  | None -> None

(* ── K6: joint abstract-refinement candidates (design §1.2 row K6) ──────── *)

(* A one-argument, uncurried callback parameter `f : a -> Bool` ([a] a type
   variable) whose [a] appears in an element slot of the return: the shape of
   `filter`, `find`, `take_while`, `partition`.  The body is not inspected —
   the oracle decides; this only decides whether probes are spent. *)
let k6_callback (t : A.ty) : string option =
  match t with
  | A.TyArrow (A.TyVar a, A.TyCon ({ A.txt = "Bool"; _ }, [])) -> Some a.A.txt
  | _ -> None

type k6_shape = { k6_param : string; k6_callback : string; k6_return : string }

let k6_returns (a : string) (ret : A.ty) : string list =
  let is_a = function A.TyVar v -> v.A.txt = a | _ -> false in
  let pa = Printf.sprintf "%s[p]" a and np = Printf.sprintf "{%s | !p(_)}" a in
  match ret with
  | A.TyCon ({ A.txt = "List"; _ }, [ e ]) when is_a e -> [ Printf.sprintf "List(%s)" pa ]
  | A.TyCon ({ A.txt = "Option"; _ }, [ e ]) when is_a e -> [ Printf.sprintf "Option(%s)" pa ]
  | A.TyTuple [ A.TyCon ({ A.txt = "List"; _ }, [ e1 ]); A.TyCon ({ A.txt = "List"; _ }, [ e2 ]) ]
    when is_a e1 && is_a e2 ->
    [ Printf.sprintf "(List(%s), List(%s))" pa np;
      Printf.sprintf "(List(%s), List(%s))" pa a;
      Printf.sprintf "(List(%s), List(%s))" a np ]
  | _ -> []

let k6_shapes (s : slot) : k6_shape list =
  match s.path, s.fd.A.fn_ret_ty with
  | Param f, Some ret -> (
    match k6_callback s.base with
    | Some a ->
      List.map
        (fun r -> { k6_param = f; k6_callback = Printf.sprintf "%s -> Bool[p]" a; k6_return = r })
        (k6_returns a ret)
    | None -> [])
  | _ -> []

let k6_slots ~(fn : string) (fd : A.fn_def) : slot list =
  match first_clause fd, fd.A.fn_ret_ty with
  | Some c, Some ret when not (excluded fd) ->
    List.filter_map
      (fun (n, t) ->
        match k6_callback t with
        | Some a when k6_returns a ret <> [] -> Some { fn; fd; path = Param n; base = t; kinds = [ K6 ] }
        | _ -> None)
      (PI.named_params c)
  | _ -> []

(* The function with [shape] written into its signature: the signature is
   re-spelled as text and PARSED, so the parser's own sugar (`Bool[p]`,
   `a[p]`) defines the abstract refinement, and the parsed parameter and
   return types are grafted onto the real definition (body untouched).
   [None] when a parameter has no surface rendering or the text does not
   parse. *)
let graft (s : slot) (shape : k6_shape) : A.fn_def option =
  let fd = s.fd in
  match first_clause fd with
  | None -> None
  | Some c -> (
    let params = PI.named_params c in
    let rendered =
      List.map
        (fun (n, t) ->
          if n = shape.k6_param then Some (Printf.sprintf "%s : %s" n shape.k6_callback)
          else Option.map (fun ts -> Printf.sprintf "%s : %s" n ts) (render Return t))
        params
    in
    if List.mem None rendered || List.length params <> List.length c.A.fc_params then None
    else
      let src =
        Printf.sprintf "mod InferK6 do
  fn %s(%s) : %s do 0 end
end
" fd.A.fn_name.A.txt
          (String.concat ", " (List.map Option.get rendered)) shape.k6_return
      in
      match March_parser.Parse.module_of_lexbuf (Lexing.from_string src) with
      | exception _ -> None
      | m -> (
        match m.A.mod_decls with
        | [ A.DFn (g, _) ] -> (
          match first_clause g with
          | None -> None
          | Some gc ->
            let tys = PI.named_params gc in
            let upd (p : A.param) =
              match List.assoc_opt p.A.param_name.A.txt tys with
              | Some t -> { p with A.param_ty = Some t }
              | None -> p
            in
            let upd_fp = function
              | A.FPNamed p -> A.FPNamed (upd p)
              | A.FPDefault (p, e) -> A.FPDefault (upd p, e)
              | other -> other
            in
            Some
              { fd with
                A.fn_ret_ty = g.A.fn_ret_ty;
                A.fn_clauses =
                  List.map (fun (c : A.fn_clause) -> { c with A.fc_params = List.map upd_fp c.A.fc_params }) fd.A.fn_clauses })
        | _ -> None))

let enumerate ~(is_user : A.span -> bool) (decls : A.decl list) : slot list =
  PI.enum_fns [] decls
  |> List.filter (fun (_, (fd : A.fn_def)) -> is_user fd.A.fn_name.A.span)
  |> List.concat_map (fun ((_, fd) as pf) ->
         let fn = PI.qualified_of pf in
         slots_of_fn ~fn fd @ k6_slots ~fn fd)

(* Functions with a parameter that has no annotation: no base to refine
   (reported `unannotated-signature`, §1.1). *)
let unannotated (decls : A.decl list) : (string * A.span) list =
  PI.enum_fns [] decls
  |> List.filter_map (fun ((_, (fd : A.fn_def)) as pf) ->
         match first_clause fd with
         | Some c
           when List.exists
                  (function
                    | A.FPNamed { A.param_ty = None; _ } | A.FPPat (A.PatVar _) -> true
                    | _ -> false)
                  c.A.fc_params ->
           Some (PI.qualified_of pf, fd.A.fn_name.A.span)
         | _ -> None)

(* ── Installing a hypothesis ─────────────────────────────────────────────── *)

(* Steps from the root to the slot, root-first. *)
let rec steps = function
  | Param _ | Return | Lambda_param _ -> []
  | Elem p -> steps p @ [ `Elem ]
  | Tuple (i, p) -> steps p @ [ `Tuple i ]

let rec refine_at (st : [ `Elem | `Tuple of int ] list) ~(mk : A.span -> A.expr) ~(sp : A.span) (t : A.ty) : A.ty =
  match st, t with
  | [], _ -> A.TyRefine (t, None, mk sp)
  | _, A.TyLinear (l, t) -> A.TyLinear (l, refine_at st ~mk ~sp t)
  | `Elem :: rest, A.TyCon (n, [ e ]) -> A.TyCon (n, [ refine_at rest ~mk ~sp e ])
  | `Tuple i :: rest, A.TyTuple ts -> A.TyTuple (List.mapi (fun j t -> if j = i then refine_at rest ~mk ~sp t else t) ts)
  | _ -> t

(* [s.fd] with [mk]'s predicate written at the slot, in every clause. *)
let install (s : slot) ~(mk : A.span -> A.expr) : A.fn_def =
  let fd = s.fd in
  let st = steps s.path in
  match root s.path with
  | Return ->
    { fd with A.fn_ret_ty = Option.map (refine_at st ~mk ~sp:fd.A.fn_name.A.span) fd.A.fn_ret_ty }
  | Param x ->
    let upd (p : A.param) =
      if p.A.param_name.A.txt <> x then p
      else { p with A.param_ty = Option.map (refine_at st ~mk ~sp:p.A.param_name.A.span) p.A.param_ty }
    in
    let upd_fp = function
      | A.FPNamed p -> A.FPNamed (upd p)
      | A.FPDefault (p, e) -> A.FPDefault (upd p, e)
      | other -> other
    in
    { fd with
      A.fn_clauses =
        List.map (fun (c : A.fn_clause) -> { c with A.fc_params = List.map upd_fp c.A.fc_params }) fd.A.fn_clauses }
  | _ -> fd
