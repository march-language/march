`[P2]` - [ ] **The capability ceiling charges the prelude's `IO.Console` to a module with no `main`.**

> **REOPENED 2026-09-09.** The closure below is wrong: it verified
> `ptype Box = Box(Int, Int)`, which does compile cleanly, while the shape
> `forge/test/test_build_check.ml` exercises, `Box(Int, String)`, still fails
> the ceiling on both macOS and Linux. Removing the `forge` workaround on the
> strength of that check turned `test (ubuntu-24.04)` red on `main`. Tracking
> continues in
> `specs/todos/2026-09-09-cap-ceiling-charges-prelude-io-to-mainless-module.md`.

Filed 2026-09-03, found while landing `@[no_alloc]`
(`specs/progress/2026-09-03-allocation-contracts.md`); caught by CI on the
Linux test leg, then reproduced on macOS, so it is not platform-specific.

Compiling a library module that declares no `main` and performs no IO fails
the default capability ceiling:

```march
mod Boxes do
  ptype Box = Box(Int, Int)
  fn bump(b : Box) : Box do
    match b do
      Box(x, y) -> Box(x + 1, y)
    end
  end
end
```

```
march --compile -o /tmp/boxes.bin boxes.march
-- ERROR --
module `Boxes` uses `IO.Console` but does not declare `needs IO.Console`.
```

`--no-cap-strict` makes it compile. The module never mentions console IO: the
charge comes from the injected prelude. `bin/main.ml`'s attribution already
has machinery for exactly this (`transparent_fns` marks stdlib-span top-level
declarations see-through precisely because `println$String`'s console use was
being charged to the entry module), plus a `Dce.prune_unreachable`
`~extra_root` for the main-less case. One of the two is not covering this
shape.

Why it matters beyond the error itself: `forge fix --contracts` shells out to
`march --compile --report-contracts`, which hits this on every library
project. It currently passes `--no-cap-strict` to get around it
(`forge/lib/cmd_fix.ml`) — that is a workaround at the call site, not a fix,
and it should be removed once the attribution is corrected.

Suggested first step: compare `stdlib_span_files` against the spans actually
carried by prelude declarations for a main-less module, and check whether the
`extra_root` branch in `Dce.root_names` (which only fires when no other root
exists) is reached at all here.

## Closed 2026-09-08 — RETRACTED, see the banner above

Re-ran the exact repro above against `origin/main` at `a9706580` (a freshly
built `bin/main.exe`, not a cached one — see the worktree-stale-binary trap in
project memory). It no longer fails:

```
march --compile -o /tmp/boxes.bin boxes.march       # exit 0
march --check boxes.march                            # exit 0
march --compile --report-contracts boxes.march       # exit 0
march --compile --cap-strict -o /tmp/boxes3.bin boxes.march   # exit 0
```

Control: an unrelated `main` with no grant that performs console IO still
correctly errors with "`main` performs IO but declares no grant" — so the
ceiling itself is still enforced; only the main-less-module misattribution is
gone.

Could not identify the specific commit that fixed this — no commit since this
item was filed touches `Dce.root_names`, `transparent_fns`, or
`stdlib_span_files` in `bin/main.ml` / `lib/tir/cap_attrib.ml`. It may have
been fixed as a side effect of unrelated capability-attribution work, or the
repro's failure mode may have been narrower than stated. Left undetermined
rather than guessed.

**Follow-up landed in the same commit as this closure:** removed the
`--no-cap-strict` workaround from `forge/lib/cmd_fix.ml`'s `--report-contracts`
invocation now that the underlying bug is gone. Verified `forge fix
--contracts` still runs cleanly (exit 0, no cap-ceiling error) against a
minimal library project (`forge.toml` with `[package] name = "boxlib"`, one
main-less module) with `march --compile --report-contracts` also confirmed to
exit 0 directly on the same module.
