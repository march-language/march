(** Resolve a capability's dictionary type — nominal for a proof capability
    that declared one, structural/derived for an IO capability under `--test`.
    See the implementation header for why this cannot live in [Typecheck_env]. *)

open Typecheck_types
open Typecheck_env

val dict_ty_of_cap : env -> string -> ty option
