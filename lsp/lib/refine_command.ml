(** `march.suggestRefinement` — the executeCommand side of the "Suggest a
    refinement type" code action.

    The action offered in [Analysis.code_actions_at] carries a command rather
    than an edit, because computing the edit costs a fully checked module plus a
    series of Z3 queries — far too much to spend on every cursor movement.  This
    module does that work once, when the user picks the action, and returns a
    [WorkspaceEdit] for the server to hand back via workspace/applyEdit.

    The inference runs in the compiler (`march --refine-suggest-json`) for the
    same reason `forge refine` shells out: the pipeline that turns a file into a
    checkable module — stdlib load, import resolution, typecheck — lives in
    bin/main.ml, not in a library.  The resulting edit is computed by
    [March_refactor.Refine_edit], the same code `forge refine --apply` uses, so
    accepting the quick-fix and running the CLI produce identical bytes. *)

module Lsp = Linol_lsp.Lsp
module Types = Lsp.Types

type suggestion = { param : string; annotation : string }

type parsed = {
  ps_fn : string;
  ps_file : string;
  ps_line : int;
  ps_status : string;
  ps_debt_before : int;
  ps_debt_after : int;
  ps_suggestions : suggestion list;
}

let read_all path =
  try
    let ic = open_in_bin path in
    let n = in_channel_length ic in
    let s = Bytes.create n in
    really_input ic s 0 n;
    close_in ic;
    Some (Bytes.to_string s)
  with Sys_error _ -> None

let run_compiler ~file ~fn : string =
  let tmp = Filename.temp_file "march_lsp_refine" ".json" in
  let cmd =
    Printf.sprintf
      "march --check --refine-suggest-json --refine-suggest %s %s >%s 2>/dev/null"
      (Filename.quote fn) (Filename.quote file) (Filename.quote tmp)
  in
  ignore (Sys.command cmd);
  let out = Option.value ~default:"" (read_all tmp) in
  (try Sys.remove tmp with Sys_error _ -> ());
  out

let parse (json : string) : parsed list =
  match Yojson.Safe.from_string json with
  | exception _ -> []
  | `Assoc top ->
    let member k o = try List.assoc k o with Not_found -> `Null in
    let str = function `String s -> s | _ -> "" in
    let int = function `Int n -> n | _ -> 0 in
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
                         { param = str (member "param" s);
                           annotation = str (member "annotation" s) }
                     | _ -> None)
                   ss
               | _ -> []
             in
             Some
               { ps_fn = str (member "fn" r);
                 ps_file = str (member "file" r);
                 ps_line = int (member "line" r);
                 ps_status = str (member "status" r);
                 ps_debt_before = int (member "debt_before" r);
                 ps_debt_after = int (member "debt_after" r);
                 ps_suggestions = sugs }
           | _ -> None)
         rs
     | _ -> [])
  | _ -> []

let short_name fn =
  match String.rindex_opt fn '.' with
  | Some i -> String.sub fn (i + 1) (String.length fn - i - 1)
  | None -> fn

(* One TextEdit per suggested parameter.  Every edit is computed against the
   ORIGINAL source, so the ranges are independent and the client may apply them
   in any order — which is the contract a WorkspaceEdit's edit list carries. *)
let edits_of ~(src : string) (p : parsed) : Types.TextEdit.t list option =
  let fn = short_name p.ps_fn in
  let rec go acc = function
    | [] -> Some (List.rev acc)
    | s :: tl ->
      (match
         March_refactor.Refine_edit.byte_range_of_param ~src ~line:p.ps_line ~fn
           ~param:s.param
       with
       | None -> None
       | Some (a, b) ->
         let (sl, sc) = March_refactor.Refine_edit.position_of_offset src a in
         let (el, ec) = March_refactor.Refine_edit.position_of_offset src b in
         let range =
           Types.Range.create
             ~start:(Types.Position.create ~line:sl ~character:sc)
             ~end_:(Types.Position.create ~line:el ~character:ec)
         in
         go (Types.TextEdit.create ~range ~newText:(" " ^ s.annotation) :: acc) tl)
  in
  go [] p.ps_suggestions

let msg status ?(edit : Types.WorkspaceEdit.t option) text =
  let base =
    [ ("status", `String status);
      ("kind", `String "suggestRefinement");
      ("message", `String text) ]
  in
  `Assoc
    (match edit with
     | None -> base
     | Some e -> base @ [ ("edit", Types.WorkspaceEdit.yojson_of_t e) ])

(** Returns the JSON payload for the executeCommand response, plus the edit the
    server should send through workspace/applyEdit (if there is one). *)
let run ~(file : string) ~(fn : string) :
    Yojson.Safe.t * Types.WorkspaceEdit.t option =
  match parse (run_compiler ~file ~fn) with
  | [] ->
    ( msg "error"
        (Printf.sprintf
           "Could not run the refinement checker for `%s`. Is `march` on PATH, \
            and is z3 installed?"
           fn),
      None )
  | p :: _ ->
    (match p.ps_status with
     | "no-debt" ->
       ( msg "ok"
           (Printf.sprintf
              "`%s` has nothing to prove — every obligation in its body is \
               already discharged."
              fn),
         None )
     | "budget-exhausted" ->
       ( msg "ok"
           (Printf.sprintf
              "The search for `%s` stopped at its probe budget with %d \
               obligation(s) still unproven."
              fn p.ps_debt_after),
         None )
     | "no-candidate" ->
       ( msg "ok"
           (Printf.sprintf
              "`%s` has %d unproven obligation(s), but no candidate refinement \
               discharges any of them."
              fn p.ps_debt_before),
         None )
     | "not-found" ->
       (msg "error" (Printf.sprintf "No function named `%s` in %s." fn file), None)
     | _ ->
       (match read_all p.ps_file with
        | None ->
          (msg "error" (Printf.sprintf "Could not read %s." p.ps_file), None)
        | Some src ->
          (match edits_of ~src p with
           | None ->
             ( msg "error"
                 (Printf.sprintf
                    "Found a refinement for `%s`, but could not locate the \
                     annotation to rewrite — apply it by hand."
                    fn),
               None )
           | Some edits ->
             let uri = Types.DocumentUri.of_path p.ps_file in
             let we = Types.WorkspaceEdit.create ~changes:[ (uri, edits) ] () in
             let summary =
               String.concat ", "
                 (List.map
                    (fun s -> Printf.sprintf "%s : %s" s.param s.annotation)
                    p.ps_suggestions)
             in
             let tail =
               if p.ps_status = "solved" then
                 Printf.sprintf "discharges all %d unproven obligation(s)"
                   p.ps_debt_before
               else
                 Printf.sprintf "discharges %d of %d; %d still unproven"
                   (p.ps_debt_before - p.ps_debt_after)
                   p.ps_debt_before p.ps_debt_after
             in
             ( msg "ok" ~edit:we (Printf.sprintf "%s — %s" summary tail),
               Some we ))))
