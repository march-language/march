(** Constant folding pass.
    Evaluates pure expressions whose operands are all literals.
    Sets [~changed] on any rewrite. *)

let int_ops = ["+"; "-"; "*"; "/"; "%"]
let float_ops = ["+."; "-."; "*."; "/."]

(* OCaml's [int] is March's 63-bit Int, so these are the runtime's overflow
   tests.  An overflowing `+ - *` is left unfolded: it panics at run time
   (specs/lang/type-system.md, "Int width and overflow"). *)
let fold_int_op op a b =
  match op with
  | "+" -> let r = a + b in
    if (a >= 0) = (b >= 0) && (r >= 0) <> (a >= 0) then None else Some r
  | "-" -> let r = a - b in
    if (a >= 0) <> (b >= 0) && (r >= 0) <> (a >= 0) then None else Some r
  | "*" -> let r = a * b in
    if a <> 0 && (r / a <> b || (a = -1 && b = min_int) || (b = -1 && a = min_int))
    then None else Some r
  | "/" -> if b = 0 then None else Some (a / b)
  | "%" -> if b = 0 then None else Some (a mod b)
  | _   -> None

let fold_float_op op a b =
  match op with
  | "+." -> Some (a +. b)
  | "-." -> Some (a -. b)
  | "*." -> Some (a *. b)
  | "/." -> Some (a /. b)
  | _    -> None

let mk_int n = Tir.EAtom (Tir.ALit (March_ast.Ast.LitInt n))
let mk_float f = Tir.EAtom (Tir.ALit (March_ast.Ast.LitFloat f))
let mk_bool b = Tir.EAtom (Tir.ALit (March_ast.Ast.LitBool b))
let mk_string s = Tir.EAtom (Tir.ALit (March_ast.Ast.LitString s))

(* True when the module defines a top-level fn named `not`.  A user fn owns
   that name (an entry-module fn may shadow a builtin: see
   lib/modules/prelude_collision.ml; llvm_emit's [shadows_dispatched_builtin]
   and js_emit's [shadows_js_builtin] route its call sites to it), so a call
   `not(x)` in the TIR is THAT fn: folding `not(<literal>)` by name skips it,
   and rewriting `x == false` to `not x` would call it (#1177).  The same
   tm_fns membership the backends test. *)
let has_user_not (m : Tir.tir_module) =
  List.exists (fun (fd : Tir.fn_def) -> fd.Tir.fn_name = "not") m.Tir.tm_fns

let rec fold_expr ~user_not ~changed : Tir.expr -> Tir.expr = function
  (* Integer arithmetic on two literals *)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitInt a); Tir.ALit (March_ast.Ast.LitInt b)])
    when List.mem f.Tir.v_name int_ops ->
    (match fold_int_op f.Tir.v_name a b with
     | Some n -> changed := true; mk_int n
     | None   -> Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitInt a); Tir.ALit (March_ast.Ast.LitInt b)]))

  (* Float arithmetic on two literals *)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitFloat a); Tir.ALit (March_ast.Ast.LitFloat b)])
    when List.mem f.Tir.v_name float_ops ->
    (match fold_float_op f.Tir.v_name a b with
     | Some v -> changed := true; mk_float v
     | None   -> Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitFloat a); Tir.ALit (March_ast.Ast.LitFloat b)]))

  (* not <bool_literal> *)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitBool b)])
    when f.Tir.v_name = "not" && not user_not ->
    changed := true; mk_bool (not b)

  (* false && rhs → false
     Safe to drop rhs: in ANF all EApp args are atoms, and atom evaluation is always pure. *)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitBool false); _rhs])
    when f.Tir.v_name = "&&" ->
    changed := true; mk_bool false

  (* true || rhs → true (same reasoning) *)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitBool true); _rhs])
    when f.Tir.v_name = "||" ->
    changed := true; mk_bool true

  (* if true -> then branch; if false -> else branch *)
  | Tir.ECase (Tir.ALit (March_ast.Ast.LitBool true),
               [{ Tir.br_tag; br_body; _ }], _)
    when br_tag = Tir_names.synthetic_true_tag ->
    changed := true; fold_expr ~user_not ~changed br_body

  | Tir.ECase (Tir.ALit (March_ast.Ast.LitBool false),
               [{ Tir.br_tag; _ }], Some else_e)
    when br_tag = Tir_names.synthetic_true_tag ->
    changed := true; fold_expr ~user_not ~changed else_e

  (* ECase with LitBool false scrutinee and no default — unreachable in practice
     (March lowering always emits a default branch for if/else), fall through to recurse *)

  (* String concatenation: "a" ++ "b" → "ab" *)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitString a); Tir.ALit (March_ast.Ast.LitString b)])
    when f.Tir.v_name = "++" || f.Tir.v_name = "string_concat" ->
    changed := true; mk_string (a ^ b)

  (* string_byte_length("...") → n *)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitString s)])
    when f.Tir.v_name = "string_byte_length" || f.Tir.v_name = "string_length" ->
    changed := true; mk_int (String.length s)

  (* string_is_empty("...") → bool *)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitString s)])
    when f.Tir.v_name = "string_is_empty" ->
    changed := true; mk_bool (String.length s = 0)

  (* Pure NUMERIC-RESULT builtins on literal args → the literal result.
     Semantics mirror lib/eval/eval.ml exactly (verified equal to the runtime C
     in runtime/march_runtime.c): int_abs=abs, int_to_float=float_of_int,
     float_abs=fabs, float_{floor,ceil}=(int)(floor|ceil), float_round=(int)round
     (half away from zero, both OCaml Float.round and C round), float_truncate=
     (int)f (toward zero).  Deliberately NOT folding STRING-producing builtins
     (int_to_string/float_to_string/bool_to_string) — their exact formatting
     must stay owned by the per-backend formatters (see the 5 float→string
     formatters, memory float_to_string_backends) rather than duplicated here. *)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitInt a)])
    when f.Tir.v_name = "int_abs" && a <> min_int ->
    changed := true; mk_int (abs a)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitInt a)])
    when f.Tir.v_name = "int_to_float" ->
    changed := true; mk_float (float_of_int a)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitFloat a)])
    when f.Tir.v_name = "float_abs" ->
    changed := true; mk_float (Float.abs a)
  (* float→int: guard finite + safely in 63-bit int range so the OCaml-side
     conversion can't overflow/UB where the C (int64_t) cast would differ. *)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitFloat a)])
    when Float.is_finite a && Float.abs a < 4.6e18
         && (match f.Tir.v_name with
             | "float_floor" | "float_ceil" | "float_round" | "float_truncate" -> true
             | _ -> false) ->
    let r = match f.Tir.v_name with
      | "float_floor"    -> int_of_float (floor a)
      | "float_ceil"     -> int_of_float (ceil a)
      | "float_round"    -> Float.to_int (Float.round a)
      | "float_truncate" -> Float.to_int a
      | _                -> 0
    in
    changed := true; mk_int r

  (* Boolean comparison identities — arise after inlining guard / predicate functions.
     x == true  →  x
     x == false →  not x  (new let needed for ANF; use simplified form via EApp)
     true == x  →  x
     false == x →  not x  *)
  | Tir.EApp (f, [x; Tir.ALit (March_ast.Ast.LitBool true)])
    when f.Tir.v_name = "==" ->
    changed := true; Tir.EAtom x
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitBool true); x])
    when f.Tir.v_name = "==" ->
    changed := true; Tir.EAtom x
  | Tir.EApp (f, [x; Tir.ALit (March_ast.Ast.LitBool false)])
    when f.Tir.v_name = "==" && not user_not ->
    let not_v = { Tir.v_name = "not"; v_ty = Tir.TFn ([Tir.TBool], Tir.TBool); v_lin = Tir.Unr } in
    changed := true; Tir.EApp (not_v, [x])
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitBool false); x])
    when f.Tir.v_name = "==" && not user_not ->
    let not_v = { Tir.v_name = "not"; v_ty = Tir.TFn ([Tir.TBool], Tir.TBool); v_lin = Tir.Unr } in
    changed := true; Tir.EApp (not_v, [x])

  (* Integer comparison with known constant: int_op(lit_a, lit_b) → bool *)
  | Tir.EApp (f, [Tir.ALit (March_ast.Ast.LitInt a); Tir.ALit (March_ast.Ast.LitInt b)])
    when (match f.Tir.v_name with "<" | "<=" | ">" | ">=" | "==" | "!=" -> true | _ -> false) ->
    changed := true;
    let result = match f.Tir.v_name with
      | "<"  -> a < b   | "<=" -> a <= b
      | ">"  -> a > b   | ">=" -> a >= b
      | "==" -> a = b   | "!=" -> a <> b
      | _    -> false
    in mk_bool result

  (* Recurse into all other nodes *)
  | Tir.ELet (v, rhs, body) ->
    Tir.ELet (v, fold_expr ~user_not ~changed rhs, fold_expr ~user_not ~changed body)
  | Tir.ECase (a, branches, default) ->
    let branches' = List.map (fun b ->
      { b with Tir.br_body = fold_expr ~user_not ~changed b.Tir.br_body }) branches in
    let default' = Option.map (fold_expr ~user_not ~changed) default in
    Tir.ECase (a, branches', default')
  | Tir.ELetRec (fns, body) ->
    let fns' = List.map (fun fd ->
      { fd with Tir.fn_body = fold_expr ~user_not ~changed fd.Tir.fn_body }) fns in
    Tir.ELetRec (fns', fold_expr ~user_not ~changed body)
  | Tir.ESeq (e1, e2) ->
    Tir.ESeq (fold_expr ~user_not ~changed e1, fold_expr ~user_not ~changed e2)
  | other -> other

let run_fn ?(user_not = false) ~changed fd =
  { fd with Tir.fn_body = fold_expr ~user_not ~changed fd.Tir.fn_body }

let run ~changed (m : Tir.tir_module) : Tir.tir_module =
  let user_not = has_user_not m in
  { m with Tir.tm_fns = List.map (run_fn ~user_not ~changed) m.Tir.tm_fns }
