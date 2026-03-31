module C = Configurator.V1

let () =
  C.main ~name:"blake3" (fun c ->
    let default =
      match C.ocaml_config_var c "system" with
      | Some "macosx" ->
        let prefix =
          if Sys.file_exists "/opt/homebrew/include/blake3.h" then "/opt/homebrew"
          else "/usr/local"
        in
        { C.Pkg_config.cflags = [ "-I" ^ prefix ^ "/include" ]
        ; libs = [ "-L" ^ prefix ^ "/lib"; "-lblake3" ]
        }
      | _ -> { C.Pkg_config.cflags = []; libs = [ "-lblake3" ] }
    in
    let conf =
      match C.Pkg_config.get c with
      | None -> default
      | Some pc ->
        (match C.Pkg_config.query pc ~package:"blake3" with
         | None -> default
         | Some deps -> deps)
    in
    C.Flags.write_sexp "blake3_cflags.sexp" conf.cflags;
    C.Flags.write_sexp "blake3_libs.sexp" conf.libs)
