(** Shared harness for the March LSP test suite.

    Module aliases and the handful of helpers every group needs
    ([analyse], [pos_of], [mk_span], and the small accessors over
    [Analysis.t]).  Split out of [test_lsp.ml] so the ~350 test functions
    could move into focused modules without each one re-deriving these.

    Every [test_lsp_*.ml] opens this; [test_lsp.ml] itself opens all of them,
    which is what lets the Alcotest registration keep referring to the test
    functions by their bare names, unchanged. *)

module Lsp  = Linol_lsp.Lsp
module Ast  = March_ast.Ast
module Pos  = March_lsp_lib.Position
module An   = March_lsp_lib.Analysis
module Qy   = March_lsp_lib.Query

(* ------------------------------------------------------------------ *)
(* Helpers                                                             *)
(* ------------------------------------------------------------------ *)

(** Find the first occurrence of [sub] in [src] and return its
    (0-indexed line, 0-indexed col). *)
let pos_of src sub =
  let sn = String.length sub in
  let n  = String.length src in
  let rec find i line col =
    if i + sn > n then
      failwith (Printf.sprintf "pos_of: %S not found in source" sub)
    else if String.sub src i sn = sub then (line, col)
    else if src.[i] = '\n' then find (i + 1) (line + 1) 0
    else find (i + 1) line (col + 1)
  in
  find 0 0 0

(** Build a March span with 1-indexed lines and 0-indexed cols. *)
let mk_span ?(file = "test.march") sl sc el ec =
  { Ast.file; start_line = sl; start_col = sc; end_line = el; end_col = ec }

(** Run analyse on [src] with filename "test.march". *)
let analyse src = An.analyse ~filename:"test.march" ~src

(** Return the number of diagnostics whose severity is Error. *)
let count_errors (a : An.t) =
  List.length
    (List.filter (fun (d : Lsp.Types.Diagnostic.t) ->
         d.severity = Some Lsp.Types.DiagnosticSeverity.Error)
       a.diagnostics)

(** Names present in the document symbol outline. *)
let symbol_names (a : An.t) =
  match An.document_symbols a with
  | `DocumentSymbol syms ->
    List.map (fun (s : Lsp.Types.DocumentSymbol.t) -> s.name) syms
  | _ -> []

(** Labels present in the completion list. *)
let completion_labels (a : An.t) =
  List.map (fun (i : Lsp.Types.CompletionItem.t) -> i.label)
    (An.completions_at a ~line:0 ~character:0)

let contains_sub hay needle =
  let h = String.lowercase_ascii hay and n = String.lowercase_ascii needle in
  let hl = String.length h and nl = String.length n in
  let rec f i = if i + nl > hl then false
                else if String.sub h i nl = n then true else f (i + 1) in
  f 0

(** Code actions at the cursor located at the first occurrence of [sub] in
    [src], optionally offset by [off] characters. *)

let str_contains ~sub s =
  let ls = String.length s and lsub = String.length sub in
  let rec go i = i + lsub <= ls && (String.sub s i lsub = sub || go (i + 1)) in
  go 0

let all_edit_texts acts title =
  match List.find_opt (fun (c : Lsp.Types.CodeAction.t) -> contains_sub c.title title) acts with
  | None -> ""
  | Some c ->
    (match c.edit with
     | None -> ""
     | Some e ->
       (match e.changes with
        | None -> ""
        | Some chs ->
          String.concat "|"
            (List.concat_map (fun (_, es) ->
                 List.map (fun (te : Lsp.Types.TextEdit.t) -> te.newText) es) chs)))

