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

(** Diagnostics crash observers (stdlib/diagnostics.march; the compiled
    runtime's twin is march_runtime.c's "Diagnostics: crash observers").
    [diag_observers] in registration order; [diag_ctx] the crash context,
    a March List((String, DiagnosticValue)).  One of each: the interpreter
    runs one handler at a time, and with_context restores the context
    through try_finally before the next one runs. *)
let diag_observers : (int * value) list ref = ref []
let diag_next_id : int ref = ref 1
let diag_ctx : value ref = ref (VCon ("Nil", []))
let diag_dispatching : bool ref = ref false

(** The message and context of the last error raised while an observer was
    registered.  A crash reaches its boundary (the actor loop, the top
    level) only after every try_finally on the way out has run, which has
    restored the context of each with_context it left; this keeps the
    context that was in force where the error was raised, as the compiled
    runtime reports it. *)
let diag_raise_ctx : (string * value) option ref = ref None

let eval_error fmt =
  Printf.ksprintf (fun s ->
      if !diag_observers <> [] then diag_raise_ctx := Some (s, !diag_ctx);
      raise (Eval_error s)) fmt

(** Flag set when graceful shutdown has been requested (SIGTERM, App.stop). *)
let shutdown_requested : bool ref = ref false

(** How many loops that poll [shutdown_requested] are running (the actor
    scheduler drain, the HTTP event loop, an app's lifecycle).  An unwatched
    SIGTERM/SIGINT arriving while none is running has nobody to act on the
    flag, so the signal handler exits instead (see [Eval.handle_os_signal]). *)
let shutdown_consumers : int ref = ref 0

let with_shutdown_consumer (f : unit -> 'a) : 'a =
  incr shutdown_consumers;
  Fun.protect ~finally:(fun () -> decr shutdown_consumers) f

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

(** Take a mark of the March call stack (Eval.march_stack, which lives
    above this module); calling the result restores the stack to it.  Set
    by eval.ml. *)
let march_stack_mark : (unit -> (unit -> unit)) ref =
  ref (fun () -> fun () -> ())

(** Call every crash observer registered now, in registration order, with a
    Diagnostics.DiagCrash.  An observer's exception is swallowed, and an
    observer's own crash is never reported. *)
let diag_dispatch ~(kind : int) ~(msg : string) ~(frames : value)
    ~(pid : int) ~(supervised : bool) ~(ctx : value) : unit =
  if !diag_observers <> [] && not !diag_dispatching then begin
    let report =
      VCon ("DiagCrash",
            [VInt kind; VString msg; frames; VInt pid;
             VInt (if supervised then 1 else 0); ctx]) in
    let snapshot = !diag_observers in
    diag_dispatching := true;
    Fun.protect ~finally:(fun () -> diag_dispatching := false) (fun () ->
        List.iter (fun (_, cb) ->
            try ignore (!apply_hook cb [report]) with _ -> ()) snapshot)
  end
