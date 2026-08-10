(** March desugaring pass.

    Transforms the surface AST into a simpler "core" form that the type
    checker and all subsequent passes can handle uniformly.  The key
    transformations are:

    1. **Multi-head function desugaring** — consecutive fn clauses with the
       same name are already grouped into a single [DFn] by the parser's
       [group_fn_clauses].  Here we turn a [fn_def] with more than one
       clause (or with pattern params in a single clause) into a single
       clause whose body is a [match] expression.

       Before:
         fn fib(0) do 1 end
         fn fib(1) do 1 end
         fn fib(n) do fib(n-1) + fib(n-2) end

       After grouping (done by parser):
         DFn { fn_clauses = [clause0; clause1; clause2] }

       After desugaring (done here):
         DFn { fn_clauses = [
           { fc_params  = [FPNamed "__arg0"]
           ; fc_guard   = None
           ; fc_body    = EMatch(__arg0, [
               0   -> 1
               1   -> 1
               n   -> fib(n-1) + fib(n-2)
             ])
           }
         ]}

    2. **Pipe desugaring** — [x |> f] becomes [f(x)].

    3. **If without else** (future) — for now [if] always requires else.

    The output is still an [Ast.module_] — we don't introduce a separate
    Core AST yet.  That will come when we have enough typed information to
    make it worthwhile. *)

open March_ast.Ast
module Err = March_errors.Errors

(* ---- Utilities ---- *)

(** Counter for generating unique synthetic spans for synthesised params.
    Each call to [fresh_arg_name] gets a distinct [start_line] so that
    the typechecker can annotate each synthesised [__argN] param at its
    own slot in the type_map, avoiding collisions across functions that
    previously all shared [dummy_span] and got the wrong inferred type. *)
let _synth_counter = ref 0

(** Generate fresh argument names __arg0, __arg1 … for synthesised match
    scrutinees.  These are prefixed with "__" to avoid shadowing user
    bindings.  Each generated name gets a unique synthetic span so the
    typechecker's type_map entries don't collide across functions. *)
let fresh_arg_name i =
  incr _synth_counter;
  let txt = Printf.sprintf "__arg%d" i in
  { txt; span = { file = "__synth__";
                  start_line = !_synth_counter;
                  start_col  = i;
                  end_line   = 0;
                  end_col    = 0 } }

(** True if a fn_param is "trivially named" — i.e. it is an [FPNamed]
    with no need to match.  A single clause of all trivially-named params
    needs no match desugaring. *)
let is_trivial_param = function
  | FPNamed _ -> true
  | FPPat (PatVar _) -> true   (* single var pattern is just a binding *)
  | FPPat _ -> false
  | FPDefault _ -> false  (* forces desugar to run expand_defaults_in_def *)

(** A guard looks like a type-class constraint (e.g. [Eq(a)]) when it is a
    constructor application whose constructor name starts with an uppercase
    letter.  Such guards should be preserved in [fc_guard] rather than
    pushed into a match-branch guard so that the type checker can recognize
    and handle them as interface constraints on the function's scheme. *)
let is_class_constraint_guard = function
  | Some (ECon (name, _, _))
    when String.length name.txt > 0
      && Char.uppercase_ascii name.txt.[0] = name.txt.[0] -> true
  | _ -> false

(** True if a single-clause fn needs no match desugaring at all. *)
let clause_is_trivial (clause : fn_clause) =
  (clause.fc_guard = None || is_class_constraint_guard clause.fc_guard)
  && List.for_all is_trivial_param clause.fc_params

(** Convert an [fn_param] into the [pattern] used as a branch arm.
    - [FPNamed p]        → PatVar p.param_name
    - [FPPat p]          → p  (already a pattern) *)
let fn_param_to_pattern : fn_param -> pattern = function
  | FPNamed p -> PatVar p.param_name
  | FPPat  p  -> p
  | FPDefault (p, _) -> PatVar p.param_name

(** Convert an [fn_param] into the "declaration" form used in the
    single merged clause.  We always use an [FPNamed] with the generated
    arg name so the type checker sees a simple named param. *)
let mk_named_param name : fn_param =
  FPNamed { param_name = name; param_ty = None; param_lin = Unrestricted }

(* ---- HTML IOList generation for ~H sigil ---- *)

(** Decompose an interpolation into a flat list of parts.

    The parser emits interpolations as a single shape (see [desugar_interp] in
    [lib/parser/parser.mly]):
      "prefix" ++ to_string(e1) ++ "mid" ++ to_string(e2) ++ "suffix"
    and this pass then collapses `++` chains of 3+ into [string_concat3], so
    both shapes reach here — the concat3 one because [ESigil]'s arm calls
    [desugar_expr] on its content before handing it over.

    Keeping this in sync with those two shapes is load-bearing:
    [html_interp_to_iolist] identifies the dynamic parts by matching
    [to_string(e)] *per part*, so a shape this function cannot see through
    collapses the whole template into ONE opaque part — silently disabling HTML
    auto-escaping (and island/CSRF rewriting) rather than failing. That has
    happened twice, and it fails OPEN: the template still renders, unsafely.
    Guarded by the `~H sigil codegen` tests. *)
let rec decompose_concat (e : expr) : expr list =
  match e with
  | EApp (EVar { txt = "++"; _ }, [left; right], _sp) ->
    decompose_concat left @ decompose_concat right
  | EApp (EVar { txt = "string_concat3"; _ }, [a; b; c], _sp) ->
    decompose_concat a @ decompose_concat b @ decompose_concat c
  | _ -> [e]

(** Number of operands in a [++] chain, without building the list. *)
let concat_chain_len (e : expr) : int = List.length (decompose_concat e)

(** Rebuild a flattened [++] chain using three-way concats, consuming three
    operands per allocation instead of two.

    [a;b;c;d;e] becomes [string_concat3(string_concat3(a,b,c), d, e)] — two
    allocations where the left-deep [++] chain needed four.  A trailing pair
    falls back to [++], and a trailing single operand is appended with [++],
    since [string_concat3] is fixed-arity.

    Left-associative, matching [++]'s own associativity, so evaluation order and
    therefore the result string are unchanged. *)
let fold_concat3 (parts : expr list) (sp : span) : expr =
  let cat2 a b = EApp (EVar { txt = "++"; span = sp }, [a; b], sp) in
  let cat3 a b c =
    EApp (EVar { txt = "string_concat3"; span = sp }, [a; b; c], sp) in
  let rec go acc rest =
    match rest with
    | []            -> acc
    | [x]           -> cat2 acc x
    | x :: y :: tl  -> go (cat3 acc x y) tl
  in
  match parts with
  | []            -> ELit (LitString "", sp)
  | [x]           -> x
  | [x; y]        -> cat2 x y
  | x :: y :: z :: tl -> go (cat3 x y z) tl

(* ── Island tag parsing in ~H ──────────────────────────────────────────── *)

(** Try to extract the value of an attribute (name='value' or name="value")
    from a raw HTML-like string.  Returns [Some value] or [None]. *)
let extract_attr (attr_name : string) (s : string) : string option =
  let pat_sq = attr_name ^ "='" in
  let pat_dq = attr_name ^ "=\"" in
  let try_quote pat close_char =
    match String.split_on_char pat.[0] s with
    | _ ->
      (* Simple substring search *)
      let plen = String.length pat in
      let slen = String.length s in
      let rec scan i =
        if i + plen > slen then None
        else if String.sub s i plen = pat then begin
          let start = i + plen in
          let rec find_end j =
            if j >= slen then None
            else if s.[j] = close_char then
              Some (String.sub s start (j - start))
            else find_end (j + 1)
          in
          find_end start
        end
        else scan (i + 1)
      in
      scan 0
  in
  match try_quote pat_sq '\'' with
  | Some _ as r -> r
  | None -> try_quote pat_dq '"'

(** Check if a string literal starts an island tag: [<island ...].
    Returns the module name if found, and whether the tag is self-closing
    within this literal (i.e. contains [/>]). *)
let detect_island_start (s : string) : string option =
  let trimmed = String.trim s in
  if String.length trimmed >= 7 &&
     String.sub trimmed 0 7 = "<island" then
    extract_attr "name" trimmed
  else
    None

(** Check if a string contains the self-closing end of an island tag [/>]. *)
let has_island_close (s : string) : bool =
  let len = String.length s in
  let rec scan i =
    if i + 1 >= len then false
    else if s.[i] = '/' && s.[i+1] = '>' then true
    else scan (i + 1)
  in
  scan 0

(** Process a list of parts from an ~H sigil, replacing <island> tags with
    calls to [IslandView.island_ssr].

    Recognises:
      ~H"<island name='Counter' />                  — no props
      ~H"<island name='Counter' props=${expr} />     — with props

    Desugars to:
      IslandView.island_ssr(name, Json.to_string(to_json(Mod.init(props))),
                            IOList.to_string(Mod.render(Mod.init(props))))

    When no props are given, uses the record literal [{}] as a dummy.
    The props expression comes from the next interpolated part after the
    opening string that contains [props=]. *)
let process_island_tags (parts : expr list) (sp : span) : expr list =
  let v s = EVar { txt = s; span = sp } in
  let app f args = EApp (v f, args, sp) in
  let rec go acc = function
    | [] -> List.rev acc
    (* String literal that contains an island tag *)
    | ELit (LitString s, lsp) :: rest when detect_island_start s <> None ->
      let module_name = match detect_island_start s with
        | Some n -> n | None -> assert false in
      (* Determine if props= appears in the string.  If so, the next
         interpolated part is the props expression. *)
      let has_props =
        let len = String.length s in
        let rec scan i =
          if i + 6 > len then false
          else if String.sub s i 6 = "props=" then true
          else scan (i + 1)
        in
        scan 0
      in
      if has_props then begin
        (* Expect: EApp(to_string, [props_expr]) :: ELit(" />") :: rest' *)
        match rest with
        | EApp (EVar { txt = "to_string"; _ }, [props_expr], _) :: tail ->
          (* Skip the closing " />" literal if present *)
          let rest' = match tail with
            | ELit (LitString closing, _) :: r when has_island_close closing -> r
            | _ -> tail
          in
          let init_call = app (module_name ^ ".create") [props_expr] in
          let state_json = app "Json.to_string" [app "to_json" [init_call]] in
          let render_call = app "IOList.to_string" [
            app (module_name ^ ".render") [
              app (module_name ^ ".create") [props_expr]
            ]
          ] in
          let island_expr =
            app "IslandView.island_ssr" [
              ELit (LitString module_name, sp);
              state_json;
              render_call
            ]
          in
          go (island_expr :: acc) rest'
        | _ ->
          (* Malformed — treat as a no-props island *)
          let island_expr = app "IslandView.island" [
            ELit (LitString module_name, sp);
            ELit (LitString "{}", lsp)
          ] in
          go (island_expr :: acc) rest
      end
      else begin
        (* No props — skip to closing /> *)
        let rest' = if has_island_close s then rest
          else match rest with
            | ELit (LitString closing, _) :: r when has_island_close closing -> r
            | _ -> rest
        in
        let island_expr = app "IslandView.island" [
          ELit (LitString module_name, sp);
          ELit (LitString "{}", lsp)
        ] in
        go (island_expr :: acc) rest'
      end
    | part :: rest ->
      go (part :: acc) rest
  in
  go [] parts

(* ── CSRF token injection in ~H ──────────────────────────────────────────── *)

(* B16 note: ~H used to auto-inject a `CSRF.tag_string(conn)` call after
   every mutating `<form method="post|put|patch|delete">` opening tag,
   UNCONDITIONALLY assuming a free `conn` variable in scope (the Bastion
   convention). That broke every non-Bastion ~H user with a baffling
   unbound-`conn` error, so the injection was removed entirely — which in
   turn silently dropped CSRF protection from every Bastion app (every POST
   started 403ing). The resolution keeps both behaviours: injection now
   fires ONLY when a `conn` binding is lexically in scope at the ~H sigil
   (function/lambda parameter, `let`/`let?` binding earlier in the block, or
   a match-branch pattern). Templates without `conn` render verbatim and
   never see an unbound-`conn` error; templates following the Bastion
   convention keep automatic CSRF protection.

   DO NOT ALSO INTERPOLATE A TOKEN YOURSELF. An earlier version of this comment
   claimed an explicit `${CSRF.tag_string(conn)}` "still works either way". It
   does not — injection is unconditional once `conn` is in scope, so an explicit
   token is emitted IN ADDITION to the injected one. Measured:

     ~H"<form method=\"post\"></form>"
       -> <form method="post"><input _csrf ...></form>          correct

     ~H"<form method=\"post\">${CSRF.tag(conn)}</form>"
       -> <form ...><input _csrf ...><input _csrf ...></form>   DUPLICATE

     ~H"<form method=\"post\">${CSRF.tag_string(conn)}</form>"
       -> <form ...><input _csrf ...>&lt;input name=&quot;...   ESCAPED GARBAGE

   The `tag_string` case is the worse-looking one — it returns `String`, so the
   contextual escaper treats it as untrusted text and renders a visible chunk of
   escaped markup on the page. The `tag` case returns `IOList`, which passes
   through unescaped and duplicates SILENTLY, which is the more dangerous of the
   two.

   Inside a ~H template with `conn` in scope, write the bare form tag and let
   the injection do it. Explicit token helpers are for markup built OUTSIDE ~H
   (see bastion's Form.render, which concatenates strings and is correct). *)

(** Is a `conn` binding lexically in scope at the expression currently being
    desugared?  Maintained imperatively (like [expr_err_ctx]) because
    [desugar_expr] doesn't thread an environment.  Scope owners save/restore
    via [with_conn_scope]. *)
let csrf_conn_in_scope : bool ref = ref false

(** Run [f] with [csrf_conn_in_scope] additionally enabled when [flag] holds,
    restoring the previous value afterwards (exception-safe). *)
let with_conn_scope (flag : bool) (f : unit -> 'a) : 'a =
  let saved = !csrf_conn_in_scope in
  csrf_conn_in_scope := saved || flag;
  Fun.protect ~finally:(fun () -> csrf_conn_in_scope := saved) f

(** Does pattern [p] bind a variable named [conn]? *)
let rec pat_binds_conn (p : pattern) : bool =
  match p with
  | PatWild _ | PatLit _ -> false
  | PatVar n -> n.txt = "conn"
  | PatCon (_, ps) -> List.exists pat_binds_conn ps
  | PatAtom (_, ps, _) -> List.exists pat_binds_conn ps
  | PatTuple (ps, _) -> List.exists pat_binds_conn ps
  | PatRecord (fields, _) -> List.exists (fun (_, fp) -> pat_binds_conn fp) fields
  | PatAs (inner, n, _) -> n.txt = "conn" || pat_binds_conn inner
  | PatOr (ps, _) -> List.exists pat_binds_conn ps

(** Does a function parameter bind [conn]? *)
let fn_param_binds_conn : fn_param -> bool = function
  | FPNamed p | FPDefault (p, _) -> p.param_name.txt = "conn"
  | FPPat pat -> pat_binds_conn pat

let params_bind_conn (ps : fn_param list) : bool =
  List.exists fn_param_binds_conn ps

let lam_params_bind_conn (ps : param list) : bool =
  List.exists (fun (p : param) -> p.param_name.txt = "conn") ps

(** Check whether [s] contains a [<form] opening tag whose [method] attribute
    specifies a mutating HTTP method (post, put, patch, delete).

    Returns [Some close_pos] where [close_pos] is the byte index just after
    the [>] closing the form opening tag, or [None].

    Detection is case-insensitive on both tag name and method value.
    Only the first mutating form tag within [s] is detected; call recursively
    on the remainder to handle multiple forms in one literal. *)
let csrf_form_close_pos (s : string) : int option =
  let lower = String.lowercase_ascii s in
  let len   = String.length lower in
  let is_boundary c =
    c = ' ' || c = '\t' || c = '\n' || c = '\r' || c = '>' in
  let find_sub needle hay from =
    let nlen = String.length needle in
    let hlen = String.length hay in
    let rec loop i =
      if i + nlen > hlen then -1
      else if String.sub hay i nlen = needle then i
      else loop (i + 1)
    in
    loop from
  in
  let mutating = ["post"; "put"; "patch"; "delete"] in
  let rec scan i =
    let fi = find_sub "<form" lower i in
    if fi = -1 then None
    else begin
      let after_tag = fi + 5 in
      (* Require whitespace or '>' immediately after "<form" so we don't
         match "<format", "<formdata", etc. *)
      if after_tag < len && not (is_boundary lower.[after_tag]) then
        scan (fi + 1)
      else begin
        (* Find the closing '>' of this form tag *)
        let rec find_close j =
          if j >= len then -1
          else if lower.[j] = '>' then j + 1
          else find_close (j + 1)
        in
        let close = find_close after_tag in
        if close = -1 then None
        else begin
          let tag_src = String.sub lower fi (close - fi) in
          let has_method = List.exists (fun m ->
            find_sub ("method=\"" ^ m ^ "\"") tag_src 0 >= 0 ||
            find_sub ("method='" ^ m ^ "'") tag_src 0 >= 0 ||
            find_sub ("method=" ^ m) tag_src 0 >= 0
          ) mutating in
          if has_method then Some close
          else scan (fi + 1)
        end
      end
    end
  in
  scan 0

(** Diagnostic sink for expression-level desugar errors.

    [desugar_expr] is public API called without an error context by the
    REPL and other tools, so [desugar_module ~errors] communicates its
    context via this ref for the duration of the module pass.  When a
    caller-supplied context is installed, errors are reported through the
    standard [Errors] diagnostic machinery (positioned span, rendered by
    the drivers that check [has_errors]).  When no context was supplied,
    we raise the same positioned [ParseError] exception the parse path
    uses — loud failure, never silently-wrong desugared code. *)
let expr_err_ctx : Err.ctx option ref = ref None

let desugar_expr_error ~(sp : span) ?hint msg : unit =
  match !expr_err_ctx with
  | Some ctx ->
    Err.report ctx
      { severity = Err.Error; span = sp; message = msg; labels = [];
        notes = (match hint with Some h -> [h] | None -> []);
        code = None; fix = None }
  | None ->
    let pos = { Lexing.pos_fname = sp.file;
                pos_lnum = sp.start_line;
                pos_bol  = 0;
                pos_cnum = sp.start_col } in
    raise (March_errors.Errors.ParseError (msg, hint, pos))

(* Same sink, Warning severity. Unlike the error path this does NOT raise when
   no context is installed: a warning that aborts the REPL would be worse than
   the thing it warns about. *)
let desugar_expr_warning ~(sp : span) ?hint msg : unit =
  match !expr_err_ctx with
  | Some ctx ->
    Err.report ctx
      { severity = Err.Warning; span = sp; message = msg; labels = [];
        notes = (match hint with Some h -> [h] | None -> []);
        code = Some "redundant_csrf_token"; fix = None }
  | None -> ()

(** Inject CSRF hidden-input string expressions into a ~H parts list.

    For each [ELit (LitString s, _)] that contains a [<form method="post/...">]
    opening tag, split the literal at the closing [>] and insert an
    [EApp(CSRF.tag_string, [EVar "conn"])] call between the two halves.

    The injected call returns [String] (not IOList), so it is valid as an
    element in the [List(String)] passed to [IOList.from_strings].

    Only called when [csrf_conn_in_scope] holds — the caller guarantees a
    [conn] variable is lexically in scope (the standard Bastion convention
    for request-handler functions that use ~H templates). *)
(* Is this part an explicit CSRF token interpolation -- `${CSRF.tag(conn)}` or
   `${CSRF.tag_string(conn)}`? At this point in the pipeline a hole is still
   `to_string(inner)`; the contextual escaper is applied later.

   Matched EXACTLY (or as a dotted suffix of a module path), never as a loose
   substring. The asymmetry matters: a false negative leaves a duplicate token,
   which is ugly. A FALSE POSITIVE suppresses injection and leaves the form
   unprotected. So this errs towards not matching. *)
let is_explicit_csrf_token (e : expr) : bool =
  let is_token_name n =
    n = "CSRF.tag" || n = "CSRF.tag_string"
    || (let suffix s = String.length n > String.length s
                       && String.sub n (String.length n - String.length s)
                            (String.length s) = s in
        suffix ".CSRF.tag" || suffix ".CSRF.tag_string")
  in
  match e with
  | EApp (EVar { txt = "to_string"; _ }, [inner], _) ->
    (match inner with
     | EApp (EVar { txt; _ }, _, _) -> is_token_name txt
     | _ -> false)
  | EApp (EVar { txt; _ }, _, _) -> is_token_name txt
  | _ -> false

(* Does an explicit token appear inside THIS form -- after its opening tag and
   before the form ends?

   Scoped PER FORM on purpose. A template-wide check would be actively harmful:
   a template with two forms, only one carrying an explicit token, would lose
   injection on BOTH, turning a cosmetic duplicate into an unprotected form.
   Scanning stops at `</form` or at the next `<form`, so each form is judged on
   its own contents. *)
let explicit_token_in_this_form (after : string) (rest : expr list) : bool =
  let lower s = String.lowercase_ascii s in
  let ends_scope s =
    let l = lower s in
    let contains sub =
      let n = String.length l and m = String.length sub in
      let rec go i = i + m <= n && (String.sub l i m = sub || go (i + 1)) in
      m = 0 || go 0
    in
    contains "</form" || contains "<form"
  in
  if ends_scope after then false
  else
    let rec scan = function
      | [] -> false
      | ELit (LitString s, _) :: tl -> if ends_scope s then false else scan tl
      | p :: tl -> if is_explicit_csrf_token p then true else scan tl
    in
    scan rest

let inject_csrf_tokens (parts : expr list) (sp : span) : expr list =
  let v s = EVar { txt = s; span = sp } in
  let csrf_call = EApp (v "CSRF.tag_string", [v "conn"], sp) in
  let rec go = function
    | [] -> []
    | ELit (LitString s, lsp) :: rest ->
      (match csrf_form_close_pos s with
       | None -> ELit (LitString s, lsp) :: go rest
       | Some close_pos ->
         let before = String.sub s 0 close_pos in
         let after  = String.sub s close_pos (String.length s - close_pos) in
         if explicit_token_in_this_form after rest then begin
           (* The author wrote their own token in this form. Injecting as well
              would emit TWO hidden inputs -- silently, when the explicit call
              returns IOList. Skip, and say so: the explicit call is now
              redundant, and silence would leave the author believing it is
              load-bearing. *)
           desugar_expr_warning ~sp
             ~hint:("Remove the explicit token — ~H injects one automatically \
                     for a mutating <form> whenever `conn` is in scope.")
             "This <form> already interpolates a CSRF token, so ~H did not \
              inject one. Emitting both would put two hidden _csrf_token \
              inputs in the form.";
           ELit (LitString before, lsp)
           :: go (ELit (LitString after, lsp) :: rest)
         end else
           (* Recurse on the remainder to handle multiple forms in one literal *)
           ELit (LitString before, lsp)
           :: csrf_call
           :: go (ELit (LitString after, lsp) :: rest))
    | part :: rest ->
      part :: go rest
  in
  go parts



(** Build an IOList directly from the parts of an ~H sigil interpolation.

    Static string literals are kept as-is.  Dynamic parts (to_string calls)
    are wrapped in Html.escape for auto-escaping.

    Island tags ([<island name='Mod' props=${expr} />]) are recognised and
    replaced with [IslandView.island_ssr(...)] calls that perform SSR.

    Form tags with mutating methods ([<form method="post/put/patch/delete">])
    have a [CSRF.tag_string(conn)] call injected immediately after the opening
    tag — but only when a [conn] binding is lexically in scope (see the B16
    note above [csrf_conn_in_scope]).

    The result is:
      IOList.from_strings(["static1", Html.escape(to_string(e1)), "static2", ...])
    which produces a multi-segment IOList without building an intermediate
    concatenated string. *)
let html_interp_to_iolist (content : expr) (sp : span) : expr =
  let parts = decompose_concat content in
  (* First pass: replace <island> tags with IslandView calls *)
  let parts = process_island_tags parts sp in
  (* Second pass: inject CSRF tokens after mutating <form> opening tags —
     but ONLY when a `conn` binding is lexically in scope (B16: standalone
     templates must never see an injected unbound `conn`). *)
  let parts =
    if !csrf_conn_in_scope then inject_csrf_tokens parts sp else parts in
  (* Third pass: walk the FIXED chunks through the HTML context automaton and
     give each hole the escaper its parse context calls for.

     This is the whole point of the analysis, and it is entirely compile-time.
     Per Samuel et al. (arXiv:2605.16561v1) an interpolation is a single
     transition whose successor depends only on the predecessor context, never
     on the interpolated value; and ~H has no in-template control flow, so
     there are no join points and no fixed point. The context trajectory is
     therefore fully determined by the literal chunks, which are constants
     sitting right here. Nothing survives to runtime but a direct escaper call.

     Three things fall out of the walk:
     - the escaper id per hole (html in element content, a URL scheme
       allowlist at the start of an href, JS inside <script>, and so on);
     - SUBSTITUTIONS — an unquoted attribute value receiving a hole gets a
       quote inserted, and the automaton closes it on the way out, so
       `<div class=${x}>` emits `<div class="..."`>;
     - DIAGNOSTICS for holes no escaper can make safe (an attribute name, an
       element name, a comment interior). Those are hard errors: there is no
       encoding that makes an attacker-chosen attribute name safe. *)
  let tbl = Lazy.force March_ctxesc.Automaton.default in
  let ctx = ref March_ctxesc.Context.initial in
  let lit s psp = ELit (LitString s, psp) in
  let parts = List.concat_map (fun part ->
    match part with
    | ELit (LitString s, psp) ->
      (match March_ctxesc.Automaton.consume_literal tbl !ctx s with
       | Ok o -> ctx := o.March_ctxesc.Automaton.ctx; [lit o.March_ctxesc.Automaton.emit psp]
       | Error (msg, _off) ->
         desugar_expr_error ~sp:psp msg;
         [part])
    | EApp (EVar { txt = "to_string"; _ }, args, psp) ->
      let inner =
        match args with
        | [one] -> one
        | _ ->
          (* Unusual arity — keep the to_string call and escape its result. *)
          EApp (EVar { txt = "to_string"; span = psp }, args, psp)
      in
      (match March_ctxesc.Automaton.consume_interp tbl !ctx with
       | Ok (esc, subst, ctx') ->
         ctx := ctx';
         let id = March_ctxesc.Context.escaper_id esc in
         let call =
           EApp (EVar { txt = "html_escape_ctx"; span = psp },
                 [ELit (LitInt id, psp); inner], psp) in
         if subst = "" then [call] else [lit subst psp; call]
       | Error diag ->
         desugar_expr_error ~sp:psp
           ~hint:(Printf.sprintf
                    "This interpolation is %s. Move the dynamic part into a \
                     value position instead."
                    (March_ctxesc.Context.describe !ctx))
           diag;
         [part])
    | _ ->
      (* island_ssr / CSRF injections: markup that is only valid in element
         content. If the walk says we are anywhere else, the template is
         malformed in a way that would splice into a tag. *)
      (if (!ctx).March_ctxesc.Context.state <> March_ctxesc.Context.Pcdata then
         desugar_expr_error ~sp
           "A template fragment can only be inserted in element content, not \
            inside a tag or attribute.");
      [part]
  ) parts in
  (* A template must not end mid-tag, mid-attribute or mid-comment: whatever
     the caller concatenates next would splice into it, which is exactly the
     composition hazard this analysis exists to stop. *)
  if not (March_ctxesc.Automaton.is_valid_terminal !ctx) then
    desugar_expr_error ~sp
      (Printf.sprintf
         "This ~H template does not end in a well-formed state — it ends %s. \
          Anything concatenated after it would be spliced into that position."
         (March_ctxesc.Context.describe !ctx));
  (* Build the cons-list of parts.
     CRITICAL: every generated node must carry a DISTINCT span.  The
     typechecker records each expression's inferred type in a type_map keyed
     by its span, and the TIR lowerer reads that map to decide which ADT a
     bare constructor belongs to (`ty_of_span span` → "TypeName.Ctor").
     If the inner `Cons`/`Nil` nodes shared the sigil span with the outer
     `IOList.from_strings(...)` application, the application's result type
     (`IOList`) would clobber the list's `List(String)` type in the map, and
     every `Cons`/`Nil` would lower to the non-existent `IOList.Cons`/`Nil`
     tags — rendering the template as the empty string.  We derive a unique
     span per node by offsetting the columns so the map entries never collide
     while still pointing at (roughly) the sigil's source location. *)
  let uid = ref 1 in
  let uniq_span () =
    let n = !uid in
    incr uid;
    { sp with start_col = sp.start_col + n; end_col = sp.end_col + n }
  in
  let list_expr = List.fold_right (fun e acc ->
    let s = uniq_span () in
    ECon ({ txt = "Cons"; span = s }, [e; acc], s)
  ) parts (let s = uniq_span () in ECon ({ txt = "Nil"; span = s }, [], s)) in
  EApp (EVar { txt = "IOList.from_strings"; span = sp }, [list_expr], sp)

(* ---- Pipe desugaring ---- *)

(* ---- Predicate qualified-spelling flattening (Task 8 prototype) ────────

   NARROW SLICE ONLY — this does NOT run refinement predicates through the
   general expression desugarer.  It replicates *only* the dotted-path
   flattening [desugar_expr]'s own [EField] arm already applies to ordinary
   call heads (`List.length(_)` → the [EVar] `"List.length"` that
   [Refine_check.qualified_name]/the measure-alias machinery keys on), and
   nothing else: no pipe desugaring, no multi-head-fn desugaring, no
   conn-scope tracking, no sigil expansion, no ELetFn/ELetQ handling.
   Constructs that a predicate should never plausibly contain (ELam, ELetFn,
   ELetQ, ESend, ESpawn, EPipe, ESigil, EAssert, EDbg) are left untouched by
   the catch-all rather than risked through unrelated desugaring paths. *)
let rec flatten_pred_quals (e : expr) : expr =
  let go = flatten_pred_quals in
  match e with
  | EField (ex, name, sp) ->
    let rec flatten_module_path = function
      | ECon (mod_name, [], _) -> Some mod_name.txt
      | EField (inner, field, _) ->
        (match flatten_module_path inner with
         | Some prefix -> Some (prefix ^ "." ^ field.txt)
         | None -> None)
      | _ -> None
    in
    (match flatten_module_path ex with
     | Some prefix ->
       let qualified_txt = prefix ^ "." ^ name.txt in
       if String.length name.txt > 0 && Char.uppercase_ascii name.txt.[0] = name.txt.[0]
       then ECon ({ txt = qualified_txt; span = sp }, [], sp)
       else EVar { txt = qualified_txt; span = sp }
     | None -> EField (go ex, name, sp))
  | EApp (f, args, sp)      -> EApp (go f, List.map go args, sp)
  | ECon (n, args, sp)      -> ECon (n, List.map go args, sp)
  | ETuple (es, sp)         -> ETuple (List.map go es, sp)
  | EAtom (a, args, sp)     -> EAtom (a, List.map go args, sp)
  | EIf (c, t, f, sp)       -> EIf (go c, go t, go f, sp)
  | ECond (arms, sp)        ->
    ECond (List.map (fun (c, b) -> (go c, go b)) arms, sp)
  | EAnnot (ex, ty, sp)     -> EAnnot (go ex, ty, sp)
  | EMatch (s, brs, sp)     ->
    EMatch (go s,
            List.map (fun br ->
                { br with branch_guard = Option.map go br.branch_guard
                        ; branch_body  = go br.branch_body }) brs,
            sp)
  | EBlock (es, sp)         -> EBlock (List.map go es, sp)
  | ELet (b, sp)            -> ELet ({ b with bind_expr = go b.bind_expr }, sp)
  | ERecord (fs, sp)        ->
    ERecord (List.map (fun (n, e) -> (n, go e)) fs, sp)
  | ERecordUpdate (b, fs, sp) ->
    ERecordUpdate (go b, List.map (fun (n, e) -> (n, go e)) fs, sp)
  | ELit _ | EVar _ | EHole _ | EResultRef _ -> e
  | ELam _ | ELetFn _ | ELetQ _ | ESend _ | ESpawn _ | EPipe _ | ESigil _
  | EAssert _ | EDbg _ -> e

(** Structural [ty] walk whose ONLY effect is calling [flatten_pred_quals] on
    every [TyRefine] predicate it finds — mirrors [Desugar.respan_ty]'s shape
    (same constructor set) but respans nothing and touches nothing outside
    the predicate expression.  Wired into every site that carries a surface
    [ty] on the normal (non-derive) desugaring path: fn param/return types,
    `let`-binding annotations (both a block-level [ELet] and a top-level
    [DLet] — see [desugar_decl]'s `DLet` arm), `EAnnot`, and record/variant
    field types.  This is a SUPERSET of everywhere [Refine_check.warn_predicate_ty]
    itself recurses, not an exact match: it also walks a [DType]'s own
    field/variant types, which [Refine_check.warn_predicate_decls] deliberately
    does not (a refinement in a type DEFINITION is checked where the type is
    used, not at the definition site) — covering more than the warning needs
    is harmless, so the extra site stays. *)
let rec desugar_ty (t : ty) : ty =
  match t with
  | TyCon (n, args)    -> TyCon (n, List.map desugar_ty args)
  | TyVar _            -> t
  | TyArrow (a, b)     -> TyArrow (desugar_ty a, desugar_ty b)
  | TyTuple ts         -> TyTuple (List.map desugar_ty ts)
  | TyRecord fs        -> TyRecord (List.map (fun (n, t) -> (n, desugar_ty t)) fs)
  | TyLinear (l, t)    -> TyLinear (l, desugar_ty t)
  | TyNat _            -> t
  | TyNatOp (op, a, b) -> TyNatOp (op, desugar_ty a, desugar_ty b)
  | TyChan _           -> t
  | TyRefine (t, n, e) -> TyRefine (desugar_ty t, n, flatten_pred_quals e)

(** Desugar [EPipe (l, r, sp)] → [EApp (r, [l], sp)].
    Works recursively; all other nodes are walked to catch nested pipes. *)
let rec desugar_expr (e : expr) : expr =
  match e with
  (* --- Pipe: x |> f(a,b)  ⟶  f(x,a,b) --- *)
  (* Elixir-style pipe: the LHS becomes the FIRST argument of the RHS.
     When the RHS is already an application, prepend the LHS to its
     argument list so we get a single saturated call instead of a
     curried (partial-apply) chain. *)
  | EPipe (l, r, sp) ->
    let l' = desugar_expr l in
    let r' = desugar_expr r in
    (match r' with
     | EApp (f, args, _) -> EApp (f, l' :: args, sp)
     | ECond (arms, cond_sp) ->
       (* x |> match do Pat -> body end  ⟶  match x do Pat -> body end
          Convert cond-arm exprs to patterns for the LHS scrutinee. *)
       let rec expr_to_pat e = match e with
         | ECon (name, args, _) -> PatCon (name, List.map expr_to_pat args)
         | EVar name -> PatVar name
         | ELit (lit, litsp) -> PatLit (lit, litsp)
         | EAtom (a, args, epsp) -> PatAtom (a, List.map expr_to_pat args, epsp)
         | ETuple (es, epsp) -> PatTuple (List.map expr_to_pat es, epsp)
         | _ ->
           desugar_expr_error ~sp
             ~hint:"Only constructors, variables, literals, and tuples are \
                    allowed as match arms in a `|>` pipe expression."
             "pipe-to-match: expression cannot be used as a pattern here.";
           (* Error recovery (context path): a wildcard keeps the branch
              well-formed; compilation aborts on the reported error. *)
           PatWild sp
       in
       let branches = List.map (fun (cond_e, body) ->
           { branch_pat = expr_to_pat cond_e
           ; branch_guard = None
           ; branch_body = body }) arms in
       EMatch (l', branches, cond_sp)
     | EMatch (_, branches, match_sp) ->
       (* B6: `x |> (match scrut do ... end)` used to silently DISCARD
          `scrut` and match on `x` instead — verified silent wrong code.
          The supported scrutinee-less form (`x |> (match do ... end)`)
          parses as ECond and is handled above; an explicit scrutinee
          here is always a mistake, so report it. *)
       desugar_expr_error ~sp:match_sp
         ~hint:"The piped value becomes the scrutinee. Use \
                `x |> (match do pat -> ... end)` (no scrutinee), or write \
                `match x do ... end` directly."
         "piping into a match discards its scrutinee; write `match x do ... end` instead";
       (* Error recovery (context path): keep the historical shape so
          downstream passes see a well-formed tree; compilation aborts on
          the reported error. *)
       EMatch (l', branches, match_sp)
     | _ -> EApp (r', [l'], sp))

  (* --- Recurse into all other nodes --- *)
  | ELit _ | EVar _ | EHole _ | EResultRef _ -> e
  | EDbg (None, _) -> e
  | EDbg (Some inner, sp) -> EDbg (Some (desugar_expr inner), sp)

  (* Collapse a `++` chain into three-way concats before the generic EApp path.
     `a ++ b ++ c ++ d ++ e` parses left-deep, so evaluating it link by link
     allocates k-1 intermediates and re-copies the growing prefix at each one --
     O(k^2) bytes for k parts.  Folding in groups of three brings that to
     ceil((k-1)/2) allocations, halving both at k=3 and k=5.

     Placed HERE, in desugar, rather than in the parser or in TIR:
       - the parser is the wrong place; PR #90 showed that changing the AST
         interpolation shape silently broke the formatter's `"${...}"`
         reconstruction and disabled `~H` HTML escaping;
       - the formatter runs on the PARSED module, before desugar, so it never
         sees this rewrite;
       - `~H` lowering (html_interp_to_iolist) runs in the ESigil arm, which
         decomposes the chain itself and never reaches this arm;
       - TIR is ANF, so by then the chain is let-bound temporaries with dec_rc
         interleaved -- a liveness analysis rather than a tree rewrite.

     Two-part chains are left alone: `a ++ b` is already one allocation and one
     copy pass, so there is nothing to save. *)
  | EApp (EVar { txt = "++"; _ }, [_; _], sp) when concat_chain_len e >= 3 ->
    let parts = List.map desugar_expr (decompose_concat e) in
    fold_concat3 parts sp

  | EApp (f, args, sp) ->
    let f' = desugar_expr f in
    let args' = List.map desugar_expr args in
    (* When a qualified constructor reference (e.g. Result.Error, desugared
       from EField to ECon("Result.Error",[],_)) is applied to arguments,
       fold the args directly into the ECon so the typechecker and eval see a
       proper constructor application rather than a function call. *)
    (match f' with
     | ECon (name, [], _) when String.contains name.txt '.' ->
       ECon (name, args', sp)
     | _ ->
       EApp (f', args', sp))

  | ECon (name, args, sp) ->
    ECon (name, List.map desugar_expr args, sp)

  | ELam (ps, body, sp) ->
    let body' =
      with_conn_scope (lam_params_bind_conn ps) (fun () -> desugar_expr body) in
    ELam (ps, body', sp)

  | EBlock (es, sp) ->
    (* `let conn = ...` brings `conn` into scope for the REST of the block —
       walk statements in order, enabling the CSRF conn gate once a binding
       of `conn` has been seen. Restore on exit (block-scoped). *)
    with_conn_scope false (fun () ->
      (* Explicit recursion: statement order matters for the scope scan
         (List.map's application order is unspecified). *)
      let rec go acc = function
        | [] -> List.rev acc
        | stmt :: rest ->
          let stmt' = desugar_expr stmt in
          (match stmt' with
           | ELet (b, _) when pat_binds_conn b.bind_pat ->
             csrf_conn_in_scope := true
           | _ -> ());
          go (stmt' :: acc) rest
      in
      EBlock (go [] es, sp))

  | ELet (b, sp) ->
    ELet ({ b with bind_expr = desugar_expr b.bind_expr
                  ; bind_ty  = Option.map desugar_ty b.bind_ty }, sp)

  | EMatch (scrut, branches, sp) ->
    let branches' = List.map (fun br ->
        with_conn_scope (pat_binds_conn br.branch_pat) (fun () ->
          { br with branch_guard = Option.map desugar_expr br.branch_guard
                  ; branch_body  = desugar_expr br.branch_body })) branches in
    EMatch (desugar_expr scrut, branches', sp)

  | ETuple (es, sp) ->
    ETuple (List.map desugar_expr es, sp)

  | ERecord (fields, sp) ->
    ERecord (List.map (fun (n, ex) -> (n, desugar_expr ex)) fields, sp)

  | ERecordUpdate (base, fields, sp) ->
    ERecordUpdate (desugar_expr base,
                   List.map (fun (n, ex) -> (n, desugar_expr ex)) fields,
                   sp)

  | EField (ex, name, sp) ->
    (* Desugar module member access: A.B.fn(...) → EVar "A.B.fn"
       If the base is a chain of ECon/EField that looks like a module path,
       flatten it into a single qualified name.
       When the field name is uppercase (a constructor), emit ECon so that the
       typechecker resolves it through the constructor table rather than vars. *)
    let rec flatten_module_path = function
      | ECon (mod_name, [], _) -> Some mod_name.txt
      | EField (inner, field, _) ->
        (match flatten_module_path inner with
         | Some prefix -> Some (prefix ^ "." ^ field.txt)
         | None -> None)
      | _ -> None
    in
    (match flatten_module_path ex with
     | Some prefix ->
       let qualified_txt = prefix ^ "." ^ name.txt in
       if String.length name.txt > 0 && Char.uppercase_ascii name.txt.[0] = name.txt.[0]
       then ECon ({ txt = qualified_txt; span = sp }, [], sp)
       else EVar { txt = qualified_txt; span = sp }
     | None -> EField (desugar_expr ex, name, sp))

  | EIf (cond, t, f, sp) ->
    EIf (desugar_expr cond, desugar_expr t, desugar_expr f, sp)

  | ECond (arms, sp) ->
    ECond (List.map (fun (cond_e, body) -> (desugar_expr cond_e, desugar_expr body)) arms, sp)

  | EAnnot (ex, ty, sp) ->
    EAnnot (desugar_expr ex, desugar_ty ty, sp)

  | EAtom (a, args, sp) ->
    EAtom (a, List.map desugar_expr args, sp)

  | ESend (cap, msg, sp) ->
    ESend (desugar_expr cap, desugar_expr msg, sp)

  | ESpawn (actor, sp) ->
    ESpawn (desugar_expr actor, sp)

  | ELetFn (name, params, ret_ty, body, sp) ->
    let body' =
      with_conn_scope (lam_params_bind_conn params)
        (fun () -> desugar_expr body) in
    ELetFn (name, params, ret_ty, body', sp)

  | ELetQ (p, result, cont, sp) ->
    (* `let? conn = ...` binds `conn` for the continuation only. *)
    let result' = desugar_expr result in
    let cont' =
      with_conn_scope (pat_binds_conn p) (fun () -> desugar_expr cont) in
    ELetQ (p, result', cont', sp)

  | EAssert (e, sp) ->
    EAssert (desugar_expr e, sp)

  | ESigil (name, content, sp) ->
    let content' = desugar_expr content in
    if name = "H" then
      (* Desugar ~H"..." → IOList.from_strings([parts...])
         Decompose the ++ chain into segments, wrap dynamic parts in
         Html.escape, and build a multi-segment IOList directly. *)
      html_interp_to_iolist content' sp
    else begin
      (* Other sigils: ~R"..." → Sigil.r(content), ~xml"..." → Sigil.xml(content), etc.
      
         These hand the handler a single ALREADY-CONCATENATED string, which it
         then PARSES. So an interpolated value is spliced into the source text
         before parsing and can change the parsed STRUCTURE, not just a value
         in it. Demonstrated on every shipped handler:

           ~xml"<user><name>${v}</name></user>"
             v = "</name><admin>true</admin><name>"
             -> <user><name/><admin>true</admin><name/></user>   3 children

           ~toml"name = \"${v}\""   -> injects a whole new key
           ~yaml"name: ${v}"        -> injects a whole new key

         ~H solves its version of this by escaping per parse context, but ~H
         must emit TEXT and has no alternative. These sigils produce a parsed
         STRUCTURE, so the sound fix is to supply values as data rather than as
         source text — the parameterisation analogue — not a second family of
         escapers. YAML in particular cannot be made safe by escaping in any way
         worth trusting.

         Until a handler offers that, interpolation here is refused. It is used
         nowhere: across the compiler, bastion, forgepm, conduit, depot and
         march_doc there are six uses of these sigils, all in this repo's own
         tests, and NONE with interpolation. *)
      let parts = decompose_concat content' in
      let has_hole =
        List.exists
          (function
            | EApp (EVar { txt = "to_string"; _ }, _, _) -> true
            | _ -> false)
          parts
      in
      if has_hole then
        desugar_expr_error ~sp
          ~hint:("Build the value programmatically instead — e.g. parse a "
                 ^ "literal document and set fields on it — so the "
                 ^ "interpolated value is data rather than source text.")
          (Printf.sprintf
             "Cannot interpolate into a ~%s sigil. Its content is parsed, so an \
              interpolated value would be spliced into the source text and could \
              change the parsed structure rather than appear as a value in it."
             name);
      let fn_name = "Sigil." ^ String.lowercase_ascii name in
      EApp (EVar { txt = fn_name; span = sp }, [content'], sp)
    end

(* ---- Multi-head fn desugaring ---- *)

(** Desugar a [fn_def] that may have multiple clauses (or pattern params)
    into one that always has exactly one clause with only [FPNamed] params.

    Strategy:
    - Count params by looking at the first clause (all clauses must have
      the same arity — a later validation pass can enforce this).
    - Generate fresh arg names [__arg0 … __argN].
    - Build a tuple scrutinee if arity > 1, otherwise use the single arg.
    - Build one [branch] per clause, turning its [fn_param list] into a
      [PatTuple] (or direct pattern for arity 1), plus the clause guard.
    - The body of the merged clause is [EMatch(scrutinee, branches)].
    - If there is only one clause AND it is trivial (all named params, no
      guard), skip the match and return as-is — no-op for simple functions. *)

(** Apply [desugar_ty] to every param type and the return type of [def],
    without touching bodies/guards/params otherwise — a pure pre-pass so the
    branches below (which only ever rewrite bodies/guards) don't need their
    own copy of this. *)
let desugar_fn_def_tys (def : fn_def) : fn_def =
  let desugar_fn_param = function
    | FPNamed p        -> FPNamed { p with param_ty = Option.map desugar_ty p.param_ty }
    | FPDefault (p, e) -> FPDefault ({ p with param_ty = Option.map desugar_ty p.param_ty }, e)
    | FPPat _ as p     -> p
  in
  { def with
    fn_ret_ty  = Option.map desugar_ty def.fn_ret_ty;
    fn_clauses = List.map (fun c -> { c with fc_params = List.map desugar_fn_param c.fc_params })
        def.fn_clauses }

let desugar_fn_def (def : fn_def) (fn_span : span) : fn_def =
  let def = desugar_fn_def_tys def in
  let clauses = def.fn_clauses in
  match clauses with
  | [] -> def   (* degenerate — validation pass will catch this *)

  | [only] when clause_is_trivial only ->
    (* Fast path: single clause, all named params, no guard — nothing to do
       except recursively desugar the body. *)
    let only' =
      with_conn_scope (params_bind_conn only.fc_params) (fun () ->
        { only with fc_body = desugar_expr only.fc_body
                  ; fc_guard = Option.map desugar_expr only.fc_guard })
    in
    { def with fn_clauses = [only'] }

  | [only]
    when (only.fc_guard = None || is_class_constraint_guard only.fc_guard)
      && List.for_all
           (function FPNamed _ | FPPat (PatVar _) | FPDefault _ -> true
                   | FPPat _ -> false)
           only.fc_params ->
    (* Fast path for a single clause whose only "non-trivial" params are
       [FPDefault] (e.g. a default-arg function defined inside a nested
       module, which [expand_defaults_decl] does not reach — it only runs on
       top-level decls).  Strip the defaults to plain named params and take
       the fast path, so the function keeps its real signature instead of
       being routed through the general param-tuple [EMatch] path.

       The general path boxes every parameter into a synthesised tuple
       (`let $t = (a, …) in case $t of Tuple(…)`).  When such a function also
       takes a type-erased closure parameter, that tuple adapter mismanages
       the closure's refcount and frees it before its call — a use-after-free
       (observed in bastion's Form.Wrapper.render via CSRF.tag). Top-level
       default-arg fns avoid this because they ARE expanded (their `$N`
       arities have plain named params); this brings nested ones in line.

       Default *values* are dropped here, matching the pre-existing behaviour
       of the general path (the synthesised tuple match also requires every
       argument to be supplied — nested default-arg dispatch was never wired
       up). *)
    let strip = function FPDefault (p, _) -> FPNamed p | other -> other in
    let only' =
      with_conn_scope (params_bind_conn only.fc_params) (fun () ->
        { only with fc_params = List.map strip only.fc_params
                  ; fc_body = desugar_expr only.fc_body
                  ; fc_guard = Option.map desugar_expr only.fc_guard })
    in
    { def with fn_clauses = [only'] }

  | first :: _ ->
    (* General path: synthesise fresh arg names based on first clause's arity. *)
    let arity = List.length first.fc_params in
    let arg_names = List.init arity fresh_arg_name in

    (* Build the scrutinee expression from the generated arg names. *)
    let scrutinee : expr =
      match arg_names with
      | [n] -> EVar n
      | ns  -> ETuple (List.map (fun n -> EVar n) ns, fn_span)
    in

    (* Convert one clause into a match branch. *)
    let clause_to_branch (clause : fn_clause) : branch =
      let patterns = List.map fn_param_to_pattern clause.fc_params in
      let pat : pattern =
        match patterns with
        | [p] -> p
        | ps  -> PatTuple (ps, clause.fc_span)
      in
      with_conn_scope (params_bind_conn clause.fc_params) (fun () ->
        { branch_pat   = pat
        ; branch_guard = Option.map desugar_expr clause.fc_guard
        ; branch_body  = desugar_expr clause.fc_body
        })
    in

    let branches = List.map clause_to_branch clauses in

    (* Build the merged body: match (arg0, …, argN) do … end *)
    let body = EMatch (scrutinee, branches, fn_span) in

    (* Single merged clause with all FPNamed params *)
    let merged_clause : fn_clause =
      { fc_params = List.map mk_named_param arg_names
      ; fc_guard  = None
      ; fc_body   = body
      ; fc_span   = fn_span
      }
    in
    { def with fn_clauses = [merged_clause] }

(* ---- Declaration desugaring ---- *)

let rec desugar_decl (d : decl) : decl =
  match d with
  | DFn (def, sp) ->
    DFn (desugar_fn_def def sp, sp)

  | DLet (vis, b, sp) ->
    DLet (vis, { b with bind_expr = desugar_expr b.bind_expr
                       ; bind_ty  = Option.map desugar_ty b.bind_ty }, sp)

  | DType (vis, name, tparams, td, sp) ->
    (* Field/variant-arg types can themselves carry `TyRefine` predicates
       (`type T = { x : {Int | x > 0} }`) — flatten qualified spellings
       there the same way fn signatures are handled above. *)
    let td' = match td with
      | TDAlias t    -> TDAlias (desugar_ty t)
      | TDVariant vs -> TDVariant (List.map (fun v -> { v with var_args = List.map desugar_ty v.var_args }) vs)
      | TDRecord fs  -> TDRecord (List.map (fun f -> { f with fld_ty = desugar_ty f.fld_ty }) fs)
    in
    DType (vis, name, tparams, td', sp)

  | DActor (vis, name, actor, sp) ->
    let init'     = desugar_expr actor.actor_init in
    let handlers' = List.map (fun h ->
        { h with ah_body = desugar_expr h.ah_body }) actor.actor_handlers in
    DActor (vis, name, { actor with actor_init = init'; actor_handlers = handlers' }, sp)

  | DMod (name, vis, decls, sp) ->
    DMod (name, vis, List.map desugar_decl decls, sp)

  | DInterface (idef, sp) ->
    (* Desugar default method bodies *)
    let methods' = List.map (fun (m : method_decl) ->
        { m with md_default = Option.map desugar_expr m.md_default }
      ) idef.iface_methods in
    DInterface ({ idef with iface_methods = methods' }, sp)

  | DImpl (idef, sp) ->
    (* Desugar each provided method's fn_def *)
    let methods' = List.map (fun (name, def) ->
        (name, desugar_fn_def def sp)
      ) idef.impl_methods in
    DImpl ({ idef with impl_methods = methods' }, sp)

  | DProtocol _ | DSig _ | DExtern _ | DUse _ | DAlias _ | DNeeds _ | DProofCap _
  | DAlwaysLinearType _ | DTransitions _ | DOpts _ ->
    d

  | DDeriving _ ->
    (* DDeriving is expanded by desugar_module before desugar_decl is called *)
    d

  | DSatisfy _ ->
    (* DSatisfy is expanded by desugar_module before desugar_decl is called *)
    d

  | DTest (tdef, sp) ->
    DTest ({ tdef with test_body = desugar_expr tdef.test_body }, sp)

  | DDescribe (name, decls, sp) ->
    DDescribe (name, List.map desugar_decl decls, sp)

  | DSetup (body, sp) ->
    DSetup (desugar_expr body, sp)

  | DSetupAll (body, sp) ->
    DSetupAll (desugar_expr body, sp)

  | DApp (adef, sp) ->
    (* Desugar: DApp → private __app_init__ function that returns a record
       { spec, on_start, on_stop }.  The interpreter detects __app_init__ in
       the environment and uses it to drive the supervisor lifecycle. *)
    let body' = desugar_expr adef.app_body in
    let on_start' = Option.map desugar_expr adef.app_on_start in
    let on_stop'  = Option.map desugar_expr adef.app_on_stop  in
    (* Build: fn __app_init__() -> { spec = <body>, on_start = <fn>, on_stop = <fn> } *)
    let none_val = ECon ({ txt = "None"; span = sp }, [], sp) in
    let wrap_opt = function
      | None   -> none_val
      | Some e -> ECon ({ txt = "Some"; span = sp }, [ELam ([], e, sp)], sp)
    in
    (* Annotate the spec field so the type checker verifies the body
       returns SupervisorSpec, rather than silently accepting any type. *)
    let spec_ty = TyCon ({ txt = "SupervisorSpec"; span = sp }, []) in
    let annotated_body = EAnnot (body', spec_ty, sp) in
    let result_expr = ERecord (
      [ ({ txt = "spec";     span = sp }, annotated_body)
      ; ({ txt = "on_start"; span = sp }, wrap_opt on_start')
      ; ({ txt = "on_stop";  span = sp }, wrap_opt on_stop')
      ], sp) in
    let init_fn : fn_def = {
      fn_name    = { txt = "__app_init__"; span = sp };
      fn_vis     = Private;
      fn_doc     = None;
      fn_attrs   = [];
      fn_ret_ty  = None;
      fn_bounds  = [];
      fn_clauses = [{
        fc_params = [];
        fc_guard  = None;
        fc_body   = result_expr;
        fc_span   = sp;
      }];
    } in
    DFn (init_fn, sp)

(* ---- Module entry point ---- *)

(** Collect interface definitions from a declaration list (one level deep). *)
let collect_interfaces (decls : decl list) : (string * interface_def) list =
  List.filter_map (function
    | DInterface (idef, _) -> Some (idef.iface_name.txt, idef)
    | _ -> None
  ) decls

(** Inject default methods from the interface into an impl that omits them. *)
let inject_defaults (interfaces : (string * interface_def) list) (d : decl) : decl =
  match d with
  | DImpl (idef, sp) ->
    (match List.assoc_opt idef.impl_iface.txt interfaces with
     | None -> d
     | Some iface ->
       let provided_names = List.map (fun (n, _) -> n.txt) idef.impl_methods in
       let extra_methods = List.filter_map (fun (m : method_decl) ->
           if List.mem m.md_name.txt provided_names then None
           else match m.md_default with
             | None -> None
             | Some default_expr ->
               (* Synthesise a fn_def for the default method.  The default body
                  has the method's FULL arrow type (`a -> a -> Bool`), so it is
                  almost always a lambda `fn x y -> ...`.  FLATTEN that lambda's
                  parameters into the synthesised fn's OWN parameters, rather
                  than wrapping it in a zero-param clause that merely RETURNS the
                  lambda.  Otherwise the call `neqx(a, b)` compiles to a 2-arg
                  call of a 0-param function: the args are dropped, the returned
                  closure is never applied, and its pointer is used as the result
                  — so the method always yields the same answer regardless of its
                  arguments (item 283; the interpreter applied the closure and
                  so was correct).  A non-lambda default (a bare value method)
                  keeps the zero-param clause. *)
               let desugared = desugar_expr default_expr in
               let clause_params, clause_body =
                 match desugared with
                 | ELam (ps, body, _) -> List.map (fun p -> FPNamed p) ps, body
                 | other -> [], other
               in
               let fn_def : fn_def = {
                 fn_name = m.md_name;
                 fn_vis = Private;
                 fn_doc = None;
                 fn_attrs = [];
                 fn_ret_ty = None;
                 fn_clauses = [{
                   fc_params = clause_params;
                   fc_guard = None;
                   fc_body = clause_body;
                   fc_span = m.md_name.span;
                 }];
                 fn_bounds = [];
               } in
               Some (m.md_name, fn_def)
         ) iface.iface_methods
       in
       if extra_methods = [] then d
       else DImpl ({ idef with impl_methods = idef.impl_methods @ extra_methods }, sp))
  | _ -> d

(* ── Derive expansion ──────────────────────────────────────────────────── *)

(** Collect DType definitions: name → (type_params, type_def). *)
let collect_type_defs (decls : decl list) : (string * (name list * type_def)) list =
  List.filter_map (function
    | DType (_, name, tparams, td, _) -> Some (name.txt, (tparams, td))
    | _ -> None
  ) decls

(** Make a name with a dummy span. *)
let mk_name txt = { txt; span = dummy_span }

(** Make a single-clause fn_def with named params and a body expression. *)
let mk_fn_def name params body : fn_def =
  { fn_name   = mk_name name;
    fn_vis     = Private;
    fn_doc     = None;
    fn_attrs   = [];
    fn_ret_ty  = None;
    fn_bounds  = [];
    fn_clauses = [{
      fc_params = List.map (fun p ->
        FPNamed { param_name = mk_name p; param_ty = None; param_lin = Unrestricted }
      ) params;
      fc_guard  = None;
      fc_body   = body;
      fc_span   = dummy_span;
    }] }

(* ── Derive-expansion span uniquification ──────────────────────────────

   Every AST node minted by [derive_impl] used to carry the SAME [dummy_span].
   The typechecker records inferred types keyed by span ([env.type_map],
   [Hashtbl.replace] — last write wins) and TIR lowering reads them back
   ([Lower_state.ty_of_span]), so a shared span made every derived node
   collide on ONE table entry: lowering saw arbitrary garbage types for
   derived params and body exprs (e.g. [Ord$Wrap.compare(a : (Wrap) -> Int)]),
   and the LLVM backend then picked the wrong representation strategy for the
   receiver match — SIGSEGV / non-exhaustive panic on Newtype-repr variant
   types (P1 in specs/todos.md).  Rewriting every span inside the generated
   decls to a fresh structurally-unique key gives each node its own type_map
   entry, so derived methods typecheck+lower exactly like hand-written impls.
   The file stays "<none>" so span-based synthetic-code filters (coverage's
   file check, the LSP's [= dummy_span] checks compare the whole record and
   never map "<none>" spans onto a document) keep treating derived code as
   synthetic. *)

let _synthetic_span_counter = ref 0

let fresh_synthetic_span () : span =
  incr _synthetic_span_counter;
  { file = "<none>"; start_line = !_synthetic_span_counter; start_col = 0;
    end_line = !_synthetic_span_counter; end_col = 0 }

let respan_name (n : name) : name = { n with span = fresh_synthetic_span () }

let rec respan_pat (p : pattern) : pattern =
  match p with
  | PatWild _            -> PatWild (fresh_synthetic_span ())
  | PatVar n             -> PatVar (respan_name n)
  | PatCon (n, subs)     -> PatCon (respan_name n, List.map respan_pat subs)
  | PatAtom (s, subs, _) -> PatAtom (s, List.map respan_pat subs, fresh_synthetic_span ())
  | PatTuple (subs, _)   -> PatTuple (List.map respan_pat subs, fresh_synthetic_span ())
  | PatLit (l, _)        -> PatLit (l, fresh_synthetic_span ())
  | PatRecord (fs, _)    ->
    PatRecord (List.map (fun (n, p) -> (respan_name n, respan_pat p)) fs,
               fresh_synthetic_span ())
  | PatAs (p, n, _)      -> PatAs (respan_pat p, respan_name n, fresh_synthetic_span ())
  | PatOr (ps, _)        -> PatOr (List.map respan_pat ps, fresh_synthetic_span ())

let rec respan_ty (t : ty) : ty =
  match t with
  | TyCon (n, args)      -> TyCon (respan_name n, List.map respan_ty args)
  | TyVar n              -> TyVar (respan_name n)
  | TyArrow (a, b)       -> TyArrow (respan_ty a, respan_ty b)
  | TyTuple ts           -> TyTuple (List.map respan_ty ts)
  | TyRecord fs          -> TyRecord (List.map (fun (n, t) -> (respan_name n, respan_ty t)) fs)
  | TyLinear (l, t)      -> TyLinear (l, respan_ty t)
  | TyNat _ as t         -> t
  | TyNatOp (op, a, b)   -> TyNatOp (op, respan_ty a, respan_ty b)
  | TyChan (a, b)        -> TyChan (respan_name a, respan_name b)
  | TyRefine (t, n, e)   -> TyRefine (respan_ty t, Option.map respan_name n, respan_expr e)

and respan_expr (e : expr) : expr =
  match e with
  | ELit (l, _)          -> ELit (l, fresh_synthetic_span ())
  | EVar n               -> EVar (respan_name n)
  | EApp (f, args, _)    -> EApp (respan_expr f, List.map respan_expr args, fresh_synthetic_span ())
  | ECon (n, args, _)    -> ECon (respan_name n, List.map respan_expr args, fresh_synthetic_span ())
  | ELam (ps, body, _)   -> ELam (List.map respan_param ps, respan_expr body, fresh_synthetic_span ())
  | EBlock (es, _)       -> EBlock (List.map respan_expr es, fresh_synthetic_span ())
  | ELet (b, _)          -> ELet (respan_binding b, fresh_synthetic_span ())
  | EMatch (s, brs, _)   -> EMatch (respan_expr s, List.map respan_branch brs, fresh_synthetic_span ())
  | ETuple (es, _)       -> ETuple (List.map respan_expr es, fresh_synthetic_span ())
  | ERecord (fs, _)      ->
    ERecord (List.map (fun (n, e) -> (respan_name n, respan_expr e)) fs, fresh_synthetic_span ())
  | ERecordUpdate (e, fs, _) ->
    ERecordUpdate (respan_expr e,
                   List.map (fun (n, e) -> (respan_name n, respan_expr e)) fs,
                   fresh_synthetic_span ())
  | EField (e, n, _)     -> EField (respan_expr e, respan_name n, fresh_synthetic_span ())
  | EIf (c, t, f, _)     -> EIf (respan_expr c, respan_expr t, respan_expr f, fresh_synthetic_span ())
  | ECond (arms, _)      ->
    ECond (List.map (fun (c, b) -> (respan_expr c, respan_expr b)) arms, fresh_synthetic_span ())
  | EPipe (a, b, _)      -> EPipe (respan_expr a, respan_expr b, fresh_synthetic_span ())
  | EAnnot (e, t, _)     -> EAnnot (respan_expr e, respan_ty t, fresh_synthetic_span ())
  | EHole (n, _)         -> EHole (Option.map respan_name n, fresh_synthetic_span ())
  | EAtom (s, args, _)   -> EAtom (s, List.map respan_expr args, fresh_synthetic_span ())
  | ESend (a, b, _)      -> ESend (respan_expr a, respan_expr b, fresh_synthetic_span ())
  | ESpawn (e, _)        -> ESpawn (respan_expr e, fresh_synthetic_span ())
  | EResultRef _ as e    -> e
  | EDbg (e, _)          -> EDbg (Option.map respan_expr e, fresh_synthetic_span ())
  | ELetFn (n, ps, rt, body, _) ->
    ELetFn (respan_name n, List.map respan_param ps, Option.map respan_ty rt,
            respan_expr body, fresh_synthetic_span ())
  | ELetQ (p, e1, e2, _) -> ELetQ (respan_pat p, respan_expr e1, respan_expr e2, fresh_synthetic_span ())
  | EAssert (e, _)       -> EAssert (respan_expr e, fresh_synthetic_span ())
  | ESigil (s, e, _)     -> ESigil (s, respan_expr e, fresh_synthetic_span ())

and respan_param (p : param) : param =
  { param_name = respan_name p.param_name;
    param_ty   = Option.map respan_ty p.param_ty;
    param_lin  = p.param_lin }

and respan_binding (b : binding) : binding =
  { bind_pat  = respan_pat b.bind_pat;
    bind_ty   = Option.map respan_ty b.bind_ty;
    bind_lin  = b.bind_lin;
    bind_expr = respan_expr b.bind_expr }

and respan_branch (br : branch) : branch =
  { branch_pat   = respan_pat br.branch_pat;
    branch_guard = Option.map respan_expr br.branch_guard;
    branch_body  = respan_expr br.branch_body }

let respan_fn_param : fn_param -> fn_param = function
  | FPPat p          -> FPPat (respan_pat p)
  | FPNamed p        -> FPNamed (respan_param p)
  | FPDefault (p, e) -> FPDefault (respan_param p, respan_expr e)

let respan_fn_def (fd : fn_def) : fn_def =
  { fd with
    fn_name    = respan_name fd.fn_name;
    fn_ret_ty  = Option.map respan_ty fd.fn_ret_ty;
    fn_bounds  = List.map (fun (n, t) -> (respan_name n, respan_ty t)) fd.fn_bounds;
    fn_clauses = List.map (fun c ->
        { fc_params = List.map respan_fn_param c.fc_params;
          fc_guard  = Option.map respan_expr c.fc_guard;
          fc_body   = respan_expr c.fc_body;
          fc_span   = fresh_synthetic_span () }) fd.fn_clauses }

(** Uniquify every span inside a derive-generated decl (the decl's own
    top-level span — the derive site — is kept: it is a real user span used
    for error attribution).  [derive_impl] only emits [DImpl] and [DFn]
    (Json); any other decl kind passes through unchanged, which merely keeps
    today's shared-dummy-span behavior for it. *)
let respan_derived_decl (d : decl) : decl =
  match d with
  | DImpl (idef, sp) ->
    DImpl ({ impl_iface       = respan_name idef.impl_iface;
             impl_ty          = respan_ty idef.impl_ty;
             impl_constraints = List.map (fun (n, tys) ->
                 (respan_name n, List.map respan_ty tys)) idef.impl_constraints;
             impl_assoc_types = List.map (fun (n, t) ->
                 (respan_name n, respan_ty t)) idef.impl_assoc_types;
             impl_methods     = List.map (fun (n, fd) ->
                 (respan_name n, respan_fn_def fd)) idef.impl_methods },
           sp)
  | DFn (fd, sp) -> DFn (respan_fn_def fd, sp)
  | d -> d

(** Build derived declarations for one interface on [type_name].
    Returns a list of [decl] — usually one [DImpl], but [Json] produces
    two standalone [DFn] declarations (to_json / from_json).
    [iface_span] is the span of the interface name in the source, used for
    error reporting when the interface is unknown. *)
let derive_impl (errors : Err.ctx) (type_name : name) (sp : span)
    (iface : string) (iface_span : span) (tparams : name list) (td : type_def) : decl list =
  (* Type annotation for the type being implemented *)
  let self_ty : ty =
    if tparams = [] then TyCon (type_name, [])
    else TyCon (type_name, List.map (fun tp -> TyVar tp) tparams)
  in
  (* Helper: build an impl_def with a single method *)
  let impl_one meth_name fn_body_params fn_body =
    let fn_def = mk_fn_def meth_name fn_body_params fn_body in
    let idef : impl_def = {
      impl_iface       = mk_name iface;
      impl_ty          = self_ty;
      impl_constraints = [];
      impl_assoc_types = [];
      impl_methods     = [(mk_name meth_name, fn_def)];
    } in
    DImpl (idef, sp)
  in
  match iface with
  | "Eq" ->
    (* derive Eq: structural comparison using == on each field/variant.
       For variant types: match on pairs of constructors.
       For records: compare field-by-field.
       For aliases: delegate to the aliased type. *)
    let body = match td with
      | TDVariant variants ->
        (* match (a, b) with | (CtorA(args...), CtorA(args...)) -> all args eq | _ -> false *)
        let pair = ETuple ([EVar (mk_name "a"); EVar (mk_name "b")], dummy_span) in
        let branches = List.mapi (fun _i (v : variant) ->
            let n = List.length v.var_args in
            if n = 0 then
              (* no-arg ctor: Red, Red -> true *)
              { branch_pat = PatTuple (
                    [PatCon (v.var_name, []); PatCon (v.var_name, [])], dummy_span);
                branch_guard = None;
                branch_body  = ELit (LitBool true, dummy_span) }
            else begin
              (* ctor with args: Wrap(a0), Wrap(b0) -> a0 == b0 && ... *)
              let avar_names = List.init n (fun i -> Printf.sprintf "_da%d" i) in
              let bvar_names = List.init n (fun i -> Printf.sprintf "_db%d" i) in
              let pats_a = List.map (fun s -> PatVar (mk_name s)) avar_names in
              let pats_b = List.map (fun s -> PatVar (mk_name s)) bvar_names in
              let eq_exprs = List.map2 (fun sa sb ->
                  EApp (EVar (mk_name "=="),
                        [EVar (mk_name sa); EVar (mk_name sb)],
                        dummy_span)
                ) avar_names bvar_names in
              let body_expr = List.fold_right (fun eq_e acc ->
                  EApp (EVar (mk_name "&&"), [eq_e; acc], dummy_span)
                ) (List.rev (List.tl (List.rev eq_exprs)))
                  (List.nth eq_exprs (List.length eq_exprs - 1))
              in
              { branch_pat = PatTuple (
                    [PatCon (v.var_name, pats_a); PatCon (v.var_name, pats_b)], dummy_span);
                branch_guard = None;
                branch_body  = body_expr }
            end
          ) variants
        in
        (* wildcard arm: _ -> false *)
        let wild_branch = {
          branch_pat  = PatWild dummy_span;
          branch_guard = None;
          branch_body  = ELit (LitBool false, dummy_span);
        } in
        EMatch (pair, branches @ [wild_branch], dummy_span)
      | TDRecord fields ->
        (* compare each field: a.f == b.f && a.g == b.g && ... *)
        (match fields with
         | [] -> ELit (LitBool true, dummy_span)
         | [f] ->
           EApp (EVar (mk_name "=="),
                 [EField (EVar (mk_name "a"), f.fld_name, dummy_span);
                  EField (EVar (mk_name "b"), f.fld_name, dummy_span)],
                 dummy_span)
         | f :: rest ->
           let field_eq fld =
             EApp (EVar (mk_name "=="),
                   [EField (EVar (mk_name "a"), fld.fld_name, dummy_span);
                    EField (EVar (mk_name "b"), fld.fld_name, dummy_span)],
                   dummy_span)
           in
           List.fold_left (fun acc fld ->
               EApp (EVar (mk_name "&&"), [acc; field_eq fld], dummy_span)
             ) (field_eq f) rest)
      | TDAlias _ ->
        (* Delegate to the underlying type's eq *)
        EApp (EVar (mk_name "=="), [EVar (mk_name "a"); EVar (mk_name "b")], dummy_span)
    in
    [impl_one "eq" ["a"; "b"] body]

  | "Show" ->
    let body = match td with
      | TDVariant variants ->
        let branches = List.map (fun (v : variant) ->
            let n = List.length v.var_args in
            if n = 0 then
              { branch_pat  = PatCon (v.var_name, []);
                branch_guard = None;
                branch_body  = ELit (LitString v.var_name.txt, dummy_span) }
            else begin
              let arg_names = List.init n (fun i -> Printf.sprintf "_sv%d" i) in
              let pats = List.map (fun s -> PatVar (mk_name s)) arg_names in
              (* "Ctor(" ++ show(a0) ++ ", " ++ show(a1) ++ ... ++ ")" *)
              let parts = List.mapi (fun i s ->
                  let show_e = EApp (EVar (mk_name "show"), [EVar (mk_name s)], dummy_span) in
                  if i = 0 then show_e
                  else EApp (EVar (mk_name "++"),
                             [ELit (LitString ", ", dummy_span); show_e],
                             dummy_span)
                ) arg_names
              in
              let inner = List.fold_left (fun acc p ->
                  EApp (EVar (mk_name "++"), [acc; p], dummy_span)
                ) (ELit (LitString (v.var_name.txt ^ "("), dummy_span)) parts
              in
              let full = EApp (EVar (mk_name "++"),
                               [inner; ELit (LitString ")", dummy_span)],
                               dummy_span)
              in
              { branch_pat  = PatCon (v.var_name, pats);
                branch_guard = None;
                branch_body  = full }
            end
          ) variants
        in
        EMatch (EVar (mk_name "x"), branches, dummy_span)
      | TDRecord fields ->
        (* "TypeName { f1 = " ++ show(x.f1) ++ ", f2 = " ++ show(x.f2) ++ " }" *)
        let field_strs = List.mapi (fun i f ->
            let prefix = if i = 0 then f.fld_name.txt ^ " = " else ", " ^ f.fld_name.txt ^ " = " in
            let show_e = EApp (EVar (mk_name "show"),
                               [EField (EVar (mk_name "x"), f.fld_name, dummy_span)],
                               dummy_span)
            in
            EApp (EVar (mk_name "++"),
                  [ELit (LitString prefix, dummy_span); show_e],
                  dummy_span)
          ) fields
        in
        let header = ELit (LitString (type_name.txt ^ " { "), dummy_span) in
        let mid = List.fold_left (fun acc e ->
            EApp (EVar (mk_name "++"), [acc; e], dummy_span)
          ) header field_strs
        in
        EApp (EVar (mk_name "++"), [mid; ELit (LitString " }", dummy_span)], dummy_span)
      | TDAlias _ ->
        EApp (EVar (mk_name "show"), [EVar (mk_name "x")], dummy_span)
    in
    [impl_one "show" ["x"] body]

  | "Hash" ->
    (* Avoid calling hash() recursively (check_fn shadows the polymorphic binding).
       For variants: return the constructor index directly (stable hash).
       For records: use int_hash(field) via the builtin int hashing path. *)
    let body = match td with
      | TDVariant variants ->
        let branches = List.mapi (fun i (v : variant) ->
            let n = List.length v.var_args in
            let pats = List.init n (fun _ -> PatWild dummy_span) in
            { branch_pat  = PatCon (v.var_name, pats);
              branch_guard = None;
              branch_body  = ELit (LitInt i, dummy_span) }
          ) variants
        in
        EMatch (EVar (mk_name "x"), branches, dummy_span)
      | TDRecord fields ->
        (match fields with
         | [] -> ELit (LitInt 0, dummy_span)
         | fields ->
           (* Combine field hashes: fold over fields, mixing with prime *)
           let hash_field fld =
             (* Use the polymorphic hash for each field's value.
                Note: field values may be any type — hash is safe here since
                it's called on field values, not on x: Color. *)
             EApp (EVar (mk_name "hash"),
                   [EField (EVar (mk_name "x"), fld.fld_name, dummy_span)],
                   dummy_span)
           in
           (match fields with
            | [] -> ELit (LitInt 0, dummy_span)
            | [f] -> hash_field f
            | f :: rest ->
              List.fold_left (fun acc fld ->
                  EApp (EVar (mk_name "+"),
                        [EApp (EVar (mk_name "*"), [acc; ELit (LitInt 31, dummy_span)], dummy_span);
                         hash_field fld],
                        dummy_span)
                ) (hash_field f) rest))
      | TDAlias _ ->
        EApp (EVar (mk_name "hash"), [EVar (mk_name "x")], dummy_span)
    in
    [impl_one "hash" ["x"] body]

  | "Ord" ->
    (* derive Ord: compare constructors by their declaration index.
       For records: compare field by field lexicographically. *)
    let body = match td with
      | TDVariant variants ->
        (* fn compare(a, b) -> compare(ctor_index(a), ctor_index(b)) *)
        let index_of_branches var_name_for arg_count =
          List.mapi (fun i (v : variant) ->
              let n = List.length v.var_args in
              let pats = List.init n (fun _ -> PatWild dummy_span) in
              { branch_pat  = PatCon (v.var_name, pats);
                branch_guard = None;
                branch_body  = ELit (LitInt i, dummy_span) }
            ) variants
          |> (fun branches ->
               EMatch (EVar (mk_name var_name_for), branches, dummy_span))
          |> (fun e -> ignore arg_count; e)
        in
        let ai = index_of_branches "a" (List.length variants) in
        let bi = index_of_branches "b" (List.length variants) in
        (* let _ai = ...; let _bi = ...; compare(_ai, _bi) *)
        EBlock ([
          ELet ({ bind_pat = PatVar (mk_name "_oi_a"); bind_ty = None;
                  bind_lin = Unrestricted; bind_expr = ai }, dummy_span);
          ELet ({ bind_pat = PatVar (mk_name "_oi_b"); bind_ty = None;
                  bind_lin = Unrestricted; bind_expr = bi }, dummy_span);
          EApp (EVar (mk_name "-"),
                [EVar (mk_name "_oi_a"); EVar (mk_name "_oi_b")],
                dummy_span);
        ], dummy_span)
      | TDRecord fields ->
        (* Compare field by field; return first non-zero *)
        (match fields with
         | [] -> ELit (LitInt 0, dummy_span)
         | [f] ->
           EApp (EVar (mk_name "compare"),
                 [EField (EVar (mk_name "a"), f.fld_name, dummy_span);
                  EField (EVar (mk_name "b"), f.fld_name, dummy_span)],
                 dummy_span)
         | fields ->
           let stmts = List.mapi (fun i f ->
               let cmp_e =
                 EApp (EVar (mk_name "compare"),
                       [EField (EVar (mk_name "a"), f.fld_name, dummy_span);
                        EField (EVar (mk_name "b"), f.fld_name, dummy_span)],
                       dummy_span)
               in
               let name = Printf.sprintf "_cmp%d" i in
               ELet ({ bind_pat = PatVar (mk_name name); bind_ty = None;
                       bind_lin = Unrestricted; bind_expr = cmp_e }, dummy_span)
             ) fields
           in
           let final_cmp name i =
             if i = List.length fields - 1 then EVar (mk_name name)
             else
               EIf (EApp (EVar (mk_name "!="),
                          [EVar (mk_name name); ELit (LitInt 0, dummy_span)],
                          dummy_span),
                    EVar (mk_name name),
                    EVar (mk_name (Printf.sprintf "_cmp%d" (i + 1))),
                    dummy_span)
           in
           let last_name = Printf.sprintf "_cmp%d" (List.length fields - 1) in
           let result =
             List.fold_right (fun (i, f) acc ->
                 ignore f;
                 let cname = Printf.sprintf "_cmp%d" i in
                 if i = List.length fields - 1 then EVar (mk_name last_name)
                 else
                   EIf (EApp (EVar (mk_name "!="),
                              [EVar (mk_name cname); ELit (LitInt 0, dummy_span)],
                              dummy_span),
                        EVar (mk_name cname),
                        acc,
                        dummy_span)
               ) (List.mapi (fun i f -> (i, f)) fields |> List.rev |> List.tl |> List.rev)
               (EVar (mk_name last_name))
           in
           ignore result;
           ignore final_cmp;
           EBlock (stmts @ [
             List.fold_right (fun (i, _f) acc ->
                 let cname = Printf.sprintf "_cmp%d" i in
                 if i = List.length fields - 1 then EVar (mk_name cname)
                 else EIf (EApp (EVar (mk_name "!="),
                                 [EVar (mk_name cname); ELit (LitInt 0, dummy_span)],
                                 dummy_span),
                           EVar (mk_name cname), acc, dummy_span)
               ) (List.mapi (fun i f -> (i, f)) fields |> List.rev) (ELit (LitInt 0, dummy_span))
           ], dummy_span))
      | TDAlias _ ->
        EApp (EVar (mk_name "compare"), [EVar (mk_name "a"); EVar (mk_name "b")], dummy_span)
    in
    [impl_one "compare" ["a"; "b"] body]

  | "Json" when March_caps.Cap_surface_ty.caps_in_type_def td <> [] ->
    (* Capability unforgeability (R3).  A capability may be received and
       narrowed, never constructed; a derived Json codec over a `Cap` position
       is a construction route, so the derive is refused outright rather than
       generated with a hole in it.

       Why this is caught HERE and not by the generated code failing to
       typecheck: `encoder_for_ty` and `decode_value_at` below both fall back
       to "assume the nested type also derives Json" for any type they do not
       recognise.  `Cap(X)` is not recognised, so the codec was generated over
       the capability position without complaint and the decoder ran far
       enough to return a Json.DecodeError — a runtime failure that looks like
       bad input rather than a refused operation.

       Rejecting at the `derive` declaration also puts the diagnostic on a
       real span.  Every declaration this branch generates carries
       `dummy_span`, so an error raised from inside the generated codec would
       have nowhere useful to point.

       Both directions are refused together (see the message): a rule that
       rejected only decoding would leave `derive Json` half-expanded, with a
       working encoder beside a refused decoder. *)
    let caps = March_caps.Cap_surface_ty.caps_in_type_def td in
    let cap = List.hd caps in
    Err.error errors ~span:iface_span
      (Printf.sprintf
         "`Cap(%s)` cannot be deserialized — a capability may only be \
          received, never constructed, so `%s` cannot derive Json.\n\
          hint: hold the capability in a separate value and pass it as a \
          parameter, keeping `%s` free of capability fields."
         cap type_name.txt type_name.txt);
    []

  | "Json" ->
    (* derive Json: generate standalone to_json and from_json functions.
       to_json(x : T) : JsonValue   — structural encoding to JSON
       from_json(v : JsonValue) : Result(T, String) — decoding from JSON *)
    let sp = dummy_span in
    (* Helper: encode a field value based on its type annotation *)
    let encoder_for_ty (ty : ty) (value_expr : expr) : expr =
      match ty with
      | TyCon ({txt = "String"; _}, []) ->
        EApp (EVar (mk_name "Json.encode_string"), [value_expr], sp)
      | TyCon ({txt = "Int"; _}, []) ->
        EApp (EVar (mk_name "Json.encode_int"), [value_expr], sp)
      | TyCon ({txt = "Float"; _}, []) ->
        EApp (EVar (mk_name "Json.encode_number"), [value_expr], sp)
      | TyCon ({txt = "Bool"; _}, []) ->
        EApp (EVar (mk_name "Json.encode_bool"), [value_expr], sp)
      | _ ->
        (* Assume nested type also derives Json — call to_json recursively *)
        EApp (EVar (mk_name "to_json"), [value_expr], sp)
    in
    (* ── to_json ────────────────────────────────────────────── *)
    let to_json_body = match td with
      | TDRecord fields ->
        (* Json.encode_object([("f1", encode(x.f1)), ("f2", encode(x.f2)), ...]) *)
        let pair_exprs = List.map (fun (f : field) ->
            let field_access = EField (EVar (mk_name "x"), f.fld_name, sp) in
            let encoded = encoder_for_ty f.fld_ty field_access in
            ETuple ([ELit (LitString f.fld_name.txt, sp); encoded], sp)
          ) fields
        in
        let pairs_list = List.fold_right (fun e acc ->
            ECon (mk_name "Cons", [e; acc], sp)
          ) pair_exprs (ECon (mk_name "Nil", [], sp))
        in
        EApp (EVar (mk_name "Json.encode_object"), [pairs_list], sp)
      | TDVariant variants ->
        (* match x with
           | Ctor0 -> encode_object([("tag", encode_string("Ctor0"))])
           | Ctor1(v0) -> encode_object([("tag", ...), ("0", encode(v0))]) *)
        let branches = List.map (fun (v : variant) ->
            let n = List.length v.var_args in
            let arg_names = List.init n (fun i -> Printf.sprintf "_jv%d" i) in
            let pats = List.map (fun s -> PatVar (mk_name s)) arg_names in
            let tag_pair = ETuple ([
                ELit (LitString "tag", sp);
                EApp (EVar (mk_name "Json.encode_string"),
                      [ELit (LitString v.var_name.txt, sp)], sp)
              ], sp) in
            let arg_pairs = List.mapi (fun i arg_name ->
                let ty = List.nth v.var_args i in
                ETuple ([
                    ELit (LitString (string_of_int i), sp);
                    encoder_for_ty ty (EVar (mk_name arg_name))
                  ], sp)
              ) arg_names
            in
            let all_pairs = tag_pair :: arg_pairs in
            let pairs_list = List.fold_right (fun e acc ->
                ECon (mk_name "Cons", [e; acc], sp)
              ) all_pairs (ECon (mk_name "Nil", [], sp))
            in
            { branch_pat = PatCon (v.var_name, pats);
              branch_guard = None;
              branch_body = EApp (EVar (mk_name "Json.encode_object"), [pairs_list], sp) }
          ) variants
        in
        EMatch (EVar (mk_name "x"), branches, sp)
      | TDAlias _ ->
        EApp (EVar (mk_name "to_json"), [EVar (mk_name "x")], sp)
    in
    (* ── from_json ──────────────────────────────────────────── *)
    (* Shared helpers for the TDRecord decoder: build a Json.DecodeError
       whose path is a single JPathField(key) step (or Nil for the
       root-level "expected an object" case), so every failure names the
       field that caused it instead of one opaque wildcard error. *)
    let jpath_field_step (key : string) : expr =
      ECon (mk_name "Json.JPathField", [ELit (LitString key, sp)], sp)
    in
    let nil_path : expr = ECon (mk_name "Nil", [], sp) in
    let single_step_path (key : string) : expr =
      ECon (mk_name "Cons", [jpath_field_step key; nil_path], sp)
    in
    let mk_decode_err (msg : string) (path : expr) : expr =
      ECon (mk_name "Json.DecodeError",
            [ELit (LitString msg, sp); path; ELit (LitInt (-1), sp)], sp)
    in
    let err_at_field (msg : string) (key : string) : expr =
      ECon (mk_name "Err", [mk_decode_err msg (single_step_path key)], sp)
    in
    (* Variant-decoding counterparts of the above: a positional argument's
       path step is JPathIndex(i) rather than JPathField(key), so an argument
       error renders as `$[0]: expected Int` instead of `$.field: ...`. *)
    let jpath_index_step (i : int) : expr =
      ECon (mk_name "Json.JPathIndex", [ELit (LitInt i, sp)], sp)
    in
    let single_index_path (i : int) : expr =
      ECon (mk_name "Cons", [jpath_index_step i; nil_path], sp)
    in
    let err_at_path (msg : string) (path : expr) : expr =
      ECon (mk_name "Err", [mk_decode_err msg path], sp)
    in
    let mk_decode_err_expr (msg_expr : expr) (path : expr) : expr =
      ECon (mk_name "Json.DecodeError", [msg_expr; path; ELit (LitInt (-1), sp)], sp)
    in
    let cat2 (a : expr) (b : expr) : expr =
      EApp (EVar (mk_name "++"), [a; b], sp)
    in
    (* Decode a single field's raw JsonValue (bound to [fv]) according to its
       declared type, then invoke [k] with the expression for the decoded
       (already-converted) value. For a nested derive-Json type, recurse via
       from_json and prepend this field's step to the inner error — this one
       line (Json.decode_error_under) is what makes a path like `$.inner.id`
       compose across a record boundary without threading a cursor through
       user code. *)
    (* Generic version: decode a raw JsonValue (bound to [fv]) according to
       its declared type, given the path [step] to prepend to a nested error
       (via Json.decode_error_under) and the full [single_path] to use for a
       directly-observed type-mismatch at this position. Record fields use
       JPathField(key) for both; variant arguments use JPathIndex(i). *)
    let decode_value_at (ty : ty) (fv : name) (step : expr) (single_path : expr)
        (k : expr -> expr) : expr =
      let scalar_case (ctor : string) (msg : string)
          (conv : expr -> expr) : expr =
        let bound = mk_name (fv.txt ^ "_v") in
        EMatch (EVar fv, [
            { branch_pat = PatCon (mk_name ctor, [PatVar bound]);
              branch_guard = None;
              branch_body = k (conv (EVar bound)) };
            { branch_pat = PatWild sp;
              branch_guard = None;
              branch_body = err_at_path msg single_path };
          ], sp)
      in
      match ty with
      | TyCon ({txt = "String"; _}, []) ->
        scalar_case "Str" "expected String" (fun e -> e)
      | TyCon ({txt = "Int"; _}, []) ->
        scalar_case "Number" "expected Int"
          (fun e -> EApp (EVar (mk_name "float_to_int"), [e], sp))
      | TyCon ({txt = "Float"; _}, []) ->
        scalar_case "Number" "expected Float" (fun e -> e)
      | TyCon ({txt = "Bool"; _}, []) ->
        scalar_case "Bool" "expected Bool" (fun e -> e)
      | _ ->
        let inner_ok = mk_name (fv.txt ^ "_ok") in
        let inner_err = mk_name (fv.txt ^ "_err") in
        EMatch (EApp (EVar (mk_name "from_json"), [EVar fv], sp), [
            { branch_pat = PatCon (mk_name "Ok", [PatVar inner_ok]);
              branch_guard = None;
              branch_body = k (EVar inner_ok) };
            { branch_pat = PatCon (mk_name "Err", [PatVar inner_err]);
              branch_guard = None;
              branch_body = ECon (mk_name "Err",
                [EApp (EVar (mk_name "Json.decode_error_under"),
                       [step; EVar inner_err], sp)], sp) };
          ], sp)
    in
    let decode_field_value (ty : ty) (fv : name) (key : string)
        (k : expr -> expr) : expr =
      decode_value_at ty fv (jpath_field_step key) (single_step_path key) k
    in
    let decode_arg_value (ty : ty) (fv : name) (i : int)
        (k : expr -> expr) : expr =
      decode_value_at ty fv (jpath_index_step i) (single_index_path i) k
    in
    (* Build the right-nested per-field chain (Step 4 of the design):
         match Json.get_field(kvs, "f1") do
         None -> Err(DecodeError("missing field", [JPathField("f1")], -1))
         Some(fv1) -> match fv1 do
           <ok-pattern> -> <recurse into rest, or Ok({...}) at the end>
           _ -> Err(DecodeError("expected <Ty>", [JPathField("f1")], -1))
           end
         end
       Fields are looked up by name one at a time and never enumerated, so
       unmentioned/unknown JSON keys are silently ignored for free — no
       separate handling is needed for "unknown fields are ignored". *)
    let rec build_field_chain (fields : field list)
        (decoded : (name * expr) list) : expr =
      match fields with
      | [] -> ECon (mk_name "Ok", [ERecord (List.rev decoded, sp)], sp)
      | f :: rest ->
        let key = f.fld_name.txt in
        let fv = mk_name (Printf.sprintf "_jf_%s" key) in
        let get_expr = EApp (EVar (mk_name "Json.get_field"),
                             [EVar (mk_name "kvs"); ELit (LitString key, sp)], sp)
        in
        let some_body = decode_field_value f.fld_ty fv key (fun value_expr ->
            build_field_chain rest ((f.fld_name, value_expr) :: decoded))
        in
        EMatch (get_expr, [
            { branch_pat = PatCon (mk_name "None", []);
              branch_guard = None;
              branch_body = err_at_field "missing field" key };
            { branch_pat = PatCon (mk_name "Some", [PatVar fv]);
              branch_guard = None;
              branch_body = some_body };
          ], sp)
    in
    let from_json_body = match td with
      | TDRecord fields ->
        let kvs = mk_name "kvs" in
        let object_branch = {
          branch_pat = PatCon (mk_name "Object", [PatVar kvs]);
          branch_guard = None;
          branch_body = build_field_chain fields [];
        } in
        let not_object_branch = {
          branch_pat = PatWild sp;
          branch_guard = None;
          branch_body = ECon (mk_name "Err",
            [mk_decode_err "expected an object" nil_path], sp);
        } in
        EMatch (EVar (mk_name "v"), [object_branch; not_object_branch], sp)
      | TDVariant variants ->
        (* match v do
             Object(kvs) -> match Json.get_field(kvs, "tag") do
               None -> Err(DecodeError("missing field", [JPathField("tag")], -1))
               Some(tagv) -> match tagv do
                 Str("Ctor0") -> Ok(Ctor0)
                 Str("Ctor1") -> <build_arg_chain over kvs, keys "0","1",...>
                 Str(tagstr) -> Err(DecodeError("unknown variant `" ++ tagstr ++ "`", [JPathField("tag")], -1))
                 _ -> Err(DecodeError("expected String", [JPathField("tag")], -1))
               end
             end
             _ -> Err(DecodeError("expected an object", Nil, -1))
           end
           Each argument is looked up positionally by string key ("0", "1", ...)
           out of the same object, mirroring the wire shape the encoder above
           produces (tag + numeric-string keys), and its error is tagged with
           JPathIndex(i) rather than JPathField(key) so it renders as
           `$[i]: ...` — see decode_arg_value/build_arg_chain. *)
        let kvs = mk_name "kvs" in
        let tagv = mk_name "tagv" in
        let tagstr = mk_name "_tagstr" in
        let tag_path = single_step_path "tag" in
        let rec build_arg_chain (ctor_name : name) (arg_tys : ty list)
            (idx : int) (decoded : expr list) : expr =
          match arg_tys with
          | [] -> ECon (mk_name "Ok", [ECon (ctor_name, List.rev decoded, sp)], sp)
          | ty :: rest ->
            let key = string_of_int idx in
            let fv = mk_name (Printf.sprintf "_ja_%d" idx) in
            let get_expr = EApp (EVar (mk_name "Json.get_field"),
                                 [EVar kvs; ELit (LitString key, sp)], sp)
            in
            let some_body = decode_arg_value ty fv idx (fun value_expr ->
                build_arg_chain ctor_name rest (idx + 1) (value_expr :: decoded))
            in
            EMatch (get_expr, [
                { branch_pat = PatCon (mk_name "None", []);
                  branch_guard = None;
                  branch_body = err_at_path "missing field" (single_index_path idx) };
                { branch_pat = PatCon (mk_name "Some", [PatVar fv]);
                  branch_guard = None;
                  branch_body = some_body };
              ], sp)
        in
        let tag_branches = List.map (fun (variant_def : variant) ->
            { branch_pat = PatCon (mk_name "Str",
                [PatLit (LitString variant_def.var_name.txt, sp)]);
              branch_guard = None;
              branch_body = build_arg_chain variant_def.var_name variant_def.var_args 0 [] }
          ) variants
        in
        let unknown_variant_branch = {
          branch_pat = PatCon (mk_name "Str", [PatVar tagstr]);
          branch_guard = None;
          branch_body = ECon (mk_name "Err",
            [mk_decode_err_expr
               (cat2 (cat2 (ELit (LitString "unknown variant `", sp)) (EVar tagstr))
                     (ELit (LitString "`", sp)))
               tag_path], sp);
        } in
        let tag_not_string_branch = {
          branch_pat = PatWild sp;
          branch_guard = None;
          branch_body = err_at_path "expected String" tag_path;
        } in
        let tagv_match = EMatch (EVar tagv,
            tag_branches @ [unknown_variant_branch; tag_not_string_branch], sp)
        in
        let object_branch = {
          branch_pat = PatCon (mk_name "Object", [PatVar kvs]);
          branch_guard = None;
          branch_body = EMatch (
            EApp (EVar (mk_name "Json.get_field"),
                  [EVar kvs; ELit (LitString "tag", sp)], sp),
            [ { branch_pat = PatCon (mk_name "None", []);
                branch_guard = None;
                branch_body = err_at_field "missing field" "tag" };
              { branch_pat = PatCon (mk_name "Some", [PatVar tagv]);
                branch_guard = None;
                branch_body = tagv_match } ], sp);
        } in
        let not_object_branch = {
          branch_pat = PatWild sp;
          branch_guard = None;
          branch_body = ECon (mk_name "Err",
            [mk_decode_err "expected an object" nil_path], sp);
        } in
        EMatch (EVar (mk_name "v"), [object_branch; not_object_branch], sp)
      | TDAlias _ ->
        EApp (EVar (mk_name "from_json"), [EVar (mk_name "v")], sp)
    in
    (* Generate two DImpl blocks with pseudo-interfaces "JsonTo" and "JsonFrom".
       This allows impl_tbl dispatch for variant types, while also binding
       to_json/from_json in the local env for record types. *)
    let to_json_fn = mk_fn_def "to_json" ["x"] to_json_body in
    let from_json_fn = mk_fn_def "from_json" ["v"] from_json_body in
    let mk_json_impl iface_name meth_name fn_body =
      let idef : impl_def = {
        impl_iface       = mk_name iface_name;
        impl_ty          = self_ty;
        impl_constraints = [];
        impl_assoc_types = [];
        impl_methods     = [(mk_name meth_name, fn_body)];
      } in
      DImpl (idef, sp)
    in
    (* ── from_json_events (Task 7 / Phase B) ───────────────────────────
       A second, event-consuming decoder, generated ONLY for TDRecord
       types (task-7-brief.md's Step 2 illustrates a record-specific state
       machine; TDVariant/TDAlias keep only the tree-based to_json/
       from_json above -- extending the event path to variants is
       explicitly out of this task's scope).

       from_json_events(events : List(JsonStream.Event))
         : Result((T, List(JsonStream.Event)), Json.DecodeError)

       consumes exactly the events belonging to one value of type T off
       the FRONT of [events] and returns the decoded value paired with
       whatever events remain -- this is what lets a nested derived-Json
       field recurse by calling its own from_json_events on the same
       stream and threading the remainder back out, without ever
       building a JsonValue tree. This mirrors the "JsonFrom"/"JsonTo"
       pseudo-interface trick above: iface name "JsonFromEvents" starts
       with "Json", so eval.ml's/typecheck.ml's [is_json_iface]/
       [is_json_derive] prefix checks treat it exactly like from_json --
       skip interface-existence validation, bind the bare method name in
       the local env (not impl_tbl-dispatched), self-recursive closure --
       with NO changes needed to either file. This also means
       from_json_events inherits the SAME cross-type shadowing caveat as
       bare from_json (lib/eval/eval.ml's DImpl handling name-binds it
       per-derive, so the LAST type to derive Json in a module owns the
       bare name) -- a known, separately-tracked issue, not a new one.

       Two helpers are generated as LOCAL recursive functions (`ELetFn`,
       scoped to this from_json_events body) rather than extra top-level
       `pfn` declarations, so that two types deriving Json in the same
       module never collide on a shared top-level helper name -- unlike
       the shared bare `from_json`/`to_json` names (which tolerate
       last-wins shadowing by design), a stray collision on an internal
       helper would be a new, gratuitous bug.

       - skip(events, depth): unknown-field subtree skip. Tracks
         container depth EXPLICITLY (EvObjStart/EvArrStart increment,
         EvObjEnd/EvArrEnd decrement) and stops only when depth returns
         to the level it started at -- see task-7-brief.md's Step 3 for
         why counting only "the next event" would silently desynchronize
         the stream instead of erroring.
       - loop(events, slot_f1, slot_f2, ...): one Option slot per field
         (all None initially). On EvKey(k) matching a field whose slot is
         still None, decode that field's value and recurse with the slot
         filled; on EvKey(k) matching a field whose slot is ALREADY Some
         (a duplicate key) or matching no field at all (an unknown key),
         skip the value via `skip` and recurse UNCHANGED --
         first-occurrence-wins for duplicates, matching the tree
         decoder's Json.get_field/Json.parse behavior (the capability
         map), which the oracle in test_json_typed.march requires the two
         decoders to agree on. On EvObjEnd, every slot must be Some, else
         `DecodeError("missing field", ...)`. *)
    let from_json_events_impl : decl option =
      match td with
      | TDRecord fields ->
        let ev_field_slots = List.mapi (fun i (f : field) ->
            (i, f, mk_name (Printf.sprintf "_evf_%s" f.fld_name.txt))
          ) fields
        in
        let skip_name = mk_name "_ev_skip" in
        let loop_name = mk_name "_ev_loop" in
        let sk_events = mk_name "_sk_events" in
        let sk_depth  = mk_name "_sk_depth" in
        let sk_rest   = mk_name "_sk_rest" in
        let depth_e = EVar sk_depth in
        let depth_plus1  = EApp (EVar (mk_name "+"), [depth_e; ELit (LitInt 1, sp)], sp) in
        let depth_minus1 = EApp (EVar (mk_name "-"), [depth_e; ELit (LitInt 1, sp)], sp) in
        let depth_eq n = EApp (EVar (mk_name "=="), [depth_e; ELit (LitInt n, sp)], sp) in
        let sk_recurse events_e depth_e2 =
          EApp (EVar skip_name, [events_e; depth_e2], sp)
        in
        let sk_ok_rest = ECon (mk_name "Ok", [EVar sk_rest], sp) in
        let sk_close_branch =
          EIf (depth_eq 1, sk_ok_rest, sk_recurse (EVar sk_rest) depth_minus1, sp)
        in
        let skip_body =
          EMatch (EVar sk_events, [
              { branch_pat = PatCon (mk_name "Nil", []);
                branch_guard = None;
                branch_body = ECon (mk_name "Err",
                  [mk_decode_err "truncated while skipping an unknown field's value" nil_path], sp) };
              { branch_pat = PatCon (mk_name "Cons",
                  [PatCon (mk_name "EvObjStart", []); PatVar sk_rest]);
                branch_guard = None;
                branch_body = sk_recurse (EVar sk_rest) depth_plus1 };
              { branch_pat = PatCon (mk_name "Cons",
                  [PatCon (mk_name "EvArrStart", []); PatVar sk_rest]);
                branch_guard = None;
                branch_body = sk_recurse (EVar sk_rest) depth_plus1 };
              { branch_pat = PatCon (mk_name "Cons",
                  [PatCon (mk_name "EvObjEnd", []); PatVar sk_rest]);
                branch_guard = None;
                branch_body = sk_close_branch };
              { branch_pat = PatCon (mk_name "Cons",
                  [PatCon (mk_name "EvArrEnd", []); PatVar sk_rest]);
                branch_guard = None;
                branch_body = sk_close_branch };
              { branch_pat = PatCon (mk_name "Cons", [PatWild sp; PatVar sk_rest]);
                branch_guard = None;
                branch_body = EIf (depth_eq 0, sk_ok_rest, sk_recurse (EVar sk_rest) depth_e, sp) };
            ], sp)
        in
        let skip_fn_letfn =
          ELetFn (skip_name,
            [ { param_name = sk_events; param_ty = None; param_lin = Unrestricted };
              { param_name = sk_depth;  param_ty = None; param_lin = Unrestricted } ],
            None, skip_body, sp)
        in
        (* Decode one field's value out of the events immediately
           following its EvKey, mirroring decode_value_at above but
           consuming events instead of a JsonValue -- see
           decode_value_at's comment for why a nested derived-Json field
           recurses via decode_error_under. Returns
           Result((value, remaining_events), DecodeError). *)
        let decode_field_from_events (fty : ty) (events_e : expr)
            (step : expr) (single_path : expr) : expr =
          let scalar_case (ctor : string) (msg : string) (conv : expr -> expr) : expr =
            let bound = mk_name "_evsv" in
            let rest3 = mk_name "_evsrest" in
            EMatch (events_e, [
                { branch_pat = PatCon (mk_name "Cons",
                    [PatCon (mk_name ctor, [PatVar bound]); PatVar rest3]);
                  branch_guard = None;
                  branch_body = ECon (mk_name "Ok",
                    [ETuple ([conv (EVar bound); EVar rest3], sp)], sp) };
                { branch_pat = PatWild sp;
                  branch_guard = None;
                  branch_body = ECon (mk_name "Err", [mk_decode_err msg single_path], sp) };
              ], sp)
          in
          match fty with
          | TyCon ({txt = "String"; _}, []) ->
            scalar_case "EvStr" "expected String" (fun e -> e)
          | TyCon ({txt = "Int"; _}, []) ->
            scalar_case "EvNum" "expected Int"
              (fun e -> EApp (EVar (mk_name "float_to_int"), [e], sp))
          | TyCon ({txt = "Float"; _}, []) ->
            scalar_case "EvNum" "expected Float" (fun e -> e)
          | TyCon ({txt = "Bool"; _}, []) ->
            scalar_case "EvBool" "expected Bool" (fun e -> e)
          | _ ->
            (* Assume the field's type also derives Json and recurses via
               ITS OWN generated from_json_events, threading the
               remaining-events tuple straight through on success and
               prefixing this field's path step on failure. *)
            let inner_ok = mk_name "_evok" in
            let inner_rest = mk_name "_evokrest" in
            let inner_err = mk_name "_everr" in
            EMatch (EApp (EVar (mk_name "from_json_events"), [events_e], sp), [
                { branch_pat = PatCon (mk_name "Ok",
                    [PatTuple ([PatVar inner_ok; PatVar inner_rest], sp)]);
                  branch_guard = None;
                  branch_body = ECon (mk_name "Ok",
                    [ETuple ([EVar inner_ok; EVar inner_rest], sp)], sp) };
                { branch_pat = PatCon (mk_name "Err", [PatVar inner_err]);
                  branch_guard = None;
                  branch_body = ECon (mk_name "Err",
                    [EApp (EVar (mk_name "Json.decode_error_under"),
                           [step; EVar inner_err], sp)], sp) };
              ], sp)
        in
        let cursor = mk_name "_ev_cursor" in
        let all_slots = List.map (fun (_, _, s) -> s) ev_field_slots in
        let slots_as_evars = List.map (fun s -> EVar s) all_slots in
        let key_v = mk_name "_evk" in
        let after_key_v = mk_name "_evrestk" in
        let tail_v = mk_name "_evtail" in
        (* Skip one whole value (unknown key, or a duplicate of a
           known key), then resume the loop with the slots UNCHANGED. *)
        let skip_and_continue (events_after_e : expr) (slot_args : expr list) : expr =
          let sk2_ok = mk_name "_evskrest" in
          let sk2_err = mk_name "_evskerr" in
          EMatch (EApp (EVar skip_name, [events_after_e; ELit (LitInt 0, sp)], sp), [
              { branch_pat = PatCon (mk_name "Ok", [PatVar sk2_ok]);
                branch_guard = None;
                branch_body = EApp (EVar loop_name, EVar sk2_ok :: slot_args, sp) };
              { branch_pat = PatCon (mk_name "Err", [PatVar sk2_err]);
                branch_guard = None;
                branch_body = ECon (mk_name "Err", [EVar sk2_err], sp) };
            ], sp)
        in
        let is_some_expr (e : expr) : expr =
          EMatch (e, [
              { branch_pat = PatCon (mk_name "Some", [PatWild sp]);
                branch_guard = None; branch_body = ELit (LitBool true, sp) };
              { branch_pat = PatWild sp;
                branch_guard = None; branch_body = ELit (LitBool false, sp) };
            ], sp)
        in
        let rec build_key_chain (remaining : (int * field * name) list) : expr =
          match remaining with
          | [] ->
            (* No field matched this key: unknown field. *)
            skip_and_continue (EVar after_key_v) slots_as_evars
          | (i, f, slot) :: rest ->
            let key_eq = EApp (EVar (mk_name "=="),
              [EVar key_v; ELit (LitString f.fld_name.txt, sp)], sp) in
            let decode_and_set =
              let decoded = decode_field_from_events f.fld_ty (EVar after_key_v)
                  (jpath_field_step f.fld_name.txt) (single_step_path f.fld_name.txt) in
              let dv = mk_name "_evdv" in
              let drest = mk_name "_evdrest" in
              let derr = mk_name "_evderr" in
              EMatch (decoded, [
                  { branch_pat = PatCon (mk_name "Ok",
                      [PatTuple ([PatVar dv; PatVar drest], sp)]);
                    branch_guard = None;
                    branch_body =
                      let new_args = List.mapi (fun j s ->
                          if j = i then ECon (mk_name "Some", [EVar dv], sp)
                          else EVar s) all_slots in
                      EApp (EVar loop_name, EVar drest :: new_args, sp) };
                  { branch_pat = PatCon (mk_name "Err", [PatVar derr]);
                    branch_guard = None;
                    branch_body = ECon (mk_name "Err", [EVar derr], sp) };
                ], sp)
            in
            EIf (key_eq,
              (* Duplicate key (slot already filled): first-wins, so skip
                 this occurrence's value instead of overwriting. *)
              EIf (is_some_expr (EVar slot),
                   skip_and_continue (EVar after_key_v) slots_as_evars,
                   decode_and_set, sp),
              build_key_chain rest, sp)
        in
        let rec build_finish_chain (remaining : (int * field * name) list)
            (decoded : (name * expr) list) (tail_e : expr) : expr =
          match remaining with
          | [] -> ECon (mk_name "Ok",
              [ETuple ([ERecord (List.rev decoded, sp); tail_e], sp)], sp)
          | (_, f, slot) :: rest ->
            let bv = mk_name (Printf.sprintf "_evfv_%s" f.fld_name.txt) in
            EMatch (EVar slot, [
                { branch_pat = PatCon (mk_name "Some", [PatVar bv]);
                  branch_guard = None;
                  branch_body = build_finish_chain rest
                    ((f.fld_name, EVar bv) :: decoded) tail_e };
                { branch_pat = PatCon (mk_name "None", []);
                  branch_guard = None;
                  branch_body = err_at_field "missing field" f.fld_name.txt };
              ], sp)
        in
        let loop_body =
          EMatch (EVar cursor, [
              { branch_pat = PatCon (mk_name "Cons",
                  [PatCon (mk_name "EvObjEnd", []); PatVar tail_v]);
                branch_guard = None;
                branch_body = build_finish_chain ev_field_slots [] (EVar tail_v) };
              { branch_pat = PatCon (mk_name "Cons",
                  [PatCon (mk_name "EvKey", [PatVar key_v]); PatVar after_key_v]);
                branch_guard = None;
                branch_body = build_key_chain ev_field_slots };
              { branch_pat = PatCon (mk_name "Nil", []);
                branch_guard = None;
                branch_body = ECon (mk_name "Err",
                  [mk_decode_err "truncated while decoding an object" nil_path], sp) };
              { branch_pat = PatWild sp;
                branch_guard = None;
                branch_body = ECon (mk_name "Err",
                  [mk_decode_err "expected a field name or end of object" nil_path], sp) };
            ], sp)
        in
        let loop_params =
          { param_name = cursor; param_ty = None; param_lin = Unrestricted }
          :: List.map (fun s -> { param_name = s; param_ty = None; param_lin = Unrestricted }) all_slots
        in
        let loop_fn_letfn = ELetFn (loop_name, loop_params, None, loop_body, sp) in
        let rest0 = mk_name "_ev_rest0" in
        let all_none_args = List.map (fun _ -> ECon (mk_name "None", [], sp)) all_slots in
        let top_body =
          EMatch (EVar (mk_name "events"), [
              { branch_pat = PatCon (mk_name "Cons",
                  [PatCon (mk_name "EvObjStart", []); PatVar rest0]);
                branch_guard = None;
                branch_body = EApp (EVar loop_name, EVar rest0 :: all_none_args, sp) };
              { branch_pat = PatWild sp;
                branch_guard = None;
                branch_body = ECon (mk_name "Err",
                  [mk_decode_err "expected an object" nil_path], sp) };
            ], sp)
        in
        let full_body = EBlock ([skip_fn_letfn; loop_fn_letfn; top_body], sp) in
        let from_json_events_fn = mk_fn_def "from_json_events" ["events"] full_body in
        Some (mk_json_impl "JsonFromEvents" "from_json_events" from_json_events_fn)
      | TDVariant _ | TDAlias _ -> None
    in
    [mk_json_impl "JsonTo" "to_json" to_json_fn;
     mk_json_impl "JsonFrom" "from_json" from_json_fn]
    @ (match from_json_events_impl with Some d -> [d] | None -> [])

  | _ ->
    Err.error errors ~span:iface_span
      (Printf.sprintf
         "Unknown derive target `%s` for type `%s`.\n\
          Supported interfaces: Eq, Show, Hash, Ord, Json"
         iface type_name.txt);
    []

(** Expand a [DDeriving] into zero or more [DImpl] blocks.
    Emits an error for unknown interfaces and for unknown target types. *)
let expand_derive
    (errors : Err.ctx)
    (type_defs : (string * (name list * type_def)) list)
    (type_name : name)
    (ifaces : name list)
    (sp : span)
  : decl list =
  match List.assoc_opt type_name.txt type_defs with
  | None ->
    Err.error errors ~span:type_name.span
      (Printf.sprintf
         "Unknown type `%s` in `derive` — is it declared in this module?"
         type_name.txt);
    []
  | Some (tparams, td) ->
    List.concat_map (fun (iface_name : name) ->
        derive_impl errors type_name sp iface_name.txt iface_name.span tparams td
        |> List.map respan_derived_decl
      ) ifaces

(** Collect top-level function definitions for satisfy expansion. *)
let collect_fns (decls : decl list) : (string * fn_def) list =
  List.filter_map (function
    | DFn (def, _) -> Some (def.fn_name.txt, def)
    | _ -> None
  ) decls

(** Expand a [DSatisfy] into [DImpl] blocks by matching existing functions to
    interface methods by name.  Emits an error if the interface is not found or
    a required method is missing. *)
let expand_satisfy
    (errors : Err.ctx)
    (interfaces : (string * interface_def) list)
    (fns : (string * fn_def) list)
    (iface_names : name list)
    (type_names : name list)
    (sp : span)
  : decl list =
  List.concat_map (fun (iface_n : name) ->
    List.concat_map (fun (type_n : name) ->
      match List.assoc_opt iface_n.txt interfaces with
      | None ->
        Err.error errors ~span:iface_n.span
          (Printf.sprintf "Unknown interface `%s` in satisfy declaration." iface_n.txt);
        []
      | Some iface ->
        let methods = List.filter_map (fun (md : method_decl) ->
          match List.assoc_opt md.md_name.txt fns with
          | None ->
            Err.error errors ~span:sp
              (Printf.sprintf
                 "satisfy %s for %s: no function `%s` found in scope."
                 iface_n.txt type_n.txt md.md_name.txt);
            None
          | Some fn_def ->
            Some (md.md_name, fn_def)
        ) iface.iface_methods in
        if List.length methods < List.length iface.iface_methods then []
        else begin
          let impl_ty = TyCon (type_n, []) in
          let idef : impl_def = {
            impl_iface       = iface_n;
            impl_ty          = impl_ty;
            impl_constraints = [];
            impl_assoc_types = [];
            impl_methods     = methods;
          } in
          [DImpl (idef, sp)]
        end
    ) type_names
  ) iface_names

(** Check mutual exclusivity of [main] and [app] declarations.
    Reports a proper error with span if both are present. *)
let check_app_main_exclusivity (errors : Err.ctx) (decls : decl list) : unit =
  let main_span = List.find_map (function
      | DFn (def, sp) when def.fn_name.txt = "main" -> Some sp
      | _ -> None) decls in
  let app_span = List.find_map (function
      | DApp (_, sp) -> Some sp
      | _ -> None) decls in
  match main_span, app_span with
  | Some ms, Some as_ ->
    Err.error errors ~span:ms
      (Printf.sprintf
         "A module cannot define both `main()` and an `app` declaration.\n\
          `main()` is for programs that run once and exit.\n\
          `app` is for long-running supervised applications with a process tree.\n\
          Choose one: `main()` at %s:%d, or `app` at %s:%d."
         ms.file ms.start_line as_.file as_.start_line)
  | _ -> ()

(** Check that [main], if present, has a valid entry-point signature: zero
    parameters, or exactly one parameter of declared type [Cap(IO)] — the
    initial IO capability the runtime grants at startup (see
    specs/lang/capabilities.md, "Putting it together"). Any other arity or
    parameter type is rejected here with a clear diagnostic rather than left
    to silently misbehave downstream: the interpreter calls every [main] with
    zero arguments regardless of its declared arity, so a 1-parameter [main]
    that slips past this check becomes a partial application that is
    evaluated but never invoked (silent no-op, no error, no output); the
    native/WASI backend's runtime trampoline ([march_spawn_main]) invokes the
    compiled entry point through a bare 0-argument function pointer, so a
    mismatched-arity [main] there is an ABI-level miscompile (observed as a
    SIGBUS). *)
let check_main_signature (errors : Err.ctx) (decls : decl list) : unit =
  (* R1 (specs/2026-08-08-r1-no-ambient-io-design.md): `main` may be granted
     any point of the IO lattice, not only the root — the parameter type IS
     the program's grant, and Typecheck's [check_main_grant] holds the
     program's capability closure under it.  An unknown path (`Cap(IO.Nope)`)
     is rejected HERE rather than silently becoming a grant nothing sits
     under, which would read as "everything forbidden" with no explanation. *)
  let is_cap_io_ty = function
    | Some (TyCon (n, [ TyCon (inner, []) ])) ->
      n.txt = "Cap"
      && (inner.txt = "IO"
          || (String.length inner.txt > 3
              && String.sub inner.txt 0 3 = "IO."
              && List.mem_assoc inner.txt March_caps.Cap_lattice.hierarchy))
    | _ -> false
  in
  List.iter (function
      | DFn (def, _) when def.fn_name.txt = "main" ->
        (match def.fn_clauses with
         | [] -> ()
         | clause :: _ ->
           match clause.fc_params with
           | [] -> ()
           | [ FPNamed p ] when is_cap_io_ty p.param_ty -> ()
           | [ FPDefault (p, _) ] when is_cap_io_ty p.param_ty -> ()
           | params ->
             let n = List.length params in
             Err.error errors ~span:clause.fc_span
               (Printf.sprintf
                  "`main` must take zero arguments, or exactly one argument of type `Cap(IO)` (or a narrower point of the IO lattice, e.g. `Cap(IO.Console)`) — the capability the runtime GRANTS the program at startup; the whole program is then held to it.\n\
                   Found %d parameter%s instead.\n\
                   help: use `fn main() : () do ... end`, `fn main(cap : Cap(IO)) : () do ... end` for full IO, or e.g. `fn main(cap : Cap(IO.Console)) : () do ... end` to prove the program touches nothing beyond the console."
                  n (if n = 1 then "" else "s")))
      | _ -> ()
    ) decls

(* ── Island bridge auto-generation ─────────────────────────────────────── *)

(** Check if the original declarations include [DDeriving(type_name, ...Json...)]
    for a given type name. *)
let has_json_derive (type_name_str : string) (decls : decl list) : bool =
  List.exists (function
    | DDeriving (tn, ifaces, _) ->
      tn.txt = type_name_str &&
      List.exists (fun (i : name) -> i.txt = "Json") ifaces
    | _ -> false
  ) decls

(** Check if a DFn with the given name exists in the declaration list. *)
let has_fn_named (fn_name_str : string) (decls : decl list) : bool =
  List.exists (function
    | DFn (def, _) -> def.fn_name.txt = fn_name_str
    | _ -> false
  ) decls

(** Generate [update_json] and [render_json] bridge functions for an island
    module that has State and Msg types with [derive Json], plus [update]
    and [render] functions.

    The generated code uses the polymorphic [from_json]/[to_json] builtins
    which dispatch via impl_tbl at runtime.  Because the generated call sites
    feed their results into [update(state, msg)], the typechecker infers the
    correct concrete types for each [from_json] call. *)
let gen_island_bridges (sp : span) : decl list =
  let v s = EVar { txt = s; span = sp } in
  let app f args = EApp (v f, args, sp) in
  let pat_var s = PatVar (mk_name s) in
  let pat_con c args = PatCon (mk_name c, args) in
  let wild = PatWild sp in
  let br pat body = { branch_pat = pat; branch_guard = None; branch_body = body } in
  let mk_pub_fn name params body : fn_def =
    { fn_name   = mk_name name;
      fn_vis    = Public;
      fn_doc    = None;
      fn_attrs  = [];
      fn_ret_ty = None;
      fn_bounds = [];
      fn_clauses = [{
        fc_params = List.map (fun p ->
          FPNamed { param_name = mk_name p; param_ty = None; param_lin = Unrestricted }
        ) params;
        fc_guard  = None;
        fc_body   = body;
        fc_span   = sp;
      }] }
  in
  (* update_json(state_json, msg_json) : String
       match (Json.parse(state_json), Json.parse(msg_json)) do
       (Ok(sjv), Ok(mjv)) ->
         match (from_json(sjv), from_json(mjv)) do
         (Ok(state), Ok(msg)) ->
           Json.to_string(to_json(update(state, msg)))
         _ -> state_json
         end
       _ -> state_json
       end *)
  let update_body =
    let outer_scrut = ETuple ([
      app "Json.parse" [v "state_json"];
      app "Json.parse" [v "msg_json"]
    ], sp) in
    let inner_scrut = ETuple ([
      app "from_json" [v "sjv"];
      app "from_json" [v "mjv"]
    ], sp) in
    let success =
      app "Json.to_string" [
        app "to_json" [
          app "update" [v "state"; v "msg"]
        ]
      ]
    in
    let inner_match = EMatch (inner_scrut, [
      br (PatTuple ([pat_con "Ok" [pat_var "state"];
                     pat_con "Ok" [pat_var "msg"]], sp)) success;
      br wild (v "state_json")
    ], sp) in
    EMatch (outer_scrut, [
      br (PatTuple ([pat_con "Ok" [pat_var "sjv"];
                     pat_con "Ok" [pat_var "mjv"]], sp)) inner_match;
      br wild (v "state_json")
    ], sp)
  in
  (* render_json(state_json) : String
       match Json.parse(state_json) do
       Ok(sjv) ->
         match from_json(sjv) do
         Ok(state) -> IOList.to_string(render(state))
         _ -> ""
         end
       _ -> ""
       end *)
  let render_body =
    let inner_match = EMatch (app "from_json" [v "sjv"], [
      br (pat_con "Ok" [pat_var "state"])
        (app "IOList.to_string" [app "render" [v "state"]]);
      br wild (ELit (LitString "", sp))
    ], sp) in
    EMatch (app "Json.parse" [v "state_json"], [
      br (pat_con "Ok" [pat_var "sjv"]) inner_match;
      br wild (ELit (LitString "", sp))
    ], sp)
  in
  let uf = mk_pub_fn "update_json" ["state_json"; "msg_json"] update_body in
  let rf = mk_pub_fn "render_json" ["state_json"] render_body in
  [DFn (uf, sp); DFn (rf, sp)]

(** If this module looks like an island (has State + Msg with derive Json,
    and update + render functions), inject auto-generated bridge functions
    so the user doesn't need to write them manually. *)
let maybe_inject_island_bridges
    (orig_decls : decl list) (expanded : decl list) : decl list =
  let is_island =
    has_json_derive "State" orig_decls &&
    has_json_derive "Msg" orig_decls &&
    has_fn_named "update" expanded &&
    has_fn_named "render" expanded
  in
  if is_island then begin
    (* Only inject if the user hasn't already written their own *)
    let already_has_update_json = has_fn_named "update_json" expanded in
    let already_has_render_json = has_fn_named "render_json" expanded in
    if already_has_update_json || already_has_render_json then expanded
    else
      let sp = match expanded with
        | DFn (_, sp) :: _ -> sp
        | _ -> dummy_span
      in
      expanded @ gen_island_bridges sp
  end
  else expanded

(** Expand a [DFn] with [FPDefault] params into multiple [DFn] decls.
    Uses name mangling so each generated DFn has a unique name, making
    the output safe for the TIR/LLVM compiled pipeline.

    Example: [fn greet(name, greeting \\ "Hello") -> ...]
    Produces:
      [fn greet$2(name, greeting) -> ...]          (* full-arity, unique mangled name *)
      [fn greet$1(name) -> greet$2(name, "Hello")] (* short wrapper, calls mangled full *)
      [fn greet(name) -> greet$1(name)]            (* 1-arg dispatcher, original name *)
      [fn greet(name, greeting) -> greet$2(name, greeting)] (* 2-arg dispatcher *)

    The [greet$N] functions have unique names and are used by the TIR/LLVM pipeline.
    The [greet] dispatcher DFns (same original name, different arities) are combined
    into a VMultiarity value by the interpreter for backwards-compatible dispatch.
    The TIR lowering detects and skips the dispatcher DFns, rewriting call sites
    based on arity using the [greet$N] mangled names instead.
*)
let rec expand_defaults_decl (d : decl) : decl list =
  match d with
  | DFn (def, sp) ->
    (match def.fn_clauses with
     | [] -> [d]
     | first :: _ ->
       let params = first.fc_params in
       let required = List.filter (fun p -> match p with FPDefault _ -> false | _ -> true) params in
       let defaults = List.filter_map (fun p -> match p with FPDefault (param, e) -> Some (param, e) | _ -> None) params in
       if defaults = [] then [d]
       else begin
         let mk_var txt = EVar { txt; span = sp } in
         let n_total = List.length params in
         let full_mangled = Printf.sprintf "%s$%d" def.fn_name.txt n_total in
         (* Build the full-arity decl: replace FPDefault with FPNamed, rename to mangled name *)
         let strip_default = function
           | FPDefault (p, _) -> FPNamed p
           | other -> other
         in
         let full_params = List.map strip_default params in
         let full_clause = { first with fc_params = full_params } in
         let full_def = { def with fn_clauses = [full_clause];
                                   fn_name = { def.fn_name with txt = full_mangled } } in
         let full_decl = DFn (full_def, sp) in
         (* Helper: extract the arg name from a param for use at call sites *)
         let req_arg_of_param p =
           match p with
           | FPNamed p -> mk_var p.param_name.txt
           | FPPat (PatVar n) -> mk_var n.txt
           | FPDefault (p, _) -> mk_var p.param_name.txt
           | FPPat _ -> mk_var "__arg"   (* pattern params in required position: unusual *)
         in
         let req_args = List.map req_arg_of_param required in
         (* For i = 0 to n_defaults-1: generate a uniquely-named short-arity version.
            Each calls the full mangled version directly (no self-referential calls). *)
         let mangled_decls = List.init (List.length defaults) (fun i ->
           let this_arity = List.length required + i in
           let mangled_name = Printf.sprintf "%s$%d" def.fn_name.txt this_arity in
           let short_params =
             required @
             List.filteri (fun j _ -> j < i) (List.map (fun (p, _) -> FPNamed p) defaults)
           in
           let passed_default_args =
             List.filteri (fun j _ -> j < i) (List.map (fun (p, _) -> mk_var p.param_name.txt) defaults)
           in
           let remaining_default_exprs =
             List.filteri (fun j _ -> j >= i) (List.map (fun (_, e) -> e) defaults)
           in
           let all_call_args = req_args @ passed_default_args @ remaining_default_exprs in
           (* Call the full mangled version, not the original name *)
           let body = EApp (mk_var full_mangled, all_call_args, sp) in
           let short_clause = { fc_params = short_params; fc_guard = None; fc_body = body; fc_span = sp } in
           let short_def = { def with fn_clauses = [short_clause]; fn_ret_ty = None;
                                      fn_name = { def.fn_name with txt = mangled_name } } in
           DFn (short_def, sp)
         ) in
         (* No dispatcher DFns: the interpreter (eval.ml) automatically creates
            VMultiarity entries for the base name by detecting foo$N patterns.
            The TIR pipeline rewrites call sites via _default_dispatch table. *)
         mangled_decls @ [full_decl]
       end)
  | DMod (name, vis, inner, sp) ->
    (* Recurse so a default-arg fn defined inside a NESTED module also gets its
       `foo$N` arity variants.  Without this the nested fn's `FPDefault` params
       reach [desugar_fn_def]'s strip-fast-path (added for the tuple-UAF fix)
       and lose their default VALUES entirely, so a reduced-arity call
       `Inner.foo(x)` fails.  Expansion runs before [desugar_decl], so the
       fast-path never sees the (now-expanded) fn.  Paired with the
       eval nested `foo$N`→base VMultiarity reconstruction so both backends
       agree. *)
    [DMod (name, vis, List.concat_map expand_defaults_decl inner, sp)]
  | _ -> [d]

(* ---- Intra-module qualification pass ---- *)

(** Collect the bare VALUE names declared directly in [decls].
    Does NOT recurse into nested [DMod].

    "Value name" means precisely: a name that can appear as an [EVar] and
    resolve to something this module declares.  That is the only currency both
    consumers deal in — [make_qualifier]/[qualify_level] rewrite [EVar]s, and
    [strip_entry_self_qual] renames [EVar]s (its [ECon] namespace is explicitly
    left alone).  So a declaration that introduces only a TYPE name, a
    CONSTRUCTOR name, a module/interface/protocol/signature name, or a
    capability name contributes NOTHING here even though it very much
    introduces a name — those live in namespaces neither consumer touches.

    The match below is deliberately EXHAUSTIVE over [Ast.decl] with no
    wildcard: this list decides which self-qualified spellings
    [strip_entry_self_qual] rewrites and which bare calls [qualify_level]
    qualifies, so a name added here silently changes which definition a call
    resolves to.  A new declaration form must therefore be classified
    explicitly rather than defaulting to "not a value name".

    [externs] splits the ONE case where the two consumers genuinely disagree,
    and the split is not cosmetic — getting it wrong miscompiles.  An extern
    `fn` IS a value name of the declaring module, so
    [strip_entry_self_qual] must know about it ([externs:true]).  But it is
    NOT emitted under a module-qualified name: codegen calls it by its C
    symbol (`labs`, or `<lib>_<fn>` by default), so [qualify_level] must NOT
    rewrite a bare intra-module call to it ([externs:false]).  Measured: with
    externs folded into the qualification set, a nested module calling its own
    extern bare compiled to `Undefined symbols: _Bar.my_abs`.

    Classification evidence (each verified by running a program that spells the
    name self-qualified, `Foo.thing` inside entry `mod Foo`, against the same
    program spelling it bare):
    - [DFn], [DLet] — the two original cases; bare value names.
    - [DExtern] — an extern block's [fn]s are ordinary lowercase value names,
      but only for the stripping consumer (see [externs] above).  Pre-fix,
      `Foo.labs(-3)` inside `mod Foo` failed with
      `unbound variable: Foo.labs` (interp) / `Undefined symbols: _Foo.labs`
      (compiled) while bare `labs(-3)` resolved.
    - [DInterface], [DImpl] — deliberately NOT included, and this is the one
      genuinely close call.  An interface method name IS lowercase and IS
      reachable as an [EVar], but it is not a MODULE-QUALIFIED name in March:
      it resolves through interface dispatch, not through module member
      lookup.  Verified — with the interface declared in a nested `mod Bar`,
      BOTH `Bar.greet(1)` written from outside AND the auto-qualified form
      [qualify_level] would produce fail identically, with
      `unbound variable: Bar.greet`.  So entry-level `Foo.greet(1)` failing is
      consistent with every other module, not a stripping gap.  Including
      these names actively regresses working code: [qualify_level] would
      rewrite the bare `greet(1)` inside a nested module that declares the
      interface into `Bar.greet(1)` (measured: a program that printed
      `hi-nested` started failing `unbound variable: Bar.greet`), and for
      [DImpl] it would additionally rewrite every bare `show(x)` in a module
      that merely implements `Show`, breaking dispatch to a method the
      implementing module does not own.  Making `Foo.greet` resolve would need
      interface methods to become qualifiable in general — a separate change,
      not a classification question.
    - [DActor] — the actor NAME is a constructor, not a value: `spawn(Counter)`
      parses as [ECon], and `spawn(Foo.Counter)` fails in the constructor
      namespace ("I don't know a constructor called `Foo.Counter`"), which
      [strip_entry_self_qual] documents as out of scope.  The functions
      lowering derives from an actor are underscore-mangled
      ([Counter_spawn]/[Counter_dispatch]/[Counter_Increment], confirmed via
      `MARCH_DUMP_TXT=tir-lower`) and are unwritable in source.
    - [DType], [DAlwaysLinearType] — a type name plus constructors, both
      uppercase and both in namespaces neither consumer rewrites.
    - [DDeriving], [DSatisfy] — already expanded into [DImpl] by
      [desugar_module] before either consumer runs; classified as [DImpl].
    - [DUse], [DAlias] — bring names in from ELSEWHERE.  Treating an imported
      name as one of ours would qualify it to a definition this module does
      not have.
    - [DMod] — a nested module name is uppercase (never an [EVar]), and
      [strip_entry_self_qual] already collects nested module names separately
      for its dotted-head guard.
    - [DDescribe] — its body admits only [test]/nested [describe] (see
      [describe_body] in parser.mly), so it can hold no value declaration.
    - [DProtocol], [DSig], [DInterface]'s own name, [DProofCap], [DApp],
      [DTransitions] — uppercase names in the type/module/capability
      namespaces.
    - [DNeeds], [DOpts], [DTest], [DSetup], [DSetupAll] — declare no name at
      all. *)
let collect_direct_names ~(externs : bool) (decls : decl list) : string list =
  List.concat_map (function
    | DFn (def, _) -> [def.fn_name.txt]
    | DLet (_, b, _) ->
      (* Exhaustive with NO wildcard, for the same reason the outer decl match
         is: this list decides which names [strip_entry_self_qual] rewrites and
         which bare calls [qualify_level] qualifies, so a pattern form silently
         dropped here makes `Mod.name` fail to resolve while bare `name` works.
         [add_pat_vars] below is the reference for the full constructor set. *)
      let rec from_pat = function
        | PatVar n -> [n.txt]
        | PatCon (_, ps) | PatTuple (ps, _) | PatAtom (_, ps, _) ->
          List.concat_map from_pat ps
        | PatRecord (fs, _) -> List.concat_map (fun (_, p) -> from_pat p) fs
        | PatAs (p, n, _) -> n.txt :: from_pat p
        (* An or-pattern binds the same names in every alternative, so the first
           alternative suffices; unioning all of them would be equivalent. *)
        | PatOr (ps, _) -> (match ps with [] -> [] | p :: _ -> from_pat p)
        | PatWild _ | PatLit _ -> []
      in
      from_pat b.bind_pat
    | DExtern (ext, _) ->
      if externs then List.map (fun ef -> ef.ef_name.txt) ext.ext_fns else []
    (* Names in namespaces neither consumer rewrites, names resolved by
       interface dispatch rather than module lookup, or no name at all. *)
    | DInterface _
    | DImpl _ | DActor _ | DType _ | DAlwaysLinearType _
    | DDeriving _ | DSatisfy _ | DUse _ | DAlias _ | DMod _
    | DDescribe _ | DProtocol _ | DSig _ | DProofCap _ | DApp _
    | DTransitions _ | DNeeds _ | DOpts _ | DTest _ | DSetup _
    | DSetupAll _ -> []
  ) decls

(** Extend [bound] with all variable names introduced by [pat]. *)
let rec add_pat_vars (bound : string list) (pat : pattern) : string list =
  match pat with
  | PatVar n -> n.txt :: bound
  | PatCon (_, ps) | PatTuple (ps, _) | PatAtom (_, ps, _) ->
    List.fold_left add_pat_vars bound ps
  | PatRecord (fs, _) ->
    List.fold_left (fun b (_, p) -> add_pat_vars b p) bound fs
  | PatAs (p, n, _) -> add_pat_vars (n.txt :: bound) p
  | PatOr (ps, _) -> List.fold_left add_pat_vars bound ps
  | PatWild _ | PatLit _ -> bound

(** Return the expression walker for [prefix]/[own_names].
    [go bound e] rewrites [EVar "name"] → [EVar "prefix.name"]
    when [name ∈ own_names] and [name ∉ bound]. *)
let make_qualifier (prefix : string) (own_names : string list) =
  let is_own n = List.mem n own_names && not (String.contains n '.') in
  let rec go bound e =
    match e with
    | EVar n when is_own n.txt && not (List.mem n.txt bound) ->
      EVar { n with txt = prefix ^ n.txt }
    | ELam (ps, body, sp) ->
      let bound' = List.fold_left (fun b p -> p.param_name.txt :: b) bound ps in
      ELam (ps, go bound' body, sp)
    | EBlock (es, sp) -> EBlock (go_block bound es, sp)
    | ELet (b, sp) ->
      (* RHS does not see its own binding; add_pat_vars is handled in go_block. *)
      ELet ({ b with bind_expr = go bound b.bind_expr }, sp)
    | ELetFn (nm, ps, ret, body, sp) ->
      let bound' = List.fold_left (fun b p -> p.param_name.txt :: b) bound ps in
      ELetFn (nm, ps, ret, go bound' body, sp)
    | ELetQ (pat, result, cont, sp) ->
      ELetQ (pat, go bound result, go (add_pat_vars bound pat) cont, sp)
    | EMatch (scrut, branches, sp) ->
      let branches' = List.map (fun br ->
          let bound' = add_pat_vars bound br.branch_pat in
          { br with branch_body  = go bound' br.branch_body
                 ; branch_guard = Option.map (go bound') br.branch_guard }
        ) branches in
      EMatch (go bound scrut, branches', sp)
    | EApp (f, args, sp)        -> EApp (go bound f, List.map (go bound) args, sp)
    | ECon (n, args, sp)        -> ECon (n, List.map (go bound) args, sp)
    | ETuple (es, sp)           -> ETuple (List.map (go bound) es, sp)
    | ERecord (fs, sp)          -> ERecord (List.map (fun (n, ex) -> (n, go bound ex)) fs, sp)
    | ERecordUpdate (b, fs, sp) ->
      ERecordUpdate (go bound b, List.map (fun (n, ex) -> (n, go bound ex)) fs, sp)
    | EField (ex, n, sp)        -> EField (go bound ex, n, sp)
    | EIf (c, t, f, sp)         -> EIf (go bound c, go bound t, go bound f, sp)
    | ECond (arms, sp)          -> ECond (List.map (fun (c, b) -> (go bound c, go bound b)) arms, sp)
    | EPipe (l, r, sp)          -> EPipe (go bound l, go bound r, sp)
    | EAnnot (ex, ty, sp)       -> EAnnot (go bound ex, ty, sp)
    | EDbg (Some ex, sp)        -> EDbg (Some (go bound ex), sp)
    | ESend (cap, msg, sp)      -> ESend (go bound cap, go bound msg, sp)
    | ESpawn (ex, sp)           -> ESpawn (go bound ex, sp)
    | EAssert (ex, sp)          -> EAssert (go bound ex, sp)
    | EAtom (a, args, sp)       -> EAtom (a, List.map (go bound) args, sp)
    | ESigil (s, ex, sp)        -> ESigil (s, go bound ex, sp)
    | ELit _ | EVar _ | EHole _ | EResultRef _ | EDbg (None, _) -> e
  and go_block bound = function
    | [] -> []
    | ELet (b, sp) :: rest ->
      let b' = { b with bind_expr = go bound b.bind_expr } in
      ELet (b', sp) :: go_block (add_pat_vars bound b.bind_pat) rest
    | ELetFn (nm, ps, ret, body, sp) :: rest ->
      let bound' = List.fold_left (fun b p -> p.param_name.txt :: b) bound ps in
      ELetFn (nm, ps, ret, go bound' body, sp) :: go_block (nm.txt :: bound) rest
    | e :: rest -> go bound e :: go_block bound rest
  in
  go

(** Qualify bare intra-module calls in [DFn]/[DLet]/[DActor] at the current
    level.  Does NOT descend into nested [DMod] — those are handled by
    [qualify_module_refs]'s recursive walk. *)
let qualify_level (prefix : string) (own_names : string list) (decls : decl list) : decl list =
  let go = make_qualifier prefix own_names in
  let param_bound fps =
    List.fold_left (fun acc fp -> match fp with
      | FPNamed p | FPDefault (p, _) -> p.param_name.txt :: acc
      | FPPat (PatVar n) -> n.txt :: acc
      | FPPat _ -> acc) [] fps
  in
  List.map (function
    | DFn (def, sp) ->
      let def' = { def with fn_clauses = List.map (fun c ->
          let bound = param_bound c.fc_params in
          { c with fc_body  = go bound c.fc_body
                 ; fc_guard = Option.map (go bound) c.fc_guard }
        ) def.fn_clauses } in
      DFn (def', sp)
    | DLet (vis, b, sp) ->
      DLet (vis, { b with bind_expr = go [] b.bind_expr }, sp)
    | DActor (vis, name, actor, sp) ->
      let actor' = { actor with
        actor_init     = go [] actor.actor_init
      ; actor_handlers = List.map (fun h ->
            let bound = List.map (fun p -> p.param_name.txt) h.ah_params in
            { h with ah_body = go bound h.ah_body }) actor.actor_handlers
      } in
      DActor (vis, name, actor', sp)
    | d -> d
  ) decls

(** Qualify bare intra-module function calls throughout the declaration tree.
    For each [DMod], rewrites [EVar "name"] → [EVar "Mod.name"] in function
    bodies when [name] is a function declared directly in that module.
    The prefix accumulates as the walk descends into nested modules so that
    "MyNet" inside the top-level module gets prefix "MyNet." matching TIR.

    [entry_prefix] seeds the accumulation for [decls] itself: "" for the
    entry file (TIR unwraps its own top-level mod, so its own name must NOT
    be part of the prefix — see [Typecheck.cap_qual_prefix]'s doc comment
    for the matching convention on the typecheck side), or
    ["ModName."] for a non-entry file loaded by its own top-level module
    name (e.g. a stdlib/auto-discovered dependency file, whose [mod_decls]
    is already the UNWRAPPED body of its own [mod ModName do ... end] —
    the parser splits a file's sole top-level mod into [mod_name]/[mod_decls]
    fields on [module_], so [decls] here never contains a [DMod] node for
    the file's own name). Without this, a bare intra-module call two levels
    deep inside such a file (e.g. stdlib's [CRDT.PNCounter] calling its own
    sibling [map_inc] bare) got qualified as only "PNCounter.map_inc"
    instead of "CRDT.PNCounter.map_inc" — mismatching the fully-qualified
    name TIR lowering assigns the actual definition, which undefined-symbols
    at link time (the reference and the definition never converged). *)
let qualify_module_refs ?(entry_prefix = "") (decls : decl list) : decl list =
  let rec walk prefix decls =
    List.map (function
      | DMod (name, vis, inner, sp) ->
        let mod_prefix = prefix ^ name.txt ^ "." in
        (* [externs:false] — codegen calls an extern by its C symbol, never
           under a module-qualified name, so a bare intra-module call to one
           must be left alone.  See [collect_direct_names]'s [externs] doc. *)
        let own_names  = collect_direct_names ~externs:false inner in
        (* Recurse first so nested mods pick up their full prefix. *)
        let inner' = walk mod_prefix inner in
        (* Then qualify this module's own function bodies. *)
        DMod (name, vis, qualify_level mod_prefix own_names inner', sp)
      | d -> d
    ) decls
  in
  walk entry_prefix decls

(** Normalize hand-written references that self-qualify with the ENTRY
    module's OWN name. TIR unwraps the entry module (the parser splits a
    file's sole top-level [mod Foo do ... end] into [mod_name]/[mod_decls],
    and TIR emits those members WITHOUT the [Foo.] prefix — see
    [qualify_module_refs]'s doc comment / [entry_prefix = ""]). But a source
    reference that spells out its own module — [Foo.bar(x)] inside [mod Foo],
    or [Outer.Inner.wrapped(5)] inside entry [mod Outer] — keeps its leading
    own-name segment (a dotted [EVar] never matches [make_qualifier]'s bare
    [is_own] test), so the reference and the unwrapped definition never
    converge → "unbound variable" (interp) / "Undefined symbols" (compiled).

    This strips ONLY the single leading [mod_name ^ "."] segment from every
    [EVar], so [Foo.wrapped -> wrapped] and [Outer.Inner.wrapped ->
    Inner.wrapped] (the nested [Inner.] survives to match the nested
    definition's still-qualified emitted name). A dotted name can never be a
    local binding, so no scope tracking is needed; constructor names ([ECon])
    live in a separate namespace and are left untouched. Applied only to the
    entry module, before [qualify_module_refs].

    GUARD (must-name-something-of-ours): [mod_name] is only a genuine
    self-qualification prefix when the segment right after it names
    something this entry module ITSELF declares — a direct fn/let member
    (bare form, e.g. [Foo.bar]) or a nested [DMod] (dotted form, e.g.
    [Outer.Inner.wrapped]). Without this check, a MULTI-FILE project whose
    entry module's name is also a PREFIX of an unrelated sibling top-level
    module's dotted name — e.g. entry [mod MyApp] alongside a sibling file
    declaring top-level [mod MyApp.Router do ... end] (the documented
    "one mod per file" multi-file convention, see specs/lang/modules.md) —
    had its fully-qualified [MyApp.Router.dispatch] silently mangled to
    [Router.dispatch], which resolves to nothing (`Unknown module
    \`Router\``): "Router" is not a member OF the entry module, it is a
    DIFFERENT top-level module that merely happens to share a name prefix.
    Checking only the immediate next segment (not the whole remainder)
    correctly leaves such a reference fully qualified while still stripping
    genuine self-references, including nested ones like
    [Outer.Inner.wrapped] whose next segment ("Inner") IS a nested DMod
    declared directly in the entry's own [decls]. *)
let strip_entry_self_qual (mod_name : string) (decls : decl list) : decl list =
  let prefix = mod_name ^ "." in
  let plen = String.length prefix in
  (* [externs:true] — an extern `fn` IS a member of the entry module, so a
     self-qualified `Foo.my_extern` must be stripped like any other member. *)
  let direct_names = collect_direct_names ~externs:true decls in
  let nested_mod_names =
    List.filter_map (function DMod (n, _, _, _) -> Some n.txt | _ -> None) decls
  in
  let names_something_of_ours (suffix : string) : bool =
    let head = match String.index_opt suffix '.' with
      | Some i -> String.sub suffix 0 i
      | None -> suffix
    in
    List.mem head direct_names || List.mem head nested_mod_names
  in
  let rename (n : name) : name =
    let len = String.length n.txt in
    if len > plen && String.sub n.txt 0 plen = prefix then
      let suffix = String.sub n.txt plen (len - plen) in
      if names_something_of_ours suffix
      then { n with txt = suffix }
      else n
    else n
  in
  let rec rw e =
    match e with
    | EVar n -> EVar (rename n)
    | ELit _ | EHole _ | EResultRef _ | EDbg (None, _) -> e
    | ELam (ps, body, sp)       -> ELam (ps, rw body, sp)
    | EBlock (es, sp)           -> EBlock (List.map rw es, sp)
    | ELet (b, sp)              -> ELet ({ b with bind_expr = rw b.bind_expr }, sp)
    | ELetFn (nm, ps, ret, body, sp) -> ELetFn (nm, ps, ret, rw body, sp)
    | ELetQ (pat, result, cont, sp)  -> ELetQ (pat, rw result, rw cont, sp)
    | EMatch (scrut, branches, sp) ->
      let branches' = List.map (fun br ->
          { br with branch_body  = rw br.branch_body
                 ; branch_guard = Option.map rw br.branch_guard }) branches in
      EMatch (rw scrut, branches', sp)
    | EApp (f, args, sp)        -> EApp (rw f, List.map rw args, sp)
    | ECon (n, args, sp)        -> ECon (n, List.map rw args, sp)
    | ETuple (es, sp)           -> ETuple (List.map rw es, sp)
    | ERecord (fs, sp)          -> ERecord (List.map (fun (n, ex) -> (n, rw ex)) fs, sp)
    | ERecordUpdate (b, fs, sp) ->
      ERecordUpdate (rw b, List.map (fun (n, ex) -> (n, rw ex)) fs, sp)
    | EField (ex, n, sp)        -> EField (rw ex, n, sp)
    | EIf (c, t, f, sp)         -> EIf (rw c, rw t, rw f, sp)
    | ECond (arms, sp)          -> ECond (List.map (fun (c, b) -> (rw c, rw b)) arms, sp)
    | EPipe (l, r, sp)          -> EPipe (rw l, rw r, sp)
    | EAnnot (ex, ty, sp)       -> EAnnot (rw ex, ty, sp)
    | EDbg (Some ex, sp)        -> EDbg (Some (rw ex), sp)
    | ESend (cap, msg, sp)      -> ESend (rw cap, rw msg, sp)
    | ESpawn (ex, sp)           -> ESpawn (rw ex, sp)
    | EAssert (ex, sp)          -> EAssert (rw ex, sp)
    | EAtom (a, args, sp)       -> EAtom (a, List.map rw args, sp)
    | ESigil (s, ex, sp)        -> ESigil (s, rw ex, sp)
  in
  let rw_fn (def : fn_def) =
    { def with fn_clauses = List.map (fun c ->
        { c with fc_body  = rw c.fc_body
               ; fc_guard = Option.map rw c.fc_guard }) def.fn_clauses }
  in
  (* Exhaustive over [decl] — NO wildcard.  The `| d -> d` that used to close
     this match meant a self-qualified reference survived unstripped in every
     declaration form except `fn`, `let`, `actor` and `mod`: `OuterB.g(-9)`
     inside an `impl` method of the entry module `OuterB` stayed a dotted name
     that nothing downstream resolves to the plain `g`, so the refinement
     checker silently raised no obligation for it while the identical call in a
     sibling `fn` was reported.  A new declaration form must be a compile error
     here rather than another silent asymmetry. *)
  let rec strip_decls decls =
    List.map (function
      | DFn (def, sp) -> DFn (rw_fn def, sp)
      | DLet (vis, b, sp) -> DLet (vis, { b with bind_expr = rw b.bind_expr }, sp)
      | DActor (vis, name, actor, sp) ->
        let actor' = { actor with
          actor_init      = rw actor.actor_init
        ; actor_handlers  = List.map (fun h -> { h with ah_body = rw h.ah_body })
                              actor.actor_handlers
        ; actor_invariant = Option.map rw actor.actor_invariant } in
        DActor (vis, name, actor', sp)
      | DMod (name, vis, inner, sp) -> DMod (name, vis, strip_decls inner, sp)
      | DImpl (idf, sp) ->
        DImpl ({ idf with impl_methods =
                            List.map (fun (n, def) -> (n, rw_fn def)) idf.impl_methods }, sp)
      | DInterface (idf, sp) ->
        DInterface ({ idf with iface_methods =
                                 List.map (fun (m : method_decl) ->
                                     { m with md_default = Option.map rw m.md_default })
                                   idf.iface_methods }, sp)
      | DApp (app, sp) ->
        DApp ({ app with app_body     = rw app.app_body
                       ; app_on_start = Option.map rw app.app_on_start
                       ; app_on_stop  = Option.map rw app.app_on_stop }, sp)
      | DTest (t, sp) -> DTest ({ t with test_body = rw t.test_body }, sp)
      | DSetup (e, sp) -> DSetup (rw e, sp)
      | DSetupAll (e, sp) -> DSetupAll (rw e, sp)
      (* A `describe` block is part of its module's scope, so its decls are
         stripped against the SAME prefix — not re-derived like a nested mod. *)
      | DDescribe (name, ds, sp) -> DDescribe (name, strip_decls ds, sp)
      (* ── Inert: no expression that can carry a self-qualified name. ────── *)
      | DType _ | DAlwaysLinearType _   (* type definitions: types only *)
      | DSig _                          (* signature: names and types only *)
      | DProtocol _                     (* session type: message types *)
      | DTransitions _                  (* state-machine edges: bare fn names *)
      | DExtern _                       (* FFI signatures; bodies live in C *)
      | DNeeds _ | DProofCap _ | DOpts _ (* capability paths / names / flags *)
      | DDeriving _ | DSatisfy _        (* expanded into DImpl later in desugar *)
      | DUse _ | DAlias _ as d -> d     (* import/alias paths, not references *)
    ) decls
  in
  strip_decls decls

(** Desugar an entire module.  Returns a new [module_] with all multi-head
    fns and pipe expressions lowered to their core forms.
    Also injects default interface method bodies into impls that omit them.
    [DDeriving] nodes are expanded into [DImpl] blocks here.

    [is_entry] (default [true], matching every pre-existing caller's actual
    usage) controls whether [m.mod_name] itself is included when qualifying
    bare intra-module calls (see [qualify_module_refs]'s doc comment): the
    program's entry file must NOT have its own top-level mod name folded in
    (TIR unwraps it — its members are emitted bare), but a non-entry file
    loaded by name (a stdlib module or an auto-discovered dependency, via
    [Resolver]) must, since TIR keeps ITS OWN top-level mod name as part of
    every member's fully-qualified emitted name. *)
let desugar_module ?errors ?(is_entry = true) (m : module_) : module_ =
  (* Only route expression-level errors into the context when the CALLER
     supplied one (and therefore inspects it): reporting into a defaulted
     throwaway context would silently swallow the diagnostic and return
     wrong desugared code. Context-less callers get the loud positioned
     ParseError from [desugar_expr_error] instead. *)
  let caller_ctx = errors in
  let errors = match errors with Some c -> c | None -> Err.create () in
  let saved_ctx = !expr_err_ctx in
  expr_err_ctx := caller_ctx;
  Fun.protect ~finally:(fun () -> expr_err_ctx := saved_ctx) @@ fun () ->
  check_app_main_exclusivity errors m.mod_decls;
  check_main_signature errors m.mod_decls;
  (* Collect type definitions so derive expansion can reference them. *)
  let type_defs = collect_type_defs m.mod_decls in
  (* Collect interfaces and fns for satisfy expansion. *)
  let raw_ifaces = collect_interfaces m.mod_decls in
  let raw_fns    = collect_fns m.mod_decls in
  (* Expand DDeriving and DSatisfy nodes; desugar everything else. *)
  let expanded = List.concat_map (fun d ->
      match d with
      | DDeriving (type_name, ifaces, sp) ->
        expand_derive errors type_defs type_name ifaces sp
      | DSatisfy (iface_names, type_names, sp) ->
        expand_satisfy errors raw_ifaces raw_fns iface_names type_names sp
      | _ -> expand_defaults_decl d
    ) m.mod_decls in
  (* Auto-generate island bridge functions if this is an island module. *)
  let expanded = maybe_inject_island_bridges m.mod_decls expanded in
  let interfaces = collect_interfaces expanded in
  let decls = List.map (fun d ->
      inject_defaults interfaces (desugar_decl d)
    ) expanded in
  (* The entry file's own top-level mod name is unwrapped by TIR, so a
     source reference that self-qualifies with it (e.g. [Foo.bar] inside
     [mod Foo]) must have that leading segment stripped before qualification,
     or the reference never converges on the bare-emitted definition. *)
  let decls =
    if is_entry then strip_entry_self_qual m.mod_name.txt decls else decls in
  let entry_prefix = if is_entry then "" else m.mod_name.txt ^ "." in
  let decls = qualify_module_refs ~entry_prefix decls in
  { m with mod_decls = decls }
