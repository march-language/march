(** forge fix — apply definitive auto-fixes emitted by the compiler. *)

type fix_kind =
  | FInsert of { after_line : int; text : string }
  | FDelete of { start_line : int; end_line : int }
  | FReplace of { start_line : int; start_col : int;
                  end_line   : int; end_col   : int; text : string }

type fix_item = {
  fi_file     : string;
  fi_severity : string;
  fi_message  : string;
  fi_fix      : fix_kind;
}

let parse_fix_line line : fix_item option =
  try
    let j = Yojson.Basic.from_string line in
    let open Yojson.Basic.Util in
    let fix_j = j |> member "fix" in
    if fix_j = `Null then None
    else begin
      let file = j |> member "file" |> to_string in
      let sev  = j |> member "severity" |> to_string in
      let msg  = j |> member "message" |> to_string in
      let kind = fix_j |> member "kind" |> to_string in
      let fix = match kind with
        | "insert" ->
          let after_line = fix_j |> member "after_line" |> to_int in
          let text       = fix_j |> member "text"       |> to_string in
          FInsert { after_line; text }
        | "delete" ->
          let start_line = fix_j |> member "start_line" |> to_int in
          let end_line   = fix_j |> member "end_line"   |> to_int in
          FDelete { start_line; end_line }
        | "replace" ->
          let start_line = fix_j |> member "start_line" |> to_int in
          let start_col  = fix_j |> member "start_col"  |> to_int in
          let end_line   = fix_j |> member "end_line"   |> to_int in
          let end_col    = fix_j |> member "end_col"    |> to_int in
          let text       = fix_j |> member "text"       |> to_string in
          FReplace { start_line; start_col; end_line; end_col; text }
        | _ -> raise Exit
      in
      Some { fi_file = file; fi_severity = sev; fi_message = msg; fi_fix = fix }
    end
  with _ -> None

(* [contracts] switches the input from the ordinary diagnostic stream
   (`march --check-json`) to the contract-generation one
   (`march --compile --report-contracts`), which emits the same NDJSON shape
   with an `insert` fix per function verified allocation-free.  [scope_globs]
   comes from forge.toml's `[contracts] no_alloc`. *)
let collect_all_fixes ?(contracts = false) ?(scope_globs = []) ~lib_path_env files
  : fix_item list =
  let all_items = ref [] in
  List.iter (fun file ->
    let cmd =
      if contracts then
        (* --no-cap-strict: this mode writes no binary — it stops before code
           generation — and the capability ceiling exists to gate EMITTED code,
           which the real build still checks.  Without it the command cannot
           run on a library at all: compiling a module with no `main` charges
           that module with the prelude's own `IO.Console` and fails the
           ceiling, so `forge fix --contracts` would report nothing for every
           lib project.  See
           specs/todos/2026-09-03-cap-ceiling-charges-prelude-io-to-mainless-module.md *)
        Printf.sprintf "%smarch --compile --no-cap-strict --report-contracts%s %s 2>/dev/null"
          lib_path_env
          (if scope_globs = [] then ""
           else " --contract-scope " ^ Filename.quote (String.concat "," scope_globs))
          (Filename.quote file)
      else
        Printf.sprintf "%smarch --check-json %s 2>/dev/null"
          lib_path_env (Filename.quote file) in
    let ic = Unix.open_process_in cmd in
    (try
      while true do
        let line = input_line ic in
        (match parse_fix_line line with
         | Some fi -> all_items := fi :: !all_items
         | None -> ())
      done
    with End_of_file -> ());
    ignore (Unix.close_process_in ic)
  ) files;
  !all_items

let read_lines path =
  let ic = open_in path in
  let lines = ref [| "" |] in
  (try
    while true do
      lines := Array.append !lines [| input_line ic |]
    done
  with End_of_file -> ());
  close_in ic;
  !lines

let write_lines path lines =
  let tmp = path ^ ".fix.tmp" in
  let oc = open_out tmp in
  Array.iteri (fun i line ->
    if i > 0 then begin
      output_string oc line;
      if i < Array.length lines - 1 then output_char oc '\n'
    end
  ) lines;
  close_out oc;
  Sys.rename tmp path

let fix_sort_key = function
  | FInsert { after_line; _ }    -> after_line
  | FDelete { end_line; _ }      -> end_line
  | FReplace { start_line; _ }   -> start_line

let dedup_fixes items =
  let seen = Hashtbl.create 16 in
  List.filter (fun fi ->
    let key = match fi.fi_fix with
      | FInsert { after_line; text }     -> Printf.sprintf "I:%d:%s" after_line text
      | FDelete { start_line; end_line } -> Printf.sprintf "D:%d:%d" start_line end_line
      | FReplace { start_line; start_col; text; _ } ->
        Printf.sprintf "R:%d:%d:%s" start_line start_col text
    in
    if Hashtbl.mem seen key then false
    else (Hashtbl.add seen key (); true)
  ) items

let describe_fix path fi =
  match fi.fi_fix with
  | FInsert { after_line; text } ->
    Printf.printf "  insert after line %d: %s\n" after_line text
  | FDelete { start_line; end_line } ->
    if start_line = end_line then
      Printf.printf "  delete line %d\n" start_line
    else
      Printf.printf "  delete lines %d-%d\n" start_line end_line
  | FReplace { start_line; start_col; end_col; text; _ } ->
    Printf.printf "  replace %s:%d:%d-%d with: %s\n" path start_line start_col end_col text

let apply_fixes_to_file path items dry_run =
  let deduped = dedup_fixes items in
  let sorted  = List.sort (fun a b ->
    compare (fix_sort_key b.fi_fix) (fix_sort_key a.fi_fix)
  ) deduped in
  if sorted = [] then 0
  else if dry_run then begin
    Printf.printf "would fix %s:\n" path;
    List.iter (describe_fix path) (List.rev sorted);
    List.length sorted
  end else begin
    let lines = read_lines path in
    let lines_ref = ref lines in
    let count = ref 0 in
    List.iter (fun fi ->
      let ls = !lines_ref in
      let n  = Array.length ls - 1 in
      (match fi.fi_fix with
       | FInsert { after_line; text } when after_line >= 1 && after_line <= n ->
         let before = Array.sub ls 0 (after_line + 1) in
         let after  = Array.sub ls (after_line + 1) (Array.length ls - after_line - 1) in
         lines_ref := Array.concat [ before; [| text |]; after ];
         incr count
       | FDelete { start_line; end_line }
         when start_line >= 1 && end_line <= n && start_line <= end_line ->
         let before = Array.sub ls 0 start_line in
         let after  = Array.sub ls (end_line + 1)
                       (Array.length ls - end_line - 1) in
         lines_ref := Array.concat [ before; after ];
         incr count
       | FReplace { start_line; start_col; end_line; end_col; text }
         when start_line >= 1 && start_line <= n ->
         if start_line = end_line then begin
           let orig = ls.(start_line) in
           let safe_col c = max 0 (min c (String.length orig)) in
           let sc = safe_col start_col and ec = safe_col end_col in
           let new_line =
             String.sub orig 0 sc ^ text ^ String.sub orig ec (String.length orig - ec)
           in
           let new_lines = Array.copy ls in
           new_lines.(start_line) <- new_line;
           lines_ref := new_lines;
           incr count
         end
       | _ -> ()
      )
    ) sorted;
    write_lines path !lines_ref;
    !count
  end

let run ?(dry_run = false) ?(contracts = false) () =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    let lib_dir   = Filename.concat proj.Project.root "lib" in
    let files     = Cmd_build.find_march_files lib_dir in
    let all_files =
      match proj.Project.project_type with
      | Project.Lib -> files
      | Project.App | Project.Tool ->
        let entry_path = match proj.Project.entrypoint with
          | Some ep -> Filename.concat proj.Project.root ep
          | None    -> Filename.concat lib_dir (proj.Project.name ^ ".march")
        in
        let entry_abs = try Unix.realpath entry_path with _ -> entry_path in
        let already   = List.exists (fun f ->
          (try Unix.realpath f with _ -> f) = entry_abs) files in
        if already then files else entry_path :: files
    in
    if all_files = [] then Error (Printf.sprintf "no .march files found in %s" lib_dir)
    else begin
      let lib_path_env = Cmd_build.lib_path_env proj in
      let items =
        collect_all_fixes ~contracts
          ~scope_globs:(if contracts then proj.Project.contracts_no_alloc else [])
          ~lib_path_env all_files in
      let root = proj.Project.root in
        let owned = List.filter (fun fi ->
          let abs      = try Unix.realpath fi.fi_file with _ -> fi.fi_file in
          let abs_root = try Unix.realpath root       with _ -> root in
          let n = String.length abs_root in
          String.length abs >= n && String.sub abs 0 n = abs_root
        ) items in
        let by_file : (string, fix_item list) Hashtbl.t = Hashtbl.create 8 in
        List.iter (fun fi ->
          let cur = try Hashtbl.find by_file fi.fi_file with Not_found -> [] in
          Hashtbl.replace by_file fi.fi_file (fi :: cur)
        ) owned;
        let total_fixes = ref 0 in
        let total_files = ref 0 in
        Hashtbl.iter (fun path file_items ->
          let n = apply_fixes_to_file path file_items dry_run in
          if n > 0 then begin
            incr total_files;
            total_fixes := !total_fixes + n;
            if not dry_run then
              Printf.printf "fixed %s (%d change%s)\n" path n
                (if n = 1 then "" else "s")
          end
        ) by_file;
        if !total_fixes = 0 then
          Ok (if contracts then "no allocation contracts to add"
              else "no auto-fixable diagnostics found")
        else
          Ok (Printf.sprintf "%d file%s changed, %d fix%s applied%s"
            !total_files (if !total_files = 1 then "" else "s")
            !total_fixes (if !total_fixes = 1 then "" else "es")
            (if dry_run then " (dry run — no files written)" else ""))
    end
