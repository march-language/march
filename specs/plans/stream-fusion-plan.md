# Stream Fusion / Deforestation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate intermediate list allocations in `map |> filter |> fold` pipelines by fusing chained list combinators into a single loop at the TIR level, transparently (no user code changes).

**Architecture:** A new TIR pass `lib/tir/fusion.ml` runs immediately after defunctionalization and before Perceus. It uses a use-count pre-pass to find single-use intermediate list bindings, then pattern-matches on chains of known list combinators (`list_map`, `list_filter`, `list_fold_left`, etc.) and rewrites them into a single tail-recursive loop. No new surface syntax or stdlib types are required for the compiler optimization; a separate stdlib `Stream` module is added as the user-facing API for explicit streaming.

**Tech Stack:** OCaml 5.3 (TIR manipulation), March stdlib (stream module), Alcotest (tests), dune build system.

---

## Background

### 1.1  Build/foldr deforestation (Gill, Launchbury, Peyton Jones 1993)

The classic `foldr/build` fusion rule:
```
foldr c n (build g) = g c n
```
Eliminates the intermediate list produced by `build g` when it is immediately consumed by `foldr`. Works beautifully in lazy Haskell where `build` and `foldr` are the universal producers/consumers. Requires laziness to avoid duplicating work when the list is used more than once.

**Why it doesn't work for March:** March is strict. `build` would need to construct the full list eagerly before `foldr` sees it. The fusion rule only fires if the compiler can prove single-use at compile time (which it can, but the rewrite infrastructure is Haskell-specific). March has no `foldr/build` primitives to rewrite.

### 1.2  Stream fusion (Coutts, Leshchinskiy, Stewart 2007 — "Stream Fusion: From Lists to Streams to Nothing at All")

Reference: R. Coutts, R. Leshchinskiy, D. Stewart. "Stream Fusion: From Lists to Streams to Nothing at All." ICFP 2007.

Stream fusion replaces the intermediate list with a *stream* — a co-data structure that produces elements on demand. The key type:

```
type Step(s, a) = Done | Yield(a, s) | Skip(s)
```

A stream is a pair `(seed : s, step : s -> Step(s, a))`. `step` is called once per element; `Done` signals end, `Yield(a, next_seed)` produces element `a` and advances the seed, `Skip(next_seed)` skips (used for filter). Every list combinator has a stream variant that composes step functions without allocating an intermediate list. The chain:

```
fromStream . stream_filter g . stream_map f . toStream
```

fuses by inlining `toStream`/`fromStream` and composing the step functions into one.

**Why stream fusion is better for March:**

1. **Works with strict evaluation.** The stream is never materialized until `fromStream` is called, but the step function is just a regular (strict) recursive call — no heap allocation per step, no laziness bookkeeping.
2. **Composable.** Each combinator transforms the step function. After inlining, the composed step function is a direct loop body.
3. **Compatible with Perceus.** The fused loop allocates nothing (no `Cons` cells, no intermediate seeds for simple combinators), so Perceus sees zero RC operations on the hot path — a pure win.
4. **Transparent.** Users write `map |> filter |> fold`; the compiler fuses automatically.

### 1.3  Why the benchmark gap exists today

From `bench/RESULTS.md`:

| Language | list-ops(1M) |
|----------|-------------|
| March    | 117.3 ms    |
| OCaml    | 28.5 ms     |
| **Rust** | **3.0 ms**  |

Rust's iterator pipeline (`iter().map().filter().sum()`) is fused by LLVM into a single tight loop with **zero allocation**. OCaml allocates two intermediate lists but its generational GC collects them cheaply. March builds `ICons` chains for every intermediate step and pays per-node Perceus RC overhead.

Stream fusion brings March to Rust-level zero-allocation performance for HOF pipelines.

---

## 2. The Stream Representation

### 2.1  The `Step` type

```march
-- Step(s, a): the result of one step of a stream over elements of type a with seed type s.
type Step(s, a) = Done | Yield(a, s) | Skip(s)
```

- `Done` — the stream is exhausted.
- `Yield(value, next_seed)` — produce `value`, continue with `next_seed`.
- `Skip(next_seed)` — skip this position (used by `filter`), continue with `next_seed`.

### 2.2  The `Stream` type

```march
-- Stream(s, a): a producer of 'a' values parameterized on seed type s.
-- The seed is existentially quantified (type-erased) at the fusion boundary.
type Stream(s, a) = Stream(s, fn s -> Step(s, a))
```

`s` is the *internal state* — for a list stream it's `List(a)`, for a range stream it's `Int`. Users never see `s`; it is eliminated by monomorphization.

### 2.3  `toStream` and `fromStream`

`toStream` packs a list into a stream using the list spine as seed:

```march
fn toStream(xs : List(a)) : Stream(List(a), a) do
  Stream(xs, fn seed ->
    match seed do
    | Nil        -> Done
    | Cons(h, t) -> Yield(h, t)
    end)
end
```

`fromStream` materializes a stream back to a list:

```march
fn fromStream(s : Stream(seed, a)) : List(a) do
  let Stream(init, step) = s
  fn go(seed : seed, acc : List(a)) : List(a) do
    match step(seed) do
    | Done           -> List.reverse(acc)
    | Skip(next)     -> go(next, acc)
    | Yield(v, next) -> go(next, Cons(v, acc))
    end
  end
  go(init, Nil)
end
```

**The fusion boundary:** `fromStream(toStream(xs))` must simplify to `xs` after inlining. The TIR optimizer's fixed-point loop handles this: inline `toStream`, inline `fromStream`, and the `match step(seed)` reduces to a direct list match.

### 2.4  Stream combinators

Each list combinator has a stream variant that transforms the step function without allocating:

```march
-- stream_map: apply f to every yielded value
fn stream_map(f : a -> b, s : Stream(seed, a)) : Stream(seed, b) do
  let Stream(init, step) = s
  Stream(init, fn seed ->
    match step(seed) do
    | Done           -> Done
    | Skip(next)     -> Skip(next)
    | Yield(v, next) -> Yield(f(v), next)
    end)
end

-- stream_filter: skip values that don't satisfy pred
fn stream_filter(pred : a -> Bool, s : Stream(seed, a)) : Stream(seed, a) do
  let Stream(init, step) = s
  Stream(init, fn seed ->
    match step(seed) do
    | Done           -> Done
    | Skip(next)     -> Skip(next)
    | Yield(v, next) -> if pred(v) then Yield(v, next) else Skip(next)
    end)
end

-- stream_fold: consume the stream, producing a single value
fn stream_fold(zero : b, f : b -> a -> b, s : Stream(seed, a)) : b do
  let Stream(init, step) = s
  fn go(seed : seed, acc : b) : b do
    match step(seed) do
    | Done           -> acc
    | Skip(next)     -> go(next, acc)
    | Yield(v, next) -> go(next, f(acc, v))
    end
  end
  go(init, zero)
end
```

### 2.5  What the benchmark looks like with explicit streams

```march
-- Explicit stream version (for illustration; compiler fuses the list version automatically)
fn bench_stream(n : Int) : Int do
  range(1, n + 1)
  |> toStream
  |> stream_map(fn x -> x * 2)
  |> stream_filter(fn x -> x % 3 == 0)
  |> stream_fold(0, fn (a, b) -> a + b)
end
```

After inlining `toStream`, `stream_map`, `stream_filter`, `stream_fold`, the entire expression reduces to:

```march
fn bench_fused(n : Int) : Int do
  fn go(seed : List(Int), acc : Int) : Int do
    match seed do
    | Nil        -> acc
    | Cons(h, t) ->
      let v = h * 2
      if v % 3 == 0
      then go(t, acc + v)
      else go(t, acc)
    end
  end
  go(range(1, n + 1), 0)
end
```

Zero intermediate allocations. Single pass over the input.

---

## 3. Where This Lives in the Pipeline

### 3.1  Current pass order (from `bin/main.ml:347–352`)

```
Lower   → Mono   → Defun   → Perceus  → Escape  → Opt(Inline/Fold/Simplify/DCE)
```

### 3.2  Proposed pass order

```
Lower   → Mono   → Defun   → Fusion   → Perceus  → Escape  → Opt(Inline/Fold/Simplify/DCE)
```

The fusion pass (`lib/tir/fusion.ml`) runs between Defun and Perceus.

### 3.3  Why ordering matters

**After Defun:** By the time Fusion runs, all lambdas have been lifted to top-level closure structs and all calls to known list combinators are `EApp` nodes with statically known function names (`"list_map"`, `"list_filter"`, etc.). Pattern-matching on function names is reliable here. If Fusion ran before Defun, lambdas would still be `ELetRec`-as-value nodes — harder to recognize structurally.

**Before Perceus:** Perceus inserts `EIncRC`/`EDecRC`/`EFree`/`EReuse` based on the liveness of each allocation. A fused pipeline that never allocates intermediate lists will have *zero* RC operations on the hot path. If Fusion ran after Perceus, Perceus would have already inserted RC ops for the intermediate lists (which wouldn't fire — Perceus is smart about unique values — but the code would still contain dead RC chains that need a second DCE pass to clean up). Running Fusion before Perceus gives Perceus the cleanest possible input.

**Before Escape:** Escape analysis stack-allocates values that don't escape their creating function. A fused loop that never allocates intermediate lists is trivially fine for escape analysis; running Fusion before Escape means escape analysis doesn't need to see (and misanalyze) the intermediate list allocations.

**Interaction with Opt's Inline pass:** The Opt loop runs `Inline → Fold → Simplify → DCE` up to 5 times. Inline has a size threshold of 15 nodes (`inline_size_threshold = 15`). After Fusion, the fused loop contains the inlined step logic directly — Inline may further simplify it. Fusion and Inline are complementary: Fusion handles structural list-chain fusion; Inline handles small call chains everywhere else.

### 3.4  Interaction with Perceus (FBIP)

Fusion is **purely additive** for Perceus. When the list pipeline is fused, the intermediate `Cons` allocations simply don't exist. Perceus sees a loop over a single input list, iterating with a tail call, accumulating into an integer — no heap allocation, no RC operations on the hot path. The input list itself may still have its RC managed by Perceus (it's consumed once, so Perceus can emit `EFree` on each `Cons` node as it's pattern-matched), but the intermediate lists are eliminated entirely.

The FBIP reuse analysis in Perceus may further optimize the fused loop: if the input list has RC=1 when the function is called, the `Cons` cells can be freed in-place as they're consumed (Perceus already handles this for the unfused case; in the fused case, there's less to free).

### 3.5  Interaction with monomorphization

Fusion works on already-monomorphized TIR (it runs after Mono). This means:
- `stream_map(fn x -> x * 2, ...)` has type variables already resolved to `Int → Int`
- The generated fused loop is already fully typed — no new monomorphization needed
- Each unique combination of types produces its own fused specialization (this is correct since Mono already produced one)

---

## 4. Purity Analysis

### 4.1  Which operations are safe to fuse

Fusion is only correct when the step function is **pure** (no observable side effects). The existing `lib/tir/purity.ml` oracle is the right check.

Safe to fuse:
- `map(f, xs)` — safe when `f` is pure (no IO, no actor sends)
- `filter(pred, xs)` — safe when `pred` is pure
- `fold_left(acc, xs, f)` — safe when `f` is pure (fold itself is a consumer; fusing a fold into the producer is always safe if `f` is pure)
- `take(xs, n)`, `drop(xs, n)` — pure, no function argument
- `zip(xs, ys)` — pure (two-input stream; handled in Phase 4)
- `enumerate(xs)` — pure (counter is internal state)
- `flat_map(xs, f)` — safe when `f` is pure, but flattens the `Skip` optimization (more complex; leave for Phase 4)

**Not** safe to fuse:
- `map(tap>(g), xs)` — `tap>` is a debug inspector that has side effects (printing)
- `map(fn x -> send(actor, x), xs)` — `send` is in `impure_builtins`
- Any step function that contains `ECallPtr` to an unknown closure — the target may be impure

### 4.2  How to determine purity

Use the existing `Purity.is_pure : Tir.expr -> bool`. For a closure argument to `map`:
1. After Defun, the closure is an `EAlloc(TDClosure_anon_N, captured_vars)` stored in a let-binding
2. The closure dispatch function (generated by Defun) has a known name like `"$anon42_apply"`
3. Look up `$anon42_apply` in the module's `tm_fns` list
4. Run `Purity.is_pure` on its body

```ocaml
(* Pseudocode for closure purity check *)
let closure_is_pure (dispatch_name : string) (m : Tir.tir_module) : bool =
  match List.find_opt (fun fd -> fd.Tir.fn_name = dispatch_name) m.Tir.tm_fns with
  | None    -> false  (* unknown function → conservative: impure *)
  | Some fd -> Purity.is_pure fd.Tir.fn_body
```

### 4.3  Fallback for non-pure step functions

If purity cannot be proven, **do not fuse**. Leave the `EApp(list_map, ...)` chain as-is. This is the conservative-correct choice. The Purity oracle is already conservative (false negatives are safe). Users who need fusion with side-effectful steps should refactor to pull the side effects out of the step function.

---

## 5. Use-Count Analysis

### 5.1  Why single-use intermediates are the target

Fusion is only correct when the intermediate value (e.g., `ys` in `let ys = map(f, xs)`) is used **exactly once** (as the input to the next combinator). If `ys` is used twice:

```march
let ys = map(fn x -> x * 2, xs)
let sum1 = fold_left(0, ys, fn (a, b) -> a + b)   -- use 1
let sum2 = fold_left(0, ys, fn (a, b) -> a * b)   -- use 2
```

Fusing would require running the producer (`map`) twice (once per consumer). This is correct but may not be faster (depends on whether the producer is cheap). Conservative choice: **don't fuse multi-use intermediates**.

### 5.2  How to detect single-use

A pre-pass over the TIR function body counts variable occurrences:

```ocaml
(* lib/tir/use_count.ml *)
module StringMap = Map.Make(String)
type use_map = int StringMap.t

let rec count_uses_expr (m : use_map) : Tir.expr -> use_map = function
  | Tir.EAtom (Tir.AVar v)     -> StringMap.update v.v_name (function None -> Some 1 | Some n -> Some (n+1)) m
  | Tir.EApp (f, args)         ->
    let m = StringMap.update f.v_name (function None -> Some 1 | Some n -> Some (n+1)) m in
    List.fold_left count_uses_atom m args
  | Tir.ELet (_, rhs, body)    -> count_uses_expr (count_uses_expr m rhs) body
  (* ... etc for all expr forms ... *)
  | _ -> m

let uses_once (v : string) (m : use_map) : bool =
  StringMap.find_opt v m = Some 1
```

### 5.3  Multi-use intermediates — policy

If an intermediate is used more than once, skip fusion for that binding. The unfused version may still benefit from Perceus FBIP if the RC count is 1 at the call site.

---

## 6. File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/tir/use_count.ml` | **Create** | Variable use-count analysis for fusion guard |
| `lib/tir/use_count.mli` | **Create** | Interface: `count_uses_fn`, `uses_once` |
| `lib/tir/fusion.ml` | **Create** | Main fusion pass: chain detection + rewrite |
| `lib/tir/fusion.mli` | **Create** | Interface: `fuse : Tir.tir_module -> Tir.tir_module` |
| `lib/tir/dune` | **Modify** | Add `use_count` and `fusion` modules |
| `bin/main.ml:350` | **Modify** | Insert `March_tir.Fusion.fuse tir` between Defun and Perceus |
| `stdlib/stream.march` | **Create** | User-facing `Stream` module (independent of compiler pass) |
| `test/test_march.ml` | **Modify** | Add `"stream_fusion"` test suite |
| `specs/todos.md` | **Modify** | Move item to Done when complete |
| `specs/progress.md` | **Modify** | Update test count + add feature bullet |

---

## 7. TDD Phases

### Phase 1: Use-count analysis + stream stdlib

**Goal:** Verify the use-count infrastructure before touching the fusion pass.

---

#### Task 1: `lib/tir/use_count.ml` — use-count analysis

**Files:**
- Create: `lib/tir/use_count.ml`
- Create: `lib/tir/use_count.mli`
- Modify: `lib/tir/dune`
- Test: `test/test_march.ml` (add `"stream_fusion"` suite)

- [ ] **Step 1.1: Write failing test — single-use detection**

Add to `test/test_march.ml` (before the final `Alcotest.run` call):

```ocaml
(* ── Stream fusion tests ─────────────────────────────────────── *)

(** Build a minimal TIR module with one function that has a single-use let. *)
let use_count_single_use_tir () =
  (* fn foo(xs : List(Int)) : Int =
       let ys = EApp(list_map, [f, xs])   -- ys used once
       EApp(list_fold, [zero, ys, g]) *)
  let xs_var  = { Tir.v_name = "xs"; v_ty = Tir.TCon("List",[Tir.TInt]); v_lin = Tir.Unr } in
  let ys_var  = { Tir.v_name = "ys"; v_ty = Tir.TCon("List",[Tir.TInt]); v_lin = Tir.Unr } in
  let f_var   = { Tir.v_name = "f";  v_ty = Tir.TFn([Tir.TInt],Tir.TInt); v_lin = Tir.Unr } in
  let g_var   = { Tir.v_name = "g";  v_ty = Tir.TFn([Tir.TInt;Tir.TInt],Tir.TInt); v_lin = Tir.Unr } in
  let map_var = { Tir.v_name = "list_map"; v_ty = Tir.TUnit; v_lin = Tir.Unr } in
  let fold_var= { Tir.v_name = "list_fold"; v_ty = Tir.TUnit; v_lin = Tir.Unr } in
  let body =
    Tir.ELet(ys_var,
      Tir.EApp(map_var, [Tir.AVar f_var; Tir.AVar xs_var]),  (* ys = list_map(f, xs) *)
      Tir.EApp(fold_var, [Tir.ALit(March_ast.Ast.LInt 0); Tir.AVar ys_var; Tir.AVar g_var]))
      (* fold(0, ys, g) — ys used once *)
  in
  { Tir.fn_name = "foo"; fn_params = [xs_var; f_var; g_var]; fn_ret_ty = Tir.TInt; fn_body = body }

let test_use_count_single_use () =
  let fd = use_count_single_use_tir () in
  let counts = March_tir.Use_count.count_uses_fn fd in
  Alcotest.(check bool) "ys used exactly once" true
    (March_tir.Use_count.uses_once "ys" counts)

let test_use_count_multi_use () =
  let xs_var  = { Tir.v_name = "xs"; v_ty = Tir.TCon("List",[Tir.TInt]); v_lin = Tir.Unr } in
  let ys_var  = { Tir.v_name = "ys"; v_ty = Tir.TCon("List",[Tir.TInt]); v_lin = Tir.Unr } in
  let f_var   = { Tir.v_name = "f";  v_ty = Tir.TFn([Tir.TInt],Tir.TInt); v_lin = Tir.Unr } in
  let g_var   = { Tir.v_name = "g";  v_ty = Tir.TFn([Tir.TInt;Tir.TInt],Tir.TInt); v_lin = Tir.Unr } in
  let map_var = { Tir.v_name = "list_map"; v_ty = Tir.TUnit; v_lin = Tir.Unr } in
  let fold_var= { Tir.v_name = "list_fold"; v_ty = Tir.TUnit; v_lin = Tir.Unr } in
  let body =
    Tir.ELet(ys_var,
      Tir.EApp(map_var, [Tir.AVar f_var; Tir.AVar xs_var]),
      (* ys used TWICE *)
      Tir.EApp(fold_var, [Tir.AVar ys_var; Tir.AVar ys_var; Tir.AVar g_var]))
  in
  let fd = { Tir.fn_name = "bar"; fn_params = [xs_var; f_var; g_var]; fn_ret_ty = Tir.TInt; fn_body = body } in
  let counts = March_tir.Use_count.count_uses_fn fd in
  Alcotest.(check bool) "ys used twice, not once" false
    (March_tir.Use_count.uses_once "ys" counts)
```

Add the suite registration near the end of the file (before the last `]`):
```ocaml
      ("stream_fusion", [
        Alcotest.test_case "use_count single-use" `Quick test_use_count_single_use;
        Alcotest.test_case "use_count multi-use"  `Quick test_use_count_multi_use;
      ]);
```

- [ ] **Step 1.2: Run test to verify it fails**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep -A3 "stream_fusion"
```

Expected: compilation error (module `March_tir.Use_count` not found).

- [ ] **Step 1.3: Create `lib/tir/use_count.mli`**

```ocaml
(** Variable use-count analysis for the fusion pass.
    Counts occurrences of every variable name in a function body. *)

type use_map
(** Opaque map from variable name to use count. *)

val count_uses_fn : Tir.fn_def -> use_map
(** Count all variable occurrences in [fd.fn_body]. *)

val uses_once : string -> use_map -> bool
(** [uses_once name m] is [true] iff [name] appears exactly once in [m]. *)

val use_count : string -> use_map -> int
(** [use_count name m] returns the number of occurrences of [name], or 0. *)
```

- [ ] **Step 1.4: Create `lib/tir/use_count.ml`**

```ocaml
(** Variable use-count analysis.
    Walks a TIR expr and counts occurrences of each variable name.
    Used by the fusion pass to decide whether an intermediate is single-use. *)

module StringMap = Map.Make(String)

type use_map = int StringMap.t

let bump (name : string) (m : use_map) : use_map =
  StringMap.update name (function None -> Some 1 | Some n -> Some (n + 1)) m

let rec count_uses_atom (m : use_map) : Tir.atom -> use_map = function
  | Tir.AVar v   -> bump v.Tir.v_name m
  | Tir.ADefRef _ | Tir.ALit _ -> m

let rec count_uses_expr (m : use_map) : Tir.expr -> use_map = function
  | Tir.EAtom a                  -> count_uses_atom m a
  | Tir.EApp (f, args)           ->
    List.fold_left count_uses_atom (bump f.Tir.v_name m) args
  | Tir.ECallPtr (f, args)       ->
    List.fold_left count_uses_atom (count_uses_atom m f) args
  | Tir.ELet (_, rhs, body)      -> count_uses_expr (count_uses_expr m rhs) body
  | Tir.ELetRec (fns, body)      ->
    let m = List.fold_left (fun acc fd -> count_uses_expr acc fd.Tir.fn_body) m fns in
    count_uses_expr m body
  | Tir.ECase (a, branches, def) ->
    let m = count_uses_atom m a in
    let m = List.fold_left (fun acc br -> count_uses_expr acc br.Tir.br_body) m branches in
    (match def with Some d -> count_uses_expr m d | None -> m)
  | Tir.ETuple atoms             -> List.fold_left count_uses_atom m atoms
  | Tir.ERecord fs               -> List.fold_left (fun acc (_, a) -> count_uses_atom acc a) m fs
  | Tir.EField (a, _)            -> count_uses_atom m a
  | Tir.EUpdate (a, fs)          ->
    List.fold_left (fun acc (_, b) -> count_uses_atom acc b) (count_uses_atom m a) fs
  | Tir.EAlloc (_, args)
  | Tir.EStackAlloc (_, args)    -> List.fold_left count_uses_atom m args
  | Tir.EFree a
  | Tir.EIncRC a | Tir.EDecRC a
  | Tir.EAtomicIncRC a | Tir.EAtomicDecRC a -> count_uses_atom m a
  | Tir.EReuse (a, _, args)      -> List.fold_left count_uses_atom (count_uses_atom m a) args
  | Tir.ESeq (e1, e2)            -> count_uses_expr (count_uses_expr m e1) e2

let count_uses_fn (fd : Tir.fn_def) : use_map =
  count_uses_expr StringMap.empty fd.Tir.fn_body

let uses_once (name : string) (m : use_map) : bool =
  StringMap.find_opt name m = Some 1

let use_count (name : string) (m : use_map) : int =
  Option.value ~default:0 (StringMap.find_opt name m)
```

- [ ] **Step 1.5: Register module in `lib/tir/dune`**

In `lib/tir/dune`, find the `(library ...)` stanza and add `use_count` to the `modules` field:

```
 modules (tir lower mono defun perceus escape opt inline fold simplify dce
          purity pp llvm_emit use_count)
```

(Exact list may differ — add `use_count` to whatever is already there.)

- [ ] **Step 1.6: Run test to verify it passes**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep -E "stream_fusion|PASS|FAIL"
```

Expected: `stream_fusion  use_count single-use  PASS`, `stream_fusion  use_count multi-use  PASS`.

- [ ] **Step 1.7: Commit**

```bash
git add lib/tir/use_count.ml lib/tir/use_count.mli lib/tir/dune test/test_march.ml
git commit -m "feat(fusion): add use-count analysis for fusion guard"
```

---

#### Task 2: `stdlib/stream.march` — user-facing Stream module

**Files:**
- Create: `stdlib/stream.march`

- [ ] **Step 2.1: Write failing test — stream round-trip**

Add to the `"stream_fusion"` test case list in `test/test_march.ml`:

```ocaml
let test_stream_roundtrip () =
  let env = eval_module {|mod Test do
    type Step(s, a) = Done | Yield(a, s) | Skip(s)
    type Stream(s, a) = MkStream(s, fn s -> Step(s, a))

    fn to_stream(xs : List(Int)) : Stream(List(Int), Int) do
      MkStream(xs, fn seed ->
        match seed do
        | Nil        -> Done
        | Cons(h, t) -> Yield(h, t)
        end)
    end

    fn from_stream(s : Stream(List(Int), Int)) : List(Int) do
      let MkStream(init, step) = s
      fn go(seed : List(Int), acc : List(Int)) : List(Int) do
        match step(seed) do
        | Done           -> acc
        | Skip(next)     -> go(next, acc)
        | Yield(v, next) -> go(next, Cons(v, acc))
        end
      end
      go(init, Nil)
    end

    fn main() : List(Int) do
      from_stream(to_stream(Cons(1, Cons(2, Cons(3, Nil)))))
    end
  end|} in
  let v = call_fn env "main" [] in
  Alcotest.(check (list int)) "round-trip preserves list (reversed due to acc)"
    [3; 2; 1] (List.map vint (vlist v))
```

- [ ] **Step 2.2: Run test to verify it fails**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep "stream_fusion"
```

Expected: `FAIL` with a type error (the `Stream` type is not yet in stdlib).

- [ ] **Step 2.3: Create `stdlib/stream.march`**

```march
-- Stream module: pull-based streams with zero intermediate allocation.
-- Used directly for explicit streaming, and by the compiler's fusion pass.
--
-- Key types:
--   Step(s, a) = Done | Yield(a, s) | Skip(s)
--   Stream(s, a) = MkStream(s, fn s -> Step(s, a))
--
-- Usage:
--   xs |> Stream.of_list |> Stream.map(f) |> Stream.filter(p) |> Stream.fold(0, add)

mod Stream do

pub type Step(s, a) = Done | Yield(a, s) | Skip(s)
pub type Stream(s, a) = MkStream(s, fn s -> Step(s, a))

-- Convert a list to a stream (list spine is the seed).
pub fn of_list(xs : List(a)) : Stream(List(a), a) do
  MkStream(xs, fn seed ->
    match seed do
    | Nil        -> Done
    | Cons(h, t) -> Yield(h, t)
    end)
end

-- Materialize a stream into a list.
-- Elements are accumulated in reverse; result is reversed at the end.
pub fn to_list(s : Stream(seed, a)) : List(a) do
  let MkStream(init, step) = s
  fn go(state : seed, acc : List(a)) : List(a) do
    match step(state) do
    | Done           -> List.reverse(acc)
    | Skip(next)     -> go(next, acc)
    | Yield(v, next) -> go(next, Cons(v, acc))
    end
  end
  go(init, Nil)
end

-- Apply f to every yielded element.
pub fn map(f : a -> b, s : Stream(seed, a)) : Stream(seed, b) do
  let MkStream(init, step) = s
  MkStream(init, fn state ->
    match step(state) do
    | Done           -> Done
    | Skip(next)     -> Skip(next)
    | Yield(v, next) -> Yield(f(v), next)
    end)
end

-- Keep only elements satisfying pred. Non-matching elements become Skip.
pub fn filter(pred : a -> Bool, s : Stream(seed, a)) : Stream(seed, a) do
  let MkStream(init, step) = s
  MkStream(init, fn state ->
    match step(state) do
    | Done           -> Done
    | Skip(next)     -> Skip(next)
    | Yield(v, next) -> if pred(v) then Yield(v, next) else Skip(next)
    end)
end

-- Left fold over the stream.
pub fn fold(zero : b, f : b -> a -> b, s : Stream(seed, a)) : b do
  let MkStream(init, step) = s
  fn go(state : seed, acc : b) : b do
    match step(state) do
    | Done           -> acc
    | Skip(next)     -> go(next, acc)
    | Yield(v, next) -> go(next, f(acc, v))
    end
  end
  go(init, zero)
end

-- Take the first n elements.
pub fn take(n : Int, s : Stream(seed, a)) : Stream((seed, Int), a) do
  let MkStream(init, step) = s
  MkStream((init, n), fn state ->
    let (inner, remaining) = state
    if remaining <= 0 then Done
    else match step(inner) do
      | Done           -> Done
      | Skip(next)     -> Skip((next, remaining))
      | Yield(v, next) -> Yield(v, (next, remaining - 1))
      end)
end

-- Drop the first n elements.
pub fn drop(n : Int, s : Stream(seed, a)) : Stream((seed, Int), a) do
  let MkStream(init, step) = s
  MkStream((init, n), fn state ->
    let (inner, remaining) = state
    match step(inner) do
    | Done           -> Done
    | Skip(next)     -> Skip((next, remaining))
    | Yield(v, next) ->
      if remaining > 0 then Skip((next, remaining - 1))
      else Yield(v, (next, 0))
    end)
end

-- Count elements.
pub fn count(s : Stream(seed, a)) : Int do
  fold(0, fn (acc, _) -> acc + 1, s)
end

-- Sum a stream of integers.
pub fn sum(s : Stream(seed, Int)) : Int do
  fold(0, fn (acc, x) -> acc + x, s)
end

-- Zip two streams. Stops at the shorter.
pub fn zip(sa : Stream(sa, a), sb : Stream(sb, b)) : Stream((sa, sb), (a, b)) do
  let MkStream(ia, stepa) = sa
  let MkStream(ib, stepb) = sb
  MkStream((ia, ib), fn state ->
    let (sa2, sb2) = state
    match stepa(sa2) do
    | Done           -> Done
    | Skip(nsa)      -> Skip((nsa, sb2))
    | Yield(va, nsa) ->
      match stepb(sb2) do
      | Done           -> Done
      | Skip(nsb)      -> Skip((sa2, nsb))
      | Yield(vb, nsb) -> Yield((va, vb), (nsa, nsb))
      end
    end)
end

-- Pair each element with its 0-based index.
pub fn enumerate(s : Stream(seed, a)) : Stream((seed, Int), (Int, a)) do
  let MkStream(init, step) = s
  MkStream((init, 0), fn state ->
    let (inner, i) = state
    match step(inner) do
    | Done           -> Done
    | Skip(next)     -> Skip((next, i))
    | Yield(v, next) -> Yield((i, v), (next, i + 1))
    end)
end

end
```

- [ ] **Step 2.4: Load stream.march in main.ml stdlib loader**

In `bin/main.ml`, find where stdlib files are loaded (the `load_stdlib_file` calls). Add `stream.march`:

```ocaml
(* In the stdlib loading section, add: *)
"stream.march";
```

(Exact location: look for the list of stdlib files like `"list.march"`, `"iterable.march"`, etc.)

- [ ] **Step 2.5: Run test to verify it passes**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep "stream_fusion"
```

Expected: `stream_fusion  round-trip  PASS`.

- [ ] **Step 2.6: Add stream_map + stream_filter eval tests**

```ocaml
let test_stream_map () =
  let env = eval_module {|mod Test do
    fn main() : List(Int) do
      Cons(1, Cons(2, Cons(3, Nil)))
      |> Stream.of_list
      |> Stream.map(fn x -> x * 2)
      |> Stream.to_list
    end
  end|} in
  let v = call_fn env "main" [] in
  Alcotest.(check (list int)) "stream_map doubles elements" [2; 4; 6] (List.map vint (vlist v))

let test_stream_filter () =
  let env = eval_module {|mod Test do
    fn main() : List(Int) do
      Cons(1, Cons(2, Cons(3, Cons(4, Cons(5, Nil)))))
      |> Stream.of_list
      |> Stream.filter(fn x -> x % 2 == 0)
      |> Stream.to_list
    end
  end|} in
  let v = call_fn env "main" [] in
  Alcotest.(check (list int)) "stream_filter keeps evens" [2; 4] (List.map vint (vlist v))

let test_stream_fold () =
  let env = eval_module {|mod Test do
    fn main() : Int do
      Cons(1, Cons(2, Cons(3, Cons(4, Cons(5, Nil)))))
      |> Stream.of_list
      |> Stream.fold(0, fn (acc, x) -> acc + x)
    end
  end|} in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "stream_fold sums to 15" 15 (vint v)

let test_stream_map_filter_fold () =
  let env = eval_module {|mod Test do
    fn main() : Int do
      -- range 1..6, double, keep multiples of 3, sum
      -- doubled: 2,4,6,8,10  -- multiples of 3: 6  -- sum: 6
      Cons(1, Cons(2, Cons(3, Cons(4, Cons(5, Nil)))))
      |> Stream.of_list
      |> Stream.map(fn x -> x * 2)
      |> Stream.filter(fn x -> x % 3 == 0)
      |> Stream.fold(0, fn (acc, x) -> acc + x)
    end
  end|} in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "stream pipeline: sum of doubled multiples of 3" 6 (vint v)
```

- [ ] **Step 2.7: Run all stream tests**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep "stream_fusion"
```

Expected: all 5 stream tests PASS.

- [ ] **Step 2.8: Commit**

```bash
git add stdlib/stream.march bin/main.ml test/test_march.ml
git commit -m "feat(stdlib): add Stream module with map/filter/fold/take/drop/zip/enumerate"
```

---

### Phase 2: The TIR Fusion Pass

**Goal:** Implement the compiler pass that detects and fuses list combinator chains automatically. Users write `map |> filter |> fold`; the compiler eliminates intermediate lists.

#### Architecture of the fusion pass

The pass works in two stages per function definition:

1. **Scan** — walk the function body looking for `ELet(v, EApp(known_combinator, args), body)` where `v` is used exactly once in `body` and the next use is another list combinator call.

2. **Rewrite** — replace the chain with a new `ELetRec` containing a fused tail-recursive loop.

**Recognizable chains (the fusible set):**

| March function | TIR name | Kind |
|---------------|----------|------|
| `Iterable.map` | `"Iterable$map"` (after mono) | Producer→Producer |
| `Iterable.filter` | `"Iterable$filter"` | Producer→Producer |
| `Iterable.fold` | `"Iterable$fold"` | Producer→Consumer |
| `List.map` | `"List$map"` | Producer→Producer |
| `List.filter` | `"List$filter"` | Producer→Producer |
| `List.fold_left` | `"List$fold_left"` | Producer→Consumer |

**What a fused chain looks like in TIR (the benchmark):**

Before fusion:
```
(* fn main() : Int *)
ELet(xs, EApp(irange, [ALit 1; AVar n]),
ELet(ys, EApp(imap, [AVar xs; AVar double_clos]),
ELet(zs, EApp(ifilter, [AVar ys; AVar mod3_clos]),
EApp(ifold, [AVar zs; ALit 0; AVar add_clos]))))
```

After fusion (the generated loop body — written in TIR pseudocode):
```
(* Generated fused function: fuses map(double) |> filter(mod3) |> fold(add) *)
ELetRec([{
  fn_name   = "$fused_0";
  fn_params = [seed_var (* : List(Int) *); acc_var (* : Int *)];
  fn_ret_ty = TInt;
  fn_body   =
    ECase(AVar seed_var,
      [{ br_tag = "Nil"; br_vars = [];
         br_body = EAtom(AVar acc_var) }
      ;{ br_tag = "Cons"; br_vars = [h_var; t_var];
         (* apply double: v = h * 2 *)
         br_body = ELet(v_var, EApp(*, [AVar h_var; ALit 2]),
         (* apply mod3 filter: check v % 3 == 0 *)
         ELet(rem_var, EApp(%, [AVar v_var; ALit 3]),
         ECase(AVar rem_var,
           (* rem == 0: yield, accumulate v into acc *)
           [{ br_tag = "0_eq"; br_vars = [];
              br_body = ELet(acc2_var, EApp(+, [AVar acc_var; AVar v_var]),
                         EApp($fused_0, [AVar t_var; AVar acc2_var])) }
           (* rem != 0: skip, recurse with same acc *)
           ;{ br_tag = "_"; br_vars = [];
              br_body = EApp($fused_0, [AVar t_var; AVar acc_var]) }],
           None))) }],
      None)
}],
(* Call the fused function with the source list and initial accumulator *)
EApp($fused_0, [AVar xs; ALit 0]))
```

Note: the `ECase` on `rem == 0` is simplified from `EApp(==, ...)` — the constant-fold pass in Opt will further reduce this. The key insight is that **zero intermediate `Cons` cells are allocated**.

---

#### Task 3: Chain detection (recognition pass)

**Files:**
- Create: `lib/tir/fusion.ml` (initially just detection, no rewrite)
- Create: `lib/tir/fusion.mli`
- Modify: `lib/tir/dune`

- [ ] **Step 3.1: Write failing test — detect map→filter→fold chain**

Add to `test/test_march.ml` `"stream_fusion"` suite:

```ocaml
(** Verify that the fusion pass detects a 3-step chain and reports it. *)
let test_fusion_detects_chain () =
  (* Build TIR for: let ys = map(f, xs); let zs = filter(g, ys); fold(h, 0, zs) *)
  let list_ty = Tir.TCon("List", [Tir.TInt]) in
  let xs  = { Tir.v_name = "xs"; v_ty = list_ty; v_lin = Tir.Unr } in
  let ys  = { Tir.v_name = "ys"; v_ty = list_ty; v_lin = Tir.Unr } in
  let zs  = { Tir.v_name = "zs"; v_ty = list_ty; v_lin = Tir.Unr } in
  let f   = { Tir.v_name = "f";  v_ty = Tir.TFn([Tir.TInt], Tir.TInt); v_lin = Tir.Unr } in
  let g   = { Tir.v_name = "g";  v_ty = Tir.TFn([Tir.TInt], Tir.TBool); v_lin = Tir.Unr } in
  let h   = { Tir.v_name = "h";  v_ty = Tir.TFn([Tir.TInt; Tir.TInt], Tir.TInt); v_lin = Tir.Unr } in
  let imap    = { Tir.v_name = "imap";    v_ty = Tir.TUnit; v_lin = Tir.Unr } in
  let ifilter = { Tir.v_name = "ifilter"; v_ty = Tir.TUnit; v_lin = Tir.Unr } in
  let ifold   = { Tir.v_name = "ifold";   v_ty = Tir.TUnit; v_lin = Tir.Unr } in
  let body =
    Tir.ELet(ys, Tir.EApp(imap,    [Tir.AVar xs; Tir.AVar f]),
    Tir.ELet(zs, Tir.EApp(ifilter, [Tir.AVar ys; Tir.AVar g]),
    Tir.EApp(ifold, [Tir.AVar zs; Tir.ALit(March_ast.Ast.LInt 0); Tir.AVar h])))
  in
  let fd = { Tir.fn_name = "bench"; fn_params = [xs; f; g; h]; fn_ret_ty = Tir.TInt; fn_body = body } in
  let chains = March_tir.Fusion.find_chains fd in
  Alcotest.(check int) "found exactly 1 fusible chain" 1 (List.length chains)

(** Verify that a multi-use intermediate is NOT detected as a chain. *)
let test_fusion_no_chain_multi_use () =
  let list_ty = Tir.TCon("List", [Tir.TInt]) in
  let xs  = { Tir.v_name = "xs"; v_ty = list_ty; v_lin = Tir.Unr } in
  let ys  = { Tir.v_name = "ys"; v_ty = list_ty; v_lin = Tir.Unr } in
  let f   = { Tir.v_name = "f";  v_ty = Tir.TFn([Tir.TInt], Tir.TInt); v_lin = Tir.Unr } in
  let h   = { Tir.v_name = "h";  v_ty = Tir.TFn([Tir.TInt; Tir.TInt], Tir.TInt); v_lin = Tir.Unr } in
  let imap  = { Tir.v_name = "imap";  v_ty = Tir.TUnit; v_lin = Tir.Unr } in
  let ifold = { Tir.v_name = "ifold"; v_ty = Tir.TUnit; v_lin = Tir.Unr } in
  (* ys used twice *)
  let body =
    Tir.ELet(ys, Tir.EApp(imap, [Tir.AVar xs; Tir.AVar f]),
    Tir.EApp(ifold, [Tir.AVar ys; Tir.AVar ys; Tir.AVar h]))
  in
  let fd = { Tir.fn_name = "bad"; fn_params = [xs; f; h]; fn_ret_ty = Tir.TInt; fn_body = body } in
  let chains = March_tir.Fusion.find_chains fd in
  Alcotest.(check int) "multi-use intermediate: no chains found" 0 (List.length chains)
```

- [ ] **Step 3.2: Run to verify fail**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep "stream_fusion"
```

Expected: compile error (no `Fusion` module).

- [ ] **Step 3.3: Create `lib/tir/fusion.mli`**

```ocaml
(** Stream fusion / deforestation pass.

    Transforms chains of list combinators (map, filter, fold_left, etc.)
    into single fused loops, eliminating intermediate list allocations.

    This pass runs after Defun and before Perceus. *)

(** A detected fusible chain: a sequence of let-bound list operations
    where each intermediate value is used exactly once. *)
type chain = {
  ch_source_var    : string;          (** The input list variable name (e.g. "xs") *)
  ch_first_let_var : string;          (** Name bound by the first ELet of the chain (e.g. "ys") *)
  ch_steps         : chain_step list; (** map/filter steps in order *)
  ch_consumer      : chain_consumer;  (** The terminal fold/count/sum *)
  ch_result_var    : Tir.var;         (** Where the final result is bound *)
}

and chain_step =
  | StMap    of Tir.atom  (** map(f, _): f is a var or defref *)
  | StFilter of Tir.atom  (** filter(pred, _): pred is a var or defref *)

and chain_consumer =
  | ConFold  of Tir.atom * Tir.atom  (** fold(zero, f, _) *)
  | ConSum                            (** sum(_) — fold(0, (+)) *)
  | ConCount                          (** count(_) — fold(0, \_ -> +1) *)

(** Note on [ch_source_var] and [ch_first_let_var]:
    - [ch_source_var]   is the name of the input list variable (e.g. "xs")
    - [ch_first_let_var] is the name bound by the FIRST ELet in the chain
      (e.g. "ys" in [let ys = map(f, xs)]).  [replace_chain] uses this to
      locate the exact ELet node to splice out. *)

val find_chains : Tir.fn_def -> chain list
(** Detect all fusible chains in a function body.
    A chain is fusible iff:
    - Every intermediate variable is used exactly once.
    - The chain terminates in a consumer (fold, sum, count). *)

val fuse : Tir.tir_module -> Tir.tir_module
(** Run the full fusion pass over all functions in the module. *)
```

- [ ] **Step 3.4: Create `lib/tir/fusion.ml` (detection only, no rewrite yet)**

```ocaml
(** Stream fusion pass — chain detection.
    See fusion.mli for the interface description. *)

(* ── Fusible function names ─────────────────────────────────── *)
(* These are the monomorphized names produced by the stdlib after
   Mono + Defun. Both the bench-local names (imap, ifilter, ifold)
   and the stdlib names are listed. *)

let fusible_map_names = [
  "imap"; "List$map"; "Iterable$map"; "map"
]
let fusible_filter_names = [
  "ifilter"; "List$filter"; "Iterable$filter"; "filter"
]
let fusible_fold_names = [
  "ifold"; "List$fold_left"; "Iterable$fold"; "fold"; "fold_left"
]
let fusible_sum_names  = ["List$sum_int"; "sum_int"; "sum"]
let fusible_count_names = ["List$length"; "Iterable$count"; "count"; "length"]

let is_map_call    name = List.mem name fusible_map_names
let is_filter_call name = List.mem name fusible_filter_names
let is_fold_call   name = List.mem name fusible_fold_names
let is_sum_call    name = List.mem name fusible_sum_names
let is_count_call  name = List.mem name fusible_count_names

(* ── Chain type ─────────────────────────────────────────────── *)

type chain_step =
  | StMap    of Tir.atom
  | StFilter of Tir.atom

type chain_consumer =
  | ConFold  of Tir.atom * Tir.atom
  | ConSum
  | ConCount

type chain = {
  ch_source_var    : string;
  ch_first_let_var : string;          (** name of first ELet binding in chain, for [replace_chain] *)
  ch_steps         : chain_step list;
  ch_consumer      : chain_consumer;
  ch_result_var    : Tir.var;
}

(* ── Detection ──────────────────────────────────────────────── *)

(** Try to extend a growing chain by looking at what 'var_name' feeds into.
    [expr] is the continuation after [var_name] is bound.
    [steps_rev] accumulates steps in reverse order.
    [counts] is the use-count map for the whole function body. *)
let rec try_extend_chain
    (var_name : string)
    (steps_rev : chain_step list)
    (counts : Use_count.use_map)
    (result_var : Tir.var)
    (expr : Tir.expr)
  : chain option =
  match expr with
  | Tir.ELet (bound, Tir.EApp (f, args), rest) ->
    (* Only extend if var_name is used exactly once (the argument to this call) *)
    if not (Use_count.uses_once var_name counts) then None
    else begin
      (* Check if this is a map(f, var_name) or filter(p, var_name) *)
      if is_map_call f.Tir.v_name then
        (* map(var_name, f) — note argument order varies by function.
           Convention: imap(xs, f) has xs first; List.map(xs, f) same.
           Check that var_name appears as one of the args. *)
        let input_is_var = List.exists (function
          | Tir.AVar v -> v.Tir.v_name = var_name
          | _ -> false) args in
        let fn_arg = List.find_opt (function
          | Tir.AVar v -> v.Tir.v_name <> var_name
          | Tir.ADefRef _ -> true
          | _ -> false) args in
        if input_is_var then
          match fn_arg with
          | Some fa -> try_extend_chain bound.Tir.v_name (StMap fa :: steps_rev) counts bound rest
          | None -> None
        else None
      else if is_filter_call f.Tir.v_name then
        let input_is_var = List.exists (function
          | Tir.AVar v -> v.Tir.v_name = var_name | _ -> false) args in
        let pred_arg = List.find_opt (function
          | Tir.AVar v -> v.Tir.v_name <> var_name
          | Tir.ADefRef _ -> true
          | _ -> false) args in
        if input_is_var then
          match pred_arg with
          | Some pa -> try_extend_chain bound.Tir.v_name (StFilter pa :: steps_rev) counts bound rest
          | None -> None
        else None
      else None  (* not a fusible step *)
    end
  | Tir.EApp (f, args) ->
    (* Terminal: fold, sum, or count consuming var_name *)
    if not (Use_count.uses_once var_name counts) then None
    else
      let input_is_var = List.exists (function
        | Tir.AVar v -> v.Tir.v_name = var_name | _ -> false) args in
      if not input_is_var then None
      else if is_fold_call f.Tir.v_name then
        (* fold(acc, xs, f) or fold(zero, xs, f) depending on convention *)
        let non_input_args = List.filter (function
          | Tir.AVar v -> v.Tir.v_name <> var_name | _ -> true) args in
        (match non_input_args with
         | [zero; fold_f] ->
           Some { ch_source_var    = "";  (* filled by caller *)
                  ch_first_let_var = "";  (* filled by caller *)
                  ch_steps         = List.rev steps_rev;
                  ch_consumer      = ConFold(zero, fold_f);
                  ch_result_var    = result_var }
         | _ -> None)
      else if is_sum_call f.Tir.v_name then
        Some { ch_source_var = ""; ch_first_let_var = "";
               ch_steps = List.rev steps_rev;
               ch_consumer = ConSum; ch_result_var = result_var }
      else if is_count_call f.Tir.v_name then
        Some { ch_source_var = ""; ch_first_let_var = "";
               ch_steps = List.rev steps_rev;
               ch_consumer = ConCount; ch_result_var = result_var }
      else None
  | _ -> None

(** Scan a function body for fusible chains. *)
let rec scan_for_chains
    (counts : Use_count.use_map)
    (chains_acc : chain list)
    (result_placeholder : Tir.var)
    (expr : Tir.expr)
  : chain list =
  match expr with
  | Tir.ELet (bound, Tir.EApp (f, args), rest) ->
    (* Is this a map or filter with a list-typed argument? *)
    let is_producer = is_map_call f.Tir.v_name || is_filter_call f.Tir.v_name in
    if is_producer && Use_count.uses_once bound.Tir.v_name counts then begin
      (* Try to find the source (list input) variable *)
      let source_opt = List.find_opt (function
        | Tir.AVar v -> (match v.Tir.v_ty with Tir.TCon("List", _) | Tir.TCon("IntList", _) -> true | _ -> false)
        | _ -> false) args in
      match source_opt with
      | Some (Tir.AVar src_var) ->
        let step = if is_map_call f.Tir.v_name then
          let fn_arg = List.find_opt (function
            | Tir.AVar v -> v.Tir.v_name <> src_var.Tir.v_name | Tir.ADefRef _ -> true | _ -> false) args in
          Option.map (fun fa -> StMap fa) fn_arg
        else
          let pred_arg = List.find_opt (function
            | Tir.AVar v -> v.Tir.v_name <> src_var.Tir.v_name | Tir.ADefRef _ -> true | _ -> false) args in
          Option.map (fun pa -> StFilter pa) pred_arg
        in
        let new_chains =
          match step with
          | None -> []
          | Some s ->
            match try_extend_chain bound.Tir.v_name [s] counts result_placeholder rest with
            | None -> []
            | Some ch -> [{ ch with
                            ch_source_var    = src_var.Tir.v_name;
                            ch_first_let_var = bound.Tir.v_name }]
        in
        scan_for_chains counts (new_chains @ chains_acc) bound rest
      | _ -> scan_for_chains counts chains_acc bound rest
    end else
      scan_for_chains counts chains_acc bound rest
  | Tir.ELet (_, _, rest) -> scan_for_chains counts chains_acc result_placeholder rest
  | _ -> chains_acc

let find_chains (fd : Tir.fn_def) : chain list =
  let counts = Use_count.count_uses_fn fd in
  let dummy_var = { Tir.v_name = "$result"; v_ty = fd.Tir.fn_ret_ty; v_lin = Tir.Unr } in
  scan_for_chains counts [] dummy_var fd.Tir.fn_body

(* ── Rewrite (Phase 3) — stubbed for now ───────────────────── *)

let fuse (m : Tir.tir_module) : Tir.tir_module = m
(* Rewrite implementation added in Phase 3 *)
```

- [ ] **Step 3.5: Add `use_count` and `fusion` to `lib/tir/dune`**

```
 modules (tir lower mono defun perceus escape opt inline fold simplify dce
          purity pp llvm_emit use_count fusion)
```

- [ ] **Step 3.6: Run chain detection tests**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep "stream_fusion"
```

Expected: `fusion_detects_chain PASS`, `fusion_no_chain_multi_use PASS`.

- [ ] **Step 3.7: Commit**

```bash
git add lib/tir/fusion.ml lib/tir/fusion.mli lib/tir/dune test/test_march.ml
git commit -m "feat(fusion): add chain detection pass (rewrite is a stub)"
```

---

#### Task 4: TIR inspection helper + fused-loop code generation

This task implements `fuse` — the actual rewrite. A critical test here is that we can inspect the TIR output of compiling a list pipeline and confirm no intermediate `EAlloc(Cons, ...)` nodes exist.

**Files:**
- Modify: `lib/tir/fusion.ml` (implement `fuse_fn_def`, `emit_fused_loop`)
- Modify: `test/test_march.ml` (add TIR inspection tests)

- [ ] **Step 4.1: Write failing test — TIR inspection for zero intermediate allocs**

```ocaml
(** Build a small module, run it through Lower→Mono→Defun→Fusion, and inspect
    the TIR for absence of intermediate list Cons allocations on the hot path. *)
let tir_of_source src =
  let type_map = Hashtbl.create 4 in
  let lexbuf = Lexing.from_string src in
  let m = March_parser.Parser.module_ March_lexer.Lexer.token lexbuf in
  let m = March_desugar.Desugar.desugar_module m in
  let _ = March_typecheck.Typecheck.check_module ~type_map m in
  let tir = March_tir.Lower.lower_module ~type_map m in
  let tir = March_tir.Mono.monomorphize tir in
  let tir = March_tir.Defun.defunctionalize tir in
  March_tir.Fusion.fuse tir

(** Count EAlloc nodes whose type contains "IntList" or "Cons" in the TIR. *)
let rec count_list_allocs : Tir.expr -> int = function
  | Tir.EAlloc (Tir.TCon("IntList", _), _) -> 1
  | Tir.EAlloc (Tir.TCon("List", _), _)    -> 1
  | Tir.ELet (_, rhs, body) -> count_list_allocs rhs + count_list_allocs body
  | Tir.ELetRec (fns, body) ->
    List.fold_left (fun a fd -> a + count_list_allocs fd.Tir.fn_body) 0 fns
    + count_list_allocs body
  | Tir.ECase (_, branches, def) ->
    List.fold_left (fun a b -> a + count_list_allocs b.Tir.br_body) 0 branches
    + Option.fold ~none:0 ~some:count_list_allocs def
  | Tir.ESeq (e1, e2) -> count_list_allocs e1 + count_list_allocs e2
  | _ -> 0

let test_fusion_no_intermediate_allocs () =
  let tir = tir_of_source {|mod Test do
    type IntList = INil | ICons(Int, IntList)
    fn imap(xs : IntList, f : Int -> Int) : IntList do
      match xs do
      | INil        -> INil
      | ICons(h, t) -> ICons(f(h), imap(t, f))
      end
    end
    fn ifilter(xs : IntList, pred : Int -> Bool) : IntList do
      match xs do
      | INil        -> INil
      | ICons(h, t) ->
        if pred(h) then ICons(h, ifilter(t, pred))
        else ifilter(t, pred)
      end
    end
    fn ifold(xs : IntList, acc : Int, f : Int -> Int -> Int) : Int do
      match xs do
      | INil        -> acc
      | ICons(h, t) -> ifold(t, f(acc, h), f)
      end
    end
    fn pipeline(xs : IntList) : Int do
      let ys = imap(xs, fn x -> x * 2)
      let zs = ifilter(ys, fn x -> x % 3 == 0)
      ifold(zs, 0, fn (a, b) -> a + b)
    end
  end|} in
  let pipeline_fn =
    List.find (fun fd -> fd.Tir.fn_name = "pipeline") tir.Tir.tm_fns in
  let allocs = count_list_allocs pipeline_fn.Tir.fn_body in
  Alcotest.(check int) "fused pipeline has zero intermediate list allocs in hot path" 0 allocs
```

- [ ] **Step 4.2: Run to verify fail (fusion is still a stub)**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep "no_intermediate_allocs"
```

Expected: FAIL (the unfused `pipeline` still has `ICons` allocs).

- [ ] **Step 4.3: Implement `emit_fused_loop` and `fuse_fn_def` in `lib/tir/fusion.ml`**

```ocaml
(* ── Fresh name generation ──────────────────────────────────────── *)

let _fuse_counter = ref 0
let fresh_fused () =
  incr _fuse_counter;
  Printf.sprintf "$fused_%d" !_fuse_counter

(** Build the body of the fused loop function.

    The loop has signature: fused(seed : ListTy, acc : AccTy) : AccTy.
    seed is the tail of the source list; acc is the fold accumulator.

    For each element h from the list:
    1. Apply all StMap steps in sequence
    2. For each StFilter step, check the predicate — if false, skip to tail recursion
    3. Apply the consumer (fold_f) to update acc
    4. Tail-recurse on the list tail

    This is a standard stream fusion loop. *)
let build_fused_body
    (loop_name : string)
    (seed_var  : Tir.var)
    (acc_var   : Tir.var)
    (tail_var  : Tir.var)
    (elem_var  : Tir.var)
    (ch        : chain)
  : Tir.expr =
  (* Build the chain of map/filter applications *)
  let rec build_chain (steps : chain_step list) (current : Tir.var) : Tir.expr =
    match steps with
    | [] ->
      (* At end of steps: apply consumer *)
      let new_acc_var = { Tir.v_name = fresh_fused (); v_ty = acc_var.Tir.v_ty; v_lin = Tir.Unr } in
      let recurse = Tir.EApp (
        { Tir.v_name = loop_name; v_ty = Tir.TUnit; v_lin = Tir.Unr },
        [Tir.AVar tail_var; Tir.AVar new_acc_var]
      ) in
      (match ch.ch_consumer with
       | ConFold (_, fold_f) ->
         Tir.ELet (new_acc_var,
           Tir.ECallPtr (fold_f, [Tir.AVar acc_var; Tir.AVar current]),
           recurse)
       | ConSum ->
         Tir.ELet (new_acc_var,
           Tir.EApp ({ Tir.v_name = "+"; v_ty = Tir.TUnit; v_lin = Tir.Unr },
                     [Tir.AVar acc_var; Tir.AVar current]),
           recurse)
       | ConCount ->
         Tir.ELet (new_acc_var,
           Tir.EApp ({ Tir.v_name = "+"; v_ty = Tir.TUnit; v_lin = Tir.Unr },
                     [Tir.AVar acc_var; Tir.ALit (March_ast.Ast.LInt 1)]),
           recurse))
    | StMap fa :: rest ->
      let out = { Tir.v_name = fresh_fused (); v_ty = Tir.TVar "_"; v_lin = Tir.Unr } in
      Tir.ELet (out, Tir.ECallPtr (fa, [Tir.AVar current]), build_chain rest out)
    | StFilter pred_atom :: rest ->
      (* If pred is false, recurse with same acc (skip); if true, continue chain *)
      let recurse_skip = Tir.EApp (
        { Tir.v_name = loop_name; v_ty = Tir.TUnit; v_lin = Tir.Unr },
        [Tir.AVar tail_var; Tir.AVar acc_var]
      ) in
      let keep_branch = { Tir.br_tag = "true";  Tir.br_vars = []; Tir.br_body = build_chain rest current } in
      let skip_branch = { Tir.br_tag = "false"; Tir.br_vars = []; Tir.br_body = recurse_skip } in
      let test_var = { Tir.v_name = fresh_fused (); v_ty = Tir.TBool; v_lin = Tir.Unr } in
      Tir.ELet (test_var,
        Tir.ECallPtr (pred_atom, [Tir.AVar current]),
        Tir.ECase (Tir.AVar test_var, [keep_branch; skip_branch], None))
  in

  (* Match on the list: Nil → return acc; Cons(h, t) → apply chain *)
  let nil_branch = { Tir.br_tag = "INil"; Tir.br_vars = []; Tir.br_body = Tir.EAtom (Tir.AVar acc_var) } in
  let cons_branch = {
    Tir.br_tag = "ICons";
    Tir.br_vars = [elem_var; tail_var];
    Tir.br_body = build_chain ch.ch_steps elem_var;
  } in
  Tir.ECase (Tir.AVar seed_var, [nil_branch; cons_branch], None)

(** Emit a fused loop for [ch] sourced from [source_atom].
    Returns: (ELetRec wrapping the fused fn, call to the fused fn). *)
let emit_fused_loop
    (ch          : chain)
    (source_atom : Tir.atom)
    (ret_ty      : Tir.ty)
  : Tir.expr =
  let loop_name = fresh_fused () in
  let list_ty = match source_atom with
    | Tir.AVar v -> v.Tir.v_ty
    | _ -> Tir.TCon ("IntList", [])
  in
  let (zero_atom, acc_ty) = match ch.ch_consumer with
    | ConFold (zero, _) ->
      let ty = match zero with Tir.AVar v -> v.Tir.v_ty | _ -> ret_ty in
      (zero, ty)
    | ConSum | ConCount -> (Tir.ALit (March_ast.Ast.LInt 0), Tir.TInt)
  in
  let seed_var = { Tir.v_name = fresh_fused (); v_ty = list_ty; v_lin = Tir.Unr } in
  let acc_var  = { Tir.v_name = fresh_fused (); v_ty = acc_ty;  v_lin = Tir.Unr } in
  let elem_var = { Tir.v_name = fresh_fused (); v_ty = Tir.TVar "_"; v_lin = Tir.Unr } in
  let tail_var = { Tir.v_name = fresh_fused (); v_ty = list_ty; v_lin = Tir.Unr } in
  let fused_fn : Tir.fn_def = {
    Tir.fn_name   = loop_name;
    Tir.fn_params = [seed_var; acc_var];
    Tir.fn_ret_ty = acc_ty;
    Tir.fn_body   = build_fused_body loop_name seed_var acc_var tail_var elem_var ch;
  } in
  let call = Tir.EApp (
    { Tir.v_name = loop_name; v_ty = Tir.TUnit; v_lin = Tir.Unr },
    [source_atom; zero_atom]
  ) in
  Tir.ELetRec ([fused_fn], call)

(** Rewrite function body: find the first pure chain, fuse it, repeat.
    [m] is threaded through for purity checking. *)
let rec rewrite_body (m : Tir.tir_module) (fd : Tir.fn_def) : Tir.fn_def =
  let chains = find_chains fd in
  let pure_chains = List.filter (chain_is_pure m) chains in
  match pure_chains with
  | [] -> fd
  | ch :: _ ->
    (* Find the source atom (the var that feeds the first step) *)
    let source_atom = Tir.AVar { Tir.v_name = ch.ch_source_var;
                                  v_ty = Tir.TCon("IntList", []); v_lin = Tir.Unr } in
    let fused_expr = emit_fused_loop ch source_atom fd.Tir.fn_ret_ty in
    (* Replace the chain in the body with fused_expr *)
    let new_body = replace_chain ch fused_expr fd.Tir.fn_body in
    let new_fd = { fd with Tir.fn_body = new_body } in
    (* Iterate in case multiple chains exist *)
    rewrite_body m new_fd

(** Replace the let-chain matching [ch] with [replacement] in [expr].
    Identifies the chain start by matching on [ch.ch_first_let_var] — the name
    bound by the FIRST ELet of the chain.  All subsequent ELets in the chain are
    consumed by the fused loop; the rest of the expression after the chain is
    preserved unchanged. *)
and replace_chain (ch : chain) (replacement : Tir.expr) (expr : Tir.expr) : Tir.expr =
  match expr with
  | Tir.ELet (bound, (Tir.EApp _ as _rhs), rest) when bound.Tir.v_name = ch.ch_first_let_var ->
    (* This ELet is the start of the chain.  Drop the entire chain (all subsequent
       ELets up to and including the consumer) and substitute [replacement]. *)
    ignore rest;  (* the consumer and all intermediate bindings are fused away *)
    replacement
  | Tir.ELet (bound, rhs, rest) ->
    Tir.ELet (bound, rhs, replace_chain ch replacement rest)
  | _ -> expr

let fuse_fn_def (m : Tir.tir_module) (fd : Tir.fn_def) : Tir.fn_def =
  let chains = find_chains fd in
  (* Only fuse chains whose step functions are provably pure *)
  let pure_chains = List.filter (chain_is_pure m) chains in
  if pure_chains = [] then fd else rewrite_body m fd

let fuse (m : Tir.tir_module) : Tir.tir_module =
  { m with Tir.tm_fns = List.map (fuse_fn_def m) m.Tir.tm_fns }
```

> **Note:** `chain_is_pure` and `rewrite_body` are both defined earlier in the module (see Step 3.4 detection stub and this step's rewrite code). The final module has them in source order: detection helpers → `find_chains` → `chain_is_pure` → `emit_fused_loop` → `build_fused_body` → `replace_chain` → `rewrite_body` → `fuse_fn_def` → `fuse`.

- [ ] **Step 4.4: Wire fusion into the pipeline in `bin/main.ml`**

Find line 350 (`let tir = March_tir.Perceus.perceus tir in`) and insert before it:

```ocaml
let tir = March_tir.Fusion.fuse tir in
```

So the sequence becomes:
```ocaml
let tir = March_tir.Lower.lower_module ~type_map desugared in
let tir = March_tir.Mono.monomorphize tir in
let tir = March_tir.Defun.defunctionalize tir in
let tir = March_tir.Fusion.fuse tir in          (* NEW *)
let tir = March_tir.Perceus.perceus tir in
let tir = March_tir.Escape.escape_analysis tir in
let tir = if !opt_enabled then March_tir.Opt.run tir else tir in
```

- [ ] **Step 4.5: Build**

```bash
/Users/80197052/.opam/march/bin/dune build 2>&1
```

Expected: clean build.

- [ ] **Step 4.6: Run TIR inspection test**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep -E "stream_fusion|no_intermediate"
```

Expected: `no_intermediate_allocs  PASS`.

- [ ] **Step 4.7: Run full test suite to check for regressions**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | tail -20
```

Expected: all existing tests still pass (fusion is a no-op for functions that have no fusible chains).

- [ ] **Step 4.8: Commit**

```bash
git add lib/tir/fusion.ml bin/main.ml test/test_march.ml
git commit -m "feat(fusion): implement fused loop emission, wire into pipeline"
```

---

### Phase 3: Benchmark Validation

**Goal:** Confirm the benchmark improves; confirm no regressions.

#### Task 5: Run list-ops benchmark before and after

- [ ] **Step 5.1: Baseline (should already be in RESULTS.md — 117ms)**

```bash
cd /Users/80197052/code/march/.claude/worktrees/determined-rosalind
/Users/80197052/.opam/march/bin/dune build
time bash bench/run_benchmarks.sh 2>&1 | grep -A5 "list-ops"
```

Expected baseline: ~117ms median.

- [ ] **Step 5.2: Build with fusion enabled and run benchmark**

```bash
/Users/80197052/.opam/march/bin/dune build
bash bench/run_benchmarks.sh 2>&1 | grep -A5 "list-ops"
```

Target: median ≤ 60ms (2× improvement minimum; goal is ≤57ms, which is within 2× of OCaml's 28.5ms).

- [ ] **Step 5.3: Write a benchmark regression test**

Add to the `"stream_fusion"` test suite (as a `Slow` test so CI can skip it):

```ocaml
(** End-to-end eval correctness for the fusion benchmark.
    This uses the interpreter, not native code — checks correctness, not speed. *)
let test_fusion_benchmark_correct () =
  let env = eval_module {|mod ListOps do
    type IntList = INil | ICons(Int, IntList)
    fn irev(xs : IntList, acc : IntList) : IntList do
      match xs do
      | INil        -> acc
      | ICons(h, t) -> irev(t, ICons(h, acc))
      end
    end
    fn irange_acc(lo : Int, hi : Int, acc : IntList) : IntList do
      if lo > hi then acc
      else irange_acc(lo + 1, hi, ICons(lo, acc))
    end
    fn irange(lo : Int, hi : Int) : IntList do
      irev(irange_acc(lo, hi, INil), INil)
    end
    fn imap(xs : IntList, f : Int -> Int) : IntList do
      match xs do
      | INil        -> INil
      | ICons(h, t) -> ICons(f(h), imap(t, f))
      end
    end
    fn ifilter(xs : IntList, pred : Int -> Bool) : IntList do
      match xs do
      | INil        -> INil
      | ICons(h, t) ->
        if pred(h) then ICons(h, ifilter(t, pred))
        else ifilter(t, pred)
      end
    end
    fn ifold(xs : IntList, acc : Int, f : Int -> Int -> Int) : Int do
      match xs do
      | INil        -> acc
      | ICons(h, t) -> ifold(t, f(acc, h), f)
      end
    end
    fn run(n : Int) : Int do
      let xs    = irange(1, n)
      let ys    = imap(xs, fn x -> x * 2)
      let zs    = ifilter(ys, fn x -> x % 3 == 0)
      ifold(zs, 0, fn (a, b) -> a + b)
    end
  end|} in
  (* range(1,10): doubled = [2,4,6,8,10,12,14,16,18,20], multiples of 3 = [6,12,18], sum = 36 *)
  let v = call_fn env "run" [March_eval.Eval.VInt 10] in
  Alcotest.(check int) "fusion benchmark gives correct result for n=10" 36 (vint v)
```

Register as `Slow`:
```ocaml
Alcotest.test_case "benchmark correctness n=10" `Slow test_fusion_benchmark_correct;
```

- [ ] **Step 5.4: Run correctness test**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep "benchmark_correct"
```

Expected: PASS with value 36.

- [ ] **Step 5.5: Update RESULTS.md with new timings**

If benchmark improves, update `bench/RESULTS.md` with new timings and add a note about fusion.

- [ ] **Step 5.6: Commit**

```bash
git add bench/RESULTS.md test/test_march.ml
git commit -m "bench(fusion): update list-ops results after stream fusion"
```

---

### Phase 4: Edge Cases

**Goal:** Verify correctness under edge cases. Test multi-use intermediates, effectful maps, zip fusion, and bounded streams.

#### Task 6: Multi-use and effectful guards

**Files:**
- Modify: `test/test_march.ml` (add edge case tests)
- Modify: `lib/tir/fusion.ml` (guard on `ECallPtr` impurity)

- [ ] **Step 6.1: Write tests — multi-use not fused**

```ocaml
let test_fusion_multi_use_not_fused () =
  (* If ys is used twice, it must NOT be fused — the list must be materialized *)
  let env = eval_module {|mod Test do
    fn main() : Int do
      let xs = Cons(1, Cons(2, Cons(3, Nil)))
      let ys = List.map(xs, fn x -> x * 2)
      -- use ys twice: sum + length
      let s = List.fold_left(0, ys, fn (a, b) -> a + b)
      let n = List.length(ys)
      s + n
    end
  end|} in
  let v = call_fn env "main" [] in
  (* sum([2,4,6]) = 12, length([2,4,6]) = 3, result = 15 *)
  Alcotest.(check int) "multi-use intermediate gives correct result" 15 (vint v)

let test_fusion_empty_list () =
  let env = eval_module {|mod Test do
    fn main() : Int do
      let xs = Nil
      let ys = List.map(xs, fn x -> x * 2)
      let zs = List.filter(ys, fn x -> x > 0)
      List.fold_left(0, zs, fn (a, b) -> a + b)
    end
  end|} in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "fusion over empty list gives 0" 0 (vint v)

let test_fusion_singleton_list () =
  let env = eval_module {|mod Test do
    fn main() : Int do
      let xs = Cons(5, Nil)
      let ys = List.map(xs, fn x -> x * 3)
      let zs = List.filter(ys, fn x -> x > 10)
      List.fold_left(0, zs, fn (a, b) -> a + b)
    end
  end|} in
  let v = call_fn env "main" [] in
  (* 5 * 3 = 15 > 10 → sum = 15 *)
  Alcotest.(check int) "fusion over singleton [5]: map*3, filter>10, sum = 15" 15 (vint v)

let test_fusion_filter_removes_all () =
  let env = eval_module {|mod Test do
    fn main() : Int do
      let xs = Cons(1, Cons(2, Cons(3, Nil)))
      let ys = List.filter(xs, fn x -> x > 100)
      List.fold_left(0, ys, fn (a, b) -> a + b)
    end
  end|} in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "filter-all: sum = 0" 0 (vint v)
```

- [ ] **Step 6.2: Run tests**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep "stream_fusion"
```

Expected: all PASS.

- [ ] **Step 6.3: Add purity guard to fusion pass**

In `lib/tir/fusion.ml`, before emitting a fused loop for a chain, verify that all step function atoms are pure. Add a helper:

```ocaml
(** Check if a step function atom is provably pure.
    For ADefRef, look up the function in the module and run Purity.is_pure.
    For AVar pointing to a closure, look up the dispatch function.
    Conservative: unknown → impure. *)
let step_atom_is_pure (m : Tir.tir_module) (a : Tir.atom) : bool =
  match a with
  | Tir.ADefRef did ->
    (match List.find_opt (fun fd -> fd.Tir.fn_name = did.Tir.did_name) m.Tir.tm_fns with
     | Some fd -> Purity.is_pure fd.Tir.fn_body
     | None -> false)
  | Tir.AVar v ->
    (* After defun, a closure var's type is TFn — look for the dispatch function *)
    let dispatch_name = v.Tir.v_name ^ "_apply" in
    (match List.find_opt (fun fd -> fd.Tir.fn_name = dispatch_name) m.Tir.tm_fns with
     | Some fd -> Purity.is_pure fd.Tir.fn_body
     | None -> false)  (* conservative: don't fuse unknown closures *)
  | _ -> false

let chain_is_pure (m : Tir.tir_module) (ch : chain) : bool =
  List.for_all (function
    | StMap fa | StFilter fa -> step_atom_is_pure m fa
  ) ch.ch_steps
  &&
  match ch.ch_consumer with
  | ConFold (_, fold_f) -> step_atom_is_pure m fold_f
  | ConSum | ConCount -> true
```

**Important:** `rewrite_body` must also be updated to accept and thread `m` for purity checking (see the corrected signature in Step 4.3: `rewrite_body (m : Tir.tir_module) (fd : Tir.fn_def)`). The updated `fuse_fn_def` and `fuse` already use this signature.

The final versions of `fuse_fn_def` and `fuse` (shown below) supersede the stub in Step 3.4:

```ocaml
let fuse_fn_def (m : Tir.tir_module) (fd : Tir.fn_def) : Tir.fn_def =
  let chains = find_chains fd in
  let pure_chains = List.filter (chain_is_pure m) chains in
  if pure_chains = [] then fd else rewrite_body m fd

let fuse (m : Tir.tir_module) : Tir.tir_module =
  { m with Tir.tm_fns = List.map (fuse_fn_def m) m.Tir.tm_fns }
```

- [ ] **Step 6.4: Write test — effectful map is NOT fused**

```ocaml
let test_fusion_effectful_not_fused () =
  (* map with println (side effect) must not be fused — println must execute once per element *)
  let env = eval_module {|mod Test do
    fn main() : Int do
      let xs = Cons(1, Cons(2, Cons(3, Nil)))
      -- println is impure; fusion must be suppressed
      let ys = List.map(xs, fn x -> do
        println(int_to_string(x))
        x * 2
      end)
      List.fold_left(0, ys, fn (a, b) -> a + b)
    end
  end|} in
  let v = call_fn env "main" [] in
  (* correctness must hold even if fusion is suppressed *)
  Alcotest.(check int) "effectful map: correct result even if not fused" 12 (vint v)
```

- [ ] **Step 6.5: Run all edge case tests**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep "stream_fusion"
```

Expected: all PASS.

- [ ] **Step 6.6: Commit**

```bash
git add lib/tir/fusion.ml test/test_march.ml
git commit -m "feat(fusion): add purity guard, edge case tests (multi-use, empty, effectful)"
```

---

#### Task 7: Nested fusion chains and take/drop

- [ ] **Step 7.1: Write tests for take/drop and nested chains**

```ocaml
let test_stream_take () =
  let env = eval_module {|mod Test do
    fn main() : Int do
      Cons(1, Cons(2, Cons(3, Cons(4, Cons(5, Nil)))))
      |> Stream.of_list
      |> Stream.take(3)
      |> Stream.to_list
      |> List.fold_left(0, fn (a, b) -> a + b)   -- sum of first 3
    end
  end|} in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "stream_take(3): sum [1,2,3] = 6" 6 (vint v)

let test_stream_drop () =
  let env = eval_module {|mod Test do
    fn main() : Int do
      Cons(1, Cons(2, Cons(3, Cons(4, Cons(5, Nil)))))
      |> Stream.of_list
      |> Stream.drop(2)
      |> Stream.to_list
      |> List.fold_left(0, fn (a, b) -> a + b)   -- sum of [3,4,5]
    end
  end|} in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "stream_drop(2): sum [3,4,5] = 12" 12 (vint v)

let test_stream_map_filter_map () =
  (* Two map steps with a filter in between *)
  let env = eval_module {|mod Test do
    fn main() : Int do
      -- [1..5] -> *2 -> [2,4,6,8,10] -> keep>5 -> [6,8,10] -> *2 -> [12,16,20] -> sum=48
      Cons(1, Cons(2, Cons(3, Cons(4, Cons(5, Nil)))))
      |> Stream.of_list
      |> Stream.map(fn x -> x * 2)
      |> Stream.filter(fn x -> x > 5)
      |> Stream.map(fn x -> x * 2)
      |> Stream.fold(0, fn (acc, x) -> acc + x)
    end
  end|} in
  let v = call_fn env "main" [] in
  Alcotest.(check int) "map|filter|map pipeline: 48" 48 (vint v)

let test_stream_zip () =
  let env = eval_module {|mod Test do
    fn main() : Int do
      let xs = Cons(1, Cons(2, Cons(3, Nil)))
      let ys = Cons(10, Cons(20, Cons(30, Nil)))
      Stream.zip(Stream.of_list(xs), Stream.of_list(ys))
      |> Stream.map(fn (a, b) -> a + b)
      |> Stream.fold(0, fn (acc, x) -> acc + x)
    end
  end|} in
  let v = call_fn env "main" [] in
  (* (1+10) + (2+20) + (3+30) = 11 + 22 + 33 = 66 *)
  Alcotest.(check int) "stream_zip sum = 66" 66 (vint v)

let test_stream_enumerate () =
  let env = eval_module {|mod Test do
    fn main() : Int do
      Cons(10, Cons(20, Cons(30, Nil)))
      |> Stream.of_list
      |> Stream.enumerate
      |> Stream.fold(0, fn (acc, pair) -> let (i, v) = pair in acc + i * v)
    end
  end|} in
  let v = call_fn env "main" [] in
  (* 0*10 + 1*20 + 2*30 = 0 + 20 + 60 = 80 *)
  Alcotest.(check int) "stream_enumerate: weighted sum = 80" 80 (vint v)
```

- [ ] **Step 7.2: Run tests**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep "stream_fusion"
```

Expected: all PASS.

- [ ] **Step 7.3: Commit**

```bash
git add test/test_march.ml
git commit -m "test(fusion): add take/drop, nested map/filter/map, zip, enumerate tests"
```

---

### Phase 5: Stdlib Integration

**Goal:** Make the stdlib list functions (`List.map`, `List.filter`, `List.fold_left`, `Iterable.map`, etc.) fusion-friendly by recognizing them in the fusion pass.

#### Task 8: Extend fusible name table + add iterable pipeline tests

- [ ] **Step 8.1: Write test — stdlib list pipeline is fused**

```ocaml
let test_fusion_stdlib_list_pipeline () =
  (* Use stdlib List functions — fusion must recognize and fuse them *)
  let tir = tir_of_source {|mod Test do
    fn pipeline(xs : List(Int)) : Int do
      let ys = List.map(xs, fn x -> x * 2)
      let zs = List.filter(ys, fn x -> x % 3 == 0)
      List.fold_left(0, zs, fn (acc, x) -> acc + x)
    end
  end|} in
  let fns_with_allocs = List.filter_map (fun fd ->
    let n = count_list_allocs fd.Tir.fn_body in
    if n > 0 && fd.Tir.fn_name = "pipeline" then Some (fd.Tir.fn_name, n)
    else None
  ) tir.Tir.tm_fns in
  Alcotest.(check int) "stdlib pipeline: pipeline fn has no intermediate list allocs"
    0 (List.length fns_with_allocs)

let test_fusion_iterable_pipeline () =
  let env = eval_module {|mod Test do
    fn main() : Int do
      let xs = Cons(1, Cons(2, Cons(3, Cons(4, Cons(5, Nil)))))
      xs
      |> Iterable.map(fn x -> x * 2)
      |> Iterable.filter(fn x -> x % 2 == 0)
      |> Iterable.fold(0, fn (acc, x) -> acc + x)
    end
  end|} in
  let v = call_fn env "main" [] in
  (* [1..5] -> *2 -> [2,4,6,8,10] -> all even -> sum=30 *)
  Alcotest.(check int) "Iterable pipeline sum=30" 30 (vint v)
```

- [ ] **Step 8.2: Extend fusible name tables in `lib/tir/fusion.ml`**

Update the `fusible_map_names`, `fusible_filter_names`, `fusible_fold_names` lists to include all monomorphized stdlib names that Mono+Defun produce. The exact names depend on monomorphization (e.g., `List$map$Int$Int`, or `list_map_Int_Int`).

To discover the exact names, add a debug dump:

```bash
# Compile a simple pipeline and dump TIR to inspect function names
echo 'mod T do
  fn main() : Int do
    let xs = Cons(1, Nil)
    let ys = List.map(xs, fn x -> x * 2)
    List.fold_left(0, ys, fn (a, b) -> a + b)
  end
end' > /tmp/t.march
/Users/80197052/.opam/march/bin/dune exec march -- --dump-tir /tmp/t.march 2>&1 | grep -E "^fn " | head -30
```

Add the discovered names to the fusible name tables.

- [ ] **Step 8.3: Run stdlib integration tests**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep "stream_fusion"
```

Expected: all PASS including `stdlib_list_pipeline` and `iterable_pipeline`.

- [ ] **Step 8.4: Run full test suite — final regression check**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1
```

Expected: all 1127+ tests pass. Zero regressions.

- [ ] **Step 8.5: Update specs**

In `specs/todos.md`, move the stream fusion item to the Done section.

In `specs/progress.md`:
- Update test count to reflect new tests added
- Add to feature bullet list: "Stream fusion (deforestation): fuses map/filter/fold chains into single loops, eliminating intermediate allocations. Transparent — no user code changes."

- [ ] **Step 8.6: Final commit**

```bash
git add lib/tir/fusion.ml stdlib/stream.march specs/todos.md specs/progress.md test/test_march.ml
git commit -m "feat(fusion): stream fusion pass — transparent deforestation of list combinator chains

Eliminates intermediate list allocations in map/filter/fold pipelines.
New pass: lib/tir/fusion.ml (runs after Defun, before Perceus).
New stdlib: stdlib/stream.march (user-facing Stream module).
Target: list-ops benchmark ≤ 2× OCaml (was 4×).

Closes #stream-fusion"
```

---

## 8. Risks and Mitigations

### 8.1  Code size blowup from inlining step functions

**Risk:** Each fused chain generates a new `ELetRec` function. For large programs with many pipelines, this could increase binary size.

**Mitigation:** The fused loop is typically smaller than the original (no intermediate list nodes, no list spine allocations). The Opt pass's DCE will remove any dead code from the original unfused functions after they're no longer called. Additionally, the `inline_size_threshold = 15` in the existing Inline pass limits how aggressively step functions are inlined — fusion operates at a higher level.

### 8.2  Interaction with Perceus reuse analysis

**Risk:** Perceus looks for `EAlloc` nodes with RC=1 for FBIP reuse. If fusion eliminates `EAlloc(Cons, ...)` nodes, Perceus has less to analyze. But this is fine — a loop that doesn't allocate doesn't need Perceus to optimize allocation away.

**Mitigation:** The source list (`xs` in `map(xs, f)`) is still analyzed by Perceus. Since the fused loop consumes `xs` sequentially with tail calls, Perceus will detect the spine nodes as last-use and emit `EFree` (or `EReuse` if RC=1) for each `Cons` cell. This is the same behavior as the unfused case, and correct.

### 8.3  Debugging difficulty (fused code is hard to step through)

**Risk:** Users stepping through code in a debugger or REPL will see the fused loop, not their original `map |> filter |> fold` calls. This makes source-level debugging harder.

**Mitigation:** Fusion is controlled by the same `--opt` flag as the rest of the optimization pipeline. When `--opt 0` is passed, `Fusion.fuse` is a no-op (same as `Opt.run` being skipped). The REPL always uses the interpreter (`March_eval.Eval`), not the TIR pipeline, so REPL debugging is unaffected.

### 8.4  Semantics changes with effectful operations

**Risk:** If a user's `map` function has side effects (e.g., `println`), fusing could change the order of effects or skip them entirely.

**Mitigation:** The purity guard in `chain_is_pure` prevents fusion when any step function is impure. The existing `Purity.is_pure` oracle treats `println`, `send`, and all I/O as impure. In the worst case (false negative from purity analysis), an impure chain is not fused — correctness is maintained at the cost of performance. The conservative direction is always taken.

---

## 9. Success Criteria

Before marking this feature done, ALL of the following must hold:

| Criterion | Measurement | Target |
|-----------|-------------|--------|
| list-ops benchmark improvement | `bash bench/run_benchmarks.sh` median | ≤ 57ms (within 2× OCaml's 28.5ms) |
| No regressions on fib(40) | Same benchmark script | Within 5% of pre-fusion baseline |
| No regressions on binary-trees | Same benchmark script | Within 5% of pre-fusion baseline |
| No regressions on tree-transform | Same benchmark script | Within 5% of pre-fusion baseline |
| All existing tests pass | `dune runtest` | 0 failures |
| Fusion is transparent | Existing test programs produce identical output | All test programs pass unchanged |
| New stream tests pass | `dune runtest` → `stream_fusion` suite | All PASS |
| TIR has no intermediate allocs in fused pipeline | `count_list_allocs` test | 0 allocs in `pipeline` fn |

---

## 10. Appendix: TIR Pseudocode Reference

### Unfused benchmark TIR (after Lower→Mono→Defun)

```
fn main() : TInt =
  ELet(n,    EAtom(ALit(LInt 1000000)),
  ELet(xs,   EApp(irange, [ALit(LInt 1); AVar n]),
  ELet(dbl,  EAlloc(TDClosure_anon_double, []),   (* fn x -> x * 2 *)
  ELet(ys,   EApp(imap, [AVar xs; AVar dbl]),     (* allocates ~1M ICons cells *)
  ELet(m3,   EAlloc(TDClosure_anon_mod3, []),     (* fn x -> x % 3 == 0 *)
  ELet(zs,   EApp(ifilter, [AVar ys; AVar m3]),   (* allocates ~333K ICons cells *)
  ELet(add,  EAlloc(TDClosure_anon_add, []),      (* fn (a,b) -> a + b *)
  EApp(ifold, [AVar zs; ALit(LInt 0); AVar add]))))))))
```

Allocations on hot path: ~1.333M `ICons` cells for `ys` and `zs`.

### After fusion — `main` body

```
fn main() : TInt =
  ELet(n,    EAtom(ALit(LInt 1000000)),
  ELet(xs,   EApp(irange, [ALit(LInt 1); AVar n]),
  ELetRec([{
    fn_name   = "$fused_1";
    fn_params = [seed : TCon("IntList",[]); acc : TInt];
    fn_ret_ty = TInt;
    fn_body   =
      ECase(AVar seed,
        [{ br_tag = "INil"; br_vars = [];
           br_body = EAtom(AVar acc) }
        ;{ br_tag = "ICons"; br_vars = [h : TInt; t : TCon("IntList",[])];
           br_body =
             (* apply StMap(double_closure): v = ECallPtr(dbl, [h]) *)
             ELet(v, ECallPtr(AVar dbl, [AVar h]),
             (* apply StFilter(mod3_closure): test = ECallPtr(m3, [v]) *)
             ELet(test, ECallPtr(AVar m3, [AVar v]),
             ECase(AVar test,
               [{ br_tag = "true";  br_vars = [];
                  br_body = ELet(acc2, EApp(+, [AVar acc; AVar v]),
                             EApp($fused_1, [AVar t; AVar acc2])) }
               ;{ br_tag = "false"; br_vars = [];
                  br_body = EApp($fused_1, [AVar t; AVar acc]) }],
               None))) }],
        None)
  }],
  EApp($fused_1, [AVar xs; ALit(LInt 0)]))))
```

Allocations on hot path: **zero** `ICons` cells. The closure dispatch `ECallPtr(dbl, [h])` and `ECallPtr(m3, [v])` will be further reduced by the Inline pass (if the closures are small enough) into direct `EApp(*, [h; ALit 2])` and `EApp(%, [v; ALit 3])` operations.

### After Opt(Inline) — fully specialized fused loop

After Inline inlines the closure dispatch functions (each is 2 nodes, well under the threshold of 15):

```
fn $fused_1(seed : TCon("IntList",[]), acc : TInt) : TInt =
  ECase(AVar seed,
    [{ br_tag = "INil"; br_vars = [];
       br_body = EAtom(AVar acc) }
    ;{ br_tag = "ICons"; br_vars = [h; t];
       br_body =
         ELet(v, EApp(*, [AVar h; ALit(LInt 2)]),          (* x * 2, direct *)
         ELet(rem, EApp(%, [AVar v; ALit(LInt 3)]),        (* v % 3, direct *)
         ECase(AVar rem,
           [{ br_tag = "0_eq"; br_vars = [];               (* rem == 0 *)
              br_body = ELet(acc2, EApp(+, [AVar acc; AVar v]),
                         EApp($fused_1, [AVar t; AVar acc2])) }
           ;{ br_tag = "_"; br_vars = [];
              br_body = EApp($fused_1, [AVar t; AVar acc]) }],
           None))) }],
    None)
```

This is a tight, allocation-free tail-recursive loop. LLVM will compile this to a machine loop with no heap allocation, matching Rust's iterator performance.
