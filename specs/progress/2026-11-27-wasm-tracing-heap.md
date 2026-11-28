# Host-driven tracing heap for freestanding wasm32

Embedders can link `runtime/march_wasm_heap.c` with the freestanding runtime
using `MARCH_WASM_TRACING_HEAP`. The bridge supplies retained allocation
starts after March returns. The collector follows exact allocation starts
found in aligned payload words, then coalesces and reuses unreachable blocks.
It is non-moving and grows linear memory only up to a configurable cap. The
runtime retains the headers for cached string literals automatically.
Normal bump allocation and the external allocator contract are unchanged.

`scripts/test-wasm-allocator.sh` runs all three allocator modes in wasm32
under Node. The tracing case exercises cycles, explicit root removal, block
coalescing and splitting, zeroed reuse, literal cache survival, a bounded
steady state, and allocation traps.
