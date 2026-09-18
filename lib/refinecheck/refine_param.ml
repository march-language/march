(* Parametricity preconditions for the parametric element rule.

   [Refine_check.parametric_return] (P3 design §2c) and the demand-driven rule
   built on it read a callee's DECLARED signature and reason from
   parametricity: `reverse : List(a) -> List(a)` cannot make an `a`, so every
   element of its result came from its argument and keeps that argument's
   element refinement.  That argument is only as good as two facts the
   declared signature does not establish on its own
   (specs/2026-09-18-parametric-element-flow-design.md §1):

   (P1) [generic_in_inferred]: the type variable is really generic in the
        callee's INFERRED type.  March's annotation type variables are
        ordinary unification variables, so
        `fn bad(xs : List(a)) : List(a) do [0 - 5] end` typechecks with
        `a := Int`, and trusting its signature proved `sum_pos(bad(pos))` on a
        list holding -5.  The typechecker records each parameter binder's type
        in [call_type_map] at the binder's span; every position the
        declaration spells `v` must resolve to ONE unbound type variable, and
        distinct declared variables to distinct ones.  No table, no recorded
        type, or a shape that does not align all answer "no" — a lost proof,
        never a false one.

   (P2) [parametric_safe]: the callee's BODY cannot create a value of a type
        variable.  A generic function can still get one from a builtin whose
        result type variable is absent from its parameters (a decoder, a
        typed global, …), an interface method of the same shape, an FFI
        extern, or another function that does one of those.  Computed once
        per module as a greatest fixpoint over the call graph.

   This module is a link in the include chain between [Refine_post] and
   [Refine_check]; it owns two cells, both reset by [reset_param_tables]. *)

include Refine_post

(* Two views of the same type language: [March_typecheck.Typecheck]'s
   interface re-declares [ty]/[scheme] without equations, so the builtin
   table (typed in [Typecheck_types]) and the span table (typed in
   [Typecheck]) are read through their own modules. *)
module T = March_typecheck.Typecheck
module TT = March_typecheck.Typecheck_types
module TB = March_typecheck.Typecheck_builtins

(* ── Builtin and interface-method schemes ─────────────────────────────── *)

(* Builtins whose result type is a type variable that exists only so the
   call can DIVERGE: their result value never exists, so they create nothing. *)
let diverging_builtins = [ "panic"; "panic_"; "todo_"; "unreachable_" ]

let rec tvar_ids (acc : int list) (t : T.ty) : int list =
  match T.repr t with
  | T.TVar r -> (match !r with T.Unbound (id, _) -> id :: acc | T.Link _ -> acc)
  | T.TCon (_, ts) | T.TTuple ts -> List.fold_left tvar_ids acc ts
  | T.TArrow (a, b) -> tvar_ids (tvar_ids acc a) b
  | T.TRecord fs -> List.fold_left (fun acc (_, t) -> tvar_ids acc t) acc fs
  | T.TLin (_, t) | T.TRefine (t, _, _) -> tvar_ids acc t
  | T.TNatOp (_, a, b) -> tvar_ids (tvar_ids acc a) b
  | T.TNat _ | T.TChan _ | T.TError -> acc

let rec tt_tvar_ids (acc : int list) (t : TT.ty) : int list =
  match TT.repr t with
  | TT.TVar r -> (match !r with TT.Unbound (id, _) -> id :: acc | TT.Link _ -> acc)
  | TT.TCon (_, ts) | TT.TTuple ts -> List.fold_left tt_tvar_ids acc ts
  | TT.TArrow (a, b) -> tt_tvar_ids (tt_tvar_ids acc a) b
  | TT.TRecord fs -> List.fold_left (fun acc (_, t) -> tt_tvar_ids acc t) acc fs
  | TT.TLin (_, t) | TT.TRefine (t, _, _) -> tt_tvar_ids acc t
  | TT.TNatOp (_, a, b) -> tt_tvar_ids (tt_tvar_ids acc a) b
  | TT.TNat _ | TT.TChan _ | TT.TError -> acc

(* Does a scheme's RESULT (the codomain after peeling every arrow) mention a
   type variable none of its parameters mention?  Such a function creates a
   value of a type it was never handed. *)
let scheme_creates (s : TT.scheme) : bool =
  let t = match s with TT.Mono t -> t | TT.Poly (_, _, t) -> t in
  let rec split params t =
    match TT.repr t with
    | TT.TArrow (a, b) -> split (a :: params) b
    | r -> (params, r)
  in
  let params, result = split [] t in
  let pvs = List.fold_left tt_tvar_ids [] params in
  List.exists (fun v -> not (List.mem v pvs)) (tt_tvar_ids [] result)

(* Builtins (and builtin interface methods) that create a value of a result
   type variable.  Computed from the typechecker's own table, so a new
   builtin is classified the moment it is registered — no list to drift. *)
let creating_builtins : (string, unit) Hashtbl.t Lazy.t =
  lazy
    (let tbl = Hashtbl.create 32 in
     List.iter
       (fun (n, s) ->
         if scheme_creates s && not (List.mem n diverging_builtins) then Hashtbl.replace tbl n ())
       (TB.builtin_bindings @ TB.builtin_interface_bindings);
     tbl)

let builtin_names : (string, unit) Hashtbl.t Lazy.t =
  lazy
    (let tbl = Hashtbl.create 512 in
     List.iter (fun (n, _) -> Hashtbl.replace tbl n ())
       (TB.builtin_bindings @ TB.builtin_interface_bindings);
     tbl)

(* ── Surface-type helpers ─────────────────────────────────────────────── *)

let rec ty_vars (acc : string list) (t : A.ty) : string list =
  match t with
  | A.TyVar v -> if List.mem v.A.txt acc then acc else v.A.txt :: acc
  | A.TyCon (_, ts) | A.TyTuple ts -> List.fold_left ty_vars acc ts
  | A.TyArrow (a, b) -> ty_vars (ty_vars acc a) b
  | A.TyRecord fs -> List.fold_left (fun acc (_, t) -> ty_vars acc t) acc fs
  | A.TyRefine (b, _, _) | A.TyLinear (_, b) -> ty_vars acc b
  | A.TyNatOp (_, a, b) -> ty_vars (ty_vars acc a) b
  | A.TyNat _ | A.TyChan _ -> acc

(* A user interface method creates a value when its declared result mentions
   a type variable its parameters do not (`fn default() : a`). *)
let method_creates (t : A.ty) : bool =
  let rec split params t =
    match t with
    | A.TyArrow (a, b) -> split (a :: params) b
    | A.TyRefine (b, _, _) | A.TyLinear (_, b) -> split params b
    | r -> (params, r)
  in
  let params, result = split [] t in
  let pvs = List.fold_left ty_vars [] params in
  List.exists (fun v -> not (List.mem v pvs)) (ty_vars [] result)

(* ── Per-module tables ────────────────────────────────────────────────── *)

(* Every function definition, keyed exactly as [collect_all_defs] keys
   [defs], with the module path its body resolves names against. *)
let fn_defs_tbl : (string, string * A.fn_def) Hashtbl.t = Hashtbl.create 256

(* [parametric_safe]'s answers, filled once per module by [compute_safety]. *)
let safe_tbl : (string, bool) Hashtbl.t = Hashtbl.create 256

(* Names bound as interface methods: [true] when that method creates. *)
let iface_methods : (string, bool) Hashtbl.t = Hashtbl.create 32

(* FFI extern function names. *)
let extern_names : (string, unit) Hashtbl.t = Hashtbl.create 16

(* Key -> key, so [resolve_call_gen] can answer WHICH definition a call
   resolves to, by the very rule [resolve_call] uses. *)
let key_tbl : (string, string) Hashtbl.t = Hashtbl.create 256

(* Definitions whose declared CONTAINER return (`: List({Int | p})`) had every
   tail's element obligation PROVED — the element-flow counterpart of
   [gate_unverified_posts]: only a proved contract becomes a fact at a call
   site (2026-09-18 plan, Phase 1).  Filled by [Refine_check]'s gating
   rounds. *)
let elem_ret_proved : (string, unit) Hashtbl.t = Hashtbl.create 16

(* The structural induction hypothesis for a container return (2026-09-18
   plan, Phase 2): while [visit_fn] walks a function [self] with a declared
   container return, a call [self(…)] whose argument at some parameter
   position is a STRUCTURAL component of that parameter
   ([structural_subvars], bound exactly once, [ambiguous_names]) carries the declared entry
   — the same rule Tier 2 applies to a datatype return.  One set per
   parameter position.  Active only while the function's element return is
   being gated, or once it has been proved ([elem_ret_proved]): a fact from an
   unproved hypothesis must never discharge another obligation. *)
let elem_ret_hyp : (string * (string, unit) Hashtbl.t list * (string * elem option list)) option ref =
  ref None

(* Set while [Refine_check.gate_elem_returns] runs its scratch walks. *)
let gating_elem_returns : bool ref = ref false

(* Every binder occurrence in [e], duplicates kept: `let` and `match`
   patterns, local `fn` names and parameters, lambda parameters.
   [structural_subvars] works by NAME over the whole body, so a component
   name is trusted only when [ambiguous_names] says it is bound exactly once —
   a second binder of the same spelling anywhere (`match zs do Cons(h2, t)`
   after `match xs do Cons(h, t)`), or a parameter of that spelling, makes
   some occurrence of it something other than the component. *)
let rec binder_occurrences (acc : string list) (e : A.expr) : string list =
  let acc =
    match e with
    | A.ELet (b, _) -> pat_binders b.A.bind_pat @ acc
    | A.ELetFn (n, ps, _, _, _) -> n.A.txt :: List.map (fun (p : A.param) -> p.A.param_name.A.txt) ps @ acc
    | A.ELam (ps, _, _) -> List.map (fun (p : A.param) -> p.A.param_name.A.txt) ps @ acc
    | A.ELetQ (p, _, _, _) | A.ELetStar (p, _, _, _) -> pat_binders p @ acc
    | A.EMatch (_, brs, _) -> List.concat_map (fun (br : A.branch) -> pat_binders br.A.branch_pat) brs @ acc
    | _ -> acc
  in
  List.fold_left binder_occurrences acc (children e)

(* The names a structural-component set must not trust for a clause with
   parameters [params] and body [body]: every parameter name, and every name
   bound more than once in the body. *)
let ambiguous_names (params : string list) (body : A.expr) : string list =
  let occ = binder_occurrences [] body in
  params
  @ List.filter (fun n -> List.length (List.filter (( = ) n) occ) > 1) (List.sort_uniq compare occ)

let reset_param_tables () =
  elem_ret_hyp := None;
  gating_elem_returns := false;
  Hashtbl.reset elem_ret_proved;
  Hashtbl.reset fn_defs_tbl;
  Hashtbl.reset safe_tbl;
  Hashtbl.reset iface_methods;
  Hashtbl.reset extern_names;
  Hashtbl.reset key_tbl

let collect_param_tables (decls : A.decl list) : unit =
  let qualify prefix n = if prefix = "" then n else prefix ^ "." ^ n in
  let add prefix (fd : A.fn_def) =
    let key = qualify prefix fd.A.fn_name.A.txt in
    Hashtbl.replace fn_defs_tbl key (prefix, fd);
    Hashtbl.replace key_tbl key key
  in
  let rec go prefix decls =
    let adoptable = adoptable_impl_methods decls in
    List.iter
      (function
        | A.DFn (fd, _) -> add prefix fd
        | A.DImpl (idf, _) ->
          List.iter
            (fun ((mn : A.name), (fd : A.fn_def)) ->
              if List.mem mn.A.txt adoptable then add prefix { fd with A.fn_name = mn })
            idf.A.impl_methods
        | A.DInterface (idf, _) ->
          List.iter
            (fun (md : A.method_decl) ->
              let prev = Option.value ~default:false (Hashtbl.find_opt iface_methods md.A.md_name.A.txt) in
              Hashtbl.replace iface_methods md.A.md_name.A.txt (prev || method_creates md.A.md_ty))
            idf.A.iface_methods
        | A.DExtern (ed, _) ->
          List.iter (fun (ef : A.extern_fn) -> Hashtbl.replace extern_names ef.A.ef_name.A.txt ())
            ed.A.ext_fns
        | A.DMod (name, _, ds, _) -> go (qualify prefix name.A.txt) ds
        | _ -> ())
      decls
  in
  go "" decls

(* The definition key a call to [fname] from inside [ctx] resolves to. *)
let resolve_key (ctx : rctx) (fname : string) : string option =
  resolve_call_gen ctx key_tbl fname

(* An element entry usable as a fact OUTSIDE the definition that declared it:
   every element predicate mentions nothing but its own binder.  A predicate
   naming one of the callee's parameters (`List({Int | _ < n})`) would, read at
   a call site, name whatever the CALLER calls `n`. *)
let rec entry_is_closed ((_, slots) : string * elem option list) : bool =
  List.for_all
    (function
      | None -> true
      | Some (Refined (b, p, _)) -> classify_pred b [] p = Closed
      | Some (Container (c, inner)) -> entry_is_closed (c, inner))
    slots

(* ── (P2) parametric_safe ─────────────────────────────────────────────── *)

(* Every name bound anywhere in a body (parameters, patterns, `let`s, local
   `fn`s, lambda parameters).  A call head in this set is a LOCAL value, whose
   type came from the function's own parameters or from other locals: it can
   produce a type-variable value only by way of a parameter, which is what
   the parametric rule's source analysis already constrains. *)
let rec expr_binders (acc : string list) (e : A.expr) : string list =
  let go = expr_binders in
  match e with
  | A.ELit _ | A.EVar _ | A.EHole _ | A.EResultRef _ -> acc
  | A.EApp (f, args, _) -> List.fold_left go (go acc f) args
  | A.ECon (_, args, _) | A.ETuple (args, _) | A.EAtom (_, args, _) | A.EBlock (args, _) ->
    List.fold_left go acc args
  | A.ELam (ps, body, _) ->
    go (List.map (fun (p : A.param) -> p.A.param_name.A.txt) ps @ acc) body
  | A.ELet (b, _) -> go (pat_binders b.A.bind_pat @ acc) b.A.bind_expr
  | A.EMatch (s, brs, _) ->
    List.fold_left
      (fun acc (br : A.branch) ->
        let acc = pat_binders br.A.branch_pat @ acc in
        let acc = match br.A.branch_guard with Some g -> go acc g | None -> acc in
        go acc br.A.branch_body)
      (go acc s) brs
  | A.ERecord (fs, _) -> List.fold_left (fun acc (_, e) -> go acc e) acc fs
  | A.ERecordUpdate (r, fs, _) -> List.fold_left (fun acc (_, e) -> go acc e) (go acc r) fs
  | A.EField (x, _, _) | A.EAnnot (x, _, _) | A.ESpawn (x, _) | A.EAssert (x, _)
  | A.ESigil (_, x, _) -> go acc x
  | A.EIf (c, t, f, _) -> go (go (go acc c) t) f
  | A.ECond (arms, _) -> List.fold_left (fun acc (c, b) -> go (go acc c) b) acc arms
  | A.EPipe (a, b, _) | A.ESend (a, b, _) -> go (go acc a) b
  | A.EDbg (x, _) -> (match x with Some x -> go acc x | None -> acc)
  | A.ELetFn (n, ps, _, body, _) ->
    go (n.A.txt :: List.map (fun (p : A.param) -> p.A.param_name.A.txt) ps @ acc) body
  | A.ELetQ (p, a, b, _) | A.ELetStar (p, a, b, _) -> go (go (pat_binders p @ acc) a) b

(* Every named call head (`f(…)`) in a body.  A head that is not a bare name
   is a call through a local value — see [expr_binders]. *)
let rec call_heads (acc : string list) (e : A.expr) : string list =
  let go = call_heads in
  match e with
  | A.ELit _ | A.EVar _ | A.EHole _ | A.EResultRef _ -> acc
  | A.EApp (A.EVar n, args, _) -> List.fold_left go (n.A.txt :: acc) args
  | A.EApp (f, args, _) -> List.fold_left go (go acc f) args
  | A.ECon (_, args, _) | A.ETuple (args, _) | A.EAtom (_, args, _) | A.EBlock (args, _) ->
    List.fold_left go acc args
  | A.ELam (_, body, _) | A.ELetFn (_, _, _, body, _) -> go acc body
  | A.ELet (b, _) -> go acc b.A.bind_expr
  | A.EMatch (s, brs, _) ->
    List.fold_left
      (fun acc (br : A.branch) ->
        let acc = match br.A.branch_guard with Some g -> go acc g | None -> acc in
        go acc br.A.branch_body)
      (go acc s) brs
  | A.ERecord (fs, _) -> List.fold_left (fun acc (_, e) -> go acc e) acc fs
  | A.ERecordUpdate (r, fs, _) -> List.fold_left (fun acc (_, e) -> go acc e) (go acc r) fs
  | A.EField (x, _, _) | A.EAnnot (x, _, _) | A.ESpawn (x, _) | A.EAssert (x, _)
  | A.ESigil (_, x, _) -> go acc x
  | A.EIf (c, t, f, _) -> go (go (go acc c) t) f
  | A.ECond (arms, _) -> List.fold_left (fun acc (c, b) -> go (go acc c) b) acc arms
  | A.EPipe (a, b, _) | A.ESend (a, b, _) -> go (go acc a) b
  | A.EDbg (x, _) -> (match x with Some x -> go acc x | None -> acc)
  | A.ELetQ (_, a, b, _) | A.ELetStar (_, a, b, _) -> go (go acc a) b

(* A resolved callee whose declared return mentions no type variable cannot
   return a value of the caller's type variable, whatever its body does. *)
let returns_concrete (fd : A.fn_def) : bool =
  match fd.A.fn_ret_ty with
  | Some t -> ty_vars [] t = []
  | None -> false

(* What one call head means for the enclosing body's parametricity:
   [`Ok] harmless, [`Dep k] safe iff definition [k] is, [`Taint] not safe. *)
let classify_head (ctx : rctx) (locals : string list) (h : string) =
  if List.mem h locals then `Ok
  else
    match resolve_key ctx h with
    | Some k ->
      (match Hashtbl.find_opt fn_defs_tbl k with
       | Some (_, fd) when returns_concrete fd -> `Ok
       | Some _ -> `Dep k
       | None -> `Taint)
    | None ->
      (* The desugared default-argument arity forms `f$1` / `f$2`. *)
      let base = match String.index_opt h '$' with Some i -> String.sub h 0 i | None -> h in
      if Hashtbl.mem extern_names h then `Taint
      else if Hashtbl.mem (Lazy.force builtin_names) h then
        if Hashtbl.mem (Lazy.force creating_builtins) h then `Taint else `Ok
      else
        match Hashtbl.find_opt iface_methods h with
        | Some creates -> if creates then `Taint else `Ok
        | None -> if base <> h && resolve_key ctx base <> None then `Ok else `Taint

(* Fill [safe_tbl] for every definition: a greatest fixpoint, starting from
   "every body is safe" and withdrawing any that taints directly or depends on
   a withdrawn one, until nothing changes. *)
let compute_safety () : unit =
  let info = Hashtbl.create 256 in
  Hashtbl.iter
    (fun key (prefix, (fd : A.fn_def)) ->
      let ctx = { rctx0 with modpath = prefix } in
      let direct = ref false and deps = ref [] in
      List.iter
        (fun (c : A.fn_clause) ->
          let locals =
            List.concat_map fnparam_binders c.A.fc_params |> fun ps -> expr_binders ps c.A.fc_body
          in
          let heads =
            call_heads (match c.A.fc_guard with Some g -> call_heads [] g | None -> []) c.A.fc_body
          in
          List.iter
            (fun h ->
              match classify_head ctx locals h with
              | `Ok -> ()
              | `Taint -> direct := true
              | `Dep k -> if k <> key then deps := k :: !deps)
            heads)
        fd.A.fn_clauses;
      Hashtbl.replace info key (!direct, !deps);
      Hashtbl.replace safe_tbl key (not !direct))
    fn_defs_tbl;
  let changed = ref true in
  while !changed do
    changed := false;
    Hashtbl.iter
      (fun key (_, deps) ->
        if Hashtbl.find safe_tbl key
           && List.exists (fun k -> Hashtbl.find_opt safe_tbl k <> Some true) deps
        then begin
          Hashtbl.replace safe_tbl key false;
          changed := true
        end)
      info
  done

let parametric_safe (key : string) : bool =
  Option.value ~default:false (Hashtbl.find_opt safe_tbl key)

(* ── (P1) generic_in_inferred ─────────────────────────────────────────── *)

(* Walk a declared type alongside the inferred one, recording what EVERY
   declared type variable resolved to.  [false] when the shapes do not align
   around a type variable (nothing there can be accounted for). *)
let rec align (found : (string * T.ty) list ref) (d : A.ty) (t : T.ty) : bool =
  let t = T.repr t in
  match d, t with
  | (A.TyRefine (b, _, _) | A.TyLinear (_, b)), _ -> align found b t
  | _, T.TLin (_, t') -> align found d t'
  | A.TyVar v, _ ->
    found := (v.A.txt, t) :: !found;
    true
  | (A.TyCon (_, ds), T.TCon (_, ts) | A.TyTuple ds, T.TTuple ts)
    when List.length ds = List.length ts ->
    List.for_all2 (align found) ds ts
  | A.TyArrow (da, db), T.TArrow (ta, tb) -> align found da ta && align found db tb
  | _ -> ty_vars [] d = []

let unbound_id (t : T.ty) : int option =
  match T.repr t with
  | T.TVar r -> (match !r with T.Unbound (id, _) -> Some id | T.Link _ -> None)
  | _ -> None

(* P1 for the type variables [vs] of definition [fd], from the parameter
   types the typechecker recorded:
   - every parameter's inferred type is known and aligns with its declared
     one (an unannotated parameter is recorded whole, under no name);
   - each [v] is witnessed at least once, and every witness is the SAME
     unbound type variable;
   - that variable occurs NOWHERE ELSE in any parameter's inferred type — not
     under another declared variable (`a` unified with `List(b)`), not in an
     unannotated parameter.  A value of [v] can then enter only where the
     declaration says, which is what the source analysis reads. *)
let generic_in_inferred (fd : A.fn_def) (vs : string list) : bool =
  match !call_type_map with
  | None -> false
  | Some tm ->
    let found = ref [] in
    let aligned =
      List.for_all
        (fun (c : A.fn_clause) ->
          List.for_all
            (function
              | A.FPNamed p | A.FPDefault (p, _) ->
                (match p.A.param_ty, Hashtbl.find_opt tm p.A.param_name.A.span with
                 | Some d, _ when ty_vars [] d = [] -> true
                 | Some d, Some t -> align found d t
                 | None, Some t ->
                   found := ("", t) :: !found;
                   true
                 | _, None -> false)
              | A.FPPat _ -> false)
            c.A.fc_params)
        fd.A.fn_clauses
    in
    aligned
    && List.for_all
         (fun v ->
           let ws = List.filter_map (fun (v', t) -> if v' = v then Some (unbound_id t) else None) !found in
           match ws with
           | Some id :: rest when List.for_all (( = ) (Some id)) rest ->
             List.for_all
               (fun (v', t) -> v' = v || not (List.mem id (tvar_ids [] t)))
               !found
           | _ -> false)
         vs

(* The whole gate: a call to [fname] from [ctx] may carry element facts
   through type variables [vs] of the callee's declared signature.  A callee
   the definition table does not know (a callback parameter, a local `fn`,
   an unresolved name) never qualifies. *)
let parametric_ok (ctx : rctx) (fname : string) (vs : string list) : bool =
  match resolve_key ctx fname with
  | None -> false
  | Some key ->
    (match Hashtbl.find_opt fn_defs_tbl key with
     | None -> false
     | Some (_, fd) ->
       (not (List.exists (fun ((b : A.name), _) -> List.mem b.A.txt vs) fd.A.fn_bounds))
       && parametric_safe key && generic_in_inferred fd vs)

(* ── Sources of a type variable (2026-09-18 plan, Phase 3; design §4.2) ──
   Where can a value of type variable [v] ENTER a function?  By
   parametricity (P1 and P2 above), only through its parameters, and only at
   the positions its declared parameter types put [v] positively:

   - [Src_bare i]: parameter [i] is itself a [v];
   - [Src_elem (i, path)]: [v] sits inside registered containers in
     parameter [i]'s type, at [path] (container, slot index) from the top;
   - [Src_cod (i, path)]: parameter [i] is a function type (curried or
     not) whose final RESULT has [v] at [path] ([] = the result is [v]).

   Negative occurrences — [v] in a function parameter's DOMAIN — are values
   the function hands out, not sources.  An occurrence anywhere else (inside
   a tuple, a record, an unregistered type constructor such as `Task(v)`, a
   function type's domain's own domain) cannot be accounted for, and the answer is [None]: the
   rule then does not apply at all. *)
type source =
  | Src_bare of int
  | Src_elem of int * (string * int) list
  | Src_cod of int * (string * int) list

let rec strip_ty (t : A.ty) : A.ty =
  match t with A.TyRefine (b, _, _) | A.TyLinear (_, b) -> strip_ty b | t -> t

(* Paths to every occurrence of [v] in [t] that goes only through registered
   containers; [None] if some occurrence goes through anything else. *)
let rec container_paths (v : string) (t : A.ty) : (string * int) list list option =
  let t = strip_ty t in
  if not (List.mem v (ty_vars [] t)) then Some []
  else
    match t with
    | A.TyVar w when w.A.txt = v -> Some [ [] ]
    | A.TyCon (c, args) when is_container_type c.A.txt ->
      (* Slot [j] covers every value of parameter [j] only if that parameter
         appears nowhere but in direct fields ([ctor_hidden_params]). *)
      let hidden = Option.value ~default:[] (Hashtbl.find_opt ctor_hidden_params (adt_sort_name c.A.txt)) in
      let rec go j = function
        | [] -> Some []
        | a :: _ when List.mem j hidden && List.mem v (ty_vars [] a) -> None
        | a :: rest ->
          (match container_paths v a, go (j + 1) rest with
           | Some ps, Some qs -> Some (List.map (fun p -> (c.A.txt, j) :: p) ps @ qs)
           | _ -> None)
      in
      go 0 args
    | _ -> None

(* A parameter type's arrow chain: its domains and its final result
   (`a -> a -> Bool` is [[a; a]], [Bool]).  [[]] for a non-function. *)
let rec arrow_chain (t : A.ty) : A.ty list * A.ty =
  match strip_ty t with
  | A.TyArrow (d, r) ->
    let ds, res = arrow_chain r in
    (d :: ds, res)
  | t -> ([], t)

(* A domain is a CONSUMER position: every [v] there is a value the function
   hands out.  Except under a further arrow's domain, where polarity flips
   back — `f : (a -> Int) -> Int` hands the caller's [f] a function the caller
   may apply to an [a] of its own making. *)
let rec consumer_only (v : string) (t : A.ty) : bool =
  match strip_ty t with
  | A.TyArrow (d, r) -> (not (List.mem v (ty_vars [] d))) && consumer_only v r
  | A.TyCon (_, ts) | A.TyTuple ts -> List.for_all (consumer_only v) ts
  | A.TyRecord fs -> List.for_all (fun (_, t) -> consumer_only v t) fs
  | _ -> true

let sources_of (sg : fn_sig) (v : string) : source list option =
  let per_param i (t : A.ty option) : source list option =
    match Option.map arrow_chain t with
    | None -> Some []
    | Some ([], t) ->
      (match container_paths v t with
       | Some ps -> Some (List.map (fun p -> if p = [] then Src_bare i else Src_elem (i, p)) ps)
       | None -> None)
    | Some (doms, res) ->
      if List.for_all (consumer_only v) doms then
        Option.map (List.map (fun p -> Src_cod (i, p))) (container_paths v res)
      else None
  in
  let rec go i = function
    | [] -> Some []
    | t :: rest ->
      (match per_param i t, go (i + 1) rest with
       | Some a, Some b -> Some (a @ b)
       | _ -> None)
  in
  go 0 sg.param_tys

(* The surface type a scalar element refinement stands for, so it can be put
   back on a lambda parameter ([None] for a datatype-sorted one). *)
let ty_of_refined ((b, p, srt) : string * A.expr * string option) : A.ty option =
  let base n = A.TyCon ({ A.txt = n; A.span = A.dummy_span }, []) in
  let binder = if b = "_" then None else Some { A.txt = b; A.span = A.dummy_span } in
  let mk n = Some (A.TyRefine (base n, binder, p)) in
  match srt with
  | None -> mk "Int"
  | Some s when s = str_sort -> mk "String"
  | Some s when s = bool_sort -> mk "Bool"
  | Some s when s = float_sort -> mk "Float"
  | Some _ -> None
