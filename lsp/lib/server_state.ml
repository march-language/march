(** march-lsp server state — the caches, settings, workspace index and
    semantic-token encoding that both {!Server}'s class methods and its
    string-keyed request dispatcher read.

    Extracted verbatim from [server.ml] (Target C task C2 of
    specs/plans/2026-08-27-remaining-decomposition-targets.md). It is a layer
    BENEATH the server class rather than a peer of it: the caches below are
    mutable globals whose declaration order matters, and both the class and the
    dispatcher consume them.

    [server.ml] re-exports these with [include], not [open], because
    [lsp/test/test_lsp.ml] reaches several of them through [Server.] —
    [semantic_tokens_data], [token_delta], [param_name_hints_from_settings] and
    [perf_annotations_from_settings]. *)


module Lsp = Linol_lsp.Lsp
module S   = Linol_lwt.Jsonrpc2
module Pos = Position  (* our position utilities *)
module Jsonrpc = Linol_jsonrpc.Jsonrpc

(* ------------------------------------------------------------------ *)
(* Document cache                                                      *)
(* ------------------------------------------------------------------ *)

let doc_cache : (string, Analysis.t) Hashtbl.t = Hashtbl.create 16

(* Whether to emit the FBIP performance inlay annotations (♻ reused / ⧉ copied).
   Toggled by the client via `march.inlayHints.performanceAnnotations`. *)
let perf_annotations = ref true

(* Read `march.inlayHints.performanceAnnotations` (a bool) out of a
   didChangeConfiguration `settings` payload. Accepts both the fully-qualified
   path and the prefix-stripped form some clients send. None when absent. *)
let perf_annotations_from_settings (settings : Yojson.Safe.t) : bool option =
  let rec dig path j =
    match path, j with
    | [], `Bool b -> Some b
    | k :: rest, `Assoc fields ->
      (match List.assoc_opt k fields with Some j' -> dig rest j' | None -> None)
    | _ -> None
  in
  match dig ["march"; "inlayHints"; "performanceAnnotations"] settings with
  | Some _ as r -> r
  | None -> dig ["inlayHints"; "performanceAnnotations"] settings

(* Whether to emit parameter-name inlay hints at call sites
   (foo(width: a, height: b)). Toggled via `march.inlayHints.parameterNames`.
   Defaults ON. *)
let param_name_hints = ref true

(* Read `march.inlayHints.parameterNames` (a bool) out of a
   didChangeConfiguration `settings` payload. Accepts both the fully-qualified
   path and the prefix-stripped form some clients send. None when absent. *)
let param_name_hints_from_settings (settings : Yojson.Safe.t) : bool option =
  let rec dig path j =
    match path, j with
    | [], `Bool b -> Some b
    | k :: rest, `Assoc fields ->
      (match List.assoc_opt k fields with Some j' -> dig rest j' | None -> None)
    | _ -> None
  in
  match dig ["march"; "inlayHints"; "parameterNames"] settings with
  | Some _ as r -> r
  | None -> dig ["inlayHints"; "parameterNames"] settings

(* Per-document cache of the last semantic-token result, for delta requests:
   uri → (resultId, token data). *)
let sem_tokens_cache : (string, string * int array) Hashtbl.t = Hashtbl.create 16
let sem_tokens_counter = ref 0
let next_result_id () =
  incr sem_tokens_counter; string_of_int !sem_tokens_counter

(* Minimal single-edit delta between two flat token arrays: trim the common
   prefix and suffix, then describe the changed middle as one edit. *)
let token_delta (old_data : int array) (new_data : int array)
    : int * int * int array =
  let ol = Array.length old_data and nl = Array.length new_data in
  let p = ref 0 in
  while !p < ol && !p < nl && old_data.(!p) = new_data.(!p) do incr p done;
  let s = ref 0 in
  while !s < (ol - !p) && !s < (nl - !p)
        && old_data.(ol - 1 - !s) = new_data.(nl - 1 - !s) do incr s done;
  (!p, ol - !p - !s, Array.sub new_data !p (nl - !p - !s))

(* Monotonic per-document version. A background fiber (the TIR pass) only
   publishes if the document hasn't advanced since the fiber started, so a slow
   fiber for an old edit can't overwrite a newer analysis or flicker stale
   diagnostics. *)
let make_version_table () : (string, int) Hashtbl.t = Hashtbl.create 16
let versions = make_version_table ()
let bump_version vt uri =
  let v = (match Hashtbl.find_opt vt uri with Some n -> n | None -> 0) + 1 in
  Hashtbl.replace vt uri v;
  v
let is_current vt uri v =
  match Hashtbl.find_opt vt uri with Some n -> n = v | None -> false

(* Debounce window for did_change: an edit's analyse is deferred by this many
   seconds and runs only if no newer edit for the same document arrived during
   the window (checked via [is_current]). Coalesces bursts of keystrokes so a
   full analyse + TIR pass runs once per typing pause, not per character. *)
let debounce_window = 0.05

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
(* Workspace symbol index (cross-file)                                 *)
(* ------------------------------------------------------------------ *)

let ws_index : (string, Workspace.ws_symbol list) Hashtbl.t = Hashtbl.create 1

(* Derive the project root from any open document's directory, walking up to a
   forge.toml when present. *)
let project_root () : string option =
  let from_doc =
    Hashtbl.fold (fun _ (a : Analysis.t) acc ->
        match acc with
        | Some _ -> acc
        | None ->
          if a.Analysis.filename <> "" && a.Analysis.filename <> "<unknown>"
          then Some (Filename.dirname a.Analysis.filename)
          else None)
      doc_cache None
  in
  (* A directory is only a WORKSPACE if it plausibly bounds a project.  With a
     `forge.toml` above the document, that is settled.  Without one, the
     document's own directory is a guess — and for a file opened at `/`, in a
     home directory, or in a scratch dir, indexing it means walking a tree that
     has nothing to do with the code being edited.

     Refusing those is better than indexing them: workspace symbol search over
     an arbitrary slice of someone's disk returns noise, and (before the walk
     was bounded) never returned at all. The bound in [Workspace.walk_dir] is
     the backstop; this is the part that avoids starting a walk nobody wanted. *)
  let implausible_root dir =
    let home = try Sys.getenv "HOME" with Not_found -> "" in
    dir = "/" || dir = "" || (home <> "" && dir = home)
  in
  match from_doc with
  | Some dir ->
    (match Forge_config.find_forge_root dir with
     | Some r -> Some r
     | None -> if implausible_root dir then None else Some dir)
  | None ->
    (try
       let cwd = Sys.getcwd () in
       if implausible_root cwd then None else Some cwd
     with _ -> None)

(* Built once per root and cached (invalidation on disk change is a follow-up). *)
let workspace_index () : Workspace.ws_symbol list =
  match project_root () with
  | None -> []
  | Some root ->
    (match Hashtbl.find_opt ws_index root with
     | Some idx -> idx
     | None ->
       let idx = Workspace.index_project ~root in
       Hashtbl.replace ws_index root idx;
       idx)

(* Full index (defs + uses) for cross-file references. *)
let ws_index_full : (string, Workspace.ws_index) Hashtbl.t = Hashtbl.create 1
let workspace_index_full () : Workspace.ws_index =
  match project_root () with
  | None -> { Workspace.wsi_defs = []; wsi_uses = [] }
  | Some root ->
    (match Hashtbl.find_opt ws_index_full root with
     | Some idx -> idx
     | None ->
       let idx = Workspace.index_project_full ~root in
       Hashtbl.replace ws_index_full root idx;
       idx)

(* Drop all cross-file caches built by reading files from disk. Called on
   didSave (an open doc changed) and on didChangeWatchedFiles (any on-disk
   .march changed, including non-open / dependency files). *)
let invalidate_workspace_index () =
  Hashtbl.clear ws_index;
  Hashtbl.clear ws_index_full

let workspace_index_is_empty () =
  Hashtbl.length ws_index = 0 && Hashtbl.length ws_index_full = 0

(* ------------------------------------------------------------------ *)
(* Code actions (helper, defined before the class)                    *)
(* ------------------------------------------------------------------ *)

(* "Introduce parameter object" — when the cursor is on a bundleable function,
   run the march_refactor bundle engine (dry-run, so it computes but does not
   write) and surface its project-wide rewrite as a multi-file WorkspaceEdit.
   This is the cross-file part a single-file code action otherwise can't do. *)
let bundle_actions (a : Analysis.t) ~line ~character : Lsp.Types.CodeAction.t list =
  let module R = March_refactor.Refactor in
  match Analysis.bundleable_fn_at a ~line ~character with
  | None -> []
  | Some fn_name ->
    (match project_root () with
     | None -> []
     | Some root ->
       (match (try R.bundle_fn ~root ~fn_name ~dry_run:true () with _ -> Error "exn") with
        | Error _ -> []
        | Ok outcome when outcome.R.changes = [] -> []
        | Ok outcome ->
          let open Lsp.Types in
          let changes =
            List.map (fun (fc : R.file_change) ->
                (* Whole-document replace: range from (0,0) to the end of the
                   old content (byte columns ≈ UTF-16 for typical code). *)
                let el = ref 0 and ec = ref 0 in
                String.iter (fun ch ->
                    if ch = '\n' then (incr el; ec := 0) else incr ec) fc.R.fc_old;
                let edit = TextEdit.create
                    ~range:(Range.create
                              ~start:(Position.create ~line:0 ~character:0)
                              ~end_:(Position.create ~line:!el ~character:!ec))
                    ~newText:fc.R.fc_new in
                (DocumentUri.of_path fc.R.fc_path, [edit]))
              outcome.R.changes
          in
          [CodeAction.create
             ~title:(Printf.sprintf "Introduce parameter object for `%s`" fn_name)
             ~kind:CodeActionKind.RefactorRewrite
             ~edit:(WorkspaceEdit.create ~changes ()) ()]))

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
  (Analysis.code_actions_at a ~line ~character ~diagnostics ()
   |> List.map (Pos.remap_code_action a.Analysis.doc))
  @ bundle_actions a ~line ~character

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
  let mod_linear      = 8 in
  let mod_affine      = 16 in

  (* Ownership modifiers, read off the TYPE SYSTEM (Analysis.build_linearity_map):
     a binding is `linear`/`affine` because it was declared so — an explicit
     qualifier, a `linear T`/`affine T` annotation, or a type declared
     `always_linear type`.

     This used to be derived from use COUNTS instead (consumed once = linear,
     zero = affine), which tagged every ordinary once-used binding `linear`.
     Use count answers a different question than linearity does, and painting a
     plain `let x = 1` as linear misrepresents the one guarantee a reader is
     opening the editor to check. Bindings whose linearity is only inferred are
     now left uncolored rather than guessed at.

     Keyed by name, matching the rest of the LSP's name-based symbol model. *)
  let ownership = Hashtbl.create 32 in
  List.iter (fun (name, (lin : March_ast.Ast.linearity)) ->
      match lin with
      | March_ast.Ast.Linear -> Hashtbl.replace ownership name mod_linear
      | March_ast.Ast.Affine -> Hashtbl.replace ownership name mod_affine
      | March_ast.Ast.Unrestricted -> ()
    ) (Analysis.build_linearity_map a.Analysis.decls a.Analysis.always_linear_names);
  let ownership_mod name =
    match Hashtbl.find_opt ownership name with Some m -> m | None -> 0
  in

  let tokens = ref [] in
  (* LSP semantic-token start columns and lengths are in UTF-16 code units. *)
  let to_u line0 byte_col =
    Utf16.byte_col_to_lsp_char a.Analysis.doc ~line:line0 ~byte_col
  in

  (* Only spans belonging to THIS document may be emitted.  [def_map] and
     [use_map] cover the whole analysis, and the analysis has the prelude and
     any imported modules injected — so iterating them unfiltered emitted a
     token for every stdlib definition, at line numbers from another file
     entirely.  Measured on a 15-line document: 6949 tokens reaching line 3512.

     The client has no way to detect that; it either wastes the bandwidth or
     paints ranges that do not exist.  The bug was invisible while the request
     itself was unreachable, and surfaced the moment the dispatch was repaired —
     the second-round failure that being unable to run a feature hides. *)
  let in_this_document (sp : March_ast.Ast.span) =
    sp.March_ast.Ast.file = a.Analysis.filename
  in

  Hashtbl.iter (fun name sp ->
      if in_this_document sp then
      let tok_type_idx, mods =
        if List.mem_assoc name a.Analysis.types then
          tok_type, mod_declaration lor mod_readonly
        else if List.mem_assoc name a.Analysis.ctors then
          tok_enum_member, mod_declaration lor mod_readonly
        else
          (* A tracked value binding (in the consumption analysis) is a
             variable carrying an ownership modifier; everything else
             (functions, params) stays a function declaration. *)
          let own = ownership_mod name in
          if own <> 0 then tok_variable, mod_declaration lor own
          else tok_function, mod_declaration
      in
      let len = sp.March_ast.Ast.end_col - sp.March_ast.Ast.start_col in
      if sp.March_ast.Ast.start_line = sp.March_ast.Ast.end_line && len > 0 then begin
        let line0 = sp.March_ast.Ast.start_line - 1 in
        let u_start = to_u line0 sp.March_ast.Ast.start_col in
        let u_len   = to_u line0 sp.March_ast.Ast.end_col - u_start in
        tokens := (line0, u_start, u_len, tok_type_idx, mods) :: !tokens
      end
    ) a.Analysis.def_map;

  Hashtbl.iter (fun sp name ->
      if in_this_document sp then
      (* Tag the use site by what the name resolves to — type, constructor,
         or variable — instead of blindly calling every use a variable. *)
      let tok, mods =
        if List.mem_assoc name a.Analysis.types then tok_type, mod_readonly
        else if List.mem_assoc name a.Analysis.ctors then tok_enum_member, mod_readonly
        else tok_variable, ownership_mod name
      in
      let len = sp.March_ast.Ast.end_col - sp.March_ast.Ast.start_col in
      if sp.March_ast.Ast.start_line = sp.March_ast.Ast.end_line && len > 0 then begin
        let line0 = sp.March_ast.Ast.start_line - 1 in
        let u_start = to_u line0 sp.March_ast.Ast.start_col in
        let u_len   = to_u line0 sp.March_ast.Ast.end_col - u_start in
        tokens := (line0, u_start, u_len, tok, mods) :: !tokens
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
