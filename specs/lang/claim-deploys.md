---
layout: docs
title: "Claim: Deploys & Distribution"
nav_order: 20.2
permalink: /docs/claim-deploys/
---

> Part of the March Language Reference; see [specs/lang/index.md](index.md).

# Claim: Deploys & Distribution

This is one of the four claims March 1.0 makes and treats any break of as a bug. The others
are [capabilities]({{ site.baseurl }}/docs/claim-capabilities/),
[performance]({{ site.baseurl }}/docs/claim-performance/) and
[refinement types]({{ site.baseurl }}/docs/claim-refinements/).

## The guarantee

On a [tier-1 platform]({{ site.baseurl }}/docs/platforms/), `install.sh` or
`forge toolchain install` gives you the toolchain the release published, and refuses it if
its checksum doesn't match. A project's `.march-version` and `forge.lock` pin the
toolchain and every dependency, and `forge build --frozen` refuses to build if the lockfile
would change. The same source compiled by the same compiler produces the same output,
whatever the build cache holds and whatever directory you build from.
`march --compile --static` produces a binary that needs nothing beyond the operating system
(fully static with musl on Linux; nothing outside `/usr/lib` and `/System` on macOS). And
`forge deploy` upgrades a running cluster without stopping it: each node takes the new code
as a signed release, step by step, and a release that fails a step halts instead of
spreading.

## Assumptions

- You use a tier-1 platform: darwin-arm64, linux-x86_64 or linux-aarch64.
- The checksum file itself is genuine. Today release archives are checksummed but **not
  signed**, so the checksum only proves the download matches what is on the release page,
  not who put it there. Sigstore keyless signing was decided on 2026-10-30 and is not built
  yet.
- `--static` on Linux needs a musl host (Alpine, for example); on a glibc host it is
  refused rather than producing a half-static binary.
- A hot deploy needs a base binary built with `--hot-reload`, and a change the hot path can
  carry. Some changes (the runtime, a hook, the first deploy of a build) need a restart,
  which `forge deploy` plans as its own step.

## Not claimed

- **Rollback.** A halted release is not undone. Rolling back is a new release of the
  previous version, which only you can sign. An end-to-end tested rollback is planned.
- **The first hot deploy onto a freshly built base**, when the actors' state changes: the
  node does not yet know the old state layout, so it can run new handlers on old state
  (`specs/todos/2026-10-18-hcr-first-deploy-no-schema-baseline.md`, P1, fix decided).
- **Draining before reload.** A reload does not first wait for in-flight work to finish.
- **Byte-identical release archives** across two independent builds of the same commit
  (the compiler's output is checked for determinism; the packaged toolchain is not).
- **`--target linux/<arch>-musl`** cross-compilation to a static binary (not built yet).
- **Platforms below tier 1** (see [Supported Platforms]({{ site.baseurl }}/docs/platforms/)).
- **Version compatibility of the cluster control plane between 1.x releases** is promised
  on the [Compatibility]({{ site.baseurl }}/docs/compatibility/) page, but not yet tested
  (see [Gate](#gate)).

## Gate

**Runs in CI today:**

- `build.yml` (every nightly and release) builds the three tier-1 archives, fails if a
  "static" Linux binary has dynamic dependencies or won't run in a bare container, and has
  each packaged compiler compile and run a program with only the archive's own runtime and
  standard library.
- `determinism`: every program in a fixed corpus is compiled under a cold and a warm build
  cache, from two directories, and the output must be byte-identical (a small corpus on
  pull requests, about 500 programs on `main`).
- `cross-linux-oracle`: the golden corpus cross-compiled to linux/amd64 must give
  byte-identical output to the native build.
- `two-node`: every two-process cluster scenario, with faults injected from outside,
  including hot deploys and protocol changes, against per-node expected output.
- `sanitize-gate`: AddressSanitizer over the golden corpus and the two-node scenarios.

**Planned, not built:**

- **A release built only from a commit that passed full CI.** Today `release.yml` builds
  and smoke-tests the archives but does not require the test suite to have passed on that
  commit; the full check runs only in the local release script.
- **The multi-host lab as a CI gate.** The lab (`scripts/lab/`, four memory-limited
  containers) runs locally only. The plan is for its scenarios, including a mixed-version
  one (an old agent with a new leader, and the reverse), to run on every release candidate.
- **Signed releases** (Sigstore), verified by `install.sh` and forge.
- **A tested rollback** of a bad hot deploy.
- **Test coverage on linux-aarch64.** CI builds that archive but runs no tests on it.
