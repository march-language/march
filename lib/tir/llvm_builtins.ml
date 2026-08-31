(** One declarative table replacing llvm_emit.ml's four historically
    unsynchronized builtin structures: [is_builtin_fn] (name-recognition
    list), [builtin_ret_ty] (name → TIR return type override),
    [mangle_extern] (March name → C runtime symbol), and the hand-written
    LLVM preamble `declare` blob (~400 lines). Adding a builtin used to
    require touching all four by hand; missing one was the source of >=5
    "missing builtin" fix commits (see specs/analysis/2026-07-01-pipeline-
    deep-review.md §5). This module makes one table entry produce all four
    facts.

    Wave 3 Task 4 (chunk 2), HAZARD H2: the generated preamble must
    reproduce llvm_emit.ml's former hand-written declare text
    BYTE-IDENTICALLY (same order, same per-line whitespace/alignment). To
    guarantee that without risking a reformatting bug, [declare_sig] /
    [runtime_only_declares] entries hold each declare line's EXACT historical
    text (copied verbatim, not synthesized from ret_ty+name+params — the
    original blob's column alignment is hand-tuned and inconsistent, e.g.
    "declare i64  @foo" vs "declare i64    @bar" within the same block, so a
    generic formatter would not reproduce it). [emit_preamble] walks a fixed
    per-target list of [preamble_item]s (section-comment / declare-lookup /
    blank-line markers) that mirrors the original blob structure 1:1 and
    resolves each [PDeclare] marker's text from this table or from
    [runtime_only_declares]. See test/test_codegen.ml's preamble byte-diff
    test (golden = the deleted blob, kept verbatim in a comment) — that test
    is the enforcement mechanism for this hazard, not a promise this module
    keeps by construction alone.

    Membership drift (Step 3): builtins present in SOME of the four
    original structures but not all are preserved EXACTLY as before via the
    optional fields below ([c_name], [ret_ty], [declare_sig] are all
    [option]; [in_is_builtin] is an explicit bool because [is_builtin_fn]
    never returned an option). The drift itself — 38 names
    ([record_keys], [chan_new], [ws_recv], [stdlib_gzip_encode], etc.) have a
    [ret_ty]/[c_name]/preamble declare but are NOT in [is_builtin_fn]'s
    recognition set, so [is_leaf_callee] treats calls to them as non-leaf and
    forces an unnecessary reduction check; a further 7 [march_compare_*]/
    [march_hash_*] names have [ret_ty]/preamble but no [mangle_extern] case
    (they are already their own C symbol) and are also absent from
    [is_builtin_fn] — is filed in specs/todos.md (full name lists) rather
    than repaired here (repairing membership is a behavior change; this
    task is refactor-only). *)

(* ── Table schema ────────────────────────────────────────────────────── *)

(** One row per March builtin name, in the LLVM preamble's declaration
    order (native target, non-REPL) where the builtin has a preamble
    declare; builtins with no preamble presence at all (arithmetic/
    comparison operators emitted as native LLVM instructions, [int_and] et
    al. emitted as native bitwise instructions, [task_spawn]/[task_await]
    etc. and [pmap_threshold]/[get_work_pool]/[remote_ref_hashes] which are
    synthesized or constant-folded by dedicated EApp match arms in
    llvm_emit.ml rather than dispatched through [mangle_extern]) are
    appended at the end in their original [is_builtin_fn]-list order. *)
type builtin = {
  march_name    : string;
  (** C runtime symbol this name mangles to. [None] means the name is not
      listed in the historical [mangle_extern] match and falls through to
      that function's identity default (`| other -> other`) — see the
      membership-drift note above; this is DATA (today's exact behavior),
      not a bug to fix here. *)
  c_name        : string option;
  (** TIR return type override. [None] means [builtin_ret_ty] had no case
      for this name (ordinary typecheck-derived type info is used instead). *)
  ret_ty        : Tir.ty option;
  (** Whether this name was a member of the historical [is_builtin_fn]
      list (used by [atom_is_builtin], [is_leaf_callee], and the emit-arm
      shadow guards). Not an [option]: [is_builtin_fn] was a plain
      [bool]-returning predicate with no notion of absence. *)
  in_is_builtin : bool;
  (** The exact historical `declare <ty> @<c_name>(...)` text for this
      builtin's preamble entry, when it has one. Several March names alias
      the same C symbol (e.g. [string_length] and [string_byte_length] both
      mangle to [march_string_byte_length]) and so carry an IDENTICAL
      [declare_sig] — that redundancy is harmless because [emit_preamble]
      resolves each preamble position by C-symbol lookup (one [PDeclare]
      marker per symbol per section, matching the original blob), never by
      iterating every row; it does not care which alias row the text came
      from. [None] means this name has no preamble presence at all (see the
      module doc's "appended at the end" note). *)
  declare_sig   : string option;
}

(* Reserved constructor-tag ABI shared with runtime/march_runtime.h.

   Ordinary variants use per-type tags below [ordinary_ctor_tag_limit]. Actor
   messages and same-short-name collision variants have dedicated, bounded
   global ranges. Runtime-originated monitor values live in a final reserved
   range that none of those allocators may enter; [Llvm_toplevel.build_ctor_info]
   enforces every boundary when it assigns tags. Keep these values in sync with
   MARCH_*_TAG in march_runtime.h. *)
let ordinary_ctor_tag_limit = 0x0100_0000
let actor_message_tag_base = 0x0100_0000
let actor_message_tag_limit = 0x0200_0000
let collision_tag_base = 0x0200_0000
let collision_tag_limit = 0x0300_0000

let monitor_down_tag = 0x7f00_0000
let monitor_reason_normal_tag = 0x7f00_0001
let monitor_reason_killed_tag = 0x7f00_0002
let monitor_reason_crash_tag = 0x7f00_0003

let builtins : builtin list = [
  { march_name = "print"; c_name = Some "march_print"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare void @march_print(ptr %s)" };
  { march_name = "panic"; c_name = Some "march_panic"; ret_ty = Some Tir.TUnit;
    in_is_builtin = false; declare_sig = Some "declare void @march_panic(ptr %s)" };
  { march_name = "panic_"; c_name = Some "march_panic_ext"; ret_ty = Some (Tir.TPtr Tir.TUnit);
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_panic_ext(ptr %s)" };
  { march_name = "unreachable_"; c_name = Some "march_panic_ext"; ret_ty = Some (Tir.TPtr Tir.TUnit);
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_panic_ext(ptr %s)" };
  { march_name = "todo_"; c_name = Some "march_todo_ext"; ret_ty = Some (Tir.TPtr Tir.TUnit);
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_todo_ext(ptr %s)" };
  (* Structured cleanup: try_finally(action, cleanup) runs action(), then
     cleanup() (even if action panicked), then re-raises action's panic.
     Returns the action's value at the polymorphic type `a` DIRECTLY, so
     ret_ty is the erased TVar "_" (the record_put precedent): the call site
     reads a uniform ptr and the consumer conditionally untags. A concrete
     scalar here (e.g. TInt at an Int-instantiated call site) would read the
     runtime's uniform tagged value raw — 42 back as (42<<1)|1 = 85. Without
     this row the name fell through to the unknown-extern fallback and
     linked against a nonexistent bare `try_finally` symbol. *)
  { march_name = "try_finally"; c_name = Some "march_try_finally"; ret_ty = Some (Tir.TVar "_");
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_try_finally(ptr %action, ptr %cleanup)" };
  { march_name = "println"; c_name = Some "march_println"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare void @march_println(ptr %s)" };
  (* Same C symbol as "println" above; no second PDeclare.  The two March names
     exist because the polymorphic prelude wrapper shadows "println". *)
  { march_name = "print_line"; c_name = Some "march_println"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = None };
  { march_name = "print_stderr"; c_name = Some "march_print_stderr"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare void @march_print_stderr(ptr %s)" };
  { march_name = "io_read_line"; c_name = Some "march_io_read_line"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_io_read_line()" };
  { march_name = "read_line"; c_name = Some "march_io_read_line"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_io_read_line()" };
  { march_name = "io_read_byte"; c_name = Some "march_io_read_byte"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_io_read_byte()" };
  { march_name = "read_byte"; c_name = Some "march_io_read_byte"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_io_read_byte()" };
  { march_name = "html_auto_escape"; c_name = Some "march_html_auto_escape"; ret_ty = Some Tir.TString;
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_html_auto_escape(ptr %v)" };
  { march_name = "html_escape_ctx"; c_name = Some "march_html_escape_ctx"; ret_ty = Some Tir.TString;
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_html_escape_ctx(i64 %id, ptr %v)" };
  { march_name = "record_keys"; c_name = Some "march_record_keys"; ret_ty = Some (Tir.TCon ("List", [Tir.TString]));
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_record_keys(ptr %rec)" };
  { march_name = "record_values"; c_name = Some "march_record_values"; ret_ty = Some (Tir.TCon ("List", [Tir.TVar "_"]));
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_record_values(ptr %rec)" };
  { march_name = "record_entries"; c_name = Some "march_record_entries"; ret_ty = Some (Tir.TCon ("List", [Tir.TTuple [Tir.TString; Tir.TVar "_"]]));
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_record_entries(ptr %rec)" };
  { march_name = "record_get"; c_name = Some "march_record_get"; ret_ty = Some (Tir.TCon ("Option", [Tir.TVar "_"]));
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_record_get(ptr %rec, ptr %key, i64 %kind)" };
  { march_name = "record_has_key"; c_name = Some "march_record_has_key"; ret_ty = Some Tir.TBool;
    in_is_builtin = false; declare_sig = Some "declare i64  @march_record_has_key(ptr %rec, ptr %key)" };
  { march_name = "record_put"; c_name = Some "march_record_put3"; ret_ty = Some (Tir.TVar "_");
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_record_put3(ptr %rec, ptr %key, ptr %val)" };
  { march_name = "record_from_list"; c_name = Some "march_record_from_list"; ret_ty = Some (Tir.TVar "_");
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_record_from_list(ptr %list)" };
  { march_name = "int_to_string"; c_name = Some "march_int_to_string"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_int_to_string(i64 %n)" };
  { march_name = "float_to_string"; c_name = Some "march_float_to_string"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr    @march_float_to_string(double %f)" };
  { march_name = "bool_to_string"; c_name = Some "march_bool_to_string"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr    @march_bool_to_string(i64 %b)" };
  (* `atom_to_string` (the Show$Atom.show delegate) has NO preamble declare:
     unlike the other *_to_string builtins it is not a C runtime symbol but a
     compile-time-generated function emitted per-module by
     [Llvm_toplevel.emit_atom_show_table] (a switch over ctx.atom_names, run by
     both the AOT and JIT/REPL finalizers).  Emitting a `declare` here as well
     as that `define` would be an LLVM redefinition, so
     declare_sig is None; the call site still mangles to @march_atom_to_string
     via c_name and resolves to the in-module definition. *)
  { march_name = "atom_to_string"; c_name = Some "march_atom_to_string"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = None };
  { march_name = "++"; c_name = Some "march_string_concat"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_concat(ptr %a, ptr %b)" };
  { march_name = "string_concat"; c_name = Some "march_string_concat"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_concat(ptr %a, ptr %b)" };
  { march_name = "string_eq"; c_name = Some "march_string_eq"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_string_eq(ptr %a, ptr %b)" };
  { march_name = "march_compare_int"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = false; declare_sig = Some "declare i64    @march_compare_int(i64 %x, i64 %y)" };
  { march_name = "march_compare_float"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = false; declare_sig = Some "declare i64    @march_compare_float(double %x, double %y)" };
  { march_name = "march_compare_string"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = false; declare_sig = Some "declare i64    @march_compare_string(ptr %x, ptr %y)" };
  { march_name = "march_hash_int"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = false; declare_sig = Some "declare i64    @march_hash_int(i64 %x)" };
  { march_name = "march_hash_float"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = false; declare_sig = Some "declare i64    @march_hash_float(double %x)" };
  { march_name = "march_hash_string"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = false; declare_sig = Some "declare i64    @march_hash_string(ptr %x)" };
  { march_name = "march_hash_bool"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = false; declare_sig = Some "declare i64    @march_hash_bool(i64 %x)" };
  { march_name = "string_length"; c_name = Some "march_string_byte_length"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_string_byte_length(ptr %s)" };
  { march_name = "string_byte_length"; c_name = Some "march_string_byte_length"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_string_byte_length(ptr %s)" };
  { march_name = "string_byte_at"; c_name = Some "march_string_byte_at"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_string_byte_at(ptr %s, i64 %i)" };
  { march_name = "string_is_empty"; c_name = Some "march_string_is_empty"; ret_ty = Some Tir.TBool;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_string_is_empty(ptr %s)" };
  { march_name = "string_to_int"; c_name = Some "march_string_to_int"; ret_ty = Some (Tir.TCon ("Option", [Tir.TInt]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_to_int(ptr %s)" };
  { march_name = "string_concat3"; c_name = Some "march_string_concat3"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_concat3(ptr %a, ptr %b, ptr %c)" };
  { march_name = "string_join"; c_name = Some "march_string_join"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_join(ptr %list, ptr %sep)" };
  { march_name = "float_abs"; c_name = Some "march_float_abs"; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @march_float_abs(double %f)" };
  { march_name = "float_ceil"; c_name = Some "march_float_ceil"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64    @march_float_ceil(double %f)" };
  { march_name = "float_floor"; c_name = Some "march_float_floor"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64    @march_float_floor(double %f)" };
  { march_name = "float_round"; c_name = Some "march_float_round"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64    @march_float_round(double %f)" };
  { march_name = "float_truncate"; c_name = Some "march_float_truncate"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64    @march_float_truncate(double %f)" };
  { march_name = "int_to_float"; c_name = Some "march_int_to_float"; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @march_int_to_float(i64 %n)" };
  { march_name = "char_from_int"; c_name = Some "march_char_from_int"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr    @march_char_from_int(i64 %n)" };
  { march_name = "byte_to_char"; c_name = Some "march_char_from_int"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr    @march_char_from_int(i64 %n)" };
  { march_name = "char_to_int"; c_name = Some "march_char_to_int"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64    @march_char_to_int(ptr %c)" };
  { march_name = "char_is_digit"; c_name = Some "march_char_is_digit"; ret_ty = Some Tir.TBool;
    in_is_builtin = true; declare_sig = Some "declare i64    @march_char_is_digit(ptr %c)" };
  { march_name = "char_is_alphanumeric"; c_name = Some "march_char_is_alphanumeric"; ret_ty = Some Tir.TBool;
    in_is_builtin = true; declare_sig = Some "declare i64    @march_char_is_alphanumeric(ptr %c)" };
  { march_name = "char_is_whitespace"; c_name = Some "march_char_is_whitespace"; ret_ty = Some Tir.TBool;
    in_is_builtin = true; declare_sig = Some "declare i64    @march_char_is_whitespace(ptr %c)" };
  { march_name = "float_to_int"; c_name = Some "march_float_to_int"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64    @march_float_to_int(double %f)" };
  { march_name = "math_sin"; c_name = Some "march_math_sin"; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @march_math_sin(double %f)" };
  { march_name = "math_cos"; c_name = Some "march_math_cos"; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @march_math_cos(double %f)" };
  { march_name = "math_tan"; c_name = Some "march_math_tan"; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @march_math_tan(double %f)" };
  { march_name = "math_asin"; c_name = Some "march_math_asin"; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @march_math_asin(double %f)" };
  { march_name = "math_acos"; c_name = Some "march_math_acos"; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @march_math_acos(double %f)" };
  { march_name = "math_atan"; c_name = Some "march_math_atan"; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @march_math_atan(double %f)" };
  { march_name = "math_atan2"; c_name = Some "march_math_atan2"; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @march_math_atan2(double %y, double %x)" };
  { march_name = "math_sinh"; c_name = Some "march_math_sinh"; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @march_math_sinh(double %f)" };
  { march_name = "math_cosh"; c_name = Some "march_math_cosh"; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @march_math_cosh(double %f)" };
  { march_name = "math_tanh"; c_name = Some "march_math_tanh"; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @march_math_tanh(double %f)" };
  { march_name = "math_sqrt"; c_name = Some "march_math_sqrt"; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @march_math_sqrt(double %f)" };
  { march_name = "math_cbrt"; c_name = Some "march_math_cbrt"; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @march_math_cbrt(double %f)" };
  { march_name = "math_exp"; c_name = Some "march_math_exp"; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @march_math_exp(double %f)" };
  { march_name = "math_exp2"; c_name = Some "march_math_exp2"; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @march_math_exp2(double %f)" };
  { march_name = "math_log"; c_name = Some "march_math_log"; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @march_math_log(double %f)" };
  { march_name = "math_log2"; c_name = Some "march_math_log2"; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @march_math_log2(double %f)" };
  { march_name = "math_log10"; c_name = Some "march_math_log10"; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @march_math_log10(double %f)" };
  { march_name = "math_pow"; c_name = Some "march_math_pow"; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @march_math_pow(double %b, double %e)" };
  { march_name = "string_chars"; c_name = Some "march_string_chars"; ret_ty = Some (Tir.TCon ("List", [Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_chars(ptr %s)" };
  { march_name = "string_to_codepoints"; c_name = Some "march_string_to_codepoints";
    ret_ty = Some (Tir.TCon ("List", [Tir.TInt])); in_is_builtin = true;
    declare_sig = Some "declare ptr  @march_string_to_codepoints(ptr %s)" };
  { march_name = "string_from_codepoint"; c_name = Some "march_string_from_codepoint";
    ret_ty = Some (Tir.TCon ("Option", [Tir.TString])); in_is_builtin = true;
    declare_sig = Some "declare ptr  @march_string_from_codepoint(i64 %cp)" };
  { march_name = "string_from_chars"; c_name = Some "march_string_from_chars"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_from_chars(ptr %list)" };
  { march_name = "string_contains"; c_name = Some "march_string_contains"; ret_ty = Some Tir.TBool;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_string_contains(ptr %s, ptr %sub)" };
  { march_name = "string_starts_with"; c_name = Some "march_string_starts_with"; ret_ty = Some Tir.TBool;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_string_starts_with(ptr %s, ptr %prefix)" };
  { march_name = "string_ends_with"; c_name = Some "march_string_ends_with"; ret_ty = Some Tir.TBool;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_string_ends_with(ptr %s, ptr %suffix)" };
  { march_name = "string_slice"; c_name = Some "march_string_slice"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_slice(ptr %s, i64 %start, i64 %len)" };
  { march_name = "string_split"; c_name = Some "march_string_split"; ret_ty = Some (Tir.TCon ("List", [Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_split(ptr %s, ptr %sep)" };
  { march_name = "string_split_first"; c_name = Some "march_string_split_first"; ret_ty = Some (Tir.TCon ("Option", [Tir.TTuple [Tir.TString; Tir.TString]]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_split_first(ptr %s, ptr %sep)" };
  { march_name = "string_replace"; c_name = Some "march_string_replace"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_replace(ptr %s, ptr %old, ptr %new)" };
  { march_name = "string_replace_all"; c_name = Some "march_string_replace_all"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_replace_all(ptr %s, ptr %old, ptr %new)" };
  { march_name = "string_to_lowercase"; c_name = Some "march_string_to_lowercase"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_to_lowercase(ptr %s)" };
  { march_name = "string_to_uppercase"; c_name = Some "march_string_to_uppercase"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_to_uppercase(ptr %s)" };
  { march_name = "string_trim"; c_name = Some "march_string_trim"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_trim(ptr %s)" };
  { march_name = "string_trim_start"; c_name = Some "march_string_trim_start"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_trim_start(ptr %s)" };
  { march_name = "string_trim_end"; c_name = Some "march_string_trim_end"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_trim_end(ptr %s)" };
  { march_name = "string_repeat"; c_name = Some "march_string_repeat"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_repeat(ptr %s, i64 %n)" };
  { march_name = "string_reverse"; c_name = Some "march_string_reverse"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_reverse(ptr %s)" };
  { march_name = "string_pad_left"; c_name = Some "march_string_pad_left"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_pad_left(ptr %s, i64 %width, ptr %fill)" };
  { march_name = "string_pad_right"; c_name = Some "march_string_pad_right"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_pad_right(ptr %s, i64 %width, ptr %fill)" };
  { march_name = "string_grapheme_count"; c_name = Some "march_string_grapheme_count"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_string_grapheme_count(ptr %s)" };
  { march_name = "string_index_of"; c_name = Some "march_string_index_of"; ret_ty = Some (Tir.TCon ("Option", [Tir.TInt]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_index_of(ptr %s, ptr %sub)" };
  { march_name = "string_index_of_from"; c_name = Some "march_string_index_of_from"; ret_ty = Some (Tir.TCon ("Option", [Tir.TInt]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_index_of_from(ptr %s, ptr %sub, i64 %start)" };
  { march_name = "string_last_index_of"; c_name = Some "march_string_last_index_of"; ret_ty = Some (Tir.TCon ("Option", [Tir.TInt]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_last_index_of(ptr %s, ptr %sub)" };
  { march_name = "string_to_float"; c_name = Some "march_string_to_float"; ret_ty = Some (Tir.TCon ("Option", [Tir.TFloat]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_string_to_float(ptr %s)" };
  { march_name = "list_append"; c_name = Some "march_list_append"; ret_ty = Some (Tir.TCon ("List", [Tir.TVar "a"]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_list_append(ptr %a, ptr %b)" };
  { march_name = "list_concat"; c_name = Some "march_list_concat"; ret_ty = Some (Tir.TCon ("List", [Tir.TVar "a"]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_list_concat(ptr %lists)" };
  { march_name = "iolist_hash_fnv1a"; c_name = Some "march_iolist_hash_fnv1a"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_iolist_hash_fnv1a(ptr %iol)" };
  { march_name = "vault_new"; c_name = Some "march_vault_new"; ret_ty = Some (Tir.TPtr Tir.TUnit);
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_vault_new(ptr %name)" };
  { march_name = "vault_whereis"; c_name = Some "march_vault_whereis"; ret_ty = Some (Tir.TCon ("Option", [Tir.TPtr Tir.TUnit]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_vault_whereis(ptr %name)" };
  { march_name = "vault_set"; c_name = Some "march_vault_set"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_vault_set(ptr %table, ptr %key, ptr %value)" };
  { march_name = "vault_set_ttl"; c_name = Some "march_vault_set_ttl"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_vault_set_ttl(ptr %table, ptr %key, ptr %value, i64 %ttl)" };
  { march_name = "vault_put_new"; c_name = Some "march_vault_put_new"; ret_ty = Some Tir.TBool;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_vault_put_new(ptr %table, ptr %key, ptr %value, i64 %ttl)" };
  { march_name = "vault_incr"; c_name = Some "march_vault_incr"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_vault_incr(ptr %table, ptr %key, i64 %delta)" };
  { march_name = "vault_push_capped"; c_name = Some "march_vault_push_capped"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_vault_push_capped(ptr %table, ptr %key, ptr %value, i64 %max)" };
  { march_name = "vault_get"; c_name = Some "march_vault_get"; ret_ty = Some (Tir.TCon ("Option", [Tir.TPtr Tir.TUnit]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_vault_get(ptr %table, ptr %key)" };
  { march_name = "vault_drop"; c_name = Some "march_vault_drop"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_vault_drop(ptr %table, ptr %key)" };
  { march_name = "vault_update"; c_name = Some "march_vault_update"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_vault_update(ptr %table, ptr %key, ptr %f)" };
  { march_name = "vault_size"; c_name = Some "march_vault_size"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_vault_size(ptr %table)" };
  { march_name = "vault_keys"; c_name = Some "march_vault_keys"; ret_ty = Some (Tir.TCon ("List", [Tir.TPtr Tir.TUnit]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_vault_keys(ptr %table)" };
  { march_name = "vault_ns_set"; c_name = Some "march_vault_ns_set"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_vault_ns_set(ptr %ns, ptr %key, ptr %value)" };
  { march_name = "vault_ns_get"; c_name = Some "march_vault_ns_get"; ret_ty = Some (Tir.TCon ("Option", [Tir.TPtr Tir.TUnit]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_vault_ns_get(ptr %ns, ptr %key)" };
  { march_name = "vault_ns_drop"; c_name = Some "march_vault_ns_drop"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_vault_ns_drop(ptr %ns, ptr %key)" };
  { march_name = "md5"; c_name = Some "march_md5"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_md5(ptr %b)" };
  { march_name = "sha256"; c_name = Some "march_sha256"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_sha256(ptr %b)" };
  { march_name = "stdlib_sha256"; c_name = Some "march_sha256"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_sha256(ptr %b)" };
  { march_name = "sha512"; c_name = Some "march_sha512"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_sha512(ptr %b)" };
  { march_name = "stdlib_sha512"; c_name = Some "march_sha512"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_sha512(ptr %b)" };
  { march_name = "sha1_bytes"; c_name = Some "march_sha1_bytes"; ret_ty = Some (Tir.TCon ("Bytes", []));
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_sha1_bytes(ptr %b)" };
  { march_name = "hmac_sha256"; c_name = Some "march_hmac_sha256"; ret_ty = Some (Tir.TCon ("Result", [Tir.TCon ("Bytes", []); Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_hmac_sha256(ptr %key, ptr %msg)" };
  { march_name = "stdlib_hmac_sha256"; c_name = Some "march_hmac_sha256"; ret_ty = Some (Tir.TCon ("Result", [Tir.TCon ("Bytes", []); Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_hmac_sha256(ptr %key, ptr %msg)" };
  { march_name = "hmac_sha256_bytes"; c_name = Some "march_hmac_sha256_bytes"; ret_ty = Some (Tir.TCon ("Bytes", []));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_hmac_sha256_bytes(ptr %key, ptr %msg)" };
  { march_name = "pbkdf2_sha256"; c_name = Some "march_pbkdf2_sha256"; ret_ty = Some (Tir.TCon ("Result", [Tir.TCon ("Bytes", []); Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_pbkdf2_sha256(ptr %pass, ptr %salt, i64 %iters, i64 %len)" };
  { march_name = "base64_encode"; c_name = Some "march_base64_encode"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_base64_encode(ptr %b)" };
  { march_name = "stdlib_base64_encode"; c_name = Some "march_base64_encode"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_base64_encode(ptr %b)" };
  { march_name = "base64_decode"; c_name = Some "march_base64_decode"; ret_ty = Some (Tir.TCon ("Result", [Tir.TCon ("Bytes", []); Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_base64_decode(ptr %s)" };
  { march_name = "stdlib_base64_decode"; c_name = Some "march_base64_decode"; ret_ty = Some (Tir.TCon ("Result", [Tir.TCon ("Bytes", []); Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_base64_decode(ptr %s)" };
  { march_name = "random_bytes"; c_name = Some "march_random_bytes"; ret_ty = Some (Tir.TCon ("Bytes", []));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_random_bytes(i64 %n)" };
  { march_name = "stdlib_random_bytes"; c_name = Some "march_random_bytes"; ret_ty = Some (Tir.TCon ("Bytes", []));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_random_bytes(i64 %n)" };
  { march_name = "bytes_to_u8_arr"; c_name = None; ret_ty = Some (Tir.TCon ("NativeU8Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr  @bytes_to_u8_arr(ptr %b)" };
  { march_name = "u8_arr_to_bytes"; c_name = None; ret_ty = Some (Tir.TCon ("Bytes", []));
    in_is_builtin = true; declare_sig = Some "declare ptr  @u8_arr_to_bytes(ptr %arr)" };
  { march_name = "stdlib_gzip_encode"; c_name = Some "march_gzip_encode"; ret_ty = Some (Tir.TCon ("Result", [Tir.TCon ("Bytes", []); Tir.TString]));
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_gzip_encode(ptr %b, i64 %level)" };
  { march_name = "stdlib_gzip_decode"; c_name = Some "march_gzip_decode"; ret_ty = Some (Tir.TCon ("Result", [Tir.TCon ("Bytes", []); Tir.TString]));
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_gzip_decode(ptr %b)" };
  { march_name = "stdlib_deflate_encode"; c_name = Some "march_deflate_encode"; ret_ty = Some (Tir.TCon ("Result", [Tir.TCon ("Bytes", []); Tir.TString]));
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_deflate_encode(ptr %b)" };
  { march_name = "stdlib_deflate_decode"; c_name = Some "march_deflate_decode"; ret_ty = Some (Tir.TCon ("Result", [Tir.TCon ("Bytes", []); Tir.TString]));
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_deflate_decode(ptr %b)" };
  { march_name = "stdlib_zstd_encode"; c_name = Some "march_zstd_encode"; ret_ty = Some (Tir.TCon ("Result", [Tir.TCon ("Bytes", []); Tir.TString]));
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_zstd_encode(ptr %b, i64 %level)" };
  { march_name = "stdlib_zstd_decode"; c_name = Some "march_zstd_decode"; ret_ty = Some (Tir.TCon ("Result", [Tir.TCon ("Bytes", []); Tir.TString]));
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_zstd_decode(ptr %b)" };
  { march_name = "stdlib_brotli_encode"; c_name = Some "march_brotli_encode"; ret_ty = Some (Tir.TCon ("Result", [Tir.TCon ("Bytes", []); Tir.TString]));
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_brotli_encode(ptr %b, i64 %mode, i64 %quality)" };
  { march_name = "stdlib_brotli_decode"; c_name = Some "march_brotli_decode"; ret_ty = Some (Tir.TCon ("Result", [Tir.TCon ("Bytes", []); Tir.TString]));
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_brotli_decode(ptr %b)" };
  { march_name = "sys_uptime_ms"; c_name = Some "march_sys_uptime_ms"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_sys_uptime_ms()" };
  { march_name = "sys_heap_bytes"; c_name = Some "march_sys_heap_bytes"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_sys_heap_bytes()" };
  { march_name = "sys_word_size"; c_name = Some "march_sys_word_size"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_sys_word_size()" };
  { march_name = "sys_minor_gcs"; c_name = Some "march_sys_minor_gcs"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_sys_minor_gcs()" };
  { march_name = "sys_major_gcs"; c_name = Some "march_sys_major_gcs"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_sys_major_gcs()" };
  { march_name = "sys_actor_count"; c_name = Some "march_sys_actor_count"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_sys_actor_count()" };
  { march_name = "sys_cpu_count"; c_name = Some "march_sys_cpu_count"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_sys_cpu_count()" };
  { march_name = "sys_cpu_load_milli"; c_name = Some "march_sys_cpu_load_milli"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_sys_cpu_load_milli()" };
  { march_name = "sys_mem_total_bytes"; c_name = Some "march_sys_mem_total_bytes"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_sys_mem_total_bytes()" };
  { march_name = "sys_mem_available_bytes"; c_name = Some "march_sys_mem_available_bytes"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_sys_mem_available_bytes()" };
  { march_name = "sys_os"; c_name = Some "march_sys_os"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_sys_os()" };
  { march_name = "sys_arch"; c_name = Some "march_sys_arch"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_sys_arch()" };
  { march_name = "march_version"; c_name = Some "march_get_version"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_get_version()" };
  { march_name = "uuid_v4"; c_name = Some "march_uuid_v4"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_uuid_v4()" };
  { march_name = "remote_register_stub"; c_name = Some "march_remote_register"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i32  @march_remote_register(ptr %impl_hash, ptr %sg_hash, ptr %stub)" };
  { march_name = "remote_count"; c_name = Some "march_remote_count"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_remote_count()" };
  { march_name = "remote_check"; c_name = Some "march_remote_check_march"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_remote_check_march(ptr %impl_hash, ptr %sig_hash)" };
  { march_name = "remote_invoke"; c_name = Some "march_remote_invoke_march"; ret_ty = Some (Tir.TCon ("Option", [Tir.TCon ("Result", [Tir.TCon ("List", [Tir.TInt]); Tir.TString])]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_remote_invoke_march(ptr %impl_hash, ptr %args)" };
  { march_name = "logger_set_level"; c_name = Some "march_logger_set_level"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_logger_set_level(i64 %level)" };
  { march_name = "logger_get_level"; c_name = Some "march_logger_get_level"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_logger_get_level()" };
  { march_name = "logger_add_context"; c_name = Some "march_logger_add_context"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_logger_add_context(ptr %key, ptr %value)" };
  { march_name = "logger_clear_context"; c_name = Some "march_logger_clear_context"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_logger_clear_context()" };
  { march_name = "logger_get_context"; c_name = Some "march_logger_get_context"; ret_ty = Some (Tir.TCon ("List", [Tir.TTuple [Tir.TString; Tir.TString]]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_logger_get_context()" };
  { march_name = "logger_write"; c_name = Some "march_logger_write"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_logger_write(ptr %level, ptr %msg, ptr %ctx, ptr %extra)" };
  { march_name = "kill"; c_name = Some "march_kill"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare void @march_kill(ptr %actor)" };
  { march_name = "is_alive"; c_name = Some "march_is_alive"; ret_ty = Some Tir.TBool;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_is_alive(ptr %actor)" };
  { march_name = "send"; c_name = Some "march_send"; ret_ty = Some (Tir.TCon ("Option", [Tir.TUnit]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_send(ptr %actor, ptr %msg)" };
  { march_name = "actor_cast"; c_name = Some "march_send"; ret_ty = Some (Tir.TCon ("Option", [Tir.TUnit]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_send(ptr %actor, ptr %msg)" };
  { march_name = "send_linear"; c_name = Some "march_send_linear"; ret_ty = Some (Tir.TCon ("Option", [Tir.TUnit]));
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_send_linear(ptr %actor, ptr %msg)" };
  { march_name = "spawn"; c_name = Some "march_spawn"; ret_ty = Some (Tir.TPtr Tir.TUnit);
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_spawn(ptr %actor)" };
  { march_name = "spawn_supervised"; c_name = Some "march_spawn_supervised"; ret_ty = Some (Tir.TPtr Tir.TUnit);
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_spawn_supervised(ptr %actor)" };
  { march_name = "actor_get_int"; c_name = Some "march_actor_get_int"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_actor_get_int(ptr %actor, i64 %index)" };
  { march_name = "actor_call"; c_name = Some "march_actor_call"; ret_ty = Some (Tir.TCon ("Result", [Tir.TVar "a"; Tir.TVar "e"]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_actor_call(ptr %actor, ptr %msg, i64 %timeout_ms)" };
  { march_name = "actor_reply"; c_name = Some "march_actor_reply"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare void @march_actor_reply(ptr %ref, ptr %result)" };
  (* actor_send_after/actor_cancel_timer (specs/progress/2026-08-12-language-
     level-timers.md). Same (ptr, ptr, i64) -> ptr shape as actor_call above
     -- pid and msg go through the general EApp path exactly like
     actor_cast/actor_call's do (no special-casing needed: msg is
     conventionally always an actor-message constructor, same as
     actor_cast's, and pid is exactly as unconstrained). *)
  { march_name = "actor_send_after"; c_name = Some "march_send_after"; ret_ty = Some (Tir.TCon ("TimerRef", []));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_send_after(ptr %actor, ptr %msg, i64 %delay_ms)" };
  { march_name = "actor_cancel_timer"; c_name = Some "march_timer_cancel"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare void @march_timer_cancel(ptr %tok)" };
  { march_name = "receive"; c_name = Some "march_sched_recv"; ret_ty = Some (Tir.TPtr Tir.TUnit);
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_sched_recv()" };
  { march_name = "tcp_listen"; c_name = Some "march_tcp_listen"; ret_ty = Some (Tir.TCon ("Result", [Tir.TInt; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_tcp_listen(i64 %port)" };
  { march_name = "tcp_accept"; c_name = Some "march_tcp_accept"; ret_ty = Some (Tir.TCon ("Result", [Tir.TInt; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_tcp_accept(i64 %fd)" };
  { march_name = "tcp_local_port"; c_name = Some "march_tcp_local_port"; ret_ty = Some (Tir.TCon ("Result", [Tir.TInt; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_tcp_local_port(i64 %fd)" };
  { march_name = "tcp_recv_exact"; c_name = Some "march_tcp_recv_exact"; ret_ty = Some (Tir.TCon ("Result", [Tir.TCon ("Bytes", []); Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_tcp_recv_exact(i64 %fd, i64 %n)" };
  { march_name = "tcp_recv_http"; c_name = Some "march_tcp_recv_http"; ret_ty = Some (Tir.TCon ("Result", [Tir.TString; Tir.TString]));
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_tcp_recv_http(i64 %fd, i64 %max)" };
  { march_name = "tcp_send_all"; c_name = Some "march_tcp_send_all"; ret_ty = Some (Tir.TCon ("Result", [Tir.TUnit; Tir.TString]));
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_tcp_send_all(i64 %fd, ptr %data)" };
  { march_name = "tcp_close"; c_name = Some "march_tcp_close"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare void @march_tcp_close(i64 %fd)" };
  { march_name = "tcp_peer_addr"; c_name = Some "march_tcp_peer_addr"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_tcp_peer_addr(i64 %fd)" };
  { march_name = "http_parse_request"; c_name = Some "march_http_parse_request"; ret_ty = Some (Tir.TCon ("Result", [Tir.TVar "a"; Tir.TString]));
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_http_parse_request(ptr %raw)" };
  { march_name = "http_serialize_response"; c_name = Some "march_http_serialize_response"; ret_ty = Some Tir.TString;
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_http_serialize_response(i64 %status, ptr %headers, ptr %body)" };
  { march_name = "http_server_listen"; c_name = Some "march_http_server_listen"; ret_ty = Some Tir.TInt;
    in_is_builtin = false; declare_sig = Some "declare void @march_http_server_listen(i64 %port, i64 %max_conns, i64 %idle_timeout, ptr %pipeline)" };
  { march_name = "http_server_spawn_n"; c_name = Some "march_http_server_spawn_n"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_http_server_spawn_n(i64 %port, i64 %n, i64 %max_conns, i64 %idle_timeout, ptr %pipeline)" };
  { march_name = "http_server_wait"; c_name = Some "march_http_server_wait"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare void @march_http_server_wait(i64 %handle)" };
  { march_name = "ws_handshake"; c_name = Some "march_ws_handshake"; ret_ty = Some (Tir.TCon ("Result", [Tir.TVar "a"; Tir.TString]));
    in_is_builtin = false; declare_sig = Some "declare void @march_ws_handshake(i64 %fd, ptr %key)" };
  { march_name = "ws_recv"; c_name = Some "march_ws_recv"; ret_ty = Some (Tir.TCon ("Result", [Tir.TString; Tir.TString]));
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_ws_recv(i64 %fd)" };
  { march_name = "ws_send"; c_name = Some "march_ws_send"; ret_ty = Some (Tir.TCon ("Result", [Tir.TUnit; Tir.TString]));
    in_is_builtin = false; declare_sig = Some "declare void @march_ws_send(i64 %fd, ptr %frame)" };
  { march_name = "ws_select"; c_name = Some "march_ws_select"; ret_ty = Some (Tir.TCon ("Result", [Tir.TVar "a"; Tir.TString]));
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_ws_select(i64 %fd, ptr %pipe, i64 %timeout)" };
  { march_name = "file_exists"; c_name = Some "march_file_exists"; ret_ty = Some Tir.TBool;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_file_exists(ptr %s)" };
  { march_name = "dir_exists"; c_name = Some "march_dir_exists"; ret_ty = Some Tir.TBool;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_dir_exists(ptr %s)" };
  { march_name = "file_open"; c_name = Some "march_file_open"; ret_ty = Some (Tir.TCon ("Result", [Tir.TInt; Tir.TCon ("FileError", [])]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_file_open(ptr %path)" };
  { march_name = "file_close"; c_name = Some "march_file_close"; ret_ty = Some (Tir.TPtr Tir.TUnit);
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_file_close(ptr %handle)" };
  { march_name = "file_read"; c_name = Some "march_file_read"; ret_ty = Some (Tir.TCon ("Result", [Tir.TString; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_file_read(ptr %path)" };
  { march_name = "file_read_line"; c_name = Some "march_file_read_line"; ret_ty = Some (Tir.TCon ("Option", [Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_file_read_line(ptr %handle)" };
  { march_name = "file_read_chunk"; c_name = Some "march_file_read_chunk"; ret_ty = Some (Tir.TCon ("Option", [Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_file_read_chunk(ptr %handle, i64 %size)" };
  { march_name = "file_write"; c_name = Some "march_file_write"; ret_ty = Some (Tir.TCon ("Result", [Tir.TUnit; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_file_write(ptr %path, ptr %data)" };
  { march_name = "file_append"; c_name = Some "march_file_append"; ret_ty = Some (Tir.TCon ("Result", [Tir.TUnit; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_file_append(ptr %path, ptr %data)" };
  { march_name = "file_delete"; c_name = Some "march_file_delete"; ret_ty = Some (Tir.TCon ("Result", [Tir.TUnit; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_file_delete(ptr %path)" };
  { march_name = "file_copy"; c_name = Some "march_file_copy"; ret_ty = Some (Tir.TCon ("Result", [Tir.TUnit; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_file_copy(ptr %src, ptr %dst)" };
  { march_name = "file_rename"; c_name = Some "march_file_rename"; ret_ty = Some (Tir.TCon ("Result", [Tir.TUnit; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_file_rename(ptr %src, ptr %dst)" };
  { march_name = "file_stat"; c_name = Some "march_file_stat"; ret_ty = Some (Tir.TCon ("Result", [Tir.TVar "a"; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_file_stat(ptr %path)" };
  { march_name = "dir_mkdir"; c_name = Some "march_dir_mkdir"; ret_ty = Some (Tir.TCon ("Result", [Tir.TUnit; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_dir_mkdir(ptr %path)" };
  { march_name = "dir_mkdir_p"; c_name = Some "march_dir_mkdir_p"; ret_ty = Some (Tir.TCon ("Result", [Tir.TUnit; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_dir_mkdir_p(ptr %path)" };
  { march_name = "dir_rmdir"; c_name = Some "march_dir_rmdir"; ret_ty = Some (Tir.TCon ("Result", [Tir.TUnit; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_dir_rmdir(ptr %path)" };
  { march_name = "dir_rm_rf"; c_name = Some "march_dir_rm_rf"; ret_ty = Some (Tir.TCon ("Result", [Tir.TUnit; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_dir_rm_rf(ptr %path)" };
  { march_name = "dir_list"; c_name = Some "march_dir_list"; ret_ty = Some (Tir.TCon ("Result", [Tir.TCon ("List", [Tir.TString]); Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_dir_list(ptr %path)" };
  { march_name = "dir_list_full"; c_name = Some "march_dir_list_full"; ret_ty = Some (Tir.TCon ("Result", [Tir.TCon ("List", [Tir.TString]); Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_dir_list_full(ptr %path)" };
  { march_name = "process_argv"; c_name = Some "march_process_argv"; ret_ty = Some (Tir.TCon ("List", [Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_process_argv()" };
  { march_name = "process_cwd"; c_name = Some "march_process_cwd"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_process_cwd()" };
  { march_name = "process_env"; c_name = Some "march_process_env"; ret_ty = Some (Tir.TCon ("Option", [Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_process_env(ptr %name)" };
  { march_name = "process_set_env"; c_name = Some "march_process_set_env"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_process_set_env(ptr %name, ptr %value)" };
  { march_name = "process_exit"; c_name = Some "march_process_exit"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_process_exit(i64 %code)" };
  { march_name = "process_pid"; c_name = Some "march_process_pid"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_process_pid()" };
  { march_name = "process_spawn_sync"; c_name = Some "march_process_spawn_sync"; ret_ty = Some (Tir.TCon ("Result", [Tir.TVar "a"; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_process_spawn_sync(ptr %cmd, ptr %args)" };
  { march_name = "process_spawn_lines"; c_name = Some "march_process_spawn_lines"; ret_ty = Some (Tir.TCon ("Result", [Tir.TVar "a"; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_process_spawn_lines(ptr %cmd, ptr %args)" };
  { march_name = "process_spawn_async"; c_name = Some "march_process_spawn_async"; ret_ty = Some (Tir.TCon ("Result", [Tir.TCon ("LiveProcess", []); Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_process_spawn_async(ptr %cmd, ptr %args)" };
  { march_name = "process_read_line"; c_name = Some "march_process_read_line"; ret_ty = Some (Tir.TCon ("Option", [Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_process_read_line(ptr %proc)" };
  { march_name = "process_write"; c_name = Some "march_process_write"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_process_write(ptr %proc, ptr %data)" };
  { march_name = "process_kill_proc"; c_name = Some "march_process_kill_proc"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_process_kill_proc(ptr %proc)" };
  { march_name = "process_wait_proc"; c_name = Some "march_process_wait_proc"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_process_wait_proc(ptr %proc)" };
  { march_name = "tcp_recv_all"; c_name = Some "march_tcp_recv_all"; ret_ty = Some (Tir.TCon ("Result", [Tir.TString; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_tcp_recv_all(i64 %fd, i64 %max_bytes, i64 %timeout_ms)" };
  { march_name = "tcp_recv_chunk"; c_name = Some "march_tcp_recv_chunk"; ret_ty = Some (Tir.TCon ("Result", [Tir.TString; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_tcp_recv_chunk(i64 %fd, i64 %max_bytes)" };
  { march_name = "tcp_recv_chunk_timeout"; c_name = Some "march_tcp_recv_chunk_timeout"; ret_ty = Some (Tir.TCon ("Result", [Tir.TString; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_tcp_recv_chunk_timeout(i64 %fd, i64 %max_bytes, i64 %timeout_ms)" };
  { march_name = "tcp_set_recv_timeout"; c_name = Some "march_tcp_set_recv_timeout"; ret_ty = Some (Tir.TCon ("Result", [Tir.TUnit; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_tcp_set_recv_timeout(i64 %fd, i64 %timeout_ms)" };
  { march_name = "tcp_recv_timeout"; c_name = Some "march_tcp_recv_timeout"; ret_ty = Some (Tir.TCon ("Result", [Tir.TCon ("Option", [Tir.TString]); Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_tcp_recv_timeout(i64 %fd, i64 %max_bytes, i64 %timeout_ms)" };
  { march_name = "tcp_recv_http_headers"; c_name = Some "march_tcp_recv_http_headers"; ret_ty = Some (Tir.TCon ("Result", [Tir.TString; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_tcp_recv_http_headers(i64 %fd)" };
  { march_name = "tcp_recv_chunked_frame"; c_name = Some "march_tcp_recv_chunked_frame"; ret_ty = Some (Tir.TCon ("Result", [Tir.TString; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_tcp_recv_chunked_frame(i64 %fd)" };
  { march_name = "tls_client_ctx"; c_name = Some "march_tls_client_ctx"; ret_ty = Some (Tir.TCon ("Result", [Tir.TInt; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_tls_client_ctx(ptr %ca_file, ptr %alpn_list, i64 %verify_peer, i64 %timeout_ms)" };
  { march_name = "tls_server_ctx"; c_name = Some "march_tls_server_ctx"; ret_ty = Some (Tir.TCon ("Result", [Tir.TInt; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_tls_server_ctx(ptr %cert_file, ptr %key_file, ptr %ca_file, ptr %alpn_list, i64 %verify_peer)" };
  { march_name = "tls_connect"; c_name = Some "march_tls_connect"; ret_ty = Some (Tir.TCon ("Result", [Tir.TInt; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_tls_connect(i64 %fd, i64 %ctx_handle, ptr %hostname)" };
  { march_name = "tls_accept"; c_name = Some "march_tls_accept"; ret_ty = Some (Tir.TCon ("Result", [Tir.TInt; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_tls_accept(i64 %fd, i64 %ctx_handle)" };
  { march_name = "tls_read"; c_name = Some "march_tls_read"; ret_ty = Some (Tir.TCon ("Result", [Tir.TString; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_tls_read(i64 %ssl_handle, i64 %max_bytes)" };
  { march_name = "tls_read_timeout"; c_name = Some "march_tls_read_timeout"; ret_ty = Some (Tir.TCon ("Result", [Tir.TCon ("Option", [Tir.TString]); Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_tls_read_timeout(i64 %ssl_handle, i64 %max_bytes, i64 %timeout_ms)" };
  { march_name = "tls_write"; c_name = Some "march_tls_write"; ret_ty = Some (Tir.TCon ("Result", [Tir.TInt; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_tls_write(i64 %ssl_handle, ptr %data)" };
  { march_name = "tls_close"; c_name = Some "march_tls_close"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare void @march_tls_close(i64 %ssl_handle)" };
  { march_name = "tls_ctx_free"; c_name = Some "march_tls_ctx_free"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare void @march_tls_ctx_free(i64 %ctx_handle)" };
  { march_name = "tls_negotiated_alpn"; c_name = Some "march_tls_negotiated_alpn"; ret_ty = Some (Tir.TCon ("Option", [Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_tls_negotiated_alpn(i64 %ssl_handle)" };
  { march_name = "tls_peer_cn"; c_name = Some "march_tls_peer_cn"; ret_ty = Some (Tir.TCon ("Option", [Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_tls_peer_cn(i64 %ssl_handle)" };
  { march_name = "typed_array_create"; c_name = Some "march_typed_array_create"; ret_ty = Some (Tir.TVar "a");
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_typed_array_create(i64 %len, ptr %default_val)" };
  { march_name = "typed_array_from_list"; c_name = Some "march_typed_array_from_list"; ret_ty = Some (Tir.TVar "a");
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_typed_array_from_list(ptr %list)" };
  { march_name = "typed_array_to_list"; c_name = Some "march_typed_array_to_list"; ret_ty = Some (Tir.TCon ("List", [Tir.TVar "a"]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_typed_array_to_list(ptr %arr)" };
  { march_name = "typed_array_length"; c_name = Some "march_typed_array_length"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_typed_array_length(ptr %arr)" };
  { march_name = "typed_array_get"; c_name = Some "march_typed_array_get"; ret_ty = Some (Tir.TVar "a");
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_typed_array_get(ptr %arr, i64 %i)" };
  { march_name = "typed_array_set"; c_name = Some "march_typed_array_set"; ret_ty = Some (Tir.TVar "a");
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_typed_array_set(ptr %arr, i64 %i, ptr %val)" };
  { march_name = "typed_array_map"; c_name = Some "march_typed_array_map"; ret_ty = Some (Tir.TVar "a");
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_typed_array_map(ptr %arr, ptr %f)" };
  { march_name = "typed_array_filter"; c_name = Some "march_typed_array_filter"; ret_ty = Some (Tir.TVar "a");
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_typed_array_filter(ptr %arr, ptr %f)" };
  { march_name = "typed_array_fold"; c_name = Some "march_typed_array_fold"; ret_ty = Some (Tir.TVar "a");
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_typed_array_fold(ptr %arr, ptr %acc, ptr %f)" };
  { march_name = "native_int_arr_make"; c_name = None; ret_ty = Some (Tir.TCon ("NativeIntArr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_int_arr_make(i64 %len, i64 %def)" };
  { march_name = "native_int_arr_length"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64    @native_int_arr_length(ptr %arr)" };
  { march_name = "native_int_arr_get"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64    @native_int_arr_get(ptr %arr, i64 %i)" };
  { march_name = "native_int_arr_set"; c_name = None; ret_ty = Some (Tir.TCon ("NativeIntArr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_int_arr_set(ptr %arr, i64 %i, i64 %val)" };
  { march_name = "native_int_arr_sum"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64    @native_int_arr_sum(ptr %arr)" };
  { march_name = "native_int_arr_min"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64    @native_int_arr_min(ptr %arr)" };
  { march_name = "native_int_arr_max"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64    @native_int_arr_max(ptr %arr)" };
  { march_name = "native_int_arr_sumsq_dev"; c_name = None; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @native_int_arr_sumsq_dev(ptr %arr, double %mean)" };
  { march_name = "native_int_arr_map"; c_name = None; ret_ty = Some (Tir.TCon ("NativeIntArr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_int_arr_map(ptr %arr, ptr %f)" };
  { march_name = "native_int_arr_map2"; c_name = None; ret_ty = Some (Tir.TCon ("NativeIntArr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_int_arr_map2(ptr %arr1, ptr %arr2, ptr %f)" };
  { march_name = "native_int_arr_to_float_arr"; c_name = None; ret_ty = Some (Tir.TCon ("NativeFloatArr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_int_arr_to_float_arr(ptr %arr)" };
  { march_name = "native_int_arr_fold"; c_name = None; ret_ty = Some (Tir.TVar "a");
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_int_arr_fold(ptr %acc, ptr %arr, ptr %f)" };
  { march_name = "native_int_arr_from_list"; c_name = None; ret_ty = Some (Tir.TCon ("NativeIntArr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_int_arr_from_list(ptr %lst)" };
  { march_name = "native_int_arr_to_list"; c_name = None; ret_ty = Some (Tir.TCon ("List", [Tir.TInt]));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_int_arr_to_list(ptr %arr)" };
  { march_name = "native_int_arr_filter_mask"; c_name = None; ret_ty = Some (Tir.TCon ("NativeIntArr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_int_arr_filter_mask(ptr %arr, ptr %mask)" };
  { march_name = "native_float_arr_make"; c_name = None; ret_ty = Some (Tir.TCon ("NativeFloatArr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_float_arr_make(i64 %len, double %def)" };
  { march_name = "native_float_arr_length"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64    @native_float_arr_length(ptr %arr)" };
  { march_name = "native_float_arr_get"; c_name = None; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @native_float_arr_get(ptr %arr, i64 %i)" };
  { march_name = "native_float_arr_set"; c_name = None; ret_ty = Some (Tir.TCon ("NativeFloatArr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_float_arr_set(ptr %arr, i64 %i, double %val)" };
  { march_name = "native_float_arr_sum"; c_name = None; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @native_float_arr_sum(ptr %arr)" };
  { march_name = "native_float_arr_min"; c_name = None; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @native_float_arr_min(ptr %arr)" };
  { march_name = "native_float_arr_max"; c_name = None; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @native_float_arr_max(ptr %arr)" };
  { march_name = "native_float_arr_sumsq_dev"; c_name = None; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @native_float_arr_sumsq_dev(ptr %arr, double %mean)" };
  { march_name = "native_float_arr_map"; c_name = None; ret_ty = Some (Tir.TCon ("NativeFloatArr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_float_arr_map(ptr %arr, ptr %f)" };
  { march_name = "native_float_arr_map2"; c_name = None; ret_ty = Some (Tir.TCon ("NativeFloatArr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_float_arr_map2(ptr %arr1, ptr %arr2, ptr %f)" };
  { march_name = "native_float_arr_fold"; c_name = None; ret_ty = Some (Tir.TVar "a");
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_float_arr_fold(ptr %acc, ptr %arr, ptr %f)" };
  { march_name = "native_float_arr_from_list"; c_name = None; ret_ty = Some (Tir.TCon ("NativeFloatArr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_float_arr_from_list(ptr %lst)" };
  { march_name = "native_float_arr_to_list"; c_name = None; ret_ty = Some (Tir.TCon ("List", [Tir.TFloat]));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_float_arr_to_list(ptr %arr)" };
  { march_name = "native_float_arr_filter_mask"; c_name = None; ret_ty = Some (Tir.TCon ("NativeFloatArr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_float_arr_filter_mask(ptr %arr, ptr %mask)" };
  (* Narrow element widths: f32/i32/u8 (P10 narrow native array types). *)
  { march_name = "native_f32_arr_make"; c_name = None; ret_ty = Some (Tir.TCon ("NativeF32Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_f32_arr_make(i64 %len, double %def)" };
  { march_name = "native_f32_arr_length"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64    @native_f32_arr_length(ptr %arr)" };
  { march_name = "native_f32_arr_get"; c_name = None; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @native_f32_arr_get(ptr %arr, i64 %i)" };
  { march_name = "native_f32_arr_set"; c_name = None; ret_ty = Some (Tir.TCon ("NativeF32Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_f32_arr_set(ptr %arr, i64 %i, double %v)" };
  { march_name = "native_f32_arr_sum"; c_name = None; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @native_f32_arr_sum(ptr %arr)" };
  { march_name = "native_f32_arr_map"; c_name = None; ret_ty = Some (Tir.TCon ("NativeF32Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_f32_arr_map(ptr %arr, ptr %f)" };
  { march_name = "native_f32_arr_map2"; c_name = None; ret_ty = Some (Tir.TCon ("NativeF32Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_f32_arr_map2(ptr %a, ptr %b, ptr %f)" };
  { march_name = "native_f32_arr_fold"; c_name = None; ret_ty = Some (Tir.TVar "a");
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_f32_arr_fold(ptr %acc, ptr %arr, ptr %f)" };
  { march_name = "native_f32_arr_from_list"; c_name = None; ret_ty = Some (Tir.TCon ("NativeF32Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_f32_arr_from_list(ptr %lst)" };
  { march_name = "native_f32_arr_to_list"; c_name = None; ret_ty = Some (Tir.TCon ("List", [Tir.TFloat]));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_f32_arr_to_list(ptr %arr)" };
  { march_name = "native_i32_arr_make"; c_name = None; ret_ty = Some (Tir.TCon ("NativeI32Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_i32_arr_make(i64 %len, i64 %def)" };
  { march_name = "native_i32_arr_length"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64    @native_i32_arr_length(ptr %arr)" };
  { march_name = "native_i32_arr_get"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64    @native_i32_arr_get(ptr %arr, i64 %i)" };
  { march_name = "native_i32_arr_set"; c_name = None; ret_ty = Some (Tir.TCon ("NativeI32Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_i32_arr_set(ptr %arr, i64 %i, i64 %v)" };
  { march_name = "native_i32_arr_sum"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64    @native_i32_arr_sum(ptr %arr)" };
  { march_name = "native_i32_arr_map"; c_name = None; ret_ty = Some (Tir.TCon ("NativeI32Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_i32_arr_map(ptr %arr, ptr %f)" };
  { march_name = "native_i32_arr_map2"; c_name = None; ret_ty = Some (Tir.TCon ("NativeI32Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_i32_arr_map2(ptr %a, ptr %b, ptr %f)" };
  { march_name = "native_i32_arr_fold"; c_name = None; ret_ty = Some (Tir.TVar "a");
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_i32_arr_fold(ptr %acc, ptr %arr, ptr %f)" };
  { march_name = "native_i32_arr_from_list"; c_name = None; ret_ty = Some (Tir.TCon ("NativeI32Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_i32_arr_from_list(ptr %lst)" };
  { march_name = "native_i32_arr_to_list"; c_name = None; ret_ty = Some (Tir.TCon ("List", [Tir.TInt]));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_i32_arr_to_list(ptr %arr)" };
  { march_name = "native_u8_arr_make"; c_name = None; ret_ty = Some (Tir.TCon ("NativeU8Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_u8_arr_make(i64 %len, i64 %def)" };
  { march_name = "native_u8_arr_length"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64    @native_u8_arr_length(ptr %arr)" };
  { march_name = "native_u8_arr_get"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64    @native_u8_arr_get(ptr %arr, i64 %i)" };
  { march_name = "native_u8_arr_set"; c_name = None; ret_ty = Some (Tir.TCon ("NativeU8Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_u8_arr_set(ptr %arr, i64 %i, i64 %v)" };
  { march_name = "native_u8_arr_sum"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64    @native_u8_arr_sum(ptr %arr)" };
  { march_name = "native_u8_arr_map"; c_name = None; ret_ty = Some (Tir.TCon ("NativeU8Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_u8_arr_map(ptr %arr, ptr %f)" };
  { march_name = "native_u8_arr_map2"; c_name = None; ret_ty = Some (Tir.TCon ("NativeU8Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_u8_arr_map2(ptr %a, ptr %b, ptr %f)" };
  { march_name = "native_u8_arr_fold"; c_name = None; ret_ty = Some (Tir.TVar "a");
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_u8_arr_fold(ptr %acc, ptr %arr, ptr %f)" };
  { march_name = "native_u8_arr_from_list"; c_name = None; ret_ty = Some (Tir.TCon ("NativeU8Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_u8_arr_from_list(ptr %lst)" };
  { march_name = "native_u8_arr_to_list"; c_name = None; ret_ty = Some (Tir.TCon ("List", [Tir.TInt]));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_u8_arr_to_list(ptr %arr)" };
  { march_name = "native_float_to_f32_arr"; c_name = None; ret_ty = Some (Tir.TCon ("NativeF32Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_float_to_f32_arr(ptr %arr)" };
  { march_name = "native_f32_to_float_arr"; c_name = None; ret_ty = Some (Tir.TCon ("NativeFloatArr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_f32_to_float_arr(ptr %arr)" };
  { march_name = "native_int_to_i32_arr"; c_name = None; ret_ty = Some (Tir.TCon ("NativeI32Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_int_to_i32_arr(ptr %arr)" };
  { march_name = "native_i32_to_int_arr"; c_name = None; ret_ty = Some (Tir.TCon ("NativeIntArr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_i32_to_int_arr(ptr %arr)" };
  { march_name = "native_int_to_u8_arr"; c_name = None; ret_ty = Some (Tir.TCon ("NativeU8Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_int_to_u8_arr(ptr %arr)" };
  { march_name = "native_u8_to_int_arr"; c_name = None; ret_ty = Some (Tir.TCon ("NativeIntArr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_u8_to_int_arr(ptr %arr)" };
  { march_name = "native_i32_to_f32_arr"; c_name = None; ret_ty = Some (Tir.TCon ("NativeF32Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_i32_to_f32_arr(ptr %arr)" };
  { march_name = "native_u8_to_f32_arr"; c_name = None; ret_ty = Some (Tir.TCon ("NativeF32Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_u8_to_f32_arr(ptr %arr)" };
  (* Uninitialized-allocation helpers used only by llvm_emit's inline map-loop
     codegen (native_map_inline.ml) — never called from March source. *)
  { march_name = "native_int_arr_alloc_raw"; c_name = None; ret_ty = Some (Tir.TCon ("NativeIntArr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_int_arr_alloc_raw(i64 %len)" };
  { march_name = "native_float_arr_alloc_raw"; c_name = None; ret_ty = Some (Tir.TCon ("NativeFloatArr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_float_arr_alloc_raw(i64 %len)" };
  { march_name = "native_f32_arr_alloc_raw"; c_name = None; ret_ty = Some (Tir.TCon ("NativeF32Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_f32_arr_alloc_raw(i64 %len)" };
  { march_name = "native_i32_arr_alloc_raw"; c_name = None; ret_ty = Some (Tir.TCon ("NativeI32Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_i32_arr_alloc_raw(i64 %len)" };
  { march_name = "native_u8_arr_alloc_raw"; c_name = None; ret_ty = Some (Tir.TCon ("NativeU8Arr", []));
    in_is_builtin = true; declare_sig = Some "declare ptr    @native_u8_arr_alloc_raw(i64 %len)" };
  { march_name = "native_arr_map2_check_len"; c_name = None; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare void   @native_arr_map2_check_len(i64 %len1, i64 %len2)" };
  (* RingBuf — mutable fixed-capacity circular buffer (runtime/march_runtime.c).
     Elements are erased (TVar "_"); the buffer stores/returns the uniform
     march_value word, so push/pop/get/peek/to_list all use "ptr" element slots
     and pop/get/peek return niche-encoded Option(a) (None=0, Some(v)=v). *)
  { march_name = "ring_buf_make"; c_name = None; ret_ty = Some (Tir.TCon ("RingBuf", [Tir.TVar "_"]));
    in_is_builtin = true; declare_sig = Some "declare ptr    @ring_buf_make(i64 %cap)" };
  { march_name = "ring_buf_push"; c_name = None; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare void   @ring_buf_push(ptr %rb, ptr %x)" };
  { march_name = "ring_buf_pop"; c_name = None; ret_ty = Some (Tir.TCon ("Option", [Tir.TVar "_"]));
    in_is_builtin = true; declare_sig = Some "declare ptr    @ring_buf_pop(ptr %rb)" };
  { march_name = "ring_buf_get"; c_name = None; ret_ty = Some (Tir.TCon ("Option", [Tir.TVar "_"]));
    in_is_builtin = true; declare_sig = Some "declare ptr    @ring_buf_get(ptr %rb, i64 %i)" };
  { march_name = "ring_buf_peek_oldest"; c_name = None; ret_ty = Some (Tir.TCon ("Option", [Tir.TVar "_"]));
    in_is_builtin = true; declare_sig = Some "declare ptr    @ring_buf_peek_oldest(ptr %rb)" };
  { march_name = "ring_buf_peek_newest"; c_name = None; ret_ty = Some (Tir.TCon ("Option", [Tir.TVar "_"]));
    in_is_builtin = true; declare_sig = Some "declare ptr    @ring_buf_peek_newest(ptr %rb)" };
  { march_name = "ring_buf_size"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64    @ring_buf_size(ptr %rb)" };
  { march_name = "ring_buf_cap"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64    @ring_buf_cap(ptr %rb)" };
  { march_name = "ring_buf_clear"; c_name = None; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare void   @ring_buf_clear(ptr %rb)" };
  { march_name = "ring_buf_to_list"; c_name = None; ret_ty = Some (Tir.TCon ("List", [Tir.TVar "_"]));
    in_is_builtin = true; declare_sig = Some "declare ptr    @ring_buf_to_list(ptr %rb)" };
  { march_name = "unix_time"; c_name = Some "march_unix_time"; ret_ty = Some Tir.TFloat;
    in_is_builtin = true; declare_sig = Some "declare double @march_unix_time()" };
  { march_name = "unix_time_ms"; c_name = Some "march_unix_time_ms"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64    @march_unix_time_ms()" };
  (* peak_rss_bytes: process self-inspection, not capability-gated (see
     typecheck.ml — deliberately absent from the capability table). *)
  { march_name = "peak_rss_bytes"; c_name = Some "march_peak_rss_bytes"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_peak_rss_bytes()" };
  (* live_allocs: net live march_alloc count; ambient for the same reason as
     peak_rss_bytes above. Exact and platform-independent — see typecheck.ml. *)
  { march_name = "live_allocs"; c_name = Some "march_live_allocs"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_live_allocs()" };
  { march_name = "tcp_connect"; c_name = Some "march_tcp_connect"; ret_ty = Some (Tir.TCon ("Result", [Tir.TInt; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_tcp_connect(ptr %host, i64 %port)" };
  { march_name = "http_serialize_request"; c_name = Some "march_http_serialize_request"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_http_serialize_request(ptr %method, ptr %host, ptr %path, ptr %query, ptr %headers, ptr %body)" };
  { march_name = "http_parse_response"; c_name = Some "march_http_parse_response"; ret_ty = Some (Tir.TCon ("Result", [Tir.TVar "a"; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_http_parse_response(ptr %raw)" };
  { march_name = "csv_open"; c_name = Some "march_csv_open"; ret_ty = Some (Tir.TCon ("Result", [Tir.TVar "a"; Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_csv_open(ptr %path, ptr %delim, ptr %mode)" };
  { march_name = "csv_next_row"; c_name = Some "march_csv_next_row"; ret_ty = Some (Tir.TCon ("Option", [Tir.TCon ("List", [Tir.TString])]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_csv_next_row(ptr %handle)" };
  { march_name = "csv_close"; c_name = Some "march_csv_close"; ret_ty = Some (Tir.TPtr Tir.TUnit);
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_csv_close(ptr %handle)" };
  { march_name = "own"; c_name = Some "march_own"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare void @march_own(ptr %pid, ptr %value)" };
  { march_name = "cap_narrow"; c_name = Some "march_cap_narrow"; ret_ty = Some (Tir.TCon ("Cap", [Tir.TVar "a"]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_cap_narrow(ptr %cap)" };
  (* mint_cap — the gated proof-cap mint.  It has its OWN symbol rather than
     aliasing march_cap_narrow: a mint must not inherit the dictionary of the
     Cap(IO) it was minted from (see march_mint_cap), and the alias returned
     its argument.  That agreed with the interpreter only while a Cap(IO) was
     always NULL. *)
  { march_name = "mint_cap"; c_name = Some "march_mint_cap"; ret_ty = Some (Tir.TCon ("Cap", [Tir.TVar "a"]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_mint_cap(ptr %cap)" };
  (* cap_impl / cap_dict — capability runtime dictionaries.  Both are
     identity-shaped at the machine level: a capability is NULL-or-dictionary,
     and Option is niche-encoded (None = 0, Some(x) = x, lib/tir/repr.ml), so
     [cap_dict] needs no encoding step at all.  The shims exist for the
     REFERENCE COUNTING, not the value — see the ownership note in
     runtime/march_runtime.c. *)
  { march_name = "cap_impl"; c_name = Some "march_cap_impl"; ret_ty = Some (Tir.TCon ("Cap", [Tir.TVar "a"]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_cap_impl(ptr %cap, ptr %dict)" };
  { march_name = "cap_dict"; c_name = Some "march_cap_dict"; ret_ty = Some (Tir.TCon ("Option", [Tir.TVar "a"]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_cap_dict(ptr %cap)" };
  { march_name = "demonitor"; c_name = Some "march_demonitor"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare void @march_demonitor(i64 %ref)" };
  { march_name = "monitor"; c_name = Some "march_monitor"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_monitor(ptr %watcher, ptr %target)" };
  { march_name = "mailbox_size"; c_name = Some "march_mailbox_size"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_mailbox_size(ptr %pid)" };
  { march_name = "sched_stat"; c_name = Some "march_sched_stat"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_sched_stat(i64 %which)" };
  { march_name = "actor_set_mailbox_limit"; c_name = Some "march_actor_set_mbox_limit"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare void @march_actor_set_mbox_limit(ptr %pid, i64 %limit, i64 %policy)" };
  { march_name = "run_until_idle"; c_name = Some "march_run_until_idle"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare void @march_run_until_idle()" };
  { march_name = "register_resource"; c_name = Some "march_register_resource"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare void @march_register_resource(ptr %pid, ptr %name, ptr %cleanup)" };
  (* Named registry (Task 4). C signature is march_actor_register(name, actor)
     — name FIRST — but the March-level builtin is Pid -> String -> Bool (pid
     first, matching monitor/kill's argument order). The call site in
     llvm_emit.ml has a dedicated EApp arm that swaps the two atoms into the
     C order; this declare_sig documents the real callee signature. *)
  { march_name = "actor_register"; c_name = Some "march_actor_register"; ret_ty = Some Tir.TBool;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_actor_register(ptr %name, ptr %actor)" };
  { march_name = "actor_unregister"; c_name = Some "march_actor_unregister"; ret_ty = Some Tir.TBool;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_actor_unregister(ptr %name)" };
  (* Niche-encoded Option, matching vault_get's precedent: NULL is None, the
     actor pointer itself is Some — no boxed cell. *)
  { march_name = "actor_whereis"; c_name = Some "march_actor_whereis";
    ret_ty = Some (Tir.TCon ("Option", [Tir.TPtr Tir.TUnit]));
    in_is_builtin = true;
    declare_sig = Some "declare ptr  @march_actor_whereis(ptr %name)" };
  { march_name = "actor_registered"; c_name = Some "march_actor_registered";
    ret_ty = Some (Tir.TCon ("List", [Tir.TString]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_actor_registered()" };
  { march_name = "get_cap"; c_name = Some "march_get_cap"; ret_ty = Some (Tir.TCon ("Option", [Tir.TCon ("ActorCap", [Tir.TVar "a"])]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_get_cap(ptr %pid)" };
  { march_name = "send_checked"; c_name = Some "march_send_checked"; ret_ty = Some (Tir.TCon ("Atom", []));
    in_is_builtin = true; declare_sig = Some "declare i64  @march_send_checked(ptr %cap, ptr %msg)" };
  { march_name = "revoke_cap"; c_name = Some "march_revoke_cap"; ret_ty = Some (Tir.TCon ("Atom", []));
    in_is_builtin = true; declare_sig = Some "declare i64  @march_revoke_cap(ptr %cap)" };
  { march_name = "is_cap_valid"; c_name = Some "march_is_cap_valid"; ret_ty = Some Tir.TBool;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_is_cap_valid(ptr %cap)" };
  { march_name = "pid_of_int"; c_name = Some "march_pid_of_int"; ret_ty = Some (Tir.TCon ("Pid", [Tir.TVar "a"]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_pid_of_int(i64 %n)" };
  { march_name = "get_actor_field"; c_name = Some "march_get_actor_field"; ret_ty = Some (Tir.TCon ("Option", [Tir.TVar "a"]));
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_get_actor_field(ptr %pid, ptr %name)" };
  { march_name = "register_supervisor"; c_name = Some "march_register_supervisor"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare void @march_register_supervisor(ptr %supervisor, i64 %strategy, i64 %max_restarts, i64 %window_secs)" };
  { march_name = "register_supervisor_child"; c_name = Some "march_actor_register_child"; ret_ty = Some Tir.TUnit;
    in_is_builtin = true; declare_sig = Some "declare void @march_actor_register_child(ptr %sup, ptr %child, ptr %spawn_fn, i64 %word_idx, i64 %restart_type)" };
  { march_name = "pid_index_of"; c_name = Some "march_pid_index_of"; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = Some "declare i64  @march_pid_index_of(ptr %actor)" };
  { march_name = "to_string"; c_name = Some "march_value_to_string"; ret_ty = Some Tir.TString;
    in_is_builtin = true; declare_sig = Some "declare ptr  @march_value_to_string(ptr %v)" };
  { march_name = "chan_new"; c_name = Some "march_chan_new"; ret_ty = Some (Tir.TTuple [Tir.TCon ("Chan", []); Tir.TCon ("Chan", [])]);
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_chan_new(ptr %proto_name)" };
  { march_name = "chan_send"; c_name = Some "march_chan_send"; ret_ty = Some (Tir.TCon ("Chan", []));
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_chan_send(ptr %ep, ptr %val)" };
  { march_name = "chan_recv"; c_name = Some "march_chan_recv"; ret_ty = Some (Tir.TTuple [Tir.TPtr Tir.TUnit; Tir.TCon ("Chan", [])]);
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_chan_recv(ptr %ep)" };
  { march_name = "chan_close"; c_name = Some "march_chan_close"; ret_ty = Some Tir.TUnit;
    in_is_builtin = false; declare_sig = Some "declare i64  @march_chan_close(ptr %ep)" };
  { march_name = "chan_choose"; c_name = Some "march_chan_choose"; ret_ty = Some (Tir.TCon ("Chan", []));
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_chan_choose(ptr %ep, ptr %label)" };
  { march_name = "chan_offer"; c_name = Some "march_chan_offer"; ret_ty = Some (Tir.TTuple [Tir.TPtr Tir.TUnit; Tir.TCon ("Chan", [])]);
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_chan_offer(ptr %ep)" };
  { march_name = "mpst_new"; c_name = Some "march_mpst_new"; ret_ty = Some (Tir.TPtr Tir.TUnit);
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_mpst_new(ptr %proto_name, i64 %n_roles, ptr %roles_csv)" };
  { march_name = "mpst_send"; c_name = Some "march_mpst_send"; ret_ty = Some (Tir.TCon ("Chan", []));
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_mpst_send(ptr %ep, ptr %target_role, ptr %val)" };
  { march_name = "mpst_recv"; c_name = Some "march_mpst_recv"; ret_ty = Some (Tir.TTuple [Tir.TPtr Tir.TUnit; Tir.TCon ("Chan", [])]);
    in_is_builtin = false; declare_sig = Some "declare ptr  @march_mpst_recv(ptr %ep, ptr %source_role)" };
  { march_name = "mpst_close"; c_name = Some "march_mpst_close"; ret_ty = Some Tir.TUnit;
    in_is_builtin = false; declare_sig = Some "declare i64  @march_mpst_close(ptr %ep)" };
  { march_name = "+"; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = "-"; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = "*"; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = "/"; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = "%"; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = "+."; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = "-."; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = "*."; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = "/."; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = "=="; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = "!="; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = "<"; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = "<="; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = ">"; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = ">="; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = "task_spawn"; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = "task_await"; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = "task_await_unwrap"; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = "task_yield"; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = "task_spawn_steal"; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = "task_reductions"; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = "pmap_threshold"; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = "get_work_pool"; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = "int_and"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = None };
  { march_name = "int_or"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = None };
  { march_name = "int_xor"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = None };
  { march_name = "int_not"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = None };
  { march_name = "int_shl"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = None };
  { march_name = "int_shr"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = None };
  { march_name = "int_popcount"; c_name = None; ret_ty = Some Tir.TInt;
    in_is_builtin = true; declare_sig = None };
  { march_name = "remote_ref_hashes"; c_name = None; ret_ty = None;
    in_is_builtin = true; declare_sig = None };
  { march_name = "main"; c_name = Some "march_main"; ret_ty = None;
    in_is_builtin = false; declare_sig = None };
]

(* ── Preamble text assembly ──────────────────────────────────────────── *)

(** One physical line of the hand-written preamble blob, replayed in the
    ORIGINAL blob's exact order.  [PDeclare c_name] resolves its text via
    [declare_text] (below) rather than storing the text twice — the
    single string source of truth is [builtin.declare_sig] /
    [runtime_only_declares]. *)
type preamble_item =
  | PComment of string   (** a `; ...` line, printed verbatim *)
  | PDeclare of string    (** C symbol to look up and print its `declare` line *)
  | POther   of string    (** a non-declare, non-comment line (the WASM
                               [@march_tls_reductions] plain-global line) *)
  | PBlank                (** one blank line *)

(** C-runtime declares with no March-callable name at all: RC ops, Hot
    Code Reload / versioned-dispatch machinery, the test harness, LLVM
    intrinsics, the REPL persistent-slot table, and internal task/scheduler
    primitives invoked by dedicated codegen rather than by name-based
    [mangle_extern] dispatch. These still need a preamble declare line but
    have no [builtin] row (there is no March source name to key one on). *)
let runtime_only_declares : (string * string) list = [
  ("march_dispatch_enter", "declare ptr  @march_dispatch_enter(i32 %name_id, ptr %out_version)");
  ("march_dispatch_enter_gen", "declare ptr  @march_dispatch_enter_gen(i32 %name_id, i32 %caller_epoch, ptr %out_version)");
  ("march_dispatch_leave", "declare void @march_dispatch_leave(i32 %name_id, i32 %version)");
  ("march_dispatch_publish", "declare i32  @march_dispatch_publish(i32 %name_id, ptr %fn, ptr %impl_hash, ptr %sig_hash, i8 %kind)");
  ("march_dispatch_publish_epoch", "declare i32  @march_dispatch_publish_epoch(i32 %name_id, ptr %fn, ptr %impl_hash, ptr %sig_hash, i8 %kind, i32 %epoch)");
  ("march_dispatch_init", "declare void @march_dispatch_init(i32 %n_slots)");
  ("march_dispatch_register_name", "declare void @march_dispatch_register_name(i32, ptr)");
  ("march_reload_server_start", "declare void @march_reload_server_start(ptr)");
  ("march_actor_set_dispatch_id", "declare void @march_actor_set_dispatch_id(ptr %actor, i32 %name_id)");
  ("march_actor_set_call_base", "declare void @march_actor_set_call_base(ptr %actor, i64 %base)");
  ("getenv", "declare ptr  @getenv(ptr)");
  ("march_alloc", "declare noalias nonnull ptr @march_alloc(i64 %sz) allocsize(0)");
  ("march_incrc", "declare void @march_incrc(ptr %p)");
  ("march_decrc", "declare void @march_decrc(ptr %p)");
  ("march_decrc_freed", "declare i64  @march_decrc_freed(ptr %p)");
  ("march_incrc_local", "declare void @march_incrc_local(ptr %p)");
  ("march_decrc_local", "declare void @march_decrc_local(ptr %p)");
  ("march_free", "declare void @march_free(ptr %p)");
  ("march_test_init", "declare void @march_test_init(i32 %argc, ptr %argv)");
  ("march_test_run", "declare void @march_test_run(ptr %fn, ptr %name, ptr %setup_or_null)");
  ("march_test_setup_all", "declare void @march_test_setup_all(ptr %fn)");
  ("march_test_report", "declare i32  @march_test_report()");
  ("march_string_lit", "declare ptr  @march_string_lit(ptr %s, i64 %len)");
  ("march_string_lit_static", "declare ptr  @march_string_lit_static(ptr %s, i64 %len, ptr %cell)");
  ("march_record_shape_intern", "declare i32  @march_record_shape_intern(ptr %desc)");
  ("march_record_set_shape", "declare void @march_record_set_shape(ptr %rec, ptr %desc, ptr %cache)");
  ("march_record_put", "declare ptr  @march_record_put(ptr %rec, ptr %key, ptr %val, i64 %kind)");
  ("march_record_from_list_k", "declare ptr  @march_record_from_list_k(ptr %list, i64 %kind)");
  ("march_record_field_dyn", "declare ptr  @march_record_field_dyn(ptr %rec, ptr %name, i64 %len)");
  ("march_record_update_dyn", "declare ptr  @march_record_update_dyn(ptr %rec, i64 %n, ...)");
  ("march_checked_fdiv", "declare double @march_checked_fdiv(double %a, double %b)");
  ("march_checked_idiv", "declare i64    @march_checked_idiv(i64 %a, i64 %b)");
  ("march_checked_imod", "declare i64    @march_checked_imod(i64 %a, i64 %b)");
  ("march_checked_emod", "declare i64    @march_checked_emod(i64 %a, i64 %b)");
  ("march_checked_ediv", "declare i64    @march_checked_ediv(i64 %a, i64 %b)");
  ("march_checked_div_op", "declare i64    @march_checked_div_op(i64 %a, i64 %b)");
  ("march_checked_mod_op", "declare i64    @march_checked_mod_op(i64 %a, i64 %b)");
  ("march_poly_eq", "declare i64  @march_poly_eq(ptr %a, ptr %b)");
  ("march_remote_init", "declare void @march_remote_init()");
  ("march_int_pow", "declare i64  @march_int_pow(i64 %base, i64 %exp)");
  ("llvm.ctpop.i64", "declare i64  @llvm.ctpop.i64(i64 %val)");
  ("llvm.abs.i64", "declare i64  @llvm.abs.i64(i64 %val, i1 %is_int_min_poison)");
  ("llvm.stacksave", "declare ptr  @llvm.stacksave()");
  ("llvm.stackrestore", "declare void @llvm.stackrestore(ptr %ptr)");
  ("march_repl_get", "declare i64  @march_repl_get(i64 %slot)");
  ("march_repl_set", "declare void @march_repl_set(i64 %slot, i64 %val)");
  ("march_msg_copy", "declare ptr  @march_msg_copy(ptr %src_heap, ptr %dst_heap, ptr %value)");
  ("march_msg_move", "declare ptr  @march_msg_move(ptr %src_heap, ptr %dst_heap, ptr %value)");
  ("march_process_alloc", "declare ptr  @march_process_alloc(ptr %heap, i64 %sz)");
  ("march_run_scheduler", "declare void @march_run_scheduler()");
  ("march_task_spawn_thunk", "declare ptr  @march_task_spawn_thunk(ptr %clo_ptr)");
  ("march_task_await", "declare ptr  @march_task_await(ptr %task)");
  ("march_task_await_value", "declare ptr  @march_task_await_value(ptr %task)");
  ("march_sched_yield", "declare void @march_sched_yield()");
  ("march_cancel_token_new", "declare ptr  @march_cancel_token_new()");
  ("march_cancel_token_cancel", "declare void @march_cancel_token_cancel(ptr %tok)");
  ("march_cancel_token_is_cancelled", "declare i64  @march_cancel_token_is_cancelled(ptr %tok)");
  ("march_task_spawn_with_cancel_thunk", "declare ptr  @march_task_spawn_with_cancel_thunk(ptr %clo, ptr %tok)");
  ("march_task_cancel_by_id", "declare void @march_task_cancel_by_id(ptr %task)");
  ("march_yield_from_compiled", "declare void @march_yield_from_compiled()");
  ("march_signal_watch", "declare void @march_signal_watch(i64 %code, ptr %clo)");
  ("march_signal_unwatch", "declare void @march_signal_unwatch(i64 %code)");
  ("march_signal_raise_self", "declare void @march_signal_raise_self(i64 %code)");
  ("march_alloc_float", "declare ptr  @march_alloc_float(double %v)");
  ("march_unbox_float", "declare double @march_unbox_float(ptr %p)");
  ("march_poly_compare", "declare i64  @march_poly_compare(ptr %a, ptr %b)");
  ("march_simd_alloc", "declare ptr  @march_simd_alloc(i64 %kind)");
  ("march_simd_bounds_panic", "declare void @march_simd_bounds_panic(i64 %i, i64 %lanes, i64 %len)");
  ("march_simd_lane_panic", "declare void @march_simd_lane_panic(i64 %i, i64 %lanes)");
]

(** Look up the exact historical `declare ...` text for C symbol [c_name],
    checking builtin-table rows first — matched by [b.c_name] when a row has
    an explicit mangle-table mapping, or by [b.march_name] itself when
    [c_name = None] (a handful of rows, e.g. [march_compare_int]/
    [march_hash_string], ARE their own C symbol: no [mangle_extern] case
    renames them, so the March name IS the declared symbol — see
    [builtin.declare_sig]'s doc for why alias rows are not deduplicated
    away) — and falling back to [runtime_only_declares]. *)
let declare_text (c_name : string) : string =
  let from_builtins =
    List.find_map
      (fun b ->
         let sym = match b.c_name with Some c -> c | None -> b.march_name in
         if sym = c_name then b.declare_sig else None)
      builtins
  in
  match from_builtins with
  | Some s -> s
  | None ->
    (match List.assoc_opt c_name runtime_only_declares with
     | Some s -> s
     | None -> failwith ("Llvm_builtins.declare_text: no declare text for " ^ c_name))

let render_item (buf : Buffer.t) (item : preamble_item) : unit =
  match item with
  | PComment s -> Buffer.add_string buf s; Buffer.add_char buf '\n'
  | PDeclare c -> Buffer.add_string buf (declare_text c); Buffer.add_char buf '\n'
  | POther s   -> Buffer.add_string buf s; Buffer.add_char buf '\n'
  | PBlank     -> Buffer.add_char buf '\n'

let render_items (buf : Buffer.t) (items : preamble_item list) : unit =
  List.iter (render_item buf) items


let core_items : preamble_item list = [    (* always emitted, all targets *)
  PComment "; Runtime declarations";
  PComment "; Hot Code Reload versioned dispatch (runtime/march_dispatch.c)";
  PDeclare "march_dispatch_enter";
  PDeclare "march_dispatch_enter_gen";
  PDeclare "march_dispatch_leave";
  PDeclare "march_dispatch_publish";
  PDeclare "march_dispatch_publish_epoch";
  PDeclare "march_dispatch_init";
  PDeclare "march_dispatch_register_name";
  PDeclare "march_reload_server_start";
  PDeclare "march_actor_set_dispatch_id";
  PDeclare "march_actor_set_call_base";
  PDeclare "getenv";
  PDeclare "march_alloc";
  PDeclare "march_incrc";
  PDeclare "march_decrc";
  PDeclare "march_decrc_freed";
  PDeclare "march_incrc_local";
  PDeclare "march_decrc_local";
  PDeclare "march_free";
  PDeclare "march_print";
  PDeclare "march_panic";
  PDeclare "march_panic_ext";
  PDeclare "march_todo_ext";
  PDeclare "march_try_finally";
  PDeclare "march_test_init";
  PDeclare "march_test_run";
  PDeclare "march_test_setup_all";
  PDeclare "march_test_report";
  PDeclare "march_println";
  PDeclare "march_print_stderr";
  PDeclare "march_io_read_line";
  PDeclare "march_io_read_byte";
  PDeclare "march_string_lit";
  PDeclare "march_string_lit_static";
  PDeclare "march_html_auto_escape";
  PDeclare "march_html_escape_ctx";
  PDeclare "march_record_shape_intern";
  PDeclare "march_record_set_shape";
  PDeclare "march_record_keys";
  PDeclare "march_record_values";
  PDeclare "march_record_entries";
  PDeclare "march_record_get";
  PDeclare "march_record_has_key";
  PDeclare "march_record_put";
  PDeclare "march_record_put3";
  PDeclare "march_record_from_list";
  PDeclare "march_record_from_list_k";
  PDeclare "march_record_field_dyn";
  PDeclare "march_record_update_dyn";
  PDeclare "march_int_to_string";
  PDeclare "march_float_to_string";
  PDeclare "march_bool_to_string";
  PComment "; Checked float division — aborts on divisor == 0.0 instead of returning inf/NaN";
  PDeclare "march_checked_fdiv";
  PComment "; Checked integer division/remainder — panic on a zero divisor (matches interpreter)";
  PDeclare "march_checked_idiv";
  PDeclare "march_checked_imod";
  PDeclare "march_checked_emod";
  PDeclare "march_checked_ediv";
  PComment "; Operator forms of / and % — bare \"division by zero\" / \"modulo by zero\" messages";
  PDeclare "march_checked_div_op";
  PDeclare "march_checked_mod_op";
  PDeclare "march_string_concat";
  PDeclare "march_string_eq";
  PDeclare "march_poly_eq";
  PComment "; Ord / Hash builtins";
  PDeclare "march_compare_int";
  PDeclare "march_compare_float";
  PDeclare "march_compare_string";
  PDeclare "march_hash_int";
  PDeclare "march_hash_float";
  PDeclare "march_hash_string";
  PDeclare "march_hash_bool";
  PDeclare "march_string_byte_length";
  PDeclare "march_string_byte_at";
  PDeclare "march_string_is_empty";
  PDeclare "march_string_to_int";
  PDeclare "march_string_concat3";
  PDeclare "march_string_join";
  PComment "; Float builtins";
  PDeclare "march_float_abs";
  PDeclare "march_float_ceil";
  PDeclare "march_float_floor";
  PDeclare "march_float_round";
  PDeclare "march_float_truncate";
  PDeclare "march_int_to_float";
  PComment "; Char builtins";
  PDeclare "march_char_from_int";
  PDeclare "march_char_to_int";
  PDeclare "march_char_is_digit";
  PDeclare "march_char_is_alphanumeric";
  PDeclare "march_char_is_whitespace";
  PComment "; Float/Int conversion builtins";
  PDeclare "march_float_to_int";
  PComment "; Math builtins";
  PDeclare "march_math_sin";
  PDeclare "march_math_cos";
  PDeclare "march_math_tan";
  PDeclare "march_math_asin";
  PDeclare "march_math_acos";
  PDeclare "march_math_atan";
  PDeclare "march_math_atan2";
  PDeclare "march_math_sinh";
  PDeclare "march_math_cosh";
  PDeclare "march_math_tanh";
  PDeclare "march_math_sqrt";
  PDeclare "march_math_cbrt";
  PDeclare "march_math_exp";
  PDeclare "march_math_exp2";
  PDeclare "march_math_log";
  PDeclare "march_math_log2";
  PDeclare "march_math_log10";
  PDeclare "march_math_pow";
  PComment "; Extended string builtins";
  PDeclare "march_string_chars";
  PDeclare "march_string_to_codepoints";
  PDeclare "march_string_from_codepoint";
  PDeclare "march_string_from_chars";
  PDeclare "march_string_contains";
  PDeclare "march_string_starts_with";
  PDeclare "march_string_ends_with";
  PDeclare "march_string_slice";
  PDeclare "march_string_split";
  PDeclare "march_string_split_first";
  PDeclare "march_string_replace";
  PDeclare "march_string_replace_all";
  PDeclare "march_string_to_lowercase";
  PDeclare "march_string_to_uppercase";
  PDeclare "march_string_trim";
  PDeclare "march_string_trim_start";
  PDeclare "march_string_trim_end";
  PDeclare "march_string_repeat";
  PDeclare "march_string_reverse";
  PDeclare "march_string_pad_left";
  PDeclare "march_string_pad_right";
  PDeclare "march_string_grapheme_count";
  PDeclare "march_string_index_of";
  PDeclare "march_string_index_of_from";
  PDeclare "march_string_last_index_of";
  PDeclare "march_string_to_float";
  PComment "; List builtins";
  PDeclare "march_list_append";
  PDeclare "march_list_concat";
  PComment "; IOList builtins";
  PDeclare "march_iolist_hash_fnv1a";
  PComment "; Vault (key-value store) builtins";
  PDeclare "march_vault_new";
  PDeclare "march_vault_whereis";
  PDeclare "march_vault_set";
  PDeclare "march_vault_set_ttl";
  PDeclare "march_vault_put_new";
  PDeclare "march_vault_incr";
  PDeclare "march_vault_push_capped";
  PDeclare "march_vault_get";
  PDeclare "march_vault_drop";
  PDeclare "march_vault_update";
  PDeclare "march_vault_size";
  PDeclare "march_vault_keys";
  PDeclare "march_vault_ns_set";
  PDeclare "march_vault_ns_get";
  PDeclare "march_vault_ns_drop";
  PComment "; Crypto / hash builtins";
  PDeclare "march_md5";
  PDeclare "march_sha256";
  PDeclare "march_sha512";
  PDeclare "march_sha1_bytes";
  PDeclare "march_hmac_sha256";
  PDeclare "march_hmac_sha256_bytes";
  PDeclare "march_pbkdf2_sha256";
  PDeclare "march_base64_encode";
  PDeclare "march_base64_decode";
  PDeclare "march_random_bytes";
  PDeclare "bytes_to_u8_arr";
  PDeclare "u8_arr_to_bytes";
  PComment "; Compression builtins (runtime/march_compress.c)";
  PDeclare "march_gzip_encode";
  PDeclare "march_gzip_decode";
  PDeclare "march_deflate_encode";
  PDeclare "march_deflate_decode";
  PDeclare "march_zstd_encode";
  PDeclare "march_zstd_decode";
  PDeclare "march_brotli_encode";
  PDeclare "march_brotli_decode";
  PComment "; System introspection builtins";
  PDeclare "march_sys_uptime_ms";
  PDeclare "march_sys_heap_bytes";
  PDeclare "march_sys_word_size";
  PDeclare "march_sys_minor_gcs";
  PDeclare "march_sys_major_gcs";
  PDeclare "march_sys_actor_count";
  PDeclare "march_sys_cpu_count";
  PDeclare "march_sys_cpu_load_milli";
  PDeclare "march_sys_mem_total_bytes";
  PDeclare "march_sys_mem_available_bytes";
  PDeclare "march_sys_os";
  PDeclare "march_sys_arch";
  PDeclare "march_get_version";
  PComment "; UUID / identity builtins";
  PDeclare "march_uuid_v4";
  PComment "; Distributed OTP L4 — function-by-identity remote registry (march_remote_registry.c)";
  PDeclare "march_remote_init";
  PDeclare "march_remote_register";
  PDeclare "march_remote_count";
  PDeclare "march_remote_check_march";
  PDeclare "march_remote_invoke_march";
  PComment "; Integer math helpers";
  PDeclare "march_int_pow";
  PComment "; LLVM intrinsics";
  PDeclare "llvm.ctpop.i64";
  PDeclare "llvm.abs.i64";
  PDeclare "llvm.stacksave";
  PDeclare "llvm.stackrestore";
  PComment "; Logger builtins";
  PDeclare "march_logger_set_level";
  PDeclare "march_logger_get_level";
  PDeclare "march_logger_add_context";
  PDeclare "march_logger_clear_context";
  PDeclare "march_logger_get_context";
  PDeclare "march_logger_write";
  PComment "; REPL JIT persistent variable slot table (march_extras.c)";
  PDeclare "march_repl_get";
  PDeclare "march_repl_set";
  PBlank;
]

let native_actor_items : preamble_item list = [   (* native-only: actors + scheduler *)
  PComment "; Actor builtins";
  PDeclare "march_kill";
  PDeclare "march_is_alive";
  PDeclare "march_send";
  PDeclare "march_send_linear";
  PDeclare "march_msg_copy";
  PDeclare "march_msg_move";
  PDeclare "march_process_alloc";
  PDeclare "march_spawn";
  PDeclare "march_spawn_supervised";
  PDeclare "march_actor_get_int";
  PDeclare "march_actor_call";
  PDeclare "march_actor_reply";
  PDeclare "march_send_after";
  PDeclare "march_timer_cancel";
  PDeclare "march_run_scheduler";
  PDeclare "march_task_spawn_thunk";
  PDeclare "march_task_await";
  PDeclare "march_task_await_value";
  PDeclare "march_sched_yield";
  PDeclare "march_sched_recv";
  PDeclare "march_cancel_token_new";
  PDeclare "march_cancel_token_cancel";
  PDeclare "march_cancel_token_is_cancelled";
  PDeclare "march_task_spawn_with_cancel_thunk";
  PDeclare "march_task_cancel_by_id";
  PDeclare "march_signal_watch";
  PDeclare "march_signal_unwatch";
  PDeclare "march_signal_raise_self";
  PDeclare "march_alloc_float";
  PDeclare "march_unbox_float";
  PDeclare "march_poly_compare";
  PDeclare "march_simd_alloc";
  PDeclare "march_simd_bounds_panic";
  PDeclare "march_simd_lane_panic";
]

let native_net_io_items : preamble_item list = [   (* native-only: TCP/TLS/File/CSV/session-types *)
  PBlank;
  PComment "; TCP/network builtins";
  PDeclare "march_tcp_listen";
  PDeclare "march_tcp_accept";
  PDeclare "march_tcp_local_port";
  PDeclare "march_tcp_recv_exact";
  PDeclare "march_tcp_recv_http";
  PDeclare "march_tcp_send_all";
  PDeclare "march_tcp_close";
  PDeclare "march_tcp_peer_addr";
  PDeclare "march_http_parse_request";
  PDeclare "march_http_serialize_response";
  PDeclare "march_http_server_listen";
  PDeclare "march_http_server_spawn_n";
  PDeclare "march_http_server_wait";
  PDeclare "march_ws_handshake";
  PDeclare "march_ws_recv";
  PDeclare "march_ws_send";
  PDeclare "march_ws_select";
  PComment "; File/Dir builtins";
  PDeclare "march_file_exists";
  PDeclare "march_dir_exists";
  PDeclare "march_file_open";
  PDeclare "march_file_close";
  PDeclare "march_file_read";
  PDeclare "march_file_read_line";
  PDeclare "march_file_read_chunk";
  PDeclare "march_file_write";
  PDeclare "march_file_append";
  PDeclare "march_file_delete";
  PDeclare "march_file_copy";
  PDeclare "march_file_rename";
  PDeclare "march_file_stat";
  PDeclare "march_dir_mkdir";
  PDeclare "march_dir_mkdir_p";
  PDeclare "march_dir_rmdir";
  PDeclare "march_dir_rm_rf";
  PDeclare "march_dir_list";
  PDeclare "march_dir_list_full";
  PDeclare "march_process_argv";
  PDeclare "march_process_cwd";
  PDeclare "march_process_env";
  PDeclare "march_process_set_env";
  PDeclare "march_process_exit";
  PDeclare "march_process_pid";
  PDeclare "march_process_spawn_sync";
  PDeclare "march_process_spawn_lines";
  PDeclare "march_process_spawn_async";
  PDeclare "march_process_read_line";
  PDeclare "march_process_write";
  PDeclare "march_process_kill_proc";
  PDeclare "march_process_wait_proc";
  PComment "; TCP recv-all";
  PDeclare "march_tcp_recv_all";
  PDeclare "march_tcp_recv_chunk";
  PDeclare "march_tcp_recv_chunk_timeout";
  PDeclare "march_tcp_set_recv_timeout";
  PDeclare "march_tcp_recv_timeout";
  PDeclare "march_tcp_recv_http_headers";
  PDeclare "march_tcp_recv_chunked_frame";
  PComment "; TLS builtins";
  PDeclare "march_tls_client_ctx";
  PDeclare "march_tls_server_ctx";
  PDeclare "march_tls_connect";
  PDeclare "march_tls_accept";
  PDeclare "march_tls_read";
  PDeclare "march_tls_read_timeout";
  PDeclare "march_tls_write";
  PDeclare "march_tls_close";
  PDeclare "march_tls_ctx_free";
  PDeclare "march_tls_negotiated_alpn";
  PDeclare "march_tls_peer_cn";
  PComment "; TypedArray builtins";
  PDeclare "march_typed_array_create";
  PDeclare "march_typed_array_from_list";
  PDeclare "march_typed_array_to_list";
  PDeclare "march_typed_array_length";
  PDeclare "march_typed_array_get";
  PDeclare "march_typed_array_set";
  PDeclare "march_typed_array_map";
  PDeclare "march_typed_array_filter";
  PDeclare "march_typed_array_fold";
  PComment "; NativeIntArr builtins — flat i64 arrays for vectorizable loops";
  PDeclare "native_int_arr_make";
  PDeclare "native_int_arr_length";
  PDeclare "native_int_arr_get";
  PDeclare "native_int_arr_set";
  PDeclare "native_int_arr_sum";
  PDeclare "native_int_arr_min";
  PDeclare "native_int_arr_max";
  PDeclare "native_int_arr_sumsq_dev";
  PDeclare "native_int_arr_map";
  PDeclare "native_int_arr_map2";
  PDeclare "native_int_arr_to_float_arr";
  PDeclare "native_int_arr_fold";
  PDeclare "native_int_arr_from_list";
  PDeclare "native_int_arr_to_list";
  PDeclare "native_int_arr_filter_mask";
  PComment "; NativeFloatArr builtins — flat double arrays for vectorizable loops";
  PDeclare "native_float_arr_make";
  PDeclare "native_float_arr_length";
  PDeclare "native_float_arr_get";
  PDeclare "native_float_arr_set";
  PDeclare "native_float_arr_sum";
  PDeclare "native_float_arr_min";
  PDeclare "native_float_arr_max";
  PDeclare "native_float_arr_sumsq_dev";
  PDeclare "native_float_arr_map";
  PDeclare "native_float_arr_map2";
  PDeclare "native_float_arr_fold";
  PDeclare "native_float_arr_from_list";
  PDeclare "native_float_arr_to_list";
  PDeclare "native_float_arr_filter_mask";
  PDeclare "native_int_arr_alloc_raw";
  PDeclare "native_float_arr_alloc_raw";
  PDeclare "native_arr_map2_check_len";
  PComment "; Narrow native arrays (f32/i32/u8)";
  PDeclare "native_f32_arr_make";
  PDeclare "native_f32_arr_length";
  PDeclare "native_f32_arr_get";
  PDeclare "native_f32_arr_set";
  PDeclare "native_f32_arr_sum";
  PDeclare "native_f32_arr_map";
  PDeclare "native_f32_arr_map2";
  PDeclare "native_f32_arr_fold";
  PDeclare "native_f32_arr_from_list";
  PDeclare "native_f32_arr_to_list";
  PDeclare "native_i32_arr_make";
  PDeclare "native_i32_arr_length";
  PDeclare "native_i32_arr_get";
  PDeclare "native_i32_arr_set";
  PDeclare "native_i32_arr_sum";
  PDeclare "native_i32_arr_map";
  PDeclare "native_i32_arr_map2";
  PDeclare "native_i32_arr_fold";
  PDeclare "native_i32_arr_from_list";
  PDeclare "native_i32_arr_to_list";
  PDeclare "native_u8_arr_make";
  PDeclare "native_u8_arr_length";
  PDeclare "native_u8_arr_get";
  PDeclare "native_u8_arr_set";
  PDeclare "native_u8_arr_sum";
  PDeclare "native_u8_arr_map";
  PDeclare "native_u8_arr_map2";
  PDeclare "native_u8_arr_fold";
  PDeclare "native_u8_arr_from_list";
  PDeclare "native_u8_arr_to_list";
  PDeclare "native_float_to_f32_arr";
  PDeclare "native_f32_to_float_arr";
  PDeclare "native_int_to_i32_arr";
  PDeclare "native_i32_to_int_arr";
  PDeclare "native_int_to_u8_arr";
  PDeclare "native_u8_to_int_arr";
  PDeclare "native_i32_to_f32_arr";
  PDeclare "native_u8_to_f32_arr";
  PDeclare "native_f32_arr_alloc_raw";
  PDeclare "native_i32_arr_alloc_raw";
  PDeclare "native_u8_arr_alloc_raw";
  PComment "; RingBuf builtins — mutable fixed-capacity circular buffer";
  PDeclare "ring_buf_make";
  PDeclare "ring_buf_push";
  PDeclare "ring_buf_pop";
  PDeclare "ring_buf_get";
  PDeclare "ring_buf_peek_oldest";
  PDeclare "ring_buf_peek_newest";
  PDeclare "ring_buf_size";
  PDeclare "ring_buf_cap";
  PDeclare "ring_buf_clear";
  PDeclare "ring_buf_to_list";
  PComment "; Time builtins";
  PDeclare "march_unix_time";
  PDeclare "march_unix_time_ms";
  PDeclare "march_peak_rss_bytes";
  PDeclare "march_live_allocs";
  PDeclare "march_tcp_connect";
  PComment "; HTTP client builtins";
  PDeclare "march_http_serialize_request";
  PDeclare "march_http_parse_response";
  PComment "; CSV builtins";
  PDeclare "march_csv_open";
  PDeclare "march_csv_next_row";
  PDeclare "march_csv_close";
  PComment "; Resource ownership";
  PDeclare "march_own";
  PComment "; Capability builtins";
  PDeclare "march_cap_narrow";
  PDeclare "march_mint_cap";
  PDeclare "march_cap_impl";
  PDeclare "march_cap_dict";
  PComment "; Monitor/supervision builtins";
  PDeclare "march_demonitor";
  PDeclare "march_monitor";
  PDeclare "march_mailbox_size";
  PDeclare "march_sched_stat";
  PDeclare "march_actor_set_mbox_limit";
  PDeclare "march_run_until_idle";
  PDeclare "march_register_resource";
  PComment "; Named registry builtins";
  PDeclare "march_actor_register";
  PDeclare "march_actor_unregister";
  PDeclare "march_actor_whereis";
  PDeclare "march_actor_registered";
  PDeclare "march_get_cap";
  PDeclare "march_send_checked";
  PDeclare "march_revoke_cap";
  PDeclare "march_is_cap_valid";
  PDeclare "march_pid_of_int";
  PDeclare "march_get_actor_field";
  PDeclare "march_register_supervisor";
  PDeclare "march_actor_register_child";
  PDeclare "march_pid_index_of";
  PDeclare "march_value_to_string";
  PComment "; Session-typed channel builtins (binary)";
  PDeclare "march_chan_new";
  PDeclare "march_chan_send";
  PDeclare "march_chan_recv";
  PDeclare "march_chan_close";
  PDeclare "march_chan_choose";
  PDeclare "march_chan_offer";
  PComment "; Multi-party session type (MPST) builtins";
  PDeclare "march_mpst_new";
  PDeclare "march_mpst_send";
  PDeclare "march_mpst_recv";
  PDeclare "march_mpst_close";
]

let wasm_scheduler_stub_items : preamble_item list = [   (* WASM-only: no-op scheduler + plain global *)
  PComment "; WASM: plain globals (no TLS), no-op scheduler stub";
  POther "@march_preempt_request = external global i64";
  POther "@march_tls_reductions = external global i64";
  PDeclare "march_yield_from_compiled";
  PDeclare "march_run_scheduler";
  PDeclare "march_task_spawn_thunk";
  PDeclare "march_task_await";
  PDeclare "march_task_await_value";
  PDeclare "march_sched_yield";
  PDeclare "march_sched_recv";
  PDeclare "march_cancel_token_new";
  PDeclare "march_cancel_token_cancel";
  PDeclare "march_cancel_token_is_cancelled";
  PDeclare "march_task_spawn_with_cancel_thunk";
  PDeclare "march_task_cancel_by_id";
  PDeclare "march_signal_watch";
  PDeclare "march_signal_unwatch";
  PDeclare "march_signal_raise_self";
  PDeclare "march_alloc_float";
  PDeclare "march_unbox_float";
  PDeclare "march_poly_compare";
  PDeclare "march_simd_alloc";
  PDeclare "march_simd_bounds_panic";
  PDeclare "march_simd_lane_panic";
]

(** Emit the LLVM preamble (`declare`d externs for every builtin/runtime
    C symbol) to [buf].  Mirrors llvm_emit.ml's former hand-written
    structure exactly: [core_items] on every target; [native_actor_items]
    + (TLS reduction-budget global, unless [repl]) + [native_net_io_items]
    on native targets; [wasm_scheduler_stub_items] on WASM targets.
    [triple] is the already-resolved LLVM target-triple string (callers
    pass [Llvm_emit.target_triple target]); [is_wasm] likewise stands in
    for [Llvm_emit.is_wasm_target target] — this module intentionally does
    not depend on [Llvm_emit.target_config] to avoid a module cycle
    ([Llvm_emit.emit_preamble] becomes a thin wrapper passing both through). *)
let emit_preamble ~(is_wasm : bool) ~(triple : string) ?(repl = false) (buf : Buffer.t) : unit =
  Buffer.add_string buf
    (Printf.sprintf "; March compiler output\ntarget triple = \"%s\"\n\n" triple);
  render_items buf core_items;
  if not is_wasm then begin
    render_items buf native_actor_items;
    (* In REPL mode the reduction check is skipped, so march_tls_reductions and
       march_yield_from_compiled are never referenced — omitting them avoids
       the emutls symbol-not-found error from ORC JIT on macOS. *)
    if not repl then
      Buffer.add_string buf
        (* march_preempt_request is deliberately a PLAIN external global, not
           thread_local: TLS access is an indirect resolver call per function
           entry on both Darwin/arm64 (TLV) and Linux/arm64 PIE (TLSDESC),
           which cost 1.75x on call-dense code.  See emit_reduction_check and
           the rationale on the declaration in runtime/march_scheduler.h.
           march_tls_reductions stays thread_local and is still declared here
           because the task_reductions() builtin loads it. *)
        "@march_preempt_request = external global i64\n\
         @march_tls_reductions = external thread_local global i64\n\
         declare void @march_yield_from_compiled()\n";
    render_items buf native_net_io_items
  end else
    render_items buf wasm_scheduler_stub_items

(* ── Consumers, reimplemented from the table ────────────────────────── *)

(** Hashtable of every name with [in_is_builtin = true] (273 of the 318
    table rows), built once at module load. Replaces the historical
    [List.mem name [...272 literals...]] linear scan that ran on hot paths
    (emit_atom, is_leaf_callee/expr_has_call's reduction-check analysis,
    EIncRC/EDecRC/EFree shadow guards) — O(n) per call becomes O(1).
    Answer-identical: membership is exactly the historical list's
    membership (see [builtins] row order + [in_is_builtin] field, extracted
    verbatim from the deleted list). This is the one intentional
    non-cosmetic change this task makes; it changes complexity, not
    behavior. *)
let is_builtin_fn_tbl : (string, unit) Hashtbl.t =
  let tbl = Hashtbl.create 512 in
  List.iter (fun b -> if b.in_is_builtin then Hashtbl.replace tbl b.march_name ()) builtins;
  tbl

let is_builtin_fn (name : string) : bool =
  Hashtbl.mem is_builtin_fn_tbl name

(** name → TIR return type override, built once. Replaces the historical
    [builtin_ret_ty : string -> Tir.ty option] pattern-match function. *)
let builtin_ret_ty_tbl : (string, Tir.ty) Hashtbl.t =
  let tbl = Hashtbl.create 512 in
  List.iter (fun b -> match b.ret_ty with
      | Some ty -> Hashtbl.replace tbl b.march_name ty
      | None -> ())
    builtins;
  tbl

let builtin_ret_ty (name : string) : Tir.ty option =
  Hashtbl.find_opt builtin_ret_ty_tbl name

(** name → declare_sig text, built once (keyed by march_name, unlike
    [emit_preamble]'s by-c_name lookup — several march_names alias one
    c_name and each carries its own identical copy of the text, so a
    march_name-keyed table is just as sound and is what call-site argument
    coercion needs). *)
let builtin_declare_sig_tbl : (string, string) Hashtbl.t =
  let tbl = Hashtbl.create 512 in
  List.iter (fun b -> match b.declare_sig with
      | Some sig_ -> Hashtbl.replace tbl b.march_name sig_
      | None -> ())
    builtins;
  tbl

(** Builtins with a genuinely GENERIC (TVar) element parameter declared as
    "ptr" — a uniform/erased slot that must receive the boxed representation of
    a scalar argument (Int tagged (n<<1)|1, Float boxed), NOT the raw i64/double
    bits.  The general builtin call path only coerces the ptr→scalar direction
    (see the long comment at the coercion site in llvm_emit.ml — scalar→ptr is
    deliberately skipped there because several builtins declare "ptr" for an
    opaque native handle whose March type is a plain Int and must stay raw).
    This table opts specific (builtin, param_idx) slots INTO scalar→ptr boxing
    because their March type really is a generic TVar, so an inlined raw-scalar
    argument would otherwise be stored/compared at the wrong representation
    (RingBuf.push(rb, 7) stored 7 raw; the erased-i64 conditional untag then
    read odd 7 back as 3). Keyed on the slot, so opaque-handle builtins are
    untouched. *)
let builtin_boxed_generic_params_tbl : (string, int list) Hashtbl.t =
  let tbl = Hashtbl.create 8 in
  (* ring_buf_push(rb, x): x (index 1) is the erased element. *)
  Hashtbl.replace tbl "ring_buf_push" [1];
  (* native_*_arr_fold(acc, arr, f): acc (index 0) is the generic 'a
     accumulator — same erased-slot hazard as ring_buf_push's element above.
     Without this, a literal accumulator argument (e.g. the `0.0` in
     `fold_float(arr, 0.0, f)`) reaches the C runtime as a raw double bit
     pattern instead of a march_alloc_float box, and march_unbox_float
     SIGSEGVs dereferencing it inside the closure. *)
  Hashtbl.replace tbl "native_int_arr_fold" [0];
  Hashtbl.replace tbl "native_float_arr_fold" [0];
  Hashtbl.replace tbl "native_f32_arr_fold" [0];
  Hashtbl.replace tbl "native_i32_arr_fold" [0];
  Hashtbl.replace tbl "native_u8_arr_fold" [0];
  (* typed_array_* : the whole family stores/threads a genuinely generic 'a.
     Missed when this table was first written, and the omission is transitive
     — get/map/filter never touch a raw scalar themselves, they just read back
     what create/set/fold stored, so ALL of them returned corrupt values:

       typed_array_create(3, 7)  then  get(0)   ->  3   (want 7)
       typed_array_fold(a, 0, (+))                ->  48  (want 56)
       typed_array_map(a, (+1))  then  get(0)   ->  4   (want 8)

     7 was stored raw; the erased-i64 conditional untag then read odd 7 back
     as 7>>1 = 3 — the identical mechanism this table's ring_buf_push note
     describes. An EVEN element (42) survived untouched, which is exactly why
     the family looked half-working. A Float element is worse than wrong: the
     raw double bits reach march_unbox_float as a pointer and SIGSEGV.

     Indices are into the DECLARE signature, which for these three matches the
     March argument order:
       typed_array_create(i64 %len, ptr %default_val)        -> 1
       typed_array_set(ptr %arr, i64 %i, ptr %val)           -> 2
       typed_array_fold(ptr %arr, ptr %acc, ptr %f)          -> 1
     (note fold's acc is index 1 here, unlike native_*_arr_fold's index 0 —
     those declare acc first). *)
  Hashtbl.replace tbl "typed_array_create" [1];
  Hashtbl.replace tbl "typed_array_set" [2];
  Hashtbl.replace tbl "typed_array_fold" [1];
  tbl

(** True iff parameter [idx] of builtin [name] is a generic erased slot that
    must receive a boxed scalar (see [builtin_boxed_generic_params_tbl]). *)
let builtin_param_is_boxed_generic (name : string) (idx : int) : bool =
  match Hashtbl.find_opt builtin_boxed_generic_params_tbl name with
  | Some idxs -> List.mem idx idxs
  | None -> false

(** name → parameter LLVM types (bare tokens: "ptr", "i64", "double", ...),
    in declaration order, parsed from [declare_sig].  [None] when the
    builtin has no recorded [declare_sig].

    This is the single source of truth for what a builtin's C signature
    actually expects, reused (rather than duplicated into a second,
    hand-maintained table) so it can never drift from the preamble text.
    Every param token in the table today is "ptr", "i64", or "double" (no
    varargs, no i32/i1) — the exact set [Llvm_ctx.coerce] already handles
    bidirectionally (untag/tag, box/unbox), so a mismatched arg
    representation (e.g. a tuple/ADT scalar field's uniform "ptr" slot)
    flowing into a builtin call can be coerced to the declared type just
    like it already is for user-defined functions via
    [top_fn_param_tys]. *)
let builtin_param_llvm_tys (name : string) : string list option =
  match Hashtbl.find_opt builtin_declare_sig_tbl name with
  | None -> None
  | Some sig_text ->
    (match String.index_opt sig_text '(', String.rindex_opt sig_text ')' with
     | Some i, Some j when j > i ->
       let params_str = String.trim (String.sub sig_text (i + 1) (j - i - 1)) in
       if params_str = "" then Some []
       else
         Some (List.map (fun p ->
             let p = String.trim p in
             match String.index_opt p ' ' with
             | Some k -> String.sub p 0 k
             | None -> p)
           (String.split_on_char ',' params_str))
     | _ -> None)

(** March builtin name → C runtime symbol, built once. Replaces the
    historical [mangle_extern : string -> string] pattern-match function,
    including its identity-fallthrough default (`| other -> other`) for
    names with no explicit mapping. *)
let mangle_extern_tbl : (string, string) Hashtbl.t =
  let tbl = Hashtbl.create 512 in
  List.iter (fun b -> match b.c_name with
      | Some c -> Hashtbl.replace tbl b.march_name c
      | None -> ())
    builtins;
  tbl

(* Capability-marker support (specs/2026-08-03-forge-cap-audit-design.md
   §4.3, mechanism C): record every C symbol resolved for emission, so
   emit_module can emit @__march_cap_* markers for exactly the capabilities
   the emitted code references.  A module-level accumulator with an explicit
   reset — rather than a Llvm_ctx field — because [mangle_extern]'s
   [string -> string] signature is frozen by its jit/repl_jit callers.
   [Llvm_toplevel.emit_module] resets it at the start of each emission, so
   multi-module processes (tests, forge) cannot leak symbols across modules.

   The declare PREAMBLE must never feed this table: [emit_preamble] declares
   every builtin unconditionally, so recording there would mark every cap in
   every binary (the app-invariance trap — design §3).  [declare_text]
   resolves via [b.c_name] directly and never calls [mangle_extern]. *)
let called_syms : (string, unit) Hashtbl.t = Hashtbl.create 64
let reset_called_syms () = Hashtbl.reset called_syms
let called_c_symbols () =
  Hashtbl.fold (fun k () acc -> k :: acc) called_syms []

let mangle_extern (name : string) : string =
  match Hashtbl.find_opt mangle_extern_tbl name with
  | Some c -> Hashtbl.replace called_syms c (); c
  | None -> Hashtbl.replace called_syms name (); name

(** [mangle_extern] without the [called_syms] side effect: same March-name →
    C-symbol resolution, including the identity fallthrough.

    Analyses that ask "what symbol WOULD this name resolve to?" must use this
    rather than [mangle_extern].  Recording a symbol that emission never
    actually referenced would mark a capability in a binary that does not use
    it — the app-invariance trap the marker scheme exists to avoid. *)
let c_symbol_of_march_name (name : string) : string =
  match Hashtbl.find_opt mangle_extern_tbl name with
  | Some c -> c
  | None -> name
