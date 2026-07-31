# Typed JSON Decoding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn JSON — including multi-GB NDJSON — into the caller's own types,
with errors that name *which field of which record* failed, without ever
holding more than one record in memory. Design:
`specs/2026-07-31-json-typed-decoding-design.md`.

**Architecture:** Build on the existing `derive Json`
(`lib/desugar/desugar.ml:1479`) rather than a from-scratch combinator library.
Phase A restructures the generated decoder to report a JSONPath and wires it
to `JsonStream`. Phase B generates a *second*, event-consuming decoder per
type so records never become trees, with Phase A's tree decoder as its
differential oracle.

**Tech Stack:** OCaml AST generation in `lib/desugar/desugar.ml`; March stdlib
(`stdlib/json.march`, `stdlib/json_stream.march`); alcotest via
`test/test_stdlib_march.ml`; March test files under `test/stdlib/`.

## Ecosystem prior art — and the four decisions it settles

This problem is unusually well-trodden. Four decisions below are taken from
consensus rather than invented, and one cautionary tale drives the sequencing.

| Ecosystem | Error location | Streaming | Unknown fields |
|---|---|---|---|
| **serde** (Rust) | position (line/col); **semantic path only via the separate `serde_path_to_error` crate** | derive generates a `Visitor` state machine over tokens | ignored by default; `deny_unknown_fields` opt-in |
| **aeson** (Haskell) | `JSONPath = [Key Text \| Index Int]`, rendered `$.users[3].id` | — | ignored by default |
| **Elm** `Json.Decode` | recursive `Field String Error \| Index Int Error \| OneOf [Error] \| Failure` | — | ignored |
| **Go** `encoding/json` | `UnmarshalTypeError{Field, Offset, Struct, Type}` — **path *and* byte offset** | `Decoder.Decode()` per value; `Token()` | ignored; `DisallowUnknownFields()` opt-in |
| **Jackson** (Java) | `Reference` chain (field/index) | **databind is built *on* the streaming `JsonParser`** | ignored; opt-in strict |

**Decision 1 — path shape: a flat `List` of steps, rendered JSONPath-style
(`$.users[3].id`).** This follows aeson and Jackson. Elm's *recursive* error
exists to support `oneOf`, which reports several failed branches at one
position; we are not building combinators, so a flat list carries the same
information at less cost. Recorded so a future `oneOf` knows it must revisit
this.

**Decision 2 — unknown fields are ignored by default.** Unanimous across
serde, Go, Jackson, aeson. A strict mode is a later opt-in, not a default:
defaulting to strict breaks every caller whose producer adds a field.

**Decision 3 — carry a byte offset *alongside* the path**, per Go's
`UnmarshalTypeError`. Path alone identifies the field but not *which record*
in a 40,000-record file; JsonStream already knows the offset, so not carrying
it would be discarding information we already have.

**Decision 4 — Phase B follows serde's generated-visitor shape**: a generated
field dispatcher, `Option` slots filled as keys arrive in whatever order, and
a required-field check when the object closes. JSON objects are unordered, so
opportunistic slot-filling is the only correct approach. Jackson and Go both
build their object mapper on a token stream, which is the same architecture.

**The cautionary tale that fixes the order:** serde's core errors carry
position but *not* semantic path — `serde_path_to_error` is a separate crate
that wraps a deserializer after the fact, and it exists precisely because
retrofitting paths onto a decoder that was not designed for them is painful.
**A2 must land before B**, so the event decoder is generated with paths from
the start rather than growing its own bolt-on later.

## Two findings from reading the current codegen

Both change what the work is, and both were confirmed by reading the source:

1. **The generated record decoder is a single all-or-nothing tuple match** —
   `| (Some(Str(f1)), Some(Number(f2)), ...) -> Ok({...}) | _ -> Err("invalid JSON for TypeName")`
   (`lib/desugar/desugar.ml`, the `TDRecord` branch of the `from_json`
   generator). A path cannot be attached to a wildcard arm, so A2 is a
   **restructuring into per-field checks**, not a tweak. This is the single
   largest piece of work in the plan.
2. **`derive Json`'s blast radius is three test files.** `grep -rl "derive Json"`
   over `stdlib/ test/ examples/` returns only
   `test/stdlib/test_derive_json.march`, `test_derive_json_multi.march`, and
   `test_island_bridges.march`; no stdlib or example code consumes the derived
   `from_json` (`DataFrame.from_json_string` is unrelated hand-written code).
   So **changing the error type outright is nearly free** — this settles the
   design's open question 2 in favour of one entry point rather than adding a
   parallel `from_json_at`.

## Global Constraints

- Build **in this worktree** with `--root .`. Never `eval $(opam env ...)`;
  never a bare targetless `dune build --root .` (it wedges — name targets).
  **NEVER `git stash`** (the stash stack is shared across worktrees and
  already holds other sessions' entries).
- Stage files explicitly by name; no `git add -A`/`.`; no Co-Authored-By.
- **New constructors must be prefixed and collision-checked.** The
  type/constructor namespace is FLAT across modules and this has caused real
  compiled-only miscompiles. `grep` before introducing any name (Task 2 Step
  1 does this).
- **`JsonStream`'s tokenizer and public API are frozen.** Phases 1-2
  guarantees are hard constraints: totality, `cap no_panic`, bounded memory,
  and event boundaries independent of chunk boundaries. Its every-byte-split
  differential must keep passing untouched.
- March syntax traps: `init` and `doc` are reserved; `else` is mandatory and
  every `else if` needs its own `end`; write `0 - 1` not a bare `-1`; lambdas
  are `fn x -> body`; `string_slice(s, start, LEN)` takes a length.
- OCaml side: `dune build --root . bin/main.exe`. Desugar changes affect every
  March program — run the compiler suite, not just the JSON tests.
- Test commands (judge by exit code):
  - `./_build/default/bin/main.exe test test/stdlib/<file>.march`
  - `dune build --root . test/test_stdlib_march.exe && ./_build/default/test/test_stdlib_march.exe test <group> -e`
  - `./_build/default/test/run_compiler.exe -e` after any `desugar.ml` change.
- Compiled runs need `dune build --root . @install` first (stale staged-stdlib
  trap). Never pipe `march --compile` output; redirect and check `$?`.
- The machine is shared and often heavily loaded; suite failures should be
  re-run alone before being believed. `adversarial-regressions` #39
  (`MARCH_SANITIZE` timeout) is a known environmental failure — confirm by
  compiling a trivial `clang -fsanitize=address` C program, which also hangs.

## File Structure

- `stdlib/json.march` — the `DecodeError` type, its path steps, and the
  renderer. Lives here because generated code already references `Json.*`.
- `lib/desugar/desugar.ml` — the `from_json` generator (A2), and the new
  `from_json_events` generator (B).
- `stdlib/json_stream.march` — `each_typed` driver carrying byte offsets (A3).
- `test/stdlib/test_derive_json.march`, `test_derive_json_multi.march`,
  `test_island_bridges.march` — existing callers, migrated in A2.
- `test/stdlib/test_json_typed.march` — new: wiring, paths, offsets, oracle.

---

### Task 1: Map what `derive Json` actually supports, and prove the wiring

Discovery plus an end-to-end proof. Produces the capability table that scopes
every later task — in particular, whether Phase B must handle `Option`,
`List`, and type parameters.

**Files:**
- Create: `test/stdlib/test_json_typed.march`
- Modify: `test/test_stdlib_march.ml` (register the new suite)
- Create: `specs/2026-07-31-derive-json-capability-map.md`

**Interfaces:**
- Produces: the capability map consumed by Tasks 2-6; a working
  `JsonStream` + `from_json` example that later tasks extend.

- [ ] **Step 1: Write the capability probe**

Create `test/stdlib/test_json_typed.march`. Each probe is a separate test so
one failure does not mask the rest — the point is a *map*, not a pass/fail:

```march
-- Capability probe + wiring proof for `derive Json` x JsonStream.
-- Run: dune exec march -- test test/stdlib/test_json_typed.march
-- Design: specs/2026-07-31-json-typed-decoding-design.md

mod TestJsonTyped do

  type Flat = { name : String, age : Int, active : Bool, score : Float }
  derive Json for Flat

  type Inner = { id : Int }
  derive Json for Inner
  type Outer = { label : String, inner : Inner }
  derive Json for Outer

  type Tag = Red | Green
  derive Json for Tag

  type Shape = Circle(Int) | Rect(Int, Int)
  derive Json for Shape

  pfn parse_flat(s) do
    match Json.parse(s) do
    Err(e) -> Err("parse: " ++ e)
    Ok(v) -> match from_json(v) do
      Err(e) -> Err("decode: " ++ to_string(e))
      Ok(x) -> Ok(x)
      end
    end
  end

  describe "derive Json capability map" do

    test "flat record round-trips" do
      match parse_flat("{\"name\":\"a\",\"age\":3,\"active\":true,\"score\":1.5}") do
      Ok(r) -> assert (r.name == "a" && r.age == 3)
      Err(e) -> do IO.puts("FLAT: " ++ e) assert (false) end
      end
    end

    test "nested record round-trips" do
      match Json.parse("{\"label\":\"x\",\"inner\":{\"id\":7}}") do
      Ok(v) -> match from_json(v) do
        Ok(o) -> assert (o.inner.id == 7)
        Err(e) -> do IO.puts("NESTED: " ++ to_string(e)) assert (false) end
        end
      Err(_) -> assert (false)
      end
    end

    test "missing field is an error, not a crash" do
      match parse_flat("{\"name\":\"a\",\"age\":3}") do
      Ok(_) -> assert (false)
      Err(e) -> do IO.puts("MISSING-FIELD MSG: " ++ e) assert (true) end
      end
    end

    test "wrong field type is an error, not a crash" do
      match parse_flat("{\"name\":1,\"age\":3,\"active\":true,\"score\":1.5}") do
      Ok(_) -> assert (false)
      Err(e) -> do IO.puts("WRONG-TYPE MSG: " ++ e) assert (true) end
      end
    end

    test "unknown extra field" do
      match parse_flat("{\"name\":\"a\",\"age\":3,\"active\":true,\"score\":1.5,\"zzz\":9}") do
      Ok(_) -> IO.puts("UNKNOWN-FIELD: ignored (accepted)")
      Err(e) -> IO.puts("UNKNOWN-FIELD: rejected -- " ++ e)
      end
      assert (true)
    end

  end

end
```

**These probes are deliberately non-judgmental**: the unknown-field test
asserts `true` either way and *prints* what happened, because we are
discovering the current behaviour, not asserting a desired one. Decision 2
sets the target (ignore by default) — Task 2 makes it so if it is not
already.

- [ ] **Step 2: Probe the uncertain capabilities separately**

Add a second `describe` block covering the three the design flagged as
unknown. **Write each in its own test and expect that some may fail to
compile.** If a `derive Json` on one of these is a *compile* error, delete
that probe, record it in the map as unsupported, and move on — a
non-compiling test file blocks everything.

```march
  describe "derive Json uncertain capabilities" do
    -- Option(T), List(T), and a type parameter. If any of these fails to
    -- COMPILE, remove it and record "unsupported" in the capability map --
    -- that is a finding, not a blocker.
    test "Option field" do
      -- type WithOpt = { a : Int, b : Option(Int) }  derive Json for WithOpt
      assert (true)
    end
    test "List field" do
      -- type WithList = { xs : List(Int) }  derive Json for WithList
      assert (true)
    end
  end
```

Uncomment the type declarations one at a time at module scope, build, and
record what happens. This is exploratory by design; the deliverable is the
recorded answer.

- [ ] **Step 3: Register and run**

In `test/test_stdlib_march.ml`, after the `("json_stream", [...])` block:

```ocaml
    ("json_typed", [
      Alcotest.test_case "derive Json x JsonStream typed decoding"
        `Quick (run_stdlib_test "test_json_typed.march" "TestJsonTyped");
    ]);
```

**Note the two-exe trap**: registering here is necessary but check whether
`all_stdlib_decls` in the same file also needs the module, as
`test_json_stream` did.

```bash
dune build --root . bin/main.exe 2>&1 | tail -3
./_build/default/bin/main.exe test test/stdlib/test_json_typed.march; echo "exit=$?"
```

- [ ] **Step 4: Prove the streaming wiring end to end**

Add a third `describe` demonstrating the headline use case — NDJSON file →
typed records, plus one malformed record:

```march
  describe "JsonStream x derive Json" do
    test "ndjson file decodes to typed records" do
      let path = "/tmp/march_json_typed_test.jsonl"
      match File.write(path, "{\"id\":1}\n{\"id\":2}\n{\"id\":3}\n") do
      Err(_) -> assert (false)
      Ok(_) -> do
        let r = JsonStream.fold(Seq.from_list(Cons(File.read(path), Nil)), 0,
                                fn (n, e) -> n + 1)
        match r do
        Ok(_) -> assert (true)
        Err(_) -> assert (false)
        end
      end
      end
      match File.delete(path) do _ -> () end
    end
  end
```

**Adapt this to whatever `File.read` actually returns** (it is a `Result`)
— read `stdlib/file.march` first. The goal is a demonstrated path from a file
to typed values via `each_value` + `from_json`; if `each_value`'s callback
shape makes that awkward, record *that* as a finding, because it is exactly
the ergonomics problem this plan exists to fix.

- [ ] **Step 5: Write the capability map**

Create `specs/2026-07-31-derive-json-capability-map.md`: a table of
{flat record, nested record, enum, variant-with-args, `Option`, `List`, type
parameter, missing field, wrong type, unknown field, duplicate key} × {works /
fails / unsupported}, each with the observed message. Then a short section:
**what Phase B must therefore handle**.

- [ ] **Step 6: Commit**

```bash
git add test/stdlib/test_json_typed.march test/test_stdlib_march.ml specs/2026-07-31-derive-json-capability-map.md
git commit -m "test(stdlib): map derive Json capabilities and prove the JsonStream wiring"
```

---

### Task 2: `DecodeError` — the type, the renderer, and its tests

Stdlib-only. Defines the contract every later task emits, with no codegen
change yet, so the type can be reviewed on its own.

**Files:**
- Modify: `stdlib/json.march`
- Modify: `test/stdlib/test_json_typed.march`

**Interfaces:**
- Produces: `Json.DecodeError`, `Json.JPathField`/`Json.JPathIndex`,
  `Json.decode_error_to_string`, `Json.decode_error_at` — consumed by Tasks
  3-6.

- [ ] **Step 1: Collision grep — must be empty**

```bash
grep -rn "JPathField\|JPathIndex\|DecodeError\|decode_error_to_string\|decode_error_at\|JsonPathStep" stdlib/ lib/ bin/ test/ | grep -v Binary
```

Any hit → rename with the same prefix discipline and update every later task.

- [ ] **Step 2: Write the failing tests**

Append to `test/stdlib/test_json_typed.march`:

```march
  describe "DecodeError rendering" do
    test "bare message renders with the root path" do
      let e = Json.DecodeError("expected Int", Nil, 0 - 1)
      assert (Json.decode_error_to_string(e) == "$: expected Int")
    end
    test "field path renders JSONPath-style" do
      let e = Json.DecodeError("expected Int",
                Cons(Json.JPathField("id"), Nil), 0 - 1)
      assert (Json.decode_error_to_string(e) == "$.id: expected Int")
    end
    test "nested field and index render in order" do
      -- $.users[3].id -- steps are stored outermost-first.
      let p = Cons(Json.JPathField("users"),
              Cons(Json.JPathIndex(3),
              Cons(Json.JPathField("id"), Nil)))
      let e = Json.DecodeError("expected Int", p, 0 - 1)
      assert (Json.decode_error_to_string(e) == "$.users[3].id: expected Int")
    end
    test "byte offset is included when present" do
      let e = Json.DecodeError("expected Int", Cons(Json.JPathField("id"), Nil), 4096)
      assert (Json.decode_error_to_string(e) == "$.id (byte 4096): expected Int")
    end
    test "prepending a step builds the path outermost-first" do
      let inner = Json.DecodeError("expected Int", Cons(Json.JPathField("id"), Nil), 0 - 1)
      let outer = Json.decode_error_under(Json.JPathField("user"), inner)
      assert (Json.decode_error_to_string(outer) == "$.user.id: expected Int")
    end
  end
```

- [ ] **Step 3: Run to verify they fail**

```bash
dune build --root . bin/main.exe 2>&1 | tail -3
./_build/default/bin/main.exe test test/stdlib/test_json_typed.march; echo "exit=$?"
```

Expected: failures naming `Json.DecodeError` as unknown.

- [ ] **Step 4: Implement in `stdlib/json.march`**

Add near the top of `mod Json`, beside `JsonValue`:

```march
  -- One step of a JSONPath. Steps are stored OUTERMOST-FIRST, so a decoder
  -- descending into a field prepends -- see decode_error_under.
  type JsonPathStep = JPathField(String) | JPathIndex(Int)

  -- A typed decoding failure: what was wrong, where in the document
  -- structure, and (when known) the absolute byte offset of the record it
  -- came from. The offset is 0 - 1 when unknown -- decoding a value already
  -- in memory has no byte position.
  --
  -- Path shape follows aeson and Jackson: a flat list of steps rendered
  -- JSONPath-style. Elm's recursive error tree exists to support `oneOf`,
  -- which reports several failed branches at one position; with no
  -- combinator layer a flat list carries the same information for less.
  -- Revisit if `oneOf` is ever added.
  type DecodeError = DecodeError(String, List(JsonPathStep), Int)

  doc "Push `step` onto the front of a DecodeError's path, as a decoder does when it descends."
  fn decode_error_under(step, e) do
    match e do
    DecodeError(msg, path, off) -> DecodeError(msg, Cons(step, path), off)
    end
  end

  doc "Attach an absolute byte offset to a DecodeError."
  fn decode_error_at(off, e) do
    match e do
    DecodeError(msg, path, _) -> DecodeError(msg, path, off)
    end
  end

  pfn render_path(steps, acc) do
    match steps do
    Nil -> acc
    Cons(JPathField(f), t) -> render_path(t, acc ++ "." ++ f)
    Cons(JPathIndex(i), t) -> render_path(t, acc ++ "[" ++ to_string(i) ++ "]")
    end
  end

  doc """
  Render a `DecodeError` as `$.users[3].id: expected Int`, with the byte
  offset when known: `$.id (byte 4096): expected Int`.
  """
  fn decode_error_to_string(e) do
    match e do
    DecodeError(msg, path, off) -> do
      let p = render_path(path, "$")
      if off < 0 do p ++ ": " ++ msg
      else p ++ " (byte " ++ to_string(off) ++ "): " ++ msg end
    end
    end
  end
```

- [ ] **Step 5: Run to green**

```bash
dune build --root . bin/main.exe @install 2>&1 | tail -3
./_build/default/bin/main.exe test test/stdlib/test_json_typed.march; echo "exit=$?"
./_build/default/bin/main.exe test test/stdlib/test_json.march; echo "exit=$?"
```

- [ ] **Step 6: Commit**

```bash
git add stdlib/json.march test/stdlib/test_json_typed.march
git commit -m "feat(stdlib): Json.DecodeError with a JSONPath and an optional byte offset"
```

---

### Task 3: Restructure the generated record decoder to report paths

The largest task. The current generator emits one tuple match with a wildcard
failure arm, which cannot carry a path; this replaces it with per-field
checks.

**Files:**
- Modify: `lib/desugar/desugar.ml` (the `TDRecord` branch of the `from_json`
  generator)
- Modify: `test/stdlib/test_json_typed.march`
- Modify: `test/stdlib/test_derive_json.march`, `test_derive_json_multi.march`,
  `test_island_bridges.march` (error-type migration — these are the only
  three consumers)

**Interfaces:**
- Consumes: `Json.DecodeError` etc. from Task 2.
- Produces: `from_json(v) : Result(T, Json.DecodeError)` for record types.

- [ ] **Step 1: Read the generator before changing it**

Read `lib/desugar/desugar.ml` from the `derive Json` comment (~line 1479)
through the end of the `from_json` generation, and write down in the report:
the exact function that builds the `TDRecord` decoder, how it names
variables, how it currently constructs `Err`, and where the variant/enum cases
are built. **Do not begin editing before this is written down** — this is
AST-construction code where a wrong assumption produces a confusing type error
far from its cause.

- [ ] **Step 2: Write the failing tests**

```march
  describe "record decode errors carry a path" do
    test "wrong scalar type names the field" do
      match Json.parse("{\"name\":1,\"age\":3,\"active\":true,\"score\":1.5}") do
      Ok(v) -> match from_json(v) do
        Ok(_) -> assert (false)
        Err(e) -> assert (Json.decode_error_to_string(e) == "$.name: expected String")
        end
      Err(_) -> assert (false)
      end
    end
    test "missing field names the field" do
      match Json.parse("{\"name\":\"a\",\"active\":true,\"score\":1.5}") do
      Ok(v) -> match from_json(v) do
        Ok(_) -> assert (false)
        Err(e) -> assert (Json.decode_error_to_string(e) == "$.age: missing field")
        end
      Err(_) -> assert (false)
      end
    end
    test "nested failure composes the path" do
      match Json.parse("{\"label\":\"x\",\"inner\":{\"id\":\"nope\"}}") do
      Ok(v) -> match from_json(v) do
        Ok(_) -> assert (false)
        Err(e) -> assert (Json.decode_error_to_string(e) == "$.inner.id: expected Int")
        end
      Err(_) -> assert (false)
      end
    end
    test "non-object for a record type" do
      match Json.parse("[1,2]") do
      Ok(v) -> match from_json(v) do
        Ok(_) -> assert (false)
        Err(e) -> assert (Json.decode_error_to_string(e) == "$: expected an object")
        end
      Err(_) -> assert (false)
      end
    end
    test "unknown fields are ignored (Decision 2)" do
      match Json.parse("{\"name\":\"a\",\"age\":3,\"active\":true,\"score\":1.5,\"zzz\":9}") do
      Ok(v) -> match from_json(v) do
        Ok(r) -> assert (r.age == 3)
        Err(_) -> assert (false)
        end
      Err(_) -> assert (false)
      end
    end
  end
```

Exact message wording (`expected String`, `missing field`,
`expected an object`) is a contract here — Task 6's differential oracle
compares the *tree* decoder's verdict against the *event* decoder's, so both
must agree on text. If Step 1's reading shows a different existing wording is
cheaper to keep, change these tests **and** record the chosen wording in the
report as the contract.

- [ ] **Step 3: Run to verify failure**

```bash
dune build --root . bin/main.exe 2>&1 | tail -3
./_build/default/bin/main.exe test test/stdlib/test_json_typed.march; echo "exit=$?"
```

- [ ] **Step 4: Restructure the generator**

Replace the single tuple-match with a per-field chain. For a record
`{name : String, age : Int}`, generate the shape:

```march
fn from_json(v) do
  match v do
  Object(kvs) ->
    match Json.get_field(kvs, "name") do
    None -> Err(Json.DecodeError("missing field", Cons(Json.JPathField("name"), Nil), 0 - 1))
    Some(fv) -> match fv do
      Str(name) ->
        match Json.get_field(kvs, "age") do
        None -> Err(Json.DecodeError("missing field", Cons(Json.JPathField("age"), Nil), 0 - 1))
        Some(av) -> match av do
          Number(agef) -> Ok({ name = name, age = float_to_int(agef) })
          _ -> Err(Json.DecodeError("expected Int", Cons(Json.JPathField("age"), Nil), 0 - 1))
          end
        end
      _ -> Err(Json.DecodeError("expected String", Cons(Json.JPathField("name"), Nil), 0 - 1))
      end
    end
  _ -> Err(Json.DecodeError("expected an object", Nil, 0 - 1))
  end
end
```

Nested right-wards, one field at a time. For a field whose type is itself
derived, recurse and **prepend the step to the inner error**:

```march
      Some(fv) -> match from_json(fv) do
        Err(inner) -> Err(Json.decode_error_under(Json.JPathField("inner"), inner))
        Ok(innerv) -> ...continue...
        end
```

That single line is what makes `$.inner.id` compose without threading a
cursor through user code.

If `Json.get_field` does not exist, add it to `stdlib/json.march` in this task
(a linear scan of the `List((String, JsonValue))` returning `Option`), with
its own test.

**Unknown fields are ignored for free** in this shape: the decoder looks up
the fields it wants and never enumerates `kvs`. Note that in the report — it
means Decision 2 costs nothing.

- [ ] **Step 5: Migrate the three existing consumers**

`test_derive_json.march`, `test_derive_json_multi.march`, and
`test_island_bridges.march` match on the old `String` error. Update them to
the new type — most sites just need `to_string(e)` →
`Json.decode_error_to_string(e)`, or a changed `Err(e) -> ... e ...` body.
Run each file individually.

- [ ] **Step 6: Run everything a desugar change can break**

```bash
dune build --root . bin/main.exe @install test/run_compiler.exe test/test_stdlib_march.exe 2>&1 | tail -3
./_build/default/bin/main.exe test test/stdlib/test_json_typed.march; echo "typed=$?"
./_build/default/bin/main.exe test test/stdlib/test_derive_json.march; echo "derive=$?"
./_build/default/bin/main.exe test test/stdlib/test_derive_json_multi.march; echo "multi=$?"
./_build/default/bin/main.exe test test/stdlib/test_island_bridges.march; echo "island=$?"
./_build/default/test/run_compiler.exe -e 2>&1 | tail -3; echo "compiler=$?"
```

A `desugar.ml` change affects every March program — `run_compiler` is not
optional here.

- [ ] **Step 7: Commit**

```bash
git add lib/desugar/desugar.ml stdlib/json.march test/stdlib/test_json_typed.march test/stdlib/test_derive_json.march test/stdlib/test_derive_json_multi.march test/stdlib/test_island_bridges.march
git commit -m "feat(derive): record from_json reports a JSONPath instead of one opaque error"
```

---

### Task 4: Paths for enums and variants-with-args

**Files:**
- Modify: `lib/desugar/desugar.ml` (variant branches of the `from_json`
  generator)
- Modify: `test/stdlib/test_json_typed.march`

- [ ] **Step 1: Write the failing tests**

```march
  describe "variant decode errors carry a path" do
    test "unknown tag" do
      match Json.parse("{\"tag\":\"Purple\"}") do
      Ok(v) -> match from_json(v) do
        Ok(_) -> assert (false)
        Err(e) -> assert (Json.decode_error_to_string(e) == "$.tag: unknown variant `Purple`")
        end
      Err(_) -> assert (false)
      end
    end
    test "variant argument of the wrong type names its index" do
      -- Circle(Int) given a string argument
      match Json.parse("{\"tag\":\"Circle\",\"values\":[\"nope\"]}") do
      Ok(v) -> match from_json(v) do
        Ok(_) -> assert (false)
        Err(e) -> assert (Json.decode_error_to_string(e) == "$.values[0]: expected Int")
        end
      Err(_) -> assert (false)
      end
    end
  end
```

**Adapt the JSON shape to whatever the existing encoder emits** — Task 1's
capability map records it, and `test_derive_json.march` asserts `"tag"` is
present. Read the encoder side (`to_json` for variants) and mirror it exactly;
inventing a different wire format here would break round-tripping.

- [ ] **Step 2: Run to verify failure, then implement**

Same per-branch structure as Task 3: match the tag, then decode each argument
positionally, wrapping argument errors with
`Json.decode_error_under(Json.JPathIndex(i), inner)`.

- [ ] **Step 3: Run the same suite set as Task 3 Step 6, then commit**

```bash
git add lib/desugar/desugar.ml test/stdlib/test_json_typed.march
git commit -m "feat(derive): variant from_json reports the tag and argument index"
```

---

### Task 5: Byte offsets — `JsonStream.each_typed`

Connects the path to the record, per Decision 3.

**Files:**
- Modify: `stdlib/json_stream.march` (driver only — the tokenizer is frozen)
- Modify: `test/stdlib/test_json_typed.march`

- [ ] **Step 1: Write the failing tests**

```march
  describe "each_typed carries the record's byte offset" do
    test "decodes an ndjson file to typed records" do
      let path = "/tmp/march_each_typed_ok.jsonl"
      match File.write(path, "{\"id\":1}\n{\"id\":2}\n") do
      Err(_) -> assert (false)
      Ok(_) -> do
        match JsonStream.each_typed(path, fn r -> ()) do
        Ok(n) -> assert (n == 2)
        Err(_) -> assert (false)
        end
      end
      end
      match File.delete(path) do _ -> () end
    end
    test "a bad record reports its field AND a nonzero byte offset" do
      let path = "/tmp/march_each_typed_bad.jsonl"
      -- second record is malformed; its offset is past the first record
      match File.write(path, "{\"id\":1}\n{\"id\":\"nope\"}\n") do
      Err(_) -> assert (false)
      Ok(_) -> do
        match JsonStream.each_typed(path, fn r -> ()) do
        Ok(_) -> assert (false)
        Err(e) -> do
          assert (String.contains(Json.decode_error_to_string(e), "$.id"))
          assert (String.contains(Json.decode_error_to_string(e), "byte 9"))
        end
        end
      end
      end
      match File.delete(path) do _ -> () end
    end
  end
```

The expected offset (`byte 9`) assumes the second record starts right after
`{"id":1}\n`. **Verify it against the implementation rather than trusting the
arithmetic here** — if it differs deterministically, fix the test and say so
in the report.

- [ ] **Step 2: Implement `each_typed`**

Modelled on the existing `each_value`, but capturing the offset of each
record's *first* event and attaching it with `Json.decode_error_at` when
`from_json` fails. The type is
`each_typed(path, cb) : Result(Int, Json.DecodeError)` returning the record
count.

**Do not touch `feed`, `finish`, `go`, or any tokenizer internals** — this is
a driver built on the existing public API.

- [ ] **Step 3: Run, including JsonStream's own suite**

```bash
dune build --root . bin/main.exe @install 2>&1 | tail -3
./_build/default/bin/main.exe test test/stdlib/test_json_typed.march; echo "typed=$?"
./_build/default/bin/main.exe test test/stdlib/test_json_stream.march; echo "stream=$?"
```

`test_json_stream.march` must be **unchanged and green** — phases 1-2's
guarantees are frozen.

- [ ] **Step 4: Commit**

```bash
git add stdlib/json_stream.march test/stdlib/test_json_typed.march
git commit -m "feat(stdlib): JsonStream.each_typed decodes records and reports byte offsets"
```

---

### Task 6: Phase B — decode straight from events

The compiler-side payoff: a second generated decoder per type that consumes
the event stream, so a record never becomes a tree. Follows serde's
generated-visitor shape (Decision 4).

**Do not start this task until Tasks 2-4 are merged** — generating a second
decoder against an error type still in flux means designing it twice.

**Files:**
- Modify: `lib/desugar/desugar.ml` (new `from_json_events` generator)
- Modify: `test/stdlib/test_json_typed.march`

- [ ] **Step 1: Write the differential oracle first**

The oracle is the deliverable that makes generated control flow
trustworthy — write it before the generator:

```march
  describe "event decoder matches the tree decoder" do
    -- For every corpus document, from_json(build(doc)) and
    -- from_json_events(events(doc)) must agree: same value on success, same
    -- verdict AND same rendered error on failure. This is the same technique
    -- phase 1 used against Json.parse.
    test "tree and event decoders agree over the corpus" do
      let corpus = Cons("{\"name\":\"a\",\"age\":3,\"active\":true,\"score\":1.5}",
                   Cons("{\"name\":\"a\",\"age\":3,\"active\":true,\"score\":1.5,\"zzz\":9}",
                   Cons("{\"age\":3,\"name\":\"a\",\"score\":1.5,\"active\":true}",
                   Cons("{\"name\":1,\"age\":3,\"active\":true,\"score\":1.5}",
                   Cons("{\"name\":\"a\",\"active\":true,\"score\":1.5}",
                   Cons("[1,2]",
                   Nil))))))
      assert (agree_all(corpus))
    end
  end
```

with a module-scope helper comparing the two decoders' rendered outcomes and
printing any mismatch. **The corpus must include** an unknown field, a
reordered object, a missing field, a wrong type, and a non-object — those are
the cases where a generated state machine diverges from a tree walk.

- [ ] **Step 2: Generate the event decoder**

Per Decision 4, for a record type generate:

- expect `EvObjStart`, else `DecodeError("expected an object", Nil, off)`;
- one `Option` slot per field, all `None` initially;
- loop: on `EvKey(k)` dispatch on `k` to decode that field's value from the
  following events into its slot; on `EvObjEnd` stop;
- on `EvObjEnd`, every required slot must be filled, else
  `DecodeError("missing field", [JPathField(name)], off)`;
- **unknown key → skip the entire following value**, which may be a whole
  subtree.

- [ ] **Step 3: Implement unknown-field skipping with explicit depth counting**

This is the highest-risk piece in the plan and it fails *silently*: skipping a
subtree by counting only the next event desynchronizes the stream, and the
decoder then reads a nested value as if it were a sibling — producing a
**wrong value with no error**. Skipping must track depth:

```march
-- Skip exactly one value: a scalar is one event; a container runs until its
-- depth returns to zero.
pfn skip_value(events, depth) do ... end
```

Give this its own tests independent of the oracle: an unknown field whose
value is a nested object, a nested array, an array of objects, and an empty
object — each followed by a *known* field whose value must still decode
correctly. That last part is what actually detects desynchronization.

- [ ] **Step 4: Duplicate keys — state the policy**

Go and serde default to last-wins. Whatever the tree decoder does today
(Task 1's map records it), the event decoder must match, because the oracle
compares them. Add a corpus document with a duplicate key and make both agree.

- [ ] **Step 5: Run the oracle plus the full set**

```bash
dune build --root . bin/main.exe @install test/run_compiler.exe 2>&1 | tail -3
./_build/default/bin/main.exe test test/stdlib/test_json_typed.march; echo "typed=$?"
./_build/default/bin/main.exe test test/stdlib/test_json_stream.march; echo "stream=$?"
./_build/default/test/run_compiler.exe -e 2>&1 | tail -3; echo "compiler=$?"
scripts/run-tests.sh 2>&1 | tail -6
```

- [ ] **Step 6: Docs and commit**

Update `specs/todos.md` (move Component 4 to Done; note whether combinators
remain open), `specs/progress.md` (new dated entry at top), `CHANGELOG.md`
(`### Added` for `each_typed` and typed errors; `### Changed` for
`from_json`'s error type — a breaking change worth calling out), and flip the
design spec's Status. Run `bash scripts/check-docs.sh` and
`bash scripts/gen-docs-search-index.sh --check`; if the latter reports stale,
regenerate and stage `docs/pagefind/`.

```bash
git add lib/desugar/desugar.ml test/stdlib/test_json_typed.march specs/todos.md specs/progress.md CHANGELOG.md specs/2026-07-31-json-typed-decoding-design.md
git commit -m "feat(derive): from_json_events decodes without building a JsonValue tree"
```

---

## Self-review

**Spec coverage:** design Phase A1 → Task 1; A2 → Tasks 2-4 (split because
the record restructuring is by far the largest piece and enums are separable);
A3 → Task 5; Phase B → Task 6. The design's non-goals (combinators, schema
validation, `to_json` changes, tokenizer changes) have no tasks, deliberately.

**Placeholder scan:** four steps defer to source inspection, each with a
concrete instruction and a recorded output rather than "figure it out" —
Task 1 Steps 2/4 (probe uncertain capabilities; adapt to `File.read`'s actual
shape), Task 3 Step 1 (read the generator and write down its structure before
editing), Task 4 Step 1 (mirror the existing variant wire format rather than
inventing one), Task 5 Step 1 (verify the byte offset rather than trusting
arithmetic in this document). Task 3's generated-code block is illustrative
March showing the *target shape*; the actual change is OCaml AST construction,
which is why Step 1 requires reading the generator first — inventing verbatim
OCaml for code I have not fully read would be worse than specifying the
behaviour and the tests.

**Type consistency:** `DecodeError(msg, path, offset)` with path stored
outermost-first is used identically in Tasks 2-6;
`decode_error_under(step, e)` prepends, `decode_error_at(off, e)` sets the
offset; `from_json` returns `Result(T, Json.DecodeError)` from Task 3 onward;
`each_typed(path, cb) : Result(Int, Json.DecodeError)`.

**The invariant most likely to break quietly:** unknown-field subtree skipping
in Task 6. It produces a wrong value with no error, which no assertion about
the *failing* cases would catch — hence Step 3's dedicated tests requiring a
**known field after the skipped one** to still decode, and the oracle corpus
mandating unknown fields.

**Ordering constraint that is not negotiable:** Task 6 after Tasks 2-4.
serde's `serde_path_to_error` exists because paths were retrofitted onto a
decoder not designed for them; generating the event decoder before the error
type settles would repeat that mistake inside this repo.
