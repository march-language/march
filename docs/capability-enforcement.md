---
layout: docs
title: Capability Enforcement
nav_order: 5.65
permalink: /docs/capability-enforcement/
---

# Capability Enforcement

A module's declared capability set is checked and then *erased* at compile time
(see [Capabilities]({{ site.baseurl }}/docs/capabilities/), where capabilities
themselves are defined). That verifies your March code, but it says nothing about
what the process may do once it is running, and nothing about what a node accepts
when you hot-patch it in production. This page covers the two mechanisms that turn
a *declared* capability set into an *enforced* one: an OS-level sandbox that
confines the compiled binary at startup, and a deploy-time admission gate that
governs hot-patched functions. Both take the set the Capabilities page taught you
to declare and make it a boundary the runtime — or the deploying node — actually
holds you to.

---

## OS-level enforcement — sandboxing the compiled binary

Capability *types* are checked at compile time and then erased. That verifies your
March code, but it says nothing about what the process may do once it is running: an
`extern` C call, a `dlopen`, or a raw syscall is past the point the compiler can see.
This is the [`IO.Foreign`]({{ site.baseurl }}/docs/capabilities/#ioforeign--calling-unverified-c)
boundary, and the gap [`forge audit`]({{ site.baseurl }}/docs/capability-audit/#what-this-does-and-does-not-prove)
is explicit about not closing. March can close it at the OS level, turning the declared
capability set into an actual confinement.

There are two mechanisms — one imposed on the process from outside, one built into it.

### `forge cap run` — externally imposed (the stronger one)

`forge cap run` launches a binary under a sandbox that *forge* installs before the program gets control:

```
$ forge cap run ./build/myapp                        # policy from the binary's own claim
$ forge cap run --allow-only IO.Console ./untrusted   # policy YOU choose
```

For a binary you do **not** trust, pass `--allow-only`: deriving the policy from the binary's own claim only tells you what it admits to, which is worthless against code trying to hide. Where a capability cannot be enforced by the platform's available primitive, `forge cap run` reports it as **advisory** per capability rather than pretending to enforce it. This is the stronger of the two mechanisms, because the launcher — not the code being confined — chooses the policy.

### `--cap-sandbox` — self-imposed (defense in depth)

Compiling with `--cap-sandbox` embeds a **deny-default** profile, derived from *this program's own* declared capabilities, that the binary installs on itself at startup before any user code runs:

```
$ march --compile --cap-sandbox -o build/myapp app.march
```

- **macOS** — a Seatbelt (SBPL) profile via `sandbox_init()`. Deny-default, then each declared capability opens a specific hole: `IO.FileWrite` allows writes (narrowed to the path scopes you declared, otherwise blanket), `IO.Network` allows sockets, `IO.Process` allows fork. `IO.FileRead` is **advisory** here — dyld must map system libraries before any user code exists, so the baseline allows reads unconditionally and a scoped read rule would be decorative.
- **Linux** — an unprivileged in-process **seccomp-bpf** filter (`PR_SET_NO_NEW_PRIVS` + `PR_SET_SECCOMP`). One syscall class is denied per *withheld* capability: no `IO.Network` blocks `socket`/`socketpair`, no `IO.Process` blocks `execve`/`execveat`, no `IO.FileWrite` blocks the write path — denied calls return `EPERM`. `IO.FileRead` is not enforced here either, because seccomp filters syscall *numbers*, not paths; path-scoped reads come from `forge cap run`'s mount namespace instead.

Installation **fails closed**: if the sandbox cannot be installed, the program refuses to run rather than continue unconfined.

`--cap-sandbox` is **opt-in defense-in-depth**, not a guarantee against a hostile *publisher* — whoever builds the binary chooses whether to compile it in, so a malicious author simply omits it. Its purpose is a binary *you* built and trust, deployed somewhere `forge` is not the launcher — under systemd, a supervisor, a container entrypoint — the exact case `forge cap run` cannot reach. When you control the launcher, prefer `forge cap run`.

Because both mechanisms confine the **whole process**, they bound even the code the compiler cannot see — `extern` C, `dlopen`, raw syscalls. They are the enforcement counterpart to [`forge cap inspect`]({{ site.baseurl }}/docs/capability-audit/#auditing-a-compiled-binary): `inspect` *reads* what a binary holds; these *enforce* what it may do.

---

## Hot-deploy authorization — node-local admission control

When using `forge deploy hot` to upgrade a running application, the node has a second opportunity to enforce capability discipline at deployment time — after signature verification, before the new code is loaded.

> This section covers the **node-side policy gate**. There is also a **client-side monotonicity gate** — a deploy that widens a function's authority beyond the running version aborts unless you pass `--grant-cap`. Both gates, with a full worked example (a console-only handler that gains `file_write`, and how each gate responds), are in the [Hot Code Reload guide → Capability-safe deploys]({{ site.baseurl }}/docs/hot-code-reload/#capability-safe-deploys).

### How it works

A hot deploy activates only the **functions that changed** (each is sent as a separate signed activation message). For **each activated function**, `forge deploy hot` embeds that function's own inferred IO capabilities — the capabilities its own body actually requires — in the message. Admission is checked per activated function, not over the whole artifact. (This granularity matters: `--hot-reload` links the entire standard library, so a *whole-artifact* capability set would be dominated by the stdlib's footprint and identical for every app — useless for a policy. Gating on the changed function's own caps is what makes the policy discriminating.) The trust boundary is: the **base server binary is trusted** — the operator built and started it, with a policy — and each **hot-patched function** is what the gate governs.

The receiving node, for each activated function:

1. **Recomputes the capability set** — normalizes the function's declared caps and hashes them with BLAKE3, reproducing the digest that was signed during the deploy.
2. **Tamper-checks** — compares its computed digest to the signed value; a mismatch (`ERR cap_tamper`) aborts before dlopen. The tamper check is **unconditional** even when the function declares no capabilities: a genuinely cap-free function has the fixed digest `blake3("")`, so a stripped capability field on a signed message is detected rather than silently admitted.
3. **Applies the deployment policy** — if `MARCH_DEPLOY_POLICY` is set (a file path), the node verifies that every capability the activated function declares is subsumed by a capability listed in the policy; a capability outside policy (`ERR cap_policy <cap>`) aborts.

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

An empty policy file or absent `MARCH_DEPLOY_POLICY` ⇒ permissive (all activations admitted). This is the default for backward compatibility. A policy constrains what *hot-patched* functions may do; it does not retroactively constrain the trusted base binary the operator already deployed.

### Threat model and scope

The policy is **authorization on a self-reported manifest** — a defense-in-depth layer, not a sandbox. A party with the signing key can lie about what capabilities the code uses. The node admission gate proves:

- The artifact was signed by the expected entity (Phase 4 ed25519 signature).
- The declared capability set has not been tampered with in transit (BLAKE3 tamper-check).
- The declared capabilities are within a static policy envelope (subsumption check).

It does **not** prove that the code actually *uses* only those capabilities — only that the manifest claims it does, and the claim is signed and untampered. Runtime enforcement via `cap no_panic`, `cap no_alloc`, FFI sandboxing, or OS-level confinement can provide stronger guarantees. For most deployments, the combination of compile-time capability verification + signed manifests + policy gates is sufficient.

---

## See also

- [Capabilities]({{ site.baseurl }}/docs/capabilities/) — where capabilities are
  defined and declared; this page enforces what that page declares.
- [Capability Audit]({{ site.baseurl }}/docs/capability-audit/) — `forge audit`
  and `forge cap inspect`, which *read* what a binary holds; the mechanisms here
  *enforce* what it may do.
- [Safety by Construction]({{ site.baseurl }}/docs/safety-by-construction/) — how
  capabilities sit alongside the other safety axes.
</content>
</invoke>
