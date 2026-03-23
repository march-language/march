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
  let analysis = Analysis.analyse ~filename ~src in
  Hashtbl.replace doc_cache (Lsp.Types.DocumentUri.to_string uri) analysis;
  analysis

let get_analysis uri =
  Hashtbl.find_opt doc_cache (Lsp.Types.DocumentUri.to_string uri)

(* ------------------------------------------------------------------ *)
(* Code actions (helper, defined before the class)                    *)
(* ------------------------------------------------------------------ *)

let code_actions_for (_a : Analysis.t) _uri _range :
    Lsp.Types.CodeAction.t list =
  (* Stub: future home of "make linear", "suggest sort algorithm", etc. *)
  []

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
      if sp.March_ast.Ast.start_line = sp.March_ast.Ast.end_line && len > 0 then
        tokens :=
          (sp.March_ast.Ast.start_line - 1,
           sp.March_ast.Ast.start_col,
           len, tok_type_idx, mods) :: !tokens
    ) a.Analysis.def_map;

  Hashtbl.iter (fun sp _name ->
      let len = sp.March_ast.Ast.end_col - sp.March_ast.Ast.start_col in
      if sp.March_ast.Ast.start_line = sp.March_ast.Ast.end_line && len > 0 then
        tokens :=
          (sp.March_ast.Ast.start_line - 1,
           sp.March_ast.Ast.start_col,
           len, tok_variable, 0) :: !tokens
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
              ~triggerCharacters:["." ; "|" ; " "]
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
      { caps with
        ServerCapabilities.semanticTokensProvider =
          Some (`SemanticTokensOptions sem_tokens) }

    (* -------------------------------------------------------------- *)
    (* Document synchronisation                                        *)
    (* -------------------------------------------------------------- *)

    method on_notif_doc_did_open ~notify_back doc ~content =
      let uri = doc.Lsp.Types.TextDocumentItem.uri in
      let a = analyse_and_cache uri content in
      notify_back#send_diagnostic a.Analysis.diagnostics

    method on_notif_doc_did_close ~notify_back:_ doc =
      Hashtbl.remove doc_cache
        (Lsp.Types.DocumentUri.to_string
           doc.Lsp.Types.TextDocumentIdentifier.uri);
      Lwt.return_unit

    method on_notif_doc_did_change ~notify_back vdoc _changes
        ~old_content:_ ~new_content =
      let uri = vdoc.Lsp.Types.VersionedTextDocumentIdentifier.uri in
      let a = analyse_and_cache uri new_content in
      notify_back#send_diagnostic a.Analysis.diagnostics

    (* -------------------------------------------------------------- *)
    (* Hover                                                           *)
    (* -------------------------------------------------------------- *)

    method on_req_hover ~notify_back:_ ~id:_ ~uri ~pos ~workDoneToken:_ _doc =
      let open Lsp.Types in
      let (line, character) = Pos.lsp_pos_to_pair pos in
      let result =
        match get_analysis uri with
        | None -> None
        | Some a ->
          let ty_hover =
            Analysis.type_at a ~line ~character
            |> Option.map (fun ty_str ->
                let md = MarkupContent.create
                  ~kind:MarkupKind.Markdown
                  ~value:(Printf.sprintf "```march\n%s\n```" ty_str) in
                Hover.create ~contents:(`MarkupContent md) ())
          in
          (match ty_hover with
           | Some _ -> ty_hover
           | None ->
             Analysis.actor_info_at a ~line ~character
             |> Option.map (fun info ->
                 let md = MarkupContent.create
                   ~kind:MarkupKind.Markdown ~value:info in
                 Hover.create ~contents:(`MarkupContent md) ()))
      in
      Lwt.return result

    (* -------------------------------------------------------------- *)
    (* Go-to-definition                                                *)
    (* -------------------------------------------------------------- *)

    method on_req_definition ~notify_back:_ ~id:_ ~uri ~pos
        ~workDoneToken:_ ~partialResultToken:_ _doc =
      let (line, character) = Pos.lsp_pos_to_pair pos in
      let loc =
        match get_analysis uri with
        | None -> None
        | Some a -> Analysis.definition_at a ~line ~character
      in
      Lwt.return (Option.map (fun l -> `Location [l]) loc)

    (* -------------------------------------------------------------- *)
    (* Completion                                                      *)
    (* -------------------------------------------------------------- *)

    method on_req_completion ~notify_back:_ ~id:_ ~uri ~pos ~ctx:_
        ~workDoneToken:_ ~partialResultToken:_ _doc =
      let (line, character) = Pos.lsp_pos_to_pair pos in
      let items =
        match get_analysis uri with
        | None -> []
        | Some a -> Analysis.completions_at a ~line ~character
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
          let hs = Analysis.inlay_hints_for a range in
          if hs = [] then None else Some hs
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
        | Some a -> Some (Analysis.document_symbols a)
      in
      Lwt.return syms

    (* -------------------------------------------------------------- *)
    (* Code actions                                                    *)
    (* -------------------------------------------------------------- *)

    method on_req_code_action ~notify_back:_ ~id:_
        (params : Lsp.Types.CodeActionParams.t) =
      let uri   = params.textDocument.uri in
      let range = params.range in
      let acts =
        match get_analysis uri with
        | None -> []
        | Some a -> code_actions_for a uri range
      in
      Lwt.return
        (if acts = [] then None
         else Some (List.map (fun a -> `CodeAction a) acts))

    (* -------------------------------------------------------------- *)
    (* Semantic tokens (full) — dispatched via on_unknown_request     *)
    (* -------------------------------------------------------------- *)

    method on_unknown_request ~notify_back:_ ~server_request:_ ~id:_ meth params =
      if meth = "textDocument/semanticTokens/full" then begin
        let uri_opt =
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
        let data =
          match uri_opt with
          | None -> [||]
          | Some uri ->
            (match get_analysis uri with
             | None -> [||]
             | Some a -> semantic_tokens_data a)
        in
        Lwt.return
          (`Assoc [("data",
                    `List (Array.to_list (Array.map (fun n -> `Int n) data)))])
      end else
        Lwt.fail_with (Printf.sprintf "unhandled request: %s" meth)
  end
