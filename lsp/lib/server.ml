(** march-lsp server — LSP server class for the March language. *)

(* The module aliases, caches, settings, workspace index and semantic-token
   encoding this file used to open with, now in server_state.ml.

   [include] rather than [open] because these are part of [Server]'s public
   surface: lsp/test/test_lsp.ml reads semantic_tokens_data, token_delta,
   param_name_hints_from_settings and perf_annotations_from_settings through
   [Server.], and lsp/bin/main.ml instantiates the class below. The four
   module aliases come through the same include rather than being repeated
   here — repeating them is what "Multiple definition of the module name"
   rejects. *)
include Server_state

(* ------------------------------------------------------------------ *)
(* Server class                                                        *)
(* ------------------------------------------------------------------ *)

class march_server =
  object (self)
    inherit S.server as super

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
              ~resolveProvider:true   (* auto-import edits computed lazily *)
              ())

    method config_inlay_hints =
      Some (`Bool true)

    method config_symbol =
      Some (`Bool true)


    (* ── workspace/executeCommand ────────────────────────────────────────────
       This MUST be [on_req_execute_command]. linol dispatches
       `workspace/executeCommand` as a KNOWN client request, so it never reaches
       [on_unknown_request] — where this logic previously lived, which made the
       whole feature dead code returning linol's default `null`. Nothing caught
       it because a command is only observable through a live editor session:
       the runnable "Run test" / "Debug" code lenses had therefore never worked
       either, and neither had `march.suggestRefinement`. Found by driving the
       protocol over stdio; see specs/progress/2026-08-03-lsp-execute-command.md.

       RUN commands shell out to forge and return a summary. DEBUG commands do
       NOT block on an interactive debugger — launching a DAP session is the
       editor's job — so they return a structured echo the client uses to start
       its own session. `march.suggestRefinement` runs the refinement inference
       and pushes the result back as a workspace/applyEdit, so the edit lands in
       the user's BUFFER; writing the file underneath an editor with unsaved
       changes would lose their work. *)
    method! on_req_execute_command ~notify_back ~id:_ ~workDoneToken:_
        (command : string) (args : Yojson.Safe.t list option) =
      let args = Option.value args ~default:[] in

        (* Runnable code lenses dispatch here. RUN commands (march.runTest /
           march.run) shell out to forge and return a short summary. DEBUG
           commands (march.debugTest / march.debug) do NOT block on an
           interactive debugger — launching a DAP session is the editor's job —
           so we return a structured echo (command id + args + the `march dap`
           invocation) that the client uses to start its own debug session. *)
        (* Refinement inference is far too expensive to run while building the
           code-action list, so that action carries a COMMAND and the work
           happens here, once, after the user picks it.  The inference itself
           lives in the compiler (`march --refine-suggest`) because it needs a
           fully resolved, typechecked module — the same reason `forge refine`
           shells out.  The edit goes back through workspace/applyEdit so it
           lands in the user's BUFFER; writing the file underneath an editor
           with unsaved changes would lose their work. *)
        if command = "march.suggestRefinement"
           || command = "march.suggestPostcondition" then
          match args with
          | [ `String file; `String fn ] ->
            let (payload, edit) =
              if command = "march.suggestPostcondition" then
                Refine_command.run_post ~file ~fn
              else Refine_command.run ~file ~fn
            in
            (match edit with
             | None -> Lwt.return payload
             | Some we ->
               Lwt.bind
                 (notify_back#send_request
                    (Lsp.Server_request.WorkspaceApplyEdit
                       (Lsp.Types.ApplyWorkspaceEditParams.create ~edit:we
                          ~label:
                            (if command = "march.suggestPostcondition" then
                               "Suggest a postcondition"
                             else "Suggest a refinement type")
                          ()))
                    (fun _ -> Lwt.return ()))
                 (fun _ -> Lwt.return payload))
          | _ ->
            Lwt.return
              (`Assoc
                [ ("status", `String "error");
                  ("kind", `String "suggestRefinement");
                  ("message",
                   `String (command ^ " expects [file, function]")) ])
        else
        let result =
          match Analysis.resolve_lens_command ~command ~args with
          | Analysis.RunShell { description; shell } ->
            let rc = Sys.command shell in
            `Assoc [
              ("status",   `String (if rc = 0 then "ok" else "error"));
              ("kind",     `String "run");
              ("command",  `String command);
              ("shell",    `String shell);
              ("exitCode", `Int rc);
              ("message",  `String
                 (Printf.sprintf "%s — %s (exit %d)" description
                    (if rc = 0 then "passed" else "failed") rc))
            ]
          | Analysis.DebugEcho { description; debug_command; dap; args } ->
            `Assoc [
              ("status",  `String "debug");
              ("kind",    `String "debug");
              ("command", `String debug_command);
              ("dap",     `String dap);
              ("arguments", `List args);
              ("message", `String description)
            ]
          | Analysis.Unknown c ->
            `Assoc [
              ("status",  `String "error");
              ("kind",    `String "unknown");
              ("command", `String c);
              ("message", `String (Printf.sprintf "Unknown command: %s" c))
            ]
        in
        Lwt.return result

    (* ── textDocument/diagnostic (pull diagnostics) ──────────────────────────
       `TextDocumentDiagnostic` is a KNOWN client request that linol has no
       dedicated method for, so it arrives here — NOT at [on_unknown_request],
       which only ever sees requests linol could not decode. Putting a known
       request there is exactly what made every `workspace/executeCommand` dead
       code (see specs/progress/2026-08-03-lsp-execute-command-was-never-dispatched.md).

       The server advertises `diagnosticProvider`, so until this existed every
       pull fell through to linol's default and failed with "TODO: handle this
       request" — an advertised capability nothing answered, while the PUSH path
       quietly carried the feature and hid it.

       [Analysis.t] already stores `Lsp.Types.Diagnostic.t list`, so pull and
       push serve the identical values by construction; there is no second
       conversion that could drift. A cache miss analyses on the spot rather
       than answering empty: a client may pull before it opens a document, and
       an empty report is indistinguishable from a clean file. *)
    method! on_request_unhandled : type r.
        notify_back:_ -> id:_ -> r Lsp.Client_request.t -> r Linol_lwt.t =
      fun ~notify_back ~id req ->
        match req with
        | Lsp.Client_request.TextDocumentDiagnostic params ->
          let uri = params.Lsp.Types.DocumentDiagnosticParams.textDocument.uri in
          let items =
            match get_analysis uri with
            | Some a -> a.Analysis.diagnostics
            | None ->
              (match Hashtbl.find_opt doc_cache (Lsp.Types.DocumentUri.to_string uri) with
               | Some a -> a.Analysis.diagnostics
               | None -> [])
          in
          Linol_lwt.return
            (`RelatedFullDocumentDiagnosticReport
               (Lsp.Types.RelatedFullDocumentDiagnosticReport.create ~items ()))
        | _ ->
          (* ── The bridge that makes ~20 features reachable ─────────────────
             linol routes a request here when it DECODED it but has no
             dedicated `on_req_*` method for it — which is true of references,
             rename, formatting, semantic tokens, folding, signature help, call
             hierarchy, type definition, workspace symbol and a dozen more.
             Every one of those had a handler written as a method-string branch
             in [on_unknown_request], where a decoded request never arrives, so
             every one of them answered `TODO: handle this request`. Measured,
             not inferred: see
             specs/todos/2026-08-03-lsp-most-advertised-capabilities-are-dead.md.

             Rather than rewrite 20 handlers against 20 typed parameter records,
             recover the wire form of the request and feed it to the dispatcher
             that already implements them: [to_jsonrpc_request] gives back the
             method and params, and [response_of_json] turns the JSON they
             produce into the typed result this GADT arm owes. The handler
             bodies are untouched — they were never the broken part.

             A handler whose JSON does not match the protocol type now raises
             here rather than being quietly mistyped. That is the right
             direction: it converts a wrong shape into a visible failure, and
             the capability sweep in test_jsonrpc.ml is what will show it. *)
          let wire = Lsp.Client_request.to_jsonrpc_request req ~id:(`Int 0) in
          let params =
            Option.map
              (fun (p : Jsonrpc.Structured.t) -> (p :> Yojson.Safe.t))
              wire.Jsonrpc.Request.params
          in
          (* `Null is a LEGITIMATE result here, not a signal that the dispatcher
             declined: `textDocument/typeDefinition` answers null when the
             cursor is not on a type, and so do most option-returning requests.
             An earlier version treated it as "unhandled" and fell through to
             super, which reported the capability as dead when it was in fact
             answering correctly. The dispatcher signals "no branch for this
             method" by REJECTING (its final `Lwt.fail_with`), so that — and
             only that — is what delegates to super. *)
          Lwt.catch
            (fun () ->
              Lwt.bind
                (self#dispatch_by_method ~notify_back wire.Jsonrpc.Request.method_ params)
                (fun json -> Lwt.return (Lsp.Client_request.response_of_json req json)))
            (fun _exn -> super#on_request_unhandled ~notify_back ~id req)

    method on_unknown_request ~notify_back ~server_request:_ ~id:_ meth params =
      (* [params] arrives here as the narrower `Structured.t option`; the
         dispatcher works in plain JSON, which is a supertype of it. *)
      self#dispatch_by_method ~notify_back meth
        (Option.map (fun (p : Jsonrpc.Structured.t) -> (p :> Yojson.Safe.t)) params)

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
          ~full:(`Full (SemanticTokensOptions.create_full ~delta:true ()))
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
          Some (`RenameOptions
                  (Lsp.Types.RenameOptions.create ~prepareProvider:true ()));
        ServerCapabilities.signatureHelpProvider =
          Some sig_help;
        ServerCapabilities.foldingRangeProvider =
          Some (`Bool true);
        ServerCapabilities.workspaceSymbolProvider =
          Some (`Bool true);
        ServerCapabilities.documentFormattingProvider =
          Some (`Bool true);
        ServerCapabilities.implementationProvider =
          Some (`Bool true);
        ServerCapabilities.typeDefinitionProvider =
          Some (`Bool true);
        ServerCapabilities.documentHighlightProvider =
          Some (`Bool true);
        ServerCapabilities.selectionRangeProvider =
          Some (`Bool true);
        ServerCapabilities.inlineValueProvider =
          Some (`Bool true);
        ServerCapabilities.linkedEditingRangeProvider =
          Some (`Bool true);
        ServerCapabilities.callHierarchyProvider =
          Some (`Bool true);
        (* `workspaceDiagnostics` is a SEPARATE claim from the per-document
           pull: it promises `workspace/diagnostic`, a request over every file
           rather than the open ones, which this server does not answer.
           Advertising it while implementing only `textDocument/diagnostic`
           would recreate one level down the exact bug just fixed — a capability
           dispatched where nothing listens. Lowered until someone implements
           it; `Workspace.index_project` is the raw material if they do. *)
        ServerCapabilities.diagnosticProvider =
          Some (`DiagnosticOptions
                  (Lsp.Types.DiagnosticOptions.create
                     ~interFileDependencies:true ~workspaceDiagnostics:false ()));
        ServerCapabilities.codeLensProvider =
          Some (Lsp.Types.CodeLensOptions.create ~resolveProvider:false ());
        (* Advertise the runnable code-lens commands so generic clients know
           which command ids they may forward via workspace/executeCommand. *)
        ServerCapabilities.executeCommandProvider =
          Some (Lsp.Types.ExecuteCommandOptions.create
                  ~commands:[ "march.runTest"; "march.debugTest";
                              "march.run";     "march.debug";
                              "march.suggestRefinement";
                              "march.suggestPostcondition" ] ());
        (* Auto-close HTML tags inside ~H sigils when the user types '>'. *)
        ServerCapabilities.documentOnTypeFormattingProvider =
          Some (Lsp.Types.DocumentOnTypeFormattingOptions.create
                  ~firstTriggerCharacter:">" ()) }

    (* -------------------------------------------------------------- *)
    (* Document synchronisation                                        *)
    (* -------------------------------------------------------------- *)

    method on_notif_doc_did_open ~notify_back doc ~content =
      let uri = doc.Lsp.Types.TextDocumentItem.uri in
      let uri_str = Lsp.Types.DocumentUri.to_string uri in
      let v = bump_version versions uri_str in
      let a = analyse_and_cache uri content in
      (* Surface analysis activity in the editor's LSP log (the only observability
         the server previously had was stderr, which editors rarely show). *)
      Lwt.async (fun () ->
        notify_back#send_log_msg ~type_:Lsp.Types.MessageType.Info
          (Printf.sprintf "analyzed %s: %d diagnostic(s)"
             uri_str (List.length a.Analysis.diagnostics)));
      (* Run the TIR pipeline in a guarded background fiber: only publish if
         this edit is still current, and never let a TIR bug crash the server. *)
      Lwt.dont_wait
        (fun () ->
           if is_current versions uri_str v then begin
             let a2 = Analysis.run_tir_pass a in
             if is_current versions uri_str v then begin
               Hashtbl.replace doc_cache uri_str a2;
               notify_back#send_diagnostic
                 (List.map (Pos.remap_diagnostic a2.Analysis.doc) a2.Analysis.diagnostics)
             end else Lwt.return_unit
           end else Lwt.return_unit)
        (fun exn ->
           Printf.eprintf "march-lsp: TIR fiber error: %s\n%!"
             (Printexc.to_string exn));
      (* Push AST-level diagnostics immediately so the editor is responsive.
         Diagnostic ranges are byte columns; remap to UTF-16. *)
      notify_back#send_diagnostic
        (List.map (Pos.remap_diagnostic a.Analysis.doc) a.Analysis.diagnostics)

    method on_notif_doc_did_close ~notify_back:_ doc =
      Hashtbl.remove doc_cache
        (Lsp.Types.DocumentUri.to_string
           doc.Lsp.Types.TextDocumentIdentifier.uri);
      Lwt.return_unit

    (* A document was saved → its on-disk content changed, so the workspace
       index (built by reading files from disk) is stale. Clear it; the next
       workspace/symbol or cross-file references query rebuilds lazily. *)
    method! on_notif_doc_did_save ~notify_back:_ _params =
      invalidate_workspace_index ();
      Lwt.return_unit

    (* A file changed on disk outside the editor's open-document flow (e.g. a
       dependency edited in another window, or a build step). Clients that
       watch the workspace send workspace/didChangeWatchedFiles, routed here by
       linol as an "unhandled" notification. Drop the cross-file caches + the
       cached deps env so the next query re-reads from disk. *)
    method! on_notification_unhandled ~notify_back:_ n =
      (match n with
       | Lsp.Client_notification.DidChangeWatchedFiles _ ->
         invalidate_workspace_index ();
         Typecheck_cache.clear_deps ()
       | Lsp.Client_notification.ChangeConfiguration params ->
         (match perf_annotations_from_settings
                  params.Lsp.Types.DidChangeConfigurationParams.settings with
          | Some b -> perf_annotations := b
          | None -> ());
         (match param_name_hints_from_settings
                  params.Lsp.Types.DidChangeConfigurationParams.settings with
          | Some b -> param_name_hints := b
          | None -> ())
       | _ -> ());
      Lwt.return_unit

    method on_notif_doc_did_change ~notify_back vdoc _changes
        ~old_content:_ ~new_content =
      let uri = vdoc.Lsp.Types.VersionedTextDocumentIdentifier.uri in
      let uri_str = Lsp.Types.DocumentUri.to_string uri in
      let v = bump_version versions uri_str in
      (* Debounced + version-guarded: defer the analyse by [debounce_window];
         a newer keystroke supersedes this one (is_current becomes false) so
         only the latest edit in a burst is analysed. Then the same two-phase
         publish — AST diagnostics, then TIR insights — each version-guarded so
         a slow pass can never flicker a newer edit's results, and crash-
         isolated so a TIR-pass bug cannot take down the server. *)
      Lwt.dont_wait
        (fun () ->
           Lwt.bind (Lwt_unix.sleep debounce_window) (fun () ->
             if not (is_current versions uri_str v) then Lwt.return_unit
             else begin
               let a = analyse_and_cache uri new_content in
               Lwt.bind
                 (notify_back#send_diagnostic
                    (List.map (Pos.remap_diagnostic a.Analysis.doc) a.Analysis.diagnostics))
                 (fun () ->
                    if is_current versions uri_str v then begin
                      let a2 = Analysis.run_tir_pass a in
                      if is_current versions uri_str v then begin
                        Hashtbl.replace doc_cache uri_str a2;
                        notify_back#send_diagnostic
                          (List.map (Pos.remap_diagnostic a2.Analysis.doc) a2.Analysis.diagnostics)
                      end else Lwt.return_unit
                    end else Lwt.return_unit)
             end))
        (fun exn ->
           Printf.eprintf "march-lsp: did_change fiber error: %s\n%!"
             (Printexc.to_string exn));
      Lwt.return_unit

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
          let ts_str   = Analysis.query_typestate_hover_at a ~line ~utf16_char in
          let parts   = List.filter_map Fun.id [
            Option.map (fun ty -> Printf.sprintf "```march\n%s\n```" ty) ty_str;
            Option.map (fun d  -> "---\n" ^ d) doc_str;
            Option.map (fun p  -> "---\n" ^ p) perf_str;
            Option.map (fun ts -> "---\n" ^ ts) ts_str;
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
      let uri_str = Lsp.Types.DocumentUri.to_string uri in
      let items =
        match get_analysis uri with
        | None -> []
        | Some a -> Analysis.query_completions_at a ~line ~utf16_char
      in
      (* Auto-import items need the document URI so completionItem/resolve can
         re-fetch the analysis and compute the import edit. *)
      let items =
        List.map (fun (it : Lsp.Types.CompletionItem.t) ->
            match it.data with
            | Some (`Assoc fs) when List.mem_assoc "autoImport" fs ->
              { it with data = Some (`Assoc (("uri", `String uri_str) :: fs)) }
            | _ -> it)
          items
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
          let hs =
            Analysis.inlay_hints_for ~perf_annotations:!perf_annotations
              ~param_names:!param_name_hints a range in
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

    (* The string-keyed dispatcher.  Named separately from [on_unknown_request]
       because it now has TWO callers: that method (for methods linol could not
       decode) and [on_request_unhandled] (for methods it decoded but has no
       dedicated handler for).  Splitting them is what makes the second reachable
       at all — see the note on [on_request_unhandled] below. *)
    method private dispatch_by_method ~notify_back:(_notify_back : _) meth params =
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
           item, using the (module, name, uri) stashed in its `data`. *)
        match params with
        | Some (`Assoc fields) ->
          let edit =
            match List.assoc_opt "data" fields with
            | Some (`Assoc data) ->
              (match List.assoc_opt "autoImport" data, List.assoc_opt "uri" data with
               | Some (`Assoc ai), Some (`String u) ->
                 let g k = match List.assoc_opt k ai with
                   | Some (`String s) -> s | _ -> "" in
                 let m = g "module" and n = g "name" in
                 let path =
                   if String.length u >= 7 && String.sub u 0 7 = "file://"
                   then String.sub u 7 (String.length u - 7) else u in
                 let uri = Lsp.Types.DocumentUri.of_path path in
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
  end
