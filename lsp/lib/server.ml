(** march-lsp server — LSP server class for the March language. *)

module Lsp = Linol_lsp.Lsp
module S   = Linol_lwt.Jsonrpc2
module Pos = Position  (* our position utilities *)

(* ------------------------------------------------------------------ *)
(* Document cache                                                      *)
(* ------------------------------------------------------------------ *)

let doc_cache : (string, Analysis.t) Hashtbl.t = Hashtbl.create 16

let analyse_and_cache uri src =
  let filename =
    try  Lsp.Types.DocumentUri.to_path uri
    with _ -> Lsp.Types.DocumentUri.to_string uri
  in
  let key = Lsp.Types.DocumentUri.to_string uri in
  (* Fall back to the last good analysis when an edit doesn't parse, so IDE
     features keep working on a transiently-broken buffer. *)
  let prev = Hashtbl.find_opt doc_cache key in
  let analysis = Analysis.analyse_resilient ~prev ~filename ~src in
  Hashtbl.replace doc_cache key analysis;
  analysis

let get_analysis uri =
  Hashtbl.find_opt doc_cache (Lsp.Types.DocumentUri.to_string uri)

(* ------------------------------------------------------------------ *)
(* Code actions (helper, defined before the class)                    *)
(* ------------------------------------------------------------------ *)

let code_actions_for (a : Analysis.t) _uri (range : Lsp.Types.Range.t)
    (diagnostics : Lsp.Types.Diagnostic.t list) :
    Lsp.Types.CodeAction.t list =
  let line = range.Lsp.Types.Range.start.Lsp.Types.Position.line in
  (* Inbound: the client's cursor column is UTF-16; analysis works in bytes. *)
  let character =
    Utf16.lsp_char_to_byte_col a.Analysis.doc ~line
      ~utf16_char:range.Lsp.Types.Range.start.Lsp.Types.Position.character
  in
  (* Outbound: remap edit ranges back to UTF-16 for the client. *)
  Analysis.code_actions_at a ~line ~character ~diagnostics ()
  |> List.map (Pos.remap_code_action a.Analysis.doc)

(* ------------------------------------------------------------------ *)
(* Semantic tokens encoding                                            *)
(* ------------------------------------------------------------------ *)

let semantic_tokens_data (a : Analysis.t) : int array =
  let tok_type        = 1 in
  let tok_enum_member = 3 in
  let tok_function    = 4 in
  let tok_variable    = 5 in
  let mod_declaration = 1 in
  let mod_readonly    = 4 in

  let tokens = ref [] in
  (* LSP semantic-token start columns and lengths are in UTF-16 code units. *)
  let to_u line0 byte_col =
    Utf16.byte_col_to_lsp_char a.Analysis.doc ~line:line0 ~byte_col
  in

  Hashtbl.iter (fun name sp ->
      let tok_type_idx, mods =
        if List.mem_assoc name a.Analysis.types then
          tok_type, mod_declaration lor mod_readonly
        else if List.mem_assoc name a.Analysis.ctors then
          tok_enum_member, mod_declaration lor mod_readonly
        else
          tok_function, mod_declaration
      in
      let len = sp.March_ast.Ast.end_col - sp.March_ast.Ast.start_col in
      if sp.March_ast.Ast.start_line = sp.March_ast.Ast.end_line && len > 0 then begin
        let line0 = sp.March_ast.Ast.start_line - 1 in
        let u_start = to_u line0 sp.March_ast.Ast.start_col in
        let u_len   = to_u line0 sp.March_ast.Ast.end_col - u_start in
        tokens := (line0, u_start, u_len, tok_type_idx, mods) :: !tokens
      end
    ) a.Analysis.def_map;

  Hashtbl.iter (fun sp _name ->
      let len = sp.March_ast.Ast.end_col - sp.March_ast.Ast.start_col in
      if sp.March_ast.Ast.start_line = sp.March_ast.Ast.end_line && len > 0 then begin
        let line0 = sp.March_ast.Ast.start_line - 1 in
        let u_start = to_u line0 sp.March_ast.Ast.start_col in
        let u_len   = to_u line0 sp.March_ast.Ast.end_col - u_start in
        tokens := (line0, u_start, u_len, tok_variable, 0) :: !tokens
      end
    ) a.Analysis.use_map;

  let sorted = List.sort
    (fun (l1, c1, _, _, _) (l2, c2, _, _, _) ->
        let c = compare l1 l2 in
        if c <> 0 then c else compare c1 c2)
    !tokens
  in

  (* Encode as the LSP delta-encoded flat integer array *)
  let buf   = ref [] in
  let prev_line = ref 0 in
  let prev_char = ref 0 in
  List.iter (fun (line, startChar, length, tokenType, tokenModifiers) ->
      let delta_line = line - !prev_line in
      let delta_char =
        if delta_line = 0 then startChar - !prev_char else startChar
      in
      buf := tokenModifiers :: tokenType :: length :: delta_char
             :: delta_line :: !buf;
      prev_line := line;
      prev_char := startChar
    ) sorted;
  Array.of_list (List.rev !buf)

(* ------------------------------------------------------------------ *)
(* Server class                                                        *)
(* ------------------------------------------------------------------ *)

class march_server =
  object (_self)
    inherit S.server

    (* Spawn using Lwt.async *)
    method spawn_query_handler f = Linol_lwt.spawn f

    (* -------------------------------------------------------------- *)
    (* Capabilities                                                    *)
    (* -------------------------------------------------------------- *)

    method config_hover =
      Some (`HoverOptions (Lsp.Types.HoverOptions.create ()))

    method config_definition =
      Some (`Bool true)

    method config_completion =
      Some (Lsp.Types.CompletionOptions.create
              ~triggerCharacters:["." ; "|" ; " " ; "~"]
              ())

    method config_inlay_hints =
      Some (`Bool true)

    method config_symbol =
      Some (`Bool true)

    method config_code_action_provider =
      `CodeActionOptions (Lsp.Types.CodeActionOptions.create
        ~codeActionKinds:[Lsp.Types.CodeActionKind.QuickFix;
                          Lsp.Types.CodeActionKind.RefactorRewrite]
        ())

    method config_modify_capabilities caps =
      let open Lsp.Types in
      let legend = SemanticTokensLegend.create
        ~tokenTypes:[
          "namespace"; "type"; "class"; "enumMember"; "function";
          "variable"; "parameter"; "keyword"; "property";
        ]
        ~tokenModifiers:[
          "declaration"; "definition"; "readonly"; "linear"; "affine";
        ]
      in
      let sem_tokens =
        SemanticTokensOptions.create
          ~legend
          ~full:(`Full (SemanticTokensOptions.create_full ~delta:false ()))
          ()
      in
      let sig_help =
        SignatureHelpOptions.create
          ~triggerCharacters:["("; ","]
          ()
      in
      { caps with
        (* All ranges we emit are converted to UTF-16 (the LSP default) against
           the document text, so advertise UTF-16 explicitly. *)
        ServerCapabilities.positionEncoding =
          Some Lsp.Types.PositionEncodingKind.UTF16;
        ServerCapabilities.semanticTokensProvider =
          Some (`SemanticTokensOptions sem_tokens);
        ServerCapabilities.referencesProvider =
          Some (`Bool true);
        ServerCapabilities.renameProvider =
          Some (`Bool true);
        ServerCapabilities.signatureHelpProvider =
          Some sig_help;
        ServerCapabilities.foldingRangeProvider =
          Some (`Bool true);
        ServerCapabilities.codeLensProvider =
          Some (Lsp.Types.CodeLensOptions.create ~resolveProvider:false ()) }

    (* -------------------------------------------------------------- *)
    (* Document synchronisation                                        *)
    (* -------------------------------------------------------------- *)

    method on_notif_doc_did_open ~notify_back doc ~content =
      let uri = doc.Lsp.Types.TextDocumentItem.uri in
      let a = analyse_and_cache uri content in
      (* Push AST-level diagnostics immediately so the editor is responsive.
         Diagnostic ranges are produced in byte columns; remap to UTF-16. *)
      Lwt.async (fun () ->
        (* Run TIR pipeline in a background fiber.  On completion, update the
           cached analysis and push an incremental publishDiagnostics with the
           TIR-level hints merged in. *)
        let a2 = Analysis.run_tir_pass a in
        let uri_str = Lsp.Types.DocumentUri.to_string uri in
        Hashtbl.replace doc_cache uri_str a2;
        notify_back#send_diagnostic
          (List.map (Pos.remap_diagnostic a2.Analysis.doc) a2.Analysis.diagnostics));
      notify_back#send_diagnostic
        (List.map (Pos.remap_diagnostic a.Analysis.doc) a.Analysis.diagnostics)

    method on_notif_doc_did_close ~notify_back:_ doc =
      Hashtbl.remove doc_cache
        (Lsp.Types.DocumentUri.to_string
           doc.Lsp.Types.TextDocumentIdentifier.uri);
      Lwt.return_unit

    method on_notif_doc_did_change ~notify_back vdoc _changes
        ~old_content:_ ~new_content =
      let uri = vdoc.Lsp.Types.VersionedTextDocumentIdentifier.uri in
      let a = analyse_and_cache uri new_content in
      (* Same two-phase publish: AST diagnostics first, TIR insights async.
         Diagnostic ranges are byte columns; remap to UTF-16 for the client. *)
      Lwt.async (fun () ->
        let a2 = Analysis.run_tir_pass a in
        let uri_str = Lsp.Types.DocumentUri.to_string uri in
        Hashtbl.replace doc_cache uri_str a2;
        notify_back#send_diagnostic
          (List.map (Pos.remap_diagnostic a2.Analysis.doc) a2.Analysis.diagnostics));
      notify_back#send_diagnostic
        (List.map (Pos.remap_diagnostic a.Analysis.doc) a.Analysis.diagnostics)

    (* -------------------------------------------------------------- *)
    (* Hover                                                           *)
    (* -------------------------------------------------------------- *)

    method on_req_hover ~notify_back:_ ~id:_ ~uri ~pos ~workDoneToken:_ _doc =
      let open Lsp.Types in
      let (line, utf16_char) = Pos.lsp_pos_to_pair pos in
      let result =
        match get_analysis uri with
        | None -> None
        | Some a ->
          let ty_str   = Analysis.query_type_at a ~line ~utf16_char in
          let doc_str  = Analysis.query_doc_name_at a ~line ~utf16_char in
          let perf_str = Analysis.query_perf_insight_at a ~line ~utf16_char in
          let parts   = List.filter_map Fun.id [
            Option.map (fun ty -> Printf.sprintf "```march\n%s\n```" ty) ty_str;
            Option.map (fun d  -> "---\n" ^ d) doc_str;
            Option.map (fun p  -> "---\n" ^ p) perf_str;
          ] in
          if parts <> [] then
            let md = MarkupContent.create
              ~kind:MarkupKind.Markdown
              ~value:(String.concat "\n" parts) in
            Some (Hover.create ~contents:(`MarkupContent md) ())
          else
            Analysis.query_actor_info_at a ~line ~utf16_char
            |> Option.map (fun info ->
                let md = MarkupContent.create
                  ~kind:MarkupKind.Markdown ~value:info in
                Hover.create ~contents:(`MarkupContent md) ())
      in
      Lwt.return result

    (* -------------------------------------------------------------- *)
    (* Go-to-definition                                                *)
    (* -------------------------------------------------------------- *)

    method on_req_definition ~notify_back:_ ~id:_ ~uri ~pos
        ~workDoneToken:_ ~partialResultToken:_ _doc =
      let (line, utf16_char) = Pos.lsp_pos_to_pair pos in
      let loc =
        match get_analysis uri with
        | None -> None
        | Some a -> Analysis.query_definition_at a ~line ~utf16_char
      in
      Lwt.return (Option.map (fun l -> `Location [l]) loc)

    (* -------------------------------------------------------------- *)
    (* Completion                                                      *)
    (* -------------------------------------------------------------- *)

    method on_req_completion ~notify_back:_ ~id:_ ~uri ~pos ~ctx:_
        ~workDoneToken:_ ~partialResultToken:_ _doc =
      let (line, utf16_char) = Pos.lsp_pos_to_pair pos in
      let items =
        match get_analysis uri with
        | None -> []
        | Some a -> Analysis.query_completions_at a ~line ~utf16_char
      in
      Lwt.return (Some (`List items))

    (* -------------------------------------------------------------- *)
    (* Inlay hints                                                     *)
    (* -------------------------------------------------------------- *)

    method on_req_inlay_hint ~notify_back:_ ~id:_ ~uri ~range () =
      let hints =
        match get_analysis uri with
        | None -> None
        | Some a ->
          (* inlay_hints_for filters by line only, so the inbound range needs
             no column conversion; remap the outbound hint positions to UTF-16. *)
          let hs = Analysis.inlay_hints_for a range in
          if hs = [] then None
          else Some (List.map (Pos.remap_inlay_hint a.Analysis.doc) hs)
      in
      Lwt.return hints

    (* -------------------------------------------------------------- *)
    (* Document symbols                                                *)
    (* -------------------------------------------------------------- *)

    method on_req_symbol ~notify_back:_ ~id:_ ~uri
        ~workDoneToken:_ ~partialResultToken:_ () =
      let syms =
        match get_analysis uri with
        | None -> None
        | Some a ->
          (match Analysis.document_symbols a with
           | `DocumentSymbol ss ->
             Some (`DocumentSymbol
                     (List.map (Pos.remap_document_symbol a.Analysis.doc) ss))
           | other -> Some other)
      in
      Lwt.return syms

    (* -------------------------------------------------------------- *)
    (* Code actions                                                    *)
    (* -------------------------------------------------------------- *)

    method on_req_code_action ~notify_back:_ ~id:_
        (params : Lsp.Types.CodeActionParams.t) =
      let uri   = params.textDocument.uri in
      let range = params.range in
      let ctx_diags = params.context.diagnostics in
      let acts =
        match get_analysis uri with
        | None -> []
        | Some a -> code_actions_for a uri range ctx_diags
      in
      Lwt.return
        (if acts = [] then None
         else Some (List.map (fun a -> `CodeAction a) acts))

    (* -------------------------------------------------------------- *)
    (* Semantic tokens (full) — dispatched via on_unknown_request     *)
    (* -------------------------------------------------------------- *)

    method on_unknown_request ~notify_back:_ ~server_request:_ ~id:_ meth params =
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
      if meth = "textDocument/semanticTokens/full" then begin
        let data =
          match get_td_uri () with
          | None -> [||]
          | Some uri ->
            (match get_analysis uri with
             | None -> [||]
             | Some a -> semantic_tokens_data a)
        in
        Lwt.return
          (`Assoc [("data",
                    `List (Array.to_list (Array.map (fun n -> `Int n) data)))])

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
               Analysis.query_references_at a ~include_declaration ~line ~utf16_char)
        in
        Lwt.return
          (`List (List.map (fun (loc : Lsp.Types.Location.t) ->
               `Assoc [
                 ("uri",   `String (Lsp.Types.DocumentUri.to_string loc.uri));
                 ("range", json_range loc.range)
               ]) locs))

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
            `Assoc [
              ("range", json_range cl.cl_range);
              ("command", `Assoc [
                ("title",   `String cl.cl_title);
                ("command", `String "march.perf.noop");
                ("arguments", `List [])
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
            let fr = FoldingRange.create
              ~startLine:sl
              ~endLine:el
              ~kind:(FoldingRangeKind.Other kind)
              ()
            in
            FoldingRange.yojson_of_t fr
          ) ranges
        in
        Lwt.return (`List json_ranges)

      end else
        Lwt.fail_with (Printf.sprintf "unhandled request: %s" meth)
  end
