# `gc-trace-report.py` counts an immortal cell as live (2026-11-13)

Found in ocap phase 2b Task 15. When the runtime incs a cell to `MARCH_RC_IMMORTAL` or above
before any `immortal` event for it is traced, `scripts/gc-trace-report.py` reports it as live
at exit. Treat a recorded rc >= `MARCH_RC_IMMORTAL` as immortal in the report.
