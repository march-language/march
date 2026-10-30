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

(* The [len] spellings that are stdlib functions, matched by the unit they
   resolve to (§2.3: `List.length`, `String.byte_size` are `$len`). *)
let len_units = [ "List.length"; "String.byte_size" ]

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
  let adts b = Hashtbl.mem adt_tbl b in
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
        else
          match s.RT.s_target with
          | RT.S_value ->
            add 7
              (if nm = "" then "calls through a function value"
               else Printf.sprintf "calls through the value %s" nm)
              sp
          | RT.S_extern -> add 6 (Printf.sprintf "calls the extern %s" nm) sp
          | RT.S_unresolved -> add 6 (Printf.sprintf "calls %s, which the checker cannot resolve" nm) sp
          | RT.S_unit v when List.mem (unit_ v).RT.u_name len_units -> ()
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
              | [ _; A.ELit (A.LitInt k, _) ] when k <> 0 -> ()
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
                | _ -> add 6 (Printf.sprintf "calls %s at %s" nm (T.pp_ty ty)) sp)
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
                  let at = match arg_ty s with Some t -> T.pp_ty t | None -> "?" in
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
