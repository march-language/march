# An idle conduit worker grew ~5 MB/min: ten steady per-call leaks

**Date:** 2026-10-01
**Regression guard:** `test/native/idle_worker_leak_probe.march`, built twice
(plain and `--hot-reload`); every leg prints `flat: false` on main 8f2f6608.

## Symptom

forgepm's background-job process (conduit's worker/heartbeat/leader/cron loops
polling Postgres through depot's actor `Pool`) grew linearly while completely
idle: ~5 MB/min in production, ~2.7 MB/min locally. Nothing in conduit or depot
was at fault. Every Postgres round trip, pool checkout and actor message leaked
a little, through compiler and runtime bugs that showed up in ordinary code.

Measured with `live_allocs()` per call, main 8f2f6608 → this change:
`Db.exec("SELECT 1")` 210 → 0, a pooled checkout/checkin 2 → 0,
conduit `fetch_next` on an empty queue ~44 → 0, an advisory-lock call 11 → 0,
`Vault.get` with a built key 1 → 0. The real worker went from +27 MB/10 min to
flat (5.1–5.3 MB over 12 min).

## Causes and fixes

1. **Library newtypes freed shallowly** (`drop.ml`). `find_variant_by_suffix`
   re-classified a short type name under its QUALIFIED registration
   (`Bytes.Bytes` → Newtype) and declined the drop, while codegen builds the
   value Boxed by the short name. Every dying `Bytes` orphaned its String.
2. **Niche `Option` of a boxed payload freed shallowly when released
   directly** (`drop.ml`). Main's `drop_op`/`erased_payload` releases a niche
   or newtype FIELD through its payload's drop, but a niche value released on
   its own (`dec_rc o` on an `Option(Bytes)`) still got a bare release.
   `drop_fn_for` now wraps `drop_op` for such types. Postgres `DataRow` cells
   (`List(Option(Bytes))`) leaked their strings.
3. **Unaudited "owned" builtins that only read their argument** (`borrow.ml`):
   `string_chars`, `string_from_chars`, `tcp_send_all` (exempt from
   test_builtin_borrow_classification because its row is `in_is_builtin =
   false`), and the whole Vault family (vault_update's closure stays owned).
4. **Vault calls were indirect** (`defun.ml`). Missing from `builtin_names`,
   they lowered as `call_ptr`. Codegen redirects that to the vault arms, but
   Perceus/borrow saw an indirect call that consumes everything.
5. **Heap "Unit" results** (runtime). `make_unit` in march_http.c and the
   Unit-returning vault builtins `march_alloc(16)`'d a cell nothing released.
   Now `NULL`, as `mk_ok_unit` already did.
6. *(Fixed independently on main the same day, so not part of this change:
   the `let (a, b)` tuple temp's linearity, typing of tail tuples and
   match-ending scopes, tail placement of scope-end drops (`drop_agg_at_tails`)
   and dead join-point closure captures. Before those landed they accounted
   for most of the remaining per-query and `fetch_next` residue.)*
7. **Owned aggregate parameters were dropped per FUNCTION, not per path**
   (`perceus.ml` `insert_owned_aggregate_param_drops`). A parameter moved or
   released on one arm leaked on every arm that only read it. This is depot's
   `Pool.handle_checkout`.
8. **Record update kept a reference to each overwritten field**
    (`llvm_emit_data.ml`): every slot was copied with `incrc`, then the
    updated ones were overwritten.
9. **Actor handlers dup'd every heap state field** (`perceus_core.ml`
    `is_actor_move_source`). `Lower_actor` loads state fields as MOVES out of
    the linear `$actor` (and the hot-reload `$f_state_v`) and its `EReuse`
    write-back overwrites the slots without releasing them; Perceus treated
    the loads as borrowed projections and dup'd them into `state`. That was
    one leaked reference per heap field per message (two under
    `--hot-reload`).
## A use-after-free that (11) exposed

With (9) in place, depot's Pool crashed: `handle_checkout`'s `Cons(conn,
rest)` arm released the dead `cfg` BEFORE the idle list's destructuring
release. `Llvm_case.strip_scrut_decrc` finds the scrutinee's release only at
the head of a run of plain `dec_rc`s, and `Drop` (then the inliner) had turned
`dec_rc cfg` into `__drop$..(cfg)`. The list's release compiled without its
shared-path field dups, and dropping the old state freed the connection being
handed out. The extra reference from (9) had masked it. Fix:
`add_cross_decrcs` keeps the scrutinee's release at the head of the arm (the
other releases are of distinct dead values, so order is immaterial), and
`strip_scrut_decrc` also skips `__drop$` calls. Perceus snapshots now show the
scrutinee's release first.

## A use-after-free on main this change also fixes

Validating against forgepm on current main failed 2 of its 756 tests (an email
recipient's address read back as garbage). The bisect pointed to 64091d1e3: its
`drop_agg_at_tails` releases an owned aggregate IN FRONT of a tail call when
nothing the call reads points into it, but it tracked only direct projections
of the aggregate. In `match m.to do Cons(a, _) -> check(a.address, "..")`, the
branch variable [a] and its projection [a.address] were missed, so [m] and the
list holding [a] were freed before [check] read the string. The scan now
follows projections of projections, aliases of projections, and the pattern
variables bound by matching one. Guard: `test/native/branch_alias_tail_drop.march`
(prints garbage on 078067811, `ok` with the fix).

## Follow-ups (not done here)

- `in_is_builtin = false` rows escape test_builtin_borrow_classification; the
  rest of that group (`http_parse_request`, `http_serialize_response`, ...)
  still defaults to owned.
- Builtins absent from `Defun.builtin_names` lose their borrow classification
  entirely (4). A guard that every `extern_borrow_table` name is a Defun
  builtin would catch the next one.
- Postgres error responses still leak (~16 objects each, depot's
  `ErrorResponse` path); off the idle path.
- An idle conduit worker uses ~37% CPU on both old and new builds; unrelated
  to these leaks.
