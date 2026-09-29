# `process_spawn_lines` leaks its intermediate result and returns a String typed as a Seq

Logged 2026-09-29 while fixing
specs/progress/2026-09-29-process-spawn-async-leaks-live-process.md.

`march_process_spawn_lines` (runtime/march_runtime.c) calls
`march_process_spawn_sync`, which returns a fresh `Ok(ProcessResult(code,
stdout, stderr))`, then returns `mk_ok(stdout)` without releasing the outer
Result, the ProcessResult cell or the stderr String (three objects per call),
and without taking its own reference on the aliased stdout String.

Separately, the typechecker gives `process_spawn_lines` (`Process.run_stream`)
the type `Result(Seq(a), String)`, but the compiled payload is the raw stdout
String ("caller can split lines"). Decide the intended type and make both
backends agree before fixing the ownership, and add a leg for it to
test/native/process_handle_leak_probe.march.
