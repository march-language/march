# LSP publishing the same diagnostics twice, and a friendlier Option/Result field-access error

## Duplicate diagnostics: TIR-pass no-op still re-published

`Analysis.run_tir_pass` (`lsp/lib/analysis.ml`) deliberately skips the TIR
pipeline and returns its input `Analysis.t` **unchanged** when the source
already has an error-severity diagnostic — the TIR pipeline can't run on
broken input. But both call sites of it — `on_notif_doc_did_open` and
`on_notif_doc_did_change` in `lsp/lib/server.ml` — published
`a2.Analysis.diagnostics` unconditionally after that call, without checking
whether `run_tir_pass` had actually produced anything new. When it no-oped,
`a2` is physically the same record as `a`, so this republished the exact
diagnostics list already sent moments earlier in the same handler. Reported
by a user seeing the same "cannot access field" message shown stacked twice
in Zed's hover tooltip.

**Fix:** both call sites now check `a2 != a` (physical inequality — cheap,
and exactly matches whether `run_tir_pass` did real work) before publishing
the second time.

This is a distinct bug from [[2026-09-01-lsp-completion-resolve-staleness-and-tvar-name-growth]]'s
tvar-name-growth fix — that fix explained why duplicate messages could show
DIFFERENT-looking (but equally unhelpful) internal variable names; this fix
is why the message appeared twice in the first place. Confirmed together: a
user retesting after the tvar-name fix alone still saw the duplication, now
with a small, stable name (`i2`/`j2`) on both copies — which is what led to
finding this second, independent bug.

## Notes were invisible in the editor hover (found by user retest)

The first cut of the unwrap hint below shipped as a `notes` entry, and
`diag_to_lsp` joined notes onto the message after a `"\n"`. Zed's hover
popover renders only the **first line** of a diagnostic message, so the hint
appeared only in the project-diagnostics panel — a separate view that is
rarely open. The user retested and reported the hint still missing; their
hover screenshot showed the headline and nothing else, which is what exposed
this.

`diag_to_lsp` (`lsp/lib/analysis.ml`) now flattens the message and each note
onto a single line, including newlines *inside* a note (which would truncate
at the same place). The CLI renderer reads `d.notes` directly and keeps its
own indented layout, so this is a client-presentation change only.

Worth remembering as a general rule: **a diagnostic's `notes` are invisible
in hover-first editors unless they are on the message's first line.** Any
future guidance added via `notes` inherits this.

## Friendlier `Option`/`Result` field-access error

`typecheck.ml`'s `EField` handling reported "I cannot access field `%s`
because this expression has type `%s`, which is not a record" for a bare
type name, with no more context — including for the single most common way
to hit this: forgetting to unwrap an `Option`/`Result` before reading a
field on its payload. Added a `notes` hint (via `Err.report`, replacing the
plain `Err.error` call) that fires specifically for `TCon ("Option", [_])`
and `TCon ("Result", [_; _])`.

A first cut used `<expr>` placeholders and printed `pp_ty other` verbatim.
The user's verdict on that — "as an error this isn't very good, I want to
see how to actually fix the issue" — was right, and drove three changes:

- **Name the subject.** When the receiver is `Ast.EVar v` (by far the common
  shape, `l.value`), the message says `` `l` `` instead of "this
  expression", and every snippet substitutes the real name. The suggestion
  is copy-pasteable rather than a template to re-instantiate by hand.
- **Don't print inference internals.** An unresolved payload rendered as
  `Option(l2)` — a fresh-variable display name that is meaningless to the
  reader and changes between runs (the same names that show up as `m2`,
  `i2`, `u52`…). A local renderer prints `_` for an unbound payload, giving
  `Option(_)`, keeping attention on the wrapper, which is the real problem.
- **Say why.** "`l` may be `None`, so there is not always a value to read
  `value` from" explains the cause; the old text only restated that the type
  was not a record.

Note the type genuinely *is* unresolved here rather than being `Option(Tree)`:
this file's `has_val` takes an unannotated record pattern, which goes through
the closed-synthesis path described in
[[2026-09-01-self-referential-record-inference-hang-and-message]]. `Option(_)`
is the honest rendering, not a hedge.

## Evidence

- `./_build/default/bin/main.exe` on `l.value` where `l : Option(Tr)` — now
  prints the unwrap hint alongside the existing message; confirmed for both
  `Option` and `Result`.
- `scripts/run-tests.sh lsp` — 354/354.
- `scripts/run-tests.sh -q` (full suite) — all suites pass.
