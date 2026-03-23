(** forge test — discover and run *_test.march files *)

let run () =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    let test_dir = Filename.concat proj.Project.root "test" in
    if not (Sys.file_exists test_dir) then
      Error (Printf.sprintf "no test/ directory found at %s" test_dir)
    else begin
      let test_files =
        Array.to_list (Sys.readdir test_dir)
        |> List.filter_map (fun name ->
            if Filename.check_suffix name "_test.march" then
              Some (Filename.concat test_dir name)
            else None)
      in
      if test_files = [] then begin
        Printf.printf "no test files found in %s\n%!" test_dir;
        Ok ()
      end else begin
        (* Run each test file independently; march executes main() if present *)
        let failed = List.filter (fun f ->
          let rc = Sys.command (Printf.sprintf "march %s" (Filename.quote f)) in
          rc <> 0) test_files in
        if failed = [] then Ok ()
        else
          Error (Printf.sprintf "%d test file(s) failed: %s"
            (List.length failed)
            (String.concat ", " (List.map Filename.basename failed)))
      end
    end
