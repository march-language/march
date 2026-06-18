# Structural Interface Satisfaction

**Status:** Planned — P3 (medium-term)  
**Replaces:** "Row polymorphism" todo item (superseded)  
**Spec date:** 2026-06-18

---

## Motivation

Today, satisfying an interface always requires an explicit `impl` block, even
when the implementation is fully determined by functions that already exist in
scope. This creates ceremony that obscures intent:

```march
interface Named(a) do
  fn name(a) -> String
end

type User = { name: String, email: String }

-- User already has a `.name` field. You still must write:
impl Named(User) do
  fn name(u) do u.name end
end
```

Multiply this by a library that defines ten protocol interfaces and five
concrete types, and you get fifty trivial `impl` blocks that add no
information.

The original remedy considered was **row polymorphism** — open record types
with row variables (`{ name: String | r }`). That was ruled out because it
adds significant type-system complexity (row unification, row-variable
constraint propagation, complex error messages) for ergonomic gains that
March's existing interface + monomorphization system already largely covers.
The specific row-polymorphism use case — accessing a field on a polymorphic
type variable — is addressed more narrowly and cheaply by Feature 2 below.

---

## Two Independent Features

The problem splits cleanly into two separable features with different scope,
LoE, and risk. They can be designed, implemented, and shipped independently.

---

## Feature 1: `satisfy` — Opt-In Structural Impl Generation

### Design

A new declaration form that instructs the desugar pass to synthesize an
`impl` block by looking up matching functions already in scope:

```march
satisfy Named for User
```

is exactly equivalent to writing:

```march
impl Named(User) do
  fn name(u) do u.name end   -- synthesized: calls existing name/1
end
```

provided `fn name(User) -> String` exists in the current module. The
synthesized method body is a direct forwarding call to the existing function.

Multiple types and multiple interfaces can be listed together:

```march
satisfy Named for User, Post, Comment
satisfy Eq, Show for Color
satisfy Serializable, Renderable for Widget, Panel, Button
```

### Syntax

```
satisfy_decl ::= 'satisfy' iface_list 'for' type_list

iface_list   ::= upper_name (',' upper_name)*
type_list    ::= type_name (',' type_name)*
```

`satisfy` is a reserved keyword. It does not conflict with any existing
keyword or common identifier.

### Semantics

The desugar pass (`lib/desugar/desugar.ml`) expands each `satisfy Iface for T`
into a `DImpl` node before typechecking. The expansion algorithm:

1. Look up interface `Iface` in the module's declarations (both above and below
   — desugar already sees the full decl list).
2. For each method `m : T -> R` declared in `Iface` (with `T` substituted for
   the interface's type parameter):
   a. Search the module's `DFn` declarations for a function whose name matches
      `m` and whose arity matches the interface method.
   b. If found: emit `fn m(args...) do existing_m(args...) end` in the `DImpl`.
   c. If not found: emit a compile error at the `satisfy` site:
      ```
      error: `satisfy Named for User` requires `fn name(User) -> String`
             but no such function is defined in this module.
             Define `fn name(u: User) -> String` before the satisfy declaration.
      ```
3. The resulting `DImpl` is identical in structure to a hand-written one and
   goes through the normal `DImpl` typecheck path unchanged.

### What It Covers

- Record-backed accessor delegation: `type User = { name: String, ... }` with
  `fn name(u) do u.name end` already defined.
- Newtype wrappers: `type Meters = Meters(Float)` with `fn value(Meters(f)) do f end`.
- Multi-method interfaces where all methods already exist as standalone functions.
- `derive`-style shorthand: `satisfy Eq, Show for Color` when `eq` and `show`
  are already defined (as an alternative to `derive` when the logic is custom
  but the wiring is mechanical).

### What It Does NOT Cover

- Cases where the impl method has different logic from a same-named function.
- Cases where method names differ from existing function names (no renaming).
- Types or interfaces from other modules — the same orphan rule applies:
  you can `satisfy Iface for T` only in the module that owns `T` or the module
  that owns `Iface`. This is enforced identically to `impl`.
- Default method injection — if the interface has default methods, they are
  inherited exactly as with a hand-written `impl`.

### Interaction with `derive`

`satisfy` and `derive` are complementary:

| | `derive` | `satisfy` |
|---|---|---|
| Logic | Compiler generates structural impl | User writes functions, compiler wires them |
| When to use | Standard structural behavior (Eq, Ord, Show, Json) | Custom logic already exists as free functions |
| Methods | All methods generated automatically | All methods must already exist in scope |

They can co-exist: `derive Eq for Color` and `satisfy Show for Color` on the
same type are both valid.

### Coherence and Orphan Rules

`satisfy` is syntactic sugar over `impl`. All existing coherence rules apply:

- No duplicate impls: `satisfy Named for User` fails if `impl Named(User)` or
  another `satisfy Named for User` already exists.
- Orphan rule: must be in the module owning `Named` or `User`.
- `when` constraints: not supported in the initial version of `satisfy`. If the
  impl requires constraints (e.g., `when Eq(a)` for `impl Named(List(a))`),
  write an explicit `impl` block.

`when` constraint support can be added later without breaking existing `satisfy`
declarations.

---

## Feature 2: Record Field Auto-Satisfy

### Design

A zero-declaration rule applied during constraint discharge: when the compiler
needs to satisfy `CInterface("Named", TRecord[("name", TString); ...])`, it
checks if the constraint can be discharged purely from the record's field
structure without any `impl` in scope.

This allows anonymous record literals to satisfy single-method accessor
interfaces transparently:

```march
interface Named(a) do
  fn name(a) -> String
end

-- No impl, no satisfy. This just works:
fn greet(x) when Named(x) do "Hello, " ++ name(x) end
fn main() do greet({ name = "Alice", email = "a@a.com" }) end
```

### Eligibility Rules

Auto-satisfy applies **only** when all of the following hold:

1. **Anonymous structural record** — the target type is `TRecord` (not a named
   `TCon` alias like `User`). Named types still require `impl` or `satisfy`.
2. **Single-method interface** — the interface declares exactly one method.
3. **Accessor-shaped method** — the method signature is `a -> T` (one argument,
   the interface parameter itself; no additional arguments).
4. **Exact field match** — the record has a field whose name matches the method
   name and whose type unifies with `T`.

If any rule is violated, the standard "does not implement interface" error is
emitted unchanged.

### Why These Constraints

**Anonymous records only:** Named type aliases (`type User = { name: String }`)
already have a stable identity. Requiring explicit `impl`/`satisfy` for named
types prevents accidental satisfaction ("my `Widget` type now silently satisfies
`Http.Respondable` because it happens to have a `respond` field"). Anonymous
records are ad-hoc; their structural nature is expected.

**Single-method only:** Multi-method auto-satisfy requires finding N independent
field matches for N methods, which can produce surprising cross-field coupling
("this record satisfies `Serializable` because it has both `encode` and `decode`
fields, but they're unrelated String fields used for display"). Single-method
keeps the rule local and obvious.

**Accessor shape only:** Methods of the form `a -> T` are unambiguously field
reads. Methods with additional parameters, multi-argument methods, or methods
returning the type itself (`a -> a`) are not accessors and require explicit
impls.

### Implementation: `discharge_constraints`

The change lives entirely in `lib/typecheck/typecheck.ml` in the
`discharge_constraints` function, inside the `CInterface` match arm:

```ocaml
(* After the standard impl lookup fails: *)
| CInterface (iface_name, t) ->
  let ty = repr t in
  (match ty with
   | TVar _ -> ()   (* still polymorphic *)
   | TRecord flds ->
     (* Try record auto-satisfy before emitting an error *)
     let auto_satisfied =
       match StrMap.find_opt iface_name env.interfaces with
       | Some iface when List.length iface.iface_methods = 1 ->
         let m = List.hd iface.iface_methods in
         (match m.md_ty with
          | Ast.TyArrow (Ast.TyVar p, ret_ty)
            when p.txt = iface.iface_param.txt ->
            let expected_field_ty = surface_ty env ret_ty in
            (match List.assoc_opt m.md_name.txt flds with
             | Some fld_ty -> (try unify_silent env fld_ty expected_field_ty; true
                               with _ -> false)
             | None -> false)
          | _ -> false)
       | _ -> false
     in
     if not auto_satisfied then
       Err.error env.errors ~span
         (Printf.sprintf "`%s` does not implement interface `%s`." ...)
   | _ ->
     (* existing error path *) ...)
```

No new AST nodes, no desugar changes, no new keywords. Pure typechecker change.

### Interaction with Explicit Impls

Explicit `impl Named(SomeNamedType)` continues to work exactly as before.
Auto-satisfy is purely additive — it only fires for anonymous `TRecord` types
and only when there is no explicit impl in scope. The priority is:

1. Explicit `impl` in `env.impls` — always wins
2. `satisfy`-generated `impl` — same as explicit (both go through `env.impls`)
3. Record auto-satisfy — fires only when 1 and 2 are absent

---

## Error Messages

### `satisfy` — missing method

```
error[E0421]: `satisfy Named for User` is missing method `name`
  --> src/user.march:12:1
   |
12 | satisfy Named for User
   | ^^^^^^^^^^^^^^^^^^^^^^
   |
   = interface `Named` requires: fn name(User) -> String
   = no function `name` taking `User` as its first argument is defined in this module
   = define `fn name(u: User) -> String` above the satisfy declaration, or write
     an explicit `impl Named(User) do ... end`
```

### `satisfy` — type mismatch

```
error[E0422]: method `name` in `satisfy Named for User` has wrong type
  --> src/user.march:8:1
   |
 8 | fn name(u: User) do u.email end
   |                     ------- returns String (ok)
...
12 | satisfy Named for User
   | ^^^^^^^^^^^^^^^^^^^^^^
   |
   = interface `Named.name` expects: User -> String
   = found: User -> String  (this would actually be fine — example shows mismatch)
```

### Feature 2 — no field match

```
error[E0423]: anonymous record does not implement `Named`
  --> src/main.march:5:7
   |
 5 | greet({ email = "a@a.com", age = 30 })
   |        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   |
   = interface `Named` requires a field `name: String`
   = this record has fields: email: String, age: Int
   = add `name: String` to the record, or implement `Named` explicitly
```

---

## Implementation Plan

### Phase A — Feature 2: Record auto-satisfy

**Estimated effort: 0.5–1 day**

Files changed:
- `lib/typecheck/typecheck.ml` — `discharge_constraints`: ~30 lines added in
  the `CInterface` arm for anonymous `TRecord` types.

Tests to add (in `test/test_march.ml`, new group `record_auto_satisfy`):
1. Single-method interface + anonymous record with matching field → ok
2. Single-method interface + anonymous record with wrong field type → error
3. Single-method interface + anonymous record missing field → error
4. Multi-method interface + anonymous record → error (auto-satisfy not
   applicable; requires explicit impl)
5. Non-accessor-shaped method (binary) + anonymous record → error
6. Named type alias (`TCon`) does not auto-satisfy → error
7. Named type with explicit `impl` still works → ok
8. Auto-satisfy inside `when Named(x)` constraint → ok
9. Auto-satisfy with generic function, multiple record shapes at monomorphized
   call sites → ok (each site satisfies independently)

### Phase B — Feature 1: `satisfy` keyword

**Estimated effort: 1.5–2 days**

Files changed:
- `lib/lexer/lexer.mll` — add `satisfy` keyword token (`SATISFY`).
- `lib/parser/parser.mly` — add `satisfy_decl` production in the top-level
  decl rule; emit `DSatisfy of name list * name list * span`.
- `lib/ast/ast.ml` — add `| DSatisfy of name list * name list * span` to
  `decl`.
- `lib/desugar/desugar.ml` — add `expand_satisfy` function; called from
  `desugar_module` alongside `expand_derive`. Searches module decls for
  matching functions and synthesizes `DImpl` blocks.
- `lib/typecheck/typecheck.ml` — pass-through in `prebind_mod_members` and
  `check_decl` (`DSatisfy` will already be expanded; add a no-op arm or
  assert it's never seen post-desugar).
- `lib/errors/errors.ml` — no changes needed; new diagnostics emitted inline.

Tests to add (new group `satisfy_decl`):
1. Basic single-method `satisfy` → typechecks, method callable
2. `satisfy` for multi-method interface where all methods exist → ok
3. `satisfy` for multi-method interface with one missing → error, names missing method
4. `satisfy` for multiple types: `satisfy Named for A, B, C`
5. `satisfy` for multiple interfaces: `satisfy Eq, Show for Color`
6. `satisfy` after `impl` already exists → error (duplicate impl)
7. `satisfy` in wrong module (orphan) → error
8. Generated `impl` callable from another module via `when Named(x)`
9. `satisfy` with record accessor (field delegation) pattern
10. `satisfy` with newtype unwrap function
11. `derive` and `satisfy` for the same type, different interfaces → ok

### Ordering

Phase A first: it's smaller, zero syntax surface, validates the ergonomic
story before committing to a new keyword.

---

## Examples

### Record accessors (Feature 1)

```march
interface Named(a) do
  fn name(a) -> String
end

interface HasAge(a) do
  fn age(a) -> Int
end

mod User do
  type T = { name: String, age: Int, email: String }

  fn name(u) do u.name end
  fn age(u) do u.age end
  fn email(u) do u.email end

  satisfy Named, HasAge for T
end

fn describe(x) when Named(x), HasAge(x) do
  name(x) ++ " (age " ++ to_string(age(x)) ++ ")"
end

fn main() do
  println(describe(User.T { name = "Alice", age = 30, email = "a@a.com" }))
end
```

### Anonymous record duck-typing (Feature 2)

```march
interface Labelled(a) do
  fn label(a) -> String
end

fn print_label(x) when Labelled(x) do
  println(label(x))
end

fn main() do
  -- Both records auto-satisfy Labelled via their `label` field:
  print_label({ label = "inbox", count = 42 })
  print_label({ label = "sent", unread = false })
end
```

### Newtype wrappers (Feature 1)

```march
interface Measure(a) do
  fn value(a) -> Float
  fn unit_name(a) -> String
end

mod Meters do
  type T = Meters(Float)
  fn value(Meters(f)) do f end
  fn unit_name(_) do "m" end
  satisfy Measure for T
end

mod Seconds do
  type T = Seconds(Float)
  fn value(Seconds(f)) do f end
  fn unit_name(_) do "s" end
  satisfy Measure for T
end

fn format_measure(m) when Measure(m) do
  to_string(value(m)) ++ " " ++ unit_name(m)
end
```

### Web framework (Feature 1)

```march
-- In the bastion library:
interface Respondable(a) do
  fn to_conn(a) -> Conn
end

-- In user code, after defining their response helpers:
satisfy Respondable for JsonResponse, HtmlResponse, Redirect
```

---

## Non-Goals

- **Full structural subtyping** — `satisfy` and record auto-satisfy are both
  explicit/narrow. This is not Go's implicit interface model applied globally
  to all named types.
- **Renaming** — `satisfy Named for User using fn display_name` is out of scope;
  method names must match exactly.
- **`when` constraints in `satisfy`** — deferred. `satisfy Eq for List(a)` with
  an implicit `when Eq(a)` constraint requires type-variable inference in the
  expansion that is non-trivial. Write `impl Eq(List(a)) when Eq(a) do ... end`
  for parameterized cases.
- **Cross-module structural satisfaction** — no implicit satisfaction of
  interfaces the type author doesn't know about. Orphan rules unchanged.
