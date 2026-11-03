# Shell: fragments call the node's own functions instead of carrying copies

Logged 2026-10-07 (observe plan R5.5's "every other callee is resolved
against the node", which R5.4 made safe).

A shell fragment carried a copy of every function it ran. A Depot query's
fragment was 338 KB of LLVM IR, about 175 ms of clang per input, and the
connect fragment was 542 KB. The node already has most of that code, but
only safely callable when both sides agree on how it is called. That
agreement is checked, not assumed (`lib/jit/shell_ident.ml`, "calling the
node's own functions").

## What the node publishes

A `--hot-reload` build adds `x <fn> <signature> <modes>` rows to its
`__march_shell_ident` table (served by `IDENT`), one per function it emitted
with external linkage (`node_fns`):
- the LLVM signature, parsed from its own `define` line (`ret(param,...)`);
- each parameter's mode, `b` borrowed or `o` owned, as its Perceus placed
  RC against it (`Clo_flags`).

Left out:
- hot-reload slots: a deploy can replace one, and a direct call would
  bypass the dispatch table;
- entry points and trampolines;
- every name that is not stable across builds (`stable_name`), see below.

## What the client does per input

After mono/defun/prune, and after the R5.4 identity check over everything
the input reaches, a fragment function is linked (`linkable`) when all of
these hold:
- the node has the same name, and the name is stable;
- no parameter or return type contains a closure or a type variable
  (version 1: a fragment's lambda has its own apply code, and erased slots
  carry per-call Float-box ownership).

It then rebuilds without the linked bodies:
- prunes what only they reached;
- runs borrow inference and overrides the linked functions' rows with the
  node's modes, so Perceus places RC at the fragment's calls the way the
  node's code expects;
- emits them as `declare`s, which `dlopen` binds to the node's exported
  symbols (`-export_dynamic` / `--export-dynamic` on `--hot-reload` builds).

The fragment's `declare` signatures are compared with the node's. Any
mismatch (a type the node unboxes and the fragment does not, say) is
dropped from the linked set and the fragment rebuilt, until none differ.
`Escape` keeps its empty borrow map, so it never stack-promotes a value
across one of these calls.

**Caps.** Linked code is not emitted in the fragment, so its caps cannot
come from the emitted C symbols. The client adds `Cap_attrib.cap_of_call`
over every name referenced in the whole self-contained reach set. Linking
can therefore only add caps to the manifest, never drop one. The Depot
session's audited caps are unchanged (`IO.NetConnect,IO.Random` for
connect, `IO.NetConnect` per query).

## Two traps found on the way

- **Counter-named functions.** The node published `go$apply$1349`. Lifted
  lambdas, their apply functions and join points are numbered per build, so
  a client fragment's own `go$apply$0` is an unrelated function sharing a
  node name. `stable_name` rules out any `$`-segment that is a number or a
  generated kind (`apply`, `lam12`, `jp3`, `t5`, …), on both sides. It also
  rules out default-arg arity wrappers (`greet$1`), which only costs a copy.
- **A small program's stdlib is inlined away.** In the test node,
  `List.range`, `reverse` and `length` never survive as symbols. Json's
  parser and printer do, and so do Depot's functions.

## Measured (macOS node, load average ~43)

| | self-contained | linked |
|---|---|---|
| Depot connect fragment | 542 KB IR, ~230 ms clang | 46 KB, ~130 ms |
| Depot query fragment | 338 KB IR, ~175 ms clang | 81 KB, ~105 ms |

Clang medians come from three interleaved runs. A linked query fragment
defines 3 functions; most of its 81 KB is the runtime's `declare` preamble,
so what remains is clang's fixed cost. End to end, a query went from
~510 ms to ~390-450 ms. The macOS `dlopen` of each new file (~150 ms) is
still in that; Linux does not pay it.

## Tests

`test/dune` `native_shell_link.out`: `test/native/shell_node.march`'s
`main` parses and prints Json, so its build carries Json's functions. The
inputs of `test/shell/link.txt` reach them, with
`MARCH_SHELL_LINK_REPORT=1` naming what each input calls on the node:
- `Json.parse(s)` calls 18 node functions, `Json.to_string(j)` calls 3,
  each twice on a session binding;
- `List.map` with a lambda links nothing;
- `Result.map(Json.parse("[1, 2]"), fn v -> … Json.to_string(v) …
  Json.to_string(v))` passes a value local to the fragment twice to
  `Json.to_string`, which owns its argument on the node.

The output is identical with `MARCH_SHELL_NO_LINK=1`.

**The last input is the one that checks the modes.** A session binding
(`s`, `j`) is incremented by the emitter when loaded from its slot, so
calls passing one come out the same whatever the callee's modes. Forcing
every linked parameter to "borrowed" left the first six inputs green, while
the last one:
- on macOS, dropped the increment before the first call and added a
  release after the second, and the node crashed;
- on Linux under ASAN (`MARCH_SANITIZE=1 MARCH_DEBUG_RUNTIME=1` node,
  `march-amdr-repro`), reported `heap-use-after-free` in `march_decrc_freed`.

With the real modes, three sessions of the whole file ran clean under ASAN
on Linux, Json calls linked there too (`--export-dynamic`).

## Not done

- **Functions with a closure or type-variable parameter** are never linked
  (`List.map` and friends stay copies).
- **The node only has what its own program reaches,** at the types it uses;
  everything else is still a copy.
- **Clang's fixed cost** (~70-90 ms: process start and link) now dominates a
  linked fragment. Emitting the object in-process would remove most of it.
