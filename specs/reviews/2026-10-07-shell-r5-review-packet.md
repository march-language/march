# Remote shell (observe R5): security review packet

Prepared 2026-10-07 by the shell's author, for a reviewer who did not write
it. The plan requires this review before the shell is used against
production nodes (`specs/plans/2026-09-28-observe-recon-shell-plan.md`, R5
"Acceptance"). This document says what to look at and what the author already
suspects. It is not the review.

State covered: main plus #862 (cap manifest, R5.6; build identity, R5.4)
plus `feat/shell-link-node-fns` (fragments calling node functions).

## 1. What the shell is

`march --shell <reload socket>.shell app.march` (or `forge shell`/`forge rpc`,
which run it over forge's ssh tunnel) attaches to a running node built with
`--hot-reload --signing-pubkey`.
- **Client:** for each input, it typechecks against the program, compiles
  the input into a fragment `.so` (`lib/jit/repl_jit.ml` `shell_compile`),
  signs an `EVAL` line with the deploy key, and sends it.
- **Node:** the shell listener (`runtime/march_shell.c`) checks the line,
  writes the fragment to a private directory, `dlopen`s it, and runs its
  entry as a task under a crash trap, a timeout and output capture.

**Authority model.** Holding the deploy key already means "may run code on
this node" (`forge deploy hot`). The shell adds no new trust root. It adds:
- a **policy** (`$MARCH_SHELL_POLICY`) bounding the capabilities an input's
  code may use;
- an **audit line** per attempt;
- **refusal** of inputs whose code differs from the node's build.

## 2. Files

| What | Where |
|---|---|
| Node listener, EVAL checks, task, limits | `runtime/march_shell.c` |
| Signature, nonce, expiry | `runtime/march_sig.c`, `runtime/march_sig.h` |
| Client session, signing, timing | `bin/shell_cmd.ml` |
| Fragment compile, caps, manifest, linking | `lib/jit/repl_jit.ml` (`shell_compile`) |
| Build identity, node function table | `lib/jit/shell_ident.ml` |
| Node's identity table emission | `bin/main.ml` (`shell_ident_decls`, emit site) |
| forge front ends | `forge/lib/cmd_shell.ml` |
| Tests | `test/shell_check.ml`, `test/shell/*`, `test/native/shell_*` |
| Design notes | `specs/progress/2026-10-06-shell-*.md`, `2026-10-07-shell-*.md` |

## 3. The EVAL path, check by check (node side, in order)

1. Connection accepted. One of 4 sessions (`SHELL_MAX_SESSIONS`), else
   `ERR busy`.
2. `HELLO` is required first. It reserves this session's 256 value slots.
3. **The line parses.** Line ≤ 8 MiB, fragment ≤ 4 MiB (`SHELL_LINE_MAX`,
   `SHELL_SO_MAX`).
4. A deploy key is compiled in, else `ERR signing_not_configured`.
5. **The signature** (ed25519 over the whole line minus the signature,
   fragment bytes included).
6. **Nonce and expiry** (`march_sig_admit`):
   - the nonce is 16-64 hex digits;
   - `not_after_ms` is in the future, at most 60 s ahead;
   - the nonce is not in the 256-entry in-memory ring; when the ring holds
     256 unexpired nonces, `nonce_ring_full` refuses the line.
7. **Epoch:** the session's epoch is still current, else `ERR epoch_changed`
   (a deploy ends the session).
8. **Policy:** every signed cap is a line of `$MARCH_SHELL_POLICY`. The file
   is re-read per EVAL; a missing file allows nothing; matching is an exact
   line match.
9. **Limits:** timeout ≤ 30 s; `kind` is `value` or `init`.
10. **Load:** the fragment is written to `$TMPDIR/march-shell-<pid>/frag-N.so`,
    `dlopen(RTLD_NOW | RTLD_LOCAL)`, and its entry symbol looked up.
11. **Cap manifest:** `__march_cap_manifest` must exist and list exactly the
    signed caps (`ERR cap_tamper` / `ERR no_cap_manifest`).
12. The attempt is audited (`"type":"shell"`, signer, nonce, caps, source,
    result), then the entry runs as a task.

## 4. Threat model (from the plan) and where each is handled

### 4.1 An attacker who can reach the socket but lacks the key

- **Socket:** the listener is a unix socket `<reload>.shell`, chmod 0600,
  owned by the node's user.
- **Defences:** every EVAL needs a valid signature (step 5). `HELLO` and
  `IDENT` are unauthenticated. `IDENT` returns hashes of source declarations
  and the node's function signatures, not source.
- **Tests:** `test/shell_check.ml` covers `bad_signature`, `no_hello` and
  `bad_args`.
- **Look at:** the parser for the unauthenticated verbs, and allocation
  sizes before the signature is checked. An 8 MiB line is buffered before
  the check. The unauthenticated side can hold 4 sessions (DoS).

### 4.2 An attacker who captured one signed line

- **Defences:** a 60 s maximum validity; the nonce ring refuses a replay
  within it.
- **Tests:** `replay` and `epoch_changed` in `test/shell_check.ml`.
- **Suspected gaps:** see F1 and F2 below.

### 4.3 An operator whose checkout is one commit behind the node

- **Defences (R5.4):** the node embeds a hash per source declaration and
  each variant type's constructor tags (`__march_shell_ident`, served by
  `IDENT`). The client maps each fragment function to its source
  declaration by provenance span, and refuses inputs reaching anything
  that differs, naming it. A node predating this gets a warning, and its
  inputs are not checked.
- **Tests:** `native_shell_skew.out` (a changed fn body, reordered
  constructors).
- **Look at:**
  - identity is source text, not compiled code, so a different compiler
    over identical source is caught only where it changes constructor
    tags;
  - after a hot deploy the table still describes the baseline build
    (F7).

### 4.4 A fragment that under-declares its caps

- **Defences (R5.6):**
  - the client derives caps from the C symbols the emitted code calls, plus
    `Cap_attrib.cap_of_call` over everything the input reaches (for code
    called on the node instead of copied);
  - the fragment carries them as `__march_cap_manifest`;
  - the node requires the manifest to equal the signed caps, after
    `dlopen` and before running.
- **Tests:** `test/shell_check.ml` (`cap_tamper` wider and narrower,
  `no_cap_manifest`), and `nap()` in `test/shell/session.txt` (a cap
  reached through program code is refused).
- **What this does not stop:** a signer who edits both the manifest and the
  signed caps. That is the deploy key's trust, as for `ACTIVATE`.
- **Look at:**
  - whether any capability-bearing runtime entry point is missing from
    `Cap_symbols` / `cap_of_call` (an omission there is an under-declaration
    everywhere, not only in the shell);
  - that `dlopen` runs before the manifest check (F5).

### 4.5 Fragments calling the node's own functions (new, not in the plan)

- **What's checked:** a fragment may call a node function instead of
  carrying a copy, when all of these hold:
  - the node publishes it (not a hot-reload slot, a stable name);
  - the name and LLVM signature match;
  - its types hold no closure or type variable.

  The client then places RC at those calls using the node's per-parameter
  borrowed/owned modes.
- **Risks:**
  - a wrong mode is a use-after-free or a leak in the node;
  - a name collision calls the wrong function.
- **Tests:** `native_shell_link.out`. Forcing every mode to "borrowed"
  crashes the node, and Linux ASAN reports `heap-use-after-free`; the real
  modes run clean.
- **Look at:**
  - `stable_name` (counter-numbered names were published before it
    existed);
  - whether any pass after Perceus in the node's pipeline changes a
    function's parameters (I found none: Drop, Escape, Opt, map inlining);
  - that `Escape` in the client keeps an empty borrow map.

### 4.6 A key holder (out of the plan's model; for completeness)

The policy bounds capabilities, not effects. An input with no caps can still:
- `send` any message of the right type to any actor it can name (naming one
  needs `Actor.Introspect`, via `Actor.pid_from_int`);
- read actor state with `Actor.Debug`;
- run for up to 30 s;
- leave a loaded `.so` behind (fragments are never `dlclose`d), and a loop
  without cancellation points running after its timeout.

## 5. Found while preparing this packet (candidate findings)

The author's own suspicions, unverified by a second reader.

- **F1. Replay after a restart.** The nonce ring is in memory, and a
  restarted node starts at the same epoch (`MARCH_EPOCH_BASE`). A line
  captured up to 60 s before a restart is accepted once more after it: a
  second `INSERT`, say.
- **F2. Replay against another node.** An EVAL names no node. A line
  captured for one node verifies on any node with the same key and epoch,
  within its 60 s.

  *Suggested fix for both:* `HELLO` returns a random per-session challenge,
  and the client signs it into every EVAL.
- **F3. Audit fails open.** `audit()` returns quietly when the log cannot be
  opened, and the EVAL still runs. The plan says every input is audited.
  Fail closed (`ERR audit`)?
- **F4. Socket mode window, and no peer check.** The shell socket is
  `chmod 0600` after `listen()`, while the reload socket sets the mode
  between `bind` and `listen`, so a connection can be accepted under the
  umask's mode in between. The reload socket also drops peers whose uid is
  neither the process's nor root's; the shell listener does not.
- **F5. Code runs before the manifest check.** A fragment's constructors
  and initialisers run at `dlopen`, before step 11. A March-built fragment
  has none, so this matters only for a malicious signer, who is trusted
  anyway. But it means the manifest check constrains stale clients, not
  hostile ones.
- **F6. Crash containment.** A SIGSEGV inside fragment code is caught and
  the node carries on (`PANIC`), possibly with corrupted state. Worth an
  opinion on whether a fault there should take the node down instead.
- **F7. Identity after a hot deploy.** `__march_shell_ident` describes the
  baseline build, not deployed patches. Linking skips hot-reload slots, so
  no call goes to replaced code, but the identity summary can be wrong
  after a deploy.
- **F8. Policy matching is exact.** A policy line `IO` does not allow
  `IO.Console`. Safe, but an operator may expect the cap hierarchy.
- **F9. Session bindings and borrowed callees.** A `let`-bound value loaded
  from its slot is incremented on load, and is not released after a call to
  a callee that only borrows it. That would be one leaked reference per such
  call, a leak rather than a safety issue. Unverified; possibly related to
  `specs/todos/2026-10-06-shell-fragment-leaks.md`.

## 6. Suggested exercises

- **Replay:** capture a line (log it from `bin/shell_cmd.ml`), restart the
  node, and resend within 60 s (F1). Resend to a second node built with
  the same key (F2).
- **Unauthenticated fuzzing:** fuzz `HELLO`, `IDENT` and malformed `EVAL`
  field parsing.
- **Under-declaration:** hand-build a `.so` whose manifest omits a cap its
  code calls, signed honestly for the manifest's caps. Today it runs, and
  the node trusts the signer: confirm that is the intended boundary.
- **Linking:** an input passing a value to a node function that keeps it
  (stores it in an actor or a Vault). Its mode must be "owned"; check under
  `MARCH_SANITIZE=1 MARCH_DEBUG_RUNTIME=1` on Linux. The `march-amdr-repro`
  image works: copy the tree in and run `opam exec -- dune build --root .
  bin/main.exe test/shell_check.exe`, about 10 minutes. Then build the node
  with those two variables set, and set `MARCH_RUNTIME_DIR` to the tree's
  `runtime/`.
- **Resources:** 4 sessions × 30 s loops; a 4 MiB fragment per input.
