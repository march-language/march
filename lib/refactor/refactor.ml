(** Project-wide, parser-based refactoring engine for March.

    Operates on the raw (pre-desugar) AST so it edits real source constructs and
    never touches strings or comments. All transforms produce byte-offset
    [edit]s against a file's source text; edits are applied in descending order
    so earlier offsets stay valid. Every edited file is re-parsed before being
    written, so a transform never leaves source that no longer parses. *)

module Ast = March_ast.Ast

(* ------------------------------------------------------------------ *)
(* Source files                                                        *)
(* ------------------------------------------------------------------ *)

(** Recursively collect every `.march` file under [root] (sorted, so runs are
    deterministic). Skips hidden dirs and build/cache output. *)
let discover_march_files root : string list =
  let skip name =
    name = "_build" || name = ".git" || name = ".march" || name = ".forge"
    || name = "_build_wt" || (String.length name > 0 && name.[0] = '.')
  in
  let acc = ref [] in
  let rec walk dir =
    match Sys.readdir dir with
    | exception _ -> ()
    | entries ->
      Array.sort String.compare entries;
      Array.iter (fun name ->
          let path = Filename.concat dir name in
          if (try Sys.is_directory path with _ -> false) then
            (if not (skip name) then walk path)
          else if Filename.check_suffix name ".march" then
            acc := path :: !acc)
        entries
  in
  walk root;
  List.rev !acc

let read_file path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
      let n = in_channel_length ic in
      let b = Bytes.create n in
      really_input ic b 0 n; Bytes.to_string b)

let write_file path content =
  let oc = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out oc) (fun () -> output_string oc content)

let parse_string ~filename src : Ast.module_ option =
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
  try
    Some (March_parser.Parser.module_
            (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf)
  with _ -> None

(* ------------------------------------------------------------------ *)
(* Edits                                                               *)
(* ------------------------------------------------------------------ *)

type edit = { e_start : int; e_stop : int; e_repl : string }

(** Byte offset of (0-indexed [line], [col]) in [src]. *)
let offset_of_pos src line col =
  let n = String.length src in
  let cur = ref 0 and i = ref 0 in
  while !i < n && !cur < line do
    if src.[!i] = '\n' then incr cur;
    incr i
  done;
  !i + col

(** Byte [start, stop) of a span in [src]. *)
let span_bounds src (sp : Ast.span) =
  ( offset_of_pos src (sp.Ast.start_line - 1) sp.Ast.start_col,
    offset_of_pos src (sp.Ast.end_line - 1) sp.Ast.end_col )

(** Apply [edits] to [src] (descending by start; overlapping edits dropped). *)
let apply_edits src (edits : edit list) : string =
  let sorted =
    List.sort (fun a b -> compare b.e_start a.e_start) edits in
  let buf = Buffer.create (String.length src) in
  let result = ref src in
  let last_start = ref (String.length src + 1) in
  List.iter (fun e ->
      if e.e_start >= 0 && e.e_stop <= String.length !result
         && e.e_stop <= !last_start then begin
        let before = String.sub !result 0 e.e_start in
        let after = String.sub !result e.e_stop (String.length !result - e.e_stop) in
        result := before ^ e.e_repl ^ after;
        last_start := e.e_start
      end)
    sorted;
  ignore buf;
  !result

(* ------------------------------------------------------------------ *)
(* Name visitor                                                        *)
(* ------------------------------------------------------------------ *)

(** Syntactic category of a name occurrence — used by [--kind] filtering. *)
type site =
  | SFn       (* function definition name, local fn name *)
  | SValue    (* value reference: EVar, call callee *)
  | SType     (* type definition / type reference *)
  | SCtor     (* constructor definition / use / pattern *)
  | SModule   (* module name / qualifier / import path segment *)
  | SField    (* record field: definition, access, pattern *)
  | SPat      (* let/param binder name *)

let kind_of_string = function
  | "fn"     -> Some [SFn; SValue]
  | "type"   -> Some [SType]
  | "ctor"   -> Some [SCtor]
  | "module" -> Some [SModule]
  | "field"  -> Some [SField]
  | "var"    -> Some [SValue; SPat]
  | "any"    -> None   (* no filter *)
  | _        -> None

(** Visit every name-bearing node, calling [f site name]. Covers the
    constructs a project-wide rename cares about; rarely-renamed forms
    (extern/sig/needs/app/deriving) are skipped. *)
let iter_names (f : site -> Ast.name -> unit) (m : Ast.module_) : unit =
  let rec ty (t : Ast.ty) =
    match t with
    | Ast.TyCon (n, args) -> f SType n; List.iter ty args
    | Ast.TyVar n -> f SType n
    | Ast.TyArrow (a, b) -> ty a; ty b
    | Ast.TyTuple ts -> List.iter ty ts
    | Ast.TyRecord fs -> List.iter (fun (n, t) -> f SField n; ty t) fs
    | Ast.TyLinear (_, t) -> ty t
    | Ast.TyNatOp (_, a, b) -> ty a; ty b
    | Ast.TyChan (r, p) -> f SType r; f SType p
    | Ast.TyNat _ -> ()
  and pat (p : Ast.pattern) =
    match p with
    | Ast.PatWild _ | Ast.PatLit _ -> ()
    | Ast.PatVar n -> f SPat n
    | Ast.PatCon (n, ps) -> f SCtor n; List.iter pat ps
    | Ast.PatAtom (_, ps, _) -> List.iter pat ps
    | Ast.PatTuple (ps, _) -> List.iter pat ps
    | Ast.PatRecord (fs, _) -> List.iter (fun (n, p) -> f SField n; pat p) fs
    | Ast.PatAs (p, n, _) -> pat p; f SPat n
  and param (p : Ast.param) =
    f SPat p.Ast.param_name;
    (match p.Ast.param_ty with Some t -> ty t | None -> ())
  and fn_param = function
    | Ast.FPPat p -> pat p
    | Ast.FPNamed p -> param p
    | Ast.FPDefault (p, e) -> param p; expr e
  and binding (b : Ast.binding) =
    pat b.Ast.bind_pat;
    (match b.Ast.bind_ty with Some t -> ty t | None -> ());
    expr b.Ast.bind_expr
  and expr (e : Ast.expr) =
    match e with
    | Ast.ELit _ | Ast.EResultRef _ | Ast.EDbg (None, _) -> ()
    | Ast.EVar n -> f SValue n
    | Ast.EHole (Some n, _) -> f SValue n
    | Ast.EHole (None, _) -> ()
    | Ast.EApp (g, args, _) -> expr g; List.iter expr args
    | Ast.ECon (n, args, _) -> f SCtor n; List.iter expr args
    | Ast.ELam (ps, body, _) -> List.iter param ps; expr body
    | Ast.EBlock (es, _) -> List.iter expr es
    | Ast.ELet (b, _) -> binding b
    | Ast.EMatch (subj, brs, _) ->
      expr subj;
      List.iter (fun (br : Ast.branch) ->
          pat br.branch_pat;
          (match br.branch_guard with Some g -> expr g | None -> ());
          expr br.branch_body) brs
    | Ast.ETuple (es, _) -> List.iter expr es
    | Ast.ERecord (fs, _) -> List.iter (fun (n, e) -> f SField n; expr e) fs
    | Ast.ERecordUpdate (e, fs, _) ->
      expr e; List.iter (fun (n, e) -> f SField n; expr e) fs
    (* `Mod.field` — the qualifier ECon is a module reference, not a ctor. *)
    | Ast.EField (Ast.ECon (m, [], _), fld, _) -> f SModule m; f SField fld
    | Ast.EField (e, fld, _) -> expr e; f SField fld
    | Ast.EIf (c, t, el, _) -> expr c; expr t; expr el
    | Ast.ECond (arms, _) -> List.iter (fun (c, b) -> expr c; expr b) arms
    | Ast.EPipe (a, b, _) | Ast.ESend (a, b, _) -> expr a; expr b
    | Ast.EAnnot (e, t, _) -> expr e; ty t
    | Ast.EAtom (_, es, _) -> List.iter expr es
    | Ast.ESpawn (e, _) | Ast.EAssert (e, _) | Ast.ESigil (_, e, _)
    | Ast.EDbg (Some e, _) -> expr e
    | Ast.ELetFn (n, ps, rt, body, _) ->
      f SFn n; List.iter param ps;
      (match rt with Some t -> ty t | None -> ()); expr body
  in
  let fn_def (fn : Ast.fn_def) =
    f SFn fn.Ast.fn_name;
    (match fn.Ast.fn_ret_ty with Some t -> ty t | None -> ());
    List.iter (fun (cl : Ast.fn_clause) ->
        List.iter fn_param cl.fc_params;
        (match cl.fc_guard with Some g -> expr g | None -> ());
        expr cl.fc_body) fn.Ast.fn_clauses
  in
  let type_def name params (td : Ast.type_def) =
    f SType name; List.iter (f SType) params;
    match td with
    | Ast.TDAlias t -> ty t
    | Ast.TDVariant vs ->
      List.iter (fun (v : Ast.variant) -> f SCtor v.var_name; List.iter ty v.var_args) vs
    | Ast.TDRecord fs ->
      List.iter (fun (fl : Ast.field) -> f SField fl.fld_name; ty fl.fld_ty) fs
  in
  let rec decl (d : Ast.decl) =
    match d with
    | Ast.DFn (fn, _) -> fn_def fn
    | Ast.DLet (_, b, _) -> binding b
    | Ast.DType (_, n, ps, td, _) -> type_def n ps td
    | Ast.DActor (_, n, adef, _) ->
      f SType n;
      List.iter (fun (fl : Ast.field) -> f SField fl.fld_name; ty fl.fld_ty)
        adef.Ast.actor_state;
      expr adef.Ast.actor_init;
      List.iter (fun (h : Ast.actor_handler) ->
          f SCtor h.ah_msg; List.iter param h.ah_params; expr h.ah_body)
        adef.Ast.actor_handlers
    | Ast.DMod (n, _, ds, _) -> f SModule n; List.iter decl ds
    | Ast.DInterface (i, _) ->
      f SType i.Ast.iface_name; f SType i.Ast.iface_param;
      List.iter (fun (md : Ast.method_decl) ->
          f SFn md.md_name; ty md.md_ty;
          match md.md_default with Some e -> expr e | None -> ())
        i.Ast.iface_methods
    | Ast.DImpl (im, _) ->
      f SType im.Ast.impl_iface; ty im.Ast.impl_ty;
      List.iter (fun (n, fn) -> f SFn n; fn_def fn) im.Ast.impl_methods
    | Ast.DProtocol (n, _, _) -> f SType n
    | Ast.DUse (u, _) -> List.iter (f SModule) u.Ast.use_path
    | Ast.DAlias (a, _) ->
      List.iter (f SModule) a.Ast.alias_path; f SModule a.Ast.alias_name
    | Ast.DTest (t, _) -> expr t.Ast.test_body
    | Ast.DDescribe (_, ds, _) -> List.iter decl ds
    | Ast.DSetup (e, _) | Ast.DSetupAll (e, _) -> expr e
    | _ -> ()
  in
  List.iter decl m.Ast.mod_decls

(* ------------------------------------------------------------------ *)
(* Rename                                                              *)
(* ------------------------------------------------------------------ *)

type file_change = { fc_path : string; fc_old : string; fc_new : string; fc_count : int }

type outcome = {
  changes : file_change list;     (* files whose content changed *)
  skipped : (string * string) list; (* (path, reason) — e.g. would not re-parse *)
}

(** Collect rename edits for one file's [src]. [matches name] decides whether an
    occurrence is renamed; [kinds] (None = any) filters by syntactic site. *)
let rename_edits ~src ~filename ~(matches : string -> string option)
    ~(kinds : site list option) : edit list =
  match parse_string ~filename src with
  | None -> []
  | Some m ->
    let edits = ref [] in
    let kind_ok site = match kinds with None -> true | Some ks -> List.mem site ks in
    iter_names (fun site name ->
        if kind_ok site then
          match matches name.Ast.txt with
          | None -> ()
          | Some repl ->
            let (s, e) = span_bounds src name.Ast.span in
            (* Guard: the span must actually cover the old identifier text. *)
            if e > s && e <= String.length src
               && String.sub src s (e - s) = name.Ast.txt then
              edits := { e_start = s; e_stop = e; e_repl = repl } :: !edits)
      m;
    !edits

(** Rename across every `.march` file under [root]. [matches] maps an old name to
    its replacement (or None to leave it). Returns the per-file outcome; writes
    files unless [dry_run]. *)
let rename_project ~root ~matches ~kinds ~dry_run : outcome =
  let files = discover_march_files root in
  let changes = ref [] and skipped = ref [] in
  List.iter (fun path ->
      match (try Some (read_file path) with _ -> None) with
      | None -> ()
      | Some src ->
        let edits = rename_edits ~src ~filename:path ~matches ~kinds in
        if edits <> [] then begin
          let updated = apply_edits src edits in
          (* Never write source that no longer parses. *)
          match parse_string ~filename:path updated with
          | None -> skipped := (path, "result would not parse") :: !skipped
          | Some _ ->
            if not dry_run then write_file path updated;
            changes := { fc_path = path; fc_old = src; fc_new = updated;
                         fc_count = List.length edits } :: !changes
        end)
    files;
  { changes = List.rev !changes; skipped = List.rev !skipped }

(** Convenience: rename a single exact name [old_name] to [new_name]. *)
let rename_symbol ~root ~old_name ~new_name ~kind ~dry_run : outcome =
  let kinds = kind_of_string kind in
  let matches s = if s = old_name then Some new_name else None in
  rename_project ~root ~matches ~kinds ~dry_run

(** Regex bulk rename: every name fully matching [regex] is rewritten with
    [replacement] (Str backreferences like \\1 allowed). *)
let rename_pattern ~root ~regex ~replacement ~kind ~dry_run : outcome =
  let kinds = kind_of_string kind in
  let re = Str.regexp regex in
  let matches s =
    if Str.string_match re s 0 && Str.match_end () = String.length s
    then Some (Str.global_replace re replacement s)
    else None
  in
  rename_project ~root ~matches ~kinds ~dry_run

(* ------------------------------------------------------------------ *)
(* fix — convention codemods (lint-driven naming renames)              *)
(* ------------------------------------------------------------------ *)

(** Collect function definition names across a module (nested modules, interface
    and impl methods, describe blocks). *)
let collect_fn_defs (m : Ast.module_) : string list =
  let acc = ref [] in
  let rec decl (d : Ast.decl) =
    match d with
    | Ast.DFn (fn, _) -> acc := fn.Ast.fn_name.txt :: !acc
    | Ast.DMod (_, _, ds, _) | Ast.DDescribe (_, ds, _) -> List.iter decl ds
    | Ast.DInterface (i, _) ->
      List.iter (fun (md : Ast.method_decl) -> acc := md.Ast.md_name.txt :: !acc)
        i.Ast.iface_methods
    | Ast.DImpl (im, _) ->
      List.iter (fun (n, _) -> acc := n.Ast.txt :: !acc) im.Ast.impl_methods
    | _ -> ()
  in
  List.iter decl m.Ast.mod_decls;
  !acc

(** Apply the safe naming convention fixes project-wide: any function whose name
    is not snake_case is renamed to its snake_case form everywhere. (Type and
    constructor names are parser-forced to start uppercase, so PascalCase
    violations cannot occur in valid source.) *)
let fix_project ~root ~dry_run : outcome =
  let files = discover_march_files root in
  let map = Hashtbl.create 64 in
  List.iter (fun path ->
      match (try Some (read_file path) with _ -> None) with
      | None -> ()
      | Some src ->
        (match parse_string ~filename:path src with
         | None -> ()
         | Some m ->
           List.iter (fun name ->
               if not (March_lint.Lint.is_snake_case name) then
                 let snake = March_lint.Lint.to_snake_case name in
                 if snake <> name && March_lint.Lint.is_snake_case snake then
                   Hashtbl.replace map name snake)
             (collect_fn_defs m)))
    files;
  let matches s = Hashtbl.find_opt map s in
  rename_project ~root ~matches ~kinds:None ~dry_run

(* ------------------------------------------------------------------ *)
(* move — relocate a top-level declaration to another file             *)
(* ------------------------------------------------------------------ *)

let decl_span (d : Ast.decl) : Ast.span =
  match d with
  | Ast.DFn (_, sp) | Ast.DLet (_, _, sp) | Ast.DType (_, _, _, _, sp)
  | Ast.DActor (_, _, _, sp) | Ast.DProtocol (_, _, sp) | Ast.DMod (_, _, _, sp)
  | Ast.DSig (_, _, sp) | Ast.DInterface (_, sp) | Ast.DImpl (_, sp)
  | Ast.DExtern (_, sp) | Ast.DUse (_, sp) | Ast.DAlias (_, sp)
  | Ast.DNeeds (_, sp) | Ast.DApp (_, sp) | Ast.DDeriving (_, _, sp)
  | Ast.DTest (_, sp) | Ast.DDescribe (_, _, sp) | Ast.DSetup (_, sp)
  | Ast.DSetupAll (_, sp) -> sp

(** Top-level definition name of a declaration, if it has one. *)
let decl_def_name (d : Ast.decl) : string option =
  match d with
  | Ast.DFn (fn, _) -> Some fn.Ast.fn_name.txt
  | Ast.DType (_, n, _, _, _) | Ast.DActor (_, n, _, _) | Ast.DProtocol (n, _, _)
  | Ast.DMod (n, _, _, _) -> Some n.Ast.txt
  | Ast.DInterface (i, _) -> Some i.Ast.iface_name.Ast.txt
  | _ -> None

let module_name_of_file path =
  let base = Filename.remove_extension (Filename.basename path) in
  if base = "" then "M"
  else String.make 1 (Char.uppercase_ascii base.[0]) ^ String.sub base 1 (String.length base - 1)

(** Move the top-level declaration named [decl_name] (searched across the
    project) into [dest]. Creates [dest] with a module wrapper if it does not
    exist, else inserts before its final `end`. Removes the declaration from its
    source file. *)
let move_decl ~root ~decl_name ~dest ~dry_run : (outcome, string) result =
  let files = discover_march_files root in
  (* Find the source decl (search direct children of each module). *)
  let found = ref None in
  List.iter (fun path ->
      if !found = None then
        match (try Some (read_file path) with _ -> None) with
        | None -> ()
        | Some src ->
          (match parse_string ~filename:path src with
           | None -> ()
           | Some m ->
             let rec scan decls =
               List.iter (fun d ->
                   if !found = None then
                     match decl_def_name d with
                     | Some n when n = decl_name -> found := Some (path, src, d)
                     | _ -> (match d with Ast.DMod (_, _, ds, _) -> scan ds | _ -> ()))
                 decls
             in
             scan m.Ast.mod_decls))
    files;
  match !found with
  | None -> Error (Printf.sprintf "no top-level declaration named `%s` found" decl_name)
  | Some (src_path, src, d) ->
    if Filename.basename src_path = Filename.basename dest && src_path = dest then
      Error "source and destination are the same file"
    else begin
      let sp = decl_span d in
      let (s, e) = span_bounds src sp in
      if not (e > s && e <= String.length src) then
        Error "could not locate the declaration's source span"
      else begin
        let decl_text = String.sub src s (e - s) in
        (* Remove from source: delete the decl plus a trailing blank line. *)
        let e' =
          let n = String.length src in
          let j = ref e in
          while !j < n && (src.[!j] = ' ' || src.[!j] = '\t') do incr j done;
          if !j < n && src.[!j] = '\n' then !j + 1 else e
        in
        let src_updated =
          String.sub src 0 s ^ String.sub src e' (String.length src - e') in
        (* Build / update the destination. *)
        let dest_existing = if Sys.file_exists dest then Some (read_file dest) else None in
        let dest_updated =
          match dest_existing with
          | None ->
            Printf.sprintf "mod %s do\n  %s\nend\n" (module_name_of_file dest) decl_text
          | Some dsrc ->
            (* Insert before the last `end` in the file. *)
            (match parse_string ~filename:dest dsrc with
             | None -> dsrc ^ "\n" ^ decl_text ^ "\n"
             | Some _ ->
               let idx =
                 try Some (Str.search_backward (Str.regexp "end") dsrc (String.length dsrc))
                 with Not_found -> None in
               match idx with
               | Some i -> String.sub dsrc 0 i ^ "  " ^ decl_text ^ "\n" ^
                           String.sub dsrc i (String.length dsrc - i)
               | None -> dsrc ^ "\n" ^ decl_text ^ "\n")
        in
        (* Verify both still parse. *)
        match parse_string ~filename:src_path src_updated,
              parse_string ~filename:dest dest_updated with
        | Some _, Some _ ->
          if not dry_run then begin
            write_file src_path src_updated;
            write_file dest dest_updated
          end;
          Ok { changes = [
              { fc_path = src_path; fc_old = src; fc_new = src_updated; fc_count = 1 };
              { fc_path = dest; fc_old = Option.value ~default:"" dest_existing;
                fc_new = dest_updated; fc_count = 1 } ];
            skipped = [] }
        | _ -> Error "the move would produce source that does not parse"
      end
    end

(* ------------------------------------------------------------------ *)
(* replace — structural codemod with $metavariables                    *)
(* ------------------------------------------------------------------ *)

(** Rewrite `$name` placeholders to a parseable sentinel identifier. *)
let mv_prefix = "__mv_"
let subst_metavars s =
  Str.global_replace (Str.regexp "\\$\\([A-Za-z_][A-Za-z0-9_]*\\)") (mv_prefix ^ "\\1") s

let is_metavar txt =
  String.length txt > String.length mv_prefix
  && String.sub txt 0 (String.length mv_prefix) = mv_prefix

(** Parse a bare expression by wrapping it in a throwaway function. *)
let parse_expr (src : string) : Ast.expr option =
  let wrapped = Printf.sprintf "mod Zzpat do\n  fn zzf() do\n%s\n  end\nend\n" src in
  match parse_string ~filename:"<pattern>" wrapped with
  | None -> None
  | Some m ->
    (* The wrapper's `mod Zzpat do ... end` yields [DFn zzf] directly (the file
       module IS Zzpat), so search recursively for the first function body. *)
    let rec find_fn = function
      | [] -> None
      | Ast.DFn (fn, _) :: _ ->
        (match fn.Ast.fn_clauses with cl :: _ -> Some cl.Ast.fc_body | [] -> None)
      | Ast.DMod (_, _, ds, _) :: rest ->
        (match find_fn ds with Some e -> Some e | None -> find_fn rest)
      | _ :: rest -> find_fn rest
    in
    (match find_fn m.Ast.mod_decls with
     | None -> None
     | Some (Ast.EBlock (e :: _, _)) -> Some e
     | Some e -> Some e)

(** Structural find-and-replace. [pat] and [tmpl] use `$x` metavariables; only
    call-shaped patterns (`Callee($a, $b, ...)`) are supported in v1. Each match
    binds its metavariables to the actual argument source text, then the template
    string is instantiated by substituting them back. *)
let rec replace_project ~root ~pat ~tmpl ~dry_run : (outcome, string) result =
  match parse_expr (subst_metavars pat) with
  | Some (Ast.EApp (Ast.EVar pcallee, pargs, _))
    when List.for_all (function Ast.EVar n -> is_metavar n.Ast.txt | _ -> false) pargs ->
    let pname = pcallee.Ast.txt in
    let keys = List.map (function
        | Ast.EVar n -> String.sub n.Ast.txt (String.length mv_prefix)
                          (String.length n.Ast.txt - String.length mv_prefix)
        | _ -> "") pargs in
    let parity = List.length pargs in
    let files = discover_march_files root in
    let changes = ref [] and skipped = ref [] in
    List.iter (fun path ->
        match (try Some (read_file path) with _ -> None) with
        | None -> ()
        | Some src ->
          (match parse_string ~filename:path src with
           | None -> ()
           | Some m ->
             let edits = ref [] in
             iter_app_exprs (fun callee args sp ->
                 let callee_ok = match callee with
                   | Ast.EVar n -> n.Ast.txt = pname | _ -> false in
                 if callee_ok && List.length args = parity then begin
                   let binds = Hashtbl.create 8 in
                   List.iter2 (fun key a ->
                       let (s, e) = span_bounds src (span_of_expr a) in
                       if e > s && e <= String.length src then
                         Hashtbl.replace binds key (String.sub src s (e - s)))
                     keys args;
                   let out =
                     Str.global_substitute (Str.regexp "\\$\\([A-Za-z_][A-Za-z0-9_]*\\)")
                       (fun whole ->
                          let k = Str.matched_group 1 whole in
                          match Hashtbl.find_opt binds k with
                          | Some v -> v | None -> Str.matched_string whole)
                       tmpl in
                   let (s, e) = span_bounds src sp in
                   if e > s && e <= String.length src then
                     edits := { e_start = s; e_stop = e; e_repl = out } :: !edits
                 end)
               m;
             if !edits <> [] then begin
               let updated = apply_edits src !edits in
               match parse_string ~filename:path updated with
               | None -> skipped := (path, "result would not parse") :: !skipped
               | Some _ ->
                 if not dry_run then write_file path updated;
                 changes := { fc_path = path; fc_old = src; fc_new = updated;
                              fc_count = List.length !edits } :: !changes
             end))
      files;
    Ok { changes = List.rev !changes; skipped = List.rev !skipped }
  | _ -> Error "pattern must be a call with metavariable arguments, e.g. `f($a, $b)`"

(** Visit every EApp node with its callee, args, and span. (Defined here because
    [replace_project] needs application-shaped nodes specifically.) *)
and iter_app_exprs (f : Ast.expr -> Ast.expr list -> Ast.span -> unit)
    (m : Ast.module_) : unit =
  let rec ex (e : Ast.expr) =
    (match e with Ast.EApp (c, args, sp) -> f c args sp | _ -> ());
    match e with
    | Ast.EApp (c, args, _) -> ex c; List.iter ex args
    | Ast.ECon (_, args, _) | Ast.EAtom (_, args, _) | Ast.ETuple (args, _) ->
      List.iter ex args
    | Ast.ELam (_, b, _) | Ast.ELetFn (_, _, _, b, _) -> ex b
    | Ast.EBlock (es, _) -> List.iter ex es
    | Ast.ELet (b, _) -> ex b.Ast.bind_expr
    | Ast.EMatch (s, brs, _) ->
      ex s; List.iter (fun (br : Ast.branch) ->
          (match br.branch_guard with Some g -> ex g | None -> ()); ex br.branch_body) brs
    | Ast.ECond (arms, _) -> List.iter (fun (c, b) -> ex c; ex b) arms
    | Ast.EIf (c, t, el, _) -> ex c; ex t; ex el
    | Ast.EPipe (a, b, _) | Ast.ESend (a, b, _) -> ex a; ex b
    | Ast.ERecord (fs, _) -> List.iter (fun (_, e) -> ex e) fs
    | Ast.ERecordUpdate (e, fs, _) -> ex e; List.iter (fun (_, e) -> ex e) fs
    | Ast.EField (e, _, _) | Ast.EAnnot (e, _, _) | Ast.ESpawn (e, _)
    | Ast.EAssert (e, _) | Ast.ESigil (_, e, _) | Ast.EDbg (Some e, _) -> ex e
    | _ -> ()
  in
  let rec decl (d : Ast.decl) =
    match d with
    | Ast.DFn (fn, _) ->
      List.iter (fun (cl : Ast.fn_clause) ->
          (match cl.fc_guard with Some g -> ex g | None -> ()); ex cl.fc_body)
        fn.Ast.fn_clauses
    | Ast.DLet (_, b, _) -> ex b.Ast.bind_expr
    | Ast.DMod (_, _, ds, _) | Ast.DDescribe (_, ds, _) -> List.iter decl ds
    | Ast.DTest (t, _) -> ex t.Ast.test_body
    | _ -> ()
  in
  List.iter decl m.Ast.mod_decls

(** Span of an expression (mirrors the engine elsewhere). *)
and span_of_expr (e : Ast.expr) : Ast.span =
  match e with
  | Ast.ELit (_, sp) | Ast.EApp (_, _, sp) | Ast.ECon (_, _, sp)
  | Ast.ELam (_, _, sp) | Ast.EBlock (_, sp) | Ast.ELet (_, sp)
  | Ast.EMatch (_, _, sp) | Ast.ETuple (_, sp) | Ast.ERecord (_, sp)
  | Ast.ERecordUpdate (_, _, sp) | Ast.EField (_, _, sp) | Ast.EIf (_, _, _, sp)
  | Ast.ECond (_, sp) | Ast.EPipe (_, _, sp) | Ast.EAnnot (_, _, sp)
  | Ast.EHole (_, sp) | Ast.EAtom (_, _, sp) | Ast.ESend (_, _, sp)
  | Ast.ESpawn (_, sp) | Ast.EDbg (_, sp) | Ast.ELetFn (_, _, _, _, sp)
  | Ast.EAssert (_, sp) | Ast.ESigil (_, _, sp) -> sp
  | Ast.EVar n -> n.Ast.span
  | Ast.EResultRef _ -> Ast.dummy_span
