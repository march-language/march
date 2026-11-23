# forge audit compares grants entry by entry, as text

Logged 2026-11-23 by ocap phase 6, Task 7 (concern 1).

`Cmd_audit.diff_grants` compares a dependency's recorded grant with its current one as two
lists of strings. A widened or removed grant is an escalation (exit 1); a narrowed or newly
added grant is not. Because entries are compared as text, replacing `IO.Network` with the
narrower `IO.NetConnect("a.test")` is reported as a new entry, `its grant now ALSO allows:
IO.NetConnect("a.test")`, and fails the audit, although the dependency's authority shrank. The
same holds for reordered scope options or a path written with a trailing `/`. This errs toward
review, never toward silence.

What to do: parse both grants (`Dep_grants.parse_scope_text`) and compare them as scopes,
using the scope-containment test the compiler uses for `needs` (`Cap_scope.within`,
`Host_scope`, `Name_scope`): an entry is new only when no recorded entry contains it. Keep
the text form in `forge.caps.lock`.
