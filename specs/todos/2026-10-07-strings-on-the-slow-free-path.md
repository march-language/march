`[P3]` Strings still take the slow free path

Found 2026-10-07 (`specs/progress/2026-10-07-alloc-free-fast-path.md`).
`march_string_alloc` allocates with libc `malloc`, not `march_obj_malloc`, so a
string's last release goes through `march_free_any`'s full provenance check
instead of the inline arena range test that heap cells now take. Moving string
allocation onto `march_obj_malloc` puts strings on the fast path, after
checking that nothing frees string memory with a `free` that is not routed
(FFI and runtime code that frees a string buffer directly) — the -Dfree routing
in runtime/march_alloc.h covers runtime and user-FFI translation units only.
Measure a string-heavy benchmark before and after.
