(** Detects a bare top-level function name shared between the entry module
    and either (a) a March-SOURCE Prelude function, or (b) a NATIVE
    compiler builtin — see
    specs/plans/2026-08-13-prelude-entry-fn-name-collision.md.

    Both prelude.march and the user's entry file are unwrapped by
    [bin/main.ml] into bare, unqualified top-level declarations before being
    concatenated (prelude's list first, the entry module's appended).
    Nothing before this module ever checked whether that concatenation
    introduces a duplicate bare name. Since Prelude's own functions call
    other Prelude names UNQUALIFIED (e.g. [println] calls [show] and
    [print] bare), a later-declared entry-module function sharing one of
    those names silently replaces it program-wide — with observed failure
    modes ranging from a misattributed runtime arity error to a compiled
    SIGBUS to a fully silent no-op, depending on how the two definitions'
    types happen to line up.

    Two DISTINCT collision sources, both real, verified via two different
    minimal repros:

    - A name matching another March-SOURCE top-level [fn]/[pfn] in
      prelude.march (e.g. [println], [map], [reverse] — the ~21 names
      actually written as `fn X(...) do ... end` at prelude.march's top
      level). Checked against [prelude_decls]'s own [DFn]s.
    - A name matching a NATIVE COMPILER BUILTIN that has NO corresponding
      March-source declaration at all — [print] is exactly this: eval.ml
      registers it as a [VBuiltin] value directly, and grepping
      prelude.march confirms it has no bare top-level [fn]/[pfn] of its
      own. Checked against [ordinary_builtin_names] (bin/main.ml sources
      this from [Typecheck.builtin_bindings] — the SAME table the
      typechecker itself uses, so it can never drift from what the
      compiler actually treats as a builtin).

    A THIRD case looks like the second but is NOT a collision: [show],
    [eq], [compare], and [hash] are structural interface methods
    (registered separately, in [Typecheck.builtin_interface_bindings]), and
    the compiler ALREADY resolves a bare top-level [fn show(x) do ... end]
    by the call site's argument type — the same type-directed dispatch an
    explicit [impl Show(X) do ... end] gets — rather than by flat bare-name
    lookup. `test/native/iface_method_collision.march` is a standing,
    passing regression test for exactly this: a user [fn show(r :
    Option(Int)) : Int] coexists with [println]'s two calls to the builtin
    [show : String -> String], each correctly resolving to the right one BY
    TYPE. An EARLIER version of this checker treated every [show] as an
    unconditional collision and broke that fixture.

    The distinguishing fact is ARITY. [Show.show]/[Hash.hash] are strictly
    1-argument; [Eq.eq]/[Ord.compare] are strictly 2-argument. A user
    [fn]/[pfn] with one of these 4 names AND the matching arity is a
    legitimate ad-hoc dispatch overload (already handled correctly
    elsewhere in the compiler) and must NOT be flagged. A user function
    with a MISMATCHED arity — e.g. a 2-argument `show` — can never
    correctly participate in that dispatch (there is no way to call a
    2-argument function through a 1-argument interface slot), so it is
    unambiguously the original collision bug, not the supported feature,
    and IS flagged. This is passed in via [iface_method_arities].

    Only [DFn] is checked on the prelude/entry side. [DImpl] bodies (e.g.
    [impl Show(Widget) do fn show(w) do ... end end]) are a DIFFERENT
    declaration form entirely — an interface method, mangled to a
    type-qualified name downstream (e.g. [Show$Widget.show]) — and never
    reach this checker's decl lists as a bare top-level [DFn], so a module
    defining its own [Show]/[Eq]/[Ord]/[Hash] impl is untouched by this
    check either way. *)

open March_ast.Ast

module StrMap = Map.Make (String)
module StrSet = Set.Make (String)

type fn_site = { fs_span : span; fs_arity : int }

(** Every top-level [DFn]'s bare name -> its span and arity, keyed by name.
    Multi-head clauses of the same function are already merged into one
    [DFn] by desugar before this runs (and every clause of one function
    shares the same arity), so within a single already-desugared decl list
    each name appears at most once — the first clause's param count and the
    function name's own span suffice. *)
let top_level_fn_sites (decls : decl list) : fn_site StrMap.t =
  List.fold_left
    (fun acc d ->
       match d with
       | DFn (def, _) ->
         let arity = match def.fn_clauses with
           | c :: _ -> List.length c.fc_params
           | [] -> 0
         in
         StrMap.add def.fn_name.txt { fs_span = def.fn_name.span; fs_arity = arity } acc
       | _ -> acc)
    StrMap.empty decls

let report_collision errors ~name ~span ~reason =
  March_errors.Errors.error errors ~span
    (Printf.sprintf
       "`%s` redefines %s.\n\
        March's Prelude (println, show, print, and others) calls its own \
        members unqualified, so a top-level function in your program \
        sharing one of those names silently REPLACES it for the whole \
        program — including inside Prelude's own code. This can fail \
        loudly (a confusing runtime error), or fail completely silently \
        (no error, no crash, just wrong output).\n\
        Rename this function — `%s_impl`, a more specific name, or similar."
       name reason name)

(** Report a compile error for every bare function name in [entry_decls]
    that also names either a Prelude [DFn] in [prelude_decls] or an
    ordinary native builtin in [ordinary_builtin_names]. A name matching one
    of [iface_method_arities] is exempt EXACTLY when the entry function's
    own arity matches the expected one — see the module doc comment for why.
    A name unique to the entry module (or a same-name interface method at
    the right arity) is untouched — this only fires on a genuine collision,
    never on an ordinary distinct name or a supported dispatch overload. *)
let check ~(prelude_decls : decl list) ~(ordinary_builtin_names : string list)
    ~(iface_method_arities : (string * int) list) ~(entry_decls : decl list)
    (errors : March_errors.Errors.ctx) : unit =
  let prelude_sites = top_level_fn_sites prelude_decls in
  let builtin_set =
    List.fold_left (fun s n -> StrSet.add n s) StrSet.empty ordinary_builtin_names in
  let iface_arities =
    List.fold_left (fun m (n, a) -> StrMap.add n a m) StrMap.empty iface_method_arities in
  StrMap.iter
    (fun name site ->
       match StrMap.find_opt name prelude_sites with
       | Some _prelude_site ->
         report_collision errors ~name ~span:site.fs_span
           ~reason:"a name the March standard library relies on internally"
       | None ->
         if StrSet.mem name builtin_set then
           report_collision errors ~name ~span:site.fs_span
             ~reason:"a March compiler builtin"
         else
           match StrMap.find_opt name iface_arities with
           | Some expected_arity when site.fs_arity <> expected_arity ->
             report_collision errors ~name ~span:site.fs_span
               ~reason:(Printf.sprintf
                          "the name of a March structural interface method \
                           (%s is %d-argument; yours takes %d, so it cannot \
                           be a valid overload — this is the same collision \
                           as an ordinary builtin, not the supported \
                           type-directed dispatch)"
                          name expected_arity site.fs_arity)
           | Some _ | None -> ()
    ) (top_level_fn_sites entry_decls)
