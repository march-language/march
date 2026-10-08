(** Source provenance side table ([fn_name -> origin]); see provenance.ml. *)

type derivation =
  | Mono_of of string * Tir.ty list
  | Fusion_of of string * string
  | Hof_spec_of of string * string
  | Defun_of of string
  | Join_point_of of string
  | Inlined_from of string
  | Clone_of of string * string

type origin = {
  src_span : March_ast.Ast.span option;
  host     : string option;
  derived  : derivation list;
  passes   : string list;   (** most recent first *)
}

val reset : unit -> unit
(** Start of [Lower.lower_module]: a fresh table for this module/fragment. *)

val note_span : string -> March_ast.Ast.span -> unit
(** Lowering: the span of a parsed fn under its creation-time name. *)

val rename : old:string -> new_:string -> unit
(** A fn_def was renamed (module prefix, impl mangling, shadow uniquing). *)

val seed_from_lowering : file:string -> Tir.tir_module -> unit
(** End of [Lower.lower_module]: an origin for every final top-level fn. *)

val record :
  string -> ?host:string -> ?from:string -> ?derived:derivation ->
  pass:string -> unit -> unit
(** A pass created [name]. [from] copies span/host/derivations from the
    function it was derived from; [host] overrides, else [with_host]'s. *)

(** The host set by [with_host], for passes that derive a name from it. *)
val current_host : string option ref

val with_host : string -> (unit -> 'a) -> 'a
(** Run [f] with [host] as the default host for [record]. *)

val sweep : pass:string -> Tir.tir_module -> unit
(** After a pass: give every still-unrecorded top-level fn an origin naming
    [pass], so no emitted function lacks one. *)

val nested_fn_hosts : Tir.tir_module -> (string, string) Hashtbl.t
(** Every nested fn_def name mapped to its enclosing top-level fn. *)

val find : string -> origin option

val span_of : string -> March_ast.Ast.span option

val effective_span : string -> March_ast.Ast.span option
(** Own span, else the host chain's, else [None]. *)

val module_file : string option ref
(** The lowered module's source file (set by [seed_from_lowering]). *)

val string_of_span : March_ast.Ast.span -> string

val string_of_derivation : derivation -> string

val render : origin -> string
(** Tab-separated [span host derivations passes]. *)

val render_meta : origin -> string
(** Space-separated [k=v] form for an LLVM metadata string. *)

val all : unit -> (string * origin) list
(** Sorted by name, for tests and the determinism oracle. *)

val dump : out_channel -> unit
(** One [name<TAB>span<TAB>host<TAB>derivations<TAB>passes] line per fn. *)
