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
