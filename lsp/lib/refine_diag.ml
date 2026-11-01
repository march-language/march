(** Refinement diagnostics in the editor, and their invalidation when a
    dependency's reflected body changes (refinement reflection §7.2, I8).

    The analysis the server runs per keystroke typechecks; it never ran the
    refinement checker.  This module runs it, the way [Refine_command] does:
    `march --check --check-json --reflect-deps <file>` (the pipeline that
    turns a file into a checkable module lives in bin/main.ml), on the file
    as saved on disk, and keeps two things per file:

    - its refinement diagnostics (the `refinement_*` / `reflect_*` codes),
      merged into what the server publishes;
    - its DEPENDENCY KEY: the D17 logic hash of every reflected function in
      the frontier of any stage-2 query the check ran (`reflect-dep` lines),
      whether or not that function reached a proof's unsat core.  Keying on
      the core would miss a definition a cold run needed and a warm run did
      not, and a skipped obligation has no core at all, so a dependency edit
      that would turn a skip into a proof would never re-check the file.

    When a file is saved (or changes on disk), its own check reports the
    current hash of every reflected function it defines (`reflect-def`);
    every other checked file whose key names a function of that file with a
    different hash, or one that is no longer reflected, is stale and is
    re-checked.  A dependency edit that leaves every frontier hash alone
    re-checks nothing.

    Lemmas (phase 2): a dependency lemma a file calls belongs in the key too,
    with its post hash, its body hash and whether it was admitted, so a lemma
    that stops proving withdraws its callers' facts.  [lemma_key] is that
    hook; it is empty until `@[lemma]` exists. *)

type diag = {
  d_code : string;
  d_severity : string;  (** [error] / [warning] / [hint] *)
  d_line : int;  (** 1-based *)
  d_col : int;  (** 0-based byte column *)
  d_end_line : int;
  d_end_col : int;
  d_message : string;
}

(** One dependency: (file, function display name, D17 hash). *)
type dep = { dep_file : string; dep_name : string; dep_hash : string }

type result = { r_diags : diag list; r_deps : dep list; r_defs : dep list }

let canon (f : string) = try Unix.realpath f with Unix.Unix_error _ -> f

(** The compiler: [MARCH_LSP_COMPILER] when set, else `march` on PATH. *)
let compiler () = match Sys.getenv_opt "MARCH_LSP_COMPILER" with Some c when c <> "" -> c | _ -> "march"

let refinement_code c =
  List.exists (fun p -> String.starts_with ~prefix:p c) [ "refinement_"; "reflect_"; "predicate_eq"; "invalid_measure" ]

(* The MARCH_LIB_PATH a file is checked with: the forge project's library
   directories, or the file's own directory (its siblings, as the resolver
   would find them in a project). *)
let lib_path file =
  let dir = Filename.dirname file in
  match Forge_config.find_forge_root dir with
  | Some root -> String.concat ":" (Forge_config.project_lib_paths root)
  | None -> dir

let read_file p = try Some (In_channel.with_open_bin p In_channel.input_all) with Sys_error _ -> None

(* Test-only perturbation (the RED control of the frontier key): key on the
   functions the proofs' unsat cores name (`uses:`) instead. *)
let key_on_core () = Sys.getenv_opt "MARCH_REFLECT_PERTURB" = Some "deps-core"

let parse ~(file : string) (stdout : string) (stderr : string) : result =
  let base = Filename.basename file in
  let diags =
    String.split_on_char '\n' stdout
    |> List.filter_map (fun l ->
           match Yojson.Safe.from_string l with
           | `Assoc kv -> (
             let str k = match List.assoc_opt k kv with Some (`String s) -> s | _ -> "" in
             let int k = match List.assoc_opt k kv with Some (`Int n) -> n | _ -> 0 in
             let f = str "file" in
             let mine = f = file || f = base || canon f = canon file in
             match str "code" with
             | c when mine && refinement_code c ->
               Some
                 { d_code = c; d_severity = str "severity"; d_line = int "start_line"; d_col = int "start_col";
                   d_end_line = int "end_line"; d_end_col = int "end_col"; d_message = str "message" }
             | _ -> None)
           | _ | (exception _) -> None)
  in
  let rows kind =
    String.split_on_char '\n' stderr
    |> List.filter_map (fun l ->
           match String.split_on_char '\t' l with
           | [ k; f; n; h ] when k = kind ->
             let f = if Filename.is_relative f then Filename.concat (Filename.dirname file) f else f in
             Some { dep_file = canon f; dep_name = n; dep_hash = h }
           | _ -> None)
  in
  let defs = rows "reflect-def" in
  let deps =
    if not (key_on_core ()) then rows "reflect-dep"
    else
      (* `uses: f, g` of the user's proved rows, matched to the frontier rows
         by name. *)
      let used =
        String.split_on_char '\n' stderr
        |> List.concat_map (fun l ->
               match List.rev (String.split_on_char '\t' l) with
               | u :: _ when String.starts_with ~prefix:"uses: " u ->
                 List.map String.trim (String.split_on_char ',' (String.sub u 6 (String.length u - 6)))
               | _ -> [])
      in
      List.filter (fun d -> List.mem d.dep_name used) (rows "reflect-dep")
  in
  { r_diags = diags; r_deps = deps; r_defs = defs }

(** The last check of each file (canonical path). *)
let last : (string, result) Hashtbl.t = Hashtbl.create 16

(** How many refinement checks ran (tests count re-checks). *)
let runs = ref 0

(** Phase 2's hook: the dependency lemmas a file's last check called (post
    hash, body hash, admitted).  Always empty in phase 1. *)
let lemma_key (_file : string) : (string * string * bool) list = []

let command ~(file : string) =
  Printf.sprintf "cd %s && MARCH_LIB_PATH=%s %s --check --check-json --reflect-deps%s %s"
    (Filename.quote (Filename.dirname file))
    (Filename.quote (lib_path file))
    (Filename.quote (compiler ()))
    (if key_on_core () then " --refine-report-sites=all" else "")
    (Filename.quote (Filename.basename file))

(** Check [file] as it is on disk; record and return the result. *)
let check (file : string) : result =
  let file = canon file in
  incr runs;
  let out = Filename.temp_file "march_lsp_refine" ".out" and err = Filename.temp_file "march_lsp_refine" ".err" in
  ignore (Sys.command (Printf.sprintf "%s >%s 2>%s" (command ~file) (Filename.quote out) (Filename.quote err)));
  let o = Option.value ~default:"" (read_file out) and e = Option.value ~default:"" (read_file err) in
  (try Sys.remove out with Sys_error _ -> ());
  (try Sys.remove err with Sys_error _ -> ());
  let r = parse ~file o e in
  Hashtbl.replace last file r;
  r

(** The files (other than [changed]) whose dependency key is stale against
    [defs], the reflected functions [changed] defines now: a key entry for a
    function of [changed] whose hash no reflected function of [changed] has
    any more (its body or its reflectability changed). *)
let stale_dependents ~(changed : string) ~(defs : dep list) : string list =
  let changed = canon changed in
  Hashtbl.fold
    (fun f r acc ->
      if f = changed then acc
      else if
        List.exists
          (fun d ->
            (* By hash alone: the same function is `Util.is_small` in a
               dependent's check and `is_small` when its own file is the
               entry, and the hash covers the function's source text
               (its name included), so it identifies the definition. *)
            d.dep_file = changed && not (List.exists (fun x -> x.dep_hash = d.dep_hash) defs))
          r.r_deps
      then f :: acc
      else acc)
    last []
  |> List.sort compare

(** [changed] was saved or changed on disk: re-check it, then every stale
    dependent.  Returns the re-checked dependents with their results. *)
let on_change (changed : string) : (string * result) list =
  let r = check changed in
  List.map (fun f -> (f, check f)) (stale_dependents ~changed ~defs:r.r_defs)

(** An LSP diagnostic for [d] (byte columns; the caller remaps to UTF-16). *)
let to_lsp (d : diag) : Linol_lsp.Lsp.Types.Diagnostic.t =
  let module T = Linol_lsp.Lsp.Types in
  let pos l c = T.Position.create ~line:(max 0 (l - 1)) ~character:(max 0 c) in
  let severity =
    match d.d_severity with
    | "error" -> T.DiagnosticSeverity.Error
    | "warning" -> T.DiagnosticSeverity.Warning
    | "hint" -> T.DiagnosticSeverity.Hint
    | _ -> T.DiagnosticSeverity.Information
  in
  T.Diagnostic.create
    ~range:(T.Range.create ~start:(pos d.d_line d.d_col) ~end_:(pos d.d_end_line d.d_end_col))
    ~severity ~source:"march-refine" ~code:(`String d.d_code) ~message:(`String d.d_message) ()
