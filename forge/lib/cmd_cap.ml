(** forge cap query [--dir DIR]

    Walk all .march files in the project (or a given directory) and print
    a capability / typestate summary: every [needs], [always_linear type],
    [transitions], and [proof cap] declaration found in the source.

    This is a static analysis pass — it parses files but does not typecheck. *)

module Ast = March_ast.Ast

(* ------------------------------------------------------------------ *)
(* Parsing                                                              *)
(* ------------------------------------------------------------------ *)

let parse_file path : (Ast.decl list, string) result =
  try
    let ic  = open_in path in
    let src = really_input_string ic (in_channel_length ic) in
    close_in ic;
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
    let m = March_parser.Parser.module_
        (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
    Ok m.Ast.mod_decls
  with
  | Sys_error msg -> Error msg
  | exn -> Error (Printexc.to_string exn)

(* ------------------------------------------------------------------ *)
(* Extraction                                                           *)
(* ------------------------------------------------------------------ *)

type cap_summary = {
  file          : string;
  needs         : string list list;
  always_linear : string list;
  transitions   : (string * Ast.transition list) list;
  proof_caps    : string list;
}

let rec extract_decls decls acc =
  List.fold_left extract_one acc decls

and extract_one acc = function
  | Ast.DNeeds (paths, _) ->
    let strs = List.map (List.map (fun n -> n.Ast.txt)) paths in
    { acc with needs = acc.needs @ strs }
  | Ast.DAlwaysLinearType (_, name, _, _, _) ->
    { acc with always_linear = acc.always_linear @ [name.Ast.txt] }
  | Ast.DTransitions (name, arms, _) ->
    { acc with transitions = acc.transitions @ [(name.Ast.txt, arms)] }
  | Ast.DProofCap (name, _) ->
    { acc with proof_caps = acc.proof_caps @ [name.Ast.txt] }
  | Ast.DMod (_, _, inner, _) ->
    extract_decls inner acc
  | _ -> acc

let extract_caps ~file decls =
  let empty = { file; needs = []; always_linear = []; transitions = []; proof_caps = [] } in
  extract_decls decls empty

(* ------------------------------------------------------------------ *)
(* Output                                                               *)
(* ------------------------------------------------------------------ *)

let pp_cap_path parts = String.concat "." parts

let render_summary ~root (s : cap_summary) : string option =
  let has_needs = s.needs <> [] in
  let has_al    = s.always_linear <> [] in
  let has_trans = s.transitions <> [] in
  let has_pc    = s.proof_caps <> [] in
  if not (has_needs || has_al || has_trans || has_pc) then None
  else begin
    let buf = Buffer.create 64 in
    let rel =
      if String.length root < String.length s.file &&
         String.sub s.file 0 (String.length root) = root
      then "." ^ String.sub s.file (String.length root)
                   (String.length s.file - String.length root)
      else s.file
    in
    Buffer.add_string buf (rel ^ "\n");
    if has_needs then begin
      Buffer.add_string buf "  needs:\n";
      List.iter (fun p ->
          Buffer.add_string buf (Printf.sprintf "    %s\n" (pp_cap_path p))
        ) s.needs
    end;
    if has_al then begin
      Buffer.add_string buf "  always_linear:\n";
      List.iter (fun name ->
          Buffer.add_string buf (Printf.sprintf "    %s\n" name)
        ) s.always_linear
    end;
    if has_trans then begin
      Buffer.add_string buf "  transitions:\n";
      List.iter (fun (handle, arms) ->
          Buffer.add_string buf (Printf.sprintf "    %s:\n" handle);
          List.iter (fun (arm : Ast.transition) ->
              Buffer.add_string buf
                (Printf.sprintf "      %s: %s -> %s  via %s\n"
                   arm.tr_resource.txt
                   arm.tr_from.txt
                   arm.tr_to.txt
                   arm.tr_via.txt)
            ) arms
        ) s.transitions
    end;
    if has_pc then begin
      Buffer.add_string buf "  proof_caps:\n";
      List.iter (fun name ->
          Buffer.add_string buf (Printf.sprintf "    %s\n" name)
        ) s.proof_caps
    end;
    Some (Buffer.contents buf)
  end

(* ------------------------------------------------------------------ *)
(* Entry point                                                          *)
(* ------------------------------------------------------------------ *)

let query ~dir () =
  let root = match dir with
    | Some d -> d
    | None ->
      (match Project.load () with
       | Ok proj -> proj.Project.root
       | Error _ -> Sys.getcwd ())
  in
  let files = Cmd_build.find_march_files root in
  if files = [] then
    Error (Printf.sprintf "no .march files found under %s" root)
  else begin
    let any = ref false in
    List.iter (fun path ->
        match parse_file path with
        | Error msg ->
          Printf.eprintf "forge cap: %s: %s\n%!" path msg
        | Ok decls ->
          let s = extract_caps ~file:path decls in
          (match render_summary ~root s with
           | None -> ()
           | Some output -> any := true; print_string output)
      ) files;
    if not !any then
      Printf.printf "no capability declarations found under %s\n%!" root;
    Ok ()
  end
