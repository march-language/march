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

(** Source text covered by [sp], or "" if out of bounds. *)
let slice_span src (sp : Ast.span) =
  let (s, e) = span_bounds src sp in
  if e > s && s >= 0 && e <= String.length src then String.sub src s (e - s) else ""

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
    | Ast.TyRefine (base, _, _) -> ty base
  and pat (p : Ast.pattern) =
    match p with
    | Ast.PatWild _ | Ast.PatLit _ -> ()
    | Ast.PatVar n -> f SPat n
    | Ast.PatCon (n, ps) -> f SCtor n; List.iter pat ps
    | Ast.PatAtom (_, ps, _) -> List.iter pat ps
    | Ast.PatTuple (ps, _) -> List.iter pat ps
    | Ast.PatRecord (fs, _) -> List.iter (fun (n, p) -> f SField n; pat p) fs
    | Ast.PatAs (p, n, _) -> pat p; f SPat n
    | Ast.PatOr (ps, _) -> List.iter pat ps
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
    | Ast.ELetQ (_, r, c, _) | Ast.ELetStar (_, r, c, _) -> expr r; expr c
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
  | Ast.DAlwaysLinearType (_, _, _, _, sp)
  | Ast.DActor (_, _, _, sp) | Ast.DProtocol (_, _, sp) | Ast.DMod (_, _, _, sp)
  | Ast.DSig (_, _, sp) | Ast.DInterface (_, sp) | Ast.DImpl (_, sp)
  | Ast.DExtern (_, sp) | Ast.DUse (_, sp) | Ast.DAlias (_, sp)
  | Ast.DNeeds (_, sp) | Ast.DProofCap (_, _, sp) | Ast.DTransitions (_, _, sp)
  | Ast.DApp (_, sp) | Ast.DDeriving (_, _, sp) | Ast.DSatisfy (_, _, sp)
  | Ast.DTest (_, sp) | Ast.DDescribe (_, _, sp) | Ast.DSetup (_, sp)
  | Ast.DSetupAll (_, sp) | Ast.DOpts (_, sp) -> sp

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
    | Ast.ELetQ (_, r, c, _) | Ast.ELetStar (_, r, c, _) -> ex r; ex c
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
  | Ast.ELetQ (_, _, _, sp) | Ast.ELetStar (_, _, _, sp)
  | Ast.EAssert (_, sp) | Ast.ESigil (_, _, sp) -> sp
  | Ast.EVar n -> n.Ast.span
  | Ast.EResultRef _ -> Ast.dummy_span

(* ------------------------------------------------------------------ *)
(* bundle — introduce a parameter object (record) for a function       *)
(* ------------------------------------------------------------------ *)

(** Render a surface [Ast.ty] back to March source (best-effort). *)
let rec surface_ty (t : Ast.ty) : string =
  match t with
  | Ast.TyCon (n, [])   -> n.Ast.txt
  | Ast.TyCon (n, args) ->
    n.Ast.txt ^ "(" ^ String.concat ", " (List.map surface_ty args) ^ ")"
  | Ast.TyVar n         -> n.Ast.txt
  | Ast.TyArrow (a, b)  -> surface_ty a ^ " -> " ^ surface_ty b
  | Ast.TyTuple ts      -> "(" ^ String.concat ", " (List.map surface_ty ts) ^ ")"
  | Ast.TyRecord fs     ->
    "{ " ^ String.concat ", "
             (List.map (fun (n, t) -> n.Ast.txt ^ ": " ^ surface_ty t) fs) ^ " }"
  | Ast.TyLinear (_, t) -> "linear " ^ surface_ty t
  | Ast.TyNat n         -> string_of_int n
  | Ast.TyNatOp (op, a, b) ->
    surface_ty a ^ (match op with Ast.NatAdd -> " + " | Ast.NatMul -> " * ") ^ surface_ty b
  | Ast.TyChan (r, p)   -> "Chan(" ^ r.Ast.txt ^ ", " ^ p.Ast.txt ^ ")"
  (* Best-effort: the predicate is elided here (A1a). The faithful renderer is
     March_format.fmt_ty; this module only generates preview/stub signatures. *)
  | Ast.TyRefine (base, None, _)   -> "{ " ^ surface_ty base ^ " | ... }"
  | Ast.TyRefine (base, Some n, _) -> "{ " ^ n.Ast.txt ^ " : " ^ surface_ty base ^ " | ... }"

(** Split [s] on top-level commas, respecting (), [], {} nesting and string
    literals. Used to recover argument source text without trusting per-arg
    spans (string-literal spans in the parser only cover the opening quote). *)
let split_top_commas (s : string) : string list =
  let n = String.length s in
  let parts = ref [] and start = ref 0 and depth = ref 0 and instr = ref false in
  let i = ref 0 in
  while !i < n do
    let c = s.[!i] in
    (if !instr then (if c = '\\' then incr i else if c = '"' then instr := false)
     else match c with
       | '"' -> instr := true
       | '(' | '[' | '{' -> incr depth
       | ')' | ']' | '}' -> if !depth > 0 then decr depth
       | ',' when !depth = 0 ->
         parts := String.sub s !start (!i - !start) :: !parts; start := !i + 1
       | _ -> ());
    incr i
  done;
  parts := String.sub s !start (n - !start) :: !parts;
  List.rev_map String.trim !parts

let pascal_case name =
  String.concat ""
    (List.map (fun p ->
         if p = "" then ""
         else String.make 1 (Char.uppercase_ascii p.[0]) ^ String.sub p 1 (String.length p - 1))
       (String.split_on_char '_' name))

(** Spans of unshadowed references to any name in [targets] within [e]. *)
let unshadowed_uses (targets : string list) (e : Ast.expr) : (string * Ast.span) list =
  let acc = ref [] in
  let pat_names p =
    let r = ref [] in
    let rec go = function
      | Ast.PatVar n -> r := n.Ast.txt :: !r
      | Ast.PatAs (p, n, _) -> go p; r := n.Ast.txt :: !r
      | Ast.PatCon (_, ps) | Ast.PatAtom (_, ps, _) | Ast.PatTuple (ps, _) -> List.iter go ps
      | Ast.PatRecord (fs, _) -> List.iter (fun (_, p) -> go p) fs
      | _ -> () in
    go p; !r in
  let rec walk bound (e : Ast.expr) =
    match e with
    | Ast.EVar n ->
      if List.mem n.Ast.txt targets && not (List.mem n.Ast.txt bound)
      then acc := (n.Ast.txt, n.Ast.span) :: !acc
    | Ast.ELit _ | Ast.EHole _ | Ast.EResultRef _ | Ast.EDbg (None, _) -> ()
    | Ast.EApp (g, args, _) -> walk bound g; List.iter (walk bound) args
    | Ast.ECon (_, args, _) | Ast.EAtom (_, args, _) | Ast.ETuple (args, _) ->
      List.iter (walk bound) args
    | Ast.ELam (ps, body, _) ->
      walk (List.fold_left (fun b (p : Ast.param) -> p.Ast.param_name.txt :: b) bound ps) body
    | Ast.ELetFn (n, ps, _, body, _) ->
      walk (n.Ast.txt :: List.fold_left (fun b (p : Ast.param) -> p.Ast.param_name.txt :: b) bound ps) body
    | Ast.EBlock (es, _) ->
      ignore (List.fold_left (fun b e -> match e with
          | Ast.ELet (bd, _) -> walk b bd.Ast.bind_expr; pat_names bd.Ast.bind_pat @ b
          | _ -> walk b e; b) bound es)
    | Ast.ELet (bd, _) -> walk bound bd.Ast.bind_expr
    | Ast.EMatch (s, brs, _) ->
      walk bound s;
      List.iter (fun (br : Ast.branch) ->
          let b = pat_names br.branch_pat @ bound in
          (match br.branch_guard with Some g -> walk b g | None -> ());
          walk b br.branch_body) brs
    | Ast.EIf (c, t, el, _) -> walk bound c; walk bound t; walk bound el
    | Ast.ECond (arms, _) -> List.iter (fun (c, b) -> walk bound c; walk bound b) arms
    | Ast.EPipe (a, b, _) | Ast.ESend (a, b, _) -> walk bound a; walk bound b
    | Ast.ERecord (fs, _) -> List.iter (fun (_, e) -> walk bound e) fs
    | Ast.ERecordUpdate (e, fs, _) -> walk bound e; List.iter (fun (_, e) -> walk bound e) fs
    | Ast.ELetQ (_, r, c, _) | Ast.ELetStar (_, r, c, _) ->
      walk bound r;
      walk bound c
    | Ast.EField (e, _, _) | Ast.EAnnot (e, _, _) | Ast.ESpawn (e, _)
    | Ast.EAssert (e, _) | Ast.ESigil (_, e, _) | Ast.EDbg (Some e, _) -> walk bound e in
  walk [] e;
  !acc

(** Bundle the parameters of [fn_name] into a generated record, rewriting the
    function's signature and body and every call site across the project. v1
    limits: single-clause function, all parameters type-annotated. A recursive
    call in the body is rewritten as a call site and may need manual touch-up. *)
let bundle_fn ~root ~fn_name ?record_name ~dry_run () : (outcome, string) result =
  let files = discover_march_files root in
  let found = ref None in
  List.iter (fun path ->
      if !found = None then
        match (try Some (read_file path) with _ -> None) with
        | None -> ()
        | Some src ->
          (match parse_string ~filename:path src with
           | None -> ()
           | Some m ->
             let rec scan ds =
               List.iter (fun d -> if !found = None then match d with
                   | Ast.DFn (fn, _) when fn.Ast.fn_name.Ast.txt = fn_name ->
                     found := Some (path, src, fn)
                   | Ast.DMod (_, _, ds, _) -> scan ds | _ -> ()) ds in
             scan m.Ast.mod_decls))
    files;
  match !found with
  | None -> Error (Printf.sprintf "no function named `%s` found" fn_name)
  | Some (def_path, def_src, fn) ->
    (match fn.Ast.fn_clauses with
     | [cl] ->
       let extracted =
         List.map (fun p -> match p with
             | Ast.FPNamed { Ast.param_name; param_ty = Some ty; _ } -> Ok (param_name.Ast.txt, ty)
             | Ast.FPNamed { Ast.param_name; _ } -> Error param_name.Ast.txt
             | Ast.FPPat (Ast.PatVar n) -> Error n.Ast.txt
             | _ -> Error "<param>") cl.Ast.fc_params in
       (match List.find_opt (function Error _ -> true | _ -> false) extracted with
        | Some (Error nm) ->
          Error (Printf.sprintf "parameter `%s` has no type annotation (required to bundle)" nm)
        | _ ->
          let params = List.map (function Ok x -> x | Error _ -> assert false) extracted in
          if params = [] then Error "function has no parameters to bundle"
          else begin
            let rn = match record_name with Some r -> r | None -> pascal_case fn_name ^ "Args" in
            let pvar = "args" in
            let def_edits = ref [] in
            (* (a) insert the record type before the function. If the function
               carries a `doc` comment (and/or `@[..]` attributes), the type
               must go ABOVE that block — a `type` wedged between a `doc` and its
               `fn` does not parse, which would make the engine skip the file. *)
            let name_sp = fn.Ast.fn_name.Ast.span in
            let fn_line = name_sp.Ast.start_line - 1 in
            let line_start = offset_of_pos def_src fn_line 0 in
            let indent =
              let b = Buffer.create 8 in let i = ref line_start in
              while !i < String.length def_src && (def_src.[!i] = ' ' || def_src.[!i] = '\t') do
                Buffer.add_char b def_src.[!i]; incr i done; Buffer.contents b in
            let insert_off =
              match fn.Ast.fn_doc with
              | None -> line_start
              | Some _ ->
                let line_text i =
                  let s = offset_of_pos def_src i 0 in
                  let n = String.length def_src and e = ref (offset_of_pos def_src i 0) in
                  while !e < n && def_src.[!e] <> '\n' do incr e done;
                  String.sub def_src s (!e - s) in
                let trimmed_starts t pfx =
                  let kl = String.length pfx in
                  String.length t >= kl && String.sub t 0 kl = pfx in
                (* The opening line of a doc block: the doc keyword followed by
                   a string literal (single- or triple-quoted). *)
                let is_doc_start s =
                  let t = String.trim s in
                  trimmed_starts t "doc"
                  && (let j = ref 3 and n = String.length t in
                      while !j < n && t.[!j] = ' ' do incr j done;
                      !j < n && t.[!j] = '"') in
                let i = ref (fn_line - 1) in
                (* skip attribute lines sitting between the doc and the fn *)
                while !i >= 0 && trimmed_starts (String.trim (line_text !i)) "@" do decr i done;
                (* walk up to the first line of the doc block *)
                while !i >= 0 && not (is_doc_start (line_text !i)) do decr i done;
                if !i >= 0 then offset_of_pos def_src !i 0 else line_start in
            let fields_decl =
              String.concat ", " (List.map (fun (n, t) -> Printf.sprintf "%s : %s" n (surface_ty t)) params) in
            let type_text = Printf.sprintf "%stype %s = { %s }\n\n" indent rn fields_decl in
            def_edits := { e_start = insert_off; e_stop = insert_off; e_repl = type_text } :: !def_edits;
            (* (b) replace the parameter list with `(args: RN)` *)
            let (_, name_end) = span_bounds def_src name_sp in
            let n = String.length def_src in
            let popen = ref name_end in
            while !popen < n && def_src.[!popen] <> '(' do incr popen done;
            (if !popen < n then begin
                let depth = ref 0 and j = ref !popen and stop = ref (-1) in
                while !j < n && !stop < 0 do
                  (match def_src.[!j] with '(' -> incr depth | ')' -> decr depth | _ -> ());
                  if !depth = 0 then stop := !j else incr j
                done;
                if !stop > !popen then
                  def_edits := { e_start = !popen + 1; e_stop = !stop;
                                 e_repl = Printf.sprintf "%s: %s" pvar rn } :: !def_edits
              end);
            (* (c) rewrite body references to params -> args.param *)
            let pnames = List.map fst params in
            List.iter (fun (nm, sp) ->
                let (s, e) = span_bounds def_src sp in
                if e > s then
                  def_edits := { e_start = s; e_stop = e; e_repl = pvar ^ "." ^ nm } :: !def_edits)
              (unshadowed_uses pnames cl.Ast.fc_body);
            (* --- call-site edits across all files --- *)
            let changes = ref [] and skipped = ref [] in
            let nparams = List.length params in
            let process path src extra =
              match parse_string ~filename:path src with
              | None -> if extra <> [] then skipped := (path, "result would not parse") :: !skipped
              | Some m ->
                let edits = ref extra in
                iter_app_exprs (fun callee args _sp ->
                    let target = match callee with
                      | Ast.EVar n ->
                        (* Bare `connect(...)` OR module-qualified `A.connect(...)`
                           when it folds to a single dotted EVar — match on the
                           last dotted segment so cross-file qualified call sites
                           are rewritten too. *)
                        n.Ast.txt = fn_name
                        || (let suf = "." ^ fn_name in
                            let nt = n.Ast.txt and sl = String.length ("." ^ fn_name) in
                            String.length nt >= sl
                            && String.sub nt (String.length nt - sl) sl = suf)
                      | Ast.EField (_, fld, _) -> fld.Ast.txt = fn_name
                      | _ -> false in
                    if target && List.length args = nparams then begin
                      (* Find the call's parens by scanning from the callee start
                         (per-arg spans are unreliable for string literals). *)
                      let (cstart, _) = span_bounds src (span_of_expr callee) in
                      let slen = String.length src in
                      let popen = ref cstart in
                      while !popen < slen && src.[!popen] <> '(' do incr popen done;
                      if !popen < slen then begin
                        let depth = ref 0 and j = ref !popen and pclose = ref (-1) in
                        while !j < slen && !pclose < 0 do
                          (match src.[!j] with '(' -> incr depth | ')' -> decr depth | _ -> ());
                          if !depth = 0 then pclose := !j else incr j
                        done;
                        if !pclose > !popen then begin
                          let inner = String.sub src (!popen + 1) (!pclose - !popen - 1) in
                          let arg_texts = split_top_commas inner in
                          if List.length arg_texts = nparams then begin
                            let fields =
                              (* March record literals use `field: value` (colon),
                                 like `{ count: 0 }` — NOT `=`.  A `=` literal does
                                 not parse, so the rewritten call site would fail
                                 re-parse and the file would be silently skipped. *)
                              String.concat ", "
                                (List.map2 (fun (pn, _) at -> Printf.sprintf "%s: %s" pn at)
                                   params arg_texts) in
                            edits := { e_start = !popen + 1; e_stop = !pclose;
                                       e_repl = Printf.sprintf "{ %s }" fields } :: !edits
                          end
                        end
                      end
                    end) m;
                if !edits <> [] then begin
                  let updated = apply_edits src !edits in
                  match parse_string ~filename:path updated with
                  | None -> skipped := (path, "result would not parse") :: !skipped
                  | Some _ ->
                    if not dry_run then write_file path updated;
                    changes := { fc_path = path; fc_old = src; fc_new = updated;
                                 fc_count = List.length !edits } :: !changes
                end
            in
            List.iter (fun path ->
                match (try Some (read_file path) with _ -> None) with
                | None -> ()
                | Some src ->
                  let extra = if path = def_path then !def_edits else [] in
                  process path src extra)
              files;
            Ok { changes = List.rev !changes; skipped = List.rev !skipped }
          end)
     | _ -> Error "can only bundle single-clause functions")
