`[P3]` `String.split(s, "")` splits into bytes and breaks UTF-8 (2026-10-14)

Found when String's examples became checked doctests. The doc said an empty
separator "returns whole string" (`String.split("hello", "")` gives `["hello"]`);
every backend (native REPL, interpreter, compiled, browser REPL) actually returns one
string per **byte**:

    String.split("héllo", "")  ==  ["h", "\195", "\169", "l", "l", "o"]

so a multi-byte UTF-8 character is cut into invalid one-byte strings. The doc now
describes the real behaviour and points to `String.to_codepoints`
(stdlib/string.march, `split`).

Decide: keep byte splitting (documented hazard), split into codepoints or graphemes
(probably what a reader expects), or return `[s]` as the old doc claimed. Any change
is user-visible: CHANGELOG `### Changed`, and update the `split` doctest.
