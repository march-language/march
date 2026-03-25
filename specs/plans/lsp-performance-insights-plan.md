# March LSP — Performance Insights

**Status:** Draft
**Date:** 2026-03-25
**Companion plans:** `lsp-code-actions-plan.md`, `lsp-enhancements-plan.md`

---

## Executive Summary

The March compiler's optimization pipeline already knows exactly what your code will cost at
runtime — which recursive calls will run without growing the stack, which values will be
updated in place vs copied, which function calls go direct vs through a pointer, which
values live on the stack vs the heap, and which messages will cross actor boundaries with
zero copying vs a deep copy. None of that knowledge currently reaches the programmer.

This plan defines **Performance Insights**: a set of LSP diagnostics, inlay hints, and
hover annotations that surface the compiler's performance knowledge in plain English —
like Elm's compiler messages, not Haskell's academic jargon. A programmer who has never
heard of Perceus, FBIP, or escape analysis should be able to read these messages, understand
what they mean, and know exactly what to change.

The goal is not to overwhelm programmers with diagnostics. Performance insights are
**opt-in hints and info-level messages** by default, not warnings. They appear when the
compiler observes a pattern that is likely to surprise the programmer — a recursive function
that looks like it should optimize but doesn't, a value that looks cheap to share but will
be copied, an allocation that moves onto the stack automatically. The tone throughout is
collaborative: "here's what March is doing, and here's how to take advantage of it."

---

## 1. Design Philosophy: Elm-Style Messaging

Every message in this system must pass three tests:

### Test 1: No compiler internals

The message must make no reference to compiler passes, internal data structures, or
optimization names. Programmers write code, not compiler IR.

**Forbidden words and phrases** (never appear in user-facing text):
- RC, reference count, reference counting, EIncRC, EDecRC
- FBIP, Perceus, escape analysis, TIR, ANF, defunctionalization
- Atomic CAS, memory fence, happens-before
- Closure capture set, free variables, lambda lifting
- Borrow inference, linearity annotation, affine type
- "insert dec_rc", "reuse token", "last-use transfer"

### Test 2: Specific and actionable

Every message must say what to change. "This might be slow" is not a message.
"Move the `+ 1` into an accumulator parameter to avoid growing the stack" is a message.

### Test 3: Plain English

The message must make sense to a working programmer who knows functions, values, loops,
and memory — but not type theory. Use "this value is copied" not "this value requires
a deep clone due to non-unique ownership at the send site."

### Tone model: Elm compiler

Elm's error messages are the gold standard for compiler communication. They:
- State the problem in one sentence
- Show the code location precisely
- Explain *why* it's a problem in plain terms
- Give a concrete suggestion

March performance insights follow this model exactly.

---

## 2. Compiler Infrastructure Available

Before describing each insight, here is a map of what the existing compiler already
knows and where that knowledge lives. This determines implementation complexity.

### 2.1 AST / Type-checker level (available in LSP today)

The LSP runs `parse → desugar → typecheck` on every save. The `Analysis.t` record gives:

| Data | Location | Notes |
|------|----------|-------|
| Type of every expression | `type_map : (span, Tc.ty) Hashtbl.t` | Includes linearity via `TLin` |
| Linear/affine consumption records | `consumption : consumption list` | Tracks def + all use-site spans |
| Actor definitions | `actors : (string * actor_def) list` | Actor name, message type, handlers |
| In-scope variables + schemes | `vars : (string * Tc.scheme) list` | |
| All call sites with args | `call_sites : call_site list` | fn name + arg spans |

The typechecker produces `TLin(lin, ty)` for linear/affine-annotated types. The LSP
already uses this for the "make linear" code action. We can use the same information
to detect when a non-linear value is sent to an actor and will be deep-copied.

**Recursion detection at AST level**: The desugar pass already groups multi-head function
definitions. We can detect self-recursion by walking the body of a function and checking
whether any call targets the function's own name.

**Tail position detection at AST level**: Walking the desugared AST, we can determine
whether a recursive call is in tail position — specifically, whether there are any
pending operations after the call returns. The critical cases:
- `f x + 1` — call is not in tail position (arithmetic follows)
- `1 + f x` — not in tail position
- `if cond then f x else g x` — both branches are in tail position
- `match v with | A -> f x | B -> g y` — both arms in tail position
- `let _ = f x` (not last expr) — not in tail position

### 2.2 TIR level (requires extending the LSP pipeline)

The TIR optimization passes run after typecheck in the compiler but are **not currently
run by the LSP**. To surface TIR-level insights, the LSP must optionally run:

```
parse → desugar → typecheck → lower → mono → defun → known_call → perceus → escape
```

This is a heavier pipeline. Two options:

**Option A — Incremental TIR (recommended for P1/P2 work)**: Run TIR lowering
asynchronously on save, cache the result alongside `Analysis.t`. The TIR pipeline
completes in tens of milliseconds for typical files; it does not block hover or completions.

**Option B — AST heuristics (sufficient for many insights)**: For several categories,
the TIR result can be approximated with high accuracy from the typed AST alone, without
running TIR. This is described per-category below.

### 2.3 TIR node vocabulary

| TIR node | What it means |
|----------|--------------|
| `EApp(f, args)` | Direct (known) function call — fast |
| `ECallPtr(closure, args)` | Indirect call through closure — one pointer load overhead |
| `EAlloc(ty, args)` | Heap allocation |
| `EStackAlloc(ty, args)` | Stack allocation — inserted by escape analysis, zero-cost |
| `EReuse(token, ty, args)` | In-place memory reuse — inserted by Perceus/FBIP, zero allocation |
| `EFree(v)` | Explicit deallocation of a linear/affine value |
| `EIncRC(v)` | Non-atomic ref count increment — local values only |
| `EDecRC(v)` | Non-atomic ref count decrement — local values only |
| `EAtomicIncRC(v)` | Atomic ref count increment — for actor-sent values |
| `EAtomicDecRC(v)` | Atomic ref count decrement — for actor-sent values |

The presence of `EStackAlloc` means escape analysis promoted that value. The presence
of `EReuse` means Perceus detected a reuse opportunity. The presence of `EAtomicIncRC`/
`EAtomicDecRC` means a value crosses an actor boundary and requires cross-thread
synchronization.

---

## 3. Insight Categories

### 3.1 Tail Call Optimization

#### What the compiler knows

The LLVM emitter (`lib/tir/llvm_emit.ml`) implements TCO by converting self-tail-recursive
functions into a loop with a `tco_loop_label` branch. Mutual TCO is handled by Tarjan SCC
detection in the mutual TCO pass. The key state is `tco_fn_name : string option` in the
emitter context — when set, a self-recursive `EApp` to the function's own name generates
a branch back to the loop header instead of a call instruction.

TCO fires only when the recursive call is in **strict tail position**: the call is the
last operation before the function returns, with no pending arithmetic, field access,
constructor wrapping, or other operation.

#### Example: non-tail-recursive (warning)

```march
fn sum(xs: List(Int)) -> Int =
  match xs with
  | [] -> 0
  | [x, ..rest] -> x + sum(rest)   -- ← THIS CALL
  end
```

The `sum(rest)` call is not in tail position because `x + _` is still pending. For a
list with 100,000 elements, this grows the stack 100,000 frames deep.

**Diagnostic message (Warning, on the `sum(rest)` call):**
> This recursive call isn't optimized because `x + ...` happens after it returns, which
> grows the stack by one frame for each list element.
>
> Rewrite using an accumulator parameter so the addition happens before the recursive call:
>
> ```march
> fn sum(xs: List(Int), acc: Int) -> Int =
>   match xs with
>   | [] -> acc
>   | [x, ..rest] -> sum(rest, acc + x)
>   end
> ```

#### Example: tail-recursive (hint)

```march
fn sum(xs: List(Int), acc: Int) -> Int =
  match xs with
  | [] -> acc
  | [x, ..rest] -> sum(rest, acc + x)   -- ← optimized
  end
```

**Inlay hint (on function signature, not inline):**
> ✓ tail-recursive

Or as a hover annotation on the recursive call: "This call is in tail position — March
compiles it as a loop with no stack growth."

#### Example: accumulator pattern exists but is unused

```march
fn length(xs: List(a)) -> Int =
  match xs with
  | [] -> 0
  | [_, ..rest] -> 1 + length(rest)   -- ← grows stack
  end
```

**Diagnostic message:**
> This recursive call grows the stack once per list element. Move the `+ 1` before
> the recursive call using an accumulator:
>
> ```march
> fn length(xs: List(a), acc: Int) -> Int =
>   match xs with
>   | [] -> acc
>   | [_, ..rest] -> length(rest, acc + 1)
>   end
> ```

#### Severity: Warning
#### Display: Inline diagnostic on the non-tail-call expression
#### Implementation complexity: Low — pure AST pattern matching
#### Dependencies: None (works with current LSP `parse → typecheck` pipeline)

**Implementation approach**: Walk the desugared AST for each function. Track whether each
sub-expression is in tail position (passed down as a boolean context). When a recursive
self-call appears in a non-tail position with a known "wrapping" operation (arithmetic,
constructor application, tuple creation, string concat), emit the diagnostic with specific
text about what operation is blocking TCO.

---

### 3.2 Memory Reuse Opportunities

#### What the compiler knows

The Perceus pass (`lib/tir/perceus.ml`) detects when a value's reference count reaches
zero at a point where a new value of the same shape is being constructed. At that point
it emits `EReuse` instead of `EAlloc`, allowing the runtime to reuse the old memory
in-place. This only fires when the old value is **uniquely owned** — used in exactly
one place so the compiler can prove no other reference exists.

When a value is used in two places, an `EIncRC` is emitted to track the second reference.
This prevents reuse. The opportunity for the programmer: if they can restructure to use
the value in one place only (e.g., by consuming it in a transformation), reuse becomes
possible.

#### Example: reuse blocked (hint)

```march
fn double_tree(t: Tree(Int)) -> Tree(Int) =
  match t with
  | Leaf(n) -> Leaf(n * 2)
  | Node(l, r) ->
      let l2 = double_tree(l)
      let r2 = double_tree(r)
      Node(l2, r2)
  end
```

Here, if `t` is uniquely held, `Node(l2, r2)` can reuse `t`'s memory. The compiler
handles this automatically. No insight needed.

But consider:

```march
fn process(t: Tree(Int)) -> (Tree(Int), Int) =
  let transformed = double_tree(t)
  let original_root = root_value(t)   -- ← t used here too
  (transformed, original_root)
```

Because `t` is used twice (in `double_tree` and `root_value`), the transform cannot
run in-place.

**Diagnostic message (Hint, on the second use of `t`):**
> `t` is used in two places, so each transformation allocates a new copy. If you can
> extract `original_root` before passing `t` to `double_tree`, the transform can update
> `t` in place:
>
> ```march
> fn process(t: Tree(Int)) -> (Tree(Int), Int) =
>   let original_root = root_value(t)
>   let transformed = double_tree(t)
>   (transformed, original_root)
> ```

#### Severity: Hint (informational)
#### Display: Inline hint on the "extra" use site; hover on the variable name
#### Implementation complexity: Medium
#### Dependencies: Requires TIR Perceus output (Option A: async TIR pipeline) or use-count analysis on typed AST (Option B: count uses via `refs_map`)

**AST approximation (Option B)**: The LSP already builds `refs_map : (string, span list)
Hashtbl.t`. If a variable bound to a value of a heap type (any `TCon`) appears more than
once in `refs_map`, that is a candidate for this hint. The heuristic is not perfect (it
may fire when reuse wasn't possible anyway) but is useful and requires no TIR.

---

### 3.3 Actor Message Copying

#### What the compiler knows

The Perceus pass (`lib/tir/perceus.ml`) collects all variables passed as the message
argument to `send()` calls via `collect_actor_sent_vars`. For those variables, it emits
`EAtomicIncRC`/`EAtomicDecRC` instead of the local non-atomic variants. Atomic RC
operations cost more than local ones because they require a memory fence.

More importantly, when a **non-linear** value is sent to an actor, the runtime **deep
copies** the message into the receiving actor's heap. This is by design (actors share
nothing), but it surprises programmers who expect message passing to be cheap.

When a value is **linear**, sending it is a zero-copy ownership transfer — the sender
loses its reference, the receiver gains it. No copying occurs.

#### Example: copied message (warning)

```march
fn send_data(worker: Pid(WorkerMsg), items: List(Item)) =
  send(worker, Process(items))   -- ← items is List(Item), not linear
```

`items` is a regular (unrestricted) list. Sending it copies the entire list into the
worker's mailbox.

**Diagnostic message (Warning, on the `send(...)` call):**
> `items` will be deep-copied when sent. For large values, this can be expensive.
>
> If you don't need `items` after this point, declare it `linear` so March can transfer
> ownership instead of copying:
>
> ```march
> fn send_data(worker: Pid(WorkerMsg), items: linear List(Item)) =
>   send(worker, Process(items))   -- zero-copy transfer
> ```

#### Example: linear send (hint)

```march
fn forward(next: Pid(Msg), data: linear Bytes) =
  send(next, Data(data))   -- ← zero-copy
```

**Hover text on the `send(...)` call:**
> This message is transferred without copying because `data` is linear. March moves
> ownership to the receiving actor — no allocation occurs.

#### Severity: Warning (for large/complex types); Hint (for scalars and small types)
#### Display: Diagnostic on `send()` call; hover on the message argument
#### Implementation complexity: Low — the LSP already tracks actor definitions and linearity via `TLin`. Detecting `send()` calls is a simple AST walk.
#### Dependencies: Typechecker linearity information (already available in `Analysis.t` via `Tc.TLin`)

**Detection**: Walk the AST for calls to `send`. Check the type of the message argument
in `type_map`. If the type is not `TLin(Lin, _)` or `TLin(Aff, _)`, the message will
be copied. Emit the warning if the type is complex (a `TCon`, a record, a list — not an
`Int`, `Bool`, `Float`, or `Unit`).

---

### 3.4 Direct vs Indirect Function Calls

#### What the compiler knows

The known-call pass (`lib/tir/known_call.ml`) converts `ECallPtr` (indirect call through
a closure function pointer) to `EApp` (direct call) when the closure allocation is visible
in scope. After defunctionalization, all closures are struct allocations with a function
pointer as their first field. An `ECallPtr` requires loading that pointer and jumping
through it. An `EApp` is a direct branch — zero indirection.

From a programmer perspective: calling a function by name is always direct. Calling a
function stored in a variable, returned from another function, or captured from an outer
scope *may* be indirect.

#### Example: indirect call (hint)

```march
fn apply_twice(f: Int -> Int, x: Int) -> Int =
  f(f(x))   -- ← f is a closure parameter: indirect call
```

**Inlay hint (on the call site):**
> indirect call

**Hover text:**
> `f` is a function passed as a parameter, so March calls it through a function pointer.
> If you inline the call or specialize this function for a specific `f`, March can call
> it directly.

#### Example: known-call optimization fires (positive hint)

```march
let transform = fn x -> x * 2
List.map(transform, items)   -- ← known call: transform is visible in scope
```

**Hover text on `transform` argument:**
> March can see that `transform` is defined right here, so this calls it directly
> without going through a pointer.

#### Severity: Hint (informational)
#### Display: Inlay hints on call sites; hover text on the callee argument
#### Implementation complexity: Medium — requires TIR known_call pass output, or an approximation: if the callee in a call expression is a variable bound to a lambda in the same scope, it's likely a known call.
#### Dependencies: Option A (TIR pipeline) for precision; AST approximation adequate for most cases

---

### 3.5 Allocation Hotspots

#### What the compiler knows

Any `EAlloc` in the TIR is a heap allocation. When an `EAlloc` appears inside a recursive
function body (i.e., inside a loop), it runs on every iteration. The TIR can identify
these by walking function bodies looking for `EAlloc` nodes that are not dominated by
a fixed-iteration bound.

At the AST level: a value construction (constructor application, list literal, record
literal) inside a recursive function arm is a candidate.

#### Example: allocation in loop (warning)

```march
fn build_prefixes(s: String, acc: List(String)) -> List(String) =
  match string_length(s) with
  | 0 -> acc
  | n ->
      let prefix = string_slice(s, 0, n)   -- ← allocates on every recursion
      build_prefixes(string_slice(s, 0, n - 1), [prefix, ..acc])
  end
```

**Diagnostic message (Warning, on the `string_slice` call in the recursive arm):**
> This creates a new string on every recursive call. If the goal is to collect all
> prefixes, consider building the list from the outside in so each prefix is a
> slice of the original string — or use `List.map` on a pre-built index list to
> separate the slicing from the recursion.

#### Example: allocation hoisting opportunity (hint)

```march
fn repeat_format(n: Int, template: String) -> List(String) =
  match n with
  | 0 -> []
  | k ->
      let result = format_string(template, k)   -- template parse is re-done each time
      [result, ..repeat_format(n - 1, template)]
  end
```

**Diagnostic message (Hint):**
> `template` is parsed on every call. If `format_string` compiles the template
> internally, consider pre-compiling it outside the loop and passing the compiled
> form in.

#### Severity: Warning (clear allocation in every recursion); Hint (possible opportunity)
#### Display: Inline diagnostic on the allocating expression
#### Implementation complexity: Medium — requires identifying which expressions are inside a recursive function body and which are "fixed" vs "varying"
#### Dependencies: Recursion detection (from inline.ml pattern: `calls_self name`); AST walk

---

### 3.6 Stack vs Heap Allocation

#### What the compiler knows

The escape analysis pass (`lib/tir/escape.ml`) promotes `EAlloc` nodes to `EStackAlloc`
when a value's lifetime is provably bounded to the current function's stack frame. Stack
allocation is effectively free — the frame pointer adjustment handles it with zero runtime
overhead. Heap allocation costs: an allocator call, a reference count initialization,
and a future decrement.

This is a **positive insight** — when the compiler automatically promotes a value to the
stack, the programmer should know this happened. It validates their code structure.

#### Example: stack-promoted value (positive hint)

```march
fn clamp(x: Int, lo: Int, hi: Int) -> Range =
  let r = Range { lo = lo, hi = hi }   -- this never escapes clamp()
  if x < r.lo then r.lo
  else if x > r.hi then r.hi
  else x
```

**Inlay hint (on the `Range { ... }` expression):**
> stack-allocated

**Hover text:**
> `r` stays local to this function, so March allocates it on the stack — no heap
> involvement, no memory management cost.

#### Example: value escapes (informational)

```march
fn make_range(lo: Int, hi: Int) -> Range =
  Range { lo = lo, hi = hi }   -- returned: escapes to caller
```

**Hover text:**
> `Range { lo, hi }` is returned from this function, so it's allocated on the heap.
> That's fine — the caller will own it and clean it up automatically.

No diagnostic is emitted for heap allocation in the common case. This avoids noise.
A diagnostic fires only when the programmer has done something that *prevents* promotion
that would otherwise occur — like taking the value's address, storing it in a global, or
capturing it in a closure.

#### Severity: Hint (informational, positive)
#### Display: Inlay hints on allocation expressions; hover text
#### Implementation complexity: High — requires running the escape analysis pass, which in turn requires the full TIR pipeline
#### Dependencies: Option A (async TIR pipeline with escape.ml output)

---

### 3.7 Closure Allocation

#### What the compiler knows

After defunctionalization (`lib/tir/defun.ml`), each lambda becomes a closure struct
heap allocation (`EAlloc(TCon("$Clo_...", _), ...)`) with one field per captured variable.
If the known-call pass fires, the allocation may still happen but the *call* becomes
direct. If escape analysis fires, the closure struct may be stack-promoted.

From the programmer's perspective: a lambda that captures many variables creates a larger
heap object and a longer copy if it is ever sent to an actor.

#### Example: large capture set (hint)

```march
fn make_handler(config: Config, db: Db, logger: Logger, metrics: Metrics) =
  fn request -> handle(config, db, logger, metrics, request)
```

**Diagnostic message (Hint, on the lambda):**
> This function captures 4 values. If you pass it to another actor or store it in a
> data structure, those 4 values travel with it. Consider grouping them into a single
> record to make the capture explicit and the size predictable.

#### Severity: Hint
#### Display: Hover on lambda; inlay hint showing capture count for lambdas with ≥3 captures
#### Implementation complexity: Low — at AST level, count free variables in the lambda body vs the lambda's own parameters
#### Dependencies: Free variable analysis on typed AST (no TIR required)

---

## 4. Priority Tiers

### P1 — Implement Now (AST-level, no new infrastructure)

| Insight | Basis | Complexity |
|---------|-------|-----------|
| 3.1 Tail call optimization — non-tail detection | AST walk, recursion detection, tail position tracking | Low |
| 3.3 Actor message copying — non-linear send warning | `type_map` linearity check + `send()` call detection | Low |
| 3.7 Closure allocation — large capture set hint | AST free variable count | Low |

These three insights require only what the LSP already runs: `parse → desugar → typecheck`.
No new pipeline stages. No new infrastructure beyond a new analysis pass over the typed AST.
They can be implemented as a new `perf_insights` function in `analysis.ml` returning
`perf_insight list` alongside the existing `diagnostics`.

### P2 — Implement with AST heuristics (good approximation, no TIR needed)

| Insight | Basis | Complexity |
|---------|-------|-----------|
| 3.2 Memory reuse opportunities | `refs_map` use-count heuristic | Medium |
| 3.4 Direct vs indirect calls — indirect hint | Check if callee is a function parameter or lambda | Medium |
| 3.5 Allocation hotspots — allocation in recursion | Recursion detection + constructor-in-recursive-arm | Medium |

These can be approximated with moderate accuracy from the typed AST. False positives
are acceptable at the Hint severity level.

### P3 — Implement with async TIR pipeline

| Insight | Basis | Complexity |
|---------|-------|-----------|
| 3.6 Stack vs heap — stack promotion hints | Requires `escape.ml` output | High |
| 3.4 Direct vs indirect calls — precise | Requires `known_call.ml` output | High |
| 3.2 Memory reuse — precise | Requires `perceus.ml` EReuse vs EAlloc output | High |

P3 insights require extending the LSP to run the TIR pipeline asynchronously. The
architecture for this: after `Analysis.t` is computed, queue a `Tir_analysis.t` job
on a background fiber. When complete, merge the TIR-level insights into the document
state and push a `textDocument/publishDiagnostics` notification with the additional hints.
The TIR analysis is non-blocking — completions, hover, and go-to-definition work
immediately from `Analysis.t` while TIR results follow asynchronously.

---

## 5. How Insights Are Displayed

### 5.1 Inline diagnostics (`textDocument/publishDiagnostics`)

Used for: TCO warnings, actor copy warnings, allocation hotspot warnings.

Severity mapping:
- `Warning` — something that will surprise the programmer and likely hurts performance
  (non-tail recursive call on a large-data function, sending a large non-linear value)
- `Information` — something worth knowing, not necessarily a problem
  (stack-allocated value, direct call confirmed)
- `Hint` — subtle optimization opportunity the programmer can choose to act on
  (reuse opportunity, large closure capture)

Diagnostic `code` field: use a namespaced string like `"perf:tco_blocked"`,
`"perf:actor_copy"`, `"perf:alloc_in_loop"` — consistent with the existing diagnostic
code scheme in `analysis.ml`.

### 5.2 Inlay hints (`textDocument/inlayHint`)

Used for: marking tail-recursive calls as `✓ tail`, stack-allocated expressions as
`stack`, indirect calls as `indirect`.

Inlay hints should be **disabled by default** and enabled by a client-side setting:
`"march.inlayHints.performanceAnnotations": true`.

Implementation: add a new `perf_inlay_hints` function in `analysis.ml` returning
`inlay_hint list`. Wire it into the existing `on_req_inlay_hints` handler in `server.ml`
guarded by a capability flag in the server config.

### 5.3 Hover annotations (`textDocument/hover`)

Used for: explaining optimizations that are already firing (positive) and opportunities
(constructive). Hover text appears when the programmer asks "what's going on here?"

Implementation: extend the existing `on_req_hover` handler in `server.ml`. When the
cursor is on a call expression, a `send()` call, or a lambda, include a performance
section in the hover Markdown after the type information.

Format:
```markdown
**Type:** `List(Int) → Int`

---

**Performance:** This recursive call is in tail position. March compiles this function
as a loop — it uses constant stack space regardless of list length.
```

### 5.4 Code lenses (`textDocument/codeLens`)

Used for: per-function summary annotations above function definitions.

Example code lens text (appears above a function header in the editor):
- `⚡ tail-recursive` — confirms TCO is active
- `⚠ 3 allocations per call` — warns about allocation in hot path
- `📦 stack-allocated result` — confirms escape-promoted return value

Code lenses are **disabled by default**. Enable via `"march.codeLens.performance": true`.

Implementation: add an `on_req_code_lens` handler. The `linol` library has typed support
for code lenses via `config_code_lens_provider`. Collect per-function insights during the
analysis pass and group by function definition span.

---

## 6. New Analysis Data Required

To support P1/P2 insights, `Analysis.t` needs two new fields:

```ocaml
type perf_insight = {
  pi_span     : Ast.span;
  pi_kind     : perf_kind;
  pi_severity : [ `Warning | `Information | `Hint ];
  pi_message  : string;
  pi_suggestion : string option;  (* code suggestion, if any *)
}

and perf_kind =
  | TcoBlocked of { blocking_op: string }   (* "x + ..." blocks TCO *)
  | TcoConfirmed                            (* this call is in tail position *)
  | ActorCopy of { value_name: string; ty_name: string }
  | ActorTransfer of { value_name: string } (* zero-copy linear send *)
  | ReuseOpportunity of { value_name: string; use_count: int }
  | IndirectCall of { callee: string }
  | AllocInLoop of { constructor: string }
  | LargeCapture of { count: int }
  | StackPromoted                           (* P3: escape analysis confirmed *)
```

Add `perf_insights : perf_insight list` to `Analysis.t`. The `analyze` function in
`analysis.ml` populates this by running a new `Perf_analysis.run` pass over the typed AST.

The existing `diagnostics` field is populated from type errors and linting. Performance
insights at `Warning` severity are also merged into `diagnostics` so they appear in the
editor's problem panel. Hints and Information insights are kept in `perf_insights` only,
surfaced via hover and inlay hints.

---

## 7. TCO Detection Implementation Notes

The tail position analysis works over `Ast.expr` after desugaring. The key recursive
function is:

```ocaml
(** [is_tail_call fn_name expr] returns true if [expr] is a tail-recursive
    call to [fn_name], false if it's a non-tail-recursive call. *)
val find_non_tail_recursive_calls : fn_name:string -> Ast.expr -> blocking_call list
```

Where a `blocking_call` records:
- The span of the recursive call
- The span and description of the "blocking operation" (the thing that runs after the call)

**Tail position rules**:

| Expression form | Is tail position? |
|----------------|-------------------|
| `fn_name(args...)` alone | Yes |
| `e1 + fn_name(...)` | No — arithmetic after |
| `fn_name(...) + e2` | No — arithmetic after |
| `constructor(fn_name(...))` | No — constructor wrap after |
| `if cond then fn_name(...) else e2` | Yes (then branch) |
| `if cond then e1 else fn_name(...)` | Yes (else branch) |
| `match x with | P -> fn_name(...) | ...` | Yes (each branch arm) |
| `let _ = fn_name(...)\n ...more exprs` | No — more exprs follow |
| `let x = fn_name(...)\n x` | Yes (last expr is just the binding) |

The implementation traverses the AST with a `in_tail_position:bool` flag, inverting it
when entering a non-tail context (arithmetic RHS, constructor arg, non-last block expr).

**Identifying blocking operations**: When a recursive call is found in non-tail position,
identify the immediate parent expression to generate a helpful message:
- Parent is `EBinop(op, _, call)` or `EBinop(op, call, _)` → message: "`{op}` runs after the call returns"
- Parent is `EApp(constructor, [...call...])` → message: "the `{constructor}(...)` constructor is applied after the call returns"
- Parent is block expression at non-last position → message: "the result is used before the function returns"

---

## 8. Actor Copy Detection Implementation Notes

Detecting actor message copies requires:

1. Walk the AST for calls to the `send` builtin: `EApp(EVar "send", [actor_arg; msg_arg])`
2. Look up `msg_arg`'s type in `type_map`
3. If the type is `Tc.TLin(Tc.Lin, _)` or `Tc.TLin(Tc.Aff, _)` → zero-copy transfer
4. Otherwise → deep copy. Determine if it's "complex" (non-scalar):
   - Scalar (no warning): `Int`, `Float`, `Bool`, `Unit`, `String` (immutable, cheap)
   - Complex (warning): `TCon(_, _)`, `TTuple _`, `TRecord _` — these are heap objects

For the warning, extract the variable name from `msg_arg` if it's `EVar name`, and
look up the type name from the `TCon` constructor for a human-readable message.

**Integration with actor type information**: The `actors` field in `Analysis.t` gives
each actor's declared message type. Cross-reference: if the message type matches the
actor's declared type exactly, the copy is unavoidable without changing the actor contract.
If the message type is a subterm (e.g., wrapping a large value in a tiny constructor),
suggest extracting the large value as a linear field.

---

## 9. Message Style Guide

This section is the reference for writing new performance insight messages. All future
messages must follow these rules.

### Rule 1: Lead with what the programmer's code does, not what the compiler does

**Wrong:** "Perceus reuse blocked: non-unique reference count at allocation site"
**Right:** "`items` is used in two places, so each transformation allocates a new copy."

The subject of the sentence is the programmer's value. The compiler is never the subject.

### Rule 2: Say what *happens*, then say what *to do*

Structure: [observation]. [consequence]. [suggestion].

**Wrong:** "Non-tail-recursive call detected."
**Right:** "This recursive call grows the stack once per list element. For large lists, it will overflow. Move the `+ 1` into an accumulator parameter so the addition happens before the recursive call."

### Rule 3: Show the fix in code, not just in words

When a message has an obvious rewrite, include a code snippet. The snippet should be
minimal — the exact function body with the change applied, not an essay about functional
programming style.

### Rule 4: Positive insights are just as important as warnings

When the compiler *is* optimizing something, say so. "This call is compiled as a loop"
validates the programmer's code structure. "This value is allocated on the stack" tells
them their temporary is free.

### Rule 5: Severity must match the real-world impact

| Impact | Severity |
|--------|----------|
| Stack overflow possible for large input | Warning |
| Deep copy of large value on hot path | Warning |
| Small allocation that could be avoided | Hint |
| Compiler optimization is active (positive) | Information |
| Micro-optimization opportunity | Hint |

Do not emit `Warning` for anything that is correct behavior. `Warning` means "this is
likely to bite you in production."

### Do/Don't Reference

| Don't write | Write instead |
|-------------|--------------|
| "Atomic CAS required for this reference" | "This value uses synchronized memory operations because it crosses an actor boundary" |
| "FBIP reuse blocked" | "March can't update this in place because it's used in two places" |
| "Closure captures N free variables" | "This function closes over N values" |
| "ECallPtr emitted — indirect dispatch" | "This call goes through a function pointer" |
| "Linear type enables ownership transfer" | "`data` is marked linear, so sending it transfers ownership — no copying" |
| "Escape analysis: value does not escape" | "This value stays local to the function, so it lives on the stack" |
| "Non-atomic RC used for local value" | (just don't say anything — local RC is invisible to the programmer) |

---

## 10. Differentiation: Why This Matters

Most language tooling surfaces one kind of insight: type errors. A handful of mature
systems (rust-analyzer, HLS) add lifetime or strictness warnings. None of them surface
the full optimization picture in plain English.

March has a unique opportunity here because:

1. **The compiler does more**: Perceus/FBIP, escape analysis, and defunctionalization
   produce richer optimization data than most language compilers. There is genuinely more
   to say.

2. **The target audience cares**: March programmers writing actors, processing large data
   structures, or building hot-path code want to know whether their code is efficient.
   They are not using March casually.

3. **The timing is right**: It is much easier to add performance insight infrastructure
   early, before the compiler's internal representations stabilize, than to retrofit it
   later. The TIR node types are the right abstraction — they already encode exactly the
   distinctions needed.

4. **No one else does this well**: Rust's `clippy` hints at some of this but focuses on
   correctness. Haskell's `ghc -ddump-simpl` requires reading Core IR. GHC's `{-# INLINABLE #-}` annotations are user-driven, not compiler-driven. March can be the first
   language where the compiler proactively explains its optimization decisions in plain
   English, in the editor, in real time.

The pitch for the marketing page: **"March's LSP tells you what your code will cost, not
just whether it type-checks."**

---

## 11. Implementation Checklist

### Phase 1 (P1 insights, no new pipeline)

- [ ] Add `perf_insight` type and `perf_insights` field to `Analysis.t`
- [ ] Implement `Perf_analysis.find_non_tail_calls` — AST tail position analysis
- [ ] Implement `Perf_analysis.find_actor_copies` — send() call + linearity check
- [ ] Implement `Perf_analysis.find_large_captures` — free variable count in lambdas
- [ ] Wire P1 insights into `analyze` in `analysis.ml`
- [ ] Merge `Warning`-severity insights into the `diagnostics` list
- [ ] Add `perf_insights` to hover handler for contextual annotations
- [ ] Tests: 8 new tests in `test_lsp.ml` covering TCO, actor copy, closure capture
- [ ] Update `specs/todos.md` and `specs/progress.md`

### Phase 2 (P2 insights, AST heuristics)

- [ ] Implement `Perf_analysis.find_reuse_opportunities` — refs_map use-count heuristic
- [ ] Implement `Perf_analysis.find_indirect_calls` — parameter/lambda callee detection
- [ ] Implement `Perf_analysis.find_alloc_in_loops` — allocation in recursive arms
- [ ] Add inlay hints for indirect calls and reuse hints
- [ ] Add `"march.inlayHints.performanceAnnotations"` configuration key
- [ ] Tests: 6 additional tests in `test_lsp.ml`

### Phase 3 (P3 insights, async TIR pipeline)

- [ ] Design `Tir_analysis.t` record and async computation model
- [ ] Wire TIR pipeline: `lower → mono → defun → known_call → perceus → escape`
- [ ] Extract `EStackAlloc` sites and map back to source spans
- [ ] Extract `EReuse` sites and map back to source spans
- [ ] Extract `ECallPtr` sites that survived known_call optimization
- [ ] Push incremental `publishDiagnostics` when TIR results arrive
- [ ] Add code lens provider for per-function performance summaries
- [ ] Tests: 6 additional tests covering TIR-level insights

---

## 12. Dependencies and Risk

| Dependency | Risk | Mitigation |
|-----------|------|-----------|
| AST tail position analysis | Low — pure tree walk | Well-defined algorithm, no external deps |
| `type_map` linearity for actor copy | Low — already in Analysis.t | Use existing `Tc.TLin` check |
| TIR async pipeline (P3) | Medium — new infrastructure | P1/P2 deliver value independently |
| Span mapping TIR → source (P3) | Medium — TIR loses some span info | Preserve spans in lower.ml for critical nodes |
| Editor support for inlay hints | Low — linol supports them | Follow existing `inlay_hints` implementation |
| Performance of analysis pass | Low — AST walk is cheap | Profile; cache per-function results |

The P1/P2 insights deliver significant value with no risk. P3 requires careful
engineering but is not on the critical path.
