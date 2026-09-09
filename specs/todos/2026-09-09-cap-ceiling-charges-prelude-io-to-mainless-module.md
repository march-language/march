# `[P2]` The capability ceiling charges the prelude's `IO.Console` to a module with no `main`

Reopened 2026-09-09. Originally filed 2026-09-03 and closed 2026-09-08 in
`specs/progress/2026-09-03-cap-ceiling-charges-prelude-io-to-mainless-module.md`;
that closure was wrong and its follow-up broke CI on `main`.

Compiling a library module that declares no `main` and performs no IO still
fails the default capability ceiling:

```march
mod Boxes do
  ptype Box = Box(Int, String)
  fn bump(b : Box) : Box do
    match b do
      Box(x, y) -> Box(x + 1, y)
    end
  end
end
```

```
march --compile --report-contracts boxes.march
-- ERROR --
module `Boxes` uses `IO.Console` but does not declare `needs IO.Console`.
```

`--no-cap-strict` makes it compile. The module never mentions console IO; the
charge comes from the injected prelude.

## Why the 2026-09-08 closure missed it: the bug is String-dependent

The closure re-ran the repro as it was originally written, with
`ptype Box = Box(Int, Int)`, saw exit 0, and concluded the bug was gone. It is
not. The field type decides it:

| module | `march --compile --report-contracts` |
|---|---|
| `ptype Box = Box(Int, Int)` | exit 0 |
| `ptype Box = Box(Int, String)` | exit 1, ceiling error |

`forge/test/test_build_check.ml` uses the `String` shape, which is why
`forge fix --contracts` tests 0 and 2 went red the moment the workaround was
removed. Verified on macOS (arm64) and on Linux in `ci/Dockerfile.ubuntu`;
this is not platform-specific, contrary to what the failure pattern first
suggested.

**Any future attempt to close this must re-run `@forge/test/runtest`, not a
hand-written minimal module.** A narrower repro reports success while the bug
is live — that is exactly how this regression reached `main`.

## Note on reproducing

The `forge fix --contracts` cases pass when `test_build_check.exe` is invoked
directly but fail under `dune build @forge/test/runtest`, so reproduce through
the dune alias. `scripts/run-tests.sh` does not run `forge/test/` at all, so a
fully green local `run-tests.sh` says nothing about this.

## Original analysis (still current)

`bin/main.ml`'s attribution already has machinery for exactly this
(`transparent_fns` marks stdlib-span top-level declarations see-through
precisely because `println$String`'s console use was being charged to the entry
module), plus a `Dce.prune_unreachable` `~extra_root` for the main-less case.
One of the two is not covering this shape — and the `String` dependence points
at `println$String` specifically.

Suggested first step: compare `stdlib_span_files` against the spans actually
carried by prelude declarations for a main-less module, and check whether the
`extra_root` branch in `Dce.root_names` (which only fires when no other root
exists) is reached at all here.

## Call-site workaround

`forge/lib/cmd_fix.ml` passes `--no-cap-strict` to
`march --compile --report-contracts`. That is a workaround, not a fix, and
should be removed once the attribution is corrected — but only together with a
green `@forge/test/runtest`.
