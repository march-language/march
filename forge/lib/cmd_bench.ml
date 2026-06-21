(** forge bench [<name>] — compile and run benchmarks under bench/.

    Each `bench/*.march` (a standalone program with `main()`) is a benchmark,
    named by its filename stem. Built at --opt 2 (release) through the resolved
    toolchain, run, and timed. Output is a table or `--json` for CI tracking. *)

(* --- pure helpers (unit-tested) --- *)

let bench_name path = Filename.remove_extension (Filename.basename path)

let matches ~filter name =
  filter = "" ||
  (let nl = String.length name and fl = String.length filter in
   let rec at i = i + fl <= nl && (String.sub name i fl = filter || at (i + 1)) in
   at 0)

(* [results] are (name, seconds, ok). *)
let format_results results ~json =
  if json then
    let item (n, s, ok) =
      Printf.sprintf "  {\"name\": %S, \"seconds\": %.6f, \"ok\": %b}" n s ok
    in
    "[\n" ^ String.concat ",\n" (List.map item results) ^ "\n]"
  else
    let row (n, s, ok) =
      if ok then Printf.sprintf "  %-28s %.3fs" n s
      else Printf.sprintf "  %-28s FAILED" n
    in
    String.concat "\n" (List.map row results)

(* --- runner --- *)

let discover root =
  let dir = Filename.concat root "bench" in
  if not (Sys.file_exists dir) then []
  else
    Sys.readdir dir |> Array.to_list
    |> List.filter (fun f -> Filename.check_suffix f ".march")
    |> List.sort compare
    |> List.map (fun f -> (bench_name f, Filename.concat dir f))

let run ?(filter = "") ?(json = false) () =
  match Project.load () with
  | Error e -> Error e
  | Ok proj ->
    let benches =
      discover proj.Project.root |> List.filter (fun (n, _) -> matches ~filter n)
    in
    if benches = [] then
      (Printf.printf "no benchmarks found in bench/%s\n%!"
         (if filter = "" then "" else Printf.sprintf " matching %S" filter); Ok ())
    else begin
      let lib_path_env = Cmd_build.lib_path_env proj in
      let out_dir = Filename.concat proj.Project.root ".march/bench" in
      Project.mkdir_p out_dir;
      let results =
        List.map (fun (name, path) ->
          let bin = Filename.concat out_dir name in
          Printf.eprintf "  compiling %s ...\n%!" name;
          let crc =
            Cmd_build.compile_entry ~lib_path_env ~ffi_flags:"" ~output:bin ~release:true ~dump_phases:false path
          in
          if crc <> 0 then (name, 0.0, false)
          else begin
            let t0 = Unix.gettimeofday () in
            let rrc = Sys.command (Filename.quote bin) in
            (name, Unix.gettimeofday () -. t0, rrc = 0)
          end)
          benches
      in
      print_string (format_results results ~json);
      print_newline ();
      if List.for_all (fun (_, _, ok) -> ok) results then Ok ()
      else Error "some benchmarks failed"
    end
