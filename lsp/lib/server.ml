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
               (* [run_tir_pass] returns [a] PHYSICALLY UNCHANGED when the
                  source has errors (it skips the TIR pipeline entirely rather
                  than run it on broken input) — so [a2.diagnostics] is then
                  the exact same list already published below. Re-publishing
                  it anyway doesn't just waste a round trip: a client that
                  doesn't treat publishDiagnostics as a full replacement (or
                  that surfaces overlapping-range diagnostics from more than
                  one publish in its hover UI) shows the same message stacked
                  twice. Only publish again when the TIR pass actually ran. *)
               if a2 != a then
                 notify_back#send_diagnostic
                   (List.map (Pos.remap_diagnostic a2.Analysis.doc) a2.Analysis.diagnostics)
               else Lwt.return_unit
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
                        (* See the matching comment in [on_notif_doc_did_open]:
                           [run_tir_pass] returns [a] unchanged when the
                           source has errors, so re-publishing [a2.diagnostics]
                           then republishes the exact list already sent above
                           — the visible symptom being a diagnostic shown
                           stacked twice in the editor. *)
                        if a2 != a then
                          notify_back#send_diagnostic
                            (List.map (Pos.remap_diagnostic a2.Analysis.doc) a2.Analysis.diagnostics)
                        else Lwt.return_unit
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
         re-fetch the analysis and compute the import edit. The document
         version is stashed alongside it so resolve can refuse to answer
         against a buffer that has since changed underneath it — resolve is
         a separate, unordered request the client can fire per-keystroke
         while filtering the completion list, well after the user has moved
         on to typing elsewhere; computing an import-insertion edit (whose
         target line is the file's first declaration, not the cursor —
         see [Analysis.import_text_edit]) against a stale analysis lands
         the edit on whatever now occupies that unrelated line. *)
      let v = (match Hashtbl.find_opt versions uri_str with Some n -> n | None -> 0) in
      let items =
        List.map (fun (it : Lsp.Types.CompletionItem.t) ->
            match it.data with
            | Some (`Assoc fs) when List.mem_assoc "autoImport" fs ->
              { it with data = Some (`Assoc
                  (("uri", `String uri_str) :: ("version", `Int v) :: fs)) }
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
    method private dispatch_by_method ~notify_back meth params =
      (* The body is a free function: it used no `self` and no `super`, so it
         lives in server_dispatch.ml. `notify_back` is threaded through
         unchanged rather than dropped here, which is what lets the body move
         verbatim — see the ORDER IS SEMANTICS note at the top of that file. *)
      Server_dispatch.dispatch ~notify_back ~meth ~params
  end
