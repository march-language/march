(** Compiler-inserted capability passing — the plumbing half.

    A cap-requiring builtin does not take its capability as an argument
    ([println : (String) -> ()]); the requirement lives in a side table and is
    discharged module-wide by `needs`, so there is frequently NO capability
    value in scope where the operation happens.  A dictionary attached to a
    capability therefore cannot be consulted — there is nothing at the call
    site to consult it through.  This pass supplies one, giving every function
    that transitively performs interceptable IO an IMPLICIT capability
    parameter and threading it from its callers.

    {2 Why TIR and not the AST}

    The AST has 58 expression constructors and no generic map, so a rewriter
    must be total over all 58 by hand — and a missed constructor is SILENT: a
    call site inside it keeps its old arity while the callee gained a
    parameter.  TIR is in ANF, so every call is [EApp] or [ECallPtr] and
    nothing nests inside an expression; the match below has no wildcard, which
    makes a missed constructor a COMPILE error instead.

    The pass runs immediately after [Lower.lower_module], which is the one
    point where a TIR fn's name is still exactly its source name (Mono has not
    mangled anything, Defun has not lifted lambdas).

    {2 What this half does and does not do}

    THREADING ONLY.  It adds parameters and passes them; it does not yet
    rewrite an operation into a dictionary dispatch.  That ordering is
    deliberate: with nothing consuming the new parameters, an elaborated
    program must behave EXACTLY as it did before, which makes the whole test
    suite a check on the riskiest half — arity changes flowing through Defun,
    Mono, Perceus and the CAS key — before any behaviour rides on it.

    {2 Restrictions, each costing interception and never correctness}

    - Only functions reachable from the roots are elaborated; an
      un-elaborated function keeps today's behaviour exactly.
    - A function whose name is used anywhere except as a call HEAD — captured
      in a closure ([ADefRef]), or passed as a value — is NOT elaborated.
      Changing its arity would break that reference.
    - Actor handlers are invoked by the scheduler rather than by an elaborated
      caller, so there is nobody to thread from; they are left alone. *)

module T = Tir

(* ── which operations are interceptable ───────────────────────────────── *)

(** The capability whose dictionary has a field for [name].  Deliberately not
    [builtin_cap_table] directly: an operation with no dictionary field
    (polymorphic, or shadowed by a stdlib March function) can never be
    intercepted, so threading a capability for it would change arity for no
    benefit at all. *)
let cap_of_interceptable_op : string -> string option =
  let tbl = Hashtbl.create 128 in
  let built = ref false in
  fun name ->
    if not !built then begin
      built := true;
      List.iter
        (fun (op, cap) ->
           if List.mem_assoc op (March_typecheck.Io_ops_gen.dict_fields cap) then
             Hashtbl.replace tbl op cap)
        March_typecheck.Typecheck_builtins.builtin_cap_table
    end;
    Hashtbl.find_opt tbl name

(** The implicit parameter carrying [cap].  `$` keeps it out of the user's
    namespace; dots become underscores because a variable name cannot carry
    the capability path's dots. *)
let cap_param_name (cap : string) : string =
  "$cap_" ^ String.map (fun c -> if c = '.' then '_' else c) cap

let cap_ty (cap : string) : T.ty = T.TCon ("Cap", [ T.TCon (cap, []) ])

let cap_var (cap : string) : T.var =
  { T.v_name = cap_param_name cap; T.v_ty = cap_ty cap; T.v_lin = T.Unr }

(** The ambient sentinel: a capability carrying no dictionary, which is what
    every capability in every program is unless something attached one.
    [root_cap] is special-cased by both backends to the sentinel (null in
    [Llvm_emit.emit_atom], [VUnit] in eval).  Source code may not name it
    outside a test body (reject/t152), but that is a TYPECHECK rule and this
    pass runs after typechecking. *)
let ambient_atom (cap : string) : T.atom =
  T.AVar { T.v_name = "root_cap"; T.v_ty = cap_ty cap; T.v_lin = T.Unr }

(* ── analysis ─────────────────────────────────────────────────────────── *)

module StrSet = Set.Make (String)

type facts = {
  calls : (string, string list) Hashtbl.t;   (** fn -> names it calls in HEAD position *)
  ops   : (string, string list) Hashtbl.t;   (** fn -> capabilities its own body needs *)
  unsafe : (string, unit) Hashtbl.t;         (** fn referenced other than as a call head *)
  toplevel : (string, unit) Hashtbl.t;       (** every top-level fn name in the module *)
}

(** Walk one function body, recording call heads, interceptable operations, and
    any TOP-LEVEL FUNCTION name used in a position where changing its arity
    would break it.

    [bound] carries the locally-bound names, and it is load-bearing.  Without
    it the [unsafe] set is keyed by bare name across the whole program, so a
    LOCAL VARIABLE anywhere poisons the top-level function that happens to
    share its name — `Sort.introsort_go` has a local `middle`, which silently
    disqualified a user function called `middle` from ever being elaborated.
    A local that shadows a top-level name still marks it, which is
    conservative: it costs interception, never correctness.

    No wildcard arm: a new TIR constructor must be classified here explicitly
    rather than silently dropping the call edges inside it. *)
let rec scan (f : facts) (owner : string) (bound : StrSet.t) (e : T.expr) : unit =
  let add tbl k v =
    Hashtbl.replace tbl k (v :: Option.value ~default:[] (Hashtbl.find_opt tbl k))
  in
  let mark n =
    (* Only a top-level function's arity can be changed by this pass, and only
       a reference to THAT function (not to a local of the same name) can be
       broken by changing it. *)
    if Hashtbl.mem f.toplevel n && not (StrSet.mem n bound) then
      Hashtbl.replace f.unsafe n ()
  in
  let atom (a : T.atom) =
    match a with
    | T.AVar v -> mark v.T.v_name
    | T.ADefRef d -> mark d.T.did_name
    | T.ALit _ -> ()
  in
  let atoms = List.iter atom in
  let go = scan f owner bound in
  match e with
  | T.EApp (v, args) ->
    add f.calls owner v.T.v_name;
    (match cap_of_interceptable_op v.T.v_name with
     | Some cap -> add f.ops owner cap
     | None -> ());
    atoms args
  | T.ECallPtr (fa, args) -> atom fa; atoms args
  | T.EAtom a -> atom a
  | T.ELet (v, e1, e2) ->
    go e1;
    scan f owner (StrSet.add v.T.v_name bound) e2
  | T.ELetRec (fns, body) ->
    let bound' =
      List.fold_left (fun acc (fd : T.fn_def) -> StrSet.add fd.T.fn_name acc) bound fns
    in
    List.iter
      (fun (fd : T.fn_def) ->
         let inner =
           List.fold_left (fun acc (p : T.var) -> StrSet.add p.T.v_name acc) bound' fd.T.fn_params
         in
         scan f fd.T.fn_name inner fd.T.fn_body)
      fns;
    scan f owner bound' body
  | T.ECase (a, brs, def) ->
    atom a;
    List.iter
      (fun (b : T.branch) ->
         let inner =
           List.fold_left (fun acc (v : T.var) -> StrSet.add v.T.v_name acc) bound b.T.br_vars
         in
         scan f owner inner b.T.br_body)
      brs;
    Option.iter go def
  | T.ETuple ats -> atoms ats
  | T.ERecord flds -> List.iter (fun (_, a) -> atom a) flds
  | T.EField (a, _) -> atom a
  | T.EUpdate (a, flds) -> atom a; List.iter (fun (_, x) -> atom x) flds
  | T.EAlloc (_, ats) | T.EStackAlloc (_, ats) -> atoms ats
  | T.EReuse (a, _, ats) -> atom a; atoms ats
  | T.EFree a | T.EIncRC a | T.EDecRC a | T.EAtomicIncRC a | T.EAtomicDecRC a -> atom a
  | T.ESeq (e1, e2) -> go e1; go e2
  | T.EAllocHole (tok, _, ats, _) -> Option.iter atom tok; atoms ats
  | T.ESetField (o, _, v) -> atom o; atom v

(** [needed_caps m] maps each function to the capabilities it must carry: the
    ones its own body performs, plus everything its callees need, to a
    fixpoint.  Functions in [unsafe] are excluded — their arity cannot change. *)
let needed_caps (m : T.tir_module) : (string, string list) Hashtbl.t =
  let f = { calls = Hashtbl.create 64; ops = Hashtbl.create 64;
            unsafe = Hashtbl.create 64; toplevel = Hashtbl.create 512 } in
  List.iter (fun (fd : T.fn_def) -> Hashtbl.replace f.toplevel fd.T.fn_name ()) m.T.tm_fns;
  List.iter
    (fun (fd : T.fn_def) ->
       let bound =
         List.fold_left (fun acc (p : T.var) -> StrSet.add p.T.v_name acc)
           StrSet.empty fd.T.fn_params
       in
       scan f fd.T.fn_name bound fd.T.fn_body)
    m.T.tm_fns;
  let need = Hashtbl.create 64 in
  let get k = Option.value ~default:[] (Hashtbl.find_opt need k) in
  let union a b = List.sort_uniq String.compare (a @ b) in
  Hashtbl.iter (fun k v -> Hashtbl.replace need k (List.sort_uniq String.compare v)) f.ops;
  let changed = ref true in
  while !changed do
    changed := false;
    List.iter
      (fun (fd : T.fn_def) ->
         let me = fd.T.fn_name in
         let from_callees =
           List.fold_left (fun acc c -> union acc (get c)) []
             (Option.value ~default:[] (Hashtbl.find_opt f.calls me))
         in
         let merged = union (get me) from_callees in
         if merged <> get me then begin Hashtbl.replace need me merged; changed := true end)
      m.T.tm_fns
  done;
  (* Drop anything whose arity must not change, and anything left needing
     nothing. *)
  Hashtbl.iter
    (fun k _ -> if Hashtbl.mem f.unsafe k then Hashtbl.remove need k)
    (Hashtbl.copy need);
  Hashtbl.iter (fun k v -> if v = [] then Hashtbl.remove need k) (Hashtbl.copy need);
  need

(** Human-readable analysis dump, behind [MARCH_DUMP_CAP_PASSING=1].  The
    threading is only as good as this table, and the table is derived from a
    call graph rather than declared anywhere, so it needs to be inspectable
    before anything rides on it. *)
let dump (m : T.tir_module) : unit =
  (* Focused trace for one function, for debugging the analysis itself. *)
  (match Sys.getenv_opt "MARCH_DUMP_CAP_PASSING_FN" with
   | None -> ()
   | Some target ->
     let f = { calls = Hashtbl.create 64; ops = Hashtbl.create 64;
               unsafe = Hashtbl.create 64; toplevel = Hashtbl.create 512 } in
     List.iter (fun (fd : T.fn_def) -> Hashtbl.replace f.toplevel fd.T.fn_name ()) m.T.tm_fns;
     List.iter
       (fun (fd : T.fn_def) ->
          let bound =
            List.fold_left (fun acc (p : T.var) -> StrSet.add p.T.v_name acc)
              StrSet.empty fd.T.fn_params
          in
          scan f fd.T.fn_name bound fd.T.fn_body)
       m.T.tm_fns;
     Printf.eprintf "--- trace %s: in tm_fns=%b unsafe=%b calls=[%s] ops=[%s]\n"
       target
       (List.exists (fun (fd : T.fn_def) -> fd.T.fn_name = target) m.T.tm_fns)
       (Hashtbl.mem f.unsafe target)
       (String.concat ", " (Option.value ~default:[] (Hashtbl.find_opt f.calls target)))
       (String.concat ", " (Option.value ~default:[] (Hashtbl.find_opt f.ops target))));
  let need = needed_caps m in
  let rows =
    Hashtbl.fold (fun k v acc -> (k, v) :: acc) need []
    |> List.sort (fun (a, _) (b, _) -> String.compare a b)
  in
  Printf.eprintf "=== cap-passing: %d of %d functions need a threaded capability ===\n"
    (List.length rows) (List.length m.T.tm_fns);
  List.iter (fun (k, v) -> Printf.eprintf "  %-52s %s\n" k (String.concat ", " v)) rows

(* ── threading ────────────────────────────────────────────────────────── *)

(** Functions whose arity must not change because something outside this pass
    calls them: the runtime entry point, the test runner's targets, and
    anything exported for DCE/hot-reload to reach.  They stay as they are and
    pass the ambient sentinel to whatever they call.

    (Actor handlers are reached through a dispatch table, so they appear as
    [ADefRef] and the [unsafe] rule already excludes them; they are not
    special-cased here.) *)
let roots (m : T.tir_module) : (string, unit) Hashtbl.t =
  let h = Hashtbl.create 32 in
  let add n = Hashtbl.replace h n () in
  List.iter (fun (fd : T.fn_def) ->
      let n = fd.T.fn_name in
      if n = "main" || Filename.check_suffix n ".main" then add n)
    m.T.tm_fns;
  List.iter (fun (fn, _) -> add fn) m.T.tm_tests;
  List.iter add m.T.tm_exports;
  h

(** Rewrite every call to an elaborated function so it carries the capabilities
    that function now expects.

    [avail] is what the ENCLOSING function can supply: the capabilities it
    itself carries.  Anything it cannot supply is passed as the ambient
    sentinel, which reads back as [None] — i.e. exactly today's behaviour.
    That is why this half is safe to land before any dispatch exists.

    No wildcard arm, for the same reason as [scan]: a call site inside an
    unhandled constructor would keep its old arity while its callee gained
    parameters. *)
let rec thread (need : (string, string list) Hashtbl.t)
    (avail : StrSet.t) (e : T.expr) : T.expr =
  let go = thread need avail in
  match e with
  | T.EApp (v, args) ->
    (match Hashtbl.find_opt need v.T.v_name with
     | None -> e
     | Some caps ->
       let extra =
         List.map
           (fun c -> if StrSet.mem c avail then T.AVar (cap_var c) else ambient_atom c)
           caps
       in
       (* Keep the callee var's own type in step with its new arity: a stale
          TFn here would misreport the callee's shape to any later pass that
          reads it rather than the fn_def. *)
       let v =
         match v.T.v_ty with
         | T.TFn (ps, r) -> { v with T.v_ty = T.TFn (List.map cap_ty caps @ ps, r) }
         | _ -> v
       in
       T.EApp (v, extra @ args))
  | T.ELet (v, e1, e2) -> T.ELet (v, go e1, go e2)
  | T.ELetRec (fns, body) ->
    (* A lambda body sees the enclosing function's capability parameters as
       free variables; Defun captures them when it lifts the lambda. *)
    T.ELetRec
      (List.map (fun (fd : T.fn_def) -> { fd with T.fn_body = go fd.T.fn_body }) fns,
       go body)
  | T.ECase (a, brs, def) ->
    T.ECase (a,
             List.map (fun (b : T.branch) -> { b with T.br_body = go b.T.br_body }) brs,
             Option.map go def)
  | T.ESeq (e1, e2) -> T.ESeq (go e1, go e2)
  | T.EAtom _ | T.ECallPtr _ | T.ETuple _ | T.ERecord _ | T.EField _
  | T.EUpdate _ | T.EAlloc _ | T.EStackAlloc _ | T.EFree _ | T.EIncRC _
  | T.EDecRC _ | T.EAtomicIncRC _ | T.EAtomicDecRC _ | T.EReuse _
  | T.EAllocHole _ | T.ESetField _ -> e

(** [elaborate m] gives every function that performs interceptable IO an
    implicit capability parameter and threads it from its callers.

    THREADING ONLY: nothing yet consumes the parameters, so an elaborated
    program must behave exactly as it did before.  That is the point — it makes
    the whole test suite a check on arity changes flowing through Defun, Mono,
    Perceus and the CAS key, before any behaviour rides on them. *)
let elaborate (m : T.tir_module) : T.tir_module =
  let need = needed_caps m in
  let rts = roots m in
  Hashtbl.iter (fun k _ -> if Hashtbl.mem rts k then Hashtbl.remove need k)
    (Hashtbl.copy need);
  if Hashtbl.length need = 0 then m
  else
    let changed = ref 0 in
    let fns =
      List.map
        (fun (fd : T.fn_def) ->
           let caps = Option.value ~default:[] (Hashtbl.find_opt need fd.T.fn_name) in
           if caps <> [] then incr changed;
           let avail = StrSet.of_list caps in
           { fd with
             T.fn_params = List.map cap_var caps @ fd.T.fn_params;
             T.fn_body = thread need avail fd.T.fn_body })
        m.T.tm_fns
    in
    (* Report what was actually rewritten.  Without this the only evidence the
       pass ran is the absence of a difference, which is exactly what a pass
       that silently did nothing also looks like. *)
    if Sys.getenv_opt "MARCH_DUMP_CAP_PASSING" = Some "1" then
      Printf.eprintf "=== cap-passing: threaded %d functions ===\n" !changed;
    { m with T.tm_fns = fns }
