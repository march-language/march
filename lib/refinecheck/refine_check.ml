(* Refinement checking (Phases A1b + A2, minimal vertical slice).

   A post-typecheck pass over the AST: it collects functions whose parameters
   carry an `{Int | predicate}` refinement, then walks every call site and, for
   each refined parameter, discharges a verification condition through the A0
   Z3 bridge (`March_refine`).

   A1b: Int/Bool predicates over the binder `_`, literal / refined-local args.
   A2 : the `len` measure and cross-argument predicates, so bounds such as
        `{Int | _ >= 0 && _ < len(xs)}` are checkable when the length is known
        (a list literal) or symbolically related.

   Soundness stance: an argument we cannot reflect (an unconstrained variable,
   a complex expression) is conservatively SKIPPED — no false positives.
   Scope: direct (named) calls only, no path sensitivity. *)

module A = March_ast.Ast
module Smt = March_refine.Smt
module Refine = March_refine.Refine
module Err = March_errors.Errors

(* A refined parameter: position, predicate binder, predicate expression. *)
type rparam = { idx : int; binder : string; pred : A.expr }

(* A function's signature: parameter names by position + its refined params. *)
type fn_sig = { param_names : string list; refined : rparam list }

let binder_name : A.name option -> string = function
  | None -> "_"
  | Some n -> n.A.txt

let is_int_base : A.ty -> bool = function
  | A.TyCon ({ A.txt = "Int"; _ }, []) -> true
  | _ -> false

(* Length of a list literal (a Cons/Nil ECon chain); None if not a literal. *)
let rec list_len (e : A.expr) : int option =
  match e with
  | A.ECon ({ A.txt = "Nil"; _ }, _, _) -> Some 0
  | A.ECon ({ A.txt = "Cons"; _ }, [ _; tl ], _) ->
    (match list_len tl with Some n -> Some (n + 1) | None -> None)
  | _ -> None

(* Registered measure names for this compilation: the builtin `len` plus any
   user function annotated `@[measure]`.  Set once per [check_module]. *)
let registered_measures : string list ref = ref []
let is_measure (m : string) : bool = m = "len" || List.mem m !registered_measures

(* Measures known to be non-negative (so `m(x) >= 0` is a sound axiom).  `len`
   always; a user measure when its body is syntactically non-negative. *)
let measure_nonneg : string list ref = ref []
let is_nonneg_measure (m : string) : bool = m = "len" || List.mem m !measure_nonneg

(* Conservative syntactic non-negativity of a measure body: every return path is
   a non-negative literal, a sum/product of non-negatives, or a call to a measure
   already known non-negative (incl. the measure itself, inductively). *)
let measure_body_nonneg (self : string) (known : string list) (body : A.expr) : bool =
  let rec go e =
    match e with
    | A.ELit (A.LitInt n, _) -> n >= 0
    | A.EApp (A.EVar { A.txt = ("+" | "*"); _ }, [ a; b ], _) -> go a && go b
    | A.EApp (A.EVar { A.txt = m; _ }, [ _ ], _)
      when m = self || m = "len" || List.mem m known -> true
    | A.EIf (_, t, e, _) -> go t && go e
    | A.ECond (arms, _) -> List.for_all (fun (_, b) -> go b) arms
    | A.EMatch (_, brs, _) -> List.for_all (fun (br : A.branch) -> go br.A.branch_body) brs
    | A.EBlock (es, _) -> (match List.rev es with last :: _ -> go last | [] -> false)
    | _ -> false (* variables, subtraction, arbitrary calls: unknown sign *)
  in
  go body

(* ── Measure axioms (M-a): datatype model + recursion-equation preamble ───── *)
(* ctor name -> field sorts as the measure sees them (recursive self -> SData adt,
   type params / other ADTs -> opaque "Elem", Int/Bool concrete). *)
let ctor_field_sorts : (string, Smt.sort list) Hashtbl.t = Hashtbl.create 32
let adt_ctors : (string, string list) Hashtbl.t = Hashtbl.create 16
(* measures we soundly axiomatize: name -> its argument ADT name. *)
let axiom_measures : (string, string) Hashtbl.t = Hashtbl.create 16
let is_axiom_measure m = Hashtbl.mem axiom_measures m

(* Base-case ground values for axiom measures: name -> [(ctor_name, int_value)].
   Populated for arms whose body is a concrete integer (no recursion).
   Used to evaluate measures over concrete SMT terms without quantifier axioms,
   avoiding Z3 returning `unknown` for trivially SAT queries. *)
let measure_base_cases : (string, (string * int) list) Hashtbl.t = Hashtbl.create 8
let measure_preamble : string ref = ref ""

(* ctor name -> field names in declaration order.  Populated for TDRecord
   1-ctor datatypes; used to map EField/ERecord field names to selector indices. *)
let ctor_field_names : (string, string list) Hashtbl.t = Hashtbl.create 16

(* declare-datatypes preamble for TDRecord types; included in every VC that
   refines over a record value.  Built after measure_preamble so sort
   deduplication (measure_preamble_sorts) works. *)
let type_preamble : string ref = ref ""

(* ADT sort names already declared in measure_preamble; populated by
   build_measure_preamble so build_type_preamble can skip them and avoid
   duplicate sort declarations in the same VC (Z3 rejects those). *)
let measure_preamble_sorts : (string, unit) Hashtbl.t = Hashtbl.create 8

(* SMT sort name for a March ADT.  z3 reserves several sort names (`List`,
   `Array`, `Seq`, `Set`, …); keeping our datatype sorts in a private `M_`
   namespace guarantees no user/builtin ADT name collides with a reserved one.
   [adt_ctors] / [SData] are keyed by this safe name; constructors are not
   renamed. *)
let adt_sort_name (march_name : string) : string = "M_" ^ march_name

(* True when [t] is a bare TyCon that maps to a registered 1-constructor
   TDRecord sort — used to gate record-typed refinements on both the param
   and return sides. *)
let is_record_base (t : A.ty) : bool =
  match t with
  | A.TyCon ({ A.txt = name; _ }, []) ->
    (match Hashtbl.find_opt adt_ctors (adt_sort_name name) with
     | Some [ ctor ] -> Hashtbl.mem ctor_field_names ctor
     | _ -> false)
  | _ -> false

(* The SMT sort a measure sees for a constructor field: Int/Bool concrete, ANY
   registered ADT (self or another — so cross-ADT measure calls are well-sorted,
   M-c) its datatype sort, everything else (type params, unmodelled types) the
   opaque `Elem`.  Requires every ADT name already registered in [adt_ctors] —
   hence the two-pass registration (names, then field sorts). *)
let smt_sort_of_field (t : A.ty) : Smt.sort =
  match t with
  | A.TyCon ({ A.txt = "Int"; _ }, []) -> Smt.SInt
  | A.TyCon ({ A.txt = "Bool"; _ }, []) -> Smt.SBool
  | A.TyCon ({ A.txt; _ }, _) when Hashtbl.mem adt_ctors (adt_sort_name txt) ->
    Smt.SData (adt_sort_name txt)
  | _ -> Smt.SData "Elem"

(* Pass 1: register every ADT's constructor list (keyed by sort name). *)
let rec register_adt_names (decls : A.decl list) : unit =
  List.iter
    (function
      | A.DType (_, name, _, A.TDVariant variants, _)
      | A.DAlwaysLinearType (_, name, _, A.TDVariant variants, _) ->
        Hashtbl.replace adt_ctors (adt_sort_name name.A.txt)
          (List.map (fun (v : A.variant) -> v.A.var_name.A.txt) variants)
      | A.DType (_, name, _, A.TDRecord _, _)
      | A.DAlwaysLinearType (_, name, _, A.TDRecord _, _) ->
        Hashtbl.replace adt_ctors (adt_sort_name name.A.txt) [ name.A.txt ]
      | A.DMod (_, _, ds, _) -> register_adt_names ds
      | _ -> ())
    decls

(* Pass 2: register each constructor's field sorts (needs all names from pass 1). *)
let rec register_field_sorts (decls : A.decl list) : unit =
  List.iter
    (function
      | A.DType (_, _, _, A.TDVariant variants, _)
      | A.DAlwaysLinearType (_, _, _, A.TDVariant variants, _) ->
        List.iter
          (fun (v : A.variant) ->
            Hashtbl.replace ctor_field_sorts v.A.var_name.A.txt
              (List.map smt_sort_of_field v.A.var_args))
          variants
      | A.DType (_, name, _, A.TDRecord fields, _)
      | A.DAlwaysLinearType (_, name, _, A.TDRecord fields, _) ->
        let ctor = name.A.txt in
        Hashtbl.replace ctor_field_sorts ctor
          (List.map (fun (f : A.field) -> smt_sort_of_field f.A.fld_ty) fields);
        Hashtbl.replace ctor_field_names ctor
          (List.map (fun (f : A.field) -> f.A.fld_name.A.txt) fields)
      | A.DMod (_, _, ds, _) -> register_field_sorts ds
      | _ -> ())
    decls

(* The matched argument's name + its ADT, if the (first) parameter is a
   registered ADT. *)
let clause_param_adt (c : A.fn_clause) : (string * string) option =
  match c.A.fc_params with
  | A.FPNamed p :: _ -> (
      match p.A.param_ty with
      | Some (A.TyCon (adt, _)) when Hashtbl.mem adt_ctors (adt_sort_name adt.A.txt) ->
        Some (p.A.param_name.A.txt, adt_sort_name adt.A.txt)
      | _ -> None)
  | _ -> None

(* The (first) parameter's name, whatever its type (for the termination gate). *)
let clause_param_name (c : A.fn_clause) : string option =
  match c.A.fc_params with
  | (A.FPNamed p | A.FPDefault (p, _)) :: _ -> Some p.A.param_name.A.txt
  | _ -> None

let measure_param_adt (fd : A.fn_def) : (string * string) option =
  match fd.A.fn_clauses with c :: _ -> clause_param_adt c | [] -> None

let rec unblock = function
  | A.EBlock (es, sp) -> (match List.rev es with last :: _ -> unblock last | [] -> A.EBlock (es, sp))
  | e -> e

(* Extract `match param do Ctor(vars) -> body … end` arms (None if not that shape). *)
let measure_arms (param : string) (body : A.expr) : (string * string list * A.expr) list option =
  match unblock body with
  | A.EMatch (A.EVar { A.txt; _ }, branches, _) when txt = param -> (
      try
        Some
          (List.map
             (fun (br : A.branch) ->
               match br.A.branch_pat with
               | A.PatCon (ctor, pats) ->
                 (* Counter is per-arm so _w1/_w2/… are unique within an arm's
                    scope; cross-arm collisions are harmless (vars are per-arm). *)
                 let wildcard_ctr = ref 0 in
                 let vars =
                   List.map
                     (function
                       | A.PatVar n -> n.A.txt
                       | A.PatWild _ ->
                         incr wildcard_ctr;
                         Printf.sprintf "_w%d" !wildcard_ctr
                       | _ -> raise Exit)
                     pats
                 in
                 (ctor.A.txt, vars, br.A.branch_body)
               | _ -> raise Exit)
             branches)
      with Exit -> None)
  | _ -> None

(* Translate a measure arm body to SMT (function-app encoding): patvars -> Const,
   a measure call m(v) -> (m v) where m is the measure itself OR another
   axiomatisable measure ([allowed]) and v MUST be a bound patvar (a structurally
   smaller value).  Requiring a structural argument on EVERY measure call (self
   or cross — M-c) keeps the whole, possibly mutually-recursive, measure system
   structurally decreasing, hence total: axiomatising it is sound.  `len` and
   non-axiomatised measures are not [allowed], so an arm calling one stays
   untranslatable (symbolic fallback).  None => untranslatable. *)
let rec smt_of_axiom_body ~self ~allowed (bound : string list) (e : A.expr) : Smt.term option =
  let r = smt_of_axiom_body ~self ~allowed bound in
  match e with
  | A.ELit (A.LitInt n, _) -> Some (Smt.IntLit n)
  | A.EVar { A.txt; _ } when List.mem txt bound -> Some (Smt.Const txt)
  | A.EApp (A.EVar { A.txt = m; _ }, [ A.EVar { A.txt = v; _ } ], _)
    when (m = self || allowed m) && List.mem v bound ->
    Some (Smt.App (m, [ Smt.Const v ]))
  | A.EApp (A.EVar { A.txt = "+"; _ }, [ a; b ], _) ->
    (match r a, r b with Some x, Some y -> Some (Smt.Add (x, y)) | _ -> None)
  | A.EApp (A.EVar { A.txt = "-"; _ }, [ a; b ], _) ->
    (match r a, r b with Some x, Some y -> Some (Smt.Sub (x, y)) | _ -> None)
  | A.EApp (A.EVar { A.txt = "*"; _ }, [ A.ELit (A.LitInt k, _); b ], _) ->
    Option.map (fun y -> Smt.MulLit (k, y)) (r b)
  | _ -> None

(* All ADT sorts reachable from [seeds] through constructor fields, so a single
   `declare-datatypes` covers every sort an axiom mentions (handles cross-ADT
   references and mutually-recursive datatypes). *)
let adt_closure (seeds : string list) : string list =
  let seen = Hashtbl.create 16 in
  let rec visit a =
    if not (Hashtbl.mem seen a) then begin
      Hashtbl.replace seen a ();
      List.iter
        (fun c ->
          List.iter
            (function Smt.SData s when s <> "Elem" -> visit s | _ -> ())
            (try Hashtbl.find ctor_field_sorts c with Not_found -> []))
        (try Hashtbl.find adt_ctors a with Not_found -> [])
    end
  in
  List.iter visit seeds;
  Hashtbl.fold (fun a () acc -> a :: acc) seen []

let ctor_decl (c : string) : string =
  let sorts = try Hashtbl.find ctor_field_sorts c with Not_found -> [] in
  if sorts = [] then Printf.sprintf "(%s)" c
  else
    Printf.sprintf "(%s %s)" c
      (String.concat " "
         (List.mapi (fun i s -> Printf.sprintf "(%s_%d %s)" c i (Smt.string_of_sort s)) sorts))

(* One `declare-datatypes` declaring all [adts] sorts together (mutual recursion
   among them resolves within the single command). *)
let datatype_decls (adts : string list) : string =
  if adts = [] then ""
  else
    let sort_decls = String.concat " " (List.map (fun a -> Printf.sprintf "(%s 0)" a) adts) in
    let bodies =
      String.concat " "
        (List.map
           (fun a ->
             Printf.sprintf "(%s)"
               (String.concat " " (List.map ctor_decl (try Hashtbl.find adt_ctors a with Not_found -> []))))
           adts)
    in
    Printf.sprintf "(declare-datatypes (%s) (%s))" sort_decls bodies

(* The recursion-equation axiom for one arm of [name] (None if untranslatable). *)
let arm_axiom ~allowed (name : string) ((ctor, vars, body) : string * string list * A.expr) : string option =
  match smt_of_axiom_body ~self:name ~allowed vars body with
  | None -> None
  | Some bsmt ->
    let sorts = try Hashtbl.find ctor_field_sorts ctor with Not_found -> [] in
    if List.length vars <> List.length sorts then None
    else
      let lhs =
        if vars = [] then Printf.sprintf "(%s %s)" name ctor
        else Printf.sprintf "(%s (%s %s))" name ctor (String.concat " " vars)
      in
      if vars = [] then Some (Printf.sprintf "(assert (= %s %s))" lhs (Smt.render bsmt))
      else
        let bound =
          List.map2 (fun v s -> Printf.sprintf "(%s %s)" v (Smt.string_of_sort s)) vars sorts
        in
        Some
          (Printf.sprintf "(assert (forall (%s) (! (= %s %s) :pattern (%s))))"
             (String.concat " " bound) lhs (Smt.render bsmt) lhs)

(* Build the global measure-axiom preamble; populates [axiom_measures].

   A measure is axiomatised iff (a) its body is an exhaustive `match` on its ADT
   parameter (shape + totality) and (b) every arm translates — which, since a
   cross-measure call is only translatable when its callee is itself
   axiomatisable (M-c), is a mutual dependency.  We resolve it with a greatest
   fixpoint: start with every shape-OK measure as a candidate and drop any whose
   arms fail to translate against the current candidate set, until stable.  All
   `declare-fun`s are emitted before any axiom so cross-measure (incl. mutually
   recursive) references resolve. *)
let build_measure_preamble (mdefs : (string * A.fn_def) list) : unit =
  Hashtbl.reset axiom_measures;
  (* shape-OK measures: (name, param-ADT, arms), exhaustive match on the param. *)
  let shaped =
    List.filter_map
      (fun (name, fd) ->
        match measure_param_adt fd, fd.A.fn_clauses with
        | Some (param, adt), c :: _ -> (
          match measure_arms param c.A.fc_body with
          | Some arms ->
            let covered = List.sort compare (List.map (fun (c, _, _) -> c) arms) in
            let all = List.sort compare (try Hashtbl.find adt_ctors adt with Not_found -> []) in
            if covered = all && all <> [] then Some (name, adt, arms) else None
          | None -> None)
        | _ -> None)
      mdefs
  in
  let translates allowed (name, _, arms) =
    List.for_all (fun arm -> arm_axiom ~allowed name arm <> None) arms
  in
  let candidates = ref (List.map (fun (n, _, _) -> n) shaped) in
  let changed = ref true in
  while !changed do
    changed := false;
    List.iter
      (fun ((name, _, _) as s) ->
        if List.mem name !candidates && not (translates (fun m -> List.mem m !candidates) s)
        then begin
          candidates := List.filter (( <> ) name) !candidates;
          changed := true
        end)
      shaped
  done;
  let allowed m = List.mem m !candidates in
  let axiomatized = List.filter (fun (n, _, _) -> allowed n) shaped in
  List.iter (fun (name, adt, _) -> Hashtbl.replace axiom_measures name adt) axiomatized;
  Hashtbl.reset measure_base_cases;
  List.iter
    (fun (name, _, arms) ->
      let bases =
        List.filter_map
          (fun (ctor, _vars, body) ->
            (* A base case arm has a concrete-integer body.  We do not guard on
               vars=[] because wildcard arms (e.g. Leaf(_)) now produce generated
               names (_w1, …) in vars — but an ELit body is always variable-free
               regardless of how many wildcards appear in the pattern. *)
            match body with
            | A.ELit (A.LitInt n, _) -> Some (ctor, n)
            | _ -> None)
          arms
      in
      if bases <> [] then Hashtbl.replace measure_base_cases name bases)
    axiomatized;
  if axiomatized = [] then measure_preamble := ""
  else begin
    let buf = Buffer.create 256 in
    (* declare-funs first … *)
    List.iter
      (fun (name, adt, _) -> Buffer.add_string buf (Printf.sprintf "(declare-fun %s (%s) Int)\n" name adt))
      axiomatized;
    (* … then non-negativity axioms … *)
    List.iter
      (fun (name, adt, _) ->
        if is_nonneg_measure name then
          Buffer.add_string buf
            (Printf.sprintf "(assert (forall ((x %s)) (! (>= (%s x) 0) :pattern ((%s x)))))\n"
               adt name name))
      axiomatized;
    (* … then the recursion-equation axioms. *)
    List.iter
      (fun (name, _, arms) ->
        List.iter
          (fun arm -> match arm_axiom ~allowed name arm with Some s -> Buffer.add_string buf (s ^ "\n") | None -> ())
          arms)
      axiomatized;
    let covered = adt_closure (List.map (fun (_, adt, _) -> adt) axiomatized) in
    let dts = datatype_decls covered in
    measure_preamble := "(declare-sort Elem 0)\n" ^ dts ^ "\n" ^ Buffer.contents buf;
    Hashtbl.reset measure_preamble_sorts;
    List.iter (fun s -> Hashtbl.replace measure_preamble_sorts s ()) covered
  end

(* The built-in `List(a)` modelled as an ADT so user measures over lists are
   axiomatised exactly like user ADTs: `Nil | Cons(a, List(a))`, element opaque
   (`Elem`), tail recursive (`List`).  Seeded before user types so a user-defined
   `List` (unusual) still overrides. *)
let register_builtin_adts () : unit =
  Hashtbl.replace adt_ctors (adt_sort_name "List") [ "Nil"; "Cons" ];
  Hashtbl.replace ctor_field_sorts "Nil" [];
  Hashtbl.replace ctor_field_sorts "Cons" [ Smt.SData "Elem"; Smt.SData (adt_sort_name "List") ]

(* Build type_preamble from all registered TDRecord sorts, excluding any sorts
   already declared in measure_preamble (tracked in measure_preamble_sorts). *)
let build_type_preamble () : unit =
  let record_sorts =
    Hashtbl.fold
      (fun sort _ctors acc ->
        match Hashtbl.find_opt adt_ctors sort with
        | Some [ ctor ] when Hashtbl.mem ctor_field_names ctor -> sort :: acc
        | _ -> acc)
      adt_ctors []
  in
  if record_sorts = [] then type_preamble := ""
  else begin
    let all_sorts = adt_closure record_sorts in
    let new_sorts = List.filter (fun s -> not (Hashtbl.mem measure_preamble_sorts s)) all_sorts in
    if new_sorts = [] then type_preamble := ""
    else
      (* Only emit (declare-sort Elem 0) if measure_preamble doesn't already
         have it — the two preambles are concatenated in record_vc_preamble and
         a duplicate declaration causes a Z3 error inside the same push. *)
      let elem_decl = if !measure_preamble = "" then "(declare-sort Elem 0)\n" else "" in
      type_preamble := elem_decl ^ datatype_decls new_sorts
  end

(* All sorts needed for a record VC, WITHOUT measure axioms — used when all
   measure applications were evaluated concretely at the OCaml level.  Avoids
   the quantified forall axioms that cause Z3 to return `unknown` for SAT
   queries even when the goal no longer references any measure function. *)
let type_only_preamble () : string =
  let record_sorts =
    Hashtbl.fold
      (fun sort _ctors acc ->
        match Hashtbl.find_opt adt_ctors sort with
        | Some [ ctor ] when Hashtbl.mem ctor_field_names ctor -> sort :: acc
        | _ -> acc)
      adt_ctors []
  in
  if record_sorts = [] then ""
  else
    let all_sorts = adt_closure record_sorts in
    if all_sorts = [] then ""
    else
      (* Only emit `(declare-sort Elem 0)` when a sort in the closure actually
         uses Elem-typed fields (i.e. a List ADT is reachable).  Pure record
         types with no list fields don't need Elem and emitting it is harmless
         but inconsistent with build_type_preamble's deduplication logic. *)
      let needs_elem =
        List.exists
          (fun sort ->
            List.exists
              (fun ctor ->
                List.exists
                  (fun s -> s = Smt.SData "Elem")
                  (try Hashtbl.find ctor_field_sorts ctor with Not_found -> []))
              (try Hashtbl.find adt_ctors sort with Not_found -> []))
          all_sorts
      in
      (if needs_elem then "(declare-sort Elem 0)\n" else "") ^ datatype_decls all_sorts

let record_vc_preamble () : string =
  match !measure_preamble, !type_preamble with
  | "", t -> t
  | m, "" -> m
  | m, t -> m ^ "\n" ^ t

(* ── M-b: the @[measure] soundness gate ─────────────────────────────────────
   `@[measure]` is a promise that the function is a TOTAL, TERMINATING, PURE
   mathematical function.  The axiom encoding trusts that promise: axiomatising a
   partial / non-terminating / effectful "measure" makes the SMT context
   inconsistent, from which the solver can prove ANYTHING — silent unsoundness,
   the worst failure mode.  So breaking the promise is a HARD compile error, not
   a silent fallback: a user relying on the measure in a predicate deserves to
   know it cannot be trusted.

   The checks are conservative syntactic over-approximations.  A measure that is
   sound but merely outside the v1 axiom *encoding* fragment (multi-argument,
   element-inspecting, `let`-bodied) is NOT an error — it falls back to a sound
   symbolic reflection.  Only the three soundness properties are gated. *)

(* Immediate sub-expressions, for a structure-agnostic traversal. *)
let children : A.expr -> A.expr list = function
  | A.ELit _ | A.EVar _ | A.EHole _ | A.EResultRef _ | A.EDbg (None, _) -> []
  | A.EApp (f, args, _) -> f :: args
  | A.ECon (_, args, _) | A.EAtom (_, args, _) | A.ETuple (args, _) -> args
  | A.ELam (_, b, _) | A.ELetFn (_, _, _, b, _) -> [ b ]
  | A.EBlock (es, _) -> es
  | A.ELet (b, _) -> [ b.A.bind_expr ]
  | A.EMatch (s, brs, _) ->
    s
    :: List.concat_map
         (fun (br : A.branch) ->
           (match br.A.branch_guard with Some g -> [ g ] | None -> []) @ [ br.A.branch_body ])
         brs
  | A.ERecord (fs, _) -> List.map snd fs
  | A.ERecordUpdate (r, fs, _) -> r :: List.map snd fs
  | A.EField (r, _, _) -> [ r ]
  | A.EIf (c, t, e, _) -> [ c; t; e ]
  | A.ECond (arms, _) -> List.concat_map (fun (c, b) -> [ c; b ]) arms
  | A.EPipe (a, b, _) -> [ a; b ]
  | A.EAnnot (e, _, _) | A.ESpawn (e, _) | A.EAssert (e, _) | A.ESigil (_, e, _)
  | A.EDbg (Some e, _) -> [ e ]
  | A.ESend (a, b, _) -> [ a; b ]
  | A.ELetQ (_, e1, e2, _) -> [ e1; e2 ]

let rec iter_all (f : A.expr -> unit) (e : A.expr) : unit =
  f e;
  List.iter (iter_all f) (children e)

(* Variables structurally smaller than [param]: bound by a constructor pattern
   when matching [param] (or an already-structural variable, so a nested
   `match l do …` contributes l's components too).  Accumulated top-down. *)
let structural_subvars (param : string) (body : A.expr) : (string, unit) Hashtbl.t =
  let set = Hashtbl.create 16 in
  let is_struct v = v = param || Hashtbl.mem set v in
  let rec pat_vars = function
    | A.PatVar n -> [ n.A.txt ]
    | A.PatCon (_, ps) | A.PatAtom (_, ps, _) | A.PatTuple (ps, _) -> List.concat_map pat_vars ps
    | A.PatAs (p, n, _) -> n.A.txt :: pat_vars p
    | A.PatRecord (fs, _) -> List.concat_map (fun (_, p) -> pat_vars p) fs
    | A.PatOr (ps, _) -> List.concat_map pat_vars ps
    | A.PatWild _ | A.PatLit _ -> []
  in
  iter_all
    (fun e ->
      match e with
      | A.EMatch (A.EVar s, brs, _) when is_struct s.A.txt ->
        List.iter
          (fun (br : A.branch) ->
            match br.A.branch_pat with
            | A.PatCon (_, pats) ->
              List.iter (fun v -> Hashtbl.replace set v ()) (List.concat_map pat_vars pats)
            | _ -> ())
          brs
      | _ -> ())
    body;
  set

(* Builtins that diverge or abort: a body calling one is not a total function. *)
let measure_partial_calls =
  [ "panic"; "panic_"; "todo"; "todo_"; "unreachable"; "unreachable_"; "exit" ]

(* Gate violations of a `@[measure]`, as human-readable predicate clauses. *)
let measure_gate_errors (fd : A.fn_def) : string list =
  let self = fd.A.fn_name.A.txt in
  let errs = ref [] in
  let add m = if not (List.mem m !errs) then errs := m :: !errs in
  List.iter
    (fun (c : A.fn_clause) ->
      let body = c.A.fc_body in
      (* (1) Purity & totality of operations. *)
      iter_all
        (fun e ->
          match e with
          | A.ESpawn _ -> add "must be pure (it spawns an actor)"
          | A.ESend _ -> add "must be pure (it sends a message)"
          | A.EDbg _ -> add "must be pure (it uses a `dbg` expression)"
          | A.EAssert _ -> add "must be total (an `assert` can abort)"
          | A.EApp (A.EVar { A.txt; _ }, _, _) when List.mem txt measure_partial_calls ->
            add (Printf.sprintf "must be total (it calls `%s`, which does not return)" txt)
          | A.EApp (A.EVar { A.txt = ("/" | "%") as op; _ }, [ _; d ], _) -> (
            match d with
            | A.ELit (A.LitInt n, _) when n <> 0 -> ()
            | _ -> add (Printf.sprintf "must be total (`%s` can divide by zero)" op))
          | _ -> ())
        body;
      (* (2) Termination via structural recursion. *)
      (match clause_param_name c with
       | Some param ->
         let sset = structural_subvars param body in
         iter_all
           (fun e ->
             match e with
             | A.EApp (A.EVar { A.txt; _ }, args, _) when txt = self -> (
               match args with
               | [ A.EVar v ] when Hashtbl.mem sset v.A.txt -> ()
               | _ ->
                 add
                   "is not structurally recursive (every recursive call must be on a \
                    component of the matched parameter)")
             | _ -> ())
           body
       | None ->
         iter_all
           (fun e ->
             match e with
             | A.EApp (A.EVar { A.txt; _ }, _, _) when txt = self ->
               add
                 "cannot be shown to terminate (a recursive @[measure] must take an ADT \
                  parameter and recurse on its components)"
             | _ -> ())
           body);
      (* (3) Totality via an exhaustive match on the ADT parameter. *)
      match clause_param_adt c with
      | Some (param, adt) -> (
        match measure_arms param body with
        | Some arms ->
          let covered = List.map (fun (ctor, _, _) -> ctor) arms in
          let all = try Hashtbl.find adt_ctors adt with Not_found -> [] in
          let missing = List.filter (fun ctor -> not (List.mem ctor covered)) all in
          if all <> [] && missing <> [] then
            add
              (Printf.sprintf "must be total (its `match` does not cover %s)"
                 (String.concat ", " missing))
        | None -> ())
      | None -> ())
    fd.A.fn_clauses;
  List.rev !errs

(* ── Translate the decidable predicate fragment to an SMT term ────────────── *)
(* [resolve_var] maps a scalar variable to its SMT term; [resolve_measure]
   maps a (measure-name, argument-name) to its measure term.  None => outside
   the supported Int/Bool linear fragment. *)
let rec smt_of ~resolve_var ~resolve_measure ?(resolve_field = fun _ _ -> None)
    ?(resolve_measure_app = fun _ _ -> None) (e : A.expr) : Smt.term option =
  let r = smt_of ~resolve_var ~resolve_measure ~resolve_field ~resolve_measure_app in
  let b2 f a b = match r a, r b with Some x, Some y -> Some (f x y) | _ -> None in
  match e with
  | A.ELit (A.LitInt n, _) -> Some (Smt.IntLit n)
  | A.ELit (A.LitBool b, _) -> Some (Smt.BoolLit b)
  (* A measure application m(e): m(var) reflects to a consistent measure symbol;
     m(expr) is evaluated via resolve_measure_app (e.g. concrete_len for a list);
     len(list-literal) is computed concretely without needing resolve_measure_app. *)
  | A.EApp (A.EVar { A.txt = m; _ }, [ a ], _) when is_measure m ->
    (match a with
     | A.EVar { A.txt = x; _ } -> resolve_measure m x
     | _ ->
       (match if m = "len" then list_len a else None with
        | Some n -> Some (Smt.IntLit n)
        | None ->
          (match r a with
           | Some arg_term -> resolve_measure_app m arg_term
           | None -> None)))
  | A.EVar { A.txt; _ } -> resolve_var txt
  (* Zero/multi-arity constructors: Nil → App("Nil",[]), Cons(h,t) → App("Cons",[h,t]).
     Only constructors registered in ctor_field_sorts are handled (builtins + user ADTs). *)
  | A.ECon ({ A.txt = ctor; _ }, args, _) when Hashtbl.mem ctor_field_sorts ctor ->
    let reflected = List.map r args in
    if List.for_all Option.is_some reflected then
      Some (Smt.App (ctor, List.filter_map Fun.id reflected))
    else None
  (* Field access on a bare variable: s.count → selector applied to s.
     Only EVar receivers are supported; complex receivers conservatively return
     None — safe under the definite-failure soundness stance. *)
  | A.EField (A.EVar { A.txt = x; _ }, { A.txt = fname; _ }, _) -> resolve_field x fname
  | A.EApp (A.EVar { A.txt = "&&"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.And (x, y)) a b
  | A.EApp (A.EVar { A.txt = "||"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Or (x, y)) a b
  | A.EApp (A.EVar { A.txt = "not"; _ }, [ a ], _) -> Option.map (fun x -> Smt.Not x) (r a)
  | A.EApp (A.EVar { A.txt = ">="; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Ge (x, y)) a b
  | A.EApp (A.EVar { A.txt = "<="; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Le (x, y)) a b
  | A.EApp (A.EVar { A.txt = ">"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Gt (x, y)) a b
  | A.EApp (A.EVar { A.txt = "<"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Lt (x, y)) a b
  | A.EApp (A.EVar { A.txt = "=="; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Eq (x, y)) a b
  | A.EApp (A.EVar { A.txt = "!="; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Ne (x, y)) a b
  | A.EApp (A.EVar { A.txt = "+"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Add (x, y)) a b
  | A.EApp (A.EVar { A.txt = "-"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Sub (x, y)) a b
  | A.EApp (A.EVar { A.txt = "negate"; _ }, [ a ], _) -> Option.map (fun x -> Smt.Neg x) (r a)
  | A.EApp (A.EVar { A.txt = "*"; _ }, [ a; b ], _) ->
    (match a, b with
     | A.ELit (A.LitInt k, _), _ -> Option.map (fun y -> Smt.MulLit (k, y)) (r b)
     | _, A.ELit (A.LitInt k, _) -> Option.map (fun x -> Smt.MulLit (k, x)) (r a)
     | _ -> None)
  | _ -> None

(* User-facing infix rendering of a predicate (best-effort). *)
let rec pred_str (e : A.expr) : string =
  let binop op a b = pred_str a ^ " " ^ op ^ " " ^ pred_str b in
  match e with
  | A.ELit (A.LitInt n, _) -> string_of_int n
  | A.ELit (A.LitBool b, _) -> if b then "true" else "false"
  | A.EApp (A.EVar { A.txt = m; _ }, [ a ], _) when is_measure m -> m ^ "(" ^ pred_str a ^ ")"
  | A.EVar { A.txt; _ } -> txt
  | A.EField (recv, { A.txt = fname; _ }, _) -> pred_str recv ^ "." ^ fname
  | A.EApp (A.EVar { A.txt = ("&&" | "||" | ">=" | "<=" | ">" | "<" | "==" | "!=" | "+" | "-" | "*") as op; _ }, [ a; b ], _) ->
    binop op a b
  | A.EApp (A.EVar { A.txt = "not"; _ }, [ a ], _) -> "!" ^ pred_str a
  | A.EApp (A.EVar { A.txt = "negate"; _ }, [ a ], _) -> "-" ^ pred_str a
  | _ -> "<predicate>"

(* Split a rendered S-expression string into its top-level tokens,
   respecting nested parentheses.  "1 (as nil (List Int))" → ["1";"(as nil (List Int))"] *)
let sexp_tokens (s : string) : string list =
  let n = String.length s in
  let depth = ref 0 in
  let start = ref 0 in
  let acc = ref [] in
  for i = 0 to n - 1 do
    (match s.[i] with
     | '(' -> incr depth
     | ')' -> decr depth
     | ' ' when !depth = 0 ->
       if i > !start then
         acc := String.sub s !start (i - !start) :: !acc;
       start := i + 1
     | _ -> ())
  done;
  if !start < n then acc := String.sub s !start (n - !start) :: !acc;
  List.rev !acc

(* Pretty-print an SMT value string for human-readable counterexamples.
   "(RawRecord 1)" → "{ count: 1 }" when ctor_field_names["RawRecord"] = ["count"].
   "(as nil ...)" → "[]".  Falls back to the raw string for unknown shapes. *)
let rec pretty_smt_value (v : string) : string =
  let n = String.length v in
  if n >= 2 && v.[0] = '(' && v.[n - 1] = ')' then begin
    let inner = String.sub v 1 (n - 2) in
    match sexp_tokens inner with
    | "as" :: "nil" :: _ -> "[]"
    | ctor :: args ->
      (match Hashtbl.find_opt ctor_field_names ctor with
       | Some fields when List.length fields = List.length args ->
         "{ " ^ String.concat ", "
           (List.map2 (fun f a -> f ^ ": " ^ pretty_smt_value a) fields args) ^ " }"
       | _ -> v)
    | _ -> v
  end else v

(* Render one model entry: "m(x) = v" for measure symbols, "k = v" otherwise. *)
let render_model_entry (k, v) : string =
  let v' = pretty_smt_value v in
  match String.index_opt k '$' with
  | Some i ->
    Printf.sprintf "%s(%s) = %s"
      (String.sub k 0 i) (String.sub k (i + 1) (String.length k - i - 1)) v'
  | None -> Printf.sprintf "%s = %s" k v'

(* Inline counterexample suffix for call-site errors (e.g. precondition checks).
   Returns "" when the model is empty. *)
let format_cx (model : (string * string) list) : string =
  if model = [] then ""
  else " (e.g. " ^ String.concat ", " (List.map render_model_entry model) ^ ")"

(* Multi-line counterexample block for return-type constraint errors. Returns "" when empty. *)
let cx_block (model : (string * string) list) : string =
  if model = [] then ""
  else
    "\n\nA counterexample was found:\n\n    " ^
    String.concat "\n    " (List.map render_model_entry model)

let model_of = function Refine.Refuted m -> m | _ -> []

(* ── Scope of refined locals/params: name -> (binder, predicate) ─────────── *)
type scope = (string * (string * A.expr * string option)) list

let refined_int_ty : A.ty option -> (string * A.expr) option = function
  | Some (A.TyRefine (base, binder, pred)) when is_int_base base ->
    Some (binder_name binder, pred)
  | _ -> None

(* Like refined_int_ty but also admits record TyCon params.
   Returns (binder, pred, sort_opt) where sort_opt = Some "M_…" for record params. *)
let refined_scope_ty : A.ty option -> (string * A.expr * string option) option = function
  | Some (A.TyRefine (base, binder, pred)) when is_int_base base ->
    Some (binder_name binder, pred, None)
  | Some (A.TyRefine ((A.TyCon ({ A.txt = name; _ }, []) as base), binder, pred))
    when is_record_base base ->
    Some (binder_name binder, pred, Some (adt_sort_name name))
  | _ -> None

let scope_add_param (sc : scope) (p : A.param) : scope =
  match refined_scope_ty p.A.param_ty with
  | Some r -> (p.A.param_name.A.txt, r) :: sc
  | None -> sc

let scope_add_fnparam (sc : scope) : A.fn_param -> scope = function
  | A.FPNamed p | A.FPDefault (p, _) -> scope_add_param sc p
  | A.FPPat _ -> sc

let scope_add_binding (sc : scope) (b : A.binding) : scope =
  match b.A.bind_pat, refined_scope_ty b.A.bind_ty with
  | A.PatVar n, Some r -> (n.A.txt, r) :: sc
  | _ -> sc

(* ── Collect signatures, keyed by bare + qualified name ──────────────────── *)
let param_name_of : A.fn_param -> string = function
  | A.FPNamed p | A.FPDefault (p, _) -> p.A.param_name.A.txt
  | A.FPPat _ -> "_"

let sig_of_clause (c : A.fn_clause) : fn_sig =
  let param_names = List.map param_name_of c.A.fc_params in
  let refined =
    List.mapi (fun idx fp -> (idx, fp)) c.A.fc_params
    |> List.filter_map (fun (idx, fp) ->
           match fp with
           | A.FPNamed p | A.FPDefault (p, _) ->
             (match refined_int_ty p.A.param_ty with
              | Some (binder, pred) -> Some { idx; binder; pred }
              | None -> None)
           | A.FPPat _ -> None)
  in
  { param_names; refined }

(* Every function definition keyed by its fully-qualified name (e.g. "A.B.foo"),
   mapping to Some sig when it carries a refinement, None when it does not.
   Recording NON-refined defs too is essential for correct lexical resolution: a
   bare call that resolves to a non-refined sibling must NOT fall through to a
   refined function of the same name in an enclosing module — that would check
   the wrong predicate (a false positive). *)
let collect_all_defs (decls : A.decl list) : (string, fn_sig option) Hashtbl.t =
  let tbl = Hashtbl.create 128 in
  let rec go prefix decls =
    List.iter
      (function
        | A.DFn (fd, _) ->
          let key = if prefix = "" then fd.A.fn_name.A.txt else prefix ^ "." ^ fd.A.fn_name.A.txt in
          let sg =
            match fd.A.fn_clauses with c :: _ -> sig_of_clause c | [] -> { param_names = []; refined = [] }
          in
          Hashtbl.replace tbl key (if sg.refined <> [] then Some sg else None)
        | A.DMod (name, _, ds, _) ->
          go (if prefix = "" then name.A.txt else prefix ^ "." ^ name.A.txt) ds
        | _ -> ())
      decls
  in
  go "" decls;
  tbl

(* ── Use/alias-aware call resolution ───────────────────────────────────────
   Resolve a call name the way the typechecker does: a bare name binds to the
   nearest enclosing module that defines it (lexical scope, with shadowing); an
   alias-qualified name (`alias X.Y as P` → `P.foo`) expands to the original; a
   `use`-imported bare name binds to the exporting module.  This replaces the
   previous "qualified key OR globally-unique bare name" matching, which dropped
   sibling calls on any cross-module name collision and never resolved aliased or
   `use`-imported names. *)
let dotted (path : A.name list) : string = String.concat "." (List.map (fun n -> n.A.txt) path)

type rctx = {
  modpath : string;                       (* enclosing module prefix, "" at top *)
  aliases : (string * string) list;       (* (alias short, original dotted prefix) *)
  uses : (string * A.use_selector) list;  (* (exporting module dotted, selector) *)
}

let rctx0 = { modpath = ""; aliases = []; uses = [] }

(* Enclosing-module prefixes of [mp], innermost first: "A.B" -> ["A.B"; "A"; ""]. *)
let modpath_prefixes (mp : string) : string list =
  let segs = if mp = "" then [] else String.split_on_char '.' mp in
  let n = List.length segs in
  List.init (n + 1) (fun i -> String.concat "." (List.filteri (fun j _ -> j < n - i) segs))

(* Resolve a call name to a definition:
     Some (Some sig) -> a refined function (check it)
     Some None       -> a real but non-refined function (skip — no predicate)
     None            -> unresolved / external (skip)
   Only Some (Some sig) leads to a check, so a wrong resolution can at worst
   *skip* — it can never check against the wrong predicate. *)
let resolve_call (ctx : rctx) (defs : (string, fn_sig option) Hashtbl.t) (fname : string)
  : fn_sig option option =
  let lookup k = Hashtbl.find_opt defs k in
  let qualify p n = if p = "" then n else p ^ "." ^ n in
  (* 1. Lexical scope: the nearest enclosing module that defines [fname] wins
        (shadowing any same-named function further out). *)
  match List.find_map (fun p -> lookup (qualify p fname)) (modpath_prefixes ctx.modpath) with
  | Some r -> Some r
  | None ->
    (* 2. Alias-qualified `P.rest` with `alias X.Y as P` -> `X.Y.rest`. *)
    let aliased =
      match String.index_opt fname '.' with
      | Some i ->
        let head = String.sub fname 0 i in
        let rest = String.sub fname (i + 1) (String.length fname - i - 1) in
        (match List.assoc_opt head ctx.aliases with Some orig -> lookup (orig ^ "." ^ rest) | None -> None)
      | None -> None
    in
    (match aliased with
     | Some r -> Some r
     | None ->
       (* 3. `use`-imported bare name. *)
       if String.contains fname '.' then None
       else
         List.find_map
           (fun (m, sel) ->
             let imported =
               match sel with
               | A.UseAll -> true
               | A.UseNames ns -> List.exists (fun (n : A.name) -> n.A.txt = fname) ns
               | A.UseExcept ns -> not (List.exists (fun (n : A.name) -> n.A.txt = fname) ns)
               | A.UseSingle -> false
             in
             if imported then lookup (qualify m fname) else None)
           ctx.uses)

(* ── Reflect a scalar actual argument into (term, decls, assumptions) ─────── *)
let reflect_scalar (sc : scope) (actual : A.expr)
  : (Smt.term * (string * Smt.sort) list * Smt.term list) option =
  match actual with
  | A.EVar { A.txt = x; _ } ->
    let xc = Smt.Const x in
    (match List.assoc_opt x sc with
     | Some (b, q, None) ->
       (* A refined local (Int): carry its own refinement as an assumption. *)
       let rv n = if n = b || n = "_" then Some xc else None in
       let assumptions =
         match smt_of ~resolve_var:rv ~resolve_measure:(fun _ _ -> None) q with
         | Some qa -> [ qa ]
         | None -> []
       in
       Some (xc, [ (x, Smt.SInt) ], assumptions)
     | Some _ | None ->
       (* An ordinary variable: reflect it as a constant so a path-context
          guard about it can constrain it.  Without a guard it stays
          unconstrained and the definite-failure check keeps us silent. *)
       Some (xc, [ (x, Smt.SInt) ], []))
  | _ ->
    (match smt_of ~resolve_var:(fun _ -> None) ~resolve_measure:(fun _ _ -> None) actual with
     | Some t -> Some (t, [], [])
     | None -> None)

(* ── Check one refined parameter at a call site ──────────────────────────── *)
(* [path] is the path context: conditions known true here, each tagged with
   whether it is negated (the else-branch of an `if`). *)
let check_call ~root errctx ~span (sg : fn_sig) (args : A.expr list)
    (path : (A.expr * bool) list) (rp : rparam) (sc : scope) : unit =
  let name_pos = List.mapi (fun i n -> (n, i)) sg.param_names in
  let actual_of_name name =
    match List.assoc_opt name name_pos with
    | Some i -> List.nth_opt args i
    | None -> None
  in
  match List.nth_opt args rp.idx with
  | None -> ()
  | Some self_actual ->
    let decls = ref [] and assume = ref [] in
    (* Attach the (expensive) datatype/quantifier preamble ONLY to VCs that
       actually reference an axiomatised measure; a plain Int/Bool VC pays no
       axiom cost.  Set when [resolve_measure] reflects an axiom measure. *)
    let uses_axiom = ref false in
    let absorb = function
      | Some (t, d, a) -> decls := d @ !decls; assume := a @ !assume; Some t
      | None -> None
    in
    (* Resolve a scalar variable.  A predicate references callee parameters;
       a path condition references caller variables — both go through the
       actual caller values so the names line up in SMT. *)
    let resolve_var name =
      if name = rp.binder || name = "_" then absorb (reflect_scalar sc self_actual)
      else
        match actual_of_name name with
        | Some a -> absorb (reflect_scalar sc a)
        | None ->
          (* a caller-scope variable from the path context *)
          decls := (name, Smt.SInt) :: !decls;
          Some (Smt.Const name)
    in
    let measure_of_var m x =
      let c = Smt.Const (m ^ "$" ^ x) in
      decls := (m ^ "$" ^ x, Smt.SInt) :: !decls;
      (* `len` is known non-negative; user measures get no axiom in v1 (sound;
         guarded uses still discharge via the path context). *)
      if is_nonneg_measure m then assume := Smt.Ge (c, Smt.IntLit 0) :: !assume;
      Some c
    in
    (* Reflect a value into the SMT datatype term an axiomatised measure ranges
       over: a constructor application becomes (ctor …) (so the recursion axioms
       fire); a variable becomes a fresh datatype constant. *)
    let dt_counter = ref 0 in
    let rec reflect_dt adt e =
      match e with
      | A.ECon (ctor, args, _)
        when (match Hashtbl.find_opt adt_ctors adt with Some cs -> List.mem ctor.A.txt cs | None -> false) ->
        let sorts = try Hashtbl.find ctor_field_sorts ctor.A.txt with Not_found -> [] in
        if List.length args <> List.length sorts then None
        else
          List.fold_right2
            (fun a s acc ->
              match reflect_field a s, acc with Some t, Some ts -> Some (t :: ts) | _ -> None)
            args sorts (Some [])
          |> Option.map (fun ts -> Smt.App (ctor.A.txt, ts))
      | A.EVar { A.txt = x; _ } -> decls := (x, Smt.SData adt) :: !decls; Some (Smt.Const x)
      | _ -> None
    and reflect_field a = function
      | Smt.SData sub when sub <> "Elem" -> reflect_dt sub a
      | sort ->
        (* element / Int field: irrelevant to a structural measure -> fresh const *)
        incr dt_counter;
        let nm = Printf.sprintf "_e%d" !dt_counter in
        decls := (nm, sort) :: !decls;
        Some (Smt.Const nm)
    in
    let resolve_measure m name =
      if is_axiom_measure m then (
        uses_axiom := true;
        let adt = Hashtbl.find axiom_measures m in
        match actual_of_name name with
        | None ->
          decls := (name, Smt.SData adt) :: !decls;
          Some (Smt.App (m, [ Smt.Const name ]))
        | Some a -> Option.map (fun t -> Smt.App (m, [ t ])) (reflect_dt adt a))
      else
        match actual_of_name name with
        | Some a -> (
            match (if m = "len" then list_len a else None) with
            | Some n -> Some (Smt.IntLit n)
            | None -> (match a with A.EVar { A.txt = x; _ } -> measure_of_var m x | _ -> None))
        | None -> measure_of_var m name (* a caller-scope variable *)
    in
    (* Translate the path conditions into assumptions (dropping any that fall
       outside the supported fragment — sound, just weaker). *)
    List.iter
      (fun (cond, negated) ->
        match smt_of ~resolve_var ~resolve_measure cond with
        | Some t -> assume := (if negated then Smt.Not t else t) :: !assume
        | None -> ())
      path;
    (match smt_of ~resolve_var ~resolve_measure rp.pred with
     | None -> ()
     | Some goal ->
       (* de-duplicate decls (a symbol may be requested twice) *)
       let decls =
         List.fold_left
           (fun acc d -> if List.mem d acc then acc else d :: acc)
           [] !decls
       in
       let vc = { Smt.decls; assumptions = !assume; goal } in
       let preamble = if !uses_axiom then !measure_preamble else "" in
       (* Report a violation ONLY when the precondition can *never* hold under
          the assumptions (a definite failure).  If it merely *might* fail
          (e.g. a symbolic, unknown length), that is unprovable either way and
          we stay silent — no false positives.

          - discharge(goal=G) Verified  => G always holds        => pass
          - else discharge(goal=¬G) Verified => G never holds     => violation
          - otherwise (G depends on unknowns / solver unsure)     => skip *)
       (match Refine.discharge ~root ~preamble vc with
        | Refine.Verified -> ()
        | first ->
          (match Refine.discharge ~root ~preamble { vc with Smt.goal = Smt.Not goal } with
           | Refine.Verified ->
             Err.error errctx ~span
               (Printf.sprintf
                  "refinement violation: argument does not satisfy precondition `%s`%s\n\
                   note: guard the call (e.g. `if %s do …`) or pass a value known to satisfy it"
                  (pred_str rp.pred) (format_cx (model_of first)) (pred_str rp.pred))
           | _ -> ())))

(* ── Postconditions: a function's return value must satisfy its return
   refinement.  We check each *tail* expression (a return position) under the
   path/scope reaching it, with the same definite-failure soundness stance. ── *)

let return_refine (fd : A.fn_def) : (string * A.expr) option =
  match fd.A.fn_ret_ty with
  | Some (A.TyRefine (base, binder, pred)) when is_int_base base ->
    Some (binder_name binder, pred)
  | _ -> None

(* Like return_refine but also returns the SMT sort name when the return base
   type is a registered TDRecord, enabling EField reflection in check_post. *)
let return_refine_ext (fd : A.fn_def) : (string * A.expr * string option) option =
  match fd.A.fn_ret_ty with
  | Some (A.TyRefine (base, binder, pred)) when is_int_base base ->
    Some (binder_name binder, pred, None)
  | Some (A.TyRefine (A.TyCon ({ A.txt = name; _ }, []) as base, binder, pred))
    when is_record_base base ->
    Some (binder_name binder, pred, Some (adt_sort_name name))
  | _ -> None

(* Return-position expressions of a body, each with the path reaching it. *)
let rec tails (path : (A.expr * bool) list) (e : A.expr) : ((A.expr * bool) list * A.expr) list =
  match e with
  | A.EBlock (es, _) -> (match List.rev es with last :: _ -> tails path last | [] -> [ (path, e) ])
  | A.EIf (c, t, el, _) -> tails ((c, false) :: path) t @ tails ((c, true) :: path) el
  | A.ECond (arms, _) -> List.concat_map (fun (c, b) -> tails ((c, false) :: path) b) arms
  | A.EMatch (_, branches, _) ->
    List.concat_map
      (fun (br : A.branch) ->
        let p = match br.A.branch_guard with Some g -> (g, false) :: path | None -> path in
        tails p br.A.branch_body)
      branches
  | _ -> [ (path, e) ]

(* Build a resolve_field closure for a known record binder: v.fname becomes the
   SMT selector applied to the term representing v. *)
let make_field_resolver (binder : string) (sort_name : string) (binder_term : Smt.term)
    : string -> string -> Smt.term option =
  fun varname fname ->
    if varname <> binder && varname <> "_" then None
    else
      match Hashtbl.find_opt adt_ctors sort_name with
      | Some [ ctor ] ->
        (match Hashtbl.find_opt ctor_field_names ctor with
         | None -> None
         | Some names ->
           let rec find_idx i = function
             | [] -> None
             | n :: _ when n = fname -> Some i
             | _ :: rest -> find_idx (i + 1) rest
           in
           (match find_idx 0 names with
            | None -> None
            | Some idx ->
              Some (Smt.App (Printf.sprintf "%s_%d" ctor idx, [ binder_term ]))))
      | _ -> None

(* Facts true throughout the body: each refined param contributes its predicate. *)
(* Returns (decls, assumptions, has_record).
   Int entries: declare an SInt const, reflect predicate over it.
   Record entries: declare a datatype const (SData sort_name), reflect the
   predicate with a field resolver so `s.field` becomes the SMT selector
   applied to the opaque const.  `has_record` is true when any record entry
   is present — signals check_post to include the datatype preamble. *)
let scope_facts (sc : scope) : (string * Smt.sort) list * Smt.term list * bool =
  List.fold_left
    (fun (ds, asm, has_rec) (name, (b, q, sort)) ->
      match sort with
      | None ->
        let c = Smt.Const name in
        let rv n = if n = b || n = "_" then Some c else Some (Smt.Const n) in
        let ds = (name, Smt.SInt) :: ds in
        (match smt_of ~resolve_var:rv ~resolve_measure:(fun _ _ -> None) q with
         | Some qa -> (ds, qa :: asm, has_rec)
         | None -> (ds, asm, has_rec))
      | Some sort_name ->
        let c = Smt.Const name in
        let ds = (name, Smt.SData sort_name) :: ds in
        let rv n = if n = b || n = "_" then Some c else Some (Smt.Const n) in
        let rf = make_field_resolver b sort_name c in
        let rma m arg =
          if is_axiom_measure m then Some (Smt.App (m, [ arg ])) else None
        in
        (match smt_of ~resolve_var:rv ~resolve_measure:(fun _ _ -> None)
                 ~resolve_field:rf ~resolve_measure_app:rma q with
         | Some qa -> (ds, qa :: asm, true)
         (* Predicate untranslatable: declare the const but don't set has_rec.
            Without a loaded assumption, scope_has_record would trigger the
            "SAT = definite error" path with an unconstrained cex — unsound. *)
         | None -> (ds, asm, has_rec)))
    ([], [], false) sc

(* Evaluate a field-selector application on a concrete constructor term.
   <ctor>_<idx>(App(ctor, args)) → args[idx] — enables concrete len evaluation
   through record field projections like State_1(State(1, Nil)) → Nil. *)
let rec selector_reduce (term : Smt.term) : Smt.term =
  match term with
  | Smt.App (selector, [ (Smt.App (ctor, args) as inner) ]) ->
    let prefix = ctor ^ "_" in
    let plen = String.length prefix in
    if String.length selector > plen && String.sub selector 0 plen = prefix then
      match int_of_string_opt (String.sub selector plen (String.length selector - plen)) with
      | Some idx when idx >= 0 && idx < List.length args -> selector_reduce (List.nth args idx)
      | _ -> Smt.App (selector, [ inner ])
    else Smt.App (selector, [ inner ])
  | other -> other

(* Evaluate `len` on a concrete SMT list term (Nil / Cons / selector chain).
   Returns None for opaque (variable/unknown) terms — avoids quantifier-based
   axioms that would cause Z3 to return `unknown` instead of sat/unsat. *)
let rec concrete_len (term : Smt.term) : int option =
  match selector_reduce term with
  | Smt.App ("Nil", []) -> Some 0
  | Smt.App ("Cons", [ _h; t ]) -> Option.map (( + ) 1) (concrete_len t)
  | _ -> None

(* Try to evaluate an axiom measure on a concrete SMT term.
   Uses selector_reduce to unfold record projections, then matches the
   constructor against known base cases (measure_base_cases).  For
   inductive cases we recurse up to a depth limit to avoid loops.
   Returns None if the term is opaque, not a base case, or too deep. *)
let concrete_measure_app (name : string) (arg_term : Smt.term) : int option =
  match Hashtbl.find_opt measure_base_cases name with
  | None -> None
  | Some bases ->
    let go term =
      match selector_reduce term with
        | Smt.App (ctor, []) ->
          (* Zero-arg constructor: look up in base cases *)
          List.assoc_opt ctor bases
        | Smt.App (_ctor, _args) ->
          (* Multi-arg constructor: not a base case for simple measures;
             would need the step case — give up for now *)
          None
        | _ ->
          (* Non-App after selector_reduce: opaque (variable, literal, etc.).
             selector_reduce is a fixed point on non-App terms, so further
             recursion cannot reduce it — return None immediately. *)
          None
    in
    go arg_term

(* Reflect an ERecord literal as a constructor application in SMT.
   Fields are reordered to match the declaration order stored in ctor_field_names.
   Returns None if any field's scalar term is untranslatable (conservative skip). *)
let reflect_record_literal (sort_name : string) (fields : (A.name * A.expr) list)
    (reflect_scalar : A.expr -> Smt.term option) : Smt.term option =
  match Hashtbl.find_opt adt_ctors sort_name with
  | Some [ ctor ] ->
    (match Hashtbl.find_opt ctor_field_names ctor with
     | None -> None
     | Some fname_list ->
       let field_map = List.map (fun (n, e) -> (n.A.txt, e)) fields in
       let in_order =
         List.filter_map (fun fname -> List.assoc_opt fname field_map) fname_list
       in
       if List.length in_order <> List.length fname_list then None
       else
         let reflected = List.map reflect_scalar in_order in
         if List.exists Option.is_none reflected then None
         else Some (Smt.App (ctor, List.filter_map Fun.id reflected)))
  | _ -> None

let check_post ~root errctx ~span ?(record_sort : string option = None)
    ?(fn_name : string option = None) (sc : scope)
    (binder : string) (ret_pred : A.expr)
    ((path, tail_e) : (A.expr * bool) list * A.expr) : unit =
  let base_decls, base_assume, scope_has_record = scope_facts sc in
  let decls = ref base_decls and assume = ref base_assume in
  let post_measure_ctr = ref 0 in
  (* Set when resolve_measure_app emits App(m, arg) — the VC then needs the full
     measure preamble (axioms + datatypes).  False => type_preamble only suffices
     (no quantified axioms → Z3 answers sat/unsat without returning `unknown`). *)
  let needs_axiom_preamble = ref false in
  let var_const name = decls := (name, Smt.SInt) :: !decls; Some (Smt.Const name) in
  let resolve_measure m name =
    let c = Smt.Const (m ^ "$" ^ name) in
    decls := (m ^ "$" ^ name, Smt.SInt) :: !decls;
    if is_nonneg_measure m then assume := Smt.Ge (c, Smt.IntLit 0) :: !assume;
    Some c
  in
  (* Handle measure applications where the argument is a non-variable expression
     (e.g. len(v.history) where v.history resolves to a concrete list term).
     - "len" on a concrete list: evaluated by concrete_len; avoids Z3 quantifier axioms
     - axiom measures (user @[measure]): OCaml-level evaluation first (avoids forall
       quantifiers that cause Z3 `unknown`); falls back to App(m,[arg]) for non-concrete
     - other: introduce a fresh symbolic constant with non-negativity if applicable *)
  let resolve_measure_app m arg_term =
    if m = "len" then
      match concrete_len arg_term with
      | Some n -> Some (Smt.IntLit n)
      | None ->
        incr post_measure_ctr;
        let nm = Printf.sprintf "len$app%d" !post_measure_ctr in
        decls := (nm, Smt.SInt) :: !decls;
        assume := Smt.Ge (Smt.Const nm, Smt.IntLit 0) :: !assume;
        Some (Smt.Const nm)
    else if is_axiom_measure m then
      (match concrete_measure_app m arg_term with
       | Some n -> Some (Smt.IntLit n)
       | None ->
         (* Concrete evaluation failed — fall back to App(m, arg) and tell the
            preamble builder that the VC needs quantified axioms. *)
         needs_axiom_preamble := true;
         Some (Smt.App (m, [ arg_term ])))
    else begin
      incr post_measure_ctr;
      let nm = Printf.sprintf "%s$app%d" m !post_measure_ctr in
      decls := (nm, Smt.SInt) :: !decls;
      if is_nonneg_measure m then assume := Smt.Ge (Smt.Const nm, Smt.IntLit 0) :: !assume;
      Some (Smt.Const nm)
    end
  in
  (* Field resolver covering record-typed scope params: resolves `old.field` in
     the return expression via the SMT selector for the opaque param const. *)
  let scope_field_resolver : string -> string -> Smt.term option =
    List.fold_left
      (fun rf (name, (_b, _q, sort)) ->
        match sort with
        | None -> rf
        | Some sort_name ->
          let rf_param = make_field_resolver name sort_name (Smt.Const name) in
          fun varname fname ->
            match rf varname fname with
            | Some _ as r -> r
            | None -> rf_param varname fname)
      (fun _ _ -> None) sc
  in
  let scalar e = smt_of ~resolve_var:var_const ~resolve_measure ~resolve_measure_app ~resolve_field:scope_field_resolver e in
  let tail_term_opt =
    match record_sort with
    | Some sort_name ->
      (match tail_e with
       | A.ERecord (fields, _) -> reflect_record_literal sort_name fields scalar
       | _ -> scalar tail_e)
    | None -> scalar tail_e
  in
  match tail_term_opt with
  | None -> ()
  | Some tail_term ->
    let resolve_field = match record_sort with
      | Some sort_name -> make_field_resolver binder sort_name tail_term
      | None -> fun _ _ -> None
    in
    let resolve_var name = if name = binder || name = "_" then Some tail_term else var_const name in
    List.iter
      (fun (cond, negated) ->
        match smt_of ~resolve_var ~resolve_measure ~resolve_field ~resolve_measure_app cond with
        | Some t -> assume := (if negated then Smt.Not t else t) :: !assume
        | None -> ())
      path;
    (match smt_of ~resolve_var ~resolve_measure ~resolve_field ~resolve_measure_app ret_pred with
     | None -> ()
     | Some goal ->
       let decls =
         List.fold_left (fun acc d -> if List.mem d acc then acc else d :: acc) [] !decls
       in
       let vc = { Smt.decls; assumptions = !assume; goal } in
       let preamble =
         if record_sort <> None || scope_has_record then
           (* When all measure apps were evaluated concretely (needs_axiom_preamble=false),
              skip the quantified-axiom measure_preamble.  The quantified forall axioms
              cause Z3 to return `unknown` for SAT queries even when the goal is trivial
              and measures no longer appear in it.  Type preamble alone suffices. *)
           if !needs_axiom_preamble then record_vc_preamble ()
           else type_only_preamble ()
         else ""
       in
       (match Refine.discharge ~root ~preamble vc with
        | Refine.Verified -> ()
        | first ->
          let emit_error () =
            ignore tail_e;
            let pred = pred_str ret_pred in
            let fn_prefix = match fn_name with
              | Some n -> Printf.sprintf "`%s` does not satisfy" n
              | None   -> "The return value does not satisfy"
            in
            let msg = Printf.sprintf
              "%s its return type constraint on all code paths.\n\nThe return type requires:\n\n    %s%s"
              fn_prefix pred (cx_block (model_of first))
            in
            let hint = Printf.sprintf
              "Every branch must produce a return value satisfying `%s`." pred
            in
            Err.report errctx
              { March_errors.Errors.severity = March_errors.Errors.Error
              ; span; message = msg; labels = []
              ; notes = [hint]; code = None; fix = None }
          in
          if scope_has_record then
            (* With concrete record preconditions in scope, a SAT counterexample
               satisfying those preconditions IS a real violation — report it. *)
            (match first with Refine.Refuted _ -> emit_error () | _ -> ())
          else
            match Refine.discharge ~root ~preamble { vc with Smt.goal = Smt.Not goal } with
            | Refine.Verified -> emit_error ()
            | _ -> ()))

let check_fn_post ~root errctx (fd : A.fn_def) : unit =
  match return_refine_ext fd with
  | None -> ()
  | Some (binder, ret_pred, record_sort) ->
    List.iter
      (fun (c : A.fn_clause) ->
        let sc = List.fold_left scope_add_fnparam [] c.A.fc_params in
        let base = match c.A.fc_guard with Some g -> [ (g, false) ] | None -> [] in
        List.iter
          (check_post ~root errctx ~span:c.A.fc_span ~record_sort
             ~fn_name:(Some fd.A.fn_name.A.txt) sc binder ret_pred)
          (tails base c.A.fc_body))
      fd.A.fn_clauses

(* ── Walk expressions, threading the refined-local scope and path context ── *)
let rec visit ~root errctx defs (ctx : rctx) (path : (A.expr * bool) list) (sc : scope)
    (e : A.expr) : unit =
  let go = visit ~root errctx defs ctx path sc in
  let go_path p = visit ~root errctx defs ctx p sc in
  match e with
  | A.EApp (A.EVar { A.txt = fname; _ }, args, sp) ->
    (match resolve_call ctx defs fname with
     | Some (Some sg) ->
       List.iter (fun rp -> check_call ~root errctx ~span:sp sg args path rp sc) sg.refined
     | _ -> ());
    List.iter go args
  | A.EApp (f, args, _) -> go f; List.iter go args
  | A.ECon (_, args, _) | A.EAtom (_, args, _) | A.ETuple (args, _) -> List.iter go args
  | A.EBlock (es, _) ->
    (* Thread BOTH the path context and the refined-local scope left-to-right:
       a `let` extends the scope; an `assert(p)` (used as an `assume`) extends
       the path so a later call can rely on p. *)
    ignore
      (List.fold_left
         (fun (path, sc) e ->
           visit ~root errctx defs ctx path sc e;
           let path' =
             match e with A.EAssert (p, _) -> (p, false) :: path | _ -> path
           in
           let sc' = match e with A.ELet (b, _) -> scope_add_binding sc b | _ -> sc in
           (path', sc'))
         (path, sc) es)
  | A.ELet (b, _) -> go b.A.bind_expr
  | A.ELam (ps, body, _) ->
    visit ~root errctx defs ctx path (List.fold_left scope_add_param sc ps) body
  | A.ELetFn (_, ps, _, body, _) ->
    visit ~root errctx defs ctx path (List.fold_left scope_add_param sc ps) body
  | A.EMatch (subj, branches, _) ->
    go subj;
    List.iter
      (fun (br : A.branch) ->
        let p = match br.A.branch_guard with Some g -> (g, false) :: path | None -> path in
        go_path p br.A.branch_body)
      branches
  | A.EIf (c, t, e, _) ->
    go c;
    go_path ((c, false) :: path) t;
    go_path ((c, true) :: path) e
  | A.ECond (arms, _) ->
    List.iter (fun (c, b) -> go c; go_path ((c, false) :: path) b) arms
  | A.ERecord (fields, _) -> List.iter (fun (_, v) -> go v) fields
  | A.ERecordUpdate (r, fields, _) -> go r; List.iter (fun (_, v) -> go v) fields
  | A.EField (r, _, _) -> go r
  | A.EPipe (a, b, _) -> go a; go b
  | A.EAnnot (e, _, _) | A.ESpawn (e, _) | A.EAssert (e, _) | A.ESigil (_, e, _) -> go e
  | A.ESend (a, b, _) -> go a; go b
  | A.ELetQ (_, e1, e2, _) -> go e1; go e2
  | A.EDbg (Some e, _) -> go e
  | A.ELit _ | A.EVar _ | A.EHole _ | A.EResultRef _ | A.EDbg (None, _) -> ()

let visit_fn ~root errctx defs (ctx : rctx) (fd : A.fn_def) : unit =
  check_fn_post ~root errctx fd;
  List.iter
    (fun (c : A.fn_clause) ->
      let sc = List.fold_left scope_add_fnparam [] c.A.fc_params in
      let path = match c.A.fc_guard with Some g -> [ (g, false) ] | None -> [] in
      visit ~root errctx defs ctx path sc c.A.fc_body)
    fd.A.fn_clauses

let rec visit_decls ~root errctx defs (ctx : rctx) (decls : A.decl list) : unit =
  (* Gather this scope's aliases/uses first so every function in the module sees
     them (matches lexical, module-wide visibility; inner modules inherit). *)
  let ctx =
    List.fold_left
      (fun ctx d ->
        match d with
        | A.DAlias (ad, _) -> { ctx with aliases = (ad.A.alias_name.A.txt, dotted ad.A.alias_path) :: ctx.aliases }
        | A.DUse (ud, _) -> { ctx with uses = (dotted ud.A.use_path, ud.A.use_sel) :: ctx.uses }
        | _ -> ctx)
      ctx decls
  in
  List.iter
    (function
      | A.DFn (fd, _) -> visit_fn ~root errctx defs ctx fd
      | A.DMod (name, _, ds, _) ->
        let modpath = if ctx.modpath = "" then name.A.txt else ctx.modpath ^ "." ^ name.A.txt in
        visit_decls ~root errctx defs { ctx with modpath } ds
      | _ -> ())
    decls

(** Register ADT/record sorts for a list of declarations without running the full
    VC pass.  Called by [--check-migration] mode to prime the type tables before
    invoking [check_fn_post] on a synthesised migrate_state signature.

    Clears all tables first to avoid stale accumulation from prior calls.
    Must be called with the prior-version record decls (e.g. [RawRecord]) so
    that their selectors are available when check_post reflects field projections. *)
let register_types_for_check (decls : A.decl list) : unit =
  Hashtbl.clear adt_ctors;
  Hashtbl.clear ctor_field_sorts;
  Hashtbl.clear ctor_field_names;
  Hashtbl.clear axiom_measures;
  Hashtbl.clear measure_base_cases;
  Hashtbl.clear measure_preamble_sorts;
  registered_measures := [];
  measure_nonneg := [];
  measure_preamble := "";
  type_preamble := "";
  register_builtin_adts ();
  register_adt_names decls;
  register_field_sorts decls;
  build_type_preamble ()

(** Entry point: check refinement preconditions across [m], emitting
    diagnostics into [errctx].  [root] is the project root for the VC cache. *)
(* Functions annotated `@[measure]` as (bare name, fn_def). *)
let rec collect_measure_fns (decls : A.decl list) : (string * A.fn_def) list =
  List.concat_map
    (function
      | A.DFn (fd, _) when List.mem "measure" fd.A.fn_attrs -> [ (fd.A.fn_name.A.txt, fd) ]
      | A.DMod (_, _, ds, _) -> collect_measure_fns ds
      | _ -> [])
    decls

(* [measure_axioms] (default true) gates the whole measure-axiom machinery —
   datatype modelling, recursion-equation axioms, AND the M-b soundness gate (the
   gate exists to keep those axioms sound, so with axioms off it has no purpose).
   With it off, measures reflect purely symbolically (the pre-M-a behaviour:
   sound, no quantifiers, no datatype theory), an escape hatch for the per-query
   cost of quantified/datatype reasoning.  It changes only diagnostics, never the
   compiled artifact, so it is not part of the CAS cache key. *)
let check_module ?(root = Sys.getcwd ()) ?(measure_axioms = true) (errctx : Err.ctx)
    (m : A.module_) : unit =
  let mfns = collect_measure_fns m.A.mod_decls in
  registered_measures := List.map fst mfns;
  (* Determine which measures are non-negative (single pass; a measure depending
     only on already-classified ones, itself, and `len` is classified). *)
  measure_nonneg :=
    List.fold_left
      (fun known (name, fd) ->
        match fd.A.fn_clauses with
        | c :: _ when measure_body_nonneg name known c.A.fc_body -> name :: known
        | _ -> known)
      [] mfns;
  Hashtbl.reset adt_ctors;
  Hashtbl.reset ctor_field_sorts;
  Hashtbl.reset ctor_field_names;
  Hashtbl.reset axiom_measures;
  Hashtbl.reset measure_base_cases;
  Hashtbl.reset measure_preamble_sorts;
  measure_preamble := "";
  type_preamble := "";
  if measure_axioms then begin
    register_builtin_adts ();
    register_adt_names m.A.mod_decls;
    register_field_sorts m.A.mod_decls;
    build_measure_preamble mfns;
    build_type_preamble ();
    (* M-b soundness gate: a `@[measure]` must be a total, terminating, pure
       function, else its axioms would be unsound.  Emit a hard error per
       violation (filtered to user files by the caller, like every diagnostic). *)
    List.iter
      (fun (_name, fd) ->
        List.iter
          (fun msg ->
            Err.error errctx ~span:fd.A.fn_name.A.span
              (Printf.sprintf "@[measure] `%s` %s" fd.A.fn_name.A.txt msg))
          (measure_gate_errors fd))
      mfns
  end;
  let defs = collect_all_defs m.A.mod_decls in
  (* Always walk: a function may have a refined *return* (postcondition) even
     with no refined parameters, so it won't appear in [defs]. *)
  visit_decls ~root errctx defs rctx0 m.A.mod_decls
