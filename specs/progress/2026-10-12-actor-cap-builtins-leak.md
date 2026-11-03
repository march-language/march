# The epoch-Cap builtins leaked the cap on every call

**Fixed** 2026-10-12. Found by the LSan pass of the native sanitizer sweep
(`scripts/native-sanitize-sweep.sh -l`): `proc_reclaim_kill_respawn` reported
about 1,100 `march_get_cap` cells from its `use_cap` lambda, and
`cap_epoch_plane` reported two from `march_main`.

## The bug

`send_checked`, `is_cap_valid` and `revoke_cap` sat in
`Borrow.extern_owned_builtins`, so Perceus handed each call a reference to the
cap. The runtime only reads the cap's `(pid_index, epoch)` words
(`march_send_checked`, `march_is_cap_valid`, `march_revoke_cap`); nothing
stores or frees it. Every call leaked the cap `get_cap` had allocated (one per
`get_cap` whose cap was used at all, since the last use is a consuming one).

## The fix

The three builtins move to `Borrow.extern_borrow_table`: the cap borrowed, and
`send_checked`'s message still owned (it is sent, or released on every
refusal path).

## Verification

- `test/native/actor_cap_leak_probe.march`: 200 rounds of two sends and a
  check through one cap on a live actor, and of check / revoke / check /
  refused send on a fresh actor: one leaked cap per round before, flat after.
  The cap is used again after each call.
- Linux arm64 ASAN error pass and LSan pass on the probe, `cap_epoch_plane`
  and `proc_reclaim_kill_respawn`: no errors, and neither reports the caps.
