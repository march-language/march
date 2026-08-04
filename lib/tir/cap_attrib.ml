(* Per-module capability attribution.  See cap_attrib.mli for why this is a
   pre-inline TIR pass rather than a codegen side effect, and for why
   transparent (stdlib) modules are seen through rather than reported. *)

module SSet = Set.Make (String)

(* March builtin name → capability, via the same name→C-symbol table codegen
   uses.  Resolved through [c_symbol_of_march_name], NOT [mangle_extern]:
   the latter records into the marker accumulator, and an analysis that
   walks unreachable-at-emit code would mark capabilities the binary never
   references. *)
let cap_of_call (name : string) : string option =
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
  (* RC ops and EFree only ever carry an already-bound local, never a
     top-level function name, but scanning them costs nothing and keeps this
     match exhaustive-by-construction rather than by a catch-all — the shape
     that has repeatedly hidden a missed case in this codebase's cap walks. *)
  | Tir.EFree a | Tir.EIncRC a | Tir.EDecRC a
  | Tir.EAtomicIncRC a | Tir.EAtomicDecRC a ->
    (add_atoms caps [ a ], callees)

let attribute ?(transparent = fun _ -> false) (m : Tir.tir_module) :
    (string * string) list =
  (* lower.ml strips the entry file-module's name from its own declarations,
     so an unprefixed function is the entry module's.  Dependency modules
     keep their prefix (verified: @BigLib.load survives to emitted IR). *)
  let entry = if m.Tir.tm_name = "" then "main" else m.Tir.tm_name in
  let owner_of fn_name =
    match Hot_reload.module_of_name fn_name with "" -> entry | o -> o
  in
  (* The entry module is the program itself; seeing through it would leave a
     capability with nowhere to land. *)
  let is_transparent owner = owner <> entry && transparent owner in

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
    if not (is_transparent (owner_of fn_name)) then [ owner_of fn_name ]
    else begin
      let seen = Hashtbl.create 16 in
      let found = ref SSet.empty in
      let rec go n =
        if not (Hashtbl.mem seen n) then begin
          Hashtbl.replace seen n ();
          List.iter
            (fun c ->
               let o = owner_of c in
               if is_transparent o then go c else found := SSet.add o !found)
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
