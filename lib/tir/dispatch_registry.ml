(** Cross-pass channel carrying collision-conditional interface-dispatch rows
    from [Mono] (which resolves each colliding impl to its EXACT specialized
    symbol name — e.g. "Speak$NA.Thing.speak$Thing", including the
    [enqueue_specialized_impl] suffix that a bare-name reconstruction could
    not recover) to [Llvm_dispatch] (which generates the runtime tag-switch
    function that reads those symbols).

    Why a global side-table rather than reconstruction in llvm_emit: the
    emitted impl symbol depends on Mono's per-call-site specialization suffix,
    which is only known during monomorphization. And why not a new
    [tir_module] field: the rows are consumed lazily at LLVM-emission time
    (mirroring [Llvm_eq.ensure_adt_eq_fn], called on demand from
    [llvm_emit.ml]), never re-serialized between passes, so a module field
    would only add threading noise to every intervening pass.

    Keyed by the sentinel callee name Mono rewrites a colliding call to
    ([__march_ifdispatch$<Iface>$<method>$<Short>]); the value is the list of
    [(declaring_module_qualified_type_name, specialized_impl_symbol)] rows.
    Populated only when a short type name is declared by >=2 modules, so a
    program with no collisions leaves this table empty and every consumer's
    "member of this table" gate is a cheap miss — the byte-identity invariant.

    [reset] is called at the start of each [Mono.monomorphize] so state never
    leaks across compilations (REPL / test driver reuse the process). *)

let table : (string, (string * string) list) Hashtbl.t = Hashtbl.create 8

let reset () = Hashtbl.clear table

let register (sentinel : string) (rows : (string * string) list) : unit =
  Hashtbl.replace table sentinel rows

let lookup (sentinel : string) : (string * string) list option =
  Hashtbl.find_opt table sentinel

let mem (sentinel : string) : bool = Hashtbl.mem table sentinel

(** The prefix Mono stamps on every dispatch sentinel; [llvm_emit]'s
    intercept guard and [dce]'s reachability seeding both match on it. *)
let sentinel_prefix = "__march_ifdispatch$"

let is_sentinel (name : string) : bool =
  String.length name >= String.length sentinel_prefix
  && String.sub name 0 (String.length sentinel_prefix) = sentinel_prefix
