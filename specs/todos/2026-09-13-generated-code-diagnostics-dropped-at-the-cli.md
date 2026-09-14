# `[P2]` Diagnostics inside generated (`derive` / `@[endpoints]`) code are dropped at the CLI

Found 2026-09-13 while building the event-shaped endpoint API. A generator
bug that produced `The linear value `ep` is used more than once` inside a
generated `await_*` function was reported by the endpoint unit harness
(`test/test_endpoints.ml`, which typechecks with the stdlib prepended) and by
nothing else: `march --check` on `test/session/stream_actor_events.march`
printed no diagnostic and exited 0, and the program compiled and ran.

## Cause

`Desugar_derive.respan_derived_decl` gives every span inside a generated
declaration a synthetic span whose `file` is `"<none>"`. `bin/main.ml`'s
`is_user_file` counts a diagnostic as the user's when its file is the entry
file, `""`, `"<unknown>"`, or a `MARCH_LIB_PATH` file; `"<none>"` is none of
those, so every diagnostic raised inside generated code is filtered out with
the stdlib's. The exit code follows the filtered set. Measured with the
generator as first written (the double use present): `--check` on the fixture
printed nothing and exited 0; the harness reported the error twice.

The `derive` expansions have the same file tag, so a bug in a derived `Json`
codec is equally invisible at the CLI.

## What to build

- Treat `"<none>"` as a user file in `is_user_file` (all five copies in
  `bin/main.ml`), or better, give synthetic spans the generating
  declaration's file so the diagnostic also says which `derive`/`protocol`
  produced it.
- Then decide how to render a diagnostic whose span is synthetic (line
  numbers are a counter, not source lines): print the generating
  declaration's span with a "in code generated for `X`" note.
- Witness: the perturbation above as a unit test on the driver path, or a
  `test/native` fixture that a deliberately broken generator would fail.
