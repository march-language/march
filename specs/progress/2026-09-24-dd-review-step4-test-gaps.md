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

## Fixed 2026-09-24

1. `cli_role_grant_direct_builtin`: a body lambda calling `file_write` directly, with no
   helper between, is refused with "the body passed to `Stream_Run.run_Cons` reaches
   `IO.FileWrite`". Perturbation: the root's own-caps arm in `charge_lambda` replaced with
   `[]` in a scratch worktree → this case red, the rest of the suite green (recorded in
   the PR description / session report).
2. `cli_grants_not_in_program_fingerprint`: three programs (no grant, one grant, two
   grants on two roles) run interpreted and print `Stream_Msg.fingerprint()`; the three
   digests must be equal. Perturbation: the grants mixed into the `fingerprint_of` call at
   the generation site → red; `grants_not_in_fingerprint` (the helper-level test) stays
   green under the same perturbation, which is the gap the finding describes.
