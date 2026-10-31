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

type verdict = Reflected of string list  (** the unfolding guards (§3.6) *) | Blocked of blocker

type row = { r_name : string; r_span : A.span; r_verdict : verdict; r_top : bool }

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

type bind = { k_var : bool;  (** a value ([false]: a local [fn]) *) k_owner : A.span  (** the unit that bound it *) }

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
  let rec walk ~(owner : A.span) ~(local : bool) (env : bind SM.t) (e : A.expr) : unit =
    let w = walk ~owner ~local env in
    match e with
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
    | A.EAssert (x, sp) -> emit owner 4 "has a runtime `assert`" sp; w x
    | A.EHole (_, sp) -> emit owner 4 "has a typed hole" sp
    | A.EMatch (s, brs, sp) ->
      if inp.nonexhaustive sp then begin
        if List.exists (fun (b : A.branch) -> b.A.branch_guard <> None) brs then
          emit owner 5 "guarded match may not match" sp
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
          | _ -> add 7 (Printf.sprintf "names %s as a value" nm) sp
        end
        else if Hashtbl.mem g.RT.ambiguous sp then
          (* More than one declaration could be meant here (review C-A,
             C-B; third review C1): a body that calls it has no single
             definition, so the function is not reflected. *)
          add 6 (Printf.sprintf "calls %s, a name more than one declaration could denote" nm) sp
        else
          match s.RT.s_target with
          | RT.S_value ->
            add 7
              (if nm = "" then "calls through a function value"
               else Printf.sprintf "calls through the value %s" nm)
              sp
          | RT.S_extern -> add 6 (Printf.sprintf "calls the extern %s" nm) sp
          | RT.S_unresolved -> add 6 (Printf.sprintf "calls %s, which the checker cannot resolve" nm) sp
          | RT.S_unit v when is_len_unit v -> ()
          | RT.S_unit v when ident <> None && (is_effect nm || List.mem nm fail_builtins) -> ignore v
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
    (* R2 *)
    if RT.is_recursive g u.RT.u_id then begin
      match cert_of u with
      | "structural" | "metric" -> ()
      | c -> add 2 c sp
    end
    else if RT.is_diverges u then add 2 "diverges" sp;
    (* R7: a function-typed parameter *)
    List.iteri
      (fun i p ->
        let nm = match p with Some s -> s | None -> Printf.sprintf "#%d" (i + 1) in
        match param_ty u i with
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
              | A.EApp (A.EVar f, _, _) when !bad = None && not (inp.pred_fn f.A.txt) -> bad := Some f.A.txt
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
  let dep_ok (d, _) =
    match d with `Refl v -> refl.(v) | `Eq ids -> List.for_all (fun i -> eqok.(i)) ids
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
  Array.to_list g.RT.units
  |> List.filter_map (fun (u : RT.unit_) ->
         match (u.RT.u_kind, origin_of u) with
         | RT.Handler, _ | _, O_let | _, O_default -> None
         | _ ->
           let v =
             match reason u.RT.u_id with
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
type template = { t_cases : (Smt.term list * Smt.term) list; t_pre : Smt.term list; t_name : string }

let templates : (string, template) Hashtbl.t = Hashtbl.create 64

let param_const i = Printf.sprintf "$rp%d" i

(* Every immediate subterm rebuilt through [f]. *)
let map_term (f : Smt.term -> Smt.term) (t : Smt.term) : Smt.term =
  let open Smt in
  match t with
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

(* §3.6 + §3.7: one unfolding per reflected call of the query (the goal, then
   the assumptions in order: the depth-0 frontier).  Each call's guarded
   equations are asserted behind one assumption literal, which names the
   function in the unsat core (the [uses:] note). *)
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
  let lits = ref [] and facts = ref [] in
  List.iteri
    (fun k (f, args) ->
      let tp = Hashtbl.find templates f in
      let env = List.mapi (fun i a -> (param_const i, a)) args in
      let pre = if perturb = Some "no-guard" then [] else List.map (subst env) tp.t_pre in
      let lhs = Smt.App (f, args) in
      let eqs =
        List.map
          (fun (conds, res) ->
            let res = subst env res and conds = List.map (subst env) conds in
            (* A call the unfolding PRODUCES is not unfolded again (D12). *)
            List.iter
              (fun (g, gargs) ->
                if not (List.mem (g, gargs) frontier) then begin
                  RS.fuel_pending := true;
                  if !RS.fuel_fn = "" then RS.fuel_fn := (Hashtbl.find templates g).t_name
                end)
              (List.fold_left reflected_apps [] (res :: conds));
            let g = pre @ conds in
            let eq = Smt.Eq (lhs, res) in
            if g = [] then eq else Smt.Implies (conj g, eq))
          tp.t_cases
      in
      let lit = Printf.sprintf "|%s%d:%s|" RS.literal_prefix k tp.t_name in
      Hashtbl.replace RS.literal_owner lit tp.t_name;
      lits := (lit, Smt.SBool) :: !lits;
      (* Test-only perturbation (the I7 control): every unfolding asserts
         [false], so stage 2 proves anything it is asked. *)
      let body = if !perturb_false then Smt.BoolLit false else conj eqs in
      facts := Smt.Implies (Smt.Const lit, body) :: !facts)
    frontier;
  (decls @ List.rev !lits, assumptions @ List.rev !facts)

(* ── Sorts of a signature (§3.2, §3.3) ──────────────────────────────────── *)

(* The one datatype a constructor NAME belongs to, or [Decline] when two
   registered datatypes declare it (review audit): the SMT constructor,
   tester and selectors are keyed by that name, so an ambiguous one could be
   read at the wrong datatype.  Never guess. *)
let unique_ctor_adt (c : string) : string =
  match Hashtbl.fold (fun adt cs acc -> if List.mem c cs then adt :: acc else acc) RE.adt_ctors [] with
  | [ adt ] -> adt
  | _ -> raise Decline

let poly_sort (vars : (int * int) list ref) (t : T.ty) : Smt.sort =
  let short n = match String.rindex_opt n '.' with Some i -> String.sub n (i + 1) (String.length n - i - 1) | None -> n in
  let rec go (t : T.ty) =
    match T.repr t with
    | T.TCon ("Int", []) -> Smt.SInt
    | T.TCon ("Bool", []) -> Smt.SBool
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
      (match Hashtbl.find_opt RE.adt_decl_paths ("M_" ^ short n) with
       | Some (_ :: _ :: _) -> raise Decline
       | _ -> ());
      let adt = RE.adt_sort_name (short n) in
      (match Hashtbl.find_opt RE.adt_ctors adt with
       | Some [ ctor ] when Hashtbl.mem RE.ctor_field_names ctor -> raise Decline (* a record *)
       | Some _ ->
         let k = try Hashtbl.find RE.adt_arity adt with Not_found -> 0 in
         if k = 0 then Smt.sdata adt
         else if List.length args <> k then raise Decline
         else Smt.SData (adt, List.map go args)
       | None -> raise Decline)
    | _ -> raise Decline
  in
  go t

(* ── The body translator (§3.4) ─────────────────────────────────────────── *)

type tctx = {
  c_sites : (A.span, RT.site) Hashtbl.t;
  c_sym_of_unit : int -> string option;
  c_ty : A.span -> T.ty option;
  c_len_unit : int -> bool;
  c_eq_structural : T.ty -> bool;  (** program [==] at this type is SMT [=] (§3.5) *)
  c_unit : RT.unit_ array;
  c_ambiguous : A.span -> bool;  (** [Refine_term.graph.ambiguous] *)
}

let is_int_ty = function Some t -> (match T.repr t with T.TCon ("Int", []) -> true | _ -> false) | None -> false

let rec tr_val (c : tctx) (env : (string * Smt.term) list) (e : A.expr) : Smt.term =
  let v = tr_val c env in
  match e with
  | A.ELit (A.LitInt n, _) -> Smt.IntLit n
  | A.ELit (A.LitBool b, _) -> Smt.BoolLit b
  | A.EVar x -> ( match List.assoc_opt x.A.txt env with Some t -> t | None -> raise Decline)
  | A.EAnnot (x, _, _) -> v x
  | A.EBlock ([ x ], _) -> v x
  | A.EBlock (_ :: _, _) | A.EMatch _ -> (
    match tr_case c env e with
    | [ ([], t) ] -> t
    | _ -> raise Decline)
  | A.EIf (cnd, a, b, _) -> Smt.Ite (v cnd, v a, v b)
  | A.ECon (ctor, args, _) when Hashtbl.mem RE.ctor_field_sorts ctor.A.txt ->
    let ts = List.map v args in
    RE.ctor_term (unique_ctor_adt ctor.A.txt) ctor.A.txt ts
  | A.EApp (A.EVar f, args, sp) -> (
    (* The same rule as [note] (third review C1): an ambiguous site has no
       single callee, in every branch below. *)
    if c.c_ambiguous sp then raise Decline;
    let site = Hashtbl.find_opt c.c_sites sp in
    let nm = f.A.txt in
    let target = Option.map (fun (s : RT.site) -> s.RT.s_target) site in
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
  | (("/" | "%") as op), [ a; d ] when RE.nonzero_int_literal d <> None ->
    Refine_scope.truncating_division ~op ~nonneg_dividend:false (v a) (`Lit (Option.get (RE.nonzero_int_literal d)))
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
      | Some t when c.c_eq_structural t || perturb = Some "eq-structural" -> Smt.Eq (x, y)
      | Some _ -> Smt.App (RS.eq_sym, [ x; y ])
      | None -> raise Decline
    in
    if op = "==" then eq else Smt.Not eq
  | _ -> raise Decline

(* Tail position: guarded cases, one per path, with NO default (§3.4, C2). *)
and tr_case (c : tctx) (env : (string * Smt.term) list) (e : A.expr) : (Smt.term list * Smt.term) list =
  match e with
  | A.EAnnot (x, _, _) -> tr_case c env x
  | A.EBlock ([ x ], _) -> tr_case c env x
  | A.EBlock (A.ELet (b, _) :: rest, sp) -> (
    match b.A.bind_pat with
    | A.PatVar x -> tr_case c ((x.A.txt, tr_val c env b.A.bind_expr) :: env) (A.EBlock (rest, sp))
    | _ -> raise Decline)
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
    let tupled = match scrut with A.ETuple _ -> true | _ -> false in
    let prior = ref [] in
    List.concat_map
      (fun (br : A.branch) ->
        let conds, binds =
          match tupled, br.A.branch_pat with
          | true, A.PatTuple (ps, _) when List.length ps = List.length subjects ->
            List.fold_left2
              (fun (cs, bs) p s ->
                let c', b' = pat p s in
                (cs @ c', bs @ b'))
              ([], []) ps subjects
          | true, A.PatWild _ -> ([], [])
          | false, p -> pat p (List.hd subjects)
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
and pat (p : A.pattern) (s : Smt.term) : Smt.term list * (string * Smt.term) list =
  match p with
  | A.PatWild _ -> ([], [])
  | A.PatVar x -> ([], [ (x.A.txt, s) ])
  | A.PatAs (q, x, _) ->
    let cs, bs = pat q s in
    (cs, (x.A.txt, s) :: bs)
  | A.PatLit (A.LitInt n, _) -> ([ Smt.Eq (s, Smt.IntLit n) ], [])
  | A.PatLit (A.LitBool b, _) -> ([ (if b then s else Smt.Not s) ], [])
  | A.PatCon (ctor, ps) when Hashtbl.mem RE.ctor_field_sorts ctor.A.txt ->
    ignore (unique_ctor_adt ctor.A.txt);
    let n = List.length (Hashtbl.find RE.ctor_field_sorts ctor.A.txt) in
    if List.length ps <> n then raise Decline;
    let sub =
      List.mapi (fun i q -> pat q (Smt.App (Printf.sprintf "%s_%d" ctor.A.txt i, [ s ]))) ps
    in
    (Smt.IsCtor (ctor.A.txt, s) :: List.concat_map fst sub, List.concat_map snd sub)
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
                     | A.EVar x -> ignore (unique_ctor_adt ctor); Option.map (fun t -> Smt.IsCtor (ctor, t)) (var x.A.txt)
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

let install ~(user_files : string list) ~(type_map : (A.span, T.ty) Hashtbl.t option) (t : RT.t)
    (decls : A.decl list) : unit =
  RS.reset ();
  Hashtbl.reset templates;
  Hashtbl.reset encoder_blocked;
  install_errors := [];
  Hashtbl.reset RS.blocked_by_name;
  let g = t.RT.graph in
  let ne = Hashtbl.create 64 in
  List.iter (fun sp -> Hashtbl.replace ne sp ()) !March_typecheck.Typecheck.last_nonexhaustive_match_spans;
  let inputs =
    { certs = (fun _ -> None);
      nonexhaustive = Hashtbl.mem ne;
      division = (fun _ -> None);
      type_map;
      vocab = (fun s -> s = "len" || List.mem s RE.set_vocabulary || RE.ctor_of_tester s <> None);
      pred_fn = (fun s -> s = "len" || RE.known_predicate_fn s) }
  in
  let rows = analyze inputs t decls in
  let refl_spans = Hashtbl.create 64 in
  List.iter
    (fun r ->
      match r.r_verdict with
      | Reflected _ -> Hashtbl.replace refl_spans r.r_span ()
      | Blocked b ->
        Hashtbl.replace encoder_blocked r.r_span (Printf.sprintf "R%d:%s" b.b_rule b.b_text);
        if not (String.contains r.r_name '/') then Hashtbl.replace RS.blocked_by_name r.r_name (b.b_text, b.b_span))
    rows;
  let ty_at sp = match type_map with Some tm -> Hashtbl.find_opt tm sp | None -> None in
  (* §3.1: the mangled, injective symbol of each reflected unit. *)
  let sym_of = Array.make (Array.length g.RT.units) None in
  let owners : (string, int) Hashtbl.t = Hashtbl.create 64 in
  let dup = ref [] in
  Array.iter
    (fun (u : RT.unit_) ->
      if Hashtbl.mem refl_spans u.RT.u_span then begin
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
      c_eq_structural = structural_ty []; c_unit = g.RT.units; c_ambiguous = Hashtbl.mem g.RT.ambiguous }
  in
  (* Signatures and templates. *)
  let axiom_tier = Hashtbl.create 8 in
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
          if List.mem "measure" u.RT.u_attrs && List.mem (RT.bare u.RT.u_name) !RE.registered_measures then
            Hashtbl.replace axiom_tier sym ();
          (* The body: a failure leaves the symbol uninterpreted, which is
             sound (no equation is asserted), only weaker. *)
          (try
             let names =
               List.mapi
                 (fun i p -> match p with Some n -> (n, Smt.Const (param_const i)) | None -> raise Decline)
                 (match u.RT.u_clauses with [ c ] -> c.RT.o_params | _ -> raise Decline)
             in
             (* Two parameters of one name (`fn two(a, a)`): which one the
                body reads is the binder order's business, not the
                translator's guess.  No definition. *)
             if List.length (List.sort_uniq compare (List.map fst names)) <> List.length names then raise Decline;
             let cases = tr_case ctx names body in
             let pre = pre_of u ptys in
             Hashtbl.replace templates sym { t_cases = cases; t_pre = pre; t_name = u.RT.u_name }
           with Decline | Not_found | Invalid_argument _ | Failure _ -> ())
        with Decline | Not_found | Invalid_argument _ -> ()))
    g.RT.units;
  (* The one resolution rule (review C-1, C-2): a call site denotes a
     reflected function exactly when the termination graph's lexical walk
     resolved THAT site to that unit (program code), or resolved it in the
     scope where the predicate is written (a signature's refinement).  An
     axiom-tier measure is never a frontier call (I10). *)
  let note sp v =
    if Hashtbl.mem g.RT.ambiguous sp then ()
    else
    match sym_of.(v) with
    | Some sym when Hashtbl.mem RS.syms sym && not (Hashtbl.mem axiom_tier sym) ->
      Hashtbl.replace RS.call_sym sp sym
    | _ -> ()
  in
  List.iter
    (fun (s : RT.site) -> match s.RT.s_target with RT.S_unit v when s.RT.s_call -> note s.RT.s_span v | _ -> ())
    g.RT.sites;
  List.iter (fun (sp, tgt) -> match tgt with RT.S_unit v -> note sp v | _ -> ()) g.RT.pred_sites;
  RS.unfold_hook := unfold;
  March_refine.Refine.well_formed := declared_logic_symbols;
  RS.active := true;
  if (not !debug_registered) && Sys.getenv_opt "MARCH_REFLECT_DEBUG" = Some "1" then begin
    debug_registered := true;
    at_exit (fun () ->
        Printf.eprintf "reflect-debug: stage2_runs=%d stage2_queries=%d stage2_unknown_hits=%d\n%!"
          !RS.stage2_runs !March_refine.Refine.stage2_queries !March_refine.Refine.stage2_unknown_hits)
  end
