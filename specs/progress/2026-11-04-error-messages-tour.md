# Error Messages tour and error playground (2026-11-04)

A hand-written docs page, `docs/error-messages.md` (`/docs/error-messages/`, in the sidebar's
Language section), tours March's diagnostics in nine sections that build in complexity:
syntax, names and did-you-mean, types, capabilities, linearity, actors, session channels,
protocols and choreography, refinements. 34 examples in all, each a short program and its
real `march --check` output with a sentence on what the message does well, then a table
linking every `docs/errors/` page.

**Why `docs/`, not `specs/lang/`.** `specs/lang/` is the language reference and
`gen-lang-docs.py` renders its chapters into `docs/`. This page is a guide (like
`docs/tour.md` and the `coming-from-*` pages), not reference, and its outputs come from a
different generator, so it lives in `docs/` and the language-docs generator doesn't own it.

**Outputs are generated.** The programs are `docs/assets/error-tour/NN-name.march`.
`scripts/gen-error-tour.py` fills each `<!-- error-tour: name -->` block on the page with the
program and what `march --check` prints for it, each run from a fresh directory under a
private `HOME` (`--check` mode verifies; the refinement examples need z3).

**Playground.** `docs/_includes/error-playground.html` + `docs/assets/error-playground.js`:
an editor pre-loaded with 26 of the examples, a Check button and a "Try it" button under each
example. It calls a new export of the live-compiler bundle, `marchCheck(source) -> {output,
rejected}` (`js/march_browser_compile.ml`): parse, desugar, the browser stdlib,
`check_module_full`, cascade suppression, rendered with `Errors.render_diagnostic`. It resets
`Errors.explain_hints_shown` per call, since one call is one `--check` run (without that, a
second check lost its `run march --explain` line). Until the bot regenerates
`march_compile.js` after merge, the page says the checker is coming instead of failing.

Speed (2026-11-05 follow-up, after "Check doesn't work and examples load slowly"):
`gen-error-tour.py` also writes `docs/assets/error-tour/examples.json` (`{name: {file,
source, output}}`), so picking an example or pressing Check on an unedited one shows the
pinned native output at once, with no compiler: 8 ms, and Check works on the unedited
examples even before the bot rebuilds the bundle. The compiler (about 3 MB) starts loading
on the first edit, and only an edited program goes through `marchCheck(source, filename)`,
which now takes the example's file name so its header matches. The stdlib is parsed once
per page (`checker_stdlib`). Measured in Chromium: `marchCheck` took ~1,100 ms called from a
task (click, timer, rAF, MessageChannel) and ~70 ms from a microtask, with no such gap in
Node; the playground calls it from a promise callback. The cause is not established.

Not in the playground, with the reason on the page: the refinement examples (no z3 in a
browser), `06-misspelled-module` (the module suggestion reads stdlib files from disk), and
`28`/`29` (they need `Session`, which the browser stdlib bundle doesn't load).

**Guard.** `scripts/browser-repl-smoke.js` (CI job `browser-repl`) runs `marchCheck` on every
playground program and requires `examples.json`'s native output byte for byte, header file
name included (`gen-error-tour.py --check` keeps `examples.json` and the page current). Proven red
by adding `06-misspelled-module` to the playground. A message change that reaches one of
these programs turns it red until `scripts/gen-error-tour.py` is rerun.
