(** Return-type-directed dispatch for `from_json` — the side channel that
    carries one decision from the typechecker to both backends.

    `from_json` dispatches on its RESULT type, not on an argument, so neither
    backend can pick an implementation from the values in hand:
    `derive Json for T` generates `JsonFrom$T.from_json`, and at
    `from_json(v)` the only thing that names T is the type the caller expects.
    The typechecker is the one pass that knows it.

    Why a side table and not a rewritten AST.  The resolution is only sound
    once the whole module is solved — the result type is usually pinned by
    unification LATER than the call (see [Typecheck_caps.check_json_cap_sites],
    which defers for exactly this reason) — so the earliest a rewrite could
    happen is after checking. Returning a rewritten module from `check_module`
    would mean every entry point (the driver's several pipelines, forge, the
    LSP, the REPL JIT) has to remember to feed the NEW module to the backend,
    and one that forgets keeps the old, silently-wrong dispatch. A table every
    consumer already reaches is picked up everywhere by construction.

    Keyed by the call site's span, which is unique per site: real spans carry
    file and position, and derive-generated code is run through
    [Desugar_derive]'s span uniquifier precisely so that synthetic nodes get
    distinct keys (the same property [type_map] already depends on).

    Process-global, so it MUST be reset per check — [Typecheck.check_module_core]
    does that at entry. A REPL fragment, an LSP re-check and a multi-file forge
    build are each their own check and must not read a previous one's answers.

    Lives in [March_ast] because it is the one library both [March_typecheck]
    (the writer) and [March_eval] / [March_tir] (the readers) already depend
    on; putting it in the typechecker would force the interpreter to depend on
    the typechecker for a single hashtable. *)

let tbl : (Ast.span, string) Hashtbl.t = Hashtbl.create 32

let reset () = Hashtbl.reset tbl

(** Record that the `from_json` call at [sp] decodes to type [type_name].
    Called only from the capability sweep, which derives [type_name] from the
    very same solved type it screens for capabilities — so a dispatch can
    never be resolved from a type the guard did not also see. *)
let record (sp : Ast.span) (type_name : string) : unit =
  Hashtbl.replace tbl sp type_name

let find (sp : Ast.span) : string option = Hashtbl.find_opt tbl sp

(** The mangled implementation symbol `derive Json` generates for [type_name].
    Mirrors [Tir_names.iface_mangle]'s `Iface$Type.method` convention, which
    is what both the interpreter's `impl_tbl` key and the TIR backend's
    top-level function name are built from. *)
let impl_symbol (type_name : string) : string =
  "JsonFrom$" ^ type_name ^ ".from_json"

(** The typed remote send shares this table (stdlib/node.march).  For a
    `Node.send(peer, to, msg)` site the recorded string is the MESSAGE type's
    name, module-qualified where its declaration is ("Outer.Inner.Ping"): that
    string is the wire type tag, minted here so sender and receiver agree by
    construction.  The impl symbol keys on the short name, as every impl
    lookup does; [short] recovers it.  Consumers tell the two uses apart by
    the callee, never by the recorded string. *)
let short (type_name : string) : string =
  match String.rindex_opt type_name '.' with
  | Some i -> String.sub type_name (i + 1) (String.length type_name - i - 1)
  | None -> type_name

(** `JsonTo$<short>.to_json`: the encoder `derive Json` generates for a type. *)
let encoder_symbol (type_name : string) : string =
  "JsonTo$" ^ short type_name ^ ".to_json"

(** The explicit form a typed send lowers to, by callee and arity:
    `Node.send` (3 args) and `Node.enqueue` (4: the queue's policy last).
    The message is the third argument of both. *)
let tagged_callee (callee : string) (arity : int) : string option =
  match callee, arity with
  | "Node.send", 3 -> Some "Node.send_tagged"
  | "Node.enqueue", 4 -> Some "Node.enqueue_tagged"
  | "Node.accepts", 2 -> Some "Node.tag_is"
  | _ -> None

(** Both backends' rewrite of a resolved typed-send site, in one place so
    they cannot drift:
      Node.send(peer, to, msg)
        ==> Node.send_tagged(peer, to, "<tag>", JsonTo$T.to_json(msg))
      Node.enqueue(q, to, msg, policy)
        ==> Node.enqueue_tagged(q, to, "<tag>", JsonTo$T.to_json(msg), policy)
      Node.accepts(d, fn (_ : T) -> ())
        ==> Node.tag_is(d, "<tag>")
    [None] when the site was not recorded (the typechecker then already
    reported it) or the call is not one of the two shapes above. *)
let node_send_rewrite (e : Ast.expr) : Ast.expr option =
  match e with
  | Ast.EApp (Ast.EVar { txt = "Node.accepts"; span = fsp }, [ d; _witness ], sp) ->
    (* The receiver's half: `Node.accepts(d, fn (_ : T) -> ())` ==>
       `Node.tag_is(d, "<tag of T>")`.  The witness is only a type carrier. *)
    (match find sp with
     | None -> None
     | Some tag ->
       Some (Ast.EApp (Ast.EVar { txt = "Node.tag_is"; span = fsp },
                       [ d; Ast.ELit (Ast.LitString tag, sp) ], sp)))
  | Ast.EApp (Ast.EVar { txt; span = fsp }, (dst :: to_ :: msg :: rest as args), sp) ->
    (match tagged_callee txt (List.length args), find sp with
     | Some tagged, Some tag ->
       Some (Ast.EApp (Ast.EVar { txt = tagged; span = fsp },
                       [ dst; to_;
                         Ast.ELit (Ast.LitString tag, sp);
                         Ast.EApp (Ast.EVar { txt = encoder_symbol tag; span = fsp },
                                   [msg], sp) ] @ rest,
                       sp))
     | _ -> None)
  | _ -> None
