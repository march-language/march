# Strings use the March allocator

`march_string_alloc` allocated strings with libc `malloc` while every string
release went through the runtime's allocator-aware `free` routing. In native
mimalloc builds that made every last string release take the provenance slow
path, unlike other March heap objects.

Strings now allocate through `march_obj_malloc`. The existing routed `free`
continues to support both libc and mimalloc allocation modes, including direct
runtime and user-FFI releases. A focused codegen test pins the routing
contract, so a direct libc allocation cannot quietly return.

