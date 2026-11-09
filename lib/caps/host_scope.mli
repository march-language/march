(** Host scopes on [IO.NetConnect].

    A scope narrows the outbound network capability to the hosts a module may
    connect to: [needs IO.NetConnect("example.com")]. Like the filesystem path
    scopes in {!Cap_scope}, a scope travels beside the capability string, never
    inside it. See specs/2026-11-09-host-scoped-network-capabilities-design.md.

    The parser stores a declaration's [no_redirects] option in the same scope
    string as ["<pattern>;no_redirects"] (or [";no_redirects"] for any host),
    so the AST type of [needs] does not change. {!parse_decl} splits it. *)

type pattern = {
  host : string;  (** normalized; for a wildcard, the suffix after [*.] *)
  wildcard : bool;  (** [*.suffix]: any name ending in [.suffix], not the suffix itself *)
  port : int option;  (** [None]: any port *)
}

type decl = {
  patterns : pattern list;  (** [[]]: any host *)
  no_redirects : bool;
}

val normalize_host : string -> string
(** ASCII lowercase, one trailing [.] stripped. No DNS, no punycode. *)

val parse_pattern : string -> (pattern, string) result
(** [host], [host:port], [*.suffix], an IPv4 literal or a bracketed IPv6
    literal. The error is a user-facing reason (a scheme, a path, userinfo, a
    misplaced wildcard, a non-ASCII or empty label, a bad port). *)

val pattern_to_string : pattern -> string

val parse_decl : string option -> (decl, string) result
(** One [needs] declaration's scope. [None] is unscoped. *)

val matches : pattern -> host:string -> port:int -> bool
(** [host] is normalized before comparing. *)

val permits : decl list -> host:string -> port:int -> bool
(** The declarations of one module for [IO.NetConnect]. [[]] means the module
    is not scoped (true); so does any declaration with no pattern. *)

val forbids_redirects : decl list -> host:string -> port:int -> bool
(** Some declaration with [no_redirects] covers this destination. *)

type authority = { a_host : string; a_port : int }

val authority_of_url : prefix:bool -> string -> authority option
(** The destination of a literal [http://] / [https://] URL, as
    [Http.parse_url] reads it, or [None] when the compiler should not vouch
    for it. The authority ends only at [/], as in [Http.parse_url]; it may
    hold only letters, digits, [-], [.] and one [:port], so a literal on which
    the two parsers could disagree ([@], [\[], [\\], [%], [?], [#], spaces) is
    [None]. With [~prefix:true] the [/] must be present: the literal is the
    start of a concatenation, and without the [/] the rest could extend the
    host. A missing port is the scheme's default (80 / 443). *)

val encode_spec : decl list -> string
(** The run-time form the stdlib guard reads: [""] for no scoping, otherwise
    [,]-separated entries, each a pattern, with a leading [!] for
    [no_redirects] ([!] alone: any host, no redirects). *)

val decode_spec : string -> decl list
(** Inverse of {!encode_spec}. Raises [Invalid_argument] on a malformed spec. *)
