(** Test-build interception of capability operations (ocap phase 7).

    In a test build ([--test], [march test]'s compiled runs, [forge test]),
    every call of an interceptable IO builtin is routed to its generated
    dispatch wrapper ([Io_ops_gen.dispatch_wrapper], injected by the driver
    as March source).  The wrapper asks the current authority for the
    innermost [mock] covering the operation and calls its handler, or runs the
    operation itself.

    The mock is a layer of the current authority, so nothing has to be
    threaded: closures, tasks and actors made inside a [mock] block carry it
    the way they carry any other layer.  This replaces the capability-passing
    pass of the [with_cap] era, which added hidden capability parameters and
    captured them onto actor metadata.

    A release build never runs this pass and never contains the wrappers.

    Runs right after lowering, where a call of a builtin is still an [EApp] of
    its source name.  A builtin used as a value (passed to a higher-order
    function) is not rewritten: its calls are not intercepted. *)

module T = Tir

(** The capability whose mock handler has a field for builtin [name]. *)
let cap_of_interceptable_op : string -> string option =
  let tbl = Hashtbl.create 128 in
  let built = ref false in
  fun name ->
    if not !built then begin
      built := true;
      List.iter
        (fun (op, cap) ->
           if List.mem_assoc op (March_typecheck.Io_ops_gen.dict_fields cap) then
             Hashtbl.replace tbl op cap)
        March_typecheck.Typecheck_builtins.builtin_cap_table
    end;
    Hashtbl.find_opt tbl name

(* ANF: every call is an [EApp] directly under one of these. *)
let rec map_expr (f : T.expr -> T.expr) (e : T.expr) : T.expr =
  let r = map_expr f in
  match f e with
  | T.ELet (v, a, b) -> T.ELet (v, r a, r b)
  | T.ELetRec (fns, b) ->
    T.ELetRec (List.map (fun (fd : T.fn_def) -> { fd with T.fn_body = r fd.T.fn_body }) fns, r b)
  | T.ECase (a, brs, d) ->
    T.ECase (a, List.map (fun (b : T.branch) -> { b with T.br_body = r b.T.br_body }) brs,
             Option.map r d)
  | T.ESeq (a, b) -> T.ESeq (r a, r b)
  | e' -> e'

let rewrite (m : T.tir_module) : T.tir_module =
  let step (e : T.expr) : T.expr =
    match e with
    | T.EApp (v, args) when cap_of_interceptable_op v.T.v_name <> None ->
      T.EApp ({ v with T.v_name = March_typecheck.Io_ops_gen.dispatch_name v.T.v_name }, args)
    | _ -> e
  in
  let fns =
    List.map
      (fun (fd : T.fn_def) ->
         (* A wrapper calls the very operation it wraps. *)
         if March_typecheck.Io_ops_gen.is_dispatch_name fd.T.fn_name then fd
         else { fd with T.fn_body = map_expr step fd.T.fn_body })
      m.T.tm_fns
  in
  { m with T.tm_fns = fns }
