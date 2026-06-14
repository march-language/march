(** forge toolchain — manage installed March compiler toolchains (rustup-style)

      forge toolchain install [<version>]   download + install a release
      forge toolchain use <version>          switch the active toolchain
      forge toolchain list                   list installed toolchains
      forge toolchain uninstall <version>    remove an installed toolchain

    On-disk layout (shared with install.sh):

      ~/.march/versions/<tag>/   extracted release (bin/ stdlib/ runtime/ LICENSE)
      ~/.march/current        -> versions/<tag>      (the active toolchain)
      ~/.march/bin/{march,forge}  wrapper scripts that exec through current/

    The wrapper-through-[current] indirection lets march/forge resolve their
    bundled stdlib/ and runtime/ relative to the real version dir on every OS
    (macOS reports the invoked path; Linux resolves /proc/self/exe). *)

let repo = "march-language/march"

(* ----------------------------------------------------------- layout ----- *)

let march_home () =
  match Sys.getenv_opt "MARCH_HOME" with
  | Some h when h <> "" -> h
  | _ ->
    match Sys.getenv_opt "HOME" with
    | Some h -> Filename.concat h ".march"
    | None   -> failwith "HOME not set"

let versions_dir () = Filename.concat (march_home ()) "versions"
let version_dir tag = Filename.concat (versions_dir ()) tag
let current_link () = Filename.concat (march_home ()) "current"
let bin_dir ()      = Filename.concat (march_home ()) "bin"

(* ----------------------------------------------------- project pin ------ *)

(* A safe release tag / version: non-empty, not a path component (`.`/`..`),
   and only `[A-Za-z0-9._-]`. Tags become filesystem paths (versions/<tag>) and
   URL components, so anything else (a `/`, shell metachars, …) is rejected to
   prevent path traversal and injection from a crafted `.march-version` or arg. *)
let valid_tag s =
  s <> "" && s <> "." && s <> ".." && String.length s <= 128
  && String.for_all (fun c ->
       (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
       || (c >= '0' && c <= '9') || c = '-' || c = '.' || c = '_') s

(* Read a `.march-version` file: its first non-empty trimmed line, or None. A
   malformed/unsafe pin is ignored (with a warning) rather than trusted. *)
let read_version_file path =
  if Sys.file_exists path then
    match In_channel.with_open_text path In_channel.input_line with
    | Some line ->
      let v = String.trim line in
      if v = "" then None
      else if valid_tag v then Some v
      else (Printf.eprintf "warning: ignoring invalid version %S in %s\n%!" v path; None)
    | None | exception _ -> None
  else None

(* The per-project pin: the first `.march-version` found walking up from [dir]
   to the filesystem root. Returns the pinned version tag, or None. *)
let find_pin dir =
  let rec up d =
    match read_version_file (Filename.concat d ".march-version") with
    | Some _ as found -> found
    | None ->
      let parent = Filename.dirname d in
      if parent = d then None else up parent
  in
  up dir

(* The global default toolchain: the basename of the `current` symlink target. *)
let global_version () =
  match Unix.readlink (current_link ()) with
  | target -> Some (Filename.basename target)
  | exception _ -> None

(* Version Resolution Order (see forge_version_manager.md): a project
   `.march-version` pin (walking up from [cwd]) wins over the global default;
   if neither is set, None — callers fall back to `march` on PATH. *)
let resolve_version ?(cwd = Sys.getcwd ()) () =
  match find_pin cwd with
  | Some _ as v -> v
  | None -> global_version ()

(* Resolve the `march` executable to invoke for a build in [cwd]:
   - a resolved version that is installed  -> its versions/<tag>/bin/march
   - a resolved version that is NOT installed -> Error (actionable message)
   - nothing resolved (no pin, no global)  -> Ok "march" (use PATH) *)
let march_command ?(cwd = Sys.getcwd ()) () =
  match resolve_version ~cwd () with
  | None -> Ok "march"
  | Some tag ->
    let bin = Filename.concat (version_dir tag) "bin/march" in
    if Sys.file_exists bin then Ok bin
    else Error (Printf.sprintf
      "march %s is not installed. Run: forge toolchain install %s" tag tag)

(* Check that the resolved toolchain [resolved] satisfies the forge.toml `march`
   constraint [req] (same syntax as dependency constraints). A non-semver tag
   (e.g. a nightly tag like nightly-YYYYMMDD) can't be evaluated, so it is
   allowed through; a malformed constraint is a config error. *)
let check_constraint ~resolved ~req =
  match Resolver_constraint.parse req with
  | Error e -> Error (Printf.sprintf "invalid `march` constraint %S in forge.toml: %s" req e)
  | Ok c ->
    match Resolver_version.parse resolved with
    | Error _ -> Ok ()   (* not semver (e.g. a nightly tag) — cannot evaluate *)
    | Ok v ->
      if Resolver_constraint.satisfies v c then Ok ()
      else Error (Printf.sprintf
        "the active March toolchain %s does not satisfy `march = %S` in forge.toml. \
         Switch to a compatible version (forge toolchain install/use), or update the constraint."
        resolved req)

(* Drift between the toolchain recorded in forge.lock and the one actually
   resolved for this build. Option B: record + warn, never override — so this
   only produces a non-fatal warning, and only when both are known and differ. *)
let toolchain_drift ~locked ~resolved =
  match locked, resolved with
  | Some l, Some r when l <> r ->
    Some (Printf.sprintf
      "warning: building with March %s, but forge.lock records %s; \
       run `forge deps` to update the lock"
      r l)
  | _ -> None

(* A shell prefix that puts the resolved toolchain's bin/ first on PATH, so a
   bare `march` in a forge subprocess uses the pinned/global version. Empty when
   nothing is resolved (PATH fallback). Error when a pin is not installed. *)
let path_prefix ?(cwd = Sys.getcwd ()) () =
  match march_command ~cwd () with
  | Error _ as e -> e
  | Ok exe when Filename.is_relative exe -> Ok ""   (* bare "march" — use PATH *)
  | Ok exe -> Ok (Printf.sprintf "PATH=%s:$PATH " (Filename.quote (Filename.dirname exe)))

(* ----------------------------------------------------------- helpers ---- *)

let read_all ic =
  let buf = Buffer.create 4096 in
  let chunk = Bytes.create 65536 in
  let rec loop () =
    let n = input ic chunk 0 (Bytes.length chunk) in
    if n > 0 then (Buffer.add_subbytes buf chunk 0 n; loop ())
  in
  loop ();
  Buffer.contents buf

(* Run a command, capturing stdout. Returns [Error] on non-zero exit. *)
let capture cmd =
  let ic = Unix.open_process_in cmd in
  let out = read_all ic in
  match Unix.close_process_in ic with
  | Unix.WEXITED 0 -> Ok out
  | _ -> Error (Printf.sprintf "command failed: %s" cmd)

let run cmd =
  if Sys.command cmd = 0 then Ok () else Error (Printf.sprintf "command failed: %s" cmd)

(* GET a URL with curl, forwarding GITHUB_TOKEN if present (API rate limit). *)
let curl_get url =
  let auth =
    match Sys.getenv_opt "GITHUB_TOKEN" with
    | Some t when t <> "" -> Printf.sprintf "-H %s " (Filename.quote ("Authorization: Bearer " ^ t))
    | _ -> ""
  in
  capture (Printf.sprintf "curl -fsSL %s%s" auth (Filename.quote url))

(* Pure platform mapping (unit-tested). *)
let platform_of_uname os arch =
  match String.trim os, String.trim arch with
  | "Darwin", "arm64"               -> Ok "darwin-arm64"
  | "Linux",  "x86_64"              -> Ok "linux-x86_64"
  | "Linux",  ("aarch64" | "arm64") -> Ok "linux-aarch64"
  | "Darwin", "x86_64" ->
    Error "no prebuilt for Intel macOS (darwin-x86_64); build from source"
  | o, a -> Error (Printf.sprintf "unsupported platform: %s-%s" o a)

let detect_platform () =
  match capture "uname -s", capture "uname -m" with
  | Ok os, Ok arch -> platform_of_uname os arch
  | _ -> Error "could not detect platform (uname failed)"

(* ----------------------------------------------------------- API -------- *)

let api_releases_json () =
  Result.bind (curl_get (Printf.sprintf "https://api.github.com/repos/%s/releases" repo))
    (fun s -> try Ok (Yojson.Safe.from_string s)
      with _ -> Error "could not parse GitHub releases response")

let tag_of release =
  match release with
  | `Assoc fields ->
    (match List.assoc_opt "tag_name" fields with
     | Some (`String t) -> Some t
     | _ -> None)
  | _ -> None

let is_nightly tag = String.length tag >= 8 && String.sub tag 0 8 = "nightly-"

(* Group remote release tags into (stable, nightly), preserving the input order
   (the API returns newest-first), each paired with whether it is installed. *)
let classify_remote ~remote ~installed =
  let mark t = (t, List.mem t installed) in
  let stable, nightly = List.partition (fun t -> not (is_nightly t)) remote in
  (List.map mark stable, List.map mark nightly)

(* Pick the default install tag from the release list (newest-first): the
   newest stable (non-nightly), else the newest nightly. Consistent with
   [classify_remote]'s stable/nightly split. *)
let default_tag tags =
  match List.find_opt (fun t -> not (is_nightly t)) tags with
  | Some _ as s -> s
  | None -> List.find_opt is_nightly tags

(* Resolve a version spec to a concrete release tag. *)
let resolve_tag spec =
  match spec with
  | None ->
    Result.bind (api_releases_json ()) (fun json ->
      let tags = match json with `List l -> List.filter_map tag_of l | _ -> [] in
      match default_tag tags with Some t -> Ok t | None -> Error "no releases found")
  | Some "nightly" ->
    Result.bind (api_releases_json ()) (fun json ->
      let tags = match json with `List l -> List.filter_map tag_of l | _ -> [] in
      match List.find_opt is_nightly tags with Some t -> Ok t | None -> Error "no nightly releases found")
  | Some tag ->
    if valid_tag tag then Ok tag
    else Error (Printf.sprintf "invalid version %S" tag)

(* Find the (tarball_url, checksums_url) assets for [platform] in [tag]. *)
let asset_urls ~tag ~platform =
  Result.bind
    (curl_get (Printf.sprintf "https://api.github.com/repos/%s/releases/tags/%s" repo tag))
    (fun s ->
       match (try Some (Yojson.Safe.from_string s) with _ -> None) with
       | None -> Error "could not parse release metadata"
       | Some json ->
         let urls =
           match json with
           | `Assoc fields ->
             (match List.assoc_opt "assets" fields with
              | Some (`List assets) ->
                List.filter_map (function
                  | `Assoc a ->
                    (match List.assoc_opt "browser_download_url" a with
                     | Some (`String u) -> Some u | _ -> None)
                  | _ -> None) assets
              | _ -> [])
           | _ -> []
         in
         let suffix = Printf.sprintf "-%s.tar.gz" platform in
         let ends_with s suf =
           let ls = String.length s and lf = String.length suf in
           ls >= lf && String.sub s (ls - lf) lf = suf
         in
         let tarball = List.find_opt (fun u -> ends_with u suffix) urls in
         let sums    = List.find_opt (fun u -> ends_with u "checksums.txt") urls in
         match tarball with
         | None -> Error (Printf.sprintf "release %s has no asset for %s" tag platform)
         | Some t -> Ok (t, sums))

(* ----------------------------------------------------------- verify ----- *)

(* Pure: find the expected hash for [file] in a checksums document. Each line is
   "<hash>  <file>" or legacy "sha256:<hash>  <file>". Returns lowercase hex. *)
let expected_hash_for ~sums ~file =
  List.find_map (fun line ->
    match String.split_on_char ' ' (String.trim line) |> List.filter (fun s -> s <> "") with
    | hash :: f :: _ when Filename.basename f = file ->
      let hash = match String.index_opt hash ':' with
        | Some i -> String.sub hash (i + 1) (String.length hash - i - 1)
        | None -> hash
      in Some (String.lowercase_ascii hash)
    | _ -> None)
    (String.split_on_char '\n' sums)

(* Fail closed: a download with no checksums asset, no matching entry, or a
   mismatch is rejected — never silently accepted. *)
let verify_checksum ~tarball ~sums_url =
  match sums_url with
  | None -> Error "release has no checksums asset; refusing to install an unverified download"
  | Some url ->
    Result.bind (curl_get url) (fun sums ->
      let want_name = Filename.basename tarball in
      let actual =
        Digestif.SHA256.to_hex (Digestif.SHA256.digest_string (Project.read_file tarball))
      in
      match expected_hash_for ~sums ~file:want_name with
      | None -> Error (Printf.sprintf "%s is not listed in the checksums file; refusing unverified install" want_name)
      | Some want when String.lowercase_ascii actual = want -> Ok ()
      | Some _ -> Error (Printf.sprintf "checksum mismatch for %s" want_name))

(* ----------------------------------------------------------- wrappers --- *)

let write_wrappers () =
  Project.mkdir_p (bin_dir ());
  let home = march_home () in
  List.iter (fun tool ->
    let path = Filename.concat (bin_dir ()) tool in
    let oc = open_out path in
    Fun.protect ~finally:(fun () -> close_out oc) (fun () ->
      Printf.fprintf oc "#!/bin/sh\nexec \"%s/current/bin/%s\" \"$@\"\n" home tool);
    Unix.chmod path 0o755)
    ["march"; "forge"]

(* Point ~/.march/current at versions/<tag> (relative, like install.sh).
   Atomic: create a temp symlink and rename it over current, so a concurrent
   march invocation never observes a missing current. *)
let set_current tag =
  let link = current_link () in
  let tmp = link ^ ".tmp" in
  (try Unix.unlink tmp with Unix.Unix_error _ -> ());
  Unix.symlink (Filename.concat "versions" tag) tmp;
  Unix.rename tmp link

(* ----------------------------------------------------------- commands --- *)

(* The active global toolchain (alias of [global_version], kept for clarity
   at the command call sites). *)
let active_tag = global_version

let installed_tags () =
  match Sys.readdir (versions_dir ()) with
  | entries ->
    Array.to_list entries
    |> List.filter (fun e -> Sys.is_directory (Filename.concat (versions_dir ()) e))
    |> List.sort compare
  | exception _ -> []

let list () =
  let active = active_tag () in
  (match installed_tags () with
   | [] -> Printf.printf "No toolchains installed. Try: forge toolchain install\n"
   | tags ->
     List.iter (fun t ->
       let marker = if Some t = active then " (active)" else "" in
       Printf.printf "  %s%s\n" t marker) tags);
  Ok ()

(* List versions available to install from GitHub releases, grouped by
   stability, marking the ones already installed. *)
let list_remote () =
  match api_releases_json () with
  | Error e -> Error e
  | Ok json ->
    let remote = match json with `List l -> List.filter_map tag_of l | _ -> [] in
    let stable, nightly = classify_remote ~remote ~installed:(installed_tags ()) in
    let print_group title items =
      if items <> [] then begin
        Printf.printf "%s\n" title;
        List.iter (fun (t, inst) ->
          if inst then Printf.printf "  \xe2\x9c\x93 %s (installed)\n" t
          else Printf.printf "    %s\n" t) items
      end
    in
    if stable = [] && nightly = [] then Printf.printf "No releases found.\n"
    else begin
      print_group "Stable releases:" stable;
      if stable <> [] && nightly <> [] then print_newline ();
      print_group "Nightly builds:" nightly
    end;
    Ok ()

let use version =
  if not (valid_tag version) then Error (Printf.sprintf "invalid version %S" version) else
  let dir = version_dir version in
  if not (Sys.file_exists dir) then
    Error (Printf.sprintf "toolchain %s is not installed (forge toolchain install %s)" version version)
  else begin
    set_current version;
    write_wrappers ();
    Printf.printf "Now using March %s\n" version;
    Ok ()
  end

let uninstall version =
  if not (valid_tag version) then Error (Printf.sprintf "invalid version %S" version) else
  let dir = version_dir version in
  if not (Sys.file_exists dir) then
    Error (Printf.sprintf "toolchain %s is not installed" version)
  else if active_tag () = Some version then
    Error (Printf.sprintf "%s is the active toolchain; switch with `forge toolchain use` first" version)
  else
    Result.map (fun () -> Printf.printf "Removed March %s\n" version)
      (run (Printf.sprintf "rm -rf %s" (Filename.quote dir)))

(* Write a `.march-version` pin in the current directory. *)
let pin version =
  if not (valid_tag version) then Error (Printf.sprintf "invalid version %S" version) else
  let path = Filename.concat (Sys.getcwd ()) ".march-version" in
  let oc = open_out path in
  Fun.protect ~finally:(fun () -> close_out oc)
    (fun () -> output_string oc (version ^ "\n"));
  Printf.printf "Pinned March %s for this project (%s)\n" version path;
  if not (Sys.file_exists (Filename.concat (version_dir version) "bin/march")) then
    Printf.printf "note: %s is not installed yet. Run: forge toolchain install %s\n" version version;
  Ok ()

(* Show which toolchain a build here would use, and where it resolves from. *)
let which () =
  let cwd = Sys.getcwd () in
  (match find_pin cwd with
   | Some v -> Printf.printf "%s (pinned via .march-version)\n" v
   | None ->
     match global_version () with
     | Some v -> Printf.printf "%s (global default)\n" v
     | None   -> Printf.printf "none — no pin or active toolchain; `march` resolves via PATH\n");
  (match march_command ~cwd () with
   | Ok exe when not (Filename.is_relative exe) -> Printf.printf "  %s\n" exe
   | Ok _ -> ()
   | Error e -> Printf.printf "  %s\n" e);
  Ok ()

let install spec =
  let ( let* ) = Result.bind in
  let* platform = detect_platform () in
  Printf.eprintf "Platform: %s\n%!" platform;
  let* tag = resolve_tag spec in
  Printf.eprintf "Release: %s\n%!" tag;
  let* (tarball_url, sums_url) = asset_urls ~tag ~platform in
  (* Work in a race-free temp dir UNDER ~/.march so the final move into
     versions/<tag> is a same-filesystem rename, not a cross-fs copy that could
     fail partway and leave the destination destroyed. *)
  let* () = run (Printf.sprintf "mkdir -p %s" (Filename.quote (versions_dir ()))) in
  let* tmp = Result.map String.trim
      (capture (Printf.sprintf "mktemp -d %s"
                  (Filename.quote (Filename.concat (versions_dir ()) "forge-toolchain-XXXXXX")))) in
  Fun.protect ~finally:(fun () -> ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmp))))
    (fun () ->
       let tarball = Filename.concat tmp (Filename.basename tarball_url) in
       Printf.eprintf "Downloading %s ...\n%!" (Filename.basename tarball_url);
       let* () = run (Printf.sprintf "curl -fsSL -o %s %s"
                        (Filename.quote tarball) (Filename.quote tarball_url)) in
       Printf.eprintf "Verifying checksum ...\n%!";
       let* () = verify_checksum ~tarball ~sums_url in
       (* Extract; the archive holds a single march-<ver>-<platform>/ dir. *)
       let* () = run (Printf.sprintf "tar xzf %s -C %s"
                        (Filename.quote tarball) (Filename.quote tmp)) in
       let inner =
         Sys.readdir tmp |> Array.to_list
         |> List.filter (fun e ->
             let p = Filename.concat tmp e in
             Sys.is_directory p && String.length e >= 6 && String.sub e 0 6 = "march-")
         |> function x :: _ -> Some (Filename.concat tmp x) | [] -> None
       in
       match inner with
       | None -> Error "unexpected archive layout"
       | Some inner ->
         let dest = version_dir tag in
         Printf.eprintf "Installing to %s ...\n%!" dest;
         let* () = run (Printf.sprintf "rm -rf %s && mkdir -p %s"
                          (Filename.quote dest) (Filename.quote (versions_dir ()))) in
         let* () = run (Printf.sprintf "mv %s %s"
                          (Filename.quote inner) (Filename.quote dest)) in
         (* Activate on the first install; otherwise leave the active toolchain
            alone (rustup-style) so installing a version is non-disruptive. *)
         write_wrappers ();
         (match active_tag () with
          | None        -> set_current tag; Printf.printf "March %s installed and set as active.\n" tag
          | Some cur when cur = tag -> set_current tag; Printf.printf "March %s reinstalled (active).\n" tag
          | Some _      -> Printf.printf "March %s installed. Activate it with: forge toolchain use %s\n" tag tag);
         (* PATH hint if ~/.march/bin isn't on PATH. *)
         let bd = bin_dir () in
         let on_path =
           match Sys.getenv_opt "PATH" with
           | Some p -> List.mem bd (String.split_on_char ':' p)
           | None -> false
         in
         if not on_path then
           Printf.printf "\nAdd March to your PATH:\n\n    export PATH=\"%s:$PATH\"\n" bd;
         Ok ())

(* Ensure the toolchain resolved for [cwd] is installed: if a pinned/global
   version is missing, download it (auto-install) rather than failing. No-op
   when the version is already present or nothing resolves (PATH fallback). *)
let ensure_installed ?(cwd = Sys.getcwd ()) () =
  match resolve_version ~cwd () with
  | None -> Ok ()
  | Some tag ->
    if Sys.file_exists (Filename.concat (version_dir tag) "bin/march") then Ok ()
    else begin
      Printf.eprintf "March %s is pinned but not installed; installing...\n%!" tag;
      let r = install (Some tag) in
      flush stdout;   (* surface install messages before the build/run output *)
      r
    end

(* `forge upgrade` — install the latest March (newest stable, else newest
   nightly) and make it the active global toolchain. *)
let upgrade () =
  match resolve_tag None with
  | Error e -> Error e
  | Ok tag ->
    if global_version () = Some tag then
      (Printf.printf "Already on the latest March (%s)\n" tag; Ok ())
    else begin
      Printf.eprintf "Upgrading to March %s...\n%!" tag;
      let installed =
        if Sys.file_exists (Filename.concat (version_dir tag) "bin/march")
        then Ok () else install (Some tag)
      in
      Result.bind installed (fun () -> use tag)
    end
