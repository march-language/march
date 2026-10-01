# Signal.watch 25x flake: the requested failure diagnostics already exist

Diagnostics-only item from `specs/todos/2026-09-17-flake-signal-watch-capturing-handler-25x.md`
("the test's assertion aborts without printing what failed"). Checked on origin/main: it does
print. `test_signal_watch_capturing_handler_repeated_delivery_compiled` (test/test_codegen.ml)
runs each iteration as `<bin> 2>&1; echo EXIT:$?`, retries once, and fails through
`Alcotest.failf` naming the iteration and both attempts' captured output, exit code included.
That came with #322 (2026-08-21); the todo was filed later and missed it. No code change was
made (the pass criteria are untouched, as asked); the todo now says so and tells the next
sighting where to look.
