(** Per-module capability attribution: WHICH module's code performs the IO.

    The flat [__march_cap_*] markers say a binary reads files. They cannot say
    whether the reading code is yours or a dependency's, and that is the
    question a per-dependency capability budget has to answer.

    [attribute] pairs each capability with the March module whose function
    body contains the call, so codegen can emit [__march_capfrom_CAP__OWNER]
    alongside the flat markers.

    {2 Why this is a TIR pass and not a codegen side effect}

    The obvious implementation — record the module being emitted when
    [Llvm_builtins.mangle_extern] resolves a cap-bearing symbol — is wrong,
    and wrong in the dangerous direction. By emission time the inliner has
    folded small dependency functions into their callers, so a dependency's
    [file_read] appears inside the application's [main] and would be
    attributed to the application. That reports a clean dependency and a
    dirty app: exactly backwards for deciding whether to trust a dep.

    Measured, not assumed: a two-line [BigLib.load] calling [file_read]
    leaves no trace of [BigLib] in the emitted IR at all — the call site
    lands in [@march_main].

    So this runs over the pre-[Opt.run] TIR, where module prefixes still
    exist, and after reachability pruning, so a dependency feature the
    program never calls contributes nothing here either. *)

val attribute :
  ?transparent:(string -> bool) -> Tir.tir_module -> (string * string) list
(** [attribute m] returns sorted, de-duplicated [(cap_path, owner_module)]
    pairs — e.g. [("IO.FileRead", "BigLib")].

    [transparent] names modules to see THROUGH rather than report — in
    practice the stdlib. Without it, a dependency that reads a file via
    [File.read] is attributed to [File], and since most dependencies reach IO
    through stdlib wrappers, every capability in a real program lands on a
    handful of stdlib modules and the report answers nobody's question.
    Measured before this existed: a dep calling [File.read] produced
    [IO.FileRead ← File].

    When the direct owner is transparent, the reverse call graph is walked to
    the nearest non-transparent callers, and the capability is attributed to
    each of them. The entry module is never treated as transparent — seeing
    through it would leave the capability nowhere to land. If nothing outside
    the transparent set reaches the call at all, the transparent module is
    reported rather than the row dropped.

    The owner is the module prefix of the enclosing function's TIR name.
    [lower.ml] strips the entry file-module's own name from its declarations,
    so its functions are unprefixed; those are attributed to [m.tm_name].

    Only direct calls ([Tir.EApp]) are attributed. An indirect call through a
    closure ([Tir.ECallPtr]) has no statically known callee, so it yields no
    row — the flat marker still reports the capability, it just carries no
    owner. Consumers must therefore treat "flat caps minus attributed caps"
    as unattributed rather than as absent. *)

val cap_of_call : string -> string option
(** [cap_of_call march_name] is the capability a call to [march_name] implies,
    as [attribute] resolves it.  Exposed so [test_cap_attrib_agreement] can
    assert this answers identically to [Typecheck.builtin_cap_table] for every
    capability-bearing builtin — the two tables are keyed differently (March
    name vs C symbol) and silently disagreed for the trampoline-lowered spawn
    builtins, which made `--cap-strict` call them unattributable. *)
