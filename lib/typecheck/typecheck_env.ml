(** The type environment: what is in scope, and how it is entered and left.

    [lin_entry], [ctor_info], [import_entry], [import_index], [proto_info],
    [StrMap], [ref_record], the 392-line [env] record itself, [make_env], the
    [lookup_*] / [resolve_qualified_*] / [suggest_*] family, the [bind_*]
    binders, and [generalize] / [instantiate].  Lifted verbatim out of
    [Typecheck] (§7–§8) on 2026-08-26; its only dependencies are three names
    from [Typecheck_types] ([session_ty], [fresh_var], [repr]).

    [open Typecheck_types], not [include]: [Typecheck] includes both modules,
    and including the type language twice would be a multiple-definition
    error.  [open] keeps the names visible here without re-exporting them.

    As in [Typecheck_types], the mutable cells this band declares stay single
    physical cells — [include] aliases them rather than copying them.

    See specs/plans/2026-08-19-compiler-file-decomposition.md (Phase 6,
    Task 6.3). *)

open Typecheck_types

(* =================================================================
   §7  Type environment
   ================================================================= *)

(** Linear-use record: name, qualifier, "has been used" flag. *)
type lin_entry = {
  le_name : string;
  le_lin  : Ast.linearity;
  le_used : bool ref;
  le_first_use : Ast.span option ref;
  (** Span of the use that consumed this value, recorded when [le_used] is
      first set. A double-use error is about a RELATIONSHIP between two sites,
      and reporting only the second one leaves the reader to find the first by
      hand — so the diagnostic points at both. Kept in step with [le_used]
      everywhere that flag is saved and restored (see [iter_arms_linear]). *)
}

(** Constructor info — populated from [DType] declarations.
    Describes one variant of a sum type so we can give [ECon] and
    [PatCon] real types instead of fresh variables. *)
type ctor_info = {
  ci_type    : string;           (** Parent type name, e.g. "Result" *)
  ci_params  : string list;      (** Type param names in declaration order *)
  ci_arg_tys : Ast.ty list;      (** Surface arg types of this constructor *)
  ci_vis     : Ast.visibility;   (** Constructor visibility (Public/Private) *)
  ci_module  : string;
  (** Declaring module of this constructor's parent type (empty at top level /
      prelude).  Additive metadata: [ci_type] is the BARE parent-type name and
      is deliberately kept bare for cross-module unification (see
      [prebind_mod_members]'s reverted qualified-ci_type experiment), so two
      same-named types' constructors are indistinguishable by [ci_type] alone.
      [ci_module] disambiguates them for [ctors_for_type]'s exhaustiveness
      universe, which otherwise merges a user `Handle`'s ctors with stdlib's
      same-named `Handle` (linear-L4 ctor cross-talk), AND — since the FQN
      dispatch-identity plan's Task 1 — is part of [add_ctor]'s structural
      dedup key, so two DIFFERENT modules' identically-shaped ctors (e.g. both
      a nullary `Shared`) are kept as distinct candidates instead of the
      second collapsing onto the first. It still feeds NO codegen/mangling/
      dispatch, so this is byte-identical at the backend for any program that
      does not hit this exact double-collision shape.  First metadata slice of
      the module-qualified ctor identity in
      specs/plans/2026-07-17-fqn-type-ctor-identity.md (Stage 4). *)
  ci_is_actor_msg : bool;
  (** True iff this constructor is an actor message handler's auto-registered
      ctor (an `on Msg(...)` arm), i.e. [ci_type] is some `<Actor>_Msg`.  Set
      at the three DActor registration sites; [false] everywhere else INCLUDING
      the actor's own zero-arg name ctor (used by `spawn`, not a message).
      The [ECon] typing arm reads this to decide whether to run
      [check_sendable] over the constructor's instantiated argument types —
      message payloads may not carry a mutable-buffer type (RingBuf,
      NativeIntArr, NativeFloatArr); ordinary user ADTs are unrestricted.
      Exactly one site (the cross-module [ExCtor] reconstruction, which only
      has an exported name+arity to work from, not the original record) can't
      set this from a known-true/false fact and instead derives it from the
      same "_Msg" suffix [Tir_names.is_actor_msg_name] uses post-lowering —
      justified there and ONLY there, because the export bridge is the one
      place this record is rebuilt from strictly less information than it
      started with. *)
}

(** One entry in the import tracker — records an imported name or alias and
    whether it was referenced at least once during typechecking. *)
type import_entry = {
  ie_span    : Ast.span;
  ie_desc    : string;              (** human-readable warning message *)
  ie_matches : string -> bool;      (** does looking up [name] count as "using" this? *)
  ie_used    : bool ref;
  ie_used_names : (string, unit) Hashtbl.t;
  (** WHICH of this import's names were actually referenced.  [record_use]
      already computes this -- the index hit tells us precisely which imported
      name a reference resolved to -- and until now it was collapsed to
      [ie_used] and discarded.  Demand-driven capability propagation (Check 4)
      consumes it: an importer inherits only the capabilities of the functions
      it actually references, not the imported module's whole set.

      Bare names for the exact-name index (a rebound short name from
      `import M`), FULL DOTTED names for the prefix index (a qualified
      `M.foo` reference under `use M`).  Both spellings are resolved against
      the closure table by [check_module_needs]. *)
}

(* Index bookkeeping for [record_use]'s import-tracker lookup.  [record_use]
   runs once per EVar in the WHOLE combined program (stdlib + every
   auto-discovered file), so it must not re-scan the full [import_tracker]
   list (whose length is O(total use/import/alias decls across the whole
   program)) on every call -- that pairing is O(var-refs * imports), which
   is quadratic-and-then-some on a multi-hundred-file project.  Instead each
   entry is also indexed by every literal name it can EXACT-match (module
   short names / aliased names) into [ie_exact_index], and by its
   qualification prefix (the module/alias name before the dot) into
   [ie_prefix_index], so [record_use] does two O(1)-average Hashtbl lookups
   instead of an O(n) scan.  This mirrors -- but does not replace -- each
   entry's original [ie_matches] closure, which remains the source of truth
   used at entry-creation time to populate the index (no behavior change,
   just no longer scanning the flat list at lookup time). *)
type import_index = {
  ie_exact_index  : (string, import_entry list) Hashtbl.t;
  (** name -> entries that match it via an EXACT name (short_names / n.txt /
      short_name), populated with the same names the closures compare against. *)
  ie_prefix_index : (string, import_entry list) Hashtbl.t;
  (** prefix root (mod_str for Use*, alias short_name for DAlias) -> entries
      that also accept a qualified reference under that prefix.  [record_use]
      only consults this when the looked-up name contains a '.'. *)
}

let make_import_index () =
  { ie_exact_index = Hashtbl.create 64; ie_prefix_index = Hashtbl.create 16 }

let import_index_add_exact idx key entry =
  let prev = try Hashtbl.find idx.ie_exact_index key with Not_found -> [] in
  Hashtbl.replace idx.ie_exact_index key (entry :: prev)

let import_index_add_prefix idx key entry =
  let prev = try Hashtbl.find idx.ie_prefix_index key with Not_found -> [] in
  Hashtbl.replace idx.ie_prefix_index key (entry :: prev)

(** Computed session-type information for a declared [protocol].
    Stored in [env.protocols] after [DProtocol] is checked. *)
type proto_info = {
  pi_def         : Ast.protocol_def;
  pi_projections : (string * session_ty) list;  (** role → local session type *)
  pi_span        : Ast.span;
}

module StrMap = Map.Make(String)

(** A resolved reference recorded during typechecking: [callee] used a
    declaration that [caller] (both fully-qualified "Mod.name") owns, at
    [ref_file]:[ref_line]. Populated only where resolution already succeeds —
    never a textual guess. *)
type ref_record = {
  callee   : string;
  caller   : string;
  ref_kind : [ `Call | `Ctor | `TypeRef ];
  ref_file : string;
  ref_line : int;
}

(** Qualify [name] with [modname] the one way every [ref_record] site should:
    ["Mod.name"], or bare [name] when [modname] is empty. An empty module
    name shows up for prelude constructors ([Cons]/[Nil]/[Some]/[None]/[Ok]/
    [Err], whose [ci_module] is "") and for the bare-module case generally —
    without this, ad-hoc `modname ^ "." ^ name` concatenation at each
    recording site produces a callee/caller literally starting with "." for
    those references, which [Search.search_callers]'s query-side lookup can
    never match (its own [qualified_of] already treats an empty module name
    this way). Shared by the [EVar]/[ECon]/[TyCon] reference-recording hooks
    so the convention can't drift between them. *)
let qualify_ref_name (modname : string) (name : string) : string =
  if modname = "" then name else modname ^ "." ^ name

type env = {
  vars    : scheme StrMap.t;               (** Term variable → scheme *)
  types   : int StrMap.t;                  (** Type constructor name → arity *)
  ctors   : ctor_info list StrMap.t;       (** Data constructor name → all infos (head = most recent) *)
  records : (string list * (string * Ast.ty) list) StrMap.t;
    (** Named record type definitions: name → (type_params, [(field, surface_ty)]) *)
  level   : int;                           (** Current generalization level *)
  lin     : lin_entry list;                (** Linear/affine use tracking *)
  errors  : Err.ctx;
  pending_constraints : constraint_ list ref; (** Accumulated use-site constraints *)
  type_map : (Ast.span, ty) Hashtbl.t;
  refs : ref_record list ref;
  (** Resolved call/ctor/type references accumulated during checking, for
      `forge search --callers`. Shared (mutable) across all env copies
      derived from the same root, same as [import_tracker]. *)
  current_decl : string ref;
  (** Fully-qualified name ("Mod.fn") of the top-level fn/impl-method whose
      body is currently being checked. Set by [check_fn]; read wherever a
      [ref_record] is recorded so it knows its caller. Empty string before
      the first fn is entered. *)
  scheme_witnesses : (int list, constraint_ list * ty) Hashtbl.t;
  (** A1 (--emit-core-ast v2): every HM scheme instantiated during checking,
      deduped by its quantified-id list -> (constraints, body). Populated at
      the single [instantiate] chokepoint (Poly branch) so user, builtin, and
      stdlib schemes are all uniformly captured. Read by the emitter to
      serialize which schemes were generalized. *)
  inst_witnesses : (Ast.span, int list * ty list) Hashtbl.t;
  (** A1 (--emit-core-ast v2): for every polymorphic use site that supplied a
      [~use_span] to [instantiate] (EVar/EField inference), the scheme's
      quantified-id list paired positionally with the freshly-substituted
      (post-solve, [repr]-resolvable) type-argument vector. Keyed by the
      use-site span so the emitter can look up "how did THIS occurrence
      instantiate its scheme." *)
  interfaces : Ast.interface_def StrMap.t; (** Registered interfaces *)
  sigs       : (string * Ast.sig_def) list;       (** Registered module signatures *)
  mod_needs  : string list;
  (** Capabilities declared via [needs] in the current module scope, as dot-joined paths *)
  mod_need_scopes : (string * string option) list;
  (** Those same declarations paired with their optional PATH SCOPE, from
      [needs IO.FileRead("/etc/app")].  Parallel to [mod_needs], which keeps
      the bare paths every existing consumer reads, so nothing that treats a
      capability as a plain string is disturbed.  [None] means unscoped.
      A capability declared twice contributes one entry per scope, so
      [needs IO.FileRead("/a"), IO.FileRead("/b")] permits both subtrees. *)
  module_caps : (string * string list) list;
  (** Capabilities required by checked sub-modules: module name → list of cap paths.
      Populated when a [DMod] is fully checked; used for transitive enforcement.
      Each module contributes an entry under its fully-qualified path (matching
      TIR attribution, which the --cap-strict ceiling joins against) and, when
      that differs, a second one under its bare name (matching `use` paths as
      written, which Check 4 looks up).  Entries from modules nested inside a
      [DMod] propagate outward through it. *)
  protocols  : proto_info StrMap.t; (** Registered session-type protocols *)
  impls      : (ty * Ast.span * string option) list StrMap.t;
  (** iface_name → (bare impl head type, decl span, resolved declaring-module of
      the head type — None when unresolved). Head type stays BARE so
      [discharge_constraints] is unaffected; the module is used ONLY by the
      coherence overlap test. *)
  import_tracker : import_entry list ref;
  (** Accumulated import/alias entries for unused-import warning detection.
      Shared (mutable) across all env copies derived from the same root. *)
  import_idx : import_index;
  (** O(1)-average-lookup index mirroring [import_tracker] -- see
      [import_index] for why [record_use] must not scan [import_tracker]
      directly.  Shared (mutable) across all env copies derived from the
      same root, same as [import_tracker]. *)
  local_fns : unit StrMap.t;
  (** Function names DEFINED by the module currently being checked (set from
      the pass-1 / DMod forward-reference prebind).  A bulk import
      ([import X] / [import X except (...)]) must NOT rebind these bare
      names: the local definition shadows the import.  Without this guard
      the import clobbers the local fn's pass-1 placeholder with the
      imported module's concrete scheme, and check_fn then unifies the
      local definition against the WRONG function's type (manifesting as
      nonsense arity/type errors on the local fn's header). *)
  fn_arities : (int * Ast.span) StrMap.t;
  (** Declared parameter count of functions DEFINED in the current module
      scope (populated alongside [local_fns] in the pass-1 prebind).  March
      has no partial application — calling a known function with the wrong
      number of arguments panics at runtime (and the compiler miscompiles
      under-application into a body call with a garbage argument).  Used to
      reject wrong-arity calls of these functions at the call site. *)
  qual_fn_names : unit StrMap.t;
  (** Qualified ("Mod.name") keys in [vars] that denote a genuine top-level
      function — i.e. a [DFn], an interface method, or a registry [ExFn]
      export — never a [DLet] value/constant. Populated at three sites: the
      [Ast.DMod] export step (mirrors [new_names], restricted to keys
      already known to be functions via [local_fns]/[qual_fn_names] of the
      inner env — so it composes correctly across nested modules),
      [load_module_into_env]'s [ExFn] arm (registry-loaded modules), and
      [prebind_interface_decl] (interface methods, bound as both
      "Iface.method" and "Mod.Iface.method" — a call-syntax reference to
      these bypasses both other sources entirely). Consulted by the
      [Ast.EVar] reference-recording hook so a qualified value reference
      (`Mod.SOME_CONST`) is never recorded as a `` `Call `` reference, while
      a qualified function/interface-method call still is — see [local_fns]
      for the bare-name analogue of this same distinction. *)
  plain_let_names : StringSet.t;
  (** Names most recently bound by a simple, unrestricted `let name = expr`
      (single-variable pattern — see the [Ast.ELet] case of [infer_block]).
      Used ONLY by the [Ast.EApp] handler's zero-arg "calling a non-function
      local value" check (`zf()` where `let zf = answer` — see the
      [noncallable_error] comment there) as a POSITIVE, narrowly-scoped
      signal, deliberately not reusing [fn_arities]'s absence: unlike
      [fn_arities] (name-keyed and cleared by [bind_var] on every rebind,
      including a bulk `import Mod`'s re-binding of an imported function
      under its short name — see [bind_var]'s comment), this field is only
      ever ADDED to at one site, so it can't be accidentally emptied by an
      unrelated rebinding elsewhere in the same threaded env. *)
  proof_caps : (string * string) list;
  (** Proof cap registry: full cap path → declaring module name.
      Populated by [DProofCap] during check_decl; checked by check_module_needs. *)
  always_linear_types : string list;
  (** Set of type constructor names declared with [always_linear type].
      Any binding whose inferred type is [TCon(name, _)] with [name] in this list
      is automatically tracked as linear — no per-site [linear] annotation needed. *)
  current_module : string;
  (** Name of the module currently being typechecked, empty string at top level. *)
  root_cap_allowed : bool;
  (** True where naming [root_cap] is still permitted (R2, 2026-08-05).

      [root_cap] used to be an ordinary global of type [Cap(IO)] in scope in
      every module, which is no-authority-from-nothing violated at the source:
      a module declaring no [needs] at all could hold the root and narrow it to
      any descendant, legitimately, because [cap_narrow] demands exactly the
      parent it now had.  The root is now granted to [main] instead (see
      [Desugar.check_main_signature]; the runtime already passed it).

      Two contexts keep it, both deliberate and both scoped by ENCLOSING
      CONTEXT rather than by the checker declining to look — the distinction
      matters, because "we never checked here" and "we decided not to check
      here" are indistinguishable from the passing test:

      - [test]/[describe]/[setup] bodies, which have no [main] to be granted
        from.  Without this, capability behaviour would not be testable from
        March at all.  It is ambient authority, in a context that cannot reach
        production code: a dependency's test blocks do not run in a consumer's
        build.
      - the REPL, which likewise has no entry point.  Carried by
        [check_module_with_env], whose only caller is [lib/jit/repl_jit.ml]. *)
  cur_fn_public : bool;
  (** True while checking the body of a PUBLIC (fn, not pfn) function — read by
      the proof-cap mint gate. Lambdas inherit it; nested named fns/modules reset
      it via their own check_fn. *)
  cap_qual_prefix : string;
  (** Accumulated dotted-path prefix of enclosing [DMod]s, for keying
      [cap_closures] so it matches TIR's fully-qualified function-name
      convention (see [lib/tir/lower.ml]'s [mod_prefix] accumulation).  Unlike
      [current_module] (which is REPLACED, not accumulated, on entry to each
      nested module — see the [Ast.DMod] branch of [check_decl] — and is used
      elsewhere for unrelated purposes that must not be perturbed),
      [cap_qual_prefix] accumulates across nesting: "" at the entry module,
      then "Lib", then "Lib.Sub", etc., mirroring [prebind_mod_members]'s
      [prefix ^ "." ^ mname.txt] recursion. The entry module's own name is
      NOT included (TIR unwraps the entry module), so this starts empty. *)
  enclosing_package : string;
  (** Top-level module name of the file being checked, set ONCE and never
      overwritten as nested modules are entered.  [current_module] is only the
      bare name inside a nested `mod Sub`, and [cap_qual_prefix] is "" at the
      entry module, so neither answers "which package does this code belong
      to" — which bare-constructor ambiguity needs, so that a package's own
      constructor is not reported ambiguous against an unimported stdlib type. *)
  no_panic_mod : bool;
  (** True when the module currently being checked has `cap no_panic`.
      Set by [check_decl] on [DOpts ["no_panic"]]; read by [check_no_panic_module]. *)
  no_panic_modules : string list;
  (** Names of modules (siblings/imports) that have been verified as [cap no_panic].
      Functions from these modules are treated as safe in [check_no_panic_module]. *)
  nonexhaustive_match_spans : Ast.span list ref;
  (** Spans of every NON-exhaustive [match] discovered by [check_exhaustiveness]
      anywhere in the compilation.  A non-exhaustive match lowers to a runtime
      "no matching clause" panic, so it is a panic surface that
      [check_no_panic_module] must reject — but only for matches nested inside a
      `cap no_panic` module's OWN function bodies (attributed by span
      containment, see [span_within]).  A mutable ref shared (like
      [import_tracker]) across every env copy so all sites append to one list;
      recording here is cheap and never itself an error — the read/attribution
      is gated inside [check_no_panic_module], which only runs for
      `cap no_panic` modules, so a PLAIN module's non-exhaustive match stays a
      Warning and is never promoted to an error. *)
  cap_producer_ivars : (int, Ast.span) Hashtbl.t;
  (** Inner cap-argument [TVar] id → the [cap_narrow] application span that
      produced it.  A [cap_narrow(cap)] result is [Cap(a)]; we tag [a]'s id here.
      [unify] consults this table: the instant [a] (or any var linked to it) is
      bound to a nominal proof cap [TCon(p,[])] with [p] in [proof_caps], it is a
      forge (a proof cap can ONLY come from [mint_cap] in a public declaring-
      module fn or from a parameter pass-through — never from [cap_narrow]) and
      the binding is rejected.  IO caps are not in [proof_caps], so legitimate
      IO-lattice narrowing ([Cap(IO) -> Cap(IO.Network)]) is unaffected in every
      position, including laundering through a polymorphic function.  A shared
      hashtable (like [cap_closures]) so every env copy sees the same tags. *)
  cap_narrow_factory_fns : (string, Ast.span) Hashtbl.t;
  (** Names of user functions whose body IS (or launders) a [cap_narrow] result —
      a "cap-narrow factory" (e.g. `fn mk(cap) do cap_narrow(cap) end`).  A
      cross-module reference to such a fn resolves to its PREBOUND scheme (whose
      vars are distinct from the pass-2 [check_fn] vars we tag), so the unify hook
      cannot see the taint through the call.  We instead record the factory name
      here and, at the call site, taint the call's result.  (NOTE: this path does
      not yet close the nested-module cross-resolution route — see the batch-a
      report's Critical-fix section; it is retained as it closes same-module
      factory calls and is harmless.)  Shared hashtable so every env copy sees the
      same factory set. *)
  cap_dicts : (string * string) list;
      (** Capability path -> the DICTIONARY TYPE it declares, as written in the
          `proof cap Live with SessionOps` clause.  A capability absent from
          this list is runtime-erased exactly as every capability was before
          dictionaries existed; [cap_impl]/[cap_dict] on one is an error.
          Populated by [DProofCap] during check_decl, read by the [cap_dict]
          inference arm and by [check_cap_impl_sites]. *)
  cap_dict_decl_sites : (Ast.span * string * string) list ref;
      (** (span, cap path, dictionary type name as written) for every `with`
          clause.  Validated by [check_cap_dict_decls] as a post-checking sweep
          rather than at the declaration, because a `proof cap` may name a
          record type declared LATER in the same module. *)
  cap_impl_sites : (Ast.span * ty * ty * bool * string) list ref;
      (** (span, result type, dictionary-argument type, enclosing fn is public,
          enclosing module) for every [cap_impl] application.  Swept by
          [check_cap_impl_sites].  Deferred for exactly the reason
          [mint_cap_sites] is: the result cap is pinned by LATER unification
          (typically the enclosing fn's return annotation), so the gate cannot
          be decided at the application. *)
  cap_dict_sites : Ast.span list ref;
      (** Every [cap_dict] application.  Not used for any CHECK — the [cap_dict]
          arm resolves at the site — but the driver reads it, together with
          [cap_impl_sites], to refuse a COMPILED build with a proper diagnostic:
          capability dictionaries run interpreted only for now. *)
  mint_cap_sites : (Ast.span * ty * bool * string) list ref;
  (** Every [mint_cap(_)] application site, recorded as
      (span, result_type, cur_fn_public, current_module).  The mint GATE is
      checked by a post-checking sweep ([check_mint_cap_sites]): the result
      type is pinned by later unification (so it can only be inspected after the
      whole compilation is checked), while the enclosing-fn/module CONTEXT
      ([cur_fn_public], [current_module]) must be captured HERE because it is
      per-site and unavailable at sweep time.  A [mint_cap] typechecks iff its
      pinned result is [Cap(P)] with [P] a proof cap whose declaring module is
      [current_module] AND [cur_fn_public]; a proof cap from another module, a
      private fn, or a non-proof (IO) target is rejected. *)
  cap_narrow_sites : (Ast.span * ty) list ref;
  (** Every [cap_narrow] application site, as (span, the INSTANTIATED arrow).
      Swept by [check_cap_narrow_sites] to enforce that the source capability
      SUBSUMES the target — R4a's replacement for the monotonicity the old
      [Cap(IO) -> Cap(a)] argument type enforced through unification.

      Deferred for the same reason as [mint_cap_sites] and [json_cap_sites]:
      the result type is a bare var at the application site and is pinned by
      LATER unification.  See
      [specs/lang/types/reject/t155_cap_narrow_widen_deferred.march], which
      exists to fail if this is ever made eager. *)
  json_cap_sites : (Ast.span * ty * string) list ref;
  (** Every [to_json] / [from_json] / [from_json_events] application site,
      recorded as (span, the INSTANTIATED arrow type of the builtin, builtin
      name).  Swept after checking by [check_json_cap_sites], which rejects a
      capability in the encoded argument or the decoded result — capability
      unforgeability, R3.

      These three are the only builtins typed [poly2 (fun a b -> TArrow (a,
      b))] (see the binding block below), i.e. the only ones whose type places
      no constraint whatsoever on what they produce.  Nothing in [from_json]'s
      signature stops it returning [Cap(IO)].

      Why the arrow and not just the result: [to_json] is checked on its
      ARGUMENT (encoding a capability manufactures the wire value a decoder
      would consume) while the [from_json] family is checked on its RESULT.
      Recording the instantiated arrow captures both in one value, and its two
      vars are unified in place by [infer_app], so the arrow read at sweep
      time carries the solved argument and result.

      Why a deferred sweep rather than an inline check — this is the whole
      reason the mechanism exists: the result var is routinely NOT pinned at
      the application site.  In [let x = from_json(s)] followed by
      [cap_narrow(x)], it is the LATER [cap_narrow] that unifies [x] with
      [Cap(IO)].  An inline check reads an unsolved [TVar], reports nothing,
      and still passes every test that writes the annotation inline.  Same
      trap as [mint_cap_sites] above; see
      [specs/lang/types/reject/t143_cap_from_json_deferred_zonk.march], which
      exists specifically to fail if this is ever made eager. *)
  pure_mod : bool;
  (** True when the module currently being checked has `cap pure`.
      Set by [check_decl] on [DOpts ["pure"]]; read by [check_pure_module]. *)
  no_extern_mod : bool;
  (** True when the module currently being checked has `cap no_extern`.
      Set by [check_decl] on [DOpts ["no_extern"]]; read by [check_no_extern_module]. *)
  deterministic_mod : bool;
  (** True when the module currently being checked has `cap deterministic`.
      Set by [check_decl] on [DOpts ["deterministic"]]; read by [check_deterministic_module]. *)
  cap_closures : (string, string list) Hashtbl.t;
  (** Per-function inferred IO-capability closure: fully-qualified function
      name ("Mod.fn") → normalized list of cap paths that function requires,
      as computed by [check_module_needs] (declared [needs] in scope, Cap-typed
      signatures, body-scanned builtin calls, extern-implied caps, and
      transitively-imported module needs). Mutated in place (shared across all
      [env] copies derived from the same root, like [type_map]) so it survives
      threading through [check_decl]'s per-declaration env folds. Read via
      [fn_capability_closures]; a later hot-deploy manifest task consumes this. *)
  own_cap_closures : (string, string list) Hashtbl.t;
  (** Per-function OWN inferred IO-capability closure: fully-qualified function
      name ("Mod.fn") -> normalized list of cap paths that function's own
      signature/body/extern usage requires, WITHOUT the [module_wide_caps]
      merge that [cap_closures] performs. Accumulated across the multiple
      [record_fn_caps] call sites per function (sig + body + extern) exactly
      like [cap_closures], just without folding in the module-level [needs].
      This is the projection the migrate_state IO-free check needs: a
      [migrate_state] function living in an actor module that declares
      [needs IO.Console] for its *handlers* must not be falsely flagged just
      because the module-wide merge would attribute that cap to it too.
      Read via [fn_own_capability_closures]. *)
  body_cap_closures : (string, string list) Hashtbl.t;
  (** Per-function DIRECT BODY capability set: fully-qualified function name
      -> the caps its own body reaches by calling BUILTINS directly, WITHOUT
      signature caps and WITHOUT the transitive/module-wide merges the other
      two tables carry. This is the seed the `--check`-side capability ceiling
      ([check_stdlib_mediated_ceiling]) needs: a `Cap(X)` parameter is not a
      body USE (it is handled by Check 1/4), so folding sig caps in here would
      reintroduce the `fn main(cap : Cap(IO))` false positive that
      specs/progress/2026-08-08-ceiling-signature-only-fixed.md closed on the
      `--compile` side. Recorded at the BODY-scan call sites only (never the
      sig_caps site), keyed exactly like [cap_closures]. *)
  stdlib_fns : (string, unit) Hashtbl.t;
  (** The set of fully-qualified function names whose declaration is
      stdlib-spanned (via [span_is_stdlib]) — i.e. the TRANSPARENT set for the
      ceiling: a stdlib wrapper's body caps roll up to the user module that
      calls it, exactly as [March_tir.Cap_attrib]'s [~transparent] does on the
      `--compile` side. Keyed like [cap_closures]. *)
  ceiling_extra_roots : (string, unit) Hashtbl.t;
  (** Function-name keys that are ALWAYS-reachable ceiling roots regardless of
      whether the program has a `main` — mirroring the unconditional roots
      [March_tir.Dce.root_names] keeps: module-level [let] bindings (lowered
      into the always-run `__march_setup__`, so their side effects cannot be
      skipped) and `_migrate_state` functions. Without seeding the ceiling's
      reachability walk with these, a module-level `let` reaching a
      stdlib-mediated capability would be pruned as "unreachable from main" and
      the ceiling would miss it — a violation `--compile` still catches. *)
  fn_refs : (string, string list) Hashtbl.t;
  (** Per-function REFERENCE edges: fully-qualified function name ("Mod.fn",
      or the BARE name for a top-level function of the entry module — the same
      key convention as [cap_closures]) -> every name its body references.

      Collected with [free_vars_expr], NOT with [March_ast.Calls]: a function
      passed as a VALUE ([map(xs, helper)]) is a real capability edge and a
      calls-only walk misses it entirely, which is fail-open. Mutated in place
      like [cap_closures], so it survives the per-declaration env folds.

      Recorded at exactly the [record_fn_caps] call sites, so a key here is a
      key there. Consumed only by [fn_transitive_capability_closures]. *)
  fn_row_bodies : (string, (string list * Ast.expr) list) Hashtbl.t;
  (** R1 stage C: per-function ROW seeds, keyed exactly like [fn_refs] and
      recorded at exactly the [record_fn_refs] call sites.  Where [fn_refs]
      answers "what does this function reference", a seed answers the two
      questions a PER-FUNCTION grant needs and a whole-program grant did not:
      which of its own parameters it invokes (the conditional, effect-
      polymorphic part of its row) and whether it invokes a value whose
      creation site cannot be traced (the part no caller can discharge).

      Purely additive: with an empty table [Cap_rows.solve] reproduces the
      pre-stage-C flat closure exactly, which is why
      [fn_transitive_capability_closures_tbl] can be its caps projection
      rather than a second implementation.  See
      [specs/2026-08-10-r1-stage-c-effect-rows-design.md]. *)
  fn_grant_points : (string, string list * Ast.span) Hashtbl.t;
  (** Functions whose signature carries a concrete [Cap(P)] parameter —
      qualified name → (the concrete capability paths their PARAMETERS grant,
      the span to report against).  Recorded by [check_module_needs] (which
      already owns the [cap_qname] convention and already runs for nested
      modules).

      R1 stage C (2026-08-10) once consumed this at the end of
      [check_module_core] to make every [Cap(P)]-parameter function its own
      grant-discharge point.  That check ([check_fn_grants]) was REMOVED
      2026-08-13: it made any capability parameter a ceiling over everything
      the function transitively reached, forcing every caller to thread
      capabilities the module-scoped design does not require.  This table is
      still populated — Task 8 reads it to attribute a whole-program grant
      violation to the user's call chain — but nothing currently checks it.
      [main] is excluded regardless — [check_main_grant] owns it. *)
  local_mods : string list StrMap.t;
  (** In-file nested modules → their PRIVATE value/function member names.
      Populated by the [Ast.DMod] export step.  A same-file qualified reference
      to a private member (e.g. `A.secret` where `secret` is a [pfn]) never gets
      an "A.secret" key in [vars] (only public members are exported), so the
      registry-based [qualified_error_msg] would misreport "Unknown module `A`"
      for a module that plainly exists in this file.  This lets that path
      recognize the member is merely private and emit the accurate
      "Function `secret` is private to module `A`." instead. *)
  offer_conts : (session_ty ref * (string * session_ty) list) list ref;
  (** Session-type OFFER continuation registry (F5 path-dependent refinement).
      Every [Chan.offer(ch)] registers the (physical) session ref it hands back
      alongside that offer's full label→continuation map.  Because the returned
      channel and the returned label atom come from the SAME offer, a later
      `match <label> do :L -> ... end` can refine the channel — whose session
      ref is registered here — to [branches[L]] for the duration of the `:L`
      arm, instead of always typing it at the FIRST branch's continuation (the
      old conservative-but-unsound-for-multi-branch approximation).  A shared
      mutable ref (like [nonexhaustive_match_spans]) so the registration made
      deep inside [infer_expr]'s [Chan.offer] arm is visible to [infer_block]'s
      let-destructuring, which builds the label→ref linkage in [offer_labels]. *)
  offer_labels : (string * (session_ty ref * (string * session_ty) list)) list;
  (** Label-variable → (offer channel's session ref, branches) linkage.
      Populated by [infer_block] when a `let (lbl, ch) = Chan.offer(...)`
      destructures an offer result: [ch]'s session ref is looked up in
      [offer_conts] and bound here under [lbl]'s name.  Read by the `match`
      typing ([infer_match] / the [check_expr] EMatch arm): when the scrutinee
      is such a [lbl] and an arm matches label `:L`, the shared ref is
      transiently set to [branches[L]] while that arm body is checked. *)
  offer_unrefined : session_ty ref list ref;
  (** Offer continuations awaiting per-arm refinement (F5 residual, 2026-07-24).
      [Chan.offer] registers the session ref it hands back here IFF the offer's
      branch continuations are not all identical — in that case the returned
      channel's real state depends on which label the peer chose at runtime, so
      operating on it before a `match` on the paired label refines it would type
      the channel at the FIRST branch (silent type confusion: compiled, a
      String payload gets read as an Int).  [with_offer_refinement] transiently
      removes the ref while checking a refined arm; the [Chan.*] operation arms
      reject any channel still listed here.  A shared mutable ref for the same
      reason [offer_conts] is one. *)
}

let make_env errors type_map = {
  vars = StrMap.empty; types = StrMap.empty; ctors = StrMap.empty; records = StrMap.empty;
  level = 0; lin = [];
  errors; pending_constraints = ref []; type_map;
  refs = ref []; current_decl = ref "";
  scheme_witnesses = Hashtbl.create 64;
  inst_witnesses = Hashtbl.create 256;
  interfaces = StrMap.empty; sigs = [];
  mod_needs = []; mod_need_scopes = []; module_caps = []; protocols = StrMap.empty; impls = StrMap.empty;
  import_tracker = ref [];
  import_idx = make_import_index ();
  local_fns = StrMap.empty;
  fn_arities = StrMap.empty;
  qual_fn_names = StrMap.empty;
  plain_let_names = StringSet.empty;
  proof_caps = [];
  always_linear_types = [];
  current_module = "";
  root_cap_allowed = false;
  cur_fn_public = false;
  cap_qual_prefix = "";
  enclosing_package = "";
  no_panic_mod = false;
  no_panic_modules = [];
  nonexhaustive_match_spans = ref [];
  cap_producer_ivars = Hashtbl.create 16;
  cap_narrow_factory_fns = Hashtbl.create 16;
  cap_dicts = [];
  cap_dict_decl_sites = ref [];
  cap_impl_sites = ref [];
  cap_dict_sites = ref [];
  mint_cap_sites = ref [];
  cap_narrow_sites = ref [];
  json_cap_sites = ref [];
  pure_mod = false;
  no_extern_mod = false;
  deterministic_mod = false;
  cap_closures = Hashtbl.create 64;
  own_cap_closures = Hashtbl.create 64;
  body_cap_closures = Hashtbl.create 64;
  stdlib_fns = Hashtbl.create 64;
  ceiling_extra_roots = Hashtbl.create 16;
  fn_refs = Hashtbl.create 64;
  fn_row_bodies = Hashtbl.create 64;
  fn_grant_points = Hashtbl.create 16;
  local_mods = StrMap.empty;
  offer_conts = ref [];
  offer_labels = [];
  offer_unrefined = ref [];
}

let enter_level env = { env with level = env.level + 1 }
let leave_level env = { env with level = env.level - 1 }

(** Run [f] with [env.current_decl] temporarily blanked to "" — for
    [surface_ty] calls that check a type with NO enclosing function (an
    interface method signature, an impl header/when-constraint type): without
    this, [env.current_decl] is left over from whatever [DFn] happened to be
    checked immediately before in module order (it is set only by [check_fn]
    and never reset — see [current_decl]'s doc comment), so a qualified
    `TyCon` reference recorded there would be silently misattributed to an
    unrelated function.  The [`TyCon] hook in [surface_ty] skips recording
    entirely when [caller = ""], so blanking here means "don't record a
    reference for this callerless type position" rather than emitting a
    deliberately-empty [caller].  [current_decl] is a mutable ref shared
    across all [env] copies (like [import_tracker]), so this must restore the
    prior value afterward — including when [f] raises — rather than leaving
    it blanked for whatever is checked next. *)
let with_no_caller (env : env) (f : unit -> 'a) : 'a =
  let saved = !(env.current_decl) in
  env.current_decl := "";
  Fun.protect ~finally:(fun () -> env.current_decl := saved) f

(** Is [r] an [offer] continuation still awaiting per-arm refinement?
    Physical identity on purpose: [env.offer_unrefined] tracks the exact ref
    [Chan.offer] minted, and the ref cell IS the channel's identity for the
    duration of the session (every [Chan.*] op mints a FRESH ref for its
    continuation, so a marked ref can never be confused with a later state of
    the same channel). *)
let offer_ref_unrefined env (r : session_ty ref) =
  List.exists (fun r' -> r' == r) !(env.offer_unrefined)

(** Depth of enclosing `match` arms that are a CATCH-ALL over an offer label
    (`_ ->` / a variable pattern, where [with_offer_refinement] cannot refine
    because the arm names no label).  Non-zero means the user did write a
    `match`, so the bare "match the label first" advice would read as wrong —
    the diagnostic appends the real explanation instead (a catch-all does not
    identify WHICH branch the peer chose).  A global counter rather than an
    [env] field because [env] is copied by every binding construct while this
    must track dynamic nesting of the checking recursion. *)
let offer_catchall_depth = ref 0

(** The shared body of the "unrefined `Chan.offer` continuation" diagnostic.
    [lead] names what is being attempted ("Chan.recv", "This channel"). *)
let offer_unrefined_message lead =
  Printf.sprintf
    "%s came from `Chan.offer`, and the protocol's branches \
     continue differently, so I don't know which one the peer chose.\n\
     Match on the label first — `match lbl do :ok -> ... :err -> ... end` — \
     and use the channel inside each arm.%s"
    lead
    (if !offer_catchall_depth > 0 then
       "\nA `_` catch-all arm is not enough: it does not identify which branch \
        the peer chose, so every label needs its own arm."
     else "")

(** Value restriction for capability-producer applications.  Lower every
    [Unbound] TVar reachable in [ty] to level 0 IN PLACE, so [generalize]
    (which quantifies vars at [l > level] for any [level >= 0]) can NEVER
    quantify them.  The result type of a [cap_narrow]/[mint_cap] application is
    expansive (a function call) and must not be let-generalized: if
    [let x = cap_narrow(cap)] generalized [x] to [∀a. Cap(a)], each use would
    instantiate a FRESH [a] pinned to that use's type while the compiler's
    single recorded result node stayed an unbound quantified var — defeating the
    post-checking proof-cap sweep and REOPENING the forge in every let-/generic-
    flow position (a value narrowed once and reused as different caps).  Pinning
    the result to a single monomorphic var makes the use-site's type flow back to
    the recorded node, so the sweep sees the concrete cap.  Consequence: a single
    [cap_narrow]/[mint_cap] value used at two DIFFERENT cap types no longer
    typechecks (the one var can't unify with both) — that pattern is not
    least-privilege threading and does not occur in real code. *)
let rec demote_to_monomorphic (t : ty) : unit =
  match t with
  | TVar r ->
    (match !r with
     | Unbound (id, l) -> if l > 0 then r := Unbound (id, 0)
     | Link t'         -> demote_to_monomorphic t')
  | TCon   (_, args)    -> List.iter demote_to_monomorphic args
  | TArrow (a, b)       -> demote_to_monomorphic a; demote_to_monomorphic b
  | TTuple ts           -> List.iter demote_to_monomorphic ts
  | TRecord flds        -> List.iter (fun (_, t) -> demote_to_monomorphic t) flds
  | TLin   (_, t)       -> demote_to_monomorphic t
  | TNatOp (_, a, b)    -> demote_to_monomorphic a; demote_to_monomorphic b
  | TChan  _            -> ()
  | TRefine (base, _, _) -> demote_to_monomorphic base
  | TNat _ | TError     -> ()

(** Value restriction for Vault table handles — the phantom value parameter of
    [Vault(v)] (see [builtin_types]) is only worth anything if it cannot be
    re-instantiated at every use.

    A Vault table is a process-global mutable cell reached through a handle, so
    it is exactly ML's [ref []] case: [let t = Vault.new("t")] is an
    APPLICATION, not a syntactic value, and generalizing its [v] to [∀v.
    Vault(v)] would let [Vault.set(t, "k", 42)] instantiate [v := Int] and
    [Vault.get(t, "k")] instantiate [v := Pid(_)] independently — reproducing
    the erasure the phantom parameter exists to remove.  Demoting every var
    that occurs UNDER a [Vault] constructor to level 0 pins the handle's
    element type at its binding site, so the first write and every later read
    unify against one [v].

    Applied at the three generalization sites where a handle can be bound
    without the user saying what it holds: block [let] and top-level [let] with
    no annotation, and a [fn] with no return annotation.  Writing the
    annotation ([fn open(name) : Vault(v)]) is the deliberate opt-out and is
    what [Vault.new]/[Vault.open]/[Vault.whereis] and [Config]'s table getters
    use — a name-keyed global table genuinely mints handles at any element
    type, and that erasure is now explicit and greppable instead of ambient.

    Scoped to [Vault] on purpose: no type that does not mention [Vault]
    anywhere changes generalization behaviour by one variable. *)
let rec demote_vault_handle_vars (t : ty) : unit =
  match t with
  | TCon ("Vault", args) -> List.iter demote_to_monomorphic args
  | TVar r ->
    (match !r with
     | Link t'   -> demote_vault_handle_vars t'
     | Unbound _ -> ())
  | TCon   (_, args)    -> List.iter demote_vault_handle_vars args
  | TArrow (a, b)       -> demote_vault_handle_vars a; demote_vault_handle_vars b
  | TTuple ts           -> List.iter demote_vault_handle_vars ts
  | TRecord flds        -> List.iter (fun (_, t) -> demote_vault_handle_vars t) flds
  | TLin   (_, t)       -> demote_vault_handle_vars t
  | TNatOp (_, a, b)    -> demote_vault_handle_vars a; demote_vault_handle_vars b
  | TChan  _            -> ()
  | TRefine (base, _, _) -> demote_vault_handle_vars base
  | TNat _ | TError     -> ()

(** Tag the inner cap-argument var of a [cap_narrow] result [Cap(a)] so [unify]
    can reject the instant [a] is bound to a nominal proof cap — closing the
    forge even when the value is laundered through a polymorphic function.  Two
    shapes are tagged: [Cap(a)] (tag the inner var [a]) and a bare var [r] (the
    whole value type is a still-unknown var — as happens when a laundering fn's
    return decouples from its param; tag [r] itself).  If the type is already a
    concrete cap, tagging is a no-op.

    RECURSES into container shapes (tuples, records, and other [TCon] type
    arguments) so the tag reaches a cap-producer var wrapped by a factory
    function's return type — e.g. [(Cap(a), Int)] or [Option(Cap(a))] — not
    just a bare top-level [Cap(a)]/[TVar].  Mirrors
    [ty_has_tagged_cap_producer]'s traversal exactly: that detector already
    walks containers to decide WHETHER to propagate the taint into a call's
    result (see its call sites below); before this fix, the tagging half of
    that pairing silently no-opped on any container shape it found (`| _ -> ()`),
    so a container-wrapped cap-producer var reaching a truly fresh (never
    independently tagged) result var never got marked.  (In practice this was
    not independently exploitable on this tree — the ORIGINAL cap_narrow-tagged
    var is forced monomorphic by [demote_to_monomorphic] and so is never
    re-instantiated by generalization, and [unify]'s hook propagates the tag to
    any var it gets bound to, including through element-wise tuple/record
    unification — but the asymmetry left the detector/tagger pairing at the
    call-propagation sites below inert for container-shaped results, which is
    latent risk independent of that protection.) *)
let rec tag_cap_producer_result (env : env) (rty : ty) (sp : Ast.span) : unit =
  match repr rty with
  | TCon ("Cap", [inner]) ->
    (match repr inner with
     | TVar r ->
       (match !r with
        | Unbound (id, _) -> Hashtbl.replace env.cap_producer_ivars id sp
        | Link _ -> ())
     | _ -> ())
  | TVar r ->
    (match !r with
     | Unbound (id, _) -> Hashtbl.replace env.cap_producer_ivars id sp
     | Link _ -> ())
  | TCon (_, args)       -> List.iter (fun t -> tag_cap_producer_result env t sp) args
  | TArrow (a, b)        -> tag_cap_producer_result env a sp; tag_cap_producer_result env b sp
  | TTuple ts            -> List.iter (fun t -> tag_cap_producer_result env t sp) ts
  | TRecord flds         -> List.iter (fun (_, t) -> tag_cap_producer_result env t sp) flds
  | TLin (_, t)          -> tag_cap_producer_result env t sp
  | TNatOp (_, a, b)     -> tag_cap_producer_result env a sp; tag_cap_producer_result env b sp
  | TRefine (base, _, _) -> tag_cap_producer_result env base sp
  | TChan _ | TNat _ | TError -> ()

(** True if [ty] carries a [cap_narrow]-tagged cap-producer var anywhere — the
    inner var of a [Cap(a)] whose [a] is tagged, or a bare tagged var.  Used to
    propagate the forge taint through a call: an argument whose type is tainted
    laundered a cap_narrow result, so the call's result must be tainted too. *)
let ty_has_tagged_cap_producer (env : env) (ty : ty) : bool =
  let tagged r = match !r with
    | Unbound (id, _) -> Hashtbl.mem env.cap_producer_ivars id
    | Link _ -> false in
  let rec go t = match repr t with
    | TVar r             -> tagged r
    | TCon   (_, args)   -> List.exists go args
    | TArrow (a, b)      -> go a || go b
    | TTuple ts          -> List.exists go ts
    | TRecord flds       -> List.exists (fun (_, t) -> go t) flds
    | TLin   (_, t)      -> go t
    | TNatOp (_, a, b)   -> go a || go b
    | TRefine (base, _, _) -> go base
    | TChan _ | TNat _ | TError -> false
  in go ty

(** True when the compiler was invoked with [--test] (the test-runner build).

    Read by [check_cap_impl_sites]: an IO capability has no declaring module —
    IO caps are compiler-owned and rooted at [main]'s grant — so the
    declaring-module rule that gates a dictionary on a proof cap has nothing to
    bind to.  Supplying a mock implementation for one is admitted only in a
    test build.  This is a BUILD-MODE gate, not a type-level one, and it is
    weaker in kind than the declaring-module rule: `forge publish` must refuse
    an artifact built with [--test], or a library can ship its own mock. *)
let test_build = ref false

let lookup_var  name env = StrMap.find_opt name env.vars
let lookup_type name env = StrMap.find_opt name env.types

(** The last segment of a capability path: the name as WRITTEN in its
    declaration.  A `proof cap Live` inside `mod Session` has the path
    "Session.Live", so a hint spelled from the path suggests
    `proof cap Session.Live with ...`, which does not parse. *)
let cap_bare_name (cap_path : string) : string =
  match String.rindex_opt cap_path '.' with
  | None -> cap_path
  | Some i -> String.sub cap_path (i + 1) (String.length cap_path - i - 1)

(** [resolve_cap_dict_type env cap_path] — the record-type name, as registered
    in [env.records], of the runtime dictionary [cap_path] declares via
    `proof cap X with T`.  [None] when the capability declares no dictionary,
    or when the type it names is not a record in scope.

    Tries the bare spelling first and then the declaring module's
    qualification, because [DType] registers a record under both spellings
    depending on how deeply the module is nested (typecheck.ml:5900-5901). *)
let resolve_cap_dict_type env cap_path =
  match List.assoc_opt cap_path env.cap_dicts with
  | None -> None
  | Some d ->
    if StrMap.mem d env.records then Some d
    else
      match List.assoc_opt cap_path env.proof_caps with
      | Some m when m <> "" && StrMap.mem (m ^ "." ^ d) env.records ->
        Some (m ^ "." ^ d)
      | _ -> None

(** True iff the bare type name [name] resolves to an `always_linear` type *here*
    — i.e. it is registered always_linear AND the current module does NOT declare
    its OWN same-named type (which shadows the imported/stdlib one).  Bridges the
    L4 gap (a user `type Handle` was silently infected by stdlib's `always_linear
    Handle` because promotion matched the bare name globally) using the current
    module's declaration as the shadow signal — the same current-module
    preference [lookup_ctor_in_type]/the ctor system already use.  This is a
    stopgap: the principled fix is module-qualified type identity
    (specs/plans/2026-07-17-fqn-type-ctor-identity.md), which subsumes it. *)
let resolves_always_linear name env =
  (* If the current module declares its OWN same-named type, that declaration
     shadows any imported one, so promotion follows *its* linearity: promote iff
     the current module's own qualified type is always_linear (both bare and
     qualified names are registered by DAlwaysLinearType).  Otherwise there is no
     local shadow and the bare/imported linearity applies. *)
  if env.current_module <> ""
     && StrMap.mem (env.current_module ^ "." ^ name) env.types
  then List.mem (env.current_module ^ "." ^ name) env.always_linear_types
  else List.mem name env.always_linear_types

(** Resolve a bare constructor name to a candidate [ctor_info].  When several
    candidates share the bare name (e.g. two DIFFERENT modules each declaring
    their own `Shared`, kept distinct by [add_ctor] since Task 1 of the FQN
    dispatch-identity plan), prefer the candidate whose [ci_module] matches
    the reference's own LEXICAL current module — a bare `Shared` written
    inside `DcA`'s own code should mean `DcA`'s own `Shared`, not whichever
    candidate happens to be first in the internal list (order- and
    module-arrangement-dependent, and meaningless now that multiple genuinely
    different candidates can survive under one key). Falls back to the first
    candidate when the current module owns none of them (the caller is
    responsible for flagging that fallback as ambiguous when appropriate —
    see the `ECon`/`PatCon` cross-module hard-error check). *)
let lookup_ctor name env =
  match StrMap.find_opt name env.ctors with
  | None -> None
  | Some [] -> None
  | Some (first :: _ as cis) ->
    let is_canonical_monitor_key =
      match name with
      | "Down.Down"
      | "DownReason.Normal" | "DownReason.Killed" | "DownReason.Crash" -> true
      | _ -> false
    in
    if is_canonical_monitor_key then
      (* These exact type-qualified keys are the declaration-free runtime ABI.
         A nested user declaration contributes another candidate with the same
         short [ci_type], but its real public key is module-qualified
         ([Inner.Down], [DistLink.Crash], ...).  Never let registration order
         make the canonical spelling resolve to that user candidate. *)
      (match List.find_opt (fun ci -> ci.ci_module = "") cis with
       | Some _ as builtin -> builtin
       | None -> Some first)
    else
      (match List.find_opt (fun ci -> ci.ci_module = env.current_module) cis with
       | Some _ as preferred -> preferred
       | None -> Some first)

(** Same-module precedence for an UNQUALIFIED constructor reference.

    When two sibling modules in the same package define distinct types that
    share a constructor name (e.g. `IslandSocket.Registry(List(IslandHandler))`
    and `Islands.Registry(List(Descriptor))`), the bare-name entry in
    [env.ctors] holds BOTH candidates and [lookup_ctor] returns whichever was
    registered last — a single global winner shared by every module, regardless
    of which module's body is being checked.  Since March keys nominal types by
    bare name, both `Registry`s look identical at the type level; only the
    constructors' argument types differ, so the wrong candidate silently unifies
    the sibling's element type in (the observed "expected Descriptor but got
    IslandHandler").

    A module's own top-level definition must outrank a same-named one from a
    module it does not even import.  [prebind_mod_members] seeds a
    module-qualified key `Module.Ctor` (bare [ci_type]) for every module's
    public constructors, keyed by the ACCUMULATED, entry-unwrapped module path
    (e.g. a sibling `Islands` seeds `Islands.Registry`; a nested `mod Outer do
    mod Inner` under the unwrapped entry seeds `Inner.Registry`; a nested
    module under a non-entry `Outer` seeds `Outer.Inner.Registry`).  We look the
    bare name up under the current module's own such key first.

    The key must exactly match prebind's accumulated path.  [cap_qual_prefix]
    tracks precisely that path (accumulated across enclosing [DMod]s, empty at
    the TIR-unwrapped entry level — see its field doc).  At the unwrapped entry
    level [cap_qual_prefix] is "" while prebind still seeds under the entry
    module name, which [current_module] holds — so use [cap_qual_prefix] when
    set and fall back to [current_module] at the entry level.  This makes
    same-module precedence work for top-level siblings, dotted single-decl
    module names, AND arbitrarily nested modules.

    If the current module does not define [name] the key is absent and we fall
    through to the existing resolution — preserving imported names and
    d95fe942's order-independence for genuinely cross-module bare references,
    whose module path does not match the definer's.

    Ambiguity guard: the `Module.Ctor` key shares its STRING namespace with the
    `Type.Ctor` disambiguation form prebind also seeds (see the `bare_type_qctor`
    site).  When a module's leaf name coincides with a DIFFERENT package's TYPE
    name (real case: bastion `mod Gate` with an opaque `type Gate`, vs depot's
    `mod Depot.Gate` whose regular `type Gate` seeds the disambiguation key
    `Gate.Gate`), the `Gate.Gate` bucket holds BOTH ctors and the head is
    order-dependent — exactly the pollution same-module precedence is meant to
    avoid.  So only trust this key when it resolves UNAMBIGUOUSLY to one ctor;
    otherwise return None and let the caller fall through.  For an opaque type
    the module's own bare-`Ctor` key wins the head during its Pass-2 check (its
    private ctor is never prebind-seeded into the bare key, so nothing displaces
    it), making the bare fallback correct there. *)
let lookup_ctor_same_module name env =
  let self = if env.cap_qual_prefix <> "" then env.cap_qual_prefix
             else env.current_module in
  if self = "" || String.contains name '.' then None
  else match StrMap.find_opt (self ^ "." ^ name) env.ctors with
    | Some [ci] -> Some ci
    | _ -> None

(** Find the constructor [name] that belongs to [type_name] among the candidates
    registered under that bare name.  A bare constructor name can be shared by
    several ADTs (e.g. `Text` in both `Inline` and `XmlNode`); when more than
    one candidate matches [type_name] (the same-short-name cross-module
    collision case), prefer the one whose [ci_module] matches the reference's
    own lexical current module, same as [lookup_ctor] above. When the
    expected/scrutinee type is known, this lets us pick the candidate that
    actually matches it. *)
let lookup_ctor_in_type name type_name env =
  match StrMap.find_opt name env.ctors with
  | None -> None
  | Some cis ->
    let matching = List.filter (fun (ci : ctor_info) -> ci.ci_type = type_name) cis in
    (match List.find_opt (fun ci -> ci.ci_module = env.current_module) matching with
     | Some _ as preferred -> preferred
     | None -> (match matching with [] -> None | first :: _ -> Some first))

(** Like [lookup_ctor_in_type] but returns a candidate ONLY when it is the sole
    one whose parent type matches [type_name].  When two DISTINCT types in the
    same package share a constructor name (e.g. `IslandSocket.Registry` and
    `Islands.Registry`, both with bare [ci_type] "Registry"), an expected type
    of `Registry` matches BOTH candidates — [lookup_ctor_in_type] would return
    the order-dependent head, silently defeating same-module precedence.  This
    variant reports no match in that ambiguous case so the caller falls through
    to same-module resolution, while a KNOWN scrutinee type whose name is unique
    among the candidates (the Finding-1 case: local `Local = Reg(Int)` vs
    imported `Remote = Reg(String)`) still wins outright. *)
let lookup_ctor_in_type_unique name type_name env =
  match StrMap.find_opt name env.ctors with
  | Some cis ->
    (match List.filter (fun (ci : ctor_info) -> ci.ci_type = type_name) cis with
     | [ci] -> Some ci
     | _ -> None)
  | None -> None

(** Add [ci] under [key] in [ctors], keeping all infos for the same name.
    Deduplicates STRUCTURALLY (same ci_type, ci_module, ci_params, and
    ci_arg_tys) — but by MOVING the existing entry to the FRONT rather than
    no-op'ing.  Two types with the same short name but different arity (e.g.
    stdlib's `Tree(a)` and a user's `Tree`) are kept as distinct candidates.
    So are two DIFFERENT modules' identically-shaped ctors (e.g. both a
    nullary `Shared` on a type named `Thing`) — [ci_module] is part of the
    comparison (FQN dispatch-identity plan, Task 1) precisely so this case
    is no longer treated as "the same ctor" and does not collapse the
    second registration onto the first.

    Why move-to-front matters (sibling-ctor shadowing regression,
    2026-07-10): Pass-1 prebind seeds every nested module's bare ctor keys
    for order-independent cross-module resolution (d95fe942), in module
    declaration order — so a later sibling `mod B`'s `Mk` sits AHEAD of
    `mod A`'s same-named `Mk`.  Pass-2 then re-registers each module's own
    ctors (check_decl DType) right before checking that module's bodies —
    but the re-registration is structurally identical to the Pass-1 seed
    (SAME ci_module both times, since a module always re-registers its OWN
    ctors), so a no-op dedup left B's candidate at the head and A's OWN body
    resolved `Mk(1)` against B's `Mk(String)` ("expected String but got
    Int" pointing inside A).  Moving the re-registered entry to the front
    restores the declaring module's recency for its own body check (the
    pre-d95fe942 semantics) while keeping the Pass-1 seeds — and therefore
    the cross-module order-independence — intact.  A singleton list is
    unaffected; only genuinely shared names reorder.  Adding [ci_module] to
    the comparison does not disturb this: same-module re-registration always
    has matching [ci_module] on both sides, so it is unaffected; only
    cross-module identically-shaped ctors (previously wrongly deduped) now
    stay distinct. *)
let add_ctor (key : string) (ci : ctor_info) (ctors : ctor_info list StrMap.t) =
  let lst = Option.value ~default:[] (StrMap.find_opt key ctors) in
  let same c =
    c.ci_type = ci.ci_type
    && c.ci_module = ci.ci_module
    && c.ci_params = ci.ci_params
    && c.ci_arg_tys = ci.ci_arg_tys
  in
  if List.exists same lst then
    (match lst with
     | first :: _ when same first -> ctors   (* already at the front *)
     | _ -> StrMap.add key (ci :: List.filter (fun c -> not (same c)) lst) ctors)
  else StrMap.add key (ci :: lst) ctors

(* ── Qualified module resolution ─────────────────────────────────────
   When a qualified name like "Map.get" isn't in the local env, we load
   the module via the registry and inject its exports into env on demand. *)

(** Simple edit distance for "did you mean" suggestions. *)
let edit_distance (a : string) (b : string) : int =
  let m = String.length a and n = String.length b in
  if m = 0 then n
  else if n = 0 then m
  else begin
    let d = Array.make_matrix (m + 1) (n + 1) 0 in
    for i = 0 to m do d.(i).(0) <- i done;
    for j = 0 to n do d.(0).(j) <- j done;
    for i = 1 to m do
      for j = 1 to n do
        let cost = if a.[i-1] = b.[j-1] then 0 else 1 in
        d.(i).(j) <- min (min (d.(i-1).(j) + 1) (d.(i).(j-1) + 1))
                         (d.(i-1).(j-1) + cost)
      done
    done;
    d.(m).(n)
  end

(** Split a qualified name "Mod.member" into (module, member).
    Returns None if the name contains no dot.

    Splits at the LAST dot, not the first: [member] is always a single
    trailing identifier (a function/type/ctor name, never itself dotted), so
    everything before it is the module path — correct for both flat stdlib
    names ("List.map") and dotted ones ("Js.Canvas.draw_node", where the
    module is "Js.Canvas" and rindex is needed to avoid mis-splitting into
    module "Js" + member "Canvas.draw_node", which no stdlib file can ever
    satisfy). App-local multi-component paths like "Conduit.Storage.foo"
    (interface methods registered under a shorter suffix) are unaffected:
    [Module_registry.ensure_loaded] on "Conduit.Storage" misses exactly as
    it did on "Conduit" before, since neither is a real stdlib module, so
    every caller's existing miss-and-fall-through behavior is unchanged —
    this only adds resolution for module paths that genuinely exist. *)
let split_qualified (name : string) : (string * string) option =
  match String.rindex_opt name '.' with
  | None -> None
  | Some i ->
    Some (String.sub name 0 i, String.sub name (i + 1) (String.length name - i - 1))

(** Suggest a module name similar to [name] from stdlib files on disk. *)
let suggest_module_name (name : string) : string option =
  match March_modules.Module_registry.find_stdlib_dir () with
  | None -> None
  | Some dir ->
    let best = ref None in
    let best_dist = ref max_int in
    (try
       let entries = Sys.readdir dir in
       (* Sort so equal-distance ties break deterministically. *)
       Array.sort compare entries;
       Array.iter (fun entry ->
         if Filename.check_suffix entry ".march" then begin
           let base = Filename.chop_suffix entry ".march" in
           let parts = String.split_on_char '_' base in
           let mod_name = String.concat "" (List.map String.capitalize_ascii parts) in
           let d = edit_distance (String.lowercase_ascii name) (String.lowercase_ascii mod_name) in
           if d > 0 && d < !best_dist && d <= 2 then begin
             best := Some mod_name;
             best_dist := d
           end
         end
       ) entries
     with _ -> ());
    !best

(** Forward ref filled after [surface_ty] and [generalize] are defined.
    Injects interface method bindings for cross-module [ExInterface] exports. *)
let inject_iface_exports_ref
  : (string -> March_modules.Module_registry.module_exports -> env -> env) ref =
  ref (fun _mod_name _exports env -> env)

(** Load a module's exports into an env, returning the updated env.
    Injects "Mod.name" bindings for functions/values, types, and constructors.
    Interface method bindings are handled separately via inject_iface_exports_ref. *)
let load_module_into_env (mod_name : string) (exports : March_modules.Module_registry.module_exports) (env : env) : env =
  List.fold_left (fun env entry ->
    let open March_modules.Module_registry in
    let qname = mod_name ^ "." ^ entry.ex_name in
    match entry.ex_kind with
    | ExFn | ExValue ->
      (* Visibility gate (mirrors the [ExCtor] arm below): a private [pfn] /
         private [let] is NOT importable across modules. Skipping the binding
         here (rather than adding it) lets the later [lookup_var] miss fall
         through to [qualified_error_msg], which detects [not e.ex_public] and
         reports "<name> is private to module `<mod>`." — the same message the
         [ExCtor] path already produces for private constructors.
         [ExType]/[ExRecord] stay UNGATED on purpose: March uses the opaque-type
         pattern, where a private [ptype]'s bare NAME stays referenceable across
         modules (e.g. `ConsistentHash.HashRing(String)` on a param) while
         only its CONSTRUCTOR is hidden — enforced by the [ExCtor] gate below.
         [ExFn] additionally seeds [qual_fn_names] so the [EVar] reference-
         recording hook can tell a genuine function export (`ExFn`) apart
         from a plain value/constant export (`ExValue`) — see
         [qual_fn_names]'s doc comment. *)
      if not entry.ex_public then env
      else if StrMap.mem qname env.vars then env
      else
        let env = { env with vars = StrMap.add qname (Mono (fresh_var 0)) env.vars } in
        (match entry.ex_kind with
         | ExFn -> { env with qual_fn_names = StrMap.add qname () env.qual_fn_names }
         | _ -> env)
    | ExType arity ->
      (* Register the qualified name AND the BARE type name.  March uses a single
         global type namespace (see [surface_ty]'s [canon_name]): a type's bare
         name is its canonical identity, and a sibling module resolves a peer
         type UNQUALIFIED (`scope : UniqueScope`, no `use`/`import`).  When the
         defining module is PREBOUND FROM SOURCE, [prebind_mod_members] (:8931)
         seeds the bare name; when it is loaded from the compiled Module_registry
         instead (e.g. a dependency in the `--compile`/`--test` unit), only the
         qualified key was seeded — so expanding a registry-loaded RECORD whose
         field references a bare sibling type failed with a bogus "I cannot find
         `UniqueScope`" pointing at the definer's field span.  Seed the bare name
         too, first-wins (don't clobber a name a source module already bound),
         mirroring the source-prebind path. *)
      let env = if StrMap.mem qname env.types then env
                else { env with types = StrMap.add qname arity env.types } in
      if StrMap.mem entry.ex_name env.types then env
      else { env with types = StrMap.add entry.ex_name arity env.types }
    | ExRecord (arity, field_decls) ->
      let param_names = List.init arity (fun i -> Printf.sprintf "$t%d" i) in
      let env1 = if StrMap.mem qname env.types then env
                 else { env with types = StrMap.add qname arity env.types } in
      (* Bare type name too — see the [ExType] arm's rationale. *)
      let env1 = if StrMap.mem entry.ex_name env1.types then env1
                 else { env1 with types = StrMap.add entry.ex_name arity env1.types } in
      (* Register the record's fields under BOTH the qualified and bare keys so a
         bare cross-module reference (or a peer module's bare field type) expands
         structurally instead of staying an opaque TCon. *)
      let env1 = { env1 with records = StrMap.add qname (param_names, field_decls) env1.records } in
      if StrMap.mem entry.ex_name env1.records then env1
      else { env1 with records = StrMap.add entry.ex_name (param_names, field_decls) env1.records }
    | ExCtor (parent_type, _ctor_arity) ->
      begin
        (* Find the parent type's param names from the module's type exports *)
        let type_arity = List.fold_left (fun acc e ->
          match e.ex_kind with ExType a when e.ex_name = parent_type -> a | _ -> acc
        ) 0 exports.me_entries in
        let param_names = List.init type_arity (fun i ->
          Printf.sprintf "$t%d" i) in
        let arg_tys = List.init _ctor_arity (fun i ->
          Ast.TyVar { txt = Printf.sprintf "$a%d" i; span = Ast.dummy_span }) in
        let ci = {
          ci_type = mod_name ^ "." ^ parent_type;
          ci_params = param_names;
          ci_arg_tys = arg_tys;
          ci_module = mod_name;
          ci_vis = if entry.ex_public then Ast.Public else Ast.Private;
          (* Only a name + arity crosses the export bridge, not the original
             ctor_info record — this is the one place ci_is_actor_msg can't be
             read off a known fact, so it's derived the same way
             Tir_names.is_actor_msg_name does post-lowering (see that
             function's doc comment for why the "_Msg"-suffix collision risk
             is accepted there); see this field's own doc comment above. *)
          ci_is_actor_msg =
            (let sfx = "_Msg" in
             let nl = String.length parent_type and sl = String.length sfx in
             nl > sl && String.sub parent_type (nl - sl) sl = sfx);
        } in
        { env with ctors = add_ctor qname ci env.ctors }
      end
    | ExInterface _ -> env  (* handled by inject_iface_exports_ref after surface_ty is available *)
  ) env exports.me_entries

(** Try to resolve a qualified variable by loading its module.
    Returns (updated_env, scheme option). *)
let resolve_qualified_var (name : string) (env : env) : env * scheme option =
  match split_qualified name with
  | None -> env, None
  | Some (mod_name, _member) ->
    match March_modules.Module_registry.ensure_loaded mod_name with
    | None -> env, None
    | Some exports ->
      let env' = load_module_into_env mod_name exports env in
      env', lookup_var name env'

(** Try to resolve a qualified type by loading its module.
    Returns (updated_env, arity option). *)
let resolve_qualified_type (name : string) (env : env) : env * int option =
  match split_qualified name with
  | None -> env, None
  | Some (mod_name, _member) ->
    match March_modules.Module_registry.ensure_loaded mod_name with
    | None -> env, None
    | Some exports ->
      let env' = load_module_into_env mod_name exports env in
      env', lookup_type name env'

(** Try to resolve a qualified constructor by loading its module.
    Returns (updated_env, ctor_info option). *)
let resolve_qualified_ctor (name : string) (env : env) : env * ctor_info option =
  match split_qualified name with
  | None -> env, None
  | Some (mod_name, _member) ->
    match March_modules.Module_registry.ensure_loaded mod_name with
    | None -> env, None
    | Some exports ->
      let env' = load_module_into_env mod_name exports env in
      env', lookup_ctor name env'

(** Suggest a variable name close to [name] from [env.vars].
    Returns the closest match with edit distance ≤ 2 that isn't a qualified name. *)
let suggest_var_in_scope (name : string) (env : env) : string option =
  let name_lo   = String.lowercase_ascii name in
  let max_dist  = if String.length name <= 3 then 1 else 2 in
  let best      = ref None in
  let best_dist = ref max_int in
  StrMap.iter (fun k _ ->
    (* Skip qualified names (Mod.member) — those are suggested elsewhere. *)
    if not (String.contains k '.') then begin
      let d = edit_distance name_lo (String.lowercase_ascii k) in
      if d > 0 && d <= max_dist && d < !best_dist then begin
        best      := Some k;
        best_dist := d
      end
    end
  ) env.vars;
  !best

(** True if [name] is a dotted qualified reference (`Mod.member`) whose
    `member` is CONFIRMED private — either an in-file nested module's `pfn` /
    private `let` (via [env.local_mods]) or a private export of a module
    reachable through the registry.  Used to stop [EVar]'s progressive
    dot-suffix fallback (see its use site) from silently resolving a privacy
    violation to an unrelated same-named global (e.g. a bare interface
    method or builtin) instead of reporting the violation. *)
let is_confirmed_private_qualified (name : string) (env : env) : bool =
  match split_qualified name with
  | None -> false
  | Some (mod_name, member) ->
    (match StrMap.find_opt mod_name env.local_mods with
     | Some priv when List.mem member priv -> true
     | _ ->
       match March_modules.Module_registry.ensure_loaded mod_name with
       | None -> false
       | Some exports ->
         let open March_modules.Module_registry in
         List.exists (fun e -> e.ex_name = member && not e.ex_public) exports.me_entries)

(** Produce an error message for a qualified name that failed to resolve. *)
let qualified_error_msg (name : string) (env : env) : string =
  match split_qualified name with
  | None -> Printf.sprintf "I cannot find `%s`." name
  | Some (mod_name, member)
    when (match StrMap.find_opt mod_name env.local_mods with
          | Some priv -> List.mem member priv
          | None -> false) ->
    (* An in-file nested module `mod_name` declares `member` privately (`pfn` /
       private `let`).  Private members are never exported into [env.vars], so
       the registry lookup below would misreport "Unknown module" for a module
       that plainly exists in this file.  Report the real cause instead. *)
    Printf.sprintf "Function `%s` is private to module `%s`." member mod_name
  | Some (mod_name, member) ->
    match March_modules.Module_registry.ensure_loaded mod_name with
    | None ->
      let hint = match suggest_module_name mod_name with
        | Some s -> Printf.sprintf " Did you mean `%s`?" s
        | None -> ""
      in
      Printf.sprintf "Unknown module `%s`.%s" mod_name hint
    | Some exports ->
      (* Module exists but member not found — check private *)
      let open March_modules.Module_registry in
      let priv = List.find_opt (fun e -> e.ex_name = member && not e.ex_public) exports.me_entries in
      match priv with
      | Some _ ->
        Printf.sprintf "Function `%s` is private to module `%s`." member mod_name
      | None ->
        let public_names = List.filter_map (fun e ->
          if e.ex_public then Some e.ex_name else None
        ) exports.me_entries in
        let suggestions = List.filter (fun n ->
          edit_distance (String.lowercase_ascii member) (String.lowercase_ascii n) <= 2
        ) public_names in
        let hint = match suggestions with
          | [] -> ""
          | ss -> " Did you mean " ^ String.concat " or " (List.map (fun s -> Printf.sprintf "`%s.%s`" mod_name s) ss) ^ "?"
        in
        Printf.sprintf "Module `%s` does not export `%s`.%s" mod_name member hint

(** All parent types of ctors in [env] that share [name] (multiple types may
    define the same variant). Returns list of type names (deduplicated).
    O(log n) — just a single map lookup on the ctor_info list. *)
let all_ctors_named (name : string) (env : env) : string list =
  match StrMap.find_opt name env.ctors with
  | None -> []
  | Some cis ->
    let seen = Hashtbl.create 4 in
    List.filter_map (fun ci ->
      if Hashtbl.mem seen ci.ci_type then None
      else begin Hashtbl.add seen ci.ci_type (); Some ci.ci_type end
    ) cis

(** Like [all_ctors_named], but returns (type_name, declaring_module) pairs
    without deduping by type_name alone — so two DIFFERENT modules' same-
    short-name colliding types (which share [ci_type]) are counted as
    distinct candidates. Used only by the genuinely-ambiguous-reference
    hard-error check below; [all_ctors_named]'s existing bare-type-name
    callers are untouched. *)
let all_ctor_candidates_named (name : string) (env : env) : (string * string) list =
  match StrMap.find_opt name env.ctors with
  | None -> []
  | Some cis ->
    let seen = Hashtbl.create 4 in
    List.filter_map (fun ci ->
        let key = (ci.ci_type, ci.ci_module) in
        if Hashtbl.mem seen key then None
        else begin Hashtbl.add seen key (); Some key end
      ) cis

(** Suggest constructors close to [name]: case-insensitive match or first-2-char
    prefix match with length difference ≤ 2. Returns [(ctor_name, type_name)]. *)
let suggest_ctors (name : string) (env : env) : (string * string) list =
  let name_lo = String.lowercase_ascii name in
  let seen = Hashtbl.create 8 in
  StrMap.fold (fun k cis acc ->
    let k_lo = String.lowercase_ascii k in
    let close =
      k_lo = name_lo ||
      (String.length name_lo >= 2 && String.length k_lo >= 2 &&
       String.sub k_lo 0 2 = String.sub name_lo 0 2 &&
       abs (String.length k - String.length name) <= 2)
    in
    if not close then acc
    else
      List.fold_left (fun acc ci ->
        let key = k ^ "/" ^ ci.ci_type in
        if Hashtbl.mem seen key then acc
        else begin Hashtbl.add seen key (); (k, ci.ci_type) :: acc end
      ) acc cis
  ) env.ctors []

(* Binding a value name SHADOWS any same-named module fn for the direct-call
   arity check ([fn_arities], consulted at the EApp rule): a param/let/pattern
   binding named e.g. `f` must not have calls `f(x, y)` checked against a
   TOP-LEVEL `fn f`'s declared arity.  [fn_arities] is name-keyed and
   accumulates across modules, so without this removal a stdlib param like
   fold_left's `f : b -> a -> b` collides with ANY user/other-module `fn f`
   of a different arity — the false arity error is reported at the STDLIB
   span (silently filtered by bin/main.ml's is_user_file), the call is
   "recovered" as a PARTIAL application (peel), the enclosing fn's recursive
   call then hits an occurs failure (acc := elem -> acc), the type var is
   linked to TError, and the poisoned type_map lowers fold_left with a
   function-typed accumulator temp — the runaway "Monomorphization limit
   reached: List.fold_left > 512 specializations" ICE, plus TError-typed
   ('_err) stdlib values misclassified by codegen.  The env is functional,
   so the removal scopes exactly like the shadowing binding itself.  The few
   TOP-LEVEL fn (re)binding sites re-add the entry immediately after
   (module prebinds, check_decl's DFn rebind, check_fn's self-bind).
   Regression note: this fix (commit c6599af9) was lost in the PR #27/#38
   merge-conflict resolution and restored here. *)
(* [offer_labels] shadowing discipline (F5 residual, 2026-07-24 review fix):
   [offer_labels] links a NAME (e.g. `lbl` in `let (lbl, ch) = Chan.offer(...)`)
   to a session ref, keyed on the string alone — the same name-keying hazard
   [fn_arities] above is already guarded against.  `bind_var`/`bind_linear` are
   the two chokepoints EVERY binding construct funnels through (plain `let`,
   lambda/`fn` params, `match` pattern bindings all eventually call one of
   these) so rebinding a name here retires any stale [offer_labels] entry for
   it — otherwise `let lbl = :ok` after `let (lbl, ch) = Chan.offer(...)`
   would leave the OLD entry reachable by `List.assoc_opt "lbl"`, and
   `with_offer_refinement` would refine (and un-mark) an unrelated channel
   based on a label the peer never actually returned: the exact `Chan.offer`
   soundness hole this file's [offer_unrefined] field exists to close, just
   reached through a shadowed name instead of a bare missing `match`. *)
(* [local_fns] shadowing discipline (mirrors the [fn_arities]/[plain_let_names]
   removals above): [local_fns] marks a name as "genuinely the current
   module's own top-level fn" and the [EVar] Call-ref-recording hook
   (`forge search --callers`) trusts that membership check alone to decide
   whether a bare-name use is a real call to that top-level fn. Without
   retiring the entry here, a parameter or local `let` that shadows a
   top-level fn name (e.g. `fn wrapper(helper) do helper() end` when `helper`
   is also a top-level fn) would have its LOCAL variable's use misrecorded as
   a call to the shadowed top-level fn — a textual name match masquerading as
   a resolution-based one. *)
let bind_var name sch env =
  { env with vars = StrMap.add name sch env.vars;
             fn_arities = StrMap.remove name env.fn_arities;
             plain_let_names = StringSet.remove name env.plain_let_names;
             local_fns = StrMap.remove name env.local_fns;
             offer_labels = List.filter (fun (n, _) -> n <> name) env.offer_labels }

let bind_vars bindings env =
  List.fold_left (fun e (n, s) -> bind_var n s e) env bindings

(** Extend env with a new linear/affine variable. *)
let bind_linear name lin ty env =
  let le = { le_name = name; le_lin = lin; le_used = ref false; le_first_use = ref None } in
  { env with
    vars = StrMap.add name (Mono ty) env.vars;
    fn_arities = StrMap.remove name env.fn_arities;
    plain_let_names = StringSet.remove name env.plain_let_names;
    lin  = le :: env.lin;
    offer_labels = List.filter (fun (n, _) -> n <> name) env.offer_labels }

(* =================================================================
   §8  Generalization and instantiation
   ================================================================= *)

(** [generalize level ty] quantifies all [Unbound] vars at a level
    strictly greater than [level].  Called after leaving a let-binding
    level to achieve let-polymorphism.

    The returned [Poly] scheme uses freshly-allocated [TVar] refs for
    each quantified variable.  This breaks aliasing between the scheme
    and any mutable [TVar] refs still held by other parts of the program
    (e.g. forward-reference placeholders shared with mutually-recursive
    functions processed later in pass 2).  Without the copy, a later
    function body can unify the original TVar — silently corrupting an
    already-stored Poly scheme and causing the second call site to see a
    monomorphized type instead of a fresh instantiation. *)
let generalize level ty =
  let ids = ref [] in
  let rec collect t = match repr t with
    | TVar r ->
      (match !r with
       | Unbound (id, l) when l > level ->
         if not (List.mem id !ids) then ids := id :: !ids
       | _ -> ())
    | TCon   (_, args)   -> List.iter collect args
    | TArrow (a, b)      -> collect a; collect b
    | TTuple ts          -> List.iter collect ts
    | TRecord flds       -> List.iter (fun (_, t) -> collect t) flds
    | TLin   (_, t)      -> collect t
    | TNatOp (_, a, b)   -> collect a; collect b
    | TChan  _           -> ()   (* session_ty has no polymorphic variables *)
    | TRefine (base, _, _) -> collect base  (* unreachable: repr strips it *)
    | TNat _ | TError    -> ()
  in
  collect ty;
  if !ids = [] then Mono ty
  else begin
    (* Allocate fresh, isolated TVar refs for each quantified id.
       Level 0 is used so these sentinel refs are never themselves
       generalized or lowered by occurs-check level adjustments. *)
    let refresh = List.map (fun id -> (id, ref (Unbound (id, 0)))) !ids in
    let rec copy t =
      (* Preserve a refinement wrapper through generalization so the predicate
         survives into the scheme; only the base is copied. *)
      match t with
      | TRefine (base, b, p) -> TRefine (copy base, b, p)
      | _ ->
      match repr t with
      | TVar r ->
        (match !r with
         | Unbound (id, _) ->
           (match List.assoc_opt id refresh with
            | Some new_r -> TVar new_r
            | None -> t)
         | Link _ -> assert false)  (* repr always resolves links *)
      | TCon   (n, args)   -> TCon   (n, List.map copy args)
      | TArrow (a, b)      -> TArrow (copy a, copy b)
      | TTuple ts          -> TTuple (List.map copy ts)
      | TRecord flds       -> TRecord (List.map (fun (n, t) -> (n, copy t)) flds)
      | TLin   (l, t)      -> TLin   (l, copy t)
      | TNatOp (op, a, b)  -> TNatOp (op, copy a, copy b)
      | TChan  _           -> t   (* session_ty has no polymorphic variables *)
      | TRefine (base, _, _) -> copy base  (* unreachable: a behind-a-link refinement, repr-stripped *)
      | TNat _ | TError    -> t
    in
    Poly (!ids, [], copy ty)
  end

(** [instantiate level env sch] replaces each quantified variable in [sch]
    with a fresh unification variable at [level].  Any class constraints
    carried by [sch] are instantiated and appended to [env.pending_constraints]
    so they can be discharged at the enclosing declaration boundary. *)
let instantiate ?use_span level env = function
  | Mono ty -> ty
  | Poly (ids, cs, ty) ->
    let subst = List.map (fun id -> (id, fresh_var level)) ids in
    (* Proof-cap forge taint survives generalization: if a quantified var was a
       [cap_narrow]-tagged cap-producer var (e.g. an un-annotated helper
       `fn mk(cap) do cap_narrow(cap) end` whose return got generalized), tag its
       fresh instantiation too, so the unify hook still fires when the laundered
       result is bound to a proof cap at THIS call site. *)
    List.iter (fun (id, fresh) ->
        if Hashtbl.mem env.cap_producer_ivars id then
          let cn_sp = Hashtbl.find env.cap_producer_ivars id in
          (match fresh with
           | TVar r -> (match !r with Unbound (nid, _) -> Hashtbl.replace env.cap_producer_ivars nid cn_sp | Link _ -> ())
           | _ -> ())) subst;
    let rec inst t =
      (* Preserve a refinement wrapper through instantiation so call sites see
         the predicate on the parameter type; only the base is instantiated. *)
      match t with
      | TRefine (base, b, p) -> TRefine (inst base, b, p)
      | _ ->
      match repr t with
      | TVar r ->
        (match !r with
         | Unbound (id, _) ->
           (match List.assoc_opt id subst with
            | Some t' -> t'
            | None    -> t)
         | Link _ -> assert false  (* repr always follows links; this is unreachable *))
      | TCon   (n, args)   -> TCon   (n, List.map inst args)
      | TArrow (a, b)      -> TArrow (inst a, inst b)
      | TTuple ts          -> TTuple (List.map inst ts)
      | TRecord flds       -> TRecord (List.map (fun (n, t) -> (n, inst t)) flds)
      | TLin   (l, t)      -> TLin   (l, inst t)
      | TNatOp (op, a, b)  -> TNatOp (op, inst a, inst b)
      | TChan  _           -> t   (* session_ty has no polymorphic variables *)
      | TRefine (base, _, _) -> inst base  (* unreachable: a behind-a-link refinement, repr-stripped *)
      | TNat _ | TError    -> t
    in
    let inst_cs = List.map (function
        | CNum t -> CNum (inst t)
        | COrd t -> COrd (inst t)
        | CInterface (n, t) -> CInterface (n, inst t)
        | CADTBound (n, t) -> CADTBound (n, inst t)
        | CTNatBound t -> CTNatBound (inst t)) cs
    in
    env.pending_constraints := inst_cs @ !(env.pending_constraints);
    (* A1 witnesses: record the scheme (deduped by ids) and, if this call
       site supplied a span, the instantiation's type-argument vector. The
       fresh vars in `subst` are ordinary unification vars; they resolve
       through repr after the module solves, so store them as-is and let the
       emitter deep-repr them at serialization time. *)
    Hashtbl.replace env.scheme_witnesses ids (cs, ty);
    (match use_span with
     | Some sp -> Hashtbl.replace env.inst_witnesses sp (ids, List.map snd subst)
     | None -> ());
    inst ty
