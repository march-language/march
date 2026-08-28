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

(* Table of contents — the § markers below are greppable:
     grep -n '§' lib/refinecheck/refine_check.ml

     §1  Refined parameters and base-type classification
     §2  SMT sorts: strings, scalars, measures, well-sortedness
     §3  Predicate scope and parameter substitution
     §4  Function signatures, measures, and stdlib-provided names
     §5  ADT and record sorts: registry and SMT preamble builders
     §6  AST traversal helpers and measure gating
     §7  Reflection: March expressions into SMT terms
     §8  Rendering: predicates, models, counterexamples
     §9  Scope — the refined bindings in scope
     §10 The other fact channels: path, launder, recenv, cbenv
     §11 Signature extraction and definition collection
     §12 Name resolution: module paths, aliases, call targets
     §13 Reflecting actual arguments: fields, records, scalars
     §14 Verdict state and withdrawal diagnostics
     §15 check_call — precondition checking at a call site
     §16 Postcondition checking
     §17 Postconditions by induction
     §18 Function-level postcondition entry points and gating
     §19 The visit traversal
     §20 Refinement-placement warnings
     §21 The declaration walk
     §22 Registration and stdlib-shape validation
     §23 Entry point: check_module

   §15 is `check_call`, 1,361 lines and the single largest thing here;
   §16-§18 are its postcondition counterpart. *)


(* ── §1–§6 moved to [Refine_encode] ───────────────────────────────────────
   The four module aliases (A, Smt, Refine, Err) moved with the band and
   arrive through the include, so they are no longer declared above.
   The SMT encoding and sort discipline moved VERBATIM into [Refine_encode].
   [include], not aliases: that band owns 16 of this pass's 20 mutable cells
   and they are written from the far end of this file, so the SAME ref cell
   must be in scope here — see [Refine_encode]'s header. *)
include Refine_encode

(* =================================================================
   §7  Reflection: March expressions into SMT terms
   ================================================================= *)

(* ── Translate the decidable predicate fragment to an SMT term ────────────── *)
(* [resolve_var] maps a scalar variable to its SMT term; [resolve_measure]
   maps a (measure-name, argument-name) to its measure term.  None => outside
   the supported Int/Bool linear fragment. *)
(* ── Float constant folding ────────────────────────────────────────────────
   The VALUE of an expression built only from float literals and the float
   operators.  `0.0 -. 1.0` is how March spells the negative literal `-1.0`, so
   without this an obviously-violating argument would be untranslatable and the
   call skipped.

   Deliberately literal-only.  SYMBOLIC float arithmetic (`_ +. 1.0`, where one
   operand is the refined binder) is OUT of scope: modelling it needs Z3's
   rounding-mode surface, and this returns [None] for it, which makes the whole
   predicate untranslatable and the check silently skipped.  Skipping costs
   completeness; guessing at rounding would cost correctness.

   Division by zero yields [None] rather than an infinity — an infinity has no
   SMT-LIB decimal form, and inventing one would be a fact nobody stated. *)
let rec float_const_of (e : A.expr) : float option =
  let bin op a b =
    match float_const_of a, float_const_of b with
    | Some x, Some y -> op x y
    | _ -> None
  in
  match e with
  | A.ELit (A.LitFloat f, _) -> Some f
  | A.EAnnot (inner, _, _) -> float_const_of inner
  | A.EApp (A.EVar { A.txt = "+."; _ }, [ a; b ], _) -> bin (fun x y -> Some (x +. y)) a b
  | A.EApp (A.EVar { A.txt = "-."; _ }, [ a; b ], _) -> bin (fun x y -> Some (x -. y)) a b
  | A.EApp (A.EVar { A.txt = "*."; _ }, [ a; b ], _) -> bin (fun x y -> Some (x *. y)) a b
  | A.EApp (A.EVar { A.txt = "/."; _ }, [ a; b ], _) ->
    bin (fun x y -> if y = 0.0 then None else Some (x /. y)) a b
  | A.EApp (A.EVar { A.txt = "negate"; _ }, [ a ], _) ->
    Option.map (fun x -> -.x) (float_const_of a)
  | _ -> None

(* A folded float value as an SMT term, or [None] when it has no exact
   plain-decimal form (see [Smt.float_decimal]). *)
let float_lit_term (f : float) : Smt.term option =
  Option.map (fun (neg, d) -> Smt.FloatLit (neg, d)) (Smt.float_decimal f)

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
  (* A float literal, and float arithmetic over literals ONLY, folded to one.
     A `+.` with a non-literal operand falls through to [None] here, which makes
     the enclosing predicate untranslatable — the documented skip for symbolic
     float arithmetic. *)
  | A.ELit (A.LitFloat _, _)
  | A.EApp (A.EVar { A.txt = "+." | "-." | "*." | "/."; _ }, [ _; _ ], _) ->
    (match float_const_of e with Some f -> float_lit_term f | None -> None)
  | A.EApp (A.EVar { A.txt = "negate"; _ }, [ a ], _) when float_const_of a <> None ->
    (match float_const_of e with Some f -> float_lit_term f | None -> None)
  (* A string literal reflects to its per-VC constant, when the caller supplies
     a table.  Callers that cannot model strings leave [resolve_str_lit] at its
     default and the literal stays untranslatable — i.e. skipped. *)
  | A.ELit (A.LitString s, _) -> resolve_str_lit s
  (* A measure application m(e): m(var) reflects to a consistent measure symbol;
     m(expr) is evaluated via resolve_measure_app (e.g. concrete_len for a list);
     len(list-literal) is computed concretely without needing resolve_measure_app. *)
  | A.EApp (A.EVar { A.txt = m0; _ }, [ a ], _) when is_measure_app m0 ->
    (* One normalization point for BOTH sides: a path condition and a predicate
       are translated by this same function, so aliasing here is what makes
       `List.length(ys) > 0` and `len(_) > 0` land on the same SMT symbol. *)
    let m = measure_name m0 in
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

(* =================================================================
   §8  Rendering: predicates, models, counterexamples
   ================================================================= *)

(* User-facing infix rendering of a predicate (best-effort). *)
let rec pred_str (e : A.expr) : string =
  let binop op a b = pred_str a ^ " " ^ op ^ " " ^ pred_str b in
  match e with
  | A.ELit (A.LitInt n, _) -> string_of_int n
  | A.ELit (A.LitBool b, _) -> if b then "true" else "false"
  (* `%h`-free rendering that always keeps the point, so `{Float | _ != 0.0}`
     reads back as it was written rather than as `<predicate>`. *)
  | A.ELit (A.LitFloat f, _) ->
    let s = Printf.sprintf "%.12g" f in
    if String.exists (fun c -> c = '.' || c = 'e' || c = 'E') s then s else s ^ ".0"
  (* Rendering keeps the name AS WRITTEN — an aliased `List.length(_)` reads
     back as `List.length(_)`, not as the `len` it was normalized to. *)
  | A.EApp (A.EVar { A.txt = m; _ }, [ a ], _) when is_measure_app m || ctor_of_tester m <> None ->
    m ^ "(" ^ pred_str a ^ ")"
  | A.ECon ({ A.txt = ctor; _ }, [], _) -> ctor
  | A.ECon ({ A.txt = ctor; _ }, args, _) ->
    ctor ^ "(" ^ String.concat ", " (List.map pred_str args) ^ ")"
  | A.EVar { A.txt; _ } -> txt
  | A.EField (recv, { A.txt = fname; _ }, _) -> pred_str recv ^ "." ^ fname
  | A.EApp (A.EVar { A.txt = ("&&" | "||" | ">=" | "<=" | ">" | "<" | "==" | "!="
                             | "+" | "-" | "*" | "+." | "-." | "*." | "/.") as op; _ },
            [ a; b ], _) ->
    binop op a b
  | A.EApp (A.EVar { A.txt = "not"; _ }, [ a ], _) -> "!" ^ pred_str a
  | A.EApp (A.EVar { A.txt = "negate"; _ }, [ a ], _) -> "-" ^ pred_str a
  (* Any other application of a plain IDENTIFIER — an unrecognised predicate
     such as `is_prime(_)`.  It reflects to nothing, so it is exactly the case
     `cap verified` reports, and rendering it `<predicate>` would name the
     obligation in a way the user cannot match against their own source.
     Restricted to identifier heads so operator spellings keep the infix
     rendering the arms above give them. *)
  | A.EApp (A.EVar { A.txt = f; _ }, args, _)
    when f <> ""
         && (match f.[0] with 'a' .. 'z' | 'A' .. 'Z' | '_' -> true | _ -> false) ->
    f ^ "(" ^ String.concat ", " (List.map pred_str args) ^ ")"
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

(* =================================================================
   §9  Scope — the refined bindings in scope
   ================================================================= *)

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
  | Some (A.TyRefine (base, binder, pred)) when is_bool_base base ->
    Some (binder_name binder, pred, Some bool_sort)
  | Some (A.TyRefine (base, binder, pred)) when is_float_base base ->
    Some (binder_name binder, pred, Some float_sort)
  | Some (A.TyRefine ((A.TyCon ({ A.txt = name; _ }, _) as base), binder, pred))
    when is_adt_base base ->
    Some (binder_name binder, pred, Some (adt_sort_name name))
  | _ -> None

(* A function's declared RETURN refinement together with the SMT sort of the
   returned value: [None] sort for an Int return (Tier 0 / Tier 1, unchanged),
   [Some "M_…"] for a value at a registered ADT sort.

   The ADT arm is what Tier 2 adds.  Widening it here is safe on its own
   because nothing propagates until [gate_unverified_posts] has seen the
   definition side PROVE the postcondition, and the definition side proves an
   ADT-returning relational postcondition only through
   [check_post_induction] — which applies the structural induction hypothesis
   under [structural_subvars]. *)
let return_refine_sorted (fd : A.fn_def) : (string * A.expr * string option) option =
  match fd.A.fn_ret_ty with
  | Some (A.TyRefine (base, binder, pred)) when is_int_base base ->
    Some (binder_name binder, pred, None)
  | Some (A.TyRefine (base, binder, pred)) when is_bool_base base ->
    Some (binder_name binder, pred, Some bool_sort)
  | Some (A.TyRefine (base, binder, pred)) when is_float_base base ->
    Some (binder_name binder, pred, Some float_sort)
  | Some (A.TyRefine ((A.TyCon ({ A.txt = name; _ }, _) as base), binder, pred))
    when is_adt_base base ->
    Some (binder_name binder, pred, Some (adt_sort_name name))
  | _ -> None

(* Positional placeholder name for a synthesized callback [fn_sig] — it is
   only ever used to look up [rparam]/[param_names] by INDEX in [check_call],
   never displayed or looked up by name, so it need not be a real identifier. *)
let callback_param_name = "$cb_arg"

(* Synthesize a one-parameter [fn_sig] from a callback's declared arrow type,
   for checking a call made THROUGH a refined function-typed parameter (e.g.
   `f : ({Int | _ >= 0}) -> Int`) exactly like a call to a named function.
   Reuses [refined_param_ty] on the arrow's domain so Int/String/ADT/record
   domains all behave identically to a directly-refined parameter.

   Returns [None] for anything but a single-argument arrow with a REFINED
   domain — a non-arrow, an unrefined domain (nothing to check), or a
   multi-argument callback (a tupled domain, which [refined_param_ty] does not
   recognize as Int/String/ADT and so already falls through to [None]; a
   CURRIED arrow `(Int) -> (Int) -> Int` has an unrefined `Int` domain at this
   level for the same reason).  Per plan fact 2, multi-argument callbacks are
   out of scope and calling one fails typecheck anyway. *)
let callback_sig_of_ty (t : A.ty) : fn_sig option =
  match t with
  | A.TyArrow (dom, _) ->
    (match refined_param_ty (Some dom) with
     | Some (binder, pred, sort) ->
       Some
         { param_names = [ callback_param_name ]
         ; param_str = [ sort = Some str_sort ]
         ; param_scalar = [ scalar_sort_or_int sort ]
         ; refined = [ { idx = 0; binder; pred; sort } ]
         ; ret = None
         ; ret_sort = None
         }
     | None -> None)
  | _ -> None

(* True when a parameter's declared type is String, refined or not. *)
let is_string_param_ty : A.ty option -> bool = function
  | Some (A.TyRefine (base, _, _)) -> is_string_base base
  | Some t -> is_string_base t
  | None -> false

(* The SCALAR SMT sort a parameter's declared base type reflects into, refined
   or not.  Anything that is not a recognised scalar answers `Int` — the sort
   every parameter was declared at before, so nothing but Bool (and later
   Float) changes behaviour.  Driven by the DECLARED type, never by the actual:
   an unknown must stay unknown rather than be guessed from its argument. *)
let scalar_sort_of_param_ty (t : A.ty option) : Smt.sort =
  let base = match t with Some (A.TyRefine (b, _, _)) -> Some b | t -> t in
  match base with
  | Some b when is_bool_base b -> Smt.SBool
  | Some b when is_float_base b -> Smt.SFloat
  | _ -> Smt.SInt

(* Like refined_param_ty but for the refined-LOCAL scope: admits Int, String
   ([str_sort]), record TyCon params and — since 2026-07-29 — any other
   registered ADT (`List(Int)`, a user `Tree`) at the MEASURE-ONLY marker
   ([meas_sort_name], see the arm below), reporting the SMT sort name — Some
   "M_…" for a record, Some [str_sort] for a String, Some "$Meas:…" for an ADT,
   None for an Int.  NOTE for consumers: `Some _` does NOT mean "record" —
   check against [str_sort], and against [is_meas_sort], before taking a
   record-specific path. *)
let refined_scope_ty : A.ty option -> (string * A.expr * string option) option = function
  | Some (A.TyRefine (base, binder, pred)) when is_int_base base ->
    Some (binder_name binder, pred, None)
  | Some (A.TyRefine (base, binder, pred)) when is_string_base base ->
    Some (binder_name binder, pred, Some str_sort)
  | Some (A.TyRefine (base, binder, pred)) when is_bool_base base ->
    Some (binder_name binder, pred, Some bool_sort)
  | Some (A.TyRefine (base, binder, pred)) when is_float_base base ->
    Some (binder_name binder, pred, Some float_sort)
  | Some (A.TyRefine ((A.TyCon ({ A.txt = name; _ }, []) as base), binder, pred))
    when is_record_base base ->
    Some (binder_name binder, pred, Some (adt_sort_name name))
  (* Any OTHER registered ADT — `List(Int)`, `List(a)`, a user `Tree` — at the
     MEASURE-ONLY marker.  The record arm above wins for a record, so this arm
     sees variants and applied type constructors only.

     Admitting the type here is what lets a refined list PARAMETER's own
     promise reach the body at all; who reads the entry decides what is done
     with it.  Today exactly one consumer does: [check_call]'s `Other`-mode
     measure path, which loads `len(_) > 0` as an assumption over the same
     `len$x` symbol its goal already uses.  Every other consumer of [scope]
     tests the marker against a specific sort ([str_sort], a record's `M_…`) or
     through [scalar_sort_of_marker], so a `$Meas:` entry matches none of them
     and behaves exactly as the previous `None` (no entry at all) did — with the
     single exception of [scope_facts], which had a catch-all and is given an
     explicit skip arm for this marker. *)
  | Some (A.TyRefine ((A.TyCon ({ A.txt = name; _ }, _) as base), binder, pred))
    when is_adt_base base ->
    Some (binder_name binder, pred, Some (meas_sort_name name))
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
  | A.ELetQ (p, e1, e2, _) | A.ELetStar (p, e1, e2, _) ->
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

(* Does [e] mention [m] FREE — an occurrence not captured by an intervening
   binder of the same name?

   This exists because [expr_mentions] above is only safe in a DISCARDING
   position: it counts a lambda parameter (and occurrences under it) as
   mentions, which over-retires facts — silence, never a lie.  Used in an
   ACCEPTING position that direction inverts: `if any(ys, fn n -> n > 0)`
   would count as "the guard mentions `n`" when the guard's `n` is the
   lambda's own parameter and says nothing about the laundered value.  That
   shipped once (caught in review, 2026-07-31): the laundered-guard
   attribution blamed a withdrawal for a guard that never used the length.
   Anything that CONSUMES a mention as evidence must use this; anything that
   discards on a mention should keep [expr_mentions]. *)
let rec expr_mentions_free (m : string) (e : A.expr) : bool =
  let free = expr_mentions_free m in
  let any = List.exists free in
  let binds ps = List.mem m ps in
  let pbinds ps = List.exists (fun (p : A.param) -> p.A.param_name.A.txt = m) ps in
  match e with
  | A.EVar n -> n.A.txt = m
  | A.ELit _ | A.EHole _ | A.EResultRef _ | A.EDbg (None, _) -> false
  | A.EApp (f, args, _) -> free f || any args
  | A.ECon (_, args, _) | A.EAtom (_, args, _) | A.ETuple (args, _) -> any args
  | A.ELam (ps, body, _) -> if pbinds ps then false else free body
  | A.EBlock (es, _) ->
    (* Sequential: a `let` (or `let fn`) rebinding [m] shadows the REST of the
       block, but its own RHS still sees the outer [m]. *)
    let rec go = function
      | [] -> false
      | e :: rest ->
        free e
        ||
        (match e with
         | A.ELet (b, _) when binds (pat_binders b.A.bind_pat) -> false
         | A.ELetFn (n, _, _, _, _) when n.A.txt = m -> false
         | A.ELetQ (p, _, _, _) | A.ELetStar (p, _, _, _) when binds (pat_binders p) -> false
         | _ -> go rest)
    in
    go es
  | A.ELet (b, _) -> free b.A.bind_expr
  | A.ELetFn (n, ps, _, body, _) ->
    if n.A.txt = m || pbinds ps then false else free body
  | A.ELetQ (p, e1, e2, _) | A.ELetStar (p, e1, e2, _) ->
    free e1 || (if binds (pat_binders p) then false else free e2)
  | A.EMatch (subj, brs, _) ->
    free subj
    || List.exists
         (fun (br : A.branch) ->
           if binds (pat_binders br.A.branch_pat) then false
           else
             (match br.A.branch_guard with Some g -> free g | None -> false)
             || free br.A.branch_body)
         brs
  | A.ERecord (fs, _) -> List.exists (fun (_, v) -> free v) fs
  | A.ERecordUpdate (r, fs, _) -> free r || List.exists (fun (_, v) -> free v) fs
  | A.EField (r, _, _) -> free r
  | A.EIf (c, t, el, _) -> any [ c; t; el ]
  | A.ECond (arms, _) -> List.exists (fun (c, b) -> free c || free b) arms
  | A.EPipe (a, b, _) | A.ESend (a, b, _) -> free a || free b
  | A.EAnnot (e, _, _) | A.ESpawn (e, _) | A.EAssert (e, _) | A.ESigil (_, e, _)
  | A.EDbg (Some e, _) -> free e

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
(* Retiring a scope entry has TWO triggers, not one.

   The obvious one: the entry's own name is rebound, so the refinement describes
   a value this binding no longer denotes.

   The second only became load-bearing once a caller's promise could MENTION
   another name (see [reflect_scalar]'s [foreign_var]).  Given

     fn bad(n : Int, i : {Int | _ < n}) do
       let n = 0
       at(n, i)          -- `at` needs `i < n`
     end

   `i` is not rebound, so its entry survives — but its predicate's `n` refers to
   the PARAMETER, while `n` at the call site is `0`.  Keeping the entry lets the
   stale fact and the fresh goal collapse onto one `n` symbol and the call
   "proves", which is unsound: `i < n_param` does not give `i < 0`.  Attributing
   an outer fact to an inner binding is the cardinal error in this subsystem and
   has shipped from three different directions; [expr_mentions] is deliberately
   over-approximate, so this errs toward dropping a fact (silence) rather than
   inventing one. *)
let scope_shadow (sc : scope) (names : string list) : scope =
  if names = [] then sc
  else
    List.filter
      (fun (n, (_, q, _)) ->
        (not (List.mem n names)) && not (expr_mentions names q))
      sc

(* An arm whose pattern is a bare constructor with only irrefutable sub-patterns
   and NO guard fails exactly when the scrutinee's TAG differs.  That is what
   makes an earlier arm's failure informative to a later one.  `Cons(0, _)` and
   `Nil when c` both fail for reasons other than the tag, so neither licenses
   any conclusion — see [arm_excludes_tag]. *)
let rec irrefutable_pat (p : A.pattern) : bool =
  match p with
  | A.PatWild _ | A.PatVar _ -> true
  | A.PatAs (p, _, _) -> irrefutable_pat p
  | _ -> false

(* [Some ctor] when reaching a LATER arm implies the scrutinee is not [ctor]. *)
let arm_excludes_tag (br : A.branch) : string option =
  match br.A.branch_pat, br.A.branch_guard with
  | A.PatCon (ctor, subs), None when List.for_all irrefutable_pat subs ->
    Some ctor.A.txt
  | _ -> None

let path_shadow (path : (A.expr * bool) list) (names : string list) : (A.expr * bool) list =
  if names = [] then path else List.filter (fun (c, _) -> not (expr_mentions names c)) path

(* =================================================================
   §10 The other fact channels: path, launder, recenv, cbenv
   ================================================================= *)

(* ── Laundered guards: name -> the application it was let-bound to ─────────
   [visit] records, per program point, which local names are ONE `let` away
   from a direct application: `let n = List.length(ys)` records
   `n -> List.length(ys)`, so a later `if n > 0` can be recognised by
   [alias_withdrawal_cause] as the same author intent as guarding directly.
   One level ONLY — through a chain (`let a = …; let n = a`) "the guard is
   about this value" stops being syntactically evident, and the fallback is
   the honest general message, not a guess.

   The channel carries NO solver-visible fact — it is consulted only when
   choosing the WORDING of a skip — but it obeys the same shadow discipline as
   [scope]/[path], and for the same reason: an entry surviving a rebinding
   attributes an outer value's guard to an inner binding, which in this
   channel is a wrong SENTENCE rather than a wrong verdict, and a wrong
   attribution is worse than a vague one.  Hence BOTH tests below: the KEY
   retires when the laundering name rebinds (`let n = 5` after the laundering
   `let` makes the guard's `n` a literal), and the entry retires when any name
   its RHS mentions rebinds (`let ys = zs` in between leaves `n` measuring the
   OUTER list while the obligation is about the new one). *)
type launder = (string * A.expr) list

let launder_shadow (lets : launder) (names : string list) : launder =
  if names = [] then lets
  else
    List.filter
      (fun (n, rhs) -> not (List.mem n names) && not (expr_mentions names rhs))
      lets

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

(* ── Callee environment: variable name -> synthesized [fn_sig] ────────────
   [resolve_call] only resolves a NAMED callee.  This third fact channel
   covers the two shapes that fall through it: a call made THROUGH a refined
   function-typed parameter (`f(-3)` where `f : ({Int | _ >= 0}) -> Int`), and
   a call through a LOCAL ALIAS of a named function (`let g = takepos
   g(-3)`).  [EApp]'s `resolve_call` path is tried first; only when it finds
   nothing does [visit] consult this env.

   Exactly like [scope] and [recenv], every binding construct must retire a
   shadowed name here — an outer callback/alias fact attributed to an inner,
   unrelated binding of the same name is a false positive. *)
type cbenv = (string * fn_sig) list

let cb_shadow (cb : cbenv) (names : string list) : cbenv =
  if names = [] then cb else List.filter (fun (n, _) -> not (List.mem n names)) cb

(* Populate from a refined function-typed PARAMETER (Task 1). *)
let cb_add_param (cb : cbenv) (p : A.param) : cbenv =
  let cb = cb_shadow cb [ p.A.param_name.A.txt ] in
  match Option.bind p.A.param_ty callback_sig_of_ty with
  | Some sg -> (p.A.param_name.A.txt, sg) :: cb
  | None -> cb

let cb_add_fnparam (cb : cbenv) : A.fn_param -> cbenv = function
  | A.FPNamed p | A.FPDefault (p, _) -> cb_add_param cb p
  | A.FPPat pat -> cb_shadow cb (pat_binders pat)

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

(* [postcond] resolves a callee name AND the call's actual arguments to the
   callee's return refinement, already instantiated in the CALLER's namespace.
   An explicit annotation always wins; only an UNANNOTATED `let` whose RHS is a
   direct named call falls back to the callee's declared postcondition. *)
let scope_add_binding
    ~(postcond : string -> A.expr list -> (string * A.expr * string option) option)
    (sc : scope) (b : A.binding) : scope =
  (* Shadow first: `let c = neg()` followed by `let c = 5` must not leave the
     first `c`'s postcondition attached to the second. *)
  let sc = scope_shadow sc (pat_binders b.A.bind_pat) in
  match b.A.bind_pat, refined_scope_ty b.A.bind_ty with
  | A.PatVar n, Some r -> (n.A.txt, r) :: sc
  | A.PatVar n, None ->
    (match b.A.bind_expr with
     | A.EApp (A.EVar { A.txt = fname; _ }, args, _) ->
       (* An INT-sorted postcondition seeds the refined-local scope: [scope]
          entries with sort [None] are declared `Int` by [scope_facts] and
          [reflect_scalar].

          A RECORD-sorted one may too.  [record_self]'s variable branch already
          knows how to read such an entry — it declares the name at the
          record's datatype sort and resolves the carried predicate's
          `b.field` projections against that same term — it simply never saw
          one, because an annotated `let c : {v : Cfg | …} = …` was the only
          way to produce it.  So `let c = mk()` followed by `needLow(c)` was
          skipped even though the direct `needLow(mk())` is now checked; the
          two spellings must agree.

          A plain multi-constructor ADT (`Tree`, `List(a)`) may too, at the
          MEASURE-ONLY marker ([meas_sort_prefix]): [load_scope_measure_facts]
          already reads exactly this shape for a refined PARAMETER
          ([scope_add_param]) and treats a `$Meas:`-marked entry as an
          assumption over the same measure-application symbol its goal uses,
          so seeding one here for an unannotated `let` makes the two spellings
          agree the same way the record case above does.

          [postcond] (via [return_refine_sorted]) reports a plain ADT return at
          its bare registered sort (`"M_Tree"`, from [is_adt_base]/
          [adt_sort_name]) — the same convention [refined_param_ty] uses for a
          refined PARAMETER — not at the `$Meas:`-prefixed marker
          [refined_scope_ty] gives a directly-annotated local.  A non-record
          registered ADT sort is re-tagged with [meas_sort_prefix] here so the
          entry lands on the one spelling every scope consumer
          ([load_scope_measure_facts] and its constructor-tag analogue) already
          reads.

          A String postcondition is still refused, but not because
          [refined_scope_ty] cannot carry one — it has a `str_sort` arm.  The
          gap is one step earlier: [return_refine_sorted] has no String arm at
          all, so [postcond] never REPORTS a String return in the first place
          and there is nothing here to admit.

          ── The SELF-REBINDING guard on the ADT arm ────────────────────────
          [scope_shadow] above retires PRE-EXISTING entries whose predicate
          mentions one of this binding's binders.  The entry created HERE needs
          the identical test applied to itself, and for the identical reason:

            let t = push2(t, u)   -- push2 : {Tree | size(_) > size(t) + size(u)}
            needs_smaller(w, t)   -- wants size(t) < size(w), for arbitrary w

          [postcond_of] substitutes the call's ACTUALS, so `t` in the stored
          predicate denotes the value BEFORE this binding.  But the entry is
          filed under the name `t`, and [load_scope_measure_facts] accepts the
          entry's own name as a spelling of the promised value ([is_self_spelling]
          — correct for a refined PARAMETER, where the two really are the same
          value, and wrong here).  The two collide onto one symbol and the
          assumption becomes `size(t) > size(t) + size(u)`, i.e. `0 > size(u)` —
          a CONTRADICTION under the `size >= 0` axiom, which discharges any goal
          whatsoever.  A vacuously valid VC is a false proof, the one outcome
          this subsystem exists to prevent.

          Refusing to file such an entry is the whole fix: the predicate is
          simply not usable at this name.  Note this hazard predates the
          relational widening only in the sense that it was ACCIDENTALLY
          masked — before it, `size(u)` was untranslatable and [smt_of] dropped
          the predicate whole.

          Deliberately on THIS arm only.  The scalar and record arms above have
          the same shape and the same latent hole (reachable on the parent
          commit through [reflect_scalar]'s `foreign_var` channel, which never
          went through [load_scope_measure_facts] at all), but they are older,
          broader, and out of scope here — recorded with repros in
          `specs/todos/2026-08-04-postcond-let-self-rebinding-holes.md`. *)
       (match postcond fname args with
        | Some (binder, pred, m) when scalar_sort_of_marker m <> None ->
          (n.A.txt, (binder, pred, m)) :: sc
        | Some (binder, pred, Some srt) when is_record_sort srt ->
          (n.A.txt, (binder, pred, Some srt)) :: sc
        | Some (binder, pred, Some srt)
          when Hashtbl.mem adt_ctors srt
               && not (expr_mentions (pat_binders b.A.bind_pat) pred) ->
          (n.A.txt, (binder, pred, Some (meas_sort_prefix ^ srt))) :: sc
        | Some _ | None -> sc)
     | _ -> sc)
  | _ -> sc

(* =================================================================
   §11 Signature extraction and definition collection
   ================================================================= *)

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
  let param_scalar =
    List.map (fun fp -> scalar_sort_of_param_ty (param_ty_of fp)) c.A.fc_params
  in
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
  { param_names; param_str; param_scalar; refined; ret = None; ret_sort = None }

(* Every function definition keyed by its fully-qualified name (e.g. "A.B.foo"),
   mapping to Some sig when it carries a refinement, None when it does not.
   Recording NON-refined defs too is essential for correct lexical resolution: a
   bare call that resolves to a non-refined sibling must NOT fall through to a
   refined function of the same name in an enclosing module — that would check
   the wrong predicate (a false positive). *)
let sig_of_fn (fd : A.fn_def) : fn_sig =
  let base =
    match fd.A.fn_clauses with
    | c :: _ -> sig_of_clause c
    | [] ->
      { param_names = []; param_str = []; param_scalar = []; refined = []
      ; ret = None; ret_sort = None }
  in
  match return_refine_sorted fd with
  | Some (b, p, srt) -> { base with ret = Some (b, p); ret_sort = srt }
  | None -> { base with ret = None; ret_sort = None }

(* Record the signature when EITHER side carries a refinement: a function with
   only a refined *return* must be resolvable so its postcondition reaches call
   sites, even though it has no refined params of its own to check. *)
let entry_of_sig (sg : fn_sig) : fn_sig option =
  if sg.refined <> [] || Option.is_some sg.ret then Some sg else None

(* ── Which `impl` method contracts may be trusted ──────────────────────────
   An `impl` method is callable under the enclosing module's spelling exactly
   like a `fn`, and [visit_decl] now walks its BODY and would ASSUME its
   parameter refinements as facts.  A predicate assumed inside a body but never
   demanded of any caller is assume-without-check: `fn run(b, k : {Int|k != 0})`
   made `m / k` dischargeable under `cap no_panic` while `run(Box(4), 0)` was
   accepted, and the program divided by zero at run time.  Registering the
   contract in [collect_all_defs] is what obliges the caller.

   But a name only denotes ONE contract when it is unambiguous.  It is not when

     - a `fn` in the same decl list already owns the name (a module with both
       `fn map` and `impl Functor(T) do fn map`), or
     - two impls define the method (`impl Show(Int)` / `impl Show(String)` both
       give `show`), or
     - a `use` in the same decl list imports the name from elsewhere
       (`use Other.{run}` beside `impl Runner(Box) do fn run`),

   because a call resolved by NAME cannot tell which contract applies, and
   checking correct code against a predicate it never touches is the one
   failure this subsystem must never have.  So: adoptable names get their
   contract registered (callers obliged, body may assume); the rest are
   registered nowhere AND have their bodies walked with parameter refinements
   STRIPPED.  Unenforced means unusable in BOTH directions.

   `use` is the third competitor, and the one this function used to miss: a
   `use Other.{run}` binds a bare `run` in exactly the scope the impl method is
   callable from, so the name no longer denotes one contract even though only
   one impl in this decl list defines it.  Adopting it would oblige callers to
   satisfy a predicate the call may never reach — the false positive above,
   arrived at from the other direction.

   Which names a `use` binds is only knowable for the ENUMERATED selector
   ([UseNames]: `use Other.{run}`, `use Other.run`, `import Other, only: [run]`).
   [UseAll] and [UseExcept] name a module this function cannot see, so their
   import set is undecidable HERE and the rule fails CLOSED: every impl method
   in the decl list is withdrawn.  Note [UseAll] is NOT only the `.*` spelling —
   a bare `import Other` parses to it too (parser.mly, `import_path_tail`'s
   empty alternative), and that is the spelling real programs use.  [UseSingle]
   (`use Other`) binds the module itself, not any bare name, so it competes with
   nothing.  Failing closed costs only silence; failing open costs a false
   positive, and this subsystem trades the first for the second by design.

   Scope note: the competition is decl-list-local, matching this function's
   own input.  A `use` in an ENCLOSING module also binds names lexically inside
   a nested one; that case is still adopted.  Widening it is a further
   withdrawal, safe in the same direction, and deliberately not taken here
   without a witness.

   This function is the single definition of that rule.  [division_safety]
   consults it too, so the two passes cannot drift apart. *)
let adoptable_impl_methods (decls : A.decl list) : string list =
  let fns = Hashtbl.create 16 in
  let counts = Hashtbl.create 16 in
  (* An unresolvable import: some name set we cannot enumerate is in scope. *)
  let opaque_import = ref false in
  List.iter
    (function
      | A.DFn (fd, _) -> Hashtbl.replace fns fd.A.fn_name.A.txt ()
      | A.DUse (ud, _) ->
        (match ud.A.use_sel with
         | A.UseNames ns ->
           List.iter (fun (n : A.name) -> Hashtbl.replace fns n.A.txt ()) ns
         | A.UseAll | A.UseExcept _ -> opaque_import := true
         | A.UseSingle -> ())
      | A.DImpl (idf, _) ->
        List.iter
          (fun ((mn : A.name), _) ->
            Hashtbl.replace counts mn.A.txt
              (1 + Option.value ~default:0 (Hashtbl.find_opt counts mn.A.txt)))
          idf.A.impl_methods
      | _ -> ())
    decls;
  if !opaque_import then []
  else
    Hashtbl.fold
      (fun name n acc -> if n = 1 && not (Hashtbl.mem fns name) then name :: acc else acc)
      counts []

let collect_all_defs (decls : A.decl list) : (string, fn_sig option) Hashtbl.t =
  let tbl = Hashtbl.create 128 in
  let qualify prefix n = if prefix = "" then n else prefix ^ "." ^ n in
  let rec go prefix decls =
    let adoptable = adoptable_impl_methods decls in
    List.iter
      (function
        | A.DFn (fd, _) ->
          Hashtbl.replace tbl (qualify prefix fd.A.fn_name.A.txt) (entry_of_sig (sig_of_fn fd))
        | A.DImpl (idf, _) ->
          List.iter
            (fun ((mn : A.name), (fd : A.fn_def)) ->
              if List.mem mn.A.txt adoptable then
                Hashtbl.replace tbl (qualify prefix mn.A.txt) (entry_of_sig (sig_of_fn fd)))
            idf.A.impl_methods
        | A.DMod (name, _, ds, _) -> go (qualify prefix name.A.txt) ds
        | _ -> ())
      decls
  in
  go "" decls;
  tbl

(* Erase parameter refinements from [fd], leaving the return refinement alone.
   A stripped parameter contributes no fact to [scope], so a body checked with
   it can discharge nothing from a predicate no caller was obliged to
   establish.  The return refinement is CHECKED rather than assumed, so it
   stays: dropping it would lose a real check, and checking it against the
   original (unstripped) parameters is what [visit_fn] keeps doing. *)
let strip_param_refinements (fd : A.fn_def) : A.fn_def =
  let rec strip = function
    | A.TyRefine (t, _, _) -> strip t
    | A.TyLinear (l, t) -> A.TyLinear (l, strip t)
    | t -> t
  in
  let param (p : A.param) = { p with A.param_ty = Option.map strip p.A.param_ty } in
  let fp = function
    | A.FPNamed p -> A.FPNamed (param p)
    | A.FPDefault (p, e) -> A.FPDefault (param p, e)
    | A.FPPat _ as x -> x
  in
  { fd with
    A.fn_clauses =
      List.map
        (fun (c : A.fn_clause) -> { c with A.fc_params = List.map fp c.A.fc_params })
        fd.A.fn_clauses }

(* =================================================================
   §12 Name resolution: module paths, aliases, call targets
   ================================================================= *)

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
  (* (exporting module dotted, selector, scope) — [scope] is the modpath of
     the module that OWNS this `use` (recorded at [A.DUse]-gathering time,
     where [ctx.modpath] is exactly that module).  Needed because [ctx.uses]
     inherits into nested modules while declaration-list competition does
     not: without a scope tag, [resolve_call] cannot tell an inner module's
     own `use` from an enclosing one, and either always preferring defs over
     uses (the pre-fix bug: an enclosing def wrongly beats a nearer `use`) or
     always preferring uses over defs (the mirror-image bug: an outer `use`
     wrongly beats an inner module's own def) is wrong in one direction. *)
  uses : (string * A.use_selector * string) list;
  (* Names bound by an ENCLOSING BINDER (parameter, `let`, `let?`, lambda
     parameter, local `fn` name/parameter, `match` arm binder).  See
     [local_shadow]. *)
  locals : string list;
}

let rctx0 = { modpath = ""; aliases = []; uses = []; locals = [] }

(* ── The FOURTH fact channel: callee resolution ────────────────────────────
   [scope], [path], [recenv] and [cbenv] each carry facts keyed by a variable
   NAME, and each one already retires a name a binding construct rebinds.  The
   GLOBAL DEFINITION TABLE consulted by [resolve_call] is a fact channel of
   exactly the same shape — "the name `f` denotes this contract" — and it needs
   exactly the same discipline:

     fn takepos(k : {Int | _ >= 0}) : Int do k end
     fn probe() : Int do
       let takepos = fn n -> n     -- a LOCAL, unrefined, that runs
       takepos(-3)                 -- must NOT be checked against the global
     end

   Resolving that call to the module-level `takepos` checks correct code
   against a contract it never touches — a false positive, the one failure
   this subsystem must never have.  So [rctx.locals] records every name an
   enclosing binder introduced, and [resolve_call] refuses to resolve one.

   Retiring a name here can only turn a check into a SKIP, never the reverse,
   so over-approximating [locals] is always safe. *)
let local_shadow (ctx : rctx) (names : string list) : rctx =
  if names = [] then ctx else { ctx with locals = names @ ctx.locals }

let fnparam_binders : A.fn_param -> string list = function
  | A.FPNamed p | A.FPDefault (p, _) -> [ p.A.param_name.A.txt ]
  | A.FPPat pat -> pat_binders pat

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
  (* 0. A name an enclosing binder introduced is a LOCAL, not this module's
        function of that name — see [local_shadow].  Bail out before any
        lookup: the local shadows the global at every one of the three
        resolution steps below, alias- and `use`-imported names included. *)
  if List.mem fname ctx.locals then None
  else
  (* 1. Scope-aware walk: at each prefix `p` of [ctx.modpath], from innermost
        to outermost, that prefix's own DEFINITION wins first, then that
        SAME prefix's own `use`-imports, before falling outward to the next
        prefix.  This is what makes a nested `use` beat an enclosing
        definition (the fix — the `use` is recorded at the inner prefix, so
        it is consulted before the walk ever reaches the outer prefix that
        owns the shadowed definition) while an outer module's `use` still
        loses to an inner module's own definition (the inner prefix's own
        def is found before the walk ever reaches the outer prefix that owns
        the `use`). *)
  let use_at prefix =
    (* `use`-imported names are always bare (never dotted) — see the old
       step 3's guard, preserved here. *)
    if String.contains fname '.' then None
    else
      List.find_map
        (fun (m, sel, scope) ->
          if scope <> prefix then None
          else
            let imported =
              match sel with
              | A.UseAll -> true
              | A.UseNames ns -> List.exists (fun (n : A.name) -> n.A.txt = fname) ns
              | A.UseExcept ns -> not (List.exists (fun (n : A.name) -> n.A.txt = fname) ns)
              | A.UseSingle -> false
            in
            if imported then lookup (qualify m fname) else None)
        ctx.uses
  in
  match
    List.find_map
      (fun p -> match lookup (qualify p fname) with Some r -> Some r | None -> use_at p)
      (modpath_prefixes ctx.modpath)
  with
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
    aliased

(* True iff a call written as the bare [name] from inside [ctx]'s module
   resolves to exactly [sg] — i.e. the contract every caller is obliged to
   establish IS this definition's.  Used to decide whether an `impl` method's
   parameter refinements may be assumed while walking its body; see
   [collect_all_defs]'s merge step for the cases where it is false. *)
let contract_is_enforced (ctx : rctx) defs (name : string) (sg : fn_sig) : bool =
  match resolve_call ctx defs name with
  | Some (Some found) -> found.refined = sg.refined
  | _ -> false

(* Populate [cbenv] from a LOCAL ALIAS of a named refined function (Task 2):
   only a bare-variable RHS that [resolve_call] resolves to a refined function
   counts — a call, a field access, or a lambda RHS is never chased, so the
   alias fact is only ever a straight rename of a known callee, never a guess
   about the shape of a computed value.  Shadowing happens FIRST, matching
   [scope_add_binding]/[recenv_add_binding]. *)
let cb_add_binding (ctx : rctx) (defs : (string, fn_sig option) Hashtbl.t) (cb : cbenv)
    (b : A.binding) : cbenv =
  let cb = cb_shadow cb (pat_binders b.A.bind_pat) in
  match b.A.bind_pat, b.A.bind_expr with
  | A.PatVar n, A.EVar { A.txt = fname; _ } ->
    (match resolve_call ctx defs fname with
     | Some (Some sg) -> (n.A.txt, sg) :: cb
     | _ -> cb)
  | _ -> cb

(* Resolve a call name and its actual arguments to the callee's return
   refinement, expressed entirely in the CALLER's namespace, or None.  This is
   the single place the usability filter is applied, so both use sites (a
   let-bound local and an inline argument) agree.

   [Closed]        the predicate mentions only the binder; it means the same
                   thing at every call site, so it is returned unchanged.
   [Relational ps] the predicate mentions parameters; the call's actuals are
                   substituted for them SIMULTANEOUSLY, so the result talks
                   about the caller's terms and the existing reflection
                   machinery needs no changes.
   [Unusable]      never propagated.

   Skip, don't guess: if any parameter the predicate mentions has no
   corresponding actual (arity mismatch, a pattern parameter, an omitted
   defaulted argument), propagation is abandoned for this call.  A partially
   substituted predicate would mix the callee's and caller's namespaces —
   exactly the conflation that has produced false positives here before.

   The other half of the filter is applied earlier: [gate_unverified_posts]
   has already cleared [ret] on every signature whose postcondition the
   definition side did not PROVE, so anything reaching here is a fact.

   The third component of the result is the returned value's SMT sort ([None]
   for Int); see [fn_sig.ret_sort] for why every consumer must branch on it. *)
let postcond_of (ctx : rctx) (defs : (string, fn_sig option) Hashtbl.t) (fname : string)
    (args : A.expr list) : (string * A.expr * string option) option =
  match resolve_call ctx defs fname with
  | Some (Some sg) ->
    (match sg.ret with
     | Some (b, p) ->
       let srt = sg.ret_sort in
       (match classify_pred b sg.param_names p with
        | Closed -> Some (b, p, srt)
        | Unusable -> None
        | Relational ps ->
          (* Positional formal -> actual.  A formal recorded as "_" is a
             pattern parameter with no usable name; it can never be a member of
             [ps] (the classifier reads "_" as the binder), and mapping it would
             be meaningless, so it is excluded here too. *)
          let env =
            List.mapi (fun i n -> (n, List.nth_opt args i)) sg.param_names
            |> List.filter_map (function
                 | "_", _ | _, None -> None
                 | n, Some a -> Some (n, a))
          in
          if List.for_all (fun p -> List.mem_assoc p env) ps then
            Some (b, subst_params env p, srt)
          else None)
     | _ -> None)
  | _ -> None

(* =================================================================
   §13 Reflecting actual arguments: fields, records, scalars
   ================================================================= *)

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
  (* Float RECORD FIELDS are out of scope: [smt_sort_of_field] never produces
     `SFloat` (a `Float` field is opaque `Elem`), so this arm is unreachable —
     and if a later change makes it reachable, refusing the fit makes the record
     unreflectable and the call skipped, which is the safe direction. *)
  | Smt.SFloat -> false
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
(* [sort] is the SCALAR SMT sort the reflected value lives at — `Int` (the
   original and still the default), `Bool`, or `Float64`.  It is chosen from a
   DECLARED type by the caller, never inferred from the actual, and it governs
   both the declaration emitted for a variable and the one for a propagated
   postcondition's constant.  Getting it wrong puts one symbol at a sort its
   uses disagree with, which z3 rejects. *)
(* [foreign_var] / [foreign_measure]: how a name in a caller-scope refinement
   that is NOT that refinement's own subject resolves.

   `fn pick(n : Int, i : {Int | _ < n}) … at(n, i)` — the promise carried by `i`
   mentions `n`, a sibling PARAMETER. Until these existed, the resolver below
   mapped every non-subject name to [None], and [smt_of] fails on a sub-term, so
   ONE foreign name discarded the WHOLE predicate: the VC for `at(n, i)` was its
   negated goal and nothing else, satisfiable both ways, silently skipped. The
   identical fact arriving as a path guard (`if i < n do at(n, i)`) proved,
   because THAT channel has a full caller-namespace resolver — so the defect was
   never in the solver or the goal, only in which facts reached it.

   Defaulting both to [None] keeps every other caller byte-identical: only the
   call-site builder, which owns the caller namespace (sorts, string/record
   registries, the measure memo), passes them. *)
let reflect_scalar
    ~(postcond : string -> A.expr list -> (string * A.expr * string option) option)
    ?(foreign_var : (string -> (Smt.term * (string * Smt.sort)) option) option)
    ?(foreign_measure : (string -> string -> Smt.term option) option)
    ?(foreign_field :
        (string -> string -> (Smt.term * (string * Smt.sort) list) option) option)
    ?(sort : Smt.sort = Smt.SInt) (sc : scope) (actual : A.expr)
  : (Smt.term * (string * Smt.sort) list * Smt.term list) option =
  let foreign_var = Option.value foreign_var ~default:(fun _ -> None) in
  let foreign_measure =
    Option.value foreign_measure ~default:(fun _ _ -> None)
  in
  (* A field read in ACTUAL position — `takepos(a.rem)`.  The caller supplies
     the same selector term its PATH conditions reflect `a.rem` to, so a guard
     (`if a.rem >= 0`) and this goal meet on one symbol; without it the field
     access reached [smt_of]'s default resolver, came back None, and took the
     whole obligation down with it as "unreflectable" — silently, since an
     undecidable obligation is accepted. Callers that cannot model the record
     leave it unset and get exactly the old behaviour. *)
  let foreign_field = Option.value foreign_field ~default:(fun _ _ -> None) in
  (* Reflect an expression with no scope help — also the fallback for a call
     whose callee has no usable postcondition. *)
  let plain e =
    let extra = ref [] in
    let resolve_field x fname =
      match foreign_field x fname with
      | Some (t, ds) ->
        List.iter (fun d -> if not (List.mem d !extra) then extra := d :: !extra) ds;
        Some t
      | None -> None
    in
    match smt_of ~resolve_var:(fun _ -> None) ~resolve_measure:(fun _ _ -> None)
            ~resolve_field e with
    | Some t -> Some (t, !extra, [])
    | None -> None
  in
  match actual with
  | A.EVar { A.txt = x; _ } ->
    let xc = Smt.Const x in
    (match List.assoc_opt x sc with
     (* A refined local at the SAME scalar sort we are reflecting into (Int for
        the original `None` marker, Bool for `$Bool`): carry its own refinement
        as an assumption.  A scope entry at a DIFFERENT sort says nothing about
        the value at this one, and loading it would be ill-sorted, so it falls
        through to the unconstrained constant below. *)
     | Some (b, q, m) when scalar_sort_of_marker m = Some sort ->
       (* All three spellings of the refined value denote it: the anonymous `_`,
          the declared binder [b], and the variable's own name [x].  Matches
          [load_scope_measure_facts]'s [is_self_spelling] — the two sides of the
          same fact must accept the same spellings or they meet on different
          symbols. *)
       let extra = ref [] in
       let rv n =
         if n = b || n = "_" || n = x then Some xc
         else
           match foreign_var n with
           | Some (t, d) ->
             if not (List.mem d !extra) then extra := d :: !extra;
             Some t
           | None -> None
       in
       let assumptions =
         match smt_of ~resolve_var:rv ~resolve_measure:foreign_measure q with
         | Some qa -> [ qa ]
         | None -> []
       in
       Some (xc, (x, sort) :: !extra, assumptions)
     | Some _ | None ->
       (* An ordinary variable: reflect it as a constant so a path-context
          guard about it can constrain it.  Without a guard it stays
          unconstrained and the definite-failure check keeps us silent. *)
       Some (xc, [ (x, sort) ], []))
  (* A direct named call: stand its result up as a fresh constant carrying the
     callee's declared postcondition.  `.` is a legal SMT-LIB simple-symbol
     character, so a qualified name needs no mangling. *)
  | A.EApp (A.EVar { A.txt = fname; _ }, cargs, _) ->
    (* A postcondition at any OTHER sort than the one we are reflecting into is
       not a fact about this value: an ADT-sorted one (carried by [reflect_dt]
       instead), or a Bool one where an Int is expected.  Standing it up here
       would declare one symbol at two sorts, so it falls through to [plain]. *)
    (match postcond fname cargs with
     | Some (b, q, m) when scalar_sort_of_marker m = Some sort ->
       incr ret_ctr;
       let nm = Printf.sprintf "%s$ret%d" fname !ret_ctr in
       let c = Smt.Const nm in
       let rv n = if n = b || n = "_" then Some c else None in
       let assumptions =
         match smt_of ~resolve_var:rv ~resolve_measure:(fun _ _ -> None) q with
         | Some qa -> [ qa ]
         | None -> []
       in
       Some (c, [ (nm, sort) ], assumptions)
     | Some _ | None -> plain actual)
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

(* =================================================================
   §14 Verdict state and withdrawal diagnostics
   ================================================================= *)

(* ── `cap verified`: a skipped obligation becomes an error ───────────────── *)
(* March's default stance is DEFINITE FAILURE ONLY — an obligation the checker
   cannot discharge is silence, because a false positive on correct code is the
   cardinal sin here.  A module that writes `cap verified` opts INTO the
   inverse: inside it, "the checker could not verify this" is an error rather
   than silence, so the module's contracts are a guarantee instead of a
   best effort.

   Strictly OPT-IN.  This flag is false unless the decl list currently being
   walked itself contains `cap verified`, and it is saved/restored around every
   nested module by [visit_decls] — so it is scoped exactly like
   [Division_safety]'s `cap no_panic`.  Two consequences worth stating:

     - a `cap verified` module that CALLS an ordinary module does not make the
       callee's module strict; only obligations RAISED at call sites lexically
       inside the strict decl list escalate; and
     - inheritance into nested modules is deliberately NOT done.  bin/main.ml
       prepends the entire standard library as sibling `DMod` decls of the
       entry module's own decls, so an inherited flag would turn every stdlib
       module strict the moment one user module asked for verification. *)
let strict_verified = ref false

(* Whether this decl list has already been told that some contract in it went
   unverified. Scoped and restored exactly like [strict_verified].

   The default stance is "definite failure only" — an undecidable obligation
   stays silent rather than risk a false positive on correct code. That is the
   right default, but silence is indistinguishable from "checked and fine": a
   reader who never learns the checker gave up believes a contract is enforced
   when it is not, and `cap verified` (the opt-in that turns exactly this
   silence into an error) is only discoverable if you already know to look for
   it. One hint per decl list names the first such contract and points at the
   escalation — enough to be findable, not so much that a module with many
   undecidable predicates becomes a wall of text. *)
let unverified_hinted = ref false

(* Scoped exactly like [strict_verified], but to a single `fn` rather than a
   decl list: true while [visit_fn] is walking a function whose [fn_attrs]
   carry `@[trusted]`.  Consulted only by [check_call]'s [note] — see there for
   why [check_post] does not (yet) need to. *)
let trusted_fn = ref false

(* Does [e] ever APPLY the function spelled [name]?  Applications only: a bare
   mention (`let f = List.length`) is not a guard, and counting it would let an
   unrelated line decide what a call site is told. *)
let expr_applies (name : string) (e : A.expr) : bool =
  let found = ref false in
  iter_all
    (fun e ->
      match e with
      | A.EApp (A.EVar n, _, _) when n.A.txt = name -> found := true
      | _ -> ())
    e;
  !found

(* Does [e] apply [name] TO THE VARIABLE [subject], counting only a FREE
   occurrence of [subject] — one not captured by an intervening binder of the
   same name?  Stricter than [expr_applies] on purpose — see condition 3 of
   [alias_withdrawal_cause]: a guard on some OTHER list says nothing about
   this call's argument, so `List.length(zs) > 0` guarding `head(ys)` must
   not be read as a guard on `ys`.  Compared by NAME rather than
   structurally, because the same variable read at two source positions
   carries two different spans and would never compare equal.

   The FREE restriction exists because [guard_applies] below uses this in an
   ACCEPTING position: "this guard applies the withdrawn spelling to the
   subject" is evidence FOR an attribution, so a shadow-blind, discard-only
   walk (the shape [expr_mentions] above uses, built on [iter_all]) would be
   a wrong attribution here, not merely a vague one.  `if check(fn ys ->
   List.length(ys) > 0, zs) do head(ys) …` must not read as "the guard
   applies List.length to ys": the guard's `ys` is the lambda's own
   parameter, and the guard says nothing about the outer `ys` that `head`'s
   argument names.  Mirror image of the laundered-path bug fixed 2026-07-31
   (probe PE, see [expr_mentions_free] above) — same fix, one level of AST
   deeper because the thing that must stay free is the ARGUMENT reference,
   not the applied function's own name.  Modeled on [expr_mentions_free]'s
   traversal shape (sequential [EBlock] scoping, lambda/[let fn] parameter
   capture, match-arm binder capture) rather than sharing code with it: the
   two walk for different things (a free mention of a name vs. a free
   argument to an application) and a shared abstraction would be a worse
   trade than the duplication. *)
let rec expr_applies_to_free (name : string) (subject : string) (e : A.expr) : bool =
  let free = expr_applies_to_free name subject in
  let any = List.exists free in
  let binds ps = List.mem subject ps in
  let pbinds ps = List.exists (fun (p : A.param) -> p.A.param_name.A.txt = subject) ps in
  match e with
  | A.EVar _ -> false
  | A.ELit _ | A.EHole _ | A.EResultRef _ | A.EDbg (None, _) -> false
  | A.EApp (f, args, _) ->
    (match f with
     | A.EVar n
       when n.A.txt = name
            && List.exists (function A.EVar v -> v.A.txt = subject | _ -> false) args ->
       true
     | _ -> false)
    || free f || any args
  | A.ECon (_, args, _) | A.EAtom (_, args, _) | A.ETuple (args, _) -> any args
  | A.ELam (ps, body, _) -> if pbinds ps then false else free body
  | A.EBlock (es, _) ->
    (* Sequential: a `let` (or `let fn`) rebinding [subject] shadows the REST
       of the block, but its own RHS still sees the outer [subject]. *)
    let rec go = function
      | [] -> false
      | e :: rest ->
        free e
        ||
        (match e with
         | A.ELet (b, _) when binds (pat_binders b.A.bind_pat) -> false
         | A.ELetFn (n, _, _, _, _) when n.A.txt = subject -> false
         | A.ELetQ (p, _, _, _) | A.ELetStar (p, _, _, _) when binds (pat_binders p) -> false
         | _ -> go rest)
    in
    go es
  | A.ELet (b, _) -> free b.A.bind_expr
  | A.ELetFn (n, ps, _, body, _) ->
    if n.A.txt = subject || pbinds ps then false else free body
  | A.ELetQ (p, e1, e2, _) | A.ELetStar (p, e1, e2, _) ->
    free e1 || (if binds (pat_binders p) then false else free e2)
  | A.EMatch (subj, brs, _) ->
    free subj
    || List.exists
         (fun (br : A.branch) ->
           if binds (pat_binders br.A.branch_pat) then false
           else
             (match br.A.branch_guard with Some g -> free g | None -> false)
             || free br.A.branch_body)
         brs
  | A.ERecord (fs, _) -> List.exists (fun (_, v) -> free v) fs
  | A.ERecordUpdate (r, fs, _) -> free r || List.exists (fun (_, v) -> free v) fs
  | A.EField (r, _, _) -> free r
  | A.EIf (c, t, el, _) -> any [ c; t; el ]
  | A.ECond (arms, _) -> List.exists (fun (c, b) -> free c || free b) arms
  | A.EPipe (a, b, _) | A.ESend (a, b, _) -> free a || free b
  | A.EAnnot (e, _, _) | A.ESpawn (e, _) | A.EAssert (e, _) | A.ESigil (_, e, _)
  | A.EDbg (Some e, _) -> free e

(* ── Attributing a skip to a withdrawn alias ───────────────────────────────
   A withdrawn alias is only ONE of the reasons an obligation can go
   undischarged, and a wrong attribution is worse than a vague one: it sends
   the author to rename a binding that had nothing to do with their problem,
   and it hides the real cause.  So this is deliberately conjunctive — all
   four conditions, or we keep the honest general message:

   1. the reason is [Solver_undecided].  A withdrawal cannot cause any other
      skip: it removes an ASSUMPTION, so the VC is still built, still
      well-sorted, and still reaches the solver — it just arrives without the
      fact that would have discharged it.  An unreflectable predicate or a sort
      conflict failed strictly earlier, for reasons the alias cannot touch.
   2. the predicate actually mentions the measure the alias routes to.  A
      withdrawn `len` alias is irrelevant to `{Int | _ != 0}`.
   3. a POSITIVE path condition applies the withdrawn spelling TO THIS
      OBLIGATION'S OWN SUBJECT.  Each half of that is load-bearing, and the
      first version of this test had neither:

        - "to this subject", because `if List.length(zs) > 0 do head(ys) …`
          is not a guard on `ys`.  Delete the competing binding and that
          program is STILL undischarged — which is the proof that the
          withdrawal was not the cause.  Blaming it sends the author to rename
          something irrelevant, while the general message's "guard the call"
          is the correct advice.
        - "positive", because in `if List.length(ys) > 0 do 0 else head(ys) end`
          the guard does not fail to prove the predicate — it DISPROVES it.
          With the binding removed that program reports a real refinement
          violation, so "the guard proved nothing" would dress a genuine bug in
          the user's code up as a story about a nested module.  We cannot
          report the violation ourselves (the alias is withdrawn, so nothing
          reflects either way), but we can decline to misdescribe it.

      Without this conjunct the attribution would also fire on every unguarded
      call in a module that merely CONTAINS a competing definition — the
      relabel-everything failure this fix must not become.
   4. the withdrawn spelling measures the same KIND of thing as the subject:
      `List.length` for a list subject, `String.byte_size` /
      `string_byte_length` for a String one.  All three route to the single
      name `len`, so condition 2 cannot separate them on its own, and a
      withdrawn `List.length` was being blamed for an undischarged
      `{String | len(_) > 0}` — naming a list definition that could not
      possibly have mattered.

   Condition 3 accepts the guard in two spellings, and only two.  DIRECT: the
   condition itself applies the withdrawn spelling to the subject.  LAUNDERED
   through exactly one `let`: the condition mentions a name that [lets] maps
   to an application, and THAT application applies the withdrawn spelling to
   the subject — `let n = List.length(ys)` then `if n > 0` is the same author
   intent, stopped by the same withdrawal, so it earns the same sentence.
   The laundered check runs [expr_applies_to_free] against the recorded RHS with
   the obligation's own subject, never against the let-bound name: `let n =
   List.length(zs)` guarding a call about `ys` fails it exactly as the direct
   `if List.length(zs) > 0` does.  [lets] is shadow-disciplined by [visit]
   (see [launder]), so a rebinding of either the laundering name or the
   collection between the `let` and the guard has already retired the entry
   before this function ever sees it.

   Note the asymmetry with the gates themselves: THEY resolve doubt by
   suppressing (silence is safe).  This resolves doubt by staying general,
   because the thing being chosen here is a sentence, and an over-confident
   sentence is a lie.  The cost is coverage: a guard laundered through a CHAIN
   of locals (`let a = List.length(ys)` then `let n = a`), applied to a
   non-variable actual, or established in a caller, falls back to the general
   message.  That is the right trade — this reason exists to explain one
   specific confusion, not to claim every skip. *)
(* ── Condition 5: the guard, read as a fact, must ENTAIL the predicate ─────
   Condition 3 (below, [guard_applies]) only asks whether the guard applies
   the withdrawn spelling to this obligation's own subject — not whether it
   would have PROVED the goal.  `List.length(ys) >= 0` applies the spelling
   to `ys` exactly as `List.length(ys) > 0` does, but it is a tautology over
   a non-negative measure: it entails nothing about the goal `len(ys) > 0`,
   so that call is skipped with or without the withdrawal.  Blaming the
   withdrawal there sends the author to fix an import that was never the
   cause — the harm this conjunct exists to prevent.

   The check is a small syntactic interval-entailment over `==`/`!=`/`<`/
   `<=`/`>`/`>=` against an integer literal, modeled on
   [Division_safety.path_proves_nonzero]'s `dual`/`flip`/`proves` shape
   (extended there to boolean connectives): normalise both sides to `X op n`
   with `X` the measure application (or, laundered, the name it was bound
   to), read each as a half-open/closed interval of integers, and ask
   whether the guard's interval is a SUBSET of the predicate's.  `!=` is not
   convex — no single interval represents "everything but n" — so it never
   entails anything here; that is a missed proof, not a wrong one.

   Where the shapes do not match this pattern at all (anything but a single
   comparison against a literal on one side), entailment is UNDECIDED, and
   per the fail-closed stance of this whole function, undecided means "do
   not blame the withdrawal" — a generic `solver-undecided` message is a
   smaller error than sending the author to fix an unrelated import. *)
let alias_withdrawal_cause ~(pred : A.expr) ~(subject : A.expr option)
    ~(subject_is_str : bool) ~(path : (A.expr * bool) list) ~(lets : launder)
    (r : Obligation.reason) : withdrawal option =
  match (r, subject) with
  | Obligation.Solver_undecided, Some (A.EVar sn) ->
    let guard_applies (w : withdrawal) (cond : A.expr) : bool =
      (* FREE occurrence only, on both the direct condition and the laundered
         RHS: this is an ACCEPTING position, so a shadow-blind, discard-only
         walk would be the wrong tool on either path — a lambda parameter in
         the guard that merely collides with the subject's own name must not
         read as evidence (review 2026-07-31, probe PE, and its mirror image
         on the direct path). *)
      expr_applies_to_free w.wd_spelling sn.A.txt cond
      || List.exists
           (fun (m, rhs) ->
             expr_mentions_free m cond && expr_applies_to_free w.wd_spelling sn.A.txt rhs)
           lets
    in
    (* `a op b` <=> `b (flipped op) a` — used to normalise to `X op n`.  (No
       `dual`/negation step is needed here, unlike
       [Division_safety.path_proves_nonzero]: the caller below already
       filters to a POSITIVE path entry before [guard_discharges] runs — see
       condition 3's own "NEGATED guard" tests — so [cond] is always a fact
       read at face value, never one that needs de-negating first.) *)
    let flip = function
      | "<" -> ">" | ">" -> "<" | "<=" -> ">=" | ">=" -> "<="
      | op -> op (* == and != are symmetric *)
    in
    (* `X op n`, read as a closed-or-half-open integer interval.  [None] for
       either bound means unbounded on that side; [None] for the whole thing
       means "not a convex interval" (only `!=`). *)
    let interval_of op n : (int option * int option) option =
      match op with
      | ">"  -> Some (Some (n + 1), None)
      | ">=" -> Some (Some n, None)
      | "<"  -> Some (None, Some (n - 1))
      | "<=" -> Some (None, Some n)
      | "==" -> Some (Some n, Some n)
      | _ -> None
    in
    let interval_subset (lo1, hi1) (lo2, hi2) =
      let lo_ok =
        match lo2 with
        | None -> true
        | Some l2 -> (match lo1 with Some l1 -> l1 >= l2 | None -> false)
      in
      let hi_ok =
        match hi2 with
        | None -> true
        | Some h2 -> (match hi1 with Some h1 -> h1 <= h2 | None -> false)
      in
      lo_ok && hi_ok
    in
    (* Is [e] the predicate's own measure application (`len(_)`, `len(xs)`,
       …)?  Any application of the withdrawn measure name suffices — a
       parameter predicate has exactly one subject to measure. *)
    let is_measured_pred (w : withdrawal) (e : A.expr) : bool =
      match e with A.EApp (A.EVar n, _, _) -> n.A.txt = w.wd_measure | _ -> false
    in
    (* Read [pred] itself as `measure(subject) op n`.  Computed once per
       withdrawal candidate — [pred] does not vary with [cond]. *)
    let atomic_cmp (is_subject : A.expr -> bool) (e : A.expr) : (string * int) option =
      match e with
      | A.EApp (A.EVar op0, [ a; b ], _)
        when List.mem op0.A.txt [ "=="; "!="; "<"; "<="; ">"; ">=" ] -> (
        match b with
        | A.ELit (A.LitInt n, _) when is_subject a -> Some (op0.A.txt, n)
        | _ -> (
          match a with
          | A.ELit (A.LitInt n, _) when is_subject b -> Some (flip op0.A.txt, n)
          | _ -> None))
      | _ -> None
    in
    (* Does some subterm of [e] compare the withdrawn measure applied to the
       FREE subject against a literal, in a way that ENTAILS `(op2, n2)`
       (already known to be [pred]'s own comparison)?  Mirrors
       [expr_applies_to_free]'s shadow-respecting descent — same cases, same
       shadowing rules for the SUBJECT name (`sn`) — because this is asking
       the same question ("does the withdrawn spelling apply to the free
       subject somewhere in here") plus one more thing: not just THAT it
       applies, but WHAT the surrounding comparison says.  A guard buried
       inside an opaque call (`check(fn q -> List.length(ys) > 0, zs)`) still
       has a genuine, entailing comparison at that free position — nesting
       inside a call this pass cannot otherwise reason about must not by
       itself defeat entailment, or a case [guard_applies] already accepted
       ("a FREE occurrence … still attributes") would regress.  A lambda
       parameter that collides with the SUBJECT's name still closes off
       descent into that lambda's body, exactly as [expr_applies_to_free]
       already does — that is the discipline probe PE pinned, and this walk
       must not reopen it.

       [is_subject] reads a SECOND name channel besides the subject —
       [lets], the laundering table — and that channel needs its own
       shadow discipline: `let n = List.length(ys); if n >= 0 && any_pos(zs,
       fn n -> n > 0) do head(ys) …` must not read the LAMBDA's own `n` as
       the laundered length just because the string "n" is a laundering key
       somewhere in scope.  [shadowed] carries every name any binder passed
       on the way down has rebound (lambda/`let`/`let fn`/`let?`/match-arm),
       independent of whether that name happens to be the subject; a
       laundering lookup that hits a shadowed name is retired exactly as a
       path fact would be (see [path_shadow]) rather than trusted. *)
    let rec exists_discharging (w : withdrawal) (op2, n2) ~(shadowed : string list)
        (e : A.expr) : bool =
      let recur ?(bind = []) e = exists_discharging w (op2, n2) ~shadowed:(bind @ shadowed) e in
      let any ?(bind = []) es = List.exists (recur ~bind) es in
      let binds ps = List.mem sn.A.txt ps in
      let pbinds ps = List.exists (fun (p : A.param) -> p.A.param_name.A.txt = sn.A.txt) ps in
      let param_names ps = List.map (fun (p : A.param) -> p.A.param_name.A.txt) ps in
      let is_subject e =
        match e with
        | A.EApp (A.EVar n, args, _) ->
          n.A.txt = w.wd_spelling
          && List.exists (function A.EVar v -> v.A.txt = sn.A.txt | _ -> false) args
        | A.EVar { A.txt = m; _ } when not (List.mem m shadowed) -> (
          match List.assoc_opt m lets with
          | Some (A.EApp (A.EVar n, args, _)) ->
            n.A.txt = w.wd_spelling
            && List.exists (function A.EVar v -> v.A.txt = sn.A.txt | _ -> false) args
          | _ -> false)
        | _ -> false
      in
      let cmp_here =
        match atomic_cmp is_subject e with
        | Some (op1, n1) -> (
          match (interval_of op1 n1, interval_of op2 n2) with
          | Some i1, Some i2 -> interval_subset i1 i2
          | _ -> false)
        | None -> false
      in
      cmp_here
      ||
      match e with
      | A.EVar _ -> false
      | A.ELit _ | A.EHole _ | A.EResultRef _ | A.EDbg (None, _) -> false
      | A.EApp (f, args, _) -> recur f || any args
      | A.ECon (_, args, _) | A.EAtom (_, args, _) | A.ETuple (args, _) -> any args
      | A.ELam (ps, body, _) -> if pbinds ps then false else recur ~bind:(param_names ps) body
      | A.EBlock (es, _) ->
        (* Sequential, like [expr_applies_to_free]'s own [EBlock] case: a
           `let` (or `let fn`/`let?`) rebinding the SUBJECT shadows the rest
           of the block exactly as there (the [binds]/[sn.A.txt] checks
           below, unchanged); a `let` rebinding a LAUNDERING key instead
           retires that key from [is_subject]'s lookup for the rest of the
           block, via [shadowed], without discarding the whole branch — the
           subject itself may still be free elsewhere. *)
        let rec go (shadowed : string list) = function
          | [] -> false
          | e :: rest ->
            exists_discharging w (op2, n2) ~shadowed e
            ||
            (match e with
             | A.ELet (b, _) when binds (pat_binders b.A.bind_pat) -> false
             | A.ELetFn (n, _, _, _, _) when n.A.txt = sn.A.txt -> false
             | (A.ELetQ (p, _, _, _) | A.ELetStar (p, _, _, _)) when binds (pat_binders p) -> false
             | A.ELet (b, _) -> go (pat_binders b.A.bind_pat @ shadowed) rest
             | A.ELetFn (n, _, _, _, _) -> go (n.A.txt :: shadowed) rest
             | A.ELetQ (p, _, _, _) | A.ELetStar (p, _, _, _) -> go (pat_binders p @ shadowed) rest
             | _ -> go shadowed rest)
        in
        go shadowed es
      | A.ELet (b, _) -> recur b.A.bind_expr
      | A.ELetFn (n, ps, _, body, _) ->
        if n.A.txt = sn.A.txt || pbinds ps then false
        else recur ~bind:(n.A.txt :: param_names ps) body
      | A.ELetQ (p, e1, e2, _) | A.ELetStar (p, e1, e2, _) ->
        recur e1 || (if binds (pat_binders p) then false else recur ~bind:(pat_binders p) e2)
      | A.EMatch (subj, brs, _) ->
        recur subj
        || List.exists
             (fun (br : A.branch) ->
               let bs = pat_binders br.A.branch_pat in
               if binds bs then false
               else
                 (match br.A.branch_guard with Some g -> recur ~bind:bs g | None -> false)
                 || recur ~bind:bs br.A.branch_body)
             brs
      | A.ERecord (fs, _) -> List.exists (fun (_, v) -> recur v) fs
      | A.ERecordUpdate (r, fs, _) -> recur r || List.exists (fun (_, v) -> recur v) fs
      | A.EField (r, _, _) -> recur r
      | A.EIf (c, t, el, _) -> any [ c; t; el ]
      | A.ECond (arms, _) -> List.exists (fun (c, b) -> recur c || recur b) arms
      | A.EPipe (a, b, _) | A.ESend (a, b, _) -> recur a || recur b
      | A.EAnnot (e, _, _) | A.ESpawn (e, _) | A.EAssert (e, _) | A.ESigil (_, e, _)
      | A.EDbg (Some e, _) -> recur e
    in
    (* Does the guard fact [cond] — already known to apply [w]'s spelling to
       this subject, and already filtered to a POSITIVE path entry by the
       caller below — actually ENTAIL [pred]?  The laundered spelling (`if n
       > 0 …` after `let n = List.length(ys)`) is handled by substituting the
       laundering name's bound expression in wherever [cond] free-mentions
       it, one hop only — mirroring [guard_applies]'s own laundered arm. *)
    let guard_discharges (w : withdrawal) (cond : A.expr) : bool =
      match atomic_cmp (is_measured_pred w) pred with
      | None -> false
      | Some (op2, n2) ->
        exists_discharging w (op2, n2) ~shadowed:[] cond
        || List.exists
             (fun (m, rhs) ->
               expr_mentions_free m cond && exists_discharging w (op2, n2) ~shadowed:[] rhs)
             lets
    in
    List.find_opt
      (fun w ->
        w.wd_str = subject_is_str
        && expr_applies w.wd_measure pred
        && List.exists
             (fun (cond, negated) ->
               (not negated) && guard_applies w cond && guard_discharges w cond)
             path)
      !withdrawals
  (* A non-variable actual (`head(f(xs))`) carries no name a guard could be
     matched against, so we cannot show the guard was about THIS value. *)
  | _ -> None

(* ── Check one refined parameter at a call site ──────────────────────────── *)
(* [path] is the path context: conditions known true here, each tagged with
   whether it is negated (the else-branch of an `if`). *)
(* What the refined value being checked IS, for diagnostics only.  `Argument` is
   a real call's actual; `Bound_expr` is the right-hand side of an annotated
   `let`, which reaches this function through a SYNTHESIZED one-parameter
   [fn_sig] (see [check_let_annotation]).  The obligation itself is identical —
   "does this expression satisfy this predicate" — but "argument does not
   satisfy precondition" reads as nonsense at a `let`, where the author called
   nothing, so the two user-facing messages branch on this. *)
type check_subject =
  | Argument
  | Bound_expr

(* Span of an expression, for pointing a diagnostic at ONE argument instead of
   the whole call. [refinecheck] does not depend on [march_typecheck], so this
   mirrors its [span_of_expr] rather than importing it; only the forms that can
   appear in argument position need to be precise, and anything unlisted falls
   back to the caller-supplied call span (never a dummy, which would render as
   a phantom location at line 0). *)
let arg_span (fallback : A.span) : A.expr -> A.span = function
  | A.ELit (_, sp) | A.EApp (_, _, sp) | A.ECon (_, _, sp)
  | A.ETuple (_, sp) | A.ERecord (_, sp) | A.EField (_, _, sp)
  | A.EIf (_, _, _, sp) | A.EPipe (_, _, sp) | A.EAnnot (_, _, sp)
  | A.EBlock (_, sp) | A.EMatch (_, _, sp) | A.ELam (_, _, sp)
  | A.EAtom (_, _, sp) -> sp
  | A.EVar name -> name.A.span
  | _ -> fallback

(* =================================================================
   §15 check_call — precondition checking at a call site
   ================================================================= *)

(* The environment [check_call] discharges an obligation IN, as opposed to the
   obligation itself.  Every field is threaded unchanged through the whole of
   [visit]'s walk of one call node, so bundling them stops a twelve-parameter
   signature from having to be re-read at each of the three call sites — and
   gives each thread a place to say what it is, which is the documentation
   this function has never had.

   The four things that differ per obligation stay explicit parameters:
   [~span] / [~callee] (which call), [sg] / [args] (its signature and actuals)
   and [rp] (which refined parameter of it), plus [?subject] / [?verdict_out],
   which only the `let`-annotation caller sets. *)
type call_ctx = {
  root : string;
      (* Project root — passed to [Refine.discharge] so the SMT bridge can
         place its scratch files and resolve solver configuration. *)
  errctx : Err.ctx;
      (* Diagnostic sink.  [check_call] is a REPORTING site: every exit path
         records an outcome through [note], and violations are emitted here. *)
  postcond :
    string -> A.expr list -> (string * A.expr * string option) option;
      (* Return refinement of a callee, by name and actuals — how a nested
         call's postcondition becomes a premise for this one.  Always
         [postcond_of ctx defs] at every call site; it is a parameter rather
         than a direct call because [rctx]/[defs] are not in scope here. *)
  path : (A.expr * bool) list;
      (* Path facts: the guards (and their polarity) reaching this call site.
         One of the two fact channels — see the shadowing discipline note in
         §10: a name rebound in between must retire from BOTH this and
         [sc], or a stale fact proves a goal about a different value. *)
  lets : launder;
      (* Laundering `let`s: bindings whose RHS lets a guard about one name be
         re-attributed to another.  Retires on rebinding of either the key or
         any name its RHS mentions. *)
  sc : scope;
      (* The other fact channel: refined locals and parameters in scope, name
         -> (binder, predicate, sort). *)
  re : recenv;
      (* Record-typed variables in scope, name -> SMT sort name, so a
         predicate's `v.field` projections can be resolved through that
         sort's selectors. *)
}

let check_call (cx : call_ctx) ~span ~(callee : string) ?(subject = Argument)
    ?(verdict_out : Obligation.verdict option ref option)
    (sg : fn_sig) (args : A.expr list) (rp : rparam) : unit =
  (* Destructured to the names the body has always used: this is a signature
     change, not a rewrite of 1,361 lines. *)
  let { root; errctx; postcond; path; lets; sc; re } = cx in
  let subject_noun = match subject with Argument -> "argument" | Bound_expr -> "bound expression" in
  let obligation_noun =
    match subject with Argument -> "precondition" | Bound_expr -> "type annotation"
  in
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
  (* The SCALAR sort a callee parameter (and hence the actual passed to it)
     lives at.  `Int` unless the callee declared it `Bool`. *)
  let scalar_at_idx i =
    match List.nth_opt sg.param_scalar i with Some s -> s | None -> Smt.SInt
  in
  let scalar_of_name name =
    match List.assoc_opt name name_pos with Some i -> scalar_at_idx i | None -> Smt.SInt
  in
  (* The refined value's own scalar sort, read from its refinement's base type.
     [rp.sort] and [sg.param_scalar] are computed from the same declared type,
     so they agree; this spelling also covers a synthesized callback sig. *)
  let self_scalar = scalar_sort_or_int rp.sort in
  (* Every exit below records an outcome.  All but one of them are silent to the
     USER by design (the definite-failure stance: only a predicate that can
     never hold is reported); silent to the LEDGER is what this fixes, so a
     contract that checks nothing is distinguishable from one that passes.
     Recording is observation-only — it must never alter control flow. *)
  let note verdict =
    (* Re-attribute BEFORE recording, not just in the error text: the ledger is
       what `--refine-report` prints, and a ledger that disagrees with the
       diagnostic is a second thing to be confused by. *)
    let verdict, cause =
      match verdict with
      | Obligation.Skipped r ->
        (* The obligation's own SUBJECT — the actual passed at [rp.idx].  Read
           here rather than taken from the enclosing [self_actual] because
           [note] is in scope before that binding, and because a missing
           argument must simply mean "no attribution". *)
        (match
           alias_withdrawal_cause ~pred:rp.pred
             ~subject:(List.nth_opt args rp.idx)
             ~subject_is_str:(rp_is_str rp) ~path ~lets r
         with
         | Some w -> (Obligation.Skipped (Obligation.Alias_withdrawn w.wd_spelling), w.wd_span)
         | None -> (verdict, None))
      | _ -> (verdict, None)
    in
    (* `@[trusted]` accepts a SKIP as an assertion, recorded as its own verdict
       rather than escalated — see [trusted_fn].  This must run before the
       verdict is recorded (not just before the escalation match below), or
       the ledger would say `Skipped` while the diagnostic behaved as if it
       were `Trusted`.  A [Violated] is deliberately untouched: it never
       reaches this branch because it is not a [Skipped _] to begin with — a
       predicate the solver proved can never hold is a bug in the annotation,
       not an incompleteness `@[trusted]` may wave through. *)
    let verdict =
      match verdict with
      | Obligation.Skipped _ when !trusted_fn -> Obligation.Trusted
      | _ -> verdict
    in
    Obligation.record
      { Obligation.span; callee; predicate = pred_str rp.pred; verdict
      ; kind = Obligation.Precondition };
    Option.iter (fun r -> r := Some verdict) verdict_out;
    (* …except inside a `cap verified` module, where a skip is the very thing
       the user asked to be told about (see [strict_verified]).  `Proved` and
       `Violated` are unaffected: the latter already reported itself.  A
       [Skipped] that was just turned into [Trusted] above no longer matches
       here, which is how `@[trusted]` suppresses the escalation. *)
    match verdict with
    | Obligation.Skipped r when !strict_verified ->
      (* The remedy depends on the reason.  The generic advice below is worse
         than useless for a withdrawn alias — "guard the call" is what the
         author already did — so that case gets its own note, naming the
         binding to rename and, when we found it, where it is. *)
      let remedy =
        match r with
        | Obligation.Alias_withdrawn spelling ->
          let where =
            match cause with
            | Some (sp : A.span) when sp.A.file <> "" ->
              Printf.sprintf " (%s:%d)" sp.A.file sp.A.start_line
            | Some (sp : A.span) -> Printf.sprintf " (line %d)" sp.A.start_line
            | None -> ""
          in
          Printf.sprintf
            "note: at least one binding of `%s` in this compilation unit%s \
             withdrew the alias for the WHOLE unit, including this call — the \
             gate is unit-global and syntactic, so it does not matter whether \
             that binding could ever win here.  There may be others: renaming \
             or moving every one of them out of this unit restores the alias, \
             and restating the fact as a refinement avoids the guard entirely"
            spelling where
        | _ ->
          (match subject with
           | Argument ->
             "note: guard the call or strengthen what is known here, rewrite \
              the predicate into the fragment the checker supports, or remove \
              `cap verified` from this module — it asks for every obligation \
              to be discharged"
           | Bound_expr ->
             "note: bind an expression the checker can see satisfies this \
              annotation, weaken the annotation, or remove `cap verified` from \
              this module — it asks for every obligation to be discharged")
      in
      Err.error errctx ~span
        (Printf.sprintf
           "`cap verified` module: cannot verify %s `%s` on `%s` (%s: %s)\n%s"
           obligation_noun (pred_str rp.pred) callee (Obligation.reason_name r)
           (Obligation.reason_detail r) remedy)
    (* Outside `cap verified`, a skip stays non-fatal — but say once per module
       that it happened, so "no diagnostic" cannot be read as "checked". A
       withdrawn alias is excluded: it has its own dedicated explanation and is
       not the checker running out of road. *)
    | Obligation.Skipped r
      when (not !strict_verified) && (not !unverified_hinted)
           && (match r with Obligation.Alias_withdrawn _ -> false | _ -> true) ->
      unverified_hinted := true;
      Err.hint errctx ~span
        (* Hard-wrapped near 78 columns. The renderer does not reflow, so a
           single long line is left to the terminal to break wherever it
           happens to run out of width — mid-token, and differently in every
           window. *)
        (Printf.sprintf
           "%s `%s` on `%s` was NOT verified here.\n\
            reason: %s — %s\n\
            note: March reports only definite failures, so a contract it \
            cannot decide\n\
            is accepted in silence. Add `cap verified` to this module to make \
            every\n\
            unverifiable obligation an error instead; `--refine-report` lists \
            them all."
           obligation_noun (pred_str rp.pred) callee
           (Obligation.reason_name r) (Obligation.reason_detail r))
    | _ -> ()
  in
  match List.nth_opt args rp.idx with
  | None -> ()
  | Some self_actual ->
    let decls = ref [] and assume = ref [] in
    (* ── Caller-scope scalar sorts ─────────────────────────────────────────
       A path condition mentions CALLER variables and reflects each to
       `Const name`; so does an argument that IS that variable.  The two must
       agree on a sort, or the VC declares one symbol twice and z3 rejects it.
       The only names whose sort this call pins are the ones it passes to a
       parameter of known scalar sort, so those are recorded here and consulted
       by every caller-namespace producer.  A name not listed keeps the
       pre-existing default, `Int`. *)
    let caller_scalar : (string, Smt.sort) Hashtbl.t = Hashtbl.create 4 in
    List.iteri
      (fun i a ->
        match a with
        | A.EVar { A.txt = x; _ } ->
          let s = scalar_at_idx i in
          if s <> Smt.SInt then Hashtbl.replace caller_scalar x s
        | _ -> ())
      args;
    let caller_scalar_of name =
      match Hashtbl.find_opt caller_scalar name with Some s -> s | None -> Smt.SInt
    in
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
       codegen, so bytes is not a conservative guess, it is what that builtin
       means.  OCaml's [String.length] over the already-unescaped literal is
       exactly that.

       March DOES have a codepoint-length primitive — `String.codepoint_count`,
       which returns 1 for "é" where every byte-length spelling returns 2.  It
       is simply not what `$strlen` denotes, and must never be aliased to it;
       see [measure_alias].  (An earlier revision of this comment claimed the
       language had no such primitive.  It does, and reasoning from that claim
       is how a codepoint count nearly got equated with a byte count.) *)
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
    (* `a.rem` appearing as an ACTUAL argument.  Deliberately the same
       construction [path_resolve_field] uses below for `a.rem` in a PATH
       CONDITION — the record's SMT selector applied to `Const a` — because the
       guard and the goal only meet if both sides land on the identical term.
       The declaration is RETURNED (via [reflect_scalar]'s decls channel and
       [absorb]) rather than pushed straight onto [decls], so a field read that
       never makes it into the goal contributes no stray declaration.
       A receiver outside [recenv] (no known record sort) stays None: the
       obligation is skipped exactly as before, never guessed. *)
    let arg_resolve_field varname fname =
      match List.assoc_opt varname re with
      | None -> None
      | Some sort_name ->
        (match make_field_resolver varname sort_name (Smt.Const varname)
                 varname fname with
         | None -> None
         | Some t ->
           if not (List.mem sort_name !adt_sorts) then
             adt_sorts := sort_name :: !adt_sorts;
           Some (t, [ (varname, Smt.SData sort_name) ]))
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
      (* A direct CALL returning a record, whose callee has a PROVEN
         postcondition at this very record sort.  Records are a subset of the
         ADT sorts, so the Int postcondition path ([reflect_scalar]) and the
         variant path ([reflect_dt]) both already carried their return
         refinements to call sites; only the record shape was dropped here, so
         `needLow(mk())` was silently skipped while the identically-shaped Int
         version was caught.

         The result becomes a FRESH constant — never a name borrowed from the
         caller, so it cannot collide with a symbol declared at another sort —
         carrying the instantiated postcondition as an assumption.

         Two guards keep this from guessing.  The sort equality test: a
         postcondition about some OTHER record says nothing about this one and
         asserting it here would be ill-sorted.  And [gate_unverified_posts]
         has already cleared [ret] on every signature whose postcondition the
         DEFINITION side did not prove, so anything [postcond] returns is a
         fact rather than a trusted contract. *)
      | A.EApp (A.EVar { A.txt = fname; _ }, cargs, _) -> (
        match postcond fname cargs with
        | Some (b, q, Some srt) when srt = sort_name ->
          incr ret_ctr;
          let nm = Printf.sprintf "%s$rec%d" fname !ret_ctr in
          let c = Smt.Const nm in
          decls := (nm, Smt.SData sort_name) :: !decls;
          (* [q] is already in the CALLER's namespace ([postcond_of] substituted
             the actuals).  Its binder — and its `b.field` projections — must
             resolve against the SAME term the goal projects from. *)
          let rv n = if n = b || n = "_" then Some c else None in
          let rf = make_field_resolver b sort_name c in
          (match smt_of ~resolve_var:rv ~resolve_measure:(fun _ _ -> None)
                   ~resolve_field:rf q with
           | Some qa -> assume := qa :: !assume
           (* Untranslatable predicate: the constant stays unconstrained, so
              neither the goal nor its negation is provable and the call is
              simply skipped. *)
           | None -> ());
          Some c
        | _ -> None)
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
    (* The SMT symbol standing for the refined value in MEASURE position.
       Both spellings of the binder — the anonymous `_` of `{Tree | size(_) < 0}`
       and the named `v` of `{v : Tree | size(v) < 0}` — denote the same value,
       so both must reflect to one canonical symbol.  Emitting the binder's
       source name instead was wrong twice over:

         - `_` is a RESERVED SMT-LIB token (it heads indexed identifiers such
           as `(_ is Ctor)`), so `(declare-const _ M_Tree)` made z3 answer
           `(error …)`.  The predicate was therefore never decided — and `_` is
           the DOCUMENTED idiom, so the spelling the docs teach silently
           checked nothing while the named spelling worked.  Worse, a malformed
           VC on the shared `z3 -in` channel is not merely a missed check.
         - a named binder that collides with a caller-scope Int variable would
           put one symbol at two sorts, the same hazard [is_recvar] guards.

       `$self` cannot collide with a March identifier. *)
    (* The Int symbol standing for `m(x)` where [x] is a March NAME — the one
       channel through which a non-axiomatised measure over a variable is
       reflected, on the goal side and (via [load_scope_measure_facts] below) on
       the assumption side.  Memoized per `(m, x)` so BOTH sides name the symbol
       exactly once: z3 rejects a duplicate `declare-const` as a hard error, and
       a malformed VC comes back `Unknown`, i.e. an ordinary-looking SKIP with no
       signal that anything went wrong.  (This VC builder does deduplicate
       [decls] by (name, sort) pair before rendering, so an identical second
       declaration would in fact have survived; the memo does not rely on that,
       and it additionally keeps the `>= 0` assumption from being asserted
       twice.) *)
    let measure_var_cache : (string, Smt.term option) Hashtbl.t = Hashtbl.create 8 in
    let measure_of_var m x =
      let nm = m ^ "$" ^ x in
      match Hashtbl.find_opt measure_var_cache nm with
      | Some cached -> cached
      | None ->
        let c = Smt.Const nm in
        decls := (nm, Smt.SInt) :: !decls;
        (* `len` is known non-negative; user measures get no axiom in v1 (sound;
           guarded uses still discharge via the path context). *)
        if is_nonneg_measure m then assume := Smt.Ge (c, Smt.IntLit 0) :: !assume;
        let r = Some c in
        Hashtbl.replace measure_var_cache nm r;
        r
    in
    (* ── Caller-namespace resolvers for a caller-scope refinement's OWN
       predicate ─────────────────────────────────────────────────────────────
       Passed to [reflect_scalar] so a promise mentioning a sibling parameter
       survives instead of being discarded whole (see its header).  The name is
       a CALLER variable and denotes ITSELF, exactly as [path_resolve_var]
       treats a name in a path condition — the same discipline, and for the same
       reason: routing it through the goal-side resolvers would silently
       re-point it at a callee actual whenever the two happen to share an
       identifier.

       The two sort guards are not optional.  A `Str`-sorted or record-sorted
       name re-declared here at `Int` puts one symbol at two sorts, which makes
       z3 emit an error line — and a malformed VC on the shared `z3 -in` channel
       desynchronises it and silently switches refinement checking off for the
       rest of the compilation.  Returning [None] instead drops the sub-term and
       with it the fact, which only loses a proof. *)
    let foreign_var name =
      if Hashtbl.mem str_names name then None
      else if is_recvar name then None
      else Some (Smt.Const name, (name, caller_scalar_of name))
    in
    (* Route measures through the SAME memo the goal side uses, so a promise
       about `len(xs)` and a goal about `len(xs)` land on the one `len$xs`
       symbol.  Two independently-declared constants would be two unrelated
       integers and the fact would connect to nothing — a skip that looks
       exactly like a proof from outside. *)
    let foreign_measure m name = measure_of_var m name in
    let self_dt_sym = "$self" in
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
        absorb
          (reflect_cached "$self" (fun () ->
               reflect_scalar ~postcond ~foreign_var ~foreign_measure
                 ~foreign_field:arg_resolve_field
                 ~sort:self_scalar sc self_actual))
      else
        match actual_of_name name with
        | Some a ->
          absorb
            (reflect_cached name (fun () ->
                 reflect_scalar ~postcond ~foreign_var ~foreign_measure
                   ~foreign_field:arg_resolve_field
                   ~sort:(scalar_of_name name) sc a))
        | None ->
          (* a caller-scope variable from the path context *)
          if Hashtbl.mem str_names name then Some (Smt.Const name)
          (* …unless it is a caller-scope RECORD, which lives at a datatype sort.
             Declaring it `Int` here would put one symbol at two sorts; dropping
             the sub-term instead just loses a fact (silence). *)
          else if is_recvar name then None
          else begin
            decls := (name, caller_scalar_of name) :: !decls;
            Some (Smt.Const name)
          end
    in
    (* ── A caller-scope refined ADT parameter's own promise ──────────────────
       `fn outer(ys : {List(Int) | len(_) > 0}) … inner(ys)`: the goal for the
       inner call is `len$ys > 0`, and until this existed nothing said anything
       about `len$ys`, so the VC was satisfiable both ways and the call was
       SKIPPED — while the identically-shaped `Int` version composed, because
       [reflect_scalar]'s `EVar` arm consults [sc] for scalar sorts and there is
       no scalar sort for a list.

       So: when the actual is a bare name carrying a MEASURE-ONLY scope entry
       ([meas_sort_prefix]), reflect that entry's own predicate as an assumption.
       Three restrictions keep this from guessing:

         - the predicate's measures must apply to the entry's OWN refined value.
           That value has THREE spellings, all of which denote it and all of
           which must resolve identically: the anonymous `_`, the annotation's
           declared binder `v` (`{v : List(Int) | len(v) > 0}`), and the
           parameter's OWN name `ys` (`{List(Int) | len(ys) > 0}`).  A measure
           over any OTHER name is a different value; returning None there drops
           the whole predicate rather than mis-attributing it.

           Accepting only the first two (as this did until 2026-07-29) is the
           same spelling-class bug the GOAL side carried until 2026-07-27, in
           this same file: the third spelling silently composed nothing, so
           `fn outer(ys : {List(Int) | len(ys) > 0}) do inner(ys) end` stayed
           `1 proved, 1 skipped` while the other two spellings proved both
           calls.  A skip emits no diagnostic, so renaming a binder into the
           parameter's own name silently unwired composition.  All three
           spellings are now pinned by tests in BOTH directions (the positive
           case AND a weaker `len(ys) >= 0` control that must still skip).
         - the fact must be phrased over the SAME symbol the goal side uses for
           this value, which differs by measure class:
             · a NON-axiomatised measure (list `len`, a plain user measure) is a
               bare uninterpreted Int, `m$x`, via the memoized [measure_of_var];
             · an AXIOMATISED `@[measure]` ranges over the datatype itself, so
               the fact is `(m x)` with `x` declared at the measure's ADT sort —
               the same term the goal side builds when it reflects the actual
               `EVar x` through [reflect_dt].  That form only MEANS anything if
               the quantified-axiom preamble is attached to this VC, so it sets
               the very [uses_axiom] ref that gates it (defined once for the
               whole VC above; a second, disconnected flag would leave the
               assumption in the VC with nothing to interpret it).
         - [resolve_var] is `None` throughout: the binder denotes a LIST, not a
           scalar, so any predicate that mentions a variable OUTSIDE a measure
           is dropped entirely.  No approximation.  A measure over some other
           name IS translated — see [rm]'s non-self branch below — but only to
           the term the goal side builds for that same name.

       Sound direction: this only ADDS a hypothesis that the caller's own
       signature already promises about this very value, over the same symbol.
       It is loaded at most once per name per VC (the [done] table), so the
       assumption list cannot grow with the number of occurrences.

       Shadowing is handled upstream and not here: [scope_shadow] retires the
       name from [sc] at every binding construct, so after `let ys = tail(ys)`
       the lookup simply finds nothing and no fact is loaded.  Its SECOND
       trigger covers the relational case: an entry whose predicate MENTIONS a
       rebound name is retired too, so `let r = push(t, 5)` followed by a rebind
       of `t` drops `r`'s promise rather than re-reading `t` at its new value. *)
    let scope_facts_loaded : (string, unit) Hashtbl.t = Hashtbl.create 4 in
    let load_scope_measure_facts (x : string) : unit =
      if not (Hashtbl.mem scope_facts_loaded x) then begin
        Hashtbl.replace scope_facts_loaded x ();
        match List.assoc_opt x sc with
        | Some (b, q, Some s) when is_meas_sort s ->
          let rv _ = None in
          (* All three spellings of the refined value — `_`, the declared binder
             [b], and the scope entry's own name [x] — denote it.  See the note
             above; the goal side's [is_self]/[actual_of_name] pair already
             accepts the same three. *)
          let is_self_spelling n = n = b || n = "_" || n = x in
          (* ── A RELATIONAL carried predicate's OTHER names ───────────────────
             `fn push(t, x) : {Tree | size(_) == size(t) + 1}` stored against
             `let r = push(t, 5)` arrives here as `size(_) == size(t) + 1`,
             ALREADY in the caller's namespace ([postcond_of] substituted the
             actuals simultaneously, or abandoned propagation entirely).  So a
             non-self name denotes ITSELF, a caller-scope value — the same
             discipline [foreign_var]/[foreign_measure] apply to a refined
             parameter's own promise, and for the same reason: routing it
             through the GOAL-side resolvers would silently re-point it at a
             callee actual whenever a caller variable and a callee parameter
             happen to share a spelling.

             Refusing it outright (as this did until 2026-08-04) drops the
             sub-term, and [smt_of] then drops the WHOLE predicate: no
             assumption, VC satisfiable both ways, call silently skipped.  That
             is what made the motivating repro `needs_bigger(t, r)` report
             `1 proved, 1 skipped` with no diagnostic.

             What is emitted must be the term the GOAL side builds for the same
             name, or the fact connects to nothing and the skip merely looks
             like a proof:
               · axiomatised `@[measure]`: `(m n)` with `n` declared at the
                 measure's ADT sort — exactly what [reflect_dt]'s `EVar` arm
                 produces for this actual (goal side, [resolve_measure]), and
                 what its caller-scope fallback produces when the name is not a
                 callee parameter at all;
               · everything else: the memoized `m$n` from [measure_of_var],
                 which is literally the same call the goal side makes.
             A FRESH constant here would be the `{List(a) | len(_) > 0}` bug
             again — trivially satisfiable, hence a contract that enforces
             nothing while appearing to work.  The REJECT CONTROL test (a
             demand for a SMALLER tree, which `push` never provides) is what
             distinguishes the two.

             Shadowing needs nothing here: [scope_shadow] retires an entry both
             when its own name is rebound AND when its predicate MENTIONS a
             rebound name ([expr_mentions]), so a `t` rebound between the `let`
             and the call removes the whole entry rather than re-pointing this
             `Const t` at the new binding.  That second trigger already exists
             precisely because a promise may mention another name.

             Fail-closed: the sort guards (a `Str` name, a record name, a name
             already pinned to a non-Int scalar sort) drop the sub-term — and
             with it the whole fact — for a name this VC already knows at some
             other sort.  They are a cheap FIRST filter, not the invariant: what
             actually guarantees a one-symbol-two-sorts VC never reaches z3 (a
             single error line there desynchronises the shared `z3 -in` channel
             and silently switches refinement checking off for the rest of the
             compilation) is the [sort_conflict decls] gate further down, which
             sees the finished declaration list.  Losing a fact only loses a
             proof. *)
          let rm m' n =
            if not (is_self_spelling n) then
              if Hashtbl.mem str_names n || is_recvar n
                 || caller_scalar_of n <> Smt.SInt
              then None
              else if is_axiom_measure m' then begin
                let adt = Hashtbl.find axiom_measures m' in
                uses_axiom := true;
                decls := (n, Smt.SData adt) :: !decls;
                Some (Smt.App (m', [ Smt.Const n ]))
              end
              else measure_of_var m' n
            else if is_axiom_measure m' then begin
              (* Gate the quantified-axiom preamble on the SHARED per-VC ref, so
                 `(m x)` here and `(m x)` in the goal are interpreted by the same
                 axioms.  Both this and the goal side declare `x` at the sort; the
                 VC builder deduplicates [decls] by (name, sort), and the
                 per-name [scope_facts_loaded] memo keeps a repeated occurrence
                 of the same name from re-loading the fact at all. *)
              let adt = Hashtbl.find axiom_measures m' in
              uses_axiom := true;
              decls := (x, Smt.SData adt) :: !decls;
              Some (Smt.App (m', [ Smt.Const x ]))
            end
            else measure_of_var m' x
          in
          (match smt_of ~resolve_var:rv ~resolve_measure:rm q with
           | Some qa -> assume := qa :: !assume
           | None -> ())
        | _ -> ()
      end
    in
    (* ── A caller-scope refined ADT parameter's own CONSTRUCTOR-TAG promise ───
       The tester analogue of [load_scope_measure_facts], and the same gap:

         fn inner(o : {Option(Int) | is_Some(_)}) : Int do 0 end
         fn outer(p : {Option(Int) | is_Some(_)}) : Int do inner(p) end

       The goal for `inner(p)` is `((_ is Some) p)`, and [reflect_dt]'s `EVar`
       arm declares `p` as a FRESH, UNCONSTRAINED datatype constant — so the VC
       was satisfiable both ways and the call was SKIPPED, silently, while the
       measure-shaped version of the very same composition proved.  `outer`'s
       own signature already promises exactly this tag about exactly this value,
       so the fact is available; nothing was consulting [sc] for it.

       What fires, and only this:

         - the actual is a bare name [x] carrying a MEASURE-ONLY scope entry
           ([meas_sort_prefix] — the marker [refined_scope_ty] gives every
           registered non-record ADT, `Option` included);
         - that entry's predicate is EXACTLY a bare tester application over the
           entry's OWN refined value — no conjunction, no negation, no other
           subject.  All THREE spellings of that value are accepted: the
           anonymous `_`, the annotation's declared binder [b], and the
           parameter's own name [x].  Missing one of the three is the spelling
           class that has shipped broken three times in this file (twice on the
           measure side, once on the goal side); a skip emits no diagnostic, so
           the omission is invisible until someone renames a binder;
         - the tester's constructor is the SAME constructor this goal tests, and
           belongs to the SAME datatype sort [adt].  A DIFFERENT constructor is
           deliberately not loaded: `is_None(_)` composing into a callee that
           wants `is_Some(_)` would be sound to assume (and would turn the call
           into a reported violation, since the two are exclusive), but it is a
           strictly wider claim than "the caller already promised the goal", and
           a missed report costs nothing here while a wrong one is the failure
           this subsystem exists to prevent.

       The fact is phrased over `Const x` at sort [adt] — the very term
       [reflect_dt]'s `EVar` arm builds for this actual on the GOAL side — so
       assumption and goal meet on one symbol.  Both sides also emit the same
       `(x, SData adt)` declaration; the VC builder deduplicates [decls] by
       (name, sort) before rendering, and the per-(name, ctor) memo below keeps
       a repeated occurrence from re-asserting the assumption.

       Sound direction: this only ADDS a hypothesis the caller's own signature
       already states about this very value.  Shadowing is handled upstream by
       [scope_shadow], which retires the name from [sc] at every binding
       construct, so after `let p = None` or a `match` arm binding `p` the
       lookup finds nothing and no fact is loaded. *)
    let tester_facts_loaded : (string, unit) Hashtbl.t = Hashtbl.create 4 in
    let load_scope_tester_facts (adt : string) (goal_ctor : string) (x : string) : unit =
      let key = x ^ "|" ^ adt ^ "|" ^ goal_ctor in
      if not (Hashtbl.mem tester_facts_loaded key) then begin
        Hashtbl.replace tester_facts_loaded key ();
        match List.assoc_opt x sc with
        | Some (b, q, Some s) when is_meas_sort s -> (
          match q with
          | A.EApp (A.EVar { A.txt = t; _ }, [ A.EVar { A.txt = n; _ } ], _)
            when n = b || n = "_" || n = x -> (
            match ctor_of_tester t with
            | Some ctor when ctor = goal_ctor && sort_of_ctor ctor = Some adt ->
              decls := (x, Smt.SData adt) :: !decls;
              if not (List.mem adt !adt_sorts) then adt_sorts := adt :: !adt_sorts;
              assume := Smt.IsCtor (ctor, Smt.Const x) :: !assume
            | _ -> ())
          | _ -> ())
        | _ -> ()
      end
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
      (* ── Tier 2 propagation ────────────────────────────────────────────────
         A CALL returning a value at this very datatype sort, whose callee has a
         PROVEN postcondition (an unproven one has already been cleared by
         [gate_unverified_posts]).  It becomes a fresh opaque constant of the
         sort, carrying the instantiated postcondition as an assumption — the
         datatype analogue of [reflect_scalar]'s call branch.
         The sort equality test is load-bearing: a postcondition about a value
         of some OTHER datatype says nothing about this one, and asserting it
         about this constant would be ill-sorted. *)
      | A.EApp (A.EVar { A.txt = fname; _ }, cargs, _) -> (
        match postcond fname cargs with
        | Some (b, q, Some srt) when srt = adt ->
          incr ret_ctr;
          let nm = Printf.sprintf "%s$dt%d" fname !ret_ctr in
          let c = Smt.Const nm in
          decls := (nm, Smt.SData adt) :: !decls;
          (* [q] is already in the CALLER's namespace (postcond_of substituted
             the actuals), so every remaining variable denotes itself.  A
             measure over the binder applies to [c]; a measure over any other
             term is reflected at the measure's own ADT sort. *)
          let rv n = if n = b || n = "_" then Some c else None in
          let rm m x =
            if not (is_axiom_measure m) then None
            else begin
              uses_axiom := true;
              if x = b || x = "_" then Some (Smt.App (m, [ c ]))
              else
                let a = Hashtbl.find axiom_measures m in
                Option.map
                  (fun t -> Smt.App (m, [ t ]))
                  (reflect_dt a (A.EVar { A.txt = x; A.span }))
            end
          in
          let rma m arg_term =
            if not (is_axiom_measure m) then None
            else
              match concrete_measure_app m arg_term with
              | Some n -> Some (Smt.IntLit n)
              | None -> uses_axiom := true; Some (Smt.App (m, [ arg_term ]))
          in
          (match smt_of ~resolve_var:rv ~resolve_measure:rm ~resolve_measure_app:rma q with
           | Some qa -> assume := qa :: !assume
           (* Untranslatable predicate: the constant stays unconstrained, which
              proves nothing in either direction — the call is simply skipped. *)
           | None -> ());
          Some c
        | _ -> None)
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
        (* The subject is a bare caller-scope name: load whatever the CALLER's
           own signature promises about its TAG first, so the promise and the
           goal meet on the one `Const x` symbol [reflect_dt] is about to
           build for it.  Mirrors the measure side's load-before-reflect. *)
        (match subject with
         | A.EVar { A.txt = x; _ } -> load_scope_tester_facts adt ctor x
         | _ -> ());
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
        (* BOTH spellings resolve against the SAME actual argument, exactly as
           the non-axiomatised branch below does — the anonymous `_`, the named
           binder and (for a cross-argument name) that parameter's own name all
           denote the value being passed.

           Until this, the self spellings routed to an UNCONSTRAINED datatype
           constant [self_dt_sym] instead, discarding [self_actual].  So
           `{Tree | size(_) > 0}` was decided only by `size`'s own axioms about
           an arbitrary tree — satisfiable both ways — and every call was
           SKIPPED, including `inner(Node(Leaf, 5, Leaf))` (provable: the
           recursion axioms compute 1) and `inner(Leaf)` (a real violation:
           they compute 0).  A contract in that shape enforced nothing at all,
           silently, while the same measure over ANOTHER parameter's name
           (`{Int | _ < size(t)}`) worked, because that path already reflected
           the actual.

           Reflecting the actual is also what lets the CALLER's own promise meet
           this goal: for `EVar x` [reflect_dt] yields `Const x` at the ADT sort,
           the same term [load_scope_measure_facts] phrases its assumption over.
           Hence the load below, before reflecting.

           The fallback keeps the previous behaviour where there is nothing to
           reflect (an actual that is neither a variable, a constructor literal,
           nor a call with a proven postcondition): an unconstrained constant,
           i.e. SAT, i.e. a skip. *)
        let actual = if is_self name then Some self_actual else actual_of_name name in
        match actual with
        | None ->
          decls := (name, Smt.SData adt) :: !decls;
          Some (Smt.App (m, [ Smt.Const name ]))
        | Some a ->
          (match a with A.EVar { A.txt = x; _ } -> load_scope_measure_facts x | _ -> ());
          (match reflect_dt adt a with
           | Some t -> Some (Smt.App (m, [ t ]))
           | None ->
             if is_self name then begin
               decls := (self_dt_sym, Smt.SData adt) :: !decls;
               Some (Smt.App (m, [ Smt.Const self_dt_sym ]))
             end
             else None))
      else
        (* A measure with no axioms (a user measure, or list `len`).  All three
           spellings of the refined value — the anonymous `_`, the named binder
           `v`, and the parameter's own name `xs` — denote the SAME value, so all
           three must resolve against the SAME actual argument.  Routing `_`/`v`
           to a fresh constant instead (as this did until 2026-07-27) made
           `{List(a) | len(_) > 0}` and `{v : List(a) | len(v) > 0}` reflect to
           an unconstrained non-negative integer: satisfiable, hence never a
           definite failure, hence SILENT.  The contract parsed, typechecked and
           checked nothing, while the third spelling worked — so a stdlib author
           following the documented `_` idiom got no enforcement at all, and
           renaming a parameter silently unenforced a working contract. *)
        let actual = if is_self name then Some self_actual else actual_of_name name in
        match actual with
        | Some a -> (
            match (if m = "len" then list_len a else None) with
            | Some n -> Some (Smt.IntLit n)
            | None -> (
                match a with
                (* The actual is a bare name.  Load whatever the CALLER's own
                   signature promises about its measures first, so the promise
                   and the goal meet on the one memoized `m$x` symbol. *)
                | A.EVar { A.txt = x; _ } ->
                  load_scope_measure_facts x;
                  measure_of_var m x
                (* A non-variable, non-literal actual (a call, a field…): no
                   symbol to share with the caller's facts.  For the binder
                   spellings keep the fresh non-negative constant — it is what
                   the two spellings resolved to before, and it stays SAT, so
                   the outcome is silence either way. *)
                | _ when is_self name -> measure_of_var m self_dt_sym
                | _ -> None))
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
               reflect_scalar ~postcond ~sort:(caller_scalar_of name) sc
                 (A.EVar { A.txt = name; A.span })))
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
      (* `len` over a name ALREADY declared into the `Str` sort is the string
         length, i.e. the same `($strlen name)` the predicate side produces —
         and the caller's `name` is the very constant it produced it over (the
         binder is pre-reflected just above, before path translation, exactly so
         that this holds).  Without this the two sides split: the predicate says
         `($strlen t)` while the guard said `len$t`, an unrelated Int constant,
         and no string guard could ever discharge a string obligation.
         [path_resolve_var] applies the identical `str_names` rule to plain
         occurrences, so this keeps measure and variable positions at one sort.

         Unreachable from source until the byte-length aliases existed — March
         has no callable `len`, so a guard could not mention this measure. *)
      else if m = "len" && string_len_available () && Hashtbl.mem str_names name then
        Some (Smt.App (strlen_fn, [ Smt.Const name ]))
      else measure_of_var m name
    in
    let path_resolve_tester ctor arg =
      (* A tag test on a LIST is a statement about its length, and saying it that
         way is what connects a `match` arm to a `len` contract:

           match xs do Nil -> Err(…) | _ -> Ok(mean(xs)) end

         The `_` arm carries `not is_Nil(xs)` (pushed by the arm-order exclusion
         in [visit]), and `mean`'s precondition is about `len(xs)`.  Routed
         through the datatype encoding below those are two unrelated facts — a
         tester over an opaque datatype constant, and an integer — so the arm
         proved nothing and every safe-wrapper in the stdlib carried permanent
         unprovable debt.  Translating the tester onto the SAME memoized `len$x`
         symbol the goal uses closes the gap with no datatype declaration and no
         quantified axiom:

           is_Nil(xs)   <->  len(xs) = 0
           is_Cons(xs)  <->  len(xs) > 0

         Both are exact for lists, and `len >= 0` is already asserted by
         [measure_of_var], so `not (len$xs = 0)` gives z3 `len$xs > 0` directly.

         Gated on the constructor belonging to the BUILT-IN List sort: a user
         ADT is free to have its own `Nil`, and a `len` claim about that would be
         invented rather than derived. *)
      let list_sort = adt_sort_name "List" in
      match arg, sort_of_ctor ctor with
      | A.EVar { A.txt = x; _ }, Some adt
        when adt = list_sort && (ctor = "Nil" || ctor = "Cons") ->
        (match measure_of_var "len" x with
         | Some len_x ->
           Some
             (if ctor = "Nil" then Smt.Eq (len_x, Smt.IntLit 0)
              else Smt.Gt (len_x, Smt.IntLit 0))
         | None -> None)
      | _ ->
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
     | None ->
       (* Two different causes reach this arm and they must not be conflated:
          `Skip` means the SUBJECT (a record actual) did not reflect, while the
          other modes mean the PREDICATE itself did not.  The distinction was
          cosmetic while it only fed a debug count; `cap verified` puts the
          reason in front of a user, and telling someone their perfectly
          reflectable predicate is unreflectable sends them after the wrong
          thing. *)
       note
         (Obligation.Skipped
            (match mode with
             | `Skip -> Obligation.Unreflectable_subject
             | `Other | `Record _ -> Obligation.Unreflectable_predicate))
     | Some goal when not (wellsorted (Hashtbl.mem str_names) goal) ->
       note (Obligation.Skipped Obligation.Sort_conflict)
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
       if sort_conflict decls then note (Obligation.Skipped Obligation.Sort_conflict)
       else
       (* Drop ill-sorted assumptions.  Weakening the hypothesis set can only
          make BOTH discharges harder, so this can only turn a report into a
          skip — never the reverse. *)
       let assumptions = List.filter (wellsorted (Hashtbl.mem str_names)) !assume in
       (* Now the declarations are final, so which symbols are floats is known:
          rewrite every ordinary comparison over two floats into its IEEE form,
          then drop anything that still mixes a float with an Int. *)
       let sort_of n = List.assoc_opt n decls in
       let is_float n = sort_of n = Some Smt.SFloat in
       let goal = fp_rewrite is_float goal in
       if not (float_wellsorted is_float goal && formula_wellsorted sort_of goal) then
         note (Obligation.Skipped Obligation.Float_sort_gate)
       else
       let assumptions =
         List.filter_map
           (fun a ->
             let a = fp_rewrite is_float a in
             if float_wellsorted is_float a && formula_wellsorted sort_of a then Some a
             else None)
           assumptions
       in
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
        | Refine.Verified -> note Obligation.Proved
        | first ->
          (match Refine.discharge ~root ~preamble { vc with Smt.goal = Smt.Not goal } with
           | Refine.Verified ->
             note Obligation.Violated;
             (* Name the parameter and callee rather than saying "argument".
                On a call with several arguments, "argument does not satisfy
                `_ != 0`" leaves the reader to work out WHICH one, and the
                predicate's binder is usually the anonymous `_`, so the message
                alone does not identify it. *)
             let param_label =
               match subject, List.nth_opt sg.param_names rp.idx with
               | Argument, Some pname when pname <> "" ->
                 Printf.sprintf "argument `%s` of `%s`" pname callee
               | Argument, _ -> Printf.sprintf "argument %d of `%s`" (rp.idx + 1) callee
               | Bound_expr, _ -> subject_noun
             in
             (* Point at the offending argument itself. The call span covers the
                whole expression, which on a multi-argument call underlines
                everything and singles out nothing. *)
             let labels =
               match subject, List.nth_opt args rp.idx with
               | Argument, Some a ->
                 let sp = arg_span span a in
                 if sp = span then []
                 else
                   [{ Err.lbl_span = sp;
                      Err.lbl_message =
                        Printf.sprintf "this argument must satisfy `%s`"
                          (pred_str rp.pred) }]
               | _ -> []
             in
             Err.report errctx
               { Err.severity = Err.Error; span;
                 message = Printf.sprintf
                   "refinement violation: %s does not satisfy %s `%s`%s\n%s"
                   param_label obligation_noun (pred_str rp.pred)
                   (format_cx (model_of first))
                   (match subject with
                    | Argument ->
                      Printf.sprintf
                        "note: guard the call (e.g. `if %s do …`) or pass a value known to \
                         satisfy it"
                        (pred_str rp.pred)
                    | Bound_expr ->
                      "note: a refined annotation on a `let` is CHECKED against the \
                       expression it annotates, not assumed — bind a value that satisfies \
                       it, or weaken the annotation");
                 labels; notes = []; code = None; fix = None }
           | _ -> note (Obligation.Skipped Obligation.Solver_undecided))))

(* =================================================================
   §16 Postcondition checking
   ================================================================= *)

(* ── Postconditions: a function's return value must satisfy its return
   refinement.  We check each *tail* expression (a return position) under the
   path/scope reaching it, with the same definite-failure soundness stance. ── *)

(* The return refinements [check_post] can discharge DIRECTLY: an Int return, or
   a record return (whose SMT sort name is reported so [check_post] can reflect
   `_.field`).  A variant-ADT return is deliberately absent — it is proven, when
   it can be, by [check_post_induction] instead. *)
let return_refine_ext (fd : A.fn_def) : (string * A.expr * string option) option =
  match fd.A.fn_ret_ty with
  | Some (A.TyRefine (base, binder, pred)) when is_int_base base ->
    Some (binder_name binder, pred, None)
  | Some (A.TyRefine (base, binder, pred)) when is_bool_base base ->
    Some (binder_name binder, pred, Some bool_sort)
  | Some (A.TyRefine (base, binder, pred)) when is_float_base base ->
    Some (binder_name binder, pred, Some float_sort)
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
      (* Every SCALAR entry — the original Int (`None`) and now Bool — declares
         one constant at its own sort and loads its predicate over it.  The sort
         must come from the marker, not be assumed `Int`: a Bool constant used
         where the VC says `Int` is exactly the one-symbol-two-sorts rejection
         the string and record paths already guard against. *)
      | _ when scalar_sort_of_marker sort <> None ->
        let s = scalar_sort_or_int sort in
        let c = Smt.Const name in
        let rv n = if n = b || n = "_" then Some c else Some (Smt.Const n) in
        let ds = (name, s) :: ds in
        (match smt_of ~resolve_var:rv ~resolve_measure:(fun _ _ -> None) q with
         | Some qa -> (ds, qa :: asm, has_rec)
         | None -> (ds, asm, has_rec))
      | None -> (ds, asm, has_rec)
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
      (* A MEASURE-ONLY entry ([meas_sort_prefix]) contributes NOTHING here, and
         must not fall into the ADT arm below: `$Meas:M_List` is a marker, not a
         declared sort, so `(declare-const xs $Meas:M_List)` would be a z3
         `(error …)` on the shared solver channel — and setting [has_rec] off a
         list predicate would switch [check_post] onto its "a SAT model is a
         definite violation" branch with nothing concrete pinned, which is a
         false-positive engine.  Skipping leaves [check_post] behaving exactly as
         it did before these entries existed; carrying a list measure through a
         POSTcondition is a separate piece of work. *)
      | Some sort_name when is_meas_sort sort_name -> (ds, asm, has_rec)
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
(* [scalar_env] gives the SCALAR SMT sort of body names whose declared type
   fixes one — the clause's `Bool` parameters.  [sc] only carries REFINED
   locals, so without this a bare `fn f(b : Bool) : {Bool | _ == true} do b end`
   would declare `b` at `Int` and use it as a Bool. *)
let check_post ~root errctx ~span ?(record_sort : string option = None)
    ?(scalar_env : (string * Smt.sort) list = [])
    ?(fn_name : string option = None) ?(emit = true) ?(record = true)
    (sc : scope) (binder : string) (ret_pred : A.expr)
    ((path, tail_e) : (A.expr * bool) list * A.expr) : bool =
  (* Mirrors [check_call]'s [note]: every exit records an outcome, so a return
     refinement that checks nothing is distinguishable from one that passes.
     [record] (NOT [emit]) gates whether this fires at all — [check_fn_post_verdict]
     is invoked twice per refined-return function, once from the
     [gate_unverified_posts] pre-pass with [~emit:false] and once from the walk
     with [emit = true]; both calls are threaded here as [~record:emit] by the
     caller, so only the emitting (reporting) run ever records, and the same
     postcondition is never counted twice. *)
  let note verdict =
    (* `@[trusted]` accepts a SKIP as an assertion rather than escalating it —
       mirrors [check_call]'s [note] exactly, including running before the
       verdict is recorded/escalated, so the ledger and the diagnostic agree.
       A [Violated] is untouched: a predicate the solver proved can never hold
       is a bug in the annotation, not an incompleteness [@[trusted]] waves
       through. *)
    let verdict =
      match verdict with
      | Obligation.Skipped _ when !trusted_fn -> Obligation.Trusted
      | _ -> verdict
    in
    if record then
      Obligation.record
        { Obligation.span; callee = Option.value ~default:"" fn_name
        ; predicate = pred_str ret_pred; verdict; kind = Obligation.Postcondition };
    (* `cap verified` escalates an undischarged POSTCONDITION exactly as
       [check_call] escalates an undischarged precondition — the last place a
       fact was granted without obliging anyone.  Gated on [record] (which
       [check_fn_post_verdict] threads as [~record:emit]) so only the emitting
       run escalates: the [gate_unverified_posts] pre-pass calls this with
       [~record:false] purely to decide propagation, and must never also
       report — that would print the same contract's failure twice. *)
    match verdict with
    | Obligation.Skipped r when !strict_verified && record ->
      let fn_label = match fn_name with Some n -> n | None -> "<anonymous>" in
      let remedy =
        "note: strengthen the return expression so the checker can see it \
         satisfies this contract, rewrite the predicate into the fragment the \
         checker supports, or remove `cap verified` from this module — it asks \
         for every obligation to be discharged"
      in
      Err.error errctx ~span
        (Printf.sprintf
           "`cap verified` module: cannot verify return type constraint `%s` on `%s` (%s: %s)\n%s"
           (pred_str ret_pred) fn_label (Obligation.reason_name r)
           (Obligation.reason_detail r) remedy)
    | _ -> ()
  in
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
  (* The sort a body name is declared at: the refined-local scope decides first
     (it has already declared the name in [scope_facts]), then the declared-type
     environment, then the historical default of `Int`. *)
  let scalar_of name =
    match List.assoc_opt name sc with
    | Some (_, _, m) when scalar_sort_of_marker m <> None -> scalar_sort_or_int m
    | Some _ -> Smt.SInt
    | None -> (match List.assoc_opt name scalar_env with Some s -> s | None -> Smt.SInt)
  in
  let var_const name =
    if is_str_scope name then Some (Smt.Const name)
    else begin decls := (name, scalar_of name) :: !decls; Some (Smt.Const name) end
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
        (* `Str` is opaque — it has no fields and no selectors; nor is a
           scalar (`$Bool`) a declared record sort. *)
        | None -> rf
        | Some s when s = str_sort || is_scalar_sort s -> rf
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
  | None -> note (Obligation.Skipped Obligation.Unreflectable_predicate); false
  | Some tail_term ->
    let resolve_field = match record_sort with
      | Some sort_name -> make_field_resolver binder sort_name tail_term
      | None -> fun _ _ -> None
    in
    let resolve_var name = if name = binder || name = "_" then Some tail_term else var_const name in
    (* ── Body-namespace resolvers, for the PATH CONTEXT only ────────────────
       A path condition was collected from the function BODY, so every name in
       it is a body name — a parameter or a local — and denotes itself.  The
       return BINDER is not a body name at all: it exists only inside the
       refinement predicate, where it stands for the returned value.  Routing
       the path through [resolve_var] therefore re-points any body variable that
       happens to share the binder's spelling at the returned expression:

         fn f(v : Int, k : Int) : {v : Int | v > 0} do
           if v < 0 do k else 1 end     -- the guard is about the PARAMETER `v`

       read through the binder, `v < 0` becomes `k < 0`, which makes `v > 0`
       (i.e. `k > 0`) definitely false and reports correct code.  This is the
       same caller/callee conflation already fixed for [check_call]'s path
       conditions (see [path_resolve_var] there).

       `_` is left pointing at the return term: it is not a legal variable in
       body code, so it can only have come from a predicate, and mapping it
       through [var_const] would declare a constant named `_`. *)
    let path_resolve_var name = if name = "_" then Some tail_term else var_const name in
    (* Same split for field selectors: `old.count` in a guard projects from the
       SCOPE's record parameter, not from the returned record. *)
    let path_resolve_field varname fname =
      if varname = "_" then resolve_field varname fname
      else scope_field_resolver varname fname
    in
    List.iter
      (fun (cond, negated) ->
        match
          smt_of ~resolve_var:path_resolve_var ~resolve_measure
            ~resolve_field:path_resolve_field ~resolve_measure_app cond
        with
        | Some t -> assume := (if negated then Smt.Not t else t) :: !assume
        | None -> ())
      path;
    (match smt_of ~resolve_var ~resolve_measure ~resolve_field ~resolve_measure_app ret_pred with
     | None -> note (Obligation.Skipped Obligation.Unreflectable_predicate); false
     | Some goal ->
       let decls =
         List.fold_left (fun acc d -> if List.mem d acc then acc else d :: acc) [] !decls
       in
       if sort_conflict decls then (note (Obligation.Skipped Obligation.Sort_conflict); false)
       else
       (* See [check_call] for why the IEEE rewrite runs here, once the
          declarations — and hence which symbols are `Float64` — are final. *)
       let sort_of n = List.assoc_opt n decls in
       let is_float n = sort_of n = Some Smt.SFloat in
       let goal = fp_rewrite is_float goal in
       if not (float_wellsorted is_float goal && formula_wellsorted sort_of goal) then
         (note (Obligation.Skipped Obligation.Float_sort_gate); false)
       else
       let assumptions =
         List.filter_map
           (fun a ->
             let a = fp_rewrite is_float a in
             if float_wellsorted is_float a && formula_wellsorted sort_of a then Some a
             else None)
           !assume
       in
       let vc = { Smt.decls; assumptions; goal } in
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
        | Refine.Verified -> note Obligation.Proved; true
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
          (* Whether this IS a violation is independent of [emit] — [emit_error]
             merely gates whether we tell the user; [note] below must still
             record the true verdict either way. *)
          let violated =
            if scope_has_record then
              (* With concrete record preconditions in scope, a SAT counterexample
                 satisfying those preconditions IS a real violation — report it. *)
              (match first with Refine.Refuted _ -> emit_error (); true | _ -> false)
            else
              (match Refine.discharge ~root ~preamble { vc with Smt.goal = Smt.Not goal } with
               | Refine.Verified -> emit_error (); true
               | _ -> false)
          in
          (* Not [Verified] on the positive goal ⇒ not proven, whatever the
             refutation attempt said. *)
          if violated then note Obligation.Violated
          else note (Obligation.Skipped Obligation.Solver_undecided);
          false))

(* =================================================================
   §17 Postconditions by induction
   ================================================================= *)

(* ══ Tier 2: structural induction over a recursive function ═════════════════

   A RELATIONAL postcondition on a recursive function — `fn insert(t, x) :
   {Tree | size(_) == size(t) + 1}` — cannot be discharged by Z3 alone: Z3 does
   not do induction.  But full induction is not needed.  For a function that
   recurses structurally on one parameter it suffices to make the postcondition
   available as an ASSUMPTION at each recursive call whose argument is a proper
   component of the matched parameter — the induction hypothesis — and then
   discharge each arm separately against the measure's recursion equations:

     Leaf arm:        size(Node(Leaf,x,Leaf)) == size(Leaf) + 1
                      reduces via the axioms to 1 + 0 + 0 == 0 + 1.  No IH needed.
     Node(l,v,r) arm: size(Node(insert(l,x),v,r)) == size(t) + 1
                      needs size(insert(l,x)) == size(l) + 1 — the postcondition
                      instantiated at `l`, which IS structurally smaller.

   ── THE SOUNDNESS PROPERTY ────────────────────────────────────────────────
   The IH may be assumed ONLY at a recursive call whose recursion argument is
   structurally smaller than the matched parameter.  Assuming it at an arbitrary
   argument is circular — you would assume exactly what you are proving — and it
   fails in the DANGEROUS direction: a proven postcondition is ADDED to the
   assumption set that later call-site checks prove `¬goal` against, and adding
   assumptions makes a violation EASIER to prove.  An unsound IH therefore does
   not merely fail to help, it manufactures FALSE POSITIVES on correct code.
   [structural_subvars] is the gate, unchanged and unwidened — the same gate that
   makes `@[measure]` axiomatisation sound.

   The induction is on the matched parameter alone, so only the argument at THAT
   position must shrink; the IH is universally quantified over the others (an
   accumulator may grow freely).

   ── WHY THIS IS A SEPARATE PATH, AND WHY IT NEVER EMITS ────────────────────
   [check_post] handles Int and record returns.  A VARIANT-ADT return was
   previously inert: [return_refine_ext] returns None for it, so nothing at all
   happened.  This function occupies exactly that previously-inert case, so it
   cannot regress any existing verdict.  It is VERDICT-ONLY: it returns "proven"
   or "not proven" and never reports a diagnostic, so the definition side of a
   Tier 2 function stays silent no matter what the solver says.  Its observable
   effects are enabling PROPAGATION via [gate_unverified_posts] and — for the
   constructor-literal shape only — writing a [Postcondition] entry to the
   obligation ledger, so `--refine-report` can tell "attempted and proved" from
   "never looked at".  That write is gated on [~record], NOT on emission,
   because [check_fn_post_verdict] runs twice per refined-return function and
   the same postcondition must never be counted twice; this mirrors exactly
   what [check_post]'s own [record] parameter is for.

   Everything outside a narrow, recognised shape returns false (= not proven =
   skipped): several clauses, a clause guard, a catch-all arm, a nested pattern,
   a binder that shadows a parameter, a sort we cannot pin down.  Skipping costs
   completeness; guessing would cost correctness. *)

(* The SMT sort of a DECLARED March type; None when the checker has no model. *)
let rec smt_sort_of_ty (t : A.ty) : Smt.sort option =
  match t with
  | A.TyRefine (base, _, _) -> smt_sort_of_ty base
  | A.TyCon ({ A.txt = "Int"; _ }, []) -> Some Smt.SInt
  | A.TyCon ({ A.txt = "Bool"; _ }, []) -> Some Smt.SBool
  | A.TyCon ({ A.txt; _ }, _) when Hashtbl.mem adt_ctors (adt_sort_name txt) ->
    Some (Smt.SData (adt_sort_name txt))
  | _ -> None

let ctor_belongs (ctor : string) (adt : string) : bool =
  match Hashtbl.find_opt adt_ctors adt with Some cs -> List.mem ctor cs | None -> false

let check_post_induction ~root ?(record = true) (fd : A.fn_def) : bool =
  let self = fd.A.fn_name.A.txt in
  let dummy_span = fd.A.fn_name.A.span in
  let evar x = A.EVar { A.txt = x; A.span = dummy_span } in
  match fd.A.fn_ret_ty, fd.A.fn_clauses with
  | Some (A.TyRefine ((A.TyCon (rn, _) as rbase), bnd, pred)), [ c ]
    when is_adt_base rbase && (not (is_record_base rbase)) && c.A.fc_guard = None -> (
    let ret_adt = adt_sort_name rn.A.txt in
    let binder = binder_name bnd in
    let params = List.map param_name_of c.A.fc_params in
    let ps = match classify_pred binder params pred with
      | Unusable -> None
      | Closed -> Some []
      | Relational ps -> Some ps
    in
    (* Every sort this VC family mentions must already be declared by the
       measure preamble; otherwise the VC would reference an undeclared sort and
       z3 would answer with an `(error …)` line — the failure mode that
       desynchronises the shared solver channel.  (`--no-measure-axioms` empties
       the preamble, so this also disables Tier 2 under that flag.) *)
    match ps with
    | None -> false
    | Some _ when not (Hashtbl.mem measure_preamble_sorts ret_adt) -> false
    | Some ps ->
      (* ── The single VC builder, shared by every accepted body shape ────────
         [mctx] is the INDUCTION context — the matched parameter, its ADT sort,
         its index in the parameter list, and the structurally-smaller variables
         computed over the whole clause body.  It is the only thing that
         licenses an induction hypothesis, so a body with no top-level match
         passes [None] and can therefore never assume one.  [pat] is the pattern
         equation for the arm under check (its constructor and flat binders); it
         is meaningful only alongside an [mctx], since the equation's left-hand
         side IS the matched parameter.

         There is deliberately ONE generator: a second, parallel VC builder for
         the non-match shape could drift from this one, the hazard recorded at
         [postcond_infer.ml:25]. *)
      let check_tail
          ~(mctx : (string * string * int * (string, unit) Hashtbl.t) option)
          ~(pat : (string * (string * Smt.sort) list) option) ~(refute : bool)
          ((path, tail_e) : (A.expr * bool) list * A.expr) : Obligation.verdict option =
            (* ── Per-VC state ───────────────────────────────────────────────
               [declare] is the well-sortedness guard: one symbol at two sorts
               makes z3 emit an `(error …)`, which desynchronises the shared
               `z3 -in` channel and silently disables refinement checking for the
               rest of the compilation.  Any conflict abandons the whole VC. *)
            let decls : (string, Smt.sort) Hashtbl.t = Hashtbl.create 16 in
            let conflict = ref false in
            let declare n s =
              match Hashtbl.find_opt decls n with
              | None -> Hashtbl.replace decls n s; true
              | Some s' -> if s' = s then true else (conflict := true; false)
            in
            let assume = ref [] in
            let ctr = ref 0 in
            let fresh s =
              incr ctr;
              let n = Printf.sprintf "$t2f%d" !ctr in
              Hashtbl.replace decls n s;
              Smt.Const n
            in
            let ok = ref true in
            (match mctx with
             | Some (mparam, madt, _, _) ->
               if not (declare mparam (Smt.SData madt)) then ok := false
             | None -> ());
            (match pat with
             | Some (_, binder_sorts) ->
               List.iter
                 (fun (n, s) -> if not (declare n s) then ok := false)
                 binder_sorts
             | None -> ());
            List.iter
              (fun fp ->
                match Option.bind (param_ty_of fp) smt_sort_of_ty with
                | Some s -> if not (declare (param_name_of fp) s) then ok := false
                | None -> ())
              c.A.fc_params;
            (* ── Reflection, always at a KNOWN expected sort ─────────────── *)
            let rec reflect_at (s : Smt.sort) (e : A.expr) : Smt.term option =
              match s with
              | Smt.SData d when d <> "Elem" -> reflect_dt d e
              | Smt.SInt -> reflect_int e
              (* An `Elem` or Bool field is invisible to a structural measure:
                 an unconstrained constant of the right sort keeps the VC
                 well-sorted and asserts nothing. *)
              | _ -> Some (fresh s)
            and reflect_dt (d : string) (e : A.expr) : Smt.term option =
              match e with
              | A.EVar { A.txt = x; _ } ->
                if declare x (Smt.SData d) then Some (Smt.Const x) else None
              | A.ECon (ct, args, _) when ctor_belongs ct.A.txt d ->
                let fs = try Hashtbl.find ctor_field_sorts ct.A.txt with Not_found -> [] in
                if List.length fs <> List.length args then None
                else
                  List.fold_right2
                    (fun a s acc ->
                      match reflect_at s a, acc with
                      | Some t, Some ts -> Some (t :: ts)
                      | _ -> None)
                    args fs (Some [])
                  |> Option.map (fun ts -> Smt.App (ct.A.txt, ts))
              (* ── THE INDUCTION HYPOTHESIS ─────────────────────────────────
                 A self-recursive call returning this datatype.  It becomes a
                 fresh opaque constant; the postcondition is assumed ABOUT that
                 constant if and only if the argument at the MATCHED parameter's
                 position is a variable in [structural_subvars].  Any other
                 recursive call still reflects (so the arm can be attempted) but
                 carries NO assumption — an unconstrained constant proves
                 nothing, which is exactly the skip we want.  With no [mctx]
                 there is no matched parameter and hence nothing that could be
                 structurally smaller, so no IH is ever available. *)
              | A.EApp (A.EVar { A.txt = f; _ }, args, _) when f = self && d = ret_adt ->
                incr ctr;
                let nm = Printf.sprintf "$t2rec%d" !ctr in
                Hashtbl.replace decls nm (Smt.SData ret_adt);
                let cst = Smt.Const nm in
                let ih_arg =
                  match mctx with
                  | None -> None
                  | Some (_, _, mparam_idx, sset) -> (
                    match List.nth_opt args mparam_idx with
                    | Some (A.EVar v) when Hashtbl.mem sset v.A.txt -> Some v
                    | _ -> None)
                in
                (match ih_arg with
                 | Some _ ->
                   let env =
                     List.mapi (fun i n -> (n, List.nth_opt args i)) params
                     |> List.filter_map (function
                          | "_", _ | _, None -> None
                          | n, Some a -> Some (n, a))
                   in
                   if List.for_all (fun p -> List.mem_assoc p env) ps then
                     (match pred_term cst (subst_params env pred) with
                      | Some t -> assume := t :: !assume
                      | None -> ())
                 | None -> ());
                Some cst
              | _ -> None
            and reflect_int (e : A.expr) : Smt.term option =
              smt_of ~resolve_var:rv_int ~resolve_measure:rm ~resolve_measure_app:rma e
            and rv_int (x : string) : Smt.term option =
              if declare x Smt.SInt then Some (Smt.Const x) else None
            and rm (m : string) (x : string) : Smt.term option =
              if not (is_axiom_measure m) then None
              else
                let a = Hashtbl.find axiom_measures m in
                Option.map (fun t -> Smt.App (m, [ t ])) (reflect_dt a (evar x))
            and rma (m : string) (arg : Smt.term) : Smt.term option =
              if not (is_axiom_measure m) then None
              else
                match concrete_measure_app m arg with
                | Some n -> Some (Smt.IntLit n)
                | None -> Some (Smt.App (m, [ arg ]))
            (* Reflect the return PREDICATE with its binder standing for [bt].
               The binder is ADT-valued, so it can appear only under a measure
               (`size(_)`) or as a bare occurrence; both route to [bt]. *)
            and pred_term (bt : Smt.term) (p : A.expr) : Smt.term option =
              let rv x = if x = binder || x = "_" then Some bt else rv_int x in
              let rm' m x =
                if not (is_axiom_measure m) then None
                else if x = binder || x = "_" then Some (Smt.App (m, [ bt ]))
                else rm m x
              in
              smt_of ~resolve_var:rv ~resolve_measure:rm' ~resolve_measure_app:rma p
            in
            (* The pattern equation.  Without it a match arm knows nothing about
               the scrutinee, and even the BASE case (`size(t) + 1` with `t =
               Leaf`) is unprovable.  A body with no match has no scrutinee to
               constrain — the parameters stay universally quantified, which is
               strictly WEAKER than any equation, so omitting it cannot make a
               goal provable that would otherwise fail. *)
            (match pat, mctx with
             | None, _ -> ()
             | Some (ctor, binder_sorts), Some (mparam, _, _, _) ->
               let pat_eq =
                 List.fold_right
                   (fun (n, _) acc -> Option.map (fun ts -> Smt.Const n :: ts) acc)
                   binder_sorts (Some [])
                 |> Option.map (fun ts -> Smt.Eq (Smt.Const mparam, Smt.App (ctor, ts)))
               in
               (match pat_eq with Some t -> assume := t :: !assume | None -> ok := false)
             (* A pattern with no matched parameter is not a shape we build. *)
             | Some _, None -> ok := false);
            (* Reflecting the tail is what mints the IH assumptions, so it must
               happen before the assumption list is read. *)
            let tail_term = reflect_dt ret_adt tail_e in
            List.iter
              (fun (cond, negated) ->
                match reflect_int cond with
                | Some t -> assume := (if negated then Smt.Not t else t) :: !assume
                | None -> ())
              path;
            match tail_term with
            | None -> None
            | Some tt -> (
              match pred_term tt pred with
              | None -> None
              | Some goal ->
                if (not !ok) || !conflict then None
                else
                  let decls =
                    Hashtbl.fold (fun n s acc -> (n, s) :: acc) decls []
                    |> List.sort compare
                  in
                  let vc = { Smt.decls; assumptions = !assume; goal } in
                  match Refine.discharge ~root ~preamble:!measure_preamble vc with
                  | Refine.Verified -> Some Obligation.Proved
                  | _ when not refute -> Some (Obligation.Skipped Obligation.Solver_undecided)
                  (* DEFINITE failure only: "not proved" is not "violated".  The
                     predicate is reported as violated only when its NEGATION is
                     itself Verified — i.e. it can never hold. *)
                  | _ ->
                    if Refine.discharge ~root ~preamble:!measure_preamble
                         { vc with Smt.goal = Smt.Not goal }
                       = Refine.Verified
                    then Some Obligation.Violated
                    else Some (Obligation.Skipped Obligation.Solver_undecided))
      in
      let proved_tail ~mctx ~pat t =
        check_tail ~mctx ~pat ~refute:false t = Some Obligation.Proved
      in
      (match c.A.fc_body with
      (* ── Shape 1: a constructor-literal body ───────────────────────────────
         The simplest possible case, and one that needs no induction at all:
         there is no recursive call to hypothesise over, so the goal is just the
         predicate with its binder replaced by the constructed term, discharged
         under the measure's own recursion axioms.  This shape used to fall
         through to `false` SILENTLY — Tier 2 is verdict-only — so a
         deliberately wrong postcondition on it reported no obligation of any
         kind.  Checked BEFORE the match shape so the path that already worked
         is reached unchanged. *)
      | A.ECon _ as body ->
        (* Unlike the match shape, this one RECORDS its verdict in the
           obligation ledger.  Tier 2 stays verdict-only in the sense that
           matters — it emits no diagnostic either way — but "attempted" has to
           be distinguishable from "never looked at", and the ledger is the only
           channel that carries that.  Gated on [record] (which the caller
           threads from [emit]) so the pre-pass run does not double-count.
           (Extending the same accounting to the match shape is a separate
           change: it would move counts under every existing Tier 2 fixture, so
           it is deliberately not bundled here.) *)
        let v =
          (* The refutation query exists only to classify a LEDGER verdict, so
             it is pointless on the non-recording pass — and skipping it there
             cannot change the boolean result, since [Violated] and
             [Skipped Solver_undecided] are both "not proven". *)
          match check_tail ~mctx:None ~pat:None ~refute:record ([], body) with
          | Some v -> v
          (* No VC could be built at all — reflection failed somewhere. *)
          | None -> Obligation.Skipped Obligation.Unreflectable_predicate
        in
        if record then
          Obligation.record
            { Obligation.span = fd.A.fn_name.A.span
            ; callee = self
            ; predicate = pred_str pred
            ; verdict = v
            ; kind = Obligation.Postcondition };
        v = Obligation.Proved
      (* ── Shape 2: one clause whose whole body matches on a parameter ─────── *)
      | A.EMatch (A.EVar sv, branches, _) when List.mem sv.A.txt params -> (
        let mparam = sv.A.txt in
        let mparam_idx =
          let rec ix i = function
            | [] -> -1
            | x :: r -> if x = mparam then i else ix (i + 1) r
          in
          ix 0 params
        in
        let mparam_ty =
          List.find_opt (fun fp -> param_name_of fp = mparam) c.A.fc_params
          |> (fun o -> Option.bind o param_ty_of)
          |> (fun o -> Option.bind o smt_sort_of_ty)
        in
        match mparam_ty with
        | Some (Smt.SData madt) when madt <> "Elem" ->
          if not (Hashtbl.mem measure_preamble_sorts madt) then false
          else begin
            (* Structurally smaller variables, computed over the WHOLE clause
               body so a nested match contributes its components too. *)
            let sset = structural_subvars mparam c.A.fc_body in
            let mctx = Some (mparam, madt, mparam_idx, sset) in
            let check_branch (br : A.branch) : bool =
              match br.A.branch_pat with
              | A.PatCon (ct, subpats) when ctor_belongs ct.A.txt madt -> (
                let ctor = ct.A.txt in
                let fsorts = try Hashtbl.find ctor_field_sorts ctor with Not_found -> [] in
                if List.length subpats <> List.length fsorts then false
                else
                  (* Only flat PatVar / PatWild sub-patterns: a nested pattern
                     would need an equation we do not build. *)
                  let names =
                    List.mapi
                      (fun i p ->
                        match p with
                        | A.PatVar n -> Some n.A.txt
                        | A.PatWild _ -> Some (Printf.sprintf "$w%s%d" ctor i)
                        | _ -> None)
                      subpats
                  in
                  if List.exists Option.is_none names then false
                  else
                    let names = List.map Option.get names in
                    (* A binder that reuses a parameter's name would be
                       conflated with it (both reflect to `Const name`). *)
                    if List.exists (fun n -> List.mem n params) names then false
                    else
                      let binder_sorts = List.combine names fsorts in
                      let base_path =
                        match br.A.branch_guard with Some g -> [ (g, false) ] | None -> []
                      in
                      let ts = tails base_path br.A.branch_body in
                      (* Fold, not for_all: no short-circuit, so the VC cache is
                         warmed uniformly and the verdict is order-independent. *)
                      ts <> []
                      && List.fold_left
                           (fun acc t ->
                             proved_tail ~mctx ~pat:(Some (ctor, binder_sorts)) t && acc)
                           true ts)
              (* A catch-all arm binds no constructor, so there is no pattern
                 equation pinning the scrutinee — nothing to prove from. *)
              | _ -> false
            in
            branches <> []
            && List.fold_left (fun acc br -> check_branch br && acc) true branches
          end
        | _ -> false)
      | _ -> false))
  | _ -> false

(* =================================================================
   §18 Function-level postcondition entry points and gating
   ================================================================= *)

(* Check every return-position tail of every clause of [fd] against its declared
   return refinement.  Returns true iff ALL of them positively verified (a
   function with no clauses, or a clause with no reachable tail, counts as NOT
   verified — silence is not proof).  [emit] threads through to [check_post].

   A return refinement [check_post] cannot handle at all (a variant-ADT return)
   falls through to [check_post_induction], the Tier 2 path.  That path never
   emits, so this stays the single reporting site.  [emit] IS threaded to it as
   [~record], though: its constructor-literal shape writes an obligation, and
   this function runs twice per refined-return function, so without the thread
   every such postcondition would be counted twice in `--refine-report`. *)
let check_fn_post_verdict ~root errctx ?(emit = true) (fd : A.fn_def) : bool =
  match return_refine_ext fd with
  | None -> check_post_induction ~root ~record:emit fd
  | Some (binder, ret_pred, marker) ->
    (* [record_sort] must carry only a DECLARED sort name.  A scalar marker
       (`$Bool`) is not one: handing it here would send the return value down
       the record-literal reflection and the datatype preamble, for a sort
       nobody declares. *)
    let record_sort =
      match marker with Some s when not (is_scalar_sort s) -> Some s | _ -> None
    in
    let clause_ok (c : A.fn_clause) =
      let sc = List.fold_left scope_add_fnparam [] c.A.fc_params in
      let scalar_env =
        List.map (fun fp -> (param_name_of fp, scalar_sort_of_param_ty (param_ty_of fp)))
          c.A.fc_params
      in
      let base = match c.A.fc_guard with Some g -> [ (g, false) ] | None -> [] in
      let ts = tails base c.A.fc_body in
      (* Fold (not List.for_all): every tail must be checked so every
         diagnostic is emitted — short-circuiting would hide errors. *)
      ts <> []
      && List.fold_left
           (fun acc t ->
             check_post ~root errctx ~span:c.A.fc_span ~record_sort ~scalar_env
               ~fn_name:(Some fd.A.fn_name.A.txt) ~emit ~record:emit sc binder ret_pred t
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

(* =================================================================
   §19 The visit traversal
   ================================================================= *)

(* ── An annotated `let`'s refinement is an OBLIGATION, not a promise ───────

   `let ys : {List(Int) | len(_) > 0} = []` used to be believed on sight:
   [scope_add_binding]'s annotated arm admits the predicate into [scope]
   unconditionally, so the annotation became a fact about `ys` and every later
   goal that needed it was PROVED off an expression that plainly violates it.
   Under `cap verified` — whose premise is "if it compiles, it is proved" —
   that is an unsound hole reachable by ordinary, non-adversarial code: an
   author writes an annotation to document an invariant and instead silently
   manufactures it.

   The check is not new machinery.  "Does this expression satisfy this
   predicate" is exactly what [check_call] answers for a call's actual, so the
   binding is reflected AS a one-parameter call: the annotation is the
   precondition, the bound expression is the sole argument.  That inherits the
   definite-failure stance (report only on a positive proof of ¬goal;
   unreflectable or solver-unsure stays a [Skipped]) and every resolver
   [check_call] already has, including the measure and constructor-tag paths
   added for contract composition.

   Two details that are easy to get wrong and are load-bearing:

   - [param_names] carries the LET NAME, not the refinement's binder.
     [check_call] resolves the refined value through [actual_of_name], which
     looks a name up in [param_names]; the binder travels separately in
     [rparam.binder].  All three spellings of the value must land on the same
     actual — `_`, a declared binder (`{v : T | p(v)}`), and the bound name
     itself (`len(ys)`) — and only this arrangement gets the third one.  (This
     is the difference from [callback_sig_of_ty], whose `$cb_arg` placeholder
     is safe precisely because a callback's domain has no name a predicate
     could spell.)

   - The binding's own name is SHADOWED out of all three fact channels first.
     The predicate's `ys` denotes the value being bound here, never an outer
     `ys`; leaving a stale entry visible would let an outer value's fact be
     attributed to this binder, which is the false-positive direction this
     subsystem must never take.  Retiring a fact can only cost precision (a
     skip), never soundness.

   Returns [Some true] when the annotation was PROVED, [Some false] when it was
   violated or left undecided, and [None] when the binding carries no refined
   annotation at all (so the caller falls through to [scope_add_binding]'s
   ordinary postcondition-derived handling).

   The caller uses that verdict to decide whether the predicate may enter
   [scope].  Admitting it on anything but a proof would re-open the hole in a
   quieter form: a `let ys : {List(Int) | len(_) > 0} = zs` the checker cannot
   decide would file a Skipped obligation and then STILL hand `len(ys) > 0` to
   every later goal, so `inner(ys)` would report `Proved` on the strength of a
   premise nobody established.  A proof that rests on an unverified assumption
   is exactly what this change exists to remove, so an unproven annotation
   grants nothing.  That costs precision — an invariant the author knows but
   the checker cannot see is no longer usable — and the cost lands entirely in
   the safe direction, as more skips. *)
let check_let_annotation ~root errctx defs (ctx : rctx) (path : (A.expr * bool) list)
    (lets : launder) (sc : scope) (re : recenv) (b : A.binding) : bool option =
  match b.A.bind_pat, refined_scope_ty b.A.bind_ty with
  | A.PatVar n, Some (binder, pred, sort) ->
    let name = n.A.txt in
    let names = pat_binders b.A.bind_pat in
    let sg =
      { param_names = [ name ]
      ; param_str = [ sort = Some str_sort ]
      ; param_scalar = [ scalar_sort_or_int sort ]
      ; refined = [ { idx = 0; binder; pred; sort } ]
      ; ret = None
      ; ret_sort = None
      }
    in
    let out = ref None in
    (* Every fact channel is shadowed by the names this binding introduces —
       see [call_ctx]'s note: all of them, or none. *)
    let cx =
      { root
      ; errctx
      ; postcond = postcond_of ctx defs
      ; path = path_shadow path names
      ; lets = launder_shadow lets names
      ; sc = scope_shadow sc names
      ; re = recenv_shadow re names
      }
    in
    check_call cx ~span:n.A.span
      ~callee:(Printf.sprintf "let %s" name)
      ~subject:Bound_expr ~verdict_out:out sg
      [ b.A.bind_expr ]
      { idx = 0; binder; pred; sort };
    Some (!out = Some Obligation.Proved)
  | _ -> None

(* ── Walk expressions, threading the refined-local scope, the record-typed
   variables ([recenv]) and the path context ─────────────────────────────── *)
let rec visit ~root errctx defs (ctx : rctx) (path : (A.expr * bool) list)
    (lets : launder) (sc : scope) (re : recenv) (cb : cbenv) (e : A.expr) : unit =
  let go = visit ~root errctx defs ctx path lets sc re cb in
  let go_path p = visit ~root errctx defs ctx p lets sc re cb in
  match e with
  | A.EApp (A.EVar { A.txt = fname; _ }, args, sp) ->
    (match resolve_call ctx defs fname with
     | Some (Some sg) ->
       let cx = { root; errctx; postcond = postcond_of ctx defs; path; lets; sc; re } in
       List.iter (fun rp -> check_call cx ~span:sp ~callee:fname sg args rp) sg.refined
     | _ ->
       (* Not a resolvable NAMED callee: fall back to the callee env — a call
          made through a refined function-typed parameter, or through a local
          alias of a named function (see [cbenv]). *)
       (match List.assoc_opt fname cb with
        | Some sg ->
          let cx = { root; errctx; postcond = postcond_of ctx defs; path; lets; sc; re } in
          List.iter (fun rp -> check_call cx ~span:sp ~callee:fname sg args rp) sg.refined
        | None -> ()));
    List.iter go args
  | A.EApp (f, args, _) -> go f; List.iter go args
  | A.ECon (_, args, _) | A.EAtom (_, args, _) | A.ETuple (args, _) -> List.iter go args
  | A.EBlock (es, _) ->
    (* Thread the path context, the refined-local scope AND the callee env
       left-to-right: a `let` extends the scope (and, for a bare-alias RHS,
       the callee env); an `assert(p)` (used as an `assume`) extends the path
       so a later call can rely on p.

       A block-level `fn f(...) do ... end` (ELetFn) is itself a SIBLING
       block statement, not nested inside — [visit]'s dedicated [A.ELetFn]
       case only descends into that local function's OWN body, so its bound
       name must ALSO be retired here for the statements that follow it in
       this block.  It carries no [scope]/[recenv] fact of its own (those
       channels track Int/String/ADT VALUES, and a function name is never
       one), but it always shadows [cbenv]: a same-named outer refined
       callback parameter must not keep being checked against calls to this
       new, unrelated local function. *)
    ignore
      (List.fold_left
         (fun (ctx, path, lets, sc, re, cb) e ->
           visit ~root errctx defs ctx path lets sc re cb e;
           (* An annotated `let`'s refinement is checked against its bound
              expression HERE, against the scope as it stands BEFORE the
              binding — exactly as a call's arguments are checked against the
              caller's pre-call scope.  Doing it after [scope_add_binding]
              would let the annotation discharge itself. *)
           let annot_proved =
             match e with
             | A.ELet (b, _) -> check_let_annotation ~root errctx defs ctx path lets sc re b
             | _ -> None
           in
           (* A `let`/local-`fn` binder also retires the name for CALLEE
              RESOLUTION in the statements that follow — see [local_shadow]. *)
           let ctx' =
             match e with
             | A.ELet (b, _) -> local_shadow ctx (pat_binders b.A.bind_pat)
             | A.ELetFn (n, _, _, _, _) -> local_shadow ctx [ n.A.txt ]
             | _ -> ctx
           in
           let path' =
             match e with
             | A.EAssert (p, _) -> (p, false) :: path
             (* A `let` REBINDS its names: retire any fact about them. *)
             | A.ELet (b, _) -> path_shadow path (pat_binders b.A.bind_pat)
             | A.ELetFn (n, _, _, _, _) -> path_shadow path [ n.A.txt ]
             | _ -> path
           in
           (* The laundering channel: retire first (both the key and any entry
              whose RHS mentions a rebound name — see [launder]), then record a
              single-name binding whose RHS is a direct application, so a later
              guard on that name can be traced back to the call it launders.
              Any [A.EApp] qualifies — [alias_withdrawal_cause] re-checks the
              recorded RHS against the withdrawn spelling and the obligation's
              own subject, so recording a non-measure application costs nothing
              but the entry. *)
           let lets' =
             match e with
             | A.ELet (b, _) ->
               let names = pat_binders b.A.bind_pat in
               let lets = launder_shadow lets names in
               (match b.A.bind_pat, b.A.bind_expr with
                | A.PatVar n, (A.EApp _ as rhs) -> (n.A.txt, rhs) :: lets
                (* A `let n = a` where `a` is ITSELF a laundered name copies the
                   underlying application forward under the new name, so the chain
                   extends to any depth without extra lookup machinery at use time.
                   `lets` is most-recent-first and already shadow-disciplined by
                   [launder_shadow] above, so `List.assoc_opt` finds the live entry. *)
                | A.PatVar n, A.EVar { A.txt = y; _ } ->
                  (match List.assoc_opt y lets with
                   | Some rhs -> (n.A.txt, rhs) :: lets
                   | None -> lets)
                | _ -> lets)
             | A.ELetFn (n, _, _, _, _) -> launder_shadow lets [ n.A.txt ]
             | _ -> lets
           in
           let sc' =
             match e with
             (* An annotation that was NOT proved grants no fact — it is
                retired rather than admitted, so no later goal can be
                discharged by a premise this binding failed to establish. *)
             | A.ELet (b, _) when annot_proved = Some false ->
               scope_shadow sc (pat_binders b.A.bind_pat)
             | A.ELet (b, _) -> scope_add_binding ~postcond:(postcond_of ctx defs) sc b
             | _ -> sc
           in
           let re' = match e with A.ELet (b, _) -> recenv_add_binding re b | _ -> re in
           let cb' =
             match e with
             | A.ELet (b, _) -> cb_add_binding ctx defs cb b
             | A.ELetFn (n, _, _, _, _) -> cb_shadow cb [ n.A.txt ]
             | _ -> cb
           in
           (ctx', path', lets', sc', re', cb'))
         (ctx, path, lets, sc, re, cb) es)
  | A.ELet (b, _) -> go b.A.bind_expr
  | A.ELam (ps, body, _) ->
    let names = List.map (fun (p : A.param) -> p.A.param_name.A.txt) ps in
    let ctx = local_shadow ctx names in
    visit ~root errctx defs ctx (path_shadow path names) (launder_shadow lets names)
      (List.fold_left scope_add_param sc ps)
      (List.fold_left recenv_add_param re ps)
      (List.fold_left cb_add_param cb ps)
      body
  | A.ELetFn (n, ps, _, body, _) ->
    let names = n.A.txt :: List.map (fun (p : A.param) -> p.A.param_name.A.txt) ps in
    let sc = scope_shadow sc [ n.A.txt ] in
    let re = recenv_shadow re [ n.A.txt ] in
    let cb = cb_shadow cb [ n.A.txt ] in
    let ctx = local_shadow ctx names in
    visit ~root errctx defs ctx (path_shadow path names) (launder_shadow lets names)
      (List.fold_left scope_add_param sc ps)
      (List.fold_left recenv_add_param re ps)
      (List.fold_left cb_add_param cb ps)
      body
  | A.EMatch (subj, branches, _) ->
    go subj;
    ignore
    @@ List.fold_left
      (fun (earlier : A.branch list) (br : A.branch) ->
        let binders = pat_binders br.A.branch_pat in
        (* A pattern binder shadows a same-named refined outer local. *)
        let sc = scope_shadow sc binders in
        (* …and a same-named fact in the path context, for the same reason. *)
        let path = path_shadow path binders in
        (* …and a same-named laundered-guard fact — see [launder]. *)
        let lets = launder_shadow lets binders in
        (* …and a same-named callback/alias fact — see [cbenv]. *)
        let cb = cb_shadow cb binders in
        (* …and a same-named GLOBAL FUNCTION, for callee resolution. *)
        let ctx = local_shadow ctx binders in
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
        (* A record DESTRUCTURED OUT OF AN ADT PAYLOAD — `match b do Wrap(c) ->
           …` where `Wrap` carries a record.  Such a binder is a record-typed
           variable exactly like a record-typed PARAMETER, and [recenv] is what
           lets a field guard (`if c.port <= 0 do …`) attach to it; without an
           entry the guard's `c.port` translated to nothing and every call
           taking `c` was skipped.  The plain-parameter spelling of the same
           code was checked, so the two disagreed.

           The positional field's SMT sort is already recorded by ADT
           registration, and [is_record_sort] distinguishes a record from a
           plain variant — only records have selectors to project.  Only a
           DIRECT `PatVar` sub-pattern is registered; a deeper nested pattern
           has no single name to attach the identity to and is left alone
           (silence).

           Retirement needs no new code: the entry is added AFTER
           [recenv_shadow] above, and every binding construct inside the arm
           already retires a name it rebinds from [recenv].  Like a parameter's
           entry it carries NO predicate — the constant is wholly
           unconstrained, so on its own it proves nothing in either direction
           and the call stays skipped unless the path context settles it. *)
        let re =
          match br.A.branch_pat with
          | A.PatCon (ctor, subpats) ->
            let sorts = try Hashtbl.find ctor_field_sorts ctor.A.txt with Not_found -> [] in
            if List.length subpats <> List.length sorts then re
            else
              List.fold_left2
                (fun re sub srt ->
                  match sub, srt with
                  | A.PatVar n, Smt.SData s when is_record_sort s -> (n.A.txt, s) :: re
                  | _ -> re)
                re subpats sorts
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
        (* A Bool-literal arm — `match cond do true -> … false -> … end`.
           This is the same branch on the same Bool as an [A.EIf], so it earns
           the same fact, and it is recorded in the same (condition, negated)
           form the [A.EIf] arm below uses: the `true` arm learns the
           scrutinee holds, the `false` arm learns its negation.

           Unlike the constructor narrowing above this needs NO stable name
           for the scrutinee — a path condition is an arbitrary expression, so
           an inline `match a >= b do` works exactly as `if a >= b do` does.
           Gating on the PATTERN being a Bool literal is what keeps it typed:
           only a Bool scrutinee can be matched against `true`/`false`. *)
        let p =
          match br.A.branch_pat with
          | A.PatLit (A.LitBool bv, _) -> (subj, not bv) :: p
          | _ -> p
        in
        (* Arm-order exclusion.  Reaching this arm means every EARLIER arm
           failed to match, so for each of those whose failure is decided purely
           by the tag ([arm_excludes_tag]), the scrutinee is known NOT to carry
           it.  This is what gives the `_` arm of

             match xs do Nil -> Err(…) | _ -> Ok(mean(xs)) end

           the fact `not is_Nil(xs)` — the shape every "safe wrapper" in a
           standard library has, and previously a permanent source of unprovable
           debt.  Same three guards as the positive narrowing above, plus: an
           earlier arm with a guard, or with a refutable sub-pattern, licenses
           nothing, because it can fail with the tag still matching. *)
        let p =
          match subj with
          | A.EVar s when not (List.mem s.A.txt binders) ->
            List.fold_left
              (fun p (prev : A.branch) ->
                match arm_excludes_tag prev with
                | Some ctor when sort_of_ctor ctor <> None ->
                  let sp = s.A.span in
                  let tester =
                    A.EApp
                      ( A.EVar { A.txt = "is_" ^ ctor; A.span = sp }
                      , [ A.EVar { A.txt = s.A.txt; A.span = sp } ]
                      , sp )
                  in
                  (tester, true) :: p
                | _ -> p)
              p earlier
          | _ -> p
        in
        (* Arm-order exclusion for Bool-literal arms, the counterpart of the
           tag exclusion above: reaching this arm means every earlier
           `true ->` / `false ->` failed to match, so the scrutinee is known
           NOT to be that literal — which is what gives the `_` arm of
           `match cond do true -> … _ -> … end` the negated guard, exactly as
           an `if`'s else-branch gets it.  An earlier arm carrying a GUARD
           licenses nothing: it can fail with the literal still matching. *)
        let p =
          List.fold_left
            (fun p (prev : A.branch) ->
              match prev.A.branch_pat, prev.A.branch_guard with
              | A.PatLit (A.LitBool bv, _), None -> (subj, bv) :: p
              | _ -> p)
            p earlier
        in
        visit ~root errctx defs ctx p lets sc re cb br.A.branch_body;
        br :: earlier)
      [] branches
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
  | A.ELetQ (p, e1, e2, _) | A.ELetStar (p, e1, e2, _) ->
    go e1;
    (* `let? p = e1` (and `let* p = e1`, same shape) binds p's names in the
       Ok payload / flat_map callback before continuing into e2 — a binding
       construct exactly like ELet/ELam/EMatch, so it must shadow any
       same-named outer refined local before e2 is visited. *)
    let binders = pat_binders p in
    let sc = scope_shadow sc binders in
    let re = recenv_shadow re binders in
    let cb = cb_shadow cb binders in
    let ctx = local_shadow ctx binders in
    visit ~root errctx defs ctx (path_shadow path binders) (launder_shadow lets binders)
      sc re cb e2
  | A.EDbg (Some e, _) -> go e
  | A.ELit _ | A.EVar _ | A.EHole _ | A.EResultRef _ | A.EDbg (None, _) -> ()

(* =================================================================
   §20 Refinement-placement warnings
   ================================================================= *)

(* Render a dotted MODULE path (`List.length`, `M.N.f`, …) back to a string, or
   [None] for anything else.  Mirrors [desugar_expr]'s [flatten_module_path]
   (`lib/desugar/desugar.ml`) exactly, which is the ground truth for what the
   parser produces for a dotted reference: an uppercase module segment parses
   as a zero-arg `A.ECon`, and the chain BOTTOMS OUT there.

   A bare `A.EVar` receiver is deliberately NOT accepted. `c.cb(1)` is a record
   FIELD call on a value, not a qualified call on a module; flattening it would
   report it as "a qualified call" and suggest the field name as a "bare
   spelling", both of which are false. It enforces nothing either way (`smt_of`
   has no arm for an applied field access), but a wrong explanation costs more
   than silence here. *)
let rec qualified_name (e : A.expr) : string option =
  match e with
  | A.ECon (mod_name, [], _) -> Some mod_name.A.txt
  | A.EField (r, { A.txt = n; _ }, _) ->
    Option.map (fun base -> base ^ "." ^ n) (qualified_name r)
  | _ -> None

(* The bare measure a QUALIFIED spelling should be rewritten to, independent of
   whether that alias is currently withdrawn.

   Deliberately NOT [measure_alias]: that function is gated on the
   stdlib-ownership refs ([list_length_is_stdlib] &c), so it answers "does this
   spelling alias `len` right now". The question here is the different one
   "what should the author write instead", whose answer is `len` either way —
   a withdrawn alias is a separate problem with its own attribution machinery
   ([withdrawals]), not a reason to send the author somewhere else.

   Deriving the suggestion from the last dotted segment instead — the obvious
   shortcut — hands back `length`, which is not predicate vocabulary: following
   that advice merely swaps this warning for the unknown-name one, and the
   contract still enforces nothing. *)
let qualified_measure_spelling (qname : string) : string option =
  match qname with "List.length" | "String.byte_size" -> Some "len" | _ -> None

(* ── Predicate-vocabulary warning ──────────────────────────────────────────
   A refinement predicate that calls a name [known_predicate_fn] does not
   recognize is never reflected into an SMT query — the definite-failure
   stance simply skips it, so the contract silently enforces nothing.  This
   walk finds every `{T | pred}` in the module (parameter, return, and local
   `let`-binding refinements — anywhere `A.TyRefine` can appear) and warns
   once per unrecognized applied name.

   Must run AFTER [registered_measures] is populated (see [check_module]):
   otherwise every user `@[measure]` looks unrecognized and warns spuriously.

   [warn_qualified_call] is the shared remedy-builder for an unresolved
   dotted spelling [qname], reached whether it arrives as an un-flattened
   `EField` chain or as a dotted `EVar` [Desugar.desugar_ty] already
   flattened but that still failed [known_predicate_fn] (alias withdrawn, or
   simply not a recognized qualified spelling). *)
let warn_qualified_call (errctx : Err.ctx) ~(span : A.span) (qname : string) : unit =
  let remedy =
    match qualified_measure_spelling qname with
    | Some bare -> Printf.sprintf " Use the bare spelling `%s` instead." bare
    | None ->
      " A predicate can only call the bare measure vocabulary — `len`, or an \
       `@[measure]` function by its bare name."
  in
  Err.warning errctx ~span
    (Printf.sprintf
       "`%s` is a qualified call inside a refinement predicate. This spelling is \
        never reflected here, so the refinement enforces nothing.%s"
       qname remedy)

let warn_predicate_expr (errctx : Err.ctx) (e : A.expr) : unit =
  let rec go (e : A.expr) =
    match e with
    | A.EApp (A.EVar { A.txt = f; _ }, args, span) ->
      if not (known_predicate_fn f) then begin
        if String.contains f '.' then
          (* [Desugar.desugar_ty] (Task 8) now flattens a MODULE-PATH call head
             (`List.length(_)`) in predicate position into this dotted `EVar`
             the SAME way ordinary call heads are flattened — so a live alias
             is already reflected by the time [known_predicate_fn] is
             consulted, and this branch is reached ONLY when the alias is
             unavailable (withdrawn by a competing binding, or simply not a
             recognized qualified spelling at all).  Route it through the
             SAME remedy as an unresolved qualified call so a withdrawn
             `List.length` still points at `len`, instead of degrading to the
             generic "not a measure" message below. *)
          warn_qualified_call errctx ~span f
        else
          Err.warning errctx ~span
            (Printf.sprintf
               "`%s` is not a measure or known predicate, so this refinement is not checked. \
                Annotate the function `@[measure]`, or use a supported predicate."
               f)
      end;
      List.iter go args
    (* A qualified call in call position that ISN'T already flattened to a
       dotted `EVar` by [Desugar.desugar_ty] — e.g. a receiver that is itself
       a call (`f(x).g(y)`), which [Desugar.flatten_pred_quals] deliberately
       does not rewrite (mirrors [Desugar.desugar_expr]'s own `EField` arm,
       which only flattens a chain bottoming out at a bare module `ECon`). *)
    | A.EApp ((A.EField _ as fhd), args, span) ->
      (match qualified_name fhd with
       | Some qname -> warn_qualified_call errctx ~span qname
       | None -> ());
      go fhd;
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

(* Does [t] carry a refinement ANYWHERE — either position of an arrow spine
   (so both a parameter and the return), or nested inside a type argument,
   tuple, record field or linearity wrapper?  Every one of those positions is
   equally inert in an interface method signature, so the detector must not be
   narrowed to the spine.  Mirrors [warn_predicate_ty]'s traversal exactly. *)
let rec ty_has_refinement (t : A.ty) : bool =
  match t with
  | A.TyRefine _ -> true
  | A.TyCon (_, args) -> List.exists ty_has_refinement args
  | A.TyArrow (a, b) -> ty_has_refinement a || ty_has_refinement b
  | A.TyTuple ts -> List.exists ty_has_refinement ts
  | A.TyRecord fs -> List.exists (fun (_, t) -> ty_has_refinement t) fs
  | A.TyLinear (_, t) -> ty_has_refinement t
  | A.TyChan _ | A.TyVar _ | A.TyNat _ | A.TyNatOp _ -> false

(* ── Interface-signature refinement warning ────────────────────────────────
   A refinement written in an `interface` method signature (`A.method_decl`'s
   [md_ty]) is inert.  NOTHING in this pass reads [md_ty]: [visit_decl]'s
   `DInterface` arm descends only into [md_default], and the two other walks
   that touch [iface_methods] ([stdlib_member_defs_ok], [bare_builtin_undefined])
   read method NAMES only.  Nor does the front end carry it anywhere:
   [Desugar.inject_defaults] synthesises a default method's `fn_def` with
   `fn_ret_ty = None` and parameters taken from the default LAMBDA (which
   carries no `param_ty`), so even the one place an interface signature turns
   into code drops the predicate on the floor.

   So it obliges no call site AND lets no body assume anything — a missing
   check, not an unsound one.  The defect is that it is silent: it parses,
   typechecks, and reads exactly like a working contract.

   The remedy is deliberately stated for BOTH positions, because they are
   enforced under different conditions and naming only the parameter one would
   be wrong advice for a return refinement:
     · a RETURN refinement on an `impl` method is always checked — [visit_fn]
       calls [check_fn_post] unconditionally;
     · a PARAMETER refinement is enforced only when [adoptable_impl_methods]
       adopts the method name (exactly one `impl` defines it and no top-level
       `fn` owns it); otherwise [visit_decl] walks the body with the parameter
       refinements STRIPPED and no caller is obliged.
   Saying "put it on the impl parameter" flatly would send an author with an
   ambiguous method name from one silent no-op to another.

   The caller has already established [ty_has_refinement m.md_ty] and branches
   on it.  [strict] is the module's own `cap verified` status — NOT read from
   the [strict_verified] ref, which by the time [warn_predicate_decls] runs
   has already been restored by [visit_decls]'s [Fun.protect] (it is scoped to
   the walk, and this vocabulary pass runs after the walk finishes).  The
   caller threads the flag through explicitly for that reason; see
   [warn_predicate_decls]. `cap verified` promises "if it compiles, it is
   proved" — a contract that provably enforces nothing is exactly the shape
   that promise exists to rule out, so under `cap verified` this is an error,
   matching [check_call]/[check_post]'s own escalation. *)
let warn_iface_method_refinement (errctx : Err.ctx) ~(strict : bool) (m : A.method_decl) : unit =
  let msg =
    Printf.sprintf
      "the interface signature of `%s` carries a refinement, which enforces \
       nothing: an interface method signature is never read by the refinement \
       checker, so no call site is obliged by this predicate and no body may \
       assume it. Write the refinement on the corresponding `impl` method's own \
       signature instead — a refinement on its return type is always checked, \
       and one on a parameter is enforced when the method name is unambiguous \
       (exactly one `impl` defines it and no top-level `fn` shares the name)."
      m.A.md_name.A.txt
  in
  if strict then Err.error errctx ~span:m.A.md_name.A.span msg
  else Err.warning errctx ~span:m.A.md_name.A.span msg

(* ── `sig` signature refinement warning ────────────────────────────────────
   A refinement in a `sig` module signature (`A.sig_def`'s [sig_fns]) is inert
   for the same structural reason the interface one is: nothing in this pass
   reads [sig_fns].  [visit_decl] has no `DSig` arm that descends, and the
   signature is an ASCRIPTION — it constrains what a module exports, not what
   any particular function body does, so there is no `fn_def` for the predicate
   to attach to and no call site that consults it.

   The remedy is the module's own `fn` definition, where a parameter refinement
   obliges callers and a return refinement is discharged against the body.

   Emits unconditionally: the caller has already established
   [ty_has_refinement]. *)
let warn_sig_fn_refinement (errctx : Err.ctx) (sig_name : A.name) (fn_name : A.name) : unit =
  Err.warning errctx ~span:fn_name.A.span
    (Printf.sprintf
       "the `sig %s` signature of `%s` carries a refinement, which enforces \
        nothing: a `sig` signature is never read by the refinement checker, so \
        no call site is obliged by this predicate and no body may assume it. \
        Write the refinement on the module's own `fn` definition instead, where \
        a parameter refinement obliges callers and a return refinement is \
        checked against the body."
       sig_name.A.txt fn_name.A.txt)

(* ── `extern` signature refinement warning ─────────────────────────────────
   A refinement on an `extern` function's parameter or return type is inert,
   and here the reason is not merely that the pass does not walk it — it is
   that it CANNOT be honoured.  The callee is foreign C, so:
     · a RETURN refinement is an unverifiable claim: there is no March body to
       discharge it against, and assuming it would be UNSOUND rather than
       merely missing;
     · a PARAMETER refinement has a March-side call site that could in
       principle be obliged, but the extern declaration is not a `fn_def` and
       registers no contract, so today it obliges nothing.
   The remedy is a March wrapper: put the parameter refinement on the wrapper,
   where callers are obliged, and CHECK the foreign result at runtime rather
   than asserting it in a type.

   Emits unconditionally: the caller has already established
   [ty_has_refinement]. *)
let warn_extern_fn_refinement (errctx : Err.ctx) (ef : A.extern_fn) : unit =
  Err.warning errctx ~span:ef.A.ef_name.A.span
    (Printf.sprintf
       "the `extern` signature of `%s` carries a refinement, which enforces \
        nothing: the callee is not March code, so the refinement checker \
        obliges no caller with it and can discharge no claim about the value it \
        returns. Wrap the extern in a March `fn` and write the parameter \
        refinement there, where call sites are obliged; a foreign RESULT cannot \
        be verified at all and must be checked at runtime rather than asserted \
        in its type."
       ef.A.ef_name.A.txt)

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
  | A.ELetQ (_, e1, e2, _) | A.ELetStar (_, e1, e2, _) -> ge e1; ge e2
  | A.EAssert (e, _) -> ge e
  | A.ESigil (_, e, _) -> ge e

(* Exhaustive over [A.decl], for the same reason the obligation walks are: the
   `| _ -> ()` this replaced meant the "not a measure or known predicate"
   warning never fired for a refinement written on an `impl` or `interface`
   method — precisely where the widened checks now CONSUME such predicates, so
   an unrecognized one there was both unchecked and unmentioned. *)
(* Whether [decls] itself declares `cap verified` — the same test
   [visit_decls] applies, extracted so [warn_predicate_decls] (which runs
   AFTER [visit_decls] has already restored [strict_verified], see that
   function's [Fun.protect]) can recompute the same fact independently rather
   than reading a ref that no longer holds it. *)
let decls_declare_verified (decls : A.decl list) : bool =
  List.exists (function A.DOpts (opts, _) -> List.mem "verified" opts | _ -> false) decls

(* [strict]: whether the ENCLOSING decl list (module or `describe` block) is
   under `cap verified`.  Mirrors [strict_verified]'s own scoping rule from
   [visit_decls]: a nested `mod` does not inherit its parent's `cap verified`
   and recomputes from its own decls (below); a `describe` block is not a
   module and inherits the flag unchanged, matching [visit_decl]'s own
   [visit_group] treatment of `DDescribe`. *)
let rec warn_predicate_decls (errctx : Err.ctx) ~(strict : bool) (decls : A.decl list) : unit =
  let warn_fn (fd : A.fn_def) =
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
  in
  let expr = warn_predicate_expr_tys errctx in
  List.iter
    (function
      | A.DFn (fd, _) -> warn_fn fd
      | A.DMod (_, _, ds, _) -> warn_predicate_decls errctx ~strict:(decls_declare_verified ds) ds
      | A.DDescribe (_, ds, _) -> warn_predicate_decls errctx ~strict ds
      | A.DImpl (idf, _) -> List.iter (fun (_, fd) -> warn_fn fd) idf.A.impl_methods
      | A.DInterface (idf, _) ->
        List.iter
          (fun (m : A.method_decl) ->
            (* Either the signature carries a refinement — in which case the
               whole thing is inert and [warn_iface_method_refinement] says so —
               or it does not, in which case [warn_predicate_ty] has nothing to
               find.  Running BOTH would append "annotate the function
               `@[measure]`" to a signature where no annotation can help:
               following that advice leaves the contract enforcing nothing just
               the same, and a misleading remedy costs more here than a missing
               one.  The vocabulary warning still fires once the predicate is
               moved to the `impl` method, which is where it can act. *)
            if ty_has_refinement m.A.md_ty then warn_iface_method_refinement errctx ~strict m
            else warn_predicate_ty errctx m.A.md_ty;
            (* A DEFAULT body is real code; it is walked as such and is not
               part of the signature this warning is about. *)
            Option.iter expr m.A.md_default)
          idf.A.iface_methods
      | A.DLet (_, b, _) ->
        Option.iter (warn_predicate_ty errctx) b.A.bind_ty;
        expr b.A.bind_expr
      | A.DActor (_, _, ad, _) ->
        expr ad.A.actor_init;
        List.iter (fun (h : A.actor_handler) -> expr h.A.ah_body) ad.A.actor_handlers;
        Option.iter expr ad.A.actor_invariant
      | A.DApp (app, _) ->
        expr app.A.app_body;
        Option.iter expr app.A.app_on_start;
        Option.iter expr app.A.app_on_stop
      | A.DTest (t, _) -> expr t.A.test_body
      | A.DSetup (e, _) | A.DSetupAll (e, _) -> expr e
      (* `DSig` and `DExtern` used to sit in the "not walked" list below under
         the label "inert: no type annotation or expression that can carry a
         refinement predicate".  That label was FALSE for both and was
         demonstrated so by probe: `sig Store do fn put : Int -> {Int | _ > 0}
         end` exited 0 with no diagnostic at all.  Both are now walked, on the
         same footing as `DInterface` — same shape, same reason, and the same
         either/or between the inert-signature warning and the vocabulary one
         (running both would append "annotate the function `@[measure]`" to a
         position where no annotation can help). *)
      | A.DSig (sig_name, sd, _) ->
        List.iter
          (fun ((fn_name : A.name), (t : A.ty)) ->
            if ty_has_refinement t then warn_sig_fn_refinement errctx sig_name fn_name
            else warn_predicate_ty errctx t)
          sd.A.sig_fns
      | A.DExtern (ed, _) ->
        List.iter
          (fun (ef : A.extern_fn) ->
            let tys = ef.A.ef_ret_ty :: List.map snd ef.A.ef_params in
            if List.exists ty_has_refinement tys then warn_extern_fn_refinement errctx ef
            else List.iter (warn_predicate_ty errctx) tys)
          ed.A.ext_fns
      (* ── Not walked.  Named so a new decl form breaks the build. ──
         Genuinely inert: none of these carries a type annotation or expression
         that can hold a refinement predicate.  Do not re-derive that claim by
         eyeballing the list — it was load-bearing and wrong for `DSig`/`DExtern`
         until they were moved out of it above.  Probe a candidate before adding
         it here. ── *)
      | A.DType _ | A.DAlwaysLinearType _  (* refinements in a type DEFINITION
                                              are checked where they are used *)
      | A.DProtocol _ | A.DTransitions _
      | A.DNeeds _ | A.DProofCap _ | A.DOpts _
      | A.DDeriving _ | A.DSatisfy _       (* desugared into DImpl before this *)
      | A.DUse _ | A.DAlias _ -> ())
    decls

(* =================================================================
   §21 The declaration walk
   ================================================================= *)

(* [assume_params:false] walks the body with the parameter refinements erased,
   so none of them can discharge anything.  Used for an `impl` method whose
   contract [collect_all_defs] could not adopt unambiguously: with no caller
   obliged to establish the predicate, assuming it inside the body would be
   assume-without-check.  The POSTcondition check still sees the original
   [fd] — a return refinement is verified, not assumed, and verifying it
   against the declared parameters is exactly right. *)
let visit_fn ~root errctx defs ?(assume_params = true) (ctx : rctx) (fd : A.fn_def) : unit =
  let is_trusted = List.mem "trusted" fd.A.fn_attrs in
  (* `@[trusted]` outside `cap verified` changes no behaviour at all — [note]
     only consults [trusted_fn] inside the [strict_verified] escalation
     branch.  An attribute that silently does nothing is exactly the failure
     mode this subsystem keeps producing, so say so. *)
  if is_trusted && not !strict_verified then
    Err.warning errctx ~span:fd.A.fn_name.A.span
      (Printf.sprintf
         "`@[trusted]` on `%s` has no effect here: this function is not inside \
          a `cap verified` module, so there is no escalation for it to \
          suppress. Add `cap verified` to this module, or remove the attribute."
         fd.A.fn_name.A.txt);
  (* Scoped to exactly this function, mirroring [strict_verified]'s own
     save/restore around a decl list — a nested `fn` (there is no such thing
     in March, but a fresh call into [visit_fn] for a sibling clearly must not
     inherit this) never sees a stale `true` left behind by a caller. *)
  let saved_trusted = !trusted_fn in
  trusted_fn := is_trusted;
  Fun.protect ~finally:(fun () -> trusted_fn := saved_trusted) (fun () ->
    check_fn_post ~root errctx fd;
    let walked = if assume_params then fd else strip_param_refinements fd in
    List.iter
      (fun (c : A.fn_clause) ->
        let sc = List.fold_left scope_add_fnparam [] c.A.fc_params in
        let re = List.fold_left recenv_add_fnparam [] c.A.fc_params in
        let cb = List.fold_left cb_add_fnparam [] c.A.fc_params in
        (* A PARAMETER named like a module-level function shadows it for callee
           resolution inside this body too — see [local_shadow]. *)
        let ctx = local_shadow ctx (List.concat_map fnparam_binders c.A.fc_params) in
        let path = match c.A.fc_guard with Some g -> [ (g, false) ] | None -> [] in
        visit ~root errctx defs ctx path [] sc re cb c.A.fc_body)
      walked.A.fn_clauses)

let rec visit_decls ~root errctx defs (ctx : rctx) (decls : A.decl list) : unit =
  (* Gather this scope's aliases/uses first so every function in the module sees
     them (matches lexical, module-wide visibility; inner modules inherit). *)
  let ctx =
    List.fold_left
      (fun ctx d ->
        match d with
        | A.DAlias (ad, _) -> { ctx with aliases = (ad.A.alias_name.A.txt, dotted ad.A.alias_path) :: ctx.aliases }
        | A.DUse (ud, _) ->
          (* [ctx.modpath] here is exactly the module that OWNS this `use` —
             [visit_decls]'s caller ([visit_decl]'s [A.DMod] arm) extends
             [modpath] BEFORE recursing into this fold, so tagging with the
             current [ctx.modpath] needs no extra plumbing.  See the [uses]
             field comment. *)
          { ctx with uses = (dotted ud.A.use_path, ud.A.use_sel, ctx.modpath) :: ctx.uses }
        | _ -> ctx)
      ctx decls
  in
  (* `cap verified` is scoped to the decl list that declares it — saved and
     restored here so a nested module neither inherits it nor leaks its own
     back out.  See [strict_verified] for why inheritance would be wrong. *)
  let saved_strict = !strict_verified in
  strict_verified := decls_declare_verified decls;
  (* Per-decl-list, for the same reason [strict_verified] is: a nested module is
     its own unit of advice, and one hint there should not silence the parent's
     (or vice versa). *)
  let saved_hinted = !unverified_hinted in
  unverified_hinted := false;
  Fun.protect
    ~finally:(fun () ->
      strict_verified := saved_strict;
      unverified_hinted := saved_hinted)
    (fun () -> List.iter (visit_decl ~root errctx defs ctx) decls)

(* One declaration.  Every constructor of [A.decl] is named — there is NO
   wildcard, deliberately: for years this walk descended only into [DFn] and
   [DMod] and ended in `| _ -> ()`, so `cap no_panic` said nothing about a
   division inside an `impl` method, a top-level `let`, or an actor handler,
   and accepted programs that divided by zero at runtime.  With the match
   exhaustive, a 25th decl form is a COMPILE ERROR here rather than a silent
   hole — the same guarantee [stdlib_member_defs_ok] already gives. *)
and visit_decl ~root errctx defs (ctx : rctx) (d : A.decl) : unit =
  (* A bare expression that is not a function clause: no parameters, no guard,
     hence empty scope/recenv/cbenv and an empty path condition. *)
  let visit_expr e = visit ~root errctx defs ctx [] [] [] [] [] e in
  (* Decls that merely group other decls (`describe`) must NOT go through
     [visit_decls]: that would re-derive [strict_verified] from the inner list,
     which carries no `cap` directive of its own, and so would silently drop
     the enclosing module's capability.  A `describe` block is part of its
     module's scope, so it inherits. *)
  let visit_group ds = List.iter (visit_decl ~root errctx defs ctx) ds in
  match d with
  | A.DFn (fd, _) -> visit_fn ~root errctx defs ctx fd
  | A.DMod (name, _, ds, _) ->
    let modpath = if ctx.modpath = "" then name.A.txt else ctx.modpath ^ "." ^ name.A.txt in
    visit_decls ~root errctx defs { ctx with modpath } ds
  (* Each method body is an ordinary function body — but its parameter
     refinements may be assumed ONLY if callers are obliged to establish them,
     i.e. only if [collect_all_defs] adopted this method's contract under the
     name a caller would write.  When it could not (a `fn` owns the name, or
     two impls of the same interface define the method), the body is walked
     with the refinements stripped rather than silently trusted. *)
  | A.DImpl (idf, _) ->
    List.iter
      (fun ((mn : A.name), (fd : A.fn_def)) ->
        let assume_params = contract_is_enforced ctx defs mn.A.txt (sig_of_fn fd) in
        visit_fn ~root errctx defs ~assume_params ctx fd)
      idf.A.impl_methods
  (* An interface's DEFAULT method body is real code; the signatures are not. *)
  | A.DInterface (idf, _) ->
    List.iter
      (fun (m : A.method_decl) -> Option.iter visit_expr m.A.md_default)
      idf.A.iface_methods
  | A.DLet (_, b, _) ->
    (* A top-level `let`'s own annotation must be CHECKED against its bound
       expression exactly as a block-level `let`'s is -- see
       [check_let_annotation] and its call site inside the [A.EBlock] case
       above.  There is no enclosing block to thread scope/path/lets/recenv
       through here, so all four start empty, matching [visit_expr]'s own
       convention just above; a top-level `let` also has no following
       sibling statements in THIS sense of "block", so there is nothing to
       admit the proved fact into afterward. *)
    ignore (check_let_annotation ~root errctx defs ctx [] [] [] [] b);
    visit_expr b.A.bind_expr
  | A.DActor (_, _, ad, _) ->
    visit_expr ad.A.actor_init;
    List.iter
      (fun (h : A.actor_handler) ->
        (* Handler parameters bind exactly like named function parameters, so
           their refinements must be in scope for the body. *)
        let ps = List.map (fun p -> A.FPNamed p) h.A.ah_params in
        let sc = List.fold_left scope_add_fnparam [] ps in
        let re = List.fold_left recenv_add_fnparam [] ps in
        let cb = List.fold_left cb_add_fnparam [] ps in
        let ctx = local_shadow ctx (List.concat_map fnparam_binders ps) in
        visit ~root errctx defs ctx [] [] sc re cb h.A.ah_body)
      ad.A.actor_handlers;
    (* The @invariant predicate is evaluated at run time like any other
       expression, so obligations inside it count. *)
    Option.iter visit_expr ad.A.actor_invariant
  | A.DApp (app, _) ->
    visit_expr app.A.app_body;
    Option.iter visit_expr app.A.app_on_start;
    Option.iter visit_expr app.A.app_on_stop
  | A.DTest (t, _) -> visit_expr t.A.test_body
  | A.DSetup (e, _) | A.DSetupAll (e, _) -> visit_expr e
  | A.DDescribe (_, ds, _) -> visit_group ds
  (* ── Inert: these decl forms carry no expression an obligation can arise in.
     Named individually so adding a 25th form breaks the build here. ────── *)
  | A.DType _                (* type definitions: types only, no terms *)
  | A.DAlwaysLinearType _    (* likewise, plus a linearity marker *)
  | A.DSig _                 (* module signature: names and types only *)
  | A.DProtocol _            (* session type: message types, no bodies *)
  | A.DTransitions _         (* state-machine edges: names of fns declared elsewhere *)
  | A.DExtern _              (* FFI declarations: signatures, bodies live in C *)
  | A.DNeeds _               (* capability manifest: capability paths *)
  | A.DProofCap _            (* proof-capability declaration: a name *)
  | A.DOpts _                (* the `cap` directive itself, read above *)
  | A.DDeriving _            (* desugared into DImpl before this pass runs *)
  | A.DSatisfy _             (* likewise desugared into DImpl *)
  | A.DUse _                 (* import: read into [ctx.uses] above *)
  | A.DAlias _ -> ()         (* alias: read into [ctx.aliases] above *)

(* =================================================================
   §22 Registration and stdlib-shape validation
   ================================================================= *)

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
  Hashtbl.clear measure_scalar_field_dep;
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

(* Decide whether `List.length` in THIS compilation unit is the stdlib list
   length — the only reading under which aliasing it to `len` is a true fact.
   See [list_length_is_stdlib].

   The gate is deliberately COARSE.  A precise answer needs the lexical
   [resolve_call] resolver, which [smt_of] does not have in scope; and the
   asymmetry of the two errors is total — over-suppressing costs a missed
   proof (silence, the status quo ante), under-suppressing costs a FALSE
   POSITIVE on correct code.  So anything that even looks like a competing
   `List.length` withdraws the alias for the whole module.

   It cannot key on the module PATH.  bin/main.ml prepends the whole stdlib —
   including `mod List` — into every module it checks, so "reject any `mod
   List`" would disable the feature in production.  And the outer `mod Q` is
   the [module_] record rather than a decl, so a nested `mod List do fn length`
   lands at path `List.length` too, exactly like the stdlib's: the two are
   indistinguishable by name alone.

   What separates them is the SOURCE FILE the definition came from, tested
   against the identity the CALLER supplied in [stdlib_source_files].  It must
   NOT be inferred from the path's shape: an earlier revision of this gate
   asked for a parent directory named `stdlib`, which

     - disabled the feature outright in an installed March, where `stdlib/dune`
       ships the sources to `<prefix>/share/march` (parent `march`), and under
       any `MARCH_STDLIB` pointing elsewhere; and
     - accepted ANY file path ending `stdlib/list.march`, so a vendored or
       forked `List` under `MARCH_LIB_PATH` was taken for the real one and
       re-opened the false positive it was written to close.

     - `mod Q do mod List do fn length … end end`  -> not a stdlib file -> suppress
     - a vendored `MARCH_LIB_PATH` `mod List`      -> not a stdlib file -> suppress
     - the stdlib's own, whatever the layout       -> stdlib file       -> allow
     - no `List` module at all (the unit tests)    -> no defs           -> allow

   `alias Foo as List` and `use Some.List` can also make the spelling denote
   someone else's function, so either withdraws the alias too. *)
let is_stdlib_source_file (f : string) : bool = List.mem f !stdlib_source_files

(* ── Glob imports: LOOK instead of assuming ────────────────────────────────
   `import X` / `use X.*` can only make a spelling denote something else if X
   actually PROVIDES the competing member.  An earlier revision of both gates
   below withdrew on the mere presence of a glob, on the reasoning that it
   might carry anything.  That is not merely coarse, it is fatal: bin/main.ml
   prepends the whole stdlib into every compilation unit and both gates are
   unit-global, so the single `import Process` in `stdlib/system.march`
   withdrew every alias for EVERY March program ever compiled — the feature
   was inert in production, and only a REJECT witness could notice (a skip
   exits 0, exactly like a proof).

   So resolve the glob's target and ask.  Resolution is purely syntactic over
   the declarations of the compilation unit that was handed to us, which is
   all the module structure this pass has; whenever it cannot answer — the
   path names a module not present in the unit, or the search runs out of fuel
   — the answer is `true`, i.e. WITHDRAW, exactly as before.  Precision is
   only ever added where the contents are actually in hand.

   Direction of doubt is unchanged and non-negotiable: over-suppressing costs
   a missed proof (silence); under-suppressing puts a wrong fact in the
   assumption set, which makes violations EASIER to prove and reports correct
   code — a false positive, this pass's cardinal sin. *)

(* Walk [path] down through nested `mod` declarations from [root]. *)
let find_module_decls (root : A.decl list) (path : A.name list) : A.decl list option =
  let rec descend ds = function
    | [] -> Some ds
    | (seg : A.name) :: rest ->
      let rec search = function
        | [] -> None
        | A.DMod (n, _, ds', _) :: _ when n.A.txt = seg.A.txt -> descend ds' rest
        | _ :: tl -> search tl
      in
      search ds
  in
  match path with [] -> None | _ -> descend root path

(* Does a glob import of the module at [path] bring a competitor into scope?

   [binds_decl] recognises a NON-`use` declaration of the target module that
   provides the thing (a nested `mod List`, a `fn string_byte_length`, …).
   [names_it] answers whether an explicit selector list names it, and
   [single_binds] whether a bare `use A.B` (no selector) binds it under its
   last segment.  A `use` INSIDE the target is followed transitively, since we
   cannot be sure March does not re-export it; [fuel] bounds that walk and its
   exhaustion, like any other unresolved case, withdraws. *)
let glob_import_competes ~(root : A.decl list) ~(unit_name : string)
    ~(binds_decl : A.decl -> bool) ~(names_it : A.name list -> bool)
    ~(single_binds : A.name list -> bool) (path : A.name list) : bool =
  (* A path may be written relative to the unit's own module (`import
     System.Process` from inside `mod System`), whose declarations ARE the
     root list rather than a `DMod` within it. *)
  let resolve p =
    match find_module_decls root p with
    | Some ds -> Some ds
    | None -> (
      match p with
      | (hd : A.name) :: tl when hd.A.txt = unit_name -> find_module_decls root tl
      | _ -> None)
  in
  let rec provides fuel ds =
    List.exists
      (fun d ->
        binds_decl d
        ||
        match d with
        | A.DDescribe (_, ds', _) -> provides fuel ds'
        | A.DUse (u, _) -> (
          match u.A.use_sel with
          | A.UseSingle -> single_binds u.A.use_path
          | A.UseNames xs -> names_it xs
          | A.UseExcept xs -> (not (names_it xs)) && glob fuel u.A.use_path
          | A.UseAll -> glob fuel u.A.use_path)
        | _ -> false)
      ds
  and glob fuel p =
    if fuel <= 0 then true
    else match resolve p with Some ds -> provides (fuel - 1) ds | None -> true
  in
  glob 4 path

(* Is the qualified spelling `<md>.<fn>` still the standard library's own?
   Parameterised over the pair so the `List.length` and `String.byte_size`
   aliases share one gate rather than two that can drift apart.

   ── THE INVARIANT (shared with [bare_builtin_undefined]) ───────────────────
   Ask only: can this declaration make the spelling `<md>.<fn>` denote a
   function that is not the stdlib's?  Two ways — DEFINE a member named [fn]
   inside a module named [md], or REBIND the bare segment [md] to some other
   module.  Everything that can do either must be named here.

   An earlier revision asked instead "is this an `A.DFn` inside a `DMod`?" and
   ended its walk in a `| _ -> ()` wildcard.  A competing member defined as a
   module-level `let`, or declared in an `extern` block, was therefore
   invisible: the alias stayed on, `List.length` was equated with `len`, the
   dead branch under a contradictory guard was treated as reachable, and
   CORRECT code was reported — a false positive, the one error this pass must
   never make.  That is the identical hole [bare_builtin_undefined] had closed
   for the bare spelling and this gate never inherited; hence the match below
   is EXHAUSTIVE over [A.decl] with no wildcard, so a new declaration form is a
   compile error here rather than a silent hole.  The arms that do nothing say
   so by name, and each is a claim that that form can neither define a member
   nor rebind a module name; check it rather than trusting it.

   [mod_name] is the ENCLOSING module's own name.  The entry module's
   declarations are top-level rather than a `DMod` — and bin/main.ml strips the
   stdlib's `DMod List` whenever the entry module shadows it — so a file
   `mod List do fn length …` defines `List.length` with nothing nested to see.
   Starting the walk with `in_mod = true` when the names match closes that.

   That walk start is PINNED by `specs/lang/types/accept/t126_entry_module_
   shadows_list_length.march` (and `t127…string_byte_size` for the other
   alias), not by any unit fixture here — a string-parsed module has an empty
   [stdlib_source_files], so nothing in it can be told apart from the stdlib's
   own definitions.  The witness declares `length` as an `interface`/`impl`
   method pair on purpose: desugar's [strip_entry_self_qual] rewrites
   `List.length` to bare `length` when the entry module declares `length` as a
   `fn`, a `let` or (since 2026-07-30) an `extern`, so only the decl forms it
   does not rewrite (`impl`, `interface`) leave a qualified call site for this
   gate to matter at.  Revert this to `go false` and the corpus rejects `t126`
   with a false `len(ys) = 0`.

   The `A.DExtern` arm of the member scan below is pinned separately, by
   `accept/t139_nested_module_shadows_list_length_extern.march` — a NESTED
   `mod List` with a foreign `length`, whose module name [strip_entry_self_qual]
   does not touch.  Delete that arm and the corpus rejects `t139` with the same
   false `len(ys) = 0`.  Before 2026-07-30, `t126` covered both at once; it can
   no longer, because an entry-level extern member's call site is now stripped
   bare and never reaches the alias at all.

   Direction of doubt is always to SUPPRESS: a missed proof is silence, the
   status quo ante; a wrong fact in the assumption set is a false positive.

   Returns the verdict PLUS the span of the first competing declaration found,
   so a withdrawal can point at its cause instead of leaving the user to search
   the unit (which, with `MARCH_LIB_PATH`, may not even be their own code).
   The span is diagnostic-only — the boolean is computed exactly as before. *)
let stdlib_member_defs_ok ~(md : string) ~(fn : string) ~(mod_name : string)
    (decls : A.decl list) : bool * A.span option =
  let foreign = ref false in
  let rebound = ref false in
  let cause = ref None in
  let blame (sp : A.span) = if !cause = None then cause := Some sp in
  (* A member definition only competes if it did NOT come from the standard
     library's own sources — see [is_stdlib_source_file]. *)
  let defines in_mod (sp : A.span) b =
    if in_mod && b && not (is_stdlib_source_file sp.A.file) then begin
      foreign := true;
      blame sp
    end
  in
  let mentions_md xs = List.exists (fun (n : A.name) -> n.A.txt = md) xs in
  (* Does glob-importing the module at [path] put some other module under the
     bare name `<md>`?  A nested `mod <md>` or an `alias … as <md>` inside the
     target does; nothing else in it can. *)
  let glob_competes path =
    glob_import_competes ~root:decls ~unit_name:mod_name
      ~binds_decl:(function
        | A.DMod (n, _, _, _) -> n.A.txt = md
        | A.DAlias (a, _) -> a.A.alias_name.A.txt = md
        | _ -> false)
      ~names_it:mentions_md
      ~single_binds:(fun p ->
        match List.rev p with last :: _ -> last.A.txt = md | [] -> false)
      path
  in
  (* A `use`/`alias` competes for the bare name `<md>` on the same terms a
     member definition does: only when it is the PROGRAM's, not the standard
     library's.  Without this the exclusion was asymmetric — [defines] already
     ignored stdlib spans — and one `import` added inside stdlib withdrew the
     alias for every program compiled with that stdlib.

     That happened: #112 added `import Process` to stdlib/system.march to
     dedupe System.ProcessResult.  It is a glob (`UseAll`), which an earlier
     revision of this scan treated as "could carry a nested module named
     List", so `List.length` stopped being recognised as the stdlib's and
     every `{List(a) | len(_) > 0}` contract silently stopped being enforced —
     caught only by specs/lang/types/reject/t117, whose whole purpose is to
     notice the alias going missing.

     Scoping makes this sound beyond the stdlib case: an import inside
     `mod System` binds names in System's body, not in the module being
     checked.  This stays conservative for user code and only stops the
     stdlib's own internals from speaking for the program.

     ── WHY THIS COMPOSES WITH [glob_competes] ─────────────────────────────
     The two guards were written independently for the same bug and are kept
     BOTH, conjoined: a glob withdraws only when it is the program's own AND
     its target provably provides a competitor.  That is sound for the reason
     any intersection of over-approximations is.  Write C for "this
     declaration really can make `<md>` denote a non-stdlib module".  The
     span rule is sound, i.e. C ⟹ ¬is_stdlib_source_file; the resolution rule
     is sound, i.e. C ⟹ glob_competes (unresolvable answers `true`).  Hence
     C ⟹ both, so anything that really competes still withdraws, and the two
     only ever subtract cases where at least one of them has a proof that
     nothing competes.  Neither can license the other into missing a genuine
     competitor, because neither weakens the other's test — they are ANDed,
     not substituted. *)
  let rebinds (sp : A.span) b =
    if b && not (is_stdlib_source_file sp.A.file) then begin
      rebound := true;
      blame sp
    end
  in
  (* ── The UseSingle narrowing (Task 9, 2026-07-31): LOOK, don't assume ────
     `use X.<md>` used to withdraw purely syntactically on its last path
     segment, while the two glob forms already RESOLVE their target and check
     it.  Measured cost (MARCH_LIB_PATH fixture, obligation-ledger report):
     one nested `use Extras.Deep.List` in a dependency module — whose target
     had NO `length` member at all — flipped an entry program's obligation
     from `1 proved` to `1 skipped (alias-withdrawn)`, program-wide.

     [use_target_provides] answers: can the module at [path] provide a member
     named [fn]?  If it provably cannot, rebinding the bare segment `<md>` to
     it cannot make `<md>.<fn>` denote a non-stdlib function at ANY call site
     — the spelling either fails to resolve through that binding (a typecheck
     error, not a wrong refinement fact) or resolves elsewhere, and any
     elsewhere that competes is some OTHER declaration this walk still sees.
     The argument deliberately does NOT rest on resolver semantics (scoping,
     shadowing order): it only needs "a module provides no `<fn>` ⟹ member
     lookup of `<fn>` in it finds nothing", so the resolve_call step-ordering
     hole filed in specs/todos.md is neither consulted nor widened.

     Fail-closed edges, each an over-approximation:
       - resolution considers EVERY module scope of the unit and ALL matches
         (duplicate paths, enclosing-relative spellings), withdrawing if ANY
         match provides — which resolution the real resolver would pick is
         exactly the question this pass cannot answer;
       - nothing resolves ⇒ withdraw, as the glob forms always have;
       - "provides" counts every member-capable decl form the [defines] scan
         counts (fn, let-bound, extern, interface/impl — the latter two the
         same deliberate over-approximation documented on the member arms
         below), PLUS the target's own use-forms: a `use Y.{<fn>}` or an
         unenumerable glob inside the target may re-export the member, so
         both count as providing (glob fuel exhaustion ⇒ provides).

     Note the residual duty is small by construction: a target that provides
     `<fn>` via a DIRECT member decl is a `mod <md>` carrying that member,
     which the [defines] scan withdraws independently — so this check alone
     stands guard over the re-export and unresolvable shapes, and an
     under-count in the member forms here is still backstopped there.
     DAlias/UseNames stay unconditionally withdrawing: no measured cost
     implicated them, and each narrowing in this gate must pay its own way. *)
  let use_target_provides (path : A.name list) : bool =
    let member = function
      | A.DFn (fd, _) -> fd.A.fn_name.A.txt = fn
      | A.DLet (_, b, _) -> List.mem fn (pat_binders b.A.bind_pat)
      | A.DExtern (ed, _) ->
        List.exists (fun (f : A.extern_fn) -> f.A.ef_name.A.txt = fn) ed.A.ext_fns
      | A.DInterface (idf, _) ->
        List.exists
          (fun (m : A.method_decl) -> m.A.md_name.A.txt = fn)
          idf.A.iface_methods
      | A.DImpl (idf, _) ->
        List.exists (fun ((mn : A.name), _) -> mn.A.txt = fn) idf.A.impl_methods
      | _ -> false
    in
    let mentions_fn xs = List.exists (fun (n : A.name) -> n.A.txt = fn) xs in
    (* Every decl-list scope in the unit: the root, and the body of every
       (arbitrarily nested) module.  `describe` blocks do not open a scope. *)
    let scopes =
      let rec go acc ds =
        List.fold_left
          (fun acc d ->
            match d with
            | A.DMod (_, _, ds', _) -> go (ds' :: acc) ds'
            | A.DDescribe (_, ds', _) -> go acc ds'
            | _ -> acc)
          acc ds
      in
      go [ decls ] decls
    in
    (* All decl-lists reachable by [p] from scope [ds] — every matching module
       per segment, describe blocks flattened at each level. *)
    let rec descend_all ds p =
      match p with
      | [] -> [ ds ]
      | (seg : A.name) :: rest ->
        let rec at_level acc = function
          | [] -> acc
          | A.DMod (n, _, ds', _) :: tl when n.A.txt = seg.A.txt ->
            at_level (descend_all ds' rest @ acc) tl
          | A.DDescribe (_, ds', _) :: tl -> at_level (at_level acc ds') tl
          | _ :: tl -> at_level acc tl
        in
        at_level [] ds
    in
    let resolve_all p =
      let direct = List.concat_map (fun s -> descend_all s p) scopes in
      (* A path may be written relative to the unit's own module, whose
         declarations are the root list rather than a `DMod` within it. *)
      match p with
      | (hd : A.name) :: (_ :: _ as tl) when hd.A.txt = mod_name ->
        direct @ List.concat_map (fun s -> descend_all s tl) scopes
      | _ -> direct
    in
    let rec provides fuel ds =
      List.exists
        (fun d ->
          member d
          ||
          match d with
          | A.DDescribe (_, ds', _) -> provides fuel ds'
          | A.DUse (u, _) -> (
            match u.A.use_sel with
            (* `use A.B` binds the MODULE B, not B's members — but a
               lowercase last segment is a shape we do not understand, so
               count it as providing rather than reason about it. *)
            | A.UseSingle -> (
              match List.rev u.A.use_path with
              | last :: _ -> last.A.txt = fn
              | [] -> false)
            | A.UseNames xs -> mentions_fn xs
            | A.UseExcept xs -> (not (mentions_fn xs)) && glob fuel u.A.use_path
            | A.UseAll -> glob fuel u.A.use_path)
          | _ -> false)
        ds
    and glob fuel p =
      if fuel <= 0 then true
      else
        match resolve_all p with
        | [] -> true
        | ms -> List.exists (provides (fuel - 1)) ms
    in
    match resolve_all path with
    | [] -> true
    | ms -> List.exists (provides 4) ms
  in
  let rec go in_mod ds =
    List.iter
      (function
        (* ── Can define `<md>.<fn>` ──────────────────────────────────────── *)
        | A.DFn (fd, sp) -> defines in_mod sp (fd.A.fn_name.A.txt = fn)
        (* `let length = fn xs -> …` is a member exactly like `fn length`. *)
        | A.DLet (_, b, sp) -> defines in_mod sp (List.mem fn (pat_binders b.A.bind_pat))
        (* An `extern` block declares its functions as members of the module
           that encloses it. *)
        | A.DExtern (ed, sp) ->
          defines in_mod sp
            (List.exists (fun (f : A.extern_fn) -> f.A.ef_name.A.txt = fn) ed.A.ext_fns)
        (* Interface/impl methods are counted as a DELIBERATE OVER-APPROXIMATION.
           They are NOT actually reachable under the declaring module's
           qualified spelling — `Bar.greet(1)` fails `unbound variable` for a
           nested module and the entry module alike, because a method resolves
           through interface dispatch rather than module member lookup (measured
           2026-07-30; see the residual in `specs/todos.md`).  An earlier
           revision of this comment asserted the opposite as fact.

           The arms stay anyway, because this gate's policy is suppress-on-doubt:
           over-counting a competitor costs a lost proof (silence), while
           under-counting puts a wrong fact in the assumption set and reports
           correct code — the cardinal sin here.  Do NOT "fix" this by deleting
           the arms: `accept/t126`/`t127` now depend on them, and see the
           coupling note on that residual before changing either. *)
        | A.DInterface (idf, sp) ->
          defines in_mod sp
            (List.exists
               (fun (m : A.method_decl) -> m.A.md_name.A.txt = fn)
               idf.A.iface_methods)
        | A.DImpl (idf, sp) ->
          defines in_mod sp
            (List.exists (fun ((mn : A.name), _) -> mn.A.txt = fn) idf.A.impl_methods)
        (* ── Rebinds the bare segment `<md>` ─────────────────────────────── *)
        | A.DAlias (a, sp) -> rebinds sp (a.A.alias_name.A.txt = md)
        | A.DUse (u, sp) ->
          (* Four selector forms, all of which can put some other module under
             the bare name `<md>`:
               `use X.<md>`            — UseSingle, the path's last segment
               `import X.{<md>, …}`    — UseNames (its list admits upper names)
               `import X`              — UseAll, a glob that can carry a
                                         nested module named `<md>`
               `import X, except: [_]` — UseExcept, ditto unless `<md>` is
                                         excluded. *)
          (match u.A.use_sel with
           (* UseSingle RESOLVES its target and asks whether it can provide
              the member, instead of assuming so from the segment name — see
              [use_target_provides] above for the measurement and the
              soundness argument.  Unresolvable ⇒ withdraw, as before. *)
           | A.UseSingle ->
             rebinds sp
               (match List.rev u.A.use_path with
                | last :: _ :: _ ->
                  last.A.txt = md && use_target_provides u.A.use_path
                | _ -> false)
           | A.UseNames xs -> rebinds sp (mentions_md xs)
           (* The two glob forms RESOLVE their target and look for a module
              named `<md>` rather than assuming one — see
              [glob_import_competes].  Unresolvable ⇒ withdraw, as before.
              [rebinds] then adds the stdlib-span exclusion on top. *)
           | A.UseExcept xs ->
             rebinds sp ((not (mentions_md xs)) && glob_competes u.A.use_path)
           | A.UseAll -> rebinds sp (glob_competes u.A.use_path))
        (* ── Contains declarations; recurse ──────────────────────────────── *)
        | A.DMod (name, _, ds, _) -> go (name.A.txt = md) ds
        (* A `describe` block does not open a module scope of its own, so its
           declarations sit at the enclosing module's level. *)
        | A.DDescribe (_, ds, _) -> go in_mod ds
        (* ── Can neither define `<md>.<fn>` nor rebind `<md>` ────────────── *)
        (* Types and their constructors: constructors are capitalised, so they
           cannot collide with the lowercase `length`/`byte_size`. *)
        | A.DType _ | A.DAlwaysLinearType _ | A.DTransitions _
        (* Capitalised entities in their own namespaces; none of them is a
           module that the bare segment `<md>` could resolve to. *)
        | A.DActor _ | A.DProtocol _ | A.DSig _ | A.DApp _
        (* Desugared into `DImpl` before this pass runs; handled above. *)
        | A.DDeriving _ | A.DSatisfy _
        (* Capability/compiler directives — no bindings at all. *)
        | A.DNeeds _ | A.DProofCap _ | A.DOpts _
        (* Test bodies bind only within themselves. *)
        | A.DTest _ | A.DSetup _ | A.DSetupAll _ -> ())
      ds
  in
  go (mod_name = md) decls;
  (((not !foreign) && not !rebound), !cause)

let list_length_defs_ok ~(mod_name : string) (decls : A.decl list) : bool * A.span option =
  stdlib_member_defs_ok ~md:"List" ~fn:"length" ~mod_name decls

let string_byte_size_defs_ok ~(mod_name : string) (decls : A.decl list) :
    bool * A.span option =
  stdlib_member_defs_ok ~md:"String" ~fn:"byte_size" ~mod_name decls

(* Does any binding construct inside [e] bind [name]?  BINDER positions only —
   an ordinary `string_byte_length(t)` CALL mentions the name without binding
   it, so [expr_mentions] (which counts every occurrence) is the wrong tool
   here: it would report the very uses this alias exists to serve.

   [iter_all] supplies the structure-agnostic descent, so a new expression form
   is covered as soon as it appears in [children]; this match only has to name
   the forms that BIND.

   Returns the SPAN of the first binder found rather than a bare boolean: the
   `cap verified` diagnostic points the user at the binding that withdrew the
   alias, and "somewhere in this unit" is not actionable when the unit spans a
   `MARCH_LIB_PATH` dependency.  The predicate [expr_binds_name] below is this
   function's `<> None`, so the two cannot drift. *)
let expr_binder_span (name : string) (e : A.expr) : A.span option =
  let found = ref None in
  let is n = n = name in
  let param (p : A.param) = is p.A.param_name.A.txt in
  iter_all
    (fun e ->
      if !found = None then
        let here =
          match e with
          | A.ELam (ps, _, sp) -> if List.exists param ps then Some sp else None
          | A.ELetFn (n, ps, _, _, sp) ->
            if is n.A.txt || List.exists param ps then Some sp else None
          | A.ELet (b, sp) ->
            if List.exists is (pat_binders b.A.bind_pat) then Some sp else None
          | A.ELetQ (p, _, _, sp) | A.ELetStar (p, _, _, sp) ->
            if List.exists is (pat_binders p) then Some sp else None
          | A.EMatch (_, brs, sp) ->
            if
              List.exists
                (fun (br : A.branch) -> List.exists is (pat_binders br.A.branch_pat))
                brs
            then Some sp
            else None
          | _ -> None
        in
        if here <> None then found := here)
    e;
  !found

let expr_binds_name (name : string) (e : A.expr) : bool =
  expr_binder_span name e <> None

(* Is the BARE name [name] still the compiler builtin?  There is no stdlib
   March definition of `string_byte_length` to identify (it is an intrinsic),
   so unlike [stdlib_member_defs_ok] there is no allow-because-stdlib case:
   any binding of the name is a competing one.

   Deliberately coarse — it does not ask whether the binding is actually in
   scope at the call, because the errors are asymmetric (over-suppress = a lost
   proof; under-suppress = a FALSE POSITIVE) and the precise answer needs a
   lexical resolver this pass does not have here.  A glob `use X.*` (or an
   `except:` list that does not exclude the name) can import an arbitrary
   `string_byte_length`, so both count as taking it.

   ── THE INVARIANT ──────────────────────────────────────────────────────────
   Scan every construct that can BIND [name] into a scope some `DFn` body can
   see.  That is strictly LARGER than the set the checker descends into, and
   conflating the two is how this gate has been wrong twice:

     - round 1 scanned declaration forms only, missing a `let`/parameter
       binding INSIDE a `DFn` body;
     - round 2 argued the scanned set "is exactly [visit_decls]'s", which is
       the wrong invariant even though the sentence was true.  [visit_decls]
       recurses into `DFn`/`DMod` alone — but a module-level `DLet` is never
       DESCENDED INTO and still BINDS the name for every sibling `DFn`, which
       is precisely where obligations are raised.  Both misses were the same
       failure: a real shadowing left the alias active, so a dead `== 0`
       branch was treated as reachable and a correct program was reported.

   So do not reason about where bodies are visited.  Ask only: can this
   construct put the name in scope for a checked body?  Two consequences —
   this walks expression binders via [expr_binds_name] (round 1), and the
   match below is EXHAUSTIVE over [A.decl] with no wildcard, so a new
   declaration form is a compile error here rather than a silent hole (round
   2).  The arms that do nothing say so by name, and each is a claim that that
   form cannot bind a bare value name; check it rather than trusting it. *)
let bare_builtin_undefined ?(mod_name = "") (name : string) (decls : A.decl list) :
    bool * A.span option =
  let taken = ref false in
  let cause = ref None in
  (* [sp] is the best location we have for this binder; the FIRST one recorded
     wins, so the reported cause is stable under list order. *)
  let take (sp : A.span) b =
    if b then begin
      taken := true;
      if !cause = None then cause := Some sp
    end
  in
  (* A binder found INSIDE an expression knows its own span, which is far more
     useful than the enclosing declaration's. *)
  let take_in (sp : A.span) e =
    match expr_binder_span name e with Some s -> take s true | None -> ignore sp
  in
  let named xs = List.exists (fun (n : A.name) -> n.A.txt = name) xs in
  (* Does glob-importing the module at [path] bring a member called [name]
     into scope?  Only a value DECLARATION of that name in the target does —
     a nested module's members are not glob-imported along with it. *)
  let glob_competes path =
    glob_import_competes ~root:decls ~unit_name:mod_name
      ~binds_decl:(function
        | A.DFn (fd, _) -> fd.A.fn_name.A.txt = name
        | A.DLet (_, b, _) -> List.mem name (pat_binders b.A.bind_pat)
        | A.DExtern (ed, _) ->
          List.exists (fun (f : A.extern_fn) -> f.A.ef_name.A.txt = name) ed.A.ext_fns
        | A.DInterface (idf, _) ->
          List.exists
            (fun (m : A.method_decl) -> m.A.md_name.A.txt = name)
            idf.A.iface_methods
        | A.DImpl (idf, _) ->
          List.exists (fun ((mn : A.name), _) -> mn.A.txt = name) idf.A.impl_methods
        | _ -> false)
      ~names_it:named
      ~single_binds:(fun _ -> false)
      path
  in
  let fn_def_takes (sp : A.span) (fd : A.fn_def) =
    take fd.A.fn_name.A.span (fd.A.fn_name.A.txt = name);
    List.iter
      (fun (c : A.fn_clause) ->
        take sp (List.mem name (List.concat_map fnparam_binders c.A.fc_params));
        (* A default-value expression is a binder site too (it can carry a
           lambda), and [fc_params] holds it outside the body. *)
        List.iter
          (function
            | A.FPDefault (_, d) -> take_in sp d
            | A.FPNamed _ | A.FPPat _ -> ())
          c.A.fc_params;
        (match c.A.fc_guard with Some g -> take_in sp g | None -> ());
        take_in sp c.A.fc_body)
      fd.A.fn_clauses
  in
  let rec go ds =
    List.iter
      (function
        (* ── Binds a bare value name ─────────────────────────────────────── *)
        | A.DFn (fd, sp) -> fn_def_takes sp fd
        (* A module-level `let` is never descended into by [visit_decls], yet it
           binds the name for every sibling `DFn` body — the round-2 hole. *)
        | A.DLet (_, b, sp) ->
          take sp (List.mem name (pat_binders b.A.bind_pat));
          take_in sp b.A.bind_expr
        (* An `extern` block declares its functions under their bare names. *)
        | A.DExtern (ed, sp) ->
          take sp
            (List.exists (fun (f : A.extern_fn) -> f.A.ef_name.A.txt = name) ed.A.ext_fns)
        (* Interface METHODS are called by bare name and dispatched on the
           argument's type, so a method of this name takes the spelling; a
           default body is a binder site as well. *)
        | A.DInterface (idf, sp) ->
          List.iter
            (fun (m : A.method_decl) ->
              take m.A.md_name.A.span (m.A.md_name.A.txt = name);
              match m.A.md_default with Some d -> take_in sp d | None -> ())
            idf.A.iface_methods
        | A.DImpl (idf, sp) ->
          List.iter
            (fun ((mn : A.name), (fd : A.fn_def)) ->
              take mn.A.span (mn.A.txt = name);
              fn_def_takes sp fd)
            idf.A.impl_methods
        | A.DAlias (a, sp) -> take sp (a.A.alias_name.A.txt = name)
        | A.DUse (u, sp) ->
          (match u.A.use_sel with
           (* A glob takes the name only if its target actually defines it —
              see [glob_import_competes].  Unresolvable ⇒ take, as before. *)
           | A.UseAll -> take sp (glob_competes u.A.use_path)
           | A.UseExcept xs -> take sp ((not (named xs)) && glob_competes u.A.use_path)
           | A.UseNames xs -> take sp (named xs)
           (* `use A.B` binds the MODULE `B`, never a bare value name. *)
           | A.UseSingle -> ())
        (* ── Contains declarations; recurse ──────────────────────────────── *)
        | A.DMod (_, _, ds, _) | A.DDescribe (_, ds, _) -> go ds
        (* ── Cannot bind a bare value name ───────────────────────────────── *)
        (* Types and their constructors: March constructors are capitalised, so
           they cannot collide with a lowercase builtin, and they are `ECon`
           rather than `EVar` at the call anyway. *)
        | A.DType _ | A.DAlwaysLinearType _ | A.DTransitions _
        (* Named, capitalised entities with their own namespace. *)
        | A.DActor _ | A.DProtocol _ | A.DSig _ | A.DApp _
        (* Desugared into `DImpl` before this pass runs; handled above. *)
        | A.DDeriving _ | A.DSatisfy _
        (* Capability/compiler directives — no value bindings at all. *)
        | A.DNeeds _ | A.DProofCap _ | A.DOpts _
        (* Test bodies bind only within themselves, and no obligation raised in
           a sibling `DFn` can see those bindings. *)
        | A.DTest _ | A.DSetup _ | A.DSetupAll _ -> ())
      ds
  in
  go decls;
  (not !taken, !cause)

(* =================================================================
   §23 Entry point: check_module
   ================================================================= *)

(* [measure_axioms] (default true) gates the whole measure-axiom machinery —
   datatype modelling, recursion-equation axioms, AND the M-b soundness gate (the
   gate exists to keep those axioms sound, so with axioms off it has no purpose).
   With it off, measures reflect purely symbolically (the pre-M-a behaviour:
   sound, no quantifiers, no datatype theory), an escape hatch for the per-query
   cost of quantified/datatype reasoning.  It changes only diagnostics, never the
   compiled artifact, so it is not part of the CAS cache key. *)
(* [stdlib_files]: the source files the caller loaded as the standard library.
   Only used to decide whether a `List.length` / `String.byte_size` in scope is
   the real one — see [stdlib_source_files].  (The bare `string_byte_length`
   alias does not consult it: that name is a compiler builtin with no stdlib
   definition, so any definition of it is competing by construction.)

   Omitting it does NOT disable the `List.length` alias.  It makes the answer
   "no file is the stdlib's", which matters only when a competing
   `List.length` definition is actually in scope: with none present — the case
   for every string-parsed test fixture — [list_length_defs_ok] finds nothing
   foreign and the alias stays enabled.  So the default is safe in the sense
   that no non-stdlib definition can ever be mistaken for the stdlib's, not in
   the sense that it turns the feature off. *)
let check_module ?(root = Sys.getcwd ()) ?(measure_axioms = true)
    ?(stdlib_files : string list = []) (errctx : Err.ctx)
    (m : A.module_) : unit =
  (* A module owns one solver declaration scope.  Z3 4.8.x does not reliably
     retract datatype declarations on [pop], even with [:global-decls false]:
     checking a later module that reuses a qualified type name with a different
     shape then yields declaration errors and silently downgrades its VCs to
     [Unknown].  Start each module with a fresh process while retaining solver
     reuse for every VC within the module; the content-addressed VC cache still
     preserves cross-module results. *)
  March_refine.Refine.shutdown ();
  (* The ledger is per-module: without this, counts accumulate across every
     compilation in one process (the test binary today, an LSP session
     tomorrow) and a report would describe every module ever checked. *)
  Obligation.reset ();
  (* Hygiene: [visit_decls] sets this per decl list, but a prior module must
     never be able to leave it on. *)
  strict_verified := false;
  stdlib_source_files := stdlib_files;
  let mod_name = m.A.mod_name.A.txt in
  (* Each gate answers "is the alias still safe?"; a `false` is a WITHDRAWAL,
     and the withdrawal is what a `cap verified` diagnostic must be able to
     name.  The boolean stored is exactly the gate's own answer — this records
     alongside it, it does not decide anything. *)
  withdrawals := [];
  let gate spelling measure ~str (ok, cause) =
    if not ok then
      withdrawals :=
        { wd_spelling = spelling; wd_measure = measure; wd_str = str; wd_span = cause }
        :: !withdrawals;
    ok
  in
  list_length_is_stdlib :=
    gate "List.length" "len" ~str:false (list_length_defs_ok ~mod_name m.A.mod_decls);
  string_byte_size_is_stdlib :=
    gate "String.byte_size" "len" ~str:true
      (string_byte_size_defs_ok ~mod_name m.A.mod_decls);
  string_byte_length_is_builtin :=
    gate "string_byte_length" "len" ~str:true
      (bare_builtin_undefined ~mod_name "string_byte_length" m.A.mod_decls);
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
  Hashtbl.reset measure_scalar_field_dep;
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
      mfns;
    (* Silent-inertness warning.  A measure reading a scalar constructor field
       is axiomatised correctly and still proves nothing, because call-site
       reflection erased the field (see [measure_scalar_field_dep]).  Every
       symptom of a working measure is present, so without this the author's
       only signal is that contracts using it never fire — which is how this
       cost a full investigation to find on `Array.length`.

       A WARNING, not an error: the measure is sound and its predicates remain
       legal vocabulary, so nothing that compiles today stops compiling.  It
       changes no verdict. *)
    List.iter
      (fun (name, fd) ->
        if Hashtbl.mem measure_scalar_field_dep name then
          Err.warning errctx ~span:fd.A.fn_name.A.span
            (Printf.sprintf
               "@[measure] `%s` reads a constructor field that is not itself a \
                data type, so its value cannot be computed at a call site and \
                refinements using it will never be proved or refuted."
               name))
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
  warn_predicate_decls errctx ~strict:(decls_declare_verified m.A.mod_decls) m.A.mod_decls
