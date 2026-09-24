type platform = Elf | MachO

type t = {
  canonical_target : string;
  llvm_triple : string;
  pointer_bytes : int;
  platform : platform;
  runtime_abi : int;
}

val of_target : Llvm_toplevel.target_config -> (t, string) result
val abi_id : t -> string
