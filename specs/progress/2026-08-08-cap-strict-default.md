# The capability ceiling is on by default

Landed 2026-08-08. `march --compile` now enforces every module's `needs` as a
hard ceiling over its emitted code; `--no-cap-strict` opts out;
`--cap-strict` is still accepted as an explicit spelling of the default.

## Why now

The ceiling is the only check that sees a stdlib-MEDIATED capability use
(`File.read` rather than `file_read`) — the severity flip (2026-08-06) made
the direct-builtin route an error, but the mediated route was enforced by
nothing unless the user passed `--cap-strict`. The docs said so honestly, and
saying it honestly made it obvious the default was the gap.

It could not be defaulted earlier because of its false-positive rate, which
took three fixes in sequence:

1. **Trampoline-lowered builtins were unattributable** (fixed with #221,
   `specs/progress/2026-08-07-cap-attrib-table-agreement.md`) — all of
   IO.Clock, IO.Signal, IO.Spawn.
2. **A module with no entry point was charged for the whole stdlib** — this
   change. See below; this was the actually dominant failure.
3. **A signature-only capability was an unfixable Unattributed violation** —
   this change; see
   `specs/progress/2026-08-08-ceiling-signature-only-fixed.md`. What forced
   it out of the todo pile: `fn main(cap : Cap(IO))` — the documented
   entry-point shape, pinned by `test/native/main_cap_io.march` — trips it,
   so the default would have rejected the sanctioned way to write `main`.
   The strict check's used-set is now the attributed (body-derived) set
   alone; `own_caps_of_this_module` still feeds `--cap-sandbox`, where the
   signature reading is the right one. The table-drift detection the union
   used to provide is `test_cap_attrib_agreement`'s job now.

## The full sweep changed the problem statement

The #221 estimate ("12 undeclared programs to migrate") came from `examples/`
+ `bench/` — 72 programs. Sweeping every compiled corpus (312 programs:
examples, bench, test/native, test/stdlib, test/whole_program) told a
different story: **110 failures, 86 of them in files with no `fn main`, 84
blaming a stdlib module** — a violation a user cannot fix, and which must not
be "fixed" by adding `needs` to the stdlib (that weakens attribution; see the
severity-flip progress doc).

Minimal repro: a file whose only declaration is `fn helper(x) = x + 1` drew
**17** ceiling violations.

## Root cause: DCE's fail-open roots

`Dce.root_names` has a deliberate fallback: a module with no `main`, no
setup/migrate, no exports and no tests has no roots, and rather than prune
everything, DCE keeps everything. Right for codegen — emptying a library
would be absurd. But the ceiling reads the **pruned** TIR to decide what the
program *uses*, so the fallback made the entire prepended stdlib look
reachable. Attribution then found no non-transparent caller for any of it —
correct, nothing called it — and fell back to naming the stdlib module,
exactly as `responsible_owners` documents, on input that should never have
reached it.

## The fix, and the two wrong versions before it

`Dce.prune_unreachable` gains two optional parameters, both defaulting to
today's behavior so codegen is untouched:

- `extra_root : string -> bool` — extra roots, **consulted only when the
  module has no natural roots**;
- `fail_open : bool` — whether an empty root set keeps everything (codegen)
  or means nothing is reachable (analysis).

The ceiling passes the functions **this file declares** as roots and
`fail_open:false`. Both refinements were forced by measurement:

- **Roots cannot be recovered from TIR names.** First attempt: root every
  unprefixed function, since `Lower` strips the entry module's prefix. But
  the PRELUDE's functions (`println`, `panic`, `debug`, …) are unprefixed
  too, so the same `fn helper` file was then charged IO.Console, IO.FileWrite
  and IO.NetConnect. The roots must come from the desugared AST, where a
  declaration's span still says which file it came from — the same
  stdlib-span filter `own_caps_of_this_module` uses, now shared as
  `user_fn_names_of`.
- **Extra roots must not apply when natural roots exist.** Applying them
  unconditionally resurrected user functions `main` never calls, and turned
  three previously-clean programs into ceiling violations. Caught only by
  diffing the full sweep against the pre-fix sweep, not by looking at the
  improvement.

`test/test_cap_ceiling.ml` pins four behaviors: a main-less capability-free
module is clean; a main-less module that really uses a capability is still
charged (without this, "prune harder" passes by checking nothing); a
test-only file reports nothing (`--compile` does not build test bodies —
their capability uses are checked when tests are built, where `tm_tests`
roots them); and `--cap-strict`/`--no-cap-strict` behave as spelling/opt-out.

## Migration

After the DCE fix, the genuine migration was 24 files, 28 `needs` lines,
every violation naming the file's own module: IO.NetListen and IO.NetConnect
(6 each), IO.Spawn (4), IO.FileWrite (3), and singles. Applied mechanically
from the ceiling's own output and verified per-file.

One casualty of honesty: `examples/read_file.march` now fails at LINK
(`_try_finally` undefined) — a pre-existing bug the ceiling error used to
mask, verified against the unmodified file with `--no-cap-strict`. Filed
separately; not a regression of this change.

## What the default does NOT change

- `--check` still exits 0 on the stdlib-mediated route: the ceiling needs
  TIR, and `--check` stops after typecheck. Still open in
  `specs/todos/2026-08-04-cap-ceiling-follow-ups.md`.
- `needs` is still a self-declaration; nothing *grants* capabilities (R1).
