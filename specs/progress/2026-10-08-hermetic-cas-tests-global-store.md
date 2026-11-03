# Two stdlib tests made hermetic against the user-global CAS store

`Cas.create` opens `$HOME/.march/cas` as a read-through/write-through store in
addition to `<project_root>/.march/cas`, so a temp `project_root` is not enough
isolation:

- `track integration` #6 `cas cache hit` asserted "first pass: compile called",
  but a prior run's write-through entry for the same SCC hashes in `~/.march/cas`
  made the first pass a hit. Now `HOME` points at the temp dir while the store is
  created, and the temp dir is removed afterwards.
- `adversarial-regressions` #49 (MARCH_SANITIZE cache isolation) compiled a
  fixed-content program, so its artifact was served from `~/.march/cas` on every
  run after the first ("first (thread) build is not cached"). The compiles now
  run with a private `HOME` under the test's temp dir, which is removed at the end.

Proved: each passes twice in a row; each still fails when the guarded property is
broken (`store_artifact` made a no-op -> "second pass" gets 19 compiles;
`MARCH_SANITIZE=thread` collapsed onto the address key -> "address build stored its
own artifacts (2 -> 2)").
