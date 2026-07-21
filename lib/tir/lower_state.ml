(** Shared lowering state: the [env] record and the module-level mutable
    tables/refs that every other lower_*.ml split module (types excepted)
    needs to read or write (Wave 3 Task 9).

    This module exists because [env] (and several of the refs below, e.g.
    [_fn_param_types], the alias tables, the iface-method tables) are
    consumed by [lower_match.ml], [lower_decls.ml], [lower_actor.ml],
    [lower_tests.ml], AND [lower.ml] itself — no single one of those owns
    them, and OCaml's acyclic-module-dependency requirement means whichever
    module defines [env] must be buildable before all of its consumers.
    Rather than picking one arbitrary consumer to own it (which would make
    the others depend on a module named after an unrelated concern) this
    small foundational module holds exactly the cross-cutting state,
    verbatim from lower.ml. This is the "small lower_state.ml if the cut
    demands; justify" case anticipated by the Task 9 brief.

    Every ref here keeps its ORIGINAL "NOT converted to an env field"
    rationale comment from lower.ml's Wave 3 Task 8 pass — moving the
    module doesn't change any of those load-bearing staleness/accumulator
    semantics, just the file the ref's declaration lives in. *)

module Ast = March_ast.Ast
module Typecheck = March_typecheck.Typecheck

(* ── Fresh name generation ──────────────────────────────────────── *)

(** Monotonic fresh-name counter ($lamN/$tN/$pN/$jpN/…).

    NOT converted to an env field (Wave 3 Task 8): a pure accumulator —
    mutated without restore across the entire module traversal, reset to 0
    exactly once per [lower_module] call via [reset_counter ()] (that
    per-call restart is load-bearing: the TIR snapshot corpus and the REPL
    JIT's per-fragment numbering both depend on it — see
    test/test_snapshots.ml's determinism note). The direct lower.ml
    analogue of perceus's [_rc_fresh_ctr], which chunk-1 Task 4 kept as a
    ref under the same "accumulator/table-build semantics" law clause. *)
let _lower_counter = ref 0

let fresh_name (prefix : string) : string =
  incr _lower_counter;
  Printf.sprintf "$%s%d" prefix !_lower_counter

let reset_counter () = _lower_counter := 0

let fresh_var ?(lin = Tir.Unr) (ty : Tir.ty) : Tir.var =
  { v_name = fresh_name "t"; v_ty = ty; v_lin = lin }

(** Emit a runtime panic for a non-exhaustive match that the typechecker
    missed.  Returning [LitInt 0] here would silently reinterpret a value of
    the match's real (possibly non-Int) type as a tagged int — e.g. treated
    as a heap pointer for a [String] result — which crashes or corrupts
    memory rather than failing loudly.  Shared by every match-compilation
    fallback site (see [compile_matrix_impl] and the guarded-match fallthrough
    in [lower_match]) so all of them fail the same way the interpreter does. *)
let nonexhaustive_panic () =
  let panic_var : Tir.var = {
    Tir.v_name = "panic"; Tir.v_ty = Tir.TCon ("Never", []); Tir.v_lin = Tir.Unr } in
  Tir.EApp (panic_var, [Tir.ALit (Ast.LitString "non-exhaustive pattern match")])

(* ── Parameter type scope (set by lower_fn_def, used by lower_to_atom_k) ── *)

(** Maps current function's (or lambda's) parameter names → their TIR types.
    Used to give body variable references the correct type when [ty_of_span]
    returns a wrong or stale type for a parameter at its use-site (e.g. due
    to shared mutable type_map entries).  Managed by [lower_fn_def] and the
    [ELam] case in [lower_expr]:
    - [lower_fn_def] saves/restores across nested calls so function scopes
      don't interfere.
    - [ELam] temporarily installs the lambda's own parameter types so the
      lambda body can't accidentally inherit an enclosing function parameter
      of the same name but different type.

    NOT converted to an [env] field (Wave 3 Task 8): all 6 save/restore sites
    (this file's [EBlock]/[ELetFn]-as-block-statement, [ELam], [ELetFn],
    [lower_branch_body_with_pat], the guarded-match arm in [lower_match], and
    [lower_fn_def]'s full-scope save/clear/restore) bracket a call to
    [lower_expr] — which can [failwith] (EPipe/EResultRef/ESigil bail-outs,
    the non-exhaustive-pattern-kind panic in the match compiler, the
    fn-arity-mismatch check in [lower_fn_def]) — WITHOUT [Fun.protect]. A
    thrown exception during any of these six windows leaves the table
    populated with the inner scope's entries (or, for [lower_fn_def],
    cleared entirely) instead of restored. This is a genuine restore-gap:
    an [env]-record version using [{ env with fn_param_types = saved }]
    would NOT reproduce this on the throw path (the caller's [env] binding
    is untouched by a callee's exception, so the "leak" would silently
    disappear) — a real behavior change on the error path, forbidden by the
    plan's transformation law. Preserved bit-for-bit as a global, dirty-on-
    throw semantics included. Filed: specs/todos.md (Wave 3 Task 8 entry,
    citing analysis doc lower.ml High #2's neighborhood). *)
let _fn_param_types : (string, Tir.ty) Hashtbl.t = Hashtbl.create 8

(* ── Env — module-scoped state threaded through the lowering functions
   (Wave 3 Task 8) ──────────────────────────────────────────────────────

   Only fields whose old ref was BOTH (a) genuinely save-and-restored
   (never left dirty on a lexical exit) AND (b) safe to reset per
   [lower_module] call (not part of the documented cross-call-staleness
   trio below) are carried here. Everything else stays a module-level
   ref/Hashtbl, each with a comment at its declaration explaining why
   (accumulator, restore-gap, or intentional cross-call staleness) —
   see the "NOT converted" comments throughout this file for the full
   per-ref rationale demanded by the plan's transformation law. *)
type env = {
  type_map : (Ast.span, Typecheck.ty) Hashtbl.t option;
      (** The typechecker's span → type table. Set once at [lower_module]
          entry, read-only for the entire lowering run (never mutated
          mid-traversal — only ever replaced wholesale at the next
          [lower_module] call), reset to [None] at exit. A pure
          module-scoped constant, the same shape as perceus's
          [borrow_map]/[type_defs] fields. Was [_type_map_ref]. *)
  current_module_aliases : (string, string) Hashtbl.t;
      (** Per-module import aliases (the aliases from the module CURRENTLY
          being lowered, inheriting the enclosing module's). Consulted
          BEFORE the program-global [_use_aliases] so a module's own
          [import X] wins over an alias another module registered globally
          for the same short name. Was [_current_module_aliases], which had
          TWO save/restore dances:
          - [lower_mod_decls] (inherit-on-enter / restore-on-exit): the old
            code protected this one with [Fun.protect], so the env version
            (a callee's exception cannot touch the caller's own [env]
            binding) is exactly as safe — no throw-path change.
          - [collect_tests]' [DMod] case (snapshot re-load for test
            bodies): the old code did a BARE save/mutate/recurse/restore
            with NO [Fun.protect] around throw-capable recursion — on the
            throw path the ref stayed dirty (pointing at the snapshot).
            The env version erases that dirty-on-throw state. This is a
            behavior change, but a provably UNOBSERVABLE one: every read
            site of the old ref ([resolve_use_alias], the [DUse]
            registration, the snapshot save, both dance saves) executes
            only within [lower_module]'s dynamic extent; a throw escaping
            [collect_tests] propagates out of [lower_module] (whose exit
            cleanup was not exception-protected, so the dirt survived the
            frame), and the NEXT [lower_module] call reset the ref to a
            fresh table in its entry preamble BEFORE any read could occur
            — while in batch mode the process exits on the diagnostic.
            Filed in specs/todos.md (Wave 3 Task 8 amendment) with the
            full trace. *)
  mod_prefix : string;
      (** The LEXICAL enclosing module's qualification prefix (e.g. "" at
          top level, "DcA." inside [mod DcA do ... end], "A.B." for a
          doubly-nested module) — mirrors [current_module_aliases]'
          inherit-on-enter / restore-on-exit scoping exactly (set by
          [lower_mod_decls]'s [mod_env] at each [DMod] descent to the
          SAME [prefix] value that function already threads as a bare
          parameter for [rename_tir_vars]/fn-name qualification). Added
          for Task 3 of specs/plans/2026-07-21-fqn-dispatch-identity-stages.md
          ("native construction — qualify ECon lowering for colliding
          types"): [collect_iface_impls] (Pass 1, impl-symbol
          qualification) already tracked an analogous [mod_prefix] as a
          bare recursion parameter, but that parameter is LOCAL to Pass 1
          and never reaches [lower_expr]/[lower_to_atom_k] (defined
          top-level in lower.ml, taking only [env]) where [ECon] is
          lowered to [EAlloc]. Threading it through [env] instead is what
          makes it visible at that deeper call site — the same reasoning
          that put [current_module_aliases] in [env] rather than leaving
          it a bare recursion parameter. *)
  collision_set : (string, string list) Hashtbl.t;
      (** [Collision_set.compute]'s result: short type name -> declaring
          qualified names, for short names declared by >= 2 modules.
          Computed ONCE per [lower_module] call (from the SAME early
          AST walk — [collect_type_names] — that already fed Pass 1's
          impl-symbol qualification), then read-only for the entire
          lowering run — the same "module-scoped constant" shape as
          [type_map]. Reused (not recomputed) by the [ECon] arm so both
          consumers agree on exactly which short names collide. *)
}

(** The env used at the top of [lower_module], before [type_map] is known
    and before any module scope has been entered — mirrors the old refs'
    initial values ([None], a fresh empty [Hashtbl]). *)
let empty_env : env = {
  type_map = None;
  current_module_aliases = Hashtbl.create 0;
  mod_prefix = "";
  collision_set = Hashtbl.create 0;
}

(** Look up the TIR type for an expression from the env's type_map.
    Falls back to [unknown_ty] when no type_map is set or the span
    is not present (e.g. spans introduced by desugaring). *)
let ty_of_span (env : env) (sp : Ast.span) : Tir.ty =
  match env.type_map with
  | None -> Lower_types.unknown_ty
  | Some tbl ->
    (match Hashtbl.find_opt tbl sp with
     | Some t ->
       Lower_types.convert_ty t
     | None   -> Lower_types.unknown_ty)

let ty_of_expr (env : env) (e : Ast.expr) : Tir.ty =
  ty_of_span env (Typecheck.span_of_expr e)

(* ── Use import resolution ───────────────────────────────────────── *)

(** Maps unqualified names to their qualified module-prefixed names.
    Built from [DUse] declarations. E.g. [map] → [List.map].

    NOT converted to an env field: this is an accumulator, not a
    save-and-restore scope. It is reset to a fresh (empty) table once at
    [lower_module] entry, then progressively WRITTEN TO throughout Pass 2
    as each [DUse]/[DMod] declaration is processed, with later declarations'
    lowering reading entries earlier declarations in the SAME pass wrote —
    so, unlike [type_map] above, its value is not fixed for the whole run.
    Cleared (to size 0, not reset) at [lower_module] exit. Stays a ref,
    documented per the plan's "accumulator/table-build semantics" rule. *)
let _use_aliases : (string, string) Hashtbl.t ref = ref (Hashtbl.create 0)

(** Protocol name → sorted, deduplicated role-name list.  Populated from
    [DProtocol] declarations during lowering (mirrors [protocol_roles_tbl] in
    the interpreter).  Consulted by the [MPST.new] lowering to pass the roles
    in tuple-position (role-name-sorted) order to the runtime, so name-based
    routing in send/recv lines up with the endpoint tuple positions. *)
let _protocol_roles : (string, string list) Hashtbl.t = Hashtbl.create 8

(** Module-alias prefix table: maps a `alias Long.Path as Short` declaration's
    short name to its full module path (e.g. "PubSub" -> "Bastion.PubSub").
    Consulted as an ORDER-INDEPENDENT fallback in [resolve_use_alias]: a
    reference `Short.member` is rewritten to `Long.Path.member` by prefix
    substitution, WITHOUT requiring the target function to have been lowered
    yet.  This is what the exact-name entries the DAlias handlers build by
    scanning [!fns] cannot guarantee — those only cover aliases whose target
    module happened to be lowered first, which holds for the entry file's
    top-level aliases (processed after every other module) but NOT for an
    `alias` declared inside a non-entry (auto-discovered / stdlib) module
    body, whose target sibling may be lowered afterward.  Global, matching
    [_use_aliases]; explicit-alias short names rarely collide (same hijack
    caveat as [_use_aliases], mitigated by first-wins registration). *)
let _module_aliases : (string, string) Hashtbl.t ref = ref (Hashtbl.create 0)

(** Snapshot of each module's [current_module_aliases] env field (keyed by its qualified
    prefix, e.g. "TestLivePostgres."), saved at the end of [lower_mod_decls].
    Test/setup bodies are lowered in a SEPARATE later pass ([collect_tests]) after
    the per-module scope has been restored, so they re-load their enclosing
    module's aliases from here — otherwise a test's `close(conn)` would fall back
    to the global table and hijack Connection.close → Db.close.

    NOT converted to an env field: an accumulator written throughout Pass 2
    (one entry per module lowered) and read later by the wholly separate
    [collect_tests] pass, which runs AFTER [env.current_module_aliases] has
    already been unwound back to its outermost (entry-module) value by
    [lower_mod_decls]'s save/restore — i.e. this snapshot table is exactly
    the mechanism that lets test bodies see a per-module [env] value the
    live [env] no longer holds by the time they run. Reset fresh at
    [lower_module] entry. *)
let _module_alias_snapshots : (string, (string, string) Hashtbl.t) Hashtbl.t ref
  = ref (Hashtbl.create 0)

(* ── Alias-ambiguity audit (MARCH_ALIAS_AUDIT=1) ─────────────────────────
   The name-hijack bug class (to_string → Bytes.to_string, close → Db.close,
   march#8) is a bare name resolving through the PROGRAM-GLOBAL first-wins
   alias table while several distinct qualified candidates exist.  The
   per-module table fixes precedence for the importing module itself, but a
   bare name that still falls through to the global table with ≥2 candidates
   is resolving by registration order — a hijack waiting to happen.  Track
   every qualified target ever offered for each short name; when the global
   fallback fires for an ambiguous one, report it once.  Diagnostic only.

   NOT converted to env fields: pure diagnostic accumulators (never
   consulted for a lowering DECISION, only for an optional stderr report),
   reset via [Hashtbl.reset] at [lower_module] entry. *)
let _alias_candidates : (string, string list) Hashtbl.t = Hashtbl.create 64
let _alias_reported   : (string, unit) Hashtbl.t = Hashtbl.create 16
let alias_audit_on = lazy (Sys.getenv_opt "MARCH_ALIAS_AUDIT" <> None)
let note_alias_candidate (short : string) (target : string) : unit =
  let cur = match Hashtbl.find_opt _alias_candidates short with
    | Some l -> l | None -> [] in
  if not (List.mem target cur) then
    Hashtbl.replace _alias_candidates short (target :: cur)

(* Resolve a variable name through use-import aliases.
   A name that is currently bound as a local (function parameter or
   let-binding tracked in [_fn_param_types]) is NOT resolved through
   aliases — local bindings shadow imports.  Without this guard, a
   parameter named e.g. [status] would be rewritten to [HttpServer.status]
   whenever [import HttpServer] is in scope, replacing every use of the
   local parameter with a global function reference. *)
(** Bare function names DEFINED by the module currently being lowered.  A
    same-module top-level fn shadows any import alias — including one another
    module's import added to the (program-global) [_use_aliases] table.
    Without this, e.g. CounterIsland.ssr's bare `render(state)` was rewritten
    to `Controller.render` (added by some other module's `import Controller`),
    silently calling the wrong function.

    NOT converted to an env field, despite [with_current_module_fns] below
    being a textbook exception-safe save/restore dance ([Fun.protect]): this
    ref is a member of the documented NOT-reset trio (analysis doc lower.ml
    High #2, alongside [_default_dispatch] and [_fn_param_types]). Its value
    is deliberately NOT reset at [lower_module] entry — [lower_module]'s Pass
    2 preamble sets it directly to the ENTRY module's own fn names, and that
    assignment happens AFTER Pass 1 ([collect_iface_impls ~lower_bodies:true],
    which lowers impl method bodies) has already run and read whatever this
    table held at the END OF THE PREVIOUS [lower_module] CALL (or its initial
    empty value, on the first call in the process). The REPL JIT
    (lib/jit/repl_jit.ml) calls [lower_module] once per fragment, so this
    staleness is live, load-bearing, current behavior — turning it into an
    env field reset fresh at the top of every [lower_module] call (the
    natural env-record idiom) would silently FIX (i.e. change) this.
    Preserved as a ref exactly. Filed: specs/todos.md. *)
let _current_module_fns : (string, unit) Hashtbl.t ref = ref (Hashtbl.create 0)

(** Run [f] with [_current_module_fns] set to [names], restoring the previous
    table afterwards (so nested module lowering composes correctly). *)
let with_current_module_fns (names : string list) (f : unit -> 'a) : 'a =
  let saved = !_current_module_fns in
  let tbl = Hashtbl.create (List.length names) in
  List.iter (fun n -> Hashtbl.replace tbl n ()) names;
  _current_module_fns := tbl;
  Fun.protect ~finally:(fun () -> _current_module_fns := saved) f

let resolve_use_alias (env : env) (name : string) : string =
  if Hashtbl.mem _fn_param_types name then name
  else if Hashtbl.mem !_current_module_fns name then name
  (* A bulk `import Mod` registers every public fn of Mod as an unqualified
     alias (see [register_aliases] / the DUse cases).  When one of those short
     names is a compiler builtin — e.g. [to_string], which has a generic
     value→string impl AND type-specific functions like [Bytes.to_string] — the
     alias would hijack the builtin PROGRAM-WIDE (the alias table is global): a
     later polymorphic call such as [to_string(v)] in an unrelated module would
     be rewritten to that one concrete impl and then crash on a value of the
     wrong type (e.g. a String matched as a Bytes(List(Int))).  The builtin must
     always win — matching the typechecker (which binds the polymorphic builtin)
     and the interpreter — so never resolve a builtin name through the alias
     table. *)
  else if Defun.StringSet.mem name Defun.builtin_names then name
  (* The current module's OWN imports take precedence over the program-global
     table, so [import Connection] in this module resolves [close] to
     Connection.close even if another module globally registered Db.close. *)
  else match Hashtbl.find_opt env.current_module_aliases name with
  | Some qualified -> qualified
  | None ->
  (* The GLOBAL [_use_aliases] table is populated program-wide by EVERY module's
     bulk imports (e.g. a `import Bastion` in one module registers the dotted
     short name `Logger.debug` -> `Bastion.Logger.debug`).  Consulting it for a
     MODULE-QUALIFIED (dotted) reference lets one module's import hijack an
     unrelated module's qualified call: a `Logger.debug(msg)` written in a
     module that never imported Bastion (and which the typechecker bound to the
     stdlib `Logger.debug/1`) would be rewritten at lowering to the arity-2
     `Bastion.Logger.debug`, emitting a call with an uninitialised second
     argument (RC underflow at runtime).  The importing module itself always
     also registers the alias into its OWN [current_module_aliases] (checked
     above), so restricting the global fallback to UNQUALIFIED (dot-free) names
     keeps intra-module resolution intact while matching the typechecker's
     per-module import scoping.  Dotted names fall through to the explicit
     module-alias prefix rewrite below. *)
  match (if String.contains name '.' then None
         else Hashtbl.find_opt !_use_aliases name) with
  | Some qualified ->
    (* GLOBAL-fallback resolution: the current module did not import this name
       itself.  If several distinct qualified candidates exist program-wide,
       this resolution is registration-order-dependent — the hijack class.
       Report once per name under MARCH_ALIAS_AUDIT. *)
    (if Lazy.force alias_audit_on && not (Hashtbl.mem _alias_reported name) then
       match Hashtbl.find_opt _alias_candidates name with
       | Some (_ :: _ :: _ as cands) ->
         Hashtbl.replace _alias_reported name ();
         Printf.eprintf
           "[alias-audit] bare `%s` resolved via GLOBAL table to %s (ambiguous: %s)\n%!"
           name qualified (String.concat ", " cands)
       | _ -> ());
    qualified
  | None ->
    (* Module-alias prefix rewrite (order-independent) — see [_module_aliases].
       Only consulted after every exact-name lookup above has missed, so an
       imported/sibling exact fn-alias always wins.  A dotted `Short.member`
       whose leading segment is a registered module alias is rewritten to
       `Long.Path.member`; this resolves an `alias` declared inside a
       non-entry module body, which builds no exact [!fns]-scanned entry when
       its target sibling is lowered after it (the undefined-symbol bug). *)
    (match String.index_opt name '.' with
     | None -> name
     | Some i ->
       let head = String.sub name 0 i in
       match Hashtbl.find_opt !_module_aliases head with
       | Some real_path ->
         real_path ^ String.sub name i (String.length name - i)
       | None -> name)

(* ── Qualified module lowering (refs) ──────────────────────────── *)

(** Module-level refs for function and type accumulators, set by [lower_module].
    Needed so [ensure_module_lowered] can append stdlib module definitions.

    NOT converted to env fields: [_fns_ref]/[_types_ref] are accumulators
    (each [lower_module] call points them at that call's own [fns]/[types]
    list-refs; [_ensure_module_lowered]'s closure and [lower_stdlib_mod_decls]
    append to them as a side effect throughout the whole run — there is no
    "restore" step, only reset-then-grow). They are ALSO poked directly by
    test/test_eval.ml's [test_tir_lower_qualified_auto_load] to exercise
    [_ensure_module_lowered] in isolation from a full [lower_module] call —
    a real (if unusual) external dependency on these being globally
    reachable refs, not env-record fields a caller would have to construct
    a full [env] to obtain. *)
let _fns_ref : Tir.fn_def list ref ref = ref (ref [])
let _types_ref : Tir.type_def list ref ref = ref (ref [])

(** Tracks which modules have already been lowered to avoid duplicates.
    NOT converted to an env field: same accumulator/test-coupling rationale
    as [_fns_ref] above ([test_tir_lower_qualified_auto_load] resets and
    reads this directly). Reset fresh at [lower_module] entry (part of the
    "reset-at-entry set", together with [_type_map_ref] (now [env.type_map]),
    [_iface_methods], [_use_aliases]). *)
let _lowered_modules : (string, unit) Hashtbl.t ref = ref (Hashtbl.create 8)

(** Forward ref — filled after [lower_fn_def] / [lower_type_def] are defined
    (now in [Lower_decls]). NOT convertible to an env field: this is a
    process-lifetime function pointer (the standard OCaml forward-reference
    idiom for breaking the ordering constraint that [lower_to_atom_k]/
    [lower_expr] — defined before [lower_stdlib_mod_decls] — need to call
    it). It is set exactly ONCE via [let () = _ensure_module_lowered := ...]
    at module-load time, never per-[lower_module]-call; the closure it holds
    reads [_fns_ref]/[_types_ref]/[_lowered_modules] (all refs) at call time,
    so it always sees whichever module's accumulators are currently
    installed. Also poked directly by [test_tir_lower_qualified_auto_load].
    Takes an [env] (threaded through to [lower_stdlib_mod_decls]/
    [lower_fn_def] for the lazily-loaded module's own body) as its first
    argument. *)
let _ensure_module_lowered : (env -> string -> unit) ref = ref (fun _ _ -> ())

(* ── Interface method resolution ────────────────────────────────── *)

(** Maps interface method names to a list of (concrete_type_name, mangled_fn_name).
    Used during lowering to rewrite calls like [show(42)] → [Show$Int.show(42)].
    Keys include BOTH base names (e.g. "checkpoint_get") AND fully-qualified
    names (e.g. "Conduit.Storage.checkpoint_get") so that polymorphic call sites
    that use qualified names can be resolved post-monomorphization.

    NOT converted to an env field: reset to a fresh table at [lower_module]
    entry (like [type_map]), but — unlike [type_map] — it is then WRITTEN TO
    throughout Pass 1 ([collect_iface_impls]) and Pass 2, with
    [resolve_iface_method] reading it INTERLEAVED with those writes (an impl
    registered while lowering module A's body must be visible when lowering
    module B's body later in the same pass). An accumulator, not a
    fixed-for-the-run constant — stays a ref, mirroring [_use_aliases]. *)
let _iface_methods : (string, (string * string) list) Hashtbl.t ref
  = ref (Hashtbl.create 0)

(** Saved copy of [_iface_methods] after the most recent [lower_module] call.
    Retained so that [Mono.monomorphize] can resolve interface calls in
    functions that were polymorphic during lowering but become concrete after
    type-variable substitution.

    NOT converted to an env field: deliberately a CROSS-CALL cache — written
    only at [lower_module] EXIT (never reset at entry) and read by
    [get_iface_methods] strictly AFTER [lower_module] has already returned
    its [Tir.tir_module] result (by [Mono.monomorphize], via the public
    [get_iface_methods ()] API). An [env] field cannot outlive the [env]
    value the function that produced it was holding — this ref's entire
    reason to exist is to outlive the call. *)
let _saved_iface_methods : (string, (string * string) list) Hashtbl.t ref
  = ref (Hashtbl.create 0)

(** Return the interface-method dispatch table built during the last call to
    [lower_module].  Used by the monomorphization pass. *)
let get_iface_methods () : (string, (string * string) list) Hashtbl.t =
  !_saved_iface_methods

(** Maps base function names to [(arity, mangled_name)] for default-arg functions.
    Built from [DFn] declarations whose names end with [$N] (N = arity number).
    Used to rewrite calls like [greet(x)] → [greet$1(x)] in the TIR pipeline.

    NOT converted to an env field: part of the documented NOT-reset trio
    (analysis doc lower.ml High #2, alongside [_current_module_fns] and
    [_fn_param_types]). It IS unconditionally reassigned inside every
    [lower_module] call (via [build_default_dispatch]) — but only AFTER Pass
    1's [collect_iface_impls ~lower_bodies:true] has already lowered impl
    method bodies against whatever this table held at the end of the
    PREVIOUS [lower_module] call. Converting to an env field constructed
    fresh at the top of [lower_module] would erase that inter-call
    staleness window Pass 1 currently runs inside — a genuine (if narrow)
    behavior change the plan's law forbids introducing silently. Preserved
    as a ref. Filed: specs/todos.md. *)
let _default_dispatch : (string, (int * string) list) Hashtbl.t ref
  = ref (Hashtbl.create 0)

(** Resolve an interface method call if possible.
    Given a method name and the inferred type of the first argument,
    returns the mangled impl function name, or None.
    Tries the name as-is first, then progressively strips module prefixes to
    handle calls like "Conduit.Storage.enqueue" when the impl was registered
    under "Storage.enqueue" (user wrote `impl Storage(T)` after `import Conduit`). *)
let resolve_iface_method (env : env) (method_name : string) (arg_span : Ast.span) : string option =
  let rec find_impls name =
    match Hashtbl.find_opt !_iface_methods name with
    | Some impls -> Some impls
    | None ->
      (match String.index_opt name '.' with
       | None -> None
       | Some i ->
         find_impls (String.sub name (i + 1) (String.length name - i - 1)))
  in
  match find_impls method_name with
  | None -> None
  | Some impls ->
    match env.type_map with
    | None -> None
    | Some tbl ->
      match Hashtbl.find_opt tbl arg_span with
      | None -> None
      | Some tc_ty ->
        let tc_ty = Typecheck.repr tc_ty in
        (* Extract the concrete type name from the typechecker type *)
        let type_name = match tc_ty with
          | Typecheck.TCon (name, _) -> Some name
          (* Tuples resolve by ARITY so a 2-tuple finds `Show$Tuple2` and a
             3-tuple finds `Show$Tuple3` (registration side: [Lower.type_name]
             for `Ast.TyTuple`). Arity-agnostic "$Tuple" collapsed all arities. *)
          | Typecheck.TTuple ts      -> Some (Printf.sprintf "$Tuple%d" (List.length ts))
          | Typecheck.TRecord _      -> Some "$Record"
          | _ -> None
        in
        match type_name with
        | None -> None
        | Some tname ->
          List.assoc_opt tname impls
