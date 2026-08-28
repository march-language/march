# Core March: Reference v1 (core fragment complete)

**Date:** 2026-07-04 (v0 walking skeleton) → 2026-07-05 (v1 consolidation)
**Status:** Reference v1: the **complete CORE fragment** of the March language
specification, assembled and versioned from the seven incremental slices
(Tasks 1–7) that grew it end-to-end. This is the CORE, not the whole language:
the deferred set (§6) is still real and is now exactly the roadmap's Phase-2/3
queue.
**Depends on:** the language-specification roadmap design spec
(`specs/archive/2026-07-04-language-specification-roadmap-design.md`), which framed this
document as its Phase-1 first artifact, and the Phase-1 task plan
(`specs/plans/archive/2026-07-05-core-march-phase1-plan.md`) that Tasks 1–9 executed.

---

## 0. What this is (and is not)

This document specifies the **complete core fragment** of March across the
*entire* spec stack:

1. the **core grammar** (§2),
2. the **surface → core desugaring map** (§3),
3. the **operational semantics** (§4), and
4. a **golden conformance corpus** verified interpreter-vs-compiled (§5).

The core covered here is: literals and the `Int`/`Bool`/`Float`/`String`/atom
primitives with their full δ-rule table (`+`, `-`, `*`, `/`, `%`, comparisons,
`&&`/`||`/`not`, `++`, unary `negate`); `let`, lambda + application, and
higher-order functions; **tuples**, **records** (literals, field access,
functional update), and **atoms** (nullary + payload-carrying); the **full
pattern language** with guards and the exhaustiveness/`Match_failure` rule;
**local recursive functions** (`ELetFn`, the env-ref recursive knot); and
**conditionals** (`if`/`else` and the scrutinee-less `match do c -> b … end`
boolean chain). Every one of these is grounded arm-for-arm in `eval.ml` (§4) and
anchored by the golden corpus (§5).

Its original purpose was to prove the *method*: that a normative spec can be
extracted faithfully from the existing implementation and kept accurate by the
differential oracle. That method held across all seven widening slices, and this
v1 is their consolidation into one coherent reference.

**Widening slice (2026-07-06):** §4.4.2 extends the primitive-dispatch material
above with **method dispatch**: how a call like `speak(d)` or `show(v)`
resolves to a specific `impl`'s method body at runtime, as opposed to how the
typechecker determines a suitable `impl` exists at all (`core-march-types.md`
§2.1a/§2.3, unchanged by this addition). The built-in type-directed interfaces
(`Show`/`Eq`/`Ord`/`Hash`) dispatch through a real runtime hashtable
(`impl_tbl`, keyed `(iface, type_name)`); user-defined interfaces get no such
table at all and resolve through the same ordinary lexical `env` binding §4.1
already specifies for every other name, which is exactly why overlapping
user-interface impls are "just shadowing," not a designed policy. The
coherence/overlap divergence this causes (and how the COMPILED backend
resolves the same overlap differently) is documented in full in §4.4.3, with
`derive`/`satisfy`-generated impls' identical treatment in §4.4.4; both land
in this same widening slice, cross-referenced from §4.4.2 rather than
repeated there.

**Widening slice (2026-07-06, modules):** §4.7 adds **module declaration,
nesting, and name resolution**: how `mod Name do … end` evaluates and
exports its declared names as `"Name.member"` into the enclosing scope, why a
bare (unqualified) reference never resolves into a sibling nested module
while a qualified one does, the lexical-scoping nuance that makes a private
`pfn` callable bare from a module nested directly inside its declaring
module, and the grammar-level one-mod-per-file rule. Cross-module VISIBILITY
enforcement (`pfn`/`ptype` privacy) is a TYPECHECK-time concept
(`core-march-types.md`'s corresponding Task 3 section): §4.7 states
exactly that the evaluator's own export gate (`own_names`, declared-by-
this-module) is not the same, narrower gate typecheck applies (`pub_set`,
declared-PUBLIC-by-this-module), so privacy is enforced before eval even
runs, not by eval itself.

**It is not** the whole language semantics. The CORE covers the pure,
value-level reduction fragment; everything outside it (strings as first-class
data (beyond their appearance in the value grammar), `to_string`/`show` and the
interface-dispatch mechanism, effects/IO ordering, actors, refinements,
capabilities, the Perceus RC discipline, session types, sigils) is explicitly
**deferred** to Phase 2/3 (see §6). Each deferred group becomes a widening slice
like Tasks 1–7 did.

Every rule below is grounded in a specific line of the implementation. Where a
rule states "faithful to `eval.ml:N`", that citation *is* the correctness
argument, and the golden corpus (§5) is its executable check.

## 1. The core is the desugared AST; `eval.ml` is its reference semantics

**Decision (locked for the whole spec effort):** *Core March* is the AST as it
exists **after the desugar pass**, and the tree-walking interpreter
(`lib/eval/eval.ml`) is its **reference operational semantics**.

This is grounded, not invented. The compiler pipeline is
parse → desugar → typecheck → eval (`bin/main.ml:772`–`807`): the interpreter's
entry point `eval_module_env (m : module_)` (`eval.ml:8409`) consumes exactly
the `module_` value that `March_desugar.Desugar.desugar_module` produces: the
same `Ast.expr` type, after sugar has been removed. The TIR → LLVM path
(`Lower.lower_module`, the `--compile` branch) is a *separate* consumer of that
same desugared AST, which is why the differential oracle can hold the two
backends to a single reference.

Consequences:

- The **desugaring map** (§3) is read from `desugar.ml`; the **operational
  rules** (§4) are read from `eval.ml`. Both describe the *same object* (the
  desugared AST) from its two sides: how it is produced, and what it means.
- We are **documenting an existing core, not designing a new one.** There is no
  gap to defend between "the spec's core" and "what March runs."

## 2. Core grammar (the fragment)

The fragment's abstract syntax, as the constructors of `Ast.expr` /
`Ast.pattern` / `Ast.literal` (`lib/ast/ast.ml:32`–`110`). Spans are elided.

```
literal  ℓ  ::= LitInt n | LitFloat f | LitString s | LitBool b | LitAtom a
                                                            (ast.ml:32–37)

expr     e  ::= ELit ℓ                                      -- literal
             |  EVar x                                      -- variable
             |  ELam [x…] e                                 -- lambda (n params)
             |  EApp e [e…]                                 -- application
             |  ECon C [e…]                                 -- constructor application
             |  ETuple [e…]                                 -- tuple construction (ast.ml:60)
             |  ERecord [(f = e)…]                          -- record literal (ast.ml:61)
             |  ERecordUpdate e [(f = e)…]                  -- functional record update (ast.ml:62–63)
             |  EField e f                                  -- field access: e.f (ast.ml:64)
             |  EBlock [e…]                                 -- do … end sequence
             |  ELet (p = e)                                -- block-scoped binding
             |  ELetFn f [x…] e                             -- local recursive fn (ast.ml:77)
             |  EMatch e [ p when g? -> e … ]               -- pattern match
             |  EIf e e e                                   -- if c do … else … end
             |  ECond [(e_cond, e_body)…]                   -- scrutinee-less boolean match: match do c -> b … end (ast.ml:66)
             |  EAtom a [e…]                                -- atom expression: :ok, :error(x) (ast.ml:70)
                                                            (ast.ml:51–91)

pattern  p  ::= PatWild | PatVar x | PatLit ℓ | PatCon C [p…]
             |  PatTuple [p…]                                -- tuple pattern: (p…) (ast.ml:45)
             |  PatRecord [(f = p)…]                         -- record pattern: { f, … } (ast.ml:47)
             |  PatAtom a [p…]                                -- atom pattern: :ok, :error(x) (ast.ml:44)
                                                            (ast.ml:40–48)

value    v  ::= VInt n | VFloat f | VString s | VBool b | VAtom a
                                                            (eval.ml:32–37)
             |  VClosure ρ [x…] e                           -- closure: env + params + body
             |  VCon C [v…]                                 -- constructor value: tag + payload
             |  VTuple [v…]                                 -- tuple value: fixed-arity value list (eval.ml:39)
             |  VRecord [(f = v)…]                          -- record value: field-name/value assoc list (eval.ml:40)
             |  VBuiltin name f                             -- primitive (e.g. +, ==)
```

**`EAtom`/`PatAtom` are a single AST node parameterized by an optional
payload, not two separate nullary/payload constructors.** `Ast.expr`'s
`EAtom of string * expr list * span` (`ast.ml:70`) and `Ast.pattern`'s
`PatAtom of string * pattern list * span` (`ast.ml:44`) both carry a `string`
tag plus an **argument/sub-pattern list** that is empty for a nullary atom
(`:ok` ⇒ `EAtom("ok", [], _)`) and non-empty for a payload-carrying one
(`:error(x)` ⇒ `EAtom("error", [x], _)`), confirmed by the parser
productions that build them: `parser.mly:1211–1212` (`ATOM LPAREN args RPAREN`
⇒ `EAtom(a, args, …)`) and `:1213–1214` (bare `ATOM` ⇒ `EAtom(a, [], …)`) on
the expression side; `parser.mly:1316–1317` and `:1318–1319` mirror this for
`PatAtom` on the pattern side. The lexer produces the `ATOM` token directly
from a `:`-prefixed identifier (`lexer.mll:122`, `':' (atom_name as a) {
ATOM a }`): there is no separate token for "atom-with-payload" vs.
"nullary atom"; the distinction is made entirely by which grammar production
matches (whether a `(` follows).

**`LitAtom` (inside `ELit`/`PatLit`) is a *different*, narrower construct
than `EAtom`/`PatAtom`, and, like `PatRecord` (§2 above), is dead code from
the parser's perspective at this AST level.** `Ast.literal`'s `LitAtom of
string` (`ast.ml:37`) has its own `eval_expr` arm (`ELit (LitAtom a, _) ->
VAtom a`, `eval.ml:6949`) and its own `match_pattern` arm (`PatLit (LitAtom
a, _), VAtom b when a = b -> Some []`, `eval.ml:781`, already stated in
§4.3's literal-match table), so the interpreter is fully prepared to
evaluate/match an `ELit(LitAtom _)`/`PatLit(LitAtom _)` node if one exists.
But grepping `parser.mly` for `LitAtom` finds **zero** occurrences: no rule
in the grammar constructs one from surface `:ok` syntax: both the
expression and pattern productions for the `ATOM` token build `EAtom`/
`PatAtom` (above), never `ELit`/`PatLit`. A `LitAtom` node can only arise by
constructing the AST directly (e.g. a test), not by parsing a `.march`
source file: the same "implemented but unreachable from any parsed
program" situation §2 already documents for `PatRecord`. (One further
subtlety, out of this fragment's scope but worth flagging for the reader who
greps `lower.ml`: the separate TIR lowering stage, `lib/tir/lower.ml:615`,
*does* rewrite a nullary `Ast.EAtom(a, [], _)` into a `Tir.EAtom(Tir.ALit
(Ast.LitAtom a))` shape, but that rewrite happens downstream of the
desugared-AST/`eval.ml` layer this spec specifies (§1), inside the TIR pass,
so it does not contradict "`LitAtom` is dead at the parser/`eval.ml` level"
above; it is simply a different representation the compiled backend chooses
for its own IR, invisible to the interpreter.)

`ETuple`'s surface form is `(e₁, …, e_k)`: parenthesized, comma-separated
expressions, `k ≥ 2` for an actual tuple; the parser also accepts `k = 0`
(`()`), which the evaluator (§4.2, E-Tuple) treats as an alias for `VUnit`
rather than a real zero-arity `VTuple`; see the E-Tuple rule's note. There
is no 1-tuple (`(e)` parses as a parenthesized `e`, not `ETuple [e]`). `PatTuple`
mirrors this on the pattern side: `(p₁, …, p_k)` destructures a `VTuple` of the
same arity componentwise (§4.3).

**`ERecord`/`ERecordUpdate`'s surface form uses `:`, not `=`, despite what the
AST doc comments say.** `lib/ast/ast.ml`'s comments for `ERecord`/
`ERecordUpdate`/`PatRecord` (`ast.ml:47, 61–63`) show an aspirational
`{ x = 1, y = 2 }` / `{ state with count = … }` surface form, but the actual
grammar production is `record_field_expr: name = lower_name; COLON; e = expr`
(`parser.mly:1267–1268`), used by both the literal (`parser.mly:1248–1250`)
and the update (`:1251–1253`) productions. The real, working surface syntax is
**`{ x: 1, y: 2 }`** and **`{ base with f: v, … }`**, confirmed against the
committed regression fixture `test/imports/record_native/rn_entry.march`
(e.g. `{ name: "Alice", age: 30 }`, `{ built with a: 99 }`) and by hand
(`{ x = 1 }` is a parse error; `{ x: 1 }` is not). The doc comments' `=` is
stale/never-implemented; this spec documents the grammar the parser actually
accepts, per §0's "documenting an existing core, not designing a new one."

**`PatRecord` has no surface production at all: it is dead code, reachable
only by constructing the AST node directly (e.g. in a test), never by parsing
March source.** Grepping `parser.mly` for `PatRecord` finds zero occurrences;
`desugar.ml`'s three `PatRecord` arms (`:295, 997–998, 1978`) only
recurse into an *already-constructed* `PatRecord`, never build one fresh from
another surface form. The LLVM backend's own comment on this is the most
direct evidence: `lib/tir/lower_match.ml:132–138`'s `pat_tag_and_subs` arm for
`PatRecord` immediately `failwith`s with *"record patterns are not yet
compilable (…); PatRecord has no `{...}` pattern production in the grammar
today, so this indicates a pattern constructed directly rather than parsed."*
Confirmed by hand: both `let { x, y } = r` and `match r do { x, y } -> … end`
are parse errors ("I got stuck here"). The evaluator's `match_pattern` arm for
`PatRecord` (§4.3, `eval.ml:810`) and the typechecker's `infer_pattern` arm
(`typecheck.ml:2666–2675`) are both fully implemented and would work correctly
should a `PatRecord` value reach them; the gap is purely in the parser.
This spec therefore states the `PatRecord` matching rule (§4.3) for
completeness and fidelity to `eval.ml`, but no golden program in §5
exercises it, because no March **source program** can construct one. (This
form is collected with the other implemented-but-unreachable pattern form,
`PatAs`, in **§4.3.1**.)

`LitFloat`/`VFloat` carry an OCaml `float` (IEEE-754 double); `LitString`/
`VString` carry an OCaml `string`. `VAtom` likewise stores a `string` naming
the atom (surface `:ok`, `:error`, …: an interned-looking but here just a
string-valued tag). `LitFloat`/`LitString` are produced by the parser as
direct literal tokens (`FLOAT`, `STRING`, `parser.mly:1198`–`1199`) with
**no desugaring**, exactly like `LitInt`/`LitBool` (§3's `ELit` row).
`LitAtom` is spelled with the same `ATOM` token (`parser.mly:1213`) but, as
just noted above, the parser never actually builds an `ELit(LitAtom …)` from
it: it builds `EAtom`/`PatAtom` instead (see the `EAtom`/`PatAtom` note
above `LitAtom` is included in the literal/value grammars above only because
`eval.ml` has match arms ready for it, for fidelity, not because surface
syntax reaches it).

**`VAtom` (nullary) vs. a payload atom's `VCon` representation.** A bare
`:ok` evaluates to `VAtom "ok"`, a distinct value former, *not* a `VCon`.
But `:error(x)` evaluates to `VCon("error", [v])`: the **same** value
former a 0-argument-vs-N-argument *constructor* application (`ECon`) would
produce, not a variant of `VAtom` extended with a payload slot. In other
words: **whether an atom expression's value is a `VAtom` or a `VCon` is
decided purely by arity** (zero args ⇒ `VAtom`, one-or-more args ⇒ `VCon`
tagged with the atom's name): there is no `VAtom`-with-payload value shape
in the grammar at all. This is the single most critical, non-obvious
fact about atoms (see the `EAtom` evaluation rule and the `PatAtom` matching
rules below, both cited against `eval.ml`).

**`ELetFn` is a local *recursive* function, and, unlike `PatRecord`/`PatAs`,
it IS reachable from surface syntax.** `Ast.expr`'s `ELetFn of name * param
list * ty option * expr * span` (`ast.ml:77`) is a **named function bound
*inside a block***, written `fn go(params) do body end` as an `EBlock`
statement, sitting alongside `let` bindings, and its defining feature is that
its own name is in scope *within its body*, so it can call **itself**
(`go(n - 1)`). It has a real grammar production (`parser.mly:1015`–`1027`:
`FN lower_name ( params ) [ret_annot] DO block_body END` ⇒ `ELetFn(name,
params, ret, body, …)`), confirmed by hand: a `fn go(n) do … end` inside
`main` parses, interprets, and compiles+runs (see g28–g30, §5). This is the
first construct this spec adds that comes with recursive-binding semantics, and
it is the reason §4.2's block rules need one extra rule beyond E-Blk-Let.

`ELetFn` is **distinct from both** of the fragment's other two function-shaped
forms:

- from a **lambda `ELam [x…] e`** (§2 above): a lambda is an anonymous
  *expression* value that is **not self-referential**; its body's environment
  is exactly the `ρ` captured at `VClosure` creation (E-Lam), with no binding of
  the lambda to any name, so a lambda cannot recurse by name. `ELetFn` binds a
  name AND makes that name visible inside the body (the recursive knot,
  E-LetFn below).
- from a **top-level `DFn`** (a module-level `fn f(…) do … end` declaration,
  outside any block): `DFn` is a *declaration*, entered into the module's
  top-level environment before `main` runs; `ELetFn` is an *expression-level*
  statement local to one block, visible only to the rest of that block (like a
  `let`), not to the whole module.

**`ECond` is the scrutinee-*less* sibling of `EMatch`, a boolean chain, and it
IS reachable from surface syntax (like `ELetFn`, unlike `PatRecord`/`PatAs`).**
`Ast.expr`'s `ECond of (expr * expr) list * span` (`ast.ml:66`) is a list of
`(condition, body)` arm pairs, written `match do c₁ -> b₁  c₂ -> b₂  … end`:
syntactically a `match` with **no scrutinee expression between `match` and
`do`**, where the "patterns" are ordinary boolean *conditions* rather than
patterns. The parser production is `MATCH DO option(arm_sep)
separated_nonempty_list(arm_sep, cond_branch) END ⇒ ECond(bs, …)`
(`parser.mly:1075`), a distinct grammar alternative from the scrutinee-bearing
`MATCH e DO … branch … END ⇒ EMatch(…)` one line above it (`parser.mly:1073`),
so whether a `match … do … end` parses to `EMatch` or `ECond` is decided purely
by whether a scrutinee expression sits between `match` and `do`. Confirmed by
hand: `match do x > 0 -> "pos"  true -> "nonpos" end` parses, interprets, and
compiles+runs (see g31–g32, §5).

A `cond_branch` (`parser.mly:1292`–`1296`) is either `e -> body` (an arbitrary
boolean *expression* `e` as the condition) **or** a bare `_ -> body`, which the
parser desugars to `(ELit (LitBool true, …), body)` (`parser.mly:1295`–`1296`):
i.e. `_ ->` is not a wildcard *pattern* here (there is no scrutinee to match
against) but sugar for an **always-true final arm**, exactly equivalent to
writing `true -> body`. This is the idiomatic way to make an `ECond` total (see
E-Cond's all-false behavior in §4.2). `ECond` is **distinct from `EIf`**: `EIf`
is a fixed two-way branch (`ast.ml:65`, `EIf of expr * expr * expr`) with a
*mandatory* `else`, whereas `ECond` is an n-way boolean chain with **no implicit
else**; running off the end of an all-false chain is a runtime error, not a
`VUnit` default (§4.2, E-Cond). Both are grouped together as the fragment's
"conditionals" in §4.2.

Two facts that a reader coming from surface syntax must know, because they are
critical for every rule below:

- **Primitive operators are not syntax.** `a + b` is *not* a distinct node; it
  is `EApp(EVar "+", [a; b])` (parser `parser.mly:1145` for `+`, `:1136` for
  `==`). The operator name resolves, like any variable, to a `VBuiltin`
  (`eval.ml:2762` binds `"+"`, `:2805` binds `"=="`). There is no special
  "arithmetic" evaluation path: arithmetic is ordinary application of a
  built-in function value.
- **Constructor application is its own node.** `Som(7)` is `ECon("Som",[7])`,
  distinct from `EApp`: constructors build data (`VCon`), they are not called
  (`eval.ml:6977`).

## 3. Surface → core (the desugaring map)

What `desugar.ml` does to each surface form in the fragment. For this fragment
the desugarer is almost entirely the identity modulo recursion into
subexpressions: the interesting rewrites are binary operators (already done by
the parser) and multi-clause functions.

| Surface | Core form | Where |
|---|---|---|
| `a + b`, `a == b` | `EApp(EVar "+"/"==", [a; b])`, produced by the **parser**; desugar recurses but does not reshape | `parser.mly:1136,1145`; `desugar.ml:552` |
| `do let x = e₁  e₂ end` | `EBlock([ELet(x = e₁'); e₂'])`, left structural; only `bind_expr` is recursively desugared | `desugar.ml:573–593` |
| multi-clause `fn f(0) -> …  fn f(n) -> …` | **one** clause `fn f(a) -> EMatch(a, [PatLit 0 -> …; PatVar n -> …])` on a synthesized arg (tuple if arity > 1) | `desugar.ml:697–786` |
| `fn x -> e` (`ELam`) | identity (recurse body) | `desugar.ml:568–571` |
| `fn go(x…) do e end` (`ELetFn`) | **structural identity**: recurse into the body only; name/params/return-type kept verbatim. (It runs the body under `with_conn_scope (lam_params_bind_conn params)`, connection-linearity bookkeeping irrelevant to this fragment; no reshaping.) | `desugar.ml:653–657` |
| `f(e…)` (`EApp`) | identity, plus a qualified-`ECon` fold for `Mod.Ctor(args)` | `desugar.ml:552–563` |
| `C(e…)` (`ECon`) | identity (recurse args) | `desugar.ml:565–566` |
| `:ok`, `:error(e…)` (`EAtom`) | identity (recurse args; `[]` for a nullary atom) | `desugar.ml:644–645` |
| `(e…)` (`ETuple`) | identity (recurse elements) | `desugar.ml:602–603` |
| `{ f: e, … }` (`ERecord`) | identity (recurse each field's value expr; field names untouched) | `desugar.ml:605–606` |
| `{ base with f: e, … }` (`ERecordUpdate`) | identity (recurse base + each update value expr) | `desugar.ml:608–611` |
| `e.f` (`EField`) | **not** pure identity: if `e` is a chain of `ECon`/`EField` that flattens to a dotted path (a module reference, e.g. `A.B.f`), rewrite to a single qualified `EVar "A.B.f"` (or `ECon` if `f` starts uppercase, i.e. a qualified constructor); otherwise identity (recurse into `e`, keep `EField`) | `desugar.ml:613–633` |
| `match e do … end` (`EMatch`) | identity (recurse scrutinee, guards, bodies) | `desugar.ml:595–600` |
| `if c do a else b end` (`EIf`) | **identity**; `EIf` is *not* rewritten to a match on the bool | `desugar.ml:635–636` |
| `match do c -> b, … end` (`ECond`) | **identity**: recurse into each arm's condition and body; arm order preserved verbatim, NOT rewritten to nested `EIf`s. (The `_ -> b` catch-all was already turned into a `true`-condition arm by the *parser*, `parser.mly:1295–1296`, before desugar sees it.) | `desugar.ml:638–639` |
| `ELit`, `EVar` | identity | `desugar.ml:548` |
| `type C = A \| B` (`DType`) | identity; the desugarer never touches type declarations or constructors | `desugar.ml:798–800` |

The surface language's meaning is therefore: **desugar to core, then evaluate
the core by §4.**

## 4. Operational semantics

The interpreter is a **big-step** evaluator: `eval_expr : env -> expr -> value`
(`eval.ml:6943`). We present the semantics in the same big-step, environment
form, one rule per `eval_expr` arm, because that makes the "spec matches the
implementation" cross-check exact (rule ⇄ arm). §4.8 states the small-step
reduction form the eventual metatheory (`specs/lean4-metatheory-plan.md`) will
use and its relationship to this one.

### 4.1 Environment and judgment

The environment `ρ` is an **association list** of `(name, value)`
(`eval.ml:89`); lookup returns the **first** binding, so a later `let` or a
parameter **shadows** an earlier binding by prepending (`eval.ml:6873, 6896`).
The evaluation judgment is

```
    ρ ⊢ e ⇓ v          "in environment ρ, expression e evaluates to value v"
```

Evaluation is **call-by-value**, **left-to-right**, and **deterministic**
(`eval.ml:6967` evaluates the callee then `List.map` over the args in order).
Values do not reduce further; a lambda becomes a closure immediately
(`eval.ml:6987`).

### 4.2 Core rules

```
(E-Lit)     ─────────────────────                                  eval.ml:6945–6949
            ρ ⊢ ELit ℓ ⇓ 𝓋(ℓ)   where 𝓋(LitInt n)=VInt n, 𝓋(LitFloat f)=VFloat f,
                                       𝓋(LitString s)=VString s, 𝓋(LitBool b)=VBool b,
                                       𝓋(LitAtom a)=VAtom a

(E-Var)     x ↦ v ∈ ρ   (first occurrence)                        eval.ml:6951
            ────────────────────────────
            ρ ⊢ EVar x ⇓ v

(E-Lam)     ────────────────────────────────                      eval.ml:6987
            ρ ⊢ ELam [x…] e ⇓ VClosure ρ [x…] e     -- captures ρ at creation

(E-Con)     ρ ⊢ eᵢ ⇓ vᵢ   (i = 1..k, left-to-right)               eval.ml:6977
            ──────────────────────────────────────
            ρ ⊢ ECon C [e₁…e_k] ⇓ VCon C [v₁…v_k]

(E-Atom-0)  ─────────────────────────                              eval.ml:7145
            ρ ⊢ EAtom a [] ⇓ VAtom a

(E-Atom-N)  ρ ⊢ eᵢ ⇓ vᵢ   (i = 1..k, k ≥ 1, left-to-right)         eval.ml:7146–7148
            ──────────────────────────────────────
            ρ ⊢ EAtom a [e₁…e_k] ⇓ VCon a [v₁…v_k]
            -- a payload atom's value is a VCon tagged with the atom's own
               name `a`, exactly like ECon's value shape (E-Con above) —
               there is no separate "atom-with-payload" value former; see
               §2's "VAtom (nullary) vs. a payload atom's VCon
               representation" note for why this is the fragment's single
               most load-bearing atom fact

(E-Tuple)   ρ ⊢ eᵢ ⇓ vᵢ   (i = 1..k, left-to-right)                eval.ml:7004–7005
            ──────────────────────────────────────
            ρ ⊢ ETuple [e₁…e_k] ⇓ VTuple [v₁…v_k]
            -- this arm matches any non-empty list (k ≥ 1); the parser only ever
               constructs k ≥ 2 (§2), so k = 1 is unreachable from surface syntax
            -- ETuple [] ⇓ VUnit instead (k = 0 is the `()` alias, not a genuine
               0-ary VTuple)                                      eval.ml:7003

(E-Record)  ρ ⊢ eᵢ ⇓ vᵢ   (i = 1..k, left-to-right, over the fields  eval.ml:7007–7008
            as written in source order)
            ────────────────────────────────────────────────────
            ρ ⊢ ERecord [(f₁=e₁)…(f_k=e_k)] ⇓ VRecord [(f₁=v₁)…(f_k=v_k)]
            -- field names are carried verbatim (no sorting, no dedup check);
               a repeated field name produces a VRecord with a duplicate key,
               and later lookups (EField, PatRecord) find the FIRST occurrence
               (List.assoc_opt semantics) — the typechecker's ERecord case
               does not reject duplicate names either (out of this fragment's
               scope to adjudicate; noted here only as a fidelity caveat)

(E-Update)  ρ ⊢ e_b ⇓ VRecord [(f₁=v₁)…(f_n=v_n)]                  eval.ml:7010–7037
            ρ ⊢ eᵢ ⇓ uᵢ   (i = 1..m, left-to-right, over the updates
            as written in source order)
            ∀ (g, _) ∈ [(g₁=u₁)…(g_m=u_m)] . g ∈ {f₁,…,f_n}
            ──────────────────────────────────────────────────────────
            ρ ⊢ ERecordUpdate e_b [(g₁=e₁)…(g_m=e_m)] ⇓
                VRecord [(f₁=v₁')…(f_n=v_n')]
                where vᵢ' = uⱼ if fᵢ = gⱼ for some j (FIRST-listed g wins on a
                            repeated update name — `List.assoc_opt` over the
                            update list returns the first match; `{ r with x: 10,
                            x: 20 }` yields `x = 10`, eval.ml:7031–7035 — the same
                            first-occurrence convention as E-Record; note the MERGE
                            direction: for the
                            OUTPUT record it is the update side, not the base
                            side, that is consulted per base field), else vᵢ
            -- ADJUDICATED RULE (see prose below): if ANY update name g is
               NOT among the base's actual field names {f₁,…,f_n}, evaluation
               is an ERROR (`eval_error "record update: no field '%s' in
               record" g`, eval.ml:7026–7029) — the update is UNDEFINED for an
               absent field, it does NOT extend the record's shape
            -- a non-VRecord base ⇒ eval_error "record update on non-record
               value" (eval.ml:7037)
            -- NOTE (backend quote-character difference in the error text): the
               two backends emit the missing-field error with DIFFERENT quote
               characters around the field name — the interpreter uses SINGLE
               quotes (`no field 'z' in record`, from the `'%s'` format string
               at eval.ml:7026–7029) while the compiled runtime uses DOUBLE
               quotes (`no field "z" in record`, `march_record_update_dyn`,
               runtime/march_extras.c:2206–2231). The message WORDING was
               deliberately converged (§4.2.1) so both say "no field … in
               record" and both exit nonzero; only the quote glyph differs. This
               is disclosed but easy to miss — it is a diagnostic-text cosmetic
               difference, NOT a semantic divergence, and (like every crashing
               witness) is not golden-checkable since a nonzero interpreter exit
               is an automatic INTERP FAIL under verify.sh.

(E-Field)   ρ ⊢ e ⇓ VRecord [(f₁=v₁)…(f_k=v_k)]                    eval.ml:7039, 7067–7071
            f = fᵢ for some i  (first occurrence, List.assoc_opt)
            ─────────────────────────────────────────────────
            ρ ⊢ EField e f ⇓ vᵢ
            -- f absent from every fᵢ ⇒ eval_error "record has no field '%s'"
               (eval.ml:7071)
            -- a non-VRecord, non-module-path e ⇒ eval_error "field access on
               non-record value" (eval.ml:7083); EField ALSO doubles as
               qualified module-member access (`Mod.member`) when its base
               resolves to a module path rather than a record value — see the
               prose note below the rule table

(E-App-Clo) ρ ⊢ e_f ⇓ VClosure ρ' [x₁…x_k] e_b    ρ ⊢ eᵢ ⇓ vᵢ
            |x…| = |e…| = k    (x₁↦v₁,…,x_k↦v_k, ρ') ⊢ e_b ⇓ v     eval.ml:6957, 6889
            ─────────────────────────────────────────────────────
            ρ ⊢ EApp e_f [e₁…e_k] ⇓ v
            -- arity mismatch ⇒ eval_error (eval.ml:6892)

(E-App-Prim) ρ ⊢ e_f ⇓ VBuiltin _ f   ρ ⊢ eᵢ ⇓ vᵢ                 eval.ml:6889 (VBuiltin arm)
            ─────────────────────────────────────
            ρ ⊢ EApp e_f [e₁…e_k] ⇓ f [v₁…v_k]

-- ── Conditionals (EIf and ECond, presented together — see prose below) ──

(E-If-T)    ρ ⊢ e_c ⇓ VBool true    ρ ⊢ e_t ⇓ v                   eval.ml:7085
            ────────────────────────────────────
            ρ ⊢ EIf e_c e_t e_e ⇓ v

(E-If-F)    ρ ⊢ e_c ⇓ VBool false   ρ ⊢ e_e ⇓ v                   eval.ml:7091
            ────────────────────────────────────
            ρ ⊢ EIf e_c e_t e_e ⇓ v
            -- a non-Bool condition ⇒ eval_error "if condition must be a boolean" (eval.ml:7095)

(E-Cond-Sel)  ρ ⊢ c_j ⇓ VBool false  (j = 1..i−1)                   eval.ml:7097–7106
              ρ ⊢ c_i ⇓ VBool true    ρ ⊢ b_i ⇓ v
              ────────────────────────────────────────────────────
              ρ ⊢ ECond [(c₁,b₁)…(c_n,b_n)] ⇓ v
              -- the arms' CONDITIONS are evaluated top-to-bottom (`go` walks
                 the arm list, eval.ml:7098–7106); the FIRST arm whose condition
                 evaluates to `VBool true` is selected and ONLY its body runs
                 (eval.ml:7102). Every earlier arm's condition evaluated to
                 `VBool false` and was skipped (eval.ml:7103, `go rest`); every
                 later arm is never consulted. Bodies of non-selected arms are
                 NOT evaluated.

(E-Cond-Fail) ρ ⊢ c_j ⇓ VBool false  (j = 1..n)                    eval.ml:7099
              ────────────────────────────────────────────────────
              ρ ⊢ ECond [(c₁,b₁)…(c_n,b_n)] ⇓ ⊥
              -- ALL-FALSE BEHAVIOR (pinned from the code, not guessed): if `go`
                 runs off the end of the arm list with no condition having been
                 `VBool true`, it raises `eval_error "non-exhaustive `match do` —
                 no arm matched"` (eval.ml:7099) — a RUNTIME error, NOT a VUnit
                 default and NOT a required literal-true catch-all. Compiled, the
                 same all-false path panics `non-exhaustive match do`. So `ECond`
                 is NOT statically total: the typechecker checks each condition
                 is Bool and the bodies unify (typecheck.ml:4015–4031) but does
                 NOT check exhaustiveness — an all-false chain typechecks and
                 fails at runtime, exactly as a non-exhaustive `EMatch` does
                 (§4.3's Match_failure rule). A final `true ->` arm — or the
                 `_ ->` sugar for it (parser.mly:1295–1296) — makes the chain
                 total.
              -- a non-`VBool` condition ⇒ eval_error "`match do` condition must
                 be Bool" (eval.ml:7104) — but this is unreachable from a
                 well-typed program: typecheck.ml:4022,4026 force every condition
                 to `t_bool`, the ECond analogue of E-If's non-Bool guard above.

(E-Match)   ρ ⊢ e_s ⇓ v    selectᵨ(v, branches) = v'              eval.ml:6998, 7317
            ──────────────────────────────────────
            ρ ⊢ EMatch e_s branches ⇓ v'
```

**Conditionals: `EIf` and `ECond` are the fragment's two branching-on-Bool
forms, presented together above.** They share the same evaluation shape (a
`Bool`-valued test drives the choice of exactly one continuation) but differ
in arity and totality:

- **`EIf e_c e_t e_e`** (E-If-T / E-If-F, `eval.ml:7085`–`7095`) is a fixed
  **two-way** branch with a *mandatory* `else` (§Syntax: `else` is not optional;
  the parser rejects `if c do … end` without it, `parser.mly:1058`–`1062`).
  It is therefore **always total**: `e_c` is either `VBool true` (run `e_t`) or
  `VBool false` (run `e_e`), with no third outcome for a well-typed program (a
  non-Bool `e_c` ⇒ `eval_error`, but the typechecker rules that out).
- **`ECond [(c₁,b₁)…(c_n,b_n)]`** (E-Cond-Sel / E-Cond-Fail, `eval.ml:7097`–
  `7106`) is an **n-way** boolean chain (the scrutinee-less
  `match do c -> b … end`) with **no implicit else**. It evaluates conditions
  top-to-bottom and runs the first `VBool true` arm's body (E-Cond-Sel); crucially,
  unlike `EIf`, it is **NOT total**: if every condition is false it raises at
  runtime (E-Cond-Fail), because there is no fall-through default. Authors make
  it total with a final `true ->` arm (or the `_ ->` sugar the parser rewrites
  to `true ->`, `parser.mly:1295`–`1296`).

The desugarer leaves BOTH forms intact in structure (§3): neither is rewritten
into the other: `EIf` is *not* lowered to a one-arm `ECond`, and `ECond` is
*not* lowered to a nest of `EIf`s. They remain two distinct `eval_expr` arms,
each with its own big-step rule(s) above, and the golden corpus exercises `EIf`
(pervasively, e.g. g28's `if n == 0 do …`) and `ECond` (g31–g32) separately.

**`EField` also doubles as qualified module-member access, tried FIRST.**
Before `EField`'s "look up a record field" behavior (E-Field above) is even
attempted, `eval_expr`'s `EField` arm (`eval.ml:7039`–`7064`) tries to read
`ex` as a **module path**: if `ex` flattens (via a nested `ECon`/`EField`
walk, `eval.ml:7041`–`7048`) to a dotted name like `A.B`, it looks up
`"A.B." ^ field` first in the local environment, then in the global
`module_registry`, lazily loading the module from stdlib on a miss
(`eval.ml:7049`–`7063`); only if ALL of that fails does it fall through to
evaluating `ex` as an ordinary expression and trying the record-field /
`VCon`-module-member arms shown in E-Field (`eval.ml:7064`–`7083`). This
mirrors the analogous, but separate, COMPILE-TIME rewrite the desugarer
performs for the same surface form (§3's `EField` row): the desugar-time
rewrite handles the common case (a literal module path known at desugar
time), while this runtime fallback handles paths the desugarer's simpler
walk didn't resolve (e.g. one that ends in a `VCon`-shaped module reference
established later, at eval time, via `ensure_module_loaded`). A record's
`.field` access and a module's `.member` access therefore share ONE surface
form (`e.f`) and one AST node (`EField`), disambiguated dynamically by what
`e` evaluates to; this is a fidelity note about `EField`'s full behavior,
not a new core construct: the fragment's E-Field rule (§4.2) states only the
record-field case, which is this task's scope.

### 4.2.1 `ERecordUpdate` on a missing field: the interpreter/compiled adjudication (resolved)

**This is the semantic decision Task 3 exists to make.** `{ base with f: v
}` is only a well-formed *program* when `base`'s type is a concrete,
statically-known `TRecord`: in that case the typechecker's `ERecordUpdate`
case (`typecheck.ml:3855`–`3892`) resolves `base`'s type via
`expand_record`, and REJECTS the program at typecheck time if `f` is absent
from the resolved fields (`typecheck.ml:3869`–`3875`, "This record does not
have a field called..."), so E-Update's runtime behavior on an absent field
is **unreachable** for a statically-typed base; both backends simply never
run it, because the program never compiles/interprets past typechecking.

The rule only becomes runtime-observable when `base`'s type is **erased**:
a bare, unconstrained type variable that `expand_record` cannot resolve to a
concrete `TRecord` (`typecheck.ml:3879`–`3886`). This happens for a base
produced by a fully polymorphic stdlib builtin such as `record_from_list`
(`("record_from_list", poly2 (fun a b -> TArrow (t_list (TTuple [t_string;
a]), b)))`, `typecheck.ml:1297`; the return type `b` is a fresh, unrelated
type variable) or `record_put`. In that `TVar` branch, the typechecker
cannot check the update's field names against anything, so it instead
BUILDS a partial `TRecord` constraint out of the update's OWN field names
(`typecheck.ml:3881`–`3885`) and lets the program through, deferring the
"does this field actually exist on the base" question to runtime, where the
two backends used to disagree:

- **Compiled** (`llvm_emit.ml:2803`, `runtime/march_extras.c`
  `march_record_update_dyn`, `:2206`–`2231`): resolves every update name
  against the base's runtime shape registry FIRST, and **panics** ("record
  update: no field \"%s\" in record") before touching any reference counts
  if any name is unresolved.
- **Interpreter, BEFORE this task** (`eval.ml`'s old `ERecordUpdate` arm):
  silently APPENDED any update field absent from the base: `{ base with z:
  99 }` on a base without `z` produced a record with `z` added, no error.

Concretely, `{ record_from_list([("a", 1)]) with z: 99 }` used to panic
compiled (`no field "z" in record`, clean exit 1) while succeeding
interpreted (`Some(99)` printed via `record_get`, exit 0), confirmed by hand
before this task's fix (see the golden-corpus verification note below).
This was logged as an open bug (`specs/todos/`, "Interpreter/compiled
divergence: `ERecordUpdate` on a missing field") and pinned by a dedicated
unit test (`test/test_properties.ml`,
`test_record_update_missing_field_on_erased_base_...`) rather than generated
by the QCheck property corpus, per that plan's "constrain each generator to
the currently-working subset" rule.

**Adjudicated rule (this task): the compiled contract is normative.** A
functional record update is defined **only** for a field that already
exists on the base record's actual (runtime) shape. Updating a field absent
from that shape is a **runtime error**, full stop: it is not a shape
extension, and the language does not have a separate "extend" operation
spelled `{ base with … }` (field-adding is `record_put`'s job, a distinct
builtin with truly different, and intentional, semantics; see the
note below E-Update above). This is the safer contract: silently
fabricating a field an author never declared masks a likely typo or a stale
refactor, exactly the class of bug static field-name checking exists to
catch, and the compiled backend was already enforcing it; the interpreter
was the outlier.

**Outcome: the interpreter was converged to match, and both backends now
agree.** `eval.ml`'s `ERecordUpdate` arm now validates every update name
against the base's actual fields BEFORE merging (`eval.ml:7026`–`7029`,
shown as the ADJUDICATED RULE note under E-Update above) and raises
`eval_error "record update: no field '%s' in record" k`, intentionally
matching the compiled panic's wording ("no field ... in record") for
diagnostic consistency across backends. All six standard test runners
(`run_compiler`, `run_eval`, `run_codegen`, `run_stdlib`,
`test_stdlib_march`, `run_snapshots`) and the `@oracle` conformance sweep
stayed green after this change: no code in the compiler, stdlib, or test
suite depended on the old fabricate-on-missing-field behavior, other than
the one test built to pin the divergence itself, which was updated to
assert convergence instead (see `test/test_properties.ml`,
`test_record_update_missing_field_on_erased_base_converged`, and
`test/test_codegen.ml`'s `test_erased_update_missing_field_panics_compiled`
doc comment). The `specs/todos/` open-divergence entry and the informal
"known divergence" framing around this bug are both retired by this
convergence; §5's golden corpus documents the now-agreeing behavior as a
prose note (not a golden MATCH program; see §5's caveat on why this
specific shape is intentionally NOT added as one).

`EBlock` threads the environment through its statements; a block-`let` binds for
the **rest** of the block, the last statement is the block's value, and a
non-final non-`let` statement is evaluated and discarded (`eval.ml:6861`):

```
(E-Blk-Last)  ρ ⊢ e ⇓ v                          (single/last statement)
              ────────────────────
              ρ ⊢ EBlock [e] ⇓ v

(E-Blk-Let)   ρ ⊢ e₁ ⇓ v₁    match(p, v₁) = σ    σ·ρ ⊢ EBlock rest ⇓ v
              ──────────────────────────────────────────────────────────
              ρ ⊢ EBlock (ELet(p = e₁) :: rest) ⇓ v
              -- match failure ⇒ Match_failure (eval.ml:6869)

(E-LetFn)     r = ref ρ   (fresh mutable cell, initially the pre-binding ρ)   eval.ml:6875–6884
              c = VBuiltin("<rec:f>", λargs. apply (VClosure(!r, [x…], e_b)) args)
              ρ' = (f ↦ c) · ρ        r := ρ'        ρ' ⊢ EBlock rest ⇓ v
              ────────────────────────────────────────────────────────────────
              ρ ⊢ EBlock (ELetFn f [x…] e_b :: rest) ⇓ v
              -- f is bound to a SELF-REFERENTIAL closure: because c's body
                 re-reads the mutable ref `r` on every call (eval.ml:6880) and
                 r has been back-patched to ρ' = (f ↦ c)·ρ (eval.ml:6882–6883),
                 the environment c runs its body `e_b` in CONTAINS f ↦ c itself
                 — so `f(…)` inside e_b resolves to c and recurses. The binding
                 is visible to the REST of the block (rest runs in ρ', not ρ —
                 eval.ml:6884), exactly like a block-`let`. This is the ONE
                 construct in the fragment that needs the mutable-ref fixpoint;
                 see the prose below for why a persistent env cannot express it.

(E-Blk-Seq)   ρ ⊢ e ⇓ _    ρ ⊢ EBlock rest ⇓ v   (e neither ELet nor ELetFn, rest ≠ [])
              ──────────────────────────────────
              ρ ⊢ EBlock (e :: rest) ⇓ v
```

(A bare `ELet` evaluated *outside* a block just evaluates its RHS and drops the
binding (`eval.ml:6993`) because binding is only meaningful relative to a
continuation, which the block supplies. A bare `ELetFn` evaluated *outside* a
block (e.g. as the last/only statement of a block, which the `[e]` last-arm
sends to `eval_expr`, not `eval_block`) ties the SAME knot but simply RETURNS
the closure `c` as the block's value instead of binding it and continuing
(`eval.ml:7262`–`7271`); `c` is still self-referential, so the returned value
can recurse if later applied, but no expression in that block sees `f` by name.)

**Why `ELetFn` is the one construct that needs a mutable ref.** Every other
rule in §4 threads the environment as a **persistent** association list: a
binding is created by *prepending* `(name ↦ value)` to `ρ` (§4.1), and the
value being bound is fully evaluated *before* the extended environment exists.
That order is fine for `let x = e` (E-Blk-Let): `e` is evaluated in the
*old* `ρ`, so `x` need not be in scope while computing its own value. But a
*recursive* function's value (its closure) must capture an environment in
which its **own name already resolves to that very closure**, a cyclic
dependency the strict "evaluate the value, then extend the env" order cannot
satisfy directly, because the closure and the environment each need the other
first. `eval_block`'s `ELetFn` arm (`eval.ml:6875`–`6884`) breaks the cycle
with the single use of mutation in the otherwise-persistent environment: it
allocates a `ref` (`env_ref`, `eval.ml:6878`) initialized to the *pre-binding*
`ρ`, builds the closure-carrying `VBuiltin` wrapper with a body that **defers**
reading the environment until call time (`let call_env = !env_ref`,
`eval.ml:6880`; read on *every* application, not captured once), extends `ρ`
with `f ↦ c` to get `ρ'` (`eval.ml:6882`), and only THEN back-patches
`env_ref := ρ'` (`eval.ml:6883`). By the time `f` is eventually *called*, `!env_ref`
is `ρ'`, which contains `f ↦ c`, so the deferred read hands the body an
environment in which `f` is itself, closing the recursive knot. The
indirection through `VBuiltin`-wrapping-`VClosure` (rather than a plain
`VClosure` captured directly) exists exactly so the environment read can be
deferred past the moment the closure is constructed; a bare `VClosure` would
have to snapshot its environment at creation, before `f ↦ c` existed.

### 4.3 Branch selection and pattern matching

`selectᵨ(v, branches)` is the whole `eval_match` function
(`eval.ml:7317`–`7342`): a tail-recursive `go` loop over the branch list that
tries branches **top-to-bottom, first success wins**. A branch *succeeds* iff
its pattern matches AND (if it has a guard) that guard evaluates to `VBool
true`; the FIRST succeeding branch is selected and its body runs in the
pattern-extended environment. A pattern that fails to match, OR a guard that is
false, falls through to the next branch. If the loop runs off the end of the
list with no branch selected, it raises `Match_failure` (the **exhaustiveness**
rule):

```
select selection, over branches in order (eval.ml:7318 `go`):
  branch (p when? g -> e_b):
     match(p, v) = σ                                    (eval.ml:7324)
        no  ⇒ σ = ⊥ ⇒ try next branch                   (eval.ml:7325)
        yes ⇒ let ρ' = σ·ρ  (bindings @ env)            (eval.ml:7327)
              guard_ok = ( g absent )                    (eval.ml:7330)
                       ∨ ( ρ' ⊢ g ⇓ VBool true )         (eval.ml:7332–7333)
              guard_ok = true  ⇒  result is ρ' ⊢ e_b ⇓ v' (eval.ml:7339)
              guard_ok = false ⇒  try next branch          (eval.ml:7340)
  no branch matches ⇒ raise Match_failure               (eval.ml:7320)
```

**Branch-selection rule (cited to `eval_match`, `eval.ml:7317`–`7342`).**

- **First-match-wins, top-to-bottom.** `go 0 branches` (`eval.ml:7342`) walks
  the list head-first; the branch loop `br :: rest` (`eval.ml:7323`) tries the
  head, and on any failure recurses `go (arm_idx + 1) rest` (`eval.ml:7325`,
  `:7340`), so an earlier branch always shadows a later one that would also
  match.
- **Pattern-extended environment.** On `match_pattern v br.branch_pat = Some
  bindings` (`eval.ml:7324`, `:7326`), the body and guard both run in `env' =
  bindings @ env` (`eval.ml:7327`): the σ bindings are *prepended* to ρ, so by
  the §4.1 first-occurrence lookup rule a pattern variable shadows any
  same-named outer binding for the duration of the arm.
- **Guard (`branch_guard`, the `when g` clause).** The guard is
  `br.branch_guard : expr option` (`ast.ml:108`). When absent (`None`) the
  branch is selected immediately (`guard_ok = true`, `eval.ml:7330`). When present
  (`Some g`), the guard `g` is evaluated **in the pattern-extended env `env'`**
  (`eval.ml:7332`), so it may read the variables the pattern just bound, and
  its result **must be a `VBool`**: `VBool b ⇒ guard_ok = b` (`eval.ml:7333`),
  and any non-`VBool` value ⇒ `eval_error "guard must evaluate to a boolean"`
  (`eval.ml:7334`). A guard that yields `VBool false` does NOT fail the whole
  match; it falls through to the next branch (`go (arm_idx + 1) rest`,
  `eval.ml:7340`), exactly as a non-matching pattern does. (Surface syntax:
  `p when g -> e_b`, `parser.mly:1280` builds the branch, `when_guard` =
  `WHEN; e = expr`, `parser.mly:409`–`410`.)
- **Exhaustiveness / no-match.** When `go` reaches the empty list `[]` (no
  branch's pattern matched, or every matching branch had a false guard) it
  raises `Match_failure` (`eval.ml:7320`–`7322`) with the message
  *"Non-exhaustive pattern match: no branch matched the value …"*. `match` is
  therefore **not** statically total in this reference semantics: a
  non-exhaustive `match` typechecks (the typechecker emits only a *warning*,
  not an error, for a missing case) and fails at **runtime** with
  `Match_failure` if control actually reaches the uncovered value, confirmed
  by hand (`match n do 0 -> … 1 -> … end` on `n = 5` prints the exhaustiveness
  warning at compile time, then panics `match failure: Non-exhaustive pattern
  match: no branch matched the value 5` at run time, exit nonzero). A
  `PatWild` (`_`) catch-all arm (`eval.ml:773`, `match(PatWild, v) = ∅`, always
  succeeds) is the idiomatic way to make a `match` total; this is why no golden
  program can be a runtime-`Match_failure` witness (a nonzero interpreter exit
  is an automatic `INTERP FAIL` under `verify.sh`, the same harness limitation
  §4.4.1 notes for the crashing strict-`&&`/`||` witness; g26 instead exhibits
  the *complementary* fact, that a `_` catch-all keeps a `match` total and
  matching).

The matching relation `match(p, v) = σ | ⊥` returns bindings σ or failure
(`eval.ml:771`):

```
match(PatWild, v)               = ∅                            eval.ml:773
match(PatVar x, v)              = { x ↦ v }                    eval.ml:775
match(PatLit ℓ, v)             = ∅    if 𝓋(ℓ) = v, else ⊥     eval.ml:777–782
match(PatCon C [p…], VCon C' [v…]) = ⋃ match(pᵢ, vᵢ)          eval.ml:784
        provided  bare(C) = C'  and  |p…| = |v…|,  else ⊥
match(PatCon …, non-VCon)       = ⊥                            eval.ml:795

match(PatAtom a [], VAtom b)        = ∅  if a = b                  eval.ml:797
        provided  p… = []  (nullary pattern)
match(PatAtom a [p…], VCon a' [v…]) = ⋃ match(pᵢ, vᵢ)             eval.ml:798–800
        provided  a = a'  and  |p…| = |v…|,  else ⊥
match(PatAtom …, _)                 = ⊥  (all other cases)         eval.ml:801
```

**This dual-arm rule is the key documented fact about atoms: a
payload-carrying `PatAtom` matches a `VCon`, not a `VAtom`.** `match_pattern`'s
two `PatAtom` cases (`eval.ml:797`–`798`, shown as the two rules above) are
tried in order: the FIRST requires the scrutinee to be a nullary `VAtom` with
an equal tag AND the pattern itself to be nullary (`pats = []`, guarded in
the OCaml `when` clause): `match(PatAtom "ok" [], VAtom "ok") = ∅`. The
SECOND requires the scrutinee to be a `VCon` with a tag equal to the pattern's
atom name: `match(PatAtom "error" [p], VCon("error", [v])) = match(p, v)`,
componentwise via the same `match_list` helper `PatCon`/`PatTuple` share
(§4.3 below). A `PatAtom` therefore matches **two value shapes of
different structure** depending on whether it (and the value) has a payload;
this is the pattern-side mirror of E-Atom-0/E-Atom-N's value-shape split
above (§4.2), and it is why `:error(msg)` (a `PatAtom` with one sub-pattern)
can successfully destructure a value that was built as a `VCon`, never a
`VAtom`, at construction time (`eval.ml:7146–7148`). Unlike `PatCon`, there is
no separate arity-mismatch clause spelled out for `PatAtom`/`VCon` beyond the
`List.length pats <> List.length args` check inside the second arm
(`eval.ml:799`): a nullary `PatAtom` (`pats = []`) can never match a `VCon`
through this second arm either, because `List.length [] <> List.length args`
is true whenever `args` is non-empty, so `:ok` (nullary pattern) correctly
fails against a `VCon("ok", [x])` value (which cannot arise from `:ok`
construction anyway, since E-Atom-0/E-Atom-N tie payload-presence at
construction time to the same value-shape choice a matching `PatAtom` must
make); the two sides stay in lockstep by construction, not by coincidence.

```
match(PatTuple [], VUnit)          = ∅                          eval.ml:803
match(PatTuple [p…], VTuple [v…])  = ⋃ match(pᵢ, vᵢ)          eval.ml:804–806
        provided  |p…| = |v…| (componentwise via match_list, eval.ml:832–840),
        else ⊥
match(PatTuple …, non-VTuple/VUnit) = ⊥                        eval.ml:808

match(PatRecord [(f₁=p₁)…(f_k=p_k)], VRecord fields)                eval.ml:810–822
        = ⋃ match(pᵢ, vᵢ)  where vᵢ = fields[fᵢ] (List.assoc_opt),
          provided EVERY fᵢ is present in fields — i.e. the pattern's field
          set must be a SUBSET of the record's actual fields, not an exact
          match: a pattern naming fewer fields than the value has still
          succeeds (any fields present in the value but not named by the
          pattern are simply not bound, not rejected); a pattern naming a
          field ABSENT from the value fails the whole match (⊥) rather than
          matching partially
        else ⊥ if any named field is missing from the record
match(PatRecord …, non-VRecord)     = ⊥                             eval.ml:824

match(PatAs (p, x), v)   = match(p, v) ∪ { x ↦ v }                  eval.ml:826–829
        provided  match(p, v) = σ ≠ ⊥  (inner pattern matches first),
        then bind x to the WHOLE matched value v in ADDITION to σ;
        if match(p, v) = ⊥ then match(PatAs …) = ⊥ (the as-binding is
        conditional on the inner pattern succeeding)
```

`match_list` (`eval.ml:832`–`840`) is the shared componentwise helper: a
`List.fold_left2` over the pattern/value pairs that threads `match_pattern`
across each position and short-circuits to `⊥` (`None`) the moment any one
component fails, otherwise unioning the accumulated bindings, the same
combinator `PatCon`'s arm (above) already relies on for its own `⋃`.
`PatTuple ([], _)` matching `VUnit` (`eval.ml:803`) is the pattern-side
counterpart of E-Tuple's `ETuple [] ⇓ VUnit` alias (§4.2): a 0-arity tuple
*value* never actually exists at runtime (only `VUnit` does), so the empty
tuple pattern is special-cased to accept `VUnit` directly rather than an
(impossible) `VTuple []`.

**`PatRecord` implements SUBSET matching, unlike every other structural
pattern in this fragment.** `PatCon`/`PatTuple`/`PatAtom` all require the
value to have EXACTLY the pattern's arity (`List.length pats <> List.length
args/vs` ⇒ `⊥`, `eval.ml:792, 805`): a 2-element `PatTuple` never matches a
3-element `VTuple`. `PatRecord`'s implementation (`eval.ml:810–822`) is
different by construction: it `List.fold_left`s over the PATTERN's field
list only, looking each named field up in the value's field list via
`List.assoc_opt` (`eval.ml:815`); there is no arity check against the
record's total field count anywhere in this arm. So `{ x }` (naming only
`x`) successfully matches a value with fields `{x: 1, y: 2, z: 3}`, binding
just `x`, and simply never inspects `y`/`z`. The failure mode is asymmetric:
missing a field the PATTERN needs (`List.assoc_opt` returns `None`,
`eval.ml:816`) fails the whole match, but the value having EXTRA fields the
pattern doesn't mention is never even examined, much less rejected. As documented in
§2, however, this rule is presently unreachable from any parsed March
program: `PatRecord` has no `{...}` pattern grammar production
(`lib/tir/lower_match.ml:132–138`), so this subset-matching behavior can only
be observed by constructing the AST node directly (e.g. from a test), not by
writing and running a `.march` source file.

**`PatAs` (`p as x`) binds the whole matched value AND the inner pattern's
bindings.** `match_pattern`'s `PatAs (inner, alias, _)` arm (`eval.ml:826`–
`829`) first matches the value against the *inner* pattern (`match_pattern v
inner`); if that fails (`None`), the whole `PatAs` fails (`eval.ml:828`); if it
succeeds with bindings `bs`, the result is `(alias.txt, v) :: bs`
(`eval.ml:829`): i.e. σ extended with the alias `x` bound to the ENTIRE value
`v` that was matched, in addition to whatever the inner pattern bound. So
`match(PatCon "Som" [PatVar "v"] as "whole", VCon("Som",[VInt 7]))` binds both
`v ↦ VInt 7` (from the inner `PatVar`) and `whole ↦ VCon("Som",[VInt 7])` (the
whole value). Because the alias is **prepended** (`:: bs`, `eval.ml:829`), it
takes lookup precedence over any inner binding of the same name (§4.1
first-occurrence rule), an edge case that cannot arise from well-typed source
anyway. The inner `p` may be any pattern, so `PatAs` composes with nesting like
every other structural pattern; the recursion is `match_pattern`'s own, not a
special case.

**`PatAs` has no surface production at all: it is dead code, exactly like
`PatRecord`, reachable only by constructing the AST node directly.** Grepping
`parser.mly` for `PatAs` finds **zero** occurrences: the `pattern` grammar
(`parser.mly:1311`–`1341`) has productions for `PatCon`/`PatAtom`/`PatWild`/
`PatVar`/`PatLit`/`PatTuple` (and the list-literal sugar), but **no `pattern
AS name` rule**: the `AS` token is used only for module aliases (`alias P as
Q`, `parser.mly:704`–`707`) and as a soft identifier (`parser.mly:1361`),
never to build a `PatAs`. Confirmed by hand against the built compiler: `p as
x` is a parse error in every position tried: as a `match` arm (`Som(v) as
whole -> …` and `n as whole -> …` both report *"I was expecting `->` in the
match arm here"* at the `as`) and as a `let` binding (`let (n as whole) = 5`
reports *"I got stuck here"* at the `as`). `desugar.ml`'s three `PatAs` arms
(`:296, 1000, 1980`) only recurse into an *already-constructed* `PatAs`
(respanning / collecting bound vars), never build one fresh from another
surface form: the same "implemented in `eval.ml`/`desugar.ml`/`typecheck.ml`
but unreachable from any parsed program" situation §2 documents for
`PatRecord`. This spec therefore states the `PatAs` matching rule (above) for
completeness and fidelity to `eval.ml`, but **no golden program in §5 exercises
it**, because no March *source program* can construct one; the golden
substitute (g27) instead exercises a guard reading pattern-bound variables,
which IS reachable and covers the adjacent "bindings visible to the arm"
semantics. (This form is collected with the other implemented-but-unreachable
pattern form, `PatRecord`, in **§4.3.1**.)

`match(PatLit ℓ, v)` is one arm per literal kind, each requiring **both** the
pattern and scrutinee to be the *same* value constructor with equal payload:
there is no cross-kind coercion (a `PatLit (LitInt 0)` never matches a
`VFloat`):

```
match(PatLit (LitInt i),    VInt j)     = ∅ if i = j, else ⊥    eval.ml:777
match(PatLit (LitFloat f),  VFloat g)   = ∅ if f = g, else ⊥    eval.ml:778
match(PatLit (LitString s), VString t)  = ∅ if s = t, else ⊥    eval.ml:779
match(PatLit (LitBool b),   VBool c)    = ∅ if b = c, else ⊥    eval.ml:780
match(PatLit (LitAtom a),   VAtom b)    = ∅ if a = b, else ⊥    eval.ml:781
match(PatLit _, _ )                     = ⊥  (kind mismatch, or unequal)  eval.ml:782
```

(`LitFloat` equality is OCaml `(=) : float -> float -> bool`: ordinary IEEE
structural equality, no epsilon tolerance; this is the same primitive used by
δ-EqF below.)

`bare(C)` strips a leading module qualifier (`eval.ml:786`); the constructor
value's tag is stored already-stripped (`eval.ml:6981`), which is why
`match(PatCon "Som" …, VCon "Som" …)` succeeds regardless of qualification.

### 4.3.1 Implemented-but-unreachable pattern forms (`PatRecord`, `PatAs`)

Two of the pattern constructors with matching rules that §4.3 states in full,
**`PatRecord`** (`{ f, … }`, the record-destructuring pattern) and **`PatAs`**
(`p as x`, the as-pattern), are **implemented in the interpreter but have NO
surface grammar**: no `parser.mly` production builds one from `.march`
source, so both are *dead code* from the parser's perspective. They are
reachable only by constructing the `Ast.pattern` node directly (e.g. inside an
OCaml unit test), never by writing and running a March program.

This spec documents their matching rules anyway, **for fidelity**: §4 is a
faithful transcription of the interpreter's `match_pattern`, and
`match_pattern` supports both (with fully-implemented arms that would work
correctly should such a node reach them). Stating them keeps the spec an
accurate mirror of `eval.ml`. But **no golden program in §5 exercises either**,
because no March *source program* can construct one.

The evidence and the exact rule citations live at each form's own rule (kept in
place; this subsection collects, it does not relocate the citations):

- **`PatRecord`**. Matching rule and its SUBSET-matching semantics: §4.3
  (`match(PatRecord …)`, `eval.ml:810–822`, `eval.ml:824`). Dead-code evidence:
  §2's "`PatRecord` has no surface production at all" note (zero `parser.mly`
  occurrences; `lib/tir/lower_match.ml:132–138`'s `failwith` comment "PatRecord
  has no `{...}` pattern production in the grammar today"; both `let { x, y } =
  r` and `match r do { x, y } -> … end` are parse errors). The typechecker's
  `infer_pattern` arm (`typecheck.ml:2666–2675`) and the interpreter's
  `match_pattern` arm are both complete; the gap is purely in the parser.
- **`PatAs`**. Matching rule (binds the whole matched value AND the inner
  pattern's bindings): §4.3 (`match(PatAs …)`, `eval.ml:826–829`). Dead-code
  evidence: §4.3's "`PatAs` has no surface production at all" note (zero
  `parser.mly` occurrences; the `AS` token is only a module-alias / soft
  identifier; `Som(v) as whole -> …`, `n as whole -> …`, and `let (n as whole)
  = 5` are all parse errors). `desugar.ml`'s three `PatAs` arms (`:296, 1000,
  1980`) only ever recurse into an already-constructed `PatAs`, never build one.
  The golden substitute is **g27** (a guard reading its branch's own
  pattern-bound variables, the reachable analogue of the as-binding's
  "bindings visible to the arm" semantics).

(`LitAtom` inside `ELit`/`PatLit` is a THIRD, narrower implemented-but-parser-
unreachable form (see §2's "`LitAtom` … is dead code from the parser's
perspective" note) but it is a *literal* constructor, not a top-level pattern
form, and the parser builds `EAtom`/`PatAtom` from `:ok` syntax instead; it is
cross-referenced here for completeness but its rule stays at E-Lit / the
`match(PatLit (LitAtom a), …)` arm.)

### 4.4 Primitive δ-rules

Every primitive operator below is bound in `base_env` (`eval.ml:2760`–…) to a
`VBuiltin (name, f)` where `f : value list -> value` is an ordinary OCaml
function (no special evaluator support). The parser is what turns surface
infix/prefix syntax into `EApp(EVar name, args)` (§2's "primitive operators are
not syntax" fact); (E-App-Prim) (§4.2) is what applies `f` to the
already-evaluated argument values. The table below is therefore just an
enumeration of `f`'s pattern-match arms, one δ-rule per arm, each restricted to
the value kinds shown; an application outside those kinds raises
`eval_error` (an OCaml exception the interpreter's top level reports as a
compiler-fatal error; not a `March` value, hence not further modeled here).

**Arithmetic**: `arith_num iop fop name` (`eval.ml:850`–`853`) applies `iop`
to two `VInt`s or `fop` to two `VFloat`s (no int/float mixing):

```
(δ-Add-I)  f₊ [VInt a; VInt b]     = VInt (a + b)              eval.ml:851, bound eval.ml:2762
(δ-Add-F)  f₊ [VFloat a; VFloat b] = VFloat (a +. b)           eval.ml:852, bound eval.ml:2762
(δ-Sub-I)  f₋ [VInt a; VInt b]     = VInt (a - b)              eval.ml:851, bound eval.ml:2763 ("-")
(δ-Sub-F)  f₋ [VFloat a; VFloat b] = VFloat (a -. b)           eval.ml:852, bound eval.ml:2763 ("-")
(δ-Mul-I)  f₊ [VInt a; VInt b]     = VInt (a * b)              eval.ml:851, bound eval.ml:2764 ("*")
(δ-Mul-F)  f₊ [VFloat a; VFloat b] = VFloat (a *. b)           eval.ml:852, bound eval.ml:2764 ("*")
```

(`arith_num` is one polymorphic-in-the-OCaml-operator definition; `+`, `-`,
`*` are three separate bindings that each instantiate it with a different
`(iop, fop)` pair, eval.ml:2762–2764. Surface `a - b`/`a * b` are
`EApp(EVar "-"/"*", [a;b])`, produced by the parser exactly like `+`:
`parser.mly:1146` (`-`), `:1153` (`*`).)

`/` and `%` (integer division and remainder) are **not** `arith_num`: they
are bespoke `VBuiltin`s with an explicit zero-divisor guard instead of letting
the host language's own behavior leak through:

```
(δ-Div-I)  f_/ [VInt a; VInt b]    = VInt (a / b)     if b ≠ 0   eval.ml:2766
(δ-Div-F)  f_/ [VFloat a; VFloat b] = VFloat (a /. b)  if b ≠ 0.0 eval.ml:2767
(δ-Div-0)  f_/ [VInt _; VInt 0]     ⇒ eval_error "division by zero"        eval.ml:2768
(δ-Div-0F) f_/ [VFloat _; VFloat 0.0] ⇒ eval_error "division by zero"     eval.ml:2772
(δ-Mod-I)  f_% [VInt a; VInt b]    = VInt (a mod b)   if b ≠ 0   eval.ml:2775
(δ-Mod-0)  f_% [VInt _; VInt 0]     ⇒ eval_error "modulo by zero"          eval.ml:2776
```

Both `/` (`VInt a / VInt b`) and `%` use OCaml's native `(/)`/`mod`, which
**truncate toward zero** (e.g. `(-7) / 2 = -3`, `(-7) mod 2 = -1`); this is
the concrete rounding rule the spec commits to, since it is what `eval.ml`
actually computes. There is no `%`-on-`Float` builtin (`%` restricted to
`VInt`; a `VFloat` operand falls through to the catch-all `eval_error
"builtin %%: expected two integers"`, `eval.ml:2777`).

**Note on surface spelling:** the brief's "arithmetic … `mod`" refers to the
*semantic family* (integer remainder), not a literal `mod` infix token:
`mod` is a **reserved keyword** for module declarations (`mod Name do … end`,
lexer.mll:31, `MOD` token) and cannot be reused as an operator. The surface
spelling of integer remainder is `%` (`PERCENT` token, lexer.mll:161;
`parser.mly:1155` builds `EApp(EVar "%", [a;b])`); its builtin name in
`base_env` is likewise `"%"`, not `"mod"`.

**Comparison family**: `cmp_op op_i op_f op_s op_b name` (`eval.ml:876`)
tries, in order, `Int`/`Float`/`String`/`Bool` same-kind comparison, then
(for `==`/`!=`) an `Eq`-impl-or-structural-equality fallback, then (for
ordering operators) an `Ord`-impl dispatch:

```
(δ-Eq-I)   f₌  [VInt a;    VInt b]    = VBool (a = b)          eval.ml:877, bound eval.ml:2805 ("==")
(δ-Eq-F)   f₌  [VFloat a;  VFloat b]  = VBool (a = b)          eval.ml:878, bound eval.ml:2805 ("==")
(δ-Eq-S)   f₌  [VString a; VString b] = VBool (a = b)          eval.ml:879, bound eval.ml:2805 ("==")
(δ-Eq-B)   f₌  [VBool a;   VBool b]   = VBool (a = b)          eval.ml:880, bound eval.ml:2805 ("==")
(δ-Neq-*)  f₍≠₎ [<same four pairs>]   = VBool (a <> b)         eval.ml:877–880, bound eval.ml:2806 ("!=")
(δ-Lt-*)   f₍<₎ [<same four pairs>]   = VBool (a < b)          eval.ml:877–880, bound eval.ml:2807 ("<")
(δ-Le-*)   f₍≤₎ [<same four pairs>]   = VBool (a <= b)         eval.ml:877–880, bound eval.ml:2808 ("<=")
(δ-Gt-*)   f₍>₎ [<same four pairs>]   = VBool (a > b)          eval.ml:877–880, bound eval.ml:2809 (">")
(δ-Ge-*)   f₍≥₎ [<same four pairs>]   = VBool (a >= b)         eval.ml:877–880, bound eval.ml:2810 (">=")
```

(`cmp_op` is instantiated once per operator with OCaml's own `(=)`, `(<>)`,
`(<)`, `(<=)`, `(>)`, `(>=)` as the four same-kind comparators; the table
above collapses `Int`/`Float`/`String`/`Bool` into "same four pairs" per
operator to avoid 24 near-identical rows; each pair is total for that
operator restricted to two values of the *same* one of those four kinds.)
For `Int`/`Float`/`String`/`Bool`, every operator in this family is **total**
and needs no interface dispatch: the `Eq`/`Ord`-impl and structural-equality
fallback arms (`eval.ml:881`–`914`) exist for types outside this fragment
(records, ADTs, …) and are explicitly out of scope here (this is the same
under-specified corner the walking skeleton flagged for `==`: the
`==`-on-`Newtype` bug the oracle found lived there).

**Unary negation**: `negate` (`eval.ml:2932`), reached from surface prefix
`-e` which the parser rewrites to `EApp(EVar "negate", [e])`
(`parser.mly:1162`–`1163`, distinct from binary `-`):

```
(δ-Neg-I)  f₋₁ [VInt n]   = VInt (~- n)                        eval.ml:2933
(δ-Neg-F)  f₋₁ [VFloat f] = VFloat (~-. f)                      eval.ml:2934
```

**Boolean ops**: `&&`, `||`, `not` are plain strict `VBuiltin`s restricted to
`VBool`, exactly parallel to `+`/`==` (see §4.4.1 for the critical fact
that they do **not** short-circuit):

```
(δ-And)  f_&& [VBool a; VBool b] = VBool (a && b)               eval.ml:2812–2814
(δ-Or)   f_|| [VBool a; VBool b] = VBool (a || b)                eval.ml:2815–2817
(δ-Not)  f_not [VBool b]         = VBool (not b)                 eval.ml:2818–2820
```

**String concatenation**: `++`, restricted to `VString`:

```
(δ-Concat) f₊₊ [VString a; VString b] = VString (a ^ b)          eval.ml:2822–2824
```

Surface `a ++ b` is `EApp(EVar "++", [a;b])`, produced by the parser
(`parser.mly:1147`) at the same precedence level as `+`/`-` (`expr_add`).

### 4.4.1 `&&`/`||` are strict, not short-circuiting (resolved from the code)

**This is an operational rule, not a δ-rule**: it is a fact about *when* the
right operand is evaluated, which the δ-rule table above cannot express
because δ-rules apply to already-evaluated argument values.

**Resolved answer: `&&` and `||` are strict.** Both operands are
unconditionally evaluated before the operator is applied: there is no
short-circuiting. This applies both to the `&&`/`||` symbols directly and to
any surface spelling that reduces to them.

**How this was verified** (not guessed): surface `a && b` / `a || b` are
built by the **parser**, not the desugarer, as ordinary `EApp` nodes:
`expr_and: a AND b { EApp (EVar "&&", [a; b]) }` (`parser.mly:1132`) and
`expr_or: a OR b { EApp (EVar "||", [a; b]) }` (`parser.mly:1128`), exactly
the same shape as `a + b`. `AND`/`OR` are not word-keywords; the lexer maps
the *symbols* `&&`/`||` straight to the `AND`/`OR` tokens
(`lexer.mll:168`–`169`); grepping the keyword table (`lexer.mll:20`–~`75`)
confirms there is no `"and"`/`"or"` word entry, so **there is no English-word
`and`/`or` surface form in March**, only `&&`/`||`.

Given `EApp(EVar "&&", [a;b])`, the single `eval_expr` arm that handles
*every* `EApp` (`eval.ml:6957`–`6975`) evaluates the callee (`f`) and then
does `List.map (eval_expr env) args` (`eval.ml:6967`) **before** calling
`apply fn_val arg_vals` (`eval.ml:6972`). This map has no special case for any
callee name; it evaluates `a` and `b` unconditionally, in order, whatever the
result of evaluating `a` is, and only then applies the builtin closure looked
up for `"&&"`/`"||"` (`eval.ml:2812`–`2817`, shown as δ-And/δ-Or above), which
itself pattern-matches on two already-produced `VBool`s. Grepping `ast.ml` and
`eval.ml` for `EAnd`/`EOr` confirms there is no dedicated short-circuiting AST
node or evaluator arm: `&&`/`||` are ordinary named values of type
`value list -> value`, dispatched through the generic strict-application
path, with **no** mechanism by which `b` could be skipped.

Consequence: `false && (1 / 0 == 0)` and `true || (1 / 0 == 0)` both **raise**
`eval_error "division by zero"` in March (confirmed by direct test:
`true || (1 / 0 == 0)` prints `division by zero` and exits 1), where a
short-circuiting language would return `false`/`true` without evaluating the
right operand. This exact crashing program is **not** usable as a golden
entry, though: the committed `verify.sh` harness treats any nonzero
interpreter exit code as an automatic `INTERP FAIL` (it does not compare
"both sides crash the same way"), so a crashing program can never register as
a `MATCH` regardless of whether the interpreter and compiled backend agree.
`g13_strict_bool.march` (§5) is therefore a **non-crashing** witness with the
same evidentiary content: it puts an observable `println` side effect on the
operand that a short-circuiting `||`/`&&` would never evaluate (the left
operand already determines the result) and confirms (identically,
interpreted and compiled) that the side effect fires anyway. That is the
golden-checked confirmation of strictness; the crashing variant above is the
sharper illustration but is intentionally kept out of the golden corpus for
the harness-compatibility reason just given.

(`not` is unary and has no left-to-right evaluation-order question: `!e` /
`not(e)` evaluate the single argument then apply `eval.ml:2818`–`2820`, same
generic path.)

### 4.4.2 Method dispatch: `impl_tbl` vs. ordinary lexical `env` binding

§4.4's comparison family flagged, and deferred, exactly this question: the
`Eq`/`Ord`-impl-or-structural-equality fallback arms of `==`/`<` "exist for
types outside this fragment ... and are explicitly out of scope here"
(§4.4, `eval.ml:881`–`914`). This subsection is that deferral discharged for
`interface`/`impl` method calls specifically: how a call like `speak(d)` or
`show(v)` picks WHICH method body actually runs, at RUNTIME, once the
typechecker (`core-march-types.md` §2.1a/§2.3) has already decided a suitable
`impl` statically **exists**. That is the crucial division of labor to keep
straight: **typing determines an impl exists; this subsection is how the right
one's method body gets invoked.** The mechanism is not what a reader coming
from Rust/Haskell/Swift might expect: March has **two entirely different
runtime dispatch strategies**, depending on which interface is being called,
and the split is a hard **four-name allowlist**, not a general property of
"is this a built-in vs. user interface" in the abstract (it happens to
coincide with that distinction today only because no user-declared interface
is on the allowlist).

**Built-in type-directed interfaces (`Show`, `Eq`, `Ord`, `Hash`) dispatch
through `impl_tbl`, a real runtime hashtable keyed `(iface, type_name)`.**

```
impl_tbl : (string * string, value) Hashtbl.t                      eval.ml:257

is_type_dispatched_method(iface, meth) =                           eval.ml:270–273
    true   iff (iface,meth) ∈ {("Show","show"),("Eq","eq"),
                                ("Ord","compare"),("Hash","hash")}
    false  otherwise

is_type_dispatched_iface(iface) =                                  eval.ml:287–289
    true   iff iface ∈ {"Show","Eq","Ord","Hash"}
    false  otherwise

(E-Dispatch-Builtin)
    ρ ⊢ e ⇓ v            type_name_of_value(v) = Some τ            eval.ml:877–888
    Hashtbl.find_opt impl_tbl (iface, τ) = Some f_impl
    ──────────────────────────────────────────────────────────────
    a call to the builtin `show`/`==`/`<`/`hash` on v invokes f_impl
    -- reached via: show_dispatch (eval.ml:2756–2774, called by both the
       `show` builtin at eval.ml:3362–3364 AND `println`'s value-formatting,
       eval.ml:2853–2856), the `==`/`!=` and `<`/`<=`/`>`/`>=` arms of
       cmp_op (eval.ml:901–915, 916–934), the standalone `eq`/`compare`/
       `hash` builtins (eval.ml:3336–3348, 3349–3361, 3365–3378) — every one
       of these looks up impl_tbl BY THE ARGUMENT'S OWN DYNAMIC TYPE, via
       type_name_of_value (eval.ml:877–888: ctor_type_tbl for an ADT value,
       record_type_tbl for a record value's field-name signature).
    -- fallback (no impl_tbl entry): structural OCaml equality/comparison
       for ==/</hash (eval.ml:915, "no `Ord` implementation" eval_error for
       <, etc.), value_to_string for show (eval.ml:2773–2774) — the "types
       outside this fragment" escape hatch §4.4 already named.
```

This is a real, type-directed runtime lookup: which method body runs depends
on `v`'s dynamic type tag at the CALL site, not on which `impl` happened to
be declared last or where in the source the call appears lexically. Two
`derive(Show)`s for two different types populate two different `impl_tbl`
entries (`("Show","Color")`, `("Show","Shape")`, say) that coexist without
interfering; this is exactly what makes the built-in interfaces behave the
way a reader familiar with single-dispatch runtime polymorphism would expect.

**`t28_derive_impl_tbl_dispatch.march` (`specs/lang/types/accept/`) witnesses
this concretely:** `derive Show, Eq for Color` (on `type Color = Red | Green
| Blue`) expands, at DESUGAR time, to ordinary `DImpl` blocks (`derive`'s
own mechanism, `desugar.ml`, out of this document's scope; see
`core-march-types.md` §2.3/`interface-impl-survey.md` §5); those `DImpl`
blocks are evaluated by the SAME `DImpl` handler documented below, and
because `Show`/`Eq` are on the four-name allowlist, they register into
`impl_tbl` under `("Show","Color")`/`("Eq","Color")` rather than binding
`show`/`eq` as bare names. Running it (interpreted, confirmed live):

```
println(show(Red))       -- Red    (impl_tbl lookup on Red's dynamic tag)
println(Green == Green)  -- true   (impl_tbl "Eq" lookup, structural payload compare)
println(Red == Blue)     -- false
```

Without `derive Eq for Color`, `Red == Blue` is rejected at typecheck time
(`` `Color` does not implement interface `Eq`. ``; `core-march-types.md`
§2.1a), confirming the program above is truly exercising the derived
`impl_tbl` entry, not an incidental structural-equality fallback that would
apply regardless.

**STALE (2026-07-06) → CORRECTED (2026-07-22): user-defined interfaces do NOT
resolve through bare lexical `env` shadowing any more: a second runtime
table, `iface_method_tbl`, now dispatches a general interface method by its
FIRST argument's runtime type.** An earlier revision of this reference
documented general (non-`Show`/`Eq`/`Ord`/`Hash`) interface methods as
resolving through ordinary `EVar` lookup, so that two `impl`s of the same
interface (even for two DIFFERENT types) would have whichever one was
registered LAST silently clobber the earlier binding in `ρ`, with no
reference at all to the call's actual argument type. That was accurate for
the interpreter as it stood on 2026-07-06, but it was subsequently identified
as a real correctness bug (`specs/plans/archive/2026-07-17-interface-impl-coherence.md`)
and fixed as part of the impl-coherence / FQN-dispatch-identity work
(2026-07-17 → 2026-07-21, `specs/todos/`'s "impl-coherence" and "FQN
dispatch-identity" entries). `DImpl`'s eval handler (still two copies kept in
lockstep: the top-level/module path around `eval.ml:8969`–`9069` and the
`make_recursive_env`/letrec-style path around `eval.ml:9345`–`9440`; re-grep,
these drift) now does:

```
(E-DImpl)
    is_dispatched = is_type_dispatched_method(iface, meth)      eval.ml:8990 (9365)
    case is_dispatched of
    | true  → build a PLAIN, non-self-referential closure for the method
              value, bind it ONLY in impl_tbl (NOT in the returned env)
              — unchanged from before, see (E-Dispatch-Builtin) above
    | false → register the CONCRETE method value in iface_method_tbl under
              (iface, meth, dispatch_type_name) — a THIRD runtime table,
              keyed (iface_name, method_name, type_name) so a multi-method
              interface's methods don't overwrite each other        eval.ml:9024 (9396)
              — then bind mname ONCE in the returned env to a TYPE-DISPATCHER
              VBuiltin (tagged "$dispatch$Iface$method", idempotent across
              sibling impls of the same method) that reads its FIRST
              argument's runtime type via dispatch_type_name_of_value and
              looks the concrete method up in iface_method_tbl by
              (iface, meth, that type), erroring "no implementation of
              interface `%s` for type `%s`" if none is registered   eval.ml:9046–9067 (9418–9439)
    ────────────────────────────────────────────────────────────────
    a later `impl` of the SAME (iface, method, type) triple still overwrites
    the iface_method_tbl entry for that exact type (see §4.4.3 — this exact
    shape is now REJECTED at typecheck by a coherence check before eval ever
    runs); a later `impl` of the SAME interface/method for a DIFFERENT type
    adds a SIBLING entry under a different type key and does not disturb the
    first — the dispatcher routes to whichever entry matches the call's
    actual argument type
```

Concretely: `interface Speak(a) do fn speak : a -> String end` is not on the
`is_type_dispatched_method` allowlist, so `impl Speak(Dog) do fn speak(self)
do ... end end`'s eval arm takes the `false` branch; but rather than binding
`speak` directly to Dog's method body, it registers Dog's body in
`iface_method_tbl` under `("Speak", "speak", "Dog")` and binds the bare name
`speak` to a type-dispatcher closure. A later `impl Speak(Cat) do fn
speak(self) do ... end end` registers Cat's body under `("Speak", "speak",
"Cat")` and finds the dispatcher already bound (`already = true`,
`eval.ml:9051`/`9422`), so it leaves the existing binding as it is: it does
**not** overwrite `speak` with a second concrete closure. A later call
`speak(d)` therefore is NOT a plain `EVar "speak"` lookup that "finds
whichever impl was registered last" (`d`'s dynamic type is now exactly what
selects the right method): `speak(Dog("Rex"))` and `speak(Cat("Tom")))` both
correctly resolve to their own type's method, confirmed live (interpreted
AND compiled; the compiled backend resolves each call site via
monomorphization on the call's statically-known argument type, so it was
never subject to the lexical-shadowing bug this table describes for the
interpreter). `t27_user_iface_lexical_dispatch.march`
(`specs/lang/types/accept/`) still witnesses the single-impl case (one
`interface Speak(a)`, one `impl Speak(Dog)`,
`speak(Dog("Rex"))` → `"Rex says Woof"`) but its committed
comment's framing (that this is "the unambiguous
case" because "there is only one impl in scope for this call") is now
outdated commentary, not a live restriction: a second impl for a different
type no longer makes the call ambiguous. (The file itself was not edited by
this docs-only task; flagged here as a corpus-comment staleness, not a
corpus-correctness bug; the program still typechecks, runs, and prints the
documented output.)

**Coherence, not shadowing, is now what governs overlap.** §4.4.3,
immediately below, was rewritten (2026-07-22) to reflect that overlapping
impls of the same interface for the same type (or for types with heads that
unify) are REJECTED at typecheck time by a dedicated coherence check, not
silently accepted and resolved differently per backend. The "just shadowing,
not a designed coherence policy" framing this subsection used to carry here
no longer describes current behavior for either same-type or
generic-vs-specific overlap; see §4.4.3 for the current rule and its
evidence.

**Context, not a rule: the `is_type_dispatched_iface` guard defends against a
same-key collision that today never actually fires.** The doc comment at
`eval.ml:259`–`269` and `eval.ml:275`–`286` explains the guard's motivation:
`if (not (is_type_dispatched_iface idef.impl_iface.txt)) || is_dispatched
then Hashtbl.replace impl_tbl (idef.impl_iface.txt, type_name) fn_val`
(`eval.ml:8323`–`8324`, mirrored `:8639`–`8640`) ensures that only a type-
dispatched interface's OWN canonical method (`Eq`'s `eq`, not a hypothetical
extra `neq`) is allowed to claim the shared `(iface, type)` `impl_tbl` key;
any other method under the same built-in interface name is left out of
`impl_tbl` entirely, specifically so it cannot clobber the dispatch entry and
cause `neq → eq → neq`-shaped infinite recursion (a real historical bug this
guard fixed). Re-grepped live and confirmed present, unchanged, and correctly
shaped at the cited lines in this worktree. It is **currently unreachable for
the four built-in interfaces**, though; reproduced live for this task:
hand-writing `impl Eq(Dog) do fn eq(a,b) do ... end fn neq(a,b) do
not(eq(a,b)) end end` is REJECTED at TYPECHECK time, `` Interface `Eq` does
not declare a method `neq`. `` (`core-march-types.md` §2.3's extra-method
check, `typecheck.ml:7158`–`7165`; the built-in `Eq` interface's own
`iface_methods` list contains only `eq`, so `neq` is an "extra undeclared
method" like any other). The eval.ml guard is therefore belt-and-suspenders:
correct and still critical for a HYPOTHETICAL future built-in interface
with multiple methods (or if `is_type_dispatched_method`'s allowlist is at some point
widened), but the specific `Eq`/`neq` collision its comment narrates cannot
occur today, because the typechecker's own extra-method rejection forecloses
it first.

### 4.4.3 Impl coherence: overlap is now REJECTED at typecheck (was an open divergence; CLOSED 2026-07-17)

**STALE (2026-07-06) → CORRECTED (2026-07-22): this subsection used to
document an open, intentionally-unfixed cross-backend divergence: two
overlapping impls both typechecked silently, and the interpreter and
compiled backend picked different winners at runtime. That divergence was
resolved by adding a real impl-coherence check, landed in two stages
(`specs/plans/archive/2026-07-17-interface-impl-coherence.md`, Stage 1+2, 2026-07-17;
`specs/todos/`'s "impl-coherence" entries).** The design decision
`core-march-types.md` §2.3's `(T-ImplMatch)` discussion and the original
version of this subsection both flagged as unmade ("add a coherence check
that rejects overlap entirely, à la Rust; pick one deterministic selection
policy; or formally embrace overlapping instances") has been made: March
took the **Rust-style coherence** branch. `register_impl_shape`
(`lib/typecheck/typecheck.ml`) now does a **lookup-before-insert** keyed on
an alpha-normalized structural key of the impl head (`canonical_impl_key`)
before the `(T-Impl)` prepend that used to be unconditional, and rejects a
second impl with a head that overlaps an already-registered one: for an EXACT
same-type collision, and (Stage 2, unifiability-based) for a
**generic-vs-specific** overlap too (`List(a)` vs `List(Int)`-shaped heads).

**The current fact, reproduced live in this worktree (2026-07-22): two
`impl Speak(Dog)` blocks for the same interface and the same concrete type
no longer both typecheck.** The exact program the original repro used:

```march
mod M do
  interface Speak(a) do
    fn speak : a -> String
  end

  type Dog = Dog(String)

  impl Speak(Dog) do
    fn speak(self) do
      "FIRST"
    end
  end

  impl Speak(Dog) do
    fn speak(self) do
      "SECOND"
    end
  end

  fn main() do
    println(speak(Dog("Rex")))
  end
end
```

`--check` now exits **1** on both backends' shared typechecker, with:

```
Overlapping implementation: `impl Speak(Dog)` conflicts with the
implementation at <file>:8:7 — their heads overlap.
A type may implement an interface at most once (coherence). If you meant a
different behavior, wrap the type in a newtype and implement the interface
on that.
```

pointing at the second `impl Speak(Dog)`'s span and citing the first's. The
program never reaches either runtime, so the old "interpreted prints
`SECOND`, compiled prints `FIRST`" split described here previously can no
longer arise for this program: it is now caught before either backend runs
it, exactly the outcome the original open-divergence framing named as one
possible (but then-unimplemented) resolution. Pinned by the types corpus:
`reject/t79_impl_coherence_duplicate` (`specs/lang/types/reject/`).

**The generic-vs-specific and derive-vs-manual overlap probes this
subsection used to document as separate confirmed divergence instances are
ALSO now rejected, not just the exact-duplicate case.** Re-probed live,
same methodology as the original finding:

- **Generic-vs-specific:** `impl Speak(Box(a))` (blanket over every `Box`)
  followed by `impl Speak(Box(Int))` (a concrete specialization): the
  program that used to print `"int box"` interpreted and `"generic box"`
  compiled now fails `--check` with the same `Overlapping implementation …
  their heads overlap` diagnostic, citing the `Box(a)` impl as the
  conflicting declaration. This is Stage 2's parametric-overlap check
  (`types_overlap`, unifiability-based; `List(a)` vs `List(Int)`-shaped
  heads are treated as overlapping even though neither is a literal
  duplicate of the other). Pinned by `reject/t80_impl_parametric_overlap`.
- **Derive-vs-manual:** `derive Show, Eq for Color` followed by a
  hand-written `impl Eq(Color) do fn eq(a, b) do true end end`: the program
  that used to print `true` interpreted (hand-written wins) and `false`
  compiled (derive-generated structural comparison wins) now ALSO fails
  `--check` with an `Overlapping implementation` diagnostic (confirmed live
  this task, citing the derive-expansion's synthesized span as the
  conflicting declaration): `derive`'s generated `DImpl` registers through
  the identical `register_impl_shape` path as a hand-written one, so it is
  not exempted from the coherence check.

**What is intentionally still allowed (not a residual divergence, a scoping
decision).** Per `specs/todos/`'s Stage-1+2 closeout note, a user impl
overlapping a *built-in* seeded impl (e.g. a hand-written `impl Eq(Int)`) is
still accepted: built-ins are seeded into `env.impls` with a `dummy_span`
and skipped by the check, because several interface-mechanism test fixtures
validly re-impl a builtin on a primitive; tightening that is logged as
its own follow-on, not a live cross-backend selection divergence (both
backends still agree once a program passes typecheck, since a single
`register_impl_shape` gate now runs before either backend's `DImpl` handler
even sees the program). Two DISTINCT types each implementing the same
interface (§4.4.2's `Speak(Dog)` + `Speak(Cat)` case), and same-short-name
types in DIFFERENT declaring modules (the "FQN dispatch-identity" work,
`specs/todos/`, 2026-07-20/21), are correctly NOT treated as overlap:
coherence is scoped to "the same type implements the same interface twice,"
not "an interface has more than one impl in the program."

**Historical note, kept for provenance.** Before this fix, the interpreter
picked the LAST-registered impl (an artifact of `Hashtbl.replace`/lexical
env-prepend ordering) and the compiled backend's TIR lowering picked the
FIRST-registered impl (`collect_iface_impls`'s `already`-guarded
`List.mem_assoc` check, `lib/tir/lower.ml`): two different, both
non-specificity-aware, deterministic-but-disagreeing selection rules. That
mechanism no longer runs on any program that reaches either runtime, because
`register_impl_shape` now rejects the overlapping-impl shape at typecheck
before either backend's `DImpl`/lowering handler is invoked. This is the
same kind of resolution §4.2.1 documents for the (unrelated) `ERecordUpdate`
missing-field case: a truly OPEN divergence that got ADJUDICATED AND
CONVERGED, not a divergence left in place without notice. `specs/todos/`'s
impl-coherence entries are the closeout record; `core-march-types.md` §2.3's
`(T-Impl)`/`(T-ImplMatch)` sections should be read alongside this one for
the typing-side mechanics of the new check (re-verify that section's own
staleness independently; it was written from the same 2026-07-06 vintage
this subsection was).

### 4.4.4 `derive`/`satisfy`-generated impls run through the SAME dispatch rules as hand-written ones

`core-march-types.md` §2.4 documents `derive`/`satisfy` as DESUGAR-time
generators of ordinary `DImpl` blocks; this subsection is the one-sentence
operational consequence, kept short because there is truly no new material
to specify here: **once desugar has expanded a `derive`/`satisfy` node,
`(E-Dispatch-Builtin)`/`(E-DImpl)` above cannot tell the difference between a
generated impl and a hand-written one.** A `derive Eq, Show for Color`
produces `impl Eq(Color)`/`impl Show(Color)` blocks targeting the REAL
interface names, so, being `Eq`/`Show`, they register into `impl_tbl`
exactly as `t28_derive_impl_tbl_dispatch` already witnesses (§4.4.2); a
`satisfy Named for Person` produces an `impl Named(Person)` block for a
user-defined interface, so, `Named` not being on the four-name allowlist,
it takes the general-interface `iface_method_tbl` type-dispatcher path
(§4.4.2, corrected 2026-07-22), exactly like any hand-written
`impl Named(Person)` would (`accept/t30_satisfy_wiring`,
`specs/lang/types/accept/`, run-witnessed: `name(Person("Ada"))` prints
`Ada`). **STALE → CORRECTED:** this subsection used to point at §4.4.3's
"coherence divergence" and cite a derive-vs-manual-impl overlap probe as a
third confirmed instance of a last-registered-wins/first-registered-wins
split. §4.4.3 was rewritten 2026-07-22, and that split no longer exists: a
`derive`-generated impl and a hand-written impl of the same `(interface,
type)` pair are indeed impossible to distinguish by the time either backend's
`DImpl` eval/lowering handler sees them, but they are now caught and
REJECTED by `register_impl_shape`'s coherence check before either handler
runs (confirmed live: `derive Eq for Color` followed by a hand-written
`impl Eq(Color)` fails `--check` with `Overlapping implementation`, citing
the derive-expansion's synthesized span); see §4.4.3 for the current rule
and evidence. Being `derive`-generated still doesn't exempt an impl from the
overlap rule; the rule itself changed from "silently diverges per backend"
to "rejected at typecheck."

The one operationally-relevant special case is `Json`'s pseudo-interfaces,
and it does NOT fit either of the two clean patterns above: it is a real
third case. `derive Json for T` generates impls under `"JsonTo"`/`"JsonFrom"`,
names that are on neither the `is_type_dispatched_method` nor
`is_type_dispatched_iface` allowlists (`eval.ml:270–273`, `:287–289`), yet
`DImpl`'s eval handler special-cases them by NAME anyway via its own
`is_json_iface` check (`eval.ml:8288–8290`, `String.sub … 0 4 = "Json"`;
the identical string-prefix test as `core-march-types.md` §2.4's
`is_json_derive` on the typecheck side, independently duplicated rather than
shared): the `to_json` method (under pseudo-interface `JsonTo`) registers
into `impl_tbl` (same as a type-dispatched method would) but is
INTENTIONALLY NOT ALSO bound as a bare name in the returned `env`
(`eval.ml:8335`: `if (is_json_iface && mname.txt = "to_json") || is_dispatched
then env else new_env`; the bare-binding step is skipped), specifically so
a second `derive Json` for a different type doesn't shadow the first type's
`to_json` closure in lexical scope; the polymorphic `to_json`/`from_json`
BUILTINS (`eval.ml:3383–3391`, `:3392–3453`) are what ordinary call sites
actually invoke, and they read `impl_tbl` directly by the argument's dynamic
type (cross-referenced from `core-march-types.md` §2.4's `is_json_derive`
note). The `from_json` method (under pseudo-interface `JsonFrom`), by
contrast, DOES get bound as a bare name in `env` in addition to `impl_tbl`:
the comment at `eval.ml:8329–8331` explains why the two methods are treated
asymmetrically: `from_json` cannot be dispatched by `impl_tbl` at the
BUILTIN's own call site, because the builtin only has a `JsonValue` argument
in hand, not yet a value of the TARGET type to look up `impl_tbl` by, so
the standalone `from_json` builtin (`eval.ml:3392–3453`) instead inspects the
JSON payload's own embedded type-tag by structure, and the bare `env`
binding exists as a secondary, lexically-scoped path for direct
`from_json(v)` calls that already know their target type from context.

### 4.7 Module declaration, nesting, and name resolution

This subsection specifies **`DMod`** (`mod Name do … end`): declaration,
nesting, how a module contributes names to its enclosing scope, and how bare
vs. qualified references resolve at runtime. `core-march-types.md`'s Task 3
section documents the corresponding TYPING side (`pub_set`-filtered export,
the `ex_public` visibility gate, the no-per-module-type-namespace design
point): **visibility (`pfn`/`ptype` privacy) is a TYPECHECK-time concept**;
this subsection describes what the EVALUATOR itself does, which, as the note
at the end of this subsection makes precise, exports unconditionally by
*declaration*, not by *publicity*.

**(E-DMod)**

```
(E-DMod)    ρ ⊢ eval_mod_decls(decls, ρ ⊳ stubs) ⇓ ρ_mod                    eval.ml:8168–8226
            own = declared_names(decls)                                    eval.ml:8231–8248
            ρ' = { (Name.k, v) | (k, v) ∈ ρ_mod, k ∈-prefix own }          eval.ml:8250–8271
            ─────────────────────────────────────────────────────────────
            ρ ⊢ DMod(Name, _, decls) ⇓ ρ' @ ρ
```

Concretely, from `lib/eval/eval.ml:8168–8276` (the `DMod` arm of `eval_decl`):

1. **Entry: `module_stack`.** `module_stack := name.txt :: !module_stack`
   (`eval.ml:8170`) pushes the module's name; it is popped
   (`module_stack := List.tl !module_stack`, `eval.ml:8227`) once the module's
   own declarations have all been evaluated. This stack is what
   `current_doc_prefix ()` (`eval.ml:342–345`) reads to qualify doc-comment
   keys, and (read again at `eval.ml:314`/`339`) is the same stack `EField`'s
   qualified-lookup path (§4.2's prose note, "`EField` also doubles as
   qualified module-member access") consults when flattening a dotted
   reference; nesting is therefore represented at eval time as an ordinary
   stack push/pop around a normal (non-tail-recursive) recursive descent:
   **nesting depth is unlimited** (no depth check anywhere in the arm),
   matching the survey's live probe (`mod Main do mod A do mod Inner do … end
   end end` evaluates and typechecks with no special-casing).
2. **Two-pass body evaluation** (`eval.ml:8171–8226`, `eval_mod_decls`). Same
   shape as top-level `DFn` mutual recursion: a first pass installs a
   `<stub:name>` closure (`eval.ml:8175–8176`) for every `DFn` in the module's
   OWN decl list, so a forward reference from one sibling fn to another
   (declared later in the same `mod` body, or mutually recursive with it)
   resolves; the second pass (`eval_mod_decls`, `eval.ml:8181–8224`) iterates
   over `decls` in order, replacing each stub with its real `VClosure`/
   `VMultiarity` binding (multi-arity clause grouping mirrors the top-level
   `DFn` overloading rule, `eval.ml:8208–8216`) and threading the accumulating
   env through `inner_ref` so a nested `DMod` inside this one sees all of its
   elder siblings' bindings, exactly like ordinary top-level sequencing.
3. **Export: the `own_names` gate** (`eval.ml:8228–8271`). After the body
   finishes, `declared_names` (`eval.ml:8231–8248`) walks the module's OWN
   `decls` list ONLY (not `mod_env`, which also contains everything inherited
   from the outer scope) and collects every name **this module itself
   declares**: `DFn` names, `DLet` pattern-bound variables (including nested
   tuple/ctor patterns, `eval.ml:8235–8241`), nested `DMod` names, and
   `DExtern` fn names (`eval.ml:8243–8245`). `is_own_key`
   (`eval.ml:8250–8256`) then filters `mod_env`'s bindings to just those keys
   equal to, or dot-prefixed by, an `own_names` entry (so `"B.f"` is kept when
   `B` is itself a declared sub-module, letting a nested module's own
   qualified exports flow through transitively); every kept `(k, v)` pair is
   re-prefixed to `"Name." ^ k"` (`eval.ml:8257–8261`) and, after
   deduplicating so a module's own binding wins over a same-named binding
   that just leaked in from the outer scope via `inner_ref`
   (`eval.ml:8262–8271`, comment explains the `"MyNet.connect"` motivating
   case), the resulting `"Name.member"` bindings are (a) prepended onto the
   returned environment (`prefixed @ env`, `eval.ml:8276`; so unqualified
   code in THIS scope can still see them qualified) and (b) also written into
   the global `module_registry` hashtable (`eval.ml:8272–8275`), the
   single cross-module lookup table `EField`'s qualified-access fallback
   reads from (§4.2's prose note; `eval.ml:313–320`'s doc comment: "a closure
   captured in Router can call UsersController.index even if
   UsersController hadn't been evaluated yet when Router was defined, because
   the lookup happens at call time against this registry"). **This is the
   mechanism by which a module "exports its declared names as `Mod.name`
   into the outer scope."**
4. **`own_names`, not `pub_set`: the visibility caveat, stated exactly.**
   The gate at step 3 is keyed on **`own_names`: names this module
   DECLARED**, independent of whether a declaration used `fn`/`pfn` or
   `type`/`ptype`. Typecheck's corresponding `DMod` export step
   (`typecheck.ml`, documented in `core-march-types.md`'s Task 3 section)
   additionally filters by **`pub_set`: names this module marked PUBLIC**,
   a strictly narrower set for any module with at least one private member.
   **The evaluator therefore exports every name a module declares, public or
   private, into `module_registry` and the returned env**: no code in
   `eval.ml`'s `DMod` arm itself checks `Ast.Public`/`Ast.Private`. This is
   not a bug in the interpreter: cross-module privacy enforcement is a
   TYPECHECK-time gate (`load_module_into_env`'s `ex_public` check,
   `typecheck.ml:657–692`, extended to `ExFn`/`ExValue` by the visibility fix
   landed earlier in this widening slice, commit `c0570d16`) that runs BEFORE
   `eval.ml` even sees the program; every construct this reference's golden
   corpus and the `specs/lang/types/` corpus exercise passes through
   `--check` first, so a private cross-module reference is already rejected
   before eval-time export semantics come into play. `eval.ml`'s "export
   everything declared" behavior is an **available-if-typecheck-is-skipped**
   fact worth stating exactly rather than leaving implicit, since a
   hypothetical future eval-only entry point (bypassing typecheck) would not,
   on its own, re-enforce privacy, the same caveat the survey raises in its
   §1 closing note.

**Bare vs. qualified resolution.** A bare, unqualified reference (`f()`) is
ordinary `lookup_var`/`env.vars` lookup: it is **never** auto-satisfied by a
sibling nested module's export, public or not, because a sibling module's
names only enter the enclosing scope under the `"Name.member"` qualified
key (step 3 above), never under the bare `member` key. Confirmed live:

```march
mod Main do
  mod A do
    fn f() : Int do 1 end
  end
  fn main() : Int do f() end          -- bare — A never bare-exports "f"
end
```
rejects with `` I cannot find `f`. Did you mean `%`? `` (exit 1), while changing
the call site to the qualified form `A.f()` typechecks (exit 0) and, run
interpreted, evaluates to `1` (see `accept/t32`, below, for the pinned
corpus witness). This is exactly what the export rule above predicts: `A`'s
`own_names` include `f`, so `mod_env`'s `"f"` binding is re-exported as
`"A.f"` (never as bare `"f"`) into `Main`'s scope.

**The lexical-scoping nuance: a `pfn` nested lexically inside `A` IS callable
bare from a module nested inside `A`.** This is not an exception to the rule
above; it falls out of ordinary lexical `env` threading (step 2): a nested
`DMod Inner` inside `A` is evaluated by `eval_mod_decls` with `A`'s own
`inner_ref` env already in scope (the same fold that threads elder siblings'
bindings to younger ones, per step 2), so `Inner`'s body sees `A`'s `secret`
binding as an ordinary, unqualified lexical variable, exactly as it would see
any other outer-scope `let`-bound name. Confirmed live:

```march
mod Main do
  mod A do
    pfn secret() : Int do 42 end
    mod Inner do
      fn call_secret() : Int do secret() end     -- bare call, lexically inside A
    end
  end
  fn main() do println(int_to_string(A.Inner.call_secret())) end
end
```
typechecks (exit 0) and, run interpreted, prints `42`, pinned as
`accept/t33`, below. `secret` being declared `pfn` (private) is irrelevant to
THIS resolution path: privacy (per the typing reference) only gates
CROSS-module qualified access, not same-module (including nested-submodule)
LEXICAL access: `Inner` is textually inside `A`, so it is not "another
module" from the visibility rule's point of view any more than a `let` bound
in an outer block is invisible to an inner block.

**One-mod-per-file.** Confirmed live (re-grepped `lib/parser/parser.mly:240–245`;
this is a GRAMMAR-level rejection, a dedicated Menhir production with an
`error` token right after a complete `MOD … END`, not a later semantic pass
over an already-parsed file):
```march
mod A do
  fn f() : Int do 1 end
end

mod Main do
  fn main() : Int do A.f() end
end
```
rejects with the exact message
`` A file may have only one top-level `mod`; everything else must live inside it. ``
(exit 1): every declaration besides the file's single top-level `mod` must
live INSIDE it (nesting, per this subsection, is unlimited). This is the
file-wrapper rule the grammar reference documents at
`specs/lang/surface-syntax.md`'s "Module" section ("Every file must start with
a module declaration"); this subsection adds the precise rejection mechanism
and message for the two-top-level-`mod` case, which the grammar reference
does not itself spell out.

**Value-witness corpus** (`specs/lang/types/accept/`, run interpreted to
confirm the printed value, not just `--check`ed; see `t27`–`t30` for the
prior practice of this reference's corpus doubling as an operational witness):

- **`accept/t32_qualified_cross_module_call`**: `A.double(21)` from `Main`,
  a plain qualified cross-module call to a public fn in a sibling nested
  module; prints `42`. Witnesses the export mechanism (step 3) and the
  qualified-resolves/bare-fails imbalance above.
- **`accept/t33_nested_module_lexical_resolution`**: `A.Inner.call_secret()`
  calls a `pfn` bare, from a module nested directly inside its declaring
  module; prints `42`. Witnesses the lexical-scoping nuance above.

### 4.7.1 `use` / `import` / `alias`: surface selectors and the file-based resolver pre-pass

**Widening slice 2, Task 4.** §4.7 above describes how a module *already
present in the same compilation unit* (a same-file nested `mod`, or a
stdlib/`MARCH_LIB_PATH` file the compiler auto-splices as a real `DMod`)
exports its names as qualified `"Name.member"` keys. This subsection covers
the surface mechanism that either (a) rebinds some of those already-exported
qualified keys as bare unqualified names inside the CURRENT module's own
scope (`use`/`import`/`alias`, a typecheck-time-only rebinding; see below),
or (b) is the reason a name got spliced in as a real `DMod` at all in the
first place, when it lives in a SEPARATE FILE the entry file references by
name (the resolver pre-pass). These are two different mechanisms living at
two different pipeline stages, and the distinction is exactly where the
surprising behavior below comes from.

**Surface forms and their AST (`lib/ast/ast.ml:203–217`):**

```ocaml
and use_decl = { use_path : name list; use_sel : use_selector }
and alias_decl = { alias_path : name list; alias_name : name }
and use_selector =
  | UseAll               (* .*  *)
  | UseNames of name list (* .{f, g}  or  a single lowercase .foo *)
  | UseSingle             (* bare `use A` — path only, no new bindings *)
  | UseExcept of name list (* Elixir-only: except: [f, g] *)
```

Both March-native `use` (`parser.mly:647–672`) and Elixir-style `import`
(`parser.mly:679–700`) parse to the **same `DUse` AST node**: `import` is
pure surface sugar over `use`'s selector shapes, plus its own `only:`/
`except:` keyword-argument syntax (re-grepped live, current lines):

| Surface form | Grammar production | `use_sel` | Rechecked live |
|---|---|---|---|
| `use A` (bare) | `use_decl` → `use_path_tail` empty (`parser.mly:660`) | `UseSingle` | no-op; makes `A`'s path syntactically known, binds no new name (`typecheck.ml:7272–7274`) |
| `use A.*` | `use_selector` → `STAR` (`parser.mly:668–670`) | `UseAll` | rebinds every `"A.x"` in scope as bare `x` |
| `use A.{f, g}` | `use_selector` → `LBRACE … RBRACE` (`parser.mly:671–672`) | `UseNames [f; g]` | rebinds only the LISTED names |
| `use A.foo` (single lowercase segment) | `use_path_tail` → `DOT; lower_name` (`parser.mly:665–666`) | `UseNames [foo]` | same as the one-element brace form; confirmed live, `accept/t38`-adjacent probe |
| `import A` (bare) | `import_decl` → `import_path_tail` empty (`parser.mly:692`) | `UseAll` | **differs from bare `use A`**: Elixir's bare `import` bulk-imports everything; March's bare `use` imports no names at all. Confirmed live. |
| `import A, only: [f, g]` | `COMMA; ONLY; COLON; LBRACKET … RBRACKET` (`parser.mly:693–694`) | `UseNames [f; g]` | same semantics as `use A.{f, g}` |
| `import A, except: [f, g]` | `COMMA; EXCEPT; COLON; LBRACKET … RBRACKET` (`parser.mly:695–696`) | `UseExcept [f; g]` | rebinds every public name EXCEPT the listed ones |
| `import A.{B, C}` | `DOT; LBRACE … RBRACE` (`parser.mly:697–698`) | `UseNames [B; C]` | dotted-path selector form, mixed with Elixir sugar |
| `alias A.B, as: C` / `alias A.B as C` / bare `alias A.B` | `alias_decl_rule` (`parser.mly:703–710`) | (separate `DAlias` node) | bare form defaults the short name to the LAST path segment (`parser.mly:708–710`) |

**Note the one real semantic imbalance the table above flags:** bare `use A`
and bare `import A` are NOT equivalent: `use A` is `UseSingle` (a no-op;
`A`'s members stay qualified-only unless individually `use`d), while bare
`import A` is `UseAll` (bulk-imports every public name unqualified). This
mirrors Elixir's own `import`/`alias` distinction (`import` pulls names in
by default; `alias`, and March's plain `use`, only makes the PATH known).

**What each selector brings into scope (`typecheck.ml:7268–7370`, the `DUse`
arm of `check_decl`; re-grepped live, current lines):**

- **`UseSingle`** (`typecheck.ml:7272–7274`): no-op. The module's qualified
  names were already reachable via `Mod.name` (they were spliced in as a real
  `DMod`, either same-file or via the resolver pre-pass below); `use A` adds
  no effect beyond making the bare path `A` textually acknowledged.
- **`UseAll`** (`typecheck.ml:7275–7319`): scans `env.vars`/`env.interfaces`
  for every key prefixed `"A."`, strips the prefix, and rebinds the SHORT
  name in the current scope, **skipping any short name the current module
  already defines itself** (`env.local_fns`, `typecheck.ml:7287`; a local
  definition always shadows a bulk import rather than being clobbered by it).
  Also registers an "unused import" warning (`import_tracker`) that counts
  BOTH the rebound short names AND any qualified (`A.x`) reference to the
  same module, so a module used only via full qualification does not
  false-positive as unused (`typecheck.ml:7300–7318`).
- **`UseNames names`** (`typecheck.ml:7320–7337`): for each requested name,
  looks up `"A." ^ name"` in `env.vars`; if present, binds it bare; **if
  absent, because the name doesn't exist OR because it was never exported
  (private), hard error**: `` Module `%s` does not export `%s`. `` This is
  the rejection path a selective `use`/`import` of a private or nonexistent
  member takes (see the reject-corpus discussion below).
- **`UseExcept excluded`** (`typecheck.ml:7338–7370`): same scan as
  `UseAll`, but drops any short name appearing in the exclusion list before
  rebinding the rest.
- **`DAlias`** (`typecheck.ml:7372` onward): re-exports every `"Orig.x"` key
  additionally as `"Short.x"`; `alias` does **not** hide or remove the
  original qualified path: both `A.B.f` and `C.f` remain live simultaneously
  after `alias A.B as C`.

Value-witnessed live against `List` (a real stdlib module,
`stdlib/list.march`), using `append`, a truly `List`-only public fn, not
one of the handful of names (`length`, `reverse`, `filter`, `map`) that
`stdlib/prelude.march` ALSO defines bare at global scope (so those would
misleadingly "work" even without any `use` at all):

```march
mod Main do
  use List.*                                   -- or: use List.{append}
                                                -- or: import List
                                                -- or: import List, only: [append]
  fn main() do
    println(int_to_string(length(append([1, 2], [3]))))
  end
end
```

Without a `use`/`import` of `List`, a bare `append(...)` call rejects with
`` I cannot find `append`. `` (confirmed live); with any of the four forms
above, it typechecks and, run interpreted, prints `3`, pinned as
`accept/t37_use_all_stdlib_module` (`use List.*`) and
`accept/t38_use_selector_named_import` (`use List.{append}`), below.

**The file-based resolver pre-pass (`lib/resolver/resolver.ml`), a SEPARATE
mechanism from typecheck's `DUse` handling above, and the source of the
file-vs-in-file distinction.** Before typecheck even sees the program,
`bin/main.ml`'s `resolve_imports` (`bin/main.ml:786` and its call site at
`:795–798`, delegating to `Resolver.resolve_imports`) walks every `DUse`/
`DAlias` node in the entry file (`resolver.ml:56–69`, `import_refs`,
recursing into nested `DMod`s too), extracts the FIRST path segment of each
(`"List"`, `"Array"`, …) as a module name, and tries to locate that name as
an actual **file on disk**:

```
module_name_to_filename "MyApp.Router"  =  "my_app/router.march"          resolver.ml:29–32
find_file mod_name = search_path                                          resolver.ml:184–190
                       |> List.find_map (fun dir ->
                            let p = dir / module_name_to_filename mod_name
                            if Sys.file_exists p then Some p else None)
search_path = source_dir :: extra_lib_paths @ MARCH_LIB_PATH-dirs         resolver.ml:149–156
```

If found, the file is parsed, desugared, and wrapped in a real `DMod`
(`resolver.ml:239–244`), then spliced into the entry file's own
`mod_decls` as `extra_decls` (`bin/main.ml:786–798`), at which point it is
typechecked through the exact same `DMod`/`pub_set` export gate §4.7
describes, and `use A.*`'s `UseAll` rebinding (above) has real `"A.x"` keys
to draw from. Stdlib modules (`List`, `Array`, …) are ALSO pre-spliced this
same way, just via a separate `load_stdlib` call (`bin/main.ml:284–323`, the
`stdlib_module_names` allowlist in `resolver.ml:38–51` additionally
SUPPRESSES the "not found" error for these specific names since they are
known to be provided by the bundled stdlib rather than the project's own
source tree), which is why `use List.*`/`use Array.{…}` above work with no
extra setup: `List`/`Array` are real files (`stdlib/list.march`,
`stdlib/array.march`) the compiler always loads.

**The critical, surprising consequence: `use`/`import`/`alias` are a
file-resolution mechanism: they do NOT reach a same-file nested `mod` at
all.** A same-file nested module (§4.7's `mod Main do mod A do … end end`) is
not a file; the resolver's `find_file` looks for `a.march` on disk, does not
find one (there IS no such file; `A` only exists as an in-memory `DMod`
already nested inside `Main`), and rejects. Confirmed live:

```march
mod Main do
  mod A do
    fn f() : Int do 1 end
  end
  use A.*
  fn main() : Int do f() end
end
```

rejects with the EXACT message
`` Module `A` not found (looked for `a.march` in the source directory) ``
(`resolver.ml:206–211`, exit 1), even though `A` is clearly present, right
there in the same file, and its public `f` is perfectly reachable via
ordinary qualification (`A.f()`, §4.7) without any `use` at all. The
resolver's notion of "module A" (a FILE named `a.march`) and typecheck's
notion of "module A" (an in-memory `DMod` node already sitting in the AST)
are simply disjoint concepts that happen to share a name: `use`/`import`
only operates on the FIRST kind. This is not a bug to fix in a
docs-only task; it is documented here exactly because it is real and
easy to trip over: reaching for `mod`/nesting + qualification (§4.7) for a
same-file module, and reaching for `use`/`import` only when the module
truly lives in its own `.march` file, are two different, non-overlapping
tools. The same rejection shape covers `import A` (bare Elixir sugar),
`import A, only: [f]`, `import A, except: [g]`, and `alias A.B as C` against
the same in-file `A`: all five forms funnel through the identical
`resolver.ml` pre-pass and produce the identical "not found" message,
confirmed live for each.

**Selective `use` of a non-exported (private) name: consistent with the
cross-module visibility fix.** `use`/`import`'s `UseNames`/`UseExcept` arms
(above) look up `"Mod.name"` in `env.vars`, the SAME `env.vars` that the
`DMod` export step (§4.7, and `core-march-types.md` §2.5's `pub_set` gate)
populates only for PUBLIC members. So a selective `use` of a private stdlib
function fails for exactly the same underlying reason a plain qualified
reference to it does (`core-march-types.md` §2.5's `reject/t26`): the key
was never written into `env.vars` in the first place. Confirmed live against
`Array.lst_rev`, a real `pfn` (`stdlib/array.march:39`, the same function
`reject/t26_cross_module_private_fn` exercises via plain qualification):

```march
mod Main do
  use Array.{lst_rev}
  fn main() : Int do 0 end
end
```

rejects with `` Module `Array` does not export `lst_rev`. `` (exit 1),
pinned as `reject/t27_use_selector_private_name`, below. Note the message
text differs from `reject/t26`'s `` … is private to module `Array`. `` even
though both trace back to the identical `pub_set` absence: `UseNames`'s
lookup (`typecheck.ml:7333–7336`) only sees "found" or "not found" in
`env.vars` and cannot distinguish "truly doesn't exist" from "exists but
is private" the way `resolve_qualified_var`'s dedicated
`qualified_error_msg` (which DOES draw that distinction, `typecheck.ml:750–
779`) can, but the OUTCOME (reject, exit 1) is the same, so selective `use`
of a private member is exactly as rejected as bare qualified access to it,
consistent with the visibility fix landed earlier in this widening slice.
A selective `use` of a nonexistent (never-defined) member of a real module
produces the identical "does not export" message and is impossible to distinguish
from the private case by the text on its own; both are, correctly, hard rejections.

**Scope boundary: `MARCH_LIB_PATH` multi-file discovery is build-tooling, out
of this reference's scope.** The resolver's `search_path` (`source_dir ::
extra_lib_paths @ MARCH_LIB_PATH`-dirs, `resolver.ml:149–156`) and its
auto-discovery walk (`resolver.ml:105–129`'s `collect_lib_files`, plus the
two-phase parse-then-depth-sort auto-splice step in `resolve_imports`,
`resolver.ml:287–349`, which loads every `.march` file reachable from the
library search path even WITHOUT an explicit `use`, so that qualified
cross-module calls to a file with a declared module name that doesn't match its
filename still resolve) are project/build-tooling mechanics (how multiple
files become one compilation unit), not language-level typing or evaluation
semantics. `CLAUDE.md`'s "Multi-file compilation (MARCH_LIB_PATH)" section
and `resolver.ml`'s own doc comment (`resolver.ml:1–10`) are the canonical
description of the discovery walk itself; this reference only documents what
happens to a name ONCE its module has been resolved into a real `DMod` (the
`use`/`import`/`alias` rebinding rules above, and §4.7's export/resolution
rules), not the directory-walking/filename-convention mechanics that get it
there.

**Corpus** (`specs/lang/types/accept|reject/`, run interpreted where noted to
confirm the printed value, not just `--check`ed):

- **`accept/t37_use_all_stdlib_module`**: `use List.*` brings `List`'s
  public names (including `append`, not shadowed by `prelude.march`) into
  bare scope; prints `3`. Witnesses `UseAll`'s rebinding rule and the
  resolver pre-pass successfully locating a real stdlib file.
- **`accept/t38_use_selector_named_import`**: `use List.{append}` imports
  exactly the one named public function; prints `3`. Witnesses `UseNames`'s
  narrower, per-name rebinding rule.
- **`reject/t27_use_selector_private_name`**: `use Array.{lst_rev}`, a
  selective import of a real PRIVATE `pfn`; rejects with `` Module `Array`
  does not export `lst_rev`. `` Witnesses that selective `use` is exactly as
  gated by the cross-module visibility fix as plain qualified access
  (`reject/t26`).

### 4.8 Relationship to the small-step form (the metatheory target)

`specs/lean4-metatheory-plan.md` will state the semantics as a **small-step**
relation `e → e'` (for progress + preservation). The standard call-by-value,
left-to-right small-step system (evaluation contexts `E ::= □ | E(e…) | v(…E…e) |
C(…E…e) | if E then e else e | match E of …`, β-reduction via closure-env
extension, and the δ-rules above) is **equivalent** to the big-step system here:
for closed `e`, `∅ ⊢ e ⇓ v` **iff** `e →* v`. The big-step rules are the faithful
mirror of the interpreter (used to *validate* the model against `eval.ml`); the
small-step form is the shape the proofs consume. Writing the full small-step
apparatus (contexts + the substitution-vs-environment reconciliation) is
metatheory work (the Lean track), not part of this reference; but note it is a
*refinement* of §4.2, not a different semantics.

### 4.9 Faithfulness (the candid caveat)

The §4.2–4.4 rules (and §4.7's `(E-DMod)`) were transcribed arm-for-arm from
`eval.ml` at the cited lines. That transcription is **human-reviewed, not
mechanically verified**:
this is the roadmap's §7 faithfulness risk made concrete, and it remains true
now that the core is complete: the rules are only as faithful as the review of
each citation. What *is* mechanically checked is weaker but real: the golden
corpus (§5) confirms that, on these 39 programs, the interpreter these rules
describe and the independently-written compiled backend produce identical
output. A divergence there would mean either the interpreter or the compiler is
wrong; agreement plus arm-for-arm review is the reference's correctness
evidence. This caveat does NOT weaken with completion: a complete core is a
larger transcription surface, so the golden corpus (and the CI `@oracle` sweep
it feeds) is what keeps the "spec matches the implementation" claim accurate as
the reference is relied on.

### 4.10 Actors: spawn / send / receive / `run_until_idle` (operational)

The typing reference pins **what an actor declaration checks** and **what
`spawn(Name)` produces as a type** (`core-march-types.md` §2.6; the state type
is checked, but the `Pid` parameter does not propagate to a `spawn` site). This
subsection pins the **runtime** side: how `spawn`, `send`, `receive`, and the
scheduler-drain builtin `run_until_idle` actually reduce in `eval.ml`, and (the
point of putting actor programs in the golden corpus at all) that a program
with observable output that does not depend on scheduler interleaving is
**byte-equal interpreted vs compiled**.

The actor runtime is *not* part of the pure reduction fragment of §4.2–4.4: it
is stateful (a global `actor_registry`, per-actor mailboxes) and its message
dispatch is driven by an explicit scheduler pass, not by β-reduction. The rules
below are stated operationally against `eval.ml`, in the same arm-for-arm style
as §4.2, but they describe side-effecting builtins over mutable actor state, so
they sit alongside the §4 core rather than inside the δ-table.

#### 4.10.1 `spawn`: register an `actor_inst`, return a `VPid`

`spawn(Name)` is evaluated by the `ESpawn` arm (`eval.ml:7194`). It resolves the
argument to a **literal actor name** (only `EVar` or `ECon(_, [], _)`; anything
else is `spawn: expected actor name`, mirroring the compile-time rejection of a
computed actor expression in typing §2.6.2), looks the name up in
`actor_defs_tbl`, allocates a fresh integer pid from the `next_pid` counter, and
evaluates the actor's `init { … }` expression to obtain the initial state
record. It then builds an `actor_inst` record, `{ ai_name; ai_def; ai_state =
init_state; ai_alive = true; ai_mailbox = Queue.create (); … }`, inserts it
into the global `actor_registry` hashtable keyed by the pid, and **returns
`VPid pid`**. (For a `supervise`-declared actor the arm first spawns each child,
injects their pids into the init state, and records `ai_supervisor`; that
supervision path is out of scope for the golden witnesses here.)

Observation discipline (a logged finding, honored by the witnesses): actor state
is observed ONLY through a handler that `println`s, never through an external
`get_actor_field(pid, …)` or `pid_of_int`-from-outside: `march_get_actor_field`
is a hard stub returning `None` in the compiled runtime and `march_pid_of_int`
does an unsafe int→ptr cast, so a compiled program using either **SIGSEGVs**.
Every golden witness keeps every observation on the handler-`println` /
`is_alive` path, which is why the pid returned by `spawn` is used only as the
target of `send` and never inspected.

#### 4.10.2 `send(pid, msg)`: async, non-blocking mailbox enqueue

`send(cap, msg)` is evaluated by the `ESend` arm (`eval.ml:7265`). It evaluates
the target (a `VPid` or, for capability sends, a `VCap`) and the message, and
(this is the operational fact) **pushes the message onto the target's
`ai_mailbox` (`Queue.push`) and returns immediately** with `Some(())`; it does
**not** dispatch the handler inline. Send is therefore a *pure async enqueue*:
non-blocking, fire-and-forget. A send to a dead or unknown pid silently drops
(returns `None`). Only constructor/atom values (`VCon`/`VAtom`) are valid
messages; anything else is a `send: message must be a constructor value` error.
Because dispatch is deferred, the message ORDERING a program observes is exactly
the order of `send` calls into a single actor's mailbox (a FIFO `Queue.t`), not
an interleaving, which is what makes a single-actor, strictly-ordered send
sequence deterministic (§4.10.5).

The compiled backend implements the same async-mailbox semantics over green
threads rather than an OCaml `Queue.t` (see `runtime/march_scheduler.c` for the
scheduler context); the golden witnesses assert that, for interleaving-free
programs, the two implementations agree down to the byte.

#### 4.10.3 `receive()`: pop the mailbox, or `BlockedOnReceive`

`receive()` is the builtin at `eval.ml:3076`. Called inside a handler (it errors
`receive: called outside an actor handler` otherwise), it pops the **next**
message from the *current* actor's `ai_mailbox` and returns it. If the mailbox
is empty it `raise`s the internal `BlockedOnReceive` exception rather than
returning: the scheduler catches this, re-queues the message that triggered the
current handler at the front of the mailbox, and retries the handler on a later
pass once more messages have arrived (see §4.10.4). A handler that consumes an
already-queued follow-up message (one delivered by an earlier `send` in the same
ordered sequence) therefore finds the mailbox non-empty and pops it directly.

**Documented limitation (`eval.ml` `run_scheduler`, ~:7576–7590):** only the
FIRST `receive()` call in a handler body is safe to block on. If a handler calls
`receive()` twice and the *second* one blocks (empty mailbox), the message
popped by the first `receive()` has already been consumed and is lost: the
scheduler's re-queue only restores the outer triggering message, not the
mid-handler pop. Handlers needing multiple messages should use a recursive
pattern where each `receive()` is the first operation in its own handler body.
The `receive()` golden witness (`g36`) calls `receive()` exactly once and on a
mailbox that is already non-empty, so it neither blocks nor trips this
limitation.

#### 4.10.4 `run_until_idle()`: drain the scheduler to a fixed point

`run_until_idle()` is the builtin at `eval.ml:3067`: `[] -> !run_scheduler_hook
(); VUnit`. The hook target is `run_scheduler` (`eval.ml:7523`). It runs a
**cooperative drain loop**: repeatedly, until a full pass produces no work, it
iterates over a snapshot of every live actor and, for each with a non-empty
mailbox, pops one message, finds the `on Msg(…)` handler with the message tag that
matches, binds `state` to the actor's current `ai_state` plus the message
payload as handler params, evaluates the handler body, and **replaces the
actor's state with the handler's return value** (the new state record). A
handler that raises `BlockedOnReceive` has its triggering message re-queued (no
forward progress marked); a handler that raises any other exception crashes the
actor (supervision path). The loop terminates when a whole pass over all actors
finds every mailbox empty: the *idle* fixed point.

Because a message with no matching handler is silently dropped and an
arity-mismatched handler consumes-without-crashing, the observable output of a
drained program is a pure function of (the initial states, the ordered messages
each mailbox received). For a program that sends a fixed, strictly-ordered
sequence into a single actor and then calls `run_until_idle()` exactly once,
that function is deterministic and independent of any scheduling choice.

#### 4.10.5 The determinism property, and the golden witnesses

**Verified property.** For an actor program where the observable output does not
depend on scheduler interleaving (concretely: a single observable actor, or a
set of actors with no cross-actor ordering dependence, fed a strictly-ordered
`send` sequence and drained by one `run_until_idle()`, printing its result from
a handler) the `println` output is DETERMINISTIC and **byte-equal
interpreted vs compiled**. This is not a claim about arbitrary concurrent actor
programs (their interleaving-dependent output is intentionally excluded from the
golden corpus); it is the narrow, mechanically-checked property that the two
independently-written backends agree on the interleaving-free slice.

Two golden programs witness it (both `MATCH` under `verify.sh`; see §5):

- **`g35_actor_spawn_send`**: the spawn + async-send + `run_until_idle`
  witness. A single `Counter` actor is spawned; `Inc(1)`, `Inc(3)`, `Inc(4)` are
  sent in order (each handler returns the new `{ count: … }` state), then a
  `Report()` handler prints the accumulated count; one `run_until_idle()` drains
  all four in FIFO order. Output: `count=8` then `done`.
- **`g36_actor_receive`**: the `receive()`-mediated follow-up witness. An
  `Inbox` actor's `on Start()` handler calls `receive()` once to pop the
  already-queued `Follow(99)` (sent immediately after `Start()`, so it is in the
  mailbox before dispatch) and prints its payload. Output: `got=99` then `done`.
  This exercises the pop-or-`BlockedOnReceive` rule (§4.10.3) on the non-blocking
  path and honors the once-per-handler limitation.

Both programs keep every observation on the handler-`println` path (never
`get_actor_field` / `pid_of_int`), so neither SIGSEGVs compiled, the
precondition for being a golden `MATCH` at all.

#### 4.10.6 Lifecycle (`kill` / `is_alive`) and epoch-stamped capabilities

§4.10.1–.5 pin the message plane (spawn / send / receive / drain). This
subsection pins the **lifecycle plane**: how an actor is killed, how its
liveness is observed, what a send to a dead actor does, and the epoch-stamped
`Cap` mechanism by which a capability held across a restart is rejected. As with
the rest of §4.10, these are side-effecting builtins over mutable actor state,
stated operationally against `eval.ml`.

**`kill(pid)` (`eval.ml:2961`): force-crash an actor.** The arm is
`[VPid pid] -> crash_actor pid "killed"; VUnit`. It delegates to `crash_actor`
(`eval.ml:1766`), which, for a live actor, sets `inst.ai_alive <- false`
(`eval.ml:1772`), runs the actor's resource-cleanup thunks and linear-value drop
handlers in reverse acquisition order, notifies any supervisor/monitors, and
crashes bidirectionally-linked actors. `crash_actor` is idempotent: killing an
already-dead actor (`Some inst when not inst.ai_alive`) or an unknown pid is a
no-op. `kill` itself returns `VUnit`.

**`is_alive(pid)` (`eval.ml:2964`): observe liveness as a `Bool`.** It looks
the pid up in the global `actor_registry`; a live/dead registered actor returns
`VBool inst.ai_alive`, and an **unknown pid returns `VBool false`**. This is the
one lifecycle observation that is SAFE under the compiled backend: it is a pure
registry lookup returning a boolean, touching no mailbox and dereferencing no
actor payload; unlike `get_actor_field`/`pid_of_int` (the §4.10.1 SIGSEGV
finding), `is_alive` is byte-equal interpreted vs compiled. The typing side
pins its signature as `is_alive : Pid(a) -> Bool` (`core-march-types.md` §2.6.3,
`typecheck.ml:1341`); `kill : Pid(a) -> Unit` (`typecheck.ml:1340`).

The lifecycle witness is **`g37_actor_lifecycle`** (§5): `spawn` a `Counter`
(→ `ai_alive = true`, so `is_alive` is `true`), then `kill` (→ `ai_alive =
false`, so `is_alive` is `false`), each printed via a `Bool→String` helper.
Output `alive=true` / `alive=false`, `MATCH` under `verify.sh`.

**Send to a dead actor: verified behavior.** A plain `send(pid, msg)` to a
dead or unknown pid is a **silent fire-and-forget drop returning `None`**: the
`ESend` arm (`eval.ml:7265`) returns `VCon ("None", [])` for both the
`None` (unknown pid) and `Some inst when not inst.ai_alive` (killed) cases, and
`Some(())` only on a successful enqueue. It does **not** raise. A `send_checked`
on a stale/dead cap returns the `:error` atom (below) rather than `None`. Both
were verified live in the interpreter (`send(dead) = None`,
`send_checked(dead) = :error`).

> **Fixed 2026-07-18: the capability/dead-send plane is now byte-equal.**
> The dead-actor and capability paths used to diverge between the interpreter
> and the compiled backend; both are now aligned and pinned by
> `test/native/cap_epoch_plane`:
>
> | Probe (single actor) | interpreted | compiled |
> |---|---|---|
> | `send(dead_pid, Msg)` | `None` | `None` |
> | `send_checked(live_cap, Msg)` | `:ok` | `:ok` |
> | `send_checked(dead_cap, Msg)` | `:error` | `:error` |
> | `get_cap(dead_pid)` | `None` | `None` |
> | `get_cap(live_pid)` / `send(live_pid, Msg)` / `is_alive` | `Some` / `Some` / bool | `Some` / `Some` / bool (agree) |
>
> `march_send_checked` (`runtime/march_runtime.c`) now checks the revocation
> table, then the actor's current epoch against the epoch written into the cap, then
> liveness, before enqueuing, returning `march_atom_of_name("ok"/"error")` to
> match the interpreter exactly, rather than an uninterned atom. `march_get_cap`
> gates on liveness (niche `None` for a dead/unknown pid). The epoch-`Cap` rules
> below apply to both backends.

**Epoch-stamped capabilities (`Cap`): the interpreter's model.** A capability
is `VCap of int * int = (pid, epoch)` (`eval.ml:48`): a send-permit tagged with
the actor's restart epoch at the moment it was issued. The registry stores a
per-actor monotone `ai_epoch` counter (`eval.ml:110`) and a global
`revocation_table : (int*int, unit) Hashtbl.t` (`eval.ml:389`). The invariant
(`eval.ml:384–388`): **a cap is invalid iff its `(pid, epoch)` is in the
revocation table OR the actor's current `ai_epoch` differs from the cap's epoch**
(a restart occurred) OR the actor is dead/unknown.

- **`get_cap(pid)` (`eval.ml:3129`)**: the ONLY surface way to obtain a `Cap`.
  Returns `Some(Cap(pid, inst.ai_epoch))` if the actor is alive, else `None`.
  Typed `get_cap : Pid(a) -> Option(Cap(a))` (`typecheck.ml:1473`).
- **`send_checked(cap, msg)` (`eval.ml:3137`)**: a validated send. Returns the
  `:ok` atom iff the actor is known, alive, `inst.ai_epoch = cap_epoch`, and
  `(pid, cap_epoch)` is **not** in the revocation table; otherwise `:error`. On
  `:ok` it enqueues `msg` on the mailbox asynchronously (call `run_until_idle()`
  to process; same async plane as §4.10.2). Typed
  `send_checked : Cap(a) -> a -> Atom` (`typecheck.ml:1474`; curried: one
  message arg, not a `(Cap, msg)` pair).
- **`revoke_cap(cap)` (`eval.ml:3164`)**: adds `(pid, epoch)` to the revocation
  table and returns `:ok` (idempotent). **`is_cap_valid(cap)` (`eval.ml:3172`)**
  is the boolean form of the invariant above. Both are registered in the
  typechecker's builtin table (`typecheck.ml:2342–2343`) and are ordinary
  surface-callable builtins on both backends; the compiled runtime implements
  the matching pair `march_revoke_cap`/`march_is_cap_valid`
  (`runtime/march_runtime.c`).

**Two invalidation paths.**

1. **Explicit revoke.** `revoke_cap(cap)` records `(pid, epoch)` in the
   revocation table; a subsequent `send_checked(cap, …)` matches the
   revocation-table arm and returns `:error`. Deterministic, no supervisor
   needed, and expressible in a pure surface program on either backend.
2. **Restart (epoch staleness).** A supervised restart replaces the crashed
   instance with a fresh one with an epoch of `old.ai_epoch + 1`
   (`spawn_child_actor`, `eval.ml:1512–1518`; `increment_epoch` at
   `eval.ml:1100` bumps `ai_epoch <- ai_epoch + 1`). A `Cap` captured **before**
   the restart therefore has a stale epoch, so `send_checked` hits the
   `inst.ai_epoch <> cap_epoch` arm and returns `:error`: the capability is
   auto-invalidated across the restart without any explicit revoke. The
   **restart-triggered** witness (a supervisor crashing and restarting a child,
   then a pre-restart `Cap` being rejected) belongs to the **supervision**
   subsection (§4.10.7); this subsection documents the epoch-staleness *rule* and
   cites it; §4.10.7 covers the end-to-end restart case.

#### 4.10.7 Supervision (`one_for_one` restart + epoch invalidation)

§4.10.6 pinned the lifecycle plane (`kill`/`is_alive`) and the epoch-stamped
`Cap` mechanism, but left the actual **restart** (the event that bumps an
actor's epoch) to this subsection. Supervision is how a crashed child is
automatically respawned; a restart is the concrete producer of the "epoch
staleness" invalidation §4.10.6 described in the abstract. As with the rest of
§4.10, this is stated operationally against `eval.ml`; the child-observation
surface (`get_actor_field`/`pid_of_int`, and the supervisor's spawn-time child
`init`) is byte-equal on both backends as of 2026-07-08 (below), so this
subsection's semantics apply equally to compiled binaries.

**Supervisor declaration (static form).** An actor becomes a supervisor by
including a `supervise` block in its definition, which the parser stores as
`actor_supervise : supervise_config option` on the `actor_def` (`ast.ml:276`;
`Some` ⇔ this actor is a supervisor). The block names a restart `strategy`, a
`max_restarts N within S` budget, and a list of `ChildActor field` children:

```march
actor Worker do
  state { count : Int }
  init do
    println("worker init")
    { count: 0 }
  end
  on Work() do { count: state.count + 1 } end
end

actor Sup do
  state { wa : Int, wb : Int }
  init  { wa: 0, wb: 0 }
  supervise do
    strategy one_for_one
    max_restarts 5 within 60
    Worker wa
    Worker wb
  end
end
```

`spawn(Sup)` (the `ESpawn` supervisor arm, `eval.ml:7207–7254`) eagerly
instantiates each declared child: it evaluates each child's `init`
(`eval.ml:7220`), allocates a child `actor_inst` with `ai_supervisor = Some
sup_pid` (`:7228`), and overlays the child pids into the corresponding
supervisor-state fields (`wa`/`wb` become the children's `VInt` pids, `:7240–
7251`). The `supervise_config` record is `{ sc_fields; sc_strategy;
sc_max_restarts; sc_window_secs; sc_order }` (`ast.ml:264–270`).

**`one_for_one`: a child crash restarts just that child.** When a supervised
child crashes, `crash_actor` (`eval.ml:1766`), after marking it dead and running
its cleanup, notifies its supervisor via `notify_supervisor sup_pid pid`
(`eval.ml:1816`). `notify_supervisor` (`:1748`) dispatches on the supervisor's
static strategy enum (`sc_strategy`, `:1756–1762`):

- `OneForOne  -> one_for_one_restart` (`eval.ml:1760`)
- `OneForAll  -> one_for_all_restart` (`:1761`)
- `RestForOne -> rest_for_one_restart` (`:1762`)

`one_for_one_restart` (`eval.ml:1545`) locates which supervisor-state field held
the crashed pid (`:1553–1557`), checks the `max_restarts`-within-`window` budget
(`:1574–1581`; exceeding it crashes the supervisor itself, `:1581`), then calls
`spawn_child_actor` (`:1586`, definition `:1505`) to allocate a **fresh** child
instance and rewrites just that field to the new pid (`:1588–1592`). The
siblings' pids and instances are untouched; that is the `one_for_one` property:
only the crashed child is replaced. `one_for_all_restart` (`:1597`) and
`rest_for_one_restart` (`:1648`) exist and implement the "restart all" and
"restart the crashed child + all declared after it" policies respectively; this
subsection focuses on `one_for_one` and defers their detail (their surface form
is `strategy one_for_all` / `strategy rest_for_one`, exercised in
`examples/supervision_strategies.march`).

**Two supervision subsystems: do not conflate them.** March has *two* distinct
supervisor implementations with different strategy coverage:

1. The **static** `actor Name do … supervise do strategy … end end` declaration
   form (above) dispatches through the **full three-strategy enum**
   `OneForOne | OneForAll | RestForOne` (`ast.ml:254–257`, dispatched at
   `eval.ml:1756–1762`): all three strategies are implemented.
2. The **dynamic** supervisor (a runtime `dyn_sup_state` with no static
   `actor_def`, created via the `Supervisor.spec`/registry path) stores its
   strategy as a **string** field `ds_strategy`: its own comment pins it as
   `"one_for_one" (only strategy supported now)` (`eval.ml:141`); the dynamic
   path implements **`one_for_one` only**. A crash routed to a dynamic
   supervisor goes through `notify_dyn_supervisor` (`eval.ml:1753`), not the
   static enum dispatch.

The `one_for_one` semantics documented here are the ones both subsystems share;
the three-strategy claim applies **only** to the static declaration form.

**Epoch invalidation across a restart (cross-ref §4.10.6).** A restart is where
the epoch bump of §4.10.6 actually happens. `spawn_child_actor`
(`eval.ml:1505`) inherits the crashed instance's epoch and adds one: the new
child's `ai_epoch = old.ai_epoch + 1` (`eval.ml:1513–1518`). So a `Cap` issued
against the child **before** its crash keeps the pre-restart epoch; after the
restart the live instance's `ai_epoch` differs, so a `send_checked` on that
stale `Cap` hits the `inst.ai_epoch <> cap_epoch` arm (`eval.ml:3147`) and
returns `:error`: the capability is auto-invalidated across the restart with no
explicit `revoke_cap` (§4.10.6's "Restart (epoch staleness)" path). This is
observable on **both backends**: the compiled `send_checked`/epoch-`Cap` plane
is byte-equal to the interpreter (§4.10.6, fixed 2026-07-18), and the
surface way to *hold* a pre-restart child cap (reading the child pid out of
the supervisor state via `get_actor_field` + `pid_of_int`) resolves correctly
compiled (below, fixed 2026-07-08). The epoch-invalidation rule therefore
applies to compiled binaries as much as to the interpreter.

**Restart observation is byte-equal on both backends (fixed 2026-07-08).**
Every surface way to observe a supervised child (the supervisor's spawn-time
child `init`, `get_actor_field`, `pid_of_int`) used to diverge or crash
compiled; all three now agree:

| Observation path | interpreted | compiled |
|---|---|---|
| `spawn(Sup)` runs each child's `init` body (a `println` in `init`) | fires once per child (deterministic) | fires once per child (deterministic) |
| `get_actor_field(sup, "wa")` (read a child pid out of supervisor state) | returns `Some(pid)` | returns `Some(pid)`, a real shape-registry lookup (`march_get_actor_field`, `runtime/march_extras.c`) |
| `pid_of_int(n)` (turn that int back into a `Pid` to `send`/`kill`/`is_alive`) | valid `Pid` | valid `Pid`, a registry lookup by spawn index, with a safe already-dead sentinel for an unknown index (`march_pid_of_int`, `runtime/march_runtime.c`) |
| whole `examples/supervision_strategies.march` compiled | exit 0, restarts observed | exit 0, restarts observed |

Confirmed live: `examples/supervision_strategies.march` runs clean (exit 0)
compiled, exercising all three restart strategies
(`one_for_one`/`one_for_all`/`rest_for_one`) with correctly-resolved child pids.
`march_get_actor_field` resolves a named field through the same runtime shape
registry `march_record_field_dyn` uses (a shape id written into the actor
struct at spawn time), rather than the historical stub; `march_pid_of_int`
looks an index up in the actor table and falls back to a static "already dead"
sentinel actor for an unrecognized index, so every caller's existing
dead-actor early-return path (`march_send`/`march_kill`/`march_is_alive`)
handles it safely instead of dereferencing garbage. Consequently the
supervision restart semantics documented here in prose + `eval.ml` citations
apply to both backends, and the `Actor.call` timeout gap encountered nearby was
separately fixed 2026-07-13 (the compiled runtime now enforces `timeout_ms`,
see `specs/lang/actors.md`).

### 4.11 Session-typed channels: the runtime model (operational)

The typing reference (`core-march-types.md` §2.7) pins **what a `protocol`
declaration checks** and **how `Chan.send`/`recv`/`choose`/`offer`/`close`
advance a channel's static session state** (§2.7.3–§2.7.9). This subsection
pins the **runtime** side: what a channel actually IS at runtime, how the four
core operations reduce in `eval.ml`, and (the point of adding channel
programs to the golden corpus at all) that a program using only the binary
channel plane is **byte-equal interpreted vs compiled**, now that the
concurrent codegen fix (F1/F2, `specs/todos/`) tags payloads symmetrically
at the send site.

**The runtime model in one line:** a channel is a pair of synchronous,
single-threaded FIFO queues; `recv` does **not** suspend: an empty queue is a
fatal error on both backends; there is **no scheduler**, so the programmer
must order every `send` textually before its matching `recv` in program
order.

#### 4.11.1 Values and the crossed-queue representation

A binary channel endpoint is `VChan of chan_endpoint` (`eval.ml:50`); the
multi-party (MPST) analogue is `VMChan of mpst_endpoint` (`:51`). The binary
`chan_endpoint` record (`:63–73`):

```ocaml
and chan_endpoint = {
  ce_id      : int;           (* Globally unique channel id *)
  ce_role    : string;        (* Which side of the protocol this is *)
  ce_proto   : string;        (* Protocol name, for runtime error messages *)
  mutable ce_closed   : bool;
  ce_out_q   : value Queue.t; (* Values this endpoint puts out (other side reads) *)
  ce_in_q    : value Queue.t; (* Values this endpoint receives (other side wrote) *)
}
```

Two endpoints of the same channel share **crossed** queues: endpoint `a`'s
`ce_out_q` IS endpoint `b`'s `ce_in_q`, and vice versa: a `send` on one side
becomes a pending value for a `recv` on the other, mediated purely by two
plain OCaml `Queue.t` values with no locking, no thread, no scheduler
involved. (The MPST `mpst_endpoint`, `:75–88`, generalizes this to N×(N−1)
directed queues, one per ordered role pair, keyed by peer role in a
hashtable; same crossed-queue idea, more of them; see §4.11.5 for why MPST
is documented but not golden-witnessed.)

#### 4.11.2 `Chan.new`: role-sorted endpoint construction

`chan_new proto_name role_a role_b` (`eval.ml:2632`) allocates a fresh
globally-unique channel id, creates the two underlying queues (`q_ab` for
a→b, `q_ba` for b→a), and builds the two endpoint records with `ce_out_q`/
`ce_in_q` crossed as above. The builtin dispatch for surface `Chan.new(Proto)`
(`:5551–5559`) calls `chan_new` with the two roles named `"A"`/`"B"` by
convention (the typechecker has already verified the protocol's real role
names; the runtime only needs *a* connected pair, not their exact labels)
and returns `VTuple [VChan ep_a; VChan ep_b]`. Crucially, the returned pair's
ORDER is the same role-sorted order the typing side already fixed
(`core-march-types.md` §2.7.3's `project_protocol`, which sorts roles and
returns projections in that order), so `let (cc, sc) = Chan.new(Echo)` binds
the roles in a fixed, deterministic order, not spawn-order or declaration-
order.

#### 4.11.3 `Chan.send` / `Chan.recv` / `Chan.close`

- **`chan_send ce v`** (`eval.ml:2645`): errors if `ce.ce_closed`; otherwise
  `Queue.push v ce.ce_out_q` and returns `VChan ce` (the *same* endpoint
  record; the type system's linearity discipline is what prevents reuse in a
  well-typed program; the runtime itself does not re-check linearity, see
  §4.11.6). This is a **pure enqueue**: it does not block, does not look at
  the other side's queue, and returns immediately: `send` is fire-and-forget
  in the exact same async sense as an actor `send` (§4.10.2), just onto a
  different queue shape.
- **`chan_recv ce`** (`eval.ml:2655`): errors if `ce.ce_closed`; if
  `ce.ce_in_q` is empty, **hard error** (`:2660`): `"Chan.recv: channel
  %s#%d has no pending value, did you run the sender first?"`. This is the
  operative fact for §4.11.6/F6: `recv` never suspends or retries, it either
  finds a value immediately (pushed by an earlier `send` on the other
  endpoint, evaluated earlier in program order) or the program crashes.
  Otherwise pops the value and returns `VTuple [v; VChan ce]`, the popped
  payload paired with the same endpoint, now advanced.
- **`chan_close ce`** (`eval.ml:2666`): errors if already closed; otherwise
  sets `ce.ce_closed <- true` and returns `VUnit`. Marks the endpoint dead;
  any further `send`/`recv`/`close` on it is the "already closed" error.

The builtin dispatch table wires these directly: `Chan.send`
(`eval.ml:5563–5565`) is `chan_send`, `Chan.recv` (`:5569–5571`) is
`chan_recv`, `Chan.close` (`:5575–5577`) is `chan_close`; no additional
runtime logic beyond argument-shape matching.

#### 4.11.4 `Chan.choose` / `Chan.offer`: branch selection IS send/recv of an atom

`Chan.choose(ch, :label)` (`eval.ml:5581–5584`) is **literally** `chan_send`
applied to the label value (an `Atom` or `String`); the builtin arm is `[VChan
ce; (VAtom _ as v)] | [VChan ce; (VString _ as v)] -> chan_send ce v`, no
separate "selection" mechanism at all. `Chan.offer(ch)` (`:5588–5589`) is
**literally** `chan_recv`: `[VChan ce] -> chan_recv ce`. So MPST-style
choice/offer over a session type reduces, at runtime, to sending and
receiving an ordinary value over the same crossed FIFO queues §4.11.1
describes: the "protocol branch" abstraction is entirely a typechecker-side
fiction (tracking which `SChoose`/`SOffer` continuation is legal next,
`core-march-types.md` §2.7.8) with **zero** runtime representation of its own.
This is why a `choose`/`offer` program is exactly as byte-equal-compiled
as a plain send/recv program with the same payload types: there is no
extra runtime surface for the compiled backend to get wrong beyond the
ordinary channel payload path (§4.11.5 below).

#### 4.11.5 Interp==compiled property for the binary channel plane (post F1/F2)

**Verified property (this task).** For a program using only the **binary**
channel plane (`Chan.*`, not `MPST.*`) with `Int`/`Bool`/`String` payloads,
correctly interleaved (every `send` textually before its matching `recv`;
§4.11.6/F6), the interpreted and compiled outputs are **byte-equal**.
This was NOT true before the concurrent codegen fix logged as F1/F2 in
`specs/todos/`: `march_chan_send` used to receive its payload as a bare
untagged `i64` while `march_chan_recv`'s result went through the standard
conditional erased-i64 untag (`ashr` iff the low bit is set): an imbalance
that corrupted every **odd** `Int` payload (`43` came back `21`) and flipped
every `Bool` (`true` came back `false`), while even Ints and heap payloads
(String, records) passed by construction (even-aligned pointers are
untouched by the conditional untag). That imbalance is fixed: the send site
now tags the payload the same way the recv site expects, so the round-trip
is symmetric for the full payload-type range a channel can carry. Two golden
programs (§5) witness this directly:

- **`g38_chan_int_echo`**: a plain `Chan.new`/`send`/`recv`/`close`
  round-trip moving an **odd** `Int` (`42` sent, `43` returned), exactly
  the value class F1 used to corrupt. `MATCH` under `verify.sh`.
- **`g39_chan_choose_offer`**: `Chan.choose`/`Chan.offer` branch selection
  over a protocol with **type-distinct** branches (`ok -> Int`, `err ->
  String`, required so the MPST-merge-rule-into-binary-duality pitfall, F4,
  does not spuriously reject the protocol), the chooser picking `:ok` and
  sending an odd Int (`43`) after the label. `MATCH` under `verify.sh`.

**F3 RECHECKED 2026-07-24: MPST send/recv/close runs correctly compiled.**
An earlier version of this document reported that every `MPST.*` program
segfaulted compiled (exit 139) while running correctly interpreted, and
attributed it to the compiled MPST C runtime
(`runtime/march_extras.c:1463+`) not being correctly wired to the lowered
representation. Re-run live for this task: a 3-role and a 4-role MPST
protocol (`Int`/`Bool`/`String` payloads, `MPST.new`/`send`/`recv`/`close`
only) both compile, run, and print output identical to the interpreter,
exit 0 (full transcript in `specs/todos/`); the segfault does not
reproduce. **MPST is still NOT in the golden corpus**, though: the property
above is verified only by this ad hoc transcript, not by a mechanically-
pinned `specs/lang/golden/` witness the way binary channels are (§5); a
golden MPST program is future work, not a claim this re-verification makes.
Separately, **multiparty `choose`/`offer` remain unimplemented**: there is
no `MPST.choose`/`MPST.offer` typing arm at all (§2.7.8 of the typing
reference only defines the binary `Chan.*` six and the multi-party
`new`/`send`/`recv`/`close` four). Calling either name now gets a clear,
explicit compile error (`typecheck.ml:4756–4773`): `` `MPST.choose` is not
a session-channel operation I know, or it was called with the wrong number
of arguments. Binary channels: Chan.new/send/recv/close/choose/offer.
Multi-party: MPST.new/send/recv/close — multi-party `choose`/`offer` are not
implemented yet. ``, rather than the misleading "Unknown module `MPST`"
one might otherwise expect, or a runtime crash.

#### 4.11.6 Two scope boundaries, both logged as findings, neither "fixed" here

Two properties of this runtime are documented as **findings**, not faults
this task resolves: they are real, live-verified, and critical for
anyone writing a channel program, but fixing either is out of scope for a
docs-widening slice:

- **F6: no scheduler, so `recv`-before-`send` deadlocks at runtime, not
  caught statically.** Because `chan_recv` never suspends (§4.11.3), a
  protocol with two roles driven by separate functions called in the
  "wrong" order (the receiver's function invoked before the sender's) TYPE-
  CHECKS fine (session-state advancement is a per-op static check, oblivious
  to call order) but dies at runtime on BOTH backends: interpreted, the
  `"has no pending value"` error above; compiled, `march: Chan.recv on empty
  channel queue (role N)` then abort. This is a fundamental scope boundary:
  **session types here are a linear protocol-conformance checker over a
  same-thread mailbox, not a concurrent session system**: every golden
  witness in this corpus is therefore written with strict send-before-recv
  program order, by construction, not by accident.
- **F7: partial linearity enforcement.** Session-channel "use exactly once"
  is enforced by the same generic linear-`let` tracker every other linear
  value uses, not by session-specific accounting. Two shapes slip through:
  dropping an unclosed `SEnd` channel (never calling `Chan.close` once a
  channel reaches `End`) typechecks and runs cleanly; and reusing a linear
  **parameter** endpoint (rather than a `let`-bound continuation) at a
  protocol shape where the parameter's declared session state coincidentally
  still matches after one op (e.g. two `Chan.send` calls against the same
  parameter `ch : Chan(Client, Send(Int, Send(Int, End)))` rather than
  threading the first call's returned continuation) also typechecks and
  runs cleanly. The "consume each channel exactly once, at the exact
  advancing state" guarantee therefore only actually applies to `let`-bound
  continuations threaded through in the same scope.

Both are logged in `specs/todos/` with live repros; neither blocks a golden
witness (every witness here is written to avoid both shapes on purpose:
every channel is closed, and every continuation is threaded through fresh
`let` bindings rather than re-read from a stale parameter or `let`).

**F8 REMOVED 2026-07-24: there is no undeclared-participant HINT any more.**
A third finding used to be named here so it would not be mistaken for a
golden-corpus hazard: `protocol` participant names not declared as an `actor`
or a `type` produced a typecheck-time HINT to the compiler's stderr, e.g.
bare `Sender`/`Receiver` roles with no corresponding declaration. It was
always diagnostic noise rather than a runtime or golden-corpus issue (the
HINT had no program-runtime representation on either backend, so it could
never appear in either side of `verify.sh`'s interp-stdout vs
compiled-stdout+stderr comparison), and on 2026-07-24 the hint was deleted
entirely: protocol roles are their own namespace, not type or actor names, so
the hint fired on essentially every ordinary protocol, including this
document's own `Echo` example. The emitting code no longer exists (the former
`typecheck.ml:~7057–7066` site now retains only a comment recording the
removal). `g38`/`g39` still declare their roles as nullary types
(`type Client = Client`); that is now stylistic, not a way to silence
anything. Typing-side note: `core-march-types.md` §2.7.1.

### 4.12 Linearity at runtime (operational: there is none)

Linearity (`core-march-types.md` §2.9) is **compile-time-erased**. Neither
backend performs any use-accounting at runtime; a linearity-correct program
behaves identically to the same program with every `linear`/`affine`
annotation deleted. Golden witness: `g41_linear_annotations_erased` (all
three keyword surfaces: `linear` param, `linear let`, `affine`
type-modifier binding, prints `42` / `done`, byte-equal, MATCH).

What each layer actually does (all line numbers drift; re-grep):

- **Interpreter** (`eval.ml`): no tracking. `DAlwaysLinearType` is handled
  identically to `DType` (`eval.ml:~8412`); `chan_send` passes the endpoint
  through with the comment "the type system ensures linearity; here we just
  pass it through" (`:~2686`). The only linear-labeled mechanism is actor
  **Drop-on-crash cleanup**: `ai_linear_values` (value, drop-fn pairs,
  `:~119`), registered by the `own(pid, value)` builtin (`:~3088`) and run in
  reverse acquisition order at actor death (`:~1827`), which is resource
  management, not enforcement.
- **Compiled backend** (TIR): the surface linearity is lowered onto TIR vars
  as `v_lin : Lin | Aff | Unr` (`tir.ml:17`, via `lower_types.ml:58-61`) and
  used ONLY for optimization, never checks: a `send` of a `v_lin = Lin`
  message emits `march_send_linear` (zero-copy move instead of copy,
  `llvm_emit.ml:~1576`), and the implicit `$actor` param is marked `Lin` so
  Perceus elides incrc on field loads (FBIP in-place mutation,
  `lower_actor.ml:~92`). The *type*-level `TLin` wrapper is stripped at both
  lowering entries (`lower_types.ml:51` surface, `:92` typecheck-ty).
- **Consequence**: any program the static tracker fails to reject (the L3/L4
  param-field and F7 session-parameter gaps, `specs/todos/`) runs with NO
  runtime safety net, same posture as the capability system (§2.8's
  runtime-erased `Cap(X)`).

**Finding L7 (FIXED 2026-07-10, was: direct `match` on a local
Newtype-repr construction printed garbage compiled):** g41's first-ever run
caught escape analysis stack-promoting a non-escaping ERASED-repr alloc
(`let c = R(22)`, annotation irrelevant, the plain form was equally broken)
into a boxed stack cell that the match then decoded under the erased
convention (untagging the raw stack address). Erased-repr (Newtype/Niche)
allocs are no longer stack-promotion candidates
(`lib/tir/escape.ml` `alloc_emits_heap_cell`; they emit immediates, so
promotion was also a strict pessimization), and `llvm_emit.ml`'s
`EStackAlloc` arm fails visibly if one does slip through. `g41` now consumes
its affine binding via a DIRECT match (the exact shape that was broken)
as the permanent regression witness. Full writeup in `specs/todos/`
(Linearity section, L7 ✅).

### 4.13 `let?`: Result-propagation (operational)

`let? p = result; body` (typed by `core-march-types.md` §2.10) evaluates
natively in the interpreter: `ELetQ` in `eval.ml` (`:7644`; re-grep), with
no desugaring to `match`. Two rules, and both backends agree down to the byte
(golden `g42`):

```
        result ⇓ Ok(v)      body[p ↦ v] ⇓ w
  (E-LetQ-Ok)  ──────────────────────────────────
                  (let? p = result; body) ⇓ w

        result ⇓ Err(w)
  (E-LetQ-Err)  ─────────────────────────────────────
                  (let? p = result; body) ⇓ Err(w)      -- body NOT evaluated
```

- **(E-LetQ-Ok)**: `result` reduces to `Ok(v)`; `p` is bound to `v` (the bind
  cannot fail; `p` is an irrefutable `simple_pattern`, §2.10.1) and the
  continuation runs.
- **(E-LetQ-Err)**: `result` reduces to `Err(w)`; the whole `let?` returns
  `Err(w)` **verbatim** and the continuation is never evaluated. This is the
  short-circuit: `let?` always propagates the first `Err` upward with the
  same error value. (A non-`Result` scrutinee is impossible in a well-typed
  program, §2.10; the interpreter has a defensive `eval_error` for it.)

Unlike a bare `with … do … end` (which desugars to an `Err`-arm-less `match`
and `Match_failure`-panics on `Err`), `let?` is exhaustive by construction:
the `Err` short-circuit is the rule itself, so `let?` can never crash on an
`Err`. Golden `g42` witnesses both paths: `chain(5)` succeeds through two
steps (`ok 70`), `chain(-1)` fails the first step so the second `let?` never
runs (`err neg`), identical interpreted and compiled.

### 4.14 Data parallelism: the determinism guarantee (operational)

March's data-parallel combinators: `List.pmap`/`pfilter`/`preduce` (list-based,
`stdlib/list.march`) and the RRB-`Vec` `Parallel` module (`pmap`/`pmap_n`/
`preduce`/`preduce_n` plus `psum`/`pcount`/`pany`/`pall`) are **not new core
constructs**. They are ordinary polymorphic stdlib functions built on
`task_spawn`/`task_await_unwrap` (§4.10). Their conformance content is a single
*operational guarantee*: **a data-parallel operation produces exactly the same
result (same values, same order) as its sequential counterpart, and that
result is byte-equal interpreted and compiled**, even though the interpreter
runs the task thunks eagerly and sequentially while the compiled backend runs
them on the real multi-core work-stealing scheduler.

```
  map f xs ⇓ ys
  ─────────────────────────  (E-PMap)   pmap preserves order
  pmap f xs ⇓ ys

  merge associative,  z identity of merge,  fold_left (merge ∘ f) z xs ⇓ w
  ────────────────────────────────────────────────────────────────────────  (E-PReduce)
  preduce z f merge xs ⇓ w
```

- **(E-PMap)**: the gather reads task results in **spawn order** via a
  per-handle `await` (not completion order), so the output vector's order equals
  the input's regardless of how many workers ran or how the scheduler
  interleaved them. `pmap`/`pmap_n` are therefore order-preserving
  *unconditionally*.
- **(E-PReduce)**: `preduce` splits the input into contiguous chunks, reduces
  each chunk, then merges the partials left-to-right. When `merge` is
  **associative** and `z` is its **identity** (the documented contract), the
  result is independent of the chunk boundaries, and the chunk count differs
  between backends (the interpreter's worker count comes from
  `Domain.recommended_domain_count`, the compiled runtime's from the physical
  CPU count), so associativity is exactly what makes the two backends agree.
  `psum`/`pcount` (integer `+`), `pany`/`pall` (`||`/`&&`, no short-circuit) all
  satisfy this and are deterministic.

**The candid exclusion (finding P1).** `Parallel.psum_float` is **not**
backend-portable: IEEE-754 `+.` is not associative, so the differing chunk
counts can reorder the additions and change the last bit. It is intentionally
absent from the golden. The same caveat applies to any `preduce` with a
non-associative `merge` (subtraction, average): the result becomes worker-count-
dependent, hence backend-dependent, and is outside the guarantee. Programs where
`f`/`pred` performs observable **side effects** also fall outside it: the
*returned value* stays deterministic, but under compiled execution the effects
run concurrently on up to N OS threads, so their ordering is not.

Golden `g43_parallel_determinism` witnesses the guarantee: `List.pmap == List.map`
on 199 elements, and `Parallel.psum`/`pcount`/`pany`/`pall`/`preduce` over the
same data, all byte-equal interpreted and compiled, stress-verified 0/15
crashes. It is the first compiled conformance witness for the RRB `Parallel`
module (the suite's `test_compiled_pmap_matches_map` covers only `List.pmap`/
`pfilter`).

### 4.15 Distributed CRDTs: convergence laws, and the single-process boundary (operational)

The distributed/OTP stack (`stdlib/crdt.march`, `vector_clock.march`,
`membership.march`, `global_registry.march`, `merkle.march`,
`consistent_hash.march`, and the RPC/identity layer) splits cleanly into a
**pure, single-process-testable core** and a **live-network shell**. Only the
core is a conformance subject here; the shell is a documented scope boundary.

**Conformance-testable in one process (the CRDT / lattice laws).** These are
pure functions over data structures and run byte-identically on both backends:

```
  merge commutative:   merge a b  =  merge b a
  merge associative:   merge (merge a b) c  =  merge a (merge b c)     -- join-semilattice
  merge idempotent:    merge a a  =  a
  ──────────────────────────────────────────────────────────────────  (CRDT-Converge)
  replicas that have seen the same set of updates hold equal state,
  independent of the order in which updates and merges were applied
```

This covers `GCounter`/`PNCounter`/`LWWRegister`/`ORSet.merge`, `Membership` and
`GlobalRegistry.merge` (incarnation-/vector-clock-ordered CRDT views),
`VectorClock` causality (`happens_before` is the partial order induced by
component-wise `≤`; `compare` classifies Before/After/Concurrent/Equal),
`Merkle.root_hash`/`diff`, `ConsistentHash` ring placement, and `RingBuf`
FIFO/overwrite invariants, plus the wire codecs (`NetFrame`, `NodeIdentity`,
`GlobalPid`, `Handshake`, `RemoteCall`, `SwimDriver`; for each, `decode ∘ encode = id`),
`ClusterAuth`'s HMAC challenge/response, and `RemoteCall.verify`'s content-
addressed admission (TypeMismatch/VersionSkew/NoTarget). Golden
`g44_crdt_convergence` witnesses the GCounter/PNCounter/ORSet merge laws and
VectorClock causality on causally-ordered clocks.

**Prose-only scope boundary (needs a live multi-node harness).** The following
are **not** single-process conformance subjects and are exercised only by the
native TCP-loopback tests under `test/native/` (two logical nodes over
`127.0.0.1`, golden `.expected` diffs), never by the eval harness or the oracle:
the net-kernel handshake (`NetKernel.handshake`, `ClusterConn`), synchronous RPC
transport (`NodeCall.call`/`serve_loop`), SWIM gossip *dispatch* to peer fds
(`SwimDriver.dispatch*`), the compiler-emitted `__rpc_stub` → C-registry
dispatch (a no-op under the interpreter, `eval.ml` `remote_check`→0), and
cross-node monitor firing (`march_monitor_registry.c` writes to fds). True
multi-*machine* semantics (netsplit, node restart/incarnation, cross-host clock
skew) remain prose-only.

**Finding C1: FIXED (2026-07-11).** `VectorClock.compare`, and any code
that reduces over a map's own keys and looks each one up in that map, after the map was
built by the read-then-update idiom `Map.insert(m, k, f(Map.get_or(m, k, …)), cmp)`,
used to **crash compiled** (use-after-free of a String key in `march_hash_string`,
SIGSEGV or hang) while running correctly interpreted. Root cause: `lib/tir/
llvm_case.ml`'s `strip_scrut_decrc` recognized a match arm's scrutinee-dying
`EDecRC` only as the LITERAL head of the branch body, but Perceus's
`add_cross_decrcs` can prepend OTHER cross-branch-dead variables' `EDecRC`s in
front of it (e.g. `Map.node_insert`'s `HLeaf` arm emits `dec_rc eq; dec_rc node;
…`, an unrelated comparator param dec'd before the scrutinee). When that
literal-head match failed, the shared-path field-protection (an `IncRC` on
each extracted heap field when the scrutinee's refcount is >1, keeping a
field's count correct when the scrutinee stays live) never fired, silently
under-counting an extracted String key's refcount whenever the map argument
was shared, which the read-then-update idiom on a function parameter used at
both a borrowed (`get_or`) and owned (`insert`) position routinely produces.
Fixed by generalizing `strip_scrut_decrc` to scan through a leading run of
bare `dec_rc` ops for the scrutinee's own, preserving the others in place.
`g44` now includes the disjoint-key `VectorClock.compare`/`.concurrent` case
that used to be excluded; the full CRDT/lattice core is unconditionally
byte-equal and crash-free (stress-verified 0/20), not scoped around a bug.

### 4.16 Perceus reference counting: the compiled backend's own operational discipline (widening slice 11, 2026-07-11)

**Why this section looks different from every other one in §4.** Every prior
slice states its rules as big-step reductions on the *core AST*, with
`eval.ml` as the reference implementation and a golden program's job to prove
the compiled backend agrees with it. Perceus RC insertion has no such anchor:
`eval.ml` uses OCaml's own GC and performs **no explicit refcounting at
all**: the interpreter offers no baseline to compare the compiled
backend's RC behavior against. This section therefore states RC discipline
as invariants over **TIR** (the compiled backend's own post-Perceus
intermediate form), verified two ways that together substitute for the
interp-vs-compiled diff every other section relies on: (1) exact byte-level
pinning of the emitted TIR against a committed snapshot
(`test/snapshots/perceus/*.expected`, `test/test_snapshots.ml`), which
catches any drift in *where* `dup`/`drop`/`reuse` land; and (2) running the
compiled binary under `MARCH_SANITIZE=1` (ASan+UBSan), which catches
whether that placement is actually *correct* (no leak, no use-after-free);
something a snapshot by itself cannot prove. Full governing detail lives in
`specs/perceus-invariants.md`; this section states the two invariants that
already have both forms of pinning, in the same hypothesis/conclusion style as
the rest of §4.

**RC applicability (`lib/tir/rc_types.ml`).** Two predicates over `Tir.ty`,
`needs_rc` (must Perceus emit `EIncRC`/`EDecRC` for this type?) and
`borrow_eligible` (may a parameter of this type be borrow-inferred?),
intentionally **disagree** on two constructor families:

```
  needs_rc(TFn _) = true       borrow_eligible(TFn _) = false     -- closures: Perceus-only
  needs_rc(TTuple/TRecord) = false   borrow_eligible(TTuple/TRecord) = true  -- fields reconciled individually
```

Closures are always heap-allocated post-defun (`llvm_ty (TFn _) = "ptr"`), so
Perceus must track their lifetime, but letting the borrow fixpoint
reclassify a closure parameter as borrowed would leave capture-site
accounting and call-site accounting disagreeing about who owns the closure
and its captured free variables. Tuples/records get the opposite treatment:
Perceus never emits an *aggregate*-level `dup`/`drop` for a tuple or record
cell (ownership is reconciled per-field via `borrowed_field_vars`), but the
aggregate parameter itself must still be borrow-*eligible* so the fixpoint
can infer a function that only reads fields as fully borrowed.

**The owned/borrowed call-boundary contract and the dual-position invariant
(B1).** `lib/tir/borrow.ml`'s fixpoint classifies each function parameter
**owned** or **borrowed** (borrowed iff every use is read-only: matched,
field-accessed, or passed to another borrowed position; never stored,
returned, or passed to an owning position of an unknown callee). The
contract at a call boundary:

```
        param p classified borrowed by Borrow's fixpoint
  (E-Call-Borrowed-Callee)  ─────────────────────────────────────
        callee emits NO `EDecRC` for p at its last use

        arg a passed at p (borrowed), a still live after the call
  (E-Call-Borrowed-Caller-Live)  ─────────────────────────────────
        caller emits NO `EIncRC` for a

        arg a passed at p (borrowed), a is the caller's last use of a
  (E-Call-Borrowed-Caller-Dead)  ─────────────────────────────────
        caller emits `EDecRC(a)` AFTER the call
        (the callee will never dec it — someone still must)
```

The dual-position invariant closes the one case these three rules by themselves get
wrong: **a variable passed at BOTH an owned and a borrowed position of the
same call, dead afterward, must be dup'd exactly once.**

```
        call C(..., a:owned, ..., a:borrowed, ...);  a dead after C
  (E-Call-Dual-Position)  ─────────────────────────────────────────
        exactly one `EIncRC(a)` emitted before C, one `EDecRC(a)` after
```

Naively, the owned-position accounting (`find_inc_vars`) and the borrowed-
position accounting (`post_dec_vars`) are computed independently: the
owned side sees only one occurrence of `a` and emits zero dups (it thinks
the single owned reference transfers), while the borrowed side
independently schedules its own post-call dec. Both fire: net two
consumptions against one owned reference: RC underflow, a use-after-free
the moment the callee returns a value built from `a`. The fix
(`lib/tir/perceus.ml`'s `EApp` case, mirrored for `ECallPtr`-extern)
partitions the post-dec set into `dual_pos_vars` (also owned-positioned in
the *same* call) and emits one balancing `EIncRC` for exactly those,
keeping the value alive across the whole call regardless of which
occurrence the callee consumes first.

**Golden `g45_dual_position_borrow`** witnesses `both(a: owned, b:
borrowed, n: owned)` called as `both(s, s, 1)`, the exact shape that
underflowed before the fix. It is verified three ways: interp==compiled
byte-equal output (this corpus's usual check); the post-Perceus TIR
matches `test/snapshots/perceus/mixed_owned_borrowed_args.expected` exactly
(one `inc_rc s` before the call, one `dec_rc` after); and the compiled
binary runs clean under `MARCH_SANITIZE=1`: exit 0, no ASan/UBSan report
(live-verified 2026-07-11; not yet a standing CI gate; no broad sanitizer
sweep exists over the corpus, a documented gap, not built in this
docs-only slice).

**What this section intentionally excludes.** FBIP/reuse (`lib/tir/
perceus_fbip.ml`) needs an "reuse preserves semantics" theorem to state as a
real rule, not just an arity-compatibility check; excluded pending that
metatheory. Atomic RC mode-selection (`specs/atomic-rc-design.md`) is an
undesigned draft; no code implements it today. Escape-analysis stack
promotion (`lib/tir/escape.ml`) is an orthogonal optimization with no
correctness content of its own to formalize (its one correctness
obligation, never stack-promote an erased-repr alloc, was already the L7
finding fixed in slice 7, §4.12).

## 5. Golden conformance corpus

Forty-six programs in `specs/lang/golden/`, each exercising a slice of the
fragment, each verified to produce **identical output interpreted and
compiled** (`march f.march` vs `march --compile f.march -o b && b`). This is
the executable anchor for §4. `g01`–`g08` are the walking-skeleton's original
corpus (`+`, `==`, lambdas, ADTs, match); `g09`–`g13` are Task 1's addition,
covering the remaining literals and the full primitive δ-rule table; `g14`–`g16`
are Task 2's addition, covering tuple construction, destructuring, and nesting;
`g17`–`g20` are Task 3's addition, covering record literals, field access, and
functional update on the currently-working (non-divergent) subset; `g21`–`g23`
are Task 4's addition, covering nullary-atom matching, payload-atom matching
with binding, and an atom-returning function used in both `==` and `match`;
`g24`–`g27` are Task 5's addition, covering the full pattern language's
matching + guard + exhaustiveness slice: a deeply nested pattern (con → tuple
→ con), a guarded branch that FALLS THROUGH to a later branch, an intentional
`_` catch-all after specific patterns, and a guard reading its branch's own
pattern-bound variables (the reachable substitute for the unparseable `PatAs`
as-pattern; see the `PatAs` note in §4.3); `g28`–`g30` are Task 6's addition,
covering local recursive functions (`ELetFn`, §4.2's E-LetFn / the env_ref
recursive-knot): a self-referential `fn go` computing factorial, a local
recursive fn CLOSING OVER an outer `let` binding (lexical capture + recursion
together), and a recursion with a result bound by a following `let` and used
by the rest of the block (proving the `ELetFn` binding is visible to the block
continuation, not only inside its own body); `g31`–`g32` are Task 7's addition,
covering the boolean-chain conditional (`ECond`, §4.2's E-Cond-Sel /
E-Cond-Fail; the scrutinee-less `match do c -> b … end`): a chain where a
MIDDLE arm is the first `VBool true` and is selected (earlier false arms
skipped, later arms including the terminal catch-all never consulted), and the
all-false path routed through a terminal `_ ->`/`true ->` catch-all arm (the
non-crashing witness of "the last arm is selected exactly when every earlier
condition is false"; the truly-all-false chain that would raise
`non-exhaustive match do` at runtime is intentionally NOT a golden program, since
a nonzero interpreter exit is an automatic `INTERP FAIL` under `verify.sh`, the
same harness limitation §4.4.1 / §4.3 note for the crashing strict-`&&` and
`Match_failure` witnesses); `g35`–`g36` are the actor-operational addition,
covering the interleaving-free actor slice of §4.10 (spawn + async `send` +
`run_until_idle` draining a single actor to a fixed point in `g35`, and a
`receive()`-mediated follow-up on the non-blocking pop path in `g36`): the two
witnesses named in §4.10.5's determinism property (interp==compiled
byte-equal for actor programs where output does not depend on scheduler
interleaving), observing state only through handler `println`s so neither
SIGSEGVs compiled; `g37` is the actor-lifecycle addition, covering the
`spawn → kill → is_alive` liveness slice of §4.10.6 (a pure registry-bool
observation, the only lifecycle plane byte-equal compiled; the capability /
dead-`send` plane diverges and is documented as a finding in §4.10.6, not as a
golden program). `g38`–`g42` are the session-channel (§4.11), actor-foreign-drop
(§4.10), linearity-erasure (§4.12), and `let?` (§4.13) additions, each
documented in its own section above. `g43` is the parallelism addition (§4.14),
witnessing the data-parallel determinism guarantee: `List.pmap == List.map`
plus the RRB `Parallel` integer/bool reductions, the first compiled witness for
that module. `g44` is the distributed-CRDT addition (§4.15), witnessing the
convergence laws of the single-process-testable CRDT core (GCounter/PNCounter/
ORSet merge, VectorClock causality including the disjoint-key `compare`/
`.concurrent` case that used to crash compiled (finding C1, fixed
2026-07-11). `g45` is the Perceus RC
addition (§4.16), witnessing the dual-position dup/drop invariant (B1),
verified interp==compiled, against a committed TIR snapshot, AND clean under
`MARCH_SANITIZE=1`. `g46` is the refinement-types addition
(`core-march-types.md` §2.14), witnessing that a program with refinement
obligations all discharged by proof at `--check` time runs
byte-identically, since neither backend inserts any runtime predicate check:

| Program | Fragment feature | Output (interp = compiled) |
|---|---|---|
| `g01_let_arith.march` | block `let`, `Int`, `+` (δ-Add, E-Blk-Let) | `5` |
| `g02_lambda_app.march` | `ELam` + `EApp` (E-Lam, E-App-Clo) | `11` |
| `g03_bool_eq.march` | `Bool`, `==` (δ-EqI) | `true` / `false` |
| `g04_adt_match.march` | 2-ctor ADT, `match`, `PatCon` no payload | `red` / `green` |
| `g05_adt_payload.march` | ADT payload, `PatCon C [x]` binding | `0` / `107` |
| `g06_hof.march` | higher-order function (closure passed as arg) | `7` |
| `g07_match_lit.march` | `PatLit` + `PatWild`, first-match-wins | `zero`/`one`/`many` |
| `g08_nested_let_shadow.march` | nested block + `let` shadowing (assoc-list prepend) | `16` |
| `g09_literals.march` | `LitFloat`/`VFloat`, `LitString`/`VString`, `LitAtom`/`VAtom` + atom `==` (δ-Eq-*, match(PatLit …)) | `3.5` / `hello, march` / `true` / `false` |
| `g10_arithmetic.march` | `-`,`*`,`/`,`%` on `Int`, truncating-toward-zero `/`/`%` on negatives, unary `negate`, `-`/`*` on `Float` (δ-Sub-I/F, δ-Mul-I/F, δ-Div-I, δ-Mod-I, δ-Neg-I) | `5`/`42`/`3`/`2`/`-3`/`-1`/`-5`/`1.5`/`7.5` |
| `g11_comparison.march` | `!=`,`<`,`<=`,`>`,`>=` on `Int`, plus one `Float` and one `String` case (δ-Neq/Lt/Le/Gt/Ge-*) | `true`/`false` × 12 |
| `g12_bool_ops.march` | `&&`,`\|\|`,`!`/`not`, `++` (δ-And, δ-Or, δ-Not, δ-Concat) | `true`/`false` × 6, `ab` |
| `g13_strict_bool.march` | `&&`/`\|\|` **strictness** witness (§4.4.1): a `println` inside the operand a short-circuiting evaluator would skip fires anyway | `or-rhs-evaluated`/`and-rhs-evaluated`/`true`/`false` |
| `g14_tuple_let.march` | `ETuple` construction, `PatTuple` destructuring in a block `let` (E-Tuple, match(PatTuple, VTuple)) | `7` |
| `g15_tuple_match.march` | `PatTuple` destructuring as a `match` branch pattern, alongside a literal-tuple `PatTuple [PatLit 0; PatLit 0]` branch (first-match-wins over `select`) | `origin` / `3,5` |
| `g16_tuple_nested.march` | nested `ETuple` construction (tuple-of-tuples) destructured by a nested `PatTuple` **in a `match`** (componentwise `match_list` recursion) | `10` |
| `g17_record_literal_field.march` | `ERecord` construction + `EField` access, plus a `println`-traced witness that record-field values evaluate **left-to-right** in source order (E-Record, E-Field) | `eval-x`/`eval-y`/`1`/`2` |
| `g18_record_update.march` | `ERecordUpdate` on an EXISTING field: the base record is unaffected (functional/persistent update) while the result reflects the new value (E-Update) | `1`/`2`/`100`/`2` |
| `g19_record_update_multi_field.march` | `ERecordUpdate` naming MULTIPLE existing fields in one update expression, with a field left untouched, passed through a function that reads via `EField` (E-Update, E-Field) | `12`/`93` |
| `g20_record_nested.march` | a record VALUE nested inside another record's field, accessed/updated through chained `EField`/`ERecordUpdate` (`outer.inner.a`, `{ outer with inner: {...} }`) | `12`/`39` |
| `g21_atom_match.march` | nullary `EAtom`/`VAtom` matched against a nullary `PatAtom` in a `match` (E-Atom-0, match(PatAtom, VAtom)) | `matched ok` |
| `g22_atom_payload_match.march` | payload `EAtom`/`VCon` matched against a payload `PatAtom`, binding the payload (E-Atom-N, match(PatAtom, VCon)) | `error: disk full` |
| `g23_atom_returning_fn.march` | a function returning `:zero`/`:nonzero`, its result compared with atom `==` and separately dispatched over in a `match` | `true`/`was nonzero` |
| `g24_nested_con_tuple.march` | deeply nested pattern: `PatCon (Wrap) [PatTuple [PatVar; PatCon (Som/Non)]]`, matched componentwise via `match_list` recursion at three depths (con → tuple → con → var) | `7` / `9` |
| `g25_guard_fallthrough.march` | a `PatVar` branch with a guard `when n > 10` that is FALSE for `n = 5`, so it falls through (`eval.ml:7340`) to a later branch that matches, the guard-fall-through witness | `big`/`small`/`nonpositive` |
| `g26_catchall.march` | specific `PatCon` branches (`Red`/`Green`) then an intentional `PatWild` (`_`) catch-all, which selects for every other value (`Blue`, `Other(7)`) and keeps the `match` total | `1`/`2`/`0`/`0` |
| `g27_guard_binding.march` | a guard `when a == b` reading variables bound by its OWN branch pattern `P(a, b)` (guard evaluated in the pattern-extended env, `eval.ml:7327,7332`); false for `P(3, 10)` ⇒ falls through; the reachable substitute for the unparseable as-pattern | `0`/`7` |
| `g28_letfn_factorial.march` | a local self-referential `fn go(n)` computing factorial recursively: `go` calls itself via the env_ref recursive knot (E-LetFn, `eval.ml:6875–6884`) | `120`/`1` |
| `g29_letfn_capture.march` | a local recursive `fn go` that CLOSES OVER an outer `let` binding (`step`) while recursing, proving lexical capture + recursion together (the re-read env `!env_ref` contains both the outer `let` and `go` itself, `eval.ml:6880–6883`) | `8` |
| `g30_letfn_sum_result.march` | a recursive `fn go` (sum-to-n) with its RESULT bound by a following `let` and used by the rest of the block, proving the `ELetFn` binding is visible to the block continuation (`eval.ml:6884`), like `let` | `55`/`110` |
| `g31_cond_middle_arm.march` | `ECond` boolean chain where the FIRST condition is false and the SECOND (middle) is the first `VBool true`, so the MIDDLE arm is selected: top-to-bottom, first-true-wins, earlier false arms skipped and later arms (incl. the `true` catch-all) never consulted (E-Cond-Sel, `eval.ml:7097–7106`) | `A`/`B`/`C`/`F` |
| `g32_cond_all_false_catchall.march` | `ECond` where every SPECIFIC condition (`n > 0`, `n < 0`) is false for `n = 0`, so control reaches the terminal `_ ->` catch-all: the non-crashing witness of the all-false path (a truly all-false chain raises at runtime, E-Cond-Fail `eval.ml:7099`; `_ ->` is parser sugar for a `true ->` arm, `parser.mly:1295–1296`, keeping the chain total) | `positive`/`negative`/`zero` |
| `g33_float_show.march` | whole-number `Float` **display** via the `float_to_string` observation primitive, added after the concurrent `float_to_string` backend-unification fix (`0a2d3f53`) that the golden corpus's Task-1 float program had surfaced. Pins only the display format (four backends agree a whole-number `Float` prints OCaml-style `1.`, matching the `eval.ml` `string_of_float` reference); it does NOT lift the float deferral of §0/§6: float arithmetic and ordering remain deferred | `1.`/`42.`/`100.`/`0.`/`-3.`/`1.5` |
| `g34_nested_tuple_let.march` | nested `PatTuple` destructured in a block `let` (`let ((a,b),(c,d)) = …`), componentwise `match_list` recursion under E-Blk-Let. Added after the concurrent fix (`3f719a8e`) to `lib/tir/lower.ml`'s block-`let` nested-pattern lowering that the golden corpus's Task-2 tuple work had surfaced (it emitted invalid LLVM before); the `match`-form equivalent (g16) always compiled | `10` |
| `g35_actor_spawn_send.march` | operational actor slice (§4.10): `spawn` a single `Counter` actor (`ESpawn` → `actor_inst` in `actor_registry`, returns `VPid`), three async `send(c, Inc(n))` (FIFO mailbox enqueue, non-blocking) each returning the new `{count:…}` state, a `Report()` handler that `println`s the accumulated count, drained by one `run_until_idle()` (scheduler-drain to fixed point): the interleaving-free determinism witness of §4.10.5 | `count=8` / `done` |
| `g36_actor_receive.march` | operational actor slice (§4.10): an `Inbox` actor, its `on Start()` handler calls `receive()` ONCE to pop the already-queued `Follow(99)` (sent immediately after `Start()`, so present before dispatch: the non-blocking pop-or-`BlockedOnReceive` path, `eval.ml:3076`) and `println`s its payload; honors the once-per-handler `receive()` limitation (§4.10.3) | `got=99` / `done` |
| `g37_actor_lifecycle.march` | actor lifecycle slice (§4.10.6): `spawn` a `Counter` (`ai_alive = true`) so `is_alive` returns `true`, then `kill` (`crash_actor` sets `ai_alive <- false`, `eval.ml:2961/1766/1772`) so `is_alive` returns `false`, observed via the `Bool` `is_alive` returns (`eval.ml:2964`, a registry lookup SAFE compiled), printed via a `Bool→String` helper. The one lifecycle observation byte-equal compiled; the cap / dead-`send` plane diverges (§4.10.6 finding) and is NOT a golden program | `alive=true` / `alive=false` |
| `g38_chan_int_echo.march` | session-typed channel runtime slice (§4.11): binary `Chan.new`/`send`/`recv`/`close` round-trip (`chan_new`/`chan_send`/`chan_recv`/`chan_close`, `eval.ml:2632/2645/2655/2666`) moving an **odd** `Int` payload (`42` sent, `43` returned), exactly the payload class the concurrent F1/F2 codegen fix (payload tagging at the send site) made byte-equal compiled; every `send` precedes its matching `recv` in program order (§4.11.6/F6) | `43` |
| `g39_chan_choose_offer.march` | session-typed channel runtime slice (§4.11): `Chan.choose`/`Chan.offer` branch selection (`eval.ml:5581/5588`; literally `chan_send`/`chan_recv` of the label atom) over a protocol with TYPE-DISTINCT branches (`ok -> Int`, `err -> String`, avoiding the F4 merge-rule-into-binary-duality pitfall); the chooser picks `:ok` and sends an odd `Int` (`43`) after the label | `:ok` / `43` |

**Result: 46 / 46 matched, 0 divergences in the committed corpus** (the table
above enumerates `g01`–`g39`; `g40`–`g46` are documented in their respective §4
sections (or, for `g46`, `core-march-types.md` §2.14).
These print via `println` /
`int_to_string` / `float_to_string` / `bool_to_string`, *observation
primitives* used to make the result observable; they are outside the pure
reduction fragment and are treated here only as opaque output functions, not
specified by §4.)

**Two guardrails intentionally followed while drafting `g17`–`g20`, both
confirmed by hand, not assumed:** (1) no golden program prints a whole
`VRecord` via `to_string`/`println`/`hash`; confirmed by hand that
`to_string({x: 1, y: 2})` prints `{ x: 1, y: 2 }` interpreted but `#<tag:0>`
compiled (the same `to_string`-on-container class already in
`specs/todos/`'s P1 and `test/test_oracle.ml`'s `known_divergence` list),
and that `hash({x: 1, y: 2})` differs across backends entirely by design
(`specs/todos/`, "Compiled and interpreted `hash()` use different,
backend-specific algorithms ... for RECORD types"), every golden program
here prints only extracted `Int` FIELD VALUES (via `int_to_string`), never a
record value itself. (2) no golden program generates the missing-field
`ERecordUpdate` shape (the divergence adjudicated in §4.2.1); all four
programs update only fields already present in the base's shape.

**A real divergence found and routed around, not hidden:** while drafting
`g10`, `float_to_string` on a *whole-number* `Float` (e.g. `1.0`) printed
`1.` interpreted (OCaml's `string_of_float`, `eval.ml:2891`) but `1` compiled
(the C runtime's `march_float_to_string` uses `snprintf("%g", f)`,
`runtime/march_runtime.c:349`–`353`, which drops a bare `.0`). This is a
real, pre-existing bug in the *compiled* `float_to_string` builtin, outside
this task's scope (§0's fragment excludes "floats beyond their appearance in
the value grammar") and outside the δ-rules being added here (`float_to_string`
is an observation primitive, not a core primitive), so `g10`'s Float
arithmetic (`1.75 - 0.25`, `2.5 * 3.0`) was chosen to land on non-whole
results (`1.5`, `7.5`) where both formatters agree, rather than silently
special-casing or hiding the bug. It is flagged here and via a background
task for separate triage into a `known_divergence` entry once that mechanism
exists.

**A second, new real divergence found and routed around, not hidden:** while
drafting `g16`, a **nested** `PatTuple` (a tuple pattern containing another
tuple pattern, e.g. `let ((a, b), (c, d)) = ((1, 2), (3, 4))`) destructured via
a block-level `ELet` evaluates correctly interpreted (`10`) but **fails to
compile**: `clang` rejects the emitted IR with `use of undefined value '@a'`
(the LLVM backend's `let`-pattern lowering appears to treat a nested tuple
sub-binding's name as an undefined global/function reference rather than a
local variable, a compiled-backend codegen bug, not an interpreter bug). A
*flat* (non-nested) `PatTuple` in a `let` compiles and runs correctly
(confirmed: `let (a, b) = t` compiles, links, and matches interpreted output;
this is exactly `g14`), and a *nested* `PatTuple` used as a **`match`** branch
pattern (rather than a block `let`) also compiles and runs correctly
(confirmed; this is `g16` as committed). So the bug's precise trigger is
`nested PatTuple` × `ELet` specifically, not `PatTuple` or `nesting` or `ELet`
in isolation. This is outside this task's scope (documenting the interpreter
faithfully, not fixing the compiler) and is a **new** divergence, not the
already-logged whole-tuple-`Show` bug (`specs/todos/`, "Tuples have no `Show`
impl"); `g16` was rewritten to destructure the nested tuple in a `match`
instead of a `let` specifically to route around it while still exercising
nested tuple construction and componentwise matching. Flagged here for
separate triage; not logged as a `specs/todos/` entry by this task (spec-only
scope) but should be by a follow-up.

**A third divergence, this one ADJUDICATED and CONVERGED by this task, not
just routed around:** `{ base with f: v }` where `f` is absent from
`base`'s actual (runtime) shape used to diverge: the interpreter silently
fabricated the field, the compiled backend panicked (§4.2.1 has the full
adjudication). This shape is **intentionally excluded from the golden
corpus**: per §0's fragment scope and this task's brief, a golden entry must
be a `MATCH` on the SAME observable output, but this divergence's *resolved*
form is "both sides now reject the program with a nonzero exit": the
committed `verify.sh` harness (like the `@oracle` sweep) classifies any
nonzero interpreter exit as an automatic `INTERP FAIL`, so a program that is
supposed to error on both sides can never register as a golden `MATCH`
regardless of backend agreement (the same harness limitation §4.4.1 notes
for the strict-`&&`/`||` crashing witness). Instead, the convergence is
pinned by a dedicated unit test,
`test/test_properties.ml`'s
`test_record_update_missing_field_on_erased_base_converged`, which checks
BOTH backends now exit nonzero (non-signal) with a "no field" message for
`{ record_from_list([("a", 1)]) with z: 99 }`. Also note that this
divergence was **only reachable through an erased base**:
`record_from_list`/`record_put` results, with a static type that is an
unconstrained type variable (§4.2.1), because a statically-typed record
literal base makes an unknown-field update a **typecheck-time** error on
both backends (`typecheck.ml:3869`–`3875`) before either backend's runtime
`ERecordUpdate` path can execute; none of `g17`–`g20` needed to route
around this, since none of them update through an erased base.

**A known, already-logged divergence encountered again while drafting `g22`,
reached through a second path, routed around, not hidden.** *(**FIXED
2026-07-08, commit `76d4001b` "fix(codegen): make Atom Showable so compiled
println(:atom) links", verified live in this worktree: `println(:ok)` now
compiles and prints `:ok` on both backends. The paragraph below is kept as
historical record of why `g22` was written the way it was; it no longer
describes current compiler behavior.)* `println` on a bare atom value (e.g.
`println(:ok)`) was a known, logged compiler bug: it interpreted fine (`VAtom`
prints as `:ok`, exit 0) but failed to **compile**: the linker rejected the
emitted object with `Undefined symbols … "_show" … _println$Atom`, i.e.
`Atom` had no compiled `_show` implementation (this bug was tracked as chip
`task_6bee4d07`, explicitly out of this task's scope per its brief's
guardrail, at the time this section was written). Confirmed by hand before
drafting `g22`: `println(:ok)` printed `:ok` interpreted (exit 0) but failed
to link compiled with exactly that `_show`/`Atom` error. The FIRST
draft of `g22` did not print a bare atom directly, but hit the *same* bug via
a second, less obvious path: `match result do :error(msg) -> println(msg) …
end` — printing `msg`, a `String` value bound out of a payload atom's
`PatAtom` match, **also** failed to link with the identical `_show`/`Atom`
error. The root cause traces back to the typechecker, not the pattern-match
mechanics: `EAtom`'s inferred type is unconditionally `t_atom` regardless of
payload (`typecheck.ml:4045`–`4047`, `ignore (infer_expr env a)` on each
argument; the argument's own inferred type is discarded, only used for its
unification side effects), and `PatAtom`'s inferred pattern type mirrors this
(`typecheck.ml:2661`–`2664`: the OVERALL pattern type is `t_atom`, while each
sub-pattern (e.g. `msg`) gets its own type from a fresh, otherwise
unconstrained `infer_pattern` call). No constraint unifies `msg`'s type to a
concrete `String`, so it stays an erased type variable at the print site;
the same "erased base" situation §4.2.1 already documents for
`record_from_list`'s return type, and `println` on an erased-type value
falls through to the generic/dynamic show path, which needs a per-type
`_show`, and `Atom`'s is the missing one. This is **the same logged bug**
reached by a second route (an atom payload's erased binding type), not a new
divergence: `g22` was rewritten to route the payload through `describe(msg) =
"error: " ++ msg` first — `++`'s `VString`-restricted δ-rule (δ-Concat, §4.4)
forces `msg`'s type to unify concretely with `String`, so the `println` call
prints a real `VString` rather than an erased-type value, sidestepping the
bug while still exercising the intended semantics (atom construction with a
payload, `PatAtom` matching with binding) end to end.

Run the check: `dune build bin/main.exe && specs/lang/golden/verify.sh`
(the committed harness diffs both outputs per program and exits nonzero on any
mismatch). These programs are exactly the shape the `@oracle` conformance sweep
(`test/test_oracle.ml`) already runs, so folding `specs/lang/golden/` into that
sweep's corpus, so the anchor runs in CI, not just on demand, is the natural
next wiring (§6).

## 6. What Phase-1 validated, and the Phase-2/3 queue

**Phase-1 core: COMPLETE.** The seven widening slices (Tasks 1–7) plus this
consolidation (Task 8) cover every core `Ast.expr`/`pattern`/`literal`
constructor the interpreter runs and the desugarer leaves in the core
(cross-checked against `ast.ml:32–110`), minus the explicitly-deferred set
below. The record `ERecordUpdate`-missing-field divergence was adjudicated and
converged (§4.2.1). The golden corpus is 32/32 MATCH, 0 divergences (§5).

**Validated (the point of the exercise, now proven across the whole core):**

- The "core = desugared AST, `eval.ml` = reference" decision remains in force and is
  grounded in the real pipeline (§1).
- The four layers cohere: the grammar (§2), the desugaring map (§3), and the
  operational rules (§4) all describe one object, and the golden corpus (§5)
  agrees 34/34 across both independently-written backends.
- The doc format (grammar table, desugaring table, arm-cited big-step rules,
  golden table) proved a workable template, replicated cleanly across all
  seven slices and assembled here into one reference.

**Deferred: the Phase-2/3 queue (each group becomes a widening slice like the
Phase-1 tasks did):**

- strings as first-class data (beyond their appearance in the value grammar);
- `to_string`/`show` and the interface-dispatch mechanism: **LANDED
  (§4.4.2–§4.4.4, 2026-07-06; §4.4.2/§4.4.3 UPDATED 2026-07-22).** §4.4.2
  documents the runtime METHOD DISPATCH mechanism: the four-name `impl_tbl`
  type-directed lookup for `Show`/`Eq`/`Ord`/`Hash`, and, as of the
  2026-07-22 correction, a SECOND type-directed table (`iface_method_tbl`)
  every general user-defined interface now dispatches through by its first
  argument's runtime type, replacing the plain lexical `env`-binding path
  this reference originally described. §4.4.3 documents the impl-coherence
  rule: overlapping impls of the SAME `(iface, type)`, including
  generic-vs-specific and derive-vs-manual overlap, are REJECTED at
  typecheck by `register_impl_shape` (landed 2026-07-17, `specs/todos/`),
  closing what this reference originally logged as an open,
  intentionally-left-unfixed cross-backend selection divergence. §4.4.4
  documents `derive`/`satisfy`'s operational consequence: a generated impl
  runs through the identical dispatch rules as a hand-written one, plus
  `Json`'s `JsonTo`/`JsonFrom` pseudo-interface special case
  (`core-march-types.md` §2.3/§2.4 cover the typing/desugar side of all of
  this). The known container-`to_string`/`hash` divergences §5 routes around
  are UNCHANGED by any of this: those are bugs in the fallback arms §4.4.2
  explicitly does not re-litigate, not in the dispatch mechanism (the
  atom-`_show` divergence §5 also routes around WAS separately fixed,
  2026-07-08, commit `76d4001b`; see the §5 g22 note)
  §4.4.2 newly specifies;
- effects and IO ordering;
- actors;
- refinements;
- capabilities;
- the Perceus RC discipline (its own Level-3 track);
- session types: **LANDED (§4.11, 2026-07-06).** §4.11 documents the
  channel-runtime operational model: the crossed-FIFO-queue representation
  (`VChan`/`chan_endpoint`), `Chan.new`/`send`/`recv`/`close`,
  `Chan.choose`/`offer` as literal send/recv of a label atom, the
  interp==compiled property for the binary channel plane now that the
  concurrent F1/F2 codegen fix lands (witnessed by `g38`/`g39`), and the
  no-scheduler-deadlock (F6) and partial-linearity (F7 residual) findings.
  MPST's compiled-segfault finding (F3) was RECHECKED 2026-07-24 and no
  longer recurs (see §4.11.5), and the HINT-noise finding (F8) was
  removed the same day (protocol roles are their own namespace, no "unknown
  participant" hint fires). The typing side (`protocol`/projection/duality/
  per-op session-state typing) is `core-march-types.md` §2.7; MPST still has
  no golden corpus witness (§4.11.5); that's a coverage gap, not a known
  divergence;
- sigils.

(This is the same deferred set §0 now names. Everything that was on the ORIGINAL
v0 deferred line but is now *covered* (tuples (Task 2), records (Task 3), atoms
(Task 4), the full pattern language + guards + exhaustiveness (Task 5), local
recursive functions (Task 6), and conditionals (Task 7)) has been removed from
this queue; keep this list and §0's in lockstep as Phase-2/3 slices land.)

**Next steps (the Phase-1 closeout track):**

1. ~~Fold `specs/lang/golden/` into `test/test_oracle.ml`'s corpus~~ **DONE**:
   the `@oracle` sweep enumerates `specs/lang/golden/` alongside
   `bench/`+`examples/`, so the spec's golden anchor runs in CI, not only via the
   standalone `verify.sh`.
2. Make the reference **normative-by-cross-reference**: annotate each core
   `eval_expr` arm in `lib/eval/eval.ml` with its rule name and a pointer back
   to this document's §4 (the oracle-gated legibility refactor: the remaining
   Phase-1 code task).
3. Then open Phase 2 with the first deferred group above, as its own widening
   slice, following the same design-spec → plan → golden-anchored execution
   loop this core fragment proved out.
