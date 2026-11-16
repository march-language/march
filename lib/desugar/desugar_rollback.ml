(** Hot-reload H5: the rollback round trip.

    Design: specs/2026-11-04-lemmas-hcr-actors-choreography-design.md, §3.4
    "H5. Round trip for rollback".  A deploy that changes an actor's state
    shape can only be undone by another deploy whose `migrate_state` maps the
    new shape back; the law a user wants of that reverse migration is that
    rolling back loses nothing the old version had.

    The convention: beside `<actor>_migrate_state(old : A) : B`, a build may
    declare `<actor>_rollback_state(new : B) : A`.  When both are declared in
    the same module, this pass adds

      @[lemma]
      fn <actor>_rollback_roundtrip(old : A)
        : {Unit | <actor>_rollback_state(<actor>_migrate_state(old)) == old} do () end

    which the typechecker types like user code, the refinement checker proves
    by unfolding both functions (or refutes with the `old` that breaks it), and
    [Lemma_erase] removes before anything runs.  [A] is `migrate_state`'s own
    parameter type, so an `old` the migration's contract excludes is excluded
    here too.  The rollback deploy itself is unchanged: the reverse build's
    `migrate_state` is this build's `rollback_state`.

    Spans: reflection keys call sites and units by span, so every node gets a
    span of its own, derived from the rollback function's declaration span
    (the lemma's name is that span, which a failure points at). *)

open March_ast.Ast

let migrate_suffix = "_migrate_state"
let rollback_suffix = "_rollback_state"
let roundtrip_suffix = "_rollback_roundtrip"

let strip_suffix ~suffix s =
  let n = String.length s and k = String.length suffix in
  if n > k && String.sub s (n - k) k = suffix then Some (String.sub s 0 (n - k)) else None

(* A distinct span per synthesized node, all inside the rollback function's
   declaration ([sp]): the lemma's name is [sp] itself. *)
let derived (sp : span) (k : int) : span =
  if k = 0 then sp else { sp with end_col = sp.end_col + k }

let first_param_ty (fd : fn_def) : ty option =
  match fd.fn_clauses with
  | { fc_params = (FPNamed p | FPDefault (p, _)) :: _; _ } :: _ -> p.param_ty
  | _ -> None

let roundtrip ~(actor : string) ~(migrate : fn_def) ~(sp : span) : decl =
  let nm k s = { txt = s; span = derived sp k } in
  let old k = EVar (nm k "old") in
  let call k f args = EApp (EVar (nm k f), args, derived sp k) in
  let theorem =
    call 1 "=="
      [ call 2 (actor ^ rollback_suffix) [ call 3 (actor ^ migrate_suffix) [ old 4 ] ]; old 5 ]
  in
  let fd =
    { fn_name = nm 0 (actor ^ roundtrip_suffix); fn_vis = Private; fn_doc = None;
      fn_attrs = [ "lemma" ];
      fn_ret_ty = Some (TyRefine (TyCon (nm 6 "Unit", []), Some (nm 7 "_"), theorem));
      fn_clauses =
        [ { fc_params =
              [ FPNamed { param_name = nm 8 "old"; param_ty = first_param_ty migrate;
                          param_lin = Unrestricted } ];
            fc_guard = None; fc_body = ETuple ([], derived sp 9);
            fc_span = derived sp 10; fc_params_span = derived sp 11 } ];
      fn_bounds = []; fn_attr_args = []; fn_needs = None }
  in
  DFn (fd, sp)

let rec expand (ds : decl list) : decl list =
  let fns =
    List.filter_map (function DFn (fd, sp) -> Some (fd, sp) | _ -> None) ds
  in
  let declared name = List.exists (fun ((fd : fn_def), _) -> fd.fn_name.txt = name) fns in
  let extra =
    List.filter_map
      (fun ((fd : fn_def), sp) ->
        match strip_suffix ~suffix:rollback_suffix fd.fn_name.txt with
        | Some actor when not (declared (actor ^ roundtrip_suffix)) ->
          (match
             List.find_opt (fun ((m : fn_def), _) -> m.fn_name.txt = actor ^ migrate_suffix) fns
           with
           | Some (migrate, _) -> Some (roundtrip ~actor ~migrate ~sp)
           | None -> None)
        | _ -> None)
      fns
  in
  List.map
    (function DMod (n, v, inner, sp) -> DMod (n, v, expand inner, sp) | d -> d)
    ds
  @ extra
