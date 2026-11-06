# A second scrolling explainer: what a deploy is allowed to do

`docs/deploy-authority.md` (`/docs/deploy-authority/`, in the sidebar after "From a
Protocol to a Cluster"). Capabilities, topology and deploys, told as one dependency update
to `examples/lab_app` followed past every check that asks what the new code can reach.
About 1,700 words and 24 cards, inside the 20-minute budget the first page set
(`scripts/check-explainer-budget.py` prints the live count).

## What the page follows

`gauge`, a fixture library that formats the health reading the lab app's `Probe` writes.
Version 1.0 declares nothing; 1.1 adds `needs IO.NetConnect` and opens a socket. The
checks it meets, in page order:

1. `needs` lines: a module that uses a capability it does not declare (`cap_needs`).
2. The grant on `main`, a ceiling on the whole program (`cap_grant_exceeded`).
3. `forge deps` against the committed `forge.caps.lock`: refused, exit 1.
4. The capabilities the compiler derives for each topology pool: both pools gain
   `IO.NetConnect`, through `Probe`, which both hooks start.
5. `forge deploy hot`'s widening gate, and the same update against a pool whose `caps`
   are written in the topology (the compiler refuses the build).
6. The node's policy gate, then a short section on `--cap-sandbox`.

The dependency is deliberately used from `Probe`, which the pools' hooks call, not from a
role body. A role served through a topology file is not checked against its role grant
(`specs/todos/2026-11-05-topology-role-grant-unenforced.md`), so a story that ran through
`Work.stock` would have leaned on a check that does not fire. The page lists that gap
under "What this does not do".

## Where the numbers come from

`scripts/gen-authority-data.py` writes `docs/_data/authority.json`. It needs the compiler
and forge (`$MARCH_BIN`, `$FORGE_BIN`, or the `_build` copies) and takes about two
minutes. In a scratch directory under a private `HOME` it:

- reads `module_caps` from `march --emit-core-ast` (the squares);
- runs `march --check` on `docs/assets/explainer/authority/programs/*.march`;
- copies the lab app, `forge add`s the `gauge-1.0` fixture, replaces the one line of
  `Probe` that formats the reading with `Gauge.line(...)`, runs `forge audit --record`,
  `forge topology export --json --env lab` and `forge topology gen ufw --env lab`;
- swaps in `gauge-1.1` and runs `forge deps`, `forge deps --accept-caps`, the export
  again, `forge deploy hot --env lab` with and without `--grant-cap`, and `forge build`
  on a variant with the work pool's `caps` written down.

`examples/lab_app` itself is not changed and still has no dependency.

Two things are not measured, and the page says so in its drawer:

- **The deploy record is seeded.** `forge deploy hot` compares with
  `.forge/deploy/lab/derived.json`, which a completed deploy writes. The script deploys
  nothing, so it writes that file from the export made before the update.
- **The node's refusal is quoted.** `ERR cap_policy` is the line from the worked example
  in `docs/hot-code-reload.md`, pinned by phrase (`PINNED`): if the chapter stops saying
  it, the generator fails instead of carrying it on. Producing it from the lab app needs
  a running node with a policy, which the generator does not start.

Also general, not measured on the lab app: how a granted change travels (one signed
release to the control leader, from `docs/hot-code-reload.md`), and that it would be a hot
patch at all. `forge deploy hot` is what the generator runs because its gate fires before
any build or host is needed; a cluster with a `[control]` section deploys with
`forge deploy`, which blocks a widened pool in its plan through the same comparison
(`forge/lib/pool_caps.ml`). The page says both.

The lab was not run for this page, and nothing on it claims it was. The sandbox section
is prose from `specs/lang/capability-threat-model.md`; no sandboxed run was made.

## How it is built

It shares the first page's machinery (`docs/_includes/explainer.html`, the scroll engine,
`svgFigure`, `canvasFigure`). What is new:

- `docs/_includes/explainer.html` takes `data=` and `figures=`; with
  `figures="authority"` it also loads the four `-authority.js` scripts. No Liquid tag may
  be spelled out in that file's comment: Liquid runs inside HTML comments, and an include
  of the file from its own comment recursed until Jekyll's stack ran out.
- `figures-authority.js`: `reach`, one square per module in three groups. Every square has
  a fixed place and each group keeps one empty place for the dependency, so a card only
  recolours squares or adds that one.
- `sim-topology.js`: the simulation core (placement, sessions as message legs, a stopped
  host, the single-holder role moving after the suspect time, the patch's phases).
- `draw-authority.js`: its canvas renderer, in two densities (desk and phone) of the same
  side-by-side layout. It draws only rectangles, segments, circles and text, so the
  fallback renderer replays it into SVG.
- `chapters-authority.js`: the figures `reach`, `topology` and `rollout`. Each simulation
  card is an `enter` function and a settle time; a card's picture is every earlier card's
  `enter` run in order, and moving on to the next card runs only that card's `enter` on
  the simulation on screen. `chapters.js` gained `ME.registerSim` for this.

## Checks

- `scripts/check-explainer.sh` runs `test/explainer/authority.test.js` (26 tests: the
  squares, the simulation's rules, every card's state known to its figure, the data
  telling one story), `test/explainer/test_gen_authority.py` (16), the fallback images
  (`reach.svg`, `topology.svg`, `rollout.svg`) and the reading budget for both pages.
- doc-lint Check H also runs `gen-authority-data.py --check-inputs` (the lab app and the
  fixtures, by hash; needs no compiler).
- CI's doctest job builds forge and runs `gen-authority-data.py --check`, so a compiler
  or forge change that rewords a message or moves a count fails there.
- Looked at in the browser pane at phone width and at 700 px (one column), and at
  1300 px (two columns): all four figures mount, cards drive them, the Ledger moves when
  its machine stops, the patch stops at forge's gate. Not checked: reduced motion,
  JavaScript disabled, a timed read-through, the light theme.

## Found on the way

- A simulation in the preview pane can sit on its first card after a scroll: the pane
  pauses `requestAnimationFrame` while hidden, and the scroll observer waits on a frame.
  It is the pane, not the page; a screenshot wakes it.
