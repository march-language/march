(** Pattern exhaustiveness and redundancy checking (a simplified Maranget
    "Warnings for Pattern Matching"), plus the session-channel and sendability
    checks that share its machinery.

    Seven of this module's twenty-seven definitions are its contract; the other
    twenty — the pattern matrix, its five specialisation operators, the
    usefulness search, the or-pattern expansion cap — are the algorithm's
    internals and stop being reachable here.  [Typecheck] regains everything
    below through [include Typecheck_exhaustive]. *)

open Typecheck_types
open Typecheck_env

(** A simplified pattern, normalised for the matrix algorithm. *)
type spat =
  | SPWild                          (** [_] or any variable binding *)
  | SPCon  of string * spat list    (** constructor: [Some(x)], [None] *)
  | SPLit  of Ast.literal           (** literal: [0], [true], ["hi"] *)
  | SPTup  of spat list             (** tuple: [(a, b)] *)
  | SPRec  of (string * spat) list  (** record, sorted by field name; OPEN *)

(** Instantiate a surface type against a substitution for its type variables.
    Used to specialise a constructor's declared argument types to the
    scrutinee's actual type arguments. *)
val inst_ty : (string * ty) list -> Ast.ty -> ty

(** Source span of a pattern's outermost node. *)
val span_of_pat : Ast.pattern -> Ast.span

(** Warn on match arms that can never be reached because earlier arms already
    cover them. *)
val check_redundant_arms : env -> ty -> Ast.branch list -> unit

(** Warn when a match does not cover its scrutinee type, naming a witness
    pattern that would fall through. *)
val check_exhaustiveness : env -> Ast.span -> ty -> Ast.branch list -> unit

(** Unfold one level of a recursive session type ([SRec]). *)
val unfold_srec : session_ty -> session_ty

(** Report using a channel whose [offer] branch was never refined, and answer
    whether it did report — callers use the boolean to stop checking. *)
val offer_unrefined_error : env -> Ast.span -> session_ty ref -> string -> bool

(** Reject values that cannot cross an actor or channel boundary. *)
val check_sendable : env -> Ast.span -> ty -> unit

(** The primitive roots of [is_send]: builtin types that write memory another
    reference could observe and are neither [always_linear] nor copy-on-write.
    Empty; test/test_typecheck_send.ml fails the build if a name is added before
    the general Send check (plan Parts A and B) lands. *)
val non_sendable_types : string list

(** Test hook: extra primitive roots for [is_send] (test/test_typecheck_send.ml only). *)
val send_roots_for_tests : string list ref

(** The structural sendability judgement; see the implementation's comment. *)
type send_result =
  | Send
  | Not_send of string list * ty
  | Send_if of ty list
  | Send_mod_closures of string list

val is_send : env -> ty -> send_result
