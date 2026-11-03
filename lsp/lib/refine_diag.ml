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

    The key also holds the CONTRACT hash of every function of another file
    the file reaches through calls (`reflect-cdep`; review round 1): its
    head's text, parameter and return refinements included, and whether it
    is reflected.  A callee's contract enters a caller's proof with no body
    in any frontier (`Util.need(3)` against `need(n : {v | v > 1})`), a
    callee going from blocked to reflected is in no frontier before the
    edit, and a callee's reflectability rests on its own callees (reached,
    so in the key, wherever they live).

    When a file is saved (or changes on disk), its own check reports the
    current logic hash of every reflected user function (`reflect-def`) and
    the contract hash of every user function (`reflect-cdef`), of every user
    file the check loaded, not only its own: a body edit can change a
    function of ANOTHER file's reflectability (its callee gained an effect).
    Every other checked file whose key names a function of a file that check
    reported with a hash it no longer reports is stale and is re-checked.  A
    dependency edit that moves no frontier hash and no called contract
    re-checks nothing.

    Lemmas (phase 2): a dependency lemma a file calls belongs in the key too,
    with its post hash, its body hash and whether it was admitted, so a lemma
    that stops proving withdraws its callers' facts: the compiler prints
    `lemma-def` / `lemma-dep` rows whose hash carries both ([lemma_key]). *)

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
  let defs = rows "reflect-def" @ rows "reflect-cdef" @ rows "lemma-def" in
  let deps =
    if not (key_on_core ()) then rows "reflect-dep" @ rows "reflect-cdep" @ rows "lemma-dep"
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

(* A lemma row's hash is `lemma:<digest>:admitted|unproved`. *)
let lemma_of (d : dep) : (string * string * bool) option =
  match String.split_on_char ':' d.dep_hash with
  | [ "lemma"; digest; status ] -> Some (d.dep_name, digest, status = "admitted")
  | _ -> None

(** The dependency lemmas a file's last check called: (qualified name,
    digest of its theorem and body, admitted).  They are part of the key
    ([r_deps]), so a dependency lemma that changes or stops proving re-checks
    its callers ([stale_dependents]). *)
let lemma_key (file : string) : (string * string * bool) list =
  match Hashtbl.find_opt last (canon file) with
  | Some r -> List.filter_map lemma_of r.r_deps
  | None -> []

(** Whether the last check of any file proved the lemma [name] (its bare
    or qualified name): [None] when no check reported it. *)
let lemma_admitted (name : string) : bool option =
  let matches n = n = name || String.ends_with ~suffix:("." ^ name) n in
  Hashtbl.fold
    (fun _ r acc ->
      match acc with
      | Some _ -> acc
      | None ->
        List.find_map
          (fun d -> match lemma_of d with Some (n, _, a) when matches n -> Some a | _ -> None)
          (r.r_defs @ r.r_deps))
    last None

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
    [defs], what [changed]'s fresh check reports of every user file it
    loaded (logic and contract hashes): a key entry for a function of a
    reported file (or of [changed] itself) whose hash that file no longer
    has (its body, contract or reflectability changed). *)
let stale_dependents ~(changed : string) ~(defs : dep list) : string list =
  let changed = canon changed in
  let reported f = f = changed || List.exists (fun x -> x.dep_file = f) defs in
  Hashtbl.fold
    (fun f r acc ->
      if f = changed then acc
      else if
        List.exists
          (fun d ->
            (* By (file, qualified name, hash): the compiler prints every
               function by its qualified name (review round 2); twin
               definitions in two nested modules of one file share a hash
               and differ by name. *)
            reported d.dep_file
            && not
                 (List.exists
                    (fun x -> x.dep_file = d.dep_file && x.dep_name = d.dep_name && x.dep_hash = d.dep_hash)
                    defs))
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
