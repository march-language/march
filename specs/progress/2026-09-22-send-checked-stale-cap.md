# `[P2]` Compiled `send_checked` / `is_cap_valid` intermittently accepted a stale cap

**DONE 2026-09-22.**

**Symptom.** `test/native/cap_epoch_plane.march` compiled: after `kill(q)`, a cap
taken on `q` while it was alive printed `send_checked stale: :ok` in 40/200 runs and
`stale cap valid: true` in 7/200 (the interpreter prints `:error`/`false` every
time). The fixture had no `.expected` file and no `test/dune` rule, so nothing ran it.

**Root cause.** Not only the discarded `march_send` result the report suspected. A
compiled cap (`march_get_cap`, 5 words) stores the actor pointer in `word[2]`
**without a reference**. Once the actor is dead, its green thread drops the
runtime-held reference, and when the program drops its last `Pid` the record is freed
and its memory reused. `march_is_cap_valid` (via `find_meta_by_pid_index(..)->actor`)
and `march_send_checked` (via `cap_words[2]`) both then read the record's alive word
(`word[3]`) out of reused memory. When that word was non-zero the cap validated, and
`send_checked` called `march_send` on freed memory. It also returned `:ok`
unconditionally, whatever `march_send` returned.

**Fix** (`runtime/march_runtime.c`).
- New `cap_live_meta_locked(pid_index, epoch)`: resolves the incarnation by pid index
  and rejects it if unknown, `terminal_set` (claimed by `do_actor_death` under
  `g_tbl_mu`), or epoch-mismatched. It never touches the actor record. The meta is
  never freed.
- `march_is_cap_valid` = not revoked && `cap_live_meta_locked` under `g_tbl_mu`.
- `march_send_checked` takes its own `march_incrc` on `meta->actor` under the same lock.
  `terminal_set == 0` under `g_tbl_mu` implies that the actor thread still holds its
  reference, because it only drops that reference after `do_actor_death` claims
  `terminal_set` under the lock. So the record cannot be freed between the check and
  `march_send`. It returns `:ok` only when `march_send` returned `Some(())` (tag 1). A
  death or `stop`-draining between validation and enqueue now gives `:error`.
- The cap's `word[2]` is no longer read by either call.

**Test.** `test/native/cap_epoch_plane.expected` (the interpreter's output) + a
`test/dune` rule. Because the bug was a flake, the rule runs the binary once for the
golden and 50 more times, printing any run whose output differs. Proven RED on
origin/main's runtime (runs 4, 5, 6, 10, … differed with `send_checked stale: :ok`)
and GREEN with the fix. Direct loop with the fix: 1000/1000 runs clean (before: 40/200
stale `:ok`).

**Docs.** `specs/lang/actors.md`'s "exact byte match as of 2026-07-18" claims now note
the 2026-09-22 fix. `docs/actors.md` is an older hand-written page that still calls
the cap plane "interpreter-only"; the generator that would resync it
(`scripts/gen-lang-docs.py`) is not on main yet, so it was left alone.
