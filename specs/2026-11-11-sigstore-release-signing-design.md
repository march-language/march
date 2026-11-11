# Sigstore signing of release artifacts: design note

Date: 2026-11-11. Status: design, for owner review. No code in this change.

Package P3 of the pre-1.0 execution plan (`specs/plans/2026-11-11-pre-1.0-execution-plan.md`).
It implements decision 9 of `specs/plans/2026-09-28-road-to-1.0.md`:

> Sigstore keyless (GitHub OIDC in CI). The Sigstore bundle (signature, certificate,
> transparency-log proof) ships next to each artifact; `install.sh` and forge verify it offline
> against the pinned workflow identity.

Lines marked **Owner check** are my calls, not settled facts. They are collected in section 12.

Sizes use the plan's scale: S is days, M is about a week, L is several weeks.

## 1. Summary

- **Sign** in the `publish` job of `release.yml` and `nightly.yml` with `cosign sign-blob`. Sign
  each archive, the checksums file and `install.sh`. Upload `<file>.sigstore.json` next to each.
  Size S.
- **Verify in forge** with a new, small OCaml library (`lib/sigstore/`). It needs one new
  dependency for ECDSA P-256 and P-384. Everything else it needs is already in the tree. Size L.
  This is the part that can grow.
- **Verify in `install.sh`** in three tiers: an already installed forge, then `cosign` if it is on
  PATH, then a small static verifier binary that `install.sh` downloads and checks against a
  SHA-256 written into the script. Size M, after the forge verifier exists.
- **Offline** means no call to any Sigstore service at verify time. The trusted root is a
  snapshot of Sigstore's `trusted_root.json`, compiled into forge and into the verifier binary.
- **Recommended staging**: sign first (stage 1), then forge (stage 2), then `install.sh`
  (stage 3), then the Rekor v2 and timestamp path (stage 4). Section 9 says what each stage
  leaves weak.

The total is one S, one L and two M. If the owner wants less before 1.0, the cut that costs
least is stage 3; sections 8 and 9 say why.

## 2. What exists today

Read from the tree on 2026-11-11.

- `build.yml` is a reusable workflow. Its matrix builds `march-<version>-<platform>.tar.gz` for
  `darwin-arm64`, `linux-x86_64` and `linux-aarch64`. A `checksums` job writes
  `march-<version>-checksums.txt` (`sha256sum` format).
- `release.yml` runs on a `v*` tag push. It calls `build.yml`, then its `publish` job uploads
  `artifacts/*` and `install.sh` to the GitHub release. It also has a `workflow_dispatch` path
  that rebuilds an existing release and replaces its assets in place.
- `nightly.yml` runs on a schedule on `main`. It calls `build.yml`, then its `publish` job
  creates a `nightly-YYYYMMDD` release with the archives, the checksums, a manifest and
  `install.sh`.
- `install.sh` and `forge toolchain install` (`forge/lib/toolchain.ml`) both download the archive
  and the checksums file from the same release and compare SHA-256. Both fail closed when the
  checksums file is missing or does not match.
- No workflow requests `id-token: write`. Nothing signs.

The checksum protects against a corrupted download. It does not protect against anyone who can
change release assets, because the archive and its checksum sit side by side.

Crypto already in the repo:

| Primitive | Where | Usable from forge |
|---|---|---|
| SHA-256, SHA-384, SHA-512 | `digestif` (opam, already a forge dependency) | yes |
| Ed25519 verify | `lib/ed25519/` over `runtime/tweetnacl.c` (forge links `march_ed25519`) | yes |
| JSON | `yojson` (already a forge dependency) | yes |
| Base64 | hand-written in `lib/ed25519/ed25519.ml` | yes |
| ECDSA P-256, P-384 | none | **no** |
| X.509 or ASN.1 DER parsing | none in OCaml. The runtime's TLS uses OpenSSL (`runtime/march_tls.c`), which forge does not link | **no** |
| RFC 3161 timestamps (CMS) | none | **no** |

So the verifier's new needs are ECDSA on two curves and a DER reader.

## 3. Signing in CI

Recommended shape. Size S.

- Add `permissions: id-token: write` to the `publish` job of `release.yml` and of `nightly.yml`.
  Only those jobs get it. `build.yml` does not.
- Install `cosign` with `sigstore/cosign-installer`, pinned by commit SHA, with a pinned cosign
  version (3.x).
- For each file `F` in the release (three archives, the checksums file, `install.sh`):
  `cosign sign-blob --yes --bundle F.sigstore.json F`.
- Upload every `F.sigstore.json` as a release asset. The name follows the Sigstore client spec's
  discovery rule (`{input}.sigstore.json`), so `cosign verify-blob` finds it without help.
- Before upload, the same job verifies each bundle with `cosign verify-blob` and with the freshly
  built forge (once stage 2 lands). A release whose signatures do not verify is not published.

**Why sign in `publish` and not in `build.yml`.** The certificate's identity is the workflow file
that contains the signing job. Signing inside the reusable `build.yml` would make every
certificate say `build.yml`, for releases and nightlies alike. Signing in the caller makes the
identity name `release.yml` or `nightly.yml` directly.

**What the bundle will contain.** The bundle is JSON, media type
`application/vnd.dev.sigstore.bundle.v0.3+json`. For a blob signed with the public instance it
holds:

- `verificationMaterial.certificate`: one leaf certificate from Fulcio (v0.3 carries the leaf
  only, not the chain). The key is an ephemeral ECDSA P-256 key.
- `verificationMaterial.tlogEntries[]`: the Rekor entry, with an inclusion proof and a signed
  checkpoint. A Rekor v1 entry also has an `inclusionPromise` (the signed entry timestamp, SET)
  and an `integratedTime`.
- `verificationMaterial.timestampVerificationData.rfc3161Timestamps[]`: optional for Rekor v1,
  required for Rekor v2, which no longer signs a time.
- `messageSignature`: the SHA-256 digest of the file and the signature over it.

**Rekor v1 or v2.** As of Sigstore's latest posts, the public instance still uses Rekor v1 by
default. Rekor v2 is in production, clients opt in with a signing config, and Sigstore has
promised a year's notice before v1 stops accepting entries. The two produce different evidence:

| | Rekor v1 | Rekor v2 |
|---|---|---|
| Log key | ECDSA P-256, one key since 2021 | Ed25519, a new key per shard, shards rotate about yearly |
| Trusted time | the log's own signed `integratedTime` | an RFC 3161 timestamp from a timestamp authority |
| Proof | SET, plus inclusion proof and checkpoint | inclusion proof and checkpoint only |

The first verifier targets Rekor v1 bundles, because that is what cosign produces by default and
it avoids the RFC 3161 parser. Stage 4 adds v2. The implementer of stage 1 must check in one real
bundle from the pinned cosign version as a fixture and confirm it matches this section, since
the facts here come from documentation, not from a signed March artifact.

**Owner check 1.** Sign `install.sh` and the checksums file as well as the archives. Decision 9
says "each artifact"; I read that as every file on the release page.

## 4. The verifier

This is the open point in the plan. Three options, then the recommendation.

### Option A: require `cosign`, fail closed. Size S.

Both installers run `cosign verify-blob --bundle ... --trusted-root ... --certificate-identity
... --certificate-oidc-issuer ...` and refuse to install without it.

- Good: no crypto code to write or maintain. cosign tracks Sigstore's format changes.
- Bad: almost no first-time user has cosign. The default `curl | sh` install would fail for most
  people, and the fix they would learn is the bypass flag. A check that most users bypass does
  not protect them.
- Bad: forge's automatic install of a pinned toolchain (`Toolchain.ensure_installed`, which runs
  inside `forge build`) would start failing on machines without cosign.

Rejected as the end state. Kept as one tier inside `install.sh` and as the documented manual
check.

### Option B: verify in forge only; `install.sh` checks the checksum. Size L (the forge verifier), nothing for the script.

`install.sh` stays as it is. After install, forge can confirm the bundle.

- Bad: forge is inside the archive being checked. An attacker who replaces the archive replaces
  forge. A check run by the thing under test proves nothing about a hostile archive. It only
  works for upgrades, where an older trusted forge does the checking.
- Good: it is honest about upgrades, and it is the smallest thing that gives forge users real
  verification.

Rejected as the end state for `install.sh`, because it gives a first install nothing. Its forge
half is kept: that is stage 2.

### Option C: implement bundle verification in forge. Size L.

A library with no forge dependencies, `lib/sigstore/`, used by `forge toolchain install`, by a
new `forge toolchain verify FILE`, and by the standalone verifier of section 4.2.

**Recommended.** It is the only option where a user with nothing but March installed gets the
check by default.

#### 4.1 What must be verified

This follows the Sigstore client spec's verification section. Inputs: the file, its bundle, the
trusted root, and the expected identity and issuer. Any failed step refuses the file.

1. **Parse the bundle.** Accept media type `application/vnd.dev.sigstore.bundle.v0.3+json` only.
   Require a single `certificate`, a `messageSignature`, and at least one `tlogEntries` item.
   Reject DSSE bundles and public-key bundles: March does not produce them.
2. **Establish the signing time.** From a Rekor v1 entry: verify the SET (ECDSA P-256 with
   SHA-256 over the canonical JSON of `body`, `integratedTime`, `logID`, `logIndex`) with the log
   key from the trusted root whose `logId` matches, then take `integratedTime`. From stage 4: an
   RFC 3161 timestamp over the signature bytes, verified to a timestamp authority in the trusted
   root. At least one verified time is required. The machine's clock is never used.
3. **Certificate chain.** Verify the leaf's signature with a Fulcio intermediate from the trusted
   root, and the intermediate with its root (both ECDSA P-384 with SHA-384 today). Check each
   certificate is valid at the signing time, and that the trusted-root entry's `validFor` window
   contains the signing time. Check the leaf is an end-entity certificate with the code-signing
   extended key usage.
4. **SCT.** Extract the embedded signed certificate timestamp, rebuild the precertificate bytes
   (the leaf's TBS with the SCT extension removed), and verify the SCT (ECDSA P-256 with SHA-256,
   RFC 6962 section 3.2) with a CT log key from the trusted root. This proves Fulcio logged the
   certificate.
5. **Identity.** The leaf's Subject Alternative Name URI must equal the expected identity
   exactly. The issuer extension (OID `1.3.6.1.4.1.57264.1.8`, a DER UTF8String) must equal the
   expected issuer exactly. Section 6 gives the strings.
6. **Log entry matches.** Decode the entry's `body`. It must be a `hashedrekord` of a supported
   version. Its signature must equal the bundle's signature, its certificate must equal the
   bundle's leaf, and its digest must equal the file's SHA-256.
7. **Inclusion.** Recompute the Merkle root from the entry's leaf hash and the inclusion proof
   (RFC 6962 audit path, SHA-256). It must equal the root hash in the checkpoint. Verify the
   checkpoint's signature (a signed note: ECDSA P-256 for Rekor v1, Ed25519 for v2) with the log
   key from the trusted root.
8. **Artifact signature.** Hash the file with SHA-256. It must equal the bundle's
   `messageDigest`. Verify the signature (ECDSA P-256 with SHA-256) with the leaf's public key.

What this does not do: it does not ask Rekor or the CT log anything, so it cannot see a log that
shows different contents to different people. Catching that is the job of log monitors and
witnesses, not of an installer.

#### 4.2 What it takes to build

| Piece | New code | Notes |
|---|---|---|
| Bundle and trusted-root JSON | small | `yojson` |
| DER reader and an X.509 subset | medium | TBS, validity, public key, SAN, the Fulcio OIDs, the SCT list, key usage. Written by hand, read-only, strict |
| ECDSA P-256 and P-384 verify | **new dependency** | see below |
| Chain check | small | the intermediates are in the trusted root, so there is no path building |
| SCT check | small but fiddly | re-encoding the TBS without one extension |
| SET, entry body, Merkle proof, checkpoint | small | SHA-256 and string handling |
| Ed25519 checkpoint (Rekor v2) | none | `lib/ed25519` |
| RFC 3161 timestamp (stage 4) | medium | CMS SignedData, TSTInfo, the authority's chain. The largest single parser |

My estimate is 1,500 to 2,200 lines of OCaml with tests for stages 2 and 4 together. Stage 4 is
about a quarter of that.

**The ECDSA dependency.** Options:

- **`mirage-crypto-ec`** (recommended). OCaml with generated C for the field arithmetic. No
  system library, so it links into the static musl builds unchanged. It brings in `eqaf`,
  `mirage-crypto` and `mirage-crypto-rng` (which brings `logs` and `duration`).
- **The `x509` opam package.** Rejected. It depends on `mirage-crypto-pk`, which needs `zarith`
  and so GMP: a new native library to link statically on three platforms. It also does not check
  SCTs or RFC 3161 timestamps, so it would not remove the hard parts.
- **Link OpenSSL's libcrypto into forge.** Rejected. It would do the chain, the ECDSA and the
  timestamp check, and the Alpine build already installs `openssl-libs-static`. But macOS has no
  static system OpenSSL, the last release problem of that kind was the Homebrew `libblake3`
  path, and it adds a large C surface to a tool that today has none of it.
- **Vendor a small C ECDSA** next to `tweetnacl.c`. Possible, and it matches how Ed25519 got
  here. Rejected for now because nothing as small and as reviewed as TweetNaCl covers P-384.

**Owner check 2.** Adding `mirage-crypto-ec` to the compiler's opam dependencies.

**A conformance check.** Sigstore publishes `sigstore-conformance`, a test suite that drives a
client through a small command-line protocol with good and bad bundles. The verifier should pass
its verification half. That is the main guard against a hand-written verifier that accepts
something it should not.

#### 4.3 `install.sh`

A shell script cannot do the eight steps. It can decide who does. In order:

1. **An installed forge** that has `forge toolchain verify`. This is the upgrade path, and it is
   as strong as forge's own check.
2. **`cosign` on PATH.** `install.sh` writes its embedded trusted root to a temp file and runs
   `cosign verify-blob FILE --bundle FILE.sigstore.json --trusted-root ROOT
   --certificate-identity ID --certificate-oidc-issuer ISSUER`. With `--trusted-root`, cosign
   does not fetch the root over the network.
3. **A bootstrap verifier.** `march-verify` is a static binary built from `lib/sigstore/` alone,
   a few megabytes, published as a release asset per platform. `install.sh` carries the SHA-256
   of each platform's `march-verify` from an earlier release. It downloads that binary, checks
   the hash, and runs it on the archive and its bundle.

If none of the three works, `install.sh` stops with an error. It does not fall back to the
checksum.

Tier 3 is what makes a first install verify with no tools the user must install first. Its cost
is one more build target per platform and one line in the release ritual (update the pinned
hashes after a release). The hashes point at a previous release, so there is no circular step
inside one release run.

Rejected for `install.sh`:

- **Verifying with `openssl` on the command line.** It can check the chain, the identity and the
  artifact signature. It cannot check the SCT or the log entry in portable shell, and the flags
  differ between OpenSSL and the LibreSSL that macOS ships. It would be a partial check that
  looks like a full one.
- **Downloading cosign itself, pinned by hash.** It works, but cosign is far larger than the
  verifier binary, and it makes a third-party release a hard dependency of every install.

**Owner check 3.** The bootstrap verifier (tier 3). Without it, a first install on a machine
with no cosign either fails or is unverified; section 9 covers that choice.

## 5. What "offline" means

**Definition.** At verify time the installer contacts GitHub for the archive and the bundle and
nothing else. It makes no request to Fulcio, Rekor, the CT log, the timestamp authority or
Sigstore's TUF repository. It does not read the machine's clock for any trust decision.

**Where the trusted root comes from.** Sigstore publishes one file, `trusted_root.json`, through
its TUF repository (`sigstore/root-signing`). On 2026-11-11 it lists:

| Service | Entries | Key type |
|---|---|---|
| Fulcio (`certificateAuthorities`) | an old chain that ended in 2022, and the current root plus intermediate, valid from 2022-04 | ECDSA P-384 |
| Rekor (`tlogs`) | `rekor.sigstore.dev`, valid from 2021-01, and `log2025-1.rekor.sigstore.dev`, valid from 2025-09 | ECDSA P-256, and Ed25519 for the v2 shard |
| CT logs (`ctlogs`) | a 2021 test log that ended in 2022, and the 2022 log | ECDSA P-256 |
| Timestamp authority (`timestampAuthorities`) | `timestamp.sigstore.dev`, valid from 2025-07 | ECDSA P-384 chain |

**How it is pinned.** A copy lives in the repository at `lib/sigstore/trusted_root.json`. It is
compiled into forge and `march-verify` as a string, and embedded in `install.sh` for the cosign
tier. Changing it is a reviewed commit. The copy is fetched with a real TUF client (cosign or
`sigstore-go`), never with a plain `curl` of the file.

**How it is refreshed.** A scheduled CI job fetches the current root through TUF and compares it
with the pinned copy. If they differ, the job fails and names the difference, and a person
updates the copy. Sigstore adds a new key to the root before it starts using that key, so a
weekly check gives time to ship a release that knows the new key.

**What happens when Sigstore rotates.** Two cases.

- **Old signatures after a rotation.** Nothing breaks. An old key stays in the root with an end
  date, and a bundle is checked against the keys that were valid at its signing time. A release
  signed today still verifies in ten years with today's root.
- **New signatures, old verifier.** This is the real problem. A forge built before a rotation
  does not know the new key. It cannot verify a release signed after the rotation, so
  `forge toolchain install` and `forge upgrade` for that release fail closed. With Rekor v1 this
  is rare: its key has not changed since 2021 and the Fulcio chain dates from 2022. With Rekor
  v2 it becomes routine, because each yearly shard has its own key.

For the second case the note recommends, for 1.0:

- A clear error: which key was unknown, and the two ways out.
- Way out 1: run the current `install.sh` again. It carries a current root.
- Way out 2: `forge toolchain install --trusted-root FILE`, with a root the user fetched and
  trusts. The flag replaces the compiled-in root for that one command.

Rejected for 1.0: **a TUF client in forge**. It is the standard answer and it removes the stale
verifier problem, but it means more signature formats, threshold and expiry rules, and a root
chain to walk. It also makes a normal install depend on a network fetch from Sigstore, which
decision 9 excludes. It can be added after 1.0 as an opt-in refresh.

Also considered, not recommended yet: **a root update signed by March's own release workflow**,
published with each release, which an old forge accepts if it verifies under the root it already
has. It works only for updates signed while the old keys were still in use, so an old forge would
have to walk forward through releases. That is a design of its own.

**Owner check 4.** Accepting that a forge older than a Sigstore key rotation cannot verify newer
releases without one of the two ways out.

## 6. The pinned identity

Fulcio writes the GitHub token's `job_workflow_ref` into the certificate's Subject Alternative
Name as a URI, and the token's issuer into extension `1.3.6.1.4.1.57264.1.8`.

**Issuer**, for both kinds of release:

```
https://token.actions.githubusercontent.com
```

**Release, tag `vX.Y.Z`** (SAN, exact match, with the tag being installed substituted):

```
https://github.com/march-language/march/.github/workflows/release.yml@refs/tags/vX.Y.Z
```

**Nightly** (SAN, exact match):

```
https://github.com/march-language/march/.github/workflows/nightly.yml@refs/heads/main
```

Rules for the verifier:

- A tag that starts with `v` is checked against the release identity for that exact tag. A
  bundle signed for `v1.0.0` does not verify an install of `v1.0.1`. This stops an attacker from
  serving an old signed release under a new tag.
- A tag that starts with `nightly-` is checked against the nightly identity.
- No pattern matching inside forge. The human-facing docs may show
  `--certificate-identity-regexp` for the "latest" case, where the reader does not know the tag.

These strings hold only if signing happens in the `publish` jobs (section 3). They are derived
from Fulcio's documented mapping. Stage 1 must print the certificate of the first signed nightly
and confirm them before any verifier pins them.

**Things the identity does not prove, which the owner should know:**

- **Anyone who can push a `v*` tag can mint the release identity.** The workflow file that runs
  is the one at the tagged commit. The identity says "a file named `release.yml`, in this
  repository, at this tag". It does not say the file is the one on `main`. A tag ruleset that
  limits who can create `v*` tags is part of this design, not an extra.
- **The rebuild path stops working for signed releases.** `release.yml`'s `workflow_dispatch`
  path runs from a branch, so its certificate says `release.yml@refs/heads/main`. That does not
  match the tag identity, and it must not: otherwise any dispatch could re-sign any release. So
  once a release is signed, its archives cannot be replaced in place. A packaging fix becomes a
  new patch release.
- **A nightly's identity does not name its date.** All nightlies share one identity, so an old
  signed nightly could be served under a newer nightly tag. The attacker needs control of the
  release assets and gains only a rollback to another genuine nightly. A cheap guard: the signing
  time in the bundle must be within two days of the date in the tag.
- **The organisation name is a string.** If `march-language` were ever renamed and the old name
  taken by someone else, they could mint a matching SAN. The certificate also carries the
  repository's numeric id (extension `.1.15`) and the owner's (`.1.17`). Checking those too
  closes this.

**Owner check 5.** Retiring the in-place rebuild path for signed releases.
**Owner check 6.** Adding a tag ruleset for `v*`.
**Owner check 7.** Whether to add the nightly date guard and the numeric id check now or later.
Both are a few lines once the certificate parser exists.

## 7. Failure behaviour

Both installers, same rules.

| Situation | Result |
|---|---|
| Bundle present, every step passes | install |
| Bundle present, any step fails | error, nothing installed, **no flag overrides this** |
| Bundle missing, release is at or after the first signed version | error, nothing installed, **no flag overrides this** |
| Bundle missing, release is older than the first signed version | error by default; installs with the unsigned flag, checksum still required, with a warning on every run |
| Unknown key in the trusted root (section 5) | error naming the key and the two ways out |
| `install.sh` finds no verifier (stage 3 not shipped yet) | see section 9 |

**The first signed version** is a constant compiled into forge and written into `install.sh`:
the first stable tag and the first nightly date that carry bundles. It is what stops an attacker
from deleting the bundle and calling the release "old".

**The flag.**

- forge: `forge toolchain install --allow-unsigned TAG`.
- `install.sh`: `MARCH_ALLOW_UNSIGNED=1`, an environment variable because the script is usually
  piped into `sh`.
- forge also reads `MARCH_ALLOW_UNSIGNED=1`. This matters for `Toolchain.ensure_installed`: a
  project whose `.march-version` pins an old release triggers an install from inside
  `forge build`, where there is no place to pass a flag. Without the variable, the error says
  which release is unsigned and names the variable.

The flag never applies to a release at or after the first signed version. A user who truly needs
to bypass a bad bundle can download and unpack the archive by hand; the tools will not help.

Errors say what failed in plain words: which file, which check, and the expected and actual
identity when the identity is what differed.

**Owner check 8.** No override at all for a bad or missing bundle on a signed release.

## 8. Bootstrapping: what verifies `install.sh`

Nothing verifies `install.sh` when it is piped from `curl` into `sh`. The user trusts TLS and
GitHub for that one file. Anyone who can replace release assets can replace `install.sh` with a
copy that skips every check. No design inside the script can fix this, and the note does not
pretend to.

What the design does give:

- **`install.sh` is signed like any other asset.** `install.sh.sigstore.json` sits next to it. A
  careful user downloads both, runs `cosign verify-blob` with the identity from section 6, then
  runs the script. The install docs show the three commands.
- **Checks inside `install.sh` are worth having when the script came from somewhere better than
  the release page**: a copy vendored into a Dockerfile, one pinned by hash in a build system,
  one a packager reviewed. In those cases the script is trusted, the archive is not, and the
  script's verification does real work.
- **forge does not have this problem.** A forge that is already installed carries its own root
  and identity. For `forge toolchain install` and `forge upgrade` the check is complete. This is
  why the forge verifier comes before the `install.sh` work.

So the honest ranking of the two installers is: forge's check is strong; `install.sh`'s check is
as strong as the way the user got `install.sh`.

## 9. Staging

| Stage | What ships | Size | What is still weak after it |
|---|---|---|---|
| 1 | Signing in both `publish` jobs; bundles uploaded; CI verifies with cosign before publishing; docs for checking by hand; real bundle fixtures checked in | S | Installers check nothing new. Only users who run cosign by hand are protected |
| 2 | `lib/sigstore/` for Rekor v1 bundles; `forge toolchain install` and `forge upgrade` fail closed; `forge toolchain verify`; the first-signed-version floor; the root freshness job | L | `install.sh` still checks the checksum only |
| 3 | `install.sh` tiers: installed forge, cosign, `march-verify`; fail closed | M | The limits in section 8, which are permanent |
| 4 | Rekor v2 entries and RFC 3161 timestamps in the verifier | M | The stale-verifier problem of section 5 becomes yearly |

**Order.** 1, 2, 3, 4. Stage 1 is useful alone and is needed to get real fixtures for stage 2.

**Stage 4 has an outside deadline.** It must ship before Rekor v1 stops taking entries. Sigstore
has promised a year's notice and has not given it. If cosign's default moves to v2 before 1.0,
either pin the signing config to v1 in CI or pull stage 4 forward.

**If the package has to shrink before 1.0**, in the order I would cut:

1. Cut stage 3. `install.sh` uses forge or cosign when present and otherwise installs on the
   checksum alone, printing that the signature was not checked and how to check it. This is the
   fallback the execution plan's risk section describes. It weakens decision 9: a first install
   through `install.sh` is unverified on most machines. Given section 8, the real loss is
   smaller than it sounds, which is why this is the first cut.
2. Cut stage 4, on the condition above about Rekor v1.
3. Cut stage 2 as well, leaving signing and cosign-only checks in both installers. I would not
   ship 1.0 this way and call decision 9 met. forge would verify only where cosign is installed.

**During stage 1 and 2**, before stage 3, `install.sh` behaves as in cut 1.

**Owner check 9.** Whether 1.0 needs stage 3, or whether cut 1 is acceptable for 1.0 with stage 3
in 1.x.

## 10. Testing

The bar: CI must show a tampered archive being refused, by both installers, and the test must be
seen to fail when the check is removed.

**Unit tests for `lib/sigstore/`** (run on every PR, no network, no clock):

- Real fixtures: a file, its bundle and the trusted root of that day, captured once from a CI
  run. Because the signing time comes from the bundle, these verify forever.
- Each of these must be refused, with the expected error:
  - one byte of the file changed;
  - the bundle of a different file;
  - a real bundle from a different identity (signed by a pull-request workflow in this
    repository), presented as a release;
  - a release bundle presented for a different tag;
  - a nightly bundle presented as a release;
  - the SET changed, the inclusion proof changed, the checkpoint signature changed;
  - the certificate swapped for another valid Fulcio certificate;
  - a trusted root that lacks the log key, the CT key or the Fulcio chain;
  - an unknown media type, a DSSE bundle, a truncated bundle.
- A private test hierarchy (a test CA, a test log key, a test CT key, generated by a script and
  checked in with its trusted root) for the cases a real bundle cannot provide: a certificate
  outside its validity at the signing time, a missing SCT, a wrong extended key usage, a wrong
  issuer extension with the right SAN.
- `sigstore-conformance`, verification half.

**End-to-end, in the `publish` jobs, before anything is uploaded** (nightly gives a daily run
with a real identity):

1. Verify every archive with cosign and with the freshly built forge. Both must pass.
2. Append one byte to a copy of an archive. Both must refuse it.
3. Swap the bundles of two archives. Both must refuse.
4. Remove a bundle. forge must refuse.

**End-to-end for the installers** (on PRs, with fixtures served from a local directory):

- Serve a tampered archive together with a checksums file recomputed to match it, so the
  checksum passes and only the signature can catch it. Run `install.sh` and
  `forge toolchain install` against it. Each must exit non-zero and leave nothing under
  `versions/`.
- The same with the bundle removed, and with an old-version tag plus and minus the unsigned flag.
- This needs a way to point both installers at a local base URL. Today the GitHub URLs are fixed
  in both. The override changes where files are fetched from and nothing else: the identity and
  root stay compiled in.

**Proving the tests can fail.** Before the suite is trusted, run it once against a verifier with
step 8 stubbed to succeed and once with step 5 stubbed, and record that it goes red. This repo
has shipped checks that could not fail (see "Refactor oracles" in `CLAUDE.md`).

**The execution plan's done-condition** is then checkable: a release candidate's archives verify
with the published identity, and a modified archive is refused by both installers.

## 11. Relation to other signing work

- **`specs/todos/2026-08-03-forge-wide-artifact-signing.md`** (ed25519 signing of artifacts that
  forge builds) stays separate. It signs what users build, with keys users hold. This note signs
  what the March project ships, with no long-lived key. The only shared code is `lib/ed25519`,
  which stage 4 uses for Rekor v2 checkpoints.
- **The hot-reload deploy key** (`--signing-pubkey`, `runtime/march_sig.h`) is unrelated.
- **Registry notarization** follows this package and can reuse `lib/sigstore/`. It is capability
  work and is not planned here.
- **GitHub artifact attestations** (`actions/attest-build-provenance`, checked with
  `gh attestation verify`) use the same Sigstore instance and add build provenance. They are a
  DSSE bundle stored by GitHub, not next to the artifact, and verifying them offline means the
  DSSE path this note leaves out. They could be added beside this design later. They do not
  replace it.

## 12. Owner checks, collected

1. Sign `install.sh` and the checksums file as well as the archives.
2. Add `mirage-crypto-ec` as a dependency of the compiler and forge.
3. Build and publish the `march-verify` bootstrap binary.
4. Accept that a forge older than a Sigstore key rotation needs a rerun of `install.sh` or
   `--trusted-root` to install newer releases. No TUF client in 1.0.
5. Retire the in-place rebuild path of `release.yml` for signed releases.
6. Add a tag ruleset limiting who can create `v*` tags.
7. Nightly date guard and numeric repository id check: now or later.
8. No override for a bad or missing bundle on a signed release.
9. Whether stage 3 is required for 1.0.

## 13. Sources

Checked on 2026-11-11.

- Sigstore client spec, verification section:
  <https://github.com/sigstore/architecture-docs/blob/main/client-spec.md>
- Bundle format: <https://github.com/sigstore/protobuf-specs/blob/main/protos/sigstore_bundle.proto>
- Trusted root as published: <https://github.com/sigstore/root-signing/blob/main/targets/trusted_root.json>
- Fulcio certificate extensions: <https://github.com/sigstore/fulcio/blob/main/docs/oid-info.md>
- Rekor v2 general availability: <https://blog.sigstore.dev/rekor-v2-ga/>
- Rekor v1 remains the default: <https://blog.sigstore.dev/rekor-evolution/>
- `cosign verify-blob` flags: <https://github.com/sigstore/cosign/blob/main/doc/cosign_verify-blob.md>
- Conformance suite: <https://github.com/sigstore/sigstore-conformance>

Not checked against a real artifact: the exact contents of a bundle from the cosign version CI
will pin, and the exact SAN strings. Stage 1 confirms both.
