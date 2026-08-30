(** March tree-walking interpreter.

    Evaluates a desugared [Ast.module_] directly, without any prior type
    information.  Useful for quick prototyping, REPL experimentation, and as
    a reference semantics for the compiler back-end.

    Design notes:
    - Values are OCaml heap objects; no explicit memory management.
    - Environments are association lists; later entries shadow earlier ones.
    - Two-pass module evaluation: pass 1 installs mutable stubs so that
      mutually-recursive top-level functions can reference each other; pass 2
      fills the stubs with real closures.
    - Pattern matching raises [Match_failure] when no branch matches. *)

(* Sections (grep for "§N" to jump):
     §1  Actor runtime
     §2  Tap bus — thread-safe value inspector (Clojure tap> model)
     §3  Exceptions
     §4  Built-in environment
     §5  Phase 1: Monitors, Links, and crash_actor (must precede base_env)
     §6  FFI extern stub table
     §7  FFI Marshal Layer — see specs/plans/2026-06-22-ffi-interpreter-full.md
     §8  Evaluation
     §9  Phase 2/3: Initialize eval_expr_hook for supervisor restarts
     §10  Task builtins
     §11  App / Supervisor machinery
     §12  App / Supervisor machinery
     §13  Module evaluation
     §14  Test runner
     §15  Doctest runner

   The builtin table, the protocol runtimes, the shared runtime state and
   the value/env types live in sibling modules — see eval_builtins.ml,
   eval_net.ml, eval_session.ml, eval_simd.ml, eval_runtime.ml,
   eval_prim.ml and eval_types.ml. *)

open March_ast.Ast

(* Value and environment types moved to eval_types.ml.  Re-exported so
   [Eval.value] / [Eval.env] keep working for existing call sites. *)
include Eval_types

(* Simd 128-bit vector ops and the NativeArray narrow-width (f32/i32/u8)
   helpers moved to eval_simd.ml.  [include] (not [open]) because [base_env]
   calls them unqualified *and* the test suite reaches them through
   [let open March_eval.Eval in ... f32_round]. *)
include Eval_simd

(* Shared runtime state and value rendering ([value_to_string], the vault
   registry) moved to eval_runtime.ml — eval_net.ml needs them and eval.ml
   depends on eval_net.ml, so they may no longer live here. *)
include Eval_runtime

(* Session-typed channel + MPST runtimes moved to eval_session.ml.
   [include] so [base_env] keeps calling [chan_new] / [mpst_send] / … by
   their bare names. *)
include Eval_session

(* CSV reader, HTTP server, WebSocket framing and the non-blocking connection
   multiplexer moved to eval_net.ml.  [include] so [base_env] and the rest of
   eval.ml keep calling [tcp_send_all] / [csv_open_impl] / … by bare name. *)
include Eval_net

(* =================================================================
   §1  Actor runtime
   ================================================================= *)













(** Allocates negative virtual pids to avoid collisions with real actor pids. *)
let dyn_sup_next_vpid  : int ref = ref (-1)

(** Task registry — maps task IDs to their result. *)
type task_entry = {
  te_id               : int;
  mutable te_result   : value option;
  te_thunk            : value;    (** The closure to execute *)
  mutable te_cancelled: bool;     (** True if the task was cancelled before await *)
}

let task_registry : (int, task_entry) Hashtbl.t = Hashtbl.create 16
let next_task_id : int ref = ref 0






(** Doc registry: fully-qualified name → doc string.
    Populated when [eval_decl] encounters a [DFn] with [fn_doc = Some s]. *)
let doc_registry : (string, string) Hashtbl.t = Hashtbl.create 32


(** General-interface method dispatch table — maps (iface_name, method_name,
    type_name) to the concrete method value, so a call to a general (non
    type-dispatched-builtin) interface method routes by the FIRST argument's
    runtime type instead of the last-bound name. Keyed by method too (unlike
    [impl_tbl]'s single (iface,type) slot) so a MULTI-method interface's methods
    don't overwrite each other. [type_name] is the declaring-module-qualified
    identity for a colliding short name, else the bare name (see DImpl eval). *)
let iface_method_tbl : (string * string * string, value) Hashtbl.t = Hashtbl.create 8

(** Interface methods that are dispatched by the argument's type through a
    type-directed builtin ([show], [eq], [compare], [hash], [to_json]) rather
    than by name.

    For these, the DImpl eval must NOT bind the bare method name in the outer
    env: doing so lets the last-registered impl shadow the builtin, so a second
    `derive` of the same interface breaks dispatch for the first type (wrong
    result, or a non-exhaustive-match panic when the wrong impl's clauses run).
    Instead they are registered only in [impl_tbl], keyed by (iface, type), and
    the builtin resolves the correct impl from the value's type at call time.
    A plain (non-self-referential) closure is used so recursive calls in the
    body (e.g. [eq] on nested fields) also route through builtin dispatch.

    [("JsonTo", "to_json")] is included for the same reason: without it, the
    DImpl eval's catch-all branch (`eval_decl env (DFn (fn_def, sp))`) binds
    `to_json` into a SELF-recursive closure (via [eval_decl]'s DFn case),
    so a bare `to_json(...)` call inside one type's derived encoder body —
    emitted by `encoder_for_ty`'s recursive-call fallback for any non-scalar
    field, e.g. a field whose type is another `derive Json` record — calls
    right back into the ENCLOSING type's own encoder instead of dispatching
    by the field VALUE's runtime type. Concretely: `type Inner = { id: Int }`
    nested inside `type Outer = { label: String, inner: Inner }`, both
    `derive Json`, made `to_json(outer_val)` panic with "record has no field
    'label'" — it silently re-entered `Outer`'s own encoder on the `Inner`
    value. `to_json` itself is never bound in the env either way (see the
    [is_json_iface] branch below), so marking it type-dispatched only changes
    which KIND of closure the DImpl eval builds for the impl_tbl entry — from
    self-referential to plain — with no other observable effect. [from_json]
    is deliberately NOT included: unlike `to_json`, there is no value of the
    target type in hand at a `from_json` call site to dispatch on (its
    dispatch is by JSON shape, at the return type, not the argument type) —
    see `specs/2026-07-31-json-from-json-dispatch-design.md`. *)
let is_type_dispatched_method iface meth =
  match iface, meth with
  | "Show", "show" | "Eq", "eq" | "Ord", "compare" | "Hash", "hash"
  | "JsonTo", "to_json" -> true
  | _ -> false

(** Whether [iface] is a built-in interface whose value-level dispatch reads
    [impl_tbl] under the shared (iface, type) key (see [is_type_dispatched_method]).

    Such an interface has exactly ONE dispatch method (Eq→eq, Ord→compare,
    Show→show, Hash→hash), but a user may declare it with the built-in name and
    give it EXTRA methods — e.g. [Eq]'s default [neq], or [Ord]'s [lt]/[gt]/
    [le]/[ge].  Those extra methods must NOT be written into [impl_tbl], or they
    clobber the dispatch method under the same key: the builtin then invokes the
    wrong method and [neq → eq → neq] recurses forever (stack overflow).
    Interfaces excluded here (Json, Drop, user interfaces) have no EXTRA
    method that could collide with a single dispatch slot the way [Eq]'s
    [neq] or [Ord]'s [lt]/[gt] can, so they don't need this exclusivity
    protection — [JsonTo]'s `to_json` is still a genuine
    [is_type_dispatched_method] and still reads/writes its (iface, type)
    [impl_tbl] entry by value (see the `to_json` builtin above); it just
    doesn't need to be excluded from anything here. *)
let is_type_dispatched_iface = function
  | "Show" | "Eq" | "Ord" | "Hash" -> true
  | _ -> false


(** Same-short-name type collision set — the interpreter's counterpart to
    [Collision_set] in lib/tir (native/TIR backend, Task 0 of
    specs/plans/2026-07-20-fqn-impl-dispatch-identity.md). The interpreter
    never lowers to TIR, so this walks the AST directly instead of
    [Tir.type_def]s. Maps a type's bare declared short name -> present iff
    2+ DISTINCT declaring-module-qualified names (e.g. "NA.Thing" and
    "NB.Thing") declare it somewhere in the module being run. A short name
    declared exactly once — by far the common case — must be ABSENT (not
    present with degenerate content): every consumer's gate is "member of
    this table", so the non-colliding path must stay cheap and exact.
    Computed once per [eval_module_env] run, from the FULL AST upfront
    (before any [DType]/[DImpl] is evaluated) since eval order alone can't
    tell a first same-short-name declaration from the only one. *)
let type_collision_set : (string, unit) Hashtbl.t = Hashtbl.create 16

let is_colliding_type_name (short_name : string) : bool =
  Hashtbl.mem type_collision_set short_name

(** (module-prefix, bare ctor name) -> declaring type's SHORT name, populated
    ONLY for a ctor that is BOTH (a) declared PUBLIC by a colliding type (see
    [type_collision_set]) AND (b) shared by name with another PUBLIC
    candidate in that SAME collision group — e.g. "Shared" declared `type`
    (public) by both DcA.Thing and DcB.Thing. Mirrors typecheck.ml's Task-1
    [ctor_names_of]/[ctor_sets_disjoint] double-collision check, at the AST
    level instead of [env.ctors]. A ctor unique to exactly one candidate
    (e.g. "OnlyA", only ever declared by DcA.Thing) is deliberately ABSENT:
    its bare tag alone already disambiguates at the value level, so
    [ECon]/[match_pattern] should leave it bare exactly as before this table
    existed. Keyed by MODULE prefix (not type name) because that's all a
    bare [ECon]/[PatCon] site has at eval time — see
    [effective_module_prefix]; the corresponding type name is looked up here
    so the qualified tag can still embed it (e.g. "DcA.Thing.Shared"),
    matching [register_type_ctors]'s own qualified-tag registration.

    PRIVATE (`ptype`) candidates are EXCLUDED from this table entirely —
    not just from counting towards "shared", but never registered as a
    qualification source even if their own ctor happens to coincide with a
    PUBLIC candidate elsewhere. Found empirically (regression on the full
    suite): stdlib/seq.march and stdlib/file.march each independently
    declare `ptype Seq(a) = Seq(a)` — same short name, same sole ctor name,
    a textbook "double collision" by this table's naive definition — but
    this is a DELIBERATE structural-interop pattern (file.march's own
    comment: redeclaring the shape "avoids dependency" on seq.march), and
    `File.with_lines`'s callback constructs a `File.Seq` value that the
    CALLER then feeds through `Seq.map`/`Seq.to_list` (a DIFFERENT
    module's functions) on purpose — qualifying either side's tag broke
    this cross-module hand-off (`Seq.map`'s own `Seq(...)` pattern no
    longer matched a `File`-qualified tag). A `ptype` is module-internal by
    construction (never nominally identified from outside its own module —
    only used, as here, via ITS SHAPE), so treating two independent
    `ptype` redeclarations as a genuinely ambiguous double-collision is the
    wrong call: only PUBLIC same-short-name types (the plan's actual target
    — two types each `impl`-ing the same interface) get qualified.

    A SECOND filter, found via the SAME full-suite regression sweep: a
    short name must ALSO have at least one `impl` block somewhere in the
    program (any interface, any candidate) to participate — see
    [compute_type_collision_set]'s [types_with_any_impl]. `bin/main.exe`
    (the real compiler entry, used by [test_codegen.ml]'s
    interp/compiled-parity tests) auto-loads a broad stdlib prelude
    regardless of what the user's own program needs, so a user type's bare
    short name routinely coincides with an UNRELATED stdlib type's name by
    pure accident — e.g. an MPST test's own marker `type Server = Server`
    (a multiparty-session-types ROLE token, zero impls, never dispatched
    through any interface) collided with `stdlib/http_server.march`'s
    unrelated, also-public `type Server = Server(...)` purely by name.
    MPST's own runtime resolves role names by reading a [VCon]'s tag as a
    raw string key ("has no channel to `Server`") — qualifying it broke
    that lookup, even though NOTHING about MPST roles is genuinely
    coherence-ambiguous (no interface, no dispatch). Requiring an `impl`
    scopes qualification to the plan's actual target — two same-short-name
    types that are BOTH the subject of at least one `impl` block, the
    shape that creates observable dispatch ambiguity in the first place —
    while excluding plain marker/sentinel types that merely happen to
    share a common name with something elsewhere in the (often much
    larger, auto-loaded) combined program. *)
let colliding_ctor_type_by_module : (string * string, string) Hashtbl.t =
  Hashtbl.create 16

(** [Some short_type_name] iff [ctor_name] referenced bare from module
    [module_prefix] needs collision qualification — see
    [colliding_ctor_type_by_module]. *)
let colliding_shared_ctor_type (module_prefix : string) (ctor_name : string)
  : string option =
  Hashtbl.find_opt colliding_ctor_type_by_module (module_prefix, ctor_name)

(** Populate [type_collision_set] AND [colliding_ctor_type_by_module] by
    walking [decls] recursively (descending into [DMod], accumulating a
    "Sub.Sub2." prefix the same way [module_stack]/[current_doc_prefix] do
    at eval time — see the [DMod] arm of [eval_decl] below), collecting
    every [DType]/[DAlwaysLinearType]'s declaring-module-qualified name,
    visibility, AND (for [TDVariant]s) its constructor names.
    [type_collision_set] itself is computed from EVERY candidate regardless
    of visibility — unchanged from the parent FQN plan's own Task 5, whose
    existing consumers ([ctor_qualified_type_tbl]/[dispatch_type_name_of_value],
    general-interface dispatch) already rely on that broader membership and
    are NOT touched by this task. Only [colliding_ctor_type_by_module] (this
    task's new, more invasive, VCon-tag-identity-affecting table) applies
    the additional public-only filter — see its own doc comment. *)
let compute_type_collision_set (decls : decl list) : unit =
  Hashtbl.reset type_collision_set;
  Hashtbl.reset colliding_ctor_type_by_module;
  (* short type name -> (module_prefix, qualified_name, visibility, ctor_names)
     list, one entry per distinct qualified declaration seen. *)
  let by_short : (string, (string * string * visibility * string list) list) Hashtbl.t =
    Hashtbl.create 16 in
  (* Short type names with at least one `impl` block anywhere in the
     program (any interface, any candidate) — see [colliding_ctor_type_by_module]'s
     doc comment for why this second filter exists. *)
  let types_with_any_impl : (string, unit) Hashtbl.t = Hashtbl.create 16 in
  (* The compiler's own always-injected prelude ADTs (Option/Result/List —
     see the native mirror [Lower.builtin_type_defs]) are seeded as a
     bare-prefix ("") PUBLIC candidate up front, and unconditionally marked
     impl-bearing. Unlike the Seq/Server false positives the impl-presence
     filter above exists to exclude (a deliberate same-shape structural
     handoff, or a raw-string-key marker type), a user type reusing one of
     these three exact bare names is NEVER a legitimate alias of the
     interpreter's own builtin ctor table (registered separately, never as
     a [DType] AST node, so it was otherwise invisible to this walk) — it is
     always a genuine nominal collision that must be qualified. Without this
     seed, a no-`impl` user `type Result = Ok(...) | Err(...)` collided with
     the builtin Result/Ok/Err with no qualification ever applied on either
     backend (P0: builtin-ctor-collision-gap, 2026-07-22). *)
  List.iter (fun (name, ctors) ->
      Hashtbl.replace by_short name [("", name, Public, ctors)];
      Hashtbl.replace types_with_any_impl name ()
    ) ["Option", ["None"; "Some"]; "Result", ["Ok"; "Err"]; "List", ["Nil"; "Cons"]];
  let add_qualified prefix qualified vis ctor_names =
    let short = match String.rindex_opt qualified '.' with
      | None   -> qualified
      | Some i -> String.sub qualified (i + 1) (String.length qualified - i - 1)
    in
    let existing = match Hashtbl.find_opt by_short short with Some l -> l | None -> [] in
    if not (List.exists (fun (_, q, _, _) -> q = qualified) existing) then
      Hashtbl.replace by_short short ((prefix, qualified, vis, ctor_names) :: existing)
  in
  let rec walk prefix ds =
    List.iter (function
        | DType (vis, name, _, type_def, _) | DAlwaysLinearType (vis, name, _, type_def, _) ->
          let ctor_names = match type_def with
            | TDVariant variants -> List.map (fun (v : variant) -> v.var_name.txt) variants
            | _ -> []
          in
          add_qualified prefix (prefix ^ name.txt) vis ctor_names
        | DImpl (idef, _) ->
          let impl_short = match idef.impl_ty with
            | TyCon (n, _) -> n.txt
            | TyVar n      -> n.txt
            | _            -> ""
          in
          if impl_short <> "" then Hashtbl.replace types_with_any_impl impl_short ()
        | DMod (sub, _, inner, _) -> walk (prefix ^ sub.txt ^ ".") inner
        | _ -> ()
      ) ds
  in
  walk "" decls;
  Hashtbl.iter (fun short candidates ->
      if List.length candidates >= 2 then begin
        Hashtbl.replace type_collision_set short ();
        (* Only PUBLIC candidates of a short name that ALSO has at least one
           `impl` block anywhere participate in shared-ctor qualification
           (see [colliding_ctor_type_by_module]'s doc comment for why —
           excludes both the stdlib's own `ptype Seq(a) = Seq(a)` duplicate
           in seq.march/file.march, and impl-less marker types like MPST's
           `type Server = Server` colliding by pure accident with
           stdlib/http_server.march's unrelated `Server`). *)
        let public_candidates =
          if not (Hashtbl.mem types_with_any_impl short) then []
          else List.filter (fun (_, _, vis, _) -> vis = Public) candidates
        in
        (* How many DISTINCT public candidates in this group declare each
           ctor name (dedup within one candidate's own list first, so a
           type that somehow lists a ctor twice doesn't inflate its own
           count). *)
        let ctor_counts : (string, int) Hashtbl.t = Hashtbl.create 8 in
        List.iter (fun (_, _, _, ctors) ->
            List.iter (fun c ->
                let n = match Hashtbl.find_opt ctor_counts c with Some n -> n | None -> 0 in
                Hashtbl.replace ctor_counts c (n + 1)
              ) (List.sort_uniq String.compare ctors)
          ) public_candidates;
        List.iter (fun (prefix, _, _, ctors) ->
            List.iter (fun c ->
                match Hashtbl.find_opt ctor_counts c with
                | Some n when n >= 2 ->
                  Hashtbl.replace colliding_ctor_type_by_module (prefix, c) short
                | _ -> ()
              ) ctors
          ) public_candidates
      end
    ) by_short



(** Names of `resource`-declared FFI types (e.g. `resource Db`), populated
    alongside [ffi_type_decl_tbl] when [eval_decl] processes [DType] nodes.

    The parser desugars `resource Foo` to [DType (Public, "Foo", [], TDVariant [], _)]
    (see lib/parser/parser.mly, resource_decl) — an empty-constructor variant.
    Every *other* grammar production for a type declaration requires
    [separated_nonempty_list(PIPE, variant)], i.e. at least one constructor,
    so [TDVariant []] is a structurally reliable signal that a [DType] came
    from a `resource` declaration and not a genuine user type. We use that
    signal here (rather than adding a new AST decl constructor, which would
    force exhaustiveness updates across ~90 unrelated match sites in
    typecheck/lower/borrow/format for no behavioral gain) to mark the name as
    opaque: the FFI marshal layer must treat it as a raw handle ([VResource])
    instead of trying to interpret it as a zero-case variant discriminant. *)
let ffi_resource_tbl : (string, unit) Hashtbl.t = Hashtbl.create 16


(** Global module member registry — maps "ModName.member" to its value.
    Populated as [DMod] nodes are evaluated.  Used by [EField] qualified
    lookup so that cross-module references work regardless of load order:
    a closure captured in Router can call UsersController.index even if
    UsersController hadn't been evaluated yet when Router was defined,
    because the lookup happens at *call time* against this registry.
    Reset at the start of each [eval_module_env] run. *)
let module_registry : (string, value) Hashtbl.t = Hashtbl.create 64

(** Callback set by the driver (main.ml / REPL) to load a stdlib module
    on demand.  When set, [ensure_module_loaded] calls this to parse,
    desugar, typecheck, and eval the module, populating [module_registry]. *)
let module_loader : (string -> unit) option ref = ref None

(** Ensure a stdlib module has been loaded into [module_registry].
    Idempotent — checks a sentinel key before invoking [module_loader]. *)
let ensure_module_loaded (name : string) : unit =
  let sentinel = name ^ ".__loaded__" in
  if not (Hashtbl.mem module_registry sentinel) then begin
    Hashtbl.replace module_registry sentinel VUnit;
    match !module_loader with
    | Some loader -> (try loader name with _ -> ())
    | None -> ()
  end

(** Module stack for tracking the current module path during eval.
    Updated when entering/leaving [DMod]. Top of stack = innermost module. *)
let module_stack : string list ref = ref []

let current_doc_prefix () =
  match !module_stack with
  | []    -> ""
  | parts -> String.concat "." (List.rev parts) ^ "."

(** Dynamically-scoped override for [effective_module_prefix]: the lexical
    declaring-module prefix captured on the currently-executing closure's
    [VClosure] (its 4th field) when it was CONSTRUCTED, active only while
    [apply_inner]'s [VClosure] arm is evaluating that closure's body.
    [None] outside any active closure application (falls back to the real,
    eager-decl-processing [current_doc_prefix]). [apply_inner] saves the
    prior value, installs the callee's captured prefix, evaluates the body,
    and restores the prior value afterward (exception-safe), so nested
    closure calls correctly layer — an inner closure's own prefix is in
    effect only for the duration of its own body, and the caller's prefix
    (or [None]) is back in effect once it returns. See [VClosure]'s doc
    comment for why this exists (module_stack alone is stale by the time a
    deferred closure body actually runs). *)
let closure_prefix_override : string option ref = ref None

(** The module-qualifying prefix to use at THIS evaluation point for
    constructor-collision qualification: the active closure's own captured
    lexical prefix if we're currently inside one ([closure_prefix_override]),
    else the real, eager-decl-processing [current_doc_prefix]. Consulted by
    [ECon] evaluation, [match_pattern]'s [PatCon] arm, and every [VClosure]
    construction site (to capture the right prefix at closure-creation
    time — itself correct whether that creation is eager, e.g. top-level
    [DFn]/[DImpl] processing, or happens while ALREADY inside another
    closure's body, e.g. a lambda literal written inside a function). *)
let effective_module_prefix () =
  match !closure_prefix_override with
  | Some p -> p
  | None -> current_doc_prefix ()

(* =================================================================
   §2  Tap bus — thread-safe value inspector (Clojure tap> model)
   ================================================================= *)



(** Drain all pending tap values from the queue and return them in FIFO order.
    Thread-safe.  Called by the REPL after each expression evaluation. *)
let tap_drain () : value list =
  Mutex.lock tap_mutex;
  let acc = ref [] in
  while not (Queue.is_empty tap_queue) do
    acc := Queue.pop tap_queue :: !acc
  done;
  Mutex.unlock tap_mutex;
  List.rev !acc

let lookup_doc (key : string) : string option =
  Hashtbl.find_opt doc_registry key





(* [shutdown_requested] moved to eval_prim.ml — the HTTP event loop in
   eval_net.ml polls it, and eval.ml will depend on Eval_net.  Aliasing a
   [ref] shares the same mutable cell, so every existing assignment and read
   (here and in bin/main.ml via [Eval.shutdown_requested]) is unchanged. *)
let shutdown_requested = Eval_prim.shutdown_requested

(* ---- Signal.watch interpreter state ─────────────────────────────────
   One deferred watcher per signal, indexed by a stable code 0-4
   (Term, Int, Hup, Usr1, Usr2 — see stdlib/signal.march, which translates
   the [Sig] enum to these codes before calling [signal_watch]).  The OS
   handler [handle_os_signal] runs at OCaml's safe points and only flips the
   [signal_pending] flag; the scheduler drain (see [run_scheduler]) applies
   the March closure on a normal green-thread stack.  A watcher on Term/Int
   suppresses the default graceful-shutdown for the first delivery; a second
   delivery escapes to shutdown (the escape hatch). *)
let signal_watchers : value option array = Array.make 5 None
let signal_pending  : bool array          = Array.make 5 false
let signal_seen     : bool array          = Array.make 5 false

(** Map a stable signal code (0-4) to its OCaml OS signal number. *)
let signal_os_of_code = function
  | 0 -> Sys.sigterm | 1 -> Sys.sigint | 2 -> Sys.sighup
  | 3 -> Sys.sigusr1 | 4 -> Sys.sigusr2
  | _ -> invalid_arg "signal_os_of_code"

(** Map an incoming OS signal number to our stable code, or [-1] if unknown. *)
let signal_code_of_os n =
  if n = Sys.sigterm then 0 else if n = Sys.sigint then 1
  else if n = Sys.sighup then 2 else if n = Sys.sigusr1 then 3
  else if n = Sys.sigusr2 then 4 else -1

(** OS signal handler.  Async-context-safe: only writes flag arrays (OCaml
    defers delivery to safe points, so no true async re-entrancy).  Never
    allocates or runs March code here — the drain does that. *)
let handle_os_signal (osnum : int) : unit =
  let code = signal_code_of_os osnum in
  if code >= 0 then
    match signal_watchers.(code) with
    | Some _ ->
      (* Watched: defer to the scheduler drain.  Term/Int escape to shutdown
         only on a second delivery. *)
      if signal_seen.(code) && (code = 0 || code = 1) then
        shutdown_requested := true;
      signal_pending.(code) <- true;
      signal_seen.(code)    <- true
    | None ->
      (* Unwatched: Term/Int fall back to graceful shutdown.  Hup/Usr1/Usr2
         handlers are only installed while watched (removed on unwatch), so
         this branch runs for Term/Int in practice. *)
      if code = 0 || code = 1 then shutdown_requested := true

(* ---- Logger global state ───────────────────────────────────────────
   Logger v2 keeps richer field values (Int, Float, Bool, Atom, String,
   Null) so structured formatters (JSON, logfmt) can preserve types
   instead of stringifying everything.  The v1 flat (string * string)
   context stays accessible via shim — v1 `with_context` writes a
   `LogStr` field; v1 `get_context` lossily reads back as strings. *)


(* Sequential-fallback cutoff for List.pmap/pfilter/preduce, set by
   bin/main.ml from --pmap-threshold (default 1024). *)
let pmap_threshold_value : int ref = ref 1024






(* Moved to eval_prim.ml; re-exported here so [Eval.http_fetch_hook] keeps
   working for existing call sites (the js_of_ocaml build installs it).
   Aliasing a [ref] shares the same mutable cell. *)
let http_fetch_hook = Eval_prim.http_fetch_hook




(** Ordered list of pids spawned by [spawn_from_spec], in start order.
    Shutdown iterates this in reverse (last started = first stopped). *)
let app_spawn_order : int list ref = ref []





(** [ring_drop_newest r n] drops the n most-recent entries (logical indices 0..n-1).
    Used by replay to discard frames newer than the cursor.
    Clamps: if n >= rb_size, clears the buffer. *)
let ring_drop_newest r n =
  if n <= 0 then ()
  else if n >= r.rb_size then (r.rb_head <- 0; r.rb_size <- 0)
  else begin
    r.rb_head <- ((r.rb_head - n) + r.rb_cap * 2) mod r.rb_cap;
    r.rb_size <- r.rb_size - n
  end


type actor_inst_snapshot = {
  ais_name  : string;
  ais_state : value;
  ais_alive : bool;
  ais_terminal_reason : monitor_down_reason;
}

type actor_state_snapshot = {
  ass_defs      : (string * (actor_def * env ref)) list;
  ass_instances : (int * actor_inst_snapshot) list;
  ass_next_pid  : int;
}

type trace_frame = {
  tf_expr   : expr;
  tf_env    : env;
  tf_result : value option;
  tf_exn    : string option;
  tf_actor  : actor_state_snapshot;
  tf_span   : span;
  tf_depth  : int;
}

type actor_msg_event = {
  ame_pid          : int;
  ame_actor_name   : string;
  ame_msg          : value;
  ame_state_before : value;
  ame_state_after  : value option;   (* None if handler raised *)
  ame_frame_idx    : int;            (* trace ring index at time of dispatch *)
}

(** Stepping mode for an editor-driven (DAP) debug session.
    The [int] payloads record the call depth captured when the step was
    requested, so step-over/step-out know which frame to return to. *)
type step_mode =
  | Run                  (* continue until a breakpoint is hit *)
  | Pause                (* stop at the next evaluated expression *)
  | StepInto             (* stop at the next source line, descending into calls *)
  | StepOver of int      (* stop at the next line at depth <= captured depth *)
  | StepOut  of int      (* stop once depth < captured depth *)

type debug_ctx = {
  dc_trace         : trace_frame ring;
  mutable dc_pos   : int;       (* navigation cursor; 0 = most recent *)
  mutable dc_enabled : bool;
  mutable dc_depth : int;       (* current call depth *)
  mutable dc_on_dbg : (env -> unit) option;
  mutable dc_actor_log : actor_msg_event list;  (* per-actor message history *)
  (* ---- Editor-driven stepping (DAP). Unused by the terminal REPL debugger. ---- *)
  mutable dc_breakpoints : (string * int, unit) Hashtbl.t;
  (* Active breakpoints keyed by (file, 1-indexed line). *)
  mutable dc_step : step_mode;
  (* Current stepping intent; consulted on every evaluated expression. *)
  mutable dc_on_pause : (env -> span -> unit) option;
  (* Called when execution should stop; blocks the eval thread until the
     controller assigns the next [dc_step] and resumes. None = no pausing. *)
  mutable dc_last_line : (string * int) option;
  (* Last (file,line) we stopped on — suppresses re-stopping on the same
     source line as evaluation walks its sub-expressions. *)
}

(** Snapshot the current actor state. Deep-copies mutable fields. *)
let snapshot_actors () : actor_state_snapshot =
  let defs = Hashtbl.fold (fun name (def, env_r) acc ->
      (name, (def, ref !env_r)) :: acc
    ) actor_defs_tbl [] in
  let instances = Hashtbl.fold (fun pid (inst : actor_inst) acc ->
      let snap = { ais_name  = inst.ai_name;
                   ais_state = inst.ai_state;
                   ais_alive = inst.ai_alive;
                   ais_terminal_reason = inst.ai_terminal_reason } in
      (pid, snap) :: acc
    ) actor_registry [] in
  { ass_defs = defs; ass_instances = instances; ass_next_pid = !next_pid }

(** Restore actor state from a snapshot. *)
let restore_actors (snap : actor_state_snapshot) : unit =
  Hashtbl.reset actor_defs_tbl;
  List.iter (fun (name, (def, env_r)) ->
      Hashtbl.add actor_defs_tbl name (def, env_r)
    ) snap.ass_defs;
  Hashtbl.reset actor_registry;
  List.iter (fun (pid, s) ->
      match Hashtbl.find_opt actor_defs_tbl s.ais_name with
      | None -> ()
      | Some (def, env_r) ->
        let inst = { ai_name     = s.ais_name;
                     ai_def      = def;
                     ai_env_ref  = env_r;
                     ai_state    = s.ais_state;
                     ai_alive    = s.ais_alive;
                     ai_terminal_reason = s.ais_terminal_reason;
                     ai_monitors = [];
                     ai_mailbox  = Queue.create ();
                     ai_supervisor = None;
                     ai_restart_count = [];
                     ai_epoch = 0;
                     ai_resources = [];
                     ai_linear_values = [];
                     ai_mbox_limit = 0;
                     ai_mbox_policy = 0 } in
        Hashtbl.add actor_registry pid inst
    ) snap.ass_instances;
  next_pid := snap.ass_next_pid

(** Module-level debug context. None = no overhead. *)
let debug_ctx : debug_ctx option ref = ref None

(* =================================================================
   §3  Exceptions
   ================================================================= *)


(* [Eval_error] moved to eval_prim.ml; rebound here so [Eval.Eval_error]
   stays matchable at existing call sites. *)
exception Eval_error = Eval_prim.Eval_error

(** Bounded consolation diagnostic for task 7 of the 2026-08-03
    refinement-followups-seven plan (see
    specs/progress/2026-08-0*-interface-method-names-qualifiability-disposition.md).

    Interface method names are not module-qualifiable: `Foo.greet(1)` never
    resolves, even when `Foo` declares `interface Greeter do fn greet : ... end`
    and greet is dispatched via `impl`, because dispatch works through the
    unqualified name, not module-member lookup — see [lookup]'s
    `strip_lookup` fallback below, whose terminal case raises exactly
    `Eval_error ("unbound variable: " ^ name)` for this shape. Making that
    resolve is a dispatch-side redesign (see the todo this task closed for
    why the naive fix — teaching [Desugar.collect_direct_names] about method
    names — was measured to regress working code and silently re-vacuate the
    accept/t126 and accept/t127 corpus witnesses). This function does NOT
    change resolution: it only recognizes the exact failure shape after the
    fact and appends a note suggesting the working spelling. Called from
    [bin/main.ml]'s [Eval_error] handler, which has no other access to the
    desugared module tree once evaluation has already unwound.

    [module_ast] is the desugared top-level module. On a dotted unbound-name
    failure `"unbound variable: Mod.method"`, this walks every module
    (top-level and nested [DMod]) whose own name matches the last path
    segment before [method] and checks whether it declares an interface with
    a method by that name. If so, returns a note; otherwise [None] — including
    for a genuinely unbound name, which must fall through unchanged. *)
let interface_method_hint (module_ast : module_) (msg : string) : string option =
  let prefix = "unbound variable: " in
  let plen = String.length prefix in
  if String.length msg <= plen || String.sub msg 0 plen <> prefix then None
  else
    let name = String.sub msg plen (String.length msg - plen) in
    match String.rindex_opt name '.' with
    | None -> None
    | Some i ->
      let mod_path = String.sub name 0 i in
      let member = String.sub name (i + 1) (String.length name - i - 1) in
      (* Last path segment, matching [lookup]'s own [strip_lookup] fallback
         which progressively strips leading module components. *)
      let last_segment =
        match String.rindex_opt mod_path '.' with
        | None -> mod_path
        | Some j -> String.sub mod_path (j + 1) (String.length mod_path - j - 1)
      in
      let find_in_decls decls =
        List.find_map
          (function
            | DInterface (idef, _) ->
              if List.exists
                   (fun (m : method_decl) -> m.md_name.txt = member)
                   idef.iface_methods
              then Some idef.iface_name.txt
              else None
            | _ -> None)
          decls
      in
      let rec search this_name decls =
        let here =
          if this_name = last_segment || this_name = mod_path then
            match find_in_decls decls with
            | Some iface_name -> Some (this_name, iface_name)
            | None -> None
          else None
        in
        match here with
        | Some _ -> here
        | None ->
          List.find_map
            (function
              | DMod (nested_name, _, inner, _) -> search nested_name.txt inner
              | _ -> None)
            decls
      in
      (match search module_ast.mod_name.txt module_ast.mod_decls with
       | None -> None
       | Some (found_mod, iface_name) ->
         Some (Printf.sprintf
                 "\nnote: `%s` is a method of interface `%s` declared in module `%s` — interface methods aren't module-qualifiable (dispatch resolves the bare name, not the qualified one). Call it as `%s(...)` instead of `%s(...)`."
                 member iface_name found_mod member name))


(** Raised when an actor/task's reduction budget is exhausted. *)
exception Yield


type march_frame = {
  mf_name : string;
  mf_file : string;
  mf_line : int;
}

(** Per-evaluation March call stack.  Single-threaded (cooperative scheduling
    via Yield, no true parallelism during evaluation), so a plain ref is safe. *)
let march_stack : march_frame list ref = ref []

let march_stack_push (name : string) (sp : span) : unit =
  march_stack := { mf_name = name; mf_file = sp.file; mf_line = sp.start_line }
                 :: !march_stack

let march_stack_pop () : unit =
  match !march_stack with _ :: rest -> march_stack := rest | [] -> ()

let get_march_stack () : march_frame list = !march_stack

let clear_march_stack () : unit = march_stack := []

(** Global reduction context — None means reduction counting is disabled. *)
let reduction_ctx : March_scheduler.Scheduler.reduction_ctx option ref = ref None

(** Enable/disable reduction counting for the evaluator. *)
let set_reduction_counting (enabled : bool) : unit =
  if enabled then
    reduction_ctx := Some (March_scheduler.Scheduler.create_reduction_ctx ())
  else
    reduction_ctx := None

(** Reset the reduction budget (call between scheduling quanta). *)
let reset_reduction_budget () : unit =
  match !reduction_ctx with
  | Some ctx -> March_scheduler.Scheduler.reset_budget ctx
  | None -> ()

(** Check the reduction counter and raise Yield if exhausted.
    Called at every yield point: EApp, EMatch, ESend. *)
let check_reductions () : unit =
  match !reduction_ctx with
  | Some ctx ->
    if March_scheduler.Scheduler.tick ctx then
      raise Yield
  | None -> ()

(* Moved to eval_prim.ml; re-exported so [Eval.eval_error] keeps working. *)
let eval_error = Eval_prim.eval_error





(** Try to match [v] against [pat].
    Returns [Some bindings] on success, [None] on failure.
    Bindings are accumulated in reverse order (callers reverse or prepend).

    This is the operational semantics of Core March's pattern-matching
    relation `match(Pat…)` — see `specs/lang/core-march.md` §4.3. Each arm
    below is annotated with the spec rule it implements. *)
let rec match_pattern (v : value) (pat : pattern) : (string * value) list option =
  match pat, v with
  | PatWild _, _ -> Some []  (* match(PatWild) — §4.3 *)

  | PatVar n, _ -> Some [(n.txt, v)]  (* match(PatVar) — §4.3 *)

  | PatLit (LitInt i, _),    VInt j    when i = j   -> Some []  (* match(PatLit) — §4.3 *)
  | PatLit (LitFloat f, _),  VFloat g  when f = g   -> Some []  (* match(PatLit) — §4.3 *)
  | PatLit (LitString s, _), VString t when s = t   -> Some []  (* match(PatLit) — §4.3 *)
  | PatLit (LitBool b, _),   VBool c   when b = c   -> Some []  (* match(PatLit) — §4.3 *)
  | PatLit (LitAtom a, _),   VAtom b   when a = b   -> Some []  (* match(PatLit) — §4.3 *)
  | PatLit _,                _                       -> None    (* match(PatLit) — §4.3 *)

  | PatCon (n, pats), VCon (tag, args) ->  (* match(PatCon) — §4.3 *)
    (* Strip any type qualifier from the pattern name before comparing so that
       both Result.Ok(x) and Ok(x) match VCon("Ok", …) at runtime. *)
    let bare_pat = match String.rindex_opt n.txt '.' with
      | Some i -> String.sub n.txt (i + 1) (String.length n.txt - i - 1)
      | None   -> n.txt
    in
    (* Apply the SAME collision qualification [ECon] evaluation applies at
       construction time (see [effective_module_prefix] and
       [colliding_ctor_type_by_module]'s doc comments), so a bare pattern
       written inside a colliding type's OWN declaring module — e.g. a
       `Shared` arm inside DcA's own `impl Speak(Thing)` body — compares
       correctly against a `VCon("DcA.Thing.Shared", …)` value, while a
       non-colliding bare pattern anywhere else stays byte-identical to
       before this table existed.

       A DOTTED written name is NOT necessarily already resolved: the
       documented, spec'd qualified-pattern syntax (specs/lang/pattern-
       matching.md "Qualified Constructor Patterns", `Http.Ok(resp)` /
       `Json.Ok(data)`) writes a MODULE prefix, not the declaring TYPE's own
       name — construction-side qualification produces a 3-segment
       "module.Type.Ctor" tag (see the `Some short_type_name` arm just
       below), so a 2-segment "module.Ctor" pattern can never equal it via a
       bare string comparison (P0: builtin-ctor-collision-gap, 2026-07-22).
       Try the pattern's own qualifier as a MODULE prefix first (mirrors
       construction exactly); only fall back to the old "already a plain
       Type.Ctor reference, no such module" behavior when that lookup
       misses — e.g. `List.Cons` (List is a type, not a module: no
       [colliding_shared_ctor_type] entry keyed by prefix "List." exists)
       stays byte-identical. *)
    let qualified_pat =
      match String.rindex_opt n.txt '.' with
      | Some i ->
        let qual = String.sub n.txt 0 i ^ "." in
        (match colliding_shared_ctor_type qual bare_pat with
         | Some short_type_name -> qual ^ short_type_name ^ "." ^ bare_pat
         | None -> bare_pat)
      | None ->
        let prefix = effective_module_prefix () in
        match colliding_shared_ctor_type prefix bare_pat with
        | Some short_type_name -> prefix ^ short_type_name ^ "." ^ bare_pat
        | None -> bare_pat
    in
    if qualified_pat <> tag then None
    else if List.length pats <> List.length args then None
    else match_list pats args

  | PatCon _, _ -> None  (* match(PatCon) — §4.3 *)

  | PatAtom (a, pats, _), VAtom b when a = b && pats = [] -> Some []  (* match(PatAtom) nullary — §4.3 *)
  | PatAtom (a, pats, _), VCon (tag, args) when a = tag ->             (* match(PatAtom) payload — §4.3 *)
    if List.length pats <> List.length args then None
    else match_list pats args
  | PatAtom _, _ -> None  (* match(PatAtom) — §4.3 *)

  | PatTuple ([], _), VUnit -> Some []  (* match(PatTuple) k=0 alias to VUnit — §4.3 *)
  | PatTuple (pats, _), VTuple vs ->    (* match(PatTuple) — §4.3 *)
    if List.length pats <> List.length vs then None
    else match_list pats vs

  | PatTuple _, _ -> None  (* match(PatTuple) — §4.3 *)

  | PatRecord (fields, _), VRecord record_fields ->  (* match(PatRecord) — §4.3 *)
    let bindings = List.fold_left (fun acc (fname, fpat) ->
        match acc with
        | None -> None
        | Some bs ->
          match List.assoc_opt fname.txt record_fields with
          | None -> None
          | Some fv ->
            match match_pattern fv fpat with
            | None -> None
            | Some new_bs -> Some (new_bs @ bs)
      ) (Some []) fields in
    bindings

  | PatRecord _, _ -> None  (* match(PatRecord) — §4.3 *)

  | PatAs (inner, alias, _), _ ->  (* match(PatAs) — §4.3 *)
    (match match_pattern v inner with
     | None -> None
     | Some bs -> Some ((alias.txt, v) :: bs))

  | PatOr (alts, _), _ ->  (* match(PatOr) — §4.3, first matching alternative wins *)
    let rec try_alts = function
      | [] -> None
      | p :: rest ->
        (match match_pattern v p with
         | Some bs -> Some bs
         | None -> try_alts rest)
    in
    try_alts alts

(** Match a list of patterns against a list of values. *)
and match_list (pats : pattern list) (vs : value list) : (string * value) list option =
  List.fold_left2 (fun acc p v ->
      match acc with
      | None -> None
      | Some bs ->
        match match_pattern v p with
        | None -> None
        | Some new_bs -> Some (new_bs @ bs)
    ) (Some []) pats vs

(* =================================================================
   §4  Built-in environment
   ================================================================= *)

let arith_int op name = VBuiltin (name, function
    | [VInt a; VInt b] -> VInt (op a b)
    | _ -> eval_error "builtin %s: expected two ints" name)



(** Constructor -> declaring-module-QUALIFIED type name, populated ONLY for
    a ctor whose type's short name collides (see [type_collision_set]).
    Deliberately a SEPARATE table from [ctor_type_tbl] (which stays bare
    for every ctor, colliding or not) rather than qualifying [ctor_type_tbl]
    itself in place: [ctor_type_tbl]/[type_name_of_value] are also consulted
    by [impl_tbl] (Eq/Ord/Show/Hash/Json/`own` dispatch), [ffi_type_decl_tbl]
    (actor message tag-index routing) and [record_type_tbl] (Json
    record-decode) — none of which key their OWN tables by the qualified
    name, so qualifying the shared bare lookup in place would silently break
    those unrelated round-trips for a colliding type. Keeping this table
    separate and additive-only means a non-colliding program is byte-for-byte
    unaffected, and [iface_method_tbl] (general-interface dispatch, the only
    consumer of [dispatch_type_name_of_value] below) is the only thing that
    sees the qualified identity. *)
let ctor_qualified_type_tbl : (string, string) Hashtbl.t = Hashtbl.create 8

(** Like [type_name_of_value], but a colliding [VCon]'s type resolves to its
    declaring-module-qualified name (e.g. "NA.Thing") instead of the bare
    short name, so a general-interface method call routes through
    [iface_method_tbl] to the actual argument's impl rather than whichever
    same-short-name type's impl happened to register last. Non-colliding
    values (the common case) fall back to [type_name_of_value] unchanged. *)
let dispatch_type_name_of_value = function
  | VCon (tag, _) as v ->
    (match Hashtbl.find_opt ctor_qualified_type_tbl tag with
     | Some qualified -> Some qualified
     | None -> type_name_of_value v)
  | v -> type_name_of_value v

(** Register every constructor of a [TDVariant] type in [ctor_type_tbl]
    (bare, as always) and, when [name_txt]'s short name collides (per
    [type_collision_set]), ALSO in [ctor_qualified_type_tbl] under the
    current [module_stack]-derived qualified name. Shared by every [DType]/
    [DAlwaysLinearType] eval site so the qualification rule can't drift
    between them. *)
let register_type_ctors (name_txt : string) (variants : variant list) : unit =
  List.iter (fun (v : variant) ->
      Hashtbl.replace ctor_type_tbl v.var_name.txt name_txt;
      if is_colliding_type_name name_txt then begin
        let module_prefix = current_doc_prefix () in
        let qualified_type = module_prefix ^ name_txt in
        Hashtbl.replace ctor_qualified_type_tbl v.var_name.txt qualified_type;
        (* When this specific ctor is ALSO collision-shared (see
           [colliding_ctor_type_by_module]), [ECon] construction now
           produces a VCon carrying the fully-qualified tag
           "<module>.<type>.<ctor>" instead of the bare ctor name — register
           that exact tag too, in BOTH tables, so [type_name_of_value] /
           [dispatch_type_name_of_value] can still resolve a value carrying
           it (general-interface dispatch, Eq/Ord/Show/Hash, JSON, …). The
           bare-keyed entries above are left untouched: a NON-shared ctor of
           this same colliding type (e.g. "OnlyA") stays bare at
           construction time, so its bare registration is still what gets
           looked up. *)
        if colliding_shared_ctor_type module_prefix v.var_name.txt <> None then begin
          let qualified_tag = qualified_type ^ "." ^ v.var_name.txt in
          Hashtbl.replace ctor_type_tbl qualified_tag name_txt;
          Hashtbl.replace ctor_qualified_type_tbl qualified_tag qualified_type
        end
      end
    ) variants

(* Moved to eval_prim.ml; re-exported here (same mutable cell). *)
let iface_dispatch_hook = Eval_prim.iface_dispatch_hook


(** Pretty-print a value with indented multi-line layout when the flat
    representation exceeds [width] characters.
    Truncates collections longer than [max_items] with "... (N more)". *)
let value_to_string_pretty ?(width=80) ?(max_items=50) ?(max_depth=6) v =
  let flat = value_to_string v in
  if String.length flat <= width then flat
  else
    let indent n = String.make n ' ' in
    let truncate_list items pp_item depth =
      let n = List.length items in
      if n <= max_items then
        List.map (pp_item depth) items
      else
        let shown = List.filteri (fun i _ -> i < max_items) items in
        List.map (pp_item depth) shown
        @ [Printf.sprintf "... (%d more)" (n - max_items)]
    in
    let truncate_fields fields pp_field depth =
      let n = List.length fields in
      if n <= max_items then
        List.map (pp_field depth) fields
      else
        let shown = List.filteri (fun i _ -> i < max_items) fields in
        List.map (pp_field depth) shown
        @ [Printf.sprintf "... (%d more fields)" (n - max_items)]
    in
    let rec pp depth v =
      if depth >= max_depth then "<...>" else
      let flat_v = value_to_string v in
      if String.length flat_v <= width - depth * 2 then flat_v
      else match v with
      | VRecord fields ->
        let pad = indent (depth * 2 + 2) in
        let close_pad = indent (depth * 2) in
        let strs = truncate_fields fields
          (fun d (k, fv) -> k ^ ": " ^ pp (d + 1) fv) depth in
        "{ " ^ String.concat ("\n" ^ pad ^ ", ") strs
        ^ "\n" ^ close_pad ^ "}"
      | VTuple vs ->
        let pad = indent (depth * 2 + 2) in
        let close_pad = indent (depth * 2) in
        "( " ^ String.concat ("\n" ^ pad ^ ", ") (List.map (pp (depth + 1)) vs)
        ^ "\n" ^ close_pad ^ ")"
      | VCon ("Nil", []) -> "[]"
      | VCon ("Cons", _) as lv when is_list_value lv ->
        let elems = list_elems [] lv in
        let pad = indent (depth * 2 + 2) in
        let close_pad = indent (depth * 2) in
        let strs = truncate_list elems (fun d e -> pp d e) (depth + 1) in
        "[ " ^ String.concat ("\n" ^ pad ^ ", ") strs
        ^ "\n" ^ close_pad ^ "]"
      | VCon (tag, args) when args <> [] ->
        let pad = indent (depth * 2 + 2) in
        let close_pad = indent (depth * 2) in
        display_tag tag ^ "(\n" ^ pad
        ^ String.concat ("\n" ^ pad ^ ", ") (List.map (pp (depth + 1)) args)
        ^ "\n" ^ close_pad ^ ")"
      | _ -> flat_v
    in
    pp 0 v


type actor_info = {
  ai_pid       : int;
  ai_name      : string;
  ai_alive     : bool;
  ai_state_str : string;
  (** Distinct from actor_inst.ai_state which is a [value]. *)
}

let increment_epoch pid =
  match Hashtbl.find_opt actor_registry pid with
  | None -> ()
  | Some inst -> inst.ai_epoch <- inst.ai_epoch + 1

let list_actors () =
  Hashtbl.fold (fun pid (inst : actor_inst) acc ->
    { ai_pid       = pid;
      ai_name      = inst.ai_name;
      ai_alive     = inst.ai_alive;
      ai_state_str = value_to_string inst.ai_state }
    :: acc
  ) actor_registry []
  |> List.sort (fun a b -> compare a.ai_pid b.ai_pid)

(* =================================================================
   §5  Phase 1: Monitors, Links, and crash_actor (must precede base_env)
   ================================================================= *)




(* Moved to eval_prim.ml; re-exported here (same mutable cells). *)
let eval_expr_hook = Eval_prim.eval_expr_hook
let run_scheduler_hook = Eval_prim.run_scheduler_hook
let apply_hook = Eval_prim.apply_hook

(* =================================================================
   §6  FFI extern stub table
   ================================================================= *)

(** Table of OCaml-side stubs for extern functions.
    Key: (lib_name, symbol_name).
    On interpreter path we don't dlopen; instead we register known
    math/libc symbols here so that `extern "c"` and `extern "m"` blocks
    work without a C runtime call. *)
let foreign_stubs : (string * string, value list -> value) Hashtbl.t =
  let t = Hashtbl.create 32 in
  let reg lib sym f = Hashtbl.replace t (lib, sym) f in
  (* libc / libm math — single-float functions *)
  let f1 name ocaml_fn =
    List.iter (fun lib -> reg lib name (function
        | [VFloat x] -> VFloat (ocaml_fn x)
        | [VInt x]   -> VFloat (ocaml_fn (float_of_int x))
        | _ -> eval_error "extern %s: expected one numeric argument" name))
      ["c"; "m"; "libm"; "libc"; "libm.so"; "libc.so"] in
  let f2 name ocaml_fn =
    List.iter (fun lib -> reg lib name (function
        | [VFloat a; VFloat b] -> VFloat (ocaml_fn a b)
        | [VInt   a; VFloat b] -> VFloat (ocaml_fn (float_of_int a) b)
        | [VFloat a; VInt   b] -> VFloat (ocaml_fn a (float_of_int b))
        | [VInt   a; VInt   b] -> VFloat (ocaml_fn (float_of_int a) (float_of_int b))
        | _ -> eval_error "extern %s: expected two numeric arguments" name))
      ["c"; "m"; "libm"; "libc"; "libm.so"; "libc.so"] in
  f1 "sqrt"  sqrt;
  f1 "cbrt"  (fun x -> Float.cbrt x);
  f1 "exp"   exp;
  f1 "exp2"  (fun x -> Float.exp2 x);
  f1 "log"   log;
  f1 "log2"  (fun x -> Float.log2 x);
  f1 "log10" log10;
  f1 "sin"   sin;
  f1 "cos"   cos;
  f1 "tan"   tan;
  f1 "asin"  asin;
  f1 "acos"  acos;
  f1 "atan"  atan;
  f1 "sinh"  sinh;
  f1 "cosh"  cosh;
  f1 "tanh"  tanh;
  f1 "fabs"  abs_float;
  f1 "ceil"  ceil;
  f1 "floor" floor;
  f1 "round" Float.round;
  f1 "trunc" (fun x -> Float.of_int (int_of_float x));
  f2 "pow"   ( ** );
  f2 "fmod"  mod_float;
  f2 "atan2" atan2;
  f2 "hypot" hypot;
  f2 "fmin"  Float.min;
  f2 "fmax"  Float.max;
  (* puts: print string + newline, return length *)
  List.iter (fun lib ->
    reg lib "puts" (function
      | [VString s] -> capture_writeln s; VInt (String.length s + 1)
      | _ -> eval_error "extern puts: expected String"))
    ["c"; "libc"; "libc.so"];
  t

(* ------------------------------------------------------------------ *)
(* Dynamic FFI (Phase 4): dlopen + fixed-arity trampoline for primitive *)
(* externs not covered by the static foreign_stubs table above.         *)
(* Interpreter-only; primitives only (Int/Bool args, Int/Bool/Float ret).*)
(* ------------------------------------------------------------------ *)
external _ffi_dlopen    : string -> nativeint = "march_eval_dlopen"
external _ffi_dlsym     : nativeint -> string -> nativeint = "march_eval_dlsym"
external _ffi_dyncall_i : nativeint -> int64 array -> int -> int64 = "march_eval_dyncall_i"
external _ffi_dyncall_d : nativeint -> int64 array -> int -> float = "march_eval_dyncall_d"
external _ffi_dyncall_fi : nativeint -> int64 array -> int -> float array -> int -> int64 = "march_eval_dyncall_fi"
external _ffi_dyncall_fd : nativeint -> int64 array -> int -> float array -> int -> float = "march_eval_dyncall_fd"
(* Gap 1: open a user FFI shim .so into the interpreter's symbol space. *)
external _ffi_dlopen_extra : string -> unit = "march_eval_dlopen_extra"

(** Thunk returning the path to the runtime .so holding FFI symbols; set by the
    driver (bin/main.ml).  Called lazily on the first extern call so non-FFI
    programs never pay the .so build cost.  Default/None ⇒ resolve from
    already-loaded libs (RTLD_DEFAULT). *)
let ffi_runtime_so : (unit -> string option) ref = ref (fun () -> None)
(* Gap 1: optional path to a pre-compiled user shim .so (from forge.toml [ffi]
   sources, or --ffi-so).  Set by bin/main.ml before run_module when ffi_c_files
   are present.  Loaded lazily alongside the runtime .so. *)
let ffi_shim_so : string option ref = ref None
let _ffi_handle : nativeint option ref = ref None
(* The FFI ABI version this build expects; must equal MARCH_FFI_ABI_VERSION in
   runtime/march_ffi.h.  Verified against the dlopened runtime at load time. *)
let _ffi_abi_expected = 1
let _ffi_get_handle () : nativeint =
  match !_ffi_handle with
  | Some h -> h
  | None ->
    let h = match !ffi_runtime_so () with
      | Some path when path <> "" -> _ffi_dlopen path
      | _ -> 0n  (* RTLD_DEFAULT *) in
    (* ABI handshake (spec §4.1): a dlopened runtime must report a matching ABI
       version, so a stale/foreign .so is rejected with a clear message rather
       than corrupting at a later call. *)
    if h <> 0n then begin
      let vp = _ffi_dlsym h "march_ffi_abi_version" in
      if vp <> 0n then begin
        let v = Int64.to_int (_ffi_dyncall_i vp [||] 0) in
        if v <> _ffi_abi_expected then
          eval_error "FFI ABI version mismatch: the loaded runtime reports ABI \
                      v%d but this build expects v%d — rebuild the runtime/bindings"
            v _ffi_abi_expected
      end
    end;
    (* Gap 1: load user shim .so if present.  Must happen AFTER the runtime .so
       so that symbols from march_ffi.h (e.g. march_str_borrow) are already in
       the global symbol table when the shim's initialisation code runs. *)
    (match !ffi_shim_so with
     | Some path when path <> "" ->
       (try _ffi_dlopen_extra path
        with Failure msg ->
          eval_error "FFI: could not load user shim .so — %s" msg)
     | _ -> ());
    _ffi_handle := Some h; h

(* =================================================================
   §7  FFI Marshal Layer — see specs/plans/2026-06-22-ffi-interpreter-full.md
   ================================================================= *)

(* Shape descriptor "name:k;…" sorted by field name; must match forge's logic. *)
let ffi_shape_desc (fields : field list) : string =
  let sorted = List.sort (fun a b -> String.compare a.fld_name.txt b.fld_name.txt) fields in
  String.concat "" (List.map (fun f ->
    let k = match f.fld_ty with
      | TyCon ({txt = "Int"|"Bool"|"Unit"|"Atom"; _}, []) -> 'i'
      | TyCon ({txt = "Float"; _}, []) -> 'f'
      | TyVar _ -> 'g'
      | _ -> 'p'
    in
    Printf.sprintf "%s:%c;" f.fld_name.txt k) sorted)

(* Option(Float)/Option(Unit) payloads are boxed (niche would alias None=0). *)
let ffi_payload_is_boxed = function
  | TyCon ({txt = "Float"|"Unit"; _}, []) -> true
  | _ -> false

(* Helper: find index of an item in a list (returns -1 if not found). *)
let list_index pred lst =
  let rec go i = function [] -> -1 | x :: r -> if pred x then i else go (i+1) r
  in go 0 lst

(* Marshal: interpreter value → int64 march_value.
   int_enc=`Raw: Int/Bool as plain machine int (record/variant field slots, top-level).
   int_enc=`Tagged: Int/Bool as tagged word via make_int (Option/Result payloads). *)
let rec ffi_marshal_iv (int_enc : [`Raw | `Tagged]) (ty : ty) (v : value) : int64 =
  match ty, v with
  (* Opaque FFI `resource` handle: pass the raw marshaled bits straight
     through, regardless of the expected type — a VResource is only ever
     produced by ffi_unmarshal_iv's own resource case below, so it's always
     already the correct representation for re-entering an extern call.
     Bump the refcount first: the OCaml [value] keeps its own live reference
     to [mv] independent of this call, but dynamic_ffi_call's post-call
     cleanup unconditionally drops every heap-classified argument it
     marshaled (mirroring the fact that e.g. VString's str_new allocates a
     fresh, call-scoped march_value). A resource is the one case where the
     marshaled march_value is NOT a fresh call-scoped allocation but the same
     long-lived handle the March-level variable still holds, so without this
     dup the cleanup drop would prematurely free it (and run its native
     destructor) after its first use as an argument — e.g. passing the same
     `Db` handle into two successive `sqlite_prepare` calls would close the
     connection after the first. *)
  | _, VResource mv -> Ffi_marshal.dup mv; mv
  | TyCon ({txt = "Int"|"Char"; _}, []), VInt n ->
    let n64 = Int64.of_int n in
    if int_enc = `Tagged then Ffi_marshal.make_int n64 else n64
  | TyCon ({txt = "Bool"; _}, []), VBool b ->
    let n = if b then 1L else 0L in
    if int_enc = `Tagged then Ffi_marshal.make_int n else n
  | TyCon ({txt = "Float"; _}, []), VFloat f ->
    Ffi_marshal.make_float f
  | TyCon ({txt = "Float"; _}, []), VInt n ->
    Ffi_marshal.make_float (Float.of_int n)
  | TyCon ({txt = "Unit"; _}, []), (VUnit | VTuple []) ->
    0L   (* Unit payload inside boxed Some: sentinel 0 *)
  | TyCon ({txt = "String"; _}, []), VString s ->
    Ffi_marshal.str_new s
  | TyCon ({txt = "Bytes"; _}, []), VString s ->
    Ffi_marshal.bytes_new s
  | TyCon ({txt = "Option"; _}, [p_ty]), VCon ("None", []) ->
    if ffi_payload_is_boxed p_ty then Ffi_marshal.none_boxed () else Ffi_marshal.none ()
  | TyCon ({txt = "Option"; _}, [p_ty]), VCon ("Some", [x]) ->
    let pv = ffi_marshal_payload p_ty x in
    if ffi_payload_is_boxed p_ty then Ffi_marshal.some_boxed pv else Ffi_marshal.some pv
  | TyCon ({txt = "Result"; _}, [a_ty; _]), VCon ("Ok", [x]) ->
    Ffi_marshal.ok (ffi_marshal_payload a_ty x)
  | TyCon ({txt = "Result"; _}, [_; e_ty]), VCon ("Err", [x]) ->
    Ffi_marshal.err (ffi_marshal_payload e_ty x)
  | TyCon ({txt = tname; _}, _), VRecord fields ->
    (match Hashtbl.find_opt ffi_type_decl_tbl tname with
     | Some (TDRecord fdecls) ->
       let sorted = List.sort
         (fun a b -> String.compare a.fld_name.txt b.fld_name.txt) fdecls in
       let slots = Array.of_list (List.map (fun fdecl ->
         let v = try List.assoc fdecl.fld_name.txt fields
                 with Not_found ->
                   eval_error "FFI marshal: missing field '%s' in %s" fdecl.fld_name.txt tname in
         ffi_marshal_field fdecl.fld_ty v) sorted) in
       Ffi_marshal.make_record (ffi_shape_desc fdecls) slots
     | _ ->
       eval_error "FFI marshal: %s is not a known record type (use --compile for complex types)" tname)
  | TyCon ({txt = tname; _}, _), VCon (ctor, args) ->
    (match Hashtbl.find_opt ffi_type_decl_tbl tname with
     | Some (TDVariant vars) ->
       let tag = list_index (fun v -> v.var_name.txt = ctor) vars in
       if tag < 0 then eval_error "FFI marshal: unknown constructor %s in %s" ctor tname;
       let var = List.nth vars tag in
       if List.length var.var_args <> List.length args then
         eval_error "FFI marshal: ctor %s arity mismatch" ctor;
       let slots = Array.of_list (List.map2 ffi_marshal_field var.var_args args) in
       Ffi_marshal.make_variant tag slots
     | _ ->
       eval_error "FFI marshal: %s is not a known variant type (use --compile for complex types)" tname)
  | _ ->
    eval_error "FFI marshal: cannot marshal %s across FFI boundary (run with --compile)" (show_ty ty)

and ffi_marshal_field ty v = ffi_marshal_iv `Raw ty v
and ffi_marshal_payload ty v = ffi_marshal_iv `Tagged ty v

(** Does marshalling [v] at type [ty] hand back an *owned* march_value that the
    caller must [drop] after the call?  Mirrors [ffi_marshal_iv]'s allocation
    cases above — keep the two in sync.

    This must be decided from the static type and value shape, never from the
    marshaled bit pattern.  [Int]/[Char]/[Bool] arguments are marshaled `Raw`
    (untagged), so an even value is bit-identical to a heap pointer: reading
    ownership off the bits made every even [Int] argument >= 4096 (the
    runtime's [IS_HEAP_PTR] floor) get decremented as if it were a refcounted
    object.  Chunk sizes and native handles are exactly that shape, so any
    extern doing file I/O crashed while one taking only 0/1 flags survived. *)
and ffi_marshal_owns (ty : ty) (v : value) : bool =
  match ty, v with
  (* Dup'd on the way in (see the VResource case above); the drop balances it. *)
  | _, VResource _ -> true
  | TyCon ({txt = "Int"|"Char"|"Bool"|"Float"|"Unit"; _}, []), _ -> false
  (* Niche Option is the payload's representation, so it inherits its
     ownership; the boxed form always allocates a cell. *)
  | TyCon ({txt = "Option"; _}, [p_ty]), VCon ("None", []) ->
    ffi_payload_is_boxed p_ty
  | TyCon ({txt = "Option"; _}, [p_ty]), VCon ("Some", [x]) ->
    ffi_payload_is_boxed p_ty || ffi_marshal_owns p_ty x
  (* String/Bytes/Result/record/variant all allocate; anything else would have
     raised in ffi_marshal_iv before reaching the drop loop. *)
  | _ -> true

(* Unmarshal: int64 march_value → interpreter value. *)
let rec ffi_unmarshal_iv (int_enc : [`Raw | `Tagged]) (ty : ty) (mv : int64) : value =
  match ty with
  | TyCon ({txt = "Int"|"Char"; _}, []) ->
    VInt (Int64.to_int (if int_enc = `Tagged then Ffi_marshal.get_int mv else mv))
  | TyCon ({txt = "Bool"; _}, []) ->
    VBool ((if int_enc = `Tagged then Ffi_marshal.get_int mv else mv) <> 0L)
  | TyCon ({txt = "Float"; _}, []) ->
    VFloat (Ffi_marshal.get_float mv)
  | TyCon ({txt = "Unit"; _}, []) ->
    VUnit
  | TyCon ({txt = "String"; _}, []) ->
    VString (Ffi_marshal.str_borrow_copy mv)
  | TyCon ({txt = "Bytes"; _}, []) ->
    VString (Ffi_marshal.bytes_borrow_copy mv)
  | TyCon ({txt = "Option"; _}, [p_ty]) ->
    if ffi_payload_is_boxed p_ty then begin
      (* None_boxed = tag 0, Some_boxed = tag 1 *)
      if Ffi_marshal.variant_tag mv = 0 then VCon ("None", [])
      else VCon ("Some", [ffi_unmarshal_payload p_ty (Ffi_marshal.variant_field mv 0)])
    end else begin
      if mv = 0L then VCon ("None", [])
      else VCon ("Some", [ffi_unmarshal_payload p_ty mv])  (* niche: Some value = the payload *)
    end
  | TyCon ({txt = "Result"; _}, [a_ty; e_ty]) ->
    if Ffi_marshal.variant_tag mv = 0
    then VCon ("Ok",  [ffi_unmarshal_payload a_ty (Ffi_marshal.variant_field mv 0)])
    else VCon ("Err", [ffi_unmarshal_payload e_ty (Ffi_marshal.variant_field mv 0)])
  | TyCon ({txt = tname; _}, _) when Hashtbl.mem ffi_resource_tbl tname ->
    (* `resource Foo` — an opaque FFI handle (see ffi_resource_tbl comment).
       Never consult ffi_type_decl_tbl's variant path for these: the raw bits
       are not a variant discriminant, just wrap them as-is. *)
    VResource mv
  | TyCon ({txt = tname; _}, _) ->
    (match Hashtbl.find_opt ffi_type_decl_tbl tname with
     | Some (TDRecord fdecls) ->
       let sorted = List.sort
         (fun a b -> String.compare a.fld_name.txt b.fld_name.txt) fdecls in
       let fields = List.mapi (fun i fdecl ->
         (fdecl.fld_name.txt, ffi_unmarshal_field fdecl.fld_ty (Ffi_marshal.record_field mv i)))
         sorted in
       VRecord fields
     | Some (TDVariant vars) ->
       let tag = Ffi_marshal.variant_tag mv in
       let var = (try List.nth vars tag
                  with Failure _ | Invalid_argument _ ->
                    eval_error "FFI unmarshal: variant tag %d out of range for %s" tag tname) in
       let args = List.mapi (fun i arg_ty ->
         ffi_unmarshal_field arg_ty (Ffi_marshal.variant_field mv i))
         var.var_args in
       VCon (var.var_name.txt, args)
     | _ ->
       eval_error "FFI unmarshal: unknown type %s (run with --compile)" tname)
  | _ ->
    eval_error "FFI unmarshal: cannot unmarshal %s from FFI boundary (run with --compile)" (show_ty ty)

and ffi_unmarshal_field ty mv = ffi_unmarshal_iv `Raw ty mv
and ffi_unmarshal_payload ty mv = ffi_unmarshal_iv `Tagged ty mv

(** Dynamically call an extern.  Returns None if the binding uses unsupported
    types (upcalls/closures); otherwise calls the function and returns the
    result as a March [value]. *)
let dynamic_ffi_call (lib : string) (sym : string)
    (param_tys : ty list) (ret_ty : ty) (ef_raises : bool)
    (args : value list) : value option =
  (* Load the runtime .so first — marshal calls lazy-init from RTLD_DEFAULT,
     which only works once the .so is loaded with RTLD_GLOBAL. *)
  let h = _ffi_get_handle () in
  Ffi_marshal.reset ();   (* invalidate pointer cache if a new .so was just loaded *)
  (* Classify each arg as GP (int64) or FP (float) based on its static type. *)
  (* [`GP (word, owned)] — [owned] records whether marshalling allocated a
     reference we must drop after the call.  It is computed from the static
     type, not from [word]'s bits: see [ffi_marshal_owns]. *)
  let classify_arg ty v : [`GP of int64 * bool | `FP of float | `Err] =
    match ty with
    | TyCon ({txt = "Float"; _}, []) ->
      (match v with VFloat f -> `FP f | VInt n -> `FP (Float.of_int n) | _ -> `Err)
    | TyArrow _ ->
      (* Gap 2: closures/upcalls as FFI arguments require --compile.
         The interpreter cannot synthesize a C function pointer for an OCaml
         closure without a JIT trampoline.  Return `Err` so dynamic_ffi_call
         returns None and the caller emits a clear diagnostic.
         Future work: allocate mmap'd trampolines or use libffi to create real
         C function pointers here, enabling interpreter upcalls. *)
      `Err
    | _ ->
      (try `GP (ffi_marshal_field ty v, ffi_marshal_owns ty v)
       with Eval_error _ -> `Err)
  in
  let classified = List.map2 classify_arg param_tys args in
  if List.exists (fun c -> c = `Err) classified then None
  else begin
    (* Look up symbol first in the runtime handle, then fall back to the global
       symbol scope (RTLD_DEFAULT = 0n).  The fallback finds symbols from any
       RTLD_GLOBAL-loaded library, including user shim .so files loaded by
       _ffi_dlopen_extra (Gap 1). *)
    let fnptr =
      let p = _ffi_dlsym h sym in
      if p <> 0n then p else _ffi_dlsym 0n sym
    in
    if fnptr = 0n then
      eval_error "extern %s:%s — symbol not found for interpreter FFI \
                  (build the runtime, or run with --compile)" lib sym;
    (* Optionally prepend a raises-env pointer as the first GP arg. *)
    let env_ptr = if ef_raises then Some (Ffi_marshal.alloc_env ()) else None in
    let gp_prefix = match env_ptr with
      | Some p -> [Ffi_marshal.env_ptr_i64 p] | None -> [] in
    let gp_args = Array.of_list (gp_prefix @
      List.filter_map (function `GP (i, _) -> Some i | _ -> None) classified) in
    let fp_args = Array.of_list (
      List.filter_map (function `FP f -> Some f | _ -> None) classified) in
    let ni = Array.length gp_args in
    let nf = Array.length fp_args in
    (* Determine the actual C return type:
       - `raises fn f(...): Result(Float,E)` → C returns double (bare Ok payload)
       - `fn f(...): Float`                  → C returns double
       - everything else                     → C returns int64_t *)
    let c_ret_is_float = match ret_ty with
      | TyCon ({txt = "Float"; _}, []) -> true
      | TyCon ({txt = "Result"; _}, [TyCon ({txt = "Float"; _}, []); _]) when ef_raises -> true
      | _ -> false
    in
    let result =
      if c_ret_is_float then begin
        let f = if nf = 0 then _ffi_dyncall_d fnptr gp_args ni
                else _ffi_dyncall_fd fnptr gp_args ni fp_args nf in
        (match env_ptr with
         | None -> Some (VFloat f)
         | Some p ->
           let v = if Ffi_marshal.env_raised p then
             let e_ty = (match ret_ty with TyCon({txt="Result";_},[_;e]) -> e | _ -> ret_ty) in
             let ev = ffi_unmarshal_payload e_ty (Ffi_marshal.env_err p) in
             VCon ("Err", [ev])
           else VCon ("Ok", [VFloat f]) in
           Ffi_marshal.free_env p;
           Some v)
      end else begin
        let raw = if nf = 0 then _ffi_dyncall_i fnptr gp_args ni
                  else _ffi_dyncall_fi fnptr gp_args ni fp_args nf in
        let v =
          match env_ptr with
          | None -> ffi_unmarshal_field ret_ty raw
          | Some p ->
            let v = if Ffi_marshal.env_raised p then
              let e_ty = (match ret_ty with TyCon({txt="Result";_},[_;e]) -> e | _ -> ret_ty) in
              let ev = ffi_unmarshal_payload e_ty (Ffi_marshal.env_err p) in
              VCon ("Err", [ev])
            else
              let ok_ty = (match ret_ty with TyCon({txt="Result";_},[a;_]) -> a | _ -> ret_ty) in
              VCon ("Ok", [ffi_unmarshal_field ok_ty raw]) in
            Ffi_marshal.free_env p;
            v
        in
        Some v
      end
    in
    (* Drop only the references marshalling actually allocated.  The [is_heap]
       check stays as a defensive second gate, but [owned] is what makes this
       correct — an unowned scalar can look heap-shaped. *)
    List.iter (function
      | `GP (i, true) when Ffi_marshal.is_heap i -> Ffi_marshal.drop i
      | _ -> ()) classified;
    result
  end















(* [base_env] moved to eval_builtins.ml.  Re-exported here because
   [Eval.base_env] has external call sites across the compiler and the
   test suite. *)
let base_env = Eval_builtins.base_env

(* =================================================================
   §8  Evaluation
   ================================================================= *)

(* ── Global-tail lookup cache ─────────────────────────────────────────
   [env] is a cons list whose suffix (builtins + loaded module fns) is
   physically shared by every closure and call frame. Scanning it per
   variable reference was 95% of interpreted run time. We remember that
   suffix pointer and hash its contents; [lookup] scans only the local
   prefix (typically < 20 entries) and then probes the table.
   Invariants:
   - a name's value in the table is the FIRST occurrence in the tail
     (same as the scan), built by inserting from the end;
   - [global_tail] is compared with physical equality ([==]); an env that
     does not share the pointer is scanned to the end exactly as before. *)
let global_tail : env ref = ref []
let global_tbl : (string, value) Hashtbl.t = Hashtbl.create 1024

let install_global_tail (tail : env) : unit =
  global_tail := tail;
  Hashtbl.reset global_tbl;
  List.iter (fun (k, v) -> Hashtbl.replace global_tbl k v) (List.rev tail)

let clear_global_tail () : unit =
  global_tail := [];
  Hashtbl.reset global_tbl

(** Monomorphic assoc over [env]. [List.assoc_opt] goes through polymorphic
    [compare] (caml_compare → compare_val → memcmp per entry); on a ~650-entry
    builtin tail that was ~95% of interpreted run time (sampled 2026-08-23). *)
let rec assoc_str (name : string) (env : env) : value option =
  if env == !global_tail && env != [] then Hashtbl.find_opt global_tbl name
  else
  match env with
  | [] -> None
  | (k, v) :: rest -> if String.equal k name then Some v else assoc_str name rest

let lookup name env =
  match assoc_str name env with
  | Some v -> v
  | None ->
    (* Qualified module references (dotted names like "Beta.value") are desugared
       from EField to EVar by the desugar pass.  If not found in the lexical env,
       check the global module_registry so that cross-module calls work regardless
       of load order — a closure captured in Alpha can call Beta.value even if
       Beta was evaluated after Alpha. *)
    if String.contains name '.' then
      (match Hashtbl.find_opt module_registry name with
       | Some v -> v
       | None ->
         (* Try loading the module on demand from stdlib *)
         let dot = String.index name '.' in
         let mod_name = String.sub name 0 dot in
         ensure_module_loaded mod_name;
         (match Hashtbl.find_opt module_registry name with
          | Some v -> v
          | None ->
            (* Interface dispatch fallback: progressively strip leading module
               components to resolve "Conduit.Storage.checkpoint_get" →
               "Storage.checkpoint_get" which is registered in module_registry
               when the impl was evaluated. *)
            let rec strip_lookup nm =
              match String.index_opt nm '.' with
              | None -> eval_error "unbound variable: %s" name
              | Some i ->
                let shorter = String.sub nm (i+1) (String.length nm - i - 1) in
                match Hashtbl.find_opt module_registry shorter with
                | Some v -> v
                | None -> strip_lookup shorter
            in
            strip_lookup name))
    else
      eval_error "unbound variable: %s" name

(** Extract parameter names from a single fn_clause (after desugaring,
    all params are FPNamed or FPPat(PatVar)). *)
let clause_params (clause : fn_clause) : string list =
  List.map (function
      | FPNamed p       -> p.param_name.txt
      | FPPat (PatVar n) -> n.txt
      | FPPat _         -> eval_error "unexpected pattern param after desugaring"
      | FPDefault (p, _) -> p.param_name.txt  (* desugar should have expanded these *)
    ) clause.fc_params

(** Extract span from an expression, or dummy_span if unavailable. *)
let span_of_expr (e : expr) : span =
  match e with
  | ELit (_, sp) | EApp (_, _, sp) | ECon (_, _, sp)
  | ELam (_, _, sp) | EBlock (_, sp) | ELet (_, sp)
  | EMatch (_, _, sp) | ETuple (_, sp) | ERecord (_, sp)
  | ERecordUpdate (_, _, sp) | EField (_, _, sp)
  | EIf (_, _, _, sp) | ECond (_, sp) | EPipe (_, _, sp) | EAnnot (_, _, sp)
  | EHole (_, sp) | EAtom (_, _, sp) | ESend (_, _, sp)
  | ESpawn (_, sp) | EDbg (_, sp) | ELetFn (_, _, _, _, sp) -> sp
  | ELetQ (_, _, _, sp) | ELetStar (_, _, _, sp) -> sp
  | EAssert (_, sp) -> sp
  | ESigil (_, _, sp) -> sp
  | EVar n -> n.span
  | EResultRef _ -> dummy_span

(** Evaluate a block: return the value of the last expression.
    [ELet] bindings extend the environment for subsequent expressions.

    This is the operational semantics of Core March's block rules — see
    `specs/lang/core-march.md` §4.2 (E-Blk-Last, E-Blk-Let, E-LetFn,
    E-Blk-Seq). Each arm below is annotated with the spec rule it implements. *)
let rec eval_block (env : env) (es : expr list) : value =
  match es with
  | []      -> VUnit
  | [e]     -> eval_expr env e  (* E-Blk-Last — core-march.md §4.2 *)
  | ELet (b, _) :: rest ->      (* E-Blk-Let — core-march.md §4.2 *)
    let v = eval_expr env b.bind_expr in
    let bindings = match match_pattern v b.bind_pat with
      | Some bs -> bs
      | None    -> raise (Match_failure
                            (Printf.sprintf "let binding pattern failed: the value %s did not match the expected pattern"
                               (value_to_string v)))
    in
    eval_block (bindings @ env) rest
  (* Local named recursive function: fn go(params) do body end *)
  | ELetFn (name, params, _, body, _) :: rest ->
    (* E-LetFn — core-march.md §4.2 — env_ref recursive knot: the closure's
       body reads !env_ref at call time (deferred), and env_ref is
       back-patched to env' (which contains name -> rec_v) below, so the
       closure's own name resolves to itself once called. *)
    let param_names = List.map (fun p -> p.param_name.txt) params in
    (* Use the env_ref trick so the function can call itself recursively. *)
    let env_ref = ref env in
    (* Captured NOW (this ELetFn's own construction point), not inside the
       `fun args -> …` below — see [VClosure]'s doc comment. *)
    let defn_prefix = effective_module_prefix () in
    let rec_v = VBuiltin ("<rec:" ^ name.txt ^ ">", fun args ->
      let call_env = !env_ref in
      apply (VClosure (call_env, param_names, body, defn_prefix)) args) in
    let env' = (name.txt, rec_v) :: env in
    env_ref := env';
    eval_block env' rest
  | e :: rest ->  (* E-Blk-Seq — core-march.md §4.2 *)
    let _ = eval_expr env e in
    eval_block env rest

(** Apply a callable value to a list of argument values. *)
and apply_inner (fn_val : value) (args : value list) : value =
  match fn_val with
  | VClosure (closure_env, params, body, defn_prefix) ->
    if List.length params <> List.length args then
      eval_error "arity mismatch: expected %d args, got %d"
        (List.length params) (List.length args);
    let env' = List.combine params args @ closure_env in
    (* Install this closure's own captured lexical prefix as the ambient
       [closure_prefix_override] for the duration of its body — see
       [VClosure]'s and [effective_module_prefix]'s doc comments.
       Exception-safe (Fun.protect) so a raised exception (Match_failure,
       March panic, …) never leaves a stale override in place for whatever
       runs next (a supervisor restart, a sibling actor handler, …).
       Unconditional (no fast path for [defn_prefix = ""]) even though that
       is the overwhelmingly common case: [module_stack] can be transiently
       non-empty here too (on-demand stdlib loading via [module_loader] can
       recurse into [eval_decl] while a closure body is mid-evaluation), so
       skipping the override write would let a STALE [current_doc_prefix]
       leak through instead of this closure's own (correctly empty)
       declaring prefix. Correctness over the small constant-factor cost on
       this hot path. *)
    let saved = !closure_prefix_override in
    closure_prefix_override := Some defn_prefix;
    Fun.protect
      ~finally:(fun () -> closure_prefix_override := saved)
      (fun () -> eval_expr env' body)

  | VBuiltin (name, f) ->
    (* Witness-validation effect guard — see [Eval_prim.builtin_guard]. *)
    (match !Eval_prim.builtin_guard with
     | Some g -> g name
     | None -> ());
    f args

  | VForeign (lib, sym, ef_raises, param_tys, ret_ty) ->
    (* 1. Static OCaml stub (libm/libc math etc.). Keyed by both the C symbol
          and the bare extern name so `= "sym"` and default bindings both hit. *)
    (match Hashtbl.find_opt foreign_stubs (lib, sym) with
     | Some f -> f args
     | None ->
       (* 2. Dynamic call via marshal layer (dlopen + typed trampoline). *)
       (match dynamic_ffi_call lib sym param_tys ret_ty ef_raises args with
        | Some v -> v
        | None ->
          eval_error "extern %s:%s — interpreter FFI cannot marshal the argument \
                      or return types of this binding (closures/upcalls not yet \
                      supported). Run with --compile." lib sym))

  | VMultiarity variants ->
    let n = List.length args in
    (match List.assoc_opt n variants with
     | Some fn_v -> apply fn_v args
     | None ->
       let arities = List.map (fun (a, _) -> string_of_int a) variants in
       eval_error "arity mismatch: function accepts %s args, got %d"
         (String.concat " or " arities) n)

  | _ -> eval_error "applied non-function value: %s" (value_to_string fn_val)

(** Depth-tracking wrapper around [apply_inner]. *)
and apply (fn_val : value) (args : value list) : value =
  (match !debug_ctx with
   | Some ctx -> ctx.dc_depth <- ctx.dc_depth + 1
   | None -> ());
  let result =
    (try `Ok (apply_inner fn_val args)
     with exn -> `Err exn)
  in
  (match !debug_ctx with
   | Some ctx -> ctx.dc_depth <- max 0 (ctx.dc_depth - 1)
   | None -> ());
  match result with
  | `Ok v    -> v
  | `Err exn -> raise exn

(** Main expression evaluator (inner, no tracing).

    This is the operational semantics of Core March — see
    `specs/lang/core-march.md` §4. Each core-construct arm below is annotated
    with the spec rule it implements. *)
and eval_expr_inner (env : env) (e : expr) : value =
  match e with
  | ELit (LitInt n, _)    -> VInt n     (* E-Lit — core-march.md §4.2 *)
  | ELit (LitFloat f, _)  -> VFloat f   (* E-Lit — core-march.md §4.2 *)
  | ELit (LitString s, _) -> VString s  (* E-Lit — core-march.md §4.2 *)
  | ELit (LitBool b, _)   -> VBool b    (* E-Lit — core-march.md §4.2 *)
  | ELit (LitAtom a, _)   -> VAtom a    (* E-Lit — core-march.md §4.2 *)

  | EVar n -> lookup n.txt env  (* E-Var — core-march.md §4.2 *)

  | EHole (name, _) ->
    let label = match name with Some n -> "?" ^ n.txt | None -> "?" in
    eval_error "typed hole `%s` reached the evaluator — the type checker should have caught this" label

  | EApp (f, args, sp) ->
    (* E-App-Clo / E-App-Prim — core-march.md §4.2 (dispatch on fn_val's shape
       happens inside apply/apply_inner: VClosure -> E-App-Clo, VBuiltin -> E-App-Prim) *)
    check_reductions ();
    let fn_name = match f with
      | EVar n -> n.txt
      | EField (_, field, _) -> field.txt
      | _ -> "<anon>"
    in
    (if !March_coverage.Coverage.coverage_enabled then
      March_coverage.Coverage.record_fn_call fn_name);
    let fn_val = eval_expr env f in
    let arg_vals = List.map (eval_expr env) args in
    march_stack_push fn_name sp;
    (* Leave March-panic frames live for the backtrace handler.
       Pop for all other exceptions (Yield, Stack_overflow, etc.) so they
       don't corrupt subsequent backtraces. *)
    (match apply fn_val arg_vals with
     | v -> march_stack_pop (); v
     | exception (Eval_error _ | Match_failure _ | Assert_failure _ as e) -> raise e
     | exception e -> march_stack_pop (); raise e)

  | ECon (name, args, _) ->  (* E-Con — core-march.md §4.2 *)
    let arg_vals = List.map (eval_expr env) args in
    (* Strip any type qualifier from the constructor tag so that
       Result.Ok and Ok both produce VCon("Ok", …) at runtime. *)
    let bare_tag = match String.rindex_opt name.txt '.' with
      | Some i -> String.sub name.txt (i + 1) (String.length name.txt - i - 1)
      | None   -> name.txt
    in
    (* Collision-conditional module-qualified tag: when [bare_tag] is
       BOTH declared by a colliding type AND shares that ctor name with
       another candidate in the same collision group (see
       [colliding_ctor_type_by_module]'s doc comment), the tag becomes
       "<lexical module>.<type>.<ctor>" (e.g. "DcA.Thing.Shared") instead
       of the bare name — otherwise a same-shape ctor from a same-short-name
       type declared in a DIFFERENT module would be runtime-indistinguishable
       ([VCon]'s tag string IS its entire identity, unlike native which has a
       separate integer discriminant). [effective_module_prefix] (not the
       raw [current_doc_prefix]) supplies "the module this ECon was
       LEXICALLY written in", correct even when this site is evaluated
       later as part of a deferred closure body — see its doc comment.

       An explicitly qualified name (contains '.') is NOT necessarily
       already-resolved: the documented qualified-CONSTRUCTOR-reference
       syntax writes a MODULE prefix (mirrors the qualified-PATTERN syntax
       in specs/lang/pattern-matching.md, `Http.Ok(resp)`), so `B.Ok(s)`
       must resolve the SAME way a bare `Ok(s)` written lexically inside
       `B` would — see [match_pattern]'s [PatCon] arm, fixed identically
       (P0: builtin-ctor-collision-gap, 2026-07-22). Falls back to
       stripped-bare only when the qualifier is not a colliding module
       prefix (e.g. a plain `Type.Ctor` reference where "Type" is a type
       name, not a module — no [colliding_shared_ctor_type] entry exists for
       it). A NON-colliding or non-shared bare ctor (the overwhelming
       common case) takes the [None] branch and produces the byte-identical
       bare tag as before this change. *)
    let tag =
      match String.rindex_opt name.txt '.' with
      | Some i ->
        let qual = String.sub name.txt 0 i ^ "." in
        (match colliding_shared_ctor_type qual bare_tag with
         | Some short_type_name -> qual ^ short_type_name ^ "." ^ bare_tag
         | None -> bare_tag)
      | None ->
        let prefix = effective_module_prefix () in
        match colliding_shared_ctor_type prefix bare_tag with
        | Some short_type_name -> prefix ^ short_type_name ^ "." ^ bare_tag
        | None -> bare_tag
    in
    VCon (tag, arg_vals)

  | ELam (params, body, _) ->  (* E-Lam — core-march.md §4.2 *)
    let param_names = List.map (fun p -> p.param_name.txt) params in
    VClosure (env, param_names, body, effective_module_prefix ())

  | EBlock (es, _) -> eval_block env es
    (* E-Blk-Last / E-Blk-Let / E-LetFn / E-Blk-Seq — core-march.md §4.2, see eval_block below *)

  | ELet (b, _) ->
    (* Standalone let (outside a block) — evaluate and ignore bindings.
       This shouldn't appear after desugaring except inside EBlock.
       (Not itself one of the block rules below — those apply to ELet
       encountered *inside* an EBlock's statement list; see E-Blk-Let.) *)
    eval_expr env b.bind_expr

  | EMatch (scrut, branches, sp) ->  (* E-Match — core-march.md §4.2, branch selection §4.3 *)
    check_reductions ();
    let v = eval_expr env scrut in
    eval_match env sp v branches

  | ETuple ([], _) -> VUnit           (* E-Tuple (k=0 alias to VUnit) — core-march.md §4.2 *)
  | ETuple (es, _) ->                 (* E-Tuple — core-march.md §4.2 *)
    VTuple (List.map (eval_expr env) es)

  | ERecord (fields, _) ->  (* E-Record — core-march.md §4.2 *)
    VRecord (List.map (fun (n, ex) -> (n.txt, eval_expr env ex)) fields)

  | ERecordUpdate (base, updates, _) ->  (* E-Update — core-march.md §4.2 *)
    let base_val = eval_expr env base in
    (match base_val with
     | VRecord fields ->
       let updated = List.map (fun (n, ex) -> (n.txt, eval_expr env ex)) updates in
       (* A functional update is only defined for fields that already exist
          on the base record's actual (runtime) shape — matches the compiled
          backend's march_record_update_dyn contract (runtime/march_extras.c),
          which panics rather than silently fabricating a new field.  Most
          call sites have a statically-known record type, so the typechecker
          (typecheck.ml's ERecordUpdate case, expand_record on a concrete
          TRecord) already rejects an unknown field name before this arm ever
          runs; this eval_error only fires for an update through an
          erased/generic base (record_from_list/record_put results, whose
          type is a bare TVar), which is exactly the case the typechecker
          cannot validate ahead of time. *)
       List.iter (fun (k, _) ->
           if not (List.mem_assoc k fields) then
             eval_error "record update: no field '%s' in record" k
         ) updated;
       (* Merge: updated fields override existing ones *)
       let new_fields = List.map (fun (k, v) ->
           match List.assoc_opt k updated with
           | Some v' -> (k, v')
           | None    -> (k, v)
         ) fields in
       VRecord new_fields
     | _ -> eval_error "record update on non-record value")

  | EField (ex, field, _) ->
    (* E-Field — core-march.md §4.2 (the record-field case below; module-path
       resolution here is a fidelity note in the spec prose, not a separate rule) *)
    (* First try to resolve as a module path (handles A.B.c chained access) *)
    let rec module_path_str = function
      | ECon (n, [], _) -> Some n.txt
      | EField (e2, f, _) ->
        (match module_path_str e2 with
         | Some prefix -> Some (prefix ^ "." ^ f.txt)
         | None -> None)
      | _ -> None
    in
    let qualified_lookup =
      match module_path_str ex with
      | Some prefix ->
        let key = prefix ^ "." ^ field.txt in
        (match List.assoc_opt key env with
         | Some _ as v -> v
         | None ->
           match Hashtbl.find_opt module_registry key with
           | Some _ as v -> v
           | None ->
             (* Try loading the module on demand from stdlib *)
             ensure_module_loaded prefix;
             Hashtbl.find_opt module_registry key)
      | None -> None
    in
    (match qualified_lookup with
     | Some v -> v
     | None ->
    (match eval_expr env ex with
     | VRecord fields ->
       (match List.assoc_opt field.txt fields with
        | Some v -> v
        | None   -> eval_error "record has no field '%s'" field.txt)
     | VCon (mod_name, []) ->
       (* Module member access: Mod.member — look up "Mod.member" in env *)
       let key = mod_name ^ "." ^ field.txt in
       (match List.assoc_opt key env with
        | Some v -> v
        | None ->
          (* Try loading on demand *)
          ensure_module_loaded mod_name;
          (match Hashtbl.find_opt module_registry key with
           | Some v -> v
           | None -> eval_error "no member '%s' in module '%s'" field.txt mod_name))
     | _ -> eval_error "field access on non-record value"))

  | EIf (cond, then_, else_, sp) ->
    (match eval_expr env cond with
     | VBool true  ->  (* E-If-T — core-march.md §4.2 *)
       (if !March_coverage.Coverage.coverage_enabled then
         March_coverage.Coverage.record_branch sp true);
       eval_expr env then_
     | VBool false ->  (* E-If-F — core-march.md §4.2 *)
       (if !March_coverage.Coverage.coverage_enabled then
         March_coverage.Coverage.record_branch sp false);
       eval_expr env else_
     | _           -> eval_error "if condition must be a boolean")

  | ECond (arms, _) ->
    let rec go = function
      | [] -> eval_error "non-exhaustive `match do` — no arm matched"
        (* E-Cond-Fail — core-march.md §4.2 *)
      | (cond_e, body_e) :: rest ->
        (match eval_expr env cond_e with
         | VBool true  -> eval_expr env body_e  (* E-Cond-Sel — core-march.md §4.2 *)
         | VBool false -> go rest                (* E-Cond-Sel — core-march.md §4.2 *)
         | _           -> eval_error "`match do` condition must be Bool")
    in
    go arms

  | EPipe _ ->
    eval_error "pipe expression reached evaluator (should be desugared)"

  | ESigil _ ->
    eval_error "sigil expression reached evaluator (should be desugared)"

  | EResultRef _ ->
    raise (Eval_error "EResultRef reached evaluator — substitution missing")

  | EDbg (None, _) ->
    (* Unconditional breakpoint: pause and open debug REPL. *)
    (match !debug_ctx with
     | Some ctx when ctx.dc_enabled ->
       (match ctx.dc_on_dbg with
        | Some f -> f env
        | None   -> ())
     | _ -> ());
    VUnit

  | EDbg (Some inner, sp) ->
    let v = eval_expr env inner in
    (match !debug_ctx with
     | Some ctx when ctx.dc_enabled ->
       (match v with
        | VBool b ->
          (* Conditional breakpoint: pause only when true. *)
          if b then (match ctx.dc_on_dbg with Some f -> f env | None -> ())
        | _ ->
          (* Value trace: print to stderr and return the value. *)
          Printf.eprintf "[dbg] %s:%d:%d = %s\n%!"
            sp.March_ast.Ast.file sp.March_ast.Ast.start_line
            sp.March_ast.Ast.start_col (value_to_string v))
     | _ -> ());
    v

  | EAnnot (ex, _, _) -> eval_expr env ex

  | EAtom (a, [], _) -> VAtom a  (* E-Atom-0 — core-march.md §4.2 *)
  | EAtom (a, args, _) ->        (* E-Atom-N — core-march.md §4.2 *)
    let arg_vals = List.map (eval_expr env) args in
    VCon (a, arg_vals)

  | ESpawn (actor_expr, _) ->
    let actor_name = match actor_expr with
      | EVar n           -> n.txt
      | ECon (n, [], _)  -> n.txt
      | _ -> eval_error "spawn: expected actor name (got complex expression)"
    in
    (match Hashtbl.find_opt actor_defs_tbl actor_name with
     | None -> eval_error "spawn: unknown actor '%s'" actor_name
     | Some (def, env_ref) ->
       let pid = !next_pid in
       next_pid := pid + 1;
       (* Phase 2: if this actor is a supervisor, spawn children first and
          inject their pids into the init state. *)
       let init_state = match def.actor_supervise with
         | None ->
           eval_expr !env_ref def.actor_init
         | Some sup_cfg ->
           (* Spawn each child and collect (field_name -> pid) *)
           let child_pids = List.map (fun sf ->
             let child_actor_name = match sf.sf_ty with
               | TyCon (n, []) -> n.txt
               | _ -> eval_error "supervise: child type must be a simple actor name"
             in
             match Hashtbl.find_opt actor_defs_tbl child_actor_name with
             | None -> eval_error "spawn supervisor: unknown child actor '%s'" child_actor_name
             | Some (child_def, child_env_ref) ->
               let child_init_state = eval_expr !child_env_ref child_def.actor_init in
               let child_pid = !next_pid in
               next_pid := child_pid + 1;
               let child_inst = {
                 ai_name = child_actor_name; ai_def = child_def;
                 ai_env_ref = child_env_ref;
                 ai_state = child_init_state; ai_alive = true;
                 ai_terminal_reason = Normal;
                 ai_monitors = []; ai_mailbox = Queue.create ();
                 ai_supervisor = Some pid;
                 ai_restart_count = []; ai_epoch = 0;
                 ai_resources = [];
                 ai_linear_values = [];
                 ai_mbox_limit = 0; ai_mbox_policy = 0 } in
               Hashtbl.add actor_registry child_pid child_inst;
               (sf.sf_name.txt, child_pid)
           ) sup_cfg.sc_fields in
           (* Build init state: start from declared init, then overlay child pids *)
           let base_state = eval_expr !env_ref def.actor_init in
           (match base_state with
            | VRecord fields ->
              (* Replace fields that correspond to child actors with their pids *)
              let updated = List.map (fun (fname, fval) ->
                match List.assoc_opt fname child_pids with
                | Some cpid -> (fname, VInt cpid)
                | None -> (fname, fval)
              ) fields in
              (* Also add any child pids not in the record *)
              let extras = List.filter_map (fun (fname, cpid) ->
                if List.assoc_opt fname fields = None
                then Some (fname, VInt cpid)
                else None
              ) child_pids in
              VRecord (updated @ extras)
            | _ ->
              (* Non-record state: just use the init as-is *)
              base_state)
       in
       let inst = { ai_name     = actor_name; ai_def = def; ai_env_ref = env_ref;
                    ai_state    = init_state; ai_alive = true;
                    ai_terminal_reason = Normal;
                    ai_monitors = []; ai_mailbox = Queue.create ();
                    ai_supervisor = None; ai_restart_count = [];
                    ai_epoch = 0; ai_resources = [];
                    ai_linear_values = [];
                    ai_mbox_limit = 0; ai_mbox_policy = 0 } in
       Hashtbl.add actor_registry pid inst;
       VPid pid)

  | ESend (cap_expr, msg_expr, _) ->
    check_reductions ();
    let pid_val = eval_expr env cap_expr in
    let msg_val = eval_expr env msg_expr in
    (match pid_val with
     | VPid pid ->
       (match Hashtbl.find_opt actor_registry pid with
        | None -> VCon ("None", [])  (* dead/unknown actor: fire-and-forget, silently drop *)
        | Some inst when not inst.ai_alive -> VCon ("None", [])  (* actor was killed: drop *)
        | Some inst ->
          (* Phase 4: async — push message to mailbox, do not dispatch inline.
             Only constructor values (VCon/VAtom) are valid messages. *)
          (match msg_val with
           | VCon _ | VAtom _ ->
             mailbox_enqueue inst msg_val;
             VCon ("Some", [VUnit])
           | _ ->
             eval_error "send: message must be a constructor value, got %s"
               (value_to_string msg_val)))
     | VCap (pid, cap_epoch) ->
       (* Capability-based send: validate epoch and revocation before enqueuing. *)
       (match Hashtbl.find_opt actor_registry pid with
        | None -> VCon ("None", [])
        | Some inst when not inst.ai_alive -> VCon ("None", [])
        | Some inst when inst.ai_epoch <> cap_epoch ->
          eval_error "send: capability epoch mismatch — cap has epoch %d, actor is at epoch %d"
            cap_epoch inst.ai_epoch
        | _ when Hashtbl.mem revocation_table (pid, cap_epoch) ->
          eval_error "send: capability (pid=%d, epoch=%d) has been revoked" pid cap_epoch
        | Some inst ->
          (match msg_val with
           | VCon _ | VAtom _ ->
             mailbox_enqueue inst msg_val;
             VCon ("Some", [VUnit])
           | _ ->
             eval_error "send: message must be a constructor value, got %s"
               (value_to_string msg_val)))
     | _ ->
       eval_error "send: first argument must be a Pid or Cap, got %s"
         (value_to_string pid_val))

  | ELetFn (name, params, _, body, _) ->
    (* ELetFn as a standalone expression: return the closure (for e.g. last expr in block) *)
    let param_names = List.map (fun p -> p.param_name.txt) params in
    let env_ref = ref env in
    let defn_prefix = effective_module_prefix () in
    let rec_v = VBuiltin ("<rec:" ^ name.txt ^ ">", fun args ->
      let call_env = !env_ref in
      apply (VClosure (call_env, param_names, body, defn_prefix)) args) in
    let env' = (name.txt, rec_v) :: env in
    env_ref := env';
    rec_v

  | ELetQ (p, result_expr, cont, _) ->
    (match eval_expr env result_expr with
     | VCon ("Ok", [v]) ->
       let env' = match match_pattern v p with
         | Some bs -> bs @ env
         | None -> eval_error "let? pattern match failed (unreachable after typecheck)"
       in
       eval_expr env' cont
     | (VCon ("Err", _)) as err -> err
     | other ->
       eval_error "let? expected a Result value, got %s" (value_to_string other))

  | ELetStar (p, result_expr, cont, _) ->
    (* Dynamic counterpart of TIR lowering's static `M.flat_map(result_expr,
       fn p -> cont end)` expansion (lib/tir/lower.ml): the interpreter has
       no compile-time type info, so it dispatches on the RUNTIME value's
       type instead, via [type_name_of_value] (the same primitive `hash`/
       `to_json`'s dynamic dispatch above uses), then looks up `<Type>.
       flat_map` through the ordinary qualified-name env lookup every
       `Module.member` call already goes through. The continuation is
       passed to it as a plain [VBuiltin] closure -- [apply] dispatches a
       [VBuiltin] exactly like a March closure, so `flat_map`'s own March
       body calling `f(x)` invokes this OCaml callback transparently. *)
    let v = eval_expr env result_expr in
    let flat_map_fn =
      match type_name_of_value v with
      | Some head_name -> lookup (head_name ^ ".flat_map") env
      | None -> eval_error "let*: cannot determine the type of `%s`" (value_to_string v)
    in
    let k = VBuiltin ("$letstar_k", function
        | [x] ->
          (match match_pattern x p with
           | Some bs -> eval_expr (bs @ env) cont
           | None -> eval_error "let* pattern match failed (unreachable after typecheck)")
        | args -> eval_error "let* continuation: expected 1 argument, got %d" (List.length args))
    in
    apply flat_map_fn [v; k]

  | EAssert (inner, sp) ->
    (* Compiler-assisted assertion rewriting:
       If the inner expression is a binary comparison (==, !=, <, >, <=, >=),
       we evaluate both sides separately so we can show their values on failure.
       Otherwise, we just evaluate the expression and check if it's true. *)
    let comparison_ops = ["=="; "!="; "<"; ">"; "<="; ">="] in
    let loc = Printf.sprintf "%s:%d" sp.file sp.start_line in
    (match inner with
     | EApp (EVar op_name, [lhs; rhs], _) when List.mem op_name.txt comparison_ops ->
       let lv = eval_expr env lhs in
       let rv = eval_expr env rhs in
       let op_fn = lookup op_name.txt env in
       (match apply op_fn [lv; rv] with
        | VBool true -> VUnit
        | VBool false ->
          raise (Assert_failure (Printf.sprintf
            "assert failed at %s\n    left:  %s\n    right: %s"
            loc (value_to_string lv) (value_to_string rv)))
        | _ -> raise (Assert_failure (Printf.sprintf
            "assert: comparison did not return Bool (at %s)" loc)))
     | _ ->
       (match eval_expr env inner with
        | VBool true  -> VUnit
        | VBool false ->
          raise (Assert_failure (Printf.sprintf
            "assert: condition was false (at %s)" loc))
        | v ->
          raise (Assert_failure (Printf.sprintf
            "assert: expected Bool, got %s (at %s)" (value_to_string v) loc))))

(** Evaluate a match expression: try each branch until one matches.
    [match_span] is the span of the [EMatch] node, used for coverage arm tracking.

    This is the operational semantics of Core March's branch selection —
    see `specs/lang/core-march.md` §4.3. Branch selection: first-match-wins,
    guard, Match_failure — §4.3. *)
and eval_match (env : env) (match_span : span) (v : value) (branches : branch list) : value =
  let rec go arm_idx = function
    | [] ->
      (* exhaustiveness / no-match: raises Match_failure — §4.3 *)
      raise (Match_failure
               (Printf.sprintf "Non-exhaustive pattern match: no branch matched the value %s.\nAdd a catch-all `_ -> ...` arm, or handle this case explicitly."
                  (value_to_string v)))
    | br :: rest ->
      (match match_pattern v br.branch_pat with
       | None -> go (arm_idx + 1) rest  (* pattern failed to match: try next branch — §4.3 *)
       | Some bindings ->
         let env' = bindings @ env in  (* pattern-extended environment — §4.3 *)
         (* Check guard if present *)
         let guard_ok = match br.branch_guard with
           | None   -> true  (* no guard: branch selected outright — §4.3 *)
           | Some g ->
             (match eval_expr env' g with
              | VBool b -> b  (* guard evaluated in pattern-extended env — §4.3 *)
              | _       -> eval_error "guard must evaluate to a boolean")
         in
         if guard_ok then begin
           (* first-match-wins: this is the selected branch — §4.3 *)
           (if !March_coverage.Coverage.coverage_enabled then
             March_coverage.Coverage.record_arm match_span arm_idx);
           eval_expr env' br.branch_body
         end else go (arm_idx + 1) rest)  (* false guard: try next branch, does not fail the whole match — §4.3 *)
  in
  go 0 branches

(** Editor-driven (DAP) pause check. Consulted on every evaluated expression
    when a debug context with an [dc_on_pause] callback is installed.

    Stops (calls [dc_on_pause], which blocks until the controller assigns the
    next [dc_step] and resumes) when the current source line first becomes
    active and either a breakpoint sits on it or the active step mode says so.
    Tracking the last line — updated on every call — gives line-granular
    stepping (no stop on each sub-expression of a line) while still re-stopping
    when control loops back to the same line. *)
and maybe_pause (ctx : debug_ctx) (env : env) (e : expr) : unit =
  match ctx.dc_on_pause with
  | None -> ()
  | Some on_pause ->
    let sp = span_of_expr e in
    let line = sp.start_line in
    if line <= 0 then ()
    else begin
      let key = (sp.file, line) in
      let line_changed = ctx.dc_last_line <> Some key in
      ctx.dc_last_line <- Some key;
      let hit_bp = line_changed && Hashtbl.mem ctx.dc_breakpoints key in
      let step_stop =
        match ctx.dc_step with
        | Run        -> false
        | Pause      -> true
        | StepInto   -> line_changed
        | StepOver d -> line_changed && ctx.dc_depth <= d
        | StepOut  d -> line_changed && ctx.dc_depth <  d
      in
      if step_stop || hit_bp then on_pause env sp
    end

(** Tracing wrapper around [eval_expr_inner].
    When debug mode is active, records a [trace_frame] for every evaluation step.
    When [!debug_ctx] is None, this is a single pointer deref — zero overhead.
    Coverage recording is gated by [March_coverage.Coverage.coverage_enabled]. *)
and eval_expr (env : env) (e : expr) : value =
  (if !March_coverage.Coverage.coverage_enabled then
    March_coverage.Coverage.record_expr (span_of_expr e));
  match !debug_ctx with
  | None | Some { dc_enabled = false; _ } ->
    eval_expr_inner env e
  | Some ctx ->
    maybe_pause ctx env e;
    let outcome =
      try `Ok (eval_expr_inner env e)
      with exn -> `Err exn
    in
    let (result_v, exn_s) = match outcome with
      | `Ok v  -> (Some v, None)
      | `Err e -> (None, Some (Printexc.to_string e))
    in
    let frame = { tf_expr   = e;
                  tf_env    = env;
                  tf_result = result_v;
                  tf_exn    = exn_s;
                  tf_actor  = snapshot_actors ();
                  tf_span   = span_of_expr e;
                  tf_depth  = ctx.dc_depth } in
    ring_push ctx.dc_trace frame;
    (match outcome with
     | `Ok v   -> v
     | `Err exn -> raise exn)

(* =================================================================
   §9  Phase 2/3: Initialize eval_expr_hook for supervisor restarts
   ================================================================= *)

let () = eval_expr_hook := eval_expr
let () = apply_hook := apply
let () = iface_dispatch_hook := apply


(* =================================================================
   §10  Task builtins
   These are defined after [apply] so they can call it directly.
   ================================================================= *)

(** The number of reductions consumed during the most recent call to
    [eval_with_reduction_tracking]. *)
let last_reduction_count : int ref = ref 0

(** Reset all scheduler/task state. Call between test runs. *)
let reset_scheduler_state () : unit =
  clear_global_tail ();
  Hashtbl.clear task_registry;
  next_task_id := 0;
  Hashtbl.clear actor_registry;
  Hashtbl.clear named_registry;
  Hashtbl.clear reg_names_pending;
  pending_timers := [];
  Hashtbl.clear actor_defs_tbl;
  Hashtbl.reset impl_tbl;
  Hashtbl.reset iface_method_tbl;
  Hashtbl.reset ctor_type_tbl;
  Hashtbl.reset ctor_qualified_type_tbl;
  Hashtbl.reset type_collision_set;
  Hashtbl.reset colliding_ctor_type_by_module;
  closure_prefix_override := None;
  (* Pre-register builtin constructor → type mappings so Show dispatch works *)
  List.iter (fun (ctor, ty) -> Hashtbl.replace ctor_type_tbl ctor ty)
    [ "Ok", "Result"; "Err", "Result"
    ; "Some", "Option"; "None", "Option"
    ; "Cons", "List";  "Nil",  "List" ];
  Hashtbl.reset record_type_tbl;
  Hashtbl.reset protocol_roles_tbl;
  next_pid := 0;
  next_monitor_id := 0;
  current_pid := None;
  reduction_ctx := None;
  last_reduction_count := 0;
  dropped_messages_count := 0;
  Hashtbl.clear process_registry;
  Hashtbl.clear pid_to_registry_name;
  Hashtbl.clear dyn_sup_registry;
  Hashtbl.clear dyn_sup_vpid_map;
  dyn_sup_next_vpid := (-1);
  app_spawn_order := [];
  shutdown_requested := false;
  Hashtbl.clear revocation_table;
  Hashtbl.clear pending_replies;
  next_call_ref := 0;
  logger_level := 1;
  logger_fields := [];
  logger_appenders := [];
  Hashtbl.clear logger_module_levels;
  Hashtbl.clear vault_registry;
  Hashtbl.clear vault_name_registry;
  vault_next_id := 0;
  Hashtbl.clear ffi_type_decl_tbl;
  Hashtbl.clear ffi_resource_tbl

(* NOTE: debug_ctx actor event logging is intentionally not reproduced here.
   The old ESend recorded ame_state_before/ame_state_after. When actor debug
   tracing is needed, add the same pattern inside the handler dispatch block below. *)

(** Deliver every [pending_timers] entry whose deadline has passed (real
    wall-clock time, [Unix.gettimeofday]) and drop the rest of this pass's
    bookkeeping for it either way — a fired-or-cancelled entry is removed
    from [pending_timers] regardless of which happened. A cancelled entry's
    message is simply not delivered (OCaml's GC reclaims [tt_msg]; there is
    no explicit dtor to run here the way the compiled runtime needs one, per
    march_sched_set_msg_dtor's doc comment — the interpreter has no separate
    RC to release). A target that died or was never spawned is treated the
    same as march_send/actor_cast already treat it: the message is simply
    dropped.

    Called once per [run_scheduler] pass (see below), so [run_until_idle]
    delivers any timer that's already due — but does NOT wait for one that
    isn't: a pass where nothing else changes and no timer is due yet lets
    the pass loop's [changed] stay false and [run_scheduler] return, exactly
    mirroring the compiled runtime's march_sched_wait_idle design decision
    (see its doc comment in runtime/march_scheduler.c) that a pending
    send_after should not block that primitive. *)
let timer_service_tick () =
  if !pending_timers <> [] then begin
    let now = Unix.gettimeofday () *. 1000. in
    let due, still_pending =
      List.partition (fun t -> t.tt_cancelled || now >= t.tt_fire_at) !pending_timers
    in
    pending_timers := still_pending;
    List.iter (fun t ->
        if not t.tt_cancelled then
          match Hashtbl.find_opt actor_registry t.tt_target with
          | Some inst when inst.ai_alive -> mailbox_enqueue inst t.tt_msg
          | _ -> ()
      ) due
  end

(** Drain all actor mailboxes cooperatively.
    Each pass iterates over all live actors; for each with a non-empty mailbox
    it pops one message, finds the matching [on Msg] handler, and runs it.
    Repeats until a full pass produces no work (all mailboxes empty). *)
let run_scheduler () =
  let changed = ref true in
  while !changed && not !shutdown_requested do
    changed := false;
    timer_service_tick ();
    (* Drain deferred OS-signal watchers (Signal.watch): apply each pending
       handler on a normal green-thread stack, coalescing repeats to one call.
       The handler is typed [() -> ()] but may be spelled [fn -> body] (0-arg)
       or [fn _ -> body] (1-arg unit discard) — apply with the matching arity. *)
    for code = 0 to 4 do
      if signal_pending.(code) then begin
        signal_pending.(code) <- false;
        match signal_watchers.(code) with
        | Some handler ->
          (try
             ignore (match handler with
               | VClosure (_, [], _, _) -> apply handler []
               | _                   -> apply handler [VUnit])
           with exn ->
             Printf.eprintf "signal watcher (code %d) raised: %s\n%!"
               code (Printexc.to_string exn));
          changed := true
        | None -> ()
      end
    done;
    (* Snapshot current pids to avoid issues with new actors spawned mid-pass *)
    let pids = Hashtbl.fold (fun pid _ acc -> pid :: acc) actor_registry [] in
    List.iter (fun pid ->
      match Hashtbl.find_opt actor_registry pid with
      | None -> ()
      | Some inst when not inst.ai_alive -> ()
      | Some inst when Queue.is_empty inst.ai_mailbox -> ()
      | Some inst ->
        let msg = Queue.pop inst.ai_mailbox in
        let (msg_tag, msg_args) = match msg with
          | VCon (tag, args) -> (tag, args)
          | VAtom tag        -> (tag, [])
          | _ ->
            Printf.eprintf "run_scheduler: dropping malformed message from actor %d: %s\n"
              pid (value_to_string msg);
            ("__drop__", [])
        in
        if msg_tag <> "__drop__" then
          (match List.find_opt (fun h -> h.ah_msg.txt = msg_tag)
                   inst.ai_def.actor_handlers with
           | None ->
             (* No handler for this message tag: silently drop *)
             ()
           | Some handler ->
             if List.length handler.ah_params <> List.length msg_args then
               Printf.eprintf "run_scheduler: handler '%s' arity mismatch for actor %d\n%!"
                 msg_tag pid
               (* Arity mismatch: message consumed but actor not crashed.
                  The message is lost and the actor continues with unchanged state.
                  This is intentional: a mismatch is a programming error, but crashing
                  the actor would mask the original bug. *)
             else begin
               let prev_pid = !current_pid in
               current_pid := Some pid;
               let param_bindings =
                 List.map2 (fun p v -> (p.param_name.txt, v))
                   handler.ah_params msg_args
               in
               let handler_env =
                 [("state", inst.ai_state)] @ param_bindings @ !(inst.ai_env_ref)
               in
               (match !eval_expr_hook handler_env handler.ah_body with
                | new_state ->
                  inst.ai_state <- new_state;
                  changed := true   (* mark progress only on success *)
                | exception BlockedOnReceive ->
                  (* The handler called receive() but the mailbox was empty at
                     that point.  Put the triggering message back at the front
                     of the mailbox so the handler retries on a later pass.
                     Do NOT set [changed := true] — no forward progress was made.
                     LIMITATION: only the FIRST receive() call in a handler is
                     safe.  If a handler calls receive() twice and the second one
                     blocks, the first message has already been consumed and is
                     lost — re-queueing only restores the outer message.  Handlers
                     that need multiple messages should use a recursive pattern
                     where each receive() is the first operation in its own
                     handler body. *)
                  let front_q = Queue.create () in
                  Queue.push msg front_q;
                  Queue.transfer inst.ai_mailbox front_q;
                  inst.ai_mailbox <- front_q
                | exception exn ->
                  (* Handler raised an exception: crash the actor.
                     Clear the march stack so leaked frames from this handler
                     don't pollute the backtrace of the next crash. *)
                  clear_march_stack ();
                  crash_actor pid (Printexc.to_string exn));
               current_pid := prev_pid
             end)
    ) pids
  done

let () = run_scheduler_hook := run_scheduler

(* =================================================================
   §11  App / Supervisor machinery
   ================================================================= *)

(** Internal helper: create a task entry for an already-completed result. *)
let make_task_entry tid result thunk =
  { te_id = tid; te_result = result; te_thunk = thunk; te_cancelled = false }

(** Task builtins: spawn, await, await_unwrap, yield, and cancel tokens.
    Placed after [apply] because [task_spawn] calls [apply] to eagerly
    execute the thunk (Phase 1: single-threaded cooperative scheduler). *)
let task_builtins : env =
  [ ("task_spawn", VBuiltin ("task_spawn", function
      | [thunk] ->
        let tid = !next_task_id in
        next_task_id := tid + 1;
        (* Phase 1: eagerly evaluate the thunk.
           Phase 2+ will enqueue on the run queue instead. *)
        (* Thunks are (Int -> a) — pass dummy 0 arg. *)
        let result = apply thunk [VInt 0] in
        let entry = make_task_entry tid (Some result) thunk in
        Hashtbl.add task_registry tid entry;
        VTask tid
      | _ -> eval_error "task_spawn: expected 1 argument (a function)"))

  ; ("task_await", VBuiltin ("task_await", function
      | [VTask tid] ->
        (match Hashtbl.find_opt task_registry tid with
         | Some entry when entry.te_cancelled ->
           VCon ("Err", [VString "cancelled"])
         | Some entry ->
           (match entry.te_result with
            | Some v -> VCon ("Ok", [v])
            | None -> VCon ("Err", [VString "task not completed"]))
         | None -> VCon ("Err", [VString (Printf.sprintf "unknown task %d" tid)]))
      | _ -> eval_error "task_await: expected 1 argument (a Task)"))

  ; ("task_await_unwrap", VBuiltin ("task_await_unwrap", function
      | [VTask tid] ->
        (match Hashtbl.find_opt task_registry tid with
         | Some entry when entry.te_cancelled ->
           eval_error "task_await!: task %d was cancelled" tid
         | Some entry ->
           (match entry.te_result with
            | Some v -> v
            | None -> eval_error "task_await!: task %d not completed" tid)
         | None -> eval_error "task_await!: unknown task %d" tid)
      | _ -> eval_error "task_await!: expected 1 argument (a Task)"))

  ; ("task_yield", VBuiltin ("task_yield", function
      | [] ->
        (* Voluntary yield — exhaust the budget so check_reductions raises Yield.
           When reduction counting is disabled this is a no-op. *)
        (match !reduction_ctx with
         | Some ctx ->
           ctx.March_scheduler.Scheduler.remaining <- 0;
           ignore (March_scheduler.Scheduler.tick ctx)
         | None -> ());
        VUnit
      | _ -> eval_error "task_yield: expected 0 arguments"))

  ; ("task_spawn_steal", VBuiltin ("task_spawn_steal", function
    | [VWorkPool; thunk] ->
      (* Cap(WorkPool) validated — spawn on the stealing pool.
         In Phase 1 (single-threaded), this is equivalent to task_spawn
         but validates the capability requirement. *)
      let tid = !next_task_id in
      next_task_id := tid + 1;
      let result = apply thunk [VInt 0] in
      let entry = make_task_entry tid (Some result) thunk in
      Hashtbl.add task_registry tid entry;
      VTask tid
    | [_; _] ->
      eval_error "task_spawn_steal: first argument must be a Cap(WorkPool)"
    | _ -> eval_error "task_spawn_steal: expected 2 arguments (pool, function)"))

  ; ("task_reductions", VBuiltin ("task_reductions", function
    | [] -> VInt !last_reduction_count
    | _ -> eval_error "task_reductions: expected 0 arguments"))

  ; ("pmap_threshold", VBuiltin ("pmap_threshold", function
    | [] -> VInt !pmap_threshold_value
    | _ -> eval_error "pmap_threshold: expected 0 arguments"))

  (* ── Phase 5B: cancellation token builtins ───────────────────────── *)

  ; ("task_cancel_token_new", VBuiltin ("task_cancel_token_new", function
      | [] -> VCancelToken (ref false)
      | _ -> eval_error "task_cancel_token_new: expected 0 arguments"))

  ; ("task_cancel", VBuiltin ("task_cancel", function
      | [VCancelToken r] -> r := true; VUnit
      | _ -> eval_error "task_cancel: expected 1 argument (a CancelToken)"))

  ; ("task_is_cancelled", VBuiltin ("task_is_cancelled", function
      | [VCancelToken r] -> VBool !r
      | _ -> eval_error "task_is_cancelled: expected 1 argument (a CancelToken)"))

  (* Spawn a task with an associated cancel token.
     In Phase 1 (interpreter): if the token is already cancelled, the task is
     not run and its await returns Err("cancelled").  Otherwise, the task runs
     eagerly as usual. *)
  ; ("task_spawn_with_cancel", VBuiltin ("task_spawn_with_cancel", function
      | [thunk; VCancelToken r] ->
        let tid = !next_task_id in
        next_task_id := tid + 1;
        if !r then begin
          (* Token already cancelled — skip execution, mark as cancelled. *)
          let entry = { (make_task_entry tid None thunk) with te_cancelled = true } in
          Hashtbl.add task_registry tid entry;
          VTask tid
        end else begin
          let result = apply thunk [VInt 0] in
          let entry = make_task_entry tid (Some result) thunk in
          Hashtbl.add task_registry tid entry;
          VTask tid
        end
      | _ -> eval_error "task_spawn_with_cancel: expected (thunk, CancelToken)"))

  (* Cancel a task by id (marks te_cancelled on the registry entry).
     In Phase 1, the task already ran, so this only affects future awaits. *)
  ; ("task_cancel_by_id", VBuiltin ("task_cancel_by_id", function
      | [VTask tid] ->
        (match Hashtbl.find_opt task_registry tid with
         | Some entry -> entry.te_cancelled <- true
         | None -> ());
        VUnit
      | _ -> eval_error "task_cancel_by_id: expected 1 argument (a Task)"))

  ; ("get_work_pool", VWorkPool)
  (* Capability builtins — at runtime caps are opaque unit sentinels *)
  ; ("root_cap",   VUnit)
  ; ("cap_narrow", VBuiltin ("cap_narrow", function
    | [_cap] -> VUnit   (* attenuation is a compile-time check; runtime is a no-op *)
    | _ -> eval_error "cap_narrow: expected 1 argument"))
  (* mint_cap — the gated proof-cap mint. Gating is a compile-time check; at
     runtime it is a no-op alias of cap_narrow (caps are opaque unit sentinels). *)
  ; ("mint_cap", VBuiltin ("mint_cap", function
    | [_cap] -> VUnit
    | _ -> eval_error "mint_cap: expected 1 argument"))

  (* Signal.watch — register/remove a deferred OS-signal watcher.  [code] is
     the stable 0-4 signal code produced by stdlib/signal.march.  The handler
     runs later, from the scheduler drain (see [run_scheduler]); here we only
     record it and (lazily) install the OS handler.  Term/Int (0/1) already
     carry the shutdown handler from [run_module], so we only install/restore
     Hup/Usr1/Usr2 (>= 2) on watch/unwatch to leave their default disposition
     intact when unwatched. *)
  ; ("signal_watch", VBuiltin ("signal_watch", function
      | [VInt code; handler] when code >= 0 && code < 5 ->
        signal_watchers.(code) <- Some handler;
        signal_pending.(code)  <- false;
        signal_seen.(code)     <- false;
        if code >= 2 then
          Sys.set_signal (signal_os_of_code code) (Sys.Signal_handle handle_os_signal);
        VUnit
      | [VInt _; _] -> eval_error "signal_watch: signal code out of range (0-4)"
      | _ -> eval_error "signal_watch: expected (Int, handler)"))
  ; ("signal_unwatch", VBuiltin ("signal_unwatch", function
      | [VInt code] when code >= 0 && code < 5 ->
        signal_watchers.(code) <- None;
        signal_pending.(code)  <- false;
        signal_seen.(code)     <- false;
        if code >= 2 then
          Sys.set_signal (signal_os_of_code code) Sys.Signal_default;
        VUnit
      | [VInt _] -> eval_error "signal_unwatch: signal code out of range (0-4)"
      | _ -> eval_error "signal_unwatch: expected (Int)"))
  ; ("signal_raise_self", VBuiltin ("signal_raise_self", function
      | [VInt code] when code >= 0 && code < 5 ->
        Unix.kill (Unix.getpid ()) (signal_os_of_code code);
        VUnit
      | [VInt _] -> eval_error "signal_raise_self: signal code out of range (0-4)"
      | _ -> eval_error "signal_raise_self: expected (Int)"))

  (* Phase 5: task_spawn_link — spawn a task linked to an actor pid.
     If the linked actor crashes, the task is cancelled (or vice versa). *)
  (* App/Supervisor builtins *)
  ; ("worker", VBuiltin ("worker", function
      | [VCon (name, [])] ->
        VRecord [("actor", VString name); ("restart", VAtom "permanent")]
      | [VString name] ->
        VRecord [("actor", VString name); ("restart", VAtom "permanent")]
      (* Two-arg form: worker(Name, :restart_policy) or worker(Name, :registered_name).
         Restart policies (:permanent, :temporary, :transient) set the restart field.
         Any other atom is treated as a registered process name. *)
      | [VCon (name, []); VAtom arg] ->
        (match arg with
         | "permanent" | "temporary" | "transient" ->
           VRecord [("actor", VString name); ("restart", VAtom arg)]
         | atom_name ->
           VRecord [("actor", VString name); ("restart", VAtom "permanent");
                    ("name", VAtom atom_name)])
      | [VString name; VAtom arg] ->
        (match arg with
         | "permanent" | "temporary" | "transient" ->
           VRecord [("actor", VString name); ("restart", VAtom arg)]
         | atom_name ->
           VRecord [("actor", VString name); ("restart", VAtom "permanent");
                    ("name", VAtom atom_name)])
      (* Three-arg form: worker(Name, :policy, {name: :my_svc}) *)
      | [VCon (name, []); VAtom policy; VRecord opts] ->
        let base = [("actor", VString name); ("restart", VAtom policy)] in
        let with_name = match List.assoc_opt "name" opts with
          | Some (VAtom n) -> ("name", VAtom n) :: base
          | _ -> base in
        VRecord with_name
      | [VString name; VAtom policy; VRecord opts] ->
        let base = [("actor", VString name); ("restart", VAtom policy)] in
        let with_name = match List.assoc_opt "name" opts with
          | Some (VAtom n) -> ("name", VAtom n) :: base
          | _ -> base in
        VRecord with_name
      | _ -> eval_error "worker: expected an actor name, or (name, :policy), or (name, :policy, opts)"))

  ; ("Supervisor.spec", VBuiltin ("Supervisor.spec", function
      | [strategy; children] ->
        VRecord [("strategy", strategy); ("children", children)]
      | _ -> eval_error "Supervisor.spec: expected (strategy, children)"))

  ; ("App.stop", VBuiltin ("App.stop", function
      | [] | [VUnit] ->
        shutdown_requested := true;
        VUnit
      | _ -> eval_error "App.stop: expected no arguments"))


  (* Process registry: whereis returns Option(Pid); whereis_bang crashes if missing *)
  ; ("whereis", VBuiltin ("whereis", function
      | [VAtom name] ->
        (match Hashtbl.find_opt process_registry name with
         | Some pid when (match Hashtbl.find_opt actor_registry pid with
                          | Some inst -> inst.ai_alive
                          | None -> false) ->
           VCon ("Some", [VPid pid])
         | _ -> VCon ("None", []))
      | _ -> eval_error "whereis: expected atom argument"))

  ; ("App.whereis", VBuiltin ("App.whereis", function
      | [VAtom name] ->
        (match Hashtbl.find_opt process_registry name with
         | Some pid when (match Hashtbl.find_opt actor_registry pid with
                          | Some inst -> inst.ai_alive
                          | None -> false) ->
           VCon ("Some", [VPid pid])
         | _ -> VCon ("None", []))
      | _ -> eval_error "App.whereis: expected atom argument"))

  ; ("whereis_bang", VBuiltin ("whereis_bang", function
      | [VAtom name] ->
        (match Hashtbl.find_opt process_registry name with
         | Some pid when (match Hashtbl.find_opt actor_registry pid with
                          | Some inst -> inst.ai_alive
                          | None -> false) ->
           VPid pid
         | _ -> eval_error "whereis!: no alive process named :%s" name)
      | _ -> eval_error "whereis_bang: expected atom argument"))

  ; ("App.whereis_bang", VBuiltin ("App.whereis_bang", function
      | [VAtom name] ->
        (match Hashtbl.find_opt process_registry name with
         | Some pid when (match Hashtbl.find_opt actor_registry pid with
                          | Some inst -> inst.ai_alive
                          | None -> false) ->
           VPid pid
         | _ -> eval_error "whereis!: no alive process named :%s" name)
      | _ -> eval_error "App.whereis_bang: expected atom argument"))

  (* Dynamic supervisor: dynamic_supervisor(:name, :strategy) *)
  ; ("dynamic_supervisor", VBuiltin ("dynamic_supervisor", function
      | [VAtom name; strategy] ->
        let strat_str = match strategy with
          | VAtom s -> s | VCon (s, []) -> String.lowercase_ascii s | _ -> "one_for_one" in
        let vpid = !dyn_sup_next_vpid in
        dyn_sup_next_vpid := vpid - 1;
        let ds = { ds_name = name; ds_strategy = strat_str;
                   ds_max_restarts = 10; ds_window_secs = 60;
                   ds_vpid = vpid;
                   ds_children = []; ds_restart_count = [] } in
        Hashtbl.replace dyn_sup_registry name ds;
        Hashtbl.replace dyn_sup_vpid_map vpid name;
        VRecord [("type", VString "dynamic_supervisor"); ("name", VAtom name); ("vpid", VInt vpid)]
      | [VAtom name; strategy; VRecord opts] ->
        let strat_str = match strategy with
          | VAtom s -> s | VCon (s, []) -> String.lowercase_ascii s | _ -> "one_for_one" in
        let max_r = match List.assoc_opt "max_restarts" opts with
          | Some (VInt n) -> n | _ -> 10 in
        let window = match List.assoc_opt "within" opts with
          | Some (VInt n) -> n | _ -> 60 in
        let vpid = !dyn_sup_next_vpid in
        dyn_sup_next_vpid := vpid - 1;
        let ds = { ds_name = name; ds_strategy = strat_str;
                   ds_max_restarts = max_r; ds_window_secs = window;
                   ds_vpid = vpid;
                   ds_children = []; ds_restart_count = [] } in
        Hashtbl.replace dyn_sup_registry name ds;
        Hashtbl.replace dyn_sup_vpid_map vpid name;
        VRecord [("type", VString "dynamic_supervisor"); ("name", VAtom name); ("vpid", VInt vpid)]
      | _ -> eval_error "dynamic_supervisor: expected (name, strategy) or (name, strategy, opts)"))

  (* Supervisor.start_child(:sup_name, child_spec) : Result(Pid, String) *)
  ; ("Supervisor.start_child", VBuiltin ("Supervisor.start_child", function
      | [VAtom sup_name; VRecord spec_fields] ->
        (match Hashtbl.find_opt dyn_sup_registry sup_name with
         | None -> VCon ("Err", [VString ("no dynamic supervisor named :" ^ sup_name)])
         | Some ds ->
           let actor_name = match List.assoc_opt "actor" spec_fields with
             | Some (VString s) -> s
             | _ -> "" in
           let restart_pol = match List.assoc_opt "restart" spec_fields with
             | Some (VAtom s) -> s | _ -> "permanent" in
           if actor_name = "" then
             VCon ("Err", [VString "start_child: spec missing actor field"])
           else begin
             let new_pid = spawn_child_actor actor_name ds.ds_vpid in
             let entry = { dce_pid = new_pid; dce_actor_name = actor_name;
                           dce_restart = restart_pol } in
             ds.ds_children <- entry :: ds.ds_children;
             VCon ("Ok", [VInt new_pid])
           end)
      | _ -> eval_error "Supervisor.start_child: expected (atom, child_spec)"))

  (* Supervisor.stop_child(:sup_name, pid) : Result(Unit, String) *)
  ; ("Supervisor.stop_child", VBuiltin ("Supervisor.stop_child", function
      | [VAtom sup_name; VInt pid] ->
        (match Hashtbl.find_opt dyn_sup_registry sup_name with
         | None -> VCon ("Err", [VString ("no dynamic supervisor named :" ^ sup_name)])
         | Some ds ->
           (match List.find_opt (fun e -> e.dce_pid = pid) ds.ds_children with
            | None -> VCon ("Err", [VString "stop_child: pid not found"])
            | Some entry ->
              (* Detach from supervisor first to prevent restart *)
              (match Hashtbl.find_opt actor_registry entry.dce_pid with
               | Some inst -> inst.ai_supervisor <- None
               | None -> ());
              ds.ds_children <- List.filter (fun e -> e.dce_pid <> pid) ds.ds_children;
              crash_actor pid "stop_child";
              VCon ("Ok", [VUnit])))
      | _ -> eval_error "Supervisor.stop_child: expected (atom, pid)"))

  (* Supervisor.which_children(:sup_name) : List({pid, actor, restart}) *)
  ; ("Supervisor.which_children", VBuiltin ("Supervisor.which_children", function
      | [VAtom sup_name] ->
        (match Hashtbl.find_opt dyn_sup_registry sup_name with
         | None -> VCon ("Nil", [])
         | Some ds ->
           let make_rec e =
             VRecord [("pid",    VInt e.dce_pid);
                      ("actor",  VString e.dce_actor_name);
                      ("restart", VAtom e.dce_restart)] in
           List.fold_right
             (fun e acc -> VCon ("Cons", [make_rec e; acc]))
             ds.ds_children (VCon ("Nil", [])))
      | _ -> eval_error "Supervisor.which_children: expected (atom)"))

  (* Supervisor.count_children(:sup_name) : {active: Int, specs: Int} *)
  ; ("Supervisor.count_children", VBuiltin ("Supervisor.count_children", function
      | [VAtom sup_name] ->
        (match Hashtbl.find_opt dyn_sup_registry sup_name with
         | None -> VRecord [("active", VInt 0); ("specs", VInt 0)]
         | Some ds ->
           let total = List.length ds.ds_children in
           let active = List.length (List.filter (fun e ->
             match Hashtbl.find_opt actor_registry e.dce_pid with
             | Some inst -> inst.ai_alive | None -> false) ds.ds_children) in
           VRecord [("active", VInt active); ("specs", VInt total)])
      | _ -> eval_error "Supervisor.count_children: expected (atom)"))

  ; ("task_spawn_link", VBuiltin ("task_spawn_link", function
    | [thunk; VPid linked_pid] ->
      let tid = !next_task_id in
      next_task_id := tid + 1;
      (* Check if linked actor is still alive before running *)
      let linked_alive = match Hashtbl.find_opt actor_registry linked_pid with
        | Some inst -> inst.ai_alive
        | None -> false
      in
      if not linked_alive then begin
        (* Linked actor already dead — task fails immediately *)
        let entry = make_task_entry tid
                      (Some (VCon ("Err", [VString "linked actor dead"]))) thunk in
        Hashtbl.add task_registry tid entry;
        VTask tid
      end else begin
        (* Eagerly execute the thunk (Phase 1: single-threaded) *)
        let result =
          (try
             let v = apply thunk [VInt 0] in
             v
           with exn ->
             (* Task raised an exception: crash the linked actor *)
             (match Hashtbl.find_opt actor_registry linked_pid with
              | Some inst when inst.ai_alive ->
                crash_actor linked_pid
                  (Printf.sprintf "linked task raised: %s" (Printexc.to_string exn))
              | _ -> ());
             raise exn)
        in
        let entry = make_task_entry tid (Some result) thunk in
        Hashtbl.add task_registry tid entry;
        VTask tid
      end
    | _ -> eval_error "task_spawn_link: expected (thunk, Pid)"))
  ]

(** Run [thunk] (a zero-argument closure) while counting reductions.
    Returns [(result, reductions_consumed)].  The count is also stored in
    [last_reduction_count] so that the [task_reductions] builtin can read it. *)
let eval_with_reduction_tracking (thunk : value) : value * int =
  let ctx = March_scheduler.Scheduler.create_reduction_ctx () in
  reduction_ctx := Some ctx;
  let result = apply thunk [] in
  let consumed = March_scheduler.Scheduler.max_reductions - ctx.March_scheduler.Scheduler.remaining in
  reduction_ctx := None;
  last_reduction_count := consumed;
  (result, consumed)

(* =================================================================
   §12  App / Supervisor machinery
   ================================================================= *)

(** Convert a March list value (VCon Cons/Nil) to an OCaml list of values. *)
let rec march_list_to_list = function
  | VCon ("Nil", []) -> []
  | VCon ("Cons", [h; t]) -> h :: march_list_to_list t
  | v -> eval_error "march_list_to_list: expected list, got %s" (value_to_string v)

(** Send [Shutdown()] to [pid], run one scheduler pass to execute the handler
    if defined, then force-kill the actor regardless. *)
let shutdown_actor_pid (pid : int) : unit =
  match Hashtbl.find_opt actor_registry pid with
  | None -> ()
  | Some inst when not inst.ai_alive -> ()
  | Some inst ->
    (* Enqueue Shutdown() message *)
    Queue.push (VCon ("Shutdown", [])) inst.ai_mailbox;
    (* Process one message from this actor's mailbox (the Shutdown we just queued) *)
    if not (Queue.is_empty inst.ai_mailbox) then begin
      let msg = Queue.pop inst.ai_mailbox in
      let (msg_tag, msg_args) = match msg with
        | VCon (tag, args) -> (tag, args)
        | VAtom tag        -> (tag, [])
        | _                -> ("__drop__", [])
      in
      if msg_tag <> "__drop__" then begin
        match List.find_opt (fun h -> h.ah_msg.txt = msg_tag)
                inst.ai_def.actor_handlers with
        | None -> ()  (* No Shutdown handler: fall through to force-kill *)
        | Some handler ->
          if List.length handler.ah_params = List.length msg_args then begin
            let prev_pid = !current_pid in
            current_pid := Some pid;
            let param_bindings =
              List.map2 (fun p v -> (p.param_name.txt, v))
                handler.ah_params msg_args
            in
            let handler_env =
              [("state", inst.ai_state)] @ param_bindings @ !(inst.ai_env_ref)
            in
            (match !eval_expr_hook handler_env handler.ah_body with
             | new_state -> inst.ai_state <- new_state
             | exception _ -> ());
            current_pid := prev_pid
          end
      end
    end;
    (* Force-kill the actor. Deliberately bypasses crash_actor (and so its
       Task 5 named_registry retire mirror too): this is process-teardown-
       only, called from graceful_shutdown as the app exits, with no
       watcher left to observe a stale name and no further named_registry
       lookups expected afterward — not an oversight. *)
    (match Hashtbl.find_opt actor_registry pid with
     | Some inst2 ->
       inst2.ai_terminal_reason <- Normal;
       inst2.ai_alive <- false
     | None -> ())

(** Graceful shutdown: stop all app-level children in reverse spawn order. *)
let graceful_shutdown () : unit =
  let pids_rev = List.rev !app_spawn_order in
  List.iter shutdown_actor_pid pids_rev;
  app_spawn_order := []

(** Spawn all children described in a supervisor spec record.
    Spec shape: { strategy = :one_for_one, children = [ChildSpec, ...] }
    ChildSpec shape: { actor = "Name", restart = :permanent }
    Records spawn order in [app_spawn_order]. *)
let spawn_from_spec (spec : value) : unit =
  match spec with
  | VRecord fields ->
    let children_val = match List.assoc_opt "children" fields with
      | Some v -> v
      | None -> eval_error "spawn_from_spec: spec missing 'children' field"
    in
    let children = march_list_to_list children_val in
    List.iter (fun child ->
      match child with
      | VRecord child_fields ->
        (* Dynamic supervisor specs are pre-registered; skip spawning an actor for them *)
        (match List.assoc_opt "type" child_fields with
         | Some (VString "dynamic_supervisor") -> ()
         | _ ->
           let actor_name = match List.assoc_opt "actor" child_fields with
             | Some (VString s) -> s
             | Some other -> eval_error "spawn_from_spec: actor field should be a string, got %s"
                               (value_to_string other)
             | None -> eval_error "spawn_from_spec: child spec missing 'actor' field"
           in
           (match Hashtbl.find_opt actor_defs_tbl actor_name with
            | None -> eval_error "spawn_from_spec: unknown actor '%s'" actor_name
            | Some (def, env_ref) ->
              let pid = !next_pid in
              next_pid := pid + 1;
              let init_state = eval_expr !env_ref def.actor_init in
              let inst = {
                ai_name = actor_name; ai_def = def; ai_env_ref = env_ref;
                ai_state = init_state; ai_alive = true;
                ai_terminal_reason = Normal;
                ai_monitors = []; ai_mailbox = Queue.create ();
                ai_supervisor = None; ai_restart_count = []; ai_epoch = 0;
                ai_resources = []; ai_linear_values = [];
                ai_mbox_limit = 0; ai_mbox_policy = 0 } in
              Hashtbl.add actor_registry pid inst;
              app_spawn_order := !app_spawn_order @ [pid];
              (* Register named children in the process registry *)
              (match List.assoc_opt "name" child_fields with
               | Some (VAtom atom_name) ->
                 Hashtbl.replace process_registry atom_name pid;
                 Hashtbl.replace pid_to_registry_name pid atom_name
               | _ -> ())))
      | other -> eval_error "spawn_from_spec: expected child spec record, got %s"
                   (value_to_string other)
    ) children
  | other -> eval_error "spawn_from_spec: expected supervisor spec record, got %s"
               (value_to_string other)

(* =================================================================
   §13  Module evaluation
   ================================================================= *)

(** A mutable stub: lets us install a forward reference for a name and
    later fill it with the real closure. *)
type stub = { mutable sv : value }

(** Evaluate a single declaration, extending [env].
    Returns the updated environment. *)
let rec eval_decl (env : env) (d : decl) : env =
  match d with
  | DFn (def, _) ->
    (* Register doc string if present *)
    (match def.fn_doc with
     | Some s -> Hashtbl.replace doc_registry (current_doc_prefix () ^ def.fn_name.txt) s
     | None   -> ());
    let clause = match def.fn_clauses with
      | [c] -> c
      | _   -> eval_error "fn %s: expected exactly one clause after desugaring"
                  def.fn_name.txt
    in
    let params = clause_params clause in
    let arity = List.length params in
    (* Use a mutable env ref so the closure can call itself recursively.
       When [rec_closure] is invoked, [env_ref] already contains the
       function's own name, making self-recursion work in the REPL. *)
    let env_ref = ref env in
    let rec_name = Printf.sprintf "<rec:%s/%d>" def.fn_name.txt arity in
    (* Captured at THIS declaration's processing point (eager, module_stack
       correct here) — see [VClosure]'s doc comment. *)
    let defn_prefix = effective_module_prefix () in
    let rec_closure = VBuiltin (rec_name,
                                fun args ->
                                  let call_env = !env_ref in
                                  let fn_v = VClosure (call_env, params, clause.fc_body, defn_prefix) in
                                  apply fn_v args) in
    let env' = (def.fn_name.txt, rec_closure)
               :: List.remove_assoc def.fn_name.txt env in
    env_ref := env';
    env'

  | DLet (_, b, _) ->
    let v = eval_expr env b.bind_expr in
    (match match_pattern v b.bind_pat with
     | Some bs -> bs @ env
     | None    -> eval_error "top-level let binding pattern failed")

  | DType (_, name, _, td, _) ->
    (* Populate ctor_type_tbl so dispatch can find the type from a constructor value. *)
    (match td with
     | TDVariant variants -> register_type_ctors name.txt variants
     | TDRecord fields ->
       (* Register record type by its field names for Json derive dispatch *)
       let field_names = List.map (fun (f : field) -> f.fld_name.txt) fields in
       let key = String.concat "," (List.sort String.compare field_names) in
       Hashtbl.replace record_type_tbl key name.txt
     | _ -> ());
    (* Also register in ffi_type_decl_tbl so the FFI marshal layer can look up
       field/ctor types for record and variant arguments. A `resource Foo`
       declaration desugars to TDVariant [] (see resource_decl in parser.mly);
       mark such names in ffi_resource_tbl so the marshal layer treats them as
       opaque handles instead of zero-case variants. *)
    (match td with
     | TDVariant [] -> Hashtbl.replace ffi_resource_tbl name.txt ()
     | TDVariant _ | TDRecord _ -> Hashtbl.replace ffi_type_decl_tbl name.txt td
     | _ -> ());
    env

  | DActor (_, name, def, _) ->
    (* Register actor definition so spawn() can find it later.
       Also register under the qualified name (e.g. "ActorDemo.Counter") so
       that spawn(ActorDemo.Counter) works when the actor is defined inside a
       module — the desugar pass turns A.B into ECon("A.B") which becomes the
       actor_name used in ESpawn. *)
    let env_ref = ref env in
    Hashtbl.replace actor_defs_tbl name.txt (def, env_ref);
    let qual = current_doc_prefix () ^ name.txt in
    if qual <> name.txt then
      Hashtbl.replace actor_defs_tbl qual (def, env_ref);
    env

  | DMod (name, _, decls, _) ->
    (* Evaluate nested module; bindings are prefixed with "ModName." *)
    module_stack := name.txt :: !module_stack;
    (* Two-pass evaluation for inner decls so recursive/mutual fns work *)
    let inner_ref = ref env in
    List.iter (function
      | DFn (def, _) ->
        let stub = VBuiltin ("<stub:" ^ def.fn_name.txt ^ ">",
                             fun _ -> eval_error "stub %s called before initialisation"
                                 def.fn_name.txt) in
        inner_ref := (def.fn_name.txt, stub) :: !inner_ref
      | _ -> ()
    ) decls;
    let rec eval_mod_decls ds e =
      match ds with
      | [] -> e
      | DFn (def, _) :: rest ->
        (match def.fn_doc with
         | Some s -> Hashtbl.replace doc_registry (current_doc_prefix () ^ def.fn_name.txt) s
         | None   -> ());
        let clause = match def.fn_clauses with
          | [c] -> c
          | _   -> eval_error "fn %s: expected one clause after desugaring"
                       def.fn_name.txt
        in
        let params = clause_params clause in
        let arity = List.length params in
        let rec_name = Printf.sprintf "<rec:%s/%d>" def.fn_name.txt arity in
        (* Captured here (module_stack is correctly ["name.txt"; …] at this
           point in the walk) — see [VClosure]'s doc comment. *)
        let defn_prefix = effective_module_prefix () in
        let rec_closure = VBuiltin (rec_name,
                                    fun args ->
                                      let call_env = !inner_ref in
                                      let fn_v = VClosure (call_env, params, clause.fc_body, defn_prefix) in
                                      apply fn_v args) in
        let parse_rec_arity n =
          match String.rindex_opt n '/' with
          | None -> None
          | Some i ->
            (try Some (int_of_string (String.sub n (i+1) (String.length n - i - 2)))
             with _ -> None)
        in
        let combined =
          match List.assoc_opt def.fn_name.txt e with
          | Some (VMultiarity variants) ->
            VMultiarity ((arity, rec_closure) :: List.remove_assoc arity variants)
          | Some (VBuiltin (n, _) as prev) when parse_rec_arity n <> None ->
            let prev_arity = Option.get (parse_rec_arity n) in
            VMultiarity [(arity, rec_closure); (prev_arity, prev)]
          | _ -> rec_closure
        in
        let e' = (def.fn_name.txt, combined)
                   :: List.remove_assoc def.fn_name.txt e in
        (* Default-arg base-name reconstruction for a NESTED-module member:
           a mangled `foo$N` also registers under the base name `foo` as a
           VMultiarity so a reduced-arity call `Inner.foo(x)` dispatches by
           arity — mirrors the same reconstruction [make_recursive_env] does
           for top-level default-arg fns. Without this, nested default-arg fns
           are callable compiled (TIR _default_dispatch) but not interpreted. *)
        let e'' =
          match String.rindex_opt def.fn_name.txt '$' with
          | Some dollar_pos when dollar_pos > 0 ->
            let base = String.sub def.fn_name.txt 0 dollar_pos in
            let suffix = String.sub def.fn_name.txt (dollar_pos + 1)
                           (String.length def.fn_name.txt - dollar_pos - 1) in
            (match int_of_string_opt suffix with
             | Some _ ->
               let existing = match List.assoc_opt base e' with
                 | Some (VMultiarity vs) -> vs
                 | _ -> [] in
               let base_v = VMultiarity
                 ((arity, rec_closure) :: List.remove_assoc arity existing) in
               (base, base_v) :: List.remove_assoc base e'
             | None -> e')
          | _ -> e'
        in
        inner_ref := e'';
        eval_mod_decls rest e''
      | d :: rest ->
        let e' = eval_decl e d in
        inner_ref := e';
        eval_mod_decls rest e'
    in
    let mod_env = eval_mod_decls decls !inner_ref in
    module_stack := List.tl !module_stack;
    (* Collect names actually defined by this module's declarations
       (DFn, DLet top bindings, nested DMod names).  We only expose
       these under the qualified prefix, not inherited outer bindings. *)
    let rec declared_names acc = function
      | [] -> acc
      | DFn (def, _) :: rest ->
        let nm = def.fn_name.txt in
        let acc = nm :: acc in
        (* A mangled default-arg decl `foo$N` also exposes its base name `foo`
           so the reconstructed `Inner.foo` VMultiarity (bound in the module
           env above) is prefixed/exported for a reduced-arity call. *)
        let acc =
          match String.rindex_opt nm '$' with
          | Some i when i > 0 &&
                        (match int_of_string_opt
                                 (String.sub nm (i + 1) (String.length nm - i - 1))
                         with Some _ -> true | None -> false) ->
            String.sub nm 0 i :: acc
          | _ -> acc
        in
        declared_names acc rest
      | DLet (_, b, _) :: rest ->
        let rec pat_names a = function
          | PatVar n -> n.txt :: a
          | PatTuple (ps, _) -> List.fold_left pat_names a ps
          | PatCon (_, ps) -> List.fold_left pat_names a ps
          | _ -> a
        in
        declared_names (pat_names acc b.bind_pat) rest
      | DMod (n, _, _, _) :: rest -> declared_names (n.txt :: acc) rest
      | DExtern (edef, _) :: rest ->
        let names = List.map (fun (ef : extern_fn) -> ef.ef_name.txt) edef.ext_fns in
        declared_names (names @ acc) rest
      | _ :: rest -> declared_names acc rest
    in
    let own_names = declared_names [] decls in
    (* Also export keys like "B.f" when "B" is a declared sub-module *)
    let is_own_key k =
      List.exists (fun n ->
        k = n ||
        (String.length k > String.length n + 1 &&
         String.sub k 0 (String.length n + 1) = n ^ ".")
      ) own_names
    in
    let prefixed_raw = List.filter_map (fun (k, v) ->
        if is_own_key k
        then Some (name.txt ^ "." ^ k, v)
        else None
      ) mod_env in
    (* Deduplicate: mod_env is an assoc list with most-recently-bound entries
       first, so inherited outer bindings that share a name with a module-local
       fn appear after the module-local one.  Keep only the first occurrence of
       each key so that e.g. "MyNet.connect" maps to MyNet's own closure, not
       the outer module's "connect" that leaked in via inner_ref. *)
    let seen_keys = Hashtbl.create 8 in
    let prefixed = List.filter_map (fun (k, v) ->
        if Hashtbl.mem seen_keys k then None
        else begin Hashtbl.replace seen_keys k (); Some (k, v) end
      ) prefixed_raw in
    (* Register in the global module registry so that cross-module
       qualified lookups (EField) can find these bindings at call time
       even if the referencing module was evaluated before this one. *)
    List.iter (fun (k, v) -> Hashtbl.replace module_registry k v) prefixed;
    prefixed @ env

  | DImpl (idef, sp) ->
    (* Evaluate each impl method so they become callable at runtime.
       Default methods injected by the desugar pass have fc_params=[] and a
       lambda body; evaluate the body directly and bind the resulting value.
       Phase 6b: also populate impl_tbl so the `own` builtin can resolve drop fns. *)
    let type_name = match idef.impl_ty with
      | TyCon (n, _) -> n.txt
      | TyVar n      -> n.txt
      | _            -> ""
    in
    (* Declaring-module-qualified identity for [iface_method_tbl] ONLY, when
       [type_name]'s short name collides (see [type_collision_set]) — e.g.
       "NA.Thing" vs "NB.Thing" so each same-short-name type's general-interface
       impl gets its own dispatch-table slot instead of overwriting the
       other's (Hashtbl.replace on a shared bare key). [impl_tbl] below keeps
       using bare [type_name] unchanged (see [ctor_qualified_type_tbl]'s doc
       comment for why qualifying it in place would be unsafe there). *)
    let dispatch_type_name =
      if type_name <> "" && is_colliding_type_name type_name
      then current_doc_prefix () ^ type_name
      else type_name
    in
    let is_json_iface =
      String.length idef.impl_iface.txt >= 4
      && String.sub idef.impl_iface.txt 0 4 = "Json"
    in
    List.fold_left (fun env (mname, fn_def) ->
        (* Type-dispatched methods (show/eq/compare/hash) use a
           non-self-referential closure so recursive calls inside the body go
           through the builtin dispatch (impl_tbl), not back to this impl. *)
        let is_dispatched =
          is_type_dispatched_method idef.impl_iface.txt mname.txt
        in
        (* General (non-type-dispatched-builtin, non-JSON) interface: same
           self-recursion hazard as show/eq/compare/hash above, but the
           dispatch route is the ad-hoc per-(iface,method) [iface_method_tbl]
           dispatcher below rather than a baked-in builtin. A compositional
           impl body (e.g. `MyEq(Wrap(a)) when MyEq(a)`'s `eq` calling `eq` on
           the unwrapped value) must re-dispatch by the runtime type of THAT
           call's arguments, not recurse back into this impl — so its closure
           must be built non-self-referentially too, over an environment
           where [mname.txt] is bound to the dispatcher. The dispatcher is
           created here (idempotently — reused if a prior impl of this method
           already built one) rather than only in the env-threading step
           below, so this works regardless of impl declaration order: a
           closure built while processing the FIRST impl of a method must
           already see the dispatcher, not just closures built afterward. *)
        let is_general_iface =
          (not (is_type_dispatched_iface idef.impl_iface.txt)) && not is_json_iface
        in
        let disp_tag = "$dispatch$" ^ idef.impl_iface.txt ^ "$" ^ mname.txt in
        let disp =
          if not is_general_iface then None
          else
            match List.assoc_opt mname.txt env with
            | Some (VBuiltin (n, _) as d) when n = disp_tag -> Some d
            | _ ->
              let iface = idef.impl_iface.txt in
              Some (VBuiltin (disp_tag, fun args ->
                  match args with
                  | arg0 :: _ ->
                    (match dispatch_type_name_of_value arg0 with
                     | Some tname ->
                       (match Hashtbl.find_opt iface_method_tbl (iface, mname.txt, tname) with
                        | Some m -> !iface_dispatch_hook m args
                        | None -> eval_error
                            "no implementation of interface `%s` for type `%s`" iface tname)
                     | None -> eval_error
                         "cannot dispatch interface method `%s`: argument has no dispatchable type" mname.txt)
                  | [] -> eval_error
                      "interface method `%s` called with no arguments" mname.txt))
        in
        let env_for_body = match disp with
          | Some d -> (mname.txt, d) :: List.remove_assoc mname.txt env
          | None -> env
        in
        let new_env = match fn_def.fn_clauses with
          | [{ fc_params = []; fc_body; _ }] ->
            let v = eval_expr env fc_body in
            (mname.txt, v) :: env
          | _ when is_dispatched ->
            (* Plain closure: method name in body → builtin dispatch, not self. *)
            let clause = List.hd fn_def.fn_clauses in
            let params = clause_params clause in
            let clo = VClosure (env, params, clause.fc_body, effective_module_prefix ()) in
            (mname.txt, clo) :: env
          | _ when is_general_iface ->
            (* Plain closure over [env_for_body]: method name in body →
               dispatcher, not self (see comment above). *)
            let clause = List.hd fn_def.fn_clauses in
            let params = clause_params clause in
            let clo = VClosure (env_for_body, params, clause.fc_body, effective_module_prefix ()) in
            (mname.txt, clo) :: env
          | _ ->
            eval_decl env (DFn (fn_def, sp))
        in
        (* Phase 6b: register in impl_tbl for own() resolution, and also
           register under "InterfaceName.MethodName" in module_registry so
           that fully-qualified interface calls like "Conduit.Storage.checkpoint_get"
           can be resolved via the lookup fallback (which strips module prefixes). *)
        if type_name <> "" then begin
          match List.assoc_opt mname.txt new_env with
          | Some fn_val ->
            (* For a type-dispatched interface, only its single dispatch method
               may claim the shared (iface, type) key; extra methods (e.g. Eq's
               default `neq`) must not clobber it, or builtin dispatch invokes
               the wrong method and recurses forever (neq → eq → neq). *)
            if (not (is_type_dispatched_iface idef.impl_iface.txt)) || is_dispatched then
              Hashtbl.replace impl_tbl (idef.impl_iface.txt, type_name) fn_val;
            (* General (non-builtin, non-Json) interface methods also go in the
               per-method dispatch table so a call routes by the first arg's
               runtime type, not the last-bound name (fixes multi-impl dispatch,
               e.g. Speak(Dog) + Speak(Cat), and — via [dispatch_type_name] —
               Speak(NA.Thing) + Speak(NB.Thing)). *)
            if not (is_type_dispatched_iface idef.impl_iface.txt) && not is_json_iface then
              Hashtbl.replace iface_method_tbl
                (idef.impl_iface.txt, mname.txt, dispatch_type_name) fn_val;
            let iface_qualified = idef.impl_iface.txt ^ "." ^ mname.txt in
            Hashtbl.replace module_registry iface_qualified fn_val
          | None -> ()
        end;
        (* For Json derive: to_json only registers in impl_tbl (so the
           builtin dispatcher can route by value type); from_json binds in
           env (since we can't dispatch on the target type from a JsonValue).
           For type-dispatched methods (show/eq/compare/hash) the builtin
           dispatches through impl_tbl, so binding the bare name in the env
           would shadow the builtin and break dispatch when 2+ impls exist. *)
        if (is_json_iface && mname.txt = "to_json") || is_dispatched then env
        else if is_json_iface then new_env  (* from_json &c.: name-bound (dispatch is on return type) *)
        else if is_type_dispatched_iface idef.impl_iface.txt then new_env
          (* A NON-dispatch method (e.g. a user `interface Eq`'s default `neq`)
             of a builtin-named interface: bind the concrete method by name. *)
        else
          (* General interface method: bind the TYPE-DISPATCHER (computed
             above — routes by arg0's runtime type via iface_method_tbl)
             instead of the concrete method, so 2+ impls dispatch by type
             rather than last-binding-wins. [disp] is reused as-is (not
             recreated) when a prior impl already bound this exact dispatcher. *)
          match disp with
          | Some d -> (mname.txt, d) :: List.remove_assoc mname.txt env
          | None -> env  (* unreachable: is_general_iface is true on this branch *)
      ) env idef.impl_methods

  | DProtocol (name, pdef, _sp) ->
    (* Register the protocol roles so MPST.new can create the right endpoints. *)
    let rec collect_roles acc = function
      | [] -> acc
      | ProtoMsg (s, r, _) :: rest ->
        collect_roles (s.txt :: r.txt :: acc) rest
      | ProtoLoop steps :: rest ->
        collect_roles (collect_roles acc steps) rest
      | ProtoChoice (ch, branches) :: rest ->
        let branch_roles = List.concat_map (fun (_, steps) ->
            collect_roles [] steps) branches in
        collect_roles (ch.txt :: branch_roles @ acc) rest
      | ProtoStop _ :: rest -> collect_roles acc rest
    in
    let roles = List.sort_uniq String.compare
        (collect_roles [] pdef.proto_steps) in
    Hashtbl.replace protocol_roles_tbl name.txt roles;
    env

  | DSig _ | DInterface _ | DNeeds _ | DProofCap _ | DTransitions _ | DOpts _ -> env

  | DAlwaysLinearType (_, name, _, td, _) ->
    (* Treat like DType at runtime — register constructors/records for dispatch. *)
    (match td with
     | TDVariant variants -> register_type_ctors name.txt variants
     | TDRecord fields ->
       let field_names = List.map (fun (f : field) -> f.fld_name.txt) fields in
       let key = String.concat "," (List.sort String.compare field_names) in
       Hashtbl.replace record_type_tbl key name.txt
     | _ -> ());
    (* resource Foo desugars to TDVariant []; see comment at ffi_resource_tbl.
       always_linear types can't currently arise from `resource` declarations
       (resource_decl only produces DType), but handle it the same way as the
       other two registration sites for defense in depth. *)
    (match td with
     | TDVariant [] -> Hashtbl.replace ffi_resource_tbl name.txt ()
     | TDVariant _ | TDRecord _ -> Hashtbl.replace ffi_type_decl_tbl name.txt td
     | _ -> ());
    env

  | DExtern (edef, _sp) ->
    (* Bind each extern function name to a VForeign stub carrying its signature
       (param types + return type) for interpreter-side marshalling. *)
    List.fold_left (fun env' (ef : extern_fn) ->
      let sym = match ef.ef_symbol with
        | Some s -> s
        | None   -> edef.ext_lib_name ^ "_" ^ ef.ef_name.txt in
      let param_tys = List.map snd ef.ef_params in
      let stub = VForeign (edef.ext_lib_name, sym, ef.ef_raises, param_tys, ef.ef_ret_ty) in
      (ef.ef_name.txt, stub) :: env'
    ) env edef.ext_fns

  | DDeriving _ ->
    (* DDeriving is expanded to DImpl blocks by the desugar pass; skip here. *)
    env

  | DSatisfy _ ->
    (* DSatisfy is expanded to DImpl blocks by the desugar pass; skip here. *)
    env

  | DApp _ ->
    (* DApp is desugared to DFn(__app_init__) before eval; reaching here is a bug. *)
    env

  | DTest _ | DSetup _ | DSetupAll _ | DDescribe _ ->
    (* DTest/DSetup/DSetupAll/DDescribe are not run during normal module eval.
       They are collected and run by [run_tests]. *)
    env

  | DUse (ud, _) ->
    let prefix = String.concat "." (List.map (fun (n : name) -> n.txt) ud.use_path) ^ "." in
    (match ud.use_sel with
     | UseSingle -> env
     | UseAll ->
       let plen = String.length prefix in
       let additions = List.filter_map (fun (k, v) ->
           if String.length k > plen && String.sub k 0 plen = prefix then
             Some (String.sub k plen (String.length k - plen), v)
           else None) env in
       additions @ env
     | UseNames names ->
       List.fold_left (fun env n ->
           match List.assoc_opt (prefix ^ n.txt) env with
           | Some v -> (n.txt, v) :: env
           | None -> env) env names
     | UseExcept excluded ->
       let excl_set = List.map (fun (n : name) -> n.txt) excluded in
       let plen = String.length prefix in
       let additions = List.filter_map (fun (k, v) ->
           if String.length k > plen && String.sub k 0 plen = prefix then
             let short = String.sub k plen (String.length k - plen) in
             if List.mem short excl_set then None
             else Some (short, v)
           else None) env in
       additions @ env)

  | DAlias (ad, _) ->
    let mod_name    = String.concat "." (List.map (fun (n : name) -> n.txt) ad.alias_path) in
    let orig_prefix = mod_name ^ "." in
    let short_prefix = ad.alias_name.txt ^ "." in
    let plen = String.length orig_prefix in
    (* Ensure the target module is loaded so its entries are in module_registry. *)
    ensure_module_loaded mod_name;
    (* Collect aliases from the lexical env… *)
    let env_additions = List.filter_map (fun (k, v) ->
        if String.length k > plen && String.sub k 0 plen = orig_prefix then
          Some (short_prefix ^ String.sub k plen (String.length k - plen), v)
        else None) env in
    (* …and from module_registry (stdlib modules loaded on demand live there). *)
    let reg_additions = Hashtbl.fold (fun k v acc ->
        if String.length k > plen && String.sub k 0 plen = orig_prefix then
          (short_prefix ^ String.sub k plen (String.length k - plen), v) :: acc
        else acc) module_registry [] in
    (* Register the alias entries so on-demand variable lookup finds them too. *)
    List.iter (fun (k, v) -> Hashtbl.replace module_registry k v) reg_additions;
    (env_additions @ reg_additions) @ env

and eval_decls (env : env) (decls : decl list) : env =
  List.fold_left eval_decl env decls

(** Two-pass module evaluation.

    Pass 1: For every top-level [DFn], install a stub closure in the
            environment.  This lets mutually-recursive functions refer
            to each other by name.

    Pass 2: Re-evaluate each [DFn] so that its closure captures the
            fully-populated environment (including all stubs). *)
let eval_module_env (m : module_) : env =
  (* Reset global actor and task state for this module run *)
  closure_prefix_override := None;
  Hashtbl.clear module_registry;
  Hashtbl.clear actor_defs_tbl;
  Hashtbl.clear actor_registry;
  Hashtbl.clear named_registry;
  Hashtbl.clear reg_names_pending;
  pending_timers := [];
  next_pid := 0;
  dropped_messages_count := 0;
  Hashtbl.clear task_registry;
  next_task_id := 0;
  Hashtbl.clear dyn_sup_registry;
  Hashtbl.clear dyn_sup_vpid_map;
  dyn_sup_next_vpid := (-1);
  (* Pre-register builtin constructor → type mappings so Show/impl dispatch works *)
  Hashtbl.reset impl_tbl;
  Hashtbl.reset iface_method_tbl;
  Hashtbl.reset ctor_type_tbl;
  Hashtbl.reset ctor_qualified_type_tbl;
  List.iter (fun (ctor, ty) -> Hashtbl.replace ctor_type_tbl ctor ty)
    [ "Ok", "Result"; "Err", "Result"
    ; "Some", "Option"; "None", "Option"
    ; "Cons", "List";  "Nil",  "List" ];
  (* Same-short-name type collision set (see [type_collision_set]'s doc
     comment): computed ONCE per run, from the full AST, before any DType/
     DImpl below is evaluated — [is_colliding_type_name]/[register_type_ctors]
     consult it as they go. Also resets it, so a later test run in the same
     process (all run_eval tests share this one OCaml process) never sees a
     stale collision entry left over from an unrelated earlier module. *)
  compute_type_collision_set m.mod_decls;

  (* Pass 1: stubs.  We use a ref cell shared across all stubs so that
     closures created in pass 2 can see the final environment. *)
  let env_ref : env ref = ref (task_builtins @ base_env) in

  (* Install a placeholder for every top-level fn *)
  let install_stub = function
    | DFn (def, _) ->
      (* Placeholder that will be overwritten in pass 2 *)
      let stub = VBuiltin ("<stub:" ^ def.fn_name.txt ^ ">",
                           fun _ -> eval_error "stub %s called before initialisation"
                               def.fn_name.txt) in
      env_ref := (def.fn_name.txt, stub) :: !env_ref
    | _ -> ()
  in
  List.iter install_stub m.mod_decls;

  (* Pass 2: evaluate declarations in order, building up real closures.
     Each closure closes over [env_ref], which by the time any function
     is *called* will hold the full environment. *)
  let rec make_recursive_env decls env =
    match decls with
    | [] -> env
    | DFn (def, _) :: rest ->
      (match def.fn_doc with
       | Some s -> Hashtbl.replace doc_registry (current_doc_prefix () ^ def.fn_name.txt) s
       | None   -> ());
      let clause = match def.fn_clauses with
        | [c] -> c
        | _   -> eval_error "fn %s: expected one clause after desugaring"
                     def.fn_name.txt
      in
      let params = clause_params clause in
      (* The closure environment is the ref itself; we use a trick:
         build a closure that looks up in [env_ref] at call time. *)
      let arity = List.length params in
      (* Encode arity in the name so we can recover it when combining arities *)
      let rec_name = Printf.sprintf "<rec:%s/%d>" def.fn_name.txt arity in
      let defn_prefix = effective_module_prefix () in
      let rec_closure = VBuiltin (rec_name,
                                  fun args ->
                                    let call_env = !env_ref in
                                    let fn_v = VClosure (call_env, params, clause.fc_body, defn_prefix) in
                                    apply fn_v args) in
      (* Support default-arg overloading: if a same-named fn already has a real
         closure (VMultiarity or a previous single-arity VBuiltin), combine into
         VMultiarity so both arities are callable. *)
      let parse_rec_arity n =
        (* "<rec:greet/1>" → Some 1 *)
        match String.rindex_opt n '/' with
        | None -> None
        | Some i ->
          (try Some (int_of_string (String.sub n (i+1) (String.length n - i - 2)))
           with _ -> None)
      in
      let combined =
        match List.assoc_opt def.fn_name.txt env with
        | Some (VMultiarity variants) ->
          VMultiarity ((arity, rec_closure) :: List.remove_assoc arity variants)
        | Some (VBuiltin (n, _) as prev) when parse_rec_arity n <> None ->
          let prev_arity = Option.get (parse_rec_arity n) in
          VMultiarity [(arity, rec_closure); (prev_arity, prev)]
        | _ -> rec_closure
      in
      let env' = (def.fn_name.txt, combined)
                 :: List.remove_assoc def.fn_name.txt env in
      (* If this is a mangled default-arg function (foo$N), also register
         under the base name (foo) as a VMultiarity so that callers using
         the original name can dispatch by arity (e.g. call_fn env "greet"). *)
      let env'' =
        let name = def.fn_name.txt in
        match String.rindex_opt name '$' with
        | Some dollar_pos when dollar_pos > 0 ->
          let base = String.sub name 0 dollar_pos in
          let suffix = String.sub name (dollar_pos + 1) (String.length name - dollar_pos - 1) in
          (match int_of_string_opt suffix with
           | Some _ ->
             let existing_variants = match List.assoc_opt base env' with
               | Some (VMultiarity vs) -> vs
               | Some (VBuiltin (n, _) as prev) when parse_rec_arity n <> None ->
                 [(Option.get (parse_rec_arity n), prev)]
               | _ -> []
             in
             let base_combined = VMultiarity
               ((arity, rec_closure) :: List.remove_assoc arity existing_variants) in
             (base, base_combined) :: List.remove_assoc base env'
           | None -> env')
        | _ -> env'
      in
      env_ref := env'';
      make_recursive_env rest env''

    | DLet (_, b, _) :: rest ->
      let v = eval_expr env b.bind_expr in
      let env' = match match_pattern v b.bind_pat with
        | Some bs -> bs @ env
        | None    -> eval_error "top-level let pattern failed"
      in
      env_ref := env';
      make_recursive_env rest env'

    | DActor (_, name, def, _) :: rest ->
      (* Register actor with the shared env_ref so handlers can call module fns.
         Also register qualified name for spawn(Mod.Actor) support. *)
      Hashtbl.replace actor_defs_tbl name.txt (def, env_ref);
      let qual = current_doc_prefix () ^ name.txt in
      if qual <> name.txt then
        Hashtbl.replace actor_defs_tbl qual (def, env_ref);
      make_recursive_env rest env

    | DMod _ as d :: rest ->
      (* Evaluate nested module via eval_decl (which handles module_stack push/pop
         and exposes prefixed bindings). Docs inside nested modules are registered
         as a side effect of eval_decl → eval_decls → eval_decl(DFn). *)
      let env' = eval_decl env d in
      env_ref := env';
      make_recursive_env rest env'

    | DImpl _ as d :: rest ->
      (* Delegate to eval_decl's DImpl arm rather than duplicating its
         dispatch-construction logic here: this case used to carry its own
         byte-for-byte copy of that logic (keyed on [acc_env] instead of
         [env]), and the two copies silently diverged — a fix for
         self-recursive general-interface dispatch (compositional impls like
         `MyEq(Wrap(a)) when MyEq(a)` whose `eq` calls `eq` on the unwrapped
         value) landed in [eval_decl]'s copy but not this one, since a
         source file's single top-level `mod X do ... end` is unwrapped by
         the parser so its decls are processed HERE, not via [eval_decl]'s
         own DMod recursion. Delegating removes the duplicate outright. *)
      let env' = eval_decl env d in
      env_ref := env';
      make_recursive_env rest env'

    | (DUse _ | DAlias _) as d :: rest ->
      let env' = eval_decl env d in
      env_ref := env';
      make_recursive_env rest env'

    | DType (_, name, _, td, _) :: rest ->
      (* Populate ctor_type_tbl and record_type_tbl for dispatch *)
      (match td with
       | TDVariant variants -> register_type_ctors name.txt variants
       | TDRecord fields ->
         let field_names = List.map (fun (f : field) -> f.fld_name.txt) fields in
         let key = String.concat "," (List.sort String.compare field_names) in
         Hashtbl.replace record_type_tbl key name.txt
       | _ -> ());
      (* resource Foo desugars to TDVariant []; see comment at ffi_resource_tbl. *)
      (match td with
       | TDVariant [] -> Hashtbl.replace ffi_resource_tbl name.txt ()
       | TDVariant _ | TDRecord _ -> Hashtbl.replace ffi_type_decl_tbl name.txt td
       | _ -> ());
      make_recursive_env rest env

    | DProtocol _ as d :: rest ->
      ignore (eval_decl env d);
      make_recursive_env rest env

    | DExtern _ as d :: rest ->
      let env' = eval_decl env d in
      env_ref := env';
      make_recursive_env rest env'

    | _ :: rest -> make_recursive_env rest env
  in

  let final_env = make_recursive_env m.mod_decls !env_ref in
  env_ref := final_env;
  install_global_tail final_env;
  final_env

(** Call an optional hook stored as [Some(fn)] / [None] in a VCon. *)
let call_hook_opt (v_opt : value option) : unit =
  match v_opt with
  | Some (VCon ("Some", [hook_fn])) -> ignore (apply hook_fn [])
  | _ -> ()

(** Evaluate a list of declarations (typically a DMod from a stdlib file)
    into the current module_registry WITHOUT resetting global state.
    Used by the on-demand module_loader callback. *)
let eval_stdlib_decls (decls : decl list) : unit =
  let base = task_builtins @ base_env in
  let env_ref = ref base in
  let rec go ds env =
    match ds with
    | [] -> env
    | DMod (name, _, inner_decls, _) :: rest ->
      module_stack := name.txt :: !module_stack;
      let inner_ref = ref env in
      List.iter (function
        | DFn (def, _) ->
          let stub = VBuiltin ("<stub:" ^ def.fn_name.txt ^ ">",
                               fun _ -> eval_error "stub %s called before initialisation"
                                   def.fn_name.txt) in
          inner_ref := (def.fn_name.txt, stub) :: !inner_ref
        | _ -> ()
      ) inner_decls;
      let rec eval_inner ds' e =
        match ds' with
        | [] -> e
        | DFn (def, _) :: r ->
          let clause = match def.fn_clauses with
            | [c] -> c
            | _   -> eval_error "fn %s: expected one clause" def.fn_name.txt
          in
          let params = clause_params clause in
          let defn_prefix = effective_module_prefix () in
          let rec_clo = VBuiltin ("<rec:" ^ def.fn_name.txt ^ ">",
            fun args ->
              let call_env = !inner_ref in
              let fn_v = VClosure (call_env, params, clause.fc_body, defn_prefix) in
              apply fn_v args) in
          let e' = (def.fn_name.txt, rec_clo) :: List.remove_assoc def.fn_name.txt e in
          inner_ref := e';
          eval_inner r e'
        | d :: r ->
          let e' = eval_decl e d in
          inner_ref := e';
          eval_inner r e'
      in
      let mod_env = eval_inner inner_decls !inner_ref in
      module_stack := (match !module_stack with _ :: tl -> tl | [] -> []);
      let rec declared_names acc = function
        | [] -> acc
        | DFn (def, _) :: r -> declared_names (def.fn_name.txt :: acc) r
        | DLet (_, b, _) :: r ->
          let rec pn a = function PatVar n -> n.txt :: a | PatTuple (ps, _) -> List.fold_left pn a ps | PatCon (_, ps) -> List.fold_left pn a ps | _ -> a in
          declared_names (pn acc b.bind_pat) r
        | DMod (n, _, _, _) :: r -> declared_names (n.txt :: acc) r
        | DExtern (edef, _) :: r ->
          declared_names (List.map (fun (ef : extern_fn) -> ef.ef_name.txt) edef.ext_fns @ acc) r
        | _ :: r -> declared_names acc r
      in
      let own_names = declared_names [] inner_decls in
      let is_own_key k =
        List.exists (fun n ->
          k = n || (String.length k > String.length n + 1 &&
                    String.sub k 0 (String.length n + 1) = n ^ ".")) own_names in
      let prefixed = List.filter_map (fun (k, v) ->
        if is_own_key k then Some (name.txt ^ "." ^ k, v) else None) mod_env in
      List.iter (fun (k, v) -> Hashtbl.replace module_registry k v) prefixed;
      let env' = prefixed @ env in
      env_ref := env';
      go rest env'
    | d :: rest ->
      let env' = eval_decl env d in
      env_ref := env';
      go rest env'
  in
  ignore (go decls !env_ref)

(** Bind `let* p = e` at a REPL prompt.

    There is no continuation at a prompt, so this cannot be the ordinary
    [ELetStar] expansion.  Instead it runs the value's OWN `flat_map` with a
    callback that captures the first value it is handed and then returns the
    original monadic value, which is well-typed as the callback's `M(b)`
    result for any `M` without needing a generic `pure` the language does not
    have.  `flat_map`'s result is discarded -- only the captured payload
    matters.

    Semantics, chosen to match `let?`'s prompt behaviour: bind the FIRST value
    yielded.  For `Option`/`Result` there is at most one, so this is exactly
    "unwrap".  For a multi-value monad like `List` the callback runs once per
    element and the first wins, which is the reading `let* x = [1,2,3]` most
    naturally suggests.  A value that yields NOTHING (`None`, `Err`, `[]`)
    binds nothing and is reported rather than silently succeeding.

    Returns [Ok bindings] or [Error message]. *)
let letstar_repl_bind (env : env) (p : pattern) (e : expr)
    : ((string * value) list, string) result =
  let v = eval_expr env e in
  (* [type_name_of_value] reads [ctor_type_tbl], which is populated by
     [register_variant_ctors] from a March-source [DType].  Option/Result/List
     are BUILTIN types with no such declaration, so in a REPL session they
     resolve to [None] and `let* x = Some(1)` would report "cannot determine
     the type" for the three types a user is most likely to try first.  Map
     their constructors directly -- the same builtin triple already spelled
     out for the collision seed above.  A user-defined type needs none of
     this: its DType registers its ctors normally. *)
  let builtin_ctor_type = function
    | "Some" | "None" -> Some "Option"
    | "Ok"   | "Err"  -> Some "Result"
    | "Cons" | "Nil"  -> Some "List"
    | _ -> None
  in
  let head_opt =
    match type_name_of_value v with
    | Some t -> Some t
    | None -> (match v with VCon (tag, _) -> builtin_ctor_type tag | _ -> None)
  in
  match head_opt with
  | None ->
    Error (Printf.sprintf "let*: cannot determine the type of %s"
             (value_to_string v))
  | Some head_name ->
    let flat_map_name = head_name ^ ".flat_map" in
    (match (try Some (lookup flat_map_name env) with _ -> None) with
     | None ->
       Error (Printf.sprintf
                "let* needs `%s`, but it doesn't exist" flat_map_name)
     | Some flat_map_fn ->
       let captured = ref None in
       let k = VBuiltin ("$letstar_repl_k", function
           | [x] ->
             (match !captured with None -> captured := Some x | Some _ -> ());
             v
           | args ->
             eval_error "let* continuation: expected 1 argument, got %d"
               (List.length args))
       in
       ignore (apply flat_map_fn [v; k]);
       (match !captured with
        | None ->
          Error (Printf.sprintf
                   "let*: %s yielded no value to bind"
                   (value_to_string v))
        | Some x ->
          (match match_pattern x p with
           | Some bs -> Ok bs
           | None ->
             Error (Printf.sprintf
                      "let* pattern did not match the value %s"
                      (value_to_string x)))))

(** Run the module: evaluate it, then call [main()] or drive the [app] lifecycle. *)
let run_module (m : module_) : unit =
  (* Reset global app state for fresh run *)
  app_spawn_order   := [];
  shutdown_requested := false;
  (* Reset Signal.watch state for a fresh run. *)
  Array.fill signal_watchers 0 5 None;
  Array.fill signal_pending  0 5 false;
  Array.fill signal_seen     0 5 false;
  let env = eval_module_env m in
  (* Install SIGTERM/SIGINT handlers: graceful shutdown by default, or (once a
     Signal.watch watcher is registered) deferred dispatch with a
     second-delivery shutdown escape hatch. *)
  Sys.set_signal Sys.sigterm (Sys.Signal_handle handle_os_signal);
  Sys.set_signal Sys.sigint  (Sys.Signal_handle handle_os_signal);
  match List.assoc_opt "__app_init__" env with
  | Some init_fn ->
    (* App entry point: evaluate app body to get { spec, on_start, on_stop } *)
    let app_record = apply init_fn [] in
    let spec = match app_record with
      | VRecord fields ->
        (match List.assoc_opt "spec" fields with
         | Some v -> v
         | None -> app_record)
      | _ -> app_record
    in
    let on_start_opt = match app_record with
      | VRecord fields -> List.assoc_opt "on_start" fields
      | _ -> None
    in
    let on_stop_opt = match app_record with
      | VRecord fields -> List.assoc_opt "on_stop" fields
      | _ -> None
    in
    (* 1. Spawn supervision tree *)
    spawn_from_spec spec;
    (* 2. Call on_start hook (after tree is up) *)
    call_hook_opt on_start_opt;
    (* 3. Run scheduler until drained or shutdown requested *)
    run_scheduler ();
    (* 4. Graceful shutdown: reverse-order Shutdown() to each child *)
    if not (List.is_empty !app_spawn_order) then
      graceful_shutdown ();
    (* 5. Call on_stop hook (after tree is down) *)
    call_hook_opt on_stop_opt
  | None ->
    match List.assoc_opt "main" env with
    | None   -> ()
    | Some v ->
      (* [main] may be declared 0-arity or take ANY NUMBER of [Cap(P)]
         parameters (checked at desugar time by
         [Desugar.check_main_signature]; R1 stage D made the grant a SET so a
         program needing e.g. console AND spawn can state a narrow grant
         instead of widening to `Cap(IO)`). Each receives the erased
         capability, matching [root_cap]'s own runtime representation
         ([VUnit], see the initial env binding above).

         This MUST track the compiled path's entry adapter
         (lib/tir/llvm_toplevel.ml, which supplies the same number of erased
         nulls). The two are the same contract in two backends, and the
         compiled-and-run parity tests in test_codegen's [main_cap_adapter]
         group exist because only running BOTH catches a divergence — this
         arm silently passed 0 args to a 2-parameter `main` and produced
         "arity mismatch: expected 2 args, got 0" while the compiled side was
         fine.

         Top-level functions are bound to a [VBuiltin] recursion wrapper (see
         the [DFn] case of [eval_decl], the "<rec:name/arity>" closure), not
         directly to a [VClosure], so arity can't be read off [v] itself —
         read it from the entry module's own AST instead. *)
      let main_arity = List.find_map (function
          | DFn (def, _) when def.fn_name.txt = "main" ->
            (match def.fn_clauses with
             | [clause] -> Some (List.length (clause_params clause))
             | _ -> None)
          | _ -> None
        ) m.mod_decls
      in
      let args = match main_arity with
        | Some n when n > 0 -> List.init n (fun _ -> VUnit)
        | _ -> []
      in
      let _ = apply v args in
      run_scheduler ()

(* =================================================================
   §14  Test runner
   ================================================================= *)

(** Result of running a single test. *)
type test_result =
  | TestPass
  | TestFail of string  (** failure message *)
  | TestError of string (** unexpected exception *)

(** Collect all [DTest], [DSetup], and [DSetupAll] nodes from the module,
    flattening [DDescribe] groups (prefixing test names with describe label). *)
let collect_test_decls (m : module_) :
    expr option * expr option * (string * expr) list =
  let setup_ref     = ref None in
  let setup_all_ref = ref None in
  let tests         = ref [] in
  let rec collect_decl prefix d =
    match d with
    | DTest (tdef, _) ->
      let full_name = if prefix = "" then tdef.test_name
                      else prefix ^ " " ^ tdef.test_name in
      tests := (full_name, tdef.test_body) :: !tests
    | DDescribe (name, decls, _) ->
      let new_prefix = if prefix = "" then name else prefix ^ " " ^ name in
      List.iter (collect_decl new_prefix) decls
    | DSetup (body, _)    -> setup_ref     := Some body
    | DSetupAll (body, _) -> setup_all_ref := Some body
    | _ -> ()
  in
  List.iter (collect_decl "") m.mod_decls;
  (!setup_all_ref, !setup_ref, List.rev !tests)

(** Run the test suite in [m] with the given options.
    Returns [(total, n_failed, failures)] so the caller can emit a summary.
    [~verbose] — emit each test name instead of dots.
    [~quiet]   — suppress all output; just return counts and failure list.
    [~filter]  — only run tests whose name contains this substring.

    Output:
      - Dot mode (default):  prints one `.` per pass, `F` per fail, then "Finished" line.
      - Verbose mode:        prints `✓ name` / `✗ name  (msg)`, then "Finished" line.
      - Quiet mode:          no output at all; caller handles reporting.

    Exit-code contract: the caller is responsible for exiting 1 if failures > 0.
    [~capture_io] — when true, suppress print/log output during each test and
    include it in the failure message if the test fails.  Opt-in via @capture_io
    in the test source. *)
let run_tests ?(verbose=false) ?(quiet=false) ?(dot_stream=false) ?(filter="") ?(capture_io=false) (m : module_) : int * int * (string * string) list =
  (* Build the module environment (registers all fns, lets, etc.) *)
  let env = eval_module_env m in
  let (setup_all_opt, setup_opt, tests) = collect_test_decls m in
  (* Apply filter *)
  let tests = if filter = "" then tests
              else List.filter (fun (name, _) ->
                     let lname = String.lowercase_ascii name in
                     let lpat  = String.lowercase_ascii filter in
                     let n = String.length lname and p = String.length lpat in
                     let rec check i =
                       if i + p > n then false
                       else if String.sub lname i p = lpat then true
                       else check (i + 1)
                     in check 0
                   ) tests in
  (* Run setup_all once *)
  (match setup_all_opt with
   | Some body -> (try let _ = eval_expr env body in ()
                   with exn ->
                     Printf.eprintf "setup_all failed: %s\n%!" (Printexc.to_string exn))
   | None -> ());
  let total = List.length tests in
  let failures = ref [] in
  if not verbose && not quiet then Printf.printf "%!" else ();
  List.iter (fun (name, body) ->
    (* Run per-test setup *)
    (match setup_opt with
     | Some s -> (try let _ = eval_expr env s in ()
                  with exn ->
                    Printf.eprintf "setup failed for \"%s\": %s\n%!" name (Printexc.to_string exn))
     | None -> ());
    (* Clear the March call stack so a previous failing test's frames
       don't bleed into the next test's error message. *)
    clear_march_stack ();
    (* When capture_io is enabled, redirect print/log into a per-test buffer. *)
    let cap_buf = if capture_io then Some (Buffer.create 128) else None in
    (match cap_buf with Some b -> test_capture_buf := Some b | None -> ());
    let result =
      try
        let _ = eval_expr env body in
        TestPass
      with
      | Assert_failure msg -> TestFail msg
      | Eval_error msg     -> TestError msg
      | Match_failure msg  -> TestError ("match failure: " ^ msg)
      | exn                -> TestError (Printexc.to_string exn)
    in
    test_capture_buf := None;
    let captured = match cap_buf with
      | Some b -> Buffer.contents b
      | None -> ""
    in
    (* Append captured output to failure message when non-empty. *)
    let with_output msg =
      if captured = "" then msg
      else msg ^ "\n\n--- captured output ---\n" ^ String.trim captured
    in
    if quiet then begin
      (* Collect failures silently *)
      (match result with
       | TestPass -> ()
       | TestFail msg -> failures := (name, with_output msg) :: !failures
       | TestError msg -> failures := (name, with_output ("error: " ^ msg)) :: !failures)
    end else if verbose then begin
      match result with
      | TestPass ->
        Printf.printf "  ✓ %s\n%!" name
      | TestFail msg ->
        let full = with_output msg in
        Printf.printf "  ✗ %s\n    %s\n%!" name
          (String.concat "\n    " (String.split_on_char '\n' full));
        failures := (name, full) :: !failures
      | TestError msg ->
        let full = with_output ("error: " ^ msg) in
        Printf.printf "  ✗ %s\n    %s\n%!" name
          (String.concat "\n    " (String.split_on_char '\n' full));
        failures := (name, full) :: !failures
    end else begin
      (match result with
       | TestPass ->
         if dot_stream then Printf.printf "\027[32m.\027[0m%!"
         else Printf.printf ".%!"
       | TestFail msg ->
         if dot_stream then Printf.printf "\027[31mF\027[0m%!"
         else Printf.printf "F%!";
         failures := (name, with_output msg) :: !failures
       | TestError msg ->
         if dot_stream then Printf.printf "\027[31mE\027[0m%!"
         else Printf.printf "E%!";
         failures := (name, with_output ("error: " ^ msg)) :: !failures)
    end
  ) tests;
  let n_failed = List.length !failures in
  if not quiet && not dot_stream then begin
    if not verbose then Printf.printf "\n%!";
    (* Print failure details in dot mode *)
    if not verbose && !failures <> [] then begin
      Printf.printf "\n%d failure(s):\n\n" (List.length !failures);
      List.iter (fun (name, msg) ->
        Printf.printf "FAIL: \"%s\"\n  %s\n\n" name
          (String.concat "\n  " (String.split_on_char '\n' msg))
      ) (List.rev !failures)
    end;
    Printf.printf "Finished: %d test%s, %d failure%s\n%!"
      total (if total = 1 then "" else "s")
      n_failed (if n_failed = 1 then "" else "s")
  end;
  (total, n_failed, List.rev !failures)

(* =================================================================
   §15  Doctest runner
   ================================================================= *)

(** Run all doctests extracted from [fn_doc] fields in the module.

    [parse_expr] converts a source string to an AST [expr].  It is injected
    by the caller so that [march_eval] does not need to depend on [march_parser].

    Returns [(total, n_failed, failures)] with the same contract as [run_tests].
    Output format mirrors [run_tests]:
      Verbose   — "  ✓ doctest Option.is_some (1)"
      Dot mode  — one '.' per pass, 'F' per fail, 'E' per error
      Quiet     — no output; caller handles reporting. *)
let run_doctests ?(verbose=false) ?(quiet=false) ?(filter="")
    ~(parse_expr : string -> expr)
    (m : module_) : int * int * (string * string) list =
  (* Build the module environment *)
  let env = eval_module_env m in
  (* Collect (qualified_fn_name, doc_string) pairs, walking nested mods *)
  let rec collect_docs prefix decls =
    List.concat_map (fun decl ->
      match decl with
      | DFn (def, _) ->
        (match def.fn_doc with
         | None -> []
         | Some doc ->
           let qname = if prefix = "" then def.fn_name.txt
                       else prefix ^ "." ^ def.fn_name.txt in
           [(qname, doc)])
      | DMod (mname, _, inner, _) ->
        let new_prefix = if prefix = "" then mname.txt
                         else prefix ^ "." ^ mname.txt in
        collect_docs new_prefix inner
      | _ -> [])
    decls
  in
  let fn_docs = collect_docs "" m.mod_decls in
  (* Expand docs into (test_name, example) list *)
  let tests : (string * March_doctest.Doctest.example) list =
    List.concat_map (fun (fname, doc) ->
      let examples = March_doctest.Doctest.extract doc in
      List.mapi (fun i ex ->
        let name = Printf.sprintf "doctest %s (%d)" fname (i + 1) in
        (name, ex)
      ) examples
    ) fn_docs
  in
  (* Filter *)
  let tests =
    if filter = "" then tests
    else List.filter (fun (name, _) ->
           let lname = String.lowercase_ascii name in
           let lpat  = String.lowercase_ascii filter in
           let n = String.length lname and p = String.length lpat in
           let rec check i =
             if i + p > n then false
             else if String.sub lname i p = lpat then true
             else check (i + 1)
           in check 0
         ) tests
  in
  let total    = List.length tests in
  let failures = ref [] in
  List.iter (fun (name, ex) ->
    clear_march_stack ();
    let result =
      (try
         let expr   = parse_expr ex.March_doctest.Doctest.ex_source in
         let v      = eval_expr env expr in
         let actual = value_to_string v in
         (match ex.March_doctest.Doctest.ex_expected with
          | March_doctest.Doctest.ExpectOutput expected ->
            if actual = expected then TestPass
            else TestFail (Printf.sprintf "expected: %s\n  got:      %s" expected actual)
          | March_doctest.Doctest.ExpectPanic expected ->
            TestFail (Printf.sprintf "expected panic %S\n  but got: %s" expected actual)
          | March_doctest.Doctest.ExpectNothing ->
            TestPass)
       with
       | Eval_error msg ->
         (match ex.March_doctest.Doctest.ex_expected with
          | March_doctest.Doctest.ExpectPanic expected ->
            (* Panic messages are raised as "panic: <msg>"; strip the prefix *)
            let panic_tag = "panic: " in
            let actual_msg =
              if String.length msg > String.length panic_tag &&
                 String.sub msg 0 (String.length panic_tag) = panic_tag
              then String.sub msg (String.length panic_tag)
                     (String.length msg - String.length panic_tag)
              else msg
            in
            if actual_msg = expected then TestPass
            else TestFail (Printf.sprintf "expected panic %S\n  got panic: %s" expected actual_msg)
          | _ ->
            TestError msg)
       | exn ->
         TestError (Printexc.to_string exn))
    in
    if quiet then begin
      match result with
      | TestPass -> ()
      | TestFail msg -> failures := (name, msg) :: !failures
      | TestError msg -> failures := (name, "error: " ^ msg) :: !failures
    end else if verbose then begin
      match result with
      | TestPass ->
        Printf.printf "  ✓ %s\n%!" name
      | TestFail msg ->
        Printf.printf "  ✗ %s\n    %s\n%!" name
          (String.concat "\n    " (String.split_on_char '\n' msg));
        failures := (name, msg) :: !failures
      | TestError msg ->
        Printf.printf "  ✗ %s (error: %s)\n%!" name msg;
        failures := (name, "error: " ^ msg) :: !failures
    end else begin
      match result with
      | TestPass  -> Printf.printf "\027[32m.\027[0m%!"
      | TestFail msg ->
        Printf.printf "\027[31mF\027[0m%!";
        failures := (name, msg) :: !failures
      | TestError msg ->
        Printf.printf "\027[31mE\027[0m%!";
        failures := (name, "error: " ^ msg) :: !failures
    end
  ) tests;
  let n_failed = List.length !failures in
  if not quiet then begin
    if not verbose then Printf.printf "\n%!";
    if not verbose && !failures <> [] then begin
      Printf.printf "\n%d failure(s):\n\n" (List.length !failures);
      List.iter (fun (name, msg) ->
        Printf.printf "FAIL: \"%s\"\n  %s\n\n" name
          (String.concat "\n  " (String.split_on_char '\n' msg))
      ) (List.rev !failures)
    end;
    Printf.printf "Finished: %d doctest%s, %d failure%s\n%!"
      total (if total = 1 then "" else "s")
      n_failed (if n_failed = 1 then "" else "s")
  end;
  (total, n_failed, List.rev !failures)
