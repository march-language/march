# `[P1]` `Regex.find`/`replace`/`split` still backtrack and are still a DoS

- [ ] **Extend the linear matcher to report match positions, then route the
  `find` family through it.**

  `matches`/`matches_opts` are now linear
  (`specs/progress/2026-08-12-regex-linear-matcher.md`), but `find`,
  `find_all`, `replace`, `replace_all` and `split` still call the backtracking
  `find_match`, because they need a `(start, end)` span and the NFA
  simulation as built answers only the boolean question.

  So the measured denial of service — `a*a*a*a*b` against 80 bytes taking
  5.7s — **is still reachable through these entry points**, which are the ones
  an application is most likely to point at user input.

  The work: track, per active NFA state, the earliest input offset that
  reached it, so the accepting state carries a match start. Leftmost-longest
  is the semantics to match (what the backtracking engine produces today for
  these calls — verify rather than assume, since greedy backtracking and
  leftmost-longest differ on some patterns).

  Extend the differential test in `test/stdlib/test_regex.march` to compare
  `find` results, not just booleans, before switching anything over.
