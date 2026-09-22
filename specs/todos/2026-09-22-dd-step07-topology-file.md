# `[P2]` Distributed deploys, build step 7: the topology file, static only

**Parent:** [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md), section 4, II.6, D6, D7, D18, D22, D25, D26. Groundwork done:
G4 (TOML line numbers, unknown-key warnings,
`specs/progress/2026-09-22-forge-toml-positions-no-silent-drops.md`), G5
(`Project.entry`).

**What.** `topology.toml` and `topology.<env>.toml` overlays (deep-merge tables,
replace arrays), digested to `.forge/topology.json` (`version: 1`); pools,
`serves`/`initiates`, `public` ports, placement-rule syntax; derived `caps` and
`initiates` (D22) with widening through `--grant-cap` (D26); the unlabelled-step
warning (D25); `forge topology check` (run by `forge build`/`run`/`deploy`), `export`,
`gen` (systemd, ufw, do-firewall, compose; `forge-topology-<target>` on PATH); LSP
support for the TOML. Unknown keys in topology sections are **errors** from day one,
using `Toml.check_keys` and the `_at` accessors.

**Acceptance.** `forge topology check` reports `topology.toml:<line>: unknown key
'...'`, an unbound served role, an `on` label no host has, and `count` above the host
count; `export` round-trips; each built-in generator has a golden test.
