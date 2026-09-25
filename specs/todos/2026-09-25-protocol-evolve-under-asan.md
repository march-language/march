`[P2]` protocol_evolve fails under AddressSanitizer

Filed 2026-09-25 with #663, which moved `test/two_node/protocol_evolve` (step 9's
network acceptance) into CI. It passes plain on macOS and Linux, repeatedly. Under
`MARCH_SANITIZE=1` in the arm64 ubuntu container (the sanitize gate's options,
`detect_leaks=0:halt_on_error=1`) it fails without any sanitizer report, two ways:

1. node-b prints "driving" and then nothing for 600 s; both deploys had completed
   within seven seconds of the start. Not investigated: node-b was gone before a
   backtrace could be taken.
2. node-b finishes but reports 5 sessions lost (`connect to role Shop: ... no
   endpoint registered for role 2`) and 2 refused (`node-a did not answer`), and
   never sees a v2/v2 pairing.

(2) is the re-offer window widened by ASan's 2-20x slowdown: a version-2 Buyer is
accepted by the offer node-a is replacing, whose endpoint is gone by the time it
connects. That may be a real race in `SessionNode` (accept, then close_offer)
that plain timing hides. (1) could be the same race wedging a Driver task that
`settle` waits on, but `settle` is bounded, so something is starving node-b's
main green thread.

The scenario exits 3 (skipped) under `MARCH_SANITIZE` until this is understood;
`hcr_new_code_session` covers a hot deploy under ASan. To reproduce, run it in the
container with `MARCH_SANITIZE=1 TWO_NODE_TIMEOUT=600` after removing the skip,
and attach gdb to node-b once `deploy_a.log` says "Deploy complete".
