(** cmd_bastion_new.ml — forge bastion new <name>

    Scaffolds a new Bastion web application.  Thin Cmdliner wrapper around
    [Scaffold_bastion.scaffold]. *)

let run name =
  match Scaffold_bastion.scaffold name with
  | Ok () ->
    Printf.printf "created Bastion app '%s'\n%!" name;
    Printf.printf "  next steps:\n%!";
    Printf.printf "    cd %s\n%!" name;
    Printf.printf "    forge bastion server\n%!";
    Ok ()
  | Error m -> Error m
