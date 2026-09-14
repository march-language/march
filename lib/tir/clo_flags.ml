(** Cross-pass channel carrying each function's per-parameter borrow modes
    from [Perceus] (which owns the converged [Borrow.borrow_map]) to
    [Llvm_emit], for the one kind of closure callee Perceus never sees: the
    [$clo_wrap] trampoline that lets a named top-level function (or builtin)
    be called through a closure.

    ── The closure-call convention ─────────────────────────────────────────

    A closure call CONSUMES every heap argument except a boxed Float.  All
    callers agree on that: Perceus's [ECallPtr] case transfers each argument
    (dup'ing one that is live after the call), and the C runtime's
    higher-order helpers ([runtime/march_runtime.c]'s map/fold helpers,
    [march_vault_update], [march_call]) give the callee a reference for any
    value they keep.  The callee side is:

    - a lifted lambda's apply fn: [Borrow.infer_module] pins every apply-fn
      parameter owned, so RC insertion releases each one at its last use (or
      at entry, when unused — [Perceus.insert_dead_apply_param_drops]);
    - a [$clo_wrap]: forwards to a target whose own parameters may be
      BORROWED.  The trampoline releases those after the call, using the modes
      registered here.

    A Float parameter crosses the closure ABI as a fresh [march_float_box]
    that the callee unboxes in its prologue and never releases; the box stays
    the caller's (released by [Llvm_emit_call]'s call-site release and by the
    runtime helpers themselves).

    ── Failure direction ────────────────────────────────────────────────────

    A MISSING entry makes the trampoline release nothing, which leaks a
    borrowed argument once per call (the pre-2026-09-14 behaviour) but never
    double-frees.  Every path that does not register (a function outside the
    module Perceus ran on) degrades to that.

    [reset] is called at the start of each [Perceus.perceus] so state never
    leaks across compilations (the REPL and the test drivers reuse the
    process). *)

let table : (string, bool list) Hashtbl.t = Hashtbl.create 64

let reset () = Hashtbl.clear table

let register (fn_name : string) (borrowed : bool list) : unit =
  Hashtbl.replace table fn_name borrowed

(** Which parameters of [fn_name] its body borrows, if [Perceus] registered it. *)
let borrowed_params (fn_name : string) : bool list option =
  Hashtbl.find_opt table fn_name
