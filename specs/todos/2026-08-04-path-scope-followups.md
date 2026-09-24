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

- [ ] **`csv_open` takes an atom, not a path.** It is declared
  `IO.FileRead` but its first argument is `t_atom`, so it is absent from
  `path_arg_builtins` and no scope check applies. Worth confirming whether it
  resolves a path internally; if so it needs a scope check of its own shape.

- [x] **Relative scopes and scopes on non-filesystem capabilities are now
  rejected** (DONE 2026-09-21, see
  `specs/progress/2026-09-21-path-scope-declaration-checks.md`, which keeps the
  two original bullets).
