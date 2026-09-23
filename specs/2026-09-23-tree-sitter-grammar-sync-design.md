# Tree-sitter grammar sync: re-measure, fix, and keep it from drifting again

**Date:** 2026-09-23
**Status:** design only; nothing here has landed.
**Closes (when built):** `specs/todos/2026-08-04-tree-sitter-grammar-drift.md` [P2].

**Method:** every claim in §2 and §3 was checked on 2026-09-23 against
`origin/main` at `154cf1754`, either by opening the cited file or by running the
command shown. Numbers come from a scratch copy of `tree-sitter-march/` built and
loaded by explicit path (§1.1). Nothing under `tree-sitter-march/` was modified.
Where a claim could not be verified it says so.

---

## Decisions needed

**D1. What shape is the CI gate?**
Options: (a) a hard gate, every accepted `.march` file must parse ERROR-free;
(b) a count ratchet, a checked-in number that may only go down; (c) a
**list ratchet**, a checked-in list of files allowed to fail, where every file
not on the list must parse ERROR-free and every listed file that now parses
must be removed from the list.
**Recommendation: (c), plus a hard gate on `specs/lang/grammar/parse/` once
Stage 4 has emptied it.** A hard gate is unreachable today (631 of 831 accepted
files fail, §1.2). A count alone cannot see a change that fixes ten files and
breaks two; the todo's own "Approach" section already requires the subset
check, and a list *is* the subset check. The stale-entry rule makes the list
shrink monotonically without anyone remembering to shrink it.

**D2. Does the generated `src/parser.c` stay committed?**
**Recommendation: yes, and CI proves it fresh.** Zed compiles the grammar from
the git tree at the pinned rev and needs `parser.c` and the headers present
(`.gitignore:26-27`, `specs/zed-extension-maintenance.md` "Directory
structure"). CI regenerates with a pinned CLI and fails on `git diff
--exit-code tree-sitter-march/src`. Today's committed `parser.c`,
`grammar.json` and `node-types.json` are byte-identical to a fresh
`tree-sitter generate` with CLI 0.26.7 (§2.3), so this check starts green.
Cost to accept: the prototype's GLR conflicts grow `parser.c` from 861 KB to
2.19 MB.

**D3. What happens to `tree-sitter-march/tree-sitter-march.wasm`?**
Nothing in the repo loads it (§4). It is hand-synced, so it silently goes stale
on every grammar change, and the todo's Acceptance section makes regenerating it
a manual step. **Recommendation: delete it, unless you know of a consumer
outside this repo.** If one exists, CI builds it (`tree-sitter build --wasm`)
instead of anyone committing it. I could not check whether a wasm build works
on the CI runner without Docker or a wasi-sdk download; that is unverified.

**D4. Where does the job run, and when?**
**Recommendation: a new job in `.github/workflows/ci.yml`, `ubuntu-24.04`
only, with no opam and no dune.** It needs the tree-sitter CLI (pinned to
0.26.7), a C compiler and `bash`. Measured cost of the work itself is under 3 s
(§6.4); runner setup dominates. One Linux leg is enough: tree-sitter output does
not depend on the OS, and macOS minutes are the scarce budget (5 concurrent
org-wide). It runs under ci.yml's existing `paths-ignore: ['**.md']` filter,
which is right because any `.march` or grammar change can move the result.

**D5. Should `grammar.js` be derived from `parser.mly`?**
**Recommendation: no generation, but derive one cheap check.** Generating a
tree-sitter grammar from menhir is not feasible (§5.2). What *is* cheap and
catches the commonest kind of drift, a new keyword: a check that every
keyword in `lib/lexer/lexer.mll`'s `keyword_table` (78 today) appears as a
literal in `grammar.js` or on a small checked-in allowlist. Today 32 are
missing (§3.4).

**D6. Who keeps it green?**
**Recommendation: the PR that changes the surface syntax.** A PR adding syntax
to `parser.mly` or `lexer.mll` either extends `grammar.js` or adds its new
fixtures to the known-failures list, with a `specs/todos/` entry, in the same
PR. The list edit is the visible cost that stops silent drift. Add a line to
CLAUDE.md's "Keeping specs up to date" section saying so.

**D7. Fix the two broken Zed queries now, separately from the grammar work?**
`zed-march/languages/march/highlights.scm:57` and `outline.scm:9-11` no longer
compile against the grammar (§4.1): tree-sitter rejects them as "Impossible
pattern". **Recommendation: yes, fold it into Stage 0**, because Stage 0's query
check fails on them anyway. It is a two-line fix (`(module_def name:
(module_path) ...)`).

---

## 1. Measurement

### 1.1 How the numbers were produced, and how I know they measured this grammar

The todo warns that `tree-sitter parse` can silently read the main repo's
grammar through `~/.config/tree-sitter/config.json`, and that
`~/.cache/tree-sitter/lib/march.dylib` is not invalidated. I avoided both by
never letting the CLI find a grammar on its own:

```bash
S=<scratch>/ts                                   # scratch dir, outside the repo
cp -R tree-sitter-march "$S/tsm"
export HOME=$S/home XDG_CACHE_HOME=$S/home/.cache  # private: no config.json, no cached dylib
cd "$S/tsm"
tree-sitter generate                              # 0.26.7
tree-sitter build -o "$S/march.dylib"             # explicit output path
cd <worktree>
tree-sitter parse -l "$S/march.dylib" --lang-name march -q -s --paths corpus.txt
```

With the private `HOME` the CLI prints "You have not configured any parser
directories!" on every call, which is the evidence that no config file was
read. A file counts as failing when its summary line carries `(ERROR ...)` or
`(MISSING ...)`.

**Proof that the numbers move with this grammar.** I perturbed a second scratch
copy (deleted `optional($.when_guard),` from `match_arm`), regenerated, built to
a different path and re-measured: 646 failing became 647, and the one new file
was `test/snapshots/src/guard_match.march`, the file whose point is a guard.
Re-measuring with the unperturbed dylib reproduced the original failing list
byte for byte. Every prototype step in §5.4 also moved the count, which the
cached dylib could not have done.

**Three traps found while doing this, all of which the CI script must avoid:**

1. **A failed `tree-sitter generate` still leaves a buildable parser.** My first
   two perturbations tripped "Reserved word 'pfn' must be a token", generate
   exited 1, the old `src/parser.c` stayed in place, and `tree-sitter build`
   happily built the *unperturbed* grammar. The counts matched exactly and
   looked like "the perturbation had no effect". The script must delete
   `src/parser.c` before generating, or check generate's exit status.
2. **`tree-sitter test -l <dylib>` ignores `-l` in 0.26.7.** It used the cached
   `march.dylib` keyed by language name. Proof: with the cache holding the
   committed grammar, `tree-sitter test -l <prototype.dylib>` reported 56/56
   passing, and `tree-sitter test -p <prototype dir>` reported 8 failures. Use
   `-p <grammar dir>` (which implies `--rebuild`) for `tree-sitter test`.
3. **Plain `tree-sitter test` does not rebuild when you `cd` to a different
   grammar directory.** Running it in the committed copy and then in the
   prototype copy reused the first build for both.

### 1.2 Results

Corpus: every `.march` under `stdlib/`, `test/`, `examples/`, `bench/`,
`specs/lang/grammar/parse/` and `specs/lang/grammar/reject/`, 849 files. Each
file was also run through the real compiler with
`_build/default/bin/main.exe --emit-core-ast <file>`, which prints JSON whose
`"module"` field is `null` exactly when parsing (lexer + menhir + token filter)
failed. "Accepted" below means `module` was non-null. I ran this on all 849
files, not a sample.

| directory | files | accepted by menhir | tree-sitter fails (accepted) | % |
|---|---:|---:|---:|---:|
| `stdlib/` | 124 | 124 | 100 | 80.6% |
| `test/` | 564 | 563 | 439 | 78.0% |
| `examples/` | 41 | 41 | 30 | 73.2% |
| `bench/` | 67 | 64 | 35 | 54.7% |
| `specs/lang/grammar/parse/` | 39 | 39 | 27 | 69.2% |
| **total (excl. `reject/`)** | **835** | **831** | **631** | **75.9%** |

Files menhir itself rejects, reported separately:

- `specs/lang/grammar/reject/`: 13 of 14 rejected by the parser (`r05_letq_last_in_block`
  parses and is rejected later, which is why it counts as accepted). Tree-sitter is
  error-tolerant, so it only flags 10 of the 13; `r03`, `r09` and `r14` parse
  clean. That is expected and not a defect: tree-sitter need not reject what
  menhir rejects.
- `bench/http_get.march`, `bench/http_get_close.march`,
  `bench/http_get_keepalive.march`: **menhir rejects these** ("March `if`
  expressions always need an `else` branch", e.g. `bench/http_get.march:9`).
  They are dead benchmarks outside the bench gate; a separate cleanup, not this
  design.
- `test/imports/test_sibling_parse_error/test_b.march`: intentionally invalid.

**Against 4 August (150 / 199, 75.4%).** The corpus differs (that one was
`stdlib/` plus `~/code/mgrep/lib` and `~/code/forgepm/lib`), so the comparison
is by rate: 75.9% now versus 75.4% then. To check the two measurements agree,
I rebuilt the August corpus: `stdlib/` as of `fc8f94ae8` (the commit that
closed the August fix, 112 files) plus today's mgrep and forgepm (94 files).
Today's grammar fails **155 / 206 (75.2%)** on it. The grammar has not changed
since `fc8f94ae8` (`git diff fc8f94ae8 HEAD -- tree-sitter-march` is empty), so
the rate held steady while the language grew: `stdlib/` alone went from 112 to
124 files and from 88 to 100 failures.

The wider `specs/lang/` corpora (`types/accept`, `types/reject`, `golden/`, 462
files) were not part of the brief. For reference, today's grammar fails 282 of
them and the §5.4 prototype fails 17. They are cheap to add to the gate later.

---

## 2. Ground truth: the compiler's grammar

### 2.1 Where the real grammar lives

- `lib/lexer/lexer.mll` (320 lines): keywords in `keyword_table`
  (`lexer.mll:38-100`, 78 entries), sigil prefixes `~X` and `~name`
  (`lexer.mll:76-77`), nested block comments (`lexer.mll:142`, `:238`), string
  interpolation with a brace-depth counter (`lexer.mll:7-13`, `:165-175`,
  `:245-300`), triple-quoted strings (`:272`). `let?` and `let*` are two tokens
  (`LET` plus `QUESTION` at `lexer.mll:212`, or `STAR`), not one.
- `lib/parser/parser.mly` (2109 lines), menhir.
- `lib/parser/token_filter.ml` (645 lines), which sits between them and makes
  the stream context-sensitive. §3 covers what it does and which parts a
  tree-sitter grammar must reproduce.
- `specs/lang/grammar.md` is the prose reference, and
  `specs/lang/grammar/{parse,reject}/` (39 + 14 files) is its conformance
  corpus, run by `specs/lang/grammar/check_grammar.sh` via `dune build
  @grammar-check` (`test/dune:1103-1110`), in CI's `conformance` job
  (`.github/workflows/ci.yml:519-523`). That check runs only the compiler.

### 2.2 What `tree-sitter-march/` contains

- `grammar.js` (582 lines), `src/scanner.c` (45 lines, handles only nested
  `{- -}` block comments), generated `src/parser.c`, `grammar.json`,
  `node-types.json`, `src/tree_sitter/*.h`, all committed.
- `queries/highlights.scm` and `queries/injections.scm`.
- `test/corpus/`: 11 files, 56 cases. All 56 pass against the committed
  grammar (`tree-sitter test -p`).
- `tree-sitter-march.wasm` (118 KB, committed).
- The `sigil_expression` comment at `grammar.js:509` says the external scanner
  tokenizes HTML in sigil content. It does not; `scanner.c` knows only block
  comments. The comment is stale.

### 2.3 Is the committed generated code fresh?

Yes. In the scratch copy, `tree-sitter generate` (0.26.7) reproduced
`src/parser.c`, `src/grammar.json` and `src/node-types.json` byte for byte
(`cmp` clean on all three). `parser.c` declares `LANGUAGE_VERSION 15`. The last
commit to touch any of it is `fc8f94ae8` (4 August).

### 2.4 Does any CI job touch tree-sitter today?

No. `grep -rn tree-sitter .github/workflows/` finds nothing; neither do
`scripts/` nor any `dune` file. Nothing checks that the grammar parses anything,
that the corpus tests pass, that `parser.c` is fresh, or that the query files
compile.

---

## 3. What the token filter does, and what tree-sitter needs for each

`token_filter.ml` exists because parts of March are not context-free over a
newline-free token stream. For each behaviour, the question is whether a
tree-sitter grammar needs an external scanner, GLR conflicts, or nothing.

| Token-filter behaviour | Where | Tree-sitter answer | Evidence |
|---|---|---|---|
| Soft keywords demoted to identifiers unless the next token fits: `test`/`describe` (STRING), `setup`/`setup_all` (DO), `restart`, `backoff`, `shutdown`, `may`/`or` (`crash`), `role` (UPPER) | `token_filter.ml:52-160` | **Nothing extra**: leave these out of `reserved`. Tree-sitter's keyword extraction lexes a word as a keyword only where the parse state allows it. | Prototype step p15: unreserving `test`/`describe`/`setup`/`setup_all`/`send` fixed 11 files (`fn describe(...)`, `fn send(...)`) with no regressions. |
| `init` followed by `(` becomes `INIT_PAREN` | `token_filter.ml:134-149`, `parser.mly:791-797` | **A declared GLR conflict** (`[actor_init, unit_expression]`, `[actor_init, _lparen]`). No scanner needed. | Prototype p12 generated only after adding the conflict; 0 regressions. |
| `NL` passes to the parser only inside a `match` body, where it separates arms; a lookahead decides whether the next line starts a new arm (`pattern ... ->`) or continues the body | `token_filter.ml:1-14`, `:297-372` (`lookahead_is_new_arm`), `parser.mly:1931-1933` (`arm_sep`) | **A declared GLR conflict** on `block_body` is enough in practice: a mis-split fails at the `->` and GLR drops that branch. | Prototype p7: arm bodies as `block_body` plus `[block_body]` conflict fixed 75 files, 0 regressions. ERROR-free is not proof the split is right; see §7. |
| `(` at the start of a line, after a complete expression, becomes `LPAREN_STMT`, which only group/tuple/unit and patterns accept, never a call | `token_filter.ml:590-631`, `parser.mly` `simple_pattern` (`LPAREN_STMT` alternatives) | **External scanner token.** No grammar-only fix: after `x`, `(` is a call and the newline is invisible. This is exactly the todo's "tuple pattern" cluster: `(:get, Nil) ->` and `(Some(a), Some(b)) ->` as a *second* arm. | Prototype p16: a 12-line scanner addition fixed 35 files, 0 regressions. |
| `choose by R:` branches: a lower-case label starts a branch, not a labelled message step | `token_filter.ml:29-34` (`ms_is_choose`) | **A declared GLR conflict** on `choose_branch`. | Prototype p10. |
| Cond-form `match do` (no scrutinee): arm left sides are boolean expressions | `token_filter.ml:35-39`, `parser.mly:1587-1590` | **Unsolved in the prototype.** Making the scrutinee optional collided with `constructor_pattern` versus `bare_constructor`; I dropped it. 3 `parse/` files still fail on it. Likely a separate `cond_expression` rule with its own arm type; needs design work in Stage 4. | §5.4 residue. |
| Curried-call guard `f(1)(2)` is an error | `token_filter.ml:590-601` | **Nothing**: tree-sitter does not need to reject what menhir rejects. | |
| Monadic `with ... <- ... do` context | `token_filter.ml:17-20` | Not measured; no corpus file failed on it first. | |

The lexer-level behaviours:

- **Nested block comments** are already in `scanner.c`.
- **String interpolation** `${...}` has no ERROR cost: the `string` token
  (`grammar.js:542`) swallows it as text. Highlighting the interpolated
  expression would need scanner support; that is a feature, not drift.
- **String escapes**: `grammar.js:542-548` accepts only `\n \t \\ \"`. `\r`,
  `\x00`, `\0` and `\$` all turn the whole string into an ERROR (14 accepted
  files contain one). A one-line fix, no scanner.
- **Lower-case sigils** (`~yaml"..."`, `~toml`, `~xml`) are lexed by
  `lexer.mll:77` but `grammar.js:515` allows only `~[A-Z]`.

### 3.4 Keyword coverage

Of the 78 `keyword_table` entries, 32 appear nowhere in `grammar.js`:
`dbg supervise strategy max_restarts within restart backoff shutdown may or role
permanent transient temporary one_for_one one_for_all rest_for_one requires
invariant derive satisfy in opaque resource app on_start on_stop choose by offer
always_linear tag transitions via`. After the prototype, 6 remain: `dbg
requires invariant in offer tag`. That count is the D5 check.

---

## 4. Consumers: who breaks when the grammar drifts

- **Zed**, the only real consumer. `zed-march/extension.toml` pins
  `[grammars.march]` to `repository = "file:///Users/80197052/code/march"`, `rev
  = 281261a5...`, `path = "tree-sitter-march"`. Zed compiles the grammar from
  that commit and reads highlights, brackets, indents, outline and injections
  from `zed-march/languages/march/*.scm`. The grammar at the pinned rev is
  identical to HEAD's (empty `git diff 281261a5f HEAD -- tree-sitter-march`), so
  the pin is not stale. The `file://` URL only works on one machine; flagged in
  §10.
- **The tree-sitter CLI** (`tree-sitter highlight`), through
  `tree-sitter-march/queries/`.
- **Not consumers**, checked:
  - `lsp/` never mentions tree-sitter (`grep -rni tree.sitter lsp` is empty). Its
    semantic tokens come from the typechecked analysis
    (`lsp/lib/server_state.ml:259`), and it only emits four token types (type,
    enumMember, function, variable; `server_state.ml:260-263`). Keywords,
    strings, comments and all structure still come from tree-sitter.
  - `editors/vscode-march-debug/` is a debug adapter client only; it contributes
    no grammar. There is no VS Code syntax extension in the repo.
  - The docs site highlights with Rouge (`docs/_config.yml:7-11`), not
    tree-sitter.
  - No `.gitattributes` and no TextMate grammar; GitHub Linguist is unaffected
    either way.
  - `tree-sitter-march.wasm`: no file in the repo refers to it (searched for
    `tree-sitter-march.wasm` and every `.wasm` mention outside the compiler's
    own wasm target).

### 4.1 A live breakage found while checking consumers

`tree-sitter query -p <committed grammar> <query> stdlib/list.march` fails for
two of the Zed query files:

```
zed-march/languages/march/highlights.scm  Query error at 57:13. Impossible pattern:
    (module_def name: (type_identifier) @namespace)
zed-march/languages/march/outline.scm     Query error at 11:3. Impossible pattern:
      name: (type_identifier) @name) @item
```

`fc8f94ae8` (4 August) changed `module_def`'s `name` field from
`type_identifier` to `module_path`; the Zed queries were last edited on 26 March
(`d9f19b748`). Tree-sitter compiles a query file as a unit, so I expect Zed
loses highlighting and the outline for March entirely rather than just module
names. I did not open Zed to confirm that. The copies under
`tree-sitter-march/queries/` do compile, and they are *different files* from
Zed's (`diff -q` differs), which is how one set rotted unseen.

Also stale: `docs/tooling.md:1013` says to point Zed's "Install Dev Extension"
at `tree-sitter-march/`; `specs/zed-extension-maintenance.md` step 7 says
`zed-march/`, which is the directory that holds `extension.toml`.

---

## 5. Where the failures come from

### 5.1 Clusters, measured by fixing them

Classifying first-ERROR sites by regex was unreliable: tree-sitter's error
recovery often starts the ERROR node at the enclosing declaration, and one
missing construct (say, record literals in `init { v: 0 }`) shows up as an
error at the next `on` handler. So the decisive evidence is a prototype (§5.4)
that adds one construct at a time and records how many files each step turns
ERROR-free, with a subset check at every step. The table is ordered by that
count. "Files containing it" is an approximate `grep -lE` over the 832 accepted
files and over-counts where the pattern also matches types or patterns; "n/a"
means the construct is not greppable.

| # | Construct | Files fixed (marginal) | Files containing it | Example |
|---|---|---:|---:|---|
| 1 | Multi-statement lambda bodies in call arguments (`List.map(xs, fn x -> let y = .. y)`) plus `\|`-separated one-line arms | 93 (80 from lambdas alone) | n/a | `bench/actors/fanin_flood.march:51` |
| 2 | Parenthesised expression `(a + b)`: no rule at all, only unit and tuple | 79 | n/a | `stdlib/bytes.march:213` |
| 3 | Multi-expression match-arm bodies | 75 | n/a | `bench/alphadev_sort.march:12` |
| 4 | Declarations: nested `mod`, `derive`/`satisfy`, `resource Name`, `transitions`, `app`, `always_linear`/`opaque type`, extern `blocking`/`raises` and `= "symbol"` | 50 | nested mod 14, derive 18, extern symbol 26, resource 5 | `test/native/boxed_adt_float_field.march:16` |
| 5 | Unit type `()` and parenthesised types `(Int) -> Int` | 45 | 118 | `test/native/bare_none_print.march:10` |
| 6 | Record literal `{ f: v }`: the rule exists but uses `=` (`grammar.js:502`) | 44 | ~180 | `test/native/actor_counter.march:10` |
| 7 | Patterns: list `[a, b]`, record, `as`, or `1 \| 2`, parenthesised, qualified `Mod.Ctor(...)` | 42 | n/a | `test/two_node/stall/node_a.march:26` (`Membership.Alive ->`) |
| 8 | Nested `fn` inside a block | 36 | n/a | `stdlib/array.march:40` |
| 9 | Line-initial `(` as a new statement or arm: the `LPAREN_STMT` scanner token | 35 | n/a | `stdlib/option.march:159` |
| 10 | Float operators `+. -. *. /.` | 26 | 62 | `bench/array_numeric.march:20` |
| 11 | Actor body: `init(params)`, `mailbox`, `supervise do ... end`, `on_stop` | 24 | supervise 27, on_stop 4 | `test/native/actor_on_stop.march:63` |
| 12 | Lexical: string escapes, lower-case sigils, `fn ->`, record types, default args `\\`, `consume`, `spawn(A, args)` | 40 | escapes 14, `fn ->` 14 | `test/stdlib/test_toml.march:519` |
| 13 | Soft keywords reserved by mistake (`fn describe`, `fn send`) | 11 | n/a | `stdlib/node.march:83` |
| 14 | `@[...]` attributes | 10 (most of the 103 files with one also need #15) | 103 | `test/two_node/cluster_ap/node_a.march:14` |
| 15 | Protocol steps: `choose by`, labelled messages, `or crash do`, `role ... needs`, `may crash`, `stop` | 5 | protocol 85, choose 24 | `specs/lang/grammar/parse/p20_protocol_choose_session_type.march:5` |
| 16 | `let?` / `let*` | 5 | 4 | `specs/lang/grammar/parse/` |

**The todo's three repros, re-checked.** (1) Record literal: fixed by row 6.
(2) "Tuple pattern mixing an atom and a list literal": the real causes were
list patterns (row 7) and, for second and later arms, the missing
`LPAREN_STMT` newline rule (row 9); the prototype parses it clean. (3)
`resource R do 1 end` **is not valid March**: the compiler rejects it with
"Parse error in declaration". The real form is the bare `resource Name`
(`parser.mly:1328-1330`), which the prototype handles.

### 5.2 Why not generate `grammar.js` from `parser.mly`

- Menhir actions carry work the grammar depends on: `error_raise` productions
  that exist only to give messages (`parser.mly:744-748`, `:1073-1078`), soft
  keyword checks inside actions (`c.txt <> "crash"` at `:1022-1026`), and list
  folds that build the AST.
- A third of the real grammar is not in `parser.mly` at all. It is the token
  filter's newline and lookahead logic (§3), and no tool translates OCaml
  control flow into tree-sitter rules or a scanner.
- Tree-sitter wants a different grammar: named, highlightable nodes, operator
  precedence as `prec.left(n)` instead of menhir's precedence declarations
  plus stratified `expr_or`/`expr_and`/... rules, and error recovery.
  Mechanical output would be hard to write queries against.

What *can* be derived is the keyword set (D5), and the conformance corpus
(§6.2) is the other half: it states the behaviour both grammars must share,
without either being derived from the other.

### 5.3 Why not drop tree-sitter for LSP semantic tokens

The LSP emits four token types, needs a successful parse and typecheck to emit
anything, and does nothing for brackets, indentation, outline or injections.
Zed needs a tree-sitter grammar for all of those regardless. Semantic tokens
are a layer on top, not a replacement.

### 5.4 Prototype (scratch only, not proposed as-is)

In the scratch copy I applied the fixes cumulatively, one step at a time. After
each step: delete `src/parser.c`, generate, build to a new dylib, re-measure all
849 files, and check that the new failing set is a subset of the previous one.
**Every step had zero newly broken files.** The diff is `grammar.js` +114/-30
and `scanner.c` +11/-7.

| step | failing (of 849) |
|---|---:|
| baseline | 646 |
| p1 record `:` | 602 |
| p2 parenthesised expr | 523 |
| p3 float ops | 497 |
| p4 unit / paren types | 452 |
| p5 `@[...]` | 442 |
| p6 nested `fn` | 406 |
| p7 block arm bodies + `[block_body]` conflict | 331 |
| p8 `let?`/`let*` | 326 |
| p9 patterns | 284 |
| p10 protocol steps + `[choose_branch]` conflict | 279 |
| p11 declarations | 229 |
| p12 actor body + `init(` conflicts | 205 |
| p13 lambda bodies, `\|` arms | 112 |
| p14 lexical misc | 72 |
| p15 soft keywords | 61 |
| p16 `_stmt_lparen` external scanner token | **26** |

Of the 26 still failing, 11 are files menhir rejects. The other **15 accepted
files**: cond `match do` (`parse/p26`, `p27`, `p28`); list comprehension
(`parse/p07`); `tag` (`parse/p21`); `doc` combined with an attribute
(`parse/p36`); `@[assume]`/`@[trusted_linear]` in positions the prototype does
not allow (`stdlib/array.march:388`, `map.march:422`, `set.march:368`,
`linear_map.march:88`); `proof cap X with Ops` (`stdlib/session.march:62`,
`stdlib/cluster_node.march:1523`, `test/native/cap_dictionary.march:25`); a
top-level `test` block in an imports fixture; and an interface default method
(`test/native/default_method_args.march:11`). By directory, accepted files
still failing: `stdlib` 6, `test` 3, `examples` 0, `bench` 0, `grammar/parse`
6. That is **15 / 831 (1.8%)**, down from 631 (75.9%).

The key scanner addition, for reference (this is the only newline-sensitive
token needed so far):

```c
// valid only where a group/tuple/unit expression or a pattern may start
bool saw_newline = false;
while (lexer->lookahead == ' ' || lexer->lookahead == '\t' ||
       lexer->lookahead == '\n' || lexer->lookahead == '\r') {
  if (lexer->lookahead == '\n') saw_newline = true;
  lexer->advance(lexer, true);
}
if (lexer->lookahead == '(' && valid_symbols[STMT_LPAREN] && saw_newline) {
  lexer->advance(lexer, false);
  lexer->result_symbol = STMT_LPAREN;
  return true;
}
```

`grammar.js` then routes `tuple_pattern`, `paren_pattern`, `unit_expression`,
`parenthesized_expression` and `tuple_expression` through
`_lparen: choice('(', $._stmt_lparen)`, while `call_expression` keeps a plain
`'('`. The production version needs the standard error-recovery guard (during
recovery tree-sitter marks every symbol valid; the prototype does not guard
this).

**Caveats on the prototype.**

- It is more permissive than the compiler in places. `let?` is one token in the
  prototype, but the compiler lexes `let` `?` as two. Every lambda body is a
  `block_body`, where the compiler allows a statement sequence only in
  call-argument position (`parser.mly:1717-1721`, `:1792-1811`) and lets plus
  one expression elsewhere (`:1627-1650`). A faithful lets-then-one-expression
  body everywhere broke 66 files, which is how I found the call-argument rule.
- 8 of the 56 existing `test/corpus` cases change shape (arm bodies gain a
  `block_body` wrapper, the record type becomes `record_type`, lambda bodies
  change). That is intended, but each needs to be reviewed, not bulk-updated;
  see the todo's note about `tree-sitter test --update`.
- ERROR-free does not mean correct. A match arm split at the wrong place can
  still produce an ERROR-free tree. §6.2 is the answer.
- `parser.c` grows from 861 KB to 2.19 MB.

---

## 6. Chosen design

### 6.1 `scripts/check-tree-sitter.sh`

One script, run locally and in CI. Everything under a `mktemp -d` with
`HOME` and `XDG_CACHE_HOME` pointed inside it:

1. **Freshness.** Copy `tree-sitter-march/` to the temp dir, delete
   `src/parser.c`, run `tree-sitter generate` and fail on a non-zero exit (trap
   1 in §1.1). Compare `src/{parser.c,grammar.json,node-types.json}` with the
   committed files and fail on any difference.
2. **Build** with `tree-sitter build -o $tmp/march.so`.
3. **Corpus tests**: `tree-sitter test -p $tmp/tsm` (never `-l`; trap 2).
4. **Queries**: `tree-sitter query -p $tmp/tsm <q> stdlib/list.march` for every
   `.scm` in `tree-sitter-march/queries/` and `zed-march/languages/march/`.
   Fail on "Query compilation failed" (today: `highlights.scm` and
   `outline.scm`, §4.1).
5. **Ratchet**: parse every `.march` under `stdlib/ test/ examples/ bench/
   specs/lang/grammar/parse/` with `-l $tmp/march.so --lang-name march -q -s
   --paths <list>`. Compare the failing set against
   `tree-sitter-march/known-failures.txt` (sorted paths, one per line, `#`
   comments allowed):
   - failing but not listed: **red**, "new tree-sitter failure" plus the ERROR
     position;
   - listed but parsing clean: **red**, "stale entry, delete this line" (this is
     what makes the list only shrink);
   - listed paths that no longer exist: red, same reason.
   Files menhir rejects go on the list with a `# menhir-rejects` comment so the
   script does not have to run the compiler.
6. **Keyword coverage** (D5): extract the quoted words from
   `lexer.mll`'s `keyword_table` block and require each to appear as `'word'` in
   `grammar.js` or in `tree-sitter-march/keywords-allowlist.txt`. Stale
   allowlist entries are red, as in step 5.
7. **Self-test** (`--self-test`, run by CI on every invocation, costs about 1.5
   s): apply a known perturbation to a copy (delete `optional($.when_guard),`
   from `match_arm`), rebuild, and assert that
   `test/snapshots/src/guard_match.march` newly fails. If it does not, the
   script is measuring something other than the grammar it just built, and
   exits red. This is the §1.1 proof, made permanent.

Why this does not flake: tree-sitter parsing is deterministic, uses no
timeouts or threads, and the job reads no global state (private `HOME`, no
config file). Pinning the CLI version (D4) keeps `parser.c` byte-stable. The
only moving input is the set of `.march` files, and a change there is exactly
what the gate is meant to see.

### 6.2 The corpus contract

`specs/lang/grammar/parse/*.march` becomes the shared contract. Stage 4 moves
it from the list ratchet to a hard gate: all 39 files must parse ERROR-free.
For the constructs where ERROR-free is not enough, that is arm splitting,
`LPAREN_STMT`, and `choose` branches, each gets a `test/corpus/` case whose
expected s-expression pins the **shape** (how many `match_arm` nodes, and
which tokens sit in which body). Those cases are how an arm split in the wrong
place goes red. I would not convert every `parse/` file into a corpus case;
the expected trees are large and churn on every grammar refactor. Pin shape
only where ambiguity exists.

### 6.3 Workflow wiring

A `tree-sitter` job in `ci.yml`: `ubuntu-24.04`, `timeout-minutes: 5`,
`actions/checkout`, install the pinned CLI (`npm i -g tree-sitter-cli@0.26.7`
or the release binary), `scripts/check-tree-sitter.sh --self-test && scripts/check-tree-sitter.sh`.
Add a row to `.github/workflows/README.md`.

### 6.4 Cost, measured on this Mac (load average 13-23 from other sessions)

- `tree-sitter generate`: 0.2 s committed grammar, 0.45 s prototype.
- `tree-sitter build`: 0.8-0.85 s.
- Parse all 849 files (3.76 MB): 0.55 s committed grammar, 0.3-0.4 s
  prototype. The prototype is faster because error recovery is the expensive
  path.
- `tree-sitter test`: under 1 s.

CI setup and CLI install will dominate. Budget 1-2 minutes of runner time per
run, on a single Linux leg.

---

## 7. Staged build plan

Each stage lands on its own, keeps the gate green, and shrinks
`known-failures.txt`.

- **Stage 0: the gate, with today's baseline.** `scripts/check-tree-sitter.sh`,
  the CI job, `known-failures.txt` (today 635 lines: the 631 accepted failures plus the
  4 menhir-rejected files outside `reject/`, which the ratchet corpus excludes), `keywords-allowlist.txt` (32), the
  two-line Zed query fix (D7), the stale comment at `grammar.js:509`, the
  `docs/tooling.md:1013` path, and a CLAUDE.md line for D6. Decide D3 (wasm)
  here. No grammar change, so no parse result changes.
- **Stage 1: context-free fixes, no conflicts.** Record `:`, parenthesised
  expressions, float operators, unit and paren types, nested `fn`, string
  escapes, lower-case sigils, `fn ->`, default args, `consume`, `spawn` args,
  unreserving soft keywords. Prototype evidence: about 280 files. Corpus cases
  for each construct.
- **Stage 2: declarations, patterns, actors, protocols.** `@[...]`, nested
  `mod`, `derive`/`satisfy`, `resource`, `transitions`, `app`,
  `always_linear`/`opaque`, extern forms, list/record/as/or/qualified patterns,
  actor `init(...)`/`mailbox`/`supervise`/`on_stop`, protocol steps. Adds the
  `init(` and `choose_branch` conflicts. Prototype evidence: about 140 files.
  Keyword allowlist drops toward 6.
- **Stage 3: newline-sensitive parts.** Block arm bodies with the
  `[block_body]` conflict, call-argument lambda bodies, `|` arm separators,
  and the `_stmt_lparen` scanner token with an error-recovery guard. Shape-pinning
  corpus cases (§6.2) land in the same PR. Prototype evidence: about 200 files.
  Also re-check `parser.c` size and parse time.
- **Stage 4: long tail and the hard gate.** Cond `match do`, comprehensions,
  `tag`, `doc` with attributes, attribute placement, `proof cap ... with`,
  interface default methods, and the 6 remaining keywords. Then make
  `specs/lang/grammar/parse/` a hard gate, and consider adding
  `specs/lang/{types,golden}` to the ratchet corpus.
- **Stage 5 (optional): repoint Zed.** Bump `zed-march/extension.toml`'s rev
  after Stage 3 and fix the machine-local `repository` URL (§10).

The per-stage file counts are from the prototype's order of application, so
they are indicative: applying the same fixes in stage order will attribute
files differently (a file needing both a Stage 1 and a Stage 3 construct only
turns clean in Stage 3).

The todo moves to `specs/progress/` when Stage 3 lands. That meets its
Acceptance ("drops materially ... zero regressions", corpus cases, wasm
handled). Stage 4 can be its own todo.

---

## 8. Verification plan: prove each check can go red

Each check gets a one-time demonstration in its PR description, and 6.1's
self-test repeats the grammar-provenance one on every CI run.

| Check | How to make it red |
|---|---|
| Grammar provenance | `--self-test` (§6.1 step 7). Also manually: build with the perturbation but parse with the old dylib, and confirm the self-test fails. |
| Failed-generate masking | Introduce a generate error (use a reserved word that is not a token, e.g. drop the only rule using `'pfn'`). The script must exit red at generate, not report the old counts. |
| Freshness | Edit `grammar.js` without regenerating; the script must report `parser.c` differs. |
| Corpus tests | Change one expected s-expression; `tree-sitter test -p` must fail. Also run once with `-l` to record that it wrongly passes, and why the script forbids it. |
| Queries | Already red today on `zed-march/.../highlights.scm:57`. Stage 0 shows it red, then green after the fix. |
| Ratchet, new failure | Add a fixture with an unsupported construct (for example a cond `match do`) outside the list: red. |
| Ratchet, stale entry | Add a clean-parsing file to `known-failures.txt`: red. |
| Ratchet, removed entry | Delete a still-failing line: red. |
| Keyword coverage | Add a keyword to `lexer.mll` in a scratch branch: red. Add an unused word to the allowlist: red. |
| Shape pins (Stage 3) | Temporarily drop the `[block_body]` conflict or the scanner token: the arm-split corpus cases must fail, not merely the ERROR count. |

---

## 9. Risks

- **GLR conflicts cost size and speed.** `parser.c` 2.5x larger. Parse time
  held (faster, in fact), but Zed parses on every keystroke. Re-measure in Stage
  3 on the largest stdlib files (`stdlib/session_node.march` is 2,281
  lines).
- **Wrong trees that are ERROR-free.** A mis-split arm highlights wrongly and
  no count sees it. Mitigated only by the shape pins (§6.2).
- **CLI version drift.** A different tree-sitter version regenerates a
  different `parser.c`, and possibly a different ABI. Pin the version in CI and
  in `specs/zed-extension-maintenance.md`. Whether Zed's bundled tree-sitter
  loads ABI 15 is unverified (the committed parser is already ABI 15, so this
  risk is not new).
- **Friction for language PRs.** D6 makes every syntax change touch
  `tree-sitter-march/`. The known-failures escape hatch keeps that to a
  one-line list edit plus a todo.
- **Scanner and error recovery.** External scanners are a common source of
  tree-sitter hangs and crashes during recovery. The production scanner must
  return false when every symbol is valid, and Stage 3 should fuzz it by
  running the ratchet over truncated files (cut each corpus file in half).

---

## 10. Open questions

1. Does anything outside this repo consume `tree-sitter-march.wasm` (D3)?
2. `zed-march/extension.toml` points at `file:///Users/80197052/code/march`.
   Is Zed support meant for anyone else? If so, the grammar needs a public URL.
   `specs/zed-extension-maintenance.md` also says the grammar is "its own git
   repo — required by Zed", but it is tracked inside this repo and addressed
   with `path =`, so that sentence looks stale. Not verified inside Zed.
3. Should the two `highlights.scm` copies become one file (a symlink or a CI
   identity check)? Their divergence is how §4.1 went unnoticed.
4. Cond `match do` needs a real design (§3), not a conflict declaration. I did
   not find one in the time spent here.
5. Should `specs/lang/{types,golden}` (462 files; 282 fail today, 17 with the
   prototype) join the ratchet corpus in Stage 0 or Stage 4?
