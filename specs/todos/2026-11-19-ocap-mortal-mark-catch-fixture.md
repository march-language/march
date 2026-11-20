`[P1]` (high priority: memory safety)

# No test of a panic caught where the authority mark is a mortal cell (2026-11-19)

Found by the ocap phase 4 Task 10b review. Since Task 10b, native, JIT and JS
restore the authority at every panic-catch site (`march_cap_unwind` and the catch
sites in `runtime/march_runtime.c`). The restore releases the cells pushed since
the catch's mark. No test covers a catch whose mark is itself a MORTAL cell
(refcounted, not the immortal launch layer): a catch entered inside a scoped
function nested in another scoped function, with the panic raised one frame
deeper. That is the one path where a wrong count frees the mark the catch then
restores to: a use-after-free.

What to do: a three-deep fixture (scoped `f` calls scoped `g`, which enters a
`try_finally`/caught panic, and scoped `h` under it panics), run in every mode by
`test/cap_conformance` and under `scripts/triage.sh --deep` (ASAN) natively, plus
an `--rc-trace` run showing no live authority cell at exit.
