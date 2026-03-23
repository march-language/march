# Standard Interfaces (Eq / Ord / Show / Hash)

## Overview

March defines four standard interfaces that ADTs can automatically derive via a `derive` annotation. These replace the need for manually writing boilerplate `impl` blocks for equality, ordering, display, and hashing.

## Implementation Status

**Implemented on branch `claude/intelligent-austin` — pending merge to main.**

The implementation adds:
- `derive [Eq, Ord, Show, Hash]` surface syntax
- `DDeriving` AST node
- Lexer/parser support
- Eval dispatch via `impl_tbl` for `==`, `show`, `hash`, `compare`
- Desugar expansion of `DDeriving` into concrete `DImpl` blocks

## Superclass Constraints

**Implemented on main.** The `DInterface` AST node includes `iface_superclasses`:

```ocaml
(* lib/ast/ast.ml:261 *)
iface_superclasses : (name * ty list) list;
```

The type checker verifies superclass satisfaction when processing `DImpl` declarations (`lib/typecheck/typecheck.ml:3098–3121`):
- When you implement interface `B` for type `T`, and `B` requires superclass `A`, the checker verifies an `impl A(T)` already exists in scope.
- Multi-param superclasses are not yet supported (single-param only).

## Surface Syntax (after merge)

```march
-- Derive Eq and Show automatically
type Color = Red | Green | Blue
derive [Eq, Show] for Color

-- Derive all four
type Point = { x : Int, y : Int }
derive [Eq, Ord, Show, Hash] for Point
```

## Interface Definitions

```march
interface Eq(a) do
  fn eq(x : a, y : a) : Bool
end

interface Ord(a) when Eq(a) do
  fn compare(x : a, y : a) : Int   -- negative, 0, positive
  fn lt(x : a, y : a) : Bool
  fn gt(x : a, y : a) : Bool
end

interface Show(a) do
  fn show(x : a) : String
end

interface Hash(a) when Eq(a) do
  fn hash(x : a) : Int
end
```

## Implementation Files (on branch `claude/intelligent-austin`)

| File | Purpose |
|---|---|
| `lib/ast/ast.ml` | `DDeriving` node added to `decl` variant |
| `lib/lexer/lexer.mll` | `DERIVE` keyword token |
| `lib/parser/parser.mly` | `derive_decl` grammar rule |
| `lib/desugar/desugar.ml` | Expand `DDeriving` → concrete `DImpl` methods |
| `lib/eval/eval.ml` | `impl_tbl` dispatch for `==`, `show`, `hash`, `compare` |

## Eval Dispatch (existing — main branch)

The eval interpreter already has an `impl_tbl` for interface dispatch (`lib/eval/eval.ml:138`):

```ocaml
let impl_tbl : (string * string, value) Hashtbl.t = Hashtbl.create 8
```

`impl_tbl` maps `(interface_name, type_name)` → closure. The `Drop` interface is already dispatched this way. Once merged, `Eq`/`Ord`/`Show`/`Hash` will use the same mechanism.

## Merge Blockers

- Needs review and testing before merging to main
- Should add tests in `test/test_march.ml` for derive syntax and dispatch correctness
