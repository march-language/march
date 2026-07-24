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
      - the C toolchain's own [--version] output — deliberately NOT covered by
        [Cas.compiler_identity], which hashes only the march executable's
        bytes.  A runner-image clang bump with an unchanged march binary must
        invalidate these objects, and today would not;
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
    a private temp directory and then [Unix.rename]s it into place, which is
    atomic on POSIX; a loser sees [ENOTEMPTY]/[EEXIST], discards its temp
    copy, and uses the winner's.  (Note that [Cas.store_artifact] does NOT do
    this — it writes its pointer file directly — which is a latent gap there,
    tolerable today only because whole-binary entries are keyed per-source and
    so rarely contended.) *)

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

let cc_identity (cc : string) : string =
  match Hashtbl.find_opt cc_identity_tbl cc with
  | Some h -> h
  | None ->
    let tmp = Filename.temp_file "march_ccver" ".txt" in
    let rc =
      Sys.command (Printf.sprintf "%s --version > %s 2>&1" cc (Filename.quote tmp)) in
    let raw = match (if rc = 0 then read_file tmp else None) with
      | Some s -> s
      (* Unreadable/failed --version: fall back to the driver string itself.
         That still separates clang from zig cc, just not two clang builds —
         acceptable, and the runtime digest below is the load-bearing part. *)
      | None -> cc
    in
    (try Sys.remove tmp with Sys_error _ -> ());
    let h = Blake3.hash_string raw in
    Hashtbl.replace cc_identity_tbl cc h;
    h

(* Runtime objects depend only on the runtime sources + toolchain + flags —
   nothing project-specific — so they live under $HOME rather than in a
   project's .march/, which also keeps them out of dune's build sandboxes.
   Falls back to the cwd when HOME is unset (CI containers, some sandboxes). *)
let cache_root () =
  let base = match Sys.getenv_opt "HOME" with
    | Some h -> h
    | None -> Sys.getcwd ()
  in
  Filename.concat base ".march/cache/runtime-objs"

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
let ensure ~(cc : string) ~(cflags : string) ~(sources : string list)
  : (string list, string) result =
  if sources = [] then Ok []
  else begin
    let key =
      Blake3.hash_string
        (String.concat "\x00"
           ([ "march-runtime-objs-v1";
              Lazy.force Cas.runtime_identity;
              cc_identity cc;
              cflags ]
            @ List.map Filename.basename sources))
    in
    let root = cache_root () in
    let dir =
      Filename.concat root
        (String.sub key 0 2 ^ "/" ^ String.sub key 2 (String.length key - 2))
    in
    let objs = List.map (fun s -> Filename.concat dir (obj_name s)) sources in
    let all_present () = List.for_all Sys.file_exists objs in
    (* The rename below is atomic, so an existing directory is a complete one.
       [all_present] additionally guards against a partially-deleted entry
       (e.g. a hand-pruned cache) rather than trusting the directory alone. *)
    if all_present () then Ok objs
    else begin
      let parent = Filename.dirname dir in
      mkdir_p parent;
      let tmp =
        Filename.concat parent
          (Printf.sprintf "tmp-%d-%d" (Unix.getpid ())
             (int_of_float (Unix.gettimeofday () *. 1000.)))
      in
      rm_rf tmp;
      mkdir_p tmp;
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
        ) None sources
      in
      match failure with
      | Some cmd ->
        rm_rf tmp;
        Error (Printf.sprintf "object compile failed: %s" cmd)
      | None ->
        (* Publish atomically.  A lost race (another process already renamed
           its own build into place) fails with ENOTEMPTY/EEXIST/EACCES —
           that is success as far as we're concerned: the winner's objects
           are byte-equivalent, built from the same key. *)
        (try Unix.rename tmp dir
         with Unix.Unix_error _ -> rm_rf tmp);
        if all_present () then Ok objs
        else Error "objects missing after build (cache raced or was pruned)"
    end
  end
