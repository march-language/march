# R1 stage D — grant required (implementation)

Filed 2026-08-10. Design:
`specs/2026-08-10-r1-stage-d-grant-required-design.md`.

Closes R1's opt-in gap: a parameterless `main` whose transitive capability
closure is non-empty becomes a compile error. Hard flip, no flag.

Ships as one unit, because flipping the default WITHOUT multi-cap `main`
forces 30% of migrating programs to `Cap(IO)` and earns a worse claim than
today:

1. Multi-capability `main` — `check_main_signature` accepts N cap params;
   grant = union (stage C's existing rule); `check_main_grant` stops taking
   `g :: _`. `IO.Foreign` moves to stage C's rule (refused only when
   uncovered).
2. Codegen: the 0-arg entry adapter supplies N nulls, not 1. **SIGBUS
   precedent** — `test/native/main_cap_io.march`. Compiled-and-run tests at
   0/1/2/3 params are mandatory; typecheck-only tests pass while the binary
   crashes.
3. The flip itself: `| None -> ()` in `check_main_grant` becomes the error
   path when the closure is non-empty. No `unknown` refusal at `main` (design
   §D3 — it is a per-function concept; the program is closed).
4. Diagnostic names the exact grant (`caps(main)`) + JSON `fix` payload so
   `forge fix` applies it.
5. Migrate 283 in-repo files via the autofix; verify with
   `specs/lang/types/check_types.sh` and a real-binary compile of examples/,
   bench/, test/native/, test/stdlib/ — not green alcotest alone.

TDD per convention: RED tests in `test_compiler.ml` (`cap_grant_required`)
before any typecheck.ml change, plus `test_codegen.ml` for the adapter.
