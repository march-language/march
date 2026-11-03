# Browser REPL: a pasted stdlib-doc transcript runs one prompt line at a time

Landed 2026-10-20. `docs/assets/march-repl.js` (hand-maintained; not one of the
bot-regenerated bundles), `scripts/browser-repl-smoke.js`.

**Report.** On https://march-lang.org/docs/stdlib/Sort.html the "Try it" REPL printed
`[1, 2, 2, 5, 8]` for `Sort.heapsort_by([8, 5, 2, 9999999, 1, 2], fn a -> fn b -> a <= b)`,
as if heapsort had dropped `9999999`. Heapsort is correct everywhere (native interpreter,
compiled, both browser bundles). The submitted input was two lines: the call, and the doc
transcript's expected-output line `[1, 2, 2, 5, 8]` under it. March evaluates a multi-line
input as one block and prints the value of the last expression, the literal list. The
second line came from the stdlib page's Copy button, which copies the whole transcript
(prompt lines `march> …` and output lines); the `march> ` shown in the REPL history is a
CSS `::before`, so a pasted prompt line looks harmless.

**Fix.** `MarchRepl.splitTranscript(code)`: when any line of the submitted text begins
with `march> ` (after leading whitespace), the text is a transcript. Each prompt line with
the prefix stripped is one input, in order; every other line is expected output and is
dropped. Text with no prompt line is returned as the single input it always was, so
single-line and hand-written multi-line inputs are unchanged. `submit()` feeds the inputs
to the existing in-order queue (`_run`), so each gets its own echo and result. The
function is a static on `MarchRepl` so it can be tested without a DOM.

**Test.** `scripts/browser-repl-smoke.js` gained a "Pasted doc transcript" section that
loads `march-repl.js` under `vm` (from `docs/assets/`, independent of the ASSETS_DIR CI
passes for the freshly built bundles), asserts the split, and runs each input through
the bundle: the Sort.html paste prints `[1, 2, 2, 5, 8, 9999999]`; a two-prompt transcript
with indentation and a blank line yields two inputs; prompt-free text is one input.

**Not covered.** The node harness shows the live page could only have printed the
reported value from a paste with the prefix already removed by hand: with `march> ` left
on line 1 the REPL answers `unbound variable: march`. A prefix-free two-line paste is
indistinguishable from a deliberate block (`let y = 40` / `y + 2`), so it is left alone.
The lasting fix is on the page side: the Copy button in march_doc
(`lib/march_doc/doc_html.march`, "Copy buttons on pre blocks") should copy only the
inputs, or the output lines as comments; that lives in the march_doc repo.
