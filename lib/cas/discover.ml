module C = Configurator.V1

let () =
  C.main ~name:"blake3" (fun c ->
    let is_macos = C.ocaml_config_var c "system" = Some "macosx" in
    let macos_prefix () =
      if Sys.file_exists "/opt/homebrew/include/blake3.h" then "/opt/homebrew"
      else "/usr/local"
    in
    (* On macOS, prefer a static libblake3.a when one is present so the binary
       carries no blake3 dylib dependency (runs on machines without Homebrew).
       Falls back to dynamic -lblake3 otherwise (typical local dev). *)
    let static_macos =
      if is_macos then
        let prefix = macos_prefix () in
        let archive = prefix ^ "/lib/libblake3.a" in
        if Sys.file_exists archive then
          Some { C.Pkg_config.cflags = [ "-I" ^ prefix ^ "/include" ]; libs = [ archive ] }
        else None
      else None
    in
    let default =
      if is_macos then
        let prefix = macos_prefix () in
        { C.Pkg_config.cflags = [ "-I" ^ prefix ^ "/include" ]
        ; libs = [ "-L" ^ prefix ^ "/lib"; "-lblake3" ]
        }
      else { C.Pkg_config.cflags = []; libs = [ "-lblake3" ] }
    in
    let conf =
      match static_macos with
      | Some s -> s            (* static archive takes precedence on macOS *)
      | None ->
        (match C.Pkg_config.get c with
         | None -> default
         | Some pc ->
           (match C.Pkg_config.query pc ~package:"blake3" with
            | None -> default
            | Some deps -> deps))
    in
    C.Flags.write_sexp "blake3_cflags.sexp" conf.cflags;
    C.Flags.write_sexp "blake3_libs.sexp" conf.libs)
