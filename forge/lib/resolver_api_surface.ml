(** Public API surface extraction and semver change classification.

    Parses each .march source file with the real March parser
    ([March_parser.Parser.module_]) and walks the resulting AST to extract a
    package's public API surface:
      - Public function signatures: `fn name(params...) : RetType`
      - Public type declarations: `type Name = ...` /
        `always_linear type Name = ...`

    Visibility in March is `fn` (public) / `pfn` (private) — `type` is public
    by default. There is no `pub` keyword. An earlier version of this module
    scanned source text line-by-line for an invented `pub fn ... -> T`
    dialect that March does not have, which made [extract_from_directory]
    return an empty surface for every real package (silently — no parse
    error, just nothing found). See
    specs/progress/2026-08-03-forge-api-surface-parser-wrong-syntax.md.

    Reading the surface off the AST (rather than off source text) also means
    multi-head clauses, default arguments, and signatures wrapped across
    lines are captured for free — a line scanner cannot see any of those.

    Change classification follows the plan's rules:
      MAJOR: remove a public fn or type, change a fn signature, or change the
             body of a public fn that has no return-type annotation (the
             diff cannot see its return type, so it cannot certify less)
      MINOR: add a new public fn or type
      PATCH: no API change

    Signatures are compared STRUCTURALLY, not as rendered text (2026-10-11):
    parameter names are dropped and type variables are renamed to a canonical
    order, so renaming a parameter or a type variable is no longer a false
    MAJOR.  A type's parameters are part of its comparison too: before,
    they were ignored, and `type Box(a)` -> `type Box(a, b)` diffed as no
    change.  Still not done: comparing INFERRED types (so an unannotated
    function gets a precise verdict) and classifying a refinement change by
    direction -- see specs/todos/2026-07-31-forge-semantic-semver.md.

    Pre-1.0.0 packages skip enforcement entirely.
*)

module Ast = March_ast.Ast
module Fmt = March_format.Format

(* ------------------------------------------------------------------ *)
(*  Surface representation                                             *)
(* ------------------------------------------------------------------ *)

(** The parts of a function's definition its signature is made of, kept as
    AST so [diff] can compare them structurally.  [None] for a signature built
    by hand (tests), which then compares by its rendered text. *)
type fn_ast = {
  fa_params : Ast.fn_param list list; (** one list per clause *)
  fa_ret    : Ast.ty option;
  fa_bounds : (Ast.name * Ast.ty) list;
}

(** A public function signature as read off the AST. *)
type fn_sig = {
  name       : string;
  params_raw : string;   (** rendered parameter list, e.g. "x : Int, y : Int".
                              A multi-head function's clauses are joined with
                              " | ", each parenthesized, so a change to any
                              head shows up in the diff. *)
  return_raw : string;   (** rendered return type annotation (empty if absent) *)
  clauses_raw : string;  (** the whole definition, formatter-rendered without
                              its doc string or comments, so layout and doc
                              edits do not register.  Compared only when
                              [return_raw] is empty; see [UnverifiableFn]. *)
  sig_ast : fn_ast option;
}

(** A type declaration's parameters and right-hand side, kept for the
    structural comparison.  [None] for a hand-built declaration. *)
type type_ast = {
  ta_params : string list;
  ta_def    : Ast.type_def;
}

(** A public type declaration. *)
type type_decl = {
  type_name : string;
  body_raw  : string;   (** rendered RHS of the type declaration *)
  type_ast  : type_ast option;
}

(** The public API surface of a package. *)
type surface = {
  fns   : fn_sig list;
  types : type_decl list;
}

let empty_surface = { fns = []; types = [] }

(* ------------------------------------------------------------------ *)
(*  Rendering (surface-syntax text, for diffing/display purposes only) *)
(* ------------------------------------------------------------------ *)

let render_clause_params (clause : Ast.fn_clause) =
  String.concat ", " (List.map Fmt.fmt_fn_param clause.Ast.fc_params)

(** Render a function's full parameter surface across all of its clauses. *)
let render_fn_params (fn : Ast.fn_def) =
  match fn.Ast.fn_clauses with
  | [clause] -> render_clause_params clause
  | clauses  ->
    String.concat " | "
      (List.map (fun c -> "(" ^ render_clause_params c ^ ")") clauses)

let render_return (fn : Ast.fn_def) =
  match fn.Ast.fn_ret_ty with
  | None    -> ""
  | Some ty -> Fmt.fmt_ty ty

let render_clauses (fn : Ast.fn_def) =
  let ctx = Fmt.make_ctx [] in
  Fmt.emit_fn ctx { fn with Ast.fn_doc = None };
  Buffer.contents ctx.Fmt.buf

let render_type_def (tdef : Ast.type_def) =
  match tdef with
  | Ast.TDAlias ty -> Fmt.fmt_ty ty
  | Ast.TDVariant variants ->
    let var_str (v : Ast.variant) =
      match v.Ast.var_args with
      | []  -> v.Ast.var_name.Ast.txt
      | tys -> Printf.sprintf "%s(%s)" v.Ast.var_name.Ast.txt (Fmt.fmt_tys tys)
    in
    String.concat " | " (List.map var_str variants)
  | Ast.TDRecord fields ->
    let fld_str (f : Ast.field) =
      Printf.sprintf "%s%s : %s"
        (Fmt.fmt_lin f.Ast.fld_lin) f.Ast.fld_name.Ast.txt (Fmt.fmt_ty f.Ast.fld_ty)
    in
    "{ " ^ String.concat ", " (List.map fld_str fields) ^ " }"

(* ------------------------------------------------------------------ *)
(*  Parsing                                                             *)
(* ------------------------------------------------------------------ *)

(** Parse a .march file with the real parser, the same way
    [Cmd_cap.parse_file] does for `forge cap`. *)
let parse_file path : (Ast.decl list, string) result =
  try
    let ic  = open_in path in
    let src = really_input_string ic (in_channel_length ic) in
    close_in ic;
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
    let m = March_parser.Parse.module_of_lexbuf lexbuf in
    Ok m.Ast.mod_decls
  with
  | Sys_error msg -> Error msg
  | exn -> Error (Printexc.to_string exn)

(** Parse a string of March source (a whole module body) and return its
    declarations. Used by [extract_from_string] and by tests. *)
let parse_string ?(fname = "<string>") src : (Ast.decl list, string) result =
  try
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = fname };
    let m = March_parser.Parse.module_of_lexbuf lexbuf in
    Ok m.Ast.mod_decls
  with exn -> Error (Printexc.to_string exn)

(* ------------------------------------------------------------------ *)
(*  Extraction                                                         *)
(* ------------------------------------------------------------------ *)

(** Walk [decls], accumulating every public `fn`/`type`/`always_linear type`,
    descending into nested `mod ... end` blocks. Private (`pfn`) declarations
    and anything inside `describe`/`test` blocks are not part of the public
    surface and are skipped. *)
let rec extract_decls decls surf =
  List.fold_left extract_one surf decls

and extract_one surf (d : Ast.decl) =
  let names ps = List.map (fun (n : Ast.name) -> n.Ast.txt) ps in
  let public_type surf (name : Ast.name) params tdef =
    let t = { type_name = name.Ast.txt; body_raw = render_type_def tdef;
              type_ast = Some { ta_params = names params; ta_def = tdef } } in
    { surf with types = surf.types @ [t] }
  in
  match d with
  | Ast.DFn (fn, _) ->
    (match fn.Ast.fn_vis with
     | Ast.Private -> surf
     | Ast.Public ->
       let s = { name       = fn.Ast.fn_name.Ast.txt;
                 params_raw = render_fn_params fn;
                 return_raw = render_return fn;
                 clauses_raw = render_clauses fn;
                 sig_ast = Some {
                     fa_params =
                       List.map (fun c -> c.Ast.fc_params) fn.Ast.fn_clauses;
                     fa_ret = fn.Ast.fn_ret_ty;
                     fa_bounds = fn.Ast.fn_bounds } } in
       { surf with fns = surf.fns @ [s] })
  | Ast.DType (Ast.Private, _, _, _, _) -> surf
  | Ast.DType (Ast.Public, name, params, tdef, _) ->
    public_type surf name params tdef
  | Ast.DAlwaysLinearType (Ast.Private, _, _, _, _) -> surf
  | Ast.DAlwaysLinearType (Ast.Public, name, params, tdef, _) ->
    public_type surf name params tdef
  | Ast.DMod (_, _, inner, _) ->
    extract_decls inner surf
  | _ -> surf

(** Extract the public API surface from a string of March source
    (a single module body — no `mod ... do ... end` wrapper needed, since
    [March_parser.Parser.module_] accepts a bare sequence of declarations). *)
let extract_from_string src =
  match parse_string src with
  | Error _   -> empty_surface
  | Ok decls  -> extract_decls decls empty_surface

(** Recursively collect the .march files that make up a package's PUBLIC API,
    in sorted order for deterministic output.

    Two kinds of directory are pruned, because what lands here is what
    `forge publish` treats as the package's public API surface and holds the
    author to under semver:

    - Dot-directories (`.march/`, `.git/`, …). `.march/` is forge's own build
      tree, physically under the project root; anything cached there would be
      counted a second time, and a vendored dependency's sources would be
      folded into THIS package's surface, so a dependency upgrade alone would
      demand a major bump.
    - The package's top-level `test/` directory — forge's own convention
      (see [Cmd_test], which resolves tests as `<root>/test`). Test helpers
      are not API: without this, renaming a fixture helper reads as
      [ChangedFn] → [Major] and blocks an otherwise legitimate patch release.
      Pruned only at the root, so a `src/test_utils.march` (a real module
      that happens to be named for testing) still counts. *)
let march_files_under root =
  let files = ref [] in
  let rec walk dir =
    (try
       let entries = Sys.readdir dir in
       Array.iter (fun name ->
           let path = Filename.concat dir name in
           if Sys.is_directory path then begin
             let is_dot_dir = String.length name > 0 && name.[0] = '.' in
             let is_root_test_dir = dir = root && name = "test" in
             if not (is_dot_dir || is_root_test_dir) then walk path
           end
           else if Filename.check_suffix name ".march" then
             files := path :: !files
         ) entries
     with Sys_error _ -> ())
  in
  walk root;
  List.sort String.compare !files

(** Extract the combined API surface of a package source tree, together with
    the files that could not be parsed.

    A parse failure is NOT benign here. Every public item in an unreadable
    file is simply absent from the surface, and absence is indistinguishable
    from deletion: if the OLD tree has an unparseable file, [diff] sees none
    of its functions and reports no [RemovedFn] for them, so a genuinely
    breaking release classifies as [Patch] and publishes unchallenged — the
    same silent-pass this module was rewritten to eliminate, just reached by
    a different route. Callers that gate on the verdict must treat a
    non-empty file list as "surface incomplete, verdict not trustworthy"
    rather than as a warning; [Cmd_publish] refuses to certify a bump. *)
let extract_from_directory_checked root_dir =
  let files = march_files_under root_dir in
  List.fold_left (fun (surf, failed) path ->
      match parse_file path with
      | Error msg ->
        Printf.eprintf "forge: api-surface: %s: %s\n%!" path msg;
        (surf, (path, msg) :: failed)
      | Ok decls -> (extract_decls decls surf, failed)
    ) (empty_surface, []) files
  |> fun (surf, failed) -> (surf, List.rev failed)

(** Surface only, discarding parse failures. For callers that are not gating
    a release on completeness; [extract_from_directory_checked] is what
    [Cmd_publish] uses. *)
let extract_from_directory root_dir = fst (extract_from_directory_checked root_dir)

(* ------------------------------------------------------------------ *)
(*  Change classification                                              *)
(* ------------------------------------------------------------------ *)

type change_kind =
  | Major  (** breaking: removed or changed signature *)
  | Minor  (** additive: new public item *)
  | Patch  (** no API change *)

type change =
  | RemovedFn    of fn_sig             (* Major *)
  | ChangedFn    of fn_sig * fn_sig    (* Major: old, new *)
  | UnverifiableFn of fn_sig * fn_sig  (* Major: see below *)
  | AddedFn      of fn_sig             (* Minor *)
  | RemovedType  of type_decl          (* Major *)
  | ChangedType  of type_decl * type_decl  (* Major: old, new *)
  | AddedType    of type_decl          (* Minor *)

let change_kind_of = function
  | RemovedFn _    -> Major
  | ChangedFn _    -> Major
  (* No return annotation, and the body changed.  The signature text is the
     same on both sides, but without an annotation it does not include the
     return type, and a changed body can return something else: a function
     that returned an Int and now returns a String diffed as no change and
     published as a PATCH.  The diff cannot rule that out, so, as with an
     unparseable file, it refuses to certify anything short of MAJOR rather
     than certify wrongly. *)
  | UnverifiableFn _ -> Major
  | RemovedType _  -> Major
  | ChangedType _  -> Major
  | AddedFn _      -> Minor
  | AddedType _    -> Minor

(** Compute the required semver bump from a list of changes. *)
let required_bump changes =
  if List.exists (fun c -> change_kind_of c = Major) changes then Major
  else if List.exists (fun c -> change_kind_of c = Minor) changes then Minor
  else Patch

(* ------------------------------------------------------------------ *)
(*  Structural signature keys                                          *)
(* ------------------------------------------------------------------ *)

(* What a caller can observe of a signature, as a string that is equal for two
   signatures exactly when the comparison calls them the same
   (specs/2026-09-18-forge-p1-design.md section 3, step 1, as far as it goes
   without the typechecker):

   - parameter NAMES are dropped (a caller never spells one), but each
     parameter's linearity, type and whether it has a default are kept;
   - type variables are renamed '0, '1, ... in order of first occurrence
     across the parameters, the return type and then the bounds, so `List(a)`
     and `List(b)` agree (a quote cannot appear in a written type, so a
     renamed variable never collides with a real one).

   The design's "aliases expanded" has nothing to do: the grammar has no
   user-written alias.  `type UserId = Int` parses as a variant with ONE
   constructor named `Int` (see the comment on [walk_type_def] in
   lib/refinecheck/refine_audit.ml), so `UserId` and `Int` are different
   types and replacing one with the other is rightly MAJOR.

   Anything the key does not model is compared as written: a pattern head is
   rendered (behaviour, not a type, but a multi-head function's heads were
   always part of the comparison), and a refinement keeps its binder and
   predicate verbatim, so changing either is still MAJOR (step 3, classifying
   a refinement change by direction, is not done). *)

let rec ty_vars acc (t : Ast.ty) =
  match t with
  | Ast.TyVar n -> if List.mem n.Ast.txt acc then acc else acc @ [n.Ast.txt]
  | Ast.TyCon (_, args) | Ast.TyTuple args -> List.fold_left ty_vars acc args
  | Ast.TyArrow (a, b) | Ast.TyNatOp (_, a, b) -> ty_vars (ty_vars acc a) b
  | Ast.TyRecord flds -> List.fold_left (fun acc (_, t) -> ty_vars acc t) acc flds
  | Ast.TyLinear (_, t) | Ast.TyRefine (t, _, _) -> ty_vars acc t
  | Ast.TyNat _ | Ast.TyChan _ -> acc

let rec map_ty_vars f (t : Ast.ty) : Ast.ty =
  let go = map_ty_vars f in
  match t with
  | Ast.TyVar n -> f n
  | Ast.TyCon (c, args) -> Ast.TyCon (c, List.map go args)
  | Ast.TyTuple args -> Ast.TyTuple (List.map go args)
  | Ast.TyArrow (a, b) -> Ast.TyArrow (go a, go b)
  | Ast.TyNatOp (op, a, b) -> Ast.TyNatOp (op, go a, go b)
  | Ast.TyRecord flds -> Ast.TyRecord (List.map (fun (n, t) -> (n, go t)) flds)
  | Ast.TyLinear (l, t) -> Ast.TyLinear (l, go t)
  | Ast.TyRefine (t, b, p) -> Ast.TyRefine (go t, b, p)
  | Ast.TyNat _ | Ast.TyChan _ -> t

(* A renderer that writes each variable as its position in [order]. *)
let canonical_renderer order =
  let rn v =
    let rec idx i = function
      | [] -> v
      | x :: _ when x = v -> Printf.sprintf "'%d" i
      | _ :: r -> idx (i + 1) r in
    idx 0 order in
  let render t =
    Fmt.fmt_ty (map_ty_vars (fun n -> Ast.TyVar { n with Ast.txt = rn n.Ast.txt }) t) in
  (rn, render)

let fn_key (f : fn_sig) =
  match f.sig_ast with
  | None -> f.params_raw ^ " : " ^ f.return_raw
  | Some a ->
    let param_ty = function
      | Ast.FPNamed p | Ast.FPDefault (p, _) -> p.Ast.param_ty
      | Ast.FPPat _ -> None in
    let ptys = List.concat_map (List.filter_map param_ty) a.fa_params in
    let ret = a.fa_ret in
    let bounds = List.map (fun ((n : Ast.name), t) -> (n.Ast.txt, t)) a.fa_bounds in
    let order = List.fold_left ty_vars [] (ptys @ Option.to_list ret) in
    let order =
      List.fold_left (fun acc (v, _) -> if List.mem v acc then acc else acc @ [v])
        order bounds in
    let order = List.fold_left ty_vars order (List.map snd bounds) in
    let rn, render = canonical_renderer order in
    let param_key = function
      | Ast.FPNamed p ->
        Fmt.fmt_lin p.Ast.param_lin
        ^ (match p.Ast.param_ty with Some t -> render t | None -> "_")
      | Ast.FPDefault (p, _) ->
        Fmt.fmt_lin p.Ast.param_lin
        ^ (match p.Ast.param_ty with Some t -> render t | None -> "_")
        ^ " = default"
      | Ast.FPPat pat -> "pattern " ^ Fmt.fmt_pat pat in
    let clauses =
      List.map (fun ps -> "(" ^ String.concat ", " (List.map param_key ps) ^ ")")
        a.fa_params in
    let ret_key = match ret with Some t -> render t | None -> "" in
    let bounds_key =
      List.map (fun (v, t) -> rn v ^ " : " ^ render t) bounds in
    String.concat " | " clauses ^ " : " ^ ret_key
    ^ (if bounds_key = [] then "" else " where " ^ String.concat ", " bounds_key)

let type_key (t : type_decl) =
  match t.type_ast with
  | None -> t.body_raw
  | Some a ->
    (* The declared parameters fix the variable order, so `Pair(a, b)` and
       `Pair(x, y)` with the body renamed to match agree, and an added or
       removed parameter changes the key: every use `Box(Int)` breaks. *)
    let tys =
      match a.ta_def with
      | Ast.TDAlias ty -> [ ty ]
      | Ast.TDVariant vs -> List.concat_map (fun v -> v.Ast.var_args) vs
      | Ast.TDRecord fs -> List.map (fun f -> f.Ast.fld_ty) fs in
    let order = List.fold_left ty_vars a.ta_params tys in
    let rn, render = canonical_renderer order in
    let body =
      match a.ta_def with
      | Ast.TDAlias ty -> render ty
      | Ast.TDVariant vs ->
        String.concat " | "
          (List.map
             (fun (v : Ast.variant) ->
                (match v.Ast.var_vis with Ast.Private -> "private " | Ast.Public -> "")
                ^ v.Ast.var_name.Ast.txt
                ^ (match v.Ast.var_args with
                   | [] -> ""
                   | args ->
                     "(" ^ String.concat ", " (List.map (fun t -> render t) args)
                     ^ ")"))
             vs)
      | Ast.TDRecord fs ->
        "{ "
        ^ String.concat ", "
          (List.map
             (fun (f : Ast.field) ->
                Fmt.fmt_lin f.Ast.fld_lin ^ f.Ast.fld_name.Ast.txt ^ " : "
                ^ render f.Ast.fld_ty)
             fs)
        ^ " }" in
    "(" ^ String.concat ", " (List.map rn a.ta_params) ^ ") = " ^ body

(** Diff two API surfaces and return the list of changes. *)
let diff ~old_ ~new_ =
  let changes = ref [] in
  (* Check for removed or changed functions *)
  List.iter (fun old_fn ->
      match List.find_opt (fun f -> f.name = old_fn.name) new_.fns with
      | None ->
        changes := RemovedFn old_fn :: !changes
      | Some new_fn ->
        if fn_key old_fn <> fn_key new_fn then
          changes := ChangedFn (old_fn, new_fn) :: !changes
        else if new_fn.return_raw = ""
             && old_fn.clauses_raw <> new_fn.clauses_raw then
          changes := UnverifiableFn (old_fn, new_fn) :: !changes
    ) old_.fns;
  (* Check for added functions *)
  List.iter (fun new_fn ->
      if not (List.exists (fun f -> f.name = new_fn.name) old_.fns) then
        changes := AddedFn new_fn :: !changes
    ) new_.fns;
  (* Check for removed or changed types *)
  List.iter (fun old_ty ->
      match List.find_opt (fun t -> t.type_name = old_ty.type_name) new_.types with
      | None ->
        changes := RemovedType old_ty :: !changes
      | Some new_ty ->
        if type_key old_ty <> type_key new_ty then
          changes := ChangedType (old_ty, new_ty) :: !changes
    ) old_.types;
  (* Check for added types *)
  List.iter (fun new_ty ->
      if not (List.exists (fun t -> t.type_name = new_ty.type_name) old_.types) then
        changes := AddedType new_ty :: !changes
    ) new_.types;
  List.rev !changes

(* ------------------------------------------------------------------ *)
(*  Semver enforcement (for forge publish)                            *)
(* ------------------------------------------------------------------ *)

(** Result of checking whether the declared semver bump is sufficient. *)
type semver_check =
  | Ok                   (** declared bump is correct or conservative *)
  | UnderBumped of {
      required    : change_kind;
      declared    : change_kind;
      breaking    : change list;
    }

(** Check whether [declared_bump] is sufficient for [changes].
    Returns Ok if the declared bump ≥ required bump, UnderBumped otherwise.
    Always returns Ok for pre-1.0.0 packages. *)
let check_semver_bump ~old_version ~new_version ~changes =
  let open Resolver_version in
  let old_v = match parse old_version with Ok v -> v | Error _ -> zero in
  (* Pre-1.0.0: skip enforcement *)
  if old_v.major = 0 then Ok
  else begin
    let new_v = match parse new_version with Ok v -> v | Error _ -> zero in
    let declared =
      if new_v.major > old_v.major then Major
      else if new_v.minor > old_v.minor then Minor
      else Patch
    in
    let required = required_bump changes in
    match required, declared with
    | Major, (Minor | Patch) ->
      let breaking = List.filter (fun c -> change_kind_of c = Major) changes in
      UnderBumped { required; declared; breaking }
    | Minor, Patch ->
      let additive = List.filter (fun c -> change_kind_of c = Minor) changes in
      UnderBumped { required; declared; breaking = additive }
    | _ -> Ok
  end

(* ------------------------------------------------------------------ *)
(*  Human-readable output                                             *)
(* ------------------------------------------------------------------ *)

let string_of_change_kind = function
  | Major -> "MAJOR"
  | Minor -> "MINOR"
  | Patch -> "PATCH"

let string_of_change = function
  | RemovedFn f ->
    Printf.sprintf "  • Removed function `%s`" f.name
  | ChangedFn (old_f, new_f) ->
    Printf.sprintf "  • Function `%s` signature changed:\n\
                    \      was: fn %s(%s)%s\n\
                    \      now: fn %s(%s)%s"
      old_f.name
      old_f.name old_f.params_raw
      (if old_f.return_raw = "" then "" else " : " ^ old_f.return_raw)
      new_f.name new_f.params_raw
      (if new_f.return_raw = "" then "" else " : " ^ new_f.return_raw)
  | UnverifiableFn (_, f) ->
    Printf.sprintf "  • Function `%s` changed, and it has no return-type annotation,\n\
                    \      so forge cannot tell whether what it returns changed.\n\
                    \      Add a return-type annotation to get a precise verdict\n\
                    \      on later releases."
      f.name
  | AddedFn f ->
    Printf.sprintf "  • Added function `%s`" f.name
  | RemovedType t ->
    Printf.sprintf "  • Removed type `%s`" t.type_name
  | ChangedType (old_t, new_t) ->
    Printf.sprintf "  • Type `%s` changed:\n\
                    \      was: %s\n\
                    \      now: %s"
      old_t.type_name old_t.body_raw new_t.body_raw
  | AddedType t ->
    Printf.sprintf "  • Added type `%s`" t.type_name

let format_underBumped name old_ver new_ver required _declared breaking =
  Printf.sprintf
    "-- SEMVER VIOLATION -------------------------------- forge.toml\n\n\
     You are publishing `%s %s` but your changes require a %s version bump.\n\n\
     %s changes detected:\n\n\
     %s\n\n\
     To publish this change, bump the version to `%s` in forge.toml.\n"
    name new_ver
    (string_of_change_kind required)
    (string_of_change_kind required)
    (String.concat "\n" (List.map string_of_change breaking))
    (match required with
     | Major ->
       let v = match Resolver_version.parse old_ver with
         | Ok v  -> Printf.sprintf "%d.0.0" (v.Resolver_version.major + 1)
         | Error _ -> "NEXT_MAJOR.0.0"
       in v
     | Minor ->
       let v = match Resolver_version.parse old_ver with
         | Ok v  ->
           Printf.sprintf "%d.%d.0" v.Resolver_version.major (v.Resolver_version.minor + 1)
         | Error _ -> "MAJOR.NEXT_MINOR.0"
       in v
     | Patch -> new_ver)
