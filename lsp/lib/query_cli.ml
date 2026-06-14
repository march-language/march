(** Stateless one-shot CLI: analyse one file, answer one query, print JSON.

    Designed for editors without a persistent client, for scripts, and for LLMs
    (which can pipe an unsaved buffer via --stdin). All positions are 0-indexed
    UTF-16, matching the LSP convention. Output is a single JSON object. *)

module Lsp = Linol_lsp.Lsp

let read_file path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
    let n = in_channel_length ic in
    let b = Bytes.create n in
    really_input ic b 0 n;
    Bytes.to_string b)

let read_stdin () =
  let buf = Buffer.create 4096 in
  (try
     while true do Buffer.add_channel buf stdin 4096 done
   with End_of_file -> ());
  Buffer.contents buf

(* Minimal JSON string escaping (avoids a json dependency). *)
let jstr s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter (fun c ->
    match c with
    | '"'  -> Buffer.add_string b "\\\""
    | '\\' -> Buffer.add_string b "\\\\"
    | '\n' -> Buffer.add_string b "\\n"
    | '\r' -> Buffer.add_string b "\\r"
    | '\t' -> Buffer.add_string b "\\t"
    | c when Char.code c < 0x20 ->
      Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
    | c -> Buffer.add_char b c) s;
  Buffer.add_char b '"';
  Buffer.contents b

let opt_str = function None -> "null" | Some s -> jstr s

let jrange (sl, sc, el, ec) =
  Printf.sprintf
    "{\"start\":{\"line\":%d,\"character\":%d},\"end\":{\"line\":%d,\"character\":%d}}"
    sl sc el ec

let find_flag argv name =
  let n = Array.length argv in
  let rec go i =
    if i + 1 >= n then None
    else if argv.(i) = name then Some argv.(i + 1)
    else go (i + 1)
  in
  go 0

let int_flag argv name default =
  match find_flag argv name with
  | Some s -> (try int_of_string s with _ -> default)
  | None -> default

let diag_message (d : Lsp.Types.Diagnostic.t) =
  match d.Lsp.Types.Diagnostic.message with
  | `String s -> s
  | `MarkupContent m -> m.Lsp.Types.MarkupContent.value

(* [src_override] lets tests inject source without touching the filesystem. *)
let run_to_string (args : string list) ~src_override : string =
  let argv = Array.of_list args in
  match args with
  | _ :: feature :: file :: _ ->
    let src =
      match src_override with
      | Some s -> s
      | None ->
        if Array.exists (( = ) "--stdin") argv then read_stdin ()
        else read_file file
    in
    let a = Analysis.analyse ~filename:file ~src in
    let line = int_flag argv "--line" 0 and col = int_flag argv "--col" 0 in
    (match feature with
     | "hover" ->
       let r = Query.hover a ~line ~utf16_char:col in
       Printf.sprintf "{\"type\":%s,\"doc\":%s,\"perf\":%s}"
         (opt_str r.Query.h_type) (opt_str r.Query.h_doc) (opt_str r.Query.h_perf)
     | "definition" ->
       (match Query.definition a ~line ~utf16_char:col with
        | None -> "{\"definition\":null}"
        | Some l ->
          Printf.sprintf "{\"definition\":{\"uri\":%s,\"range\":%s}}"
            (jstr l.Query.loc_uri) (jrange l.Query.loc_range))
     | "references" ->
       (* Current file (live, scope-correct). *)
       let local = Query.references a ~include_declaration:true ~line ~utf16_char:col in
       let local_json =
         List.map (fun (l : Query.location) ->
             Printf.sprintf "{\"uri\":%s,\"range\":%s}" (jstr l.Query.loc_uri)
               (jrange l.Query.loc_range)) local
       in
       (* Other files: name-based cross-file refs for a top-level symbol. *)
       let byte_col = Utf16.lsp_char_to_byte_col a.Analysis.doc ~line ~utf16_char:col in
       let cross_json =
         match Analysis.local_symbol_at a ~line ~character:byte_col with
         | Some _ -> []
         | None ->
           (match Analysis.name_at a ~line ~character:byte_col with
            | None -> []
            | Some name ->
              let root =
                match Forge_config.find_forge_root (Filename.dirname file) with
                | Some r -> r | None -> Filename.dirname file
              in
              Workspace.references_across (Workspace.index_project_full ~root) name
              |> List.filter (fun (f, _) -> f <> a.Analysis.filename)
              |> List.map (fun (f, (sp : March_ast.Ast.span)) ->
                     let r = Position.span_to_lsp_range sp in
                     Printf.sprintf "{\"uri\":%s,\"range\":%s}"
                       (jstr (Lsp.Types.DocumentUri.to_string
                                (Lsp.Types.DocumentUri.of_path f)))
                       (jrange
                          (r.Lsp.Types.Range.start.Lsp.Types.Position.line,
                           r.Lsp.Types.Range.start.Lsp.Types.Position.character,
                           r.Lsp.Types.Range.end_.Lsp.Types.Position.line,
                           r.Lsp.Types.Range.end_.Lsp.Types.Position.character))))
       in
       "{\"references\":[" ^ String.concat "," (local_json @ cross_json) ^ "]}"
     | "diagnostics" ->
       (* Remap byte-column ranges to UTF-16 for client-consistent output. *)
       let ds = List.map (Position.remap_diagnostic a.Analysis.doc)
                  (Query.diagnostics a) in
       let one (d : Lsp.Types.Diagnostic.t) =
         let r = d.Lsp.Types.Diagnostic.range in
         Printf.sprintf "{\"message\":%s,\"range\":%s}" (jstr (diag_message d))
           (jrange
              (r.Lsp.Types.Range.start.Lsp.Types.Position.line,
               r.Lsp.Types.Range.start.Lsp.Types.Position.character,
               r.Lsp.Types.Range.end_.Lsp.Types.Position.line,
               r.Lsp.Types.Range.end_.Lsp.Types.Position.character))
       in
       "{\"diagnostics\":[" ^ String.concat "," (List.map one ds) ^ "]}"
     | "completions" ->
       let items = Query.completions a ~line ~utf16_char:col in
       let label (it : Lsp.Types.CompletionItem.t) =
         jstr it.Lsp.Types.CompletionItem.label
       in
       "{\"completions\":[" ^ String.concat "," (List.map label items) ^ "]}"
     | other -> Printf.sprintf "{\"error\":%s}" (jstr ("unknown query: " ^ other)))
  | _ ->
    "{\"error\":\"usage: march-lsp query <feature> <file> \
     [--line N --col M] [--stdin]\"}"

let main (argv : string array) : int =
  let out = run_to_string (Array.to_list argv) ~src_override:None in
  print_string out;
  print_newline ();
  if String.length out >= 9 && String.sub out 0 9 = "{\"error\":" then 2 else 0
