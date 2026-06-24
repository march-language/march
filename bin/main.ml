(** March compiler entry point. *)

(* Decode URL-safe base64 (with or without padding) to bytes.
 * Returns Some bytes_string on success, None on invalid input. *)
let b64_decode_pubkey b64 =
  let tbl = Array.make 256 (-1) in
  let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=" in
  String.iteri (fun i c -> tbl.(Char.code c) <- i) chars;
  let s = String.map (function '-' -> '+' | '_' -> '/' | c -> c) b64 in
  let s = match String.length s mod 4 with
    | 2 -> s ^ "=="
    | 3 -> s ^ "="
    | _ -> s in
  let n = String.length s in
  if n = 0 || n mod 4 <> 0 then None
  else begin
    let buf = Buffer.create (n / 4 * 3) in
    let ok = ref true in
    let i = ref 0 in
    while !i < n && !ok do
      let v0 = tbl.(Char.code s.[!i]) in
      let v1 = tbl.(Char.code s.[!i+1]) in
      let v2 = tbl.(Char.code s.[!i+2]) in
      let v3 = tbl.(Char.code s.[!i+3]) in
      if v0 < 0 || v1 < 0 || v2 < 0 || v3 < 0 then ok := false
      else begin
        Buffer.add_char buf (Char.chr ((v0 lsl 2) lor (v1 lsr 4)));
        if s.[!i+2] <> '=' then
          Buffer.add_char buf (Char.chr (((v1 land 0xf) lsl 4) lor (v2 lsr 2)));
        if s.[!i+3] <> '=' then
          Buffer.add_char buf (Char.chr (((v2 land 0x3) lsl 6) lor v3))
      end;
      i := !i + 4
    done;
    if not !ok then None
    else begin
      let bytes = Buffer.contents buf in
      if String.length bytes <> 32 then None
      else begin
        let hex = String.concat "" (List.init 32 (fun j ->
          Printf.sprintf "%02x" (Char.code bytes.[j]))) in
        Some hex
      end
    end
  end

(* ------------------------------------------------------------------ *)
(* Stdlib loader                                                       *)
(* ------------------------------------------------------------------ *)

(** Resolve an executable name to an absolute path.
    If the name already contains a slash it is used as-is (after resolving
    relative to CWD).  Otherwise PATH is searched.  Falls back to the raw
    name if nothing is found. *)
let resolve_exe_path name =
  if String.contains name '/' then
    (* relative or absolute path — resolve against CWD *)
    if String.length name > 0 && name.[0] = '/' then name
    else Filename.concat (Sys.getcwd ()) name
  else begin
    let path_dirs =
      match Sys.getenv_opt "PATH" with
      | None   -> ["/usr/local/bin"; "/usr/bin"; "/bin"]
      | Some p -> String.split_on_char ':' p
    in
    match List.find_opt (fun d ->
        let p = Filename.concat d name in
        Sys.file_exists p && not (Sys.is_directory p)
      ) path_dirs with
    | Some d -> Filename.concat d name
    | None   -> name
  end

(** Locate the stdlib directory.
    Resolution order:
    1. MARCH_STDLIB environment variable (explicit override)
    2. Paths relative to the resolved march executable:
       - bin/../stdlib          (source-tree / opam switch layout)
       - bin/../../stdlib       (nested build layout)
       - bin/../share/march/stdlib  (installed share layout)
    3. "stdlib" relative to CWD (works when running from the March repo root) *)
let find_stdlib_dir () =
  match Sys.getenv_opt "MARCH_STDLIB" with
  | Some p when Sys.file_exists p -> Some p
  | _ ->
    let exe_path = resolve_exe_path Sys.executable_name in
    let exe_dir  = Filename.dirname exe_path in
    let candidates = [
      (* Exe-relative candidates — work regardless of CWD *)
      Filename.concat exe_dir "../stdlib";
      Filename.concat exe_dir "../../stdlib";
      (* Installed share layout: bin/../share/march/stdlib or bin/../share/march *)
      Filename.concat exe_dir "../share/march/stdlib";
      Filename.concat exe_dir "../share/march";
      (* CWD-relative fallback — works when invoked from the March repo root *)
      "stdlib";
    ] in
    List.find_opt Sys.file_exists candidates

(** Parse a stdlib source file and return its top-level declarations.
    Each stdlib file is a single [mod Name do ... end] wrapper.
    - For "prelude.march": the inner declarations are returned directly,
      so they land in the user module's top-level scope.
    - For all other files: the whole [DMod] is returned, so the module
      is accessible as e.g. [Option.is_some]. *)
let load_stdlib_file path =
  let src =
    try
      let ic = open_in path in
      let n = in_channel_length ic in
      let buf = Bytes.create n in
      really_input ic buf 0 n;
      close_in ic;
      Bytes.to_string buf
    with Sys_error _ -> ""
  in
  if src = "" then []
  else
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
    (try
       let m = March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
       let m = March_desugar.Desugar.desugar_module m in
       let basename = Filename.basename path in
       if basename = "prelude.march" then
         (* Unwrap the outer mod so prelude functions are in global scope *)
         (match m.March_ast.Ast.mod_decls with
          | [March_ast.Ast.DMod (_, _, inner_decls, _)] -> inner_decls
          | decls -> decls)
       else
         (* Wrap in a DMod so names are accessible as Module.name *)
         [March_ast.Ast.DMod (m.March_ast.Ast.mod_name,
                              March_ast.Ast.Public,
                              m.March_ast.Ast.mod_decls,
                              March_ast.Ast.dummy_span)]
     with
     | March_parser.Parser.Error ->
       let pos = Lexing.lexeme_start_p lexbuf in
       Printf.eprintf "[stdlib] parse error in %s at line %d col %d\n%!"
         path pos.Lexing.pos_lnum (pos.Lexing.pos_cnum - pos.Lexing.pos_bol);
       []
     | exn ->
       Printf.eprintf "[stdlib] error in %s: %s\n%!" path (Printexc.to_string exn); [])

(** The ordered list of stdlib file names. *)
let stdlib_file_list = [
  "prelude.march";
  "option.march";
  "result.march";
  "list.march";
  "hamt.march";
  "map.march";
  "math.march";
  "string.march";
  "iolist.march";
  "html.march";
  "sigil.march";
  "http.march";
  "http_transport.march";
  "http_client.march";
  "seq.march";
  "path.march";
  "file.march";
  "dir.march";
  "sort.march";
  "csv.march";
  "websocket.march";
  "http_server.march";
  "iterable.march";
  "set.march";
  "array.march";
  "bigint.march";
  "decimal.march";
  "duration.march";
  "bytes.march";
  "msgpack.march";
  "toml.march";
  "xml.march";
  "yaml.march";
  "socket.march";
  "dns.march";
  "process.march";
  "io.march";
  "system.march";
  "cluster.march";
  "cluster_load.march";
  "logger.march";
  "actor.march";
  "flow.march";
  "json.march";
  "regex.march";
  "datetime.march";
  "queue.march";
  "enum.march";
  "random.march";
  "gen.march";
  "check.march";
  "stats.march";
  "plot.march";
  "dataframe.march";
  "tls.march";
  "uuid.march";
  "vault.march";
  "channel.march";
  "pubsub.march";
  "channel_server.march";
  "channel_socket.march";
  "presence.march";
  "env.march";
  "config.march";
  "test.march";
  "tuple.march";
  "char.march";
  "ordered_map.march";
  "sorted_set.march";
  "range.march";
  "crypto.march";
  "base64.march";
  "native_array.march";
  "task.march";
  "uri.march";
  "forge_nb.march";
  "handle.march";
  (* Distributed OTP — added after all other stdlib deps are loaded *)
  "net_frame.march";
  "cluster_auth.march";
  "node_identity.march";
  "handshake.march";
  "global_pid.march";
  "remote_call.march";
  "node_rpc.march";
  "peer_registry.march";
  "net_kernel.march";
  "membership.march";
  "swim.march";
  "swim_driver.march";
  "global_registry.march";
  "cluster_conn.march";
  "node_call.march";
]

(** Stdlib modules only loaded for --target js builds.
    These have externs with no native C symbols, so including them in native/JIT
    builds would cause dlopen(RTLD_NOW) to fail at link time. *)
let js_only_stdlib_file_list = ["dom.march"]

(** Read all stdlib source files and compute a hash of their contents.
    Returns (stdlib_dir, source_hash, file_paths). *)
let stdlib_source_hash ?(for_js=false) () =
  match find_stdlib_dir () with
  | None -> None
  | Some stdlib_dir ->
    let file_list =
      if for_js then stdlib_file_list @ js_only_stdlib_file_list
      else stdlib_file_list
    in
    let paths = List.map (Filename.concat stdlib_dir) file_list in
    let buf = Buffer.create (256 * 1024) in
    List.iter (fun path ->
      try
        let ic = open_in path in
        let n = in_channel_length ic in
        let bytes = Bytes.create n in
        really_input ic bytes 0 n;
        close_in ic;
        Buffer.add_bytes buf bytes
      with Sys_error _ -> ()
    ) paths;
    let hash = Digest.to_hex (Digest.string (Buffer.contents buf)) in
    Some (stdlib_dir, hash, paths)

(** Load all stdlib modules and return their declarations, to be
    prepended to the user module before evaluation.
    Uses a content-hash-keyed cache of parsed+desugared ASTs. *)
let load_stdlib ?(for_js=false) () =
  let file_list =
    if for_js then stdlib_file_list @ js_only_stdlib_file_list
    else stdlib_file_list
  in
  match stdlib_source_hash ~for_js () with
  | None -> []
  | Some (stdlib_dir, source_hash, _) ->
    let home = (try Sys.getenv "HOME" with Not_found -> ".") in
    let cache_dir = Filename.concat home ".cache/march" in
    let short_hash = String.sub source_hash 0 16 in
    let cache_path = Filename.concat cache_dir
      ("stdlib_ast_" ^ short_hash ^ ".bin") in
    (* Cache hit: unmarshal parsed ASTs *)
    match (try
      if Sys.file_exists cache_path then begin
        let ic = open_in_bin cache_path in
        let data : March_ast.Ast.decl list = Marshal.from_channel ic in
        close_in ic;
        Some data
      end else None
    with _ -> None) with
    | Some decls -> decls
    | None ->
      (* Cache miss: parse all files, then cache *)
      let decls = List.concat_map (fun name ->
          load_stdlib_file (Filename.concat stdlib_dir name)
        ) file_list in
      (try
        (try Unix.mkdir cache_dir 0o755
         with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
        (* Write-to-temp + rename: the cache dir is shared across concurrent
           sessions; a reader must never see a half-written Marshal blob. *)
        let tmp = Printf.sprintf "%s.%d.tmp" cache_path (Unix.getpid ()) in
        let oc = open_out_bin tmp in
        Marshal.to_channel oc decls [];
        close_out oc;
        Sys.rename tmp cache_path
      with _ -> ());
      decls

(** Pre-compile the C runtime to a shared library.
    Cached at ~/.cache/march/libmarch_runtime_<hash>.so, where <hash> covers
    every C source/header that goes into the build plus the clang flags.

    The cache directory is SHARED across worktrees and concurrent sessions,
    so the artifact name must be a pure function of its inputs and the write
    must be atomic (compile to a pid-suffixed temp, then rename).  The old
    scheme — one fixed "libmarch_runtime.so" invalidated by the mtime of
    march_runtime.c alone — let two worktrees with diverged runtimes
    ping-pong overwrite each other's binary (ABI mismatch → wrong symbols →
    hangs/crashes in whichever session dlopen'd the other's build), and a
    reader could dlopen a half-written .so mid-compile.
    Returns the path to the .so. *)
let ensure_runtime_so () =
  let home = Sys.getenv "HOME" in
  let dot_cache = Filename.concat home ".cache" in
  let cache_dir = Filename.concat dot_cache "march" in
  (* Create parent directories recursively *)
  List.iter (fun d ->
    try Unix.mkdir d 0o755
    with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  ) [dot_cache; cache_dir];
  (* Find runtime source *)
  let candidates = [
    "runtime/march_runtime.c";
    Filename.concat (Filename.dirname Sys.executable_name) "../runtime/march_runtime.c";
    Filename.concat (Filename.dirname Sys.executable_name) "../../runtime/march_runtime.c";
  ] in
  let runtime_c_opt = List.find_opt Sys.file_exists candidates in
  match runtime_c_opt with
  | None ->
    (* No sources (e.g. installed binary without a source tree): fall back
       to the newest cached runtime .so from a previous run, if any. *)
    let cached =
      (try Sys.readdir cache_dir with Sys_error _ -> [||])
      |> Array.to_list
      |> List.filter (fun f ->
          String.length f > 16
          && String.sub f 0 16 = "libmarch_runtime"
          && Filename.check_suffix f ".so")
      |> List.map (Filename.concat cache_dir)
      |> List.sort (fun a b ->
          compare (Unix.stat b).Unix.st_mtime (Unix.stat a).Unix.st_mtime)
    in
    (match cached with
     | newest :: _ -> newest
     | [] -> failwith "march: cannot find runtime/march_runtime.c")
  | Some runtime_c ->
    let runtime_dir = Filename.dirname runtime_c in
    (* Note: -lpthread not needed on macOS (pthreads are in libSystem). *)
    let http_c     = Filename.concat runtime_dir "march_http.c" in
    let extras_c   = Filename.concat runtime_dir "march_extras.c" in
    let compress_c = Filename.concat runtime_dir "march_compress.c" in
    let opt_file f = if Sys.file_exists f then Printf.sprintf " %s" f else "" in
    let sched_c   = Filename.concat runtime_dir "march_scheduler.c" in
    let ffi_c     = Filename.concat runtime_dir "march_ffi.c" in
    let sha1_c    = Filename.concat runtime_dir "sha1.c" in
    let base64_c  = Filename.concat runtime_dir "base64.c" in
    let extra_files =
      (if Sys.file_exists http_c then
        let simd_c    = Filename.concat runtime_dir "march_http_parse_simd.c" in
        let resp_c    = Filename.concat runtime_dir "march_http_response.c" in
        let io_c      = Filename.concat runtime_dir "march_http_io.c" in
        let evloop_c  = Filename.concat runtime_dir "march_http_evloop.c" in
        let tls_c     = Filename.concat runtime_dir "march_tls.c" in
        Printf.sprintf " %s %s %s%s%s%s%s%s%s%s%s" http_c sha1_c base64_c
          (opt_file simd_c) (opt_file sched_c) (opt_file resp_c)
          (opt_file io_c) (opt_file evloop_c) (opt_file tls_c) (opt_file extras_c)
          (opt_file compress_c)
      else
        (* march_extras.c unconditionally references base64_encode (base64.c) and
           sha1 (sha1.c), so they must be linked whenever march_extras.c is —
           independent of the HTTP stack. Without this, a build tree that has
           march_extras.c but not march_http.c (e.g. a native test rule that
           lists extras as a dep but not http) fails to link with undefined
           _base64_encode / _sha1. opt_file-guarded so absent files are skipped. *)
        Printf.sprintf "%s%s%s%s%s" (opt_file sched_c) (opt_file extras_c)
          (opt_file compress_c) (opt_file base64_c) (opt_file sha1_c))
      ^ (opt_file ffi_c)
      ^ (opt_file (Filename.concat runtime_dir "march_dispatch.c"))  (* HCR dispatch table *)
      ^ (opt_file (Filename.concat runtime_dir "march_reload.c"))    (* HCR reload server *)
      ^ (opt_file (Filename.concat runtime_dir "march_remote_registry.c"))  (* L4 remote registry *)
    in
    (* OpenSSL flags: needed when march_tls.c is included. *)
    let tls_c = Filename.concat runtime_dir "march_tls.c" in
    let openssl_flags =
      if not (Sys.file_exists tls_c) then ""
      else
        let dirs = [
          "/opt/homebrew/opt/openssl@3";
          "/opt/homebrew/opt/openssl";
          "/usr/local/opt/openssl@3";
          "/usr/local/opt/openssl";
          "/usr/include/openssl";
        ] in
        let found = List.fold_left (fun acc d ->
          match acc with
          | Some _ -> acc
          | None ->
            let hdr = Filename.concat d "include/openssl/ssl.h" in
            if Sys.file_exists hdr then Some d else None
        ) None dirs in
        match found with
        | Some d ->
          Printf.sprintf " -I%s/include -L%s/lib -lssl -lcrypto" d d
        | None ->
          (* Try pkg-config *)
          if Sys.command "pkg-config --exists openssl 2>/dev/null" = 0 then
            " -lssl -lcrypto"
          else ""
    in
    let evloop_flag =
      let evloop_c = Filename.concat runtime_dir "march_http_evloop.c" in
      if Sys.file_exists evloop_c then " -DMARCH_HTTP_USE_EVLOOP" else ""
    in
    (* Compression flags: always link -lz (system zlib), optionally zstd/brotli *)
    let compress_flags =
      if not (Sys.file_exists compress_c) then ""
      else begin
        let zstd_flags =
          if Sys.file_exists "/opt/homebrew/include/zstd.h" then
            " -DMARCH_HAVE_ZSTD -I/opt/homebrew/include -L/opt/homebrew/lib -lzstd"
          else if Sys.file_exists "/usr/include/zstd.h" then
            " -DMARCH_HAVE_ZSTD -lzstd"
          else ""
        in
        let brotli_flags =
          if Sys.file_exists "/opt/homebrew/include/brotli/encode.h" then
            " -DMARCH_HAVE_BROTLI -I/opt/homebrew/include -L/opt/homebrew/lib -lbrotlienc -lbrotlidec"
          else if Sys.file_exists "/usr/include/brotli/encode.h" then
            " -DMARCH_HAVE_BROTLI -lbrotlienc -lbrotlidec"
          else ""
        in
        Printf.sprintf " -lz%s%s" zstd_flags brotli_flags
      end
    in
    let so_dbg_flag = if Sys.getenv_opt "MARCH_DEBUG_RUNTIME" <> None then " -g" else "" in
    let so_san_flag =
      if Sys.getenv_opt "MARCH_SANITIZE" <> None then " -fsanitize=address,undefined" else ""
    in
    (* Content key: digests of every C input (the .c files named in the
       command plus every header in runtime/) and the full flag string.
       Identical inputs across worktrees share one artifact; any divergence
       gets its own filename instead of overwriting a shared one. *)
    let flags_sig = Printf.sprintf
      "clang -shared -O2 -fPIC -msse4.2 -Wno-unused-command-line-argument%s%s%s -I%s %s%s%s%s"
      evloop_flag so_dbg_flag so_san_flag runtime_dir runtime_c extra_files openssl_flags compress_flags in
    let key_buf = Buffer.create 256 in
    Buffer.add_string key_buf flags_sig;
    let c_inputs =
      runtime_c ::
      (String.split_on_char ' ' extra_files
       |> List.filter (fun s -> s <> "" && Filename.check_suffix s ".c")) in
    let h_inputs =
      (try Sys.readdir runtime_dir with Sys_error _ -> [||])
      |> Array.to_list
      |> List.filter (fun f -> Filename.check_suffix f ".h")
      |> List.sort String.compare
      |> List.map (Filename.concat runtime_dir) in
    List.iter (fun p ->
        Buffer.add_string key_buf p;
        try Buffer.add_string key_buf (Digest.to_hex (Digest.file p))
        with Sys_error _ -> ())
      (c_inputs @ h_inputs);
    let key = String.sub (Digest.to_hex (Digest.string (Buffer.contents key_buf))) 0 16 in
    let so_path = Filename.concat cache_dir ("libmarch_runtime_" ^ key ^ ".so") in
    if not (Sys.file_exists so_path) then begin
      (* Compile to a pid-suffixed temp and rename into place: rename(2) is
         atomic on the same filesystem, so a concurrent session can never
         dlopen a half-written .so, and same-key racers converge on
         identical bytes regardless of who wins the rename. *)
      let tmp = Printf.sprintf "%s.%d.tmp" so_path (Unix.getpid ()) in
      let cmd = Printf.sprintf "%s -o %s 2>&1" flags_sig tmp in
      let rc = Sys.command cmd in
      if rc <> 0 then begin
        (try Sys.remove tmp with Sys_error _ -> ());
        failwith (Printf.sprintf "march: failed to compile runtime .so (clang exit %d)" rc)
      end;
      (try Sys.rename tmp so_path
       with Sys_error _ -> (try Sys.remove tmp with Sys_error _ -> ()))
    end;
    so_path

let dump_tir       = ref false
let dump_phases    = ref false
let do_timings     = ref false
let emit_llvm      = ref false
let do_compile     = ref false
(* FFI Phase 5: extra C sources / linker flags from forge.toml [[ffi]] blocks,
   compiled + linked into the native binary alongside the runtime. *)
let ffi_c_files    = ref []      (* C source paths, in declaration order (reversed) *)
let ffi_link_flags = ref []      (* extra linker flags, e.g. "-lz" *)
(* A CAS-key fragment digesting the FFI shim sources + link flags, so editing a
   shim (a .c file, not the .march source) invalidates the cached binary. Empty
   when no FFI shims are in play. *)
let ffi_cas_tag () : string list =
  if !ffi_c_files = [] && !ffi_link_flags = [] then []
  else begin
    let buf = Buffer.create 64 in
    List.iter (fun f ->
      Buffer.add_string buf f;
      (try Buffer.add_string buf (Digest.to_hex (Digest.file f)) with _ -> ()))
      (List.rev !ffi_c_files);
    List.iter (Buffer.add_string buf) (List.rev !ffi_link_flags);
    ["ffi:" ^ Digest.to_hex (Digest.string (Buffer.contents buf))]
  end
let do_check       = ref false   (* --check: typecheck only, no codegen or eval *)
let check_json     = ref false   (* --check-json: emit diagnostics as NDJSON to stdout *)
let measure_axioms = ref true    (* --no-measure-axioms: reflect @[measure]s symbolically *)
let do_test        = ref false   (* --test: compile test blocks into a test-runner binary *)
let output_file    = ref ""
let debug_mode     = ref false
let debug_tui_mode = ref false
let opt_enabled    = ref true
let fast_math      = ref false
let pmap_threshold = ref 1024    (* --pmap-threshold: List.pmap sequential-fallback cutoff *)
let no_copy_runtime = ref false    (* --no-copy-runtime: skip auto-copy of march_runtime.mjs *)
(* --hot-reload=<Prefix>: compile boundary modules (under <Prefix>) with the
   versioned dispatch table so their functions can be hot-swapped at runtime. *)
let hot_reload_prefix = ref None
let compile_so = ref false   (* --compile-so: emit a shared library patch (no @main) *)
let signing_pubkey = ref ""  (* --signing-pubkey: base64 ed25519 public key (with --hot-reload) *)
let hr_config () =
  Option.map March_tir.Hot_reload.default_config !hot_reload_prefix
(* CAS cache-key fragment — hot reload changes codegen, so it MUST key the cache. *)
let hr_cas_tag () = match !hot_reload_prefix with Some p -> ["hr:" ^ p] | None -> []
let opt_level      = ref (-1)   (* -1 = not set; 0..3 = explicit clang -ON *)
let do_fmt         = ref false   (* --fmt: format source before compiling *)
let target_str     = ref "native"  (* --target: native | wasm64-wasi | wasm32-wasi | wasm32-unknown-unknown *)

(** Parse --target string into Llvm_emit.target_config. *)
let parse_target s =
  match String.lowercase_ascii s with
  | "native" -> March_tir.Llvm_emit.Native
  | "wasm64-wasi" | "wasm64" -> March_tir.Llvm_emit.Wasm64Wasi
  | "wasm32-wasi" | "wasm32" -> March_tir.Llvm_emit.Wasm32Wasi
  | "wasm32-unknown-unknown" | "wasm-browser" | "browser" -> March_tir.Llvm_emit.Wasm32Unknown
  | "js" | "javascript" -> March_tir.Llvm_emit.Js
  | other ->
    Printf.eprintf "march: unknown target '%s'\n  Valid targets: native, wasm64-wasi, wasm32-wasi, wasm32-unknown-unknown, js\n" other;
    exit 1

(* ------------------------------------------------------------------ *)
(* Formatter helpers                                                   *)
(* ------------------------------------------------------------------ *)

(** Read a file's contents, returning the string. *)
let read_file path =
  let ic = open_in path in
  let n  = in_channel_length ic in
  let buf = Bytes.create n in
  really_input ic buf 0 n;
  close_in ic;
  Bytes.to_string buf

(** Write [contents] to [path] atomically (via a temp file). *)
let write_file path contents =
  let tmp = path ^ ".fmt.tmp" in
  let oc = open_out tmp in
  output_string oc contents;
  close_out oc;
  Sys.rename tmp path

(* ------------------------------------------------------------------ *)
(* Cross-file import resolver (delegated to march_resolver library)  *)
(* ------------------------------------------------------------------ *)

(** Recursively collect all .march files under [dir].
    (Re-exported from the shared resolver for callers below.) *)
let collect_lib_files = March_resolver.Resolver.collect_lib_files

(** Cross-file import resolution — single shared implementation in
    lib/resolver (also used by the REPL and the LSP), so editor
    diagnostics, REPL loads, and forge builds resolve modules identically. *)
let resolve_imports ~source_file m =
  March_resolver.Resolver.resolve_imports ~source_file m

(** Format [filename] in-place.  Returns true if the file was changed. *)
let fmt_file filename =
  let src = read_file filename in
  let formatted =
    try March_format.Format.format_source ~filename src
    with
    | March_errors.Errors.ParseError (msg, hint, _) ->
      Printf.eprintf "%s\n"
        (March_errors.Errors.render_parse_error ~src ~filename ?hint ~msg
           (Lexing.from_string src));
      exit 1
    | March_parser.Parser.Error ->
      let lexbuf = Lexing.from_string src in
      lexbuf.Lexing.lex_curr_p <-
        { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
      Printf.eprintf "%s\n"
        (March_errors.Errors.render_parse_error ~src ~filename
           ~msg:"Parse error (cannot format)" lexbuf);
      exit 1
  in
  formatted <> src, formatted

(** Collect all .march files under a directory recursively. *)
let rec march_files_in dir =
  let entries = Sys.readdir dir in
  Array.sort compare entries;
  Array.fold_left (fun acc entry ->
    let path = Filename.concat dir entry in
    if Sys.is_directory path then
      acc @ march_files_in path
    else if Filename.check_suffix path ".march" then
      acc @ [path]
    else
      acc
  ) [] entries

(** Run the test subcommand and exit.
    Discovers test files, parses/typechecks them, and runs all test blocks.
    Usage: march test [--verbose|-v] [--filter=pattern] [file...] *)
let run_test_cmd args =
  let verbose  = ref false in
  let filter   = ref "" in
  let coverage = ref false in
  let targets  = ref [] in
  List.iter (fun a ->
    if a = "--verbose" || a = "-v" then verbose := true
    else if a = "--coverage" then coverage := true
    else if String.length a > 9 && String.sub a 0 9 = "--filter=" then
      filter := String.sub a 9 (String.length a - 9)
    else if String.length a > 7 && String.sub a 0 7 = "--seed=" then
      Unix.putenv "MARCH_PROP_SEED" (String.sub a 7 (String.length a - 7))
    else if a = "--skip-properties" then
      Unix.putenv "MARCH_SKIP_PROPERTIES" "1"
    else
      targets := a :: !targets
  ) args;
  let targets = List.rev !targets in
  (* If no explicit files given, auto-discover test/test_*.march and test/*_test.march *)
  let files =
    if targets <> [] then targets
    else begin
      let test_dir = "test" in
      if not (Sys.file_exists test_dir) then []
      else
        let entries = List.sort compare (Array.to_list (Sys.readdir test_dir)) in
        List.filter_map (fun name ->
          if (String.length name > 6 && String.sub name 0 5 = "test_"
              && Filename.check_suffix name ".march")
          || Filename.check_suffix name "_test.march"
          then Some (Filename.concat test_dir name)
          else None
        ) entries
    end
  in
  if files = [] then begin
    Printf.eprintf "march test: no test files found\n";
    Printf.eprintf "  Put test files in test/ named test_*.march or *_test.march\n";
    exit 0
  end;
  let total_files = List.length files in
  let total_tests = ref 0 in
  let total_failed = ref 0 in
  let failed_files = ref [] in
  (* In quiet mode (non-verbose), collect failures across files for end-of-run reporting. *)
  let all_file_failures : (string * (string * string) list) list ref = ref [] in
  List.iter (fun filename ->
    let src =
      try read_file filename
      with Sys_error msg ->
        Printf.eprintf "march test: %s\n" msg; exit 1
    in
    if !verbose then Printf.printf "%s\n%!" filename;
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
    let module_ast =
      try March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
      with
      | March_errors.Errors.ParseError (msg, hint, _) ->
        Printf.eprintf "\n%s\n"
          (March_errors.Errors.render_parse_error ~src ~filename ?hint ~msg lexbuf);
        exit 1
      | March_parser.Parser.Error ->
        Printf.eprintf "\n%s\n"
          (March_errors.Errors.render_parse_error ~src ~filename ~msg:"Parse error:" lexbuf);
        exit 1
    in
    let parse_errs = March_parser.Parse_errors.take_parse_errors () in
    if parse_errs <> [] then begin
      List.iter (fun (msg, _hint, pos) ->
        let open Lexing in
        Printf.eprintf "%s:%d:%d: error: %s\n"
          filename pos.pos_lnum (pos.pos_cnum - pos.pos_bol) msg
      ) parse_errs;
      exit 1
    end;
    let desugar_errors = March_errors.Errors.create () in
    let desugared = March_desugar.Desugar.desugar_module ~errors:desugar_errors module_ast in
    if March_errors.Errors.has_errors desugar_errors then begin
      List.iter (fun (d : March_errors.Errors.diagnostic) ->
          Printf.eprintf "%s:%d:%d: error: %s\n"
            d.span.March_ast.Ast.file d.span.March_ast.Ast.start_line
            d.span.March_ast.Ast.start_col d.message
        ) (March_errors.Errors.sorted desugar_errors);
      exit 1
    end;
    let (resolve_errors, extra_decls, user_files) = resolve_imports ~source_file:filename desugared in
    if resolve_errors <> [] then begin
      List.iter (fun (_mod_name, span, msg) ->
          Printf.eprintf "%s:%d:%d: error: %s\n"
            span.March_ast.Ast.file span.March_ast.Ast.start_line
            span.March_ast.Ast.start_col msg
        ) resolve_errors;
      exit 1
    end;
    let desugared =
      { desugared with
        March_ast.Ast.mod_decls = extra_decls @ desugared.March_ast.Ast.mod_decls }
    in
    let stdlib_decls = load_stdlib () in
    let desugared =
      { desugared with
        March_ast.Ast.mod_decls = stdlib_decls @ desugared.March_ast.Ast.mod_decls }
    in
    let (errors, _type_map) = March_typecheck.Typecheck.check_module desugared in
    (* Phase A1b: discharge refinement-precondition VCs at call sites. *)
    March_refinecheck.Refine_check.check_module ~measure_axioms:!measure_axioms errors desugared;
    let diags = March_errors.Errors.sorted errors in
    (* Fatal when the diagnostic points into any file loaded as user code:
       the entry file or imported modules (source dir / MARCH_LIB_PATH). *)
    let is_user_file (d : March_errors.Errors.diagnostic) =
      let f = d.span.March_ast.Ast.file in
      f = filename || f = "" || f = "<unknown>" || List.mem f user_files
    in
    let has_user_errors = List.exists (fun (d : March_errors.Errors.diagnostic) ->
        d.severity = March_errors.Errors.Error && is_user_file d
      ) diags in
    if has_user_errors then begin
      List.iter (fun (d : March_errors.Errors.diagnostic) ->
        if is_user_file d && d.severity = March_errors.Errors.Error then begin
          (* Render against the file the span points into — imported-module
             errors must not be shown with the entry file's source lines. *)
          let f = d.span.March_ast.Ast.file in
          let (d_src, d_file) =
            if f = filename || f = "" || f = "<unknown>" then (src, filename)
            else (try read_file f with Sys_error _ -> src), f
          in
          Printf.eprintf "%s\n\n\n"
            (March_errors.Errors.render_diagnostic ~src:d_src ~filename:d_file d)
        end
      ) diags;
      exit 1
    end;
    (* Enable coverage tracking for this file's test run. *)
    if !coverage then begin
      March_coverage.Coverage.reset ();
      March_coverage.Coverage.coverage_enabled := true
    end;
    (* Check whether the test source opts into IO capture via @capture_io. *)
    let capture_io =
      let pat = "@capture_io" in
      let n = String.length src and p = String.length pat in
      let rec check i =
        if i + p > n then false
        else if String.sub src i p = pat then true
        else check (i + 1)
      in check 0
    in
    let (n_tests, n_failed, file_failures) =
      if !verbose then
        March_eval.Eval.run_tests ~verbose:true ~filter:!filter ~capture_io desugared
      else
        March_eval.Eval.run_tests ~dot_stream:true ~filter:!filter ~capture_io desugared
    in
    if !coverage then begin
      March_coverage.Coverage.coverage_enabled := false;
      March_coverage.Coverage.report_summary ~target_file:filename desugared ()
    end;
    total_tests  := !total_tests + n_tests;
    total_failed := !total_failed + n_failed;
    if n_failed > 0 then begin
      failed_files := filename :: !failed_files;
      if not !verbose then
        all_file_failures := (filename, file_failures) :: !all_file_failures
    end;
    (* Run doctests extracted from fn_doc fields *)
    let parse_expr src =
      let lexbuf = Lexing.from_string src in
      let expr =
        try March_parser.Parser.expr_eof (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
        with
        | March_errors.Errors.ParseError (msg, _, _) ->
          failwith ("doctest parse error: " ^ msg)
        | March_parser.Parser.Error ->
          failwith ("doctest parse error in: " ^ src)
      in
      March_desugar.Desugar.desugar_expr expr
    in
    let (dt_total, dt_failed, dt_failures) =
      if !verbose then
        March_eval.Eval.run_doctests ~verbose:true ~filter:!filter ~parse_expr desugared
      else
        March_eval.Eval.run_doctests ~quiet:true ~filter:!filter ~parse_expr desugared
    in
    total_tests  := !total_tests + dt_total;
    total_failed := !total_failed + dt_failed;
    if dt_failed > 0 then begin
      if not (List.mem filename !failed_files) then
        failed_files := filename :: !failed_files;
      if not !verbose then
        all_file_failures := (filename, dt_failures) :: !all_file_failures
    end
  ) files;
  (* End the dot line after all files *)
  if not !verbose then Printf.printf "\n%!";
  (* Print collected failure details grouped by file. *)
  if not !verbose && !all_file_failures <> [] then begin
    List.iter (fun (filename, failures) ->
      Printf.printf "%s\n" filename;
      List.iter (fun (name, msg) ->
        Printf.printf "  FAIL: \"%s\"\n    %s\n\n" name
          (String.concat "\n    " (String.split_on_char '\n' msg))
      ) failures
    ) (List.rev !all_file_failures)
  end;
  let n_failed_files = List.length !failed_files in
  if n_failed_files = 0 then
    Printf.printf "=== %d file%s, %d test%s passed ===\n%!"
      total_files (if total_files = 1 then "" else "s")
      !total_tests (if !total_tests = 1 then "" else "s")
  else
    Printf.printf "=== %d/%d file%s, %d/%d test%s failed ===\n%!"
      n_failed_files total_files (if total_files = 1 then "" else "s")
      !total_failed !total_tests (if !total_tests = 1 then "" else "s");
  if !total_failed > 0 then exit 1
  else exit 0

(** Run the fmt subcommand and exit. *)
let run_fmt args =
  (* Parse flags and collect targets *)
  let check_mode = ref false in
  let stdin_mode = ref false in
  let targets    = ref [] in
  List.iter (fun a ->
    if a = "--check" then check_mode := true
    else if a = "--stdin" then stdin_mode := true
    else targets := a :: !targets
  ) args;
  (* --stdin: read from stdin, format, write to stdout *)
  if !stdin_mode then begin
    let buf = Buffer.create 4096 in
    (try while true do Buffer.add_char buf (input_char stdin) done
     with End_of_file -> ());
    let src = Buffer.contents buf in
    let filename = match !targets with f :: _ -> f | [] -> "<stdin>" in
    let formatted =
      try March_format.Format.format_source ~filename src
      with _ -> src
    in
    print_string formatted;
    exit 0
  end;
  let targets = List.rev !targets in
  let files = List.concat_map (fun target ->
    if target = "." || (Sys.file_exists target && Sys.is_directory target) then
      march_files_in target
    else
      [target]
  ) targets in
  if files = [] then begin
    Printf.eprintf "march fmt: no files specified\n"; exit 1
  end;
  let any_changed = ref false in
  List.iter (fun f ->
    let changed, formatted = fmt_file f in
    if !check_mode then begin
      if changed then begin
        Printf.eprintf "%s: not formatted\n" f;
        any_changed := true
      end
    end else begin
      if changed then begin
        write_file f formatted;
        Printf.printf "formatted %s\n%!" f
      end
    end
  ) files;
  if !check_mode && !any_changed then exit 1
  else exit 0

(* ------------------------------------------------------------------ *)
(* File compiler                                                       *)
(* ------------------------------------------------------------------ *)

let compile filename =
  let is_js_target = parse_target !target_str = March_tir.Llvm_emit.Js in
  let src =
    try read_file filename
    with Sys_error msg ->
      Printf.eprintf "march: %s\n" msg;
      exit 1
  in
  (* --fmt: format the source file before compiling *)
  if !do_fmt then begin
    let changed, formatted = fmt_file filename in
    if changed then begin
      write_file filename formatted;
      Printf.eprintf "formatted %s\n%!" filename
    end
  end;
  (* Early source-hash CAS: read all input bytes, compute hash, and exit
     before parsing if sources are unchanged since the last successful run.
     This fires for both --check (exit 0) and --compile (copy + exit 0).
     Moving it before the parse+resolve pipeline saves ~0.25s on cache hits. *)
  let early_cas =
    if not !do_compile && not !do_check then None
    else begin
      let buf = Buffer.create (256 * 1024) in
      Buffer.add_string buf src;
      (match stdlib_source_hash ~for_js:is_js_target () with
       | Some (_, h, _) -> Buffer.add_string buf h
       | None -> ());
      (* Hash every .march file the resolver will load as user code: the
         entry's OWN source directory (siblings are auto-discovered by
         resolve_imports — search_path = source_dir :: lib paths) plus all
         MARCH_LIB_PATH directories.  Omitting the source-dir siblings let a
         cached OK artifact survive edits to an imported sibling module, so
         --check/--compile exited 0 on an ill-typed program without ever
         typechecking it.  The entry file is skipped (its bytes are already
         the first buffer element); realpath comparison so relative/absolute
         spellings of the entry don't double-count or slip through. *)
      let lib_path = try Sys.getenv "MARCH_LIB_PATH" with Not_found -> "" in
      let lib_dirs =
        List.filter (fun d -> d <> "") (String.split_on_char ':' lib_path) in
      let entry_real =
        (try Unix.realpath filename with Unix.Unix_error _ -> filename) in
      List.iter (fun dir ->
        let files = List.sort String.compare (collect_lib_files dir) in
        List.iter (fun fp ->
          let fp_real =
            (try Unix.realpath fp with Unix.Unix_error _ -> fp) in
          if fp_real <> entry_real then begin
            Buffer.add_string buf fp;
            (try
              let ic = open_in_bin fp in
              let n  = in_channel_length ic in
              let b  = Bytes.create n in
              really_input ic b 0 n;
              close_in ic;
              Buffer.add_bytes buf b
            with Sys_error _ -> ())
          end
        ) files
      ) (Filename.dirname filename :: lib_dirs);
      let src_hash = "src:" ^ Digest.to_hex (Digest.string (Buffer.contents buf)) in
      let store = March_cas.Cas.create ~project_root:(Sys.getcwd ()) in
      if !do_check then begin
        let ch = March_cas.Cas.compilation_hash src_hash ~target:"check" ~flags:[] in
        (match March_cas.Cas.lookup_artifact store ch with
         | Some _ -> exit 0
         | None -> ());
        Some (store, ch)
      end else begin (* !do_compile *)
        let target_parsed = parse_target !target_str in
        let target_label  = match target_parsed with
          | March_tir.Llvm_emit.Native          -> "native"
          | March_tir.Llvm_emit.Wasm64Wasi      -> "wasm64-wasi"
          | March_tir.Llvm_emit.Wasm32Wasi      -> "wasm32-wasi"
          | March_tir.Llvm_emit.Wasm32Unknown   -> "wasm32-unknown-unknown"
          | March_tir.Llvm_emit.Js              -> "js"
        in
        let effective_opt = if !opt_level >= 0 && !opt_level <= 3 then !opt_level else 2 in
        let cas_flags =
          (if !opt_enabled then Printf.sprintf "O%d" effective_opt else "no-opt")
          :: Printf.sprintf "pmt%d" !pmap_threshold
          :: (hr_cas_tag () @ ffi_cas_tag ()
              @ (if !compile_so then ["compile-so"] else [])) in
        let ch = March_cas.Cas.compilation_hash src_hash ~target:target_label ~flags:cas_flags in
        let is_wasm  = March_tir.Llvm_emit.is_wasm_target target_parsed in
        let basename = Filename.remove_extension filename in
        let out_bin  =
          if !output_file <> "" then !output_file
          else if is_wasm then basename ^ ".wasm"
          else if target_parsed = March_tir.Llvm_emit.Js then basename ^ ".mjs"
          else basename
        in
        (match March_cas.Cas.lookup_artifact store ch with
         | Some cached_bin
           when March_cas.Cas.copy_artifact ~src:cached_bin ~dest:out_bin ->
           Printf.eprintf "compiled %s (cached)\n" out_bin;
           exit 0
         (* Stale/missing artifact or failed copy → recompile *)
         | Some _ | None -> ());
        Some (store, ch)
      end
    end
  in
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
  (* Parse *)
  let module_ast =
    try March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
    with
    | March_errors.Errors.ParseError (msg, hint, _) ->
      Printf.eprintf "%s\n"
        (March_errors.Errors.render_parse_error ~src ~filename ?hint ~msg lexbuf);
      exit 1
    | March_parser.Parser.Error ->
      Printf.eprintf "%s\n"
        (March_errors.Errors.render_parse_error ~src ~filename ~msg:"I got stuck here:" lexbuf);
      exit 1
  in
  (* Display any declaration-level parse errors collected during recovery *)
  let parse_errs = March_parser.Parse_errors.take_parse_errors () in
  let has_parse_errors = parse_errs <> [] in
  List.iter (fun (msg, hint, pos) ->
      let open Lexing in
      Printf.eprintf "%s:%d:%d: error: %s\n"
        filename pos.pos_lnum (pos.pos_cnum - pos.pos_bol) msg;
      (match hint with
       | None -> ()
       | Some h -> Printf.eprintf "hint: %s\n" h)
    ) parse_errs;
  (* Apply .march.spans sidecar remapping if present *)
  let module_ast =
    match March_ast.Span_remap.load_sidecar filename with
    | Some tbl -> March_ast.Span_remap.remap_module tbl module_ast
    | None -> module_ast
  in
  (* Desugar *)
  let desugar_errors = March_errors.Errors.create () in
  let desugared = March_desugar.Desugar.desugar_module ~errors:desugar_errors module_ast in
  List.iter (fun (d : March_errors.Errors.diagnostic) ->
      Printf.eprintf "%s:%d:%d: error: %s\n"
        d.span.March_ast.Ast.file d.span.March_ast.Ast.start_line
        d.span.March_ast.Ast.start_col d.message
    ) (March_errors.Errors.sorted desugar_errors);
  let has_desugar_errors = March_errors.Errors.has_errors desugar_errors in
  (* Capture user AST before stdlib injection — used by -dump-phases *)
  let user_ast = desugared in
  (* Resolve cross-file imports: find imported .march files, parse and inject *)
  let (resolve_errors, extra_decls, user_files) = resolve_imports ~source_file:filename desugared in
  List.iter (fun (_mod_name, span, msg) ->
      Printf.eprintf "%s:%d:%d: error: %s\n"
        span.March_ast.Ast.file span.March_ast.Ast.start_line
        span.March_ast.Ast.start_col msg
    ) resolve_errors;
  let has_resolve_errors = resolve_errors <> [] in
  let desugared =
    { desugared with
      March_ast.Ast.mod_decls = extra_decls @ desugared.March_ast.Ast.mod_decls }
  in
  (* Inject stdlib declarations before user declarations.
     If MARCH_LIB_PATH provided a module that also ships in the stdlib, defer
     to the external version: strip the stdlib copy so the external one is
     the sole definition. *)
  let stdlib_decls = load_stdlib ~for_js:is_js_target () in
  let extern_mod_names =
    (* The ENTRY module's own name must shadow a same-named stdlib module
       too: its declarations live at the top level (not as a DMod in
       extra_decls), so without this a project file like lib/crypto.march
       (`mod Crypto`) coexists with the stdlib Crypto DMod and sibling
       modules resolve `Crypto.foo` against the stdlib copy. *)
    desugared.March_ast.Ast.mod_name.March_ast.Ast.txt
    :: List.filter_map (function
      | March_ast.Ast.DMod (nm, _vis, _decls, _sp) ->
        Some nm.March_ast.Ast.txt
      | _ -> None
    ) extra_decls
  in
  let stdlib_decls =
    if extern_mod_names = [] then stdlib_decls
    else List.filter (function
      | March_ast.Ast.DMod (nm, _vis, _decls, _sp) ->
        not (List.mem nm.March_ast.Ast.txt extern_mod_names)
      | _ -> true
    ) stdlib_decls
  in
  let desugared =
    { desugared with
      March_ast.Ast.mod_decls = stdlib_decls @ desugared.March_ast.Ast.mod_decls }
  in
  (* source_cas_state = early_cas — the CAS lookup already ran before parse.
     On a cache hit we already exited; if we reach this point it's a miss.
     We still pass the (store, ch) pair forward so the post-clang store fires. *)
  let source_cas_state = early_cas in
  (* Per-stage timing: stamp records wall time since process start.
     Enabled by --timings; output goes to stderr so it doesn't mix with
     the compiled binary's stdout. *)
  let t_compile_start = Unix.gettimeofday () in
  let stamp label =
    if !do_timings then
      Printf.eprintf "[timings] %6.3fs  %s\n%!" (Unix.gettimeofday () -. t_compile_start) label
  in
  (* Typecheck + capability enforcement (applies to both eval and compile paths).
     Capability enforcement is embedded in check_module via check_module_needs:
       - transitive needs propagation across module imports
       - extern block capability gating
     See also: March_effects.Effects.check_capabilities *)
  let (errors, type_map, typecheck_env) = March_typecheck.Typecheck.check_module_full desugared in
  (* Phase A1b: discharge refinement-precondition VCs at call sites. *)
  March_refinecheck.Refine_check.check_module ~measure_axioms:!measure_axioms errors desugared;
  stamp "typecheck";
  (* Print diagnostics sorted by position, filtering stdlib-internal errors.
     "User" means any file loaded as user code: the entry file AND modules
     resolved from the source dir / MARCH_LIB_PATH.  Filtering by entry
     filename alone silently compiled ill-typed imported modules. *)
  let diags = March_errors.Errors.sorted errors in
  let is_user_file (d : March_errors.Errors.diagnostic) =
    let f = d.span.March_ast.Ast.file in
    f = filename || f = "" || f = "<unknown>" || List.mem f user_files
  in
  if !check_json then begin
    List.iter (fun (d : March_errors.Errors.diagnostic) ->
      if is_user_file d then
        print_string (March_errors.Errors.render_diagnostic_json d ^ "\n")
    ) diags;
    exit 0
  end;
  List.iter (fun (d : March_errors.Errors.diagnostic) ->
      if is_user_file d then begin
        (* Render against the file the span points into — imported-module
           errors must not be shown with the entry file's source lines. *)
        let f = d.span.March_ast.Ast.file in
        let (d_src, d_file) =
          if f = filename || f = "" || f = "<unknown>" then (src, filename)
          else (try read_file f with Sys_error _ -> src), f
        in
        Printf.eprintf "%s\n\n\n"
          (March_errors.Errors.render_diagnostic ~src:d_src ~filename:d_file d)
      end
    ) diags;
  let compile_mode = !dump_tir || !emit_llvm || !do_compile || !dump_phases in
  let has_user_errors = List.exists (fun (d : March_errors.Errors.diagnostic) ->
      d.severity = March_errors.Errors.Error && is_user_file d
    ) diags in
  (* In compile mode, abort on user-file errors only.  Stdlib errors
     (e.g. http_client) are tolerated since those modules are WIP. *)
  if has_user_errors || has_parse_errors || has_resolve_errors || has_desugar_errors then exit 1
  (* --check: stop after typecheck.  Diagnostics above already printed; we just
     exit 0 so tooling (forge build / forge check) can treat a clean typecheck
     as a pass.  Warnings do not fail the exit code — consistent with eval and
     compile modes. *)
  else if !do_check then begin
    (* Cache successful check result so the next identical-source invocation
       exits immediately without re-running the typecheck pipeline. *)
    (match source_cas_state with
     | Some (src_store, src_ch) ->
       March_cas.Cas.store_artifact src_store src_ch filename
     | None -> ());
    exit 0
  end
  else if compile_mode then begin
    (* -dump-phases: collect per-stage JSON graphs *)
    let phases = ref [] in
    let snap_tir label tir =
      if !dump_phases then
        phases := March_dump.Dump.tir_phase tir label :: !phases
    in
    (* Phase 1: AST after parse+desugar — user file only (no stdlib). *)
    (if !dump_phases then
       phases := March_dump.Dump.ast_phase user_ast "parse" :: !phases);
    let tir = March_tir.Lower.lower_module ~type_map ~test_mode:!do_test desugared in
    (* Inject IO-module names from the typecheck env so the policy audit can
       identify calls that require Cap(IO) at the TIR level. *)
    let io_modules =
      List.filter_map (fun (mod_name, caps) ->
        if List.exists (fun c ->
          c = "IO" ||
          (String.length c > 3 && String.sub c 0 3 = "IO.")
        ) caps
        then Some mod_name
        else None
      ) typecheck_env.March_typecheck.Typecheck.module_caps
    in
    let tir = { tir with March_tir.Tir.tm_io_fns = io_modules } in
    snap_tir "tir-lower" tir;
    stamp "lower";
    (* Capture the interface-dispatch table before it is cleared by lower_module.
       Passed to monomorphize so it can resolve interface calls in functions
       that were polymorphic during lowering but now have concrete types. *)
    let iface_methods = March_tir.Lower.get_iface_methods () in
    (* For WASM island targets, mark render/update/init as exported.
       Set exports BEFORE monomorphization so the functions get mono'd. *)
    let tir = match parse_target !target_str with
      | March_tir.Llvm_emit.Wasm32Unknown ->
        let island_suffixes = ["render"; "update"; "init"] in
        let exports = List.filter_map (fun (fn : March_tir.Tir.fn_def) ->
          let n = fn.March_tir.Tir.fn_name in
          if List.exists (fun suffix ->
            n = suffix ||
            (String.length n > String.length suffix + 1 &&
             String.sub n (String.length n - String.length suffix - 1)
               (String.length suffix + 1) = ("." ^ suffix))
          ) island_suffixes
          then Some n else None
        ) tir.March_tir.Tir.tm_fns in
        { tir with March_tir.Tir.tm_exports = exports }
      | _ -> tir
    in
    let tir = March_tir.Mono.monomorphize ~iface_methods tir in
    snap_tir "tir-mono" tir;
    stamp "mono";
    (* After mono, update tm_exports to use monomorphized names *)
    let tir =
      if tir.March_tir.Tir.tm_exports <> [] then begin
        let island_suffixes = ["render"; "update"; "init"] in
        let matches_suffix name suffix =
          let base = match String.index_opt name '$' with
            | Some i -> String.sub name 0 i
            | None -> name
          in
          base = suffix ||
          (String.length base > String.length suffix + 1 &&
           String.sub base (String.length base - String.length suffix - 1)
             (String.length suffix + 1) = ("." ^ suffix))
        in
        let exports = List.filter_map (fun (fn : March_tir.Tir.fn_def) ->
          let n = fn.March_tir.Tir.fn_name in
          if List.exists (matches_suffix n) island_suffixes
          then Some n else None
        ) tir.March_tir.Tir.tm_fns in
        { tir with March_tir.Tir.tm_exports = exports }
      end else tir
    in
    (* Pin __rpc_stub functions so the DCE pass keeps them (and their callees)
       alive.  Without this, private stubs never called from March code are
       dropped before the CAS hash and LLVM emit steps can see them. *)
    let tir =
      let stub_suffix = "__rpc_stub" in
      let slen = String.length stub_suffix in
      let stubs = List.filter_map (fun (fn : March_tir.Tir.fn_def) ->
        let n = fn.March_tir.Tir.fn_name in
        let nl = String.length n in
        if nl > slen && String.sub n (nl - slen) slen = stub_suffix
        then Some n else None
      ) tir.March_tir.Tir.tm_fns in
      if stubs = [] then tir
      else { tir with March_tir.Tir.tm_exports =
               tir.March_tir.Tir.tm_exports @ stubs }
    in
    let tir = if !opt_enabled then March_tir.Fusion.run ~changed:(ref false) tir else tir in
    snap_tir "tir-fusion" tir;
    stamp "fusion";
    (* Phase 3b: policy-tag audit — report violations in Tagged(_, P) functions. *)
    let policy_violations = March_tir.Policy_dce.audit tir in
    List.iter (fun (_fn_name, msg) ->
      Printf.eprintf "Error: %s\n\n" msg
    ) policy_violations;
    if policy_violations <> [] then exit 1;
    let tir = March_tir.Defun.defunctionalize tir in
    snap_tir "tir-defun" tir;
    stamp "defun";
    (* Known-call pass: run before Perceus so apply functions are still pure
       and eligible for inlining in the subsequent Opt fixed-point loop.
       Also included in the Opt coordinator for cases revealed after Perceus.
       This rewrites ECallPtr(clo, args) -> EApp(clo_apply, clo :: args).  The
       closure-apply ABI consumes the closure argument, so Perceus must NOT
       emit a caller-side post-call EDecRC for the $clo slot of an apply
       function even when borrow inference classifies it as borrowed — see the
       [is_apply_fn] guard in [Perceus]'s EApp post_dec_vars.  Without that
       guard the rewrite double-freed the closure (List.sort_by SIGBUS at
       n >= ~90 with a heap-capturing comparator). *)
    let tir = if !opt_enabled
              then March_tir.Known_call.run ~changed:(ref false) tir
              else tir in
    snap_tir "tir-known-call" tir;
    (* Beta-ADT: reduce case-of-known-constructor before Perceus so that the
       EAlloc is DCE'd before RC insertion, avoiding a spurious allocation and
       its associated reference-count operations entirely. *)
    let tir = if !opt_enabled
              then March_tir.Beta_adt.run ~changed:(ref false) tir
              else tir in
    snap_tir "tir-beta-adt-pre" tir;
    (* P1 Layer 1: alpha-merge let-floating on RC-free TIR.  Hoists common
       leading lets above ECase even when arms bind the shared RHS under
       different fresh ANF names, substituting onto one floated binder.  Must
       run BEFORE Perceus so RC is inserted once for the hoisted binding.  The
       conservative (name-equality) variant still runs in the post-Perceus opt
       loop. *)
    let tir = if !opt_enabled
              then March_tir.Join_points.run_pre ~changed:(ref false) tir
              else tir in
    snap_tir "tir-join-points-pre" tir;
    (* Pre-Perceus simplify: folds that are only sound before RC insertion,
       currently the empty-string concat identities (x ++ "" → x, "" ++ x → x).
       Folding here aliases the result to `x` while it is still un-RC-tracked, so
       Perceus inserts a single correct dec_rc afterwards.  The post-Perceus Opt
       loop runs Simplify with pre_perceus=false and never applies these. *)
    let tir = if !opt_enabled
              then March_tir.Simplify.run ~pre_perceus:true ~changed:(ref false) tir
              else tir in
    snap_tir "tir-simplify-pre" tir;
    let tir = March_tir.Perceus.perceus tir in
    snap_tir "tir-perceus" tir;
    stamp "perceus";
    let tir = March_tir.Escape.escape_analysis tir in
    snap_tir "tir-escape" tir;
    stamp "escape";
    (* Run optimizer with per-pass snapshots (Phase 3 instrumentation).
       When dump_phases is on, each individual opt pass is captured separately
       (tir-opt-1-inline, tir-opt-1-cprop, …) so the viewer shows every step.
       When opt is disabled, fall through to a single tir-opt snapshot. *)
    (* Save pre-opt TIR so we can hash __rpc_stub base functions that the
       inliner may eliminate before the CAS hash step below. *)
    let pre_opt_tir = tir in
    let tir =
      if !opt_enabled then
        March_tir.Opt.run
          ~snap:(fun label m ->
            if !dump_phases then
              phases := March_dump.Dump.tir_phase m label :: !phases)
          ~hot_reload:(hr_config ())
          tir
      else tir
    in
    (* When opt is disabled there are no per-pass snaps; still emit one overall. *)
    if not !opt_enabled then snap_tir "tir-opt" tir;
    stamp "opt";
    (* RPC admission hashes (remote_ref_hashes constant-folding + the @main
       march_remote_register calls) must be IDENTICAL across SEPARATE client and
       server compilations of the same source.  Derive them uniformly from the
       PRE-opt TIR via hash_fn_def for ALL functions — never from the post-opt
       SCC hashes, which only a live (server-side) function receives while a
       caller-side function is usually dead-code-eliminated, so the two binaries
       would disagree.  Combined with alpha-normalized serialization this makes
       each hash a pure function of the function's normalized body + its callees'
       stable names, so a non-trivial body (one that calls stdlib functions)
       matches across binaries just like a trivial leaf does. *)
    let rpc_impl_hashes : (string, string) Hashtbl.t = Hashtbl.create 16 in
    let rpc_sig_hashes  : (string, string) Hashtbl.t = Hashtbl.create 16 in
    List.iter (fun (fn : March_tir.Tir.fn_def) ->
      let h = March_cas.Hash.hash_fn_def fn in
      Hashtbl.replace rpc_impl_hashes fn.March_tir.Tir.fn_name h.March_cas.Hash.impl_hash;
      Hashtbl.replace rpc_sig_hashes  fn.March_tir.Tir.fn_name h.March_cas.Hash.sig_hash
    ) pre_opt_tir.March_tir.Tir.tm_fns;
    (* Write all collected phases to march-phases/phases.json *)
    (if !dump_phases then
       March_dump.Dump.write_phases ~source_file:filename (List.rev !phases));
    if !dump_tir then begin
      List.iter (fun td ->
          Printf.printf "%s\n\n" (March_tir.Pp.string_of_type_def td)
        ) tir.tm_types;
      List.iter (fun fn ->
          Printf.printf "%s\n\n" (March_tir.Pp.string_of_fn_def fn)
        ) tir.tm_fns
    end else begin
      let target = parse_target !target_str in
      let basename = Filename.remove_extension filename in
      let ll_file  = basename ^ ".ll" in
      if !do_compile then begin
        let is_wasm = March_tir.Llvm_emit.is_wasm_target target in
        let out_bin =
          if !output_file <> "" then !output_file
          else if is_wasm then basename ^ ".wasm"
          else if target = March_tir.Llvm_emit.Js then basename ^ ".mjs"
          else basename
        in
        (* JS target: skip LLVM/clang entirely *)
        if target = March_tir.Llvm_emit.Js then begin
          let tir_for_js = if !opt_enabled then March_tir.Opt.run tir else tir in
          (* Collect source lines from user AST for source map generation.
             user_ast = desugared before stdlib injection, so only user functions. *)
          let rec collect_fn_lines prefix = function
            | [] -> []
            | March_ast.Ast.DFn (def, _) :: rest ->
              let name = prefix ^ def.fn_name.txt in
              let line = def.fn_name.span.start_line in
              (name, line) :: collect_fn_lines prefix rest
            | March_ast.Ast.DMod (nm, _, sub, _) :: rest ->
              collect_fn_lines (prefix ^ nm.txt ^ ".") sub
              @ collect_fn_lines prefix rest
            | _ :: rest -> collect_fn_lines prefix rest
          in
          let fn_lines =
            collect_fn_lines "" user_ast.March_ast.Ast.mod_decls
          in
          let (js, map_opt) =
            (try March_tir.Js_emit.emit_module ~source_file:filename ~fn_lines tir_for_js
             with March_tir.Js_emit.Js_emit_error msgs ->
               List.iter (fun msg -> Printf.eprintf "%s\n" msg) msgs;
               exit 1)
          in
          (* Write source map if available, and append sourceMappingURL to JS *)
          let map_name = Filename.basename out_bin ^ ".map" in
          let js = match map_opt with
            | None -> js
            | Some map_json ->
              let map_path = Filename.concat (Filename.dirname out_bin) map_name in
              (try
                let oc2 = open_out map_path in
                output_string oc2 map_json;
                close_out oc2
               with Sys_error _ -> ());
              js ^ "//# sourceMappingURL=" ^ map_name ^ "\n"
          in
          let oc = open_out out_bin in
          output_string oc js;
          close_out oc;
          (* Copy runtime .mjs files alongside the output so imports work,
             unless --no-copy-runtime is given (e.g. when dune manages them) *)
          if not !no_copy_runtime then begin
            let out_dir = Filename.dirname out_bin in
            let copy_runtime name =
              let dest = Filename.concat out_dir name in
              let candidates = [
                Filename.concat "runtime" name;
                Filename.concat (Filename.dirname Sys.executable_name) (Filename.concat "../runtime" name);
                Filename.concat (Filename.dirname Sys.executable_name) (Filename.concat "../../runtime" name);
              ] in
              match List.find_opt Sys.file_exists candidates with
              | Some src ->
                let ic = open_in src in
                let content = really_input_string ic (in_channel_length ic) in
                close_in ic;
                let oc2 = open_out dest in
                output_string oc2 content;
                close_out oc2
              | None -> Printf.eprintf "march: warning: cannot find %s\n" name
            in
            copy_runtime "march_runtime.mjs";
            copy_runtime "march_dom.mjs"
          end;
          Printf.eprintf "compiled %s\n" out_bin
        end else begin
        (* CAS: check for a cached binary before running clang *)
        let target_label = match target with
          | March_tir.Llvm_emit.Native -> "native"
          | March_tir.Llvm_emit.Wasm64Wasi -> "wasm64-wasi"
          | March_tir.Llvm_emit.Wasm32Wasi -> "wasm32-wasi"
          | March_tir.Llvm_emit.Wasm32Unknown -> "wasm32-unknown-unknown"
          | March_tir.Llvm_emit.Js -> "js"
        in
        let store = March_cas.Cas.create ~project_root:(Sys.getcwd ()) in
        let h_sccs = March_cas.Pipeline.hash_module tir in
        let mod_hash = String.concat "" (List.map March_cas.Pipeline.scc_impl_hash h_sccs) in
        (* Hot Code Reload: per-function impl_hash map (qualified fn name →
           64-char hex Merkle root) so the baseline dispatch-table publish can
           carry real hashes instead of null. Built from the same CAS hashing
           that keys the artifact cache; only consulted when --hot-reload is on. *)
        let hr_impl_hashes : (string, string) Hashtbl.t = Hashtbl.create 16 in
        (* L4 remote registry: sig_hash map for remote_ref_hashes constant folding. *)
        let remote_sig_hashes : (string, string) Hashtbl.t = Hashtbl.create 16 in
        let add_hdef (hd : March_cas.Cas.hashed_def) =
          match hd.March_cas.Cas.hd_def with
          | March_cas.Cas.FnDef fd ->
            Hashtbl.replace hr_impl_hashes fd.March_tir.Tir.fn_name
              hd.March_cas.Cas.hd_impl_hash;
            Hashtbl.replace remote_sig_hashes fd.March_tir.Tir.fn_name
              hd.March_cas.Cas.hd_sig_hash
          | March_cas.Cas.TypeDef _ -> ()
        in
        List.iter (function
          | March_cas.Pipeline.HSingle { hs_hdef } -> add_hdef hs_hdef
          | March_cas.Pipeline.HGroup { hg_hdefs; _ } -> List.iter add_hdef hg_hdefs)
          h_sccs;
        (* For __rpc_stub base functions inlined by opt (no post-opt entry),
           fall back to pre-opt hashes so stub_setup can emit register calls. *)
        let () =
          let stub_suffix = "__rpc_stub" in
          let slen = String.length stub_suffix in
          let pre_fns = pre_opt_tir.March_tir.Tir.tm_fns in
          let pre_fn_tbl = Hashtbl.create 16 in
          List.iter (fun fd -> Hashtbl.replace pre_fn_tbl fd.March_tir.Tir.fn_name fd) pre_fns;
          List.iter (fun (fn : March_tir.Tir.fn_def) ->
            let n = fn.March_tir.Tir.fn_name in
            let nl = String.length n in
            if nl > slen && String.sub n (nl - slen) slen = stub_suffix then begin
              let base = String.sub n 0 (nl - slen) in
              if not (Hashtbl.mem hr_impl_hashes base) then
                match Hashtbl.find_opt pre_fn_tbl base with
                | Some base_fn ->
                  let h = March_cas.Hash.hash_fn_def base_fn in
                  Hashtbl.replace hr_impl_hashes base h.March_cas.Hash.impl_hash;
                  Hashtbl.replace remote_sig_hashes base h.March_cas.Hash.sig_hash
                | None -> ()
            end
          ) pre_fns;
          (* Pass 2: hash all remaining pre-opt functions so remote_ref_hashes
             constant-folding works even when the optimizer eliminated them
             (e.g. a pfn only referenced from the caller side, not the server). *)
          List.iter (fun (fn : March_tir.Tir.fn_def) ->
            let n = fn.March_tir.Tir.fn_name in
            if not (Hashtbl.mem hr_impl_hashes n) then begin
              let h = March_cas.Hash.hash_fn_def fn in
              Hashtbl.replace hr_impl_hashes n h.March_cas.Hash.impl_hash;
              Hashtbl.replace remote_sig_hashes n h.March_cas.Hash.sig_hash
            end
          ) pre_fns
        in
        let effective_opt = if !opt_level >= 0 && !opt_level <= 3 then !opt_level else 2 in
        let cas_flags =
          (if !opt_enabled then Printf.sprintf "O%d" effective_opt else "no-opt")
          :: Printf.sprintf "pmt%d" !pmap_threshold
          :: (hr_cas_tag () @ ffi_cas_tag ()
              @ (if !compile_so then ["compile-so"] else [])) in
        let ch = March_cas.Cas.compilation_hash mod_hash ~target:target_label ~flags:cas_flags in
        let cached_ok =
          match March_cas.Cas.lookup_artifact store ch with
          | Some cached_bin ->
            March_cas.Cas.copy_artifact ~src:cached_bin ~dest:out_bin
          | None -> false
        in
        (if cached_ok then
          Printf.eprintf "compiled %s (cached)\n" out_bin
        else
          (* Cache miss (or stale artifact / failed copy): emit LLVM IR,
             call clang, then cache the binary *)
          let ir = March_tir.Llvm_emit.emit_module ~fast_math:!fast_math ~pmap_threshold:!pmap_threshold ~target ~hot_reload:(hr_config ()) ~impl_hashes:hr_impl_hashes ~remote_impl_hashes:rpc_impl_hashes ~remote_sig_hashes:remote_sig_hashes ~emit_main:(not !compile_so) tir in
          stamp "llvm-emit";
          let oc = open_out ll_file in
          output_string oc ir;
          close_out oc;
          if is_wasm then begin
            (* ── WASM compilation path ──────────────────────────────────── *)
            let wasm_runtime_candidates = [
              "runtime/march_runtime_wasm.c";
              Filename.concat (Filename.dirname Sys.executable_name) "../runtime/march_runtime_wasm.c";
              Filename.concat (Filename.dirname Sys.executable_name) "../../runtime/march_runtime_wasm.c";
            ] in
            let wasm_runtime = match List.find_opt Sys.file_exists wasm_runtime_candidates with
              | Some p -> p
              | None ->
                (* Fall back to main runtime with -DMARCH_WASM *)
                let candidates = [
                  "runtime/march_runtime.c";
                  Filename.concat (Filename.dirname Sys.executable_name) "../runtime/march_runtime.c";
                  Filename.concat (Filename.dirname Sys.executable_name) "../../runtime/march_runtime.c";
                ] in
                (match List.find_opt Sys.file_exists candidates with
                 | Some p -> p
                 | None ->
                   Printf.eprintf "march: cannot find runtime for WASM target\n"; exit 1)
            in
            let triple = March_tir.Llvm_emit.target_triple target in
            let opt_flag = Printf.sprintf " -O%d" effective_opt in
            (* Locate wasi-sdk for WASI targets, or use system clang for wasm32-unknown-unknown *)
            let clang, sysroot_flag = match target with
              | March_tir.Llvm_emit.Wasm64Wasi | March_tir.Llvm_emit.Wasm32Wasi ->
                let wasi_sdk = match Sys.getenv_opt "WASI_SDK_PATH" with
                  | Some p -> p
                  | None ->
                    if Sys.file_exists "/opt/wasi-sdk" then "/opt/wasi-sdk"
                    else begin
                      Printf.eprintf "march: wasi-sdk not found. Set WASI_SDK_PATH or install to /opt/wasi-sdk\n";
                      exit 1
                    end
                in
                (Filename.concat wasi_sdk "bin/clang",
                 Printf.sprintf " --sysroot=%s/share/wasi-sysroot" wasi_sdk)
              | _ ->
                (* wasm32-unknown-unknown: need a clang with WASM backend.
                   Apple clang doesn't include it, so try wasi-sdk or homebrew LLVM. *)
                let wasm_clang =
                  let wasi_candidates = [
                    (match Sys.getenv_opt "WASI_SDK_PATH" with Some p -> Some (Filename.concat p "bin/clang") | None -> None);
                    (if Sys.file_exists "/opt/wasi-sdk/bin/clang" then Some "/opt/wasi-sdk/bin/clang" else None);
                    (if Sys.file_exists "/opt/homebrew/opt/llvm/bin/clang" then Some "/opt/homebrew/opt/llvm/bin/clang" else None);
                    (if Sys.file_exists "/usr/local/opt/llvm/bin/clang" then Some "/usr/local/opt/llvm/bin/clang" else None);
                  ] in
                  match List.find_map Fun.id wasi_candidates with
                  | Some p -> p
                  | None ->
                    Printf.eprintf "march: No clang with WASM backend found.\n";
                    Printf.eprintf "  Install wasi-sdk (brew install wasi-sdk) or LLVM (brew install llvm)\n";
                    exit 1
                in
                (wasm_clang, " -nostdlib -Wl,--no-entry -Wl,--export-dynamic")
            in
            let wasm_dbg_flag = if !debug_mode || !debug_tui_mode then " -g" else "" in
            let cmd = Printf.sprintf
              "%s --target=%s%s%s%s -DMARCH_WASM -Wno-unused-command-line-argument %s %s -o %s"
              clang triple sysroot_flag opt_flag wasm_dbg_flag wasm_runtime ll_file out_bin in
            let rc = Sys.command cmd in
            if rc <> 0 then begin
              Printf.eprintf "march: WASM compilation failed (exit %d)\n  cmd: %s\n" rc cmd; exit 1
            end else begin
              stamp "clang";
              March_cas.Cas.store_artifact store ch out_bin;
              (match source_cas_state with
               | Some (src_store, src_ch) -> March_cas.Cas.store_artifact src_store src_ch out_bin
               | None -> ());
              Printf.eprintf "compiled %s (%s)\n" out_bin target_label
            end
          end else begin
            (* ── Native compilation path ────────────────────────────────── *)
            let candidates = [
              "runtime/march_runtime.c";
              Filename.concat (Filename.dirname Sys.executable_name) "../runtime/march_runtime.c";
              Filename.concat (Filename.dirname Sys.executable_name) "../../runtime/march_runtime.c";
            ] in
            let runtime = match List.find_opt Sys.file_exists candidates with
              | Some p -> p
              | None ->
                Printf.eprintf "march: cannot find runtime/march_runtime.c\n"; exit 1
            in
            let opt_flag = Printf.sprintf " -O%d" effective_opt in
            let runtime_dir = Filename.dirname runtime in
            let http_c      = Filename.concat runtime_dir "march_http.c" in
            let extras_c2   = Filename.concat runtime_dir "march_extras.c" in
            let compress_c2 = Filename.concat runtime_dir "march_compress.c" in
            let opt_file2 f = if Sys.file_exists f then Printf.sprintf " %s" f else "" in
            let sched_c2  = Filename.concat runtime_dir "march_scheduler.c" in
            let ffi_c2    = Filename.concat runtime_dir "march_ffi.c" in
            let sha1_c2   = Filename.concat runtime_dir "sha1.c" in
            let base64_c2 = Filename.concat runtime_dir "base64.c" in
            let extra_c_files =
              (if Sys.file_exists http_c then
                let simd_c    = Filename.concat runtime_dir "march_http_parse_simd.c" in
                let resp_c    = Filename.concat runtime_dir "march_http_response.c" in
                let io_c      = Filename.concat runtime_dir "march_http_io.c" in
                let evloop_c  = Filename.concat runtime_dir "march_http_evloop.c" in
                let tls_c2    = Filename.concat runtime_dir "march_tls.c" in
                Printf.sprintf " %s %s %s%s%s%s%s%s%s%s%s" http_c sha1_c2 base64_c2
                  (opt_file2 simd_c) (opt_file2 sched_c2) (opt_file2 resp_c)
                  (opt_file2 io_c) (opt_file2 evloop_c)
                  (opt_file2 tls_c2) (opt_file2 extras_c2) (opt_file2 compress_c2)
              else
                (* march_extras.c references base64_encode (base64.c) and sha1
                   (sha1.c), so link them whenever extras is linked — independent
                   of the HTTP stack (else an extras-but-no-http build tree fails
                   with undefined _base64_encode / _sha1). opt_file2-guarded. *)
                Printf.sprintf "%s%s%s%s%s" (opt_file2 sched_c2) (opt_file2 extras_c2)
                  (opt_file2 compress_c2) (opt_file2 base64_c2) (opt_file2 sha1_c2))
              ^ (opt_file2 ffi_c2)
              ^ (if not !compile_so then opt_file2 (Filename.concat runtime_dir "march_dispatch.c") else "")  (* HCR dispatch table *)
              ^ (if not !compile_so then opt_file2 (Filename.concat runtime_dir "march_reload.c")    else "")  (* HCR reload server *)
              ^ (if not !compile_so then opt_file2 (Filename.concat runtime_dir "tweetnacl.c")       else "")  (* ed25519 for ACTIVATE verification *)
              ^ (opt_file2 (Filename.concat runtime_dir "march_remote_registry.c"))  (* L4 remote registry *)
              (* User FFI shim sources from forge.toml [[ffi]] (--ffi-c). *)
              ^ String.concat "" (List.rev_map (fun f -> " " ^ Filename.quote f) !ffi_c_files)
            in
            (* OpenSSL flags for TLS *)
            let tls_c2 = Filename.concat runtime_dir "march_tls.c" in
            let openssl_flags2 =
              if not (Sys.file_exists tls_c2) then ""
              else
                let dirs = [
                  "/opt/homebrew/opt/openssl@3";
                  "/opt/homebrew/opt/openssl";
                  "/usr/local/opt/openssl@3";
                  "/usr/local/opt/openssl";
                ] in
                let found = List.fold_left (fun acc d ->
                  match acc with
                  | Some _ -> acc
                  | None ->
                    let hdr = Filename.concat d "include/openssl/ssl.h" in
                    if Sys.file_exists hdr then Some d else None
                ) None dirs in
                match found with
                | Some d ->
                  Printf.sprintf " -I%s/include -L%s/lib -lssl -lcrypto" d d
                | None ->
                  if Sys.command "pkg-config --exists openssl 2>/dev/null" = 0
                  then " -lssl -lcrypto" else ""
            in
            let evloop_flag =
              let evloop_c = Filename.concat runtime_dir "march_http_evloop.c" in
              if Sys.file_exists evloop_c then " -DMARCH_HTTP_USE_EVLOOP" else ""
            in
            let compress_flags2 =
              if not (Sys.file_exists compress_c2) then ""
              else begin
                let zstd_flags =
                  if Sys.file_exists "/opt/homebrew/include/zstd.h" then
                    " -DMARCH_HAVE_ZSTD -I/opt/homebrew/include -L/opt/homebrew/lib -lzstd"
                  else if Sys.file_exists "/usr/include/zstd.h" then
                    " -DMARCH_HAVE_ZSTD -lzstd"
                  else ""
                in
                let brotli_flags =
                  if Sys.file_exists "/opt/homebrew/include/brotli/encode.h" then
                    " -DMARCH_HAVE_BROTLI -I/opt/homebrew/include -L/opt/homebrew/lib -lbrotlienc -lbrotlidec"
                  else if Sys.file_exists "/usr/include/brotli/encode.h" then
                    " -DMARCH_HAVE_BROTLI -lbrotlienc -lbrotlidec"
                  else ""
                in
                Printf.sprintf " -lz%s%s" zstd_flags brotli_flags
              end
            in
            let math_flag = if Sys.unix then " -lm" else "" in
            let dbg_flag = if !debug_mode || !debug_tui_mode then " -g" else "" in
            let san_flag =
              if Sys.getenv_opt "MARCH_SANITIZE" <> None then " -fsanitize=address,undefined"
              else ""
            in
            (* User FFI linker flags from forge.toml [[ffi]] (--ffi-link), e.g. -lz. *)
            let ffi_link = String.concat "" (List.rev_map (fun f -> " " ^ f) !ffi_link_flags) in
            (* When compiling user FFI shims, put the runtime dir on the include
               path so their `#include "march_ffi.h"` resolves with no config. *)
            let ffi_inc = if !ffi_c_files = [] then ""
                          else Printf.sprintf " -I%s" (Filename.quote runtime_dir) in
            let rdynamic_flag =
              (* Export all symbols so dlopen'd patch .so can resolve back to server.
                 Pass via -Wl, so the flag goes straight to the linker, not the clang driver.
                 Linux (GNU ld): --export-dynamic. macOS (ld64): -export_dynamic. *)
              if !hot_reload_prefix <> None && not !compile_so then
                if Sys.file_exists "/proc/version" then " -Wl,--export-dynamic"
                else " -Wl,-export_dynamic"
              else "" in
            let so_flag =
              if !compile_so then
                (* Linux: allow undefined symbols resolved from the server binary at dlopen time.
                   macOS: clang uses -undefined dynamic_lookup for the same effect. *)
                let undef = if Sys.file_exists "/proc/version"
                            then " -Wl,--allow-shlib-undefined"
                            else " -undefined dynamic_lookup" in
                " -shared -fPIC" ^ undef
              else "" in
            let reload_ldl =
              (* -ldl is needed on Linux for dlopen; macOS has it in libc. *)
              if !hot_reload_prefix <> None && not !compile_so
                 && Sys.file_exists "/proc/version" then " -ldl" else "" in
            let signing_define =
              if !hot_reload_prefix <> None && not !compile_so && !signing_pubkey <> "" then
                match b64_decode_pubkey !signing_pubkey with
                | Some hex -> Printf.sprintf " -DMARCH_SIGNING_PUBKEY_HEX=\"%s\"" hex
                | None ->
                  Printf.eprintf "march: --signing-pubkey: invalid base64 or not 32 bytes\n";
                  ""
              else "" in
            let cmd = Printf.sprintf
              "clang%s%s%s%s%s -msse4.2 -Wno-unused-command-line-argument%s%s%s %s%s%s%s%s %s -o %s%s%s"
              opt_flag dbg_flag san_flag rdynamic_flag so_flag evloop_flag ffi_inc signing_define runtime extra_c_files openssl_flags2 compress_flags2 ffi_link ll_file out_bin math_flag reload_ldl in
            let rc = Sys.command cmd in
            if rc <> 0 then begin
              Printf.eprintf "march: clang failed (exit %d)\n" rc; exit 1
            end else begin
              stamp "clang";
              March_cas.Cas.store_artifact store ch out_bin;
              (match source_cas_state with
               | Some (src_store, src_ch) -> March_cas.Cas.store_artifact src_store src_ch out_bin
               | None -> ());
              Printf.eprintf "compiled %s\n" out_bin
            end
          end);
        (* When building a hot-reload .so, write a sidecar manifest so that
           forge deploy hot knows each function's impl_hash and sig_hash
           without having to dlopen the artifact.  Format:
             # march-hcr-manifest v1
             # cas_hash <64-char blake3 hex>
             <fn_name> <impl_hash> <sig_hash>
           sig_hash may be empty if the function was not hashed. *)
        (if !compile_so && Hashtbl.length hr_impl_hashes > 0 then begin
          let mf = out_bin ^ ".hcr_manifest" in
          (try
             let oc = open_out mf in
             Printf.fprintf oc "# march-hcr-manifest v1\n# cas_hash %s\n" ch;
             Hashtbl.iter (fun name impl_h ->
               let sig_h = Option.value ~default:""
                   (Hashtbl.find_opt remote_sig_hashes name) in
               Printf.fprintf oc "%s %s %s\n" name impl_h sig_h
             ) hr_impl_hashes;
             close_out oc
           with Sys_error _ -> ()) (* non-fatal if manifest write fails *)
        end)
      end (* else begin: non-JS LLVM/clang path *)
      end else begin
        (* --emit-llvm only: write IR and exit *)
        (* Mirror the compile path's per-fn impl_hash map so --emit-llvm
           --hot-reload also publishes real baseline hashes (only built/used
           when --hot-reload is active). *)
        let hr_impl_hashes : (string, string) Hashtbl.t = Hashtbl.create 16 in
        let remote_sig_hashes2 : (string, string) Hashtbl.t = Hashtbl.create 16 in
        (let add_hdef (hd : March_cas.Cas.hashed_def) =
           match hd.March_cas.Cas.hd_def with
           | March_cas.Cas.FnDef fd ->
             Hashtbl.replace hr_impl_hashes fd.March_tir.Tir.fn_name
               hd.March_cas.Cas.hd_impl_hash;
             Hashtbl.replace remote_sig_hashes2 fd.March_tir.Tir.fn_name
               hd.March_cas.Cas.hd_sig_hash
           | March_cas.Cas.TypeDef _ -> ()
         in
         List.iter (function
           | March_cas.Pipeline.HSingle { hs_hdef } -> add_hdef hs_hdef
           | March_cas.Pipeline.HGroup { hg_hdefs; _ } -> List.iter add_hdef hg_hdefs)
           (March_cas.Pipeline.hash_module tir));
        let () =
          let stub_suffix = "__rpc_stub" in
          let slen = String.length stub_suffix in
          let pre_fns = pre_opt_tir.March_tir.Tir.tm_fns in
          let pre_fn_tbl = Hashtbl.create 16 in
          List.iter (fun fd -> Hashtbl.replace pre_fn_tbl fd.March_tir.Tir.fn_name fd) pre_fns;
          List.iter (fun (fn : March_tir.Tir.fn_def) ->
            let n = fn.March_tir.Tir.fn_name in
            let nl = String.length n in
            if nl > slen && String.sub n (nl - slen) slen = stub_suffix then begin
              let base = String.sub n 0 (nl - slen) in
              if not (Hashtbl.mem hr_impl_hashes base) then
                match Hashtbl.find_opt pre_fn_tbl base with
                | Some base_fn ->
                  let h = March_cas.Hash.hash_fn_def base_fn in
                  Hashtbl.replace hr_impl_hashes base h.March_cas.Hash.impl_hash;
                  Hashtbl.replace remote_sig_hashes2 base h.March_cas.Hash.sig_hash
                | None -> ()
            end
          ) pre_fns;
          List.iter (fun (fn : March_tir.Tir.fn_def) ->
            let n = fn.March_tir.Tir.fn_name in
            if not (Hashtbl.mem hr_impl_hashes n) then begin
              let h = March_cas.Hash.hash_fn_def fn in
              Hashtbl.replace hr_impl_hashes n h.March_cas.Hash.impl_hash;
              Hashtbl.replace remote_sig_hashes2 n h.March_cas.Hash.sig_hash
            end
          ) pre_fns
        in
        let ir = March_tir.Llvm_emit.emit_module ~fast_math:!fast_math ~pmap_threshold:!pmap_threshold ~target ~hot_reload:(hr_config ()) ~impl_hashes:hr_impl_hashes ~remote_impl_hashes:rpc_impl_hashes ~remote_sig_hashes:remote_sig_hashes2 ~emit_main:(not !compile_so) tir in
        let oc = open_out ll_file in
        output_string oc ir;
        close_out oc;
        Printf.eprintf "wrote %s\n" ll_file
      end
    end
  end
  else begin
    (* Set up the on-demand module loader so qualified access like Map.get()
       can trigger loading a stdlib module even if it wasn't explicitly imported.
       This is mostly a fallback — load_stdlib() already loads common modules,
       but this covers modules not in the hardcoded list or REPL scenarios. *)
    March_eval.Eval.module_loader := Some (fun mod_name ->
      match March_modules.Module_registry.find_stdlib_file mod_name with
      | None -> ()
      | Some path ->
        let decls = load_stdlib_file path in
        March_eval.Eval.eval_stdlib_decls decls
    );
    (if !debug_mode || !debug_tui_mode then begin
      let ctx = March_debug.Debug.make_debug_ctx
        ~on_dbg:(fun env ->
          March_debug.Debug_repl.run_session
            (Option.get !March_eval.Eval.debug_ctx) env)
      in
      March_debug.Debug.install ctx;
      Printf.eprintf "[debug] Trace recording enabled (buffer: %d frames)\n%!"
        ctx.March_eval.Eval.dc_trace.March_eval.Eval.rb_cap
    end);
    let print_march_backtrace () =
      let all = March_eval.Eval.get_march_stack () in
      let show_full = Sys.getenv_opt "MARCH_BACKTRACE" = Some "full" in
      (* Canonical stdlib prefix from the same resolver that load_stdlib uses.
         When it matches, no false positives.  When it doesn't match (e.g. the
         stdlib AST was cached from a different build dir), fall back to checking
         that the immediate parent directory is literally named "stdlib" — correct
         for all stdlib paths, both relative and absolute. *)
      let stdlib_prefix_opt =
        match find_stdlib_dir () with
        | None -> None
        | Some p -> Some (p ^ "/")
      in
      let is_stdlib path =
        (match stdlib_prefix_opt with
         | Some prefix when String.starts_with ~prefix path -> true
         | _ -> false)
        || Filename.basename (Filename.dirname path) = "stdlib"
      in
      (* Desugarer-generated EApp nodes use dummy_span (file="<none>", line=0). *)
      let non_synthetic = List.filter (fun f ->
        f.March_eval.Eval.mf_file <> "<none>" && f.March_eval.Eval.mf_line > 0) all
      in
      let frames =
        if show_full then non_synthetic
        else List.filter (fun f -> not (is_stdlib f.March_eval.Eval.mf_file)) non_synthetic
      in
      (* Add "()" to plain identifiers so "panic  file:3" reads as a call site,
         not a definition site.  Operators and <anon> are left as-is. *)
      let display_name name =
        if name = "" || name.[0] = '<' then name
        else
          let is_op_char = function
            | '+' | '-' | '*' | '/' | '=' | '<' | '>' | '!'
            | '&' | '|' | '^' | '~' | '%' -> true
            | _ -> false
          in
          if String.for_all is_op_char name then name
          else name ^ "()"
      in
      if frames <> [] then begin
        Printf.eprintf "\nStack trace (most recent call first):\n";
        List.iteri (fun i f ->
          Printf.eprintf "  [%d] %-24s %s:%d\n"
            i (display_name f.March_eval.Eval.mf_name)
            f.March_eval.Eval.mf_file
            f.March_eval.Eval.mf_line
        ) frames;
        if not show_full then
          Printf.eprintf "\nnote: set MARCH_BACKTRACE=full for all frames including stdlib\n"
      end
    in
    March_eval.Eval.clear_march_stack ();
    (* Interpreter FFI (Phase 4): provide the runtime .so so extern calls can be
       resolved dynamically.  Lazy — only built if the program actually calls an
       extern at runtime. *)
    March_eval.Eval.ffi_runtime_so := (fun () -> Some (ensure_runtime_so ()));
    (* Gap 1: if ffi_c_files are present (from --ffi-c or forge.toml [ffi]),
       compile them into a temp .so and tell the interpreter to dlopen it.
       An explicit --ffi-so path (set above) takes precedence.
       Hash = sum of source paths and their content for cache invalidation. *)
    (match !March_eval.Eval.ffi_shim_so with
     | Some _ -> ()  (* already set explicitly via --ffi-so *)
     | None when !ffi_c_files = [] -> ()  (* no shim sources *)
     | None ->
       (* Build a content-addressed temp path for the shim .so *)
       let home = (try Sys.getenv "HOME" with Not_found -> ".") in
       let cache_dir = Filename.concat home ".cache/march" in
       (try Unix.mkdir cache_dir 0o755
        with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
       let key_buf = Buffer.create 256 in
       List.iter (fun f ->
         Buffer.add_string key_buf f;
         (try Buffer.add_string key_buf (Digest.to_hex (Digest.file f)) with _ -> ()))
         (List.rev !ffi_c_files);
       let key = String.sub (Digest.to_hex (Digest.string (Buffer.contents key_buf))) 0 16 in
       let so_path = Filename.concat cache_dir ("march_ffi_shim_" ^ key ^ ".so") in
       if not (Sys.file_exists so_path) then begin
         (* Find the runtime dir for the -I flag (march_ffi.h lives there) *)
         let runtime_dir_opt =
           let candidates = [
             "runtime/march_runtime.c";
             Filename.concat (Filename.dirname Sys.executable_name) "../runtime/march_runtime.c";
             Filename.concat (Filename.dirname Sys.executable_name) "../../runtime/march_runtime.c";
           ] in
           match List.find_opt Sys.file_exists candidates with
           | Some p -> Some (Filename.dirname p)
           | None -> None
         in
         let inc_flag = match runtime_dir_opt with
           | Some d -> Printf.sprintf " -I%s" (Filename.quote d)
           | None -> ""
         in
         let src_files = String.concat " "
           (List.rev_map Filename.quote !ffi_c_files) in
         let tmp = Printf.sprintf "%s.%d.tmp" so_path (Unix.getpid ()) in
         (* On macOS, shim symbols reference runtime functions (e.g. march_str_borrow)
            that are not available at .so link time — they'll be resolved at dlopen
            time via RTLD_GLOBAL.  Pass -undefined dynamic_lookup on Darwin. *)
         let platform_flags =
           match Sys.getenv_opt "MARCH_FFI_SHIM_LDFLAGS" with
           | Some f -> " " ^ f   (* explicit override *)
           | None ->
             (* Detect macOS via the existence of /System/Library/CoreServices *)
             if Sys.file_exists "/System/Library/CoreServices"
             then " -undefined dynamic_lookup"
             else ""
         in
         let cmd = Printf.sprintf
           "cc -shared -O2 -fPIC%s%s %s -o %s 2>&1"
           platform_flags inc_flag src_files tmp in
         let rc = Sys.command cmd in
         if rc <> 0 then
           Printf.eprintf "march: warning: failed to compile FFI shim sources \
                           to .so (exit %d) — interpreter will not find shim symbols\n" rc
         else begin
           (try Sys.rename tmp so_path
            with Sys_error _ ->
              (try Sys.remove tmp with Sys_error _ -> ()))
         end
       end;
       if Sys.file_exists so_path then
         March_eval.Eval.ffi_shim_so := Some so_path);
    (try March_eval.Eval.run_module desugared
     with
     | March_eval.Eval.Eval_error msg ->
       (* panic_/todo_/unreachable_ builtins already prefix their messages with
          "panic: " / "todo: " / "unreachable: " — print as-is. *)
       Printf.eprintf "%s\n" msg;
       print_march_backtrace ();
       exit 1
     | March_eval.Eval.Match_failure msg ->
       Printf.eprintf "panic: match failure — %s\n" msg;
       print_march_backtrace ();
       exit 1
     | March_eval.Eval.Assert_failure msg ->
       Printf.eprintf "panic: %s\n" msg;
       print_march_backtrace ();
       exit 1
     | Unix.Unix_error (Unix.EINTR, syscall, _) ->
       (* SIGINT interrupted a blocking syscall (accept/select/recv) —
          print nothing if shutdown was requested, otherwise show the call *)
       if not !March_eval.Eval.shutdown_requested then
         Printf.eprintf "%s: interrupted syscall: %s\n" filename syscall;
       exit 0);
    March_debug.Debug.uninstall ()
  end

(** Type-check multiple .march files together.
    Parses each file, collects all their declarations, and type-checks the
    combined module.  Exits 0 on success, 1 if any errors are found.
    Used by [forge build] for library projects. *)
let run_check_cmd files =
  if files = [] then begin
    Printf.eprintf "march check: no files specified\n"; exit 1
  end;
  let stdlib_decls = load_stdlib ~for_js:(parse_target !target_str = March_tir.Llvm_emit.Js) () in
  (* Files pulled in by import resolution (source dir / MARCH_LIB_PATH) are
     user code too: diagnostics pointing into them must be fatal even though
     they were not listed on the command line. *)
  let import_user_files = ref [] in
  (* Parse and desugar each file; collect all declarations *)
  let all_decls = List.concat_map (fun filename ->
    let src =
      try read_file filename
      with Sys_error msg ->
        Printf.eprintf "march: %s\n" msg; exit 1
    in
    let lexbuf = Lexing.from_string src in
    lexbuf.Lexing.lex_curr_p <-
      { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
    let module_ast =
      try March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf
      with
      | March_errors.Errors.ParseError (msg, hint, _) ->
        Printf.eprintf "%s\n"
          (March_errors.Errors.render_parse_error ~src ~filename ?hint ~msg lexbuf);
        exit 1
      | March_parser.Parser.Error ->
        Printf.eprintf "%s\n"
          (March_errors.Errors.render_parse_error ~src ~filename
             ~msg:"I got stuck here:" lexbuf);
        exit 1
    in
    let desugared = March_desugar.Desugar.desugar_module module_ast in
    let (_resolve_errors, extra_decls, user_files) = resolve_imports ~source_file:filename desugared in
    import_user_files := user_files @ !import_user_files;
    let desugared =
      { desugared with
        March_ast.Ast.mod_decls = extra_decls @ desugared.March_ast.Ast.mod_decls }
    in
    (* Wrap each user file in a DMod so its names are accessible as Module.name,
       mirroring what load_stdlib_file does for stdlib modules. *)
    [March_ast.Ast.DMod (desugared.March_ast.Ast.mod_name,
                         March_ast.Ast.Public,
                         desugared.March_ast.Ast.mod_decls,
                         March_ast.Ast.dummy_span)]
  ) files in
  (* Build a synthetic combined module and type-check it *)
  let dummy_span = March_ast.Ast.{
    file = ""; start_line = 0; start_col = 0; end_line = 0; end_col = 0
  } in
  let combined = {
    March_ast.Ast.mod_name = { March_ast.Ast.txt = "LibCheck"; span = dummy_span };
    March_ast.Ast.mod_decls = stdlib_decls @ all_decls;
  } in
  let (errors, _type_map) = March_typecheck.Typecheck.check_module combined in
  let diags = March_errors.Errors.sorted errors in
  let lib_files =
    List.sort_uniq String.compare (files @ !import_user_files) in
  let is_user_file (d : March_errors.Errors.diagnostic) =
    List.mem d.span.March_ast.Ast.file lib_files ||
    d.span.March_ast.Ast.file = "" ||
    d.span.March_ast.Ast.file = "<unknown>"
  in
  let user_errors = List.filter (fun d ->
    is_user_file d &&
    d.March_errors.Errors.severity = March_errors.Errors.Error
  ) diags in
  List.iter (fun (d : March_errors.Errors.diagnostic) ->
    Printf.eprintf "%s:%d:%d: error: %s\n"
      d.span.March_ast.Ast.file
      d.span.March_ast.Ast.start_line
      d.span.March_ast.Ast.start_col
      d.message
  ) user_errors;
  if user_errors <> [] then exit 1
  else exit 0

(* ── Phase 10: GC trace analyser ────────────────────────────────────── *)
(*
 * Reads a gc.jsonl file produced by MARCH_TRACE_GC=1 and reports:
 *   - leaked objects   (alloc'd but never freed at program end)
 *   - double frees     (free event for an already-freed address)
 *   - negative RCs     (dec_ref whose post-decrement RC < 0)
 *)
let analyze_gc_trace path =
  let ic = try open_in path
           with Sys_error _ ->
             Printf.eprintf "march analyze-trace: cannot open '%s'\n" path;
             exit 1
  in
  (* Minimal JSON field scanner — pure OCaml, no external deps.
     Handles "key":"string_val" and "key":number_val forms. *)
  let str_find haystack needle from =
    let hl = String.length haystack and nl = String.length needle in
    let r = ref (-1) and i = ref from in
    while !i <= hl - nl && !r < 0 do
      if String.sub haystack !i nl = needle then r := !i else incr i
    done; !r
  in
  let get_field json key =
    let ps = "\"" ^ key ^ "\":\"" in
    let pn = "\"" ^ key ^ "\":" in
    let i  = str_find json ps 0 in
    if i >= 0 then
      let s = i + String.length ps in
      (match String.index_from_opt json s '"' with
       | Some e -> Some (String.sub json s (e - s))
       | None   -> None)
    else
      let j = str_find json pn 0 in
      if j >= 0 then
        let s = j + String.length pn in
        let e = ref s in
        while !e < String.length json &&
              (let c = json.[!e] in (c >= '0' && c <= '9') || c = '-') do
          incr e
        done;
        if !e > s then Some (String.sub json s (!e - s)) else None
      else None
  in
  let live  : (string, int * int) Hashtbl.t = Hashtbl.create 4096 in
  let freed : (string, bool)      Hashtbl.t = Hashtbl.create 1024 in
  let n_alloc = ref 0 and n_free = ref 0 and n_inc = ref 0 and n_dec = ref 0 in
  let n_double = ref 0 and n_neg = ref 0 and lno = ref 0 in
  (try while true do
    let line = String.trim (input_line ic) in
    incr lno;
    if line <> "" then begin
      let ev   = Option.value ~default:"" (get_field line "event") in
      let addr = Option.value ~default:"" (get_field line "addr")  in
      let rc   = Option.fold  ~none:0 ~some:int_of_string (get_field line "rc") in
      match ev with
      | "alloc" ->
        incr n_alloc;
        Hashtbl.replace live addr (rc, !lno);
        Hashtbl.remove freed addr
      | "free" ->
        incr n_free;
        if Hashtbl.mem freed addr then incr n_double
        else begin Hashtbl.remove live addr; Hashtbl.replace freed addr true end
      | "inc_ref" ->
        incr n_inc;
        (match Hashtbl.find_opt live addr with
         | Some (_, eno) -> Hashtbl.replace live addr (rc, eno)
         | None -> ())
      | "dec_ref" ->
        incr n_dec;
        (match Hashtbl.find_opt live addr with
         | Some (_, eno) ->
           if rc < 0 then incr n_neg;
           Hashtbl.replace live addr (rc, eno)
         | None -> ())
      | _ -> ()
    end
  done with End_of_file -> ());
  close_in ic;
  let n_leaked = Hashtbl.length live in
  Printf.printf "March GC Trace Analysis: %s\n" path;
  Printf.printf "  events        : alloc=%d  free=%d  inc_ref=%d  dec_ref=%d\n"
    !n_alloc !n_free !n_inc !n_dec;
  Printf.printf "  leaked objects: %d\n" n_leaked;
  Printf.printf "  double frees  : %d\n" !n_double;
  Printf.printf "  negative RCs  : %d\n" !n_neg;
  let ok = n_leaked = 0 && !n_double = 0 && !n_neg = 0 in
  if ok then print_string "  result: OK\n"
  else begin
    if n_leaked > 0 then begin
      Printf.eprintf "error: %d leaked object(s)\n" n_leaked;
      let shown = ref 0 in
      Hashtbl.iter (fun addr (rc, eno) ->
        if !shown < 10 then begin
          Printf.eprintf "  leak: addr=%-18s rc=%-3d (alloc at event #%d)\n" addr rc eno;
          incr shown
        end
      ) live;
      if n_leaked > 10 then
        Printf.eprintf "  … and %d more\n" (n_leaked - 10)
    end;
    if !n_double > 0 then
      Printf.eprintf "error: %d double-free(s)\n" !n_double;
    if !n_neg   > 0 then
      Printf.eprintf "error: %d negative reference count(s)\n" !n_neg
  end;
  exit (if ok then 0 else 1)

let () =
  (* Colour — priority: MARCH_COLOR env > NO_COLOR env > TERM=dumb > isatty. *)
  March_errors.Errors.use_color := (
    match Sys.getenv_opt "MARCH_COLOR" with
    | Some "always" -> true
    | Some "never"  -> false
    | _ ->
      Sys.getenv_opt "NO_COLOR" = None
      && Sys.getenv_opt "TERM" <> Some "dumb"
      && Unix.isatty Unix.stderr
  )

let () =
  (* Handle subcommands before Arg.parse *)
  let argv = Sys.argv in
  if Array.length argv >= 2 && (argv.(1) = "--version" || argv.(1) = "-version") then begin
    (* Keep in sync with the (version ...) field in dune-project. *)
    print_string "march 0.1.0\n";
    exit 0
  end;
  if Array.length argv >= 2 && argv.(1) = "fmt" then begin
    let rest = Array.to_list (Array.sub argv 2 (Array.length argv - 2)) in
    run_fmt rest
  end;
  if Array.length argv >= 2 && argv.(1) = "check" then begin
    let rest = Array.to_list (Array.sub argv 2 (Array.length argv - 2)) in
    run_check_cmd rest
  end;
  if Array.length argv >= 2 && argv.(1) = "test" then begin
    let rest = Array.to_list (Array.sub argv 2 (Array.length argv - 2)) in
    run_test_cmd rest
  end;
  (* Phase 10: GC trace validator — see analyze_gc_trace below. *)
  if Array.length argv >= 2 && argv.(1) = "analyze-trace" then begin
    let path = if Array.length argv >= 3 then argv.(2) else "trace/gc/gc.jsonl" in
    analyze_gc_trace path
  end;
  if Array.length argv >= 2 && argv.(1) = "warm-cache" then begin
    let t0 = Unix.gettimeofday () in
    (* 1. Parse + desugar stdlib (populates AST cache) *)
    let stdlib_decls = load_stdlib () in
    let t1 = Unix.gettimeofday () in
    Printf.printf "stdlib AST:      %.3fs\n%!" (t1 -. t0);
    (* 2. Typecheck stdlib (populates TC env cache) *)
    let type_map = Hashtbl.create 64 in
    let base_tc = March_typecheck.Typecheck.base_env
      (March_errors.Errors.create ()) type_map in
    let tc_pre = March_repl.Repl.preregister_stdlib_types base_tc stdlib_decls in
    let content_hash = March_repl.Repl.stdlib_content_hash stdlib_decls in
    (match March_repl.Repl.load_cached_tc_env ~content_hash ~type_map with
     | Some _ ->
       let t2 = Unix.gettimeofday () in
       Printf.printf "tc_env:          %.3fs (cached)\n%!" (t2 -. t1)
     | None ->
       let (_e0, tc0) = March_repl.Repl.load_decls_into_env
         March_eval.Eval.base_env tc_pre stdlib_decls in
       March_repl.Repl.save_cached_tc_env ~content_hash tc0;
       let t2 = Unix.gettimeofday () in
       Printf.printf "tc_env:          %.3fs (built + cached)\n%!" (t2 -. t1));
    (* 3. Compile C runtime .so *)
    let t3 = Unix.gettimeofday () in
    let runtime_so = ensure_runtime_so () in
    let t4 = Unix.gettimeofday () in
    Printf.printf "runtime .so:     %.3fs\n%!" (t4 -. t3);
    (* 4. Precompile stdlib .so *)
    let jit_ctx = March_jit.Repl_jit.create ~runtime_so () in
    March_repl.Repl.maybe_precompile_stdlib (Some jit_ctx) ~stdlib_decls ~type_map;
    March_jit.Repl_jit.cleanup jit_ctx;
    let t5 = Unix.gettimeofday () in
    Printf.printf "stdlib .so:      %.3fs\n%!" (t5 -. t4);
    Printf.printf "total:           %.3fs\n%!" (t5 -. t0);
    exit 0
  end;
  if Array.length argv >= 2 && argv.(1) = "repl" then begin
    let preload_file = if Array.length argv >= 3 then Some argv.(2) else None in
    let runtime_so = ensure_runtime_so () in
    let jit_ctx = March_jit.Repl_jit.create ~runtime_so () in
    Fun.protect
      ~finally:(fun () -> March_jit.Repl_jit.cleanup jit_ctx)
      (fun () ->
        March_repl.Repl.run ~stdlib_decls:(load_stdlib ())
          ~jit_ctx:(Some jit_ctx) ~preload_file ());
    exit 0
  end;
  if Array.length argv >= 2 && argv.(1) = "dap" then begin
    (* Debug Adapter Protocol server (editor debugger).
       The program to debug is supplied by the editor via the DAP `launch`
       request, not on the command line. We run it through the interpreter
       under a debug context driven by the DAP session. *)

    (* Build a runnable for a source path: parse → desugar → prepend stdlib →
       run_module (the same shape as the interpreter run path). The session
       installs the debug context; this thunk must not install its own. *)
    let make_program path () =
      let src =
        let ic = open_in path in
        let n = in_channel_length ic in
        let b = Bytes.create n in
        really_input ic b 0 n; close_in ic; Bytes.to_string b
      in
      let lexbuf = Lexing.from_string src in
      lexbuf.Lexing.lex_curr_p <-
        { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = path };
      let module_ast =
        March_parser.Parser.module_
          (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
      let desugared = March_desugar.Desugar.desugar_module module_ast in
      let stdlib_decls = load_stdlib () in
      let combined =
        { desugared with
          March_ast.Ast.mod_decls = stdlib_decls @ desugared.March_ast.Ast.mod_decls } in
      March_eval.Eval.module_loader := Some (fun mod_name ->
        match March_modules.Module_registry.find_stdlib_file mod_name with
        | None -> ()
        | Some p -> March_eval.Eval.eval_stdlib_decls (load_stdlib_file p));
      March_eval.Eval.clear_march_stack ();
      March_eval.Eval.run_module combined
    in

    (* Take over fd 1 for the DAP protocol: keep the original stdout for framed
       DAP messages and redirect the program's own stdout to a pipe that we
       forward as DAP `output` events. *)
    let real_out_fd = Unix.dup Unix.stdout in
    let real_oc = Unix.out_channel_of_descr real_out_fd in
    let (pipe_r, pipe_w) = Unix.pipe () in
    Unix.dup2 pipe_w Unix.stdout;
    Unix.close pipe_w;
    set_binary_mode_in stdin true;

    let session =
      March_dap.Dap_session.create ~ic:stdin ~oc:real_oc ~make_program in
    let _reader =
      Thread.create (fun () ->
          let buf = Bytes.create 4096 in
          let rec loop () =
            match Unix.read pipe_r buf 0 4096 with
            | 0 -> ()
            | n ->
              March_dap.Dap_session.send_output session
                ~category:"stdout" (Bytes.sub_string buf 0 n);
              loop ()
            | exception _ -> ()
          in loop ()) ()
    in
    March_dap.Dap_session.serve session;
    exit 0
  end;
  let files = ref [] in
  let specs = [
    ("--dump-tir",     Arg.Set dump_tir,     " Print TIR instead of evaluating");
    ("--dump-phases",  Arg.Set dump_phases,  " Serialize each IR stage to march-phases/phases.json");
    ("--timings",      Arg.Set do_timings,   " Print per-stage compilation times to stderr");
    ("--emit-llvm",  Arg.Set emit_llvm,   " Emit LLVM IR to <file>.ll");
    ("--compile",    Arg.Set do_compile,  " Compile to native binary via clang");
    ("--compile-so", Arg.Set compile_so,
     " Compile as a shared library for hot reload patching (no @main, no dispatch init)");
    ("--hot-reload", Arg.String (fun p -> hot_reload_prefix := Some p),
     "<Prefix> Compile modules under <Prefix> with the hot-reload dispatch table");
    ("--signing-pubkey", Arg.Set_string signing_pubkey,
     "<base64>  ed25519 public key to embed for ACTIVATE signature verification (with --hot-reload)");
    ("--ffi-c",      Arg.String (fun f -> ffi_c_files := f :: !ffi_c_files),
                     "<file.c>  Compile+link an FFI shim C source (forge [[ffi]]); repeatable");
    ("--ffi-link",   Arg.String (fun f -> ffi_link_flags := f :: !ffi_link_flags),
                     "<flag>  Extra linker flag for FFI (e.g. -lz); repeatable");
    ("--ffi-so",     Arg.String (fun p -> March_eval.Eval.ffi_shim_so := Some p),
                     "<path.so>  Pre-compiled FFI shim .so to dlopen in interpreter mode");
    ("--check",      Arg.Set do_check,    " Typecheck only — parse, resolve imports, typecheck, then exit (no codegen or eval)");
    ("--check-json", Arg.Set check_json,  " Emit diagnostics as NDJSON to stdout (for tooling such as forge fix)");
    ("--no-measure-axioms", Arg.Clear measure_axioms, " Reflect @[measure] functions symbolically instead of axiomatising them (skips datatype/quantifier reasoning and the soundness gate)");
    ("--test",       Arg.Set do_test,     " Compile test blocks into a standalone test-runner binary (use with --compile)");
    ("--target",     Arg.Set_string target_str,  "<target>  Compilation target: native, wasm64-wasi, wasm32-wasi, wasm32-unknown-unknown");
    ("-o",           Arg.Set_string output_file, "<file>  Output binary name (with --compile)");
    ("--no-opt",    Arg.Clear opt_enabled,  " Skip TIR optimization passes");
    ("--fast-math",  Arg.Set fast_math,  " Emit 'fast' on all FP LLVM instructions");
    ("--pmap-threshold", Arg.Set_int pmap_threshold, "<N>  List.pmap/pfilter/preduce fall back to sequential below N elements (default 1024)");
    ("--opt",        Arg.Set_int opt_level, "<N>  Optimization level passed to clang (0-3)");
    ("--debug",     Arg.Set debug_mode,     " Enable time-travel debugger (simple mode)");
    ("--debug-tui", Arg.Set debug_tui_mode, " Enable time-travel debugger (TUI mode)");
    ("--fmt",       Arg.Set do_fmt,         " Format source file in-place before compiling");
    ("--no-copy-runtime", Arg.Set no_copy_runtime, " (JS) Skip auto-copy of march_runtime.mjs / march_dom.mjs (for build tools that manage them)");
  ] in
  Arg.parse specs (fun f -> files := f :: !files) "Usage: march [options] [file.march]";
  (* --target js implies --compile (skip JIT, emit .mjs) *)
  if !target_str = "js" || !target_str = "javascript" then do_compile := true;
  (* Propagate --pmap-threshold to the interpreter (codegen reads it via
     emit_module's ~pmap_threshold argument below). *)
  March_eval.Eval.pmap_threshold_value := !pmap_threshold;
  match !files with
  | []  ->
    let runtime_so = ensure_runtime_so () in
    let jit_ctx = March_jit.Repl_jit.create ~runtime_so () in
    Fun.protect
      ~finally:(fun () -> March_jit.Repl_jit.cleanup jit_ctx)
      (fun () ->
        March_repl.Repl.run ~stdlib_decls:(load_stdlib ()) ~jit_ctx:(Some jit_ctx) ())
  | [f] -> compile f
  | _   -> Printf.eprintf "Usage: march [options] [file.march]\n"; exit 1
