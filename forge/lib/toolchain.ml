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

let detect_platform () =
  let trim s = String.trim s in
  match capture "uname -s", capture "uname -m" with
  | Ok os, Ok arch ->
    (match trim os, trim arch with
     | "Darwin", "arm64"                  -> Ok "darwin-arm64"
     | "Linux",  "x86_64"                 -> Ok "linux-x86_64"
     | "Linux",  ("aarch64" | "arm64")    -> Ok "linux-aarch64"
     | "Darwin", "x86_64" ->
       Error "no prebuilt for Intel macOS (darwin-x86_64); build from source"
     | o, a -> Error (Printf.sprintf "unsupported platform: %s-%s" o a))
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

(* Resolve a version spec to a concrete release tag. *)
let resolve_tag spec =
  match spec with
  | Some "nightly" | None ->
    Result.bind (api_releases_json ()) (fun json ->
      let tags = match json with `List l -> List.filter_map tag_of l | _ -> [] in
      let stable = List.find_opt (fun t -> String.length t > 0 && t.[0] = 'v') tags in
      match spec, stable with
      | None, Some t -> Ok t                       (* prefer newest stable *)
      | _ ->
        (match List.find_opt (fun t ->
             String.length t >= 8 && String.sub t 0 8 = "nightly-") tags with
         | Some t -> Ok t
         | None -> Error "no releases found"))
  | Some tag -> Ok tag

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

let verify_checksum ~tarball ~sums_url =
  match sums_url with
  | None ->
    Printf.eprintf "warning: no checksums asset; skipping verification\n%!"; Ok ()
  | Some url ->
    Result.bind (curl_get url) (fun sums ->
      let want_name = Filename.basename tarball in
      let actual =
        Digestif.SHA256.to_hex (Digestif.SHA256.digest_string (Project.read_file tarball))
      in
      (* Each line is "<hash>  <file>" or legacy "sha256:<hash>  <file>". *)
      let expected =
        List.find_map (fun line ->
          match String.split_on_char ' ' (String.trim line) |> List.filter (fun s -> s <> "") with
          | hash :: file :: _ when Filename.basename file = want_name ->
            let hash = match String.index_opt hash ':' with
              | Some i -> String.sub hash (i + 1) (String.length hash - i - 1)
              | None -> hash
            in Some (String.lowercase_ascii hash)
          | _ -> None)
          (String.split_on_char '\n' sums)
      in
      match expected with
      | None -> Printf.eprintf "warning: %s not in checksums; skipping\n%!" want_name; Ok ()
      | Some want when String.lowercase_ascii actual = want -> Ok ()
      | Some _ -> Error (Printf.sprintf "checksum mismatch for %s" want_name))

(* ----------------------------------------------------------- wrappers --- *)

let write_wrappers () =
  Project.mkdir_p (bin_dir ());
  let home = march_home () in
  List.iter (fun tool ->
    let path = Filename.concat (bin_dir ()) tool in
    let oc = open_out path in
    Printf.fprintf oc "#!/bin/sh\nexec \"%s/current/bin/%s\" \"$@\"\n" home tool;
    close_out oc;
    Unix.chmod path 0o755)
    ["march"; "forge"]

(* Point ~/.march/current at versions/<tag> (relative, like install.sh). *)
let set_current tag =
  let link = current_link () in
  (try Unix.unlink link with Unix.Unix_error _ -> ());
  Unix.symlink (Filename.concat "versions" tag) link

(* ----------------------------------------------------------- commands --- *)

let active_tag () =
  match Unix.readlink (current_link ()) with
  | target -> Some (Filename.basename target)
  | exception _ -> None

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

let use version =
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
  let dir = version_dir version in
  if not (Sys.file_exists dir) then
    Error (Printf.sprintf "toolchain %s is not installed" version)
  else if active_tag () = Some version then
    Error (Printf.sprintf "%s is the active toolchain; switch with `forge toolchain use` first" version)
  else
    Result.map (fun () -> Printf.printf "Removed March %s\n" version)
      (run (Printf.sprintf "rm -rf %s" (Filename.quote dir)))

let install spec =
  let ( let* ) = Result.bind in
  let* platform = detect_platform () in
  Printf.eprintf "Platform: %s\n%!" platform;
  let* tag = resolve_tag spec in
  Printf.eprintf "Release: %s\n%!" tag;
  let* (tarball_url, sums_url) = asset_urls ~tag ~platform in
  (* Work in a temp dir, then move into place. *)
  let tmp = Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "forge-toolchain-%d" (Unix.getpid ())) in
  let* () = run (Printf.sprintf "rm -rf %s && mkdir -p %s"
                   (Filename.quote tmp) (Filename.quote tmp)) in
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
         let* () = use tag in
         Printf.printf "March %s installed.\n" tag;
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
