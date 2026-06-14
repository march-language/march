(** Shell completion scripts and external-subcommand discovery for forge. *)

(** Generate a shell completion script for forge.

    [shell] is one of ["bash"], ["zsh"], or ["fish"].
    [subcommands] is the list of built-in command names to complete. *)
let completion_script ~shell ~subcommands =
  let names = String.concat " " subcommands in
  match shell with
  | "bash" ->
    Printf.sprintf
      "# bash completion for forge\n\
       _forge_completions() {\n\
         local cur=\"${COMP_WORDS[COMP_CWORD]}\"\n\
         COMPREPLY=($(compgen -W \"%s\" -- \"${cur}\"))\n\
       }\n\
       complete -F _forge_completions forge\n"
      names
  | "zsh" ->
    Printf.sprintf
      "#compdef forge\n\
       _forge() {\n\
         local -a cmds\n\
         cmds=(%s)\n\
         _describe 'command' cmds\n\
       }\n\
       _forge \"$@\"\n"
      names
  | "fish" ->
    List.map
      (fun cmd -> Printf.sprintf "complete -c forge -f -a '%s'\n" cmd)
      subcommands
    |> String.concat ""
  | unknown ->
    Printf.sprintf "# unsupported shell: %s\n" unknown

(** Look up an external forge subcommand.

    Returns [Some path] when [argv1] is not in [known] and
    [path_lookup ("forge-" ^ argv1)] returns a non-None path.
    Returns [None] if [argv1] is a built-in (built-ins always win) or if no
    [forge-<argv1>] binary is found. *)
let external_subcommand ~known ~argv1 ~path_lookup =
  if List.mem argv1 known then None
  else path_lookup ("forge-" ^ argv1)
