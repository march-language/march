(** Refinement reflection, phase 0 (specs/2026-10-29-refinement-reflection-design.md,
    §2.1 and §10): WHICH functions would be reflected, and why not.

    {1 What this pass is, and is not}

    This is the §2.1 rule computed as a greatest fixpoint over the
    termination graph ([Refine_term]).  It is INERT: nothing in the compiler
    reads it except [--reflect-report] (bin/main.ml), and no verdict changes.
    Phase 1 is what makes a reflected function's body reach the solver.

    A function is reflected when it passes R1-R9 and R11 (§2.1):
    - R1: a top-level [fn], or a local [fn] that captures nothing; not an
      [impl] method, an actor handler, an interface default, a top-level
      [let] or [main];
    - R2: a recursive unit's SCC certificate is [structural] or [metric]
      ([Refine_term.last_certs], else the phase-1 certificate); a
      non-recursive unit passes unless marked [@[diverges]];
    - R3: no effect: no [spawn] / [send] / [dbg], no effectful builtin;
    - R4: cannot fail: no [panic]-family builtin, no runtime [assert], no
      typed hole, and every [/] and [%] by a non-literal has its [Division]
      obligation PROVED in the ledger ([Obligation.by_span], read through
      [inputs.division]);
    - R5: every [match] covers (the typechecker's [nonexhaustive_match_spans],
      which records guarded matches the warning never reports);
    - R6: every callee is reflected, a builtin of the §2.3 table, or [==] whose
      every reachable [eq] passes R2-R7; any other interface dispatch blocks;
    - R7: first-order: no lambda, no [let*], no call through a value, no
      function named as a value, no function-typed parameter;
    - R8: every parameter and the result have a sort (§3.2), the result is
      not [Unit], every parameter refinement uses only predicate vocabulary;
    - R9: not [@[opaque]], [@[assume]] or [@[trusted]];
    - R11: the name a predicate would spell it by is not predicate vocabulary.

    The fixpoint starts from every unit passing its local tests and drops any
    unit with a dropped callee until nothing changes; a recursive SCC is kept
    or dropped as a whole.  Each unreflected unit's reason is its FIRST
    blocker in R-order, ties broken by source position. *)

module A = March_ast.Ast
module RT = Refine_term
module T = March_typecheck.Typecheck
module SM = Map.Make (String)

(** What the driver hands the analysis: the pieces of the check it reads. *)
type inputs = {
  certs : A.span -> string option;  (** [Refine_term.last_certs] *)
  nonexhaustive : A.span -> bool;  (** a [match] span the typechecker recorded *)
  division : A.span -> Obligation.verdict option;
      (** the [Division] verdict at a [/] or [%] call span, if one was filed *)
  type_map : (A.span, T.ty) Hashtbl.t option;
  vocab : string -> bool;  (** R11: a name predicates give a built-in meaning *)
  pred_fn : string -> bool;  (** R8: a name a predicate can apply *)
}

type blocker = { b_rule : int; b_text : string; b_span : A.span }

type verdict =
  | Reflected of string list  (** the unfolding guards (§3.6) *)
  | Blocked of blocker
  | Specialised of int  (** phase 5: a function taking functions, specialised at this many call sites *)

type row = { r_name : string; r_span : A.span; r_verdict : verdict; r_top : bool }

(* ── Phase 5 (D10): specialisation per call site ────────────────────────────
   A unit [g] whose function parameters only flow into calls [p(..)] and into
   the same position of its own recursive call has no definition of its own,
   but each call [g(xs, fn x -> e)] does: [g]'s body with the lambda put in
   place of [p] (plan: specs/plans/2026-11-03-reflection-phase5-fnvalues-plan.md). *)

(** A function argument a specialised call passes. *)
type fn_arg =
  | F_lambda of A.param list * A.expr * A.span  (** a lambda literal: parameters, body, its span *)
  | F_named of int * A.span  (** a top-level function the graph resolved at this name *)

type spec_site = {
  ss_callee : int;
  ss_caller : int;
  ss_span : A.span;  (** the call's span *)
  ss_args : A.expr list;
  ss_fn : (int * fn_arg) list;  (** each function parameter's position, and its argument *)
}

(** Units whose function parameters can be specialised, by unit id: each such
    parameter's position, name and call arity (when [g] calls it). *)
let spec_params : (int, (int * string * int option) list) Hashtbl.t = Hashtbl.create 16

(** The call sites the last [analyze] specialises, by call span: accepted
    arguments, a specialised callee, and every lambda total and pure. *)
let spec_sites : (A.span, spec_site) Hashtbl.t = Hashtbl.create 16

(** Specialised units by declaring span ([@[reflect]] accepts them). *)
let specialised : (A.span, unit) Hashtbl.t = Hashtbl.create 16

(* Test-only perturbations of phase 5, each the RED control of one rule of the
   plan's soundness table. *)
let spec_perturb (k : string) = Sys.getenv_opt "MARCH_REFLECT_PERTURB" = Some k

(* A refinement that constrains something: the abstract-refinement definer
   [a -> Bool[p]] parses with the domain [{x : a | true}], which does not. *)
let rec has_refine (t : A.ty) =
  match t with
  | A.TyRefine (b, _, A.ELit (A.LitBool true, _)) -> has_refine b
  | A.TyRefine _ -> true
  | A.TyCon (_, args) | A.TyTuple args -> List.exists has_refine args
  | A.TyArrow (a, b) | A.TyNatOp (_, a, b) -> has_refine a || has_refine b
  | A.TyRecord fs -> List.exists (fun (_, t) -> has_refine t) fs
  | A.TyLinear (_, t) -> has_refine t
  | A.TyVar _ | A.TyNat _ | A.TyChan _ -> false

(* Every name a binder anywhere in [e] introduces. *)
let binders_in (e : A.expr) : string list =
  let acc = ref [] in
  let params ps = List.map (fun (p : A.param) -> p.A.param_name.A.txt) ps in
  Refine_encode.iter_all
    (function
      | A.ELet (b, _) -> acc := RT.pat_vars b.A.bind_pat @ !acc
      | A.EMatch (_, brs, _) -> List.iter (fun (br : A.branch) -> acc := RT.pat_vars br.A.branch_pat @ !acc) brs
      | A.ELam (ps, _, _) -> acc := params ps @ !acc
      | A.ELetFn (n, ps, _, _, _) -> acc := (n.A.txt :: params ps) @ !acc
      | A.ELetQ (p, _, _, _) | A.ELetStar (p, _, _, _) -> acc := RT.pat_vars p @ !acc
      | _ -> ())
    e;
  !acc

let rec has_lambda (e : A.expr) =
  match March_ast.Bounded_pred.view e with
  | Some q -> List.exists has_lambda (q.body :: March_ast.Bounded_pred.domain_exprs q.domain)
  | None -> match e with
    | A.ELam _ | A.ELetFn _ | A.ELetStar _ -> true
    | _ -> List.exists has_lambda (Refine_encode.children e)

(* Every [/] and [%] divides by a non-zero literal. *)
let literal_divisions (e : A.expr) =
  let r = ref true in
  Refine_encode.iter_all
    (function
      | A.EApp (A.EVar { A.txt = "/" | "%"; _ }, [ _; d ], _) when Refine_encode.nonzero_int_literal d = None -> r := false
      | _ -> ())
    e;
  !r

let span_within (a : A.span) (b : A.span) =
  a.A.file = b.A.file
  && compare (a.A.start_line, a.A.start_col) (b.A.start_line, b.A.start_col) >= 0
  && compare (a.A.end_line, a.A.end_col) (b.A.end_line, b.A.end_col) <= 0

(* ── The §2.3 table ─────────────────────────────────────────────────────── *)

(* Builtins with a z3 meaning (§2.3).  [/] and [%] are R4's (the ledger),
   comparisons are checked at their argument's type, and [==] / [!=] by the
   reachable [eq]s (§3.5). *)
let table_ops =
  [ "+"; "-"; "*"; "negate"; "not"; "&&"; "||"; "+."; "-."; "*."; "/."; "<."; "<=."; ">."; ">=.";
    "string_byte_length" ]

let comparison_ops = [ "<"; "<="; ">"; ">=" ]
let eq_ops = [ "=="; "!=" ]
let div_ops = [ "/"; "%" ]

(* Set vocabulary, meaningful only inside a set-valued function. *)
let set_ops = [ "union"; "inter"; "diff"; "singleton"; "member"; "subset"; "empty"; "card" ]

let fail_builtins = [ "panic"; "panic_"; "todo"; "todo_"; "unreachable"; "unreachable_"; "exit" ]

let effect_builtins : (string, unit) Hashtbl.t Lazy.t =
  lazy
    (let t = Hashtbl.create 128 in
     List.iter (fun (n, _) -> Hashtbl.replace t n ()) March_typecheck.Typecheck_builtins.builtin_cap_table;
     List.iter (fun n -> Hashtbl.replace t n ()) RT.event_builtins;
     List.iter (fun n -> Hashtbl.replace t n ())
       [ "get_actor_field"; "self"; "receive"; "send"; "spawn"; "dbg"; "print"; "println";
         "print_line"; "print_stderr" ];
     t)

let is_effect n = Hashtbl.mem (Lazy.force effect_builtins) n

(* ── Sorts (§3.2) ───────────────────────────────────────────────────────── *)

let rec strip (t : A.ty) = match t with A.TyRefine (b, _, _) | A.TyLinear (_, b) -> strip b | t -> t

(* [None]: encodable; [Some what]: the offending type, as text. *)
let rec ast_sort ~(adts : string -> bool) (t : A.ty) : string option =
  match strip t with
  | A.TyCon (n, args) ->
    let b = RT.bare n.A.txt in
    if List.mem b [ "Int"; "Bool"; "String"; "Float"; "Set"; "Unit"; "List"; "Option"; "Result" ] || adts b then
      List.find_map (ast_sort ~adts) args
    else Some n.A.txt
  | A.TyVar _ -> None
  | A.TyTuple ts -> List.find_map (ast_sort ~adts) ts
  | A.TyRecord fs -> List.find_map (fun (_, t) -> ast_sort ~adts t) fs
  | A.TyArrow _ -> Some "a function type"
  | A.TyNat _ | A.TyNatOp _ -> Some "a type-level number"
  | A.TyChan _ -> Some "a channel"
  | A.TyRefine _ | A.TyLinear _ -> None

let rec ty_sort ~(adts : string -> bool) (t : T.ty) : string option =
  match T.repr t with
  | T.TCon (n, args) ->
    let b = RT.bare n in
    if List.mem b [ "Int"; "Bool"; "String"; "Float"; "Set"; "Unit"; "List"; "Option"; "Result" ] || adts b then
      List.find_map (ty_sort ~adts) args
    else Some (T.pp_ty t)
  | T.TVar _ -> None
  | T.TTuple ts -> List.find_map (ty_sort ~adts) ts
  | T.TRecord fs -> List.find_map (fun (_, t) -> ty_sort ~adts t) fs
  | T.TLin (_, t) | T.TRefine (t, _, _) -> ty_sort ~adts t
  | T.TArrow _ -> Some "a function type"
  | _ -> Some (T.pp_ty t)

let ast_is_unit (t : A.ty) =
  match strip t with
  | A.TyCon ({ A.txt = "Unit"; _ }, []) | A.TyTuple [] -> true
  | _ -> false

let ty_is_unit (t : T.ty) =
  match T.repr t with T.TCon ("Unit", []) | T.TTuple [] -> true | _ -> false

let ast_is_arrow (t : A.ty) = match strip t with A.TyArrow _ -> true | _ -> false

let ty_is_arrow (t : T.ty) =
  match T.repr t with T.TArrow _ -> true | T.TLin (_, t) -> (match T.repr t with T.TArrow _ -> true | _ -> false) | _ -> false

(* ── Origins: what declared each unit ───────────────────────────────────── *)

type origin = O_fn | O_impl of string | O_default | O_let | O_handler

(* A type for report text: an unsolved variable reads as such, not as its
   internal name. *)
let pp_ty (t : T.ty) = match T.repr t with T.TVar _ -> "a type variable" | _ -> T.pp_ty t

let span_str (s : A.span) = Printf.sprintf "%s:%d:%d" s.A.file s.A.start_line s.A.start_col

let pos_lt (a : A.span) (b : A.span) = compare (a.A.start_line, a.A.start_col) (b.A.start_line, b.A.start_col) < 0

(* ── The body walk: syntax-level events per unit ────────────────────────── *)

type ev = { ev_rule : int; ev_text : string; ev_span : A.span }

(** Scoped proof validation: a missing entry is outside a checked body,
    [None] is valid, and [Some reason] records a rejected proof body. *)
let proof_blocks : (A.span, string option) Hashtbl.t = Hashtbl.create 16

(** Lemmas (§4.2) the last [analyze] found invalid under L2 or L3, by
    declaring span: (2 or 3, the first offending event's text). *)
let lemma_blocked : (A.span, int * string) Hashtbl.t = Hashtbl.create 16

(** L5: each site the last [analyze] found naming a lemma as a value, with
    the lemma's name. *)
let lemma_value_uses : (A.span * string) list ref = ref []

type bind = { k_var : bool;  (** a value ([false]: a local [fn]) *) k_owner : A.span  (** the unit that bound it *) }

(* `reveal f` (todo 2026-11-06-proof-reveal-and-local-fuel): the [@[opaque]]
   units that are blocked by R9 alone (every other rule passes, every callee is
   reflected, and the unit is alone in its SCC).  [analyze] fills it; the rows
   and every caller's verdict are unchanged, so nothing that does not say
   `reveal` sees a difference. *)
let revealable : (A.span, unit) Hashtbl.t = Hashtbl.create 8

let analyze (inp : inputs) (t : RT.t) (decls : A.decl list) : row list =
  let g = t.RT.graph in
  let n = Array.length g.RT.units in
  let units_at : (A.span, int) Hashtbl.t = Hashtbl.create 256 in
  Array.iter (fun (u : RT.unit_) -> Hashtbl.add units_at u.RT.u_span u.RT.u_id) g.RT.units;
  let origin : (A.span, origin) Hashtbl.t = Hashtbl.create 256 in
  let events : (A.span, ev) Hashtbl.t = Hashtbl.create 256 in
  let emit owner rule text span = Hashtbl.add events owner { ev_rule = rule; ev_text = text; ev_span = span } in
  (* Declared data types: an ADT or record has a sort (§3.2). *)
  let adt_tbl = RT.collect_types decls in
  (* A declared data type has a sort unless a field, at any depth, holds a
     function (§3.2). *)
  let adt_memo = Hashtbl.create 64 in
  let rec adts b =
    match Hashtbl.find_opt adt_memo b with
    | Some r -> r
    | None -> (
      match Hashtbl.find_opt adt_tbl b with
      | None -> false
      | Some d ->
        Hashtbl.replace adt_memo b true;  (* a recursive type is assumed fine while visited *)
        let rec ok (t : A.ty) =
          match strip t with
          | A.TyArrow _ -> false
          | A.TyCon (n, args) ->
            let h = RT.bare n.A.txt in
            (not (Hashtbl.mem adt_tbl h) || adts h) && List.for_all ok args
          | A.TyTuple ts -> List.for_all ok ts
          | A.TyRecord fs -> List.for_all (fun (_, t) -> ok t) fs
          | _ -> true
        in
        let r = List.for_all ok d.RT.t_fields in
        Hashtbl.replace adt_memo b r;
        r)
  in
  (* Types with a hand-written [impl Eq]: a derived impl's interface name has
     the synthetic file "<none>" ([Desugar_derive.respan_derived_decl]). *)
  let hand_eq = Hashtbl.create 16 in
  let rec scan_eq ds =
    List.iter
      (function
        | A.DImpl (idf, _) when RT.bare idf.A.impl_iface.A.txt = "Eq" && idf.A.impl_iface.A.span.A.file <> "<none>" -> (
          match strip idf.A.impl_ty with A.TyCon (n, _) -> Hashtbl.replace hand_eq (RT.bare n.A.txt) () | _ -> ())
        | A.DMod (_, _, inner, _) -> scan_eq inner
        | _ -> ())
      ds
  in
  scan_eq decls;
  let proof_depth = ref 0 in
  let rec walk ~(owner : A.span) ~(local : bool) (env : bind SM.t) (e : A.expr) : unit =
    let w = walk ~owner ~local env in
    match March_ast.Bounded_pred.view e with
    | Some q ->
      List.iter w (March_ast.Bounded_pred.domain_exprs q.domain);
      let env = SM.add q.binder.txt {k_var = true; k_owner = owner} env in
      walk ~owner ~local env q.body
    | None -> match e with
    | A.EVar v -> (
      match SM.find_opt v.A.txt env with
      | Some { k_var = true; k_owner } when local && k_owner <> owner ->
        emit owner 1 (Printf.sprintf "captures %s" v.A.txt) v.A.span
      | _ -> ())
    | A.ELam (ps, body, sp) ->
      emit owner 7 "contains a lambda" sp;
      let env' =
        List.fold_left
          (fun env (p : A.param) -> SM.add p.A.param_name.A.txt { k_var = true; k_owner = owner } env)
          env ps
      in
      walk ~owner ~local env' body
    | A.ESpawn (x, sp) -> emit owner 3 "spawns an actor" sp; w x
    | A.ESend (a, b, sp) -> emit owner 3 "sends a message" sp; w a; w b
    | A.EDbg (x, sp) -> emit owner 3 "calls dbg" sp; Option.iter w x
    | A.EProof (A.PReveal _, _) -> ()
    | A.EProof (A.PWithFuel (_, _, body), sp) -> w (A.EBlock (body, sp))
    | A.EProof (A.PAssertBy (p, hs), sp) ->
      let saved = !proof_depth in
      Fun.protect ~finally:(fun () -> proof_depth := saved)
        (fun () -> proof_depth := saved + 1; w p; w (A.EBlock (hs, sp)))
    | A.EAssert (x, sp) ->
      if !proof_depth = 0 then emit owner 4 "has a runtime `assert`" sp;
      w x
    | A.EHole (_, sp) -> emit owner 4 "has a typed hole" sp
    | A.EMatch (s, brs, sp) ->
      if inp.nonexhaustive sp then begin
        if List.exists (fun (b : A.branch) -> b.A.branch_guard <> None) brs then begin
          (* Test-only: the parity net's C2 control admits a guarded match. *)
          if Sys.getenv_opt "MARCH_REFLECT_PERTURB" <> Some "r5-guarded" then
            emit owner 5 "guarded match may not match" sp
        end
        else emit owner 5 "non-exhaustive match" sp
      end;
      w s;
      List.iter
        (fun (br : A.branch) ->
          let env' =
            List.fold_left
              (fun env x -> SM.add x { k_var = true; k_owner = owner } env)
              env (RT.pat_vars br.A.branch_pat)
          in
          Option.iter (walk ~owner ~local env') br.A.branch_guard;
          walk ~owner ~local env' br.A.branch_body)
        brs
    | A.ECond (arms, sp) ->
      (match List.rev arms with
       | (A.ELit (A.LitBool true, _), _) :: _ -> ()
       | _ -> emit owner 5 "`match do` may fall through" sp);
      List.iter (fun (c, b) -> w c; w b) arms
    | A.EBlock (es, _) -> ignore (List.fold_left (fun env x -> item ~owner ~local env x) env es)
    | A.ELet (b, _) -> w b.A.bind_expr
    | A.ELetFn _ -> ignore (item ~owner ~local env e)
    | A.ELetQ (p, r, c, _) ->
      w r;
      walk ~owner ~local (bind_pat ~owner env p) c
    | A.ELetStar (p, r, c, sp) ->
      emit owner 7 "uses `let*` (a callback)" sp;
      w r;
      walk ~owner ~local (bind_pat ~owner env p) c
    | e -> List.iter w (Refine_encode.children e)
  and bind_pat ~owner env p =
    List.fold_left (fun env x -> SM.add x { k_var = true; k_owner = owner } env) env (RT.pat_vars p)
  and item ~owner ~local env (e : A.expr) =
    match e with
    | A.ELet (b, _) ->
      walk ~owner ~local env b.A.bind_expr;
      bind_pat ~owner env b.A.bind_pat
    | A.ELetFn (name, ps, _, body, _) ->
      let lspan = name.A.span in
      Hashtbl.replace origin lspan O_fn;
      let env = SM.add name.A.txt { k_var = false; k_owner = owner } env in
      let inner =
        List.fold_left
          (fun env (p : A.param) -> SM.add p.A.param_name.A.txt { k_var = true; k_owner = lspan } env)
          env ps
      in
      walk ~owner:lspan ~local:true inner body;
      env
    | e ->
      walk ~owner ~local env e;
      env
  in
  let walk_fn ~(o : origin) (fd : A.fn_def) =
    let owner = fd.A.fn_name.A.span in
    Hashtbl.replace origin owner o;
    List.iter
      (fun (c : A.fn_clause) ->
        let env =
          List.fold_left
            (fun env x -> SM.add x { k_var = true; k_owner = owner } env)
            SM.empty (RT.clause_binders c)
        in
        Option.iter (walk ~owner ~local:false env) c.A.fc_guard;
        walk ~owner ~local:false env c.A.fc_body)
      fd.A.fn_clauses
  in
  let rec walk_decls (ds : A.decl list) =
    List.iter
      (fun (d : A.decl) ->
        match d with
        | A.DFn (fd, _) -> walk_fn ~o:O_fn fd
        | A.DImpl (idf, _) ->
          let ty =
            match strip idf.A.impl_ty with
            | A.TyCon (n, []) -> n.A.txt
            | A.TyCon (n, _) -> n.A.txt ^ "(..)"
            | _ -> "_"
          in
          List.iter
            (fun ((mn : A.name), fd) ->
              walk_fn ~o:(O_impl (Printf.sprintf "impl %s(%s).%s" (RT.bare idf.A.impl_iface.A.txt) ty mn.A.txt)) fd)
            idf.A.impl_methods
        | A.DInterface (idf, _) ->
          List.iter
            (fun (md : A.method_decl) -> Hashtbl.replace origin md.A.md_name.A.span O_default)
            idf.A.iface_methods
        | A.DLet (_, b, _) ->
          let rec names (p : A.pattern) : A.name list =
            match p with
            | A.PatVar n -> [ n ]
            | A.PatAs (p, n, _) -> n :: names p
            | A.PatCon (_, ps) | A.PatAtom (_, ps, _) | A.PatTuple (ps, _) | A.PatOr (ps, _) ->
              List.concat_map names ps
            | A.PatRecord (fs, _) -> List.concat_map (fun (_, p) -> names p) fs
            | A.PatWild _ | A.PatLit _ -> []
          in
          List.iter (fun (nm : A.name) -> Hashtbl.replace origin nm.A.span O_let) (names b.A.bind_pat)
        | A.DActor (_, _, actor, _) ->
          List.iter
            (fun (h : A.actor_handler) -> Hashtbl.replace origin h.A.ah_msg.A.span O_handler)
            (A.actor_body_handlers actor)
        | A.DMod (_, _, inner, _) -> walk_decls inner
        | _ -> ())
      ds
  in
  walk_decls decls;
  let unit_ i = g.RT.units.(i) in
  let origin_of (u : RT.unit_) =
    match u.RT.u_kind with
    | RT.Handler -> O_handler
    | _ -> Option.value ~default:O_fn (Hashtbl.find_opt origin u.RT.u_span)
  in
  let impl_name (u : RT.unit_) =
    match origin_of u with O_impl s -> s | _ -> u.RT.u_name
  in
  (* `$len` by resolved identity (I3): the unit must be the STDLIB's
     `List.length` / `String.byte_size`, and the encoder's own gate must agree
     that the spelling denotes it in this program ([Refine_encode]'s
     [list_length_is_stdlib] &c).  A user `mod List do fn length …` is an
     ordinary callee. *)
  let is_len_unit v =
    let u = unit_ v in
    March_typecheck.Typecheck_builtins.file_is_stdlib u.RT.u_span.A.file
    &&
    match RT.bare u.RT.u_name, u.RT.u_name with
    | "length", ("List.length" | "length") ->
      !Refine_encode.list_length_is_stdlib && Filename.basename u.RT.u_span.A.file = "list.march"
    | "byte_size", ("String.byte_size" | "byte_size") ->
      !Refine_encode.string_byte_size_is_stdlib && Filename.basename u.RT.u_span.A.file = "string.march"
    | _ -> false
  in
  let ty_at sp = match inp.type_map with Some tm -> Hashtbl.find_opt tm sp | None -> None in
  let arg_ty (s : RT.site) = match s.RT.s_args with a :: _ -> ty_at (T.span_of_expr a) | [] -> None in
  let is_set_result (u : RT.unit_) =
    match u.RT.u_ret with
    | Some r -> (match strip r with A.TyCon ({ A.txt = "Set"; _ }, _) -> true | _ -> false)
    | None -> false
  in
  (* The builtin a callee denotes: a builtin itself, or a stdlib [Prelude]
     function that shadows the builtin of the same name (the compiled
     `println` is `Prelude.println`). *)
  let builtin_identity (s : RT.site) =
    match s.RT.s_target with
    | RT.S_builtin | RT.S_impls _ -> Some s.RT.s_name
    | RT.S_unit v
      when (unit_ v).RT.u_name = "Prelude." ^ s.RT.s_name
           || (Filename.basename (unit_ v).RT.u_span.A.file = "prelude.march"
               && RT.bare (unit_ v).RT.u_name = RT.bare s.RT.s_name) ->
      Some s.RT.s_name
    | _ -> None
  in
  (* ── Local events from the graph's sites; dependencies for the fixpoint ── *)
  let sites = Array.make n [] in
  List.iter (fun (s : RT.site) -> sites.(s.RT.s_src) <- s :: sites.(s.RT.s_src)) g.RT.sites;
  let deps = Array.make n [] in
  (* The calls inside signatures' refinement predicates, by application span
     ([Refine_term.graph.pred_sites]): R8 reads them by site (phase 1b). *)
  let pred_site_tbl : (A.span, RT.site_target) Hashtbl.t = Hashtbl.create 64 in
  List.iter (fun (sp, tgt) -> Hashtbl.replace pred_site_tbl sp tgt) g.RT.pred_sites;
  (* Phase 5: the lambdas and function names a specialised call passes
     (filled below, before [site_events] runs), and each accepted call's
     arguments by call span. *)
  let accepted_lam : (A.span, unit) Hashtbl.t = Hashtbl.create 16 in
  let accepted_ref : (A.span, unit) Hashtbl.t = Hashtbl.create 16 in
  let site_spec : (A.span, (int * fn_arg) list) Hashtbl.t = Hashtbl.create 16 in
  let is_fn_param (u : RT.unit_) nm =
    match Hashtbl.find_opt spec_params u.RT.u_id with
    | Some fps -> List.exists (fun (_, p, _) -> p = nm) fps
    | None -> false
  in
  (* [`Refl v]: v must be reflected; [`Eq ids]: each must pass R2-R7 with its
     callees ([==], §3.5). *)
  let site_events (u : RT.unit_) : ev list =
    let evs = ref [] in
    let add rule text span = evs := { ev_rule = rule; ev_text = text; ev_span = span } :: !evs in
    List.iter
      (fun (s : RT.site) ->
        let nm = s.RT.s_name and sp = s.RT.s_span in
        let ident = builtin_identity s in
        (match ident with
         | Some b when is_effect b -> add 3 (Printf.sprintf "calls %s" b) sp
         | Some b when List.mem b fail_builtins -> add 4 (Printf.sprintf "calls %s" b) sp
         | _ -> ());
        if not s.RT.s_call then begin
          match s.RT.s_target with
          | RT.S_unit v when origin_of (unit_ v) = O_let && not (match (unit_ v).RT.u_clauses with
                                                                 | [ { RT.o_params = _ :: _; _ } ] -> true
                                                                 | _ -> false) ->
            add 6 (Printf.sprintf "reads the top-level `let` %s, which is not reflected" nm) sp
          | _ when Hashtbl.mem accepted_ref sp -> ()
          | _ -> add 7 (Printf.sprintf "names %s as a value" nm) sp
        end
        else if Hashtbl.mem g.RT.ambiguous sp then
          (* More than one declaration could be meant here (review C-A,
             C-B; third review C1): a body that calls it has no single
             definition, so the function is not reflected. *)
          add 6 (Printf.sprintf "calls %s, a name more than one declaration could denote" nm) sp
        else
          match s.RT.s_target with
          (* A call of the specialised unit's own function parameter: the
             lambda's body, at each specialisation (phase 5). *)
          | RT.S_value when is_fn_param u nm -> ()
          | RT.S_value ->
            add 7
              (if nm = "" then "calls through a function value"
               else Printf.sprintf "calls through the value %s" nm)
              sp
          | RT.S_extern -> add 6 (Printf.sprintf "calls the extern %s" nm) sp
          | RT.S_unresolved -> add 6 (Printf.sprintf "calls %s, which the checker cannot resolve" nm) sp
          | RT.S_unit v when is_len_unit v -> ()
          | RT.S_unit v when ident <> None && (is_effect nm || List.mem nm fail_builtins) -> ignore v
          | RT.S_unit v when Hashtbl.mem spec_params v && v <> u.RT.u_id -> (
            (* Phase 5: a call of a specialisable unit.  Each function
               argument must be a lambda or a function the graph resolved;
               a named one must itself be reflected. *)
            match Hashtbl.find_opt site_spec sp with
            | Some fa ->
              deps.(u.RT.u_id) <- (`Refl v, s) :: deps.(u.RT.u_id);
              List.iter
                (function
                  | _, F_named (f, _) -> deps.(u.RT.u_id) <- (`Refl f, s) :: deps.(u.RT.u_id)
                  | _, F_lambda _ -> ())
                fa
            | None ->
              add 7
                (Printf.sprintf "passes %s a function value that is not a lambda or a function's name" nm)
                sp)
          | RT.S_unit v -> deps.(u.RT.u_id) <- (`Refl v, s) :: deps.(u.RT.u_id)
          | RT.S_impls ids when List.mem nm eq_ops ->
            if ids <> [] then deps.(u.RT.u_id) <- (`Eq ids, s) :: deps.(u.RT.u_id)
          | RT.S_impls (i :: _) when not (is_effect nm || List.mem nm fail_builtins) ->
            add 6 (Printf.sprintf "dispatches to %s (via %s)" (impl_name (unit_ i)) nm) sp
          | RT.S_impls _ | RT.S_builtin when is_effect nm || List.mem nm fail_builtins -> ()
          | RT.S_impls [] | RT.S_builtin ->
            if List.mem nm table_ops then ()
            else if List.mem nm div_ops then begin
              match s.RT.s_args with
              | [ _; d ] when Refine_encode.nonzero_int_literal d <> None -> ()
              | [ _; A.ELit (A.LitInt 0, _) ] -> add 4 "divides by zero" sp
              | [ _; d ] -> (
                match inp.division sp with
                | Some Obligation.Proved -> ()
                | _ ->
                  let what = match d with A.EVar v -> v.A.txt | _ -> "an expression" in
                  add 4 (Printf.sprintf "division by %s not proved" what) sp)
              | _ -> add 4 "division not proved" sp
            end
            else if List.mem nm comparison_ops then begin
              match arg_ty s with
              | Some ty -> (
                match T.repr ty with
                | T.TCon (("Int" | "Float"), []) -> ()
                | _ -> add 6 (Printf.sprintf "calls %s at %s" nm (pp_ty ty)) sp)
              | None -> add 6 (Printf.sprintf "calls %s at a type the checker did not record" nm) sp
            end
            else if List.mem nm set_ops && is_set_result u then ()
            else add 6 (Printf.sprintf "calls %s" nm) sp
          | RT.S_impls _ -> ())
      (List.rev sites.(u.RT.u_id));
    !evs
  in
  (* ── Per-unit local blockers ──────────────────────────────────────────── *)
  let cert_of (u : RT.unit_) =
    match inp.certs u.RT.u_span with
    | Some c -> c
    | None -> RT.cert_name t.RT.certs.(g.RT.scc_of.(u.RT.u_id))
  in
  let param_ty (u : RT.unit_) i =
    let ast = match List.nth_opt u.RT.u_param_tys i with Some (Some t) -> Some t | _ -> None in
    let typed =
      match List.nth_opt u.RT.u_param_spans i with Some (Some sp) -> ty_at sp | _ -> None
    in
    (ast, typed)
  in
  (* ── Phase 5 (D10): which units specialise, which calls are accepted ──── *)
  Hashtbl.reset spec_params;
  Hashtbl.reset spec_sites;
  Hashtbl.reset specialised;
  let call_at : (A.span, RT.site) Hashtbl.t = Hashtbl.create 256 in
  let ref_at : (A.span, RT.site) Hashtbl.t = Hashtbl.create 64 in
  List.iter (fun (s : RT.site) -> Hashtbl.replace (if s.RT.s_call then call_at else ref_at) s.RT.s_span s) g.RT.sites;
  let is_arrow_param u i =
    match param_ty u i with Some a, _ when ast_is_arrow a -> true | _, Some t when ty_is_arrow t -> true | _ -> false
  in
  (* A refinement on what a function parameter is called with: a lambda's
     body could rely on it, so the parameter is not specialised.  The
     result's abstract refinement ([Bool[p]]) is the lambda's promise and
     does not matter here. *)
  let rec domain_refined (t : A.ty) =
    match t with
    | A.TyRefine (b, _, A.ELit (A.LitBool true, _)) -> domain_refined b
    | A.TyRefine _ -> true
    | A.TyLinear (_, b) -> domain_refined b
    | A.TyArrow (a, b) -> has_refine a || (match b with A.TyArrow _ -> domain_refined b | _ -> false)
    | _ -> false
  in
  Array.iter
    (fun (u : RT.unit_) ->
      let fps = List.filter_map (fun i -> if is_arrow_param u i then Some i else None) (List.init (List.length u.RT.u_params) Fun.id) in
      if fps <> [] && not (List.mem "lemma" u.RT.u_attrs) then
        match u.RT.u_clauses with
        | [ c ] when g.RT.sccs.(g.RT.scc_of.(u.RT.u_id)) = [ u.RT.u_id ] -> (
          let named = List.map (fun i -> (i, List.nth c.RT.o_params i)) fps in
          if List.for_all (fun (_, n) -> n <> None) named then begin
            let fps = List.map (fun (i, n) -> (i, Option.get n)) named in
            let names = List.map snd fps in
            let ok =
              ref
                ((not (has_lambda c.RT.o_body))
                 && not (List.exists (fun b -> List.mem b names) (binders_in c.RT.o_body)))
            in
            List.iter
              (fun (i, _) ->
                match List.nth_opt u.RT.u_param_tys i with Some (Some a) when domain_refined a -> ok := false | _ -> ())
              fps;
            let arity = Hashtbl.create 4 in
            let self_call sp =
              (not (Hashtbl.mem g.RT.ambiguous sp))
              && match Hashtbl.find_opt call_at sp with Some { RT.s_target = RT.S_unit v; _ } -> v = u.RT.u_id | _ -> false
            in
            (* Every occurrence of a function parameter is a call of it, or
               the same position of a call of [u] itself. *)
            let rec occ (e : A.expr) =
              match e with
              | A.EVar v when List.mem v.A.txt names -> ok := false
              | A.EApp (A.EVar f, args, _) when List.mem f.A.txt names ->
                let k = List.length args in
                (match Hashtbl.find_opt arity f.A.txt with
                 | Some k' when k' <> k -> ok := false
                 | _ -> Hashtbl.replace arity f.A.txt k);
                List.iter occ args
              | A.EApp (A.EVar _, args, sp) when self_call sp ->
                List.iteri
                  (fun i a ->
                    match List.assoc_opt i fps, a with
                    | Some p, A.EVar v when v.A.txt = p -> ()
                    | Some _, A.EVar v when spec_perturb "spec-any-position" && List.mem v.A.txt names -> ()
                    | Some _, _ -> ok := false
                    | None, a -> occ a)
                  args
              | e -> List.iter occ (Refine_encode.children e)
            in
            occ c.RT.o_body;
            if !ok then
              Hashtbl.replace spec_params u.RT.u_id
                (List.map (fun (i, p) -> (i, p, Hashtbl.find_opt arity p)) fps)
          end)
        | _ -> ())
    g.RT.units;
  (* The function [n] names, when the graph resolved THIS occurrence to a
     top-level unit (never by spelling: a local value of that name has no
     site, review lesson of phase 1a). *)
  let named_fn (n : A.name) : int option =
    if spec_perturb "spec-by-spelling" then
      (* Test-only: the RED control, a lookup by bare name. *)
      List.find_map
        (fun (v : RT.unit_) -> if v.RT.u_kind = RT.Top && RT.bare v.RT.u_name = n.A.txt then Some v.RT.u_id else None)
        (Array.to_list g.RT.units)
    else if Hashtbl.mem g.RT.ambiguous n.A.span then None
    else
      match Hashtbl.find_opt ref_at n.A.span with
      | Some { RT.s_target = RT.S_unit f; _ } when (unit_ f).RT.u_kind = RT.Top -> Some f
      | _ -> None
  in
  List.iter
    (fun (s : RT.site) ->
      match s.RT.s_target with
      | RT.S_unit v
        when s.RT.s_call && v <> s.RT.s_src && Hashtbl.mem spec_params v && not (Hashtbl.mem g.RT.ambiguous s.RT.s_span) ->
        let args = Array.of_list s.RT.s_args in
        let one (i, _, ar) =
          if i >= Array.length args then None
          else
            match args.(i) with
            | A.ELam (ps, body, lsp)
              when (match ar with Some k -> List.length ps = k | None -> true)
                   && List.for_all
                        (fun (p : A.param) -> match p.A.param_ty with Some t -> not (has_refine t) | None -> true)
                        ps
                   && (not (has_lambda body))
                   && literal_divisions body ->
              Some (i, F_lambda (ps, body, lsp))
            | A.EVar n -> (
              match named_fn n with
              | Some f
                when (not (Hashtbl.mem spec_params f))
                     && (match ar with Some k -> List.length (unit_ f).RT.u_params = k | None -> false) ->
                Some (i, F_named (f, n.A.span))
              | _ -> None)
            | _ -> None
        in
        let got = List.map one (Hashtbl.find spec_params v) in
        if List.for_all Option.is_some got then begin
          let fa = List.map Option.get got in
          Hashtbl.replace site_spec s.RT.s_span fa;
          List.iter
            (function
              | _, F_lambda (_, _, lsp) -> Hashtbl.replace accepted_lam lsp ()
              | _, F_named (_, sp) -> Hashtbl.replace accepted_ref sp ())
            fa
        end
      | _ -> ())
    g.RT.sites;
  (* An accepted lambda is not R7's "contains a lambda": its body is the
     caller's code, and its own events stay the caller's. *)
  Hashtbl.filter_map_inplace
    (fun _ e -> if e.ev_rule = 7 && e.ev_text = "contains a lambda" && Hashtbl.mem accepted_lam e.ev_span then None else Some e)
    events;
  let unit_events (u : RT.unit_) : ev list =
    let evs = ref (Hashtbl.find_all events u.RT.u_span) in
    let add rule text span = evs := { ev_rule = rule; ev_text = text; ev_span = span } :: !evs in
    let sp = u.RT.u_span in
    let bare_name = RT.bare u.RT.u_name in
    (* R1 *)
    (match origin_of u with
     | O_handler -> add 1 "is an actor handler" sp
     | O_impl _ -> add 1 "is an `impl` method" sp
     | O_default -> add 1 "is an interface default method" sp
     | O_let -> add 1 "is a top-level `let`" sp
     | O_fn -> if u.RT.u_name = "main" then add 1 "is `main`" sp);
    (* A stdlib member whose qualified spelling this program re-defines
       (`mod String do … byte_size …`): the encoder's alias gate withdrew
       the spelling ([Refine_encode.string_byte_size_is_stdlib] &c), and a
       call the termination graph resolved to the stdlib's unit may be the
       program's own member.  Not reflected, so no such call gains a
       definition (accept/t127). *)
    (if March_typecheck.Typecheck_builtins.file_is_stdlib sp.A.file then
       let file = Filename.basename sp.A.file in
       let withdrawn =
         match bare_name, file with
         | "length", "list.march" -> not !Refine_encode.list_length_is_stdlib
         | "byte_size", "string.march" -> not !Refine_encode.string_byte_size_is_stdlib
         | "length", "array.march" -> not !Refine_encode.array_length_is_stdlib
         | _ -> false
       in
       if withdrawn then add 6 "is a stdlib member this program's own module re-defines" sp);
    (* R2 *)
    if RT.is_recursive g u.RT.u_id then begin
      match cert_of u with
      | "structural" | "metric" -> ()
      | _
        when spec_perturb "spec-lambda-own-unit"
             && List.for_all
                  (fun (e : RT.edge) ->
                    g.RT.scc_of.(e.RT.e_dst) <> g.RT.scc_of.(u.RT.u_id) || e.RT.e_kind = RT.Lambda)
                  g.RT.out.(u.RT.u_id) ->
        (* Test-only: the RED control of recursion through a lambda. *)
        ()
      | c -> add 2 c sp
    end
    else if RT.is_diverges u then add 2 "diverges" sp;
    (* R7: a function-typed parameter *)
    List.iteri
      (fun i p ->
        let nm = match p with Some s -> s | None -> Printf.sprintf "#%d" (i + 1) in
        match param_ty u i with
        | _ when Hashtbl.mem spec_params u.RT.u_id -> ()  (* specialised per call site (phase 5) *)
        | Some a, _ when ast_is_arrow a -> add 7 (Printf.sprintf "takes a function-typed parameter %s" nm) sp
        | _, Some t when ty_is_arrow t -> add 7 (Printf.sprintf "takes a function-typed parameter %s" nm) sp
        | _ -> ())
      u.RT.u_params;
    (* R8 *)
    List.iteri
      (fun i p ->
        let nm = match p with Some s -> s | None -> Printf.sprintf "#%d" (i + 1) in
        let bad =
          match param_ty u i with
          | Some a, _ when not (ast_is_arrow a) -> ast_sort ~adts a
          | _, Some t when not (ty_is_arrow t) -> ty_sort ~adts t
          | _ -> None
        in
        Option.iter (fun what -> add 8 (Printf.sprintf "parameter %s has type %s, which has no sort" nm what) sp) bad;
        (* a parameter refinement must translate: only predicate vocabulary *)
        match param_ty u i with
        | Some a, _ -> (
          let rec refines (t : A.ty) =
            match t with
            | A.TyRefine (b, _, pred) -> pred :: refines b
            | A.TyLinear (_, b) -> refines b
            | _ -> []
          in
          let bad = ref None in
          List.iter
            (Refine_encode.iter_all (function
              | A.EApp (A.EVar f, args, csp) when !bad = None && not (inp.pred_fn f.A.txt) -> (
                (* Phase 1b: a call of a function the termination graph
                   resolved AT THIS SITE, in the scope the predicate is
                   written in, translates through that function's logic
                   symbol, so the function must itself be reflected (a
                   fixpoint dependency, like a body call).  A name two
                   declarations could supply, or one the graph did not
                   resolve to a unit, does not translate: R8 as before. *)
                match Hashtbl.find_opt pred_site_tbl csp with
                | Some (RT.S_unit _) when Sys.getenv_opt "MARCH_REFLECT_PERTURB" = Some "guard-no-dep" ->
                  (* Test-only: the RED control of the dependency. *)
                  ()
                | Some (RT.S_unit v) when not (Hashtbl.mem g.RT.ambiguous csp) ->
                  deps.(u.RT.u_id) <-
                    ( `Refl v,
                      { RT.s_src = u.RT.u_id; s_name = f.A.txt; s_span = csp; s_call = true; s_args = args;
                        s_target = RT.S_unit v } )
                    :: deps.(u.RT.u_id)
                | _ -> bad := Some f.A.txt)
              | _ -> ()))
            (refines a);
          match !bad with
          | Some f ->
            add 8 (Printf.sprintf "the refinement of %s does not translate (%s is not predicate vocabulary)" nm f) sp
          | None ->
            (* §3.5: a guard's `==` is structural; at a type with a
               hand-written Eq the checker does not translate it the way
               the program reads it (g1: the call site skips
               `sort-conflict`), so it cannot be the unfolding guard. *)
            (* `==` AT THE PARAMETER'S TYPE: one operand is the binder
               itself (`_ == P(1, 2)`).  `len(_) == 3` compares Ints. *)
            let rec binders (t : A.ty) =
              match t with
              | A.TyRefine (b, bn, pred) ->
                ((match bn with Some n -> n.A.txt | None -> "_"), pred) :: binders b
              | A.TyLinear (_, b) -> binders b
              | _ -> []
            in
            let uses_eq = ref false in
            List.iter
              (fun (bn, pred) ->
                Refine_encode.iter_all
                  (function
                    | A.EApp (A.EVar { A.txt = "==" | "!="; _ }, [ x; y ], _)
                      when List.exists (function A.EVar v -> v.A.txt = bn | _ -> false) [ x; y ] ->
                      uses_eq := true
                    | _ -> ())
                  pred)
              (binders a);
            if !uses_eq then
              match List.find_opt (fun c -> Hashtbl.mem hand_eq c) (RT.ty_cons (strip a)) with
              | Some c ->
                add 8 (Printf.sprintf "the refinement of %s uses == at %s, which has a hand-written Eq" nm c) sp
              | None -> ())
        | _ -> ())
      u.RT.u_params;
    let body_ty () =
      match u.RT.u_clauses with c :: _ -> ty_at (T.span_of_expr c.RT.o_body) | [] -> None
    in
    (match u.RT.u_ret with
     | Some r when ast_is_unit r -> add 8 "returns Unit" sp
     | Some r -> Option.iter (fun w -> add 8 (Printf.sprintf "the result has type %s, which has no sort" w) sp) (ast_sort ~adts r)
     | None -> (
       match body_ty () with
       | Some t when ty_is_unit t -> add 8 "returns Unit" sp
       | Some t -> Option.iter (fun w -> add 8 (Printf.sprintf "the result has type %s, which has no sort" w) sp) (ty_sort ~adts t)
       | None -> ()));
    (* R9 *)
    List.iter
      (fun a -> if List.mem a u.RT.u_attrs then add 9 (Printf.sprintf "@[%s]" a) sp)
      [ "opaque"; "assume"; "trusted" ];
    (* R11: the bare name, which is how a predicate inside the function's own
       module spells it, and there the vocabulary wins (F21).  Bare in every
       module, so the verdict does not depend on which file is the entry. *)
    let spelled = bare_name in
    if (not (String.contains spelled '/')) && inp.vocab spelled then
      add 11 (Printf.sprintf "its name `%s` is predicate vocabulary" spelled) sp;
    !evs @ site_events u
  in
  let local = Array.map (fun u -> unit_events u) g.RT.units in
  let first (evs : ev list) =
    List.fold_left
      (fun acc e ->
        match acc with
        | Some a when a.ev_rule < e.ev_rule || (a.ev_rule = e.ev_rule && not (pos_lt e.ev_span a.ev_span)) -> acc
        | _ -> Some e)
      None evs
  in
  (* ── The greatest fixpoint ─────────────────────────────────────────────── *)
  let refl = Array.map (fun evs -> evs = []) local in
  (* EqOK: R2-R7 (§3.5, C4): an [impl Eq] method's own R1 does not apply. *)
  let eqok = Array.map (List.for_all (fun e -> e.ev_rule < 2 || e.ev_rule > 7)) local in
  (* A call of a lemma is `()` in the logic (§4.5, I2): it is erased before the
     program runs, so it neither blocks its caller nor needs a definition. *)
  let dep_ok (d, _) =
    match d with
    | `Refl v -> refl.(v) || List.mem "lemma" (unit_ v).RT.u_attrs
    | `Eq ids -> List.for_all (fun i -> eqok.(i)) ids
  in
  let changed = ref true in
  while !changed do
    changed := false;
    for i = 0 to n - 1 do
      if refl.(i) && not (List.for_all dep_ok deps.(i)) then (refl.(i) <- false; changed := true);
      if eqok.(i) && not (List.for_all dep_ok deps.(i)) then (eqok.(i) <- false; changed := true)
    done;
    (* A recursive SCC is reflected as a whole or not at all. *)
    Array.iter
      (fun members ->
        (* An [impl] method in the group is never reflected (R1), but an
           [eq] that passes R2-R7 is what [==] needs (§3.5): it does not
           drop its callers. *)
        let blocks v = (not refl.(v)) && not (eqok.(v) && match origin_of (unit_ v) with O_impl _ -> true | _ -> false) in
        if List.exists blocks members then
          List.iter (fun v -> if refl.(v) then (refl.(v) <- false; changed := true)) members)
      g.RT.sccs
  done;
  Hashtbl.reset revealable;
  Array.iteri
    (fun i (u : RT.unit_) ->
      if List.mem "opaque" u.RT.u_attrs
         && List.for_all (fun e -> e.ev_rule = 9 && e.ev_text = "@[opaque]") local.(i)
         && local.(i) <> []
         && List.for_all dep_ok deps.(i)
         && g.RT.sccs.(g.RT.scc_of.(i)) = [ i ]
      then Hashtbl.replace revealable u.RT.u_span ())
    g.RT.units;
  (* ── Reasons ───────────────────────────────────────────────────────────── *)
  let memo = Hashtbl.create 64 in
  let rec reason (i : int) : blocker option =
    if refl.(i) then None
    else
      match Hashtbl.find_opt memo i with
      | Some r -> r
      | None ->
        Hashtbl.replace memo i None;
        let u = unit_ i in
        let dep_evs =
          List.filter_map
            (fun ((d, (s : RT.site)) as dd) ->
              if dep_ok dd then None
              else
                match d with
                | `Refl v ->
                  let callee = (unit_ v).RT.u_name in
                  Some { ev_rule = 6; ev_text = Printf.sprintf "calls %s, which is not reflected" callee;
                         ev_span = s.RT.s_span }
                | `Eq ids ->
                  let bad = List.find (fun x -> not eqok.(x)) ids in
                  let what =
                    match eq_reason bad with
                    | Some b when b.b_rule = 2 -> "has termination certificate " ^ b.b_text
                    | Some b -> b.b_text
                    | None -> "is not total and pure"
                  in
                  let at = match arg_ty s with Some t -> pp_ty t | None -> "?" in
                  Some
                    { ev_rule = 6;
                      ev_text = Printf.sprintf "%s at %s dispatches to %s, which %s" s.RT.s_name at
                          (impl_name (unit_ bad)) what;
                      ev_span = s.RT.s_span })
            deps.(i)
        in
        let scc_ev =
          let members = g.RT.sccs.(g.RT.scc_of.(i)) in
          match List.find_opt (fun v -> v <> i && local.(v) <> []) members with
          | Some v when local.(i) = [] && dep_evs = [] ->
            [ { ev_rule = 6;
                ev_text = Printf.sprintf "is recursive with %s, which is not reflected" (unit_ v).RT.u_name;
                ev_span = u.RT.u_span } ]
          | _ -> []
        in
        (* A call back into the unit's own SCC fails only as a consequence
           of the member that really blocks; name that one when there is one. *)
        let same_scc (d, _) = match d with `Refl v -> g.RT.scc_of.(v) = g.RT.scc_of.(i) | `Eq _ -> false in
        let outside = List.filter (fun dd -> not (dep_ok dd) && not (same_scc dd)) deps.(i) in
        let dep_evs =
          if local.(i) = [] && outside = [] then dep_evs
          else
            List.filteri
              (fun k _ ->
                let dd = List.nth (List.filter (fun dd -> not (dep_ok dd)) deps.(i)) k in
                not (same_scc dd))
              dep_evs
        in
        let r =
          match first (local.(i) @ dep_evs @ scc_ev) with
          | Some e -> Some { b_rule = e.ev_rule; b_text = e.ev_text; b_span = e.ev_span }
          | None ->
            Some { b_rule = 6; b_text = "is recursive with a function that is not reflected"; b_span = u.RT.u_span }
        in
        Hashtbl.replace memo i r;
        r
  (* Why an [eq] fails R2-R7: its first such local blocker, else a callee. *)
  and eq_reason (i : int) : blocker option =
    match first (List.filter (fun e -> e.ev_rule >= 2 && e.ev_rule <= 7) local.(i)) with
    | Some e -> Some { b_rule = e.ev_rule; b_text = e.ev_text; b_span = e.ev_span }
    | None -> (
      match List.find_opt (fun d -> not (dep_ok d)) deps.(i) with
      | Some (`Refl v, _) ->
        Some { b_rule = 6; b_text = Printf.sprintf "calls %s, which is not reflected" (unit_ v).RT.u_name;
               b_span = (unit_ i).RT.u_span }
      | Some (`Eq _, s) ->
        Some { b_rule = 6; b_text = Printf.sprintf "uses %s on a type whose `eq` is not total" s.RT.s_name;
               b_span = s.RT.s_span }
      | None -> None)
  in
  (* The unfolding guard: each parameter refinement, with its binder renamed
     to the parameter (§3.6). *)
  let guards (u : RT.unit_) =
    List.concat
      (List.mapi
         (fun i p ->
           match (p, List.nth_opt u.RT.u_param_tys i) with
           | Some pn, Some (Some ty) ->
             let rec refs (t : A.ty) =
               match t with
               | A.TyRefine (b, binder, pred) ->
                 let bn = match binder with Some b -> b.A.txt | None -> "_" in
                 let rec sub (e : A.expr) : A.expr =
                   match e with
                   | A.EVar v when v.A.txt = bn -> A.EVar { v with A.txt = pn }
                   | A.EApp (f, args, sp) -> A.EApp (sub f, List.map sub args, sp)
                   | A.ECon (c, args, sp) -> A.ECon (c, List.map sub args, sp)
                   | A.EField (r, f, sp) -> A.EField (sub r, f, sp)
                   | e -> e
                 in
                 Refine_scope.pred_str (sub pred) :: refs b
               | A.TyLinear (_, b) -> refs b
               | _ -> []
             in
             refs ty
           | _ -> [])
         u.RT.u_params)
  in
  (* ── Lemmas (§4.2): L2 and L3 over the same events ───────────────────────
     A lemma never runs, so the rules that keep a reflected body total and
     pure (R3, R4, R5, R7) apply to it, except that its `assert` is a static
     obligation (L2); its callees must be reflected functions, other lemmas,
     constructors or R6 builtins (L3).  R8's "returns Unit" is the point of a
     lemma and does not apply. *)
  Hashtbl.reset lemma_blocked;
  Hashtbl.reset proof_blocks;
  lemma_value_uses := [];
  let is_lemma v = List.mem "lemma" (unit_ v).RT.u_attrs in
  Array.iter
    (fun (u : RT.unit_) ->
      let i = u.RT.u_id in
      let scopes = ref [] in
      List.iter (fun (c : RT.owner) ->
        Refine_encode.iter_all (function A.EProof (A.PAssertBy _, sp) -> scopes := sp :: !scopes | _ -> ()) c.RT.o_body)
        u.RT.u_clauses;
      if is_lemma i || !scopes <> [] then begin
        (* `==` inside a lemma's `assert` is the predicate's logical
           equality (§3.5), never a call of `eq`. *)
        let asserts = ref [] in
        List.iter
          (fun (c : RT.owner) ->
            Refine_encode.iter_all (function
              | A.EAssert (_, sp) -> asserts := sp :: !asserts
              | A.EProof (A.PAssertBy (goal, _), _) -> asserts := T.span_of_expr goal :: !asserts
              | _ -> ()) c.RT.o_body)
          u.RT.u_clauses;
        let in_assert (sp : A.span) =
          List.exists
            (fun (a : A.span) ->
              sp.A.file = a.A.file
              && compare (sp.A.start_line, sp.A.start_col) (a.A.start_line, a.A.start_col) >= 0
              && compare (sp.A.end_line, sp.A.end_col) (a.A.end_line, a.A.end_col) <= 0)
            !asserts
        in
        let l2 =
          List.filter
            (fun e -> List.mem e.ev_rule [ 3; 4; 5; 7 ] && e.ev_text <> "has a runtime `assert`")
            local.(i)
        in
        let l3 =
          List.filter (fun e -> e.ev_rule = 6) local.(i)
          @ List.filter_map
              (fun ((d, (s : RT.site)) as dd) ->
                match d with
                | `Refl v when refl.(v) || is_lemma v -> None
                | `Refl v ->
                  Some { ev_rule = 6; ev_text = Printf.sprintf "calls %s, which is not reflected" (unit_ v).RT.u_name;
                         ev_span = s.RT.s_span }
                | `Eq _ when dep_ok dd || in_assert s.RT.s_span -> None
                | `Eq _ ->
                  Some { ev_rule = 6; ev_text = Printf.sprintf "uses %s on a type whose `eq` is not total" s.RT.s_name;
                         ev_span = s.RT.s_span })
              deps.(i)
        in
        (* Revealing a body does not relax totality: only units already in
           [revealable] qualify. Actual lexical visibility is still enforced
           by the proof walk's [Reflect_state.revealed] scope. *)
        let explicit_reveals = ref [] in
        List.iter (fun (c : RT.owner) ->
          Refine_encode.iter_all (function
            | A.EProof (A.PReveal (A.EVar f), _) -> explicit_reveals := f.A.txt :: !explicit_reveals
            | _ -> ()) c.RT.o_body) u.RT.u_clauses;
        let revealed_event e =
          List.exists (function
            | `Refl v, (s : RT.site) ->
              s.RT.s_span = e.ev_span
              && List.exists (Reflect_state.names_fn ~display:(unit_ v).RT.u_name) !explicit_reveals
              && Hashtbl.mem revealable (unit_ v).RT.u_span
            | _ -> false) deps.(i)
        in
        let proof_events = l2 @ List.filter (fun e -> not (revealed_event e)) l3 in
        List.iter (fun sp ->
          match first (List.filter (fun e -> span_within e.ev_span sp) proof_events) with
          | Some e -> Hashtbl.replace proof_blocks sp (Some e.ev_text)
          | None -> Hashtbl.replace proof_blocks sp None) !scopes;
        if is_lemma i then
          match (first l2, first l3) with
          | Some e, _ -> Hashtbl.replace lemma_blocked u.RT.u_span (2, e.ev_text)
          | None, Some e -> Hashtbl.replace lemma_blocked u.RT.u_span (3, e.ev_text)
          | None, None -> ()
      end)
    g.RT.units;
  (* L5: a lemma named as a value. *)
  List.iter
    (fun (s : RT.site) ->
      match s.RT.s_target with
      | RT.S_unit v when (not s.RT.s_call) && is_lemma v ->
        lemma_value_uses := (s.RT.s_span, (unit_ v).RT.u_name) :: !lemma_value_uses
      | _ -> ())
    g.RT.sites;
  (* Phase 5: the calls that are specialised.  The callee passed every rule
     but R7's, each named argument is reflected, and each lambda is total and
     pure on its own: its events and dependencies, which are its caller's,
     those inside its span (a reflected caller has none at all). *)
  let lam_ok owner (lsp : A.span) =
    refl.(owner)
    || spec_perturb "spec-skip-lambda-check"
    || List.for_all (fun e -> not (span_within e.ev_span lsp)) local.(owner)
       && List.for_all (fun ((_, (s : RT.site)) as d) -> (not (span_within s.RT.s_span lsp)) || dep_ok d) deps.(owner)
  in
  let counts = Hashtbl.create 16 in
  Hashtbl.iter
    (fun sp fa ->
      let s = Hashtbl.find call_at sp in
      match s.RT.s_target with
      | RT.S_unit v
        when refl.(v)
             && List.for_all
                  (function
                    | _, F_named (f, _) -> refl.(f) && not (List.mem "lemma" (unit_ f).RT.u_attrs)
                    | _, F_lambda (_, _, lsp) -> lam_ok s.RT.s_src lsp)
                  fa ->
        Hashtbl.replace spec_sites sp
          { ss_callee = v; ss_caller = s.RT.s_src; ss_span = sp; ss_args = s.RT.s_args; ss_fn = fa };
        Hashtbl.replace counts v (1 + Option.value ~default:0 (Hashtbl.find_opt counts v))
      | _ -> ())
    site_spec;
  Array.to_list g.RT.units
  |> List.filter_map (fun (u : RT.unit_) ->
         match (u.RT.u_kind, origin_of u) with
         | RT.Handler, _ | _, O_let | _, O_default -> None
         | _ ->
           let v =
             match reason u.RT.u_id with
             | None when Hashtbl.mem spec_params u.RT.u_id ->
               Hashtbl.replace specialised u.RT.u_span ();
               Specialised (Option.value ~default:0 (Hashtbl.find_opt counts u.RT.u_id))
             | None -> Reflected (guards u)
             | Some b -> Blocked b
           in
           Some
             { r_name = u.RT.u_name; r_span = u.RT.u_span; r_verdict = v;
               r_top = u.RT.u_kind = RT.Top && origin_of u = O_fn })

(** The [--reflect-report] block (§2.4): one row per function whose span
    [is_user] accepts, deduplicated by declaration site and in source order,
    then a summary. *)
let report_lines ?(is_user : A.span -> bool = fun _ -> true) (rows : row list) : string list =
  let seen = Hashtbl.create 64 in
  let rows =
    List.filter
      (fun r ->
        is_user r.r_span
        &&
        let k = span_str r.r_span in
        if Hashtbl.mem seen k then false else (Hashtbl.replace seen k (); true))
      rows
    |> List.stable_sort (fun a b ->
           compare (a.r_span.A.file, a.r_span.A.start_line, a.r_span.A.start_col)
             (b.r_span.A.file, b.r_span.A.start_line, b.r_span.A.start_col))
  in
  let line r =
    match r.r_verdict with
    | Reflected [] -> Printf.sprintf "reflect\t%s\t%s\treflected\tunfold" (span_str r.r_span) r.r_name
    | Reflected gs ->
      Printf.sprintf "reflect\t%s\t%s\treflected\tunfold (guard: %s)" (span_str r.r_span) r.r_name
        (String.concat " && " gs)
    | Blocked b ->
      Printf.sprintf "reflect\t%s\t%s\tno\tR%d:%s (%s)" (span_str r.r_span) r.r_name b.b_rule b.b_text
        (span_str b.b_span)
    | Specialised k ->
      Printf.sprintf "reflect\t%s\t%s\tspecialised\t%d call site%s" (span_str r.r_span) r.r_name k
        (if k = 1 then "" else "s")
  in
  let refl = List.filter (fun r -> match r.r_verdict with Reflected _ -> true | _ -> false) rows in
  let count p = List.length (List.filter p rows) in
  let by_rule =
    List.filter_map
      (fun k ->
        match count (fun r -> match r.r_verdict with Blocked b -> b.b_rule = k | _ -> false) with
        | 0 -> None
        | c -> Some (Printf.sprintf "R%d=%d" k c))
      [ 1; 2; 3; 4; 5; 6; 7; 8; 9; 11 ]
  in
  let tops = List.filter (fun r -> r.r_top) rows in
  (Printf.sprintf "reflect report: %d functions, %d reflected" (List.length rows) (List.length refl)
  :: List.map line rows)
  @ [ Printf.sprintf "  top-level: %d of %d reflected" (List.length (List.filter (fun r -> List.memq r refl) tops))
        (List.length tops);
      "  first blocker: " ^ (if by_rule = [] then "none" else String.concat " " by_rule) ]

(* ══ Phase 1a: the encoding (§3) ════════════════════════════════════════════

   [install] runs at the top of every [Refine_check.check_module]: it computes
   the §2.1 verdicts with the inputs available BEFORE the refinement walk,
   gives each reflected function its logic symbol (§3.1) and signature (§3.2,
   §3.3), translates its body into guarded cases ([term_of_body], §3.4), and
   points [Reflect_state.unfold_hook] at [unfold] (§3.6, §3.7).

   What the walk decides later is not available here, so the encoder's R2
   and R4 are the conservative halves of the report's:
   - R2: the certificate of the termination graph itself (structural, or a
     non-recursive unit).  A [metric] certificate is decided by the walk's
     termination obligations, after this point; such a function is not
     unfolded in phase 1a.
   - R4: a division by a non-zero literal passes; every other division
     blocks (its [Division] obligation is filed after the check).
   Both can only leave a function out of the logic, never put one in. *)

module Smt = March_refine.Smt
module RS = Reflect_state
module RE = Refine_encode

exception Decline

(* The template of one reflected function: guarded cases over the parameter
   placeholders [$rp<i>] (§3.4: one implication per arm, no default arm), and
   the conjunction of its parameter refinements over the same placeholders
   (§3.6, C1). *)
type template = {
  t_cases : (Smt.term list * Smt.term) list;
  t_pre : Smt.term list;
  t_name : string;
  t_eqs : (string * string) list;
      (** each type the body uses program [==] at, with its §3.5 reading
          ([structural] or [opaque]): part of the D17 hash (I8) *)
  t_fuel : int;
      (** how deep a chain through this function's calls is unfolded (§3.8):
          [@[reflect(fuel: N)]], else [default_fuel] *)
}

(* §3.8, D14. *)
let default_fuel = 2

(* The fuel an attribute list sets, [@[reflect(fuel: N)]] as
   ["reflect:fuel:N"]. *)
let fuel_of_attrs (attrs : string list) : int option =
  List.find_map
    (fun a ->
      match String.split_on_char ':' a with
      | [ "reflect"; "fuel"; n ] -> int_of_string_opt n
      | _ -> None)
    attrs

(* The types a body's [==] was read at while its template is built. *)
let eq_seen : (string * string) list ref = ref []

(* Test-only perturbation [swap-arms] (the parity net's RED control, §9.2):
   the first two cases exchange their results, a wrong arm order the net
   must catch. *)
let swap_arms = function
  | (g1, r1) :: (g2, r2) :: rest -> (g1, r2) :: (g2, r1) :: rest
  | cs -> cs

let templates : (string, template) Hashtbl.t = Hashtbl.create 64

let param_const i = Printf.sprintf "$rp%d" i

(* Every immediate subterm rebuilt through [f]. *)
let map_term (f : Smt.term -> Smt.term) (t : Smt.term) : Smt.term =
  let open Smt in
  match t with
  | Quant (q, n, sort, g, b) -> Quant (q, n, sort, f g, f b)
  | Const _ | IntLit _ | BoolLit _ | FloatLit _ | SetEmpty _ -> t
  | App (g, xs) -> App (g, List.map f xs)
  | Ctor (c, s, xs) -> Ctor (c, s, List.map f xs)
  | IsCtor (c, a) -> IsCtor (c, f a)
  | IsCtorAt (c, s, n, a) -> IsCtorAt (c, s, n, f a)
  | MulLit (k, a) -> MulLit (k, f a)
  | DivLit (a, k) -> DivLit (f a, k)
  | ModLit (a, k) -> ModLit (f a, k)
  | Neg a -> Neg (f a)
  | Not a -> Not (f a)
  | SetSng (e, a) -> SetSng (e, f a)
  | SetCard (e, a) -> SetCard (e, f a)
  | Ite (c, a, b) -> Ite (f c, f a, f b)
  | Add (a, b) -> Add (f a, f b)
  | Sub (a, b) -> Sub (f a, f b)
  | Mul (a, b) -> Mul (f a, f b)
  | Div (a, b) -> Div (f a, f b)
  | Mod (a, b) -> Mod (f a, f b)
  | And (a, b) -> And (f a, f b)
  | Or (a, b) -> Or (f a, f b)
  | Implies (a, b) -> Implies (f a, f b)
  | Eq (a, b) -> Eq (f a, f b)
  | Ne (a, b) -> Ne (f a, f b)
  | Lt (a, b) -> Lt (f a, f b)
  | Le (a, b) -> Le (f a, f b)
  | Gt (a, b) -> Gt (f a, f b)
  | Ge (a, b) -> Ge (f a, f b)
  | FpEq (a, b) -> FpEq (f a, f b)
  | FpLt (a, b) -> FpLt (f a, f b)
  | FpLe (a, b) -> FpLe (f a, f b)
  | FpGt (a, b) -> FpGt (f a, f b)
  | FpGe (a, b) -> FpGe (f a, f b)
  | SetMem (a, b) -> SetMem (f a, f b)
  | SetUnion (a, b) -> SetUnion (f a, f b)
  | SetInter (a, b) -> SetInter (f a, f b)
  | SetDiff (a, b) -> SetDiff (f a, f b)
  | SetSub (a, b) -> SetSub (f a, f b)

let rec subst (env : (string * Smt.term) list) (t : Smt.term) : Smt.term =
  match t with
  | Smt.Const c -> ( match List.assoc_opt c env with Some u -> u | None -> t)
  | t -> map_term (subst env) t

let rec reflected_apps (acc : (string * Smt.term list) list) (t : Smt.term) =
  let acc =
    match t with
    | Smt.App (f, args) when Hashtbl.mem templates f -> (f, args) :: acc
    | _ -> acc
  in
  List.fold_left reflected_apps acc (Smt.children t)

let conj = function [] -> Smt.BoolLit true | t :: ts -> List.fold_left (fun a b -> Smt.And (a, b)) t ts

(* Test-only perturbations, each the RED control of one rule (progress note):
   [false-unfold] every unfolding asserts false (I7); [no-guard] drops the
   domain guard (C1); [eq-structural] makes a body's [==] SMT equality at
   every type (D7, C3); [budget-64] raises the cap (§3.9). *)
let perturb = Sys.getenv_opt "MARCH_REFLECT_PERTURB"

let perturb_false = ref (perturb = Some "false-unfold")

(* The per-query cap on unfoldings (§3.9). *)
let budget = if perturb = Some "budget-64" then 64 else 32

(* ── Decided guards (§3.8, D13) ──────────────────────────────────────────
   Which arm of a produced call holds, read syntactically from the query's
   facts, never with a solver query.  The answer only chooses which arm's
   equation to add and when to stop: every equation added is still guarded
   by its own arm conditions and the domain guard, exactly as a depth-0 one,
   so a wrong answer costs a proof, never makes one. *)

(* `<ctor>_<i>`: a selector's constructor and field index. *)
let selector_of (f : string) : (string * int) option =
  match String.rindex_opt f '_' with
  | None -> None
  | Some i -> (
    let c = String.sub f 0 i and idx = String.sub f (i + 1) (String.length f - i - 1) in
    match int_of_string_opt idx with
    | Some k when Hashtbl.mem RE.ctor_field_sorts c -> Some (c, k)
    | _ -> None)

type facts = {
  vals : (Smt.term, Smt.term) Hashtbl.t;  (** a term's known value: a constructor term, a literal, or an earlier unfolding's result *)
  tags : (Smt.term, string) Hashtbl.t;  (** a term's known constructor, from a tester fact *)
  holds : (Smt.term, bool) Hashtbl.t;  (** a top-level assumption, or its negation *)
}

let rec ground_int (t : Smt.term) : int option =
  match t with
  | Smt.IntLit n -> Some n
  | Smt.Add (a, b) -> Option.bind (ground_int a) (fun x -> Option.map (( + ) x) (ground_int b))
  | Smt.Sub (a, b) -> Option.bind (ground_int a) (fun x -> Option.map (fun y -> x - y) (ground_int b))
  | Smt.MulLit (k, a) -> Option.map (( * ) k) (ground_int a)
  | Smt.Neg a -> Option.map (fun x -> -x) (ground_int a)
  | _ -> None

(* [t] rewritten by what is known, at most [n] steps deep. *)
let rec norm (st : facts) (n : int) (t : Smt.term) : Smt.term =
  if n <= 0 then t
  else
    let known () = match Hashtbl.find_opt st.vals t with Some v when v <> t -> norm st (n - 1) v | _ -> t in
    match t with
    | Smt.App (f, [ u ]) -> (
      match selector_of f with
      | Some (k, i) -> (
        match norm st (n - 1) u with
        | Smt.Ctor (k', _, args) when k' = k -> (
          match List.nth_opt args i with Some a -> norm st (n - 1) a | None -> t)
        | _ -> known ())
      | None -> known ())
    | _ -> (
      match ground_int t with Some k -> Smt.IntLit k | None -> known ())

let rec decide (st : facts) (c : Smt.term) : bool option =
  let n = 12 in
  match Hashtbl.find_opt st.holds c with
  | Some b -> Some b
  | None -> (
    match c with
    | Smt.BoolLit b -> Some b
    | Smt.Not a -> Option.map not (decide st a)
    | Smt.And (a, b) -> (
      match decide st a, decide st b with
      | Some false, _ | _, Some false -> Some false
      | Some true, Some true -> Some true
      | _ -> None)
    | Smt.Or (a, b) -> (
      match decide st a, decide st b with
      | Some true, _ | _, Some true -> Some true
      | Some false, Some false -> Some false
      | _ -> None)
    | Smt.IsCtor (k, s) -> (
      match norm st n s with
      | Smt.Ctor (k', _, _) -> Some (k = k')
      | s' -> (
        match Hashtbl.find_opt st.tags s', Hashtbl.find_opt st.tags s with
        | Some k', _ | None, Some k' -> Some (k = k')
        | None, None -> None))
    | Smt.Eq (a, b) -> (
      match norm st n a, norm st n b with
      | Smt.Ctor (k, _, _), Smt.Ctor (k', _, _) when k <> k' -> Some false
      | Smt.IntLit x, Smt.IntLit y -> Some (x = y)
      | Smt.BoolLit x, Smt.BoolLit y -> Some (x = y)
      | a', b' when a' = b' -> Some true
      | _ -> None)
    | Smt.Lt (a, b) | Smt.Le (a, b) | Smt.Gt (a, b) | Smt.Ge (a, b) -> (
      match norm st n a, norm st n b with
      | Smt.IntLit x, Smt.IntLit y ->
        Some
          (match c with
           | Smt.Lt _ -> x < y
           | Smt.Le _ -> x <= y
           | Smt.Gt _ -> x > y
           | _ -> x >= y)
      | _ -> None)
    | t -> (
      match norm st n t with
      | Smt.BoolLit b -> Some b
      | t' when t' <> t -> decide st t'
      | _ -> None))

let rec conjuncts (t : Smt.term) = match t with Smt.And (a, b) -> conjuncts a @ conjuncts b | t -> [ t ]

let facts_of (assumptions : Smt.term list) : facts =
  let st = { vals = Hashtbl.create 32; tags = Hashtbl.create 16; holds = Hashtbl.create 32 } in
  let is_value = function Smt.Ctor _ | Smt.IntLit _ | Smt.BoolLit _ -> true | _ -> false in
  List.iter
    (fun c ->
      Hashtbl.replace st.holds c true;
      match c with
      | Smt.Not a -> Hashtbl.replace st.holds a false
      | Smt.IsCtor (k, s) -> Hashtbl.replace st.tags s k
      | Smt.Eq (a, b) when is_value b && not (is_value a) -> Hashtbl.replace st.vals a b
      | Smt.Eq (a, b) when is_value a && not (is_value b) -> Hashtbl.replace st.vals b a
      | _ -> ())
    (List.concat_map conjuncts assumptions);
  st

(* The one arm whose conditions hold, every earlier arm's failing ([None]:
   not decided). *)
let decided_arm (st : facts) (cases : (Smt.term list * Smt.term) list) : (Smt.term list * Smt.term) option =
  let rec go = function
    | [] -> None
    | ((conds, _) as arm) :: rest -> (
      match List.map (decide st) conds with
      | ds when List.for_all (( = ) (Some true)) ds -> Some arm
      | ds when List.exists (( = ) (Some false)) ds -> go rest
      | _ -> None)
  in
  go cases

(* §3.6-§3.8: unfold the query's reflected calls.  Depth 0 is every call of
   the query (the goal, then the assumptions in order), each with all its
   guarded equations, as phase 1 has it (D12).  A call an unfolding produces
   is at the next depth; it is unfolded, breadth first, only while its depth
   is below its function's fuel and its guard is decided (D13, D14), and then
   with the decided arm's equation only.  Every unfolding's equations are
   asserted behind one assumption literal, which names the function in the
   unsat core (the [uses:] note).  At most [budget] unfoldings per query
   (§3.9). *)
let unfold (decls : (string * Smt.sort) list) (goal : Smt.term) (assumptions : Smt.term list) =
  let seen = ref [] in
  let frontier =
    List.fold_left
      (fun acc t ->
        List.fold_left
          (fun acc (f, args) ->
            let k = (f, args) in
            if List.mem k !seen then acc else (seen := k :: !seen; k :: acc))
          acc
          (List.rev (reflected_apps [] t)))
      [] (goal :: assumptions)
    |> List.rev
  in
  let frontier =
    if List.length frontier > budget then begin
      RS.budget_hit := true;
      List.filteri (fun i _ -> i < budget) frontier
    end
    else frontier
  in
  let st = facts_of assumptions in
  let count = ref 0 in
  (* Guard calls queued so far ([rounds]): bounded by [budget] as unfoldings
     are, since a chain of guards need never unfold anything. *)
  let asked = ref 0 in
  let lits = ref [] and facts = ref [] in
  (* Unfold [f(args)] with [cases] (all of them at depth 0, the decided arm
     deeper); returns the reflected calls its equations mention. *)
  let emit (f, args) cases =
    Hashtbl.replace RS.check_frontier f ();
    let tp = Hashtbl.find templates f in
    let env = List.mapi (fun i a -> (param_const i, a)) args in
    let pre = if perturb = Some "no-guard" then [] else List.map (subst env) tp.t_pre in
    let lhs = Smt.App (f, args) in
    let produced = ref [] in
    let eqs =
      List.map
        (fun (conds, res) ->
          let res = subst env res and conds = List.map (subst env) conds in
          produced := List.fold_left reflected_apps !produced (res :: conds);
          let g = pre @ conds in
          let eq = Smt.Eq (lhs, res) in
          if g = [] then eq else Smt.Implies (conj g, eq))
        cases
    in
    let lit = Printf.sprintf "|%s%d:%s|" RS.literal_prefix !count tp.t_name in
    incr count;
    Hashtbl.replace RS.literal_owner lit tp.t_name;
    lits := (lit, Smt.SBool) :: !lits;
    (* Test-only perturbation (the I7 control): every unfolding asserts
       [false], so stage 2 proves anything it is asked. *)
    let body = if !perturb_false then Smt.BoolLit false else conj eqs in
    facts := Smt.Implies (Smt.Const lit, body) :: !facts;
    List.rev !produced
  in
  (* A decided call's value, for the guards of the calls after it. *)
  let learn (f, args) =
    let tp = Hashtbl.find templates f in
    let env = List.mapi (fun i a -> (param_const i, a)) args in
    let inst = List.map (fun (conds, res) -> (List.map (subst env) conds, subst env res)) tp.t_cases in
    match decided_arm st inst with
    | Some (_, res) -> Hashtbl.replace st.vals (Smt.App (f, args)) res
    | None -> ()
  in
  let next =
    List.concat_map
      (fun (f, args) ->
        let tp = Hashtbl.find templates f in
        learn (f, args);
        emit (f, args) tp.t_cases)
      frontier
  in
  (* Deeper levels: each round unfolds every pending call it can decide;
     what an unfolding learns may decide another, so a level is retried until
     a round makes no progress. *)
  let rec level depth (pending : (string * Smt.term list) list) =
    let pending =
      List.sort_uniq compare (List.filter (fun k -> not (List.mem k !seen)) pending)
    in
    if pending <> [] then begin
      let out_next = ref [] in
      let rec rounds (todo : (string * Smt.term list) list) =
        let progressed = ref false in
        (* The reflected calls inside an undecided call's guards: unfolded at
           this level too, since what they learn may decide it. *)
        let guard_calls = ref [] in
        let left =
          List.filter
            (fun ((f, args) as k) ->
              let tp = Hashtbl.find templates f in
              if List.mem k !seen then false
              else if depth >= RS.fuel_for ~display:tp.t_name tp.t_fuel || !count >= budget then true
              else
                let env = List.mapi (fun i a -> (param_const i, a)) args in
                let inst = List.map (fun (conds, res) -> (List.map (subst env) conds, subst env res)) tp.t_cases in
                match decided_arm st inst with
                | None ->
                  List.iter
                    (fun (conds, _) ->
                      List.iter
                        (fun g ->
                          if !asked < budget && not (List.mem g !seen || List.mem g todo || List.mem g !guard_calls)
                          then begin
                            incr asked;
                            guard_calls := g :: !guard_calls
                          end)
                        (List.rev (List.fold_left reflected_apps [] conds)))
                    inst;
                  true
                | Some (conds, res) ->
                  progressed := true;
                  seen := k :: !seen;
                  Hashtbl.replace st.vals (Smt.App (f, args)) res;
                  (* The arm's conditions stay in its implication, over the
                     template's own (unsubstituted) case. *)
                  let arm =
                    List.find (fun (c, r) -> List.map (subst env) c = conds && subst env r = res) tp.t_cases
                  in
                  out_next := emit k [ arm ] @ !out_next;
                  false)
            todo
        in
        if !guard_calls <> [] then rounds (left @ List.rev !guard_calls)
        else if !progressed && left <> [] then rounds left
        else left
      in
      let left = rounds pending in
      (* What stays is over fuel, over budget, or undecided (§3.9). *)
      List.iter
        (fun (f, args) ->
          let tp = Hashtbl.find templates f in
          if !count >= budget && depth < RS.fuel_for ~display:tp.t_name tp.t_fuel then RS.budget_hit := true;
          RS.fuel_pending := true;
          if !RS.fuel_fn = "" then RS.fuel_fn := tp.t_name;
          ignore args)
        left;
      level (depth + 1) !out_next
    end
  in
  level 1 next;
  (* D9: each string literal the query mentions has its byte length, and
     two literals of different content are different strings. *)
  let strs =
    let acc = ref [] in
    let rec walk (t : Smt.term) =
      (match t with
       | Smt.App (f, []) when Hashtbl.mem RS.str_lits f && not (List.mem f !acc) -> acc := f :: !acc
       | _ -> ());
      List.iter walk (Smt.children t)
    in
    List.iter walk ((goal :: assumptions) @ !facts);
    List.sort compare !acc
  in
  let str_facts =
    List.concat_map
      (fun f ->
        Smt.Eq (Smt.App (RE.strlen_fn, [ Smt.App (f, []) ]), Smt.IntLit (String.length (Hashtbl.find RS.str_lits f)))
        :: List.filter_map (fun g -> if f < g then Some (Smt.Ne (Smt.App (f, []), Smt.App (g, []))) else None) strs)
      strs
  in
  (decls @ List.rev !lits, assumptions @ List.rev !facts @ str_facts)

(* ── Sorts of a signature (§3.2, §3.3) ──────────────────────────────────── *)

(* The datatype a typechecker type names, when it pins exactly ONE: a short
   type name two modules declare (`A.T`, `B.T`) is not decided here, and a
   record is not a variant.  [None] = not known. *)
let adt_of_ty (t : T.ty) : string option = RE.adt_of_tc_ty t

(* A SOURCE constructor name as (datatype, SMT constructor) (2026-11-02,
   specs/progress/2026-11-02-reflection-ctor-registry-by-datatype.md):
   by [adt], the type the checker knows the value has, when it knows one
   (and then the constructor must be one of that datatype's); else by the
   name alone when exactly one datatype declares it, and then only in a
   CONSTRUCTION ([~construct]): a pattern or tester on a value of unknown
   type declines (review round 4).  Anything else — an ambiguous name with
   no type, a type that does not declare it — raises [Decline].  Never
   guess. *)
let resolve_ctor ?(construct = false) ?(adt : string option) (c : string) : string * string =
  match adt with
  | Some a -> (match RE.ctor_of_adt a c with Some s -> (a, s) | None -> raise Decline)
  | None when not construct && not (RE.untyped_harness ()) -> raise Decline
  | None -> (
    match RE.unique_ctor c with
    | Some p -> p
    | None -> (
      match Hashtbl.find_opt RE.ctor_decls c with
      (* Test-only: the RED control of the ambiguity rule (pick one). *)
      | Some (a :: _) when Sys.getenv_opt "MARCH_REFLECT_PERTURB" = Some "ctor-guess" ->
        (a, RE.ctor_smt_name a c)
      | _ -> raise Decline))

(* The datatype a field of SMT constructor [smt] holds at index [i], when it
   is one: the sub-subject's type for a nested constructor pattern. *)
let field_adt (smt : string) (i : int) : string option =
  match List.nth_opt (try Hashtbl.find RE.ctor_field_sorts_poly smt with Not_found -> []) i with
  (* A field type whose short name two declarants share is KNOWN but
     conflated: never a key a constructor resolves through (review round 2). *)
  | Some (Smt.SData (a, _)) when Hashtbl.mem RE.ambiguous_adts a -> Some RE.ambiguous_adt_sentinel
  | Some (Smt.SData (a, _)) when Hashtbl.mem RE.adt_ctors a -> Some a
  | _ -> None

(* The declared record a structural record type is (records unify by their
   fields, so the typechecker keeps no name): the ONE registered,
   monomorphic, unconflated record whose field names are exactly [fs]'s and
   whose declared field sorts are [fs]'s sorts ([sort]).  Anything else —
   two declared records with one field set, a parametric record, a field of
   another sort (an anonymous record) — is not decided here. *)
let record_of_fields (sort : T.ty -> Smt.sort) (fs : (string * T.ty) list) : (string * string * string list) option =
  let names = List.sort compare (List.map fst fs) in
  let cands =
    Hashtbl.fold
      (fun adt cs acc ->
        match cs with
        | [ ctor ] -> (
          match Hashtbl.find_opt RE.ctor_field_names ctor with
          | Some ns when List.sort compare ns = names -> (adt, ctor, ns) :: acc
          | _ -> acc)
        | _ -> acc)
      RE.adt_ctors []
  in
  match cands with
  | [ (adt, ctor, ns) ]
    when (not (Hashtbl.mem RE.ambiguous_adts adt))
         && Option.value ~default:0 (Hashtbl.find_opt RE.adt_arity adt) = 0 -> (
    let declared = try Hashtbl.find RE.ctor_field_sorts_poly ctor with Not_found -> [] in
    try
      if List.length declared <> List.length ns then None
      else if List.for_all2 (fun n d -> sort (List.assoc n fs) = d) ns declared then Some (adt, ctor, ns)
      else None
    with Decline | Not_found | Invalid_argument _ -> None)
  | _ -> None

let poly_sort (vars : (int * int) list ref) (t : T.ty) : Smt.sort =
  let rec go (t : T.ty) =
    match T.repr t with
    (* A tuple (§3.2): the tuple datatype of its arity, at its instance. *)
    | T.TTuple (_ :: _ :: _ as ts) -> Smt.SData (RE.tuple_adt (List.length ts), List.map go ts)
    (* A record (§3.2): its declared record sort. *)
    | T.TRecord fs -> (
      match record_of_fields go fs with Some (adt, _, _) -> Smt.sdata adt | None -> raise Decline)
    | T.TCon ("Int", []) -> Smt.SInt
    | T.TCon ("Bool", []) -> Smt.SBool
    (* D9: the checker's Float sort, every operation on it opaque. *)
    | T.TCon ("Float", []) -> Smt.SFloat
    (* D9: the opaque `$Str`, with only `$strlen`. *)
    | T.TCon ("String", []) -> RS.str_sort
    | T.TLin (_, b) -> go b
    | T.TVar r -> (
      match !r with
      | T.Unbound (id, _) -> (
        match List.assoc_opt id !vars with
        | Some i -> Smt.SParam i
        | None ->
          let i = List.length !vars in
          vars := (id, i) :: !vars;
          Smt.SParam i)
      | T.Link _ -> raise Decline)
    | T.TCon (n, args) ->
      (* Two declared types of one short name (`A.T`, `B.T`): which one the
         short name denotes is not decided here.  Decline. *)
      (* The same resolution as a constructor's ([RE.adt_of_type_name],
         review round 4): a conflated short name, an inexact qualified one,
         or a type that is no registered variant declines. *)
      let adt =
        match RE.adt_of_type_name ~arity:(List.length args) n with
        | Some a when a <> RE.ambiguous_adt_sentinel -> a
        | _ -> raise Decline
      in
      (match Hashtbl.find_opt RE.adt_ctors adt with
       | Some _ ->
         let k = try Hashtbl.find RE.adt_arity adt with Not_found -> 0 in
         if k = 0 then Smt.sdata adt
         else if List.length args <> k then raise Decline
         else Smt.SData (adt, List.map go args)
       | None -> raise Decline)
    | _ -> raise Decline
  in
  go t

(* A record datatype (§3.2: the sort the checker already declares, one
   constructor with named fields): (datatype, constructor, field names). *)
let record_of_adt (adt : string) : (string * string * string list) option =
  match Hashtbl.find_opt RE.adt_ctors adt with
  | Some [ ctor ] when Hashtbl.mem RE.ctor_field_names ctor -> Some (adt, ctor, Hashtbl.find RE.ctor_field_names ctor)
  | _ -> None

let record_of_ty (t : T.ty option) : string * string * string list =
  let rec strip t = match T.repr t with T.TLin (_, b) -> strip b | t -> t in
  match Option.map strip t with
  | Some (T.TRecord fs) -> (
    match record_of_fields (poly_sort (ref [])) fs with Some r -> r | None -> raise Decline)
  | _ -> (
    match Option.bind t RE.adt_of_tc_ty with
    | Some a when a <> RE.ambiguous_adt_sentinel -> (
      match record_of_adt a with Some r -> r | None -> raise Decline)
    | _ -> raise Decline)

(* A subject's datatype for its patterns: a record's declared sort, else
   [adt_of_ty]'s. *)
let pat_adt (t : T.ty option) : string option =
  match t with
  | None -> None
  | Some t -> (
    let rec strip t = match T.repr t with T.TLin (_, b) -> strip b | t -> t in
    match strip t with
    | T.TRecord _ -> (try let a, _, _ = record_of_ty (Some t) in Some a with Decline -> None)
    | _ -> adt_of_ty t)

(* The selector of field [i] of SMT constructor [ctor]. *)
let field_sel (ctor : string) (i : int) (x : Smt.term) : Smt.term = Smt.App (Printf.sprintf "%s_%d" ctor i, [ x ])

let index_of (n : string) (names : string list) : int =
  match List.find_index (( = ) n) names with Some i -> i | None -> raise Decline

(* ── The body translator (§3.4) ─────────────────────────────────────────── *)

type tctx = {
  c_sites : (A.span, RT.site) Hashtbl.t;
  c_sym_of_unit : int -> string option;
  c_ty : A.span -> T.ty option;
  c_len_unit : int -> bool;
  c_eq_structural : T.ty -> bool;  (** program [==] at this type is SMT [=] (§3.5) *)
  c_unit : RT.unit_ array;
  c_ambiguous : A.span -> bool;  (** [Refine_term.graph.ambiguous] *)
  c_spec : spec_ctx option;  (** translating a specialisation's body (phase 5) *)
}

(* A specialisation's body (phase 5): [g]'s function parameters stand for the
   call's arguments.  Each is bound in the environment to a SENTINEL constant
   ([$fn:<name>]) that only a call of it, or the same position of [g]'s own
   recursive call, may meet; anything else that reaches one declines. *)
and spec_ctx = {
  sc_self : int;  (** [g]'s unit *)
  sc_sym : string;  (** this specialisation's symbol *)
  sc_fn : (string * fn_arg) list;  (** function parameter -> the call's argument *)
  sc_fnpos : (int * string) list;  (** its position *)
  sc_caps : (string * Smt.term) list;  (** each capture of the lambdas -> its parameter *)
}

let sentinel p = Smt.Const ("$fn:" ^ p)

let is_sentinel = function Smt.Const k -> String.starts_with ~prefix:"$fn:" k | _ -> false

let is_int_ty = function Some t -> (match T.repr t with T.TCon ("Int", []) -> true | _ -> false) | None -> false

let is_float_ty = function Some t -> (match T.repr t with T.TCon ("Float", []) -> true | _ -> false) | None -> false

(* The most cases a `let`'s right-hand side may split a body into ([tr_case]):
   past it the body is declined, so one function's equations stay few. *)
let max_let_cases = 16

(* The solver's half of R4: [d] is non-zero under [facts], asked of z3 over
   the integer parameters alone.  A fact over anything else (a datatype, a
   call's symbol, a non-literal division) is dropped, which only weakens the
   assumptions; a divisor over anything else is not asked. *)
let solver_nonzero ~(int_consts : string list) (facts : Smt.term list) (d : Smt.term) : bool =
  let open Smt in
  let rec arith t =
    match t with
    | Const k -> List.mem k int_consts
    | IntLit _ | BoolLit _ -> true
    | Add _ | Sub _ | Mul _ | MulLit _ | DivLit _ | ModLit _ | Neg _ | Not _ | And _ | Or _ | Implies _ | Ite _
    | Eq _ | Ne _ | Lt _ | Le _ | Gt _ | Ge _ ->
      List.for_all arith (children t)
    | _ -> false
  in
  arith d
  && (let vc =
        { decls = List.map (fun k -> (k, SInt)) int_consts;
          assumptions = List.filter arith facts;
          goal = Ne (d, IntLit 0) }
      in
      match March_refine.Refine.discharge ~root:(Sys.getcwd ()) vc with
      | March_refine.Refine.Verified -> true
      | _ -> false)

(* R4 for a non-literal divisor, decided on the translated template: every
   [Div]/[Mod] in a case must have a divisor its facts show non-zero.  The
   facts are the parameter refinements ([pre]), the case's earlier guards,
   and on the way down the conditions short-circuiting and [Ite] put in
   force (`b == 0 || a / b > 0`, `if b == 0 do 0 else a / b end`).  Purely
   structural, so it needs no solver and gives the same answer every run; a
   divisor it cannot see is non-zero declines the template (sound: the
   symbol stays uninterpreted). *)
let divisions_defined ?(solver = fun (_ : Smt.term list) (_ : Smt.term) -> false) (pre : Smt.term list)
    (cases : (Smt.term list * Smt.term) list) : bool =
  let open Smt in
  let rec conj = function And (a, b) -> conj a @ conj b | t -> [ t ] in
  let nonzero_fact d f =
    match f with
    | Ne (x, IntLit 0) | Ne (IntLit 0, x) | Not (Eq (x, IntLit 0)) | Not (Eq (IntLit 0, x)) -> x = d
    | Eq (x, IntLit k) | Eq (IntLit k, x) -> x = d && k <> 0
    | Gt (x, IntLit k) | Lt (IntLit k, x) | Not (Le (x, IntLit k)) | Not (Ge (IntLit k, x)) -> x = d && k >= 0
    | Ge (x, IntLit k) | Le (IntLit k, x) | Not (Lt (x, IntLit k)) | Not (Gt (IntLit k, x)) -> x = d && k >= 1
    | Lt (x, IntLit k) | Gt (IntLit k, x) | Not (Ge (x, IntLit k)) | Not (Le (IntLit k, x)) -> x = d && k <= 0
    | Le (x, IntLit k) | Ge (IntLit k, x) | Not (Gt (x, IntLit k)) | Not (Lt (IntLit k, x)) -> x = d && k <= -1
    | _ -> false
  in
  let nonzero facts d =
    match d with IntLit k -> k <> 0 | _ -> List.exists (nonzero_fact d) facts || solver facts d
  in
  let rec ok facts t =
    let with_ f = conj f @ facts in
    match t with
    | Div (x, d) | Mod (x, d) -> nonzero facts d && ok facts x && ok facts d
    | And (a, b) -> ok facts a && ok (with_ a) b
    | Or (a, b) -> ok facts a && ok (with_ (Not a)) b
    | Implies (a, b) -> ok facts a && ok (with_ a) b
    | Ite (c, a, b) -> ok facts c && ok (with_ c) a && ok (with_ (Not c)) b
    | _ -> List.for_all (ok facts) (children t)
  in
  (* Each guard is evaluated under the ones before it, the result under all. *)
  let rec case facts = function
    | [], r -> ok facts r
    | g :: gs, r -> ok facts g && case (conj g @ facts) (gs, r)
  in
  List.for_all (ok []) pre && List.for_all (case (List.concat_map conj pre)) cases

let rec tr_val (c : tctx) (env : (string * Smt.term) list) (e : A.expr) : Smt.term =
  let v = tr_val c env in
  match e with
  | A.ELit (A.LitInt n, _) -> Smt.IntLit n
  | A.ELit (A.LitBool b, _) -> Smt.BoolLit b
  | A.ELit (A.LitFloat f, _) -> (match Refine_scope.float_lit_term f with Some t -> t | None -> raise Decline)
  | A.ELit (A.LitString s, _) -> Smt.App (RS.str_lit_sym s, [])
  | A.EVar x -> (
    match List.assoc_opt x.A.txt env with Some t when not (is_sentinel t) -> t | _ -> raise Decline)
  | A.EAnnot (x, _, _) -> v x
  | A.EBlock ([ x ], _) -> v x
  | A.EBlock (_ :: _, _) | A.EMatch _ -> (
    match tr_case c env e with
    | [ ([], t) ] -> t
    (* Several cases in value position (an argument, an operand): an
       if-then-else chain.  Each case's guards already exclude the cases
       before it, and the cases cover (R5), so the last needs no test. *)
    | (_ :: _ :: _) as cases when List.length cases <= max_let_cases ->
      let rev = List.rev cases in
      List.fold_left (fun acc (g, r) -> Smt.Ite (conj g, r, acc)) (snd (List.hd rev)) (List.tl rev)
    | _ -> raise Decline)
  | A.EIf (cnd, a, b, _) -> Smt.Ite (v cnd, v a, v b)
  | A.ECon (ctor, args, sp) when RE.is_source_ctor ctor.A.txt ->
    (* Resolved by the expression's own type (2026-11-02). *)
    let adt, k = resolve_ctor ~construct:true ?adt:(Option.bind (c.c_ty sp) adt_of_ty) ctor.A.txt in
    let ts = List.map v args in
    if List.length ts <> List.length (try Hashtbl.find RE.ctor_field_sorts k with Not_found -> []) then
      raise Decline;
    RE.ctor_term adt k ts
  (* A tuple: its datatype's one constructor. *)
  | A.ETuple ((_ :: _ :: _ as xs), _) ->
    let n = List.length xs in
    RE.ctor_term (RE.tuple_adt n) (RE.tuple_ctor n) (List.map v xs)
  (* Records (§3.2): the declared record sort, its selectors and its one
     constructor.  A literal names every field exactly once. *)
  | A.EField (x, fld, _) ->
    let _, ctor, names = record_of_ty (c.c_ty (T.span_of_expr x)) in
    field_sel ctor (index_of fld.A.txt names) (v x)
  | A.ERecord (fs, sp) ->
    let adt, ctor, names = record_of_ty (c.c_ty sp) in
    let given = List.map (fun ((n : A.name), _) -> n.A.txt) fs in
    if List.sort compare given <> List.sort compare names then raise Decline;
    RE.ctor_term adt ctor
      (List.map (fun n -> v (snd (List.find (fun ((m : A.name), _) -> m.A.txt = n) fs))) names)
  | A.ERecordUpdate (x, fs, sp) ->
    let adt, ctor, names = record_of_ty (c.c_ty sp) in
    let given = List.map (fun ((n : A.name), _) -> n.A.txt) fs in
    if List.length (List.sort_uniq compare given) <> List.length given then raise Decline;
    List.iter (fun n -> ignore (index_of n names)) given;
    let base = v x in
    RE.ctor_term adt ctor
      (List.mapi
         (fun i n ->
           match List.find_opt (fun ((m : A.name), _) -> m.A.txt = n) fs with
           | Some (_, e) -> v e
           | None -> field_sel ctor i base)
         names)
  | A.EApp (A.EVar f, args, sp) -> (
    (* The same rule as [note] (third review C1): an ambiguous site has no
       single callee, in every branch below. *)
    if c.c_ambiguous sp then raise Decline;
    let site = Hashtbl.find_opt c.c_sites sp in
    let nm = f.A.txt in
    let target = Option.map (fun (s : RT.site) -> s.RT.s_target) site in
    match List.assoc_opt nm env, c.c_spec, target with
    (* Phase 5: a call of [g]'s function parameter is the call's argument
       applied: a lambda's body under its own scope (its parameters and its
       captures, never [g]'s names), or the named function's symbol. *)
    | Some (Smt.Const k as t), Some sc, _ when is_sentinel t -> (
      let p = String.sub k 4 (String.length k - 4) in
      let targs = List.map v args in
      match List.assoc_opt p sc.sc_fn with
      | Some (F_lambda (ps, body, _)) ->
        if List.length ps <> List.length targs then raise Decline;
        let env' = List.combine (List.map (fun (q : A.param) -> q.A.param_name.A.txt) ps) targs @ sc.sc_caps in
        tr_val { c with c_spec = None } env' body
      | Some (F_named (fu, _)) -> (
        match c.c_sym_of_unit fu with Some sym -> Smt.App (sym, targs) | None -> raise Decline)
      | None -> raise Decline)
    | Some t, _, _ when is_sentinel t -> raise Decline
    (* [g]'s own recursive call, each function parameter in its own place:
       the same specialisation. *)
    | _, Some sc, Some (RT.S_unit u) when u = sc.sc_self ->
      List.iteri
        (fun i a ->
          match List.assoc_opt i sc.sc_fnpos, a with
          | Some p, A.EVar x -> (
            match List.assoc_opt x.A.txt env with
            | Some t when t = sentinel p -> ()
            | Some t when spec_perturb "spec-any-position" && is_sentinel t -> ()
            | _ -> raise Decline)
          | Some _, _ -> raise Decline
          | None, _ -> ())
        args;
      let nonfn = List.filteri (fun i _ -> not (List.mem_assoc i sc.sc_fnpos)) args in
      Smt.App (sc.sc_sym, List.map v nonfn @ List.map snd sc.sc_caps)
    (* A specialised call: its symbol over the expressions [site_args]
       recorded, captures included, translated in this scope. *)
    | _, _, Some (RT.S_unit _) when Hashtbl.mem RS.site_args sp -> (
      match RS.resolve_site sp with
      | Some sym -> Smt.App (sym, List.map v (Hashtbl.find RS.site_args sp))
      | None -> raise Decline)
    | _, _, _ ->
    match target with
    | Some (RT.S_unit u) when c.c_len_unit u -> (
      match args with [ a ] -> Smt.App (RE.list_len_measure, [ v a ]) | _ -> raise Decline)
    | Some (RT.S_unit u) -> (
      match c.c_sym_of_unit u with
      | Some sym -> Smt.App (sym, List.map v args)
      | None -> raise Decline)
    | Some (RT.S_builtin | RT.S_impls _) -> builtin c env nm args
    | _ -> raise Decline)
  | _ -> raise Decline

(* A statement-position call of a lemma, `l(..)` or `let _ = l(..)`: erased
   before the program runs, so it is `()` in a reflected body (§4.5, I2). *)
and lemma_stmt (c : tctx) (e : A.expr) : bool =
  match e with
  | A.EProof (A.PAssertBy _, _) | A.ELet ({ A.bind_expr = A.EProof (A.PAssertBy _, _); _ }, _) -> true
  | _ ->
  let call =
    match e with
    | A.EApp (A.EVar _, _, sp) -> Some sp
    | A.ELet ({ A.bind_pat = A.PatWild _; bind_expr = A.EApp (A.EVar _, _, sp); _ }, _) -> Some sp
    | _ -> None
  in
  match Option.bind call (Hashtbl.find_opt c.c_sites) with
  | Some { RT.s_target = RT.S_unit u; _ } -> List.mem "lemma" c.c_unit.(u).RT.u_attrs
  | _ -> false

and builtin c env nm args =
  let v = tr_val c env in
  let ty_of a = c.c_ty (T.span_of_expr a) in
  match nm, args with
  | "+", [ a; b ] -> Smt.Add (v a, v b)
  | "-", [ a; b ] -> Smt.Sub (v a, v b)
  | "*", [ A.ELit (A.LitInt k, _); b ] -> Smt.MulLit (k, v b)
  | "*", [ a; A.ELit (A.LitInt k, _) ] -> Smt.MulLit (k, v a)
  | "*", [ a; b ] -> Smt.Mul (v a, v b)
  | "negate", [ a ] when is_int_ty (ty_of a) -> Smt.Neg (v a)
  | "string_byte_length", [ a ] -> Smt.App (RE.strlen_fn, [ v a ])
  (* D9: Float arithmetic and comparison are opaque symbols (§2.3). *)
  | "negate", [ a ] when is_float_ty (ty_of a) -> Smt.App (RS.float_sym "fneg", [ v a ])
  | (("+." | "-." | "*." | "/.") as op), [ a; b ] ->
    let f = match op with "+." -> "fadd" | "-." -> "fsub" | "*." -> "fmul" | _ -> "fdiv" in
    Smt.App (RS.float_sym f, [ v a; v b ])
  | (("<." | "<=." | ">." | ">=." | "<" | "<=" | ">" | ">=") as op), [ a; b ] when is_float_ty (ty_of a) ->
    let f =
      match op with "<." | "<" -> "flt" | "<=." | "<=" -> "fle" | ">." | ">" -> "fgt" | _ -> "fge"
    in
    Smt.App (RS.float_sym f, [ v a; v b ])
  | (("/" | "%") as op), [ a; d ] when RE.nonzero_int_literal d <> None ->
    Refine_scope.truncating_division ~op ~nonneg_dividend:false (v a) (`Lit (Option.get (RE.nonzero_int_literal d)))
  | (("/" | "%") as op), [ a; d ] ->
    (* A non-literal divisor: [divisions_defined] proves it non-zero from the
       function's own facts before the template is kept (R4). *)
    Refine_scope.truncating_division ~op ~nonneg_dividend:false (v a) (`Term (v d))
  | "&&", [ a; b ] -> Smt.And (v a, v b)
  | "||", [ a; b ] -> Smt.Or (v a, v b)
  | "not", [ a ] -> Smt.Not (v a)
  | (("<" | "<=" | ">" | ">=") as op), [ a; b ] when is_int_ty (ty_of a) ->
    let x = v a and y = v b in
    (match op with "<" -> Smt.Lt (x, y) | "<=" -> Smt.Le (x, y) | ">" -> Smt.Gt (x, y) | _ -> Smt.Ge (x, y))
  | (("==" | "!=") as op), [ a; b ] ->
    (* §3.5: the program's equality.  SMT [=] at a type whose [Eq] is derived
       all the way down and holds no Float; else the opaque [eq] symbol. *)
    let x = v a and y = v b in
    let eq =
      match ty_of a with
      | Some t when c.c_eq_structural t || perturb = Some "eq-structural" ->
        eq_seen := (T.pp_ty t, "structural") :: !eq_seen;
        Smt.Eq (x, y)
      | Some t ->
        eq_seen := (T.pp_ty t, "opaque") :: !eq_seen;
        Smt.App (RS.eq_sym, [ x; y ])
      | None -> raise Decline
    in
    if op = "==" then eq else Smt.Not eq
  | _ -> raise Decline

(* Tail position: guarded cases, one per path, with NO default (§3.4, C2). *)
and tr_case (c : tctx) (env : (string * Smt.term) list) (e : A.expr) : (Smt.term list * Smt.term) list =
  match e with
  | A.EAnnot (x, _, _) -> tr_case c env x
  | A.EBlock ([ x ], _) -> tr_case c env x
  | A.EBlock (stmt :: (_ :: _ as rest), sp) when lemma_stmt c stmt -> tr_case c env (A.EBlock (rest, sp))
  | A.EBlock (A.ELet (b, _) :: rest, sp) -> (
    match b.A.bind_pat with
    (* A right-hand side with several cases (a `match` or `if` in value
       position): the rest of the block once per case, each under that case's
       conditions, as a tail `match` is. *)
    | A.PatVar x ->
      let cases = tr_case c env b.A.bind_expr in
      if List.length cases > max_let_cases then raise Decline;
      List.concat_map
        (fun (g, t) ->
          List.map (fun (g', r) -> (g @ g', r)) (tr_case c ((x.A.txt, t) :: env) (A.EBlock (rest, sp))))
        cases
    (* A destructuring `let` (a record or tuple pattern): bindings only.  A
       pattern that tests anything (a constructor, a literal) declines. *)
    | p ->
      let adt = pat_adt (c.c_ty (T.span_of_expr b.A.bind_expr)) in
      let cases = tr_case c env b.A.bind_expr in
      if List.length cases > max_let_cases then raise Decline;
      List.concat_map
        (fun (g, t) ->
          let conds, binds = pat ?adt p t in
          if conds <> [] then raise Decline;
          List.map (fun (g', r) -> (g @ g', r)) (tr_case c (binds @ env) (A.EBlock (rest, sp))))
        cases)
  | A.EBlock (A.ELetFn _ :: rest, sp) -> tr_case c env (A.EBlock (rest, sp))
  | A.EBlock (_, _) -> raise Decline
  | A.EIf (cnd, a, b, _) ->
    let t = tr_val c env cnd in
    List.map (fun (g, r) -> (t :: g, r)) (tr_case c env a)
    @ List.map (fun (g, r) -> (Smt.Not t :: g, r)) (tr_case c env b)
  | A.EMatch (scrut, branches, _) ->
    let subjects =
      match scrut with
      | A.ETuple (xs, _) -> List.map (tr_val c env) xs
      | x -> [ tr_val c env x ]
    in
    (* Each subject's datatype, from its type, for its constructor patterns. *)
    let adt_of x = pat_adt (c.c_ty (T.span_of_expr x)) in
    let adts = match scrut with A.ETuple (xs, _) -> List.map adt_of xs | x -> [ adt_of x ] in
    let tupled = match scrut with A.ETuple _ -> true | _ -> false in
    let prior = ref [] in
    List.concat_map
      (fun (br : A.branch) ->
        let conds, binds =
          match tupled, br.A.branch_pat with
          | true, A.PatTuple (ps, _) when List.length ps = List.length subjects ->
            List.fold_left2
              (fun (cs, bs) p (s, adt) ->
                let c', b' = pat ?adt p s in
                (cs @ c', bs @ b'))
              ([], []) ps (List.combine subjects adts)
          | true, A.PatWild _ -> ([], [])
          | false, p -> pat ?adt:(List.hd adts) p (List.hd subjects)
          | _ -> raise Decline
        in
        let env' = binds @ env in
        let guard = match br.A.branch_guard with Some g -> [ tr_val c env' g ] | None -> [] in
        let here = conds @ guard in
        let negs = List.rev_map (fun h -> Smt.Not (conj h)) !prior in
        prior := here :: !prior;
        List.map (fun (g, r) -> (negs @ here @ g, r)) (tr_case c env' br.A.branch_body))
      branches
  | e -> [ ([], tr_val c env e) ]

(* A pattern over a subject term: its conditions and bindings. *)
(* [adt]: the subject's datatype, when its type pins one ([adt_of_ty]). *)
and pat ?(adt : string option) (p : A.pattern) (s : Smt.term) : Smt.term list * (string * Smt.term) list =
  match p with
  | A.PatWild _ -> ([], [])
  | A.PatVar x -> ([], [ (x.A.txt, s) ])
  | A.PatAs (q, x, _) ->
    let cs, bs = pat ?adt q s in
    (cs, (x.A.txt, s) :: bs)
  | A.PatLit (A.LitInt n, _) -> ([ Smt.Eq (s, Smt.IntLit n) ], [])
  | A.PatLit (A.LitBool b, _) -> ([ (if b then s else Smt.Not s) ], [])
  | A.PatCon (ctor, ps) when RE.is_source_ctor ctor.A.txt ->
    let _, k = resolve_ctor ?adt ctor.A.txt in
    let n = List.length (try Hashtbl.find RE.ctor_field_sorts k with Not_found -> raise Decline) in
    if List.length ps <> n then raise Decline;
    let sub =
      List.mapi (fun i q -> pat ?adt:(field_adt k i) q (Smt.App (Printf.sprintf "%s_%d" k i, [ s ]))) ps
    in
    (Smt.IsCtor (k, s) :: List.concat_map fst sub, List.concat_map snd sub)
  (* A tuple pattern: its one constructor always matches; each component's
     sub-pattern over its selector. *)
  | A.PatTuple ((_ :: _ :: _ as ps), _) ->
    let n = List.length ps in
    ignore (RE.tuple_adt n);
    let ctor = RE.tuple_ctor n in
    let sub = List.mapi (fun i q -> pat q (field_sel ctor i s)) ps in
    (List.concat_map fst sub, List.concat_map snd sub)
  (* A record pattern: its one constructor always matches; each named
     field's sub-pattern over its selector. *)
  | A.PatRecord (fps, _) ->
    let _, ctor, names =
      match adt with
      | Some a when a <> RE.ambiguous_adt_sentinel -> (match record_of_adt a with Some r -> r | None -> raise Decline)
      | _ -> raise Decline
    in
    let sub =
      List.map
        (fun ((n : A.name), q) ->
          let i = index_of n.A.txt names in
          pat ?adt:(field_adt ctor i) q (field_sel ctor i s))
        fps
    in
    (List.concat_map fst sub, List.concat_map snd sub)
  | _ -> raise Decline

(* The guard of an unfolding (§3.6): each parameter refinement, over the
   placeholders.  Only predicate vocabulary R8 admitted reaches here; one that
   does not translate leaves the function without equations. *)
let pre_of (u : RT.unit_) (psorts : Smt.sort list) : Smt.term list =
  List.concat
    (List.mapi
       (fun i (p, ty) ->
         match p, ty with
         | Some pn, Some ty ->
           let rec refs (t : A.ty) =
             match t with
             | A.TyRefine (b, binder, pred) -> (Option.fold ~none:"_" ~some:(fun b -> b.A.txt) binder, pred) :: refs b
             | A.TyLinear (_, b) -> refs b
             | _ -> []
           in
           List.map
             (fun (bn, pred) ->
               let var x =
                 if x = bn || x = pn then Some (Smt.Const (param_const i))
                 else
                   match List.find_index (fun q -> q = Some x) u.RT.u_params with
                   | Some j -> Some (Smt.Const (param_const j))
                   | None -> None
               in
               let is_list j = match List.nth_opt psorts j with Some (Smt.SData (a, _)) -> a = RE.list_adt | _ -> false in
               let measure m x =
                 match var x with
                 | Some (Smt.Const c as t) when m = "len" ->
                   let j = int_of_string (String.sub c 3 (String.length c - 3)) in
                   if is_list j then Some (Smt.App (RE.list_len_measure, [ t ])) else None
                 | _ -> None
               in
               match
                 Refine_scope.smt_of ~resolve_var:var ~resolve_measure:measure
                   ~resolve_tester:(fun ctor a ->
                     match a with
                     | A.EVar x ->
                       (* The tester's constructor, by the parameter's sort. *)
                       let adt =
                         match var x.A.txt with
                         | Some (Smt.Const pc) ->
                           (match List.find_index (fun j -> param_const j = pc) (List.init (List.length psorts) Fun.id) with
                            | Some j ->
                              (match List.nth_opt psorts j with
                               | Some (Smt.SData (a, _)) -> Some a
                               (* A known sort that is no datatype (review round 3). *)
                               | Some _ -> Some RE.ambiguous_adt_sentinel
                               | None -> None)
                            | None -> None)
                         | _ -> None
                       in
                       let _, k = resolve_ctor ?adt ctor in
                       Option.map (fun t -> Smt.IsCtor (k, t)) (var x.A.txt)
                     | _ -> None)
                   pred
               with
               | Some t -> t
               | None -> raise Decline)
             (refs ty)
         | None, Some ty when (match ty with A.TyRefine _ -> true | _ -> false) -> raise Decline
         | _ -> [])
       (List.combine u.RT.u_params u.RT.u_param_tys))

(* The origin of a definition (§3.1): [std], [lib:<dir>] or [user]. *)
let origin_of_file ~(user_files : string list) (f : string) : string =
  ignore user_files;
  if March_typecheck.Typecheck_builtins.file_is_stdlib f then "std" else "user"

(** The encoder's verdicts for the module, kept for the report's note on a
    row the encoder does not unfold. *)
let encoder_blocked : (A.span, string) Hashtbl.t = Hashtbl.create 64

(** Internal errors [install] found (a duplicate symbol, I4), reported by
    the driver. *)
let install_errors : (A.span * string) list ref = ref []

(** (display name, declaring file) of every function the last [install]
    found reflected, whether or not it got a logic symbol (the parity net
    lists the ones that did not, review round 1). *)
let reflected_fns : (string * string) list ref = ref []

(** Phase 5: each specialisation's symbol -> its call site and the names of
    its captures, for the parity net. *)
let spec_meta : (string, spec_site * string list) Hashtbl.t = Hashtbl.create 16

(** The termination graph's units of the last [install] (the parity net names
    a specialisation's callee and named arguments through it). *)
let last_units : RT.unit_ array ref = ref [||]

let debug_registered = ref false

(* Every reflected logic symbol a query applies is declared by its preamble
   ([Refine_encode.query_instance_preamble] declares the ones [resolve_sorts]
   named).  A discharge path that skips that step would send z3 an undeclared
   symbol; [Refine.discharge] refuses such a query instead (sound: it is not
   proved). *)
let declared_logic_symbols (preamble : string) (vc : Smt.vc) : bool =
  let ok = ref true in
  let contains hay needle =
    let n = String.length needle and h = String.length hay in
    let rec at i = i + n <= h && (String.sub hay i n = needle || at (i + 1)) in
    at 0
  in
  let rec walk (t : Smt.term) =
    if !ok then begin
      (match t with
       | Smt.App (f, _) when String.length f > 3 && String.sub f 0 3 = "|r:" ->
         if not (contains preamble ("(declare-fun " ^ f ^ " ")) then ok := false
       | _ -> ());
      List.iter walk (Smt.children t)
    end
  in
  List.iter walk (vc.Smt.goal :: vc.Smt.assumptions);
  !ok

(** Certificates known before the walk: a metric certificate the previous
    pass of [Refine_check.check_module] decided (R2). *)
let seed_certs : (A.span, string) Hashtbl.t = Hashtbl.create 8

let install ~(user_files : string list) ~(type_map : (A.span, T.ty) Hashtbl.t option) (t : RT.t)
    (decls : A.decl list) : unit =
  RS.reset ();
  Hashtbl.reset templates;
  Hashtbl.reset encoder_blocked;
  install_errors := [];
  reflected_fns := [];
  Hashtbl.reset RS.blocked_by_name;
  let g = t.RT.graph in
  last_units := g.RT.units;
  let ne = Hashtbl.create 64 in
  List.iter (fun sp -> Hashtbl.replace ne sp ()) !March_typecheck.Typecheck.last_nonexhaustive_match_spans;
  let inputs =
    { certs = Hashtbl.find_opt seed_certs;
      nonexhaustive = Hashtbl.mem ne;
      (* A non-literal divisor passes here and is decided on the translated
         template ([divisions_defined]): the ledger's verdict comes after. *)
      division = (fun _ -> Some Obligation.Proved);
      type_map;
      vocab = (fun s -> s = "len" || List.mem s RE.set_vocabulary || RE.ctor_of_tester s <> None);
      pred_fn = (fun s -> s = "len" || RE.known_predicate_fn s) }
  in
  let rows = analyze inputs t decls in
  let refl_spans = Hashtbl.create 64 in
  reflected_fns :=
    List.filter_map
      (fun r -> match r.r_verdict with Reflected _ -> Some (r.r_name, r.r_span.A.file) | Blocked _ | Specialised _ -> None)
      rows;
  List.iter
    (fun r ->
      match r.r_verdict with
      | Reflected _ -> Hashtbl.replace refl_spans r.r_span ()
      | Blocked b ->
        Hashtbl.replace encoder_blocked r.r_span (Printf.sprintf "R%d:%s" b.b_rule b.b_text);
        if not (String.contains r.r_name '/') then Hashtbl.replace RS.blocked_by_name r.r_name (b.b_text, b.b_span)
      | Specialised _ ->
        (* Phase 5: no definition of its own, so not reflected for every
           reader that asks (a predicate, a lemma argument), only each of its
           specialised calls is. *)
        let why = "takes a function, so only its calls with a lambda or a function's name are reflected" in
        Hashtbl.replace encoder_blocked r.r_span ("R7:" ^ why);
        if not (String.contains r.r_name '/') then Hashtbl.replace RS.blocked_by_name r.r_name (why, r.r_span))
    rows;
  let ty_at sp = match type_map with Some tm -> Hashtbl.find_opt tm sp | None -> None in
  (* §3.1: the mangled, injective symbol of each reflected unit. *)
  let sym_of = Array.make (Array.length g.RT.units) None in
  let owners : (string, int) Hashtbl.t = Hashtbl.create 64 in
  let dup = ref [] in
  (* A revealable [@[opaque]] unit gets a symbol too, but only in a program
     that says `reveal` somewhere: anywhere else nothing changes. *)
  let reveals =
    let found = ref false in
    let body e = RE.iter_all (function A.EProof (A.PReveal _, _) -> found := true | _ -> ()) e in
    let fn (fd : A.fn_def) = List.iter (fun (c : A.fn_clause) -> body c.A.fc_body) fd.A.fn_clauses in
    (* Every place a statement can be: functions, impl methods, actor handlers,
       tests, an app's body (review minor). *)
    let rec scan ds =
      List.iter
        (function
          | A.DFn (fd, _) -> fn fd
          | A.DImpl (idf, _) -> List.iter (fun (_, fd) -> fn fd) idf.A.impl_methods
          | A.DActor (_, _, ad, _) ->
            body ad.A.actor_init;
            List.iter (fun (h : A.actor_handler) -> body h.A.ah_body) (A.actor_body_handlers ad)
          | A.DTest (t, _) -> body t.A.test_body
          | A.DApp (app, _) -> body app.A.app_body
          | A.DLet (_, b, _) -> body b.A.bind_expr
          | A.DMod (_, _, inner, _) | A.DDescribe (_, inner, _) -> scan inner
          | _ -> ())
        ds
    in
    scan decls;
    !found
  in
  let hidden_units = Hashtbl.create 8 in
  Array.iter
    (fun (u : RT.unit_) ->
      if reveals && Hashtbl.mem revealable u.RT.u_span then Hashtbl.replace hidden_units u.RT.u_id ())
    g.RT.units;
  Array.iter
    (fun (u : RT.unit_) ->
      if Hashtbl.mem refl_spans u.RT.u_span || Hashtbl.mem hidden_units u.RT.u_id then begin
        let origin = origin_of_file ~user_files u.RT.u_span.A.file in
        (* The display name is not unique on its own (an entry module's
           nested `mod X` and a library `X` both print `X.g`, review C-A):
           the declaration's position makes the symbol injective. *)
        let path =
          Printf.sprintf "%s#%s:%d:%d" u.RT.u_name (Filename.basename u.RT.u_span.A.file) u.RT.u_span.A.start_line
            u.RT.u_span.A.start_col
        in
        let sym = Printf.sprintf "|r:%s:%s|" origin path in
        (match Hashtbl.find_opt owners sym with
         | Some v when v <> u.RT.u_id -> dup := (sym, u) :: !dup
         | _ -> Hashtbl.replace owners sym u.RT.u_id);
        sym_of.(u.RT.u_id) <- Some sym
      end)
    g.RT.units;
  (* The duplicate-definition check (§3.1, I4): two definitions must never
     share a symbol.  Neither is reflected, and the collision is reported. *)
  List.iter
    (fun (sym, (u : RT.unit_)) ->
      (* Defensive only: positions make this unreachable.  A collision
         leaves both functions out of the logic; it is never an error, since
         a valid program must not fail to check because of reflection. *)
      ignore u;
      Array.iteri (fun i s -> if s = Some sym then sym_of.(i) <- None) sym_of)
    !dup;
  (* Types whose program [==] is SMT [=] (§3.5). *)
  let tbl = RT.collect_types decls in
  let hand_eq = Hashtbl.create 16 in
  let rec scan ds =
    List.iter
      (function
        | A.DImpl (idf, _) when RT.bare idf.A.impl_iface.A.txt = "Eq" && idf.A.impl_iface.A.span.A.file <> "<none>" -> (
          match strip idf.A.impl_ty with A.TyCon (n, _) -> Hashtbl.replace hand_eq (RT.bare n.A.txt) () | _ -> ())
        | A.DMod (_, _, inner, _) -> scan inner
        | _ -> ())
      ds
  in
  scan decls;
  (* A bare type name declared more than once (an entry type and a
     library's, M1): which one an [Eq] or a field type means is not decided
     by the bare name, so neither counts as structural. *)
  let decl_count = Hashtbl.create 64 in
  let rec count ds =
    List.iter
      (function
        | A.DType (_, n, _, _, _) | A.DAlwaysLinearType (_, n, _, _, _) ->
          Hashtbl.replace decl_count n.A.txt (1 + Option.value ~default:0 (Hashtbl.find_opt decl_count n.A.txt))
        | A.DMod (_, _, inner, _) -> count inner
        | _ -> ())
      ds
  in
  count decls;
  let dup_type b = Option.value ~default:0 (Hashtbl.find_opt decl_count b) > 1 in
  Hashtbl.reset RS.hand_eq;
  Hashtbl.iter (fun k () -> Hashtbl.replace RS.hand_eq k ()) hand_eq;
  let rec structural_ty seen (t : T.ty) =
    match T.repr t with
    | T.TCon (("Int" | "Bool" | "String"), []) -> true
    | T.TCon (n, args) ->
      let b = RT.bare n in
      (not (Hashtbl.mem hand_eq b)) && (not (dup_type b)) && b <> "Float"
      && List.for_all (structural_ty seen) args
      && (List.mem b seen
          ||
          match Hashtbl.find_opt tbl b with
          | Some d -> List.for_all (structural_aty (b :: seen)) d.RT.t_fields
          | None -> List.mem b [ "List"; "Option"; "Result" ])
    | _ -> false
  and structural_aty seen (t : A.ty) =
    match strip t with
    | A.TyCon (n, args) ->
      let b = RT.bare n.A.txt in
      (match b with
       | "Int" | "Bool" | "String" -> true
       | "Float" -> false
       | _ ->
         (not (Hashtbl.mem hand_eq b))
         && (not (dup_type b))
         && List.for_all (structural_aty seen) args
         && (List.mem b seen
             || match Hashtbl.find_opt tbl b with
                | Some d -> List.for_all (structural_aty (b :: seen)) d.RT.t_fields
                | None -> List.mem b [ "List"; "Option"; "Result" ]))
    | A.TyVar _ -> true (* a field of the declaring type's parameter: its instance decides, checked at the use *)
    | _ -> false
  in
  let sites = Hashtbl.create 256 in
  List.iter (fun (s : RT.site) -> if s.RT.s_call then Hashtbl.replace sites s.RT.s_span s) g.RT.sites;
  let len_unit v =
    let u = g.RT.units.(v) in
    March_typecheck.Typecheck_builtins.file_is_stdlib u.RT.u_span.A.file
    &&
    match RT.bare u.RT.u_name, u.RT.u_name with
    | "length", ("List.length" | "length") ->
      !RE.list_length_is_stdlib && Filename.basename u.RT.u_span.A.file = "list.march"
    | _ -> false
  in
  let ctx =
    { c_sites = sites; c_sym_of_unit = (fun v -> sym_of.(v)); c_ty = ty_at; c_len_unit = len_unit;
      c_eq_structural = structural_ty []; c_unit = g.RT.units; c_ambiguous = Hashtbl.mem g.RT.ambiguous; c_spec = None }
  in
  (* Signatures (§3.2, §3.3). *)
  let axiom_tier = Hashtbl.create 8 in
  let sig_ptys = Array.make (Array.length g.RT.units) None in
  Array.iter
    (fun (u : RT.unit_) ->
      match sym_of.(u.RT.u_id) with
      | None -> ()
      | Some sym -> (
        try
          let vars = ref [] in
          let ptys =
            List.map
              (fun sp -> match Option.bind sp ty_at with Some t -> poly_sort vars t | None -> raise Decline)
              u.RT.u_param_spans
          in
          let body = match u.RT.u_clauses with [ c ] -> c.RT.o_body | _ -> raise Decline in
          let ret = match ty_at (T.span_of_expr body) with Some t -> poly_sort vars t | None -> raise Decline in
          if ptys = [] then raise Decline;
          let fs = { RS.fs_sym = sym; fs_name = u.RT.u_name; fs_params = ptys; fs_ret = ret; fs_nvars = List.length !vars } in
          (* An axiom-tier measure (§5.3) keeps its own symbol in predicates:
             its calls never reach stage 2 (I10).  Its reflected symbol still
             serves a reflected body that calls it. *)
          RS.register fs;
          sig_ptys.(u.RT.u_id) <- Some ptys;
          if List.mem "measure" u.RT.u_attrs && List.mem (RT.bare u.RT.u_name) !RE.registered_measures then
            Hashtbl.replace axiom_tier sym ()
        with Decline | Not_found | Invalid_argument _ -> ()))
    g.RT.units;
  (* The one resolution rule (review C-1, C-2): a call site denotes a
     reflected function exactly when the termination graph's lexical walk
     resolved THAT site to that unit (program code), or resolved it in the
     scope where the predicate is written (a signature's refinement).  An
     axiom-tier measure is never a frontier call (I10).  Filled before the
     templates so a guard that calls a reflected function translates through
     the same rule (phase 1b). *)
  let note sp v =
    if Hashtbl.mem g.RT.ambiguous sp then ()
    else
    match sym_of.(v) with
    | Some sym when Hashtbl.mem RS.syms sym && not (Hashtbl.mem axiom_tier sym) ->
      if Hashtbl.mem hidden_units v then
        Hashtbl.replace RS.hidden_call_sym sp (sym, g.RT.units.(v).RT.u_name)
      else Hashtbl.replace RS.call_sym sp sym
    | _ -> ()
  in
  List.iter
    (fun (s : RT.site) -> match s.RT.s_target with RT.S_unit v when s.RT.s_call -> note s.RT.s_span v | _ -> ())
    g.RT.sites;
  List.iter (fun (sp, tgt) -> match tgt with RT.S_unit v -> note sp v | _ -> ()) g.RT.pred_sites;
  (* Phase 5: one symbol per specialised call site.  Its parameters are the
     callee's non-function parameters, then the lambdas' captures; its sorts
     are the call's own (§3.2).  Registered before any template, since a
     reflected caller's body translates the call through it. *)
  Hashtbl.reset spec_meta;
  let ref_sites = Hashtbl.create 64 in
  List.iter (fun (s : RT.site) -> if not s.RT.s_call then Hashtbl.replace ref_sites s.RT.s_span ()) g.RT.sites;
  (* A lambda's captures: the names its body reads that it does not bind and
     the graph did not resolve to a function (no site), in order. *)
  let captures (fa : (int * fn_arg) list) : (string * A.expr) list =
    let acc = ref [] in
    let rec go bound (e : A.expr) =
      match e with
      | A.EVar x ->
        if (not (List.mem x.A.txt bound)) && (not (Hashtbl.mem ref_sites x.A.span)) && not (List.mem_assoc x.A.txt !acc)
        then acc := (x.A.txt, e) :: !acc
      | A.EApp (A.EVar _, args, sp)
        when (match Hashtbl.find_opt sites sp with Some { RT.s_target = RT.S_value; _ } | None -> false | Some _ -> true) ->
        List.iter (go bound) args
      | A.EMatch (sc, brs, _) ->
        go bound sc;
        List.iter
          (fun (br : A.branch) ->
            let b = RT.pat_vars br.A.branch_pat @ bound in
            Option.iter (go b) br.A.branch_guard;
            go b br.A.branch_body)
          brs
      | A.EBlock (es, _) ->
        ignore
          (List.fold_left
             (fun b (x : A.expr) ->
               match x with
               | A.ELet (lb, _) -> go b lb.A.bind_expr; RT.pat_vars lb.A.bind_pat @ b
               | x -> go b x; b)
             bound es)
      | A.ELet (lb, _) -> go bound lb.A.bind_expr
      | A.ELam (ps, body, _) -> go (List.map (fun (p : A.param) -> p.A.param_name.A.txt) ps @ bound) body
      | A.ELetQ (p, r, k, _) | A.ELetStar (p, r, k, _) -> go bound r; go (RT.pat_vars p @ bound) k
      | e -> List.iter (go bound) (RE.children e)
    in
    List.iter (function _, F_lambda (ps, body, _) -> go (List.map (fun (p : A.param) -> p.A.param_name.A.txt) ps) body | _ -> ()) fa;
    List.rev !acc
  in
  let unit_path (u : RT.unit_) =
    Printf.sprintf "%s#%s:%d:%d" u.RT.u_name (Filename.basename u.RT.u_span.A.file) u.RT.u_span.A.start_line
      u.RT.u_span.A.start_col
  in
  let spec_defs =
    Hashtbl.fold (fun _ ss acc -> ss :: acc) spec_sites []
    |> List.sort (fun a b -> compare (span_str a.ss_span) (span_str b.ss_span))
    |> List.filter_map (fun ss ->
           try
             let gu = g.RT.units.(ss.ss_callee) in
             let fnpos = List.map fst ss.ss_fn in
             let nonfn = List.filteri (fun i _ -> not (List.mem i fnpos)) ss.ss_args in
             let caps = captures ss.ss_fn in
             let vars = ref [] in
             let sort_of e = match ty_at (T.span_of_expr e) with Some t -> poly_sort vars t | None -> raise Decline in
             let ptys = List.map sort_of nonfn @ List.map (fun (_, e) -> sort_of e) caps in
             let ret = match ty_at ss.ss_span with Some t -> poly_sort vars t | None -> raise Decline in
             if ptys = [] then raise Decline;
             let origin = origin_of_file ~user_files gu.RT.u_span.A.file in
             let at = ss.ss_span in
             let sym =
               if spec_perturb "spec-key-by-callee" then Printf.sprintf "|r:%s:%s$spec|" origin (unit_path gu)
               else
                 Printf.sprintf "|r:%s:%s$spec:%s#%s:%d:%d|" origin (unit_path gu)
                   g.RT.units.(ss.ss_caller).RT.u_name (Filename.basename at.A.file) at.A.start_line at.A.start_col
             in
             let name =
               Printf.sprintf "%s[%s:%d:%d]" gu.RT.u_name (Filename.basename at.A.file) at.A.start_line at.A.start_col
             in
             let fs = { RS.fs_sym = sym; fs_name = name; fs_params = ptys; fs_ret = ret; fs_nvars = List.length !vars } in
             Some (sym, ss, fs, nonfn @ List.map snd caps, List.map fst caps)
           with Decline | Not_found | Invalid_argument _ | Failure _ -> None)
  in
  (* Two call sites one symbol (a basename shared by two directories): the
     §3.1 duplicate check.  Neither is specialised.  (Test-only
     [spec-key-by-callee] shares one on purpose: the first template wins.) *)
  let spec_defs =
    if spec_perturb "spec-key-by-callee" then spec_defs
    else List.filter (fun (sym, _, _, _, _) -> List.length (List.filter (fun (s, _, _, _, _) -> s = sym) spec_defs) = 1) spec_defs
  in
  List.iter
    (fun (sym, ss, fs, args, caps) ->
      if not (Hashtbl.mem RS.syms sym) then begin
        RS.register fs;
        Hashtbl.replace spec_meta sym (ss, caps)
      end;
      Hashtbl.replace RS.call_sym ss.ss_span sym;
      Hashtbl.replace RS.site_args ss.ss_span args)
    spec_defs;
  (* Templates (§3.4, §3.6). *)
  Array.iter
    (fun (u : RT.unit_) ->
      match sym_of.(u.RT.u_id), sig_ptys.(u.RT.u_id) with
      | Some sym, Some ptys -> (
        (* The body: a failure leaves the symbol uninterpreted, which is
           sound (no equation is asserted), only weaker. *)
        try
          let body = match u.RT.u_clauses with [ c ] -> c.RT.o_body | _ -> raise Decline in
          let names =
            List.mapi
              (fun i p -> match p with Some n -> (n, Smt.Const (param_const i)) | None -> raise Decline)
              (match u.RT.u_clauses with [ c ] -> c.RT.o_params | _ -> raise Decline)
          in
          (* Two parameters of one name (`fn two(a, a)`): which one the
             body reads is the binder order's business, not the
             translator's guess.  No definition. *)
          if List.length (List.sort_uniq compare (List.map fst names)) <> List.length names then raise Decline;
          eq_seen := [];
          let cases = tr_case ctx names body in
          let cases = if perturb = Some "swap-arms" then swap_arms cases else cases in
          let eqs = List.sort_uniq compare !eq_seen in
          (* A guard that calls a reflected function translates through its
             logic symbol: the predicate translator's reflected-call arm,
             which only translates in stage 2. *)
          let pre =
            let saved = !RS.arm_on and saved_active = !RS.active in
            RS.arm_on := true;
            RS.active := true;
            Fun.protect
              ~finally:(fun () -> RS.arm_on := saved; RS.active := saved_active)
              (fun () -> pre_of u ptys)
          in
          let int_consts =
            List.concat (List.mapi (fun i s -> if s = Smt.SInt then [ param_const i ] else []) ptys)
          in
          if not (divisions_defined ~solver:(solver_nonzero ~int_consts) pre cases) then begin
            let why = "divides by a value nothing shows is non-zero" in
            Hashtbl.replace encoder_blocked u.RT.u_span ("R4:" ^ why);
            if not (String.contains u.RT.u_name '/') then Hashtbl.replace RS.blocked_by_name u.RT.u_name (why, u.RT.u_span);
            raise Decline
          end;
          let fuel =
            match fuel_of_attrs u.RT.u_attrs with Some n when n >= 1 && n <= 8 -> n | _ -> default_fuel
          in
          Hashtbl.replace templates sym
            { t_cases = cases; t_pre = pre; t_name = u.RT.u_name; t_eqs = eqs; t_fuel = fuel }
        with Decline | Not_found | Invalid_argument _ | Failure _ -> ())
      | _ -> ())
    g.RT.units;
  (* Phase 5: each specialisation's template, [g]'s body with its function
     parameters standing for the call's arguments (ruling 5). *)
  Hashtbl.iter
    (fun sym ((ss : spec_site), caps) ->
      try
        let gu = g.RT.units.(ss.ss_callee) in
        let fs = Hashtbl.find RS.syms sym in
        let c = match gu.RT.u_clauses with [ c ] -> c | _ -> raise Decline in
        let pname i = match List.nth c.RT.o_params i with Some n -> n | None -> raise Decline in
        let nonfn_idx = List.filter (fun i -> not (List.mem_assoc i ss.ss_fn)) (List.init (List.length c.RT.o_params) Fun.id) in
        let nn = List.length nonfn_idx in
        let names =
          List.mapi
            (fun i _ ->
              let n = pname i in
              if List.mem_assoc i ss.ss_fn then (n, sentinel n)
              else
                match List.find_index (( = ) i) nonfn_idx with
                | Some k -> (n, Smt.Const (param_const k))
                | None -> raise Decline)
            c.RT.o_params
        in
        if List.length (List.sort_uniq compare (List.map fst names)) <> List.length names then raise Decline;
        (* A refinement on a function parameter itself would not be part of
           the guard below: decline rather than drop it. *)
        List.iter
          (fun (i, _) -> match List.nth_opt gu.RT.u_param_tys i with Some (Some (A.TyRefine _)) -> raise Decline | _ -> ())
          ss.ss_fn;
        let capterms =
          List.mapi (fun j n -> (n, if spec_perturb "spec-capture-zero" then Smt.IntLit 0 else Smt.Const (param_const (nn + j)))) caps
        in
        let sc =
          { sc_self = ss.ss_callee; sc_sym = sym;
            sc_fn = List.map (fun (i, fa) -> (pname i, fa)) ss.ss_fn;
            sc_fnpos = List.map (fun (i, _) -> (i, pname i)) ss.ss_fn;
            sc_caps = capterms }
        in
        eq_seen := [];
        let cases = tr_case { ctx with c_spec = Some sc } names c.RT.o_body in
        let cases = if spec_perturb "spec-swap-arms" then swap_arms cases else cases in
        let eqs = List.sort_uniq compare !eq_seen in
        (* The domain guard: [g]'s refinements on its non-function
           parameters, renumbered to this symbol's. *)
        let pick l = List.map (fun i -> List.nth l i) nonfn_idx in
        let fake = { gu with RT.u_params = pick gu.RT.u_params; u_param_tys = pick gu.RT.u_param_tys } in
        let psorts = List.filteri (fun i _ -> i < nn) fs.RS.fs_params in
        let pre =
          let saved = !RS.arm_on and saved_active = !RS.active in
          RS.arm_on := true;
          RS.active := true;
          Fun.protect ~finally:(fun () -> RS.arm_on := saved; RS.active := saved_active) (fun () -> pre_of fake psorts)
        in
        let fuel = match fuel_of_attrs gu.RT.u_attrs with Some n when n >= 1 && n <= 8 -> n | _ -> default_fuel in
        Hashtbl.replace templates sym { t_cases = cases; t_pre = pre; t_name = fs.RS.fs_name; t_eqs = eqs; t_fuel = fuel }
      with Decline | Not_found | Invalid_argument _ | Failure _ -> ())
    spec_meta;
  (* The D17 hash of every reflected function (§7.1, I8). *)
  let file_cache : (string, string option) Hashtbl.t = Hashtbl.create 16 in
  let file_text f =
    match Hashtbl.find_opt file_cache f with
    | Some t -> t
    | None ->
      let t = try Some (In_channel.with_open_bin f In_channel.input_all) with Sys_error _ -> None in
      Hashtbl.replace file_cache f t;
      t
  in
  (* The source text of a unit: from its name to the end of its last clause
     body.  Position-free, so an edit elsewhere in the file (a line inserted
     above) does not change it. *)
  let source_of (u : RT.unit_) =
    let sp = u.RT.u_span in
    let stop =
      List.fold_left
        (fun (l, c) (o : RT.owner) ->
          let b = T.span_of_expr o.RT.o_body in
          if (b.A.end_line, b.A.end_col) > (l, c) then (b.A.end_line, b.A.end_col) else (l, c))
        (sp.A.end_line, sp.A.end_col) u.RT.u_clauses
    in
    match file_text sp.A.file with
    | None -> None
    | Some text ->
      let offset (line, col) =
        let rec go i l = if l >= line then Some i else match String.index_from_opt text i '\n' with Some j -> go (j + 1) (l + 1) | None -> None in
        Option.map (fun i -> i + col) (go 0 1)
      in
      (match offset (sp.A.start_line, sp.A.start_col), offset stop with
       | Some a, Some b when a >= 0 && b >= a && b <= String.length text -> Some (String.sub text a (b - a))
       | _ -> None)
  in
  (* A template's text with every logic symbol named by its function and
     file, not its position: the symbol's position moves with unrelated
     edits, the identity does not. *)
  let canon_name s =
    match Hashtbl.find_opt RS.syms s with
    | Some fs -> (
      match Hashtbl.find_opt owners s with
      | Some v -> Printf.sprintf "%s@%s" fs.RS.fs_name (Filename.basename g.RT.units.(v).RT.u_span.A.file)
      | None -> fs.RS.fs_name)
    | None -> s
  in
  let rec canon (t : Smt.term) : Smt.term =
    match t with
    | Smt.App (f, args) -> Smt.App (canon_name f, List.map canon args)
    | t -> map_term canon t
  in
  let guards_of = Hashtbl.create 64 in
  List.iter
    (fun r -> match r.r_verdict with Reflected gs -> Hashtbl.replace guards_of r.r_span gs | Blocked _ | Specialised _ -> ())
    rows;
  Array.iter
    (fun (u : RT.unit_) ->
      match sym_of.(u.RT.u_id) with
      | Some sym when Hashtbl.mem RS.syms sym ->
        let src = Option.value ~default:"" (source_of u) in
        let status =
          "reflected" ^ String.concat "" (List.map (fun g -> "\000guard " ^ g) (Option.value ~default:[] (Hashtbl.find_opt guards_of u.RT.u_span)))
        in
        let defn, eqs =
          match Hashtbl.find_opt templates sym with
          | None -> ("uninterpreted", [])
          | Some tp ->
            ( String.concat "\000"
                (List.map (fun t -> "pre " ^ Smt.render (canon t)) tp.t_pre
                @ List.map
                    (fun (cs, r) ->
                      "case " ^ String.concat " & " (List.map (fun c -> Smt.render (canon c)) cs) ^ " => " ^ Smt.render (canon r))
                    tp.t_cases),
              tp.t_eqs )
        in
        let payload =
          if perturb = Some "hash-text-only" then src
          else
            String.concat "\000"
              ([ "march-reflect-logic-v1"; src; status; defn ]
              @ List.map (fun (t, k) -> "eq " ^ t ^ " " ^ k) eqs)
        in
        let h = March_cas.Blake3.hash_string payload in
        Hashtbl.replace RS.logic_hash sym h;
        Hashtbl.replace RS.sym_origin sym (u.RT.u_name, u.RT.u_span.A.file);
        let prev = Option.value ~default:[] (Hashtbl.find_opt RS.logic_by_name u.RT.u_name) in
        Hashtbl.replace RS.logic_by_name u.RT.u_name (List.sort compare ((u.RT.u_span.A.file, h) :: prev))
      | _ -> ())
    g.RT.units;
  (* Phase 5: a specialisation's D17 hash covers [g]'s source, each function
     argument's (a lambda's text, a named function's own logic hash) and the
     template.  Its origin is [g], and [g]'s display name gets a logic hash of
     its own body, so a hot patch of [g] is refused when a proof used one of
     its specialisations (§7.2), and an edit to the lambda moves the hash. *)
  let span_text (sp : A.span) =
    match file_text sp.A.file with
    | None -> ""
    | Some text ->
      let offset (line, col) =
        let rec go i l = if l >= line then Some i else match String.index_from_opt text i '\n' with Some j -> go (j + 1) (l + 1) | None -> None in
        Option.map (fun i -> i + col) (go 0 1)
      in
      (match offset (sp.A.start_line, sp.A.start_col), offset (sp.A.end_line, sp.A.end_col) with
       | Some a, Some b when a >= 0 && b >= a && b <= String.length text -> String.sub text a (b - a)
       | _ -> "")
  in
  Hashtbl.iter
    (fun sym ((ss : spec_site), _) ->
      let gu = g.RT.units.(ss.ss_callee) in
      let gsrc = Option.value ~default:"" (source_of gu) in
      let args =
        List.map
          (function
            | i, F_lambda (_, _, lsp) -> Printf.sprintf "arg %d lambda %s" i (span_text lsp)
            | i, F_named (f, _) ->
              let fh = match sym_of.(f) with Some fsym -> Option.value ~default:"-" (Hashtbl.find_opt RS.logic_hash fsym) | None -> "-" in
              Printf.sprintf "arg %d named %s %s" i g.RT.units.(f).RT.u_name fh)
          ss.ss_fn
      in
      let defn =
        match Hashtbl.find_opt templates sym with
        | None -> "uninterpreted"
        | Some tp ->
          String.concat "\000"
            (List.map (fun t -> "pre " ^ Smt.render (canon t)) tp.t_pre
            @ List.map
                (fun (cs, r) ->
                  "case " ^ String.concat " & " (List.map (fun c -> Smt.render (canon c)) cs) ^ " => " ^ Smt.render (canon r))
                tp.t_cases
            @ List.map (fun (t, k) -> "eq " ^ t ^ " " ^ k) tp.t_eqs)
      in
      Hashtbl.replace RS.logic_hash sym
        (March_cas.Blake3.hash_string (String.concat "\000" ([ "march-reflect-spec-v1"; gsrc ] @ args @ [ defn ])));
      Hashtbl.replace RS.sym_origin sym (gu.RT.u_name, gu.RT.u_span.A.file);
      let prev = Option.value ~default:[] (Hashtbl.find_opt RS.logic_by_name gu.RT.u_name) in
      if not (List.mem_assoc gu.RT.u_span.A.file prev) then
        Hashtbl.replace RS.logic_by_name gu.RT.u_name
          (List.sort compare
             ((gu.RT.u_span.A.file, March_cas.Blake3.hash_string ("march-reflect-specialised-v1\000" ^ gsrc)) :: prev)))
    spec_meta;
  (* The contract hash of every unit (review round 1): its head's text up to
     its last clause's body, its attributes, and whether it is reflected
     (with its unfolding guards).  A multi-clause function's earlier bodies
     fall inside the head text: an over-approximation (a re-check too many),
     never a missed one. *)
  let head_of (u : RT.unit_) =
    let sp = u.RT.u_span in
    let stop =
      List.fold_left
        (fun (l, c) (o : RT.owner) ->
          let b = T.span_of_expr o.RT.o_body in
          if (b.A.start_line, b.A.start_col) > (l, c) then (b.A.start_line, b.A.start_col) else (l, c))
        (sp.A.end_line, sp.A.end_col) u.RT.u_clauses
    in
    match file_text sp.A.file with
    | None -> ""
    | Some text ->
      let offset (line, col) =
        let rec go i l = if l >= line then Some i else match String.index_from_opt text i '\n' with Some j -> go (j + 1) (l + 1) | None -> None in
        Option.map (fun i -> i + col) (go 0 1)
      in
      (match offset (sp.A.start_line, sp.A.start_col), offset stop with
       | Some a, Some b when a >= 0 && b >= a && b <= String.length text -> String.sub text a (b - a)
       | _ -> "")
  in
  (* Review round 2: the functions a unit's refinements NAME.  A
     predicate's call (`_ < size()`, `sz(_) > 0`) makes the callee's BODY
     part of the contract.  Names resolve by their last component (same file
     first, else every file): an over-approximation, so a re-check too many,
     never a missed one.  (A refinement type alias, `type Big = {Int | ...}`,
     does not parse, so a head's refinements are all written in it.) *)
  let refs_of (u : RT.unit_) =
    let names = ref [] in
    (* A name the refinement binds is a value, never a function: the unit's
       own parameters (a lemma's `f` in `EnvMsg(f, p)`) and the binders
       (`_`, `v` of `{v : T | ...}`).  Resolved by bare name like a call,
       a stdlib theorem's parameter `f` marked a user's `App.f` (and all
       it reaches) as named by a predicate, so the user function's contract
       hash moved with the set of files loaded (the LSP re-checked a
       dependent that nothing touched). *)
    let params = List.filter_map Fun.id u.RT.u_params in
    let rec ty (t : A.ty) =
      match t with
      | A.TyRefine (b, binder, e) ->
        ty b;
        let bound = "_" :: (match binder with Some n -> [ n.A.txt ] | None -> []) @ params in
        let rec walk (e : A.expr) =
          (match e with
           | A.EVar n when List.mem n.A.txt bound -> ()
           | A.EVar n -> names := n.A.txt :: !names
           | A.EField (_, n, _) -> names := n.A.txt :: !names
           | _ -> ());
          List.iter walk (RE.children e)
        in
        walk e
      | A.TyCon (_, args) | A.TyTuple args -> List.iter ty args
      | A.TyArrow (a, b) | A.TyNatOp (_, a, b) -> ty a; ty b
      | A.TyRecord fs -> List.iter (fun (_, t) -> ty t) fs
      | A.TyLinear (_, t) -> ty t
      | A.TyVar _ | A.TyNat _ | A.TyChan _ -> ()
    in
    List.iter (Option.iter ty) u.RT.u_param_tys;
    Option.iter ty u.RT.u_ret;
    List.sort_uniq compare !names
  in
  let by_bare : (string, int) Hashtbl.t = Hashtbl.create 256 in
  Array.iter (fun (u : RT.unit_) -> Hashtbl.add by_bare (RT.bare u.RT.u_name) u.RT.u_id) g.RT.units;
  let resolve (u : RT.unit_) (name : string) =
    let all = Hashtbl.find_all by_bare (RT.bare name) in
    match List.filter (fun v -> g.RT.units.(v).RT.u_span.A.file = u.RT.u_span.A.file) all with
    | [] -> all
    | same -> same
  in
  let refs = lazy (Array.map refs_of g.RT.units) in
  let pred_edges =
    lazy
      (let r = Lazy.force refs in
       List.concat_map
         (fun (u : RT.unit_) -> List.concat_map (fun n -> List.map (fun v -> (u.RT.u_id, v)) (resolve u n)) r.(u.RT.u_id))
         (Array.to_list g.RT.units))
  in
  (* The units whose whole body is a contract: those a predicate names, and
     everything their bodies reach. *)
  let in_predicate =
    lazy
      (let n = Array.length g.RT.units in
       let mark = Array.make n false in
       let rec go v =
         if not mark.(v) then begin
           mark.(v) <- true;
           List.iter (fun (e : RT.edge) -> go e.RT.e_dst) g.RT.out.(v)
         end
       in
       List.iter (fun (_, v) -> go v) (Lazy.force pred_edges);
       mark)
  in
  let contract = lazy (
    let whole = Lazy.force in_predicate in
    Array.map
      (fun (u : RT.unit_) ->
        let status =
          match sym_of.(u.RT.u_id) with
          | Some sym when Hashtbl.mem RS.logic_hash sym ->
            "reflected" ^ String.concat "" (List.map (fun g -> "\000guard " ^ g) (Option.value ~default:[] (Hashtbl.find_opt guards_of u.RT.u_span)))
          | _ -> "-"
        in
        let text = if whole.(u.RT.u_id) then "body " ^ Option.value ~default:"" (source_of u) else head_of u in
        March_cas.Blake3.hash_string
          (String.concat "\000"
             ([ "march-contract-v2"; text; status ]
             @ List.map (fun a -> "attr " ^ a) u.RT.u_attrs)))
      g.RT.units)
  in
  RS.contract_defs :=
    lazy (let c = Lazy.force contract in
          Array.map (fun (u : RT.unit_) -> (u.RT.u_span.A.file, u.RT.u_name, c.(u.RT.u_id))) g.RT.units);
  RS.contract_edges :=
    lazy
      (List.sort_uniq compare
         (List.map (fun (e : RT.edge) -> (e.RT.e_src, e.RT.e_dst)) g.RT.edges @ Lazy.force pred_edges));
  RS.unfold_hook := unfold;
  March_refine.Refine.well_formed := declared_logic_symbols;
  RS.active := true;
  if (not !debug_registered) && Sys.getenv_opt "MARCH_REFLECT_DEBUG" = Some "1" then begin
    debug_registered := true;
    at_exit (fun () ->
        Printf.eprintf "reflect-debug: stage2_runs=%d stage2_queries=%d stage2_unknown_hits=%d\n%!"
          !RS.stage2_runs !March_refine.Refine.stage2_queries !March_refine.Refine.stage2_unknown_hits)
  end
