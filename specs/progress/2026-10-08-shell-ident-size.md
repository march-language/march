# Shell: a smaller identity table, and a session fetches only what differs

Logged 2026-10-08. Follows `2026-10-07-shell-build-identity.md`.

The shell identity table (`lib/jit/shell_ident.ml`) that every
`--compile --hot-reload` binary embeds as `__march_shell_ident` was 177 KB
(4,464 rows, 4,214 of them declaration hashes, mostly the stdlib's). The node
sent all of it, base64, on every shell session (`IDENT`, 239 KB).

## What changed

- **Format 2** (`Shell_ident.to_string` / `parse`, described under "the table
  as text"):
  - A `march-shell-ident 2` header.
  - Declarations grouped by module prefix: one `m <group> <digest>` line,
    then `<rest> <hash>` rows, so `List.f:map` is written `f:map` under
    `m List`.
  - 48-bit hashes as 8 base64url characters (`hash48`) instead of 16 hex
    digits. A hash is only ever compared with the other side's hash of the
    same key, never looked up among the others. So an edit is missed only if
    the edited text happens to hash to the very 48 bits the node has: 1 in
    2^48 per edited declaration, with no birthday bound. The table guards
    against a stale checkout; the signature guards what runs.
  - Constructor tags drop `=n` where the tag is the constructor's position.
- **Two-step fetch** (`Shell_ident.fetch`, `runtime/march_shell.c`
  `ident_select`): `IDENT SUMMARY` returns everything except the declaration
  rows: the `t` and `x` rows (which the client cannot compute) and the group
  digests. The client computes the same digests over its own declarations.
  It then asks `IDENT GROUPS a,b` only for groups whose digest differs. For
  a group that agrees, the client's own rows are the node's. `differing`,
  `fragment_skew` and the `x` rows for linking see the same table as before.
- **Compatibility.**
  - A node built before this answers `IDENT SUMMARY` with
    `ERR unknown_verb`. The client then asks for `IDENT` and reads format 1,
    taking a hash's first 12 hex digits, which are the same 48 bits.
  - A client built before this reads none of a format-2 table's
    declarations, so it refuses every input that reaches one ("is not in the
    node's build"). It fails closed.
  - `IDENT` with no argument still returns the whole table.
- **CAS key.** `digest` (`sident:`) is a hash of the format-2 encoding of the
  declarations, which is still a function of the declarations alone.

## Measurements (test/native/shell_node.march, macOS arm64)

| | before | after |
|---|---|---|
| embedded table | 179,562 B | 105,290 B |
| node binary | 937,512 B | 871,496 B |
| session start, up-to-date checkout | `IDENT`, 239,420 B | `IDENT SUMMARY`, 19,796 B |
| whole table (`IDENT`) | 239,420 B | 140,392 B |

The summary is mostly constructor tags (225 types), which the client cannot
derive from its source.

## Tests

- `test/test_shell_ident.ml` (run_compiler, group `shell_ident`):
  - format 2 round-trip, and re-encoding is stable;
  - `hash48` equals a format-1 hash's first 48 bits;
  - `fetch` against an emulation of the node's selection, in three cases: an
    up-to-date client sends only the summary; a client that differs fetches
    exactly the differing groups and gets the same `differing`; a format-1
    node is handled by the fallback.
  - Perturbing the digest comparison, the format-1 conversion and the tag
    expansion fails five of the six.
- The four shell goldens pass unchanged. `native_shell_skew.out` exercises
  `IDENT GROUPS`: breaking the node's group selection turns "2 declarations
  differ (evens, type Shade)" into 41 "not in the node's build".
- By hand: a new client against a node built from main (format 1) runs
  inputs and reports the skew as before.
