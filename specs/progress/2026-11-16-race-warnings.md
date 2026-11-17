Diagnostics: warnings for logical races (2026-11-16)

March has no memory-level data races. Values are immutable, actors share nothing, an
in-place update happens only to a value with one reference, and linear values cannot be
shared. Two kinds of race live above that model, and `lib/typecheck/typecheck_races.ml`
now warns about both. It runs at the end of `check_module_core`, beside the other
end-of-module sweeps, over `Typecheck_caps.module_own_exprs` of each module (nested
modules included), using the typechecker's exhaustive `iter_expr`.

The stdlib's own code is skipped (`Typecheck_builtins.span_is_stdlib`), including a
stdlib module checked as the entry: `test/dune`'s `cluster_node_check` and
`session_node_check` rules require that check to print no warning, and the stdlib's
Vault use (session_node's pending queues, cluster_node's meta counters) is concurrency
code reviewed where it is written, not something a user can change.

## `vault_check_then_act`

Each `Vault` call takes the table's lock for that call only. A read followed by a write
of the same key that depends on it loses a concurrent writer's update.

- Reads: `Vault.get`, `get_or`, `has`. Writes: `Vault.set`, `put`, `set_ttl`, `update`.
  `Vault.update` counts as a write because the runtime reads, runs `f` unlocked, then
  writes (`runtime/march_extras.c`, `march_vault_update`). Its stdlib doc now says so.
- Table and key are matched as written (`key_of`: names, literals, fields, constructors,
  tuples and calls of those). Anything else never matches.
- The pair must be in the same function body (not split across lambdas), and the write
  must depend on the read (`depends_on`): the read is inside the write's arguments, or a
  `let` chain carries the read's result into them, or the write is in a branch of an
  `if` / `match` / `cond` whose condition carries it.
- The warning is at the write, with a label at the read. The advice depends on the
  shape: `Vault.incr` when the written value does arithmetic, `Vault.put_new` after a
  `has` or a `get`, otherwise an actor or `incr` / `put_new` / `push_capped`.
- `@[no_warn_race]` on a function skips its body. It is in
  `Refine_check.known_fn_attributes`.

Swept over the repo's tracked `.march` files outside `stdlib/` that use a Vault read or
a parallel combinator (109 files): 54 warnings. Without the dependence rule there were
52, 4 of them unrelated reads and writes of the same key, which the rule drops; it adds
6 where the read is inside the write (`Vault.set(v, k, Vault.get_or(v, k, "") ++ "1")`).
The rest are real read-modify-writes in tests and examples, most of them on a Vault that
one task uses as a mutable cell. They are warnings, and those files were not edited.
`examples/lab_app` line 219 is a real race (a keep-the-max update in session replies,
which its own comment says arrive out of order).

## `parallel_shared_write`, `parallel_output_order`

The combinators and the argument each calls per element are `lib/tir/portable.ml`'s
seed list: `List.pmap/pmap_n/pfilter/preduce`, `Parallel.pmap/pmap_n/preduce/
preduce_n/pcount/pany/pall`, `Task.async_stream/async_stream_n`.

- A lambda argument (or a named function of this module) that writes a Vault key built
  from none of the lambda's own binders (its parameters and the names bound in its body)
  writes the same key on every call: `parallel_shared_write`.
- One that calls `println`, `print`, `print_line` or `print_stderr`:
  `parallel_output_order`.
- Both follow calls into functions of the same module to a fixpoint (`fn_effects`). A
  helper's write counts as shared when its key mentions none of the helper's own
  parameters or locals. The note says "(through `helper`)".
- Other I/O is not flagged: `portable.ml` allows it on purpose, and the docs recommend
  `pmap_n` with an HTTP fetch per element.

## Docs and corpus

- `specs/lang/errors/{vault_check_then_act,parallel_shared_write,parallel_output_order}.md`
  (new `CONCURRENCY` category in `Code.category_table`), and a paragraph in
  `specs/lang/parallelism.md`'s correctness guarantees.
- Corpus cases seeded from the three pages. `parallel_shared_write`'s page program
  printed `16` instead of the intended `81` on one run.

## Not done

- Calls through helpers in other modules, and through closures stored in variables,
  are not followed.
- No fix is offered: the atomic rewrite depends on what the code meant.
