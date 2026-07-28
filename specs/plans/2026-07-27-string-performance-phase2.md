# String Performance Phase 2 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make March string operations measurably faster, guided by the phase 1 profile.

**Architecture:** Five independent targets, each landable on its own, sequenced by evidence strength and by what unblocks what. Every target is verified by the phase 1 harness with a same-session A/B against a re-measured baseline.

**Tech Stack:** C11 (runtime), OCaml (compiler: TIR/codegen/typecheck/eval), March (stdlib + benchmarks).

**Phase 1 inputs:** `specs/2026-07-26-string-performance-design.md`, `specs/2026-07-26-string-performance-profile.md`, `bench/STRING_RESULTS.md`.

---

## Global Constraints

- **Same-session A/B only.** Absolute timings on the dev machine are not comparable across runs: the identical binary measured 578ms and 910ms hours apart, with load average in the same range both times (likely core placement or clock state). **Every task re-measures the baseline binary alongside the changed one, back to back, in the same run.** Never compare against a number stored in a file.
- Check `uptime` before timing. `bench/run_string_bench.sh` records load average and warns above half the core count; treat a warned run's wall-clock columns as unusable. Memory and allocation counts are load-independent.
- **After editing any `runtime/*.c`:** `dune build --root . @warm-cache`, then `rm -rf .march/cas/artifacts-v2`. Compiled programs resolve the runtime exe-relative from `_build/default/runtime`, which a targeted build does not refresh, and a stale CAS entry prints `(cached)` while linking the old runtime. The artifact dir is `artifacts-v2`, **not** `artifacts` as the `compiler-builtin` skill states.
- Build with named targets; a bare `dune build --root .` hangs.
- Benchmarks always compiled `--compile --opt 2`, never interpreted.
- Never `git stash` (shared stash stack across worktrees); stage files explicitly by name.
- `kill`/`pkill` silently no-op under the sandbox — they exit 0 and deliver no signal. If a process must die, ask the operator.

### The nine sites a string builtin touches

Verified empirically against `string_split`, not taken from the skill doc (which lists four and is out of date):

| # | File | What |
|---|---|---|
| 1 | `lib/tir/llvm_builtins.ml` | the record: `march_name`, `c_name`, `ret_ty`, `in_is_builtin`, `declare_sig` |
| 2 | `lib/tir/llvm_builtins.ml` | `PDeclare "march_<name>"` in the preamble list |
| 3 | `lib/tir/defun.ml` | `builtin_names` entry (without it, no inlining) |
| 4 | `lib/tir/borrow.ml` | borrow signature — which args are borrowed vs consumed |
| 5 | `lib/typecheck/typecheck.ml` | `Mono (TArrow ...)` signature |
| 6 | `lib/eval/eval.ml` | interpreter `VBuiltin` implementation (parity with compiled) |
| 7 | `lib/tir/js_emit.ml` | name list for the JS backend |
| 8 | `runtime/march_runtime.c` | the C implementation |
| 9 | `stdlib/string.march` | the March-level wrapper + doctest |

Plus **both** JS runtime shims: `test/native/march_runtime.mjs` and `test/whole_program/march_runtime.mjs`.

---

## Sequencing rationale, and one correction to the phase 1 recommendation

Phase 1 recommended a "Vec(String)-returning split". **Investigation for this plan shows that will not work as described**, and it changes the order:

- `Array` in March is a **March-level persistent trie** (`PVec(n, shift, trie, tail)` in `stdlib/array.march`), not a flat C array. A `Vec`-returning split would allocate trie nodes instead of cons cells — plausibly *more* allocation, not less.
- `NativeArray` is C-backed and flat, but exists only for unboxed `int` and `float`. **There is no flat array of heap pointers in March.**
- So a zero-cons split needs a genuinely new RC-aware container type, which is the largest and riskiest item on the list — not the cheap one it appeared to be.
- Meanwhile **offset-aware `index_of` partly subsumes it**: it lets user code use the `slice_walk` pattern (429ms) instead of `split` (1117ms) with no new container at all.

Order is therefore: `index_of` offset → SIMD search → n-ary concat → freelist (after re-measuring) → split container (after a decision task).

---

### Task 1: `String.index_of` with a start offset

**Files:**
- Modify: `runtime/march_runtime.c` (near `march_string_index_of`), `lib/tir/llvm_builtins.ml`, `lib/tir/defun.ml`, `lib/tir/borrow.ml`, `lib/typecheck/typecheck.ml`, `lib/eval/eval.ml`, `lib/tir/js_emit.ml`, `stdlib/string.march`, `test/native/march_runtime.mjs`, `test/whole_program/march_runtime.mjs`
- Test: `test/test_stdlib_suite.ml`

**Interfaces:**
- Produces: `string_index_of_from(s : String, sub : String, start : Int) : Option(Int)` as a bare builtin, wrapped as `String.index_of_from(s, sub, start)`. Returns the index **in `s`'s coordinates** (not relative to `start`), or `None`.

- [ ] **Step 1: Write the failing test**

Add to `test/test_stdlib_suite.ml` beside the other string-stats tests:

```ocaml
(* Offset-aware search. Without it, tokenizing a string means re-slicing the
   remaining tail on every step -- O(n^2) in bytes copied, which is what forced
   bench/string_slice_walk to walk by arithmetic instead of by searching, and
   what makes bench/string_parallel_scan count hits via replace_all. Returns an
   index in s's OWN coordinates so callers can feed it straight back as the
   next start without adding offsets themselves. *)
let test_string_index_of_from () =
  with_compiled_program ~tag:"march_idxfrom" ~env_prefix:""
    ~src_text:
      "mod IdxFrom do\n\
      \  fn show(o : Option(Int)) : String do\n\
      \    match o do\n\
      \    Some(k) -> to_string(k)\n\
      \    None    -> \"none\"\n\
      \    end\n\
      \  end\n\
      \  fn main() do\n\
      \    let s = \"a,b,c\"\n\
      \    println(show(String.index_of_from(s, \",\", 0)))\n\
      \    println(show(String.index_of_from(s, \",\", 2)))\n\
      \    println(show(String.index_of_from(s, \",\", 4)))\n\
      \    println(show(String.index_of_from(s, \"\", 3)))\n\
      \    println(show(String.index_of_from(s, \",\", -5)))\n\
      \    println(show(String.index_of_from(s, \",\", 99)))\n\
      \  end\n\
       end\n"
    (fun _ -> ())

(* Compiled and interpreted must agree -- a builtin has two implementations
   (runtime C and eval.ml) and they drift silently otherwise. *)
let test_string_index_of_from_parity () =
  let src =
    "mod IdxParity do\n\
    \  fn main() do\n\
    \    let s = \"aXbXc\"\n\
    \    match String.index_of_from(s, \"X\", 2) do\n\
    \    Some(k) -> println(to_string(k))\n\
    \    None    -> println(\"none\")\n\
    \    end\n\
    \  end\n\
     end\n"
  in
  Alcotest.(check string) "interpreted result" "3" (String.trim (run_interpreted src));
  Alcotest.(check string) "compiled result"    "3" (String.trim (run_compiled src))
```

If `run_interpreted` / `run_compiled` helpers do not exist in this file, use the
`with_compiled_program` helper for the compiled side and
`Sys.command` on `bin/main.exe <file>` for the interpreted side, asserting the
captured stdout.

Expected output for `test_string_index_of_from`, asserted by capturing stdout:
`1`, `3`, `none`, `3`, `1`, `none` — note the last three: an empty needle
returns `start` clamped into range, a negative `start` clamps to 0, and a
`start` past the end returns `None`.

Register both:

```ocaml
Alcotest.test_case "String.index_of_from: offsets and clamping" `Slow
  test_string_index_of_from;
Alcotest.test_case "String.index_of_from: interp/compiled parity" `Slow
  test_string_index_of_from_parity;
```

- [ ] **Step 2: Run to verify it fails**

```bash
dune build --root . test/run_stdlib.exe && ./_build/default/test/run_stdlib.exe test adversarial-regressions -e 2>&1 | tail -20
```

Expected: FAIL — `Unknown function String.index_of_from` at compile time.

- [ ] **Step 3: C implementation**

In `runtime/march_runtime.c`, directly after `march_string_index_of`:

```c
/* index_of starting at a byte offset.  Returns the index in S's own
 * coordinates so a caller can feed the result straight back in as the next
 * start.  Without this, tokenizing means re-slicing the tail every step --
 * O(n^2) in bytes copied. */
void *march_string_index_of_from(void *s, void *sub, int64_t start) {
    march_string *ss = (march_string *)s;
    march_string *su = (march_string *)sub;
    if (start < 0) start = 0;
    if (start > ss->len) return make_none();
    if (su->len == 0) return make_some_i64(start);
    if (su->len > ss->len - start) return make_none();
    for (int64_t i = start; i + su->len <= ss->len; i++) {
        if (memcmp(ss->data + i, su->data, (size_t)su->len) == 0)
            return make_some_i64(i);
    }
    return make_none();
}
```

- [ ] **Step 4: Register at all nine sites**

`lib/tir/llvm_builtins.ml` — record, beside `string_index_of`:

```ocaml
  { march_name = "string_index_of_from"; c_name = Some "march_string_index_of_from";
    ret_ty = Some (Tir.TCon ("Option", [Tir.TInt]));
    in_is_builtin = true;
    declare_sig = Some "declare ptr  @march_string_index_of_from(ptr %s, ptr %sub, i64 %start)" };
```

`lib/tir/llvm_builtins.ml` — preamble list, beside the other `PDeclare "march_string_*"` entries:

```ocaml
  PDeclare "march_string_index_of_from";
```

`lib/tir/defun.ml` — add `"string_index_of_from";` to `builtin_names` beside `"string_index_of"`.

`lib/tir/borrow.ml` — both string args are borrowed, the int is scalar:

```ocaml
  ("string_index_of_from",  [true; true; true]);
```

`lib/typecheck/typecheck.ml`:

```ocaml
    ("string_index_of_from", Mono (TArrow (t_string, TArrow (t_string, TArrow (t_int, t_option t_int)))));
```

Match the exact `t_option`/`t_int` spellings used by the neighbouring `string_index_of` entry.

`lib/eval/eval.ml` — beside `string_index_of`:

```ocaml
  ; ("string_index_of_from", VBuiltin ("string_index_of_from", function
        | [VString s; VString sub; VInt start] ->
          let n = String.length s and m = String.length sub in
          let start = if start < 0 then 0 else start in
          if start > n then none_value
          else if m = 0 then some_int start
          else begin
            let res = ref none_value in
            (try
               for i = start to n - m do
                 if String.sub s i m = sub then begin res := some_int i; raise Exit end
               done
             with Exit -> ());
            !res
          end
        | _ -> eval_error "string_index_of_from: expected (String, String, Int)"))
```

Use whatever `none_value` / `some_int` constructors the neighbouring
`string_index_of` case uses — copy its exact shape rather than inventing names.

`lib/tir/js_emit.ml` — add `"string_index_of_from"` to the name list containing `"string_index_of"`.

Both JS shims (`test/native/march_runtime.mjs`, `test/whole_program/march_runtime.mjs`), mirroring the existing `march_string_index_of`:

```js
export function march_string_index_of_from(s, sub, start) {
  if (start < 0) start = 0;
  if (start > s.length) return march_none();
  if (sub.length === 0) return march_some(start);
  const i = s.indexOf(sub, start);
  return i < 0 ? march_none() : march_some(i);
}
```

Use the same `march_none`/`march_some` helpers the neighbouring function uses.

`stdlib/string.march`, beside `index_of`:

```march
  doc """
  Find the first occurrence of `sub` at or after byte offset `start`.
  Returns the index in `s`'s own coordinates, so the result can be fed
  straight back in as the next `start` when tokenizing.

  Prefer this over slicing off the tail and searching again: the latter
  copies the remaining bytes on every step, making a full tokenize O(n²).

  march> String.index_of_from("a,b,c", ",", 2)
  Some(3)
  march> String.index_of_from("a,b,c", ",", 4)
  None
  """
  fn index_of_from(s, sub, start) do string_index_of_from(s, sub, start) end
```

- [ ] **Step 5: Rebuild and verify the tests pass**

```bash
dune build --root . bin/main.exe test/run_stdlib.exe
dune build --root . @warm-cache
rm -rf .march/cas/artifacts-v2
./_build/default/test/run_stdlib.exe test adversarial-regressions -e 2>&1 | tail -20
```

Expected: PASS for both new tests.

- [ ] **Step 6: Prove it removes the quadratic**

```bash
cat > /tmp/tok.march <<'EOF'
mod Tok do
  pfn walk(s : String, pos : Int, acc : Int) : Int do
    match String.index_of_from(s, ",", pos) do
    None    -> acc + 1
    Some(k) -> walk(s, k + 1, acc + 1)
    end
  end
  fn main() do
    let buf = String.repeat("aaa,bbb,ccc,ddd\n", 50000)
    println("fields=" ++ to_string(walk(buf, 0, 0)))
  end
end
EOF
./_build/default/bin/main.exe --compile --opt 2 /tmp/tok.march -o /tmp/tok && time /tmp/tok
MARCH_STRING_STATS=1 /tmp/tok 2>&1 >/dev/null | grep -E "allocs |copy_bytes"
```

Expected: `fields=150001`, well under a second, and **`copy_bytes` near zero** — the walk allocates no substrings at all. Record both in the commit message. If `copy_bytes` is large, the search is still copying and the implementation is wrong.

- [ ] **Step 7: Commit**

```bash
git add runtime/march_runtime.c lib/tir/llvm_builtins.ml lib/tir/defun.ml lib/tir/borrow.ml lib/typecheck/typecheck.ml lib/eval/eval.ml lib/tir/js_emit.ml stdlib/string.march test/native/march_runtime.mjs test/whole_program/march_runtime.mjs test/test_stdlib_suite.ml
git commit -m "feat(string): index_of_from — offset-aware search

Removes the O(n^2) trap in tokenizing: without a start offset, finding the
next separator means slicing off the tail and searching again, re-copying
the remaining bytes every step. Two phase 1 benchmarks had to be written
around this."
```

---

### Task 2: `memchr`/SIMD substring search

**Files:**
- Modify: `runtime/march_runtime.c` (`march_string_index_of`, `march_string_index_of_from`, `march_string_contains`, `march_string_last_index_of`, `march_string_split`, `march_string_replace`, `march_string_replace_all`)
- Test: `test/test_stdlib_suite.ml`
- Reference: `runtime/march_http_parse_simd.c` (existing SSE4.2-with-scalar-fallback precedent in this repo)

**Interfaces:**
- Consumes: `march_string_index_of_from` from Task 1.
- Produces: a private `static const char *march_memmem(const char *hay, int64_t haylen, const char *needle, int64_t nlen)` used by every search site. No March-level API change.

- [ ] **Step 1: Write the failing test — correctness first, speed second**

A faster search that is wrong is worse than a slow one, and the edge cases
(empty needle, needle longer than haystack, match at the very end, overlapping
candidates, embedded NUL bytes) are exactly where a hand-rolled scanner breaks.

```ocaml
(* Substring search edge cases, pinned BEFORE the search is rewritten to use
   memchr/SIMD. The dangerous cases for a fast scanner are: a match at the very
   last possible offset, a first-byte match that fails on the rest (the
   candidate-rejection path), a needle longer than the haystack, and embedded
   NUL bytes -- March strings are length-counted, so a NUL is ordinary data and
   any implementation that treats it as a terminator silently truncates. *)
let test_string_search_edge_cases () =
  with_compiled_program ~tag:"march_search" ~env_prefix:""
    ~src_text:
      "mod Search do\n\
      \  fn show(o : Option(Int)) : String do\n\
      \    match o do\n\
      \    Some(k) -> to_string(k)\n\
      \    None    -> \"none\"\n\
      \    end\n\
      \  end\n\
      \  fn main() do\n\
      \    println(show(String.index_of(\"abcabd\", \"abd\")))\n\
      \    println(show(String.index_of(\"aaaa\", \"aaaa\")))\n\
      \    println(show(String.index_of(\"aaa\", \"aaaa\")))\n\
      \    println(show(String.index_of(\"xxxxy\", \"y\")))\n\
      \    println(show(String.index_of(\"abc\", \"\")))\n\
      \    println(to_string(String.contains(\"abcabd\", \"abd\")))\n\
      \    println(to_string(List.length(String.split(\"a,,b\", \",\"))))\n\
      \    println(String.replace_all(\"aXbXc\", \"X\", \"--\"))\n\
      \  end\n\
       end\n"
    (fun _ -> ())
```

Assert stdout is exactly: `3`, `0`, `none`, `4`, `0`, `true`, `3`, `a--b--c`.

Register as `` `Slow ``. **Run it and confirm it PASSES against the current
scalar implementation** — this test is a regression net for the rewrite, so it
must be green before the change and green after. A test that only passes after
is not pinning existing behaviour.

- [ ] **Step 2: Run to confirm it passes pre-change**

```bash
dune build --root . test/run_stdlib.exe && ./_build/default/test/run_stdlib.exe test adversarial-regressions -e 2>&1 | tail -10
```

Expected: PASS. If it fails, the current search is already wrong and that is a bug to fix before optimizing.

- [ ] **Step 3: Add the shared search helper**

In `runtime/march_runtime.c`, above the string search functions:

```c
/* Substring search shared by every string search site.
 *
 * Two-stage: memchr to find candidate first bytes, then memcmp to confirm.
 * libc's memchr is SIMD-optimised on every platform we target, so this gets
 * vector scanning without any intrinsics or per-arch code -- the same reason
 * runtime/march_http_parse_simd.c keeps a scalar fallback rather than
 * requiring SSE4.2 everywhere.
 *
 * March strings are LENGTH-COUNTED and may contain NUL bytes, so nothing here
 * may use strstr/strchr or treat NUL as a terminator.
 *
 * Returns a pointer into [hay], or NULL. */
static const char *march_memmem(const char *hay, int64_t haylen,
                                const char *needle, int64_t nlen) {
    if (nlen == 0) return hay;
    if (nlen > haylen) return NULL;
    const char first = needle[0];
    const char *p = hay;
    int64_t remaining = haylen;
    while (remaining >= nlen) {
        const char *hit = (const char *)memchr(p, first, (size_t)(remaining - nlen + 1));
        if (!hit) return NULL;
        if (memcmp(hit, needle, (size_t)nlen) == 0) return hit;
        remaining -= (hit - p) + 1;
        p = hit + 1;
    }
    return NULL;
}
```

- [ ] **Step 4: Route the search sites through it**

Rewrite the scan loop in each of `march_string_index_of`,
`march_string_index_of_from`, `march_string_contains`, `march_string_split`,
`march_string_replace`, `march_string_replace_all` to call `march_memmem`.
`march_string_last_index_of` scans backwards — leave it scalar rather than
inverting the helper, and note why in a comment.

Example, `march_string_index_of`:

```c
void *march_string_index_of(void *s, void *sub) {
    march_string *ss = (march_string *)s;
    march_string *su = (march_string *)sub;
    if (su->len == 0) return make_some_i64(0);
    const char *hit = march_memmem(ss->data, ss->len, su->data, su->len);
    return hit ? make_some_i64(hit - ss->data) : make_none();
}
```

- [ ] **Step 5: Verify correctness, then measure**

```bash
dune build --root . bin/main.exe test/run_stdlib.exe && dune build --root . @warm-cache && rm -rf .march/cas/artifacts-v2
./_build/default/test/run_stdlib.exe test adversarial-regressions -e 2>&1 | tail -10
scripts/run-tests.sh 2>&1 | tail -5
```

Expected: the edge-case test still passes, and the full suite is green apart from the known environmental `MARCH_SANITIZE` failure.

Then the same-session A/B — **this is the only valid way to claim a speedup**:

```bash
# keep the PRE-change binary before rebuilding, then compare back to back
uptime   # abort if 1-min load exceeds half the core count
for i in 1 2 3; do /usr/bin/time -p /tmp/pre_string_scan 2>&1 >/dev/null | grep real; done
./_build/default/bin/main.exe --compile --opt 2 bench/string_scan.march -o /tmp/post_string_scan
for i in 1 2 3; do /usr/bin/time -p /tmp/post_string_scan 2>&1 >/dev/null | grep real; done
```

Baseline for reference (load 4.62, same session): `string_scan` 806.0ms, ~0.5 GB/s. A `memchr` two-stage scan should be several times faster on the absent-needle case. Record actual before/after numbers in the commit.

- [ ] **Step 6: Commit**

```bash
git add runtime/march_runtime.c test/test_stdlib_suite.ml
git commit -m "perf(runtime): memchr-based substring search"
```

---

### Task 3: n-ary string concat

**Files:**
- Modify: `runtime/march_runtime.c`, the nine builtin sites, `lib/tir/fold.ml` or `lib/tir/simplify.ml` (the rewrite), `lib/parser/parser.mly` (remove the interpolation threshold)
- Test: `test/test_stdlib_suite.ml`, `test/test_eval.ml`
- Snapshots: `test/snapshots/` may need regenerating — review the diff, do not blind-accept

**Interfaces:**
- Produces: `march_string_concat_n(void **parts, int64_t n)` — sums lengths, allocates once, copies once. Emitted from a TIR rewrite of a left-deep `++` chain of length ≥ 3.

**Design note:** doing this as a TIR pass rather than in the parser means it also
speeds up hand-written `a ++ b ++ c`, and keeps the AST shape the formatter and
`~H` sigil lowering already understand. PR #90 showed what happens otherwise:
changing the parser's emitted AST broke `try_collect_interp` in the formatter and
silently disabled HTML escaping in `decompose_concat`.

**Note on scope:** the string-literal immortality fix on main already removed the
per-evaluation literal allocation, so part of this target's original case is
gone. The remaining win is the intermediate strings in a chain of 3+.

- [ ] **Step 1: Write the failing benchmark-style test**

```ocaml
(* A 5-part concat chain must allocate ONE result string, not three
   intermediates. Asserting on the allocation count rather than on time makes
   this a real regression gate rather than a noisy timing check. *)
let test_concat_chain_single_allocation () =
  with_compiled_program ~tag:"march_catn" ~env_prefix:"MARCH_STRING_STATS=1 "
    ~src_text:
      "mod CatN do\n\
      \  pfn go(a : String, b : String, i : Int, n : Int, acc : Int) : Int do\n\
      \    if i >= n do acc\n\
      \    else\n\
      \      let s = a ++ b ++ a ++ b ++ a\n\
      \      go(a, b, i + 1, n, acc + String.byte_size(s))\n\
      \    end\n\
      \  end\n\
      \  fn main() do println(to_string(go(\"xx\", \"yy\", 0, 100000, 0))) end\n\
       end\n"
    (fun err_file ->
       let allocs = string_stat_of ~stderr_file:err_file "allocs" in
       (* 100_000 iterations: one result string each, plus a small constant.
          A left-deep ++ chain allocates 3 intermediates per iteration. *)
       Alcotest.(check bool)
         (Printf.sprintf "5-part chain allocates ~1 string per iteration (got %d)" allocs)
         true (allocs < 150_000))
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL with roughly 400,000 allocations (4 per iteration).

- [ ] **Step 3: C implementation**

```c
/* n-ary concat: sum lengths, allocate once, copy once.
 *
 * A left-deep `++` chain re-copies the growing prefix at every step, so k parts
 * copy O(k^2) bytes and allocate k-1 intermediates. string_join avoids the
 * re-copying but must materialize a cons list first, which measured at 59% of
 * its total cost. Taking the parts directly avoids both. */
void *march_string_concat_n(void **parts, int64_t n) {
    int64_t total = 0;
    for (int64_t i = 0; i < n; i++)
        total += ((march_string *)parts[i])->len;
    march_string *r = march_string_alloc(total);
    char *dst = r->data;
    for (int64_t i = 0; i < n; i++) {
        march_string *p = (march_string *)parts[i];
        march_str_copy(dst, p->data, (size_t)p->len);
        dst += p->len;
    }
    *dst = '\0';
    return r;
}
```

- [ ] **Step 4: Emit it from TIR**

Add a rewrite that collapses a left-deep `EApp("++", [EApp("++", [a; b]); c])`
chain of length ≥ 3 into a single `concat_n` call, in the same pass that already
folds `++` (`lib/tir/fold.ml:76` handles `"++" | "string_concat"`). The call
site must `alloca` an array of `n` pointers, store each part, and pass the array
plus `n`.

Leave 2-part `++` alone: it is already one allocation and one copy pass, so
there is nothing to save, and routing it through an array is strictly more work.

- [ ] **Step 5: Verify, including the snapshots**

```bash
dune build --root . bin/main.exe test/run_stdlib.exe test/run_snapshots.exe
dune build --root . @warm-cache && rm -rf .march/cas/artifacts-v2
./_build/default/test/run_snapshots.exe -e 2>&1 | tail -5
```

TIR shape changes, so snapshots will differ. Regenerate deliberately with
`UPDATE_SNAPSHOTS=1 ./_build/default/test/run_snapshots.exe -e` and **read the
diff** — it is the code review artifact for this change.

- [ ] **Step 6: Remove the interpolation threshold**

With n-ary concat, `interp_join_threshold` in `lib/parser/parser.mly` no longer
earns its keep: every interpolation can desugar to a plain `++` chain and let
TIR collapse it. Delete the threshold and the `string_join` branch, keep the
`++` chain, and update `test/test_eval.ml`'s two parse-shape tests
(`parse interp`, `parse interp many`) to expect `++` in both cases.

Re-run the formatter and `~H` escaping tests specifically — they are what broke
last time the interpolation AST changed:

```bash
./_build/default/test/test_fmt.exe -e 2>&1 | tail -3
./_build/default/test/run_eval.exe test h_sigil_csrf_conn_gated -e 2>&1 | tail -5
```

- [ ] **Step 7: Same-session A/B and commit**

Compare `bench/string_build.march` and `bench/iolist_template.march` before and
after, back to back. Commit all sites plus the reviewed snapshot diff.

---

### Task 4: Size-class freelist — CLOSED, not built

**Verdict: do not build.** Closed 2026-07-27 on measurement, not estimate.

`bench/run_string_xlang.sh` runs this benchmark against four baselines chosen to
separate allocator overhead from representation:

| | ms | vs March |
|---|---|---|
| C++ (`std::string`, has SSO) | 238 | 2.98× faster |
| C (raw `malloc`) | 400 | 1.77× |
| Rust (`String`, no SSO — March's representation) | 553 | 1.28× |
| **March** | **709** | — |
| Python (`pymalloc` size classes) | 1249 | 0.57× |

Rust has March's exact representation and is only ~1.3× faster, which **bounds
what a freelist can win** — a freelist attacks precisely the allocator and
refcount overhead that separates the two. Meanwhile C++ with inline storage is
~3× faster and beats raw `malloc`: you cannot out-allocate not allocating.

So the freelist buys roughly a third, forecloses most of the available gain, and
composes with nothing. Inline storage is the better use of the same effort — see
`specs/plans/2026-07-27-string-sso.md`.

The gate this task opened with (re-measure the criterion, since the literal fix
cut the target traffic from 24M to 10M allocations) was answered along the way:
the criterion still holds — allocations are still small and still proportional to
time — but the conclusion it pointed at was the wrong fix.

### Task 5: Container-returning `split` — CLOSED, not built

**Verdict: not needed as specified.** Closed 2026-07-27.

Two findings retired it:

1. **March has no flat array of heap pointers to build on.** `Array` is a
   March-level persistent trie (`stdlib/array.march`), so a `Vec`-returning split
   allocates trie nodes rather than cons cells — plausibly more allocation, not
   less. `NativeArray` is flat and C-backed but handles only unboxed `int`/`float`.
   A zero-cons split therefore needs a new RC-aware container type, making this the
   largest item on the phase 2 list rather than the cheap one it appeared to be.

2. **Task 1 delivered most of the win without one.** Counting 150K fields in an
   800KB buffer: `String.split` + `List.length` at 975ms against an
   `index_of_from` walk at 267ms — **3.7× with effectively zero allocation**.

What remains is narrower than phase 1 implied: callers who genuinely need every
field retained as a `String`, which the scan pattern does not serve. Nobody has
shown that is a hot path. Reopen with a workload that demonstrates one.

## Self-review

**Spec coverage:** all five user-named targets have a task. Sequencing changed from the phase 1 recommendation, with the reason recorded (Array is a trie; no pointer-array primitive).

**Known corrections to phase 1 carried here:** the Vec-split target is not implementable as described (Task 5); the SSO criterion needs re-measuring because the literal fix removed 42% of the traffic (Task 4 Step 1); n-ary concat's case is partly eroded by the same fix (Task 3 note).

**Placeholders:** Task 5 deliberately stops at a decision task rather than specifying an implementation blind — that is a scoping decision, not an omission, and it has a concrete first experiment.

**Type consistency:** the builtin name `string_index_of_from` and its C symbol `march_string_index_of_from` are used identically across all nine sites in Task 1 and referenced by Task 2's helper.

**Verification discipline:** every performance claim in this plan is gated on a same-session A/B with the baseline re-measured alongside, per the Global Constraints — because absolute numbers on this machine are not comparable across runs.
