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

## Done (2026-11-07)

`scripts/cookbook-run-blocks-check.js` now runs every ` ```march ` block on every
`layout: cookbook` page (the 16 `docs/cookbook/*.md` pages and the three
`docs/coming-from-*.md`) through the browser REPL the way the run button does
(`scripts/browser-repl-node.js`: on-demand stdlib loading, `march>` transcripts split
into their prompt lines), each block in a fresh session, with a 20 s limit per block.
CI's `browser-repl` job runs it against the fresh build. On the 2026-11-07 bundle it
found 54 failing blocks of 151; now 118 run and 33 are display-only, 0 fail.

What each failure needed:
- **A REPL bug** (2 blocks, `html.md`): `~H"..."` desugars to `IOList.from_strings`, but
  the on-demand loader (`referenced_modules` in `js/march_browser.ml`) only saw dotted
  names in the source, so IOList never loaded (`unbound variable: IOList.from_strings`).
  A sigil now names the module it desugars into: `~H` gives IOList, any other `~name`
  gives Sigil. Pinned by a `browser-repl-smoke.js` case. (`HashMap` from the original
  report already loaded on demand since the module index landed.)
- **Wrong snippets**: `1_000_000` (March has no digit separators; it lexed as `1`
  applied to `_000_000`), `find_user`/`fetch_user` with a comment for a body (a parse
  error), and `-2147483648` as a max seed in `parallel-data.md` (past the browser's
  32-bit Int; the scores are non-negative, so it is `0` now).
- **A binding from an earlier block** (`n`, `score`, `nums`, `shape`, `tv`, `jv`, `arr`,
  `original`, `scores`, `v`, `urls`, `expensive_computation`): a line or two of setup at
  the top of the block. Where the block is also a notebook cell (no `scroll:skip`),
  the setup is only a `let` (`vault.md`, `parallel-data.md`), so
  `scripts/gen-scrollmd.py --check` still passes.
- **Too slow in the interpreter**: `RRB.range(1, 1000001)` plus two `pmap`s ran past
  20 s; the example uses 1000 elements (the performance section is separate).
- **Display-only** (33 blocks), marked `<!-- repl:skip -->` on the line before the fence:
  `File`/`Dir`/`HttpServer`/`System.exit` programs, all the `Js.Dom` examples in `dom.md`
  (Js.Dom works only in a `--target js` program; in the REPL it fails with
  `march_ffi_marshal_reset not implemented`), `...`-bodied sketches in `linear-types.md`,
  and one-liners that only continue the block above (`Option.unwrap_or(find_user(42), …)`,
  `spawn(Counter)`, `Task.race` over undefined sources). `docs/assets/cookbook.js` gives
  such a block a copy button but no run button (`displayOnly`: the comment survives
  kramdown as a sibling of the block's wrapper).

Not changed: actor blocks run without error, but an actor's `println` (e.g. the
Counter's `Report`) prints nothing in the browser REPL; the check looks at errors, not
output.
