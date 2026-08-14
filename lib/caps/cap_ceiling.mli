(** `needs` as a hard ceiling, checked against attributed use.

    {2 Why this is not another source walk}

    The source-level checks in [Typecheck] each cover one route to a
    capability, and measured, they do not cover the same set:

    - a direct builtin call ([file_write "…"]) is a WARNING (Check 1b);
    - a stdlib-mediated call ([File.write "…"]) produced NO diagnostic at all,
      because Check 4 walks [DUse] declarations and stdlib modules are
      ambiently available without one;
    - an import of a user module that declares [needs] is an ERROR (Check 4);
    - an [extern] block is an ERROR (Check 5).

    So the most common route in real code was also the silent one. Closing it
    with a fifth AST walk would repeat the failure that produced the first
    four: this codebase has shipped five separate capability decl-walks whose
    catch-all arm silently skipped a declaration form.

    This check instead runs over what codegen actually emitted, via
    [March_tir.Cap_attrib]. All three call routes collapse into one rule,
    and re-routing a call through a helper or a wrapper cannot evade it.

    {2 The rule}

    For every module [M]: every capability attributed to [M] must be subsumed
    by one of [M]'s own [needs] declarations.

    Because attribution charges stdlib-mediated IO to the CALLING module
    rather than to the stdlib wrapper, this asks nothing of the standard
    library's own declarations — the module that called [File.write] is the
    one required to declare [needs IO.FileWrite]. *)

type violation =
  | Undeclared of { cap : string; owner : string; span : March_ast.Ast.span }
      (** [owner]'s emitted code uses [cap], which none of its [needs]
          declarations subsumes. [span] is [owner]'s first [DNeeds] span, or
          its module-header span if it declares none — where a diagnostic
          pointing at this violation, and a fix inserting the missing
          [needs] line, should land. *)
  | Unattributed of { cap : string }
      (** The program uses [cap] but no module can be held responsible for it
          — it is reached only through indirect calls, whose callee is not
          statically known.

          This is a violation rather than a pass. A capability the analysis
          cannot attribute is precisely the one an attacker would route
          through, so certifying it would make the check worthless exactly
          where it matters most. *)

val check :
  module_caps:(string * string list) list ->
  module_spans:(string * March_ast.Ast.span) list ->
  attribution:(string * string) list ->
  caps:string list ->
  violation list
(** [module_caps] is each module's declared [needs]; a module absent from it
    has declared none. [module_spans] maps a module name to the span an
    [Undeclared] violation naming it should point at (see [violation]'s
    [span] field); a module absent from it falls back to
    [March_ast.Ast.dummy_span]. [caps] is the program's flat capability set —
    the marker channel — used to find capabilities with no owner row.

    [IO.Foreign] and [IO.Foreign.Blocking] are excluded: they are emitted from
    the presence of [extern] blocks rather than from an attributed call site,
    so they have no owner by construction, and Typecheck's Check 5 already
    errors when an extern's capability is undeclared.

    Results are sorted and de-duplicated for deterministic diagnostics. *)

val describe : violation -> string
(** One-line rendering, without span or severity decoration. *)
