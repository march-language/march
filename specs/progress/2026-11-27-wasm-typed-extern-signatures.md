# Typed WebAssembly extern declarations

The LLVM emitter declared every parameter of a user extern as a pointer.
Call sites already used the types from the March declaration. With a mixed
signature such as `(Int, Float, String)`, the linker therefore saw a
different function type from the C definition.

For WebAssembly targets the declaration now uses the same LLVM types as the
call emitter. Runtime prototypes provided by the preamble still take priority.

The codegen regression checks an extern taking a native integer, a native
float, and a March string. Its declaration uses `i64`, `double`, and `ptr`
in that order.
