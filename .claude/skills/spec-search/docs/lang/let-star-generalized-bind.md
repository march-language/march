> Part of the March Language Reference; see [specs/lang/index.md](index.md).

# `let*`: Generalized Monadic Bind

**Status:** Implemented, shipped, and conformance-tested (2026-08-14).
`let* p = e1; e2` binds the result of applying `e1`'s type's `flat_map` to a
callback that pattern-matches `p` against the payload and runs `e2`. It
generalizes [`let?`](let-propagation.md) (`Result`-only) to any type with a
same-named module exporting `flat_map`: `Option`, `Result`, `List`, and any
user-defined type following the same convention. Corpus:
`specs/lang/types/{accept/t177-t178, reject/t178-t179}`,
`specs/lang/grammar/{parse/p35, reject/r16}`, golden `g47`. Design history:
`specs/plans/2026-08-09-parsing-and-string-search.md` §4.3, §9 decision 5.

**Depends on:** any type `M` with a module of the same name exporting
`flat_map(x : M(a), f : a -> M(b)) : M(b)`.

---

## 1. Why this exists, and why it's shaped the way it is

`let?` propagates `Result`; see [`let-propagation.md`](let-propagation.md)
§1 for the motivating gap (`with` without `else` panics instead of
propagating). `let*` asks the same question one level up: **the exact same
propagate-or-continue shape is useful for `Option`, `List`, and any parser
combinator type, not just `Result`.** Hardcoding a second, third, fourth
`let??`/`let!!` for each would repeat `let?`'s implementation with the
constructor names swapped: not a generalization, just more copies.

The obvious generalization, a `Bind`/`Monad` interface with
`Self(a) -> (a -> Self(b)) -> Self(b)`, **does not fit March's type
system.** `interface Name(param)` takes exactly one type parameter
(`lib/parser/parser.mly:838`); `Self` is never applied to a type argument
anywhere in the language. There is no higher-kinded apparatus, and adding it
for this one feature would be a much larger, much riskier change than the
feature itself.

So `let*` does what `let?` already does: it is a **native AST node,
typechecked and lowered natively**, exactly like `let?`. The difference is
that `let?` hardwires `Result`, and `let*` instead asks, at typecheck time,
"what is `e1`'s type, and does a module of that name export `flat_map`?"

## 2. The dispatch convention

`let* p = e1; e2`'s `M` is `e1`'s inferred type's head type constructor:
`Option(a)` → `Option`, `Result(a, e)` → `Result`, `List(a)` → `List`. `M`'s
`flat_map` is resolved by the same convention the whole standard library
already follows without exception for its container types: **the module
sharing the type's name owns that type's operations** (`Option.flat_map`,
`Result.flat_map`, `List.flat_map` all already existed as ordinary stdlib
functions before `let*`, for exactly this reason; no part of them is
`let*`-specific).

This is a real convention the design leans on, but it is **not compiler-enforced**
outside of `let*` itself: no rule prevents a module from being named
differently than its primary type. `let*` is the first thing in the compiler
that actually depends on it holding. When it doesn't hold, `let*` cannot find
`M.flat_map` and reports a clear, actionable error naming exactly what's
missing (§5), not a crash or a silent fallback.

The combinator library was the one place in the stdlib that broke the
convention: its type was `Parser` but its module was `Parse`, so `let*`, a
feature with a *parser* as its own motivating example, did not work with it.
Resolved 2026-08-17 by renaming the module to `Parser`, so the type and
module names agree the way they already do for `Option`/`Result`/`List`
(`specs/progress/2026-08-17-letstar-followups.md`). Corpus witness:
`specs/lang/types/accept/t185_letstar_parser_combinator.march`.

The alternative, teaching `let*` a second resolution path (e.g. falling back
to the module that DECLARES the type), was considered and not taken. It would
avoid the `Parser.Parser(a)` stutter an external type annotation now reads
with, but the resolution is duplicated across three layers (typecheck, TIR
lowering, and the interpreter, each with its own tables), and this codebase
has repeatedly been bitten by exactly that shape of multi-site walker drifting
apart; see `lib/ast/calls.ml`'s header, where the drift was fail-OPEN. The
rename needs no compiler change at all. If a second library at some point wants to
break the convention, revisit it then, with one decision rather than two.

## 3. Type checking

`lib/typecheck/typecheck.ml`'s `infer_expr`, `Ast.ELetStar` case:

1. If the continuation is an empty block (`let*` is the last expression),
   reject immediately, on the same reasoning as `let?`: there is no way to unify
   an empty block's `()` against `M(b)` and get a message that points at
   the real problem.
2. Infer `e1`'s type, `result_ty`.
3. `repr result_ty` must reduce to `TCon(head_name, _)`, a concrete type
   constructor. A bare, still-ambiguous type variable is rejected with a
   message asking for a concrete type, since there is no type name to look up
   `flat_map` against yet.
4. Resolve `head_name ^ ".flat_map"` via the same qualified-name resolution
   an ordinary `Option.flat_map(...)` call already goes through
   (`resolve_qualified_var`), so this can never see a different `flat_map`
   than a hand-written qualified call would. Missing → the error in §5.
5. Instantiate that scheme. It's expected to destructure as
   `M_arg -> (A -> M_b1) -> M_b2`: unify `result_ty` against `M_arg` (this
   is what actually pins down `M`'s other type parameters, e.g. `Result`'s
   error type, with no arity assumptions baked into `let*` itself), unify
   `M_b1` against `M_b2`, type `p` against `A`, and type the continuation
   against `M_b2`. The `let*` expression's own type is `M_b2`.

Because step 5 never hand-constructs `M(...)` itself (it only unifies
against whatever shape the real `flat_map` scheme has), this works
correctly for `Result(a, e)` (two type parameters, the second held fixed)
exactly as well as `Option(a)` (one), with no special-casing either way.

## 4. Lowering and evaluation

**Compiled (`lib/tir/lower.ml`):** `let* p = e1; e2` is rewritten into an
ordinary call, `M.flat_map(e1, fn $tmp -> match $tmp do p -> e2 end end)`,
and re-lowered through the normal `EApp`/`ELam`/`EMatch` path. `M` comes
from `e1`'s type in the typechecker's `type_map` (the same table
monomorphization already reads to resolve interface-method dispatch), not
re-inferred. This is why `let*` needs no new TIR node, no new codegen, and
no new runtime support at all: by the time lowering sees it, it's already
an ordinary function call.

**Interpreted (`lib/eval/eval.ml`):** the interpreter has no compile-time
type info, so it dispatches on the *runtime value's* type instead:
`type_name_of_value` (the same primitive `hash`/`to_json`'s own dynamic
dispatch already uses) on `e1`'s evaluated value, then an ordinary env
lookup of `<Type>.flat_map`. The continuation is passed to it as a native
closure value (`VBuiltin`) that performs the pattern match and evaluates
`e2`; `apply` already dispatches a `VBuiltin` exactly like a March closure,
so `flat_map`'s own March body calling `f(x)` invokes it transparently.

## 5. Diagnostics

- **Trailing `let*`** (empty continuation):
  ```
  `let*` cannot be the last expression in a block.
  Add an expression of the same type as the right-hand side after it — ...
  ```
- **RHS type still ambiguous:**
  ```
  `let*`'s right-hand side must have a concrete type (e.g. `Option(a)`,
  `Result(a, e)`) so `let*` can find its `flat_map` — its type could not be
  determined here.
  ```
- **No matching `flat_map`:**
  ```
  `let*` needs `<Type>.flat_map`, but it doesn't exist.
  Define `flat_map(x : <Type>(a), f : a -> <Type>(b)) : <Type>(b)` in a
  module named `<Type>` to make `let*` work with `<Type>`.
  ```
- **Wrong-shaped `flat_map`** (exists, but not `M(a) -> (a -> M(b)) -> M(b)`):
  ```
  `<Type>.flat_map` doesn't have the shape `let*` needs: `<Type>(a) -> (a ->
  <Type>(b)) -> <Type>(b)`.
  ```

## 6. What's explicitly out of scope

- ~~**The REPL.**~~ **Shipped 2026-08-17.** `let* p = e` at a prompt binds
  through the value's own `flat_map` (`ReplLetStar`, `Typecheck.
  check_letstar_repl`, `Eval.letstar_repl_bind`), in the terminal REPL, the
  notty TUI and the browser REPL. There is no continuation at a prompt, so
  the binding runs `flat_map` with a callback that captures the FIRST value
  yielded and returns the original monadic value, well-typed as the
  callback's `M(b)` for any `M` without needing a generic `pure` the language
  does not have. For `Option`/`Result` "first" is just "unwrap"; for `List`
  it is the reading `let* x = [1,2,3]` suggests. A value that yields no result
  (`None`, `Err`, `[]`) binds no value and reports as much rather than silently
  succeeding.
- **`stdlib/parse.march`'s `Parser` type**, per §2 above.
- **A `let*`/`let?` unification.** The parsing-and-string-search plan (§9
  decision 5) left open whether `let?` should eventually be re-expressed as
  `let*` specialized to `Result`. They still coexist as separate AST nodes:
  `let?`'s three bespoke diagnostics and its match-based (not
  `flat_map`-based) lowering are unaffected by `let*` existing alongside it.
