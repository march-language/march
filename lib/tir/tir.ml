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
[@@deriving show]

type linearity = Lin | Aff | Unr
[@@deriving show]

(** A variable with its type and linearity annotation. *)
type var = {
  v_name : string;
  v_ty   : ty;
  v_lin  : linearity;
}
[@@deriving show]

(** A top-level definition identity: human-readable name + content hash.
    The hash is the primary key; the name is for diagnostics only.
    Produced by content-addressed lowering (Phase 5 of content-addressing). *)
type def_id = {
  did_name : string;   (** human-readable, for diagnostics *)
  did_hash : string;   (** 64-char BLAKE3 hex impl_hash *)
}
[@@deriving show]

(** Atoms — values that require no computation. *)
type atom =
  | AVar    of var
  | ADefRef of def_id   (** reference to a top-level definition by content hash *)
  | ALit    of March_ast.Ast.literal
[@@deriving show]

(** ANF expressions. *)
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
[@@deriving show]

(** A case branch: constructor tag + bound variables → body. *)
and branch = {
  br_tag  : string;           (* constructor name *)
  br_vars : var list;          (* bound variables for constructor args *)
  br_body : expr;
}
[@@deriving show]

(** A function definition. *)
and fn_def = {
  fn_name   : string;
  fn_params : var list;
  fn_ret_ty : ty;
  fn_body   : expr;
}
[@@deriving show]

(** Top-level type definitions. *)
type type_def =
  | TDVariant of string * (string * ty list) list   (* name, [(ctor, arg types)] *)
  | TDRecord  of string * (string * ty) list        (* name, [(field, ty)] *)
  | TDClosure of string * ty list                   (* defun closure struct *)
[@@deriving show]

(** An extern (FFI) function declaration. *)
type extern_decl = {
  ed_march_name : string;     (* name as used in March source *)
  ed_c_name     : string;     (* C symbol name *)
  ed_params     : ty list;    (* parameter types *)
  ed_ret        : ty;         (* return type *)
}
[@@deriving show]

(** A TIR module. *)
type tir_module = {
  tm_name    : string;
  tm_fns     : fn_def list;
  tm_types   : type_def list;
  tm_externs : extern_decl list;
  tm_exports : string list;  (** Extra root function names to keep alive during DCE.
                                 Used for WASM island exports (render, update, init). *)
}
[@@deriving show]
