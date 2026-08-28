---
layout: docs
title: Stdlib Guide
nav_order: 12.5
permalink: /docs/stdlib-guide/
---

# Standard Library Guide

> **Looking for the full API reference?** Every stdlib module, type, and function, with
> signatures and docstrings generated from source, lives at **[/docs/stdlib/](/docs/stdlib/)**.
> This page is a hand-written tour of the most commonly used modules.

March ships with 116 stdlib modules covering collections, strings, I/O, HTTP, cryptography, and more. This page provides an overview and quick reference for the most commonly used modules.

All stdlib modules are available without any import statement: use qualified access (`List.map`, `String.length`, etc.) or `import`/`use` to bring names into scope.

---

## What do I use for…?

You know the task; this maps it to the module(s) that do it. (Don't see your task? The [full reference](/docs/stdlib/) is searchable.)

| I want to… | Reach for | Recipe |
|---|---|---|
| Parse CLI args | `System` / `Process` (`argv`) | [CLI](/docs/cookbook/cli/), [Build a CLI](/docs/build-a-cli/) |
| Read / write files | `File`, `Dir`, `Path` | [Files](/docs/cookbook/files/) |
| Parse a CSV | `Csv` | [Files](/docs/cookbook/files/) |
| Call an HTTP API | `HttpClient`, `Http` | [HTTP](/docs/cookbook/http/) |
| Parse a JSON response | `Json` | [JSON API](/docs/cookbook/json-api/) |
| Parse TOML / YAML config | `Toml`, `Yaml` | [Config](/docs/cookbook/config/) |
| Read environment variables | `Env`, `Config` | [Config](/docs/cookbook/config/) |
| Run a subprocess | `Process` (`run`, `run_stream`) | none |
| Hash / encode data | `Crypto`, `Base64` | none |
| Work with dates / durations | `DateTime`, `Duration` | none |
| Structured logging | `Logger` | none |
| Run work concurrently | `Task`, `actor`, `Flow` | [Concurrency](/docs/cookbook/concurrency/) |
| Transform a big collection in parallel | `List.pmap` / `pmap_n` | none |
| Process a large numeric array fast | `NativeArray`, `Simd` | [Numeric Data](/docs/cookbook/numeric-data/) |

---

## NativeArray and Simd

For numeric hot loops (summing a column, scaling an array, scanning bytes),
reach for `NativeArray` instead of `List`/`Array`. It's a flat, contiguous
numeric array (`Int`/`Float`/`f32`/`i32`/`u8` element widths) that
`march --compile` can auto-vectorize: `NativeArray.sum_float`,
`NativeArray.map_int`, `NativeArray.map2_f32`, and friends compile to real
SIMD instructions on a compiled build, no ceremony required.

```march
let arr = NativeArray.make_float(1_000_000, 0.0)
let doubled = NativeArray.map_float(arr, fn x -> x *. 2.0)
let total = NativeArray.sum_float(doubled)
```

When you need guaranteed vector codegen rather than an optimizer decision
(cross-lane structure with masks and `select`, a fused multiply-add, or byte-level
scanning), reach for the `Simd` module instead: five 128-bit vector types
(`F32x4`, `F64x2`, `I32x4`, `I64x2`, `U8x16`) with 127 operations between
them, register-resident in compiled code.

See [SIMD & Native Arrays](/docs/simd/) for the full guide (what vectorizes,
how to trigger it, the unvarnished performance story) and
[SIMD Benchmarks](/docs/simd-benchmarks/) for the numbers, or jump straight
to the API references: [`NativeArray`](/docs/stdlib/NativeArray.html),
[`Simd`](/docs/stdlib/Simd.html).

---

## Prelude (Auto-imported)

The `Prelude` module is automatically imported into every March program. These names are always in scope:

```march
-- Diverging
panic("invariant violated")   -- terminates with an error
todo("not yet implemented")   -- typechecks as any type
unreachable()                 -- asserts a branch can't be reached

-- Option helpers
unwrap(Some(42))              -- 42, panics if None
unwrap_or(None, 0)            -- 0
unwrap_or_else(opt, fn () -> compute_default())

-- List basics
head([1, 2, 3])               -- 1, panics if empty
tail([1, 2, 3])               -- [2, 3], panics if empty
is_nil([])                    -- true

-- Combinators
identity(x)                   -- x
compose(f, g)                 -- fn x -> f(g(x))
flip(f)                       -- fn a b -> f(b, a)
const(x)                      -- fn _ -> x
```

---

## List

`list.march`: the standard singly-linked list.

```march
-- Construction
List.empty()                         -- []
List.singleton(42)                   -- [42]
List.repeat("hi", 3)                 -- ["hi", "hi", "hi"]
List.range(0, 5)                     -- [0, 1, 2, 3, 4]
List.range_step(0, 10, 2)            -- [0, 2, 4, 6, 8]

-- Access
List.head([1, 2, 3])                 -- 1  (panics if empty)
List.head_opt([1, 2, 3])             -- Some(1)
List.last([1, 2, 3])                 -- 3
List.nth([10, 20, 30], 1)            -- 20  (0-indexed; n : {Int | _ >= 0 && _ < len(xs)})
List.nth_opt([10, 20], 5)            -- None

-- Predicates
List.is_empty([])                    -- true
List.length([1, 2, 3])               -- 3
List.any([1, 2, 3], fn x -> x > 2)  -- true
List.all([2, 4, 6], fn x -> x % 2 == 0)  -- true
List.member([1, 2, 3], 2)           -- true

-- Transformation
List.map([1, 2, 3], fn x -> x * 2)          -- [2, 4, 6]
List.filter([1, 2, 3, 4], fn x -> x % 2 == 0) -- [2, 4]
List.filter_map(xs, fn x -> if x > 0 do Some(x * 2) else None end)
List.flat_map([1, 2, 3], fn x -> [x, x * 10])  -- [1, 10, 2, 20, 3, 30]
List.reverse([1, 2, 3])              -- [3, 2, 1]
List.append([1, 2], [3, 4])         -- [1, 2, 3, 4]
List.concat([[1, 2], [3], [4, 5]])   -- [1, 2, 3, 4, 5]

-- Folds
List.fold_left([1, 2, 3], 0, fn (acc, x) -> acc + x)   -- 6
List.fold_right([1, 2, 3], 0, fn (x, acc) -> x + acc)  -- 6
List.scan_left([1, 2, 3], 0, fn (acc, x) -> acc + x)   -- [0, 1, 3, 6]

-- Search
List.find([1, 2, 3], fn x -> x > 1)      -- Some(2)
List.find_index([10, 20, 30], fn x -> x == 20)  -- Some(1)

-- Iteration (side effects)
List.each([1, 2, 3], fn x -> println(int_to_string(x)))

-- Sorting
List.sort_by([3, 1, 2], fn (a, b) -> a < b)   -- [1, 2, 3]

-- Zipping
List.zip([1, 2, 3], ["a", "b", "c"])  -- [(1, "a"), (2, "b"), (3, "c")]
List.unzip([(1, "a"), (2, "b")])       -- ([1, 2], ["a", "b"])

-- Grouping
List.intersperse([1, 2, 3], 0)         -- [1, 0, 2, 0, 3]
List.take([1, 2, 3, 4, 5], 3)         -- [1, 2, 3]
List.drop([1, 2, 3, 4], 2)            -- [3, 4]
List.take_while([1, 2, 3, 4], fn x -> x < 3)   -- [1, 2]
List.drop_while([1, 2, 3, 4], fn x -> x < 3)   -- [3, 4]

-- Parallel (real multi-core parallelism in compiled code; the supplied
-- function MUST be safe to run concurrently)
List.pmap([1, 2, 3], fn x -> x * 2)              -- [2, 4, 6]  (parallel map)
List.pmap_n(urls, fn u -> fetch(u), 8)           -- parallel map, ≤8 tasks at once
List.pfilter([1, 2, 3, 4], fn x -> x % 2 == 0)  -- [2, 4]     (parallel filter)
List.preduce([1, 2, 3, 4], 0, fn (a, b) -> a + b)  -- 10  (combine MUST be associative)
```

The parallel operations are order-preserving and return exactly what their
sequential counterparts (`map`/`filter`/`fold_left`) do. Below a configurable
cutoff they fall back to the sequential version (no task-spawn overhead); above
it the list is split into chunks, one task per chunk, run on the multithreaded
scheduler. Real CPU parallelism happens in **compiled** code; the interpreter
runs the tasks eagerly on one thread (correct, but sequential).

- The cutoff is `pmap_threshold()` (default **1024**), set at compile time with
  `--pmap-threshold=N` (forge passes it through via `MARCH_PMAP_THRESHOLD`).
- `pmap_n` caps concurrency explicitly; use it when each element does heavy
  work (few elements, expensive per-element) so the size heuristic doesn't apply.
- `preduce` is a **tree reduction**: `combine` must be associative
  (`combine(combine(x, y), z) == combine(x, combine(y, z))`) with `identity` as
  its unit. Sum, product, max, min, string concat, set union qualify;
  subtraction and average do not. The compiler cannot check this; it's the
  caller's contract.

> **Tip:** the LSP flags a pure `List.map`/`List.filter` as a `pmap`/`pfilter`
> candidate with a one-click "Convert to `List.pmap`" quick-fix.

See the [Parallel Collections guide]({{ site.baseurl }}/docs/parallel-collections/)
for how chunking works, the `--pmap-threshold` flag, when to parallelize, and the
editor-driven detection.

---

## String

`string.march`: String operations.

```march
string_length("hello")              -- 5  (bare builtin, not under the String module)
String.join(["a", "b", "c"], "")    -- "abc"
String.join(["a", "b", "c"], ", ")  -- "a, b, c"
String.split("a,b,c", ",")          -- ["a", "b", "c"]
String.trim("  hello  ")            -- "hello"
String.trim_start("  hi")           -- "hi"
String.trim_end("hi  ")             -- "hi"
String.to_uppercase("hello")        -- "HELLO"
String.to_lowercase("HELLO")        -- "hello"
String.starts_with("hello", "he")   -- true
String.ends_with("hello", "lo")     -- true
String.contains("hello world", "world")  -- true
String.replace_all("hello", "l", "r")   -- "herro"  (replace() only replaces the first match)
String.slice("hello", 1, 3)         -- "ell"  (start, length — not start, end)
String.to_int("42")                 -- Ok(42)
String.to_float("3.14")             -- Ok(3.14)
String.repeat("ab", 3)              -- "ababab"
String.reverse("hello")             -- "olleh"
```

---

## Map

`map.march`: HAMT-backed persistent map. O(log n) amortized operations.

Map operations that need key identity take an explicit comparator:
`cmp : k -> k -> Bool` where `cmp(a)(b) = true` means `a < b`.

> **No comparator?** If your keys are strings, ints, or any type where structural
> `==` is the right equality, use [`HashMap`](#hashmap) instead: identical API,
> no `cmp` argument anywhere.

```march
let cmp = fn a -> fn b -> a < b   -- comparator for String keys

-- Construction
let m = Map.empty()
let m2 = Map.singleton("key", 42)
let m3 = Map.from_list([("a", 1), ("b", 2), ("c", 3)], cmp)

-- Access
Map.get(m3, "a", cmp)          -- Some(1)
Map.get_or(m3, "z", 0, cmp)   -- 0
Map.contains_key(m3, "b", cmp) -- true
Map.size(m3)                   -- 3
Map.is_empty(m)                -- true

-- Modification (returns new map)
let m4 = Map.insert(m3, "d", 4, cmp)
let m5 = Map.remove(m4, "a", cmp)

-- Traversal
Map.keys(m3)     -- ["a", "b", "c"] (hash order)
Map.values(m3)   -- [1, 2, 3]
Map.entries(m3)  -- [("a", 1), ("b", 2), ("c", 3)]
Map.fold(m3, 0, fn (acc, _k, v) -> acc + v)   -- 6

-- Transformation
Map.map_values(m3, fn v -> v * 10)            -- {"a": 10, "b": 20, "c": 30}
Map.filter(m3, fn _k -> fn v -> v > 1, cmp)  -- {"b": 2, "c": 3}
Map.merge(m3, m4, cmp)                        -- right takes precedence on conflict
Map.merge_with(m3, m4, fn a -> fn b -> a + b, cmp)  -- custom merge

-- Converting
Map.to_list(m3)   -- [("a", 1), ("b", 2), ("c", 3)]
```

---

## HashMap

`hash_map.march`: HAMT-backed persistent map using structural `==` for key
equality and the built-in polymorphic `hash` function. No comparator needed at
any call site. Key iteration order is hash-traversal order (not sorted, not
insertion order).

Use `Map` when you need sorted output or a custom comparator. Use `HashMap`
when you don't want to thread a comparator everywhere, especially for
string/int keys or for Enum.uniq / Enum.frequencies patterns.

```march
-- Construction (no comparator arg anywhere)
let m = HashMap.new()
let m2 = HashMap.from_list([("a", 1), ("b", 2), ("c", 3)])

-- Access
HashMap.get(m2, "a")           -- Some(1)
HashMap.get_or(m2, "z", 0)    -- 0
HashMap.has(m2, "b")           -- true
HashMap.size(m2)               -- 3
HashMap.is_empty(m)            -- true

-- Modification (returns new map)
let m3 = HashMap.put(m2, "d", 4)
let m4 = HashMap.delete(m3, "a")

-- Counter pattern (no get-then-put dance)
let counts = List.fold_left(words, HashMap.new(), fn (acc, w) ->
  HashMap.update(acc, w, fn opt ->
    match opt do
    None    -> 1
    Some(n) -> n + 1
    end
  )
)

-- Traversal
HashMap.keys(m2)     -- ["a", "b", "c"] (hash order)
HashMap.values(m2)   -- [1, 2, 3]
HashMap.entries(m2)  -- [("a", 1), ("b", 2), ("c", 3)]
HashMap.fold(m2, 0, fn (acc, _k, v) -> acc + v)  -- 6

-- Transformation
HashMap.map_values(m2, fn v -> v * 10)
HashMap.filter(m2, fn _k -> fn v -> v > 1)
HashMap.merge(m2, m3)                               -- right takes precedence
HashMap.merge_with(m2, m3, fn va -> fn vb -> va + vb)

-- Converting
HashMap.to_list(m2)  -- [("a", 1), ("b", 2), ("c", 3)] (hash order)
```

---

## Set

`set.march`: HAMT-backed persistent set. The set is always the **first**
argument, and operations that need element identity take a trailing comparator
`cmp : a -> a -> Bool` where `cmp(a)(b) = true` means `a < b` (same convention
as `Map`).

```march
let cmp = fn a -> fn b -> a < b

let s = Set.from_list([1, 2, 3, 4, 5], cmp)
Set.contains(s, 3, cmp)    -- true
Set.insert(s, 6, cmp)      -- {1,2,3,4,5,6}
Set.remove(s, 3, cmp)      -- {1,2,4,5}
Set.size(s)                -- 5
Set.is_empty(Set.empty())  -- true

let s1 = Set.from_list([1, 2, 3], cmp)
let s2 = Set.from_list([2, 3, 4], cmp)
Set.union(s1, s2, cmp)         -- {1,2,3,4}
Set.intersection(s1, s2, cmp)  -- {2,3}
Set.difference(s1, s2, cmp)    -- {1}
Set.is_subset(s1, s2, cmp)     -- false

Set.to_list(s)                       -- [1, 2, 3, 4, 5]
Set.fold(s, 0, fn (acc, x) -> acc + x)  -- 15
```

---

## Option

`option.march`: `Option(a) = None | Some(a)`.

```march
Option.map(Some(5), fn x -> x + 1)     -- Some(6)
Option.map(None, fn x -> x + 1)        -- None
Option.flat_map(Some(5), fn x -> if x > 3 do Some(x) else None end)
Option.or_else(None, fn () -> Some(0)) -- Some(0)
Option.unwrap_or(None, 0)              -- 0
Option.unwrap_or_else(None, fn () -> compute())
Option.is_some(Some(1))               -- true
Option.is_none(None)                  -- true
Option.to_list(Some(42))              -- [42]
Option.to_list(None)                  -- []
Option.filter(Some(5), fn x -> x > 3)  -- Some(5)
Option.filter(Some(2), fn x -> x > 3)  -- None
```

---

## Result

`result.march`: `Result(a, e) = Ok(a) | Err(e)`.

```march
Result.map(Ok(5), fn x -> x + 1)      -- Ok(6)
Result.map(Err("oops"), fn x -> x + 1) -- Err("oops")
Result.map_err(Err("x"), String.to_uppercase) -- Err("X")
Result.flat_map(Ok(5), fn x -> Ok(x * 2))   -- Ok(10)
Result.or_else(Err("x"), fn e -> Ok(0))  -- Ok(0)
Result.unwrap(Ok(42))                 -- 42  (panics on Err)
Result.unwrap_or(Err("e"), 0)         -- 0
Result.is_ok(Ok(1))                   -- true
Result.is_err(Err("e"))               -- true
Result.to_option(Ok(42))              -- Some(42)
Result.to_option(Err("e"))            -- None
```

For lightweight error propagation in chains, use the `let?` binding instead of `Result.flat_map`:

```march
-- with Result.flat_map
Result.flat_map(String.to_int(s), fn n -> Result.flat_map(fetch(n), fn v -> Ok(v + 1)))

-- with let?
fn run(s : String) : Result(Int, String) do
  let? n = String.to_int(s)
  let? v = fetch(n)
  Ok(v + 1)
end
```

---

## IO

`io.march`: Explicit I/O operations.

```march
IO.puts("Hello, World!")         -- print with newline
IO.write("no newline")           -- print without newline
IO.warn("warning message")       -- print to stderr
IO.read_line()                   -- read a line from stdin -> String
IO.gets("> ")                    -- print prompt, read line
IO.inspect(any_value)            -- pretty-prints and returns any_value unchanged (for piping)
```

The `println` and `print` builtins are also always available.

---

## Math

`math.march`: Mathematical functions.

```march
int_abs(-5)                  -- 5  (Int abs is a bare builtin, not under Math)
Math.abs(-3.14)              -- 3.14  (Math.abs is Float-only)
Math.min_int(3, 5)           -- 3
Math.max_int(3, 5)           -- 5
Math.clamp_int(15, 0, 10)    -- 10
Math.sqrt(16.0)              -- 4.0
Math.pow(2.0, 10.0)          -- 1024.0
Math.exp(1.0)                -- 2.718...
Math.log(Math.e())           -- 1.0
Math.log2(8.0)                -- 3.0
Math.log10(1000.0)           -- 3.0
Math.floor(3.7)               -- 3.0
Math.ceil(3.2)                -- 4.0
Math.round(3.5)               -- 4.0
Math.sin(Math.pi() /. 2.0)   -- 1.0
Math.cos(0.0)                -- 1.0
Math.pi()                    -- 3.14159...  (pi/e/tau are 0-arg functions — call with `()`)
Math.e()                     -- 2.71828...
float_infinity()             -- Float infinity  (bare builtin, not under Math)
float_is_nan(float_nan())    -- true  (bare builtins; `0.0 /. 0.0` panics with "division by zero" rather than yielding NaN)
```

---

## Crypto

`crypto.march`: Cryptographic primitives.

```march
-- Hashing
Crypto.sha256("hello")              -- hex string
Crypto.sha512("hello")              -- hex string
Crypto.hmac(:sha256, key, message)  -- HMAC; algo is :sha256 or :sha512

-- Password hashing (PBKDF2 under the hood; stores salt + iterations)
let h = Crypto.hash_password("hunter2")     -- "pbkdf2:sha256:..." digest string
Crypto.verify_password("hunter2", h)         -- true (constant-time)

-- Randomness
Crypto.random_bytes(32)             -- Bytes of cryptographically random data
Crypto.random_hex(16)               -- random hex string (32 chars)

-- Encoding
Crypto.base64_encode("hello")       -- "aGVsbG8="
Crypto.base64_decode("aGVsbG8=")    -- Ok(Bytes)
Crypto.base64_url_encode("hello")   -- URL-safe Base64
Crypto.base64_url_decode(s)         -- Ok(Bytes)

-- Constant-time comparison (use for secrets / MACs)
Crypto.secure_compare(a, b)         -- Bool
```

---

## UUID

`uuid.march`: UUID generation and parsing.

```march
UUID.v4()                     -- generate a random UUID (a `UUID` value, not a bare String)
UUID.v5(namespace, name)      -- deterministic UUID from a UUID namespace + name
UUID.parse("550e8400-...")    -- Result(UUID, Atom): Ok(UUID(...)) or Err(:invalid)
UUID.to_string(uuid)          -- "550e8400-e29b-41d4-a716-446655440000"
UUID.version(uuid)            -- 4
UUID.is_valid("550e8400-...") -- true
UUID.to_string(UUID.nil())    -- "00000000-0000-0000-0000-000000000000"
```

---

## JSON

`json.march`: JSON encoding and decoding.

```march
type JsonValue =
    Null
  | Bool(Bool)
  | Number(Float)         -- both ints and floats decode to Number(Float)
  | Str(String)
  | Array(List(JsonValue))
  | Object(List((String, JsonValue)))

Json.parse("{\"key\": 42}")               -- Result(JsonValue, String)
Json.to_string(Object([("x", Number(1.0))]))  -- "{\"x\":1}"
Json.get(obj, "key")                      -- Option(JsonValue)
```

The module is `Json` (not `JSON`), and there is no `encode`/`encode_pretty`;
`to_string` renders a `JsonValue` back to JSON text. `encode_null`/`encode_bool`/
`encode_number`/`encode_int`/`encode_string`/`encode_array`/`encode_object` are
constructor helpers for building a `JsonValue` from a primitive, not string
serializers.

---

## HTTP Client

`http_client.march`: Make HTTP requests.

`Http.get`/`Http.post`/etc are pure: they just parse a URL into a `Request`
(`Result(Request(b), UrlError)`), no network I/O. Actually performing a
request goes through an `HttpClient` client value:

```march
let client = HttpClient.new_client()

let resp = HttpClient.get(client, "https://api.example.com/data")
let resp = HttpClient.post(client, "https://api.example.com/data", body)

-- A custom method/headers request: build with Http, run with HttpClient.
let req  = Result.unwrap(Http.put("https://api.example.com/items/1", json_body))
let req2 = Http.set_header(req, "Content-Type", "application/json")
let resp = HttpClient.run(client, req2)

match resp do
  Ok(r) ->
    println("status: " ++ int_to_string(Http.response_status_code(r)))
    println("body: "   ++ Http.response_body(r))
  Err(e) ->
    println("error")
end
```

---

## File System

`file.march`, `dir.march`, `path.march`:

```march
-- File I/O (Result-based)
File.read("data.txt")              -- Result(String, String)
File.write("out.txt", "content")   -- Result((), String)
File.append("log.txt", "line\n")   -- Result((), String)
File.exists("config.json")         -- Bool
File.delete("temp.txt")            -- Result((), String)
File.copy("src.txt", "dst.txt")    -- Result((), String)

-- Directory
Dir.list("./src")                  -- Result(List(String), String)
Dir.mkdir("./output")              -- Result((), String)
Dir.exists("./data")               -- Bool

-- Path manipulation (pure, no I/O)
Path.join("src", "main.march")     -- "src/main.march"
Path.dirname("src/lib/foo.march")  -- "src/lib"
Path.basename("src/lib/foo.march") -- "foo.march"
Path.extension("foo.march")        -- "march"  (no leading dot)
Path.strip_extension("foo.march")  -- "foo"
Path.is_absolute("/usr/bin")       -- true
```

---

## System

`system.march`: OS and runtime information.

```march
System.os()                -- "macos" | "linux" | "windows"
System.arch()              -- "x86_64" | "arm64"
System.cpu_count()         -- number of logical CPUs
System.monotonic_time()    -- Int (nanoseconds, for timing)
System.env("HOME")         -- Option(String)
System.put_env("KEY", "val")
System.argv()              -- List(String)
System.cwd()               -- String
System.pid()               -- Int (OS process ID)
System.exit(0)             -- terminate with exit code
System.cmd("ls", ["-la"])  -- Result(ProcessResult, String)
                            -- unpack with System.stdout/stderr/exit_code/ok
```

---

## Logger

`logger.march`: Structured logging.

```march
Logger.info("server started")
Logger.warn("connection retry")
Logger.error("database unreachable")
Logger.debug("processing request")
Logger.with_context(fn () ->
  Logger.put_context("request_id", "abc123")
  Logger.info("request received")
  process_request()
)
```

---

## Vault

`vault.march`: Process-local key-value store backed by a mutable hash table. Used extensively in the stdlib for global mutable state.

A handle is `Vault(v)`, phantom in the type of the values the table stores, so
a table written at one type cannot be read back at another.

```march
let t = Vault.new("counter_table")    -- Vault(v); or Vault.open(name), idempotent

Vault.put(t, "counter", 0)       -- pins v := Int
Vault.get(t, "counter")          -- Option(Int)
Vault.update(t, "counter", fn n -> n + 1)   -- fn is (v) -> v
Vault.delete(t, "counter")
Vault.keys(t)                    -- List(String) — all live keys (no prefix filter)
Vault.all(t)                     -- List((String, Int))
```

The element type is fixed where the handle is bound: a `let`-bound handle does
not let-generalize, because a Vault is a process-global mutable cell. Two
doors stay element-erased on purpose: `new`/`open`/`whereis`, which mint a
handle from a *name* and so choose `v` rather than check it, and the
`ns_set`/`ns_get`/`ns_drop` namespace-string API, which has no handle to carry
`v`. `Config` (a heterogeneous store by design) opts out explicitly with a
`: Vault(v)` annotation on its table getters.

---

## Enum

`enum.march`: Elixir-inspired lazy enumeration over any `Iterable`.

```march
Enum.map(items, fn x -> x * 2)
Enum.filter(items, fn x -> x > 0)
Enum.fold(items, 0, fn acc -> fn x -> acc + x)   -- combiner is curried
Enum.sort_by(items, fn a -> fn b -> a < b)        -- comparator: a < b
Enum.chunk_every(items, 3)     -- group into chunks of 3
Enum.chunk_by([1, 1, 2, 2, 3], fn x -> x)  -- [(1, [1, 1]), (2, [2, 2]), (3, [3])]
Enum.zip(items_a, items_b)
Enum.dedup(items)              -- remove consecutive duplicates
Enum.uniq(items)               -- remove all duplicates
Enum.take_while(items, pred)
Enum.drop_while(items, pred)
Enum.sum(nums)
Enum.product(nums)
Enum.scan(items, 0, fn acc -> fn x -> acc + x)
Enum.with_index(items)         -- [(x, 0), (y, 1), ...]
Enum.frequencies(items)        -- List((a, Int)): count of each item
Enum.min_by(items, fn x -> x.score)   -- Option(a)
Enum.max_by(items, fn x -> x.score)   -- Option(a)
```

---

## Duration

`duration.march`: Time-span arithmetic.

```march
let d = Duration.seconds(30)
let h = Duration.hours(2)
let w = Duration.weeks(1)

Duration.add(d, h)
Duration.subtract(h, d)
Duration.multiply(d, 3)
Duration.compare(d, h)     -- Int: negative, 0, positive
Duration.format(d)         -- "30 seconds"
Duration.to_milliseconds(d)  -- 30000  (Duration.milliseconds(n) is a *constructor*, not this accessor)
```

---

## URI

`uri.march`: URI parsing and construction. The module is `Uri` (not `URI`).

```march
let u = Uri.parse("https://example.com/path?k=v")
-- URI(scheme, host, port, path, query, fragment) — a plain ADT value, not a Result

Uri.scheme(u)                 -- "https"
Uri.host(u)                   -- "example.com"
Uri.path(u)                   -- "/path"
Uri.query(u)                  -- "k=v"
Uri.encode("hello world")     -- "hello%20world"
Uri.decode("hello%20world")   -- "hello world"
Uri.decode_query("k=v&a=b")   -- [("k", "v"), ("a", "b")]
```

---

## Js.Dom (JS only)

`dom.march`: Browser DOM bindings for `--target js` builds. Auto-loaded; no import needed.

```march
-- Query
Js.Dom.find("my-id")              -- Option(Js.Dom.Node)
Js.Dom.select("#nav")             -- Option(Js.Dom.Node)
Js.Dom.select_all(".item")        -- List(Js.Dom.Node)
Js.Dom.body()                     -- Js.Dom.Node

-- Construction
Js.Dom.create("div")              -- Js.Dom.Node
Js.Dom.text_node("hello")         -- Js.Dom.Node

-- Tree
Js.Dom.append(parent, child)
Js.Dom.prepend(parent, child)
Js.Dom.remove(el)
Js.Dom.remove_child(parent, child)

-- Content
Js.Dom.set_text(el, "hello")
Js.Dom.set_html(el, "<b>bold</b>")
Js.Dom.get_text(el)               -- String
Js.Dom.get_html(el)               -- String

-- Attributes and style
Js.Dom.set_attr(el, "data-x", "1")
Js.Dom.get_attr(el, "data-x")    -- Option(String)
Js.Dom.remove_attr(el, "data-x")
Js.Dom.add_class(el, "active")
Js.Dom.remove_class(el, "active")
Js.Dom.toggle_class(el, "open")
Js.Dom.set_style(el, "color", "red")

-- Events (Js.Dom.listen, not Js.Dom.on — there is no on_keydown/dispatch wrapper;
-- listen for "keydown" directly)
Js.Dom.listen(el, "click", fn ev -> ...)
Js.Dom.listen(el, "keydown", fn ev -> ...)
Js.Dom.prevent_default(ev)
Js.Dom.stop_propagation(ev)
Js.Dom.taps(el)                   -- List((Int, Int)) — drain buffered taps (poll per frame)
Js.Dom.key_presses()              -- List(String) — drain buffered keydown keys (poll per frame)
Js.Dom.store_get("save")          -- Option(String) — localStorage read
Js.Dom.store_set("save", data)    -- localStorage write
Js.Dom.pointer_pos(el)            -- (Int, Int) — live cursor position over el
Js.Dom.window_size()              -- (Int, Int) — window.innerWidth/innerHeight
```

`Js.Dom` requires `needs Ffi` because DOM calls are implemented as JS externs. It is only valid in `--target js` builds.

---

## Js.Canvas (JS only)

`canvas.march`: 2D drawing bindings for `--target js` builds, wrapping the browser's `CanvasRenderingContext2D`. Auto-loaded; no import needed.

```march
-- Setup
Js.Dom.find("my-canvas")                          -- Option(Node), from Js.Dom
Js.Canvas.get_context(node)                       -- Option(Context)

-- State stack
Js.Canvas.save(ctx)
Js.Canvas.restore(ctx)
Js.Canvas.translate(ctx, 10.0, 10.0)
Js.Canvas.rotate(ctx, 0.5)
Js.Canvas.scale(ctx, 2.0, 2.0)

-- Style
Js.Canvas.set_fill_style(ctx, "#e74c3c")
Js.Canvas.set_stroke_style(ctx, "#3498db")
Js.Canvas.set_line_width(ctx, 2.0)
Js.Canvas.set_global_alpha(ctx, 0.8)
Js.Canvas.set_font(ctx, "16px sans-serif")

-- Rects
Js.Canvas.clear_rect(ctx, 0.0, 0.0, 480.0, 360.0)
Js.Canvas.fill_rect(ctx, 10.0, 10.0, 80.0, 40.0)
Js.Canvas.stroke_rect(ctx, 10.0, 10.0, 80.0, 40.0)

-- Paths
Js.Canvas.begin_path(ctx)
Js.Canvas.move_to(ctx, 0.0, 0.0)
Js.Canvas.line_to(ctx, 100.0, 100.0)
Js.Canvas.arc(ctx, 50.0, 50.0, 20.0, 0.0, 6.283185307179586)
Js.Canvas.quadratic_curve_to(ctx, 60.0, 0.0, 120.0, 40.0)
Js.Canvas.bezier_curve_to(ctx, 20.0, 0.0, 80.0, 0.0, 100.0, 40.0)
Js.Canvas.fill(ctx)
Js.Canvas.stroke(ctx)

-- Text
Js.Canvas.fill_text(ctx, "score: 0", 10.0, 20.0)
Js.Canvas.stroke_text(ctx, "score: 0", 10.0, 20.0)
Js.Canvas.set_text_align(ctx, "center")

-- Images
Js.Canvas.load_image("sprite.png")                -- Result(Image, String)
Js.Canvas.draw_image(ctx, img, 0.0, 0.0)
Js.Canvas.draw_image_scaled(ctx, img, 0.0, 0.0, 64.0, 64.0)
```

`Js.Canvas` requires `needs Ffi` because drawing calls are implemented as JS externs. It is only valid in `--target js` builds. Pair with `Js.Dom.event_x`/`Js.Dom.event_y` for canvas-relative pointer coordinates from a `"pointerdown"`/`"click"` listener.

---

## Js.Audio (JS only)

`audio.march`: procedural sound-effect synthesis for `--target js` builds, wrapping the browser's Web Audio API. Sounds are synthesized on the fly (tones, sweeps, filtered noise) rather than loaded from files: no assets, no licensing. Auto-loaded; no import needed.

```march
Js.Audio.create()                                 -- Ctx
Js.Audio.resume(actx)                             -- unlock output; call from a user-gesture handler
Js.Audio.beep(actx, 440.0, 0.1, "sine")            -- flat tone: "sine"/"square"/"sawtooth"/"triangle"
Js.Audio.sweep(actx, 200.0, 800.0, 0.2, "square")  -- frequency ramp (chirps, risers, fall-offs)
Js.Audio.noise_burst(actx, 0.15, 600.0)            -- filtered white noise (impacts, explosions)
Js.Audio.set_volume(actx, 0.5)                     -- master gain 0.0 (mute) to 1.0
```

`Js.Audio` requires `needs Ffi` and is only valid in `--target js` builds. Browsers block audio output until a user gesture occurs on the page; call `resume` from inside your first tap/click handler (game loops that already gate their first frame on a tap, like a "tap to start" screen, get this for free).

---

## Distributed OTP (cluster networking)

These modules implement the distributed-OTP transport layer (P1). They are stdlib modules loaded on demand via the module registry; no `forge.toml` dependency needed.

### NodeIdentity

`node_identity.march`: A node's stable identity for the cluster.

```march
type Identity = { name : String, node_id : String, incarnation : Int }

NodeIdentity.make("worker@host", pubkey, 0)
-- { name: "worker@host", node_id: sha256(pubkey), incarnation: 0 }

NodeIdentity.encode(id)        -- List(Int)  (MessagePack bytes)
NodeIdentity.decode(bytes)     -- Result(Identity, String)
```

### NetFrame

`net_frame.march`: Length-prefixed framing over TCP.

```march
NetFrame.encode(payload)       -- List(Int)  (4-byte header + payload)
NetFrame.decode(buf)           -- Option((List(Int), List(Int)))
```

### ClusterAuth

`cluster_auth.march`: Shared-secret HMAC challenge/response.

```march
ClusterAuth.prove(secret, nonce)         -- String (HMAC-SHA256 hex)
ClusterAuth.verify(secret, nonce, proof) -- Bool
```

### Handshake

`handshake.march`: Pure authenticated handshake protocol (no I/O).

```march
Handshake.make_hello(identity, nonce)    -- Handshake.Hello
Handshake.encode_hello(hello)            -- List(Int)
Handshake.decode_hello(bytes)            -- Result(Hello, String)
Handshake.authenticate(secret, our_nonce, peer, peer_proof)
-- Result(NodeIdentity.Identity, String)
```

### PeerRegistry

`peer_registry.march`: One-connection-per-peer table.

```march
type Peer = { node_id : String, identity : NodeIdentity.Identity, fd : Int }
type Registry = Registry(Map(String, Peer))

PeerRegistry.empty()
PeerRegistry.add(reg, peer)           -- Registry
PeerRegistry.lookup(reg, node_id)     -- Option(Peer)
PeerRegistry.remove(reg, node_id)     -- Registry
PeerRegistry.peers(reg)               -- List(Peer)
```

### NetKernel

`net_kernel.march`: TCP socket transport for the net-kernel (framing + handshake).

```march
NetKernel.fresh_nonce()               -- String (random hex)
NetKernel.send_frame(fd, payload)     -- Result((), String)
NetKernel.recv_frame(fd, buf)         -- Result((List(Int), List(Int)), String)
NetKernel.handshake(fd, my_id, secret, my_nonce)
-- Result(NodeIdentity.Identity, String)
```

### ClusterConn

`cluster_conn.march`: Connection lifecycle: dial or accept, handshake, register.

Requires `needs IO.NetListen` (for `tcp_listen`/`tcp_accept` builtins).

```march
ClusterConn.listen(port)
-- Result(Int, String)  -- listen_fd

ClusterConn.connect_to_peer(reg, host, port, my_id, secret)
-- Result((PeerRegistry.Registry, PeerRegistry.Peer), String)

ClusterConn.accept_one(reg, listen_fd, my_id, secret)
-- Result((PeerRegistry.Registry, PeerRegistry.Peer), String)
```

`tcp_listen` and `tcp_accept` are builtins in the `IO.NetListen` capability group:

```march
tcp_listen(port)       : Result(Int, String)  -- bind + listen, return fd
tcp_accept(listen_fd)  : Result(Int, String)  -- block until client, return fd
```

---

## Module Quick Reference

| Module | Purpose |
|--------|---------|
| `Prelude` | Auto-imported helpers |
| `List` | Singly-linked list operations |
| `String` | String manipulation |
| `Map` | HAMT-backed key-value map |
| `Set` | HAMT-backed set |
| `Option` | Maybe type helpers |
| `Result` | Either type helpers |
| `Enum` | Lazy enumeration |
| `Sort` | Timsort, Introsort, specialized small sorts |
| `Math` | Arithmetic and transcendental functions |
| `IO` | Console I/O |
| `System` | OS/runtime info |
| `File` | File I/O |
| `Dir` | Directory operations |
| `Path` | Path manipulation |
| `Crypto` | SHA, HMAC, PBKDF2, random |
| `UUID` | UUID v4/v5 |
| `Json` | JSON encode/decode |
| `Base64` | Base64 encode/decode |
| `Uri` | URI parsing/construction |
| `Duration` | Time-span arithmetic |
| `Logger` | Structured logging |
| `Vault` | Process-local KV store |
| `Http` | HTTP client |
| `HttpServer` | HTTP/WebSocket server |
| `Task` | Structured concurrency |
| `Seq` | Lazy sequences |
| `IOList` | Lazy string builder |
| `Random` | Random number generation |
| `Regex` | Regular expressions |
| `AhoCorasick` | Multi-pattern string search (build once, scan many) |
| `BigInt` | Arbitrary-precision integers |
| `Decimal` | Exact decimal arithmetic |
| `Csv` | CSV parsing |
| `DateTime` | Date and time |
| `Js.Dom` | Browser DOM bindings (JS only, auto-loaded for `--target js`) |
| `Js.Canvas` | 2D canvas drawing bindings (JS only, auto-loaded for `--target js`) |
| `NodeIdentity` | Cluster node identity (name, node\_id, incarnation) |
| `NetFrame` | Length-prefixed TCP framing |
| `ClusterAuth` | HMAC shared-secret challenge/response |
| `Handshake` | Pure authenticated handshake protocol |
| `PeerRegistry` | One-connection-per-peer table |
| `NetKernel` | TCP framing + handshake transport |
| `ClusterConn` | Dial/accept + handshake + register lifecycle |
| `Gen` | Property test generators (Hedgehog-style) |
| `Check` | Property test runner with shrinking |
| `Test` | Test assertion helpers |

---

## Next Steps

- [Property Testing]({{ site.baseurl }}/docs/property-testing/): write property-based tests with `Gen` and `Check`
- [REPL]({{ site.baseurl }}/docs/repl/): explore the stdlib interactively
- [Interfaces]({{ site.baseurl }}/docs/interfaces/): how stdlib types implement interfaces
- [Tooling]({{ site.baseurl }}/docs/tooling/): `forge search` to find functions by type or name
