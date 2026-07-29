(** March cross-file import resolver — shared between the compiler entry
    point (bin/main.ml), the REPL (lib/repl/repl.ml), and the LSP
    (lsp/lib/analysis.ml).

    This is the single source of truth for module resolution.  It resolves
    explicit [import]/[alias] declarations by filename convention AND
    auto-discovers every .march file reachable through the library search
    path, indexing modules by their DECLARED name — so a module like
    [Bastion.Channel] living in [channel.march] resolves the same way for
    `forge check`, the REPL, and editor diagnostics. *)

(** Convert a single CamelCase segment to snake_case.
    E.g. "HttpClient" → "http_client", "Router" → "router" *)
let camel_to_snake name =
  let buf = Buffer.create (String.length name + 4) in
  String.iteri (fun i c ->
    if i > 0 && c >= 'A' && c <= 'Z' then begin
      Buffer.add_char buf '_';
      Buffer.add_char buf (Char.lowercase_ascii c)
    end else
      Buffer.add_char buf (Char.lowercase_ascii c)
  ) name;
  Buffer.contents buf

(** Convert a possibly-dotted module name to a relative file path.
    Single segment: "HttpClient" → "http_client.march"
    Dotted:         "MyApp.Router" → "my_app/router.march"
                    "MyApp.Templates.Layout" → "my_app/templates/layout.march" *)
let module_name_to_filename name =
  let parts = String.split_on_char '.' name in
  let snake_parts = List.map camel_to_snake parts in
  String.concat Filename.dir_sep snake_parts ^ ".march"

(** Stdlib module names — used only to SUPPRESS "module not found" errors
    for imports that resolve from the bundled stdlib.  A user file with the
    same conventional filename always wins (it is found first), so listing
    a name here never shadows user code.

    Every entry must name a module that [stdlib/] actually declares.  Nine
    Depot* names (Depot, Depot.Gate, DepotForm, DepotGate, DepotSchema,
    DepotRepo, DepotQuery, DepotMigration, DepotTest) were listed but ship
    in the third-party `depot` package, not here, so they only suppressed
    genuine diagnostics for depot's own modules.  "URI" was likewise never
    a module — [stdlib/uri.march] declares `mod Uri`, and the mismatched
    casing meant a plain `import Uri` reported "not found". *)
let stdlib_module_names =
  [ "List"; "Map"; "Set"; "Array"; "Queue"; "String"; "Option"; "Result"
  ; "Math"; "Enum"; "BigInt"; "Decimal"; "DateTime"; "Duration"; "Bytes"; "Json"
  ; "Regex"; "Csv"; "File"; "Dir"; "Path"; "Http"; "HttpClient"
  ; "HttpServer"; "HttpTransport"; "WebSocket"; "Process"; "Logger"
  ; "Flow"; "Actor"; "Sort"; "Hamt"; "Seq"; "Iterable"; "IOList"
  ; "Random"; "Stats"; "Plot"; "Prelude"; "DataFrame"; "Test"
  ; "Vault"; "Uri"
  ; "Config"; "Crypto"; "Env"; "Channel"; "PubSub"
  ; "ChannelServer"; "ChannelSocket"; "Presence"; "Tls"; "Uuid"
  ; "Tuple"; "Char"; "OrderedMap"; "SortedSet"; "Range" ]

(** All non-empty dotted prefixes of [names], LONGEST first, down to the
    single leading segment. E.g. [["A"; "B"; "C"]] -> [["A.B.C"; "A.B"; "A"]].
    Used to disambiguate a dotted [use]/[alias] path (see [import_refs]). *)
let dotted_prefixes (names : string list) : string list =
  let rec aux acc = function
    | [] -> List.rev acc
    | l -> aux (String.concat "." l :: acc) (List.rev (List.tl (List.rev l)))
  in
  aux [] names

(** Collect [(candidate_names, span)] for each DUse/DAlias in [decls],
    recursing into nested DMod blocks so that imports written inside
    `mod Foo do import Bar ... end` are also resolved.

    [candidate_names] lists every dotted prefix of the written path, longest
    first: a dotted path like `use A.B` is syntactically ambiguous between
    TWO distinct multi-file patterns that both use the same `Outer.Inner`
    spelling —
    (1) a top-level module literally named "A.B", living in its own file per
        the "one mod per file" convention (`module_name_to_filename` maps it
        to `a/b.march`), or
    (2) a submodule `B` nested inside a single file's `mod A do mod B do
        ... end end`, where only "A" is an actual file on disk.
    [load_refs] tries each candidate against the search path and loads the
    first one that resolves to a real file, so both patterns work without
    the writer having to know (or the parser being able to tell) which one
    a given `use`/`alias` path is. *)
let rec import_refs decls =
  List.concat_map (function
    | March_ast.Ast.DUse (ud, sp) ->
      (match ud.March_ast.Ast.use_path with
       | [] -> []
       | segs ->
         let names = List.map (fun (n : March_ast.Ast.name) -> n.March_ast.Ast.txt) segs in
         [(dotted_prefixes names, sp)])
    | March_ast.Ast.DAlias (ad, sp) ->
      (match ad.March_ast.Ast.alias_path with
       | [] -> []
       | segs ->
         let names = List.map (fun (n : March_ast.Ast.name) -> n.March_ast.Ast.txt) segs in
         [(dotted_prefixes names, sp)])
    | March_ast.Ast.DMod (_, _, inner_decls, _) ->
      import_refs inner_decls
    | _ -> []
  ) decls

(** A module that must NEVER be pruned by reachability analysis: its decls
    have GLOBAL effect (typeclass instances, interfaces, protocols, FFI
    symbols, derived instances, state-machine transitions) that other modules
    can use WITHOUT textually naming this module, so dropping it would break
    dispatch / linking even though no reference names it.  Recurses into
    nested [DMod] blocks. *)
let rec has_global_effect_decl decls =
  List.exists (function
    | March_ast.Ast.DImpl _ | March_ast.Ast.DInterface _
    | March_ast.Ast.DDeriving _ | March_ast.Ast.DTransitions _
    | March_ast.Ast.DProtocol _ | March_ast.Ast.DExtern _
    | March_ast.Ast.DDescribe _ | March_ast.Ast.DTest _
    | March_ast.Ast.DSetup _ | March_ast.Ast.DSetupAll _ -> true
    | March_ast.Ast.DMod (_, _, inner, _) -> has_global_effect_decl inner
    | _ -> false) decls

(** Names a module makes available that OTHER modules can reference WITHOUT
    naming this module — its type names and their data constructors (March
    registers constructors program-wide, so `Foo(1)` can resolve to a ctor of a
    module the caller never names).  Used, alongside the module's own name, as a
    reachability anchor so such a module is not wrongly pruned.  Recurses into
    nested [DMod] blocks. *)
let rec provided_anchor_names decls =
  List.concat_map (function
    | March_ast.Ast.DType (_, tn, _, td, _)
    | March_ast.Ast.DAlwaysLinearType (_, tn, _, td, _) ->
      tn.March_ast.Ast.txt ::
      (match td with
       | March_ast.Ast.TDVariant variants ->
         List.map (fun (v : March_ast.Ast.variant) -> v.var_name.March_ast.Ast.txt) variants
       | _ -> [])
    | March_ast.Ast.DMod (_, _, inner, _) -> provided_anchor_names inner
    | _ -> []) decls

(** Over-approximate the set of module-name tokens textually referenced in
    [text]: every maximal run of identifier/dot characters, plus each of its
    dot-separated prefixes (so `A.B.C.member` yields A, A.B, A.B.C, ...).  Used
    to decide which auto-discovered modules an entry can reach.  This is a
    deliberate OVER-approximation — a name appearing in a comment or string
    still counts — because the only safe error direction is to KEEP a module
    that turns out unused; wrongly pruning a reachable module would break the
    build. *)
let referenced_name_tokens text =
  let tbl : (string, unit) Hashtbl.t = Hashtbl.create 64 in
  let n = String.length text in
  let is_tok c =
    (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
    || (c >= '0' && c <= '9') || c = '_' || c = '.'
  in
  let i = ref 0 in
  while !i < n do
    if is_tok text.[!i] then begin
      let start = !i in
      while !i < n && is_tok text.[!i] do incr i done;
      let run = String.sub text start (!i - start) in
      (* Register every dot-prefix of the run so a qualified reference marks
         its enclosing namespace module reachable too. *)
      ignore (List.fold_left (fun acc seg ->
          let path = if acc = "" then seg else acc ^ "." ^ seg in
          Hashtbl.replace tbl path ();
          path) "" (String.split_on_char '.' run))
    end else incr i
  done;
  tbl

let read_file path =
  let ic = open_in_bin path in
  let n  = in_channel_length ic in
  let b  = Bytes.create n in
  really_input ic b 0 n;
  close_in ic;
  Bytes.to_string b

(** Parse a .march source file.  Returns [Ok module_ast] or [Error msg].
    Applies a span-remap sidecar when one exists (template-lowered files). *)
let parse_march_file path src =
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
  try
    let m = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
    let m = match March_ast.Span_remap.load_sidecar path with
      | Some tbl -> March_ast.Span_remap.remap_module tbl m
      | None -> m
    in
    Ok m
  with
  | March_errors.Errors.ParseError (msg, _hint, pos) ->
    let open Lexing in
    Error (Printf.sprintf "%s:%d: parse error: %s" path pos.pos_lnum msg)
  | March_parser.Parser.Error ->
    let pos = Lexing.lexeme_start_p lexbuf in
    let open Lexing in
    Error (Printf.sprintf "%s:%d: parse error" path pos.pos_lnum)

(** Recursively collect all .march files under [dir].
    Entries are sorted so discovery order is deterministic — raw
    [Sys.readdir] order is unspecified and filesystem-dependent, which
    would make whole-program module discovery vary across machines. *)
let collect_lib_files dir =
  let rec walk acc d =
    if not (Sys.file_exists d && Sys.is_directory d) then acc
    else begin
      (* A permission-denied directory (e.g. macOS's $TMPDIR/TemporaryItems,
         which [Sys.is_directory] reports as a directory since it stats fine,
         but whose contents are "Operation not permitted") makes [Sys.readdir]
         raise [Sys_error].  Treat any directory we cannot read as empty and
         skip it rather than crashing the whole compile — an unrelated
         unreadable sibling must never abort an otherwise well-typed build. *)
      let entries = try Sys.readdir d with Sys_error _ -> [||] in
      Array.sort compare entries;
      Array.fold_left (fun acc name ->
          (* Skip dotfiles/dotdirs and macOS AppleDouble junk ("._x.march": a
             binary resource-fork file that ends in ".march" but is not source —
             invisible on macOS, a real NUL-leading file on Linux that the lexer
             rejects). Also skips .git/.march/etc. Never a source module. *)
          if String.length name > 0 && name.[0] = '.' then acc
          else
          let p = Filename.concat d name in
          (* A dangling symlink makes [Sys.is_directory] (which stats through
             the link) raise [Sys_error]; skip any entry we can't stat rather
             than aborting the whole compile. *)
          match Sys.is_directory p with
          | true -> walk acc p
          | false -> if Filename.check_suffix p ".march" then p :: acc else acc
          | exception (Sys_error _ | Unix.Unix_error _) -> acc)
        acc entries
    end
  in
  walk [] dir

(** Resolve cross-file imports and auto-discover project library files.

    Step 1 resolves explicit [import]/[alias] declarations from the entry
    module (by filename convention).  Step 2 auto-discovers all .march
    files in the library search path so that qualified cross-module calls
    (e.g. MyApp.Router.dispatch) and modules whose declared name does not
    match their filename (mod Bastion.Channel in channel.march) work
    without explicit [use] declarations — required for multi-file projects.

    The search path is [source_dir :: extra_lib_paths @ MARCH_LIB_PATH].
    [extra_lib_paths] lets callers (e.g. the LSP) inject paths derived from
    forge.toml without requiring the env var to be set.

    Returns (errors, extra_dmods_to_prepend, user_files) where [user_files]
    is every file loaded as user code (entry + imports + discovered libs) —
    callers use it to decide which typecheck diagnostics are fatal. *)
let resolve_imports ?(extra_lib_paths = []) ?(auto_discover = true)
    ~source_file (m : March_ast.Ast.module_) =
  let source_dir = Filename.dirname source_file in
  let env_lib_paths =
    match Sys.getenv_opt "MARCH_LIB_PATH" with
    | None -> []
    | Some s -> List.filter (fun d -> d <> "") (String.split_on_char ':' s)
  in
  let all_lib_paths = extra_lib_paths @ env_lib_paths in
  let search_path = source_dir :: all_lib_paths in
  let resolved : (string, March_ast.Ast.decl list) Hashtbl.t = Hashtbl.create 8 in
  (* Track loaded file paths so the same file is never parsed twice *)
  let loaded_paths : (string, unit) Hashtbl.t = Hashtbl.create 8 in
  (* [loaded_paths] is keyed by CANONICAL (realpath) paths for dedup, but
     diagnostic spans carry the path string the file was PARSED under
     (pos_fname = the possibly-relative path used to open it).  Callers do
     exact membership checks of span files against [user_files], so record
     BOTH forms — returning only the canonical form silently un-fixed the
     imported-module error filter (regression fixture:
     test/imports/entry_imports_ill_typed.march). *)
  let user_files = ref [] in
  let note_user_file path canon =
    user_files :=
      path :: (if canon = path then [] else [canon]) @ !user_files
  in
  let in_progress : (string, unit) Hashtbl.t = Hashtbl.create 4 in
  (* Source text of every module reachable via explicit imports (step 1).
     Seeds step-2 reachability analysis so that a qualified reference made
     from an explicitly-imported module (e.g. `use App` then `App.Sub.foo`)
     still keeps [App.Sub] in the build. *)
  let loaded_srcs : string list ref = ref [] in
  let errors : (string * March_ast.Ast.span * string) list ref = ref [] in
  let dummy_span = March_ast.Ast.dummy_span in
  (* Pre-mark the entry file so auto-discovery never re-loads it.
     Canonicalise the path so that relative and absolute references to the
     same file are treated as identical (prevents the file being loaded a
     second time when it also appears in the lib path as an absolute path). *)
  let canonical_source =
    (try Unix.realpath source_file with Unix.Unix_error _ -> source_file) in
  Hashtbl.add loaded_paths canonical_source ();
  note_user_file source_file canonical_source;

  (* Does [path] declare `mod [mod_name]` at the start of a line?  A cheap
     textual check — enough to locate the file, which is then parsed
     properly by [load]. *)
  let file_declares path mod_name =
    match (try Some (read_file path) with Sys_error _ -> None) with
    | None -> false
    | Some src ->
      let needle = "mod " ^ mod_name in
      let nlen = String.length needle in
      let slen = String.length src in
      let rec scan i =
        if i + nlen > slen then false
        else if (i = 0 || src.[i - 1] = '\n')
                && String.sub src i nlen = needle
                && (i + nlen = slen
                    || (match src.[i + nlen] with
                        | ' ' | '\t' | '\n' | '\r' -> true
                        | _ -> false))
        then true
        else scan (i + 1)
      in
      scan 0
  in

  (* The conventional dotted->path mapping first ("MyApp.Router" ->
     "my_app/router.march"), then a scan for the file that actually DECLARES
     the module.  The scan matters because a module's file need not follow
     the convention: step 2's auto-discovery keys off the `mod` declaration,
     not the path, so such a module was always reachable — just not by
     explicit `import`.  depot declares `mod Depot.Query` in
     lib/api/depot_query.march, and until [import_refs] began yielding
     dotted candidates that import resolved only because "Depot" sat
     (wrongly) in [stdlib_module_names] and suppressed the lookup entirely.
     Scanning only on a miss keeps the common path a single [Sys.file_exists]
     and preserves the precise "looked for <path>" diagnostic for a module
     that genuinely is not there. *)
  let find_file mod_name =
    let fname = module_name_to_filename mod_name in
    match
      List.find_map (fun dir ->
          let p = Filename.concat dir fname in
          if Sys.file_exists p then Some p else None
        ) search_path
    with
    | Some p -> Some p
    | None ->
      List.find_map (fun dir ->
          List.find_opt (fun p -> file_declares p mod_name)
            (collect_lib_files dir)
        ) search_path
  in

  let rec load mod_name ~from_span =
    if Hashtbl.mem resolved mod_name then
      (* Already emitted at some point — never re-emit (would duplicate decls) *)
      []
    else if Hashtbl.mem in_progress mod_name then begin
      errors := (mod_name, from_span,
        Printf.sprintf
          "Circular import: module `%s` imports itself (directly or transitively)"
          mod_name) :: !errors;
      []
    end else begin
      Hashtbl.add in_progress mod_name ();
      let result =
        match find_file mod_name with
        | None ->
          if not (List.mem mod_name stdlib_module_names) then
            errors := (mod_name, from_span,
              Printf.sprintf
                "Module `%s` not found (looked for `%s` in the source directory)"
                mod_name (module_name_to_filename mod_name)) :: !errors;
          []
        | Some file_path ->
          let canon_fp =
            (try Unix.realpath file_path with Unix.Unix_error _ -> file_path) in
          if Hashtbl.mem loaded_paths canon_fp then
            (* Already loaded (entry file or earlier import) — avoid duplication *)
            []
          else begin
            Hashtbl.add loaded_paths canon_fp ();
            note_user_file file_path canon_fp;
            let src =
              try read_file file_path
              with Sys_error msg ->
                errors := (mod_name, from_span,
                  Printf.sprintf "Cannot read `%s`: %s" file_path msg) :: !errors;
                ""
            in
            if src <> "" then loaded_srcs := src :: !loaded_srcs;
            if src = "" then []
            else
              match parse_march_file file_path src with
              | Error msg ->
                errors := (mod_name, from_span, msg) :: !errors; []
              | Ok ast ->
                let ast = March_desugar.Desugar.desugar_module ~is_entry:false ast in
                (* Mark resolved BEFORE recursing so cycles don't duplicate. *)
                Hashtbl.add resolved mod_name [];
                let transitive = load_refs ast.March_ast.Ast.mod_decls in
                let self_dmod =
                  March_ast.Ast.DMod (ast.March_ast.Ast.mod_name,
                                      March_ast.Ast.Public,
                                      ast.March_ast.Ast.mod_decls,
                                      dummy_span)
                in
                (* Emit transitive imports as top-level siblings, NOT nested.
                   Nesting would cause TIR to prefix their fn names with this
                   module's name (e.g. `Runner.foo` → `Processes.Runner.foo`),
                   which breaks qualified cross-module calls at link time. *)
                transitive @ [self_dmod]
          end
      in
      Hashtbl.remove in_progress mod_name;
      result
    end

  and load_refs decls =
    let refs = import_refs decls in
    let seen : (string, unit) Hashtbl.t = Hashtbl.create 4 in
    List.concat_map (fun (candidates, span) ->
        (* Drop any candidate that names a stdlib module outright — matches
           the pre-existing behavior of skipping a bare stdlib [use] (deferred
           to lazy stdlib loading, never routed through this file resolver). *)
        match List.filter (fun c -> not (List.mem c stdlib_module_names)) candidates with
        | [] -> []
        | filtered ->
          (* Try candidates longest (most specific) first — see
             [import_refs]'s doc comment for why a dotted path is ambiguous
             between a same-named top-level file and a nested submodule.
             The first candidate that maps to a REAL file on the search path
             wins; if none do, fall through to the longest candidate so the
             "not found" diagnostic names the actual path that was written. *)
          let target =
            match List.find_opt (fun c -> find_file c <> None) filtered with
            | Some c -> c
            | None -> List.hd filtered
          in
          if Hashtbl.mem seen target then []
          else begin
            Hashtbl.add seen target ();
            load target ~from_span:span
          end
      ) refs
  in

  (* Step 1: resolve explicit imports (DUse/DAlias) from the entry file *)
  let explicit_decls = load_refs m.March_ast.Ast.mod_decls in
  (* Mark all explicitly-loaded modules (and their nested transitive deps) as
     already-emitted.  This prevents them from being re-embedded as transitive
     deps inside auto-discovered DMods in step 2.  Without this, every
     submodule that does `import App` would embed the entire App DMod
     inside itself, causing O(N²) typecheck cost. *)
  let rec mark_emitted_decls = function
    | [] -> ()
    | March_ast.Ast.DMod ({March_ast.Ast.txt = mn; _}, _, inner, _) :: rest ->
      Hashtbl.replace resolved mn [];
      mark_emitted_decls inner;
      mark_emitted_decls rest
    | _ :: rest -> mark_emitted_decls rest
  in
  mark_emitted_decls explicit_decls;

  (* Step 2: auto-discover all .march files in the library search path.
     Load any that were not already pulled in via explicit imports.
     Two-phase: parse all files first to learn their module names, then sort
     by module-name depth (more dot-segments = deeper namespace = fewer
     dependents = load first) so dependencies are in env before their users. *)
  let dot_count s =
    String.fold_left (fun n c -> if c = '.' then n + 1 else n) 0 s
  in
  (* Entry source text — the primary reachability seed.  If it cannot be read,
     pruning is disabled (fall back to loading every discovered module) so a
     read failure never silently drops a module the entry needs. *)
  let entry_src = try Some (read_file source_file) with Sys_error _ -> None in
  let auto_decls =
    if not auto_discover then []
    else begin
      (* Phase 1: parse + desugar every un-loaded discovered file across ALL
         lib dirs, keeping its source text for reachability analysis. *)
      let all_parsed =
        List.concat_map (fun (dir_idx, lib_dir) ->
            let files = collect_lib_files lib_dir in
            List.filter_map (fun file_path ->
                let canon_fp =
                  (try Unix.realpath file_path with Unix.Unix_error _ -> file_path) in
                if Hashtbl.mem loaded_paths canon_fp then None
                else
                  let src = try read_file file_path with Sys_error _ -> "" in
                  if src = "" then None
                  else
                    match parse_march_file file_path src with
                    | Error msg ->
                      Printf.eprintf "[lib] %s\n%!" msg; None
                    | Ok ast ->
                      Some (dir_idx, canon_fp, file_path,
                            March_desugar.Desugar.desugar_module ~is_entry:false ast,
                            src)
              ) files
          ) (List.mapi (fun i d -> (i, d)) all_lib_paths)
      in
      (* Reachability pruning.  An auto-discovered library module is only
         built when the entry can actually reach it — directly or transitively,
         by textually referencing its module name — OR when it carries a
         global-effect decl (a typeclass instance, protocol, FFI block, ...)
         that may be used without naming the module.  This keeps one broken,
         UNRELATED library module from failing an entry that never references
         it, while still preventing that module's ill-typed TIR from reaching
         codegen: it is dropped from the program entirely, not merely tolerated
         (the failure mode of the earlier "load everything" design).  A module
         the entry DOES reference stays in the build and still errors.

         References are over-approximated (see [referenced_name_tokens]): the
         only safe error is to KEEP a module, never to wrongly prune one. *)
      let mod_name_of ast = ast.March_ast.Ast.mod_name.March_ast.Ast.txt in
      (* Pruning keys off being able to read the entry source (the primary
         reachability seed).  When it cannot be read — e.g. the REPL/LSP passing
         a synthetic path — fall back to the historical "load everything"
         behavior rather than risk dropping a module the entry needs. *)
      let pruning_enabled = entry_src <> None in
      let reachable : (string, unit) Hashtbl.t = Hashtbl.create 64 in
      if pruning_enabled then begin
        (* For each discovered module: its declared name, the reachability
           anchors that keep it (module name + provided type/ctor names), and
           the module-name tokens its own source references (transitive spread). *)
        let discovered =
          List.map (fun (_, _, _, ast, src) ->
              let mn = mod_name_of ast in
              let anchors = mn :: provided_anchor_names ast.March_ast.Ast.mod_decls in
              (mn, anchors, referenced_name_tokens src))
            all_parsed
        in
        let queue : (string, unit) Hashtbl.t Queue.t = Queue.create () in
        let seed_texts =
          (match entry_src with Some s -> [s] | None -> []) @ !loaded_srcs in
        List.iter (fun t -> Queue.add (referenced_name_tokens t) queue) seed_texts;
        while not (Queue.is_empty queue) do
          let toks = Queue.take queue in
          List.iter (fun (mn, anchors, own_toks) ->
              if not (Hashtbl.mem reachable mn)
                 && List.exists (fun a -> Hashtbl.mem toks a) anchors then begin
                Hashtbl.add reachable mn ();
                Queue.add own_toks queue
              end)
            discovered
        done
      end;
      let keep ast =
        not pruning_enabled
        || Hashtbl.mem reachable (mod_name_of ast)
        || has_global_effect_decl ast.March_ast.Ast.mod_decls
      in
      (* Sort: SEARCH-PATH ORDER first, then more dot-segments in mod name
         (namespace leaves), then alphabetically for determinism.

         The search-path key is what keeps the caller's ordering intent
         intact.  `forge test` places lib/ before test/ on MARCH_LIB_PATH
         precisely because test modules call into lib modules and never the
         reverse: a lib function still bound to its pass-1 Mono placeholder,
         pinned first by a TEST call site, makes every later call site with
         a different record shape fail to unify.  Sorting on the module name
         alone silently undid that — `Forgepm.Test.*` and `Forgepm.Web.*`
         have equal dot-counts, so "Test" sorted ahead of "Web" and the test
         modules were checked first, yielding a wall of `expected () but got
         Unit`.  Within one directory the dot-count rule still applies. *)
      let sorted = List.sort (fun (ia, _, _, a, _) (ib, _, _, b, _) ->
          if ia <> ib then compare ia ib
          else
            let da = dot_count (mod_name_of a) and db = dot_count (mod_name_of b) in
            if db <> da then compare db da
            else compare (mod_name_of a) (mod_name_of b)
        ) all_parsed in
      (* Phase 2: build DMods in sorted order for KEPT modules only.  Emit
         transitive imports as top-level siblings (not nested) to avoid
         name-mangling collisions.  [canon_fp] keys the dedup; [orig_path] is
         the string the file was parsed under (= what its spans carry),
         recorded for user_files.  A pruned module is skipped entirely — never
         noted as a user file, never emitted, never typechecked. *)
      List.concat_map (fun (_dir_idx, canon_fp, orig_path, ast, _src) ->
          if Hashtbl.mem loaded_paths canon_fp then []
          else if not (keep ast) then []
          else begin
            Hashtbl.add loaded_paths canon_fp ();
            note_user_file orig_path canon_fp;
            let mn = mod_name_of ast in
            if Hashtbl.mem resolved mn then []
            else begin
              (* Mark emitted BEFORE load_refs so recursive imports don't
                 re-emit this module inside their own transitive set. *)
              Hashtbl.add resolved mn [];
              let transitive = load_refs ast.March_ast.Ast.mod_decls in
              let self_dmod =
                March_ast.Ast.DMod (ast.March_ast.Ast.mod_name,
                                    March_ast.Ast.Public,
                                    ast.March_ast.Ast.mod_decls,
                                    dummy_span)
              in
              transitive @ [self_dmod]
            end
          end
        ) sorted
    end
  in

  (* Every file loaded here is USER code (the entry file plus modules from
     the source dir / lib path).  Callers use this list to decide which
     typecheck diagnostics are fatal: errors in any of these files must
     abort, while stdlib-internal errors are tolerated (some stdlib modules
     are WIP).  Membership is exact, so [user_files] carries BOTH the
     parse-time path string of each file (what its spans record) and its
     canonical realpath — and is robust against stdlib files whose cached
     spans point at a different install location. *)
  (!errors, explicit_decls @ auto_decls,
   List.sort_uniq String.compare !user_files)
