# Let a freestanding wasm32 embedder provide its allocator

`MARCH_WASM_EXTERNAL_ALLOC` omits the default bump allocator from the
freestanding runtime so the embedding module can link its own `march_alloc`.
The override preserves the zeroed, eight-byte-aligned linear-memory allocation
contract. The embedder still owns reclamation and must retain live allocations,
including cached string literals. The runtime's reference counting and free
operations remain no-ops.

`scripts/test-wasm-allocator.sh` builds wasm32 modules with both allocators
and executes them in Node. The linked allocator variant previously failed
with a duplicate symbol and now supplies all literal allocations.
