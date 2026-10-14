`[P3]` 57 of 151 cookbook "run" blocks fail in the browser REPL (2026-10-14)

Every ` ```march ` block in `docs/cookbook/*.md` and `docs/coming-from-*.md` gets a
"run" button (`docs/assets/cookbook.js`). Fed one at a time to the browser REPL
(`marchResetSession` then `marchEvalLine`, the same path the button takes), 57 of 151
return an error. The result is identical on the July bundle and the 2026-10-14 release
bundle, so this is not a bundle regression.

Seen on `basics.md` alone:
- `unbound variable: n` / `score`: snippets that use a binding from an earlier block.
- `no member 'from_list' in module 'HashMap'`: `hash_map.march` is loaded for the live
  compiler but not for the interpreter (`js/march_browser.ml` `browser_stdlib_files`).

Reproduce: load `docs/assets/march_stdlib.js` and `march.js` into a Node `vm` context
as `scripts/browser-repl-smoke.js` does, and evaluate each fenced block.

Relevant to the "Try it" work: decide per block whether to fix the snippet, load the
module in the browser, or mark the block display-only.
