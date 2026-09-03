`[P2]` - [ ] **The capability ceiling charges the prelude's `IO.Console` to a module with no `main`.**

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
