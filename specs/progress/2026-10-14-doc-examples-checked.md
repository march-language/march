# Doc examples: checked natively, runnable programs, 19 more modules runnable (2026-10-14)

This is project 4 of 4 toward runnable documentation examples (projects 1-3:
`specs/2026-10-14-browser-repl-bundle-design.md`,
`specs/2026-10-14-browser-repl-modules-design.md`,
`specs/2026-10-14-doc-try-it-design.md`).

- **`scripts/check-stdlib-doctests.py`**
  - Checks every module opted in with `-- doc: try`, as well as the old hand-kept
    allowlist.
  - Feeds every expression of a module, in file order, to one REPL session, so `let`
    lines set up later ones.
  - Compares non-primitive expected values with `(expr) == (expected)`.
  - Reads `march>` lines in `--` header comments too.
  - Interprets ```` ```march try ```` programs natively; each must exit 0 and match a
    following ```` ```output ```` block.
  - Result: 100 → 402 examples run, plus 1 program.
- **Browser REPL**
  - Desugars each input. A `|>` pipe used to fail with "pipe expression reached
    evaluator".
  - Passes an erased `()` per `main` parameter, as native does, so
    `fn main(io : Cap(IO))` runs.
  - `browser-repl-doc-sweep.js` reads header-comment transcripts. It now covers 523
    examples, 510 clean and 13 expected failures.
- **Converted to checked transcripts and opted in.** These 19 modules wrote examples
  as `expr  -- result` comments: String, Duration, Json, IOList, Uri, Html, Xml, Toml,
  Crypto, UUID, Regex, AhoCorasick, DateTime, Dns, Task, Vault, Seq, IO, plus Actor's
  module example as a checked program. Examples that are random, time-based, network,
  stdin, or above the browser's 32-bit Int stay plain code.
- **"Try it"** now covers 248 examples (498 inputs) on 33 pages, all running in the
  browser (`check-doc-try-it.js`).
- **Wrong docs found and corrected (behaviour unchanged).**
  - String: `split(s, "")` splits bytes; the NFD example was NFC; error texts; tuple in
    `split_first`; invalid hex and `1e10` literals.
  - Crypto: String vs Bytes types, a wrong `base64_decode` error text.
  - UUID: `v5` type error, `_` digit separators, version range.
  - Regex: header named a nonexistent function.
  - AhoCorasick: match count.
  - IOList: hash value.
  - Html: `Html.to_string` does not exist.
  - Task: `await!` does not exist; `race` error text; `scope` semantics.
  - Vault: key encoding, `keys` return type, Tuple/Ctor keys, Bool/Int keys.
  - Uri: parse, merge and merge_strict.
- **Real bugs found, not fixed here.**
  - Uri `merge_strict` traversal off-by-one, plus parse/merge (security-relevant;
    separate task).
  - Native REPL: NativeArray i32 sign (branch fix/repl-i32-native-array-sign),
    `Err(:atom)` segfault (separate task), and the quirks in
    `specs/todos/2026-10-14-native-repl-quirks-found-by-doctests.md`.
  - `String.split(s, "")` byte splitting:
    `specs/todos/2026-10-14-string-split-empty-separator-bytes.md`.
