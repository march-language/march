# `[P2]` `Parse`: the grammar is rebuilt during the parse, not once

- [ ] **Make `delay` build its parser once instead of on every entry.**

  `delay(thunk)` calls `thunk()` each time it is *run*, so every recursive
  descent re-executes the rule constructor. For a grammar written the natural
  way — `alt(number(), alt(string(), alt(..., delay(fn -> value()))))` — each
  nested value re-allocates the whole alternative chain and every closure
  under it: **O(depth × grammar size) allocations per document**, on top of
  one `ParseReply` per combinator step.

  Measured, not suspected: the combinator JSON parser ran **16.5× slower**
  than hand-written recursive descent on an 18KB document
  (`specs/progress/2026-08-12-json-combinator-ab.md`), with token scanning
  held constant so the gap is purely structural. This is the leading suspect
  for most of that factor, which means 16.5× is an **upper bound**, not a
  settled number.

  The fix is memoization — build the `Parser` on first use, reuse it after —
  which needs somewhere to put the cached value. March has no bare mutable
  ref in the stdlib surface; options worth costing:

  - a `Vault`-backed once-cell keyed per call site (heavyweight, needs a key);
  - a runtime builtin for a single-assignment cell;
  - restructuring so recursive rules are built once at module level and
    referenced, which may be possible without any new mechanism and should be
    tried first because it costs nothing.

  Re-run the A/B in the progress note after fixing; the benchmark and corpus
  are reproducible from commit `159ea9e8`.
