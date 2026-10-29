`[P2]` `Range.to_list({start: 5, stop: 0, step: 0})` loops forever

Filed 2026-10-27 by phase 0 of `specs/2026-10-26-termination-checking-design.md`
(§0.4 row s2). Measured: it loops, both interpreted and compiled.

`Range.new_step` (`stdlib/range.march`) guards `step : {Int | _ != 0}`. But a range is a
plain record type, so a record literal bypasses the constructor and reaches
`Range.to_list` with `step = 0`.

Decision D5 (settled 2026-10-27): `Range.to_list` panics on `step == 0`. This is one PR of its
own, with a CHANGELOG `### Fixed` bullet.
