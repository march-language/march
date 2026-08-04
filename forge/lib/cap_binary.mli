(** Read capabilities from a compiled March binary.

    Three channels, cross-checked (specs/2026-08-03-forge-cap-audit-design.md
    §4.2-§4.4):
    - [markers]: [__march_cap_*] globals emitted by codegen from the C symbols
      the module actually referenced — precise, March-level.
    - [rt_symbols]: capability-bearing runtime entry points present in the
      symbol table ([March_caps.Cap_symbols.table]) — meaningful because
      dead-strip removes unused ones.
    - [manifest]: raw JSON of an embedded [MARCHCAP\x01] blob, when present.

    The reader never assumes stripping happened: a binary carrying every cap
    symbol was almost certainly linked without dead-strip and is classified
    [Unstripped] — reporting its full symbol set as "capabilities" would be
    the app-invariance failure (design §3). *)

type build_kind =
  | Dead_stripped      (** normal capstrip executable *)
  | Unstripped         (** every cap symbol present — strip did not apply *)
  | Symbols_removed    (** names stripped; symbol/marker channels unavailable *)

type t = {
  caps : string list;        (** normalized; markers preferred, symbols as fallback *)
  markers : string list;     (** cap paths recovered from [__march_cap_*] globals *)
  attribution : (string * string) list;
      (** [(cap_path, owner_module)] from [__march_capfrom_*] globals: which
          module's code performs the IO, so a capability can be traced to the
          dependency that introduced it rather than only to the program.

          Computed by the compiler BEFORE inlining ([March_tir.Cap_attrib]) —
          by emission time a small dependency function has been folded into
          its caller and would be credited to the application instead.

          A cap in [markers] with no row here is UNATTRIBUTED, not
          unattributable-to-anyone: indirect calls through closures have no
          statically known callee. Report that difference; do not present an
          empty owner set as "nothing uses it". Binaries built by a
          pre-attribution compiler have this empty entirely. *)
  declarations : (string * string) list;
      (** [(cap_path, owner_module)] from [__march_capdecl_*] globals: what
          each module DECLARED, as opposed to what [attribution] shows it
          uses. Both channels together let [forge cap inspect --strict]
          re-check the capability ceiling on a binary it did not build —
          attribution alone shows use but never the promise it should be
          measured against.

          Emitted only for modules that have attributed use, so a module
          absent here is not necessarily undeclared. Empty for binaries from a
          pre-attribution compiler. *)
  rt_symbols : string list;  (** cap-bearing runtime symbols present *)
  build : build_kind;
  manifest : string option;  (** raw JSON; [None] when absent *)
}

val read : string -> (t, string) result
(** [read path] inspects the binary at [path].  Errors on unreadable files and
    on a binary carrying MULTIPLE manifest blobs (a planted second blob must
    never shadow the real one — design §6). *)
