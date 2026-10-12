`[P4]` `MARCH_SANITIZE=thread` builds of the process-spawn fixtures never finish

Found 2026-10-12 by the TSAN sweep (`test/native/*.march` with an `.expected`, built with
`MARCH_SANITIZE=thread` on macOS 26 / M3, Homebrew LLVM 22). Two fixtures time out at
1, 2 AND 14 schedulers. Plain builds pass them in the default suite. TSAN prints no
report.

| fixture | last line printed | stuck in |
|---|---|---|
| `live_process_registry` | `p1 exit: 0` | the "concurrent" phase (green threads calling `Process.spawn_async` + `read_line` + `wait_proc` at once) |
| `process_handle_leak_probe` | `run = 40, flat: true` | `process_spawn_lines` / `Process.run_stream` / `set_env` |

What was seen, without a debugger (ps/lsof only; never attach lldb/sample):

- `live_process_registry` at 1 scheduler was still running after 300 s and using
  about 90-190% CPU. That is a spin, not an idle-poll wedge (the 2026-10-11 wedge
  sat at about 1%).
- In one sample, a child with command name `echo` sat in state `S` at 0.8% CPU. In
  another sample there was no child at all.

## Candidates (none tested)

- **A TSAN artifact.** `runtime/march_runtime.c` spawns with `fork()` and then calls
  `close`/`dup2`/`execvp` in the child. Under TSAN those calls are intercepted, and
  forking a multi-threaded TSAN process can leave the child blocked on a TSAN-internal
  lock that another thread held at the fork. Then the parent's read never sees EOF.
  Switching to `posix_spawn` with file actions would remove the window in any build.
- **A real busy-wait** that is only slow enough to matter under TSAN's roughly 10x
  slowdown: the parent's read loop polling a nonblocking pipe.

Start by running the fixtures with `TSAN_OPTIONS=die_after_fork=0`. Also try one
`Process.spawn_async("echo", ...)` in a loop at 1 scheduler, to separate the fork
question from concurrency.
