module C = Configurator.V1

(* Generates link/compile flags for the zstd + brotli compression stubs.

   On macOS, prefer the static archives (libzstd.a, libbrotli{enc,dec,common}.a)
   when present so the binary carries no compression dylib dependency and runs
   on machines without Homebrew. Falls back to dynamic -l flags when an archive
   is absent. On other platforms, emit the plain dynamic flags (unchanged). *)
let () =
  C.main ~name:"compress" (fun c ->
    let is_macos = C.ocaml_config_var c "system" = Some "macosx" in
    let defines = [ "-DMARCH_HAVE_ZSTD"; "-DMARCH_HAVE_BROTLI" ] in
    if is_macos then begin
      let prefix =
        if Sys.file_exists "/opt/homebrew/include/zstd.h" then "/opt/homebrew"
        else "/usr/local"
      in
      let libdir = prefix ^ "/lib" in
      let archive name = libdir ^ "/lib" ^ name ^ ".a" in
      (* Use the static archive when present, else the dynamic -l form. *)
      let pick name = if Sys.file_exists (archive name) then [ archive name ] else [ "-l" ^ name ] in
      (* brotlienc/brotlidec depend on brotlicommon, so list common last. *)
      let common = if Sys.file_exists (archive "brotlicommon") then [ archive "brotlicommon" ] else [] in
      let libs =
        ("-L" ^ libdir) :: "-lz"
        :: (pick "zstd" @ pick "brotlienc" @ pick "brotlidec" @ common)
      in
      C.Flags.write_sexp "compress_cflags.sexp" (("-I" ^ prefix ^ "/include") :: defines);
      C.Flags.write_sexp "compress_libs.sexp" libs
    end else begin
      C.Flags.write_sexp "compress_cflags.sexp" defines;
      (* -lbrotlicommon, last, is load-bearing for a STATIC link and a no-op
         for a dynamic one.  libbrotlienc/libbrotlidec both call into
         libbrotlicommon (BrotliDefaultAllocFunc, _kBrotliPrefixCodeRanges,
         BrotliTransformDictionaryWord, ...); when they are shared objects the
         loader follows their own DT_NEEDED and pulls it in for us, which is
         why omitting it went unnoticed.  Against the .a archives there is no
         such chain and the link dies with ~30 undefined references.  The macOS
         branch above already lists common last for exactly this reason. *)
      C.Flags.write_sexp "compress_libs.sexp"
        [ "-lz"; "-lzstd"; "-lbrotlienc"; "-lbrotlidec"; "-lbrotlicommon" ]
    end)
