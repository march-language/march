(** Cursor- and diagnostic-driven code actions: quick fixes attached to a
    diagnostic (exhaustiveness, unused binding/import, naming, De Morgan,
    the fix registry, HTML close, refinement) plus the cursor-position
    refactorings that do not need the raw AST.

    [code_actions_at] moved here verbatim from [analysis.ml], keeping its
    exact signature — [~line ~character ?diagnostics ()], trailing unit
    included. [Analysis] re-exports it with [include Code_actions_diag], so
    [Analysis.code_actions_at] is unchanged for every caller.

    [open Code_actions_ast] is what makes the internal
    [@ ast_code_actions a ~line ~character] line below resolve; the AST engine
    is spliced in at its original position in the concatenation, not appended
    at the end, so the order of the returned actions is unchanged. *)

open Analysis_util
open Code_actions_ast

(** Generate code actions relevant to the cursor position [line, character].
    Produces cursor- and diagnostic-driven quick fixes and refactorings;
    see [ast_code_actions] for the AST-driven refactorings (pipe, extract,
    inline, capture, holes, scaffolding). *)
let code_actions_at (a : t) ~line ~character
    ?(diagnostics : Lsp.Types.Diagnostic.t list = [])
    ()
    : Lsp.Types.CodeAction.t list =
  let open Lsp.Types in
  (* ---- Make-linear actions ---- *)
  let make_linear_actions =
    List.filter_map (fun (c : consumption) ->
        let span = c.con_def in
        if not (Pos.span_contains span ~line ~character) then None
        else if List.length c.con_uses <> 1 then None
        else begin
          let name = c.con_name in
          let hint_ofs =
            offset_of_pos a.src (span.Ast.start_line - 1) span.Ast.start_col
          in
          match find_name_ofs a.src name hint_ofs with
          | None -> None
          | Some name_ofs ->
            let insert_line = ref 0 and insert_col = ref 0 in
            let cur_line = ref 0 and cur_col = ref 0 in
            String.iteri (fun i _ch ->
                if i = name_ofs then begin
                  insert_line := !cur_line;
                  insert_col  := !cur_col
                end;
                if a.src.[i] = '\n' then begin incr cur_line; cur_col := 0 end
                else incr cur_col
              ) a.src;
            let range =
              Range.create
                ~start:(Position.create ~line:!insert_line ~character:!insert_col)
                ~end_:(Position.create  ~line:!insert_line ~character:!insert_col)
            in
            let edit = TextEdit.create ~range ~newText:"linear " in
            let uri  = DocumentUri.of_path a.filename in
            let we   = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
            let action = CodeAction.create
                           ~title:(Printf.sprintf "Make `%s` linear" name)
                           ~kind:CodeActionKind.RefactorRewrite
                           ~edit:we
                           () in
            Some action
        end
      ) a.consumption
  in
  (* ---- Exhaustion quickfix actions ---- *)
  (* Helper: derive a variable name from an AST surface type (for typed stubs). *)
  let name_from_ast_ty (ty : Ast.ty) =
    match ty with
    | Ast.TyCon (n, args) ->
      (match n.Ast.txt, args with
       | "Int",    []  -> "n"
       | "String", []  -> "s"
       | "Float",  []  -> "f"
       | "Bool",   []  -> "b"
       | "List",   _   -> "items"
       | "Option", _   -> "opt"
       | name, _ ->
         let lower = String.lowercase_ascii name in
         if lower = "" then "x" else String.sub lower 0 1)
    | Ast.TyVar v -> v.Ast.txt
    | _ -> "x"
  in
  (* Helper: deduplicate a list of names by appending numeric suffixes. *)
  let dedup_names names =
    let counts : (string, int) Hashtbl.t = Hashtbl.create 4 in
    List.iter (fun n ->
        Hashtbl.replace counts n
          (1 + (match Hashtbl.find_opt counts n with Some c -> c | None -> 0))
      ) names;
    let seen : (string, int) Hashtbl.t = Hashtbl.create 4 in
    List.map (fun n ->
        let total = match Hashtbl.find_opt counts n with Some c -> c | None -> 1 in
        if total = 1 then n
        else begin
          let idx = 1 + (match Hashtbl.find_opt seen n with Some c -> c | None -> 0) in
          Hashtbl.replace seen n idx;
          Printf.sprintf "%s%d" n idx
        end
      ) names
  in
  (* Helper: generate arm text for one missing case using typed stubs. *)
  let arm_text_for_case (ms : match_site) case =
    (* March match arms are `pattern -> body` with NO leading `|` (arms separate
       on newline). A leading `|` after the existing newline is a double
       separator → parse error. *)
    match List.assoc_opt case ms.ms_ctor_sigs with
    | None | Some [] ->
      Printf.sprintf "%s ->\n    ?\n" case
    | Some arg_tys ->
      let base_names = List.map name_from_ast_ty arg_tys in
      let names = dedup_names base_names in
      Printf.sprintf "%s(%s) ->\n    ?\n" case (String.concat ", " names)
  in
  (* Helper: given a match_site, compute the insert position just before 'end' *)
  let insert_pos_for_match_site (ms : match_site) =
    match find_end_before_span a.src ms.ms_span with
    | None -> None
    | Some end_ofs ->
      let e_line = ref 0 and e_col = ref 0 in
      let cl = ref 0 and cc = ref 0 in
      String.iteri (fun i _ch ->
          if i = end_ofs then begin
            e_line := !cl;
            e_col  := !cc
          end;
          if a.src.[i] = '\n' then begin incr cl; cc := 0 end
          else incr cc
        ) a.src;
      Some (Position.create ~line:!e_line ~character:!e_col)
  in
  (* A match expression's AST span starts at the SCRUTINEE, not the `match`
     keyword (e.g. `match d do … end` spans from `d`), so a cursor sitting on
     the `match` keyword is NOT column-contained by ms_span.  For a whole-match
     quickfix, accept the cursor anywhere on the match statement's LINE range
     rather than requiring exact column containment. *)
  let cursor_on_match (ms : match_site) =
    let sl = ms.ms_span.Ast.start_line - 1 and el = ms.ms_span.Ast.end_line - 1 in
    line >= sl && line <= el
  in
  let exhaustion_actions =
    List.concat_map (fun (ms : match_site) ->
        if not (cursor_on_match ms) then []
        else begin
          match insert_pos_for_match_site ms with
          | None -> []
          | Some insert_pos ->
            let range = Range.create ~start:insert_pos ~end_:insert_pos in
            let uri   = DocumentUri.of_path a.filename in
            (* Individual "Add missing case: X" actions — typed stubs via arm_text_for_case *)
            let individual_actions =
              List.map (fun case ->
                  let arm_text = arm_text_for_case ms case in
                  let edit = TextEdit.create ~range ~newText:arm_text in
                  let we   = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
                  CodeAction.create
                    ~title:(Printf.sprintf "Add missing case: %s" case)
                    ~kind:CodeActionKind.QuickFix
                    ~edit:we
                    ()
                ) ms.ms_missing_cases
            in
            (* "Add all N missing cases" when there are multiple *)
            let bulk_action =
              if List.length ms.ms_missing_cases <= 1 then []
              else begin
                let arm_texts = List.map (arm_text_for_case ms) ms.ms_missing_cases in
                let combined = String.concat "" arm_texts in
                let edit = TextEdit.create ~range ~newText:combined in
                let we   = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
                [CodeAction.create
                   ~title:(Printf.sprintf "Add all %d missing cases"
                             (List.length ms.ms_missing_cases))
                   ~kind:CodeActionKind.QuickFix
                   ~edit:we
                   ()]
              end
            in
            (* File-scope "Fix all incomplete T matches" when same type has
               multiple incomplete match sites *)
            let file_scope_action =
              match ms.ms_matched_type with
              | None -> []
              | Some tname ->
                let same_type_sites =
                  match List.assoc_opt tname a.type_matches with
                  | Some sites -> sites
                  | None -> []
                in
                if List.length same_type_sites <= 1 then []
                else begin
                  (* Build edits for all sites with missing cases *)
                  let all_edits = List.filter_map (fun (site : match_site) ->
                      if site.ms_missing_cases = [] then None
                      else
                        match insert_pos_for_match_site site with
                        | None -> None
                        | Some ipos ->
                          let r = Range.create ~start:ipos ~end_:ipos in
                          let arm_texts = List.map (arm_text_for_case site) site.ms_missing_cases in
                          Some (TextEdit.create ~range:r
                                  ~newText:(String.concat "" arm_texts))
                    ) same_type_sites
                  in
                  if all_edits = [] then []
                  else
                    let we = WorkspaceEdit.create
                      ~changes:[(uri, all_edits)] () in
                    [CodeAction.create
                       ~title:(Printf.sprintf
                           "Fix all incomplete `%s` matches in file" tname)
                       ~kind:CodeActionKind.RefactorRewrite
                       ~edit:we
                       ()]
                end
            in
            individual_actions @ bulk_action @ file_scope_action
        end
      ) a.match_sites
  in
  (* ---- Suggest-a-refinement action ----

     Offered on a function's own name, for any function with an annotated,
     not-yet-refined parameter.  This test is deliberately syntactic and
     solver-free: computing the actual suggestion costs a full checked module
     plus a series of Z3 queries, which is far too much to spend on every
     cursor movement.  So the action carries a COMMAND rather than an edit —
     the server runs the inference only once the user picks it, and applies the
     result via workspace/applyEdit.  See [March_refinecheck.Precond_infer] for
     the inference and server.ml's `march.suggestRefinement` for the handler. *)
  let refine_actions =
    let refinable (fd : Ast.fn_def) =
      List.exists
        (fun (c : Ast.fn_clause) ->
          List.exists
            (function
              | Ast.FPNamed { Ast.param_ty = Some t; _ }
              | Ast.FPDefault ({ Ast.param_ty = Some t; _ }, _) ->
                (match t with Ast.TyRefine _ -> false | _ -> true)
              | _ -> false)
            c.Ast.fc_params)
        fd.Ast.fn_clauses
    in
    let rec collect prefix (decls : Ast.decl list) =
      List.concat_map
        (function
          | Ast.DFn (fd, _) ->
            let sp = fd.Ast.fn_name.Ast.span in
            if Pos.span_contains sp ~line ~character && refinable fd then
              [ (if prefix = "" then fd.Ast.fn_name.Ast.txt
                 else prefix ^ "." ^ fd.Ast.fn_name.Ast.txt) ]
            else []
          | Ast.DMod (n, _, inner, _) ->
            collect
              (if prefix = "" then n.Ast.txt else prefix ^ "." ^ n.Ast.txt)
              inner
          | _ -> [])
        decls
    in
    (* A second action for the RETURN, offered only when there is a declared
       return type to refine and it is not refined already — the same
       solver-free test as above, for the same reason. *)
    let returns_refinable (fd : Ast.fn_def) =
      match fd.Ast.fn_ret_ty with
      | Some (Ast.TyRefine _) | None -> false
      | Some _ -> true
    in
    let rec collect_ret prefix (decls : Ast.decl list) =
      List.concat_map
        (function
          | Ast.DFn (fd, _) ->
            let sp = fd.Ast.fn_name.Ast.span in
            if Pos.span_contains sp ~line ~character && returns_refinable fd then
              [ (if prefix = "" then fd.Ast.fn_name.Ast.txt
                 else prefix ^ "." ^ fd.Ast.fn_name.Ast.txt) ]
            else []
          | Ast.DMod (n, _, inner, _) ->
            collect_ret
              (if prefix = "" then n.Ast.txt else prefix ^ "." ^ n.Ast.txt) inner
          | _ -> [])
        decls
    in
    List.map
      (fun qname ->
        CodeAction.create
          ~title:(Printf.sprintf "Suggest a refinement type for `%s`" qname)
          ~kind:CodeActionKind.RefactorRewrite
          ~command:
            (Command.create ~title:"Suggest a refinement type"
               ~command:"march.suggestRefinement"
               ~arguments:[ `String a.filename; `String qname ] ())
          ())
      (collect "" a.decls)
    @ List.map
        (fun qname ->
          CodeAction.create
            ~title:(Printf.sprintf "Suggest a postcondition for `%s`" qname)
            ~kind:CodeActionKind.RefactorRewrite
            ~command:
              (Command.create ~title:"Suggest a postcondition"
                 ~command:"march.suggestPostcondition"
                 ~arguments:[ `String a.filename; `String qname ] ())
            ())
        (collect_ret "" a.decls)
  in
  (* ---- Add-type-annotation actions (P1.7 enhanced) ---- *)
  (* Look up the smallest type_map entry containing a point. *)
  let type_at_point rhs_sp =
    let rhs_line = rhs_sp.Ast.start_line - 1 in
    let rhs_char = rhs_sp.Ast.start_col in
    let candidates = Hashtbl.fold (fun sp ty acc ->
        if Pos.span_contains sp ~line:rhs_line ~character:rhs_char
        then (sp, ty) :: acc else acc
      ) a.type_map []
    in
    match candidates with
    | [] -> None
    | _ ->
      let (_, ty) = List.fold_left (fun (bs, bt) (sp, ty) ->
          if Pos.span_smaller sp bs then (sp, ty) else (bs, bt)
        ) (List.hd candidates) (List.tl candidates)
      in
      Some ty
  in
  (* Scan forward from [from_ofs] to find the "do" keyword (word-boundary aware).
     Returns the byte offset of 'd' in "do", or None. Scans at most 400 chars. *)
  let find_do_after from_ofs =
    let src = a.src in
    let len = String.length src in
    let is_ident_char c =
      let k = Char.code c in
      (k >= 97 && k <= 122) || (k >= 65 && k <= 90) || k = 95 || (k >= 48 && k <= 57)
    in
    let limit = min len (from_ofs + 400) in
    let rec find i =
      if i + 2 > limit then None
      else if src.[i] = 'd' && src.[i+1] = 'o'
           && (i = 0 || not (is_ident_char src.[i-1]))
           && (i + 2 >= len || not (is_ident_char src.[i+2]))
      then Some i
      else find (i + 1)
    in
    find from_ofs
  in
  (* Convert a byte offset in a.src to (line, col) 0-indexed. *)
  let ofs_to_lsp_pos ofs =
    let e_line = ref 0 and e_col = ref 0 in
    let cl = ref 0 and cc = ref 0 in
    String.iteri (fun i _ch ->
        if i = ofs then begin e_line := !cl; e_col := !cc end;
        if a.src.[i] = '\n' then begin incr cl; cc := 0 end
        else incr cc
      ) a.src;
    Position.create ~line:!e_line ~character:!e_col
  in
  (* A rendered type is annotatable only if it has a valid surface form in
     annotation position. Named record types now recover their declared name in
     [Tc.pp_ty] and render as a bare identifier (e.g. `R`), which is a valid
     annotation — so those are allowed through. Only *anonymous*/unnameable
     structural records still print as `{ … }`, which March's parser rejects
     after `->` or `:`; refuse those so we never emit an annotation that would
     break the file. The `{` test distinguishes the two cases. *)
  let annotatable_ty_str s = not (String.contains s '{') in
  let make_annotation_action site =
    if not (Pos.span_contains site.as_name_span ~line ~character) then None
    else begin
      let uri = DocumentUri.of_path a.filename in
      match site.as_kind with

      | AnnLet ->
        (* Insert ": Type" after binding name *)
        (match type_at_point site.as_rhs_span with
         | None -> None
         | Some ty ->
           let ty_str = Tc.pp_ty ty in
           (* Anonymous record types render as `{ … }`, which March's parser
              does not accept in annotation position — skip rather than produce
              an edit that would break the file. *)
           if not (annotatable_ty_str ty_str) then None
           else
           let insert_line = site.as_name_span.Ast.start_line - 1 in
           let insert_col  = site.as_name_span.Ast.end_col in
           let pos   = Position.create ~line:insert_line ~character:insert_col in
           let range = Range.create ~start:pos ~end_:pos in
           let edit  = TextEdit.create ~range ~newText:(": " ^ ty_str) in
           let we    = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
           Some (CodeAction.create ~title:"Add type annotation"
                   ~kind:CodeActionKind.RefactorRewrite ~edit:we ()))

      | AnnFnReturn ->
        (* Look up fn type from type_map via fn_name.span; extract return type *)
        (match type_at_point site.as_rhs_span with
         | None -> None
         | Some ty ->
           let (_, ret_str) = unwrap_arrows ty in
           if not (annotatable_ty_str ret_str) then None
           else
           (* Find the "do" keyword after the fn name to determine insert position *)
           let fn_ofs =
             offset_of_pos a.src
               (site.as_name_span.Ast.start_line - 1)
               site.as_name_span.Ast.start_col
           in
           (match find_do_after fn_ofs with
            | None -> None
            | Some do_ofs ->
              let pos   = ofs_to_lsp_pos do_ofs in
              let range = Range.create ~start:pos ~end_:pos in
              (* March return type syntax is `: T` before `do` — NOT `-> T`
                 (`fn f() -> Int do` is a parse error). *)
              let edit  = TextEdit.create ~range
                            ~newText:(": " ^ ret_str ^ " ") in
              let we    = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
              Some (CodeAction.create ~title:"Add return type annotation"
                      ~kind:CodeActionKind.RefactorRewrite ~edit:we ())))

      | AnnFnParam ->
        (* Look up param type from type_map via param_name.span *)
        (match type_at_point site.as_rhs_span with
         | None -> None
         | Some ty ->
           let ty_str = Tc.pp_ty ty in
           if not (annotatable_ty_str ty_str) then None
           else
           let insert_line = site.as_name_span.Ast.start_line - 1 in
           let insert_col  = site.as_name_span.Ast.end_col in
           let pos   = Position.create ~line:insert_line ~character:insert_col in
           let range = Range.create ~start:pos ~end_:pos in
           let edit  = TextEdit.create ~range ~newText:(": " ^ ty_str) in
           let we    = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
           Some (CodeAction.create ~title:"Add parameter type annotation"
                   ~kind:CodeActionKind.RefactorRewrite ~edit:we ()))
    end
  in
  let annotation_actions = List.filter_map make_annotation_action a.annotation_sites in
  (* Batch "Annotate all unannotated let bindings in file" action *)
  let batch_annotation_action =
    (* Only show when cursor is on an AnnLet site and there are 2+ AnnLet sites *)
    let cursor_on_ann_let =
      List.exists (fun (site : annotation_site) ->
          site.as_kind = AnnLet &&
          Pos.span_contains site.as_name_span ~line ~character
        ) a.annotation_sites
    in
    let let_sites = List.filter (fun (s : annotation_site) -> s.as_kind = AnnLet)
                      a.annotation_sites in
    if not cursor_on_ann_let || List.length let_sites < 2 then []
    else begin
      let uri = DocumentUri.of_path a.filename in
      let edits = List.filter_map (fun (site : annotation_site) ->
          match type_at_point site.as_rhs_span with
          | None -> None
          | Some ty ->
            let ty_str = Tc.pp_ty ty in
            let insert_line = site.as_name_span.Ast.start_line - 1 in
            let insert_col  = site.as_name_span.Ast.end_col in
            let pos   = Position.create ~line:insert_line ~character:insert_col in
            let range = Range.create ~start:pos ~end_:pos in
            Some (TextEdit.create ~range ~newText:(": " ^ ty_str))
        ) let_sites
      in
      if edits = [] then []
      else
        let we = WorkspaceEdit.create ~changes:[(uri, edits)] () in
        [CodeAction.create
           ~title:(Printf.sprintf "Annotate all %d unannotated bindings in file"
                     (List.length let_sites))
           ~kind:CodeActionKind.RefactorRewrite
           ~edit:we ()]
    end
  in
  (* ---- Remove-unused-binding actions (from diagnostics context) ---- *)
  let extract_name_from_msg msg =
    (* "Unused variable `x`.\n..." → Some "x" *)
    let prefix = "Unused variable `" in
    let plen = String.length prefix in
    if String.length msg >= plen && String.sub msg 0 plen = prefix then
      let rest = String.sub msg plen (String.length msg - plen) in
      (match String.index_opt rest '`' with
       | Some i -> Some (String.sub rest 0 i)
       | None   -> None)
    else
      None
  in
  let diag_cursor_overlap (diag : Lsp.Types.Diagnostic.t) =
    let sl = diag.range.Lsp.Types.Range.start.line in
    let el = diag.range.Lsp.Types.Range.end_.line in
    let sc = diag.range.Lsp.Types.Range.start.character in
    let ec = diag.range.Lsp.Types.Range.end_.character in
    if line > sl && line < el then true
    else if line = sl && line = el then character >= sc && character < ec
    else if line = sl then character >= sc
    else if line = el then character < ec
    else false
  in
  let unused_binding_actions =
    List.concat_map (fun (diag : Lsp.Types.Diagnostic.t) ->
        let has_code = match diag.code with
          | Some (`String "unused_binding") -> true
          | _ -> false
        in
        if not has_code || not (diag_cursor_overlap diag) then []
        else
          let diag_line = diag.range.Lsp.Types.Range.start.line in
          let diag_char = diag.range.Lsp.Types.Range.start.character in
          let msg = match diag.message with `String s -> s | _ -> "" in
          (match extract_name_from_msg msg with
           | None -> []
           | Some name ->
             (* Prefix with underscore: insert "_" before the name *)
             let pfx_pos    = Position.create ~line:diag_line ~character:diag_char in
             let pfx_range  = Range.create ~start:pfx_pos ~end_:pfx_pos in
             let pfx_edit   = TextEdit.create ~range:pfx_range ~newText:"_" in
             let pfx_uri    = DocumentUri.of_path a.filename in
             let pfx_we     = WorkspaceEdit.create ~changes:[(pfx_uri, [pfx_edit])] () in
             let pfx_action = CodeAction.create
               ~title:(Printf.sprintf "Prefix with underscore `_%s`" name)
               ~kind:CodeActionKind.QuickFix
               ~edit:pfx_we
               () in
             (* Remove unused binding: look up consumption for full let span *)
             let remove_actions =
               List.filter_map (fun (c : consumption) ->
                   if c.con_name <> name || c.con_uses <> [] then None
                   else begin
                     let sp = c.con_def in
                     let del_start = Position.create
                       ~line:(sp.Ast.start_line - 1) ~character:0 in
                     let del_end   = Position.create
                       ~line:(sp.Ast.start_line) ~character:0 in
                     let del_range = Range.create ~start:del_start ~end_:del_end in
                     let del_edit  = TextEdit.create ~range:del_range ~newText:"" in
                     let del_uri   = DocumentUri.of_path a.filename in
                     let del_we    = WorkspaceEdit.create ~changes:[(del_uri, [del_edit])] () in
                     Some (CodeAction.create
                       ~title:(Printf.sprintf "Remove unused binding `%s`" name)
                       ~kind:CodeActionKind.QuickFix
                       ~edit:del_we
                       ())
                   end
                 ) a.consumption
             in
             (* P1.8: Assign to _: replace the name with just `_`, discarding result *)
             let assign_end_char = diag_char + String.length name in
             let assign_pos    = Position.create ~line:diag_line ~character:diag_char in
             let assign_end_ps = Position.create ~line:diag_line ~character:assign_end_char in
             let assign_range  = Range.create ~start:assign_pos ~end_:assign_end_ps in
             let assign_edit   = TextEdit.create ~range:assign_range ~newText:"_" in
             let assign_uri    = DocumentUri.of_path a.filename in
             let assign_we     = WorkspaceEdit.create ~changes:[(assign_uri, [assign_edit])] () in
             let assign_action = CodeAction.create
               ~title:"Assign to `_` (discard result)"
               ~kind:CodeActionKind.QuickFix
               ~edit:assign_we
               () in
             pfx_action :: assign_action :: remove_actions)
      ) diagnostics
  in
  (* ---- P2.10: Remove-unused-import actions ---- *)
  (* Helper: delete the line that contains [lsp_range_start].
     Produces a TextEdit that removes characters from column 0 of that line
     through column 0 of the next line (i.e. the whole line including newline). *)
  let delete_line (lsp_line : int) =
    let del_start = Position.create ~line:lsp_line ~character:0 in
    let del_end   = Position.create ~line:(lsp_line + 1) ~character:0 in
    let del_range = Range.create ~start:del_start ~end_:del_end in
    TextEdit.create ~range:del_range ~newText:""
  in
  (* Helper: given the byte offset of a name in a `use Mod.{a, b, c}` import,
     remove just that name (plus the adjacent comma/space) from the brace list.
     Returns a TextEdit, or None if the context cannot be parsed (fall back to
     whole-line deletion). *)
  let remove_name_from_import_list name_start_ofs name_len =
    let src = a.src in
    let src_len = String.length src in
    let name_end_ofs = name_start_ofs + name_len in
    (* Scan backwards to find ',' or '{' *)
    let rec scan_back i =
      if i < 0 then None
      else match src.[i] with
        | '{' -> Some (`OpenBrace i)
        | ',' -> Some (`CommaBefore i)
        | ' ' | '\t' -> scan_back (i - 1)
        | _ -> None
    in
    (* Scan forwards from name end to find ',' or '}' *)
    let rec scan_fwd i =
      if i >= src_len then None
      else match src.[i] with
        | '}' -> Some (`CloseBrace i)
        | ',' -> Some (`CommaAfter i)
        | ' ' | '\t' -> scan_fwd (i + 1)
        | _ -> None
    in
    match scan_back (name_start_ofs - 1), scan_fwd name_end_ofs with
    | Some (`OpenBrace _), Some (`CommaAfter comma_ofs) ->
      (* First name: remove "name, " (and trailing spaces) *)
      let del_end_ofs =
        let j = ref (comma_ofs + 1) in
        while !j < src_len && (src.[!j] = ' ' || src.[!j] = '\t') do incr j done;
        !j
      in
      let start_line = ref 0 and start_col = ref 0 in
      let cur_l = ref 0 and cur_c = ref 0 in
      String.iteri (fun i _ ->
          if i = name_start_ofs then begin start_line := !cur_l; start_col := !cur_c end;
          if src.[i] = '\n' then begin incr cur_l; cur_c := 0 end else incr cur_c
        ) src;
      let end_line = ref 0 and end_col = ref 0 in
      let cur_l2 = ref 0 and cur_c2 = ref 0 in
      String.iteri (fun i _ ->
          if i = del_end_ofs then begin end_line := !cur_l2; end_col := !cur_c2 end;
          if src.[i] = '\n' then begin incr cur_l2; cur_c2 := 0 end else incr cur_c2
        ) src;
      let r = Range.create
        ~start:(Position.create ~line:!start_line ~character:!start_col)
        ~end_:(Position.create ~line:!end_line ~character:!end_col) in
      Some (TextEdit.create ~range:r ~newText:"")
    | Some (`CommaBefore comma_ofs), _ ->
      (* Non-first name: remove ", name" (comma + optional spaces + name) *)
      let del_start_ofs = comma_ofs in
      let start_line = ref 0 and start_col = ref 0 in
      let cur_l = ref 0 and cur_c = ref 0 in
      String.iteri (fun i _ ->
          if i = del_start_ofs then begin start_line := !cur_l; start_col := !cur_c end;
          if src.[i] = '\n' then begin incr cur_l; cur_c := 0 end else incr cur_c
        ) src;
      let end_line = ref 0 and end_col = ref 0 in
      let cur_l2 = ref 0 and cur_c2 = ref 0 in
      String.iteri (fun i _ ->
          if i = name_end_ofs then begin end_line := !cur_l2; end_col := !cur_c2 end;
          if src.[i] = '\n' then begin incr cur_l2; cur_c2 := 0 end else incr cur_c2
        ) src;
      let r = Range.create
        ~start:(Position.create ~line:!start_line ~character:!start_col)
        ~end_:(Position.create ~line:!end_line ~character:!end_col) in
      Some (TextEdit.create ~range:r ~newText:"")
    | _ -> None
  in
  let unused_import_actions =
    List.concat_map (fun (diag : Lsp.Types.Diagnostic.t) ->
        let has_code = match diag.code with
          | Some (`String "unused_import") -> true
          | _ -> false
        in
        if not has_code || not (diag_cursor_overlap diag) then []
        else begin
          let uri   = DocumentUri.of_path a.filename in
          let msg   = match diag.message with `String s -> s | _ -> "" in
          let diag_lsp_line = diag.range.Lsp.Types.Range.start.line in
          let diag_lsp_char = diag.range.Lsp.Types.Range.start.character in
          (* Messages from warn_unused_imports:
             "Unused import: nothing from `X` is used." — whole-module import
             "Unused import `name` from `X`."           — specific name *)
          let is_whole_module =
            let prefix = "Unused import: nothing from" in
            let plen = String.length prefix in
            String.length msg >= plen && String.sub msg 0 plen = prefix
          in
          (* Extract the name from "Unused import `name` from `Mod`" messages *)
          let extract_import_name m =
            let prefix = "Unused import `" in
            let plen = String.length prefix in
            if String.length m >= plen && String.sub m 0 plen = prefix then
              let rest = String.sub m plen (String.length m - plen) in
              match String.index_opt rest '`' with
              | Some i -> Some (String.sub rest 0 i)
              | None -> None
            else None
          in
          if is_whole_module then
            (* Delete the entire import line *)
            let edit = delete_line diag_lsp_line in
            let we   = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
            [CodeAction.create
               ~title:"Remove unused import"
               ~kind:CodeActionKind.QuickFix
               ~edit:we ()]
          else begin
            match extract_import_name msg with
            | None ->
              (* Fallback: delete whole line *)
              let edit = delete_line diag_lsp_line in
              let we   = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
              [CodeAction.create
                 ~title:"Remove unused import"
                 ~kind:CodeActionKind.QuickFix
                 ~edit:we ()]
            | Some name ->
              (* Specific name: try to remove just the name from the import list;
                 fall back to whole-line removal if context can't be parsed. *)
              let name_ofs = offset_of_pos a.src diag_lsp_line diag_lsp_char in
              let smart_edit = remove_name_from_import_list name_ofs (String.length name) in
              let edit = match smart_edit with
                | Some e -> e
                | None   -> delete_line diag_lsp_line
              in
              let we = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
              [CodeAction.create
                 ~title:(Printf.sprintf "Remove unused import `%s`" name)
                 ~kind:CodeActionKind.QuickFix
                 ~edit:we ()]
          end
        end
      ) diagnostics
  in
  (* ---- P3.4: Introduce / Remove Debug.inspect ---- *)
  (* Helper: find the smallest type_map span that contains the cursor,
     returning (span, lsp_start_position, lsp_end_position). *)
  let innermost_expr_span_at ~line ~character =
    let candidates = Hashtbl.fold (fun sp _ acc ->
        if Pos.span_contains sp ~line ~character then sp :: acc
        else acc
      ) a.type_map []
    in
    match candidates with
    | [] -> None
    | _ ->
      let best = List.fold_left (fun best sp ->
          if Pos.span_smaller sp best then sp else best
        ) (List.hd candidates) (List.tl candidates)
      in
      Some best
  in
  (* "Wrap with inspect": wrap the innermost expression at cursor. *)
  let wrap_inspect_actions =
    match innermost_expr_span_at ~line ~character with
    | None -> []
    | Some sp ->
      (* Only offer if the span is within this file *)
      if sp.Ast.file <> a.filename && sp.Ast.file <> "" && sp.Ast.file <> "<unknown>"
      then []
      else begin
        (* Extract the source text of the expression for the label hint *)
        let expr_start_ofs = offset_of_pos a.src (sp.Ast.start_line - 1) sp.Ast.start_col in
        let expr_end_ofs   = offset_of_pos a.src (sp.Ast.end_line - 1) sp.Ast.end_col in
        let expr_text =
          if expr_end_ofs > expr_start_ofs && expr_end_ofs <= String.length a.src
          then String.sub a.src expr_start_ofs (expr_end_ofs - expr_start_ofs)
          else "expr"
        in
        (* Use first 20 chars of the expression as the label, sanitised *)
        let raw_label = if String.length expr_text > 20
                        then String.sub expr_text 0 20 ^ "..."
                        else expr_text in
        let label = String.concat "" (List.map (fun c ->
            if c = '"' || c = '\\' || c = '\n' || c = '\r' || c = '\t'
            then "_" else String.make 1 c) (List.init (String.length raw_label)
                                              (String.get raw_label))) in
        let uri    = DocumentUri.of_path a.filename in
        let s_line = sp.Ast.start_line - 1 in
        let s_col  = sp.Ast.start_col in
        let e_line = sp.Ast.end_line - 1 in
        let e_col  = sp.Ast.end_col in
        let prefix_range = Range.create
          ~start:(Position.create ~line:s_line ~character:s_col)
          ~end_:(Position.create ~line:s_line ~character:s_col) in
        let suffix_range = Range.create
          ~start:(Position.create ~line:e_line ~character:e_col)
          ~end_:(Position.create ~line:e_line ~character:e_col) in
        let prefix_edit = TextEdit.create ~range:prefix_range ~newText:"inspect(" in
        let suffix_edit = TextEdit.create ~range:suffix_range
            ~newText:(Printf.sprintf ", \"%s\")" label) in
        let we = WorkspaceEdit.create ~changes:[(uri, [prefix_edit; suffix_edit])] () in
        [CodeAction.create
           ~title:"Wrap with inspect"
           ~kind:CodeActionKind.RefactorRewrite
           ~edit:we ()]
      end
  in
  (* "Remove inspect": detect `inspect(inner, "label")` around cursor and unwrap. *)
  let remove_inspect_actions =
    let src = a.src in
    let src_len = String.length src in
    let cursor_ofs = offset_of_pos src line character in
    (* Scan backwards for "inspect(" — look within same line *)
    let line_start_ofs = offset_of_pos src line 0 in
    let inspect_keyword = "inspect(" in
    let iklen = String.length inspect_keyword in
    (* Find last occurrence of "inspect(" before cursor on same line *)
    let inspect_start =
      let result = ref None in
      let i = ref (min cursor_ofs (src_len - iklen)) in
      while !i >= line_start_ofs do
        if !i + iklen <= src_len
           && String.sub src !i iklen = inspect_keyword then begin
          result := Some !i;
          i := -1
        end else
          decr i
      done;
      !result
    in
    match inspect_start with
    | None -> []
    | Some start_ofs ->
      (* Find matching closing paren, skipping nested parens *)
      let inner_start = start_ofs + iklen in
      let depth = ref 1 in
      let i = ref inner_start in
      while !i < src_len && !depth > 0 do
        (match src.[!i] with
         | '(' -> incr depth
         | ')' -> decr depth
         | _ -> ());
        if !depth > 0 then incr i else ()
      done;
      if !depth <> 0 then []
      else begin
        let close_ofs = !i in
        (* The inspect call spans [start_ofs, close_ofs] inclusive.
           Find the first argument (before the first top-level comma). *)
        let comma_ofs =
          let d = ref 0 in
          let c = ref None in
          let j = ref inner_start in
          while !j < close_ofs && !c = None do
            (match src.[!j] with
             | '(' | '[' | '{' -> incr d
             | ')' | ']' | '}' -> decr d
             | ',' when !d = 0 -> c := Some !j
             | _ -> ());
            if !c = None then incr j
          done;
          !c
        in
        let inner_end = match comma_ofs with
          | Some co -> co  (* inner expression is [inner_start, co) *)
          | None    -> close_ofs  (* no comma → whole inner part *)
        in
        (* Trim whitespace from inner expression boundaries *)
        let is_ws c = c = ' ' || c = '\t' || c = '\n' || c = '\r' in
        let inner_s = ref inner_start in
        while !inner_s < inner_end && is_ws src.[!inner_s] do incr inner_s done;
        let inner_e = ref (inner_end - 1) in
        while !inner_e >= !inner_s && is_ws src.[!inner_e] do decr inner_e done;
        let inner_text =
          if !inner_e >= !inner_s
          then String.sub src !inner_s (!inner_e - !inner_s + 1)
          else ""
        in
        (* Compute LSP positions for the full inspect(…) range *)
        let mk_lsp_pos ofs =
          let l = ref 0 and c = ref 0 in
          let cl = ref 0 and cc = ref 0 in
          String.iteri (fun i _ ->
              if i = ofs then begin l := !cl; c := !cc end;
              if src.[i] = '\n' then begin incr cl; cc := 0 end else incr cc
            ) src;
          Position.create ~line:!l ~character:!c
        in
        let call_start_pos = mk_lsp_pos start_ofs in
        let call_end_pos   = mk_lsp_pos (close_ofs + 1) in
        let call_range     = Range.create ~start:call_start_pos ~end_:call_end_pos in
        let uri  = DocumentUri.of_path a.filename in
        let edit = TextEdit.create ~range:call_range ~newText:inner_text in
        let we   = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
        [CodeAction.create
           ~title:"Remove inspect"
           ~kind:CodeActionKind.RefactorRewrite
           ~edit:we ()]
      end
  in
  (* ---- Registry-driven fixes from diagnostics context ---- *)
  let registry_actions = apply_fix_registry a diagnostics in
  (* ---- Naming convention rename actions (P2.8) ---- *)
  let naming_actions =
    List.filter_map (fun (nv : naming_violation) ->
        if not (Pos.span_contains nv.nv_span ~line ~character) then None
        else begin
          let def_line = nv.nv_span.Ast.start_line - 1 in
          let def_char = nv.nv_span.Ast.start_col in
          let edits = rename_at a ~line:def_line ~character:def_char
                        ~new_name:nv.nv_suggested in
          if edits = [] then None
          else begin
            let uri = DocumentUri.of_path a.filename in
            let we  = WorkspaceEdit.create ~changes:[(uri, edits)] () in
            let kind_str = match nv.nv_kind with
              | `Function -> "function"
              | `Type -> "type"
            in
            Some (CodeAction.create
              ~title:(Printf.sprintf "Rename %s to `%s`" kind_str nv.nv_suggested)
              ~kind:CodeActionKind.RefactorRewrite
              ~edit:we
              ())
          end
        end
      ) a.naming_violations
  in
  (* ---- De Morgan rewrite actions (P3.10) ---- *)
  let src_slice (sp : Ast.span) =
    let s = offset_of_pos a.src (sp.Ast.start_line - 1) sp.Ast.start_col in
    let e = offset_of_pos a.src (sp.Ast.end_line   - 1) sp.Ast.end_col in
    let n = String.length a.src in
    if s >= 0 && e > s && e <= n then String.sub a.src s (e - s) else ""
  in
  let demorgan_actions =
    List.filter_map (fun (dm : demorgan_site) ->
        if not (Pos.span_contains dm.dm_span ~line ~character) then None
        else begin
          let ls = src_slice dm.dm_left_span in
          let rs = src_slice dm.dm_right_span in
          if ls = "" || rs = "" then None
          else begin
            let (title, new_text) = match dm.dm_form with
              | `NegatedBinop "&&" ->
                ("Apply De Morgan: !(a && b) \xe2\x86\x92 !(a) || !(b)",
                 Printf.sprintf "!(%s) || !(%s)" ls rs)
              | `NegatedBinop "||" ->
                ("Apply De Morgan: !(a || b) \xe2\x86\x92 !(a) && !(b)",
                 Printf.sprintf "!(%s) && !(%s)" ls rs)
              | `PairOfNegs "&&" ->
                ("Apply De Morgan: !a && !b \xe2\x86\x92 !(a || b)",
                 Printf.sprintf "!(%s || %s)" ls rs)
              | `PairOfNegs "||" ->
                ("Apply De Morgan: !a || !b \xe2\x86\x92 !(a && b)",
                 Printf.sprintf "!(%s && %s)" ls rs)
              | _ -> ("", "")
            in
            if title = "" then None
            else begin
              let range = Pos.span_to_lsp_range dm.dm_span in
              let edit  = TextEdit.create ~range ~newText:new_text in
              let uri   = DocumentUri.of_path a.filename in
              let we    = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
              Some (CodeAction.create
                ~title
                ~kind:CodeActionKind.RefactorRewrite
                ~edit:we
                ())
            end
          end
        end
      ) a.demorgan_sites
  in
  (* ---- P3.8: Batch "Fix all" — prefix every unused binding in the file ---- *)
  let batch_fix_all_actions =
    let prefix_edits =
      List.filter_map (fun (diag : Lsp.Types.Diagnostic.t) ->
          match diag.code with
          | Some (`String "unused_binding") ->
            let pos = diag.range.Lsp.Types.Range.start in
            Some (TextEdit.create
                    ~range:(Range.create ~start:pos ~end_:pos) ~newText:"_")
          | _ -> None)
        a.diagnostics
    in
    if List.length prefix_edits < 2 then []
    else
      let uri = DocumentUri.of_path a.filename in
      [CodeAction.create
         ~title:(Printf.sprintf "Fix all: prefix %d unused bindings with `_`"
                   (List.length prefix_edits))
         ~kind:CodeActionKind.SourceFixAll
         ~edit:(WorkspaceEdit.create ~changes:[(uri, prefix_edits)] ()) ()]
  in
  (* ---- Close unclosed HTML tags in a ~H sigil ---- *)
  (* One action per sigil that has unclosed tags, offered when the cursor is on
     any of its unclosed-tag spans; inserts all closers (innermost-first) at the
     sigil's closing quote. *)
  let html_close_actions =
    let uri = DocumentUri.of_path a.filename in
    let groups = Hashtbl.create 4 in   (* insert_span → (closer, count, cursor_hit) *)
    List.iter (fun (hi : html_issue) ->
        let (closer, cnt, hit) =
          try Hashtbl.find groups hi.hi_insert_span
          with Not_found -> (hi.hi_closer, 0, false) in
        let hit = hit || Pos.span_contains hi.hi_open_span ~line ~character in
        Hashtbl.replace groups hi.hi_insert_span (closer, cnt + 1, hit))
      a.html_issues;
    Hashtbl.fold (fun (insert_span : Ast.span) (closer, cnt, hit) acc ->
        if not hit then acc
        else begin
          let pos = Position.create
              ~line:(insert_span.Ast.start_line - 1) ~character:insert_span.Ast.start_col in
          let edit = TextEdit.create ~range:(Range.create ~start:pos ~end_:pos) ~newText:closer in
          let title =
            if cnt = 1 then Printf.sprintf "Close unclosed tag (`%s`)" closer
            else Printf.sprintf "Close %d unclosed tags (`%s`)" cnt closer in
          CodeAction.create ~title ~kind:CodeActionKind.QuickFix
            ~edit:(WorkspaceEdit.create ~changes:[(uri, [edit])] ()) () :: acc
        end)
      groups []
  in
  (* ---- Convert a pure List.map/filter to its parallel form ---- *)
  let parallelize_actions =
    List.filter_map (fun (pi : perf_insight) ->
        match pi.pi_kind with
        | Parallelizable { pi_op = _; pi_par; pi_name_span }
          when Pos.span_contains pi.pi_span ~line ~character ->
          let range = Pos.span_to_lsp_range pi_name_span in
          let edit  = TextEdit.create ~range ~newText:pi_par in
          let uri   = DocumentUri.of_path a.filename in
          let we    = WorkspaceEdit.create ~changes:[(uri, [edit])] () in
          Some (CodeAction.create
                  ~title:(Printf.sprintf "Convert to `List.%s`" pi_par)
                  ~kind:CodeActionKind.RefactorRewrite
                  ~edit:we
                  ~diagnostics:[perf_insight_to_diag pi]
                  ())
        | _ -> None
      ) a.perf_insights
  in
  (* ---- Add `@[no_alloc]` on a verified-clean function ---- *)
  (* Same generation scope `forge fix --contracts` uses, so the editor offers
     the action exactly where forge would insert it. *)
  let no_alloc_actions =
    List.filter_map (fun (_name, (name_span : Ast.span), (decl_span : Ast.span)) ->
        if not (Pos.span_contains decl_span ~line ~character
                || Pos.span_contains name_span ~line ~character) then None
        else begin
          let pos = Position.create
              ~line:(decl_span.Ast.start_line - 1) ~character:decl_span.Ast.start_col in
          let indent = String.make decl_span.Ast.start_col ' ' in
          let edit = TextEdit.create ~range:(Range.create ~start:pos ~end_:pos)
              ~newText:("@[no_alloc]\n" ^ indent) in
          let uri = DocumentUri.of_path a.filename in
          Some (CodeAction.create ~title:"Add `@[no_alloc]`"
                  ~kind:CodeActionKind.QuickFix
                  ~edit:(WorkspaceEdit.create ~changes:[(uri, [edit])] ()) ())
        end) a.no_alloc_candidates
  in
  make_linear_actions @ exhaustion_actions @ annotation_actions
  @ batch_annotation_action @ unused_binding_actions @ unused_import_actions
  @ wrap_inspect_actions @ remove_inspect_actions
  @ naming_actions @ demorgan_actions
  @ batch_fix_all_actions
  @ ast_code_actions a ~line ~character
  @ registry_actions
  @ html_close_actions
  @ parallelize_actions
  @ no_alloc_actions
  @ refine_actions

