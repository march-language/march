# HTTP e2e leak check: event-loop RSS failure was measurement noise, not a leak

**Symptom.** `compiled HTTP server: event loop (MARCH_HTTP_EVLOOP=1)` in
`http server (compiled, end-to-end)` (run_stdlib, `test (ubuntu-24.04, rest)`)
failed on PRs (#764: 3152 KiB, #763: 3580 KiB over 20,000 requests, bound
2048 KiB) while main passed the same code (#764's merge commit 7971248fd was
green on main).

**Verdict: (b), noisy RSS.** Evidence:

- Exact live-object gauge (`march_live_allocs`, read via a `GET /live` route
  in the test server) on the current runtime: **+0 objects** over 20,000-35,000
  requests, both servers, on macOS (arm64) and in the ubuntu arm64 container
  (glibc 2.39, 14 cores), 40/40 runs.
- 20 runs of the unchanged test on main in the container: thread pool always
  568 KiB; event loop 64-392 KiB in 18 runs, **2336 and 2248 KiB in 2** (both
  failures). Bimodal, not proportional to request count.
- With per-window RSS marks (4 windows x 5,000 requests), the step lands in
  the first window only, then 0/0/0 KiB. In the run that showed it (event
  loop, +2504 KiB), the *before* reading was ~2.3 MiB lower than usual and the
  plateau matched every other run: the "growth" was a low baseline after the
  warm-up (allocator page state at that moment; compiled builds use
  per-thread mimalloc heaps since 2026-10-01), not memory held per request.
- A gotcha on the way: a probe compiled with `_build/default/bin/main.exe`
  without `MARCH_RUNTIME_DIR` linked a stale staged runtime and showed a
  21-object-per-request leak. That is the pre-#753 runtime, not current main.

**Fix (test only).** Phase E of `test/test_http_native.ml` now:

1. asserts the live-object gauge grows by at most 500 over 20,000 requests
   (a one-object-per-request leak is 20,000);
2. keeps RSS as a guard for native (non-March-object) leaks, as a slope:
   it fails only if RSS grows more than 256 KiB in **every** 5,000-request
   window (about 52 bytes/request). Steady state measured 0-8 KiB per window.

**Shown to go red** (ubuntu container, both servers):

- `march_http_release_conn` returning early (the #753 leak): live objects
  +500,052 (25 per request) -> FAIL.
- an unfreed 160-byte `malloc` per request (gauge stays +0): RSS per window
  540-1300 KiB in every window -> FAIL.

Both perturbations reverted.

**Merged with e71b1d069** (landed on main in parallel: warm-up raised from
1,000 to 10,000 requests for the same flake). Both are kept: the longer
warm-up keeps the reported RSS marks flat, and the gauge plus per-window rule
stay correct even if the step lands after it.
