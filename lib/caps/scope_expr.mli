(** Scope expressions (ocap phase 5, decision 3): a constructor written with
    a capability path in expression position, [IO.Console],
    [IO.FileRead("/srv/")], [IO.NetConnect("api.x.com", methods(get))], and
    the arguments of [restrict].

    One classifier, shared by the type checker, [Lower] and the interpreter,
    so the three cannot disagree about which expressions are scopes and which
    are literal.  It reads the DESUGARED shapes: [IO.FileRead("/a/")] is
    [ECon ("IO.FileRead", [ELit "/a/"])], [methods(get)] is
    [EApp (EVar "methods", [EVar "get"])], [prefix("w.")] is
    [EApp (EVar "prefix", [ELit "w."])] and [no_redirects] is
    [EVar "no_redirects"]. *)

(** One entry in the [needs] AST encoding: the capability path and the scope
    string ("<first string>;name=<s>;<option>;...", or ";<option>..." for
    options alone), exactly as the parser builds it for a [needs] line. *)
type entry = March_ast.Ast.name list * string option

type form =
  | Literal of entry list  (** [()] is [Literal []] *)
  | Computed of { kind : string; strings : March_ast.Ast.expr list; options : string list }
      (** one entry with a computed string: the capability path, every string
          argument (literal or not) in order, and the encoded options *)
  | Not_scope

(** [is_cap_path name]: [name] is a capability kind: rooted at [IO] ([IO],
    [IO.Console], ...) or a top-level kind outside it ([Actor.Introspect],
    [Actor.Debug]), so an [ECon] of it is a scope expression rather than a
    constructor.  No stdlib module declares a constructor under those paths. *)
val is_cap_path : string -> bool

(** [classify e]: an [ECon] of a capability path with arguments in the
    [needs] grammar (strings, then options) is [Literal] when every string is
    a literal and [Computed] when one is any other expression.  A [+] of two
    [Literal] forms is [Literal] (concatenated); a [+] involving anything else
    is [Not_scope] (an ordinary [+] on [Scope] values).  A non-literal option,
    a string after an option or an empty first string followed by more is
    [Not_scope]; for an [ECon] of a capability path the type checker reports
    that as [invalid_cap_scope]. *)
val classify : March_ast.Ast.expr -> form

(** [restrict_text es]: [Some text] when every entry of a [restrict] is
    [Literal] (the text is [Cap_request.request_of_entries] of the entries,
    ["()"] when there are none); [None] when the restrict is computed. *)
val restrict_text : March_ast.Ast.expr list -> string option

(** [restrict_entries es]: the entries of a literal [restrict], in order;
    [None] when it is computed. *)
val restrict_entries : March_ast.Ast.expr list -> entry list option
