# HCR CI follow-up: service work entries and compile-so metadata

PR #1046's first CI run exposed two product gaps and several fixture assumptions.
A shared-library build without `--hot-reload` lost its sidecars when serialization
was shared with embedded metadata. The compile-so sidecar contract is restored;
Forge entry-rule tests verify manifests and byte-identical warm-cache restoration.

Closure creation-epoch pins correctly keep old callbacks on old code, but generated
long-lived service callbacks also create new session endpoints. Entering their old
frame before endpoint creation incorrectly made new sessions old. Generated topology
function/hosted-role adapters and protocol work-start adapters now explicitly enter the accepting
actor/task's epoch, only after comparing their complete ABI. Ordinary callbacks remain
pinned, and the adapter never chooses the globally newest epoch for old work.

The ABI includes parameter/result types, parameter ownership, and reachable nominal
layouts, including constructor and record field order. Qualified definitions are
resolved even when inferred parameters retain leaf names. A mismatch restores the
prior frame and raises a readable restart diagnostic instead of invoking the pointer.
Compiler provenance marks adapters; user function names alone do not opt into this path.

The closure-lifetime fixture now enters fresh requests explicitly, proves baseline
calls remain old, and retains escaping closures across the next activation before
releasing their pins. It keeps the original aggregate result checks and tests ring
reclamation. Remote-message/session fixtures make their fresh-work boundary explicit
without weakening loss, version-pair, or old-session assertions.

Validation so far:
- Forge entry-rule suite: all five cases, including cold and warm-cache sidecars.
- CAS ABI tests: 12 cases, including record order and simultaneous bare/qualified names.
- Compiled function and hosted-topology ABI regressions: captured nominal-layout changes alter published
  adapter signatures; manifest type hashes plus modes reconstruct those signatures.
- Generated incompatible-ABI execution: readable restart diagnostic, no segfault.
- Runtime frame/replay tests and closure pin golden (including ASan).
- Two-node remote message epoch and new-code session scenarios: ASan passes with
  original version, pair, and no-loss assertions.
- Control leader-kill, artifact-digest, and partition recovery: pass.
- Endpoint generation: 130 tests pass. Forge live upgrade cases 1 and 3 pass,
  preserving old sessions and checking new actor/task/session behavior.
- Documentation, runtime source inventory, and actor reference-store checks pass.

The expanded role-policy scenario passes both socket and control-plane reloads,
requiring both function and hosted-loop sessions to report exactly 40, 407, 4007.
Full platform CI is pending the follow-up push.
