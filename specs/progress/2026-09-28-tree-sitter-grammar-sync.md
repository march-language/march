# tree-sitter-march parses the March the compiler accepts (grammar sync)

Done 2026-09-28. Was `specs/todos/2026-08-04-tree-sitter-grammar-drift.md` [P2]
("the tree-sitter grammar still fails on 150 of 199 real March files").
Followed `specs/2026-09-23-tree-sitter-grammar-sync-design.md` (§5.4 order,
§6.1 check, §8 red proofs). Leftover tooling decisions from that design are
filed as `specs/todos/2026-09-28-tree-sitter-followups.md`.

## Result

Corpus: every `.march` under `stdlib/ test/ examples/ bench/
specs/lang/grammar/parse/` that the compiler's parser accepts (919 of 923; a
parse-only harness over `March_parser.Parser.module_` plus the token filter
decided acceptance). Failing = the file's tree has an ERROR or MISSING node.
Grammar built in a private HOME from an explicit path each round (design
§1.1); after every round the failing set had to be a SUBSET of the previous
one, and it was every time (zero regressions).

| round | change | failing (of 919) |
|---|---|---:|
| base | origin/main grammar | 713 |
| b1 | record fields `a: v`, parenthesised expressions, float operators, all string escapes, lower-case sigils, `fn ->` | 547 |
| b2 | unit / parenthesised / record / nat types, nested `fn`, `let?` `let*` `linear let`, default args `\\`, `@[...]` attributes, `fn send`, `fn f[bounds]`, un-reserving `test`/`describe`/`setup`/`setup_all`/`send` | 434 |
| b3 | patterns: list, record, `as`, or `\|`, parenthesised, `Mod.Ctor` | 407 |
| b4 | match-arm bodies are statement sequences (`[block_body]` GLR conflict), leading/`\|` arm separators | 268 |
| b5 | nested `mod`, `derive`, `satisfy`, `resource`, `transitions`, `app`, `opaque`/`always_linear`/`tag` types, extern modifiers + `= "sym"` + `consume` params, interface `requires` + default methods, `impl A.B(T)`, `proof cap … with`, scoped `needs`; actor `init(params)`, `mailbox`, `supervise`, `on_stop`; protocol labels, `or crash do`, `choose by`, `role`, `may`, `stop`, `loop name` | 160 |
| b6 | lambda bodies: `let`s then one expression in general, a statement sequence as a call argument (the compiler's `call_arg`) | 54 |
| b7 | `_stmt_lparen` external scanner token: a line-initial `(` starts a statement or arm, never a call (the compiler's `LPAREN_STMT`), with an error-recovery guard | 8 |
| b8 | `use A` (bare), `spawn(A, args)`, list comprehensions, cond-form `match do` | **0** |

Also measured, same grammar:

- `specs/lang/{types,golden,...}` (everything under `specs/lang` outside
  `grammar/`, 462 accepted files): 282 → 0.
- The todo's original corpus, `~/code/mgrep/lib` + `~/code/forgepm/lib` (94
  accepted files): 67 → 0.
- The four files the compiler rejects (`bench/http_get*.march`,
  `test/imports/test_sibling_parse_error/test_b.march`) still fail in
  tree-sitter; they are the whole of `tree-sitter-march/known-failures.txt`.
- Robustness: every corpus file truncated at 25/50/75/90% (5,524 inputs)
  parses to completion in about a second, no crash or hang.
- Speed: average 22.0 KB/ms against 9.5 before (error recovery was the slow
  path); `stdlib/session_node.march` (3,099 lines) 6.4 ms against 22.6 ms.
  `src/parser.c` grows from 861 KB to 2.06 MB.

## Trees, not just ERROR counts

ERROR-free is not proof a tree is right: an arm split in the wrong place can
still be ERROR-free. `test/corpus/grammar_sync.txt` (13 cases) pins the shape
where the grammar has to guess the compiler's newline handling: an arm body of
several statements ending at the next arm, a line-initial tuple pattern
starting a new arm, a line-initial `()` not becoming a call, a call-argument
lambda taking statements while a `let`-bound lambda stops before the next
statement, `|` separators against or-patterns, cond `match do`, `choose`
branches with `stop`. Disabling the `_stmt_lparen` token turns three of them
red.

Existing corpus: 10 of 56 expectations changed, each only by an intended
change, checked mechanically (whitespace-normalised old vs new, with the
intended changes undone on the new tree): arm and lambda bodies gained a
`block_body` wrapper, a record type is a `record_type` node, `impl`'s
interface is a `module_path`, `needs` items are `scoped_capability`. Three
inputs used `{ a = 1 }`, which the compiler rejects; they now say `{ a: 1 }`.
Only the changed expectations were rewritten, so the corpus diff is small.

## Queries

`tree-sitter-march/queries/highlights.scm` needed `impl_def interface:` →
`module_path`, and gained the new keywords and `@[...]` attributes.
`zed-march/languages/march/highlights.scm` and `outline.scm` had been
failing to compile since 2026-08-04 (`module_def name:` became a
`module_path`; design §4.1) and now compile, with the same `impl` fix.

## Gate

`scripts/check-tree-sitter.sh` (design §6.1: freshness, corpus, queries,
list ratchet, `--self-test`) and a `tree-sitter` job in `ci.yml` running it
with tree-sitter-cli 0.26.7. Each check was made to go red once: a grammar edit
without regenerating (stale `parser.c`), a generate error (not masked by the
old `parser.c`), a new unparseable file, a stale known-failures entry, a broken
Zed query, a changed corpus expectation. The query check was green on a broken
query at first: under `pipefail` the query command's own non-zero exit made
the `if` false, and BSD grep ignored `\|`. Both fixed.

`tree-sitter-march.wasm` regenerated with `tree-sitter build --wasm`
(wasi-sdk); a `--wasm` parse of all 919 files is clean.
