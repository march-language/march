# Path-scoped capabilities — follow-ups

Design: `specs/2026-08-04-path-scoped-capabilities-design.md`.
Shipped 2026-08-04: scope algebra, grammar, declaration storage, the static
literal check, and scoped WRITE grants in the self-imposed sandbox.

## Enforcement status, as measured

| capability | static check | macOS `--cap-sandbox` | macOS `forge cap run` | Linux `forge cap run` |
|---|---|---|---|---|
| `IO.FileWrite` scope | literal violations rejected | **enforced** (subpath allow) | **enforced** (subpath allow), measured | wired (writable bind), args unit-tested, not run |
| `IO.FileRead` scope | literal violations rejected | **not enforceable** | **not enforceable** (reported advisory) | wired (allow-list + ro bind), args unit-tested, not run |

- [x] **A scope containing a symlink silently matched nothing** (DONE
  2026-09-24, see `specs/progress/2026-09-24-path-scope-realpath.md`). The
  runtime now `realpath`s each write scope in `march_sandbox_install` before
  `sandbox_init`: longest existing prefix, remainder re-appended.

- [x] **Wire scopes into `forge cap run` (external enforcement)** (DONE
  2026-10-11, see `specs/progress/2026-10-11-path-scope-forge-cap-run.md`).
  Owner decision 2026-10-11: the **embedded-manifest route**. The binary
  carries its DECLARED scopes in a `MARCHCAP\x01` manifest; `forge cap run`
  reads them and narrows the sandbox. Rationale: for ENFORCEMENT a declared
  scope is enough. The sandbox blocks everything outside it, so the claim
  never has to be proved from emitted code; a binary that under-states its
  scope only breaks itself, and a scope can only narrow a class the policy
  already grants (it applies under `--allow-only` too, never widening it).
  The soundness rule below (scope from emitted code, `DYNAMIC`) is for an
  AUDIT claim, not for enforcement, which is why that item stays open.

- [ ] **Run the Linux half of the `forge cap run` scope tests on Linux.** The
  bwrap argument construction is unit-tested (`forge/test/test_cap_sandbox.ml`:
  "bwrap write scope", "bwrap read scope", "scopes never widen"), and the
  end-to-end "forge cap run enforces a declared scope" test runs on bwrap
  when `bwrap --ro-bind / / true` works, but it was only ever run on macOS
  when this landed. Confirm it passes on a Linux box with usable bwrap
  (unprivileged user namespaces allowed), and add a read-scope end-to-end
  case there: a read outside an `IO.FileRead("/dir")` scope must fail.

- [ ] **bwrap: `IO.FileWrite` without `IO.FileRead` cannot write to the
  host at all.** Pre-existing, found 2026-10-11. `bwrap_args` puts a program
  that holds writes but not reads into the allow-list namespace, whose only
  writable place is a private `/tmp` tmpfs, so an UNSCOPED write grant
  writes nowhere persistent. (A scoped one now gets writable binds of its
  scopes, so it works.) Either bind the whole tree writable in that case or
  document that writing needs reading; the end-to-end test asserts the
  unscoped host effects on macOS only because of this.

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
