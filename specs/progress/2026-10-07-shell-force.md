# Shell `--force`: read-only inputs over code that differs from the node's build (R5.4)

Logged 2026-10-07 (observe plan R5.4's `--force`; follows
[shell build identity](2026-10-07-shell-build-identity.md)).

The shell refuses an input whose fragment reaches a declaration that
differs from the node's build. That is right by default, and it blocks the
common case of an operator one commit ahead of production who only wants to
look. `--force` lets such an input run when it cannot change anything.

## What changed

- **Flags.** `march --shell … --shell-force`, `forge shell --force`,
  `forge rpc --force` (`forge/lib/cmd_shell.ml` builds the `march` command
  line in `march_args`).
- **Compile (`Repl_jit.shell_compile ?force`).** `Shell_ident.skew_parts`
  splits a fragment's skew three ways:
  - differing code (`sk_decls`): functions, top-level lets, impls, module
    headers;
  - differing type, actor or protocol definitions (`sk_types`);
  - constructor-tag differences (`sk_tags`).

  How each is handled:
  - Types and tags are refused as before, forced or not. Forced, the
    message adds "(--shell-force never overrides a differing type or
    constructor numbering)". A changed definition is a value layout the
    node's data has. A read-only input can still read a node value (a
    Vault entry), and would decode it with this checkout's layout. Tags
    alone were the plan's hard stop; a payload type changed under the same
    tags is the same hazard, so types are included.
  - Code only, forced: the fragment is built **with nothing linked to the
    node**. It runs this checkout's copy of everything it reaches, so a
    differing function is never swapped for the node's version. Every C
    symbol its code calls is then in the emitted IR.
  - After emission, `Shell_ident.not_read_only ~caps ~syms ~fns` must be
    empty, or the input is refused before clang. The message names the
    differing declarations and why the input is not read-only.
  - The fragment's `sf_skew` lists the differing declarations.
- **Client (`bin/shell_cmd.ml`).** A fragment with `sf_skew` prints a
  warning on stderr naming the declarations. The session is then marked
  skewed, and the interactive prompt reads `march [skew]> `. The EVAL is
  signed with `skew:1`. The session-start summary says differing inputs
  are refused "unless read-only (--shell-force)".
- **Node (`runtime/march_shell.c`).** EVAL accepts an optional signed
  `skew:0|1` field; any other value is `bad_args`. `skew:1` adds
  `"skew":1` to the audit line, and nothing else changes. The protocol
  comment documents it. Without `--force`, or for an input that reaches no
  differing code, the client sends no `skew` field, so a node built before
  this change still accepts every request a non-forced session makes.

## The read-only rule, and why

An input is read-only when all of these hold:

1. **Capabilities: an allowlist.** Every cap in its manifest is one of
   `IO.Console` (output is captured into the reply), `IO.Clock`,
   `IO.Random` or `IO.FileRead`. Anything else disqualifies it:
   `IO.FileWrite`, `IO.Net*`, `IO.Process`, `IO.Spawn`, `IO.Mut` (Vault
   writes), `IO.Signal`, `IO.Foreign`, an FFI cap, and any cap added later.
   An allowlist fails closed when caps are added; a denylist would not.
2. **No mutation without a capability: a denylist of runtime symbols**
   (`Shell_ident.is_mutating_sym`, over the `march_*` symbols the emitted
   code calls). A symbol is denied when it contains a word that names a
   mutation: `send`, `spawn`, `kill`, `stop`, `register`, `monitor`,
   `reply`, `revoke`, `reload`, `_set`, `close`, `cancel`, `drop`, `free`,
   `write`, `delete`, `remove`, `rename`, `update`, `incr`, `push`, `reap`,
   `exit` or `drain`. It is also denied when it starts with `march_logger_`,
   or is one of an exact list whose names do not say so: `march_actor_call`,
   `march_try_call*`, `march_remote_invoke_march`, `march_actor_inspect*`,
   `march_run_until_idle`, `march_io_read_*` (the node's stdin),
   `march_delivery_failed_watch`, `march_http_fetch`, and
   `march_epoch_hold`/`release`. Words rather than only a list, so that a
   runtime entry point added later with a telling name is caught without an
   edit. The cost of a false positive is only a refused forced input.
   - The task asked whether a `send`, which needs no capability, should
     disqualify. It does: a message makes another actor run the node's code
     on data this checkout built.
   - The check reads the C symbols the emitted code calls, so it sees a
     send through any wrapper (`Actor.cast`, `Actor.call`, a program
     function).
   - Program and library function names are recorded in the same table
     (`evens`, `List.drop`) and are not matched.
3. **No `Actor.Debug`** (the plan's rule). The fragment's code may not
   reach `Actor.debug` or `Actor.inspect_state`, and `march_actor_inspect`
   is denied. Reading state does not change it. The rule is kept because
   Debug is the authority to see anything an actor holds, and a skewed
   session should not add that to what a reviewer must reason about.
4. **No closure from an earlier `let`.** A forced input may not use a
   session binding whose type may hold a closure (`may_hold_closure`: a
   function type, in the type's arguments or in its definition's
   constructor and field types). The closure's code lives in the earlier
   input's fragment, where the symbol check cannot see it: `let f = fn x ->
   send(...)` followed by a forced `f(evens(2))` would otherwise pass.

Why not only the cap manifest: the plan's rule was "no `Actor.Debug` in the
fragment's caps", but **`Actor.Debug` and `Actor.Introspect` never appear in
a fragment's manifest**. The manifest is derived from the C symbols the
emitted code calls (`Cap_symbols`), and those two are proof caps with no
symbol. Checked 2026-10-07: against the test node with a policy of only
`IO.Console`, `Actor.inspect_state(debug, Actor.pid_from_int(intro, 0), 500)`
runs and answers `Ok({ n: 1 })`, signed and audited with `"caps":"-"`. So
the Debug check here is made on reached function names and the inspect
symbol instead. The node's policy not gating `Actor.Debug` (or
`Actor.Introspect`) for shell inputs is a pre-existing gap, outside this
change; filed as
[todo](../todos/2026-10-07-shell-policy-ignores-proof-caps.md).

## Limits

- **The symbol denylist is by name.** A new runtime function that mutates
  shared state without a capability, and has none of the words, is allowed
  until it is added to `mutating_syms`.
- **Closures reached another way are not seen.** A closure read out of a
  Vault or an actor's reply is not caught. Neither is one hidden in a
  session binding whose type is a bare type variable, which counts as no
  closure so that `Pid(a)` bindings stay usable.
- **The node does not enforce it.** The node never sees the client's
  source, so it cannot detect skew. A client that omits `skew:1` is not
  caught. The field makes forced inputs stand out in the audit trail; it is
  not a control. The deploy key is the trust boundary, as for every EVAL.
- **A read-only answer can still be wrong for the node.** The fragment
  runs this checkout's version of the differing code. That is the point
  of the warning and the `[skew]` marker.
- **`let` under `--force`.** A forced `let` stores its value in the
  session's own slot. That is not node state, so it is allowed, and the
  session is marked `[skew]` from then on.

## Tests

- `test/dune` `native_shell_skew_force.out` (new;
  `test/shell/skew_force.txt`, expected
  `test/native/shell_skew_force.expected`): the skewed client of
  `native_shell_skew.out` with `--shell-force`, under a policy listing
  `IO.Console`, `Actor.Introspect` and `Actor.Debug`.
  - `evens(4)` runs with the warning (`[0, 2, 4]`, this checkout's
    `evens`).
  - `send(c, Bump(…evens…))` is refused ("calls march_send").
  - `Actor.set_queue_limit(c, …evens…, 1)` is refused ("calls
    march_actor_set_mbox_limit").
  - `f(…evens…)`, where `let f = fn x -> x + 1` came earlier, is refused
    ("uses `f`, an earlier binding that may hold a closure").
  - `Actor.inspect_state(debug, c, …evens…)` is refused ("calls
    march_actor_inspect", "uses Actor.Debug").
  - `file_write(…evens…)` is refused ("calls march_file_write", "uses
    IO.FileWrite"), and the file is never created.
  - `List.length([Dark, Light]) + …evens…` is refused on `Shade` (its
    definition and its tags differ). The fixture has no type that differs
    without a tag change, so the type-only case is not separately covered.
  - `nap() + …evens…` passes the read-only rule and is refused by the
    node's policy (`IO.Clock`).
  - An unforced `Actor.inspect_state(debug, c, 500)` afterwards shows
    `{ n: 1 }`: the refused send never ran.
  - The node's audit log has `"skew":1` on exactly the two forced inputs
    that reached it.
- `test/shell_check.ml` (`native_shell_node.out`): a signed `skew:1` EVAL
  runs; `skew:yes` is `bad_args`; exactly that one audit line carries
  `"skew":1`.
- Unchanged and green: `native_shell_session.out`, `native_shell_skew.out`
  (no `--force`: same refusals as before), `native_shell_link.out`;
  `scripts/run-tests.sh -q compiler`.

**RED proof** (each change made by copying the file aside, editing it, and
copying it back):
- `not_read_only` returning `[]`: `native_shell_skew_force.out` diverges.
  The send, the queue-limit change, the inspect and the closure call all
  run (`Ok({ n: 4 })` before and after), the file write reaches the node's
  policy instead, and the audit gains four more `"skew":1` lines.
- The forced case accepting type and tag differences
  (`| decls, _ when force`): the `Shade` input runs (`4`) and is audited as
  skewed.
- Not writing `"skew":1` in `march_shell.c`'s audit: `native_shell_node.out`
  fails "the skew:1 EVAL, and only it, is audited with "skew":1".
- With all of this change reverted, the new golden fails on the unknown
  `--shell-force` flag, and `shell_check` gets `ERR bad_args` for `skew:1`.

Also checked by hand (not in the golden) against the same node: forced
read-only inputs using `Pid` and `List(Int)` bindings, `String.join` over
`List.map`, and `Actor.top_by_mailbox(intro, 3)` all run. `Actor.cast` is
refused (`march_send`), and so is `Option.map` over a binding holding
`Some(fn …)`.

`forge/test/test_forge.ml` "shell": `--force` passes `--shell-force` to
`march --shell` (`Cmd_shell.march_args`), and nothing without it.

## Reference counting is read-only (2026-10-08)

Merging this onto main exposed that the read-only check refuses any forced input
whose code reaches a non-inlined RC call. `Shell_ident.is_mutating_sym` matches
symbols by words, and the RC family's names contain two of them ("incr",
"free"). Reference counting normally compiles inline and is never a recorded
call, so nothing noticed until owned-call drop fusion made `march_decrc_freed` a
real call: every forced input that reached one was refused with "calls
march_decrc_freed" (`native_shell_skew_force`).

`rc_bookkeeping_syms` now exempts exactly `march_incrc`, `march_decrc`, their
`_local` forms and `march_decrc_freed` / `march_decrc_local_freed`. Exact names
only: a symbol that merely starts with one of them (`march_decrc_and_send`) is
still judged by its words. `test_shell_ident` "force: RC bookkeeping is
read-only" covers both halves and is red without the exemption.
