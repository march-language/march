# Bake `MARCH_PIN_MAIN` into a binary: forge.toml `[package] pin_main = true`

**Done 2026-09-22 (the forge half; the item is now closed).**

- **TOML `Bool`.** `forge/lib/toml.ml`'s `value` gained a real `Bool of bool`
  constructor (not a `Str "true"` encoding), plus `Toml.get_bool`. Only the
  exact bare words `true`/`false` become `Bool`; every other bare value (e.g.
  `True`, `1.2.3`) keeps its old `Str` reading, and a quoted `"true"` stays a
  `Str`. No `forge.toml` in the repo or scaffolded by forge contains a bare
  boolean, so no existing file changes meaning. Matches updated:
  `Project.parse_deps_section` (the only exhaustive one; a `name = true` dep is
  now ignored rather than read as registry version `"true"`), and
  `Cmd_lint.load_config`, which keeps warning "unknown severity" for
  `rule = true` (previously that arrived as `Str "true"`). The other consumers
  already had `| _ ->` arms or read through `get_string`, which returns `None`
  for a `Bool`. (`lsp/lib/forge_config.ml` has its own separate parser and is
  untouched.)
- **`Project.pin_main : bool`** from `[package] pin_main`. Absent means false.
  A non-boolean value (including quoted `"true"`) makes the load fail with
  `forge.toml: [package] pin_main must be true or false (unquoted)`: a GUI app
  that silently did not pin fails as a window that never appears, with no
  diagnostic.
- **Where `--pin-main` is passed.** `Cmd_build.compile_entry` takes
  `~pin_main`, and its command is now built by the pure
  `Cmd_build.compile_command` (unit-testable; byte-identical to before when
  `pin_main` is false). Callers: `forge build` (and so `forge run --compiled`
  on the project), `forge run --compiled FILE` inside a project (via
  `Cmd_run.context.pin_main`, alongside the lib path and FFI shims it already
  inherits), `forge bench`, and `forge install` (its own command string).
  A bool rather than the whole project is threaded because the single-FILE
  run may have no project.
- **Not passed:** `forge test` (compiled test binaries' `@main` calls
  `march_test_run` directly, which runs each test on the OS main thread
  without the scheduler spawn, so `--pin-main` would change nothing but the
  CAS key; checked with `nm` on a real test binary built both ways: neither
  `march_spawn_main` nor the pinned variant is linked); interpreted runs (no
  compiled entry point); `--compile-so` hot-reload patches and WASM islands
  (no `main`).
- Documented in `docs/tooling.md` (forge.toml keys are documented only there;
  there is no `specs/` copy of the forge guide).

**Verification.**
- New forge tests (`forge/test/test_forge.ml`): toml group "bare true/false
  are Bool", "Bool in inline table/array", "other bare values stay Str";
  metadata group "pin_main = true", "pin_main absent/false -> false",
  "pin_main non-bool -> error"; new "pin_main" group "build command carries
  --pin-main iff set" (pins the exact unpinned and pinned command strings).
- Red control: before the change the suite does not compile
  (`Error: Unbound value "Toml.get_bool"`). Semantic reds, by temporarily
  reverting one piece at a time: dropping the `true`/`false` -> `Bool` lexing
  fails "bare true/false are Bool" (`Expected: Some true`, `Received: None`)
  and "pin_main = true" (`load failed: forge.toml: [package] pin_main must be
  true or false (unquoted)`); dropping the flag in `compile_command` fails
  "pin_main -> --pin-main" (`Expected: true`, `Received: false`).
- `dune build --root . @forge/test/runtest`: exit 0.
- End to end with the just-built compiler and forge on a scratch app:
  `pin_main = true` -> `forge build` binary defines `_march_spawn_main_pinned`
  (and not `_march_spawn_main`) and runs; `pin_main = false` -> the reverse.

---

The original todo follows.

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
