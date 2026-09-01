(** The string-keyed LSP request dispatcher — the 22 methods linol either could
    not decode or decoded without having a dedicated [on_req_*] handler for.

    Moved verbatim out of [Server]'s [dispatch_by_method] (Target C task C3 of
    specs/plans/2026-08-27-remaining-decomposition-targets.md). It used no [self]
    and no [super]: it was a free function wearing a method's clothes, closing
    over [params] and four local helpers, and reading eight names that task C2
    had already moved to {!Server_state}.

    ORDER IS SEMANTICS. This is an [if]/[else if] chain, so
    ["textDocument/semanticTokens/full"] must stay ahead of [".../full/delta"]
    (it is a strict prefix), and ["callHierarchy/incomingCalls"] ahead of the arm
    that handles [incomingCalls || outgoingCalls] together. No oracle and no test
    sees arm order, so the move asserts it directly: the extracted branch-name
    sequence is diffed against the original's. *)

open Server_state


let dispatch ~notify_back:(_notify_back : _) ~meth ~params =
      ignore _notify_back;
      (* ---- helpers ---- *)
      let get_td_uri () =
        match params with
        | Some (`Assoc fields) ->
          (match List.assoc_opt "textDocument" fields with
           | Some (`Assoc td) ->
             (match List.assoc_opt "uri" td with
              | Some (`String u) ->
                let path =
                  if String.length u >= 7 &&
                     String.sub u 0 7 = "file://"
                  then String.sub u 7 (String.length u - 7)
                  else u
                in
                Some (Lsp.Types.DocumentUri.of_path path)
              | _ -> None)
           | _ -> None)
        | _ -> None
      in
      let get_position () =
        match params with
        | Some (`Assoc fields) ->
          (match List.assoc_opt "position" fields with
           | Some (`Assoc pos) ->
             let line =
               match List.assoc_opt "line" pos with
               | Some (`Int n) -> n | _ -> 0
             in
             let character =
               match List.assoc_opt "character" pos with
               | Some (`Int n) -> n | _ -> 0
             in
             (line, character)
           | _ -> (0, 0))
        | _ -> (0, 0)
      in
      let json_range (r : Lsp.Types.Range.t) =
        `Assoc [
          ("start", `Assoc [
            ("line",      `Int r.Lsp.Types.Range.start.Lsp.Types.Position.line);
            ("character", `Int r.Lsp.Types.Range.start.Lsp.Types.Position.character)]);
          ("end", `Assoc [
            ("line",      `Int r.Lsp.Types.Range.end_.Lsp.Types.Position.line);
            ("character", `Int r.Lsp.Types.Range.end_.Lsp.Types.Position.character)])
        ]
      in
      (* ---- dispatch ---- *)
      let json_ints data =
        `List (Array.to_list (Array.map (fun n -> `Int n) data))
      in
      if meth = "textDocument/semanticTokens/full" then begin
        match get_td_uri () with
        | None -> Lwt.return (`Assoc [("data", `List [])])
        | Some uri ->
          let data =
            match get_analysis uri with None -> [||] | Some a -> semantic_tokens_data a in
          let rid = next_result_id () in
          Hashtbl.replace sem_tokens_cache
            (Lsp.Types.DocumentUri.to_string uri) (rid, data);
          Lwt.return (`Assoc [("resultId", `String rid); ("data", json_ints data)])

      end else if meth = "textDocument/semanticTokens/full/delta" then begin
        let prev_id =
          match params with
          | Some (`Assoc fields) ->
            (match List.assoc_opt "previousResultId" fields with
             | Some (`String s) -> Some s | _ -> None)
          | _ -> None
        in
        match get_td_uri () with
        | None -> Lwt.return (`Assoc [("data", `List [])])
        | Some uri ->
          let key = Lsp.Types.DocumentUri.to_string uri in
          let new_data =
            match get_analysis uri with None -> [||] | Some a -> semantic_tokens_data a in
          let rid = next_result_id () in
          let cached = Hashtbl.find_opt sem_tokens_cache key in
          Hashtbl.replace sem_tokens_cache key (rid, new_data);
          (match cached with
           | Some (old_id, old_data) when Some old_id = prev_id ->
             let (start, delete_count, data) = token_delta old_data new_data in
             Lwt.return (`Assoc [
                 ("resultId", `String rid);
                 ("edits", `List [ `Assoc [
                     ("start", `Int start);
                     ("deleteCount", `Int delete_count);
                     ("data", json_ints data) ]]) ])
           | _ ->
             (* No matching baseline → fall back to a full response. *)
             Lwt.return (`Assoc [("resultId", `String rid); ("data", json_ints new_data)]))

      end else if meth = "textDocument/references" then begin
        let include_declaration =
          match params with
          | Some (`Assoc fields) ->
            (match List.assoc_opt "context" fields with
             | Some (`Assoc ctx) ->
               (match List.assoc_opt "includeDeclaration" ctx with
                | Some (`Bool b) -> b | _ -> false)
             | _ -> false)
          | _ -> false
        in
        let (line, utf16_char) = get_position () in
        let locs =
          match get_td_uri () with
          | None -> []
          | Some uri ->
            (match get_analysis uri with
             | None -> []
             | Some a ->
               (* Current file: live, scope-correct, UTF-16-remapped results. *)
               let local =
                 Analysis.query_references_at a ~include_declaration ~line ~utf16_char
               in
               (* Other files: name-based cross-file references, but ONLY for a
                  top-level symbol (locals are file-scoped). *)
               let byte_col =
                 Utf16.lsp_char_to_byte_col a.Analysis.doc ~line ~utf16_char
               in
               let cross =
                 match Analysis.local_symbol_at a ~line ~character:byte_col with
                 | Some _ -> []
                 | None ->
                   (match Analysis.name_at a ~line ~character:byte_col with
                    | None -> []
                    | Some name ->
                      let cur = a.Analysis.filename in
                      Workspace.references_across (workspace_index_full ()) name
                      |> List.filter (fun (f, _) -> f <> cur)
                      |> List.map (fun (f, sp) ->
                             Lsp.Types.Location.create
                               ~uri:(Lsp.Types.DocumentUri.of_path f)
                               ~range:(Pos.span_to_lsp_range sp)))
               in
               local @ cross)
        in
        Lwt.return
          (`List (List.map (fun (loc : Lsp.Types.Location.t) ->
               `Assoc [
                 ("uri",   `String (Lsp.Types.DocumentUri.to_string loc.uri));
                 ("range", json_range loc.range)
               ]) locs))

      end else if meth = "textDocument/prepareRename" then begin
        let (line, utf16_char) = get_position () in
        let range =
          match get_td_uri () with
          | None -> None
          | Some uri ->
            (match get_analysis uri with
             | None -> None
             | Some a -> Analysis.query_prepare_rename_at a ~line ~utf16_char)
        in
        (match range with
         | None -> Lwt.return `Null               (* reject the rename *)
         | Some r -> Lwt.return (json_range r))

      end else if meth = "textDocument/rename" then begin
        let new_name =
          match params with
          | Some (`Assoc fields) ->
            (match List.assoc_opt "newName" fields with
             | Some (`String s) -> s | _ -> "")
          | _ -> ""
        in
        let (line, utf16_char) = get_position () in
        let edits, uri_str =
          match get_td_uri () with
          | None -> ([], "")
          | Some uri ->
            (match get_analysis uri with
             | None -> ([], "")
             | Some a ->
               let es = Analysis.query_rename_at a ~line ~utf16_char ~new_name in
               (es, Lsp.Types.DocumentUri.to_string uri))
        in
        let json_edits = List.map (fun (e : Lsp.Types.TextEdit.t) ->
            `Assoc [
              ("range",   json_range e.range);
              ("newText", `String e.newText)
            ]) edits
        in
        if edits = [] then
          Lwt.return (`Assoc [("changes", `Assoc [])])
        else
          Lwt.return
            (`Assoc [("changes", `Assoc [(uri_str, `List json_edits)])])

      end else if meth = "textDocument/signatureHelp" then begin
        let (line, utf16_char) = get_position () in
        let result =
          match get_td_uri () with
          | None -> None
          | Some uri ->
            (match get_analysis uri with
             | None -> None
             | Some a -> Analysis.query_signature_help_at a ~line ~utf16_char)
        in
        (match result with
         | None ->
           Lwt.return (`Assoc [("signatures", `List [])])
         | Some (label, param_labels, active_param) ->
           let parameters = List.map (fun p ->
               `Assoc [("label", `String p)]
             ) param_labels in
           Lwt.return
             (`Assoc [
               ("signatures", `List [
                 `Assoc [
                   ("label",      `String label);
                   ("parameters", `List parameters)
                 ]
               ]);
               ("activeSignature", `Int 0);
               ("activeParameter", `Int active_param)
             ]))

      end else if meth = "textDocument/codeLens" then begin
        let items =
          match get_td_uri () with
          | None -> []
          | Some uri ->
            (match get_analysis uri with
             | None -> []
             | Some a ->
               (* Remap code-lens ranges (byte columns) to UTF-16. *)
               List.map (fun (cl : Analysis.code_lens_item) ->
                   { cl with Analysis.cl_range =
                               Pos.remap_range a.Analysis.doc cl.Analysis.cl_range })
                 a.Analysis.code_lens_items)
        in
        let json_items = List.map (fun (cl : Analysis.code_lens_item) ->
            (* Actionable lenses carry a real command id + arguments; the
               informational perf-summary lenses fall back to a client-side
               noop so they still render as a title-only annotation. *)
            let command_id, args =
              match cl.Analysis.cl_command with
              | Some id -> id, cl.Analysis.cl_args
              | None    -> "march.perf.noop", []
            in
            `Assoc [
              ("range", json_range cl.cl_range);
              ("command", `Assoc [
                ("title",   `String cl.cl_title);
                ("command", `String command_id);
                ("arguments", `List args)
              ])
            ]
          ) items
        in
        Lwt.return (`List json_items)

      end else if meth = "textDocument/foldingRange" then begin
        let ranges =
          match get_td_uri () with
          | None -> []
          | Some uri ->
            (match get_analysis uri with
             | None -> []
             | Some a -> a.Analysis.fold_ranges)
        in
        let open Lsp.Types in
        let json_ranges = List.map (fun (sl, el, kind) ->
            (* Use the standard kinds where one applies — editors treat
               `imports` specially (e.g. "fold all imports"), which an
               `Other "imports"` does not reliably reach. *)
            let kind = match kind with
              | "imports" -> FoldingRangeKind.Imports
              | "region"  -> FoldingRangeKind.Region
              | "comment" -> FoldingRangeKind.Comment
              | other     -> FoldingRangeKind.Other other
            in
            let fr = FoldingRange.create
              ~startLine:sl
              ~endLine:el
              ~kind
              ()
            in
            FoldingRange.yojson_of_t fr
          ) ranges
        in
        Lwt.return (`List json_ranges)

      end else if meth = "workspace/symbol" then begin
        let query =
          match params with
          | Some (`Assoc fields) ->
            (match List.assoc_opt "query" fields with
             | Some (`String s) -> s | _ -> "")
          | _ -> ""
        in
        let syms = Workspace.query_symbols (workspace_index ()) query in
        (* Cap to keep responses bounded; names are ASCII so the byte-column
           span maps to UTF-16 directly. *)
        let syms = List.filteri (fun i _ -> i < 200) syms in
        let json = List.map (fun (s : Workspace.ws_symbol) ->
            let uri = Lsp.Types.DocumentUri.of_path s.Workspace.wsy_file in
            `Assoc [
              ("name", `String s.Workspace.wsy_name);
              ("kind", Lsp.Types.SymbolKind.yojson_of_t s.Workspace.wsy_kind);
              ("location", `Assoc [
                  ("uri",   `String (Lsp.Types.DocumentUri.to_string uri));
                  ("range", json_range (Pos.span_to_lsp_range s.Workspace.wsy_span))
                ])
            ]) syms
        in
        Lwt.return (`List json)

      end else if meth = "textDocument/formatting" then begin
        let edits =
          match get_td_uri () with
          | None -> []
          | Some uri ->
            (match get_analysis uri with
             | None -> []
             | Some a ->
               (* Don't format code that doesn't parse (format_source raises). *)
               (try
                  let formatted =
                    Utf16.normalize_trailing
                      (March_format.Format.format_source
                         ~filename:a.Analysis.filename a.Analysis.src)
                  in
                  if formatted = a.Analysis.src then []
                  else
                    let (el, ec) = Utf16.end_position a.Analysis.doc in
                    [ (el, ec, formatted) ]
                with _ -> []))
        in
        let json = List.map (fun (el, ec, text) ->
            `Assoc [
              ("range", `Assoc [
                  ("start", `Assoc [("line", `Int 0); ("character", `Int 0)]);
                  ("end",   `Assoc [("line", `Int el); ("character", `Int ec)])]);
              ("newText", `String text)
            ]) edits
        in
        Lwt.return (`List json)

      end else if meth = "textDocument/implementation" then begin
        let (line, utf16_char) = get_position () in
        let locs =
          match get_td_uri () with
          | None -> []
          | Some uri ->
            (match get_analysis uri with
             | None -> []
             | Some a -> Analysis.query_implementation_at a ~line ~utf16_char)
        in
        Lwt.return
          (`List (List.map (fun (l : Lsp.Types.Location.t) ->
               `Assoc [
                 ("uri",   `String (Lsp.Types.DocumentUri.to_string l.uri));
                 ("range", json_range l.range)
               ]) locs))

      end else if meth = "textDocument/typeDefinition" then begin
        let (line, utf16_char) = get_position () in
        let loc =
          match get_td_uri () with
          | None -> None
          | Some uri ->
            (match get_analysis uri with
             | None -> None
             | Some a -> Analysis.query_type_definition_at a ~line ~utf16_char)
        in
        (match loc with
         | None -> Lwt.return `Null
         | Some l ->
           Lwt.return
             (`Assoc [
                ("uri",   `String (Lsp.Types.DocumentUri.to_string l.uri));
                ("range", json_range l.range)
              ]))

      end else if meth = "textDocument/documentHighlight" then begin
        let (line, utf16_char) = get_position () in
        let hls =
          match get_td_uri () with
          | None -> []
          | Some uri ->
            (match get_analysis uri with
             | None -> []
             | Some a -> Analysis.query_document_highlights_at a ~line ~utf16_char)
        in
        Lwt.return
          (`List (List.map (fun (h : Lsp.Types.DocumentHighlight.t) ->
               let k = Option.value h.kind
                         ~default:Lsp.Types.DocumentHighlightKind.Text in
               `Assoc [ ("range", json_range h.range);
                        ("kind", Lsp.Types.DocumentHighlightKind.yojson_of_t k) ]) hls))

      end else if meth = "textDocument/selectionRange" then begin
        (* Params carry a list of positions; return one nested SelectionRange
           per position (innermost range first, each with its parent). *)
        let positions =
          match params with
          | Some (`Assoc fields) ->
            (match List.assoc_opt "positions" fields with
             | Some (`List ps) ->
               List.map (fun p -> match p with
                   | `Assoc pos ->
                     let g k = match List.assoc_opt k pos with
                       | Some (`Int n) -> n | _ -> 0 in
                     (g "line", g "character")
                   | _ -> (0, 0)) ps
             | _ -> [])
          | _ -> []
        in
        let nest ranges =
          (* ranges innermost→outermost → a parent-linked SelectionRange JSON *)
          List.fold_right (fun r child ->
              `Assoc (("range", json_range r)
                      :: (match child with `Null -> [] | c -> [("parent", c)])))
            ranges `Null
        in
        let result =
          match get_td_uri () with
          | None -> List.map (fun _ -> `Null) positions
          | Some uri ->
            (match get_analysis uri with
             | None -> List.map (fun _ -> `Null) positions
             | Some a ->
               List.map (fun (line, utf16_char) ->
                   nest (Analysis.query_selection_range_at a ~line ~utf16_char))
                 positions)
        in
        Lwt.return (`List result)

      end else if meth = "textDocument/prepareCallHierarchy" then begin
        let (line, utf16_char) = get_position () in
        match get_td_uri () with
        | None -> Lwt.return `Null
        | Some uri ->
          (match get_analysis uri with
           | None -> Lwt.return `Null
           | Some a ->
             (match Analysis.query_prepare_call_hierarchy_at a ~line ~utf16_char with
              | None -> Lwt.return `Null
              | Some (name, range, sel) ->
                let item = Lsp.Types.CallHierarchyItem.create
                    ~kind:Lsp.Types.SymbolKind.Function ~name
                    ~range ~selectionRange:sel ~uri () in
                Lwt.return (`List [Lsp.Types.CallHierarchyItem.yojson_of_t item])))

      end else if meth = "callHierarchy/incomingCalls"
               || meth = "callHierarchy/outgoingCalls" then begin
        (* The client echoes back the item from prepareCallHierarchy. *)
        let item_name, item_uri =
          match params with
          | Some (`Assoc fields) ->
            (match List.assoc_opt "item" fields with
             | Some (`Assoc it) ->
               let name = match List.assoc_opt "name" it with
                 | Some (`String s) -> s | _ -> "" in
               let uri = match List.assoc_opt "uri" it with
                 | Some (`String u) ->
                   let path =
                     if String.length u >= 7 && String.sub u 0 7 = "file://"
                     then String.sub u 7 (String.length u - 7) else u in
                   Some (Lsp.Types.DocumentUri.of_path path)
                 | _ -> None in
               (name, uri)
             | _ -> ("", None))
          | _ -> ("", None)
        in
        let incoming = meth = "callHierarchy/incomingCalls" in
        let calls =
          match item_uri with
          | None -> []
          | Some uri ->
            (match get_analysis uri with
             | None -> []
             | Some a ->
               let mk_item (name, range, sel) =
                 Lsp.Types.CallHierarchyItem.create
                   ~kind:Lsp.Types.SymbolKind.Function ~name
                   ~range ~selectionRange:sel ~uri ()
               in
               if incoming then
                 Analysis.query_incoming_calls a item_name
                 |> List.map (fun (it, ranges) ->
                        Lsp.Types.CallHierarchyIncomingCall.yojson_of_t
                          (Lsp.Types.CallHierarchyIncomingCall.create
                             ~from:(mk_item it) ~fromRanges:ranges))
               else
                 Analysis.query_outgoing_calls a item_name
                 |> List.map (fun (it, ranges) ->
                        Lsp.Types.CallHierarchyOutgoingCall.yojson_of_t
                          (Lsp.Types.CallHierarchyOutgoingCall.create
                             ~to_:(mk_item it) ~fromRanges:ranges)))
        in
        Lwt.return (`List calls)

      end else if meth = "textDocument/linkedEditingRange" then begin
        let (line, utf16_char) = get_position () in
        let ranges =
          match get_td_uri () with
          | None -> []
          | Some uri ->
            (match get_analysis uri with
             | None -> []
             | Some a -> Analysis.query_linked_editing_ranges_at a ~line ~utf16_char)
        in
        if ranges = [] then Lwt.return `Null
        else Lwt.return (`Assoc [("ranges", `List (List.map json_range ranges))])

      end else if meth = "textDocument/inlineValue" then begin
        (* DAP inline values: while stopped at a breakpoint, the editor asks for
           the in-scope variables in the visible [range]; we return one
           InlineValueVariableLookup per visible local at/above the stopped line
           and let the debugger resolve live values. Robust on error buffers:
           missing/garbled params degrade to an empty list, never an exception. *)
        let line_of obj key =
          match obj with
          | `Assoc o ->
            (match List.assoc_opt key o with
             | Some (`Assoc p) ->
               (match List.assoc_opt "line" p with Some (`Int n) -> n | _ -> 0)
             | _ -> 0)
          | _ -> 0
        in
        let range_obj, ctx_obj =
          match params with
          | Some (`Assoc fields) ->
            (Option.value ~default:`Null (List.assoc_opt "range" fields),
             Option.value ~default:`Null (List.assoc_opt "context" fields))
          | _ -> (`Null, `Null)
        in
        let range_start_line = line_of range_obj "start" in
        let range_end_line   = line_of range_obj "end" in
        (* Stopped line comes from context.stoppedLocation; if absent, allow the
           whole requested range (no cutoff) by using its end line. *)
        let stopped_loc =
          match ctx_obj with
          | `Assoc o -> Option.value ~default:`Null (List.assoc_opt "stoppedLocation" o)
          | _ -> `Null
        in
        let stopped_line =
          match stopped_loc with
          | `Null -> range_end_line
          | _ -> line_of stopped_loc "start"
        in
        let values =
          match get_td_uri () with
          | None -> []
          | Some uri ->
            (match get_analysis uri with
             | None -> []
             | Some a ->
               (try
                  Analysis.query_inline_values a
                    ~range_start_line ~range_end_line ~stopped_line
                with _ -> []))
        in
        Lwt.return (`List (List.map Lsp.Types.InlineValue.yojson_of_t values))

      end else if meth = "workspace/diagnostic" then begin
        (* Whole-project diagnostics: analyse every .march file under the project
           root and return a full report per file (capped to bound the work). *)
        let items =
          match project_root () with
          | None -> []
          | Some root ->
            let sources = Workspace.discover_sources ~root in
            let sources = List.filteri (fun i _ -> i < 200) sources in
            Analysis.project_diagnostics sources
            |> List.map (fun (path, diags) ->
                   let uri = Lsp.Types.DocumentUri.of_path path in
                   `Assoc [
                     ("kind", `String "full");
                     ("uri", `String (Lsp.Types.DocumentUri.to_string uri));
                     ("items", `List (List.map Lsp.Types.Diagnostic.yojson_of_t diags))
                   ])
        in
        Lwt.return (`Assoc [("items", `List items)])

      end else if meth = "completionItem/resolve" then begin
        (* Lazily compute the auto-import additionalTextEdit for the accepted
           item, using the (module, name, uri, version) stashed in its
           `data`. The import-insertion edit targets the file's first
           declaration line, not the cursor (see [Analysis.import_text_edit]),
           so if the document has changed since the completion list was
           computed, re-fetching `get_analysis` here would compute that edit
           against a DIFFERENT buffer than the one currently open, landing it
           on whatever now occupies that unrelated line. Refuse to answer
           once the document has moved on, rather than risk that. *)
        match params with
        | Some (`Assoc fields) ->
          let edit =
            match List.assoc_opt "data" fields with
            | Some (`Assoc data) ->
              (match List.assoc_opt "autoImport" data, List.assoc_opt "uri" data,
                     List.assoc_opt "version" data with
               | Some (`Assoc ai), Some (`String u), Some (`Int v) ->
                 let g k = match List.assoc_opt k ai with
                   | Some (`String s) -> s | _ -> "" in
                 let m = g "module" and n = g "name" in
                 let path =
                   if String.length u >= 7 && String.sub u 0 7 = "file://"
                   then String.sub u 7 (String.length u - 7) else u in
                 let uri = Lsp.Types.DocumentUri.of_path path in
                 let uri_str = Lsp.Types.DocumentUri.to_string uri in
                 if not (is_current versions uri_str v) then None
                 else
                   (match get_analysis uri with
                    | Some a -> Analysis.query_import_text_edit a ~module_:m ~name:n
                    | None -> None)
               | _ -> None)
            | _ -> None
          in
          (match edit with
           | None -> Lwt.return (`Assoc fields)
           | Some (e : Lsp.Types.TextEdit.t) ->
             let fields =
               List.filter (fun (k, _) -> k <> "additionalTextEdits") fields in
             Lwt.return (`Assoc (("additionalTextEdits",
                                  `List [ `Assoc [ ("range", json_range e.range);
                                                   ("newText", `String e.newText) ]])
                                 :: fields)))
        | _ -> Lwt.return `Null

      end else if meth = "textDocument/onTypeFormatting" then begin
        (* Auto-close HTML tags in ~H sigils when the user types '>'.
           Params: { textDocument: {uri}, position: {line, character}, ch: string }
           Returns: TextEdit list (one edit) or empty list. *)
        let (line, utf16_char) = get_position () in
        let edit =
          match get_td_uri () with
          | None -> None
          | Some uri ->
            (match get_analysis uri with
             | None -> None
             | Some a ->
               let byte_col =
                 Utf16.lsp_char_to_byte_col a.Analysis.doc ~line ~utf16_char
               in
               (match Analysis.autoclose_tag_at a ~line ~character:byte_col with
                | None -> None
                | Some e -> Some (Pos.remap_text_edit a.Analysis.doc e)))
        in
        (match edit with
         | None -> Lwt.return (`List [])
         | Some (e : Lsp.Types.TextEdit.t) ->
           Lwt.return (`List [
             `Assoc [
               ("range",   json_range e.range);
               ("newText", `String e.newText)
             ]
           ]))

      end else
        Lwt.fail_with (Printf.sprintf "unhandled request: %s" meth)
