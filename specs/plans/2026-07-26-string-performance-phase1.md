# String Performance Phase 1 (Measurement) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the measurement apparatus — benchmark corpus, runtime counters, harness — that decides whether March's string representation must change.

**Architecture:** Six `bench/string_*.march` programs each isolating one cost; opt-in runtime counters (`MARCH_STRING_STATS=1`) tallying allocation count, a size histogram, bytes copied, and peak live bytes, dumped at exit; a bash+python3 harness capturing median wall time and peak RSS. No optimization work, no codegen changes, no new builtins.

**Tech Stack:** C11 (runtime, `_Atomic` relaxed counters), March (benchmarks), bash + python3 (harness), OCaml/alcotest (integrity tests).

**Spec:** `specs/2026-07-26-string-performance-design.md`

## Global Constraints

- Benchmarks are **always compiled**: `--compile --opt 2`. Never interpreted — interpreted runs on these shapes take hours and measure the interpreter.
- Counters are **off by default**; overhead when off is one predictable branch. Verified within 2% (Task 8).
- **No new March builtin and no codegen changes** in phase 1. The stats surface is an env var plus an `atexit` dump to stderr.
- All counters use **relaxed atomics**, mirroring `march_live_alloc_count` — approximate cross-thread totals are correct for a profiling aid, and stronger ordering would distort what we are measuring.
- Benchmarks live in `bench/`, are documented in `specs/benchmarks.md`, and print a **deterministic checksum** so the harness can prove the work actually happened.
- The benchmark corpus is **not** part of `dune runtest`.
- Build with `dune build --root .` and named targets. A bare `dune build --root .` with no target hangs in this repo.
- **After editing any `runtime/*.c`, run `dune build --root . @warm-cache` before compiling a March program**, and clear `.march/cas/artifacts-v2` if a compile prints `(cached)`. Compiled programs resolve the runtime exe-relative from `_build/default/runtime`, which a targeted `dune build test/... bin/main.exe` does **not** refresh — so a runtime edit silently links the stale copy and tests fail with the instrumentation apparently absent. Note the CAS artifact directory is `artifacts-v2`, not `artifacts`.
- Do **not** use `git stash` (the stash stack is shared across worktrees), and stage files explicitly by name — never `git add -A`/`.`.
- Size knobs are named constants at the top of each benchmark so CI can run small and profiling can run large.

---

### Task 1: Allocation counters, size histogram, and exit dump

**Files:**
- Modify: `runtime/march_runtime.c` (add stats block after `gc_trace_on`, ~line 95; hook `march_string_alloc` at line 361; hook the free path in `march_decrc` at line 211)
- Test: `test/test_stdlib_suite.ml`

**Interfaces:**
- Consumes: nothing.
- Produces: `MARCH_STRING_STATS=1` env flag; a stderr dump whose lines are `march_string_stats <key> <value>`, keys: `allocs`, `alloc_bytes`, `frees`, `copy_bytes`, `peak_live_bytes`, `hist_le7`, `hist_le15`, `hist_le23`, `hist_le31`, `hist_le63`, `hist_le255`, `hist_gt255`. `copy_bytes` is emitted by this task but stays 0 until Task 2.

- [ ] **Step 1: Write the failing test**

Add to `test/test_stdlib_suite.ml`, near the other compiled regression tests:

```ocaml
(* Phase 1 string measurement: the allocation histogram must be exact, not
   approximate.  The representation decision (SSO vs views) rests on the
   fraction of allocations in the small buckets, so a miscounting histogram
   would silently produce the wrong architecture.  This program allocates a
   known number of strings at known sizes: string_repeat produces one string
   per call, so 100 calls at 4 bytes and 100 at 40 bytes must show up as
   exactly 100 in hist_le7 and 100 in hist_le63. *)
let test_string_stats_histogram_exact () =
  let main_exe = find_main_exe () in
  let tmp = Filename.temp_file "march_strstats" "" in
  Sys.remove tmp;
  Unix.mkdir tmp 0o755;
  let src = Filename.concat tmp "strstats.march" in
  let oc = open_out src in
  output_string oc
    "mod StrStats do\n\
    \  pfn small(i : Int, n : Int, acc : Int) : Int do\n\
    \    if i >= n do acc\n\
    \    else\n\
    \      let s = String.repeat(\"ab\", 2)\n\
    \      small(i + 1, n, acc + String.byte_size(s))\n\
    \    end\n\
    \  end\n\
    \  pfn big(i : Int, n : Int, acc : Int) : Int do\n\
    \    if i >= n do acc\n\
    \    else\n\
    \      let s = String.repeat(\"abcd\", 10)\n\
    \      big(i + 1, n, acc + String.byte_size(s))\n\
    \    end\n\
    \  end\n\
    \  fn main() do\n\
    \    println(to_string(small(0, 100, 0) + big(0, 100, 0)))\n\
    \  end\n\
     end\n";
  close_out oc;
  let bin = Filename.concat tmp "strstats_bin" in
  match compile_march_or_skip ~main_exe ~bin ~src () with
  | None -> ()  (* legitimate, counted skip: no clang on PATH *)
  | Some bin ->
    let err_file = Filename.concat tmp "err.txt" in
    let rc =
      Sys.command
        (Printf.sprintf "MARCH_STRING_STATS=1 %s > /dev/null 2> %s"
           (Filename.quote bin) (Filename.quote err_file))
    in
    Alcotest.(check int) "benchmark program exits 0" 0 rc;
    let stats = read_file_lines err_file in
    let get key =
      let prefix = "march_string_stats " ^ key ^ " " in
      match List.find_opt (fun l ->
          String.length l > String.length prefix &&
          String.sub l 0 (String.length prefix) = prefix) stats with
      | Some l ->
        int_of_string (String.trim
          (String.sub l (String.length prefix)
             (String.length l - String.length prefix)))
      | None -> Alcotest.failf "no stats line for %s (got: %s)"
                  key (String.concat " | " stats)
    in
    (* 100 x 4-byte strings land in the <=7 bucket; 100 x 40-byte in <=63. *)
    Alcotest.(check int) "hist_le7 counts the 4-byte strings"  100 (get "hist_le7");
    Alcotest.(check int) "hist_le63 counts the 40-byte strings" 100 (get "hist_le63");
    Alcotest.(check bool) "allocs covers both loops" true (get "allocs" >= 200);
    Alcotest.(check bool) "peak_live_bytes is positive" true (get "peak_live_bytes" > 0)

(* Stats are OFF unless the env var is set: an always-on dump would corrupt
   every other test's stderr expectations and slow the hot alloc path. *)
let test_string_stats_off_by_default () =
  let main_exe = find_main_exe () in
  let tmp = Filename.temp_file "march_strstats_off" "" in
  Sys.remove tmp;
  Unix.mkdir tmp 0o755;
  let src = Filename.concat tmp "off.march" in
  let oc = open_out src in
  output_string oc
    "mod Off do\n  fn main() do println(String.repeat(\"x\", 3)) end\nend\n";
  close_out oc;
  let bin = Filename.concat tmp "off_bin" in
  match compile_march_or_skip ~main_exe ~bin ~src () with
  | None -> ()
  | Some bin ->
    let err_file = Filename.concat tmp "err.txt" in
    let rc = Sys.command
        (Printf.sprintf "%s > /dev/null 2> %s"
           (Filename.quote bin) (Filename.quote err_file)) in
    Alcotest.(check int) "exits 0" 0 rc;
    let stats = read_file_lines err_file in
    Alcotest.(check bool) "no stats emitted without the env var" false
      (List.exists (fun l ->
           let p = "march_string_stats" in
           String.length l >= String.length p &&
           String.sub l 0 (String.length p) = p) stats)
```

If `read_file_lines` does not already exist in this file, add it next to the other helpers:

```ocaml
let read_file_lines path =
  let ic = open_in path in
  let rec go acc =
    match input_line ic with
    | line -> go (line :: acc)
    | exception End_of_file -> close_in ic; List.rev acc
  in
  go []
```

Register both tests in the `adversarial-regressions` group alongside the other compiled tests:

```ocaml
Alcotest.test_case "string stats: histogram is exact" `Slow
  test_string_stats_histogram_exact;
Alcotest.test_case "string stats: off by default" `Quick
  test_string_stats_off_by_default;
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
dune build --root . test/run_stdlib.exe && ./_build/default/test/run_stdlib.exe test adversarial-regressions -e 2>&1 | tail -20
```

Expected: FAIL on "string stats: histogram is exact" with `no stats line for hist_le7`. ("off by default" passes already — it is the control that proves the other test isn't trivially satisfiable.)

- [ ] **Step 3: Add the stats block to the runtime**

In `runtime/march_runtime.c`, immediately after `gc_trace_on()` (~line 95), insert:

```c
/* ── String statistics (MARCH_STRING_STATS=1) ────────────────────────── */
/* Opt-in profiling counters for the phase 1 string measurement (see
 * specs/2026-07-26-string-performance-design.md).  OFF by default: the cost
 * is one predictable branch inside functions that are already calling
 * malloc/memcpy.  Relaxed atomics mirror march_live_alloc_count — exact
 * cross-thread ordering is not needed for a profiling aid, and stronger
 * ordering would distort the very timings being measured. */
static pthread_mutex_t str_stats_mutex = PTHREAD_MUTEX_INITIALIZER;
static int str_stats_state = 0;  /* 0 = uninit, 1 = on, -1 = off */

#define MARCH_STR_NBUCKETS 7
static _Atomic int64_t str_alloc_count;
static _Atomic int64_t str_alloc_bytes;
static _Atomic int64_t str_free_count;
static _Atomic int64_t str_copy_bytes;
static _Atomic int64_t str_live_bytes;
static _Atomic int64_t str_peak_bytes;
static _Atomic int64_t str_hist[MARCH_STR_NBUCKETS];

static const char *str_hist_names[MARCH_STR_NBUCKETS] = {
    "hist_le7", "hist_le15", "hist_le23", "hist_le31",
    "hist_le63", "hist_le255", "hist_gt255"
};

/* Bucket bounds chosen for the SSO decision: 23 bytes is what would fit in
 * the footprint the 24-byte march_string header already occupies. */
static inline int str_bucket(int64_t len) {
    if (len <=   7) return 0;
    if (len <=  15) return 1;
    if (len <=  23) return 2;
    if (len <=  31) return 3;
    if (len <=  63) return 4;
    if (len <= 255) return 5;
    return 6;
}

static void str_stats_dump(void) {
    fprintf(stderr, "march_string_stats allocs %lld\n",
            (long long)atomic_load_explicit(&str_alloc_count, memory_order_relaxed));
    fprintf(stderr, "march_string_stats alloc_bytes %lld\n",
            (long long)atomic_load_explicit(&str_alloc_bytes, memory_order_relaxed));
    fprintf(stderr, "march_string_stats frees %lld\n",
            (long long)atomic_load_explicit(&str_free_count, memory_order_relaxed));
    fprintf(stderr, "march_string_stats copy_bytes %lld\n",
            (long long)atomic_load_explicit(&str_copy_bytes, memory_order_relaxed));
    fprintf(stderr, "march_string_stats peak_live_bytes %lld\n",
            (long long)atomic_load_explicit(&str_peak_bytes, memory_order_relaxed));
    for (int i = 0; i < MARCH_STR_NBUCKETS; i++)
        fprintf(stderr, "march_string_stats %s %lld\n", str_hist_names[i],
                (long long)atomic_load_explicit(&str_hist[i], memory_order_relaxed));
}

static void str_stats_init_locked(void) {
    const char *e = getenv("MARCH_STRING_STATS");
    if (e && *e && strcmp(e, "0") != 0) {
        str_stats_state = 1;
        atexit(str_stats_dump);
    } else {
        str_stats_state = -1;
    }
}

static inline int str_stats_on(void) {
    if (__builtin_expect(str_stats_state != 0, 1)) return str_stats_state > 0;
    pthread_mutex_lock(&str_stats_mutex);
    if (str_stats_state == 0) str_stats_init_locked();
    pthread_mutex_unlock(&str_stats_mutex);
    return str_stats_state > 0;
}

/* Tally one string allocation of [len] payload bytes, maintaining the
 * running peak of live string bytes with a CAS loop (relaxed: the peak is a
 * report, not a synchronisation point). */
static void str_stats_alloc(int64_t len) {
    atomic_fetch_add_explicit(&str_alloc_count, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&str_alloc_bytes, len, memory_order_relaxed);
    atomic_fetch_add_explicit(&str_hist[str_bucket(len)], 1, memory_order_relaxed);
    int64_t live = atomic_fetch_add_explicit(&str_live_bytes, len,
                                             memory_order_relaxed) + len;
    int64_t peak = atomic_load_explicit(&str_peak_bytes, memory_order_relaxed);
    while (live > peak &&
           !atomic_compare_exchange_weak_explicit(
               &str_peak_bytes, &peak, live,
               memory_order_relaxed, memory_order_relaxed)) { }
}

static void str_stats_free(int64_t len) {
    atomic_fetch_add_explicit(&str_free_count, 1, memory_order_relaxed);
    atomic_fetch_sub_explicit(&str_live_bytes, len, memory_order_relaxed);
}
```

- [ ] **Step 4: Hook the allocation and free paths**

In `march_string_alloc` (line 361), after the header fields are set and before `return s;`, add:

```c
    if (str_stats_on()) str_stats_alloc(len);
```

In `march_decrc`, inside the `if (prev == 1) {` branch at line 211, **before** `free(p)` (the length must be read while the object is still alive):

```c
        if (tag == MARCH_STRING_TAG && str_stats_on())
            str_stats_free(((march_string *)p)->len);
```

Note the sibling free path at line 231 (`if (prev == 1) { march_run_resource_dtor(p); MARCH_FREE_BUMP(); free(p); return 1; }`) — add the same two lines there, before `free(p)`. Missing it would undercount frees and inflate `peak_live_bytes`.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
dune build --root . test/run_stdlib.exe && ./_build/default/test/run_stdlib.exe test adversarial-regressions -e 2>&1 | tail -20
```

Expected: PASS for both. If `hist_le7` reads 0 but `allocs` is nonzero, `String.repeat("ab", 2)` is being constant-folded — change the loop to build a length that depends on `i` and update the expected counts accordingly.

- [ ] **Step 6: Commit**

```bash
git add runtime/march_runtime.c test/test_stdlib_suite.ml
git commit -m "feat(runtime): opt-in string allocation stats (MARCH_STRING_STATS)"
```

---

### Task 2: Bytes-copied instrumentation

**Files:**
- Modify: `runtime/march_runtime.c` (add `march_str_copy` near the stats block; replace `memcpy` at the string-op sites)
- Test: `test/test_stdlib_suite.ml`

**Interfaces:**
- Consumes: `str_stats_on()`, `str_copy_bytes` from Task 1.
- Produces: a nonzero `march_string_stats copy_bytes` line.

- [ ] **Step 1: Write the failing test**

Add to `test/test_stdlib_suite.ml`:

```ocaml
(* Bytes-copied is the counter that discriminates "views would help" from
   "allocation is the problem".  A slice of 1000 bytes taken 100 times must
   report ~100_000 copied bytes; if the counter reads 0, the memcpy sites
   were not converted and the views decision would rest on a blank number. *)
let test_string_stats_copy_bytes () =
  let main_exe = find_main_exe () in
  let tmp = Filename.temp_file "march_strcopy" "" in
  Sys.remove tmp;
  Unix.mkdir tmp 0o755;
  let src = Filename.concat tmp "strcopy.march" in
  let oc = open_out src in
  output_string oc
    "mod StrCopy do\n\
    \  pfn go(buf : String, i : Int, n : Int, acc : Int) : Int do\n\
    \    if i >= n do acc\n\
    \    else\n\
    \      let s = String.slice(buf, i, 1000)\n\
    \      go(buf, i + 1, n, acc + String.byte_size(s))\n\
    \    end\n\
    \  end\n\
    \  fn main() do\n\
    \    let buf = String.repeat(\"abcdefghij\", 1000)\n\
    \    println(to_string(go(buf, 0, 100, 0)))\n\
    \  end\n\
     end\n";
  close_out oc;
  let bin = Filename.concat tmp "strcopy_bin" in
  match compile_march_or_skip ~main_exe ~bin ~src () with
  | None -> ()
  | Some bin ->
    let err_file = Filename.concat tmp "err.txt" in
    let rc = Sys.command
        (Printf.sprintf "MARCH_STRING_STATS=1 %s > /dev/null 2> %s"
           (Filename.quote bin) (Filename.quote err_file)) in
    Alcotest.(check int) "exits 0" 0 rc;
    let stats = read_file_lines err_file in
    let get key =
      let prefix = "march_string_stats " ^ key ^ " " in
      match List.find_opt (fun l ->
          String.length l > String.length prefix &&
          String.sub l 0 (String.length prefix) = prefix) stats with
      | Some l -> int_of_string (String.trim
          (String.sub l (String.length prefix)
             (String.length l - String.length prefix)))
      | None -> Alcotest.failf "no stats line for %s" key
    in
    (* 100 slices x 1000 bytes, plus the 10_000-byte source buffer build. *)
    Alcotest.(check bool)
      (Printf.sprintf "copy_bytes >= 100_000 (got %d)" (get "copy_bytes"))
      true (get "copy_bytes" >= 100_000)
```

Register it:

```ocaml
Alcotest.test_case "string stats: bytes copied" `Slow
  test_string_stats_copy_bytes;
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
dune build --root . test/run_stdlib.exe && ./_build/default/test/run_stdlib.exe test adversarial-regressions -e 2>&1 | grep -i "bytes copied" -A 3
```

Expected: FAIL — `copy_bytes >= 100_000 (got 0)`.

- [ ] **Step 3: Add the copy wrapper**

In `runtime/march_runtime.c`, immediately after `str_stats_free`:

```c
/* memcpy with opt-in byte accounting.  Every string-building memcpy in this
 * file routes through here so bytes-copied is attributable per operation
 * rather than as one lump.  When stats are off this is a plain memcpy plus a
 * predictable branch. */
static inline void march_str_copy(void *dst, const void *src, size_t n) {
    memcpy(dst, src, n);
    if (str_stats_on())
        atomic_fetch_add_explicit(&str_copy_bytes, (int64_t)n,
                                  memory_order_relaxed);
}
```

- [ ] **Step 4: Convert the string-op memcpy sites**

Replace `memcpy` with `march_str_copy` in the string-producing functions only — `march_string_lit`, `march_string_concat`, `march_string_join`, `march_string_repeat`, `march_string_replace`, `march_string_replace_all`, `march_string_pad_left`, `march_string_pad_right`, `march_string_reverse`, `march_string_to_lowercase`, `march_string_to_uppercase`, `march_string_trim`, `march_string_trim_start`, `march_string_trim_end`. Find them with:

```bash
grep -n "memcpy" runtime/march_runtime.c
```

Do **not** convert `memcpy` calls outside the string functions (scheduler, HTTP, actor mailboxes). They are not string copies, and counting them would make `copy_bytes` mean nothing.

`march_string_slice` needs no change — it delegates to `march_string_lit`, which is converted.

- [ ] **Step 5: Run the test to verify it passes**

```bash
dune build --root . test/run_stdlib.exe && ./_build/default/test/run_stdlib.exe test adversarial-regressions -e 2>&1 | tail -20
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add runtime/march_runtime.c test/test_stdlib_suite.ml
git commit -m "feat(runtime): tally bytes copied in string ops under MARCH_STRING_STATS"
```

---

### Task 3: Scan and transform benchmarks

**Files:**
- Create: `bench/string_scan.march`, `bench/string_case.march`
- Modify: `specs/benchmarks.md`

**Interfaces:**
- Consumes: nothing.
- Produces: two executables printing `checksum=<int>`, consumed by the Task 7 harness.

- [ ] **Step 1: Write `bench/string_scan.march`**

```march
-- String scan benchmark: substring search over a large buffer.
--
-- Isolates SCAN THROUGHPUT.  index_of/contains are a byte-at-a-time loop
-- calling memcmp (runtime/march_runtime.c), with no memchr or SIMD; this is
-- the benchmark that measures what that costs and what fixing it buys.
--
-- Two cases, because they have very different profiles:
--   absent  -- needle never matches: the full O(n*m) worst case, every byte
--              of the buffer examined on every call.  The honest number.
--   late    -- needle at ~90% through: the realistic "found eventually" case.
--
-- Expected output: checksum=8100000
-- Usage: march --compile --opt 2 bench/string_scan.march -o /tmp/string_scan

mod StringScan do

-- Size knob: 10 bytes per unit.  100_000 -> 1MB (CI), 1_600_000 -> 16MB.
pfn buffer_units() : Int do 100000 end
pfn iterations() : Int do 20 end

pfn scan_absent(buf : String, i : Int, n : Int, acc : Int) : Int do
  if i >= n do acc
  else
    let hit = match String.index_of(buf, "zzzzzzzz") do
      Some(k) -> k
      None    -> 1
    end
    scan_absent(buf, i + 1, n, acc + hit)
  end
end

pfn scan_late(buf : String, needle : String, i : Int, n : Int, acc : Int) : Int do
  if i >= n do acc
  else
    let hit = match String.index_of(buf, needle) do
      Some(k) -> k
      None    -> 0
    end
    scan_late(buf, needle, i + 1, n, acc + hit)
  end
end

fn main() do
  let buf = String.repeat("abcdefghij", buffer_units())
  -- A needle that occurs once, ~90% through: splice a marker in by rebuilding
  -- the buffer as prefix ++ marker ++ suffix.
  let cut    = (String.byte_size(buf) * 9) / 10
  let marked = String.slice(buf, 0, cut) ++ "QQMARKERQQ"
               ++ String.slice(buf, cut, String.byte_size(buf) - cut)

  let a = scan_absent(buf, 0, iterations(), 0)
  let b = scan_late(marked, "QQMARKERQQ", 0, iterations(), 0)
  println("checksum=" ++ to_string(a + b))
end

end
```

- [ ] **Step 2: Compile, run, and record the real checksum**

```bash
dune build --root . bin/main.exe
./_build/default/bin/main.exe --compile --opt 2 bench/string_scan.march -o /tmp/string_scan && /tmp/string_scan
```

Expected: a `checksum=<int>` line. **Replace the `Expected output:` comment in the file with the actual value printed.** The checksum in the header above is a placeholder that must be corrected here — the harness asserts against it, so a wrong value fails every run.

- [ ] **Step 3: Write `bench/string_case.march`**

```march
-- String case-conversion benchmark: to_lowercase/to_uppercase over a large
-- buffer.
--
-- Isolates TRANSFORM THROUGHPUT.  A second SIMD target with a different shape
-- from string_scan: no search, pure map-and-copy, one full-size allocation
-- per call.  The pairing matters -- if scan is slow but case is fast, the
-- problem is the search loop; if both are slow, it is memory bandwidth.
--
-- Expected output: checksum=8000000
-- Usage: march --compile --opt 2 bench/string_case.march -o /tmp/string_case

mod StringCase do

pfn buffer_units() : Int do 100000 end
pfn iterations() : Int do 40 end

pfn go(buf : String, i : Int, n : Int, acc : Int) : Int do
  if i >= n do acc
  else
    let up = String.to_uppercase(buf)
    let lo = String.to_lowercase(up)
    go(buf, i + 1, n, acc + String.byte_size(lo))
  end
end

fn main() do
  let buf = String.repeat("abcdefghij", buffer_units())
  println("checksum=" ++ to_string(go(buf, 0, iterations(), 0)))
end

end
```

- [ ] **Step 4: Compile, run, record the checksum**

```bash
./_build/default/bin/main.exe --compile --opt 2 bench/string_case.march -o /tmp/string_case && /tmp/string_case
```

Correct the `Expected output:` comment to the printed value.

- [ ] **Step 5: Document both in `specs/benchmarks.md`**

Insert after the `bench/string_pipeline.march` section, matching the surrounding format exactly:

```markdown
## bench/string_scan.march — Substring search over a 1MB buffer

**Command:** 20 absent-needle scans + 20 late-needle scans over 1MB
**Expected output:** `checksum=<value from Step 2>`

| Feature exercised | Notes |
|-------------------|-------|
| `String.index_of` | Byte-at-a-time loop calling `memcmp` — no `memchr`/SIMD |
| Absent needle | Full O(n·m) worst case: every byte examined every call |
| Late needle | Realistic "found at ~90%" case |

**Comparison baseline:** C (`memmem`), Rust (`str::find`), Go (`strings.Index`), Python (`str.find`).
**What to watch:** March should be far behind C here until phase 2 lands `memchr`/SIMD. A regression *after* that work points at the search fast path.

---

## bench/string_case.march — Case conversion over a 1MB buffer

**Command:** 40 × (`to_uppercase` then `to_lowercase`) over 1MB
**Expected output:** `checksum=<value from Step 4>`

| Feature exercised | Notes |
|-------------------|-------|
| `String.to_uppercase` / `to_lowercase` | Full-size allocation + byte map per call |
| Allocation throughput | 80 full-buffer allocations |
| Memory bandwidth | Pure map-and-copy, no search |

**Comparison baseline:** C (in-place `toupper` loop), Rust (`to_uppercase`), Go (`strings.ToUpper`), Python (`str.upper`).
**What to watch:** Paired with `string_scan` — if both are slow, the ceiling is memory bandwidth, not the search loop.

---
```

- [ ] **Step 6: Commit**

```bash
git add bench/string_scan.march bench/string_case.march specs/benchmarks.md
git commit -m "bench: string scan and case-conversion benchmarks"
```

---

### Task 4: The split/slice discriminator pair

**Files:**
- Create: `bench/string_split_large.march`, `bench/string_slice_walk.march`
- Modify: `specs/benchmarks.md`

**Interfaces:**
- Consumes: nothing.
- Produces: two executables printing `checksum=<int>`. **Their difference is the measurement that decides views vs array-returning split** — they must use the same buffer size and field shape or the comparison is meaningless.

- [ ] **Step 1: Write `bench/string_split_large.march`**

```march
-- Large-input split benchmark: CSV-shaped buffer split into fields.
--
-- Isolates the REALISTIC MIX: one allocation, one cons cell, and one copy per
-- field.  Paired with string_slice_walk, which does the same copying with NO
-- cons cells -- the difference between the two attributes cost to the list
-- structure versus to the copying, which is exactly the fork between an
-- array-returning split and a view representation.
--
-- MUST stay in sync with string_slice_walk: same buffer size, same field
-- shape.  Changing one without the other invalidates the comparison.
--
-- Expected output: checksum=800000
-- Usage: march --compile --opt 2 bench/string_split_large.march -o /tmp/string_split_large

mod StringSplitLarge do

-- 16 bytes per row -> 50_000 rows = 800KB.
pfn rows() : Int do 50000 end
pfn iterations() : Int do 10 end

pfn sum_lens(xs : List(String), acc : Int) : Int do
  match xs do
  Nil        -> acc
  Cons(h, t) -> sum_lens(t, acc + String.byte_size(h))
  end
end

pfn go(buf : String, i : Int, n : Int, acc : Int) : Int do
  if i >= n do acc
  else
    let parts = String.split(buf, ",")
    go(buf, i + 1, n, acc + sum_lens(parts, 0))
  end
end

fn main() do
  let buf = String.repeat("aaa,bbb,ccc,ddd\n", rows())
  println("checksum=" ++ to_string(go(buf, 0, iterations(), 0)))
end

end
```

- [ ] **Step 2: Write `bench/string_slice_walk.march`**

```march
-- Slice-walk benchmark: tokenize a CSV-shaped buffer by index_of + slice,
-- building NO list.
--
-- Isolates COPYING OFF A LARGE OWNER with no cons cells.  Paired with
-- string_split_large -- see that file's header for why the pair exists.
--
-- MUST stay in sync with string_split_large: same buffer size, same field
-- shape.
--
-- Expected output: checksum=800000
-- Usage: march --compile --opt 2 bench/string_slice_walk.march -o /tmp/string_slice_walk

mod StringSliceWalk do

pfn rows() : Int do 50000 end
pfn iterations() : Int do 10 end

-- Walk the buffer field by field, slicing each one out and summing its
-- length.  No list is built, so the only heap traffic is the slice copies.
pfn walk(buf : String, pos : Int, len : Int, acc : Int) : Int do
  if pos >= len do acc
  else
    let rest = String.slice(buf, pos, len - pos)
    match String.index_of(rest, ",") do
    None    -> acc + String.byte_size(rest)
    Some(k) ->
      let field = String.slice(rest, 0, k)
      walk(buf, pos + k + 1, len, acc + String.byte_size(field))
    end
  end
end

pfn go(buf : String, i : Int, n : Int, acc : Int) : Int do
  if i >= n do acc
  else go(buf, i + 1, n, acc + walk(buf, 0, String.byte_size(buf), 0)) end
end

fn main() do
  let buf = String.repeat("aaa,bbb,ccc,ddd\n", rows())
  println("checksum=" ++ to_string(go(buf, 0, iterations(), 0)))
end

end
```

Note: `walk` re-slices the remaining tail each step, which is itself a copy off the owner — that is deliberate. It is precisely the pattern a view representation would make free, so it belongs in the benchmark that measures the views win.

- [ ] **Step 3: Compile both, run, record checksums**

```bash
./_build/default/bin/main.exe --compile --opt 2 bench/string_split_large.march -o /tmp/string_split_large && /tmp/string_split_large
./_build/default/bin/main.exe --compile --opt 2 bench/string_slice_walk.march -o /tmp/string_slice_walk && /tmp/string_slice_walk
```

Correct both `Expected output:` comments to the printed values.

`string_slice_walk` may run substantially longer than `string_split_large` because of the tail re-slicing. If it exceeds ~30s, reduce `iterations()` in **that file only** and note the asymmetry in the docs — the per-iteration cost is what gets compared, not the total.

- [ ] **Step 4: Verify the pair reports comparable copy volume**

```bash
MARCH_STRING_STATS=1 /tmp/string_split_large 2>&1 >/dev/null | grep -E "copy_bytes|allocs"
MARCH_STRING_STATS=1 /tmp/string_slice_walk  2>&1 >/dev/null | grep -E "copy_bytes|allocs"
```

Expected: both report substantial `copy_bytes`. Record both numbers in the commit message — they are the first real data point of the whole phase.

- [ ] **Step 5: Document both in `specs/benchmarks.md`**

Insert after the `string_case` section:

```markdown
## bench/string_split_large.march — Split an 800KB CSV-shaped buffer

**Command:** 10 × `String.split(buf, ",")` over 800KB (50K rows)
**Expected output:** `checksum=<value from Step 3>`

| Feature exercised | Notes |
|-------------------|-------|
| `String.split` | One allocation + one cons cell + one copy per field |
| Cons-cell allocation | 200K cells per iteration |
| List traversal | `sum_lens` walks every field |

**Comparison baseline:** C (in-place `strtok`, zero copy), Rust (`split` iterator, zero copy), Go (`strings.Split`), Python (`str.split`).
**What to watch:** **Paired with `string_slice_walk`** — the two use the same buffer and field shape on purpose. Their difference attributes cost to the cons list versus to the copying, which decides between an array-returning `split` and a view representation. Changing one benchmark's size knob without the other invalidates that comparison.

---

## bench/string_slice_walk.march — Tokenize 800KB by index_of + slice

**Command:** 10 × field-by-field walk over 800KB (50K rows), no list built
**Expected output:** `checksum=<value from Step 3>`

| Feature exercised | Notes |
|-------------------|-------|
| `String.slice` | Copies off a large owner; no view representation exists |
| `String.index_of` | Field-boundary search |
| Zero cons cells | The controlled difference vs `string_split_large` |

**Comparison baseline:** C (pointer walk, zero copy), Rust (`&str` slices, zero copy), Go (slicing, zero copy), Python (`str.find` + slicing).
**What to watch:** See `string_split_large`. Languages with string views do this with no allocation at all; the gap is the size of the prize.

---
```

- [ ] **Step 6: Commit**

```bash
git add bench/string_split_large.march bench/string_slice_walk.march specs/benchmarks.md
git commit -m "bench: split/slice discriminator pair for the views decision"
```

---

### Task 5: Small-string churn benchmark

**Files:**
- Create: `bench/string_small_churn.march`
- Modify: `specs/benchmarks.md`

**Interfaces:**
- Consumes: nothing.
- Produces: an executable printing `checksum=<int>`; its histogram is the SSO evidence.

- [ ] **Step 1: Write `bench/string_small_churn.march`**

```march
-- Small-string churn benchmark: many short strings, request-shaped.
--
-- Isolates PER-ALLOCATION OVERHEAD.  Every string in March is a malloc plus a
-- refcount, even a 4-byte one, so this is the benchmark that says whether a
-- small-string optimization is worth building.  Sizes (4-30 bytes) are chosen
-- to look like HTTP header names and values, and to straddle the 23-byte
-- bucket boundary that an SSO would use.
--
-- The size knob is deliberately exposed: the SSO decision criterion requires
-- checking that wall time scales with allocation count, so this benchmark
-- gets run twice, at pairs() and at 2 * pairs().
--
-- Expected output: checksum=2400000
-- Usage: march --compile --opt 2 bench/string_small_churn.march -o /tmp/string_small_churn

mod StringSmallChurn do

pfn pairs() : Int do 200000 end

-- Build a short "header name: value" pair, compare it, and discard it.
-- Nothing escapes the loop, so this measures allocate-and-free churn.
pfn churn(i : Int, n : Int, acc : Int) : Int do
  if i >= n do acc
  else
    let name  = "x-req-" ++ to_string(i % 97)
    let value = "v" ++ to_string(i) ++ "-abcdefgh"
    let pair  = name ++ ": " ++ value
    let bump  = if String.starts_with(pair, "x-req-") do 1 else 0 end
    churn(i + 1, n, acc + String.byte_size(name) + bump)
  end
end

fn main() do
  println("checksum=" ++ to_string(churn(0, pairs(), 0)))
end

end
```

- [ ] **Step 2: Compile, run, record the checksum**

```bash
./_build/default/bin/main.exe --compile --opt 2 bench/string_small_churn.march -o /tmp/string_small_churn && /tmp/string_small_churn
```

Correct the `Expected output:` comment.

- [ ] **Step 3: Confirm the histogram lands in the small buckets**

```bash
MARCH_STRING_STATS=1 /tmp/string_small_churn 2>&1 >/dev/null | grep hist
```

Expected: the bulk of allocations in `hist_le7` through `hist_le31`. If most land in `hist_gt255`, the benchmark is not building the short strings it claims to and the SSO evidence would be worthless — fix the string shapes before continuing.

- [ ] **Step 4: Document in `specs/benchmarks.md`**

```markdown
## bench/string_small_churn.march — 200K short-string build/compare cycles

**Command:** 200K × (build two short strings, concat, prefix-compare, discard)
**Expected output:** `checksum=<value from Step 2>`

| Feature exercised | Notes |
|-------------------|-------|
| Small-string allocation | Every string is a `malloc` + refcount, even 4 bytes |
| `++` on short operands | Three concats per iteration |
| `String.starts_with` | Short-prefix compare |
| Allocate-and-free churn | Nothing escapes the loop |

**Comparison baseline:** Rust (`String`, has no SSO either), C++ (`std::string`, has SSO), Go, Python (interned short strings).
**What to watch:** The size histogram under `MARCH_STRING_STATS=1` is the SSO evidence — the fraction of allocations at ≤23 bytes. The C++ comparison is the informative one, since it is the baseline that *has* the optimization under consideration.

---
```

- [ ] **Step 5: Commit**

```bash
git add bench/string_small_churn.march specs/benchmarks.md
git commit -m "bench: small-string churn benchmark for the SSO decision"
```

---

### Task 6: Parallel scan scaling benchmark

**Files:**
- Create: `bench/string_parallel_scan.march`
- Modify: `specs/benchmarks.md`

**Interfaces:**
- Consumes: nothing.
- Produces: an executable printing `checksum=<int>` plus one `workers=<n> ms=<t>` line per worker count, parsed by the Task 7 harness for the scaling curve.

**Note:** `Parallel.pmap` takes a `Vec`, not a `List` — build the chunk list with `RRB.from_list` and read results back with `RRB.to_list`. Passing a `List` is a type error.

- [ ] **Step 1: Write `bench/string_parallel_scan.march`**

```march
-- Parallel scan scaling benchmark.
--
-- Measures how scan work scales across workers when every worker shares ONE
-- big input string.  Two things come out of it:
--   1. the pre-parallelism baseline for phase 3, and
--   2. refcount contention -- march_incrc/march_decrc are atomic, so N workers
--      touching one shared owner ping-pong its cache line.  If scaling is
--      already poor here, chunked parallel string ops need a contention answer
--      before they need a chunking algorithm.
--
-- Parallel.pmap operates on Vec, not List: chunk indices go in via
-- RRB.from_list and results come back via RRB.to_list.
--
-- Expected output: checksum=32
-- Usage: march --compile --opt 2 bench/string_parallel_scan.march -o /tmp/string_parallel_scan

mod StringParallelScan do

pfn buffer_units() : Int do 400000 end   -- 4MB
pfn passes() : Int do 4 end

-- Count occurrences of a needle within one chunk of the shared buffer.
-- Each worker slices its own chunk out of the SAME owner string, which is
-- what generates the refcount traffic being measured.
pfn count_in_chunk(buf : String, chunk : Int, chunks : Int) : Int do
  let total = String.byte_size(buf)
  let size  = total / chunks
  let start = chunk * size
  let len   = if chunk == chunks - 1 do total - start else size end
  let part  = String.slice(buf, start, len)
  count_hits(part, 0)
end

pfn count_hits(s : String, acc : Int) : Int do
  match String.index_of(s, "QQ") do
  None    -> acc
  Some(k) ->
    let rest = String.slice(s, k + 2, String.byte_size(s) - k - 2)
    count_hits(rest, acc + 1)
  end
end

pfn sum_ints(xs : List(Int), acc : Int) : Int do
  match xs do
  Nil        -> acc
  Cons(h, t) -> sum_ints(t, acc + h)
  end
end

pfn range_list(i : Int, n : Int, acc : List(Int)) : List(Int) do
  if i >= n do acc else range_list(i + 1, n, Cons(n - 1 - i, acc)) end
end

-- Run the scan split across `workers` chunks and report elapsed ms.
pfn run_at(buf : String, workers : Int) : Int do
  let idxs = RRB.from_list(range_list(0, workers, []))
  let t0   = System.monotonic_time()
  let res  = Parallel.pmap(idxs, fn c -> count_in_chunk(buf, c, workers))
  let hits = sum_ints(RRB.to_list(res), 0)
  let t1   = System.monotonic_time()
  println("workers=" ++ to_string(workers) ++ " ms=" ++ to_string(t1 - t0))
  hits
end

pfn drive(buf : String, i : Int, acc : Int) : Int do
  if i >= passes() do acc
  else
    let w = match i do
      0 -> 1
      1 -> 2
      2 -> 4
      _ -> 8
    end
    drive(buf, i + 1, acc + run_at(buf, w))
  end
end

fn main() do
  -- One "QQ" marker per 10-byte unit gives a predictable hit count.
  let buf = String.repeat("abcdefQQhi", buffer_units())
  println("checksum=" ++ to_string(drive(buf, 0, 0)))
end

end
```

- [ ] **Step 2: Compile, run, record the checksum**

```bash
./_build/default/bin/main.exe --compile --opt 2 bench/string_parallel_scan.march -o /tmp/string_parallel_scan && /tmp/string_parallel_scan
```

Expected: four `workers=N ms=T` lines and one `checksum=` line. The checksum must be **identical across worker counts' contribution** — that is, the total is 4 × the single-run hit count. If it varies between runs, the chunking is racy or drops boundary hits, and the benchmark is invalid; fix it before recording anything. Correct the `Expected output:` comment.

Note the known boundary limitation: a needle straddling a chunk boundary is missed. That is acceptable here because every chunk boundary falls inside the repeated 10-byte unit and the count stays deterministic — but it is exactly the problem phase 3 must solve properly, so say so in the docs.

- [ ] **Step 3: Sanity-check that it actually parallelizes**

```bash
/tmp/string_parallel_scan
```

Expected: `ms` should fall from `workers=1` to `workers=8`, though likely sublinearly. **A flat or rising curve is a finding, not a bug** — it is the contention signal phase 3 is gated on. Record the four numbers in the commit message.

- [ ] **Step 4: Document in `specs/benchmarks.md`**

```markdown
## bench/string_parallel_scan.march — Shared-buffer scan at 1/2/4/8 workers

**Command:** count `"QQ"` occurrences in a 4MB buffer, chunked across 1, 2, 4, 8 workers
**Expected output:** `checksum=<value from Step 2>`, plus one `workers=N ms=T` line per worker count

| Feature exercised | Notes |
|-------------------|-------|
| `Parallel.pmap` | Vec-based; chunk indices via `RRB.from_list` |
| Shared-owner refcounting | Every worker slices from the same string — atomic RC on one cache line |
| `String.slice` per chunk | Copies, because no view representation exists |

**Comparison baseline:** Rust (rayon over `&str` chunks, zero copy), Go (goroutines over slices), C (pthreads over pointer ranges).
**What to watch:** The scaling *shape*, not absolute times. Worse than ~4× at 8 workers gates phase 3 on a refcount-contention answer before any chunking algorithm is worth writing. **Known limitation:** a needle straddling a chunk boundary is missed — acceptable for a deterministic benchmark, and precisely the problem phase 3 must solve.

---
```

- [ ] **Step 5: Commit**

```bash
git add bench/string_parallel_scan.march specs/benchmarks.md
git commit -m "bench: shared-buffer parallel scan scaling benchmark"
```

---

### Task 7: The harness

**Files:**
- Create: `bench/run_string_bench.sh`
- Create (generated): `bench/STRING_RESULTS.md`

**Interfaces:**
- Consumes: the six benchmarks from Tasks 3–6 and the counters from Tasks 1–2.
- Produces: `bench/STRING_RESULTS.md`; exit code 0 only if every benchmark compiled, ran, and matched its documented checksum.

- [ ] **Step 1: Write the harness**

```bash
#!/usr/bin/env bash
# String performance harness (phase 1).
#
# Runs each bench/string_*.march benchmark compiled at --opt 2, five times,
# and reports median wall time, peak RSS, and the MARCH_STRING_STATS counters.
#
# Deliberate choices:
#   * python3 for timing and RSS rather than /usr/bin/time, whose output format
#     differs between macOS and Linux.
#   * Checksums are ASSERTED, not just printed.  A benchmark whose work got
#     optimized away would otherwise report a wonderful number.
#   * A failing benchmark is reported and the run continues, but the script
#     exits non-zero.  It never silently skips -- a perf suite that quietly
#     drops its hardest case is worse than no suite.
#
# Usage: bash bench/run_string_bench.sh [name ...]
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARCH="$REPO_ROOT/_build/default/bin/main.exe"
OUT="$REPO_ROOT/bench/STRING_RESULTS.md"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

RUNS=5
FAILURES=0

# Benchmark name -> expected checksum.  Kept in step with the Expected output
# comment in each .march file and the entry in specs/benchmarks.md.
declare -A EXPECTED=(
  [string_scan]="FILL_ME"
  [string_case]="FILL_ME"
  [string_split_large]="FILL_ME"
  [string_slice_walk]="FILL_ME"
  [string_small_churn]="FILL_ME"
  [string_parallel_scan]="FILL_ME"
)

BENCHES=("$@")
if [ ${#BENCHES[@]} -eq 0 ]; then
  BENCHES=(string_scan string_case string_split_large string_slice_walk
           string_small_churn string_parallel_scan)
fi

if [ ! -x "$MARCH" ]; then
  echo "error: $MARCH not found. Run: dune build --root . bin/main.exe" >&2
  exit 1
fi

# Runs a command RUNS times; prints "median_ms min_ms max_ms peak_rss_bytes".
# ru_maxrss is BYTES on macOS and KILOBYTES on Linux -- normalizing to bytes is
# the difference between a correct number and a silent 1024x error.
timeit() {
  python3 - "$RUNS" "$@" <<'PYEOF'
import sys, time, subprocess, resource, platform
runs = int(sys.argv[1]); cmd = sys.argv[2:]
times = []
for _ in range(runs):
    start = time.perf_counter()
    r = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    times.append((time.perf_counter() - start) * 1000.0)
    if r.returncode != 0:
        print("RUNFAIL"); sys.exit(0)
times.sort()
rss = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
if platform.system() != "Darwin":
    rss *= 1024                      # Linux reports kilobytes
print(f"{times[len(times)//2]:.1f} {times[0]:.1f} {times[-1]:.1f} {rss}")
PYEOF
}

printf '# String Benchmark Results\n\n' > "$OUT"
printf 'Generated by `bench/run_string_bench.sh`. Median of %d runs, compiled `--opt 2`.\n\n' "$RUNS" >> "$OUT"
printf '| Benchmark | Median ms | Min ms | Max ms | Peak RSS MB | Allocs | Alloc MB | Copied MB | Peak live MB |\n' >> "$OUT"
printf '|---|---|---|---|---|---|---|---|---|\n' >> "$OUT"

for name in "${BENCHES[@]}"; do
  src="$REPO_ROOT/bench/$name.march"
  bin="$TMP/$name"

  if ! "$MARCH" --compile --opt 2 "$src" -o "$bin" > "$TMP/$name.build.log" 2>&1; then
    echo "FAIL $name: compile error (see $TMP/$name.build.log)" >&2
    sed -n '1,20p' "$TMP/$name.build.log" >&2
    printf '| %s | **COMPILE FAILED** | | | | | | | |\n' "$name" >> "$OUT"
    FAILURES=$((FAILURES + 1))
    continue
  fi

  # Correctness gate: the checksum proves the work actually happened.
  actual=$("$bin" 2>/dev/null | grep '^checksum=' | cut -d= -f2)
  want="${EXPECTED[$name]:-}"
  if [ -z "$actual" ]; then
    echo "FAIL $name: no checksum= line in output" >&2
    FAILURES=$((FAILURES + 1)); continue
  fi
  if [ "$want" != "FILL_ME" ] && [ "$actual" != "$want" ]; then
    echo "FAIL $name: checksum $actual, expected $want" >&2
    printf '| %s | **CHECKSUM MISMATCH** (%s vs %s) | | | | | | | |\n' "$name" "$actual" "$want" >> "$OUT"
    FAILURES=$((FAILURES + 1)); continue
  fi

  read -r med mn mx rss <<< "$(timeit "$bin")"
  if [ "$med" = "RUNFAIL" ]; then
    echo "FAIL $name: nonzero exit during timed run" >&2
    printf '| %s | **RUN FAILED** | | | | | | | |\n' "$name" >> "$OUT"
    FAILURES=$((FAILURES + 1)); continue
  fi

  # Stats pass is separate and untimed: instrumentation must never contaminate
  # the numbers reported above.
  MARCH_STRING_STATS=1 "$bin" > /dev/null 2> "$TMP/$name.stats"
  stat_of() { grep "^march_string_stats $1 " "$TMP/$name.stats" | awk '{print $3}'; }
  allocs=$(stat_of allocs)
  abytes=$(stat_of alloc_bytes)
  cbytes=$(stat_of copy_bytes)
  pbytes=$(stat_of peak_live_bytes)

  mb() { awk -v b="${1:-0}" 'BEGIN { printf "%.1f", b / 1048576 }'; }
  printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
    "$name" "$med" "$mn" "$mx" "$(mb "$rss")" "${allocs:-0}" \
    "$(mb "$abytes")" "$(mb "$cbytes")" "$(mb "$pbytes")" >> "$OUT"

  echo "ok   $name  ${med}ms  rss $(mb "$rss")MB  copied $(mb "$cbytes")MB"
done

if [ "$FAILURES" -gt 0 ]; then
  printf '\n**%d benchmark(s) failed — results above are incomplete.**\n' "$FAILURES" >> "$OUT"
  echo "$FAILURES benchmark(s) failed" >&2
  exit 1
fi
echo "wrote $OUT"
```

- [ ] **Step 2: Fill in the expected checksums**

Replace each `FILL_ME` in the `EXPECTED` map with the value recorded in that benchmark's `Expected output:` comment (Tasks 3–6). Until they are filled, the checksum gate is inert — which is why this step exists as its own step.

- [ ] **Step 3: Make it executable and run it**

```bash
chmod +x bench/run_string_bench.sh
dune build --root . bin/main.exe
bash bench/run_string_bench.sh
```

Expected: six `ok` lines and `wrote .../bench/STRING_RESULTS.md`, exit 0.

- [ ] **Step 4: Verify the checksum gate actually fires**

A gate that never fails is not a gate. Temporarily corrupt one expected value:

```bash
sed -i.bak 's/\[string_scan\]="[0-9]*"/[string_scan]="999999"/' bench/run_string_bench.sh
bash bench/run_string_bench.sh string_scan; echo "exit=$?"
mv bench/run_string_bench.sh.bak bench/run_string_bench.sh
```

Expected: `FAIL string_scan: checksum ... expected 999999` and `exit=1`. If it exits 0, the gate is broken — fix it before committing.

- [ ] **Step 5: Commit**

```bash
git add bench/run_string_bench.sh bench/STRING_RESULTS.md
git commit -m "bench: string performance harness with checksum gate and RSS capture"
```

---

### Task 8: Zero-overhead verification

**Files:**
- Modify: `bench/run_string_bench.sh` (add `--verify-overhead` mode)
- Modify: `specs/2026-07-26-string-performance-design.md` (record the mechanism change)

**Interfaces:**
- Consumes: the harness from Task 7.
- Produces: `bash bench/run_string_bench.sh --verify-overhead` exiting non-zero if instrumented-off runtime exceeds baseline by >2%.

**Design note — deviation from the spec:** the spec described this as an alcotest test. A 2% timing assertion in `dune runtest` would flake on any loaded CI machine and get muted, which is worse than not having it. It lands as a harness mode instead: same claim, same threshold, run deliberately rather than on every test invocation. Update the spec's "Keeping the harness honest" item 3 to match.

- [ ] **Step 1: Add the mode to the harness**

Insert after the `if [ ! -x "$MARCH" ]` guard:

```bash
# --verify-overhead: the "zero cost when off" claim, checked rather than
# assumed.  Compares the same binary with MARCH_STRING_STATS unset against
# MARCH_STRING_STATS=0 (both take the off path) -- if merely having the
# counters compiled in costs more than 2%, the baseline numbers this harness
# reports are contaminated by their own instrumentation.
if [ "${1:-}" = "--verify-overhead" ]; then
  name=string_small_churn      # the most allocation-dense benchmark
  bin="$TMP/$name"
  "$MARCH" --compile --opt 2 "$REPO_ROOT/bench/$name.march" -o "$bin" > /dev/null 2>&1 \
    || { echo "compile failed" >&2; exit 1; }
  read -r base _ _ _ <<< "$(timeit "$bin")"
  read -r off  _ _ _ <<< "$(MARCH_STRING_STATS=0 timeit "$bin")"
  echo "baseline ${base}ms   stats-off ${off}ms"
  awk -v a="$base" -v b="$off" 'BEGIN {
    pct = (b - a) / a * 100;
    printf "overhead %.2f%%\n", pct;
    exit (pct > 2.0) ? 1 : 0
  }' || { echo "FAIL: stats-off overhead exceeds 2%" >&2; exit 1; }
  echo "ok: overhead within 2%"
  exit 0
fi
```

- [ ] **Step 2: Run it**

```bash
bash bench/run_string_bench.sh --verify-overhead
```

Expected: `overhead <2.00%` and `ok: overhead within 2%`, exit 0.

If it exceeds 2%, the cause is almost certainly `march_str_copy` failing to inline or `str_stats_on()` being called per byte rather than per operation. Check that `str_stats_on()` appears **once per string operation**, not inside any loop.

- [ ] **Step 3: Update the spec**

In `specs/2026-07-26-string-performance-design.md`, replace item 3 of "Keeping the harness honest" with:

```markdown
3. **Instrumentation contaminating the baseline.** `bash bench/run_string_bench.sh
   --verify-overhead` asserts that the most allocation-dense benchmark's median
   runtime with `MARCH_STRING_STATS` off is within 2% of baseline. It is a
   harness mode rather than an alcotest test on purpose: a 2% timing assertion
   inside `dune runtest` would flake on loaded CI and get muted, which is worse
   than not having it.
```

- [ ] **Step 4: Commit**

```bash
git add bench/run_string_bench.sh specs/2026-07-26-string-performance-design.md
git commit -m "bench: verify the zero-overhead-when-off claim for string stats"
```

---

### Task 9: Run the profile and apply the decision criteria

**Files:**
- Create: `specs/2026-07-26-string-performance-profile.md`
- Modify: `specs/progress.md`, `CHANGELOG.md`, `specs/todos.md`

**Interfaces:**
- Consumes: everything above.
- Produces: the written verdict that opens the phase 2 spec.

- [ ] **Step 1: Run the full suite at profiling size**

```bash
dune build --root . bin/main.exe
bash bench/run_string_bench.sh 2>&1 | tee /tmp/string_bench_run.log
```

Run on an otherwise idle machine. Record the machine (CPU, core count, OS) in the profile document — these numbers are meaningless without it.

- [ ] **Step 2: Collect the SSO scaling evidence**

The SSO criterion requires that wall time scale with allocation count. Double the knob and re-measure:

```bash
sed -i.bak 's/pfn pairs() : Int do 200000 end/pfn pairs() : Int do 400000 end/' bench/string_small_churn.march
./_build/default/bin/main.exe --compile --opt 2 bench/string_small_churn.march -o /tmp/churn2x
MARCH_STRING_STATS=1 /tmp/churn2x 2>&1 >/dev/null | grep allocs
bash -c 'time /tmp/churn2x' 2>&1 | tail -3
mv bench/string_small_churn.march.bak bench/string_small_churn.march
```

Expected: allocations roughly double. Record whether wall time does too — flat time under doubled allocations means allocation is not the bottleneck and SSO would buy little.

- [ ] **Step 3: Cross-check against a real profile**

The spec's first risk is that the corpus measures the wrong thing. Check it:

```bash
# macOS
xcrun xctrace record --template 'Time Profiler' --launch /tmp/string_split_large
# Linux
perf record -g /tmp/string_split_large && perf report --stdio | head -40
```

Confirm the hot symbols are the string functions the benchmark targets. **If they are not, stop — the corpus is wrong and phase 2 must not read anything into it.**

- [ ] **Step 4: Write the profile document**

Create `specs/2026-07-26-string-performance-profile.md` containing:

1. Machine and date.
2. The `bench/STRING_RESULTS.md` table, verbatim.
3. The allocation histogram for each benchmark.
4. The `string_split_large` vs `string_slice_walk` comparison, with the bytes-copied and allocation counts side by side, and which of the two costs dominates.
5. The parallel scaling curve (1/2/4/8) and the measured speedup at 8 workers.
6. **Each decision criterion from the spec, quoted, with the measured value and a met/not-met verdict.** Do not paraphrase the criteria — quote them, so the verdict is checkable against what was committed in advance.
7. A recommendation for phase 2 that follows from those verdicts, including anything the criteria did *not* settle.

- [ ] **Step 5: Update the project records**

Per the project's documentation rules, all three files in the same commit:

- `specs/progress.md` — a "Current State" entry describing what phase 1 built and what the profile concluded.
- `specs/todos.md` — move the phase 1 item to Done; add phase 2 (repr decision from the profile) and phase 3 (data-parallel ops) as pending.
- `CHANGELOG.md` — under `[Unreleased]` → `### Added`: the `MARCH_STRING_STATS` env var and the string benchmark suite. These are user-visible; the internal counters are not, so describe the flag and the suite, not the plumbing.

- [ ] **Step 6: Verify docs and full suite are clean**

```bash
scripts/check-docs.sh
scripts/run-tests.sh 2>&1 | tail -5
```

Expected: doc-lint passes; the test suite is green apart from any pre-existing environmental failures (a hung `MARCH_SANITIZE` test is a known machine-level ASAN issue, confirmable with a trivial `clang -fsanitize=address` control program).

- [ ] **Step 7: Commit**

```bash
git add specs/2026-07-26-string-performance-profile.md specs/progress.md specs/todos.md CHANGELOG.md
git commit -m "docs: string performance phase 1 profile and decision verdicts"
```

---

## Self-review

**Spec coverage:** corpus (Tasks 3–6, all six programs), counters (Tasks 1–2, all six metrics including the histogram), harness with RSS and median-of-5 (Task 7), decision criteria applied (Task 9 Step 4), all three integrity guards (checksum gate Task 7 Step 4, counter validation Tasks 1–2, overhead check Task 8), the `march_http.c:350` blind spot (noted in the spec, unchanged here), the cross-check-against-a-real-profile risk mitigation (Task 9 Step 3).

**Known deviation:** the zero-overhead check is a harness mode rather than an alcotest test (Task 8 rationale, spec updated in the same task).

**Placeholders:** the `FILL_ME` checksums and `Expected output:` comments are intentional — real values cannot be known before the code runs, and each has a dedicated step that fills it in plus a step that proves the gate fires (Task 7 Steps 2 and 4).

**Type consistency:** the stats key names in the Task 1 dump (`allocs`, `alloc_bytes`, `frees`, `copy_bytes`, `peak_live_bytes`, `hist_*`) are the same strings parsed by the Task 1/2 tests and by the Task 7 harness's `stat_of`. `Parallel.pmap`'s `Vec` requirement is flagged in Task 6 where it is used.
