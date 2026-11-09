(** Where a network operation's destination comes from.

    Host scopes (specs/2026-11-09-host-scoped-network-capabilities-design.md)
    are checked at every network boundary call from a host-scoped module, and
    the check needs to know, per callee, which argument names the host. This
    is that table for builtins; stdlib and user functions say it with
    [@[net_dest(param)]]. *)

type dest =
  | Url of int  (** argument [i] is a full [http://] / [https://] URL *)
  | Host of int * int option  (** argument [i] is a host name, [j] (if any) the port *)
  | Handle
      (** acts on a connection opened elsewhere (an integer fd). The host is
          not knowable here, so a scoped module may not call it. *)
  | Inbound  (** server side: a connection someone made to you; not scoped *)
  | Neutral  (** contacts no host: context setup, local bind, a DNS lookup *)
  | Unknown  (** an address in a form the compiler does not read *)

val builtin_dest : string -> dest option
(** [None] for a name that is not a network builtin. Every builtin whose
    [builtin_cap_table] capability is [IO.NetConnect] or a descendant, or
    [IO.WebSocket], has a row ([test/test_host_scope.ml] enforces it). *)

val is_network_cap : string -> bool
(** [IO.NetConnect] and every capability under it. *)

val redirect_capable : string -> bool
(** The [HttpClient] entry points that follow redirects or run request
    steps, and so have a private [<name>_scoped] twin taking the caller's
    scope (the run-time guard). Qualified TIR names: ["HttpClient.get"]. *)

val net_dest_attr : string list -> string option
(** The parameter named by a [@[net_dest(p)]] attribute in a function's
    [fn_attrs] (stored as ["net_dest:p"]). *)

val method_of : string -> string option
(** The fixed HTTP method (lowercase) of a URL entry point, for method
    scopes: [HttpClient.post] is ["post"]. [None] when the method is decided
    at run time ([HttpClient.with_connection]) or the name is not an entry
    point; the run-time guard checks those. *)
