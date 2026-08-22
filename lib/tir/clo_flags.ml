(** Cross-pass channel carrying ONE bit of borrow information about each
    closure's callee from [Perceus] (which owns the converged
    [Borrow.borrow_map]) to [Llvm_emit] (which materialises closure objects),
    so that the C runtime's higher-order helpers can see it.

    ── The question the runtime cannot answer on its own ────────────────────

    [runtime/march_runtime.c]'s five fold helpers thread the accumulator
    through the erased closure ABI:

        result = call_closure_2(f, prev, elem);

    and then have to decide whether they still own [prev].  They do NOT if the
    apply fn consumed it (Perceus's documented [ECallPtr] convention is that
    the closure-apply ABI consumes its arguments, and an apply fn with an
    OWNING use of that parameter — `fn (acc, x) -> Cons(x, acc)` — stores the
    caller's reference into its result without an [EIncRC]).  They DO if the
    apply fn merely borrowed it — `fn (acc, x) -> int_to_string(len(acc) + x)`
    — in which case not releasing it leaks one heap object per element,
    unbounded in array length.

    Both shapes are ordinary March.  The runtime sees the same `void *f`
    either way, and no dynamic test distinguishes them: a "fresh" result and
    a borrowed alias are both just pointers, and rc == 1 is equally consistent
    with "solely mine" and "solely the array's".  PR #313 could only close the
    Float case because the uniform-ptr ABI makes every Float-typed return
    provably a fresh box ([MARCH_FLOAT_TAG] is the witness); no such witness
    exists for a String / List / record accumulator.  So the answer has to
    come from the compiler, which is what this table carries.

    ── What is carried, and where it is stamped ─────────────────────────────

    [Borrow.first_user_arg_borrowed] answers "does this function's first USER
    argument (i.e. skipping an apply fn's implicit [$clo]) have no owning use
    in its body?".  [Perceus] records that per function here; [Llvm_emit]
    looks it up at every site that materialises a closure object and, when it
    holds, stamps [flag_arg0_borrowed] into the object's header pad word
    (offset 12 — [march_hdr.pad], zeroed by [march_alloc]).  The runtime reads
    it back through [MARCH_CLO_ARG0_BORROWED] in [runtime/march_runtime.h].

    Why the pad word and not a side table keyed by fn pointer: the flag has to
    travel with the VALUE.  `NativeArray.fold_int` is a March wrapper around
    the builtin, so at the emission site of the actual runtime call the
    callback is a plain parameter with no statically-known apply fn — a
    call-site-keyed channel would fix only the folds whose lambda is written
    inline and silently leave every stdlib wrapper leaking.

    ── Failure direction ────────────────────────────────────────────────────

    A MISSING flag costs nothing but the pre-existing leak: the fold helper
    falls back to the [MARCH_FLOAT_TAG]-only release PR #313 landed.  Every
    path that does not stamp — REPL/JIT fragments, hot-reload closures,
    closures rebuilt by the cross-heap message copier, a future closure
    materialisation site nobody updates — therefore degrades to today's
    behaviour rather than to a double free.  That asymmetry is deliberate:
    the table is consulted only to ENABLE a release, never to suppress one.

    [reset] is called at the start of each [Perceus.perceus] so state never
    leaks across compilations (the REPL and the test drivers reuse the
    process).  Perceus runs unconditionally in every pipeline that reaches
    LLVM emission (`bin/main.ml`, `lib/jit/repl_jit.ml`,
    `lib/driver/js_pipeline.ml`), so a lookup always reads the current
    module's answers — the same discipline as [Dispatch_registry]. *)

(** Header-pad bit meaning "the callee does not consume or retain this
    closure's first user argument".  MUST equal [MARCH_CLO_ARG0_BORROWED] in
    [runtime/march_runtime.h]. *)
let flag_arg0_borrowed = 1

let table : (string, bool) Hashtbl.t = Hashtbl.create 64

let reset () = Hashtbl.clear table

let register (fn_name : string) (arg0_borrowed : bool) : unit =
  Hashtbl.replace table fn_name arg0_borrowed

(** The pad word to stamp into a closure object whose callee is [fn_name]
    (the lifted apply fn for a lambda, the wrapped top-level function for a
    [$clo_wrap] trampoline).  0 when nothing is known — see "failure
    direction" above. *)
let pad_for (fn_name : string) : int =
  match Hashtbl.find_opt table fn_name with
  | Some true -> flag_arg0_borrowed
  | Some false | None -> 0
