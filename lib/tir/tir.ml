(** March TIR — Typed Intermediate Representation.

    ANF-based IR between the type checker and LLVM emission.
    All function arguments are atoms (variables or literals).
    Every binding carries an explicit type and linearity annotation. *)

(** Monomorphic types. After monomorphization no type variables remain.
    Pre-mono, [TVar] may still appear as a placeholder. *)
type ty =
  | TInt | TFloat | TBool | TString | TUnit
  | TTuple  of ty list
  | TRecord of (string * ty) list          (* sorted by field name *)
  | TCon    of string * ty list            (* monomorphic named type *)
  | TFn     of ty list * ty               (* closure struct after defun *)
  | TPtr    of ty                          (* raw heap pointer, FFI only *)
  | TVar    of string                      (* pre-mono type variable placeholder *)
type linearity = Lin | Aff | Unr

(* A variable with its type and linearity annotation. *)
type var = {
  v_name : string;
  v_ty   : ty;
  v_lin  : linearity;
}

(* A top-level definition identity: human-readable name + content hash.
   The hash is the primary key; the name is for diagnostics only. *)
type def_id = {
  did_name : string;   (* human-readable, for diagnostics *)
  did_hash : string;   (* 64-char BLAKE3 hex impl_hash *)
}

(* Atoms — values that require no computation. *)
type atom =
  | AVar    of var
  | ADefRef of def_id   (* reference to a top-level definition by content hash *)
  | ALit    of March_ast.Ast.literal

(* ANF expressions. *)
type expr =
  | EAtom    of atom
  | EApp     of var * atom list                   (* known function call *)
  | ECallPtr of atom * atom list                  (* indirect call via closure dispatch *)
  | ELet     of var * expr * expr                 (* let x : T = e1 in e2 *)
  | ELetRec  of fn_def list * expr                (* mutually recursive functions *)
  | ECase    of atom * branch list * expr option  (* case scrutinee, branches, default *)
  | ETuple   of atom list
  | ERecord  of (string * atom) list
  | EField   of atom * string                     (* record projection *)
  | EUpdate  of atom * (string * atom) list       (* record functional update *)
  | EAlloc      of ty * atom list                 (* heap-allocate a constructor *)
  | EStackAlloc of ty * atom list                 (* stack-allocate — inserted by Escape analysis *)
  | EFree    of atom                              (* explicit dealloc — inserted by Perceus *)
  | EIncRC   of atom                              (* non-atomic RC increment — local values only *)
  | EDecRC   of atom                              (* non-atomic RC decrement — local values only *)
  | EAtomicIncRC of atom                          (* atomic RC increment — actor-shared values *)
  | EAtomicDecRC of atom                          (* atomic RC decrement — actor-shared values *)
  | EReuse   of atom * ty * atom list             (* FBIP reuse — inserted by Perceus *)
  | ESeq     of expr * expr                       (* sequence, first result discarded *)

(* A case branch: constructor tag + bound variables → body. *)
and branch = {
  br_tag  : string;           (* constructor name *)
  br_vars : var list;          (* bound variables for constructor args *)
  br_body : expr;
}

(* The synthesis role of a [fn_def] — WHY it exists, set honestly by its
   producer (Wave 3 Task 3; see specs/plans/2026-07-03-wave3-chunk1-refactors.md).
   Before this field, several consumers (borrow.ml, perceus.ml, llvm_emit.ml)
   answered "is this fn synthetic / an apply wrapper / etc.?" by re-deriving
   the answer from [fn_name] (magic substrings like "$apply$") — the same
   name-sniffing drift class Tir_names (W3.1) centralized for OTHER kinds of
   names. [fn_kind] gives those consumers a field to check directly instead.

   NOTE: this list intentionally does NOT include a "try-call thunk" variant.
   [__try_call]/[__try_call_val] (see [Tir_names.is_try_call]) are ordinary
   builtin call targets; the lambda passed as their thunk argument is
   synthesized by [lower.ml] exactly like any other lambda ([FnLambda]) — the
   "try-call-ness" is a property of the *call site* (borrow.ml's
   [closure_escapes]/[owned_in] check the CALLEE name, not the thunk's
   fn_def), not of the thunk's own fn_def. Inventing a kind with no producer
   would violate the "adapt to what synthesis sites actually distinguish"
   rule, so there is no [FnTryThunk] here. *)
and fn_kind =
  | FnNormal     (* parsed user/stdlib fn, iface-method shim, module-level
                     `let`-as-zero-arg-fn, actor handler/dispatch/spawn glue —
                     anything not synthesized as one of the roles below *)
  | FnLambda     (* body of an `ELam`/named-local-recursive-fn (`ELetFn`), as
                     lowered by lower.ml into the ELetRec([fn], AVar fn) lambda-
                     creation pattern.  Always consumed by Defun before Perceus
                     runs — defun.ml's [lift_lambda] builds a brand-new
                     [FnApply] fn_def from it, so no [FnLambda]-tagged fn_def
                     survives to reach borrow.ml/perceus.ml/llvm_emit.ml. Set
                     honestly anyway: the field must be meaningful at every
                     construction site, and it documents defun's consuming
                     role precisely. *)
  | FnJoinPoint  (* the hoisted-fallback join point minted by lower.ml's
                     [compile_matrix] (non-atomic match `fallback`, `jp_fn`) —
                     structurally the same ELetRec([fn], AVar fn) shape as
                     [FnLambda] (so it goes through the identical defun lift
                     into [FnApply]), but the ROLE differs: it exists to dedupe
                     a shared match fallback, not to represent user code. *)
  | FnApply      (* the closure "apply wrapper" lifted by defun.ml's
                     [lift_lambda] for EVERY defunctionalized lambda/local-fn/
                     join-point ([Tir_names.apply_fn_name], "<fn>$apply$<uid>").
                     This is the kind [Tir_names.is_apply_fn] / the former
                     perceus.ml and llvm_emit.ml name-sniffing copies existed
                     to detect — see those call sites' transitional asserts. *)
  | FnFused      (* a whole-loop fusion helper synthesized by fusion.ml
                     ([gen_map_fold]/[gen_filter_fold]/[gen_map_filter_fold],
                     gensym "mf"/"ff"/"mff") — a new self-recursive top-level
                     fn, not a lifted lambda.  No consumer currently sniffs
                     these names (grep-verified against lib/tir at task time),
                     so this kind exists purely for honest labeling; it is not
                     (yet) load-bearing for any RC/codegen decision. *)

(* A function definition. *)
and fn_def = {
  fn_name   : string;
  fn_params : var list;
  fn_ret_ty : ty;
  fn_body   : expr;
  fn_kind   : fn_kind;
  (* Role flag (Wave 3 Task 3). Deliberately OMITTED from [show_fn_def] below
     and from [Pp.string_of_fn_def] (lib/tir/pp.ml) this chunk — printing it
     would churn every TIR snapshot for a purely additive field. See
     specs/plans/2026-07-03-wave3-chunk1-refactors.md Task 3 "printer
     caveat". *)
}

(* Top-level type definitions. *)
type type_def =
  | TDVariant of string * (string * ty list) list   (* name, [(ctor, arg types)] *)
  | TDRecord  of string * (string * ty) list        (* name, [(field, ty)] *)
  | TDClosure of string * ty list                   (* defun closure struct *)

(* An extern (FFI) function declaration. *)
type extern_decl = {
  ed_march_name : string;     (* name as used in March source *)
  ed_c_name     : string;     (* C symbol name *)
  ed_lib_name   : string;     (* library / JS module specifier from `extern "..."` *)
  ed_js_sym     : string;     (* JS export name: explicit @"sym" or march name (no lib_ prefix) *)
  ed_params     : ty list;    (* parameter types *)
  ed_consumed   : bool list;  (* per-param: true if `consume` (ownership to callee) *)
  ed_blocking   : bool;       (* `blocking`: dispatch on an OS thread, yield the green thread *)
  ed_raises     : bool;       (* `raises`: env-routed errors (march_env* + bare Ok payload) *)
  ed_ret        : ty;         (* return type *)
}

(* A TIR module. *)
type tir_module = {
  tm_name    : string;
  tm_fns     : fn_def list;
  tm_types   : type_def list;
  tm_externs : extern_decl list;
  tm_exports : string list;  (* extra root function names to keep alive during DCE *)
  tm_tests   : (string * string) list;
  (* (fn_name, display_name) pairs for --test mode *)
  tm_io_fns  : string list;
  (** Names of modules that require Cap(IO), extracted from typecheck env.
      Used by policy_dce's NoIO check. Empty in pre-policy builds. *)
}

(* ── Hand-written show functions — used for content-addressed fingerprinting ── *)

let rec show_ty = function
  | TInt -> "TInt" | TFloat -> "TFloat" | TBool -> "TBool"
  | TString -> "TString" | TUnit -> "TUnit"
  | TTuple ts -> Printf.sprintf "TTuple[%s]" (String.concat "," (List.map show_ty ts))
  | TRecord fs -> Printf.sprintf "TRecord{%s}" (String.concat "," (List.map (fun (n,t) -> n^":"^show_ty t) fs))
  | TCon (n, ts) -> Printf.sprintf "TCon(%s,[%s])" n (String.concat "," (List.map show_ty ts))
  | TFn (ps, r) -> Printf.sprintf "TFn([%s],%s)" (String.concat "," (List.map show_ty ps)) (show_ty r)
  | TPtr t -> "TPtr(" ^ show_ty t ^ ")"
  | TVar s -> "TVar(" ^ s ^ ")"

let show_linearity = function Lin -> "Lin" | Aff -> "Aff" | Unr -> "Unr"

let show_var v = v.v_name ^ ":" ^ show_ty v.v_ty ^ "/" ^ show_linearity v.v_lin

let show_atom = function
  | AVar v -> "AVar(" ^ show_var v ^ ")"
  | ADefRef d -> "ADefRef(" ^ d.did_hash ^ ")"
  | ALit l -> "ALit(" ^ March_ast.Ast.show_literal l ^ ")"

let rec show_expr = function
  | EAtom a -> "EAtom(" ^ show_atom a ^ ")"
  | EApp (v, args) ->
    Printf.sprintf "EApp(%s,[%s])" (show_var v) (String.concat "," (List.map show_atom args))
  | ECallPtr (f, args) ->
    Printf.sprintf "ECallPtr(%s,[%s])" (show_atom f) (String.concat "," (List.map show_atom args))
  | ELet (v, e1, e2) ->
    Printf.sprintf "ELet(%s,%s,%s)" (show_var v) (show_expr e1) (show_expr e2)
  | ELetRec (fns, body) ->
    Printf.sprintf "ELetRec([%s],%s)" (String.concat "," (List.map show_fn_def fns)) (show_expr body)
  | ECase (a, brs, def) ->
    Printf.sprintf "ECase(%s,[%s],%s)" (show_atom a)
      (String.concat "," (List.map show_branch brs))
      (match def with None -> "None" | Some e -> "Some(" ^ show_expr e ^ ")")
  | ETuple atoms -> Printf.sprintf "ETuple[%s]" (String.concat "," (List.map show_atom atoms))
  | ERecord fields ->
    Printf.sprintf "ERecord{%s}" (String.concat "," (List.map (fun (n,a) -> n^"="^show_atom a) fields))
  | EField (a, f) -> Printf.sprintf "EField(%s,%s)" (show_atom a) f
  | EUpdate (a, fields) ->
    Printf.sprintf "EUpdate(%s,{%s})" (show_atom a)
      (String.concat "," (List.map (fun (n,v) -> n^"="^show_atom v) fields))
  | EAlloc (t, args) ->
    Printf.sprintf "EAlloc(%s,[%s])" (show_ty t) (String.concat "," (List.map show_atom args))
  | EStackAlloc (t, args) ->
    Printf.sprintf "EStackAlloc(%s,[%s])" (show_ty t) (String.concat "," (List.map show_atom args))
  | EFree a -> "EFree(" ^ show_atom a ^ ")"
  | EIncRC a -> "EIncRC(" ^ show_atom a ^ ")"
  | EDecRC a -> "EDecRC(" ^ show_atom a ^ ")"
  | EAtomicIncRC a -> "EAtomicIncRC(" ^ show_atom a ^ ")"
  | EAtomicDecRC a -> "EAtomicDecRC(" ^ show_atom a ^ ")"
  | EReuse (a, t, args) ->
    Printf.sprintf "EReuse(%s,%s,[%s])" (show_atom a) (show_ty t)
      (String.concat "," (List.map show_atom args))
  | ESeq (e1, e2) -> Printf.sprintf "ESeq(%s,%s)" (show_expr e1) (show_expr e2)

and show_branch br =
  Printf.sprintf "Br(%s,[%s],%s)" br.br_tag
    (String.concat "," (List.map show_var br.br_vars))
    (show_expr br.br_body)

and show_fn_def fn =
  Printf.sprintf "Fn(%s,[%s],%s,%s)" fn.fn_name
    (String.concat "," (List.map show_var fn.fn_params))
    (show_ty fn.fn_ret_ty)
    (show_expr fn.fn_body)