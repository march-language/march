# Observe `SOURCE`: follow-ups to R10

R10 ([`progress/2026-10-11-observe-r10-which-source.md`](../progress/2026-10-11-observe-r10-which-source.md))
left these open.

- **`forge observe --which NAME` / `--source NAME`.** `SOURCE` is signed, so only
  hand-built requests and `Recon.source` reach it today. `forge observe` already
  signs `STATE` and `CRASHES_FULL`; `SOURCE` is one more `debug_request` case
  (`forge/lib/cmd_observe.ml`).
- **Source through the cluster control API.** `Cluster_deploy` uploads artifacts
  with `CAS_PUT` only for a hash a staged release names, so `kind:source` is
  refused there. A release could carry the texts of its functions.
- **`gc` for `sources/`.** `Cas.gc` walks `objects/` and `artifacts-v2/`; the
  source files are left alone. They are small and keyed by slot function, but
  they grow with every edit.
- **Baseline source on a node built elsewhere.** A node gets its baseline's text
  only from the build host's `~/.march/cas` or, after the first deploy that
  replaces it, from the upload. `forge deploy hot` could upload the baseline's
  text for functions it does not change when the node lacks it.
