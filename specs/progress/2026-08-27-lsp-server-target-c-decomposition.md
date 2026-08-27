# `lsp/lib/server.ml` decomposition — Target C, tasks C1–C3

**Date:** 2026-08-27
**Plan:** `specs/plans/2026-08-27-remaining-decomposition-targets.md`, Target C
**Branch:** `claude/lsp-server-target-c`

`lsp/lib/server.ml` **1,556 → 569** lines, in three commits:

| | Task | Kind | Result |
|---|---|---|---|
| C1 | extend `test_jsonrpc` to every dispatch branch | tests | +14 cases; 22 → 36 |
| C2 | `lsp/lib/server_state.ml` | code motion | 1,556 → 1,207; new file 376 |
| C3 | `lsp/lib/server_dispatch.ml` | code motion | 1,207 → **569**; new file 663 |

The plan predicted ≈1,200 after C2 and ≈560 after C3. Both landed within a
handful of lines of that.

## Why C1 came first, and what it actually cost

**No oracle covers `lsp/`.** `scripts/ir-oracle.sh` is structurally blind to it
(LSP code is never emitted as LLVM IR), and `types-oracle` / `refine-oracle`
drive the `march` binary, not `march-lsp`. Running any of them here and
reporting the green would be false assurance. The only real check is
`lsp/test/test_jsonrpc.ml`, which speaks LSP over stdio to a real `march-lsp`
process — and it reached 16 of the 22 dispatch methods.

C1 added a `dispatch branches` group covering the other eight:

```
textDocument/semanticTokens/full        (previously only reached by the
                                         reachability sweep, which asserts
                                         nothing about content)
textDocument/semanticTokens/full/delta
textDocument/prepareRename
callHierarchy/incomingCalls
callHierarchy/outgoingCalls
workspace/diagnostic
completionItem/resolve
textDocument/onTypeFormatting
```

`semanticTokens/full/delta` got the most attention, because it is the **only arm
in the chain with cross-request state**: it answers in delta form only when the
request's `previousResultId` matches what a prior `full` stashed in
`sem_tokens_cache`. An extraction that separates the chain from that cache — or
that reorders the two semanticTokens arms, `full` being a strict prefix of
`full/delta` in an `if` chain — degrades it to a full response, which every
client still renders correctly. So the case asserts the delta *shape* (one edit,
`deleteCount` 0, no `data` array), and a companion sends a baseline the server
never issued to pin the documented fallback in the other direction.

### Both halves were shown RED before landing

A test that passes against a broken branch is the LSP equivalent of the dead
oracle this project already shipped once, so each case was run against a
deliberately broken server:

- **Mutation A** — all eight guards renamed (`meth = "X-MUTANT"`) so the arms
  fall through to the chain's final `Lwt.fail_with`. **10 of the 14 cases went
  RED.** The four that stayed green are the reject cases: they assert
  *emptiness*, and cannot distinguish a missing branch from a correct "nothing".
- **Mutation B** — `prepareRename` made never to reject; call hierarchy made to
  answer about the *other* function (`item_name` flipped); `workspace/diagnostic`
  made to attribute every diagnostic to every file; `onTypeFormatting` made to
  close void elements. **Those four went RED**, as did
  `workspace/diagnostic`'s clean-file-reports-zero assertion.

Union of the two: every one of the 14 new cases is RED against a broken branch.

### Two protocol traps worth writing down

`workspace/diagnostic` requires `previousResultIds` and `onTypeFormatting`
requires `options`, and **omitting either fails the decode rather than reaching
the handler** — linol decodes these known requests before routing them to
`dispatch_by_method`. The first draft of both cases failed for that reason and
looked exactly like a broken handler:

```
cannot decode request: WorkspaceDiagnosticParams.t_of_yojson:
the following record elements were undefined: previousResultIds
```

## C2 — `server_state.ml`

`server.ml:8–362` moved verbatim: document cache, settings parsing, per-document
version table, project root / workspace index, code-action glue and
`semantic_tokens_data`. Declaration order is preserved exactly — the caches are
mutable globals and `versions = make_version_table ()` is an initialiser.

**`include`, not `open`.** The plan left this conditional on
`grep -rn 'Server\.' lsp/`; that grep is non-empty — `lsp/test/test_lsp.ml`
reaches `semantic_tokens_data`, `token_delta`, `param_name_hints_from_settings`
and `perf_annotations_from_settings` through `Server.`.

**One plan correction.** The plan expected the four module aliases (`Lsp`, `S`,
`Pos`, `Jsonrpc`) to be **duplicated** across both files. With `include` they
cannot be — a second copy in `server.ml` is a hard error:

```
Error: Multiple definition of the module name "Lsp".
```

They **move** instead and reach `server.ml` through the same `include`.
`Server`'s public surface is unchanged either way; they were already top-level
aliases exported from it. The duplication advice in the plan was written against
the `open` branch of its own conditional.

## C3 — `server_dispatch.ml`

The 643-line method body becomes
`Server_dispatch.dispatch ~notify_back ~meth ~params`. It used no `self` and no
`super` — a free function wearing a method's clothes.

**One plan deviation, in service of verbatim-ness.** The plan sketched the
collapsed method dropping `notify_back` with an `ignore`. Threading it through
instead is what keeps the body byte-identical: its first line is
`ignore _notify_back;`, and the parameter must exist for that line to move
unchanged. Behaviour is identical — nothing in the chain uses it.

### The branch-order assertion

**Order is semantics and nothing in this project's tooling sees it.** This is the
same class of hazard that elsewhere made a reordering refactor invisible to a
byte-exact oracle. Asserted directly:

```bash
git show HEAD:lsp/lib/server.ml | awk 'NR>=564 && NR<=1206' \
  | grep -o 'meth = "[^"]*"' > /tmp/before
grep -o 'meth = "[^"]*"' lsp/lib/server_dispatch.ml > /tmp/after
diff /tmp/before /tmp/after     # empty; 23 occurrences on both sides
```

`textDocument/semanticTokens/full` still precedes `.../full/delta`, and
`callHierarchy/incomingCalls` still precedes the arm handling
`incomingCalls || outgoingCalls` together.

## How verbatim-ness was checked

Not by eye. For each move, the relocated region is read back **out of the
destination file**, substituted at its call site in `server.ml`, and required to
reproduce the pre-move file **byte for byte** — the check that caught a
`.rstrip('\n')` silently eating a trailing blank line during the earlier
decomposition. Comment nesting is separately asserted to balance outside string
literals in both files.

```
C2: VERBATIM OK: band 355 lines, reassembly byte-identical to HEAD
C3: VERBATIM OK: 643 lines, reassembly byte-identical
```

## Verification

**No oracle is reported for any of this, because none exists for `lsp/`.**
What actually ran, per task, judged by exit code:

- the five LSP suites built and run **individually** from the repo root —
  `test_lsp` 354, `test_utf16` 5, `test_jsonrpc` 36, `test_incremental` 10,
  `test_query_cli` 7
- `scripts/run-tests.sh` — **11 suites, 3,175 tests, exit 0** (baseline before
  C1 was 3,161; the difference is exactly C1's 14 cases)
- `dune build --root . @check` — **17 errors**, byte-identical file set to the
  pre-refactor baseline (all pre-existing, under `forge/test/` and `js/`). This
  is the only check that sees `let open` and aliased consumers such as `An.` for
  `Analysis`, which `grep` cannot.

`lsp/lib/dune` has no explicit `(modules …)` list — its only `modules`-looking
line is a `march_modules` library dependency — so both new modules were
auto-discovered with no dune change.
