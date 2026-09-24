(** forge audit — what capabilities do my dependencies ask for, and did that
    change?

    A March library cannot acquire an ambient capability: everything it does to
    the outside world is declared with [needs] and checked by the compiler. That
    makes a question npm, cargo, hex and pip structurally cannot answer
    mechanically — "did this update start touching the filesystem?" — a matter
    of reading declarations rather than of heuristics, sandboxes, or trust.

    [forge audit] extracts the capability set of every (transitive) dependency
    and compares it against a recorded baseline. A dependency that previously
    needed [IO.FileRead] and now also needs [IO.FileWrite] and [IO.Network] is
    reported, and the command exits non-zero so CI can gate on it.

    {1 Why the baseline is its own file}

    The baseline lives in [forge.caps.lock], not in [forge.lock].
    [Resolver_lockfile.write] rewrites the lockfile wholesale from the entries
    dependency resolution produced, so a capability set recorded there would be
    silently erased by the next [forge deps] — the failure mode being that the
    gate stops comparing anything and reports success. A separate file is
    written only by this command and cannot be clobbered by resolution.

    {1 What this does NOT claim}

    The capability set is what a package's source *declares*. It is exactly as
    trustworthy as the compiler's enforcement of [needs] — which is to say
    strong for March code, and silent about anything reached through an
    [extern] block, whose capability is declared by the block rather than
    inferred from the C it calls. A package that grows an [extern] therefore
    shows up as [IO.Foreign], not as whatever the foreign code actually does. *)

module A = March_ast.Ast

(* ------------------------------------------------------------------ *)
(*  Capability extraction                                              *)
(* ------------------------------------------------------------------ *)

(** Every [needs] path declared anywhere in [decls], including nested modules.
    Paths are dot-joined ("IO.FileRead"), matching how the compiler and
    [forge cap] spell them. *)
let rec needs_in_decls (decls : A.decl list) : string list =
  List.concat_map
    (function
      | A.DNeeds (paths, _) ->
        (* Render the scope into the reported string: a dependency narrowed to
           IO.FileRead("/etc/app") must not audit identically to one that reads
           anywhere, and the baseline diff compares these strings. *)
        List.map
          (fun (path, scope) ->
             let p = String.concat "." (List.map (fun (n : A.name) -> n.A.txt) path) in
             match scope with None -> p | Some sc -> Printf.sprintf "%s(%s)" p sc)
          paths
      | A.DMod (_, _, inner, _) -> needs_in_decls inner
      | _ -> [])
    decls

let parse_file path : A.decl list option =
  try
    let ic = open_in path in
    let src = really_input_string ic (in_channel_length ic) in
    close_in ic;
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
    let m =
      March_parser.Parser.module_
        (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
    in
    Some m.A.mod_decls
  with _ -> None

(** Recursively collect .march files, skipping the build/cache directory so a
    vendored copy of a dependency's own deps is not counted as this package's
    surface. *)
let march_files_under root =
  let acc = ref [] in
  let rec walk dir =
    match Sys.readdir dir with
    | entries ->
      Array.iter
        (fun name ->
          if name <> ".march" && name <> ".git" then begin
            let path = Filename.concat dir name in
            if Sys.is_directory path then walk path
            else if Filename.check_suffix name ".march" then acc := path :: !acc
          end)
        entries
    | exception Sys_error _ -> ()
  in
  if Sys.file_exists root && Sys.is_directory root then walk root;
  List.sort compare !acc

let sorted_uniq xs = List.sort_uniq compare xs

(** The capability set a package declares, across every .march file it ships.
    A file that fails to parse contributes nothing — [forge build] is where a
    broken dependency should be reported, and failing the audit for it would
    conflate "cannot read" with "asks for nothing". *)
let caps_of_dir (dir : string) : string list =
  march_files_under dir
  |> List.filter_map parse_file
  |> List.concat_map needs_in_decls
  |> sorted_uniq

(** The capability set a package's code INFERS, via `march caps`, rather than
    the set it declares.

    The two miss opposite things, which is why this is a mode rather than a
    replacement (measured, see the coverage note in [scope_note]):
    - declared misses a capability builtin called directly in a body with no
      matching [needs] — that is a warning, not an error
      (specs/todos/2026-08-03-undeclared-capability-is-only-a-warning.md);
    - inferred misses a capability reached through a stdlib or dependency
      FUNCTION rather than a builtin, because it reads each package's OWN
      closures.

    Inferred needs the package to typecheck cleanly, which declared does not,
    so it returns [Error] where [caps_of_dir] would return a partial answer.
    Callers must surface that rather than treating it as "asks for nothing". *)
let inferred_caps_of_dir ~env_prefix (dir : string) : (string list, string) result =
  match Cap_package.of_package ~root:dir ~env_prefix with
  | Ok t -> Ok t.Cap_package.caps
  | Error e -> Error e

(** What this audit does NOT cover. Printed with every report: a bare
    capability list reads as a complete account of what a dependency can do,
    and neither extraction mode is that. *)
let scope_note ~inferred =
  if inferred then
    "note: inferred from each package's own code. Does not cover capabilities
    \      reached through a stdlib or dependency function, or through FFI.
    \      `forge cap inspect <binary>` is the sound check for a built artifact."
  else
    "note: read from `needs` declarations. Does not cover a capability builtin
    \      called directly in a body without a matching `needs` (a warning, not
    \      an error), or anything reached through FFI. `forge cap inspect <binary>`
    \      is the sound check for a built artifact."

(* ------------------------------------------------------------------ *)
(*  Dependency enumeration                                             *)
(* ------------------------------------------------------------------ *)

(* Git/registry deps are installed under [~/.march/cas/deps/<name>] (see
   [Project.dep_root_dir]) — NOT under the project root. [base] is the
   directory of the project that DECLARED [dep], needed to resolve a
   relative PathDep. *)
let dep_dir ~base ~name ~dep =
  match Project.dep_root_dir ~project_root:base (name, dep) with
  | Some d -> d
  | None -> Filename.concat base name

(** Every transitive dependency paired with the capabilities it declares.
    Mirrors [Cmd_licenses.collect]'s walk so the two agree on what counts as a
    dependency. A dep whose directory is missing yields an empty set rather
    than being skipped: "not installed" and "needs nothing" must not look the
    same to a reviewer, so the caller distinguishes them via [installed]. *)
type dep_caps = {
  dc_name : string;
  dc_caps : string list;
  dc_installed : bool;
}

(** What one audit run found. [deps] is every dependency whose set is known
    (in declared mode, all of them). [unanalyzable] is only ever non-empty
    with [--inferred]: each dependency whose code `march caps` could not
    analyze, with the reason. Those are deliberately NOT in [deps] with an
    empty set — "could not analyze" and "asks for nothing" must never look
    the same — so every consumer has to decide what to do with them. *)
type collected = {
  deps : dep_caps list;
  unanalyzable : (string * string) list;  (** name, reason *)
}

(* ------------------------------------------------------------------ *)
(*  Inferred-set cache                                                 *)
(* ------------------------------------------------------------------ *)

(* Each `march caps` run loads the whole stdlib plus the dependency's tree
   (minutes for a handful of real dependencies), and the answer is a pure
   function of three things, all folded into the key:
   - the dependency's own files (every .march file under its root),
   - its lib path: the exact MARCH_LIB_PATH/PATH prefix it is analyzed
     under, AND the contents of every .march file on that path — the prefix
     string alone misses a path dependency edited in place (the limitation
     [Cmd_build.check_all_cache_key] documents),
   - the compiler ([Cap_package.compiler_identity]), so a new toolchain
     re-analyzes everything.
   Only successful analyses are cached. A failure is re-run every time, so a
   dependency that is fixed upstream, or failed for a transient reason, is
   never pinned as unanalyzable. Same shape as [Cmd_build.check_all]'s
   marker cache, which lives beside this one under .forge/. *)

let audit_cache_dir root = Filename.concat root (Filename.concat ".forge" "audit-cache")

let read_bytes path =
  let ic = open_in_bin path in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  s

(* Every .march file on [dir]'s MARCH_LIB_PATH that comes from another
   package: the same transitive walk and per-dep lib-path expansion
   [Cmd_build.lib_path_env] performs (dev scope, as it defaults to). The
   package's own lib/, config/ and .forge/generated are under [dir] and are
   already covered by [march_files_under dir]. *)
let lib_path_files dir =
  match Project.load_from_dir dir with
  | Error _ -> []
  | Ok dp ->
    let coords = Project.dep_coords ~project_root:dir in
    Cmd_build.collect_transitive_deps ~coords (Hashtbl.create 16)
      (dir, Cmd_build.build_scope ~release:false dp)
    |> List.concat_map (fun (root, n, d) -> Cmd_build.dep_to_lib_paths ~coords ~root (n, d))
    |> List.concat_map (fun ld ->
        match Sys.readdir ld with
        | entries ->
          Array.to_list entries
          |> List.filter (fun f -> Filename.check_suffix f ".march")
          |> List.map (Filename.concat ld)
        | exception Sys_error _ -> [])
    |> List.sort_uniq compare

let inferred_cache_key ~identity ~env_prefix ~dir =
  let buf = Buffer.create 65536 in
  let add s = Buffer.add_string buf s; Buffer.add_char buf '\x00' in
  add "forge-audit-inferred-v1";
  add identity;
  add env_prefix;
  add dir;
  let add_file f =
    add f;
    add (try read_bytes f with Sys_error _ -> "<unreadable>")
  in
  List.iter add_file (march_files_under dir);
  add "--lib-path--";
  List.iter add_file (lib_path_files dir);
  Digest.to_hex (Digest.string (Buffer.contents buf))

let cache_magic = "forge-audit-caps v1"

(* A hit is only a file that starts with [cache_magic]: an empty or
   truncated file must never read back as "no capabilities". *)
let cache_read path =
  match read_bytes path with
  | exception Sys_error _ -> None
  | s ->
    (match String.split_on_char '\n' s with
     | first :: rest when first = cache_magic ->
       Some (List.filter (fun c -> String.trim c <> "") rest)
     | _ -> None)

let cache_write path caps =
  try
    Project.mkdir_p (Filename.dirname path);
    let tmp = path ^ ".tmp" in
    let oc = open_out_bin tmp in
    output_string oc (String.concat "\n" (cache_magic :: caps) ^ "\n");
    close_out oc;
    Sys.rename tmp path
  with Sys_error _ | Unix.Unix_error _ -> ()

exception Toolchain_unusable of string

let collect ?(inferred = false) (proj : Project.project) : (collected, string) result =
  let root = proj.Project.root in
  (* Each dependency is analyzed in ITS OWN scope. Using the application's
     lib path pulls the app's sources onto MARCH_LIB_PATH, so the app's own
     type errors abort every dependency's analysis. *)
  let env_for dir =
    match Project.load_from_dir dir with
    | Ok dp -> Cmd_build.lib_path_env dp
    | Error _ -> ""
  in
  (* The toolchain every dependency's `march caps` resolves to: the same
     PATH prefix [Cmd_build.lib_path_env] puts in front of each command. A
     pinned toolchain that is not installed is an error here rather than a
     silent fall-through to whatever `march` is on PATH. *)
  let toolchain_prefix =
    lazy (match Toolchain.path_prefix () with
        | Ok p -> p
        | Error e -> raise (Toolchain_unusable e))
  in
  let identity =
    lazy (Cap_package.compiler_identity ~toolchain_prefix:(Lazy.force toolchain_prefix))
  in
  (* Probed once per audit, and only before the first real `march caps`:
     a fully cached run never needs it (every hit was produced by this exact
     compiler), so a hit prints exactly what a miss does. *)
  let probe =
    lazy (match Cap_package.probe_caps_support
                  ~toolchain_prefix:(Lazy.force toolchain_prefix) with
        | Ok () -> ()
        | Error e -> raise (Toolchain_unusable e))
  in
  let inferred_for dir =
    let env_prefix = env_for dir in
    let key = inferred_cache_key ~identity:(Lazy.force identity) ~env_prefix ~dir in
    let path = Filename.concat (audit_cache_dir root) (key ^ ".caps") in
    match cache_read path with
    | Some caps -> Ok caps
    | None ->
      Lazy.force probe;
      (match inferred_caps_of_dir ~env_prefix dir with
       | Ok caps -> cache_write path caps; Ok caps
       | Error e -> Error e)
  in
  let tbl : (string, dep_caps) Hashtbl.t = Hashtbl.create 32 in
  let failed : (string, string) Hashtbl.t = Hashtbl.create 8 in
  let rec visit ~base ~name ~dep =
    if not (Hashtbl.mem tbl name || Hashtbl.mem failed name) then begin
      let dir = dep_dir ~base ~name ~dep in
      let installed = Sys.file_exists dir && Sys.is_directory dir in
      let caps =
        if not installed then Ok []
        else if inferred then inferred_for dir
        else Ok (caps_of_dir dir)
      in
      (match caps with
       | Ok caps ->
         Hashtbl.replace tbl name { dc_name = name; dc_caps = caps; dc_installed = installed }
       | Error e -> Hashtbl.replace failed name e);
      match Project.load_from_dir dir with
      | Ok p -> List.iter (fun (cn, cd) -> visit ~base:dir ~name:cn ~dep:cd) p.Project.deps
      | Error _ -> ()
    end
  in
  match List.iter (fun (n, d) -> visit ~base:root ~name:n ~dep:d) proj.Project.deps with
  | exception Toolchain_unusable e -> Error e
  | () ->
    Ok { deps =
           Hashtbl.fold (fun _ v acc -> v :: acc) tbl []
           |> List.sort (fun a b -> compare a.dc_name b.dc_name);
         unanalyzable =
           Hashtbl.fold (fun n e acc -> (n, e) :: acc) failed []
           |> List.sort compare }

(* ------------------------------------------------------------------ *)
(*  Baseline file                                                      *)
(* ------------------------------------------------------------------ *)

let baseline_path root = Filename.concat root "forge.caps.lock"

let write_baseline path (deps : dep_caps list) =
  let oc = open_out path in
  output_string oc
    "# Capability baseline — written by `forge audit --record`.\n\
     # Each entry is the set of `needs` declarations a dependency ships.\n\
     # `forge audit` fails when a dependency asks for more than is recorded here.\n\n";
  List.iter
    (fun d ->
      output_string oc "[[package]]\n";
      output_string oc (Printf.sprintf "name = %S\n" d.dc_name);
      output_string oc
        (Printf.sprintf "caps = [%s]\n\n"
           (String.concat ", " (List.map (fun c -> Printf.sprintf "%S" c) d.dc_caps))))
    deps;
  close_out oc

(** Deliberately a small hand parser over the exact shape [write_baseline]
    emits, matching how [Resolver_lockfile] reads forge.lock. *)
let read_baseline path : (string * string list) list =
  if not (Sys.file_exists path) then []
  else begin
    let ic = open_in path in
    let entries = ref [] and cur_name = ref None in
    let trim = String.trim in
    let unquote s =
      let s = trim s in
      let n = String.length s in
      if n >= 2 && s.[0] = '"' && s.[n - 1] = '"' then String.sub s 1 (n - 2) else s
    in
    (try
       while true do
         let line = trim (input_line ic) in
         if line = "" || String.length line > 0 && line.[0] = '#' then ()
         else if line = "[[package]]" then cur_name := None
         else
           match String.index_opt line '=' with
           | None -> ()
           | Some i ->
             let key = trim (String.sub line 0 i) in
             let value = trim (String.sub line (i + 1) (String.length line - i - 1)) in
             if key = "name" then cur_name := Some (unquote value)
             else if key = "caps" then begin
               let v = trim value in
               let inner =
                 let n = String.length v in
                 if n >= 2 && v.[0] = '[' && v.[n - 1] = ']' then String.sub v 1 (n - 2)
                 else v
               in
               let caps =
                 String.split_on_char ',' inner
                 |> List.map unquote
                 |> List.filter (fun s -> s <> "")
               in
               match !cur_name with
               | Some n -> entries := (n, sorted_uniq caps) :: !entries
               | None -> ()
             end
       done
     with End_of_file -> ());
    close_in ic;
    List.rev !entries
  end

(* ------------------------------------------------------------------ *)
(*  Diffing and reporting                                              *)
(* ------------------------------------------------------------------ *)

type change =
  | Added of string * string list      (** dependency is new; its capabilities *)
  | Widened of string * string list    (** existing dependency, newly-requested caps *)
  | Narrowed of string * string list   (** existing dependency, caps it no longer asks for *)
  | Removed of string                  (** dependency is gone *)

(** Only [Added] and [Widened] represent new authority, and only those fail the
    audit. A dependency that stops asking for a capability is reported for
    completeness but is not a reason to block a build — narrowing is the
    direction you want. *)
let is_escalation = function
  | Added (_, caps) -> caps <> []
  | Widened _ -> true
  | Narrowed _ | Removed _ -> false

let diff ~(baseline : (string * string list) list) ~(current : dep_caps list) : change list =
  let changes = ref [] in
  List.iter
    (fun d ->
      match List.assoc_opt d.dc_name baseline with
      | None -> changes := Added (d.dc_name, d.dc_caps) :: !changes
      | Some old ->
        let gained = List.filter (fun c -> not (List.mem c old)) d.dc_caps in
        let lost = List.filter (fun c -> not (List.mem c d.dc_caps)) old in
        if gained <> [] then changes := Widened (d.dc_name, gained) :: !changes;
        if lost <> [] then changes := Narrowed (d.dc_name, lost) :: !changes)
    current;
  List.iter
    (fun (name, _) ->
      if not (List.exists (fun d -> d.dc_name = name) current) then
        changes := Removed name :: !changes)
    baseline;
  List.rev !changes

let string_of_change = function
  | Added (n, []) -> Printf.sprintf "  + %s — new dependency, declares no capabilities" n
  | Added (n, caps) ->
    Printf.sprintf "  + %s — new dependency, declares: %s" n (String.concat ", " caps)
  | Widened (n, caps) ->
    Printf.sprintf "  ! %s — now ALSO needs: %s" n (String.concat ", " caps)
  | Narrowed (n, caps) ->
    Printf.sprintf "  - %s — no longer needs: %s" n (String.concat ", " caps)
  | Removed n -> Printf.sprintf "  - %s — dependency removed" n

(* ------------------------------------------------------------------ *)
(*  Entry points                                                       *)
(* ------------------------------------------------------------------ *)

let plural n ~one ~many = if n = 1 then one else many

(* How many lines of a reason to print per dependency. `march caps` on a
   dependency with real type errors prints every one of them; the first few
   say what is wrong, and `march check` reproduces the rest. *)
let reason_lines = 8

(** List every dependency whose capability set could not be computed, and
    why. Printed by every mode that collected any, flag or not: with
    [--allow-unanalyzable] these are excluded from the gate, never from the
    report. *)
let print_unanalyzable ~allowed (un : (string * string) list) =
  if un <> [] then begin
    let n = List.length un in
    Printf.printf "%d dependenc%s NOT ANALYZABLE — capability set unknown%s:\n" n
      (plural n ~one:"y" ~many:"ies")
      (if allowed then " (excluded from the gate by --allow-unanalyzable)" else "");
    List.iter
      (fun (name, reason) ->
        Printf.printf "  ? %s — NOT ANALYZABLE\n" name;
        let lines =
          String.split_on_char '\n' (String.trim reason)
          |> List.filter (fun l -> String.trim l <> "")
        in
        List.iteri
          (fun i l -> if i < reason_lines then Printf.printf "      %s\n" l)
          lines;
        let more = List.length lines - reason_lines in
        if more > 0 then Printf.printf "      … %d more line%s\n" more (plural more ~one:"" ~many:"s"))
      un;
    print_endline ""
  end

let unanalyzable_hint =
  "Fix them (`march check` over the dependency reproduces the error), or pass \
   --allow-unanalyzable to gate on the analyzable subset while these stay listed."

let print_sets ~inferred (c : collected) =
  if c.deps = [] && c.unanalyzable = [] then print_endline "no dependencies"
  else
    List.iter
      (fun d ->
        if not d.dc_installed then
          Printf.printf "  %s — not installed (run `forge deps`)\n" d.dc_name
        else if d.dc_caps = [] then Printf.printf "  %s — no capabilities\n" d.dc_name
        else Printf.printf "  %s — %s\n" d.dc_name (String.concat ", " d.dc_caps))
      c.deps;
  print_endline "";
  print_endline (scope_note ~inferred)

(** Print the capability set of every dependency. *)
let show ?(inferred = false) (proj : Project.project) : (unit, string) result =
  match collect ~inferred proj with
  | Error e -> Error e
  | Ok c ->
    print_sets ~inferred c;
    print_endline "";
    print_unanalyzable ~allowed:false c.unanalyzable;
    Ok ()

let record ?(inferred = false) ?(allow_unanalyzable = false) (proj : Project.project)
  : (unit, string) result =
  match collect ~inferred proj with
  | Error e -> Error e
  | Ok c ->
  let deps = c.deps in
  let missing = List.filter (fun d -> not d.dc_installed) deps in
  if missing <> [] then
    Error
      (Printf.sprintf
         "cannot record a baseline while %d dependenc%s not installed (%s) — run \
          `forge deps` first.\n\
          Recording now would treat them as asking for nothing, and a later \
          install would look like an escalation."
         (List.length missing)
         (if List.length missing = 1 then "y is" else "ies are")
         (String.concat ", " (List.map (fun d -> d.dc_name) missing)))
  else if c.unanalyzable <> [] && not allow_unanalyzable then begin
    print_unanalyzable ~allowed:false c.unanalyzable;
    let n = List.length c.unanalyzable in
    Error
      (Printf.sprintf
         "refusing to record a baseline while %d dependenc%s cannot be analyzed: \
          recording %s would treat %s as asking for nothing.\n%s"
         n (if n = 1 then "y" else "ies")
         (plural n ~one:"it" ~many:"them")
         (plural n ~one:"it" ~many:"them")
         unanalyzable_hint)
  end
  else begin
    let path = baseline_path proj.Project.root in
    (* An unanalyzable dependency's previously recorded set is carried over
       unchanged: dropping it would erase a reviewed baseline, and writing an
       empty one would record "asks for nothing". One that was never
       recorded stays out of the file until it can be analyzed. *)
    let previous = read_baseline path in
    let carried =
      List.filter_map
        (fun (name, _) ->
          match List.assoc_opt name previous with
          | Some caps -> Some { dc_name = name; dc_caps = caps; dc_installed = true }
          | None -> None)
        c.unanalyzable
    in
    write_baseline path
      (List.sort (fun a b -> compare a.dc_name b.dc_name) (deps @ carried));
    print_unanalyzable ~allowed:true c.unanalyzable;
    Printf.printf "recorded %d dependenc%s to %s\n" (List.length deps)
      (if List.length deps = 1 then "y" else "ies")
      (Filename.basename path);
    if c.unanalyzable <> [] then
      Printf.printf
        "not recorded: %d unanalyzable dependenc%s (%d previously recorded set%s \
         kept as-is)\n"
        (List.length c.unanalyzable)
        (plural (List.length c.unanalyzable) ~one:"y" ~many:"ies")
        (List.length carried)
        (plural (List.length carried) ~one:"" ~many:"s");
    Ok ()
  end

(** Compare against the recorded baseline. Returns the exit code: 0 when the
    audit passes, 1 when a dependency gained authority — or, without
    [allow_unanalyzable], when any dependency could not be analyzed. *)
let check_proj ?(inferred = false) ?(allow_unanalyzable = false) (proj : Project.project)
  : (int, string) result =
  match collect ~inferred proj with
  | Error e -> Error e
  | Ok c ->
  let path = baseline_path proj.Project.root in
  let current = c.deps in
  let un_names = List.map fst c.unanalyzable in
  (* Without the flag an unanalyzable dependency fails the audit: its set is
     unknown, so the audit cannot vouch for it. *)
  let unanalyzable_verdict () =
    print_unanalyzable ~allowed:allow_unanalyzable c.unanalyzable;
    if c.unanalyzable <> [] && not allow_unanalyzable then begin
      let n = List.length c.unanalyzable in
      Printf.printf "%d dependenc%s could not be analyzed, so this audit cannot vouch for %s.\n"
        n (if n = 1 then "y" else "ies") (plural n ~one:"it" ~many:"them");
      print_endline unanalyzable_hint;
      1
    end
    else 0
  in
  if not (Sys.file_exists path) then begin
    print_endline "no capability baseline recorded.";
    print_endline "";
    print_sets ~inferred c;
    print_endline "";
    print_endline "Record the current set with `forge audit --record`, commit \
                   forge.caps.lock, and this command will fail whenever a \
                   dependency asks for more.";
    print_endline "";
    Ok (unanalyzable_verdict ())
  end
  else begin
    (* Gate on the analyzable subset: an unanalyzable dependency's baseline
       entry is set aside rather than compared, so it is neither reported as
       removed nor as unchanged. It is listed below instead. *)
    let baseline =
      List.filter (fun (n, _) -> not (List.mem n un_names)) (read_baseline path)
    in
    let changes = diff ~baseline ~current in
    let escalations = List.filter is_escalation changes in
    let escalation_code =
      if changes = [] then begin
        Printf.printf "capabilities unchanged across %d %sdependenc%s\n"
          (List.length current)
          (if c.unanalyzable = [] then "" else "analyzable ")
          (if List.length current = 1 then "y" else "ies");
        0
      end
      else begin
        List.iter (fun c -> print_endline (string_of_change c)) changes;
        print_endline "";
        if escalations = [] then begin
          print_endline "No new capabilities requested. Refresh the baseline with \
                         `forge audit --record`.";
          0
        end
        else begin
          Printf.printf
            "%d dependenc%s asking for capabilities it did not have.\n"
            (List.length escalations)
            (if List.length escalations = 1 then "y is" else "ies are");
          print_endline "Review the change, then accept it with `forge audit --record`.";
          1
        end
      end
    in
    if c.unanalyzable <> [] then print_endline "";
    let un_code = unanalyzable_verdict () in
    Ok (max escalation_code un_code)
  end

(** CLI entry. [record] rewrites the baseline; otherwise compare against it.
    Returns the process exit code so the caller can gate CI on it. *)
let run ?(record_mode = false) ?(inferred = false) ?(allow_unanalyzable = false) ()
  : (int, string) result =
  if allow_unanalyzable && not inferred then
    Error "--allow-unanalyzable only applies with --inferred: reading `needs` \
           declarations never fails to analyze a dependency."
  else
  match Project.load () with
  | Error e -> Error e
  | Ok proj ->
    if record_mode then
      match record ~inferred ~allow_unanalyzable proj with
      | Ok () -> Ok 0
      | Error m -> Error m
    else check_proj ~inferred ~allow_unanalyzable proj
