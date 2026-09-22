# DONE 2026-09-21: relative scopes and scopes on non-filesystem capabilities are rejected

Two of the bullets in `specs/todos/2026-08-04-path-scope-followups.md` (the
symlink, `forge cap run`, scoped-marker and `csv_open` bullets stay open there).

## What changed

`lib/typecheck/typecheck.ml`, the `Ast.DNeeds` arm: every declared scope is
checked where it is recorded, with an error reported at the capability name:

- `Cap_scope.is_scopable cap` false -> "`IO.Network` does not take a path
  scope; only filesystem capabilities do (...), so `("/etc")` would be ignored",
  with a hint to scope the filesystem capability meant.
- `Cap_scope.is_absolute path` false -> "The scope `etc/myapp` on `IO.FileRead`
  is a relative path, so it would name a different directory depending on the
  working directory at run time".

Errors, not warnings, per the design (§5 and the §11 test table: "relative
scope -> error", "scope on `IO.Network` -> error").

**One judgement call:** bare `IO` is not scopable (`is_scopable` covers only
`IO.FileRead`/`IO.FileWrite`/`IO.FileSystem`), so `needs IO("/srv")` is now
rejected. Before this change that declaration did narrow the filesystem
literal check through subsumption, while leaving everything else `IO` grants
(network, process, ...) unscoped, which is easy to misread. The hint points at
`needs IO.FileSystem("/srv")`. No in-tree code declared a scope on anything but
the three filesystem capabilities (grepped `.march`, `.ml`, `.md`).

The language reference (`specs/lang/capabilities.md`) and the site copy
(`docs/capability-enforcement.md`) had no description of scoped `needs` at all;
both gained a short "Path scopes" paragraph covering the syntax, the literal
check, `--cap-sandbox` narrowing and the two new errors.

## Verification

`test/test_cap_scope.ml`, through the real compiler (`--check`), asserting on
the message rather than just the exit code:

- relative scope (`"etc/myapp"`, `"./out"`) -> rejected for being relative
- scope on `IO.Network` and on `IO` -> rejected as not scopable
- control: the same fixture with `IO.FileRead("/etc/myapp")` and
  `IO.FileSystem("/srv")` is accepted, so the failures belong to the scope

Red control (the new check block disabled): the two reject cases FAIL, the
accept control stays OK. With the check: all 18 cap_scope cases pass.

---

## Original bullets (filed 2026-08-04)

- [ ] **Relative and non-absolute scopes are not rejected yet.** The design
  says a relative scope should be a compile error, since it would denote
  different directories depending on the working directory at run time.
  `Cap_scope.is_absolute` exists for this; the check is not wired.

- [ ] **A scope on a non-filesystem capability is not rejected yet.**
  `Cap_scope.is_scopable` exists and is tested, but nothing calls it, so
  `needs IO.Network("/etc")` currently parses and is silently ignored. An
  ignored scope reads as enforcement that is not there.
