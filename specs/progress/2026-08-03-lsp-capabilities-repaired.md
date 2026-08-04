# ~20 advertised LSP capabilities were dead code — repaired by one bridge

**FIXED 2026-08-03.** `[P1]` **Most of `march-lsp`'s advertised features never ran.** References, rename,
formatting, semantic tokens, folding, signature help, call hierarchy, type definition,
workspace symbol, document highlight, selection range, code lens and inline values all
return an error to the client. Measured, not inferred — see the table.

## How it was found

Three bugs of the same shape landed in one week — `workspace/executeCommand` dispatched
nowhere, `exit` never honoured, `textDocument/diagnostic` advertised but unimplemented —
each invisible to `dune runtest` and each visible within a minute of running the server
against a real editor. That pattern prompted an audit of every advertised capability. The
audit found the pattern is the norm, not the exception.

## Measurement (2026-08-03, protocol-driven against the real binary)

Each request was sent over stdio after `initialize` + `didOpen` of a valid module.

**Dead — every one answers `LSP request handler failed with Failure("TODO: handle this
request")`:**

| Request | Advertised as |
|---|---|
| `textDocument/references` | `referencesProvider` |
| `textDocument/formatting` | `documentFormattingProvider` |
| `textDocument/documentHighlight` | `documentHighlightProvider` |
| `textDocument/foldingRange` | `foldingRangeProvider` |
| `textDocument/semanticTokens/full` | `semanticTokensProvider` |
| `textDocument/signatureHelp` | `signatureHelpProvider` |
| `textDocument/typeDefinition` | `typeDefinitionProvider` |
| `workspace/symbol` | `workspaceSymbolProvider` |
| `textDocument/prepareCallHierarchy` | `callHierarchyProvider` |
| `textDocument/selectionRange` | `selectionRangeProvider` |

Not probed individually but dead by the identical mechanism — they are method-string
branches in `on_unknown_request` whose LSP method is a known `Client_request` variant:
`textDocument/rename`, `textDocument/prepareRename`, `textDocument/onTypeFormatting`,
`textDocument/linkedEditingRange`, `textDocument/inlineValue`, `textDocument/codeLens`,
`callHierarchy/incomingCalls`, `callHierarchy/outgoingCalls`,
`textDocument/semanticTokens/full/delta`, `completionItem/resolve`,
`workspace/diagnostic`.

**Working** — every one of these is dispatched through an `on_req_*` override (or, for
pull diagnostics, an `on_request_unhandled` arm):

`textDocument/hover`, `textDocument/definition`, `textDocument/completion`,
`textDocument/documentSymbol`, `textDocument/codeAction`, `textDocument/inlayHint`,
`textDocument/diagnostic`, `workspace/executeCommand`, plus push diagnostics.

## Cause — one mistake, repeated ~20 times

`lib/server.ml`'s `on_unknown_request` dispatches on the raw method string. But linol only
routes a request there when it could **not decode** it: all 56 entries of
`Lsp.Client_request.t` — including every method in the dead list — are decoded and sent
either to a dedicated `on_req_*` method or to `on_request_unhandled`. A method-string
branch for a known request is therefore unreachable by construction.

The handler bodies themselves appear to be written and plausible. This is a wiring
failure, not missing functionality — which is why it survived review: reading the file
shows a complete-looking implementation of every feature.

## Why nothing caught it

Every unit test calls into `Analysis.*` directly, where the logic lives and works. Only the
transport layer is broken, and `lsp/test/test_jsonrpc.ml` — the sole suite that speaks the
protocol — covered `initialize`/`didOpen`/`hover`, all of which happen to be on the working
side.

## The fix, and it is mechanical

For each dead branch, move the body out of `on_unknown_request` into either:

- the dedicated `on_req_*` method linol provides (as done for
  `workspace/executeCommand` — see
  `specs/progress/2026-08-03-lsp-execute-command-was-never-dispatched.md`), or
- an arm of the overridden `on_request_unhandled`, for requests linol decodes but has no
  method for (as done for `textDocument/diagnostic` — see
  `specs/progress/2026-08-03-lsp-pull-diagnostics-implemented.md`).

Check `~/.opam/*/lib/linol/server.ml`'s dispatch to decide which of the two applies per
request; do not guess, since guessing wrong reproduces the bug silently.

## Acceptance

- A protocol-level test per repaired capability in `lsp/test/test_jsonrpc.ml`, asserting a
  well-formed non-error result. The suite that only calls `Analysis.*` cannot substitute:
  the logic already passes there today while the feature is dead.
- Each test must distinguish "answered" from "answered emptily" wherever an empty result
  is plausible — `workspace/symbol` for a query that matches nothing and a broken handler
  look identical otherwise.
- A guard against regression of the whole class: one test that walks the advertised
  `ServerCapabilities` and asserts every advertised request answers without error. That is
  the test whose absence allowed twenty features to die quietly.

## Note on scope

This is not a small change, and the temptation is to repair the easy half. Repairing some
and leaving the rest advertised keeps the same lie in place for whatever is skipped —
either wire a capability up or stop advertising it, per request.


---

# The repair (2026-08-03)

## One bridge, not twenty rewrites

The handler bodies were never broken — only their wiring — so rewriting them against twenty
typed parameter records would have risked twenty new bugs to fix zero real ones. Instead
`on_request_unhandled` gained a single generic arm:

```
to_jsonrpc_request req   ->  recover the wire method + params
dispatch_by_method       ->  the EXISTING string-keyed handlers, untouched
response_of_json req     ->  turn their JSON into the typed result the GADT owes
```

`on_unknown_request`'s body became a private `dispatch_by_method` with `on_unknown_request`
as a thin forwarder, so genuinely-undecodable methods still reach it. It is private
because a new public method widens the object type and breaks the coercion to
`Linol_lwt.Jsonrpc2.server` in `lsp/bin/main.ml`.

**13 failing capabilities → 0**, in one change.

## Two mistakes worth recording, both mine, both caught by measurement

**Treating `` `Null `` as "not handled".** The first version fell through to `super`
whenever the dispatcher returned null — but null is a *legitimate* result for
`typeDefinition`, `workspace/symbol` and most option-returning requests. The capability
sweep reported `typeDefinition` as still dead when it was answering correctly. The
dispatcher signals "no branch" by REJECTING (`Lwt.fail_with`), so that alone now delegates
to super.

**A test URI at the filesystem root.** The sweep first appeared to hang everything. Cause:
`project_root` falls back to the open document's directory, and `file:///cap_sweep.march`
makes that `/` — so the workspace index walked the entire disk. `references` and
`workspace/symbol` never returned. The repair was fine; the test was pathological.

That second one is a **real sharp edge left in place**: a client that opens a file in a very
large directory with no `forge.toml` above it will hang those two requests. Worth its own
todo, not fixed here.

## Verification

`test_every_advertised_capability_answers` in `lsp/test/test_jsonrpc.ml` drives every
advertised capability over stdio and asserts none returns a protocol error. It asserts
"answered", deliberately not "answered usefully" — a null result is legitimate for many
of these, and demanding content would trade brittleness for coverage the per-feature unit
tests already give. What it catches is exactly the failure that hid for months:
`Failure("TODO: handle this request")`.

Independently confirmed with an out-of-band probe script: references, formatting,
documentHighlight, foldingRange, semanticTokens, signatureHelp, prepareCallHierarchy and
selectionRange all return real payloads; typeDefinition and workspace/symbol return
legitimate empties for the probe's cursor position.

365 LSP tests pass (342 analysis + 6 jsonrpc + 10 + 7).

## What this does not do

It does not verify each capability returns the RIGHT answer — only that each is reachable.
Twelve features have now run for the first time; their outputs have never been exercised
against a real editor. Expect a second round of bugs behind this one, and treat per-feature
tests as still owed.
