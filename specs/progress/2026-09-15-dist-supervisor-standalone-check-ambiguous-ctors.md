# `[P3]` `stdlib/dist_supervisor.march` fails a standalone `--check`: `Normal`/`Killed`/`Crash` ambiguous between modules

Filed 2026-09-15, measured on `main` (with the stdlib as committed):

```
$ march --check stdlib/dist_supervisor.march
Constructor `Normal` is ambiguous between multiple modules:
Constructor `Killed` is ambiguous between multiple modules:
Constructor `Crash` is ambiguous between multiple modules:
```

`DistLink.DownReason` (`Normal | Killed | Crash(String) | NodeDown`) shares
constructor names with the local monitor's `DownReason` (`Normal | Killed |
Crash(String)`), and `dist_supervisor.march` matches them bare. It is not in
the `entry_mod_qual_erasure` exact-check list, which is why nothing red
shows; a program that `use`s both would hit the same ambiguity.

Fix: qualify the matches in `dist_supervisor.march` (`DistLink.Killed`), and
add the file to the exact-check list so it stays checkable standalone.

## Shipped 2026-09-15

Arms qualified (`DistLink.Normal` etc.) in `should_restart`; `--check
stdlib/dist_supervisor.march` exits 0 (one pre-existing non-tail-recursion
warning on `update_child_go`, unrelated). Guard: `test_compiler.ml`'s
`entry_mod_qual_erasure` group gained "dist_supervisor.march exact CLI
check", the same shape as dist_link's.
