(** cmd_assets.ml — forge assets build / deploy / watch

    Shells out to esbuild to bundle the assets in [assets/] into
    [priv/static/assets/].

    build   — dev bundle: sourcemaps, no minification
    deploy  — prod bundle: minified + content-hash fingerprinting, writes manifest
    watch   — runs esbuild in --watch mode (for use alongside forge bastion server)

    Directory conventions (relative to project root):
      assets/js/app.js         JS entry point (may import CSS)
      assets/css/app.css       CSS entry point
      priv/static/assets/      output directory (gitignored)
      priv/static/assets/manifest.json  digest manifest (deploy only)

    esbuild must be on PATH.  Install with:
      npm install -g esbuild    OR    brew install esbuild
*)

(* ------------------------------------------------------------------ helpers *)

let read_file path =
  let ic = open_in_bin path in
  let n  = in_channel_length ic in
  let buf = Bytes.create n in
  really_input ic buf 0 n;
  close_in ic;
  Bytes.to_string buf

let write_file path content =
  let dir = Filename.dirname path in
  let _   = Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote dir)) in
  let oc  = open_out_bin path in
  output_string oc content;
  close_out oc

(** Collect all regular files immediately inside [dir] (non-recursive). *)
let readdir_files dir =
  try
    Array.to_list (Sys.readdir dir)
    |> List.filter (fun name ->
        let p = Filename.concat dir name in
        Sys.file_exists p && not (Sys.is_directory p))
  with Sys_error _ -> []

(** Locate esbuild in PATH. *)
let find_esbuild () =
  let path_dirs =
    match Sys.getenv_opt "PATH" with
    | None   -> ["/usr/local/bin"; "/usr/bin"; "/bin"]
    | Some p -> String.split_on_char ':' p
  in
  match List.find_opt (fun d ->
      Sys.file_exists (Filename.concat d "esbuild")
    ) path_dirs with
  | Some d -> Ok (Filename.concat d "esbuild")
  | None   ->
    Error ("esbuild not found in PATH.\n" ^
           "Install it with one of:\n" ^
           "  npm install -g esbuild\n" ^
           "  brew install esbuild")

(** 8-hex-char MD5 digest of a string — good enough for cache-busting. *)
let fingerprint content =
  let digest = Digest.string content in
  (* Digest.to_hex returns a 32-char hex string *)
  String.sub (Digest.to_hex digest) 0 8

(* --------------------------------------------------------- esbuild wrappers *)

(** Ensure priv/static/assets/ exists. *)
let ensure_output_dir root =
  let dir = Filename.concat root "priv/static/assets" in
  let _ = Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote dir)) in
  ()

(** Build the esbuild command string from entry points, flags, and outdir. *)
let esbuild_cmd esbuild_exe root extra_flags =
  let js_entry  = Filename.concat root "assets/js/app.js" in
  let css_entry = Filename.concat root "assets/css/app.css" in
  let out_dir   = Filename.concat root "priv/static/assets" in
  (* Only include entry points that exist *)
  let entries =
    List.filter_map (fun p -> if Sys.file_exists p then Some (Filename.quote p) else None)
      [js_entry; css_entry]
  in
  if entries = [] then
    Error "No entry points found. Expected assets/js/app.js or assets/css/app.css"
  else
    let entry_str = String.concat " " entries in
    let cmd = Printf.sprintf "%s %s --bundle --outdir=%s %s"
        (Filename.quote esbuild_exe)
        entry_str
        (Filename.quote out_dir)
        extra_flags
    in
    Ok cmd

(* ------------------------------------------------------------------- digest *)

(** Digest all output files, rename them with a hash suffix, and write
    [priv/static/assets/manifest.json].

    The manifest maps logical names (e.g. ["app.js"]) to digested names
    (e.g. ["app-a1b2c3d4.js"]).  Bastion.Static.path/1 reads this file. *)
let digest_assets root =
  let assets_dir = Filename.concat root "priv/static/assets" in
  let files = readdir_files assets_dir
              |> List.filter (fun f -> f <> "manifest.json")
  in
  let manifest_entries =
    List.filter_map (fun filename ->
        let filepath = Filename.concat assets_dir filename in
        let content  = read_file filepath in
        let hash     = fingerprint content in
        let ext      = Filename.extension filename in
        let stem     = Filename.remove_extension filename in
        let hashed   = Printf.sprintf "%s-%s%s" stem hash ext in
        let hashed_p = Filename.concat assets_dir hashed in
        (try Sys.rename filepath hashed_p
         with Sys_error msg ->
           Printf.eprintf "warning: could not rename %s: %s\n%!" filename msg);
        Some (filename, hashed)
      ) files
  in
  (* Write manifest.json *)
  let manifest_path = Filename.concat assets_dir "manifest.json" in
  let pairs = List.map (fun (k, v) ->
      Printf.sprintf "  %S: %S" k v
    ) manifest_entries in
  let content = "{\n" ^ String.concat ",\n" pairs ^ "\n}\n" in
  write_file manifest_path content;
  Printf.printf "wrote %s (%d %s)\n%!"
    manifest_path
    (List.length manifest_entries)
    (if List.length manifest_entries = 1 then "entry" else "entries");
  List.iter (fun (k, v) ->
      Printf.printf "  %s -> %s\n%!" k v
    ) manifest_entries

(* --------------------------------------------------------------------- run *)

(** [forge assets build] — dev bundle with sourcemaps, no minification. *)
let build () =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    let root = proj.Project.root in
    ensure_output_dir root;
    match find_esbuild () with
    | Error msg -> Error msg
    | Ok esbuild ->
      match esbuild_cmd esbuild root "--sourcemap" with
      | Error msg -> Error msg
      | Ok cmd ->
        Printf.printf "--> forge assets build\n    %s\n%!" cmd;
        let exit_code = Sys.command cmd in
        if exit_code = 0 then begin
          Printf.printf "--> assets built successfully.\n%!";
          Ok ()
        end else
          Error (Printf.sprintf "esbuild exited with code %d" exit_code)

(** [forge assets deploy] — prod bundle: minified + digest fingerprinting. *)
let deploy () =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    let root = proj.Project.root in
    ensure_output_dir root;
    match find_esbuild () with
    | Error msg -> Error msg
    | Ok esbuild ->
      match esbuild_cmd esbuild root "--minify --sourcemap=external" with
      | Error msg -> Error msg
      | Ok cmd ->
        Printf.printf "--> forge assets deploy\n    %s\n%!" cmd;
        let exit_code = Sys.command cmd in
        if exit_code = 0 then begin
          Printf.printf "--> bundling complete, fingerprinting...\n%!";
          digest_assets root;
          Printf.printf "--> assets deployed successfully.\n%!";
          Ok ()
        end else
          Error (Printf.sprintf "esbuild exited with code %d" exit_code)

(** [forge assets watch] — rebuild on file changes (dev mode). *)
let watch () =
  match Project.load () with
  | Error msg -> Error msg
  | Ok proj ->
    let root = proj.Project.root in
    ensure_output_dir root;
    match find_esbuild () with
    | Error msg -> Error msg
    | Ok esbuild ->
      match esbuild_cmd esbuild root "--sourcemap --watch" with
      | Error msg -> Error msg
      | Ok cmd ->
        Printf.printf "--> forge assets watch (press Ctrl+C to stop)\n    %s\n%!" cmd;
        let exit_code = Sys.command cmd in
        if exit_code = 0 then Ok ()
        else Error (Printf.sprintf "esbuild exited with code %d" exit_code)
