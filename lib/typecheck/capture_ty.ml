(* Annotated types for capture inference (ocap phase 8a,
   specs/2026-11-11-ocap-capture-checking-design.md §4).

   A [t] has the shape of a solved [Typecheck_types.ty] with a set variable
   on every arrow and on every value of a declared (or opaque builtin) type
   that can hold a function value.  It lives beside [ty], never inside it:
   unification and lowering do not see it, which is what makes the layer
   erase by construction (design §10.4).

   One HM type variable is one annotation: a [Var] carries the id of the
   type variable and one set variable standing for everything a value of
   that type holds.  Where a scheme is instantiated the [Var] is replaced by
   the instance's annotated type, the same one at every occurrence. *)

open Typecheck_types
open Typecheck_env

type svar = int

type t =
  | Plain  (** holds no function value anywhere inside: no set *)
  | Arrow of t * t * svar  (** parameter, result, the function value's set *)
  | Con of string * t list * svar option
      (** a declared or builtin type; [None] when the type itself holds no arrow *)
  | Tuple of t list
  | Record of (string * t) list
  | Var of int * svar  (** an HM type variable and the set of what it holds *)
  | Hole of hole  (** a parameter, typed at its first use *)
  | Opaque  (** not modelled: as a source, every set it reaches is unknown *)

and hole = { mutable h_ty : t option; mutable h_in : t list; mutable h_hm : ty option }

let new_hole () = Hole { h_ty = None; h_in = []; h_hm = None }

(* ── which types hold a function value ──────────────────────────────────── *)

(* Builtin types with no constructors that hold no function value. *)
let pure_builtins =
  [ "Int"; "Float"; "String"; "Bool"; "Char"; "Byte"; "Bytes"; "Atom"; "Unit"; "Never"; "Scope";
    "Cap"; "Nat"; "BigInt"; "Decimal"; "Ordering"; "Regex"; "Duration"; "Instant"; "$LogicSet" ]

(* Builtin types with no declaration that hold a function value themselves
   (their type arguments carry their own sets either way). *)
let closure_builtins = [ "Task" ]

(* Types a value can be written to and read from: invariant in their
   arguments (design §6.3).  A builtin type not known to the checker is
   treated the same way. *)
let invariant_builtins = [ "Vault"; "Pid"; "Chan"; "Ref"; "Atomic"; "Array"; "MutArray"; "Cell"; "Stream" ]

let rec surface_holds_arrow (s : Ast.ty) : bool * string list =
  (* (an arrow appears outside any type parameter, the type names referenced) *)
  match s with
  | Ast.TyArrow _ -> (true, [])
  | Ast.TyCon (n, args) ->
    let rs = List.map surface_holds_arrow args in
    (List.exists fst rs, n.Ast.txt :: List.concat_map snd rs)
  | Ast.TyTuple ts ->
    let rs = List.map surface_holds_arrow ts in
    (List.exists fst rs, List.concat_map snd rs)
  | Ast.TyRecord fs ->
    let rs = List.map (fun (_, t) -> surface_holds_arrow t) fs in
    (List.exists fst rs, List.concat_map snd rs)
  | Ast.TyLinear (_, t) | Ast.TyRefine (t, _, _) -> surface_holds_arrow t
  | Ast.TyVar _ | Ast.TyNat _ | Ast.TyNatOp _ | Ast.TyChan _ -> (false, [])

let bare (n : string) : string =
  match String.rindex_opt n '.' with Some i -> String.sub n (i + 1) (String.length n - i - 1) | None -> n

type decls = {
  d_env : env;
  d_fields : (string, Ast.ty list) Hashtbl.t;  (** bare declared type -> every field's surface type *)
  d_holds : (string, bool) Hashtbl.t;
}

let decls_of (env : env) : decls =
  let d_fields = Hashtbl.create 256 in
  let add ty_name tys =
    let k = bare ty_name in
    Hashtbl.replace d_fields k (tys @ Option.value ~default:[] (Hashtbl.find_opt d_fields k))
  in
  StrMap.iter (fun _ cis -> List.iter (fun (ci : ctor_info) -> add ci.ci_type ci.ci_arg_tys) cis) env.ctors;
  StrMap.iter (fun name (_, fields) -> add name (List.map snd fields)) env.records;
  { d_env = env; d_fields; d_holds = Hashtbl.create 64 }

(* Whether a value of declared type [name] can hold a function value through
   its own fields (type arguments carry their own sets).  Two declared types
   with one bare name are merged, which can only answer [true] more often. *)
let rec holds (d : decls) (name : string) : bool =
  let k = bare name in
  match Hashtbl.find_opt d.d_holds k with
  | Some b -> b
  | None ->
    if List.mem k pure_builtins then false
    else (
      match Hashtbl.find_opt d.d_fields k with
      | None ->
        (* A builtin type with no declaration.  A handle holds no function
           value; a task holds the function it runs. *)
        List.mem k closure_builtins
      | Some tys ->
        Hashtbl.replace d.d_holds k false;  (* a recursive occurrence adds nothing *)
        let b =
          List.exists
            (fun s ->
               let arrow, names = surface_holds_arrow s in
               arrow || List.exists (fun n -> bare n <> k && Hashtbl.mem d.d_fields (bare n) && holds d n) names)
            tys
        in
        Hashtbl.replace d.d_holds k b;
        b)

let declared (d : decls) (name : string) : bool = Hashtbl.mem d.d_fields (bare name)

let variance (d : decls) (name : string) : [ `Co | `Inv ] =
  let k = bare name in
  if List.mem k invariant_builtins then `Inv
  else if declared d k then if holds d k then `Inv else `Co
  else if List.mem k [ "List"; "Option"; "Result"; "Map"; "Set"; "Seq"; "Task" ] then `Co
  else `Inv

(* ── building one from a solved type ────────────────────────────────────── *)

type gen = { fresh : unit -> svar; hv : int -> svar }

let rec of_ty (d : decls) (g : gen) (ty : ty) : t =
  match repr ty with
  | TArrow (a, b) -> Arrow (of_ty d g a, of_ty d g b, g.fresh ())
  | TCon (n, args) ->
    let args' = List.map (of_ty d g) args in
    if holds d n then Con (n, args', Some (g.fresh ()))
    else if List.for_all (fun a -> a = Plain) args' then Plain
    else Con (n, args', None)
  | TTuple ts ->
    let ts' = List.map (of_ty d g) ts in
    if List.for_all (fun a -> a = Plain) ts' then Plain else Tuple ts'
  | TRecord fs ->
    let fs' = List.map (fun (n, t) -> (n, of_ty d g t)) fs in
    if List.for_all (fun (_, a) -> a = Plain) fs' then Plain else Record fs'
  | TVar { contents = Unbound (id, _) } -> Var (id, g.hv id)
  | TVar { contents = Link t } -> of_ty d g t
  | TLin (_, t) | TRefine (t, _, _) -> of_ty d g t
  | TNat _ | TNatOp _ -> Plain
  | TChan _ | TError -> Opaque

(* Whether a solved type can hold a set at all: the fast path. *)
let rec ty_is_plain (d : decls) (ty : ty) : bool =
  match repr ty with
  | TArrow _ | TVar _ | TChan _ | TError -> false
  | TCon (n, args) -> (not (holds d n)) && List.for_all (ty_is_plain d) args
  | TTuple ts -> List.for_all (ty_is_plain d) ts
  | TRecord fs -> List.for_all (fun (_, t) -> ty_is_plain d t) fs
  | TLin (_, t) | TRefine (t, _, _) -> ty_is_plain d t
  | TNat _ | TNatOp _ -> true

let rec svars (t : t) : svar list =
  match t with
  | Plain | Opaque -> []
  | Arrow (a, b, s) -> (s :: svars a) @ svars b
  | Con (_, args, so) -> Option.to_list so @ List.concat_map svars args
  | Tuple ts -> List.concat_map svars ts
  | Record fs -> List.concat_map (fun (_, t) -> svars t) fs
  | Var (_, s) -> [ s ]
  | Hole { h_ty = Some t; _ } -> svars t
  | Hole { h_ty = None; _ } -> []

(* The sets a value of this type holds: its own, and those of what it
   contains.  A function's parameter is not something the function holds. *)
let rec held (t : t) : svar list =
  match t with
  | Plain | Opaque -> []
  | Arrow (_, _, s) -> [ s ]
  | Con (_, args, so) -> Option.to_list so @ List.concat_map held args
  | Tuple ts -> List.concat_map held ts
  | Record fs -> List.concat_map (fun (_, t) -> held t) fs
  | Var (_, s) -> [ s ]
  | Hole { h_ty = Some t; _ } -> held t
  | Hole { h_ty = None; _ } -> []

let rec has_opaque (t : t) : bool =
  match t with
  | Opaque -> true
  | Plain | Var _ -> false
  | Arrow (a, b, _) -> has_opaque a || has_opaque b
  | Con (_, args, _) | Tuple args -> List.exists has_opaque args
  | Record fs -> List.exists (fun (_, t) -> has_opaque t) fs
  | Hole { h_ty = Some t; _ } -> has_opaque t
  | Hole { h_ty = None; _ } -> false

(* ── the declared-type rule (design §4.2) ───────────────────────────────── *)

(* The annotated types of a declared type's fields, for a value [Con (name,
   args, so)]: a bare arrow, and every declared type that holds one, shares
   the value's own set [so]; a type parameter is the value's annotated
   argument.  [None] when the field types cannot be resolved here. *)
let decl_field_types (d : decls) (g : gen) ~(params : string list) ~(field_tys : Ast.ty list)
    ~(args : t list) ~(own : svar option) : t list option =
  if List.length params <> List.length args then None
  else
    let scratch = { d.d_env with errors = Err.create () } in
    let markers = List.map (fun p -> (p, fresh_var 0)) params in
    let marker_of (ty : ty) : t option =
      match repr ty with
      | TVar r ->
        let rec find ms as_ =
          match ms, as_ with
          | (_, m) :: ms', a :: as' -> (
            match repr m with TVar r' when r' == r -> Some a | _ -> find ms' as')
          | _ -> None
        in
        find markers args
      | _ -> None
    in
    let failed = ref false in
    let rec conv (ty : ty) : t =
      match marker_of ty with
      | Some a -> a
      | None -> (
        match repr ty with
        | TArrow (a, b) -> (
          match own with
          | Some s -> Arrow (conv a, conv b, s)
          | None ->
            failed := true;
            Opaque)
        | TCon (n, targs) ->
          let targs' = List.map conv targs in
          if holds d n then (
            match own with
            | Some _ -> Con (n, targs', own)
            | None when not (declared d n) -> Con (n, targs', Some (g.fresh ()))
            | None ->
              failed := true;
              Opaque)
          else if List.for_all (fun a -> a = Plain) targs' then Plain
          else Con (n, targs', None)
        | TTuple ts ->
          let ts' = List.map conv ts in
          if List.for_all (fun a -> a = Plain) ts' then Plain else Tuple ts'
        | TRecord fs ->
          let fs' = List.map (fun (n, t) -> (n, conv t)) fs in
          if List.for_all (fun (_, a) -> a = Plain) fs' then Plain else Record fs'
        | TVar _ -> Plain  (* a type variable the declaration does not bind: phantom *)
        | TLin (_, t) | TRefine (t, _, _) -> conv t
        | TNat _ | TNatOp _ -> Plain
        | TChan _ -> Opaque
        | TError ->
          failed := true;
          Opaque)
    in
    match
      List.map
        (fun s -> conv (Typecheck_unify.surface_ty scratch ~tvars:(ref markers) s))
        field_tys
    with
    | ts when not !failed -> Some ts
    | _ -> None
    | exception _ -> None

(* ── printing ───────────────────────────────────────────────────────────── *)

(* [set s] is the printed set of [s] ("" when empty).  An arrow chain whose
   arrows share one set variable is one multi-parameter function. *)
let pp_flag ~(set : svar -> string) (ty : ty) (t : t) : string * bool =
  let any = ref false in
  let needs s body =
    match set s with
    | "" -> body
    | txt ->
      any := true;
      body ^ " needs " ^ txt
  in
  (* An element of a comma-separated list is parenthesised when its own set
     would otherwise read as more elements of the list. *)
  let rec item ~(multi : bool) (ty : ty) (t : t) : string =
    let t' = match t with Hole { h_ty = Some x; _ } -> x | x -> x in
    let top = match t' with Arrow (_, _, s) | Con (_, _, Some s) -> set s | _ -> "" in
    if top <> "" && (multi || String.contains top ',') then go ~parens:true ty t else go ty t
  and go ?(parens = false) (ty : ty) (t : t) : string =
    let t = match t with Hole { h_ty = Some t'; _ } -> t' | t -> t in
    match repr ty, t with
    | _, (Plain | Opaque | Hole _) -> pp_ty ~parens ty
    | TArrow _, Arrow (_, _, s) ->
      let rec chain ty t acc =
        match repr ty, t with
        | TArrow (a, b), Arrow (pa, pb, s') when s' = s -> chain b pb ((a, pa) :: acc)
        | _ -> (List.rev acc, ty, t)
      in
      let params, rty, rt = chain ty t [] in
      let ps =
        match params with
        | [ (a, pa) ] -> go ~parens:true a pa
        | _ -> "(" ^ String.concat ", " (List.map (fun (a, pa) -> item ~multi:true a pa) params) ^ ")"
      in
      let res =
        let r = go ~parens:true rty rt in
        (* A result that carries its own set is parenthesised: a trailing
           `needs` belongs to the nearest arrow (design §4.1, §4.3). *)
        let carries =
          match rt with
          | Arrow _ -> false
          | Con (_, _, Some s') -> set s' <> ""
          | _ -> false
        in
        if carries && not (String.length r > 0 && r.[0] = '(') then "(" ^ r ^ ")" else r
      in
      let body = needs s (ps ^ " -> " ^ res) in
      if parens then "(" ^ body ^ ")" else body
    | TCon (n, args), Con (_, targs, so) when List.length args = List.length targs ->
      let head =
        if args = [] then n
        else
          n ^ "("
          ^ String.concat ", " (List.map2 (fun a ta -> item ~multi:(List.length args > 1) a ta) args targs)
          ^ ")"
      in
      (match so with
       | Some s when set s <> "" -> if parens then "(" ^ needs s head ^ ")" else needs s head
       | _ -> head)
    | TTuple ts, Tuple tts when List.length ts = List.length tts ->
      "(" ^ String.concat ", " (List.map2 (fun a ta -> item ~multi:true a ta) ts tts) ^ ")"
    | TRecord fs, Record tfs when List.length fs = List.length tfs ->
      "{ "
      ^ String.concat ", "
          (List.map
             (fun (n, a) ->
                n ^ " : " ^ item ~multi:(List.length fs > 1) a (Option.value ~default:Plain (List.assoc_opt n tfs)))
             fs)
      ^ " }"
    | (TLin (_, inner) | TRefine (inner, _, _)), _ -> go ~parens inner t
    | _ -> pp_ty ~parens ty
  in
  let text = go ty t in
  (text, !any)

let pp ~set ty t = fst (pp_flag ~set ty t)
