**STATUS 2026-08-04: shipped as `forge cap deps`** — see
`specs/todos/2026-08-04-cap-deps-followups.md` for what remains (toolchain
version check, speed, wiring into `forge add`/`outdated`). Implemented against
a local reviewed baseline rather than the registry, which turned out not to be
required: dependencies arrive as source, so forge computes their capability
sets locally.

---

# forge: capability diff at dependency-upgrade time

- [ ] Once registry notarization lands (cap-audit plan Tasks 7-8: `forge publish`
  records each package version's inferred cap set against its artifact hash), surface
  **capability widenings during dependency resolution** — `forge outdated` /
  `forge add` / lockfile updates should show:

  ```
  json-parse 1.4.2 -> 1.5.0
    caps: + IO.Network   (was: pure)
  ```

  and require an explicit acknowledgment (flag or interactive confirm) before
  accepting a dep whose new version widens its cap set.

  **Why this is the highest-leverage supply-chain piece:** the binary-level gate
  (`forge cap audit --deny`) only sees the whole-program union, so a malicious dep
  hiding inside an app that already holds the widened cap is invisible there. The
  upgrade-time diff sees the *per-package* delta — which is exactly the
  xz/event-stream shape (a previously-pure library growing an effect class) at the
  moment it enters the tree, before any code runs. Data is already available at
  resolve time from the registry record; this is UI + resolver plumbing, not new
  analysis. See `specs/2026-08-03-forge-cap-audit-design.md` §4.3 (D) and the
  threat-model discussion in the design conversation.
