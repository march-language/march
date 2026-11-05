---
layout: docs
title: "From a Protocol to a Cluster"
permalink: /docs/protocol-to-cluster/
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
<div class="mx-figure"><div class="mx-stage"></div></div>
<div class="mx-steps">

<div class="mx-step" data-state="empty">
<p>Here is every combination: {{ x.state_map.cells }} cells, one for each way the three
positions can line up. Blocks are Shop's position, columns are Stock's, rows are Ledger's.</p>
<p>Nothing stops ordinary networked programs from reaching any of them. Most are trouble:
one side waiting for a message the other will never send, or both sides waiting.</p>
</div>

<div class="mx-step" data-state="path">
<p>The protocol reaches {{ reach }} of them. They light in the order a run visits them,
counting a role as moved once it has sent, even if its peer has not received yet.</p>
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
<div class="mx-figure"><div class="mx-stage"></div></div>
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
<p>The views are checked against each other first. If one role would send while its peer
is also sending, the protocol itself is rejected, before any role is written
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
<code>S_choose_have_out</code>. Only <code>choose_have</code> and <code>choose_out</code>
accept it. <code>send_Book</code> wants an <code>S_send_Book</code>, and only
<code>choose_have</code> returns one.</p>
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
counting, LLVM, a native binary for each pool.</p>
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

## The cluster: nodes down and up

## Deploying while it runs

## What March does not do
