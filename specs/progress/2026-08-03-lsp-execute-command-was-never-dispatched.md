# `workspace/executeCommand` was never dispatched — every LSP command was dead code

**Found & fixed:** 2026-08-03, while verifying the `forge refine` code action under Zed.

## What was broken

Every `workspace/executeCommand` returned `null`. Not just the new
`march.suggestRefinement` — the runnable code lenses shipped earlier
(`march.runTest`, `march.debugTest`, `march.run`, `march.debug`) had **never worked**
either. Clicking "Run test" in an editor did nothing and reported nothing.

## Cause

The handler lived in `on_unknown_request`, matching on
`meth = "workspace/executeCommand"`. But linol dispatches that method as a **known**
client request (`Lsp.Client_request.ExecuteCommand`) straight to
`on_req_execute_command`, which `march-lsp` never overrode. linol's default
implementation is:

```ocaml
method on_req_execute_command ~notify_back:_ ~id:_ ~workDoneToken:_ _c _args =
  IO.return `Null
```

So the entire branch was unreachable and the client always got `null`.

## Why nothing caught it

A command is only observable through a live protocol session. The unit tests exercise
`Analysis.code_actions_at` directly — which correctly returned the action all along —
and `dune runtest` never speaks the protocol end to end. The feature looked complete
from every angle except the one that matters.

It was found within a minute of driving the real binary over stdio: `codeAction` returned
the action, `executeCommand` returned `{"result": null}`, and no `workspace/applyEdit`
ever arrived.

## The fix

Moved the logic to `method! on_req_execute_command`, which is what linol actually calls.
`march.suggestRefinement` now sends the edit back through `workspace/applyEdit`, so it
lands in the user's BUFFER — writing the file underneath an editor with unsaved changes
would lose their work.

Verified over a real stdio session:

```
3. codeAction returned 4 action(s); found march.suggestRefinement
   title: Suggest a refinement type for `batches`
   carries an eager edit? no (correct)
4. server sent workspace/applyEdit  label='Suggest a refinement type'
   edit demo.march [1:35-1:39] -> ' {Int | _ > 0}'
   line before: fn batches(xs : List(Int), size : Int) : List(List(Int)) do
   line after : fn batches(xs : List(Int), size : {Int | _ > 0}) : List(List(Int)) do
```

and the previously-dead lens commands now return their structured payloads instead of
`null`.

## The regression guard, and why it is shaped that way

`lsp/test/test_jsonrpc.ml` — the one suite that spawns the real binary and speaks the
protocol — now sends a **deliberately unknown** command id and asserts the structured
`kind: "unknown"` payload comes back. That needs no project on disk, no solver and no
shell-out, yet it can only be produced by a handler that is genuinely being dispatched to.
A `null` there means the wiring has broken again.

Confirmed non-vacuous by mutation: neutering the handler to `return \`Null` makes it fail
(exit 1). The first attempt at that mutation check was itself wrong — it rebuilt only the
test binary and not `lsp/bin/main.exe`, so the test ran against a stale, correct server and
"passed". Rebuild both, and judge by an exit code that is not measured through a pipe.

## Related

`specs/todos/2026-08-03-lsp-advertises-pull-diagnostics-it-does-not-implement.md` — the
same class of defect (a capability advertised, dispatched somewhere nothing listens),
found in the same Zed session. Worth auditing every advertised capability against a
handler that exists.
