(** TIR well-formedness verifier (observability plan A1,
    specs/plans/incremental-codegen-cas-plan.md §6).

    Passes trust each other; nothing between them could say "this TIR is
    malformed" until codegen tripped over it, or did not. [check] is that
    statement for one stage's module. It is installed as the [snap] observer
    of [Contract_pipeline.run] under [--verify-tir] / [MARCH_VERIFY_TIR=1], so
    it sees the module after every pass (and after every inner [Opt] pass),
    and it is always on in the TIR snapshot harness and the hand-rolled
    pipelines in test/test_codegen.ml.

    The shape follows [Policy_dce.audit]: a list of [(fn_name, message)], empty
    when the module is well-formed; each message names the stage, the
    construct and the violated invariant.

    {1 Check 1: scoping and references (this file)}

    - every [AVar] is bound: a parameter, a [let], a case-branch binder or an
      enclosing [ELetRec] function, or else a global the emitter would resolve
      (a module function, an extern, a builtin, a [march_] runtime symbol);
    - every [EApp] callee is in [tm_fns], [tm_externs], [Builtin_table], a
      [march_] runtime symbol, a local binding, or (for the REPL) a function a
      previous fragment compiled. The emitter's unqualified fallback (a bare
      [base64_encode] for [Crypto.base64_encode], see
      [Llvm_toplevel.emit_module]) is honoured, with the same exclusion of
      interface-mangled names. A bare interface-method name is also accepted
      at every stage: before mono it is legitimately unresolved, and after
      mono an unresolved one is a user error the emitter diagnoses;
    - every [ADefRef] resolves: by content hash when [def_hashes] (hash ->
      fn name) is given, else by [did_name]. (Nothing produces [ADefRef] yet;
      the check exists so the first producer is held to it.);
    - an [ECallPtr] callee has a function or pointer type (or an erased
      [TVar] / closure struct);
    - no two [fn_def]s share a name (from [tir-mono] on: before it a program
      fn may shadow a generic prelude fn of the same bare name).

    {1 Check 2: type consistency ([check_types])}

    From [tir-mono] on, where every type a pass relies on is concrete.  Each
    rule fires only on a mismatch that changes the machine code, never on a
    type difference codegen tolerates (an erased [TVar], a closure behind a
    pointer, a named record against its structure):

    - a call to a module function passes exactly its parameter count;
    - with the kind table (from [tir-defun] on), each argument has the same
      machine representation as its parameter ({!Kind.layout_of}: immediate,
      float, pointer, unboxed aggregate, SIMD vector). Closure apply
      functions are exempt: they share one boxed ABI by design
      ([Tir_names.is_apply_fn]);
    - a case branch binds exactly as many variables as its constructor has
      fields, when the scrutinee's variant is known;
    - a projected field exists in the record or closure type;
    - no source-named type variable ([a]) survives monomorphisation in an
      ordinary function's signature; the typechecker's own [_<id>] variables
      are erased by design.

    {1 Check 3: RC balance ({!Tir_verify_rc})}

    Under its own switch for now ([rc_enabled]).  At [tir-perceus], given the
    borrow map and kind table Perceus used: no
    path consumes or releases a reference it does not hold, or reads an
    object after its last reference is gone.  Leaks only with [~rc_leaks]
    (or [MARCH_VERIFY_TIR_LEAKS=1]).

    Checks 4-5 (repr, pass contracts) are not built. *)

module StringSet = Set.Make (String)

exception Failed of string * (string * string) list
(** [Failed (stage, findings)], raised by [enforce]. *)

let enabled_by_env : bool Lazy.t =
  lazy (match Sys.getenv_opt "MARCH_VERIFY_TIR" with
        | Some ("" | "0") | None -> false
        | Some _ -> true)

(** Set by [--verify-tir]. *)
let enabled_flag = ref false

let enabled () = !enabled_flag || Lazy.force enabled_by_env

(** Check 3 (RC balance) is its own switch for now: [--verify-tir-rc] /
    [MARCH_VERIFY_TIR_RC=1] (each implies the verifier).  It found real
    Perceus bugs in stdlib code every program compiles
    (specs/todos/2026-10-07-perceus-releases-parent-before-field-use.md);
    until they are fixed, putting it under plain [--verify-tir] would fail
    every verified build. *)
let rc_flag = ref false
let rc_by_env : bool Lazy.t =
  lazy (match Sys.getenv_opt "MARCH_VERIFY_TIR_RC" with
        | Some ("" | "0") | None -> false | Some _ -> true)
let rc_enabled () = !rc_flag || Lazy.force rc_by_env
let enabled () = enabled () || rc_enabled ()

(* Stages before monomorphisation, where a bare interface-method call
   ([show(x)]) is legitimately unresolved. *)
let pre_mono_stage stage =
  List.mem stage [ "tir-lower"; "tir-trmc" ]

(* Callee names the emitter handles in a dedicated [emit_expr] arm BEFORE
   its general known-callee test ([Llvm_calls.is_known_callee]), and which
   [Builtin_table] therefore does not list: the short-circuit operators
   ([llvm_emit.ml] `&&`/`||` arms), the SIMD family decoded from the name
   ([Llvm_emit_simd.decode_simd_call]) and dispatch sentinels
   ([Dispatch_registry.is_sentinel]). *)
let emitter_arm name =
  name = "&&" || name = "||"
  || Llvm_emit_simd.decode_simd_call name <> None
  || Llvm_emit_nmap.decode_nmap_inline_call name <> None
  || Llvm_emit_nmap.decode_nfold_inline_call name <> None
  (* NativeArray sum(map) fusion (phase C) landed after check 1 and added
     this family; the emitter decodes it in its own arm too. *)
  || Llvm_emit_nmap.decode_nsummap_inline_call name <> None
  || Dispatch_registry.is_sentinel name
  (* @[vectorize] sentinels stamped by Vectorize_mark and consumed by
     Vectorize_check before emission *)
  || Vectorize_check.marker_severity name <> None

(* JS-only stdlib modules (Js.Dom, Js.Canvas) are not loaded for a native
   build, but a native program may still name them in code that typechecks
   and is never reached (test/native/js_dom_available.march pins exactly
   that); DCE removes it before emission, and a reachable call still fails
   there as [Llvm_calls.Unknown_callee]. *)
let js_only_name name =
  String.length name > 3 && String.sub name 0 3 = "Js."

(* The `derive Json` interface's methods.  [Lower] does not register them in
   [iface_methods] (the interface is synthesized, not declared), and a
   generic function may call one bare -- stdlib's JsonStream.typed_events
   calls `from_json` -- which mono resolves to the caller's derived impl
   ([Json$T.from_json]) when the code is reachable (measured: a compiled
   program calling JsonStream.each_typed on a derived record builds and
   runs). *)
let derived_iface_methods = [ "to_json"; "from_json"; "from_json_events" ]


(* ── Check 2: type consistency ─────────────────────────────────────── *)

let atom_ty (a : Tir.atom) : Tir.ty option =
  match a with
  | Tir.AVar v -> Some v.Tir.v_ty
  | Tir.ALit (March_ast.Ast.LitInt _) -> Some Tir.TInt
  | Tir.ALit (March_ast.Ast.LitFloat _) -> Some Tir.TFloat
  | Tir.ALit (March_ast.Ast.LitString _) -> Some Tir.TString
  | Tir.ALit (March_ast.Ast.LitBool _) -> Some Tir.TBool
  | Tir.ALit _ | Tir.ADefRef _ -> None

(** The representation class a value is passed in, or [None] when it is
    erased (decided at run time). *)
let repr_class (k : Kind.table) (t : Tir.ty) : string option =
  (* `()` is unit whether spelled [TUnit] or the empty tuple ([Show$Unit.show]
     is called with an empty-tuple atom). *)
  let t = match t with Tir.TTuple [] -> Tir.TUnit | t -> t in
  match (Kind.of_ty k t).Kind.layout with
  | Kind.Erased -> None
  | Kind.Imm -> Some "an immediate word"
  | Kind.Flt -> Some "a native float"
  | Kind.Heap | Kind.Cell -> Some "a heap pointer"
  | Kind.Agg s -> Some ("the unboxed aggregate " ^ s)
  | Kind.Vec n -> Some (Printf.sprintf "a %d-lane vector" n)

let last_segment s =
  match String.rindex_opt s '.' with
  | Some i -> String.sub s (i + 1) (String.length s - i - 1)
  | None -> s

(* A source-named type variable ([a], from an annotation).  The
   typechecker's own variables ([_53272]) and lowering's unknown ([_]) are
   erased by design when nothing pins them: mono defaults only some of them
   ([Mono.default_residual_in_subst]), and a corpus sweep found them in
   ordinary stdlib signatures everywhere. *)
let rec has_named_tvar (t : Tir.ty) =
  match t with
  | Tir.TVar n -> String.length n > 0 && n.[0] <> '_'
  | Tir.TTuple ts -> List.exists has_named_tvar ts
  | Tir.TRecord fs -> List.exists (fun (_, t) -> has_named_tvar t) fs
  | Tir.TCon (_, ts) -> List.exists has_named_tvar ts
  | Tir.TFn (ps, r) -> List.exists has_named_tvar ps || has_named_tvar r
  | Tir.TPtr t -> has_named_tvar t
  | _ -> false

let check_types ~report ~(k_table : Kind.table option) (m : Tir.tir_module) =
  let fns = Hashtbl.create 256 in
  List.iter (fun (fd : Tir.fn_def) -> Hashtbl.replace fns fd.Tir.fn_name fd) m.Tir.tm_fns;
  let variants = Hashtbl.create 64 and records = Hashtbl.create 64
  and closures = Hashtbl.create 64 in
  (* Two modules may each define a type with the same short name (the
     collision set, [Collision_set]); a TIR type reference then does not say
     which, so a name defined more than once is not checked. *)
  let defs = Hashtbl.create 64 in
  List.iter (function
      | Tir.TDVariant (n, _) | Tir.TDRecord (n, _) | Tir.TDClosure (n, _) ->
        let k = last_segment n in
        Hashtbl.replace defs k (1 + Option.value ~default:0 (Hashtbl.find_opt defs k)))
    m.Tir.tm_types;
  (* by short name: a colliding type is registered qualified ([HttpServer.Conn])
     while a reference to it may say only [Conn] *)
  let unique n = Hashtbl.find_opt defs (last_segment n) = Some 1 in
  List.iter (function
      | Tir.TDVariant (n, ctors) when unique n -> Hashtbl.replace variants n ctors
      | Tir.TDRecord (n, fs) when unique n -> Hashtbl.replace records n fs
      | Tir.TDClosure (n, tys) when unique n -> Hashtbl.replace closures n tys
      | _ -> ())
    m.Tir.tm_types;
  let ty = Pp.string_of_ty in
  let check_call fn env (f : Tir.var) args =
    if not (StringSet.mem f.Tir.v_name env) then
      match Hashtbl.find_opt fns f.Tir.v_name with
      | None -> ()
      | Some callee ->
        let np = List.length callee.Tir.fn_params and na = List.length args in
        if np <> na then
          report fn (Printf.sprintf "call to `%s` passes %d argument(s); it takes %d"
                       f.Tir.v_name na np)
        else
          match k_table with
          | Some k when not (Tir_names.is_apply_fn callee.Tir.fn_name)
                     && callee.Tir.fn_kind <> Tir.FnApply ->
            List.iteri (fun i ((p : Tir.var), a) ->
                match atom_ty a with
                | None -> ()
                | Some at ->
                  match repr_class k p.Tir.v_ty, repr_class k at with
                  | Some pc, Some ac when pc <> ac ->
                    report fn (Printf.sprintf
                                 "argument %d of `%s` is %s (`%s`), but the parameter `%s` \
                                  is %s (`%s`)"
                                 (i + 1) f.Tir.v_name ac (ty at) p.Tir.v_name pc (ty p.Tir.v_ty))
                  | _ -> ())
              (List.combine callee.Tir.fn_params args)
          | _ -> ()
  in
  let check_case fn (scrut : Tir.atom) (branches : Tir.branch list) =
    match atom_ty scrut with
    | Some (Tir.TCon (tn, _)) ->
      (match Hashtbl.find_opt variants tn with
       | None -> ()
       | Some ctors ->
         List.iter (fun (b : Tir.branch) ->
             let want = last_segment b.Tir.br_tag in
             match List.filter (fun (c, _) -> last_segment c = want) ctors with
             | [ (c, args) ] ->
               let n = List.length b.Tir.br_vars and k = List.length args in
               if n <> k then
                 report fn (Printf.sprintf
                              "case branch `%s` binds %d variable(s); constructor `%s` of \
                               `%s` has %d field(s)" b.Tir.br_tag n c tn k)
             | _ -> ())
           branches)
    | _ -> ()
  in
  let check_field fn (a : Tir.atom) field =
    let missing kind tname =
      report fn (Printf.sprintf "field `%s` is projected from %s `%s`, which has no such field"
                   field kind tname) in
    match atom_ty a with
    | Some (Tir.TRecord fs) when not (List.mem_assoc field fs) ->
      missing "the record" (ty (Tir.TRecord fs))
    | Some (Tir.TCon (tn, _)) ->
      (match Hashtbl.find_opt records tn with
       | Some fs when not (List.mem_assoc field fs) -> missing "the record type" tn
       | Some _ -> ()
       | None ->
         match Hashtbl.find_opt closures tn with
         | Some tys when Tir_names.is_fv_field field ->
           let idx = int_of_string_opt (String.sub field 3 (String.length field - 3)) in
           (match idx with
            | Some i when i < 1 || i >= List.length tys -> missing "the closure struct" tn
            | _ -> ())
         | _ -> ())
    | _ -> ()
  in
  let rec walk fn env (e : Tir.expr) =
    match e with
    | Tir.EApp (f, args) -> check_call fn env f args
    | Tir.ECase (scrut, branches, default) ->
      check_case fn scrut branches;
      List.iter (fun (b : Tir.branch) ->
          walk fn (List.fold_left (fun s (v : Tir.var) -> StringSet.add v.Tir.v_name s)
                     env b.Tir.br_vars) b.Tir.br_body) branches;
      Option.iter (walk fn env) default
    | Tir.EField (a, f) -> check_field fn a f
    | Tir.ELet (v, rhs, body) -> walk fn env rhs; walk fn (StringSet.add v.Tir.v_name env) body
    | Tir.ELetRec (fds, body) ->
      let env = List.fold_left (fun s (fd : Tir.fn_def) -> StringSet.add fd.Tir.fn_name s) env fds in
      List.iter (fun (fd : Tir.fn_def) ->
          walk fn (List.fold_left (fun s (v : Tir.var) -> StringSet.add v.Tir.v_name s)
                     env fd.Tir.fn_params) fd.Tir.fn_body) fds;
      walk fn env body
    | Tir.ESeq (a, b) -> walk fn env a; walk fn env b
    | _ -> ()
  in
  List.iter (fun (fd : Tir.fn_def) ->
      (* Drop glue ([__drop$List_Va]) is synthesised per type, erased
         element included; it is not a specialisation mono failed to finish. *)
      if fd.Tir.fn_kind = Tir.FnNormal
         && not (String.starts_with ~prefix:Tir_names.drop_fn_prefix fd.Tir.fn_name)
         && (List.exists (fun (v : Tir.var) -> has_named_tvar v.Tir.v_ty) fd.Tir.fn_params
             || has_named_tvar fd.Tir.fn_ret_ty) then
        report fd.Tir.fn_name
          (Printf.sprintf "a named type variable survived monomorphisation in the \
                           signature (%s) -> %s"
             (String.concat ", " (List.map (fun (v : Tir.var) -> ty v.Tir.v_ty) fd.Tir.fn_params))
             (ty fd.Tir.fn_ret_ty));
      let env = List.fold_left (fun s (v : Tir.var) -> StringSet.add v.Tir.v_name s)
          StringSet.empty fd.Tir.fn_params in
      walk fd.Tir.fn_name env fd.Tir.fn_body)
    m.Tir.tm_fns

let check ~(stage : string) ?(borrow_map : Borrow.borrow_map option)
    ?(k_table : Kind.table option) ?(rc = rc_enabled ()) ?rc_leaks
    ?(iface_methods : (string, (string * string) list) Hashtbl.t option)
    ?(def_hashes : (string, string) Hashtbl.t option)
    ?(known_fn : string -> bool = fun _ -> false)
    (m : Tir.tir_module) : (string * string) list =
  let findings = ref [] in
  let report fn msg =
    findings := (fn, Printf.sprintf "[%s] %s" stage msg) :: !findings in
  let top = Hashtbl.create 256 in
  List.iter (fun (fd : Tir.fn_def) -> Hashtbl.replace top fd.Tir.fn_name ()) m.Tir.tm_fns;
  let externs = Hashtbl.create 32 in
  List.iter (fun (ed : Tir.extern_decl) ->
      Hashtbl.replace externs ed.Tir.ed_march_name ())
    m.Tir.tm_externs;
  (* The emitter's unqualified fallback: last dot-segment -> first fn with it. *)
  let unqualified = Hashtbl.create 256 in
  List.iter (fun (fd : Tir.fn_def) ->
      let n = fd.Tir.fn_name in
      match String.rindex_opt n '.' with
      | Some i when not (Tir_names.is_iface_mangled n) ->
        let unq = String.sub n (i + 1) (String.length n - i - 1) in
        if not (Hashtbl.mem unqualified unq) then Hashtbl.replace unqualified unq ()
      | _ -> ())
    m.Tir.tm_fns;
  let is_iface name =
    match iface_methods with Some h -> Hashtbl.mem h name | None -> false in
  let pre_mono = pre_mono_stage stage in
  (* Bare interface-method names: the method part of an interface-mangled
     fn ([Json$Point.from_json] -> [from_json]).  Before mono a call may still
     name the method bare (return-position dispatch); mono resolves it. *)
  let iface_suffixes = Hashtbl.create 64 in
  List.iter (fun (fd : Tir.fn_def) ->
      let n = fd.Tir.fn_name in
      if Tir_names.is_iface_mangled n then
        match String.rindex_opt n '.' with
        | Some i ->
          let sfx = String.sub n (i + 1) (String.length n - i - 1) in
          (* a further-specialised impl ([show$List_Int]) keeps the bare stem *)
          let stem = match String.index_opt sfx '$' with
            | Some j -> String.sub sfx 0 j | None -> sfx in
          Hashtbl.replace iface_suffixes stem ()
        | None -> ())
    m.Tir.tm_fns;
  let global_known name =
    Hashtbl.mem top name || Hashtbl.mem externs name
    || Hashtbl.mem unqualified name
    || Tir_names.has_runtime_prefix name
    || Builtin_table.is_builtin name
    || known_fn name
    || emitter_arm name
    || js_only_name name
    (* An interface-method call left unresolved is a USER error the emitter
       reports with a proper diagnostic ([fail_if_unresolved_iface_method],
       the missing-JsonTo-impl message); the verifier must not preempt it
       with an internal-error exit, so these names are accepted at every
       stage, not only before mono. *)
    || is_iface name || Hashtbl.mem iface_suffixes name
    || List.mem name derived_iface_methods
  in
  (* ── duplicate definitions ──
     From mono on only: before it, an entry-module fn may share a bare name
     with a generic prelude fn ([head], [unwrap], [inspect]); the program's
     own definition shadows the prelude's and mono keeps exactly one
     (measured: a user `head` returning 42 wins, interpreted and compiled). *)
  let seen = Hashtbl.create 256 in
  if not pre_mono then List.iter (fun (fd : Tir.fn_def) ->
      if Hashtbl.mem seen fd.Tir.fn_name then
        report fd.Tir.fn_name
          (Printf.sprintf "two top-level fn_defs are named `%s`" fd.Tir.fn_name)
      else Hashtbl.replace seen fd.Tir.fn_name ())
    m.Tir.tm_fns;
  (* ── scoping ── *)
  let rec ty_is_callable = function
    | Tir.TFn _ | Tir.TPtr _ | Tir.TVar _ -> true
    | Tir.TCon (_, _) -> true   (* a defun closure struct is a TCon *)
    | Tir.TRecord _ | Tir.TTuple _ -> false
    | Tir.TInt | Tir.TFloat | Tir.TBool | Tir.TString | Tir.TUnit -> false
  and check_atom fn env (a : Tir.atom) =
    match a with
    | Tir.AVar v ->
      if not (StringSet.mem v.Tir.v_name env || global_known v.Tir.v_name) then
        report fn (Printf.sprintf "variable `%s` is not bound (no parameter, \
                                   let, branch binder or enclosing letrec \
                                   binds it, and it is not a module function, \
                                   extern or builtin)" v.Tir.v_name)
    | Tir.ADefRef d ->
      let ok =
        match def_hashes with
        | Some h -> (match Hashtbl.find_opt h d.Tir.did_hash with
            | Some n -> Hashtbl.mem top n
            | None -> false)
        | None -> Hashtbl.mem top d.Tir.did_name
      in
      if not ok then
        report fn (Printf.sprintf "ADefRef `%s` (%s) resolves to no fn_def"
                     d.Tir.did_name d.Tir.did_hash)
    | Tir.ALit _ -> ()
  and check_expr fn env (e : Tir.expr) =
    let atoms = List.iter (check_atom fn env) in
    match e with
    | Tir.EAtom a -> check_atom fn env a
    | Tir.EApp (f, args) ->
      if not (StringSet.mem f.Tir.v_name env || global_known f.Tir.v_name) then
        report fn (Printf.sprintf "call to `%s`, which is not a function in \
                                   tm_fns, an extern, a builtin or a local \
                                   binding" f.Tir.v_name);
      atoms args
    | Tir.ECallPtr (callee, args) ->
      check_atom fn env callee;
      (match callee with
       | Tir.AVar v when not (ty_is_callable v.Tir.v_ty) ->
         report fn (Printf.sprintf "indirect call through `%s`, whose type `%s` \
                                    is not a function or pointer"
                      v.Tir.v_name (Tir.show_ty v.Tir.v_ty))
       | Tir.ALit _ ->
         report fn "indirect call through a literal"
       | _ -> ());
      atoms args
    | Tir.ELet (v, rhs, body) ->
      check_expr fn env rhs;
      check_expr fn (StringSet.add v.Tir.v_name env) body
    | Tir.ELetRec (fns, body) ->
      let env' =
        List.fold_left (fun s (fd : Tir.fn_def) -> StringSet.add fd.Tir.fn_name s)
          env fns in
      List.iter (fun (fd : Tir.fn_def) -> check_fn ~env:env' fd) fns;
      check_expr fn env' body
    | Tir.ECase (scrut, branches, default) ->
      check_atom fn env scrut;
      List.iter (fun (b : Tir.branch) ->
          let env' =
            List.fold_left (fun s (v : Tir.var) -> StringSet.add v.Tir.v_name s)
              env b.Tir.br_vars in
          check_expr fn env' b.Tir.br_body)
        branches;
      Option.iter (check_expr fn env) default
    | Tir.ETuple xs | Tir.EAlloc (_, xs) | Tir.EStackAlloc (_, xs) -> atoms xs
    | Tir.ERecord fs -> atoms (List.map snd fs)
    | Tir.EField (a, _) -> check_atom fn env a
    | Tir.EUpdate (a, fs) -> check_atom fn env a; atoms (List.map snd fs)
    | Tir.EFree a | Tir.EIncRC a | Tir.EDecRC a
    | Tir.EAtomicIncRC a | Tir.EAtomicDecRC a -> check_atom fn env a
    | Tir.EReuse (tok, _, xs) -> check_atom fn env tok; atoms xs
    | Tir.ESeq (a, b) -> check_expr fn env a; check_expr fn env b
    | Tir.EAllocHole (tok, _, xs, _) -> Option.iter (check_atom fn env) tok; atoms xs
    | Tir.ESetField (o, _, v) -> check_atom fn env o; check_atom fn env v
  and check_fn ~env (fd : Tir.fn_def) =
    let env =
      List.fold_left (fun s (v : Tir.var) -> StringSet.add v.Tir.v_name s)
        env fd.Tir.fn_params in
    check_expr fd.Tir.fn_name env fd.Tir.fn_body
  in
  List.iter (check_fn ~env:StringSet.empty) m.Tir.tm_fns;
  if not pre_mono then check_types ~report ~k_table m;
  (* Check 3 (RC balance, lib/tir/tir_verify_rc.ml): at tir-perceus only,
     with the borrow map and kind table Perceus itself used. *)
  let rc =
    match stage, borrow_map, k_table with
    | "tir-perceus", Some borrow_map, Some k_table when rc ->
      Tir_verify_rc.check ~stage ?leaks:rc_leaks ~k_table ~borrow_map m
    | _ -> [] in
  List.rev !findings @ rc

let render ~stage (findings : (string * string) list) : string =
  Printf.sprintf "TIR verifier: %d finding(s) after %s:\n%s" (List.length findings) stage
    (String.concat "\n"
       (List.map (fun (fn, msg) -> Printf.sprintf "  in `%s`: %s" fn msg) findings))

let () =
  Printexc.register_printer (function
    | Failed (stage, findings) -> Some (render ~stage findings)
    | _ -> None)

(** Run [check] and raise [Failed] on any finding. *)
let enforce ~stage ?borrow_map ?k_table ?rc ?rc_leaks ?iface_methods ?def_hashes ?known_fn m =
  match check ~stage ?borrow_map ?k_table ?rc ?rc_leaks ?iface_methods ?def_hashes ?known_fn m with
  | [] -> ()
  | findings -> raise (Failed (stage, findings))
