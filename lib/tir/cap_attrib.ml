(* Per-module capability attribution.  See cap_attrib.mli for why this is a
   pre-inline TIR pass rather than a codegen side effect, and for why
   transparent (stdlib) modules are seen through rather than reported. *)

module SSet = Set.Make (String)

(* March builtin name → capability.

   Consults [Typecheck.builtin_cap_table] (keyed by MARCH NAME) FIRST, then
   falls back to [Cap_symbols] (keyed by C SYMBOL) via
   [c_symbol_of_march_name] — NOT [mangle_extern]: the latter records into the
   marker accumulator, and an analysis that walks unreachable-at-emit code
   would mark capabilities the binary never references.

   The March-name lookup was added 2026-08-07 because the C-symbol route alone
   silently missed TEN capability-bearing builtins — every one of IO.Clock's,
   IO.Signal's and IO.Spawn's. [c_symbol_of_march_name] returns its argument
   UNCHANGED for a builtin with no [c_name] (a trampoline-lowered one like
   [task_spawn]), and the bare March name is not a key in [Cap_symbols], so the
   lookup quietly yielded [None] and attribution learned nothing.

   The symptom did not look like a table mismatch. `--cap-strict` reported
   "`IO.Spawn` is used but cannot be attributed to any module — it is reached
   only through indirect calls" on programs that call [task_spawn] directly and
   declare `needs IO.Spawn`; [Unattributed] simply had no better explanation to
   offer. Four of a 24-program sample failed that way, all parallel code, none
   fixable by declaring anything.

   The C-symbol fallback is still required: [Cap_symbols] also keys synthesized
   post-lowering symbols ([march_task_spawn_thunk]) that never appear as a
   March name. Both tables are live; [test_cap_attrib_agreement] asserts they
   agree for every capability-bearing builtin so a third one cannot drift in. *)
let cap_of_call (name : string) : string option =
  match List.assoc_opt name March_typecheck.Typecheck.builtin_cap_table with
  | Some cap -> Some cap
  | None ->
    March_caps.Cap_symbols.cap_of_symbol
      (Llvm_builtins.c_symbol_of_march_name name)

(* A builtin can also appear as a VALUE rather than a call — [apply1(file_read,
   p)] passes it as an atom, and only later does defun synthesize the apply
   wrapper that calls it.  Measured: without this, such a program emitted an
   IO.FileRead marker with NO owner row, so the module that handed out the
   capability escaped attribution entirely.  Charging it to the module that
   passes the value is right: that module is the one granting the authority. *)
let atom_cap (a : Tir.atom) : string option =
  match a with
  | Tir.AVar v -> cap_of_call v.Tir.v_name
  | Tir.ADefRef _ | Tir.ALit _ -> None

let add_atoms caps atoms =
  List.fold_left
    (fun acc a -> match atom_cap a with Some c -> SSet.add c acc | None -> acc)
    caps atoms

(* One walk collecting both halves: the capabilities this body reaches
   directly, and the functions it calls (for the reverse call graph). *)
let rec walk (caps, callees) (e : Tir.expr) =
  match e with
  | Tir.EApp (v, args) ->
    let n = v.Tir.v_name in
    let caps =
      match cap_of_call n with Some c -> SSet.add c caps | None -> caps
    in
    (add_atoms caps args, SSet.add n callees)
  | Tir.ELet (_, rhs, body) -> walk (walk (caps, callees) rhs) body
  | Tir.ESeq (a, b) -> walk (walk (caps, callees) a) b
  | Tir.ECase (scrut, branches, default) ->
    let acc =
      List.fold_left (fun a (br : Tir.branch) -> walk a br.Tir.br_body)
        (add_atoms caps [ scrut ], callees) branches
    in
    (match default with Some d -> walk acc d | None -> acc)
  (* A lambda lifted into an inner fn_def is still the enclosing module's
     code, so its uses belong to the same owner. *)
  | Tir.ELetRec (fns, body) ->
    let acc =
      List.fold_left (fun a (fd : Tir.fn_def) -> walk a fd.Tir.fn_body)
        (caps, callees) fns
    in
    walk acc body
  (* ECallPtr's CALLEE is not statically known — that is the residual gap the
     .mli documents — but its atoms are still scanned, so a builtin handed to
     it as an argument is attributed. *)
  | Tir.ECallPtr (f, args) -> (add_atoms caps (f :: args), callees)
  | Tir.EAtom a -> (add_atoms caps [ a ], callees)
  | Tir.ETuple atoms -> (add_atoms caps atoms, callees)
  | Tir.ERecord fields -> (add_atoms caps (List.map snd fields), callees)
  | Tir.EField (a, _) -> (add_atoms caps [ a ], callees)
  | Tir.EUpdate (a, fields) ->
    (add_atoms caps (a :: List.map snd fields), callees)
  | Tir.EAlloc (_, atoms) | Tir.EStackAlloc (_, atoms) ->
    (add_atoms caps atoms, callees)
  | Tir.EReuse (a, _, atoms) -> (add_atoms caps (a :: atoms), callees)
  | Tir.EAllocHole (_, atoms, _) -> (add_atoms caps atoms, callees)
  | Tir.ESetField (o, _, v) -> (add_atoms caps [ o; v ], callees)
  (* RC ops and EFree only ever carry an already-bound local, never a
     top-level function name, but scanning them costs nothing and keeps this
     match exhaustive-by-construction rather than by a catch-all — the shape
     that has repeatedly hidden a missed case in this codebase's cap walks. *)
  | Tir.EFree a | Tir.EIncRC a | Tir.EDecRC a
  | Tir.EAtomicIncRC a | Tir.EAtomicDecRC a ->
    (add_atoms caps [ a ], callees)

let attribute ?(transparent = fun _ -> false)
    ?(transparent_fns = fun _ -> false) (m : Tir.tir_module) :
    (string * string) list =
  (* lower.ml strips the entry file-module's name from its own declarations,
     so an unprefixed function is the entry module's.  Dependency modules
     keep their prefix (verified: @BigLib.load survives to emitted IR). *)
  let entry = if m.Tir.tm_name = "" then "main" else m.Tir.tm_name in
  (* [Handler_owner] first: a synthesized actor-handler name is BARE by
     contract (`Weeble_Zorp` — the spawn symbol and HCR manifest assert the
     short spelling), so deriving ownership from the name charges every
     nested module's handler to the entry module.  Lowering records the
     declaring module out-of-band; only then fall back to the name. *)
  let owner_of fn_name =
    match Handler_owner.owner_of fn_name with
    | Some o -> o
    | None ->
      (* An impl method's TIR name is the iface mangling
         `[Prefix.]Iface$Ty.method`.  Taking the last-dot prefix as the owner
         yielded the SYNTHETIC module `Iface$Ty` — which no `needs` line can
         declare for, so a correctly-declared program was unfixably rejected
         ("module `Save$Thing` uses `IO.FileWrite` ...").  The owner is what
         precedes the mangled segment: the module that declared the impl, or
         the entry module when nothing does. *)
      let n =
        if Tir_names.is_iface_mangled fn_name then
          match String.index_opt fn_name '$' with
          | Some j ->
            (match String.rindex_from_opt fn_name j '.' with
             | Some i -> String.sub fn_name 0 i
             | None -> "")
          | None -> fn_name
        else Hot_reload.module_of_name fn_name
      in
      (match n with "" -> entry | o -> o)
  in
  (* The entry module is the program itself; seeing through it would leave a
     capability with nowhere to land. *)
  let is_transparent owner = owner <> entry && transparent owner in
  (* Transparency is decided per FUNCTION, not only per owner-module, because
     the PRELUDE's functions are unprefixed — `println$String` names no module,
     so [owner_of] resolves it to the entry module and the module-level test
     can never see through it.  Before [transparent_fns], the console use
     inside the prelude's `println` wrapper was therefore charged to the ENTRY
     module no matter which nested module called it: `mod Outer` containing
     `mod Inner` (with `needs IO.Console`) whose function calls `println` drew
     "module `Outer` uses `IO.Console`" — a violation Inner's declaration
     could not satisfy, and Outer's would mask.  First diagnosed through the
     actor-handler route (the todo blamed the handler's bare name — that gap
     was real too, see [Handler_owner], but fixing it alone changed nothing
     because the capability sat one frame lower, in the wrapper).  The
     [transparent_fns] check deliberately ignores the entry guard above:
     prelude functions' owner IS the entry module, which is exactly why they
     need their own predicate. *)
  let see_through fn_name =
    transparent_fns fn_name || is_transparent (owner_of fn_name)
  in

  let direct : (string, SSet.t) Hashtbl.t = Hashtbl.create 64 in
  let callers : (string, string list) Hashtbl.t = Hashtbl.create 256 in
  let defined : (string, unit) Hashtbl.t = Hashtbl.create 256 in
  List.iter
    (fun (fn : Tir.fn_def) -> Hashtbl.replace defined fn.Tir.fn_name ())
    m.Tir.tm_fns;
  List.iter
    (fun (fn : Tir.fn_def) ->
       let caps, callees = walk (SSet.empty, SSet.empty) fn.Tir.fn_body in
       if not (SSet.is_empty caps) then
         Hashtbl.replace direct fn.Tir.fn_name caps;
       SSet.iter
         (fun callee ->
            if Hashtbl.mem defined callee then
              Hashtbl.replace callers callee
                (fn.Tir.fn_name
                 :: Option.value ~default:[] (Hashtbl.find_opt callers callee)))
         callees)
    m.Tir.tm_fns;

  (* Nearest non-transparent owner, walking the reverse call graph.  A
     dependency that reads a file through File.read is the responsible party;
     attributing it to the stdlib wrapper would report the same owner for
     every dependency in the program and answer nobody's question. *)
  let responsible_owners fn_name =
    if not (see_through fn_name) then [ owner_of fn_name ]
    else begin
      let seen = Hashtbl.create 16 in
      let found = ref SSet.empty in
      let rec go n =
        if not (Hashtbl.mem seen n) then begin
          Hashtbl.replace seen n ();
          List.iter
            (fun c ->
               if see_through c then go c
               else found := SSet.add (owner_of c) !found)
            (Option.value ~default:[] (Hashtbl.find_opt callers n))
        end
      in
      go fn_name;
      (* Nothing outside the transparent set reaches it — every caller is
         stdlib, or it is reached only indirectly.  Naming the stdlib module
         is then the honest answer rather than dropping the row. *)
      if SSet.is_empty !found then [ owner_of fn_name ]
      else SSet.elements !found
    end
  in

  let seen : (string * string, unit) Hashtbl.t = Hashtbl.create 32 in
  Hashtbl.iter
    (fun fn_name caps ->
       let owners = responsible_owners fn_name in
       SSet.iter
         (fun cap ->
            List.iter (fun o -> Hashtbl.replace seen (cap, o) ()) owners)
         caps)
    direct;
  Hashtbl.fold (fun k () acc -> k :: acc) seen []
  |> List.sort_uniq compare
