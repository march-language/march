(** Emit-time verification of machine-applicable fixes
    (specs/progress/2026-11-06-fix-applicability-tiers.md).

    `--check-json` is what `forge fix`, the editor and agents read, and a
    fix marked machine-applicable there may be applied unasked.  So before it
    prints one, the driver tries it: it applies the fix to a copy of the
    source, checks the copy, and keeps the tier only when the fix cleared its
    own diagnostic and brought in nothing new.  Anything else is downgraded to
    maybe-incorrect: still offered, never applied unasked.

    "Brought in nothing new" is a comparison of the diagnostic codes before
    and after, counted with multiplicity: after the fix there must be fewer
    of the fixed diagnostic's code and no more of any other.  The corpus is
    full of programs with two independent mistakes, and a fix for one must
    not be blamed for the other; counting codes rather than matching spans
    also survives the line shifts an inserted or deleted line causes.

    The copy is checked by this same executable, with the same arguments,
    reading the patched text through [--fix-verify-source] while keeping the
    original file name: sibling modules, MARCH_LIB_PATH and the module's own
    identity resolve exactly as they did for the real run.  [MARCH_FIX_VERIFY=0]
    in the child (and for a caller who wants none) turns verification off.

    A parse error is verified in-process instead: the parser is cheap and pure,
    and a later-stage error the fix uncovers could not have been reported
    before it, so the test is only that parsing now gets past the fix. *)

module Err = March_errors.Errors

let enabled () = Sys.getenv_opt "MARCH_FIX_VERIFY" <> Some "0"

(* Individually verified fixes beyond this many are downgraded unchecked, so
   a file with dozens of fixes costs a bounded number of extra checks.  The
   batch check below normally settles them all in one. *)
let max_individual = 8

let code_re = Str.regexp {|"code":"\([^"\\]*\)"|}

(** The error and warning codes in an NDJSON stream, one per line.  A hint
    is advice, not a problem, so one a fix brings in (`needs IO` draws the
    "narrow this" hint) does not count against it. *)
let codes_of_ndjson out =
  List.filter_map (fun l ->
      if String.starts_with ~prefix:{|{"severity":"hint"|} l then None
      else match Str.search_forward code_re l 0 with
        | _ -> Some (Str.matched_group 1 l)
        | exception Not_found -> None)
    (String.split_on_char '\n' out)

let count c codes = List.length (List.filter (( = ) c) codes)

(* The codes of [patched], checked by a child run of this executable with the
   same arguments; [None] when the child could not be run. *)
let check_patched ~patched =
  let tmp = Filename.temp_file "march_fix_verify" ".march" in
  let out = Filename.temp_file "march_fix_verify" ".json" in
  let cleanup () = (try Sys.remove tmp with _ -> ()); (try Sys.remove out with _ -> ()) in
  try
    let oc = open_out_bin tmp in
    output_string oc patched;
    close_out oc;
    (* [--check-json] whatever the run was: the codes are read from it. *)
    let args =
      Array.append Sys.argv [| "--check-json"; "--fix-verify-source"; tmp |] in
    let prev = Sys.getenv_opt "MARCH_FIX_VERIFY" in
    Unix.putenv "MARCH_FIX_VERIFY" "0";
    let out_fd = Unix.openfile out [ Unix.O_WRONLY; Unix.O_TRUNC; Unix.O_CREAT ] 0o600 in
    let null = Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0 in
    let pid =
      Fun.protect
        ~finally:(fun () ->
            Unix.close out_fd; Unix.close null;
            Unix.putenv "MARCH_FIX_VERIFY" (Option.value prev ~default:""))
        (fun () -> Unix.create_process Sys.executable_name args Unix.stdin out_fd null) in
    let _ = Unix.waitpid [] pid in
    let ic = open_in_bin out in
    let s = really_input_string ic (in_channel_length ic) in
    close_in ic;
    cleanup ();
    Some (codes_of_ndjson s)
  with _ -> cleanup (); None

let downgrade (d : Err.diagnostic) =
  match d.fix with
  | Some f when f.tier = Err.Machine_applicable ->
    { d with fix = Some { f with tier = Err.Maybe_incorrect } }
  | _ -> d

(** [diags] (a type-checked program's, as `--check-json` is about to print
    them) with every machine-applicable fix that does not survive a re-check
    downgraded.  [verifiable d] says which diagnostics are this file's own. *)
let verify ~src ~(verifiable : Err.diagnostic -> bool) (diags : Err.diagnostic list) =
  let is_candidate (d : Err.diagnostic) =
    verifiable d && d.severity <> Err.Hint
    && (match d.fix with Some f -> f.tier = Err.Machine_applicable | None -> false) in
  let candidates = List.filter is_candidate diags in
  if candidates = [] || not (enabled ()) then diags
  else begin
    let before = List.map (fun (d : Err.diagnostic) -> d.code)
        (List.filter (fun (d : Err.diagnostic) -> verifiable d && d.severity <> Err.Hint) diags) in
    let edits_of ds = List.filter_map (fun (d : Err.diagnostic) ->
        Option.map (fun (f : Err.fix) -> f.edit) d.fix) ds in
    (* Every candidate at once: when that is clean, so is each one. *)
    let batch_ok =
      match check_patched ~patched:(Err.apply_edits src (edits_of candidates)) with
      | None -> false
      | Some after ->
        let fixed c = count c (List.map (fun (d : Err.diagnostic) -> d.code) candidates) in
        List.for_all (fun c -> count c after <= count c before - fixed c)
          (List.sort_uniq compare (before @ after)) in
    if batch_ok then diags
    else begin
      let verdicts = Hashtbl.create 8 in
      List.iteri (fun i (d : Err.diagnostic) ->
          let ok =
            i < max_individual
            && (match check_patched ~patched:(Err.apply_edits src (edits_of [ d ])) with
                | None -> false
                | Some after ->
                  count d.code after < count d.code before
                  && List.for_all (fun c -> c = d.code || count c after <= count c before)
                    (List.sort_uniq compare after)) in
          Hashtbl.replace verdicts i ok)
        candidates;
      let idx = ref (-1) in
      List.map (fun (d : Err.diagnostic) ->
          if is_candidate d then begin
            incr idx;
            if Hashtbl.find verdicts !idx then d else downgrade d
          end else d)
        diags
    end
  end

(** A parse error's diagnostics, with a machine-applicable fix downgraded
    unless the patched source parses, or parses further: its first error now
    starts after the last line the fix touched. *)
let verify_parse ~filename ~src (diags : Err.diagnostic list) =
  if not (enabled ()) then diags
  else
    List.map (fun (d : Err.diagnostic) ->
        match d.fix with
        | Some f when f.tier = Err.Machine_applicable ->
          let patched = Err.apply_edits src [ f.edit ] in
          let delta =
            List.length (String.split_on_char '\n' patched)
            - List.length (String.split_on_char '\n' src) in
          let last_touched =
            List.fold_left (fun m e -> max m (match e with
                | Err.FInsert { after_line; _ } -> after_line + 1
                | Err.FDelete { start_line; _ } -> start_line
                | Err.FReplace { span; _ } -> span.March_ast.Ast.end_line
                | Err.FMulti _ -> 0)) 0 (Err.fix_edits f.edit) + max 0 delta in
          (match March_parser.Parse.module_ ~filename patched with
           | Ok _ -> d
           | Error (e :: _) when e.Err.span.March_ast.Ast.start_line > last_touched -> d
           | Error _ -> downgrade d)
        | _ -> d)
      diags
