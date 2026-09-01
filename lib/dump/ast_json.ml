(** Core-AST -> JSON serializer.

    Serializes the desugared [March_ast.Ast] tree (the "core AST" — i.e. the
    [user_ast] binding produced right after [desugar_module], before stdlib
    injection / import resolution) to JSON, for the [--emit-core-ast] CLI
    flag (wired in a later task) and consumption by the independent
    Lean-side conformance checker.

    Design contract (see specs/plans/2026-07-20-emit-core-ast-a0.md
    "Global Constraints"):

    - TOTAL: one JSON encoding per OCaml constructor, for every type in
      the same recursive group as [Ast.expr]/[Ast.decl]. Every match here
      is EXHAUSTIVE — no wildcard [_ ->] catch-all anywhere in this file,
      so adding a new AST constructor is a compile error here, not a
      silent gap.
    - Every constructor of a multi-constructor (variant) type is encoded
      as a JSON object tagged with ["kind":"ConstructorName"], uniformly
      — including payload-less constructors (e.g. [Linear] ->
      [{"kind":"Linear"}]) — so a Lean-side deserializer can always expect
      a tagged object for these types, never a bare JSON string.
      Single-constructor record types (e.g. [param], [binding], [module_])
      are encoded directly as a JSON object of their fields, with no
      ["kind"] wrapper (there is no ambiguity to tag).
    - Every AST node that carries an explicit [span] field includes it
      under the key ["span"] in its JSON object. Nodes that do NOT carry
      a span field of their own (e.g. [EResultRef], [test_def], most [ty]
      constructors) do not fabricate one — the JSON simply omits ["span"]
      for that node, matching the source of truth exactly. Nested [name]
      values still carry their own ["span"] as always.
    - Reuses [Dump.json_string] / [Dump.json_obj] / [Dump.json_list] — no
      second hand-rolled JSON encoder.

    Note on numeric encoding: unlike [dump.ml] (whose JSON output feeds a
    debugging UI and quotes numbers as strings for uniformity), this
    serializer emits genuine JSON numbers for integers and floats, since
    its target is a real JSON-consuming parser (the Lean checker), not a
    JS viewer — this matches the "format_version is a JSON integer"
    contract in the Global Constraints. *)

open March_ast.Ast
module T = March_typecheck.Typecheck

(* ------------------------------------------------------------------ *)
(* Generic helpers                                                     *)
(* ------------------------------------------------------------------ *)

let json_bool b = if b then "true" else "false"
let json_int (n : int) = string_of_int n

(* JSON has no NaN/Infinity literals; encode those as tagged strings and
   everything else as a plain JSON number via a round-trippable format. *)
let json_float (f : float) : string =
  if f <> f then Dump.json_string "NaN"
  else if f = Float.infinity then Dump.json_string "Infinity"
  else if f = Float.neg_infinity then Dump.json_string "-Infinity"
  else Printf.sprintf "%.17g" f

let json_opt (f : 'a -> string) (o : 'a option) : string =
  match o with
  | None -> "null"
  | Some x -> f x

(* ------------------------------------------------------------------ *)
(* span / name                                                         *)
(* ------------------------------------------------------------------ *)

let span_to_json (s : span) : string =
  Dump.json_obj [
    ("file", Dump.json_string s.file);
    ("start_line", json_int s.start_line);
    ("start_col", json_int s.start_col);
    ("end_line", json_int s.end_line);
    ("end_col", json_int s.end_col);
  ]

let name_to_json (n : name) : string =
  Dump.json_obj [
    ("txt", Dump.json_string n.txt);
    ("span", span_to_json n.span);
  ]

(* ------------------------------------------------------------------ *)
(* Simple enums                                                        *)
(* ------------------------------------------------------------------ *)

let linearity_to_json (l : linearity) : string =
  match l with
  | Unrestricted -> Dump.json_obj [ ("kind", Dump.json_string "Unrestricted") ]
  | Linear -> Dump.json_obj [ ("kind", Dump.json_string "Linear") ]
  | Affine -> Dump.json_obj [ ("kind", Dump.json_string "Affine") ]

let visibility_to_json (v : visibility) : string =
  match v with
  | Private -> Dump.json_obj [ ("kind", Dump.json_string "Private") ]
  | Public -> Dump.json_obj [ ("kind", Dump.json_string "Public") ]

(* ------------------------------------------------------------------ *)
(* Internal (elaborated) ty / constraint_ -> JSON                      *)
(* (distinct from the surface [ty_to_json] below: this encodes         *)
(* [March_typecheck.Typecheck.ty], the post-elaboration internal type  *)
(* representation, for --emit-core-ast v2's HM-witness annotations.    *)
(* Defined up here, ahead of [expr_to_json], because [expr_to_json]    *)
(* calls it (via [resolved_ty_field]) to emit each node's              *)
(* ["resolved_ty"] field.) *)
(* ------------------------------------------------------------------ *)

let lin_str : linearity -> string = function
  | Linear -> "linear"
  | Affine -> "affine"
  | Unrestricted -> "unrestricted"

let natop_str : nat_op -> string = function
  | NatAdd -> "add"
  | NatMul -> "mul"

(* Internal-ty -> JSON. Deep-repr at every level: resolve the head, then
   recurse (each recursive call re-reprs its argument). Total over T.ty.
   Contract: see test/test_ty_json.ml and the A1 design doc §2. *)
let rec resolved_ty_to_json (t : T.ty) : string =
  match T.repr t with
  | T.TCon (name, args) ->
    Dump.json_obj
      [ ("kind", Dump.json_string "TCon");
        ("name", Dump.json_string name);
        ("args", Dump.json_list (List.map resolved_ty_to_json args)) ]
  | T.TArrow (a, b) ->
    Dump.json_obj
      [ ("kind", Dump.json_string "TArrow");
        ("from", resolved_ty_to_json a);
        ("to", resolved_ty_to_json b) ]
  | T.TTuple ts ->
    Dump.json_obj
      [ ("kind", Dump.json_string "TTuple");
        ("elems", Dump.json_list (List.map resolved_ty_to_json ts)) ]
  | T.TRecord flds ->
    Dump.json_obj
      [ ("kind", Dump.json_string "TRecord");
        ("fields",
         Dump.json_list
           (List.map
              (fun (n, ft) ->
                Dump.json_obj
                  [ ("name", Dump.json_string n);
                    ("ty", resolved_ty_to_json ft) ])
              flds)) ]
  | T.TVar r ->
    (match !r with
     | T.Unbound (id, _) ->
       Dump.json_obj
         [ ("kind", Dump.json_string "TVar"); ("id", string_of_int id) ]
     | T.Link _ ->
       (* repr already follows links; unreachable, but stay total. *)
       resolved_ty_to_json (T.repr t))
  | T.TLin (l, inner) ->
    Dump.json_obj
      [ ("kind", Dump.json_string "TLin");
        ("lin", Dump.json_string (lin_str l));
        ("ty", resolved_ty_to_json inner) ]
  | T.TNat n ->
    Dump.json_obj
      [ ("kind", Dump.json_string "TNat"); ("n", string_of_int n) ]
  | T.TNatOp (op, a, b) ->
    Dump.json_obj
      [ ("kind", Dump.json_string "TNatOp");
        ("op", Dump.json_string (natop_str op));
        ("a", resolved_ty_to_json a);
        ("b", resolved_ty_to_json b) ]
  | T.TChan _ ->
    Dump.json_obj
      [ ("kind", Dump.json_string "unsupported");
        ("what", Dump.json_string "session") ]
  | T.TError -> Dump.json_obj [ ("kind", Dump.json_string "TError") ]
  | T.TRefine (base, _, _) ->
    (* repr strips TRefine, so this is unreachable; recurse defensively. *)
    resolved_ty_to_json base

let constraint_to_json : T.constraint_ -> string = function
  | T.CNum t ->
    Dump.json_obj [ ("kind", Dump.json_string "CNum"); ("ty", resolved_ty_to_json t) ]
  | T.COrd t ->
    Dump.json_obj [ ("kind", Dump.json_string "COrd"); ("ty", resolved_ty_to_json t) ]
  | T.CInterface (n, t) ->
    Dump.json_obj
      [ ("kind", Dump.json_string "CInterface");
        ("name", Dump.json_string n);
        ("ty", resolved_ty_to_json t) ]
  | T.CADTBound (n, t) ->
    Dump.json_obj
      [ ("kind", Dump.json_string "CADTBound");
        ("name", Dump.json_string n);
        ("ty", resolved_ty_to_json t) ]
  | T.CTNatBound t ->
    Dump.json_obj [ ("kind", Dump.json_string "CTNatBound"); ("ty", resolved_ty_to_json t) ]

(* [resolved_ty] annotation plumbing for --emit-core-ast v2.

   [module_to_json] is called exactly once per CLI invocation (or per test
   call, sequentially), so a file-local ref carrying the current run's
   [type_map] is simpler than threading a [~types] labeled parameter through
   every mutually-recursive encoder in this file (expr_to_json's own
   [and]-group, plus the much larger decl_to_json group that reaches exprs
   transitively through fn_clause_to_json, actor_handler_to_json,
   test_def_to_json, etc.) — only [module_to_json]'s signature changes;
   every other encoder here is untouched. [module_to_json] sets this before
   walking the tree; [resolved_ty_field] reads it by span by exact identity
   with however the typechecker keyed [type_map] (see
   [March_typecheck.Typecheck.span_of_expr], which we call directly on each
   expr node so this can never drift from the typechecker's own key). *)
let current_types : (span, T.ty) Hashtbl.t option ref = ref None

let resolved_ty_field (sp : span) : string * string =
  match !current_types with
  | None -> ("resolved_ty", "null")
  | Some tbl ->
    (match Hashtbl.find_opt tbl sp with
     | Some t -> ("resolved_ty", resolved_ty_to_json t)
     | None -> ("resolved_ty", "null"))

(* ------------------------------------------------------------------ *)
(* literal                                                             *)
(* ------------------------------------------------------------------ *)

let literal_to_json (lit : literal) : string =
  match lit with
  | LitInt n ->
    Dump.json_obj [ ("kind", Dump.json_string "LitInt"); ("value", json_int n) ]
  | LitFloat f ->
    Dump.json_obj [ ("kind", Dump.json_string "LitFloat"); ("value", json_float f) ]
  | LitString s ->
    Dump.json_obj [ ("kind", Dump.json_string "LitString"); ("value", Dump.json_string s) ]
  | LitBool b ->
    Dump.json_obj [ ("kind", Dump.json_string "LitBool"); ("value", json_bool b) ]
  | LitAtom a ->
    Dump.json_obj [ ("kind", Dump.json_string "LitAtom"); ("value", Dump.json_string a) ]

(* ------------------------------------------------------------------ *)
(* pattern                                                             *)
(* ------------------------------------------------------------------ *)

let rec pattern_to_json (p : pattern) : string =
  match p with
  | PatWild span ->
    Dump.json_obj [ ("kind", Dump.json_string "PatWild"); ("span", span_to_json span) ]
  | PatVar n ->
    Dump.json_obj [ ("kind", Dump.json_string "PatVar"); ("name", name_to_json n) ]
  | PatCon (n, args) ->
    Dump.json_obj [
      ("kind", Dump.json_string "PatCon");
      ("name", name_to_json n);
      ("args", Dump.json_list (List.map pattern_to_json args));
    ]
  | PatAtom (a, args, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "PatAtom");
      ("atom", Dump.json_string a);
      ("args", Dump.json_list (List.map pattern_to_json args));
      ("span", span_to_json span);
    ]
  | PatTuple (elts, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "PatTuple");
      ("elements", Dump.json_list (List.map pattern_to_json elts));
      ("span", span_to_json span);
    ]
  | PatLit (lit, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "PatLit");
      ("literal", literal_to_json lit);
      ("span", span_to_json span);
    ]
  | PatRecord (fields, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "PatRecord");
      ("fields", Dump.json_list (List.map (fun (n, p) ->
           Dump.json_obj [ ("name", name_to_json n); ("pattern", pattern_to_json p) ])
           fields));
      ("span", span_to_json span);
    ]
  | PatAs (p, n, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "PatAs");
      ("pattern", pattern_to_json p);
      ("name", name_to_json n);
      ("span", span_to_json span);
    ]
  | PatOr (ps, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "PatOr");
      ("patterns", Dump.json_list (List.map pattern_to_json ps));
      ("span", span_to_json span);
    ]

(* ------------------------------------------------------------------ *)
(* expr / param / binding / branch / ty / nat_op                       *)
(* (mutually recursive group, mirroring ast.ml's [and] chain)          *)
(* ------------------------------------------------------------------ *)

let rec expr_to_json (e : expr) : string =
  (* Computed once per node, from the outer [e] — captured here, ahead of the
     match, so per-arm shadowing of the name [e] (e.g. [EAnnot (e, ty, span)],
     [EDbg (e, span)], [EAssert (e, span)]) can never affect which expr this
     span was derived from. Uses the typechecker's own [span_of_expr] so the
     lookup key is *exactly* how [type_map] was populated (T.ty Hashtbl.t
     keyed by [Ast.span]) — not a re-derived/guessed span. *)
  let rty = resolved_ty_field (T.span_of_expr e) in
  match e with
  | ELit (lit, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "ELit");
      ("literal", literal_to_json lit);
      ("span", span_to_json span);
      rty;
    ]
  | EVar n ->
    Dump.json_obj [ ("kind", Dump.json_string "EVar"); ("name", name_to_json n); rty ]
  | EApp (fn, args, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "EApp");
      ("fn", expr_to_json fn);
      ("args", Dump.json_list (List.map expr_to_json args));
      ("span", span_to_json span);
      rty;
    ]
  | ECon (n, args, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "ECon");
      ("name", name_to_json n);
      ("args", Dump.json_list (List.map expr_to_json args));
      ("span", span_to_json span);
      rty;
    ]
  | ELam (params, body, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "ELam");
      ("params", Dump.json_list (List.map param_to_json params));
      ("body", expr_to_json body);
      ("span", span_to_json span);
      rty;
    ]
  | EBlock (exprs, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "EBlock");
      ("exprs", Dump.json_list (List.map expr_to_json exprs));
      ("span", span_to_json span);
      rty;
    ]
  | ELet (b, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "ELet");
      ("binding", binding_to_json b);
      ("span", span_to_json span);
      rty;
    ]
  | EMatch (scrutinee, branches, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "EMatch");
      ("scrutinee", expr_to_json scrutinee);
      ("branches", Dump.json_list (List.map branch_to_json branches));
      ("span", span_to_json span);
      rty;
    ]
  | ETuple (elts, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "ETuple");
      ("elements", Dump.json_list (List.map expr_to_json elts));
      ("span", span_to_json span);
      rty;
    ]
  | ERecord (fields, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "ERecord");
      ("fields", Dump.json_list (List.map (fun (n, e) ->
           Dump.json_obj [ ("name", name_to_json n); ("value", expr_to_json e) ])
           fields));
      ("span", span_to_json span);
      rty;
    ]
  | ERecordUpdate (base, fields, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "ERecordUpdate");
      ("base", expr_to_json base);
      ("fields", Dump.json_list (List.map (fun (n, e) ->
           Dump.json_obj [ ("name", name_to_json n); ("value", expr_to_json e) ])
           fields));
      ("span", span_to_json span);
      rty;
    ]
  | EField (target, n, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "EField");
      ("target", expr_to_json target);
      ("field", name_to_json n);
      ("span", span_to_json span);
      rty;
    ]
  | EIf (cond, then_, else_, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "EIf");
      ("cond", expr_to_json cond);
      ("then_", expr_to_json then_);
      ("else_", expr_to_json else_);
      ("span", span_to_json span);
      rty;
    ]
  | ECond (arms, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "ECond");
      ("arms", Dump.json_list (List.map (fun (c, b) ->
           Dump.json_obj [ ("cond", expr_to_json c); ("body", expr_to_json b) ])
           arms));
      ("span", span_to_json span);
      rty;
    ]
  | EPipe (lhs, rhs, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "EPipe");
      ("lhs", expr_to_json lhs);
      ("rhs", expr_to_json rhs);
      ("span", span_to_json span);
      rty;
    ]
  | EAnnot (e, ty, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "EAnnot");
      ("expr", expr_to_json e);
      ("ty", ty_to_json ty);
      ("span", span_to_json span);
      rty;
    ]
  | EHole (n, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "EHole");
      ("name", json_opt name_to_json n);
      ("span", span_to_json span);
      rty;
    ]
  | EAtom (a, args, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "EAtom");
      ("atom", Dump.json_string a);
      ("args", Dump.json_list (List.map expr_to_json args));
      ("span", span_to_json span);
      rty;
    ]
  | ESend (cap, msg, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "ESend");
      ("cap", expr_to_json cap);
      ("msg", expr_to_json msg);
      ("span", span_to_json span);
      rty;
    ]
  | ESpawn (actor, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "ESpawn");
      ("actor", expr_to_json actor);
      ("span", span_to_json span);
      rty;
    ]
  | EResultRef idx ->
    (* No span field on this constructor — REPL-only magic value.
       [T.span_of_expr] maps it to [Ast.dummy_span] for [type_map] lookup
       purposes (see typecheck.ml); [rty] is derived the same way here, so
       it will be ["resolved_ty":null] unless something was recorded at
       [dummy_span], matching the typechecker's own behavior exactly. *)
    Dump.json_obj [
      ("kind", Dump.json_string "EResultRef");
      ("index", json_opt json_int idx);
      rty;
    ]
  | EDbg (e, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "EDbg");
      ("expr", json_opt expr_to_json e);
      ("span", span_to_json span);
      rty;
    ]
  | ELetFn (n, params, ret_ty, body, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "ELetFn");
      ("name", name_to_json n);
      ("params", Dump.json_list (List.map param_to_json params));
      ("ret_ty", json_opt ty_to_json ret_ty);
      ("body", expr_to_json body);
      ("span", span_to_json span);
      rty;
    ]
  | ELetQ (pat, value, cont, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "ELetQ");
      ("pattern", pattern_to_json pat);
      ("value", expr_to_json value);
      ("cont", expr_to_json cont);
      ("span", span_to_json span);
      rty;
    ]
  | ELetStar (pat, value, cont, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "ELetStar");
      ("pattern", pattern_to_json pat);
      ("value", expr_to_json value);
      ("cont", expr_to_json cont);
      ("span", span_to_json span);
      rty;
    ]
  | EAssert (e, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "EAssert");
      ("expr", expr_to_json e);
      ("span", span_to_json span);
      rty;
    ]
  | ESigil (name, content, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "ESigil");
      ("sigil", Dump.json_string name);
      ("content", expr_to_json content);
      ("span", span_to_json span);
      rty;
    ]

and param_to_json (p : param) : string =
  Dump.json_obj [
    ("name", name_to_json p.param_name);
    ("ty", json_opt ty_to_json p.param_ty);
    ("lin", linearity_to_json p.param_lin);
  ]

and binding_to_json (b : binding) : string =
  Dump.json_obj [
    ("pattern", pattern_to_json b.bind_pat);
    ("ty", json_opt ty_to_json b.bind_ty);
    ("lin", linearity_to_json b.bind_lin);
    ("expr", expr_to_json b.bind_expr);
  ]

and branch_to_json (b : branch) : string =
  Dump.json_obj [
    ("pattern", pattern_to_json b.branch_pat);
    ("guard", json_opt expr_to_json b.branch_guard);
    ("body", expr_to_json b.branch_body);
  ]

and ty_to_json (t : ty) : string =
  match t with
  | TyCon (n, args) ->
    Dump.json_obj [
      ("kind", Dump.json_string "TyCon");
      ("name", name_to_json n);
      ("args", Dump.json_list (List.map ty_to_json args));
    ]
  | TyVar n ->
    Dump.json_obj [ ("kind", Dump.json_string "TyVar"); ("name", name_to_json n) ]
  | TyArrow (from_, to_) ->
    Dump.json_obj [
      ("kind", Dump.json_string "TyArrow");
      ("from", ty_to_json from_);
      ("to", ty_to_json to_);
    ]
  | TyTuple elts ->
    Dump.json_obj [
      ("kind", Dump.json_string "TyTuple");
      ("elements", Dump.json_list (List.map ty_to_json elts));
    ]
  | TyRecord fields ->
    Dump.json_obj [
      ("kind", Dump.json_string "TyRecord");
      ("fields", Dump.json_list (List.map (fun (n, t) ->
           Dump.json_obj [ ("name", name_to_json n); ("ty", ty_to_json t) ])
           fields));
    ]
  | TyLinear (lin, t) ->
    Dump.json_obj [
      ("kind", Dump.json_string "TyLinear");
      ("lin", linearity_to_json lin);
      ("ty", ty_to_json t);
    ]
  | TyNat n ->
    Dump.json_obj [ ("kind", Dump.json_string "TyNat"); ("value", json_int n) ]
  | TyNatOp (op, a, b) ->
    Dump.json_obj [
      ("kind", Dump.json_string "TyNatOp");
      ("op", nat_op_to_json op);
      ("lhs", ty_to_json a);
      ("rhs", ty_to_json b);
    ]
  | TyChan (role, protocol) ->
    Dump.json_obj [
      ("kind", Dump.json_string "TyChan");
      ("role", name_to_json role);
      ("protocol", name_to_json protocol);
    ]
  | TyRefine (base, binder, pred) ->
    Dump.json_obj [
      ("kind", Dump.json_string "TyRefine");
      ("base", ty_to_json base);
      ("binder", json_opt name_to_json binder);
      ("predicate", expr_to_json pred);
    ]

and nat_op_to_json (op : nat_op) : string =
  match op with
  | NatAdd -> Dump.json_obj [ ("kind", Dump.json_string "NatAdd") ]
  | NatMul -> Dump.json_obj [ ("kind", Dump.json_string "NatMul") ]

(* ------------------------------------------------------------------ *)
(* transition (used by DTransitions; not part of the [expr]/[decl]     *)
(* recursive groups in ast.ml, but reachable from [decl] all the same) *)
(* ------------------------------------------------------------------ *)

let transition_to_json (t : transition) : string =
  Dump.json_obj [
    ("resource", name_to_json t.tr_resource);
    ("from", name_to_json t.tr_from);
    ("to", name_to_json t.tr_to);
    ("via", name_to_json t.tr_via);
    ("span", span_to_json t.tr_span);
  ]

(* ------------------------------------------------------------------ *)
(* decl and its recursive-group auxiliaries                            *)
(* ------------------------------------------------------------------ *)

let rec decl_to_json (d : decl) : string =
  match d with
  | DFn (fd, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DFn");
      ("fn", fn_def_to_json fd);
      ("span", span_to_json span);
    ]
  | DLet (vis, b, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DLet");
      ("vis", visibility_to_json vis);
      ("binding", binding_to_json b);
      ("span", span_to_json span);
    ]
  | DType (vis, n, params, def, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DType");
      ("vis", visibility_to_json vis);
      ("name", name_to_json n);
      ("params", Dump.json_list (List.map name_to_json params));
      ("def", type_def_to_json def);
      ("span", span_to_json span);
    ]
  | DActor (vis, n, ad, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DActor");
      ("vis", visibility_to_json vis);
      ("name", name_to_json n);
      ("actor", actor_def_to_json ad);
      ("span", span_to_json span);
    ]
  | DProtocol (n, pd, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DProtocol");
      ("name", name_to_json n);
      ("protocol", protocol_def_to_json pd);
      ("span", span_to_json span);
    ]
  | DMod (n, vis, decls, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DMod");
      ("name", name_to_json n);
      ("vis", visibility_to_json vis);
      ("decls", Dump.json_list (List.map decl_to_json decls));
      ("span", span_to_json span);
    ]
  | DSig (n, sd, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DSig");
      ("name", name_to_json n);
      ("sig_", sig_def_to_json sd);
      ("span", span_to_json span);
    ]
  | DInterface (id, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DInterface");
      ("interface", interface_def_to_json id);
      ("span", span_to_json span);
    ]
  | DImpl (impl, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DImpl");
      ("impl", impl_def_to_json impl);
      ("span", span_to_json span);
    ]
  | DExtern (ed, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DExtern");
      ("extern", extern_def_to_json ed);
      ("span", span_to_json span);
    ]
  | DUse (ud, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DUse");
      ("use", use_decl_to_json ud);
      ("span", span_to_json span);
    ]
  | DAlias (ad, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DAlias");
      ("alias", alias_decl_to_json ad);
      ("span", span_to_json span);
    ]
  | DNeeds (paths, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DNeeds");
      (* Scope emitted alongside the path so a dumped AST is not a widened
         version of the source. *)
      ("paths", Dump.json_list (List.map (fun (path, _scope) ->
           Dump.json_list (List.map name_to_json path)) paths));
      ("scopes", Dump.json_list (List.map (fun (_p, scope) ->
           match scope with
           | None -> Dump.json_string ""
           | Some sc -> Dump.json_string sc) paths));
      ("span", span_to_json span);
    ]
  | DProofCap (n, _dict, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DProofCap");
      ("name", name_to_json n);
      ("span", span_to_json span);
    ]
  | DOpts (opts, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DOpts");
      ("opts", Dump.json_list (List.map Dump.json_string opts));
      ("span", span_to_json span);
    ]
  | DAlwaysLinearType (vis, n, params, def, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DAlwaysLinearType");
      ("vis", visibility_to_json vis);
      ("name", name_to_json n);
      ("params", Dump.json_list (List.map name_to_json params));
      ("def", type_def_to_json def);
      ("span", span_to_json span);
    ]
  | DTransitions (n, transitions, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DTransitions");
      ("name", name_to_json n);
      ("transitions", Dump.json_list (List.map transition_to_json transitions));
      ("span", span_to_json span);
    ]
  | DApp (ap, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DApp");
      ("app", app_def_to_json ap);
      ("span", span_to_json span);
    ]
  | DDeriving (ty_name, ifaces, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DDeriving");
      ("type_name", name_to_json ty_name);
      ("interfaces", Dump.json_list (List.map name_to_json ifaces));
      ("span", span_to_json span);
    ]
  | DSatisfy (ifaces, tys, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DSatisfy");
      ("interfaces", Dump.json_list (List.map name_to_json ifaces));
      ("types", Dump.json_list (List.map name_to_json tys));
      ("span", span_to_json span);
    ]
  | DTest (td, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DTest");
      ("test", test_def_to_json td);
      ("span", span_to_json span);
    ]
  | DDescribe (descr, decls, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DDescribe");
      ("description", Dump.json_string descr);
      ("decls", Dump.json_list (List.map decl_to_json decls));
      ("span", span_to_json span);
    ]
  | DSetup (e, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DSetup");
      ("expr", expr_to_json e);
      ("span", span_to_json span);
    ]
  | DSetupAll (e, span) ->
    Dump.json_obj [
      ("kind", Dump.json_string "DSetupAll");
      ("expr", expr_to_json e);
      ("span", span_to_json span);
    ]

and test_def_to_json (td : test_def) : string =
  Dump.json_obj [
    ("name", Dump.json_string td.test_name);
    ("body", expr_to_json td.test_body);
  ]

and app_def_to_json (ap : app_def) : string =
  Dump.json_obj [
    ("name", name_to_json ap.app_name);
    ("body", expr_to_json ap.app_body);
    ("on_start", json_opt expr_to_json ap.app_on_start);
    ("on_stop", json_opt expr_to_json ap.app_on_stop);
  ]

and use_decl_to_json (ud : use_decl) : string =
  Dump.json_obj [
    ("path", Dump.json_list (List.map name_to_json ud.use_path));
    ("selector", use_selector_to_json ud.use_sel);
  ]

and alias_decl_to_json (ad : alias_decl) : string =
  Dump.json_obj [
    ("path", Dump.json_list (List.map name_to_json ad.alias_path));
    ("name", name_to_json ad.alias_name);
  ]

and use_selector_to_json (sel : use_selector) : string =
  match sel with
  | UseAll -> Dump.json_obj [ ("kind", Dump.json_string "UseAll") ]
  | UseNames names ->
    Dump.json_obj [
      ("kind", Dump.json_string "UseNames");
      ("names", Dump.json_list (List.map name_to_json names));
    ]
  | UseSingle -> Dump.json_obj [ ("kind", Dump.json_string "UseSingle") ]
  | UseExcept names ->
    Dump.json_obj [
      ("kind", Dump.json_string "UseExcept");
      ("names", Dump.json_list (List.map name_to_json names));
    ]

and fn_def_to_json (fd : fn_def) : string =
  Dump.json_obj [
    ("name", name_to_json fd.fn_name);
    ("vis", visibility_to_json fd.fn_vis);
    ("doc", json_opt Dump.json_string fd.fn_doc);
    ("attrs", Dump.json_list (List.map Dump.json_string fd.fn_attrs));
    ("ret_ty", json_opt ty_to_json fd.fn_ret_ty);
    ("clauses", Dump.json_list (List.map fn_clause_to_json fd.fn_clauses));
    ("bounds", Dump.json_list (List.map (fun (n, t) ->
         Dump.json_obj [ ("name", name_to_json n); ("ty", ty_to_json t) ])
         fd.fn_bounds));
  ]

and fn_clause_to_json (fc : fn_clause) : string =
  Dump.json_obj [
    ("params", Dump.json_list (List.map fn_param_to_json fc.fc_params));
    ("guard", json_opt expr_to_json fc.fc_guard);
    ("body", expr_to_json fc.fc_body);
    ("span", span_to_json fc.fc_span);
  ]

and fn_param_to_json (fp : fn_param) : string =
  match fp with
  | FPPat p ->
    Dump.json_obj [ ("kind", Dump.json_string "FPPat"); ("pattern", pattern_to_json p) ]
  | FPNamed p ->
    Dump.json_obj [ ("kind", Dump.json_string "FPNamed"); ("param", param_to_json p) ]
  | FPDefault (p, e) ->
    Dump.json_obj [
      ("kind", Dump.json_string "FPDefault");
      ("param", param_to_json p);
      ("default", expr_to_json e);
    ]

and type_def_to_json (td : type_def) : string =
  match td with
  | TDAlias ty ->
    Dump.json_obj [ ("kind", Dump.json_string "TDAlias"); ("ty", ty_to_json ty) ]
  | TDVariant variants ->
    Dump.json_obj [
      ("kind", Dump.json_string "TDVariant");
      ("variants", Dump.json_list (List.map variant_to_json variants));
    ]
  | TDRecord fields ->
    Dump.json_obj [
      ("kind", Dump.json_string "TDRecord");
      ("fields", Dump.json_list (List.map field_to_json fields));
    ]

and variant_to_json (v : variant) : string =
  Dump.json_obj [
    ("name", name_to_json v.var_name);
    ("args", Dump.json_list (List.map ty_to_json v.var_args));
    ("vis", visibility_to_json v.var_vis);
  ]

and field_to_json (f : field) : string =
  Dump.json_obj [
    ("name", name_to_json f.fld_name);
    ("ty", ty_to_json f.fld_ty);
    ("lin", linearity_to_json f.fld_lin);
  ]

and restart_strategy_to_json (rs : restart_strategy) : string =
  match rs with
  | OneForOne -> Dump.json_obj [ ("kind", Dump.json_string "OneForOne") ]
  | OneForAll -> Dump.json_obj [ ("kind", Dump.json_string "OneForAll") ]
  | RestForOne -> Dump.json_obj [ ("kind", Dump.json_string "RestForOne") ]

and supervise_field_to_json (sf : supervise_field) : string =
  Dump.json_obj [
    ("name", name_to_json sf.sf_name);
    ("ty", ty_to_json sf.sf_ty);
  ]

and supervise_config_to_json (sc : supervise_config) : string =
  Dump.json_obj [
    ("fields", Dump.json_list (List.map supervise_field_to_json sc.sc_fields));
    ("strategy", restart_strategy_to_json sc.sc_strategy);
    ("max_restarts", json_int sc.sc_max_restarts);
    ("window_secs", json_int sc.sc_window_secs);
    ("order", Dump.json_list (List.map name_to_json sc.sc_order));
  ]

and actor_def_to_json (ad : actor_def) : string =
  Dump.json_obj [
    ("state", Dump.json_list (List.map field_to_json ad.actor_state));
    ("init", expr_to_json ad.actor_init);
    ("handlers", Dump.json_list (List.map actor_handler_to_json ad.actor_handlers));
    ("supervise", json_opt supervise_config_to_json ad.actor_supervise);
    ("compat", Dump.json_string ad.actor_compat);
    ("invariant", json_opt expr_to_json ad.actor_invariant);
  ]

and actor_handler_to_json (ah : actor_handler) : string =
  Dump.json_obj [
    ("msg", name_to_json ah.ah_msg);
    ("params", Dump.json_list (List.map param_to_json ah.ah_params));
    ("body", expr_to_json ah.ah_body);
  ]

and protocol_def_to_json (pd : protocol_def) : string =
  Dump.json_obj [
    ("steps", Dump.json_list (List.map protocol_step_to_json pd.proto_steps));
  ]

and protocol_step_to_json (ps : protocol_step) : string =
  match ps with
  | ProtoMsg (from_, to_, ty) ->
    Dump.json_obj [
      ("kind", Dump.json_string "ProtoMsg");
      ("from", name_to_json from_);
      ("to", name_to_json to_);
      ("msg_ty", ty_to_json ty);
    ]
  | ProtoLoop steps ->
    Dump.json_obj [
      ("kind", Dump.json_string "ProtoLoop");
      ("steps", Dump.json_list (List.map protocol_step_to_json steps));
    ]
  | ProtoStop _ ->
    Dump.json_obj [
      ("kind", Dump.json_string "ProtoStop");
    ]
  | ProtoChoice (role, branches) ->
    Dump.json_obj [
      ("kind", Dump.json_string "ProtoChoice");
      ("role", name_to_json role);
      ("branches", Dump.json_list (List.map (fun (label, steps) ->
           Dump.json_obj [
             ("label", name_to_json label);
             ("steps", Dump.json_list (List.map protocol_step_to_json steps));
           ]) branches));
    ]

and interface_def_to_json (id : interface_def) : string =
  Dump.json_obj [
    ("name", name_to_json id.iface_name);
    ("param", name_to_json id.iface_param);
    ("superclasses", Dump.json_list (List.map (fun (n, args) ->
         Dump.json_obj [
           ("name", name_to_json n);
           ("args", Dump.json_list (List.map ty_to_json args));
         ]) id.iface_superclasses));
    ("assoc_types", Dump.json_list (List.map assoc_type_decl_to_json id.iface_assoc_types));
    ("methods", Dump.json_list (List.map method_decl_to_json id.iface_methods));
  ]

and assoc_type_decl_to_json (at : assoc_type_decl) : string =
  Dump.json_obj [
    ("name", name_to_json at.at_name);
    ("constraints", Dump.json_list (List.map ty_to_json at.at_constraints));
  ]

and method_decl_to_json (md : method_decl) : string =
  Dump.json_obj [
    ("name", name_to_json md.md_name);
    ("ty", ty_to_json md.md_ty);
    ("default", json_opt expr_to_json md.md_default);
  ]

and impl_def_to_json (impl : impl_def) : string =
  Dump.json_obj [
    ("iface", name_to_json impl.impl_iface);
    ("ty", ty_to_json impl.impl_ty);
    ("constraints", Dump.json_list (List.map (fun (n, args) ->
         Dump.json_obj [
           ("name", name_to_json n);
           ("args", Dump.json_list (List.map ty_to_json args));
         ]) impl.impl_constraints));
    ("assoc_types", Dump.json_list (List.map (fun (n, t) ->
         Dump.json_obj [ ("name", name_to_json n); ("ty", ty_to_json t) ])
         impl.impl_assoc_types));
    ("methods", Dump.json_list (List.map (fun (n, fd) ->
         Dump.json_obj [ ("name", name_to_json n); ("fn", fn_def_to_json fd) ])
         impl.impl_methods));
  ]

and sig_def_to_json (sd : sig_def) : string =
  Dump.json_obj [
    ("types", Dump.json_list (List.map (fun (n, params) ->
         Dump.json_obj [
           ("name", name_to_json n);
           ("params", Dump.json_list (List.map name_to_json params));
         ]) sd.sig_types));
    ("fns", Dump.json_list (List.map (fun (n, t) ->
         Dump.json_obj [ ("name", name_to_json n); ("ty", ty_to_json t) ])
         sd.sig_fns));
  ]

and extern_def_to_json (ed : extern_def) : string =
  Dump.json_obj [
    ("lib_name", Dump.json_string ed.ext_lib_name);
    ("cap_ty", ty_to_json ed.ext_cap_ty);
    ("fns", Dump.json_list (List.map extern_fn_to_json ed.ext_fns));
  ]

and extern_fn_to_json (ef : extern_fn) : string =
  Dump.json_obj [
    ("name", name_to_json ef.ef_name);
    ("params", Dump.json_list (List.map (fun (n, t) ->
         Dump.json_obj [ ("name", name_to_json n); ("ty", ty_to_json t) ])
         ef.ef_params));
    ("param_consumed", Dump.json_list (List.map json_bool ef.ef_param_consumed));
    ("blocking", json_bool ef.ef_blocking);
    ("raises", json_bool ef.ef_raises);
    ("ret_ty", ty_to_json ef.ef_ret_ty);
    ("symbol", json_opt Dump.json_string ef.ef_symbol);
  ]

(* ------------------------------------------------------------------ *)
(* module_                                                             *)
(* ------------------------------------------------------------------ *)

let module_to_json ~(types : (span, T.ty) Hashtbl.t) (m : module_) : string =
  current_types := Some types;
  Dump.json_obj [
    ("name", name_to_json m.mod_name);
    ("decls", Dump.json_list (List.map decl_to_json m.mod_decls));
  ]
