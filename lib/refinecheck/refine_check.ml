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

(* A refined parameter: position, predicate binder, predicate expression, and
   the SMT sort of its base type when that base is NOT `Int`:
     - [str_sort] when the base is `String` — the binder reflects into the
       opaque `Str` sort rather than `Int`;
     - a registered ADT's sort name — the call site reflects the actual
       argument as a datatype term instead of a scalar;
     - a registered 1-constructor RECORD's sort name (`Some "M_Config"`), a
       special case of the ADT line above: the call site additionally resolves
       the predicate's `v.field` projections through that sort's selectors;
     - [None] for a plain `Int`.
   Use [rp_is_str] rather than comparing against [str_sort] by hand, and
   [is_record_sort] rather than testing for a record shape by hand. *)
type rparam = { idx : int; binder : string; pred : A.expr; sort : string option }

let binder_name : A.name option -> string = function
  | None -> "_"
  | Some n -> n.A.txt

let is_int_base : A.ty -> bool = function
  | A.TyCon ({ A.txt = "Int"; _ }, []) -> true
  | _ -> false

let is_string_base : A.ty -> bool = function
  | A.TyCon ({ A.txt = "String"; _ }, []) -> true
  | _ -> false

(* ── The String encoding ───────────────────────────────────────────────────
   `String` is modelled as an UNINTERPRETED SORT and `len` as an uninterpreted
   function `Str -> Int` constrained only by non-negativity.  Each distinct
   string literal appearing in a VC becomes a declared constant with its length
   pinned and its distinctness from every other literal asserted.

   This deliberately stays inside the EUF + linear-arithmetic fragment that
   `Smt.render` already emits — structurally the same trick as list `len`.  We
   do NOT use Z3's string theory (`str.len`, `str.++`, the built-in `String`
   sort, regex): staying decidable and cheap is the whole point of the scoping.

   The consequence to keep in mind is that `Str` is opaque: knowing a value is
   DISTINCT from the empty literal does not establish its length (there is no
   injectivity axiom relating a string to its length).  So an `s == ""` guard
   proves nothing about `len(s)` in the else-branch, and the checker stays
   silent there — correct under the definite-failure stance, and documented as
   a limitation rather than papered over.

   All three SMT names below contain `$`, which is legal in an SMT-LIB simple
   symbol but CANNOT occur in a March identifier.  That is load-bearing, not
   cosmetic: a plain `len` symbol collides with any user or stdlib variable
   named `len`, and a colliding `(declare-const len Int)` next to
   `(declare-fun len …)` makes z3 emit an error line.  The solver is one
   long-lived `z3 -in` process shared by the whole compilation and the driver
   reads exactly one verdict line per query, so a single such error
   DESYNCHRONISES the channel and corrupts every subsequent VC in the run. *)
let str_sort = "$Str"
let strlen_fn = "$strlen"

let string_preamble =
  Printf.sprintf
    "(declare-sort %s 0)\n\
     (declare-fun %s (%s) Int)\n\
     (assert (forall ((s %s)) (! (>= (%s s) 0) :pattern ((%s s)))))\n"
    str_sort strlen_fn str_sort str_sort strlen_fn strlen_fn

(* Does this refined parameter's base type reflect into the `Str` sort?  The
   one place [rparam.sort] is compared against [str_sort]; every other consumer
   of [sort] treats a `Some _` it does not recognise as an ADT sort name. *)
let rp_is_str (rp : rparam) : bool = rp.sort = Some str_sort

(* ── Well-sortedness guard ────────────────────────────────────────────────
   `$Str` is a sort apart, and the rest of the VC language is Int/Bool.  A term
   that mixes them (`(= caller_var $str0)` where the caller variable was
   reflected as an Int) is not merely useless — z3 REJECTS it, with the
   channel-desynchronising consequence described above.  So a term mentioning a
   string is admitted only where it is genuinely well-sorted: as the argument of
   [strlen_fn], or with both sides of an =/≠ being string constants.

   [mentions_str] deliberately stops at [strlen_fn]: `($strlen c)` is an Int and
   may be added, compared and multiplied like any other. *)
let rec mentions_str (is_str : string -> bool) (t : Smt.term) : bool =
  let m = mentions_str is_str in
  match t with
  | Smt.App (f, [ _ ]) when f = strlen_fn -> false
  | Smt.Const c -> is_str c
  | Smt.App (_, args) -> List.exists m args
  (* A datatype tester ranges over an ADT sort, never over `Str`; it only
     "mentions a string" if its subject somehow does. *)
  | Smt.IsCtor (_, a) -> m a
  | Smt.IntLit _ | Smt.BoolLit _ -> false
  | Smt.Not a | Smt.Neg a | Smt.MulLit (_, a) -> m a
  | Smt.Add (a, b) | Smt.Sub (a, b) | Smt.And (a, b) | Smt.Or (a, b)
  | Smt.Implies (a, b) | Smt.Eq (a, b) | Smt.Ne (a, b) | Smt.Lt (a, b)
  | Smt.Le (a, b) | Smt.Gt (a, b) | Smt.Ge (a, b) -> m a || m b

let rec wellsorted (is_str : string -> bool) (t : Smt.term) : bool =
  let w = wellsorted is_str and m = mentions_str is_str in
  let int_side a = (not (m a)) && w a in
  match t with
  | Smt.Const _ | Smt.IntLit _ | Smt.BoolLit _ -> true
  | Smt.App (f, [ a ]) when f = strlen_fn ->
    (match a with Smt.Const c -> is_str c | _ -> false)
  | Smt.App (_, args) -> List.for_all int_side args
  (* `((_ is Ctor) x)` is a Bool over a datatype subject.  It is well-sorted
     exactly when its subject is a datatype term, i.e. does not drag a `Str`
     constant in — which cannot happen, but is checked rather than assumed. *)
  | Smt.IsCtor (_, a) -> not (m a)
  | Smt.Eq (a, b) | Smt.Ne (a, b) ->
    (match a, b with
     | Smt.Const x, Smt.Const y when is_str x && is_str y -> true
     | _ -> int_side a && int_side b)
  | Smt.Not a -> w a
  | Smt.Neg a | Smt.MulLit (_, a) -> int_side a
  | Smt.And (a, b) | Smt.Or (a, b) | Smt.Implies (a, b) -> w a && w b
  | Smt.Add (a, b) | Smt.Sub (a, b) | Smt.Lt (a, b) | Smt.Le (a, b)
  | Smt.Gt (a, b) | Smt.Ge (a, b) -> int_side a && int_side b

(* A function's declared return refinement, when its base type is Int.
   Defined here (rather than beside the other postcondition helpers) because
   [collect_all_defs] records it into every fn_sig. *)
let return_refine (fd : A.fn_def) : (string * A.expr) option =
  match fd.A.fn_ret_ty with
  | Some (A.TyRefine (base, binder, pred)) when is_int_base base ->
    Some (binder_name binder, pred)
  | _ -> None

(* True iff [pred]'s only free variable is the refinement binder — i.e. the
   predicate constrains the refined value alone and mentions no parameter.

   `{Int | _ >= 0}`      -> closed
   `{Int | _ == n + 1}`  -> NOT closed (mentions the parameter `n`)
   `{Int | _ < len(xs)}` -> NOT closed (mentions `xs`)

   A non-closed (relational) postcondition can only be used at a call site by
   substituting actuals for formals — deliberately out of scope (Tier 1).
   Unrecognised syntax is conservatively treated as NOT closed, so an
   unfamiliar predicate is skipped rather than trusted. *)
let pred_is_closed (binder : string) (pred : A.expr) : bool =
  let ok = ref true in
  let rec go (e : A.expr) =
    match e with
    | A.EVar { A.txt; _ } -> if txt <> binder && txt <> "_" then ok := false
    (* The head of an application is a function/operator name, not a value
       reference: only its arguments can carry free variables. *)
    | A.EApp (A.EVar _, args, _) -> List.iter go args
    | A.EApp (f, args, _) -> go f; List.iter go args
    | A.ETuple (es, _) | A.ECon (_, es, _) | A.EAtom (_, es, _) -> List.iter go es
    | A.EAnnot (e, _, _) -> go e
    | A.ELit _ -> ()
    | _ -> ok := false
  in
  go pred;
  !ok

(* A function's signature: parameter names by position, its refined params, and
   its declared return refinement (binder + predicate) when the return type is
   an Int refinement.  [ret] is stored UNFILTERED — the closedness test is
   applied at the use sites via [postcond_of], so relaxing it for relational
   postconditions (Tier 1) is a one-place change. *)
type fn_sig = {
  param_names : string list;
  (* Parallel to [param_names]: true where the parameter's declared base type is
     String (bare or refined).  This is what makes the `len` OVERLOAD safe — the
     string meaning is chosen only from a declared type, never guessed. *)
  param_str : bool list;
  refined : rparam list;
  ret : (string * A.expr) option;
}

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

(* `len` over strings is only safe to encode while `len` still MEANS the builtin
   measure.  A user `@[measure] fn len(…)` would be axiomatised over its own ADT
   sort, and declaring a second `len : Str -> Int` in the same VC would either
   collide or silently assert a fact about the wrong function.  When the name is
   taken, we disable the string meaning entirely and skip — a wrong resolution
   asserts a wrong fact, which is the one thing that must never happen. *)
let string_len_available () : bool = not (List.mem "len" !registered_measures)

(* ── The predicate vocabulary ──────────────────────────────────────────────
   Which names carry meaning inside a refinement predicate.  Previously this
   knowledge was implicit: spread across [is_measure], [is_nonneg_measure] and
   inline "len" comparisons at four sites, and otherwise encoded only in
   [smt_of]'s match arms.  Naming it lets us (a) warn about a predicate the
   checker will silently ignore, and (b) give the ADT feature one place to
   register its constructor testers. *)

(* Operators [smt_of] translates.  Kept in sync with its match arms by the
   `every operator is known vocabulary` test in test_refinecheck.ml. *)
let predicate_operators =
  [ "+"; "-"; "*"; "negate"; "not"; "&&"; "||"
  ; "=="; "!="; "<"; "<="; ">"; ">=" ]

let is_predicate_operator (m : string) : bool = List.mem m predicate_operators

(* [known_predicate_fn] is defined below [adt_ctors], since the vocabulary now
   includes the auto-derived `is_<Ctor>` testers. *)

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

(* ── Constructor testers ───────────────────────────────────────────────────
   Every constructor of every registered ADT implicitly gains an `is_<Ctor>`
   predicate: "is_Some" -> Some "Some", when `Some` is a constructor of some
   registered ADT.  The match is EXACT-CASE, so `is_some` (the lowercase
   stdlib helper `Option.is_some`) is NOT a tester: a misspelling keeps drawing
   the unrecognized-predicate warning rather than silently meaning something. *)
let ctor_of_tester (m : string) : string option =
  let pfx = "is_" in
  let n = String.length pfx in
  if String.length m <= n || String.sub m 0 n <> pfx then None
  else
    let ctor = String.sub m n (String.length m - n) in
    let known =
      Hashtbl.fold (fun _ ctors acc -> acc || List.mem ctor ctors) adt_ctors false
    in
    if known then Some ctor else None

(* True iff the checker attaches meaning to [m] applied inside a predicate. *)
let known_predicate_fn (m : string) : bool =
  is_predicate_operator m || is_measure m || ctor_of_tester m <> None

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

(* [is_record_base] on an already-computed SMT sort name.  Records are a strict
   SUBSET of the ADT sorts, so a consumer that wants the record-specific path
   (field selectors) must test this rather than merely observing `sort = Some
   _`, which is also true of a String ([str_sort]) and of a plain variant. *)
let is_record_sort (s : string) : bool =
  s <> str_sort
  && (match Hashtbl.find_opt adt_ctors s with
      | Some [ ctor ] -> Hashtbl.mem ctor_field_names ctor
      | _ -> false)

(* True when [t] is a bare TyCon naming any registered ADT — variant or
   record, and (unlike [is_record_base]) whether or not it is applied to type
   arguments, e.g. `Option(Int)`.  The ADT-tag feature dispatches on this. *)
let is_adt_base (t : A.ty) : bool =
  match t with
  | A.TyCon ({ A.txt = name; _ }, _) -> Hashtbl.mem adt_ctors (adt_sort_name name)
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

(* The built-in ADTs, modelled so user measures and constructor testers over
   them work exactly like over user ADTs.  `List(a)` = `Nil | Cons(a, List(a))`
   with the element opaque (`Elem`) and the tail recursive.  `Option(a)` and
   `Result(a, e)` have no `type` declaration anywhere — not in the stdlib
   either; they are pre-registered by the typechecker (see [builtin_ctors] in
   typecheck.ml), so the refinement checker must seed them the same way or
   `is_Some` would name nothing.  Payloads are opaque (`Elem`): a constructor
   tester cares about the tag, not the contents.  Seeded before user types so a
   user-defined `List`/`Option` (unusual) still overrides. *)
let register_builtin_adts () : unit =
  Hashtbl.replace adt_ctors (adt_sort_name "List") [ "Nil"; "Cons" ];
  Hashtbl.replace ctor_field_sorts "Nil" [];
  Hashtbl.replace ctor_field_sorts "Cons" [ Smt.SData "Elem"; Smt.SData (adt_sort_name "List") ];
  Hashtbl.replace adt_ctors (adt_sort_name "Option") [ "None"; "Some" ];
  Hashtbl.replace ctor_field_sorts "None" [];
  Hashtbl.replace ctor_field_sorts "Some" [ Smt.SData "Elem" ];
  Hashtbl.replace adt_ctors (adt_sort_name "Result") [ "Ok"; "Err" ];
  Hashtbl.replace ctor_field_sorts "Ok" [ Smt.SData "Elem" ];
  Hashtbl.replace ctor_field_sorts "Err" [ Smt.SData "Elem" ]

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

(* Datatype declarations for [seeds] and everything reachable from them — the
   preamble a VC needs when a constructor tester ranges over those sorts.
   [skip] drops sorts already declared elsewhere in the same VC (Z3 rejects a
   duplicate sort inside one push), and [skip_elem] does the same for the
   opaque `Elem` sort. *)
let adt_vc_preamble ~(skip : string -> bool) ~(skip_elem : bool) (seeds : string list) : string =
  let sorts = List.filter (fun s -> not (skip s)) (adt_closure seeds) in
  if sorts = [] then ""
  else
    let needs_elem =
      (not skip_elem)
      && List.exists
           (fun sort ->
             List.exists
               (fun ctor ->
                 List.exists
                   (fun s -> s = Smt.SData "Elem")
                   (try Hashtbl.find ctor_field_sorts ctor with Not_found -> []))
               (try Hashtbl.find adt_ctors sort with Not_found -> []))
           sorts
    in
    (if needs_elem then "(declare-sort Elem 0)\n" else "") ^ datatype_decls sorts

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
    ?(resolve_measure_app = fun _ _ -> None) ?(resolve_tester = fun _ _ -> None)
    ?(resolve_str_lit = fun _ -> None)
    (e : A.expr) : Smt.term option =
  let r = smt_of ~resolve_var ~resolve_measure ~resolve_field ~resolve_measure_app
            ~resolve_tester ~resolve_str_lit in
  let b2 f a b = match r a, r b with Some x, Some y -> Some (f x y) | _ -> None in
  match e with
  | A.ELit (A.LitInt n, _) -> Some (Smt.IntLit n)
  | A.ELit (A.LitBool b, _) -> Some (Smt.BoolLit b)
  (* A string literal reflects to its per-VC constant, when the caller supplies
     a table.  Callers that cannot model strings leave [resolve_str_lit] at its
     default and the literal stays untranslatable — i.e. skipped. *)
  | A.ELit (A.LitString s, _) -> resolve_str_lit s
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
  (* A constructor tester `is_Ctor(e)`: reflects to the Z3 datatype tester
     ((_ is Ctor) e).  [resolve_tester] owns reflecting [e] into a term of the
     right datatype sort (and declaring/registering it); a context that cannot
     do that returns None and the predicate is skipped. *)
  | A.EApp (A.EVar { A.txt = m; _ }, [ arg ], _) when ctor_of_tester m <> None ->
    (match ctor_of_tester m with
     | Some ctor -> resolve_tester ctor arg
     | None -> None)
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
  | A.EApp (A.EVar { A.txt = m; _ }, [ a ], _) when is_measure m || ctor_of_tester m <> None ->
    m ^ "(" ^ pred_str a ^ ")"
  | A.ECon ({ A.txt = ctor; _ }, [], _) -> ctor
  | A.ECon ({ A.txt = ctor; _ }, args, _) ->
    ctor ^ "(" ^ String.concat ", " (List.map pred_str args) ^ ")"
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
    (* SMT-LIB writes a negative integer as `(- 1)`; show it as `-1`. *)
    | [ "-"; n ] when n <> "" && String.for_all (fun c -> c >= '0' && c <= '9') n -> "-" ^ n
    | ctor :: args ->
      (match Hashtbl.find_opt ctor_field_names ctor with
       | Some fields when List.length fields = List.length args ->
         "{ " ^ String.concat ", "
           (List.map2 (fun f a -> f ^ ": " ^ pretty_smt_value a) fields args) ^ " }"
       | _ -> v)
    | _ -> v
  end else v

(* True for the "ret<N>" suffix of a propagated-postcondition constant. *)
let is_ret_suffix (s : string) : bool =
  String.length s > 3
  && String.sub s 0 3 = "ret"
  && String.for_all (fun c -> c >= '0' && c <= '9')
       (String.sub s 3 (String.length s - 3))

(* Render one model entry.  Internal SMT constants use `$` to join a symbol to
   its subject:
     - a measure application, "len$xs"        -> "len(xs) = 3"
     - a propagated call result, "f$ret1"     -> "f() can return -1"   (the
       `ret1` part is an internal freshness tag, NOT an argument — rendering
       it as "f(ret1)" reads as a call to `f` with a variable named `ret1`).
       The model gives a WITNESS satisfying f's postcondition, not a claim
       about what f actually returns, so the phrasing must not assert fact.
   Anything else prints as "k = v". *)
let render_model_entry (k, v) : string =
  let v' = pretty_smt_value v in
  match String.index_opt k '$' with
  | Some i ->
    let head = String.sub k 0 i in
    let tail = String.sub k (i + 1) (String.length k - i - 1) in
    if is_ret_suffix tail then Printf.sprintf "%s() can return %s" head v'
    else Printf.sprintf "%s(%s) = %s" head tail v'
  | None -> Printf.sprintf "%s = %s" k v'

(* Drop model entries whose value is an uninterpreted-sort witness such as
   `Str!val!0`.  Z3 invents those names for elements of a sort it knows nothing
   about; printing one tells the reader nothing about their program and reads
   like internal noise.  The useful facts about a string (its length) come
   through as ordinary `(len c)` entries and survive this filter. *)
let is_opaque_witness (v : string) : bool =
  match String.index_opt v '!' with
  | None -> false
  | Some i ->
    let rest = String.sub v i (String.length v - i) in
    String.length rest > 5 && String.sub rest 0 5 = "!val!"

let visible_model (model : (string * string) list) : (string * string) list =
  List.filter (fun (_, v) -> not (is_opaque_witness v)) model

(* Inline counterexample suffix for call-site errors (e.g. precondition checks).
   Returns "" when the model is empty. *)
let format_cx (model : (string * string) list) : string =
  let model = visible_model model in
  if model = [] then ""
  else " (e.g. " ^ String.concat ", " (List.map render_model_entry model) ^ ")"

(* Multi-line counterexample block for return-type constraint errors. Returns "" when empty. *)
let cx_block (model : (string * string) list) : string =
  let model = visible_model model in
  if model = [] then ""
  else
    "\n\nA counterexample was found:\n\n    " ^
    String.concat "\n    " (List.map render_model_entry model)

let model_of = function Refine.Refuted m -> m | _ -> []

(* ── Scope of refined locals/params: name -> (binder, predicate) ─────────── *)
type scope = (string * (string * A.expr * string option)) list

(* A refined PARAMETER, for the call-site check: `Int` (no sort), `String`
   ([str_sort], reflected as an opaque `Str` constant), or any registered ADT —
   applied or not, so `{Option(Int) | is_Some(_)}` counts — carrying that ADT's
   SMT sort name.  Deliberately wider than [refined_scope_ty] on the ADT side:
   an ADT refinement is a fact the call site can discharge from a constructor
   literal or a `match` narrowing, but it is not (yet) something the checker
   carries through a local binding.

   RECORDS need no clause of their own: a record type IS a registered
   1-constructor ADT, so [is_adt_base] already admits `{v : Config | v.port >=
   1}` and hands back the same `M_Config` sort name the record path in
   [check_call] keys on (see [is_record_sort]). *)
let refined_param_ty : A.ty option -> (string * A.expr * string option) option = function
  | Some (A.TyRefine (base, binder, pred)) when is_int_base base ->
    Some (binder_name binder, pred, None)
  | Some (A.TyRefine (base, binder, pred)) when is_string_base base ->
    Some (binder_name binder, pred, Some str_sort)
  | Some (A.TyRefine ((A.TyCon ({ A.txt = name; _ }, _) as base), binder, pred))
    when is_adt_base base ->
    Some (binder_name binder, pred, Some (adt_sort_name name))
  | _ -> None

(* True when a parameter's declared type is String, refined or not. *)
let is_string_param_ty : A.ty option -> bool = function
  | Some (A.TyRefine (base, _, _)) -> is_string_base base
  | Some t -> is_string_base t
  | None -> false

(* Like refined_param_ty but for the refined-LOCAL scope: admits Int, String
   ([str_sort]) and record TyCon params, reporting the SMT sort name — Some
   "M_…" for a record, Some [str_sort] for a String, None for an Int.  NOTE for
   consumers: `Some _` does NOT mean "record" — check against [str_sort] before
   taking a record-specific path. *)
let refined_scope_ty : A.ty option -> (string * A.expr * string option) option = function
  | Some (A.TyRefine (base, binder, pred)) when is_int_base base ->
    Some (binder_name binder, pred, None)
  | Some (A.TyRefine (base, binder, pred)) when is_string_base base ->
    Some (binder_name binder, pred, Some str_sort)
  | Some (A.TyRefine ((A.TyCon ({ A.txt = name; _ }, []) as base), binder, pred))
    when is_record_base base ->
    Some (binder_name binder, pred, Some (adt_sort_name name))
  | _ -> None

(* Names a pattern binds (so a binding construct can shadow them). *)
let rec pat_binders (p : A.pattern) : string list =
  match p with
  | A.PatVar n -> [ n.A.txt ]
  | A.PatAs (sub, n, _) -> n.A.txt :: pat_binders sub
  | A.PatCon (_, ps) | A.PatAtom (_, ps, _) | A.PatTuple (ps, _) ->
    List.concat_map pat_binders ps
  | A.PatRecord (fps, _) -> List.concat_map (fun (_, sub) -> pat_binders sub) fps
  (* UNION across alternatives, not intersection.  This list drives
     [scope_shadow], so a name that is missed here leaves an outer refined
     entry visible and lets the checker attribute the outer value's predicate
     to the inner binder — a false positive, the one failure this subsystem
     must never have.  Retiring a name an alternative did not actually bind
     only discards a fact, which is safe.  (Typecheck rejects or-patterns
     whose alternatives bind, so today this recursion finds names only in
     patterns nested around one; it is written for the contract, not the
     current restriction.) *)
  | A.PatOr (ps, _) -> List.concat_map pat_binders ps
  | A.PatWild _ | A.PatLit _ -> []

(* Drop shadowed entries.  [scope] is an assoc list read with [List.assoc_opt],
   so an inner binder that is itself UNREFINED would otherwise leave the outer
   refined entry visible and the checker would attribute the outer value's
   predicate to the inner binder — a false positive.  Every binding construct
   must remove its binders' names before adding any refined ones. *)
let scope_shadow (sc : scope) (names : string list) : scope =
  if names = [] then sc else List.filter (fun (n, _) -> not (List.mem n names)) sc

(* Does [e] mention any of [names]?  Deliberately syntactic and deliberately
   OVER-approximate: an occurrence anywhere in the subtree counts, including
   under a nested binder of the same name.  [path_shadow] only ever uses this
   to DISCARD a fact, so over-approximating loses information (silence) rather
   than inventing it (a false positive). *)
let rec expr_mentions (names : string list) (e : A.expr) : bool =
  let any = List.exists (expr_mentions names) in
  let bound ps = List.exists (fun n -> List.mem n names) ps in
  let params ps = List.exists (fun (p : A.param) -> List.mem p.A.param_name.A.txt names) ps in
  match e with
  | A.EVar n -> List.mem n.A.txt names
  | A.ELit _ | A.EHole _ | A.EResultRef _ | A.EDbg (None, _) -> false
  | A.EApp (f, args, _) -> expr_mentions names f || any args
  | A.ECon (_, args, _) | A.EAtom (_, args, _) | A.ETuple (args, _) -> any args
  | A.ELam (ps, body, _) -> params ps || expr_mentions names body
  | A.EBlock (es, _) -> any es
  | A.ELet (b, _) -> bound (pat_binders b.A.bind_pat) || expr_mentions names b.A.bind_expr
  | A.ELetFn (n, ps, _, body, _) ->
    List.mem n.A.txt names || params ps || expr_mentions names body
  | A.ELetQ (p, e1, e2, _) ->
    bound (pat_binders p) || expr_mentions names e1 || expr_mentions names e2
  | A.EMatch (subj, brs, _) ->
    expr_mentions names subj
    || List.exists
         (fun (br : A.branch) ->
           bound (pat_binders br.A.branch_pat)
           || (match br.A.branch_guard with Some g -> expr_mentions names g | None -> false)
           || expr_mentions names br.A.branch_body)
         brs
  | A.ERecord (fs, _) -> List.exists (fun (_, v) -> expr_mentions names v) fs
  | A.ERecordUpdate (r, fs, _) ->
    expr_mentions names r || List.exists (fun (_, v) -> expr_mentions names v) fs
  | A.EField (r, _, _) -> expr_mentions names r
  | A.EIf (c, t, el, _) -> any [ c; t; el ]
  | A.ECond (arms, _) ->
    List.exists (fun (c, b) -> expr_mentions names c || expr_mentions names b) arms
  | A.EPipe (a, b, _) | A.ESend (a, b, _) -> expr_mentions names a || expr_mentions names b
  | A.EAnnot (e, _, _) | A.ESpawn (e, _) | A.EAssert (e, _) | A.ESigil (_, e, _)
  | A.EDbg (Some e, _) -> expr_mentions names e

(* The path-context companion to [scope_shadow].  A path condition is recorded
   against a VARIABLE NAME (`is_None(x)`, `x < 0`); when an inner scope rebinds
   that name, the fact is about the OUTER value and saying it about the inner
   one is a false positive:

     match x do
       None ->
         let x = Some(1)
         unwrap(x)     -- `is_None(x)` must not survive to here
       ...

   So every binding construct in [visit] must drop any condition mentioning one
   of its binders before descending — exactly the discipline [scope_shadow]
   already imposes on the refined-local scope.  Dropping a fact is always sound
   under the definite-failure stance: fewer assumptions means fewer definite
   contradictions, i.e. more silence. *)
let path_shadow (path : (A.expr * bool) list) (names : string list) : (A.expr * bool) list =
  if names = [] then path else List.filter (fun (c, _) -> not (expr_mentions names c)) path

(* ── Record-typed variables in scope, refined or not ───────────────────────
   [scope] carries only REFINED locals, so a plain `c : Config` parameter is
   invisible to it — and a guard `if c.port >= 1` had nowhere to attach: the
   path condition's `c.port` translated to `None` and the fact was dropped.

   This env maps a variable whose DECLARED type is a registered record to that
   record's SMT sort.  [check_call] uses it for exactly two things:
     - a PATH CONDITION mentioning `c.field` reflects as the record's SMT
       selector applied to the constant `c`;
     - a record ARGUMENT that is such a variable reflects to that SAME
       constant, so the guard constrains the very value the goal projects from.
   Those two must agree or the fact is about a different value than the goal.

   It carries NO predicate.  A variable here is a wholly UNCONSTRAINED datatype
   constant: on its own neither the goal nor its negation is provable, so the
   call stays skipped exactly as before unless the path context settles it.
   Adding an entry can therefore only turn a skip into a check the guards
   actually decide — never into a guess.

   Like [scope] and [path] it obeys the shadow discipline: every binding
   construct must retire its binders' names before descending, or an outer
   record's identity is attributed to an inner binding.  Note the two channels
   are independent and BOTH matter here — [recenv_shadow] stops the inner
   binding being reflected as the outer constant, [path_shadow] stops the outer
   fact surviving; either one alone leaves a false positive. *)
type recenv = (string * string) list

let recenv_shadow (re : recenv) (names : string list) : recenv =
  if names = [] then re else List.filter (fun (n, _) -> not (List.mem n names)) re

(* The SMT sort of a declared type when it names a registered record — through
   a refinement wrapper too, so `c : {v : Config | …}` is tracked as well (its
   predicate still travels through [scope]; this records only the sort). *)
let record_sort_of_ty : A.ty option -> string option = function
  | Some (A.TyCon ({ A.txt = name; _ }, []) as t) when is_record_base t ->
    Some (adt_sort_name name)
  | Some (A.TyRefine ((A.TyCon ({ A.txt = name; _ }, []) as b), _, _)) when is_record_base b ->
    Some (adt_sort_name name)
  | _ -> None

let recenv_add_param (re : recenv) (p : A.param) : recenv =
  let re = recenv_shadow re [ p.A.param_name.A.txt ] in
  match record_sort_of_ty p.A.param_ty with
  | Some s -> (p.A.param_name.A.txt, s) :: re
  | None -> re

let recenv_add_fnparam (re : recenv) : A.fn_param -> recenv = function
  | A.FPNamed p | A.FPDefault (p, _) -> recenv_add_param re p
  | A.FPPat pat -> recenv_shadow re (pat_binders pat)

(* `let c : Config = …` takes the sort from the annotation; an UNANNOTATED
   `let c = d` whose RHS is a variable already known to be a record propagates
   that sort, since `c` and `d` denote the same value and so may share one SMT
   constant.  Everything else only shadows.  Note the shadowing happens FIRST,
   so `let c = c` finds nothing to propagate and the name simply leaves the
   env — the conservative direction. *)
let recenv_add_binding (re : recenv) (b : A.binding) : recenv =
  let re = recenv_shadow re (pat_binders b.A.bind_pat) in
  match b.A.bind_pat with
  | A.PatVar n ->
    (match record_sort_of_ty b.A.bind_ty with
     | Some s -> (n.A.txt, s) :: re
     | None ->
       (match b.A.bind_expr with
        | A.EVar { A.txt = y; _ } ->
          (match List.assoc_opt y re with Some s -> (n.A.txt, s) :: re | None -> re)
        | _ -> re))
  | _ -> re

let scope_add_param (sc : scope) (p : A.param) : scope =
  let sc = scope_shadow sc [ p.A.param_name.A.txt ] in
  match refined_scope_ty p.A.param_ty with
  | Some r -> (p.A.param_name.A.txt, r) :: sc
  | None -> sc

let scope_add_fnparam (sc : scope) : A.fn_param -> scope = function
  | A.FPNamed p | A.FPDefault (p, _) -> scope_add_param sc p
  | A.FPPat pat -> scope_shadow sc (pat_binders pat)

(* [postcond] resolves a callee name to its closed return refinement.  An
   explicit annotation always wins; only an UNANNOTATED `let` whose RHS is a
   direct named call falls back to the callee's declared postcondition. *)
let scope_add_binding ~(postcond : string -> (string * A.expr) option) (sc : scope)
    (b : A.binding) : scope =
  (* Shadow first: `let c = neg()` followed by `let c = 5` must not leave the
     first `c`'s postcondition attached to the second. *)
  let sc = scope_shadow sc (pat_binders b.A.bind_pat) in
  match b.A.bind_pat, refined_scope_ty b.A.bind_ty with
  | A.PatVar n, Some r -> (n.A.txt, r) :: sc
  | A.PatVar n, None ->
    (match b.A.bind_expr with
     | A.EApp (A.EVar { A.txt = fname; _ }, _, _) ->
       (match postcond fname with
        | Some (binder, pred) -> (n.A.txt, (binder, pred, None)) :: sc
        | None -> sc)
     | _ -> sc)
  | _ -> sc

(* ── Collect signatures, keyed by bare + qualified name ──────────────────── *)
let param_name_of : A.fn_param -> string = function
  | A.FPNamed p | A.FPDefault (p, _) -> p.A.param_name.A.txt
  | A.FPPat _ -> "_"

let param_ty_of : A.fn_param -> A.ty option = function
  | A.FPNamed p | A.FPDefault (p, _) -> p.A.param_ty
  | A.FPPat _ -> None

let sig_of_clause (c : A.fn_clause) : fn_sig =
  let param_names = List.map param_name_of c.A.fc_params in
  let param_str = List.map (fun fp -> is_string_param_ty (param_ty_of fp)) c.A.fc_params in
  let refined =
    List.mapi (fun idx fp -> (idx, fp)) c.A.fc_params
    |> List.filter_map (fun (idx, fp) ->
           match fp with
           | A.FPNamed p | A.FPDefault (p, _) ->
             (* [refined_param_ty] admits all four refinable bases — Int,
                String, variant ADT and record — so a record-refined parameter
                (`{v : Config | v.port >= 1}`) reaches [fn_sig.refined] and its
                field predicate is discharged at call sites.  The reported
                `sort` is what selects the String / ADT / record path in
                [check_call]; `None` keeps the Int path unchanged. *)
             (match refined_param_ty p.A.param_ty with
              | Some (binder, pred, sort) -> Some { idx; binder; pred; sort }
              | None -> None)
           | A.FPPat _ -> None)
  in
  { param_names; param_str; refined; ret = None }

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
          let base =
            match fd.A.fn_clauses with
            | c :: _ -> sig_of_clause c
            | [] -> { param_names = []; param_str = []; refined = []; ret = None }
          in
          let sg = { base with ret = return_refine fd } in
          (* Record the signature when EITHER side carries a refinement: a
             function with only a refined *return* must be resolvable so its
             postcondition reaches call sites, even though it has no refined
             params of its own to check. *)
          Hashtbl.replace tbl key
            (if sg.refined <> [] || Option.is_some sg.ret then Some sg else None)
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

(* Resolve a call name to the callee's *closed* return refinement, or None.
   This is the single place the closedness filter is applied, so both use
   sites (a let-bound local and an inline argument) agree, and Tier 1
   (relational postconditions) is a change to this one function.

   The other half of the filter is applied earlier: [gate_unverified_posts]
   has already cleared [ret] on every signature whose postcondition the
   definition side did not PROVE, so anything reaching here is a fact. *)
let postcond_of (ctx : rctx) (defs : (string, fn_sig option) Hashtbl.t) (fname : string)
  : (string * A.expr) option =
  match resolve_call ctx defs fname with
  | Some (Some sg) ->
    (match sg.ret with
     | Some (b, p) when pred_is_closed b p -> Some (b, p)
     | _ -> None)
  | _ -> None

(* Fresh-name counter for SMT constants standing in for a call's return value.
   Monotonic per compilation; freshness is all that is required. *)
let ret_ctr = ref 0

(* ── Record reflection helpers ────────────────────────────────────────────
   Shared by the call-site (precondition) and return-site (postcondition)
   checks, so both sides map a record value and its field projections into SMT
   exactly the same way. *)

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

(* True when [t] is a WELL-SORTED term for a constructor field of [sort].

   This check is not cosmetic.  The scalar reflection declares every variable it
   meets as `SInt`, so a record field of a non-Int type bound to a variable
   (`{ port: 8080, name: n }` where `name : String` has SMT sort `Elem`) would
   build a constructor application whose argument sorts do not match the
   datatype declaration.  Z3 answers such a VC with an `(error …)` rather than
   sat/unsat, and that error desynchronises the long-lived `z3 -in` channel —
   silently disabling refinement checking for the REST of the compilation.  A
   malformed VC is therefore far worse than a skipped one, so any field we
   cannot place at its declared sort makes the whole record unreflectable.

   Int/Bool fields accept any scalar term except a constructor application;
   a datatype-sorted field accepts only a constructor OF THAT SORT (so
   `history: Nil` still reflects, while `history: xs` — an opaque variable —
   does not).

   The check RECURSES into a constructor's arguments, because a top-level fit
   is not enough: `history: Cons(1, Nil)` places a well-sorted `M_List`
   constructor at an `M_List` field, but `Cons`'s own head field is declared
   `Elem` (the built-in `List` is generic, so its element sort is opaque) and
   the scalar reflection hands it the integer `1`.  Z3 rejects `(Cons 1 Nil)`
   with a multi-line `(error …)`, which is the very desynchronisation this
   function exists to prevent — so a list literal with concrete elements makes
   the record unreflectable, and the call is skipped. *)
let rec term_fits_sort (sort : Smt.sort) (t : Smt.term) : bool =
  let is_ctor_app = function
    | Smt.App (c, _) -> Hashtbl.mem ctor_field_sorts c
    | _ -> false
  in
  match sort with
  | Smt.SInt | Smt.SBool -> not (is_ctor_app t)
  | Smt.SData s ->
    (match t with
     | Smt.App (ctor, args) ->
       (match Hashtbl.find_opt adt_ctors s with
        | Some cs when List.mem ctor cs ->
          (* Every argument must sit at its own declared field sort.  An arity
             mismatch, or a constructor we have no field sorts for, is treated
             as a non-fit — again the skip direction. *)
          (match Hashtbl.find_opt ctor_field_sorts ctor with
           | Some fsorts when List.length fsorts = List.length args ->
             List.for_all2 term_fits_sort fsorts args
           | Some _ -> false
           | None -> args = [])
        | _ -> false)
     | _ -> false)

(* Reflect an ERecord literal as a constructor application in SMT.
   Fields are reordered to match the declaration order stored in ctor_field_names.
   Returns None if any field is MISSING.

   [opaque] decides what happens to a field that is untranslatable, or that
   reflects to a term not WELL-SORTED at its declared sort (`history:
   Cons(1, Nil)`, `name: n` for a `String` `n`).  Without it — the default, and
   what the postcondition side keeps — the whole record reflects to None and
   the check is skipped, losing the perfectly checkable sibling fields with it.
   With it, the offending field is replaced by a FRESH constant that [opaque]
   mints and declares AT THAT FIELD'S DECLARED SORT.

   Why the substitution is sound *for the call-site check only*.  The stand-in
   carries no assumptions whatsoever, so it denotes an arbitrary value of the
   right sort and nothing can be concluded about it in either direction.  The
   call-site decision procedure reports only when `¬goal` is VERIFIED — valid
   for every assignment — so a goal that depends on the stand-in is never
   reported (nor ever discharged), while a goal that depends only on the
   reflected siblings is decided exactly as if the record had been fully known.

   It must NOT be used by [check_post]: with a concrete record in scope that
   check switches to "a SAT model is a definite violation", and a model free to
   assign the stand-in a bad value would then be reported as a counterexample
   even though the real field holds a fine value — a false positive.  Hence the
   argument is optional and the return side never passes it. *)
let reflect_record_literal ?(opaque : (Smt.sort -> Smt.term) option)
    (sort_name : string) (fields : (A.name * A.expr) list)
    (reflect_scalar : A.expr -> Smt.term option) : Smt.term option =
  match Hashtbl.find_opt adt_ctors sort_name with
  | Some [ ctor ] ->
    (match Hashtbl.find_opt ctor_field_names ctor, Hashtbl.find_opt ctor_field_sorts ctor with
     | Some fname_list, Some fsorts when List.length fname_list = List.length fsorts ->
       let field_map = List.map (fun (n, e) -> (n.A.txt, e)) fields in
       let in_order =
         List.filter_map (fun fname -> List.assoc_opt fname field_map) fname_list
       in
       if List.length in_order <> List.length fname_list then None
       else
         let reflected =
           List.map2
             (fun e s ->
               match reflect_scalar e with
               | Some t when term_fits_sort s t -> Some t
               | _ -> Option.map (fun mk -> mk s) opaque)
             in_order fsorts
         in
         if List.exists Option.is_none reflected then None
         else Some (Smt.App (ctor, List.filter_map Fun.id reflected))
     | _ -> None)
  | _ -> None

(* ── Reflect a scalar actual argument into (term, decls, assumptions) ─────── *)
let reflect_scalar ~(postcond : string -> (string * A.expr) option) (sc : scope)
    (actual : A.expr)
  : (Smt.term * (string * Smt.sort) list * Smt.term list) option =
  (* Reflect an expression with no scope help — also the fallback for a call
     whose callee has no usable postcondition. *)
  let plain e =
    match smt_of ~resolve_var:(fun _ -> None) ~resolve_measure:(fun _ _ -> None) e with
    | Some t -> Some (t, [], [])
    | None -> None
  in
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
  (* A direct named call: stand its result up as a fresh constant carrying the
     callee's declared postcondition.  `.` is a legal SMT-LIB simple-symbol
     character, so a qualified name needs no mangling. *)
  | A.EApp (A.EVar { A.txt = fname; _ }, _, _) ->
    (match postcond fname with
     | Some (b, q) ->
       incr ret_ctr;
       let nm = Printf.sprintf "%s$ret%d" fname !ret_ctr in
       let c = Smt.Const nm in
       let rv n = if n = b || n = "_" then Some c else None in
       let assumptions =
         match smt_of ~resolve_var:rv ~resolve_measure:(fun _ _ -> None) q with
         | Some qa -> [ qa ]
         | None -> []
       in
       Some (c, [ (nm, Smt.SInt) ], assumptions)
     | None -> plain actual)
  | _ -> plain actual

(* The registered ADT sort a constructor belongs to.  None when the name is
   unknown OR when it is ambiguous across two registered ADTs (March allows the
   same bare constructor name in two modules): an ambiguous tag identifies no
   particular datatype, so the tester says nothing definite and is skipped. *)
let sort_of_ctor (ctor : string) : string option =
  match
    Hashtbl.fold
      (fun sort ctors acc -> if List.mem ctor ctors then sort :: acc else acc)
      adt_ctors []
  with
  | [ s ] -> Some s
  | _ -> None

(* ── Check one refined parameter at a call site ──────────────────────────── *)
(* [path] is the path context: conditions known true here, each tagged with
   whether it is negated (the else-branch of an `if`). *)
let check_call ~root errctx ~span ~(postcond : string -> (string * A.expr) option)
    (sg : fn_sig) (args : A.expr list)
    (path : (A.expr * bool) list) (rp : rparam) (sc : scope) (re : recenv) : unit =
  let name_pos = List.mapi (fun i n -> (n, i)) sg.param_names in
  (* A CALLER-scope name whose declared type is a record (see [recenv]).  Such a
     name is declared into the record's datatype sort by [path_resolve_field];
     every other producer must therefore refuse to declare it `Int`, or the VC
     declares one symbol at two sorts and z3 answers with an `(error …)` that
     desynchronises the shared `z3 -in` channel — silently disabling refinement
     checking for the rest of the compilation. *)
  let is_recvar name = List.mem_assoc name re in
  let actual_of_name name =
    match List.assoc_opt name name_pos with
    | Some i -> List.nth_opt args i
    | None -> None
  in
  (* Is the callee parameter called [name] declared String? *)
  let str_pos = List.mapi (fun i b -> (i, b)) sg.param_str in
  let name_is_str name =
    match List.assoc_opt name name_pos with
    | Some i -> (match List.assoc_opt i str_pos with Some b -> b | None -> false)
    | None -> false
  in
  match List.nth_opt args rp.idx with
  | None -> ()
  | Some self_actual ->
    let decls = ref [] and assume = ref [] in
    (* Attach the (expensive) datatype/quantifier preamble ONLY to VCs that
       actually reference an axiomatised measure; a plain Int/Bool VC pays no
       axiom cost.  Set when [resolve_measure] reflects an axiom measure. *)
    let uses_axiom = ref false in
    (* ADT sorts a constructor tester ranged over; their datatype declarations
       are attached to this VC's preamble. *)
    let adt_sorts = ref [] in
    (* ── Per-VC string state ────────────────────────────────────────────────
       [str_names] records every constant declared into the `Str` sort, so a
       later reflection of the same March variable agrees on its sort and
       [resolve_measure_app] can tell a string term from a list term.
       [str_lit_tbl] maps each DISTINCT literal to its constant, so the same
       literal reflects to the same symbol and distinct literals are asserted
       distinct.  [uses_string] decides whether this VC gets the string
       preamble — the same "attach only when actually used" discipline the
       measure preamble follows. *)
    let str_lit_tbl : (string, string) Hashtbl.t = Hashtbl.create 4 in
    let str_names : (string, unit) Hashtbl.t = Hashtbl.create 4 in
    let uses_string = ref false in
    let declare_str_const c =
      if not (Hashtbl.mem str_names c) then begin
        Hashtbl.replace str_names c ();
        uses_string := true;
        decls := (c, Smt.SData str_sort) :: !decls
      end
    in
    (* A string literal's constant, minted on first sight.  Literal text is NOT
       embedded in the symbol (arbitrary text is not a legal SMT-LIB symbol); an
       index is used instead.  Two facts are asserted: the pinned length, and
       distinctness from every literal already seen.

       LENGTH IS IN BYTES.  March's `string_length` builtin is `String.length`
       in the interpreter and an alias for `march_string_byte_length` in native
       codegen — the language has no codepoint-length primitive at all, so bytes
       is not a conservative guess, it is the definition.  OCaml's
       [String.length] over the already-unescaped literal is exactly that. *)
    let str_lit_const (s : string) : Smt.term option =
      if not (string_len_available ()) then None
      else
        match Hashtbl.find_opt str_lit_tbl s with
        | Some c -> Some (Smt.Const c)
        | None ->
          let c = Printf.sprintf "$str%d" (Hashtbl.length str_lit_tbl) in
          Hashtbl.replace str_lit_tbl s c;
          declare_str_const c;
          assume :=
            Smt.Eq (Smt.App (strlen_fn, [ Smt.Const c ]), Smt.IntLit (String.length s))
            :: !assume;
          Hashtbl.iter
            (fun s' c' ->
              if s' <> s then assume := Smt.Ne (Smt.Const c, Smt.Const c') :: !assume)
            str_lit_tbl;
          Some (Smt.Const c)
    in
    (* Reflect a STRING-typed actual.  Side effects (declarations, assumptions)
       must happen once per key, hence the memo table.  A refined string local
       carries its own predicate in as an assumption — that is what makes
       `fn f(s : {String | len(_) > 0}) … nonempty(s)` provable rather than
       merely unprovable-and-skipped. *)
    let str_reflected : (string, Smt.term option) Hashtbl.t = Hashtbl.create 4 in
    let reflect_str (key : string) (e : A.expr) : Smt.term option =
      match Hashtbl.find_opt str_reflected key with
      | Some cached -> cached
      | None ->
        let result =
          if not (string_len_available ()) then None
          else
            match e with
            | A.ELit (A.LitString s, _) -> str_lit_const s
            | A.EVar { A.txt = x; _ } ->
              declare_str_const x;
              let xc = Smt.Const x in
              (match List.assoc_opt x sc with
               | Some (b, q, Some srt) when srt = str_sort ->
                 let rv n = if n = b || n = "_" then Some xc else None in
                 let rm m n =
                   if m = "len" && (n = b || n = "_") then Some (Smt.App (strlen_fn, [ xc ]))
                   else None
                 in
                 (match smt_of ~resolve_var:rv ~resolve_measure:rm
                          ~resolve_str_lit:str_lit_const q with
                  | Some qa -> assume := qa :: !assume
                  | None -> ())
               | _ -> ());
              Some xc
            (* Any other string-producing expression (a concatenation, a call)
               is opaque to this encoding — skip rather than guess. *)
            | _ -> None
        in
        Hashtbl.replace str_reflected key result;
        result
    in
    let absorb = function
      | Some (t, d, a) -> decls := d @ !decls; assume := a @ !assume; Some t
      | None -> None
    in
    (* Reflection must be stable per binder within one [check_call]: two
       syntactic occurrences of the same binder (or the same cross-argument
       parameter name) in a predicate denote the same value, so they must
       resolve to the same SMT constant.  [reflect_scalar]'s call-argument
       branch mints a *fresh* constant on every invocation (via [ret_ctr]),
       so without memoizing here a predicate like [_ != 4] combined with
       [n > 3 && n < 5] would bind each `_`/`n` occurrence to a different
       constant and lose the contradiction between them.  Caching the
       reflection (not just its absorption) fixes that; re-[absorb]ing an
       identical reflection is harmless (decls are deduplicated before the
       VC is built, and a repeated assumption is the same term). *)
    let reflect_cache
      : (string, (Smt.term * (string * Smt.sort) list * Smt.term list) option) Hashtbl.t =
      Hashtbl.create 8
    in
    let reflect_cached key compute =
      match Hashtbl.find_opt reflect_cache key with
      | Some cached -> cached
      | None ->
        let result = compute () in
        Hashtbl.add reflect_cache key result;
        result
    in
    (* ── The record-refined-parameter path ──────────────────────────────────
       A record actual is NOT a scalar: it must become a datatype term so the
       predicate's `v.field` projections select from it.  We recognise exactly
       two shapes and SKIP everything else:

         - a record literal `{ port: 0 }`  -> the constructor applied to its
           field terms, reordered into declaration order.  If ANY field is
           itself unreflectable — or reflects to a term that would not be
           WELL-SORTED at that field's declared sort — the whole record
           reflects to None: a partial or ill-sorted reflection would either
           assert facts about fields we cannot see, or build a VC z3 answers
           with an `(error …)`.
         - a variable holding a record-refined local/param -> an opaque
           datatype constant carrying that local's own predicate as an
           assumption, which is what lets a refinement forward through a call.

       An unrefined record variable, a call, a field access, … all yield None
       and the call is skipped — the definite-failure stance.

       Note this path deliberately keeps the SAME two-discharge decision
       procedure as the Int path (report only when ¬goal is Verified).  It does
       NOT use check_post's report-on-SAT branch, so a record fact that merely
       fails to establish the callee's precondition stays silent. *)
    let scalar_arg e = absorb (reflect_scalar ~postcond sc e) in
    (* A stand-in for a record field we cannot reflect (see
       [reflect_record_literal]).  Fresh per occurrence, declared at the field's
       DECLARED sort, and given NO assumption — so it denotes an arbitrary value
       and the call-site's "report only when ¬goal is Verified" rule can never
       conclude anything from it.  Its only job is to keep the VC well-sorted so
       the record's CHECKABLE fields survive a sibling we cannot see. *)
    let opaque_ctr = ref 0 in
    let opaque_field (s : Smt.sort) : Smt.term =
      incr opaque_ctr;
      let nm = Printf.sprintf "fld$op%d" !opaque_ctr in
      decls := (nm, s) :: !decls;
      Smt.Const nm
    in
    let record_self sort_name : Smt.term option =
      match self_actual with
      | A.ERecord (fields, _) ->
        reflect_record_literal ~opaque:opaque_field sort_name fields scalar_arg
      | A.EVar { A.txt = x; _ } ->
        (match List.assoc_opt x sc with
         | Some (b, q, Some s) when s = sort_name ->
           let c = Smt.Const x in
           decls := (x, Smt.SData sort_name) :: !decls;
           (* The carried predicate must resolve `b.field` against the SAME
              term the goal projects from, or the assumption constrains a
              different value than the one being checked. *)
           let rv n = if n = b || n = "_" then Some c else None in
           let rf = make_field_resolver b sort_name c in
           (match smt_of ~resolve_var:rv ~resolve_measure:(fun _ _ -> None)
                    ~resolve_field:rf q with
            | Some qa -> assume := qa :: !assume
            (* Untranslatable predicate: the constant stays unconstrained, so
               neither the goal nor its negation can be proven and the call is
               skipped.  Sound, just weaker. *)
            | None -> ());
           Some c
         (* An UNREFINED record variable of the right type ([recenv]).  It
            reflects to an opaque constant carrying NO predicate: on its own
            that proves nothing in either direction, so the call is still
            skipped unless the PATH context — a `if c.port >= 1` guard,
            reflected onto this very constant by [path_resolve_field] — settles
            it.  Before this the whole call was skipped, so a guarded call could
            never discharge and a guard that made the call a DEFINITE failure
            was never reported. *)
         | _ ->
           (match List.assoc_opt x re with
            | Some s when s = sort_name ->
              decls := (x, Smt.SData sort_name) :: !decls;
              Some (Smt.Const x)
            | _ -> None))
      | _ -> None
    in
    (* [`Other] = every non-record subject — Int, String and variant ADT — each
       handled by its own resolver below, unchanged.
       [`Skip]   = a RECORD parameter whose actual we cannot reflect; the goal
                   is not even built, so the call is silently skipped. *)
    let mode =
      match rp.sort with
      | Some sort_name when is_record_sort sort_name ->
        (match record_self sort_name with
         | None -> `Skip
         | Some t ->
           (* Seed the ADT preamble so this VC gets the record's
              `declare-datatypes`.  Sharing main's [adt_sorts] machinery (rather
              than emitting a separate record preamble) is what keeps a VC that
              mentions a record AND a tester AND a string free of duplicate sort
              declarations, which z3 rejects inside one push. *)
           if not (List.mem sort_name !adt_sorts) then adt_sorts := sort_name :: !adt_sorts;
           `Record (sort_name, t))
      | _ -> `Other
    in
    (* Resolve a scalar variable IN THE PREDICATE, i.e. in the CALLEE's
       namespace: the refined binder (`_` or its declared name) denotes this
       call's actual argument, and another parameter's name denotes that
       parameter's actual.  Path conditions live in the CALLER's namespace and
       must NOT come through here — see [path_resolve_var]. *)
    let is_self name = name = rp.binder || name = "_" in
    let self_is_str = rp_is_str rp in
    let resolve_var name =
      (* A String-typed subject reflects into the `Str` sort, never `Int`.  The
         choice is driven by a DECLARED type (the refinement's own base type for
         the binder, the callee's parameter type otherwise), never inferred from
         the actual — so an unknown stays unknown instead of being guessed. *)
      match mode with
      (* The refined value is a record: it stands for the datatype term, not
         for anything [reflect_scalar] could produce.  Records and strings are
         disjoint sorts, so this cannot shadow the String path. *)
      | `Record (_, t) when is_self name -> Some t
      | _ ->
      if is_self name && self_is_str then reflect_str "$self" self_actual
      else if (not (is_self name)) && name_is_str name then
        (match actual_of_name name with Some a -> reflect_str name a | None -> None)
      else if is_self name then
        absorb (reflect_cached "$self" (fun () -> reflect_scalar ~postcond sc self_actual))
      else
        match actual_of_name name with
        | Some a -> absorb (reflect_cached name (fun () -> reflect_scalar ~postcond sc a))
        | None ->
          (* a caller-scope variable from the path context *)
          if Hashtbl.mem str_names name then Some (Smt.Const name)
          (* …unless it is a caller-scope RECORD, which lives at a datatype sort.
             Declaring it `Int` here would put one symbol at two sorts; dropping
             the sub-term instead just loses a fact (silence). *)
          else if is_recvar name then None
          else begin
            decls := (name, Smt.SInt) :: !decls;
            Some (Smt.Const name)
          end
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
    (* A constructor tester, in the predicate or in a path condition.  Its
       subject is reflected into the datatype sort the constructor belongs to:
       the refined binder (`_` or its name) stands for THIS call's actual
       argument, another parameter's name for that parameter's actual, and
       anything else — a caller-scope variable, a constructor literal — for
       itself.  [reflect_dt] turns a literal into `(Ctor …)` (so the tester
       decides concretely) and a variable into an opaque datatype constant (so
       an unconstrained value stays unknown and we keep silent). *)
    let resolve_tester ctor arg =
      match sort_of_ctor ctor with
      | None -> None
      | Some adt ->
        let subject =
          match arg with
          | A.EVar { A.txt = x; _ } when x = rp.binder || x = "_" -> self_actual
          | A.EVar { A.txt = x; _ } ->
            (match actual_of_name x with Some a -> a | None -> arg)
          | _ -> arg
        in
        (match reflect_dt adt subject with
         | Some t ->
           if not (List.mem adt !adt_sorts) then adt_sorts := adt :: !adt_sorts;
           Some (Smt.IsCtor (ctor, t))
         | None -> None)
    in
    let resolve_measure m name =
      (* `len` OVERLOAD RESOLUTION.  The string meaning is taken only when the
         subject's DECLARED base type is String — the refinement's own base type
         for the binder, the callee's parameter type for a cross-argument name.
         Everything else falls through to the existing list handling unchanged,
         so list `len` keeps its meaning exactly. *)
      if m = "len" && string_len_available ()
         && ((is_self name && self_is_str) || ((not (is_self name)) && name_is_str name))
      then
        let key = if is_self name then "$self" else name in
        let actual = if is_self name then Some self_actual else actual_of_name name in
        (match actual with
         | Some a -> Option.map (fun t -> Smt.App (strlen_fn, [ t ])) (reflect_str key a)
         | None -> None)
      else if is_axiom_measure m then (
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
    (* [resolve_field] turns the predicate's `v.port` into the record's SMT
       selector applied to the term standing for the refined value.  Only the
       record path installs one; every other path keeps [smt_of]'s default
       (which returns None, dropping any field-bearing predicate). *)
    let resolve_field =
      match mode with
      | `Record (sort_name, t) -> make_field_resolver rp.binder sort_name t
      | `Other | `Skip -> fun _ _ -> None
    in
    (* A measure applied to a non-variable term — `len(v.history)` where
       `v.history` is a field selector.  Mirrors check_post: evaluate
       concretely when we can (a concrete answer needs no quantified axioms,
       which is what keeps Z3 from returning `unknown`), otherwise fall back
       to a symbolic constant, or to the axiomatised application. *)
    let mapp_ctr = ref 0 in
    (* Memoized per (measure, term): two occurrences of `len(v.history)` in one
       predicate denote the same value and must share a constant, or a
       contradiction between them is lost. *)
    let mapp_cache : (string, Smt.term option) Hashtbl.t = Hashtbl.create 8 in
    let resolve_measure_app_record m arg_term =
      let key = m ^ "|" ^ Smt.render arg_term in
      match Hashtbl.find_opt mapp_cache key with
      | Some cached -> cached
      | None ->
        let result =
          if m = "len" then
            match concrete_len arg_term with
            | Some n -> Some (Smt.IntLit n)
            | None ->
              incr mapp_ctr;
              let nm = Printf.sprintf "len$app%d" !mapp_ctr in
              decls := (nm, Smt.SInt) :: !decls;
              assume := Smt.Ge (Smt.Const nm, Smt.IntLit 0) :: !assume;
              Some (Smt.Const nm)
          else if is_axiom_measure m then
            match concrete_measure_app m arg_term with
            | Some n -> Some (Smt.IntLit n)
            | None ->
              (* No concrete answer: use the axiomatised application, which
                 makes this VC need the quantified-axiom preamble. *)
              uses_axiom := true;
              Some (Smt.App (m, [ arg_term ]))
          else begin
            incr mapp_ctr;
            let nm = Printf.sprintf "%s$app%d" m !mapp_ctr in
            decls := (nm, Smt.SInt) :: !decls;
            if is_nonneg_measure m then
              assume := Smt.Ge (Smt.Const nm, Smt.IntLit 0) :: !assume;
            Some (Smt.Const nm)
          end
        in
        Hashtbl.add mapp_cache key result;
        result
    in
    (* `len(<expr>)` where the expression itself reflected to a term.  Two
       disjoint meanings, tried in order:
         - STRING: the term is one of OUR declared `Str` constants (e.g. an
           inline `len("abc")`) — main's rule, unchanged;
         - RECORD: the term is a field selector such as `len(v.history)` —
           evaluated concretely when possible, otherwise a symbolic constant or
           the axiomatised application.
       They cannot both match one term (a `Str` constant is never a selector),
       so the order is arbitrary and neither changes the other's behaviour. *)
    let resolve_measure_app m arg =
      match m, arg with
      | "len", Smt.Const c when string_len_available () && Hashtbl.mem str_names c ->
        Some (Smt.App (strlen_fn, [ arg ]))
      | _ ->
        (match mode with
         | `Record _ -> resolve_measure_app_record m arg
         | `Other | `Skip -> None)
    in
    (* Pre-reflect a String binder before the path conditions are translated, so
       a caller variable mentioned by a guard is already known to be `Str`-sorted
       and both occurrences agree on a sort. *)
    if self_is_str then ignore (resolve_var rp.binder);
    (* ── Caller-namespace resolvers, for the PATH CONTEXT only ─────────────
       A path condition was collected at the call site, so every name in it is
       a CALLER variable and denotes itself.  Routing it through the predicate
       resolvers above (which consult [rp.binder] and [actual_of_name]) would
       silently re-point it at the callee's actuals whenever the caller happens
       to use the same identifier as a callee parameter or as the refinement's
       named binder — reporting `y = None` from a fact about an unrelated
       caller `o`.  A caller variable therefore always reflects to `Const name`
       — the very term [reflect_scalar]/[reflect_dt] give an `EVar` actual, so
       when the argument really IS that variable the two sides still meet on
       the same SMT symbol and the narrowing keeps working. *)
    let path_resolve_var name =
      (* A name already declared into the `Str` sort denotes ITSELF at that
         sort.  [reflect_scalar] would unconditionally declare it `Int`, and a
         VC declaring one symbol at two sorts makes z3 emit an error line — the
         failure mode that desynchronises the shared `z3 -in` channel and
         silently switches refinement checking off for the rest of the
         compilation.  So the string sort wins here, exactly as it does in
         [resolve_var]'s caller-scope fallback. *)
      if Hashtbl.mem str_names name then Some (Smt.Const name)
      (* Same rule for a caller-scope RECORD: it is declared at its datatype
         sort by [path_resolve_field], so it must never also be reflected as a
         scalar.  Returning None drops the sub-term — and with it the whole
         condition — which only loses a fact. *)
      else if is_recvar name then None
      else
        absorb
          (reflect_cached ("$path$" ^ name) (fun () ->
               reflect_scalar ~postcond sc (A.EVar { A.txt = name; A.span })))
    in
    (* `c.port` in a PATH CONDITION.  The name is a CALLER variable, so it
       denotes itself: the record's SMT selector applied to `Const c` — the very
       term [record_self] gives a record actual that IS that variable, so a
       guard and the goal meet on one constant.  A name outside [recenv] yields
       None and the condition is dropped (sound, just weaker). *)
    let path_resolve_field varname fname =
      match List.assoc_opt varname re with
      | None -> None
      | Some sort_name ->
        let c = Smt.Const varname in
        (match make_field_resolver varname sort_name c varname fname with
         | None -> None
         | Some t ->
           decls := (varname, Smt.SData sort_name) :: !decls;
           if not (List.mem sort_name !adt_sorts) then adt_sorts := sort_name :: !adt_sorts;
           Some t)
    in
    let path_resolve_measure m name =
      if is_axiom_measure m then (
        uses_axiom := true;
        let adt = Hashtbl.find axiom_measures m in
        decls := (name, Smt.SData adt) :: !decls;
        Some (Smt.App (m, [ Smt.Const name ])))
      else measure_of_var m name
    in
    let path_resolve_tester ctor arg =
      match sort_of_ctor ctor with
      | None -> None
      | Some adt ->
        (match reflect_dt adt arg with
         | Some t ->
           if not (List.mem adt !adt_sorts) then adt_sorts := adt :: !adt_sorts;
           Some (Smt.IsCtor (ctor, t))
         | None -> None)
    in
    (* Translate the path conditions into assumptions (dropping any that fall
       outside the supported fragment — sound, just weaker).  Names resolve in
       the CALLER's namespace; string literals still reflect to this VC's `Str`
       constants so a guard mentioning one lines up with the predicate. *)
    List.iter
      (fun (cond, negated) ->
        match
          smt_of ~resolve_var:path_resolve_var ~resolve_measure:path_resolve_measure
            ~resolve_field:path_resolve_field
            ~resolve_measure_app ~resolve_tester:path_resolve_tester
            ~resolve_str_lit:str_lit_const cond
        with
        | Some t -> assume := (if negated then Smt.Not t else t) :: !assume
        | None -> ())
      path;
    (* [`Skip]: a record parameter whose actual could not be reflected — build
       no goal at all, so neither discharge runs and the call is passed over. *)
    (match
       (match mode with
        | `Skip -> None
        | `Other | `Record _ ->
          smt_of ~resolve_var ~resolve_measure ~resolve_field ~resolve_measure_app
            ~resolve_tester ~resolve_str_lit:str_lit_const rp.pred)
     with
     | None -> ()
     | Some goal when not (wellsorted (Hashtbl.mem str_names) goal) -> ()
     | Some goal ->
       (* de-duplicate decls (a symbol may be requested twice) *)
       let decls =
         List.fold_left
           (fun acc d -> if List.mem d acc then acc else d :: acc)
           [] !decls
       in
       (* A symbol declared into the `Str` sort must NOT also be declared `Int`
          by some other reflection path: z3 rejects the duplicate, and a single
          error line desynchronises the shared `z3 -in` channel, silently
          disabling refinement checking for the remainder of the compilation.
          Every producer is supposed to consult [str_names] first; this is the
          one place that can guarantee it, so it is enforced here as well.  Any
          term that still refers to such a symbol as an Int is ill-sorted and
          is dropped by [wellsorted] below. *)
       let decls =
         List.filter
           (fun (n, s) -> not (s = Smt.SInt && Hashtbl.mem str_names n))
           decls
       in
       (* Drop ill-sorted assumptions.  Weakening the hypothesis set can only
          make BOTH discharges harder, so this can only turn a report into a
          skip — never the reverse. *)
       let assumptions = List.filter (wellsorted (Hashtbl.mem str_names)) !assume in
       let vc = { Smt.decls; assumptions; goal } in
       (* Attach the (expensive) axiom preamble only when an axiomatised
          measure was reflected, the datatype declarations only when a
          constructor tester was, and the `$Str` sort only when a string was.
          When measure and ADT both fire, the measure preamble already declares
          `Elem` and its own covered sorts, so the ADT half must not redeclare
          them — z3 rejects a duplicate sort inside one push, and one such
          error line desynchronises the shared solver channel.  The string
          preamble declares only `$Str`/`$strlen`, names no other preamble can
          produce, so it composes with either or both unconditionally.

          A RECORD subject seeds its sort into [adt_sorts] (see [mode]), so it
          rides this same path and inherits the same deduplication — which is
          what makes a VC mentioning a record AND a tester AND a string emit
          each sort exactly once. *)
       let preamble =
         let m = if !uses_axiom then !measure_preamble else "" in
         let a =
           if !adt_sorts = [] then ""
           else
             adt_vc_preamble
               ~skip:(fun s -> m <> "" && Hashtbl.mem measure_preamble_sorts s)
               ~skip_elem:(m <> "") !adt_sorts
         in
         let s = if !uses_string then string_preamble else "" in
         let ma = match m, a with "", x | x, "" -> x | x, y -> x ^ "\n" ^ y in
         match ma, s with "", x | x, "" -> x | x, y -> x ^ "\n" ^ y
       in
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
  | A.EBlock (es, _) ->
    (match List.rev es with
     | last :: _ ->
       (* A `let` before the tail REBINDS its names, so any fact the path
          context holds about them is about the outer value — retire it
          (see [path_shadow]). *)
       let path =
         List.fold_left
           (fun p e ->
             match e with
             | A.ELet (b, _) -> path_shadow p (pat_binders b.A.bind_pat)
             | _ -> p)
           path es
       in
       tails path last
     | [] -> [ (path, e) ])
  | A.EIf (c, t, el, _) -> tails ((c, false) :: path) t @ tails ((c, true) :: path) el
  | A.ECond (arms, _) -> List.concat_map (fun (c, b) -> tails ((c, false) :: path) b) arms
  | A.EMatch (_, branches, _) ->
    List.concat_map
      (fun (br : A.branch) ->
        let path = path_shadow path (pat_binders br.A.branch_pat) in
        let p = match br.A.branch_guard with Some g -> (g, false) :: path | None -> path in
        tails p br.A.branch_body)
      branches
  | _ -> [ (path, e) ]

(* Facts true throughout the body: each refined param contributes its predicate. *)
(* Returns (decls, assumptions, has_record).
   Int entries: declare an SInt const, reflect predicate over it.
   Record entries: declare a datatype const (SData sort_name), reflect the
   predicate with a field resolver so `s.field` becomes the SMT selector
   applied to the opaque const.  `has_record` is true when any record entry
   is present — signals check_post to include the datatype preamble. *)
let scope_facts (sc : scope) : (string * Smt.sort) list * Smt.term list * bool * bool =
  let has_string =
    List.exists (fun (_, (_, _, sort)) -> sort = Some str_sort) sc
  in
  let ds, asm, has_rec =
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
      (* A String-refined entry declares a `Str` constant and loads its
         predicate, but MUST NOT set [has_rec]: that flag switches check_post
         onto the "a SAT model is a definite violation" path, which is only
         justified when the scope pins a concrete record.  An opaque `Str` pins
         nothing, so flipping it there would be a false-positive engine. *)
      | Some sort_name when sort_name = str_sort ->
        let c = Smt.Const name in
        let ds = (name, Smt.SData str_sort) :: ds in
        let rv n = if n = b || n = "_" then Some c else None in
        let rm m n =
          if m = "len" && string_len_available () && (n = b || n = "_") then
            Some (Smt.App (strlen_fn, [ c ]))
          else None
        in
        (match smt_of ~resolve_var:rv ~resolve_measure:rm q with
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
  in
  (ds, asm, has_rec, has_string)

(* Check one return-position tail against the declared return refinement.

   Returns TRUE only when the tail was POSITIVELY VERIFIED — i.e. the solver
   proved the predicate holds on this path.  Anything else (an unreflectable
   tail, an unreflectable predicate, an `unknown` from the solver, a refutation)
   returns false.  That verdict is what gates postcondition *propagation*
   (see [postcond_of]): only a proven postcondition is a true fact, so only a
   proven one may be assumed at call sites.

   [emit] (default true) controls diagnostics.  The verdict pre-pass runs with
   [~emit:false] so it cannot double-report; the in-walk [check_fn_post] runs
   with the default and is the single reporting site.  The repeated discharge
   is served from the content-addressed VC cache. *)
let check_post ~root errctx ~span ?(record_sort : string option = None)
    ?(fn_name : string option = None) ?(emit = true) (sc : scope)
    (binder : string) (ret_pred : A.expr)
    ((path, tail_e) : (A.expr * bool) list * A.expr) : bool =
  let base_decls, base_assume, scope_has_record, scope_has_string = scope_facts sc in
  let decls = ref base_decls and assume = ref base_assume in
  (* Scope names already declared into the `Str` sort by [scope_facts].  Both
     [var_const] and [resolve_measure] must agree with that sort, or the VC
     declares one symbol at two sorts and Z3 rejects the whole query. *)
  let is_str_scope name =
    List.exists (fun (n, (_, _, sort)) -> n = name && sort = Some str_sort) sc
  in
  let post_measure_ctr = ref 0 in
  (* Set when resolve_measure_app emits App(m, arg) — the VC then needs the full
     measure preamble (axioms + datatypes).  False => type_preamble only suffices
     (no quantified axioms → Z3 answers sat/unsat without returning `unknown`). *)
  let needs_axiom_preamble = ref false in
  let var_const name =
    if is_str_scope name then Some (Smt.Const name)
    else begin decls := (name, Smt.SInt) :: !decls; Some (Smt.Const name) end
  in
  let resolve_measure m name =
    (* `len` over a String-sorted scope name is the string `len`, applied to the
       very constant scope_facts declared — so the param's own predicate and the
       return predicate talk about the same length. *)
    if m = "len" && string_len_available () && is_str_scope name then
      Some (Smt.App (strlen_fn, [ Smt.Const name ]))
    else
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
        (* `Str` is opaque — it has no fields and no selectors. *)
        | None -> rf
        | Some s when s = str_sort -> rf
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
  | None -> false
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
     | None -> false
     | Some goal ->
       let decls =
         List.fold_left (fun acc d -> if List.mem d acc then acc else d :: acc) [] !decls
       in
       let vc = { Smt.decls; assumptions = !assume; goal } in
       let str_pre = if scope_has_string then string_preamble else "" in
       let preamble = str_pre ^
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
        | Refine.Verified -> true
        | first ->
          let emit_error () =
            if emit then begin
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
            end
          in
          if scope_has_record then
            (* With concrete record preconditions in scope, a SAT counterexample
               satisfying those preconditions IS a real violation — report it. *)
            (match first with Refine.Refuted _ -> emit_error () | _ -> ())
          else
            (match Refine.discharge ~root ~preamble { vc with Smt.goal = Smt.Not goal } with
             | Refine.Verified -> emit_error ()
             | _ -> ());
          (* Not [Verified] on the positive goal ⇒ not proven, whatever the
             refutation attempt said. *)
          false))

(* Check every return-position tail of every clause of [fd] against its declared
   return refinement.  Returns true iff ALL of them positively verified (a
   function with no clauses, or a clause with no reachable tail, counts as NOT
   verified — silence is not proof).  [emit] threads through to [check_post]. *)
let check_fn_post_verdict ~root errctx ?(emit = true) (fd : A.fn_def) : bool =
  match return_refine_ext fd with
  | None -> false
  | Some (binder, ret_pred, record_sort) ->
    let clause_ok (c : A.fn_clause) =
      let sc = List.fold_left scope_add_fnparam [] c.A.fc_params in
      let base = match c.A.fc_guard with Some g -> [ (g, false) ] | None -> [] in
      let ts = tails base c.A.fc_body in
      (* Fold (not List.for_all): every tail must be checked so every
         diagnostic is emitted — short-circuiting would hide errors. *)
      ts <> []
      && List.fold_left
           (fun acc t ->
             check_post ~root errctx ~span:c.A.fc_span ~record_sort
               ~fn_name:(Some fd.A.fn_name.A.txt) ~emit sc binder ret_pred t
             && acc)
           true ts
    in
    fd.A.fn_clauses <> []
    && List.fold_left (fun acc c -> clause_ok c && acc) true fd.A.fn_clauses

let check_fn_post ~root errctx (fd : A.fn_def) : unit =
  ignore (check_fn_post_verdict ~root errctx fd)

(* ── Verification gate on postcondition propagation ────────────────────────
   A declared postcondition is only a FACT at a call site if the definition side
   PROVED it.  [check_fn_post] deliberately rejects only a postcondition that can
   never hold, so a merely *unproven* one is legal at the definition — but
   propagated facts are ADDED to the assumption set the call-site VC proves
   against, and a false assumption makes a violation easier to "prove".  An
   unproven postcondition that travelled would therefore be a false-positive
   engine (a stale `{Int | _ < 0}` on a function that returns 6 would flag the
   correct call `takepos(score(5))`).

   So: an unproven postcondition stays legal, it simply does not travel.  This
   pre-pass runs the definition-side check for every refined-return function
   (with diagnostics suppressed) and CLEARS [ret] on every signature that did
   not verify, so [postcond_of] — and hence both propagation sites — see only
   proven facts.

   Why a pre-pass rather than lazy memoization: [postcond_of] is consulted from
   arbitrary call sites during the AST walk, including calls that precede their
   callee's definition and calls that cross module boundaries.  Computing on
   first use would need a key→fn_def index and would still make the *result*
   order-independent only by construction of that index; a pre-pass reuses
   [collect_all_defs]'s own traversal, is order-independent by construction, and
   keeps [visit] unchanged.  Diagnostics are emitted exactly once, later, by
   [check_fn_post] during the walk; the repeated discharge hits the VC cache. *)
let gate_unverified_posts ~root errctx (defs : (string, fn_sig option) Hashtbl.t)
    (decls : A.decl list) : unit =
  let rec go prefix decls =
    List.iter
      (function
        | A.DFn (fd, _) ->
          let key = if prefix = "" then fd.A.fn_name.A.txt else prefix ^ "." ^ fd.A.fn_name.A.txt in
          (match Hashtbl.find_opt defs key with
           | Some (Some sg) when Option.is_some sg.ret ->
             if not (check_fn_post_verdict ~root errctx ~emit:false fd) then
               (* Keep the entry (it must still shadow an outer same-named
                  function for [resolve_call]); drop only the postcondition. *)
               Hashtbl.replace defs key (Some { sg with ret = None })
           | _ -> ())
        | A.DMod (name, _, ds, _) ->
          go (if prefix = "" then name.A.txt else prefix ^ "." ^ name.A.txt) ds
        | _ -> ())
      decls
  in
  go "" decls

(* ── Walk expressions, threading the refined-local scope, the record-typed
   variables ([recenv]) and the path context ─────────────────────────────── *)
let rec visit ~root errctx defs (ctx : rctx) (path : (A.expr * bool) list) (sc : scope)
    (re : recenv) (e : A.expr) : unit =
  let go = visit ~root errctx defs ctx path sc re in
  let go_path p = visit ~root errctx defs ctx p sc re in
  match e with
  | A.EApp (A.EVar { A.txt = fname; _ }, args, sp) ->
    (match resolve_call ctx defs fname with
     | Some (Some sg) ->
       let postcond = postcond_of ctx defs in
       List.iter
         (fun rp -> check_call ~root errctx ~span:sp ~postcond sg args path rp sc re)
         sg.refined
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
         (fun (path, sc, re) e ->
           visit ~root errctx defs ctx path sc re e;
           let path' =
             match e with
             | A.EAssert (p, _) -> (p, false) :: path
             (* A `let` REBINDS its names: retire any fact about them. *)
             | A.ELet (b, _) -> path_shadow path (pat_binders b.A.bind_pat)
             | _ -> path
           in
           let sc' =
             match e with
             | A.ELet (b, _) -> scope_add_binding ~postcond:(postcond_of ctx defs) sc b
             | _ -> sc
           in
           let re' = match e with A.ELet (b, _) -> recenv_add_binding re b | _ -> re in
           (path', sc', re'))
         (path, sc, re) es)
  | A.ELet (b, _) -> go b.A.bind_expr
  | A.ELam (ps, body, _) ->
    let names = List.map (fun (p : A.param) -> p.A.param_name.A.txt) ps in
    visit ~root errctx defs ctx (path_shadow path names)
      (List.fold_left scope_add_param sc ps)
      (List.fold_left recenv_add_param re ps)
      body
  | A.ELetFn (n, ps, _, body, _) ->
    let names = n.A.txt :: List.map (fun (p : A.param) -> p.A.param_name.A.txt) ps in
    let sc = scope_shadow sc [ n.A.txt ] in
    let re = recenv_shadow re [ n.A.txt ] in
    visit ~root errctx defs ctx (path_shadow path names)
      (List.fold_left scope_add_param sc ps)
      (List.fold_left recenv_add_param re ps)
      body
  | A.EMatch (subj, branches, _) ->
    go subj;
    List.iter
      (fun (br : A.branch) ->
        let binders = pat_binders br.A.branch_pat in
        (* A pattern binder shadows a same-named refined outer local. *)
        let sc = scope_shadow sc binders in
        (* …and a same-named fact in the path context, for the same reason. *)
        let path = path_shadow path binders in
        (* …and a same-named record IDENTITY, so an inner binder is not
           reflected as the outer record's SMT constant.  A bare `PatVar`
           binder on a record-typed variable scrutinee then re-enters the env
           under the NEW name: `match d do c -> …` makes `c` the same value as
           `d`, so sharing one constant is correct.  Looked up in the OUTER env
           on purpose — `match c do c -> …` must find the pre-shadow entry. *)
        let re_outer = re in
        let re = recenv_shadow re binders in
        let re =
          match subj, br.A.branch_pat with
          | A.EVar s, A.PatVar n ->
            (match List.assoc_opt s.A.txt re_outer with
             | Some sort -> (n.A.txt, sort) :: re
             | None -> re)
          | _ -> re
        in
        let p = match br.A.branch_guard with Some g -> (g, false) :: path | None -> path in
        (* Constructor-tag narrowing.  Inside a `Ctor(…) ->` arm a VARIABLE
           scrutinee is known to carry that tag, so we push the synthetic path
           condition `is_Ctor(s)` — an ordinary predicate expression, which
           reaches the solver through the existing [smt_of] translation with no
           new plumbing.  Three guards keep it sound:
             - the scrutinee must be a bare variable (any other expression has
               no stable name to attach the fact to → no fact),
             - the pattern head must be an unambiguous registered constructor,
             - the arm must not REBIND the scrutinee's name: matching `y` with
               `Some(x) ->` says nothing about the fresh `x`, so a narrowing
               recorded against a shadowed name would be a false positive. *)
        let p =
          match subj, br.A.branch_pat with
          | A.EVar s, A.PatCon (ctor, _)
            when sort_of_ctor ctor.A.txt <> None && not (List.mem s.A.txt binders) ->
            let sp = s.A.span in
            let tester =
              A.EApp
                ( A.EVar { A.txt = "is_" ^ ctor.A.txt; A.span = sp }
                , [ A.EVar { A.txt = s.A.txt; A.span = sp } ]
                , sp )
            in
            (tester, false) :: p
          | _ -> p
        in
        visit ~root errctx defs ctx p sc re br.A.branch_body)
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
  | A.ELetQ (p, e1, e2, _) ->
    go e1;
    (* `let? p = e1` binds p's names in the Ok payload before continuing into
       e2 — a binding construct exactly like ELet/ELam/EMatch, so it must
       shadow any same-named outer refined local before e2 is visited. *)
    let binders = pat_binders p in
    let sc = scope_shadow sc binders in
    let re = recenv_shadow re binders in
    visit ~root errctx defs ctx (path_shadow path binders) sc re e2
  | A.EDbg (Some e, _) -> go e
  | A.ELit _ | A.EVar _ | A.EHole _ | A.EResultRef _ | A.EDbg (None, _) -> ()

(* ── Predicate-vocabulary warning ──────────────────────────────────────────
   A refinement predicate that calls a name [known_predicate_fn] does not
   recognize is never reflected into an SMT query — the definite-failure
   stance simply skips it, so the contract silently enforces nothing.  This
   walk finds every `{T | pred}` in the module (parameter, return, and local
   `let`-binding refinements — anywhere `A.TyRefine` can appear) and warns
   once per unrecognized applied name.

   Must run AFTER [registered_measures] is populated (see [check_module]):
   otherwise every user `@[measure]` looks unrecognized and warns spuriously. *)
let warn_predicate_expr (errctx : Err.ctx) (e : A.expr) : unit =
  let rec go (e : A.expr) =
    match e with
    | A.EApp (A.EVar { A.txt = f; _ }, args, span) ->
      if not (known_predicate_fn f) then
        Err.warning errctx ~span
          (Printf.sprintf
             "`%s` is not a measure or known predicate, so this refinement is not checked. \
              Annotate the function `@[measure]`, or use a supported predicate."
             f);
      List.iter go args
    | A.EApp (f, args, _) -> go f; List.iter go args
    | A.ETuple (es, _) | A.ECon (_, es, _) | A.EAtom (_, es, _) -> List.iter go es
    | A.EAnnot (e, _, _) -> go e
    | A.ELit _ | A.EVar _ -> ()
    | _ -> ()
  in
  go e

let rec warn_predicate_ty (errctx : Err.ctx) (t : A.ty) : unit =
  match t with
  | A.TyRefine (base, _binder, pred) ->
    warn_predicate_ty errctx base;
    warn_predicate_expr errctx pred
  | A.TyCon (_, args) -> List.iter (warn_predicate_ty errctx) args
  | A.TyArrow (a, b) -> warn_predicate_ty errctx a; warn_predicate_ty errctx b
  | A.TyTuple ts -> List.iter (warn_predicate_ty errctx) ts
  | A.TyRecord fs -> List.iter (fun (_, t) -> warn_predicate_ty errctx t) fs
  | A.TyLinear (_, t) -> warn_predicate_ty errctx t
  | A.TyChan _ | A.TyVar _ | A.TyNat _ | A.TyNatOp _ -> ()

let rec warn_predicate_expr_tys (errctx : Err.ctx) (e : A.expr) : unit =
  let ge = warn_predicate_expr_tys errctx in
  match e with
  | A.ELit _ | A.EVar _ | A.EHole _ | A.EResultRef _ -> ()
  | A.EApp (f, args, _) -> ge f; List.iter ge args
  | A.ECon (_, es, _) | A.EAtom (_, es, _) | A.ETuple (es, _) -> List.iter ge es
  | A.ELam (ps, body, _) ->
    List.iter (fun (p : A.param) -> Option.iter (warn_predicate_ty errctx) p.A.param_ty) ps;
    ge body
  | A.EBlock (es, _) -> List.iter ge es
  | A.ELet (b, _) ->
    Option.iter (warn_predicate_ty errctx) b.A.bind_ty;
    ge b.A.bind_expr
  | A.EMatch (e, brs, _) ->
    ge e;
    List.iter
      (fun (br : A.branch) ->
        Option.iter ge br.A.branch_guard;
        ge br.A.branch_body)
      brs
  | A.ERecord (fs, _) -> List.iter (fun (_, e) -> ge e) fs
  | A.ERecordUpdate (e, fs, _) -> ge e; List.iter (fun (_, e) -> ge e) fs
  | A.EField (e, _, _) -> ge e
  | A.EIf (c, t, e, _) -> ge c; ge t; ge e
  | A.ECond (arms, _) -> List.iter (fun (c, b) -> ge c; ge b) arms
  | A.EPipe (a, b, _) -> ge a; ge b
  | A.EAnnot (e, t, _) -> ge e; warn_predicate_ty errctx t
  | A.ESend (a, b, _) -> ge a; ge b
  | A.ESpawn (e, _) -> ge e
  | A.EDbg (eo, _) -> Option.iter ge eo
  | A.ELetFn (_, ps, ret_ty, body, _) ->
    List.iter (fun (p : A.param) -> Option.iter (warn_predicate_ty errctx) p.A.param_ty) ps;
    Option.iter (warn_predicate_ty errctx) ret_ty;
    ge body
  | A.ELetQ (_, e1, e2, _) -> ge e1; ge e2
  | A.EAssert (e, _) -> ge e
  | A.ESigil (_, e, _) -> ge e

let rec warn_predicate_decls (errctx : Err.ctx) (decls : A.decl list) : unit =
  List.iter
    (function
      | A.DFn (fd, _) ->
        Option.iter (warn_predicate_ty errctx) fd.A.fn_ret_ty;
        List.iter
          (fun (c : A.fn_clause) ->
            List.iter
              (function
                | A.FPNamed p | A.FPDefault (p, _) ->
                  Option.iter (warn_predicate_ty errctx) p.A.param_ty
                | A.FPPat _ -> ())
              c.A.fc_params;
            warn_predicate_expr_tys errctx c.A.fc_body)
          fd.A.fn_clauses
      | A.DMod (_, _, ds, _) -> warn_predicate_decls errctx ds
      | _ -> ())
    decls

let visit_fn ~root errctx defs (ctx : rctx) (fd : A.fn_def) : unit =
  check_fn_post ~root errctx fd;
  List.iter
    (fun (c : A.fn_clause) ->
      let sc = List.fold_left scope_add_fnparam [] c.A.fc_params in
      let re = List.fold_left recenv_add_fnparam [] c.A.fc_params in
      let path = match c.A.fc_guard with Some g -> [ (g, false) ] | None -> [] in
      visit ~root errctx defs ctx path sc re c.A.fc_body)
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
  (* Reset per-module so the SMT constant names a VC is built from are a
     function of the module alone.  Without this the counter drifts across
     repeated [check_module] calls in one process (the test binary today; an
     LSP/REPL embedding tomorrow) and every VC mentioning a propagated
     postcondition misses the content-addressed VC cache forever. *)
  ret_ctr := 0;
  (* Registering the module's (and the built-in) ADTs is NOT part of the
     measure-axiom machinery [measure_axioms] gates: constructor-tag
     refinements build their own small datatype preamble per VC and pay no
     quantifier cost.  Leaving these inside the guard emptied [adt_ctors] under
     `--no-measure-axioms`, which made `is_Some` look like unknown vocabulary
     and produced a warning that is simply false. *)
  register_builtin_adts ();
  register_adt_names m.A.mod_decls;
  register_field_sorts m.A.mod_decls;
  if measure_axioms then begin
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
  (* Only POSITIVELY VERIFIED postconditions may be assumed at call sites. *)
  gate_unverified_posts ~root errctx defs m.A.mod_decls;
  (* Always walk: a function may have a refined *return* (postcondition) even
     with no refined parameters, so it won't appear in [defs]. *)
  visit_decls ~root errctx defs rctx0 m.A.mod_decls;
  (* Vocabulary warning: runs last so [registered_measures] (set at the top of
     this function) is already populated — otherwise a user `@[measure]`
     would look unrecognized and warn spuriously. *)
  warn_predicate_decls errctx m.A.mod_decls
