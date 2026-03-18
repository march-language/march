# TIR (Typed Intermediate Representation) Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the TIR layer (`lib/tir/`) that lowers the desugared AST into A-normal form with explicit types and linearity annotations, as the foundation for monomorphization, defunctionalization, and Perceus RC.

**Architecture:** The TIR is an ANF IR where all function arguments are atoms (variables or literals), all intermediate results are named via `ELet`, and every binding carries a monomorphic type and linearity annotation. The initial implementation covers: (1) TIR type definitions in `tir.ml`, (2) AST→TIR lowering in `lower.ml` that converts expressions to ANF using continuation-passing style for let-insertion, and flattens nested patterns into nested `ECase`. Later passes (mono, defun, perceus) build on this foundation but are out of scope for this plan.

**Tech Stack:** OCaml 5.3.0, dune 3.0, menhir, alcotest, ppx_deriving

---

## File Structure

```
lib/tir/
├── dune         # Library definition: march_tir, depends on march_ast
├── tir.ml       # TIR type definitions: ty, linearity, var, atom, expr, fn_def, tir_module, type_def
├── lower.ml     # AST→TIR lowering: ANF conversion, pattern flattening, block→ELet chains
└── pp.ml        # Pretty-printer for TIR (debugging/test assertions)
```

**Responsibilities:**
- `tir.ml` — Pure type definitions. No logic. Every binding has a type and linearity. Matches the spec in `specs/tir.md` with one exception: types may still contain `TVar` placeholders pre-monomorphization.
- `lower.ml` — Structural translation from `Ast.module_` → `Tir.tir_module`. Key transformations: expressions→ANF (name intermediates via CPS), blocks→right-nested `ELet`, nested patterns→nested `ECase`, `EIf`→`ECase` on bool. Uses continuation-passing (`lower_to_atom_k`) from the start to correctly insert `ELet` bindings for non-atomic subexpressions.
- `pp.ml` — `string_of_expr`, `string_of_ty`, etc. for test assertions and debugging. Keeps `tir.ml` free of logic.

**What this plan does NOT cover** (future plans):
- Monomorphization (`mono.ml`)
- Defunctionalization (`defun.ml`)
- Perceus RC analysis (`perceus.ml`)
- Escape analysis (`escape.ml`)
- LLVM emission (`llvm_emit.ml`)

**Known limitations of this initial implementation:**
- Guard expressions on match branches are not yet handled (will `failwith` if encountered)
- Actor declarations are skipped during lowering (actors are a future pass concern)
- Type information is best-effort pre-monomorphization (`TVar "_"` placeholder for unresolved types)

---

### Task 1: Scaffold `lib/tir/` with type definitions

**Files:**
- Create: `lib/tir/dune`
- Create: `lib/tir/tir.ml`

- [ ] **Step 1: Create the dune build file**

Create `lib/tir/dune`:
```
(library
 (name march_tir)
 (libraries march_ast)
 (preprocess (pps ppx_deriving.show)))
```

- [ ] **Step 2: Create `tir.ml` with all TIR type definitions**

Create `lib/tir/tir.ml` with types from `specs/tir.md`:
```ocaml
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

(** Atoms — values that require no computation. *)
type atom =
  | AVar of var
  | ALit of March_ast.Ast.literal
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
  | EAlloc   of ty * atom list                    (* heap-allocate a constructor *)
  | EFree    of atom                              (* explicit dealloc — inserted by Perceus *)
  | EIncRC   of atom                              (* RC increment — inserted by Perceus *)
  | EDecRC   of atom                              (* RC decrement — inserted by Perceus *)
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

(** A TIR module. *)
type tir_module = {
  tm_name  : string;
  tm_fns   : fn_def list;
  tm_types : type_def list;
}
[@@deriving show]
```

- [ ] **Step 3: Verify it builds**

Run: `dune build`
Expected: Clean build, no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/tir/dune lib/tir/tir.ml
git commit -m "feat(tir): scaffold TIR type definitions (ty, var, atom, expr, fn_def, tir_module)"
```

---

### Task 2: TIR pretty-printer

**Files:**
- Create: `lib/tir/pp.ml`
- Modify: `test/test_march.ml`
- Modify: `test/dune`

- [ ] **Step 1: Write failing tests that import the pretty-printer**

Add `march_tir` to `test/dune` libraries:
```
(test
 (name test_march)
 (libraries march_lexer march_parser march_ast march_desugar march_typecheck march_errors march_eval march_tir alcotest))
```

Add to `test/test_march.ml` — new test functions and a `"tir"` group in the test runner:
```ocaml
let test_tir_pp_atom () =
  let open March_tir.Tir in
  let open March_tir.Pp in
  let v = { v_name = "x"; v_ty = TInt; v_lin = Unr } in
  let a = AVar v in
  Alcotest.(check string) "atom var" "x" (string_of_atom a)

let test_tir_pp_lit () =
  let open March_tir.Pp in
  let a = March_tir.Tir.ALit (March_ast.Ast.LitInt 42) in
  Alcotest.(check string) "atom lit" "42" (string_of_atom a)
```

Add to the test runner:
```ocaml
      ( "tir",
        [
          Alcotest.test_case "pp atom var"         `Quick test_tir_pp_atom;
          Alcotest.test_case "pp atom lit"          `Quick test_tir_pp_lit;
        ] );
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune runtest`
Expected: Compilation error — `March_tir.Pp` does not exist.

- [ ] **Step 3: Implement `pp.ml`**

Create `lib/tir/pp.ml`:
```ocaml
(** Pretty-printer for TIR expressions and types. *)

open Tir

let rec string_of_ty = function
  | TInt -> "Int"
  | TFloat -> "Float"
  | TBool -> "Bool"
  | TString -> "String"
  | TUnit -> "Unit"
  | TTuple ts -> "(" ^ String.concat ", " (List.map string_of_ty ts) ^ ")"
  | TRecord fs ->
    "{ " ^ String.concat ", " (List.map (fun (n, t) -> n ^ " : " ^ string_of_ty t) fs) ^ " }"
  | TCon (name, []) -> name
  | TCon (name, args) -> name ^ "(" ^ String.concat ", " (List.map string_of_ty args) ^ ")"
  | TFn (params, ret) ->
    "(" ^ String.concat ", " (List.map string_of_ty params) ^ ") -> " ^ string_of_ty ret
  | TPtr t -> "Ptr(" ^ string_of_ty t ^ ")"
  | TVar name -> "'" ^ name

let string_of_linearity = function
  | Lin -> "linear"
  | Aff -> "affine"
  | Unr -> ""

let string_of_var v =
  let lin = match v.v_lin with Unr -> "" | l -> string_of_linearity l ^ " " in
  lin ^ v.v_name ^ " : " ^ string_of_ty v.v_ty

let string_of_atom = function
  | AVar v -> v.v_name
  | ALit (March_ast.Ast.LitInt n) -> string_of_int n
  | ALit (March_ast.Ast.LitFloat f) -> string_of_float f
  | ALit (March_ast.Ast.LitString s) -> "\"" ^ String.escaped s ^ "\""
  | ALit (March_ast.Ast.LitBool b) -> string_of_bool b
  | ALit (March_ast.Ast.LitAtom a) -> ":" ^ a

let rec string_of_expr = function
  | EAtom a -> string_of_atom a
  | EApp (f, args) ->
    f.v_name ^ "(" ^ String.concat ", " (List.map string_of_atom args) ^ ")"
  | ECallPtr (f, args) ->
    "call_ptr " ^ string_of_atom f ^ "(" ^ String.concat ", " (List.map string_of_atom args) ^ ")"
  | ELet (v, e1, e2) ->
    "let " ^ string_of_var v ^ " = " ^ string_of_expr e1 ^ " in\n" ^ string_of_expr e2
  | ELetRec (fns, body) ->
    "letrec [" ^ String.concat "; " (List.map (fun f -> f.fn_name) fns) ^ "] in\n" ^ string_of_expr body
  | ECase (scrut, branches, default) ->
    let brs = List.map (fun br ->
        br.br_tag ^ "(" ^ String.concat ", " (List.map (fun v -> v.v_name) br.br_vars) ^ ") -> " ^ string_of_expr br.br_body
      ) branches in
    let def = match default with
      | Some e -> ["_ -> " ^ string_of_expr e]
      | None -> []
    in
    "case " ^ string_of_atom scrut ^ " of\n  " ^ String.concat "\n  " (brs @ def)
  | ETuple atoms ->
    "(" ^ String.concat ", " (List.map string_of_atom atoms) ^ ")"
  | ERecord fields ->
    "{ " ^ String.concat ", " (List.map (fun (n, a) -> n ^ " = " ^ string_of_atom a) fields) ^ " }"
  | EField (a, name) -> string_of_atom a ^ "." ^ name
  | EUpdate (a, fields) ->
    "{ " ^ string_of_atom a ^ " with " ^
    String.concat ", " (List.map (fun (n, a) -> n ^ " = " ^ string_of_atom a) fields) ^ " }"
  | EAlloc (ty, args) ->
    "alloc " ^ string_of_ty ty ^ "(" ^ String.concat ", " (List.map string_of_atom args) ^ ")"
  | EFree a -> "free " ^ string_of_atom a
  | EIncRC a -> "inc_rc " ^ string_of_atom a
  | EDecRC a -> "dec_rc " ^ string_of_atom a
  | EReuse (a, ty, args) ->
    "reuse " ^ string_of_atom a ^ " as " ^ string_of_ty ty ^
    "(" ^ String.concat ", " (List.map string_of_atom args) ^ ")"
  | ESeq (e1, e2) ->
    string_of_expr e1 ^ ";\n" ^ string_of_expr e2

let string_of_fn_def fn =
  "fn " ^ fn.fn_name ^ "(" ^
  String.concat ", " (List.map string_of_var fn.fn_params) ^
  ") : " ^ string_of_ty fn.fn_ret_ty ^ " =\n  " ^ string_of_expr fn.fn_body
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dune runtest`
Expected: All tests pass, including the two new TIR pp tests.

- [ ] **Step 5: Commit**

```bash
git add lib/tir/pp.ml test/test_march.ml test/dune
git commit -m "feat(tir): add TIR pretty-printer and basic tests"
```

---

### Task 3: Lowering infrastructure — fresh name generation, type conversion, CPS helpers

**Files:**
- Create: `lib/tir/lower.ml`
- Modify: `test/test_march.ml`

This task creates the `lower.ml` file with: fresh variable generation, AST type → TIR type conversion, AST linearity → TIR linearity conversion, and the CPS-based `lower_to_atom_k` / `lower_atoms_k` helpers. No full expression lowering yet — just the infrastructure.

- [ ] **Step 1: Write failing tests for type conversion**

Add to `test/test_march.ml`:
```ocaml
let test_tir_lower_ty_int () =
  let ast_ty = March_ast.Ast.TyCon ({ txt = "Int"; span = March_ast.Ast.dummy_span }, []) in
  let tir_ty = March_tir.Lower.lower_ty ast_ty in
  Alcotest.(check string) "Int → TInt" "Int" (March_tir.Pp.string_of_ty tir_ty)

let test_tir_lower_ty_tuple () =
  let open March_ast.Ast in
  let ast_ty = TyTuple [
    TyCon ({ txt = "Int"; span = dummy_span }, []);
    TyCon ({ txt = "Bool"; span = dummy_span }, [])
  ] in
  let tir_ty = March_tir.Lower.lower_ty ast_ty in
  Alcotest.(check string) "tuple" "(Int, Bool)" (March_tir.Pp.string_of_ty tir_ty)
```

Add to the `"tir"` test group:
```ocaml
          Alcotest.test_case "lower ty Int"        `Quick test_tir_lower_ty_int;
          Alcotest.test_case "lower ty tuple"      `Quick test_tir_lower_ty_tuple;
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune runtest`
Expected: Compilation error — `March_tir.Lower` does not exist.

- [ ] **Step 3: Implement `lower.ml` with helpers and CPS infrastructure**

Create `lib/tir/lower.ml`:
```ocaml
(** AST → TIR lowering pass.

    Converts desugared [Ast.module_] to [Tir.tir_module] in A-normal form.
    Key transformations:
    - All intermediate results named via [Tir.ELet] using CPS-style let-insertion
    - Blocks → right-nested [ELet] chains
    - Nested patterns → nested [ECase]
    - [EIf] → [ECase] on bool

    ANF conversion uses continuation-passing: [lower_to_atom_k e k] lowers [e]
    and calls [k atom] with the resulting atom. If [e] is not already atomic,
    a fresh [ELet] binding wraps the continuation. This ensures all call
    arguments are atoms without dangling variable references. *)

module Ast = March_ast.Ast

(* ── Fresh name generation ──────────────────────────────────────── *)

let _lower_counter = ref 0

let fresh_name (prefix : string) : string =
  incr _lower_counter;
  Printf.sprintf "$%s%d" prefix !_lower_counter

let reset_counter () = _lower_counter := 0

let fresh_var ?(lin = Tir.Unr) (ty : Tir.ty) : Tir.var =
  { v_name = fresh_name "t"; v_ty = ty; v_lin = lin }

(* ── Type conversion: Ast.ty → Tir.ty ──────────────────────────── *)

(** Default type used when no annotation is available. A placeholder
    that will be resolved during monomorphization. *)
let unknown_ty = Tir.TVar "_"

(** Convert surface types to TIR types.
    Pre-monomorphization, type variables become [TVar]. *)
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

(** Convert AST linearity to TIR linearity. *)
let lower_linearity : Ast.linearity -> Tir.linearity = function
  | Ast.Linear       -> Tir.Lin
  | Ast.Affine       -> Tir.Aff
  | Ast.Unrestricted -> Tir.Unr
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dune runtest`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/tir/lower.ml test/test_march.ml
git commit -m "feat(tir): add type conversion and fresh name generation for lowering"
```

---

### Task 4: Lower expressions to ANF with CPS let-insertion

**Files:**
- Modify: `lib/tir/lower.ml`
- Modify: `test/test_march.ml`

This task adds the full expression lowering with CPS-style let-insertion from the start. All non-atomic subexpressions are properly named via `ELet` bindings.

- [ ] **Step 1: Write failing tests**

Add to `test/test_march.ml`:
```ocaml
(** Parse, desugar, and lower a March module to TIR. *)
let lower_module src =
  let m = parse_and_desugar src in
  March_tir.Lower.lower_module m

let find_fn name (m : March_tir.Tir.tir_module) =
  List.find (fun (f : March_tir.Tir.fn_def) -> f.fn_name = name) m.tm_fns

let test_tir_lower_literal () =
  let m = lower_module {|mod Test do
    fn answer() : Int do 42 end
  end|} in
  let f = find_fn "answer" m in
  match f.fn_body with
  | March_tir.Tir.EAtom (ALit (March_ast.Ast.LitInt 42)) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "expected EAtom(42), got: %s"
           (March_tir.Pp.string_of_expr f.fn_body))

let test_tir_lower_let () =
  let m = lower_module {|mod Test do
    fn double(x : Int) : Int do
      let y = x
      y
    end
  end|} in
  let f = find_fn "double" m in
  match f.fn_body with
  | March_tir.Tir.ELet (_, _, _) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "expected ELet, got: %s"
           (March_tir.Pp.string_of_expr f.fn_body))

let test_tir_lower_if () =
  let m = lower_module {|mod Test do
    fn pick(b : Bool) : Int do if b then 1 else 0 end
  end|} in
  let f = find_fn "pick" m in
  let rec has_case = function
    | March_tir.Tir.ECase _ -> true
    | March_tir.Tir.ELet (_, _, body) -> has_case body
    | _ -> false
  in
  Alcotest.(check bool) "if→case" true (has_case f.fn_body)

let test_tir_anf_nested_call () =
  (* f(g(x)) should produce an ELet for the inner g(x) call *)
  let m = lower_module {|mod Test do
    fn g(x : Int) : Int do x end
    fn f(x : Int) : Int do x end
    fn main() : Int do f(g(1)) end
  end|} in
  let f = find_fn "main" m in
  let rec has_let = function
    | March_tir.Tir.ELet (_, _, _) -> true
    | _ -> false
  in
  Alcotest.(check bool) "nested call needs ELet" true (has_let f.fn_body)

let test_tir_lower_constructor () =
  let m = lower_module {|mod Test do
    type Shape = Circle(Int) | Square(Int)
    fn make() do Circle(42) end
  end|} in
  let f = find_fn "make" m in
  let rec has_alloc = function
    | March_tir.Tir.EAlloc _ -> true
    | March_tir.Tir.ELet (_, e1, e2) -> has_alloc e1 || has_alloc e2
    | _ -> false
  in
  Alcotest.(check bool) "constructor→EAlloc" true (has_alloc f.fn_body)

let test_tir_lower_lambda () =
  let m = lower_module {|mod Test do
    fn make_adder(n : Int) do fn x -> x end
  end|} in
  let f = find_fn "make_adder" m in
  let rec has_letrec = function
    | March_tir.Tir.ELetRec _ -> true
    | March_tir.Tir.ELet (_, _, body) -> has_letrec body
    | _ -> false
  in
  Alcotest.(check bool) "lambda→ELetRec" true (has_letrec f.fn_body)

let test_tir_lower_match () =
  let m = lower_module {|mod Test do
    type Shape = Circle(Int) | Square(Int)
    fn area(s) do
      match s with
      | Circle(r) -> r
      | Square(side) -> side
      end
    end
  end|} in
  let f = find_fn "area" m in
  let rec has_case = function
    | March_tir.Tir.ECase _ -> true
    | March_tir.Tir.ELet (_, _, body) -> has_case body
    | _ -> false
  in
  Alcotest.(check bool) "match→ECase" true (has_case f.fn_body)

let test_tir_lower_record () =
  let m = lower_module {|mod Test do
    fn make() do { x = 1, y = 2 } end
  end|} in
  let f = find_fn "make" m in
  match f.fn_body with
  | March_tir.Tir.ERecord _ -> ()
  | _ -> Alcotest.fail (Printf.sprintf "expected ERecord, got: %s"
           (March_tir.Pp.string_of_expr f.fn_body))

let test_tir_lower_seq () =
  let m = lower_module {|mod Test do
    fn f() do
      println("hi")
      42
    end
  end|} in
  let f = find_fn "f" m in
  let rec has_seq = function
    | March_tir.Tir.ESeq _ -> true
    | March_tir.Tir.ELet (_, _, body) -> has_seq body
    | _ -> false
  in
  Alcotest.(check bool) "block→ESeq" true (has_seq f.fn_body)
```

Add all to `"tir"` test group:
```ocaml
          Alcotest.test_case "lower literal"       `Quick test_tir_lower_literal;
          Alcotest.test_case "lower let"            `Quick test_tir_lower_let;
          Alcotest.test_case "lower if→case"        `Quick test_tir_lower_if;
          Alcotest.test_case "ANF nested call"      `Quick test_tir_anf_nested_call;
          Alcotest.test_case "lower constructor"    `Quick test_tir_lower_constructor;
          Alcotest.test_case "lower lambda"         `Quick test_tir_lower_lambda;
          Alcotest.test_case "lower match"          `Quick test_tir_lower_match;
          Alcotest.test_case "lower record"         `Quick test_tir_lower_record;
          Alcotest.test_case "lower seq"            `Quick test_tir_lower_seq;
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune runtest`
Expected: Compilation error — `March_tir.Lower.lower_module` does not exist.

- [ ] **Step 3: Implement expression lowering with CPS-style let-insertion**

Add to `lib/tir/lower.ml`:
```ocaml
(* ── CPS-based ANF lowering ────────────────────────────────────── *)

(** Lower an expression, ensuring the result is an atom.
    [k] is called with the resulting atom, and any necessary [ELet]
    bindings are wrapped around the result of [k].

    This is the core ANF trick: non-atomic expressions get a fresh
    variable name, their lowered form becomes the RHS of an [ELet],
    and the continuation [k] receives the bound variable as an atom. *)
let rec lower_to_atom_k (e : Ast.expr) (k : Tir.atom -> Tir.expr) : Tir.expr =
  match e with
  | Ast.ELit (lit, _) -> k (Tir.ALit lit)
  | Ast.EVar { txt = name; _ } ->
    k (Tir.AVar { v_name = name; v_ty = unknown_ty; v_lin = Tir.Unr })
  | _ ->
    let rhs = lower_expr e in
    let v = fresh_var unknown_ty in
    Tir.ELet (v, rhs, k (Tir.AVar v))

(** Lower a list of expressions to atoms using CPS. *)
and lower_atoms_k (es : Ast.expr list) (k : Tir.atom list -> Tir.expr) : Tir.expr =
  match es with
  | [] -> k []
  | e :: rest ->
    lower_to_atom_k e (fun a ->
      lower_atoms_k rest (fun rest_atoms ->
        k (a :: rest_atoms)))

(** Translate an AST expression to a TIR expression in ANF. *)
and lower_expr (e : Ast.expr) : Tir.expr =
  match e with
  (* --- Atoms --- *)
  | Ast.ELit (lit, _) -> Tir.EAtom (ALit lit)

  | Ast.EVar { txt = name; _ } ->
    Tir.EAtom (AVar { v_name = name; v_ty = unknown_ty; v_lin = Unr })

  (* --- Let bindings --- *)
  | Ast.ELet (b, _) ->
    lower_expr b.bind_expr

  (* --- Blocks → right-nested ELet --- *)
  | Ast.EBlock ([], _) -> Tir.EAtom (ALit (Ast.LitAtom "unit"))
  | Ast.EBlock ([e], _) -> lower_expr e
  | Ast.EBlock (Ast.ELet (b, _) :: rest, sp) ->
    let rhs = lower_expr b.bind_expr in
    let bind_name = match b.bind_pat with
      | Ast.PatVar n -> n.txt
      | _ -> fresh_name "p"
    in
    let v : Tir.var = {
      v_name = bind_name;
      v_ty = (match b.bind_ty with Some t -> lower_ty t | None -> unknown_ty);
      v_lin = lower_linearity b.bind_lin;
    } in
    let body = lower_expr (Ast.EBlock (rest, sp)) in
    Tir.ELet (v, rhs, body)
  | Ast.EBlock (e :: rest, sp) ->
    let e' = lower_expr e in
    let body = lower_expr (Ast.EBlock (rest, sp)) in
    Tir.ESeq (e', body)

  (* --- If → ECase on bool (CPS for condition) --- *)
  | Ast.EIf (cond, then_e, else_e, _) ->
    lower_to_atom_k cond (fun cond_atom ->
      let then' = lower_expr then_e in
      let else' = lower_expr else_e in
      Tir.ECase (cond_atom,
        [{ br_tag = "True"; br_vars = []; br_body = then' }],
        Some else'))

  (* --- Tuples (CPS for elements) --- *)
  | Ast.ETuple (es, _) ->
    lower_atoms_k es (fun atoms -> Tir.ETuple atoms)

  (* --- Records (CPS for field values) --- *)
  | Ast.ERecord (fields, _) ->
    let names = List.map (fun (n, _) -> n.Ast.txt) fields in
    let exprs = List.map snd fields in
    lower_atoms_k exprs (fun atoms ->
      Tir.ERecord (List.combine names atoms))

  | Ast.ERecordUpdate (base, updates, _) ->
    lower_to_atom_k base (fun base_atom ->
      let names = List.map (fun (n, _) -> n.Ast.txt) updates in
      let exprs = List.map snd updates in
      lower_atoms_k exprs (fun atoms ->
        Tir.EUpdate (base_atom, List.combine names atoms)))

  | Ast.EField (e, { txt = name; _ }, _) ->
    lower_to_atom_k e (fun a -> Tir.EField (a, name))

  (* --- Function application (CPS: all args must be atoms) --- *)
  | Ast.EApp (f_expr, args, _) ->
    lower_to_atom_k f_expr (fun f_atom ->
      lower_atoms_k args (fun arg_atoms ->
        let f_var = match f_atom with
          | Tir.AVar v -> v
          | Tir.ALit _ ->
            { v_name = "<lit>"; v_ty = unknown_ty; v_lin = Tir.Unr }
        in
        Tir.EApp (f_var, arg_atoms)))

  (* --- Constructor application (CPS for args) --- *)
  | Ast.ECon ({ txt = tag; _ }, args, _) ->
    lower_atoms_k args (fun arg_atoms ->
      Tir.EAlloc (Tir.TCon (tag, []), arg_atoms))

  (* --- Lambda → ELetRec with a single fn_def --- *)
  | Ast.ELam (params, body, _) ->
    let fn_name = fresh_name "lam" in
    let params' = List.map (fun (p : Ast.param) ->
        { Tir.v_name = p.param_name.txt;
          v_ty = (match p.param_ty with Some t -> lower_ty t | None -> unknown_ty);
          v_lin = lower_linearity p.param_lin }
      ) params in
    let body' = lower_expr body in
    let ret_ty = unknown_ty in
    let fn : Tir.fn_def = {
      fn_name; fn_params = params'; fn_ret_ty = ret_ty; fn_body = body'
    } in
    let fn_var : Tir.var = {
      v_name = fn_name;
      v_ty = Tir.TFn (List.map (fun v -> v.Tir.v_ty) params', ret_ty);
      v_lin = Tir.Unr
    } in
    Tir.ELetRec ([fn], Tir.EAtom (AVar fn_var))

  (* --- Match → ECase (CPS for scrutinee) --- *)
  | Ast.EMatch (scrut, branches, _) ->
    lower_to_atom_k scrut (fun scrut_atom ->
      lower_match scrut_atom branches)

  (* --- Annotations: lower the inner expr --- *)
  | Ast.EAnnot (e, _, _) -> lower_expr e

  (* --- Atoms (the :tag syntax) --- *)
  | Ast.EAtom (a, [], _) -> Tir.EAtom (ALit (Ast.LitAtom a))
  | Ast.EAtom (a, args, _) ->
    lower_atoms_k args (fun arg_atoms ->
      Tir.EAlloc (Tir.TCon (a, []), arg_atoms))

  (* --- Holes --- *)
  | Ast.EHole (name, _) ->
    let label = match name with Some n -> n.txt | None -> "?" in
    Tir.EAtom (ALit (Ast.LitAtom ("hole_" ^ label)))

  (* --- Pipe should be desugared already --- *)
  | Ast.EPipe _ -> failwith "TIR lower: EPipe should have been desugared"

  (* --- Send/Spawn (CPS for args) --- *)
  | Ast.ESend (cap, msg, _) ->
    lower_to_atom_k cap (fun cap' ->
      lower_to_atom_k msg (fun msg' ->
        let send_var : Tir.var = { v_name = "send"; v_ty = unknown_ty; v_lin = Tir.Unr } in
        Tir.EApp (send_var, [cap'; msg'])))

  | Ast.ESpawn (actor, _) ->
    lower_to_atom_k actor (fun actor' ->
      let spawn_var : Tir.var = { v_name = "spawn"; v_ty = unknown_ty; v_lin = Tir.Unr } in
      Tir.EApp (spawn_var, [actor']))

(* ── Match lowering ─────────────────────────────────────────────── *)

(** Lower match branches to [ECase].
    - Constructor patterns → branches with bound variables
    - Literal patterns → branches with tag = string representation
    - Wildcard/var patterns → default arm
    - PatVar default arms: wraps body in [ELet] binding the scrutinee to the variable name
    - Guards: not yet supported (failwith if encountered) *)
and lower_match (scrut : Tir.atom) (branches : Ast.branch list) : Tir.expr =
  (* Check for guards — not supported yet *)
  List.iter (fun (br : Ast.branch) ->
      match br.branch_guard with
      | Some _ -> failwith "TIR lower: match guards are not yet supported"
      | None -> ()
    ) branches;
  let tir_branches = List.filter_map (fun (br : Ast.branch) ->
      match br.branch_pat with
      | Ast.PatCon ({ txt = tag; _ }, sub_pats) ->
        let vars = List.map (fun pat ->
            let name = match pat with
              | Ast.PatVar n -> n.txt
              | Ast.PatWild _ -> fresh_name "w"
              | _ -> fresh_name "p"
            in
            { Tir.v_name = name; v_ty = unknown_ty; v_lin = Tir.Unr }
          ) sub_pats in
        Some { Tir.br_tag = tag; br_vars = vars; br_body = lower_expr br.branch_body }
      | Ast.PatLit (Ast.LitInt n, _) ->
        Some { Tir.br_tag = string_of_int n; br_vars = [];
               br_body = lower_expr br.branch_body }
      | Ast.PatLit (Ast.LitBool b, _) ->
        Some { Tir.br_tag = string_of_bool b; br_vars = [];
               br_body = lower_expr br.branch_body }
      | Ast.PatLit (Ast.LitString s, _) ->
        Some { Tir.br_tag = "\"" ^ s ^ "\""; br_vars = [];
               br_body = lower_expr br.branch_body }
      | Ast.PatLit (Ast.LitAtom a, _) ->
        Some { Tir.br_tag = ":" ^ a; br_vars = [];
               br_body = lower_expr br.branch_body }
      | _ -> None
    ) branches in
  (* Default arm: wildcard or var pattern *)
  let default = List.find_map (fun (br : Ast.branch) ->
      match br.branch_pat with
      | Ast.PatWild _ -> Some (lower_expr br.branch_body)
      | Ast.PatVar n ->
        (* Bind the scrutinee to the variable name so the body can use it *)
        let v : Tir.var = { v_name = n.txt; v_ty = unknown_ty; v_lin = Tir.Unr } in
        Some (Tir.ELet (v, Tir.EAtom scrut, lower_expr br.branch_body))
      | _ -> None
    ) branches in
  Tir.ECase (scrut, tir_branches, default)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dune runtest`
Expected: Compilation error — `lower_module` not yet defined. That's fine — the tests from this task call `lower_module` which will be added in Task 5. But the expression lowering code itself will compile.

Actually, since the tests call `lower_module`, they need it to exist. Move the test additions to Task 5 or add a stub `lower_module`. Better approach: split — add expression lowering code now, tests come with Task 5 when `lower_module` exists.

Instead, verify the build compiles:

Run: `dune build`
Expected: Clean build.

- [ ] **Step 5: Commit**

```bash
git add lib/tir/lower.ml
git commit -m "feat(tir): implement ANF expression lowering with CPS let-insertion"
```

---

### Task 5: Lower declarations, modules, and add all expression tests

**Files:**
- Modify: `lib/tir/lower.ml`
- Modify: `test/test_march.ml`

- [ ] **Step 1: Add declaration/module lowering to `lower.ml`**

Add to `lib/tir/lower.ml`:
```ocaml
(* ── Declaration lowering ───────────────────────────────────────── *)

(** Lower a single function definition (post-desugaring: exactly 1 clause). *)
let lower_fn_def (def : Ast.fn_def) : Tir.fn_def =
  let clause = match def.fn_clauses with
    | [c] -> c
    | _ -> failwith (Printf.sprintf "TIR lower: fn %s has %d clauses (expected 1 after desugaring)"
                       def.fn_name.txt (List.length def.fn_clauses))
  in
  let params = List.map (fun fp ->
      match fp with
      | Ast.FPNamed p ->
        { Tir.v_name = p.param_name.txt;
          v_ty = (match p.param_ty with Some t -> lower_ty t | None -> unknown_ty);
          v_lin = lower_linearity p.param_lin }
      | Ast.FPPat (Ast.PatVar n) ->
        { Tir.v_name = n.txt; v_ty = unknown_ty; v_lin = Tir.Unr }
      | _ -> failwith "TIR lower: unexpected pattern param after desugaring"
    ) clause.fc_params in
  let ret_ty = match def.fn_ret_ty with
    | Some t -> lower_ty t
    | None -> unknown_ty
  in
  let body = lower_expr clause.fc_body in
  { fn_name = def.fn_name.txt; fn_params = params; fn_ret_ty = ret_ty; fn_body = body }

(** Lower a type definition. *)
let lower_type_def (name : Ast.name) (_params : Ast.name list) (td : Ast.type_def) : Tir.type_def option =
  match td with
  | Ast.TDVariant variants ->
    let ctors = List.map (fun (v : Ast.variant) ->
        (v.var_name.txt, List.map lower_ty v.var_args)
      ) variants in
    Some (Tir.TDVariant (name.txt, ctors))
  | Ast.TDRecord fields ->
    let fs = List.map (fun (f : Ast.field) ->
        (f.fld_name.txt, lower_ty f.fld_ty)
      ) fields in
    Some (Tir.TDRecord (name.txt, fs))
  | Ast.TDAlias _ -> None

(** Lower a module. *)
let lower_module (m : Ast.module_) : Tir.tir_module =
  reset_counter ();
  let fns = ref [] in
  let types = ref [] in
  List.iter (fun d ->
      match d with
      | Ast.DFn (def, _) ->
        fns := lower_fn_def def :: !fns
      | Ast.DType (name, params, td, _) ->
        (match lower_type_def name params td with
         | Some td' -> types := td' :: !types
         | None -> ())
      | Ast.DLet _ -> ()
      | Ast.DActor _ -> ()
      | Ast.DMod _ | Ast.DProtocol _ | Ast.DSig _ | Ast.DInterface _
      | Ast.DImpl _ | Ast.DExtern _ -> ()
    ) m.mod_decls;
  { tm_name = m.mod_name.txt;
    tm_fns = List.rev !fns;
    tm_types = List.rev !types }
```

- [ ] **Step 2: Add all tests from Task 4 plus module/declaration tests**

Add all the test functions from Task 4 Step 1, plus these additional tests:

```ocaml
let test_tir_lower_module () =
  let m = lower_module {|mod Test do
    fn add(x : Int, y : Int) : Int do x + y end
    fn main() do add(1, 2) end
  end|} in
  Alcotest.(check int) "2 functions" 2 (List.length m.March_tir.Tir.tm_fns);
  Alcotest.(check string) "first fn name" "add" (List.hd m.tm_fns).fn_name

let test_tir_lower_type_def () =
  let m = lower_module {|mod Test do
    type Shape = Circle(Int) | Square(Int)
    fn main() do 0 end
  end|} in
  Alcotest.(check int) "1 type def" 1 (List.length m.March_tir.Tir.tm_types)

let test_tir_lower_fn_params () =
  let m = lower_module {|mod Test do
    fn add(x : Int, y : Int) : Int do x + y end
  end|} in
  let f = find_fn "add" m in
  Alcotest.(check int) "2 params" 2 (List.length f.March_tir.Tir.fn_params);
  Alcotest.(check string) "ret type" "Int"
    (March_tir.Pp.string_of_ty f.fn_ret_ty)

let test_tir_anf_invariant () =
  (* Verify the core ANF property: all EApp arguments are atoms *)
  let m = lower_module {|mod Test do
    fn f(x : Int) : Int do x + x end
  end|} in
  let f = find_fn "f" m in
  let rec check_anf = function
    | March_tir.Tir.EApp (_, args) ->
      List.for_all (function
        | March_tir.Tir.AVar _ | March_tir.Tir.ALit _ -> true
      ) args
    | March_tir.Tir.ELet (_, e1, e2) -> check_anf e1 && check_anf e2
    | March_tir.Tir.ESeq (e1, e2) -> check_anf e1 && check_anf e2
    | March_tir.Tir.ECase (_, brs, def) ->
      List.for_all (fun br -> check_anf br.br_body) brs &&
      (match def with Some e -> check_anf e | None -> true)
    | _ -> true
  in
  Alcotest.(check bool) "ANF invariant: all call args are atoms" true (check_anf f.fn_body)

let test_tir_lower_patvar_default () =
  (* PatVar in default arm should bind the scrutinee *)
  let m = lower_module {|mod Test do
    fn describe(n) do
      match n with
      | 0 -> 0
      | other -> other
      end
    end
  end|} in
  let f = find_fn "describe" m in
  (* The default arm should have an ELet binding "other" *)
  let rec find_case = function
    | March_tir.Tir.ECase (_, _, Some def) -> def
    | March_tir.Tir.ELet (_, _, body) -> find_case body
    | e -> e
  in
  match find_case f.fn_body with
  | March_tir.Tir.ELet (v, _, _) ->
    Alcotest.(check string) "PatVar binds scrutinee" "other" v.v_name
  | _ -> Alcotest.fail "expected ELet in default arm for PatVar"
```

Add all to the `"tir"` test group:
```ocaml
          Alcotest.test_case "lower literal"       `Quick test_tir_lower_literal;
          Alcotest.test_case "lower let"            `Quick test_tir_lower_let;
          Alcotest.test_case "lower if→case"        `Quick test_tir_lower_if;
          Alcotest.test_case "ANF nested call"      `Quick test_tir_anf_nested_call;
          Alcotest.test_case "lower constructor"    `Quick test_tir_lower_constructor;
          Alcotest.test_case "lower lambda"         `Quick test_tir_lower_lambda;
          Alcotest.test_case "lower match"          `Quick test_tir_lower_match;
          Alcotest.test_case "lower record"         `Quick test_tir_lower_record;
          Alcotest.test_case "lower seq"            `Quick test_tir_lower_seq;
          Alcotest.test_case "lower module"         `Quick test_tir_lower_module;
          Alcotest.test_case "lower type def"       `Quick test_tir_lower_type_def;
          Alcotest.test_case "lower fn params"      `Quick test_tir_lower_fn_params;
          Alcotest.test_case "ANF invariant"        `Quick test_tir_anf_invariant;
          Alcotest.test_case "PatVar default arm"   `Quick test_tir_lower_patvar_default;
```

- [ ] **Step 3: Run tests**

Run: `dune runtest`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/tir/lower.ml test/test_march.ml
git commit -m "feat(tir): complete AST→TIR lowering with declaration/module support and tests"
```

---

### Task 6: Wire TIR lowering into the compiler pipeline

**Files:**
- Modify: `bin/main.ml`
- Modify: `bin/dune`

- [ ] **Step 1: Read `bin/dune` and add `march_tir` to dependencies**

Read `bin/dune`. Add `march_tir` to the libraries list.

- [ ] **Step 2: Add `--dump-tir` flag to the compiler**

Modify `bin/main.ml`. Add a `dump_tir` ref at the top and refactor arg parsing from `Sys.argv` pattern matching to `Arg.parse`:

```ocaml
let dump_tir = ref false
```

In `compile`, after the typecheck-errors check, add a TIR lowering branch:
```ocaml
  if March_errors.Errors.has_errors errors then exit 1
  else if !dump_tir then begin
    let tir = March_tir.Lower.lower_module desugared in
    List.iter (fun fn ->
        Printf.printf "%s\n\n" (March_tir.Pp.string_of_fn_def fn)
      ) tir.tm_fns
  end
  else begin
    try March_eval.Eval.run_module desugared
    with
    | March_eval.Eval.Eval_error msg ->
      Printf.eprintf "%s: runtime error: %s\n" filename msg; exit 1
    | March_eval.Eval.Match_failure msg ->
      Printf.eprintf "%s: match failure: %s\n" filename msg; exit 1
  end
```

Replace the `let () =` block at the bottom with `Arg.parse`:
```ocaml
let () =
  let files = ref [] in
  let specs = [
    ("--dump-tir", Arg.Set dump_tir, " Print TIR instead of evaluating")
  ] in
  Arg.parse specs (fun f -> files := f :: !files) "Usage: march [options] [file.march]";
  match !files with
  | []  -> repl ()
  | [f] -> compile f
  | _   -> Printf.eprintf "Usage: march [options] [file.march]\n"; exit 1
```

- [ ] **Step 3: Test manually with an example file**

Run: `dune exec march -- --dump-tir examples/list_lib.march`
Expected: Prints TIR function definitions to stdout without crashing.

- [ ] **Step 4: Verify all existing tests still pass**

Run: `dune runtest`
Expected: All tests pass (50+ existing + new TIR tests).

- [ ] **Step 5: Commit**

```bash
git add bin/main.ml bin/dune
git commit -m "feat(tir): wire TIR lowering into compiler pipeline with --dump-tir flag"
```

---

### Task 7: End-to-end integration tests

**Files:**
- Modify: `test/test_march.ml`

- [ ] **Step 1: Write integration tests using inline sources**

Add to `test/test_march.ml` (using inline March source, not file paths, for portability):
```ocaml
let test_tir_lower_polymorphic () =
  (* Polymorphic functions should lower without crashing *)
  let m = lower_module {|mod Test do
    fn identity(x) do x end
    fn apply(f, x) do f(x) end
    fn compose(f, g, x) do f(g(x)) end
  end|} in
  Alcotest.(check int) "3 functions" 3 (List.length m.March_tir.Tir.tm_fns)

let test_tir_lower_recursive () =
  let m = lower_module {|mod Test do
    fn fib(0) do 0 end
    fn fib(1) do 1 end
    fn fib(n) do fib(n - 1) + fib(n - 2) end
  end|} in
  let f = find_fn "fib" m in
  (* Should have an ECase from the desugared multi-head *)
  let rec has_case = function
    | March_tir.Tir.ECase _ -> true
    | March_tir.Tir.ELet (_, _, body) -> has_case body
    | _ -> false
  in
  Alcotest.(check bool) "recursive fn lowers" true (has_case f.fn_body)

let test_tir_lower_list_ops () =
  let m = lower_module {|mod Test do
    type List = Cons(Int, List) | Nil

    fn map(f, xs) do
      match xs with
      | Nil -> Nil()
      | Cons(h, t) -> Cons(f(h), map(f, t))
      end
    end

    fn length(xs) do
      match xs with
      | Nil -> 0
      | Cons(h, t) -> 1 + length(t)
      end
    end
  end|} in
  Alcotest.(check int) "2 functions" 2 (List.length m.March_tir.Tir.tm_fns);
  Alcotest.(check int) "1 type def" 1 (List.length m.March_tir.Tir.tm_types)

let test_tir_lower_closures_and_hof () =
  let m = lower_module {|mod Test do
    fn make_adder(n : Int) do
      fn x -> x + n
    end

    fn twice(f, x) do f(f(x)) end

    fn main() : Int do
      let add5 = make_adder(5)
      twice(add5, 10)
    end
  end|} in
  Alcotest.(check int) "3 functions" 3 (List.length m.March_tir.Tir.tm_fns)
```

Add to the `"tir"` test group:
```ocaml
          Alcotest.test_case "lower polymorphic"   `Quick test_tir_lower_polymorphic;
          Alcotest.test_case "lower recursive"     `Quick test_tir_lower_recursive;
          Alcotest.test_case "lower list ops"      `Quick test_tir_lower_list_ops;
          Alcotest.test_case "lower closures/HOF"  `Quick test_tir_lower_closures_and_hof;
```

- [ ] **Step 2: Run tests**

Run: `dune runtest`
Expected: All pass.

- [ ] **Step 3: Fix any lowering failures discovered**

If any AST nodes are unhandled, add cases to `lower_expr`. This is the "shake out bugs" step.

- [ ] **Step 4: Commit**

```bash
git add test/test_march.ml lib/tir/lower.ml
git commit -m "test(tir): add integration tests for polymorphic, recursive, HOF lowering"
```

---

## Summary

| Task | What it builds | Tests added |
|------|---------------|-------------|
| 1 | `tir.ml` type definitions + dune scaffold | build check |
| 2 | `pp.ml` pretty-printer | 2 unit tests |
| 3 | `lower.ml` helpers (fresh names, type conversion, CPS infra) | 2 unit tests |
| 4 | Expression lowering with CPS let-insertion | build check (tests in Task 5) |
| 5 | Declaration/module lowering + all expression tests | 14 tests (expr + decl + ANF invariant + PatVar default) |
| 6 | Wire into compiler pipeline (`--dump-tir`) | manual + regression |
| 7 | Integration tests (polymorphic, recursive, HOF, list ops) | 4 integration tests |

**Total: ~7 commits, ~22 new tests, 3 new files created.**
