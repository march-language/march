# P3 todo: SIMD bullet reworded, MCP and multi-lib FFI split out

Docs-only. `specs/todos/2026-06-19-p3-language-features.md` still described fixed-width SIMD
vector types as unbuilt, but the 128-bit ones shipped (`stdlib/simd.march`: `F32x4`, `F64x2`,
`I32x4`, `I64x2`, `U8x16`; `specs/progress/2026-08-10-simd-vector-types.md`). The bullet now
covers only the 256-bit widths (`f32x8`, `i32x8`).

The two large items that had no relation to the rest were split into their own files, one
item per file per `specs/todos/README.md`: `2026-06-19-mcp-server.md` and
`2026-06-19-ffi-multi-lib-array-of-tables.md`. The parent keeps the remaining FFI gaps and
the 256-bit SIMD item.
