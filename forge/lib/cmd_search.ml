(** forge search [QUERY] [--type TYPE] [--doc KEYWORDS] [--limit N] [--json]

    Hoogle-style search across March stdlib and project dependencies.
    Searches function names, type signatures, and doc strings. *)

module Search = March_search.Search

(* ------------------------------------------------------------------ *)
(* Index cache                                                         *)
(* ------------------------------------------------------------------ *)

let index_cache_path root =
  Filename.concat root (Filename.concat ".march" "search-index.json")

(** Load cached index if it exists, otherwise build from stdlib. *)
let load_or_build_index ~verbose root =
  let cache = index_cache_path root in
  if Sys.file_exists cache then begin
    (if verbose then
       Printf.eprintf "forge search: loading index from %s\n%!" cache);
    let ic = open_in cache in
    let n  = in_channel_length ic in
    let buf = Bytes.create n in
    really_input ic buf 0 n;
    close_in ic;
    (try Ok (Search.index_from_json (Bytes.to_string buf))
     with Failure msg ->
       Error (Printf.sprintf "failed to parse search index: %s" msg))
  end else begin
    (if verbose then
       Printf.eprintf "forge search: building index from stdlib...\n%!");
    let idx = Search.build_stdlib_index () in
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

let print_results ~as_json ~pretty ~limit results =
  let results = if limit > 0 then
    let rec take n = function
      | [] -> []
      | _ when n = 0 -> []
      | x :: xs -> x :: take (n - 1) xs
    in
    take limit results
  else results
  in
  if as_json then begin
    let entries = List.map fst results in
    let j : Yojson.Basic.t = `List
        (List.map Search.entry_to_json entries)
    in
    print_string (Yojson.Basic.pretty_to_string j);
    print_newline ()
  end else if pretty then
    Search.format_results_pretty results
  else begin
    if results = [] then
      print_endline "no results found"
    else
      List.iter (fun (entry, _score) ->
        print_endline (Search.format_entry entry);
        print_newline ()
      ) results
  end

(* ------------------------------------------------------------------ *)
(* Command                                                             *)
(* ------------------------------------------------------------------ *)

let run ~query ~type_sig ~doc_query ~limit ~as_json ~pretty ~rebuild () =
  let root = match Project.load () with
    | Ok p  -> p.Project.root
    | Error _ -> Filename.current_dir_name
  in
  (if rebuild then begin
     let cache = index_cache_path root in
     if Sys.file_exists cache then Sys.remove cache
   end);
  match load_or_build_index ~verbose:false root with
  | Error msg -> Printf.eprintf "error: %s\n%!" msg; exit 1
  | Ok idx ->
    let name_q     = if String.length query    > 0 then Some query    else None in
    let type_q     = if String.length type_sig > 0 then Some type_sig else None in
    let doc_q      = if String.length doc_query > 0 then Some doc_query else None in
    let results =
      if name_q = None && type_q = None && doc_q = None then
        (* No query — print a summary *)
        (Printf.printf "index contains %d entries (stdlib)\n%!"
           (List.length idx.Search.entries);
         [])
      else
        Search.search_combined idx ?name:name_q ?type_sig:type_q ?doc_query:doc_q ()
    in
    print_results ~as_json ~pretty ~limit results
