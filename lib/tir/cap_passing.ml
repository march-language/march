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

(** [actor_of_spawn n] is the actor name when [n] is a spawn glue function. *)
let actor_of_spawn (n : string) : string option =
  let sfx = Tir_names.actor_spawn_suffix in
  let ls = String.length sfx and ln = String.length n in
  if ln > ls && String.sub n (ln - ls) ls = sfx
  then Some (String.sub n 0 (ln - ls)) else None


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
  | T.EApp (v, args) when v.T.v_name = "register_supervisor_child" ->
    (* The spawn glue named as this call's third argument is passed as a
       VALUE (the runtime re-runs it on respawn), but it is not a value use
       that freezes the glue's arity: [thread] replaces it with a closure
       that CALLS the glue with the capabilities the enclosing glue carries.
       So record it as a call edge, exactly like the head-position call the
       supervised-child shape already makes to it, and never as [unsafe] —
       otherwise a supervisor nested under another supervisor could never
       carry its own children's capabilities. *)
    add f.calls owner v.T.v_name;
    List.iteri
      (fun i a ->
         match i, a with
         | 2, T.AVar sf when actor_of_spawn sf.T.v_name <> None ->
           add f.calls owner sf.T.v_name
         | _ -> atom a)
      args
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
    (* A local function's calls and operations belong to the ENCLOSING
       top-level function, not to the local's own name.

       This is the SIGBUS.  Attributing them to the local name puts that name
       in the `need` table, but a local is not in [tm_fns], so [elaborate]
       never adds parameters to it while [thread] happily adds an argument at
       its call sites — an arity mismatch that dies at runtime.  Defun lifts
       these to top level LATER, which is why `--dump-tir` shows `fn do_lines`
       and made it look top-level.  `File.with_lines` is the witness: its local
       `do_lines` calls `file_read_line`.

       Attributing upward is also the semantically right answer — a local
       function's IO is its enclosing function's IO — so it closes a missed
       -threading hole at the same time. The local's own name and parameters
       still enter [bound] so that references to them are not mistaken for
       references to a top-level function of the same name. *)
    let bound' =
      List.fold_left (fun acc (fd : T.fn_def) -> StrSet.add fd.T.fn_name acc) bound fns
    in
    List.iter
      (fun (fd : T.fn_def) ->
         let inner =
           List.fold_left (fun acc (p : T.var) -> StrSet.add p.T.v_name acc) bound' fd.T.fn_params
         in
         scan f owner inner fd.T.fn_body)
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

(** The actors [e] spawns as SUPERVISED CHILDREN.  A `supervise` block's
    children are spawned inside the supervisor's own spawn glue
    (`lower_actor.ml`'s [spawn_with_fields]), as
      let $sup_child_raw_f = Child_spawn() in
      let $sup_child_ptr_f = spawn_supervised($sup_child_raw_f) in …
    which is a different shape from a plain `spawn(Child)` at a user site. *)
let supervised_children (e : T.expr) : string list =
  let acc = ref [] in
  let rec go (e : T.expr) =
    match e with
    | T.ELet (raw, T.EApp (cs, []), (T.ELet (_, T.EApp (ss, [ T.AVar raw' ]), _) as rest))
      when ss.T.v_name = "spawn_supervised" && raw'.T.v_name = raw.T.v_name ->
      (match actor_of_spawn cs.T.v_name with
       | Some child -> acc := child :: !acc
       | None -> ());
      go rest
    | T.ELet (_, a, b) | T.ESeq (a, b) -> go a; go b
    | T.ELetRec (fns, b) ->
      List.iter (fun (fd : T.fn_def) -> go fd.T.fn_body) fns; go b
    | T.ECase (_, brs, d) ->
      List.iter (fun (br : T.branch) -> go br.T.br_body) brs; Option.iter go d
    | T.EApp _ | T.ECallPtr _ | T.EAtom _ | T.ETuple _ | T.ERecord _
    | T.EField _ | T.EUpdate _ | T.EAlloc _ | T.EStackAlloc _ | T.EFree _
    | T.EIncRC _ | T.EDecRC _ | T.EAtomicIncRC _ | T.EAtomicDecRC _
    | T.EReuse _ | T.EAllocHole _ | T.ESetField _ -> ()
  in
  go e; List.rev !acc

(** [needed_caps m] maps each function to the capabilities it must carry: the
    ones its own body performs, plus everything its callees need, to a
    fixpoint.  Functions in [unsafe] are excluded — their arity cannot change. *)
let needed_caps (m : T.tir_module) : (string, string list) Hashtbl.t =
  let f = { calls = Hashtbl.create 64; ops = Hashtbl.create 64;
            unsafe = Hashtbl.create 64; toplevel = Hashtbl.create 512 } in
  List.iter (fun (fd : T.fn_def) -> Hashtbl.replace f.toplevel fd.T.fn_name ()) m.T.tm_fns;
  (* A supervisor's spawn glue spawns its declared children ITSELF, so it is
     the only place a supervised child's capabilities can be captured from —
     and the user's `spawn(Sup)` site is where a `with_cap` mock is in scope.
     Model the glue as calling each child's dispatch: the fixpoint below then
     charges it with everything the child's handlers reach, the user site
     threads those in (the glue is only ever a call head — a CHILD's spawn fn
     is passed as a value to `register_supervisor_child` for respawn and stays
     frozen, but a child needs no parameters, only a record set on it), and
     the capture pattern in [thread] builds the child's record inside the glue
     from the parameters it now carries. *)
  List.iter
    (fun (fd : T.fn_def) ->
       match actor_of_spawn fd.T.fn_name with
       | None -> ()
       | Some _ ->
         List.iter
           (fun child ->
              let callee = child ^ Tir_names.actor_dispatch_suffix in
              Hashtbl.replace f.calls fd.T.fn_name
                (callee :: Option.value ~default:[] (Hashtbl.find_opt f.calls fd.T.fn_name)))
           (supervised_children fd.T.fn_body))
    m.T.tm_fns;
  List.iter
    (fun (fd : T.fn_def) ->
       (* A dispatch wrapper CALLS the operation it wraps — that call is the
          ambient path, not a reason to give the wrapper a capability. It
          already takes one as its first parameter, so scanning it here would
          hand it a second. *)
       if not (March_typecheck.Io_ops_gen.is_dispatch_name fd.T.fn_name) then
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
  (* Invariant: [need] may only ever name a TOP-LEVEL function.  Anything else
     cannot have parameters added ([elaborate] maps over [tm_fns]) while its
     call sites would still gain arguments. *)
  Hashtbl.iter
    (fun k _ -> if not (Hashtbl.mem f.toplevel k) then Hashtbl.remove need k)
    (Hashtbl.copy need);
  (* Drop anything whose arity must not change, and anything left needing
     nothing. *)
  Hashtbl.iter
    (fun k _ -> if Hashtbl.mem f.unsafe k then Hashtbl.remove need k)
    (Hashtbl.copy need);
  Hashtbl.iter (fun k v -> if v = [] then Hashtbl.remove need k) (Hashtbl.copy need);
  need

(** Diagnostic: every name that appears as an [ADefRef], with no filtering at
    all.  [scan]'s [unsafe] rule only marks such a name when [did_name] matches
    a top-level [fn_name] and is not locally bound; if those spellings ever
    disagree, a function can be threaded AND still reached indirectly, and an
    indirect call passes the OLD arity. *)
let all_defrefs (m : T.tir_module) : (string, unit) Hashtbl.t =
  let h = Hashtbl.create 256 in
  let rec go (e : T.expr) =
    let atom (a : T.atom) =
      match a with
      | T.ADefRef d -> Hashtbl.replace h d.T.did_name ()
      | T.AVar _ | T.ALit _ -> ()
    in
    let atoms = List.iter atom in
    match e with
    | T.EApp (_, args) -> atoms args
    | T.ECallPtr (f, args) -> atom f; atoms args
    | T.EAtom a -> atom a
    | T.ELet (_, a, b) -> go a; go b
    | T.ELetRec (fns, b) -> List.iter (fun (fd : T.fn_def) -> go fd.T.fn_body) fns; go b
    | T.ECase (a, brs, d) ->
      atom a; List.iter (fun (br : T.branch) -> go br.T.br_body) brs; Option.iter go d
    | T.ETuple ats -> atoms ats
    | T.ERecord fl -> List.iter (fun (_, a) -> atom a) fl
    | T.EField (a, _) -> atom a
    | T.EUpdate (a, fl) -> atom a; List.iter (fun (_, x) -> atom x) fl
    | T.EAlloc (_, ats) | T.EStackAlloc (_, ats) -> atoms ats
    | T.EReuse (a, _, ats) -> atom a; atoms ats
    | T.EFree a | T.EIncRC a | T.EDecRC a | T.EAtomicIncRC a | T.EAtomicDecRC a -> atom a
    | T.ESeq (a, b) -> go a; go b
    | T.EAllocHole (t, _, ats, _) -> Option.iter atom t; atoms ats
    | T.ESetField (o, _, v) -> atom o; atom v
  in
  List.iter (fun (fd : T.fn_def) -> go fd.T.fn_body) m.T.tm_fns;
  h

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
  (* The invariant that keeps threading sound: nothing threaded may also be
     reachable indirectly.  Report violations rather than assuming. *)
  let refs = all_defrefs m in
  let leaked =
    List.filter (fun (k, _) -> Hashtbl.mem refs k) rows |> List.map fst
  in
  if leaked <> [] then
    Printf.eprintf
      "=== cap-passing: %d THREADED FUNCTIONS ALSO APPEAR AS ADefRef: %s ===\n"
      (List.length leaked) (String.concat ", " leaked);
  Printf.eprintf "=== cap-passing: %d of %d functions need a threaded capability ===\n"
    (List.length rows) (List.length m.T.tm_fns);
  List.iter (fun (k, v) -> Printf.eprintf "  %-52s %s\n" k (String.concat ", " v)) rows

(* ── the actor boundary ───────────────────────────────────────────────── *)

(** Capabilities [e] reaches: what it performs directly, plus what anything it
    calls needs.

    The callee half is the important one and was easy to get wrong. A
    dispatch's handlers are NOT inlined into it at this point in the pipeline —
    that happens later, in the optimizer — so at this point the body reads

      case $msg of Say($Say_s) -> Logger_Say(root_cap, $actor, $Say_s)

    i.e. a CALL to an already-threaded handler that the dispatch is supplying
    the ambient sentinel to. Scanning only for operations finds nothing, which
    is exactly what the first version did. *)
let caps_reached (need : (string, string list) Hashtbl.t) (e : T.expr) : string list =
  let acc = ref [] in
  let f = { calls = Hashtbl.create 8; ops = Hashtbl.create 8;
            unsafe = Hashtbl.create 8; toplevel = Hashtbl.create 8 } in
  scan f "$probe" StrSet.empty e;
  Hashtbl.iter (fun _ v -> acc := v @ !acc) f.ops;
  Hashtbl.iter
    (fun _ callees ->
       List.iter
         (fun c ->
            match Hashtbl.find_opt need c with
            | Some caps -> acc := caps @ !acc
            | None -> ())
         callees)
    f.calls;
  List.sort_uniq String.compare !acc

(** [actor_of_dispatch n] is the actor name when [n] is a dispatch function. *)
let actor_of_dispatch (n : string) : string option =
  let sfx = Tir_names.actor_dispatch_suffix in
  let ls = String.length sfx and ln = String.length n in
  if ln > ls && String.sub n (ln - ls) ls = sfx
  then Some (String.sub n 0 (ln - ls)) else None

(** The capabilities an actor's dispatch needs, sorted and de-duplicated;
    empty when [fd] is not a dispatch or reaches no capability.

    v1 handled exactly ONE capability and returned [None] for two or more, so
    an actor that logged AND read the clock got nothing captured at all.  Now
    every capability the dispatch reaches is captured, as one record of them
    built at the spawn site (see [thread]) — one shape for one capability and
    for many, so the two cannot disagree about WHICH capabilities an actor
    needs. *)
let dispatch_caps (need : (string, string list) Hashtbl.t) (fd : T.fn_def)
  : string list =
  match actor_of_dispatch fd.T.fn_name with
  | None -> []
  | Some _ -> caps_reached need fd.T.fn_body

(** The record of an actor's captured capabilities, as [(field, capability)]:
    one field per capability, named [cap_param_name c] (the `$cap_IO_Console`
    spelling the parameters already use), SORTED BY FIELD NAME — the
    [T.TRecord] invariant ([tir.ml]) that [Llvm_data.field_index_for] relies
    on to compute each projection's index.  Sorted here explicitly rather than
    inherited from [caps_reached]'s capability order: the field name swaps `.`
    for `_`, and `_` sorts after every capital letter, so a capability-sorted
    list is not field-sorted in general (`IO.A` < `IOB` but
    `$cap_IO_A` > `$cap_IOB`). *)
let caps_record_fields (caps : string list) : (string * string) list =
  List.sort (fun (a, _) (b, _) -> String.compare a b)
    (List.map (fun c -> (cap_param_name c, c)) caps)

let caps_record_ty (caps : string list) : T.ty =
  T.TRecord (List.map (fun (f, c) -> (f, cap_ty c)) (caps_record_fields caps))

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
let rec thread ?(dispatch = false) ?(spawn_caps = Hashtbl.create 1)
    (need : (string, string list) Hashtbl.t)
    (binds : (string * T.atom) list) (e : T.expr) : T.expr =
  let go = thread ~dispatch ~spawn_caps need binds in
  (* What this scope can supply for a capability: the enclosing function's own
     parameter, a `with_cap` mock, or — failing both — the ambient sentinel. *)
  let supply c =
    match List.assoc_opt c binds with Some a -> a | None -> ambient_atom c
  in
  match e with
  | T.EApp (v, [ cap_atom ]) when v.T.v_name = "cap_ops_empty" ->
    (* Resolve to the generated all-None base for the capability the argument
       carries.  A generated March function rather than a record built here:
       constructing it would mean re-deriving None's constructor type and
       duplicating lower's ty translation. *)
    (match cap_atom with
     | T.AVar mv ->
       (match mv.T.v_ty with
        | T.TCon ("Cap", [ T.TCon (c, []) ]) ->
          T.EApp ({ v with T.v_name = March_typecheck.Io_ops_gen.ops_empty_name c }, [])
        | _ -> e)
     | _ -> e)
  | T.EApp (v, args) when dispatch && cap_of_interceptable_op v.T.v_name <> None ->
    (* Route the operation through its generated wrapper, which consults the
       capability's dictionary and falls back to the operation itself. *)
    let cap = Option.get (cap_of_interceptable_op v.T.v_name) in
    let name = March_typecheck.Io_ops_gen.dispatch_name v.T.v_name in
    let v =
      match v.T.v_ty with
      | T.TFn (ps, r) -> { v with T.v_name = name; T.v_ty = T.TFn (cap_ty cap :: ps, r) }
      | _ -> { v with T.v_name = name }
    in
    T.EApp (v, supply cap :: args)
  | T.EApp (v, [ sup; ptr; T.AVar sf; idx; restart ])
    when v.T.v_name = "register_supervisor_child"
      && actor_of_spawn sf.T.v_name <> None && Hashtbl.mem need sf.T.v_name ->
    (* The respawn value for a child whose spawn glue now CARRIES capabilities
       (a supervisor nested under this one).  The runtime re-runs whatever it
       is handed with no arguments on every respawn — `march_respawn_child`
       reads the `$clo_wrap` pointer out of the closure cell and calls it with
       the cell as its only argument — so hand it a zero-argument closure that
       calls the glue with the capabilities in scope here, the same threaded
       call the supervised-child shape makes for the original spawn:

         let $respawn = letrec [ fn $respawn() = Mid_spawn($cap_c1, …) ] in $respawn
         in register_supervisor_child(sup, ptr, $respawn, idx, restart)

       Built the way lower's [ELam] case builds a lambda thunk, so Defun lifts
       it like any other; its free variables are exactly this glue's `$cap`
       parameters, which Defun captures and Perceus dups at the capture.  A
       glue that carries nothing keeps the static function reference — the
       cheapest thing to pass, and the shape every existing supervisor test
       compiles to.

       RC: every apply function drops the closure it is handed, and the
       runtime calls the SAME cell on every respawn, so `march_respawn_child`
       incs it before each call; without that the second respawn would be a
       use-after-free (`cap_mock_supervised_nested`'s third row). *)
    let name = Lower_state.fresh_name "respawn" in
    let fn_var =
      { T.v_name = name; T.v_ty = T.TFn ([], T.TPtr T.TUnit); T.v_lin = T.Unr }
    in
    let fd : T.fn_def =
      { T.fn_name = name; T.fn_params = []; T.fn_ret_ty = T.TPtr T.TUnit;
        T.fn_body = go (T.EApp (sf, [])); T.fn_kind = T.FnLambda }
    in
    T.ELet (fn_var, T.ELetRec ([ fd ], T.EAtom (T.AVar fn_var)),
            T.EApp (v, [ sup; ptr; T.AVar fn_var; idx; restart ]))
  | T.EApp (v, args) ->
    (match Hashtbl.find_opt need v.T.v_name with
     | None -> e
     | Some caps ->
       let extra = List.map supply caps in
       (* Keep the callee var's own type in step with its new arity: a stale
          TFn here would misreport the callee's shape to any later pass that
          reads it rather than the fn_def. *)
       let v =
         match v.T.v_ty with
         | T.TFn (ps, r) -> { v with T.v_ty = T.TFn (List.map cap_ty caps @ ps, r) }
         | _ -> v
       in
       T.EApp (v, extra @ args))
  (* Spawn-site capture.  Lower emits
       let $raw_actor = Name_spawn() in spawn($raw_actor)
     and `march_spawn` is what CREATES the actor's runtime metadata, so the
     capabilities have to be attached after it, not before:
       let $raw_actor  = Name_spawn() in
       let $pid        = spawn($raw_actor) in
       let $spawn_caps = { $cap_c1: <supply c1>, …, $cap_cn: <supply cn> } in
       set_actor_caps($raw_actor, $spawn_caps); $pid
     One record on the meta's single pointer regardless of how many
     capabilities the actor needs; a capability this site cannot supply is the
     ambient sentinel in its field, so a PARTIAL mock (Console mocked, Clock
     real) works.  The actor's dispatch reads it back — see [dispatch_caps]
     and the projection in [elaborate].

     RC: [needs_rc (TRecord _)] is false, so the record itself is never
     inc'd/dec'd — it is retained forever on the meta, matching the meta's own
     leak-don't-free discipline.  The +1 on each capability now comes from the
     record build (Perceus dups an owned copy of every field into it), NOT
     from the builtin's owned argument as it did for the bare pointer; that is
     what lets a mock outlive the `with_cap` scope that supplied it. *)
  | T.ELet (raw, (T.EApp (sf, []) as spawn_call), T.EApp (sp, [ T.AVar raw' ]))
    when sp.T.v_name = "spawn" && raw'.T.v_name = raw.T.v_name
      && (match actor_of_spawn sf.T.v_name with Some _ -> true | None -> false) ->
    let actor = Option.get (actor_of_spawn sf.T.v_name) in
    (* [go spawn_call], not [spawn_call]: a SUPERVISOR's spawn glue carries its
       children's capabilities as parameters (see [needed_caps]), so the call
       to it gains arguments here like any other elaborated callee — whether
       or not the supervisor's own dispatch needs anything. *)
    (match Hashtbl.find_opt spawn_caps actor with
     | None | Some [] -> T.ELet (raw, go spawn_call, T.EApp (sp, [ T.AVar raw ]))
     | Some caps ->
       let pid = { T.v_name = "$pid_cap"; T.v_ty = T.TPtr T.TUnit; T.v_lin = T.Unr } in
       let setter =
         { T.v_name = "set_actor_caps"; T.v_ty = T.TPtr T.TUnit; T.v_lin = T.Unr }
       in
       let fields = caps_record_fields caps in
       let caps_var =
         { T.v_name = "$spawn_caps"; T.v_ty = caps_record_ty caps; T.v_lin = T.Unr }
       in
       T.ELet (raw, go spawn_call,
         T.ELet (pid, T.EApp (sp, [ T.AVar raw ]),
           T.ELet (caps_var,
             T.ERecord (List.map (fun (f, c) -> (f, supply c)) fields),
             T.ESeq (T.EApp (setter, [ T.AVar raw; T.AVar caps_var ]),
                     T.EAtom (T.AVar pid))))))
  (* Supervised-child capture: the SECOND spawn shape, inside a supervisor's
     spawn glue (see [supervised_children]).  `march_spawn_supervised` creates
     the child's meta exactly as `march_spawn` does, so the record is attached
     right after it; the caps come from the glue's own parameters, i.e. from
     whatever the user's `spawn(Sup)` site supplied.  A child the runtime
     RESPAWNS after a crash goes through `march_respawn_child`, not through
     this glue; the runtime carries the record over to the replacement there.
     Kept distinct from the plain pattern above on purpose: they share
     [spawn_caps] (so they cannot disagree about which caps a child needs)
     and nothing else. *)
  | T.ELet (raw, (T.EApp (cs, []) as child_call),
            T.ELet (ptr, (T.EApp (ss, [ T.AVar raw' ]) as sup_call), rest))
    when ss.T.v_name = "spawn_supervised" && raw'.T.v_name = raw.T.v_name
      && (match actor_of_spawn cs.T.v_name with Some _ -> true | None -> false) ->
    let child = Option.get (actor_of_spawn cs.T.v_name) in
    (* [go child_call]: a child that is itself a supervisor carries ITS
       children's capabilities as parameters (see [scan]'s
       `register_supervisor_child` case), so its spawn call gains arguments
       here like the plain pattern's does.  Re-emitting it bare would be an
       arity mismatch that dies at runtime, not a compile error. *)
    let child_call = go child_call in
    (match Hashtbl.find_opt spawn_caps child with
     | None | Some [] -> T.ELet (raw, child_call, T.ELet (ptr, sup_call, go rest))
     | Some caps ->
       let setter =
         { T.v_name = "set_actor_caps"; T.v_ty = T.TPtr T.TUnit; T.v_lin = T.Unr }
       in
       let fields = caps_record_fields caps in
       let caps_var =
         { T.v_name = raw.T.v_name ^ "_caps"; T.v_ty = caps_record_ty caps; T.v_lin = T.Unr }
       in
       T.ELet (raw, child_call,
         T.ELet (ptr, sup_call,
           T.ELet (caps_var,
             T.ERecord (List.map (fun (f, c) -> (f, supply c)) fields),
             T.ESeq (T.EApp (setter, [ T.AVar raw; T.AVar caps_var ]),
                     go rest)))))
  | T.ELet (v, e1, e2) ->
    (* `with_cap(mock, fn _ -> body)`: inside that lambda, the capability is
       the MOCK rather than whatever the enclosing scope was supplying.  Lower
       emits the thunk as
         let v = letrec [lam] in lam  ...  with_cap(mock, v)
       so the lambda's fn_def is reachable from the let that binds it, and the
       capability is read off the mock's own type. *)
    let e1' =
      match (e1, List.assoc_opt v.T.v_name (with_cap_thunks e2)) with
      | (T.ELetRec (fns, inner), Some (cap, mock)) ->
        let binds' = (cap, mock) :: List.remove_assoc cap binds in
        T.ELetRec
          (List.map
             (fun (fd : T.fn_def) ->
                { fd with T.fn_body = thread ~dispatch ~spawn_caps need binds' fd.T.fn_body })
             fns,
           thread ~dispatch ~spawn_caps need binds' inner)
      | _ -> go e1
    in
    T.ELet (v, e1', go e2)
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

(** Every `with_cap(mock, thunk)` in [e], as [thunk_var -> (capability, mock)].

    The capability is read off the mock's own type rather than declared
    anywhere, which is what lets `with_cap` be an ordinary function call
    instead of new syntax. *)
and with_cap_thunks (e : T.expr) : (string * (string * T.atom)) list =
  let acc = ref [] in
  let rec go (e : T.expr) =
    (match e with
     | T.EApp (v, [ mock; T.AVar t ]) when v.T.v_name = "with_cap" ->
       let cap =
         match mock with
         | T.AVar mv ->
           (match mv.T.v_ty with
            | T.TCon ("Cap", [ T.TCon (c, []) ]) -> Some c
            | _ -> None)
         | _ -> None
       in
       (match cap with
        | Some c -> acc := (t.T.v_name, (c, mock)) :: !acc
        | None -> ())
     | _ -> ());
    match e with
    | T.ELet (_, a, b) | T.ESeq (a, b) -> go a; go b
    | T.ELetRec (fns, b) ->
      List.iter (fun (fd : T.fn_def) -> go fd.T.fn_body) fns; go b
    | T.ECase (_, brs, d) ->
      List.iter (fun (br : T.branch) -> go br.T.br_body) brs; Option.iter go d
    | T.EApp _ | T.ECallPtr _ | T.EAtom _ | T.ETuple _ | T.ERecord _
    | T.EField _ | T.EUpdate _ | T.EAlloc _ | T.EStackAlloc _ | T.EFree _
    | T.EIncRC _ | T.EDecRC _ | T.EAtomicIncRC _ | T.EAtomicDecRC _
    | T.EReuse _ | T.EAllocHole _ | T.ESetField _ -> ()
  in
  go e; !acc

(** [elaborate m] gives every function that performs interceptable IO an
    implicit capability parameter and threads it from its callers.

    THREADING ONLY: nothing yet consumes the parameters, so an elaborated
    program must behave exactly as it did before.  That is the point — it makes
    the whole test suite a check on arity changes flowing through Defun, Mono,
    Perceus and the CAS key, before any behaviour rides on them. *)
let elaborate ?(dispatch = false) (m : T.tir_module) : T.tir_module =
  let need = needed_caps m in
  let rts = roots m in
  Hashtbl.iter (fun k _ -> if Hashtbl.mem rts k then Hashtbl.remove need k)
    (Hashtbl.copy need);
  if Hashtbl.length need = 0 then m
  else
    (* Which capability each actor's dispatch needs, so a spawn site knows what
       to capture and the dispatch knows what to read back. *)
    let spawn_caps : (string, string list) Hashtbl.t = Hashtbl.create 8 in
    List.iter
      (fun (fd : T.fn_def) ->
         match actor_of_dispatch fd.T.fn_name, dispatch_caps need fd with
         | Some actor, (_ :: _ as caps) -> Hashtbl.replace spawn_caps actor caps
         | _ -> ())
      m.T.tm_fns;
    let changed = ref 0 in
    let fns =
      List.map
        (fun (fd : T.fn_def) ->
           let caps = Option.value ~default:[] (Hashtbl.find_opt need fd.T.fn_name) in
           if caps <> [] then incr changed;
           let binds = List.map (fun c -> (c, T.AVar (cap_var c))) caps in
           if March_typecheck.Io_ops_gen.is_dispatch_name fd.T.fn_name then fd
           else
             (* An actor's dispatch is entered from the scheduler, so its arity
                is frozen and it has no capability parameter to supply.  Read
                the record captured at the spawn site off the actor's runtime
                metadata instead, project one variable per capability out of
                it, and bind those for the body — the calls it makes to the
                threaded handlers then supply them instead of the sentinel:

                  let $caps_opt : Option({…}) = actor_caps($actor) in
                  let $caps : {…} = case $caps_opt of
                                      Some($r) -> $r
                                      None()   -> { $cap_c: root_cap, … } in
                  let $spawn_cap_c = $caps.$cap_c in …

                The read is NULL for any actor this pass did not capture for —
                a supervised child, a respawned one, anything spawned through a
                shape the rewrite does not match — and v1's bare pointer read
                that as the sentinel for free.  A record projection cannot, so
                the read is typed as the niche `Option` (`None` IS null) and
                matched exactly as the generated `cap_dict` wrappers match
                theirs; the `None` arm builds a record of sentinels, so the
                uncaptured actor keeps release behaviour instead of a wild
                field load.

                RC: `$caps` MUST be typed [TRecord] — [needs_rc] false — so
                Perceus never decs the retained record at scope end (a [TCon]
                here would be a use-after-free on the second message).  The
                `Some` payload moves into it without a dec of the scrutinee,
                the same shape the `cap_dict` wrappers already exercise; each
                projection is a borrowed-field var, dup'd when it escapes into
                a handler call and never dec'd locally. *)
             let (extra_binds, wrap) =
               match actor_of_dispatch fd.T.fn_name, dispatch_caps need fd with
               | Some actor, (_ :: _ as caps) when Hashtbl.mem spawn_caps actor ->
                 (match fd.T.fn_params with
                  | actor_param :: _ ->
                    let fields = caps_record_fields caps in
                    let rec_ty = caps_record_ty caps in
                    let opt_ty = T.TCon ("Option", [ rec_ty ]) in
                    let mk name ty = { T.v_name = name; T.v_ty = ty; T.v_lin = T.Unr } in
                    let caps_opt = mk "$caps_opt" opt_ty in
                    (* [TVar "_"] for the branch binder, as lower's own case
                       compilation does; the typed rebinding is the let. *)
                    let caps_some = mk "$caps_some" (T.TVar "_") in
                    let caps_var = mk "$caps" rec_ty in
                    let reader = mk "actor_caps" opt_ty in
                    let proj =
                      List.map
                        (fun (f, c) ->
                           (* `$cap_IO_Console` -> `$spawn_cap_IO_Console` *)
                           let pn = cap_param_name c in
                           (c, f, mk ("$spawn_" ^ String.sub pn 1 (String.length pn - 1))
                                    (cap_ty c)))
                        fields
                    in
                    (List.map (fun (c, _, v) -> (c, T.AVar v)) proj,
                     fun body ->
                       T.ELet (caps_opt, T.EApp (reader, [ T.AVar actor_param ]),
                         T.ELet (caps_var,
                           T.ECase (T.AVar caps_opt,
                             [ { T.br_tag = "Some"; T.br_vars = [ caps_some ];
                                 T.br_body = T.EAtom (T.AVar caps_some) };
                               { T.br_tag = "None"; T.br_vars = [];
                                 T.br_body =
                                   T.ERecord (List.map (fun (f, c) -> (f, ambient_atom c)) fields) } ],
                             Some (Lower_state.nonexhaustive_panic ())),
                           List.fold_right
                             (fun (_, f, v) acc -> T.ELet (v, T.EField (T.AVar caps_var, f), acc))
                             proj body)))
                  | [] -> ([], fun b -> b))
               | _ -> ([], fun b -> b)
             in
             let binds = extra_binds @ binds in
             { fd with
               T.fn_params = List.map cap_var caps @ fd.T.fn_params;
               T.fn_body = wrap (thread ~dispatch ~spawn_caps need binds fd.T.fn_body) })
        m.T.tm_fns
    in
    (* Report what was actually rewritten.  Without this the only evidence the
       pass ran is the absence of a difference, which is exactly what a pass
       that silently did nothing also looks like. *)
    if Sys.getenv_opt "MARCH_DUMP_CAP_PASSING" = Some "1" then
      Printf.eprintf "=== cap-passing: threaded %d functions ===\n" !changed;
    { m with T.tm_fns = fns }
