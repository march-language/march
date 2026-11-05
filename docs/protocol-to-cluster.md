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

## Inside one node: the actor

## The cluster: nodes down and up

## Deploying while it runs

## What March does not do
