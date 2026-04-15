(** forge new <name> [--app|--lib|--tool]: scaffold a new project *)

let write_file path content =
  let oc = open_out path in
  output_string oc content;
  close_out oc

(** Convert snake_case to PascalCase: "test_project" -> "TestProject" *)
let snake_to_pascal s =
  String.split_on_char '_' s
  |> List.filter (fun p -> p <> "")
  |> List.map String.capitalize_ascii
  |> String.concat ""

let forge_toml name project_type =
  Printf.sprintf
    "[package]\nname = \"%s\"\nversion = \"0.1.0\"\ntype = \"%s\"\ndescription = \"\"\nauthor = \"\"\n\n[deps]\n"
    name (Project.project_type_to_string project_type)

let lib_source name = function
  | Project.App ->
    Printf.sprintf "mod %s do\n\n  fn main() do\n    println(\"Hello from %s!\")\n  end\n\nend\n"
      (snake_to_pascal name) name
  | Project.Lib ->
    Printf.sprintf "mod %s do\n\n  fn hello(name: String) : String do\n    \"Hello, \" ++ name ++ \"!\"\n  end\n\nend\n"
      (snake_to_pascal name)
  | Project.Tool ->
    Printf.sprintf "mod %s do\n\n  fn main() do\n    println(\"Hello from %s!\")\n  end\n\nend\n"
      (snake_to_pascal name) name

let test_source name =
  Printf.sprintf "mod %sTest do\n\n  fn test_placeholder() : Bool do\n    true\n  end\n\n  fn main() do\n    let result = test_placeholder()\n    if result then println(\"All tests passed.\") else println(\"Tests failed.\")\n  end\n\nend\n"
    (snake_to_pascal name)

let editorconfig =
  "root = true\n\n\
   [*]\n\
   indent_style = space\n\
   indent_size = 2\n\
   charset = utf-8\n\
   end_of_line = lf\n\
   trim_trailing_whitespace = true\n\
   insert_final_newline = true\n\n\
   [*.march]\n\
   indent_style = space\n\
   indent_size = 2\n"

let gitignore = "/.march/\n"

let readme name =
  Printf.sprintf "# %s\n" (String.capitalize_ascii name)

let scaffold name project_type =
  if Sys.file_exists name then
    Error (Printf.sprintf "directory '%s' already exists" name)
  else
    try
      Unix.mkdir name 0o755;
      Project.mkdir_p (Filename.concat name "lib");
      Project.mkdir_p (Filename.concat name "test");
      write_file (Filename.concat name "forge.toml")
        (forge_toml name project_type);
      write_file (Filename.concat name (Filename.concat "lib" (name ^ ".march")))
        (lib_source name project_type);
      write_file (Filename.concat name (Filename.concat "test" (name ^ "_test.march")))
        (test_source name);
      write_file (Filename.concat name ".editorconfig") editorconfig;
      write_file (Filename.concat name ".gitignore") gitignore;
      write_file (Filename.concat name "README.md") (readme name);
      let _ = Sys.command
          (Printf.sprintf "git init %s > /dev/null 2>&1" (Filename.quote name)) in
      Ok ()
    with
    | Unix.Unix_error (e, fn, arg) ->
      Error (Printf.sprintf "%s: %s %s" fn (Unix.error_message e) arg)
    | Sys_error msg -> Error msg
