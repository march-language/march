# Runtime declarations for WebAssembly modules

WebAssembly output starts with a small runtime preamble. Calls to additional
runtime functions still need declarations when a host supplies their C
implementations or when the linker will discard the calling function.

Module emission now looks up reached C symbols in the shared runtime signature
table and adds declarations for symbols the module has yet to define or
declare. Inline native array accesses register their out-of-line fallback
calls with the same symbol tracker.

The regression checks that a native array constructor and access fallback
have declarations and an unused sort does not. A declaration describes a
signature. The host must still provide the corresponding implementation for
calls that survive linking.
