`[P2]` `List.range_step(5, 0, 0)` loops forever

Filed 2026-10-27 by phase 0 of `specs/2026-10-26-termination-checking-design.md`
(§0.4 row s1). The COUNT sweep found it. Measured: it loops for 10 s, both interpreted and
compiled.

`range_step_go` (`stdlib/list.march`) recurses on `i + step`. With `step = 0` and
`i > stop`, it recurses on the same `i` forever.

Decision D5 (settled 2026-10-27): give `List.range_step`'s `step` the refinement
`{Int | _ != 0}`, and add the runtime panic that `Range.new_step` already has. This is one PR,
separate from the termination PRs, because it turns a hang into a panic or a
refinement error, which is a behaviour change. It needs a CHANGELOG `### Fixed` bullet.
