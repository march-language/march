# Serialization — MessagePack stdlib module

**Date:** 2026-04-18
**Status:** In progress

---

## Overview

March needs a compact binary serialization format to complement the JSON
module.  JSON is the right choice for human-readable interchange and HTTP
APIs, but binary formats are significantly more compact and faster to
encode/decode when:

- Communicating between March services over internal channels or TCP
- Caching structured values in Vault or Redis
- Embedding structured payloads in WebSocket frames without JSON overhead

The selected format is **MessagePack** (https://msgpack.org/), a compact
binary format that mirrors JSON's type system while adding a dedicated
binary blob type.  MessagePack is widely supported across languages
(Python, Go, Rust, Elixir, JS) so March services can exchange data with
non-March peers without bespoke parsers.

---

## Type

```march
type Value
  = Null
  | Bool(Bool)
  | Int(Int)
  | Str(String)
  | Bin(List(Int))
  | Array(List(Value))
  | Map(List((Value, Value)))
```

**No `Float` in v1.**  Encoding IEEE 754 bit patterns requires a
`float_bits : Float -> Int` builtin that does not yet exist.  Floats can
be serialized by the caller as `Str(float_to_string(f))` or
`Int(float_to_int(f))` until the builtin lands.  A v2 addendum will add
`Float(Float)` once `float_bits` is available.

**`Bin` uses `List(Int)` (byte values 0–255)**, not the `Bytes` newtype.
Callers with `Bytes` values use `Bytes.to_list(b)` to unwrap.  Keeping
`Msgpack` self-contained avoids ordering constraints in the stdlib load
list and makes the module easier to test in isolation.

**`Map` keys are `Value`**, not `String`.  MessagePack allows arbitrary key
types; constraining to `String` would lose interop with maps encoded by
other languages.  Pure-string maps remain ergonomic: `Map([("k", Str("v"))])`.

---

## API

```march
mod Msgpack do

  type Value
    = Null
    | Bool(Bool)
    | Int(Int)
    | Str(String)
    | Bin(List(Int))
    | Array(List(Value))
    | Map(List((Value, Value)))

  -- Core
  fn encode(v : Value) : List(Int)
  fn decode(bs : List(Int)) : Result(Value, String)
  fn decode_all(bs : List(Int)) : Result(List(Value), String)

  -- Convenience constructors (mirror Json module style)
  fn null() : Value
  fn bool(b : Bool) : Value
  fn int(n : Int) : Value
  fn str(s : String) : Value
  fn bin(bs : List(Int)) : Value
  fn array(xs : List(Value)) : Value
  fn map(kvs : List((Value, Value))) : Value

end
```

**`encode`** returns `List(Int)` (bytes 0–255).  Callers that need `Bytes`
wrap with `Bytes.from_list(Msgpack.encode(v))`.

**`decode`** consumes all input; returns `Err` if there are trailing bytes.
Use `decode_all` to parse a sequence of concatenated messages.

**`decode_all`** parses zero or more values from a byte stream, returning
`Ok([])` on empty input.  Useful for batch/framing protocols.

---

## MessagePack format subset

The implementation covers the common cases used in practice.  Exotic cases
(float32/64, ext types, fixext) return `Err` from `decode`.

### Integer encoding (most compact wins)

| Condition | Format | Bytes |
|-----------|--------|-------|
| `0 ≤ n ≤ 127` | positive fixint | 1 |
| `−32 ≤ n ≤ −1` | negative fixint | 1 |
| `−128 ≤ n ≤ −33` | int8 `0xd0` | 2 |
| `128 ≤ n ≤ 255` | uint8 `0xcc` | 2 |
| `−32768 ≤ n ≤ −129` | int16 `0xd1` | 3 |
| `256 ≤ n ≤ 65535` | uint16 `0xcd` | 3 |
| `−2³¹ ≤ n ≤ −32769` | int32 `0xd2` | 5 |
| `65536 ≤ n ≤ 2³²−1` | uint32 `0xce` | 5 |
| `n < −2³¹` | int64 `0xd3` | 9 |
| `n ≥ 2³²` | uint64 `0xcf` | 9 |

**March `Int` is 63-bit** (OCaml native int on 64-bit).  Values outside
`[−2⁶², 2⁶²−1]` cannot be represented; encoding such values silently
truncates (unreachable in practice since March cannot produce them).

### String encoding

Strings are encoded as UTF-8 bytes.  March's `string_split(s, "")` gives
byte-level access (each element is a single-byte string), so multi-byte
UTF-8 sequences are preserved correctly.

| Length | Format | Overhead |
|--------|--------|----------|
| 0–31 bytes | fixstr `0xa0`–`0xbf` | 1 |
| 32–255 bytes | str8 `0xd9` | 2 |
| 256–65535 bytes | str16 `0xda` | 3 |
| 65536+ bytes | str32 `0xdb` | 5 |

### Binary encoding

| Length | Format | Overhead |
|--------|--------|----------|
| 0–255 bytes | bin8 `0xc4` | 2 |
| 256–65535 bytes | bin16 `0xc5` | 3 |
| 65536+ bytes | bin32 `0xc6` | 5 |

### Array / Map encoding

| Length | Format | Overhead |
|--------|--------|----------|
| 0–15 | fixarray/fixmap | 1 |
| 16–65535 | array16/map16 | 3 |
| 65536+ | array32/map32 | 5 |

---

## Implementation layers

```
stdlib/msgpack.march     pure March: encoder + decoder
test/stdlib/test_msgpack.march    unit tests
test/stdlib/test_properties.march  property tests (round-trip)
```

No C runtime component is needed.  MessagePack's byte-level operations map
cleanly onto `int_and`, `int_or`, `int_shl`, `int_shr` and ordinary
arithmetic — all already available as March builtins.

---

## Property tests

Round-trip is the primary invariant: `decode(encode(v)) == Ok(v)` for all `v`.

```march
-- Null
decode(encode(Null)) == Ok(Null)

-- Bool
Check.all(Gen.bool(), fn b ->
  Msgpack.decode(Msgpack.encode(Msgpack.Bool(b))) == Ok(Msgpack.Bool(b))
)

-- Int (fixint range, int32, int64)
Check.all(Gen.int(-32, 127), fn n ->  ...)
Check.all(Gen.int(-2147483648, 2147483647), fn n -> ...)
Check.all(Gen.int(-4611686018427387904, 4611686018427387903), fn n -> ...)

-- Str (ASCII, via Gen.lowercase_string)
Check.all(Gen.lowercase_string(), fn s -> ...)

-- Bin
Check.all(Gen.list(Gen.int(0, 255)), fn bs -> ...)

-- Array (flat, to avoid depth explosion)
Check.all(Gen.list(Gen.int(-100, 100)), fn ns ->
  let v = Msgpack.Array(List.map(ns, fn n -> Msgpack.Int(n)))
  Msgpack.decode(Msgpack.encode(v)) == Ok(v)
)

-- Map (string keys, int values)
Check.all(Gen.list(Gen.tuple2(Gen.lowercase_string(), Gen.int(-100, 100))), fn pairs ->
  let kvs = List.map(pairs, fn p -> match p do (k, v) -> (Msgpack.Str(k), Msgpack.Int(v)) end)
  let v = Msgpack.Map(kvs)
  Msgpack.decode(Msgpack.encode(v)) == Ok(v)
)
```

Additional properties:
- `encode` always produces a non-empty list
- Fixint range encodes in exactly 1 byte
- Bool encodes in exactly 1 byte
- Null encodes in exactly 1 byte

---

## TDD approach

Tests are written first and drive the implementation.  The order:

1. `Null` encode/decode
2. `Bool` encode/decode
3. `Int` fixint range → int8/uint8 → int16/uint16 → int32/uint32 → int64
4. `Str` fixstr → str8 → str16
5. `Bin` bin8 → bin16
6. `Array` fixarray → array16 (elements: Null, Bool, Int)
7. `Map` fixmap → map16 (string keys, any values)
8. Nested structures (Array of Maps, Map of Arrays)
9. `decode_all` on concatenated encodings
10. Error cases: empty input, truncated data, unknown format byte

---

## Files changed

| File | Change |
|------|--------|
| `stdlib/msgpack.march` | Add (new stdlib module) |
| `bin/main.ml` | Add `msgpack.march` to stdlib load order after `bytes.march` |
| `test/stdlib/test_msgpack.march` | Add (unit tests) |
| `test/stdlib/test_properties.march` | Add Msgpack round-trip property tests |
| `test/test_stdlib_march.ml` | Add msgpack test case + stdlib decl |
| `specs/plans/serialization-plan.md` | This document |
| `specs/todos.md` | Move item to Done |
| `specs/progress.md` | Update feature list |

---

## Out of scope

- **Float encoding** — requires `float_bits : Float -> Int` builtin (v2)
- **Ext types** — user-defined extensions; decode returns `Err` for ext bytes
- **Streaming decoder** — `decode_all` covers batch use; true streaming
  requires an iterator/pull interface beyond the current stdlib
- **CBOR / Protobuf** — different trade-offs; can be separate modules
