# Preserve signed immediates in wasm32 pointers

On wasm32, an erased or niche integer stored as a pointer has a 31-bit
signed payload and a one-bit tag. LLVM zero-extends the pointer when
converting it to i64, so shifting that result as i64 treated negative
payloads as positive.

Decode at i32 width and then sign-extend the result to i64. Use that
decode for erased casts, known tagged niche and newtype payloads, and
closure trampolines. The conditional decoder still passes through even
heap-pointer bit patterns unchanged.

A freestanding wasm32 probe that reads `-23` from a cons cell produces
`2147483625` with the old compiler and `-23` after the fix. The codegen
regression also checks the closure trampoline and both wasm32 targets.
