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

let cas_deps_dir root =
  Filename.concat root (Filename.concat ".march" (Filename.concat "cas" "deps"))

let dep_dir ~root ~base ~name ~dep =
  match dep with
  | Project.PathDep p -> if Filename.is_relative p then Filename.concat base p else p
  | _ -> Filename.concat (cas_deps_dir root) name

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

let collect ?(inferred = false) (proj : Project.project) : dep_caps list =
  let root = proj.Project.root in
  (* Each dependency is analyzed in ITS OWN scope. Using the application's
     lib path pulls the app's sources onto MARCH_LIB_PATH, so the app's own
     type errors abort every dependency's analysis. *)
  let env_for dir =
    match Project.load_from_dir dir with
    | Ok dp -> Cmd_build.lib_path_env dp
    | Error _ -> ""
  in
  let tbl : (string, dep_caps) Hashtbl.t = Hashtbl.create 32 in
  let rec visit ~base ~name ~dep =
    if not (Hashtbl.mem tbl name) then begin
      let dir = dep_dir ~root ~base ~name ~dep in
      let installed = Sys.file_exists dir && Sys.is_directory dir in
      Hashtbl.replace tbl name
        { dc_name = name;
          dc_caps =
            (if not installed then []
             else if inferred then
               (match inferred_caps_of_dir ~env_prefix:(env_for dir) dir with
                | Ok caps -> caps
                | Error e ->
                  (* Loud, and NOT an empty set: "could not analyze" and
                     "asks for nothing" must never look the same. *)
                  Printf.eprintf "forge audit: %s: %s\n%!" name e;
                  caps_of_dir dir)
             else caps_of_dir dir);
          dc_installed = installed };
      match Project.load_from_dir dir with
      | Ok p -> List.iter (fun (cn, cd) -> visit ~base:dir ~name:cn ~dep:cd) p.Project.deps
      | Error _ -> ()
    end
  in
  List.iter (fun (n, d) -> visit ~base:root ~name:n ~dep:d) proj.Project.deps;
  Hashtbl.fold (fun _ v acc -> v :: acc) tbl []
  |> List.sort (fun a b -> compare a.dc_name b.dc_name)

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

(** Print the capability set of every dependency. *)
let show ?(inferred = false) (proj : Project.project) : unit =
  let deps = collect ~inferred proj in
  if deps = [] then print_endline "no dependencies"
  else
    List.iter
      (fun d ->
        if not d.dc_installed then
          Printf.printf "  %s — not installed (run `forge deps`)\n" d.dc_name
        else if d.dc_caps = [] then Printf.printf "  %s — no capabilities\n" d.dc_name
        else Printf.printf "  %s — %s\n" d.dc_name (String.concat ", " d.dc_caps))
      deps;
  print_endline "";
  print_endline (scope_note ~inferred)

let record ?(inferred = false) (proj : Project.project) : (unit, string) result =
  let deps = collect ~inferred proj in
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
  else begin
    let path = baseline_path proj.Project.root in
    write_baseline path deps;
    Printf.printf "recorded %d dependenc%s to %s\n" (List.length deps)
      (if List.length deps = 1 then "y" else "ies")
      (Filename.basename path);
    Ok ()
  end

(** Compare against the recorded baseline. Returns the exit code: 0 when the
    audit passes, 1 when a dependency gained authority. *)
let check_proj ?(inferred = false) (proj : Project.project) : int =
  let path = baseline_path proj.Project.root in
  let current = collect ~inferred proj in
  if not (Sys.file_exists path) then begin
    print_endline "no capability baseline recorded.";
    print_endline "";
    show proj;
    print_endline "";
    print_endline "Record the current set with `forge audit --record`, commit \
                   forge.caps.lock, and this command will fail whenever a \
                   dependency asks for more.";
    0
  end
  else begin
    let baseline = read_baseline path in
    let changes = diff ~baseline ~current in
    let escalations = List.filter is_escalation changes in
    if changes = [] then begin
      Printf.printf "capabilities unchanged across %d dependenc%s\n"
        (List.length current)
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
  end

(** CLI entry. [record] rewrites the baseline; otherwise compare against it.
    Returns the process exit code so the caller can gate CI on it. *)
let run ?(record_mode = false) ?(inferred = false) () : (int, string) result =
  match Project.load () with
  | Error e -> Error e
  | Ok proj ->
    if record_mode then
      match record ~inferred proj with Ok () -> Ok 0 | Error m -> Error m
    else Ok (check_proj ~inferred proj)
