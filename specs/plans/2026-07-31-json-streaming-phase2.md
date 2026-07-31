# Streaming JSON Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `JsonStream` fast by replacing per-byte token materialization
with per-run slicing, then decide on C/SIMD from a measurement rather than an
assumption. Design: `specs/2026-07-31-json-streaming-phase2-design.md`.

**Architecture:** No interface change, no new C. `str_byte`'s plain-content
path and `num_byte`'s digit path stop allocating a 1-byte string + cons cell
per byte and instead slice the whole run in one step, using the existing
memchr-backed `string_index_of_from` builtin to find the run end. Plus
`EvNumRaw(String)` as an opt-in lossless number mode (design Component 2b).

**Tech Stack:** March stdlib (`string_index_of_from`, `string_slice`,
`string_byte_at`, `string_byte_length`), `march test`, alcotest registration
already in place from phase 1.

## Global Constraints

- Build **in this worktree** with `--root .`. Never `eval $(opam env ...)`;
  never a bare targetless `dune build --root .` (it wedges — always name
  targets). NEVER `git stash` (the stash stack is shared across worktrees).
- Stage files explicitly by name; no `git add -A`/`.`; no Co-Authored-By.
- **Phase 1's 217 tests must pass UNMODIFIED.** The single permitted edit to
  the existing test file is the new `EvNumRaw` arm in `ev_str` that
  exhaustiveness forces (Task 3). A test that needs editing to accommodate a
  speedup is a behavior change wearing a disguise — if one fails, the
  implementation is wrong, not the test.
- **The per-byte loop stays strictly tail-recursive.** Every continuation is
  a tail call to `go` or an `Err`. Run-slicing must not introduce a non-tail
  frame.
- **`cap no_panic` stays.** No new `/` or `%` except by nonzero constants.
- March syntax traps that have bitten this module: `init` and `doc` are
  reserved words; `else` is mandatory and every `else if` needs its own
  closing `end`; write `0 - 1` not a bare `-1`; lambdas are `fn x -> body`.
- `string_slice(s, start, LEN)` — the third argument is a **length**, not an
  end index. `string_byte_at` returns a negative sentinel past the end.
- Test: `dune build --root . bin/main.exe && ./_build/default/bin/main.exe test test/stdlib/test_json_stream.march`
  (judge by exit code; expect 217 until Task 3 adds more).
- Registered suite: `dune build --root . test/test_stdlib_march.exe && ./_build/default/test/test_stdlib_march.exe test json_stream -e`
- Compiled runs need `dune build --root . @install` first — a targeted
  `bin/main.exe` build does **not** restage stdlib, and the compiled binary
  reads the staged copy. Never pipe `march --compile` output; redirect to a
  file and judge `$?`.
- Benchmark A/B arms need `rm -rf .march/cas/artifacts-v2` between them, and
  timings must be compared within one session (never across runs) with the
  arm order swapped — the first timed variant pays a warmup penalty.

## File Structure

- `stdlib/json_stream.march` — all implementation changes.
- `test/stdlib/test_json_stream.march` — new tests appended; existing ones
  untouched except Task 3's forced `ev_str` arm.
- `bench/json_stream.march` + `specs/benchmarks.md` — Task 4.
- `specs/todos.md`, `specs/progress.md`, `CHANGELOG.md`,
  `specs/2026-07-31-json-streaming-phase2-design.md` — Task 4.

---

### Task 1: Run-slicing for string content

**Files:**
- Modify: `stdlib/json_stream.march` (add `run_end` + `str_run`; change one
  branch of `str_byte`)
- Modify: `test/stdlib/test_json_stream.march` (append tests only)

**Interfaces:**
- Produces (internal, used by Task 2's sibling logic): `run_end(s, i) : Int`
  returning the index of the next `"` or `\` at or after `i`, or `0 - 1` if
  neither occurs before the chunk ends.
- Consumes: existing `PStr(pieces, len, esc, hi, soff)`, `go`, `push_piece`.

- [ ] **Step 1: Write the failing/characterizing tests**

Append inside the main `describe "JsonStream" do` block. These must pass both
before and after — they characterize behavior run-slicing must preserve, and
two of them exercise paths the existing suite does not reach:

```march
  describe "run-sliced strings" do
    test "long escape-free string round-trips" do
      let body = repeat_str("abcdefghij", 500, "")
      assert (one_shot("\"" ++ body ++ "\"") == "S(" ++ body ++ ")|")
    end
    test "run interrupted by an escape rejoins correctly" do
      assert (one_shot("\"aaa\\nbbb\"") == "S(aaa" ++ byte_to_char(10) ++ "bbb)|")
    end
    test "run split across a chunk boundary rejoins correctly" do
      assert (two_shot("\"abcdefghij\"", 5) == "S(abcdefghij)|")
    end
    test "many runs separated by escapes" do
      assert (one_shot("\"a\\tb\\tc\\td\"") ==
              "S(a" ++ byte_to_char(9) ++ "b" ++ byte_to_char(9)
                   ++ "c" ++ byte_to_char(9) ++ "d)|")
    end
    test "non-ASCII bytes survive a run" do
      -- C3 A9 is U+00E9; run-slicing must not decode or split it.
      let e = byte_to_char(195) ++ byte_to_char(169)
      assert (one_shot("\"x" ++ e ++ "y\"") == "S(x" ++ e ++ "y)|")
    end
    test "token limit trips mid-run, at the token start offset" do
      -- The limit must be checked BEFORE the run is materialized: a 100-byte
      -- run against a 10-byte limit must not allocate 100 bytes first.
      let st = JsonStream.start_with(JsonStream.JsonLimits(8, 10))
      match JsonStream.feed(st, "\"" ++ repeat_str("a", 100, "") ++ "\"") do
      Err(e) -> assert (err_str(e) == "TOK:0")
      Ok(_) -> assert (false)
      end
    end
    test "token limit counts across runs, not per run" do
      -- Two 6-byte runs under an 8-byte limit must still trip.
      let st = JsonStream.start_with(JsonStream.JsonLimits(8, 8))
      match JsonStream.feed(st, "\"aaaaaa\\naaaaaa\"") do
      Err(e) -> assert (err_str(e) == "TOK:0")
      Ok(_) -> assert (false)
      end
    end
    test "pending high surrogate still rejects a raw byte at its own offset" do
      -- Run-slicing must be suppressed while a high surrogate is pending.
      assert (one_shot("\"\\ud83dxyz\"") == "ERR:7")
    end
  end
```

`repeat_str` and `byte_to_char` already exist in the test file / as a
builtin. If the last test's expected offset disagrees with the
implementation, **do not adjust it without checking the pre-change
behavior** — run the same probe against a `git stash`-free copy of the
current module (use `git show HEAD:stdlib/json_stream.march > /tmp/pre_cg858.march`
and compare reasoning); a changed offset here means run-slicing swallowed a
byte it should have rejected.

- [ ] **Step 2: Run — all must PASS pre-change**

```bash
dune build --root . bin/main.exe 2>&1 | tail -3
./_build/default/bin/main.exe test test/stdlib/test_json_stream.march; echo "exit=$?"
```

Expected: 225 passed (217 + 8), exit 0. These characterize existing
behavior, so a failure here is a bug in the test, not the module — fix the
test before touching the implementation.

- [ ] **Step 3: Add the run-end probe**

In `stdlib/json_stream.march`, beside the other small helpers (after
`hex_val`):

```march
  -- Index of the next '"' or '\' at or after `i`, or 0 - 1 if neither occurs
  -- before the chunk ends.  Both probes go through `string_index_of_from`,
  -- which is backed by `march_memmem` (two-stage memchr + memcmp) in the C
  -- runtime -- so this is the vectorized scan phase 2 leans on, with no new
  -- C written.  Control bytes deliberately do NOT end a run: they are
  -- passed through as content per the design's decision table.
  pfn run_end(s, i) do
    match string_index_of_from(s, "\"", i) do
    None ->
      match string_index_of_from(s, "\\", i) do
      None -> 0 - 1
      Some(y) -> y
      end
    Some(x) ->
      match string_index_of_from(s, "\\", i) do
      None -> x
      Some(y) -> if y < x do y else x end
      end
    end
  end
```

- [ ] **Step 4: Add the run slicer**

Beside `push_piece`:

```march
  -- Slice a whole plain run in one piece instead of one 1-byte string plus
  -- one cons cell per byte -- the phase 2 measurement showed that per-byte
  -- materialization, not scanning, is what made the tokenizer 3.6x slower
  -- than Json.parse.
  --
  -- The caller guarantees the byte at `i` is neither '"' nor '\' and that no
  -- high surrogate is pending, so the run is at least one byte and `go`
  -- always advances -- there is no zero-length step to loop on.
  --
  -- The length check happens BEFORE the slice is materialized: a 10MB run
  -- against an 8MB limit must return ETokenLimit, not allocate 10MB first.
  pfn str_run(s, i, cfg, mode, stack, depth, base, evs, ps, len, hi, soff) do
    let e = run_end(s, i)
    let stop = if e < 0 do string_byte_length(s) else e end
    match cfg do
    JsCfg(_, maxt, _) ->
      let len2 = len + (stop - i)
      if len2 > maxt do Err(ETokenLimit(soff))
      else
        go(s, stop, cfg, mode, stack, depth,
           PStr(Cons(string_slice(s, i, stop - i), ps), len2, SPlain, hi, soff),
           base, evs)
      end
    end
  end
```

- [ ] **Step 5: Route `str_byte`'s plain-content branch through it**

Replace the final `else` branch of `str_byte`'s `SPlain` case — the one
currently calling `push_piece(... byte_to_char(c))` — with:

```march
      else
        -- Plain content: take the whole run at once.  `c` is known not to be
        -- '"' or '\' here, and `hi < 0`, which is exactly str_run's contract.
        str_run(s, i, cfg, mode, stack, depth, base, evs, ps, len, hi, soff)
      end end end
```

Leave everything else in `str_byte` alone — the `hi >= 0` guard above it is
what keeps run-slicing from swallowing a byte that must be rejected as a
lone high surrogate, and the `SEsc`/`SHex` paths still advance one byte at a
time because escapes are one byte at a time by nature.

Note `byte_to_char` may become unused in `str_byte`; it is still used by
`simple_escape`/`utf8_encode`, so do not delete it.

- [ ] **Step 6: Run the full module suite**

```bash
dune build --root . bin/main.exe 2>&1 | tail -3
./_build/default/bin/main.exe test test/stdlib/test_json_stream.march; echo "exit=$?"
dune build --root . test/test_stdlib_march.exe 2>&1 | tail -2
./_build/default/test/test_stdlib_march.exe test json_stream -e; echo "exit=$?"
```

Expected: 225 passed, exit 0 on both — **with no edits to any pre-existing
test**. The every-byte-split differential and the truncation sweep are the
load-bearing checks here: they prove run-slicing did not make event
boundaries depend on chunk boundaries. If either fails, stop and fix the
implementation.

- [ ] **Step 7: Quick sanity measurement (not the gate)**

```bash
dune build --root . @install 2>&1 | tail -2
rm -rf .march/cas/artifacts-v2
./_build/default/bin/main.exe --compile --opt 2 bench/json_stream.march -o /tmp/js_t1_cg858 > /tmp/js_t1_compile_cg858.log 2>&1; echo "compile=$?"
/tmp/js_t1_cg858
```

Expected: `checksum=280000` unchanged, and `ms=` meaningfully below the
~225ms phase 1 baseline. Record the number in the report. Task 4 does the
rigorous A/B; this is just a smoke check that the change did something.

- [ ] **Step 8: Commit**

```bash
git add stdlib/json_stream.march test/stdlib/test_json_stream.march
git commit -m "perf(stdlib): JsonStream slices whole string runs instead of per-byte pieces"
```

---

### Task 2: Run-slicing for number lexemes

**Files:**
- Modify: `stdlib/json_stream.march` (add `num_end`; change `num_byte`'s
  digit branch and `num_start`)
- Modify: `test/stdlib/test_json_stream.march` (append tests only)

**Interfaces:**
- Consumes: `PNum(pieces, len, soff)`, `num_finalize`, `valid_num` — all
  unchanged in behavior.
- Produces: nothing new for later tasks; Task 3 modifies `num_finalize`
  independently.

- [ ] **Step 1: Write the characterizing tests**

```march
  describe "run-sliced numbers" do
    test "long integer round-trips" do
      let digits = repeat_str("1234567890", 20, "")
      assert (one_shot(digits) == "N(" ++ to_string(string_to_float_or_zero(digits)) ++ ")|")
    end
    test "number split across a chunk boundary" do
      assert (two_shot("-12345.6789e2", 6) == one_shot("-12345.6789e2"))
    end
    test "number followed immediately by a delimiter" do
      assert (one_shot("[1,22,333]") == "[|N(1.)|N(22.)|N(333.)|]|")
    end
    test "number token limit trips at the token start" do
      let st = JsonStream.start_with(JsonStream.JsonLimits(8, 4))
      match JsonStream.feed(st, "123456789") do
      Err(e) -> assert (err_str(e) == "TOK:0")
      Ok(_) -> assert (false)
      end
    end
    test "malformed numbers still report the token start" do
      assert (one_shot("012") == "ERR:0")
      assert (one_shot("1e") == "ERR:0")
    end
  end
```

**Before writing these, check whether a `string_to_float_or_zero` helper
exists in the test file.** If not, replace the first test's expectation with
a direct comparison that does not depend on float rendering — e.g. assert
that `one_shot(digits) == two_shot(digits, 7)`, which tests the same
property (chunk-independence of a long run) without pinning a float format.
Prefer that formulation; it is more robust either way.

- [ ] **Step 2: Run — all must PASS pre-change**

```bash
./_build/default/bin/main.exe test test/stdlib/test_json_stream.march; echo "exit=$?"
```

Expected: 230 passed, exit 0.

- [ ] **Step 3: Add the number-run probe**

Beside `run_end`:

```march
  -- End of the number run starting at `i`: the first index whose byte is not
  -- part of a number lexeme.  `string_byte_at` returns a negative sentinel
  -- past the end and `is_num_byte` rejects it, so this always terminates.
  -- Unlike run_end there is no memchr for "first byte NOT in a set", so this
  -- stays a scalar scan -- but it allocates nothing, which is the win.
  -- Replacing it with a C classifier is exactly the phase 2 design's
  -- Component 4 question, gated on measurement.
  pfn num_end(s, i) do
    if is_num_byte(string_byte_at(s, i)) do num_end(s, i + 1) else i end
  end
```

- [ ] **Step 4: Slice the run in `num_byte`**

Replace `num_byte`'s `is_num_byte(c)` branch — currently pushing
`char_from_int(c)` and advancing one byte — with:

```march
    if is_num_byte(c) do
      let stop = num_end(s, i)
      match cfg do
      JsCfg(_, maxt, _) ->
        let len2 = len + (stop - i)
        if len2 > maxt do Err(ETokenLimit(soff))
        else
          go(s, stop, cfg, mode, stack, depth,
             PNum(Cons(string_slice(s, i, stop - i), ps), len2, soff), base, evs)
        end
      end
    else
```

Leave the `else` (delimiter → finalize and reprocess at the same `i`)
exactly as it is. That reprocess step is what guarantees progress, and it
still holds: `stop > i` because `c` is a number byte.

- [ ] **Step 5: Let `num_start` take its run too**

`num_start` currently materializes the first byte alone with
`char_from_int(c)` and a `1 > maxt` check (added by #135 — **preserve that
check's behavior exactly**, including its `base + i` error offset). Replace
its body so the whole opening run is one slice:

```march
  pfn num_start(s, i, c, cfg, mode, stack, depth, base, evs) do
    let stop = num_end(s, i)
    match cfg do
    JsCfg(_, maxt, _) ->
      if stop - i > maxt do Err(ETokenLimit(base + i))
      else
        go(s, stop, cfg, mode, stack, depth,
           PNum(Cons(string_slice(s, i, stop - i), Nil), stop - i, base + i), base, evs)
      end
    end
  end
```

`c` is `-` or a digit, both of which are number bytes, so `stop - i >= 1`
and the `maxt = 0` rejection #135 added is preserved (`1 > 0`). Re-run the
`max_token_bytes = 0` tests #135 added specifically to confirm.

- [ ] **Step 6: Run the full module suite**

```bash
dune build --root . bin/main.exe 2>&1 | tail -3
./_build/default/bin/main.exe test test/stdlib/test_json_stream.march; echo "exit=$?"
./_build/default/test/test_stdlib_march.exe test json_stream -e; echo "exit=$?"
```

Expected: 230 passed, exit 0, no pre-existing test edited.

- [ ] **Step 7: Commit**

```bash
git add stdlib/json_stream.march test/stdlib/test_json_stream.march
git commit -m "perf(stdlib): JsonStream slices number lexemes in one piece"
```

---

### Task 3: `EvNumRaw(String)` and `with_raw_numbers` (design Component 2b)

**Files:**
- Modify: `stdlib/json_stream.march`
- Modify: `test/stdlib/test_json_stream.march` (the one permitted edit to an
  existing helper, plus new tests)

**Interfaces:**
- Produces: `with_raw_numbers(st : JsState) : JsState`; `EvNumRaw(String)`
  added to `Event`.
- Consumes: `JsCfg`, `num_finalize`, `build_step` from Tasks 1–2.

- [ ] **Step 1: Write the failing tests**

```march
  describe "raw numbers" do
    test "default mode still yields EvNum" do
      assert (one_shot("42") == "N(42.)|")
    end
    test "raw mode yields the verbatim lexeme" do
      let st = JsonStream.with_raw_numbers(JsonStream.start())
      match JsonStream.feed(st, "42") do
      Err(_) -> assert (false)
      Ok((evs, st2)) ->
        match JsonStream.finish(st2) do
        Err(_) -> assert (false)
        Ok(evs2) -> assert (evs_str(evs) ++ evs_str(evs2) == "R(42)|")
        end
      end
    end
    test "raw mode is lossless above 2^53 where default mode is not" do
      -- 9007199254740993 = 2^53 + 1, not representable as a Float.
      let big = "9007199254740993"
      let st = JsonStream.with_raw_numbers(JsonStream.start())
      match JsonStream.feed(st, big) do
      Err(_) -> assert (false)
      Ok((evs, st2)) ->
        match JsonStream.finish(st2) do
        Err(_) -> assert (false)
        Ok(evs2) -> assert (evs_str(evs) ++ evs_str(evs2) == "R(" ++ big ++ ")|")
        end
      end
      -- And the default mode demonstrably loses it: the rendered float is not
      -- the input lexeme.  This half is what proves the feature does anything.
      assert (one_shot(big) != "N(" ++ big ++ ")|")
    end
    test "raw mode composes with ndjson and custom limits" do
      let st = JsonStream.with_raw_numbers(
                 JsonStream.start_ndjson_with(JsonStream.JsonLimits(8, 1000)))
      match JsonStream.feed(st, "1\n2\n3\n") do
      Err(_) -> assert (false)
      Ok((evs, st2)) ->
        match JsonStream.finish(st2) do
        Err(_) -> assert (false)
        Ok(evs2) -> assert (evs_str(evs) ++ evs_str(evs2) == "R(1)|R(2)|R(3)|")
        end
      end
    end
    test "raw mode rejects malformed numbers identically" do
      let st = JsonStream.with_raw_numbers(JsonStream.start())
      match JsonStream.feed(st, "012") do
      Err(e) -> assert (err_str(e) == "ERR:0")
      Ok(_) -> assert (false)
      end
    end
    test "raw mode still respects the token limit" do
      let st = JsonStream.with_raw_numbers(
                 JsonStream.start_with(JsonStream.JsonLimits(8, 4)))
      match JsonStream.feed(st, "123456789") do
      Err(e) -> assert (err_str(e) == "TOK:0")
      Ok(_) -> assert (false)
      end
    end
    test "build converts raw numbers, so trees match either mode" do
      match JsonStream.build(Seq.from_list(Cons("[1, 2.5]", Nil))) do
      Err(_) -> assert (false)
      Ok(v) ->
        match Json.parse("[1, 2.5]") do
        Ok(v2) -> assert (Json.to_string(v) == Json.to_string(v2))
        Err(_) -> assert (false)
        end
      end
    end
  end
```

Also extend the existing `ev_str` helper with the forced arm — **this is the
only permitted edit to a pre-existing test helper**:

```march
  EvNumRaw(r) -> "R(" ++ r ++ ")"
```

- [ ] **Step 2: Run to verify the new tests fail**

```bash
dune build --root . bin/main.exe 2>&1 | tail -3
./_build/default/bin/main.exe test test/stdlib/test_json_stream.march; echo "exit=$?"
```

Expected: failures naming `EvNumRaw` / `with_raw_numbers` as unknown.

- [ ] **Step 3: Add the event variant**

In `Event`:

```march
  | EvNumRaw(String)
```

Add it **after** `EvNum(Float)`. Every `match` over `Event` must now handle
it — the compiler will name the sites.

- [ ] **Step 4: Widen `JsCfg` and add the setter**

`JsCfg` gains a fourth field. This is a `ptype`, so no caller sees it — but
**every `match cfg do JsCfg(...)` site must gain a fourth pattern slot**.
Find them all with `grep -n "JsCfg(" stdlib/json_stream.march`.

```march
  -- max_depth, max_token_bytes, ndjson mode, raw-number mode
  ptype JsCfg = JsCfg(Int, Int, Bool, Bool)
```

```march
  pfn cfg_of(l, nd) do
    match l do JsonLimits(d, t) -> JsCfg(d, t, nd, false) end
  end
```

```march
  doc """
  Emit `EvNumRaw(lexeme)` instead of `EvNum(float)`, preserving integers
  above 2^53 that a `Float` cannot represent.

  Composes with every constructor:

      let st = JsonStream.with_raw_numbers(JsonStream.start_ndjson())

  Validation is unchanged -- a malformed number is still rejected with the
  same error at the same offset.  Intended for a fresh state; applied
  mid-stream it affects only numbers completed after the call.
  """
  fn with_raw_numbers(st) do
    match st do
    StOk(cfg, mode, stack, depth, partial, off) ->
      match cfg do
      JsCfg(d, t, nd, _) -> StOk(JsCfg(d, t, nd, true), mode, stack, depth, partial, off)
      end
    end
  end
```

- [ ] **Step 5: Branch `num_finalize` on the mode**

`num_finalize(ps, soff)` currently validates then converts. It needs the
raw flag. Change its signature to `num_finalize(cfg, ps, soff)` and update
its **two** call sites (`num_byte`'s delimiter branch and `finish`'s `PNum`
branch — `grep -n "num_finalize" stdlib/json_stream.march`):

```march
  pfn num_finalize(cfg, ps, soff) do
    let lex = join_pieces(ps)
    if valid_num(lex) do
      match cfg do
      JsCfg(_, _, _, raw) ->
        if raw do Ok(EvNumRaw(lex))
        else
          match string_to_float(lex) do
          Some(f) -> Ok(EvNum(f))
          None -> Err(EMalformed("invalid number", soff))
          end
        end
      end
    else Err(EMalformed("invalid number", soff)) end
  end
```

`valid_num` runs in **both** modes — raw mode changes what a valid number
carries, never what counts as valid.

- [ ] **Step 6: Handle `EvNumRaw` in the tree builder**

`build_step`'s `EvNum(f) -> bpush(frames, Number(f))` gains a sibling.
`Json.JsonValue`'s `Number` holds a `Float`, so raw lexemes convert on
receipt — trees are then identical in both modes and the `Json.parse`
differential holds either way:

```march
    EvNumRaw(r) ->
      match string_to_float(r) do
      Some(f) -> bpush(frames, Number(f))
      None -> Err(EMalformed("invalid number", 0))
      end
```

The `None` arm is unreachable for a `valid_num`-approved lexeme; it exists
so the match is total rather than partial.

- [ ] **Step 7: Run the suites**

```bash
dune build --root . bin/main.exe 2>&1 | tail -3
./_build/default/bin/main.exe test test/stdlib/test_json_stream.march; echo "exit=$?"
./_build/default/bin/main.exe test test/stdlib/test_json.march; echo "exit=$?"
./_build/default/test/test_stdlib_march.exe test json_stream -e; echo "exit=$?"
```

Expected: 237 passed, exit 0 everywhere; `test_json.march` still 197.

- [ ] **Step 8: Run the totality harnesses in raw mode too**

The design requires the every-byte-split differential and truncation sweep
to run in **both** number modes. Add raw-mode variants of the two harness
tests, reusing the existing corpus lists, with raw-mode `one_shot`/`two_shot`
equivalents (`one_shot_raw` / `two_shot_raw` built by substituting
`JsonStream.with_raw_numbers(JsonStream.start())` for `JsonStream.start()`).
Keep the default-mode harnesses exactly as they are.

```bash
./_build/default/bin/main.exe test test/stdlib/test_json_stream.march; echo "exit=$?"
```

- [ ] **Step 9: Commit**

```bash
git add stdlib/json_stream.march test/stdlib/test_json_stream.march
git commit -m "feat(stdlib): JsonStream opt-in EvNumRaw for lossless large integers"
```

---

### Task 4: Measure, decide the SIMD gate, document

**Files:**
- Modify: `bench/json_stream.march` (add a string-heavy and a number-heavy
  variant, or parameterize), `specs/benchmarks.md`
- Modify: `specs/todos.md`, `specs/progress.md`, `CHANGELOG.md`,
  `specs/2026-07-31-json-streaming-phase2-design.md`

- [ ] **Step 1: Re-run the `Json.parse` A/B, order-swapped**

Recreate the phase 2 design's measurement. Write two programs that differ
only in which arm runs first, so the first-position warmup penalty is
visible rather than assumed:

```march
-- Arm A runs JsonStream first, arm B runs Json.parse first. Same corpus:
-- 20,000 records of {"id": N, "name": "user-N", "active": true, "tags": [1, 2, 3]}
-- JsonStream only COUNTS events; Json.parse builds full trees.
```

Build both with `dune build --root . @install`, `rm -rf .march/cas/artifacts-v2`
between arms, compile with `--opt 2`, and record all four numbers. The
design's phase 1 figures to beat: `Json.parse` 62ms, `JsonStream` 223–226ms.

- [ ] **Step 2: Measure string-heavy and number-heavy corpora separately**

Components 1 and 2 pay off unevenly, and one aggregate number would blur
attribution. Two variants of the record template:

- string-heavy: long string field values, few numbers
- number-heavy: many numeric fields, short strings

Record `ms` and MaxRSS (`/usr/bin/time -l`) for each, plus the unchanged
`checksum` proving the corpora parse identically before and after.

- [ ] **Step 3: Apply the design's committed decision criteria**

From `specs/2026-07-31-json-streaming-phase2-design.md`, verbatim — do not
renegotiate them now that a number exists:

- **Within ~1.5× of `Json.parse`** → diagnosis confirmed. Proceed to
  Component 4 **only if** a profile then shows scanning (not allocation, not
  RC) as the next dominant term.
- **Within ~1.5× and scanning is not dominant** → phase 2 **stops**;
  close Component 4 as not-built with the measurement recorded.
- **Gap not mostly closed** → the diagnosis was wrong. Stop and profile
  before writing any C.

Write the verdict and the numbers that produced it into the report. If the
verdict is "stop", that is a **result**, not a failure — record it the way
`specs/plans/2026-07-27-string-performance-phase2.md` recorded its Tasks 4
and 5 closures.

- [ ] **Step 4: Update the benchmark docs**

Update `specs/benchmarks.md`'s `bench/json_stream.march` entry: keep the
phase 1 baseline for comparison, add the phase 2 numbers beside it, and
revise the "What to watch" to describe run-slicing as the thing a regression
would point at. Note the string-heavy/number-heavy split.

- [ ] **Step 5: Update the canonical docs**

- `specs/2026-07-31-json-streaming-phase2-design.md`: flip **Status**, record
  the measured outcome, and record the Component 4/5 verdict.
- `specs/todos.md`: move the phase 2 item to Done with the numbers; open a
  new item only if Component 4 or 5 was left genuinely pending.
- `specs/progress.md`: new dated entry at the top (newest-first).
- `CHANGELOG.md` under `[Unreleased]`: a `### Changed` bullet for the
  speedup and an `### Added` bullet for `with_raw_numbers`/`EvNumRaw`.

- [ ] **Step 6: Full-suite and docs-lint gate**

```bash
scripts/run-tests.sh 2>&1 | tail -6
bash scripts/check-docs.sh 2>&1 | tail -4
bash scripts/gen-docs-search-index.sh --check 2>&1 | tail -2
```

Known-environmental failure: the `MARCH_SANITIZE` / `adversarial-regressions`
timeout. Anything else needs investigation — first re-run it alone, then
check `ps` for concurrent sessions (load contamination is a known
false-failure source here). Both doc checks must exit 0.

- [ ] **Step 7: Commit**

```bash
git add bench/json_stream.march specs/benchmarks.md specs/todos.md specs/progress.md CHANGELOG.md specs/2026-07-31-json-streaming-phase2-design.md
git commit -m "bench+docs: JsonStream phase 2 measurements and the SIMD gate verdict"
```

---

## Self-review

**Spec coverage:** design Component 1 → Task 1; Component 2 → Task 2;
Component 2b → Task 3; Component 3 (re-measure + gate) → Task 4.
Components 4 (C byte-set scanner) and 5 (`feed_fold`) are deliberately
**not** given tasks — both are gated on Task 4's verdict, and pre-writing
their tasks would prejudge the gate the design committed to.

**Placeholder scan:** two steps defer to the source at execution time, each
with an explicit instruction rather than a vague one — Task 2 Step 1's
check for a `string_to_float_or_zero` helper (with the preferred fallback
formulation given), and Task 3 Step 4's `grep` for all `JsCfg(` pattern
sites. Both are "verify then act", not "figure it out".

**Type consistency:** `run_end(s, i) : Int` and `num_end(s, i) : Int` both
return chunk-relative indices with `0 - 1` / `i` sentinels respectively, used
consistently in Tasks 1–2. `num_finalize` changes arity from
`(ps, soff)` to `(cfg, ps, soff)` in Task 3 only, with both call sites named.
`JsCfg` is 3-field in Tasks 1–2 and 4-field from Task 3 — the pattern slots
in Tasks 1–2's code blocks are written 3-wide on purpose and Task 3 widens
them all.

**The invariant most likely to be broken quietly:** run-slicing changing
event boundaries as a function of chunk arrival. It is invisible to
aggregate assertions and caught only by the every-byte-split differential,
which is why every task re-runs the whole suite rather than just its own
tests, and why no task is permitted to edit a pre-existing test.
