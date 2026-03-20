# JSON Library Design

**Date:** 2026-03-19
**Status:** Approved

---

## Overview

March needs a JSON library serving two use cases with equal priority: parsing HTTP API response bodies, and general-purpose JSON handling in user programs. The design is a single flat `Json` stdlib module backed by yyjson (C, compiled path) and Yojson (OCaml, interpreter path), exposing a dynamic ADT with pattern-matching-friendly accessors.

---

## Type

```march
type Json
  = Null
  | Bool(Bool)
  | Int(Int)
  | Float(Float)
  | Str(String)
  | Array(List(Json))
  | Object(Map(String, Json))
```

**`Int` and `Float` are split**, not unified into `Number(Float)`. Rationale:

- yyjson internally distinguishes signed int, unsigned int, and real — the information is free.
- Collapsing to `Float` loses precision for integers above 2⁵³ and requires `Int.from_float` noise at every call site.
- March's stdlib already separates `Num(Int)` and `Fractional(Float)` — a unified `Number(Float)` JSON type would be the only conflation in the stdlib.
- Common API payloads (IDs, counts, status codes) are integers. Users expect `Int(id)` not `Float(42.0)`.

The heuristic: if the JSON number token has no decimal point and no exponent, it parses as `Int`. Otherwise `Float`. This matches yyjson's own subtype tagging.

---

## API

```march
mod Json do

  type Json
    = Null
    | Bool(Bool)
    | Int(Int)
    | Float(Float)
    | Str(String)
    | Array(List(Json))
    | Object(Map(String, Json))

  type JsonError = JsonError(message : String, offset : Int)

  -- Core
  pub fn parse(s : String) : Result(Json, JsonError)
  pub fn encode(v : Json) : String
  pub fn encode_pretty(v : Json) : String
  pub fn parse_or_panic(s : String) : Json

  -- Object access
  pub fn get(v : Json, key : String) : Option(Json)

  -- Array access
  pub fn at(v : Json, idx : Int) : Option(Json)

  -- Nested path access
  -- path(j, ["users", "0", "name"]) — integer indices written as strings
  pub fn path(v : Json, keys : List(String)) : Option(Json)

  -- Type coercions
  pub fn as_str(v : Json) : Option(String)
  pub fn as_int(v : Json) : Option(Int)
  pub fn as_float(v : Json) : Option(Float)
  pub fn as_bool(v : Json) : Option(Bool)
  pub fn as_list(v : Json) : Option(List(Json))
  pub fn as_map(v : Json) : Option(Map(String, Json))

  -- Constructors (convenience — the ADT constructors work directly too)
  pub fn null() : Json
  pub fn bool(b : Bool) : Json
  pub fn int(n : Int) : Json
  pub fn float(f : Float) : Json
  pub fn str(s : String) : Json
  pub fn array(xs : List(Json)) : Json
  pub fn object(pairs : List((String, Json))) : Json

end
```

### Design decisions

**`path` uses `List(String)` with integer indices as strings.** Consistent with how JSON path notation works universally. Avoids a mixed `String | Int` key type.

**`object` takes `List((String, Json))` not `Map(String, Json)`.** Construction at call sites is more ergonomic with a list of pairs. The function builds the `Map` internally.

**`parse_or_panic` follows the `head`/`head_opt` convention.** For hardcoded JSON literals, test fixtures, and config known to be valid. Panics with the `JsonError` message on failure.

**No `Show` impl.** `encode` and `encode_pretty` serve that purpose. A `Show` impl would need to choose between compact and pretty — `encode` makes that explicit.

**No structured `JsonError` variants.** Callers almost never switch on error kind — they propagate or log. A string message plus byte offset covers all practical debugging needs.

---

## Implementation layers

```
runtime/yyjson.h            vendored, untouched
runtime/yyjson.c            vendored, untouched
runtime/march_json.c        C wrapper: yyjson tree → March ADT heap objects
lib/eval/eval.ml            OCaml builtins using Yojson (interpreter path)
stdlib/json.march           March module: builtins + pure March helpers
```

### Two-path approach

The eval interpreter and the compiled runtime use incompatible value representations:

- **Interpreter**: OCaml `value` type (`VString`, `VInt`, `VConstructor`, etc.)
- **Compiled runtime**: `march_alloc`-allocated heap objects with `march_hdr` layout

A single C function cannot serve both. Bridging C → OCaml values requires `CAMLparam`/`CAMLreturn` GC integration, adding complexity without benefit. The existing pattern (TCP uses OCaml's `Unix` module in eval, C runtime for compiled) is the right model.

| Path | Parser | Reason |
|------|--------|--------|
| Interpreter (`eval.ml`) | Yojson (opam) | Zero FFI complexity, already OCaml |
| Compiled (TIR → LLVM) | yyjson in `march_json.c` | Fast, C-native, consistent with runtime |

The split is invisible to users — `json_parse` is a builtin name in both paths, the March module is identical.

**Edge case caveat:** Yojson and yyjson may disagree on exotic edge cases (unusual unicode sequences, number boundary values). This is unlikely with two well-maintained parsers but is worth a future conformance test.

### C wrapper (`march_json.c`)

yyjson parses into its own internal document tree. The wrapper walks that tree once, producing March heap objects via `march_alloc` and `march_string_lit`. The yyjson document is freed immediately after the walk — no C memory escapes into March's heap.

Exposed functions:

```c
// Returns a March Result(Json, JsonError) heap object.
void *march_json_parse(const char *s, int64_t len);

// Returns a march_string*.
void *march_json_encode(void *json_val);
void *march_json_encode_pretty(void *json_val);
```

ADT tag assignments for `Json` constructors (follows alphabetical-field convention of the runtime):

| Constructor | Tag | Fields |
|-------------|-----|--------|
| `Array`     | 0   | `List(Json)` |
| `Bool`      | 1   | `Bool` (int64: 0=false, 1=true) |
| `Float`     | 2   | `Float` (double) |
| `Int`       | 3   | `Int` (int64) |
| `Null`      | 4   | none |
| `Object`    | 5   | `Map(String, Json)` |
| `Str`       | 6   | `String` (march_string*) |

`Object` fields are built as a `Map(String, Json)` by inserting into the HAMT incrementally during the tree walk. `Array` fields become a `List(Json)` built in reverse then reversed once.

### OCaml builtins (`eval.ml`)

Three builtins: `json_parse`, `json_encode`, `json_encode_pretty`. Implemented using Yojson. Translation between Yojson's `Basic.t` AST and March's `value` type is a straightforward recursive walk.

Number handling in Yojson: `Int` comes through as Yojson's `` `Int ``, `Float` as `` `Float ``. The `Int`/`Float` split is preserved naturally.

### March module (`stdlib/json.march`)

Only `parse`, `encode`, and `encode_pretty` call builtins. All accessors and helpers are pure March:

- `get`, `at` — pattern match + `Map.get` / `List.nth_opt`
- `path` — fold over keys calling `get`/`at`
- `as_str`, `as_int`, etc. — single-arm pattern matches returning `Option`
- `object` — `List.fold_left` building a `Map`
- Constructor helpers — trivial wrappers around ADT constructors

---

## Error model

```march
type JsonError = JsonError(message : String, offset : Int)
```

- `message`: human-readable description from the underlying parser
- `offset`: byte position in the input string where parsing failed

No structured error variants (`UnexpectedToken`, `MaxDepthExceeded`, etc.). JSON parse errors are almost always programmer errors or untrusted-input failures where the caller just needs to know *that* it failed and *where* for logging/debugging. A variant hierarchy adds API surface with no practical benefit.

---

## Files changed

| File | Change |
|------|--------|
| `runtime/yyjson.h` | Add (vendored) |
| `runtime/yyjson.c` | Add (vendored) |
| `runtime/march_json.c` | Add (new C wrapper) |
| `runtime/march_runtime.h` | Add declarations for `march_json_*` functions |
| `lib/eval/eval.ml` | Add `json_parse`, `json_encode`, `json_encode_pretty` builtins |
| `stdlib/json.march` | Add (new stdlib module) |
| `bin/main.ml` | Add `json.march` to stdlib load order |
| `test/test_march.ml` | Add JSON tests |
| `dune` (runtime) | Add yyjson.c and march_json.c to foreign stubs |

---

## Example usage

```march
-- Parse and extract
let result = Json.parse(response_body)
match result with
| Err(JsonError(msg, offset)) ->
  IO.println(io, "parse failed at byte #{offset}: #{msg}")
| Ok(json) ->
  match Json.path(json, ["user", "id"]) with
  | Some(Int(id)) -> IO.println(io, "user id: #{id}")
  | Some(other)   -> IO.println(io, "unexpected type: #{Json.encode(other)}")
  | None          -> IO.println(io, "missing user.id")
  end
end

-- Construct and encode
let payload = Json.object([
  ("name", Json.str("alice")),
  ("score", Json.int(42)),
  ("active", Json.bool(true))
])
IO.println(io, Json.encode(payload))
-- {"name":"alice","score":42,"active":true}
```
