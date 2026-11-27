(** Reachability prune before Mono: see the implementation's header and
    specs/2026-11-24-stdlib-compile-floor-design.md. *)

(** [prune ?iface_methods ~extra_roots ~fail_open m] keeps the functions the
    roots reach, in their original order, and returns the names it removed.

    Roots are [Dce.root_names ~fail_open] (main, setup, migrate stubs, exports,
    tests), [extra_roots], [Dce.remote_ref_targets], functions with a no-alloc
    policy and [__rpc_stub] functions.  Edges are every name a body mentions,
    plus [Mono.implicit_callees] of each.  Hand the removed set to
    [Mono.monomorphize ~pruned].

    Raises [Failure] if it reaches a function [is_unlowered] (a stdlib body
    lazy lowering left as a stub: a root or edge it missed). *)
val prune :
  ?iface_methods:(string, (string * string) list) Hashtbl.t ->
  extra_roots:string list ->
  fail_open:bool ->
  Tir.tir_module ->
  Tir.tir_module * (string, unit) Hashtbl.t

(** [__rpc_stub] functions, which [prune] pins. *)
val is_rpc_stub : string -> bool

(** A function [prune] keeps whatever calls it (an RPC stub, or one with a
    [Tagged] policy parameter).  Lazy lowering's demand walk roots the same
    set, among stubs and eagerly lowered functions alike. *)
val is_pinned : Tir.fn_def -> bool

(** [walk ~iface_methods ~known ~defs ?extra roots]: the worklist [prune]
    runs, shared with lazy lowering so the two agree edge for edge.  From
    [roots], visits each name once; for each definition [defs n] (every one,
    when a name is defined twice) it follows every name the body mentions or
    has free, and [Mono.implicit_callees] of each, to the names [known] holds,
    plus the names [extra] gives for that definition.  Returns the visited
    set (roots included). *)
val walk :
  iface_methods:(string, (string * string) list) Hashtbl.t ->
  known:(string -> bool) ->
  defs:(string -> Tir.fn_def list) ->
  ?extra:(Tir.fn_def -> string list) ->
  string list -> (string, unit) Hashtbl.t

(** [fd]'s body calls [Tir_names.unlowered_marker]: a stdlib fn lazy lowering
    did not lower. *)
val is_unlowered : Tir.fn_def -> bool
