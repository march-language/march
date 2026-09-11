> **Landed 2026-09-11.** The todo's diagnosis was half right: `format.ml` had
> an 80-column budget (`should_break`) but list and record literals had no
> multi-line renderer, so the budget was never consulted for them. New
> `emit_stmt` arms break a too-wide list one element per line and a too-wide
> record one field per line, recursing so a too-wide record inside a broken
> list breaks one level deeper; a literal that fits stays inline byte for
> byte. Honest residual: a single over-wide atom (one long string, one `++`
> chain) still yields an over-width line — nothing splits atoms. Tests in
> `test_fmt.ml` ("wide literals"): the todo's list-of-records case (RED
> pre-fix: one line), the stays-inline REJECT witness, a nested record, a
> `let`-bound record, each asserting the output is a formatting fixpoint.
> The 34 existing round-trips stay green. Design:
> `specs/2026-09-11-correctness-fixes-design.md` §5. Original filing follows.

# The formatter collapses a multi-line literal onto one enormous line

`[P2]` - [ ] **`march fmt` turns a readable 654-line file into 10 lines, one of them 19,509
characters wide.** Pre-existing in `lib/format`, but newly reachable from every editor now
that `textDocument/formatting` is dispatched.

## Repro

```
cp ~/code/forgepm/lib/forgepm/migrations.march /tmp/probe.march
march fmt /tmp/probe.march
wc -l /tmp/probe.march          # 10
awk '{if(length($0)>m)m=length($0)} END{print m}' /tmp/probe.march   # 19509
```

The file is a single `fn all()` returning a list of records whose fields are long
`++`-concatenated SQL strings. The formatter joins the whole list literal onto one line.

Content is preserved — 32,484 chars in, 19,751 out, the difference being whitespace — so
this is a readability failure, not data loss. But "Format Document" on such a file
produces a diff touching every line and a result nobody can review.

## Why it matters more now than yesterday

`textDocument/formatting` was dead: it answered `TODO: handle this request`, so no editor
could trigger it (see
`specs/progress/2026-08-03-lsp-capabilities-repaired.md`). Repairing the dispatch made this
behaviour user-facing for the first time. The bug is older than the repair; its blast
radius is not.

Found by auditing per-document LSP responses against a real 603-file project, not by a unit
test — the formatter's own tests presumably use small inputs where collapsing is invisible
or even desirable.

## What to look at

`lib/format/` — the pretty-printer's line-breaking decision for list and record literals.
The likely shape is that it emits a group that only breaks when the *source* had a break,
or that it has no width budget at all. A width-aware printer (break a group when its
flattened width exceeds the target column) is the standard fix, and the target column
should be configurable rather than hardcoded.

Check what `FormattingOptions.tabSize` / `insertSpaces` the LSP passes through, too: they
are currently accepted and ignored.

## Acceptance

- A file whose flattened literal exceeds the target width formats onto multiple lines, with
  one element per line at a stable indent.
- REJECT witness: a SHORT literal that already fits must stay on one line. A fix that
  always breaks is as wrong as one that never does, and only a test asserting the
  stays-flat case distinguishes them.
- `march fmt` is idempotent on the result — format twice, get the same bytes. Worth
  asserting for the collapsed case specifically, since a printer that reflows differently
  on its own output will churn diffs forever.
- The forgepm corpus (603 files) formats without any line exceeding the target width.

## Note

Do not fix this by special-casing `++` chains. The same collapse will apply to any long
list, record or call-argument list; the missing piece is the width budget, not a rule about
string concatenation.

> **Design spec (2026-09-11):** `specs/2026-09-11-correctness-fixes-design.md` — root cause re-verified against the tree, chosen fix, test plan with a RED control, effort and risk.
