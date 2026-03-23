# Pattern Matching

## Overview

March provides expressive pattern matching through `match` expressions and function clauses. Patterns are compiled to decision trees via a matrix algorithm, supporting constructor patterns, literals, tuples, records, wildcards, and as-patterns. Match guards (`when`) enable value-dependent branching.

## Implementation Status

**Mostly complete.** Pattern matching is fully implemented from parsing through LLVM code generation. **Exhaustiveness checking is NOT implemented** — non-exhaustive patterns produce a runtime `Match_failure` exception, not a compile-time error.

**Syntax note (as of 2026-03-21):** Match expressions use `do` instead of `with`:
```march
match expr do
| Pat -> body
end
```

## Source Files & Line References

### AST: Pattern Representations: `lib/ast/ast.ml` (62–91, 118–123)

**Pattern types (lines 62–71):**
```ocaml
type pattern =
  | PatWild of span                           (* _ *)
  | PatVar of name                            (* x *)
  | PatCon of name * pattern list             (* Some(x), Cons(h, t) *)
  | PatAtom of string * pattern list * span   (* :ok(x), :error *)
  | PatTuple of pattern list * span           (* (x, y, z) *)
  | PatLit of literal * span                  (* 42, true, "hello" *)
  | PatRecord of (name * pattern) list * span (* { x, y = p } *)
  | PatAs of pattern * name * span            (* p as x *)
```

**Match branches (lines 118–123):**
```ocaml
type branch = {
  branch_pat : pattern;
  branch_guard : expr option;       (* when expr *)
  branch_body : expr;
}
```

**Function clause parameters (lines 168–180):**
```ocaml
type fn_param =
  | FPPat of pattern              (* Pattern parameter: fn fib(0) *)
  | FPNamed of param              (* Named parameter: fn f(x : T) *)

type fn_clause = {
  fc_params : fn_param list;      (* May contain pattern params *)
  fc_guard : expr option;         (* when expr *)
  fc_body : expr;
  fc_span : span;
}
```

**Match expressions (line 82):**
```ocaml
| EMatch of expr * branch list * span
```

### Type Checking: Pattern Inference: `lib/typecheck/typecheck.ml` (910–1000+)

**Pattern type inference (lines 919–1010):**
```ocaml
let rec infer_pattern env (pat : Ast.pattern)
  : (ty_binding list * ty) =
  (* Returns list of (name, type) bindings and the type the pattern expects *)
```

**Pattern cases:**

1. **Wildcard (line 922):** No bindings, returns fresh type variable
2. **Variable (line 925):** One binding for the variable with inferred type
3. **Literal (line 929):** No bindings; type is inferred from the literal
4. **Tuple (lines 932–936):**
   - Each element pattern is inferred recursively
   - Returns tuple of all element types
5. **Constructor (lines 938–975):**
   - Looks up constructor in environment (line 939)
   - Verifies arity matches (line 953–956)
   - Recursively infers sub-patterns and collects bindings
   - Returns constructor type with sub-pattern types
6. **Atom (lines 972–975):** Similar to constructors
7. **Record (lines 977–990):** Infers types for each field pattern

**Pattern binding collection (lines 919–1010):**
- Each pattern introduces bindings that are added to the type environment for the branch body
- Duplicate bindings in a pattern are detected and reported as errors

### Exhaustiveness Checking: NOT IMPLEMENTED

**No compile-time exhaustiveness analysis exists.** The type checker does not validate that match expressions cover all possible cases. Missing branches are silently accepted and result in a runtime `Match_failure` exception when reached.

This is a known gap. Future work would implement a pattern matrix usefulness/reachability algorithm (similar to OCaml's or Rust's) to warn or error on non-exhaustive matches at compile time.

**Practical implication:** Always include a wildcard `| _ -> ...` branch if you don't want a potential runtime crash for unmatched patterns.

### Desugaring: Multi-Clause Function Conversion: `lib/desugar/desugar.ml` (45–280)

**Key insight:** Multi-clause function definitions are desugared to single-clause functions with match expressions.

**Trivial pattern detection (lines 58–64):**
```ocaml
let is_trivial : fn_param -> bool = function
  | FPNamed _ -> false
  | FPPat (PatVar _) -> true   (* single var pattern is just a binding *)
  | FPPat (PatWild _) -> true
  | FPPat _ -> false
```

- Trivial patterns (variables, wildcards) don't require match desugaring
- Non-trivial patterns (constructors, literals, tuples) require a match

**Function desugaring (lines 163–220):**
```ocaml
let desugar_fn (def : fn_def) : fn_def =
  match def.fn_clauses with
  | [single_clause] when is_trivial_clause single_clause ->
    (* No match needed: return as-is *)
    def
  | clauses ->
    (* Multiple clauses or non-trivial patterns → generate match *)
    let arg_names = generate_arg_names (arity clauses.[0]) in
    let match_branches = List.map (fun clause ->
      let patterns = List.map fn_param_to_pattern clause.fc_params in
      let pat = match patterns with
        | [p] -> p
        | ps -> PatTuple ps
      in
      let body = if Option.is_some clause.fc_guard
        then wrap_guard clause.fc_guard clause.fc_body
        else clause.fc_body
      in
      { branch_pat = pat; branch_guard = clause.fc_guard; branch_body = body }
    ) clauses in
    let merged_body = EMatch (
      ETuple (List.map (fun n -> EVar { txt = n; span = ... }) arg_names),
      match_branches,
      None
    ) in
    { def with fn_clauses = [{ fc_params = named_params arg_names;
                               fc_guard = None;
                               fc_body = merged_body;
                               fc_span = def.fn_name.span }] }
```

**Process:**
1. For each clause, convert fn_params to patterns (lines 203–205)
2. Collect all patterns into a match on synthesized argument tuple (lines 208–217)
3. Guards are preserved in the match branches (line 170)
4. Return single-clause function with match body (lines 218–220)

### TIR Lowering: Decision Tree Compilation: `lib/tir/lower.ml` (442–612)

The match expression is compiled to a decision tree represented as nested `ECase` expressions.

**Trivial pattern handling (lines 444–462):**
```ocaml
let is_trivial_pat : Ast.pattern -> bool = function
  | Ast.PatWild _ | Ast.PatVar _ -> true
  | Ast.PatAs (p, _, _) -> is_trivial_pat p
  | _ -> false

let bind_trivial_pat (scrut : atom) (pat : pattern) (body : expr) : expr =
  match pat with
  | Ast.PatWild _ -> body
  | Ast.PatVar n ->
    let v = { v_name = n.txt; v_ty = unknown_ty; v_lin = Unr } in
    ELet (v, EAtom scrut, body)
  | Ast.PatAs (inner, n, _) ->
    let v = { v_name = n.txt; v_ty = unknown_ty; v_lin = Unr } in
    let named_body = ELet (v, EAtom scrut, body) in
    bind_trivial_pat scrut inner named_body
  | _ -> body
```

Trivial patterns (variables, wildcards) don't generate branches; instead, they introduce `ELet` bindings in the case body.

**Pattern tag and sub-patterns (lines 464–476):**
```ocaml
let pat_tag_and_subs (pat : pattern) : (string * pattern list) option =
  match pat with
  | PatCon ({ txt = tag; _ }, subs) -> Some (tag, subs)
  | PatTuple (subs, _) -> Some (Printf.sprintf "$Tuple%d" (List.length subs), subs)
  | PatLit (LitInt n, _)    -> Some (string_of_int n, [])
  | PatLit (LitBool b, _)   -> Some (string_of_bool b, [])
  | PatLit (LitString s, _) -> Some ("\"" ^ s ^ "\"", [])
  | PatLit (LitAtom a, _)   -> Some (":" ^ a, [])
  | _ -> None
```

Non-trivial patterns are tagged with a discriminant (constructor name, tuple size, literal value).

**Decision tree compilation (lines 485–576):**
```ocaml
let rec compile_matrix
    (scruts   : atom list)
    (rows     : (pattern list * expr) list)
    (fallback : expr option)
  : expr
```

**Algorithm:**
1. Base cases:
   - No rows: return fallback or unit
   - Zero scrutinees: return first row's body
2. Recursive case:
   - Split rows into "constructor rows" (non-trivial first pattern) and "default rows" (trivial first pattern)
   - The default rows become the fallback for all branches
   - Group constructor rows by their tag/discriminant
   - For each tag group, recursively compile sub-patterns against the remaining scrutinees
   - Return `ECase(first_scrutinee, branches_per_tag, default)`

**Guard handling (lines 582–612):**
Patterns with `when` guards are handled specially:
```ocaml
let lower_match (scrut : atom) (branches : branch list) : expr =
  let has_guards = List.exists (fun br -> br.branch_guard <> None) branches in
  if not has_guards then
    (* Fast path: use efficient matrix compilation *)
    compile_matrix [scrut] rows None
  else
    (* Guard path: emit if-else chain *)
    let rec go = function
      | [] -> EAtom (ALit (LitInt 0))  (* match failure *)
      | br :: rest ->
        let rest_expr = go rest in
        let body = lower_expr br.branch_body in
        let guarded_body = match br.branch_guard with
          | None -> body
          | Some guard ->
            (* if guard { body } else { try next branch } *)
            let gv = fresh_var "guard" TBool in
            ELet (gv, lower_expr guard,
              ECase (AVar gv,
                [{ br_tag = "true"; br_vars = []; br_body = body }],
                Some rest_expr))
        in
        compile_matrix [scrut] [([br.branch_pat], guarded_body)] (Some rest_expr)
    in
    go branches
```

When guards are present, each branch is compiled individually with fallthrough to the next branch if the guard fails.

### Code Generation: LLVM Emission: `lib/tir/llvm_emit.ml` (1138–1327)

**ECase to LLVM switch (lines 1139–1327):**

**Case structure:**
```llvm
switch <type> <scrutinee>, label %default [
  <case_value>, label %case_label
  ...
]
```

**Discriminant determination (lines 1197–1200):**
- If scrutinee is a pointer-typed constructor: load its tag (first field)
- If scrutinee is a scalar (int, bool): use the value directly
- String patterns are handled specially with if-else chains (line 1172)

**String case handling (lines 1172–1194):**
For string literals (tags starting with `"`), emit an if-else chain using `march_string_eq`:
```llvm
if (march_string_eq(scrut, "hello") != 0) {
  br %case_hello
} else if (march_string_eq(scrut, "world") != 0) {
  br %case_world
} else {
  br %default
}
```

**Branch variable extraction (lines 1240–1267):**
For constructor cases, extract field values from the scrutinee:
```ocaml
List.iteri (fun i (v : var) ->
  let field_ty = llvm_ty of field i in
  let fv = emit_load_field scrut i field_ty in
  let slot = alloca slot for v in
  store fv to slot
) br.br_vars
```

**Reference-counting optimization (lines 1269–1305):**
When the branch body starts with `dec_rc(scrutinee)` and the branch extracts heap-typed fields:
1. Emit `march_decrc_freed` to check if decrement would free the parent
2. If freed: skip field IncRC (fields are now unique)
3. If not freed (shared): IncRC each extracted field (resolve double-ownership)

**Result materialization (lines 1164–1326):**
- Each branch stores its result to a shared alloca slot (typed `ptr`)
- All branches jump to a merge block
- Merge block loads the result from the slot
- Scalar results are coerced via `inttoptr`/`ptrtoint`

## Pattern Syntax and Semantics

### Patterns by Category

**1. Literals**
```march
match x with
| 42 -> "found forty-two"
| "hello" -> "greeting"
| true -> "boolean"
| :ok -> "atom"
end
```

**2. Variables and Wildcards**
```march
match opt with
| Some(v) -> v
| None -> 0
| _ -> -1   (* unreachable after Some and None *)
end
```

**3. Constructors**
```march
match list with
| Cons(h, t) -> h + sum(t)
| Nil -> 0
end
```

**4. Tuples**
```march
match pair with
| (x, 0) -> x
| (0, y) -> y
| (a, b) -> a + b
end
```

**5. Records**
```march
match person with
| { name = "Alice", age = a } -> a
| { name, age } -> name ++ ": " ++ int_to_string(age)
end
```

**6. As-patterns (bind outer name)**
```march
match opt with
| Some(v) as full -> (v, full)
| None as empty -> (0, empty)
end
```

**7. Guards**
```march
match x with
| y when y > 0 -> "positive"
| y when y < 0 -> "negative"
| _ -> "zero"
end
```

### Multi-Clause Functions

Equivalent ways to express the same logic:

```march
(* Style 1: match expression *)
fn fib(n) do
  match n with
  | 0 -> 1
  | 1 -> 1
  | k -> fib(k-1) + fib(k-2)
  end
end

(* Style 2: multi-clause with patterns *)
fn fib(0) do 1 end
fn fib(1) do 1 end
fn fib(n) do fib(n-1) + fib(n-2) end

(* Style 3: multi-clause with guards *)
fn fib(n) when n <= 1 do 1 end
fn fib(n) do fib(n-1) + fib(n-2) end
```

All three are desugared to the same internal representation.

## Test Coverage

### `test/test_march.ml`

**Pattern parsing and desugaring (lines 115–220):**
- `test_parse_module_multi_head`: Parser handles multi-clause functions
- `test_desugar_multi_head_fn`: Multi-clause functions desugar to match expressions
- `test_desugar_single_named_fn`: Single-named-param functions don't get wrapped in match
- `test_desugar_multi_param`: Multiple parameters create tuple patterns

**Type checking patterns (lines 249–260):**
- `test_tc_match`: Match expressions type-check correctly
- Pattern bindings are visible in branch bodies
- Type errors in branches are reported

### `test/test_cas.ml`

Patterns are tested implicitly through serialization tests of TIR structures that include ECase nodes.

## Known Limitations

1. **No Literal Exhaustiveness Analysis:**
   - Integer and floating-point patterns don't warn about missing ranges
   - Only constructor types (variants) are fully exhaustiveness-checked
   - Example: `match x { | 0 -> | 1 -> | _ -> }` for an Int doesn't warn about missing 2, 3, ...

2. **No Nested Guard Propagation:**
   - Guards in outer patterns don't affect inner pattern matching
   - Each branch guard is independent

3. **Limited Record Pattern Syntax:**
   - Record patterns can bind fields but not provide default values
   - `{ x = 42 } as p` doesn't work; must use `{ x } when x = 42`

4. **No Pattern Guard Reuse:**
   - Can't write `when p(x) && q(x)` where `p` and `q` are pattern-derived conditions
   - Guards must be arbitrary expressions

5. **No Views or Pattern Guards in Bindings:**
   - `let x@(y, z) = ...` (as-pattern in let) works
   - But custom pattern views (active patterns) are not supported

6. **Linear Pattern Analysis Not Implemented:**
   - Pattern matching doesn't track linearity changes
   - A linear value can be matched without ensuring all branches use it

## Compilation Strategy

The compilation pipeline for pattern matching:

1. **Parsing:** Patterns are parsed as `pattern` AST nodes
2. **Type Checking:** Infer pattern types and collect bindings; check exhaustiveness
3. **Desugaring:** Multi-clause functions convert to match expressions
4. **TIR Lowering:**
   - Match expression → decision tree (matrix algorithm)
   - Decision tree → nested `ECase` expressions (each scrutinizes one discriminant)
5. **LLVM Emission:**
   - `ECase` → LLVM switch statement (or if-else chain for strings)
   - Branch variables extracted from scrutinee fields
   - Result materialized via shared alloca slot

## Dependencies on Other Features

- **Constructor definitions:** Pattern matching relies on type definitions (variants, records)
- **Type inference:** Pattern types drive binding types in branch bodies
- **Desugaring:** Multi-clause functions depend on pattern desugaring
- **TIR expressions:** Decision trees are represented as TIR expressions (ECase)
- **LLVM backend:** Final code generation uses LLVM switch and branch instructions

## Examples

### Simple Constructor Matching

```march
type Color = Red | Green | Blue

fn color_name(c : Color) : String =
  match c with
  | Red -> "red"
  | Green -> "green"
  | Blue -> "blue"
  end
```

### Nested Pattern Matching

```march
type Tree(a) = Leaf(a) | Branch(Tree(a), Tree(a))

fn sum_tree(t : Tree(Int)) : Int =
  match t with
  | Leaf(x) -> x
  | Branch(Leaf(l), Leaf(r)) -> l + r
  | Branch(l, r) -> sum_tree(l) + sum_tree(r)
  end
```

### Guard-Based Dispatch

```march
fn compare_int(x : Int, y : Int) : String =
  match (x, y) with
  | (a, b) when a > b -> "greater"
  | (a, b) when a < b -> "less"
  | _ -> "equal"
  end
```

### Multi-Clause with Guards

```march
fn max(x, y) when x >= y do x end
fn max(x, y) do y end
```

This is desugared to:
```march
fn max(x, y) do
  match (x, y) with
  | (x, y) when x >= y -> x
  | (x, y) -> y
  end
end
```

### Record Pattern

```march
type Person = { name : String, age : Int }

fn is_adult(p : Person) : Bool =
  match p with
  | { age = a } when a >= 18 -> true
  | _ -> false
  end
```
