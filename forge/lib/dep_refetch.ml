(** Replacing a cached dependency tree that failed its integrity check.

    Online builds re-hash every cached git/registry tree they are about to use
    against forge.lock's [hash] ([Cmd_build.deps_preflight]). On a mismatch the
    network is available, so instead of failing the build forge fetches the
    locked version again, checks the fresh copy against the same hash, and
    only then swaps it in. If the fresh copy ALSO mismatches, the cache was
    not the problem: forge.lock or the upstream source changed, and the user
    has to decide which to trust, so that is an error naming both hashes.

    Offline mode never gets here: a mismatch there stays an error
    ([Offline_deps.mismatch_error]). Every fetch below goes through
    [Net_gate], so an offline caller would be refused anyway.

    The registry tarball download also lives here, shared with
    `forge deps` ([Cmd_deps] cannot be called from [Cmd_build], which it
    depends on). *)

module LF = Resolver_lockfile
module RQ = Registry_query

let download_url ~base name version =
  Printf.sprintf "%s/api/v1/packages/%s/releases/%s/download"
    (RQ.no_trailing_slash base) name version

(** A verified copy of [name] [vstr]'s tarball in [Tarball_cache], downloading
    it only when the cache has no intact copy. The download goes to a temp
    file, is checked against the registry's published [expected_cs], and only
    then enters the cache (atomically), so the cache never holds bytes that
    failed verification. *)
let cached_or_download ~binary ~base ~name ~vstr ~expected_cs =
  let label = name ^ " " ^ vstr in
  let cached =
    match Tarball_cache.lookup expected_cs with
    | Tarball_cache.Hit p -> Some p
    | Tarball_cache.Miss -> None
    | Tarball_cache.Corrupt { path; actual } ->
      prerr_endline (Tarball_cache.corrupt_warning ~label ~path
                       ~expected:expected_cs ~actual);
      None
  in
  match cached with
  | Some p ->
    Printf.printf "  %s: using cached tarball\n%!" label;
    Ok p
  | None ->
    let tmp = Filename.temp_file ("forge_" ^ name ^ "_") ".tar.gz" in
    Fun.protect ~finally:(fun () -> try Sys.remove tmp with Sys_error _ -> ())
      (fun () ->
         Printf.printf "  %s: downloading...\n%!" label;
         match RQ.fetch ~binary ~url:(download_url ~base name vstr) ~out:tmp with
         | Error e -> Error (Printf.sprintf "%s: %s" label e)
         | Ok () ->
           let actual_cs = Tarball_cache.sha256_file tmp in
           let expected_hex =
             Option.value ~default:expected_cs (Tarball_cache.hex_of_checksum expected_cs) in
           if actual_cs <> expected_hex then
             Error (Printf.sprintf
                      "%s: checksum mismatch\n  expected: %s\n  got:      %s"
                      label expected_cs actual_cs)
           else
             Result.map_error (fun e -> label ^ ": " ^ e)
               (Tarball_cache.store ~checksum:expected_cs ~src:tmp))

let remedy name =
  Printf.sprintf
    "The cached copy of `%s` failed its integrity check and cannot be \
     re-fetched offline. Run the command again with network access."
    name

(** Fetch a git dep at exactly [commit] into [staging]. A full clone, because
    `--depth 1` cannot name an arbitrary commit. *)
let fetch_git ~name ~url ~commit ~staging =
  let cmd =
    Printf.sprintf "git clone -q %s %s && git -C %s checkout -q %s"
      (Filename.quote url) (Filename.quote staging)
      (Filename.quote staging) (Filename.quote commit)
  in
  match
    Net_gate.command
      ~what:(Printf.sprintf "re-fetch dependency `%s` from %s @ %s" name url commit)
      ~remedy:(remedy name) cmd
  with
  | Error e -> Error e
  | Ok 0 -> Ok ()
  | Ok rc ->
    Error (Printf.sprintf "could not re-fetch %s @ %s (git exit %d)" url commit rc)

(** Extract a registry dep's published tarball into [staging]: from the
    tarball cache when it holds an intact copy (no network), else downloaded
    and verified against the lockfile's [checksum] first. *)
let fetch_registry ~name ~version ~checksum ~staging =
  let tarball =
    match Tarball_cache.lookup checksum with
    | Tarball_cache.Hit p -> Ok p
    | (Tarball_cache.Miss | Tarball_cache.Corrupt _) as l ->
      (match l with
       | Tarball_cache.Corrupt { path; actual } ->
         (* [lookup] has already discarded it; say so, then download. *)
         prerr_endline (Tarball_cache.corrupt_warning
                          ~label:(name ^ " " ^ version) ~path ~expected:checksum ~actual)
       | _ -> ());
      (match RQ.compile_client () with
       | Error e -> Error e
       | Ok binary ->
         Fun.protect ~finally:(fun () -> try Sys.remove binary with Sys_error _ -> ())
           (fun () ->
              cached_or_download ~binary ~base:(RQ.registry_base_url ())
                ~name ~vstr:version ~expected_cs:checksum))
  in
  match tarball with
  | Error e -> Error e
  | Ok tarball ->
    if Offline_deps.extract ~tarball ~dest:staging = 0 then Ok ()
    else Error (Printf.sprintf "%s %s: could not extract tarball %s" name version tarball)

(** Put [staging] at [dest], replacing what is there. Both sit in the same
    directory, so the renames stay on one filesystem; the old tree is moved
    aside first and only deleted once the new one is in place. *)
let swap_in ~staging ~dest =
  let aside =
    Filename.concat (Filename.dirname dest)
      (Printf.sprintf ".%s.corrupt-%d" (Filename.basename dest) (Unix.getpid ())) in
  Offline_deps.rm_rf aside;
  match Sys.rename dest aside with
  | exception Sys_error msg -> Offline_deps.rm_rf staging; Error msg
  | () ->
    match Sys.rename staging dest with
    | exception Sys_error msg ->
      (try Sys.rename aside dest with Sys_error _ -> ());
      Offline_deps.rm_rf staging;
      Error msg
    | () -> Offline_deps.rm_rf aside; Ok ()

(** Re-fetch lockfile entry [e] whose cached tree [dest] hashed to
    [cached_actual] instead of [e.hash], verify the fresh copy, and swap it
    in. [Error] carries a user-facing message naming the dependency and the
    hashes. *)
let refetch ~format (e : LF.entry) ~dest ~cached_actual =
  let name = e.LF.name in
  let label = Offline_deps.entry_label e in
  let staging =
    Filename.concat (Filename.dirname dest)
      (Printf.sprintf ".%s.refetch-%d" (Filename.basename dest) (Unix.getpid ())) in
  Offline_deps.rm_rf staging;
  let fetched =
    let src = e.LF.source in
    if String.length src > 4 && String.sub src 0 4 = "git:" then
      match e.LF.commit with
      | Some commit when commit <> "" ->
        fetch_git ~name ~url:(String.sub src 4 (String.length src - 4)) ~commit ~staging
      | _ -> Error "forge.lock records no commit to re-fetch"
    else if src = "registry:forge" then
      match e.LF.version, e.LF.checksum with
      | Some version, Some checksum ->
        fetch_registry ~name ~version ~checksum ~staging
      | _ -> Error "forge.lock records no version and tarball checksum to re-fetch"
    else Error (Printf.sprintf "cannot re-fetch a dependency from %s" src)
  in
  let fail detail =
    Offline_deps.rm_rf staging;
    Error (Printf.sprintf
             "dependency `%s` (%s) failed its integrity check and could not be \
              re-fetched:\n  \
              cached tree: %s\n  \
              expected (forge.lock): %s\n  \
              actual:                %s\n  \
              %s"
             name label dest e.LF.hash cached_actual detail)
  in
  match fetched with
  | Error detail -> fail detail
  | Ok () ->
    match Offline_deps.verify_tree ~format e staging with
    | Offline_deps.Mismatch { expected; actual = fresh } ->
      Offline_deps.rm_rf staging;
      Error (Printf.sprintf
               "dependency `%s` (%s) does not match forge.lock, and neither \
                does a freshly fetched copy:\n  \
                expected (forge.lock): %s\n  \
                fresh copy:            %s\n  \
                cached tree:           %s (%s)\n  \
                So the cache is not the problem: forge.lock or the upstream \
                source has changed. If the upstream change is expected, run \
                `forge deps` to re-lock it; otherwise find out why before \
                trusting it."
               name label expected fresh cached_actual dest)
    | Offline_deps.Verified | Offline_deps.Unverifiable _ ->
      match swap_in ~staging ~dest with
      | Ok () -> Ok ()
      | Error msg -> fail (Printf.sprintf "replacing the cached tree failed: %s" msg)
