# march_doc fixed for the strict main-capability-grant rule; nightly smoke guard added

**Date:** 2026-08-12

## Problem

The stdlib API doc generator (`scripts/gen-stdlib-docs.sh`) drives the external
`march_doc` tool (github.com/march-language/march_doc), which is compiled by
*this* repo's compiler. The strict capability-grant rule ("`main`'s capability
parameter is now the program's grant", CHANGELOG Unreleased) broke march_doc's
`fn main()` — it performs IO (`IO.Console`, `IO.FileRead`, `IO.FileWrite`,
`IO.Process`) but declared no grant, so `forge doc` failed with
`march_doc.doc exited with code 1`.

Nothing caught this: `.github/workflows/gen-stdlib-docs.yml` only triggers on
`stdlib/**` pushes, so a compiler-rule change breaks the tool silently and the
failure surfaces weeks later on an unrelated stdlib change.

## Fix

1. **march_doc repo** (`forge/doc.march`): gave `main` the compiler-suggested
   grant — `fn main(_cap_console : Cap(IO.Console), _cap_fileread :
   Cap(IO.FileRead), _cap_filewrite : Cap(IO.FileWrite), _cap_process :
   Cap(IO.Process))` — plus the four matching `needs IO.*` module
   declarations (the second error round; the grant rule and the module
   `needs`-coverage check are separate obligations).
2. **This repo**: added a `stdlib-docs-smoke` job to
   `.github/workflows/nightly.yml` that runs `scripts/gen-stdlib-docs.sh`
   daily (compiling and running march_doc against the current compiler) and
   then asserts `git diff --exit-code docs/docs/stdlib` so a stale committed
   reference is also caught within a day.

## Verification

`scripts/gen-stdlib-docs.sh` runs end-to-end: "generated 115 module pages in
docs/docs/stdlib/", and the regenerated output is byte-identical to the
committed pages (empty `git status docs/docs/stdlib`).

Note: the nightly guard clones march_doc from GitHub, so it stays red until
the march_doc fix is pushed to `march-language/march_doc` main.
