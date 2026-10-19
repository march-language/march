(* `march --compile --static`: what it links and how it proves the result
   (static-output design, decisions D4/D5, approved 2026-10-18:
   specs/2026-09-23-static-compile-output-design.md §5).

   - Linux: musl only.  A static glibc link "works" but leaves NSS (anything
     beyond files/dns), iconv and dlopen depending on the host again, so a
     glibc host is refused, with the Alpine route named.  The link is
     `-static` with the archive (lib<name>.a) of every library the program
     reaches.
   - macOS: "self-contained".  A fully static Mach-O executable is not
     supported (libSystem is always dynamic), so the mode means: no load
     command outside /usr/lib and /System.  OpenSSL, zstd and brotli link from
     Homebrew's archives; zlib is the system's /usr/lib/libz.

   Which libraries: those of the runtime members the emitted code reaches
   ([reached], from Llvm_builtins.called_c_symbols), so a program that never
   uses TLS needs no libssl.a.  A reached library whose archive cannot be
   found is an error naming the package, before the link, never a wall of
   linker output (the todo's acceptance item 3).

   After the link, [verify] reads the binary itself and refuses anything
   outside the allowed set, so "silently still dynamic" cannot ship (the
   todo's Non-acceptance). *)

type lib = { name : string; (* lib<name>.a / -l<name> *) }

(* Which runtime members the program reaches, by the C symbols it calls. *)
type reach = { tls : bool; zlib : bool; zstd : bool; brotli : bool }

let reached (called : string list) : reach =
  let uses prefix = List.exists (fun s ->
      String.length s >= String.length prefix
      && String.sub s 0 (String.length prefix) = prefix) called in
  { tls = uses "march_tls_";
    zlib = uses "march_gzip_" || uses "march_deflate_";
    zstd = uses "march_zstd_";
    brotli = uses "march_brotli_" }

let everything = { tls = true; zlib = true; zstd = true; brotli = true }

(* The libraries a reach needs, in link order, each with the module that
   reached it and the package that provides its archive per platform. *)
let libs_of (r : reach) : (string * string * string) list =
  (* (lib name, who reached it, which feature) *)
  (if r.tls then [ ("ssl", "TLS", "openssl"); ("crypto", "TLS", "openssl") ] else [])
  @ (if r.zstd then [ ("zstd", "Compress.Zstd", "zstd") ] else [])
  @ (if r.brotli then [ ("brotlienc", "Compress.Brotli", "brotli");
                        ("brotlidec", "Compress.Brotli", "brotli");
                        ("brotlicommon", "Compress.Brotli", "brotli") ] else [])
  @ (if r.zlib then [ ("z", "Compress.Gzip/Deflate", "zlib") ] else [])

let alpine_package = function
  | "openssl" -> "openssl-libs-static"
  | "zstd" -> "zstd-static"
  | "brotli" -> "brotli-static"
  | "zlib" -> "zlib-static"
  | "ucontext" -> "libucontext-dev"
  | p -> p

let brew_formula = function
  | "openssl" -> "openssl@3"
  | p -> p

(* MARCH_TEST_LIBPROBE_ROOT (the driver's probe test hook, bin/main.ml):
   prefix every archive search directory with it, so a test can make an
   archive missing without touching the host. *)
let test_root = Sys.getenv_opt "MARCH_TEST_LIBPROBE_ROOT"

let first_existing dirs file =
  List.find_map (fun d ->
      let d = match test_root with Some r -> r ^ d | None -> d in
      let p = Filename.concat d file in
      if Sys.file_exists p then Some p else None) dirs

(* The -L directories named in a probe's flags, then the usual places. *)
let lib_dirs_of_flags (flags : string) : string list =
  String.split_on_char ' ' flags
  |> List.filter_map (fun t ->
      if String.length t > 2 && String.sub t 0 2 = "-L"
      then Some (String.sub t 2 (String.length t - 2)) else None)

let fail_missing (missing : (string * string * string) list) ~(macos : bool) =
  List.iter (fun (name, who, pkg) ->
      if macos then
        Printf.eprintf "march: --static: %s is used, but lib%s.a was not found (brew install %s)\n"
          who name (brew_formula pkg)
      else
        Printf.eprintf "march: --static: %s is used, but lib%s.a was not found (apk add %s)\n"
          who name (alpine_package pkg))
    (List.sort_uniq compare missing);
  exit 1

(* macOS: the archive paths (or, for zlib, the system dylib) to link for
   [r], given the dynamic probes' flags for their -L directories. *)
let macos_link_args ~(r : reach) ~(openssl_flags : string) ~(zstd_flags : string)
    ~(brotli_flags : string) : string =
  let homebrew = [ "/opt/homebrew/lib"; "/usr/local/lib" ] in
  let dirs_for = function
    | "ssl" | "crypto" ->
      lib_dirs_of_flags openssl_flags
      @ [ "/opt/homebrew/opt/openssl@3/lib"; "/usr/local/opt/openssl@3/lib" ] @ homebrew
    | "zstd" -> lib_dirs_of_flags zstd_flags @ [ "/opt/homebrew/opt/zstd/lib" ] @ homebrew
    | _ -> lib_dirs_of_flags brotli_flags @ [ "/opt/homebrew/opt/brotli/lib" ] @ homebrew in
  let wanted = libs_of r in
  let resolved, missing =
    List.fold_left (fun (ok, miss) ((name, _, _) as l) ->
        if name = "z" then (ok @ [ " -lz" ], miss)   (* /usr/lib/libz: a system dylib *)
        else match first_existing (dirs_for name) ("lib" ^ name ^ ".a") with
          | Some p -> (ok @ [ " " ^ Filename.quote p ], miss)
          | None -> (ok, miss @ [ l ]))
      ([], []) wanted in
  if missing <> [] then fail_missing missing ~macos:true;
  String.concat "" resolved

(* musl Linux: -l<name> for every reached library, each checked to have its
   archive, plus libucontext's (the scheduler's green threads). *)
let musl_link_args ~(r : reach) : string =
  let dirs = [ "/usr/lib"; "/lib"; "/usr/local/lib" ] in
  let wanted = libs_of r @ [ ("ucontext", "the scheduler", "ucontext") ] in
  let missing = List.filter (fun (name, _, _) ->
      first_existing dirs ("lib" ^ name ^ ".a") = None) wanted in
  if missing <> [] then fail_missing missing ~macos:false;
  " -static" ^ String.concat "" (List.map (fun (n, _, _) -> " -l" ^ n) wanted)

(* ── Post-link self-check ─────────────────────────────────────────────── *)

(* ELF: refuse a program interpreter (PT_INTERP) or any DT_NEEDED.  Read in
   OCaml rather than through readelf, which a minimal build host may lack.
   64-bit little-endian only (every Linux target March builds); anything
   else is reported, not passed. *)
let elf_problems (path : string) : string list =
  let s = try In_channel.with_open_bin path In_channel.input_all with Sys_error e -> "" ^ e in
  let n = String.length s in
  if n < 64 || String.sub s 0 4 <> "\x7fELF" then [ "not an ELF file" ]
  else if s.[4] <> '\002' || s.[5] <> '\001' then [ "not a 64-bit little-endian ELF" ]
  else begin
    let u16 o = Char.code s.[o] lor (Char.code s.[o + 1] lsl 8) in
    let u32 o = u16 o lor (u16 (o + 2) lsl 16) in
    let u64 o = u32 o lor (u32 (o + 4) lsl 32) in
    let phoff = u64 0x20 and phentsize = u16 0x36 and phnum = u16 0x38 in
    let problems = ref [] in
    for i = 0 to phnum - 1 do
      let ph = phoff + (i * phentsize) in
      if ph + 40 <= n then begin
        let ptype = u32 ph in
        if ptype = 3 then problems := "has a program interpreter (PT_INTERP)" :: !problems
        else if ptype = 2 then begin
          let off = u64 (ph + 8) and sz = u64 (ph + 32) in
          let needed = ref 0 in
          let rec scan o =
            if o + 16 <= n && o + 16 <= off + sz then begin
              let tag = u64 o in
              if tag = 0 then ()
              else begin
                if tag = 1 then incr needed;
                scan (o + 16)
              end
            end in
          scan off;
          if !needed > 0 then
            problems := Printf.sprintf "needs %d shared librar%s (DT_NEEDED)"
                !needed (if !needed = 1 then "y" else "ies") :: !problems
        end
      end
    done;
    List.rev !problems
  end

(* Mach-O: every load command must be under /usr/lib or /System. *)
let macho_problems (path : string) : string list =
  let ic = Unix.open_process_in (Printf.sprintf "otool -L %s 2>/dev/null" (Filename.quote path)) in
  let rec lines acc = match input_line ic with
    | l -> lines (l :: acc) | exception End_of_file -> List.rev acc in
  let ls = (match lines [] with _ :: rest -> rest | [] -> []) in
  ignore (Unix.close_process_in ic);
  List.filter_map (fun l ->
      let l = String.trim l in
      let p = match String.index_opt l ' ' with Some i -> String.sub l 0 i | None -> l in
      let ok pre = String.length p >= String.length pre && String.sub p 0 (String.length pre) = pre in
      if p = "" || ok "/usr/lib/" || ok "/System/" then None
      else Some ("loads " ^ p)) ls

(* Refuse [out] (and delete it) unless it is self-contained. *)
let verify ~(macos : bool) (out : string) : unit =
  let problems = if macos then macho_problems out else elf_problems out in
  if problems <> [] then begin
    Printf.eprintf "march: --static: %s is not self-contained:\n" out;
    List.iter (fun p -> Printf.eprintf "  %s\n" p) problems;
    (try Sys.remove out with Sys_error _ -> ());
    exit 1
  end

(* Does the C compiler target musl?  Asked of the compiler (its target
   triple, e.g. x86_64-alpine-linux-musl vs x86_64-pc-linux-gnu), not of
   the filesystem: a glibc host can have a musl loader installed
   (/lib/ld-musl-*, from musl-tools), which Toolchain.is_musl_host takes for
   a musl host; CI's Ubuntu runners do. *)
let cc_targets_musl (cc : string) : bool =
  try
    let ic = Unix.open_process_in (cc ^ " -dumpmachine 2>/dev/null") in
    let l = try input_line ic with End_of_file -> "" in
    ignore (Unix.close_process_in ic);
    let n = String.length l in
    let rec has i = i + 4 <= n && (String.sub l i 4 = "musl" || has (i + 1)) in
    has 0
  with _ -> false

(* Refusals that need nothing but the flags and the host. *)
let check_supported ~(hot_reload : bool) ~(compile_so : bool) ~(cross : bool)
    ~(macos : bool) ~(musl : bool) : unit =
  let refuse msg = Printf.eprintf "march: --static: %s\n" msg; exit 1 in
  if hot_reload then refuse "a --hot-reload build loads patches with dlopen, which a static executable cannot do";
  if compile_so then refuse "--compile-so builds a shared object";
  if cross then refuse "--target is not supported with --static yet (a static musl cross target is planned: specs/2026-09-23-static-compile-output-design.md, Stage 5)";
  if not macos && not musl then
    refuse "on Linux, --static links against musl, and this host's C library is glibc. \
            Build on Alpine (apk add build-base openssl-libs-static zlib-static zstd-static \
            brotli-static libucontext-dev)."

(* A one-line reminder: a static binary that carries OpenSSL must ship its
   license (Apache-2.0) with it (design §8). *)
let openssl_notice (r : reach) =
  if r.tls then
    prerr_endline "march: note: this binary contains OpenSSL (Apache-2.0); distribute its license with it"
