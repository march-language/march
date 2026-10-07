# Shell: the program is lowered once per session

Logged 2026-10-06 (observe plan R5, fragment latency).

Each shell input used to be lowered together with the whole program,
through the full `Lower.lower_module` path. That was needed for
`import`-using libraries like Depot, but it lowered the whole program and
specialised all of it again for every input, even `1 + 1`. Measured against
a Depot-backed node on macOS (ms per input):

| phase | before | after |
|---|---|---|
| lower | 200-270 | 0.1 |
| trmc | 33-35 | (once) |
| mono | 110-170 | 1-3 |
| defun | 32-42 | <1 |
| prune before mono | - | 3-7 |
| clang | 70-190 | 85-200 |

## How

- `Lower.lower_module ~resumable:true` keeps what its declaration pass
  resolves names against: the env, interface impls, use and module aliases,
  default-arg dispatch, lowered modules, the entry's fn scope, top-level
  lets, and the fresh-name counter. `Lower.lower_more decls` lowers more
  top-level `fn`s against that state, as if they were declared at the end of
  the module. Fresh names continue past the module's, so a new `$lamN` never
  collides with a cached one. If a call fails, the modules it lowered lazily
  are unmarked, so a later call can still lower them.
- `Repl_jit.shell_lower_program` lowers and TRMCs the program once per
  session. `march --shell` calls it at session start, next to the program
  typecheck, so no input pays the 270 ms. `shell_compile` adds each input's
  spans to the cached type map, lowers it with `lower_more`, and appends it
  to the cached TIR.
- A prune runs before mono. It is rooted at the input's `main` plus every
  interface impl, because an interface method call names no impl until mono
  picks one. Mono then specialises only what the input can reach. The
  existing prune after defun still runs.

`--compile`'s program declares every stdlib and `MARCH_LIB_PATH` module, so
lazy module lowering does not fire in the shell; library fns lowered by an
input would join the cache if it did.

## Where the time goes now

End to end, against a macOS node: about 315 ms per small input and about
440 ms per Depot query. The client side is about 110 ms for a small input,
nearly all clang (about 45 ms of compile, the rest the link). The rest is the
node: the macOS `dlopen` of each new file costs about 150 ms, while Linux
pays about 0.02 ms. A Depot query's fragment is about 0.5 MB of IR, because
it carries its own copy of the Depot code it reaches.

Tried and rejected:
- lld instead of ld64 on macOS gave no gain.
- `-O0` would cut a Depot fragment's clang time from about 185 ms to
  110 ms. Fragments stay at `-O1` because March leaves mutual tail calls to
  LLVM, and library code in a fragment may loop that way.

Next: call the node's own copies of functions it already has, so a fragment
stops carrying them. This shrinks the Depot fragment, and with it the
clang and `dlopen` time. It is gated on the R5.4 identity check (client and
node built from the same program).

## Tests

`test/shell/session.txt` drives 19 inputs through the cached path. Its new
inputs `Math.abs(-2.5)` and `Math.sqrt(Math.abs(-16.0))` reach a module the
program never calls. The test still passes with the "library fns join the
cache" step disabled, because that step never fires under `--compile`.
