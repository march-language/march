# CI: apt mirror fallback for an ubuntu.com DNS outage — DONE (2026-11-11)

On 2026-11-11 Canonical's authoritative nameservers (`ns1`-`ns3.canonical.com`) were
unreachable for several hours. Every Linux CI job timed out in "Set up toolchain":
`ocaml/setup-ocaml`'s own `apt-get install` (and ours after it) spent about a minute per
package on "Temporary failure resolving 'azure.archive.ubuntu.com'" until the job's 30-40
minute limit. All three hosts in the runner image's `/etc/apt/apt-mirrors.txt` are under
ubuntu.com, so apt's built-in mirror fallback could not help. macOS jobs were unaffected.

- `.github/actions/apt-mirror-fallback/` (composite action + `apt-mirror-fallback.sh`): on
  Linux, if the first configured mirror host does not resolve (three tries), try mirrors
  outside ubuntu.com in order (amd64: kernel.org, Princeton, MIT; arm64 `ubuntu-ports`: MIT,
  Waterloo, Berkeley). A mirror is taken only when it answers and a full package-list refresh
  from it finishes inside 240 s; one that stalls is skipped (MIT's ports mirror stalled once
  during the outage). If none works, the image's files are put back and the job carries on
  as before. While the default mirror resolves the step is a no-op (one `getent`).
- Called first in `.github/actions/opam-deps` (so before `setup-ocaml`), which covers every
  `march-setup` job, and before the four `apt-get install` steps in `ci.yml` jobs that use
  neither (cross-linux-oracle, determinism, property-tests, property-oracle).
- Mirrors are plain `http`: apt verifies the archive by signature, and it keeps the step
  independent of the runner's certificate store.
- Tested against the live outage in `ubuntu:24.04` containers shaped like the runner image
  (amd64 with `mirror+file:`; arm64 with direct `ports.ubuntu.com` URIs): install failed
  before, succeeded after; the no-op path leaves both files untouched. On a real runner the
  fallback path was taken once with `APT_MIRROR_FALLBACK_FORCE=1` on this PR's first commit.
