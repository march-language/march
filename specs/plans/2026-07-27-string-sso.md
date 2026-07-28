# Small-String Optimization — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Store strings of ≤7 bytes inline in the value itself, eliminating roughly half the string allocations in real workloads.

**Architecture:** A tagged-immediate representation that fits March's *existing* pointer-tagging scheme, so `march_incrc`/`march_decrc` need no changes at all. Every reader of a string is routed through accessors first, as a behaviour-preserving refactor; only then is the constructor flipped. That sequencing is the whole safety story.

**Tech Stack:** C11 (runtime), OCaml (TIR codegen), March (benchmarks).

**Evidence:** `specs/2026-07-26-string-performance-profile.md`. **Do not start without reading its two addenda** — the cross-language comparison that killed the freelist alternative, and the real-workload size histogram that sizes this one.

---

## Why this, and why 7 bytes

March already tags immediates, and the RC path already rejects them:

```c
/* immediate integer n  -> ptr = (n << 1) | 1   (low bit set)
   heap pointer p       -> ptr = p              (low bit clear) */
#define IS_HEAP_PTR(p) \
    (((uintptr_t)(p) & 1u) == 0 && (uintptr_t)(p) >= 4096u && (intptr_t)(p) > 0)
```

`march_incrc` and `march_decrc` both open with `if (!IS_HEAP_PTR(p)) return;`. **An
inline string is therefore refcount-free with zero changes to the RC hot path** —
normally the most invasive part of an SSO retrofit, and here it is already done.
It is also not a type-system change: `String` stays one type, and typecheck,
mono, and defun never learn about this.

**Capacity is the constraint.** A tagged value has 64 bits; after the marker and a
length field, 7 bytes of payload remain. Measured against real workloads that
covers roughly half of allocations:

| workload | allocations | ≤7 bytes |
|---|---|---|
| `bench/iolist_template` (web templating) | 100,007 | **53%** |
| `bench/string_small_churn` (synthetic) | 10,000,009 | 42% |

Treat 53% as the estimate. Two other workloads measured higher (CSV split
99.99%, JSON 90%) and **both are misleading**: the CSV benchmark is synthetic
with 3-byte fields, and the JSON figure is an artifact of a parser that
allocates 2.03 strings per input byte. Which is the standing caution for this
whole project: **an SSO makes allocation-heavy code look fast without fixing
it.** If a workload benefits enormously, check whether it should simply be
allocating less.

## The encoding

```
heap pointer     : bit63 = 0, low bit = 0, value >= 4096
immediate int    : low bit = 1                       (any sign)
inline string    : bit63 = 1, low bit = 0            <- NEW

layout:  [63] = 1  |  [62:59] = length 0..7  |  [58:3] = payload (56 bits = 7 bytes)  |  [2:0] = 0
```

**This cannot collide with either existing form**, and the reason is worth stating
because it is the correctness argument for the whole design:

- an immediate integer is `(n << 1) | 1`, so its low bit is **always** 1, for any
  `n` including negative — an inline string has low bit 0;
- a heap pointer must satisfy `(intptr_t)p > 0`, i.e. bit63 clear — an inline
  string has bit63 set.

So an inline string is rejected by `IS_HEAP_PTR` (fails the sign test) and is
distinguishable from an immediate integer (differs in the low bit). Bytes are
stored little-endian within the payload field; the empty string is length 0.

---

## Global Constraints

- **After editing any `runtime/*.c`:** `dune build --root . @warm-cache`, then `rm -rf .march/cas/artifacts-v2`. Compiled programs resolve the runtime exe-relative from `_build/default/runtime`, which a targeted build does not refresh; the CAS artifact dir is `artifacts-v2`, not `artifacts`.
- **Run `dune build --root . @runtest`, not just `scripts/run-tests.sh`.** The script invokes only the four alcotest binaries; the JS-pipeline tests are dune *rules* and run only under the alias. Read the exit code directly, never through a pipe.
- **Every performance claim is a same-session A/B**: build the before-binary, keep it, build the after-binary, run them interleaved. Absolute timings on the dev machine are not comparable across runs — the identical binary has measured 578ms and 910ms hours apart.
- **ASAN is mandatory for this work**, not optional. A representation change that gets a tag check wrong produces exactly the use-after-free class this project has hit before, and it will surface as unrelated corruption elsewhere.
- Build with named targets; a bare `dune build --root .` hangs.
- Never `git stash`; stage files explicitly by name.
- A new JS-visible builtin must go in **`runtime/march_runtime.mjs`** (canonical — `test/dune` copies it) *and* `test/native/`, `test/whole_program/`. Updating only the `test/` pair passes locally and fails CI.

---

### Task 1: Encoding, accessors, and their tests — no behaviour change

**Files:**
- Modify: `runtime/march_runtime.h` (the accessor inlines), `runtime/march_runtime.c`
- Test: `test/test_stdlib_suite.ml`

**Interfaces:**
- Produces: `march_str_is_inline(void *)`, `march_str_len(void *)`, `march_str_data(void *, char *scratch)`, `march_str_make_inline(const char *, int64_t)`. Nothing calls them yet.

The point of this task is that it changes nothing observable. It ends with the
encoding in place, exercised by tests, while every existing code path still runs
on heap strings exactly as before.

- [ ] **Step 1: Write the failing test**

```ocaml
(* The inline-string encoding must round-trip every length 0..7, and must be
   distinguishable from BOTH existing tagged forms. The collision argument is
   the correctness basis for the whole representation, so it is asserted rather
   than reasoned about:
     - an immediate integer is (n << 1) | 1, so low bit is ALWAYS 1
     - a heap pointer satisfies (intptr_t)p > 0, so bit63 is clear
     - an inline string sets bit63 and clears the low bit — unreachable by either *)
let test_inline_string_encoding () =
  with_compiled_program ~tag:"march_ssoenc" ~env_prefix:""
    ~src_text:
      "mod SsoEnc do\n\
      \  fn main() do\n\
      \    println(sso_selftest())\n\
      \  end\n\
       end\n"
    (fun _ -> ())
```

Backed by a C self-test the builtin calls, added in `runtime/march_runtime.c`,
which returns `"ok"` or a description of the first failure:

```c
/* Exercises the inline encoding directly: round-trips every length 0..7 with a
 * distinct byte pattern, and asserts non-collision with the other two tagged
 * forms. Exposed as a builtin purely so the test suite can reach it. */
const char *march_sso_selftest(void);
```

Assert stdout is exactly `ok`.

- [ ] **Step 2: Run to verify it fails**

```bash
dune build --root . test/run_stdlib.exe && ./_build/default/test/run_stdlib.exe test adversarial-regressions -e 2>&1 | tail -10
```

Expected: FAIL — `sso_selftest` is not a known function.

- [ ] **Step 3: Add the encoding and accessors**

In `runtime/march_runtime.h`, beside the `march_string` definition:

```c
/* ── Small-string optimization ────────────────────────────────────────────
 * Strings of <= 7 bytes are stored INLINE in the value, with no allocation:
 *
 *   [63] = 1  |  [62:59] = length 0..7  |  [58:3] = payload  |  [2:0] = 0
 *
 * This is unreachable by the two existing tagged forms, which is what makes it
 * safe: an immediate integer is (n << 1) | 1 and so always has its low bit set,
 * while a heap pointer must satisfy (intptr_t)p > 0 and so has bit63 clear.
 *
 * Consequence worth stating: IS_HEAP_PTR already rejects anything with the sign
 * bit set, so march_incrc/march_decrc no-op on inline strings with NO change to
 * the RC path. Inline strings are never freed, never counted, never shared. */
#define MARCH_SSO_MAX 7
#define MARCH_SSO_BIT (1ULL << 63)

static inline int march_str_is_inline(const void *p) {
    return ((uintptr_t)p & MARCH_SSO_BIT) != 0 && ((uintptr_t)p & 1u) == 0;
}
static inline int64_t march_str_len(const void *p) {
    if (march_str_is_inline(p)) return (int64_t)(((uintptr_t)p >> 59) & 0xF);
    return ((const march_string *)p)->len;
}
/* Returns a pointer to the bytes. For an inline string the bytes are unpacked
 * into [scratch], which the CALLER owns and which must be at least 8 bytes —
 * the returned pointer is only valid while [scratch] is. Heap strings return
 * their own data and ignore [scratch]. */
static inline const char *march_str_data(const void *p, char *scratch) {
    if (march_str_is_inline(p)) {
        uint64_t bits = (uint64_t)(uintptr_t)p >> 3;
        int64_t n = march_str_len(p);
        for (int64_t i = 0; i < n; i++) scratch[i] = (char)((bits >> (i * 8)) & 0xFF);
        scratch[n] = '\0';
        return scratch;
    }
    return ((const march_string *)p)->data;
}
static inline void *march_str_make_inline(const char *s, int64_t n) {
    uint64_t bits = 0;
    for (int64_t i = 0; i < n; i++) bits |= (uint64_t)(unsigned char)s[i] << (i * 8);
    return (void *)(uintptr_t)(MARCH_SSO_BIT | ((uint64_t)n << 59) | (bits << 3));
}
```

- [ ] **Step 4: Run to verify it passes**

Expected: PASS. Nothing else in the suite changes — no constructor produces an
inline string yet.

- [ ] **Step 5: Commit**

```bash
git add runtime/march_runtime.h runtime/march_runtime.c test/test_stdlib_suite.ml
git commit -m "feat(runtime): inline-string encoding and accessors (unused)"
```

---

### Task 2: Route every reader through the accessors — still no behaviour change

**Files:**
- Modify: `runtime/march_runtime.c`, `runtime/march_extras.c`, `runtime/march_http.c`, `runtime/march_ffi.c`

**This is the task that makes the flip safe, and it is the one to be exhaustive
about.** Every site that reads `->len` or `->data` on a string must go through
`march_str_len` / `march_str_data` *before* any constructor produces an inline
string. While the constructor is unchanged, this refactor is a no-op and the
full suite proves it.

- [ ] **Step 1: Enumerate every reader**

```bash
grep -n "march_string \*" runtime/*.c | wc -l
grep -n -- "->len\|->data" runtime/*.c | grep -v "march_str_len\|march_str_data" | wc -l
```

Record both counts in the commit message. The second must reach zero for string
values by the end of this task (other types have `->len`/`->data` too — array
and bytes cells — so read each site, do not blind-replace).

- [ ] **Step 2: Convert them, in groups, running the suite after each group**

Suggested grouping, smallest blast radius first: constructors and length queries
→ comparisons and search → builders (concat, join, replace, case, pad) → the
FFI and HTTP boundaries.

For a function that needs the bytes:

```c
    char sa[8], sb[8];
    const char *da = march_str_data(a, sa);
    const char *db = march_str_data(b, sb);
    int64_t la = march_str_len(a), lb = march_str_len(b);
```

- [ ] **Step 3: Verify the refactor changed nothing**

```bash
dune build --root . bin/main.exe && dune build --root . @warm-cache && rm -rf .march/cas/artifacts-v2
dune build --root . @runtest    # read $? directly
bash bench/run_string_bench.sh  # all six checksums must still assert
```

Expected: identical results to before the task. A behaviour change here means a
site was converted incorrectly, and it is far cheaper to find now than after the
flip.

- [ ] **Step 4: Commit**

---

### Task 3: The flip

**Files:**
- Modify: `runtime/march_runtime.c` (`march_string_lit`, `march_string_alloc` callers)

- [ ] **Step 1: Write the failing test**

```ocaml
(* After the flip, short strings must allocate NOTHING. The allocation counter
   is the assertion rather than timing, because it is exact and load-independent. *)
let test_short_strings_do_not_allocate () =
  with_compiled_program ~tag:"march_ssoalloc"
    ~env_prefix:"MARCH_STRING_STATS=1 "
    ~src_text:
      "mod SsoAlloc do\n\
      \  pfn go(i : Int, n : Int, acc : Int) : Int do\n\
      \    if i >= n do acc\n\
      \    else\n\
      \      let s = String.slice(\"abcdefgh\", 0, 5)\n\
      \      go(i + 1, n, acc + String.byte_size(s))\n\
      \    end\n\
      \  end\n\
      \  fn main() do println(to_string(go(0, 100000, 0))) end\n\
       end\n"
    (fun err_file ->
       let allocs = string_stat_of ~stderr_file:err_file "allocs" in
       Alcotest.(check bool)
         (Printf.sprintf "100K 5-byte slices allocate nothing (got %d)" allocs)
         true (allocs < 1000))
```

- [ ] **Step 2: Run to verify it fails** — expect ~100,000 allocations.

- [ ] **Step 3: Flip the constructor**

`march_string_lit` returns `march_str_make_inline(utf8, len)` when
`len <= MARCH_SSO_MAX`. Leave `march_string_alloc` alone: it returns a *writable*
cell that callers fill in afterwards, and an inline string has nowhere to write.
Builders that allocate-then-fill should construct into a stack buffer and call
`march_string_lit` at the end when the result is short.

- [ ] **Step 4: Verify — correctness, then leaks, then speed**

```bash
dune build --root . bin/main.exe && dune build --root . @warm-cache && rm -rf .march/cas/artifacts-v2
dune build --root . @runtest
MARCH_SANITIZE=1 <compile and run several corpus programs>   # MANDATORY
bash bench/run_string_bench.sh
```

The ASAN pass is not optional. A missed tag check dereferences a value whose
high bit is set — an address in kernel space — and the failure will present far
from its cause.

- [ ] **Step 5: Same-session A/B and commit**

Interleave the before/after binaries for `string_small_churn` and
`iolist_template`. Record real numbers in the commit message; the expectation
from the histogram is roughly half the allocations disappearing, not a 3× — C++
reaches 3× with 15–22 bytes of inline capacity, not 7.

---

### Task 4: The FFI boundary

**Files:**
- Modify: `runtime/march_ffi.c`, `specs/2026-06-19-c-ffi-abi-design.md`

An `extern` C function receiving a March `String` gets a pointer it will
dereference. An inline string is not a pointer.

- [ ] **Step 1: Write the failing test** — an `extern` taking a short string,
      which must receive valid NUL-terminated bytes.
- [ ] **Step 2: Materialize at the boundary** — convert inline to a heap string
      before the call. Document the ownership of that temporary explicitly in the
      FFI ABI spec; this is a new allocation the caller must release.
- [ ] **Step 3: Verify** with the FFI test group and an ASAN run.
- [ ] **Step 4: Commit**, updating the ABI spec in the same commit.

---

### Task 5: Report

- [ ] Update `specs/2026-07-26-string-performance-profile.md` with measured
      before/after, including the allocation histogram (the ≤7 bucket should
      collapse to near zero) and same-session timings.
- [ ] Update `specs/progress.md`, `specs/todos.md`, `CHANGELOG.md` in one commit.
- [ ] Regenerate the docs search index (`scripts/gen-docs-search-index.sh`) —
      CI rejects a stale one, and doc edits here will invalidate it.

---

## Self-review

**Scope:** one representation change, staged so each task is independently
verifiable. Task 2 is deliberately the largest and most boring; it is what makes
Task 3 a small change rather than a rewrite.

**Known unknowns, stated rather than hidden:**
- The 53% estimate comes from one templating benchmark. If the flip lands and the
  ≤7 bucket does not collapse on real workloads, stop and re-measure rather than
  pressing on to 15-byte inline storage — that needs a multi-word `String` and is
  a different project.
- `march_string_alloc`'s allocate-then-fill contract does not fit inline storage.
  Task 3 keeps it heap-only, which means builders producing short results still
  allocate unless they are individually converted. That is a deliberate partial
  measure; quantify what it leaves behind before deciding whether to chase it.

**What this plan does NOT do:** change `String`'s type, touch the RC path, or
alter the JS backend (strings are JS strings there).
