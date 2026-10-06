(** The one answer to "is this bare callee name a runtime builtin?".

    TIR has no builtin constructor: a builtin call is an ordinary
    [EApp (var, args)] whose [v_name] is the bare March builtin name
    ([tir.ml]'s [EApp]).  The LLVM emitter used to decide "known callee" from
    three overlapping sources — [Llvm_builtins.builtin_ret_ty], the
    [Builtin_name] variant, and a hard-coded I/O name list in
    [Llvm_emit_call] — and silently [declare]d anything none of them knew, so
    a mistyped or never-registered builtin surfaced only as a link failure
    (or, worse, linked to an unrelated same-named C symbol).

    Sources: the row table [Llvm_builtins.builtins] (one row
    per March builtin name, which already drives the preamble declares, the
    C-symbol mangling and the return-type overrides).  [Builtin_name.t] is the
    second source and is unioned in: the names [emit_expr] dispatches with a
    dedicated arm.  The union is not redundant — 24 of them ([int_div],
    [negate], [task_cancel], [signal_watch], ...) are synthesized by their arm
    and have no row.  The former hard-coded I/O list is gone: every name on it
    has a row with a return type (pinned by test).

    The preamble is NOT derived from this table here: its bytes are pinned
    by the [llvm_builtins_preamble_golden] tests and deriving it would change
    them.  That is a separate follow-up.

    Consumers: [Llvm_emit_call]'s general-call and global-[ECallPtr] arms
    (known-callee test), and the planned TIR verifier (A1 in
    specs/plans/incremental-codegen-cas-plan.md). *)

let table : (string, unit) Hashtbl.t =
  let h = Hashtbl.create 512 in
  List.iter (fun (b : Llvm_builtins.builtin) -> Hashtbl.replace h b.march_name ())
    Llvm_builtins.builtins;
  List.iter (fun c -> Hashtbl.replace h (Builtin_name.to_string c) ())
    Builtin_name.all;
  h

let is_builtin (name : string) : bool = Hashtbl.mem table name

(** Every builtin name, sorted and duplicate-free. *)
let all : string list =
  Hashtbl.fold (fun k () acc -> k :: acc) table [] |> List.sort_uniq compare

(** TIR return-type override for a builtin, when it has one (delegates to
    [Llvm_builtins.builtin_ret_ty]; [None] for builtins whose type comes from
    the call site or that a dedicated emit arm handles). *)
let ret_ty (name : string) : Tir.ty option = Llvm_builtins.builtin_ret_ty name
