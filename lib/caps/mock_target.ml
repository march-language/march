(** The target an interceptable capability operation names (ocap phase 7),
    in terms of its arguments: what the stdlib entry point that performs it
    passes to [Authority.check], so a scoped [mock] covers exactly the
    operations its scope admits.  One table for the test build's generated
    dispatch wrappers ([Io_ops_gen.dispatch_wrapper]) and the interpreter's
    interception ([Eval.mock_call]). *)

type t =
  | Lit of string          (** a fixed target; [""] names nothing *)
  | Arg of int             (** the [n]th argument, a [String] *)
  | Int_arg of int         (** the [n]th argument, an [Int], in decimal *)
  | Host_port of int * int (** ["<arg i>:<arg j>"], a host and an [Int] port *)

(** [of_op cap op]: the target of builtin [op] of capability [cap].  [Lit ""]
    for an operation that names nothing: a scoped mock of its kind does not
    cover it, an unscoped one does. *)
let of_op (cap : string) (op : string) : t =
  match cap, op with
  | "IO.Console", ("print" | "print_line") -> Lit "stdout"
  | "IO.Console", "print_stderr" -> Lit "stderr"
  | "IO.Console", _ -> Lit "stdin"
  | ("IO.FileRead" | "IO.FileWrite" | "IO.FileSystem"), _ -> Arg 0
  | "IO.NetConnect", ("tcp_connect" | "tcp_connect_timeout" | "udp_open" | "udp_resolve") ->
    Host_port (0, 1)
  | "IO.NetListen", "tcp_listen" -> Int_arg 0
  | "IO.Network", "dns_resolve" -> Arg 0
  | "IO.Process", ("process_env" | "process_set_env" | "process_spawn_async"
                  | "process_spawn_lines" | "process_spawn_sync") -> Arg 0
  | "IO.Registry", "actor_unregister" -> Arg 0
  | _ -> Lit ""

(** March source computing [t] over parameters named [a0], [a1], .... *)
let to_source (t : t) : string =
  match t with
  | Lit s -> Printf.sprintf "%S" s
  | Arg i -> Printf.sprintf "a%d" i
  | Int_arg i -> Printf.sprintf "int_to_string(a%d)" i
  | Host_port (i, j) -> Printf.sprintf "a%d ++ \":\" ++ int_to_string(a%d)" i j
