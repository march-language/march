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

## What the compiler makes of it

## Inside one node: the actor

## The cluster: nodes down and up

## Deploying while it runs

## What March does not do
