# `march repl --grant` error handling (2026-11-19)

Found by the ocap phase 4 Task 7 review:

- `march repl --grant BAD` reports the launch error as `march: MARCH_GRANT is not
  a scope list: ...`, because the REPL passes the flag through `putenv`. It should
  name `--grant`, as `march --grant BAD file.march` does.
- A trailing `--grant` with no value falls through to the preload argument arm
  instead of reporting a missing value.

What to do: carry the grant's source into the launch error text, reject a
valueless `--grant`, and pin both in the REPL tests.
