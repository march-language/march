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
        let files_str = String.concat " " (List.map Filename.quote test_files) in
        let cmd = Printf.sprintf "march --test %s" files_str in
        let rc  = Sys.command cmd in
        if rc = 0 then Ok ()
        else Error (Printf.sprintf "tests exited with code %d" rc)
      end
    end
