# `march --pin-main`: the binary carries the main-thread requirement

Landed 2026-09-17. The compiler half of
`specs/todos/2026-09-03-pin-main-compiler-switch.md`, which stays open for the
`forge.toml` half.

## Why

`MARCH_PIN_MAIN=1` pins `main` to scheduler 0 — the process main thread — which
Cocoa and GLFW require for window creation. It was a run-time environment
variable only, so a GUI program had to be *launched* with it set. A
double-clickable app cannot rely on that, and the failure mode is a window that
never appears with no diagnostic.

## Why not a `-D` define

The todo already ruled this out and it is worth keeping: the runtime is
compiled once into a cached `.so`, so a per-program define does not reach it.
The choice has to live in the **emitted entry point**, which is why this is a
second runtime symbol rather than a flag on the existing one.

## Shape

`march_spawn_main` and `march_spawn_main_pinned` are now two thin entries over
one `spawn_main_impl(fn, force_pin)`. `Llvm_toplevel.pin_main` (a ref, like
`Trmc.enabled`, because the entry point is emitted from a module-level buffer
walk that carries no ctx) selects which one the emitted `@main` declares and
calls.

`MARCH_PIN_MAIN` still works and can only turn pinning **on**, never off a
build that asked for it: a program compiled `--pin-main` needs the main thread
to run at all, so honouring `MARCH_PIN_MAIN=0` there would break it in a way
the user cannot diagnose from the message they would not get.

## CAS

`--pin-main` changes the emitted binary, so it is tagged in `codegen_cas_tags`.
Verified the value-revealing way rather than by reading the code — compiling
the same source both ways, in both orders, and checking the defined symbols:

| build | `march_spawn_main_pinned` defined |
|---|---|
| plain, then pinned | 0, then 1 |
| pinned, then plain | 1, then 0 |

A missing tag would have shown up as the second build in each row inheriting
the first's artifact.

## Verification

`--emit-llvm` shows the default build calling `march_spawn_main` and a
`--pin-main` build calling `march_spawn_main_pinned`; a `--pin-main` binary
compiles and runs.
