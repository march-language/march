type platform = Elf | MachO

type t = {
  canonical_target : string;
  llvm_triple : string;
  pointer_bytes : int;
  platform : platform;
  runtime_abi : int;
}

(* 3: actor-message constructor tags became a stable hash of the qualified
   constructor name, and Actor.call's positional tag translation moved from
   march_actor_set_call_base to march_actor_set_call_tags
   (specs/progress/2026-09-25-migrate-msg-actor-message-tags.md). A patch
   built by this compiler would drop every actor message a v2 process sends
   it, and could not even load against a v2 runtime.
   4: a dispatch slot's sig_hash folds in its parameters' borrow modes
   (March_cas.Hash.hcr_sig_hash), so a patch that flips one is a signature
   change to forge's gate instead of a use-after-free or a leak
   (specs/progress/2026-10-13-hcr-borrow-mode-not-in-sig-hash.md).  A v3
   process published type-only hashes, which no v4 patch's can match, and
   its patches record no sig_hash at all: hot deploys from this compiler
   into a v3 process are refused by identity (forge's HCR_INFO preflight,
   then the runtime's own check after dlopen) and need one restart on a v4
   build. *)
let runtime_abi = 4

let contains haystack needle =
  let hay_len = String.length haystack in
  let needle_len = String.length needle in
  let rec loop i =
    if i + needle_len > hay_len then false
    else if String.sub haystack i needle_len = needle then true
    else loop (i + 1)
  in
  needle_len = 0 || loop 0

let unsupported target_name =
  Error (Printf.sprintf
    "hot reload requires a native dynamic loader and Unix-domain sockets; target %s is unsupported"
    target_name)

let of_target target =
  let open Llvm_toplevel in
  let llvm_triple = target_triple target in
  let pointer_bytes = target_ptr_size target in
  match target with
  | LinuxGnu { arch = X86_64; _ } ->
    Ok { canonical_target = "linux/amd64"; llvm_triple; pointer_bytes;
         platform = Elf; runtime_abi }
  | LinuxGnu { arch = Arm64; _ } ->
    Ok { canonical_target = "linux/arm64"; llvm_triple; pointer_bytes;
         platform = Elf; runtime_abi }
  | Native ->
    let lower = String.lowercase_ascii llvm_triple in
    if contains lower "linux" then
      Ok { canonical_target = "native"; llvm_triple; pointer_bytes;
           platform = Elf; runtime_abi }
    else if contains lower "darwin" || contains lower "apple" then
      Ok { canonical_target = "native"; llvm_triple; pointer_bytes;
           platform = MachO; runtime_abi }
    else
      unsupported "native"
  | Wasm64Wasi -> unsupported "wasm64-wasi"
  | Wasm32Wasi -> unsupported "wasm32-wasi"
  | Wasm32Unknown -> unsupported "wasm32-unknown-unknown"
  | Js -> unsupported "js"

let abi_id profile =
  Printf.sprintf "march-hcr-v%d;triple=%s;ptr=%d"
    profile.runtime_abi profile.llvm_triple profile.pointer_bytes
