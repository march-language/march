(** forge doc — delegates to the march_doc archive task.

    The real implementation lives in march_doc/forge/doc.march.
    This shim finds the march_doc archive and invokes its task via the
    standard archive task mechanism, passing CLI flags as FORGE_TASK_ARGS. *)

(* ------------------------------------------------------------------ *)
(* Locate march_doc archive                                            *)
(* ------------------------------------------------------------------ *)

(** Find the march_doc archive root.  Checks:
    1. "march_doc" relative to cwd (for development)
    2. Global archive store *)
let find_march_doc_root () =
  let home = try Sys.getenv "HOME" with Not_found -> "" in
  let candidates = [
    "march_doc";
    Filename.concat (Filename.dirname (Sys.getcwd ())) "march_doc";
    Filename.concat home "code/march_doc";
  ] in
  let from_candidates =
    List.find_opt (fun d ->
        Sys.file_exists (Filename.concat d "forge.toml"))
      candidates
  in
  match from_candidates with
  | Some d -> Some d
  | None ->
    (* Fall back to global archive store *)
    let entries = Archive_store.load_registry () in
    (match List.assoc_opt "march_doc" entries with
     | None -> None
     | Some entry ->
       let root = match entry.Archive_store.source with
         | Archive_store.Path p -> p
         | _ -> Archive_store.archive_dir "march_doc"
       in
       if Sys.file_exists (Filename.concat root "forge.toml")
       then Some root
       else None)

(* ------------------------------------------------------------------ *)
(* Command                                                             *)
(* ------------------------------------------------------------------ *)

let run ?(output_dir = "doc") ?(include_private = false) ?(stdlib_only = false) () =
  match find_march_doc_root () with
  | None ->
    Error "march_doc archive not found. Install it with: forge install march_doc"
  | Some root ->
    (* Build args list matching what the task expects *)
    let args =
      ["-o"; output_dir]
      @ (if include_private then ["--private"] else [])
      @ (if stdlib_only then ["--stdlib"] else [])
    in
    let task_file = Filename.concat root "forge/doc.march" in
    let lib_paths = Archive_store.lib_paths_for_root root in
    let rc = Archive_store.run_task task_file lib_paths args in
    if rc = 0 then Ok ()
    else Error (Printf.sprintf "march_doc.doc exited with code %d" rc)
