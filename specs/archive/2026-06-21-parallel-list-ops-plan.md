# Parallel List Operations + Parallelization Lint — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `List.pmap`/`pmap_n`/`pfilter`/`preduce` to the stdlib, a compiler-configurable `--pmap-threshold` cutoff, and an LSP hint + quick-fix that suggests parallelizing pure `List.map`/`List.filter` calls.

**Architecture:** The parallel functions are thin, order-preserving March wrappers over the existing `task_spawn`/`task_await_unwrap` scheduler (real parallelism in compiled code; correct-but-sequential in the interpreter). They chunk the input with the existing `List.chunks` helper and spawn one task per chunk. A new nullary builtin `pmap_threshold()` returns a compile-time/interpreter-time constant set by `--pmap-threshold` (default 1024) below which the wrappers fall back to sequential. The lint reuses the existing `Purity.impure_builtins` whitelist and the LSP `perf_insight` framework to flag pure map/filter calls as `Hint`s with a "Convert to parallel" code action.

**Tech Stack:** OCaml 5.3 (compiler: typecheck/eval/tir/lsp), March (stdlib), C runtime (already complete — no changes), Alcotest + `.march` test files.

---

## File Structure

| File | Responsibility | Change |
|------|----------------|--------|
| `lib/typecheck/typecheck.ml` | Register `pmap_threshold : Fn(()) -> Int` builtin | Modify (~line 1369) |
| `lib/eval/eval.ml` | `pmap_threshold_value` ref + builtin returning it | Modify (~line 354, ~7134) |
| `lib/tir/llvm_emit.ml` | Emit `pmap_threshold()` as constant i64; thread value through `ctx` | Modify (~line 27, 161, 2316, 5135) |
| `bin/main.ml` | Parse `--pmap-threshold=N`; wire into eval ref + `emit_module` | Modify (~line 446, 1243, 1435, 1884) |
| `forge/lib/cmd_build.ml` | Pass `--pmap-threshold` through to `march --compile` | Modify (~line 244) |
| `stdlib/list.march` | `pmap`, `pmap_n`, `pfilter`, `preduce` | Modify (append after `filter`) |
| `lsp/lib/analysis.ml` | `Parallelizable` perf_insight + detection + code action | Modify (~line 120, 1561, 1738, 6372) |
| `test/stdlib/test_list.march` | Behavioural tests (interpreter, `Quick`) | Modify |
| `test/test_codegen.ml` | Compiled↔interpreter parity test (`Slow`) | Modify |
| `lsp/test/` | Lint hint + code-action test | Modify |
| `specs/todos.md`, `specs/progress.md` | Record feature | Modify |

**Important pre-existing facts (verified):**
- `List.chunks(xs, size) : List(List(a))` already exists at `stdlib/list.march:555` — order-preserving. **Reuse it; do not add a chunk helper.**
- `List.map`/`filter`/`fold_left`/`concat`/`length`/`take`/`drop` all exist.
- `task_spawn : Fn(Int) -> a) -> Task(a)` and `task_await_unwrap : Task(a) -> a` exist (`stdlib/task.march`, registered `typecheck.ml:1364-1366`). In the interpreter, `task_spawn` runs the thunk eagerly, so the wrappers are correct (sequential) there.
- `task_reductions` (`typecheck.ml:1369`, `eval.ml:7134`, `llvm_emit.ml:2316`) is the exact template for a nullary Int builtin.
- `Purity.impure_builtins : string list` is public (`lib/tir/purity.ml:12`).

---

## Task 1: Register the `pmap_threshold` builtin in the typechecker

**Files:**
- Modify: `lib/typecheck/typecheck.ml:1369`

- [ ] **Step 1: Add the type registration**

In the builtin list, immediately after the `task_reductions` line (1369), add:

```ocaml
    ("pmap_threshold",     Mono (TArrow (t_unit, t_int)));
```

- [ ] **Step 2: Build to verify it typechecks**

Run: `dune build lib/typecheck/ 2>&1 | head -20`
Expected: clean build (no errors).

- [ ] **Step 3: Commit**

```bash
git add lib/typecheck/typecheck.ml
git commit -m "feat(typecheck): register pmap_threshold builtin"
```

---

## Task 2: Implement `pmap_threshold` in the interpreter

**Files:**
- Modify: `lib/eval/eval.ml` (add ref near line 354; add builtin near line 7134)
- Test: `test/stdlib/test_list.march`

- [ ] **Step 1: Write the failing test**

Append a new `describe` block to `test/stdlib/test_list.march` (before the final `end` that closes `mod TestList`):

```march
describe "pmap_threshold builtin" do
  test "default threshold is positive" do
    assert (pmap_threshold() > 0)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `dune build test/run_stdlib.exe && ./_build/default/test/run_stdlib.exe -e 2>&1 | grep -i 'pmap_threshold\|FAIL' | head`
Expected: FAIL — `pmap_threshold` is unbound at eval (builtin not yet in the value env).

- [ ] **Step 3: Add the config ref**

In `lib/eval/eval.ml`, near the other module-level refs (after `logger_level` at line 354), add:

```ocaml
(* Sequential-fallback cutoff for List.pmap/pfilter/preduce, set by
   bin/main.ml from --pmap-threshold (default 1024). *)
let pmap_threshold_value : int ref = ref 1024
```

- [ ] **Step 4: Add the builtin**

In the builtins list, immediately after the `task_reductions` builtin (ends line 7136), add:

```ocaml
  ; ("pmap_threshold", VBuiltin ("pmap_threshold", function
    | [] -> VInt !pmap_threshold_value
    | _ -> eval_error "pmap_threshold: expected 0 arguments"))
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `dune build test/run_stdlib.exe && ./_build/default/test/run_stdlib.exe -e 2>&1 | grep -i 'pmap_threshold\|FAIL\|tests run' | head`
Expected: the new test passes; no failures.

- [ ] **Step 6: Commit**

```bash
git add lib/eval/eval.ml test/stdlib/test_list.march
git commit -m "feat(eval): pmap_threshold builtin + configurable value"
```

---

## Task 3: Emit `pmap_threshold` as a constant in the LLVM backend

**Files:**
- Modify: `lib/tir/llvm_emit.ml` (ctx type ~27, `make_ctx` ~161, builtin allowlist ~374, codegen ~2316, `emit_module` ~5135)

- [ ] **Step 1: Add a field to the codegen context**

In the `type ctx = {` record (line 27), add a field alongside `fast_math : bool;` (line 49):

```ocaml
  pmap_threshold : int;
```

- [ ] **Step 2: Thread it through `make_ctx`**

Change `make_ctx` (line 161) from:

```ocaml
let make_ctx ?(fast_math=false) ?(repl=false) () = {
```

to:

```ocaml
let make_ctx ?(fast_math=false) ?(pmap_threshold=1024) ?(repl=false) () = {
```

and add `pmap_threshold;` to the record body next to `fast_math;` (line 172).

- [ ] **Step 3: Register the builtin name as a known direct-call builtin**

In the builtin-name list that includes `"task_reductions"` (lines 374-375), add `"pmap_threshold";` to the list so it is not treated as an unknown function.

- [ ] **Step 4: Add the codegen case**

Immediately after the `task_reductions` codegen case (ends line 2323), add:

```ocaml
  (* pmap_threshold() → compile-time constant i64 from --pmap-threshold *)
  | Tir.EApp (f, []) when f.Tir.v_name = "pmap_threshold" ->
    ("i64", string_of_int ctx.pmap_threshold)
```

- [ ] **Step 5: Plumb the value into `emit_module`**

Change `emit_module` (line 5135) from:

```ocaml
let emit_module ?(fast_math=false) ?(target=Native) (m : Tir.tir_module) : string =
```

to:

```ocaml
let emit_module ?(fast_math=false) ?(pmap_threshold=1024) ?(target=Native) (m : Tir.tir_module) : string =
```

and update its `make_ctx` call (line 5137) to pass `~pmap_threshold`:

```ocaml
  let ctx = make_ctx ~fast_math ~pmap_threshold () in
```

- [ ] **Step 6: Build to verify**

Run: `dune build lib/tir/ 2>&1 | head -20`
Expected: clean build.

- [ ] **Step 7: Commit**

```bash
git add lib/tir/llvm_emit.ml
git commit -m "feat(codegen): emit pmap_threshold as compile-time constant"
```

---

## Task 4: Wire the `--pmap-threshold` flag in the compiler driver

**Files:**
- Modify: `bin/main.ml` (ref ~446, flag spec ~1888, eval wiring + both `emit_module` calls 1243 & 1435)

- [ ] **Step 1: Add the global ref**

After `let fast_math = ref false` (line 443), add:

```ocaml
let pmap_threshold = ref 1024  (* --pmap-threshold: List.pmap sequential-fallback cutoff *)
```

- [ ] **Step 2: Add the Arg spec**

In the `Arg` spec list, after the `--fast-math` entry (line 1887), add:

```ocaml
    ("--pmap-threshold", Arg.Set_int pmap_threshold, "<N>  List.pmap/pfilter/preduce fall back to sequential below N elements (default 1024)");
```

- [ ] **Step 3: Propagate to the interpreter**

The interpreter path runs after argument parsing. Find where evaluation begins (search for `run_module` / the eval entry in the non-compile branch) and, right after `Arg.parse`/argument parsing completes but before any eval or codegen, set the eval ref. A safe location is immediately after the argument spec list is parsed; add:

```ocaml
  March_eval.Eval.pmap_threshold_value := !pmap_threshold;
```

(If a single obvious post-parse point isn't available, place this line at the top of both the eval branch and the compile branch.)

- [ ] **Step 4: Propagate to codegen (both call sites)**

At `bin/main.ml:1243` and `bin/main.ml:1435`, change:

```ocaml
let ir = March_tir.Llvm_emit.emit_module ~fast_math:!fast_math ~target tir in
```

to:

```ocaml
let ir = March_tir.Llvm_emit.emit_module ~fast_math:!fast_math ~pmap_threshold:!pmap_threshold ~target tir in
```

- [ ] **Step 5: Build the compiler**

Run: `dune build bin/main.exe 2>&1 | head -20`
Expected: clean build.

- [ ] **Step 6: Manually verify the flag flows to the interpreter**

Create `/tmp/pmt_bold-murdock-f5cadc.march`:

```march
fn main() do
  println(Int.to_string(pmap_threshold()))
end
```

Run: `./_build/default/bin/main.exe --pmap-threshold=77 /tmp/pmt_bold-murdock-f5cadc.march`
Expected output: `77`

Run without the flag: `./_build/default/bin/main.exe /tmp/pmt_bold-murdock-f5cadc.march`
Expected output: `1024`

- [ ] **Step 7: Commit**

```bash
git add bin/main.ml
git commit -m "feat(cli): --pmap-threshold flag wired to interpreter and codegen"
```

---

## Task 5: `List.pmap` — parallel map

**Files:**
- Modify: `stdlib/list.march` (append after `filter`, line ~288)
- Test: `test/stdlib/test_list.march`

- [ ] **Step 1: Write the failing tests**

Append to the appropriate `describe` area of `test/stdlib/test_list.march`:

```march
describe "pmap" do
  test "matches map on empty list" do
    assert (List.pmap([], fn x -> x + 1) == [])
  end

  test "matches map on small list (below threshold)" do
    assert (List.pmap([1, 2, 3], fn x -> x * 2) == [2, 4, 6])
  end

  test "preserves order and matches map on a large list" do
    let xs = List.range(0, 5000)          -- length 5000 > default 1024
    assert (List.pmap(xs, fn x -> x * x) == List.map(xs, fn x -> x * x))
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `dune build test/run_stdlib.exe && ./_build/default/test/run_stdlib.exe -e 2>&1 | grep -iE 'pmap|FAIL' | head`
Expected: FAIL — `List.pmap` is undefined.

- [ ] **Step 3: Implement `pmap`**

Append to `stdlib/list.march` after the `filter` function (after line 288, inside `mod List`):

```march
  doc """
  Parallel map: applies `f` to every element, returning a new list in the
  same order as `map`.  `f` MUST be safe to run concurrently (pure / no
  cross-element ordering dependency).

  Below `pmap_threshold()` elements this delegates to sequential `map`
  (zero spawn overhead).  Above it, the list is split into threshold-sized
  chunks, each mapped on its own task, and the results concatenated in
  order.  In the interpreter tasks run eagerly (correct, sequential); in
  compiled code they run on the multi-core scheduler.

  ## Examples

      march> List.pmap([1, 2, 3], fn x -> x * 2)
      [2, 4, 6]
  """
  fn pmap(xs : List(a), f : a -> b) : List(b) do
    let t = pmap_threshold()
    if length(xs) <= t do
      map(xs, f)
    else do
      let cs = chunks(xs, t)
      let tasks = map(cs, fn c -> task_spawn(fn _ -> map(c, f)))
      concat(map(tasks, fn tk -> task_await_unwrap(tk)))
    end
    end
  end
```

- [ ] **Step 4: Run to verify pass**

Run: `dune build test/run_stdlib.exe && ./_build/default/test/run_stdlib.exe -e 2>&1 | grep -iE 'pmap|FAIL|tests' | head`
Expected: pmap tests pass; no failures.

- [ ] **Step 5: Commit**

```bash
git add stdlib/list.march test/stdlib/test_list.march
git commit -m "feat(stdlib): List.pmap parallel map"
```

---

## Task 6: `List.pmap_n` — bounded-concurrency parallel map

**Files:**
- Modify: `stdlib/list.march` (after `pmap`)
- Test: `test/stdlib/test_list.march`

- [ ] **Step 1: Write the failing tests**

```march
describe "pmap_n" do
  test "matches map regardless of concurrency cap" do
    let xs = List.range(0, 100)
    assert (List.pmap_n(xs, fn x -> x + 1, 4) == List.map(xs, fn x -> x + 1))
  end

  test "handles empty list" do
    assert (List.pmap_n([], fn x -> x + 1, 4) == [])
  end

  test "cap of 1 still produces correct result" do
    assert (List.pmap_n([5, 6, 7], fn x -> x * 10, 1) == [50, 60, 70])
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `dune build test/run_stdlib.exe && ./_build/default/test/run_stdlib.exe -e 2>&1 | grep -iE 'pmap_n|FAIL' | head`
Expected: FAIL — `List.pmap_n` undefined.

- [ ] **Step 3: Implement `pmap_n`**

Append after `pmap` in `stdlib/list.march`:

```march
  doc """
  Like `pmap`, but caps the number of concurrent tasks at `max_concurrency`
  by splitting the input into at most that many contiguous chunks.  Use this
  when each element is expensive (few elements, heavy work) so the threshold
  heuristic doesn't apply.  No threshold check is performed.

  `max_concurrency` is treated as at least 1.  Result order matches `map`.
  """
  fn pmap_n(xs : List(a), f : a -> b, max_concurrency : Int) : List(b) do
    let n = length(xs)
    if n == 0 do []
    else do
      let cap = if max_concurrency < 1 do 1 else max_concurrency end
      -- ceil(n / cap), at least 1, so we get at most `cap` chunks
      let csize = if n / cap * cap == n do n / cap else n / cap + 1 end
      let csize2 = if csize < 1 do 1 else csize end
      let cs = chunks(xs, csize2)
      let tasks = map(cs, fn c -> task_spawn(fn _ -> map(c, f)))
      concat(map(tasks, fn tk -> task_await_unwrap(tk)))
    end
    end
  end
```

- [ ] **Step 4: Run to verify pass**

Run: `dune build test/run_stdlib.exe && ./_build/default/test/run_stdlib.exe -e 2>&1 | grep -iE 'pmap_n|FAIL|tests' | head`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add stdlib/list.march test/stdlib/test_list.march
git commit -m "feat(stdlib): List.pmap_n bounded-concurrency parallel map"
```

---

## Task 7: `List.pfilter` — parallel filter

**Files:**
- Modify: `stdlib/list.march` (after `pmap_n`)
- Test: `test/stdlib/test_list.march`

- [ ] **Step 1: Write the failing tests**

```march
describe "pfilter" do
  test "matches filter on small list" do
    assert (List.pfilter([1, 2, 3, 4, 5], fn x -> x > 2) == [3, 4, 5])
  end

  test "matches filter on large list, order preserved" do
    let xs = List.range(0, 5000)
    let pred = fn x -> x % 2 == 0
    assert (List.pfilter(xs, pred) == List.filter(xs, pred))
  end

  test "handles empty list" do
    assert (List.pfilter([], fn x -> x > 0) == [])
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `dune build test/run_stdlib.exe && ./_build/default/test/run_stdlib.exe -e 2>&1 | grep -iE 'pfilter|FAIL' | head`
Expected: FAIL — `List.pfilter` undefined.

- [ ] **Step 3: Implement `pfilter`**

Append after `pmap_n`:

```march
  doc """
  Parallel filter: keeps elements satisfying `pred`, in the same order as
  sequential `filter`.  `pred` MUST be safe to run concurrently.  Below
  `pmap_threshold()` elements it delegates to sequential `filter`; above it
  each threshold-sized chunk is filtered on its own task and the kept
  elements concatenated in order.
  """
  fn pfilter(xs : List(a), pred : a -> Bool) : List(a) do
    let t = pmap_threshold()
    if length(xs) <= t do
      filter(xs, pred)
    else do
      let cs = chunks(xs, t)
      let tasks = map(cs, fn c -> task_spawn(fn _ -> filter(c, pred)))
      concat(map(tasks, fn tk -> task_await_unwrap(tk)))
    end
    end
  end
```

- [ ] **Step 4: Run to verify pass**

Run: `dune build test/run_stdlib.exe && ./_build/default/test/run_stdlib.exe -e 2>&1 | grep -iE 'pfilter|FAIL|tests' | head`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add stdlib/list.march test/stdlib/test_list.march
git commit -m "feat(stdlib): List.pfilter parallel filter"
```

---

## Task 8: `List.preduce` — parallel associative reduction

**Files:**
- Modify: `stdlib/list.march` (after `pfilter`)
- Test: `test/stdlib/test_list.march`

- [ ] **Step 1: Write the failing tests**

```march
describe "preduce" do
  test "sums a small list" do
    assert (List.preduce([1, 2, 3, 4], 0, fn a -> fn b -> a + b) == 10)
  end

  test "matches fold_left sum on a large list" do
    let xs = List.range(0, 5000)
    let add = fn a -> fn b -> a + b
    assert (List.preduce(xs, 0, add) == List.fold_left(xs, 0, add))
  end

  test "empty list returns identity" do
    assert (List.preduce([], 0, fn a -> fn b -> a + b) == 0)
  end

  test "string concat (associative) preserves order" do
    let xs = ["a", "b", "c", "d"]
    let cat = fn a -> fn b -> a ++ b
    assert (List.preduce(xs, "", cat) == "abcd")
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `dune build test/run_stdlib.exe && ./_build/default/test/run_stdlib.exe -e 2>&1 | grep -iE 'preduce|FAIL' | head`
Expected: FAIL — `List.preduce` undefined.

- [ ] **Step 3: Implement `preduce`**

Append after `pfilter`. Note `fold_left(xs, acc, f : b -> a -> b)` accepts a curried `f`; `combine : a -> a -> a` unifies with `b -> a -> b` when `a = b`:

```march
  doc """
  Parallel reduction over an associative `combine` with `identity` as its
  unit.

  **Contract:** `combine` MUST be associative — `combine(combine(x, y), z)`
  must equal `combine(x, combine(y, z))` — and `identity` must be its unit.
  Sum, product, max, min, string concat, and set union qualify; subtraction
  and average DO NOT.  The compiler cannot check this; correctness is the
  caller's responsibility.

  Below `pmap_threshold()` elements this is sequential `fold_left`.  Above
  it, each threshold-sized chunk is reduced on its own task and the partial
  results are combined in order — identical to the sequential result iff the
  contract holds.

  ## Examples

      march> List.preduce([1, 2, 3, 4], 0, fn a -> fn b -> a + b)
      10
  """
  fn preduce(xs : List(a), identity : a, combine : a -> a -> a) : a do
    let t = pmap_threshold()
    if length(xs) <= t do
      fold_left(xs, identity, combine)
    else do
      let cs = chunks(xs, t)
      let tasks = map(cs, fn c -> task_spawn(fn _ -> fold_left(c, identity, combine)))
      let partials = map(tasks, fn tk -> task_await_unwrap(tk))
      fold_left(partials, identity, combine)
    end
    end
  end
```

- [ ] **Step 4: Run to verify pass**

Run: `dune build test/run_stdlib.exe && ./_build/default/test/run_stdlib.exe -e 2>&1 | grep -iE 'preduce|FAIL|tests' | head`
Expected: pass.

- [ ] **Step 5: Run the full stdlib quick suite (regression)**

Run: `scripts/run-tests.sh -q stdlib 2>&1 | tail -20; echo "EXIT: $?"`
Expected: `EXIT: 0`.

- [ ] **Step 6: Commit**

```bash
git add stdlib/list.march test/stdlib/test_list.march
git commit -m "feat(stdlib): List.preduce parallel associative reduction"
```

---

## Task 9: Compiled↔interpreter parity test (Slow)

**Files:**
- Create: `test/native/pmap_parity_bold-murdock-f5cadc.march` (or follow the existing compiled-test naming under `test/native/`)
- Modify: `test/test_codegen.ml` (register as `Slow`, mirroring the existing compiled adversarial regression tests)

- [ ] **Step 1: Inspect the existing compiled-test pattern**

Run: `grep -n 'Slow\|compile\|run_native\|expected' test/test_codegen.ml | head -30`
Read the helper used to compile a `.march` file and compare stdout, plus how a case is registered with `` `Slow ``.

- [ ] **Step 2: Write the parity program**

Create `test/native/pmap_parity_bold-murdock-f5cadc.march`:

```march
fn main() do
  let xs = List.range(0, 5000)
  let seq = List.map(xs, fn x -> x * x)
  let par = List.pmap(xs, fn x -> x * x)
  if seq == par do println("OK") else println("MISMATCH") end
end
```

- [ ] **Step 3: Add the Slow test case**

Following the exact helper/registration pattern found in Step 1, add a `` `Slow `` case that compiles the program with the default threshold (so the 5000-element list takes the parallel path) and asserts stdout is `OK\n`. Use the worktree-suffixed temp binary name to avoid `/tmp` collisions.

- [ ] **Step 4: Run the parity test**

Run: `dune build test/run_codegen.exe && ./_build/default/test/run_codegen.exe 2>&1 | grep -iE 'pmap|parity|FAIL'; echo "EXIT: $?"`
Expected: the parity case passes (`EXIT: 0`).

- [ ] **Step 5: Manually confirm threshold flips the path**

Run the same program compiled with `--pmap-threshold=100000` (forces sequential) and `--pmap-threshold=1` (forces chunked) and confirm both print `OK`:

```bash
./_build/default/bin/main.exe --compile --pmap-threshold=1 -o /tmp/pmap_lo_bold-murdock-f5cadc test/native/pmap_parity_bold-murdock-f5cadc.march && /tmp/pmap_lo_bold-murdock-f5cadc
./_build/default/bin/main.exe --compile --pmap-threshold=100000 -o /tmp/pmap_hi_bold-murdock-f5cadc test/native/pmap_parity_bold-murdock-f5cadc.march && /tmp/pmap_hi_bold-murdock-f5cadc
```

Expected: both print `OK`.

- [ ] **Step 6: Commit**

```bash
git add test/native/pmap_parity_bold-murdock-f5cadc.march test/test_codegen.ml
git commit -m "test(codegen): pmap compiled-vs-interpreter parity (Slow)"
```

---

## Task 10: forge passthrough for `--pmap-threshold`

**Files:**
- Modify: `forge/lib/cmd_build.ml:244`

- [ ] **Step 1: Inspect the build command construction**

Run: `sed -n '230,250p' forge/lib/cmd_build.ml`
Identify how `opt_flag` is built and concatenated into the `march --compile` command string.

- [ ] **Step 2: Add an optional pmap-threshold flag**

Following the exact pattern of `opt_flag`, add a `pmap_flag` string (empty when unset) sourced from the forge config / CLI, and splice it into the command string at line 244 alongside `opt_flag`. If forge has no config plumbing for this yet, read it from an environment variable `MARCH_PMAP_THRESHOLD` so the value can flow through without a config-schema change:

```ocaml
let pmap_flag =
  match Sys.getenv_opt "MARCH_PMAP_THRESHOLD" with
  | Some v when v <> "" -> Printf.sprintf " --pmap-threshold=%s" v
  | _ -> ""
in
```

and add `pmap_flag` to the `Printf.sprintf` argument list right after `opt_flag` (update the format string with one more `%s`).

- [ ] **Step 3: Build forge**

Run: `dune build forge/ 2>&1 | head -20`
Expected: clean build.

- [ ] **Step 4: Commit**

```bash
git add forge/lib/cmd_build.ml
git commit -m "feat(forge): pass --pmap-threshold through to march --compile"
```

---

## Task 11: LSP lint — flag parallelizable `List.map`/`List.filter`

**Files:**
- Modify: `lsp/lib/analysis.ml` (perf_insight_kind ~120, `perf_insight_to_diag` ~1561, `collect_perf_insights` ~1738)
- Modify: `lsp/lib/dune` if `march_tir` (for `Purity`) isn't already a dependency

- [ ] **Step 1: Confirm the LSP can see `Purity`**

Run: `grep -n 'march_tir\|Purity\|libraries' lsp/lib/dune`
If `march_tir` is not in `(libraries ...)`, add it. Build check: `dune build lsp/lib/ 2>&1 | head`.

- [ ] **Step 2: Add the insight kind**

In the `perf_insight_kind` variant (after `RecursiveAlloc`, line 120), add:

```ocaml
  | Parallelizable of { pi_op : string }
      (** A pure List.map/List.filter that could be List.pmap/List.pfilter. *)
```

- [ ] **Step 3: Map the kind to a Hint diagnostic**

In `perf_insight_to_diag` (line 1561), in the `severity, code` match, add a case:

```ocaml
    | Parallelizable _ -> Lsp.Types.DiagnosticSeverity.Hint, "perf/parallelizable"
```

- [ ] **Step 4: Write a purity helper over the surface AST**

Add a helper near the other AST walkers in `analysis.ml`. It conservatively returns `false` on anything not obviously pure, and treats any applied name in `Purity.impure_builtins` as impure (single source of truth shared with the TIR oracle):

```ocaml
(* Conservative purity check for a lambda body / function argument, operating
   on the surface AST. Mirrors lib/tir/purity.ml's whitelist (shared via
   Purity.impure_builtins). False = "treat as impure" (safe: no hint). *)
let rec ast_expr_is_pure (e : Ast.expr) : bool =
  match e with
  | Ast.ELit _ | Ast.EVar _ | Ast.ECon _ -> true
  | Ast.EApp (Ast.EVar n, args, _) ->
      not (List.mem n.Ast.txt Purity.impure_builtins)
      && List.for_all ast_expr_is_pure args
  | Ast.EApp (Ast.EField (_, m, _), args, _) ->
      (* qualified call like IO.println / Random.int — be conservative:
         only known-pure module funcs pass; default impure. *)
      not (List.mem m.Ast.txt Purity.impure_builtins)
      && List.for_all ast_expr_is_pure args
  | Ast.EApp (f, args, _) -> ast_expr_is_pure f && List.for_all ast_expr_is_pure args
  | Ast.ELam (_, body, _) -> ast_expr_is_pure body
  | Ast.EIf (c, t, e, _) ->
      ast_expr_is_pure c && ast_expr_is_pure t
      && Option.fold ~none:true ~some:ast_expr_is_pure e
  | Ast.ELet (_, rhs, body, _) -> ast_expr_is_pure rhs && ast_expr_is_pure body
  | _ -> false
```

**Note for the implementer:** verify the exact `Ast.expr` constructor names/arities against `lib/ast/ast.ml` (e.g. `ELam`, `EIf`, `ELet`, `EField`) and adjust the patterns to match — the AST is the source of truth. Keep the `| _ -> false` catch-all so unknown shapes are treated as impure.

- [ ] **Step 5: Detect map/filter call sites in `collect_perf_insights`**

In `collect_perf_insights` (line 1738), add a recursive AST walk that, for each
`EApp (EField (EVar {txt="List"}, {txt=op}, _), [_xs; f], sp)` where `op` is
`"map"` or `"filter"`, checks `ast_expr_is_pure f` and, if pure, emits:

```ocaml
let pop = if op = "map" then "pmap" else "pfilter" in
{ pi_span = sp;
  pi_kind = Parallelizable { pi_op = pop };
  pi_message =
    Printf.sprintf
      "This pure `List.%s` could be `List.%s` to run in parallel \
       (only worth it for large lists / heavy per-element work)." op pop }
```

Append these to the returned `perf_insight list`. **Never** match `fold_left`/`fold_right`/`reduce` — purity does not imply associativity.

- [ ] **Step 6: Write the lint test**

Add/extend an LSP analysis test (follow the existing test pattern in `lsp/test/`). Assert:
- A pure call `List.map(xs, fn x -> x + 1)` produces a `perf/parallelizable` Hint.
- An impure call `List.map(xs, fn x -> println(x))` produces **no** such hint.
- `List.fold_left(xs, 0, add)` produces **no** such hint.

If `lsp/test/` has no analysis-level harness, add the assertions where `collect_perf_insights`/`Analysis` results are already exercised. Locate it:

Run: `ls lsp/test/ 2>/dev/null; grep -rn 'perf_insight\|collect_perf\|Analysis\.' lsp/test/ 2>/dev/null | head`

- [ ] **Step 7: Run the LSP tests**

Run: `dune build lsp/ && dune runtest lsp/ 2>&1 | tail -20; echo "EXIT: $?"`
Expected: `EXIT: 0`.

- [ ] **Step 8: Commit**

```bash
git add lsp/lib/analysis.ml lsp/lib/dune lsp/test
git commit -m "feat(lsp): hint when a pure List.map/filter could be parallelized"
```

---

## Task 12: LSP code action — "Convert to List.pmap/pfilter"

**Files:**
- Modify: `lsp/lib/analysis.ml` (`code_actions_at`, line 6372)

- [ ] **Step 1: Inspect an existing quick-fix code action**

Run: `sed -n '6372,6470p' lsp/lib/analysis.ml`
Identify how an existing action builds a `WorkspaceEdit` (TextEdit over a span) and how it filters by cursor position / matching diagnostic.

- [ ] **Step 2: Add the conversion action**

In `code_actions_at`, add a branch: when the cursor range overlaps a `Parallelizable` insight's `pi_span`, produce a `QuickFix` `CodeAction` whose `WorkspaceEdit` replaces the `List.map`/`List.filter` head token at that call with `List.pmap`/`List.pfilter`. Reuse the same span→`Range` conversion and `WorkspaceEdit.create ~changes` pattern found in Step 1. Title: `"Convert to List.pmap"` / `"Convert to List.pfilter"`.

The edit only needs to rewrite the method name token; compute its range from the `EField` method-name span (the `op` name token), not the whole call span, so arguments are untouched. If the method-name span isn't separately retained, store it on the `Parallelizable` insight when detecting it in Task 11 Step 5 (add a `pi_name_span : Ast.span` field and populate from the `EField` name).

- [ ] **Step 3: Extend the lint test to assert the action**

In the LSP test from Task 11, request code actions at the `List.map` call position and assert one titled `"Convert to List.pmap"` exists whose edit replaces `map` with `pmap`.

- [ ] **Step 4: Run the LSP tests**

Run: `dune build lsp/ && dune runtest lsp/ 2>&1 | tail -20; echo "EXIT: $?"`
Expected: `EXIT: 0`.

- [ ] **Step 5: Commit**

```bash
git add lsp/lib/analysis.ml lsp/test
git commit -m "feat(lsp): 'Convert to List.pmap/pfilter' quick-fix"
```

---

## Task 13: Benchmark validation + spec maintenance

**Files:**
- Modify: `specs/todos.md`, `specs/progress.md`
- Reference: `bench/list_ops.march`, `specs/benchmarks.md`

- [ ] **Step 1: Run the closure/HOF benchmark for regressions**

Per `CLAUDE.md`, closure/HOF changes map to `bench/list_ops.march`.
Run: `./_build/default/bin/main.exe --compile -o /tmp/listops_bold-murdock-f5cadc bench/list_ops.march && /tmp/listops_bold-murdock-f5cadc`
Expected: completes without error; note timings (sequential `map` paths must be unchanged — `pmap` is additive).

- [ ] **Step 2: Sanity-check the default threshold**

Write a quick bench that times `List.pmap` vs `List.map` over a large list with a moderately heavy `f`, compiled (real parallelism). Confirm `pmap` is not dramatically slower at the default 1024 on a trivial `f` (it should fall back to sequential below threshold, and chunk above). If trivial-`f` parallel overhead is large, record the observation in `specs/progress.md`; 1024 is a documented starting point, not a tuned constant.

- [ ] **Step 3: Run the FULL test suite**

Run: `scripts/run-tests.sh 2>&1 | tail -30; echo "EXIT: $?"`
Expected: `EXIT: 0` (includes the `Slow` parity test).

- [ ] **Step 4: Update specs**

- In `specs/todos.md`: move the parallel-list-ops item to the Done section.
- In `specs/progress.md`: bump the test count and add a feature bullet, e.g.
  "Parallel list ops: `List.pmap`/`pmap_n`/`pfilter`/`preduce`, `--pmap-threshold` flag, and an LSP hint + quick-fix suggesting parallelization of pure `map`/`filter`."

- [ ] **Step 5: Commit**

```bash
git add specs/todos.md specs/progress.md
git commit -m "docs(specs): record parallel list ops + parallelization lint"
```

---

## Out of scope (designed, deferred — see design doc §Part 4)

- `--auto-parallel` TIR pass that rewrites `map`→`pmap` automatically. The
  purity oracle (`Purity.is_pure_ext` + `impure_fns_of_module`) and the runtime
  threshold are the extension points; no code in this milestone.

## Self-Review notes

- **Spec coverage:** Part 1 (stdlib) → Tasks 5–8; Part 2 (threshold flag) →
  Tasks 1–4, 10; Part 3 (LSP lint) → Tasks 11–12; Testing strategy → Tasks
  2/5/6/7/8 (interpreter), 9 (parity Slow), 11/12 (lint), 13 (bench + suite);
  Part 4 → explicitly deferred.
- **Type consistency:** `pmap_threshold : Fn(()) -> Int` everywhere; eval ref
  `pmap_threshold_value`; codegen field `ctx.pmap_threshold`; CLI ref
  `pmap_threshold`; all wrappers return the same type as their sequential
  counterpart (`pmap`/`pmap_n : List(b)`, `pfilter : List(a)`, `preduce : a`).
- **No invented helpers:** reuses existing `List.chunks`, `map`, `filter`,
  `fold_left`, `concat`, `length`, `task_spawn`, `task_await_unwrap`,
  `Purity.impure_builtins`. The only AST constructor names to re-verify against
  `lib/ast/ast.ml` are flagged inline in Task 11 Step 4.
