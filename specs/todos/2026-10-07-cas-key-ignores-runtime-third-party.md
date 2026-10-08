`[P2]` The runtime-object cache and the compiled-binary CAS key ignore runtime/third_party/

Found 2026-10-07 (`specs/progress/2026-10-07-alloc-free-fast-path.md`). The
runtime digest that keys the cached runtime objects and the compiled-binary CAS
covers `runtime/*.c` and `runtime/*.h` only, not `runtime/third_party/**`
(vendored mimalloc). An edit to a vendored file alone is therefore served
stale objects: it silently made one mimalloc-configuration measurement in that
work compare a binary against itself. Include `runtime/third_party/**` (or at
least every file the driver compiles or includes from there) in the digest,
and add a check that editing a vendored file changes the key.
