# A discarded `Ok(())` leaks its cell (2026-11-13)

Found in ocap phase 2b Task 15 (pre-existing: the same on the merge-base). Under
`--rc-trace` + `scripts/gc-trace-report.py`, and under LSan, most native fixtures report one
or two live 24-byte `Ok(())` cells at exit: the `Result` that `println` returns when it is
discarded inside a match arm, and a block-final `let _ = e` in `main`. They are small, but
they make both leak tools red on almost every fixture, which hides real leaks.

Fix in Perceus (a dead discarded value in those two positions should get its dec), then add
a snapshot and a leak-probe fixture that asserts `gc-trace-report.py` exits 0.
