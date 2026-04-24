(* lib/jit/jit_orc.ml — see .mli for docs *)

type t = nativeint  (* LLVMOrcLLJITRef, stored as a nativeint *)

external create_c : unit -> nativeint = "march_orc_create"
external add_ir_c : nativeint -> string -> string -> unit = "march_orc_add_ir"
external lookup_c : nativeint -> string -> nativeint = "march_orc_lookup"
external dispose_c : nativeint -> unit = "march_orc_dispose"

let create () = create_c ()
let add_ir t ~ir ~name = add_ir_c t ir name
let lookup t sym = lookup_c t sym
let dispose t = dispose_c t
