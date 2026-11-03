`[P2]` `Duration.format` of the minimum Int recurses forever

Filed 2026-10-27 by phase 0 of `specs/2026-10-26-termination-checking-design.md`
(§0.4 row s4). Measured: interpreted, there is no result in 10 s; compiled, it fails with SIGBUS (a stack
overflow).

```march
Duration.format(Duration(0 - 4611686018427387903 - 1))
```

`format` (`stdlib/duration.march`) handles `ms < 0` as `format(Duration(-ms))`. Since
`-min_int` is `min_int`, the negative branch is taken again.

Decision D5 (settled 2026-10-27): handle `ms < 0` without negating `min_int`. Either format
the magnitude digit by digit, or special-case the minimum. This is one PR of its own, with
a CHANGELOG `### Fixed` bullet.
