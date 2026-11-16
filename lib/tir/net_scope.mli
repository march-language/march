(** Host scopes on [IO.NetConnect], checked on post-lowering TIR.

    specs/2026-11-09-host-scoped-network-capabilities-design.md §4–§5.

    Runs right after lowering, where function names are still source names
    (module prefixes intact, nothing monomorphised or lifted) and a call's
    arguments are still the literals or variables the program wrote. A module
    with host scopes ({!March_caps.Host_scope.decl}) may reach the network
    only at calls whose destination host the compiler can see and its scope
    admits; everything else is refused (fail closed). Modules without host
    scopes are not checked.

    Callbacks are charged to whoever supplies them, as in {!Cap_attrib}: a call
    through a parameter or local is not an edge, and a lambda belongs to the
    function it is written in. *)

type violation = {
  code : string;  (** [cap_host_scope], [cap_host_unproven] or [cap_host_annotation] *)
  owner : string;  (** the module the offending code belongs to *)
  fn_name : string;  (** the TIR function containing it *)
  message : string;
}

val check :
  scopes:(string * March_caps.Host_scope.decl list) list ->
  transparent:(string -> bool) ->
  transparent_fns:(string -> bool) ->
  annotated:(string * int) list ->
  Tir.tir_module ->
  violation list
(** [scopes] maps a module (as {!Cap_attrib.owner_of} names it) to its host
    scopes; [[]] or absent means not scoped. [transparent] / [transparent_fns]
    name the stdlib, as for {!Cap_attrib.attribute}. [annotated] maps a TIR
    function name to the index of its [@[net_dest(p)]] parameter. *)

val rewrite :
  scopes:(string * March_caps.Host_scope.decl list) list ->
  Tir.tir_module ->
  Tir.tir_module
(** In a host-scoped module, a call to a redirect-capable [HttpClient] entry
    point ({!March_caps.Net_dest.redirect_capable}) becomes a call to its
    private [<name>_scoped] twin with the module's encoded scope appended
    ({!March_caps.Host_scope.encode_spec}), so the stdlib can refuse a
    redirect or a step-rewritten host outside it. Other modules are
    untouched. *)

val describe : violation -> string
