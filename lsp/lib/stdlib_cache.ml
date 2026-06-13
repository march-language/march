(** Process-lifetime memo of parsed+desugared stdlib declarations.

    The stdlib is invariant across keystrokes; re-reading and re-parsing it
    per analyse (the previous behaviour) dominated LSP latency. We cache the
    decls in-process, keyed by a content hash of all stdlib *.march files plus
    the compiler identity (so a rebuilt compiler busts the cache) — the same
    invalidation discipline used by the CAS (March_cas.Cas.compiler_identity).

    [loader] and [stdlib_dir] are injected by Analysis (which owns the
    parse/desugar pipeline) to avoid a dependency cycle. *)

let cache : (string, March_ast.Ast.decl list) Hashtbl.t = Hashtbl.create 1

let loader : (unit -> March_ast.Ast.decl list) ref = ref (fun () -> [])
let set_loader f = loader := f

let stdlib_dir : (unit -> string option) ref = ref (fun () -> None)
let set_stdlib_dir f = stdlib_dir := f

(* Hash of (sorted filename + content) over every stdlib .march file. *)
let content_key (dir : string) : string =
  let files =
    try
      Sys.readdir dir |> Array.to_list
      |> List.filter (fun f -> Filename.check_suffix f ".march")
      |> List.sort String.compare
    with Sys_error _ -> []
  in
  let buf = Buffer.create (1 lsl 16) in
  List.iter (fun f ->
    Buffer.add_string buf f; Buffer.add_char buf '\x00';
    (try
       let ic = open_in_bin (Filename.concat dir f) in
       Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
         let n = in_channel_length ic in
         let b = Bytes.create n in
         really_input ic b 0 n;
         Buffer.add_bytes buf b)
     with _ -> ());
    Buffer.add_char buf '\x00'
  ) files;
  March_cas.Blake3.hash_string (Buffer.contents buf)

let load () : March_ast.Ast.decl list =
  match (!stdlib_dir) () with
  | None -> []
  | Some dir ->
    let key =
      content_key dir ^ "\x00" ^ Lazy.force March_cas.Cas.compiler_identity
    in
    (match Hashtbl.find_opt cache key with
     | Some decls -> decls
     | None ->
       let decls = (!loader) () in
       Hashtbl.replace cache key decls;
       decls)
