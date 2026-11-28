# Empty launch requests in freestanding WebAssembly

A capability-free `main` compiled for `wasm32-unknown-unknown` still called
`Authority.launch_init`. The browser has no process environment supplying
`MARCH_GRANT`, and the generated LLVM referred to an undeclared native grant
lookup even for `fn main() : Unit do () end`.

The compiler now omits the launch initializer for an empty request in a
freestanding browser program. Static capability checking still runs. Native
and WASI targets, test builds, and browser programs with nonempty requests
retain their existing initialization path.

The regression checks the emitted browser entry point, a scoped browser
request, and an empty native request. Clang accepts the LLVM for the empty
browser request, and the exported `_start` runs when linked with the
freestanding runtime.
