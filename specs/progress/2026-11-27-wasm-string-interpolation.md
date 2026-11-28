# Freestanding WebAssembly string interpolation

The compiler emits `march_string_concat3` for three interpolation parts and
`march_string_concat_n` for four or more. The freestanding WebAssembly
runtime provided neither symbol, which left browser applications such as
Ur dependent on a runtime patch.

Both symbols now use the same two-pass implementation. It measures the
result, bounds the allocation, and copies each borrowed operand once into
the output. The bump allocator only retains the output buffer and header.

A wasm32 probe linked a compiler-emitted function containing both call
shapes. Linking failed on both missing symbols with the previous runtime.
The updated runtime linked and returned the expected bytes with an empty
operand, an embedded NUL, and a UTF-8 character.
