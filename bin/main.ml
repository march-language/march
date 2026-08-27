(** March compiler entry point. *)

open Toolchain
open Flags

(** The set of source files a batch of stdlib declarations actually came from.

    The refinement checker needs to know whether a `List.length` in scope is
    the real stdlib one before it may treat it as the `len` measure (see
    [Refine_check.stdlib_source_files]); a wrong answer there is a false
    positive on correct code. Reading the identity off the declarations we are
    about to prepend — rather than pattern-matching the path — is what makes it
    agree with [find_stdlib_dir]'s resolution order (repo `stdlib/`, an
    installed `share/march`, `MARCH_STDLIB`) AND with the marshalled stdlib-AST
    cache, whose spans carry whatever directory the entry was written from.
    Declarations arriving via `MARCH_LIB_PATH` are user decls, not stdlib
    decls, so a vendored or forked `List` is correctly not in this set. *)
let stdlib_span_files (decls : March_ast.Ast.decl list) : string list =
  let seen = Hashtbl.create 64 in
  (* Both no-file spellings are excluded. `""` is what a string-parsed fixture
     carries; `"<none>"` is [Ast.dummy_span]'s, and [load_stdlib_file] gives
     every stdlib module's wrapping [DMod] a dummy span — so without this the
     sentinel would be a member of the identity set on every production run,
     and any `fn length` inside a `mod List` that happened to carry a dummy
     span would be certified as the standard library's. No such declaration is
     reachable today (desugar's synthesized `DFn`s all reuse their source
     declaration's real span), but admitting the sentinel is precisely the
     class of wrong fact this gate exists to prevent, so the route is closed
     rather than argued about. *)
  let add (sp : March_ast.Ast.span) =
    let f = sp.March_ast.Ast.file in
    if f <> "" && f <> March_ast.Ast.dummy_span.March_ast.Ast.file then
      Hashtbl.replace seen f ()
  in
  let rec go ds =
    List.iter
      (function
        | March_ast.Ast.DMod (_, _, inner, sp) -> add sp; go inner
        | March_ast.Ast.DFn (_, sp) -> add sp
        | _ -> ())
      ds
  in
  go decls;
  Hashtbl.fold (fun f () acc -> f :: acc) seen []

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

(** Typecheck [stdlib_decls] once and cache the resulting environment, so a
    combined check/compile can seed pass 1 from it (via
    [Typecheck.check_module_core]'s [?seed_env]) instead of re-typechecking
    the whole stdlib from scratch every invocation — stdlib typecheck alone
    measured ~68% of `forge check`'s wall time on a small (10-file) real
    project, and a large fixed cost even on bigger ones.

    Deliberately NOT the same cache/mechanism as [lib/repl/repl.ml]'s
    `stdlib_tcenv_*.bin`: that one is built by folding [check_decl] over each
    stdlib decl one at a time with no forward-reference prebinding pass, and
    is KNOWN to tolerate real typecheck errors in some stdlib modules (see
    its own comment on `load_decls_into_env` — http_server_listen/ws_recv
    fail under that path and the resulting partial env is used anyway). This
    cache is instead built via the exact same [check_module_core] pass 1/1b/2
    machinery `march --check`/`--compile` already trust for stdlib, just
    applied to stdlib alone first — so a cache hit here is behaviorally
    identical to what today's from-scratch combined check would have done
    for stdlib's own portion, not a reduced approximation of it. *)
let get_stdlib_tc_env ~for_js (stdlib_decls : March_ast.Ast.decl list) =
  let content_hash = Digest.to_hex (Digest.string (Marshal.to_string stdlib_decls [])) in
  let home = (try Sys.getenv "HOME" with Not_found -> ".") in
  let cache_dir = Filename.concat home ".cache/march" in
  let short_hash = String.sub content_hash 0 16 in
  let js_suffix = if for_js then "_js" else "" in
  (* Keyed on the compiler build too — this is a Marshal of the typecheck env
     record, so a field added to it while stdlib source is unchanged would
     otherwise be read back at the wrong shape.  See the note on the AST
     cache above. *)
  let build_id = String.sub (Lazy.force March_cas.Cas.compiler_identity) 0 12 in
  let cache_path = Filename.concat cache_dir
    (Printf.sprintf "stdlib_tcenv_cli%s_%s_%s.bin" js_suffix build_id short_hash) in
  let type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t =
    Hashtbl.create 4096 in
  (* Drop staging files left by processes that died mid-write — the REPL
     sweeps the same shared dir on start, but a user who only ever runs the
     CLI would otherwise never clear them. *)
  March_repl.Repl.sweep_stale_cache_tmps cache_dir;
  let load_from_cache () =
    try
      if Sys.file_exists cache_path then begin
        let ic = open_in_bin cache_path in
        let (cached_env : March_typecheck.Typecheck.env) = Marshal.from_channel ic in
        let (cached_tm : (March_ast.Ast.span * March_typecheck.Typecheck.ty) list) =
          Marshal.from_channel ic in
        (* Restore the two PROCESS-GLOBAL side-tables a from-scratch stdlib
           check would have advanced/populated as a side effect, and that a
           cache hit otherwise skips entirely:
             - [Typecheck._counter]: the fresh-metavar id source. Checking
               stdlib alone burns ~2000 ids; skip that on a cache hit and
               pass 2 (the user's own file) starts allocating from near 0
               instead of continuing where a from-scratch run would have
               left off. The raw id VALUES differ either way (harmless —
               golden fixtures compare via canonical renumbering — see
               test/test_emit_core_ast.ml's [canonicalize]), but which of
               two user-file schemes happens to get the SMALLER raw id can
               flip depending on the counter's starting point, and THAT
               flips their relative order in the emitted `schemes` array
               (sorted by raw id, then canonicalized — canonicalization
               renumbers id VALUES but never reorders arrays). Confirmed via
               a three-way diff (cold / warm / pre-Task-3.1 binary) on
               `--emit-core-ast` of specs/lang/types/accept/
               t07_generic_option_two_types.march: cold and the pre-3.1
               binary agree on scheme order, warm alone disagrees — see
               specs/progress/2026-08-24-interp-perf-phase-3-startup-tcenv-cache.md's
               "Fix round 2" section. [max] rather than a blind overwrite:
               never let a cache read move the counter BACKWARD, which
               could mint an id that collides with one already allocated
               earlier in this same process.
             - [Typecheck._record_names]: a display-only signature->name
               index (never consulted by --emit-core-ast's JSON emitter,
               confirmed by reading [Ast_json.resolved_ty_to_json]'s TRecord
               case — it never touches this table) but DOES feed [pp_ty],
               which renders type names into ordinary diagnostic text. Left
               unrestored, a cache-hit run could render a record type
               structurally where a cold run renders it nominally (or vice
               versa) purely because stdlib's own record declarations never
               ran through [register_record_name] on this process — a
               latent diagnostic-text divergence beyond what actually
               reproduced in the golden corpus. Restored defensively for
               the same reason the round-1 fix insisted on byte-identical
               diagnostics rather than "close enough". *)
        let (cached_counter : int) = Marshal.from_channel ic in
        let (cached_record_names : (string * string option) list) =
          Marshal.from_channel ic in
        close_in ic;
        List.iter (fun (k, v) -> Hashtbl.replace type_map k v) cached_tm;
        if cached_counter > !March_typecheck.Typecheck._counter then
          March_typecheck.Typecheck._counter := cached_counter;
        List.iter (fun (k, v) -> Hashtbl.replace March_typecheck.Typecheck._record_names k v)
          cached_record_names;
        Some { cached_env with
               March_typecheck.Typecheck.errors = March_errors.Errors.create ();
               type_map }
      end else None
    with _ -> None
  in
  match load_from_cache () with
  | Some env -> env
  | None ->
    let dummy_span = March_ast.Ast.{
      file = ""; start_line = 0; start_col = 0; end_line = 0; end_col = 0
    } in
    let synthetic = {
      March_ast.Ast.mod_name = { March_ast.Ast.txt = "StdlibBaseline"; span = dummy_span };
      March_ast.Ast.mod_decls = stdlib_decls;
    } in
    let errors = March_errors.Errors.create () in
    let (_errs, _tm, final_env) =
      March_typecheck.Typecheck.check_module_core ~errors synthetic in
    (try
      mkdir_p cache_dir;
      let tmp = Printf.sprintf "%s.%d.tmp" cache_path (Unix.getpid ()) in
      let oc = open_out_bin tmp in
      (* Same staging discipline as [March_repl.Repl.save_cached_tc_env], and
         for the same reasons: the env is stripped of its unmarshalable
         import-tracker closures before writing, and [Fun.protect] unlinks the
         temp if anything raises, so a failed save cannot leave a zero-byte
         orphan in the shared cache dir. *)
      Fun.protect
        ~finally:(fun () ->
          (try close_out oc with _ -> ());
          if Sys.file_exists tmp then (try Sys.remove tmp with _ -> ()))
        (fun () ->
          Marshal.to_channel oc (March_repl.Repl.marshalable_tc_env final_env) [];
          let tm_list = Hashtbl.fold (fun k v acc -> (k, v) :: acc)
            final_env.March_typecheck.Typecheck.type_map [] in
          Marshal.to_channel oc tm_list [];
          (* Snapshot the two process-global side-tables RIGHT NOW — the
             point where a from-scratch run would hand off from "stdlib
             checked" to "start checking the user's own file" — so a later
             cache hit can restore them to this exact point. See the long
             comment on [load_from_cache] above for why both matter. *)
          Marshal.to_channel oc !March_typecheck.Typecheck._counter [];
          let record_names_list =
            Hashtbl.fold (fun k v acc -> (k, v) :: acc)
              March_typecheck.Typecheck._record_names [] in
          Marshal.to_channel oc record_names_list [];
          close_out oc;
          Sys.rename tmp cache_path)
    with e ->
      Printf.eprintf
        "[warn] could not save the stdlib typecheck cache (%s); stdlib will be \
         re-typechecked on every invocation\n%!"
        (Printexc.to_string e));
    { final_env with
      March_typecheck.Typecheck.errors = March_errors.Errors.create ();
      type_map = final_env.March_typecheck.Typecheck.type_map }

(* Substring test used by the MARCH_DUMP_TXT stage filter (see snap_tir). *)
let contains_substring (hay : string) (needle : string) =
  let nh = String.length hay and nn = String.length needle in
  nn = 0 ||
  (let rec go i = i + nn <= nh && (String.sub hay i nn = needle || go (i + 1)) in
   go 0)

(* A CAS-key fragment digesting the FFI shim sources + link flags, so editing a
   shim (a .c file, not the .march source) invalidates the cached binary. Empty
   when no FFI shims are in play. *)
let ffi_cas_tag () : string list =
  if !ffi_c_files = [] && !ffi_link_flags = [] then []
  else begin
    let buf = Buffer.create 64 in
    List.iter (fun f ->
      Buffer.add_string buf f;
      (try Buffer.add_string buf (Digest.to_hex (Digest.file f)) with _ -> ()))
      (List.rev !ffi_c_files);
    List.iter (Buffer.add_string buf) (List.rev !ffi_link_flags);
    ["ffi:" ^ Digest.to_hex (Digest.string (Buffer.contents buf))]
  end

(* Interpreter FFI (Phase 4 / Gap 1): provide the runtime .so so extern calls
   can be resolved dynamically, and — if ffi_c_files are present (from
   --ffi-c or forge.toml [ffi]) — compile them into a temp .so and tell the
   interpreter to dlopen it. An explicit --ffi-so path takes precedence.
   Shared by every interpreter entry point (plain `march file.march` and
   `march test`) so FFI shims resolve the same way in both. *)
let setup_interpreter_ffi () =
  March_eval.Eval.ffi_runtime_so := (fun () -> Some (ensure_runtime_so ()));
  match !March_eval.Eval.ffi_shim_so with
  | Some _ -> ()  (* already set explicitly via --ffi-so *)
  | None when !ffi_c_files = [] -> ()  (* no shim sources *)
  | None ->
    (* Build a content-addressed temp path for the shim .so *)
    let home = (try Sys.getenv "HOME" with Not_found -> ".") in
    let cache_dir = Filename.concat home ".cache/march" in
    mkdir_p cache_dir;
    let key_buf = Buffer.create 256 in
    List.iter (fun f ->
      Buffer.add_string key_buf f;
      (try Buffer.add_string key_buf (Digest.to_hex (Digest.file f)) with _ -> ()))
      (List.rev !ffi_c_files);
    List.iter (Buffer.add_string key_buf) (List.rev !ffi_link_flags);
    let key = String.sub (Digest.to_hex (Digest.string (Buffer.contents key_buf))) 0 16 in
    let so_path = Filename.concat cache_dir ("march_ffi_shim_" ^ key ^ ".so") in
    if not (Sys.file_exists so_path) then begin
      (* Find the runtime dir for the -I flag (march_ffi.h lives there) *)
      let runtime_dir_opt =
        Option.map Filename.dirname (find_runtime_file "march_runtime.c")
      in
      let inc_flag = match runtime_dir_opt with
        | Some d -> Printf.sprintf " -I%s" (Filename.quote d)
        | None -> ""
      in
      let src_files = String.concat " "
        (List.rev_map Filename.quote !ffi_c_files) in
      (* Link flags from forge.toml [ffi] link (e.g. -lsqlite3) — the shim's
         own C code needs these resolved same as a native `forge build`;
         without them, symbols the shim calls into a system library for
         (not march runtime symbols, which resolve at dlopen time via
         RTLD_GLOBAL) are undefined and the whole shim fails to dlopen. *)
      let link_flags = String.concat " " (List.rev !ffi_link_flags) in
      let tmp = Printf.sprintf "%s.%d.tmp" so_path (Unix.getpid ()) in
      (* On macOS, shim symbols reference runtime functions (e.g. march_str_borrow)
         that are not available at .so link time — they'll be resolved at dlopen
         time via RTLD_GLOBAL. Pass -undefined dynamic_lookup on Darwin. *)
      let platform_flags =
        match Sys.getenv_opt "MARCH_FFI_SHIM_LDFLAGS" with
        | Some f -> " " ^ f   (* explicit override *)
        | None ->
          (* Detect macOS via the existence of /System/Library/CoreServices *)
          if Sys.file_exists "/System/Library/CoreServices"
          then " -undefined dynamic_lookup"
          else ""
      in
      let cmd = Printf.sprintf
        "cc -shared -O2 -fno-strict-aliasing -fwrapv -fPIC%s%s%s %s -o %s %s 2>&1"
        platform_flags (install_name_flag so_path) inc_flag src_files tmp link_flags in
      let rc = Sys.command cmd in
      if rc <> 0 then
        Printf.eprintf "march: warning: failed to compile FFI shim sources \
                        to .so (exit %d) — interpreter will not find shim symbols\n" rc
      else begin
        (try Sys.rename tmp so_path
         with Sys_error _ ->
           (try Sys.remove tmp with Sys_error _ -> ()))
      end
    end;
    if Sys.file_exists so_path then
      March_eval.Eval.ffi_shim_so := Some so_path

(* [own_caps_of_this_module env m] — the module's OWN inferred capability
    set, filtered to functions this file declares.

    Two traps this exists to avoid, both previously shipped:
    - [fn_capability_closures] folds in transitively-imported module needs,
      which makes the union app-invariant;
    - even [fn_own_capability_closures] is keyed over EVERY function the
      typechecker saw, including linked stdlib, so it must be filtered to this
      file or a pure program reports "needs everything".

    Read by --cap-sandbox (the embedded profile's grant set).  Until #225 the
    --cap-strict ceiling read it too; the ceiling's used-set is now
    attribution-only.

    The [belongs] filter collects EVERY key shape
    [fn_own_capability_closures] can produce for this file's declarations —
    bare [DFn]/[DLet] names, dotted nested-module names, impl methods'
    "[Prefix.]Iface$Ty.method" manglings, actor handlers' bare synthesized
    "Actor_Msg" names, and the bare dispatch node an impl emits.  It was
    [DFn]-only until 2026-08-08
    (2026-08-06-cap-sandbox-belongs-filter-misses-non-dfn-keys.md), which made
    the sandbox profile UNDER-grant: a program whose only write lived in a
    module-level [let] embedded a pure program's profile and was denied at
    runtime by its own sandbox.  Pinned by test_cap_sandbox_profile's "widens
    the profile" fixtures, one per key shape.

    NOT shared with `march caps` — that goes through
    [run_check_cmd ~emit_caps:true] with its OWN [belongs], keyed on the
    module names the listed files declare (its keys are never entry-unwrapped,
    so the predicates cannot be unified without unifying the key economy).
    Do not restore the pre-2026-08-06 sharing claim without actually sharing
    the predicate.

    [stdlib_files] must list the files whose declarations are the standard
    library's (see [stdlib_span_files]).  The callers pass [desugared] AFTER
    the stdlib prepend — it has to be that module, since that is what gets
    lowered — so the prelude's own top-level functions (`println`, `debug`, …)
    ride in the entry module's decl list.  Without this filter they were
    registered as functions "this file declares", and their capabilities were
    credited to the user's module: measured, `mod M do fn main() do () end end`
    reported IO.Console, which made --cap-strict reject the emptiest possible
    program (IO.Console in the used set with no attributed owner reads as
    "cannot be attributed to any module").  Same gate the typechecker's Check
    1b uses, for the same reason. *)

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

(* MIRRORS the local [impl_ty_key] inside Typecheck's [check_module_needs] —
   the producer of the "Iface$Ty.method" closure keys this file must match.
   Four stable arms; if a fifth impl-target shape ever lands there, the
   "impl method widens the profile" fixture in test_cap_sandbox_profile is
   the drift alarm (its key stops belonging and the grant disappears). *)
let impl_ty_key_of (t : March_ast.Ast.ty) : string =
  match t with
  | March_ast.Ast.TyCon (n, _) -> n.March_ast.Ast.txt
  | March_ast.Ast.TyTuple tys -> Printf.sprintf "$Tuple%d" (List.length tys)
  | March_ast.Ast.TyRecord _ -> "$Record"
  | _ -> "$Unknown"

let own_caps_of_this_module ~stdlib_files typecheck_env
    (m : March_ast.Ast.module_) : string list =
  let own = March_typecheck.Typecheck.fn_own_capability_closures typecheck_env in
  let is_stdlib (sp : March_ast.Ast.span) =
    List.mem sp.March_ast.Ast.file stdlib_files
  in
  let own_keys = Hashtbl.create 64 in
  (* [prefix] follows [check_module_needs]'s [cap_qname] convention: empty at
     the entry level (the entry module is unwrapped), dotted below. *)
  let qname prefix leaf = if prefix = "" then leaf else prefix ^ "." ^ leaf in
  let add prefix leaf = Hashtbl.replace own_keys (qname prefix leaf) () in
  let rec walk prefix decls =
    List.iter (fun (d : March_ast.Ast.decl) ->
        match d with
        | March_ast.Ast.DFn (fd, sp) ->
          if not (is_stdlib sp) then
            add prefix fd.March_ast.Ast.fn_name.March_ast.Ast.txt
        | March_ast.Ast.DLet (_, b, sp) ->
          (match b.March_ast.Ast.bind_pat with
           | March_ast.Ast.PatVar n when not (is_stdlib sp) ->
             add prefix n.March_ast.Ast.txt
           | _ -> ())
        | March_ast.Ast.DImpl (idef, sp) ->
          if not (is_stdlib sp) then begin
            let ty_key = impl_ty_key_of idef.March_ast.Ast.impl_ty in
            List.iter (fun ((mn : March_ast.Ast.name), _) ->
                add prefix
                  (idef.March_ast.Ast.impl_iface.March_ast.Ast.txt
                   ^ "$" ^ ty_key ^ "." ^ mn.March_ast.Ast.txt);
                (* The bare dispatch node ([check_module_needs] emits it when
                   no DFn shares the name; adding it unconditionally is safe —
                   when a DFn does share it, the DFn arm already added it). *)
                add prefix mn.March_ast.Ast.txt)
              idef.March_ast.Ast.impl_methods
          end
        | March_ast.Ast.DActor (_, name, actor, sp) ->
          (* Handler closures are keyed by the DECLARING MODULE
             ("Sub.Weeble_Zorp"), same as a sibling [DFn] — see
             [check_module_needs]'s DActor branch, which stopped keying them
             bare so that two same-named actors in different modules get
             DISTINCT closures.  The actor-NAME node (which carries `init`'s
             caps) is keyed the same way, and is added here too: an `init` that
             writes a file must widen the sandbox profile. *)
          if not (is_stdlib sp) then begin
            add prefix name.March_ast.Ast.txt;
            List.iter (fun (h : March_ast.Ast.actor_handler) ->
                add prefix
                  (name.March_ast.Ast.txt ^ "_"
                   ^ h.March_ast.Ast.ah_msg.March_ast.Ast.txt))
              actor.March_ast.Ast.actor_handlers
          end
        | March_ast.Ast.DMod (nm, _, inner, _) ->
          walk (qname prefix nm.March_ast.Ast.txt) inner
        | _ -> ()) decls
  in
  walk "" m.March_ast.Ast.mod_decls;
  let belongs qname = Hashtbl.mem own_keys qname in
  List.concat_map (fun (qname, cs) -> if belongs qname then cs else []) own
  |> List.sort_uniq String.compare
  |> March_caps.Cap_lattice.normalize
  |> List.sort String.compare

(* --refine-report: bin/main.ml prepends the full stdlib into every module
   before checking it (see stdlib_decls below), so the raw ledger is
   dominated by stdlib obligations and a single unlabelled count would tell a
   user nothing about their own program. Report the user-code slice AND the
   whole-ledger (user + stdlib) slice, clearly labelled, using the same
   "is this span in a file we loaded as user code" test the diagnostic
   printer uses just below each check_module call site. *)
let print_refine_report ~filename ~user_files () =
  let is_user_span (span : March_ast.Ast.span) =
    let f = span.March_ast.Ast.file in
    f = filename || f = "" || f = "<unknown>" || List.mem f user_files
  in
  let summarize obligations =
    let proved = ref 0 and violated = ref 0 and trusted = ref 0 in
    let skips = Hashtbl.create 8 in
    List.iter
      (fun (o : March_refinecheck.Obligation.t) ->
        match o.verdict with
        | March_refinecheck.Obligation.Proved -> incr proved
        | March_refinecheck.Obligation.Violated -> incr violated
        | March_refinecheck.Obligation.Trusted -> incr trusted
        | March_refinecheck.Obligation.Skipped r ->
          Hashtbl.replace skips r (1 + Option.value ~default:0 (Hashtbl.find_opt skips r)))
      obligations;
    (!proved, !violated, !trusted, Hashtbl.fold (fun r n acc -> (r, n) :: acc) skips [])
  in
  (* A postcondition (a function's own return type) and a precondition (a
     callee's declared param type, checked at the call site) are the same
     kind of obligation to the headline totals — a proved postcondition IS a
     proved obligation — but naming the split is cheap and answers "did my
     return types get checked at all", which the headline alone cannot. *)
  let count_kind kind obligations =
    List.length
      (List.filter (fun (o : March_refinecheck.Obligation.t) -> o.kind = kind) obligations)
  in
  let print_block label obligations =
    let proved, violated, trusted, skips = summarize obligations in
    let skipped = List.fold_left (fun a (_, n) -> a + n) 0 skips in
    Printf.eprintf "refinement obligations (%s): %d proved, %d violated, %d trusted, %d skipped\n"
      label proved violated trusted skipped;
    List.iter
      (fun (r, n) ->
        Printf.eprintf "  skipped (%s): %d\n" (March_refinecheck.Obligation.reason_name r) n)
      (List.sort compare skips);
    Printf.eprintf "  by kind: %d precondition, %d postcondition, %d division\n"
      (count_kind March_refinecheck.Obligation.Precondition obligations)
      (count_kind March_refinecheck.Obligation.Postcondition obligations)
      (count_kind March_refinecheck.Obligation.Division obligations)
  in
  let all_obligations = March_refinecheck.Obligation.all () in
  let user_obligations = List.filter (fun (o : March_refinecheck.Obligation.t) -> is_user_span o.span) all_obligations in
  print_block "user code" user_obligations;
  print_block "user + stdlib" all_obligations


let refine_suggest_active () =
  !refine_suggest_target <> None || !refine_suggest_all
  || !refine_suggest_post <> None || !refine_suggest_post_all

let json_escape s =
  let b = Buffer.create (String.length s + 8) in
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | c when Char.code c < 0x20 ->
        Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let print_refine_suggestions ~filename ~user_files desugared =
  let module PI = March_refinecheck.Precond_infer in
  let is_user (span : March_ast.Ast.span) =
    let f = span.March_ast.Ast.file in
    f = filename || List.mem f user_files
  in
  let root = Sys.getcwd () in
  let budget = !refine_suggest_budget in
  let results =
    if !refine_suggest_all then PI.suggest_all ~root ~budget ~is_user desugared
    else
      match !refine_suggest_target with
      | None -> []
      | Some target -> PI.suggest ~root ~budget ~is_user ~target desugared
  in
  if !refine_suggest_json then begin
    let sug_json (s : PI.suggestion) =
      Printf.sprintf
        {|{"param":"%s","base":"%s","predicate":"%s","discharged":%d,"annotation":"{%s | %s}"}|}
        (json_escape s.PI.sg_param) (json_escape s.PI.sg_base)
        (json_escape s.PI.sg_pred) s.PI.sg_discharged
        (json_escape s.PI.sg_base) (json_escape s.PI.sg_pred)
    in
    let one (r : PI.t) =
      Printf.sprintf
        {|{"fn":"%s","file":"%s","line":%d,"col":%d,"status":"%s","debt_before":%d,"debt_after":%d,"queries":%d,"suggestions":[%s]}|}
        (json_escape r.PI.rs_fn)
        (json_escape r.PI.rs_span.March_ast.Ast.file)
        r.PI.rs_span.March_ast.Ast.start_line
        r.PI.rs_span.March_ast.Ast.start_col
        (PI.status_name r.PI.rs_status)
        r.PI.rs_debt_before r.PI.rs_debt_after r.PI.rs_queries
        (String.concat "," (List.map sug_json r.PI.rs_suggestions))
    in
    Printf.printf "{\"suggestions\":[%s]}\n%!"
      (String.concat "," (List.map one results))
  end
  else begin
    (* Human form.  Only the CHANGED parameters are re-spelled: rendering a
       whole signature would need a full type printer whose only job is to be
       wrong about the one type it cannot spell. *)
    List.iter
      (fun (r : PI.t) ->
        match r.PI.rs_status with
        | PI.Not_found ->
          Printf.printf "no user function named `%s`\n" r.PI.rs_fn
        | PI.No_debt ->
          Printf.printf "%s: nothing to prove — every obligation in this body is already discharged\n"
            r.PI.rs_fn
        | PI.No_candidate ->
          Printf.printf
            "%s: %d unproven obligation(s), but no candidate refinement discharges any of them\n"
            r.PI.rs_fn r.PI.rs_debt_before
        | PI.Budget_exhausted ->
          Printf.printf
            "%s: search stopped at the probe budget with %d obligation(s) still unproven — \
             re-run with a larger --refine-suggest-budget\n"
            r.PI.rs_fn r.PI.rs_debt_after
        | PI.Solved | PI.Partial ->
          Printf.printf "%s (%s:%d)\n" r.PI.rs_fn
            r.PI.rs_span.March_ast.Ast.file r.PI.rs_span.March_ast.Ast.start_line;
          List.iter
            (fun (s : PI.suggestion) ->
              Printf.printf "    %s : %s  ->  %s : {%s | %s}\n" s.PI.sg_param
                s.PI.sg_base s.PI.sg_param s.PI.sg_base s.PI.sg_pred)
            r.PI.rs_suggestions;
          if r.PI.rs_status = PI.Solved then
            Printf.printf "  discharges all %d unproven obligation(s)\n"
              r.PI.rs_debt_before
          else
            Printf.printf "  discharges %d of %d; %d still unproven\n"
              (r.PI.rs_debt_before - r.PI.rs_debt_after)
              r.PI.rs_debt_before r.PI.rs_debt_after)
      results;
    if results = [] then Printf.printf "no suggestions\n"
  end

let print_refine_postconditions ~filename ~user_files desugared =
  let module PO = March_refinecheck.Postcond_infer in
  let is_user (span : March_ast.Ast.span) =
    let f = span.March_ast.Ast.file in
    f = filename || List.mem f user_files
  in
  let root = Sys.getcwd () in
  let budget = !refine_suggest_budget in
  let results =
    if !refine_suggest_post_all then PO.suggest_all ~root ~budget ~is_user desugared
    else
      match !refine_suggest_post with
      | None -> []
      | Some target -> PO.suggest ~root ~budget ~is_user ~target desugared
  in
  if !refine_suggest_json then begin
    let one (r : PO.t) =
      Printf.sprintf
        {|{"fn":"%s","file":"%s","line":%d,"col":%d,"status":"%s","base":"%s","predicate":"%s","annotation":"{%s | %s}","callers":%d,"debt_before":%d,"debt_after":%d,"queries":%d}|}
        (json_escape r.PO.rs_fn)
        (json_escape r.PO.rs_span.March_ast.Ast.file)
        r.PO.rs_span.March_ast.Ast.start_line
        r.PO.rs_span.March_ast.Ast.start_col
        (PO.status_name r.PO.rs_status)
        (json_escape r.PO.rs_base) (json_escape r.PO.rs_pred)
        (json_escape r.PO.rs_base) (json_escape r.PO.rs_pred)
        r.PO.rs_callers r.PO.rs_debt_before r.PO.rs_debt_after r.PO.rs_queries
    in
    Printf.printf "{\"postconditions\":[%s]}\n%!"
      (String.concat "," (List.map one results))
  end
  else begin
    List.iter
      (fun (r : PO.t) ->
        match r.PO.rs_status with
        | PO.Not_found -> Printf.printf "no user function named `%s`\n" r.PO.rs_fn
        | PO.No_return_type ->
          Printf.printf "%s: no declared return type to refine\n" r.PO.rs_fn
        | PO.Already_refined ->
          Printf.printf "%s: its return is already refined\n" r.PO.rs_fn
        | PO.No_callers ->
          Printf.printf
            "%s: nothing calls it here, so there is no obligation a postcondition could discharge\n"
            r.PO.rs_fn
        | PO.No_debt ->
          Printf.printf "%s: its callers have no unproven obligations\n" r.PO.rs_fn
        | PO.No_candidate ->
          Printf.printf
            "%s: %d unproven obligation(s) in %d caller(s), but no candidate postcondition is both provable and useful\n"
            r.PO.rs_fn r.PO.rs_debt_before r.PO.rs_callers
        | PO.Solved | PO.Partial ->
          Printf.printf "%s (%s:%d)\n" r.PO.rs_fn
            r.PO.rs_span.March_ast.Ast.file r.PO.rs_span.March_ast.Ast.start_line;
          Printf.printf "    returns %s  ->  returns {%s | %s}\n"
            r.PO.rs_base r.PO.rs_base r.PO.rs_pred;
          if r.PO.rs_status = PO.Solved then
            Printf.printf "  discharges all %d obligation(s) across %d caller(s)\n"
              r.PO.rs_debt_before r.PO.rs_callers
          else
            Printf.printf "  discharges %d of %d across %d caller(s); %d still unproven\n"
              (r.PO.rs_debt_before - r.PO.rs_debt_after) r.PO.rs_debt_before
              r.PO.rs_callers r.PO.rs_debt_after)
      results;
    if results = [] then Printf.printf "no postcondition suggestions\n"
  end

let hr_config () =
  Option.map March_tir.Hot_reload.default_config !hot_reload_prefix
(* CAS cache-key fragment — hot reload changes codegen, so it MUST key the cache. *)
let hr_cas_tag () = match !hot_reload_prefix with Some p -> ["hr:" ^ p] | None -> []
(* CAS cache-key fragments for the remaining toggles that alter the emitted
   binary: MARCH_SANITIZE adds -fsanitize to the clang link, MARCH_HTTP_EVLOOP
   adds -DMARCH_HTTP_USE_EVLOOP, --fast-math changes IR emission, and
   --debug/--debug-tui add -g. Any toggle missing here lets a cached artifact
   silently shadow the requested codegen. (MARCH_DEBUG_RUNTIME is deliberately
   absent: it only affects the interpreter/JIT runtime .so, which is keyed by
   its own flags_sig content key.) *)
(* Version of the C-runtime compilation FLAGS (as opposed to its source, which
   compiler_identity/runtime_identity already digest).  compilation_hash mixes in
   the compiler executable's bytes, but a released/cached toolchain can serve a
   binary built with a DIFFERENT set of runtime cflags (e.g. before/after adding
   -fno-strict-aliasing -fwrapv) whenever the exe digest happens to match — the
   flags themselves are not otherwise in the key.  Bump this whenever the runtime
   clang/cc invocation flags change so no stale artifact can shadow the new ABI.
   v2 = runtime now built with -fno-strict-aliasing -fwrapv. *)
let codegen_cas_tags () =
  "rtcflags2"
  :: (if Sys.getenv_opt "MARCH_SANITIZE" <> None then ["sanitize"] else [])
  (* TRMC rewrites eligible functions into destination-passing style, so it
     changes the emitted binary.  Without this tag a cached non-TRMC artifact
     silently satisfies a TRMC build and vice versa — which is exactly how the
     first TRMC benchmark run reported a 0.06s "TRMC off" number that was
     really the TRMC binary served from the cache.  Reads the ref, not the env
     var, so --trmc/--no-trmc are also CAS-distinct; every cas_flags site is
     inside [compile], which runs after Arg.parse has set it. *)
  @ (if !March_tir.Trmc.enabled then ["trmc"] else [])
  @ (if (try Sys.getenv "MARCH_HTTP_EVLOOP" = "1" with Not_found -> false)
     then ["evloop"] else [])
  @ (if !fast_math then ["fast-math"] else [])
  @ (if !debug_mode || !debug_tui_mode then ["dbg"] else [])

(** Parse --target string into Llvm_emit.target_config. *)
let parse_target s =
  match String.lowercase_ascii s with
  | "native" -> March_tir.Llvm_emit.Native
  | "wasm64-wasi" | "wasm64" -> March_tir.Llvm_emit.Wasm64Wasi
  | "wasm32-wasi" | "wasm32" -> March_tir.Llvm_emit.Wasm32Wasi
  | "wasm32-unknown-unknown" | "wasm-browser" | "browser" -> March_tir.Llvm_emit.Wasm32Unknown
  | "js" | "javascript" -> March_tir.Llvm_emit.Js
  (* glibc floor 2.36 matches the deploy image (debian:bookworm-slim ships glibc
     2.36) and, crucially, is the minimum that TLS builds need: the target
     libcrypto.so.3 references GLIBC_2.34 symbols (pthread_getspecific@2.34,
     dlsym/dlclose@2.34 — that's where libdl merged into libc) plus stat@2.33,
     which a lower floor's libc doesn't provide, so `ld.lld
     --no-allow-shlib-undefined` rejects the link.  Bumping from 2.31→2.36 trades
     pre-bookworm portability (which the hot-deploy target does not need) for a
     TLS-capable cross link.  See specs/…cross-compile-linux-hot-deploy-design.md
     §5 (P3). *)
  | "linux/amd64" | "linux/x86_64" | "linux-x86_64" ->
    March_tir.Llvm_emit.(LinuxGnu { arch = X86_64; glibc_min = "2.36" })
  | "linux/arm64" | "linux/aarch64" | "linux-arm64" ->
    March_tir.Llvm_emit.(LinuxGnu { arch = Arm64; glibc_min = "2.36" })
  | other ->
    Printf.eprintf "march: unknown target '%s'\n  Valid targets: native, linux/amd64, linux/arm64, wasm64-wasi, wasm32-wasi, wasm32-unknown-unknown, js\n" other;
    exit 1

(* ------------------------------------------------------------------ *)
(* CAS cache key                                                       *)
(* ------------------------------------------------------------------ *)

(** The clang -O level actually used: [!opt_level] when explicitly set in
    range, 2 otherwise.  Shared by [build_cas_key] and the clang invocation so
    the cached-under level and the compiled-at level cannot drift apart. *)
let effective_opt () =
  if !opt_level >= 0 && !opt_level <= 3 then !opt_level else 2

(** Stable string name for a target, used as the CAS key's [~target] component.

    Distinct from [!target_str]: the glibc floor is folded in here, so bumping
    it invalidates cached cross binaries. *)
let cas_target_label (target : March_tir.Llvm_emit.target_config) : string =
  match target with
  | March_tir.Llvm_emit.Native -> "native"
  | March_tir.Llvm_emit.LinuxGnu { arch = March_tir.Llvm_emit.X86_64; glibc_min } ->
    "linux-x86_64-gnu-" ^ glibc_min
  | March_tir.Llvm_emit.LinuxGnu { arch = March_tir.Llvm_emit.Arm64; glibc_min } ->
    "linux-arm64-gnu-" ^ glibc_min
  | March_tir.Llvm_emit.Wasm64Wasi -> "wasm64-wasi"
  | March_tir.Llvm_emit.Wasm32Wasi -> "wasm32-wasi"
  | March_tir.Llvm_emit.Wasm32Unknown -> "wasm32-unknown-unknown"
  | March_tir.Llvm_emit.Js -> "js"

(** Build the CAS cache key: the flag list plus the compilation hash.

    THE only place codegen flags enter the cache key.  A flag that affects the
    emitted binary but is missing from this list makes two semantically
    different builds collide on one cache entry, and the cache then serves the
    wrong binary — a silently stale result, not an error.  Adding a codegen
    flag anywhere in this file means adding it *here*, once.

    Two call sites use this, at two different cache layers: the early
    source-level check in [compile] (keyed on the source digest, before parsing)
    and the post-TIR check (keyed on the module's per-SCC impl hashes).  They
    differ only in [src_hash]; every flag is shared.  The cross-sysroot digest
    is computed here rather than passed in, because it is a pure function of
    [target] and so cannot legitimately diverge between the layers either.

    [MARCH_DEBUG_CASFLAGS=1] prints the resulting key, from both sites. *)
let build_cas_key ~(target : March_tir.Llvm_emit.target_config)
      ~(target_label : string) ~(src_hash : string) : string list * string =
  (* Cross-toolchain identity: the target OpenSSL/zlib .so live OUTSIDE the
     repo (~/.cache/march/cross-sysroot), so runtime_identity (which digests
     only runtime/*.c/*.h) does NOT cover them.  Fold a digest of the three
     sysroot .so files into cas_flags so re-fetching a different
     OpenSSL/zlib version invalidates cached cross binaries.  The glibc
     floor is already in target_label. *)
  let cross_sysroot_tag =
    match linux_arch_str target with
    | None -> []
    | Some arch ->
      (match cross_sysroot_dir arch with
       | Some d -> ["xsysroot:" ^ cross_sysroot_digest d]
       | None -> [])
  in
  let cas_flags =
    (if !opt_enabled then Printf.sprintf "O%d" (effective_opt ()) else "no-opt")
    :: Printf.sprintf "pmt%d" !pmap_threshold
    :: (hr_cas_tag () @ ffi_cas_tag () @ codegen_cas_tags ()
        @ (if !compile_so then ["compile-so"] else [])
        (* capstrip: the dead-strip link mode (strip_flag/section_cflags
           below) changes the emitted binary's contents; a pre-strip
           cached artifact must never satisfy a post-strip build or the
           cap inspect silently reports every capability. Mirrors the
           eligibility condition on strip_flag. *)
        @ (if !compile_so || !hot_reload_prefix <> None
           then [] else ["capstrip"])
        (* --cap-sandbox changes the emitted binary (a -D define), so a
           non-sandboxed cached artifact must never satisfy it. *)
        @ (if !cap_sandbox then ["capsandbox"] else [])
        @ (if !cap_strict then ["capstrict"] else [])
        @ cross_sysroot_tag
        @ (if !signing_pubkey <> "" then ["spk:" ^ !signing_pubkey] else [])) in
  let ch = March_cas.Cas.compilation_hash src_hash ~target:target_label ~flags:cas_flags in
  (if Sys.getenv_opt "MARCH_DEBUG_CASFLAGS" <> None then
     Printf.eprintf "MARCH_CASFLAGS: target=%s flags=[%s] ch=%s\n%!"
       target_label (String.concat "," cas_flags) ch);
  (cas_flags, ch)

(* ------------------------------------------------------------------ *)
(* Formatter helpers                                                   *)
(* ------------------------------------------------------------------ *)

(** Read a file's contents, returning the string. *)
let read_file path =
  let ic = open_in path in
  let n  = in_channel_length ic in
  let buf = Bytes.create n in
  really_input ic buf 0 n;
  close_in ic;
  Bytes.to_string buf

(** Write [contents] to [path] atomically (via a temp file). *)
let write_file path contents =
  let tmp = path ^ ".fmt.tmp" in
  let oc = open_out tmp in
  output_string oc contents;
  close_out oc;
  Sys.rename tmp path

(* ------------------------------------------------------------------ *)
(* Cross-file import resolver (delegated to march_resolver library)  *)
(* ------------------------------------------------------------------ *)

(** Recursively collect all .march files under [dir].
    (Re-exported from the shared resolver for callers below.) *)
let collect_lib_files = March_resolver.Resolver.collect_lib_files

(** Cross-file import resolution — single shared implementation in
    lib/resolver (also used by the REPL and the LSP), so editor
    diagnostics, REPL loads, and forge builds resolve modules identically. *)
let resolve_imports ~source_file m =
  March_resolver.Resolver.resolve_imports ~source_file m

(** Format [filename] in-place.  Returns true if the file was changed. *)
let fmt_file filename =
  let src = read_file filename in
  let formatted =
    try March_format.Format.format_source ~filename src
    with
    | March_errors.Errors.ParseError (msg, hint, _) ->
      Printf.eprintf "%s\n"
        (March_errors.Errors.render_parse_error ~src ~filename ?hint ~msg
           (Lexing.from_string src));
      exit 1
    | March_parser.Parser.Error ->
      let lexbuf = Lexing.from_string src in
      lexbuf.Lexing.lex_curr_p <-
        { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
      Printf.eprintf "%s\n"
        (March_errors.Errors.render_parse_error ~src ~filename
           ~msg:"Parse error (cannot format)" lexbuf);
      exit 1
  in
  formatted <> src, formatted

(** Collect all .march files under a directory recursively.
    Tolerant of unreadable entries: a permission-denied subdirectory (whose
    [Sys.readdir] raises) or an entry we cannot [Sys.is_directory]-stat (e.g. a
    dangling symlink) is skipped rather than aborting the whole walk — mirrors
    [March_resolver.Resolver.collect_lib_files]. *)
let rec march_files_in dir =
  let entries = try Sys.readdir dir with Sys_error _ -> [||] in
  Array.sort compare entries;
  Array.fold_left (fun acc entry ->
    (* Skip dotfiles/dotdirs and macOS AppleDouble junk. "._x.march" is a binary
       resource-fork file macOS creates (invisible there, a real file on Linux)
       that ends in ".march" but is NOT source — the lexer chokes on its leading
       NUL. Also skips .git/.march/etc. Never a source module either way. *)
    if String.length entry > 0 && entry.[0] = '.' then acc
    else
    let path = Filename.concat dir entry in
    match Sys.is_directory path with
    | true -> acc @ march_files_in path
    | false -> if Filename.check_suffix path ".march" then acc @ [path] else acc
    | exception (Sys_error _ | Unix.Unix_error _) -> acc
  ) [] entries

(** Run the test subcommand and exit.
    Discovers test files, parses/typechecks them, and runs all test blocks.
    Usage: march test [--verbose|-v] [--filter=pattern] [file...] *)
let run_test_cmd args =
  let verbose  = ref false in
  let filter   = ref "" in
  let coverage = ref false in
  let targets  = ref [] in
  let rec parse_args = function
    | [] -> ()
    | a :: rest when a = "--verbose" || a = "-v" -> verbose := true; parse_args rest
    | a :: rest when a = "--coverage" -> coverage := true; parse_args rest
    | a :: rest when String.length a > 9 && String.sub a 0 9 = "--filter=" ->
      filter := String.sub a 9 (String.length a - 9); parse_args rest
    | a :: rest when String.length a > 7 && String.sub a 0 7 = "--seed=" ->
      Unix.putenv "MARCH_PROP_SEED" (String.sub a 7 (String.length a - 7)); parse_args rest
    | a :: rest when a = "--skip-properties" ->
      Unix.putenv "MARCH_SKIP_PROPERTIES" "1"; parse_args rest
    (* --ffi-c/--ffi-link/--ffi-so take their value as the next token, matching
       the Arg.String convention used by the generic (non-test) CLI path. *)
    | "--ffi-c" :: v :: rest -> ffi_c_files := v :: !ffi_c_files; parse_args rest
    | "--ffi-link" :: v :: rest -> ffi_link_flags := v :: !ffi_link_flags; parse_args rest
    | "--ffi-so" :: v :: rest -> March_eval.Eval.ffi_shim_so := Some v; parse_args rest
    | a :: rest -> targets := a :: !targets; parse_args rest
  in
  parse_args args;
  let targets = List.rev !targets in
  (* Same FFI wiring the plain interpreter path uses (setup_interpreter_ffi),
     so tests that call into forge.toml [ffi] shims (e.g. depot's sqlite
     shim) can resolve march runtime symbols under `march test`. *)
  setup_interpreter_ffi ();
  (* If no explicit files given, auto-discover test/test_*.march and test/*_test.march *)
  let files =
    if targets <> [] then targets
    else begin
      let test_dir = "test" in
      if not (Sys.file_exists test_dir) then []
      else
        (* Skip an unreadable test/ (permission-denied) the same way we skip a
           missing one, rather than crashing on the [Sys.readdir]. *)
        let entries =
          List.sort compare
            (Array.to_list (try Sys.readdir test_dir with Sys_error _ -> [||])) in
        List.filter_map (fun name ->
          if (String.length name > 6 && String.sub name 0 5 = "test_"
              && Filename.check_suffix name ".march")
          || Filename.check_suffix name "_test.march"
          then Some (Filename.concat test_dir name)
          else None
        ) entries
    end
  in
  if files = [] then begin
    Printf.eprintf "march test: no test files found\n";
    Printf.eprintf "  Put test files in test/ named test_*.march or *_test.march\n";
    exit 0
  end;
  let total_files = List.length files in
  let total_tests = ref 0 in
  let total_failed = ref 0 in
  let failed_files = ref [] in
  (* In quiet mode (non-verbose), collect failures across files for end-of-run reporting. *)
  let all_file_failures : (string * (string * string) list) list ref = ref [] in
  List.iter (fun filename ->
    let src =
      try read_file filename
      with Sys_error msg ->
        Printf.eprintf "march test: %s\n" msg; exit 1
    in
    if !verbose then Printf.printf "%s\n%!" filename;
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
    let module_ast =
      try March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
      with
      | March_errors.Errors.ParseError (msg, hint, _) ->
        Printf.eprintf "\n%s\n"
          (March_errors.Errors.render_parse_error ~src ~filename ?hint ~msg lexbuf);
        exit 1
      | March_parser.Parser.Error ->
        Printf.eprintf "\n%s\n"
          (March_errors.Errors.render_parse_error ~src ~filename ~msg:"Parse error:" lexbuf);
        exit 1
    in
    let parse_errs = March_parser.Parse_errors.take_parse_errors () in
    if parse_errs <> [] then begin
      List.iter (fun (msg, _hint, pos) ->
        let open Lexing in
        Printf.eprintf "%s:%d:%d: error: %s\n"
          filename pos.pos_lnum (pos.pos_cnum - pos.pos_bol) msg
      ) parse_errs;
      exit 1
    end;
    let desugar_errors = March_errors.Errors.create () in
    let desugared = March_desugar.Desugar.desugar_module ~errors:desugar_errors module_ast in
    if March_errors.Errors.has_errors desugar_errors then begin
      List.iter (fun (d : March_errors.Errors.diagnostic) ->
          Printf.eprintf "%s:%d:%d: %s: %s\n"
            d.span.March_ast.Ast.file d.span.March_ast.Ast.start_line
            d.span.March_ast.Ast.start_col (severity_word d.severity) d.message
        ) (March_errors.Errors.sorted desugar_errors);
      exit 1
    end;
    let (resolve_errors, extra_decls, user_files) = resolve_imports ~source_file:filename desugared in
    if resolve_errors <> [] then begin
      List.iter (fun (_mod_name, span, msg) ->
          Printf.eprintf "%s:%d:%d: error: %s\n"
            span.March_ast.Ast.file span.March_ast.Ast.start_line
            span.March_ast.Ast.start_col msg
        ) resolve_errors;
      exit 1
    end;
    let desugared =
      { desugared with
        March_ast.Ast.mod_decls = extra_decls @ desugared.March_ast.Ast.mod_decls }
    in
    let stdlib_decls = load_stdlib () in
    if not (is_shipped_stdlib_file filename) then
      check_no_prelude_collision ~stdlib_decls desugared;
    let desugared =
      { desugared with
        March_ast.Ast.mod_decls = stdlib_decls @ desugared.March_ast.Ast.mod_decls }
    in
    (* This pipeline runs [Panic_surface_by_proof] below, so the typechecker's
       syntactic ban must leave the contracted names to it.  Set BEFORE
       [check_module] — the flag is read during that call. *)
    March_typecheck.Typecheck.proof_based_panic_surface := true;
    let (errors, _type_map) = March_typecheck.Typecheck.check_module desugared in
    (* Phase A1b: discharge refinement-precondition VCs at call sites. *)
    March_refinecheck.Refine_check.check_module ~measure_axioms:!measure_axioms
      ~stdlib_files:(stdlib_span_files stdlib_decls) errors desugared;
    if !refine_report then print_refine_report ~filename ~user_files ();
    (* Division-safety: Z3-backed check for `cap no_panic` modules. *)
    March_refinecheck.Division_safety.check_module errors desugared;
    (* Panic-surface-by-proof: the `cap no_panic` names that carry a real
       refinement contract are admitted when their call site's PRECONDITION was
       actually discharged, rather than banned by name.  It must run here, after
       [Refine_check.check_module] has populated the per-call-site verdict index
       (and after [Division_safety], which only adds to it) — inside the
       typechecker, where the syntactic ban lives, that index does not exist
       yet. *)
    March_refinecheck.Panic_surface_by_proof.check_module errors desugared;
    (* Allocation checker: flag heap-allocating exprs in `cap no_alloc` modules. *)
    March_refinecheck.No_alloc.check_module errors desugared;
    (* Cap-infer: emit hints at call sites missing a `needs` declaration. *)
    March_refinecheck.Cap_infer.check_module errors desugared;
    (* Solving scope ends here: reap the shared z3 child now rather than
       holding an idle solver process for the rest of the run. *)
    March_refine.Refine.shutdown ();
    let diags = March_errors.Errors.sorted errors in
    (* Fatal when the diagnostic points into any file loaded as user code:
       the entry file or imported modules (source dir / MARCH_LIB_PATH). *)
    let is_user_file (d : March_errors.Errors.diagnostic) =
      let f = d.span.March_ast.Ast.file in
      f = filename || f = "" || f = "<unknown>" || List.mem f user_files
    in
    let has_user_errors = List.exists (fun (d : March_errors.Errors.diagnostic) ->
        d.severity = March_errors.Errors.Error && is_user_file d
      ) diags in
    if has_user_errors then begin
      List.iter (fun (d : March_errors.Errors.diagnostic) ->
        if is_user_file d && d.severity = March_errors.Errors.Error then begin
          (* Render against the file the span points into — imported-module
             errors must not be shown with the entry file's source lines. *)
          let f = d.span.March_ast.Ast.file in
          let (d_src, d_file) =
            if f = filename || f = "" || f = "<unknown>" then (src, filename)
            else (try read_file f with Sys_error _ -> src), f
          in
          Printf.eprintf "%s\n\n\n"
            (March_errors.Errors.render_diagnostic ~src:d_src ~filename:d_file d)
        end
      ) diags;
      exit 1
    end;
    (* Enable coverage tracking for this file's test run. *)
    if !coverage then begin
      March_coverage.Coverage.reset ();
      March_coverage.Coverage.coverage_enabled := true
    end;
    (* Check whether the test source opts into IO capture via @capture_io. *)
    let capture_io =
      let pat = "@capture_io" in
      let n = String.length src and p = String.length pat in
      let rec check i =
        if i + p > n then false
        else if String.sub src i p = pat then true
        else check (i + 1)
      in check 0
    in
    let (n_tests, n_failed, file_failures) =
      if !verbose then
        March_eval.Eval.run_tests ~verbose:true ~filter:!filter ~capture_io desugared
      else
        March_eval.Eval.run_tests ~dot_stream:true ~filter:!filter ~capture_io desugared
    in
    if !coverage then begin
      March_coverage.Coverage.coverage_enabled := false;
      March_coverage.Coverage.report_summary ~target_file:filename desugared ()
    end;
    total_tests  := !total_tests + n_tests;
    total_failed := !total_failed + n_failed;
    if n_failed > 0 then begin
      failed_files := filename :: !failed_files;
      if not !verbose then
        all_file_failures := (filename, file_failures) :: !all_file_failures
    end;
    (* Run doctests extracted from fn_doc fields *)
    let parse_expr src =
      (* Wrap in `do ... end` so a doctest chaining a `let` line into a
         following statement (see March_doctest.Doctest.extract) parses as
         a block body; a single bare expression degenerates to itself. *)
      let wrapped = "do\n" ^ src ^ "\nend" in
      let lexbuf = Lexing.from_string wrapped in
      let expr =
        try March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
        with
        | March_errors.Errors.ParseError (msg, _, _) ->
          failwith ("doctest parse error: " ^ msg)
        | March_parser.Parser.Error ->
          failwith ("doctest parse error in: " ^ src)
      in
      March_desugar.Desugar.desugar_expr expr
    in
    let (dt_total, dt_failed, dt_failures) =
      if !verbose then
        March_eval.Eval.run_doctests ~verbose:true ~filter:!filter ~parse_expr desugared
      else
        March_eval.Eval.run_doctests ~quiet:true ~filter:!filter ~parse_expr desugared
    in
    total_tests  := !total_tests + dt_total;
    total_failed := !total_failed + dt_failed;
    if dt_failed > 0 then begin
      if not (List.mem filename !failed_files) then
        failed_files := filename :: !failed_files;
      if not !verbose then
        all_file_failures := (filename, dt_failures) :: !all_file_failures
    end
  ) files;
  (* End the dot line after all files *)
  if not !verbose then Printf.printf "\n%!";
  (* Print collected failure details grouped by file. *)
  if not !verbose && !all_file_failures <> [] then begin
    List.iter (fun (filename, failures) ->
      Printf.printf "%s\n" filename;
      List.iter (fun (name, msg) ->
        Printf.printf "  FAIL: \"%s\"\n    %s\n\n" name
          (String.concat "\n    " (String.split_on_char '\n' msg))
      ) failures
    ) (List.rev !all_file_failures)
  end;
  let n_failed_files = List.length !failed_files in
  if n_failed_files = 0 then
    Printf.printf "=== %d file%s, %d test%s passed ===\n%!"
      total_files (if total_files = 1 then "" else "s")
      !total_tests (if !total_tests = 1 then "" else "s")
  else
    Printf.printf "=== %d/%d file%s, %d/%d test%s failed ===\n%!"
      n_failed_files total_files (if total_files = 1 then "" else "s")
      !total_failed !total_tests (if !total_tests = 1 then "" else "s");
  if !total_failed > 0 then exit 1
  else exit 0

(** Run the fmt subcommand and exit. *)
let run_fmt args =
  (* Parse flags and collect targets *)
  let check_mode = ref false in
  let stdin_mode = ref false in
  let targets    = ref [] in
  List.iter (fun a ->
    if a = "--check" then check_mode := true
    else if a = "--stdin" then stdin_mode := true
    else targets := a :: !targets
  ) args;
  (* --stdin: read from stdin, format, write to stdout *)
  if !stdin_mode then begin
    let buf = Buffer.create 4096 in
    (try while true do Buffer.add_char buf (input_char stdin) done
     with End_of_file -> ());
    let src = Buffer.contents buf in
    let filename = match !targets with f :: _ -> f | [] -> "<stdin>" in
    let formatted =
      try March_format.Format.format_source ~filename src
      with _ -> src
    in
    print_string formatted;
    exit 0
  end;
  let targets = List.rev !targets in
  let files = List.concat_map (fun target ->
    if target = "." || (Sys.file_exists target && Sys.is_directory target) then
      march_files_in target
    else
      [target]
  ) targets in
  if files = [] then begin
    Printf.eprintf "march fmt: no files specified\n"; exit 1
  end;
  let any_changed = ref false in
  List.iter (fun f ->
    let changed, formatted = fmt_file f in
    if !check_mode then begin
      if changed then begin
        Printf.eprintf "%s: not formatted\n" f;
        any_changed := true
      end
    end else begin
      if changed then begin
        write_file f formatted;
        Printf.printf "formatted %s\n%!" f
      end
    end
  ) files;
  if !check_mode && !any_changed then exit 1
  else exit 0


(* ------------------------------------------------------------------ *)
(* File compiler                                                       *)
(* ------------------------------------------------------------------ *)

(* Exit code for "the compile pipeline (Lower -> Perceus/Opt -> Llvm_emit)
   raised an uncaught OCaml exception on a program that already typechecked
   cleanly" — i.e. an internal compiler bug, not a diagnosed user error.
   Distinct from the exit codes already in use elsewhere in this file:
     0 = success, 1 = diagnosed error (parse/typecheck/user), 2 = usage/CLI
   error.  3 is otherwise unused; picked here and documented so callers
   (notably the differential oracle, test/test_properties.ml) can treat it
   as an unambiguous "compiler crashed" signal instead of sniffing stderr
   text. See specs/2026-07-04-differential-oracle-design.md §4.1: a survey
   of lib/tir/*.ml's ~33 failwith/assert-false sites (Oracle Task 2) found
   NONE are a deliberate "typechecked but not lowerable yet" marker — every
   site is an internal-invariant check (the typechecker/desugarer should
   have prevented reaching that state) or closed-set exhaustiveness (e.g.
   operator-name tables). There is no genuine "unsupported construct"
   category to signal separately; anything that reaches here is a bug. *)
let internal_compiler_error_exit_code = 3

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
        | March_ast.Ast.DNeeds (_, sp) | March_ast.Ast.DProofCap (_, sp)
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

let compile filename =
  (* Enable backtraces so an internal-error report (below) is actionable
     even without OCAMLRUNPARAM=b. *)
  Printexc.record_backtrace true;
  let is_js_target = parse_target !target_str = March_tir.Llvm_emit.Js in
  let src =
    try read_file filename
    with Sys_error msg ->
      Printf.eprintf "march: %s\n" msg;
      exit 1
  in
  (* --fmt: format the source file before compiling *)
  if !do_fmt then begin
    let changed, formatted = fmt_file filename in
    if changed then begin
      write_file filename formatted;
      Printf.eprintf "formatted %s\n%!" filename
    end
  end;
  (* Early source-hash CAS: read all input bytes, compute hash, and exit
     before parsing if sources are unchanged since the last successful run.
     This fires for both --check (exit 0) and --compile (copy + exit 0).
     Moving it before the parse+resolve pipeline saves ~0.25s on cache hits. *)
  let early_cas =
    (* An artifact hit exits BEFORE the refinement passes run, so any flag whose
       whole output comes from those passes must suppress the early exit or it
       silently prints nothing on a warm cache — which is exactly how
       --refine-report came to look broken.  Correctness of a diagnostic flag
       beats a cache hit on the run that asked for the diagnostic. *)
    if refine_suggest_active () || !refine_report then None
    else if not !do_compile && not !do_check then None
    else begin
      let buf = Buffer.create (256 * 1024) in
      Buffer.add_string buf src;
      (match stdlib_source_hash ~for_js:is_js_target () with
       | Some (_, h, _) -> Buffer.add_string buf h
       | None -> ());
      (* Hash every .march file the resolver will load as user code: the
         entry's OWN source directory (siblings are auto-discovered by
         resolve_imports — search_path = source_dir :: lib paths) plus all
         MARCH_LIB_PATH directories.  Omitting the source-dir siblings let a
         cached OK artifact survive edits to an imported sibling module, so
         --check/--compile exited 0 on an ill-typed program without ever
         typechecking it.  The entry file is skipped (its bytes are already
         the first buffer element); realpath comparison so relative/absolute
         spellings of the entry don't double-count or slip through. *)
      let lib_path = try Sys.getenv "MARCH_LIB_PATH" with Not_found -> "" in
      let lib_dirs =
        List.filter (fun d -> d <> "") (String.split_on_char ':' lib_path) in
      let entry_real =
        (try Unix.realpath filename with Unix.Unix_error _ -> filename) in
      List.iter (fun dir ->
        let files = List.sort String.compare (collect_lib_files dir) in
        List.iter (fun fp ->
          let fp_real =
            (try Unix.realpath fp with Unix.Unix_error _ -> fp) in
          if fp_real <> entry_real then begin
            Buffer.add_string buf fp;
            (try
              let ic = open_in_bin fp in
              let n  = in_channel_length ic in
              let b  = Bytes.create n in
              really_input ic b 0 n;
              close_in ic;
              Buffer.add_bytes buf b
            with Sys_error _ -> ())
          end
        ) files
      ) (Filename.dirname filename :: lib_dirs);
      let src_hash = "src:" ^ Digest.to_hex (Digest.string (Buffer.contents buf)) in
      let store = March_cas.Cas.create ~project_root:(Sys.getcwd ()) in
      if !do_check then begin
        let ch = March_cas.Cas.compilation_hash src_hash ~target:"check" ~flags:[] in
        (match March_cas.Cas.lookup_artifact store ch with
         | Some _ -> exit 0
         | None -> ());
        Some (store, ch)
      end else begin (* !do_compile *)
        let target_parsed = parse_target !target_str in
        let target_label  = cas_target_label target_parsed in
        (* Source-level early cache: same key construction as the post-TIR check
           below (build_cas_key), keyed on the source digest instead of the
           module's impl hashes. *)
        let (_, ch) =
          build_cas_key ~target:target_parsed ~target_label ~src_hash in
        let is_wasm  = March_tir.Llvm_emit.is_wasm_target target_parsed in
        let basename = Filename.remove_extension filename in
        let out_bin  =
          if !output_file <> "" then !output_file
          else if is_wasm then basename ^ ".wasm"
          else if target_parsed = March_tir.Llvm_emit.Js then basename ^ ".mjs"
          else basename
        in
        (match March_cas.Cas.lookup_artifact store ch with
         | Some cached_bin
           when March_cas.Cas.copy_artifact ~src:cached_bin ~dest:out_bin ->
           Printf.eprintf "compiled %s (cached)\n" out_bin;
           exit 0
         (* Stale/missing artifact or failed copy → recompile *)
         | Some _ | None -> ());
        Some (store, ch)
      end
    end
  in
  (* Per-stage timing: stamp records wall time since just before parsing.
     Enabled by --timings; output goes to stderr so it doesn't mix with
     the compiled binary's stdout. *)
  let t_compile_start = Unix.gettimeofday () in
  let stamp label =
    if !do_timings then
      Printf.eprintf "[timings] %6.3fs  %s\n%!" (Unix.gettimeofday () -. t_compile_start) label
  in
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
  (* Parse *)
  (* A hard parse failure (unlike a desugar/typecheck error) produces no
     [module_ast] at all — [compile] exits right here, well before the
     --emit-core-ast / --check-json branches further down ever run. Per the
     Global Constraints ("if march produces a parse ... error before
     typecheck is even reached, that's 'reject' too, with those
     diagnostics"), --emit-core-ast must still emit its one JSON document
     to stdout in this case, so it gets its own short-circuit here rather
     than falling through to the plain-text-only exit. There is no AST to
     serialize, so "module" is JSON null. *)
  let emit_core_ast_parse_failure (diag : March_errors.Errors.diagnostic) =
    if !emit_core_ast_file <> None then begin
      let doc =
        March_dump.Dump.json_obj [
          ("format_version", "3");
          ("verdict", March_dump.Dump.json_string "reject");
          ("diagnostics",
           March_dump.Dump.json_list [March_errors.Errors.render_diagnostic_json diag]);
          ("module", "null");
          ("schemes", "[]");
          ("instantiations", "[]");
          ("module_caps", "[]");
        ]
      in
      print_string doc
    end
  in
  let module_ast =
    try March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
    with
    | March_errors.Errors.ParseError (msg, hint, _) ->
      Printf.eprintf "%s\n"
        (March_errors.Errors.render_parse_error ~src ~filename ?hint ~msg lexbuf);
      emit_core_ast_parse_failure
        (March_errors.Errors.parse_error_diagnostic ~filename ?hint ~msg lexbuf);
      exit 1
    | March_parser.Parser.Error ->
      Printf.eprintf "%s\n"
        (March_errors.Errors.render_parse_error ~src ~filename ~msg:"I got stuck here:" lexbuf);
      emit_core_ast_parse_failure
        (March_errors.Errors.parse_error_diagnostic ~filename ~msg:"I got stuck here:" lexbuf);
      exit 1
  in
  (* Display any declaration-level parse errors collected during recovery *)
  let parse_errs = March_parser.Parse_errors.take_parse_errors () in
  let has_parse_errors = parse_errs <> [] in
  List.iter (fun (msg, hint, pos) ->
      let open Lexing in
      Printf.eprintf "%s:%d:%d: error: %s\n"
        filename pos.pos_lnum (pos.pos_cnum - pos.pos_bol) msg;
      (match hint with
       | None -> ()
       | Some h -> Printf.eprintf "hint: %s\n" h)
    ) parse_errs;
  stamp "parse";
  (* Apply .march.spans sidecar remapping if present *)
  let module_ast =
    match March_ast.Span_remap.load_sidecar filename with
    | Some tbl -> March_ast.Span_remap.remap_module tbl module_ast
    | None -> module_ast
  in
  (* Desugar *)
  let desugar_errors = March_errors.Errors.create () in
  let desugared = March_desugar.Desugar.desugar_module ~errors:desugar_errors module_ast in
  List.iter (fun (d : March_errors.Errors.diagnostic) ->
      Printf.eprintf "%s:%d:%d: %s: %s\n"
        d.span.March_ast.Ast.file d.span.March_ast.Ast.start_line
        d.span.March_ast.Ast.start_col (severity_word d.severity) d.message
    ) (March_errors.Errors.sorted desugar_errors);
  let has_desugar_errors = March_errors.Errors.has_errors desugar_errors in
  stamp "desugar";
  (* Capture user AST before stdlib injection — used by -dump-phases *)
  let user_ast = desugared in
  (* Resolve cross-file imports: find imported .march files, parse and inject *)
  let (resolve_errors, extra_decls, user_files) = resolve_imports ~source_file:filename desugared in
  List.iter (fun (_mod_name, span, msg) ->
      Printf.eprintf "%s:%d:%d: error: %s\n"
        span.March_ast.Ast.file span.March_ast.Ast.start_line
        span.March_ast.Ast.start_col msg
    ) resolve_errors;
  let has_resolve_errors = resolve_errors <> [] in
  let desugared =
    { desugared with
      March_ast.Ast.mod_decls = extra_decls @ desugared.March_ast.Ast.mod_decls }
  in
  (* Snapshot of the user's own decls (entry file + resolved imports) BEFORE
     stdlib gets prepended below.  Used to typecheck against the cached
     stdlib env (see [get_stdlib_tc_env]) instead of re-typechecking stdlib
     from scratch on every invocation — [desugared] itself keeps the stdlib
     prepend it always had, since lowering further down still needs stdlib's
     own bodies physically present (see the comment at the prepend site). *)
  let user_only_desugared = desugared in
  stamp "resolve-imports";
  (* Inject stdlib declarations before user declarations.
     If MARCH_LIB_PATH provided a module that also ships in the stdlib, defer
     to the external version: strip the stdlib copy so the external one is
     the sole definition. *)
  let stdlib_decls = load_stdlib ~for_js:is_js_target () in
  let stdlib_decls_unshadowed_count = List.length stdlib_decls in
  let extern_mod_names =
    (* The ENTRY module's own name must shadow a same-named stdlib module
       too: its declarations live at the top level (not as a DMod in
       extra_decls), so without this a project file like lib/crypto.march
       (`mod Crypto`) coexists with the stdlib Crypto DMod and sibling
       modules resolve `Crypto.foo` against the stdlib copy. *)
    desugared.March_ast.Ast.mod_name.March_ast.Ast.txt
    :: List.filter_map (function
      | March_ast.Ast.DMod (nm, _vis, _decls, _sp) ->
        Some nm.March_ast.Ast.txt
      | _ -> None
    ) extra_decls
  in
  let stdlib_decls =
    if extern_mod_names = [] then stdlib_decls
    else List.filter (function
      | March_ast.Ast.DMod (nm, _vis, _decls, _sp) ->
        not (List.mem nm.March_ast.Ast.txt extern_mod_names)
      | _ -> true
    ) stdlib_decls
  in
  (* Mirrors [run_check_cmd]'s [no_shadowing] guard.  A shadowed stdlib copy
     is stripped above so the user's own definition wins, but that leaves a
     HOLE in the stdlib module set: any unshadowed stdlib module that itself
     depends on the shadowed one now resolves against nothing, and whatever
     that produces (missing bindings, spurious errors) gets swallowed by
     [get_stdlib_tc_env]'s cache — which strips its errors before caching
     (see `{ final_env with errors = March_errors.Errors.create () }`) and,
     worse, would otherwise be REUSED across later runs against unrelated
     projects with no shadowing at all, degrading a valid cache into a
     poisoned one. This is not a cache-freshness problem (the content hash
     already busts correctly per shadow set) — it is that the seed-env
     itself is unsound whenever shadowing occurs, cached or not. So: no
     cache read or write in that case, same from-scratch combined check as
     before this optimization existed. *)
  let no_shadowing =
    List.length stdlib_decls = stdlib_decls_unshadowed_count in
  (* [desugared] is also what gets LOWERED further down (TIR needs stdlib's
     own function bodies too, not just their types, to emit a working
     binary) — so unlike [run_check_cmd] (--check only, no lowering), stdlib
     decls must stay physically present here regardless of the seed-env
     typecheck optimization below. An earlier version of this change also
     skipped this prepend when unshadowed, which silently dropped stdlib
     from what gets lowered and broke every compiled program exercising real
     stdlib internals (confirmed via the full test suite: 24 codegen + 6
     stdlib failures, all "type-incorrect TIR reached codegen" ICEs from
     stdlib functions the user's code called into never being lowered). *)
  if not (is_shipped_stdlib_file filename) then
    check_no_prelude_collision ~stdlib_decls desugared;
  let desugared =
    { desugared with
      March_ast.Ast.mod_decls = stdlib_decls @ desugared.March_ast.Ast.mod_decls }
  in
  stamp "stdlib-load";
  (* source_cas_state = early_cas — the CAS lookup already ran before parse.
     On a cache hit we already exited; if we reach this point it's a miss.
     We still pass the (store, ch) pair forward so the post-clang store fires. *)
  let source_cas_state = early_cas in
  (* Typecheck + capability enforcement (applies to both eval and compile paths).
     Capability enforcement is embedded in check_module via check_module_needs:
       - transitive needs propagation across module imports
       - extern block capability gating
     See also March_effects.Effects.check_capabilities — a thin wrapper over the
     same check, used by tests only. This file does NOT call it. *)
  (* Tell the typechecker which files are stdlib BEFORE checking: Check 1b's
     body scan must not attribute prelude's own capability uses to the entry
     module (prelude is unwrapped into global scope, so its decls ride in the
     entry module's list).  See Typecheck.stdlib_source_files. *)
  March_typecheck.Typecheck.stdlib_source_files := stdlib_span_files stdlib_decls;
  (* Run the typecheck-side capability ceiling ONLY in typecheck-only modes
     (`--check`/`--check-json`), where the `--compile` path's TIR-side
     [Cap_ceiling] never runs. On a full `--compile` this stays off so the two
     ceilings do not double-report; the TIR one is the authoritative complete
     check there. Respects `--no-cap-strict` for parity. *)
  March_typecheck.Typecheck.cap_strict_ceiling :=
    !cap_strict && (!do_check || !check_json);
  (* This pipeline runs [Panic_surface_by_proof] below, so the typechecker's
     syntactic ban must leave the contracted names to it.  Set BEFORE
     [check_module_full] — the flag is read during that call.  [run_check_cmd]
     (`march check`/`march caps`) and the LSP deliberately do NOT set it: they
     never run refinecheck, so they keep the old unconditional ban. *)
  March_typecheck.Typecheck.proof_based_panic_surface := true;
  (* Seed pass 1 from the cached stdlib typecheck env instead of
     re-typechecking [stdlib_decls] from scratch every run — stdlib
     typecheck alone is the dominant fixed cost of a `march file.march`
     interpreted start.  Checking [user_only_desugared] (no stdlib decls)
     against that seed is behaviorally identical to combined-checking
     [desugared] for the user's own portion — same [check_module_core] pass
     1/1b/2 machinery either way (see [get_stdlib_tc_env]'s docstring) — and
     the returned [type_map] is the seed's own hashtable with the user
     decls' entries added into it, so it still carries stdlib's span entries
     for the lowering pass below. [desugared] (stdlib-prepended) is
     untouched and still what gets lowered.

     ONLY when [no_shadowing]: see the comment on [no_shadowing] above for
     why a shadowed stdlib module set makes the seed itself unsound, not
     just cache-stale — mirrors [run_check_cmd]'s identical fallback. *)
  let (errors, type_map, typecheck_env) =
    if no_shadowing then
      let seed_env = get_stdlib_tc_env ~for_js:is_js_target stdlib_decls in
      March_typecheck.Typecheck.check_module_full ~seed_env user_only_desugared
    else
      March_typecheck.Typecheck.check_module_full desugared
  in
  (* Phase A1b: discharge refinement-precondition VCs at call sites. *)
  March_refinecheck.Refine_check.check_module ~measure_axioms:!measure_axioms
    ~stdlib_files:(stdlib_span_files stdlib_decls) errors desugared;
  if !refine_report then print_refine_report ~filename ~user_files ();
  (* Division-safety: Z3-backed check for `cap no_panic` modules. *)
  March_refinecheck.Division_safety.check_module errors desugared;
  (* Panic-surface-by-proof: the `cap no_panic` names that carry a real
     refinement contract are admitted when their call site's PRECONDITION was
     actually discharged, rather than banned by name.  It must run here, after
     [Refine_check.check_module] has populated the per-call-site verdict index
     (and after [Division_safety], which only adds to it) — inside the
     typechecker, where the syntactic ban lives, that index does not exist yet.
     NOTE: [run_test_cmd] has its own copy of this pipeline and needs the same
     call; the two are the only places these passes run.

     These two run BEFORE the suggestion printers below, matching
     [run_test_cmd]'s order.  They used to run after, and that was a live
     soundness hole: every suggestion probe refills the per-call-site verdict
     index from a HYPOTHESIS module, so this pass read a speculative
     contract's verdicts as if they were the program's.  `--refine-suggest-all`
     (and `forge refine`, which shells out to `--refine-suggest-json`) flipped
     `cap no_panic` in both directions — an unguarded `List.tail` compiled
     clean, a correctly-guarded one errored.  The probes are also
     non-destructive now ([Obligation.with_scratch]), so this ordering is
     belt-and-braces rather than the only thing holding it up; keep both. *)
  March_refinecheck.Panic_surface_by_proof.check_module errors desugared;
  (* Precondition suggestion.  Must follow the report and the two passes above:
     every hypothesis probe resets the obligation ledger, so anything that reads
     it afterwards would describe the last hypothesis rather than the program. *)
  if !refine_suggest_target <> None || !refine_suggest_all then
    print_refine_suggestions ~filename ~user_files desugared;
  if !refine_suggest_post <> None || !refine_suggest_post_all then
    print_refine_postconditions ~filename ~user_files desugared;
  (* Allocation checker: flag heap-allocating exprs in `cap no_alloc` modules. *)
  March_refinecheck.No_alloc.check_module errors desugared;
  (* Cap-infer: emit hints at call sites missing a `needs` declaration. *)
  March_refinecheck.Cap_infer.check_module errors desugared;
  (* Solving scope ends here: reap the shared z3 child now rather than holding
     an idle solver for the rest of the run (eval servers live indefinitely).
     --check-migration below lazily respawns; its child is reaped by at_exit. *)
  March_refine.Refine.shutdown ();
  stamp "typecheck";
  (* Print diagnostics sorted by position, filtering stdlib-internal errors.
     "User" means any file loaded as user code: the entry file AND modules
     resolved from the source dir / MARCH_LIB_PATH.  Filtering by entry
     filename alone silently compiled ill-typed imported modules. *)
  (* [dedupe_cap_hints]: trims/drops Cap_infer's call-site hint when Check 1b
     already reported the identical missing capability at the identical
     span — see its doc comment above. Applied here, once, so every
     downstream consumer of [diags] (human-readable printing below,
     --check-json, --emit-core-ast) sees the same de-duplicated set. *)
  let diags = dedupe_cap_hints (March_errors.Errors.sorted errors) in
  let is_user_file (d : March_errors.Errors.diagnostic) =
    let f = d.span.March_ast.Ast.file in
    f = filename || f = "" || f = "<unknown>" || List.mem f user_files
  in
  (* Same accept/reject condition --check uses below (has_user_errors ||
     has_parse_errors || has_resolve_errors || has_desugar_errors) — hoisted
     here (rather than left at its original position further down) so
     --emit-core-ast can reuse the identical binding for its "verdict"
     without re-deriving the condition or running the human-readable
     diagnostic-printing loop below (mirrors --check-json's short-circuit,
     which also runs before that loop). *)
  let has_user_errors = List.exists (fun (d : March_errors.Errors.diagnostic) ->
      d.severity = March_errors.Errors.Error && is_user_file d
    ) diags in
  if !check_json then begin
    List.iter (fun (d : March_errors.Errors.diagnostic) ->
      if is_user_file d then
        print_string (March_errors.Errors.render_diagnostic_json d ^ "\n")
    ) diags;
    exit 0
  end;
  if !emit_core_ast_file <> None then
    Emit_core_ast.run ~filename ~user_files ~user_ast ~type_map ~diags
      ~is_user_file ~typecheck_env
      ~rejected:(has_user_errors || has_parse_errors || has_resolve_errors
                 || has_desugar_errors);
  List.iter (fun (d : March_errors.Errors.diagnostic) ->
      if is_user_file d then begin
        (* Render against the file the span points into — imported-module
           errors must not be shown with the entry file's source lines. *)
        let f = d.span.March_ast.Ast.file in
        let (d_src, d_file) =
          if f = filename || f = "" || f = "<unknown>" then (src, filename)
          else (try read_file f with Sys_error _ -> src), f
        in
        Printf.eprintf "%s\n\n\n"
          (March_errors.Errors.render_diagnostic ~src:d_src ~filename:d_file d)
      end
    ) diags;
  let compile_mode = !dump_tir || !emit_llvm || !do_compile || !dump_phases in
  (* --jit: replace the tree-walking interpreter with the in-process ORC JIT
     for this run.  Every diagnostic above has already been produced and
     printed exactly as in interpreted mode — this flag only swaps the
     execution engine underneath, never the checking.

     Actor programs fall back to the interpreter with a notice, mirroring the
     REPL's own [actors_declared] guard: actor lowering emits dispatch tables
     the incremental fragment path does not yet set up.  The check walks
     nested modules too, and looks at [user_only_desugared] so a stdlib actor
     could never trigger it.  Suppressed on an error/compile/check run so the
     notice can't appear on a program that is about to exit 1 anyway. *)
  let jit_run =
    !jit_mode
    && not compile_mode && not !do_check && not !check_migration
    && not (has_user_errors || has_parse_errors || has_resolve_errors
            || has_desugar_errors)
    (* The time-travel debugger (--debug / --debug-tui) only exists in the
       tree-walking interpreter: [March_debug.Debug.install] hooks the eval
       loop below, and the JIT has no equivalent hook.  Route back to the
       interpreter with a notice, same pattern as the shadowing/actor arms
       below, rather than silently dropping the user's explicit --debug
       request.  Checked first so it takes precedence over those arms. *)
    && (if not (!debug_mode || !debug_tui_mode) then true
        else begin
          Printf.eprintf
            "march: --jit does not support the debugger; running interpreted\n%!";
          false
        end)
    (* A program that shadows a stdlib module must NOT be JIT'd.  The --jit arm
       feeds [get_stdlib_tc_env]'s seed env into [run_program]'s typecheck, and
       [no_shadowing] is exactly the condition under which that seed env is
       sound (see its definition above: when a user module shadows a stdlib
       one, the seed is unsound whether cached or not, which is why the
       typecheck above falls back to a from-scratch combined check).  Here the
       consequence would be worse than wrong diagnostics: run_program's
       type_map feeds LOWERING. *)
    && (if no_shadowing then true
        else begin
          Printf.eprintf
            "march: --jit does not support stdlib-shadowing programs yet; running interpreted\n%!";
          false
        end)
    && (let rec has_actor (ds : March_ast.Ast.decl list) =
          List.exists (function
            | March_ast.Ast.DActor _ -> true
            | March_ast.Ast.DMod (_, _, inner, _) -> has_actor inner
            | _ -> false) ds
        in
        if has_actor user_only_desugared.March_ast.Ast.mod_decls then begin
          Printf.eprintf
            "march: --jit does not support actor programs yet; running interpreted\n%!";
          false
        end else true)
  in
  (* In compile mode, abort on user-file errors only.  Stdlib errors
     (e.g. http_client) are tolerated since those modules are WIP. *)
  if has_user_errors || has_parse_errors || has_resolve_errors || has_desugar_errors then exit 1
  (* --check: stop after typecheck.  Diagnostics above already printed; we just
     exit 0 so tooling (forge build / forge check) can treat a clean typecheck
     as a pass.  Warnings do not fail the exit code — consistent with eval and
     compile modes. *)
  else if !do_check then begin
    (* Cache successful check result so the next identical-source invocation
       exits immediately without re-running the typecheck pipeline (the early
       CAS hit at the top of this function does `exit 0` printing nothing).

       DETERMINISM: only cache when this run printed NO user-facing diagnostics.
       A cache hit short-circuits BEFORE the diagnostic-printing pass, so if we
       cached a run that emitted warnings/hints, the next identical --check would
       exit silently and those diagnostics would vanish — making --check output
       nondeterministic (shown on the caching run, absent on cached runs, and
       reappearing whenever the shared project-root CAS store is cleared). By
       caching only diagnostic-free runs, a hit provably corresponds to "clean,
       nothing to print", so the silent exit is byte-identical to a fresh run.
       Files that do emit warnings/hints are simply re-checked each time and
       print the same diagnostics every run. This does not change WHICH
       diagnostics are emitted — only whether the cache may suppress them. *)
    let printed_user_diag =
      List.exists is_user_file diags
    in
    (match source_cas_state with
     | Some (src_store, src_ch) when not printed_user_diag ->
       March_cas.Cas.store_artifact src_store src_ch filename
     | Some _ | None -> ());
    exit 0
  end
  else if !check_migration then Schema_migration.run ~src ~desugared
  else if compile_mode then begin
   try
    (* -dump-phases: collect per-stage JSON graphs *)
    let phases = ref [] in
    (* MARCH_DUMP_TXT=<substring> prints the pretty-printed TIR at every
       snap_tir checkpoint whose label contains the substring (`all` matches
       every stage).  --dump-tir only shows the very end of the pipeline, which
       is too late to tell whether a pass CREATED a construct or merely
       preserved one; this makes the intermediate stages readable without
       going through the --dump-phases JSON. *)
    let dump_txt = Sys.getenv_opt "MARCH_DUMP_TXT" in
    let snap_tir label tir =
      if !dump_phases then
        phases := March_dump.Dump.tir_phase tir label :: !phases;
      match dump_txt with
      | Some pat when pat = "all" || contains_substring label pat ->
        Printf.eprintf "===== %s =====\n" label;
        List.iter (fun fn ->
          Printf.eprintf "%s\n\n" (March_tir.Pp.string_of_fn_def fn))
          tir.March_tir.Tir.tm_fns
      | _ -> ()
    in
    (* Phase 1: AST after parse+desugar — user file only (no stdlib). *)
    (if !dump_phases then
       phases := March_dump.Dump.ast_phase user_ast "parse" :: !phases);
    let tir = March_tir.Lower.lower_module ~type_map ~test_mode:!do_test ~hot_reload:(Option.is_some !hot_reload_prefix) desugared in
    (* @[vectorize]/@[vectorize(warn)]: this is the one point in the
       pipeline where a TIR fn's name is still exactly its source name —
       Mono hasn't mangled/duplicated anything yet, Defun hasn't lifted
       any lambdas yet — so AST attrs can be matched to TIR functions by
       plain name equality. Installs a sentinel call (see
       Vectorize_mark's doc comment) that survives everything between
       here and Vectorize_check.check far below, including inlining.
       Native/wasm compile only — no sentinel should reach Js_emit.ml, which
       has no codegen arm for the synthetic call this pass introduces. *)
    let tir = if is_js_target then tir else March_tir.Vectorize_mark.mark desugared tir in
    (* Inject IO-module names from the typecheck env so the policy audit can
       identify calls that require Cap(IO) at the TIR level. *)
    let io_modules =
      List.filter_map (fun (mod_name, caps) ->
        if List.exists (fun c ->
          c = "IO" ||
          (String.length c > 3 && String.sub c 0 3 = "IO.")
        ) caps
        then Some mod_name
        else None
      ) typecheck_env.March_typecheck.Typecheck.module_caps
    in
    let tir = { tir with March_tir.Tir.tm_io_fns = io_modules } in
    snap_tir "tir-lower" tir;
    stamp "lower";
    (* TRMC eligibility analysis (Phase 1 — analysis only, gated on
       MARCH_TRMC_REPORT).  Must run here: by tir-perceus the stdlib's nested
       `go` helpers are closures invoked via ECallPtr, so self-recursion is no
       longer syntactically visible.  See
       specs/todos/2026-08-07-trmc-tail-recursion-modulo-cons.md. *)
    March_tir.Trmc.report tir;
    (* Phase 3 (WIP, gated on --trmc / legacy MARCH_TRMC): destination-passing rewrite of
       TRMC-eligible functions.  Off by default — this is a measurement
       vehicle until the RC integration (phase 4) is done. *)
    let tir = March_tir.Trmc.transform_module tir in
    (* Phase 5: collect actor state schemas for .schemas.json emission.
       Picks up TDRecord entries named *_State — the state record emitted
       by lower_actor for every actor definition. Only collected when both
       --hot-reload and --compile-so are active. *)
    let rec ty_to_schema_str = function
      | March_tir.Tir.TInt    -> "Int"
      | March_tir.Tir.TBool   -> "Bool"
      | March_tir.Tir.TFloat  -> "Float"
      | March_tir.Tir.TString -> "String"
      | March_tir.Tir.TUnit   -> "Unit"
      | March_tir.Tir.TCon (n, []) -> n
      | March_tir.Tir.TCon (n, args) ->
        n ^ "(" ^ String.concat "," (List.map ty_to_schema_str args) ^ ")"
      | March_tir.Tir.TTuple ts ->
        "(" ^ String.concat "," (List.map ty_to_schema_str ts) ^ ")"
      | other -> March_tir.Tir.show_ty other
    in
    (* Build actor_name → @compat policy map from the desugared AST.
       Walks all module-level and nested DActor declarations. *)
    let rec collect_actor_compat acc (decls : March_ast.Ast.decl list) =
      List.fold_left (fun acc d ->
          match d with
          | March_ast.Ast.DActor (_, name, adef, _) ->
            (name.March_ast.Ast.txt, adef.March_ast.Ast.actor_compat) :: acc
          | March_ast.Ast.DMod (_, _, inner, _) ->
            collect_actor_compat acc inner
          | _ -> acc
        ) acc decls
    in
    let actor_compat_map : (string * string) list =
      collect_actor_compat [] desugared.March_ast.Ast.mod_decls in
    let rec collect_actor_invariant acc (decls : March_ast.Ast.decl list) =
      List.fold_left (fun acc d ->
          match d with
          | March_ast.Ast.DActor (_, name, adef, _) ->
            (match adef.March_ast.Ast.actor_invariant with
             | None -> acc
             | Some e -> (name.March_ast.Ast.txt, e) :: acc)
          | March_ast.Ast.DMod (_, _, inner, _) ->
            collect_actor_invariant acc inner
          | _ -> acc
        ) acc decls
    in
    let actor_invariant_map : (string * March_ast.Ast.expr) list =
      collect_actor_invariant [] desugared.March_ast.Ast.mod_decls in
    let actor_schemas : (string * (string * March_tir.Tir.ty) list) list =
      if Option.is_some !hot_reload_prefix && !compile_so then
        List.filter_map (fun td ->
            match td with
            | March_tir.Tir.TDRecord (tname, fields)
              when let n = String.length tname in
                   n > 6 && String.sub tname (n - 6) 6 = "_State" ->
                let actor_name = String.sub tname 0 (String.length tname - 6) in
                let user_fields = List.filter (fun (nm, _) ->
                    nm = "" || nm.[0] <> '$') fields in
                Some (actor_name, user_fields)
            | _ -> None
          ) tir.March_tir.Tir.tm_types
      else []
    in
    (* Capture the interface-dispatch table before it is cleared by lower_module.
       Passed to monomorphize so it can resolve interface calls in functions
       that were polymorphic during lowering but now have concrete types. *)
    let iface_methods = March_tir.Lower.get_iface_methods () in
    (* For WASM island targets, mark render/update/init as exported.
       Set exports BEFORE monomorphization so the functions get mono'd. *)
    let tir = match parse_target !target_str with
      | March_tir.Llvm_emit.Wasm32Unknown ->
        let island_suffixes = ["render"; "update"; "init"] in
        let exports = List.filter_map (fun (fn : March_tir.Tir.fn_def) ->
          let n = fn.March_tir.Tir.fn_name in
          if List.exists (fun suffix ->
            n = suffix ||
            (String.length n > String.length suffix + 1 &&
             String.sub n (String.length n - String.length suffix - 1)
               (String.length suffix + 1) = ("." ^ suffix))
          ) island_suffixes
          then Some n else None
        ) tir.March_tir.Tir.tm_fns in
        { tir with March_tir.Tir.tm_exports = exports }
      | _ -> tir
    in
    let tir = March_tir.Mono.monomorphize ~iface_methods tir in
    snap_tir "tir-mono" tir;
    stamp "mono";
    (* After mono, update tm_exports to use monomorphized names *)
    let tir =
      if tir.March_tir.Tir.tm_exports <> [] then begin
        let island_suffixes = ["render"; "update"; "init"] in
        let matches_suffix name suffix =
          let base = match String.index_opt name '$' with
            | Some i -> String.sub name 0 i
            | None -> name
          in
          base = suffix ||
          (String.length base > String.length suffix + 1 &&
           String.sub base (String.length base - String.length suffix - 1)
             (String.length suffix + 1) = ("." ^ suffix))
        in
        let exports = List.filter_map (fun (fn : March_tir.Tir.fn_def) ->
          let n = fn.March_tir.Tir.fn_name in
          if List.exists (matches_suffix n) island_suffixes
          then Some n else None
        ) tir.March_tir.Tir.tm_fns in
        { tir with March_tir.Tir.tm_exports = exports }
      end else tir
    in
    (* Pin __rpc_stub functions so the DCE pass keeps them (and their callees)
       alive.  Without this, private stubs never called from March code are
       dropped before the CAS hash and LLVM emit steps can see them. *)
    let tir =
      let stub_suffix = "__rpc_stub" in
      let slen = String.length stub_suffix in
      let stubs = List.filter_map (fun (fn : March_tir.Tir.fn_def) ->
        let n = fn.March_tir.Tir.fn_name in
        let nl = String.length n in
        if nl > slen && String.sub n (nl - slen) slen = stub_suffix
        then Some n else None
      ) tir.March_tir.Tir.tm_fns in
      if stubs = [] then tir
      else { tir with March_tir.Tir.tm_exports =
               tir.March_tir.Tir.tm_exports @ stubs }
    in
    let tir = if !opt_enabled then March_tir.Fusion.run ~changed:(ref false) tir else tir in
    snap_tir "tir-fusion" tir;
    stamp "fusion";
    (* Phase 3b: policy-tag audit — report violations in Tagged(_, P) functions. *)
    let policy_violations = March_tir.Policy_dce.audit tir in
    List.iter (fun (_fn_name, msg) ->
      Printf.eprintf "Error: %s\n\n" msg
    ) policy_violations;
    if policy_violations <> [] then exit 1;
    let tir = March_tir.Defun.defunctionalize tir in
    snap_tir "tir-defun" tir;
    stamp "defun";
    (* Known-call pass: run before Perceus so apply functions are still pure
       and eligible for inlining in the subsequent Opt fixed-point loop.
       Also included in the Opt coordinator for cases revealed after Perceus.
       This rewrites ECallPtr(clo, args) -> EApp(clo_apply, clo :: args).  The
       closure-apply ABI consumes the closure argument, so Perceus must NOT
       emit a caller-side post-call EDecRC for the $clo slot of an apply
       function even when borrow inference classifies it as borrowed — see the
       [is_apply_fn] guard in [Perceus]'s EApp post_dec_vars.  Without that
       guard the rewrite double-freed the closure (List.sort_by SIGBUS at
       n >= ~90 with a heap-capturing comparator). *)
    let tir = if !opt_enabled
              then March_tir.Known_call.run ~changed:(ref false) tir
              else tir in
    snap_tir "tir-known-call" tir;
    (* Beta-ADT: reduce case-of-known-constructor before Perceus so that the
       EAlloc is DCE'd before RC insertion, avoiding a spurious allocation and
       its associated reference-count operations entirely. *)
    let tir = if !opt_enabled
              then March_tir.Beta_adt.run ~changed:(ref false) tir
              else tir in
    snap_tir "tir-beta-adt-pre" tir;
    (* P1 Layer 1: alpha-merge let-floating on RC-free TIR.  Hoists common
       leading lets above ECase even when arms bind the shared RHS under
       different fresh ANF names, substituting onto one floated binder.  Must
       run BEFORE Perceus so RC is inserted once for the hoisted binding.  The
       conservative (name-equality) variant still runs in the post-Perceus opt
       loop. *)
    let tir = if !opt_enabled
              then March_tir.Join_points.run_pre ~changed:(ref false) tir
              else tir in
    snap_tir "tir-join-points-pre" tir;
    (* Pre-Perceus simplify: folds that are only sound before RC insertion,
       currently the empty-string concat identities (x ++ "" → x, "" ++ x → x).
       Folding here aliases the result to `x` while it is still un-RC-tracked, so
       Perceus inserts a single correct dec_rc afterwards.  The post-Perceus Opt
       loop runs Simplify with pre_perceus=false and never applies these. *)
    let tir = if !opt_enabled
              then March_tir.Simplify.run ~pre_perceus:true ~changed:(ref false) tir
              else tir in
    snap_tir "tir-simplify-pre" tir;
    let tir = March_tir.Perceus.perceus tir in
    snap_tir "tir-perceus" tir;
    stamp "perceus";
    (* Deep-drop synthesis: route Perceus's bare EDecRC on a heap-owning
       aggregate through a generated destructuring drop, so releasing a
       container that was never pattern-matched also releases its children
       (see lib/tir/drop.ml).  Skipped for the JS target, whose runtime is
       GC'd and ignores RC ops entirely — there the generated drop would be a
       pure-overhead walk of every dropped structure. *)
    let tir =
      if parse_target !target_str = March_tir.Llvm_emit.Js then tir
      else March_tir.Drop.run tir in
    snap_tir "tir-drop" tir;
    stamp "drop";
    let tir = March_tir.Escape.escape_analysis tir in
    snap_tir "tir-escape" tir;
    stamp "escape";
    (* Run optimizer with per-pass snapshots (Phase 3 instrumentation).
       When dump_phases is on, each individual opt pass is captured separately
       (tir-opt-1-inline, tir-opt-1-cprop, …) so the viewer shows every step.
       When opt is disabled, fall through to a single tir-opt snapshot. *)
    (* Save pre-opt TIR so we can hash __rpc_stub base functions that the
       inliner may eliminate before the CAS hash step below. *)
    let pre_opt_tir = tir in
    (* Per-module capability attribution MUST be taken here, before the
       inliner runs: it folds a dependency's small function into its caller
       and the module boundary is gone by emission time, so attributing then
       would credit the dependency's IO to the application.  Pruned first so
       a dependency feature nothing calls contributes no owner row — that is
       what makes "use one function of a library" cost only that function's
       capabilities.  Both passes are pure, so this observes the pipeline
       without perturbing it. *)
    let cap_attrib =
      let stdlib_mods = stdlib_module_names stdlib_decls in
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
      let stem n =
        let n =
          match String.rindex_opt n '.' with
          | Some i -> String.sub n (i + 1) (String.length n - i - 1)
          | None -> n
        in
        match String.index_opt n '$' with
        | Some i -> String.sub n 0 i
        | None -> n
      in
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
        ~transparent:(fun m -> List.mem m stdlib_mods)
        ~transparent_fns:(fun n ->
          (* Bare names only: a dotted name belongs to a module and is judged
             by the module predicate.  Matching the stem of a dotted name here
             would make a user function that merely SHARES a prelude name
             (`MyMod.println`) see-through. *)
          not (String.contains n '.') && Hashtbl.mem prelude_fns (stem n))
        (March_tir.Dce.prune_unreachable
           ~extra_root:(fun n -> Hashtbl.mem user_fns (stem n))
           ~fail_open:false pre_opt_tir)
    in
    (* --cap-strict: `needs` as a hard ceiling.  Deliberately checked here,
       against attributed use, rather than by a fifth source-level AST walk.
       The four existing walks in Typecheck do NOT cover the same routes —
       measured, a stdlib-mediated `File.write` produced no diagnostic at all,
       because Check 4 walks `DUse` declarations and stdlib modules are
       ambiently available without one.  Emitted code collapses all routes
       into one rule and cannot be evaded by re-routing through a helper.

       Runs BEFORE the CAS artifact lookup below, so a warm cache cannot
       skip it; "capstrict" is also in cas_flags so a strict build never
       reuses an artifact produced without the check. *)
    (* Per-module declared needs, in the same (cap, owner) shape as
       attribution.  Used both by --cap-strict below and, emitted into the
       artifact, by `forge cap inspect --strict` on a binary it did not
       build.  The entry module is unwrapped by desugar (~is_entry:true) so
       it has no DMod and never lands in [module_caps]; its needs accumulate
       in [mod_needs].  Attribution names it by [tm_name], so bind the two
       together or every entry-module capability reads as undeclared. *)
    let cap_module_caps =
      (pre_opt_tir.March_tir.Tir.tm_name,
       typecheck_env.March_typecheck.Typecheck.mod_needs)
      :: typecheck_env.March_typecheck.Typecheck.module_caps
    in
    let cap_decls =
      List.concat_map
        (fun (m, needs) -> List.map (fun c -> (c, m)) needs)
        cap_module_caps
      |> List.sort_uniq compare
    in
    if !cap_strict then begin
      (* The ceiling's used-set is the ATTRIBUTED set — capabilities of the
         emitted code — and deliberately NOT unioned with
         [own_caps_of_this_module] any more (changed 2026-08-08, with the
         default flip).

         The typecheck-side set counts a capability that appears only in a
         SIGNATURE (`fn main(cap : Cap(IO))`, `fn demo(c : Cap(IO.Console))`)
         as "used".  Capabilities are erased, so a signature-only capability
         corresponds to no emitted operation at all; feeding it to the
         ceiling produced an Unattributed violation nobody could fix — and
         `main(cap : Cap(IO))` is the DOCUMENTED entry-point shape (R2), so
         with the ceiling on by default that false positive rejected the
         sanctioned way to write `main`.

         What the union genuinely bought was a DRIFT DETECTOR between the two
         capability tables: when attribution's builtin lookup missed ten
         trampoline-lowered builtins (2026-08-07), it was exactly this diff
         that surfaced as "cannot be attributed".  That role is now carried
         by test_cap_attrib_agreement, which pins the two tables to each
         other directly instead of surfacing their drift as a user-facing
         false positive.

         [own_caps_of_this_module] itself is unchanged and still feeds
         --cap-sandbox, where the SIGNATURE reading is the right one: a
         module that receives a capability by parameter may exercise it, so
         the sandbox profile must allow it. *)
      let flat_caps =
        List.sort_uniq compare (List.map fst cap_attrib)
      in
      (* The entry module is unwrapped by desugar (~is_entry:true), so it has
         no DMod and never lands in [module_caps]; its `needs` accumulate in
         [mod_needs] instead. Attribution names it by [tm_name], so bind the
         two together or every entry-module capability reads as undeclared —
         which is what the first run of this check did to a module that had
         correctly declared its need. *)
      let module_caps =
        (pre_opt_tir.March_tir.Tir.tm_name,
         typecheck_env.March_typecheck.Typecheck.mod_needs)
        :: typecheck_env.March_typecheck.Typecheck.module_caps
      in
      let (module_spans, module_is_header) = cap_ceiling_module_spans
          ~entry_owner:pre_opt_tir.March_tir.Tir.tm_name
          ~entry_span:desugared.March_ast.Ast.mod_name.March_ast.Ast.span
          desugared.March_ast.Ast.mod_decls
      in
      let violations =
        March_caps.Cap_ceiling.check ~module_caps ~module_spans
          ~attribution:cap_attrib ~caps:flat_caps
      in
      if violations <> [] then begin
        (* Undeclared violations carry a span and a name to their own owning
           module (from [module_spans] above), so they render through the
           SAME diagnostic pipeline as every other capability error — with
           a real span, a source excerpt, and a machine-applicable [FInsert]
           fix — rather than the bespoke, file-less
           "-- CAPABILITY CEILING --" block this replaces (see the same
           [vectorize_diags] pattern just below for the render precedent: a
           fresh [Err.ctx], not the shared typecheck [errors], since this
           runs after that context has already been drained and printed).

           This does NOT yet make the violation visible to the LSP or
           applicable by `forge fix` — this only runs on the [--compile]
           path, which `--check`/`--check-json` (forge fix's only input,
           see [run_check_cmd]) never reaches. The fix payload is real and
           ready; it has no consumer until the ceiling also runs under
           [--check] (tracked in
           specs/todos/2026-08-14-cap-ceiling-under-check-needs-body-only-closure.md).

           [Unattributed] violations name no module and therefore have no
           span to point at — the ceiling's own [.mli] documents why this
           is a fail-closed case rather than a false-positive risk to guard
           against here — so those stay on the original bespoke line. *)
        let ctx = March_errors.Errors.create () in
        List.iter
          (fun v ->
             match v with
             | March_caps.Cap_ceiling.Undeclared { cap = _; owner = _; span }
               when span = March_ast.Ast.dummy_span ->
               (* No real span was found ANYWHERE for this violation's
                  owning module — every inner declaration was itself
                  span-less. Rendering through the normal diagnostic
                  pipeline with [dummy_span]'s file ("<none>") would raise
                  [Sys_error] on read, silently fall back to the ENTRY
                  file's source, and print line 0 of the WRONG file. Fail
                  back to the bespoke, file-less rendering instead — never
                  a crash, never a diagnostic pointing at unrelated code. *)
               Printf.eprintf "-- CAPABILITY CEILING --\n%s\n\n"
                 (March_caps.Cap_ceiling.describe v)
             | March_caps.Cap_ceiling.Undeclared { cap; owner; span } ->
               let is_header =
                 match List.assoc_opt owner module_is_header with
                 | Some h -> h | None -> true
               in
               let indent =
                 cap_ceiling_fix_indent ~src ~filename ~read_file ~is_header span
               in
               March_errors.Errors.error_with_fix ctx ~span
                 ~code:("cap_ceiling:" ^ cap)
                 ~fix:(March_errors.Errors.FInsert {
                   after_line = span.March_ast.Ast.start_line;
                   text = String.make indent ' ' ^ "needs " ^ cap })
                 (Printf.sprintf
                    "module `%s` uses `%s` but does not declare `needs %s`.\n\
                     help: add `needs %s` to the module body."
                    owner cap cap cap)
             | March_caps.Cap_ceiling.Unattributed _ ->
               Printf.eprintf "-- CAPABILITY CEILING --\n%s\n\n"
                 (March_caps.Cap_ceiling.describe v))
          violations;
        List.iter (fun (d : March_errors.Errors.diagnostic) ->
            let f = d.span.March_ast.Ast.file in
            let (d_src, d_file) =
              if f = filename || f = "" || f = "<unknown>" then (src, filename)
              else (try read_file f with Sys_error _ -> src), f
            in
            Printf.eprintf "%s\n\n\n"
              (March_errors.Errors.render_diagnostic ~src:d_src ~filename:d_file d)
          ) (March_errors.Errors.sorted ctx);
        Printf.eprintf
          "%d capability ceiling violation(s). Every module's emitted code \
           must stay within its own `needs`.\n\
           Add the missing `needs` line to the module named above, or pass \
           `--no-cap-strict` to build without this check.\n%!"
          (List.length violations);
        exit 1
      end
    end;
    let tir =
      if !opt_enabled then
        March_tir.Opt.run
          ~snap:(fun label m ->
            if !dump_phases then
              phases := March_dump.Dump.tir_phase m label :: !phases)
          ~hot_reload:(hr_config ())
          tir
      else tir
    in
    (* Prune functions unreachable from the entry points BEFORE LLVM emit, even
       when the optimizer is disabled.  Reachability pruning is a linkability
       requirement (not an optimization): the injected prelude/http stack
       references not-always-linked externs like [_http_fetch], so an
       unreachable prelude function reaching the linker produces "undefined
       symbols".  When opt IS enabled the DCE pass already pruned inside
       Opt.run, so this is an idempotent no-op there. *)
    let tir = March_tir.Dce.prune_unreachable tir in
    (* @[vectorize]/@[vectorize(warn)]: verify NativeArray.map/map2
       eligibility against the SAME pre-rewrite TIR shape
       Native_map_inline.run (right below) is about to consume — a
       DIFFERENT ctx than the shared typecheck [errors], printed and
       gated on its own, so already-printed earlier diagnostics in
       [errors] are never re-emitted here. [check]'s return value MUST be
       used going forward (not the original [tir]) — it has every
       Vectorize_mark sentinel stripped back out, and nothing past this
       point may see one (there is no @__vectorize_marker_* symbol to
       link against). *)
    let (tir, vectorize_diags) =
      if is_js_target then (tir, [])
      else
        let ctx = March_errors.Errors.create () in
        let tir' = March_tir.Vectorize_check.check ctx tir in
        (tir', March_errors.Errors.sorted ctx)
    in
    List.iter (fun (d : March_errors.Errors.diagnostic) ->
        let f = d.span.March_ast.Ast.file in
        let (d_src, d_file) =
          if f = filename || f = "" || f = "<unknown>" then (src, filename)
          else (try read_file f with Sys_error _ -> src), f
        in
        Printf.eprintf "%s\n\n\n"
          (March_errors.Errors.render_diagnostic ~src:d_src ~filename:d_file d)
      ) vectorize_diags;
    if List.exists (fun (d : March_errors.Errors.diagnostic) ->
        d.severity = March_errors.Errors.Error) vectorize_diags
    then exit 1;
    (* P10 Phase 2: inline non-capturing NativeArray.map closures so
       llvm_emit.ml can emit a direct-call loop instead of going through the
       C runtime's opaque closure-pointer indirection (never inlinable across
       that translation-unit boundary, so never vectorizable). Runs after Opt
       (not right after Defun) because the pattern it looks for only appears
       once Inline has flattened the NativeArray.map_int/map_float stdlib
       wrapper into its call site — at Defun time the closure allocation and
       the native_int_arr_map/native_float_arr_map call are still in two
       different function bodies. Native/wasm compile only (guarded on
       is_js_target) — Js_emit.ml has no codegen arm for the synthetic call
       this pass introduces, since this shared pipeline reaches the JS
       backend too (target dispatch happens later, at the emit stage below).
       Its single-use-of-the-closure-var check is also what makes running
       this late safe: if Perceus (which ran before Opt) left any RC op
       referencing the closure var, that counts as an extra use and the
       pass silently declines, falling back to the existing correct path. *)
    let tir = if is_js_target then tir else March_tir.Native_map_inline.run tir in
    snap_tir "tir-native-map-inline" tir;
    (* When opt is disabled there are no per-pass snaps; still emit one overall. *)
    if not !opt_enabled then snap_tir "tir-opt" tir;
    stamp "opt";
    (* RPC admission hashes (remote_ref_hashes constant-folding + the @main
       march_remote_register calls) must be IDENTICAL across SEPARATE client and
       server compilations of the same source.  Derive them uniformly from the
       PRE-opt TIR via hash_fn_def for ALL functions — never from the post-opt
       SCC hashes, which only a live (server-side) function receives while a
       caller-side function is usually dead-code-eliminated, so the two binaries
       would disagree.  Combined with alpha-normalized serialization this makes
       each hash a pure function of the function's normalized body + its callees'
       stable names, so a non-trivial body (one that calls stdlib functions)
       matches across binaries just like a trivial leaf does. *)
    let rpc_impl_hashes : (string, string) Hashtbl.t = Hashtbl.create 16 in
    let rpc_sig_hashes  : (string, string) Hashtbl.t = Hashtbl.create 16 in
    List.iter (fun (fn : March_tir.Tir.fn_def) ->
      let h = March_cas.Hash.hash_fn_def fn in
      Hashtbl.replace rpc_impl_hashes fn.March_tir.Tir.fn_name h.March_cas.Hash.impl_hash;
      Hashtbl.replace rpc_sig_hashes  fn.March_tir.Tir.fn_name h.March_cas.Hash.sig_hash
    ) pre_opt_tir.March_tir.Tir.tm_fns;
    (* Write all collected phases to march-phases/phases.json *)
    (if !dump_phases then
       March_dump.Dump.write_phases ~source_file:filename (List.rev !phases));
    if !dump_tir then begin
      List.iter (fun td ->
          Printf.printf "%s\n\n" (March_tir.Pp.string_of_type_def td)
        ) tir.tm_types;
      List.iter (fun fn ->
          Printf.printf "%s\n\n" (March_tir.Pp.string_of_fn_def fn)
        ) tir.tm_fns
    end else begin
      let target = parse_target !target_str in
      let basename = Filename.remove_extension filename in
      let ll_file  = basename ^ ".ll" in
      if !do_compile then begin
        let is_wasm = March_tir.Llvm_emit.is_wasm_target target in
        let out_bin =
          if !output_file <> "" then !output_file
          else if is_wasm then basename ^ ".wasm"
          else if target = March_tir.Llvm_emit.Js then basename ^ ".mjs"
          else basename
        in
        (* JS target: skip LLVM/clang entirely *)
        if target = March_tir.Llvm_emit.Js then begin
          let tir_for_js = if !opt_enabled then March_tir.Opt.run tir else tir in
          (* Collect source lines from user AST for source map generation.
             user_ast = desugared before stdlib injection, so only user functions. *)
          let rec collect_fn_lines prefix = function
            | [] -> []
            | March_ast.Ast.DFn (def, _) :: rest ->
              let name = prefix ^ def.fn_name.txt in
              let line = def.fn_name.span.start_line in
              (name, line) :: collect_fn_lines prefix rest
            | March_ast.Ast.DMod (nm, _, sub, _) :: rest ->
              collect_fn_lines (prefix ^ nm.txt ^ ".") sub
              @ collect_fn_lines prefix rest
            | _ :: rest -> collect_fn_lines prefix rest
          in
          let fn_lines =
            collect_fn_lines "" user_ast.March_ast.Ast.mod_decls
          in
          let (js, map_opt) =
            (try March_tir.Js_emit.emit_module ~source_file:filename ~fn_lines tir_for_js
             with March_tir.Js_emit.Js_emit_error msgs ->
               List.iter (fun msg -> Printf.eprintf "%s\n" msg) msgs;
               exit 1)
          in
          (* Write source map if available, and append sourceMappingURL to JS *)
          let map_name = Filename.basename out_bin ^ ".map" in
          let js = match map_opt with
            | None -> js
            | Some map_json ->
              let map_path = Filename.concat (Filename.dirname out_bin) map_name in
              (try
                let oc2 = open_out map_path in
                output_string oc2 map_json;
                close_out oc2
               with Sys_error _ -> ());
              js ^ "//# sourceMappingURL=" ^ map_name ^ "\n"
          in
          let oc = open_out out_bin in
          output_string oc js;
          close_out oc;
          (* Copy runtime .mjs files alongside the output so imports work,
             unless --no-copy-runtime is given (e.g. when dune manages them) *)
          if not !no_copy_runtime then begin
            let out_dir = Filename.dirname out_bin in
            let copy_runtime name =
              let dest = Filename.concat out_dir name in
              match find_runtime_file name with
              | Some src ->
                let ic = open_in src in
                let content = really_input_string ic (in_channel_length ic) in
                close_in ic;
                let oc2 = open_out dest in
                output_string oc2 content;
                close_out oc2
              | None -> Printf.eprintf "march: warning: cannot find %s\n" name
            in
            copy_runtime "march_runtime.mjs";
            copy_runtime "march_dom.mjs"
          end;
          Printf.eprintf "compiled %s\n" out_bin
        end else begin
        (* CAS: check for a cached binary before running clang *)
        let target_label = cas_target_label target in
        let store = March_cas.Cas.create ~project_root:(Sys.getcwd ()) in
        let h_sccs = March_cas.Pipeline.hash_module tir in
        let mod_hash = String.concat "" (List.map March_cas.Pipeline.scc_impl_hash h_sccs) in
        (* Hot Code Reload: per-function impl_hash map (qualified fn name →
           64-char hex Merkle root) so the baseline dispatch-table publish can
           carry real hashes instead of null. Built from the same CAS hashing
           that keys the artifact cache; only consulted when --hot-reload is on. *)
        let hr_impl_hashes : (string, string) Hashtbl.t = Hashtbl.create 16 in
        (* L4 remote registry: sig_hash map for remote_ref_hashes constant folding. *)
        let remote_sig_hashes : (string, string) Hashtbl.t = Hashtbl.create 16 in
        (* HCR reload-identity hash is NON-TRANSITIVE, unlike the CAS key.
           hd.hd_impl_hash is the transitive Merkle root (folds in callees' and
           types' hashes) used to key the compilation cache — correct for
           incremental builds.  But it is WRONG as a hot-reload slot identity:
           changing one leaf function changes the transitive hash of every
           caller up to `main`, so a leaf-only hot deploy would flag (and try to
           swap) the whole caller chain, including the running entry point.
           For the reloadable-slot baseline we instead publish the per-function
           hash (sig+body only, via Hash.hash_fn_def) so a leaf change touches
           only that leaf's slot.  This matches the fallback passes below, which
           already hash leftover functions non-transitively. *)
        let add_hdef (hd : March_cas.Cas.hashed_def) =
          match hd.March_cas.Cas.hd_def with
          | March_cas.Cas.FnDef fd ->
            let h = March_cas.Hash.hash_fn_def fd in
            Hashtbl.replace hr_impl_hashes fd.March_tir.Tir.fn_name
              h.March_cas.Hash.impl_hash;
            Hashtbl.replace remote_sig_hashes fd.March_tir.Tir.fn_name
              h.March_cas.Hash.sig_hash
          | March_cas.Cas.TypeDef _ -> ()
        in
        List.iter (function
          | March_cas.Pipeline.HSingle { hs_hdef } -> add_hdef hs_hdef
          | March_cas.Pipeline.HGroup { hg_hdefs; _ } -> List.iter add_hdef hg_hdefs)
          h_sccs;
        (* For __rpc_stub base functions inlined by opt (no post-opt entry),
           fall back to pre-opt hashes so stub_setup can emit register calls. *)
        let () =
          let stub_suffix = "__rpc_stub" in
          let slen = String.length stub_suffix in
          let pre_fns = pre_opt_tir.March_tir.Tir.tm_fns in
          let pre_fn_tbl = Hashtbl.create 16 in
          List.iter (fun fd -> Hashtbl.replace pre_fn_tbl fd.March_tir.Tir.fn_name fd) pre_fns;
          List.iter (fun (fn : March_tir.Tir.fn_def) ->
            let n = fn.March_tir.Tir.fn_name in
            let nl = String.length n in
            if nl > slen && String.sub n (nl - slen) slen = stub_suffix then begin
              let base = String.sub n 0 (nl - slen) in
              if not (Hashtbl.mem hr_impl_hashes base) then
                match Hashtbl.find_opt pre_fn_tbl base with
                | Some base_fn ->
                  let h = March_cas.Hash.hash_fn_def base_fn in
                  Hashtbl.replace hr_impl_hashes base h.March_cas.Hash.impl_hash;
                  Hashtbl.replace remote_sig_hashes base h.March_cas.Hash.sig_hash
                | None -> ()
            end
          ) pre_fns;
          (* Pass 2: hash all remaining pre-opt functions so remote_ref_hashes
             constant-folding works even when the optimizer eliminated them
             (e.g. a pfn only referenced from the caller side, not the server). *)
          List.iter (fun (fn : March_tir.Tir.fn_def) ->
            let n = fn.March_tir.Tir.fn_name in
            if not (Hashtbl.mem hr_impl_hashes n) then begin
              let h = March_cas.Hash.hash_fn_def fn in
              Hashtbl.replace hr_impl_hashes n h.March_cas.Hash.impl_hash;
              Hashtbl.replace remote_sig_hashes n h.March_cas.Hash.sig_hash
            end
          ) pre_fns
        in
        (* Post-TIR cache: same key construction as the source-level early
           check above (build_cas_key), keyed on the module's per-SCC impl
           hashes instead of the source digest. *)
        let (_, ch) =
          build_cas_key ~target ~target_label ~src_hash:mod_hash in
        let cached_ok =
          match March_cas.Cas.lookup_artifact store ch with
          | Some cached_bin ->
            March_cas.Cas.copy_artifact ~src:cached_bin ~dest:out_bin
          | None -> false
        in
        (if cached_ok then
          Printf.eprintf "compiled %s (cached)\n" out_bin
        else
          (* Cache miss (or stale artifact / failed copy): emit LLVM IR,
             call clang, then cache the binary *)
          let ir = March_tir.Llvm_emit.emit_module ~fast_math:!fast_math ~pmap_threshold:!pmap_threshold ~target ~hot_reload:(hr_config ()) ~impl_hashes:hr_impl_hashes ~remote_impl_hashes:rpc_impl_hashes ~remote_sig_hashes:remote_sig_hashes ~emit_main:(not !compile_so) ~cap_attrib ~cap_decls tir in
          stamp "llvm-emit";
          let oc = open_out ll_file in
          output_string oc ir;
          close_out oc;
          if is_wasm then begin
            (* ── WASM compilation path ──────────────────────────────────── *)
            let wasm_runtime = match find_runtime_file "march_runtime_wasm.c" with
              | Some p -> p
              | None ->
                (* Fall back to main runtime with -DMARCH_WASM *)
                (match find_runtime_file "march_runtime.c" with
                 | Some p -> p
                 | None ->
                   Printf.eprintf "march: cannot find runtime for WASM target\n"; exit 1)
            in
            let triple = March_tir.Llvm_emit.target_triple target in
            let opt_flag = Printf.sprintf " -O%d" (effective_opt ()) in
            (* Locate wasi-sdk for WASI targets, or use system clang for wasm32-unknown-unknown *)
            let clang, sysroot_flag = match target with
              | March_tir.Llvm_emit.Wasm64Wasi | March_tir.Llvm_emit.Wasm32Wasi ->
                let wasi_sdk = match Sys.getenv_opt "WASI_SDK_PATH" with
                  | Some p -> p
                  | None ->
                    if Sys.file_exists "/opt/wasi-sdk" then "/opt/wasi-sdk"
                    else begin
                      Printf.eprintf "march: wasi-sdk not found. Set WASI_SDK_PATH or install to /opt/wasi-sdk\n";
                      exit 1
                    end
                in
                (Filename.concat wasi_sdk "bin/clang",
                 Printf.sprintf " --sysroot=%s/share/wasi-sysroot" wasi_sdk)
              | _ ->
                (* wasm32-unknown-unknown: need a clang with WASM backend.
                   Apple clang doesn't include it, so try wasi-sdk or homebrew LLVM. *)
                let wasm_clang =
                  let wasi_candidates = [
                    (match Sys.getenv_opt "WASI_SDK_PATH" with Some p -> Some (Filename.concat p "bin/clang") | None -> None);
                    (if Sys.file_exists "/opt/wasi-sdk/bin/clang" then Some "/opt/wasi-sdk/bin/clang" else None);
                    (if Sys.file_exists "/opt/homebrew/opt/llvm/bin/clang" then Some "/opt/homebrew/opt/llvm/bin/clang" else None);
                    (if Sys.file_exists "/usr/local/opt/llvm/bin/clang" then Some "/usr/local/opt/llvm/bin/clang" else None);
                  ] in
                  match List.find_map Fun.id wasi_candidates with
                  | Some p -> p
                  | None ->
                    Printf.eprintf "march: No clang with WASM backend found.\n";
                    Printf.eprintf "  Install wasi-sdk (brew install wasi-sdk) or LLVM (brew install llvm)\n";
                    exit 1
                in
                (wasm_clang, " -nostdlib -Wl,--no-entry -Wl,--export-dynamic")
            in
            let wasm_dbg_flag = if !debug_mode || !debug_tui_mode then " -g" else "" in
            let cmd = Printf.sprintf
              "%s --target=%s%s%s%s -DMARCH_WASM -Wno-unused-command-line-argument %s %s -o %s"
              clang triple sysroot_flag opt_flag wasm_dbg_flag wasm_runtime ll_file out_bin in
            let rc = Sys.command cmd in
            if rc <> 0 then begin
              Printf.eprintf "march: WASM compilation failed (exit %d)\n  cmd: %s\n" rc cmd; exit 1
            end else begin
              stamp "clang";
              March_cas.Cas.store_artifact store ch out_bin;
              (match source_cas_state with
               | Some (src_store, src_ch) -> March_cas.Cas.store_artifact src_store src_ch out_bin
               | None -> ());
              Printf.eprintf "compiled %s (%s)\n" out_bin target_label
            end
          end else begin
            (* ── Native compilation path ────────────────────────────────── *)
            let runtime = match find_runtime_file "march_runtime.c" with
              | Some p -> p
              | None ->
                Printf.eprintf "march: cannot find runtime/march_runtime.c\n"; exit 1
            in
            let opt_flag = Printf.sprintf " -O%d" (effective_opt ()) in
            let runtime_dir = Filename.dirname runtime in
            let http_c      = Filename.concat runtime_dir "march_http.c" in
            let extras_c2   = Filename.concat runtime_dir "march_extras.c" in
            let compress_c2 = Filename.concat runtime_dir "march_compress.c" in
            let opt_file2 f = if Sys.file_exists f then Printf.sprintf " %s" f else "" in
            let sched_c2  = Filename.concat runtime_dir "march_scheduler.c" in
            let ffi_c2    = Filename.concat runtime_dir "march_ffi.c" in
            let sha1_c2   = Filename.concat runtime_dir "sha1.c" in
            let base64_c2 = Filename.concat runtime_dir "base64.c" in
            (* Runtime-owned C sources, kept separate from the user's own FFI
               shims below: only these are eligible for the precompiled-object
               cache (Stage A, see the runtime_objs binding further down) —
               user shims are per-project and must stay per-invocation. *)
            let runtime_extra_c =
              (if Sys.file_exists http_c then
                let simd_c    = Filename.concat runtime_dir "march_http_parse_simd.c" in
                let resp_c    = Filename.concat runtime_dir "march_http_response.c" in
                let io_c      = Filename.concat runtime_dir "march_http_io.c" in
                let evloop_c  = Filename.concat runtime_dir "march_http_evloop.c" in
                let tls_c2    = Filename.concat runtime_dir "march_tls.c" in
                Printf.sprintf " %s %s %s%s%s%s%s%s%s%s%s" http_c sha1_c2 base64_c2
                  (opt_file2 simd_c) (opt_file2 sched_c2) (opt_file2 resp_c)
                  (opt_file2 io_c) (opt_file2 evloop_c)
                  (opt_file2 tls_c2) (opt_file2 extras_c2) (opt_file2 compress_c2)
              else
                (* march_extras.c references base64_encode (base64.c) and sha1
                   (sha1.c), so link them whenever extras is linked — independent
                   of the HTTP stack (else an extras-but-no-http build tree fails
                   with undefined _base64_encode / _sha1). opt_file2-guarded. *)
                Printf.sprintf "%s%s%s%s%s" (opt_file2 sched_c2) (opt_file2 extras_c2)
                  (opt_file2 compress_c2) (opt_file2 base64_c2) (opt_file2 sha1_c2))
              ^ (opt_file2 ffi_c2)
              ^ (if not !compile_so then opt_file2 (Filename.concat runtime_dir "march_dispatch.c") else "")  (* HCR dispatch table *)
              ^ (if not !compile_so then opt_file2 (Filename.concat runtime_dir "march_reload.c")    else "")  (* HCR reload server *)
              ^ (if not !compile_so then opt_file2 (Filename.concat runtime_dir "march_blake3.c")    else "")  (* BLAKE3 for server-side cap_root recompute *)
              ^ (if not !compile_so then opt_file2 (Filename.concat runtime_dir "march_cap_lattice.c") else "")  (* cap subsumption/normalize for ACTIVATE4 admission *)
              ^ opt_file2 (Filename.concat runtime_dir "march_ctx_escape.c")  (* ~H contextual escapers; referenced by march_extras.c *)
              ^ (if not !compile_so then opt_file2 (Filename.concat runtime_dir "tweetnacl.c")       else "")  (* ed25519 for ACTIVATE verification *)
              ^ (opt_file2 (Filename.concat runtime_dir "march_remote_registry.c"))  (* L4 remote registry *)
              ^ (opt_file2 (Filename.concat runtime_dir "march_monitor_registry.c")) (* dist monitor registry *)
            in
            (* User FFI shim sources from forge.toml [[ffi]] (--ffi-c). *)
            let user_ffi_c =
              String.concat "" (List.rev_map (fun f -> " " ^ Filename.quote f) !ffi_c_files) in
            let extra_c_files = runtime_extra_c ^ user_ffi_c in
            (* OpenSSL flags for TLS *)
            let tls_c2 = Filename.concat runtime_dir "march_tls.c" in
            let openssl_flags2 =
              if not (Sys.file_exists tls_c2) then ""
              else
                let dirs = [
                  "/opt/homebrew/opt/openssl@3";
                  "/opt/homebrew/opt/openssl";
                  "/usr/local/opt/openssl@3";
                  "/usr/local/opt/openssl";
                ] in
                let found = List.fold_left (fun acc d ->
                  match acc with
                  | Some _ -> acc
                  | None ->
                    let hdr = Filename.concat d "include/openssl/ssl.h" in
                    if Sys.file_exists hdr then Some d else None
                ) None dirs in
                match found with
                | Some d ->
                  Printf.sprintf " -I%s/include -L%s/lib -lssl -lcrypto" d d
                | None ->
                  if Sys.command "pkg-config --exists openssl 2>/dev/null" = 0
                  then " -lssl -lcrypto" else ""
            in
            let evloop_flag =
              let evloop_c = Filename.concat runtime_dir "march_http_evloop.c" in
              (* Event-loop HTTP server is opt-in: it runs handlers on non-blocking
         loop threads that cannot perform blocking I/O (e.g. a synchronous DB
         connect), which hangs DB-backed apps. Default to thread-per-connection
         (blocking sockets, works on any worker thread); set MARCH_HTTP_EVLOOP=1
         to opt back into the event-loop server. *)
      if Sys.file_exists evloop_c
         && (try Sys.getenv "MARCH_HTTP_EVLOOP" = "1" with Not_found -> false)
      then " -DMARCH_HTTP_USE_EVLOOP" else ""
            in
            let compress_flags2 =
              if not (Sys.file_exists compress_c2) then ""
              else begin
                let zstd_flags =
                  if Sys.file_exists "/opt/homebrew/include/zstd.h" then
                    " -DMARCH_HAVE_ZSTD -I/opt/homebrew/include -L/opt/homebrew/lib -lzstd"
                  else if Sys.file_exists "/usr/include/zstd.h" then
                    " -DMARCH_HAVE_ZSTD -lzstd"
                  else ""
                in
                let brotli_flags =
                  if Sys.file_exists "/opt/homebrew/include/brotli/encode.h" then
                    " -DMARCH_HAVE_BROTLI -I/opt/homebrew/include -L/opt/homebrew/lib -lbrotlienc -lbrotlidec"
                  else if Sys.file_exists "/usr/include/brotli/encode.h" then
                    " -DMARCH_HAVE_BROTLI -lbrotlienc -lbrotlidec"
                  else ""
                in
                Printf.sprintf " -lz%s%s" zstd_flags brotli_flags
              end
            in
            let math_flag = if Sys.unix then " -lm" else "" in
            let dbg_flag = if !debug_mode || !debug_tui_mode then " -g" else "" in
            let san_flag =
              match Sys.getenv_opt "MARCH_SANITIZE" with
              | Some "thread" -> " -fsanitize=thread -g"
              | Some _ -> " -fsanitize=address,undefined"
              | None -> ""
            in
            (* BLAKE3 flags: needed when march_blake3.c is included (server-only,
               guarded by not !compile_so above, same as march_reload.c). *)
            let blake3_c2 = Filename.concat runtime_dir "march_blake3.c" in
            let blake3_flags2 = if not !compile_so && Sys.file_exists blake3_c2 then blake3_link_flags () else "" in
            (* User FFI linker flags from forge.toml [[ffi]] (--ffi-link), e.g. -lz. *)
            let ffi_link = String.concat "" (List.rev_map (fun f -> " " ^ f) !ffi_link_flags) in
            (* When compiling user FFI shims, put the runtime dir on the include
               path so their `#include "march_ffi.h"` resolves with no config. *)
            let ffi_inc = if !ffi_c_files = [] then ""
                          else Printf.sprintf " -I%s" (Filename.quote runtime_dir) in
            (* Target-derived C compiler + linker decisions (cross-compilation).
               [xtarget] is re-parsed locally so nothing here depends on the
               build host: a cross Linux .so/binary needs Linux linker flags even
               when built on macOS, and vice versa. *)
            let xtarget = parse_target !target_str in
            let link_is_linux =
              March_tir.Llvm_emit.target_is_linux xtarget
              || (match xtarget with
                  | March_tir.Llvm_emit.Native -> Sys.file_exists "/proc/version"
                  | _ -> false) in
            let rdynamic_flag =
              (* Export all symbols so dlopen'd patch .so can resolve back to server.
                 Pass via -Wl, so the flag goes straight to the linker, not the clang driver.
                 Linux (GNU ld): --export-dynamic. macOS (ld64): -export_dynamic. *)
              if !hot_reload_prefix <> None && not !compile_so then
                if link_is_linux then " -Wl,--export-dynamic"
                else " -Wl,-export_dynamic"
              else "" in
            let so_flag =
              if !compile_so then
                (* Linux: allow undefined symbols resolved from the server binary at dlopen time.
                   macOS: clang uses -undefined dynamic_lookup for the same effect. *)
                let undef = if link_is_linux
                            then " -Wl,--allow-shlib-undefined"
                            else " -undefined dynamic_lookup" in
                " -shared -fPIC" ^ undef
              else "" in
            let reload_ldl =
              (* -ldl is needed on Linux for dlopen; macOS has it in libc. *)
              if !hot_reload_prefix <> None && not !compile_so
                 && link_is_linux then " -ldl" else "" in
            let cap_sandbox_define =
              (* --cap-sandbox: embed a DENY-DEFAULT SBPL profile derived from
                 this module's own inferred capabilities, applied by
                 march_sandbox_install() before any user code runs
                 (the MARCH_CAP_PROFILE block in runtime/march_runtime.c).

                 Defense in depth only: whoever builds the binary chooses
                 whether to compile it in, so a hostile publisher omits it.
                 Its value is a binary you built and trust, deployed where
                 forge is not the launcher (systemd, a supervisor) --- the
                 case `forge cap run` cannot reach.  Externally imposed
                 enforcement stays the stronger mechanism.

                 Baseline mirrors forge/lib/cap_sandbox.ml's sbpl_baseline;
                 the two are kept in step by test/test_cap_sandbox_profile.ml. *)
              if not !cap_sandbox then ""
              else begin
                (* Filter to THIS module's own functions.  Using the whole
                   closure table unions in every linked stdlib function and
                   yields the app-invariant "needs everything" set --- which
                   would grant a pure program network and filesystem write
                   access, i.e. a sandbox that sandboxes nothing.  Same
                   filtering as `march caps`. *)
                let caps = own_caps_of_this_module
          ~stdlib_files:(stdlib_span_files stdlib_decls) typecheck_env desugared in
                let declared_scopes =
                  March_typecheck.Typecheck.declared_cap_scopes typecheck_env in
                let holds klass =
                  List.exists (fun c ->
                      March_caps.Cap_lattice.cap_subsumes klass c
                      || March_caps.Cap_lattice.cap_subsumes c klass) caps
                in
                let b = Buffer.create 512 in
                Buffer.add_string b "(version 1)(deny default)";
                Buffer.add_string b "(allow process-exec)";
                Buffer.add_string b "(allow file-read* file-read-metadata)";
                Buffer.add_string b
                  "(allow file-write-data (literal \\\"/dev/null\\\") \
                   (literal \\\"/dev/stdout\\\") (literal \\\"/dev/stderr\\\") \
                   (literal \\\"/dev/tty\\\"))";
                Buffer.add_string b "(allow sysctl-read)(allow mach*)(allow signal)";
                Buffer.add_string b "(allow ipc-posix-shm)(allow iokit-open)";
                (* Scoped filesystem grants.
                   WRITE only, and that asymmetry is measured, not assumed:

                   - file-write is not granted by the baseline, so narrowing it
                     to a subpath genuinely enforces.  Verified both ways: an
                     in-scope write succeeds, an out-of-scope one is refused.
                   - file-read IS granted by the baseline, unconditionally,
                     because dyld must map system libraries before any user
                     code exists.  A scoped read allow would therefore be
                     DECORATIVE — it adds nothing to a blanket grant already
                     present.  Narrowing the baseline was tried and aborts the
                     runtime (SIGABRT) even with /usr/lib, /System, /usr/share
                     and /dev/urandom explicitly allowed.  So IO.FileRead stays
                     advisory here rather than shipping a rule that looks like
                     enforcement and is not.  Linux scopes reads properly via
                     the mount-namespace allow-list in forge/lib/cap_sandbox.ml.

                   CAVEAT for scope authors: the kernel matches subpaths AFTER
                   resolving symlinks, and normalization here is lexical (the
                   build machine's filesystem is not the deployment machine's).
                   A scope of "/tmp/x" on macOS therefore matches nothing,
                   because /tmp is a symlink to /private/tmp.  Give the
                   resolved path. *)
                let write_scopes =
                  List.filter_map (fun (cap, sc) ->
                      if March_caps.Cap_lattice.cap_subsumes "IO.FileWrite" cap
                         || March_caps.Cap_lattice.cap_subsumes cap "IO.FileWrite"
                      then Some sc else None)
                    declared_scopes
                in
                if holds "IO.FileWrite" then begin
                  (* An unscoped grant among them means any path: narrowing
                     would be a lie if one declaration is unrestricted. *)
                  if write_scopes = [] || List.exists (fun sc -> sc = None) write_scopes
                  then Buffer.add_string b "(allow file-write*)"
                  else
                    List.iter (function
                        | None -> ()
                        | Some path ->
                          Buffer.add_string b
                            (Printf.sprintf "(allow file-write* (subpath \\\"%s\\\"))"
                               (March_caps.Cap_scope.normalize path)))
                      write_scopes
                end;
                if holds "IO.Network"   then Buffer.add_string b "(allow network*)";
                if holds "IO.Process"   then Buffer.add_string b "(allow process-fork)";
                (* Per-capability DENY flags, consumed by the Linux
                   seccomp-bpf builder in runtime/march_runtime.c.  Emitted on
                   both platforms so the two backends are driven by one
                   decision rather than two copies of it. *)
                let deny name held =
                  if held then "" else " -DMARCH_CAP_DENY_" ^ name in
                let deny_flags =
                  deny "NET"   (holds "IO.Network")
                  ^ deny "EXEC"  (holds "IO.Process")
                  ^ deny "WRITE" (holds "IO.FileWrite")
                in
                (* Filename.quote the ALREADY-quoted C literal so the shell
                   hands clang a real string; without the inner quotes the
                   macro expands as bare SBPL tokens and the runtime will not
                   compile. *)
                " -DMARCH_CAP_PROFILE="
                ^ Filename.quote ("\"" ^ Buffer.contents b ^ "\"")
                ^ deny_flags
              end in
            let strip_flag =
              (* Capability-by-absence (specs/2026-08-03-forge-cap-audit-design.md
                 §4.1): drop runtime functions the program never references, so a
                 binary physically cannot perform a capability it does not use —
                 and `forge cap inspect` can read capabilities from what remains.

                 Executables only.  A hot-reload .so resolves __march_init and
                 __migrate_<Actor> via dlsym (runtime/march_reload.c:318-351),
                 which the linker cannot see, so stripping would break hot
                 deploy; the --hot-reload server build likewise exports symbols
                 (-Wl,--export-dynamic above) for the dlopen'd patch .so to
                 resolve against. *)
              if !compile_so || !hot_reload_prefix <> None then ""
              else if link_is_linux then " -Wl,--gc-sections"
              else " -Wl,-dead_strip" in
            let section_cflags =
              (* ELF --gc-sections only drops whole sections; without
                 -ffunction-sections each object's .text is one section and
                 individual functions survive (verified with gcc 11 and
                 clang 18 — design §4.1).  Mach-O gets function granularity
                 for free via .subsections_via_symbols.  Runtime_archive.ensure
                 folds cflags into its cache key, so stale non-sectioned
                 runtime objects are invalidated automatically. *)
              if strip_flag <> "" && link_is_linux
              then " -ffunction-sections -fdata-sections"
              else "" in
            let signing_define =
              if !hot_reload_prefix <> None && not !compile_so && !signing_pubkey <> "" then
                match b64_decode_pubkey !signing_pubkey with
                | Some hex -> Printf.sprintf " -DMARCH_SIGNING_PUBKEY_HEX=\\\"%s\\\"" hex
                | None ->
                  Printf.eprintf "march: --signing-pubkey: invalid base64 or not 32 bytes\n";
                  ""
              else "" in
            (* Target-derived C compiler + arch flags (cross-compilation). *)
            let cc_driver =
              match March_tir.Llvm_emit.zig_target xtarget with
              | Some zt -> Printf.sprintf "zig cc -target %s" zt
              | None    -> "clang"
            in
            let arch_cflags =
              match xtarget with
              | March_tir.Llvm_emit.(LinuxGnu { arch = Arm64; _ }) -> ""   (* NEON by default; SSE flags are x86-only *)
              | March_tir.Llvm_emit.(LinuxGnu { arch = X86_64; _ }) | March_tir.Llvm_emit.Native -> " -msse4.2"
              | March_tir.Llvm_emit.(Wasm64Wasi | Wasm32Wasi | Wasm32Unknown | Js) -> ""
            in
            (* Cross Linux link (P3): link TLS (OpenSSL 3) + gzip (zlib) against a
               TARGET sysroot instead of the host's homebrew libs.  march_tls.c
               and march_compress.c cross-compile cleanly given the target
               headers, so KEEP them; but drop march_blake3.c (needs a target
               libblake3 we don't vendor) and march_reload.c (the HCR reload
               server — hot-reload-over-cross is out of scope; its symbols are the
               only thing that pulled in blake3).  Host-discovered link flags are
               replaced wholesale so no -L/opt/homebrew/lib leaks into the cross
               link.  See specs/2026-07-04-cross-compile-linux-hot-deploy-design.md
               §5 (P3). *)
            let is_cross = March_tir.Llvm_emit.target_is_linux xtarget in
            let cross_sysroot =
              if not is_cross then None
              else match linux_arch_str xtarget with
                | None -> None
                | Some arch ->
                  (match cross_sysroot_dir arch with
                   | Some d -> Some d
                   | None ->
                     Printf.eprintf
                       "march: cross-compile target sysroot for linux/%s not found.\n\
                       \  TLS (OpenSSL) + gzip (zlib) cross-linking needs target \
                        libssl/libcrypto/libz + headers.\n\
                       \  Populate the cache with:\n\
                       \      scripts/fetch-cross-sysroot.sh %s\n\
                       \  or point MARCH_CROSS_SYSROOT_%s (or MARCH_CROSS_SYSROOT) \
                        at a prepared sysroot\n\
                       \  (a dir with lib/{libssl.so.3,libcrypto.so.3,libz.so.1} + \
                        include/openssl + include/zlib.h).\n"
                       arch arch (String.uppercase_ascii arch);
                     exit 1)
            in
            (* Direct positional .so paths (NOT -l:/-L): lld can't find the target
               .sos via -l:libssl.so.3, but a direct path links and records the
               correct DT_NEEDED soname.  zstd/brotli stay off for cross (zlib is
               the only mandatory codec; gzip/deflate is pure zlib). *)
            let openssl_flags2 = match cross_sysroot with
              | None -> openssl_flags2
              | Some sr ->
                Printf.sprintf " -I%s/include %s/lib/libssl.so.3 %s/lib/libcrypto.so.3"
                  sr sr sr
            in
            let compress_flags2 = match cross_sysroot with
              | None -> compress_flags2
              | Some sr ->
                Printf.sprintf " -I%s/include %s/lib/libz.so.1" sr sr
            in
            (* blake3 stays host-discovered for native; zeroed for cross (its .c
               is dropped below — no target libblake3). *)
            let blake3_flags2 = if is_cross then "" else blake3_flags2 in
            let extra_c_files =
              if not is_cross then extra_c_files
              else
                (* Keep march_tls.c + march_compress.c (they link against the
                   target sysroot); drop the blake3/reload HCR pair. *)
                let dropped = ["march_blake3.c"; "march_reload.c"] in
                extra_c_files
                |> String.split_on_char ' '
                |> List.filter (fun p ->
                     p = "" || not (List.mem (Filename.basename p) dropped))
                |> String.concat " " in
            (* -fno-strict-aliasing -fwrapv: the C runtime pervasively type-puns
               (tagged pointers, reading a march_value cell's fields as different
               types, int<->ptr casts), which is strict-aliasing UB. Without these
               flags an aggressive -O2 optimizer (notably stock Linux clang, unlike
               Apple/zig clang) miscompiles the FFI Result/Option decoders and reads
               a neighboring constant — e.g. an Err("nan") payload surfaced as
               "bad int". The test-runner C rules already pass these; the production
               --compile path must too. *)
            (* Stage A: reuse precompiled runtime objects when this build's
               flags admit it, so clang only has to compile the (small)
               generated .ll instead of the whole ~20-file C runtime.  See
               lib/cas/runtime_archive.ml for the cache key and why the
               whole-binary CAS above cannot serve this.

               Deliberately narrow eligibility — every excluded case either
               bakes a per-invocation -D into the runtime sources or changes
               how they compile, and none of them is on any CI path (verified
               by grep over test/dune + ci.yml), so the fallback staying on
               today's exact monolithic command costs nothing measurable:
                 - non-Native targets: cross builds swap in a target sysroot
                   and drop sources (see the is_cross filter above); wasm/js
                   never reach here at all;
                 - --compile-so: adds -fPIC to every runtime object;
                 - MARCH_HTTP_EVLOOP=1: -DMARCH_HTTP_USE_EVLOOP is read from
                   march_http.h, so it changes more than march_http_evloop.c;
                 - --hot-reload with --signing-pubkey: bakes
                   -DMARCH_SIGNING_PUBKEY_HEX into march_reload.c.
               MARCH_NO_RUNTIME_CACHE=1 forces the fallback for A/B checks. *)
            let runtime_objs =
              let eligible =
                (match xtarget with March_tir.Llvm_emit.Native -> true | _ -> false)
                && not !compile_so
                && evloop_flag = ""
                && signing_define = ""
                && !hot_reload_prefix = None
                && Sys.getenv_opt "MARCH_NO_RUNTIME_CACHE" = None
              in
              if not eligible then None
              else begin
                let srcs =
                  runtime
                  :: (String.split_on_char ' ' runtime_extra_c
                      |> List.filter (fun s -> s <> "")) in
                (* Byte-identical to the compile half of the command below,
                   minus link-only/user-FFI pieces: -L/-l are inert under -c
                   (and -Wno-unused-command-line-argument is already passed),
                   while the -D/-I inside the openssl/compress/blake3 flags
                   genuinely affect codegen and so must be in the key. *)
                let cflags =
                  (* cap_sandbox_define MUST be here, not only on the link
                     line: these objects are precompiled and cached, so a
                     define applied at link time never reaches
                     the runtime and --cap-sandbox silently becomes a
                     no-op.  Runtime_archive.ensure keys on cflags, so
                     including it also invalidates objects built without it. *)
                  Printf.sprintf
                    "%s%s%s%s%s -Wno-unused-command-line-argument -fno-strict-aliasing -fwrapv%s%s%s%s"
                    opt_flag dbg_flag san_flag arch_cflags section_cflags
                    openssl_flags2 compress_flags2 blake3_flags2 cap_sandbox_define in
                match March_cas.Runtime_archive.ensure ~cc:cc_driver ~cflags ~sources:srcs with
                | Ok objs ->
                  Some (String.concat "" (List.map (fun o -> " " ^ Filename.quote o) objs))
                | Error msg ->
                  (if Sys.getenv_opt "MARCH_ECHO_CC" <> None then
                     Printf.eprintf
                       "march: runtime object cache unavailable (%s); \
                        falling back to full recompile\n%!" msg);
                  None
              end
            in
            (* Objects go exactly where their sources used to sit, in the same
               order, so the link is object-for-object identical either way. *)
            let runtime_inputs = match runtime_objs with
              | Some objs -> String.trim objs ^ user_ffi_c
              | None      -> runtime ^ extra_c_files
            in
            let cmd = Printf.sprintf
              "%s%s%s%s%s%s%s%s -Wno-unused-command-line-argument -fno-strict-aliasing -fwrapv%s%s%s%s %s%s%s%s%s %s -o %s%s%s%s"
              cc_driver opt_flag dbg_flag san_flag rdynamic_flag so_flag arch_cflags section_cflags evloop_flag ffi_inc signing_define cap_sandbox_define runtime_inputs openssl_flags2 compress_flags2 blake3_flags2 ffi_link ll_file out_bin math_flag reload_ldl strip_flag in
            (if Sys.getenv_opt "MARCH_ECHO_CC" <> None then
               Printf.eprintf "MARCH_CC_CMD: %s\n%!" cmd);
            let rc = Sys.command cmd in
            if rc <> 0 then begin
              Printf.eprintf "march: clang failed (exit %d)\n" rc; exit 1
            end else begin
              stamp "clang";
              March_cas.Cas.store_artifact store ch out_bin;
              (match source_cas_state with
               | Some (src_store, src_ch) -> March_cas.Cas.store_artifact src_store src_ch out_bin
               | None -> ());
              Printf.eprintf "compiled %s\n" out_bin
            end
          end);
        (* When building a hot-reload .so, write a sidecar manifest so that
           forge deploy hot knows each function's impl_hash and sig_hash
           without having to dlopen the artifact.  Format:
             # march-hcr-manifest v1
             # cas_hash <64-char blake3 hex>
             <fn_name> <impl_hash> <sig_hash> [callers:<a>,<b>] caps=<sorted-csv>
           sig_hash may be empty if the function was not hashed.
           callers: lists other boundary functions that call this one (omitted
           when empty).  The deploy tool uses this to verify that all callers
           of a sig-changed function are also being updated.
           caps: (Phase5C-A.3, revised 2026-07-04 for granularity) the
           function's OWN normalized, sorted inferred IO-capability closure
           from March_typecheck.Typecheck.fn_own_capability_closures — always
           present, empty when the function needs no capabilities.  This is
           deliberately the per-function OWN projection, not the module-merged
           closure: the whole-artifact union is dominated by the linked
           stdlib and is app-invariant, which made the deploy capability gate
           unable to discriminate between artifacts.  There is no
           artifact-wide ROOT cap_root line any more; cap_root is computed
           per-function downstream by the deploy tool from that function's
           own caps= field. *)
        (if !compile_so && Hashtbl.length hr_impl_hashes > 0 then begin
          (* Per-fn OWN cap closures, keyed by qualified name ("Mod.fn").
             fn_own_capability_closures returns each function's own caps
             (body/sig/extern), WITHOUT the module-wide `needs` merge that
             fn_capability_closures performs — that merge is what made the
             whole-artifact union app-invariant (Granularity revision,
             2026-07-04).  Caps are already normalized by Cap_lattice.normalize;
             sort here only for deterministic CSV output (List.sort does not
             mutate the underlying set). *)
          let fn_caps_tbl : (string, string list) Hashtbl.t = Hashtbl.create 16 in
          List.iter (fun (name, caps) -> Hashtbl.replace fn_caps_tbl name caps)
            (March_typecheck.Typecheck.fn_own_capability_closures typecheck_env);
          let caps_for name =
            (* Manifest names are TIR names.  An actor handler's TIR name is
               BARE ("Weeble_Zorp") while the typechecker keys its closure by
               the declaring module ("Sub.Weeble_Zorp") — two same-named actors
               in different modules must not share one closure.  Bridge the two
               spellings through [Handler_owner], the ownership channel lowering
               already records for exactly this reason; a top-level actor has no
               owner registered and hits the direct lookup. *)
            let key =
              if Hashtbl.mem fn_caps_tbl name then Some name
              else
                match March_tir.Handler_owner.owner_of name with
                | Some owner when Hashtbl.mem fn_caps_tbl (owner ^ "." ^ name) ->
                  Some (owner ^ "." ^ name)
                | _ -> None
            in
            match Option.bind key (Hashtbl.find_opt fn_caps_tbl) with
            | Some caps -> List.sort_uniq String.compare caps
            | None -> []
          in
          (* Build a reverse caller index: callee_name → sorted list of
             boundary caller names.  Walk the pre-opt TIR so that calls which
             the optimizer inlined away are still captured. *)
          let callee_to_callers : (string, string list) Hashtbl.t =
            Hashtbl.create 16
          in
          let add_caller ~callee ~caller =
            let prev = Option.value ~default:[]
                (Hashtbl.find_opt callee_to_callers callee) in
            Hashtbl.replace callee_to_callers callee (caller :: prev)
          in
          (* Recursively scan an expr for EApp calls to boundary functions. *)
          let rec scan_expr caller e =
            let open March_tir.Tir in
            match e with
            | EApp (callee_var, args) ->
              let cn = callee_var.v_name in
              if Hashtbl.mem hr_impl_hashes cn && cn <> caller then
                add_caller ~callee:cn ~caller;
              List.iter (scan_atom caller) args
            | ECallPtr (f, args) ->
              scan_atom caller f;
              List.iter (scan_atom caller) args
            | ELet (_, e1, e2) ->
              scan_expr caller e1; scan_expr caller e2
            | ELetRec (fns, body) ->
              List.iter (fun fd -> scan_expr caller fd.fn_body) fns;
              scan_expr caller body
            | ECase (a, brs, def) ->
              scan_atom caller a;
              List.iter (fun br -> scan_expr caller br.br_body) brs;
              Option.iter (scan_expr caller) def
            | ESeq (e1, e2) -> scan_expr caller e1; scan_expr caller e2
            | EAtom a -> scan_atom caller a
            | ETuple atoms -> List.iter (scan_atom caller) atoms
            | ERecord fields -> List.iter (fun (_, a) -> scan_atom caller a) fields
            | EField (a, _) -> scan_atom caller a
            | EUpdate (a, fields) ->
              scan_atom caller a;
              List.iter (fun (_, av) -> scan_atom caller av) fields
            | EAlloc (_, args) -> List.iter (scan_atom caller) args
            | EStackAlloc (_, args) -> List.iter (scan_atom caller) args
            | EFree a | EIncRC a | EDecRC a
            | EAtomicIncRC a | EAtomicDecRC a -> scan_atom caller a
            | EReuse (a, _, args) ->
              scan_atom caller a;
              List.iter (scan_atom caller) args
            | EAllocHole (tok, _, args, _) ->
              Option.iter (scan_atom caller) tok;
              List.iter (scan_atom caller) args
            | ESetField (o, _, v) -> scan_atom caller o; scan_atom caller v
          and scan_atom _caller _a = ()
          in
          (* Scan every boundary function's body in pre-opt TIR. *)
          List.iter (fun (fd : March_tir.Tir.fn_def) ->
            if Hashtbl.mem hr_impl_hashes fd.fn_name then
              scan_expr fd.fn_name fd.fn_body
          ) pre_opt_tir.March_tir.Tir.tm_fns;
          (* Deduplicate and sort each callers list for deterministic output. *)
          Hashtbl.iter (fun callee callers ->
            let deduped = List.sort_uniq String.compare callers in
            Hashtbl.replace callee_to_callers callee deduped
          ) callee_to_callers;
          let mf = out_bin ^ ".hcr_manifest" in
          (try
             let oc = open_out mf in
             Printf.fprintf oc "# march-hcr-manifest v1\n# cas_hash %s\n" ch;
             Hashtbl.iter (fun name impl_h ->
               let sig_h = Option.value ~default:""
                   (Hashtbl.find_opt remote_sig_hashes name) in
               let callers_field =
                 match Hashtbl.find_opt callee_to_callers name with
                 | Some (_ :: _ as cs) -> " callers:" ^ String.concat "," cs
                 | _ -> ""
               in
               let caps_field = "caps=" ^ String.concat "," (caps_for name) in
               Printf.fprintf oc "%s %s %s%s %s\n" name impl_h sig_h callers_field caps_field
             ) hr_impl_hashes;
             close_out oc
           with Sys_error _ -> ()) (* non-fatal if manifest write fails *)
        end);
        (* Phase 5: emit .schemas.json sidecar for actor state schema checking
           at deploy time.  Each entry records the actor's state field names
           and types so forge deploy hot can diff old vs new schemas. *)
        (if !compile_so && actor_schemas <> [] then begin
          let schema_path = out_bin ^ ".schemas.json" in
          (* Convert an AST predicate expression to a source-text string for
             storage in .schemas.json.  Raises Invalid_argument on unsupported nodes.
             Operators are represented as EApp in the March AST (e.g. "+"(a,b)). *)
          let rec pred_to_string (e : March_ast.Ast.expr) : string =
            let open March_ast.Ast in
            match e with
            | ELit (LitInt n, _)    -> string_of_int n
            | ELit (LitBool b, _)   -> if b then "true" else "false"
            | EVar { txt; _ }       -> txt
            | EField (base, field, _) ->
              pred_to_string base ^ "." ^ field.txt
            (* Binary operators: &&, ||, arithmetic, comparisons *)
            | EApp (EVar { txt = ("&&"|"||"|"+"|"-"|"*"|"/"|"%"
                                 |"=="|"!="|"<"|">"|"<="|">=" as op); _ },
                    [l; r], _) ->
              "(" ^ pred_to_string l ^ " " ^ op ^ " " ^ pred_to_string r ^ ")"
            (* Unary operators *)
            | EApp (EVar { txt = "not"; _ }, [inner], _) ->
              "!(" ^ pred_to_string inner ^ ")"
            | EApp (EVar { txt = "negate"; _ }, [inner], _) ->
              "-" ^ pred_to_string inner
            (* Single-argument measure/function calls *)
            | EApp (EVar { txt = fn_name; _ }, [arg], _) ->
              fn_name ^ "(" ^ pred_to_string arg ^ ")"
            | _ -> raise (Invalid_argument "pred_to_string")
          in
          (try
            let oc = open_out schema_path in
            Printf.fprintf oc "{\n";
            List.iteri (fun i (actor_name, fields) ->
                let field_lines =
                  if fields = [] then "[]"
                  else "[\n" ^
                    String.concat ",\n" (List.map (fun (fname, fty) ->
                      Printf.sprintf {|      {"name":%S,"ty":%S}|} fname (ty_to_schema_str fty)
                    ) fields) ^ "\n    ]"
                in
                let compat = Option.value ~default:"full"
                    (List.assoc_opt actor_name actor_compat_map) in
                let invariant_line = match List.assoc_opt actor_name actor_invariant_map with
                  | None -> ""
                  | Some e ->
                    (try Printf.sprintf "    \"invariant\": %S,\n" (pred_to_string e)
                     with Invalid_argument _ ->
                       Printf.eprintf
                         "warning: @invariant on %s contains unsupported expression; omitting\n"
                         actor_name;
                       "")
                in
                Printf.fprintf oc
                  "  %S: {\n    \"compat\": %S,\n%s    \"state_fields\": %s\n  }%s\n"
                  actor_name compat invariant_line field_lines
                  (if i < List.length actor_schemas - 1 then "," else "")
              ) actor_schemas;
            Printf.fprintf oc "}\n";
            close_out oc
          with Sys_error e ->
            Printf.eprintf "warning: could not write %s: %s\n" schema_path e)
        end)
      end (* else begin: non-JS LLVM/clang path *)
      end else begin
        (* --emit-llvm only: write IR and exit *)
        (* Mirror the compile path's per-fn impl_hash map so --emit-llvm
           --hot-reload also publishes real baseline hashes (only built/used
           when --hot-reload is active). *)
        let hr_impl_hashes : (string, string) Hashtbl.t = Hashtbl.create 16 in
        let remote_sig_hashes2 : (string, string) Hashtbl.t = Hashtbl.create 16 in
        (* Non-transitive reload-identity hash — see the compile path above for
           why HCR slots must NOT use the transitive Merkle root. *)
        (let add_hdef (hd : March_cas.Cas.hashed_def) =
           match hd.March_cas.Cas.hd_def with
           | March_cas.Cas.FnDef fd ->
             let h = March_cas.Hash.hash_fn_def fd in
             Hashtbl.replace hr_impl_hashes fd.March_tir.Tir.fn_name
               h.March_cas.Hash.impl_hash;
             Hashtbl.replace remote_sig_hashes2 fd.March_tir.Tir.fn_name
               h.March_cas.Hash.sig_hash
           | March_cas.Cas.TypeDef _ -> ()
         in
         List.iter (function
           | March_cas.Pipeline.HSingle { hs_hdef } -> add_hdef hs_hdef
           | March_cas.Pipeline.HGroup { hg_hdefs; _ } -> List.iter add_hdef hg_hdefs)
           (March_cas.Pipeline.hash_module tir));
        let () =
          let stub_suffix = "__rpc_stub" in
          let slen = String.length stub_suffix in
          let pre_fns = pre_opt_tir.March_tir.Tir.tm_fns in
          let pre_fn_tbl = Hashtbl.create 16 in
          List.iter (fun fd -> Hashtbl.replace pre_fn_tbl fd.March_tir.Tir.fn_name fd) pre_fns;
          List.iter (fun (fn : March_tir.Tir.fn_def) ->
            let n = fn.March_tir.Tir.fn_name in
            let nl = String.length n in
            if nl > slen && String.sub n (nl - slen) slen = stub_suffix then begin
              let base = String.sub n 0 (nl - slen) in
              if not (Hashtbl.mem hr_impl_hashes base) then
                match Hashtbl.find_opt pre_fn_tbl base with
                | Some base_fn ->
                  let h = March_cas.Hash.hash_fn_def base_fn in
                  Hashtbl.replace hr_impl_hashes base h.March_cas.Hash.impl_hash;
                  Hashtbl.replace remote_sig_hashes2 base h.March_cas.Hash.sig_hash
                | None -> ()
            end
          ) pre_fns;
          List.iter (fun (fn : March_tir.Tir.fn_def) ->
            let n = fn.March_tir.Tir.fn_name in
            if not (Hashtbl.mem hr_impl_hashes n) then begin
              let h = March_cas.Hash.hash_fn_def fn in
              Hashtbl.replace hr_impl_hashes n h.March_cas.Hash.impl_hash;
              Hashtbl.replace remote_sig_hashes2 n h.March_cas.Hash.sig_hash
            end
          ) pre_fns
        in
        let ir = March_tir.Llvm_emit.emit_module ~fast_math:!fast_math ~pmap_threshold:!pmap_threshold ~target ~hot_reload:(hr_config ()) ~impl_hashes:hr_impl_hashes ~remote_impl_hashes:rpc_impl_hashes ~remote_sig_hashes:remote_sig_hashes2 ~emit_main:(not !compile_so) ~cap_attrib ~cap_decls tir in
        let oc = open_out ll_file in
        output_string oc ir;
        close_out oc;
        Printf.eprintf "wrote %s\n" ll_file
      end
    end
   with
   | March_errors.Errors.ParseError _ as exn -> raise exn
   | March_tir.Js_emit.Js_emit_error _ as exn -> raise exn
   | March_tir.Llvm_calls.Ambiguous_iface_call msg ->
     (* A user-program error (an interface-method call whose dispatch
        position is not concrete at the call site — e.g. bare `from_json`
        with several `derive Json` in scope), not a compiler bug: render it
        as an ordinary diagnostic and exit 1, distinct from the
        internal-compiler-error path below (exit 3). *)
     Printf.eprintf "error: %s\n%!" msg;
     exit 1
   | exn ->
     (* Every diagnosed failure in this pipeline (parse errors, typecheck
        errors, user-file capability-policy violations, clang/link failures)
        already prints its own message and calls `exit` directly — `exit`
        terminates the process without raising, so it never reaches this
        handler.  Anything that DOES land here is an OCaml exception that
        escaped the compile pipeline (Lower -> Mono -> Perceus -> Opt ->
        Llvm_emit) uncaught: per the Oracle Task 2 survey, every failwith/
        assert-false site in lib/tir is an internal-invariant check, so this
        is always a compiler bug, never a "this construct isn't supported"
        signal.  Render it like a diagnostic instead of letting OCaml print
        a raw "Fatal error: exception ..." with no span and no guidance, and
        exit with a distinct, documented code so tooling (the differential
        oracle) can tell "the compiler crashed" apart from a clean, graceful
        nonzero exit. *)
     let bt = Printexc.get_backtrace () in
     Printf.eprintf "march: internal compiler error: %s\n" (Printexc.to_string exn);
     if bt <> "" then Printf.eprintf "%s" bt;
     Printf.eprintf
       "This is a compiler bug, not a problem with your program. Please file \
        an issue with a minimal reproduction.\n%!";
     exit internal_compiler_error_exit_code
  end
  else if jit_run then begin
    (* Whole-program JIT.  Reuses the REPL's machinery wholesale: the same
       runtime .so, the same cached stdlib prelude .so, and the same
       [get_stdlib_tc_env] seed environment the typecheck above ran against —
       so [run_program]'s internal re-check of the user module is the exact
       check_module_full call made at the top of this function, just re-run to
       produce the type_map that lowering needs. *)
    let runtime_so = ensure_runtime_so () in
    let jit_ctx = March_jit.Repl_jit.create ~runtime_so () in
    (try
       Fun.protect
         ~finally:(fun () -> March_jit.Repl_jit.cleanup jit_ctx)
         (fun () ->
            March_repl.Repl.maybe_precompile_stdlib (Some jit_ctx)
              ~stdlib_decls ~type_map;
            let tc_env = get_stdlib_tc_env ~for_js:false stdlib_decls in
            (* JIT'd code writes through the C runtime's own stdout and can
               terminate the process with C `exit()` (panic_, exit_, a fatal
               signal), which never runs OCaml's at_exit — so anything still
               sitting in OCaml's stdout/stderr buffers, INCLUDING every
               warning and hint printed by the diagnostics pass above, is lost.
               Measured: a two-warning program printed both warnings
               interpreted and neither under --jit.  Drain the host buffers
               here so --jit output is byte-identical to interpreted. *)
            flush stdout;
            flush stderr;
            March_jit.Repl_jit.run_program jit_ctx ~tc_env user_only_desugared)
     with Failure msg ->
       (* A JIT failure is a compiler-side limitation, not a bug in the user's
          program: report it as one clean line.  Without this the user gets
          `Fatal error: exception Failure(...)` plus an OCaml backtrace and
          rc=2, which reads like an internal compiler error. *)
       Printf.eprintf "march --jit: %s\n%!" msg;
       exit 1
     | exn ->
       (* Same reasoning as the compile_mode `| exn ->` handler above: any
          OCaml exception other than `Failure` that escapes the shared
          Lower -> Mono -> Perceus -> Llvm_emit pipeline (reused wholesale
          here by run_program) is, per the Oracle Task 2 survey, always a
          compiler bug and never a "this construct isn't supported"
          signal. Render it like a diagnostic instead of letting OCaml
          print a raw "Fatal error: exception ..." with no span and no
          guidance, and exit with the same distinct, documented code. *)
       let bt = Printexc.get_backtrace () in
       Printf.eprintf "march: internal compiler error: %s\n" (Printexc.to_string exn);
       if bt <> "" then Printf.eprintf "%s" bt;
       Printf.eprintf
         "This is a compiler bug, not a problem with your program. Please file \
          an issue with a minimal reproduction.\n%!";
       exit internal_compiler_error_exit_code)
  end
  else begin
    (* Set up the on-demand module loader so qualified access like Map.get()
       can trigger loading a stdlib module even if it wasn't explicitly imported.
       This is mostly a fallback — load_stdlib() already loads common modules,
       but this covers modules not in the hardcoded list or REPL scenarios. *)
    March_eval.Eval.module_loader := Some (fun mod_name ->
      match March_modules.Module_registry.find_stdlib_file mod_name with
      | None -> ()
      | Some path ->
        let decls = load_stdlib_file path in
        March_eval.Eval.eval_stdlib_decls decls
    );
    (if !debug_mode || !debug_tui_mode then begin
      let ctx = March_debug.Debug.make_debug_ctx
        ~on_dbg:(fun env ->
          March_debug.Debug_repl.run_session
            (Option.get !March_eval.Eval.debug_ctx) env)
      in
      March_debug.Debug.install ctx;
      Printf.eprintf "[debug] Trace recording enabled (buffer: %d frames)\n%!"
        ctx.March_eval.Eval.dc_trace.March_eval.Eval.rb_cap
    end);
    let print_march_backtrace () =
      let all = March_eval.Eval.get_march_stack () in
      let show_full = Sys.getenv_opt "MARCH_BACKTRACE" = Some "full" in
      (* Canonical stdlib prefix from the same resolver that load_stdlib uses.
         When it matches, no false positives.  When it doesn't match (e.g. the
         stdlib AST was cached from a different build dir), fall back to checking
         that the immediate parent directory is literally named "stdlib" — correct
         for all stdlib paths, both relative and absolute. *)
      let stdlib_prefix_opt =
        match find_stdlib_dir () with
        | None -> None
        | Some p -> Some (p ^ "/")
      in
      let is_stdlib path =
        (match stdlib_prefix_opt with
         | Some prefix when String.starts_with ~prefix path -> true
         | _ -> false)
        || Filename.basename (Filename.dirname path) = "stdlib"
      in
      (* Desugarer-generated EApp nodes use dummy_span (file="<none>", line=0). *)
      let non_synthetic = List.filter (fun f ->
        f.March_eval.Eval.mf_file <> "<none>" && f.March_eval.Eval.mf_line > 0) all
      in
      let frames =
        if show_full then non_synthetic
        else List.filter (fun f -> not (is_stdlib f.March_eval.Eval.mf_file)) non_synthetic
      in
      (* Add "()" to plain identifiers so "panic  file:3" reads as a call site,
         not a definition site.  Operators and <anon> are left as-is. *)
      let display_name name =
        if name = "" || name.[0] = '<' then name
        else
          let is_op_char = function
            | '+' | '-' | '*' | '/' | '=' | '<' | '>' | '!'
            | '&' | '|' | '^' | '~' | '%' -> true
            | _ -> false
          in
          if String.for_all is_op_char name then name
          else name ^ "()"
      in
      if frames <> [] then begin
        Printf.eprintf "\nStack trace (most recent call first):\n";
        List.iteri (fun i f ->
          Printf.eprintf "  [%d] %-24s %s:%d\n"
            i (display_name f.March_eval.Eval.mf_name)
            f.March_eval.Eval.mf_file
            f.March_eval.Eval.mf_line
        ) frames;
        if not show_full then
          Printf.eprintf "\nnote: set MARCH_BACKTRACE=full for all frames including stdlib\n"
      end
    in
    March_eval.Eval.clear_march_stack ();
    setup_interpreter_ffi ();
    (try March_eval.Eval.run_module desugared
     with
     | March_eval.Eval.Eval_error msg ->
       (* panic_/todo_/unreachable_ builtins already prefix their messages with
          "panic: " / "todo: " / "unreachable: " — print as-is. *)
       let hint = March_eval.Eval.interface_method_hint desugared msg in
       Printf.eprintf "%s%s\n" msg (Option.value hint ~default:"");
       print_march_backtrace ();
       exit 1
     | March_eval.Eval.Match_failure msg ->
       Printf.eprintf "panic: match failure — %s\n" msg;
       print_march_backtrace ();
       exit 1
     | March_eval.Eval.Assert_failure msg ->
       Printf.eprintf "panic: %s\n" msg;
       print_march_backtrace ();
       exit 1
     | Unix.Unix_error (Unix.EINTR, syscall, _) ->
       (* SIGINT interrupted a blocking syscall (accept/select/recv) —
          print nothing if shutdown was requested, otherwise show the call *)
       if not !March_eval.Eval.shutdown_requested then
         Printf.eprintf "%s: interrupted syscall: %s\n" filename syscall;
       exit 0);
    March_debug.Debug.uninstall ()
  end

(** Type-check multiple .march files together.
    Parses each file, collects all their declarations, and type-checks the
    combined module.  Exits 0 on success, 1 if any errors are found.
    Used by [forge build] for library projects. *)
(* [run_check_cmd ~emit_caps files] — `march check`, and with [emit_caps] also
   `march caps`: the PACKAGE's inferred capability set as JSON.

   Package-level, not per-file, because per-file analysis does not work: most
   files in a real package reference sibling modules and fail standalone
   (measured: conduit 9/43, depot 14/32, forgepm 15/60), and a union over
   whatever happened to typecheck UNDER-reports — the dangerous direction for
   a capability record, since it certifies a package as needing less than it
   does.  This path loads the whole package exactly as `march check` does, so
   sibling and dependency imports resolve.

   Errors are fatal even in caps mode: a package that does not typecheck has
   no knowable capability set, and reporting a partial one would be the same
   under-report by another route. *)
let caps_env : March_typecheck.Typecheck.env option ref = ref None
(* file path -> module names that file declares.  Used to keep the reported
   capability set to the package's OWN modules. *)
let file_modules : (string, string list) Hashtbl.t = Hashtbl.create 32

let run_check_cmd ?(emit_caps = false) files =
  if files = [] then begin
    Printf.eprintf "march check: no files specified\n"; exit 1
  end;
  let stdlib_decls = load_stdlib ~for_js:(parse_target !target_str = March_tir.Llvm_emit.Js) () in
  (* Files pulled in by import resolution (source dir / MARCH_LIB_PATH) are
     user code too: diagnostics pointing into them must be fatal even though
     they were not listed on the command line. *)
  let import_user_files = ref [] in
  (* Parse and desugar each file; collect all declarations *)
  let all_decls = List.concat_map (fun filename ->
    let src =
      try read_file filename
      with Sys_error msg ->
        Printf.eprintf "march: %s\n" msg; exit 1
    in
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
    let module_ast =
      try March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
      with
      | March_errors.Errors.ParseError (msg, hint, _) ->
        Printf.eprintf "%s\n"
          (March_errors.Errors.render_parse_error ~src ~filename ?hint ~msg lexbuf);
        exit 1
      | March_parser.Parser.Error ->
        Printf.eprintf "%s\n"
          (March_errors.Errors.render_parse_error ~src ~filename
             ~msg:"I got stuck here:" lexbuf);
        exit 1
    in
    let desugared = March_desugar.Desugar.desugar_module module_ast in
    (* Record which modules this file declares, top-level and nested, so caps
       mode can filter to the package's own code. *)
    (let names = ref [ desugared.March_ast.Ast.mod_name.March_ast.Ast.txt ] in
     let rec walk prefix decls =
       List.iter (fun (d : March_ast.Ast.decl) ->
           match d with
           | March_ast.Ast.DMod (n, _, inner, _) ->
             let q = if prefix = "" then n.March_ast.Ast.txt
                     else prefix ^ "." ^ n.March_ast.Ast.txt in
             names := q :: n.March_ast.Ast.txt :: !names;
             walk q inner
           | _ -> ()) decls
     in
     walk "" desugared.March_ast.Ast.mod_decls;
     Hashtbl.replace file_modules filename !names);
    let (_resolve_errors, extra_decls, user_files) = resolve_imports ~source_file:filename desugared in
    import_user_files := user_files @ !import_user_files;
    (* [extra_decls] (this file's auto-discovered/imported modules) must stay
       FLAT top-level siblings of this file's own DMod, not merged into its
       body — nesting them one level in (a) gives them the wrong qualified
       name (Module.name becomes EntryFile.Module.name — the exact hazard
       [resolve_imports]'s own doc comment warns against) and (b) hides
       cross-file duplicates from the dedup pass below: when checking
       multiple files together, each file's OWN [resolve_imports] call
       independently auto-discovers the whole search path (its dedup tables
       are scoped to that one call), so two files that both see the same
       shared dependency each produce their own copy of it — only visible
       to dedup if both copies land as top-level siblings here. *)
    [March_ast.Ast.DMod (desugared.March_ast.Ast.mod_name,
                         March_ast.Ast.Public,
                         desugared.March_ast.Ast.mod_decls,
                         March_ast.Ast.dummy_span)]
    @ extra_decls
  ) files in
  (* [resolve_imports] auto-discovers the WHOLE library search path on every
     call, with its dedup tables scoped to that single call — so calling it
     once per [files] entry (above) independently re-embeds every shared
     transitive import once per file that (directly or auto-discovered-ly)
     pulls it in.  For N files sharing common dependencies this blows up the
     combined module to N copies of the shared decls (confirmed: verified
     against a live project, error-message repeat count scaled exactly
     linearly with file count, and total time compounded far worse than
     linearly on top of that — 5 files took 24x longer than 1).  Every
     top-level decl this loop produces is a whole-module DMod, and a given
     module name always maps to exactly one file (one-mod-per-file
     convention), so any two DMods sharing a name ARE the same module —
     keep only the first occurrence. *)
  let seen_mod_names : (string, unit) Hashtbl.t = Hashtbl.create 64 in
  let all_decls = List.filter (function
    | March_ast.Ast.DMod ({March_ast.Ast.txt = mn; _}, _, _, _) ->
      if Hashtbl.mem seen_mod_names mn then false
      else begin Hashtbl.add seen_mod_names mn (); true end
    | _ -> true
  ) all_decls in
  (* If a checked file's own module name shadows a stdlib module (e.g. a
     project's own `mod Crypto do` — the exact scenario [compile]'s
     [extern_mod_names] below already guards against for the single-file
     --check/--compile path), strip the stdlib copy so the project's
     definition is the sole one.  Without this, both DMods named "Crypto"
     end up in the combined module and corrupt unrelated typecheck state:
     confirmed live — an unrelated user file shadowing stdlib Crypto made a
     completely different module's own constructor (`PgTarget`, from a
     third file) become unresolvable, with no diagnostic pointing at the
     real cause. *)
  let stdlib_decls_unshadowed_count = List.length stdlib_decls in
  let stdlib_decls = List.filter (function
    | March_ast.Ast.DMod ({March_ast.Ast.txt = mn; _}, _, _, _) ->
      not (Hashtbl.mem seen_mod_names mn)
    | _ -> true
  ) stdlib_decls in
  let no_shadowing = List.length stdlib_decls = stdlib_decls_unshadowed_count in
  if not (List.for_all is_shipped_stdlib_file files) then
    check_no_prelude_collision_decls ~stdlib_decls all_decls;
  (* Build a synthetic module of just the user's own decls and type-check it,
     seeded from the cached stdlib typecheck env (see [get_stdlib_tc_env])
     instead of re-typechecking stdlib combined with user code from scratch —
     UNLESS a user file shadows a stdlib module name, in which case the
     cached (full, unshadowed) stdlib env would be wrong for this project;
     that's rare enough to just fall back to the slower from-scratch
     combined check rather than parameterize the cache key on the shadow set. *)
  let dummy_span = March_ast.Ast.{
    file = ""; start_line = 0; start_col = 0; end_line = 0; end_col = 0
  } in
  let errors =
    if no_shadowing then begin
      let seed_env = get_stdlib_tc_env
        ~for_js:(parse_target !target_str = March_tir.Llvm_emit.Js) stdlib_decls in
      let user_only = {
        March_ast.Ast.mod_name = { March_ast.Ast.txt = "LibCheck"; span = dummy_span };
        March_ast.Ast.mod_decls = all_decls;
      } in
      let (errs, _tm, env) =
        March_typecheck.Typecheck.check_module_core ~seed_env user_only in
      caps_env := Some env;
      errs
    end else begin
      let combined = {
        March_ast.Ast.mod_name = { March_ast.Ast.txt = "LibCheck"; span = dummy_span };
        March_ast.Ast.mod_decls = stdlib_decls @ all_decls;
      } in
      (* check_module_full rather than check_module: it additionally returns
         the typecheck env, which caps mode needs.  This branch runs whenever a
         package shadows a stdlib module name — bastion does — so without it
         `march caps` failed on exactly those packages with "capability
         closures unavailable". *)
      let (errs, _type_map, env) =
        March_typecheck.Typecheck.check_module_full combined in
      caps_env := Some env;
      errs
    end
  in
  let diags = March_errors.Errors.sorted errors in
  let lib_files =
    List.sort_uniq String.compare (files @ !import_user_files) in
  let is_user_file (d : March_errors.Errors.diagnostic) =
    List.mem d.span.March_ast.Ast.file lib_files ||
    d.span.March_ast.Ast.file = "" ||
    d.span.March_ast.Ast.file = "<unknown>"
  in
  let user_diags severity = List.filter (fun d ->
    is_user_file d && d.March_errors.Errors.severity = severity
  ) diags in
  let user_errors   = user_diags March_errors.Errors.Error in
  let user_warnings = user_diags March_errors.Errors.Warning in
  let print_diag label (d : March_errors.Errors.diagnostic) =
    Printf.eprintf "%s:%d:%d: %s: %s\n"
      d.span.March_ast.Ast.file
      d.span.March_ast.Ast.start_line
      d.span.March_ast.Ast.start_col
      label
      d.message
  in
  List.iter (print_diag "warning") user_warnings;
  List.iter (print_diag "error") user_errors;
  if user_errors <> [] then begin
    if emit_caps then
      Printf.eprintf
        "march caps: %d error(s) — a package that does not typecheck has no \
         knowable capability set; refusing to report a partial one\n"
        (List.length user_errors);
    exit 1
  end;
  if emit_caps then begin
    match !caps_env with
    | None ->
      Printf.eprintf
        "march caps: capability closures unavailable (no-shadowing mode is \
         required to expose the typecheck env)\n";
      exit 1
    | Some env ->
      (* Keep only functions belonging to the modules the LISTED files declare.
         Imported deps and stdlib are excluded: including them re-creates the
         app-invariant "needs everything" union. *)
      let own_mods = Hashtbl.create 16 in
      List.iter (fun f ->
          match Hashtbl.find_opt file_modules f with
          | Some names -> List.iter (fun n -> Hashtbl.replace own_mods n ()) names
          | None -> ())
        files;
      let belongs qname =
        match String.index_opt qname '.' with
        | None -> Hashtbl.mem own_mods qname
        | Some i -> Hashtbl.mem own_mods (String.sub qname 0 i)
      in
      let caps =
        List.concat_map
          (fun (qname, cs) -> if belongs qname then cs else [])
          (March_typecheck.Typecheck.fn_own_capability_closures env)
        |> List.sort_uniq String.compare
        |> March_caps.Cap_lattice.normalize
        |> List.sort String.compare
      in
      Printf.printf "{\"caps\":[%s]}\n"
        (String.concat "," (List.map (Printf.sprintf "%S") caps));
      exit 0
  end;
  exit 0

(* ── Phase 10: GC trace analyser ────────────────────────────────────── *)
(*
 * Reads a gc.jsonl file produced by MARCH_TRACE_GC=1 and reports:
 *   - leaked objects   (alloc'd but never freed at program end)
 *   - double frees     (free event for an already-freed address)
 *   - negative RCs     (dec_ref whose post-decrement RC < 0)
 *)
let analyze_gc_trace path =
  let ic = try open_in path
           with Sys_error _ ->
             Printf.eprintf "march analyze-trace: cannot open '%s'\n" path;
             exit 1
  in
  (* Minimal JSON field scanner — pure OCaml, no external deps.
     Handles "key":"string_val" and "key":number_val forms. *)
  let str_find haystack needle from =
    let hl = String.length haystack and nl = String.length needle in
    let r = ref (-1) and i = ref from in
    while !i <= hl - nl && !r < 0 do
      if String.sub haystack !i nl = needle then r := !i else incr i
    done; !r
  in
  let get_field json key =
    let ps = "\"" ^ key ^ "\":\"" in
    let pn = "\"" ^ key ^ "\":" in
    let i  = str_find json ps 0 in
    if i >= 0 then
      let s = i + String.length ps in
      (match String.index_from_opt json s '"' with
       | Some e -> Some (String.sub json s (e - s))
       | None   -> None)
    else
      let j = str_find json pn 0 in
      if j >= 0 then
        let s = j + String.length pn in
        let e = ref s in
        while !e < String.length json &&
              (let c = json.[!e] in (c >= '0' && c <= '9') || c = '-') do
          incr e
        done;
        if !e > s then Some (String.sub json s (!e - s)) else None
      else None
  in
  let live  : (string, int * int) Hashtbl.t = Hashtbl.create 4096 in
  let freed : (string, bool)      Hashtbl.t = Hashtbl.create 1024 in
  let n_alloc = ref 0 and n_free = ref 0 and n_inc = ref 0 and n_dec = ref 0 in
  let n_double = ref 0 and n_neg = ref 0 and lno = ref 0 in
  (try while true do
    let line = String.trim (input_line ic) in
    incr lno;
    if line <> "" then begin
      let ev   = Option.value ~default:"" (get_field line "event") in
      let addr = Option.value ~default:"" (get_field line "addr")  in
      let rc   = Option.fold  ~none:0 ~some:int_of_string (get_field line "rc") in
      match ev with
      | "alloc" ->
        incr n_alloc;
        Hashtbl.replace live addr (rc, !lno);
        Hashtbl.remove freed addr
      | "free" ->
        incr n_free;
        if Hashtbl.mem freed addr then incr n_double
        else begin Hashtbl.remove live addr; Hashtbl.replace freed addr true end
      | "inc_ref" ->
        incr n_inc;
        (match Hashtbl.find_opt live addr with
         | Some (_, eno) -> Hashtbl.replace live addr (rc, eno)
         | None -> ())
      | "dec_ref" ->
        incr n_dec;
        (match Hashtbl.find_opt live addr with
         | Some (_, eno) ->
           if rc < 0 then incr n_neg;
           Hashtbl.replace live addr (rc, eno)
         | None -> ())
      | _ -> ()
    end
  done with End_of_file -> ());
  close_in ic;
  let n_leaked = Hashtbl.length live in
  Printf.printf "March GC Trace Analysis: %s\n" path;
  Printf.printf "  events        : alloc=%d  free=%d  inc_ref=%d  dec_ref=%d\n"
    !n_alloc !n_free !n_inc !n_dec;
  Printf.printf "  leaked objects: %d\n" n_leaked;
  Printf.printf "  double frees  : %d\n" !n_double;
  Printf.printf "  negative RCs  : %d\n" !n_neg;
  let ok = n_leaked = 0 && !n_double = 0 && !n_neg = 0 in
  if ok then print_string "  result: OK\n"
  else begin
    if n_leaked > 0 then begin
      Printf.eprintf "error: %d leaked object(s)\n" n_leaked;
      let shown = ref 0 in
      Hashtbl.iter (fun addr (rc, eno) ->
        if !shown < 10 then begin
          Printf.eprintf "  leak: addr=%-18s rc=%-3d (alloc at event #%d)\n" addr rc eno;
          incr shown
        end
      ) live;
      if n_leaked > 10 then
        Printf.eprintf "  … and %d more\n" (n_leaked - 10)
    end;
    if !n_double > 0 then
      Printf.eprintf "error: %d double-free(s)\n" !n_double;
    if !n_neg   > 0 then
      Printf.eprintf "error: %d negative reference count(s)\n" !n_neg
  end;
  exit (if ok then 0 else 1)

let () =
  (* Colour — priority: MARCH_COLOR env > NO_COLOR env > TERM=dumb > isatty. *)
  March_errors.Errors.use_color := (
    match Sys.getenv_opt "MARCH_COLOR" with
    | Some "always" -> true
    | Some "never"  -> false
    | _ ->
      Sys.getenv_opt "NO_COLOR" = None
      && Sys.getenv_opt "TERM" <> Some "dumb"
      && Unix.isatty Unix.stderr
  )

let () =
  (* Register the runtime directory with the CAS before anything can compute a
     compilation_hash, so the cache key always digests the sources this process
     will actually compile (see [runtime_dir]). *)
  ignore (Lazy.force runtime_dir)

let () =
  (* Handle subcommands before Arg.parse *)
  let argv = Sys.argv in
  if Array.length argv >= 2 && (argv.(1) = "--version" || argv.(1) = "-version") then begin
    (* Version.version is generated by bin/dune from dune's own
       %{version:march} variable (the (version ...) field in dune-project),
       instead of a literal that silently rots every release (this one was
       already stale: still said 0.1.0 at 0.1.1/0.2.0). *)
    Printf.printf "march %s\n" Version.version;
    exit 0
  end;
  if Array.length argv >= 2 && argv.(1) = "fmt" then begin
    let rest = Array.to_list (Array.sub argv 2 (Array.length argv - 2)) in
    run_fmt rest
  end;
  if Array.length argv >= 2 && argv.(1) = "check" then begin
    let rest = Array.to_list (Array.sub argv 2 (Array.length argv - 2)) in
    run_check_cmd rest
  end;
  (* `march caps <files...>` — the package's inferred capability set as JSON.
     Same loading path as `check` so sibling/dependency imports resolve. *)
  if Array.length argv >= 2 && argv.(1) = "caps" then begin
    let rest = Array.to_list (Array.sub argv 2 (Array.length argv - 2)) in
    run_check_cmd ~emit_caps:true rest
  end;
  if Array.length argv >= 2 && argv.(1) = "test" then begin
    let rest = Array.to_list (Array.sub argv 2 (Array.length argv - 2)) in
    run_test_cmd rest
  end;
  (* Phase 10: GC trace validator — see analyze_gc_trace below. *)
  if Array.length argv >= 2 && argv.(1) = "analyze-trace" then begin
    let path = if Array.length argv >= 3 then argv.(2) else "trace/gc/gc.jsonl" in
    analyze_gc_trace path
  end;
  if Array.length argv >= 2 && argv.(1) = "warm-cache" then begin
    let t0 = Unix.gettimeofday () in
    (* 1. Parse + desugar stdlib (populates AST cache) *)
    let stdlib_decls = load_stdlib () in
    let t1 = Unix.gettimeofday () in
    Printf.printf "stdlib AST:      %.3fs\n%!" (t1 -. t0);
    (* 2. Typecheck stdlib (populates TC env cache) *)
    let type_map = Hashtbl.create 64 in
    let base_tc = March_typecheck.Typecheck.base_env
      (March_errors.Errors.create ()) type_map in
    let tc_pre = March_repl.Repl.preregister_stdlib_types base_tc stdlib_decls in
    let content_hash = March_repl.Repl.stdlib_content_hash stdlib_decls in
    (match March_repl.Repl.load_cached_tc_env ~content_hash ~type_map with
     | Some _ ->
       let t2 = Unix.gettimeofday () in
       Printf.printf "tc_env:          %.3fs (cached)\n%!" (t2 -. t1)
     | None ->
       let (_e0, tc0) = March_repl.Repl.load_decls_into_env
         March_eval.Eval.base_env tc_pre stdlib_decls in
       March_repl.Repl.save_cached_tc_env ~content_hash tc0;
       let t2 = Unix.gettimeofday () in
       Printf.printf "tc_env:          %.3fs (built + cached)\n%!" (t2 -. t1));
    (* 2b. Typecheck stdlib via [get_stdlib_tc_env] too — the SEPARATE cache
       `march file.march` actually reads (see the perf-startup comment on
       [get_stdlib_tc_env] above): the REPL's cache warmed just above is a
       different cache/mechanism (fold-based, its own filename prefix), so
       warming only that one left `march warm-cache` NOT warming the cache
       the CLI file-run path depends on — its own hit/miss timing already
       happens inside [get_stdlib_tc_env] via [load_from_cache], so this
       call alone is enough to populate it on a miss. *)
    let t2b_0 = Unix.gettimeofday () in
    ignore (get_stdlib_tc_env ~for_js:false stdlib_decls);
    let t2b_1 = Unix.gettimeofday () in
    Printf.printf "tc_env (cli):    %.3fs\n%!" (t2b_1 -. t2b_0);
    (* 3. Compile C runtime .so *)
    let t3 = Unix.gettimeofday () in
    let runtime_so = ensure_runtime_so () in
    let t4 = Unix.gettimeofday () in
    Printf.printf "runtime .so:     %.3fs\n%!" (t4 -. t3);
    (* 4. Precompile stdlib .so *)
    let jit_ctx = March_jit.Repl_jit.create ~runtime_so () in
    March_repl.Repl.maybe_precompile_stdlib (Some jit_ctx) ~stdlib_decls ~type_map;
    March_jit.Repl_jit.cleanup jit_ctx;
    let t5 = Unix.gettimeofday () in
    Printf.printf "stdlib .so:      %.3fs\n%!" (t5 -. t4);
    Printf.printf "total:           %.3fs\n%!" (t5 -. t0);
    exit 0
  end;
  if Array.length argv >= 2 && argv.(1) = "repl" then begin
    let preload_file = if Array.length argv >= 3 then Some argv.(2) else None in
    let runtime_so = ensure_runtime_so () in
    let jit_ctx = March_jit.Repl_jit.create ~runtime_so () in
    Fun.protect
      ~finally:(fun () -> March_jit.Repl_jit.cleanup jit_ctx)
      (fun () ->
        March_repl.Repl.run ~stdlib_decls:(load_stdlib ())
          ~jit_ctx:(Some jit_ctx) ~preload_file ());
    exit 0
  end;
  if Array.length argv >= 2 && argv.(1) = "dap" then begin
    (* Debug Adapter Protocol server (editor debugger).
       The program to debug is supplied by the editor via the DAP `launch`
       request, not on the command line. We run it through the interpreter
       under a debug context driven by the DAP session. *)

    (* Build a runnable for a source path: parse → desugar → prepend stdlib →
       run_module (the same shape as the interpreter run path). The session
       installs the debug context; this thunk must not install its own. *)
    let make_program path () =
      let src =
        let ic = open_in path in
        let n = in_channel_length ic in
        let b = Bytes.create n in
        really_input ic b 0 n; close_in ic; Bytes.to_string b
      in
      let lexbuf = Lexing.from_string src in
      lexbuf.Lexing.lex_curr_p <-
        { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
      let module_ast =
        March_parser.Parser.module_
          (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
      let desugared = March_desugar.Desugar.desugar_module module_ast in
      let stdlib_decls = load_stdlib () in
      if not (is_shipped_stdlib_file path) then
        check_no_prelude_collision ~stdlib_decls desugared;
      let combined =
        { desugared with
          March_ast.Ast.mod_decls = stdlib_decls @ desugared.March_ast.Ast.mod_decls } in
      March_eval.Eval.module_loader := Some (fun mod_name ->
        match March_modules.Module_registry.find_stdlib_file mod_name with
        | None -> ()
        | Some p -> March_eval.Eval.eval_stdlib_decls (load_stdlib_file p));
      March_eval.Eval.clear_march_stack ();
      March_eval.Eval.run_module combined
    in

    (* Take over fd 1 for the DAP protocol: keep the original stdout for framed
       DAP messages and redirect the program's own stdout to a pipe that we
       forward as DAP `output` events. *)
    let real_out_fd = Unix.dup Unix.stdout in
    let real_oc = Unix.out_channel_of_descr real_out_fd in
    let (pipe_r, pipe_w) = Unix.pipe () in
    Unix.dup2 pipe_w Unix.stdout;
    Unix.close pipe_w;
    set_binary_mode_in stdin true;

    let session =
      March_dap.Dap_session.create ~ic:stdin ~oc:real_oc ~make_program in
    let _reader =
      Thread.create (fun () ->
          let buf = Bytes.create 4096 in
          let rec loop () =
            match Unix.read pipe_r buf 0 4096 with
            | 0 -> ()
            | n ->
              March_dap.Dap_session.send_output session
                ~category:"stdout" (Bytes.sub_string buf 0 n);
              loop ()
            | exception _ -> ()
          in loop ()) ()
    in
    March_dap.Dap_session.serve session;
    exit 0
  end;
  let files = ref [] in
  let specs = [
    ("--dump-tir",     Arg.Set dump_tir,     " Print TIR instead of evaluating");
    ("--dump-phases",  Arg.Set dump_phases,  " Serialize each IR stage to march-phases/phases.json");
    ("--timings",      Arg.Set do_timings,   " Print per-stage compilation times to stderr");
    ("--emit-llvm",  Arg.Set emit_llvm,   " Emit LLVM IR to <file>.ll");
    ("--compile",    Arg.Set do_compile,  " Compile to native binary via clang");
    ("--jit",        Arg.Set jit_mode,
     " Run the program through the in-process ORC JIT instead of the interpreter (experimental)");
    ("--compile-so", Arg.Set compile_so,
     " Compile as a shared library for hot reload patching (no @main, no dispatch init)");
    ("--hot-reload", Arg.String (fun p -> hot_reload_prefix := Some p),
     "<Prefix> Compile modules under <Prefix> with the hot-reload dispatch table");
    ("--signing-pubkey", Arg.Set_string signing_pubkey,
     "<base64>  ed25519 public key to embed for ACTIVATE signature verification (with --hot-reload)");
    ("--ffi-c",      Arg.String (fun f -> ffi_c_files := f :: !ffi_c_files),
                     "<file.c>  Compile+link an FFI shim C source (forge [[ffi]]); repeatable");
    ("--ffi-link",   Arg.String (fun f -> ffi_link_flags := f :: !ffi_link_flags),
                     "<flag>  Extra linker flag for FFI (e.g. -lz); repeatable");
    ("--ffi-so",     Arg.String (fun p -> March_eval.Eval.ffi_shim_so := Some p),
                     "<path.so>  Pre-compiled FFI shim .so to dlopen in interpreter mode");
    ("--check",      Arg.Set do_check,    " Typecheck only — parse, resolve imports, typecheck, then exit (no codegen or eval)");
    ("--cap-strict", Arg.Set cap_strict, " Treat `needs` as a hard ceiling (the DEFAULT since 2026-08-08; accepted for compatibility and to state the intent explicitly)");
    ("--no-cap-strict", Arg.Clear cap_strict, " Do not enforce `needs` as a ceiling: allow a module's emitted code to use capabilities it does not declare");
    ("--cap-sandbox", Arg.Set cap_sandbox, " Embed a self-imposed capability sandbox applied at startup (opt-in; macOS Seatbelt / Linux seccomp-bpf)");
    ("--check-json", Arg.Set check_json,  " Emit diagnostics as NDJSON to stdout (for tooling such as forge fix)");
    ("--no-measure-axioms", Arg.Clear measure_axioms, " Reflect @[measure] functions symbolically instead of axiomatising them (skips datatype/quantifier reasoning and the soundness gate)");
    ("--refine-report", Arg.Set refine_report,
     " Print a summary of refinement obligations: proved, violated, and skipped by reason (user code and user+stdlib)");
    ("--refine-suggest", Arg.String (fun s -> refine_suggest_target := Some s),
     "<fn>  Propose the parameter refinement that discharges what <fn>'s body leaves unproven");
    ("--refine-suggest-all", Arg.Set refine_suggest_all,
     " Propose parameter refinements for every function in user code that has unproven obligations");
    ("--refine-suggest-json", Arg.Set refine_suggest_json,
     " Emit --refine-suggest results as JSON on stdout (for tooling such as forge refine)");
    ("--refine-suggest-post", Arg.String (fun s -> refine_suggest_post := Some s),
     "<fn>  Propose the return refinement that lets <fn>'s callers discharge their obligations");
    ("--refine-suggest-post-all", Arg.Set refine_suggest_post_all,
     " Propose return refinements for every function in user code whose callers have unproven obligations");
    ("--refine-suggest-budget", Arg.Set_int refine_suggest_budget,
     "<N>  Cap the hypothesis re-checks --refine-suggest may spend per function (default 200)");
    ("--test",       Arg.Set do_test,     " Compile test blocks into a standalone test-runner binary (use with --compile)");
    ("--target",     Arg.Set_string target_str,  "<target>  Compilation target: native, wasm64-wasi, wasm32-wasi, wasm32-unknown-unknown");
    ("-o",           Arg.Set_string output_file, "<file>  Output binary name (with --compile)");
    ("--no-opt",    Arg.Clear opt_enabled,  " Skip TIR optimization passes");
    ("--fast-math",  Arg.Set fast_math,  " Emit 'fast' on all FP LLVM instructions");
    ("--trmc", Arg.Unit (fun () -> March_tir.Trmc.enabled := true),
     " Enable tail-recursion-modulo-cons (destination-passing rewrite)");
    ("--no-trmc", Arg.Unit (fun () -> March_tir.Trmc.enabled := false),
     " Disable tail-recursion-modulo-cons");
    ("--pmap-threshold", Arg.Set_int pmap_threshold, "<N>  List.pmap/pfilter/preduce fall back to sequential below N elements (default 1024)");
    ("--opt",        Arg.Set_int opt_level, "<N>  Optimization level passed to clang (0-3)");
    ("--debug",     Arg.Set debug_mode,     " Enable time-travel debugger (simple mode)");
    ("--debug-tui", Arg.Set debug_tui_mode, " Enable time-travel debugger (TUI mode)");
    ("--fmt",       Arg.Set do_fmt,         " Format source file in-place before compiling");
    ("--no-copy-runtime", Arg.Set no_copy_runtime, " (JS) Skip auto-copy of march_runtime.mjs / march_dom.mjs (for build tools that manage them)");
    ("--check-migration", Arg.Set check_migration,
     " Verify migrate_state soundness via SMT (requires --prior-schema and --new-schema)");
    ("--prior-schema", Arg.Set_string prior_schema_path,
     "<path>  Prior .schemas.json for --check-migration");
    ("--new-schema", Arg.Set_string new_schema_path,
     "<path>  New .schemas.json for --check-migration");
    ("--emit-core-ast", Arg.String (fun f -> emit_core_ast_file := Some f),
     " <file.march>  Emit desugared core AST + verdict + diagnostics as JSON to stdout");
  ] in
  (* Legacy escape hatch: MARCH_TRMC=1 predates --trmc and is still used by the
     CI sanitize gate.  Seeded BEFORE Arg.parse so it acts as a DEFAULT — an
     explicit --trmc or --no-trmc on the command line overrides it either way.
     (Applying it after parsing would silently clobber --no-trmc.) *)
  if Sys.getenv_opt "MARCH_TRMC" <> None then March_tir.Trmc.enabled := true;
  Arg.parse specs (fun f -> files := f :: !files) "Usage: march [options] [file.march]";
  (* --target js implies --compile (skip JIT, emit .mjs) *)
  if !target_str = "js" || !target_str = "javascript" then do_compile := true;
  (* Propagate --pmap-threshold to the interpreter (codegen reads it via
     emit_module's ~pmap_threshold argument below). *)
  March_eval.Eval.pmap_threshold_value := !pmap_threshold;
  (* --emit-core-ast takes its target file as its own flag argument (not a
     positional file), so route it into the normal [f] :: compile dispatch
     below rather than falling through to the REPL branch. *)
  (match !emit_core_ast_file with
   | Some f when !files = [] -> files := [f]
   | Some _ ->
     Printf.eprintf "march: --emit-core-ast takes exactly one file (its own argument); do not also pass a positional file\n";
     exit 1
   | None -> ());
  match !files with
  | []  ->
    let runtime_so = ensure_runtime_so () in
    let jit_ctx = March_jit.Repl_jit.create ~runtime_so () in
    Fun.protect
      ~finally:(fun () -> March_jit.Repl_jit.cleanup jit_ctx)
      (fun () ->
        March_repl.Repl.run ~stdlib_decls:(load_stdlib ()) ~jit_ctx:(Some jit_ctx) ())
  | [f] -> compile f
  | _   -> Printf.eprintf "Usage: march [options] [file.march]\n"; exit 1
