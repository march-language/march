(** Per-pass TIR counts (observability plan A6,
    specs/plans/incremental-codegen-cas-plan.md §10).

    Static counts over one module: how many functions, allocation sites,
    RC operations, reuse tokens and join points it holds.  Printed next to
    each pass's [--timings] stamp, so a regression that doubles the RC ops or
    stops a reuse from firing shows up as a number moving at a named pass,
    not only as a slower benchmark.  Pinned for three snapshot programs in
    test/test_snapshots.ml.

    The counts are of SITES in the IR, not of runtime events. *)

type t = {
  fns    : int;  (** top-level [fn_def]s plus [ELetRec]-bound ones *)
  allocs : int;  (** heap allocation sites: [EAlloc], [EAllocHole] *)
  stack  : int;  (** [EStackAlloc] (Escape's promotions) *)
  incs   : int;  (** [EIncRC] + [EAtomicIncRC] *)
  decs   : int;  (** [EDecRC] + [EAtomicDecRC] + [EFree] *)
  reuse  : int;  (** reuse tokens: [EReuse], [EAllocHole] with a token *)
  jps    : int;  (** join points: [fn_def]s of kind [FnJoinPoint] (lowering's
                     match fallbacks, until Defun lifts them) plus [let]
                     binders [Join_points] floated (named [$jp...]) *)
}

let zero = { fns = 0; allocs = 0; stack = 0; incs = 0; decs = 0; reuse = 0; jps = 0 }

let of_module (m : Tir.tir_module) : t =
  let c = ref zero in
  let rec expr (e : Tir.expr) =
    match e with
    | Tir.EAlloc _ -> c := { !c with allocs = !c.allocs + 1 }
    | Tir.EStackAlloc _ -> c := { !c with stack = !c.stack + 1 }
    | Tir.EAllocHole (tok, _, _, _) ->
      c := { !c with allocs = !c.allocs + 1;
                     reuse = !c.reuse + (if tok = None then 0 else 1) }
    | Tir.EReuse _ -> c := { !c with reuse = !c.reuse + 1 }
    | Tir.EIncRC _ | Tir.EAtomicIncRC _ -> c := { !c with incs = !c.incs + 1 }
    | Tir.EDecRC _ | Tir.EAtomicDecRC _ | Tir.EFree _ ->
      c := { !c with decs = !c.decs + 1 }
    | Tir.ELet (v, a, b) ->
      if String.length v.Tir.v_name >= 3 && String.sub v.Tir.v_name 0 3 = "$jp" then
        c := { !c with jps = !c.jps + 1 };
      expr a; expr b
    | Tir.ESeq (a, b) -> expr a; expr b
    | Tir.ELetRec (fs, body) -> List.iter fn fs; expr body
    | Tir.ECase (_, brs, def) ->
      List.iter (fun (b : Tir.branch) -> expr b.Tir.br_body) brs;
      Option.iter expr def
    | Tir.EAtom _ | Tir.EApp _ | Tir.ECallPtr _ | Tir.ETuple _ | Tir.ERecord _
    | Tir.EField _ | Tir.EUpdate _ | Tir.ESetField _ -> ()
  and fn (fd : Tir.fn_def) =
    c := { !c with fns = !c.fns + 1;
                   jps = !c.jps + (if fd.Tir.fn_kind = Tir.FnJoinPoint then 1 else 0) };
    expr fd.Tir.fn_body
  in
  List.iter fn m.Tir.tm_fns;
  !c

let to_string (t : t) : string =
  Printf.sprintf "fns=%d allocs=%d stack=%d inc=%d dec=%d reuse=%d jp=%d"
    t.fns t.allocs t.stack t.incs t.decs t.reuse t.jps
