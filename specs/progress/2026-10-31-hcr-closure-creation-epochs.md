# Hot-reload closures retain their creation epoch

Completed 2026-10-31 as part of the HCR ABI 5 frame-routing change in
`../plans/2026-10-31-hot-deploy-correctness-design.md`.

A closure can outlive the frame that created it and later be called from newer
work or a C callback. Keeping its image mapped does not keep its nested boundary
calls on a compatible ABI. Hot-reload closures now carry a pinned creation epoch
in their header (`MARCH_CLOSURE_TAG`, pad interpreted as uint32). Their last
release drops that pin; FBIP reuse drops the former cell's pin before replacing
its header and captures the new closure's epoch after construction.

Generated apply functions and function-value wrappers enter the captured epoch
before releasing their environment. Function values are materialized per use in
hot builds, including unchanged function bodies reached at a newer epoch.
Runtime actor dispatch/on_stop/inspect wrappers retain the actor-selected routing
context. Ordinary non-hot builds retain their static-closure behavior. Specialized
native map/map2/fold calls that pass a NULL environment inherit the active epoch.

Apply frames track the references they own to their environment, including
recursive self aliases. Generated ownership increments, releases, outgoing calls,
field stores, returns and reuse transfer that accounting. Normal release clears
it; a panic/cancellation unwind releases references whose normal cleanup was
bypassed. Frame cleanup runs closure destruction while the old frame's routing
context is still active (the shared frame-runtime implementation covers this).

## Evidence

- `test/test_hcr_closure_epoch.c` passes creation routing, fresh-work routing,
  last-reference pin release, caught-panic cleanup with multiple owned aliases,
  and cleanup of a uniquely owned environment. Its pressure case has no actor
  frame retaining epoch 1: only the escaping closure keeps it alive through
  thirty replacements, continues to call old code, and releases the last pin
  when dropped.
- `test/test_hcr_closure_codegen.ml` passes at both `--opt 2` and `--opt 0`
  (two tests, 17.720 seconds on macOS). Real generated capturing closures and
  function-value wrappers called from newer C frames keep the old nested callee
  after a changed-ABI replacement. A non-tail recursive closure panics through
  the real catch boundary and restores both reference and epoch-pin counts.
- The compiled native-map case first reproduced a fatal NULL-environment read
  (`SIGSEGV`, address 0x8). After the NULL guards, native map, map2 and fold pass.
- Capturing and capture-free local tail recursion both run 200,000 iterations at
  both optimization levels. Inspected emitted IR uses explicit `tco_loop`
  backedges, with frame entry before the loop and exit after it. No speculative
  tail-call rewrite was added.

This records focused macOS evidence, not Linux execution or a claim that the
entire hot-deploy scenario suite has finished.
