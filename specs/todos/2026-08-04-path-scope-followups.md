# Path-scoped capabilities — follow-ups

Design: `specs/2026-08-04-path-scoped-capabilities-design.md`.
Shipped 2026-08-04: scope algebra, grammar, declaration storage, the static
literal check, and scoped WRITE grants in the self-imposed sandbox.

## Enforcement status, as measured

| capability | static check | macOS `--cap-sandbox` | Linux `forge cap run` |
|---|---|---|---|
| `IO.FileWrite` scope | literal violations rejected | **enforced** (subpath allow) | not yet wired |
| `IO.FileRead` scope | literal violations rejected | **not enforceable** | not yet wired |

- [ ] **A scope containing a symlink silently matches nothing.** The kernel
  resolves symlinks before matching a subpath; scope normalization is lexical
  by design, because the build machine's filesystem is not the deployment
  machine's. `needs IO.FileWrite("/tmp/x")` on macOS therefore enforces
  against `/tmp/x` while the process writes to `/private/tmp/x` — every write
  is denied, including the intended ones. Found the hard way: the first
  end-to-end write test denied the IN-SCOPE path.

  This needs a diagnostic, not a doc note. Options: warn at compile time when
  a scope's leading component is a known symlink on the build host (cheap,
  but host-dependent and wrong for cross-compiles); or have the runtime
  `realpath` the scope before installing the profile (correct, resolves on
  the machine that matters, costs a syscall per scope at startup). The
  runtime option looks right — the scope is already a string in the profile,
  and resolving it there is the only place with the deployment filesystem.

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

- [ ] **Relative and non-absolute scopes are not rejected yet.** The design
  says a relative scope should be a compile error, since it would denote
  different directories depending on the working directory at run time.
  `Cap_scope.is_absolute` exists for this; the check is not wired.

- [ ] **A scope on a non-filesystem capability is not rejected yet.**
  `Cap_scope.is_scopable` exists and is tested, but nothing calls it, so
  `needs IO.Network("/etc")` currently parses and is silently ignored. An
  ignored scope reads as enforcement that is not there.
