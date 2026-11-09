(** The registry of diagnostic codes.

    Every diagnostic the compiler emits carries exactly one code from this
    module (the [code] field of {!Errors.diagnostic} is not optional). A code
    is a [snake_case] slug: unique, never reused for a different condition,
    and never renamed once shipped, because the LSP's quick-fixes, the
    [march --explain <slug>] pages under [specs/lang/errors/] and any tooling
    that counts errors key on it.

    Adding a code: add a [let] here AND to [all] (doc-lint Check G in
    scripts/check-docs.sh cross-checks the two), then use the constant at the
    emitting site. Never write a slug
    as a string literal outside this file; doc-lint Check G
    (scripts/check-docs.sh) fails on one.

    A few codes carry an argument after a colon ([cap_needs:IO.FileRead]),
    built with {!with_arg}; the slug is the part before the colon
    ({!slug_of}). See specs/plans/diagnostics-and-triage-plan.md §7. *)

let abstract_refinement_misuse = "abstract_refinement_misuse"
let abstract_refinement_unused = "abstract_refinement_unused"
let actor_handler_state_type = "actor_handler_state_type"
let actor_init_arity = "actor_init_arity"
let alias_kind_mismatch = "alias_kind_mismatch"
let ambiguous_constructor = "ambiguous_constructor"
let annotated_tyvar_fixed = "annotated_tyvar_fixed"
let arity_mismatch = "arity_mismatch"
let assert_failed = "assert_failed"
let attribute_no_effect = "attribute_no_effect"
let builtin_arity = "builtin_arity"
let cap_bound = "cap_bound"
let cap_bound_needs = "cap_bound_needs"
let cap_bound_iface = "cap_bound_iface"
let cap_ceiling = "cap_ceiling"
let cap_deserialize = "cap_deserialize"
let cap_dict_misuse = "cap_dict_misuse"
let cap_dict_type = "cap_dict_type"
let cap_grant = "cap_grant"
let cap_grant_exceeded = "cap_grant_exceeded"
let cap_impl_invalid = "cap_impl_invalid"
let cap_mismatch = "cap_mismatch"
let cap_narrow_invalid = "cap_narrow_invalid"
let cap_needs = "cap_needs"
let cap_root_broad = "cap_root_broad"
let cap_scope_violation = "cap_scope_violation"
let cap_widen = "cap_widen"
let callback_arity_mismatch = "callback_arity_mismatch"
let codec_missing = "codec_missing"
let compiled_unsupported = "compiled_unsupported"
let constructor_arity = "constructor_arity"
let curried_lambda_over_tuple = "curried_lambda_over_tuple"
let deterministic_violation = "deterministic_violation"
let diverges_conflict = "diverges_conflict"
let division_by_zero = "division_by_zero"
let duplicate_actor = "duplicate_actor"
let duplicate_binder = "duplicate_binder"
let duplicate_constructor = "duplicate_constructor"
let duplicate_field = "duplicate_field"
let duplicate_handler = "duplicate_handler"
let duplicate_protocol = "duplicate_protocol"
let elif_keyword = "elif_keyword"
let empty_match = "empty_match"
let endpoints_label_invalid = "endpoints_label_invalid"
let endpoints_name_clash = "endpoints_name_clash"
let extern_cap_missing = "extern_cap_missing"
let extern_needs_foreign = "extern_needs_foreign"
let field_access_non_record = "field_access_non_record"
let import_cap_missing = "import_cap_missing"
let import_unresolved = "import_unresolved"
let internal_error = "internal_error"
let int_overflow = "int_overflow"
let invalid_cap_scope = "invalid_cap_scope"
let invalid_decreases = "invalid_decreases"
let invalid_lemma = "invalid_lemma"
let invalid_measure = "invalid_measure"
let invalid_reflect = "invalid_reflect"
let invalid_type_bound = "invalid_type_bound"
let invariant_not_deploy_checkable = "invariant_not_deploy_checkable"
let io_not_allowed = "io_not_allowed"
let island_missing_fn = "island_missing_fn"
let json_derive_name_collision = "json_derive_name_collision"
let lemma_argument_impure = "lemma_argument_impure"
let lemma_unproved = "lemma_unproved"
let lemma_unproved_call = "lemma_unproved_call"
let let_question_last = "let_question_last"
let let_star_bad_flat_map = "let_star_bad_flat_map"
let let_star_last = "let_star_last"
let let_star_no_flat_map = "let_star_no_flat_map"
let let_star_unknown_type = "let_star_unknown_type"
let lex_error = "lex_error"
let linear_captured = "linear_captured"
let linear_discarded = "linear_discarded"
let linear_field_untracked = "linear_field_untracked"
let linear_generic_param = "linear_generic_param"
let linear_mixed_consumption = "linear_mixed_consumption"
let linear_module_let = "linear_module_let"
let linear_never_used = "linear_never_used"
let linear_unconsumed_early_return = "linear_unconsumed_early_return"
let linear_used_twice = "linear_used_twice"
let main_and_app = "main_and_app"
let main_signature = "main_signature"
let measure_scalar_field = "measure_scalar_field"
let migrate_msg_shape = "migrate_msg_shape"
let mint_cap_invalid = "mint_cap_invalid"
let missing_impl = "missing_impl"
let missing_method = "missing_method"
let missing_superclass_impl = "missing_superclass_impl"
let module_keyword = "module_keyword"
let no_alloc = "no_alloc"
let no_alloc_candidate = "no_alloc_candidate"
let no_alloc_policy = "no_alloc_policy"
let no_alloc_transient = "no_alloc_transient"
let no_alloc_unchecked = "no_alloc_unchecked"
let no_extern_violation = "no_extern_violation"
let no_panic_violation = "no_panic_violation"
let non_exhaustive_match = "non_exhaustive_match"
let non_tail_recursion = "non_tail_recursion"
let nonregular_type = "nonregular_type"
let not_a_function = "not_a_function"
let not_a_nat = "not_a_nat"
let not_a_variant = "not_a_variant"
let or_pattern_binding = "or_pattern_binding"
let overlapping_impl = "overlapping_impl"
let parse_error = "parse_error"
let pid_serialize = "pid_serialize"
let pipe_into_match = "pipe_into_match"
let pipe_match_pattern = "pipe_match_pattern"
let portable_capture = "portable_capture"
let predicate_eq_structural = "predicate_eq_structural"
let predicate_vocabulary_shadowed = "predicate_vocabulary_shadowed"
let prelude_collision = "prelude_collision"
let proof_cap_foreign = "proof_cap_foreign"
let proof_cap_mint_private = "proof_cap_mint_private"
let proof_cap_return = "proof_cap_return"
let property_failed = "property_failed"
let protocol_crash_branches = "protocol_crash_branches"
let protocol_empty = "protocol_empty"
let protocol_expand_invalid = "protocol_expand_invalid"
let protocol_invalid = "protocol_invalid"
let protocol_projection = "protocol_projection"
let protocol_same_participants = "protocol_same_participants"
let protocol_single_participant = "protocol_single_participant"
let protocol_step_order = "protocol_step_order"
let protocol_unlabelled_step = "protocol_unlabelled_step"
let protocol_wrong_role = "protocol_wrong_role"
let pure_violation = "pure_violation"
let realtime_mixed = "realtime_mixed"
let record_update_non_record = "record_update_non_record"
let recursive_type_alias = "recursive_type_alias"
let redundant_arm = "redundant_arm"
let redundant_csrf_token = "redundant_csrf_token"
let refinement_ignored = "refinement_ignored"
let refinement_unchecked = "refinement_unchecked"
let refinement_unverified = "refinement_unverified"
let refinement_violated = "refinement_violated"
let reflect_conflict = "reflect_conflict"
let reflect_inconsistent = "reflect_inconsistent"
let remote_actor_unroutable = "remote_actor_unroutable"
let reserved_type_name = "reserved_type_name"
let return_refinement_violated = "return_refinement_violated"
let role_grant_exceeded = "role_grant_exceeded"
let role_grant_too_wide = "role_grant_too_wide"
let role_grant_unverified = "role_grant_unverified"
let role_needs_invalid = "role_needs_invalid"
let root_cap_reference = "root_cap_reference"
let satisfy_missing_fn = "satisfy_missing_fn"
let semicolon_separator = "semicolon_separator"
let send_wrong_actor = "send_wrong_actor"
let session_choice_label = "session_choice_label"
let session_not_closed = "session_not_closed"
let session_offer_nonexhaustive = "session_offer_nonexhaustive"
let session_offer_unrefined = "session_offer_unrefined"
let session_protocol_arg = "session_protocol_arg"
let session_role_count = "session_role_count"
let session_role_mismatch = "session_role_mismatch"
let session_state_mismatch = "session_state_mismatch"
let session_type_mismatch = "session_type_mismatch"
let session_unreachable_branch = "session_unreachable_branch"
let set_measure_call = "set_measure_call"
let set_refinement_type = "set_refinement_type"
let sig_mismatch = "sig_mismatch"
let sigil_interpolation = "sigil_interpolation"
let solver_unavailable = "solver_unavailable"
let solver_version_mismatch = "solver_version_mismatch"
let spawn_computed_actor = "spawn_computed_actor"
let spawn_not_actor = "spawn_not_actor"
let stdlib_internal = "stdlib_internal"
let supervise_field_missing = "supervise_field_missing"
let syntax_error = "syntax_error"
let template_fragment_position = "template_fragment_position"
let template_unsafe_interpolation = "template_unsafe_interpolation"
let template_unterminated = "template_unterminated"
let termination_unproved = "termination_unproved"
let test_panicked = "test_panicked"
let then_keyword = "then_keyword"
let transition_via_mismatch = "transition_via_mismatch"
let trusted_linear_invalid = "trusted_linear_invalid"
let trusted_linear_reserved = "trusted_linear_reserved"
let type_arity = "type_arity"
let type_mismatch = "type_mismatch"
let typed_hole = "typed_hole"
let unbound_variable = "unbound_variable"
let undeclared_requirement = "undeclared_requirement"
let undeclared_transition = "undeclared_transition"
let unknown_attribute = "unknown_attribute"
let unknown_capability = "unknown_capability"
let unknown_constructor = "unknown_constructor"
let unknown_derive = "unknown_derive"
let unknown_export = "unknown_export"
let unknown_interface = "unknown_interface"
let unknown_method = "unknown_method"
let unknown_protocol = "unknown_protocol"
let unknown_qualified_name = "unknown_qualified_name"
let unknown_record_field = "unknown_record_field"
let unknown_role = "unknown_role"
let unknown_session_op = "unknown_session_op"
let unsatisfied_constraint = "unsatisfied_constraint"
let unsendable_type = "unsendable_type"
let unused_binding = "unused_binding"
let unused_import = "unused_import"
let unused_needs = "unused_needs"
let vectorize_failed = "vectorize_failed"
let copy_shared = "copy_shared"
(* Run-time failures the interpreter reports in the compile-error style. *)
let panic = "panic"
let runtime_error = "runtime_error"
let actor_crashed = "actor_crashed"

(** Every code above, sorted. *)
let all = [
  abstract_refinement_misuse;
  abstract_refinement_unused;
  actor_handler_state_type;
  actor_init_arity;
  alias_kind_mismatch;
  ambiguous_constructor;
  annotated_tyvar_fixed;
  arity_mismatch;
  assert_failed;
  attribute_no_effect;
  builtin_arity;
  cap_bound;
  cap_bound_needs;
  cap_bound_iface;
  cap_ceiling;
  cap_deserialize;
  cap_dict_misuse;
  cap_dict_type;
  cap_grant;
  cap_grant_exceeded;
  cap_impl_invalid;
  cap_mismatch;
  cap_narrow_invalid;
  cap_needs;
  cap_root_broad;
  cap_scope_violation;
  cap_widen;
  callback_arity_mismatch;
  codec_missing;
  compiled_unsupported;
  constructor_arity;
  curried_lambda_over_tuple;
  deterministic_violation;
  diverges_conflict;
  division_by_zero;
  duplicate_actor;
  duplicate_binder;
  duplicate_constructor;
  duplicate_field;
  duplicate_handler;
  duplicate_protocol;
  elif_keyword;
  empty_match;
  endpoints_label_invalid;
  endpoints_name_clash;
  extern_cap_missing;
  extern_needs_foreign;
  field_access_non_record;
  import_cap_missing;
  import_unresolved;
  internal_error;
  int_overflow;
  invalid_cap_scope;
  invalid_decreases;
  invalid_lemma;
  invalid_measure;
  invalid_reflect;
  invalid_type_bound;
  invariant_not_deploy_checkable;
  io_not_allowed;
  island_missing_fn;
  json_derive_name_collision;
  lemma_argument_impure;
  lemma_unproved;
  lemma_unproved_call;
  let_question_last;
  let_star_bad_flat_map;
  let_star_last;
  let_star_no_flat_map;
  let_star_unknown_type;
  lex_error;
  linear_captured;
  linear_discarded;
  linear_field_untracked;
  linear_generic_param;
  linear_mixed_consumption;
  linear_module_let;
  linear_never_used;
  linear_unconsumed_early_return;
  linear_used_twice;
  main_and_app;
  main_signature;
  measure_scalar_field;
  migrate_msg_shape;
  mint_cap_invalid;
  missing_impl;
  missing_method;
  missing_superclass_impl;
  module_keyword;
  no_alloc;
  no_alloc_candidate;
  no_alloc_policy;
  no_alloc_transient;
  no_alloc_unchecked;
  no_extern_violation;
  no_panic_violation;
  non_exhaustive_match;
  non_tail_recursion;
  nonregular_type;
  not_a_function;
  not_a_nat;
  not_a_variant;
  or_pattern_binding;
  overlapping_impl;
  parse_error;
  pid_serialize;
  pipe_into_match;
  pipe_match_pattern;
  portable_capture;
  predicate_eq_structural;
  predicate_vocabulary_shadowed;
  prelude_collision;
  proof_cap_foreign;
  proof_cap_mint_private;
  proof_cap_return;
  property_failed;
  protocol_crash_branches;
  protocol_empty;
  protocol_expand_invalid;
  protocol_invalid;
  protocol_projection;
  protocol_same_participants;
  protocol_single_participant;
  protocol_step_order;
  protocol_unlabelled_step;
  protocol_wrong_role;
  pure_violation;
  realtime_mixed;
  record_update_non_record;
  recursive_type_alias;
  redundant_arm;
  redundant_csrf_token;
  refinement_ignored;
  refinement_unchecked;
  refinement_unverified;
  refinement_violated;
  reflect_conflict;
  reflect_inconsistent;
  remote_actor_unroutable;
  reserved_type_name;
  return_refinement_violated;
  role_grant_exceeded;
  role_grant_too_wide;
  role_grant_unverified;
  role_needs_invalid;
  root_cap_reference;
  satisfy_missing_fn;
  semicolon_separator;
  send_wrong_actor;
  session_choice_label;
  session_not_closed;
  session_offer_nonexhaustive;
  session_offer_unrefined;
  session_protocol_arg;
  session_role_count;
  session_role_mismatch;
  session_state_mismatch;
  session_type_mismatch;
  session_unreachable_branch;
  set_measure_call;
  set_refinement_type;
  sig_mismatch;
  sigil_interpolation;
  solver_unavailable;
  solver_version_mismatch;
  spawn_computed_actor;
  spawn_not_actor;
  stdlib_internal;
  supervise_field_missing;
  syntax_error;
  template_fragment_position;
  template_unsafe_interpolation;
  template_unterminated;
  termination_unproved;
  test_panicked;
  then_keyword;
  transition_via_mismatch;
  trusted_linear_invalid;
  trusted_linear_reserved;
  type_arity;
  type_mismatch;
  typed_hole;
  unbound_variable;
  undeclared_requirement;
  undeclared_transition;
  unknown_attribute;
  unknown_capability;
  unknown_constructor;
  unknown_derive;
  unknown_export;
  unknown_interface;
  unknown_method;
  unknown_protocol;
  unknown_qualified_name;
  unknown_record_field;
  unknown_role;
  unknown_session_op;
  unsatisfied_constraint;
  unsendable_type;
  unused_binding;
  unused_import;
  unused_needs;
  vectorize_failed;
  copy_shared;
  panic;
  runtime_error;
  actor_crashed;
]

(** [with_arg slug arg] is the code [slug ^ ":" ^ arg]. *)
let with_arg slug arg = slug ^ ":" ^ arg

(** The slug of a code: everything before the first [':']. *)
let slug_of code =
  match String.index_opt code ':' with
  | Some i -> String.sub code 0 i
  | None -> code

(* ── Categories ────────────────────────────────────────────────────────

   Every code belongs to one category, the title of its rendered header
   (`-- TYPE MISMATCH ------ file`, Elm's convention; plan §X5), and the
   `category` field of its `--check-json` object.  A small, fixed set: a
   reader should know from the header which part of the language objected,
   not which compiler pass did.  A warning or hint keeps its severity in the
   title (`-- WARNING: UNUSED --`, `-- HINT: REFINEMENT --`).

   Adding a code: add it to exactly one list below.  test_compiler's
   "every code has one category" case checks [all] against this table. *)

let category_table : (string * string list) list = [
  "SYNTAX", [
    curried_lambda_over_tuple; elif_keyword; let_question_last; let_star_last;
    lex_error; module_keyword; parse_error; pipe_into_match; pipe_match_pattern;
    semicolon_separator; sigil_interpolation; syntax_error;
    template_fragment_position; template_unsafe_interpolation;
    template_unterminated; then_keyword ];
  "NAMING", [
    ambiguous_constructor; duplicate_binder; duplicate_constructor;
    duplicate_field; import_unresolved; prelude_collision; reserved_type_name; unbound_variable;
    unknown_constructor; unknown_export; unknown_qualified_name;
    unknown_record_field ];
  "TYPE MISMATCH", [
    annotated_tyvar_fixed; arity_mismatch; builtin_arity;
    callback_arity_mismatch; constructor_arity; field_access_non_record;
    let_star_bad_flat_map; main_signature; not_a_function; not_a_nat;
    not_a_variant; record_update_non_record; sig_mismatch; type_arity;
    type_mismatch ];
  "TYPE", [
    alias_kind_mismatch; invalid_type_bound; let_star_no_flat_map; let_star_unknown_type;
    nonregular_type; recursive_type_alias; typed_hole; unsendable_type ];
  "INTERFACE", [
    json_derive_name_collision; missing_impl; missing_method;
    missing_superclass_impl; overlapping_impl; satisfy_missing_fn;
    unknown_derive; unknown_interface; unknown_method; unsatisfied_constraint ];
  "PATTERN", [
    empty_match; non_exhaustive_match; or_pattern_binding; redundant_arm ];
  "CAPABILITY", [
    cap_bound; cap_bound_needs; cap_bound_iface; cap_ceiling; cap_deserialize;
    cap_dict_misuse; cap_dict_type; cap_grant; cap_grant_exceeded;
    cap_impl_invalid; cap_mismatch; cap_narrow_invalid; cap_needs;
    cap_root_broad; cap_scope_violation; cap_widen; extern_cap_missing;
    extern_needs_foreign; import_cap_missing; invalid_cap_scope;
    io_not_allowed; mint_cap_invalid; proof_cap_foreign;
    proof_cap_mint_private; proof_cap_return; role_grant_exceeded;
    role_grant_too_wide; role_grant_unverified; root_cap_reference;
    undeclared_requirement; unknown_capability; unused_needs ];
  "LINEARITY", [
    linear_captured; linear_discarded; linear_field_untracked;
    linear_generic_param; linear_mixed_consumption; linear_module_let;
    linear_never_used; linear_unconsumed_early_return; linear_used_twice;
    portable_capture; trusted_linear_invalid; trusted_linear_reserved ];
  "ACTOR", [
    actor_handler_state_type; actor_init_arity; codec_missing;
    duplicate_actor; duplicate_handler; island_missing_fn; migrate_msg_shape;
    pid_serialize; remote_actor_unroutable; send_wrong_actor;
    spawn_computed_actor; spawn_not_actor; supervise_field_missing ];
  "PROTOCOL", [
    duplicate_protocol; endpoints_label_invalid; endpoints_name_clash;
    protocol_crash_branches; protocol_empty; protocol_expand_invalid;
    protocol_invalid; protocol_projection; protocol_same_participants;
    protocol_single_participant; protocol_step_order; protocol_unlabelled_step;
    protocol_wrong_role; role_needs_invalid;
    session_choice_label; session_not_closed; session_offer_nonexhaustive;
    session_offer_unrefined; session_protocol_arg; session_role_count;
    session_role_mismatch; session_state_mismatch; session_type_mismatch;
    session_unreachable_branch; transition_via_mismatch;
    undeclared_transition; unknown_protocol; unknown_role; unknown_session_op ];
  "REFINEMENT", [
    abstract_refinement_misuse; abstract_refinement_unused; division_by_zero;
    int_overflow; invalid_lemma; invalid_measure; invalid_reflect;
    invariant_not_deploy_checkable;
    lemma_argument_impure; lemma_unproved; lemma_unproved_call;
    measure_scalar_field; predicate_eq_structural; predicate_vocabulary_shadowed;
    refinement_ignored;
    refinement_unchecked; refinement_unverified; refinement_violated;
    reflect_conflict; reflect_inconsistent; return_refinement_violated;
    set_measure_call; set_refinement_type; solver_unavailable;
    solver_version_mismatch ];
  "RECURSION", [
    diverges_conflict; invalid_decreases; non_tail_recursion;
    termination_unproved ];
  "CONTRACT", [
    deterministic_violation; no_alloc; no_alloc_candidate; no_alloc_policy;
    no_alloc_transient; no_alloc_unchecked; no_extern_violation;
    no_panic_violation; pure_violation; realtime_mixed; vectorize_failed ];
  "COPY", [ copy_shared ];
  "RUNTIME", [ panic; runtime_error; actor_crashed ];
  "UNUSED", [ unused_binding; unused_import ];
  (* Not compile errors: a failing `assert`, `Check.all` property or test
     body, rendered by the test runners (lib/errors/test_report.ml) through
     the same renderer, so a failed test reads like a diagnostic. *)
  "TEST FAILURE", [ assert_failed; property_failed; test_panicked ];
  "PROGRAM", [
    attribute_no_effect; compiled_unsupported; internal_error; main_and_app;
    redundant_csrf_token; stdlib_internal; unknown_attribute ];
]

(** The category of a code (its slug; an argument after `:` is ignored).
    [None] only for a string that is not a registered code. *)
let category_opt code =
  let slug = slug_of code in
  List.find_map (fun (cat, codes) -> if List.mem slug codes then Some cat else None)
    category_table

(** The category of a code; ["ERROR"] for an unregistered string, so a
    renderer never fails on one. *)
let category code = Option.value (category_opt code) ~default:"ERROR"
