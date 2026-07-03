(** AST/typechecker type → TIR type conversion (Wave 3 Task 9: split out of
    [Lower]).

    Houses BOTH type converters side by side, moved verbatim from lower.ml.
    They deliberately disagree on two encodings — this is a FILED bug (see
    specs/analysis/2026-07-01-pipeline-deep-review.md, "lower.ml" section,
    High finding #4: "[lower_ty] vs [convert_ty] disagree"), not something
    this split may fix:
      - Arrow types: [lower_ty] curries a single-arg [Ast.TyArrow(a,b)] into
        [Tir.TFn([a], b)] (never uncurries multi-arg chains); [convert_ty]
        walks a [Typecheck.TArrow] chain and uncurries into [Tir.TFn(params,
        ret)]. A function whose TIR type came from the annotation path and
        one whose type came from the type_map path can therefore disagree on
        arity/shape for the same surface type.
      - [Nat n] types: [lower_ty] encodes [Ast.TyNat n] as
        [TCon("Nat", [TCon(string_of_int n, [])])]; [convert_ty] encodes
        [Typecheck.TNat n] as [TCon(Printf.sprintf "Nat_%d" n, [])]. These two
        TCon shapes can never unify in monomorphization.
    See each function's doc comment below for the cross-reference back to
    this note. Unifying the two converters is explicitly OUT OF SCOPE for
    this split (would be a behavior change); only the move is in scope. *)

module Ast = March_ast.Ast
module Typecheck = March_typecheck.Typecheck

(** Default type used when no annotation is available. A placeholder
    that will be resolved during monomorphization. *)
let unknown_ty = Tir.TVar "_"

(** Convert surface types to TIR types.
    Pre-monomorphization, type variables become [TVar].

    See this file's module doc: disagrees with [convert_ty] below on
    [TyArrow] currying and [TyNat] encoding (filed bug, analysis doc lower.ml
    High #4) — do not unify the two. *)
let rec lower_ty (t : Ast.ty) : Tir.ty =
  match t with
  | Ast.TyCon ({ txt = "Int"; _ }, [])    -> Tir.TInt
  | Ast.TyCon ({ txt = "Float"; _ }, [])  -> Tir.TFloat
  | Ast.TyCon ({ txt = "Bool"; _ }, [])   -> Tir.TBool
  | Ast.TyCon ({ txt = "String"; _ }, []) -> Tir.TString
  | Ast.TyCon ({ txt = "Unit"; _ }, [])   -> Tir.TUnit
  | Ast.TyCon ({ txt = name; _ }, args)   ->
    Tir.TCon (name, List.map lower_ty args)
  | Ast.TyVar { txt = name; _ }          -> Tir.TVar name
  | Ast.TyArrow (a, b)                   -> Tir.TFn ([lower_ty a], lower_ty b)
  | Ast.TyTuple ts                        -> Tir.TTuple (List.map lower_ty ts)
  | Ast.TyRecord fields                   ->
    let fs = List.map (fun (n, t) -> (n.Ast.txt, lower_ty t)) fields in
    Tir.TRecord (List.sort (fun (a, _) (b, _) -> String.compare a b) fs)
  | Ast.TyLinear (_, t)                   -> lower_ty t  (* linearity tracked on var *)
  | Ast.TyNat n                           -> Tir.TCon ("Nat", [Tir.TCon (string_of_int n, [])])
  | Ast.TyNatOp _                         -> Tir.TCon ("NatOp", [])  (* placeholder *)
  | Ast.TyChan _                          -> Tir.TCon ("Chan", [])   (* lowered to opaque Chan ptr *)
  | Ast.TyRefine (base, _, _)             -> lower_ty base  (* refinement erases to base in TIR *)

(** Convert AST linearity to TIR linearity. *)
let lower_linearity : Ast.linearity -> Tir.linearity = function
  | Ast.Linear       -> Tir.Lin
  | Ast.Affine       -> Tir.Aff
  | Ast.Unrestricted -> Tir.Unr

(** Convert an internal typechecker type to a TIR type.
    [Typecheck.TArrow] is curried; we uncurry into [Tir.TFn].

    See this file's module doc: disagrees with [lower_ty] above on
    [TyArrow]/[TArrow] currying and [TyNat]/[TNat] encoding (filed bug,
    analysis doc lower.ml High #4) — do not unify the two. *)
let rec convert_ty (t : Typecheck.ty) : Tir.ty =
  match Typecheck.repr t with
  | Typecheck.TCon ("Int",    []) -> Tir.TInt
  | Typecheck.TCon ("Float",  []) -> Tir.TFloat
  | Typecheck.TCon ("Bool",   []) -> Tir.TBool
  | Typecheck.TCon ("String", []) -> Tir.TString
  | Typecheck.TCon ("Unit",   []) -> Tir.TUnit
  | Typecheck.TCon (name, args)   -> Tir.TCon (name, List.map convert_ty args)
  | Typecheck.TArrow _ as t ->
    let rec collect acc = function
      | Typecheck.TArrow (a, b) -> collect (convert_ty a :: acc) (Typecheck.repr b)
      | ret -> (List.rev acc, convert_ty ret)
    in
    let (params, ret) = collect [] t in
    Tir.TFn (params, ret)
  | Typecheck.TTuple tys ->
    Tir.TTuple (List.map convert_ty tys)
  | Typecheck.TRecord fields ->
    Tir.TRecord (List.map (fun (n, t) -> (n, convert_ty t)) fields)
  | Typecheck.TVar r ->
    (match !r with
     | Typecheck.Unbound (id, _) -> Tir.TVar (Printf.sprintf "_%d" id)
     | Typecheck.Link _ -> assert false)
  | Typecheck.TLin (_, inner) -> convert_ty inner
  | Typecheck.TNat n          -> Tir.TCon (Printf.sprintf "Nat_%d" n, [])
  | Typecheck.TNatOp _        -> Tir.TVar "_natop"
  | Typecheck.TChan _         -> Tir.TCon ("Chan", [])  (* lowered to opaque Chan ptr *)
  | Typecheck.TError          -> Tir.TVar "_err"
  | Typecheck.TRefine (base, _, _) -> convert_ty base  (* refinements erase in TIR *)
