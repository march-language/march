# `[P3]` Step 4: two checks that pass their tests with the check removed

Filed 2026-09-24 by the distributed-deploys review (step 4, PR #596). Both were
found by perturbation in a scratch worktree at d3396f743.

1. **The body walk's direct-builtin arm** (`lib/typecheck/typecheck.ml:7563`,
   the root's own `cap_of_call` caps). Replacing it with `[]` left all 102
   `endpoints` tests and corpus `t294` green. A body lambda that calls
   `file_write` directly went from rc 1 to rc 0.
2. **The grant exclusion from the fingerprint the generated code embeds**
   (`lib/desugar/desugar_endpoints.ml:1922`). The test calls `fingerprint_of`
   directly. Mixing the grants into the digest at `:1922` left the suite green
   (102/102), while `Stream_Msg.fingerprint()` changed with each grant: three
   digests, against one on main.

## Fix I would make

Add a CLI reject case for a body lambda that calls a builtin directly. Compare
`<P>_Msg.fingerprint()` across grant variants through the compiled or
interpreted program, not the helper.
