> Part of the March Language Reference; see [specs/lang/index.md](index.md).

# Standard Library: Overview

This chapter orients you in March's standard library. It is **not** the API
reference; the full, per-module, per-function documentation is generated from
the stdlib sources and published under [`docs/docs/stdlib/`](../../docs/docs/stdlib/)
(one page per module). This chapter explains the library's *shape* so you know
where to look.

## The prelude (always in scope)

A small set of functions is auto-imported into every module; no `use` needed.
These include `panic`/`todo`/`unreachable`, `unwrap`/`unwrap_or`, the core list
operations (`head`/`tail`/`length`/`reverse`/`map`/`filter`/`fold_left`), and
combinators (`identity`/`compose`/`flip`/`const`). Everything else is reached by
its module name (e.g. `List.sort_by`, `Map.insert`, `Json.parse`).

## Module categories

The library is organized by domain. The main families:

- **Core data**: `Option`, `Result`, `List`, `Tuple`, `Range`.
- **Collections**: `Map` (AVL), `HAMT`, `Set`, `SortedSet`, `OrderedMap`,
  `Queue`, `Deque`, `Array`, `NativeArray`, `RRB` (persistent vector).
  `NativeArray` pairs with `Simd`, fixed 128-bit vector types
  (`F32x4`/`F64x2`/`I32x4`/`I64x2`/`U8x16`) for guaranteed-vectorized numeric
  kernels; see `docs/simd-vectorization.md`.
- **Text**: `String`, `Char`, `IOList`, `Regex`, `CSV`, `Bytes`.
- **Numbers**: `Math`, `BigInt`, `Decimal`, `Stats`, `Random`, `DateTime`,
  `Duration`.
- **Encoding / crypto**: `Base64`, `Crypto`, `UUID`, `URI`, `JSON`,
  `MsgPack`, `Compress`.
- **Data formats**: `TOML`, `YAML`, `XML`.
- **IO / files**: `File`, `Dir`, `Path`, `Env`, `Logger`.
- **Networking / HTTP**: `Http`, `HttpTransport`, `HttpClient`, `HttpServer`,
  `TLS`, `WebSocket`, `DNS`.
- **Actors / concurrency**: `Process`, `Actor`, `Task`, `Channel`, `PubSub`,
  `Presence`, `Flow`, `Seq`, `Parallel`.
- **Distributed / OTP**: clustering, membership (SWIM), CRDTs, vector clocks,
  consistent hashing, global registries.
- **Functional utilities**: `Enum`, `Sort`, `Iterable`, `Gen`
  (property-test generators).
- **Markup / data science**: `Html`, `Sigil`, `DataFrame`, `Plot`.
- **Testing**: `Test`.

## Conventions

- **Error signaling**: fallible operations return `Option`/`Result`; functions
  that *cannot* fail on well-formed input (e.g. `List.nth`) panic on misuse,
  with a `*_opt` variant returning `Option` where a total version is useful.
- **Uncurried collections**: collection functions take the collection as the
  first argument (`List.map(xs, f)`), which composes with the pipe operator
  (`xs |> List.map(f)`).
- **Discovery**: use `forge search <name>` (Hoogle-style: by name, type
  signature, or doc keyword) to find functions across the whole library.

For the authoritative per-function signatures, types, and doctests, always
consult the generated API reference under
[`docs/docs/stdlib/`](../../docs/docs/stdlib/).
