# `linkedEditingRange` was "find all occurrences", so typing rewrote other lines

Reported as "typing on one line overwrites other lines", with buffers ending
up corrupted like this:

```
match _t do                                        -- `_` inserted
{ left: Somea), right: Someb) } -> has_vala, ...   -- `(` eaten
{ left: Some(_a), right: None } -> ...             -- `_` inserted
```

## Root cause

`Analysis.linked_editing_ranges_at` (`lsp/lib/analysis.ml`) handled `~H` sigil
open/close tag pairs first — correct — and then **fell through to returning the
symbol's definition plus every use**.

`textDocument/linkedEditingRange` is not a query. The client applies every
keystroke to *all* returned ranges simultaneously, with no prompt and no
confirmation, so it is only safe for ranges that are identical by
construction (a tag pair). Returning a symbol's uses turned ordinary typing
into an implicit rename of every occurrence, and any range slightly out of
date landed mid-token and consumed neighbouring characters.

Confirmed by driving the real server over stdio — cursor on the `a` in
`{ left: Some(a), ... } -> ... has_val(a, target)`:

```
2 ranges returned:
  line 7 col 17-18  'a'    <- Some(a)
  line 7 col 52-53  'a'    <- has_val(a, target)
```

## Fix

`linked_editing_ranges_at` now returns the tag-pair result or `[]`, nothing
else. Symbol renaming is `textDocument/rename`'s job — explicit, user-invoked,
and already supported here with a prepare step (`renameProvider` with
`prepareProvider = true`), so no capability is lost.

## The test asserted the bug

`lsp/test/test_lsp_refactor.ml`'s `test_linked_editing_ranges` asserted
`"links the binding and both uses of x" = 3`, and the registration in
`test_lsp.ml` was named "linked editing links all occurrences". Both now
assert and describe the opposite, with the reason inline, so the behaviour
cannot quietly return. The tag-pair test (`test_tag_pair_linked_edit`) is
unchanged and still passes — the legitimate case is untouched.

## How it was found (worth repeating)

Two earlier hypotheses — a stale `completionItem/resolve` auto-import edit,
then stale code-action ranges — were both **wrong**, and one of them produced
a fix that did not address this. What settled it was capturing the real
session's traffic through a logging proxy: the server sent **zero** `newText`
in the entire window, which ruled out every server-sent-edit theory at once
and pointed at a client-applied mechanism instead. The advertised
`linkedEditingRangeProvider: true` in the captured `initialize` response was
then the obvious suspect.

Lesson: for "the editor changed text I didn't type", capture the traffic
before theorising. A proxy over the LSP stdio pipe takes a few minutes and is
decisive; guessing from the corruption pattern was not.

## Evidence

- Probe against the running server: cursor on a variable now returns no
  ranges (was 2).
- `scripts/run-tests.sh lsp` — 354/354, including "linked editing does not
  link plain identifiers" and the retained "linked editing links ~H open+close
  tag pair".
