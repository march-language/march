(* Two-state specs: where `old(e)` may be written (specs/lang/actors.md,
   "Handler guarantees"; todo 2026-11-06-two-state-specs).

   `old(e)` means [e] of the state a message arrived with, so it has a meaning
   only in a handler's `ensures`, where the refinement checker
   ([Refine_check]'s `DActor` arm) reads it.  This check refuses:

   - `old` in a guarantee written as anything but a call with one argument
     (`old`, `old()`, `old(a, b)`);
   - `old(…)` in any other refinement: an `@invariant`, a state field's
     type, a message parameter's type, or a function's parameter or result
     type.  There is no "before" there for it to mean.

   Ordinary code is left alone: outside a refinement `old` is a name like any
   other, and a program that declares its own function `old` keeps it in
   refinements too.  Inside a guarantee `old(e)` is always the spec form. *)

open March_ast.Ast
module Err = March_errors.Errors

let report errors ~span msg note =
  Err.report errors
    { Err.severity = Err.Error; span; message = msg; labels = []; notes = [ note ];
      code = Err.Code.old_misuse; fix = None }

let is_old (n : name) = n.txt = "old"

(* Every expression directly under [e], in the shapes a predicate is written
   in. *)
let children (e : expr) : expr list =
  match e with
  | EApp (f, args, _) -> f :: args
  | EField (r, _, _) -> [ r ]
  | ETuple (es, _) | ECon (_, es, _) | EBlock (es, _) -> es
  | EAnnot (x, _, _) -> [ x ]
  | EIf (c, t, f, _) -> [ c; t; f ]
  | EPipe (l, r, _) -> [ l; r ]
  | ELam (_, b, _) -> [ b ]
  | _ -> []

let ensures_note =
  "`old(e)` is `e` of the state the message arrived with: write `old(state.balance)`, or \
   `old(state)` for the whole state."

(* In a guarantee: every `old` is `old(x)`. *)
let rec check_ensures errors (e : expr) : unit =
  match e with
  | EApp (EVar o, [ x ], _) when is_old o -> check_ensures errors x
  | EApp (EVar o, args, sp) when is_old o ->
    report errors ~span:sp
      (Printf.sprintf "`old` takes exactly one expression, but this passes %d." (List.length args))
      ensures_note
  | EVar o when is_old o ->
    report errors ~span:o.span "`old` on its own does not name a value." ensures_note
  | _ -> List.iter (check_ensures errors) (children e)

let elsewhere_note =
  "`old(e)` means `e` of the state a message arrived with, so it is only meaningful in a \
   handler's `ensures`: `on Msg(…) ensures state.n >= old(state.n) do … end`."

(* Outside a guarantee: no `old(…)` in a refinement. *)
let rec check_pred errors ~where (e : expr) : unit =
  match e with
  | EApp (EVar o, _, sp) when is_old o ->
    report errors ~span:sp (Printf.sprintf "`old(…)` cannot be used in %s." where) elsewhere_note
  | _ -> List.iter (check_pred errors ~where) (children e)

let rec check_ty errors ~where (t : ty) : unit =
  match t with
  | TyRefine (b, _, p) -> check_ty errors ~where b; check_pred errors ~where p
  | TyCon (_, ts) | TyTuple ts -> List.iter (check_ty errors ~where) ts
  | TyArrow (a, b) -> check_ty errors ~where a; check_ty errors ~where b
  | TyRecord fs -> List.iter (fun (_, t) -> check_ty errors ~where t) fs
  | TyLinear (_, t) -> check_ty errors ~where t
  | TyVar _ | TyNat _ | TyNatOp _ | TyChan _ -> ()

let param_ty errors ~where (p : param) = Option.iter (check_ty errors ~where) p.param_ty

let fn_sig errors (fd : fn_def) =
  let where = "a function's type" in
  Option.iter (check_ty errors ~where) fd.fn_ret_ty;
  List.iter
    (fun c ->
      List.iter
        (function FPNamed p | FPDefault (p, _) -> param_ty errors ~where p | FPPat _ -> ())
        c.fc_params)
    fd.fn_clauses

(* A function named `old` anywhere in the program: then `old(…)` in a
   refinement outside a guarantee is a call of it, not a slip. *)
let rec declares_old (decls : decl list) : bool =
  List.exists
    (function
      | DFn (fd, _) -> is_old fd.fn_name
      | DMod (_, _, inner, _) -> declares_old inner
      | _ -> false)
    decls

let check errors (decls : decl list) : unit =
  let own_old = declares_old decls in
  let rec go decls =
    List.iter
      (function
        | DActor (_, _, a, _) ->
          List.iter (fun h -> Option.iter (check_ensures errors) h.ah_ensures) a.actor_handlers;
          if not own_old then begin
            Option.iter (check_pred errors ~where:"an `@invariant`") a.actor_invariant;
            List.iter (fun f -> check_ty errors ~where:"a state field's type" f.fld_ty) a.actor_state;
            List.iter
              (fun h -> List.iter (param_ty errors ~where:"a message parameter's type") h.ah_params)
              a.actor_handlers
          end
        | DFn (fd, _) -> if not own_old then fn_sig errors fd
        | DMod (_, _, inner, _) -> go inner
        | _ -> ())
      decls
  in
  go decls
