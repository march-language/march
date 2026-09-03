# Bake `MARCH_PIN_MAIN` into a binary (compiler / forge.toml switch)

Filed 2026-09-03 alongside `specs/progress/2026-09-03-pin-main-green-thread-to-scheduler-0.md`.

`MARCH_PIN_MAIN=1` (runtime env var, read in `march_spawn_main`) pins `main`
to scheduler 0 / the OS main thread. A GUI program that needs it has to be
launched with the variable set, which is fragile for double-clickable apps.

Wanted: a `march --pin-main` (and `forge.toml` `[package] pin_main = true`)
switch that makes the compiled `@main` call a pinned spawn (e.g. emit
`march_spawn_main_pinned`, or a `-DMARCH_PIN_MAIN_DEFAULT=1` for the runtime
build — but note the runtime is compiled once into a cached `.so`, so a
per-program define does not work as-is; the emitted entry point must carry
the choice). Until then a shim-side `__attribute__((constructor))` that
`setenv("MARCH_PIN_MAIN","1",0)` works, since the constructor runs before
`main` and therefore before `march_spawn_main` reads the variable.
