`[P1]` Hot reload: a patch that flips a parameter's borrow mode passes the sig_hash gate (UAF or leak)

Found by the HCR Phase 0 spike (`specs/progress/2026-10-13-hcr-phase0-spike.md`,
experiments E2 and E2'; prototype in `specs/spikes/2026-10-13-hcr-phase0/`).

## Symptom

Borrow inference (`Borrow.infer_module`) is whole-program, so a running caller
was compiled against the borrow mode of the callee version it was built with.
A patch whose new body turns a borrowable parameter (String, List, any ADT;
`Kind.borrowable_of`) from borrowed to owned releases a reference the caller
still holds. ASan on macOS and Linux reports a heap-use-after-free, with the
free in the patch's `Handler.count` and the use in the base's
`march_incrc`. The reverse flip leaks one reference per call (LSan: 40 000
allocations over 10 000 calls). Records and tuples are always owned
parameters, so they are not affected.

`forge deploy hot` compares `sig_hash` (`Serialize.serialize_fn_sig`, the type
signature only). Both versions of the reproducer's `Handler.count` have
`sig_hash bd9fc78c…`, with different borrow modes, so the gate accepts the patch.

```
specs/spikes/2026-10-13-hcr-phase0/run.sh /tmp/o v1 v3_owned     # UAF
specs/spikes/2026-10-13-hcr-phase0/run.sh /tmp/o v3_owned v1     # leak
```

## Direction

Fold each parameter's final borrow mode (the map Perceus used) into the hash
the gate compares, as `sig_hash` or as a separate `abi_hash` in the manifest
and `ABI_QUERY`. Then a flip is an ABI change, and the existing rule (every
caller of a sig-changed slot ships in the same deploy) makes it safe. This has
no runtime cost. The alternative, forcing every slot parameter owned under
`--hot-reload`, costs an inc/dec per borrowable argument per call.
