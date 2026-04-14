(** forge add — add a dependency to forge.toml

    Usage:
      forge add <name> --git <url> [--tag v1.0 | --branch main | --rev abc123]
      forge add <name> --path ../local-lib
      forge add <name>                          (registry dep, placeholder)

    Textually appends to the [deps] (or [dev-deps]) section, preserving
    existing comments and formatting.  Then runs `forge deps` to resolve. *)

(* ------------------------------------------------------------------ *)
(*  Serialize a dep to an inline TOML table                           *)
(* ------------------------------------------------------------------ *)

let dep_to_inline_toml (dep : Project.dep) =
  match dep with
  | RegistryDep { version } ->
    Printf.sprintf "{ registry = \"forge\", version = \"%s\" }" version
  | GitTagDep { url; tag } ->
    Printf.sprintf "{ git = \"%s\", tag = \"%s\" }" url tag
  | GitBranchDep { url; branch } ->
    Printf.sprintf "{ git = \"%s\", branch = \"%s\" }" url branch
  | GitRevDep { url; rev } ->
    Printf.sprintf "{ git = \"%s\", rev = \"%s\" }" url rev
  | PathDep path ->
    Printf.sprintf "{ path = \"%s\" }" path

(* ------------------------------------------------------------------ *)
(*  Find or create a [deps] / [dev-deps] section and append the entry *)
(* ------------------------------------------------------------------ *)

(** Insert a dep line into the raw toml text.  Finds the target section
    header and appends the line after the last non-blank line in that
    section (before the next section header or EOF). *)
let insert_dep_line text ~section ~name ~dep =
  let line = Printf.sprintf "%s = %s" name (dep_to_inline_toml dep) in
  let lines = String.split_on_char '\n' text in
  let section_header = Printf.sprintf "[%s]" section in
  (* Find the section, insert after its last key *)
  let rec scan acc in_section = function
    | [] ->
      if in_section then
        (* Section was the last thing in the file — just append *)
        List.rev (line :: acc)
      else
        (* Section not found — append it at end *)
        List.rev acc @ [""; section_header; line]
    | hd :: tl ->
      let trimmed = String.trim hd in
      if in_section then begin
        (* Check if we hit the next section header *)
        if String.length trimmed >= 1 && trimmed.[0] = '[' then
          (* Insert before this header *)
          List.rev (hd :: "" :: line :: acc) @ tl
        else
          scan (hd :: acc) true tl
      end else begin
        if trimmed = section_header then
          scan (hd :: acc) true tl
        else
          scan (hd :: acc) false tl
      end
  in
  String.concat "\n" (scan [] false lines)

(* ------------------------------------------------------------------ *)
(*  Main command                                                       *)
(* ------------------------------------------------------------------ *)

let run ~name ~git ~tag ~branch ~rev ~path ~dev ~force () =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    (* Build the dep value from flags *)
    let dep_result = match git, path with
      | Some url, _ ->
        (match tag, branch, rev with
         | Some t, _, _ -> Ok (Project.GitTagDep { url; tag = t })
         | _, Some b, _ -> Ok (Project.GitBranchDep { url; branch = b })
         | _, _, Some r -> Ok (Project.GitRevDep { url; rev = r })
         | None, None, None ->
           Ok (Project.GitBranchDep { url; branch = "main" }))
      | None, Some p -> Ok (Project.PathDep p)
      | None, None ->
        Ok (Project.RegistryDep { version = "*" })
    in
    match dep_result with
    | Error msg -> Error msg
    | Ok dep ->
      let section = if dev then "dev-deps" else "deps" in
      let existing = if dev then proj.Project.dev_deps else proj.Project.deps in
      (* Check for duplicates *)
      if List.mem_assoc name existing && not force then
        Error (Printf.sprintf
          "dependency '%s' already exists in [%s] (use --force to overwrite)"
          name section)
      else begin
        (* Read the raw toml, insert the new dep line *)
        let toml_path = Filename.concat proj.Project.root "forge.toml" in
        let text = Project.read_file toml_path in
        let text' = insert_dep_line text ~section ~name ~dep in
        let oc = open_out toml_path in
        output_string oc text';
        close_out oc;
        Printf.printf "added %s to [%s]: %s\n%!" name section (dep_to_inline_toml dep);
        (* Run deps to install *)
        Printf.printf "resolving dependencies...\n%!";
        match Cmd_deps.run () with
        | Ok ()  ->
          Printf.printf "done.\n%!";
          Ok ()
        | Error msg ->
          Printf.eprintf "warning: dep resolution failed: %s\n%!" msg;
          Printf.printf "the entry was added to forge.toml — run `forge deps` to retry.\n%!";
          Ok ()
      end
