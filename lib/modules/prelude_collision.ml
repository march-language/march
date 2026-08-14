(** Detects a bare top-level function name shared between the entry module
    and a name Prelude's OWN internal code depends on — see
    specs/plans/2026-08-13-prelude-entry-fn-name-collision.md.

    Both prelude.march and the user's entry file are unwrapped by
    [bin/main.ml] into bare, unqualified top-level declarations before being
    concatenated (prelude's list first, the entry module's appended).
    Nothing before this module ever checked whether that concatenation
    introduces a duplicate bare name. Since Prelude's own functions call
    SOME other Prelude names unqualified (e.g. [println] calls [show] and
    [print] bare), a later-declared entry-module function sharing one of
    THOSE names silently replaces it program-wide — with observed failure
    modes ranging from a misattributed runtime arity error to a compiled
    SIGBUS to a fully silent no-op, depending on how the two definitions'
    types happen to line up.

    Critically, this is NOT true of every Prelude name. General shadowing
    of a builtin/Prelude name by the entry module's own top-level function
    is a documented, intentional, regression-tested feature: the compiler's
    real name resolution lets the entry module's own definition win for
    every call the entry module itself makes (specs/lang/types/accept/
    t126_entry_module_shadows_list_length.march shadows `head`;
    t168_module_fn_shadows_builtin_name.march shadows `file_read` — both
    verified working, interpreted AND compiled). The bug only bites when
    Prelude's OWN code reaches for the bare name FROM INSIDE another
    Prelude function's body — e.g. [unwrap]/[head]/[tail] all call [panic]
    unqualified, [filter]/[map] call [reverse] unqualified, [println] calls
    both [print] and [show] unqualified, and every [impl Show] body (and
    [println]) calls [show]. A name like [head] itself, [length], [map], or
    [unwrap] is never called FROM WITHIN another Prelude function — nothing
    in prelude.march ever writes bare `head(...)` except the function named
    [head] being invoked BY THE USER — so shadowing it is safe exactly as
    those fixtures assert.

    This checker therefore computes the actual internal call graph: for
    every top-level [DFn] in [prelude_decls], it collects the free
    identifiers referenced in that function's own body (not the fact that
    the name merely EXISTS in prelude_decls), and only names appearing in
    that referenced set are collision candidates. The same reasoning
    applies to [ordinary_builtin_names] — a native builtin is dangerous to
    shadow only if some Prelude function's body actually calls it bare
    (e.g. [print], [to_string]); an unrelated builtin never touched by
    Prelude's own code (e.g. [file_read]) is not.

    A THIRD case looks like a collision but is not: [show], [eq],
    [compare], and [hash] are structural interface methods (registered
    separately, in [Typecheck.builtin_interface_bindings]), and the
    compiler ALREADY resolves a bare top-level [fn show(x) do ... end] by
    the call site's argument type — the same type-directed dispatch an
    explicit [impl Show(X) do ... end] gets — rather than by flat bare-name
    lookup. `test/native/iface_method_collision.march` is a standing,
    passing regression test for exactly this. The distinguishing fact is
    ARITY: [Show.show]/[Hash.hash] are strictly 1-argument;
    [Eq.eq]/[Ord.compare] are strictly 2-argument. A user [fn]/[pfn] with
    one of these names AND the matching arity is a legitimate ad-hoc
    dispatch overload and must NOT be flagged; a mismatched arity can never
    correctly participate in that dispatch, so it is unambiguously the
    original collision bug and IS flagged. This is passed in via
    [iface_method_arities].

    Only [DFn] is checked on the prelude/entry side. [DImpl] bodies (e.g.
    [impl Show(Widget) do fn show(w) do ... end end]) are a DIFFERENT
    declaration form entirely — mangled to a type-qualified name downstream
    — and never reach this checker's decl lists as a bare top-level [DFn]. *)

open March_ast.Ast

module StrMap = Map.Make (String)
module StrSet = Set.Make (String)

type fn_site = { fs_span : span; fs_arity : int }

(** Every top-level [DFn]'s bare name -> its span, arity, and clause bodies,
    keyed by name. Multi-head clauses of the same function are already
    merged into one [DFn] by desugar before this runs (and every clause of
    one function shares the same arity), so within a single already-
    desugared decl list each name appears at most once. *)
let top_level_fn_sites (decls : decl list) : (fn_site * expr list) StrMap.t =
  List.fold_left
    (fun acc d ->
       match d with
       | DFn (def, _) ->
         let arity, bodies = match def.fn_clauses with
           | c :: _ as cs -> List.length c.fc_params, List.map (fun c -> c.fc_body) cs
           | [] -> 0, []
         in
         StrMap.add def.fn_name.txt
           ({ fs_span = def.fn_name.span; fs_arity = arity }, bodies) acc
       | _ -> acc)
    StrMap.empty decls

(** Free identifiers referenced by [e], excluding names bound by lambdas,
    let-bindings, match patterns, etc. within [e] itself. Only needs to be
    a conservative superset of "names this expression might call" — this
    drives which Prelude/builtin names are dangerous to shadow, so a rare
    false positive (an unrelated local binding shadowing a dangerous name
    inside its own scope) merely costs a slightly wider flagged set, never
    a missed real collision. *)
let rec free_names (bound : StrSet.t) (e : expr) : StrSet.t =
  let go = free_names bound in
  match e with
  | EVar n -> if StrSet.mem n.txt bound then StrSet.empty else StrSet.singleton n.txt
  | ELit _ | EHole _ | EResultRef _ | EDbg (None, _) -> StrSet.empty
  | EDbg (Some inner, _) -> go inner
  | EApp (f, args, _) -> union_all (go f :: List.map go args)
  | ECon (_, args, _) -> union_all (List.map go args)
  | ELam (ps, body, _) ->
    let inner_bound = List.fold_left (fun b (p : param) -> StrSet.add p.param_name.txt b) bound ps in
    free_names inner_bound body
  | EBlock (es, _) -> free_names_block bound es
  | ELet (b, _) -> go b.bind_expr
  | EMatch (scrut, branches, _) ->
    union_all (go scrut :: List.map (fun br ->
        let inner_bound = StrSet.union (free_pattern_names br.branch_pat) bound in
        union_all
          [ Option.fold ~none:StrSet.empty ~some:(free_names inner_bound) br.branch_guard;
            free_names inner_bound br.branch_body ])
        branches)
  | ETuple (es, _) -> union_all (List.map go es)
  | ERecord (fields, _) -> union_all (List.map (fun (_, ex) -> go ex) fields)
  | ERecordUpdate (base, fields, _) ->
    union_all (go base :: List.map (fun (_, ex) -> go ex) fields)
  | EField (ex, _, _) -> go ex
  | EIf (c, t, f, _) -> union_all [ go c; go t; go f ]
  | ECond (arms, _) -> union_all (List.map (fun (ce, be) -> StrSet.union (go ce) (go be)) arms)
  | EAnnot (ex, _, _) -> go ex
  | EAtom (_, args, _) -> union_all (List.map go args)
  | ESend (a, b, _) -> StrSet.union (go a) (go b)
  | ESpawn (e, _) -> go e
  | ELetFn (name, params, _, body, _) ->
    let inner_bound =
      List.fold_left (fun b (p : param) -> StrSet.add p.param_name.txt b)
        (StrSet.add name.txt bound) params
    in
    free_names inner_bound body
  | ELetQ (p, result, cont, _) ->
    let pat_bound = free_pattern_names p in
    StrSet.union (go result) (free_names (StrSet.union pat_bound bound) cont)
  | EPipe (l, r, _) -> StrSet.union (go l) (go r)
  | EAssert (e, _) -> go e
  | ESigil (_, content, _) -> go content

and free_names_block (bound : StrSet.t) (es : expr list) : StrSet.t =
  match es with
  | [] -> StrSet.empty
  | ELet (b, _) :: rest ->
    let used_in_rhs = free_names bound b.bind_expr in
    let pat_bound = free_pattern_names b.bind_pat in
    StrSet.union used_in_rhs (free_names_block (StrSet.union pat_bound bound) rest)
  | e :: rest -> StrSet.union (free_names bound e) (free_names_block bound rest)

and free_pattern_names (p : pattern) : StrSet.t =
  match p with
  | PatVar n -> StrSet.singleton n.txt
  | PatWild _ | PatLit _ -> StrSet.empty
  | PatCon (_, ps) -> union_all (List.map free_pattern_names ps)
  | PatAtom (_, ps, _) -> union_all (List.map free_pattern_names ps)
  | PatTuple (ps, _) -> union_all (List.map free_pattern_names ps)
  | PatRecord (fields, _) -> union_all (List.map (fun (_, p) -> free_pattern_names p) fields)
  | PatAs (p, n, _) -> StrSet.add n.txt (free_pattern_names p)
  | PatOr (ps, _) -> union_all (List.map free_pattern_names ps)

and union_all (sets : StrSet.t list) : StrSet.t =
  List.fold_left StrSet.union StrSet.empty sets

(** Names Prelude's own top-level function bodies actually reference bare
    (params bound within each body excluded). This is the real "dangerous
    to shadow" set — a strict subset of [prelude_decls]'s own names plus
    whatever builtins Prelude happens to call. *)
let internally_referenced_names (prelude_decls : decl list) : StrSet.t =
  StrMap.fold
    (fun _name (site, bodies) acc ->
       let param_bound = StrSet.empty in
       ignore site;
       List.fold_left (fun acc body -> StrSet.union acc (free_names param_bound body))
         acc bodies)
    (top_level_fn_sites prelude_decls) StrSet.empty

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
    that also names a name Prelude's OWN code calls internally — either a
    Prelude [DFn] in [prelude_decls] or a native builtin in
    [ordinary_builtin_names], restricted in both cases to names actually
    referenced from within Prelude's own function bodies (see the module
    doc comment). A name matching one of [iface_method_arities] is exempt
    exactly when the entry function's own arity matches the expected one.
    An ordinary distinct name, a Prelude/builtin name Prelude never calls
    internally, or a supported dispatch overload is left untouched. *)
let check ~(prelude_decls : decl list) ~(ordinary_builtin_names : string list)
    ~(iface_method_arities : (string * int) list) ~(entry_decls : decl list)
    (errors : March_errors.Errors.ctx) : unit =
  let dangerous = internally_referenced_names prelude_decls in
  let prelude_sites = top_level_fn_sites prelude_decls in
  let builtin_set =
    List.fold_left (fun s n -> StrSet.add n s) StrSet.empty ordinary_builtin_names in
  let iface_arities =
    List.fold_left (fun m (n, a) -> StrMap.add n a m) StrMap.empty iface_method_arities in
  StrMap.iter
    (fun name (site, _bodies) ->
       if StrMap.mem name prelude_sites && StrSet.mem name dangerous then
         report_collision errors ~name ~span:site.fs_span
           ~reason:"a name the March standard library relies on internally"
       else if StrSet.mem name builtin_set && StrSet.mem name dangerous then
         report_collision errors ~name ~span:site.fs_span
           ~reason:"a March compiler builtin Prelude relies on internally"
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
