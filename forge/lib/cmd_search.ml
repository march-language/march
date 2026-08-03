(** forge search [QUERY] [--type TYPE] [--doc KEYWORDS] [--callers NAME] [--limit N] [--json]

    Hoogle-style search across March stdlib and project dependencies.
    Searches function names, type signatures, and doc strings. *)

module Search = March_search.Search

(* ------------------------------------------------------------------ *)
(* Dependency source directories                                       *)
(* ------------------------------------------------------------------ *)

(** Collect every directory (including nested subdirs) under [dir]. *)
let rec collect_dirs acc dir =
  match Sys.is_directory dir with
  | exception Sys_error _ -> acc
  | false -> acc
  | true ->
    let children =
      try Sys.readdir dir |> Array.to_list
          |> List.map (Filename.concat dir)
          |> List.sort String.compare
      with Sys_error _ -> []
    in
    List.fold_left collect_dirs (dir :: acc) children

(** All source directories contributed by project dependencies. *)
let dep_source_dirs ~root (all_deps : (string * Project.dep) list) =
  let dep_dirs (name, dep) =
    match dep with
    | Project.PathDep rel ->
      let abs = if Filename.is_relative rel
        then Filename.concat root rel
        else rel
      in
      let lib = Filename.concat abs "lib" in
      if Sys.file_exists lib then collect_dirs [] lib
      else if Sys.file_exists abs then collect_dirs [] abs
      else []
    | Project.GitTagDep _ | Project.GitBranchDep _ | Project.GitRevDep _ ->
      (match Project.git_dep_lib_path name with
       | Some p -> collect_dirs [] p
       | None -> [])
    | _ -> []
  in
  List.concat_map dep_dirs all_deps

(* ------------------------------------------------------------------ *)
(* Index cache                                                         *)
(* ------------------------------------------------------------------ *)

let index_cache_path root =
  Filename.concat root (Filename.concat ".march" "search-index.json")

(** Build a combined index from stdlib + project dep sources. *)
let build_combined_index ~root all_deps =
  let stdlib_idx = Search.build_stdlib_index () in
  let dirs = dep_source_dirs ~root all_deps in
  if dirs = [] then stdlib_idx
  else Search.merge_indices stdlib_idx (Search.build_index_from_dirs dirs)

(** Load cached index if it exists AND matches the current on-disk cache
    shape, otherwise (re)build from stdlib + deps. A version mismatch — e.g.
    a cache written before [Search.current_index_version] was bumped for the
    [references] table this feature added — is treated exactly like a cache
    miss: without this check, a pre-existing cache would be loaded as-is
    forever (missing [references] entirely, since [Search.index_from_json]
    defaults an absent field to an empty table) and `--callers` would
    silently report "no references found" for everyone with an existing
    cache, never rebuilding on its own. *)
let load_or_build_index ~verbose ~root all_deps =
  let cache = index_cache_path root in
  let load_cached () =
    let ic = open_in cache in
    let n  = in_channel_length ic in
    let buf = Bytes.create n in
    really_input ic buf 0 n;
    close_in ic;
    (try Ok (Search.index_from_json (Bytes.to_string buf))
     with Failure msg ->
       Error (Printf.sprintf "failed to parse search index: %s" msg))
  in
  let cached_and_fresh =
    if not (Sys.file_exists cache) then None
    else match load_cached () with
      | Ok idx when idx.Search.version = Search.current_index_version -> Some (Ok idx)
      | Ok _ ->
        (if verbose then
           Printf.eprintf
             "forge search: cached index at %s is stale (version mismatch), rebuilding...\n%!"
             cache);
        None
      | Error _ as e -> Some e (* corrupt cache: surface the parse error, don't silently rebuild over it *)
  in
  match cached_and_fresh with
  | Some result ->
    (if verbose then
       Printf.eprintf "forge search: loading index from %s\n%!" cache);
    result
  | None -> begin
    (if verbose then
       Printf.eprintf "forge search: building index from stdlib and deps...\n%!");
    let idx = build_combined_index ~root all_deps in
    (* Save for future use *)
    (try
       Project.mkdir_p (Filename.dirname cache);
       let oc = open_out cache in
       output_string oc (Search.index_to_json idx);
       close_out oc;
       (if verbose then
          Printf.eprintf "forge search: saved index (%d entries) to %s\n%!"
            (List.length idx.Search.entries) cache)
     with Sys_error _ -> ());
    Ok idx
  end

(* ------------------------------------------------------------------ *)
(* Output                                                              *)
(* ------------------------------------------------------------------ *)

let take n xs =
  let rec go n = function
    | [] -> []
    | _ when n = 0 -> []
    | x :: rest -> x :: go (n - 1) rest
  in
  if n > 0 then go n xs else xs

let print_results ~as_json ~plain ~limit results =
  let results = take limit results in
  if as_json then begin
    let j : Yojson.Basic.t =
      `List (List.map (fun (e, _) -> Search.entry_to_json e) results)
    in
    print_string (Yojson.Basic.pretty_to_string j);
    print_newline ()
  end else if plain || not (Unix.isatty Unix.stdout) then
    Search.format_results_plain results
  else
    Search.format_results_colored results

(* ------------------------------------------------------------------ *)
(* Command                                                             *)
(* ------------------------------------------------------------------ *)

let run ~query ~type_sig ~doc_query ~callers ~limit ~as_json ~plain ~rebuild () =
  let (root, all_deps) = match Project.load () with
    | Ok p  ->
      let deps = p.Project.deps @ p.Project.dev_deps @ p.Project.dev_only_deps in
      (p.Project.root, deps)
    | Error _ -> (Filename.current_dir_name, [])
  in
  (if rebuild then begin
     let cache = index_cache_path root in
     if Sys.file_exists cache then Sys.remove cache
   end);
  match load_or_build_index ~verbose:false ~root all_deps with
  | Error msg -> Printf.eprintf "error: %s\n%!" msg; exit 1
  | Ok idx ->
    if String.length callers > 0 then begin
      let refs = take limit (Search.search_callers idx callers) in
      if as_json then begin
        let j : Yojson.Basic.t = `List (List.map Search.ref_entry_to_json refs) in
        print_string (Yojson.Basic.pretty_to_string j); print_newline ()
      end else if plain || not (Unix.isatty Unix.stdout) then
        Search.format_references_plain refs
      else
        Search.format_references_colored refs
    end else begin
      let name_q     = if String.length query    > 0 then Some query    else None in
      let type_q     = if String.length type_sig > 0 then Some type_sig else None in
      let doc_q      = if String.length doc_query > 0 then Some doc_query else None in
      (match type_q with
       | Some q ->
         (match Search.parse_type_query q with
          | Error msg -> Printf.eprintf "error: %s\n%!" msg; exit 1
          | Ok _ -> ())
       | None -> ());
      let results =
        if name_q = None && type_q = None && doc_q = None then
          (* No query — print a summary *)
          (Printf.printf "index contains %d entries (stdlib + deps)\n%!"
             (List.length idx.Search.entries);
           [])
        else
          Search.search_combined idx ?name:name_q ?type_sig:type_q ?doc_query:doc_q ()
      in
      print_results ~as_json ~plain ~limit results
    end
