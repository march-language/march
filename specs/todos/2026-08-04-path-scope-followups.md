# Path-scoped capabilities — follow-ups

Design: `specs/2026-08-04-path-scoped-capabilities-design.md`.
Shipped 2026-08-04: scope algebra, grammar, declaration storage, the static
literal check, and scoped WRITE grants in the self-imposed sandbox.

## Enforcement status, as measured

| capability | static check | macOS `--cap-sandbox` | Linux `forge cap run` |
|---|---|---|---|
| `IO.FileWrite` scope | literal violations rejected | **enforced** (subpath allow) | not yet wired |
| `IO.FileRead` scope | literal violations rejected | **not enforceable** | not yet wired |

- [x] **A scope containing a symlink silently matched nothing** (DONE
  2026-09-24, see `specs/progress/2026-09-24-path-scope-realpath.md`). The
  runtime now `realpath`s each write scope in `march_sandbox_install` before
  `sandbox_init`: longest existing prefix, remainder re-appended.

- [ ] **Wire scopes into `forge cap run` (external enforcement).** Today the
  external sandbox takes an unscoped `string list` from `Cap_binary.read`,
  so it cannot scope anything. Two routes: read scopes from an embedded
  manifest, or emit scoped markers (design §7). Linux gains the most — its
  mount-namespace allow-list scopes READS, which macOS structurally cannot.

- [ ] **Scoped markers with `DYNAMIC` (design §7).** Not built. The load-
  bearing rule if it is: the scope must come from EMITTED CODE, never from
  the declaration, and every uncertainty resolves to `DYNAMIC`. A scope
  copied out of `needs` is a claim; a binary can still reach any path through
  a computed argument. Measured groundwork: path-bearing symbol names and
  pinned data globals both survive `-dead_strip`, and TIR distinguishes
  `ALit` from `AVar` at the call site.

- [x] **`csv_open` was missing from `path_arg_builtins`** (DONE 2026-09-28).
  This bullet originally said `csv_open` "takes an atom, not a path". That
  was wrong. Its signature is `csv_open(path : String, delimiter : String,
  mode : Atom)` (`typecheck_builtins.ml`), and the atom is the mode. It is
  declared `IO.FileRead`, so argument 0 needs the same literal-path scope
  check as `file_read`. Before the fix, `csv_open("/etc/passwd", ",",
  :simple)` under `needs IO.FileRead("/srv/data")` compiled clean. Now it is
  rejected ("... outside it"), and a path inside the scope is still accepted:
  `test_csv_open_outside_scope_is_rejected` /
  `test_csv_open_inside_scope_is_accepted` in `test/test_cap_scope.ml`.
  `csv_next_row` / `csv_close` take the handle `csv_open` returns, so they
  need no check of their own, the same argument as `file_read_line`.

- [x] **Relative scopes and scopes on non-filesystem capabilities are now
  rejected** (DONE 2026-09-21, see
  `specs/progress/2026-09-21-path-scope-declaration-checks.md`, which keeps the
  two original bullets).
