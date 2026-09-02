(** Resolve a capability's dictionary TYPE, whichever kind of capability it is.

    Two kinds, two mechanisms:

    - A PROOF capability names its dictionary type in its own declaration
      (`proof cap Live with Ops`), so the type is NOMINAL and lives in
      [env.records] — see [Typecheck_env.resolve_cap_dict_type].
    - An IO capability has no declaration site a user owns, so its dictionary
      is DERIVED from the compiler's builtin tables and is STRUCTURAL — see
      [Io_ops_gen], and its header for why a generated stdlib module could not
      work.

    This module exists because neither of those layers can see the other:
    [Io_ops_gen] is built on [Typecheck_builtins], which is built on
    [Typecheck_env], so the env cannot reach forward to the generator.

    IO dictionaries are gated on [test_build]. Attaching one is admissible only
    in a test build ([check_cap_impl_sites]), and a capability whose dictionary
    can never be attached must not read one either: otherwise `cap_dict` on an
    IO capability in a release build would typecheck and always yield [None],
    which reads like a working default path rather than an unavailable
    feature. *)

open Typecheck_types
open Typecheck_env

let dict_ty_of_cap (env : env) (cap_path : string) : ty option =
  match resolve_cap_dict_type env cap_path with
  | Some rec_name -> Some (TCon (rec_name, []))
  | None -> if !test_build then Io_ops_gen.dict_ty cap_path else None
