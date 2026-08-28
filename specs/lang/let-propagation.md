> Part of the March Language Reference; see [specs/lang/index.md](index.md).

# `let?`: Result Propagation Binding

**Status:** Implemented, shipped, and **conformance-tested** (widening slice 8,
2026-07-10). `let? p = e` binds the `Ok` payload of a `Result`-typed `e` and
short-circuits, returning `Err(err)` immediately on the first `Err`. The RHS
must be a `Result`, the continuation must be a `Result` with the same error
type, and a `let?` cannot be the last expression in a block. The normative
rules are in `core-march-types.md` §2.10 (typing: `(T-LetQ)` + three
diagnostics) and `core-march.md` §4.13 (operational: `(E-LetQ-Ok)` /
`(E-LetQ-Err)` short-circuit), with corpus `types/{accept/t70–t72,
reject/t67–t70}` and golden `g42`. This chapter is the tutorial companion.

> **Implementation note: §4–§8 below read as a design/plan.** That material
> was written as the *implementation spec*. `let?` shipped exactly as its
> design describes: an `ELetQ` AST node typechecked natively (`typecheck.ml`
> `infer_expr`) and evaluated natively (`eval.ml`), with ONE deviation: the
> dedicated "`let?` cannot have a type annotation" parser production shown in
> §5.2 was never implemented. `let? x : T = e` is still correctly rejected,
> but by the generic missing-`=` recovery (`` I was expecting `=` in the let?
> binding here: ``), not a bespoke message. See `reject/t70` and the slice-8
> finding in `specs/todos/`.

**Depends on:** the `Result` type, the `QUESTION` token, `EMatch`, and as-pattern / tuple-pattern support (all present).

---

## 1. Motivation

March already has `with ... do ... else ... end` for multi-step Result chaining
(fully implemented). But there is a sharp, **verified** gap:

> **`with` without an `else` clause does not propagate; it crashes.**
>
> ```march
> with Ok(a) <- divide(10, 0) do Ok(a + 1) end
> ```
> desugars (via `build_with`) to `match divide(10,0) do Ok(a) -> Ok(a+1) end`
> with **no `Err` arm**. On an `Err` value this is a non-exhaustive match: the
> compiler emits a warning and the program **panics with `Match_failure` at
> runtime**. (Confirmed against the current compiler.)

So today the *only* way to propagate errors is the verbose explicit form:

```march
with
  Ok(content) <- File.read(path),
  Ok(json)    <- Json.parse(content)
do
  Ok(json)
else
  Err(e) -> Err(e)          -- this arm is mandatory or you get a runtime crash
end
```

`let?` is sugar for exactly this common case (bind the `Ok` payload, propagate
`Err` upward), fitting March's let-chain block style. (The stdlib module is
`Json`, not `JSON`; `Json.get` returns `Option`, not `Result`, so it needs
`Option.to_result` per §9.4 below. Also note: a real, verified compiler bug,
not a `let?`-specific one: `File.read`'s builtin type signature registers its
error type as an unconstrained type variable rather than the concrete
`File.FileError` it actually produces at runtime, so `let? content =
File.read(path)` inside a function declared to return `Result(_, String)`
**typechecks with no error** and then panics at runtime: `++`ing the bound
error value fails with `builtin ++: expected two strings`, because the value
is actually a `FileError` constructor, not a `String`. `Result.map_err`
converts it explicitly, which also happens to route around the bug):

```march
fn load_config(path : String) : Result(Config, String) do
  let? content = Result.map_err(File.read(path), fn _e -> "could not read config file")
  let? json    = Json.parse(content)
  let? hostval = Option.to_result(Json.get(json, "host"), "missing host field")
  match hostval do
    JsonValue.Str(host) -> Ok({ host: host, port: 8080 })
    _                   -> Err("host is not a string")
  end
end
```

**`let?` is strictly more than a bare `with`:** it always inserts the
`Err(e) -> Err(e)` passthrough arm, so the generated match is exhaustive by
construction and can never `Match_failure`. This is a safety win, not just a
brevity win.

`let?` and `with...else` are complementary:

| Situation | Use |
|---|---|
| Linear chain, one error type, propagate all failures | `let?` |
| Per-step handling, recovery from specific errors | `with...else` |
| Steps with different error types | `with...else` + explicit arms, or `Result.map_err` before each `let?` |

---

## 2. Prior art

| Language | Mechanism | Note |
|---|---|---|
| Rust | postfix `?` | Composes with method chains; `From` coercion |
| F# / OCaml | `let!` / `let*` (computation expressions) | Closest to March's block style |
| Haskell | do-notation `<-` | General monad; heavier conceptual load |
| Elixir | `with ... <-` | Already adopted as March's `with` |
| Gleam | `use x <- f(cb)` | Zero new syntax; needs callback-last APIs |

`let?` follows the F#/OCaml `let!` shape because it slots into the existing
block model with no new conceptual apparatus.

---

## 3. Surface syntax

```
let? <simple_pattern> = <expr>
```

- The `?` immediately follows `let` (lexed as `LET` then `QUESTION`; **no new
  token**; see §5.1).
- The pattern is a `simple_pattern`, identical to what plain `let` accepts.
- **No type annotation** is permitted: `let? x : T = e` is a parse error. The
  bound type is read off the `Result(T, E)`; the user never writes it.

### 3.1 What patterns are actually allowed

`simple_pattern` (parser.mly:1111) accepts **only**:

- `_` (wildcard), lowercase variable names (incl. soft keywords)
- integer / float / string / bool literals (and negative numeric literals)
- parenthesised patterns `( p )`
- tuple patterns `(a, b, …)`
- list-literal patterns `[]`, `[a, b, …]`

It does **not** accept record patterns or constructor patterns. Therefore:

```march
let? (a, b) = f()        -- OK (tuple)
let? x      = f()        -- OK (var)
let? _      = f()        -- OK (wildcard, but see §9.6)
let? { host } = f()      -- PARSE ERROR — record patterns not in simple_pattern
let? Some(v)  = f()      -- PARSE ERROR — constructor patterns not in simple_pattern
```

This is the *same* restriction plain `let` already has; it is not new behaviour,
and it keeps the bound pattern irrefutable (the `Ok` arm cannot fail to match).

---

## 4. AST

Add to `lib/ast/ast.ml`, in the `expr` type, after `ELet`:

```ocaml
| ELetQ of pattern * expr * expr * span
    (** let? p = result in body
        - pattern: irrefutable simple_pattern binding the Ok payload
        - first expr: the Result-typed scrutinee
        - second expr: the continuation (rest of the block)
        - Typechecked NATIVELY (see §6); lowered to EMatch at eval/TIR (§7). *)
```

**Design choice: continuation-carrying, not a flat marker.** `ELetQ` stores the
*rest of the block* as its third field. This is what lets the typechecker reason
about `let?` natively (and produce good errors) instead of seeing an already-
lowered `match`. The right-nesting is assembled in the parser (§5.2).

---

## 5. Parser

### 5.1 No new token; `LET QUESTION` is unambiguous

`QUESTION` already exists (parser.mly:150) and is used for holes (`?ident` and
bare `?`, parser.mly:1012–1014). After `LET`, the grammar currently only permits
a `simple_pattern`, and `simple_pattern` can never begin with `QUESTION`. So
shifting `QUESTION` right after `LET` is conflict-free and selects the `let?`
rule. No lexer change.

### 5.2 Building the continuation: fold in `block_body`

`block_expr` is a flat list element; `block_body` is `nonempty_list(block_expr)`.
To avoid LR conflicts (a right-recursive `block_body` rule would clash with
`nonempty_list(block_expr)` because both begin with `LET`), we parse `let?`
**flatly** and fold the list right-associatively in the semantic action.

Add to `block_expr` (parser.mly, near the existing `LET` case). The body field is
a placeholder that the fold **always** overwrites:

```ocaml
(* let? p = e — placeholder body, replaced by the block_body fold *)
| LET; QUESTION; p = simple_pattern; EQUALS; e = expr
    { ELetQ (p, e, EBlock ([], mk_span ($loc)), mk_span ($loc)) }

(* error recovery: missing `=` *)
| LET; QUESTION; _p = simple_pattern; error
    { error_raise
        "I was expecting `=` in the let? binding here:"
        (Some "let? name = result_expr")
        $startpos($4) }

(* error recovery: type annotation not allowed on let? *)
| LET; QUESTION; _p = simple_pattern; COLON; error
    { error_raise
        "`let?` bindings cannot have a type annotation — the type is inferred from the Result:"
        (Some "let? name = result_expr")
        $startpos($4) }
```

Rewrite the `block_body` action to fold (parser header section, near
`build_with`):

```ocaml
(** Fold a flat block-expr list, threading each `let?` continuation into its
    body field. Raises if a `let?` is the final expression (nothing to return
    on Ok). Non-let? prefixes are preserved as a sequencing EBlock. *)
let rec fold_letq es sp =
  match es with
  | [] -> EBlock ([], sp)                 (* parser guarantees nonempty *)
  | [ ELetQ (_, _, _, lsp) ] ->
      error_raise
        "`let?` cannot be the last expression in a block — there's nothing to return on success:"
        (Some "let? x = result_expr\n    Ok(x)")
        lsp.start_line  (* see note: pass the let? span's start position *)
  | [ e ] -> e
  | ELetQ (p, result, _, lsp) :: rest ->
      ELetQ (p, result, fold_letq rest sp, lsp)
  | e :: rest ->
      (match fold_letq rest sp with
       | EBlock (inner, bsp) -> EBlock (e :: inner, bsp)
       | other               -> EBlock ([e; other], sp))
```

```ocaml
block_body:
  | es = nonempty_list(block_expr)
    { fold_letq es (mk_span ($loc)) }
```

> Note on `error_raise`'s span argument: match the calling convention used by the
> other `error_raise` sites in parser.mly (they pass a `$startpos(...)` /
> position). Thread the `let?` token's start position through rather than the
> `.start_line` field shown above; the snippet is illustrative.

### 5.3 Lambda bodies

`lambda_body = lambda_stmts; e = expr`, and `lambda_stmts` is right-recursive
already. The cleanest reuse is to apply the same fold over `stmts @ [e]` in the
`lambda_body` action, plus a `let?` case in `lambda_stmts` that produces the same
placeholder `ELetQ`:

```ocaml
| LET; QUESTION; p = simple_pattern; EQUALS; ev = expr; rest = lambda_stmts
    { ELetQ (p, ev, EBlock ([], mk_span ($loc)), mk_span ($loc)) :: rest }
```

```ocaml
lambda_body:
  | stmts = lambda_stmts; e = expr
    { fold_letq (stmts @ [e]) (mk_span ($loc)) }
```

Because `lambda_body` always ends in a real `expr`, a trailing `let?` is
impossible by construction in a lambda; the "let? as last" error can only arise in
`block_body`.

---

## 6. Typechecking (native: this is where safety + good errors live)

`ELetQ` is typechecked directly by `lib/typecheck/typecheck.ml` in both
`infer_expr` and `check_expr`. **It is not desugared before typechecking.** This
is the intentional change from the first draft of this spec: the whole point of a
distinct node is that the typechecker can speak about `let?` with precision.

Let `ELetQ (p, result, body, sp)` and let the enclosing expected return type be
`Result(R, E)` (in checking mode) or a fresh `Result(R, E)` to be unified (in
synthesis mode).

### 6.1 Checking mode: `check_expr env (ELetQ ...) expected`

This is the common case: a function body checked against its declared return
type. Here `expected` **is** the function's return type, which gives the best
errors.

1. Require `expected = Result(R, E)` for some `R`, `E`.
   - If `expected` is not a `Result(_, _)`, emit **E-LETQ-RET** (§6.4).
2. Synthesise `t_result = infer_expr env result`. Require `t_result = Result(T, E')`.
   - If `t_result` is not a `Result(_, _)`, emit **E-LETQ-RHS**.
3. Unify `E' = E`. On failure emit **E-LETQ-ERRTY** (the propagated error type
   does not match the function's error type).
4. Bind the variables of `p` at type `T` (irrefutable, like `let`), giving `env'`.
5. `check_expr env' body expected`: the continuation must also yield `Result(R, E)`.
6. Result type of the whole `ELetQ` is `expected`.

### 6.2 Synthesis mode: `infer_expr env (ELetQ ...)`

Used when there is no annotation to push down (e.g. a `let?` inside a lambda
with a result type still being inferred).

1. `t_result = infer_expr env result`; require `t_result = Result(T, E)`
   (fresh `T`, `E` if it is a metavariable resolved to `Result`); else **E-LETQ-RHS**.
2. Bind `p : T` → `env'`.
3. `t_body = infer_expr env' body`; require `t_body = Result(R, E)`; unify the
   error component with `E`; on mismatch **E-LETQ-ERRTY**, on non-Result body
   **E-LETQ-BODY** ("the expression after `let?` must itself be a `Result`").
4. Synthesised type: `Result(R, E)`.

### 6.3 Error-type coherence across a chain

Because each `let?` in a function unifies its `E` with the function's `E`, a
chain of `let?` is automatically committed to a single error type. The
typechecker can therefore report the *second* mismatching binding against the
*first* fixed type:

> `let?` bindings in `load_config` propagate `String` errors (fixed at line 3),
> but `Json.parse` here returns `Result(_, ParseError)`. Convert with
> `Result.map_err(Json.parse(content), fn e -> parse_err_to_string(e))`, or
> handle it with `with ... else`.

(Illustrative diagnostic text; the real stdlib `Json.parse`'s error type is
plain `String`, not a distinct `ParseError`; the sample message just shows the
diagnostic's shape for a truly mismatched error type.)

Implementation: track the first-resolved `E` and its span in the local
environment while checking a function body (a small field threaded through the
function-body checker, or recovered from the function's declared return type when
present).

### 6.4 New diagnostics (`lib/errors/errors.ml`)

| Code | Trigger | Message |
|---|---|---|
| **E-LETQ-RET** | enclosing fn return type is not `Result` | `` `let?` can only be used where the result is a `Result`. This function returns `{ty}`. Change the return type to `Result(_, _)`, or use `let` / `match` instead. `` |
| **E-LETQ-RHS** | RHS is not `Result` | `` `let?` needs a `Result` on the right-hand side, but this expression has type `{ty}`. Use plain `let` for non-Result values. `` |
| **E-LETQ-ERRTY** | error types differ | `` This `let?` propagates `{e_here}`, but the surrounding code propagates `{e_expected}`. All `let?` in one function share one error type — convert with `Result.map_err`, or use `with ... else`. `` |
| **E-LETQ-BODY** | continuation is not `Result` | `` The code after `let?` must also produce a `Result` (so errors can flow through). This produces `{ty}`. `` |
| **E-LETQ-LAST** | `let?` is the final block expr | (raised in the parser, §5.2) `` `let?` cannot be the last expression — there's nothing to return on success. Add e.g. `Ok(value)` after it. `` |

All carry `sp` (the `let?` span) so the caret points at `let?`, not at the
desugared internals.

---

## 7. Lowering (eval + TIR)

Typechecking is native; **execution** lowers `ELetQ` to a match. There is no
post-typecheck rewrite pass in March's pipeline (eval consumes the same AST), so
each backend handles `ELetQ` directly. Both lowerings are tiny.

### 7.1 Interpreter (`lib/eval/eval.ml`)

Add a case to `eval_expr_inner`:

```ocaml
| ELetQ (p, result, body, _) ->
  (match eval_expr env result with
   | VCon ("Ok", [v]) ->
     let env' = bind_pattern env p v in   (* irrefutable; reuse let's binder *)
     eval_expr env' body
   | (VCon ("Err", _)) as err -> err      (* propagate the SAME value — free *)
   | other ->
     (* type system guarantees this is unreachable; defensive *)
     runtime_type_error "let? expected a Result value" other)
```

**Why returning `err` directly is correct and free:** runtime values are
type-erased `VCon(tag, payload)`. The `Err` value is *representationally
identical* whether typed `Result(T, E)` or `Result(R, E)`; only the (erased)
Ok-type parameter differs. So no reconstruction, no allocation, no copy.

### 7.2 Compiled path (`lib/tir/lower.ml`)

TIR is typed, so the lowering must produce a well-typed match. Lower
`ELetQ (p, result, body, sp)` to:

```
match result do
  Ok(p)   -> body
  Err($e) -> Err($e)
end
```

where `$e` is a fresh name. **The `Err($e) -> Err($e)` reconstruction is
mandatory here for typing reasons** (see §8.2): the bound `$e : E`, and rewrapping
with `Err` produces `Result(R, E)` (because `Err : E -> Result(α, E)` is
polymorphic in `α`), which is what the surrounding context demands. After TIR's
own erasure/representation selection, this rewrap compiles to a tag-and-pointer
that Perceus can do in place (§8.3), so it is free at runtime too.

Reuse the existing `Ok`/`Err` constructor lowering and the existing match
compiler; no new TIR node.

### 7.3 `EBlock` handling note

The parser fold (§5.2) already nests `let?` continuations, so by the time eval
and TIR see an `EBlock`, any `let?` is an `ELetQ` node *containing* its
continuation; it is **not** a loose statement in the block list. This mirrors how
`ELetFn` is special-cased in `lower.ml:388`, but `ELetQ` needs no block-level
special case at all because the continuation is already inside the node.

---

## 8. Compiler specifics: typing subtleties

### 8.1 Irrefutability

`p` comes from `simple_pattern`, so it is irrefutable (var/wildcard/tuple/literal/
list, and literals in binding position are already rejected by the existing
let-binding checks the same way). The `Ok(p)` arm therefore cannot fail to match,
and the only other reachable constructor is `Err`, so the generated match is
exhaustive, unlike a bare `with`.

### 8.2 Why `Err(e) -> Err(e)` must reconstruct (not pass through)

A tempting "optimisation" is to bind the whole value and return it:

```
match result do  Ok(p) -> body  | (Err(_) as whole) -> whole  end
```

**This is ill-typed.** `result : Result(T, E)`, so `whole : Result(T, E)`. But
the match must yield `Result(R, E)` (the continuation's type), and in general
`T ≠ R`. There is no subtyping in March, so `whole` cannot be returned where
`Result(R, E)` is expected. Rewrapping `Err(e)` works exactly because the
`Err` constructor is polymorphic in the Ok-type parameter: `Err(e) : Result(α, E)`
unifies `α := R`. So reconstruction is a **soundness requirement of the source
type system**, not a stylistic choice.

(At the *value* level the distinction vanishes (see §7.1), so the interpreter is
free to short-circuit with the original value. Only the typed TIR form must
reconstruct.)

### 8.3 Allocation cost

The TIR `Err($e) -> Err($e)` rewrap allocates a fresh `Err` cell only nominally.
When the scrutinee's refcount is 1 (the overwhelmingly common case for a value
produced by the immediately preceding call), Perceus reuses the cell in place:
same tag, same payload slot, no allocation. The interpreter never allocates at
all (§7.1).

---

## 9. Interactions & scoping

### 9.1 `let?` vs `with` (now corrected)

```march
-- These two are equivalent:

let? x = f()
let? y = g(x)
Ok(x + y)

with Ok(x) <- f(), Ok(y) <- g(x) do
  Ok(x + y)
else
  Err(e) -> Err(e)         -- REQUIRED; a bare `with` (no else) would crash on Err
end
```

A `with` *without* `else` is **not** equivalent; it is non-exhaustive and
panics on `Err`. `let?` always has the passthrough.

### 9.2 Free mixing with `let`, `match`, `with`

(As in §1, a literal `File.read(path)` here would hit the same `file_read`
error-type compiler bug and needs a `Result.map_err` wrapper to be truly
type-safe; omitted here to keep the scoping example focused.)

```march
fn process(path : String) : Result(Report, String) do
  let? content = File.read(path)                 -- propagate
  let lines    = String.split(content, "\n")     -- infallible
  let? data    = parse_lines(lines)              -- propagate
  match List.length(data) do
    0 -> Err("empty file")
    n -> Ok({ data: data, count: n })
  end
end
```

### 9.3 `let?` inside a lambda propagates from the lambda

`let?` propagates to the nearest enclosing function **or lambda** with a result
that is a `Result`. It does not jump to the outer function.

```march
fn process_all(paths : List(String)) : Result(List(Config), String) do
  let per_path = fn path ->
    let? content = File.read(path)     -- returns Err from THIS lambda
    let? cfg     = parse(content)
    Ok(cfg)
  end
  Result.collect(List.map(paths, per_path))   -- List(Result(..)) -> Result(List(..))
end
```

The lambda is inferred (§6.2) to have type `String -> Result(Config, String)`.

### 9.4 Option is out of scope

`let?` is `Result`-only. Convert first:

```march
let? user = Option.to_result(Map.get(users, id), "user not found")
```

A future `let??` for `Option` is noted in §12 but not specified here.

### 9.5 Not valid at module top level

`let?` is block-scoped. A module-level `let?` is a syntax error (it is only
produced inside `block_body` / `lambda_body`). Consistent with `with`.

### 9.6 `let? _ = e`: discarding the Ok value

Legal and useful: run a fallible effect for its error, ignore its success value,
continue.

```march
let? _ = validate(input)     -- propagate validation error, ignore the () payload
Ok(input)
```

The lint in §10.4 should *not* warn here (the discard is intentional via `_`),
unlike `let _ = fallible()` which silently drops a `Result`.

---

## 10. What the compiler can now tell the user

Because `let?` is a first-class typed node, these become precise and reliable.

### 10.1 "You bound a Result with plain `let`" (type error → actionable hint)

When `let x = f()` binds a `Result` and `x` is later used as the inner type, the
mismatch message can now suggest the fix by name:

> `f()` returns `Result(_, _)`. You bound it with `let`, so `x` is the whole
> `Result`. Did you mean `let? x = f()` (propagate the error) or
> `match f() do Ok(x) -> … Err(e) -> … end` (handle it)?

### 10.2 Discarded-Result lint

`let _ = fallible()` (a `Result` thrown away) warns:

> This `Result` is discarded. Use `let? _ = …` to propagate the error, or handle
> it explicitly.

(See §9.6: `let? _ = …` itself is fine and silent.)

### 10.3 Error-type coherence (§6.3)

Mismatched error types in a `let?` chain are reported at the offending binding
against the first fixed error type, with a `Result.map_err` suggestion, far
better than a bare unification failure deep in a desugared match.

### 10.4 `match` → `let?` simplification hint (lint, LSP code action)

When `lib/lint/lint.ml` sees exactly:

```march
match e do
  Ok(p)  -> <continuation>
  Err(x) -> Err(x)
end
```

with a pure passthrough `Err` arm and `e : Result`, emit a hint "this can be
written `let? p = e`" and offer an LSP code action to rewrite it.

### 10.5 Better bare-`with` message

When a `with` without `else` is non-exhaustive (the trap in §1), the
exhaustiveness warning can now cross-reference the feature:

> This `with` has no `else`, so an `Err` value will crash at runtime. Add an
> `else Err(e) -> Err(e)` arm, or use `let?` for plain propagation.

---

## 11. Optimisations

1. **`let?` chain → shared error exit.** A run of nested `ELetQ` lowers to nested
   matches that all branch to an `Err` return. A TIR/LLVM pass can merge these
   into one shared error-exit block (a φ of the propagated `Err` values) instead
   of N nested diamonds. Future; the naive nesting is already correct. Tag:
   `TODO(opt): let? chain error-exit merge`.
2. **In-place `Err` rewrap.** Already free under Perceus when refcount = 1 (§8.3).
   No new work.
3. **Tail position.** When the final continuation is in tail position, both the
   `Ok` and the `Err` paths are in tail position: no frame growth on the error
   path.
4. **No monomorphisation impact.** `ELetQ` lowers to an ordinary match before/at
   TIR; mono sees only matches.

---

## 12. Out of scope (V1)

- **`Option` support**: convert with `Option.to_result`. (`let??` reserved.)
- **Error coercion**: no `From`-style auto-conversion; error types must unify.
- **Postfix `?`**: `f()?` on arbitrary expressions; different parse story.
- **Type annotations on `let?`**: rejected (§3, §5.2).
- **`let?` at module top level**: block-scoped only.

---

## 13. Pipeline impact / touch list

Adding a surface `expr` constructor touches every pass that traverses
expressions. **Critical:** most of these passes have wildcard `| _ ->` arms
(lint: 25, LSP analysis: 162, refactor: 16, format: 11), so **OCaml's
exhaustiveness checker will NOT flag a missing `ELetQ` case**; the failure mode
is silent mishandling, not a build error. Each must be audited explicitly.

| File | Has catch-all? | Required action |
|---|---|---|
| `lib/ast/ast.ml` | none | Define `ELetQ`. |
| `lib/parser/parser.mly` | none | Produce `ELetQ`; `fold_letq`; error recovery (§5). |
| `lib/typecheck/typecheck.ml` | (exhaustive; will fail to build until handled) | Native `infer_expr` + `check_expr` rules (§6). **Primary correctness + safety.** |
| `lib/eval/eval.ml` | (exhaustive) | `eval_expr_inner` case (§7.1). **Required for run.** |
| `lib/tir/lower.ml` | (exhaustive) | Lower to match (§7.2). **Required for compile.** |
| `lib/desugar/desugar.ml` | per-constructor recursion | **Must recurse** into `result` and `body`: `ELetQ (p, desugar_expr r, desugar_expr b, sp)`. Missing this silently skips pipe/sugar desugaring inside `let?`. |
| `lib/ast/span_remap.ml` | 1 catch-all | **Must recurse** into both subexprs, or REPL/incremental span remapping breaks for any code containing `let?`. Silent if forgotten. |
| `lib/format/format.ml` | 11 catch-alls | **Must handle**: `forge format` runs on the surface AST; without a case it will mis-format or drop `let?`. Print `let? p = e` then the body. Round-trip test required (§14.7). |
| `lib/dump/dump.ml` | 2 catch-alls | Add a printable form for `--dump-phases` / AST debugging. |
| `lib/lint/lint.ml` | 25 catch-alls | Recurse into subexprs; optionally add §10.4 hint. |
| `lib/refactor/refactor.ml` | 16 catch-alls | Recurse into subexprs so rename/extract work inside `let?`. |
| `lib/coverage/coverage.ml` | 1 catch-all | Count the `result` and `body` as coverable. |
| `lsp/lib/analysis.ml` | 162 catch-alls | Recurse for hover/goto/completion inside `let?` bodies (UX, not correctness). |
| `lsp/lib/workspace.ml`, `lsp/lib/depot.ml` | none | Audit for expr traversal; recurse as needed. |

Recommended guard: a single shared `map_expr` / `fold_expr` traversal would have
made most of these automatic. Since the codebase hand-rolls traversals, each must
be checked by hand; grep `EMatch` across `lib/` and `lsp/` to find them all
(this list was produced that way).

---

## 14. Test plan

Tests: `test/test_eval.ml` (parse + interpret), `test/test_compiler.ml`
(compiled), plus a formatter round-trip test. Add a `"let? propagation"` section
to each.

### 14.1 Parser
- [ ] `let? x = Ok(1)` then `x` parses to `ELetQ(PatVar, …, …)`.
- [ ] `let? (a, b) = f()`: tuple pattern OK.
- [ ] `let? _ = f()`: wildcard OK.
- [ ] `let? x : Int = f()`: parse error (no annotation), good message.
- [ ] `let? x` (missing `=`): parse error, good message.
- [ ] `let? { host } = f()`: parse error (record pattern not in simple_pattern).
- [ ] `let? x = f()` as the **last** block expr: `E-LETQ-LAST` parse error.
- [ ] Nesting: `let?` continuation correctly captures all following statements
      (inspect that `body` field contains the rest).

### 14.2 Eval: happy path
- [ ] `let? x = Ok(42)  ; Ok(x)` → `Ok(42)`.
- [ ] chain all-Ok: `let? a = Ok(1); let? b = Ok(2); Ok(a+b)` → `Ok(3)`.
- [ ] tuple bind: `let? (x, y) = Ok((3, 4)); Ok(x+y)` → `Ok(7)`.
- [ ] `let?` after a plain `let`, and before a `match`: mixed chain.

### 14.3 Eval: propagation
- [ ] first step `Err`: returns that `Err` unchanged (identity on the value).
- [ ] **short-circuit**: a later step with an observable side effect is **not**
      evaluated when an earlier step is `Err` (use a ref/counter).
- [ ] propagated `Err` payload matches the original to the exact byte.
- [ ] `let?` inside a lambda propagates from the lambda; `Result.collect`
      composes (the §9.3 example).

### 14.4 Exhaustiveness / safety
- [ ] A `let?` chain over a function that can `Err` **never** raises
      `Match_failure` (contrast: the bare-`with` crash in §1; keep a regression
      test that the bare `with` still warns, to lock in the distinction).

### 14.5 Compiled (`test_compiler.ml`)
- [ ] compiled `let?` chain output == interpreted output.
- [ ] compiled propagation returns correct `Err`.
- [ ] compiled `let?`-in-lambda + `Result.collect`.

### 14.6 Type errors (negative: assert exact diagnostic code/message)
- [ ] RHS not Result (`let? x = 42`) → **E-LETQ-RHS**.
- [ ] heterogeneous error types → **E-LETQ-ERRTY**, reported at the 2nd binding,
      mentions the first error type and `Result.map_err`.
- [ ] enclosing fn returns non-Result → **E-LETQ-RET**, caret on `let?`.
- [ ] continuation not a Result → **E-LETQ-BODY**.

### 14.7 Formatter round-trip
- [ ] `forge format` on a file using `let?` preserves `let?` verbatim (does not
      rewrite it to `match`/`with`, does not drop it). This guards the §13
      formatter requirement.

### 14.8 LSP / lint (lighter)
- [ ] hover on a variable bound by `let?` resolves its type.
- [ ] the §10.4 `match` → `let?` hint fires on the canonical passthrough shape and
      does **not** fire when the `Err` arm is non-trivial.

---

## 15. Implementation order

1. `lib/ast/ast.ml`: add `ELetQ`.
2. `lib/parser/parser.mly`: `block_expr` / `lambda_stmts` cases, `fold_letq`,
   `block_body` / `lambda_body` actions, error recovery.
3. `lib/desugar/desugar.ml`: structural recursion into `ELetQ` subexprs.
4. `lib/typecheck/typecheck.ml`: native `infer_expr` + `check_expr` rules; new
   diagnostics in `lib/errors/errors.ml`.
5. `lib/eval/eval.ml`: `eval_expr_inner` case.
6. `lib/tir/lower.ml`: lower to match.
7. Traversal passes: `span_remap.ml`, `format.ml`, `dump.ml`, `lint.ml`,
   `refactor.ml`, `coverage.ml`, `lsp/lib/*.ml`: add real cases (do **not** rely
   on their catch-alls; see §13).
8. Tests (§14).
9. Docs: `CLAUDE.md`, `surface-syntax.md`, `docs/tour.md` (§16).

Steps 1–6 are the functional core and can land together (the build will fail
until typecheck/eval/tir are handled; those have no catch-all). Step 7 is the
"silent breakage" tail and must not be skipped. Steps 8–9 follow.

After landing: `git mv` the item's file from `specs/todos/` to `specs/progress/`
(or file a new dated entry there), per repo policy.

---

## 16. Documentation changes

### `CLAUDE.md` (surface-syntax notes, near the lambda section)

> ### `let?`: Result propagation
> `let? p = expr` binds the `Ok` value and returns the `Err` immediately.
> RHS must be `Result(T, E)`; the enclosing function must return `Result(_, E)`
> with the same `E`. For per-step handling use `with … else …`. `let?` cannot be
> the last expression in a block.

### `surface-syntax.md` (new "Result propagation" section)

Show the `let?` chain and the `with … else` alternative side by side, and call
out that a `with` **without** `else` crashes on `Err`.

### `docs/tour.md`

Present `let?` and `with…else` as the two error-handling patterns, with the
"when to use which" table from §1.
