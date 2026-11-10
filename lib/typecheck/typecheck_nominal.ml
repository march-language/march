(** Nominal identity for variant types whose short name is declared at two or
    more module paths of the checked program.

    March has a single global type namespace: a type declared inside a module
    has its BARE name as its identity, so [A.Note] and [B.Note] used to be one
    [TCon "Note"] and unified with each other (a value of one was accepted
    where the other was expected; a [match] over one listed the other's
    constructors; [from_json] could not tell their codecs apart).  See
    specs/todos/2026-11-02-typecheck-conflates-same-short-named-types.md and
    the design section of
    specs/progress/2026-10-03-derive-json-same-short-name-two-modules.md.

    This module gives each such type its own identity: [path ^ "." ^ short]
    (the bare [short] at the entry module's own top level), where [path] is
    the dotted path of nested modules from the entry module ([A], [A.Inner]).
    Only colliding VARIANT types change: a short name declared once has no
    entry here, so a program without a collision typechecks exactly as
    before.  Records unify structurally and keep their bare name.  Stdlib
    declarations are not counted (they reach a check through the cached
    stdlib env, whose signatures are bare).

    Resolution is done ONCE, up front, over the whole AST, by the lexical rule
    a reference follows: a bare [Note] means the innermost enclosing module
    that declares a type [Note]; a qualified [A.Note] means module [A] as seen
    from the innermost enclosing module that has it (the entry module's own
    name is accepted as a prefix too).  The answer is recorded against the
    reference's span, so every consumer that turns a written type into a
    [TCon] ([surface_ty], the env-less prebind of fn signatures, impl heads)
    reads the same identity without knowing the scope it is in.  A
    constructor's argument types are spans inside its declaration, so they
    mean what the declaration meant from every use site.

    The backends never see an identity: [bare] maps it back to the short name
    ([Lower_types.convert_ty]), so TIR, mangling and the CAS see the program
    exactly as before.  The one exception is [from_json]'s result-type
    dispatch ([Json_dispatch]), which both backends already resolve by the
    module-qualified name. *)

module A = March_ast.Ast

(* Span-keyed tables.  [Ast.span] is plain data, so structural hashing is the
   identity we want.  [refs] holds both written references (a [TyCon]'s name
   span) and declarations (a [DType]'s name span). *)
let refs : (A.span, string) Hashtbl.t = Hashtbl.create 16

(** identity -> arity, for the current check only. *)
let arity_tbl : (string, int) Hashtbl.t = Hashtbl.create 16

(** identity -> short name.  Additive across checks: TIR reads it after the
    check that produced the identity (and the LSP / REPL re-check in one
    process), and an identity always maps to the same short name. *)
let short_tbl : (string, string) Hashtbl.t = Hashtbl.create 16

let reset () =
  Hashtbl.reset refs;
  Hashtbl.reset arity_tbl

let is_identity (s : string) : bool = Hashtbl.mem arity_tbl s

let arity_of (s : string) : int option = Hashtbl.find_opt arity_tbl s

(** The backends' (bare) name for a type-constructor name. *)
let bare (s : string) : string =
  match Hashtbl.find_opt short_tbl s with Some b -> b | None -> s

(** The identity the type name written at [n] resolved to, if it names a
    colliding variant type. *)
let ref_identity (n : A.name) : string option =
  if Hashtbl.length refs = 0 then None
  else Hashtbl.find_opt refs n.A.span

(** The identity of a type declared with name [n]: its qualified identity
    when it collides, else its own name.  Use at every [ci_type] site. *)
let decl_identity (n : A.name) : string =
  match ref_identity n with Some id -> id | None -> n.A.txt

(** Bare names of builtin types that have no declaration anywhere: the
    handle types of ocap phase 2 (spec §6; the dotted [File.Handle] and
    [File.Dir] cannot be declared under their own spelling).  A user variant
    declared with one of these short names always gets a qualified identity,
    even when it is the only declaration, and even at the entry module's top
    level: if it kept the bare name it WOULD be the builtin, and a user module
    could forge a handle by unifying its own type with the box.  [is_reserved]
    is also what the lowering reads to send the builtin, and only the builtin,
    to the reserved TIR handle type. *)
let reserved_builtin_names = [ "Socket"; "Listener"; "Process" ]

let is_reserved (short : string) : bool = List.mem short reserved_builtin_names

let short_of q =
  match String.rindex_opt q '.' with
  | Some i -> String.sub q (i + 1) (String.length q - i - 1)
  | None -> q

let join p s = if p = "" then s else p ^ "." ^ s

(** Walk [m] and fill the tables.  [is_stdlib] tells a stdlib declaration
    (not counted).  Called at the start of every whole-module check. *)
let compute ~(is_stdlib : A.span -> bool) (m : A.module_) : unit =
  reset ();
  (* Pass 1: every type declaration, per path. *)
  let decls_at : (string * string, [ `Variant of A.name * int | `Other ]) Hashtbl.t =
    Hashtbl.create 64 in
  let variant_paths : (string, string list) Hashtbl.t = Hashtbl.create 64 in
  (* A reserved builtin name counts even in a stdlib-owned file: the stdlib
     declares none, so the only such file is an entry checked with
     `--stdlib-source`, which must not own the handle type either. *)
  let user_decl (n : A.name) =
    n.A.span <> A.dummy_span && (not (is_stdlib n.A.span) || is_reserved n.A.txt) in
  let rec collect path (ds : A.decl list) =
    List.iter (function
        | A.DType (_, n, ps, A.TDVariant _, _)
        | A.DAlwaysLinearType (_, n, ps, A.TDVariant _, _) when user_decl n ->
          if not (Hashtbl.mem decls_at (path, n.A.txt)) then begin
            Hashtbl.replace decls_at (path, n.A.txt) (`Variant (n, List.length ps));
            let prev = Option.value ~default:[] (Hashtbl.find_opt variant_paths n.A.txt) in
            Hashtbl.replace variant_paths n.A.txt (path :: prev)
          end
        | A.DType (_, n, _, _, _) | A.DAlwaysLinearType (_, n, _, _, _) ->
          if not (Hashtbl.mem decls_at (path, n.A.txt)) then
            Hashtbl.replace decls_at (path, n.A.txt) `Other
        | A.DMod (n, _, inner, _) -> collect (join path n.A.txt) inner
        | A.DDescribe (_, inner, _) -> collect path inner
        | _ -> ()) ds
  in
  collect "" m.A.mod_decls;
  let colliding = Hashtbl.create 16 in
  Hashtbl.iter (fun short paths ->
      if List.length paths >= 2 || is_reserved short then
        Hashtbl.replace colliding short ()) variant_paths;
  if Hashtbl.length colliding = 0 then ()
  else begin
    let entry = m.A.mod_name.A.txt in
    (* The identity of [short] declared at [path].  A reserved name is
       qualified by the entry module too, so it is never the bare builtin. *)
    let ident path short =
      if is_reserved short then join (join entry path) short else join path short in
    (* Declarations get their identity. *)
    Hashtbl.iter (fun (path, short) d ->
        match d with
        | `Variant (n, arity) when Hashtbl.mem colliding short ->
          let id = ident path short in
          Hashtbl.replace refs n.A.span id;
          Hashtbl.replace arity_tbl id arity;
          Hashtbl.replace short_tbl id short
        | _ -> ()) decls_at;
    let identity_at path short =
      match Hashtbl.find_opt decls_at (path, short) with
      | Some (`Variant _) -> Some (ident path short)
      | Some `Other -> None
      | None -> raise Not_found
    in
    (* [scopes]: enclosing paths, innermost first, ending with "". *)
    let resolve scopes (txt : string) : string option =
      let short = short_of txt in
      if not (Hashtbl.mem colliding short) then None
      else if not (String.contains txt '.') then
        (* A bare name: the innermost enclosing module that declares a type
           of that name (a record or alias there shadows: no identity). *)
        let rec go = function
          | [] -> None
          | p :: rest -> (try identity_at p short with Not_found -> go rest)
        in
        go scopes
      else
        let prefix = String.sub txt 0 (String.length txt - String.length short - 1) in
        let prefixes =
          if prefix = entry then [ "" ]
          else
            let el = String.length entry in
            if String.length prefix > el + 1
               && String.sub prefix 0 (el + 1) = entry ^ "."
            then [ prefix; String.sub prefix (el + 1) (String.length prefix - el - 1) ]
            else [ prefix ]
        in
        let rec go = function
          | [] -> None
          | p :: rest ->
            let found =
              List.find_map (fun pre ->
                  let cand = if pre = "" then "" else join p pre in
                  match Hashtbl.find_opt decls_at (cand, short) with
                  | Some (`Variant _) -> Some (ident cand short)
                  | _ -> None) prefixes
            in
            (match found with Some _ -> found | None -> go rest)
        in
        go scopes
    in
    let record scopes (n : A.name) =
      if n.A.span <> A.dummy_span then
        match resolve scopes n.A.txt with
        | Some id ->
          (match Hashtbl.find_opt refs n.A.span with
           | Some id' when id' <> id -> ()   (* a span claimed twice: keep the first *)
           | _ -> Hashtbl.replace refs n.A.span id)
        | None -> ()
    in
    (* Pass 2: every written type, with its lexical scope. *)
    let rec ty sc (t : A.ty) =
      match t with
      | A.TyCon (n, args) -> record sc n; List.iter (ty sc) args
      | A.TyVar _ | A.TyNat _ | A.TyChan _ -> ()
      | A.TyArrow (a, b) | A.TyNatOp (_, a, b) -> ty sc a; ty sc b
      | A.TyTuple ts -> List.iter (ty sc) ts
      | A.TyRecord fs -> List.iter (fun (_, t) -> ty sc t) fs
      | A.TyLinear (_, t) -> ty sc t
      | A.TyRefine (t, _, e) -> ty sc t; expr sc e
    and tyo sc = function Some t -> ty sc t | None -> ()
    and param sc (p : A.param) = tyo sc p.A.param_ty
    and expr sc (e : A.expr) =
      let ex = expr sc in
      match e with
      | A.ELit _ | A.EVar _ | A.EHole _ | A.EResultRef _ -> ()
      | A.EApp (f, xs, _) -> ex f; List.iter ex xs
      | A.ECon (_, xs, _) | A.ETuple (xs, _) | A.EBlock (xs, _) | A.EAtom (_, xs, _) ->
        List.iter ex xs
      | A.ELam (ps, b, _) -> List.iter (param sc) ps; ex b
      | A.ELet (b, _) -> tyo sc b.A.bind_ty; ex b.A.bind_expr
      | A.EMatch (s, brs, _) ->
        ex s;
        List.iter (fun (br : A.branch) ->
            Option.iter ex br.A.branch_guard; ex br.A.branch_body) brs
      | A.ERecord (fs, _) -> List.iter (fun (_, e) -> ex e) fs
      | A.ERecordUpdate (r, fs, _) -> ex r; List.iter (fun (_, e) -> ex e) fs
      | A.EField (e, _, _) -> ex e
      | A.EIf (a, b, c, _) -> ex a; ex b; ex c
      | A.ECond (arms, _) -> List.iter (fun (a, b) -> ex a; ex b) arms
      | A.EPipe (a, b, _) | A.ESend (a, b, _) -> ex a; ex b
      | A.EAnnot (e, t, _) -> ex e; ty sc t
      | A.ESpawn (e, _) | A.EAssert (e, _) | A.ESigil (_, e, _)
      | A.ERefineMsg (e, _, _) -> ex e
      | A.EDbg (eo, _) -> Option.iter ex eo
      | A.ELetFn (_, ps, rt, b, _) -> List.iter (param sc) ps; tyo sc rt; ex b
      | A.ELetQ (_, a, b, _) | A.ELetStar (_, a, b, _) -> ex a; ex b
      | A.EProof (p, _) ->
        (match p with
         | A.PAssertBy (e, hs) -> ex e; List.iter ex hs
         | A.PReveal e -> ex e
         | A.PWithFuel (e, _, b) -> ex e; List.iter ex b
         | A.PCalc (e, steps) ->
           ex e;
           List.iter (fun (s : A.calc_step) ->
               ex s.A.cs_rhs; List.iter ex s.A.cs_hint) steps)
    and fn_def sc (d : A.fn_def) =
      tyo sc d.A.fn_ret_ty;
      List.iter (fun (_, t) -> ty sc t) d.A.fn_bounds;
      List.iter (fun (_, es) -> List.iter (expr sc) es) d.A.fn_attr_args;
      List.iter (fun (c : A.fn_clause) ->
          List.iter (function
              | A.FPPat _ -> ()
              | A.FPNamed p -> param sc p
              | A.FPDefault (p, e) -> param sc p; expr sc e) c.A.fc_params;
          Option.iter (expr sc) c.A.fc_guard;
          expr sc c.A.fc_body) d.A.fn_clauses
    and handler sc (h : A.actor_handler) =
      List.iter (param sc) h.A.ah_params; expr sc h.A.ah_body
    and proto_step sc = function
      | A.ProtoMsg (_, _, t, _) -> ty sc t
      | A.ProtoLoop (steps, _) -> List.iter (proto_step sc) steps
      | A.ProtoChoice (_, arms) -> List.iter (fun (_, s) -> List.iter (proto_step sc) s) arms
      | A.ProtoCrashOr (s, ss, _) -> proto_step sc s; List.iter (proto_step sc) ss
      | A.ProtoStop _ | A.ProtoMayCrash _ | A.ProtoRoleNeeds _ -> ()
    and decl path sc (d : A.decl) =
      match d with
      | A.DFn (f, _) -> fn_def sc f
      | A.DLet (_, b, _) -> tyo sc b.A.bind_ty; expr sc b.A.bind_expr
      | A.DType (_, _, _, td, _) | A.DAlwaysLinearType (_, _, _, td, _) ->
        (match td with
         | A.TDAlias (t, ps) -> ty sc t; List.iter (fun (_, t) -> ty sc t) ps
         | A.TDVariant vs -> List.iter (fun (v : A.variant) -> List.iter (ty sc) v.A.var_args) vs
         | A.TDRecord fs -> List.iter (fun (f : A.field) -> ty sc f.A.fld_ty) fs)
      | A.DActor (_, _, a, _) ->
        List.iter (fun (f : A.field) -> ty sc f.A.fld_ty) a.A.actor_state;
        List.iter (param sc) a.A.actor_init_params;
        expr sc a.A.actor_init;
        List.iter (handler sc) a.A.actor_handlers;
        Option.iter (handler sc) a.A.actor_on_stop;
        Option.iter (expr sc) a.A.actor_invariant;
        Option.iter (fun (c : A.supervise_config) ->
            List.iter (fun (f : A.supervise_field) ->
                ty sc f.A.sf_ty; List.iter (expr sc) f.A.sf_init_args) c.A.sc_fields)
          a.A.actor_supervise
      | A.DProtocol (_, p, _) -> List.iter (proto_step sc) p.A.proto_steps
      | A.DMod (n, _, inner, _) ->
        let p = join path n.A.txt in
        List.iter (decl p (p :: sc)) inner
      | A.DDescribe (_, inner, _) -> List.iter (decl path sc) inner
      | A.DSig (_, s, _) -> List.iter (fun (_, t) -> ty sc t) s.A.sig_fns
      | A.DInterface (i, _) ->
        List.iter (fun (_, ts) -> List.iter (ty sc) ts) i.A.iface_superclasses;
        List.iter (fun (a : A.assoc_type_decl) -> List.iter (ty sc) a.A.at_constraints)
          i.A.iface_assoc_types;
        List.iter (fun (md : A.method_decl) ->
            ty sc md.A.md_ty; Option.iter (expr sc) md.A.md_default) i.A.iface_methods;
        List.iter (fn_def sc) i.A.iface_laws
      | A.DImpl (i, _) ->
        ty sc i.A.impl_ty;
        List.iter (fun (_, ts) -> List.iter (ty sc) ts) i.A.impl_constraints;
        List.iter (fun (_, t) -> ty sc t) i.A.impl_assoc_types;
        List.iter (fun (_, f) -> fn_def sc f) i.A.impl_methods
      | A.DExtern (e, _) ->
        ty sc e.A.ext_cap_ty;
        List.iter (fun (f : A.extern_fn) ->
            List.iter (fun (_, t) -> ty sc t) f.A.ef_params; ty sc f.A.ef_ret_ty) e.A.ext_fns
      | A.DApp (a, _) ->
        expr sc a.A.app_body;
        Option.iter (expr sc) a.A.app_on_start;
        Option.iter (expr sc) a.A.app_on_stop
      | A.DTest (t, _) -> expr sc t.A.test_body
      | A.DSetup (e, _) | A.DSetupAll (e, _) -> expr sc e
      | A.DUse _ | A.DAlias _ | A.DNeeds _ | A.DProofCap _ | A.DOpts _
      | A.DTransitions _ | A.DDeriving _ | A.DSatisfy _ -> ()
    in
    List.iter (decl "" [ "" ]) m.A.mod_decls
  end
