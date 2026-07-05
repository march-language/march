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
literal  ℓ  ::= LitInt n | LitBool b                       (ast.ml:32)

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

value    v  ::= VInt n | VBool b                            (eval.ml:32)
             |  VClosure ρ [x…] e                           -- closure: env + params + body
             |  VCon C [v…]                                 -- constructor value: tag + payload
             |  VBuiltin name f                             -- primitive (e.g. +, ==)
```

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
(E-Lit)     ─────────────────────                                  eval.ml:6945
            ρ ⊢ ELit ℓ ⇓ 𝓋(ℓ)                    where 𝓋(LitInt n)=VInt n, 𝓋(LitBool b)=VBool b

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

`bare(C)` strips a leading module qualifier (`eval.ml:786`); the constructor
value's tag is stored already-stripped (`eval.ml:6981`), which is why
`match(PatCon "Som" …, VCon "Som" …)` succeeds regardless of qualification.

### 4.4 Primitive δ-rules (`+`, `==`)

`+` is `arith_num (+)` (`eval.ml:850, 2762`); `==` is `cmp_op (=)`
(`eval.ml:876, 2805`). Restricted to the fragment's `Int`/`Bool`:

```
(δ-Add)   f₊ [VInt a; VInt b]  = VInt (a + b)                  eval.ml:851
(δ-EqI)   f₌ [VInt a; VInt b]  = VBool (a = b)                 eval.ml:877
(δ-EqB)   f₌ [VBool a; VBool b] = VBool (a = b)                eval.ml:880
```

`+` on two `Int`s and `==` on two `Int`s or two `Bool`s are total. (`==` on
other types dispatches to an `Eq` impl or OCaml structural equality —
`eval.ml:881`–`895` — which is outside this fragment and is exactly the kind of
under-specified corner the roadmap's divergence-adjudication track handles: the
`==`-on-`Newtype` bug the oracle found lived there.)

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

Nine programs in `specs/lang/golden/`, each exercising a slice of the fragment,
each verified to produce **identical output interpreted and compiled** (`march
f.march` vs `march --compile f.march -o b && b`). This is the executable anchor
for §4.

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
| `g09_float_show.march` | whole-number `Float` display via `float_to_string` (observation primitive; pins the cross-backend format) | `1.` / `42.` / `100.` / `0.` / `-3.` / `1.5` |

**Result: 9 / 9 matched, 0 divergences.** (These print via `println` /
`int_to_string` / `bool_to_string` / `float_to_string` — *observation
primitives* used to make the result observable; they are outside the pure
reduction fragment and are treated here only as opaque output functions, not
specified by §4. `g09` does not lift the float deferral of §0/§6 — it pins only
the *display* of the `float_to_string` primitive so the four backends agree that
a whole-number `Float` prints OCaml-style `1.`, matching the `eval.ml`
`string_of_float` reference; float arithmetic and ordering remain deferred.)

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
  agrees 9/9 across both backends.
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
