`[P2]` `Control.chunks("abcdef", 0)` loops forever

Filed 2026-10-27 by phase 0 of `specs/2026-10-26-termination-checking-design.md`
(§0.4 row s3). Measured: it loops, both interpreted and compiled.

`chunks_from(hex, size, off + size, n)` (`stdlib/control.march`) makes no progress when
`size = 0`, and `Control.chunks` has no precondition on `size`.

Decision D5 (settled 2026-10-27): give `Control.chunks`' `size` the refinement
`{Int | _ > 0}`, plus a runtime guard. This is one PR of its own, with a CHANGELOG
`### Fixed` bullet.
