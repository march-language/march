(** Capability-bearing runtime entry points.

    Maps the C symbol a capability's builtin lowers to (see the builtin table
    in [lib/tir/llvm_builtins.ml] and the special-lowering notes on [table])
    to the capability path the typechecker attributes to it
    ([builtin_cap_table] in [lib/typecheck/typecheck.ml]).

    Consumed by [forge cap audit] to read a binary's capabilities from its
    symbol table, and by the marker-emission pass. Kept in sync with
    [builtin_cap_table] by a freshness test in [test/test_cap_symbols.ml] —
    this module cannot depend on the typechecker without creating a
    dependency cycle (typecheck already depends on march_caps). *)

val table : (string * string) list
(** [(runtime_c_symbol, cap_path)] pairs, e.g.
    [("march_file_read", "IO.FileRead")]. One row per distinct C symbol;
    March-name aliases sharing a symbol (e.g. [random_bytes] and
    [stdlib_random_bytes]) appear once. *)

val cap_of_symbol : string -> string option
(** Accepts either the plain [march_file_read] or Mach-O-mangled
    [_march_file_read] spelling. *)

val all_caps : string list
(** Every distinct capability path appearing in [table], sorted. *)

val uncompiled_builtins : string list
(** March-name builtins from [builtin_cap_table] that have NO compiled
    lowering (no C symbol can ever appear in a native binary for them).
    The freshness test requires every cap-table entry to be accounted for
    either by [table] or by this list — a new builtin that is neither
    fails the test rather than silently escaping the audit. *)
