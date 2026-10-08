(* lib/jit/jit_emit.ml

   In-process object emission for shell fragments: parse IR, run LLVM's
   `default<O1>` pipeline and write a PIC object for a given triple, without
   spawning clang (jit_emit_stubs.c).  [Repl_jit.shell_compile] uses it and
   then runs only the linker; clang stays the fallback. *)

external available_c : string -> bool = "march_emit_available"
external emit_object_c : string -> string -> string -> string -> string
  = "march_emit_object"

(** The LLVM backend name and the CPU clang would pick for [triple]
    (`clang --target=<triple> -###` shows `-target-cpu`), or [None] for a
    triple this path does not handle (clang then compiles it). *)
let target_of_triple (triple : string) : (string * string) option =
  let starts p = String.length triple >= String.length p
                 && String.sub triple 0 (String.length p) = p in
  let has s =
    let n = String.length s and m = String.length triple in
    let rec go i = i + n <= m && (String.sub triple i n = s || go (i + 1)) in
    go 0 in
  let apple = has "apple" || has "darwin" in
  if starts "arm64" || starts "aarch64" then
    Some ("AArch64", if apple then "apple-m1" else "generic")
  else if starts "x86_64" then
    Some ("X86", if apple then "core2" else "x86-64")
  else None

let avail_cache : (string, bool) Hashtbl.t = Hashtbl.create 4

(** True when libLLVM is loaded, has every entry point the emitter needs,
    and has [arch]'s backend compiled in.  Cached; never raises. *)
let available ~arch =
  match Hashtbl.find_opt avail_cache arch with
  | Some b -> b
  | None ->
    let b = try available_c arch with _ -> false in
    Hashtbl.replace avail_cache arch b; b

(** Write [ir], compiled at O1 for [triple]/[cpu], as a PIC object to
    [out].  [Error msg] on any failure. *)
let emit_object ~ir ~triple ~cpu ~out : (unit, string) result =
  match emit_object_c ir triple cpu out with
  | "" -> Ok ()
  | msg -> Error msg
  | exception Failure msg -> Error msg
