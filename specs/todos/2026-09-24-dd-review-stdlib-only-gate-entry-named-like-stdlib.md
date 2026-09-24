# `[P1]` A user entry file named like a stdlib file is exempt from the stdlib-only gate

Filed 2026-09-24 by the distributed-deploys review (step 2, PR #594, commit
f06163fc5). Plan: section 1, II.1, D31.

## Defect

`is_shipped_stdlib_file` compares only the file's basename (`json.march`)
against the stdlib manifest. A match adds the user's own file to
`Typecheck_builtins.stdlib_source_files` (`bin/main.ml:1982-1984`,
`bin/main.ml:4134-4137`, `bin/toolchain.ml:377-378`), and the
`pid_of_int`/`actor_whereis`/`actor_registered` gate exempts it. The same
membership also weakens Check 1b for that file, from ERROR to HINT. Files named
on the command line are affected, including `--compile-so --hot-reload`
patches and every project `lib/` file `forge build`/`forge check` passes to
`march check`. Dependencies reached through `MARCH_LIB_PATH` are still gated.

## Confirmed

```march
mod Forge do
  needs IO.Console
  fn main(_c : Cap(IO.Console)) do
    let p = pid_of_int(0)
    let q = actor_whereis("x")
    let r = actor_registered()
    println("forged")
  end
end
```

Saved as `forge.march`, `march --check` exits 1 with "`pid_of_int` is internal
to the standard library …". Saved as `json.march`, it exits 0, runs
interpreted, and the compiled binary prints `forged` (rc 0). Checked twice, by
the reviewer and by re-running `--check` at d3396f743.

## Fix I would make

Exempt a file only when its real path is under the resolved stdlib directory.
Better, give the CI `--check stdlib/<mod>.march` ratchet an explicit flag and
stop inferring stdlib-ness from the name. Add a driver-level test: a user
`json.march` calling `pid_of_int` is rejected.
