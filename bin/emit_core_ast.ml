(** The [--emit-core-ast] JSON writer.

    Lifted verbatim out of [bin/main.ml] (Target A, task A4 of
    [specs/plans/2026-08-27-remaining-decomposition-targets.md]): 137 lines of
    pure serialisation that end in [exit], sharing nothing with the compile
    pipeline but its results.

    One JSON document per invocation -- verdict, diagnostics, the desugared
    module with [resolved_ty] on every node, plus [schemes],
    [instantiations] and [module_caps].  This is what
    [scripts/types-oracle.sh]'s Tier 1 hashes over ~600 fixtures, so a
    byte-identical Tier 1 is a strong proof for this module specifically.

    The body keeps [compile]'s original indentation: OCaml is insensitive to
    it, and re-indenting would forfeit the byte-for-byte motion proof. *)

let run ~(filename : string) ~(user_files : string list) ~user_ast ~type_map
        ~(diags : March_errors.Errors.diagnostic list) ~is_user_file
        ~(typecheck_env : March_typecheck.Typecheck.env)
        ~(rejected : bool) : unit =
    let verdict =
      if rejected
      then "reject" else "accept"
    in
    let diagnostics_json =
      diags
      |> List.filter is_user_file
      |> List.map March_errors.Errors.render_diagnostic_json
      |> March_dump.Dump.json_list
    in
    let module_json = March_dump.Ast_json.module_to_json ~types:type_map user_ast in
    (* The witness tables accumulate entries from the WHOLE typechecked
       program (stdlib injection included), but the emitted "module" is
       only [user_ast] — so scope both tables down to what the user's code
       actually exercises, using the same file-membership test as
       [is_user_file] above (entry file / "" / "<unknown>" / any resolved
       import file). An instantiation's use_span.file tells us whether that
       use-site is in user code; a scheme is kept iff some retained
       instantiation still references its [ids] (scheme+instantiation are
       recorded together at the same [instantiate] call keyed by the
       use-site span, so this is lossless for every user-visible use,
       including a user's use of a stdlib/builtin polymorphic function). *)
    let is_user_span_file (f : string) =
      f = filename || f = "" || f = "<unknown>" || List.mem f user_files
    in
    let insts_filtered =
      Hashtbl.fold
        (fun (sp : March_ast.Ast.span) (ids, args) acc ->
          if is_user_span_file sp.March_ast.Ast.file then (sp, ids, args) :: acc else acc)
        typecheck_env.March_typecheck.Typecheck.inst_witnesses []
    in
    let insts_sorted =
      List.sort
        (fun ((sp1 : March_ast.Ast.span), _, _) ((sp2 : March_ast.Ast.span), _, _) ->
          compare
            (sp1.March_ast.Ast.file, sp1.March_ast.Ast.start_line, sp1.March_ast.Ast.start_col,
             sp1.March_ast.Ast.end_line, sp1.March_ast.Ast.end_col)
            (sp2.March_ast.Ast.file, sp2.March_ast.Ast.start_line, sp2.March_ast.Ast.start_col,
             sp2.March_ast.Ast.end_line, sp2.March_ast.Ast.end_col))
        insts_filtered
    in
    let insts_json =
      List.map
        (fun (sp, ids, args) ->
          March_dump.Dump.json_obj
            [ ("use_span", March_dump.Ast_json.span_to_json sp);
              ("ids", March_dump.Dump.json_list (List.map string_of_int ids));
              ("args",
               March_dump.Dump.json_list (List.map March_dump.Ast_json.resolved_ty_to_json args)) ])
        insts_sorted
    in
    let retained_ids = List.map (fun (_, ids, _) -> ids) insts_sorted in
    let schemes_filtered =
      Hashtbl.fold
        (fun ids (cs, ty) acc ->
          if List.mem ids retained_ids then (ids, cs, ty) :: acc else acc)
        typecheck_env.March_typecheck.Typecheck.scheme_witnesses []
    in
    let schemes_sorted =
      List.sort (fun (ids1, _, _) (ids2, _, _) -> compare ids1 ids2) schemes_filtered
    in
    let schemes_json =
      List.map
        (fun (ids, cs, ty) ->
          March_dump.Dump.json_obj
            [ ("ids", March_dump.Dump.json_list (List.map string_of_int ids));
              ("constraints",
               March_dump.Dump.json_list (List.map March_dump.Ast_json.constraint_to_json cs));
              ("body", March_dump.Ast_json.resolved_ty_to_json ty) ])
        schemes_sorted
    in
    (* A3: the (module_name, declared_needs) table the typechecker builds as
       each nested DMod finishes (typecheck.ml:8736). The Lean conformance
       checker consumes this for Check 4 (transitive `use` coverage): a module
       that `use`s another inherits an obligation to cover that module's
       declared needs.

       module_caps is keyed by module name — each module contributes its
       fully-qualified path plus, when it differs, its bare name — and is
       consed onto the head as each DMod finishes, so it can (and, with a
       nested user module that shadows a stdlib name, does) contain
       duplicate keys. march's own
       Check 4 resolves this same table via [List.assoc_opt imported
       env.module_caps] (typecheck.ml:6832, :7068) on the unsorted, cons-order
       list — [List.assoc_opt] returns the FIRST match it finds scanning from
       the head, i.e. the most-recently-consed entry for that name. To keep
       this emitted table a genuine function of module name (so a downstream
       decoder folding the array into a map has nothing to guess), we
       de-duplicate BEFORE sorting, keeping exactly the first occurrence in
       the original cons-order list — the same entry [List.assoc_opt] would
       resolve to. Only after de-duplication is sorting order-preserving in
       the sense that matters: with unique keys, [List.stable_sort] (NOT
       plain [List.sort], which OCaml's stdlib does not document as stable)
       just reorders those already-resolved entries by name for a
       deterministic, diff-stable envelope.

       This table is emitted IN FULL (every module the typechecker ever
       recorded a nested DMod for, including all of stdlib — currently ~99
       modules), not filtered down to the set reachable from this file's own
       `use`s. That is a conscious tradeoff, not an oversight: filtering to
       `use`-reachable modules risks under-emitting if the reachability
       computation here ever disagrees with march's own, and a missing entry
       would silently make Check 4 pass downstream (no entry to violate) —
       a false accept, which is the exact failure this key exists to
       prevent. The cost is that golden fixtures are sensitive to unrelated
       stdlib `needs` edits; that coupling is accepted deliberately in
       exchange for never under-emitting. *)
    let module_caps_dedup =
      let seen = Hashtbl.create 16 in
      List.filter (fun (m, _) ->
        if Hashtbl.mem seen m then false
        else begin Hashtbl.add seen m (); true end)
        typecheck_env.March_typecheck.Typecheck.module_caps
    in
    let module_caps_json =
      module_caps_dedup
      |> List.stable_sort (fun (a, _) (b, _) -> String.compare a b)
      |> List.map (fun (m, needs) ->
           March_dump.Dump.json_obj
             [ ("module", March_dump.Dump.json_string m);
               ("needs",
                March_dump.Dump.json_list
                  (List.map March_dump.Dump.json_string needs)) ])
    in
    let doc =
      March_dump.Dump.json_obj [
        ("format_version", "3");
        ("verdict", March_dump.Dump.json_string verdict);
        ("diagnostics", diagnostics_json);
        ("module", module_json);
        ("schemes", March_dump.Dump.json_list schemes_json);
        ("instantiations", March_dump.Dump.json_list insts_json);
        ("module_caps", March_dump.Dump.json_list module_caps_json);
      ]
    in
    print_string doc;
    exit (if verdict = "accept" then 0 else 1)