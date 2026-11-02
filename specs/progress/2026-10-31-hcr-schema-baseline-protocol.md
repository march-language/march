# Activated schema baseline: runtime and Forge protocol

Implemented 2026-10-31 as part of
[`hot-deploy correctness`](../plans/2026-10-31-hot-deploy-correctness-design.md).
The original [first-deploy issue](2026-10-18-hcr-first-deploy-no-schema-baseline.md)
is complete; both compiled integration scenarios and the focused runtime/protocol
checks passed.

The compiler embeds deterministic `__march_hcr_schemas` and
`__march_hcr_manifest` character arrays in hot-reload base binaries and patches.
The reload server reads base metadata directly and patch metadata from the
loaded artifact; ACTIVATE7 verifies its bytes against the signed digest.
Owner-only, peer-credential-checked `SCHEMAS` queries return
one JSON line with `version:1`, an actor-keyed `schemas` object, and an actor-keyed
`releases` object containing `seq` and `id`. Base and unsequenced provenance use
sequence zero and ID `-`. The response reports the latest activated schema,
independently of actors still draining an older epoch. It deliberately omits the
full manifests: those can be megabytes, and duplicating them for every actor
would inflate both response size and memory use.

Only an activated actor dispatch replaces that actor's baseline. Staged,
disconnected, refused, and failed batches leave it unchanged; unrelated actor
schemas survive partial function updates. An activation of a known actor dispatch
without that actor's embedded patch schema is refused. Release provenance is
captured when each activation is received, rather than copied from a later
accepted release head when a batch commits.

Activated metadata is stored in `schemas.json` and exact per-image
`artifact-<cas>.schemas.json` / `.manifest` files beside the patch stack. Replay
rechecks signatures and bound artifact digests and reconstructs the baseline from their globals;
it never trusts the diagnostic metadata files as replay authority. Pruning the
stack also removes unreferenced per-image metadata. Before publishing code, the
server prepares and fsyncs the prospective stack, schema snapshot, and per-image
metadata, and syncs the state directory ancestry so newly created directories
are durable. A write refusal leaves code and baseline unchanged. After publication,
the authoritative stack is renamed and its directory synced first, followed by
derived metadata renames and another directory sync before acknowledgement; an
unexpected commit failure prints a diagnostic and exits with status 74 instead
of acknowledging or continuing to run an undurable activation. This is a
fail-stop response to a post-publication I/O failure, not an in-memory rollback.

`SCHEMAS` transmission handles partial writes and `EINTR` in bounded chunks;
a failed transmission closes the socket so a reader does not wait indefinitely
for a missing newline. `FRAME_PINS` reports `FRAME_PINS 1` for the updated runtime,
allowing the deploy client to distinguish frame-routing support from old servers.

Forge gives server schemas precedence over local `.prev` files and warns when
those files are stale. Only explicit `unknown_command` or `schemas_unavailable`
responses permit legacy fallback to a supplied prior schema file. Without one,
it refuses with restart / `--old-schemas` guidance. A known empty actor set is
valid. Malformed JSON, schema shapes, or release provenance and transport failures
do not fall back. Provenance validation requires exactly the schema actor keys,
unique object keys, an unsigned sequence below the runtime's reserved maximum,
and either base sequence zero with ID `-` or a positive sequence with a 32-digit
lowercase hexadecimal release ID.

## Verification

New runtime schema assertions were observed failing before implementation;
the new Forge suite initially failed its malformed-provenance and release-shape
cases. The `FRAME_PINS` assertion also failed before the capability reply was
added.

On 2026-10-31, a fresh `test/test_reload_activate4_runner` build and direct runs
passed all six modes: normal, `restore`, `schemas-restore`, `schemas-large`,
`policy`, and `policy-all`. The policy modes used the corresponding source-tree
policy fixture paths. These cover:

- Embedded base schemas, staging/disconnect isolation, partial actor updates, and
  refusal of a known actor whose patch omits its schema.
- Signed activation provenance, failed-batch preservation, denied prospective
  stack writes leaving code unchanged, restart/replay, substituted-artifact
  rejection, persisted metadata, and pruning.
- A 500 KB schema response received completely over a real socket in 997-byte
  client reads, including its final provenance object.
- Existing capability policy, artifact binding, release sequencing, and replay
  behavior.

`forge/test/test_schema_baseline.exe` passed all seven socket/provenance cases:
known empty schemas, unavailable baseline refusal, explicit legacy baseline,
malformed replies without fallback, transport failure without fallback, stale
local baseline warning/server precedence, and release provenance validation.
The tests use socket pairs with a forked peer that checks the exact `SCHEMAS`
request. Existing `test_forge` response fixtures were updated to include valid
base provenance.

Compiled integration scenarios `hcr_spawn_site_layout` and `hcr_rollback` both
passed on 2026-10-31 (coordinating run logs:
`/tmp/march-hcr-metadata-check/first-deploy.log` and `rollback4.log`). The first
exercises the initial state migration without a separately compiled base `.so`;
the second exercises signed live rollback, reverse-migration refusal, continued
service, and schema provenance. The stale-operator protocol case independently
proves that the server baseline wins over a differing local prior schema.

A subsequent durability review identified that fsyncing the file alone did not
make its rename durable. The regression interposes `fsync` in the C test process,
delegating normal calls to `SYS_fsync`: it observes synchronization of the state
directory and its parent, checks that the final metadata renames precede the
pre-ACK directory sync, and injects a directory-sync `EIO` after publication in a
forked phase. Before the fix, the synchronization assertions failed and the
injected failure was acknowledged; afterward they pass and the failure exits 74
without acknowledging. Release-head contents and directory updates are also
synced. This establishes the commit ordering and failure response; it is not a
physical power-cut test.

Restart integration exposed an additional issue: replay discarded intermediate
function versions and migration flags. Replay now preserves every complete signed
deploy batch and its migration flags, including helper dependencies. An invalid
entry refuses its whole batch and dependent suffix; a malformed line prevents
replay. Capacity exhaustion fails startup explicitly rather than omitting required
migrations. A native regression verifies two multi-function batches and refusal of
a corrupt dependency; the compiled v1 → v2 → v3 → original-base restart test verifies
both state migrations and the final shutdown callback. All six runtime modes pass.

Non-HCR runtime shared libraries use empty weak metadata definitions, overridden by
strong compiler-generated globals in hot-reload binaries. This permits REPL/JIT
runtime linking on macOS without requiring metadata symbols that only HCR builds emit.
The broad REPL/JIT suites exposed the original undefined-symbol failure.
