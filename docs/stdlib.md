---
layout: page
title: Standard Library
nav_order: 12
---

# Standard Library

March ships with 57 stdlib modules covering collections, strings, I/O, HTTP, cryptography, and more. This page provides an overview and quick reference for the most commonly used modules.

All stdlib modules are available without any import statement — use qualified access (`List.map`, `String.length`, etc.) or `import`/`use` to bring names into scope.

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

`list.march` — 508 lines. The standard singly-linked list.

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
List.nth([10, 20, 30], 1)            -- 20  (0-indexed)
List.nth_opt([10, 20], 5)            -- None

-- Predicates
List.is_empty([])                    -- true
List.length([1, 2, 3])               -- 3
List.any([1, 2, 3], fn x -> x > 2)  -- true
List.all([2, 4, 6], fn x -> x % 2 == 0)  -- true
List.member(2, [1, 2, 3])           -- true

-- Transformation
List.map([1, 2, 3], fn x -> x * 2)          -- [2, 4, 6]
List.filter([1, 2, 3, 4], fn x -> x % 2 == 0) -- [2, 4]
List.filter_map(xs, fn x -> if x > 0 do Some(x * 2) else None end)
List.flat_map([1, 2, 3], fn x -> [x, x * 10])  -- [1, 10, 2, 20, 3, 30]
List.reverse([1, 2, 3])              -- [3, 2, 1]
List.append([1, 2], [3, 4])         -- [1, 2, 3, 4]
List.concat([[1, 2], [3], [4, 5]])   -- [1, 2, 3, 4, 5]

-- Folds
List.fold_left(0, [1, 2, 3], fn acc x -> acc + x)   -- 6
List.fold_right([1, 2, 3], 0, fn x acc -> x + acc)  -- 6
List.scan_left(0, [1, 2, 3], fn acc x -> acc + x)   -- [0, 1, 3, 6]

-- Search
List.find([1, 2, 3], fn x -> x > 1)      -- Some(2)
List.find_index([10, 20, 30], fn x -> x == 20)  -- Some(1)

-- Iteration (side effects)
List.iter([1, 2, 3], fn x -> println(int_to_string(x)))

-- Sorting
List.sort_by([3, 1, 2], fn a b -> a < b)   -- [1, 2, 3]

-- Zipping
List.zip([1, 2, 3], ["a", "b", "c"])  -- [(1, "a"), (2, "b"), (3, "c")]
List.unzip([(1, "a"), (2, "b")])       -- ([1, 2], ["a", "b"])
List.with_index([10, 20, 30])          -- [(0, 10), (1, 20), (2, 30)]

-- Grouping
List.intersperse([1, 2, 3], 0)         -- [1, 0, 2, 0, 3]
List.take(3, [1, 2, 3, 4, 5])         -- [1, 2, 3]
List.drop(2, [1, 2, 3, 4])            -- [3, 4]
List.take_while([1, 2, 3, 4], fn x -> x < 3)   -- [1, 2]
List.drop_while([1, 2, 3, 4], fn x -> x < 3)   -- [3, 4]
List.chunk_by([1, 1, 2, 2, 3], fn a b -> a == b)  -- [[1, 1], [2, 2], [3]]
```

---

## String

`string.march` — String operations.

```march
String.length("hello")              -- 5
String.concat(["a", "b", "c"])      -- "abc"
String.join(["a", "b", "c"], ", ")  -- "a, b, c"
String.split("a,b,c", ",")          -- ["a", "b", "c"]
String.trim("  hello  ")            -- "hello"
String.trim_left("  hi")            -- "hi"
String.trim_right("hi  ")           -- "hi"
String.upcase("hello")              -- "HELLO"
String.downcase("HELLO")            -- "hello"
String.starts_with("hello", "he")   -- true
String.ends_with("hello", "lo")     -- true
String.contains("hello world", "world")  -- true
String.replace("hello", "l", "r")   -- "herro"
String.slice("hello", 1, 3)         -- "el"
String.to_int("42")                 -- Some(42)
String.to_float("3.14")             -- Some(3.14)
String.repeat("ab", 3)              -- "ababab"
String.reverse("hello")             -- "olleh"
String.chars("hi")                  -- ["h", "i"]
```

---

## Map

`map.march` — HAMT-backed persistent hash map. O(1) amortized operations.

```march
-- Construction
let m = Map.empty()
let m2 = Map.singleton("key", 42)
let m3 = Map.from_list([("a", 1), ("b", 2), ("c", 3)])

-- Access
Map.get(m3, "a")         -- Some(1)
Map.get_or(m3, "z", 0)  -- 0
Map.contains_key(m3, "b")  -- true
Map.size(m3)             -- 3
Map.is_empty(m)          -- true

-- Modification (returns new map)
let m4 = Map.insert(m3, "d", 4)
let m5 = Map.remove(m4, "a")

-- Traversal
Map.keys(m3)             -- ["a", "b", "c"] (in some order)
Map.values(m3)           -- [1, 2, 3]
Map.entries(m3)          -- [("a", 1), ("b", 2), ("c", 3)]
Map.fold(0, m3, fn acc k v -> acc + v)   -- 6

-- Transformation
Map.map_values(m3, fn v -> v * 10)   -- {"a": 10, "b": 20, "c": 30}
Map.filter(m3, fn k v -> v > 1)      -- {"b": 2, "c": 3}
Map.merge(m3, m4)                    -- right takes precedence on conflict
Map.merge_with(m3, m4, fn a b -> a + b)  -- custom merge function

-- Converting
Map.to_list(m3)   -- [("a", 1), ("b", 2), ("c", 3)]
```

---

## Set

`set.march` — HAMT-backed persistent set.

```march
let s = Set.from_list([1, 2, 3, 4, 5])
Set.member(3, s)           -- true
Set.insert(6, s)           -- {1,2,3,4,5,6}
Set.delete(3, s)           -- {1,2,4,5}
Set.size(s)                -- 5
Set.union(s1, s2)
Set.intersection(s1, s2)
Set.difference(s1, s2)
Set.to_list(s)             -- [1, 2, 3, 4, 5]
Set.filter(s, fn x -> x % 2 == 0)  -- {2, 4}
```

---

## Option

`option.march` — `Option(a) = None | Some(a)`.

```march
Option.map(Some(5), fn x -> x + 1)     -- Some(6)
Option.map(None, fn x -> x + 1)        -- None
Option.and_then(Some(5), fn x -> if x > 3 do Some(x) else None end)
Option.or(None, Some(42))              -- Some(42)
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

`result.march` — `Result(a, e) = Ok(a) | Err(e)`.

```march
Result.map(Ok(5), fn x -> x + 1)      -- Ok(6)
Result.map(Err("oops"), fn x -> x + 1) -- Err("oops")
Result.map_err(Err("x"), String.upcase) -- Err("X")
Result.and_then(Ok(5), fn x -> Ok(x * 2))   -- Ok(10)
Result.or(Err("x"), Ok(0))            -- Ok(0)
Result.unwrap(Ok(42))                 -- 42  (panics on Err)
Result.unwrap_or(Err("e"), 0)         -- 0
Result.is_ok(Ok(1))                   -- true
Result.is_err(Err("e"))               -- true
Result.to_option(Ok(42))              -- Some(42)
Result.to_option(Err("e"))            -- None
```

---

## IO

`io.march` — Explicit I/O operations.

```march
IO.puts("Hello, World!")         -- print with newline
IO.write("no newline")           -- print without newline
IO.warn("warning message")       -- print to stderr
IO.read_line()                   -- read a line from stdin -> String
IO.gets("> ")                    -- print prompt, read line
IO.inspect(any_value)            -- pretty-print any value with type info
```

The `println` and `print` builtins are also always available.

---

## Math

`math.march` — Mathematical functions.

```march
Math.abs(-5)          -- 5
Math.abs_f(-3.14)     -- 3.14
Math.min(3, 5)        -- 3
Math.max(3, 5)        -- 5
Math.clamp(15, 0, 10) -- 10
Math.sqrt(16.0)       -- 4.0
Math.pow(2.0, 10.0)   -- 1024.0
Math.exp(1.0)         -- 2.718...
Math.log(Math.e)      -- 1.0
Math.log2(8.0)        -- 3.0
Math.log10(1000.0)    -- 3.0
Math.floor(3.7)       -- 3.0
Math.ceil(3.2)        -- 4.0
Math.round(3.5)       -- 4.0
Math.sin(Math.pi /. 2.0)   -- 1.0
Math.cos(0.0)              -- 1.0
Math.pi                    -- 3.14159...
Math.e                     -- 2.71828...
Math.infinity              -- Float infinity
Math.is_nan(0.0 /. 0.0)   -- true
```

---

## Crypto

`crypto.march` — Cryptographic primitives.

```march
Crypto.sha256("hello")              -- hex string
Crypto.sha512("hello")              -- hex string
Crypto.hmac_sha256(key, message)    -- hex string
Crypto.random_bytes(32)             -- List(Int) of random bytes
Crypto.random_hex(16)               -- random hex string (32 chars)
Crypto.base64_encode(bytes)         -- Base64 string
Crypto.base64_decode(s)             -- List(Int)
Crypto.secure_compare(a, b)         -- constant-time equality
Crypto.pbkdf2_sha256(password, salt, iterations, key_len)  -- derived key
```

---

## UUID

`uuid.march` — UUID generation and parsing.

```march
UUID.v4()                     -- generate a random UUID string
UUID.v5(namespace, name)      -- deterministic UUID from namespace+name
UUID.parse("550e8400-...")    -- Option(UUID)
UUID.to_string(uuid)          -- "550e8400-e29b-41d4-a716-446655440000"
UUID.version(uuid)            -- 4
UUID.is_valid("550e8400-...") -- true
UUID.nil()                    -- "00000000-0000-0000-0000-000000000000"
```

---

## JSON

`json.march` — JSON encoding and decoding.

```march
type JsonValue =
  | JNull
  | JBool(Bool)
  | JInt(Int)
  | JFloat(Float)
  | JString(String)
  | JArray(List(JsonValue))
  | JObject(List((String, JsonValue)))

JSON.parse("{\"key\": 42}")          -- Result(JsonValue, String)
JSON.encode(JObject([("x", JInt(1))]))  -- "{\"x\":1}"
JSON.encode_pretty(val)               -- pretty-printed JSON
JSON.get(obj, "key")                  -- Option(JsonValue)
```

---

## HTTP Client

`http_client.march` — Make HTTP requests.

```march
let resp = Http.get("https://api.example.com/data")
let resp = Http.post("https://api.example.com/data", body)
let resp = Http.request({
  method  = "PUT",
  url     = "https://api.example.com/items/1",
  headers = [("Content-Type", "application/json")],
  body    = Some(json_body)
})

match resp do
  Ok(r) ->
    println("status: " ++ int_to_string(r.status))
    println("body: " ++ r.body)
  Err(e) ->
    println("error: " ++ e)
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
Dir.create("./output")             -- Result((), String)
Dir.exists("./data")               -- Bool

-- Path manipulation (pure, no I/O)
Path.join("src", "main.march")     -- "src/main.march"
Path.dirname("src/lib/foo.march")  -- "src/lib"
Path.basename("src/lib/foo.march") -- "foo.march"
Path.extension("foo.march")        -- ".march"
Path.stem("foo.march")             -- "foo"
Path.is_absolute("/usr/bin")       -- true
```

---

## System

`system.march` — OS and runtime information.

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
System.cmd("ls", ["-la"])  -- Result(String, String)
```

---

## Logger

`logger.march` — Structured logging.

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

`vault.march` — Process-local key-value store backed by a mutable hash table. Used extensively in the stdlib for global mutable state.

```march
Vault.put("counter", 0)
Vault.get("counter")          -- Option(a)
Vault.update("counter", fn n -> n + 1)
Vault.delete("counter")
Vault.keys("counter_")        -- List(String) with prefix
Vault.all()                   -- List((String, a))
```

---

## Enum

`enum.march` — Elixir-inspired lazy enumeration over any `Iterable`.

```march
Enum.map(items, fn x -> x * 2)
Enum.filter(items, fn x -> x > 0)
Enum.fold(items, 0, fn acc x -> acc + x)
Enum.sort(items)
Enum.sort_by(items, fn x -> x.name)
Enum.chunk_every(items, 3)     -- group into chunks of 3
Enum.zip(items_a, items_b)
Enum.dedup(items)              -- remove consecutive duplicates
Enum.uniq(items)               -- remove all duplicates
Enum.take_while(items, pred)
Enum.drop_while(items, pred)
Enum.sum(nums)
Enum.product(nums)
Enum.scan(items, 0, fn acc x -> acc + x)
Enum.with_index(items)         -- [(0, x), (1, y), ...]
Enum.frequencies(items)        -- Map(a, Int) count of each item
Enum.min_by(items, fn x -> x.score)
Enum.max_by(items, fn x -> x.score)
```

---

## Duration

`duration.march` — Time-span arithmetic.

```march
let d = Duration.seconds(30)
let h = Duration.hours(2)
let w = Duration.weeks(1)

Duration.add(d, h)
Duration.subtract(h, d)
Duration.multiply(d, 3)
Duration.compare(d, h)     -- Int: negative, 0, positive
Duration.format(d)         -- "30s"
Duration.milliseconds(d)   -- 30000
```

---

## URI

`uri.march` — URI parsing and construction.

```march
URI.parse("https://example.com/path?k=v")
-- Result({ scheme, host, port, path, query, fragment })

URI.build({ scheme = "https", host = "example.com", path = "/api", ... })
URI.encode("hello world")     -- "hello%20world"
URI.decode("hello%20world")   -- "hello world"
URI.query_params("k=v&a=b")   -- [("k", "v"), ("a", "b")]
```

---

## Module Quick Reference

| Module | Lines | Purpose |
|--------|-------|---------|
| `Prelude` | — | Auto-imported helpers |
| `List` | 508 | Singly-linked list operations |
| `String` | 364 | String manipulation |
| `Map` | — | HAMT-backed key-value map |
| `Set` | — | HAMT-backed set |
| `Option` | — | Maybe type helpers |
| `Result` | — | Either type helpers |
| `Enum` | 701 | Lazy enumeration |
| `Sort` | 615 | Timsort, Introsort, specialized small sorts |
| `Math` | 193 | Arithmetic and transcendental functions |
| `IO` | 72 | Console I/O |
| `System` | 155 | OS/runtime info |
| `File` | 139 | File I/O |
| `Dir` | 50 | Directory operations |
| `Path` | 91 | Path manipulation |
| `Crypto` | 302 | SHA, HMAC, PBKDF2, random |
| `UUID` | 266 | UUID v4/v5 |
| `JSON` | — | JSON encode/decode |
| `Base64` | 143 | Base64 encode/decode |
| `URI` | 360 | URI parsing/construction |
| `Duration` | 208 | Time-span arithmetic |
| `Logger` | — | Structured logging |
| `Vault` | — | Process-local KV store |
| `Http` | — | HTTP client |
| `HttpServer` | — | HTTP/WebSocket server |
| `Task` | — | Structured concurrency |
| `Seq` | 251 | Lazy sequences |
| `IOList` | 221 | Lazy string builder |
| `Random` | — | Random number generation |
| `Regex` | — | Regular expressions |
| `BigInt` | — | Arbitrary-precision integers |
| `Decimal` | — | Exact decimal arithmetic |
| `CSV` | 100 | CSV parsing |
| `Datetime` | — | Date and time |

---

## Next Steps

- [REPL](repl.md) — explore the stdlib interactively
- [Interfaces](interfaces.md) — how stdlib types implement interfaces
- [Tooling](tooling.md) — `forge search` to find functions by type or name
