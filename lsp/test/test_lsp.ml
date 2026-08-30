(** Test suite for the March LSP server — the Alcotest registration.

    The ~350 test functions live in focused modules beside this one; this file
    is the runner.  Each module is [open]ed rather than referenced qualified,
    so the registration below still names every test function exactly as it
    did when they all lived in one 7,181-line file — the list is unchanged,
    which is what makes it reviewable.

      [Test_lsp_harness]   shared helpers and module aliases
      [Test_lsp_analysis]  diagnostics, symbols, completions, definitions, hover
      [Test_lsp_actions]   references, rename, signature help, code actions
      [Test_lsp_perf]      performance insights
      [Test_lsp_features]  TIR pipeline, inlay hints, lenses, semantic tokens
      [Test_lsp_refactor]  DAP inline values, deltas, call hierarchy, refactors
      [Test_lsp_html]      the ~H sigil, islands, and their lints
      [Test_lsp_depot]     depot-aware analysis and capability tooling *)

open Test_lsp_analysis
open Test_lsp_actions
open Test_lsp_perf
open Test_lsp_features
open Test_lsp_refactor
open Test_lsp_html
open Test_lsp_depot

(* ------------------------------------------------------------------ *)
(* Runner                                                              *)
(* ------------------------------------------------------------------ *)

let () =
  Alcotest.run "march-lsp" [
    "cross-file", [
      "interface resolves across files", `Quick, test_cross_file_interface_resolves;
      "unknown interface still errors",  `Quick, test_unknown_interface_still_errors;
    ];
    "navigation extras", [
      "go to implementation", `Quick, test_implementation;
      "go to type definition", `Quick, test_type_definition;
      "document highlight", `Quick, test_document_highlight;
      "document highlight read/write kinds", `Quick, test_document_highlight_read_write_kinds;
      "document highlight ~H tag pair", `Quick, test_tag_pair_highlight;
    ];
    "dap inline values", [
      "locals in range reported",            `Quick, test_inline_values_locals_in_range;
      "lookup names and positions",          `Quick, test_inline_values_lookup_names_and_positions;
      "excludes vars below stopped line",    `Quick, test_inline_values_excludes_below_stopped_line;
      "de-dup by variable name",             `Quick, test_inline_values_dedup_by_name;
      "no crash on error buffer",            `Quick, test_inline_values_no_crash_on_error_buffer;
    ];
    "semantic tokens delta", [
      "delta diffs the changed middle", `Quick, test_semantic_tokens_delta_middle;
      "delta handles pure append", `Quick, test_semantic_tokens_delta_append;
      "delta is empty for identical", `Quick, test_semantic_tokens_delta_identical;
    ];
    "call hierarchy", [
      "prepare returns fn under cursor", `Quick, test_call_hierarchy_prepare;
      "incoming calls found", `Quick, test_call_hierarchy_incoming;
      "outgoing calls found", `Quick, test_call_hierarchy_outgoing;
    ];
    "annotation + missing-case fixes", [
      "add missing case has no leading pipe", `Quick, test_add_missing_case_no_leading_pipe;
      "annotation offered for named record", `Quick, test_annotation_for_named_record_return;
      "annotation offered for scalar return", `Quick, test_annotation_offered_for_scalar_return;
    ];
    "~H unclosed tags", [
      "unclosed div/p detected", `Quick, test_html_unclosed_detected;
      "balanced html ok", `Quick, test_html_balanced_no_issue;
      "void elements ok", `Quick, test_html_void_no_issue;
      "self-closing ok", `Quick, test_html_self_closing_no_issue;
      "close quickfix inserts closers", `Quick, test_html_close_quickfix;
    ];
    "~H sigil traversal", [
      "collect_h_sigils: one sigil found with correct content and offset", `Quick, test_h_sigils_collected;
      "islands_in_sigil: finds one island by name",                        `Quick, test_island_parse;
      "islands_in_sigil: name span lands on correct line and text",        `Quick, test_island_name_span;
    ];
    "island component validation", [
      "known module lacking create/render emits html/unknown-island", `Quick, test_island_known_but_invalid_flagged;
      "valid island with create+render is not flagged",               `Quick, test_island_valid_not_flagged;
    ];
    "island component name completion", [
      "Counter offered after name=' in ~H sigil", `Quick, test_island_name_completion;
    ];
    "~H unknown HTML tag lint", [
      "misspelled tag <dvi> flagged with did-you-mean div", `Quick, test_html_unknown_tag;
      "custom element my-widget not flagged",                `Quick, test_html_custom_element_not_flagged;
    ];
    "~H duplicate attribute lint", [
      "duplicate type attr flagged",              `Quick, test_html_duplicate_attr;
      "distinct attrs not flagged",               `Quick, test_html_no_duplicate_attr_for_distinct;
    ];
    "~H void/self-closing misuse lint", [
      "void close-tag </br> flagged as html/void-with-children", `Quick, test_html_void_with_children;
      "self-closing non-void <div/> flagged as html/self-closing-nonvoid", `Quick, test_html_self_closing_nonvoid;
      "void self-closing <br/> not flagged",  `Quick, test_html_void_self_closing_ok;
      "normal pair <div></div> not flagged",  `Quick, test_html_normal_pair_ok;
    ];
    "~H unsafe interpolation lint", [
      "interpolation inside <script> flagged as html/unsafe-interpolation", `Quick, test_html_unsafe_interpolation;
      "interpolation inside <style> flagged as html/unsafe-interpolation",  `Quick, test_html_unsafe_interpolation_style;
      "interpolation in normal text NOT flagged",                            `Quick, test_html_safe_interpolation_in_text;
    ];
    "introduce parameter object", [
      "fn with 2+ annotated params bundleable", `Quick, test_bundleable_fn_detected;
      "single param not bundleable", `Quick, test_single_param_not_bundleable;
      "unannotated params not bundleable", `Quick, test_unannotated_params_not_bundleable;
    ];
    "extract closure captures to record", [
      "offered for 2+ closures sharing a capture set", `Quick, test_extract_captures_action;
      "not offered for a single closure", `Quick, test_no_extract_captures_for_single_site;
      "not offered when only globals captured", `Quick, test_no_extract_captures_for_globals_only;
    ];
    "project diagnostics", [
      "per-file diagnostics across the workspace", `Quick, test_project_diagnostics;
    ];
    "cap no_panic diagnostics", [
      "a nested contracted name is reported exactly when `panic_` is", `Quick,
        test_lsp_no_panic_contracted_matches_panic;
      "a safe nested cap no_panic module is silent", `Quick,
        test_lsp_no_panic_clean_module_silent;
    ];
    "refactor extras", [
      "generate doc comment", `Quick, test_generate_doc_comment;
      "no doc comment when documented", `Quick, test_no_doc_comment_when_documented;
      "inline function", `Quick, test_inline_function;
      "no inline for recursive fn", `Quick, test_no_inline_recursive_function;
      "auto-alias repeated prefix", `Quick, test_auto_alias_repeated_prefix;
      "no auto-alias below threshold", `Quick, test_no_auto_alias_below_threshold;
      "remove unused function", `Quick, test_remove_unused_function;
      "no remove for used function", `Quick, test_no_remove_used_function;
      "remove unreachable code", `Quick, test_remove_unreachable_code;
    ];
    "auto-import", [
      "prefix before cursor", `Quick, test_prefix_at;
      "qualified access has no bare prefix", `Quick, test_prefix_at_qualified_is_empty;
      "offers un-imported symbol", `Quick, test_auto_import_offers_unimported;
      "skips already-imported symbol", `Quick, test_auto_import_skips_imported;
      "short prefix offers nothing", `Quick, test_auto_import_short_prefix_empty;
      "merge into existing use list", `Quick, test_import_edit_merge;
      "insert after existing import", `Quick, test_import_edit_insert_after_existing;
      "insert when no imports", `Quick, test_import_edit_insert_no_imports;
    ];
    "inlay config toggle", [
      "perf-annotations setting parses", `Quick, test_config_perf_toggle_parse;
    ];
    "selection + linked editing", [
      "selection range widens outward", `Quick, test_selection_range_widens_outward;
      "selection range empty off token", `Quick, test_selection_range_empty_off_token;
      "linked editing links all occurrences", `Quick, test_linked_editing_ranges;
      "linked editing links ~H open+close tag pair", `Quick, test_tag_pair_linked_edit;
    ];
    "semantic tokens", [
      "linear modifier on `linear let` binding", `Quick, test_semantic_tokens_linear_modifier;
      "affine modifier on `affine let` binding", `Quick, test_semantic_tokens_affine_modifier;
      "linear modifier follows always_linear type", `Quick, test_semantic_tokens_always_linear_type;
      "plain bindings carry no ownership modifier", `Quick, test_semantic_tokens_plain_binding_not_linear;
      "constructor use site fidelity", `Quick, test_semantic_tokens_use_site_ctor_fidelity;
    ];
    "fbip inlay hints", [
      "reuse hint on single-use allocation", `Quick, test_inlay_reuse_hint;
      "no reuse hint on scalar binding", `Quick, test_inlay_no_reuse_for_scalar;
      "send-copy surfaced as copied inlay", `Quick, test_inlay_copy_hint_wiring;
    ];
    "parameter-name inlay hints", [
      "two-arg call emits both name: hints", `Quick, test_param_hint_two_arg_call;
      "hints positioned at arg start", `Quick, test_param_hint_positions_at_arg_start;
      "redundant identifier arg suppressed", `Quick, test_param_hint_suppress_redundant_identifier;
      "single-arg call suppressed", `Quick, test_param_hint_suppress_single_arg;
      "toggled off removes hints", `Quick, test_param_hint_toggle_off;
      "hints on call nested in if branch", `Quick, test_param_hint_nested_in_cond;
      "param-name map cached on record", `Quick, test_param_hint_map_cached;
      "config toggle parse", `Quick, test_param_hint_config_toggle_parse;
    ];
    "completion depth", [
      "in-scope locals offered and ranked first", `Quick, test_completion_scoped_locals;
    ];
    "stdlib name collision", [
      "user symbol wins over stdlib name", `Quick, test_user_symbol_wins_over_stdlib_name;
    ];
    "utf16 position encoding", [
      "hover resolves identifier on a unicode line", `Quick, test_hover_after_unicode;
    ];
    "stdlib cache", [
      "stdlib parse/desugar is memoized", `Quick, test_stdlib_cache_memoizes;
    ];
    "error-resilient analysis", [
      "broken edit retains last good maps", `Quick, test_resilient_keeps_last_good;
    ];
    "document version guard", [
      "stale background results are rejected", `Quick, test_version_guard;
    ];
    "query facade", [
      "hover returns a transport-agnostic record", `Quick, test_query_hover_record;
    ];
    "symbol identity", [
      "shadowed locals resolve to distinct binders", `Quick, test_scoped_shadow_distinct;
      "rename respects shadowing", `Quick, test_rename_respects_shadowing;
      "prepareRename validates the target", `Quick, test_prepare_rename_validates;
    ];
    "context-aware completion", [
      "dot-completion offers record fields", `Quick, test_dot_completion_record_fields;
    ];
    "workspace symbols", [
      "index + query across files", `Quick, test_workspace_index_cross_file;
      "cross-file references", `Quick, test_workspace_cross_file_references;
    ];
    "position", [
      Alcotest.test_case "span_to_range single-line"    `Quick test_span_to_range_single_line;
      Alcotest.test_case "span_to_range multi-line"     `Quick test_span_to_range_multi_line;
      Alcotest.test_case "span_contains inside"         `Quick test_span_contains_inside;
      Alcotest.test_case "span_contains outside"        `Quick test_span_contains_outside;
      Alcotest.test_case "span_contains multi-line"     `Quick test_span_contains_multi_line;
      Alcotest.test_case "span_smaller"                 `Quick test_span_smaller;
      Alcotest.test_case "lsp_pos round-trip"           `Quick test_lsp_pos_round_trip;
    ];
    "diagnostics", [
      Alcotest.test_case "valid code: zero diagnostics"          `Quick test_analyse_valid_no_diagnostics;
      Alcotest.test_case "empty module: zero diagnostics"        `Quick test_analyse_empty_module;
      Alcotest.test_case "empty string: no crash"                `Quick test_analyse_empty_string;
      Alcotest.test_case "type error → diagnostic"               `Quick test_analyse_type_error_produces_diagnostic;
      Alcotest.test_case "parse error → diagnostic"              `Quick test_analyse_parse_error_produces_diagnostic;
      Alcotest.test_case "multiple errors all reported"          `Quick test_analyse_multiple_errors_all_reported;
      Alcotest.test_case "desugar error → positioned diagnostic" `Quick test_analyse_desugar_error_produces_diagnostic;
      Alcotest.test_case "warning severity"                      `Quick test_analyse_warning_severity;
      Alcotest.test_case "notes appended to message"             `Quick test_analyse_notes_appended_to_message;
      Alcotest.test_case "type mismatch has relatedInformation"  `Quick test_analyse_related_information_on_type_mismatch;
      Alcotest.test_case "arity mismatch has relatedInformation" `Quick test_analyse_arity_mismatch_has_related_information;
      Alcotest.test_case "diagnostics from user file"            `Quick test_multiple_errors_all_from_user_file;
      Alcotest.test_case "src field matches input"               `Quick test_analyse_src_field_matches_input;
      Alcotest.test_case "prelude collision → diagnostic"         `Quick test_analyse_prelude_collision_produces_diagnostic;
      Alcotest.test_case "safe builtin shadow → no diagnostic"    `Quick test_analyse_safe_shadow_no_collision_diagnostic;
      Alcotest.test_case "`print` no longer collides (println calls print_line)" `Quick test_analyse_print_no_longer_collides;
    ];
    "document-symbols", [
      Alcotest.test_case "fn name in symbols"            `Quick test_document_symbols_fn;
      Alcotest.test_case "type + ctors in symbols"       `Quick test_document_symbols_type;
      Alcotest.test_case "interface in symbols"          `Quick test_document_symbols_interface;
      Alcotest.test_case "multiple decls in symbols"     `Quick test_document_symbols_multiple_decls;
      Alcotest.test_case "type symbol has Class kind"    `Quick test_document_symbols_kind_for_type;
    ];
    "completions", [
      Alcotest.test_case "keywords in completions"          `Quick test_completions_include_keywords;
      Alcotest.test_case "in-scope names in completions"    `Quick test_completions_include_in_scope_names;
      Alcotest.test_case "type ctors in completions"        `Quick test_completions_include_type_constructors;
      Alcotest.test_case "data ctors in completions"        `Quick test_completions_include_data_constructors;
      Alcotest.test_case "interfaces in completions"        `Quick test_completions_include_interfaces;
      Alcotest.test_case "underscore vars excluded"         `Quick test_completions_no_leading_underscore_vars;
    ];
    "goto-definition", [
      Alcotest.test_case "let binding resolves"                 `Quick test_definition_at_let_binding;
      Alcotest.test_case "no definition for literal"            `Quick test_definition_at_outside_any_use;
      Alcotest.test_case "function name reference resolves"     `Quick test_definition_at_function_name_reference;
      Alcotest.test_case "constructor expression resolves"      `Quick test_definition_at_constructor_expression;
      Alcotest.test_case "constructor pattern resolves"         `Quick test_definition_at_constructor_pattern;
      Alcotest.test_case "definition-site fallback"             `Quick test_definition_at_type_definition_site;
      Alcotest.test_case "type name in decl resolves"           `Quick test_definition_at_type_name;
      Alcotest.test_case "island component name resolves"       `Quick test_island_goto_def;
    ];
    "hover-types", [
      Alcotest.test_case "no type at module keyword"      `Quick test_type_at_no_position;
      Alcotest.test_case "int literal type"               `Quick test_type_at_int_literal;
      Alcotest.test_case "some type found in valid module" `Quick test_type_at_returns_string;
    ];
    "inlay-hints", [
      Alcotest.test_case "hints for valid code"           `Quick test_inlay_hints_nonempty_for_valid_code;
      Alcotest.test_case "no hints outside file range"    `Quick test_inlay_hints_empty_for_wrong_range;
      Alcotest.test_case "hint label starts with ': '"    `Quick test_inlay_hint_has_colon_prefix;
    ];
    "march-specific", [
      Alcotest.test_case "find_impls_of: present"             `Quick test_find_impls_of_present;
      Alcotest.test_case "find_impls_of: absent"              `Quick test_find_impls_of_absent;
      Alcotest.test_case "find_impls_of: unknown interface"   `Quick test_find_impls_of_unknown_interface;
      Alcotest.test_case "actor info at actor name"           `Quick test_actor_info_at_actor_name;
      Alcotest.test_case "actor info state fields"            `Quick test_actor_info_state_fields;
      Alcotest.test_case "no actor info on fn"                `Quick test_actor_info_not_at_random_position;
      Alcotest.test_case "pipe chain: no type errors"         `Quick test_pipe_chain_parsed_without_errors;
      Alcotest.test_case "pipe chain: type available"         `Quick test_pipe_chain_type_available;
      Alcotest.test_case "derive: no crash"                   `Quick test_derive_no_false_errors;
      Alcotest.test_case "linear binding: no crash"           `Quick test_linear_consumption_map_built;
    ];
    "error-recovery", [
      Alcotest.test_case "empty file: no crash"               `Quick test_empty_file_no_crash;
      Alcotest.test_case "partial source: no crash"           `Quick test_partial_source_no_crash;
      Alcotest.test_case "bad grammar: no crash"              `Quick test_malformed_grammar_no_crash;
      Alcotest.test_case "comment-only source: no crash"      `Quick test_source_with_only_comment_no_crash;
      Alcotest.test_case "missing expression: no crash"       `Quick test_missing_expression_no_crash;
      Alcotest.test_case "lexer error: diagnostic produced"   `Quick test_lexer_error_produces_diagnostic;
      Alcotest.test_case "unterminated string: diagnostic"    `Quick test_unterminated_string_is_diagnostic;
    ];
    "analysis-struct", [
      Alcotest.test_case "empty module: struct fields"        `Quick test_empty_module_fields_empty;
      Alcotest.test_case "type_map populated for valid code"  `Quick test_analysis_has_type_map;
      Alcotest.test_case "def_map contains fn name"          `Quick test_analysis_has_def_map;
    ];
    "doc strings", [
      "documented fn",          `Quick, test_doc_for_documented_fn;
      "undocumented fn",        `Quick, test_doc_for_undocumented_fn;
      "unknown name",           `Quick, test_doc_for_unknown_name;
      "at call-site cursor",    `Quick, test_doc_name_at_cursor;
      "triple-quoted",          `Quick, test_doc_triple_quoted;
      "hover has both type and doc", `Quick, test_hover_includes_doc;
      "stdlib fn doc on hover",      `Quick, test_doc_stdlib_hover;
    ];
    "find references", [
      "literal has no refs",       `Quick, test_references_empty_for_literal;
      "finds multiple uses",        `Quick, test_references_finds_uses;
      "include_declaration flag",   `Quick, test_references_include_declaration;
      "local variable",             `Quick, test_references_local_variable;
      "no cross-contamination",     `Quick, test_references_no_cross_contamination;
    ];
    "rename symbol", [
      "literal produces no edits",    `Quick, test_rename_no_edits_for_literal;
      "def + uses all renamed",        `Quick, test_rename_produces_edits_for_def_and_uses;
      "new name appears in all edits", `Quick, test_rename_new_name_in_edits;
      "other names untouched",         `Quick, test_rename_does_not_rename_other_names;
    ];
    "signature help", [
      "none outside call",       `Quick, test_sig_help_none_outside_call;
      "single param",            `Quick, test_sig_help_single_param;
      "active param index",      `Quick, test_sig_help_active_param_index;
      "param labels",            `Quick, test_sig_help_param_labels;
      "non-resolvable callee",   `Quick, test_sig_help_not_a_known_function;
    ];
    "code actions: make-linear", [
      "offered for single-use binding",  `Quick, test_make_linear_offered_for_single_use;
      "not offered for multi-use",        `Quick, test_make_linear_not_offered_for_multi_use;
      "edit inserts 'linear ' keyword",   `Quick, test_make_linear_edit_inserts_keyword;
    ];
    "code actions: exhaustion quickfix", [
      "absent for exhaustive match",    `Quick, test_exhaustion_quickfix_absent_for_exhaustive_match;
      "offered for incomplete match",   `Quick, test_exhaustion_quickfix_offered_for_incomplete_match;
      "edit contains missing arm",      `Quick, test_exhaustion_quickfix_edit_contains_missing_arm;
      "edit inserts before end",        `Quick, test_exhaustion_quickfix_edit_inserts_before_end;
    ];
    "phase2: enhanced exhaustive match", [
      "bulk action offered for multiple missing", `Quick, test_exhaustion_all_cases_action_offered;
      "bulk edit covers all missing cases",       `Quick, test_exhaustion_all_cases_edit_covers_all;
      "no bulk action when only one missing",     `Quick, test_exhaustion_single_missing_no_bulk;
    ];
    "phase2: quickfix framework", [
      "registry has known codes",                 `Quick, test_fix_registry_has_known_codes;
      "registry returns empty for unknown code",  `Quick, test_apply_fix_registry_empty_for_unknown_code;
    ];
    "phase2: dead code detection", [
      "unused private fn: warning emitted",       `Quick, test_unused_private_fn_warning;
      "used private fn: no warning",              `Quick, test_used_private_fn_no_warning;
      "unreachable after panic: warning emitted", `Quick, test_unreachable_code_after_panic_warning;
      "unused_fns field populated correctly",     `Quick, test_unused_fns_field_populated;
    ];
    "P1.8: assign to _", [
      "action offered for unused binding",      `Quick, test_assign_to_underscore_offered;
      "edit replaces name with _",              `Quick, test_assign_to_underscore_edit_replaces_name;
    ];
    "P2.10: remove unused import", [
      "registry has unused_import code",        `Quick, test_unused_import_diagnostic_has_code;
      "action offered for unused import",       `Quick, test_remove_import_action_whole_line;
      "edit deletes the import line",           `Quick, test_remove_import_edit_deletes_line;
    ];
    "P3.4: wrap/remove inspect", [
      "wrap with inspect offered",              `Quick, test_wrap_with_inspect_offered;
      "wrap edit inserts inspect(",             `Quick, test_wrap_with_inspect_edit_adds_inspect;
      "remove inspect offered",                 `Quick, test_remove_inspect_offered;
      "remove inspect edit unwraps to inner",   `Quick, test_remove_inspect_edit_unwraps;
    ];
    "p1.1: typed match stubs", [
      "ctor with fields → typed stub",  `Quick, test_typed_match_stub_with_fields;
      "nullary ctor → bare stub",       `Quick, test_typed_match_stub_nullary;
    ];
    "p1.7: fn return type annotation", [
      "AnnFnReturn site created",       `Quick, test_fn_return_annotation_site_created;
      "action offered on fn name",      `Quick, test_fn_return_annotation_action_offered;
      "edit inserts ': T' colon form",  `Quick, test_fn_return_annotation_edit_inserts_colon;
    ];
    "named-record name recovery", [
      "hover renders record name",      `Quick, test_named_record_hover_shows_name;
      "return annotation uses name",    `Quick, test_named_record_return_annotation_uses_name;
    ];
    "p1.7: fn param type annotation", [
      "AnnFnParam site created",        `Quick, test_fn_param_annotation_site_created;
      "action offered on param",        `Quick, test_fn_param_annotation_action_offered;
    ];
    "p1.7: batch annotation", [
      "offered for 2+ bindings",        `Quick, test_batch_annotation_offered_for_multiple_bindings;
      "not offered for single binding", `Quick, test_batch_annotation_not_offered_for_single_binding;
    ];
    "code actions: naming convention (P2.8)", [
      "camelCase fn detected",                    `Quick, test_naming_violation_camel_fn_detected;
      "suggested name is snake_case",             `Quick, test_naming_violation_suggested_name;
      "detects fn inside nested mod",             `Quick, test_naming_violation_deeply_nested_detected;
      "no violation for good snake_case fn",      `Quick, test_naming_violation_no_violation_for_snake_fn;
      "rename action offered for camelCase fn",   `Quick, test_naming_action_offered_for_camel_fn;
      "rename edit uses snake_case name",         `Quick, test_naming_action_edit_uses_snake_case;
      "no action for already-snake fn",           `Quick, test_naming_action_absent_for_snake_fn;
    ];
    "code actions: De Morgan (P3.10)", [
      "!(a && b) detected",                       `Quick, test_demorgan_not_and_detected;
      "!(a || b) detected",                       `Quick, test_demorgan_not_or_detected;
      "!a && !b detected",                        `Quick, test_demorgan_pair_negs_detected;
      "action offered for !(a && b)",             `Quick, test_demorgan_action_offered_for_not_and;
      "!(a && b) rewrite contains '||'",          `Quick, test_demorgan_action_rewrite_not_and;
      "!a && !b rewrite is !(... || ...)",        `Quick, test_demorgan_action_rewrite_pair_negs;
    ];
    "perf insights: tail-call optimization", [
      "non-tail recursive call detected",         `Quick, test_perf_non_tail_call_detected;
      "tail-recursive call not flagged",          `Quick, test_perf_tail_call_not_flagged;
      "non-tail inside constructor detected",     `Quick, test_perf_non_tail_inside_constructor;
      "ctor-wrapped advice is not accumulator",   `Quick, test_perf_constructor_wrapped_advice_is_not_accumulator;
      "non-tail produces warning diagnostic",     `Quick, test_perf_non_tail_produces_warning_diagnostic;
      "non-recursive call not flagged",           `Quick, test_perf_non_tail_not_flagged_for_non_recursive;
    ];
    "perf insights: closure captures", [
      "large closure (4 captures) detected",      `Quick, test_perf_large_closure_detected;
      "small closure (2 captures) not flagged",   `Quick, test_perf_small_closure_not_flagged;
      "closure_capture hint in diagnostics",      `Quick, test_perf_closure_capture_hint_in_diagnostics;
      "closure count is accurate",                `Quick, test_perf_closure_count_accurate;
      "captures exclude top-level functions",     `Quick, test_closure_capture_excludes_globals;
      "closures inside ~H sigil are seen",         `Quick, test_closure_capture_inside_sigil;
      "closures inside match do (ECond) are seen", `Quick, test_closure_capture_inside_cond;
    ];
    "perf insights: actor send copy", [
      "actor send analysis does not crash",           `Quick, test_perf_actor_send_copy_detected;
      "actor send completes without exception",       `Quick, test_perf_actor_send_copy_in_diagnostics_when_type_known;
    ];
    "perf insights: parallelizable map/filter", [
      "pure List.map flagged as pmap",                `Quick, test_perf_parallelizable_pure_map_flagged;
      "pure List.filter flagged as pfilter",          `Quick, test_perf_parallelizable_pure_filter_flagged;
      "impure List.map not flagged",                  `Quick, test_perf_parallelizable_impure_map_not_flagged;
      "List.fold_left never flagged",                 `Quick, test_perf_parallelizable_fold_not_flagged;
      "parallelizable hint in diagnostics",           `Quick, test_perf_parallelizable_hint_in_diagnostics;
      "convert-to-pmap code action",                  `Quick, test_perf_parallelizable_code_action;
    ];
    "document symbol scope", [
      "symbols are scoped to the open file",           `Quick, test_document_symbols_scoped_to_the_file;
    ];
    "semantic tokens document scope", [
      "tokens stay inside the open document",          `Quick, test_semantic_tokens_stay_inside_the_document;
    ];
    "suggest-postcondition code action", [
      "offered on a declared return type",             `Quick, test_post_action_offered_on_declared_return;
      "absent without a return type",                  `Quick, test_post_action_absent_without_a_return_type;
      "absent when the return is already refined",     `Quick, test_post_action_absent_when_return_already_refined;
    ];
    "suggest-refinement code action", [
      "offered on a function with an annotated param", `Quick, test_refine_action_offered_on_annotated_param;
      "absent when every param is already refined",    `Quick, test_refine_action_absent_when_all_params_refined;
    ];
    "perf insights phase 2: indirect calls + recursive alloc", [
      "calling a parameter is indirect",              `Quick, test_perf_indirect_call_on_param;
      "top-level call is not indirect",               `Quick, test_perf_direct_call_not_indirect;
      "allocation in recursive arm flagged",          `Quick, test_perf_recursive_alloc_in_arm;
      "allocation in non-recursive fn not flagged",   `Quick, test_perf_alloc_not_recursive_not_flagged;
    ];
    "perf insights: hover integration", [
      "perf_insight_at returns message at call site", `Quick, test_perf_insight_at_returns_message_at_call_site;
    ];
    "phase2+: ast-driven code actions", [
      "introduce pipe",            `Quick, test_introduce_pipe_offered;
      "remove pipe",               `Quick, test_remove_pipe_offered;
      "extract variable",          `Quick, test_extract_variable_offered;
      "inline variable",           `Quick, test_inline_variable_offered;
      "collapse function capture", `Quick, test_collapse_capture_offered;
      "expand function capture",   `Quick, test_expand_capture_offered;
      "typed hole fill (variant)", `Quick, test_hole_fill_variant;
      "typed hole fill (bool)",    `Quick, test_hole_fill_bool;
      "interface impl scaffold",   `Quick, test_impl_scaffold_offered;
      "auto-import",               `Quick, test_auto_import_offered;
      "actor boilerplate",         `Quick, test_actor_boilerplate_offered;
      "session scaffolding",       `Quick, test_session_scaffold_offered;
      "convert if to match",       `Quick, test_if_to_match_offered;
      "linear consumption audit",  `Quick, test_linear_audit_offered;
      "batch fix-all",             `Quick, test_batch_fix_all_offered;
      "no crash on malformed src", `Quick, test_ast_actions_no_crash_on_error;
      "destruct / case-split",     `Quick, test_destruct_offered;
      "destruct needs known type", `Quick, test_destruct_not_offered_when_type_unknown;
      "extract function",          `Quick, test_extract_function_offered;
      "organize imports",          `Quick, test_organize_imports_offered;
      "organize imports: no-op when sorted", `Quick, test_organize_imports_not_offered_when_sorted;
    ];
    "perf insights phase 3: TIR pipeline", [
      "run_tir_pass does not crash",            `Quick, test_tir_pass_does_not_crash;
      "consumed hint on an owning call",        `Quick, test_consume_hint_on_owning_call;
      "no consumed hint on a scalar arg",       `Quick, test_no_consume_hint_on_scalar_arg;
      "no consumed hint on a temporary",        `Quick, test_no_consume_hint_on_temporary_arg;
      "run_tir_pass is idempotent",             `Quick, test_tir_pass_idempotent;
      "TIR pass skipped when source has errors",`Quick, test_tir_pass_skipped_on_error;
      "HOF indirect-call insight",              `Quick, test_tir_indirect_call_insight;
      "tir_fn_insights field populated",        `Quick, test_tir_fn_insights_field_populated;
      "code lens consistent with TIR insights", `Quick, test_code_lens_consistent_with_tir_insights;
    ];
    "tier4: ~H interpolation intelligence", [
      "type/def/completion inside ${...}",                   `Quick, test_hover_in_h_interp;
      "(a) attr-value: url:String in href=${url}",           `Quick, test_h_interp_attr_value;
      "(b) field access: u.name resolves to String",         `Quick, test_h_interp_field_access;
      "(c) let-bound local: def jumps to let binding",       `Quick, test_h_interp_let_binding;
      "(d) multiple interps on one line: Int vs String",     `Quick, test_h_interp_multiple_on_one_line;
      "(e) triple-quoted ~H: hover resolves same way",       `Quick, test_h_interp_triple_quoted;
      "task2: type-error diag range on interpolation line",  `Quick, test_h_interp_diagnostic_position;
      "task3: island props=${e} hover/def resolves",         `Quick, test_h_island_props_interp;
    ];
    "runnable code lenses", [
      "test block yields run+debug lenses",   `Quick, test_action_lens_for_test_block;
      "fn main yields run+debug lenses",       `Quick, test_action_lens_for_main;
      "no runnables -> no action lenses",      `Quick, test_action_lens_absent_without_runnables;
      "action lenses survive TIR pass",        `Quick, test_action_lens_survive_tir_pass;
      "debug command echoes (non-blocking)",   `Quick, test_resolve_debug_command_echoes;
      "run command builds forge shell",        `Quick, test_resolve_run_command_builds_forge_shell;
      "unknown command resolves gracefully",   `Quick, test_resolve_unknown_command;
    ];
    "~H element folding ranges", [
      "multi-line ~H element produces fold range", `Quick, test_h_element_folding;
      "import run folds as one range",   `Quick, test_import_run_folds;
      "cap run folds as one range",      `Quick, test_cap_run_folds;
      "runs do not span other decls",    `Quick, test_runs_do_not_span_other_decls;
      "lone import does not fold",       `Quick, test_lone_import_does_not_fold;
      "single-line ~H does not crash",             `Quick, test_h_element_no_fold_for_single_line;
    ];
    "~H auto-close on typing >", [
      "autoclose_tag_at inserts </div> after <div>", `Quick, test_autoclose_tag;
      "autoclose_tag_at returns None for void element <br>", `Quick, test_autoclose_void_tag;
      "autoclose with ${} interp containing '<' closes outer tag", `Quick, test_autoclose_tag_with_interpolation_lt;
    ];
    "~H duplicate attr lint: interpolation edge cases", [
      "no false dup-attr when attr value contains ${} with same-named key", `Quick, test_dup_attr_no_false_positive_with_interp_in_quoted_val;
    ];
    "~H island: '>' in attribute value", [
      "island name found even when data attr value contains '>'", `Quick, test_island_gt_in_attr_value;
    ];
    "~H sigil exact-case match", [
      "lowercase ~h sigil not collected as HTML sigil", `Quick, test_lowercase_h_sigil_not_collected;
    ];
    "depot: phase B column intelligence", [
      "column completion in where_eq string arg",     `Quick, test_depot_column_completion;
      "column completion: no dilution with keywords", `Quick, test_depot_column_completion_no_dilution;
      "typo'd column emits depot/unknown-column",    `Quick, test_depot_unknown_column;
      "known column not flagged",                    `Quick, test_depot_known_column_not_flagged;
      "unresolvable table not flagged (conservative)",`Quick, test_depot_unresolved_schema_not_flagged;
      "hover on column string shows field type",      `Quick, test_depot_col_hover;
      "go-to-def on column string finds schema field",`Quick, test_depot_col_def;
      "table name completion in from_table arg",      `Quick, test_depot_table_completion;
      "unknown table flagged",                        `Quick, test_depot_unknown_table;
    ];
    "depot: phase C migration intelligence", [
      "migration_ops extracts CreateTable + AlterTable",  `Quick, test_depot_migration_ops;
      "schema-drift flagged when mig has extra column",   `Quick, test_depot_schema_drift;
      "no drift when schema and migration align",          `Quick, test_depot_no_drift_when_aligned;
      "valid FK column not flagged",                      `Quick, test_depot_fk_column_valid;
      "invalid FK column flagged",                        `Quick, test_depot_fk_column_invalid;
    ];
    "depot: phase A foundation", [
      "schema extraction from Schema.define",      `Quick, test_depot_schema_extract;
      "depot_schemas field populated",             `Quick, test_depot_schemas_field;
      "query->schema resolution + col_occ",        `Quick, test_query_schema_resolution;
      "query->schema via from(schema_fn())",        `Quick, test_query_schema_resolution_from_fn;
      "depot_source_decls retained in analysis",   `Quick, test_imported_decls_retained;
    ];
    "capability tooling (phase 3f)", [
      "proof cap defs registered",                 `Quick, test_proof_cap_defs_registered;
      "proof cap go-to-def resolves declaration",  `Quick, test_proof_cap_goto_def;
      "proof cap find-refs finds type annotations", `Quick, test_proof_cap_find_refs;
      "cap inlay hint emitted for builtin in needs module", `Quick, test_cap_inlay_hints;
    ];
  ]
