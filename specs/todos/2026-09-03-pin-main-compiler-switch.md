# Bake `MARCH_PIN_MAIN` into a binary — forge.toml half remaining

> **The compiler half landed 2026-09-17**
> (`specs/progress/2026-09-17-pin-main-compiler-switch.md`): `march --pin-main`
> emits `march_spawn_main_pinned` instead of `march_spawn_main`, so the binary
> carries the requirement itself. CAS-tagged, so a non-pinned cached artifact
> cannot satisfy a `--pin-main` build.
>
> **Remaining: `forge.toml` `[package] pin_main = true`.** Not done, and it is
> not quite a one-liner: `forge/lib/toml.ml`'s `value` type has only `Str`,
> `InlineTable` and `Array` — there is no `Bool` — so `pin_main = true` either
> lexes as `Str "true"` or is not representable, and which one it is decides
> whether the getter is `get_string pkg "pin_main" = Some "true"` or whether
> the TOML value type needs a `Bool` first. Settle that before writing the
> field. Then: a field on `Project.t`, and `Cmd_build.compile_entry` needs the
> project threaded to it (it currently takes no project) to add the flag.

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
