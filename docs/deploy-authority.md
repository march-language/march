---
layout: docs
title: "What a Deploy Is Allowed to Do"
nav_order: 10.95
permalink: /docs/deploy-authority/
description: "One dependency update to a running cluster, followed past every check that asks what the new code can reach."
---

<!-- Hand-written page: the second scrolling explainer, on capabilities, topology and
     deploys. It shares its machinery with docs/protocol-to-cluster.md
     (docs/_includes/explainer.html, docs/assets/explainer/).

     Every count, excerpt and tool message here comes from docs/_data/authority.json
     (`site.data.authority`), which scripts/gen-authority-data.py writes from the real
     compiler and forge: never type one in by hand. After changing examples/lab_app or a
     fixture under docs/assets/explainer/authority/, rerun the generator (doc-lint Check H
     fails until you do).

     The page is capped at a 20-minute read: scripts/check-explainer-budget.py counts its
     words and cards. Each graphic is a `<section class="mx-scrolly" data-figure="…">`
     whose cards (`.mx-step`, `data-state`) drive a figure registered in
     docs/assets/explainer/chapters-authority.js. -->

{% include explainer.html data=site.data.authority figures="authority" %}
{% assign x = site.data.authority %}
{% assign t = x.topology %}
{% assign ingress = t.pools[0] %}
{% assign work = t.pools[1] %}

# What a Deploy Is Allowed to Do

A code review shows what a change says. It rarely shows what the change can now reach. A
library that formats a number in one release can open a socket in the next, and the diff
that brings it in is one line with a version number on it.

March keeps a record of what every part of a program may touch, and checks it at each
step between a pull request and a running machine: when a dependency arrives, when the
program is compiled, when it is deployed, and when a node is asked to run it. This page
follows one small update past each of those checks.

The program is
[`examples/lab_app`](https://github.com/march-language/march/tree/main/examples/lab_app):
three roles on four machines, the same one
[From a Protocol to a Cluster]({{ site.baseurl }}/docs/protocol-to-cluster/) follows.
Nothing here needs that page first.

## What a program may touch

Every March module says what it needs from the world outside it, on lines that begin
`needs`. This is the head of `Probe`, the lab app's module that writes each node's health
reading to a file every few seconds:

<pre class="mx-code"><code class="language-march">{{ x.excerpts.probe | escape }}  ...</code></pre>

<section class="mx-scrolly" data-figure="reach">
<div class="mx-figure"><div class="mx-stage"><img class="mx-fallback" src="{{ site.baseurl }}/assets/explainer/fallback/reach.svg" alt="{{ x.modules.total }} squares, one for each module of the lab app's program, in three groups: {{ x.modules.classes.none }} that reach nothing, {{ x.modules.classes.inside }} that reach only the process, and {{ x.modules.classes.outside }} that can reach files, the network or another process."></div></div>
<div class="mx-steps">

<div class="mx-step" data-state="all">
<p>One square for each module in the lab app's program: {{ x.modules.total }} of them.
A few were written for the app. The rest are the library code it links.</p>
</div>

<div class="mx-step" data-state="none">
<p>{{ x.modules.classes.none }} of them declare nothing. They cannot open a file, read
the clock or print a line. They take values and return values.</p>
<p>That is checked, not promised. A module that does any of those things without a
<code>needs</code> line does not compile.</p>
</div>

<div class="mx-step" data-state="inside">
<p>{{ x.modules.classes.inside }} reach only the process they run in (the console, the
clock, random numbers, tasks, shared mutable state) or a session they are handed.</p>
</div>

<div class="mx-step" data-state="outside">
<p>{{ x.modules.classes.outside }} can reach a file, the network or another process.
For anyone auditing this program, these are the modules to read.</p>
</div>

<div class="mx-step" data-state="own">
<p>{{ x.modules.own | size }} of those were written for the app, and each names what it
uses. <code>Probe</code> writes a file, reads the clock and starts a task. None of the
three names the network.</p>
</div>

<div class="mx-step" data-state="undeclared">
<p>Suppose <code>Probe</code> starts sending its reading to a collector, and nobody adds
the line.</p>
<pre><code class="language-march">{{ x.programs.undeclared.shown | escape }}</code></pre>
<p class="mx-diag">{{ x.programs.undeclared.headline | escape }}</p>
<details><summary>What the compiler prints</summary><pre>{{ x.programs.undeclared.output | escape }}</pre></details>
</div>

<div class="mx-step" data-state="ceiling">
<p>Declaring is not the same as being allowed. Authority enters a program in one place,
the parameters of <code>main</code>, and can only be narrowed from there. This
<code>main</code> is handed files and the clock, and a module under it declares the
network and uses it.</p>
<pre><code class="language-march">{{ x.programs.ceiling.shown | escape }}</code></pre>
<p class="mx-diag">{{ x.programs.ceiling.headline | escape }}</p>
<details><summary>What the compiler prints</summary><pre>{{ x.programs.ceiling.output | escape }}</pre></details>
</div>

</div>
</section>

The lab app has no hand-written `main`. The compiler generates one from a topology file
and narrows what it holds for each group of machines. That is two sections down. First,
the update.

## A dependency asks for more

The lab app has no dependencies, so to follow an update this page gives a copy of it one.
`gauge` is a small library that formats the reading `Probe` writes:

<pre class="mx-code"><code class="language-march">{{ x.dep.v1.code | escape }}</code></pre>

In the copy, the line of `Probe` that built that string by hand becomes
`{{ x.dep.call }}`. Nothing else in the app changes, on this page or in the repository:
the copy is made by the script that generates the page's numbers.

<section class="mx-scrolly" data-figure="reach">
<div class="mx-figure"><div class="mx-stage"><img class="mx-fallback" src="{{ site.baseurl }}/assets/explainer/fallback/reach.svg" alt="The same squares, with one more for the dependency."></div></div>
<div class="mx-steps">

<div class="mx-step" data-state="dep">
<p>One more square, and it reaches nothing. <code>forge audit --record</code> writes
down what each dependency declares, in a file you commit:</p>
<pre>{{ x.dep.lock_before | escape }}</pre>
</div>

<div class="mx-step" data-state="dep-update">
<p>Version {{ x.dep.v2.version }} also reports the reading to a collector.</p>
<pre><code class="language-march">{{ x.dep.v2.code | escape }}</code></pre>
<p>Its square moves. It is now one of the modules that can reach the network.</p>
</div>

<div class="mx-step" data-state="dep-update">
<p><code>forge deps</code> compares what the new version declares with the committed
file, and stops with exit status {{ x.dep.refused.exit }}:</p>
<pre>{{ x.dep.refused.output | escape }}</pre>
<p>The lock file is left as it was. Had the new version dropped a capability instead,
the update would have gone through.</p>
</div>

<div class="mx-step" data-state="dep-accepted">
<p>Nothing forbids a library from using the network. The rule is that it cannot start
to without someone saying yes. The yes is
<code>forge deps --accept-caps</code>, and it lands in the committed file, where a
reviewer sees it:</p>
<pre>{{ x.dep.lock_after | escape }}</pre>
</div>

</div>
</section>

Accepting the update changed no line of the app. `Probe` calls the same function as
before, and the program still compiles. What changed is what the machines that run
`Probe` can reach. The rest of the page is how March keeps track of that.

## From a file to machines

The lab app has no `main` and no deployment scripts. It has this file:

<pre class="mx-code"><code>{% for line in x.topology_file %}{{ line | escape }}
{% endfor %}</code></pre>

`[roles]` binds each role to the code that plays it: a function for Stock, an actor for
Ledger. `capacity` is how many sessions one machine serves in that role at once. Past it
the machine answers that it is full, and the caller tries another machine's offer.
`place` says which machines hold the role. A second, shorter file names the lab's four
machines and labels them.

<section class="mx-scrolly" data-figure="topology">
<div class="mx-figure"><div class="mx-stage"><img class="mx-fallback" src="{{ site.baseurl }}/assets/explainer/fallback/topology.svg" alt="Four machines in two pools, with the roles each one holds, the capabilities each pool may reach and the firewall links between every pair of machines."></div></div>
<div class="mx-steps">

<div class="mx-step" data-state="hosts">
<p>Two pools of machines. <code>{{ ingress.name }}</code> is one machine,
{{ ingress.hosts[0].name }}. <code>{{ work.name }}</code> is
{{ work.hosts | size }}: {{ work.hosts | map: "name" | join: ", " }}. The labels on them
come from the lab's file.</p>
</div>

<div class="mx-step" data-state="placed">
<p>Roles are placed by the file, not by code. Shop goes where the
<code>{{ ingress.name }}</code> pool starts it. Stock has no placement rule, so every
machine that serves it offers it. Ledger is placed
<code>on = "books", count = 1</code>: one machine carrying that label holds it.</p>
</div>

<div class="mx-step" data-state="flow">
<p>Each dot is one message of a session. Shop asks Stock, Stock answers and tells
Ledger, Ledger confirms to Shop. The <code>main</code> that starts all of this was
generated from the file.</p>
<p>This is a simulation, slowed so it can be watched: about
{{ x.sim.sessions_per_s }} sessions a second.</p>
</div>

<div class="mx-step" data-state="stop">
<p>Stop the machine holding the Ledger. Once the cluster has given up on it, the other
<code>books</code> machine takes the role. Sessions are refused in between.</p>
<p>Nobody edited a file or restarted anything.
<a href="{{ site.baseurl }}/docs/protocol-to-cluster/#the-cluster-nodes-down-and-up">The
other page</a> goes through what the cluster does here.</p>
</div>

<div class="mx-step" data-state="caps">
<p>The machine is back and offers Stock again. Now the part this page is about. For each
pool, the compiler works out what the pool's own code can reach: its startup hook, its
roles and everything they call.</p>
<p>Nobody wrote these lists. They come from the same <code>needs</code> lines as the
squares.</p>
</div>

<div class="mx-step" data-state="firewall">
<p><code>forge</code> writes each machine's firewall from the same file. The cluster
port, {{ t.cluster_port }}, is open between every pair of machines:
{{ t.cluster_rules }} rules. The control port, {{ t.control_port }}, is open only between
the {{ t.control_hosts | size }} machines labelled <code>control</code>:
{{ t.control_rules }} rules.</p>
<p>The firewall does not keep the pools apart. Certificates do: each node's certificate
names the roles it may play.</p>
</div>

<div class="mx-step" data-state="policy">
<p>When a machine is set up, <code>forge host init</code> also leaves it a policy file
made from its pool's list. The node checks new code against that file.</p>
<p>It is the last check a patch meets, and the next section gets there.</p>
</div>

</div>
</section>

## The patch that asked for more

Back to `gauge` {{ x.dep.v2.version }}. It was accepted and the app compiles. The next
step is to deploy it to the running cluster. March can do that hot: new code is loaded
into the live processes, with no restart.

<section class="mx-scrolly" data-figure="rollout">
<div class="mx-figure"><div class="mx-stage"><img class="mx-fallback" src="{{ site.baseurl }}/assets/explainer/fallback/rollout.svg" alt="The same four machines and the developer's machine. A patch that adds a capability is stopped at a gate before it leaves the developer's machine."></div></div>
<div class="mx-steps">

<div class="mx-step" data-state="widen">
<p>Work out the pools' lists again and both have grown by one:
<code>{{ x.widening.added.work | join: ", " }}</code>.</p>
<p>It reached them through <code>Probe</code>, which both pools start. Neither
<code>Work</code> nor <code>Ingress</code> mentions the network anywhere.</p>
</div>

<div class="mx-step" data-state="refused">
<p><code>forge deploy hot</code> makes that comparison before it builds anything,
against the lists recorded when the last deploy completed:</p>
<pre>{{ x.widening.refusal.output | escape }}</pre>
<p>The patch never leaves your machine. <code>forge deploy</code>, which a cluster like
the lab's uses, blocks the pool in its plan for the same reason.</p>
</div>

<div class="mx-step" data-state="refused">
<p>A pool can also have its list written down in the topology file:</p>
<pre>{{ x.widening.written.caps_line | escape }}</pre>
<p>Then the compiler holds the pool to it, and the same update fails the build:</p>
<pre>{{ x.widening.written.output | escape }}</pre>
</div>

<div class="mx-step" data-state="granted">
<p>To go on, someone has to name the capability, with
<code>{{ x.widening.grant_flags }}</code>:</p>
<pre>{% for line in x.widening.granted %}{{ line | escape }}
{% endfor %}</pre>
<p>The grant is signed along with the patch, and each node's audit log records who
deployed what, with which capabilities. In a cluster like the lab's the change travels
as one signed release: to the control leader, and from there to every machine.</p>
</div>

<div class="mx-step" data-state="node">
<p>Each node checks the patch again, against its own policy file. A node whose file does
not list the capability refuses to activate the function, whoever signed it, and stays
as it was. In the reference's worked example a node answers:</p>
<pre>{{ x.pinned.node_refusal | escape }}</pre>
<p>This check does not depend on <code>forge</code>. It holds when the deploy pipeline
is bypassed, or the wrong build is sent to a restricted machine.</p>
</div>

<div class="mx-step" data-state="admitted">
<p>A node reads its policy once, when it starts. Changing it means changing the file on
that machine and restarting the node. A hot patch cannot do it.</p>
<p>After that, the same signed patch is admitted. The new capability is now part of what
the pools may reach, and the next update is compared with that.</p>
</div>

</div>
</section>

## The last line

Everything so far is checked before code runs. The node's gate trusts the list a patch
carries, and that list is written by the compiler that built the patch.

For a check that does not rest on that, March can ask the operating system. A binary
compiled with `--cap-sandbox` puts a deny-by-default sandbox on itself before any of its
own code runs, built from what its `main` was granted (Seatbelt on macOS, seccomp on
Linux). It cannot be loosened afterwards, so it applies to hot-patched code and to C code
as well. If the sandbox cannot be installed, the program exits instead of running
unconfined.

It is opt-in, and the operating system cannot tell every capability apart: the clock, the
console, random numbers and task spawning are reported as advisory, not enforced.
[Capability Enforcement]({{ site.baseurl }}/docs/capability-enforcement/) has the table.
In a topology, a pool marked `isolate = true` gets its own build and its own sandbox. The
lab's pools are not marked, and the lab was not run under the sandbox for this page.

## What this does not do

- **The node's gate trusts the patch's own list.** Anyone holding the signing key can
  build a patch that claims less than it does. The gate catches mistakes, and a
  compromised pipeline that still uses the real compiler. It is not a sandbox.
- **Without a policy file there is no node gate.** `forge host init` installs one. A node
  started by hand with no `MARCH_DEPLOY_POLICY` admits every signed patch.
- **A capability says what may be reached, not what is done with it.** `IO.NetConnect`
  allows a health report and a data leak equally.
- **The first deploy has nothing to compare with.** The widening gate lets it through,
  with a note, and records the lists for next time.
- **A role served through a topology file is not yet held to its own grant.** The line
  `role Stock needs IO.Mut` is enforced when a role is run directly. Through a topology,
  the pool's list is the limit that holds. This is a known gap.
- **The firewall does not separate pools.** It closes the cluster to everyone else.

The reference chapters go further on each part:
[Capabilities]({{ site.baseurl }}/docs/capabilities/),
[Capability Audit]({{ site.baseurl }}/docs/capability-audit/),
[Topology]({{ site.baseurl }}/docs/topology/),
[Hot Code Reload]({{ site.baseurl }}/docs/hot-code-reload/#capability-safe-deploys) and
[Cluster Certificates]({{ site.baseurl }}/docs/cluster-certificates/).

<details>
<summary>How the numbers on this page were measured</summary>
<p>Every count, excerpt and tool message above is generated, not typed. One script
regenerates them all, and this page was last generated at commit
<code>{{ x.generated.commit }}</code> on {{ x.generated.date }}:</p>
<pre>scripts/gen-authority-data.py</pre>
<ul>
<li><strong>The squares:</strong> the <code>module_caps</code> list from
<code>march --emit-core-ast examples/lab_app/src/lab_app.march</code>, one entry per
module the program links, grouped by the capabilities it declares.</li>
<li><strong>Compiler messages:</strong> <code>march --check</code> on each program in
<code>docs/assets/explainer/authority/programs/</code>.</li>
<li><strong>The dependency:</strong> the script copies the lab app, runs
<code>forge add</code> on the <code>gauge</code> fixture in
<code>docs/assets/explainer/authority/</code>, replaces one line of <code>Probe</code>
with a call to it, and runs <code>forge audit --record</code>. It then swaps in version
{{ x.dep.v2.version }} and runs <code>forge deps</code>, with and without
<code>--accept-caps</code>.</li>
<li><strong>Pools, capabilities, ports and firewall rules:</strong>
<code>forge topology export --json --env lab</code> and
<code>forge topology gen ufw --env lab</code> on that copy.</li>
<li><strong>The refused deploy:</strong> <code>forge deploy hot --env lab</code> on the
copy. That command compares against a record a completed deploy leaves. The script
deploys nothing, so it writes that record itself, from the export made before the
update. The written-list variant is <code>forge build</code> on a second copy.</li>
<li><strong>The node's answer:</strong> quoted from the worked example in
<a href="{{ site.baseurl }}/docs/hot-code-reload/#capability-safe-deploys">Hot Code
Reload</a>. It was not produced by the lab app.</li>
<li><strong>Simulations:</strong> seeded ({{ x.sim.seed }}). Their rules are tested in
<code>test/explainer/</code>; they are not recordings.</li>
</ul>
</details>
