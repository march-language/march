(** forge refine — suggest a refinement type for a function.

    Given a function whose body leaves refinement obligations unproven (an
    argument to a callee with a declared precondition, say), propose the
    PARAMETER refinement that discharges them:

    {v
      $ forge refine split
      lib/text.march
        split (line 10)
            n : Int  ->  n : {Int | _ > 0}
          discharges all 1 unproven obligation(s)
    v}

    The inference lives in [March_refinecheck.Precond_infer] and runs inside the
    compiler (`march --refine-suggest`), because it needs the whole checked
    module — stdlib included — to know what the callees actually require.  This
    file is the project-level front end: it decides which files to ask about,
    renders the answer, and (under [--apply]) edits the annotation in place.

    Why shell out rather than link the checker: the pipeline that produces a
    checkable module (stdlib load, import resolution, typecheck) lives in
    bin/main.ml, not in a library.  `forge check` already drives `march check`
    the same way; duplicating that pipeline inside forge is how the two would
    drift. *)

module P = Project

(* ── Running the compiler ─────────────────────────────────────────────────── *)

let run_capturing_stdout cmd : int * string =
  let tmp = Filename.temp_file "forge_refine" ".json" in
  let rc = Sys.command (Printf.sprintf "%s >%s 2>/dev/null" cmd (Filename.quote tmp)) in
  let content =
    try
      let ic = open_in tmp in
      let n = in_channel_length ic in
      let s = Bytes.create n in
      really_input ic s 0 n;
      close_in ic;
      Bytes.to_string s
    with Sys_error _ -> ""
  in
  (try Sys.remove tmp with Sys_error _ -> ());
  (rc, content)

(* ── The compiler's JSON, as a record ─────────────────────────────────────── *)

type suggestion = {
  sg_param : string;
  sg_base : string;
  sg_pred : string;
  sg_annotation : string;   (* "{Int | _ > 0}" — what --apply writes *)
}

type fn_result = {
  rs_fn : string;
  rs_file : string;
  rs_line : int;
  rs_status : string;       (* solved | partial | no-debt | no-candidate | not-found *)
  rs_debt_before : int;
  rs_debt_after : int;
  rs_suggestions : suggestion list;
}

let parse_results (json : string) : fn_result list =
  match Yojson.Safe.from_string json with
  | exception _ -> []
  | j ->
    let member k o = try List.assoc k o with Not_found -> `Null in
    let str = function `String s -> s | _ -> "" in
    let int = function `Int n -> n | _ -> 0 in
    (match j with
     | `Assoc top ->
       (match member "suggestions" top with
        | `List rs ->
          List.filter_map
            (function
              | `Assoc r ->
                let sugs =
                  match member "suggestions" r with
                  | `List ss ->
                    List.filter_map
                      (function
                        | `Assoc s ->
                          Some
                            { sg_param = str (member "param" s);
                              sg_base = str (member "base" s);
                              sg_pred = str (member "predicate" s);
                              sg_annotation = str (member "annotation" s) }
                        | _ -> None)
                      ss
                  | _ -> []
                in
                Some
                  { rs_fn = str (member "fn" r);
                    rs_file = str (member "file" r);
                    rs_line = int (member "line" r);
                    rs_status = str (member "status" r);
                    rs_debt_before = int (member "debt_before" r);
                    rs_debt_after = int (member "debt_after" r);
                    rs_suggestions = sugs }
              | _ -> None)
            rs
        | _ -> [])
     | _ -> [])

let ask ~lib_path_env ~budget ~mode file : fn_result list =
  let cmd =
    Printf.sprintf "%smarch --check --refine-suggest-json %s --refine-suggest-budget %d %s"
      lib_path_env mode budget (Filename.quote file)
  in
  let (_rc, out) = run_capturing_stdout cmd in
  (* The compiler is a subprocess, so when this command comes back empty the
     question is always "did march fail, or did the JSON not parse?".  Setting
     FORGE_REFINE_DEBUG answers it without a rebuild. *)
  if (try Sys.getenv "FORGE_REFINE_DEBUG" <> "" with Not_found -> false) then
    Printf.eprintf "forge refine: %s\n-> %s\n%!" cmd out;
  parse_results out

(* ── Applying an edit ─────────────────────────────────────────────────────── *)

(* The splice itself lives in [March_refactor.Refine_edit] because the LSP's
   `march.suggestRefinement` command must produce a byte-identical edit; see
   that module's header. *)

let read_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = Bytes.create n in
  really_input ic s 0 n;
  close_in ic;
  Bytes.to_string s

let write_file path content =
  let oc = open_out_bin path in
  output_string oc content;
  close_out oc

(* A spliced file must still parse.  This is the backstop for every shape
   [Refine_edit]'s scanner did not anticipate: a file that no longer
   parses is never written. *)
let parses (src : string) (filename : string) : bool =
  try
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
    ignore
      (March_parser.Parser.module_
         (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf);
    true
  with _ -> false

let apply_result (r : fn_result) : (string, string) result =
  if r.rs_suggestions = [] then Error (Printf.sprintf "%s: nothing to apply" r.rs_fn)
  else
    match (try Some (read_file r.rs_file) with Sys_error m -> prerr_endline m; None) with
    | None -> Error (Printf.sprintf "cannot read %s" r.rs_file)
    | Some src0 ->
      let short_fn =
        match String.rindex_opt r.rs_fn '.' with
        | Some i -> String.sub r.rs_fn (i + 1) (String.length r.rs_fn - i - 1)
        | None -> r.rs_fn
      in
      let rec go src = function
        | [] -> Ok src
        | s :: tl ->
          (match
             March_refactor.Refine_edit.splice ~src ~line:r.rs_line ~fn:short_fn
               ~param:s.sg_param ~annotation:s.sg_annotation
           with
           | None ->
             Error
               (Printf.sprintf
                  "%s: could not locate the annotation for `%s` in %s — apply it by hand"
                  r.rs_fn s.sg_param r.rs_file)
           | Some src' -> go src' tl)
      in
      (match go src0 r.rs_suggestions with
       | Error _ as e -> e
       | Ok src' ->
         if not (parses src' r.rs_file) then
           Error
             (Printf.sprintf
                "%s: the edited source no longer parses, so nothing was written to %s"
                r.rs_fn r.rs_file)
         else begin
           write_file r.rs_file src';
           Ok (Printf.sprintf "%s: applied %d refinement(s) to %s" r.rs_fn
                 (List.length r.rs_suggestions) r.rs_file)
         end)

(* ── Rendering ────────────────────────────────────────────────────────────── *)

let print_result ~root (r : fn_result) =
  let rel =
    let n = String.length root in
    if String.length r.rs_file > n && String.sub r.rs_file 0 n = root then
      String.sub r.rs_file (n + 1) (String.length r.rs_file - n - 1)
    else r.rs_file
  in
  match r.rs_status with
  | "no-debt" ->
    Printf.printf "%s: nothing to prove — every obligation in this body is already discharged\n%!"
      r.rs_fn
  | "budget-exhausted" ->
    Printf.printf
      "%s: search stopped at the probe budget with %d obligation(s) still \
       unproven — re-run with a larger --budget\n%!"
      r.rs_fn r.rs_debt_after
  | "no-candidate" ->
    Printf.printf
      "%s: %d unproven obligation(s), but no candidate refinement discharges any of them\n%!"
      r.rs_fn r.rs_debt_before
  | _ ->
    Printf.printf "%s:%d  %s\n%!" rel r.rs_line r.rs_fn;
    List.iter
      (fun s ->
        Printf.printf "    %s : %s  ->  %s : %s\n%!" s.sg_param s.sg_base s.sg_param
          s.sg_annotation)
      r.rs_suggestions;
    if r.rs_status = "solved" then
      Printf.printf "  discharges all %d unproven obligation(s)\n%!" r.rs_debt_before
    else
      Printf.printf "  discharges %d of %d; %d still unproven\n%!"
        (r.rs_debt_before - r.rs_debt_after) r.rs_debt_before r.rs_debt_after

(* ── Entry point ──────────────────────────────────────────────────────────── *)

let default_budget = 200

let run ?(all = false) ?(apply = false) ?(budget = default_budget)
    ~(target : string) () : (string, string) result =
  match P.load () with
  | Error msg -> Error msg
  | Ok proj ->
    let root = proj.P.root in
    let lib_dir = Filename.concat root "lib" in
    let files =
      let fs = Cmd_build.find_march_files lib_dir in
      match proj.P.project_type with
      | P.Lib -> fs
      | P.App | P.Tool ->
        let entry =
          match proj.P.entrypoint with
          | Some ep -> Filename.concat root ep
          | None -> Filename.concat lib_dir (proj.P.name ^ ".march")
        in
        if List.mem entry fs || not (Sys.file_exists entry) then fs else entry :: fs
    in
    if files = [] then Error (Printf.sprintf "no .march files found under %s" root)
    else begin
      let lib_path_env = Cmd_build.lib_path_env proj in
      let mode =
        if all then "--refine-suggest-all"
        else Printf.sprintf "--refine-suggest %s" (Filename.quote target)
      in
      (* For a named target, stop at the first file that knows the function: the
         answer costs a full check per file, and asking the rest cannot change
         an answer already found. *)
      let rec sweep acc = function
        | [] -> List.rev acc
        | f :: tl ->
          let rs =
            List.filter (fun r -> r.rs_status <> "not-found") (ask ~lib_path_env ~budget ~mode f)
          in
          if rs <> [] && not all then List.rev_append acc rs else sweep (List.rev_append rs acc) tl
      in
      let results = sweep [] files in
      if results = [] then
        (* Deliberately NOT "everything is already discharged": --all reports
           only functions that HAVE a proposal, so an empty sweep also covers
           functions with debt the grammar cannot shift.  Claiming the stronger
           thing would turn "I found nothing" into "there is nothing". *)
        if all then Ok "no function in this project has a proposable refinement"
        else Error (Printf.sprintf "no user function named `%s` in this project" target)
      else begin
        List.iter (print_result ~root) results;
        let applicable = List.filter (fun r -> r.rs_suggestions <> []) results in
        if not apply then
          if applicable = [] then Ok "no annotation to propose"
          else
            Ok
              (Printf.sprintf
                 "%d function(s) with a proposal; re-run with --apply to write the annotations"
                 (List.length applicable))
        else begin
          if applicable = [] then Ok "nothing to apply"
          else begin
            let failures = ref [] in
            List.iter
              (fun r ->
                match apply_result r with
                | Ok msg -> Printf.printf "%s\n%!" msg
                | Error msg -> failures := msg :: !failures)
              applicable;
            match !failures with
            | [] ->
              Ok (Printf.sprintf "applied %d function(s)" (List.length applicable))
            | fs -> Error (String.concat "\n" (List.rev fs))
          end
        end
      end
    end
