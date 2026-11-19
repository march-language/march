# ocap: the in-browser March runtime has no launch

Logged 2026-11-17 by ocap phase 4, Task 3 review (specs/plans/2026-11-15-ocap-p4-runtime-plan.md).

The in-browser March (`docs/assets/march.js`, `march_compile.js`, `march_stdlib.js`, rebuilt by
`scripts/build-browser-repl.sh` / `gen-browser-repl.yml` after each merge) evaluates programs
without calling `Authority.launch_init`: nothing sets a launch authority there, so the "Try
it" REPL and browser-run programs have no launch layer, and a scoped `main` request is not
enforced in the browser.

What to do: have the browser driver launch the way `lib/repl/repl.ml`
(`launch_repl_authority`) does for the REPL (`"IO"`, unscoped) and the way the program
pipeline does for a compiled entry (`main`'s request), and add a case to
`scripts/browser-repl-smoke.js` that a scoped `main` refuses outside its request.
