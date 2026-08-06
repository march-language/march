# Adding a runtime `.c` file requires editing 6+ hand-maintained lists

**Filed:** 2026-08-05
**Priority:** P2 — build-correctness footgun, currently caught only by luck

## What happened

Adding `runtime/march_ctx_escape.c` (referenced by `march_extras.c`) needed the
same file added, by hand, in every one of these:

| Location | What it feeds |
|---|---|
| `bin/main.ml` (~line 615) | the `--compile` link line |
| `bin/main.ml` (~line 3044) | the second, cache-aware link line |
| `test/dune` (81 occurrences of `march_extras.c`) | native golden-test rules |
| `demo/dune` (8 occurrences) | demo build rules |
| `test/test_helpers.ml` `extra_src_list` | the REPL/JIT runtime `.so` |
| `lib/cas/cas.ml` | the CAS digest over runtime sources |

Missing the JIT one produced 7 failures in `repl_compiler_parity` with a clear
`Undefined symbols: _march_ctx_escape`, so that one fails loudly. **The others
would not have.** A rule that lists `march_extras.c` but not its new dependency
either fails at link time with a less obvious message, or — worse for the CAS
list — silently produces a stale cache key.

## Why it matters

This is the same shape as the bug in
`specs/progress/2026-08-05-h-sigil-adt-misread.md`: information that must agree
in several places, with no mechanism forcing it to. The repo already solved this
problem once, well, for the capability lattice — `lib/caps/cap_lattice.ml` is a
single source of truth, `emit_c_table.ml` generates the C, and a freshness rule
in `test/dune` fails CI on drift.

## Sketch of a fix

One source of truth for "the runtime C sources", consumed by all six. Options,
roughly in increasing order of effort:

1. A `runtime/SOURCES` manifest read by `bin/main.ml` and generated into the
   dune rules by a small emitter, with a freshness check — mirrors the
   `cap_lattice` pattern the repo already trusts.
2. A dune `(glob_files ../runtime/*.c)` in the test/demo rules, removing the
   enumeration entirely there; `bin/main.ml` still needs its own list because it
   runs against an installed runtime dir, not the build tree.
3. At minimum: a test that greps the six lists and asserts they agree on the
   set of `runtime/*.c` files, so a missing entry fails as a readable assertion
   rather than as an undefined symbol.

Option 3 is cheap and would have caught this immediately; options 1–2 remove the
duplication rather than policing it.
