# The named actor registry leaked the name and the actor record per registration

**Fixed** 2026-10-12. Found by the LSan pass of the native sanitizer sweep
(`scripts/native-sanitize-sweep.sh -l`): `proc_reclaim_kill_respawn` reported
1,500 `march_string_concat` strings from `round` (one per round: the name it
registers each worker under).

## The bugs

1. **Borrow classification.** `actor_register`, `actor_unregister` and
   `actor_whereis` sat in `Borrow.extern_owned_builtins` ("deliberately owned,
   or not audited yet"), so Perceus handed each call a reference to its name
   (and `actor_register` one to the actor) and never released it. The runtime
   only reads them: `march_vault_set` copies the key and takes its own
   reference on the value, `meta_add_name` strdups the name, unregister and
   whereis look the name up. One String per call, plus an actor reference per
   registration.
2. **The registry's graveyard.** The registry is a Vault the runtime owns. A
   Vault does not release a value it stops holding (an overwrite, a drop): it
   buries it until a typed caller reaps it, because `march_decrc` cannot
   release a compound value's children. Nothing reaps the registry, so every
   entry retired at an actor's death, unregistered, or overwritten after its
   actor died kept its actor record for the life of the process. LSan never
   saw it (the graveyard still points at it); `live_allocs` grew by one per
   registration.

## The fix

- The three builtins move to `Borrow.extern_borrow_table` as read-only
  (`actor_register`: `[true; true]`, the other two `[true]`).
- New `march_vault_release_dead(table, key)` (runtime/march_extras.c) releases
  a key's shard graveyard with a plain `march_decrc` per value. The registry
  calls it after each `march_vault_set` / `march_vault_drop`
  (`march_actor_register`, `march_actor_unregister`, `registry_retire_meta`).
  An actor record needs no typed drop: the actor's own death releases its
  state, and `march_actor_register` already releases a stale entry it reads
  with a plain decrc.

## Verification

- `test/native/actor_registry_leak_probe.march`, 200 rounds each of register
  then kill / register, whereis, unregister, kill / one name overwritten
  after each death: 401 / 400 / 201 objects left before, under 5 after (the
  last actor may still be dying). The name is read after every call.
- Linux arm64 ASAN error pass and LSan pass on the probe and on every
  `actor_registry_*` fixture, `crash_dump`, `recon_basic` and
  `proc_reclaim_kill_respawn`: no errors; `proc_reclaim_kill_respawn` no
  longer reports the name strings.
