# Core March — Walking Skeleton (v0)

**Date:** 2026-07-04
**Status:** Walking skeleton — the FIRST vertical slice of the March language
specification. Not the whole core; a deliberately tiny fragment taken end-to-end
to validate the methodology before scaling.
**Depends on:** `specs/2026-07-04-language-specification-roadmap-design.md`
(this is that roadmap's Phase-1, §9 first artifact).

---

## 0. What this is (and is not)

This document specifies a **small fragment** of March — `let`, lambda +
application, `Int`/`Bool` with `+` and `==`, a two-constructor ADT with `match`,
and `if` — across the *entire* spec stack:

1. the **core grammar** (§2),
2. the **surface → core desugaring map** (§3),
3. the **operational semantics** (§4), and
4. a **golden conformance corpus** verified interpreter-vs-compiled (§5).

Its purpose is to prove the *method* — that a normative spec can be extracted
faithfully from the existing implementation and kept honest by the differential
oracle — cheaply, before committing to the full Phase-1 plan. It is a walking
skeleton: thin but end-to-end. **It is not** a complete semantics; everything
outside the fragment (records, tuples, strings as first-class data, effects/IO
ordering, actors, refinements, capabilities, the RC discipline, floats beyond
their appearance in the value grammar) is explicitly **deferred** — see §6.

Every rule below is grounded in a specific line of the implementation. Where a
rule says "faithful to `eval.ml:N`", that citation *is* the correctness
argument, and the golden corpus (§5) is its executable check.

## 1. The core is the desugared AST; `eval.ml` is its reference semantics

**Decision (locked for the whole spec effort):** *Core March* is the AST as it
exists **after the desugar pass**, and the tree-walking interpreter
(`lib/eval/eval.ml`) is its **reference operational semantics**.

This is grounded, not invented. The compiler pipeline is
parse → desugar → typecheck → eval (`bin/main.ml:772`–`807`): the interpreter's
entry point `eval_module_env (m : module_)` (`eval.ml:8397`) consumes exactly
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
             |  EBlock [e…]                                 -- do … end sequence
             |  ELet (p = e)                                -- block-scoped binding
             |  EMatch e [ p when g? -> e … ]               -- pattern match
             |  EIf e e e                                   -- if c do … else … end
                                                            (ast.ml:51–91)

pattern  p  ::= PatWild | PatVar x | PatLit ℓ | PatCon C [p…]   (ast.ml:40–48)

value    v  ::= VInt n | VFloat f | VString s | VBool b | VAtom a
                                                            (eval.ml:32–37)
             |  VClosure ρ [x…] e                           -- closure: env + params + body
             |  VCon C [v…]                                 -- constructor value: tag + payload
             |  VBuiltin name f                             -- primitive (e.g. +, ==)
```

`LitFloat`/`VFloat` carry an OCaml `float` (IEEE-754 double); `LitString`/
`VString` carry an OCaml `string`; `LitAtom`/`VAtom` carry a `string` naming
the atom (surface `:ok`, `:error`, … — an interned-looking but here just
string-valued tag distinct from a 0-ary constructor value `VCon`). All three
are produced by the parser as direct literal tokens — `FLOAT`, `STRING`,
`ATOM` (`parser.mly:1198`–`1199`, `:1213`) — with **no desugaring**, exactly
like `LitInt`/`LitBool` (§3's `ELit` row).

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
| `f(e…)` (`EApp`) | identity, plus a qualified-`ECon` fold for `Mod.Ctor(args)` | `desugar.ml:552–563` |
| `C(e…)` (`ECon`) | identity (recurse args) | `desugar.ml:565–566` |
| `match e do … end` (`EMatch`) | identity (recurse scrutinee, guards, bodies) | `desugar.ml:595–600` |
| `if c do a else b end` (`EIf`) | **identity** — `EIf` is *not* rewritten to a match on the bool | `desugar.ml:635–636` |
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

(E-App-Clo) ρ ⊢ e_f ⇓ VClosure ρ' [x₁…x_k] e_b    ρ ⊢ eᵢ ⇓ vᵢ
            |x…| = |e…| = k    (x₁↦v₁,…,x_k↦v_k, ρ') ⊢ e_b ⇓ v     eval.ml:6957, 6889
            ─────────────────────────────────────────────────────
            ρ ⊢ EApp e_f [e₁…e_k] ⇓ v
            -- arity mismatch ⇒ eval_error (eval.ml:6892)

(E-App-Prim) ρ ⊢ e_f ⇓ VBuiltin _ f   ρ ⊢ eᵢ ⇓ vᵢ                 eval.ml:6889 (VBuiltin arm)
            ─────────────────────────────────────
            ρ ⊢ EApp e_f [e₁…e_k] ⇓ f [v₁…v_k]

(E-If-T)    ρ ⊢ e_c ⇓ VBool true    ρ ⊢ e_t ⇓ v                   eval.ml:7073
            ────────────────────────────────────
            ρ ⊢ EIf e_c e_t e_e ⇓ v

(E-If-F)    ρ ⊢ e_c ⇓ VBool false   ρ ⊢ e_e ⇓ v                   eval.ml:7079
            ────────────────────────────────────
            ρ ⊢ EIf e_c e_t e_e ⇓ v
            -- a non-Bool condition ⇒ eval_error "if condition must be a boolean" (eval.ml:7082)

(E-Match)   ρ ⊢ e_s ⇓ v    selectᵨ(v, branches) = v'              eval.ml:6998, 7303
            ──────────────────────────────────────
            ρ ⊢ EMatch e_s branches ⇓ v'
```

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

(E-Blk-Seq)   ρ ⊢ e ⇓ _    ρ ⊢ EBlock rest ⇓ v    (e not an ELet, rest ≠ [])
              ──────────────────────────────────
              ρ ⊢ EBlock (e :: rest) ⇓ v
```

(A bare `ELet` evaluated *outside* a block just evaluates its RHS and drops the
binding — `eval.ml:6993` — because binding is only meaningful relative to a
continuation, which the block supplies.)

### 4.3 Branch selection and pattern matching

`selectᵨ(v, branches)` tries branches **top-to-bottom, first match wins**; on a
match it evaluates the body in the pattern-extended environment (after an
optional boolean guard); if no branch matches it raises `Match_failure`
(`eval.ml:7303`):

```
select selection, in order:
  branch (p when g -> e_b):
     match(p, v) = σ   and   ( g absent, or  σ·ρ ⊢ g ⇓ VBool true )
        ⇒  result is  σ·ρ ⊢ e_b ⇓ v'
     otherwise ⇒ try next branch
  no branch matches ⇒ raise Match_failure          (eval.ml:7307)
```

The matching relation `match(p, v) = σ | ⊥` returns bindings σ or failure
(`eval.ml:771`):

```
match(PatWild, v)               = ∅                            eval.ml:773
match(PatVar x, v)              = { x ↦ v }                    eval.ml:775
match(PatLit ℓ, v)             = ∅    if 𝓋(ℓ) = v, else ⊥     eval.ml:777–782
match(PatCon C [p…], VCon C' [v…]) = ⋃ match(pᵢ, vᵢ)          eval.ml:784
        provided  bare(C) = C'  and  |p…| = |v…|,  else ⊥
match(PatCon …, non-VCon)       = ⊥                            eval.ml:795
```

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
apparatus (contexts + the substitution-vs-environment reconciliation) is Phase-1
work, not skeleton work — but note it is a *refinement* of §4.2, not a different
semantics.

### 4.6 Faithfulness (the honest caveat)

The §4.2–4.4 rules were transcribed arm-for-arm from `eval.ml` at the cited
lines. That transcription is **human-reviewed, not mechanically verified** —
this is the roadmap's §7 faithfulness risk made concrete. What *is* mechanically
checked is weaker but real: the golden corpus (§5) confirms that, on these
programs, the interpreter these rules describe and the independently-written
compiled backend produce identical output. A divergence there would mean either
the interpreter or the compiler is wrong; agreement plus arm-for-arm review is
the skeleton's correctness evidence. Scaling from "these 8 programs" to
"the fragment" is what the golden corpus grows to cover.

## 5. Golden conformance corpus

Thirteen programs in `specs/lang/golden/`, each exercising a slice of the
fragment, each verified to produce **identical output interpreted and
compiled** (`march f.march` vs `march --compile f.march -o b && b`). This is
the executable anchor for §4. `g01`–`g08` are the walking-skeleton's original
corpus (`+`, `==`, lambdas, ADTs, match); `g09`–`g13` are Task 1's addition,
covering the remaining literals and the full primitive δ-rule table:

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

**Result: 13 / 13 matched, 0 divergences.** (These print via `println` /
`int_to_string` / `float_to_string` / `bool_to_string` — *observation
primitives* used to make the result observable; they are outside the pure
reduction fragment and are treated here only as opaque output functions, not
specified by §4.)

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

Run the check: `dune build bin/main.exe && specs/lang/golden/verify.sh`
(the committed harness diffs both outputs per program and exits nonzero on any
mismatch). These programs are exactly the shape the `@oracle` conformance sweep
(`test/test_oracle.ml`) already runs, so folding `specs/lang/golden/` into that
sweep's corpus — so the anchor runs in CI, not just on demand — is the natural
next wiring (§6).

## 6. What the skeleton validated, and what's next

**Validated (the point of the exercise):**

- The "core = desugared AST, `eval.ml` = reference" decision holds and is
  grounded in the real pipeline (§1).
- The four layers cohere: the grammar (§2), the desugaring map (§3), and the
  operational rules (§4) all describe one object, and the golden corpus (§5)
  agrees 8/8 across both backends.
- The doc format — grammar table, desugaring table, arm-cited big-step rules,
  golden table — is a workable template to replicate per fragment.

**Deferred (the widening queue — each becomes a slice like this one):**
records/tuples/strings as data; `if`-less boolean `match`/`ECond`; local
recursive functions (`ELetFn`, already visible in `eval_block`); `to_string`/
`show` and the interface-dispatch machinery; effects/IO ordering; actors;
refinements; capabilities; the Perceus RC discipline (its own Level-3 track).

**Next steps:**

1. ~~Fold `specs/lang/golden/` into `test/test_oracle.ml`'s corpus~~ **DONE** —
   the `@oracle` sweep now enumerates `specs/lang/golden/` alongside
   `bench/`+`examples/` (all 8 golden programs MATCH; sweep 22 MATCH / 0
   un-triaged, exit 0), so the spec's golden anchor runs in CI, not only via the
   standalone `verify.sh`.
2. If this skeleton reads well, write the **Phase-1 implementation plan**
   (design-spec → plan → subagent execution, as the oracle used) to widen the
   fragment across the full desugared-AST core, and land the `eval.ml` core-loop
   refactor gated by the `@oracle` sweep (roadmap §4.2).
