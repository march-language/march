# C FFI — type-directed generated codecs (records & variants)

**Status:** design approved 2026-06-21; implementing. Builds on FFI Phase 9
(record/variant ABI accessors). Companion to `specs/2026-06-19-c-ffi-abi-design.md`
§6.4 and `specs/c-ffi-gaps.md`.

## Goal

Eliminate the by-hand `march_variant_field`/`march_make_record` marshalling a
binding author writes today. From the `type` decls reachable from an `extern`
block, generate repr-C **mirror structs** plus `march_decode_T`/`march_encode_T`
so the author writes pure C over plain structs; `march_value` only appears in the
generated boundary glue.

## Mechanism — forge generator (no compiler-pipeline changes)

`forge ffi gen-c <file.march>` is extended. It already parses `extern` blocks;
now it also:

1. Collects `DType` record/variant decls in the file.
2. Computes the transitive closure of record/variant types reachable from any
   `extern` parameter or return type.
3. Topologically orders that closure (a nested type's struct is defined before
   the struct that embeds it).
4. Emits, ahead of the shim functions, a **codec preamble**: one mirror struct
   per type + `static` `march_decode_T` / `march_encode_T`, implemented over the
   Phase 9 accessors (`march_variant_tag`/`variant_field`/`record_field`,
   `march_make_variant`/`make_record`).
5. Wires shim bodies: a record/variant **param** is decoded into a local at the
   top of the function (`T_c name = march_decode_T(name_v);`); a record/variant
   **return** is built with `march_encode_T` from a `T_c result`.

Single self-contained `.c` (same model as Phase 7). A `--types-header` split is a
trivial future add (YAGNI now).

## Representation mapping (static, from the type decl)

Records use **name-sorted** field order (March's layout); variants use
**declaration-order** tags. Slots carry March's native per-field representation.

| March field type | Mirror struct field | decode | encode |
|---|---|---|---|
| `Int`/`Bool` | `int64_t` | raw slot | raw slot |
| `Float` | `double` | `march_get_float` | `march_make_float` |
| `String`/`Bytes` | `march_slice` | `march_str_borrow` (borrow) | `march_str_new` (own) |
| nested record/variant (in closure) | `T2_c` | `march_decode_T2` | `march_encode_T2` |
| anything else (`Option`/`Result`/`resource`/`List`/type-var) | `march_value` | raw slot passthrough | raw slot passthrough |

The last row is a deliberate v1 boundary: `Option`/`Result`/`resource`/`List`
*fields* are exposed as the raw `march_value` (author uses `march_some`/`none`/
`ok`/`err`/`march_resource_get` + Phase 9 accessors). Primitives, `String`/
`Bytes`, and nested records/variants are fully typed. Top-level `Option`/`Result`
extern params/returns keep their existing first-class gen-c handling.

Record descriptors generated for `march_make_record` mirror the compiler's
`shape_kind_char` + name-sort, so the interned shape id matches March's own
records of that type.

### Variant mirror

```c
typedef struct {
    int32_t tag;                         /* declaration-order ctor index */
    union { struct { int64_t f0; } Circle;
            struct { int64_t f0, f1; } Rect; } u;
} Shape_c;
```

`tag` + per-ctor field tuple. Decode switches on `march_variant_tag`; encode
switches on `o.tag`, packs the active ctor's fields, and calls
`march_make_variant(tag, n, fields)`.

## Testing

- **forge unit** (`forge/test/test_forge.ml`): generated `.c` contains the mirror
  struct, a nested-type decode/encode, and a variant tagged union; and it
  **compiles** (`cc -c -I runtime`).
- **end-to-end native** (`test/native/ffi_codec.march` + dune rule, Phase 9
  pattern): a shim built only from generated codecs round-trips a nested record
  and a multi-field variant through real logic; diff stdout.

## Scope / non-goals

In: records + variants, nesting, primitive/`String`/`Bytes` fields, the
`march_value` passthrough for other field kinds. Out (deferred, tracked in
`c-ffi-gaps.md`): fully-typed `Option`/`Result`/`List` field decoding, List-copy
(§6.6), `raw` (§7), the Rust `#[derive]` layer (separate follow-on reusing this
ABI), compiler-emitted boundaries.
