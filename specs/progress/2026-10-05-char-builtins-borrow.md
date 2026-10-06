# `char_to_int` and three char predicates leaked their argument on every call

**FIXED 2026-10-05.** Found bisecting the cluster registry's per-operation leak
(`ClusterNode.core_register` + `core_unregister`: 858 objects per pair).

## Cause

`lib/tir/borrow.ml` listed `char_to_int`, `char_is_digit`, `char_is_alphanumeric` and
`char_is_whitespace` in `extern_owned_builtins` (the list's "not audited yet" default),
so a call consumed its String argument and the caller stopped releasing it. Their C
implementations only read `data[0]`; nothing released the String. `Msgpack`'s
`str_to_bytes` calls `char_to_int` once per byte of every string it encodes, so every
encoded name and hash leaked one object per byte: 135 objects for one registry sync
frame, `NodeSend.encode_msg_schema`'s "3 objects per call".

## Fix

The four move to `extern_borrow_table`, beside the rest of the `march_char_` family.
Both checks the list asks for hold: the C code neither stores nor frees the String, and
every Char producer hands back an owned or immortal reference.

## Effect

`Msgpack.encode(Msgpack.str("abc"))`: 3 objects left per call before, 0 after;
`encode_registry_sync_resp` of one leaf 135 -> 0; the registry core pair 858 -> 464
(the rest was the dropped-closure leak, specs/progress/2026-10-05-dropped-closure-captures.md).

## Test

`test/native/colliding_type_drop.march`, leg "Msgpack.encode of a string".
