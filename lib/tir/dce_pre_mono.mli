(** Reachability prune before Mono: see the implementation's header and
    specs/2026-11-24-stdlib-compile-floor-design.md. *)

(** [prune ?iface_methods ~extra_roots ~fail_open m] keeps the functions the
    roots reach, in their original order, and returns the names it removed.

    Roots are [Dce.root_names ~fail_open] (main, setup, migrate stubs, exports,
    tests), [extra_roots], [Dce.remote_ref_targets], functions with a no-alloc
    policy and [__rpc_stub] functions.  Edges are every name a body mentions,
    plus [Mono.implicit_callees] of each.  Hand the removed set to
    [Mono.monomorphize ~pruned]. *)
val prune :
  ?iface_methods:(string, (string * string) list) Hashtbl.t ->
  extra_roots:string list ->
  fail_open:bool ->
  Tir.tir_module ->
  Tir.tir_module * (string, unit) Hashtbl.t
