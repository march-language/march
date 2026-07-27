(** Precompiled C-runtime object cache — Stage A of the two-stage native
    compile.

    Why this exists
    ───────────────
    [bin/main.ml]'s native [--compile] path used to hand clang the generated
    [.ll] file AND every [runtime/*.c] file in a single command, so every
    invocation recompiled the whole ~20-file C runtime from source.  Measured
    at ~6.5s per invocation on GitHub Actions hardware, essentially all of it
    clang — and it is paid by all 232 native-compiling rules in [test/dune]
    plus every one of the differential oracle's 1090 generated programs.

    The whole-binary CAS in [cas.ml] does NOT help here: it keys on the March
    source, so two distinct programs (or any fuzzer-generated one) never share
    an entry, even though they link a byte-identical C runtime.

    What this caches
    ────────────────
    The runtime object files themselves, keyed on what actually determines
    their compilation:
      - [Cas.runtime_identity] — content digest of every runtime/*.{c,h}
        (reused verbatim, so editing any runtime source invalidates this the
        same way it already invalidates the whole-binary CAS);
      - [Cas.compiler_identity] — the march executable's own bytes, so a march
        upgrade invalidates the entry even when the runtime C is byte-identical;
      - the C toolchain's own [--version] output — NOT covered by
        [Cas.compiler_identity], which hashes only the march executable's
        bytes.  A runner-image clang bump with an unchanged march binary must
        invalidate these objects, and otherwise would not;
      - the exact compile flag string (opt level, -g, sanitizers, -march,
        and the -D/-I bearing openssl/zlib/blake3 discovery flags).

    A cache entry is a DIRECTORY of [.o] files, and [ensure] returns their
    paths in the same order the [.c] files were given.  Stage B then passes
    those objects positionally exactly where the sources used to sit, so the
    resulting link is object-for-object identical to the old single-command
    build — no static-archive member-selection semantics are introduced.

    Concurrency
    ───────────
    [dune runtest] compiles many rules in parallel, so a cold cache has
    several march processes racing to build the same entry.  Each builds into
    a private temp directory, then publishes each object with its own
    [Unix.rename], which is atomic on POSIX.  Racers write byte-equivalent
    content for a given key, so whoever lands last is equally correct, and a
    reader either sees a complete set (uses it) or does not (falls back).
    Publishing per-file rather than renaming the directory also makes the
    cache self-healing: an entry missing one [.o] — a pruning script, a
    partial cache restore — gets exactly that object rebuilt, where a
    whole-directory rename would fail [ENOTEMPTY] against the incomplete
    directory and silently fall back on every future build forever.  (Note
    that [Cas.store_artifact] does NOT do this — it writes its pointer file
    directly — which is a latent gap there, tolerable today only because
    whole-binary entries are keyed per-source and so rarely contended.) *)

let read_file path =
  try
    let ic  = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
      let len = in_channel_length ic in
      let s   = Bytes.create len in
      really_input ic s 0 len;
      Some (Bytes.to_string s))
  with Sys_error _ -> None

let mkdir_p path =
  let parts = String.split_on_char '/' path in
  let _ = List.fold_left (fun acc part ->
    if part = "" then acc
    else begin
      let p = if acc = "" then "/" ^ part else acc ^ "/" ^ part in
      (try Unix.mkdir p 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
      p
    end) "" parts in
  ()

let rm_rf path =
  ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote path)))

(* Identity of the C toolchain driver ("clang", "zig cc -target ...", ...).
   Memoized per driver string: `cc --version` is a subprocess, and the native
   compile path would otherwise pay it on every invocation. *)
let cc_identity_tbl : (string, string) Hashtbl.t = Hashtbl.create 4

(* [None] when `cc --version` can't be read.  Deliberately NOT degraded to
   hashing the driver string: that would silently drop the toolchain out of
   the key, so a later compiler upgrade would serve stale objects.  Losing
   the cache (falling back to the full recompile) is the safe failure. *)
let cc_identity (cc : string) : string option =
  match Hashtbl.find_opt cc_identity_tbl cc with
  | Some h -> Some h
  | None ->
    let tmp = try Some (Filename.temp_file "march_ccver" ".txt")
              with Sys_error _ -> None in
    (match tmp with
     | None -> None
     | Some tmp ->
       let rc =
         Sys.command (Printf.sprintf "%s --version > %s 2>&1" cc (Filename.quote tmp)) in
       let raw = if rc = 0 then read_file tmp else None in
       (try Sys.remove tmp with Sys_error _ -> ());
       (match raw with
        | None -> None
        | Some raw ->
          let h = Blake3.hash_string raw in
          Hashtbl.replace cc_identity_tbl cc h;
          Some h))

(* Runtime objects depend only on the runtime sources + toolchain + flags —
   nothing project-specific — so they live under $HOME rather than in a
   project's .march/, which also keeps them out of dune's build sandboxes.

   [None] when HOME is unset.  Deliberately NOT falling back to the cwd: that
   drops a .march/ directory wherever march happens to run — into a user's
   project root, or into a dune sandbox / test CWD, where a stray .march/ is
   a known hazard for the readdir in test/native's IR-validity gate. *)
let cache_root () =
  match Sys.getenv_opt "HOME" with
  | Some h when h <> "" -> Some (Filename.concat h ".march/cache/runtime-objs")
  | _ -> None

let obj_name (src : string) =
  Filename.remove_extension (Filename.basename src) ^ ".o"

(** Compile [sources] to objects once per (runtime, toolchain, flags) triple
    and return the object paths in the same order as [sources].

    [cflags] is the full compile-flag string, leading space included, exactly
    as it would have appeared in the monolithic command.  Link-only flags
    (-L/-l) may be present; they are inert under -c (and the caller already
    passes -Wno-unused-command-line-argument), and including them in the key
    is harmless.

    Returns [Error] rather than raising if anything goes wrong, so the caller
    can fall back to the original single-command compile. *)
let ensure_exn ~(cc : string) ~(cflags : string) ~(sources : string list)
  : (string list, string) result =
  if sources = [] then Ok []
  else match cache_root (), cc_identity cc with
  | None, _ -> Error "HOME unset"
  | _, None -> Error (Printf.sprintf "could not read `%s --version`" cc)
  | Some root, Some cc_id ->
    let key =
      Blake3.hash_string
        (String.concat "\x00"
           ([ "march-runtime-objs-v2";
              Cas.runtime_identity ();
              (* The march executable's own identity.  Not strictly required
                 for runtime-source changes any more — [runtime_identity] now
                 digests the very directory the driver compiles (registered via
                 [Cas.set_runtime_dir]) — but a march upgrade can change how
                 these objects are used even with byte-identical runtime C, and
                 the whole-binary CAS folds it in (see Cas.compilation_hash), so
                 match it. *)
              Lazy.force Cas.compiler_identity;
              cc_id;
              cflags ]
            @ List.map Filename.basename sources))
    in
    let dir =
      Filename.concat root
        (String.sub key 0 2 ^ "/" ^ String.sub key 2 (String.length key - 2))
    in
    let objs = List.map (fun s -> Filename.concat dir (obj_name s)) sources in
    let all_present () = List.for_all Sys.file_exists objs in
    if all_present () then Ok objs
    else begin
      mkdir_p dir;
      let tmp =
        Filename.concat (Filename.dirname dir)
          (Printf.sprintf "tmp-%d-%d" (Unix.getpid ())
             (int_of_float (Unix.gettimeofday () *. 1000.)))
      in
      rm_rf tmp;
      mkdir_p tmp;
      (* Only build what's actually missing, so a partially-pruned entry
         repairs itself instead of being rebuilt-then-discarded forever. *)
      let missing =
        List.filter (fun s -> not (Sys.file_exists (Filename.concat dir (obj_name s))))
          sources
      in
      let failure =
        List.fold_left (fun acc src ->
          match acc with
          | Some _ -> acc   (* already failed: stop compiling *)
          | None ->
            let out = Filename.concat tmp (obj_name src) in
            let cmd =
              Printf.sprintf "%s -c%s %s -o %s"
                cc cflags (Filename.quote src) (Filename.quote out) in
            if Sys.command cmd = 0 then None
            else Some cmd
        ) None missing
      in
      match failure with
      | Some cmd ->
        rm_rf tmp;
        Error (Printf.sprintf "object compile failed: %s" cmd)
      | None ->
        (* Publish each object with its own rename, which is atomic on POSIX.
           Per-file (rather than renaming the whole directory into place)
           makes this self-healing: an entry missing one .o gets exactly that
           .o restored, where a directory rename would fail ENOTEMPTY against
           the existing incomplete dir and fall back on every future build.
           Racing processes are writing byte-equivalent content for this key,
           so whoever lands last is equally correct. *)
        List.iter (fun src ->
          let from = Filename.concat tmp (obj_name src) in
          let into = Filename.concat dir (obj_name src) in
          if Sys.file_exists from then
            (try Unix.rename from into with Unix.Unix_error _ -> ())
        ) missing;
        rm_rf tmp;
        if all_present () then Ok objs
        else Error "objects missing after build (cache raced or was pruned)"
    end

(** Wrapper guaranteeing the [Error]-not-raise contract above.  [mkdir_p],
    [Filename.temp_file] and friends raise on EACCES/EROFS/ENOSPC/ENOTDIR
    (e.g. HOME set to an unwritable or non-existent path, as in `docker run
    --read-only`, nix builds, or systemd's ProtectHome), and the caller does
    a bare match on the result — so without this, a compile that previously
    succeeded dies with an internal-compiler-error exit 3 instead of quietly
    falling back to the full recompile. *)
let ensure ~(cc : string) ~(cflags : string) ~(sources : string list)
  : (string list, string) result =
  try ensure_exn ~cc ~cflags ~sources
  with e -> Error (Printexc.to_string e)
