---
layout: docs
title: "From a Protocol to a Cluster"
permalink: /docs/protocol-to-cluster/
published: false   # until chapter 5 lands (see the comment where it goes); preview with `jekyll serve --unpublished`
description: "Sixteen lines of protocol, followed through the compiler into a running cluster that loses nodes, recovers, and takes new code without stopping."
---

<!-- Hand-written page: the scrolling explainer for distributed March.
     Design: specs/2026-11-05-distributed-explainer-design.md.

     Every number, excerpt and diagnostic here comes from docs/_data/explainer.json
     (`site.data.explainer`), which scripts/gen-explainer-data.py writes from the real
     compiler: never type one in by hand. After changing examples/lab_app, rerun the
     generator (doc-lint Check H fails until you do).

     The page is capped at a 20-minute read: scripts/check-explainer-budget.py counts its
     words and cards. Each graphic is a `<section class="mx-scrolly" data-figure="…">`
     whose cards (`.mx-step`, `data-state`) drive a figure registered in
     docs/assets/explainer/. -->

{% include explainer.html %}
{% assign x = site.data.explainer %}

# From a Protocol to a Cluster

Getting programs on different machines to cooperate is mostly a matter of agreement.
Each side has to know whose turn it is, what the next message means, and what to do when
the other side goes quiet. That agreement usually lives in a document, a set of
integration tests and the heads of the people who wrote both ends. It holds until one end
changes, or one machine dies halfway through a conversation.

March puts the agreement in the program. You write the conversation once, the compiler
checks every participant against it, and the runtime uses the same description to
connect the machines and to end a conversation cleanly when one of them fails. This page
follows one small system from that description to a running cluster.

Three programs on four machines take orders, check stock and keep a ledger. This is
everything that says how they talk to each other:

<pre class="mx-code"><code class="language-march">{% for line in x.order.source %}{{ line | escape }}
{% endfor %}</code></pre>

It is {{ x.order.source | size }} lines, and it is the only place the conversation is
written down. The compiler reads it and produces a typed program for each of the three
roles. A role that speaks out of turn, skips a step or stops halfway does not compile.
The programs it accepts run as a cluster that loses machines and carries on, and that
takes new code while orders are still flowing.

This page follows those {{ x.order.source | size }} lines the whole way: what they rule
out, what the compiler makes of them, where the state lives, what happens when a machine
dies, and how the running system is changed. The app is real. It is
[`examples/lab_app`](https://github.com/march-language/march/tree/main/examples/lab_app),
the one the [multi-host lab]({{ site.baseurl }}/docs/lab/) deploys.

## What the declaration rules out

{% assign reach = x.state_map.reachable | size %}
Each role has its own view of the conversation: the steps it takes, in order. Shop can be
at any of {{ x.state_map.axes.Shop }} positions in its view, Stock at
{{ x.state_map.axes.Stock }} and Ledger at {{ x.state_map.axes.Ledger }}. Three programs
written by hand could be at any combination of those at the same moment.

<section class="mx-scrolly" data-figure="state-map">
<div class="mx-figure"><div class="mx-stage"><img class="mx-fallback" src="{{ site.baseurl }}/assets/explainer/fallback/state-map.svg" alt="A grid of 60 cells, one for every combination of the three roles' positions; the 14 the protocol can reach are filled."></div></div>
<div class="mx-steps">

<div class="mx-step" data-state="empty">
<p>Here is every combination: {{ x.state_map.cells }} cells, one for each way the three
positions can line up. Blocks are Shop's position, columns are Stock's, rows are Ledger's.</p>
<p>Nothing stops ordinary networked programs from reaching any of them, including the
ones where one side waits for a message the other will never send, or both sides wait.</p>
</div>

<div class="mx-step" data-state="path">
<p>The protocol reaches {{ reach }} of them. They light in the order the protocol can
first reach them, counting a role as moved once it has sent, even if its peer has not
received yet.</p>
<p>The other {{ x.state_map.cells | minus: reach }} cannot happen. A program that would
get there does not compile.</p>
</div>

<div class="mx-step" data-state="skip">
<p>Stock has the order and must now choose <code>have</code> or <code>out</code>. This
version skips the choice and tells Ledger to book.</p>
<pre><code class="language-march">{{ x.programs.skip_step.body | escape }}</code></pre>
<p class="mx-diag">{{ x.programs.skip_step.headline | escape }}</p>
<details><summary>What the compiler prints</summary><pre>{{ x.programs.skip_step.output | escape }}</pre></details>
</div>

<div class="mx-step" data-state="offer">
<p>Stock may answer <code>out</code>. This Shop handles <code>have</code> and nothing else.</p>
<pre><code class="language-march">{{ x.programs.offer_misses_branch.body | escape }}</code></pre>
<p class="mx-diag">{{ x.programs.offer_misses_branch.headline | escape }}</p>
<details><summary>What the compiler prints</summary><pre>{{ x.programs.offer_misses_branch.output | escape }}</pre></details>
</div>

<div class="mx-step" data-state="turn">
<p>Ledger confirms a booking before anyone has asked for one.</p>
<pre><code class="language-march">{{ x.programs.send_out_of_turn.body | escape }}</code></pre>
<p class="mx-diag">{{ x.programs.send_out_of_turn.headline | escape }}</p>
<details><summary>What the compiler prints</summary><pre>{{ x.programs.send_out_of_turn.output | escape }}</pre></details>
<p>Each message is in the protocol's own terms: the role, what it tried, and what it must
do at that point. The marked cell is where the program stood.</p>
</div>

</div>
</section>

None of these needed a test, a second machine or a timeout to find. The next section is
how the compiler does it.

## What the compiler makes of it

March has no separate checker for conversations. The compiler turns the declaration into
ordinary types and functions, then lets the checks it already has do the work. These are
its steps, in order.

<section class="mx-scrolly" data-figure="fan-out">
<div class="mx-figure"><div class="mx-stage"><img class="mx-fallback" src="{{ site.baseurl }}/assets/explainer/fallback/fan-out.svg" alt="The 16 lines of the Order protocol above the five modules the compiler generates from them, with a square for each state type and each function."></div></div>
<div class="mx-steps">

<div class="mx-step" data-state="source">
<p><strong>Parse.</strong> The <code>protocol</code> block is a declaration like a function
or a type. <code>@[endpoints]</code> asks for typed code to be generated from it.</p>
<p>Each bar is one of its {{ x.order.source | size }} lines, at its real length.</p>
</div>

<div class="mx-step" data-state="project">
<p><strong>Project.</strong> Each role gets its own view: only the steps it takes. Shop's
view has {{ x.order.strips.Shop | size }} steps, Stock's {{ x.order.strips.Stock | size }}
and Ledger's {{ x.order.strips.Ledger | size }}.</p>
<p>The views are checked against each other before any role is written: every message
one role sends must be one its peer is waiting to receive
(<code>lib/typecheck/typecheck_session.ml</code>).</p>
</div>

<div class="mx-step" data-state="modules">
<p><strong>Generate.</strong> While desugaring, the compiler writes
{{ x.order.modules | size }} modules of ordinary March beside yours: one for the messages
and their wire encoding, one for each role, and one that runs a role on a node
(<code>lib/desugar/desugar_endpoints.ml</code>).</p>
</div>

<div class="mx-step" data-state="functions">
<p>Every step of a role's view becomes its own <strong>linear type</strong>: a value that
must be used exactly once. There are {{ x.order.conversation_states }} of them, and
{{ x.order.linear_states | minus: x.order.conversation_states }} more for a session parked
inside an actor.</p>
<p>Every move is a function that consumes one state and returns the next. In all,
{{ x.order.functions }} functions come out of the {{ x.order.source | size }} lines.</p>
</div>

<div class="mx-step" data-state="typecheck">
<p><strong>Typecheck, as usual.</strong> Stock holds a value of type
<code>S_choose_have_out</code>. The only steps forward from it are
<code>choose_have</code> and <code>choose_out</code>. <code>send_Book</code> wants an
<code>S_send_Book</code>, and only <code>choose_have</code> returns one.</p>
<p>So order is enforced by an ordinary type mismatch, and exactly-once use by linearity.
A table kept beside the types (<code>lib/ast/protocol_states.ml</code>) lets the error
name roles and steps instead of generated types.</p>
</div>

<div class="mx-step" data-state="grants">
<p>The line <code>role Stock needs IO.Mut</code> becomes a parameter. Stock's body is
handed a capability for exactly that, and the compiler checks that everything the body
reaches fits under it.</p>
<pre><code class="language-march">{{ x.excerpts.stock_signature | escape }}</code></pre>
<p>A role with no <code>needs</code> line is handed its session and nothing else.</p>
</div>

<div class="mx-step" data-state="main">
<p><strong>Generate <code>main</code>.</strong> The lab app has none. A topology file says
which pool of machines runs which role, and from it the compiler writes the entry point:
start the node, narrow each pool's capabilities, open an offer for each role
(<code>lib/desugar/desugar_topology.ml</code>).</p>
</div>

<div class="mx-step" data-state="hosts">
<p><strong>Compile.</strong> From here it is the normal back half: typed IR, reference
counting, LLVM, a native binary. Pools that share a build run the same binary, and each
machine is told which pool it is.</p>
<p>The build also records the protocol's fingerprint,
<code>{{ x.order.fingerprint | slice: 0, 8 }}…</code>, a digest of its roles, steps and
payload types. Two nodes compare fingerprints before they exchange a message.</p>
</div>

</div>
</section>

The {{ x.order.source | size }} lines are now a typed program for each role, on
{{ x.topology.stock_hosts | size | plus: 1 }} machines. The next two sections are what
runs there.

## Inside one node: the actor

A node is one process. Inside it, the role that keeps state is an actor. This is the
head of the lab app's Ledger:

<pre class="mx-code"><code class="language-march">{{ x.excerpts.ledger_actor | escape }}</code></pre>

<section class="mx-scrolly" data-figure="mailbox">
<div class="mx-figure"><div class="mx-stage"><img class="mx-fallback" src="{{ site.baseurl }}/assets/explainer/fallback/mailbox.svg" alt="The Ledger actor: a queue of messages on the left, and on the right the actor with its running total and a square for each session parked in it."></div></div>
<div class="mx-steps">

<div class="mx-step" data-state="idle">
<p>An actor is a mailbox, a piece of state and a set of handlers. Messages for the
Ledger queue in the order they arrive.</p>
</div>

<div class="mx-step" data-state="one-at-a-time">
<p>It handles one message at a time, to the end, and the handler returns the next
state. Nothing else can touch <code>total</code>, so there is no lock to take and no
race to reason about.</p>
<p>Other actors on the node run in parallel with it.</p>
</div>

<div class="mx-step" data-state="sessions">
<p>Every open session's state lives inside this one actor, parked in a map keyed by
session. A delivery takes its session out, takes the next step of the protocol, and
parks it again.</p>
<p>The parked state is a linear type, the same kind as in the last section. The actor
cannot drop a session or use one twice by accident.</p>
</div>

<div class="mx-step" data-state="crash">
<p>If a handler hits a bug, the actor crashes. It does not try to repair itself.</p>
<p>Its mailbox and its state are gone, and the sessions parked in it are cancelled.
Messages sent to it meanwhile are dropped.</p>
</div>

<div class="mx-step" data-state="restart">
<p>The node's generated <code>main</code> watches the actors that host roles. When one
dies it opens the offer again with a fresh actor, and the next session finds it. No
other node is involved.</p>
</div>

<div class="mx-step" data-state="lost-total">
<p>The fresh actor starts from <code>init</code>, so the total is back at 0. The same
happens when the Ledger moves to another machine; the app's own comment says so.</p>
<p>State that must outlive its actor has to be stored outside it. March does not do
that for you.</p>
</div>

</div>
</section>

More on both halves of this: [Actors]({{ site.baseurl }}/docs/actors/) and
[Supervision Trees]({{ site.baseurl }}/docs/supervision/).

## The cluster: nodes down and up

{{ x.topology.ingress }} starts a Shop session for each order.
{{ x.topology.stock_hosts | join: ", " }} each <em>offer</em> the Stock role, with room
for {{ x.topology.stock_capacity }} sessions. One of
{{ x.topology.books_hosts | join: " and " }} holds the single Ledger, which has room for
{{ x.topology.ledger_capacity }} sessions. A session forms when the caller has found an
offer for every role.

What follows is a simulation. It obeys the rules March documents, at
{{ x.sim.load_per_s }} sessions a second so there is something to see; the lab itself
starts one every second or two.

<section class="mx-scrolly" data-figure="cluster">
<div class="mx-figure"><div class="mx-stage"><img class="mx-fallback" src="{{ site.baseurl }}/assets/explainer/fallback/cluster.svg" alt="Four machines: lab-1 starting sessions, and three hosts with a square per session slot. The host that held the Ledger is marked dead and the Ledger is on another host."></div></div>
<div class="mx-steps">

<div class="mx-step" data-state="steady">
<p>A dot is a session being set up or finishing. A filled square is a session in
progress: one square on the host playing Stock for it, and one on the Ledger.</p>
<p>The caller tries the hosts in turn, so the work spreads without a load balancer.</p>
</div>

<div class="mx-step" data-state="full">
<p>An offer has a capacity. Past it, the host answers "full" and the caller tries the
next offer.</p>
<p>Here the load is raised until the Ledger's {{ x.topology.ledger_capacity }} slots run
out. There is one Ledger, so there is no next offer, and the caller gets
<code>NoOffer</code> with what each offer said. It does not wait for a timeout.</p>
</div>

<div class="mx-step" data-state="stock-crash">
<p>{{ x.topology.stock_hosts[0] }} crashes. Its connections close, so the sessions it
was serving are cancelled at once.</p>
<p>They are not resumed. A cancelled session is discarded and the caller starts another,
which the two remaining hosts take. A reply the dead host had already sent is still
delivered.</p>
</div>

<div class="mx-step" data-state="silent">
<p>A machine that hangs is harder, because nothing closes. The cluster node is the
failure detector. It probes each peer every {{ x.timings.swim_probe_s }} second and waits
{{ x.timings.swim_ack_ms }} ms for the answer. A peer that misses one is suspected, and
has {{ x.timings.suspect_s }} seconds to show it is alive.</p>
<p>Meanwhile {{ x.topology.stock_hosts[0] }}'s sessions are frozen and a caller that
tries it moves on to the next host. When the time is up it is declared dead and its
sessions are cancelled, with that as the cause: at most about
{{ x.timings.swim_ack_ms | divided_by: 1000.0 | plus: x.timings.swim_probe_s | plus: x.timings.suspect_s }}
seconds after it hung.</p>
<div data-mx-inline="timeline:silent"></div>
</div>

<div class="mx-step" data-state="ledger-stop">
<p>The host holding the Ledger stops. The topology asks for one Ledger on a host
labelled <code>books</code>, so the other such host opens the offer once membership has
given up on the first. Sessions are refused in between.</p>
<p>The Ledger keeps a running total in memory, and the total does not move with the
role. The new Ledger starts from 0.</p>
</div>

<div class="mx-step" data-state="return">
<p>The stopped host comes back as a new incarnation, so nothing can reach it through
an old session. It offers Stock again, and no other node had to coordinate that.</p>
<p>It does not take the Ledger back at once. A node that rejoins counts for placement
only after a settle period of {{ x.timings.settle_s }} seconds, so a host that keeps
dropping out cannot pull a role back and forth. After that, if it still ranks first, the
role returns to it, and the total starts from 0 a second time.</p>
</div>

<div class="mx-step" data-state="no-offer">
<p>Both <code>books</code> hosts are down. Nothing can play Ledger, so every caller gets
<code>NoOffer</code> naming that role.</p>
<p>Stock is still on offer, but a session needs every role before it starts. None runs
half-formed.</p>
</div>

</div>
</section>

These behaviours are tested on every pull request by scenarios under `test/two_node/`,
which run the same cluster runtime with other protocols: `cluster_ap_retry` (a full offer
is passed over, and `NoOffer` when nothing is left), `cluster_crash` (a killed node is
declared dead), `cluster_session_silent` (a hung node is declared dead and its session
cancelled), `topology_move` (a single-holder role moves when its holder dies),
`topology_rejoin` (the returning node waits out the settle period, then takes the role
back) and `cluster_ap_restart` (a restarted node offers again and the next session finds
it).

The lab scenario that runs all of this on the app above is run by hand. Its one recorded
run ({{ x.lab_run.date }}) did not pass: the Ledger moved in {{ x.lab_run.failover_s }}
second with no session failed, but the returning host took the role back at once and
sessions stopped. Those bugs have since been fixed and are guarded by `topology_rejoin`.
The lab has not been run again.

<!-- Chapter 5, "Deploying while it runs", goes here. It is plan Task 13
     (specs/plans/2026-11-05-distributed-explainer-page-plan.md) and waits on the lab app
     gaining a canary step and a state migration
     (specs/todos/2026-11-05-lab-app-canary-and-migration.md). Until it lands this page
     has no `nav_order`, so the sidebar does not link it. Its simulation core and renderer
     (sim-release.js, draw.release) and the mailbox's deploy marker are already built and
     tested. -->

## What March does not do

Everything above comes with limits. These are the ones a reader is most likely to assume
away.

- **A failed session is not resumed.** It is cancelled and discarded, and the caller
  starts another. Nothing replays it.
- **An actor's state dies with the actor.** The Ledger's total starts again from 0 after
  a crash or a move. Durable state is yours to store.
- **There is no automatic rollback.** A release that halts stays where it stopped.
  Rolling back is a new release, which only you can sign.
- **Roles run over the network only when compiled.** The interpreter checks the same
  types and runs the in-process test transport, but not the sockets.
- **Every pair of roles that talk needs a direct connection.** There is no relaying
  through a third node.

The reference chapters go further on each part:
[Choreography]({{ site.baseurl }}/docs/choreography/),
[Session Types]({{ site.baseurl }}/docs/session-types/),
[Clustering]({{ site.baseurl }}/docs/clustering/),
[Topology]({{ site.baseurl }}/docs/topology/) and
[Hot Code Reload]({{ site.baseurl }}/docs/hot-code-reload/).

<details>
<summary>How the numbers on this page were measured</summary>
<p>Every number, excerpt and compiler message above is generated, not typed. One script
regenerates them all, and this page was last generated at commit
<code>{{ x.generated.commit }}</code> on {{ x.generated.date }}:</p>
<pre>scripts/gen-explainer-data.py</pre>
<ul>
<li><strong>Modules, state types and functions:</strong>
<code>march --emit-core-ast examples/lab_app/src/lab_app.march</code>, counting the
declarations in each <code>Order_*</code> module.</li>
<li><strong>Fingerprint and message tags:</strong>
<code>march --check --emit-protocols DIR examples/lab_app/src/lab_app.march</code>, which
writes <code>DIR/Order.json</code>.</li>
<li><strong>Compiler messages:</strong> <code>march --check</code> on each program in
<code>docs/assets/explainer/programs/</code>.</li>
<li><strong>The {{ x.state_map.cells }} combinations and the {{ reach }} reachable
ones:</strong> computed by the script from the step tree in <code>Order.json</code>.</li>
<li><strong>Probe, ack and suspect times:</strong> the cluster node's defaults, from the
Clustering chapter. <strong>Settle period:</strong> from the Topology chapter.
<strong>Capacities and hosts:</strong> <code>examples/lab_app/topology.toml</code> and
<code>topology.lab.toml</code>.</li>
<li><strong>Simulations:</strong> seeded ({{ x.sim.seed }}), at {{ x.sim.load_per_s }}
sessions a second. Their rules are tested in <code>test/explainer/</code>; they are not
recordings.</li>
</ul>
</details>
