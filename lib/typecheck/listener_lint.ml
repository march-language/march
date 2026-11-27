(** A `Listener` closed by its last use, `Socket.local_port` (decision D-a,
    specs/progress/2026-11-26-listener-closed-at-last-use-lint.md).

    In compiled code a handle is released at its last use.  In

    {v
      let l = ... Socket.listen(0) ...
      let port = Socket.local_port(l)
      Socket.connect("127.0.0.1", port)
    v}

    [l] is not mentioned after [local_port], so the listening socket is
    closed before the connect, which is refused.  The interpreter, which has
    no drop glue, keeps it open, so the program works there and not
    compiled.  The release is right (the owner decided against keeping a
    Listener alive to the end of its scope); this warns where it bites.

    Syntactic and block-local: in a block, a `Socket.local_port(x)` call (it
    takes only a Listener, so no type is needed) that is the only mention of
    [x] in its statement, where [x] is bound by an earlier `let` of the same
    block, is not mentioned in any later statement, and is not the block's
    last statement.  Shadowing, aliases (`use Socket`) and a use after the
    block are not followed; it is a warning, not a proof. *)

module Ast = March_ast.Ast
module Err = March_errors.Errors

let local_port_callee (f : Ast.expr) : bool =
  match f with
  | Ast.EVar v -> v.Ast.txt = "Socket.local_port"
  | Ast.EField (Ast.EVar m, fn, _) | Ast.EField (Ast.ECon (m, [], _), fn, _) ->
    m.Ast.txt = "Socket" && fn.Ast.txt = "local_port"
  | _ -> false

(* How many times [e] mentions the variable [x]. *)
let mentions ~iter_expr (x : string) (e : Ast.expr) : int =
  let n = ref 0 in
  iter_expr (fun e -> match e with Ast.EVar v when v.Ast.txt = x -> incr n | _ -> ()) e;
  !n

(* The spans of `Socket.local_port(x)` calls in [e], with their argument. *)
let local_port_calls ~iter_expr (e : Ast.expr) : (string * Ast.span) list =
  let acc = ref [] in
  iter_expr
    (fun e ->
       match e with
       | Ast.EApp (f, [ Ast.EVar x ], sp) when local_port_callee f -> acc := (x.Ast.txt, sp) :: !acc
       | _ -> ())
    e;
  List.rev !acc

let let_bound (e : Ast.expr) : string option =
  match e with
  | Ast.ELet ({ Ast.bind_pat = Ast.PatVar n; _ }, _) -> Some n.Ast.txt
  | _ -> None

let check_block ~iter_expr (errors : Err.ctx) (xs : Ast.expr list) : unit =
  let arr = Array.of_list xs in
  let n = Array.length arr in
  for j = 0 to n - 2 do
    List.iter
      (fun (x, sp) ->
         let bound_before = ref false in
         for k = 0 to j - 1 do
           if let_bound arr.(k) = Some x then bound_before := true
         done;
         let later = ref 0 in
         for m = j + 1 to n - 1 do
           later := !later + mentions ~iter_expr x arr.(m)
         done;
         if !bound_before && !later = 0 && mentions ~iter_expr x arr.(j) = 1 then
           Err.warning errors ~code:March_errors.Code.listener_closed_early ~span:sp
             (Printf.sprintf
                "`%s` is not used after this call, so a compiled program closes the \
                 listener here, before the next line runs: a connection to its port is \
                 refused. (The interpreter keeps it open, so the program behaves \
                 differently there.) Use `%s` again where you are done with it, for \
                 example `Socket.close_listener(%s)`."
                x x x))
      (local_port_calls ~iter_expr arr.(j))
  done

(** Run over a module's declarations, nested modules included. [iter_expr]
    is the typechecker's sub-expression walker; [own_exprs] is
    [Typecheck_caps.module_own_exprs]. *)
let rec check_module ~iter_expr ~(own_exprs : Ast.decl list -> Ast.expr list)
    (errors : Err.ctx) (decls : Ast.decl list) : unit =
  let roots =
    List.filter
      (fun e -> not (Typecheck_builtins.span_is_stdlib (Typecheck_types.span_of_expr e)))
      (own_exprs decls)
  in
  List.iter
    (fun root ->
       iter_expr (fun e -> match e with Ast.EBlock (xs, _) -> check_block ~iter_expr errors xs | _ -> ())
         root)
    roots;
  List.iter (function
      | Ast.DMod (_, _, inner, _) -> check_module ~iter_expr ~own_exprs errors inner
      | _ -> ())
    decls
