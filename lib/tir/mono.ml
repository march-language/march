(** Monomorphization pass for the March TIR.

    Specializes all polymorphic function definitions to their concrete
    call-site types, eliminating all [Tir.TVar] placeholders.

    Algorithm:
    1. Build a table of all fn_defs by name.
    2. Seed the worklist with all root functions (no TVar in params).
    3. For each dequeued (fn_def, subst): apply subst, walk body for
       EApp calls to functions whose type has TVar, derive a new
       substitution from arg types, clone + rename callee, enqueue.
    4. Output: only the reachable monomorphic fn_defs. *)

(* ── Interface dispatch helpers ─────────────────────────────────── *)

(** Resolve an interface method implementation for [type_name] from [impls].
    Strips module prefixes progressively ("Foo.Bar.VaultStorage" → "VaultStorage")
    to handle qualified type names registered under bare names.
    The sentinel ["$single_impl$"] selects the sole impl when the call-site
    type is erased (TVar "_" or opaque placeholder). *)
let resolve_impl_by_type (impls : (string * string) list) (type_name : string) : string option =
  if type_name = "$single_impl$" then
    (match impls with [(_, m)] -> Some m | _ -> None)
  else
    let rec loop name =
      match List.assoc_opt name impls with
      | Some m -> Some m
      | None ->
        (match String.index_opt name '.' with
         | None -> None
         | Some i -> loop (String.sub name (i + 1) (String.length name - i - 1)))
    in
    loop type_name

(* ── Type detection ─────────────────────────────────────────────── *)

let rec has_tvar : Tir.ty -> bool = function
  | Tir.TVar "_"      -> false  (* lowering fallback placeholder, not a real polymorph *)
  | Tir.TVar _        -> true
  | Tir.TTuple ts     -> List.exists has_tvar ts
  | Tir.TRecord fs    -> List.exists (fun (_, t) -> has_tvar t) fs
  | Tir.TCon (_, args)-> List.exists has_tvar args
  | Tir.TFn (ps, ret) -> List.exists has_tvar ps || has_tvar ret
  | Tir.TPtr t        -> has_tvar t
  | _                 -> false   (* TInt, TFloat, TBool, TString, TUnit *)

(* ── Type substitution ──────────────────────────────────────────── *)

type ty_subst = (string * Tir.ty) list

let rec subst_ty (s : ty_subst) : Tir.ty -> Tir.ty = function
  | Tir.TVar name      ->
    (match List.assoc_opt name s with Some t -> t | None -> Tir.TVar name)
  | Tir.TTuple ts      -> Tir.TTuple (List.map (subst_ty s) ts)
  | Tir.TRecord fs     -> Tir.TRecord (List.map (fun (n, t) -> (n, subst_ty s t)) fs)
  | Tir.TCon (n, args) -> Tir.TCon (n, List.map (subst_ty s) args)
  | Tir.TFn (ps, ret)  -> Tir.TFn (List.map (subst_ty s) ps, subst_ty s ret)
  | Tir.TPtr t         -> Tir.TPtr (subst_ty s t)
  | t                  -> t

let subst_var (s : ty_subst) (v : Tir.var) : Tir.var =
  { v with Tir.v_ty = subst_ty s v.Tir.v_ty }

let subst_atom (s : ty_subst) : Tir.atom -> Tir.atom = function
  | Tir.AVar v    -> Tir.AVar (subst_var s v)
  | Tir.ADefRef _ as a -> a  (* global ref — no type vars to substitute *)
  | a             -> a

let rec subst_expr (s : ty_subst) : Tir.expr -> Tir.expr = function
  | Tir.EAtom a           -> Tir.EAtom (subst_atom s a)
  | Tir.EApp (f, args)    -> Tir.EApp (subst_var s f, List.map (subst_atom s) args)
  | Tir.ECallPtr (f, args)-> Tir.ECallPtr (subst_atom s f, List.map (subst_atom s) args)
  | Tir.ELet (v, e1, e2)  -> Tir.ELet (subst_var s v, subst_expr s e1, subst_expr s e2)
  | Tir.ELetRec (fns, body)->
    Tir.ELetRec (List.map (subst_fn_def s) fns, subst_expr s body)
  | Tir.ECase (a, brs, def) ->
    Tir.ECase (subst_atom s a, List.map (subst_branch s) brs,
               Option.map (subst_expr s) def)
  | Tir.ETuple atoms      -> Tir.ETuple (List.map (subst_atom s) atoms)
  | Tir.ERecord fs        -> Tir.ERecord (List.map (fun (n, a) -> (n, subst_atom s a)) fs)
  | Tir.EField (a, n)     -> Tir.EField (subst_atom s a, n)
  | Tir.EUpdate (a, fs)   ->
    Tir.EUpdate (subst_atom s a, List.map (fun (n, a) -> (n, subst_atom s a)) fs)
  | Tir.EAlloc (ty, args)      -> Tir.EAlloc (subst_ty s ty, List.map (subst_atom s) args)
  | Tir.EStackAlloc (ty, args) -> Tir.EStackAlloc (subst_ty s ty, List.map (subst_atom s) args)
  | Tir.EFree a           -> Tir.EFree (subst_atom s a)
  | Tir.EIncRC a          -> Tir.EIncRC (subst_atom s a)
  | Tir.EDecRC a          -> Tir.EDecRC (subst_atom s a)
  | Tir.EAtomicIncRC a    -> Tir.EAtomicIncRC (subst_atom s a)
  | Tir.EAtomicDecRC a    -> Tir.EAtomicDecRC (subst_atom s a)
  | Tir.EReuse (a, ty, args) ->
    Tir.EReuse (subst_atom s a, subst_ty s ty, List.map (subst_atom s) args)
  | Tir.ESeq (e1, e2)     -> Tir.ESeq (subst_expr s e1, subst_expr s e2)

and subst_branch (s : ty_subst) (br : Tir.branch) : Tir.branch =
  { br with Tir.br_vars = List.map (subst_var s) br.Tir.br_vars;
            Tir.br_body = subst_expr s br.Tir.br_body }

and subst_fn_def (s : ty_subst) (fn : Tir.fn_def) : Tir.fn_def =
  { fn with Tir.fn_params = List.map (subst_var s) fn.Tir.fn_params;
            Tir.fn_ret_ty = subst_ty s fn.Tir.fn_ret_ty;
            Tir.fn_body   = subst_expr s fn.Tir.fn_body }

(* ── Name mangling ──────────────────────────────────────────────── *)

(** Produce a stable, readable string for a monomorphic type.
    Used to construct specialized function names like [map$Int$Bool]. *)
let rec mangle_ty : Tir.ty -> string = function
  | Tir.TInt          -> "Int"
  | Tir.TFloat        -> "Float"
  | Tir.TBool         -> "Bool"
  | Tir.TString       -> "String"
  | Tir.TUnit         -> "Unit"
  | Tir.TTuple ts     -> "T_" ^ String.concat "_" (List.map mangle_ty ts)
  | Tir.TRecord fs    ->
    "R_" ^ String.concat "_" (List.map (fun (n, t) -> n ^ "_" ^ mangle_ty t) fs)
  | Tir.TCon (n, [])  -> n
  | Tir.TCon (n, args)-> n ^ "_" ^ String.concat "_" (List.map mangle_ty args)
  | Tir.TFn (ps, ret) ->
    "Fn_" ^ String.concat "_" (List.map mangle_ty ps) ^ "_" ^ mangle_ty ret
  | Tir.TPtr t        -> "Ptr_" ^ mangle_ty t
  | Tir.TVar name     -> "V_" ^ name

(** [mangle_name base tys] appends a "$"-separated mangled suffix to [base].
    Returns [base] unchanged if [tys] is empty (already monomorphic).
    The "$"-glue itself is [Tir_names.specialize_mangle] (Wave 3 Chunk 2
    Task 1) — [mangle_ty] (mono-specific type-to-string) stays here. *)
let mangle_name (base : string) (tys : Tir.ty list) : string =
  match tys with
  | [] -> base
  | _  -> Tir_names.specialize_mangle base (String.concat "$" (List.map mangle_ty tys))

(* ── Derived Show synthesis (structural renderer) ───────────────── *)

(** Type definitions of the module being monomorphized — set by
    [monomorphize] at entry (single-threaded module-global, the same
    pattern as lower's [_fn_param_types]).  [synth_derived_show] uses it
    to look up ADT constructor lists. *)
let _mono_type_defs : Tir.type_def list ref = ref []

(** Synthesize a STRUCTURAL renderer for [ty] and enqueue it for emission,
    returning its function name — or [None] when [ty] has no renderable
    structure (TVar, unknown TCon).

    This is the compiled analogue of the interpreter's [value_to_string]
    FALLBACK (eval.ml): the renderer used when `show(x)` reaches a type
    with no user/prelude Show impl — tuples, records, and plain ADTs.
    Before this, such calls survived mono as bare `show` and died at link
    ("Undefined symbols: _show") for println((1,2)) / println(Circle(1.5)).

    Output contract — must match [value_to_string] byte-for-byte, because
    the differential oracle compares stdout:
      Int/Float/Bool  → the plain to_string builtins (already parity-pinned)
      String          → QUOTED: "\"" ++ s ++ "\"" (the interpreter fallback
                        quotes nested strings, unlike Show$String's identity;
                        NOTE String.escaped is NOT mirrored — a string field
                        containing quotes/backslashes/control chars will
                        diverge; filed corner in specs/todos.md)
      Unit            → "()"
      closures (TFn)  → "<fn>"
      tuple           → "(" e0 ", " e1 … ")"
      record          → "{ k: v, … }" (declaration field order)
      List            → "[]" / "[" e0 ", " e1 … "]" (structural — element
                        strings QUOTED, matching the interp fallback, which
                        deliberately differs from prelude Show$List's
                        unquoted elements)
      other ADT       → "Ctor" / "Ctor(" f0 ", " f1 … ")"
      anything else   → the generic runtime `to_string` builtin
                        (march_value_to_string), a graceful degrade
    Recursion through fields goes through this same synthesizer (memoized
    via [fn_table]; a placeholder is registered before the body is built so
    recursive ADTs — trees — terminate). *)
let rec synth_derived_show fn_table done_set
    (worklist : (string * Tir.fn_def * ty_subst) Queue.t)
    (ty : Tir.ty) : string option =
  let str_t = Tir.TString in
  let fname = "show$derived$" ^ mangle_ty ty in
  if Hashtbl.mem fn_table fname then Some fname
  else begin
    let param = { Tir.v_name = "x"; v_ty = ty; v_lin = Tir.Unr } in
    (* Placeholder first: a recursive field type (Tree in Tree) memo-hits
       this entry and uses the name; the real body replaces it below. *)
    let placeholder = { Tir.fn_name = fname; fn_params = [param];
                        fn_ret_ty = str_t; fn_body = Tir.EAtom (Tir.ALit (March_ast.Ast.LitString ""));
                        fn_kind = Tir.FnNormal } in
    Hashtbl.replace fn_table fname placeholder;
    let ctr = ref 0 in
    let fresh p = incr ctr; Printf.sprintf "$ds%s%d" p !ctr in
    let mkv n t = { Tir.v_name = n; Tir.v_ty = t; Tir.v_lin = Tir.Unr } in
    let slit s = Tir.ALit (March_ast.Ast.LitString s) in
    let fn_var n ps r = mkv n (Tir.TFn (ps, r)) in
    let app1 n pty a = Tir.EApp (fn_var n [pty] str_t, [a]) in
    (* ANF: bind each String-typed part to a var, fold left with ++ *)
    let concat_all (parts : Tir.expr list) : Tir.expr =
      match parts with
      | [] -> Tir.EAtom (slit "")
      | [e] -> e
      | first :: rest ->
        let rec go acc_var = function
          | [] -> Tir.EAtom (Tir.AVar acc_var)
          | e :: tl ->
            let ev = mkv (fresh "p") str_t in
            let cv = mkv (fresh "c") str_t in
            Tir.ELet (ev, e,
              Tir.ELet (cv,
                Tir.EApp (fn_var "++" [str_t; str_t] str_t,
                          [Tir.AVar acc_var; Tir.AVar ev]),
                go cv tl))
        in
        let fv = mkv (fresh "p") str_t in
        Tir.ELet (fv, first, go fv rest)
    in
    let render_field (a : Tir.atom) (fty : Tir.ty) : Tir.expr =
      (* Constructor/tuple fields extracted by the boxed decode live in
         generic ptr slots holding TAGGED scalars, and the builtin call
         emission passes the slot's natural type verbatim (an ELet rebind
         copies without coercing, too).  The one guaranteed coercion point
         is the OPERATOR path — arithmetic emission conditionally untags
         ptr-slot args (the same reason `<(x, y)` on list elements works) —
         so scalars are normalized via `+ 0` / `+. 0.0` (Bool via a case)
         before the to_string builtin sees them. *)
      match fty with
      | Tir.TInt ->
        let cv = mkv (fresh "v") Tir.TInt in
        Tir.ELet (cv,
          Tir.EApp (fn_var "+" [Tir.TInt; Tir.TInt] Tir.TInt,
                    [a; Tir.ALit (March_ast.Ast.LitInt 0)]),
          app1 "int_to_string" Tir.TInt (Tir.AVar cv))
      | Tir.TFloat ->
        let cv = mkv (fresh "v") Tir.TFloat in
        Tir.ELet (cv,
          Tir.EApp (fn_var "+." [Tir.TFloat; Tir.TFloat] Tir.TFloat,
                    [a; Tir.ALit (March_ast.Ast.LitFloat 0.0)]),
          app1 "float_to_string" Tir.TFloat (Tir.AVar cv))
      | Tir.TBool ->
        Tir.ECase (a,
          [{ Tir.br_tag = Tir_names.bool_lit_tag true; br_vars = [];
             br_body = Tir.EAtom (slit "true") }],
          Some (Tir.EAtom (slit "false")))
      | Tir.TUnit   -> Tir.EAtom (slit "()")
      | Tir.TString ->
        concat_all [Tir.EAtom (slit "\""); Tir.EAtom a; Tir.EAtom (slit "\"")]
      | Tir.TFn _   -> Tir.EAtom (slit "<fn>")
      | Tir.TCon ("Atom", []) -> app1 "atom_to_string" (Tir.TCon ("Atom", [])) a
      | (Tir.TTuple _ | Tir.TRecord _ | Tir.TCon _) as t ->
        (match synth_derived_show fn_table done_set worklist t with
         | Some n -> Tir.EApp (fn_var n [t] str_t, [a])
         | None   -> app1 "to_string" t a)
      | t -> app1 "to_string" t a
    in
    let comma_sep (rendered : Tir.expr list) : Tir.expr list =
      List.concat (List.mapi (fun i r ->
          if i = 0 then [r] else [Tir.EAtom (slit ", "); r]) rendered)
    in
    (* Branch fields must go through lower's exact rebinding shape:
       UNTYPED ([TVar "_"]) branch vars, each immediately re-bound with a
       TYPED let (`let f : Int = $dsf`).  The ELet copy is where the
       ptr-slot→typed-slot coercion (conditional untag / float bitcast)
       happens — and it only fires on a TYPE CHANGE, so concretely-typed
       branch vars would copy the TAGGED bits verbatim (ints printed as
       2n+1).  [bind_fields tys k] returns (raw_br_vars, body) where [k]
       receives the typed copies. *)
    let bind_fields (tys : Tir.ty list) (k : Tir.var list -> Tir.expr)
      : Tir.var list * Tir.expr =
      let raws  = List.map (fun _ -> mkv (fresh "f") (Tir.TVar "_")) tys in
      let typed = List.map (fun t -> mkv (fresh "b") t) tys in
      let body =
        List.fold_right2 (fun (r : Tir.var) (t : Tir.var) acc ->
            Tir.ELet (t, Tir.EAtom (Tir.AVar r), acc))
          raws typed (k typed)
      in
      (raws, body)
    in
    let xatom = Tir.AVar param in
    let body_opt : Tir.expr option =
      match ty with
      | Tir.TTuple ts ->
        let raws, inner = bind_fields ts (fun typed ->
            concat_all
              (Tir.EAtom (slit "(")
               :: comma_sep (List.map (fun (fv : Tir.var) ->
                      render_field (Tir.AVar fv) fv.Tir.v_ty) typed)
               @ [Tir.EAtom (slit ")")])) in
        Some (Tir.ECase (xatom,
          [{ Tir.br_tag = Tir_names.tuple_tag (List.length ts);
             br_vars = raws; br_body = inner }], None))
      | Tir.TRecord fs ->
        let parts = List.map (fun (k, ft) ->
            let fv = mkv (fresh "r") ft in
            Tir.ELet (fv, Tir.EField (xatom, k),
              concat_all [Tir.EAtom (slit (k ^ ": "));
                          render_field (Tir.AVar fv) ft])) fs in
        Some (concat_all
                (Tir.EAtom (slit "{ ") :: comma_sep parts
                 @ [Tir.EAtom (slit " }")]))
      | Tir.TCon ("List", [elt]) ->
        (* "[]" / "[" e0 (", " ei)* "]" — a recursive tail helper carries
           the accumulated string. *)
        let tail_name = fname ^ "$tail" in
        let l = mkv "l" ty and acc = mkv "acc" str_t in
        let raws_t, cons_body_t = bind_fields [elt; ty] (fun typed ->
            let h = List.nth typed 0 and tl = List.nth typed 1 in
            let s = mkv (fresh "s") str_t in
            Tir.ELet (s,
              concat_all [Tir.EAtom (Tir.AVar acc);
                          Tir.EAtom (slit ", ");
                          render_field (Tir.AVar h) elt],
              Tir.EApp (fn_var tail_name [ty; str_t] str_t,
                        [Tir.AVar tl; Tir.AVar s]))) in
        let tail_fn = {
          Tir.fn_name = tail_name; fn_params = [l; acc]; fn_ret_ty = str_t;
          fn_body = Tir.ECase (Tir.AVar l,
            [ { Tir.br_tag = "Nil"; br_vars = [];
                br_body = concat_all [Tir.EAtom (Tir.AVar acc);
                                      Tir.EAtom (slit "]")] };
              { Tir.br_tag = "Cons"; br_vars = raws_t;
                br_body = cons_body_t } ], None);
          fn_kind = Tir.FnNormal } in
        Hashtbl.replace fn_table tail_name tail_fn;
        if not (Hashtbl.mem done_set tail_name) then
          Queue.add (tail_name, tail_fn, []) worklist;
        let raws_0, cons_body_0 = bind_fields [elt; ty] (fun typed ->
            let h0 = List.nth typed 0 and t0 = List.nth typed 1 in
            let s = mkv (fresh "s") str_t in
            Tir.ELet (s,
              concat_all [Tir.EAtom (slit "[");
                          render_field (Tir.AVar h0) elt],
              Tir.EApp (fn_var tail_name [ty; str_t] str_t,
                        [Tir.AVar t0; Tir.AVar s]))) in
        Some (Tir.ECase (xatom,
          [ { Tir.br_tag = "Nil"; br_vars = [];
              br_body = Tir.EAtom (slit "[]") };
            { Tir.br_tag = "Cons"; br_vars = raws_0;
              br_body = cons_body_0 } ], None))
      | Tir.TCon (tname, targs) ->
        (* ADT: per-ctor branches, field types = the typedef's generic field
           types with the TCon's args substituted by free-tvar declaration
           order (the same convention as Llvm_toplevel.build_ctor_info and
           perceus's resolve_case_field_ty). *)
        let last_seg s = match String.rindex_opt s '.' with
          | Some i -> String.sub s (i + 1) (String.length s - i - 1)
          | None -> s in
        (* EXACT name first; fall back to last-segment candidates only when
           no exact match exists, and among those prefer one whose free-tvar
           count matches |targs| — several types can share a short name
           (the stdlib ordered_map/sorted_set `Tree`s vs a user `Tree`), and
           a wrong pick either miscounts params (silently returning None) or
           renders the wrong constructors. *)
        let exact = List.find_map (function
            | Tir.TDVariant (n, ctors) when String.equal n tname -> Some ctors
            | _ -> None) !_mono_type_defs in
        let variant = match exact with
          | Some _ -> exact
          | None ->
            let cands = List.filter_map (function
                | Tir.TDVariant (n, ctors)
                  when String.equal (last_seg n) (last_seg tname) -> Some ctors
                | _ -> None) !_mono_type_defs in
            let tvar_count ctors =
              let seen = Hashtbl.create 4 in
              let rec c = function
                | Tir.TVar n -> if not (Hashtbl.mem seen n) then Hashtbl.add seen n ()
                | Tir.TCon (_, a) -> List.iter c a
                | Tir.TFn (ps, r) -> List.iter c ps; c r
                | Tir.TTuple ts -> List.iter c ts
                | Tir.TPtr t -> c t
                | _ -> () in
              List.iter (fun (_, ftys) -> List.iter c ftys) ctors;
              Hashtbl.length seen in
            (match List.find_opt
                     (fun ctors -> tvar_count ctors = List.length targs) cands with
             | Some _ as r -> r
             | None -> (match cands with c :: _ -> Some c | [] -> None))
        in
        (match variant with
         | None -> None
         | Some ctors ->
           let seen = Hashtbl.create 4 in
           let params_order = ref [] in
           let rec collect = function
             | Tir.TVar n ->
               if not (Hashtbl.mem seen n) then begin
                 Hashtbl.add seen n (); params_order := n :: !params_order
               end
             | Tir.TCon (_, args) -> List.iter collect args
             | Tir.TFn (ps, r)    -> List.iter collect ps; collect r
             | Tir.TTuple ts      -> List.iter collect ts
             | Tir.TPtr t         -> collect t
             | _ -> () in
           List.iter (fun (_, ftys) -> List.iter collect ftys) ctors;
           let param_names = List.rev !params_order in
           if List.length param_names <> List.length targs then None
           else begin
             let s = List.combine param_names targs in
             let branches = List.map (fun (cname, gftys) ->
                 let ftys = List.map (subst_ty s) gftys in
                 let disp = last_seg cname in
                 match ftys with
                 | [] -> { Tir.br_tag = cname; br_vars = [];
                           br_body = Tir.EAtom (slit disp) }
                 | _ ->
                   let raws, body = bind_fields ftys (fun typed ->
                       concat_all
                         (Tir.EAtom (slit (disp ^ "("))
                          :: comma_sep (List.map (fun (fv : Tir.var) ->
                                 render_field (Tir.AVar fv) fv.Tir.v_ty) typed)
                          @ [Tir.EAtom (slit ")")])) in
                   { Tir.br_tag = cname; br_vars = raws; br_body = body })
                 ctors in
             Some (Tir.ECase (xatom, branches, None))
           end)
      | _ -> None
    in
    match body_opt with
    | None ->
      Hashtbl.remove fn_table fname;
      None
    | Some body ->
      let fn = { Tir.fn_name = fname; fn_params = [param]; fn_ret_ty = str_t;
                 fn_body = body; fn_kind = Tir.FnNormal } in
      Hashtbl.replace fn_table fname fn;
      if not (Hashtbl.mem done_set fname) then
        Queue.add (fname, fn, []) worklist;
      Some fname
  end

(* ── Type matching (poly → concrete → subst) ────────────────────── *)

(** [match_ty poly conc acc] extends substitution [acc] by matching
    the polymorphic type [poly] (which may contain TVar) against the
    concrete type [conc]. Does not fail — unmatched combinations are
    silently skipped (this is not unification; types must be structurally
    compatible after lowering). *)
let rec match_ty (poly : Tir.ty) (conc : Tir.ty) (acc : ty_subst) : ty_subst =
  match poly, conc with
  | Tir.TVar name, t ->
    (* Prefer concrete bindings over TVar-to-TVar bindings.  Without this,
       first-wins merging loses information when arg types are a mix of
       TVar-typed (e.g. a let-bound polymorphic value like [let empty =
       Map.empty()]) and concrete (e.g. string literals) — the TVar binding
       would win and the concrete type from a later arg would be discarded,
       leaving the callee unmangled with TVar args. *)
    (match List.assoc_opt name acc with
     | None -> (name, t) :: acc
     | Some existing ->
       (* TVar "_" is the lowering fallback placeholder used when a span is
          absent from the type_map (e.g. stdlib code lowered in a REPL
          context).  It must be treated as "worse" than any real type so that
          a later concrete binding like {b→Int} replaces an earlier spurious
          {b→TVar "_"}.  Without this, fold_left$List_Int$Int$... recursively
          calls fold_left$List_Int$V__$... instead of itself, halving results. *)
       let is_wildcard_placeholder = function Tir.TVar "_" -> true | _ -> false in
       if (has_tvar existing || is_wildcard_placeholder existing)
          && not (has_tvar t || is_wildcard_placeholder t) then
         (name, t) :: List.remove_assoc name acc
       else
         acc)
  | Tir.TCon (n1, ps1), Tir.TCon (n2, ps2) when n1 = n2 && List.length ps1 = List.length ps2 ->
    List.fold_left2 (fun acc p c -> match_ty p c acc) acc ps1 ps2
  | Tir.TTuple ps1, Tir.TTuple ps2 when List.length ps1 = List.length ps2 ->
    List.fold_left2 (fun acc p c -> match_ty p c acc) acc ps1 ps2
  | Tir.TRecord fs1, Tir.TRecord fs2 ->
    (* Match field types by NAME (records may differ in field order between the
       polymorphic param and the concrete arg).  Without this, a generic helper
       whose parameter is a record carrying a type var in a field — e.g.
       [get_req_header(conn : { hdrs : List((String, 'a)) })] called with a
       concrete [{ hdrs : List((String, String)) }] — never binds ['a→String],
       so a callee it invokes ([lookup]) stays monomorphized with an abstract
       value type.  An abstract [Option('a)] is then [Boxed] while the concrete
       caller reads it as a [Niche] — a representation mismatch that reads the
       Some-box pointer as the payload (SIGSEGV).  Mirrors the TTuple/TCon
       cases. *)
    List.fold_left (fun acc (n, p) ->
        match List.assoc_opt n fs2 with
        | Some c -> match_ty p c acc
        | None   -> acc) acc fs1
  | Tir.TFn (ps1, r1), Tir.TFn (ps2, r2) when List.length ps1 = List.length ps2 ->
    let acc = List.fold_left2 (fun acc p c -> match_ty p c acc) acc ps1 ps2 in
    match_ty r1 r2 acc
  | Tir.TPtr p, Tir.TPtr c -> match_ty p c acc
  | _ -> acc

(* ── Worklist monomorphization ──────────────────────────────────── *)

(** Set of function names bound by a lexically-enclosing nested [fn]
    (an [ELetRec] binding).  Such names shadow same-named top-level
    functions and must NOT be resolved against the module-level
    [fn_table] — see the shadowing guard in [rewrite_calls]. *)
module SSet = Set.Make (String)

(** Derive the type substitution for calling [fn_def] with arguments
    of types [arg_tys]. Matches each parameter's type against the
    corresponding argument type to collect TVar bindings. *)
let build_subst (fn : Tir.fn_def) (arg_tys : Tir.ty list) : ty_subst =
  let param_tys = List.map (fun v -> v.Tir.v_ty) fn.Tir.fn_params in
  let pairs =
    if List.length param_tys = List.length arg_tys
    then List.combine param_tys arg_tys
    else []   (* arity mismatch — don't substitute *)
  in
  List.fold_left (fun acc (poly, conc) -> match_ty poly conc acc) [] pairs

(** Return the TIR type of an atom. *)
let atom_ty : Tir.atom -> Tir.ty = function
  | Tir.AVar v    -> v.Tir.v_ty
  | Tir.ADefRef _ -> Tir.TPtr Tir.TUnit
  | Tir.ALit (March_ast.Ast.LitInt _)    -> Tir.TInt
  | Tir.ALit (March_ast.Ast.LitFloat _)  -> Tir.TFloat
  | Tir.ALit (March_ast.Ast.LitBool _)   -> Tir.TBool
  | Tir.ALit (March_ast.Ast.LitString _) -> Tir.TString
  | Tir.ALit (March_ast.Ast.LitAtom _)   -> Tir.TUnit

(** [find_first_call fn_name expr] scans [expr] for the first direct call
    ([EApp] or [ECallPtr]) to a function named [fn_name] and returns the
    argument types of that call, or [None] if no such call is found.

    Used to derive a "local subst" for generalized inner functions (produced
    by [ELetFn]) whose TVar IDs differ from the enclosing function's TVars.
    After the outer subst has been applied by [subst_fn_def], the arg types
    at the call site are concrete and can be matched against the inner fn's
    param types to obtain a specialising substitution.

    We do NOT recurse into nested [ELetRec] bodies, because the inner
    function may shadow [fn_name] there.  Branching constructs ([ECase]) are
    searched left-to-right and the first match wins. *)
let rec find_first_call (fn_name : string) (expr : Tir.expr)
    : Tir.ty list option =
  match expr with
  | Tir.EApp (fv, args) when fv.Tir.v_name = fn_name ->
    Some (List.map atom_ty args)
  | Tir.ECallPtr (Tir.AVar fv, args) when fv.Tir.v_name = fn_name ->
    Some (List.map atom_ty args)
  | Tir.EApp _ | Tir.ECallPtr _ | Tir.EAtom _
  | Tir.ETuple _ | Tir.ERecord _ | Tir.EField _ | Tir.EUpdate _
  | Tir.EAlloc _ | Tir.EStackAlloc _ | Tir.EFree _
  | Tir.EIncRC _ | Tir.EDecRC _ | Tir.EAtomicIncRC _ | Tir.EAtomicDecRC _
  | Tir.EReuse _ -> None
  | Tir.ELet (_, e1, e2) ->
    (match find_first_call fn_name e1 with
     | Some _ as r -> r
     | None -> find_first_call fn_name e2)
  | Tir.ELetRec (_, body) ->
    (* Don't recurse into the nested fn bodies — only scan the continuation. *)
    find_first_call fn_name body
  | Tir.ECase (_, brs, def) ->
    let first_in_brs = List.fold_left (fun acc br ->
        match acc with Some _ -> acc | None ->
          find_first_call fn_name br.Tir.br_body
      ) None brs in
    (match first_in_brs with
     | Some _ -> first_in_brs
     | None   -> Option.bind def (find_first_call fn_name))
  | Tir.ESeq (e1, e2) ->
    (match find_first_call fn_name e1 with
     | Some _ as r -> r
     | None -> find_first_call fn_name e2)

(** Ensure any function referenced as a value (atom) is enqueued for emission. *)
let ensure_atom_fns fn_table done_set worklist atoms =
  List.iter (function
    | Tir.AVar v ->
      let name = v.Tir.v_name in
      (match Hashtbl.find_opt fn_table name with
       | Some orig_fn when not (Hashtbl.mem done_set name) ->
         Queue.add (name, orig_fn, []) worklist
       | _ -> ())
    | Tir.ADefRef _ -> ()  (* global def ref — not in fn_table, skip *)
    | _ -> ()
  ) atoms

(** Rewrite all [EApp] and [ELetRec] calls in [expr] that target
    polymorphic functions, replacing them with calls to the
    specialized (mangled) version and enqueuing the specialization
    if not already done.

    [iface_methods] is the dispatch table saved after lowering: maps interface
    method names (both base and qualified) to [(type_name, mangled_impl)].
    [record_to_typename] maps structural [TRecord] types to their nominal names
    so that impl lookups work even when ptype aliases have been expanded. *)
let rec rewrite_calls
    (fn_table         : (string, Tir.fn_def) Hashtbl.t)
    (done_set         : (string, unit) Hashtbl.t)
    (worklist         : (string * Tir.fn_def * ty_subst) Queue.t)
    (iface_methods    : (string, (string * string) list) Hashtbl.t)
    (record_to_typename : (string, string) Hashtbl.t)
    (shadowed         : SSet.t)
    (expr             : Tir.expr)
  : Tir.expr =
  (* Concrete type of the first call argument (for interface dispatch). *)
  let first_arg_ty (args : Tir.atom list) : Tir.ty =
    match args with
    | (Tir.AVar v) :: _ -> v.Tir.v_ty
    | (Tir.ALit l) :: _ ->
      (match l with
       | March_ast.Ast.LitInt _    -> Tir.TInt
       | March_ast.Ast.LitFloat _  -> Tir.TFloat
       | March_ast.Ast.LitBool _   -> Tir.TBool
       | March_ast.Ast.LitString _ -> Tir.TString
       | March_ast.Ast.LitAtom _   -> Tir.TUnit)
    | _ -> Tir.TUnit
  in
  (* Enqueue a resolved interface impl (e.g. "Show$List.show") for emission,
     specializing it under the substitution derived from THIS call site's
     concrete argument types — exactly like the ordinary generic-fn
     specialization a few lines below (build_subst + mangle_name).

     CRITICAL (Wave 2 Task 1 — println-of-list miscompile): an impl body can
     itself be generic — e.g. `impl Show(List(a)) when Show(a)` has an
     element-level `show(x : a)` inside it.  The three call sites below used
     to enqueue such impls with an EMPTY substitution, so the impl was
     emitted once, still generic, and its nested `show(x)` call stayed an
     unresolved bare reference all the way to llvm_emit — which then mis-bound
     it via the `unqualified_fns` dot-suffix fallback to an arbitrary
     same-named impl (the actual bug: Int → SIGSEGV, String → non-exhaustive
     panic, Option → SIGSEGV/SIGBUS, depending on which impl DCE kept first).

     Returns the name the CALLER should use as the callee (either the
     original [mangled_name] when no further specialization was needed —
     the impl was already monomorphic, e.g. Show$Int.show — or a further
     doubly-mangled name, e.g. "Show$List.show$List_Int", when it was).

     Name convention: the SAME [mangle_name] scheme used for ordinary
     generic fns (glued via [Tir_names.specialize_mangle], Wave 3 Chunk 2
     Task 1 — see that helper's doc for why this never trips
     [Tir_names.is_iface_mangled]): the impl name gets an extra
     "$"-separated suffix built from its OWN concrete parameter types
     after substitution, e.g. "Show$List.show" + [List(Int)] ->
     "Show$List.show$List_Int".  Recursion (List(List(Int)) etc.) terminates
     via the existing worklist [done_set] dedup: once a given specialized
     name has been enqueued/emitted, subsequent calls just reuse it. *)
  let enqueue_specialized_impl
      (mangled_name : string) (args : Tir.atom list) : string =
    match Hashtbl.find_opt fn_table mangled_name with
    | None -> mangled_name  (* not in fn_table (e.g. a builtin-backed impl) *)
    | Some orig_impl ->
      let arg_tys = List.map atom_ty args in
      let subst = build_subst orig_impl arg_tys in
      if subst = [] then begin
        if not (Hashtbl.mem done_set mangled_name) then
          Queue.add (mangled_name, orig_impl, []) worklist;
        mangled_name
      end else begin
        let param_tys_concrete =
          List.map (fun v -> subst_ty subst v.Tir.v_ty) orig_impl.Tir.fn_params in
        let specialized_name = mangle_name mangled_name param_tys_concrete in
        if not (Hashtbl.mem done_set specialized_name) then
          Queue.add (specialized_name, orig_impl, subst) worklist;
        specialized_name
      end
  in
  (* If [name] is an interface method, resolve it to the impl for the concrete
     first-argument type.  Returns the mangled impl function name, or None.
     Mirrors the inline resolution in the [None] branch below; used to fix the
     case where a user top-level function (e.g. `show`) shares a name with an
     interface method and would otherwise hijack the dispatch inside prelude
     generics like `println`. *)
  let iface_impl_name (name : string) (args : Tir.atom list) : string option =
    let rec find_iface_impls n =
      match Hashtbl.find_opt iface_methods n with
      | Some impls -> Some impls
      | None ->
        (match String.index_opt n '.' with
         | None -> None
         | Some i -> find_iface_impls (String.sub n (i + 1) (String.length n - i - 1)))
    in
    match find_iface_impls name with
    | None -> None
    | Some impls ->
      let type_name = match first_arg_ty args with
        | Tir.TCon (n, _) -> Some n
        | Tir.TRecord fs ->
          let sorted = List.sort (fun (a, _) (b, _) -> String.compare a b) fs in
          Hashtbl.find_opt record_to_typename (mangle_ty (Tir.TRecord sorted))
        | Tir.TString -> Some "String"
        | Tir.TInt    -> Some "Int"
        | Tir.TFloat  -> Some "Float"
        | Tir.TBool   -> Some "Bool"
        | _ -> None
      in
      (match type_name with
       | None -> None
       | Some tname -> resolve_impl_by_type impls tname)
  in
  (* When `show` dispatch fails (no user/prelude impl for the concrete
     first-arg type — tuples, records, plain ADTs), synthesize the
     structural renderer instead of leaving a bare `show` for the linker
     to reject — see [synth_derived_show]. *)
  let try_synth_show (name : string) (args : Tir.atom list) : string option =
    let base = match String.rindex_opt name '.' with
      | Some i -> String.sub name (i + 1) (String.length name - i - 1)
      | None -> name in
    if not (String.equal base "show") then None
    else match args with
      | [a] -> synth_derived_show fn_table done_set worklist (atom_ty a)
      | _ -> None
  in
  match expr with
  | Tir.EApp (f_var, args) ->
    (* Ensure functions passed as arguments are discovered *)
    ensure_atom_fns fn_table done_set worklist args;
    (* Check if the *callee's definition* is polymorphic (has TVar in params),
       NOT whether f_var.v_ty has TVar. After Task 1, call sites have concrete
       types from the type_map, so f_var.v_ty is already monomorphic there —
       but the fn_def it refers to may still be the generic version. *)
    let orig_name = f_var.Tir.v_name in
    (* A call to a name bound by a lexically-enclosing nested [fn] (ELetRec)
       must NOT be resolved against the module-level [fn_table]: the nested
       binding shadows any same-named top-level function.  Leave it untouched
       for [Defun] to lift as a local closure/apply — exactly what happens when
       no top-level fn shares the name.  Without this guard a user top-level
       `go` captures every stdlib nested `go` helper (List.length/rev/map …):
       the call's callee is silently rebound to the wrong body, so e.g.
       `List.length(xs)` runs the user's `go` and returns garbage. *)
    if SSet.mem orig_name shadowed then expr
    else
    (match Hashtbl.find_opt fn_table orig_name with
     | None ->
       (* Not in fn_table (builtin or external).  Before giving up, check if
          this is an unresolved interface method call that can now be resolved
          because the type-variable substitution gave us a concrete first-arg
          type.  This handles the case where lower.ml could not resolve the
          dispatch at lowering time (polymorphic parameter), but mono has now
          replaced the TVar with a concrete type. *)
       (* Try the method name as-is, then progressively strip module prefixes.
          This handles calls like "Conduit.Storage.checkpoint_get" where the
          impl was registered under "Storage.checkpoint_get" (because the user
          wrote `impl Storage(VaultStorage)` after `import Conduit`). *)
       let rec find_iface_impls name =
         match Hashtbl.find_opt iface_methods name with
         | Some impls -> Some impls
         | None ->
           (match String.index_opt name '.' with
            | None -> None
            | Some i ->
              find_iface_impls (String.sub name (i + 1) (String.length name - i - 1)))
       in
       (match find_iface_impls orig_name with
        | None ->
          expr   (* Not an interface method — truly external/builtin *)
        | Some impls ->
          (match args with
           | [] -> expr
           | first_arg :: _ ->
             let arg_ty = match first_arg with
               | Tir.AVar v -> v.Tir.v_ty
               | _ -> Tir.TUnit
             in
             (* Get the concrete type name from the first argument. *)
             let type_name = match arg_ty with
               | Tir.TCon (n, _) -> Some n
               | Tir.TRecord fs ->
                 (* ptype aliases expand to structural records; look up the
                    nominal name via the canonical mangle-string key so that
                    field-order differences between lower_ty and convert_ty
                    don't cause missed lookups. *)
                 let sorted = List.sort (fun (a, _) (b, _) -> String.compare a b) fs in
                 let key = mangle_ty (Tir.TRecord sorted) in
                 Hashtbl.find_opt record_to_typename key
               (* TIR primitive types are distinct constructors from TCon.
                  After subst_ty {K→TString}, arg_ty = TString, not TCon("String",[]).
                  Without these cases, iface dispatch (e.g. hash → march_hash_string)
                  fails and leaves a bare @hash extern that the linker cannot resolve. *)
               | Tir.TString -> Some "String"
               | Tir.TInt    -> Some "Int"
               | Tir.TFloat  -> Some "Float"
               | Tir.TBool   -> Some "Bool"
               | _ -> None
             in
             (* Fallback: if the concrete type could not be determined (type was
                erased to TVar "_", or was coerced to a primitive like TString
                as an opaque placeholder), AND there is exactly one registered
                impl, resolve to that single impl.  This is sound when the
                program has only one concrete implementation — the typical case
                for single-backend libraries like Conduit with VaultStorage. *)
             let type_name_or_single = match type_name with
               | Some _ -> type_name
               | None ->
                 (match impls with
                  | [(_, _)] -> Some "$single_impl$"   (* sentinel: use the only impl *)
                  | _ -> None)
             in
             (match type_name_or_single with
              | None ->
                (* Unnameable concrete type (tuple/record) — synthesize the
                   structural show when this is a show call. *)
                (match try_synth_show orig_name args with
                 | Some n -> Tir.EApp ({ f_var with Tir.v_name = n }, args)
                 | None -> expr   (* Still cannot resolve — leave for linker *))
              | Some tname ->
                (match resolve_impl_by_type impls tname with
                 | None ->
                   (* Named type with no registered impl (plain ADT) —
                      synthesize the structural show when applicable. *)
                   (match try_synth_show orig_name args with
                    | Some n -> Tir.EApp ({ f_var with Tir.v_name = n }, args)
                    | None -> expr)
                 | Some mangled_name ->
                   (* Resolved!  Enqueue the impl (specialized under this
                      call's concrete arg types — see enqueue_specialized_impl
                      above for why this must NOT be an empty substitution). *)
                   let final_name = enqueue_specialized_impl mangled_name args in
                   let f_var' = { f_var with Tir.v_name = final_name } in
                   Tir.EApp (f_var', args)))))
     | Some orig_fn
       when (* Interface-method-name collision: the callee name is a user
               function, but it is ALSO an interface method, AND the user
               function's first-parameter type does not match this call's
               concrete first-argument type, AND an interface impl exists for
               that argument type.  This happens when a user defines e.g.
               `fn show(r: Option(Int))` (named `show`, the Show method) and a
               prelude generic like `println` calls `show(x)` on a different
               type (e.g. String): mono must dispatch to the interface impl
               (Show$String.show), not the user function. Same-type calls (the
               user's own show(Option), or stdlib `BigInt.compare(BigInt)`)
               have matching param/arg types and are left untouched. *)
            (match iface_impl_name orig_name args, orig_fn.Tir.fn_params with
             | Some _, p :: _ ->
               mangle_ty p.Tir.v_ty <> mangle_ty (first_arg_ty args)
             | _ -> false) ->
       (match iface_impl_name orig_name args with
        | Some mangled_name ->
          (* Specialize under this call's concrete arg types — see
             enqueue_specialized_impl for why an empty substitution is wrong
             (Wave 2 Task 1: println-of-list miscompile). *)
          let final_name = enqueue_specialized_impl mangled_name args in
          Tir.EApp ({ f_var with Tir.v_name = final_name }, args)
        | None -> expr)
     | Some orig_fn
       when not (List.exists (fun v ->
         has_tvar v.Tir.v_ty ||
         (* TVar "_" is a lowering placeholder — treat it as a wildcard that
            can still be specialized when concrete arg types are available.
            Without this, Map.key_hash(k : TVar "_") would be emitted as-is
            and the internal hash(k) call would stay as bare @hash, crashing. *)
         (match v.Tir.v_ty with Tir.TVar "_" -> true | _ -> false)
       ) orig_fn.Tir.fn_params) ->
       (* Callee params are monomorphic but it may not have been seeded
          (e.g. return type has TVar).  Ensure it's enqueued. *)
       if not (Hashtbl.mem done_set orig_name) then
         Queue.add (orig_name, orig_fn, []) worklist;
       expr
     | Some orig_fn ->
       let lit_ty = function
         | March_ast.Ast.LitInt _    -> Tir.TInt
         | March_ast.Ast.LitFloat _  -> Tir.TFloat
         | March_ast.Ast.LitBool _   -> Tir.TBool
         | March_ast.Ast.LitString _ -> Tir.TString
         | March_ast.Ast.LitAtom _   -> Tir.TUnit
       in
       let arg_tys = List.map (function
           | Tir.AVar v -> v.Tir.v_ty
           | Tir.ADefRef _ -> Tir.TPtr Tir.TUnit  (* global ref, treat as opaque ptr *)
           | Tir.ALit l -> lit_ty l
         ) args in
       let subst = build_subst orig_fn arg_tys in
       if subst = [] then begin
         (* No specialization needed (monomorphic or unresolved TVar args) —
            but still enqueue to ensure the function is emitted.  Matches the
            ECallPtr branch below which already handles this case correctly. *)
         if not (Hashtbl.mem done_set orig_name) then
           Queue.add (orig_name, orig_fn, []) worklist;
         expr
       end
       else begin
         let param_tys_concrete = List.map (fun v -> subst_ty subst v.Tir.v_ty)
             orig_fn.Tir.fn_params in
         let mangled = mangle_name orig_name param_tys_concrete in
         if not (Hashtbl.mem done_set mangled) then
           Queue.add (mangled, orig_fn, subst) worklist;
         let f_var' = { f_var with Tir.v_name = mangled;
                                   v_ty = subst_ty subst f_var.Tir.v_ty } in
         Tir.EApp (f_var', args)
       end)
  (* ECallPtr: if the callee is a known top-level fn, ensure it's discovered *)
  | Tir.ECallPtr (fn_atom, args) ->
    (match fn_atom with
     | Tir.AVar v ->
       let orig_name = v.Tir.v_name in
       (* Same lexical-shadowing guard as the EApp case above: a call to a
          nested-fn-bound name is a local closure call, not a top-level fn. *)
       if SSet.mem orig_name shadowed then expr
       else
       (match Hashtbl.find_opt fn_table orig_name with
        | None ->
          (* Not a user function.  Try to resolve as an interface method call
             (same logic as EApp above).  This handles the common case where
             lower.ml/defun emits ECallPtr for cross-module interface dispatch
             when the first argument's type is erased to TVar "_". *)
          let rec find_iface_impls name =
            match Hashtbl.find_opt iface_methods name with
            | Some impls -> Some impls
            | None ->
              (match String.index_opt name '.' with
               | None -> None
               | Some i ->
                 find_iface_impls (String.sub name (i + 1) (String.length name - i - 1)))
          in
          (match find_iface_impls orig_name with
           | None -> expr   (* Truly external/builtin — unchanged *)
           | Some impls ->
             (match args with
              | [] -> expr
              | first_arg :: _ ->
                let arg_ty = match first_arg with
                  | Tir.AVar av -> av.Tir.v_ty
                  | _ -> Tir.TUnit
                in
                let type_name = match arg_ty with
                  | Tir.TCon (n, _) -> Some n
                  | Tir.TRecord fs ->
                    let sorted = List.sort (fun (a, _) (b, _) -> String.compare a b) fs in
                    let key = mangle_ty (Tir.TRecord sorted) in
                    Hashtbl.find_opt record_to_typename key
                  | Tir.TString -> Some "String"
                  | Tir.TInt    -> Some "Int"
                  | Tir.TFloat  -> Some "Float"
                  | Tir.TBool   -> Some "Bool"
                  | _ -> None
                in
                (* Single-impl fallback for type-erased args (TVar or opaque
                   primitive placeholder). *)
                let type_name_or_single = match type_name with
                  | Some _ -> type_name
                  | None ->
                    (match impls with
                     | [(_, _)] -> Some "$single_impl$"
                     | _ -> None)
                in
                (match type_name_or_single with
                 | None -> expr
                 | Some tname ->
                   (match resolve_impl_by_type impls tname with
                    | None -> expr
                    | Some mangled_name ->
                      (* Specialize under this call's concrete arg types —
                         see enqueue_specialized_impl for why an empty
                         substitution is wrong (Wave 2 Task 1: println-of-list
                         miscompile — this is the ECallPtr twin of the EApp
                         site above). *)
                      let final_name = enqueue_specialized_impl mangled_name args in
                      (* Rewrite ECallPtr to use the resolved impl name.
                         Switch to EApp so that the call goes through the direct
                         call path in llvm_emit rather than the closure-dispatch
                         path, which would try to load a fn_ptr from a struct. *)
                      let f_var' = { v with Tir.v_name = final_name } in
                      Tir.EApp (f_var', args)))))
        | Some orig_fn ->
          (* If callee is polymorphic, try to build a substitution from args *)
          let lit_ty = function
            | March_ast.Ast.LitInt _    -> Tir.TInt
            | March_ast.Ast.LitFloat _  -> Tir.TFloat
            | March_ast.Ast.LitBool _   -> Tir.TBool
            | March_ast.Ast.LitString _ -> Tir.TString
            | March_ast.Ast.LitAtom _   -> Tir.TUnit
          in
          let arg_tys = List.map (function
              | Tir.AVar v -> v.Tir.v_ty
              | Tir.ADefRef _ -> Tir.TPtr Tir.TUnit  (* global ref, treat as opaque ptr *)
              | Tir.ALit l -> lit_ty l
            ) args in
          (* Partial application: only first N params have concrete args *)
          let param_vars = orig_fn.Tir.fn_params in
          let n = min (List.length arg_tys) (List.length param_vars) in
          let pairs = List.combine
              (List.filteri (fun i _ -> i < n) (List.map (fun v -> v.Tir.v_ty) param_vars))
              (List.filteri (fun i _ -> i < n) arg_tys) in
          let subst = List.fold_left (fun acc (poly, conc) -> match_ty poly conc acc) [] pairs in
          if subst = [] then begin
            (* No specialization needed — just ensure it's enqueued as-is *)
            if not (Hashtbl.mem done_set orig_name) then
              Queue.add (orig_name, orig_fn, []) worklist;
            expr
          end else begin
            let param_tys_concrete = List.map (fun v -> subst_ty subst v.Tir.v_ty) param_vars in
            let mangled = mangle_name orig_name param_tys_concrete in
            if not (Hashtbl.mem done_set mangled) then
              Queue.add (mangled, orig_fn, subst) worklist;
            let v' = { v with Tir.v_name = mangled;
                              v_ty = subst_ty subst v.Tir.v_ty } in
            Tir.ECallPtr (Tir.AVar v', args)
          end)
     | _ -> expr)
  | Tir.ELet (v, (Tir.ELetRec (fns, binding_body) as e1), cont)
    when List.exists (fun fn -> has_tvar (Tir.TFn (List.map (fun p -> p.Tir.v_ty) fn.Tir.fn_params, fn.Tir.fn_ret_ty))) fns ->
    (* Special case: a generalized local function (from ELetFn) is bound here
       and called in the continuation [cont].  After the outer substitution has
       been applied by [subst_fn_def], the call site in [cont] has concrete arg
       types that can be matched against the inner fn's (still-abstract) param
       types to produce a "local subst".  Applying it in-place ensures that
       defun later lifts a fully-monomorphised closure instead of a generic one
       that would leave TVar type arguments (e.g. Map.key_hash$V__4370) that
       the linker cannot resolve.

       Concretely: for
         fn from_list(pairs: List(K, V), cmp) = let go = ... in go(pairs, empty())
       specialised with {K→String}, the call go(pairs, empty()) has arg types
       [List(String,String), Map(String,String)].  Matching against go's params
       (List(K_go, V_go), Map(K_go, V_go)) gives {K_go→String, V_go→String}
       — a subst that covers go's own generalised TVars. *)
    (* For each inner fn: derive a local subst from its first concrete call
       site in [cont], apply it in-place, then run rewrite_calls on the body. *)
    let per_fn_substs : (string * ty_subst) list =
      List.filter_map (fun fn ->
          let fn_has_tvar = List.exists (fun p -> has_tvar p.Tir.v_ty) fn.Tir.fn_params
                            || has_tvar fn.Tir.fn_ret_ty in
          if not fn_has_tvar then None
          else
            match find_first_call fn.Tir.fn_name cont with
            | None -> None
            | Some call_arg_tys ->
              let s = build_subst fn call_arg_tys in
              if s = [] then None else Some (fn.Tir.fn_name, s)
        ) fns
    in
    (* Merge all per-fn substs into one (first-wins across fns). *)
    let merged_subst =
      List.fold_left (fun acc (_, s) ->
          List.fold_left (fun acc (k, v) ->
              if List.mem_assoc k acc then acc else (k, v) :: acc)
            acc s)
        [] per_fn_substs
    in
    (* These locally-bound fn names shadow any same-named top-level fn within
       the inner bodies, the ELetRec body, and the continuation. *)
    let inner_shadowed =
      List.fold_left (fun s fn -> SSet.add fn.Tir.fn_name s) shadowed fns in
    let updated_fns = List.map (fun fn ->
        let local_subst = match List.assoc_opt fn.Tir.fn_name per_fn_substs with
          | Some s -> s | None -> [] in
        let fn' = if local_subst = [] then fn else subst_fn_def local_subst fn in
        { fn' with Tir.fn_body =
            rewrite_calls fn_table done_set worklist iface_methods record_to_typename
              inner_shadowed fn'.Tir.fn_body }
      ) fns in
    (* Apply the merged subst to binding_body (e.g. EAtom(AVar fn_var)) so
       the closure-variable type inside the ELetRec stays consistent with the
       updated fn params.  Also update the outer binding var [v]. *)
    let binding_body' =
      if merged_subst = [] then binding_body
      else subst_expr merged_subst binding_body in
    let v' = if merged_subst = [] then v else subst_var merged_subst v in
    let _ = e1 in  (* e1 deconstructed into fns/binding_body above *)
    Tir.ELet (v',
      Tir.ELetRec (updated_fns,
        rewrite_calls fn_table done_set worklist iface_methods record_to_typename
          inner_shadowed binding_body'),
      rewrite_calls fn_table done_set worklist iface_methods record_to_typename
        inner_shadowed cont)
  | Tir.ELet (v, e1, e2) ->
    (* [v] is bound in [e2]; if it names a local fn/closure it shadows a
       same-named top-level fn for callee resolution there.  A block-level
       nested `fn go(...) do ... end` followed by `go(xs, 0)` lowers to
       `ELet("go", ELetRec([go], AVar go), go(xs, 0))` — the resolving call
       lives in the continuation [e2], NOT inside the ELetRec body — so the
       ELetRec-name shadowing above is not enough for a monomorphic nested
       helper (e.g. List.sum_int's `go`). *)
    Tir.ELet (v,
      rewrite_calls fn_table done_set worklist iface_methods record_to_typename shadowed e1,
      rewrite_calls fn_table done_set worklist iface_methods record_to_typename
        (SSet.add v.Tir.v_name shadowed) e2)
  | Tir.ELetRec (fns, body) ->
    (* The locally-bound fn names shadow same-named top-level fns within the
       inner bodies and the ELetRec body (see the shadowing guard above). *)
    let inner_shadowed =
      List.fold_left (fun s fn -> SSet.add fn.Tir.fn_name s) shadowed fns in
    let fns' = List.map (fun fn ->
        { fn with Tir.fn_body =
            rewrite_calls fn_table done_set worklist iface_methods record_to_typename
              inner_shadowed fn.Tir.fn_body }
      ) fns in
    Tir.ELetRec (fns',
      rewrite_calls fn_table done_set worklist iface_methods record_to_typename
        inner_shadowed body)
  | Tir.ECase (a, brs, def) ->
    let brs' = List.map (fun br ->
        (* Constructor-arg pattern vars are bound in [br_body] and likewise
           shadow same-named top-level fns for callee resolution. *)
        let br_shadowed =
          List.fold_left (fun s (bv : Tir.var) -> SSet.add bv.Tir.v_name s)
            shadowed br.Tir.br_vars in
        { br with Tir.br_body =
            rewrite_calls fn_table done_set worklist iface_methods record_to_typename
              br_shadowed br.Tir.br_body }
      ) brs in
    Tir.ECase (a, brs',
      Option.map
        (rewrite_calls fn_table done_set worklist iface_methods record_to_typename
           shadowed)
        def)
  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (
      rewrite_calls fn_table done_set worklist iface_methods record_to_typename shadowed e1,
      rewrite_calls fn_table done_set worklist iface_methods record_to_typename shadowed e2)
  | other -> other

(** Resolve record-field-projection result types from a now-concrete record.

    A generic helper like [get_req_header(conn, name) = lookup(conn.hdrs, name)]
    types [conn] as a bare row-polymorphic var and gives the projection
    [conn.hdrs] a FRESH type var unrelated to [conn]'s.  Substituting
    [conn → ConcreteRecord] (in [subst_fn_def]) makes the parameter concrete but
    leaves the projection's let-binding typed with that stale var.  Downstream
    [rewrite_calls] then derives an ABSTRACT type for any callee fed the
    projection (e.g. [lookup]'s value type stays ['_NNNN]), so [Option('_NNNN)]
    is emitted [Boxed] while the concrete caller reads it as a [Niche] — an ABI
    mismatch that reads the Some-box pointer as the payload (SIGSEGV).

    Run AFTER [subst_fn_def] (the record is concrete) and BEFORE [rewrite_calls]
    (so callees specialise on the resolved type): for every [let v = a.fld] where
    [a] resolves to a concrete record, retype [v] to the field's type and
    propagate it to [v]'s uses.  Conservative — only adopts a [has_tvar]-free
    field type, so it never introduces a worse type than was already present. *)
let refine_field_types (body : Tir.expr) : Tir.expr =
  let env : (string, Tir.ty) Hashtbl.t = Hashtbl.create 16 in
  let rv (v : Tir.var) : Tir.var =
    match Hashtbl.find_opt env v.Tir.v_name with
    | Some t -> { v with Tir.v_ty = t }
    | None   -> v
  in
  let ra : Tir.atom -> Tir.atom = function
    | Tir.AVar v -> Tir.AVar (rv v)
    | a          -> a
  in
  let ral = List.map ra in
  let rec go (e : Tir.expr) : Tir.expr =
    match e with
    | Tir.ELet (v, Tir.EField (a, n), body) ->
      let a' = ra a in
      let v' =
        if has_tvar v.Tir.v_ty then
          (match atom_ty a' with
           | Tir.TRecord fs ->
             (match List.assoc_opt n fs with
              | Some fty when not (has_tvar fty) ->
                Hashtbl.replace env v.Tir.v_name fty;
                { v with Tir.v_ty = fty }
              | _ -> v)
           | _ -> v)
        else v
      in
      Tir.ELet (v', Tir.EField (a', n), go body)
    | Tir.EAtom a              -> Tir.EAtom (ra a)
    | Tir.EApp (f, args)       -> Tir.EApp (rv f, ral args)
    | Tir.ECallPtr (f, args)   -> Tir.ECallPtr (ra f, ral args)
    | Tir.ELet (v, e1, e2)     -> Tir.ELet (rv v, go e1, go e2)
    | Tir.ELetRec (fns, b)     ->
      Tir.ELetRec
        (List.map (fun fn -> { fn with Tir.fn_body = go fn.Tir.fn_body }) fns, go b)
    | Tir.ECase (a, brs, def)  ->
      Tir.ECase (ra a,
        List.map (fun br -> { br with Tir.br_body = go br.Tir.br_body }) brs,
        Option.map go def)
    | Tir.ETuple atoms         -> Tir.ETuple (ral atoms)
    | Tir.ERecord fs           -> Tir.ERecord (List.map (fun (n, a) -> (n, ra a)) fs)
    | Tir.EField (a, n)        -> Tir.EField (ra a, n)
    | Tir.EUpdate (a, fs)      -> Tir.EUpdate (ra a, List.map (fun (n, x) -> (n, ra x)) fs)
    | Tir.EAlloc (t, args)     -> Tir.EAlloc (t, ral args)
    | Tir.EStackAlloc (t, args)-> Tir.EStackAlloc (t, ral args)
    | Tir.EFree a              -> Tir.EFree (ra a)
    | Tir.EIncRC a             -> Tir.EIncRC (ra a)
    | Tir.EDecRC a             -> Tir.EDecRC (ra a)
    | Tir.EAtomicIncRC a       -> Tir.EAtomicIncRC (ra a)
    | Tir.EAtomicDecRC a       -> Tir.EAtomicDecRC (ra a)
    | Tir.EReuse (a, t, args)  -> Tir.EReuse (ra a, t, ral args)
    | Tir.ESeq (e1, e2)        -> Tir.ESeq (go e1, go e2)
  in
  go body

(** Main entry point. Returns a new [tir_module] with no [TVar] in
    any fn_def that is reachable from a monomorphic root. Polymorphic
    fn_defs with no monomorphic callers are dropped (unreachable).

    [iface_methods] is the dispatch table saved by [Lower.get_iface_methods ()].
    When absent (empty table), interface dispatch post-mono is skipped. *)
let monomorphize ?(iface_methods = Hashtbl.create 0) (m : Tir.tir_module) : Tir.tir_module =
  _mono_type_defs := m.Tir.tm_types;
  (* Build lookup table for original fn_defs *)
  let fn_table : (string, Tir.fn_def) Hashtbl.t = Hashtbl.create 32 in
  List.iter (fun fn -> Hashtbl.replace fn_table fn.Tir.fn_name fn) m.Tir.tm_fns;
  (* Build reverse mapping: canonical TRecord mangle string → nominal type name.
     This allows us to resolve interface impls when a ptype (private type alias)
     has been expanded to its underlying record representation.
     e.g. "FakeWorkflowStorage = {vault_key: String, error: Option(String)}"
     → mangle_ty(TRecord[sorted]) = "R_error_Option_String_vault_key_String"
     → "FakeWorkflowStorage"
     Using a canonical string key (rather than structural Tir.ty key) avoids
     any potential hash/equality issues with complex type trees. *)
  let record_to_typename : (string, string) Hashtbl.t = Hashtbl.create 8 in
  List.iter (function
    | Tir.TDRecord (name, fields) ->
      let sorted = List.sort (fun (a, _) (b, _) -> String.compare a b) fields in
      let key = mangle_ty (Tir.TRecord sorted) in
      Hashtbl.replace record_to_typename key name
    | _ -> ()
  ) m.Tir.tm_types;

  let result   : Tir.fn_def list ref = ref [] in
  let done_set : (string, unit) Hashtbl.t = Hashtbl.create 32 in
  (* worklist entries: (target_name, original_fn_def, subst_to_apply) *)
  let worklist : (string * Tir.fn_def * ty_subst) Queue.t = Queue.create () in
  (* Track specialization count per original function to detect polymorphic
     recursion that would cause unbounded code-size growth.
     Limit chosen conservatively: legitimate generic code rarely needs more
     than a few dozen specializations of a single function. *)
  let spec_counts : (string, int) Hashtbl.t = Hashtbl.create 16 in
  let max_specs_per_fn = 512 in

  (* Seed: all fns that are already monomorphic (no TVar in params or ret),
     plus always seed "main" / "*.main" as entry points.
     Polymorphic exports are NOT seeded here — they will be specialised on
     demand when a concrete call site is found.  Seeding them with an empty
     substitution creates "zombie" specialisations whose type-variable
     arguments cannot be resolved by the interface-dispatch logic, causing
     linker errors when more than one impl is registered. *)
  List.iter (fun fn ->
    let is_mono =
      (not (List.exists (fun v -> has_tvar v.Tir.v_ty) fn.Tir.fn_params)) &&
      not (has_tvar fn.Tir.fn_ret_ty)
    in
    let is_main =
      fn.Tir.fn_name = "main" ||
      (let n = fn.Tir.fn_name in
       let suf = ".main" in
       let ln = String.length n and ls = String.length suf in
       ln >= ls && String.sub n (ln - ls) ls = suf)
    in
    (* Hot-reload migration entry points: always include even when the body
       has a TVar (e.g. from an empty list literal []). The LLVM emitter
       exports them as @__migrate_<Actor> aliases for dlsym at deploy time. *)
    let is_migrate_fn = Tir_names.is_migrate_fn_name fn.Tir.fn_name in
    (* Only seed monomorphic exports; polymorphic ones are specialised on demand *)
    if is_mono || is_main || is_migrate_fn then
      Queue.add (fn.Tir.fn_name, fn, []) worklist
  ) m.Tir.tm_fns;

  while not (Queue.is_empty worklist) do
    let (target_name, orig_fn, subst) = Queue.pop worklist in
    if not (Hashtbl.mem done_set target_name) then begin
      (* Guard against polymorphic recursion creating unbounded specializations.
         Each original function is allowed at most [max_specs_per_fn] distinct
         monomorphic variants.  Exceeding this almost certainly indicates
         polymorphic recursion (e.g. f[T] calls f[List[T]]) which would
         otherwise cause non-termination and unbounded binary size. *)
      let orig_name = orig_fn.Tir.fn_name in
      let count = Option.value ~default:0 (Hashtbl.find_opt spec_counts orig_name) in
      if count >= max_specs_per_fn then
        failwith (Printf.sprintf
          "Monomorphization limit reached: function '%s' has more than %d \
           specializations. This usually indicates polymorphic recursion \
           (e.g. a generic function that calls itself at a different type). \
           Add explicit type annotations or restructure to avoid type-indexed \
           recursion."
          orig_name max_specs_per_fn)
      else begin
        Hashtbl.replace spec_counts orig_name (count + 1);
        Hashtbl.add done_set target_name ();
        (* Apply substitution to get the specialized version *)
        let fn' = subst_fn_def subst orig_fn in
        let fn' = { fn' with Tir.fn_name = target_name } in
        (* Resolve record-field projections against the now-concrete record so
           callees fed a projection specialise on the concrete field type rather
           than a stale row-poly var (see [refine_field_types]). *)
        let refined_body = refine_field_types fn'.Tir.fn_body in
        (* Rewrite calls in the body, enqueuing new specializations *)
        let body' = rewrite_calls fn_table done_set worklist
                      iface_methods record_to_typename SSet.empty refined_body in
        result := { fn' with Tir.fn_body = body' } :: !result
      end
    end
  done;

  { m with Tir.tm_fns = List.rev !result }
