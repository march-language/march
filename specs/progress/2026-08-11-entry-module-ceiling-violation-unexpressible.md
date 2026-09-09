# A ceiling violation is no longer expressible in the ENTRY module

Found 2026-08-11 while fixing CI for R1 stage D
(`specs/2026-08-10-r1-stage-d-grant-required-design.md`). Not a bug — a
semantic consequence of stage D that the design did not anticipate, and that
invalidated the shape of seven capability-ceiling fixtures.

## The interaction

Three rules now compose into an impossibility:

1. **Stage D** — a program that reaches capability `X` must declare a grant at
   `main` covering `X`.
2. **Check 1** — every `Cap(X)` in a signature must be covered by `needs X` in
   that module.
3. **The ceiling** — a module's emitted code must stay within its own `needs`.

So reaching `X` forces granting `X`, granting forces declaring, and declaring
satisfies the ceiling. **In the entry module, a ceiling violation cannot be
written down.** The only spellings left are "grant it and declare it" (no
violation) or "don't grant it" (a stage-D error, which fires first and stops
the compile before the ceiling runs).

## Why this does not weaken the ceiling

The ceiling's stated purpose is per-MODULE and, above all, per-DEPENDENCY:
"every module's emitted code must stay within its own `needs`, including
dependencies that never opted in." That is exactly where it remains
expressible and load-bearing — a nested module or an imported package can
still use `IO.FileWrite` while declaring only `IO.Console`, and the ceiling
catches it:

```march
mod App do
  needs IO.Console
  needs IO.FileWrite            -- the entry's own grant obligation
  mod Inner do
    needs IO.Console            -- but Inner writes without declaring it
    fn go() : () do File.write("/tmp/x", "d") … end
  end
  fn main(_cap_console : Cap(IO.Console), _cap_filewrite : Cap(IO.FileWrite)) : () do
    Inner.go()
  end
end
```

Verified: this still produces `1 capability ceiling violation(s)`.

What is lost is only the ability to demonstrate the ceiling *in the entry
module itself*, which was never the interesting case — the entry module is the
one whose author is by definition opting in.

## The trap this set, and it nearly landed

The affected fixtures assert COMPILE FAILURE. Left un-migrated they keep
failing — but on the stage-D error, not the ceiling — so they would have gone
green while testing nothing. The failures that actually surfaced were the
inverse ones (`--no-cap-strict` must DISABLE the check, so it asserts
success), which is the only reason the vacuity was noticed at all.

Any future change that makes an earlier check fire on these fixtures will hide
them the same way. A fixture asserting rejection needs its expected message
pinned, not just a non-zero exit — `specs/lang/types/reject/*` already does
this with `EXPECT-ERROR`, and `test_cap_ceiling.ml`'s `rejects`-family helpers
should assert on the "capability ceiling" text for the same reason.

## Status

Fixtures restructured to the nested-module shape as part of the stage-D CI
fix. This todo records the semantic finding and the assert-on-text
recommendation, which is not yet done.
