# Twenty LSP capabilities are tested for *reachability*, not for *correctness*

`[P2]` - [ ] **The capability repair proved each feature answers; nothing proves any of
them answers correctly.** Twelve features ran for the first time on 2026-08-03. Their
outputs have still never been asserted at the protocol level, nor exercised against a real
editor. Per-feature tests are owed.

Stated as a caveat in `specs/progress/2026-08-03-lsp-capabilities-repaired.md`; filed here
so it is tracked rather than buried in a completed entry.

## Exactly what is and is not covered

`lsp/test/test_jsonrpc.ml` is the only suite that speaks the protocol to the real binary.
It has **7 test cases**, and exactly one of them covers the twenty repaired methods:

```
test_case "every advertised capability answers"
```

Its assertion is that no request returns a JSON-RPC error. That is the right test for the
bug it was written against — an advertised capability with no reachable handler — and it
must stay. It says nothing about content. A handler that answers `[]` to every request
passes it.

The remaining six cover `hover`, `executeCommand` dispatch, `exit`, `diagnostic`
(error and clean), and the no-project-root hang.

### The analysis-layer tests are not the missing coverage

`lsp/test/test_lsp.ml` has many per-feature tests — references 6, semantic tokens 9,
folding 8, inline values 5, and so on. They call `analyse src` and assert on the resulting
record. **That layer was never the broken part.** Dispatch was. Every one of those tests
was green throughout the entire period in which each of these features returned
`TODO: handle this request` to editors — which is precisely why `dune runtest` never
noticed. They are worth keeping and they do not close this gap.

### Features with no test at any layer

| Capability | analysis-layer tests | protocol-level correctness |
|---|---|---|
| `textDocument/formatting` | **0** | none |
| `textDocument/signatureHelp` | **0** | none |
| `workspace/symbol` | **0** | none |
| `textDocument/onTypeFormatting` | **0** | none |
| `textDocument/codeLens` | 1 | none |
| `textDocument/linkedEditingRange` | 1 | none |
| everything else repaired | 2–9 | none |

The first four are the exposed ones: nothing anywhere asserts what they return. Two of
them are already known to misbehave — `formatting` collapses a 654-line file onto a
19,509-character line (`specs/todos/2026-08-03-formatter-collapses-multiline-literals.md`),
found by hand against a real project, not by a test.

## Why this is worth real effort

The failure mode is not "a feature is missing". It is "a feature answers plausibly and
wrongly", which an editor renders as a subtly broken experience with no error anywhere.
Three bugs of the *reachability* shape landed in one week and none was caught by the test
suite; there is no reason to expect the *correctness* shape to be caught either.

The audit's own prediction, unchanged: **expect a second round of bugs behind the first.**

## Approach

Extend `lsp/test/test_jsonrpc.ml` rather than starting a new harness — it already spawns
the binary, frames Content-Length, and resolves the server exe relative to the test exe.

For each capability, one fixture with a *known* answer, asserted on the decoded response:

- `references` — a symbol used exactly twice returns exactly two locations, both in range.
- `rename` — the edit set covers every reference and nothing else; `prepareRename` refuses
  a keyword.
- `signatureHelp` — inside `f(|`, the active parameter index is 0; after a comma, 1.
- `workspace/symbol` — a query matching one declaration returns it, and a query matching
  nothing returns `[]` rather than everything.
- `formatting` — the returned edit, applied, equals `march fmt` on the same bytes. This
  one is the cheapest high-value test: it ties the LSP to a formatter the suite already
  covers, and it would have caught the line-collapse bug.
- `codeLens`, `inlineValue`, `linkedEditingRange`, `selectionRange`, `documentHighlight`,
  `typeDefinition`, `callHierarchy` — same shape: a fixture whose correct answer is a
  single obvious location or range.

**Every one must assert position, not just non-emptiness.** A response with the right
shape and wrong coordinates is the failure mode that reaches users, and a count-only
assertion cannot see it.

**Every one needs a REJECT case.** A request at a position where the correct answer is
"nothing" must return nothing. Without it, a handler that returns every symbol in the file
passes the positive test for every capability in the table above.

## Two traps this area has already sprung

1. **The prelude leak.** `semanticTokens` and `documentSymbol` both returned data
   describing the whole analysis — prelude included — rather than the open document. The
   symptom is a response far larger than the file, with line numbers past its end. Assert
   `max(endLine) < document line count` for every per-document response; that check is
   what found both.
2. **Testing a stale binary.** The suite resolves `../bin/main.exe` relative to the test
   executable, so building only the test binary runs the *previous* server and the new
   test passes against unfixed code. Build `lsp/bin/main.exe` explicitly before trusting a
   protocol-level result, and confirm any new test fails against the unfixed server before
   claiming it works.

## Acceptance

- Each capability in the table has at least one protocol-level test asserting concrete
  content, plus a REJECT case asserting emptiness where nothing is correct.
- Each new test is verified non-vacuous by mutation: break the handler, see that test and
  only that test fail.
- `every advertised capability answers` stays, unchanged. It guards a different property
  and the per-feature tests do not subsume it.
- The per-document leak assertion (`max endLine < document lines`) runs for every
  per-document response, not only the two that leaked.
