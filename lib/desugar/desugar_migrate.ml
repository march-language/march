(** Hot-reload message migration: the C-ABI wrapper for `<actor>_migrate_msg`.

    Plan: specs/plans/2026-09-21-distributed-authority-and-deploys-plan.md,
    6.3 and II.4.6-II.4.8 (D10).  A user writes

      fn counter_migrate_msg(m : CounterMsgV3) : Option(Counter.Msg) do
        match m do
          Inc(n)      -> Some(Inc(n))
          SetLabel(_) -> None
        end
      end

    and the runtime converts an old-format message the actor dequeues after
    it has moved past a message-type change.  The runtime cannot decode an
    [Option] (its representation depends on the payload's niche safety), so
    this pass generates, right after the user's function,

      fn counter_migrate_msg__hcr(m : CounterMsgV3, none : Counter.Msg)
          : Counter.Msg do
        match counter_migrate_msg(m) do
          Some(n) -> n
          None -> none
        end
      end

    which the runtime calls as [fn(old_msg, sentinel)]: the result is the
    converted message, or the sentinel it passed for [None].  The LLVM emitter
    exports it as [@__migrate_msg_<Actor>] (llvm_toplevel.ml), as it exports
    [<actor>_migrate_state] as [@__migrate_<Actor>].

    Only a function with exactly one annotated parameter and an annotated
    [Option(_)] return type gets a wrapper; the typechecker rejects any other
    shape (Typecheck_caps, the migrate-function checks), so nothing is
    generated for code that will not compile anyway. *)

open March_ast.Ast

let msg_suffix = "_migrate_msg"
let wrapper_suffix = "_migrate_msg__hcr"

let ends_with ~suffix s =
  let n = String.length s and k = String.length suffix in
  n > k && String.sub s (n - k) k = suffix

(** The wrapper for [def], if [def] is a well-shaped `*_migrate_msg`. *)
let wrapper (def : fn_def) (sp : span) : decl option =
  if not (ends_with ~suffix:msg_suffix def.fn_name.txt) then None
  else
    match def.fn_clauses, def.fn_ret_ty with
    | [ { fc_params = [ FPNamed { param_ty = Some old_ty; _ } ]; _ } ],
      Some (TyCon ({ txt = "Option"; _ }, [ new_ty ])) ->
      let n s = { txt = s; span = sp } in
      let v s = EVar (n s) in
      let body =
        EMatch
          ( EApp (v def.fn_name.txt, [ v "m" ], sp),
            [ { branch_pat = PatCon (n "Some", [ PatVar (n "x") ]);
                branch_guard = None; branch_body = v "x" };
              { branch_pat = PatCon (n "None", []);
                branch_guard = None; branch_body = v "none" } ],
            sp )
      in
      let param name ty =
        FPNamed { param_name = n name; param_ty = Some ty; param_lin = Unrestricted } in
      Some
        (DFn
           ( { fn_name = n (def.fn_name.txt ^ "__hcr");
               fn_vis = Public;
               fn_doc = None;
               fn_attrs = [];
               fn_ret_ty = Some new_ty;
               fn_clauses =
                 [ { fc_params = [ param "m" old_ty; param "none" new_ty ];
                     fc_guard = None; fc_body = body; fc_span = sp;
                     fc_params_span = sp } ];
               fn_bounds = [] },
             sp ))
    | _ -> None

(** [decls] with a wrapper after every well-shaped `*_migrate_msg`,
    recursing into nested modules. *)
let rec expand (decls : decl list) : decl list =
  List.concat_map
    (function
      | DFn (def, sp) as d ->
        (match wrapper def sp with
         | Some w -> [ d; Desugar_derive.respan_derived_decl w ]
         | None -> [ d ])
      | DMod (nm, vis, inner, s) -> [ DMod (nm, vis, expand inner, s) ]
      | d -> [ d ])
    decls
