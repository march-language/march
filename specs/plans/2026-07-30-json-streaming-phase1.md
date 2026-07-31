# Streaming JSON Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A total, resumable, constant-memory streaming JSON tokenizer
(`JsonStream`) in pure March, per `specs/2026-07-30-json-streaming-design.md`.

**Architecture:** A tail-recursive byte-at-a-time state machine. Parser state
is an explicit value (`StOk(cfg, mode, stack, depth, partial, offset)`), so
`feed` suspends at any byte and resumes on the next chunk. Zero new C; zero
compiler changes; one new stdlib module + tests + benchmark.

**Tech Stack:** March stdlib (`string_byte_at`, `string_slice`, `string_join`,
`string_to_float`, `char_from_int`, `string_byte_length`), the `march test`
runner, alcotest registration in `test/test_stdlib_march.ml`.

## Global Constraints

- Build **in this worktree** with `--root .`: `dune build --root . bin/main.exe`.
  Never `eval $(opam env ...)`; never a bare targetless `dune build --root .`
  (it wedges — always name targets). NEVER `git stash` (shared stash stack).
- Stage files explicitly by name; no `git add -A`/`.`; no Co-Authored-By lines.
- March syntax traps (each has caused real bugs): `if c do .. else .. end` —
  `else` is mandatory and every `else if` needs its own closing `end`;
  lambdas are `fn x -> body` (no do/end form); exactly ONE top-level `mod`
  per file; **`init` is a reserved word** (hence `start()`); a `(`-led line
  glues onto nothing (fixed 2026-07-30) but avoid starting lines with `(`
  anyway; write `0 - 1` rather than a bare `-1` literal in expressions.
- All new constructors are prefixed (`Ev*`, `E*`, `M*`, `P*`, `S*`, `Js*`,
  `F*`, `St*`) because the ctor/type namespace is FLAT across modules.
  Task 1 greps to prove no collision before the first build.
- The tokenizer's per-byte loop must be **strictly tail-recursive** — every
  continuation is a tail call to `go` (or an `Err`). A non-tail frame per
  byte overflows on megabyte chunks. Never "simplify" a helper into a
  non-tail shape.
- `cap no_panic` is declared on the module; the only `/`//`%` allowed are by
  the nonzero constants in `utf8_encode` (64, 4096, 262144), which the
  division-safety checker proves.
- Test runner (interpreted, fast iteration):
  `dune build --root . bin/main.exe && ./_build/default/bin/main.exe test test/stdlib/test_json_stream.march`
- Suite runner (after registration):
  `dune build --root . test/test_stdlib_march.exe && ./_build/default/test/test_stdlib_march.exe test json_stream -e`
- Judge every command by exit code, not tail output. Never pipe
  `march --compile` output.

## File Structure

- `stdlib/json_stream.march` — the whole module (tokenizer, drivers, builder).
- `bin/main.ml` — one line: `"json_stream.march"` in `stdlib_file_list`
  (append after `"json.march"`, ~line 292).
- `test/stdlib/test_json_stream.march` — all March-level tests, grown per task.
- `test/test_stdlib_march.ml` — one registration block (Task 1).
- `bench/json_stream.march` + `specs/benchmarks.md` entry (Task 5).
- `specs/todos.md`, `specs/progress.md`, `CHANGELOG.md` — Task 5.

---

### Task 1: Tokenizer core — scalars at top level

Literals, strings (escapes, `\uXXXX`, surrogate pairs), numbers, whitespace,
trailing-garbage detection, `finish`, limits on tokens. No containers yet
(`{`/`[` produce a clear `EMalformed` in this task; Task 2 replaces those two
branches). Single-doc mode only (`start_ndjson` exists but behaves like
`start` until Task 2 wires `after_value`'s ndjson branch — that branch IS
included here since it is one `if`).

**Files:**
- Create: `stdlib/json_stream.march`
- Modify: `bin/main.ml` (stdlib_file_list, after `"json.march"`)
- Create: `test/stdlib/test_json_stream.march`
- Modify: `test/test_stdlib_march.ml` (registration)

**Interfaces (later tasks rely on exactly these):**
- Produces: `start()`, `start_with(l)`, `start_ndjson()`, `default_limits()`,
  `feed(st, chunk) : Result((List(Event), JsState), JsonStreamError)`,
  `finish(st) : Result(List(Event), JsonStreamError)`,
  `err_to_string(e) : String`.
- Internal, extended by Task 2: `free_byte` (its `value_start` `{`/`[`
  branches), `after_value`, the `JsMode` type (all 10 ctors declared NOW so
  Task 2 only fills in behavior).

- [ ] **Step 1: Collision grep — must be empty before anything else**

```bash
grep -rn "EvObjStart\|EvArrStart\|EvKey\|EvStr\|EvNum\|EvBool\|EvNull\|EMalformed\|EDepthLimit\|ETokenLimit\|ETruncated\|JsonLimits\|JsonStreamError\|JsMode\|JsPartial\|JsEsc\|JsCfg\|JsState\|StOk\b\|MTop\b\|MArrFirst\|MObjColon\|PLit\b\|PStr\b\|PNum\b\|SPlain\|SHex\b" stdlib/ lib/ bin/ | grep -v Binary
```

Expected: no output. Any hit → rename the colliding name (keep the prefix
discipline) and update every later task's code to match.

- [ ] **Step 2: Write the failing test file**

Create `test/stdlib/test_json_stream.march`:

```march
-- Tests for the JsonStream stdlib module (streaming JSON tokenizer).
-- Run with: dune exec march -- test test/stdlib/test_json_stream.march
-- Design: specs/2026-07-30-json-streaming-design.md

mod TestJsonStream do

-- Render an event list as a compact string so assertions compare one string.
pfn ev_str(e) do
  match e do
  EvObjStart -> "{"
  EvObjEnd -> "}"
  EvArrStart -> "["
  EvArrEnd -> "]"
  EvKey(k) -> "K(" ++ k ++ ")"
  EvStr(sv) -> "S(" ++ sv ++ ")"
  EvNum(f) -> "N(" ++ to_string(f) ++ ")"
  EvBool(b) -> if b do "T" else "F" end
  EvNull -> "0"
  end
end

pfn evs_str(evs) do
  match evs do
  Nil -> ""
  Cons(h, t) -> ev_str(h) ++ "|" ++ evs_str(t)
  end
end

-- Feed one whole string as a single chunk, then finish; render all events,
-- or "ERR:<n>" / "TRUNC:<n>" etc. on error.
pfn err_str(e) do
  match e do
  EMalformed(_, off) -> "ERR:" ++ to_string(off)
  EDepthLimit(off) -> "DEPTH:" ++ to_string(off)
  ETokenLimit(off) -> "TOK:" ++ to_string(off)
  ETruncated(off) -> "TRUNC:" ++ to_string(off)
  end
end

pfn one_shot(src) do
  match JsonStream.feed(JsonStream.start(), src) do
  Err(e) -> err_str(e)
  Ok((evs, st)) ->
    match JsonStream.finish(st) do
    Err(e) -> evs_str(evs) ++ err_str(e)
    Ok(evs2) -> evs_str(evs) ++ evs_str(evs2)
    end
  end
end

-- Same input, split into two chunks at byte k.
pfn two_shot(src, k) do
  let n = string_byte_length(src)
  let a = string_slice(src, 0, k)
  let b = string_slice(src, k, n - k)
  match JsonStream.feed(JsonStream.start(), a) do
  Err(e) -> err_str(e)
  Ok((evs1, st1)) ->
    match JsonStream.feed(st1, b) do
    Err(e) -> evs_str(evs1) ++ err_str(e)
    Ok((evs2, st2)) ->
      match JsonStream.finish(st2) do
      Err(e) -> evs_str(evs1) ++ evs_str(evs2) ++ err_str(e)
      Ok(evs3) -> evs_str(evs1) ++ evs_str(evs2) ++ evs_str(evs3)
      end
    end
  end
end

describe "JsonStream" do

  describe "scalars one-shot" do
    test "sentinel (suite is not vacuously empty)" do
      assert (true)
    end
    test "null" do assert (one_shot("null") == "0|") end
    test "true" do assert (one_shot("true") == "T|") end
    test "false" do assert (one_shot("false") == "F|") end
    test "leading and trailing whitespace" do
      assert (one_shot("  \t\r\n null \n") == "0|")
    end
    test "simple string" do assert (one_shot("\"hi\"") == "S(hi)|") end
    test "empty string" do assert (one_shot("\"\"") == "S()|") end
    test "escapes" do
      assert (one_shot("\"a\\\"b\\\\c\\/d\\n\"") ==
              "S(a\"b\\c/d" ++ char_from_int(10) ++ ")|")
    end
    test "unicode escape BMP" do
      assert (one_shot("\"\\u0041\"") == "S(A)|")
    end
    test "unicode escape two-byte" do
      -- U+00E9 é = 0xC3 0xA9
      assert (one_shot("\"\\u00e9\"") ==
              "S(" ++ char_from_int(195) ++ char_from_int(169) ++ ")|")
    end
    test "surrogate pair to 4-byte UTF-8" do
      -- U+1F600 = \uD83D\uDE00 = F0 9F 98 80
      assert (one_shot("\"\\ud83d\\ude00\"") ==
              "S(" ++ char_from_int(240) ++ char_from_int(159)
                   ++ char_from_int(152) ++ char_from_int(128) ++ ")|")
    end
    test "integer" do assert (one_shot("42") == "N(42.0)|") end
    test "negative" do assert (one_shot("-7") == "N(-7.0)|") end
    test "zero" do assert (one_shot("0") == "N(0.0)|") end
    test "float" do assert (one_shot("3.5") == "N(3.5)|") end
    test "exponent" do assert (one_shot("2e3") == "N(2000.0)|") end
    test "number then trailing space" do assert (one_shot("42 ") == "N(42.0)|") end
  end

  describe "scalars malformed" do
    test "bare garbage" do assert (one_shot("xyz") == "ERR:0") end
    test "bad literal" do assert (one_shot("trve") == "ERR:2") end
    test "trailing garbage after value" do assert (one_shot("null null") == "ERR:5") end
    test "unknown escape" do assert (one_shot("\"\\q\"") == "ERR:2") end
    test "bad hex in unicode escape" do assert (one_shot("\"\\u00zz\"") == "ERR:5") end
    test "lone high surrogate then char" do assert (one_shot("\"\\ud83dx\"") == "ERR:7") end
    test "lone low surrogate" do assert (one_shot("\"\\ude00\"") == "ERR:7") end
    test "leading zeros" do assert (one_shot("012") == "ERR:0") end
    test "bare minus" do assert (one_shot("-") == "ERR:0") end
    test "dot without frac digits" do assert (one_shot("1.") == "ERR:0") end
    test "exp without digits" do assert (one_shot("1e") == "ERR:0") end
  end

  describe "truncation" do
    test "half a literal" do assert (one_shot("tru") == "TRUNC:0") end
    test "unterminated string" do assert (one_shot("\"abc") == "TRUNC:0") end
    test "string open mid-escape" do assert (one_shot("\"a\\") == "TRUNC:0") end
    test "empty input" do assert (one_shot("") == "TRUNC:0") end
    test "bare number completes at finish" do assert (one_shot("42") == "N(42.0)|") end
  end

  describe "chunk splits" do
    test "literal split" do assert (two_shot("true", 2) == "T|") end
    test "string split mid-content" do assert (two_shot("\"hello\"", 3) == "S(hello)|") end
    test "string split mid-escape" do
      assert (two_shot("\"a\\nb\"", 3) == "S(a" ++ char_from_int(10) ++ "b)|")
    end
    test "string split mid-hex" do assert (two_shot("\"\\u0041\"", 4) == "S(A)|") end
    test "surrogate pair split between halves" do
      assert (two_shot("\"\\ud83d\\ude00\"", 7) ==
              "S(" ++ char_from_int(240) ++ char_from_int(159)
                   ++ char_from_int(152) ++ char_from_int(128) ++ ")|")
    end
    test "number split" do assert (two_shot("1234", 2) == "N(1234.0)|") end
    test "error offset is absolute across chunks" do
      -- "null " then "x": offset of x is 5
      assert (two_shot("null x", 5) == "ERR:5")
    end
  end

  describe "limits" do
    test "token limit on a long string" do
      -- max_token_bytes = 4; five content bytes trips it. Offset = token start.
      let st = JsonStream.start_with(JsonStream.JsonLimits(8, 4))
      match JsonStream.feed(st, "\"abcdef\"") do
      Err(e) -> assert (err_str(e) == "TOK:0")
      Ok(_) -> assert (false)
      end
    end
  end

end

end
```

Notes for the implementer: `two_shot` uses `string_slice(s, start, LEN)` —
the third argument is a length, not an end index. `err_str` offsets in the
malformed tests are worked out from the design's decision table: number
shape errors report the token START (`ERR:0` for `"012"`), byte-level errors
report the offending byte (`ERR:2` for `trve`), and lone-surrogate errors
report the byte at which the violation became certain (the char after the
escape, or the final hex digit's position for `\ude00` — byte 7 is the
closing quote / last hex digit respectively). If an assertion disagrees with
the implementation by ±1 on one of these, the implementation's offset is
acceptable **if and only if** it is deterministic and documented — adjust
the test, note it in the commit message.

- [ ] **Step 3: Register the suite and confirm it FAILS (module absent)**

In `test/test_stdlib_march.ml`, after the `("json", [...])` block (~line 297):

```ocaml
    ("json_stream", [
      Alcotest.test_case "JsonStream module"
        `Quick (run_stdlib_test "test_json_stream.march" "TestJsonStream");
    ]);
```

Run:

```bash
dune build --root . bin/main.exe 2>&1 | tail -3
./_build/default/bin/main.exe test test/stdlib/test_json_stream.march; echo "exit=$?"
```

Expected: failure — `JsonStream` unknown. This proves the tests exercise the
real module rather than passing vacuously.

- [ ] **Step 4: Write the module**

Create `stdlib/json_stream.march` with exactly this content (Task 2 will
replace two branches of `value_start` and one arm of `after_value`):

```march
-- JsonStream: resumable, total, constant-memory streaming JSON tokenizer.
--
-- Design: specs/2026-07-30-json-streaming-design.md.  Feed chunks with
-- `feed`, close with `finish`.  Every failure is an Err with an absolute
-- byte offset; no input can panic, crash, or grow memory beyond the
-- configured limits.  The per-byte loop is strictly tail-recursive — keep
-- it that way (see the design's "why a state machine" section).
--
-- All constructor names are prefixed (Ev*/E*/M*/P*/S*/Js*/St*): the ctor
-- namespace is flat across modules, and Json.JsonValue already owns the
-- natural names.  Do not rename until FQN type identity lands.

mod JsonStream do

  cap no_panic

  -- ── Public types ──────────────────────────────────────────────────────

  type Event =
      EvObjStart
    | EvObjEnd
    | EvArrStart
    | EvArrEnd
    | EvKey(String)
    | EvStr(String)
    | EvNum(Float)
    | EvBool(Bool)
    | EvNull

  type JsonStreamError =
      EMalformed(String, Int)
    | EDepthLimit(Int)
    | ETokenLimit(Int)
    | ETruncated(Int)

  -- max_depth, max_token_bytes
  type JsonLimits = JsonLimits(Int, Int)

  fn default_limits() do JsonLimits(512, 8000000) end

  fn err_to_string(e) do
    match e do
    EMalformed(msg, off) -> msg ++ " at byte " ++ to_string(off)
    EDepthLimit(off) -> "nesting deeper than max_depth at byte " ++ to_string(off)
    ETokenLimit(off) -> "token longer than max_token_bytes starting at byte " ++ to_string(off)
    ETruncated(off) -> "input truncated at byte " ++ to_string(off)
    end
  end

  -- ── Internal state ────────────────────────────────────────────────────

  -- What the grammar expects next.  MTop: the (next) top-level value.
  -- MDone: single-doc top-level value consumed.  MArrFirst: just after '['
  -- (value or ']').  MArrValue: after ',' in an array (value required).
  -- MArrNext: after an array element (',' or ']').  MObjFirst: just after
  -- '{' (key or '}').  MObjKey: after ',' in an object (key required).
  -- MObjColon: after a key (':' required).  MObjValue: after ':'.
  -- MObjNext: after an object value (',' or '}').
  ptype JsMode =
      MTop | MDone
    | MArrFirst | MArrValue | MArrNext
    | MObjFirst | MObjKey | MObjColon | MObjValue | MObjNext

  -- String-escape scanner state: plain content, just after '\', or inside
  -- \uXXXX with (digits seen, value so far).
  ptype JsEsc = SPlain | SEsc | SHex(Int, Int)

  -- In-flight token.  String/number content accumulates as a REVERSED list
  -- of pieces joined once at completion (linear, unlike repeated ++).
  -- Every variant carries the token's absolute start offset for errors.
  ptype JsPartial =
      PNone
    | PLit(String, Int, Int)                    -- lexeme, matched, start
    | PStr(List(String), Int, JsEsc, Int, Int)  -- pieces, len, esc, pending high surrogate (0-1 = none), start
    | PNum(List(String), Int, Int)              -- pieces, len, start

  -- max_depth, max_token_bytes, ndjson mode
  ptype JsCfg = JsCfg(Int, Int, Bool)

  -- cfg, mode, container stack (parent modes), depth, in-flight token,
  -- absolute offset of the next unread byte.
  ptype JsState = StOk(JsCfg, JsMode, List(JsMode), Int, JsPartial, Int)

  -- ── Construction ──────────────────────────────────────────────────────

  fn start() do StOk(cfg_of(default_limits(), false), MTop, Nil, 0, PNone, 0) end
  fn start_with(l) do StOk(cfg_of(l, false), MTop, Nil, 0, PNone, 0) end
  fn start_ndjson() do StOk(cfg_of(default_limits(), true), MTop, Nil, 0, PNone, 0) end
  fn start_ndjson_with(l) do StOk(cfg_of(l, true), MTop, Nil, 0, PNone, 0) end

  pfn cfg_of(l, nd) do
    match l do JsonLimits(d, t) -> JsCfg(d, t, nd) end
  end

  -- ── Small helpers ─────────────────────────────────────────────────────

  pfn rev(xs, acc) do
    match xs do
    Nil -> acc
    Cons(h, t) -> rev(t, Cons(h, acc))
    end
  end

  pfn join_pieces(ps) do string_join(rev(ps, Nil), "") end

  pfn is_ws(c) do
    if c == 32 do true else if c == 9 do true else if c == 10 do true
    else if c == 13 do true else false end end end end
  end

  pfn is_digit(c) do
    if c >= 48 do c <= 57 else false end
  end

  -- Bytes that may CONTINUE a number token: digits - + . e E
  pfn is_num_byte(c) do
    if is_digit(c) do true else if c == 45 do true else if c == 43 do true
    else if c == 46 do true else if c == 101 do true else if c == 69 do true
    else false end end end end end end
  end

  pfn hex_val(c) do
    if is_digit(c) do c - 48
    else if c >= 97 do if c <= 102 do c - 87 else 0 - 1 end
    else if c >= 65 do if c <= 70 do c - 55 else 0 - 1 end
    else 0 - 1 end end end
  end

  -- Encode a Unicode codepoint as UTF-8 bytes.  char_from_int is
  -- single-byte (n & 0xFF in the runtime), so multi-byte sequences are
  -- assembled explicitly.  Divisors are nonzero constants (cap no_panic).
  pfn utf8_encode(cp) do
    if cp < 128 do char_from_int(cp)
    else if cp < 2048 do
      char_from_int(192 + cp / 64) ++ char_from_int(128 + (cp % 64))
    else if cp < 65536 do
      char_from_int(224 + cp / 4096)
        ++ char_from_int(128 + ((cp / 64) % 64))
        ++ char_from_int(128 + (cp % 64))
    else
      char_from_int(240 + cp / 262144)
        ++ char_from_int(128 + ((cp / 4096) % 64))
        ++ char_from_int(128 + ((cp / 64) % 64))
        ++ char_from_int(128 + (cp % 64))
    end end end
  end

  -- After a value completes in `mode`, the successor mode.
  pfn after_value(cfg, mode) do
    match mode do
    MTop -> match cfg do JsCfg(_, _, nd) -> if nd do MTop else MDone end end
    MArrFirst -> MArrNext
    MArrValue -> MArrNext
    MObjValue -> MObjNext
    _ -> mode  -- unreachable by construction; total anyway
    end
  end

  -- ── The per-byte loop ─────────────────────────────────────────────────
  -- Every continuation is a tail call to `go` or an Err.  `base` is the
  -- absolute offset of chunk byte 0; `base + i` is the current byte's
  -- absolute offset.

  fn feed(st, chunk) do
    match st do
    StOk(cfg, mode, stack, depth, partial, base) ->
      go(chunk, 0, cfg, mode, stack, depth, partial, base, Nil)
    end
  end

  pfn go(s, i, cfg, mode, stack, depth, partial, base, evs) do
    let c = string_byte_at(s, i)
    if c < 0 do
      Ok((rev(evs, Nil), StOk(cfg, mode, stack, depth, partial, base + i)))
    else
      match partial do
      PNone -> free_byte(s, i, c, cfg, mode, stack, depth, base, evs)
      PLit(lex, k, soff) ->
        lit_byte(s, i, c, cfg, mode, stack, depth, base, evs, lex, k, soff)
      PStr(ps, len, esc, hi, soff) ->
        str_byte(s, i, c, cfg, mode, stack, depth, base, evs, ps, len, esc, hi, soff)
      PNum(ps, len, soff) ->
        num_byte(s, i, c, cfg, mode, stack, depth, base, evs, ps, len, soff)
      end
    end
  end

  -- No token in flight: dispatch on the grammar mode.
  pfn free_byte(s, i, c, cfg, mode, stack, depth, base, evs) do
    if is_ws(c) do go(s, i + 1, cfg, mode, stack, depth, PNone, base, evs)
    else
      match mode do
      MDone -> Err(EMalformed("unexpected data after top-level value", base + i))
      MObjColon ->
        if c == 58 do go(s, i + 1, cfg, MObjValue, stack, depth, PNone, base, evs)
        else Err(EMalformed("expected ':' after object key", base + i)) end
      MObjNext ->
        if c == 44 do go(s, i + 1, cfg, MObjKey, stack, depth, PNone, base, evs)
        else if c == 125 do close_obj(s, i, cfg, stack, depth, base, evs)
        else Err(EMalformed("expected ',' or '}' in object", base + i)) end end
      MArrNext ->
        if c == 44 do go(s, i + 1, cfg, MArrValue, stack, depth, PNone, base, evs)
        else if c == 93 do close_arr(s, i, cfg, stack, depth, base, evs)
        else Err(EMalformed("expected ',' or ']' in array", base + i)) end end
      MObjFirst ->
        if c == 34 do
          go(s, i + 1, cfg, mode, stack, depth, PStr(Nil, 0, SPlain, 0 - 1, base + i), base, evs)
        else if c == 125 do close_obj(s, i, cfg, stack, depth, base, evs)
        else Err(EMalformed("expected a key or '}' in object", base + i)) end end
      MObjKey ->
        if c == 34 do
          go(s, i + 1, cfg, mode, stack, depth, PStr(Nil, 0, SPlain, 0 - 1, base + i), base, evs)
        else Err(EMalformed("expected a key in object", base + i)) end
      MArrFirst ->
        if c == 93 do close_arr(s, i, cfg, stack, depth, base, evs)
        else value_start(s, i, c, cfg, mode, stack, depth, base, evs) end
      _ -> value_start(s, i, c, cfg, mode, stack, depth, base, evs)
      end
    end
  end

  -- A byte that must begin a value (mode is MTop, MArrFirst, MArrValue,
  -- or MObjValue).
  pfn value_start(s, i, c, cfg, mode, stack, depth, base, evs) do
    if c == 34 do
      go(s, i + 1, cfg, mode, stack, depth, PStr(Nil, 0, SPlain, 0 - 1, base + i), base, evs)
    else if c == 116 do
      go(s, i + 1, cfg, mode, stack, depth, PLit("true", 1, base + i), base, evs)
    else if c == 102 do
      go(s, i + 1, cfg, mode, stack, depth, PLit("false", 1, base + i), base, evs)
    else if c == 110 do
      go(s, i + 1, cfg, mode, stack, depth, PLit("null", 1, base + i), base, evs)
    else if c == 45 do
      go(s, i + 1, cfg, mode, stack, depth,
         PNum(Cons(char_from_int(c), Nil), 1, base + i), base, evs)
    else if is_digit(c) do
      go(s, i + 1, cfg, mode, stack, depth,
         PNum(Cons(char_from_int(c), Nil), 1, base + i), base, evs)
    else if c == 123 do
      Err(EMalformed("objects not yet supported (Task 2)", base + i))
    else if c == 91 do
      Err(EMalformed("arrays not yet supported (Task 2)", base + i))
    else Err(EMalformed("expected a JSON value", base + i))
    end end end end end end end end
  end

  -- Containers: Task 1 stubs close_* as unreachable-but-total; Task 2
  -- replaces the two value_start branches above and these two bodies.
  pfn close_obj(s, i, cfg, stack, depth, base, evs) do
    Err(EMalformed("unmatched '}'", base + i))
  end
  pfn close_arr(s, i, cfg, stack, depth, base, evs) do
    Err(EMalformed("unmatched ']'", base + i))
  end

  -- ── Literals ──────────────────────────────────────────────────────────

  pfn lit_event(lex) do
    if lex == "true" do EvBool(true)
    else if lex == "false" do EvBool(false)
    else EvNull end end
  end

  pfn lit_byte(s, i, c, cfg, mode, stack, depth, base, evs, lex, k, soff) do
    let e = string_byte_at(lex, k)
    if c == e do
      if string_byte_at(lex, k + 1) < 0 do
        go(s, i + 1, cfg, after_value(cfg, mode), stack, depth, PNone, base,
           Cons(lit_event(lex), evs))
      else
        go(s, i + 1, cfg, mode, stack, depth, PLit(lex, k + 1, soff), base, evs)
      end
    else Err(EMalformed("invalid literal", base + i)) end
  end

  -- ── Strings ───────────────────────────────────────────────────────────

  pfn simple_escape(c) do
    if c == 34 do Some("\"")
    else if c == 92 do Some("\\")
    else if c == 47 do Some("/")
    else if c == 110 do Some(char_from_int(10))
    else if c == 114 do Some(char_from_int(13))
    else if c == 116 do Some(char_from_int(9))
    else if c == 98 do Some(char_from_int(8))
    else if c == 102 do Some(char_from_int(12))
    else None end end end end end end end end
  end

  pfn push_piece(s, i, cfg, mode, stack, depth, base, evs, ps, len, hi, soff, t) do
    match cfg do
    JsCfg(_, maxt, _) ->
      let len2 = len + string_byte_length(t)
      if len2 > maxt do Err(ETokenLimit(soff))
      else
        go(s, i + 1, cfg, mode, stack, depth,
           PStr(Cons(t, ps), len2, SPlain, hi, soff), base, evs)
      end
    end
  end

  pfn finish_str(s, i, cfg, mode, stack, depth, base, evs, ps) do
    let v = join_pieces(ps)
    match mode do
    MObjFirst -> go(s, i + 1, cfg, MObjColon, stack, depth, PNone, base, Cons(EvKey(v), evs))
    MObjKey -> go(s, i + 1, cfg, MObjColon, stack, depth, PNone, base, Cons(EvKey(v), evs))
    _ -> go(s, i + 1, cfg, after_value(cfg, mode), stack, depth, PNone, base, Cons(EvStr(v), evs))
    end
  end

  pfn str_byte(s, i, c, cfg, mode, stack, depth, base, evs, ps, len, esc, hi, soff) do
    match esc do
    SPlain ->
      if hi >= 0 do
        -- A high surrogate is pending: only '\' (opening the low half) is legal.
        if c == 92 do
          go(s, i + 1, cfg, mode, stack, depth, PStr(ps, len, SEsc, hi, soff), base, evs)
        else Err(EMalformed("lone high surrogate in string escape", base + i)) end
      else if c == 34 do finish_str(s, i, cfg, mode, stack, depth, base, evs, ps)
      else if c == 92 do
        go(s, i + 1, cfg, mode, stack, depth, PStr(ps, len, SEsc, hi, soff), base, evs)
      else
        -- Raw byte, including control bytes and non-ASCII (passed through;
        -- see the design's decision table).
        push_piece(s, i, cfg, mode, stack, depth, base, evs, ps, len, hi, soff,
                   char_from_int(c))
      end end end
    SEsc ->
      if c == 117 do
        go(s, i + 1, cfg, mode, stack, depth, PStr(ps, len, SHex(0, 0), hi, soff), base, evs)
      else if hi >= 0 do
        Err(EMalformed("lone high surrogate in string escape", base + i))
      else
        match simple_escape(c) do
        Some(t) -> push_piece(s, i, cfg, mode, stack, depth, base, evs, ps, len, hi, soff, t)
        None -> Err(EMalformed("unknown escape sequence", base + i))
        end
      end end
    SHex(k, v) ->
      let d = hex_val(c)
      if d < 0 do Err(EMalformed("invalid hex digit in unicode escape", base + i))
      else
        let v2 = v * 16 + d
        if k < 3 do
          go(s, i + 1, cfg, mode, stack, depth, PStr(ps, len, SHex(k + 1, v2), hi, soff), base, evs)
        else
          hex_done(s, i, cfg, mode, stack, depth, base, evs, ps, len, hi, soff, v2)
        end
      end
    end
  end

  -- All four hex digits of \uXXXX are in: interpret the codepoint.
  pfn hex_done(s, i, cfg, mode, stack, depth, base, evs, ps, len, hi, soff, cp) do
    if hi >= 0 do
      -- Expecting the LOW half of a surrogate pair: DC00..DFFF.
      if cp >= 56320 do
        if cp <= 57343 do
          let full = 65536 + (hi - 55296) * 1024 + (cp - 56320)
          push_piece(s, i, cfg, mode, stack, depth, base, evs, ps, len, 0 - 1, soff,
                     utf8_encode(full))
        else Err(EMalformed("expected low surrogate in unicode escape", base + i)) end
      else Err(EMalformed("expected low surrogate in unicode escape", base + i)) end
    else if cp >= 55296 do
      if cp <= 56319 do
        -- High surrogate: hold it; the next escape must be the low half.
        go(s, i + 1, cfg, mode, stack, depth, PStr(ps, len, SPlain, cp, soff), base, evs)
      else if cp <= 57343 do
        Err(EMalformed("lone low surrogate in unicode escape", base + i))
      else
        push_piece(s, i, cfg, mode, stack, depth, base, evs, ps, len, 0 - 1, soff,
                   utf8_encode(cp))
      end end
    else
      push_piece(s, i, cfg, mode, stack, depth, base, evs, ps, len, 0 - 1, soff,
                 utf8_encode(cp))
    end end
  end

  -- ── Numbers ───────────────────────────────────────────────────────────
  -- Accumulate every number-class byte; validate the complete lexeme when a
  -- delimiter (or finish) ends it.  Shape errors therefore report the token
  -- START offset — a documented, deliberate coarsening (design §tokenizer).

  pfn num_byte(s, i, c, cfg, mode, stack, depth, base, evs, ps, len, soff) do
    if is_num_byte(c) do
      match cfg do
      JsCfg(_, maxt, _) ->
        if len + 1 > maxt do Err(ETokenLimit(soff))
        else
          go(s, i + 1, cfg, mode, stack, depth,
             PNum(Cons(char_from_int(c), ps), len + 1, soff), base, evs)
        end
      end
    else
      -- Delimiter: finalize, then REPROCESS byte c (same i) token-free.
      match num_finalize(ps, soff) do
      Err(e) -> Err(e)
      Ok(ev) -> go(s, i, cfg, after_value(cfg, mode), stack, depth, PNone, base, Cons(ev, evs))
      end
    end
  end

  pfn num_finalize(ps, soff) do
    let lex = join_pieces(ps)
    if valid_num(lex) do
      match string_to_float(lex) do
      Some(f) -> Ok(EvNum(f))
      None -> Err(EMalformed("invalid number", soff))
      end
    else Err(EMalformed("invalid number", soff)) end
  end

  -- Complete-lexeme validator for: -? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?
  pfn valid_num(lex) do
    let i = if string_byte_at(lex, 0) == 45 do 1 else 0 end
    vn_int(lex, i)
  end

  pfn vn_int(lex, i) do
    let c = string_byte_at(lex, i)
    if c == 48 do vn_frac(lex, i + 1)
    else if is_digit(c) do vn_frac(lex, vn_digits(lex, i + 1))
    else false end end
  end

  pfn vn_digits(lex, i) do
    if is_digit(string_byte_at(lex, i)) do vn_digits(lex, i + 1) else i end
  end

  pfn vn_frac(lex, i) do
    let c = string_byte_at(lex, i)
    if c < 0 do true
    else if c == 46 do
      if is_digit(string_byte_at(lex, i + 1)) do vn_exp(lex, vn_digits(lex, i + 2))
      else false end
    else if c == 101 do vn_exp_body(lex, i + 1)
    else if c == 69 do vn_exp_body(lex, i + 1)
    else false end end end end
  end

  pfn vn_exp(lex, i) do
    let c = string_byte_at(lex, i)
    if c < 0 do true
    else if c == 101 do vn_exp_body(lex, i + 1)
    else if c == 69 do vn_exp_body(lex, i + 1)
    else false end end end
  end

  pfn vn_exp_body(lex, i) do
    let c = string_byte_at(lex, i)
    let j = if c == 43 do i + 1 else if c == 45 do i + 1 else i end end
    if is_digit(string_byte_at(lex, j)) do vn_tail(lex, j + 1) else false end
  end

  pfn vn_tail(lex, i) do
    let c = string_byte_at(lex, i)
    if c < 0 do true
    else if is_digit(c) do vn_tail(lex, i + 1)
    else false end end
  end

  -- ── finish ────────────────────────────────────────────────────────────

  fn finish(st) do
    match st do
    StOk(cfg, mode, stack, depth, partial, off) ->
      match partial do
      PNone -> finish_mode(cfg, mode, stack, off, Nil)
      PNum(ps, len, soff) ->
        match num_finalize(ps, soff) do
        Err(e) -> Err(e)
        Ok(ev) -> finish_mode(cfg, after_value(cfg, mode), stack, off, Cons(ev, Nil))
        end
      PLit(lex, k, soff) -> Err(ETruncated(soff))
      PStr(ps, len, esc, hi, soff) -> Err(ETruncated(soff))
      end
    end
  end

  pfn finish_mode(cfg, mode, stack, off, evs) do
    match mode do
    MDone -> Ok(evs)
    MTop ->
      match cfg do
      JsCfg(_, _, nd) ->
        if nd do
          match stack do
          Nil -> Ok(evs)
          _ -> Err(ETruncated(off))
          end
        else Err(ETruncated(off)) end
      end
    _ -> Err(ETruncated(off))
    end
  end

end
```

- [ ] **Step 5: Register the module in the stdlib list**

`bin/main.ml`, in `stdlib_file_list`, immediately after `"json.march"`:

```ocaml
  "json_stream.march";
```

- [ ] **Step 6: Build and run the tests**

```bash
dune build --root . bin/main.exe 2>&1 | tail -5; echo "build=$?"
./_build/default/bin/main.exe test test/stdlib/test_json_stream.march; echo "exit=$?"
```

Expected: build clean, all tests pass, `exit=0`. If the typechecker or
`cap no_panic` checker reports against `stdlib/json_stream.march`, read the
diagnostic — do not suppress it. Known-possible friction: if
`Division_safety` cannot discharge the constant divisors in `utf8_encode`,
that is a checker gap — report it, and only then fall back to
strength-reducing the divisions to comparisons+subtractions (all divisors
are powers of two; `cp / 64` = repeated halving is NOT acceptable in a
tail loop — instead precompute with multiplication comparisons). Do not
remove `cap no_panic`.

Then the registered suite:

```bash
dune build --root . test/test_stdlib_march.exe 2>&1 | tail -3
./_build/default/test/test_stdlib_march.exe test json_stream -e; echo "exit=$?"
```

Expected: PASS, `exit=0`.

- [ ] **Step 7: Commit**

```bash
git add stdlib/json_stream.march bin/main.ml test/stdlib/test_json_stream.march test/test_stdlib_march.ml
git commit -m "feat(stdlib): JsonStream streaming tokenizer — scalars, escapes, limits"
```

---

### Task 2: Containers, depth limit, NDJSON

**Files:**
- Modify: `stdlib/json_stream.march` (`value_start` `{`/`[` branches,
  `close_obj`, `close_arr`, new `open_container`)
- Modify: `test/stdlib/test_json_stream.march` (new describe blocks)

**Interfaces:**
- Consumes: everything from Task 1 unchanged.
- Produces: full JSON grammar; `start_ndjson()` now meaningful.

- [ ] **Step 1: Write the failing tests**

Append inside `describe "JsonStream" do`:

```march
  describe "containers" do
    test "empty array" do assert (one_shot("[]") == "[|]|") end
    test "empty object" do assert (one_shot("{}") == "{|}|") end
    test "array of scalars" do
      assert (one_shot("[1, \"a\", true, null]") == "[|N(1.0)|S(a)|T|0|]|")
    end
    test "object" do
      assert (one_shot("{\"x\": 1, \"y\": [2]}") == "{|K(x)|N(1.0)|K(y)|[|N(2.0)|]|}|")
    end
    test "nested" do
      assert (one_shot("[[[]]]") == "[|[|[|]|]|]|")
    end
    test "number closed by bracket" do assert (one_shot("[7]") == "[|N(7.0)|]|") end
    test "container split across chunks" do
      assert (two_shot("{\"a\": [1, 2]}", 6) == "{|K(a)|[|N(1.0)|N(2.0)|]|}|")
    end
  end

  describe "containers malformed" do
    test "trailing comma in array" do assert (one_shot("[1,]") == "ERR:3") end
    test "comma before first element" do assert (one_shot("[,1]") == "ERR:1") end
    test "missing colon" do assert (one_shot("{\"a\" 1}") == "ERR:5") end
    test "missing comma" do assert (one_shot("[1 2]") == "ERR:3") end
    test "mismatched close" do assert (one_shot("{]") == "ERR:1") end
    test "bare close bracket" do assert (one_shot("]") == "ERR:0") end
    test "unclosed array truncates" do assert (one_shot("[1, 2") == "[|N(1.0)|N(2.0)|TRUNC:5") end
    test "unclosed object truncates" do assert (one_shot("{\"a\":") == "{|K(a)|TRUNC:5") end
    test "non-string key" do assert (one_shot("{1: 2}") == "{|ERR:1") end
  end

  describe "depth limit" do
    test "depth exactly at limit is fine" do
      let st = JsonStream.start_with(JsonStream.JsonLimits(3, 1000))
      match JsonStream.feed(st, "[[[1]]]") do
      Err(e) -> assert (false)
      Ok((evs, st2)) ->
        match JsonStream.finish(st2) do
        Err(e) -> assert (false)
        Ok(evs2) -> assert (evs_str(evs) ++ evs_str(evs2) == "[|[|[|N(1.0)|]|]|]|")
        end
      end
    end
    test "depth past limit errors at the opening bracket" do
      let st = JsonStream.start_with(JsonStream.JsonLimits(3, 1000))
      match JsonStream.feed(st, "[[[[1]]]]") do
      Err(e) -> assert (err_str(e) == "DEPTH:3")
      Ok(_) -> assert (false)
      end
    end
  end

  describe "ndjson" do
    test "three records" do
      let st = JsonStream.start_ndjson()
      match JsonStream.feed(st, "{\"a\":1}\n[2]\ntrue\n") do
      Err(e) -> assert (false)
      Ok((evs, st2)) ->
        match JsonStream.finish(st2) do
        Err(e) -> assert (false)
        Ok(evs2) -> assert (evs_str(evs) ++ evs_str(evs2) == "{|K(a)|N(1.0)|}|[|N(2.0)|]|T|")
        end
      end
    end
    test "record split across chunks" do
      let st = JsonStream.start_ndjson()
      match JsonStream.feed(st, "1\n2") do
      Err(e) -> assert (false)
      Ok((evs, st2)) ->
        match JsonStream.feed(st2, "3\n") do
        Err(e) -> assert (false)
        Ok((evs2, st3)) ->
          match JsonStream.finish(st3) do
          Err(e) -> assert (false)
          Ok(evs3) ->
            assert (evs_str(evs) ++ evs_str(evs2) ++ evs_str(evs3) == "N(1.0)|N(23.0)|")
          end
        end
      end
    end
    test "trailing bare number completes at finish" do
      let st = JsonStream.start_ndjson()
      match JsonStream.feed(st, "1\n2") do
      Err(e) -> assert (false)
      Ok((evs, st2)) ->
        match JsonStream.finish(st2) do
        Err(e) -> assert (false)
        Ok(evs2) -> assert (evs_str(evs) ++ evs_str(evs2) == "N(1.0)|N(2.0)|")
        end
      end
    end
    test "unterminated container still truncates" do
      let st = JsonStream.start_ndjson()
      match JsonStream.feed(st, "[1\n") do
      Err(e) -> assert (false)
      Ok((evs, st2)) ->
        match JsonStream.finish(st2) do
        Err(e) -> assert (err_str(e) == "TRUNC:3")
        Ok(_) -> assert (false)
        end
      end
    end
  end
```

Note the malformed-offset convention continues Task 1's: `[1,]` errors at
byte 3 (the `]` where a value was required), `{1: 2}` at byte 1 (the `1`
where a key was required). The ndjson "record split" test's expected
`N(23.0)` is deliberate: `"2"` then `"3\n"` is ONE number `23` — chunk
boundaries are invisible to token formation, which is exactly the property
under test.

- [ ] **Step 2: Run to verify the new tests fail**

```bash
./_build/default/bin/main.exe test test/stdlib/test_json_stream.march; echo "exit=$?"
```

Expected: container tests fail with the Task 1 "not yet supported" error;
Task 1 tests still pass.

- [ ] **Step 3: Implement containers**

In `stdlib/json_stream.march`, replace the two `value_start` stub branches:

```march
    else if c == 123 do
      open_container(s, i, true, cfg, mode, stack, depth, base, evs)
    else if c == 91 do
      open_container(s, i, false, cfg, mode, stack, depth, base, evs)
```

Replace `close_obj` and `close_arr` bodies and add `open_container`:

```march
  -- '{' or '[': push the parent mode; restore it via after_value on close.
  pfn open_container(s, i, is_obj, cfg, mode, stack, depth, base, evs) do
    match cfg do
    JsCfg(maxd, _, _) ->
      if depth + 1 > maxd do Err(EDepthLimit(base + i))
      else
        let ev = if is_obj do EvObjStart else EvArrStart end
        let m2 = if is_obj do MObjFirst else MArrFirst end
        go(s, i + 1, cfg, m2, Cons(mode, stack), depth + 1, PNone, base, Cons(ev, evs))
      end
    end
  end

  pfn close_obj(s, i, cfg, stack, depth, base, evs) do
    match stack do
    Nil -> Err(EMalformed("unmatched '}'", base + i))
    Cons(parent, rest) ->
      go(s, i + 1, cfg, after_value(cfg, parent), rest, depth - 1, PNone, base,
         Cons(EvObjEnd, evs))
    end
  end

  pfn close_arr(s, i, cfg, stack, depth, base, evs) do
    match stack do
    Nil -> Err(EMalformed("unmatched ']'", base + i))
    Cons(parent, rest) ->
      go(s, i + 1, cfg, after_value(cfg, parent), rest, depth - 1, PNone, base,
         Cons(EvArrEnd, evs))
    end
  end
```

(`after_value`'s ndjson branch already exists from Task 1; nothing else
changes for ndjson.)

- [ ] **Step 4: Run tests to verify they pass**

```bash
dune build --root . bin/main.exe 2>&1 | tail -3
./_build/default/bin/main.exe test test/stdlib/test_json_stream.march; echo "exit=$?"
```

Expected: PASS, `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add stdlib/json_stream.march test/stdlib/test_json_stream.march
git commit -m "feat(stdlib): JsonStream containers, depth limit, ndjson mode"
```

---

### Task 3: Totality harnesses — every-byte-split, truncation sweep, bombs

Pure test work; no module changes expected. If any harness finds a bug, fix
it in `stdlib/json_stream.march` in the same commit with a one-line note in
the commit body.

**Files:**
- Modify: `test/stdlib/test_json_stream.march`

**Interfaces:**
- Consumes: `one_shot`, `two_shot`, `evs_str`, `err_str` from Task 1.

- [ ] **Step 1: Write the harnesses (they should PASS immediately — they
  are property nets, not feature drivers)**

Append inside `describe "JsonStream" do`:

```march
  describe "every-byte-split differential" do
    -- For every document and every split point, two-chunk == one-shot.
    -- Exercises every suspension point in the state machine, and proves
    -- event boundaries are independent of chunk boundaries (the property
    -- phase 2's block scanning requires).
    test "all corpus documents at all split points" do
      let corpus = Cons("null",
                   Cons("true",
                   Cons("-12.5e-3",
                   Cons("\"hello\"",
                   Cons("\"a\\n\\u0041\\ud83d\\ude00 b\"",
                   Cons("[]",
                   Cons("{}",
                   Cons("[1, [2, [3, []]], \"x\"]",
                   Cons("{\"k\": {\"n\": [true, false, null]}, \"z\": -0.5}",
                   Cons("  [ 1 , { \"a\" : \"b\" } ]  ",
                   Nil))))))))))
      assert (split_all(corpus))
    end
  end
```

And these helpers before `describe "JsonStream" do` (module scope, beside
`one_shot`):

```march
pfn split_all(docs) do
  match docs do
  Nil -> true
  Cons(d, rest) ->
    if split_doc(d, 1, one_shot(d)) do split_all(rest) else false end
  end
end

pfn split_doc(d, k, expect) do
  if k >= string_byte_length(d) do true
  else
    if two_shot(d, k) == expect do split_doc(d, k + 1, expect)
    else do
      IO.puts("split mismatch: doc=" ++ d ++ " k=" ++ to_string(k)
              ++ " got=" ++ two_shot(d, k) ++ " want=" ++ expect)
      false
    end end
  end
end
```

```march
  describe "truncation sweep" do
    -- Every strict prefix of these documents is incomplete, so feed must
    -- succeed and finish must return ETruncated — never a crash, never Ok.
    -- (Bare-number docs are excluded on purpose: a prefix of "42" is a
    -- complete value.  That exclusion is reasoning, not laziness.)
    test "all strict prefixes truncate" do
      let corpus = Cons("\"hello world\"",
                   Cons("[1, [2, [3]]]",
                   Cons("{\"k\": [true, null]}",
                   Cons("\"esc \\u0041\\ud83d\\ude00\"",
                   Nil))))
      assert (trunc_all(corpus))
    end
  end

  describe "adversarial" do
    test "depth bomb errors fast, no crash" do
      -- 100k open brackets against max_depth 64.
      let bomb = repeat_str("[", 100000, "")
      let st = JsonStream.start_with(JsonStream.JsonLimits(64, 1000))
      match JsonStream.feed(st, bomb) do
      Err(e) -> assert (err_str(e) == "DEPTH:64")
      Ok(_) -> assert (false)
      end
    end
    test "token bomb errors fast, no crash" do
      -- An unterminated 100k-byte string against max_token_bytes 1024.
      let bomb = "\"" ++ repeat_str("a", 100000, "")
      let st = JsonStream.start_with(JsonStream.JsonLimits(64, 1024))
      match JsonStream.feed(st, bomb) do
      Err(e) -> assert (err_str(e) == "TOK:0")
      Ok(_) -> assert (false)
      end
    end
    test "single-byte chunks agree with one big chunk" do
      let doc = "{\"a\": [1, \"b\\n\", true]}"
      assert (drip(doc, 0, JsonStream.start(), "") == one_shot(doc))
    end
  end
```

With module-scope helpers:

```march
pfn trunc_all(docs) do
  match docs do
  Nil -> true
  Cons(d, rest) -> if trunc_doc(d, 1) do trunc_all(rest) else false end
  end
end

pfn trunc_doc(d, k) do
  if k >= string_byte_length(d) do true
  else
    let p = string_slice(d, 0, k)
    match JsonStream.feed(JsonStream.start(), p) do
    Err(_) -> do
      IO.puts("prefix rejected by feed (should hold state): " ++ p)
      false
    end
    Ok((_, st)) ->
      match JsonStream.finish(st) do
      Err(ETruncated(_)) -> trunc_doc(d, k + 1)
      Err(_) -> do
        IO.puts("prefix gave non-truncation error: " ++ p)
        false
      end
      Ok(_) -> do
        IO.puts("prefix wrongly accepted: " ++ p)
        false
      end
      end
    end
  end
end

pfn repeat_str(piece, n, acc) do
  if n <= 0 do acc else repeat_str(piece, n - 1, acc ++ piece) end
end

-- Feed one byte at a time, rendering events as we go.
pfn drip(d, i, st, out) do
  let n = string_byte_length(d)
  if i >= n do
    match JsonStream.finish(st) do
    Err(e) -> out ++ err_str(e)
    Ok(evs) -> out ++ evs_str(evs)
    end
  else
    match JsonStream.feed(st, string_slice(d, i, 1)) do
    Err(e) -> out ++ err_str(e)
    Ok((evs, st2)) -> drip(d, i + 1, st2, out ++ evs_str(evs))
    end
  end
end
```

Implementation note: `repeat_str` building 100k bytes by `++` is O(n²) in
copies — at 100KB that is ~5GB of memcpy, which the interpreter will feel.
If the depth/token bomb tests are slow (>2s each), shrink the bombs to
10,000 — the property (limit trips long before the input is consumed) is
size-independent.

- [ ] **Step 2: Run**

```bash
./_build/default/bin/main.exe test test/stdlib/test_json_stream.march; echo "exit=$?"
```

Expected: PASS. Any mismatch printed by `split_doc`/`trunc_doc` names the
document and split point — reproduce it as a dedicated `two_shot` test
first, then fix the state machine, then confirm the harness is green again.

- [ ] **Step 3: Also run the registered suite and the neighbors**

```bash
./_build/default/test/test_stdlib_march.exe test json_stream -e; echo "exit=$?"
./_build/default/test/test_stdlib_march.exe test json -e; echo "exit=$?"
```

Expected: both PASS (proves the new module didn't disturb `Json` via the
flat namespace).

- [ ] **Step 4: Commit**

```bash
git add test/stdlib/test_json_stream.march stdlib/json_stream.march
git commit -m "test(stdlib): JsonStream totality harnesses — split/truncation sweeps, bombs"
```

(Include `stdlib/json_stream.march` only if a harness-found fix touched it;
otherwise drop it from the add.)

---

### Task 4: Drivers, tree builder, differential vs Json.parse

**Files:**
- Modify: `stdlib/json_stream.march` (append `fold`, `build`, `each_value`,
  builder internals)
- Modify: `test/stdlib/test_json_stream.march`

**Interfaces:**
- Consumes: `feed`/`finish`/`start`/`start_ndjson`, `Event` ctors, and
  `Json.JsonValue` ctors (`Null`, `Bool`, `Number`, `Str`, `Array`,
  `Object` — payload of `Object` is `List((String, JsonValue))`).
- Produces: `fold(chunks, z, f)`, `build(chunks) : Result(JsonValue, JsonStreamError)`,
  `each_value(path, cb)`.

- [ ] **Step 0: Verify two signatures before writing code**

Read `stdlib/file.march` lines ~95–160 (`with_chunks`) and
`stdlib/seq.march` lines ~185–215 (`fold`). Confirm: `Seq.fold(seq, start, f)`
folds eagerly with `f(acc, item)`; `File.with_chunks(path, size, callback)`
passes the callback a `Seq(String)` and returns the callback's result (or a
file-error `Result` wrapping it). **If `with_chunks` wraps the return in
`Result`, adapt `each_value` below to `let?`/match through that wrapper** —
this is the one place this plan defers to the source because the wrapper
shape was not pinned at planning time. Everything else is fixed.

- [ ] **Step 1: Write the failing tests**

Append (helpers at module scope, tests inside the main describe):

```march
pfn chunks_of2(a, b) do
  Seq.from_list(Cons(a, Cons(b, Nil)))
end
```

```march
  describe "drivers" do
    test "fold counts events across chunks" do
      let r = JsonStream.fold(chunks_of2("[1, 2, ", "3]"), 0, fn (n, e) -> n + 1)
      match r do
      Err(_) -> assert (false)
      Ok(n) -> assert (n == 5)
      end
    end
    test "fold surfaces errors" do
      match JsonStream.fold(chunks_of2("[1, ", "x]"), 0, fn (n, e) -> n + 1) do
      Err(EMalformed(_, off)) -> assert (off == 4)
      _ -> assert (false)
      end
    end
    test "build reconstructs a tree equal to Json.parse" do
      let src = "{\"a\": [1, true, null], \"b\": \"x\"}"
      match JsonStream.build(chunks_of2(string_slice(src, 0, 9),
                                        string_slice(src, 9, string_byte_length(src) - 9))) do
      Err(_) -> assert (false)
      Ok(v) ->
        match Json.parse(src) do
        Ok(v2) -> assert (Json.to_string(v) == Json.to_string(v2))
        Err(_) -> assert (false)
        end
      end
    end
    test "differential verdicts vs Json.parse over the corpus" do
      -- \u documents INCLUDED: Json.parse gained \uXXXX + surrogate-pair
      -- support on main 2026-07-30, so escapes are differential-testable.
      let corpus = Cons("null", Cons("true", Cons("-12.5e-3",
                   Cons("\"a\\u0041\\ud83d\\ude00\"",
                   Cons("\"hello\"", Cons("[]", Cons("{}",
                   Cons("[1, [2, [3, []]], \"x\"]",
                   Cons("{\"k\": {\"n\": [true, false, null]}}",
                   Cons("xyz", Cons("[1,]", Cons("{\"a\" 1}", Cons("012",
                   Nil)))))))))))))
      assert (diff_all(corpus))
    end
  end
```

```march
pfn diff_all(docs) do
  match docs do
  Nil -> true
  Cons(d, rest) -> if diff_one(d) do diff_all(rest) else false end
  end
end

pfn diff_one(d) do
  let mine = JsonStream.build(Seq.from_list(Cons(d, Nil)))
  let theirs = Json.parse(d)
  match mine do
  Ok(v) ->
    match theirs do
    Ok(v2) ->
      if Json.to_string(v) == Json.to_string(v2) do true
      else do
        IO.puts("value mismatch on: " ++ d)
        false
      end end
    Err(_) -> do
      IO.puts("we accept, Json.parse rejects: " ++ d)
      false
    end
    end
  Err(_) ->
    match theirs do
    Err(_) -> true
    Ok(_) -> do
      IO.puts("we reject, Json.parse accepts: " ++ d)
      false
    end
    end
  end
end
```

- [ ] **Step 2: Run to verify they fail** (`fold`/`build` undefined)

```bash
dune build --root . bin/main.exe 2>&1 | tail -3
./_build/default/bin/main.exe test test/stdlib/test_json_stream.march; echo "exit=$?"
```

- [ ] **Step 3: Implement drivers and builder**

Append to `stdlib/json_stream.march` before the final `end`:

```march
  -- ── Drivers ───────────────────────────────────────────────────────────
  -- Seq.fold is eager and cannot early-exit, so after an error the
  -- remaining chunks are consumed but ignored (total either way).  If
  -- Seq's Step constructors prove publicly constructible, switching to
  -- Seq.fold_while for early exit is a drop-in improvement.

  fn fold(chunks, z, f) do
    let r = Seq.fold(chunks, Ok((z, start())), fn (acc, chunk) ->
      match acc do
      Err(e) -> Err(e)
      Ok((zz, st)) ->
        match feed(st, chunk) do
        Err(e) -> Err(e)
        Ok((evs, st2)) -> Ok((fold_evs(evs, zz, f), st2))
        end
      end)
    match r do
    Err(e) -> Err(e)
    Ok((zz, st)) ->
      match finish(st) do
      Err(e) -> Err(e)
      Ok(evs) -> Ok(fold_evs(evs, zz, f))
      end
    end
  end

  pfn fold_evs(evs, z, f) do
    match evs do
    Nil -> z
    Cons(e, t) -> fold_evs(t, f(z, e), f)
    end
  end

  -- ── Tree builder (compatibility with Json.JsonValue) ─────────────────
  -- Builder frames: an open array (reversed elements), an open object
  -- awaiting a key (reversed pairs), an open object holding a key awaiting
  -- its value.

  ptype JsFrame =
      FArr(List(JsonValue))
    | FObjK(List((String, JsonValue)))
    | FObjV(String, List((String, JsonValue)))

  -- A completed value lands in the enclosing frame — or, with no frames,
  -- IS a completed top-level value.
  pfn bpush(frames, v) do
    match frames do
    Nil -> Ok((Nil, Some(v)))
    Cons(FArr(xs), rest) -> Ok((Cons(FArr(Cons(v, xs)), rest), None))
    Cons(FObjV(k, ps), rest) -> Ok((Cons(FObjK(Cons((k, v), ps)), rest), None))
    Cons(FObjK(ps), rest) -> Err(EMalformed("internal: value before key", 0))
    end
  end

  pfn build_step(frames, ev) do
    match ev do
    EvNull -> bpush(frames, Null)
    EvBool(b) -> bpush(frames, Bool(b))
    EvNum(f) -> bpush(frames, Number(f))
    EvStr(sv) -> bpush(frames, Str(sv))
    EvKey(k) ->
      match frames do
      Cons(FObjK(ps), rest) -> Ok((Cons(FObjV(k, ps), rest), None))
      _ -> Err(EMalformed("internal: key outside object", 0))
      end
    EvObjStart -> Ok((Cons(FObjK(Nil), frames), None))
    EvArrStart -> Ok((Cons(FArr(Nil), frames), None))
    EvArrEnd ->
      match frames do
      Cons(FArr(xs), rest) -> bpush(rest, Array(rev(xs, Nil)))
      _ -> Err(EMalformed("internal: mismatched array end", 0))
      end
    EvObjEnd ->
      match frames do
      Cons(FObjK(ps), rest) -> bpush(rest, Object(rev(ps, Nil)))
      _ -> Err(EMalformed("internal: mismatched object end", 0))
      end
    end
  end

  -- Fold a whole single-document chunk stream into one JsonValue.
  fn build(chunks) do
    let r = fold(chunks, Ok((Nil, None)), fn (acc, ev) ->
      match acc do
      Err(e) -> Err(e)
      Ok((frames, done)) ->
        match build_step(frames, ev) do
        Err(e) -> Err(e)
        Ok((frames2, out)) ->
          match out do
          Some(v) -> Ok((frames2, Some(v)))
          None -> Ok((frames2, done))
          end
        end
      end)
    match r do
    Err(e) -> Err(e)
    Ok(inner) ->
      match inner do
      Err(e) -> Err(e)
      Ok((frames, done)) ->
        match done do
        Some(v) -> Ok(v)
        None -> Err(ETruncated(0))
        end
      end
    end
  end

  -- NDJSON: parse `path`, calling cb(JsonValue) per completed top-level
  -- value, with bounded memory.  Adapt the with_chunks wrapper per its
  -- actual signature (Task 4 Step 0).
  fn each_value(path, cb) do
    File.with_chunks(path, 65536, fn chunks ->
      ndjson_run(chunks, cb))
  end

  pfn ndjson_run(chunks, cb) do
    let r0 = Seq.fold(chunks, nd_init(), fn (acc, chunk) -> nd_chunk(acc, chunk, cb))
    match r0 do
    Err(e) -> Err(e)
    Ok((st, frames)) ->
      match finish(st) do
      Err(e) -> Err(e)
      Ok(evs) ->
        match nd_events(evs, frames, cb) do
        Err(e) -> Err(e)
        Ok(_) -> Ok(())
        end
      end
    end
  end

  pfn nd_init() do Ok((start_ndjson(), Nil)) end

  pfn nd_chunk(acc, chunk, cb) do
    match acc do
    Err(e) -> Err(e)
    Ok((st, frames)) ->
      match feed(st, chunk) do
      Err(e) -> Err(e)
      Ok((evs, st2)) ->
        match nd_events(evs, frames, cb) do
        Err(e) -> Err(e)
        Ok(frames2) -> Ok((st2, frames2))
        end
      end
    end
  end

  pfn nd_events(evs, frames, cb) do
    match evs do
    Nil -> Ok(frames)
    Cons(ev, t) ->
      match build_step(frames, ev) do
      Err(e) -> Err(e)
      Ok((frames2, out)) ->
        match out do
        Some(v) -> do
          cb(v)
          nd_events(t, frames2, cb)
        end
        None -> nd_events(t, frames2, cb)
        end
      end
    end
  end
```

Type note: `build`'s accumulator nests `Result` inside `fold`'s `Result` —
the outer from the tokenizer, the inner from the builder — hence the
two-layer match at its end. It is deliberate, not an accident to "clean up":
flattening them loses which stage failed.

- [ ] **Step 4: Add an `each_value` test** (uses a real temp file, mirroring
  `test_csv.march`'s pattern):

```march
    test "each_value over an ndjson file" do
      let path = "/tmp/march_jsonstream_ndjson_test.jsonl"
      match File.write(path, "{\"n\": 1}\n{\"n\": 2}\n{\"n\": 3}\n") do
      Err(_) -> assert (false)
      Ok(_) -> do
        let count = Ref.make(0)
        match JsonStream.each_value(path, fn v -> Ref.set(count, Ref.get(count) + 1)) do
        Err(_) -> assert (false)
        Ok(_) -> assert (Ref.get(count) == 3)
        end
      end
      end
      match File.delete(path) do _ -> () end
    end
```

If `Ref` is not a stdlib module (check `ls stdlib | grep -i ref` — if
absent), count via an accumulating driver instead: replace the test body
with a `JsonStream.fold`-based count over `File.read(path)` split as one
chunk, and keep `each_value` covered by asserting it returns `Ok(())` on
the file and `Err` on a malformed one.

- [ ] **Step 5: Run tests to verify they pass**

```bash
dune build --root . bin/main.exe 2>&1 | tail -3
./_build/default/bin/main.exe test test/stdlib/test_json_stream.march; echo "exit=$?"
```

- [ ] **Step 6: Commit**

```bash
git add stdlib/json_stream.march test/stdlib/test_json_stream.march
git commit -m "feat(stdlib): JsonStream drivers — fold, build, ndjson each_value"
```

---

### Task 5: Benchmark, compiled parity, docs

**Files:**
- Create: `bench/json_stream.march`
- Modify: `specs/benchmarks.md`, `specs/todos.md`, `specs/progress.md`,
  `CHANGELOG.md`

- [ ] **Step 1: Write the benchmark**

`bench/json_stream.march`:

```march
-- JsonStream throughput: synthetic NDJSON, fed in 64KB chunks.
-- Expected output: checksum=200000 then a ms figure (timing line varies).

mod JsonStreamBench do

pfn build_records(n, acc) do
  if n <= 0 do acc
  else
    build_records(n - 1,
      Cons("{\"id\": " ++ to_string(n) ++ ", \"name\": \"user-" ++ to_string(n)
           ++ "\", \"active\": true, \"tags\": [1, 2, 3]}\n", acc))
  end
end

pfn count_events(chunks) do
  match JsonStream.fold(chunks, 0, fn (n, e) -> n + 1) do
  Err(_) -> 0 - 1
  Ok(n) -> n
  end
end

fn main() do
  let n = 20000
  let src = string_join(build_records(n, Nil), "")
  let t0 = System.monotonic_time()
  -- NDJSON needs the ndjson tokenizer: fold() is single-doc, so count via
  -- an explicit feed loop over slices.
  let total = run_chunked(src, 0, JsonStream.start_ndjson(), 0)
  let t1 = System.monotonic_time()
  println("checksum=" ++ to_string(total))
  println("ms=" ++ to_string((t1 - t0) / 1000000))
end

pfn run_chunked(src, off, st, n) do
  let sz = string_byte_length(src)
  if off >= sz do
    match JsonStream.finish(st) do
    Err(_) -> 0 - 1
    Ok(evs) -> n + count_list(evs)
    end
  else
    let take = if sz - off < 65536 do sz - off else 65536 end
    match JsonStream.feed(st, string_slice(src, off, take)) do
    Err(_) -> 0 - 1
    Ok((evs, st2)) -> run_chunked(src, off + take, st2, n + count_list(evs))
    end
  end
end

pfn count_list(evs) do
  match evs do
  Nil -> 0
  Cons(_, t) -> count_list(t) + 1
  end
end

end
```

Each record emits 10 events (ObjStart, 4 keys, 4 scalars... precisely:
`{` K id N K name S K active T K tags `[` N N N `]` `}` = 13 events), so
checksum = 20000 × 13 = 260000. **Compute the real figure from a 2-record
run first and fix both this comment and the expected checksum before
recording the baseline** — do not trust arithmetic done in prose, including
this prose.

- [ ] **Step 2: Compile and run — compiled, never interpreted**

```bash
dune build --root . bin/main.exe && dune build --root . @install 2>&1 | tail -2
rm -rf .march/cas/artifacts-v2
./_build/default/bin/main.exe --compile --opt 2 bench/json_stream.march -o /tmp/json_stream_bench_cg858 > /tmp/json_stream_compile_cg858.log 2>&1; echo "compile=$?"
/tmp/json_stream_bench_cg858; echo "run=$?"
```

(`@install` restages the stdlib so the compiled run sees `json_stream.march`
— a targeted `bin/main.exe` build does NOT. The /tmp names carry the
worktree suffix deliberately.)

Expected: the same checksum as the interpreted run of the same `main`
(check interpreted parity first on n=200 — full n interpreted may be slow):

```bash
./_build/default/bin/main.exe bench/json_stream.march
```

A compiled-vs-interpreted checksum mismatch is a compiler bug (this repo has
a history of exactly that class); stop and characterize it rather than
shipping the benchmark.

Record the compiled ms figure and `/usr/bin/time -l` MaxRSS:

```bash
/usr/bin/time -l /tmp/json_stream_bench_cg858 2>&1 | grep -E "maximum resident|ms="
```

- [ ] **Step 3: Add the benchmarks.md entry**

Append to `specs/benchmarks.md` before the "Running benchmarks to validate
changes" section, following the house format: feature table
(`JsonStream.feed` per-byte loop / event allocation / RC churn on pieces),
expected checksum, the measured baseline ms + MaxRSS, and a What-to-watch
noting (a) this is the phase 1 pure-March baseline that phase 2's SIMD spec
must beat, (b) RSS should stay flat if record count grows at fixed chunk
size — that is the constant-memory claim, spot-check it by 10×ing n and
confirming MaxRSS moves by the src-string size only (the benchmark holds
the whole INPUT in memory by construction; only parser-side memory is under
test). Add a row to the "Changed area → benchmark" table:
`JsonStream / streaming JSON | json_stream`.

- [ ] **Step 4: Full-suite + docs-lint gate**

```bash
scripts/run-tests.sh 2>&1 | tail -6
bash scripts/check-docs.sh 2>&1 | tail -6
```

Expected: suites green except known environmental failures
(`MARCH_SANITIZE` timeout); check-docs green — the stdlib count check
recomputes from `find stdlib`, so any doc stating "111 stdlib modules" (a
now-stale count; the tree grew) will flag and must be bumped to the new
actual, or already carries `doc-lint:ignore-count`.

- [ ] **Step 5: Update the canonical docs — same commit as the benchmark**

- `specs/todos.md`: add a Done-section entry for JsonStream phase 1;
  add an open item: "JsonStream phase 2 — SIMD structural scanning behind
  the phase-1 interface; write spec seeded with the json_stream benchmark
  baseline (see specs/2026-07-30-json-streaming-design.md)". Also note the
  deferred decoder-combinator layer (design Component 4).
- `specs/progress.md`: new dated Current State entry — test-count deltas,
  the module, the totality-harness approach (every-byte-split), the
  benchmark baseline numbers.
- `CHANGELOG.md` under `## [Unreleased]` / `### Added`:
  `JsonStream — streaming JSON tokenizer: resumable chunk-fed parsing with
  bounded memory, depth/token limits, ndjson mode, and typed errors with
  absolute byte offsets.`
- `specs/2026-07-30-json-streaming-design.md`: flip **Status** to
  "phase 1 implemented" and record any decision-table deviations found
  during implementation.

- [ ] **Step 6: Commit**

```bash
git add bench/json_stream.march specs/benchmarks.md specs/todos.md specs/progress.md CHANGELOG.md specs/2026-07-30-json-streaming-design.md
git commit -m "bench+docs: JsonStream phase 1 baseline, spec status, changelog"
```

---

## Self-review

**Spec coverage:** tokenizer API/semantics/decision table → Tasks 1–2;
every-byte-split, truncation sweep, adversarial, differential-vs-Json.parse,
parity → Tasks 3–5; drivers/builder → Task 4; benchmark + docs → Task 5.
Deliberately NOT covered, with spec's blessing: the decoder layer (Component
4, "separable — nothing in Components 1–3 depends on it") and an automated
RSS assertion (replaced by the benchmark's measured MaxRSS + 10× spot-check;
the spec's `march_live_allocs` idea assumed a March-level hook that was not
confirmed to exist — softened deliberately, recorded here).

**Known deferred-to-source points (exactly two):** the `File.with_chunks`
return-wrapper shape (Task 4 Step 0 pins the verification step) and the
benchmark's per-record event count (Task 5 Step 1 requires computing it
empirically before recording the baseline).

**Type consistency:** `feed : (JsState, String) -> Result((List(Event),
JsState), JsonStreamError)` and `finish : JsState -> Result(List(Event),
JsonStreamError)` are used identically in Tasks 1–5; `JsonLimits(depth,
token_bytes)` argument order is depth-first at every construction site;
builder `bpush`/`build_step` signatures match between definition (Task 4)
and use (Task 4 only).

**Offset conventions** (the likeliest test-vs-impl friction): byte-level
errors report the offending byte; number-shape errors report token start;
`ETruncated` reports the open token's start (partial in flight) or the
current offset (structural incompleteness). Task 1/2 test expectations
encode these; the escape hatch (deterministic ±1 with a commit note) is
stated in Task 1 Step 2.
