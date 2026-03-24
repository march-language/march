(** forge init — create a forge.toml in the current directory *)

let run () =
  let path = Filename.concat (Sys.getcwd ()) "forge.toml" in
  if Sys.file_exists path then begin
    Printf.printf "forge.toml already exists\n%!";
    Ok ()
  end else begin
    let name = Filename.basename (Sys.getcwd ()) in
    let content = Printf.sprintf
      "[package]\nname = \"%s\"\nversion = \"0.1.0\"\ntype = \"app\"\ndescription = \"\"\nauthor = \"\"\n\n[deps]\n"
      name
    in
    let oc = open_out path in
    output_string oc content;
    close_out oc;
    Printf.printf "created forge.toml\n%!";
    Ok ()
  end
