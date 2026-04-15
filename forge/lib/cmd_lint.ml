(** forge lint — run the March coding-standard rule engine *)

module Lint = March_lint.Lint

(* ------------------------------------------------------------------ *)
(* Config loading (.march-lint.toml)                                  *)
(* ------------------------------------------------------------------ *)

let parse_rule_severity = function
  | "error"   -> Some Lint.RSError
  | "warning" -> Some Lint.RSWarning
  | "hint"    -> Some Lint.RSHint
  | "off"     -> Some Lint.RSOff
  | _         -> None

(** Load .march-lint.toml from [path], merging with defaults.
    Unknown severity strings are silently ignored. *)
let load_config path =
  let cfg = Lint.default_config () in
  (match
     (try Some (
         let ic = open_in path in
         let n  = in_channel_length ic in
         let s  = Bytes.create n in
         really_input ic s 0 n;
         close_in ic;
         Bytes.to_string s)
      with Sys_error _ -> None)
   with
   | None -> ()
   | Some text ->
     let doc = Toml.parse text in
     (match List.assoc_opt "rules" doc.Toml.sections with
      | None -> ()
      | Some pairs ->
        List.iter (fun (key, value) ->
            match value with
            | Toml.Str v ->
              (match parse_rule_severity v with
               | Some sev -> Hashtbl.replace cfg.Lint.rules key sev
               | None     ->
                 Printf.eprintf
                   "forge lint: unknown severity %S for rule %S in .march-lint.toml\n%!"
                   v key)
            | _ -> ()
          ) pairs));
  cfg

(* ------------------------------------------------------------------ *)
(* File discovery                                                      *)
(* ------------------------------------------------------------------ *)

let rec collect_march_files dir =
  if not (Sys.file_exists dir) then []
  else
    Array.to_list (Sys.readdir dir)
    |> List.concat_map (fun name ->
        let path = Filename.concat dir name in
        if Sys.is_directory path then collect_march_files path
        else if Filename.check_suffix name ".march" then [path]
        else [])

(* ------------------------------------------------------------------ *)
(* Output formatting                                                   *)
(* ------------------------------------------------------------------ *)

let severity_label = function
  | Lint.Error   -> "error"
  | Lint.Warning -> "warning"
  | Lint.Hint    -> "hint"

(** Format one diagnostic as a human-readable line. *)
let format_diag (d : Lint.diagnostic) =
  Printf.sprintf "%s:%d:%d: %s [%s] %s"
    d.Lint.file
    d.Lint.line
    d.Lint.col
    (severity_label d.Lint.severity)
    d.Lint.rule
    d.Lint.message

(* ------------------------------------------------------------------ *)
(* Main run function                                                   *)
(* ------------------------------------------------------------------ *)

let run ?(strict = false) ?(all = false) () =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    let root = proj.Project.root in

    (* Load config *)
    let toml_path = Filename.concat root ".march-lint.toml" in
    let config    = load_config toml_path in

    (* Discover files *)
    let dirs  = [
      Filename.concat root "lib";
      Filename.concat root "test";
    ] in
    let files = List.concat_map collect_march_files dirs in

    if files = [] then begin
      Printf.printf "forge lint: no .march files found\n%!";
      Ok ()
    end else begin
      let all_diags = ref [] in

      List.iter (fun path ->
          let src =
            let ic = open_in path in
            let n  = in_channel_length ic in
            let s  = Bytes.create n in
            really_input ic s 0 n;
            close_in ic;
            Bytes.to_string s
          in
          let diags = Lint.check_file ~config ~filename:path ~src in
          all_diags := diags @ !all_diags
        ) files;

      (* Sort by file then line *)
      let sorted = List.sort (fun a b ->
          let c = String.compare a.Lint.file b.Lint.file in
          if c <> 0 then c
          else
            let c2 = compare a.Lint.line b.Lint.line in
            if c2 <> 0 then c2 else compare a.Lint.col b.Lint.col
        ) !all_diags in

      (* Apply --strict: promote warnings to errors *)
      let sorted =
        if strict then
          List.map (fun d ->
              if d.Lint.severity = Lint.Warning
              then { d with Lint.severity = Lint.Error }
              else d
            ) sorted
        else sorted
      in

      (* Filter by visibility: default = errors + warnings; --all = also hints *)
      let visible = List.filter (fun d ->
          match d.Lint.severity with
          | Lint.Error   -> true
          | Lint.Warning -> true
          | Lint.Hint    -> all
        ) sorted in

      (* Print *)
      List.iter (fun d -> print_endline (format_diag d)) visible;

      (* Summary line *)
      let errors   = List.length (List.filter (fun d -> d.Lint.severity = Lint.Error)   visible) in
      let warnings = List.length (List.filter (fun d -> d.Lint.severity = Lint.Warning) visible) in
      let hints    = List.length (List.filter (fun d -> d.Lint.severity = Lint.Hint)    visible) in
      if errors + warnings + hints > 0 then begin
        let parts = List.filter_map (fun (n, label) ->
            if n > 0 then Some (Printf.sprintf "%d %s" n label) else None
          ) [(errors, "error(s)"); (warnings, "warning(s)"); (hints, "hint(s)")] in
        Printf.printf "\n%s\n%!" (String.concat ", " parts)
      end else
        Printf.printf "no issues found\n%!";

      (* Exit code: 1 if any errors *)
      if errors > 0
      then Error "lint found errors"
      else Ok ()
    end
