`[P2]` **Config erased-value boundary finding (2026-08-15).** `Vault(v)` now
rejects the old typed-handle confusion, but `Config` intentionally annotates
its heterogeneous global table as `Vault(v)`. Consequently `Config.get` can
still be instantiated as `Option(Pid)` after an `Int` was stored. The minimal
witness typechecks and the interpreter reaches `is_alive` with the wrong
representation, reporting `is_alive: expected Pid`. Closing this needs a
tagged/dynamic value representation or a checked typed Config API; adding
another phantom Vault parameter cannot solve it. No runtime change is included
in this finding.
