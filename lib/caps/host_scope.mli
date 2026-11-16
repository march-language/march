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
  path : string list option;
      (** a path prefix as segments ([/v1/weather/] is [["v1"; "weather"]]);
          [None]: any path *)
}

type decl = {
  patterns : pattern list;  (** [[]]: any host *)
  no_redirects : bool;
  methods : string list option;
      (** [None]: every method; else the allowed lowercase verbs, sorted *)
}

val http_methods : string list
(** The verbs a [methods(...)] option may name: the standard ones of
    [Http.Method] ([get], [head], [post], [put], [patch], [delete], [options]). *)

val normalize_host : string -> string
(** ASCII lowercase, one trailing [.] stripped. No DNS, no punycode. *)

val parse_pattern : string -> (pattern, string) result
(** [host], [host:port], [*.suffix], an IPv4 literal or a bracketed IPv6
    literal. The error is a user-facing reason (a scheme, a path, userinfo, a
    misplaced wildcard, a non-ASCII or empty label, a bad port). *)

val pattern_to_string : pattern -> string

val split_options : string -> string * string list
(** Split a stored scope string into the scope and its options
    (["a.com;methods=get;no_redirects"] -> [("a.com", ["methods=get"; "no_redirects"])]).
    A string whose tail is not option-shaped is all scope. *)

val parse_decl : string option -> (decl, string) result
(** One [needs] declaration's scope. [None] is unscoped. *)

val matches : pattern -> host:string -> port:int -> bool
(** [host] is normalized before comparing. *)

val permits : decl list -> host:string -> port:int -> bool
(** The declarations of one module for [IO.NetConnect]. [[]] means the module
    is not scoped (true); so does any declaration with no pattern. *)

val permits_method : decl list -> host:string -> port:int -> meth:string -> bool
(** Some declaration covers the destination and allows [meth] (lowercase),
    by listing it or by listing no methods. [[]] is unscoped (true). *)

val permits_raw : decl list -> host:string -> port:int -> bool
(** A raw connection shows no method and no path, so it needs a declaration
    covering the destination with no [methods(...)] and no path. *)

val path_ok : string -> bool
(** A request path the guard will judge at all: it starts with [/], uses only
    RFC 3986 path characters (no [;], [?], [#], space or control character),
    every [%] is a well-formed escape that does not decode to [.], [/], [\\],
    [%] or a control character, and it has no [//] and no [.] or [..]
    segment. Refused, not normalized. Agrees with [Http.scope_path_ok]. *)

val path_within : prefix:string list -> string -> bool
(** Segment-wise: [/v1/weather/] admits [/v1/weather] and [/v1/weather/x], not
    [/v1/weatherman]. Query and fragment ignored. *)

val permits_request :
  decl list -> host:string -> port:int -> meth:string option -> path:string option -> bool
(** The full check. [meth = None]: the method is not known (not checked here).
    [path = None]: the path is not known, which a path-scoped pattern does not
    admit (use {!permits_host_ignoring_path} where the run-time guard will
    check the path). [[]] is unscoped (true). *)

val permits_host_ignoring_path :
  decl list -> host:string -> port:int -> meth:string option -> bool

val url_path_of_literal : prefix:bool -> string -> string option
(** The path of a literal URL ([~prefix:false]: up to the first [?], a [#]
    kept, [/] when absent, exactly as [Http.parse_url] reads it), or the path part of a literal prefix up to and including its
    last [/] ([~prefix:true]). *)

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
    [no_redirects] ([!] alone: any host, no redirects) and a trailing
    [@get+head] for [methods(get, head)]. *)

val decode_spec : string -> decl list
(** Inverse of {!encode_spec}. Raises [Invalid_argument] on a malformed spec. *)
