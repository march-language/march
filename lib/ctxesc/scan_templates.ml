(* Dry-run scanner: walk every ~H template in a source tree through the context
   automaton and report what the Task 5 desugar WOULD do, without changing it.
 *
 * Purpose is blast radius. Task 5 turns some interpolations into hard compile
 * errors and rewrites others (the unquoted-attribute substitution), so the
 * honest order is to measure a real corpus first rather than discover the
 * fallout afterwards.
 *
 * Usage:
 *   scan_templates.exe <table.tbl> <dir> [<dir> ...]
 *
 * Parses each .march file with the real lexer/parser and finds ESigil("H", _),
 * so what it sees is exactly what the desugar will see -- not a regex guess at
 * template boundaries.
 *
 * Exit code is always 0: this is a report, not a gate. *)

module C = March_ctxesc.Context
module P = March_ctxesc.Tbl_parse
module A = March_ctxesc.Automaton

type finding =
  | Ok_hole of C.escaper
  | Rejected of string
  | Literal_error of string
  | Bad_terminal of string

let escaper_counts : (string, int) Hashtbl.t = Hashtbl.create 8
let bump tbl k = Hashtbl.replace tbl k (1 + (try Hashtbl.find tbl k with Not_found -> 0))

let problems : (string * int * finding) list ref = ref []
(* Holes whose escaper is NOT EscHtml. These still COMPILE, but their output
   changes: today every hole is HTML-escaped regardless of context. Behaviour
   changes need eyeballing even when nothing errors. *)
let changed : (string * int * string) list ref = ref []
let n_templates = ref 0
let n_holes = ref 0

(* A ~H sigil's content is a `++` chain of literal chunks and to_string(hole)
   calls, exactly as the desugar sees it. *)
let rec decompose (e : March_ast.Ast.expr) =
  let open March_ast.Ast in
  match e with
  | EApp (EVar { txt = "++"; _ }, [ l; r ], _) -> decompose l @ decompose r
  | EApp (EVar { txt = "string_concat3"; _ }, [ a; b; c ], _) ->
    decompose a @ decompose b @ decompose c
  | _ -> [ e ]

let scan_sigil tbl file line content =
  let open March_ast.Ast in
  incr n_templates;
  let ctx = ref C.initial in
  let parts = decompose content in
  List.iter
    (fun part ->
       match part with
       | ELit (LitString s, _) ->
         (match A.consume_literal tbl !ctx s with
          | Ok o -> ctx := o.A.ctx
          | Error (m, _) ->
            problems := (file, line, Literal_error m) :: !problems)
       | EApp (EVar { txt = "to_string"; _ }, _, _) ->
         incr n_holes;
         (match A.consume_interp tbl !ctx with
          | Ok (esc, _, c') ->
            ctx := c';
            bump escaper_counts (C.escaper_name esc);
            if esc <> C.EscHtml then
              changed := (file, line, C.escaper_name esc) :: !changed;
            ignore (Ok_hole esc)
          | Error d ->
            problems := (file, line, Rejected d) :: !problems)
       | _ -> (* island_ssr / CSRF injections and other non-literal parts *)
         ())
    parts;
  if not (A.is_valid_terminal !ctx) then
    problems :=
      (file, line, Bad_terminal (C.describe !ctx)) :: !problems

let rec find_sigils tbl file (e : March_ast.Ast.expr) =
  let open March_ast.Ast in
  let go = find_sigils tbl file in
  match e with
  | ESigil ("H", content, sp) ->
    scan_sigil tbl file sp.start_line content;
    go content
  | ESigil (_, c, _) -> go c
  | EApp (f, args, _) -> go f; List.iter go args
  | ECon (_, args, _) -> List.iter go args
  | ELet (b, _) -> go b.bind_expr
  | ELetQ (_, a, b, _) -> go a; go b
  | ELetFn (_, _, _, b, _) -> go b
  | EIf (a, b, c, _) -> go a; go b; go c
  | ECond (arms, _) -> List.iter (fun (c, b) -> go c; go b) arms
  | EMatch (s, branches, _) ->
    go s;
    List.iter (fun (b : branch) ->
        (match b.branch_guard with Some g -> go g | None -> ()); go b.branch_body)
      branches
  | EBlock (es, _) -> List.iter go es
  | ELam (_, b, _) -> go b
  | ETuple (es, _) -> List.iter go es
  | ERecord (fs, _) -> List.iter (fun (_, e) -> go e) fs
  | ERecordUpdate (e, fs, _) -> go e; List.iter (fun (_, e) -> go e) fs
  | EField (e, _, _) -> go e
  | EPipe (a, b, _) -> go a; go b
  | EAnnot (e, _, _) -> go e
  | EAtom (_, es, _) -> List.iter go es
  | ESend (a, b, _) -> go a; go b
  | ESpawn (e, _) -> go e
  | EAssert (a, _) -> go a
  | _ -> ()

let rec find_in_decls tbl file (ds : March_ast.Ast.decl list) =
  let open March_ast.Ast in
  List.iter
    (fun d ->
       match d with
       | DFn (f, _) ->
         List.iter (fun (c : fn_clause) -> find_sigils tbl file c.fc_body) f.fn_clauses
       | DLet (_, b, _) -> find_sigils tbl file b.bind_expr
       | DMod (_, _, inner, _) -> find_in_decls tbl file inner
       | _ -> ())
    ds

let scan_file tbl path =
  try
    let ic = open_in path in
    let n = in_channel_length ic in
    let src = really_input_string ic n in
    close_in ic;
    let lexbuf = Lexing.from_string src in
    let m =
      March_parser.Parser.module_
        (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
    in
    find_in_decls tbl path m.March_ast.Ast.mod_decls
  with _ ->
    (* A file this scanner cannot parse is not a finding about escaping; the
       corpus predates this compiler and has its own drift. Counted, not
       reported as a template problem. *)
    ()

let rec walk dir f =
  match Sys.readdir dir with
  | entries ->
    Array.iter
      (fun e ->
         let p = Filename.concat dir e in
         if e = ".march" || e = ".claude" || e = "_build" || e = ".git" then ()
         else if Sys.is_directory p then walk p f
         else if Filename.check_suffix p ".march" then f p)
      entries
  | exception Sys_error _ -> ()

let () =
  if Array.length Sys.argv < 3 then begin
    prerr_endline "usage: scan_templates.exe <table.tbl> <dir> [<dir> ...]";
    exit 2
  end;
  let tbl =
    match P.parse_file Sys.argv.(1) with
    | Ok t -> A.compile t
    | Error e -> prerr_endline e; exit 2
  in
  for i = 2 to Array.length Sys.argv - 1 do
    walk Sys.argv.(i) (scan_file tbl)
  done;
  Printf.printf "templates: %d   holes: %d\n\n" !n_templates !n_holes;
  print_endline "escaper selected per hole:";
  Hashtbl.iter (fun k v -> Printf.printf "  %-16s %d\n" k v) escaper_counts;
  let chg = List.rev !changed in
  Printf.printf "\nBEHAVIOUR CHANGES (compile fine, output differs): %d\n"
    (List.length chg);
  List.iter (fun (f, l, e) -> Printf.printf "  %-14s %s:%d\n" e f l) chg;
  let probs = List.rev !problems in
  Printf.printf "\nWOULD-BREAK: %d\n" (List.length probs);
  List.iter
    (fun (f, l, p) ->
       let kind, msg =
         match p with
         | Rejected d -> "REJECT", d
         | Literal_error m -> "NO-RULE", m
         | Bad_terminal d -> "UNCLOSED", "template ends " ^ d
         | Ok_hole _ -> "OK", ""
       in
       Printf.printf "  %-8s %s:%d\n           %s\n" kind f l msg)
    probs
