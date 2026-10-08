# macOS CI: the --debug-info IR check samples the corpus

Logged 2026-10-07.

Main's CI on `0cdea7c35` failed: the macOS `test (all)` job hit its
75-minute limit. Every suite that finished passed; the codegen suite, which
runs last, never finished.

On the macOS runners the codegen suite went from 1,550-1,650 s (#814,
merge-train/a and /b) to 2,646 s (merge-train/c) and 2,794 s
(merge-train/d). The jump came with A2 (`tir/provenance-debug-info`). It added
a second pass of the native-corpus IR check, `native/*.march corpus emits
verifier-clean LLVM IR under --debug-info`, which compiles every fixture again
(348 now) and runs the LLVM verifier on each, one after another.
merge-train/d's job finished in 73 of its 75 minutes, so a slightly slower
runner on main's run timed out.

Fix (`test/test_ir_verify.ml`): on macOS, the `--debug-info` pass checks
every 8th fixture of the sorted corpus, the same ones each run. The Linux
runners still check the whole corpus, and the plain pass stays whole on both
platforms. `MARCH_IR_VERIFY_FULL=1` checks everything on macOS too.
