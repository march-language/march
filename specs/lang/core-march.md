# Core March — Reference v1 (core fragment complete)

**Date:** 2026-07-04 (v0 walking skeleton) → 2026-07-05 (v1 consolidation)
**Status:** Reference v1 — the **complete CORE fragment** of the March language
specification, assembled and versioned from the seven incremental slices
(Tasks 1–7) that grew it end-to-end. This is the CORE, not the whole language:
the deferred set (§6) is still real and is now exactly the roadmap's Phase-2/3
queue.
**Depends on:** the language-specification roadmap design spec
(`specs/2026-07-04-language-specification-roadmap-design.md`), which framed this
document as its Phase-1 first artifact, and the Phase-1 task plan
(`specs/plans/2026-07-05-core-march-phase1-plan.md`) that Tasks 1–9 executed.

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

Its original purpose was to prove the *method* — that a normative spec can be
extracted faithfully from the existing implementation and kept honest by the
differential oracle. That method held across all seven widening slices, and this
v1 is their consolidation into one coherent reference.

**It is not** the whole language semantics. The CORE covers the pure,
value-level reduction fragment; everything outside it — strings as first-class
data (beyond their appearance in the value grammar), `to_string`/`show` and the
interface-dispatch machinery, effects/IO ordering, actors, refinements,
capabilities, the Perceus RC discipline, session types, sigils — is explicitly
**deferred** to Phase 2/3 (see §6). Each deferred group becomes a widening slice
like Tasks 1–7 did.

Every rule below is grounded in a specific line of the implementation. Where a
rule says "faithful to `eval.ml:N`", that citation *is* the correctness
argument, and the golden corpus (§5) is its executable check.

## 1. The core is the desugared AST; `eval.ml` is its reference semantics

**Decision (locked for the whole spec effort):** *Core March* is the AST as it
exists **after the desugar pass**, and the tree-walking interpreter
(`lib/eval/eval.ml`) is its **reference operational semantics**.

This is grounded, not invented. The compiler pipeline is
parse → desugar → typecheck → eval (`bin/main.ml:772`–`807`): the interpreter's
entry point `eval_module_env (m : module_)` (`eval.ml:8409`) consumes exactly
the `module_` value that `March_desugar.Desugar.desugar_module` produces — the
same `Ast.expr` type, after sugar has been removed. The TIR → LLVM path
(`Lower.lower_module`, the `--compile` branch) is a *separate* consumer of that
same desugared AST, which is why the differential oracle can hold the two
backends to a single reference.

Consequences:

- The **desugaring map** (§3) is read from `desugar.ml`; the **operational
  rules** (§4) are read from `eval.ml`. Both describe the *same object* (the
  desugared AST) from its two sides — how it is produced, and what it means.
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
(`:error(x)` ⇒ `EAtom("error", [x], _)`) — confirmed by the parser
productions that build them: `parser.mly:1211–1212` (`ATOM LPAREN args RPAREN`
⇒ `EAtom(a, args, …)`) and `:1213–1214` (bare `ATOM` ⇒ `EAtom(a, [], …)`) on
the expression side; `parser.mly:1316–1317` and `:1318–1319` mirror this for
`PatAtom` on the pattern side. The lexer produces the `ATOM` token directly
from a `:`-prefixed identifier (`lexer.mll:122`, `':' (atom_name as a) {
ATOM a }`) — there is no separate token for "atom-with-payload" vs.
"nullary atom"; the distinction is made entirely by which grammar production
matches (whether a `(` follows).

**`LitAtom` (inside `ELit`/`PatLit`) is a *different*, narrower construct
than `EAtom`/`PatAtom`, and — like `PatRecord` (§2 above) — is dead code from
the parser's perspective at this AST level.** `Ast.literal`'s `LitAtom of
string` (`ast.ml:37`) has its own `eval_expr` arm (`ELit (LitAtom a, _) ->
VAtom a`, `eval.ml:6949`) and its own `match_pattern` arm (`PatLit (LitAtom
a, _), VAtom b when a = b -> Some []`, `eval.ml:781`, already stated in
§4.3's literal-match table) — so the interpreter is fully prepared to
evaluate/match an `ELit(LitAtom _)`/`PatLit(LitAtom _)` node if one exists.
But grepping `parser.mly` for `LitAtom` finds **zero** occurrences: nothing
in the grammar ever constructs one from surface `:ok` syntax — both the
expression and pattern productions for the `ATOM` token build `EAtom`/
`PatAtom` (above), never `ELit`/`PatLit`. A `LitAtom` node can only arise by
constructing the AST directly (e.g. a test), not by parsing a `.march`
source file — the same "implemented but unreachable from any parsed
program" situation §2 already documents for `PatRecord`. (One further
subtlety, out of this fragment's scope but worth flagging for the reader who
greps `lower.ml`: the separate TIR lowering stage, `lib/tir/lower.ml:615`,
*does* rewrite a nullary `Ast.EAtom(a, [], _)` into a `Tir.EAtom(Tir.ALit
(Ast.LitAtom a))` shape — but that rewrite happens downstream of the
desugared-AST/`eval.ml` layer this spec specifies (§1), inside the TIR pass,
so it does not contradict "`LitAtom` is dead at the parser/`eval.ml` level"
above; it is simply a different representation the compiled backend chooses
for its own IR, invisible to the interpreter.)

`ETuple`'s surface form is `(e₁, …, e_k)` — parenthesized, comma-separated
expressions, `k ≥ 2` for an actual tuple; the parser also accepts `k = 0`
(`()`), which the evaluator (§4.2, E-Tuple) treats as an alias for `VUnit`
rather than a genuine zero-arity `VTuple` — see the E-Tuple rule's note. There
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
**`{ x: 1, y: 2 }`** and **`{ base with f: v, … }`** — confirmed against the
committed regression fixture `test/imports/record_native/rn_entry.march`
(e.g. `{ name: "Alice", age: 30 }`, `{ built with a: 99 }`) and by hand
(`{ x = 1 }` is a parse error; `{ x: 1 }` is not). The doc comments' `=` is
stale/never-implemented; this spec documents the grammar the parser actually
accepts, per §0's "documenting an existing core, not designing a new one."

**`PatRecord` has no surface production at all — it is dead code, reachable
only by constructing the AST node directly (e.g. in a test), never by parsing
March source.** Grepping `parser.mly` for `PatRecord` finds zero occurrences;
`desugar.ml`'s three `PatRecord` arms (`:295, 997–998, 1978`) only ever
recurse into an *already-constructed* `PatRecord`, never build one fresh from
another surface form. The LLVM backend's own comment on this is the most
direct evidence: `lib/tir/lower_match.ml:132–138`'s `pat_tag_and_subs` arm for
`PatRecord` immediately `failwith`s with *"record patterns are not yet
compilable (…) — PatRecord has no `{...}` pattern production in the grammar
today, so this indicates a pattern constructed directly rather than parsed."*
Confirmed by hand: both `let { x, y } = r` and `match r do { x, y } -> … end`
are parse errors ("I got stuck here"). The evaluator's `match_pattern` arm for
`PatRecord` (§4.3, `eval.ml:810`) and the typechecker's `infer_pattern` arm
(`typecheck.ml:2666–2675`) are both fully implemented and would work correctly
if a `PatRecord` value ever reached them — the gap is purely in the parser.
This spec therefore states the `PatRecord` matching rule (§4.3) for
completeness and fidelity to `eval.ml`, but no golden program in §5
exercises it, because no March **source program** can construct one. (This
form is collected with the other implemented-but-unreachable pattern form,
`PatAs`, in **§4.3.1**.)

`LitFloat`/`VFloat` carry an OCaml `float` (IEEE-754 double); `LitString`/
`VString` carry an OCaml `string`. `VAtom` likewise carries a `string` naming
the atom (surface `:ok`, `:error`, … — an interned-looking but here just a
string-valued tag). `LitFloat`/`LitString` are produced by the parser as
direct literal tokens — `FLOAT`, `STRING` (`parser.mly:1198`–`1199`) — with
**no desugaring**, exactly like `LitInt`/`LitBool` (§3's `ELit` row).
`LitAtom` is spelled with the same `ATOM` token (`parser.mly:1213`) but, as
just noted above, the parser never actually builds an `ELit(LitAtom …)` from
it — it builds `EAtom`/`PatAtom` instead (see the `EAtom`/`PatAtom` note
above `LitAtom` is included in the literal/value grammars above only because
`eval.ml` has match arms ready for it, for fidelity, not because surface
syntax reaches it).

**`VAtom` (nullary) vs. a payload atom's `VCon` representation.** A bare
`:ok` evaluates to `VAtom "ok"` — a distinct value former, *not* a `VCon`.
But `:error(x)` evaluates to `VCon("error", [v])` — the **same** value
former a 0-argument-vs-N-argument *constructor* application (`ECon`) would
produce, not a variant of `VAtom` extended with a payload slot. In other
words: **whether an atom expression's value is a `VAtom` or a `VCon` is
decided purely by arity** (zero args ⇒ `VAtom`, one-or-more args ⇒ `VCon`
tagged with the atom's name) — there is no `VAtom`-with-payload value shape
in the grammar at all. This is the single most load-bearing, non-obvious
fact about atoms (see the `EAtom` evaluation rule and the `PatAtom` matching
rules below, both cited against `eval.ml`).

**`ELetFn` is a local *recursive* function — and, unlike `PatRecord`/`PatAs`,
it IS reachable from surface syntax.** `Ast.expr`'s `ELetFn of name * param
list * ty option * expr * span` (`ast.ml:77`) is a **named function bound
*inside a block*** — written `fn go(params) do body end` as an `EBlock`
statement, sitting alongside `let` bindings — whose defining feature is that
its own name is in scope *within its body*, so it can call **itself**
(`go(n - 1)`). It has a real grammar production (`parser.mly:1015`–`1027`:
`FN lower_name ( params ) [ret_annot] DO block_body END` ⇒ `ELetFn(name,
params, ret, body, …)`), confirmed by hand — a `fn go(n) do … end` inside
`main` parses, interprets, and compiles+runs (see g28–g30, §5). This is the
first construct this spec adds that carries a recursive-binding semantics, and
it is the reason §4.2's block rules need one extra rule beyond E-Blk-Let.

`ELetFn` is **distinct from both** of the fragment's other two function-shaped
forms:

- from a **lambda `ELam [x…] e`** (§2 above): a lambda is an anonymous
  *expression* value that is **not self-referential** — its body's environment
  is exactly the `ρ` captured at `VClosure` creation (E-Lam), with no binding of
  the lambda to any name, so a lambda cannot recurse by name. `ELetFn` binds a
  name AND makes that name visible inside the body (the recursive knot,
  E-LetFn below).
- from a **top-level `DFn`** (a module-level `fn f(…) do … end` declaration,
  outside any block): `DFn` is a *declaration*, entered into the module's
  top-level environment before `main` runs; `ELetFn` is an *expression-level*
  statement local to one block, visible only to the rest of that block (like a
  `let`), not to the whole module.

**`ECond` is the scrutinee-*less* sibling of `EMatch` — a boolean chain, and it
IS reachable from surface syntax (like `ELetFn`, unlike `PatRecord`/`PatAs`).**
`Ast.expr`'s `ECond of (expr * expr) list * span` (`ast.ml:66`) is a list of
`(condition, body)` arm pairs, written `match do c₁ -> b₁  c₂ -> b₂  … end` —
syntactically a `match` with **no scrutinee expression between `match` and
`do`**, whose "patterns" are ordinary boolean *conditions* rather than
patterns. The parser production is `MATCH DO option(arm_sep)
separated_nonempty_list(arm_sep, cond_branch) END ⇒ ECond(bs, …)`
(`parser.mly:1075`), a distinct grammar alternative from the scrutinee-bearing
`MATCH e DO … branch … END ⇒ EMatch(…)` one line above it (`parser.mly:1073`) —
so whether a `match … do … end` parses to `EMatch` or `ECond` is decided purely
by whether a scrutinee expression sits between `match` and `do`. Confirmed by
hand — `match do x > 0 -> "pos"  true -> "nonpos" end` parses, interprets, and
compiles+runs (see g31–g32, §5).

A `cond_branch` (`parser.mly:1292`–`1296`) is either `e -> body` — an arbitrary
boolean *expression* `e` as the condition — **or** a bare `_ -> body`, which the
parser desugars to `(ELit (LitBool true, …), body)` (`parser.mly:1295`–`1296`):
i.e. `_ ->` is not a wildcard *pattern* here (there is no scrutinee to match
against) but sugar for an **always-true final arm**, exactly equivalent to
writing `true -> body`. This is the idiomatic way to make an `ECond` total (see
E-Cond's all-false behavior in §4.2). `ECond` is **distinct from `EIf`**: `EIf`
is a fixed two-way branch (`ast.ml:65`, `EIf of expr * expr * expr`) with a
*mandatory* `else`, whereas `ECond` is an n-way boolean chain with **no implicit
else** — running off the end of an all-false chain is a runtime error, not a
`VUnit` default (§4.2, E-Cond). Both are grouped together as the fragment's
"conditionals" in §4.2.

Two facts that a reader coming from surface syntax must know, because they are
load-bearing for every rule below:

- **Primitive operators are not syntax.** `a + b` is *not* a distinct node; it
  is `EApp(EVar "+", [a; b])` (parser `parser.mly:1145` for `+`, `:1136` for
  `==`). The operator name resolves, like any variable, to a `VBuiltin`
  (`eval.ml:2762` binds `"+"`, `:2805` binds `"=="`). There is no special
  "arithmetic" evaluation path — arithmetic is ordinary application of a
  built-in function value.
- **Constructor application is its own node.** `Som(7)` is `ECon("Som",[7])`,
  distinct from `EApp` — constructors build data (`VCon`), they are not called
  (`eval.ml:6977`).

## 3. Surface → core (the desugaring map)

What `desugar.ml` does to each surface form in the fragment. For this fragment
the desugarer is almost entirely the identity modulo recursion into
subexpressions — the interesting rewrites are binary operators (already done by
the parser) and multi-clause functions.

| Surface | Core form | Where |
|---|---|---|
| `a + b`, `a == b` | `EApp(EVar "+"/"==", [a; b])` — produced by the **parser**; desugar recurses but does not reshape | `parser.mly:1136,1145`; `desugar.ml:552` |
| `do let x = e₁  e₂ end` | `EBlock([ELet(x = e₁'); e₂'])` — left structural; only `bind_expr` is recursively desugared | `desugar.ml:573–593` |
| multi-clause `fn f(0) -> …  fn f(n) -> …` | **one** clause `fn f(a) -> EMatch(a, [PatLit 0 -> …; PatVar n -> …])` on a synthesized arg (tuple if arity > 1) | `desugar.ml:697–786` |
| `fn x -> e` (`ELam`) | identity (recurse body) | `desugar.ml:568–571` |
| `fn go(x…) do e end` (`ELetFn`) | **structural identity** — recurse into the body only; name/params/return-type carried verbatim. (It runs the body under `with_conn_scope (lam_params_bind_conn params)`, connection-linearity bookkeeping irrelevant to this fragment; no reshaping.) | `desugar.ml:653–657` |
| `f(e…)` (`EApp`) | identity, plus a qualified-`ECon` fold for `Mod.Ctor(args)` | `desugar.ml:552–563` |
| `C(e…)` (`ECon`) | identity (recurse args) | `desugar.ml:565–566` |
| `:ok`, `:error(e…)` (`EAtom`) | identity (recurse args; `[]` for a nullary atom) | `desugar.ml:644–645` |
| `(e…)` (`ETuple`) | identity (recurse elements) | `desugar.ml:602–603` |
| `{ f: e, … }` (`ERecord`) | identity (recurse each field's value expr; field names untouched) | `desugar.ml:605–606` |
| `{ base with f: e, … }` (`ERecordUpdate`) | identity (recurse base + each update value expr) | `desugar.ml:608–611` |
| `e.f` (`EField`) | **not** pure identity — if `e` is a chain of `ECon`/`EField` that flattens to a dotted path (a module reference, e.g. `A.B.f`), rewrite to a single qualified `EVar "A.B.f"` (or `ECon` if `f` starts uppercase, i.e. a qualified constructor); otherwise identity (recurse into `e`, keep `EField`) | `desugar.ml:613–633` |
| `match e do … end` (`EMatch`) | identity (recurse scrutinee, guards, bodies) | `desugar.ml:595–600` |
| `if c do a else b end` (`EIf`) | **identity** — `EIf` is *not* rewritten to a match on the bool | `desugar.ml:635–636` |
| `match do c -> b, … end` (`ECond`) | **identity** — recurse into each arm's condition and body; arm order preserved verbatim, NOT rewritten to nested `EIf`s. (The `_ -> b` catch-all was already turned into a `true`-condition arm by the *parser*, `parser.mly:1295–1296`, before desugar sees it.) | `desugar.ml:638–639` |
| `ELit`, `EVar` | identity | `desugar.ml:548` |
| `type C = A \| B` (`DType`) | identity — the desugarer never touches type declarations or constructors | `desugar.ml:798–800` |

The surface language's meaning is therefore: **desugar to core, then evaluate
the core by §4.**

## 4. Operational semantics

The interpreter is a **big-step** evaluator: `eval_expr : env -> expr -> value`
(`eval.ml:6943`). We present the semantics in the same big-step, environment
form — one rule per `eval_expr` arm — because that makes the "spec matches the
implementation" cross-check exact (rule ⇄ arm). §4.5 states the small-step
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
forms, presented together above.** They share the same evaluation shape — a
`Bool`-valued test drives the choice of exactly one continuation — but differ
in arity and totality:

- **`EIf e_c e_t e_e`** (E-If-T / E-If-F, `eval.ml:7085`–`7095`) is a fixed
  **two-way** branch with a *mandatory* `else` (§Syntax: `else` is not optional
  — the parser rejects `if c do … end` without it, `parser.mly:1058`–`1062`).
  It is therefore **always total**: `e_c` is either `VBool true` (run `e_t`) or
  `VBool false` (run `e_e`), with no third outcome for a well-typed program (a
  non-Bool `e_c` ⇒ `eval_error`, but the typechecker rules that out).
- **`ECond [(c₁,b₁)…(c_n,b_n)]`** (E-Cond-Sel / E-Cond-Fail, `eval.ml:7097`–
  `7106`) is an **n-way** boolean chain — the scrutinee-less
  `match do c -> b … end` — with **no implicit else**. It evaluates conditions
  top-to-bottom and runs the first `VBool true` arm's body (E-Cond-Sel); crucially,
  unlike `EIf`, it is **NOT total** — if every condition is false it raises at
  runtime (E-Cond-Fail), because there is no fall-through default. Authors make
  it total with a final `true ->` arm (or the `_ ->` sugar the parser rewrites
  to `true ->`, `parser.mly:1295`–`1296`).

The desugarer leaves BOTH forms structurally intact (§3): neither is rewritten
into the other — `EIf` is *not* lowered to a one-arm `ECond`, and `ECond` is
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
(`eval.ml:7049`–`7063`) — only if ALL of that fails does it fall through to
evaluating `ex` as an ordinary expression and trying the record-field /
`VCon`-module-member arms shown in E-Field (`eval.ml:7064`–`7083`). This
mirrors the analogous, but separate, COMPILE-TIME rewrite the desugarer
performs for the same surface form (§3's `EField` row) — the desugar-time
rewrite handles the common case (a literal module path known at desugar
time), while this runtime fallback handles paths the desugarer's simpler
walk didn't resolve (e.g. one that ends in a `VCon`-shaped module reference
established later, at eval time, via `ensure_module_loaded`). A record's
`.field` access and a module's `.member` access therefore share ONE surface
form (`e.f`) and one AST node (`EField`), disambiguated dynamically by what
`e` evaluates to — this is a fidelity note about `EField`'s full behavior,
not a new core construct: the fragment's E-Field rule (§4.2) states only the
record-field case, which is this task's scope.

### 4.2.1 `ERecordUpdate` on a missing field: the interpreter/compiled adjudication (resolved)

**This is the semantic decision Task 3 exists to make.** `{ base with f: v
}` is only a well-formed *program* when `base`'s type is a concrete,
statically-known `TRecord` — in that case the typechecker's `ERecordUpdate`
case (`typecheck.ml:3855`–`3892`) resolves `base`'s type via
`expand_record`, and REJECTS the program at typecheck time if `f` is absent
from the resolved fields (`typecheck.ml:3869`–`3875`, "This record does not
have a field called...") — so E-Update's runtime behavior on an absent field
is **unreachable** for a statically-typed base; both backends simply never
run it, because the program never compiles/interprets past typechecking.

The rule only becomes runtime-observable when `base`'s type is **erased** —
a bare, unconstrained type variable that `expand_record` cannot resolve to a
concrete `TRecord` (`typecheck.ml:3879`–`3886`). This happens for a base
produced by a fully polymorphic stdlib builtin such as `record_from_list`
(`("record_from_list", poly2 (fun a b -> TArrow (t_list (TTuple [t_string;
a]), b)))`, `typecheck.ml:1297` — the return type `b` is a fresh, unrelated
type variable) or `record_put`. In that `TVar` branch, the typechecker
cannot check the update's field names against anything, so it instead
BUILDS a partial `TRecord` constraint out of the update's OWN field names
(`typecheck.ml:3881`–`3885`) and lets the program through — deferring the
"does this field actually exist on the base" question to runtime, where the
two backends used to disagree:

- **Compiled** (`llvm_emit.ml:2803`, `runtime/march_extras.c`
  `march_record_update_dyn`, `:2206`–`2231`): resolves every update name
  against the base's runtime shape registry FIRST, and **panics** ("record
  update: no field \"%s\" in record") before touching any reference counts
  if any name is unresolved.
- **Interpreter, BEFORE this task** (`eval.ml`'s old `ERecordUpdate` arm):
  silently APPENDED any update field absent from the base — `{ base with z:
  99 }` on a base without `z` produced a record with `z` added, no error.

Concretely, `{ record_from_list([("a", 1)]) with z: 99 }` used to panic
compiled (`no field "z" in record`, clean exit 1) while succeeding
interpreted (`Some(99)` printed via `record_get`, exit 0) — confirmed by hand
before this task's fix (see the golden-corpus verification note below).
This was filed as an open bug (`specs/todos.md`, "Interpreter/compiled
divergence: `ERecordUpdate` on a missing field") and pinned by a dedicated
unit test (`test/test_properties.ml`,
`test_record_update_missing_field_on_erased_base_...`) rather than generated
by the QCheck property corpus, per that plan's "constrain each generator to
the currently-working subset" rule.

**Adjudicated rule (this task): the compiled contract is normative.** A
functional record update is defined **only** for a field that already
exists on the base record's actual (runtime) shape. Updating a field absent
from that shape is a **runtime error**, full stop — it is not a shape
extension, and the language does not have a separate "extend" operation
spelled `{ base with … }` (field-adding is `record_put`'s job, a distinct
builtin with genuinely different — and intentional — semantics; see the
note below E-Update above). This is the safer contract: silently
fabricating a field an author never declared masks a likely typo or a stale
refactor, exactly the class of bug static field-name checking exists to
catch, and the compiled backend was already enforcing it — the interpreter
was the outlier.

**Outcome: the interpreter was converged to match, and both backends now
agree.** `eval.ml`'s `ERecordUpdate` arm now validates every update name
against the base's actual fields BEFORE merging (`eval.ml:7026`–`7029`,
shown as the ADJUDICATED RULE note under E-Update above) and raises
`eval_error "record update: no field '%s' in record" k` — deliberately
matching the compiled panic's wording ("no field ... in record") for
diagnostic consistency across backends. All six standard test runners
(`run_compiler`, `run_eval`, `run_codegen`, `run_stdlib`,
`test_stdlib_march`, `run_snapshots`) and the `@oracle` conformance sweep
stayed green after this change — no code in the compiler, stdlib, or test
suite depended on the old fabricate-on-missing-field behavior, other than
the one test built to pin the divergence itself, which was updated to
assert convergence instead (see `test/test_properties.ml`,
`test_record_update_missing_field_on_erased_base_converged`, and
`test/test_codegen.ml`'s `test_erased_update_missing_field_panics_compiled`
doc comment). The `specs/todos.md` open-divergence entry and the informal
"known divergence" framing around this bug are both retired by this
convergence; §5's golden corpus documents the now-agreeing behavior as a
prose note (not a golden MATCH program — see §5's caveat on why this
specific shape is deliberately NOT added as one).

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
binding — `eval.ml:6993` — because binding is only meaningful relative to a
continuation, which the block supplies. A bare `ELetFn` evaluated *outside* a
block — e.g. as the last/only statement of a block, which the `[e]` last-arm
sends to `eval_expr`, not `eval_block` — ties the SAME knot but simply RETURNS
the closure `c` as the block's value instead of binding it and continuing
(`eval.ml:7262`–`7271`); `c` is still self-referential, so the returned value
can recurse if later applied, but nothing in that block ever sees `f` by name.)

**Why `ELetFn` is the one construct that needs a mutable ref.** Every other
rule in §4 threads the environment as a **persistent** association list: a
binding is created by *prepending* `(name ↦ value)` to `ρ` (§4.1), and the
value being bound is fully evaluated *before* the extended environment exists.
That order is fine for `let x = e` (E-Blk-Let) — `e` is evaluated in the
*old* `ρ`, so `x` need not be in scope while computing its own value. But a
*recursive* function's value (its closure) must capture an environment in
which its **own name already resolves to that very closure** — a cyclic
dependency the strict "evaluate the value, then extend the env" order cannot
satisfy directly, because the closure and the environment each need the other
first. `eval_block`'s `ELetFn` arm (`eval.ml:6875`–`6884`) breaks the cycle
with the single use of mutation in the otherwise-persistent environment: it
allocates a `ref` (`env_ref`, `eval.ml:6878`) initialized to the *pre-binding*
`ρ`, builds the closure-carrying `VBuiltin` wrapper whose body **defers**
reading the environment until call time (`let call_env = !env_ref`,
`eval.ml:6880` — read on *every* application, not captured once), extends `ρ`
with `f ↦ c` to get `ρ'` (`eval.ml:6882`), and only THEN back-patches
`env_ref := ρ'` (`eval.ml:6883`). By the time `f` is ever *called*, `!env_ref`
is `ρ'`, which contains `f ↦ c` — so the deferred read hands the body an
environment in which `f` is itself, closing the recursive knot. The
indirection through `VBuiltin`-wrapping-`VClosure` (rather than a plain
`VClosure` captured directly) exists precisely so the environment read can be
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
  `:7340`) — so an earlier branch always shadows a later one that would also
  match.
- **Pattern-extended environment.** On `match_pattern v br.branch_pat = Some
  bindings` (`eval.ml:7324`, `:7326`), the body and guard both run in `env' =
  bindings @ env` (`eval.ml:7327`) — the σ bindings are *prepended* to ρ, so by
  the §4.1 first-occurrence lookup rule a pattern variable shadows any
  same-named outer binding for the duration of the arm.
- **Guard (`branch_guard`, the `when g` clause).** The guard is
  `br.branch_guard : expr option` (`ast.ml:108`). When absent (`None`) the
  branch is selected outright (`guard_ok = true`, `eval.ml:7330`). When present
  (`Some g`), the guard `g` is evaluated **in the pattern-extended env `env'`**
  (`eval.ml:7332`) — so it may read the variables the pattern just bound — and
  its result **must be a `VBool`**: `VBool b ⇒ guard_ok = b` (`eval.ml:7333`),
  and any non-`VBool` value ⇒ `eval_error "guard must evaluate to a boolean"`
  (`eval.ml:7334`). A guard that yields `VBool false` does NOT fail the whole
  match; it falls through to the next branch (`go (arm_idx + 1) rest`,
  `eval.ml:7340`), exactly as a non-matching pattern does. (Surface syntax:
  `p when g -> e_b`, `parser.mly:1280` builds the branch, `when_guard` =
  `WHEN; e = expr`, `parser.mly:409`–`410`.)
- **Exhaustiveness / no-match.** When `go` reaches the empty list `[]` — no
  branch's pattern matched, or every matching branch had a false guard — it
  raises `Match_failure` (`eval.ml:7320`–`7322`) with the message
  *"Non-exhaustive pattern match: no branch matched the value …"*. `match` is
  therefore **not** statically total in this reference semantics: a
  non-exhaustive `match` typechecks (the typechecker emits only a *warning*,
  not an error, for a missing case) and fails at **runtime** with
  `Match_failure` if control actually reaches the uncovered value — confirmed
  by hand (`match n do 0 -> … 1 -> … end` on `n = 5` prints the exhaustiveness
  warning at compile time, then panics `match failure — Non-exhaustive pattern
  match: no branch matched the value 5` at run time, exit nonzero). A
  `PatWild` (`_`) catch-all arm (`eval.ml:773`, `match(PatWild, v) = ∅`, always
  succeeds) is the idiomatic way to make a `match` total; this is why no golden
  program can be a runtime-`Match_failure` witness (a nonzero interpreter exit
  is an automatic `INTERP FAIL` under `verify.sh`, the same harness limitation
  §4.4.1 notes for the crashing strict-`&&`/`||` witness — g26 instead exhibits
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

**This dual-arm rule is the key documented fact about atoms — a
payload-carrying `PatAtom` matches a `VCon`, not a `VAtom`.** `match_pattern`'s
two `PatAtom` cases (`eval.ml:797`–`798`, shown as the two rules above) are
tried in order: the FIRST requires the scrutinee to be a nullary `VAtom` with
an equal tag AND the pattern itself to be nullary (`pats = []`, guarded in
the OCaml `when` clause) — `match(PatAtom "ok" [], VAtom "ok") = ∅`. The
SECOND requires the scrutinee to be a `VCon` whose tag equals the pattern's
atom name — `match(PatAtom "error" [p], VCon("error", [v])) = match(p, v)`,
componentwise via the same `match_list` helper `PatCon`/`PatTuple` share
(§4.3 below). A `PatAtom` therefore matches **two structurally different
value shapes** depending on whether it (and the value) carries a payload —
this is the pattern-side mirror of E-Atom-0/E-Atom-N's value-shape split
above (§4.2), and it is why `:error(msg)` (a `PatAtom` with one sub-pattern)
can successfully destructure a value that was built as a `VCon`, never a
`VAtom`, at construction time (`eval.ml:7146–7148`). Unlike `PatCon`, there is
no separate arity-mismatch clause spelled out for `PatAtom`/`VCon` beyond the
`List.length pats <> List.length args` check inside the second arm
(`eval.ml:799`) — a nullary `PatAtom` (`pats = []`) can never match a `VCon`
through this second arm either, because `List.length [] <> List.length args`
is true whenever `args` is non-empty, so `:ok` (nullary pattern) correctly
fails against a `VCon("ok", [x])` value (which cannot arise from `:ok`
construction anyway, since E-Atom-0/E-Atom-N tie payload-presence at
construction time to the same value-shape choice a matching `PatAtom` must
make) — the two sides stay in lockstep by construction, not by coincidence.

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
component fails, otherwise unioning the accumulated bindings — the same
combinator `PatCon`'s arm (above) already relies on for its own `⋃`.
`PatTuple ([], _)` matching `VUnit` (`eval.ml:803`) is the pattern-side
counterpart of E-Tuple's `ETuple [] ⇓ VUnit` alias (§4.2): a 0-arity tuple
*value* never actually exists at runtime (only `VUnit` does), so the empty
tuple pattern is special-cased to accept `VUnit` directly rather than an
(impossible) `VTuple []`.

**`PatRecord` implements SUBSET matching, unlike every other structural
pattern in this fragment.** `PatCon`/`PatTuple`/`PatAtom` all require the
value to have EXACTLY the pattern's arity (`List.length pats <> List.length
args/vs` ⇒ `⊥`, `eval.ml:792, 805`) — a 2-element `PatTuple` never matches a
3-element `VTuple`. `PatRecord`'s implementation (`eval.ml:810–822`) is
different by construction: it `List.fold_left`s over the PATTERN's field
list only, looking each named field up in the value's field list via
`List.assoc_opt` (`eval.ml:815`) — there is no arity check against the
record's total field count anywhere in this arm. So `{ x }` (naming only
`x`) successfully matches a value with fields `{x: 1, y: 2, z: 3}`, binding
just `x`, and simply never inspects `y`/`z`. The failure mode is asymmetric:
missing a field the PATTERN needs (`List.assoc_opt` returns `None`,
`eval.ml:816`) fails the whole match, but the value having EXTRA fields the
pattern doesn't mention is never even examined, let alone rejected. As documented in
§2, however, this rule is presently unreachable from any parsed March
program — `PatRecord` has no `{...}` pattern grammar production
(`lib/tir/lower_match.ml:132–138`), so this subset-matching behavior can only
be observed by constructing the AST node directly (e.g. from a test), not by
writing and running a `.march` source file.

**`PatAs` (`p as x`) binds the whole matched value AND the inner pattern's
bindings.** `match_pattern`'s `PatAs (inner, alias, _)` arm (`eval.ml:826`–
`829`) first matches the value against the *inner* pattern (`match_pattern v
inner`); if that fails (`None`), the whole `PatAs` fails (`eval.ml:828`); if it
succeeds with bindings `bs`, the result is `(alias.txt, v) :: bs`
(`eval.ml:829`) — i.e. σ extended with the alias `x` bound to the ENTIRE value
`v` that was matched, in addition to whatever the inner pattern bound. So
`match(PatCon "Som" [PatVar "v"] as "whole", VCon("Som",[VInt 7]))` binds both
`v ↦ VInt 7` (from the inner `PatVar`) and `whole ↦ VCon("Som",[VInt 7])` (the
whole value). Because the alias is **prepended** (`:: bs`, `eval.ml:829`), it
takes lookup precedence over any inner binding of the same name (§4.1
first-occurrence rule) — an edge case that cannot arise from well-typed source
anyway. The inner `p` may be any pattern, so `PatAs` composes with nesting like
every other structural pattern; the recursion is `match_pattern`'s own, not a
special case.

**`PatAs` has no surface production at all — it is dead code, exactly like
`PatRecord`, reachable only by constructing the AST node directly.** Grepping
`parser.mly` for `PatAs` finds **zero** occurrences: the `pattern` grammar
(`parser.mly:1311`–`1341`) has productions for `PatCon`/`PatAtom`/`PatWild`/
`PatVar`/`PatLit`/`PatTuple` (and the list-literal sugar), but **no `pattern
AS name` rule** — the `AS` token is used only for module aliases (`alias P as
Q`, `parser.mly:704`–`707`) and as a soft identifier (`parser.mly:1361`),
never to build a `PatAs`. Confirmed by hand against the built compiler: `p as
x` is a parse error in every position tried — as a `match` arm (`Som(v) as
whole -> …` and `n as whole -> …` both report *"I was expecting `->` in the
match arm here"* at the `as`) and as a `let` binding (`let (n as whole) = 5`
reports *"I got stuck here"* at the `as`). `desugar.ml`'s three `PatAs` arms
(`:296, 1000, 1980`) only ever recurse into an *already-constructed* `PatAs`
(respanning / collecting bound vars), never build one fresh from another
surface form — the same "implemented in `eval.ml`/`desugar.ml`/`typecheck.ml`
but unreachable from any parsed program" situation §2 documents for
`PatRecord`. This spec therefore states the `PatAs` matching rule (above) for
completeness and fidelity to `eval.ml`, but **no golden program in §5 exercises
it**, because no March *source program* can construct one — the golden
substitute (g27) instead exercises a guard reading pattern-bound variables,
which IS reachable and covers the adjacent "bindings visible to the arm"
semantics. (This form is collected with the other implemented-but-unreachable
pattern form, `PatRecord`, in **§4.3.1**.)

`match(PatLit ℓ, v)` is one arm per literal kind, each requiring **both** the
pattern and scrutinee to be the *same* value constructor with equal payload —
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

(`LitFloat` equality is OCaml `(=) : float -> float -> bool` — ordinary IEEE
structural equality, no epsilon tolerance; this is the same primitive used by
δ-EqF below.)

`bare(C)` strips a leading module qualifier (`eval.ml:786`); the constructor
value's tag is stored already-stripped (`eval.ml:6981`), which is why
`match(PatCon "Som" …, VCon "Som" …)` succeeds regardless of qualification.

### 4.3.1 Implemented-but-unreachable pattern forms (`PatRecord`, `PatAs`)

Two of the pattern constructors whose matching rules §4.3 states in full —
**`PatRecord`** (`{ f, … }`, the record-destructuring pattern) and **`PatAs`**
(`p as x`, the as-pattern) — are **implemented in the interpreter but have NO
surface grammar**: no `parser.mly` production ever builds one from `.march`
source, so both are *dead code* from the parser's perspective. They are
reachable only by constructing the `Ast.pattern` node directly (e.g. inside an
OCaml unit test), never by writing and running a March program.

This spec documents their matching rules anyway, **for fidelity** — §4 is a
faithful transcription of the interpreter's `match_pattern`, and
`match_pattern` supports both (with fully-implemented arms that would work
correctly if such a node ever reached them). Stating them keeps the spec an
honest mirror of `eval.ml`. But **no golden program in §5 exercises either**,
because no March *source program* can construct one.

The evidence and the exact rule citations live at each form's own rule (kept in
place — this subsection collects, it does not relocate the citations):

- **`PatRecord`** — matching rule and its SUBSET-matching semantics: §4.3
  (`match(PatRecord …)`, `eval.ml:810–822`, `eval.ml:824`). Dead-code evidence:
  §2's "`PatRecord` has no surface production at all" note (zero `parser.mly`
  occurrences; `lib/tir/lower_match.ml:132–138`'s `failwith` comment "PatRecord
  has no `{...}` pattern production in the grammar today"; both `let { x, y } =
  r` and `match r do { x, y } -> … end` are parse errors). The typechecker's
  `infer_pattern` arm (`typecheck.ml:2666–2675`) and the interpreter's
  `match_pattern` arm are both complete; the gap is purely in the parser.
- **`PatAs`** — matching rule (binds the whole matched value AND the inner
  pattern's bindings): §4.3 (`match(PatAs …)`, `eval.ml:826–829`). Dead-code
  evidence: §4.3's "`PatAs` has no surface production at all" note (zero
  `parser.mly` occurrences; the `AS` token is only a module-alias / soft
  identifier; `Som(v) as whole -> …`, `n as whole -> …`, and `let (n as whole)
  = 5` are all parse errors). `desugar.ml`'s three `PatAs` arms (`:296, 1000,
  1980`) only ever recurse into an already-constructed `PatAs`, never build one.
  The golden substitute is **g27** (a guard reading its branch's own
  pattern-bound variables — the reachable analogue of the as-binding's
  "bindings visible to the arm" semantics).

(`LitAtom` inside `ELit`/`PatLit` is a THIRD, narrower implemented-but-parser-
unreachable form — see §2's "`LitAtom` … is dead code from the parser's
perspective" note — but it is a *literal* constructor, not a top-level pattern
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
the value kinds shown — an application outside those kinds raises
`eval_error` (an OCaml exception the interpreter's top level reports as a
compiler-fatal error; not a `March` value, hence not further modeled here).

**Arithmetic** — `arith_num iop fop name` (`eval.ml:850`–`853`) applies `iop`
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
`(iop, fop)` pair — eval.ml:2762–2764. Surface `a - b`/`a * b` are
`EApp(EVar "-"/"*", [a;b])`, produced by the parser exactly like `+`
— `parser.mly:1146` (`-`), `:1153` (`*`).)

`/` and `%` (integer division and remainder) are **not** `arith_num` — they
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
**truncate toward zero** (e.g. `(-7) / 2 = -3`, `(-7) mod 2 = -1`) — this is
the concrete rounding rule the spec commits to, since it is what `eval.ml`
actually computes. There is no `%`-on-`Float` builtin (`%` restricted to
`VInt`; a `VFloat` operand falls through to the catch-all `eval_error
"builtin %%: expected two integers"`, `eval.ml:2777`).

**Note on surface spelling:** the brief's "arithmetic … `mod`" refers to the
*semantic family* (integer remainder), not a literal `mod` infix token —
`mod` is a **reserved keyword** for module declarations (`mod Name do … end`,
lexer.mll:31, `MOD` token) and cannot be reused as an operator. The surface
spelling of integer remainder is `%` (`PERCENT` token, lexer.mll:161;
`parser.mly:1155` builds `EApp(EVar "%", [a;b])`); its builtin name in
`base_env` is likewise `"%"`, not `"mod"`.

**Comparison family** — `cmp_op op_i op_f op_s op_b name` (`eval.ml:876`)
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
`(<)`, `(<=)`, `(>)`, `(>=)` as the four same-kind comparators — the table
above collapses `Int`/`Float`/`String`/`Bool` into "same four pairs" per
operator to avoid 24 near-identical rows; each pair is total for that
operator restricted to two values of the *same* one of those four kinds.)
For `Int`/`Float`/`String`/`Bool`, every operator in this family is **total**
and needs no interface dispatch — the `Eq`/`Ord`-impl and structural-equality
fallback arms (`eval.ml:881`–`914`) exist for types outside this fragment
(records, ADTs, …) and are explicitly out of scope here (this is the same
under-specified corner the walking skeleton flagged for `==`: the
`==`-on-`Newtype` bug the oracle found lived there).

**Unary negation** — `negate` (`eval.ml:2932`), reached from surface prefix
`-e` which the parser rewrites to `EApp(EVar "negate", [e])`
(`parser.mly:1162`–`1163`, distinct from binary `-`):

```
(δ-Neg-I)  f₋₁ [VInt n]   = VInt (~- n)                        eval.ml:2933
(δ-Neg-F)  f₋₁ [VFloat f] = VFloat (~-. f)                      eval.ml:2934
```

**Boolean ops** — `&&`, `||`, `not` are plain strict `VBuiltin`s restricted to
`VBool`, exactly parallel to `+`/`==` (see §4.4.1 for the load-bearing fact
that they do **not** short-circuit):

```
(δ-And)  f_&& [VBool a; VBool b] = VBool (a && b)               eval.ml:2812–2814
(δ-Or)   f_|| [VBool a; VBool b] = VBool (a || b)                eval.ml:2815–2817
(δ-Not)  f_not [VBool b]         = VBool (not b)                 eval.ml:2818–2820
```

**String concatenation** — `++`, restricted to `VString`:

```
(δ-Concat) f₊₊ [VString a; VString b] = VString (a ^ b)          eval.ml:2822–2824
```

Surface `a ++ b` is `EApp(EVar "++", [a;b])`, produced by the parser
(`parser.mly:1147`) at the same precedence level as `+`/`-` (`expr_add`).

### 4.4.1 `&&`/`||` are strict, not short-circuiting (resolved from the code)

**This is an operational rule, not a δ-rule** — it is a fact about *when* the
right operand is evaluated, which the δ-rule table above cannot express
because δ-rules apply to already-evaluated argument values.

**Resolved answer: `&&` and `||` are strict.** Both operands are
unconditionally evaluated before the operator is applied — there is no
short-circuiting. This holds for both the `&&`/`||` symbols directly and for
any surface spelling that reduces to them.

**How this was verified** (not guessed): surface `a && b` / `a || b` are
built by the **parser**, not the desugarer, as ordinary `EApp` nodes —
`expr_and: a AND b { EApp (EVar "&&", [a; b]) }` (`parser.mly:1132`) and
`expr_or: a OR b { EApp (EVar "||", [a; b]) }` (`parser.mly:1128`) — exactly
the same shape as `a + b`. `AND`/`OR` are not word-keywords; the lexer maps
the *symbols* `&&`/`||` straight to the `AND`/`OR` tokens
(`lexer.mll:168`–`169`); grepping the keyword table (`lexer.mll:20`–~`75`)
confirms there is no `"and"`/`"or"` word entry, so **there is no English-word
`and`/`or` surface form in March** — only `&&`/`||`.

Given `EApp(EVar "&&", [a;b])`, the single `eval_expr` arm that handles
*every* `EApp` — `eval.ml:6957`–`6975` — evaluates the callee (`f`) and then
does `List.map (eval_expr env) args` (`eval.ml:6967`) **before** calling
`apply fn_val arg_vals` (`eval.ml:6972`). This map has no special case for any
callee name; it evaluates `a` and `b` unconditionally, in order, whatever the
result of evaluating `a` is, and only then applies the builtin closure looked
up for `"&&"`/`"||"` (`eval.ml:2812`–`2817`, shown as δ-And/δ-Or above), which
itself pattern-matches on two already-produced `VBool`s. Grepping `ast.ml` and
`eval.ml` for `EAnd`/`EOr` confirms there is no dedicated short-circuiting AST
node or evaluator arm — `&&`/`||` are ordinary named values of type
`value list -> value`, dispatched through the generic strict-application
path, with **no** mechanism by which `b` could be skipped.

Consequence: `false && (1 / 0 == 0)` and `true || (1 / 0 == 0)` both **raise**
`eval_error "division by zero"` in March (confirmed by direct test —
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
operand already determines the result) and confirms — identically,
interpreted and compiled — that the side effect fires anyway. That is the
golden-checked confirmation of strictness; the crashing variant above is the
sharper illustration but is deliberately kept out of the golden corpus for
the harness-compatibility reason just given.

(`not` is unary and has no left-to-right evaluation-order question — `!e` /
`not(e)` evaluate the single argument then apply `eval.ml:2818`–`2820`, same
generic path.)

### 4.5 Relationship to the small-step form (the metatheory target)

`specs/lean4-metatheory-plan.md` will state the semantics as a **small-step**
relation `e → e'` (for progress + preservation). The standard call-by-value,
left-to-right small-step system — evaluation contexts `E ::= □ | E(e…) | v(…E…e) |
C(…E…e) | if E then e else e | match E of …`, β-reduction via closure-env
extension, and the δ-rules above — is **equivalent** to the big-step system here:
for closed `e`, `∅ ⊢ e ⇓ v` **iff** `e →* v`. The big-step rules are the faithful
mirror of the interpreter (used to *validate* the model against `eval.ml`); the
small-step form is the shape the proofs consume. Writing the full small-step
apparatus (contexts + the substitution-vs-environment reconciliation) is
metatheory work (the Lean track), not part of this reference — but note it is a
*refinement* of §4.2, not a different semantics.

### 4.6 Faithfulness (the honest caveat)

The §4.2–4.4 rules were transcribed arm-for-arm from `eval.ml` at the cited
lines. That transcription is **human-reviewed, not mechanically verified** —
this is the roadmap's §7 faithfulness risk made concrete, and it remains true
now that the core is complete: the rules are only as faithful as the review of
each citation. What *is* mechanically checked is weaker but real: the golden
corpus (§5) confirms that, on these 32 programs, the interpreter these rules
describe and the independently-written compiled backend produce identical
output. A divergence there would mean either the interpreter or the compiler is
wrong; agreement plus arm-for-arm review is the reference's correctness
evidence. This caveat does NOT weaken with completion — a complete core is a
larger transcription surface, so the golden corpus (and the CI `@oracle` sweep
it feeds) is what keeps the "spec matches the implementation" claim honest as
the reference is relied on.

## 5. Golden conformance corpus

Thirty-three programs in `specs/lang/golden/`, each exercising a slice of the
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
matching + guard + exhaustiveness slice — a deeply nested pattern (con → tuple
→ con), a guarded branch that FALLS THROUGH to a later branch, a deliberate
`_` catch-all after specific patterns, and a guard reading its branch's own
pattern-bound variables (the reachable substitute for the unparseable `PatAs`
as-pattern — see the `PatAs` note in §4.3); `g28`–`g30` are Task 6's addition,
covering local recursive functions (`ELetFn`, §4.2's E-LetFn / the env_ref
recursive-knot) — a self-referential `fn go` computing factorial, a local
recursive fn CLOSING OVER an outer `let` binding (lexical capture + recursion
together), and a recursion whose result is bound by a following `let` and used
by the rest of the block (proving the `ELetFn` binding is visible to the block
continuation, not only inside its own body); `g31`–`g32` are Task 7's addition,
covering the boolean-chain conditional (`ECond`, §4.2's E-Cond-Sel /
E-Cond-Fail — the scrutinee-less `match do c -> b … end`) — a chain where a
MIDDLE arm is the first `VBool true` and is selected (earlier false arms
skipped, later arms including the terminal catch-all never consulted), and the
all-false path routed through a terminal `_ ->`/`true ->` catch-all arm (the
non-crashing witness of "the last arm is selected precisely when every earlier
condition is false"; the genuinely-all-false chain that would raise
`non-exhaustive match do` at runtime is deliberately NOT a golden program, since
a nonzero interpreter exit is an automatic `INTERP FAIL` under `verify.sh` — the
same harness limitation §4.4.1 / §4.3 note for the crashing strict-`&&` and
`Match_failure` witnesses):

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
| `g13_strict_bool.march` | `&&`/`\|\|` **strictness** witness (§4.4.1) — a `println` inside the operand a short-circuiting evaluator would skip fires anyway | `or-rhs-evaluated`/`and-rhs-evaluated`/`true`/`false` |
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
| `g24_nested_con_tuple.march` | deeply nested pattern — `PatCon (Wrap) [PatTuple [PatVar; PatCon (Som/Non)]]`, matched componentwise via `match_list` recursion at three depths (con → tuple → con → var) | `7` / `9` |
| `g25_guard_fallthrough.march` | a `PatVar` branch whose guard `when n > 10` is FALSE for `n = 5`, so it falls through (`eval.ml:7340`) to a later branch that matches — the guard-fall-through witness | `big`/`small`/`nonpositive` |
| `g26_catchall.march` | specific `PatCon` branches (`Red`/`Green`) then a deliberate `PatWild` (`_`) catch-all, which selects for every other value (`Blue`, `Other(7)`) and keeps the `match` total | `1`/`2`/`0`/`0` |
| `g27_guard_binding.march` | a guard `when a == b` reading variables bound by its OWN branch pattern `P(a, b)` (guard evaluated in the pattern-extended env, `eval.ml:7327,7332`); false for `P(3, 10)` ⇒ falls through — the reachable substitute for the unparseable as-pattern | `0`/`7` |
| `g28_letfn_factorial.march` | a local self-referential `fn go(n)` computing factorial recursively — `go` calls itself via the env_ref recursive knot (E-LetFn, `eval.ml:6875–6884`) | `120`/`1` |
| `g29_letfn_capture.march` | a local recursive `fn go` that CLOSES OVER an outer `let` binding (`step`) while recursing — proves lexical capture + recursion together (the re-read env `!env_ref` contains both the outer `let` and `go` itself, `eval.ml:6880–6883`) | `8` |
| `g30_letfn_sum_result.march` | a recursive `fn go` (sum-to-n) whose RESULT is bound by a following `let` and used by the rest of the block — proves the `ELetFn` binding is visible to the block continuation (`eval.ml:6884`), like `let` | `55`/`110` |
| `g31_cond_middle_arm.march` | `ECond` boolean chain where the FIRST condition is false and the SECOND (middle) is the first `VBool true`, so the MIDDLE arm is selected — top-to-bottom, first-true-wins, earlier false arms skipped and later arms (incl. the `true` catch-all) never consulted (E-Cond-Sel, `eval.ml:7097–7106`) | `A`/`B`/`C`/`F` |
| `g32_cond_all_false_catchall.march` | `ECond` where every SPECIFIC condition (`n > 0`, `n < 0`) is false for `n = 0`, so control reaches the terminal `_ ->` catch-all — the non-crashing witness of the all-false path (a genuinely all-false chain raises at runtime, E-Cond-Fail `eval.ml:7099`; `_ ->` is parser sugar for a `true ->` arm, `parser.mly:1295–1296`, keeping the chain total) | `positive`/`negative`/`zero` |
| `g33_float_show.march` | whole-number `Float` **display** via the `float_to_string` observation primitive — added after the concurrent `float_to_string` backend-unification fix (`0a2d3f53`) that the golden corpus's Task-1 float program had surfaced. Pins only the display format (four backends agree a whole-number `Float` prints OCaml-style `1.`, matching the `eval.ml` `string_of_float` reference); it does NOT lift the float deferral of §0/§6 — float arithmetic and ordering remain deferred | `1.`/`42.`/`100.`/`0.`/`-3.`/`1.5` |

**Result: 32 / 32 matched, 0 divergences in the committed corpus** (These print via `println` /
`int_to_string` / `float_to_string` / `bool_to_string` — *observation
primitives* used to make the result observable; they are outside the pure
reduction fragment and are treated here only as opaque output functions, not
specified by §4.)

**Two guardrails deliberately followed while drafting `g17`–`g20`, both
confirmed by hand, not assumed:** (1) no golden program prints a whole
`VRecord` via `to_string`/`println`/`hash` — confirmed by hand that
`to_string({x: 1, y: 2})` prints `{ x: 1, y: 2 }` interpreted but `#<tag:0>`
compiled (the same `to_string`-on-container class already in
`specs/todos.md`'s P1 and `test/test_oracle.ml`'s `known_divergence` list),
and that `hash({x: 1, y: 2})` differs across backends entirely by design
(`specs/todos.md`, "Compiled and interpreted `hash()` use different,
backend-specific algorithms ... for RECORD types") — every golden program
here prints only extracted `Int` FIELD VALUES (via `int_to_string`), never a
record value itself. (2) no golden program generates the missing-field
`ERecordUpdate` shape (the divergence adjudicated in §4.2.1) — all four
programs update only fields already present in the base's shape.

**A real divergence found and routed around, not hidden:** while drafting
`g10`, `float_to_string` on a *whole-number* `Float` (e.g. `1.0`) printed
`1.` interpreted (OCaml's `string_of_float`, `eval.ml:2891`) but `1` compiled
(the C runtime's `march_float_to_string` uses `snprintf("%g", f)`,
`runtime/march_runtime.c:349`–`353`, which drops a bare `.0`). This is a
genuine, pre-existing bug in the *compiled* `float_to_string` builtin — outside
this task's scope (§0's fragment excludes "floats beyond their appearance in
the value grammar") and outside the δ-rules being added here (`float_to_string`
is an observation primitive, not a core primitive) — so `g10`'s Float
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
local variable — a compiled-backend codegen bug, not an interpreter bug). A
*flat* (non-nested) `PatTuple` in a `let` compiles and runs correctly
(confirmed: `let (a, b) = t` compiles, links, and matches interpreted output —
this is exactly `g14`), and a *nested* `PatTuple` used as a **`match`** branch
pattern (rather than a block `let`) also compiles and runs correctly
(confirmed — this is `g16` as committed). So the bug's precise trigger is
`nested PatTuple` × `ELet` specifically, not `PatTuple` or `nesting` or `ELet`
in isolation. This is outside this task's scope (documenting the interpreter
faithfully, not fixing the compiler) and is a **new** divergence, not the
already-filed whole-tuple-`Show` bug (`specs/todos.md`, "Tuples have no `Show`
impl") — `g16` was rewritten to destructure the nested tuple in a `match`
instead of a `let` specifically to route around it while still exercising
nested tuple construction and componentwise matching. Flagged here for
separate triage; not filed as a `specs/todos.md` entry by this task (spec-only
scope) but should be by a follow-up.

**A third divergence — this one ADJUDICATED and CONVERGED by this task, not
merely routed around:** `{ base with f: v }` where `f` is absent from
`base`'s actual (runtime) shape used to diverge — the interpreter silently
fabricated the field, the compiled backend panicked (§4.2.1 has the full
adjudication). This shape is **deliberately excluded from the golden
corpus**: per §0's fragment scope and this task's brief, a golden entry must
be a `MATCH` on the SAME observable output, but this divergence's *resolved*
form is "both sides now reject the program with a nonzero exit" — the
committed `verify.sh` harness (like the `@oracle` sweep) classifies any
nonzero interpreter exit as an automatic `INTERP FAIL`, so a program that is
supposed to error on both sides can never register as a golden `MATCH`
regardless of backend agreement (the same harness limitation §4.4.1 notes
for the strict-`&&`/`||` crashing witness). Instead, the convergence is
pinned by a dedicated unit test,
`test/test_properties.ml`'s
`test_record_update_missing_field_on_erased_base_converged`, which asserts
BOTH backends now exit nonzero (non-signal) with a "no field" message for
`{ record_from_list([("a", 1)]) with z: 99 }`. Also note that this
divergence was **only ever reachable through an erased base** —
`record_from_list`/`record_put` results, whose static type is an
unconstrained type variable (§4.2.1) — because a statically-typed record
literal base makes an unknown-field update a **typecheck-time** error on
both backends (`typecheck.ml:3869`–`3875`) before either backend's runtime
`ERecordUpdate` path ever executes; none of `g17`–`g20` needed to route
around this, since none of them update through an erased base.

**A known, already-filed divergence encountered again while drafting `g22`,
reached through a second path — routed around, not hidden.** `println` on a
bare atom value (e.g. `println(:ok)`) is a known, filed compiler bug: it
interprets fine (`VAtom` prints as `:ok`, exit 0) but fails to **compile** —
the linker rejects the emitted object with `Undefined symbols … "_show" …
_println$Atom`, i.e. `Atom` has no compiled `_show` implementation (this bug
is being fixed in a separate session, tracked as chip `task_6bee4d07`, and is
explicitly out of this task's scope per its brief's guardrail). Confirmed by
hand before drafting `g22`: `println(:ok)` prints `:ok` interpreted (exit 0)
but fails to link compiled with exactly that `_show`/`Atom` error. The FIRST
draft of `g22` did not print a bare atom directly, but hit the *same* bug via
a second, less obvious path: `match result do :error(msg) -> println(msg) …
end` — printing `msg`, a `String` value bound out of a payload atom's
`PatAtom` match — **also** failed to link with the identical `_show`/`Atom`
error. The root cause traces back to the typechecker, not the pattern-match
mechanics: `EAtom`'s inferred type is unconditionally `t_atom` regardless of
payload (`typecheck.ml:4045`–`4047`, `ignore (infer_expr env a)` on each
argument — the argument's own inferred type is discarded, only used for its
unification side effects), and `PatAtom`'s inferred pattern type mirrors this
(`typecheck.ml:2661`–`2664`: the OVERALL pattern type is `t_atom`, while each
sub-pattern — e.g. `msg` — gets its own type from a fresh, otherwise
unconstrained `infer_pattern` call). Nothing unifies `msg`'s type to a
concrete `String`, so it stays an erased type variable at the print site —
the same "erased base" situation §4.2.1 already documents for
`record_from_list`'s return type — and `println` on an erased-type value
falls through to the generic/dynamic show path, which needs a per-type
`_show`, and `Atom`'s is the missing one. This is **the same filed bug**
reached by a second route (an atom payload's erased binding type), not a new
divergence: `g22` was rewritten to route the payload through `describe(msg) =
"error: " ++ msg` first — `++`'s `VString`-restricted δ-rule (δ-Concat, §4.4)
forces `msg`'s type to unify concretely with `String`, so the `println` call
prints a genuine `VString` rather than an erased-type value, sidestepping the
bug while still exercising the intended semantics (atom construction with a
payload, `PatAtom` matching with binding) end to end.

Run the check: `dune build bin/main.exe && specs/lang/golden/verify.sh`
(the committed harness diffs both outputs per program and exits nonzero on any
mismatch). These programs are exactly the shape the `@oracle` conformance sweep
(`test/test_oracle.ml`) already runs, so folding `specs/lang/golden/` into that
sweep's corpus — so the anchor runs in CI, not just on demand — is the natural
next wiring (§6).

## 6. What Phase-1 validated, and the Phase-2/3 queue

**Phase-1 core: COMPLETE.** The seven widening slices (Tasks 1–7) plus this
consolidation (Task 8) cover every core `Ast.expr`/`pattern`/`literal`
constructor the interpreter runs and the desugarer leaves in the core
(cross-checked against `ast.ml:32–110`), minus the explicitly-deferred set
below. The record `ERecordUpdate`-missing-field divergence was adjudicated and
converged (§4.2.1). The golden corpus is 32/32 MATCH, 0 divergences (§5).

**Validated (the point of the exercise, now proven across the whole core):**

- The "core = desugared AST, `eval.ml` = reference" decision holds and is
  grounded in the real pipeline (§1).
- The four layers cohere: the grammar (§2), the desugaring map (§3), and the
  operational rules (§4) all describe one object, and the golden corpus (§5)
  agrees 33/33 across both independently-written backends.
- The doc format — grammar table, desugaring table, arm-cited big-step rules,
  golden table — proved a workable template, replicated cleanly across all
  seven slices and assembled here into one reference.

**Deferred — the Phase-2/3 queue (each group becomes a widening slice like the
Phase-1 tasks did):**

- strings as first-class data (beyond their appearance in the value grammar);
- `to_string`/`show` and the interface-dispatch machinery (the source of the
  known container-`to_string`/`hash`/atom-`_show` divergences §5 routes around);
- effects and IO ordering;
- actors;
- refinements;
- capabilities;
- the Perceus RC discipline (its own Level-3 track);
- session types;
- sigils.

(This is the same deferred set §0 now names. Everything that was on the ORIGINAL
v0 deferred line but is now *covered* — tuples (Task 2), records (Task 3), atoms
(Task 4), the full pattern language + guards + exhaustiveness (Task 5), local
recursive functions (Task 6), and conditionals (Task 7) — has been removed from
this queue; keep this list and §0's in lockstep as Phase-2/3 slices land.)

**Next steps (the Phase-1 closeout track):**

1. ~~Fold `specs/lang/golden/` into `test/test_oracle.ml`'s corpus~~ **DONE** —
   the `@oracle` sweep enumerates `specs/lang/golden/` alongside
   `bench/`+`examples/`, so the spec's golden anchor runs in CI, not only via the
   standalone `verify.sh`.
2. Make the reference **normative-by-cross-reference**: annotate each core
   `eval_expr` arm in `lib/eval/eval.ml` with its rule name and a pointer back
   to this document's §4 (the oracle-gated legibility refactor — the remaining
   Phase-1 code task).
3. Then open Phase 2 with the first deferred group above, as its own widening
   slice, following the same design-spec → plan → golden-anchored execution
   loop this core fragment proved out.
