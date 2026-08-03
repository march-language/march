# march-lsp advertises pull diagnostics it does not implement

**Filed:** 2026-08-03 — found by running the server under Zed while verifying the
suggest-refinement code action.

## Symptom

Every diagnostic pull logs an error client-side:

```
ERROR [crates/project/src/lsp_store.rs] pulling diagnostics:
Get diagnostics via march-lsp failed:
LSP request handler failed with Failure("TODO: handle this request")
```

## Cause

`lsp/lib/server.ml` advertises the capability:

```ocaml
ServerCapabilities.diagnosticProvider =
  Some (`DiagnosticOptions
          (Lsp.Types.DiagnosticOptions.create
             ~interFileDependencies:true ~workspaceDiagnostics:true ()));
```

but nothing handles `textDocument/diagnostic`. linol dispatches it to
`on_request_unhandled`, whose default is `IO.failwith "TODO: handle this request"`.

Diagnostics still reach the editor, because the server also PUSHES them via
`textDocument/publishDiagnostics` on didOpen/didChange — which is why this has gone
unnoticed. The advertised pull capability is simply a claim the server cannot honour, and
a conforming client that prefers pull over push gets an error instead of diagnostics.

## Two ways to fix, in order of honesty

1. **Implement it.** The data already exists: `Analysis.t` carries `diagnostics`, and the
   push path already converts them. Override `on_request_unhandled` and answer
   `TextDocumentDiagnostic` with a `RelatedFullDocumentDiagnosticReport` built from the
   cached analysis for that URI. `workspaceDiagnostics:true` is a second, larger claim —
   either implement `workspace/diagnostic` too or drop that flag.
2. **Stop advertising it.** Three lines. Strictly better than today: clients fall back to
   the push diagnostics that actually work, instead of erroring. Do this if (1) is not
   happening soon — an advertised-but-broken capability is worse than an absent one.

## Acceptance

- A protocol-level test in `lsp/test/test_jsonrpc.ml` (which spawns the real binary)
  sends `textDocument/diagnostic` after a didOpen with a type error and asserts a report
  containing that diagnostic — or, under fix (2), asserts the capability is absent from
  the initialize result.
- Zed's log is clean of `pulling diagnostics` errors across an edit session.

## Note for whoever takes this

The same class of bug — a capability advertised and dispatched somewhere nothing listens —
just cost the whole `workspace/executeCommand` feature (see
`specs/progress/2026-08-03-lsp-execute-command-was-never-dispatched.md`). Both were
invisible to unit tests and to `dune runtest`, and both showed up in the first minute of
running under a real editor. Worth a pass over every capability this server advertises,
checking each against a handler that exists.

---

# Implementation spec (added 2026-08-03)

## Decision: implement it, don't drop the capability

Dropping `diagnosticProvider` is three lines and strictly better than today. But the data
is already sitting in `Analysis.t` and the push path already converts it, so implementing
is small enough that removing would throw away more than it saves. Drop it only if this
stalls.

## Where it plugs in — and where it must NOT

`Lsp.Client_request.TextDocumentDiagnostic` is a KNOWN request: payload
`DocumentDiagnosticParams.t`, response `DocumentDiagnosticReport.t`. linol has no dedicated
method for it, so it reaches `on_request_unhandled`, a GADT-typed method:

```ocaml
method on_request_unhandled : type r.
  notify_back:notify_back -> id:Req_id.t -> r Lsp.Client_request.t -> r IO.t
```

Override that in `lsp/lib/server.ml`, match `TextDocumentDiagnostic`, and delegate
everything else to `super`.

**Do not put it in `on_unknown_request`.** That method only sees requests linol could not
decode, and a known request never arrives there — which is precisely the mistake that made
every `workspace/executeCommand` dead code
(`specs/progress/2026-08-03-lsp-execute-command-was-never-dispatched.md`). Same repo, same
week, same shape.

## The response

Return a `RelatedFullDocumentDiagnosticReport` built from the cached analysis:

1. `params.textDocument.uri` → `get_analysis uri`.
2. On a cache miss, analyse on the spot via `analyse_and_cache` rather than answering
   empty — a client may pull before it opens, and an empty report is indistinguishable
   from a clean file.
3. Reuse the exact `Analysis.diagnostics` → `Lsp.Types.Diagnostic.t` conversion the publish
   path uses, factoring it into one function if it is currently inline. Two conversions
   would let pull and push disagree about the same buffer, and only one of them is visible
   in tests.
4. Skip `resultId` / `Unchanged` in v1. It needs a per-URI report-id cache and buys nothing
   until profiling asks for it.

## `workspaceDiagnostics: true` is a SECOND claim

The capability also advertises workspace diagnostics, and `workspace/diagnostic` is a
different request over all files, not just open ones. Either implement it — the raw
material is `Workspace.index_project` — or set the flag to `false` in the same change.
Advertising it while answering only the per-document request recreates this exact bug one
level down.

## Acceptance

- In `lsp/test/test_jsonrpc.ml` (the suite that spawns the real binary): after `didOpen` of
  a buffer with a type error, `textDocument/diagnostic` returns a report whose items
  contain that diagnostic. Model it on the existing `initialize/didOpen/hover` case.
- REJECT-shaped companion: the same request against a CLEAN buffer returns a `full` report
  with an EMPTY item list — not an error, and not the previous buffer's items. A bare
  "returns something" assertion passes against a handler that always answers empty.
- Non-vacuity: neuter the new arm to fall through to `super` and confirm the test fails.
  Rebuild `lsp/bin/main.exe` as well as the test binary, or the test runs the old server
  and "passes" — that mistake cost a cycle when guarding the executeCommand fix.
- Zed's log is clean of `pulling diagnostics` errors across an edit session.

## Then do the audit this is a symptom of

Two bugs of this shape — a capability advertised, dispatched where nothing listens — in one
session, both invisible to `dune runtest`, both surfacing within a minute under a real
editor. Walk every `ServerCapabilities.*` field the `config_*` methods set in
`lsp/lib/server.ml` and pair each with the handler that answers it. Anything advertised
with no handler gets implemented or unadvertised. The audit is cheaper than the next
discovery.
