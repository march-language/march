(** Cross-pass channel carrying, for each closure type whose environment owns
    its captures, the pair (apply function, synthesized deep-drop function)
    from [Drop] to [Llvm_toplevel].

    ── The site this exists for ─────────────────────────────────────────────

    A bare release of a closure VALUE — a lambda handed to a higher-order
    function that drops it (`List.fold_left(xs, 0, step)` releases `step`), a
    closure pulled out of a data structure and discarded — lowers to
    [march_decrc], a shallow free.  Everything the lambda captured is orphaned:
    3 heap objects per call in the fixture below.

    Unlike the release INSIDE an apply function, this one cannot be typed its
    way out of: the value's TIR type there is a function type, which names no
    layout, and one function type admits many closure shapes.  So the layout
    question is answered at run time by the one thing the cell carries that
    identifies its shape — the apply-function pointer in field 0.  [Drop]
    synthesizes `__drop_clo$<Clo>` per closure type, this table pairs it with
    the apply function, [Llvm_toplevel] emits a constructor that registers the
    pairs with the runtime, and [march_drop_closure] looks the drop up by that
    pointer when its release is the one that reaches zero.

    ── Failure direction ────────────────────────────────────────────────────

    A MISSING pair leaks, never double-frees: the release stays the shallow
    free it is today.  Every path that does not register — the REPL/JIT (ORC
    does not run the module's constructors), a closure built by the C runtime
    or the cross-heap message copier — therefore degrades to the old
    behaviour.  Only closure types whose environment provably OWNS its captures
    are registered at all ([Drop.owning_clo_types], the same verdict that gates
    the apply-function side), because releasing a BORROWED capture is a double
    free.

    [reset] is called at the start of each [Drop.run]; the table is
    process-global and the REPL and test drivers compile many modules in one
    process. *)

let table : (string, string) Hashtbl.t = Hashtbl.create 64

let reset () = Hashtbl.clear table

(** [register ~apply_fn ~drop_fn] pairs a closure's apply function with the
    deep-drop synthesized for its environment. *)
let register ~(apply_fn : string) ~(drop_fn : string) : unit =
  Hashtbl.replace table apply_fn drop_fn

(** The (apply fn, drop fn) pairs registered for this module, sorted by apply
    name so the emitted constructor is deterministic. *)
let pairs () : (string * string) list =
  Hashtbl.fold (fun a d acc -> (a, d) :: acc) table []
  |> List.sort (fun (a, _) (b, _) -> String.compare a b)
