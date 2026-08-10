# TRMC On By Default — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn tail-recursion-modulo-cons from an env-gated experiment (`MARCH_TRMC=1`) into the compiler's default behaviour, with the coverage needed to trust it.

**Architecture:** TRMC already exists and works (PR #241): `lib/tir/trmc.ml` analyses eligibility post-lower and rewrites eligible functions into destination-passing style, `EAllocHole`/`ESetField` carry the hole, and `Perceus_fbip` pairs a scrutinee drop with a hole allocation so the loop reuses cells in place. This plan does not change that design. It closes the coverage gaps (sanitizer, backends, benchmarks), replaces the env var with a real flag, rewrites the stdlib producers so the optimisation has something to bite on, and only then flips the default.

**Tech Stack:** OCaml 5.3.0 / dune (opam switch `march`), LLVM textual IR, C runtime, alcotest, GitHub Actions (ubuntu-24.04 + macOS runners).

## Global Constraints

- Build and test **inside the worktree**: `dune build --root .`, never a bare targetless `dune build`.
- Run tests with `scripts/run-tests.sh` (agent-safe). `-q` skips Slow tests; run the full suite before merging.
- Judge success by **exit code**, never by tail output. Never measure an exit code through a pipe.
- Never `git add -A` / `git add .` / `git commit -am`. Stage files explicitly by name.
- No `Co-Authored-By` lines in commits.
- Never `git stash` in this worktree (the stash stack is shared across sessions).
- Benchmarks must be **compiled** (`--compile --opt 2`), never interpreted.
- Any flag that changes emitted code must be added to `codegen_cas_tags ()` in `bin/main.ml:1258`, or the CAS silently serves a stale binary across modes.
- Update `specs/todos/` → `specs/progress/` (`git mv`) and add a `CHANGELOG.md` bullet under `## [Unreleased]` in the same commit as any user-visible change.
- After changing Perceus/FBIP, run `bench/tree_transform.march`; after closure/HOF changes, `bench/list_ops.march`; after allocation changes, `bench/binary_trees.march`.

## Background: what is already true

Verified 2026-08-10 on `origin/main` @ `7109e1af`:

- TRMC is gated: `Trmc.transform_module` returns its input unchanged unless `MARCH_TRMC` is set (`lib/tir/trmc.ml`).
- Measured on a 20k-element list × 2000 maps, compiled `--opt 2`: TRMC **0.06s**, accumulator+`reverse` (today's stdlib style) **0.16s**, natural style without TRMC **0.27s**.
- Eligibility over the full stdlib link closure: **19 eligible**, 1 mixed (`OrderedMap.tree_map`), 72 non-trmc, 542 already-tail.
- Full suite passes both with and without `MARCH_TRMC=1`; TIR snapshots are unchanged by the feature.

**The local ASAN hang is a non-issue.** `MARCH_SANITIZE=1` hangs on macOS for *any* program including `println("hi")` — the stack is `__asan::AsanInitInternal → InitializeShadowMemory → MemoryRangeIsAvailable → MemoryMappingLayout::Next`, i.e. inside ASAN's own startup. `specs/lang/golden/sanitize.sh:26-32` already documents this: CrowdStrike Falcon's syscall interception hangs ASAN's shadow-memory mmap setup, and the script skips on such a Mac. Falcon is confirmed running on the dev machine. **There is already a working Linux ASAN gate** — the `sanitize-gate` job (`.github/workflows/ci.yml:331`) runs `sanitize.sh` over all 46 goldens on ubuntu-24.04. So the sanitizer work is *extending an existing green gate*, not repairing anything.

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `specs/lang/golden/sanitize.sh` | ASAN sweep over the golden corpus | Modify — accept a TRMC mode via env, label output |
| `.github/workflows/ci.yml` | CI jobs | Modify — add a TRMC leg to `sanitize-gate` |
| `lib/tir/trmc.ml` | Eligibility + DPS transform | Modify — report skipped cases; actor-safety refusal; read the flag from a ref, not getenv |
| `bin/main.ml` | Driver, CLI flags, CAS tags | Modify — `--trmc`/`--no-trmc`, set the ref, CAS tag |
| `lib/jit/repl_jit.ml` | REPL/JIT pipeline | Modify — run the transform so REPL matches compiled |
| `test/test_trmc.ml` | TRMC unit + pipeline tests | Modify — skipped-case and actor-refusal tests |
| `test/test_codegen.ml` | Codegen suite aggregator | Modify — register new suites |
| `stdlib/list.march` | List producers | Modify — natural style (Task 8) |
| `bench/list_producers.march` | New benchmark isolating traversal cost | Create |
| `CHANGELOG.md` | User-facing digest | Modify — one bullet when the default flips |

---

### Task 1: TRMC leg on the Linux ASAN gate

Gives the feature real memory-safety evidence, using the gate that already works.

**Files:**
- Modify: `specs/lang/golden/sanitize.sh`
- Modify: `.github/workflows/ci.yml:331-348`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: a CI job leg that runs all 46 goldens under ASAN with TRMC active. Later tasks rely on this being green before the default flips.

- [ ] **Step 1: Make the sweep label its mode**

In `specs/lang/golden/sanitize.sh`, after the `export ASAN_OPTIONS=...` line, add:

```bash
# TRMC mode is inherited from the environment so the caller can run this
# script twice — once per mode — and get separately attributable output.
# Without the label a failure in one mode is indistinguishable from the other.
mode_label="trmc=${MARCH_TRMC:-off}"
echo "=== golden sanitize ($mode_label) ==="
```

Then change the final summary line from:

```bash
echo "=== golden sanitize: $pass clean, $fail failed ==="
```

to:

```bash
echo "=== golden sanitize ($mode_label): $pass clean, $fail failed ==="
```

- [ ] **Step 2: Verify the script still runs and skips cleanly on macOS**

Run: `MARCH_BIN="$PWD/_build/default/bin/main.exe" ./specs/lang/golden/sanitize.sh; echo "EXIT=$?"`
Expected: the Falcon SKIP message and `EXIT=0`. (This machine cannot run the real sweep — that is what CI is for.)

- [ ] **Step 3: Add the TRMC leg to CI**

In `.github/workflows/ci.yml`, inside the `sanitize-gate` job, after the existing "Golden corpus AddressSanitizer gate" step, add:

```yaml
      - name: Golden corpus AddressSanitizer gate — TRMC enabled
        timeout-minutes: 15
        run: |
          eval $(opam env)
          MARCH_BIN="$PWD/_build/default/bin/main.exe" \
            MARCH_TRMC=1 ./specs/lang/golden/sanitize.sh
```

Bump the job's `timeout-minutes: 25` to `40` on the line above `steps:` — the job now does two full sweeps.

- [ ] **Step 4: Add a TRMC-on test leg**

Until Task 10 flips the default, nothing in CI runs the *suite* with TRMC
active — only this ASAN gate would. Add a second step to the same job so
regressions in the transform are caught by the normal tests too:

```yaml
      - name: Test suite with TRMC enabled
        timeout-minutes: 20
        run: |
          eval $(opam env)
          MARCH_TRMC=1 ./scripts/run-tests.sh
```

Remove this step in Task 10, when the default makes it redundant.

- [ ] **Step 5: Commit**

```bash
git add specs/lang/golden/sanitize.sh .github/workflows/ci.yml
git commit -m "ci(trmc): run the golden ASAN gate and the test suite with TRMC enabled"
```

- [ ] **Step 6: Push and confirm the gate is green in CI**

Push the branch and open a draft PR. Wait for `sanitize-gate` to finish. Expected: both legs report `46 clean, 0 failed`.

**If the TRMC leg fails:** stop and treat it as a real memory-safety bug in the transform. Do not proceed to later tasks. The likely suspects, in order: the hole-clear on the reuse path in `lib/tir/llvm_emit.ml` (`EAllocHole` with `Some reuse_atom`), and `moved_vars` drop suppression in `lib/tir/perceus.ml`.

---

### Task 2: Benchmark sweep and a producer benchmark

The existing benchmarks do not isolate the cost TRMC targets.

**Files:**
- Create: `bench/list_producers.march`
- Modify: `specs/benchmarks.md`

**Interfaces:**
- Consumes: nothing.
- Produces: `bench/list_producers.march`, referenced by Task 8's before/after comparison.

- [ ] **Step 1: Write the benchmark**

Create `bench/list_producers.march`:

```march
-- Isolates the cost TRMC targets: traversal count in list producers.
-- Threads the list so each pass sees a unique value (FBIP reuse applies).
mod ListProducers do
  needs IO.Console

  fn step(xs : List(Int)) : List(Int) do
    List.map(xs, fn x -> x + 1)
  end

  fn repeat_n(xs : List(Int), k : Int) : List(Int) do
    if k <= 0 do xs else repeat_n(step(xs), k - 1) end
  end

  fn main() do
    let xs = List.range(1, 20000)
    let ys = repeat_n(xs, 2000)
    println(List.sum_int(ys))
  end
end
```

- [ ] **Step 2: Compile and record the baseline**

```bash
dune build --root . bin/main.exe
rm -rf .march/cas/artifacts-v2
./_build/default/bin/main.exe --compile --opt 2 -o /tmp/lp_base_78111d bench/list_producers.march
for i in 1 2 3; do /usr/bin/time -p /tmp/lp_base_78111d >/dev/null; done
```

Expected: prints `239988000`. Record the three `real` values; the FIRST timed run pays ~25% warmup, so use runs 2 and 3.

- [ ] **Step 3: Record the TRMC number on the existing FBIP/HOF/alloc benchmarks**

```bash
rm -rf .march/cas/artifacts-v2
for b in tree_transform list_ops binary_trees; do
  ./_build/default/bin/main.exe --compile --opt 2 -o /tmp/${b}_off_78111d bench/$b.march
  MARCH_TRMC=1 ./_build/default/bin/main.exe --compile --opt 2 -o /tmp/${b}_on_78111d bench/$b.march
  echo "== $b =="
  for m in off on; do for i in 1 2 3; do /usr/bin/time -p /tmp/${b}_${m}_78111d >/dev/null; done; done
done
```

Expected: no variant is slower with TRMC on by more than run-to-run noise. `tree_transform` is the one to watch — it exercises the tree shapes TRMC's `mixed` classification does not transform.

**If any benchmark regresses:** record which, and stop. A regression here means the transform is firing somewhere it should not; fix before continuing.

- [ ] **Step 4: Document the benchmark**

Add to `specs/benchmarks.md`, in the mapping table, a row:

```
| `bench/list_producers.march` | TRMC / list-producer traversal count | `lib/tir/trmc.ml`, `lib/tir/perceus_fbip.ml` |
```

- [ ] **Step 5: Commit**

```bash
git add bench/list_producers.march specs/benchmarks.md
git commit -m "bench: add list_producers, isolating list-producer traversal cost"
```

---

### Task 3: Refuse TRMC on actor-crossing types

`specs/todos/2026-08-07-trmc-tail-recursion-modulo-cons.md` lists this as an open question and it was never implemented: `grep -c "actor" lib/tir/trmc.ml` is 0.

**Files:**
- Modify: `lib/tir/trmc.ml`
- Test: `test/test_trmc.ml`

**Interfaces:**
- Consumes: `Trmc.transform_fn : Tir.fn_def -> (Tir.fn_def * Tir.fn_def) option` (existing).
- Produces: unchanged signature; `transform_fn` now returns `None` for actor-message and actor-struct types.

**Why this is needed even though the RC check is atomic:** the reuse path loads the refcount atomically and falls back to a fresh allocation when shared, but `ESetField` writes the hole with a **plain, non-atomic store**. That is safe only while the cell is unreachable from another thread. For a value that can cross an actor boundary that is not guaranteed, and `Repr.is_actor_struct_type` already exists precisely because a name-based guess here was found to false-positive on a user type called `Tree_Actor`.

- [ ] **Step 1: Write the failing test**

Add to `test/test_trmc.ml`, before the `let suites = [` block:

```ocaml
(* An actor message type must never be TRMC'd: the hole-fill is a plain
   non-atomic store, which is only safe while the cell is thread-local. *)
let test_actor_msg_type_is_refused () =
  let msg_ty = Tir.TCon ("Counter_Msg", []) in
  let self = v "f" (Tir.TFn ([msg_ty], msg_ty)) in
  let t = v "t" msg_ty and h = v "h" Tir.TInt in
  let body =
    Tir.ELet (t, Tir.EApp (self, [Tir.AVar (v "xs" msg_ty)]),
              Tir.EAlloc (Tir.TCon ("Counter_Msg.Bump", []),
                          [Tir.AVar h; Tir.AVar t]))
  in
  let fd =
    { Tir.fn_name = "f"; fn_params = [v "xs" msg_ty]; fn_ret_ty = msg_ty;
      fn_body = body; fn_kind = Tir.FnNormal }
  in
  Alcotest.(check bool) "actor message type is not transformed"
    true (Trmc.transform_fn fd = None)
```

Register it by adding to the `"trmc"` list in `suites`:

```ocaml
    Alcotest.test_case "actor msg type refused"          `Quick test_actor_msg_type_is_refused;
```

- [ ] **Step 2: Run it and watch it fail**

Run: `dune build --root . test/run_codegen.exe && ./_build/default/test/run_codegen.exe test trmc`
Expected: FAIL on "actor msg type refused" — the transform currently accepts it.

- [ ] **Step 3: Implement the refusal**

In `lib/tir/trmc.ml`, in `transform_fn`, replace the match scrutinee guard. Change:

```ocaml
let transform_fn (fn : Tir.fn_def) : (Tir.fn_def * Tir.fn_def) option =
  let r = report_of_fn fn.Tir.fn_name fn.Tir.fn_body in
  match verdict_of r, r.r_modcons with
  | Eligible, [ (_ctor, hole) ] ->
```

to:

```ocaml
(** True when [ty] names a type that can cross an actor boundary, and so must
    never be rewritten: the hole-fill is a plain non-atomic store, safe only
    while the cell is thread-local.  Both checks are STRUCTURAL — a name-suffix
    guess here was previously found to false-positive on a user type called
    [Tree_Actor] (see [Repr.is_actor_struct_type]). *)
let crosses_actor_boundary (ty : Tir.ty) : bool =
  match ty with
  | Tir.TCon (name, _) ->
    Tir_names.is_actor_msg_name name || Tir_names.is_actor_struct_name name
  | _ -> false

let transform_fn (fn : Tir.fn_def) : (Tir.fn_def * Tir.fn_def) option =
  let r = report_of_fn fn.Tir.fn_name fn.Tir.fn_body in
  if crosses_actor_boundary fn.Tir.fn_ret_ty then None
  else
  match verdict_of r, r.r_modcons with
  | Eligible, [ (_ctor, hole) ] ->
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `dune build --root . test/run_codegen.exe && ./_build/default/test/run_codegen.exe test trmc`
Expected: all `trmc` cases PASS, including the new one.

- [ ] **Step 5: Confirm eligibility counts did not collapse**

```bash
rm -rf .march/cas/artifacts-v2
MARCH_TRMC=1 MARCH_TRMC_REPORT=1 ./_build/default/bin/main.exe --compile --opt 2 \
  -o /tmp/trmc_probe_78111d bench/list_producers.march 2>&1 | grep -c TRMCXFORM
```

Expected: still 19. If it dropped, the guard is over-broad — check which functions disappeared from the `TRMCXFORM` lines.

- [ ] **Step 6: Commit**

```bash
git add lib/tir/trmc.ml test/test_trmc.ml
git commit -m "tir(trmc): refuse actor-crossing types (hole-fill is a non-atomic store)"
```

---

### Task 4: Report what the transform skips

Right now `transform_fn` silently declines `mixed`, multi-site, and intervening-let cases. A default-on optimisation must not hide its own coverage.

**Files:**
- Modify: `lib/tir/trmc.ml`

**Interfaces:**
- Consumes: `Trmc.transform_fn` from Task 3.
- Produces: unchanged signatures. `MARCH_TRMC_REPORT=1` now emits a `TRMCSKIP` line per declined-but-eligible-looking function.

- [ ] **Step 1: Emit skip reasons**

In `lib/tir/trmc.ml`, in `transform_module`, replace the `| None -> [fn]` arm:

```ocaml
      | None -> [fn]
```

with:

```ocaml
      | None ->
        (* No silent caps: a function the ANALYSIS considers transformable but
           the TRANSFORM declines is a coverage gap, and it must be visible in
           the report rather than inferred from a missing TRMCXFORM line. *)
        (if Sys.getenv_opt "MARCH_TRMC_REPORT" <> None then begin
           let r = report_of_fn fn.Tir.fn_name fn.Tir.fn_body in
           match verdict_of r with
           | Eligible | Mixed ->
             Printf.eprintf "TRMCSKIP\t%s\t%s\tmodcons=%d other=%d\n%!"
               fn.Tir.fn_name (string_of_verdict (verdict_of r))
               (List.length r.r_modcons) r.r_other
           | _ -> ()
         end);
        [fn]
```

- [ ] **Step 2: Verify the skip lines appear**

```bash
dune build --root . bin/main.exe
rm -rf .march/cas/artifacts-v2
MARCH_TRMC=1 MARCH_TRMC_REPORT=1 ./_build/default/bin/main.exe --compile --opt 2 \
  -o /tmp/trmc_skip_78111d bench/list_producers.march 2>&1 | grep TRMCSKIP | head
```

Expected: at least one line, for `OrderedMap.tree_map` (verdict `mixed`, which `transform_fn` declines).

- [ ] **Step 3: Commit**

```bash
git add lib/tir/trmc.ml
git commit -m "tir(trmc): report functions the transform declines, not just those it rewrites"
```

---

### Task 5: Replace the env var with a real flag

Env vars are undiscoverable and neither `forge` nor CI will set one. This also moves the gate into a form that can be flipped in Task 10.

**Files:**
- Modify: `bin/main.ml`
- Modify: `lib/tir/trmc.ml`

**Interfaces:**
- Consumes: `Trmc.transform_module : Tir.tir_module -> Tir.tir_module` (existing).
- Produces: `Trmc.enabled : bool ref` (default `false`), read by `transform_module` instead of `Sys.getenv_opt`. `bin/main.ml` sets it from `--trmc` / `--no-trmc`.

- [ ] **Step 1: Add the ref and switch the gate**

In `lib/tir/trmc.ml`, immediately above `let transform_module`, add:

```ocaml
(** Whether the destination-passing transform runs.  A [ref] rather than an
    env-var read so the driver owns the decision and a CLI flag can set it;
    [bin/main.ml] is the only writer.  Default OFF until the default flips
    (see specs/plans/2026-08-10-trmc-on-by-default.md Task 10). *)
let enabled : bool ref = ref false
```

Then change the first line of `transform_module` from:

```ocaml
  if Sys.getenv_opt "MARCH_TRMC" = None then m
```

to:

```ocaml
  if not !enabled then m
```

- [ ] **Step 2: Add the CLI flags**

In `bin/main.ml`, find the argument-parsing list and add two entries alongside the other codegen flags:

```ocaml
    ("--trmc", Arg.Unit (fun () -> March_tir.Trmc.enabled := true),
     " Enable tail-recursion-modulo-cons (destination-passing rewrite)");
    ("--no-trmc", Arg.Unit (fun () -> March_tir.Trmc.enabled := false),
     " Disable tail-recursion-modulo-cons");
```

Then, immediately after argument parsing completes and before the pipeline runs, honour the legacy env var so existing scripts and the CI leg from Task 1 keep working:

```ocaml
  (* Legacy escape hatch: MARCH_TRMC=1 predates --trmc and is still used by
     the CI sanitize gate.  The flag wins if both are given. *)
  if Sys.getenv_opt "MARCH_TRMC" <> None then March_tir.Trmc.enabled := true;
```

- [ ] **Step 3: Update the CAS tag to follow the ref**

In `bin/main.ml`, `codegen_cas_tags ()` currently reads the env var. Change:

```ocaml
  @ (if Sys.getenv_opt "MARCH_TRMC" <> None then ["trmc"] else [])
```

to:

```ocaml
  @ (if !March_tir.Trmc.enabled then ["trmc"] else [])
```

**This ordering matters:** `codegen_cas_tags ()` must be called *after* argument parsing sets the ref. Verify by inspection that every `cas_flags` construction site (`bin/main.ml`, two sites) runs after `Arg.parse`.

- [ ] **Step 4: Verify both spellings work and stay CAS-distinct**

```bash
dune build --root . bin/main.exe
rm -rf .march/cas/artifacts-v2
./_build/default/bin/main.exe --compile --opt 2 --trmc -o /tmp/t_flag_78111d bench/list_producers.march
./_build/default/bin/main.exe --compile --opt 2        -o /tmp/t_off_78111d  bench/list_producers.march
for i in 1 2; do /usr/bin/time -p /tmp/t_flag_78111d >/dev/null; done
for i in 1 2; do /usr/bin/time -p /tmp/t_off_78111d  >/dev/null; done
```

Expected: the `--trmc` binary is markedly faster. If they are identical, the CAS tag is not following the flag — re-check Step 3's ordering.

- [ ] **Step 5: Full suite**

Run: `scripts/run-tests.sh`
Expected: `All suites passed.`

- [ ] **Step 6: Commit**

```bash
git add bin/main.ml lib/tir/trmc.ml
git commit -m "cli(trmc): add --trmc/--no-trmc; MARCH_TRMC stays as a legacy alias"
```

---

### Task 6: REPL/JIT parity

`lib/jit/repl_jit.ml:313` runs Perceus directly and never calls `Trmc.transform_module`. Harmless while TRMC is off; a silent behaviour split once it is on.

**Files:**
- Modify: `lib/jit/repl_jit.ml:313`
- Test: `test/test_trmc.ml`

**Interfaces:**
- Consumes: `Trmc.enabled` and `Trmc.transform_module` from Task 5.
- Produces: no new API.

- [ ] **Step 1: Write the failing test**

Add to `test/test_trmc.ml` before `let suites = [`:

```ocaml
(* REPL/JIT must apply the same transform as the compiled path, or a function
   behaves one way in the REPL and another when compiled.  repl_jit may re-lower
   a module the driver already transformed, so the transform has to be
   idempotent — running it twice must not produce a second $dps helper.

   The fixture uses a genuinely ELIGIBLE function: on an empty module both
   sides are trivially zero and the assertion holds no matter how broken the
   transform is. *)
let test_transform_is_idempotent_on_a_transformed_module () =
  let self = v "f" (Tir.TFn ([list_int], list_int)) in
  let t = v "t" list_int and h = v "h" Tir.TInt in
  let body =
    Tir.ELet (t, Tir.EApp (self, [Tir.AVar (v "xs" list_int)]),
              Tir.EAlloc (Tir.TCon ("List.Cons", []),
                          [Tir.AVar h; Tir.AVar t]))
  in
  let m = module_of [fn "f" [v "xs" list_int] body] in
  Trmc.enabled := true;
  let once = Trmc.transform_module m in
  let twice = Trmc.transform_module once in
  Trmc.enabled := false;
  (* Non-vacuousness: the first pass must actually have added the helper. *)
  Alcotest.(check int) "first transform adds the $dps helper"
    2 (List.length once.Tir.tm_fns);
  Alcotest.(check int) "transforming twice adds nothing further"
    (List.length once.Tir.tm_fns) (List.length twice.Tir.tm_fns)
```

Register it in the `"trmc"` suite list:

```ocaml
    Alcotest.test_case "transform is idempotent"         `Quick test_transform_is_idempotent_on_a_transformed_module;
```

- [ ] **Step 2: Run it**

Run: `dune build --root . test/run_codegen.exe && ./_build/default/test/run_codegen.exe test trmc`
Expected: PASS. If the second assertion fails with 3 instead of 2, the transform is not idempotent — it re-transformed its own helper. Fix that before wiring the second call site in Step 3, because `repl_jit` re-lowers modules the driver has already transformed.

- [ ] **Step 3: Wire the transform into the REPL/JIT pipeline**

In `lib/jit/repl_jit.ml`, immediately before line 313's `let tir = March_tir.Perceus.perceus ~repl:true ~repl_vars tir in`, insert:

```ocaml
  (* Match the compiled pipeline: bin/main.ml runs Trmc.transform_module
     post-lower, and without it a function behaves differently in the REPL than
     when compiled.  Gated by the same Trmc.enabled ref. *)
  let tir = March_tir.Trmc.transform_module tir in
```

- [ ] **Step 4: Verify the REPL still works**

```bash
dune build --root . 2>&1 | grep -E "Error" -A 3 | head
scripts/run-tests.sh -q
```
Expected: build clean, `All suites passed.`

- [ ] **Step 5: Commit**

```bash
git add lib/jit/repl_jit.ml test/test_trmc.ml
git commit -m "jit(trmc): run the transform in the REPL pipeline so it matches compiled output"
```

---

### Task 7: JS backend coverage

`lib/tir/js_emit.ml` has `emit_tagged_alloc_hole` and an `ESetField` property write that have never executed — no test sets the flag on a JS target.

**Files:**
- Test: `test/test_trmc.ml`
- Modify: `test/test_codegen.ml`

**Interfaces:**
- Consumes: `Trmc.enabled` (Task 5), `trmc_hole_module ()` (existing in `test/test_trmc.ml`).
- Produces: no new API.

- [ ] **Step 1: Write the failing test**

Add to `test/test_trmc.ml` before `let suites = [`:

```ocaml
(* The JS backend's hole emission has no other coverage: a fresh cell writes
   null into the hole slot, and ESetField is a property write sequenced with
   undefined so the expression's value is unit. *)
let test_js_emits_hole_and_fill () =
  (* Js_emit.emit_module returns (js_source, sourcemap option) — bind the
     tuple, not a bare string. *)
  let (js, _srcmap) = March_tir.Js_emit.emit_module (trmc_hole_module ()) in
  let contains sub =
    let n = String.length sub and m = String.length js in
    let rec go i = i + n <= m && (String.sub js i n = sub || go (i + 1)) in
    go 0
  in
  Alcotest.(check bool) "hole field emitted as null" true (contains "_1: null");
  Alcotest.(check bool) "hole fill emitted as a property write" true
    (contains "._1 = ")
```

Register it in a new suite group by adding to `suites`:

```ocaml
  "trmc-js", [
    Alcotest.test_case "js emits hole and fill"          `Quick test_js_emits_hole_and_fill;
  ];
```

- [ ] **Step 2: Run it**

Run: `dune build --root . test/run_codegen.exe && ./_build/default/test/run_codegen.exe test trmc-js`
Expected: PASS.

Signature for reference (`lib/tir/js_emit.ml:1304`):
`val emit_module : ?source_file:string -> ?fn_lines:(...) list -> Tir.tir_module -> string * string option`

- [ ] **Step 3: Commit**

```bash
git add test/test_trmc.ml test/test_codegen.ml
git commit -m "test(trmc): cover the JS backend's hole allocation and fill"
```

---

### Task 8: Rewrite the stdlib producers into natural style

**This is the task that makes the default worth flipping.** Today `List.map`/`filter`/`filter_map`/`append`/`flat_map` are accumulator+`reverse` and classify `already-tail`, so TRMC never sees them.

**Files:**
- Modify: `stdlib/list.march`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: `--trmc` from Task 5; `bench/list_producers.march` from Task 2.
- Produces: no API change — `List.map` etc. keep their exact signatures and semantics.

**Do these one function at a time**, benchmarking after each. Do not batch.

- [ ] **Step 1: Record the pre-rewrite number**

```bash
dune build --root . bin/main.exe
rm -rf .march/cas/artifacts-v2
./_build/default/bin/main.exe --compile --opt 2 --trmc -o /tmp/lp_pre_78111d bench/list_producers.march
for i in 1 2 3; do /usr/bin/time -p /tmp/lp_pre_78111d >/dev/null; done
```

Record runs 2 and 3.

- [ ] **Step 2: Rewrite `List.map`**

In `stdlib/list.march`, replace the body of `map` (currently at ~line 230, an inner `go` with an accumulator plus `List.reverse(acc)`) with:

```march
  fn map(xs : List(a), f : a -> b) : List(b) do
    match xs do
    Nil        -> Nil
    Cons(h, t) -> Cons(f(h), map(t, f))
    end
  end
```

- [ ] **Step 3: Verify eligibility and correctness**

```bash
dune build --root . bin/main.exe
rm -rf .march/cas/artifacts-v2
MARCH_TRMC_REPORT=1 ./_build/default/bin/main.exe --compile --opt 2 --trmc \
  -o /tmp/lp_map_78111d bench/list_producers.march 2>&1 | grep -E "TRMCXFORM.*List\.map"
/tmp/lp_map_78111d
```

Expected: a `TRMCXFORM` line naming a `List.map` instantiation, and the program prints `239988000`.

**If no TRMCXFORM line appears for map:** the rewrite is not being classified `Eligible`. Dump the TIR and check the shape:
`MARCH_DUMP_TXT=tir-lower ./_build/default/bin/main.exe --compile --opt 2 -o /tmp/x bench/list_producers.march 2>&1 | grep -A 12 "^fn List.map"`.
The transform needs `let t = map(...) in alloc List.Cons(fh, t)` — a *direct* `EAlloc`, no intervening let.

- [ ] **Step 4: Benchmark and run the suite**

```bash
for i in 1 2 3; do /usr/bin/time -p /tmp/lp_map_78111d >/dev/null; done
scripts/run-tests.sh
```
Expected: faster than Step 1's number; `All suites passed.`

- [ ] **Step 5: Commit**

```bash
git add stdlib/list.march
git commit -m "stdlib(list): map in natural style — one traversal under TRMC"
```

- [ ] **Step 6: Repeat Steps 2-5 for `filter`**

```march
  fn filter(xs : List(a), pred : a -> Bool) : List(a) do
    match xs do
    Nil        -> Nil
    Cons(h, t) ->
      if pred(h) do Cons(h, filter(t, pred))
      else filter(t, pred) end
    end
  end
```

Note the `else` branch is a plain tail call, so this function is classified `mixed`, not `eligible` — the `Cons` branch still gets the loop. Confirm with the report; if the whole function is declined, stop and record it rather than forcing it.

- [ ] **Step 7: Repeat Steps 2-5 for `filter_map`**

```march
  fn filter_map(xs : List(a), f : a -> Option(b)) : List(b) do
    match xs do
    Nil        -> Nil
    Cons(h, t) ->
      match f(h) do
      Some(v) -> Cons(v, filter_map(t, f))
      None    -> filter_map(t, f)
      end
    end
  end
```

- [ ] **Step 8: Add the changelog entry**

In `CHANGELOG.md`, under `## [Unreleased]` → `### Changed`:

```markdown
- `List.map`, `List.filter` and `List.filter_map` now traverse the list once
  instead of building a reversed accumulator and reversing it. Same results,
  same complexity class, roughly half the work per call.
```

- [ ] **Step 9: Commit**

```bash
git add stdlib/list.march CHANGELOG.md
git commit -m "stdlib(list): filter/filter_map in natural style; changelog"
```

---

### Task 9: Stop warning about recursion TRMC handles

`typecheck.ml:12055` and the LSP's `perf/non-tail-call` (`lsp/lib/analysis.ml:126`) both flag functions TRMC now compiles into loops.

**Files:**
- Modify: `lib/typecheck/typecheck.ml:12052-12065`
- Test: `test/test_compiler.ml`

**Interfaces:**
- Consumes: `Trmc.enabled` (Task 5).
- Produces: no new API.

**Scope note:** only the *wording* changes here, not the detection. Suppressing the warning entirely would require the typechecker to know TIR-level eligibility, which it does not have — verified: the AST-shaped `Succ(Succ(add_one(k)))` looks transformable but is classified `non-trmc` because of the intervening let. Leave the LSP lint alone; wire it to real eligibility in a separate piece of work.

- [ ] **Step 1: Write the failing test**

Add to `test/test_compiler.ml` in the diagnostics section:

```ocaml
let test_structural_recursion_warning_does_not_prescribe_accumulator () =
  let ctx = typecheck {|mod W do
  type Nat = Zero | Succ(Nat)
  fn bump(n : Nat) : Nat do
    match n do
    Zero    -> Zero
    Succ(k) -> Succ(bump(k))
    end
  end
end|} in
  let diags = March_errors.Errors.sorted ctx in
  let mentions_accumulator =
    List.exists (fun d ->
      let m = d.March_errors.Errors.message in
      (try ignore (Str.search_forward
                     (Str.regexp_string "accumulator parameter") m 0); true
       with Not_found -> false)
    ) diags
  in
  Alcotest.(check bool)
    "constructor-wrapped recursion is not told to use an accumulator"
    false mentions_accumulator
```

This uses the file's existing idiom: `typecheck` (returns an error ctx),
`March_errors.Errors.sorted ctx`, and `Str.search_forward` for substring
matching — the same shape as `test_actor_handler_body_io_with_needs_no_warning`
at `test/test_compiler.ml:3351`. There is no `diagnostics_of` helper.

- [ ] **Step 2: Run it and watch it fail**

Run: `dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe test error_improvements`
Expected: FAIL — the current message says "Consider using an accumulator parameter."

- [ ] **Step 3: Reword the non-arithmetic warning**

In `lib/typecheck/typecheck.ml`, the `else` branch at ~12060 currently reads:

```ocaml
            Err.warning errors ~span:sp
              (Printf.sprintf
                 "Warning: function `%s` is structurally recursive but not \
                  tail-recursive. This is safe for bounded input but uses \
                  O(depth) stack space."
                 fn_name)
```

Replace the message text with:

```ocaml
            Err.warning errors ~span:sp
              (Printf.sprintf
                 "Warning: function `%s` is structurally recursive but not \
                  tail-recursive. This is safe for bounded input but may use \
                  O(depth) stack space; when the recursive call is the direct \
                  argument of a constructor, the compiler turns it into a loop."
                 fn_name)
```

Leave the *arithmetic* variant (~12053) unchanged — `1 + f(n-1)` is not constructor-wrapped and TRMC can never transform it, so "use an accumulator" is still correct advice there.

- [ ] **Step 4: Run the test to verify it passes**

Run: `./_build/default/test/run_compiler.exe test error_improvements`
Expected: PASS.

- [ ] **Step 5: Check the conformance corpora**

The `@types-check` corpus asserts diagnostic **text** and is CI-only. Run it locally:

```bash
dune build --root . @types-check 2>&1 | tail -20; echo "EXIT=$?"
```
Expected: EXIT=0. If a fixture pins the old wording, update the fixture's expected output in the same commit.

- [ ] **Step 6: Commit**

```bash
git add lib/typecheck/typecheck.ml test/test_compiler.ml
git commit -m "typecheck: structural-recursion warning no longer prescribes an accumulator"
```

---

### Task 10: Flip the default

Only after Tasks 1-9 are merged and CI is green on all of them.

**Files:**
- Modify: `lib/tir/trmc.ml`
- Modify: `CHANGELOG.md`
- Move: `specs/todos/2026-08-07-trmc-tail-recursion-modulo-cons.md` → `specs/progress/`

**Interfaces:**
- Consumes: everything above.
- Produces: `Trmc.enabled` defaults to `true`; `--no-trmc` is the escape hatch.

- [ ] **Step 1: Flip the ref**

In `lib/tir/trmc.ml`, change:

```ocaml
let enabled : bool ref = ref false
```

to:

```ocaml
let enabled : bool ref = ref true
```

and update the doc comment's final sentence to read: `Default ON since 2026-08-10; --no-trmc disables it.`

- [ ] **Step 2: Full suite, both directions**

```bash
scripts/run-tests.sh
```
Expected: `All suites passed.` This now exercises TRMC by default, so it is the real gate.

Then confirm the escape hatch still works:

```bash
rm -rf .march/cas/artifacts-v2
./_build/default/bin/main.exe --compile --opt 2 --no-trmc -o /tmp/lp_noflag_78111d bench/list_producers.march
/tmp/lp_noflag_78111d
```
Expected: prints `239988000`.

- [ ] **Step 3: Regenerate TIR snapshots**

The default-on transform changes emitted TIR for eligible functions, so the goldens legitimately move:

```bash
UPDATE_SNAPSHOTS=1 ./_build/default/test/run_snapshots.exe -e
git diff test/snapshots/ | head -60
```

**Review the diff — it is the code-review artifact.** Expect `alloc_hole` / `reuse_hole` / `$dst.N <-` lines to appear in producer-shaped fixtures and nowhere else. If an unrelated fixture moved, stop and find out why.

- [ ] **Step 4: Benchmark sweep**

```bash
rm -rf .march/cas/artifacts-v2
for b in list_producers tree_transform list_ops binary_trees; do
  ./_build/default/bin/main.exe --compile --opt 2 -o /tmp/${b}_dflt_78111d bench/$b.march
  echo "== $b =="; for i in 1 2 3; do /usr/bin/time -p /tmp/${b}_dflt_78111d >/dev/null; done
done
```
Expected: `list_producers` markedly faster than the Task 2 baseline; the others within noise.

- [ ] **Step 5: Drop the now-redundant CI leg**

In `.github/workflows/ci.yml`, remove the "Test suite with TRMC enabled" step
added in Task 1 Step 4 — with the default on, the ordinary `test` job covers it.
Keep both `sanitize.sh` legs: the explicit `MARCH_TRMC=1` leg is now redundant
with the default, so delete that one too and leave the original.

- [ ] **Step 6: Changelog and specs**

In `CHANGELOG.md` under `## [Unreleased]` → `### Changed`:

```markdown
- Tail-recursion-modulo-cons is now on by default: a recursive call that is the
  direct argument of a constructor in tail position compiles to a loop that
  reuses cells in place, instead of O(depth) stack. `--no-trmc` disables it.
```

Then:

```bash
git mv specs/todos/2026-08-07-trmc-tail-recursion-modulo-cons.md specs/progress/
```

and append a closing section to that file recording the final benchmark numbers from Step 4.

- [ ] **Step 7: Commit**

```bash
git add lib/tir/trmc.ml CHANGELOG.md test/snapshots .github/workflows/ci.yml
git add specs/progress/2026-08-07-trmc-tail-recursion-modulo-cons.md
git commit -m "tir(trmc): enable tail-recursion-modulo-cons by default"
```

- [ ] **Step 8: Watch CI**

Both `sanitize-gate` legs, `test`, `conformance`, `property-tests` and `cross-linux-oracle` must be green. The sanitize gate is the one that matters most: it is the only memory-safety evidence this feature has.

---

## Notes for the implementer

- **The macOS ASAN hang is expected.** Any local `MARCH_SANITIZE=1` run hangs because of CrowdStrike Falcon; `specs/lang/golden/sanitize.sh` skips on such a host. Do not try to fix it, and do not treat a local hang as a TRMC bug. Sanitizer evidence comes from Linux CI only.
- **The CAS will lie to you** if a code-changing flag is missing from `codegen_cas_tags ()`. Symptom: two modes produce identical timings. `rm -rf .march/cas/artifacts-v2` between measurements when in doubt.
- **The first timed run of any benchmark pays ~25% warmup.** Always take three and use runs 2-3.
- **12 `CAPABILITY CEILING` failures under `dune build @all` in `demo/` are pre-existing** on main (verified against a clean checkout). They are not caused by anything in this plan.
