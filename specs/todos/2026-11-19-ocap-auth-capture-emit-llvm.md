# `src_auth_capture` cannot be emitted with plain `--emit-llvm` (2026-11-19)

Found by the ocap phase 4 Task 10 review. The `auth_capture` snapshot program
draws `cap_result_unhandled` under plain `--emit-llvm`, so `scripts/ir-oracle.sh`
skips it and its IR is not pinned by the oracle.

What to do: fix the program (wrap the unhandled result) so it emits, and add it
back to the IR oracle corpus.
