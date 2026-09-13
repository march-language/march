(** Refinement checking, §7–§11: reflection, rendering, and the fact channels.

    Moved VERBATIM out of [Refine_check] (R2 of
    [specs/plans/2026-08-28-refine-check-decomposition.md]).  Sections, using
    the numbering of [Refine_check]'s own table of contents:

      §7  Reflection: March expressions into SMT terms
      §8  Rendering: predicates, models, counterexamples
      §9  Scope — the refined bindings in scope
      §10 The other fact channels: path, launder, recenv, cbenv
      §11 Signature extraction and definition collection

    §9 and §10 are the pass's TWO fact channels — the lexical scope of refined
    bindings, and the path conditions accumulated by the traversal.  A name
    retired from one but not the other is the shadowing bug this pass has had
    before; only a test asserting SILENCE catches it, which is why the reject
    corpus (`dune build @types-check --force`) is part of this file's
    verification and `ir-oracle` is not.

    [include Refine_encode] rather than qualified references: this band reads
    the mutable registries that layer owns, and they must be the SAME ref
    cells the rest of the pass writes. *)

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

(* [smt_of_r] is [smt_of]'s body, made to name its failure: [Error e] carries
   the innermost sub-expression that returned [None] in the [option] version —
   the leaf itself where reflection bottoms out (an opaque call, an unhandled
   operator, a resolver returning [None]), or, at a recursive arm, the CHILD's
   [Error] propagated unchanged rather than wrapped, so a failure three levels
   down still names the leaf, not each ancestor on the way up. [smt_of] is now
   this function with [Result.to_option] on the outside; the 18 existing
   callers, which want only the [option], are unchanged. *)
let rec smt_of_r ~resolve_var ~resolve_measure ?(resolve_field = fun _ _ -> None)
    ?(resolve_measure_app = fun _ _ -> None) ?(resolve_tester = fun _ _ -> None)
    ?(resolve_str_lit = fun _ -> None)
    (e : A.expr) : (Smt.term, A.expr) result =
  let r = smt_of_r ~resolve_var ~resolve_measure ~resolve_field ~resolve_measure_app
            ~resolve_tester ~resolve_str_lit in
  let b2 f a b =
    match r a, r b with
    | Ok x, Ok y -> Ok (f x y)
    | Error e, _ -> Error e
    | _, Error e -> Error e
  in
  match e with
  | A.ELit (A.LitInt n, _) -> Ok (Smt.IntLit n)
  | A.ELit (A.LitBool b, _) -> Ok (Smt.BoolLit b)
  (* A zero-argument constant function IS its literal (see [const_fns]);
     `_ < size_x()` reflects exactly as `_ < 128` does. *)
  | A.EApp (A.EVar { A.txt = f; _ }, [], _) when is_const_fn f ->
    Ok (Hashtbl.find const_fns f)
  (* A float literal, and float arithmetic over literals ONLY, folded to one.
     A `+.` with a non-literal operand falls through to [None] here, which makes
     the enclosing predicate untranslatable — the documented skip for symbolic
     float arithmetic. [float_const_of] does not itself recurse through
     [smt_of_r], so a failure here is blamed on the whole arithmetic
     sub-expression [e], not some inner piece of it. *)
  | A.ELit (A.LitFloat _, _)
  | A.EApp (A.EVar { A.txt = "+." | "-." | "*." | "/."; _ }, [ _; _ ], _) ->
    (match float_const_of e with Some f -> (match float_lit_term f with Some t -> Ok t | None -> Error e) | None -> Error e)
  | A.EApp (A.EVar { A.txt = "negate"; _ }, [ a ], _) when float_const_of a <> None ->
    (match float_const_of e with Some f -> (match float_lit_term f with Some t -> Ok t | None -> Error e) | None -> Error e)
  (* A string literal reflects to its per-VC constant, when the caller supplies
     a table.  Callers that cannot model strings leave [resolve_str_lit] at its
     default and the literal stays untranslatable — i.e. skipped. *)
  | A.ELit (A.LitString s, _) -> (match resolve_str_lit s with Some t -> Ok t | None -> Error e)
  (* A measure application m(e): m(var) reflects to a consistent measure symbol;
     m(expr) is evaluated via resolve_measure_app (e.g. concrete_len for a list);
     len(list-literal) is computed concretely without needing resolve_measure_app. *)
  | A.EApp (A.EVar { A.txt = m0; _ }, [ a ], _) when is_measure_app m0 ->
    (* One normalization point for BOTH sides: a path condition and a predicate
       are translated by this same function, so aliasing here is what makes
       `List.length(ys) > 0` and `len(_) > 0` land on the same SMT symbol. *)
    let m = measure_name m0 in
    (match a with
     | A.EVar { A.txt = x; _ } -> (match resolve_measure m x with Some t -> Ok t | None -> Error e)
     | _ ->
       (match if m = "len" then list_len a else None with
        | Some n -> Ok (Smt.IntLit n)
        | None ->
          (match r a with
           | Ok arg_term ->
             (match resolve_measure_app m arg_term with Some t -> Ok t | None -> Error e)
           | Error e2 -> Error e2)))
  (* A constructor tester `is_Ctor(e)`: reflects to the Z3 datatype tester
     ((_ is Ctor) e).  [resolve_tester] owns reflecting [e] into a term of the
     right datatype sort (and declaring/registering it); a context that cannot
     do that returns None and the predicate is skipped. *)
  | A.EApp (A.EVar { A.txt = m; _ }, [ arg ], _) when ctor_of_tester m <> None ->
    (match ctor_of_tester m with
     | Some ctor -> (match resolve_tester ctor arg with Some t -> Ok t | None -> Error e)
     | None -> Error e)
  | A.EVar { A.txt; _ } -> (match resolve_var txt with Some t -> Ok t | None -> Error e)
  (* Zero/multi-arity constructors: Nil → App("Nil",[]), Cons(h,t) → App("Cons",[h,t]).
     Only constructors registered in ctor_field_sorts are handled (builtins + user ADTs).
     [List.map] evaluates EVERY argument regardless of an earlier failure, matching
     [smt_of]'s side-effecting resolvers ([reflect_cache] et al.); the first [Error]
     found (left to right) is what's reported. *)
  | A.ECon ({ A.txt = ctor; _ }, args, _) when Hashtbl.mem ctor_field_sorts ctor ->
    let reflected = List.map r args in
    (match List.find_map (function Error e -> Some e | Ok _ -> None) reflected with
     | Some e -> Error e
     | None -> Ok (Smt.App (ctor, List.map (function Ok t -> t | Error _ -> assert false) reflected)))
  (* Field access on a bare variable: s.count → selector applied to s.
     Only EVar receivers are supported; complex receivers conservatively return
     None — safe under the definite-failure soundness stance. *)
  | A.EField (A.EVar { A.txt = x; _ }, { A.txt = fname; _ }, _) ->
    (match resolve_field x fname with Some t -> Ok t | None -> Error e)
  | A.EApp (A.EVar { A.txt = "&&"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.And (x, y)) a b
  | A.EApp (A.EVar { A.txt = "||"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Or (x, y)) a b
  | A.EApp (A.EVar { A.txt = "not"; _ }, [ a ], _) -> Result.map (fun x -> Smt.Not x) (r a)
  | A.EApp (A.EVar { A.txt = ">="; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Ge (x, y)) a b
  | A.EApp (A.EVar { A.txt = "<="; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Le (x, y)) a b
  | A.EApp (A.EVar { A.txt = ">"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Gt (x, y)) a b
  | A.EApp (A.EVar { A.txt = "<"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Lt (x, y)) a b
  | A.EApp (A.EVar { A.txt = "=="; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Eq (x, y)) a b
  | A.EApp (A.EVar { A.txt = "!="; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Ne (x, y)) a b
  | A.EApp (A.EVar { A.txt = "+"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Add (x, y)) a b
  | A.EApp (A.EVar { A.txt = "-"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Sub (x, y)) a b
  | A.EApp (A.EVar { A.txt = "negate"; _ }, [ a ], _) -> Result.map (fun x -> Smt.Neg x) (r a)
  | A.EApp (A.EVar { A.txt = "*"; _ }, [ a; b ], _) ->
    (match a, b with
     | A.ELit (A.LitInt k, _), _ -> Result.map (fun y -> Smt.MulLit (k, y)) (r b)
     | _, A.ELit (A.LitInt k, _) -> Result.map (fun x -> Smt.MulLit (k, x)) (r a)
     | _ -> Error e)
  | _ -> Error e

let smt_of ~resolve_var ~resolve_measure ?(resolve_field = fun _ _ -> None)
    ?(resolve_measure_app = fun _ _ -> None) ?(resolve_tester = fun _ _ -> None)
    ?(resolve_str_lit = fun _ -> None)
    (e : A.expr) : Smt.term option =
  Result.to_option
    (smt_of_r ~resolve_var ~resolve_measure ~resolve_field ~resolve_measure_app
       ~resolve_tester ~resolve_str_lit e)

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
  (* A string literal, quoted as March source spells it (best-effort: no
     escaping of embedded quotes, matching every other arm's "best-effort"
     stance). Needed so a genuine [Unreflectable_predicate] whose failing leaf
     IS a string literal (no [resolve_str_lit] in scope, e.g. a postcondition)
     names the literal instead of falling through to the [<predicate>]
     placeholder below. *)
  | A.ELit (A.LitString s, _) -> "\"" ^ s ^ "\""
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
                             | "+" | "-" | "*" | "/" | "%" | "+." | "-." | "*." | "/.") as op; _ },
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
(* A linearity wrapper is transparent to a VALUE's refinement: `linear {Int |
   _ > 0}` promises `_ > 0` of the same Int.  Every extractor below strips it
   first (plan phase 4); before that a refinement under `linear` parsed,
   typechecked, and obliged nobody. *)
let rec unlinear : A.ty -> A.ty = function
  | A.TyLinear (_, t) -> unlinear t
  | t -> t

let refined_param_ty : A.ty option -> (string * A.expr * string option) option = fun t ->
  match Option.map unlinear t with
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
  match Option.map unlinear fd.A.fn_ret_ty with
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
         ; param_tys = [ Some dom ]
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
let refined_scope_ty : A.ty option -> (string * A.expr * string option) option = fun t ->
  match Option.map unlinear t with
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

(* Does the local function [n] ESCAPE in [e] — occur anywhere other than as
   the head of a call `n(...)`?  Passed as a value (`apply(n, 0)`), returned,
   stored in a tuple, aliased by a `let`: all escapes.  A call through the
   escaped value is not obliged by [n]'s own parameter refinements (only a
   direct `n(...)` reaches the [cbenv] entry [visit] registers), so a body
   that ASSUMED them would be assume-without-check exactly as before phase 0.
   [visit] restores the assumption only when this is false for the body and
   for every later statement of the enclosing block.

   [pass_checked callee i] is the one exception: passing [n] as argument [i]
   of a call to [callee] is NOT an escape when the caller tells us the pass
   site is itself obliged — [Refine_check.visit]'s contravariant check proved
   (or reported) that [callee]'s declared domain there implies [n]'s own
   parameter refinement, so a call through that copy is covered.  Defaults
   to "never", the conservative answer.

   Deliberately OVER-approximate like [expr_mentions]: a rebinding of the
   same name and every occurrence under it count as escapes.  Over-reporting
   an escape only STRIPS an assumption (silence), never invents one. *)
let rec name_escapes ?(pass_checked : string -> int -> bool = fun _ _ -> false) (n : string)
    (e : A.expr) : bool =
  let esc = name_escapes ~pass_checked n in
  let any = List.exists esc in
  match e with
  | A.EApp (A.EVar m, args, _) when m.A.txt = n -> any args
  | A.EApp (A.EVar f, args, _) ->
    List.exists
      (fun (i, a) ->
        match a with
        | A.EVar m when m.A.txt = n -> not (pass_checked f.A.txt i)
        | a -> esc a)
      (List.mapi (fun i a -> (i, a)) args)
  | A.EVar m -> m.A.txt = n
  | A.ELit _ | A.EHole _ | A.EResultRef _ | A.EDbg (None, _) -> false
  | A.EApp (f, args, _) -> esc f || any args
  | A.ECon (_, args, _) | A.EAtom (_, args, _) | A.ETuple (args, _) -> any args
  | A.ELam (_, body, _) -> esc body
  | A.EBlock (es, _) -> any es
  | A.ELet (b, _) -> esc b.A.bind_expr
  | A.ELetFn (_, _, _, body, _) -> esc body
  | A.ELetQ (_, e1, e2, _) | A.ELetStar (_, e1, e2, _) -> esc e1 || esc e2
  | A.EMatch (subj, brs, _) ->
    esc subj
    || List.exists
         (fun (br : A.branch) ->
           (match br.A.branch_guard with Some g -> esc g | None -> false)
           || esc br.A.branch_body)
         brs
  | A.ERecord (fs, _) -> List.exists (fun (_, v) -> esc v) fs
  | A.ERecordUpdate (r, fs, _) -> esc r || List.exists (fun (_, v) -> esc v) fs
  | A.EField (r, _, _) -> esc r
  | A.EIf (c, t, el, _) -> any [ c; t; el ]
  | A.ECond (arms, _) -> List.exists (fun (c, b) -> esc c || esc b) arms
  | A.EPipe (a, b, _) | A.ESend (a, b, _) -> esc a || esc b
  | A.EAnnot (e, _, _) | A.ESpawn (e, _) | A.EAssert (e, _) | A.ESigil (_, e, _)
  | A.EDbg (Some e, _) -> esc e

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

(* [Some (ctor, i, d)] when reaching a LATER arm with head [ctor] implies
   that its binder at field [i] is not [d]: the earlier arm is unguarded, has
   head [ctor], and is irrefutable everywhere except a nullary constructor
   [d] at exactly one position.  One level only, nullary only: that is the
   `Cons(x, Nil)` shape, and it is the only shape whose negation is a single
   tester over a single binder. *)
let arm_excludes_nested (br : A.branch) : (string * int * string) option =
  match br.A.branch_pat, br.A.branch_guard with
  | A.PatCon (ctor, subs), None ->
    let refutable =
      List.mapi (fun i p -> (i, p)) subs
      |> List.filter (fun (_, p) -> not (irrefutable_pat p))
    in
    (match refutable with
     | [ (i, A.PatCon (d, [])) ] -> Some (ctor.A.txt, i, d.A.txt)
     | _ -> None)
  | _ -> None

let path_shadow (path : (A.expr * bool) list) (names : string list) : (A.expr * bool) list =
  if names = [] then path else List.filter (fun (c, _) -> not (expr_mentions names c)) path

(* =================================================================
   §10 The other fact channels: path, launder, recenv, cbenv
   ================================================================= *)

(* ── Right-hand sides a `let` may turn into the path fact `n == rhs` ───────
   Pure, deterministic, and inside the linear fragment the path translator
   ([smt_of] above / [check_call]'s [path_resolve_var]) already reflects.
   Calls are excluded (a refined return is handled by [scope_add_binding];
   an unrefined one carries no fact); `if` is excluded (its encoding is a
   separate decision); floats are excluded (symbolic float arithmetic does
   not reflect — see the float-constant-folding note above).

   A BARE variable is excluded too, deliberately: [smt_of]'s path translator
   reflects a variable at the INTEGER sort, but an ADT-typed alias
   (`let u = o` with `o : Option(Int)`) has tester facts about `o` sitting
   at the datatype sort. Pushing `u == o` then mixes sorts in the same VC,
   and the sort-conflict gate drops the WHOLE VC — not just the alias's own
   obligations, but unrelated ones too (e.g. `unwrap(o)`, which never
   mentions `u`). An alias also carries no exclusion fact through on its
   own (`let u = t; last(u)` stays undecided either way), so admitting it
   only had a cost, never a benefit. A variable remains admitted as an
   OPERAND of `+`/`-`/`*`, where it is always at the integer sort. *)
let rec let_equality_operand (e : A.expr) : bool =
  match e with
  | A.ELit (A.LitInt _, _) -> true
  | A.EVar _ -> true
  | A.EApp (A.EVar { A.txt = ("+" | "-"); _ }, [ a; b ], _) ->
    let_equality_operand a && let_equality_operand b
  | A.EApp (A.EVar { A.txt = "*"; _ }, [ a; b ], _) ->
    (match a, b with
     | A.ELit (A.LitInt _, _), _ -> let_equality_operand b
     | _, A.ELit (A.LitInt _, _) -> let_equality_operand a
     | _ -> false)
  | _ -> false

let let_equality_rhs (e : A.expr) : bool =
  match e with
  | A.EVar _ -> false
  | _ -> let_equality_operand e

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

(* ── Container environment: variable name -> element refinement ───────────
   `xs : List({Int | _ > 0})` promises every ELEMENT satisfies `_ > 0`; the
   promise is a contract on every value that flows into such a position (a
   list literal element-wise, another container-typed variable by
   implication, anything else a recorded skip — see
   [Refine_check.check_elements]) and a fact about every element taken out
   of it (`match xs do Cons(h, t) -> …` gives `h` the predicate and `t` the
   same element refinement).  Until 2026-09-13 a refinement inside a type
   argument parsed, typechecked, and obliged nobody
   (specs/todos/2026-09-01-nested-refinement-enforcement.md).

   The fourth fact channel, exactly like [scope] / [recenv] / [cbenv]: every
   binding construct retires a name it rebinds before adding any.  The
   element refinement is stored in [refined_param_ty]'s shape so [elem_sig]
   can hand it to [check_call] unchanged.  Containers: `List` and `Option`,
   the two whose constructors the checker's ADT registry already knows
   ([register_builtin_adts]); a refinement inside any other type argument
   is still unenforced and the audit still says so. *)
type contenv = (string * (string * (string * A.expr * string option))) list

let cont_shadow (ce : contenv) (names : string list) : contenv =
  if names = [] then ce else List.filter (fun (n, _) -> not (List.mem n names)) ce

let elem_refinement (t : A.ty option) : (string * (string * A.expr * string option)) option =
  match Option.map unlinear t with
  | Some (A.TyCon ({ A.txt = ("List" | "Option") as c; _ }, [ arg ])) ->
    (match refined_param_ty (Some arg) with Some r -> Some (c, r) | None -> None)
  | _ -> None

let cont_add_param (ce : contenv) (p : A.param) : contenv =
  let ce = cont_shadow ce [ p.A.param_name.A.txt ] in
  match elem_refinement p.A.param_ty with
  | Some e -> (p.A.param_name.A.txt, e) :: ce
  | None -> ce

let cont_add_fnparam (ce : contenv) : A.fn_param -> contenv = function
  | A.FPNamed p | A.FPDefault (p, _) -> cont_add_param ce p
  | A.FPPat pat -> cont_shadow ce (pat_binders pat)

(* A `let` enters the channel through an ANNOTATION only when its element
   obligations were PROVED (the caller passes [~proved]; the same rule
   [check_let_annotation] applies to a scalar annotation: an unproven
   annotation grants nothing), or as a straight alias of a variable already
   in it. *)
let cont_add_binding ~(proved : bool) (ce : contenv) (b : A.binding) : contenv =
  let ce = cont_shadow ce (pat_binders b.A.bind_pat) in
  match b.A.bind_pat with
  | A.PatVar n ->
    (match elem_refinement b.A.bind_ty with
     | Some e when proved -> (n.A.txt, e) :: ce
     | Some _ -> ce
     | None ->
       (match b.A.bind_expr with
        | A.EVar { A.txt = y; _ } ->
          (match List.assoc_opt y ce with Some e -> (n.A.txt, e) :: ce | None -> ce)
        | _ -> ce))
  | _ -> ce

(* A one-parameter signature carrying an element refinement, so one element
   (or the symbolic element of a container-typed variable) is checked by
   [check_call] exactly like an argument. *)
let elem_sig ~(name : string) ((binder, pred, sort) : string * A.expr * string option) : fn_sig =
  { param_names = [ name ]
  ; param_str = [ sort = Some str_sort ]
  ; param_scalar = [ scalar_sort_or_int sort ]
  ; param_tys = [ None ]
  ; refined = [ { idx = 0; binder; pred; sort } ]
  ; ret = None
  ; ret_sort = None }

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

(* A postcondition-derived entry whose predicate mentions the `let`'s own
   binder denotes the PRE-binding value under the post-binding name (the
   actuals were substituted by [postcond_of] before the binding took effect).
   Filing it would collapse two values onto one SMT symbol and, for a
   relational promise like `_ == n + 1`, manufacture a contradiction that
   proves every goal.  Declining is the only sound choice: the pre-binding
   symbol has already been retired by [scope_shadow]. *)
let self_mentioning (pat : A.pattern) (pred : A.expr) : bool =
  expr_mentions (pat_binders pat) pred

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

          The guard ([self_mentioning], defined above) applies to all THREE
          arms below, not just this ADT one.  The scalar and record arms have
          the identical shape and the identical latent hole (reachable on the
          parent commit through [reflect_scalar]'s `foreign_var` channel,
          which never went through [load_scope_measure_facts] at all); there
          is nothing ADT-specific about the hazard, so there is nothing
          ADT-specific about the fix. *)
       (match postcond fname args with
        | Some (binder, pred, m)
          when scalar_sort_of_marker m <> None
               && not (self_mentioning b.A.bind_pat pred) ->
          (n.A.txt, (binder, pred, m)) :: sc
        | Some (binder, pred, Some srt)
          when is_record_sort srt && not (self_mentioning b.A.bind_pat pred) ->
          (n.A.txt, (binder, pred, Some srt)) :: sc
        | Some (binder, pred, Some srt)
          when Hashtbl.mem adt_ctors srt
               && not (self_mentioning b.A.bind_pat pred) ->
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
  let param_tys = List.map param_ty_of c.A.fc_params in
  { param_names; param_str; param_scalar; param_tys; refined; ret = None; ret_sort = None }

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
      { param_names = []; param_str = []; param_scalar = []; param_tys = []; refined = []
      ; ret = None; ret_sort = None }
  in
  match return_refine_sorted fd with
  | Some (b, p, srt) -> { base with ret = Some (b, p); ret_sort = srt }
  | None -> { base with ret = None; ret_sort = None }

(* A block-level `fn n(ps) : ret do body end` ([A.ELetFn]) as the [A.fn_def]
   every piece of function-level machinery consumes — [sig_of_fn] for its
   callers' obligations, [check_fn_post_verdict] for its return refinement,
   [strip_param_refinements] when the local escapes.  One clause, no guard,
   no attributes: that is all the surface syntax of a local function admits.
   Both spans are the [ELetFn]'s own; a diagnostic about the local's return
   points at the whole definition, which is where the contract is written. *)
let local_fn_def (n : A.name) (ps : A.param list) (ret_ty : A.ty option) (body : A.expr)
    (sp : A.span) : A.fn_def =
  { A.fn_name = n; fn_vis = A.Private; fn_doc = None; fn_attrs = []; fn_ret_ty = ret_ty
  ; fn_clauses =
      [ { A.fc_params = List.map (fun p -> A.FPNamed p) ps; fc_guard = None; fc_body = body
        ; fc_span = sp; fc_params_span = sp } ]
  ; fn_bounds = [] }

(* Record the signature when EITHER side carries a refinement: a function with
   only a refined *return* must be resolvable so its postcondition reaches call
   sites, even though it has no refined params of its own to check. *)
let has_arrow_param (sg : fn_sig) : bool =
  List.exists (function Some (A.TyArrow _) -> true | _ -> false) sg.param_tys

(* …or a parameter whose CONTAINER type carries an element refinement
   (`xs : List({Int | _ > 0})`): [fn_sig.refined] is empty for it (the
   refinement is not outermost), but [Refine_check.check_arg_elements] needs
   the signature to file the element obligations, so it must be resolvable. *)
let has_elem_param (sg : fn_sig) : bool =
  List.exists (fun t -> elem_refinement t <> None) sg.param_tys

(* …and when a parameter is FUNCTION-typed (`apply(f : Int -> Int, x)`):
   such a signature carries no obligation of its own ([refined] is empty, so
   every consumer that iterates it does nothing), but the pass-site check in
   [Refine_check.visit] needs the arrow's domain to oblige whoever passes a
   refined callable there — see [fn_sig.param_tys]. *)
let entry_of_sig (sg : fn_sig) : fn_sig option =
  if sg.refined <> [] || Option.is_some sg.ret || has_arrow_param sg || has_elem_param sg
  then Some sg
  else None

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

(* ── Actor handler contracts ───────────────────────────────────────────────
   `on Inc(n : {Int | n > 0}) do ... end` declares a contract on the MESSAGE
   `Inc(...)`: the typechecker registers each handler's message as an ordinary
   constructor (`typecheck.ml`, the `DActor` arm of the env builder), so the
   single place every route to the handler passes through — `send`,
   `Actor.call`, a generated session endpoint, a message bound to a `let`
   first — is the construction `Inc(x)` itself.  That is where [visit]'s
   [ECon] arm files the obligation, against the signature built here.

   Message constructors are registered by BARE name, program-wide, last one
   wins.  So a name denotes one contract only when exactly one handler in the
   whole decl tree defines it and no `type` variant constructor shares it;
   any clash withdraws the name entirely — no caller obliged, and (see
   [Refine_check.visit_decl]'s `DActor` arm) no handler body assuming.
   Failing closed costs silence; failing open would check a user variant
   `Inc(-1)` against an unrelated actor's predicate, the one failure this
   subsystem must never have. *)
let collect_handler_sigs (decls : A.decl list) : (string, fn_sig) Hashtbl.t =
  let handlers : (string, fn_sig) Hashtbl.t = Hashtbl.create 16 in
  let count : (string, int) Hashtbl.t = Hashtbl.create 16 in
  let ctors : (string, unit) Hashtbl.t = Hashtbl.create 16 in
  let bump n = Hashtbl.replace count n (1 + Option.value ~default:0 (Hashtbl.find_opt count n)) in
  let rec go decls =
    List.iter
      (function
        | A.DActor (_, _, ad, _) ->
          List.iter
            (fun (h : A.actor_handler) ->
              bump h.A.ah_msg.A.txt;
              let fd =
                local_fn_def h.A.ah_msg h.A.ah_params None h.A.ah_body h.A.ah_msg.A.span
              in
              Hashtbl.replace handlers h.A.ah_msg.A.txt (sig_of_fn fd))
            ad.A.actor_handlers
        | A.DType (_, _, _, A.TDVariant vs, _) | A.DAlwaysLinearType (_, _, _, A.TDVariant vs, _) ->
          List.iter (fun (v : A.variant) -> Hashtbl.replace ctors v.A.var_name.A.txt ()) vs
        | A.DMod (_, _, ds, _) -> go ds
        | _ -> ())
      decls
  in
  go decls;
  let out = Hashtbl.create 16 in
  Hashtbl.iter
    (fun n sg ->
      if Hashtbl.find_opt count n = Some 1 && not (Hashtbl.mem ctors n) && sg.refined <> [] then
        Hashtbl.replace out n sg)
    handlers;
  out

(* ── Stored-field contracts ────────────────────────────────────────────────
   `type Box = { v : {Int | _ > 0} }`, `type W = W({Int | _ > 0})`, and an
   actor's `state { value : {Int | value >= 0} }` each declare a contract on a
   CONSTRUCTION: every record literal, `{ r with ... }` update, or constructor
   application that builds the value must establish the field's predicate,
   and every reader of a stored field may assume it.  The obligation side is
   phrased as a call to a synthesised "constructor signature" — one parameter
   per field, in declaration order, refined where the field is — so
   [check_call] does the work unchanged; the assumption side is
   [field_facts], pushed into the path context whenever a variable of that
   type enters scope ([recenv] is the trigger, since it already tracks
   exactly those variables).

   Keyed by the CONSTRUCTOR's bare name: a record's is its type name, an
   actor's its own name, a variant's the constructor's.  Fail closed on any
   clash — two constructors, or a constructor and an actor message, sharing
   a name withdraw the contract entirely (neither obliged nor assumed),
   exactly as [collect_handler_sigs] does. *)
let ctor_sig_of_fields (ctor : A.name) (fields : (string * A.ty) list) : fn_sig =
  (* A field's binder is normalised to `_`.  `value : {Int | value >= 0}` names
     its binder after the field itself, and inside [check_call] a binder that
     is also the parameter's name collides with the projected actual
     `state.value`: the obligation on `{ state with value: state.value }` came
     back undecided while the identical predicate over `_` proved.  The
     rewrite is exact — the binder is bound by the refinement, so renaming it
     changes nothing the predicate says — and keeps this contract on the path
     every other `_`-bound refinement already takes. *)
  let anon (t : A.ty) : A.ty =
    match unlinear t with
    | A.TyRefine (base, Some b, pred) ->
      A.TyRefine (base, None, subst_params [ (b.A.txt, A.EVar { A.txt = "_"; A.span = b.A.span }) ] pred)
    | t -> t
  in
  let ps =
    List.map
      (fun (n, t) ->
        A.FPNamed { A.param_name = { A.txt = n; A.span = ctor.A.span }; param_ty = Some (anon t)
                  ; param_lin = A.Unrestricted })
      fields
  in
  sig_of_clause
    { A.fc_params = ps; fc_guard = None; fc_body = A.ELit (A.LitBool true, ctor.A.span)
    ; fc_span = ctor.A.span; fc_params_span = ctor.A.span }

type ctor_sigs = {
  by_ctor : (string, fn_sig) Hashtbl.t;
      (* constructor name -> signature; only REFINED, unambiguous ones *)
  by_fields : (string list, string) Hashtbl.t;
      (* sorted field-name set -> the unique record/actor constructor with
         exactly those fields, for typing a bare literal `{ v: 0 }`; absent
         when two types share the shape (fail closed) *)
}

let collect_ctor_sigs (decls : A.decl list) : ctor_sigs =
  let all : (string, fn_sig) Hashtbl.t = Hashtbl.create 32 in
  let count : (string, int) Hashtbl.t = Hashtbl.create 32 in
  let shapes : (string list, string list) Hashtbl.t = Hashtbl.create 32 in
  let bump n = Hashtbl.replace count n (1 + Option.value ~default:0 (Hashtbl.find_opt count n)) in
  let add_record (name : A.name) (fields : A.field list) =
    bump name.A.txt;
    let fs = List.map (fun (f : A.field) -> (f.A.fld_name.A.txt, f.A.fld_ty)) fields in
    Hashtbl.replace all name.A.txt (ctor_sig_of_fields name fs);
    let key = List.sort compare (List.map fst fs) in
    Hashtbl.replace shapes key (name.A.txt :: Option.value ~default:[] (Hashtbl.find_opt shapes key))
  in
  let rec go decls =
    List.iter
      (function
        | A.DType (_, name, _, A.TDRecord fields, _)
        | A.DAlwaysLinearType (_, name, _, A.TDRecord fields, _) -> add_record name fields
        | A.DActor (_, name, ad, _) ->
          add_record name ad.A.actor_state;
          List.iter (fun (h : A.actor_handler) -> bump h.A.ah_msg.A.txt) ad.A.actor_handlers
        | A.DType (_, _, _, A.TDVariant vs, _) | A.DAlwaysLinearType (_, _, _, A.TDVariant vs, _) ->
          List.iter
            (fun (v : A.variant) ->
              bump v.A.var_name.A.txt;
              let fs = List.mapi (fun i t -> (Printf.sprintf "$%d" i, t)) v.A.var_args in
              Hashtbl.replace all v.A.var_name.A.txt (ctor_sig_of_fields v.A.var_name fs))
            vs
        | A.DMod (_, _, ds, _) -> go ds
        | _ -> ())
      decls
  in
  go decls;
  let by_ctor = Hashtbl.create 32 in
  Hashtbl.iter
    (fun n sg ->
      if Hashtbl.find_opt count n = Some 1 && sg.refined <> [] then Hashtbl.replace by_ctor n sg)
    all;
  let by_fields = Hashtbl.create 32 in
  Hashtbl.iter
    (fun key names -> match names with [ n ] -> Hashtbl.replace by_fields key n | _ -> ())
    shapes;
  { by_ctor; by_fields }

(* The facts a variable [x] of a refined record/actor type contributes:
   each refined field's predicate with the binder replaced by `x.field`,
   which the path translator reflects through the sort's selector
   ([path_resolve_field]).  Pushed as ordinary path facts, so the shadow
   discipline that retires a fact when [x] is rebound applies unchanged. *)
let field_facts (x : string) ~(span : A.span) (sg : fn_sig) : (A.expr * bool) list =
  List.map
    (fun rp ->
      let fname = List.nth sg.param_names rp.idx in
      let proj = A.EField (A.EVar { A.txt = x; A.span = span }, { A.txt = fname; A.span = span }, span) in
      (* Both spellings of the subject: the binder (`_`, or a declared one),
         AND the field's own name used free — `value : {Int | value >= 0}`
         has binder [None] and refers to `value` exactly as `k : {Int | k >
         0}` refers to its parameter, which [check_call] resolves through
         [param_names]; a fact built here must resolve it the same way or
         it mentions an unbound `value` and is silently dropped. *)
      (subst_params [ (rp.binder, proj); (fname, proj) ] rp.pred, false))
    sg.refined

(* The constructor a [recenv] sort name denotes, when it is a record/actor. *)
let ctor_of_sort (sort : string) : string option =
  match Hashtbl.find_opt adt_ctors sort with
  | Some [ ctor ] when Hashtbl.mem ctor_field_names ctor -> Some ctor
  | _ -> None

(* ── `impl` method contracts, by receiver type ─────────────────────────────
   [collect_all_defs] adopts an `impl` method's contract only when its bare
   name denotes ONE definition.  When it does not — two impls of `at`, or a
   `fn at` beside one — a call `at(Crate(0), -1)` resolves to nothing and no
   caller is obliged.  The call still has exactly one target at runtime: the
   impl for the FIRST argument's type, which is the rule compilation applies
   (`Lower_state.resolve_iface_method`).  This table holds every impl
   method's signature keyed by bare method name, then by the impl's bare type
   name, so [Refine_check.visit] can make that same choice from the
   typechecker's [type_map] (plan phase 5).  Only refined signatures are
   kept; an impl whose type is not a plain constructor (a tuple, a type
   variable) is not indexed, since nothing dispatches on it by name. *)
let collect_impl_sigs (decls : A.decl list) : (string, (string * fn_sig) list) Hashtbl.t =
  let tbl : (string, (string * fn_sig) list) Hashtbl.t = Hashtbl.create 16 in
  let bare n = match String.rindex_opt n '.' with Some i -> String.sub n (i + 1) (String.length n - i - 1) | None -> n in
  let rec go decls =
    List.iter
      (function
        | A.DImpl (idf, _) ->
          (match idf.A.impl_ty with
           | A.TyCon (tn, _) ->
             List.iter
               (fun ((mn : A.name), (fd : A.fn_def)) ->
                 let sg = sig_of_fn fd in
                 if sg.refined <> [] then
                   Hashtbl.replace tbl mn.A.txt
                     ((bare tn.A.txt, sg) :: Option.value ~default:[] (Hashtbl.find_opt tbl mn.A.txt)))
               idf.A.impl_methods
           | _ -> ())
        | A.DMod (_, _, ds, _) -> go ds
        | _ -> ())
      decls
  in
  go decls;
  tbl

(* Erase parameter refinements from [fd], leaving the return refinement alone.
   A stripped parameter contributes no fact to [scope], so a body checked with
   it can discharge nothing from a predicate no caller was obliged to
   establish.  The return refinement is CHECKED rather than assumed, so it
   stays: dropping it would lose a real check, and checking it against the
   original (unstripped) parameters is what [visit_fn] keeps doing. *)
let strip_param_refinement (p : A.param) : A.param =
  let rec strip = function
    | A.TyRefine (t, _, _) -> strip t
    | A.TyLinear (l, t) -> A.TyLinear (l, strip t)
    | t -> t
  in
  { p with A.param_ty = Option.map strip p.A.param_ty }

(* The same erasure over a bare [A.param list] — a lambda's or an actor
   handler's parameters, which carry no [fn_def].  Used by [visit] for exactly
   the reason [strip_param_refinements] exists: until every construction of a
   call through that binder is obliged (see
   specs/plans/2026-09-13-refinement-enforcement-holes-plan.md), a refinement
   declared there is assume-without-check, and `cap verified` accepted
   `need(0)` through `let g = fn (n : {Int | n > 0}) -> need(n)  g(0)`. *)
let strip_params_refinements (ps : A.param list) : A.param list =
  List.map strip_param_refinement ps

let strip_param_refinements (fd : A.fn_def) : A.fn_def =
  let param = strip_param_refinement in
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

