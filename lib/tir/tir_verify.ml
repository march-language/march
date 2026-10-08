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

    Checks 2-5 (types, RC balance, repr, pass contracts) are separate PRs;
    [borrow_map] and [k_table] are accepted now so their call sites do not
    change then. *)

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


let check ~(stage : string) ?borrow_map:(_ : Borrow.borrow_map option)
    ?k_table:(_ : Kind.table option)
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
  List.rev !findings

let render ~stage (findings : (string * string) list) : string =
  Printf.sprintf "TIR verifier: %d finding(s) after %s:\n%s" (List.length findings) stage
    (String.concat "\n"
       (List.map (fun (fn, msg) -> Printf.sprintf "  in `%s`: %s" fn msg) findings))

let () =
  Printexc.register_printer (function
    | Failed (stage, findings) -> Some (render ~stage findings)
    | _ -> None)

(** Run [check] and raise [Failed] on any finding. *)
let enforce ~stage ?borrow_map ?k_table ?iface_methods ?def_hashes ?known_fn m =
  match check ~stage ?borrow_map ?k_table ?iface_methods ?def_hashes ?known_fn m with
  | [] -> ()
  | findings -> raise (Failed (stage, findings))
