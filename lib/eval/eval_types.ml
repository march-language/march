(** Interpreter value and environment types.

    Extracted verbatim from eval.ml:17-142 so that the builtin table,
    the protocol runtimes, and the evaluator can live in sibling modules
    without a dependency cycle.  No behavior change. *)

open March_ast.Ast

(* ------------------------------------------------------------------ *)
(* Ring buffer type (defined before value so VRingBuf can reference it)*)
(* ------------------------------------------------------------------ *)

type 'a ring = {
  mutable rb_arr  : 'a option array;
  mutable rb_head : int;   (* index of next write position *)
  mutable rb_size : int;   (* number of entries stored *)
  rb_cap          : int;
}

(* ------------------------------------------------------------------ *)
(* Value type                                                          *)
(* ------------------------------------------------------------------ *)

type value =
  | VInt    of int
  | VFloat  of float
  | VString of string
  | VBool   of bool
  | VAtom   of string
  | VUnit
  | VTuple  of value list
  | VRecord of (string * value) list
  | VCon    of string * value list      (** Constructor: tag + payload *)
  | VClosure of env * string list * expr * string
      (** Closure: captured env, param names, body, and the lexical
          declaring-module-QUALIFYING prefix (e.g. "DcA.", "" at top level)
          in effect when this closure was CONSTRUCTED — see
          [effective_module_prefix]. Needed because [module_stack]/
          [current_doc_prefix] alone reflect only the single, eager, upfront
          [eval_decl] walk over the AST; by the time a deferred closure body
          actually runs (any call after its containing [DFn]/[DImpl]/[ELam]
          was first evaluated), that walk has moved on (or finished
          entirely) and [module_stack] no longer names this closure's own
          declaring module. [apply_inner]'s [VClosure] arm restores this
          prefix as the ambient [closure_prefix_override] for the duration
          of the body's evaluation, so a bare colliding constructor
          referenced inside the body (construction via [ECon], or a pattern
          via [match_pattern]'s [PatCon] arm) qualifies against the module
          it was LEXICALLY written in, not whatever module the CALLER
          happens to be in. *)
  | VBuiltin of string * (value list -> value)
  | VPid    of int                      (** Actor process id *)
  | VTask         of int                 (** Task handle *)
  | VCancelToken  of bool ref            (** Cancellation token (shared mutable flag) *)
  | VTimerRef of timer_entry
      (** send_after handle (specs/progress/2026-08-12-language-level-timers.md).
          cancel_timer sets [tt_cancelled]; [timer_service_tick] (called from
          [run_scheduler]) checks it at [tt_fire_at]. *)
  | VWorkPool                            (** Work-stealing pool capability *)
  | VCap    of int * int                (** Epoch-stamped capability: (pid, epoch) *)
  | VActorId of int                     (** Opaque actor identity (epoch-independent) *)
  | VChan   of chan_endpoint            (** Binary session-typed channel endpoint *)
  | VMChan  of mpst_endpoint            (** Multi-party session-typed channel endpoint *)
  | VForeign of string * string * bool * March_ast.Ast.ty list * March_ast.Ast.ty
        (** FFI extern: (lib_name, symbol_name, raises, param_types, return_type).
            The types drive interpreter-side marshalling for the dynamic
            (dlopen+trampoline) call path. *)
  | VMultiarity of (int * value) list   (** Arity-dispatched fn: [(arity, closure)] sorted ascending *)
  | VNativeIntArr   of int array        (** Flat OCaml int array — fast numeric loops *)
  | VNativeFloatArr of float array      (** Flat OCaml float array — fast numeric loops *)
  | VNativeF32Arr of float array   (** elements pre-rounded to binary32 *)
  | VNativeI32Arr of int array     (** elements always in [-2^31, 2^31) *)
  | VNativeU8Arr  of int array     (** elements always in [0, 255] *)
  (* Simd — explicit 128-bit SIMD vector types (F32x4/F64x2/I32x4/I64x2/U8x16). *)
  | VF32x4 of float array   (** 4 lanes, each pre-rounded to binary32 *)
  | VF64x2 of float array   (** 2 lanes, native double *)
  | VI32x4 of int array     (** 4 lanes, each in [-2^31, 2^31) *)
  | VI64x2 of int64 array   (** 2 lanes, exact 64-bit (OCaml [int] is only
                                 63-bit -- see the eval.ml Simd section) *)
  | VU8x16 of int array     (** 16 lanes, each in [0, 255] *)
  | VTypedArray of value array          (** Contiguous typed array for columnar DataFrame storage *)
  | VVaultHandle of int                 (** Opaque handle into vault_registry *)
  | VRingBuf of value ring              (** Fixed-capacity mutable circular buffer — single-owner *)
  | VResource of int64
      (** Opaque FFI `resource` handle (e.g. a native DB/Stmt handle from an
          extern call). Holds the raw marshaled march_value bits; never
          introspected by the interpreter, only round-tripped through
          ffi_marshal_iv/ffi_unmarshal_iv back into subsequent extern calls. *)

(** One endpoint of a binary session-typed channel.
    Each channel consists of two linked endpoints; one side's [ce_out_q]
    is the other side's [ce_in_q]. *)
and chan_endpoint = {
  ce_id      : int;           (** Globally unique channel id *)
  ce_role    : string;        (** Which side of the protocol this is *)
  ce_proto   : string;        (** Protocol name, for runtime error messages *)
  mutable ce_closed   : bool;
  ce_out_q   : value Queue.t; (** Values this endpoint puts out (other side reads) *)
  ce_in_q    : value Queue.t; (** Values this endpoint receives (other side wrote) *)
}

(** One endpoint of a multi-party session.
    For N roles there are N*(N-1) directed queues (one per ordered role pair).
    [me_out_qs] maps target_role → send queue (messages this endpoint sends to target).
    [me_in_qs]  maps source_role → recv queue (messages this endpoint receives from source).
    By construction A.me_out_qs["B"] == B.me_in_qs["A"] (same physical Queue). *)
and mpst_endpoint = {
  me_id       : int;            (** Globally unique session id *)
  me_role     : string;         (** Which role this endpoint represents *)
  me_proto    : string;         (** Protocol name, for runtime error messages *)
  mutable me_closed : bool;
  me_out_qs   : (string, value Queue.t) Hashtbl.t;  (** target_role → send queue *)
  me_in_qs    : (string, value Queue.t) Hashtbl.t;  (** source_role → recv queue *)
}

(** A pending [send_after] timer (specs/progress/2026-08-12-language-level-
    timers.md): deliver [tt_msg] to the actor at pid [tt_target] once real
    time reaches [tt_fire_at] (milliseconds, [Unix.gettimeofday] clock),
    unless [tt_cancelled] is set first. Serviced by [timer_service_tick],
    called once per [run_scheduler] pass — see that function's doc comment
    for why a not-yet-due timer does NOT make [run_until_idle] block (the
    same design decision the compiled runtime's [march_sched_wait_idle]
    makes for the identical reason; see its doc comment in
    runtime/march_scheduler.c). *)
and timer_entry = {
  tt_fire_at    : float;
  tt_target     : int;      (** actor_registry pid *)
  tt_msg        : value;
  mutable tt_cancelled : bool;
}

(** Association-list environment mapping names to values. *)
and env = (string * value) list

