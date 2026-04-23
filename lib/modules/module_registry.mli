(** Module export registry — maps module names to their exported bindings.
    Populated by loading stdlib .march files and by processing DMod declarations.
    Queried by typecheck, eval, and TIR lower when resolving qualified names. *)

(** What kind of export a module member is. *)
type export_kind =
  | ExFn                       (** Function binding *)
  | ExType of int              (** Type constructor with arity *)
  | ExCtor of string * int     (** Data constructor: parent type name, arity *)
  | ExValue                    (** Top-level let binding *)
  | ExInterface of March_ast.Ast.interface_def  (** Interface definition (for cross-module method resolution) *)

(** A single exported member of a module. *)
type export_entry = {
  ex_name : string;            (** Short name (e.g. "get") *)
  ex_kind : export_kind;
  ex_public : bool;
}

(** All exports from a single module. *)
type module_exports = {
  me_name : string;            (** Module name (e.g. "Map") *)
  me_entries : export_entry list;
}

(** Register a module's exports in the global registry. *)
val register : string -> module_exports -> unit

(** Extract the public exports from a list of declarations (a module body).
    Called by the REPL after loading a user module via MARCH_LIB_PATH so the
    module's qualified accesses (`MyMod.foo`) resolve through the registry. *)
val extract_exports : string -> March_ast.Ast.decl list -> module_exports

(** Look up a module's exports by name. *)
val lookup : string -> module_exports option

(** Check whether a module name is known (registered or loadable). *)
val is_known_module : string -> bool

(** Load a stdlib module by name, parse+desugar it, extract public exports,
    and register them. Returns the exports table. Caches results.
    Handles circular dependencies via a "loading" sentinel. *)
val ensure_loaded : string -> module_exports option

(** Set the stdlib directory path for file resolution. *)
val set_stdlib_dir : string -> unit

(** Reset all global state (for testing). *)
val reset : unit -> unit

(** Find the stdlib directory, searching several candidates. *)
val find_stdlib_dir : unit -> string option

(** Find the stdlib .march file path for a module name. *)
val find_stdlib_file : string -> string option
