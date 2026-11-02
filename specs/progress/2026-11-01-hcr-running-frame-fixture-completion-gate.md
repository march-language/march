# Keep the running-frame fixture alive until both deploys are verified

The HCR running-frame regression used a fixed approximately ten-second
loop for its server's lifetime. Two signed deployments had to finish
within that unrelated window. Linux CI finished the first migration and
then logged `stop-new migrated` and `frame-done` while the deploy client was
still waiting, ending the connection with `Connection reset by peer`.
There was no old-frame ABI panic or process crash: the fixture exited
normally before its controller finished.

The harness now releases the fixture through a file gate only after it
observes the actor call version 3 (`fresh-301`). The original main and its
saved closure remain active and keep checking the baseline ABI meanwhile.
At completion both perform explicit, asserted baseline calls
(`old-main-101`, `old-closure-101`), followed by the existing assertion that
`on_stop` observes both state migrations (`stop-third migrated-v3:42`).
The gate is cleared before persisted replay, which repeats these checks.
Readiness and completion polls stay bounded, and the existing fixture
cleanup and suite deadline remain in place. No runtime timeout or
production code changed.

Validation used a temporary twelve-second pause immediately before the
first deploy. The original fixture exited normally and failed its deploy
with `Connection refused`; the gated fixture passed with the identical
pause, including replay. The pause was then removed, the test executable
rebuilt, and adversarial regression 48 passed again normally. The delay is
not part of the permanent test.
