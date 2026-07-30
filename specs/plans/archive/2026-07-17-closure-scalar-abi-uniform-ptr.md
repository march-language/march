# Uniform ptr closure scalar ABI (sort-RC crash fix) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the compiled closure-dispatch ABI represent every scalar (Int/Bool/Float) uniformly as a `ptr` (tagged immediate for Int/Bool, `march_float_box` for Float) at **every** call path and apply-fn boundary, eliminating the `march_incrc`-on-raw-Int SIGSEGV in generic-Int closures (heapsort/mergesort/… over `List(Int)`).

**Architecture:** A closure's apply function is shared across all instantiations of a generic, so its scalar parameters can only use the one erased representation: `ptr`. Today the ABI is inconsistent — an apply fn's params are `ptr` (when the lambda stayed polymorphic) or raw `i64`/`double` (when mono specialized it), and it is reached by *both* indirect `ECallPtr` dispatch *and* direct `EApp` calls (defun rewrites non-escaping `ECallPtr`→`EApp`). Callers pass raw scalars while `ptr`-param apply fns then RC them as heap pointers. The fix makes **all four** boundaries agree on `ptr`: the two call paths encode scalars to `ptr`, and the apply-fn / `clo_wrap` decode at entry to whatever their body expects.

**Tech Stack:** OCaml 5.3 compiler (`lib/tir/*.ml` codegen), LLVM IR text emission, C runtime (`runtime/*.c`), alcotest suites (`test/run_*.exe`), native golden tests (`test/native/*.march` + `.expected` + `test/dune` rules), `bench/*.march` compiled benchmarks.

## Global Constraints

- Build the compiler with `dune build --root . bin/main.exe`. **Never** run a bare `dune build --root .` with no target (it wedges at 0% CPU after building binaries).
- Run alcotest suites via the built exes: `./_build/default/test/run_{eval,compiler,codegen,stdlib,snapshots}.exe -e`. Judge by exit code, not tail output (rule failures hide above a green summary). `run_stdlib.exe -e` is the FULL suite (~100s, includes compiled float/sort adversarial regressions); `-q` skips the Slow tests.
- Compile a program with `MARCH_STDLIB="$PWD/stdlib" ./_build/default/bin/main.exe --compile --opt 2 <file>.march -o <out>`. **Never pipe `--compile` output** (the compiler child holds the pipe open and wedges) — redirect to a file, judge by `$?`.
- The CAS artifact cache is at **`$PWD/.march/cas`** for a worktree (NOT `/Users/80197052/code/march/.march`). Clear it with `rm -rf "$PWD/.march/cas"` when a stale "(cached)" binary is served after a compiler change. The cache key already digests the compiler exe, so a rebuilt compiler normally invalidates it automatically.
- Stage files explicitly by name in commits (never `git add -A`/`.`). No `Co-Authored-By` lines.
- Never `git stash` in this worktree (the stash stack is shared across worktrees).
- This is a **flag day**: Tasks 2–5 (the four ABI boundaries + runtime) change one representation everywhere and MUST be validated together (Task 7). A partial landing (e.g. call sites tag but apply fns don't decode) miscompiles every int closure. Commit Tasks 2–6 individually for reviewability, but do NOT consider the feature landed until Task 7 is green.

---

## Background: root cause and two DEAD-END attempts (do not repeat)

**Root cause (verified by lldb + IR).** `heap_merge_h` compiles the comparator call as `call ptr (ptr, i64) %fv(ptr %clo, i64 %x)` — it passes the Int element as a **raw `i64`**, but the comparator's apply wrapper is declared `(ptr %clo, ptr %x.arg)`. The raw even Int (e.g. `79548`) is stored as a "pointer"; because `needs_rc (TVar _) = true` (`lib/tir/rc_types.ml:117`) the apply fn emits `march_incrc_local` on it → deref of a garbage address → SIGSEGV. This is the exact Int analog of the float register-mismatch fixed in the float-boxing flip (`specs/plans/2026-07-15-float-boxing-execution-subplan.md`): for floats the *value* corrupted (FP vs GP register); for ints the value survives but **RC crashes on the untagged even Int**.

**Why a naive fix fails — the two attempts and what each broke:**

1. *Call-site tag only* (ECallPtr `orig_param_llvm_tys`: map `i64`→`ptr` so the arg is tagged): fixed 5/6 sort benches, but `introsort` produced a wrong answer and `List.map([…], inc)` / a specialized `fn x -> x*2` returned garbage (`22`) — the apply fn / `clo_wrap` read the *tagged* value as a raw `i64` and did arithmetic on it.
2. *Call-site tag + apply-fn entry untag* (also declare apply-fn `i64` params as `ptr` and conditionally untag at entry): fixed `introsort` and the specialized lambdas, but broke the curried `adder` (`add10(5)` → `12` instead of `15`) and 2 stdlib tests. Cause: **`add10(5)` is a DIRECT `EApp` call** emitted as `call ptr @$lam…$apply(ptr %clo, i64 5)` — it passes a **raw** `i64 5`, and the entry untag (`ashr` iff odd) then ashr'd the odd `5` → `2`.

**The lesson both attempts teach:** tagging at *one* call path (ECallPtr) while another path (direct `EApp`) still passes raw, combined with an entry decode that assumes "always tagged", is self-inconsistent. The fix must make **every** path that reaches an apply fn encode scalars to `ptr`, so the entry decode's assumption holds universally.

**The four boundaries that must agree (all on `ptr`):**
| # | Boundary | File | Today | Needed |
|---|---|---|---|---|
| A | `ECallPtr` (indirect closure dispatch) | `lib/tir/llvm_emit.ml` (~2286, the `orig_param_llvm_tys` remap already added for `double`) | tags nothing for `i64`; passes raw | tag `i64` / box `double` |
| B | Direct `EApp` call to an apply fn | `lib/tir/llvm_emit.ml` EApp arm (the site emitting `call ptr @$lam…$apply(…, i64 N)`) | passes raw `i64`/`double` | tag `i64` / box `double` |
| C | Apply-fn definition (signature + entry) | `lib/tir/llvm_toplevel.ml` `emit_fn` (~181 `is_apply_wrapper`, ~236 param_slots) | `double` already ptr+unbox; `i64` still raw | `i64` param → ptr, entry untag → raw slot |
| D | `clo_wrap` (named-fn → closure trampoline) | `lib/tir/llvm_calls.ml` `clo_wrap_define` (~139) | `double` already ptr+unbox; `i64` still raw | `i64` param → ptr, untag before forwarding |

The float half of A/C/D already landed (in the pushed float-boxing commits); this plan adds the `i64` half **and** the entirely new boundary B.

---

## Task 1: Pin the direct-`EApp`-to-apply-fn emit site and confirm the four-boundary inventory

**Files:**
- Inspect: `lib/tir/llvm_emit.ml` (EApp match arms), `lib/tir/defun.ml:~383` (`is_apply_fn` synthesis / the `ECallPtr`→`EApp` rewrite), `lib/tir/tir_names.ml` (`is_apply_fn`)
- Repro: `/private/tmp/hs3.march`, `/private/tmp/adder.march` (created below)

**Interfaces:**
- Produces: the exact `llvm_emit.ml` line range of the EApp arm that emits `call ptr @<applyfn>(...)` for a direct (defun-rewritten) closure call, and confirmation of whether it shares argument-emission code with the general EApp path or is a distinct arm. Later tasks (esp. Task 3) edit this site.

- [ ] **Step 1: Build the compiler at the current (clean) HEAD and create the two canonical repros**

Run:
```bash
cd /Users/80197052/code/march/.claude/worktrees/pr-27-merge-conflicts-a01119
dune build --root . bin/main.exe
cat > /private/tmp/hs3.march <<'EOF'
mod M do
  pfn gen(n:Int, seed:Int, acc:List(Int)):List(Int) do
    if n == 0 do acc else do
      let next = (seed*1664525 + 1013904223) % 1000000
      gen(n-1, next, Cons(next % 100000, acc)) end end
  end
  pfn head(xs:List(Int)):Int do match xs do Nil -> 0 Cons(h,_) -> h end end
  pfn main():Unit do
    println(int_to_string(head(Sort.heapsort_by(gen(3, 42, Nil), fn x -> fn y -> x <= y))))
  end
end
EOF
cat > /private/tmp/adder.march <<'EOF'
mod M do
  fn main() do
    let adder = fn n -> fn x -> x + n
    let add10 = adder(10)
    println(int_to_string(add10(5)))          -- expect 15
    println(int_to_string(List.head(List.map([10,20,30], fn x -> x + 1))))  -- expect 11
  end
end
EOF
```
Expected: build succeeds; both files compile.

- [ ] **Step 2: Emit IR for both and locate the direct apply-fn call**

Run:
```bash
MARCH_STDLIB="$PWD/stdlib" ./_build/default/bin/main.exe --emit-llvm /private/tmp/adder.march -o /private/tmp/adder >/dev/null 2>&1
grep -nE 'call ptr @\$lam[0-9]+\$apply' /private/tmp/adder.march.ll
```
Expected: at least one `call ptr @$lam…$apply$NNNN(ptr %…, i64 5)` — a DIRECT call passing a raw `i64`. Record its shape.

- [ ] **Step 3: Find the EApp arm in `llvm_emit.ml` that emits that direct call**

Run:
```bash
grep -nE 'is_apply_fn|call ptr @%s\(|apply.*call|@%s\(%s\)' lib/tir/llvm_emit.ml | head -40
```
Read the EApp arm(s) that resolve a callee name to a top-level fn and emit `call <ret> @<name>(<args>)`. Confirm whether it consults `Tir_names.is_apply_fn` and how it builds `<args>` (does it `coerce` each arg to the callee's declared param type, or pass the arg's own llvm type?). **Write down** the line range and the argument-emission expression — Task 3 modifies exactly this.

- [ ] **Step 4: Confirm the apply-fn signature source**

Read `lib/tir/llvm_toplevel.ml:181-252` (the `is_apply_wrapper` param handling already present for `double`). Confirm: an apply-fn parameter's declared LLVM type comes from `Llvm_ctx.llvm_param_ty v.Tir.v_ty`, and a parameter whose TIR type is a concrete `Int`/`Bool` yields `"i64"` while a `TVar` yields `"ptr"`. This is the discriminator Task 4 keys on.

- [ ] **Step 5: Record the inventory decision**

In a scratch note (not committed), confirm the four boundaries A/B/C/D map to concrete sites:
- A: `llvm_emit.ml` `orig_param_llvm_tys` remap (float already there) — add `i64`.
- B: the EApp-direct-apply-call arm found in Step 3 — **new** arg coercion.
- C: `llvm_toplevel.ml emit_fn` `is_apply_wrapper` param — add `i64` ptr+untag.
- D: `llvm_calls.ml clo_wrap_define` — add `i64` ptr+untag.
No code change in this task. **Do not commit** (investigation only).

---

## Task 2: Runtime defense-in-depth — make `march_incrc`/`march_decrc` provably skip tagged immediates

**Files:**
- Modify: `runtime/march_runtime.c` (`march_incrc`, `march_decrc`, `march_incrc_local`, `march_decrc_local` — near line 192-290)
- Test: `test/native/tagged_int_rc.march` + `.expected` + a `test/dune` rule

**Interfaces:**
- Produces: guarantee that `march_incrc(p)` / `march_decrc(p)` are no-ops when `((uintptr_t)p & 1) != 0` (a tagged immediate). This makes the whole ABI robust: even if a boundary is momentarily missed during the flag day, a *tagged* int in a ptr slot is RC-inert (only an *untagged* even int crashes). This is NOT the fix (the fix is the ABI), but it turns "raw odd int reaches incrc" from a crash into a no-op and hardens against regressions.

- [ ] **Step 1: Read the current RC ops and check the existing guard**

Run:
```bash
sed -n '190,300p' runtime/march_runtime.c
grep -n 'IS_HEAP_PTR\|& 1\|& 1u\|>> 1' runtime/march_runtime.c | head
```
Expected: confirm whether `march_incrc`/`march_decrc` already test the low tag bit / `IS_HEAP_PTR` before touching `p->rc`. (If they already skip odd pointers, this task only ADDS the test fixture — the ABI fix in Tasks 3-6 is then what prevents the *even raw int* case, and this guard covers the *odd raw int* case.)

- [ ] **Step 2: Write the failing native test**

Create `test/native/tagged_int_rc.march`:
```march
-- A generic Int closure that captures its Int arg and is RC-tracked: exercises
-- march_incrc on a value that MUST be a tagged immediate, never a heap deref.
mod Main do
  fn apply_twice(f, x) do
    let a = f(x)
    let b = f(x)
    a + b
  end
  fn main() do
    -- fn captures nothing but forces the erased-Int RC path through a HOF
    println(int_to_string(apply_twice(fn n -> n * 3, 7)))   -- 21 + 21 = 42
  end
end
```
Create `test/native/tagged_int_rc.expected`:
```
42
```

- [ ] **Step 3: Add the `test/dune` rule (copy the `native_signal_watch` rule shape, with `(source_tree ../stdlib)`)**

Add to `test/dune` (near the other `native_*` rules):
```
(rule
 (targets native_tagged_int_rc native_tagged_int_rc.out)
 (deps (file %{exe:../bin/main.exe})
       (file ../runtime/march_runtime.c) (file ../runtime/march_runtime.h)
       (file ../runtime/march_scheduler.c) (file ../runtime/march_scheduler.h)
       (file ../runtime/march_heap.c) (file ../runtime/march_heap.h)
       (file ../runtime/march_gc.c) (file ../runtime/march_gc.h)
       (file ../runtime/march_message.c) (file ../runtime/march_message.h)
       (file ../runtime/march_deque.h)
       (file ../runtime/march_extras.c) (file ../runtime/march_compress.c)
       (file ../runtime/base64.c) (file ../runtime/sha1.c)
       (file native/tagged_int_rc.march)
       (source_tree ../stdlib))
 (action
  (progn
   (run %{exe:../bin/main.exe} --compile -o native_tagged_int_rc
        native/tagged_int_rc.march)
   (with-stdout-to native_tagged_int_rc.out
        (system "./native_tagged_int_rc")))))

(rule
 (alias runtest)
 (action (diff native/tagged_int_rc.expected native_tagged_int_rc.out)))
```

- [ ] **Step 4: Run it — it may already crash (the bug) or pass (if this HOF shape avoids it)**

Run:
```bash
dune build --root . test/native_tagged_int_rc.out 2>&1 | tail -5
```
Expected: EITHER a SIGSEGV/mismatch (this shape reproduces the RC bug — good, it's now a pinned test) OR a pass (this shape doesn't hit it — keep the test as a regression guard and rely on Task 7's sort benches for the reproducing case). Record which.

- [ ] **Step 5: Add the tag-bit guard to the RC ops (if not already present)**

In `runtime/march_runtime.c`, ensure each of `march_incrc`, `march_decrc`, `march_incrc_local`, `march_decrc_local` early-returns for a tagged immediate. Example for `march_incrc`:
```c
void march_incrc(void *p) {
    if (((uintptr_t)p & 1u) != 0) return;  /* tagged immediate — not heap-allocated */
    if (!p) return;
    atomic_fetch_add_explicit((_Atomic int64_t *)p, 1, memory_order_relaxed);
}
```
(Match the existing body; only add the leading tag-bit test if absent. Do the same guard in the other three.) **NOTE:** this does NOT fix the reported bug (that value is an *even* raw int, tag bit 0). It hardens the *odd* raw-int case and is cheap insurance for the flag day. If Step 1 shows the guards already exist, skip the edit and keep only the test.

- [ ] **Step 6: Rebuild runtime-dependent target and re-run**

Run:
```bash
rm -rf "$PWD/.march/cas"
dune build --root . test/native_tagged_int_rc.out 2>&1 | tail -3
```
Expected: PASS (diff clean).

- [ ] **Step 7: Commit**

```bash
git add runtime/march_runtime.c test/native/tagged_int_rc.march test/native/tagged_int_rc.expected test/dune
git commit -m "runtime: RC ops skip tagged immediates + tagged-int RC native golden"
```

---

## Task 3: Boundary A + B — every call site encodes scalar args to ptr

**Files:**
- Modify: `lib/tir/llvm_emit.ml` — the `ECallPtr` `orig_param_llvm_tys` remap (boundary A, ~line 2286) AND the EApp-direct-apply-call arm found in Task 1 Step 3 (boundary B)
- Test: reuse `/private/tmp/hs3.march`, `/private/tmp/adder.march`

**Interfaces:**
- Consumes: `Llvm_ctx.coerce ctx from_ty v "ptr"` — already tags `i64`→ptr (`emit_tag_scalar`, `(n<<1)|1`) and boxes `double`→ptr (`march_alloc_float`). This is the single encode primitive both boundaries use.
- Produces: after this task, EVERY call reaching an apply fn passes scalars as `ptr`. Task 4 (apply-fn entry decode) depends on this invariant holding at both call paths.

- [ ] **Step 1: Boundary A — extend the ECallPtr remap to `i64`**

In `lib/tir/llvm_emit.ml`, change the `orig_param_llvm_tys` remap (currently `if t = "double" then "ptr" else t`) to also remap `i64`:
```ocaml
    let orig_param_llvm_tys =
      List.map (fun t -> if t = "double" || t = "i64" then "ptr" else t) orig_param_llvm_tys in
```
(The existing `coerce ctx actual_ty v pty` loop then tags/boxes each scalar arg because `pty` is now `"ptr"`.)

- [ ] **Step 2: Boundary B — tag/box scalar args at the direct EApp-to-apply-fn call**

At the EApp arm identified in Task 1 (the one emitting `call <ret> @<applyfn>(<clo>, <args>)` when `Tir_names.is_apply_fn <callee>`), coerce each scalar argument to `ptr` before emitting the call, and declare the call's parameter types as `ptr` for those args — mirroring boundary A. The precise edit depends on Task 1's finding; the shape is: for each arg, if its declared param type is `"i64"` or `"double"`, emit `let v' = coerce ctx actual_ty v "ptr"` and use `"ptr"` in the call signature. If this arm currently reuses a shared helper with the general EApp path, guard the remap on `Tir_names.is_apply_fn callee` so ONLY apply-fn calls are affected (a direct call to a normal top-level fn keeps its concrete ABI).

- [ ] **Step 3: Build**

Run: `dune build --root . bin/main.exe 2>&1 | tail -5`
Expected: build succeeds.

- [ ] **Step 4: Verify the direct call now tags (IR check)**

Run:
```bash
rm -rf "$PWD/.march/cas"
MARCH_STDLIB="$PWD/stdlib" ./_build/default/bin/main.exe --emit-llvm /private/tmp/adder.march -o /private/tmp/adder >/dev/null 2>&1
grep -nE 'call ptr @\$lam[0-9]+\$apply' /private/tmp/adder.march.ll
```
Expected: the direct apply calls now pass `ptr %…` (a tagged value), NOT `i64 5`. There should be a `shl`/`or`/`inttoptr` tagging the `5` just above the call.

- [ ] **Step 5: Confirm this task alone does NOT yet produce correct output (expected mid-flag-day)**

Run:
```bash
MARCH_STDLIB="$PWD/stdlib" ./_build/default/bin/main.exe --compile --opt 2 /private/tmp/adder.march -o /private/tmp/adder_bin >/dev/null 2>&1
/private/tmp/adder_bin
```
Expected: WRONG output (e.g. arithmetic on tagged values) — because boundaries C/D don't yet decode. This is the flag-day midpoint; it becomes correct after Task 4. **Do not treat this as failure.**

- [ ] **Step 6: Commit**

```bash
git add lib/tir/llvm_emit.ml
git commit -m "codegen: closure call sites (ECallPtr + direct EApp) pass scalars as ptr (boundary A+B)"
```

---

## Task 4: Boundary C — apply-fn params are ptr, decoded at entry to the body's representation

**Files:**
- Modify: `lib/tir/llvm_toplevel.ml` `emit_fn` — the `is_apply_wrapper` param signature (~185) and entry prologue (~242)
- Test: `/private/tmp/adder.march`, `/private/tmp/hs3.march`

**Interfaces:**
- Consumes: `Llvm_ctx.coerce ctx "ptr" "%<name>.arg" "i64"` (conditional untag `ashr` iff odd — safe because Task 3 guarantees the arg is now a tagged odd immediate) and the existing `march_unbox_float` path for `double`.
- Produces: an apply fn whose body sees each scalar param in the representation it was compiled against (raw `i64` for a concrete-Int-typed param; the body's own lazy `coerce` handles a `TVar`-typed param which is already `ptr`).

- [ ] **Step 1: Extend the signature remap to `i64` (mirror the `double` case already present)**

In `emit_fn`, the `params_str` mapping already does `if is_apply_wrapper && base = "double" then "ptr"`. Extend:
```ocaml
      let pty = if is_apply_wrapper && (base = "double" || base = "i64") then "ptr" else base in
```

- [ ] **Step 2: Extend the entry prologue to untag `i64` params into their raw slot**

In the `param_slots` loop, the `double` branch already unboxes. Add an `i64` branch (the arg arrives as a tagged ptr — Task 3 guarantees it — so conditionally untag into the raw `i64` slot the body reads):
```ocaml
    if is_apply_wrapper && ty = "double" then begin
      let d = Llvm_ctx.fresh ctx "cv" in
      Llvm_ctx.emit ctx (Printf.sprintf "%s = call double @march_unbox_float(ptr %%%s.arg)" d vn);
      Llvm_ctx.emit ctx (Printf.sprintf "store double %s, ptr %%%s.addr" d slot)
    end else if is_apply_wrapper && ty = "i64" then begin
      let u = Llvm_ctx.coerce ctx "ptr" (Printf.sprintf "%%%s.arg" vn) "i64" in
      Llvm_ctx.emit ctx (Printf.sprintf "store i64 %s, ptr %%%s.addr" u slot)
    end else
      Llvm_ctx.emit ctx (Printf.sprintf "store %s %%%s.arg, ptr %%%s.addr" ty vn slot);
```
**KEY:** this branch fires only when the param's `llvm_ty` is `"i64"` — i.e. the param's TIR type is a concrete `Int`/`Bool` and the body uses it raw. A `TVar` param has `llvm_ty = "ptr"`, does NOT enter this branch, keeps its `ptr` slot, and the body untags it lazily via its own `coerce` (unchanged behavior). This is why the earlier attempt's regression is now avoided: the arg is tagged at BOTH call paths (Task 3), so the conditional untag never ashr's a raw odd value.

- [ ] **Step 3: Build**

Run: `dune build --root . bin/main.exe 2>&1 | tail -5`
Expected: build succeeds.

- [ ] **Step 4: The adder is now correct**

Run:
```bash
rm -rf "$PWD/.march/cas"
MARCH_STDLIB="$PWD/stdlib" ./_build/default/bin/main.exe --compile --opt 2 /private/tmp/adder.march -o /private/tmp/adder_bin >/dev/null 2>&1
/private/tmp/adder_bin
```
Expected:
```
15
11
```
(interp gives the same — verify with `MARCH_STDLIB="$PWD/stdlib" ./_build/default/bin/main.exe /private/tmp/adder.march`.)

- [ ] **Step 5: The heapsort repro no longer crashes**

Run:
```bash
MARCH_STDLIB="$PWD/stdlib" ./_build/default/bin/main.exe --compile --opt 2 /private/tmp/hs3.march -o /private/tmp/hs3_bin >/dev/null 2>&1
/private/tmp/hs3_bin; echo "rc=$?"
```
Expected: prints a number, `rc=0` (was SIGSEGV 139), matching `MARCH_STDLIB="$PWD/stdlib" ./_build/default/bin/main.exe /private/tmp/hs3.march`.

- [ ] **Step 6: Commit**

```bash
git add lib/tir/llvm_toplevel.ml
git commit -m "codegen: apply-fn scalar params use ptr ABI, untag/unbox at entry (boundary C)"
```

---

## Task 5: Boundary D — `clo_wrap` (named-fn trampoline) decodes ptr scalar params

**Files:**
- Modify: `lib/tir/llvm_calls.ml` `clo_wrap_define` (~139)
- Test: `/private/tmp/named_hof.march` (created below)

**Interfaces:**
- Consumes: the tagged/boxed `ptr` args guaranteed by Task 3 (a named fn used as a closure is dispatched through `clo_wrap` via the same call paths).
- Produces: a `clo_wrap` that takes `ptr` scalar params and untags/unboxes each before forwarding to the concrete named fn (which expects raw `i64`/`double`).

- [ ] **Step 1: Write the failing test — a NAMED int fn used as a first-class closure**

Create `/private/tmp/named_hof.march`:
```march
mod M do
  fn dbl(x : Int) : Int do x * 2 end
  fn main() do
    println(int_to_string(List.head(List.map([10, 20, 30], dbl))))  -- expect 20
  end
end
```

- [ ] **Step 2: Confirm it is wrong before this task (clo_wrap reads the tagged value raw)**

Run:
```bash
rm -rf "$PWD/.march/cas"
MARCH_STDLIB="$PWD/stdlib" ./_build/default/bin/main.exe --compile --opt 2 /private/tmp/named_hof.march -o /private/tmp/named_bin >/dev/null 2>&1
/private/tmp/named_bin   # expect a WRONG value (tagged 10 read raw → e.g. 42), interp gives 20
```
Expected: wrong (e.g. `42`), demonstrating boundary D is still raw.

- [ ] **Step 3: Extend `clo_wrap_define`'s `wrapper_tys` and prologue to `i64`**

In `clo_wrap_define`, change `wrapper_tys` from `if t = "double" then "ptr"` to `if t = "double" || t = "i64" then "ptr"`, and add an `i64` case to the `call_arg_strs` prologue that conditionally untags before forwarding:
```ocaml
  let wrapper_tys =
    List.map (fun t -> if t = "double" || t = "i64" then "ptr" else t) param_ltys in
  ...
        end else if target_ty = "i64" then begin
          (* Int/Bool param arrives TAGGED — conditionally untag (ashr iff odd)
             to the raw i64 the concrete target expects. *)
          let i = name ^ "i" and a = name ^ "a" and c = name ^ "c"
          and s = name ^ "s" and u = name ^ "u" in
          Buffer.add_string prologue (Printf.sprintf
            "  %s = ptrtoint ptr %s to i64\n  %s = and i64 %s, 1\n  \
             %s = icmp ne i64 %s, 0\n  %s = ashr i64 %s, 1\n  \
             %s = select i1 %s, i64 %s, i64 %s\n"
            i name a i c a s i u c s i);
          "i64 " ^ u
        end else target_ty ^ " " ^ name)
```

- [ ] **Step 4: Build and verify correct**

Run:
```bash
dune build --root . bin/main.exe 2>&1 | tail -3
rm -rf "$PWD/.march/cas"
MARCH_STDLIB="$PWD/stdlib" ./_build/default/bin/main.exe --compile --opt 2 /private/tmp/named_hof.march -o /private/tmp/named_bin >/dev/null 2>&1
/private/tmp/named_bin
```
Expected: `20`.

- [ ] **Step 5: Commit**

```bash
git add lib/tir/llvm_calls.ml
git commit -m "codegen: clo_wrap decodes ptr scalar params (untag/unbox) before forwarding (boundary D)"
```

---

## Task 6: Extend the preamble golden if the golden byte-diff drifted

**Files:**
- Modify (only if the test fails): `test/test_codegen.ml` (`llvm_builtins_preamble_golden` blobs)

**Interfaces:**
- Consumes: nothing new. This task only reconciles the golden if Tasks 2-5 changed emitted preamble declares (they should NOT — no new `declare` is introduced, only existing `coerce`/tag IR — so this task is likely a no-op verification).

- [ ] **Step 1: Run the preamble golden**

Run: `./_build/default/test/run_codegen.exe test llvm_builtins_preamble_golden 2>&1 | grep -iE 'FAIL|OK|tests run'`
Expected: PASS (4/4). If it PASSES, skip to Task 7 (no commit).

- [ ] **Step 2 (only if failed): reconcile the golden**

If it fails, the diff shows exactly which declare line drifted; update the corresponding blob in `test/test_codegen.ml` to match, re-run, then `git add test/test_codegen.ml && git commit -m "test: reconcile preamble golden after closure-scalar-ABI"`.

---

## Task 7: Flag-day verification — the full failure-mode matrix, suite, benches, and oracle parity

**Files:**
- Create: `test/native/closure_scalar_abi.march` + `.expected` + `test/dune` rule (the consolidated regression golden)

**Interfaces:**
- Consumes: the complete four-boundary fix from Tasks 3-5.
- Produces: a permanent regression golden covering every failure mode, plus green suite/bench/oracle evidence.

- [ ] **Step 1: Create the consolidated native golden covering all failure modes**

Create `test/native/closure_scalar_abi.march`:
```march
-- Regression golden for the uniform ptr closure scalar ABI. Every line
-- exercises a distinct closure-dispatch path that the sort-RC crash / the two
-- dead-end attempts each broke:
mod Main do
  fn dbl(x : Int) : Int do x * 2 end                -- named fn (clo_wrap), boundary D
  fn main() do
    -- named-fn closure through a HOF (clo_wrap + ECallPtr):
    println(int_to_string(List.head(List.map([10, 20, 30], dbl))))          -- 20
    -- lambda closure through a HOF (apply-fn + ECallPtr):
    println(int_to_string(List.head(List.map([5, 6, 7], fn x -> x * 2))))   -- 10
    -- filter with a Bool-returning lambda:
    println(int_to_string(List.length(List.filter([1,2,3,4,5], fn x -> x > 2))))  -- 3
    -- curried closure with DIRECT EApp calls (boundary B) + arithmetic:
    let adder = fn n -> fn x -> x + n
    let add10 = adder(10)
    println(int_to_string(add10(5)))                                        -- 15
    -- generic-Int sort through a curried comparator (the reported crash):
    println(int_to_string(List.head(Sort.mergesort_by([5,2,8,1,9,3], fn a -> fn b -> a <= b))))  -- 1
    -- generic-String sort (poly_compare string path, unaffected):
    println(List.head(Sort.mergesort_by(["pear","apple","cherry"], fn a -> fn b -> a <= b)))     -- apple
    -- Float closure (regression guard for the earlier float-boxing flip):
    println(float_to_string(List.head(Sort.mergesort_by([3.5,-1.25,-9.0], fn a -> fn b -> a < b))))  -- -9.
  end
end
```
Create `test/native/closure_scalar_abi.expected`:
```
20
10
3
15
1
apple
-9.
```

- [ ] **Step 2: Add the `test/dune` rule (same shape as Task 2's, with `(source_tree ../stdlib)`) and run it**

Add the `native_closure_scalar_abi` rule + its `(alias runtest)` diff rule (copy Task 2's rule, rename, point at `native/closure_scalar_abi.march`). Then:
```bash
rm -rf "$PWD/.march/cas"
dune build --root . test/native_closure_scalar_abi.out 2>&1 | tail -5
diff test/native/closure_scalar_abi.expected _build/default/test/native_closure_scalar_abi.out && echo GOLDEN_PASS
```
Expected: `GOLDEN_PASS`.

- [ ] **Step 3: All six sort benches match the interpreter**

Run:
```bash
rm -rf "$PWD/.march/cas"
for b in heapsort mergesort alphadev_sort timsort introsort sort_nearly_sorted; do
  MARCH_STDLIB="$PWD/stdlib" ./_build/default/bin/main.exe --compile --opt 2 bench/$b.march -o /private/tmp/${b}_bin >/dev/null 2>&1
  ii=$(MARCH_STDLIB="$PWD/stdlib" ./_build/default/bin/main.exe bench/$b.march 2>&1 | head -1)
  co=$(/private/tmp/${b}_bin 2>&1 | head -1); rc=$?
  [ "$ii" = "$co" ] && echo "OK $b" || echo "MISMATCH $b interp=$ii compiled=$co rc=$rc"
done
```
Expected: all six `OK`, no `MISMATCH`, no nonzero `rc`.

- [ ] **Step 4: Full alcotest suite (all five runners)**

Run:
```bash
dune build --root . test/run_eval.exe test/run_compiler.exe test/run_codegen.exe test/run_stdlib.exe test/run_snapshots.exe
for r in eval compiler codegen snapshots; do ./_build/default/test/run_$r.exe -e >/tmp/sr_$r.log 2>&1; echo "$r: $(grep -c FAIL /tmp/sr_$r.log) FAIL / $(tail -1 /tmp/sr_$r.log)"; done
./_build/default/test/run_stdlib.exe -e >/tmp/sr_stdlib.log 2>&1; echo "stdlib: $(grep -c FAIL /tmp/sr_stdlib.log) FAIL / $(tail -1 /tmp/sr_stdlib.log)"
```
Expected: `0 FAIL` for all five (eval 233, compiler 514, codegen 421, snapshots 29, stdlib 809 — counts may grow by the new goldens).

- [ ] **Step 5: FFI + float goldens (shared-ABI regression guard)**

Run:
```bash
rm -rf "$PWD/.march/cas"
for t in float_boxing ffi_float ffi_codec2 ffi_optres signal_watch; do
  dune build --root . test/native_${t}.out >/dev/null 2>&1
  diff test/native/${t}.expected _build/default/test/native_${t}.out >/dev/null 2>&1 && echo "$t OK" || echo "$t FAIL"
done
```
Expected: all `OK`.

- [ ] **Step 6: Oracle conformance sweep (interp==compiled over the corpus)**

Run: `./_build/default/test/run_stdlib.exe test oracle 2>&1 | tail -5` (or the project's `@oracle` alias if present — check `grep -rn oracle test/dune`).
Expected: no NEW divergence introduced by this change (the sort-family entries that were `KNOWN_DIVERGENCE` crashes should now MATCH — update `test/test_oracle.ml`'s known-divergence list if they graduate to matching).

- [ ] **Step 7: Benchmark regression check (CLAUDE.md requires it for closure/HOF changes)**

Run `list_ops` (closures/HOF) and `binary_trees` (allocation) compiled and confirm they run and produce expected output:
```bash
for b in list_ops binary_trees tree_transform; do
  MARCH_STDLIB="$PWD/stdlib" ./_build/default/bin/main.exe --compile --opt 2 bench/$b.march -o /private/tmp/${b}_bin >/dev/null 2>&1 && \
  { echo -n "$b: "; /private/tmp/${b}_bin 2>&1 | head -1; }
done
```
Expected: all run, output matches the interpreter (spot-check the head line). Note timings vs `specs/benchmarks.md` baselines — a tagged-int closure arg adds no allocation (unlike the float box), so no material regression is expected.

- [ ] **Step 8: Commit the golden and update the docs/todos**

```bash
git add test/native/closure_scalar_abi.march test/native/closure_scalar_abi.expected test/dune
# update specs/todos.md (mark the sort-RC-underflow item done) and specs/progress.md (new Current State entry)
git add specs/todos.md specs/progress.md
git commit -m "test+docs: closure-scalar-ABI regression golden; sort-RC crash resolved"
```

---

## Task 8: Update the todos/progress narrative and the design-doc cross-links

**Files:**
- Modify: `specs/todos.md` (the sort-RC-underflow family item, currently `[ ]` open), `specs/progress.md` (new `## Current State` entry)

- [ ] **Step 1: Mark the sort-RC item done in `specs/todos.md`**

Find the `- [ ]` item describing "the known sort-RC-underflow family (`alphadev_sort`/`heapsort`/`mergesort`/…)" and change it to `- ✅`, documenting: root cause was the untagged-Int-in-ptr-closure-slot RC crash (the Int analog of the float register-mismatch); fixed by the uniform ptr closure scalar ABI (four boundaries: ECallPtr, direct EApp, apply-fn entry, clo_wrap); the kernel-wedge sub-item (a) is now resolved.

- [ ] **Step 2: Add a `## Current State` entry to `specs/progress.md`** summarizing the four-boundary fix, the failure-mode matrix, and the green suite/benches. Cross-link this plan and the float-boxing sub-plan.

- [ ] **Step 3: Commit** (folded into Task 7 Step 8 if done together, else `git commit -m "docs: sort-RC crash resolved via uniform closure scalar ABI"`).

---

## Self-Review notes

- **Spec coverage:** the four boundaries A/B/C/D each have a task (3, 3, 4, 5); the runtime hardening (2), verification matrix (7), and docs (8) round it out. The float half of A/C/D already shipped; this plan is the `i64` half + the new boundary B.
- **The one genuine unknown** is boundary B's exact emit site (which EApp arm emits the direct apply-fn call and whether it shares code with the general EApp path). Task 1 pins it with concrete IR + grep before any edit; Task 3 Step 2 is written to adapt to that finding while keeping the change guarded on `is_apply_fn` so normal direct calls are untouched.
- **Why this succeeds where the two attempts failed:** both attempts left boundary B (direct EApp) passing raw scalars while the apply-fn entry assumed tagged — the conditional untag then ashr'd a raw odd value. Task 3 closes B so the "arg is always tagged" invariant holds at *every* path, making the Task 4 entry decode sound.
- **Type consistency:** `coerce ctx _ v "ptr"` (encode) and `coerce ctx "ptr" v "i64"` / `march_unbox_float` (decode) are the only two primitives; they are the exact inverse pair used symmetrically at encode (A/B) and decode (C/D) sites.
