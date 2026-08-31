`[P3]` # `strip` fails silently and every Linux release archive ships unstripped

Found 2026-08-31 while verifying the aarch64 archive from nightly run
33418360718. Observed independently, and on the same day, as item 2 of "Three
things found while verifying" in
`specs/progress/2026-08-31-linux-aarch64-release-build-native-arm64.md`, which
records the same `strip` failure but files no todo for it. This is that todo.

## The defect

`.github/workflows/build.yml`'s "Strip binary" step:

```yaml
strip _dist/bin/march || true
strip _dist/bin/forge || true
```

Both `strip` calls fail, and `|| true` swallows it. From the aarch64 job log:

```
strip: _dist/bin/march: could not create temporary file to hold stripped copy: Permission denied
strip: _dist/bin/forge: could not create temporary file to hold stripped copy: Permission denied
```

The cause on the cross leg is ownership: the Alpine container writes `_dist` as
root with mode `r-xr-xr-x`, and the host runner (uid 1001) then cannot create a
temp file alongside them. `file` confirms the shipped binaries are `not
stripped`.

**The x86_64 archive is also `not stripped`.** That is the part the parallel
investigation did not catch — it attributed the failure to the container leg's
root-owned `_dist`, which cannot explain x86_64, where the build never enters a
container. So there are likely two distinct causes behind one symptom, and the
x86_64 one is still unexplained. Check its job log rather than assuming.

## Impact

Cosmetic-to-moderate: the binaries work. They are just larger than intended, so
every user downloads more than they need.

```
linux-aarch64  bin/march  24,113,928  not stripped
linux-x86_64   bin/march  20,773,544  not stripped
darwin-arm64   bin/march  15,648,200
```

## Why nothing caught it

The same `|| true` that the empty-`bin/` investigation already flagged as
masking #2. That investigation removed the *other* two maskings (added
`set -euo pipefail` and a payload-verification step) but left this one, because
a failed `strip` is not fatal the way a missing binary is. It is still a
failure being discarded unread.

## Acceptance

Release archives contain stripped binaries on both Linux platforms, and a
`strip` failure is either reported or deliberately and visibly tolerated —
not silently discarded. Note the fix must keep working for the cross leg, where
the files are root-owned and read-only when `strip` runs; `chmod`/`chown` in the
container before the step, or stripping inside the container, are both options.
