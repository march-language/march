(** forge test — discover and run test files via `march test` *)

let run ?(verbose=false) ?(filter="") () =
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
            if (String.length name > 5 && String.sub name 0 5 = "test_"
                && Filename.check_suffix name ".march")
            || Filename.check_suffix name "_test.march"
            then Some (Filename.concat test_dir name)
            else None)
      in
      if test_files = [] then begin
        Printf.printf "no test files found in %s\n%!" test_dir;
        Ok ()
      end else begin
        (* Delegate to `march test` which handles dot/verbose output,
           assertions, setup/setup_all, and filter support. *)
        let verbose_flag = if verbose then " --verbose" else "" in
        let filter_flag  = if filter = "" then ""
                           else Printf.sprintf " --filter=%s" (Filename.quote filter) in
        let files = String.concat " " (List.map Filename.quote test_files) in
        let cmd = Printf.sprintf "march test%s%s %s" verbose_flag filter_flag files in
        let rc = Sys.command cmd in
        if rc = 0 then Ok ()
        else Error (Printf.sprintf "test run failed (exit %d)" rc)
      end
    end
