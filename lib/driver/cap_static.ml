(* The capability checks that run on lowered TIR: the module `needs`
   ceiling ([Cap_attrib] + [March_caps.Cap_ceiling]) and host scopes on
   IO.NetConnect ([Net_scope.check]).

   Lifted out of bin/main.ml's compile arm (ocap phase 3,
   specs/plans/2026-11-10-ocap-p3-checks-plan.md) so every mode runs the same
   implementation: the compile path calls [host_scope_findings] /
   [ceiling_findings] on the TIR it already has; --check, the interpreter, the
   REPL and `march check` call [check_program], which lowers on demand.  The
   helpers below moved here verbatim; bin/main.ml aliases them. *)

(** Qualified names of the modules that are USER code: a [DMod] whose span is a
    real file outside the stdlib root (stdlib modules carry a placeholder span).
    Transparency for the capability ceiling is decided by this, never by a
    module's NAME: a user module called `Yaml` is not the stdlib's. *)
let user_module_names (decls : March_ast.Ast.decl list) : (string, unit) Hashtbl.t =
  let seen = Hashtbl.create 16 in
  let rec go prefix ds =
    List.iter
      (function
        | March_ast.Ast.DMod (name, _, inner, sp) ->
          let q =
            if prefix = "" then name.March_ast.Ast.txt
            else prefix ^ "." ^ name.March_ast.Ast.txt
          in
          let f = sp.March_ast.Ast.file in
          if f <> March_ast.Ast.dummy_span.March_ast.Ast.file
             && not (March_typecheck.Typecheck_builtins.file_is_stdlib f) then
            Hashtbl.replace seen q ();
          go q inner
        | _ -> ())
      ds
  in
  go "" decls;
  seen

(** The module names a batch of stdlib declarations defines.

    Feeds [Cap_attrib.attribute]'s [~transparent] set, so a capability reached
    through a stdlib wrapper is attributed to the dependency that called the
    wrapper rather than to the wrapper. Derived from the declarations actually
    loaded — like [stdlib_span_files] — rather than from a hand-maintained
    name list, which is exactly the thing that drifts (see the correction
    history on [Resolver.stdlib_module_names]).

    [DMod] is the only declaration form that introduces a module name, so the
    catch-all below cannot hide one; nested modules are reached through
    [DMod]'s own inner list. Note prelude.march is deliberately unwrapped into
    global scope by [load_stdlib_file], so its members are bare-named and
    invisible here — a capability used only by a prelude function is
    attributed to the entry module. *)
let stdlib_module_names (decls : March_ast.Ast.decl list) : string list =
  let seen = Hashtbl.create 64 in
  let rec go prefix ds =
    List.iter
      (function
        | March_ast.Ast.DMod (name, _, inner, _) ->
          let name = name.March_ast.Ast.txt in
          let q = if prefix = "" then name else prefix ^ "." ^ name in
          Hashtbl.replace seen q ();
          go q inner
        | _ -> ())
      ds
  in
  go "" decls;
  Hashtbl.fold (fun n () acc -> n :: acc) seen []

(* The names of the functions THIS file declares, span-filtered against the
   stdlib.  Shared by [own_caps_of_this_module] and by the --cap-strict
   ceiling's DCE roots (see [Dce.prune_unreachable]'s [extra_root]), which
   need the same "is this the user's code?" answer and must not drift apart
   in how they get it. *)
let user_fn_names_of ~stdlib_files (m : March_ast.Ast.module_) :
    (string, unit) Hashtbl.t =
  let is_stdlib (sp : March_ast.Ast.span) =
    List.mem sp.March_ast.Ast.file stdlib_files
  in
  let user_fn_names = Hashtbl.create 64 in
  let rec walk decls =
    List.iter (fun (d : March_ast.Ast.decl) ->
        match d with
        | March_ast.Ast.DFn (fd, sp) ->
          if not (is_stdlib sp) then
            Hashtbl.replace user_fn_names fd.March_ast.Ast.fn_name.March_ast.Ast.txt ()
        | March_ast.Ast.DMod (_, _, inner, _) -> walk inner
        | _ -> ()) decls
  in
  walk m.March_ast.Ast.mod_decls;
  user_fn_names

(* A TIR function name's bare stem: module prefix and monomorphization suffix
   stripped (`M.helper$Int` -> `helper`), the spelling [user_fn_names_of]
   records. *)
let tir_fn_stem n =
  let n =
    match String.rindex_opt n '.' with
    | Some i -> String.sub n (i + 1) (String.length n - i - 1)
    | None -> n
  in
  match String.index_opt n '$' with
  | Some i -> String.sub n 0 i
  | None -> n

(* Whether TIR function [n] is one THIS file declares.  The stem comparison
   strips the module prefix, so on its own it also matched every STDLIB
   function sharing a user function's bare name: a main-less module declaring
   `add` rooted `BigInt.add`, `Decimal.add`, `DateTime.add`, `Forge.add`,
   `PeerRegistry.add` and `CRDT.GCounter.add`, whose 172 reachable functions
   include console IO — and the ceiling then charged `IO.Console` to a module
   that never mentions it
   (specs/progress/2026-09-18-cap-ceiling-rooted-stdlib-namesakes.md).  A
   prefixed name is the user's own only if the prefix is not a stdlib module;
   the entry module's own functions are bare.  Shared by the --cap-strict
   ceiling's DCE roots and a main-less executable's codegen roots. *)
let is_user_tir_fn ~user_fns ~stdlib_mods n =
  Hashtbl.mem user_fns (tir_fn_stem n)
  && (let pre_mono =
        match String.index_opt n '$' with
        | Some i -> String.sub n 0 i
        | None -> n in
      match String.rindex_opt pre_mono '.' with
      | None -> true
      | Some i -> not (List.mem (String.sub pre_mono 0 i) stdlib_mods))

(** [cap_ceiling_module_spans ~entry_owner ~entry_span decls] maps each
    module's --cap-strict ceiling owner name (the same keying
    [March_typecheck.Typecheck.module_caps] uses: the entry module's own TIR
    name, and both the bare and fully-qualified spelling of every nested
    [DMod]) to (a) the span [March_caps.Cap_ceiling.check] should attribute
    an [Undeclared] violation to — that module's first [DNeeds] span if it
    declares one, otherwise its own header span ([entry_span] for the entry
    module, the [DMod]'s own declaration span for a nested one) — and (b)
    whether that span is a HEADER (no existing [DNeeds]) as opposed to an
    existing [DNeeds] line, which [cap_ceiling_fix_indent] below needs to
    pick the right indent for an inserted `needs` line.

    Mirrors [Typecheck.check_module_needs]'s [cap_qname_prefix] accumulation
    (empty at the entry level) so a violation on a doubly-nested module
    resolves to the SAME qualified key the ceiling matches attribution
    against. *)
let cap_ceiling_module_spans ~entry_owner ~entry_span
    (decls : March_ast.Ast.decl list)
    : (string * March_ast.Ast.span) list * (string * bool) list =
  let first_needs_span decls =
    List.find_map (function
        | March_ast.Ast.DNeeds (_, sp) -> Some sp
        | _ -> None)
      decls
  in
  (* A module loaded from a separate file via MARCH_LIB_PATH is synthesized
     as [DMod (..., dummy_span)] (bin/main.ml's lib-path loader never had a
     real `mod ... end` span to give it) — its OWN header span is useless.
     Fall back to the first inner declaration that carries a real span, so
     the ceiling still has somewhere concrete to point at instead of
     [dummy_span]'s (file="<none>", line=0), which downstream indexes
     straight into a negative line number. *)
  let rec first_real_decl_span decls =
    match decls with
    | [] -> None
    | d :: rest ->
      let sp =
        match (d : March_ast.Ast.decl) with
        | March_ast.Ast.DFn (_, sp) | March_ast.Ast.DLet (_, _, sp)
        | March_ast.Ast.DType (_, _, _, _, sp)
        | March_ast.Ast.DAlwaysLinearType (_, _, _, _, sp)
        | March_ast.Ast.DActor (_, _, _, sp) | March_ast.Ast.DProtocol (_, _, sp)
        | March_ast.Ast.DMod (_, _, _, sp)
        | March_ast.Ast.DSig (_, _, sp) | March_ast.Ast.DInterface (_, sp)
        | March_ast.Ast.DImpl (_, sp)
        | March_ast.Ast.DExtern (_, sp) | March_ast.Ast.DUse (_, sp)
        | March_ast.Ast.DAlias (_, sp)
        | March_ast.Ast.DNeeds (_, sp) | March_ast.Ast.DProofCap (_, _, sp)
        | March_ast.Ast.DTransitions (_, _, sp)
        | March_ast.Ast.DApp (_, sp) | March_ast.Ast.DDeriving (_, _, sp)
        | March_ast.Ast.DSatisfy (_, _, sp)
        | March_ast.Ast.DTest (_, sp) | March_ast.Ast.DDescribe (_, _, sp)
        | March_ast.Ast.DSetup (_, sp)
        | March_ast.Ast.DSetupAll (_, sp) | March_ast.Ast.DOpts (_, sp) -> sp
      in
      if sp <> March_ast.Ast.dummy_span then Some sp
      else first_real_decl_span rest
  in
  let span_and_is_header ~header decls =
    match first_needs_span decls with
    | Some sp -> (sp, false)
    | None ->
      let header =
        if header = March_ast.Ast.dummy_span then
          match first_real_decl_span decls with
          | Some sp -> sp
          | None -> header
        else header
      in
      (header, true)
  in
  let spans = ref [] and is_header = ref [] in
  let add name sp hdr =
    spans := (name, sp) :: !spans;
    is_header := (name, hdr) :: !is_header
  in
  let (entry_sp, entry_hdr) = span_and_is_header ~header:entry_span decls in
  add entry_owner entry_sp entry_hdr;
  let rec walk ~prefix decls =
    List.iter (function
        | March_ast.Ast.DMod (n, _, inner, decl_span) ->
          let qname = if prefix = "" then n.March_ast.Ast.txt
                      else prefix ^ "." ^ n.March_ast.Ast.txt in
          (* [decl_span], not [n.span] — [n] is only the module NAME token
             ("Dep" in "mod Dep do"), whose column is well past the line's
             actual leading indentation.  [decl_span] (parser.mly:
             [mk_span ($loc)] over the whole [mod ... end] production)
             starts at the `mod` keyword itself, which IS the line's
             indentation. *)
          let (sp, hdr) = span_and_is_header ~header:decl_span inner in
          add qname sp hdr;
          if qname <> n.March_ast.Ast.txt then add n.March_ast.Ast.txt sp hdr;
          walk ~prefix:qname inner
        | _ -> ())
      decls
  in
  walk ~prefix:"" decls;
  (!spans, !is_header)

(** [cap_ceiling_fix_indent ~src ~filename ~read_file ~is_header span] is the
    column an inserted `needs` line for [span]'s module should start at:
    the ACTUAL leading whitespace of [span]'s own source line (read from
    [src], or from [read_file span.file] when the span points into a
    different file than the one being compiled — a sibling module pulled in
    via [MARCH_LIB_PATH]) when [span] is an existing [DNeeds] line (a new
    line is a peer of it, same column); that plus 2 when [span] is a module
    HEADER instead — the module's body, where the fix lands, is indented one
    step deeper than its own header line. (This codebase's own convention;
    March is not indentation-sensitive, so a wrong answer here is cosmetic,
    never a build break — confirmed by [test_ceiling_violation_carries_a_span_and_a_fix],
    which does not assert on indent width.) Reading the source line directly,
    rather than trusting a token's [start_col], is deliberate: the natural
    candidate span for a header ([DMod]'s NAME token) sits well past the
    line's real indentation, which is exactly the bug this function fixes. *)
let cap_ceiling_fix_indent ~src ~filename ~read_file ~is_header
    (span : March_ast.Ast.span) : int =
  let file_src =
    if span.March_ast.Ast.file = filename || span.March_ast.Ast.file = "" then src
    else (try read_file span.March_ast.Ast.file with Sys_error _ -> src)
  in
  let lines = String.split_on_char '\n' file_src in
  let idx = span.March_ast.Ast.start_line - 1 in
  let base =
    (* [List.nth_opt] RAISES [Invalid_argument] on a negative index rather
       than returning [None] — a [dummy_span] (start_line = 0) gives
       idx = -1, which would otherwise crash the compiler here instead of
       degrading gracefully. *)
    match if idx < 0 then None else List.nth_opt lines idx with
    | None -> 0
    | Some line ->
      let n = String.length line in
      let rec count i = if i < n && line.[i] = ' ' then count (i + 1) else i in
      count 0
  in
  if is_header then base + 2 else base

(* ── The checks ─────────────────────────────────────────────────────────── *)

type input = {
  desugared : March_ast.Ast.module_;
  stdlib_decls : March_ast.Ast.decl list;
  tc_env : March_typecheck.Typecheck.env;
  type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t;
  src : string;
  filename : string;
  read_file : string -> string;
  cap_strict : bool;
}

type finding =
  | Diag of March_errors.Errors.diagnostic
  | Bare of string

type report = { findings : finding list; count : int }

let empty = { findings = []; count = 0 }

let stdlib_span_files = March_typecheck.Typecheck_builtins.stdlib_span_files

let host_scope_findings (i : input) (tir : March_tir.Tir.tir_module) : report =
  let desugared = i.desugared and stdlib_decls = i.stdlib_decls in
  let scopes =
    March_typecheck.Typecheck.declared_net_scopes i.tc_env
      ~entry_module:tir.March_tir.Tir.tm_name
  in
  if List.for_all (fun (_, ds) -> ds = []) scopes then empty
  else begin
    let stdlib_mods = stdlib_module_names stdlib_decls in
    let prelude_fns = Hashtbl.create 64 in
    (* "Transparent" (stdlib) is decided by where a declaration COMES FROM,
       never by its name: a user module named `Yaml`, or an entry-module
       function named like a prelude one, is user code and is checked
       (a by-name test let both escape the check entirely). *)
    let user_mods = Hashtbl.create 16 in
    let user_entry_fns = Hashtbl.create 64 in
    let annotated = ref [] in
    let rec walk prefix (decls : March_ast.Ast.decl list) =
      List.iter (fun (d : March_ast.Ast.decl) ->
          match d with
          | March_ast.Ast.DFn (fd, sp) ->
            let name = fd.March_ast.Ast.fn_name.March_ast.Ast.txt in
            let from_stdlib = March_typecheck.Typecheck_builtins.file_is_stdlib sp.March_ast.Ast.file in
            if prefix = "" && from_stdlib then Hashtbl.replace prelude_fns name ();
            if prefix = "" && not from_stdlib then
              Hashtbl.replace user_entry_fns name ();
            (match March_caps.Net_dest.net_dest_attr fd.March_ast.Ast.fn_attrs with
             | None -> ()
             | Some p ->
               let params =
                 match fd.March_ast.Ast.fn_clauses with
                 | c :: _ ->
                   List.map (function
                       | March_ast.Ast.FPNamed prm | March_ast.Ast.FPDefault (prm, _) ->
                         prm.March_ast.Ast.param_name.March_ast.Ast.txt
                       | March_ast.Ast.FPPat (March_ast.Ast.PatVar n) -> n.March_ast.Ast.txt
                       | March_ast.Ast.FPPat _ -> "")
                     c.March_ast.Ast.fc_params
                 | [] -> []
               in
               let rec index i = function
                 | [] -> None
                 | x :: rest -> if x = p then Some i else index (i + 1) rest
               in
               Option.iter (fun i ->
                   annotated := ((if prefix = "" then name else prefix ^ "." ^ name), i)
                                :: !annotated)
                 (index 0 params))
          | March_ast.Ast.DMod (n, _, inner, msp) ->
            let full =
              if prefix = "" then n.March_ast.Ast.txt
              else prefix ^ "." ^ n.March_ast.Ast.txt
            in
            (* Stdlib modules carry a placeholder span; a user module (the
               program's or a dependency's) has a real file outside the
               stdlib root. *)
            let f = msp.March_ast.Ast.file in
            if f <> March_ast.Ast.dummy_span.March_ast.Ast.file
               && not (March_typecheck.Typecheck_builtins.file_is_stdlib f) then
              Hashtbl.replace user_mods full ();
            walk full inner
          | _ -> ()) decls
    in
    walk "" desugared.March_ast.Ast.mod_decls;
    walk "" stdlib_decls;
    if Sys.getenv_opt "MARCH_DUMP_NET_SCOPE" = Some "1" then begin
      List.iter (fun (m, ds) ->
          if ds <> [] then
            Printf.eprintf "net-scope: module %s scoped to %s\n" m
              (March_caps.Host_scope.encode_spec ds)) scopes;
      List.iter (fun (n, i) ->
          Printf.eprintf "net-scope: @[net_dest] %s param %d\n" n i) !annotated
    end;
    let violations =
      March_tir.Net_scope.check ~scopes
        ~transparent:(fun m -> List.mem m stdlib_mods && not (Hashtbl.mem user_mods m))
        ~transparent_fns:(fun n ->
            not (String.contains n '.') && Hashtbl.mem prelude_fns n
            && not (Hashtbl.mem user_entry_fns n))
        ~annotated:(List.sort_uniq compare !annotated) tir
    in
    if violations = [] then empty
    else begin
      let (module_spans, _) = cap_ceiling_module_spans
          ~entry_owner:tir.March_tir.Tir.tm_name
          ~entry_span:desugared.March_ast.Ast.mod_name.March_ast.Ast.span
          desugared.March_ast.Ast.mod_decls
      in
      (* One diagnostic per module (TIR carries no call spans, so it points
         at the module), its first violation as the message and the rest
         listed after it. *)
      let owners =
        List.sort_uniq compare
          (List.map (fun (v : March_tir.Net_scope.violation) -> v.owner) violations)
      in
      let ctx = March_errors.Errors.create () in
      let bare = ref [] in
      List.iter (fun owner ->
          let vs =
            List.filter (fun (v : March_tir.Net_scope.violation) -> v.owner = owner)
              violations
          in
          match vs with
          | [] -> ()
          | first :: rest ->
            let msg =
              if rest = [] then first.message
              else
                first.message ^ "\n\nAlso in module `" ^ owner ^ "`:\n"
                ^ String.concat "\n"
                    (List.map (fun (v : March_tir.Net_scope.violation) ->
                         "- [" ^ v.code ^ "] " ^ v.message) rest)
            in
            let span =
              match List.assoc_opt owner module_spans with
              | Some sp -> sp
              | None -> desugared.March_ast.Ast.mod_name.March_ast.Ast.span
            in
            if span = March_ast.Ast.dummy_span then
              bare := Bare (Printf.sprintf "-- CAPABILITY --\n%s [%s]\n\n" msg first.code)
                      :: !bare
            else March_errors.Errors.error ctx ~span ~code:first.code msg)
        owners;
      { findings =
          List.rev !bare
          @ List.map (fun d -> Diag d) (March_errors.Errors.sorted ctx);
        count = List.length violations }
    end
  end

let cap_attribution (i : input) ~(pre_opt : March_tir.Tir.tir_module)
    : (string * string) list =
  let desugared = i.desugared and stdlib_decls = i.stdlib_decls in
  let pre_opt_tir = pre_opt in
  let stdlib_mods = stdlib_module_names stdlib_decls in
  let user_mods = user_module_names desugared.March_ast.Ast.mod_decls in
  (* A module with no `main` has no DCE roots, so pruning would keep the
     whole prepended stdlib and attribution would charge every stdlib
     module for capabilities the program never reaches — 17 violations for
     a file whose only declaration was `fn helper(x) = x + 1`.  Root the
     functions this FILE declares instead; see [Dce.prune_unreachable].

     Matched against the TIR name, which may be prefixed by the module
     (`M.helper`) and/or suffixed by monomorphization (`helper$Int`), so
     compare the bare stem.  Prelude functions are excluded by the
     span filter inside [user_fn_names_of] — not by shape, since `println`
     is unprefixed exactly like the entry module's own functions. *)
  let user_fns =
    user_fn_names_of ~stdlib_files:(stdlib_span_files stdlib_decls)
      desugared
  in
  let stem = tir_fn_stem in
  (* The PRELUDE's functions are the complement of [user_fns] at the top
     level: stdlib-span [DFn]s, unwrapped into the entry module, so their
     TIR names are BARE exactly like the user's own.  They must be
     see-through per FUNCTION — the module predicate above cannot express
     them (they name no module, and their owner resolves to the entry
     module, which is never transparent).  Without this, the console use
     inside `println$String` was charged to the ENTRY module no matter
     which nested module called it, and that module's own `needs` could
     not satisfy the ceiling. *)
  let prelude_fns = Hashtbl.create 64 in
  let walk_prelude decls =
    List.iter (fun (d : March_ast.Ast.decl) ->
        match d with
        | March_ast.Ast.DFn (fd, sp) ->
          if List.mem sp.March_ast.Ast.file
               (stdlib_span_files stdlib_decls) then
            Hashtbl.replace prelude_fns
              fd.March_ast.Ast.fn_name.March_ast.Ast.txt ()
        | March_ast.Ast.DMod _ -> ()  (* prefixed; module transparency covers them *)
        | _ -> ()) decls
  in
  walk_prelude desugared.March_ast.Ast.mod_decls;
  March_tir.Cap_attrib.attribute
    ~transparent:(fun m -> List.mem m stdlib_mods && not (Hashtbl.mem user_mods m))
    ~transparent_fns:(fun n ->
      (* Bare names only: a dotted name belongs to a module and is judged
         by the module predicate.  Matching the stem of a dotted name here
         would make a user function that merely SHARES a prelude name
         (`MyMod.println`) see-through. *)
      not (String.contains n '.') && Hashtbl.mem prelude_fns (stem n))
    (March_tir.Dce.prune_unreachable
       ~extra_root:(is_user_tir_fn ~user_fns ~stdlib_mods)
       ~fail_open:false pre_opt_tir)


(* Per-module declared needs, keyed as attribution names owners: the entry
   module is unwrapped by desugar, so its `needs` live in [mod_needs] under
   the TIR module name. *)
let module_caps (i : input) ~(pre_opt : March_tir.Tir.tir_module) =
  (pre_opt.March_tir.Tir.tm_name,
   i.tc_env.March_typecheck.Typecheck.mod_needs)
  :: i.tc_env.March_typecheck.Typecheck.module_caps

let ceiling_findings (i : input) ~(pre_opt : March_tir.Tir.tir_module)
    ~(attribution : (string * string) list) : report =
  if not i.cap_strict then empty
  else begin
    let flat_caps = List.sort_uniq compare (List.map fst attribution) in
    let (module_spans, module_is_header) = cap_ceiling_module_spans
        ~entry_owner:pre_opt.March_tir.Tir.tm_name
        ~entry_span:i.desugared.March_ast.Ast.mod_name.March_ast.Ast.span
        i.desugared.March_ast.Ast.mod_decls
    in
    let violations =
      March_caps.Cap_ceiling.check ~module_caps:(module_caps i ~pre_opt) ~module_spans
        ~attribution ~caps:flat_caps
    in
    if violations = [] then empty
    else begin
      let ctx = March_errors.Errors.create () in
      let bare = ref [] in
      List.iter
        (fun v ->
           match v with
           | March_caps.Cap_ceiling.Undeclared { cap = _; owner = _; span }
             when span = March_ast.Ast.dummy_span ->
             (* No real span anywhere for this module: rendering through the
                diagnostic pipeline would read the wrong file. *)
             bare := Bare (Printf.sprintf "-- CAPABILITY --\n%s\n\n"
                             (March_caps.Cap_ceiling.describe v)) :: !bare
           | March_caps.Cap_ceiling.Undeclared { cap; owner; span } ->
             let is_header =
               match List.assoc_opt owner module_is_header with
               | Some h -> h | None -> true
             in
             let indent =
               cap_ceiling_fix_indent ~src:i.src ~filename:i.filename
                 ~read_file:i.read_file ~is_header span
             in
             March_errors.Errors.error_with_fix ctx ~span
               ~code:(March_errors.Code.with_arg March_errors.Code.cap_ceiling cap)
               ~fix:(March_errors.Errors.FInsert {
                   after_line = span.March_ast.Ast.start_line;
                   text = String.make indent ' ' ^ "needs " ^ cap })
               (Printf.sprintf
                  "Module `%s` uses `%s` but does not declare `needs %s`.\n\
                   help: add `needs %s` to the module body."
                  owner cap cap cap)
           | March_caps.Cap_ceiling.Unattributed _ ->
             bare := Bare (Printf.sprintf "-- CAPABILITY --\n%s\n\n"
                             (March_caps.Cap_ceiling.describe v)) :: !bare)
        violations;
      { findings =
          List.rev !bare
          @ List.map (fun d -> Diag d) (March_errors.Errors.sorted ctx);
        count = List.length violations }
    end
  end

type outcome = Checked of finding list | Unchecked of string

exception Stop_at_pre_opt of March_tir.Tir.tir_module

let one_line why =
  match String.index_opt why '\n' with
  | Some k -> String.sub why 0 k
  | None -> why

(* Lower [i.desugared] and run both checks, stopping the post-lower pipeline
   at exactly the point the compile path takes its pre-opt snapshot (its
   [before_opt] hook), so attribution sees the same TIR.  A lowering failure
   is [Unchecked], never a rejection: the caller warns and runs the program. *)
let check_program ?(test_mode = false) ~opt ~is_js (i : input) : outcome =
  match
    (try
       let tir =
         March_tir.Lower.lower_module ~type_map:i.type_map ~test_mode i.desugared
       in
       let iface_methods = March_tir.Lower.get_iface_methods () in
       let hs = host_scope_findings i tir in
       let ceiling =
         if not i.cap_strict then empty
         else
           match
             March_tir.Contract_pipeline.run ~iface_methods ~is_js ~opt
               ~before_opt:(fun t -> raise (Stop_at_pre_opt t)) tir
           with
           | _ -> empty  (* unreachable: [before_opt] always runs *)
           | exception Stop_at_pre_opt pre_opt ->
             let attribution = cap_attribution i ~pre_opt in
             ceiling_findings i ~pre_opt ~attribution
       in
       Ok (hs.findings @ ceiling.findings)
     with
     | (Out_of_memory | Stack_overflow) as e -> raise e
     | March_errors.Errors.Diagnostic_exn d ->
       Error (one_line d.March_errors.Errors.message)
     | Failure msg -> Error (one_line msg)
     | e -> Error (one_line (Printexc.to_string e)))
  with
  | Ok fs -> Checked fs
  | Error why -> Unchecked why
