# Shell, client side: `march --shell`

**Date:** 2026-10-06
**Plan:** [`plans/2026-09-28-observe-recon-shell-plan.md`](../plans/2026-09-28-observe-recon-shell-plan.md),
R5.5 (fragment emission), R6 items 1, 6, 8 (the `march` half), 10; design §6.3, §6.9.
**Builds on:** [`2026-10-06-shell-node-listener.md`](2026-10-06-shell-node-listener.md).

## What exists now

```
march --shell <reload socket>.shell [--shell-timeout-ms N] [--shell-inputs FILE] app.march
```

The driver typechecks the program exactly as `--compile` would: same
stdlib, `MARCH_LIB_PATH`, imports and shadowing. Then, instead of compiling,
it hands `desugared`, the type map and the typecheck env to `bin/shell_cmd.ml`.
That opens the node's shell socket, says `HELLO` (getting the epoch and a slot
range), and runs a read–eval–print loop. Each input:

- **Is wrapped as generated March source and parsed normally.** The source is
  `mod Shell_N do needs … fn main() do <cap lets> let __r = (<input>)
  <render> end end`.
- **Is compiled into a self-contained fragment**
  (`Repl_jit.shell_compile`, new):
  1. typecheck against the program's env;
  2. lower with the program's declarations and the program's type map merged
     with the input's, so every stdlib or app function the input reaches is
     lowered with its real types;
  3. nothing is "already compiled", so all of them go into the fragment;
  4. `emit_repl_expr`, then clang `-O1` to a `.so` that exports only its entry
     (`-exported_symbol` on macOS, a version script and `-Bsymbolic` on Linux).

  The fragment's internal symbols cannot be interposed by the node's, nor
  interpose them. Runtime symbols stay undefined and bind to the node at
  `dlopen`.
- **Is signed and sent** as one `EVAL` with the `.so` inline. The reply's
  captured output is printed, then the result.

Session state:

- **Program types.** Once per session (`Repl_jit.shell_prepare`), the
  program's type definitions become the prefix of every fragment's type list.
  Actor message constructors get their hashed tags only from their actor's
  message type, which fragment lowering never produces. Without this, a
  `send(c, Bump(41))` built tag 0 and the actor dropped it. Takes ~0.5 s at
  attach.
- **`let x = e`** compiles an init fragment (`kind:init`, new on the node)
  that stores `e` in the next slot of the session's range. A second
  typecheck gives `x`'s type for the session env, printed as `x : T`.
- **The fragment's function is `main`.** Monomorphisation keeps `main` as a
  root even when its type is polymorphic (`let c = Actor.pid_from_int(..)`
  : `Pid(a)`). The program's own `main` is left out of the declarations
  fragments lower against.
- **Pre-bound caps.** `console`, `clock`, `intro`, `debug` become typed
  `let`s in the fragment, only those the input mentions. The node checks the
  matching cap paths against `$MARCH_SHELL_POLICY`. `root_cap` in an input is
  refused. (`dbg` is a keyword, hence `debug`.)
- **Rendering and `limit: N`.** The fragment first tries a list renderer:
  at most N elements, then `… n more`. If that does not typecheck, it uses
  `to_string`. Default 50. A trailing `limit: N` / `limit: all` sets it for
  one input, `:limit N` for the session.
- **Commands:** `:t <expr>`, `:caps`, `:limit N`, `:help`, `:quit`.
- **Ending the session.** `ERR epoch_changed` or a `BYE` ends it with a
  message, exit 2.

## Measured (macOS, this dev box)

Per input: typecheck under 1 ms, lower 2-57 ms, emit 2-12 ms, clang
110-330 ms. clang dominates because a fragment carries everything it
reaches. Plus the node's ~150 ms first-`dlopen` of each new file on macOS
(R5.1). Linux's clang and `dlopen` are several times faster (R5.1).

## Tests

- **`test/native/shell_session.expected`** (dune rule
  `native_shell_session.out`): `march --shell` runs `test/shell/session.txt`
  against `test/native/shell_node.march`, built `--hot-reload
  --signing-pubkey` with a key generated into a private HOME. It covers:
  - arithmetic;
  - list limits (default, `limit: 5`, `limit: 3`);
  - `let` and reuse;
  - captured `println`, with the node's own stdout checked never to see it;
  - the program's actor through `Actor.list`, `pid_from_int`, `send` and
    `inspect_state` (`{ n: 42 }`);
  - two panics, a type error, and the session continuing after each.
- **Red control:** without `shell_prepare`'s program types, the `send` is
  dropped and the state stays `{ n: 1 }`.
- **`test/native/shell_node.expected`** (the C-fragment checker) still
  passes with `kind:init`.

## Not yet

- **`forge shell` / `forge rpc`:** host lookup, the ssh tunnel to
  `<reload>.shell`, and running `march --shell` against the project.
- **Element-limit rendering below the top level and quoted strings (R5.7).**
  Today only a top-level list is cut; everything else is `to_string`.
- **Identity check (R5.4) and pinned NAME_IDs (R5.3).** A fragment calls its
  own copies of app functions, compiled from the client's checkout. A node
  whose code differs from the checkout is not detected yet, and after a hot
  deploy the session ends anyway.
- **Cap manifest (R5.6).** Caps are computed from the pre-bound names an
  input mentions; a call that reaches a cap through app code is not
  declared.
- **Spawning a program-defined actor from the shell.** Fragment lowering
  does not lower actors, so `spawn(Counter)` fails to compile. Sending to and
  inspecting existing actors works.
- **Latency:** clang per fragment; caching emitted support functions per
  session is the obvious lever.

## forge shell / forge rpc

`forge/lib/cmd_shell.ml` with `forge shell [--socket P | --env E]
[--timeout-ms N]` and `forge rpc ... 'expr'`. It finds the entry and
`MARCH_LIB_PATH` as `forge build` does (`Project.entry`,
`Cmd_build.lib_path_env`), opens an ssh tunnel to `<reload socket>.shell` for
a remote host, and runs `march --shell` (with `--shell-inputs` for rpc).
`march --shell` exits 1 when any scripted input failed, so `forge rpc` does
too. Checked by hand against a live node: `forge rpc --socket S '1 + 41'`
prints `42` and exits 0; `'Actor.list(intro)'` prints `[Pid(0)]`; `'panic("x")'`
prints `** panic: x` and exits 1. Several matching hosts are refused with a
pointer to `--env` (no fan-out yet, R11). Documented in `docs/observe.md`.

## A scheduler bug the shell found: green threads spawned off-scheduler ran with every signal blocked

On Linux, the node died with a bare `Segmentation fault` on the third input
of the session test (`List.range(1, 100)` rendered at the default limit). No
`march: fatal` line appeared, even with `MARCH_DEBUG_RUNTIME=1`. gdb showed
33 nested 96-byte `go$apply` frames hitting the guard page of a 4 KiB
initial green-thread stack: the ordinary lazy-growth fault. The handler
never ran because SIGSEGV was blocked.

`getcontext()` stores the calling thread's signal mask in the new
context, and every swap into it restores that mask. The shell task is
spawned from the listener's session thread, which blocks all signals. So
the task ran with SIGSEGV blocked, and its first stack-growth fault killed
the process. macOS uses 16 KiB pages, so the initial stack was 16 KiB there
and never had to grow in the test.

The fix (`runtime/march_scheduler.c`): the first `sched_loop` records the
schedulers' own signal mask. `sched_spawn_common`, when called from a
non-scheduler thread, gives the new context that mask, and never blocks
SIGSEGV, SIGBUS, SIGILL or SIGFPE in it. It applies to every off-scheduler
spawner, including the reload server's hard-drain procs. Red: the Linux
session test crashes without it. Green: the whole session passes on Linux
and macOS.

## Fragments are compiled for the node's platform

Testing `forge shell` over ssh exposed that the client compiled fragments for
its own platform. A Linux node cannot `dlopen` a Mach-O, so a shell from a
Mac to a Linux server could not have worked. The node's `HELLO` now reports
its target (`triple:<llvm triple>`, from the `MARCH_HCR_TRIPLE` the driver
already passes to `--hot-reload` builds). `Repl_jit.shell_compile ?triple`
compiles for it with `--target=`. From macOS to Linux it links with lld and
`-nostdlib`: a fragment needs no libc or sysroot, since every runtime symbol
binds at the node's `dlopen`. The export rules (Mach-O
`-exported_symbol` or ELF version script) follow the target, not the host.
A macOS node cannot be targeted from Linux, and the shell says so.

Verified 2026-10-06 against a Docker container (`march-amdr-repro`, Linux
aarch64) running sshd and the node, from this Mac, through forge's own ssh
tunnel (`FORGE_SSH_CONFIG`, `[hot-reload] ssh_host`):
- `forge rpc '1 + 41'` printed `42` and exited 0, and `forge rpc
  'Actor.list(intro)'` printed `[Pid(0)]`;
- an interactive `forge shell` (under a pty) bound `c`, sent `Bump(99)`, read
  `{ n: 100 }` back with `inspect_state`, and printed `hello over ssh` on the
  Mac, which never appeared in the node's stdout;
- `limit: 4` cut a 999-element list;
- all 7 inputs were audited `ok` on the node.

Cross-architecture (an arm64 Mac to an x86-64 node) is untested: the
fragment IR is emitted for the host and only re-targeted by clang.

## Library code, and a Depot query over the shell

Fragments used to be lowered through the REPL's lazy per-module path, which
re-reads stdlib files from disk and ignores `import`. A library on
`MARCH_LIB_PATH` therefore did not lower: Depot's `Connection.connect` was
unknown, and so was the bare `encode(..)` its `import Encode` brings in.
`Repl_jit.shell_compile` now lowers each input together with the program's
declarations through the full `Lower.lower_module` path that the native
build uses, which covers imports, aliases, actors and externs. Mono then
runs, and `Dce.prune_unreachable` keeps only what the fragment's `main`
reaches before the RC passes run. This replaced `shell_prepare`. The cost is
about 470 ms of lowering and optimisation per input for a Depot-sized
program.

The combined module is named after the program's entry module, and an
input's self-qualified `DepotNode.pg()` is stripped to `pg` the way the
entry's own desugar does it (`Desugar.strip_entry_self_qual
~members_of:program_decls`). Typechecking accepted both spellings, but the
lowered fragment called a `DepotNode.pg` that did not exist.
`test/shell/session.txt` covers this with `Main.evens(9)` and `evens(4)`,
where `evens` is a program fn whose body uses an imported bare `filter`.

Verified 2026-10-06 on macOS against Postgres 17 in Docker. The node was a
`--hot-reload` build of an app that depends on Depot. The session ran:
- `let conn = Connection.connect(DepotNode.pg())`, then `let c =
  Result.unwrap(conn)`;
- `simple_query` SELECTs, which returned rows: `[["Alice","30"],
  ["Bob","25"], ["Carol","41"]]`, and a count of `2`;
- an INSERT (`INSERT 0 1`), after which a SELECT returned the new row;
- a bad column, which came back as `Err(column "nope" does not exist)`.

The connection stayed open in a session slot across inputs. On a second
session, the duplicate INSERT came back as Postgres's unique-constraint
`Err`.

Gap: every input was audited with `caps:"-"`. The fragments reach
`IO.NetConnect` through Depot, but the client only declares the caps the
input names itself, so the node's `$MARCH_SHELL_POLICY` never saw the
network access. See `specs/todos/2026-10-06-shell-cap-manifest-library-caps.md`.
