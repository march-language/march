# P6 Unboxed Newtypes — Implementation Plan (Milestone 1 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Represent single-variant single-field constructors (`type T = T(payload)`) as their raw payload — no heap allocation, no tag — everywhere, for any payload type.

**Architecture:** A pure, memoized `repr_of_ty` table derived from the monomorphic type (Phase 1) is consulted at three codegen sites (Phase 2): EAlloc emission (emit payload directly), `emit_case` (bind field to scrutinee), and Perceus `needs_rc` (scalar payloads need no RC). The TIR `ty` type is left unchanged.

**Tech Stack:** OCaml 5.3, dune, alcotest. Build/test via `dune build --root .` and the `run_codegen`/`run_stdlib` test binaries (this is a git worktree — always pass `--root .`; `dune`/`opam` are on PATH at `/Users/80197052/.opam/march/bin`).

**Scope of this plan:** Newtypes only. The Option-shaped niche (`None=0`, `Some(x)=x`) and its runtime-ABI flip are a separate follow-on plan, written after this milestone merges. Design: `specs/2026-06-20-unboxed-single-field-constructors-design.md`.

**Reference facts (verified):**
- `type_def` is `TDVariant of string * (string * ty list) list` ([lib/tir/tir.ml:77](lib/tir/tir.ml:77)). A newtype is `TDVariant(name, [(ctor, [payload_ty])])` — exactly one variant, exactly one arg.
- The module carries `tm_types : type_def list` ([lib/tir/tir.ml:94](lib/tir/tir.ml:94)) and `tm_fns`.
- Perceus decides heap-ness via `needs_rc : ty -> bool` ([lib/tir/perceus.ml:179](lib/tir/perceus.ml:179)): `TCon _ | TString | TPtr _ -> true`; scalars false.
- EAlloc for a constructor is emitted at [lib/tir/llvm_emit.ml:3029](lib/tir/llvm_emit.ml:3029) (`EAlloc (TCon (ctor, _), args)`); the actual `march_alloc` calls are at lines 1313/1396/1471.
- `emit_case` is at [lib/tir/llvm_emit.ml:3377](lib/tir/llvm_emit.ml:3377).
- `lib/tir/dune` lists all modules explicitly; new modules must be added there.

---

## File Structure

- **Create** `lib/tir/repr.ml` — the representation table. One responsibility: classify a monomorphic type as `Boxed | Newtype | Niche`. Phase 1 implements `Boxed`/`Newtype`; the `Niche` constructor is defined now (so the type is stable for the follow-on plan) but only ever returned in the follow-on plan.
- **Modify** `lib/tir/dune` — register the `repr` module.
- **Modify** `lib/tir/perceus.ml` — make `needs_rc` repr-aware (thread `type_defs`).
- **Modify** `lib/tir/llvm_emit.ml` — consult repr at EAlloc emission and in `emit_case`; store a repr memo on the emit context.
- **Modify** `test/test_codegen.ml` — unit tests for `Repr.repr_of_ty` and an IR-level + behavioral test for newtype unboxing.

---

## Phase 1 — `Repr` module (pure analysis, no behavior change)

### Task 1: Define the `repr` type and a placeholder classifier

**Files:**
- Create: `lib/tir/repr.ml`
- Modify: `lib/tir/dune` (modules list)

- [ ] **Step 1: Create `lib/tir/repr.ml` with the type and a stub returning `Boxed`**

```ocaml
(** P6 — derived representation table.

    A pure, memoized function of the MONOMORPHIC type: after monomorphization
    every type is concrete, so representation can be decided per type with no
    threading of state.  Leaving [Tir.ty] unchanged keeps the blast radius to
    the codegen consultation sites.

    Milestone 1 implements [Boxed] and [Newtype].  [Niche] is defined now so the
    type is stable for the Option-niche follow-on plan, but is never returned
    yet. *)

type repr =
  | Boxed                                       (* today's heap cell *)
  | Newtype of Tir.ty                           (* represented as the raw payload *)
  | Niche   of { payload : Tir.ty; tagged : bool }  (* None=0, Some(x)=x (follow-on) *)

(* Look up a variant type definition by name. *)
let find_variant (type_defs : Tir.type_def list) (name : string)
    : (string * Tir.ty list) list option =
  List.find_map (function
    | Tir.TDVariant (n, variants) when n = name -> Some variants
    | _ -> None) type_defs

let repr_of_ty (_type_defs : Tir.type_def list) (_ty : Tir.ty) : repr =
  Boxed
```

- [ ] **Step 2: Register the module in `lib/tir/dune`**

Find the `(modules …)` stanza and add `repr` to the list (alphabetical position near `perceus` is fine; order does not matter to dune). Example resulting fragment:

```
(modules tir pp lower mono defun borrow perceus repr escape llvm_emit purity
 fold simplify inline dce cprop opt fusion known_call policy_dce beta_adt
 join_points)
```

- [ ] **Step 3: Build to verify it compiles**

Run: `dune build --root . lib/tir/.tir.objs/byte/march_tir__Repr.cmi 2>&1 | grep -v shift/reduce | head`
Expected: no errors (empty output or just the dune directory line).

- [ ] **Step 4: Commit**

```bash
git add lib/tir/repr.ml lib/tir/dune
git commit -m "feat(tir): add Repr module skeleton (P6 milestone 1)"
```

---

### Task 2: Classify newtypes — `Newtype(payload)`

**Files:**
- Modify: `lib/tir/repr.ml`
- Test: `test/test_codegen.ml`

- [ ] **Step 1: Write the failing tests**

Add near the existing `join_points` tests in `test/test_codegen.ml`:

```ocaml
(* P6 Repr classification *)
let test_repr_newtype_int () =
  let tds = [March_tir.Tir.TDVariant ("UserId", [("UserId", [March_tir.Tir.TInt])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("UserId", [])) with
  | March_tir.Repr.Newtype March_tir.Tir.TInt -> ()
  | other -> Alcotest.failf "expected Newtype TInt, got %s"
      (match other with March_tir.Repr.Boxed -> "Boxed" | _ -> "other")

let test_repr_newtype_ptr () =
  let tds = [March_tir.Tir.TDVariant ("Wrap", [("Wrap", [March_tir.Tir.TString])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("Wrap", [])) with
  | March_tir.Repr.Newtype March_tir.Tir.TString -> ()
  | _ -> Alcotest.fail "expected Newtype TString"

let test_repr_multivariant_is_boxed () =
  (* Option-shaped stays Boxed in milestone 1 (niche is the follow-on plan). *)
  let tds = [March_tir.Tir.TDVariant
    ("Option", [("None", []); ("Some", [March_tir.Tir.TInt])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("Option", [])) with
  | March_tir.Repr.Boxed -> ()
  | _ -> Alcotest.fail "expected Boxed for Option in milestone 1"

let test_repr_multifield_is_boxed () =
  let tds = [March_tir.Tir.TDVariant
    ("Point", [("Point", [March_tir.Tir.TInt; March_tir.Tir.TInt])])] in
  match March_tir.Repr.repr_of_ty tds (March_tir.Tir.TCon ("Point", [])) with
  | March_tir.Repr.Boxed -> ()
  | _ -> Alcotest.fail "expected Boxed for 2-field ctor"

let test_repr_scalar_is_boxed () =
  (* Bare scalars are not TCon ctors — classify as Boxed (irrelevant). *)
  match March_tir.Repr.repr_of_ty [] March_tir.Tir.TInt with
  | March_tir.Repr.Boxed -> ()
  | _ -> Alcotest.fail "expected Boxed for TInt"
```

Register them in the test list (find the `("join_points", [ … ])` group and add a sibling group):

```ocaml
      ("repr", [
        Alcotest.test_case "newtype_int"          `Quick test_repr_newtype_int;
        Alcotest.test_case "newtype_ptr"          `Quick test_repr_newtype_ptr;
        Alcotest.test_case "multivariant_boxed"   `Quick test_repr_multivariant_is_boxed;
        Alcotest.test_case "multifield_boxed"     `Quick test_repr_multifield_is_boxed;
        Alcotest.test_case "scalar_boxed"         `Quick test_repr_scalar_is_boxed;
      ]);
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune build --root . test/run_codegen.exe 2>&1 | grep -v shift/reduce | head && ./_build/default/test/run_codegen.exe -e 2>&1 | grep -i "repr"`
Expected: the `newtype_int`/`newtype_ptr` cases FAIL (classifier returns `Boxed`); the three `*_boxed` cases pass (stub returns `Boxed`).

- [ ] **Step 3: Implement newtype classification**

Replace the `repr_of_ty` stub in `lib/tir/repr.ml`:

```ocaml
let repr_of_ty (type_defs : Tir.type_def list) (ty : Tir.ty) : repr =
  match ty with
  | Tir.TCon (name, _) ->
    (match find_variant type_defs name with
     (* Newtype: exactly one variant with exactly one field. *)
     | Some [ (_ctor, [ payload ]) ] -> Newtype payload
     | _ -> Boxed)
  | _ -> Boxed
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dune build --root . test/run_codegen.exe 2>&1 | grep -v shift/reduce | head && ./_build/default/test/run_codegen.exe -e 2>&1 | grep -i "repr"`
Expected: all five `repr` cases `[OK]`.

- [ ] **Step 5: Commit**

```bash
git add lib/tir/repr.ml test/test_codegen.ml
git commit -m "feat(tir): classify newtypes in Repr.repr_of_ty (P6 milestone 1)"
```

---

## Phase 2 — Newtype unboxing at the three consultation sites

> Phase 2 changes behavior. Each task adds the consultation plus a test that locks
> it, and the FULL suite (`run_codegen` + `run_stdlib`) is the regression gate —
> newtypes already exist in the stdlib, so any miscompile shows up there.

### Task 3: Make Perceus `needs_rc` repr-aware

A newtype over a scalar (e.g. `UserId(Int)`) must carry NO reference counting; a newtype over a pointer (`Wrap(String)`) must forward RC to the payload (which `needs_rc TString = true` already does, so behavior is unchanged for that case). The change: when a `TCon` is a `Newtype`, decide `needs_rc` from the PAYLOAD's representation, not the wrapper.

**Files:**
- Modify: `lib/tir/perceus.ml` (the `needs_rc` function at line 179, and thread `type_defs` from the module entry point)
- Test: `test/test_codegen.ml`

- [ ] **Step 1: Write the failing behavioral test**

Append to `test/test_codegen.ml` a compiled end-to-end test that exercises a scalar newtype in an RC-sensitive position. Follow the existing compiled-regression pattern used by the `run_stdlib` adversarial tests (compile a `.march` string, run the binary, assert stdout). Minimal program:

```
mod Main do
  type Counter = Counter(Int)
  fn bump(c) do
    match c do
      Counter(n) -> Counter(n + 1)
    end
  end
  fn unwrap(c) do match c do Counter(n) -> n end end
  fn main() do
    let c = Counter(41)
    print(int_to_string(unwrap(bump(c))))
  end
end
```

Expected stdout: `42`.

(If a TIR-level assertion is preferred over compile-and-run: assert that after `Perceus.perceus`, the body of `bump`/`unwrap` contains no `EIncRC`/`EDecRC` whose atom has type `TCon("Counter", _)`. Use whichever harness the surrounding tests use; the compile-and-run form is the stronger correctness check.)

- [ ] **Step 2: Run to verify current behavior**

Run: compile and run the program above with `./_build/default/bin/main.exe`.
Expected BEFORE the fix: prints `42` but with a redundant heap allocation + RC per `Counter` (correct output, wasteful code). The behavioral test passes on output; the IR test in Task 4/5 is what will fail pre-fix. This task's value is removing RC on the scalar payload — verify via `--dump-tir` that `Counter` values currently flow as `TCon("Counter", …)` through `needs_rc`-driven RC ops.

- [ ] **Step 3: Thread `type_defs` into `needs_rc`**

At [lib/tir/perceus.ml:179](lib/tir/perceus.ml:179), change `needs_rc` to consult repr. Because `needs_rc` is called widely, add a repr-aware variant and route the module-level entry point's `type_defs` to it. Concretely:

```ocaml
(* repr-aware heap-ness. A Newtype's heap-ness is its payload's heap-ness;
   recurse so newtype-of-newtype resolves. Boxed/other types unchanged. *)
let rec needs_rc_with (type_defs : Tir.type_def list) (ty : Tir.ty) : bool =
  match ty with
  | Tir.TCon (_, _) ->
    (match Repr.repr_of_ty type_defs ty with
     | Repr.Newtype payload -> needs_rc_with type_defs payload
     | Repr.Boxed | Repr.Niche _ -> needs_rc ty)   (* fall back to the scalar rule *)
  | _ -> needs_rc ty
```

`needs_rc` has ~20 call sites across several helpers, so explicit signature-threading is invasive. Pragmatic mechanism (matches how an internal pass holds per-run context): add a module-level `let cur_type_defs : Tir.type_def list ref = ref []`, set it once at the top of the `perceus` entry (`cur_type_defs := m.tm_types`), and redefine `needs_rc` itself to consult repr:

```ocaml
let cur_type_defs : Tir.type_def list ref = ref []

let rec needs_rc (ty : Tir.ty) : bool =
  match ty with
  | Tir.TCon ("Atom", []) -> false
  | Tir.TCon (name, _) ->
    (match Repr.repr_of_ty !cur_type_defs ty with
     | Repr.Newtype payload -> needs_rc payload
     | Repr.Boxed | Repr.Niche _ -> true)   (* boxed TCon → heap *)
  | Tir.TString | Tir.TPtr _ -> true
  | _ -> false
```

This keeps every existing `needs_rc ty` call site unchanged — they transparently become repr-aware. The `ref` is safe: `perceus` runs single-threaded and sets it before any traversal. Verify `cur_type_defs` is assigned before the first `needs_rc` call in the entry function.

- [ ] **Step 4: Build and run the full codegen + stdlib suites**

Run:
```
dune build --root . bin/main.exe test/run_codegen.exe test/run_stdlib.exe 2>&1 | grep -v shift/reduce | head
./_build/default/test/run_codegen.exe -e >/dev/null 2>&1; echo "codegen exit=$?"
HOME=/tmp/marchhome_p6 ./_build/default/test/run_stdlib.exe >/dev/null 2>&1; echo "stdlib exit=$?"
```
Expected: both exit `0` (the 2 pre-existing `simplify` str-concat failures in codegen are known; confirm no NEW failures). The Counter program prints `42`.

- [ ] **Step 5: Commit**

```bash
git add lib/tir/perceus.ml test/test_codegen.ml
git commit -m "feat(perceus): repr-aware needs_rc — no RC for scalar newtypes (P6)"
```

---

### Task 4: Emit newtype construction as the raw payload (no `march_alloc`)

**Files:**
- Modify: `lib/tir/llvm_emit.ml` — the emit context (`make_ctx` near line 156) to carry `type_defs`; the EAlloc emission at line 3029.
- Test: `test/test_codegen.ml`

- [ ] **Step 1: Write the failing IR test**

Follow the `native_arrays` IR-test pattern (compile a module to LLVM text and inspect it). Assert that for the `Counter` program above, the emitted IR for `Counter(n + 1)` contains NO `march_alloc` call attributable to the `Counter` constructor. Concretely: emit the module's LLVM, `grep -c "march_alloc"` in the `bump` function region, expect `0` for the newtype construction. Reuse the harness the `native_arrays` group uses for obtaining emitted IR.

- [ ] **Step 2: Run to verify it fails**

Run the test. Expected: FAIL — `march_alloc(i64 24)` is currently emitted for `Counter(n+1)`.

- [ ] **Step 3: Carry `type_defs` on the emit context and consult repr at EAlloc**

In the emit context record (the struct constructed by `make_ctx`, near [lib/tir/llvm_emit.ml:156](lib/tir/llvm_emit.ml:156)), add a field `type_defs : Tir.type_def list` and populate it from `tm_types` at the top-level emit entry. Then at the constructor EAlloc case ([lib/tir/llvm_emit.ml:3029](lib/tir/llvm_emit.ml:3029)):

- Compute `Repr.repr_of_ty ctx.type_defs (TCon (type_name, _))` for the constructor's owning type. (The owning type name is recoverable from `ctor_info`/the qualified tag, as the surrounding code already does for tag lookup.)
- If the result is `Newtype _`: bind the constructor's result to its single argument atom directly (emit the atom, no `march_alloc`, no field store). The result SSA value is the payload value itself.
- Otherwise: emit as today.

- [ ] **Step 4: Run the IR test + behavioral test + full suites**

Run: the IR test (expect `march_alloc` count `0` for `Counter`), the Counter program (expect `42`), then:
```
./_build/default/test/run_codegen.exe -e >/dev/null 2>&1; echo "codegen exit=$?"
HOME=/tmp/marchhome_p6 ./_build/default/test/run_stdlib.exe >/dev/null 2>&1; echo "stdlib exit=$?"
```
Expected: IR test PASS, output `42`, both suites exit `0` (no new failures).

- [ ] **Step 5: Commit**

```bash
git add lib/tir/llvm_emit.ml test/test_codegen.ml
git commit -m "feat(emit): unbox newtype construction (no alloc) (P6)"
```

---

### Task 5: Emit newtype pattern-match as a direct bind (no tag load)

**Files:**
- Modify: `lib/tir/llvm_emit.ml` — `emit_case` at line 3377.
- Test: `test/test_codegen.ml`

- [ ] **Step 1: Write the failing IR test**

Assert that for `match c do Counter(n) -> n end`, the emitted IR does NOT load a tag/field from a heap pointer — instead `n` is bound directly to the scrutinee SSA value. Concretely: in the `unwrap` function region, assert there is no `getelementptr`/tag-load for the `Counter` scrutinee and that the result equals the scrutinee. (A simpler, robust proxy: assert no `march_alloc` AND that the program output is `42` AND, combined with Task 4, that round-tripping `Counter(41)` → `unwrap` yields `41` with zero heap ops — verify by `grep -c march_alloc` over the whole `main`+`bump`+`unwrap` IR equals the count expected for non-newtype allocations only.)

- [ ] **Step 2: Run to verify it fails**

Run the test. Expected: FAIL — `emit_case` currently emits a tag dispatch + field GEP for `Counter`.

- [ ] **Step 3: Consult repr in `emit_case`**

At the top of `emit_case` ([lib/tir/llvm_emit.ml:3377](lib/tir/llvm_emit.ml:3377)), compute the scrutinee's repr from its type. If `Newtype _` (which implies exactly one branch and one bound field):

- Bind the single field variable to the scrutinee SSA value directly (an SSA alias / `add i64 %scrut, 0` or reuse the value as the field's name in the local env, matching how the surrounding code names bound vars).
- Emit the single branch body. No `switch`, no tag load, no field GEP.

Otherwise emit as today.

- [ ] **Step 4: Run the IR test + behavioral test + full suites**

Run: the IR test, the Counter program (`42`), then both suites:
```
./_build/default/test/run_codegen.exe -e >/dev/null 2>&1; echo "codegen exit=$?"
HOME=/tmp/marchhome_p6 ./_build/default/test/run_stdlib.exe >/dev/null 2>&1; echo "stdlib exit=$?"
```
Expected: IR test PASS, output `42`, both suites exit `0`.

- [ ] **Step 5: Commit**

```bash
git add lib/tir/llvm_emit.ml test/test_codegen.ml
git commit -m "feat(emit): unbox newtype pattern-match (direct bind) (P6)"
```

---

### Task 6: End-to-end validation under the sanitizer + a newtype-in-data-structure test

**Files:**
- Test: `test/test_codegen.ml` (or the stdlib adversarial-regression suite, matching where compiled sanitizer tests live)

- [ ] **Step 1: Write a newtype-crosses-boundary + stored-in-list test**

Program that returns newtypes from functions and stores them in a `List`, ensuring the unboxed representation survives boundaries and data structures:

```
mod Main do
  type Id = Id(Int)
  fn mk(n) do Id(n * 2) end
  fn sum_ids(xs, acc) do
    match xs do
      [] -> acc
      [Id(n), ..rest] -> sum_ids(rest, acc + n)
    end
  end
  fn main() do
    let xs = [mk(1), mk(2), mk(3)]
    print(int_to_string(sum_ids(xs, 0)))
  end
end
```

Expected stdout: `12`.

- [ ] **Step 2: Run interpreted and compiled; verify equal output**

Run:
```
./_build/default/bin/main.exe /tmp/p6_e2e.march            # interpreter
./_build/default/bin/main.exe --compile -o /tmp/p6_e2e.bin /tmp/p6_e2e.march && /tmp/p6_e2e.bin
```
Expected: both print `12`.

- [ ] **Step 3: Run the compiled binary under the sanitizer**

Run with `MARCH_SANITIZE` per the project's sanitizer convention (see the compiled adversarial-regression tests in `run_stdlib`), or compile with the runtime ASan flags the repo uses. Expected: clean exit, no ASan reports (no leak from the now-unboxed `Id`, no double-free).

- [ ] **Step 4: Re-run the full suite as the final gate**

Run:
```
dune build --root . 2>&1 | grep -v shift/reduce | head
./_build/default/test/run_compiler.exe -e >/dev/null 2>&1; echo "compiler exit=$?"
./_build/default/test/run_eval.exe -e >/dev/null 2>&1; echo "eval exit=$?"
./_build/default/test/run_codegen.exe -e >/dev/null 2>&1; echo "codegen exit=$?"
HOME=/tmp/marchhome_p6 ./_build/default/test/run_stdlib.exe >/dev/null 2>&1; echo "stdlib exit=$?"
```
Expected: all exit `0` (codegen has the 2 known pre-existing `simplify` failures only).

- [ ] **Step 5: Commit**

```bash
git add test/test_codegen.ml
git commit -m "test(p6): newtype boundary + list + sanitizer e2e"
```

---

### Task 7: Update specs

**Files:**
- Modify: `specs/optimizations.md` (§P6), `specs/todos.md`, `specs/progress.md`

- [ ] **Step 1: Update `specs/optimizations.md` §P6**

Change the §P6 status to record milestone 1: "Newtype unboxing — Done. `lib/tir/repr.ml` derives representation post-mono; consulted at EAlloc emission, `emit_case`, and Perceus `needs_rc`. Single-variant single-field types carry no allocation/tag/RC. Option-niche is the follow-on milestone." Keep the design link.

- [ ] **Step 2: Update `specs/todos.md`**

Add a `✅` line for "P6 milestone 1 — newtype unboxing" and a `[ ]` line for "P6 milestone 2 — Option-shaped niche (None=0, Some(x)=x) + runtime ABI flip", linking the design doc.

- [ ] **Step 3: Update `specs/progress.md`**

Add a new `## Current State` entry (newest at top) describing the `Repr` module + newtype unboxing, with the verified suite counts.

- [ ] **Step 4: Commit**

```bash
git add specs/optimizations.md specs/todos.md specs/progress.md
git commit -m "docs(specs): record P6 milestone 1 — newtype unboxing"
```

---

## Self-Review Notes (author)

- **Spec coverage:** This plan covers design §§2–3 (Repr module, derived table), §3 sites 1–3 for the Newtype case, §6 phase 1–2, §7 testing. Design §1 Option-niche, §4 runtime ABI, and the niche soundness table are intentionally deferred to milestone 2 (a separate plan) — newtypes need none of the runtime/ABI change.
- **Type consistency:** `repr` constructors (`Boxed`/`Newtype`/`Niche`) are used identically across Tasks 1–5; `needs_rc_with` is the single new RC entry point; `ctx.type_defs` is the one new context field.
- **Known caveats made explicit:** the two pre-existing `simplify` failures are called out so a worker does not mistake them for regressions; `HOME` is isolated for the stdlib JIT `.so` cache per the repo's cross-session-cache hazard.
- **Emit-site contract:** Tasks 4–5 specify the exact file/function/line and the precise transformation + a locking test, but defer the exact LLVM-string diff to execution against live code (the emit code uses an intricate tagging convention; fabricating the diff here would risk being subtly wrong). The test is the contract.
