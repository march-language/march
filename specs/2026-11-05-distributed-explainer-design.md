# A scrolling explainer for distributed March: design

Date: 2026-11-05. Status: design, nothing built.

## Intent

One long-form page in the docs that sells March to a technical reader by showing how it
makes hard things in distributed computing simple. The reader should finish believing
that a short protocol declaration, checked by the compiler, gives them a running cluster
that survives node loss and can be changed without stopping.

It is a sales piece for engineers. It persuades by showing the mechanism and the
evidence, and by stating the limits next to the claims.

## The reader

- Technical. Use the real terms (linear type, projection, duality, epoch, incarnation)
  and explain the mechanism behind each.
- Background unknown. Do not argue by comparison with any particular stack. Pick
  problems every distributed system has.
- Has not read the March docs. The page must stand alone and link out for depth.

## Goals

- At most a 20-minute read, about 3,000 words and about 40 scroll cards.
- Follow one real system from a 16-line declaration to a cluster that is running,
  failing over and being redeployed.
- Walk through how the compiler turns the choreography declaration into a runnable
  program.
- Cover the actor model (where state lives) and deployment (hot code reload across the
  cluster).
- Every graphic is either the real artifact drawn to scale or a simulation with a clock
  and counts.
- Every number on the page can be reproduced by a command shown in a collapsed drawer.

## Non-goals

- Not a replacement for the reference chapters (choreography, session types, actors,
  supervision, clustering, topology, hot code reload). Link to them.
- Not a tutorial. The reader does not type anything.
- No comparison tables against other languages or frameworks.

## Anti-goals

These make the piece a failure even if it works:

- Box-and-arrow diagrams about the mechanism. A first mockup of a labelled sequence
  diagram was rejected as dull. Draw the thing itself.
- A number that was typed in by hand, or a simulation presented as a recording.
- March code on screen that looks more complicated than the problem it solves.
- Hiding a limit. If March does not do something a reader would assume, say so.
- Running past 20 minutes.

## The system the piece follows

`examples/lab_app`, the app the multi-host lab deploys (`docs/lab.md`, `scripts/lab/`).
It is real, it runs on four hosts, and it has scripted scenarios whose logs supply
measured numbers.

- Protocol `Order` (16 lines including `@[endpoints]`): roles `Shop`, `Stock`, `Ledger`;
  a loop with a `choose by Stock` between `have` and `out`.
- Topology: pool `ingress` on lab-1 initiates `Shop`; pool `work` on lab-2, lab-3, lab-4
  offers `Order.Stock` (a function, capacity 32) on every node and `Order.Ledger` (an
  actor, capacity 64) on one node labelled `books` (`count = 1`).
- Lab scenarios: `deploy`, `hot_role`, `restart_persist`, `failover`.

Do not invent a different example system. If a chapter needs something the lab app lacks,
say so rather than faking it.

## Structure

| Section | Minutes | Cards | Main graphic |
|---|---|---|---|
| Opening | 1 | 2 | The 16 lines |
| 1. What the declaration rules out | 2.5 | 5 | State map |
| 2. What the compiler makes of it | 4 | 8 | Fan-out, linear-type strip |
| 3. Inside one node: the actor | 3 | 6 | Mailbox and state |
| 4. The cluster: nodes down and up | 4 | 8 | Cluster view, detection timeline |
| 5. Deploying while it runs | 4.5 | 9 | Changed-function squares, release rollout, mailbox marker |
| Close: what March does not do | 1 | 2 | None |

The budget is exactly 20 minutes with no slack. If a draft runs long, cut in this order:
the state map (chapter 1), then the changed-function squares (chapter 5).

Each chapter has three beats: the failure as it happens in real systems, the mechanism
that rules it out, then the March code, which is short because the types do the work.

### Opening

The full `protocol Order` declaration, and the claim: these 16 lines are the only place
the conversation is written down.

### 1. What the declaration rules out

- The graphic is a grid with one cell for every combination of the three roles' local
  states. The protocol leaves a small set of cells reachable; the rest stay dark.
- Cards light the reachable cells in order, then show two or three wrong programs, each
  landing on a dark cell with the compiler's real diagnostic (a role that skips a step, an
  `offer` that misses a branch, a send out of turn).
- The cell counts must be computed from the real projection of `Order`, not estimated.
- What a cell is (the author's call): each axis is one role's position in its own local
  view of the protocol, taken from the projection, not the count of generated state types
  (some of those are tokens for parked, cancelled or drained sessions). Reachability is
  asynchronous, as the runtime is: a role may have sent before its peer has received. A
  message in flight does not get a cell of its own.
- The generator derives the projection and the reachable set itself from the step tree in
  `Order.json` (`--emit-protocols`). No new compiler dump is needed.

### 2. What the compiler makes of it

The stations, in order, as verified in the compiler source:

1. Parse: the `protocol` block is a declaration like any other.
2. Project and check: each role gets its local view; the protocol is rejected if the
   views do not fit (`lib/typecheck/typecheck_session.ml`).
3. Generate ordinary code during desugaring (`lib/desugar/desugar_endpoints.ml`): a
   message module, one module per role, a runner module. Each point in a role's
   conversation becomes its own linear type; each step becomes a function.
4. Typecheck as usual. There is no separate session checker: because each state is a
   linear type, the ordinary typechecker enforces order and exactly-once use. Errors are
   phrased in protocol terms (`lib/ast/protocol_states.ml`).
5. Generate `main` from the topology (`lib/desugar/desugar_topology.ml`): start the node,
   hand each pool its narrowed capabilities, open the offers.
6. Compile to a native binary through the normal back half. Pools that share a build
   share one binary; only an isolated pool gets its own.
7. Record the protocol's fingerprint for the next build to compare against.

Graphics:

- The fan-out: the 16 source lines (drawn as bars at their real lengths) fanning into
  five modules, each a row of squares, one square per generated linear state type and one
  per generated function.
- The linear-type strip: beside the code, one role's remaining steps with the current one
  marked, advancing as the highlighted line of code changes. This is a margin figure, not
  a main graphic.
- Two cards on grants: the `role Stock needs IO.Mut` line becoming a capability parameter
  in the generated body type.

The chapter ends with the binaries landing on the four hosts, which hands over to the
cluster view.

### 3. Inside one node: the actor

- A zoom from the cluster into one node. The ledger is an actor: one mailbox, one message
  handled at a time, a running total, and every open session parked inside it.
- The graphic is a mailbox queue feeding an actor box that shows its code version and its
  state. The parked sessions are the same slots the cluster view shows.
- Covers: no locks because one message at a time; a crash means a supervisor restarts the
  actor with clean state.
- The ledger's total is lost when the role moves: the lab app's own comment says a Ledger
  that moves to another node starts again from 0. Say so on the page.

### 4. The cluster: nodes down and up

The main graphic of the piece. Nodes drawn with their session slots; calls drawn as dots
moving from the initiating node to an offer; live counters for completed, in flight,
cancelled and refused.

Cards:

- Steady state. Each node offers a role with a capacity; a full node answers "full" and
  the caller tries the next offer.
- A Stock host crashes. Its sessions are cancelled, not resumed. Calls reroute.
- Crash versus hang. A closed connection is noticed at once. A hung host is noticed by
  the cluster node's own failure detector (SWIM): a missed probe, then a suspect timeout,
  then it is declared dead and its sessions are cancelled. The detection timeline is
  drawn to scale. (Corrected after review: an earlier draft said "session heartbeat",
  which applies to the direct runner only, not to cluster nodes.)
- The Ledger host stops. Failover of a `count = 1` role to the other `books` host.
- The node returns as a new incarnation and offers again; no other node coordinates it.
  It does not count for placement until a settle period has passed; after that, if it
  still ranks first, a single-holder role returns to it.
- No node can take a role: the caller gets `NoOffer`.

### 5. Deploying while it runs

Uses the lab's `hot_role` change: one edit to the Stock reply.

- Changed-function squares: every function in the binary as one square, with the changed
  ones marked. Only functions whose compiled body hash changed are uploaded and signed.
- Release rollout on the cluster view: forge builds and signs one release on the
  developer's machine; it goes to any control-plane candidate, which passes it to the
  leader; step 1 is a canary node gated on staying healthy; step 2 is the rest. Calls
  keep flowing throughout, with counters for replies from old code, replies from new
  code, and failed sessions.
- A second replay where the canary fails its gate: the release halts, the other nodes
  keep the old code, nothing is rolled back.
- Mailbox marker: inside one node, the deploy lands as a marker in the mailbox. Messages
  ahead of it finish on the old code against the old state; the state is migrated once;
  everything after runs on the new code.
- One card on what a hot patch cannot replace: `main`, the generated protocol modules and
  the standard library need a restart, which forge plans as its own step.
- A collapsed drawer on changing the protocol itself (fingerprints, compatible versus
  breaking changes, rollout order), linking to the choreography chapter.
- The rollout counters include sessions ended early at a loop boundary (drained), beside
  old-code replies, new-code replies and failed sessions. A hot deploy drains in-flight
  sessions, and the lab app's ingress counts them and does not restart them. Showing this
  is the author's call, under the rule against hiding a limit.

What the lab app does today differs from the cards above in three ways. The requester
decided to extend the lab app so the cards are real; see "Decisions on evidence and the
deploy story".

- The lab deploys with no canary. Forge's default is one step for every host with no gate;
  with `--canary N` the window defaults to 30 s. Only the two-node scenario
  `control_forge_deploy` exercises a canary, and no scenario covers a failing one.
- The `hot_role` edit rewrites a string in a plain function. The lab app has no
  `migrate_state`, so no state migration happens.
- The only actor on a work node is the ledger, which hosts sessions. Such an actor takes
  an epoch hold: it stays on the old code until its sessions release it, then moves.

### Close: what March does not do

Stated plainly, from the existing chapters:

- A failed session is cancelled and discarded; nothing resumes it.
- There is no automatic rollback; a rollback is a new signed release.
- The network runner needs the compiled backend.
- Every role that exchanges messages needs a direct connection; there is no relaying.

## Visual language

- Black, grey, hatching and one accent colour. The accent marks the single thing to look
  at on a card (a failure, a changed function, the marker). The site theme has no such
  colour today; define one that works in both the dark and light themes.
- Quantities are in the drawing: one square per function, one slot per session, bars at
  real line lengths, time axes in real seconds.
- The pinned graphic stays in place while cards scroll past; each card changes its state.
- Code sits beside the graphic, with the line that caused the change highlighted.
- Serif-free, in the site's existing type. Monospace for code and identifiers.

## Evidence rule

- Every number comes from a command. Compiler-derived numbers are produced by a generator
  script and written to a data file the page reads; nothing is typed into prose by hand.
  `scripts/gen-error-tour.py` is the precedent for generated blocks inside a hand-written
  page.
- Lab-derived numbers (failover time, sessions failed during a rollout) come from lab
  scenario logs. The lab runs on demand, not in per-PR CI, so each such number carries
  the date and commit it was measured at.
- Simulations follow March's documented rules with parameters taken from measured data,
  and each one is labelled as a simulation. This is the author's call, not something the
  requester decided.
- Each diagnostic shown is the compiler's real output for a real program.

## Verified so far

Measured at commit `eb8819a16` with a compiler built from this tree.

| Fact | Value | How |
|---|---|---|
| `protocol Order` length | 16 lines | `examples/lab_app/src/lab_app.march` |
| Generated modules | 5: `Order_Msg`, `Order_Shop`, `Order_Stock`, `Order_Ledger`, `Order_Run` | `march --emit-core-ast` on the lab app, counting declarations in each `Order_*` module |
| Linear state types | 15 (Shop 5, Stock 6, Ledger 4) | same |
| Generated functions | 152 (18, 33, 37, 26, 38) | same |
| Fingerprint | `fbc924928c002942943a81b564d2408d` | `march --check --emit-protocols <dir>` writes `Order.json` |
| Message tags | Want, Have, Book, Booked, Out, Skip | `Order.json` |
| Failure detection on a cluster node | SWIM: probe every 1 s, 500 ms for the ack, 3 s for a suspect to refute | clustering chapter. The session heartbeat (1 s / 10 s) in the choreography chapter is the direct runner's and does not apply to cluster nodes, which the lab app uses |
| Placement settle period | 15 s before a rejoining node counts again | topology chapter (`MARCH_PLACEMENT_SETTLE_MS`) |
| Lab failover bound | SWIM suspect timeout 3 s plus a margin; 15 s settle period | `docs/lab.md`, `failover` scenario |
| Lab drain deadlines | soft 3 s, hard 8 s | `examples/lab_app/topology.toml` |
| Ledger total on a move | starts again from 0 | comment above `LedgerActor` in the lab app |
| Lab traffic | one session every 1 to 2 s, at most 16 in flight | `lab_traffic` calls in `scripts/lab/` |
| Forge canary default | 0 (one step, no gate); 30 s window with `--canary N` | `forge/lib/cmd_deploy.ml`, `forge/lib/cluster_deploy.ml` |

## State of the lab evidence

- The only recorded lab run is 2026-10-05 at commit `53d66f068`
  (`specs/progress/2026-10-05-multi-host-lab.md`). `deploy` passed; `hot_role`,
  `restart_persist` and `failover` were expected-fail.
- All three scenario files still carry expected-fail markers. The items they name have
  since moved to `specs/progress/`, and one of those fixes was checked by a two-node test,
  not by a lab run. Nobody has re-run the lab since.
- The one failover figure on record is from that run: the Ledger moved from lab-4 to lab-3
  in 1 s with no session failed. The scenario still failed: the returning lab-4 took the
  role back at once and sessions stopped. The page may quote the 1 s only with that.
- No lab scenario covers a Stock-only crash, a hung peer, a full node or `NoOffer`. The
  two-node scenarios under `test/two_node/` cover several of these with other protocols
  (`crash_before_send`, `crash_after_send`, `silent`, `session_refused`).
- At lab traffic the cluster view would be nearly empty and no node could ever be full.
  Simulations therefore run at a raised load that the page states (the author's call).

## Decisions on evidence and the deploy story

Decided by the requester on 2026-11-05, after the builder review.

1. Evidence for chapters 4 and 5: use the two-node scenarios under `test/two_node/`, which
   run in CI on every pull request, together with simulations labelled as such. Re-run the
   lab alongside and swap in its numbers wherever a scenario passes. The page is not
   blocked on the lab. Where a two-node scenario uses a protocol other than `Order`, the
   page says the evidence is for the same runtime behaviour, not for the lab app itself.
2. Chapter 5 shows the canary step, the halted release and the state migration, and they
   must be real for the system the piece follows. So the work includes extending
   `examples/lab_app` and `scripts/lab`: deploy with a canary step, add a scenario where
   the canary fails its gate, and add one actor with a state migration. The ledger's
   epoch hold (old code until its sessions drain) is shown as well, since that is what a
   session-hosting actor does.

The extension to the lab app is part of this project, not a separate one. It changes an
example and the lab scripts, so it needs its own tests and a note in `docs/lab.md`.

## To verify before the affected chapter is written

- The state-map cell counts for `Order` (chapter 1).
- Binary sizes per pool (chapter 2).
- How many functions the lab app's binary has and how many the `hot_role` edit changes
  (chapter 5); `--dump-impl-hashes` before and after the edit is the likely source.
- Whether the lab's `hot_role`, `restart_persist` and `failover` scenarios pass today.
- What one `Order` message looks like on the wire, if the protocol-change drawer shows it.

## How it gets built

These are the author's calls unless marked otherwise.

- A hand-written Jekyll page under `docs/` using the `docs` layout, with its markup in an
  include and its logic in one script under `docs/assets/`, as the error playground does.
  The site has no JavaScript build step and should not gain one.
- No dependency on the reference library. Its main branch holds only the scroll engine
  and the sticky figure, and one of its five pull requests is still open. Borrow two
  ideas from it: deciding the active step with pure functions over rectangles, and
  putting the figure and the steps in one grid cell so the figure stays pinned on phones.
- Canvas for the simulations, inline SVG for the static figures. No charting library is
  needed for the graphics as sketched.
- Simulations are deterministic (seeded) so a card always shows the same thing.
- Works at phone width, in both site themes, and with reduced motion (a simulation shows
  its end state instead of animating).
- Without JavaScript the page still reads as an article: the text, the code and a static
  image of each graphic.

Decided by the requester:

- Technical audience; keep the real terms.
- At most a 20-minute read.
- The cluster view of nodes going up and down with calls moving is in.
- The compiler walkthrough, the actor model and cluster hot code reload are in.
- Do not mention the subject of the reference piece on the page.

## Repo conventions that apply

- Add a `### Documentation` bullet under `## [Unreleased]` in `CHANGELOG.md` when the page
  lands.
- File the work as one item in `specs/todos/` and move it to `specs/progress/` when done.
- `scripts/check-docs.sh` lints pages under `docs/` for dead source pointers; every
  compiler path the page names must exist.
- `docs/pagefind/` is bot-owned; do not regenerate it in the pull request.
- Language-reference chapters under `docs/` are generated from `specs/lang/`. This page is
  hand-written and is not one of them.

## Left to the builder

- The page title, permalink and place in the navigation.
- The exact wording of every card.
- Layout details, type sizes, the accent colour.
- How the generator script is organised and how its freshness is checked.
- Whether each graphic's static fallback is an SVG or an image.

## Reference

- The reference piece: https://bobbby.online/tennis-potatoes
- Its library: https://github.com/notactuallytreyanastasio/ripped_off_nyt_infographics
- Six throwaway mockups were sketched during design (a rejected sequence diagram, a
  session simulation, the cluster view, a sheet of supporting figures, the fan-out, the
  mailbox marker, the release rollout). They were not saved; the descriptions above are
  the specification.
