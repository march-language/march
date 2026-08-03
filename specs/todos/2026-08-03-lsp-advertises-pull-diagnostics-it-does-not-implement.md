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
