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

(* ------------------------------------------------------------------ *)
(* Call graph + capability coverage                                     *)
(* ------------------------------------------------------------------ *)

(** Collect direct function-call names from an expression. *)
let rec calls_in_expr acc (e : Ast.expr) =
  let acc = match e with
    | Ast.EApp (Ast.EVar n, _, _) -> n.Ast.txt :: acc
    | Ast.EApp (Ast.EField (Ast.EVar m, f, _), _, _) ->
      (m.Ast.txt ^ "." ^ f.Ast.txt) :: acc
    | _ -> acc
  in
  match e with
  | Ast.EApp (f, args, _)      -> List.fold_left calls_in_expr (calls_in_expr acc f) args
  | Ast.ELet (b, _)            -> calls_in_expr acc b.Ast.bind_expr
  | Ast.EBlock (es, _)         -> List.fold_left calls_in_expr acc es
  | Ast.EMatch (s, brs, _)     ->
    let acc = calls_in_expr acc s in
    List.fold_left (fun a br -> calls_in_expr a br.Ast.branch_body) acc brs
  | Ast.EIf (c, t, f, _)       ->
    calls_in_expr (calls_in_expr (calls_in_expr acc c) t) f
  | Ast.EPipe (x, y, _)
  | Ast.ESend (x, y, _)        -> calls_in_expr (calls_in_expr acc x) y
  | Ast.ETuple (es, _)
  | Ast.EAtom (_, es, _)
  | Ast.ECon (_, es, _)        -> List.fold_left calls_in_expr acc es
  | Ast.ERecord (fs, _)        -> List.fold_left (fun a (_, e) -> calls_in_expr a e) acc fs
  | Ast.ERecordUpdate (e, fs, _) ->
    List.fold_left (fun a (_, e) -> calls_in_expr a e) (calls_in_expr acc e) fs
  | Ast.EField (e, _, _) | Ast.EAnnot (e, _, _)
  | Ast.ESpawn (e, _)   | Ast.EAssert (e, _)   -> calls_in_expr acc e
  | Ast.ELam (_, b, _)  | Ast.ELetFn (_, _, _, b, _) -> calls_in_expr acc b
  | _ -> acc

let fn_body_calls (fn : Ast.fn_def) : string list =
  List.concat_map (fun (cl : Ast.fn_clause) -> calls_in_expr [] cl.Ast.fc_body)
    fn.Ast.fn_clauses
  |> List.sort_uniq String.compare

let expr_calls (e : Ast.expr) : string list =
  calls_in_expr [] e |> List.sort_uniq String.compare

type coverage_data = {
  cv_fn_calls  : (string, string list) Hashtbl.t;
  cv_fn_file   : (string, string) Hashtbl.t;
  cv_file_caps : (string, string list) Hashtbl.t;
  cv_tests     : (string * string list) list;
}

let build_coverage_data files =
  let fn_calls  = Hashtbl.create 64 in
  let fn_file   = Hashtbl.create 64 in
  let file_caps = Hashtbl.create 16 in
  let tests     = ref [] in
  let rec walk_decls ~prefix ~file decls =
    List.iter (walk_decl ~prefix ~file) decls
  and walk_decl ~prefix ~file (d : Ast.decl) =
    match d with
    | Ast.DFn (fn, _) ->
      let qname = if prefix = "" then fn.Ast.fn_name.Ast.txt
                  else prefix ^ "." ^ fn.Ast.fn_name.Ast.txt in
      Hashtbl.replace fn_calls qname (fn_body_calls fn);
      Hashtbl.replace fn_file  qname file
    | Ast.DMod (name, _, inner, _) ->
      let p = if prefix = "" then name.Ast.txt
              else prefix ^ "." ^ name.Ast.txt in
      walk_decls ~prefix:p ~file inner
    | Ast.DNeeds (paths, _) ->
      let caps = List.map (fun path ->
          String.concat "." (List.map (fun (n : Ast.name) -> n.txt) path)
        ) paths in
      let existing = match Hashtbl.find_opt file_caps file with
        | Some cs -> cs | None -> []
      in
      Hashtbl.replace file_caps file
        (List.sort_uniq String.compare (existing @ caps))
    | Ast.DTest (td, _) ->
      tests := (td.Ast.test_name, expr_calls td.Ast.test_body) :: !tests
    | Ast.DDescribe (_, inner, _) -> walk_decls ~prefix ~file inner
    | _ -> ()
  in
  List.iter (fun (path, decls) ->
      walk_decls ~prefix:"" ~file:path decls
    ) files;
  { cv_fn_calls = fn_calls; cv_fn_file = fn_file;
    cv_file_caps = file_caps; cv_tests = !tests }

(** BFS from [entry_calls] collecting all transitively reachable fn names. *)
let reachable_fns (cv : coverage_data) (entry_calls : string list) : string list =
  let visited = Hashtbl.create 32 in
  let queue = Queue.create () in
  List.iter (fun n -> Queue.push n queue) entry_calls;
  while not (Queue.is_empty queue) do
    let n = Queue.pop queue in
    if not (Hashtbl.mem visited n) then begin
      Hashtbl.replace visited n ();
      (match Hashtbl.find_opt cv.cv_fn_calls n with
       | Some callees -> List.iter (fun c -> Queue.push c queue) callees
       | None -> ())
    end
  done;
  Hashtbl.fold (fun k () acc -> k :: acc) visited []

(** All capability paths declared in files containing any of [fn_names]. *)
let caps_for_fns (cv : coverage_data) (fn_names : string list) : string list =
  let caps = ref [] in
  List.iter (fun fn ->
      match Hashtbl.find_opt cv.cv_fn_file fn with
      | None -> ()
      | Some f ->
        (match Hashtbl.find_opt cv.cv_file_caps f with
         | None -> ()
         | Some cs -> caps := cs @ !caps)
    ) fn_names;
  List.sort_uniq String.compare !caps

let coverage ~dir () =
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
    let parsed = List.filter_map (fun path ->
        match parse_file path with
        | Ok decls -> Some (path, decls)
        | Error msg ->
          Printf.eprintf "forge cap: %s: %s\n%!" path msg; None
      ) files in
    let cv = build_coverage_data parsed in
    let all_caps =
      Hashtbl.fold (fun _ caps acc ->
          List.fold_left (fun a c -> if List.mem c a then a else c :: a) acc caps
        ) cv.cv_file_caps []
      |> List.sort String.compare
    in
    if all_caps = [] then begin
      Printf.printf "no `needs` declarations found under %s\n%!" root; Ok ()
    end else begin
      let cap_to_tests : (string, string list) Hashtbl.t = Hashtbl.create 16 in
      List.iter (fun (test_name, entry_calls) ->
          let reachable = reachable_fns cv entry_calls in
          let caps = caps_for_fns cv (entry_calls @ reachable) in
          List.iter (fun cap ->
              let existing = match Hashtbl.find_opt cap_to_tests cap with
                | Some ts -> ts | None -> []
              in
              if not (List.mem test_name existing) then
                Hashtbl.replace cap_to_tests cap (test_name :: existing)
            ) caps
        ) cv.cv_tests;
      let covered   = List.filter (fun c ->  Hashtbl.mem cap_to_tests c) all_caps in
      let uncovered = List.filter (fun c -> not (Hashtbl.mem cap_to_tests c)) all_caps in
      if covered <> [] then begin
        Printf.printf "Covered:\n";
        List.iter (fun cap ->
            let n = List.length (match Hashtbl.find_opt cap_to_tests cap with
                | Some ts -> ts | None -> []) in
            Printf.printf "  %-30s  %d test%s\n%!" cap n (if n = 1 then "" else "s")
          ) covered
      end;
      if uncovered <> [] then begin
        if covered <> [] then Printf.printf "\n";
        Printf.printf "Uncovered:\n";
        List.iter (fun cap -> Printf.printf "  %s\n%!" cap) uncovered
      end;
      let total = List.length all_caps in
      let n_cov  = List.length covered in
      Printf.printf "\n%d/%d capabilities covered (%d%%)\n%!"
        n_cov total (if total > 0 then n_cov * 100 / total else 0);
      Ok ()
    end
  end

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

(* ------------------------------------------------------------------ *)
(* forge cap audit <binary> — read capabilities from a compiled       *)
(* executable (specs/2026-08-03-forge-cap-audit-design.md §5).        *)
(* ------------------------------------------------------------------ *)

let foreign_caps = ["IO.Foreign"; "IO.Foreign.Blocking"]

let is_foreign c = List.mem c foreign_caps

(* Witness column: which runtime symbols back a cap (from the symbol
   channel), so the report is actionable rather than a bare list. *)
let witnesses_for (t : Cap_binary.t) cap =
  List.filter
    (fun s ->
       match March_caps.Cap_symbols.cap_of_symbol s with
       | Some c -> c = cap
       | None -> false)
    t.Cap_binary.rt_symbols

let build_str = function
  | Cap_binary.Dead_stripped -> "dead-stripped"
  | Cap_binary.Unstripped -> "UNSTRIPPED"
  | Cap_binary.Symbols_removed -> "symbols-removed"

(* coverage: "full" only when every channel we rely on is intact and no
   foreign code is present.  Anything else names its limitation — the gate
   fails closed on all of them (design §5.2, §8). *)
let coverage_of (t : Cap_binary.t) =
  match t.Cap_binary.build with
  | Cap_binary.Unstripped -> `Limited "unstripped build"
  | Cap_binary.Symbols_removed -> `Limited "symbols removed"
  | Cap_binary.Dead_stripped ->
    if List.exists is_foreign t.Cap_binary.caps
    then `Partial "foreign code"
    else `Full

let coverage_str = function
  | `Full -> "full"
  | `Partial r -> Printf.sprintf "partial (%s)" r
  | `Limited r -> Printf.sprintf "limited (%s)" r

let render_report ~bin (t : Cap_binary.t) =
  let buf = Buffer.create 512 in
  let non_foreign = List.filter (fun c -> not (is_foreign c)) t.Cap_binary.caps in
  Buffer.add_string buf (Printf.sprintf "Capabilities — %s\n" bin);
  (match t.Cap_binary.build with
   | Cap_binary.Unstripped ->
     Buffer.add_string buf
       "  (not listed: this binary was linked without dead-strip, so every\n\
       \   runtime capability symbol is present regardless of use.  Rebuild\n\
       \   with a current compiler for a meaningful capability list.)\n"
   | Cap_binary.Symbols_removed ->
     Buffer.add_string buf
       "  (not listed: symbol names were stripped from this binary; the\n\
       \   marker and symbol channels are unavailable.)\n"
   | Cap_binary.Dead_stripped ->
     if non_foreign = [] then
       Buffer.add_string buf "  (none — no capability-bearing runtime entries present)\n"
     else
       List.iter
         (fun cap ->
            let w = witnesses_for t cap in
            let w_str = match w with
              | [] -> "" | l -> "  [" ^ String.concat ", " l ^ "]" in
            Buffer.add_string buf (Printf.sprintf "  %-22s%s\n" cap w_str))
         non_foreign);
  if List.exists is_foreign t.Cap_binary.caps then begin
    let blocking = List.mem "IO.Foreign.Blocking" t.Cap_binary.caps in
    Buffer.add_string buf
      (Printf.sprintf
         "\nForeign code (IO.Foreign%s) — extern C declarations present\n\
         \  Capability analysis stops at the FFI boundary. The caps above\n\
         \  describe March code only; what the linked C code does is outside\n\
         \  the compiler's knowledge and is not covered by this report.\n"
         (if blocking then ", includes blocking externs" else ""));
  end;
  Buffer.add_string buf
    (Printf.sprintf "\nbuild: %s    coverage: %s\n"
       (build_str t.Cap_binary.build)
       (coverage_str (coverage_of t)));
  Buffer.contents buf

let render_json ~bin (t : Cap_binary.t) =
  let strs l = `List (List.map (fun s -> `String s) l) in
  Yojson.Safe.pretty_to_string
    (`Assoc [
        ("binary", `String bin);
        ("caps", strs t.Cap_binary.caps);
        ("markers", strs t.Cap_binary.markers);
        ("rt_symbols", strs t.Cap_binary.rt_symbols);
        ("build", `String (build_str t.Cap_binary.build));
        ("coverage", `String (coverage_str (coverage_of t)));
        ("manifest",
         match t.Cap_binary.manifest with
         | None -> `Null
         | Some j ->
           (try Yojson.Safe.from_string j with _ -> `String j));
      ])

(* Gate evaluation.  Fail-closed: any coverage other than `Full fails unless
   the specific limitation was explicitly allowed (--allow-foreign covers
   exactly the foreign-code case, nothing else). *)
let gate_violations ~deny ~allow_only ~allow_foreign (t : Cap_binary.t) =
  let subsumes = March_caps.Cap_lattice.cap_subsumes in
  let violations = ref [] in
  (match coverage_of t with
   | `Full -> ()
   | `Partial _ when allow_foreign -> ()
   | (`Partial _ | `Limited _) as c ->
     violations :=
       Printf.sprintf
         "coverage is %s — gate requires full coverage%s"
         (coverage_str c)
         (match c with
          | `Partial _ -> " (pass --allow-foreign to accept FFI)"
          | _ -> "")
       :: !violations);
  let effective = List.filter (fun c -> not (is_foreign c)) t.Cap_binary.caps in
  List.iter
    (fun d ->
       List.iter
         (fun c ->
            if subsumes d c then
              violations :=
                Printf.sprintf "denied capability: %s (via --deny %s)" c d
                :: !violations)
         effective)
    deny;
  (match allow_only with
   | None -> ()
   | Some allowed ->
     List.iter
       (fun c ->
          if not (List.exists (fun a -> subsumes a c) allowed) then
            violations :=
              Printf.sprintf "capability not in --allow-only set: %s" c
              :: !violations)
       effective);
  List.rev !violations

let audit ~bin ~json ~deny ~allow_only ~allow_foreign () =
  match Cap_binary.read bin with
  | Error e -> Error e
  | Ok t ->
    if json then print_string (render_json ~bin t)
    else print_string (render_report ~bin t);
    (match gate_violations ~deny ~allow_only ~allow_foreign t with
     | [] -> Ok ()
     | vs ->
       List.iter (fun v -> Printf.eprintf "forge cap audit: %s\n%!" v) vs;
       Error (Printf.sprintf "%d gate violation(s)" (List.length vs)))
