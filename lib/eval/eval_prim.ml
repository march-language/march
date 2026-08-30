(** Bottom layer of the interpreter: the evaluation-error exception and the
    late-bound hook refs through which extracted modules re-enter the
    evaluator.

    Everything in lib/eval may depend on this module; it depends on nothing
    in lib/eval except [Eval_types].  That is the whole point — without it,
    [Eval_builtins]/[Eval_net]/[Eval_session] would need [Eval.eval_error]
    while [Eval] needs their exports: a cycle.

    The hook refs keep their placeholder initializers; [Eval] installs the
    real functions at startup exactly as before. *)

open March_ast.Ast
open Eval_types

exception Eval_error of string

let eval_error fmt = Printf.ksprintf (fun s -> raise (Eval_error s)) fmt

(** Flag set when graceful shutdown has been requested (SIGTERM, App.stop). *)
let shutdown_requested : bool ref = ref false

(* Hook refs — copied verbatim from eval.ml, including their placeholder
   bodies and the comments explaining who installs them. *)

(** Platform hook for HTTP client requests.  Native builds leave this [None]
    and use the socket transport (tcp_connect/tcp_send_all/...).  The
    js_of_ocaml browser build sets it to a synchronous-XHR implementation.
    Given (method, url, header_block, body) it returns [Ok raw_response] — a
    synthesized raw "HTTP/1.1 ..." response string for [http_parse_response] —
    or [Error msg] on a network/CORS failure. *)
let http_fetch_hook
  : (string -> string -> string -> string -> (string, string) result) option ref
  = ref None

(** Effect guard for compile-time witness validation
    (lib/refinecheck/witness.ml).  When set, called with the builtin's name
    before every [VBuiltin] application; the guard raises [Blocked_builtin]
    to veto effectful builtins while a counterexample candidate is being
    executed.  [None] — the normal state — costs one ref read per builtin
    call. *)
exception Blocked_builtin of string

let builtin_guard : (string -> unit) option ref = ref None

(** Forward-reference hook for dispatch in comparison operators.
    Interface dispatch needs [apply] but [cmp_op] is defined before [apply].
    Set to the real [apply] after it is defined (see [apply_hook] pattern). *)
let iface_dispatch_hook : (value -> value list -> value) ref =
  ref (fun _fn _args -> eval_error "iface_dispatch not yet initialized")

(** Forward reference for evaluating an expression — set after [eval_expr]
    is defined so that [crash_actor] can call it for supervisor restarts. *)
let eval_expr_hook : (env -> expr -> value) ref =
  ref (fun _env _expr -> eval_error "eval_expr not yet initialized")

(** Forward reference for running the scheduler — set after [run_scheduler]
    is defined so that [base_env] builtins can call it. *)
let run_scheduler_hook : (unit -> unit) ref =
  ref (fun () -> eval_error "run_scheduler not yet initialized")

(** Forward reference for [apply] — set after [apply] is defined
    so that [register_resource_ocaml] can call closures at crash time. *)
let apply_hook : (value -> value list -> value) ref =
  ref (fun _fn _args -> eval_error "apply not yet initialized")
