(** Hot-reload M10: the live-data check for a state migration.

    Design: specs/2026-11-04-lemmas-hcr-actors-choreography-design.md, §3.3
    item 3.  A `migrate_state` is pure, so before ACTIVATE the reload server
    can run the NEW build's migration on a copy of every live actor's state
    and evaluate the new state's contract on the result.  That turns an
    obligation the prover could not decide into one checked on every input
    that will actually run.

    For an actor [Tally] with a state contract (field refinements and/or an
    [@invariant]) and a `tally_migrate_state(old : T) : S`, a `--hot-reload`
    build gets, right after the migration,

      fn tally_migrate_state__check(old : T) : String do
        let migrate_check_state__ = tally_migrate_state(old)
        if <conjunct 1 over migrate_check_state__> do
          ...
            "?<conjuncts the check cannot evaluate>"   -- or "" when none
          ...
        else "!<conjunct 1, as written>" end
      end

    exported as [@__migrate_check_<Actor>] (llvm_toplevel.ml).  The result is
    the verdict: [""] every conjunct holds; ["!p"] conjunct [p] fails;
    ["?p; q"] the evaluable conjuncts hold and [p], [q] were not evaluated.

    A conjunct is evaluated only when it stays inside the grammar the HCR
    schema records (literals, field names, field access, the arithmetic,
    comparison and boolean operators, [not], [negate]) and every function it
    calls is declared beside the actor: anything else could fail to compile,
    and a check must never break the build it checks.  Such a conjunct is
    named in the ["?"] verdict, never dropped silently.

    Generated only when [enabled] (the driver sets it for `--hot-reload`):
    a plain build, `--check` and the editor see no extra function. *)

open March_ast.Ast

let enabled = ref false

let state_suffix = "_migrate_state"
let check_suffix = "_migrate_state__check"
let state_var = "migrate_check_state__"

let ends_with ~suffix s =
  let n = String.length s and k = String.length suffix in
  n > k && String.sub s (n - k) k = suffix

let binops =
  [ "&&"; "||"; "+"; "-"; "*"; "/"; "%"; "=="; "!="; "<"; ">"; "<="; ">=" ]

(* [p] with every field name read off the migrated state. *)
let rec subst ~fields (e : expr) : expr =
  match e with
  | EVar v when List.mem v.txt fields ->
    EField (EVar { txt = state_var; span = v.span }, v, v.span)
  | EField (b, f, sp) -> EField (subst ~fields b, f, sp)
  | EApp (f, args, sp) -> EApp (f, List.map (subst ~fields) args, sp)
  | e -> e

(* Whether [p] is evaluable: the schema grammar, naming only [vars] and
   calling only [fns].  Anything else might not compile in the generated
   function, and a check must never break the build it checks. *)
let rec evaluable ~fns ~vars (e : expr) : bool =
  match e with
  | ELit ((LitInt _ | LitBool _), _) -> true
  | EVar { txt; _ } -> List.mem txt vars
  | EField (b, _, _) -> evaluable ~fns ~vars b
  | EApp (EVar { txt; _ }, [ l; r ], _) when List.mem txt binops ->
    evaluable ~fns ~vars l && evaluable ~fns ~vars r
  | EApp (EVar { txt = "not" | "negate"; _ }, [ x ], _) -> evaluable ~fns ~vars x
  | EApp (EVar { txt; _ }, [ x ], _) -> List.mem txt fns && evaluable ~fns ~vars x
  | _ -> false

(* [p] as written, for the verdict. *)
let rec text (e : expr) : string =
  match e with
  | ELit (LitInt n, _) -> string_of_int n
  | ELit (LitBool b, _) -> string_of_bool b
  | EVar { txt; _ } -> txt
  | EField (b, f, _) -> text b ^ "." ^ f.txt
  | EApp (EVar { txt; _ }, [ l; r ], _) when List.mem txt binops ->
    text l ^ " " ^ txt ^ " " ^ text r
  | EApp (EVar { txt = "not"; _ }, [ x ], _) -> "!(" ^ text x ^ ")"
  | EApp (EVar { txt = "negate"; _ }, [ x ], _) -> "-" ^ text x
  | EApp (f, xs, _) -> text f ^ "(" ^ String.concat ", " (List.map text xs) ^ ")"
  | _ -> "<expression>"

let rec conjuncts (e : expr) : expr list =
  match e with
  | EApp (EVar { txt = "&&"; _ }, [ a; b ], _) -> conjuncts a @ conjuncts b
  | e -> [ e ]

let rec refinement (t : ty) : (string option * expr) option =
  match t with
  | TyRefine (_, b, p) -> Some (Option.map (fun (n : name) -> n.txt) b, p)
  | TyLinear (_, t) -> refinement t
  | _ -> None

(* [c] over the migrated state: the binder (or `_`) is field [fname]. *)
let rec rename_binder ~binder ~fname (e : expr) : expr =
  match e with
  | EVar v when v.txt = binder -> EVar { v with txt = fname }
  | EField (b, f, sp) -> EField (rename_binder ~binder ~fname b, f, sp)
  | EApp (f, args, sp) -> EApp (f, List.map (rename_binder ~binder ~fname) args, sp)
  | e -> e

let check_fn ~(fns : string list) (a : actor_def) (def : fn_def) (sp : span) : decl option =
  match def.fn_clauses with
  | [ { fc_params = [ FPNamed { param_ty = Some old_ty; _ } ]; _ } ] ->
    let field_names = List.map (fun (f : field) -> f.fld_name.txt) a.actor_state in
    let conj =
      List.concat_map
        (fun (f : field) ->
          match refinement f.fld_ty with
          | None -> []
          | Some (b, p) ->
            let binder = Option.value ~default:"_" b in
            List.map
              (fun c ->
                (f.fld_name.txt ^ ": " ^ text c,
                 rename_binder ~binder ~fname:f.fld_name.txt c))
              (conjuncts p))
        a.actor_state
      @ (match a.actor_invariant with
         | None -> []
         | Some p -> List.map (fun c -> ("@invariant: " ^ text c, c)) (conjuncts p))
    in
    if conj = [] then None
    else
      let n s = { txt = s; span = sp } in
      let str s = ELit (LitString s, sp) in
      let checked, skipped =
        List.partition (fun (_, c) -> evaluable ~fns ~vars:field_names c) conj in
      let ok = str (if skipped = [] then "" else "?" ^ String.concat "; " (List.map fst skipped)) in
      let body =
        List.fold_right
          (fun (label, c) rest ->
            EIf (subst ~fields:field_names c, rest, str ("!" ^ label), sp))
          checked ok
      in
      let body =
        EBlock
          ( [ ELet
                ( { bind_pat = PatVar (n state_var); bind_ty = None; bind_lin = Unrestricted;
                    bind_expr = EApp (EVar def.fn_name, [ EVar (n "old") ], sp) },
                  sp );
              body ],
            sp )
      in
      Some
        (DFn
           ( { fn_name = n (String.sub def.fn_name.txt 0
                              (String.length def.fn_name.txt - String.length state_suffix)
                            ^ check_suffix);
               fn_vis = Public; fn_doc = None; fn_attrs = [];
               fn_ret_ty = Some (TyCon (n "String", []));
               fn_clauses =
                 [ { fc_params =
                       [ FPNamed { param_name = n "old"; param_ty = Some old_ty;
                                   param_lin = Unrestricted } ];
                     fc_guard = None; fc_body = body; fc_span = sp; fc_params_span = sp } ];
               fn_bounds = []; fn_attr_args = []; fn_needs = None },
             sp ))
  | _ -> None

(* [c] with each handler parameter renamed to its position ([p0], [p1],
   ...), the refinement binder (or `_`) to [own]. *)
let rec rename_params env (e : expr) : expr =
  match e with
  | EVar v -> (match List.assoc_opt v.txt env with Some n -> EVar { v with txt = n } | None -> e)
  | EField (b, f, sp) -> EField (rename_params env b, f, sp)
  | EApp (f, args, sp) -> EApp (f, List.map (rename_params env) args, sp)
  | e -> e

let guard_suffix = "_migrate_msg__guard"
let msg_wrapper_suffix = "_migrate_msg__hcr"

(* [fn <actor>_migrate_msg__guard(x : <new msg type>) : Bool]: whether [x]
   meets its handler's evaluable parameter conjuncts.  A function of its own,
   not a match nested in the wrapper's [Some] arm: that shape, with the
   qualified [<Actor>.<Msg>] pattern, miscompiles (todo
   specs/todos/2026-11-05-nested-match-qualified-actor-msg-pattern-miscompile.md). *)
let guard_fn ~fns ~(actor : string) ~(name : string) (a : actor_def) (msg_ty : ty) (sp : span)
  : decl option =
  let n s = { txt = s; span = sp } in
  let arms =
    List.filter_map
      (fun (h : actor_handler) ->
        let pos = List.mapi (fun i (p : param) -> (p.param_name.txt, Printf.sprintf "p%d" i)) h.ah_params in
        let conj =
          List.concat (List.mapi
            (fun i (p : param) ->
              match Option.bind p.param_ty refinement with
              | None -> []
              | Some (b, pred) ->
                let own = Printf.sprintf "p%d" i in
                let env = (Option.value ~default:"_" b, own) :: pos in
                List.map (rename_params env) (conjuncts pred))
            h.ah_params)
          |> List.filter (evaluable ~fns ~vars:(List.map snd pos))
        in
        match conj with
        | [] -> None
        | c :: cs ->
          let body =
            List.fold_left
              (fun acc c -> EApp (EVar (n "&&"), [ acc; c ], sp)) c cs in
          Some
            { branch_pat = PatCon (n (actor ^ "." ^ h.ah_msg.txt),
                                   List.map (fun (_, v) -> PatVar (n v)) pos);
              branch_guard = None; branch_body = body })
      a.actor_handlers
  in
  if arms = [] then None
  else
    let body =
      EMatch (EVar (n "x"),
              arms @ [ { branch_pat = PatWild sp; branch_guard = None;
                         branch_body = ELit (LitBool true, sp) } ], sp) in
    Some
      (DFn
         ( { fn_name = n name; fn_vis = Private; fn_doc = None; fn_attrs = [];
             fn_ret_ty = Some (TyCon (n "Bool", []));
             fn_clauses =
               [ { fc_params = [ FPNamed { param_name = n "x"; param_ty = Some msg_ty;
                                           param_lin = Unrestricted } ];
                   fc_guard = None; fc_body = body; fc_span = sp; fc_params_span = sp } ];
             fn_bounds = []; fn_attr_args = []; fn_needs = None },
           sp ))

(* The message half of M10: in a `--hot-reload` build, the
   `<actor>_migrate_msg__hcr` wrapper (Desugar_migrate) returns [none], the
   runtime's "dropped", for a converted message that fails the new handler's
   parameter refinements, instead of handing it to a handler whose contract
   it breaks.  Only the evaluable conjuncts are tested (see [evaluable]); a
   handler with none keeps every converted message.  [Some decls]: the
   guard, then the rewritten wrapper. *)
let guard_msg_wrapper ~fns actors (def : fn_def) (sp : span) : decl list option =
  let name = def.fn_name.txt in
  let actor = String.sub name 0 (String.length name - String.length msg_wrapper_suffix) in
  match List.find_opt (fun (lower, _, _) -> lower = actor) actors, def.fn_ret_ty with
  | Some (_, spelled, a), Some msg_ty ->
    let gname = actor ^ guard_suffix in
    (match guard_fn ~fns ~actor:spelled ~name:gname a msg_ty sp with
     | None -> None
     | Some g ->
       let rewrite (c : fn_clause) =
         match c.fc_body with
         | EMatch (scrut,
                   [ ({ branch_pat = PatCon ({ txt = "Some"; _ }, [ PatVar xv ]); _ } as some); nb ],
                   msp) ->
           let x = EVar xv in
           let guarded =
             EIf (EApp (EVar { txt = gname; span = sp }, [ x ], sp), some.branch_body,
                  EVar { txt = "none"; span = sp }, sp) in
           { c with fc_body = EMatch (scrut, [ { some with branch_body = guarded }; nb ], msp) }
         | _ -> c
       in
       let def' = { def with fn_clauses = List.map rewrite def.fn_clauses } in
       Some [ Desugar_derive.respan_derived_decl g;
              Desugar_derive.respan_derived_decl (DFn (def', sp)) ])
  | _ -> None

(** [decls] with a check after every `<actor>_migrate_state` whose actor is
    declared in the same list and has a state contract, recursing into
    nested modules. *)
let rec expand (decls : decl list) : decl list =
  let actors =
    List.filter_map
      (function DActor (_, nm, a, _) -> Some (String.lowercase_ascii nm.txt, a) | _ -> None)
      decls
  in
  let fns = List.filter_map (function DFn (d, _) -> Some d.fn_name.txt | _ -> None) decls in
  let spelled =
    List.filter_map
      (function DActor (_, nm, a, _) -> Some (String.lowercase_ascii nm.txt, nm.txt, a) | _ -> None)
      decls
  in
  List.concat_map
    (function
      | DFn (def, sp) when !enabled && ends_with ~suffix:msg_wrapper_suffix def.fn_name.txt ->
        (match guard_msg_wrapper ~fns spelled def sp with
         | Some ds -> ds
         | None -> [ DFn (def, sp) ])
      | DFn (def, sp) as d when !enabled && ends_with ~suffix:state_suffix def.fn_name.txt ->
        let actor =
          String.sub def.fn_name.txt 0 (String.length def.fn_name.txt - String.length state_suffix)
        in
        (match List.assoc_opt actor actors with
         | None -> [ d ]
         | Some a ->
           (match check_fn ~fns a def sp with
            | Some w -> [ d; Desugar_derive.respan_derived_decl w ]
            | None -> [ d ]))
      | DMod (nm, vis, inner, s) -> [ DMod (nm, vis, expand inner, s) ]
      | d -> [ d ])
    decls
