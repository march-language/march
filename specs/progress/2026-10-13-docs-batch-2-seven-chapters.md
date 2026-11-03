# Seven more chapters restructured for first readers (2026-10-13)

The same pass that the choreography, observe, capabilities, refinement-types, actors,
hot-code-reload, safety-by-construction, supervision and clustering chapters got earlier
the same day, applied in one batch to the seven pages a survey of the remaining docs
ranked highest. Section bodies are kept in all seven; each gets a plain opener, an **On
this page** index grouping every section, a when-to-use (or which-X-do-I-need) table, a
**How it fits with the rest of March** table, and `Next Steps` renamed `See also`.

| Chapter | Beyond the frame |
|---|---|
| `specs/lang/session-types.md` | The interpreted-vs-compiled status paragraph (golden ids, the 2026-07-24 MPST transcript, the typing/operational pointers) moved from the intro to an **Interpreted vs compiled** section before See also. Two phrase edits. |
| `specs/lang/linear-types.md` | The claim-ticket intro replaced; four "skip ahead / if you haven't read" asides tightened. Which-qualifier table covers `linear`, `affine`, `always_linear`, typestate, `LinearMap`, `RingBuf`, `resource`. |
| `specs/lang/memory-model.md` | Perceus and FBIP each in one paragraph; "so you don't need a compilers background", "This is the whole trick", "Two candid caveats" phrasing removed. |
| `specs/lang/interfaces.md` | "The bug they kill" framing replaced; "The bug `derive` kills" → "What `derive` prevents". |
| `specs/lang/pattern-matching.md` | The three "Note (resolved)" blockquotes, each warning about a parser limitation that no longer exists, and the blockquote pointing back at them, are removed; the only inline-code tokens not carried over are the operator names inside them. Which-construct table covers `match`, `match do`, `with`, `let?`, multi-head functions, `as`, or-patterns, `when`. |
| `specs/lang/parallelism.md` | "When to use them explicitly" moved up beside the new how-it-fits table; "the whole game", "Here's what is, and isn't, happening" phrasing removed. |
| `docs/tooling.md` (hand-maintained) | All 25 sections regrouped by task (everyday, finding things, safety tooling, dependencies and toolchains, changing and documenting code, deploying and operating, editors and debugging, reference), with a task-to-command table. |

Every inbound anchor other pages use is unchanged: session-types
(`#swapping-the-transport-session`, `#the-guarantees-in-one-place`), pattern-matching
(`#record-patterns`), tooling (`#ai-assistant-search--spec-search-claude-skill`,
`#cross-compiling-to-linux`, `#release-bundles-forge-release-build`). Every in-page and
cross-chapter anchor was checked by script; the generated `docs/` copies were regenerated;
`scripts/check-docs.sh` passes after each commit.
