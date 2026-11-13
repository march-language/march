(** Name scopes on [IO.Mut] and [IO.Registry] (ocap phase 2, spec §6).

    A name scope narrows a capability that turns a NAME into authority (a
    Vault table by name, an actor by registered name) to some names:
    [needs IO.Mut("sessions")], [needs IO.Registry("logger", prefix("worker."))].
    [None] means unscoped, any name, which is what a capability declared
    without a scope means.

    The scope reaches the typechecker as the single string the parser builds
    ([lib/parser/parser.mly], [scoped_cap_path]): the first name, then
    [;name=<n>] for each further name and [;prefix=<p>] for each prefix. A
    scope of prefixes alone starts with an empty first segment
    (";prefix=worker."). The parser refuses a [;] in any scope string and
    an empty first string followed by more, so the encoding has one reading. *)

type t = { names : string list; prefixes : string list }

val parse : string -> (t, string) result
(** Decode the parser's encoding. [Error reason] (a phrase, no capital or full
    stop) for an empty name or prefix, a name or prefix holding [;], [=] or
    [,], or an option other than a further name or [prefix(...)]. *)

val admits : t -> string -> bool
(** [admits s n]: [n] is one of the names, or starts with one of the prefixes.
    A prefix is a raw character prefix: ["worker."] admits ["worker.1"] but not
    ["worker"] or ["workers.1"]. *)

val subsumes : t option -> t option -> bool
(** [subsumes a b]: does [a] permit every name [b] does? [None] (unscoped)
    subsumes everything; a scope never subsumes [None]. Otherwise every name
    of [b] must be admitted by [a], and every prefix of [b] must start with a
    prefix of [a] (a name list never covers a prefix, which admits
    unboundedly many names). Same direction as {!Cap_scope.scope_subsumes}. *)

val quote : string -> string
(** A March string literal for [s], with March's escapes. *)

val to_surface : string -> t -> string
(** [to_surface cap s] is the [needs] spelling, [IO.Registry("logger",
    prefix("worker."))], for diagnostics. Strings are quoted with March's
    escapes. *)
