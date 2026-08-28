---
layout: docs
title: Capability Enforcement
nav_order: 5.65
permalink: /docs/capability-enforcement/
---

# Capability Enforcement

A module's declared capability set is checked and then *erased* at compile time
(see [Capabilities]({{ site.baseurl }}/docs/capabilities/), where capabilities
themselves are defined). That verifies your March code. It states no fact about
what the process may do once it is running, or what a node accepts when you
hot-patch it in production. This page covers the two mechanisms that turn a
*declared* capability set into an *enforced* one: an OS-level sandbox that
confines the compiled binary at startup, and a deploy-time admission gate that
governs hot-patched functions. Both turn what you declare into a boundary that
the runtime, or the deploying node, actually makes binding on you.

A related but different question: has a dependency's declared capability set
changed since you last checked? [`forge audit`]({{ site.baseurl }}/docs/capability-audit/)
answers that, by diffing source declarations against a recorded baseline.
That's still reading, not enforcing. This page covers the mechanisms that
make a declared set actually confine what runs.

---

## OS-level enforcement: sandboxing the compiled binary

FFI is the part of this the compiler can never see: an `extern` C call, a
`dlopen`, or a raw syscall runs past the point where capability types apply,
no matter how good the checker gets. That's the [`IO.Foreign`]({{ site.baseurl }}/docs/capabilities/#ioforeign--calling-unverified-c)
boundary, and the gap [`forge audit`]({{ site.baseurl }}/docs/capability-audit/#what-this-does-and-does-not-prove)
is explicit about not closing. But `--cap-sandbox` isn't only about FFI. It's
also a safety net for ordinary March code: a capability-inference bug, or a
dependency that's wrong, with no visible sign, about what it touches, gets caught the same
way an opaque C call does. March can close both cases at the OS level,
turning the declared capability set into an actual confinement.

**How much assurance do you actually get, and what does it cost you?** From least to most:

| Option | What you do | What you get | Caveat |
|---|---|---|---|
| No extra step (only the type system) | Just write March; `needs`/`Cap(X)` are required to reach any IO builtin | Compile-time proof of what the *code* can reach, for anything flowing through a signature or a direct body call | Proves no property of the running binary. `extern`/FFI C code is invisible past `IO.Foreign`. A call routed through a stdlib wrapper (`File.read` rather than `file_read`) slips past `--check` too, though `march --compile`'s capability upper limit still catches it. |
| [`forge cap inspect`]({{ site.baseurl }}/docs/capability-audit/#auditing-a-compiled-binary) | Run it against a compiled binary | An audit of what capabilities the binary appears to need | Read-only. Reports, doesn't confine. |
| `--cap-sandbox` (below) | Add the flag at compile time | The binary sandboxes *itself* at startup, from its own declared/used capabilities | Self-imposed and opt-in: a binary built without it is simply unconfined. Protects against your own bugs and compromised dependencies, not a hostile publisher. |
| `forge cap run ./binary` (below) | Run through forge instead of directly | Forge installs the sandbox from *outside* the process, before it starts | Policy still derives from the binary's own claimed capabilities. An under-reporting binary gets an under-scoped policy. |
| `forge cap run --allow-only X ./binary` | Run through forge and state the policy yourself | The strongest option: confinement chosen entirely by you, independent of what the binary claims | You have to know what to allow. Doesn't stop misuse *within* an allowed capability. |

The rule of thumb: the type system is the foundation everything else sits on. `--cap-sandbox` is for code you trust, deployed somewhere forge isn't the launcher. `forge cap run`, especially `--allow-only`, is for code you don't trust, whenever you *can* be the launcher.

There are two OS-level mechanisms: one imposed on the process from outside, one built into it.

### `forge cap run`, externally imposed (the stronger one)

`forge cap run` launches a binary under a sandbox that *forge* installs before the program gets control:

```
$ forge cap run ./build/myapp                        # policy from the binary's own claim
$ forge cap run --allow-only IO.Console ./untrusted   # policy YOU choose
```

For a binary you do **not** trust, pass `--allow-only`. Deriving the policy from the binary's own claim only tells you what it concedes, which is worthless against code trying to hide. Where a capability cannot be enforced by the platform's available primitive, `forge cap run` reports it as **advisory** per capability rather than pretending to enforce it. This is the stronger of the two mechanisms, because the launcher chooses the policy, not the code being confined.

### `--cap-sandbox`, self-imposed (defense in depth)

Compiling with `--cap-sandbox` embeds a **deny-default** profile, derived from *this program's own* declared capabilities, that the binary installs on itself at startup before any user code runs:

```
$ march --compile --cap-sandbox -o build/myapp app.march
```

- **macOS**: a Seatbelt (SBPL) profile via `sandbox_init()`. Deny-default, then each declared capability opens a specific hole: `IO.FileWrite` allows writes (narrowed to the path scopes you declared, otherwise blanket), `IO.Network` allows the `network*` operation class, `IO.Process` allows `process-fork`. `IO.FileRead` is **advisory** here: dyld must map system libraries before any user code exists, so the baseline allows reads unconditionally, and a scoped read rule would be decorative.
- **Linux**: an unprivileged in-process **seccomp-bpf** filter (`PR_SET_NO_NEW_PRIVS` + `PR_SET_SECCOMP`). One syscall class is denied per *withheld* capability: no `IO.Network` blocks `socket`/`socketpair`, no `IO.Process` blocks `execve`/`execveat`, no `IO.FileWrite` blocks the write path. Denied calls return `EPERM`. `IO.FileRead` is not enforced here either, because seccomp filters syscall *numbers*, not paths; path-scoped reads come from `forge cap run`'s mount namespace instead.

Installation **fails closed**: if the sandbox cannot be installed, the program will not run rather than continue unconfined.

`--cap-sandbox` is **opt-in defense-in-depth**, not a guarantee against a hostile *publisher*. The party building the binary chooses whether to compile it in, so a malicious author simply omits it. Its purpose is a binary *you* built and trust, deployed somewhere `forge` is not the launcher: under systemd, a supervisor, a container entrypoint. That's the exact case `forge cap run` cannot reach. When you control the launcher, prefer `forge cap run`.

Because both mechanisms confine the **whole process**, they bound even the code the compiler cannot see: `extern` C, `dlopen`, raw syscalls. They are the enforcement complement to [`forge cap inspect`]({{ site.baseurl }}/docs/capability-audit/#auditing-a-compiled-binary). `inspect` *reads* what a binary possesses; these *enforce* what it may do.

**Two platform asymmetries, confirmed against real running binaries rather than assumed from source:**

- On macOS, `IO.Network`'s `network*` grant does not gate `socket()` creation itself. It only gates the actual network operation: `bind()`/`connect()`. A withheld `IO.Network` still lets a program open a socket; it just can't do anything with it. Linux denies `socket`/`socketpair` entirely.
- On macOS, `IO.Process`'s `process-fork` grant gates `fork()` only. `process-exec` is unconditionally allowed in the baseline regardless of capability, so a withheld `IO.Process` still lets a program `execve()` a new one. Linux is the reverse: `execve`/`execveat` are denied, `fork`/`clone` never are (the scheduler needs threads). Tracked as an open question, not settled behavior: [specs/todos/2026-08-12-cap-sandbox-macos-process-exec-not-gated.md](https://github.com/march-language/march/blob/main/specs/todos/2026-08-12-cap-sandbox-macos-process-exec-not-gated.md).

### OS primitives, capability by capability

The prose above names the operation classes. This is the full map, including capabilities not mentioned above because they're advisory on every backend. For what each capability means and when to declare it, see the [Capability hierarchy]({{ site.baseurl }}/docs/capabilities/#capability-hierarchy) on the Capabilities page. Both enforcement mechanisms were verified against real compiled and running binaries. See `test/test_cap_sandbox_runtime.ml` (`--cap-sandbox`) and `forge/lib/cap_sandbox.ml`'s header comment (`forge cap run`) for exactly how each row was measured.

**`--cap-sandbox` (self-imposed):**

| Capability | macOS (Seatbelt) | Linux (seccomp-bpf) |
|---|---|---|
| `IO.Network` | `network*`: gates `bind`/`connect`, **not** `socket()` creation | denies `socket`, `socketpair` entirely |
| `IO.Process` | `process-fork`: gates `fork()` only; `process-exec` always allowed | denies `execve`, `execveat`; `fork`/`clone` never gated |
| `IO.FileWrite` | `file-write*` (blanket, or `subpath`-scoped to a declared `@[scope]`) | denies write-flagged `openat` (`O_WRONLY`/`O_RDWR`/`O_CREAT`/`O_TRUNC`/`O_APPEND`) plus the unambiguous mutators (`unlink*`, `rename*`, `mkdir*`, `rmdir`, `truncate*`, `chmod*`) |
| `IO.FileRead` | Advisory. Baseline unconditionally allows `file-read*`/`file-read-metadata` (dyld needs it before user code exists) | Advisory. Seccomp filters syscall *numbers*, not path arguments |

**`forge cap run` (externally imposed):**

| Capability | macOS (`sandbox-exec` / SBPL) | Linux (bubblewrap) |
|---|---|---|
| `IO.FileWrite` / `IO.FileSystem` | `file-write*` | `--ro-bind / /` (whole tree read-only) unless granted, then full read-write |
| `IO.Network` / `IO.NetConnect` / `.TLS` / `IO.WebSocket` / `IO.Database` | `network*` | `--unshare-net` (network namespace) |
| `IO.NetListen` | Folded into `network*`. Enforced, no separate bind/listen split | Advisory. A network namespace isolates rather than denies: `bind()` still succeeds, it's just unreachable |
| `IO.Process` | `process-fork` (Enforced overall, but exec of the target itself can't be denied, the same underlying gap as `--cap-sandbox`) | `--unshare-pid` |
| `IO.FileRead` | Advisory. dyld must read system libraries before user code runs | Enforced. An allow-list mount namespace (`--ro-bind-try` on only the loader's paths and the binary); anything else is *absent*, not just forbidden |
| `IO.Clock`, `IO.Spawn`, `IO.Console`, `IO.Random`, `IO.Foreign`(`.Blocking`) | Advisory everywhere, both platforms. No way to tell each one from the runtime's own baseline traffic (`clock_gettime`, thread creation, stdout/stderr needed to report violations, `/dev/urandom` read at startup, foreign C code being outside the capability model entirely) | (same) |

---

## Hot-deploy authorization: node-local admission control

When using `forge deploy hot` to upgrade a running application, the node gets a second opportunity to enforce capability discipline at deployment time, after signature verification and before the new code loads.

> This section covers the **node-side policy gate**. There is also a **client-side monotonicity gate**: a deploy that widens a function's authority beyond the running version aborts unless you pass `--grant-cap`. Both gates, with a full worked example (a console-only handler that gains `file_write`, and how each gate responds), are in the [Hot Code Reload guide → Capability-safe deploys]({{ site.baseurl }}/docs/hot-code-reload/#capability-safe-deploys).

### How it works

A hot deploy activates only the **functions that changed**; each is sent as a separate signed activation message. For **each activated function**, `forge deploy hot` embeds that function's own inferred IO capabilities (the capabilities its own body actually requires) in the message. Admission is checked per activated function, not over the whole artifact. This granularity matters: `--hot-reload` links the entire standard library, so a *whole-artifact* capability set would be dominated by the stdlib's footprint and identical for every app, useless for a policy. Gating on the changed function's own caps is what makes the policy discriminating. The trust boundary: the **base server binary is trusted** (the operator built and started it, with a policy), and each **hot-patched function** is what the gate governs.

The receiving node, for each activated function:

1. **Recomputes the capability set**: normalizes the function's declared caps and hashes them with BLAKE3, reproducing the digest that was signed during the deploy.
2. **Tamper-checks**: compares its computed digest to the signed value; a mismatch (`ERR cap_tamper`) aborts before dlopen. The tamper check is **unconditional** even when the function declares no capabilities: a truly cap-free function has the fixed digest `blake3("")`, so a stripped capability field on a signed message is detected rather than silently admitted.
3. **Applies the deployment policy**: if `MARCH_DEPLOY_POLICY` is set (a file path), the node verifies that every capability the activated function declares is subsumed by a capability listed in the policy; a capability outside policy (`ERR cap_policy <cap>`) aborts.

### Configuring the policy

Set the `MARCH_DEPLOY_POLICY` environment variable to a file path:

```bash
export MARCH_DEPLOY_POLICY=/etc/march/deploy-policy.txt
```

The policy file is line-delimited. Each non-empty, non-comment line is a permitted capability path:

```
# /etc/march/deploy-policy.txt
IO
IO.FileRead
IO.NetConnect.TLS
IO.Clock
```

An empty policy file or absent `MARCH_DEPLOY_POLICY` means permissive: all activations are admitted. This is the default for backward compatibility. A policy constrains what *hot-patched* functions may do; it does not retroactively constrain the trusted base binary the operator already deployed.

### Threat model and scope

The policy is **authorization on a self-reported manifest**: a defense-in-depth layer, not a sandbox. A party with the signing key can lie about what capabilities the code uses. The node admission gate proves:

- The artifact was signed by the expected entity (Phase 4 ed25519 signature).
- The declared capability set has not been tampered with in transit (BLAKE3 tamper-check).
- The declared capabilities are within a static policy envelope (subsumption check).

It does **not** prove that the code actually *uses* only those capabilities, only that the manifest claims it does, and the claim is signed and untampered. Runtime enforcement via `cap no_panic`, `cap no_alloc`, FFI sandboxing, or OS-level confinement can provide stronger guarantees. For most deployments, the combination of compile-time capability verification, signed manifests, and policy gates is sufficient.

---

## See also

- [Capabilities]({{ site.baseurl }}/docs/capabilities/): where capabilities are
  defined and declared. This page enforces what that page declares.
- [Capability Audit]({{ site.baseurl }}/docs/capability-audit/): `forge audit`
  reads *declared* capabilities from source and flags when a dependency's
  capabilities change; `forge cap inspect` reads what a *compiled binary*
  actually possesses. Both read. The mechanisms here *enforce*.
- [Safety by Construction]({{ site.baseurl }}/docs/safety-by-construction/): how
  capabilities sit alongside the other safety axes.
