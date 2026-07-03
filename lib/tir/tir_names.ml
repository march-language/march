(** Tir_names — single home for cross-pass name contracts.

    The TIR pipeline (lower → mono → defun → known_call → join_points →
    borrow → perceus → llvm_emit / js_emit) agrees on a set of synthetic
    names and predicates BY CONVENTION: a producer pass mints a string and
    one or more consumer passes recognise it later, often by re-deriving
    the same substring/prefix/suffix test independently. Historically this
    drifted (see specs/analysis/2026-07-01-pipeline-deep-review.md §1 root
    cause 2, §7.1): [is_apply_fn] existed as two independently-typed copies
    (perceus.ml, llvm_emit.ml), the interface-mangle `$`-before-last-`.`
    predicate was duplicated the moment it was introduced (Wave 2 Task 1),
    and the `march_` runtime-prefix check had THREE aligned call sites plus
    one that briefly went stale (B9, a 6-vs-7-char off-by-one, fixed
    2026-07-01).

    This module is the ONE place each such contract is defined. Every
    producer and consumer listed below should call into here rather than
    re-literal the string or re-derive the predicate. This is a pure
    behavior-preserving move (Wave 3 Task 1): every function here was
    verified byte-identical against the code it replaces before conversion
    — see specs/plans/2026-07-03-wave3-chunk1-refactors.md Task 1 and
    .superpowers/sdd/w3-task-1-report.md for the inventory and diff verdicts.

    Naming convention across the whole scheme: every synthesized name here
    uses ['$'], which is unlexable in March surface syntax (the lexer has no
    '$' token), so no user identifier can ever collide with a synthetic one
    — see the synthetic-name catalogue in the deep-review doc §6. The sole
    exception is the double-underscore family ([__try_call], [__try_call_val],
    [__march_test_N__], [__march_setup__], [__march_setup_all__]), which ARE
    lexable and (per the deep-review doc) capturable in principle; that risk
    is out of scope for this pure-move chunk. *)

(* ── Tuples: "$TupleN" ──────────────────────────────────────────────────
   Producer: lib/tir/lower.ml's [pat_tag_and_subs] (PatTuple arm) mints the
   branch tag for a tuple pattern as ["$Tuple" ^ string_of_int arity].
   Consumer: lib/tir/js_emit.ml's tuple-case detector treats any branch tag
   with this 6-char prefix as a tuple case (type info may be erased after
   Mono, so the branch tag is the only signal left). llvm_emit.ml does NOT
   string-match this prefix anywhere — tuple ECase branches are identified
   there by the scrutinee's static [TTuple] type instead (see [pat_tag_and_subs]'s
   own doc comment cross-referencing llvm_emit's [emit_case] decoder), so
   there is no llvm_emit consumer to convert for this one. *)

(** Branch tag for an N-element tuple pattern, e.g. [tuple_tag 2 = "$Tuple2"]. *)
let tuple_tag (arity : int) : string = Printf.sprintf "$Tuple%d" arity

(** True if [tag] is a tuple branch tag ("$TupleN"). Mirrors js_emit.ml's
    inline check (`String.length t >= 6 && String.sub t 0 6 = "$Tuple"`);
    matches the 6-char prefix only, tolerant of any arity suffix. *)
let is_tuple_tag (tag : string) : bool =
  String.length tag >= 6 && String.sub tag 0 6 = "$Tuple"

(* ── "$fvN"-named fields ─────────────────────────────────────────────────
   Two independent producers share this exact string format (same decoder
   downstream treats both uniformly, so one name/predicate pair covers
   both):
     - lib/tir/defun.ml mints closure struct fields named ["$fv" ^
       string_of_int i] (1-based: field 0 is the fn pointer, fv1.. are the
       captured free variables) when lifting a lambda.
     - lib/tir/lower.ml mints the SAME format (0-based this time: $fv0,
       $fv1, ...) for tuple-destructure `let (a, b) = rhs` field access.
   Consumers (all previously independent, byte-identical, 3-char-prefix
   checks): lib/tir/llvm_emit.ml's [ELet]-peephole for closure FV loads
   (`has_fv_field`) and its [EField] evaluator arm; lib/tir/js_emit.ml's
   [EField] emitter (translates "$fvN" to the JS closure struct's "_N").
   These consumers don't distinguish the two producers — both decode "$fvN"
   the same way (load struct field N) — so the shared name here just takes
   an int index whose 0-vs-1-basing is entirely up to the caller. *)

(** Field name for "$fv" ^ [i], e.g. [fv_field 1 = "$fv1"]. Whether [i] is
    0- or 1-based is a producer-side convention (defun.ml's closure fields
    are 1-based; lower.ml's tuple-destructure fields are 0-based) — this
    helper just formats whatever index it's given. *)
let fv_field (i : int) : string = Printf.sprintf "$fv%d" i

(** True if [name] is a closure free-variable field ("$fvN"). Mirrors the
    three previously-independent inline checks
    (`String.length n > 3 && String.sub n 0 3 = "$fv"`). *)
let is_fv_field (name : string) : bool =
  String.length name > 3 && String.sub name 0 3 = "$fv"

(** Parse the index out of a closure free-variable field name, e.g.
    [fv_field_index "$fv3" = 3]. Only valid when [is_fv_field name]; mirrors
    the parse done inline at both the llvm_emit.ml and js_emit.ml consumer
    sites (`int_of_string (String.sub name 3 ...)`). *)
let fv_field_index (name : string) : int =
  int_of_string (String.sub name 3 (String.length name - 3))

(* ── Closure struct type names: "$Clo_<fn>$<uid>" ───────────────────────
   Producer: lib/tir/defun.ml mints both the closure struct's TCon name
   (["$Clo_" ^ fn_name ^ "$" ^ uid]) and its apply-wrapper fn name (see
   [apply_fn_name] below) at lambda-lifting time.
   Consumer: lib/tir/borrow.ml's [is_clo_struct] (previously inline) checks
   a TCon name for this prefix to distinguish a closure allocation from an
   ordinary constructor allocation, for FV-borrow classification. *)

(** Prefix shared by every defunctionalized closure struct's TCon name. *)
let clo_struct_prefix = "$Clo_"

(** True if [tcon_name] names a closure struct type ("$Clo_..."). Mirrors
    borrow.ml's inline check
    (`String.length n >= 5 && String.sub n 0 5 = "$Clo_"`). *)
let is_clo_struct (tcon_name : string) : bool =
  String.length tcon_name >= 5 && String.sub tcon_name 0 5 = clo_struct_prefix

(* ── Closure apply wrappers: "<fn>$apply$<uid>" ─────────────────────────
   Producer: lib/tir/defun.ml mints the apply-wrapper fn name as
   [Printf.sprintf "%s$apply$%d" fn.fn_name lam.lam_uid].
   Consumers: lib/tir/perceus.ml and lib/tir/llvm_emit.ml each had their own
   copy of [is_apply_fn] (perceus.ml:246, llvm_emit.ml:457 pre-move).

   DIFF VERDICT (Wave 3 Task 1, per the plan's mandated check): the two
   copies were read side-by-side and are BYTE-IDENTICAL — same substring
   scanner, same "$apply$" marker, same recursive [scan] helper, same
   guard. This is a case of duplicated-but-NOT-diverged code (unlike the
   [needs_rc] divergence flagged for Task 2), so unifying them here is a
   safe pure move, not a behavior change. Both former call sites are
   pointed at this single definition. *)

(** True for a defunctionalized closure apply wrapper ("<fn>$apply$<uid>").

    These are dispatched indirectly through a closure struct whose
    fn-pointer is type-erased, so all wrappers for a given source
    `(a) -> b` MUST share one calling convention: the generic ptr ABI
    (scalar results tagged via the i64->ptr coercion; heap pointers pass
    through unchanged; every call site reads the result as ptr). An apply
    function's first parameter is also always the closure struct
    ([$clo]); the closure-apply ABI CONSUMES that argument (ownership
    transfers to the callee) — this must override any borrow-map
    classification of the [$clo] slot in perceus.ml. *)
let is_apply_fn (name : string) : bool =
  let marker = "$apply$" in
  let nl = String.length name and ml = String.length marker in
  let rec scan i =
    i + ml <= nl && (String.sub name i ml = marker || scan (i + 1))
  in
  nl >= ml && scan 0

(** The closure struct's TCon name for a lifted lambda, e.g.
    [clo_struct_name ~fn_name:"foo" ~lam_uid:3 = "$Clo_foo$3"]. Mirrors
    defun.ml's inline [Printf.sprintf "$Clo_%s$%d" fn_name lam_uid]. *)
let clo_struct_name ~(fn_name : string) ~(lam_uid : int) : string =
  Printf.sprintf "$Clo_%s$%d" fn_name lam_uid

(** The apply-wrapper fn name for a lifted lambda, e.g.
    [apply_fn_name ~fn_name:"foo" ~lam_uid:3 = "foo$apply$3"]. Mirrors
    defun.ml's inline [Printf.sprintf "%s$apply$%d" fn_name lam_uid]. *)
let apply_fn_name ~(fn_name : string) ~(lam_uid : int) : string =
  Printf.sprintf "%s$apply$%d" fn_name lam_uid

(* ── Closure-struct parameter name: "$clo" ──────────────────────────────
   Producer: lib/tir/defun.ml binds every apply-wrapper's first parameter
   to this fixed name (the opaque pointer to the closure struct itself).
   Consumer: lib/tir/perceus.ml's [collect_closure_fvs] checks a fn's first
   parameter name against this constant to recognise an apply function (an
   independent signal from [is_apply_fn], checked against the PARAMETER,
   not the function name). *)

(** Fixed parameter name for the closure-struct pointer in an apply
    wrapper's parameter list (always parameter 0). *)
let clo_param_name = "$clo"

(* ── Try-call thunks: "__try_call" / "__try_call_val" ───────────────────
   Producer: these are compiler builtins registered directly in
   lib/typecheck/typecheck.ml and lib/eval/eval.ml (not synthesized by a
   TIR pass) — user code calls them by name, e.g. `__try_call(fn _ -> ...)`.
   Consumer: lib/tir/borrow.ml's [is_try] recognises the thunk argument as
   consumed-and-freed locally (not an escape). *)

(** True if [fn_name] names the try-call builtin family ("__try_call" /
    "__try_call_val"). Mirrors borrow.ml's inline
    [String.equal f "__try_call" || String.equal f "__try_call_val"]. *)
let is_try_call (fn_name : string) : bool =
  String.equal fn_name "__try_call" || String.equal fn_name "__try_call_val"

(* ── Interface-impl mangling: "Iface$Ty.method[$Spec]" ──────────────────
   Producer: the interface-impl-method mangled name ("Iface$Ty.method") is
   built where DImpl declarations are lowered (outside lib/tir's grep
   surface for this task — the mangling convention is documented, not
   re-derived, here); lib/tir/mono.ml further specializes an already-
   mangled generic impl by appending a second "$"-separated suffix (e.g.
   "Show$List.show" + [List(Int)] -> "Show$List.show$List_Int") — see
   mono.ml's [enqueue_specialized_impl] comment, which explicitly notes
   "no shared Tir_names-style helper exists yet — that's Wave 3".
   Consumer: lib/tir/llvm_emit.ml's [emit_module] (building [unqualified_fns])
   and [fail_if_unresolved_iface_method] each independently computed "is
   there a '$' before the LAST '.'?" to detect an interface-impl-mangled
   name and exclude/report it (Wave 2 Task 1 defense-in-depth for the
   println-of-list miscompile). Both copies were byte-identical:
   [match String.index_opt name '$' with Some j -> j < i | None -> false]
   where [i] is the position of [String.rindex_opt name '.']. *)

(** True if [name] is an interface-impl-mangled name — i.e. contains a
    ['$'] before its LAST ['.'] (an ordinary qualified name like
    "Crypto.base64_encode" or "App.Core.b" never contains ['$'], so those
    are unaffected). Deliberately FALSE for names with no '.' at all, and
    FALSE for a `$` that appears only after the last '.' (e.g.
    "List.map$Int" — a specialized ordinary generic fn, not an interface
    impl). Mirrors the two byte-identical inline copies in llvm_emit.ml. *)
let is_iface_mangled (name : string) : bool =
  match String.rindex_opt name '.' with
  | None -> false
  | Some i ->
    (match String.index_opt name '$' with
     | Some j -> j < i
     | None -> false)

(** Build an interface-impl mangled name: [iface_mangle ~iface:"Show"
    ~ty:"List" ~meth:"show" = "Show$List.show"]. Mirrors the producer-side
    convention documented above (the sprintf pattern
    [Printf.sprintf "%s$%s.%s" iface ty meth]). Provided so future
    producers don't re-derive the format string; not yet substituted at
    the producer site (outside this task's grep surface). *)
let iface_mangle ~(iface : string) ~(ty : string) ~(meth : string) : string =
  Printf.sprintf "%s$%s.%s" iface ty meth

(* ── Default-argument mangling: "base$N" ────────────────────────────────
   Producer: lib/desugar/desugar.ml's [expand_defaults_decl] mints, for a
   fn with default params, a full-arity mangled decl ["%s$%d" name
   n_total] plus one short-arity mangled decl per default-arity prefix
   (same format, [this_arity] in place of [n_total]). NOTE: march_desugar
   cannot depend on march_tir (march_tir already depends on march_desugar
   transitively via march_modules — lib/tir/lower.ml calls
   [March_desugar.Desugar.desugar_module] for lazy stdlib lowering, so the
   reverse edge would be a build cycle). [default_arg_mangle] is provided
   here as the documented format for any FUTURE producer that lives inside
   lib/tir, but desugar.ml's existing inline [Printf.sprintf "%s$%d" ...]
   was NOT converted to call it this chunk — that would require moving
   the mangling scheme itself, not just a caller.
   Consumer: lib/tir/lower.ml's [build_default_dispatch] parses these back
   to build the dispatch table consulted when lowering an [Ast.EApp]
   callee — this side IS converted (same library, no cycle). *)

(** Build a default-arg mangled name: [default_arg_mangle "greet" 2 =
    "greet$2"]. Mirrors desugar.ml's inline [Printf.sprintf "%s$%d" name
    arity] (used for both the full-arity and each short-arity decl); not
    yet called from desugar.ml itself — see the cross-library note above. *)
let default_arg_mangle (base : string) (arity : int) : string =
  Printf.sprintf "%s$%d" base arity

(** Parse a default-arg mangled name back into [(base, arity)], e.g.
    [parse_default_arg "greet$2" = Some ("greet", 2)]. Returns [None] if
    there is no ['$'], the ['$'] is at position 0 (empty base — mirrors
    the [dollar_pos > 0] guard at the lower.ml consumer site), or the
    suffix after ['$'] doesn't parse as an int. Uses the LAST ['$'] (mirrors
    lower.ml's [String.rindex_opt name '$'] — the mangled name itself
    never contains another ['$'], but this matches the exact scan
    direction used at the consumer site). *)
let parse_default_arg (name : string) : (string * int) option =
  match String.rindex_opt name '$' with
  | Some dollar_pos when dollar_pos > 0 ->
    let base = String.sub name 0 dollar_pos in
    let suffix = String.sub name (dollar_pos + 1) (String.length name - dollar_pos - 1) in
    (match int_of_string_opt suffix with
     | Some arity -> Some (base, arity)
     | None -> None)
  | _ -> None

(* ── Actor codegen: type/fn suffixes + field-sort prefixes ──────────────
   Producer: lib/tir/lower.ml's [lower_actor] mints, for an actor [Name]:
     - types  "Name_Msg" (message variant), "Name_Actor" (struct),
       "Name_State" (hot-reload-mode state record)
     - fns    "Name_<Handler>" (one per handler), "Name_dispatch",
       "Name_spawn"
     - fields "$d_dispatch", "$e_alive", "$f_state" (hot-reload only) on
       the "Name_Actor" struct — prefixed so that ALPHABETICAL SORT ($d <
       $e < $f < any letter) matches both the struct's alloc/reuse arg
       order (lower.ml) and the C RUNTIME'S HARDCODED WORD INDICES: the
       runtime reads the dispatch pointer at a[2] and the alive flag at
       a[3] (a[4] = state ptr in hot-reload mode) — see lower.ml's
       [lower_actor] doc comment. Changing these three field names, or any
       name that would alphabetically re-sort between them, breaks the
       runtime's hardcoded offsets.
   Consumers: lib/tir/llvm_emit.ml checks the "_Actor" / "_dispatch"
   suffixes at three independent sites (EAlloc HCR dispatch-slot wiring,
   [emit_fn]'s visibility-prefix decision, [emit_module]'s
   [is_actor_dispatch_fn] for hot-reload NAME_ID interning) — all three
   were byte-identical [ends_with] suffix checks before this move. *)

(** Suffix for an actor's message variant type name ("Name" -> "Name_Msg"). *)
let actor_msg_suffix = "_Msg"

(** Suffix for an actor's struct type name ("Name" -> "Name_Actor"). *)
let actor_struct_suffix = "_Actor"

(** Suffix for an actor's hot-reload-mode state record type name
    ("Name" -> "Name_State"). *)
let actor_state_suffix = "_State"

(** Suffix for an actor's dispatch fn name ("Name" -> "Name_dispatch"). *)
let actor_dispatch_suffix = "_dispatch"

(** Suffix for an actor's spawn fn name ("Name" -> "Name_spawn"). *)
let actor_spawn_suffix = "_spawn"

(** Actor struct field name for the dispatch-fn pointer slot (field 0).
    C-runtime word index: a[2]. MUST alphabetically sort before
    [actor_alive_field] and [actor_state_field] — see module doc above. *)
let actor_dispatch_field = "$d_dispatch"

(** Actor struct field name for the alive flag (field 1). C-runtime word
    index: a[3]. MUST alphabetically sort between [actor_dispatch_field]
    and [actor_state_field] — see module doc above. *)
let actor_alive_field = "$e_alive"

(** Actor struct field name for the hot-reload state-record pointer (field
    2, hot-reload mode only). C-runtime word index: a[4]. MUST
    alphabetically sort after [actor_alive_field] — see module doc above. *)
let actor_state_field = "$f_state"

(** True if [fn_name] ends in the actor-struct-type suffix ("...( _Actor")
    — used at TCon-name granularity, e.g. checking [alloc_type_name].
    Mirrors llvm_emit.ml's inline EAlloc HCR-wiring check. *)
let is_actor_struct_name (tcon_name : string) : bool =
  let sfx = actor_struct_suffix in
  let nl = String.length tcon_name and sl = String.length sfx in
  nl > sl && String.sub tcon_name (nl - sl) sl = sfx

(** True if [fn_name] ends in the actor-dispatch-fn suffix ("..._dispatch").
    Mirrors the two byte-identical inline copies (llvm_emit.ml's [emit_fn]
    visibility-prefix decision and [emit_module]'s
    [is_actor_dispatch_fn]). *)
let is_actor_dispatch_fn (fn_name : string) : bool =
  let sfx = actor_dispatch_suffix in
  let nl = String.length fn_name and sl = String.length sfx in
  nl > sl && String.sub fn_name (nl - sl) sl = sfx

(* ── Bool tags: "True"/"False" / "true"/"false" / string_of_bool ────────
   Three distinct spellings coexist across the pipeline (documented, NOT
   unified this chunk — see the plan's Task 1 scope note: "ONLY centralize
   the producers; llvm_emit's capitalize-tolerant decoder stays as-is"):
     - lib/tir/lower.ml's if/then-else and assert desugaring-to-ECase
       synthesizes the CAPITALIZED branch tag "True" for the single
       explicit arm of a synthetic 2-branch bool case, leaving the
       else/panic arm as the ECase's wildcard [None] default (never an
       explicit "False" branch) — 3 sites (EIf, ECond, assert-lowering).
     - lib/tir/fusion.ml's generated fold/filter/map-fusion loop bodies
       synthesize a full two-ARM case with BOTH "True" AND "False" branch
       tags explicitly (no wildcard default) when dispatching on a
       predicate's result — 2 sites (gen_filter_fold, gen_map_filter_fold).
     - lib/tir/lower.ml's [pat_tag_and_subs] (PatLit(LitBool b)) instead
       produces the LOWERCASE [string_of_bool b] ("true"/"false") for an
       explicit `true`/`false` literal pattern written by the user — this
       is the one lower.ml site using [string_of_bool] instead of a
       literal "True" (the guard-desugaring site uses lowercase "true"
       explicitly, matching [string_of_bool]).
     - lib/tir/llvm_emit.ml's [is_bool_tag] / boolean-case dispatch
       tolerates BOTH capitalizations ("true" || "True" || "false" ||
       "False") when scanning branch tags — this decoder is explicitly
       OUT OF SCOPE for this chunk (plan: "stays as-is").
   This module centralizes the PRODUCER spellings so future producer
   sites reuse a name instead of re-typing "True"/"False" or
   [string_of_bool]; it does not change the decoder or attempt to unify
   the spellings. *)

(** The capitalized "true" branch tag synthesized for a 2-branch bool
    ECase. Used both where the other arm is a wildcard [None] default
    (lower.ml's if/else, assert) and where the other arm is an explicit
    "False" tag (fusion.ml's generated loops — see [synthetic_false_tag]).
    NOT used for literal `true`/`false` patterns — see [bool_lit_tag]. *)
let synthetic_true_tag = "True"

(** The capitalized "false" branch tag, used only where fusion.ml
    generates an explicit two-arm (True/False) ECase with no wildcard
    default. NOT used for literal `true`/`false` patterns — see
    [bool_lit_tag]. *)
let synthetic_false_tag = "False"

(** The branch tag for an explicit boolean literal pattern (`true` /
    `false` written by the user), lowercase. Mirrors [pat_tag_and_subs]'s
    [string_of_bool b] for [PatLit (LitBool b)]. *)
let bool_lit_tag (b : bool) : string = string_of_bool b

(* ── Test/setup synthetic fn names ──────────────────────────────────────
   Producer: lib/tir/lower.ml mints "__march_test_N__" (N = a per-module
   counter) for each `test "..." do ... end` block, and the fixed names
   "__march_setup__" / "__march_setup_all__" for `setup`/`setup_all` blocks
   (last decl wins per lower.ml's comment).
   Consumers: lib/tir/dce.ml (keeps setup fns alive across DCE by exact
   name); lib/tir/llvm_emit.ml (locates the setup fns by exact name to wire
   test-harness entry points, 3 sites). *)

(** Synthetic fn name for the Nth `test` block in a module. *)
let test_fn_name (n : int) : string = Printf.sprintf "__march_test_%d__" n

(** Fixed synthetic fn name for a module's `setup` block. *)
let setup_fn_name = "__march_setup__"

(** Fixed synthetic fn name for a module's `setup_all` block. *)
let setup_all_fn_name = "__march_setup_all__"

(* ── C-runtime extern prefix: "march_" ──────────────────────────────────
   Producer: lib/tir/lower.ml injects C-runtime extern calls (e.g.
   march_compare_int, march_hash_int) with this fixed prefix when
   synthesizing Ord$T.compare / Hash$T.hash wrapper bodies.
   Consumers: lib/tir/llvm_emit.ml checks this 6-char prefix at four
   aligned sites ([is_leaf_callee]'s reduction-check exemption, and three
   "is this AVar a first-class reference to a C-runtime extern, not a
   local/top-level fn" guards) — all four were byte-identical
   [String.length n >= 6 && String.sub n 0 6 = "march_"] checks before
   this move. (Historical note, B9: one of these briefly regressed to a
   7-char substring compared against the 6-char literal — permanently
   false — fixed 2026-07-01; all four sites now agree.) *)

(** Fixed prefix for compiler-internal C-runtime extern names. *)
let runtime_prefix = "march_"

(** True if [name] starts with the C-runtime extern prefix ("march_...").
    Mirrors the four byte-identical inline checks in llvm_emit.ml. *)
let has_runtime_prefix (name : string) : bool =
  let sfx = runtime_prefix in
  String.length name >= String.length sfx
  && String.sub name 0 (String.length sfx) = sfx
