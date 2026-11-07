---
layout: docs
title: "What One Owner Is Worth"
nav_order: 10.96
permalink: /docs/one-owner/
description: "One tree, transformed by ordinary functional code: in-place reuse, linear and affine types, and the contract that keeps a function allocation-free."
---

<!-- Hand-written page: the third scrolling explainer, on ownership, in-place reuse, linear
     and affine types, and allocation contracts. It shares its machinery with
     docs/protocol-to-cluster.md and docs/deploy-authority.md (docs/_includes/explainer.html,
     docs/assets/explainer/).

     Every count, excerpt and compiler message here comes from docs/_data/ownership.json
     (`site.data.ownership`), which scripts/gen-ownership-data.py writes from the real
     compiler: never type one in by hand. After changing a fixture under
     docs/assets/explainer/ownership/, rerun the generator (doc-lint Check H fails until you
     do).

     The page is capped at a 20-minute read: scripts/check-explainer-budget.py counts its
     words and cards. Each graphic is a `<section class="mx-scrolly" data-figure="…">`
     whose cards (`.mx-step`, `data-state`) drive a figure registered in
     docs/assets/explainer/chapters-ownership.js. -->

{% include explainer.html data=site.data.ownership figures="ownership" %}
{% assign x = site.data.ownership %}
{% assign r = x.runs %}
{% assign c = x.contracts %}

# What One Owner Is Worth

Functional code builds new values instead of changing old ones. The usual price is that
every new value is a fresh allocation, and the old one is garbage for a collector to find
later. March pays that price only when it has to. The question it asks at every rebuild is
not "is this value immutable?" but "is anyone else holding it?", and when the answer is no,
the new value is written over the old one.

This page follows one small tree through that question four times. Then it shows the same
question asked by the type checker instead of the runtime, as a `linear` or `affine` type,
and finally the contract that makes the compiler keep a function allocation-free.

## What the compiler finds

The tree has {{ x.tree.cells }} cells: {{ x.tree.leaves }} leaves and {{ x.tree.nodes }}
inner nodes. `inc_leaves` reads as if it builds a second tree:

<pre class="mx-code"><code class="language-march">{{ r.owned.excerpt | escape }}</code></pre>

<section class="mx-scrolly" data-figure="heap">
<div class="mx-figure"><div class="mx-stage"><img class="mx-fallback" src="{{ site.baseurl }}/assets/explainer/fallback/heap.svg" alt="The {{ x.tree.cells }} cells of a binary tree, each with its reference count, and a second tree of copies growing beside it while a cursor walks the first."></div></div>
<div class="mx-steps">

<div class="mx-step" data-state="built">
<p>The {{ x.tree.cells }} cells as <code>build</code> left them. Each carries a count of
how many references point at it. Every count is 1: the tree has one holder, the binding
<code>t</code>.</p>
</div>

<div class="mx-step" data-state="owned">
<p><code>inc_leaves(t)</code> is the last thing <code>main</code> does with
<code>t</code>. The call takes over the only reference, so when a <code>match</code> looks
inside a <code>Node</code>, that cell is about to die, and the <code>Node</code> being built
has the same shape. The compiler writes the new fields into the old cell.</p>
<p>Across the whole walk, <code>inc_leaves</code> allocates
<strong>{{ r.owned.allocs.inc_leaves }}</strong> cells. That number is read from the
runtime's own allocation trace of this program, not estimated.</p>
</div>

<div class="mx-step" data-state="shared">
<p>Now <code>main</code> reads the old tree again afterwards:</p>
<pre><code class="language-march">{{ r.shared.excerpt | escape }}</code></pre>
<p>Two holders, so the counts on the path climb to 2 as the walk descends, and nothing may
be overwritten. <code>inc_leaves</code> allocates
<strong>{{ r.shared.allocs.inc_leaves }}</strong> cells: a complete second tree. The
program is still correct; it is only slower. The fallback is automatic, and the compiler
says where it happened:</p>
<p class="mx-diag">{{ r.shared.headline | escape }}</p>
<details><summary>What <code>march --why-copies</code> prints</summary><pre>{{ r.shared.why_copies | escape }}</pre></details>
</div>

<div class="mx-step" data-state="vault">
<p>A holder need not be a variable. Here the tree is put in a Vault, March's shared table,
before the transform, and <code>inc_leaves(t)</code> is again the last use in the code:</p>
<pre><code class="language-march">{{ r.vault.excerpt | escape }}</code></pre>
<p>The static report sees the code and finds no second use:</p>
<p class="mx-diag">{{ r.vault.why_copies | escape }}</p>
<p>The runtime sees the count. The Vault holds a reference, so the walk copies all
<strong>{{ r.vault.allocs.inc_leaves }}</strong> cells anyway. That is the division of
labour on this page: the compiler decides where reuse is possible, and the count decides
whether it happens.</p>
</div>

<div class="mx-step" data-state="parallel">
<p>One owner also means no lock. The two halves of a uniquely held <code>Node</code> are
disjoint, so each can be rewritten on its own task with nothing to synchronise:</p>
<pre><code class="language-march">{{ r.parallel.excerpt | escape }}</code></pre>
<p>Two tasks, and <code>inc_leaves</code> allocates
<strong>{{ r.parallel.allocs.inc_leaves }}</strong> cells. The list, the chunks and the
task handles around it cost {{ r.parallel.allocs.plumbing }} small cells; the tree costs
none.</p>
</div>

</div>
</section>

Nothing above was written for the optimiser. Two mechanisms did the work, and the
[Memory Model]({{ site.baseurl }}/docs/memory-model/) names them. **Perceus** is
deterministic reference counting: the compiler inserts each increment and decrement where
ownership changes, so a value is freed at its last use, at a point you can see. **FBIP**,
"functional but in-place", is the reuse rule on top of it: a dying value with a count of 1
gives its cell to the same-shaped value being built. Any other value is copied, and the
copy is never wrong, only slower. The compiler shows its decisions as editor hints
(`♻ in-place`, `⧉ copied`, `⚡ stack-allocated`), and `march --why-copies` lists every copy
with its reason.

## What the type guarantees

The runtime learns that a value has one owner by counting. The type checker can be told
instead. A `linear` value must be used exactly once; an `affine` value at most once. Both
forbid using it twice. Only `linear` forbids forgetting it. The compiler tracks the value
as a token that each use consumes.

<section class="mx-scrolly" data-figure="token">
<div class="mx-figure"><div class="mx-stage"><img class="mx-fallback" src="{{ site.baseurl }}/assets/explainer/fallback/token.svg" alt="A short March function with a token beside the line where a linear value is bound, consumed at its one use, and marked where a second use is refused."></div></div>
<div class="mx-steps">

<div class="mx-step" data-state="linear-ok">
<p>The same tree, declared <code>linear</code>. The token is minted at the binding and
consumed by <code>inc_leaves</code>, which takes a <code>linear</code> parameter and so
promises to consume what it is given. This compiles.</p>
<pre><code class="language-march">{{ x.linear.ok.excerpt | escape }}</code></pre>
</div>

<div class="mx-step" data-state="linear-twice">
<p>The sharing program from above, with the same declaration. The second use has no token
to consume. Where the runtime copied, the type checker refuses:</p>
<p class="mx-diag">{{ x.linear.twice.headline | escape }}</p>
<details><summary>What the compiler prints</summary><pre>{{ x.linear.twice.output | escape }}</pre></details>
</div>

<div class="mx-step" data-state="linear-never">
<p>A token that reaches the end of its scope unconsumed is the other error. For a tree it
is only a wasted value; for a file handle or a session endpoint it is a leak, and
<code>linear</code> is how March makes "you must close this" a type.</p>
<p class="mx-diag">{{ x.linear.never.headline | escape }}</p>
</div>

<div class="mx-step" data-state="affine-ok">
<p><code>affine</code> keeps half the rule. A branch may leave the token unused:</p>
<pre><code class="language-march">{{ x.linear.affine_ok.excerpt | escape }}</code></pre>
<p>It is the right word for a permission or a one-shot token: something you may decide not
to use, but must never use twice.</p>
</div>

<div class="mx-step" data-state="affine-twice">
<p>The other half still holds.</p>
<pre><code class="language-march">{{ x.linear.affine_twice.excerpt | escape }}</code></pre>
<p class="mx-diag">{{ x.linear.affine_twice.headline | escape }}</p>
</div>

</div>
</section>

Two consequences follow from the type knowing what the runtime had to count.

- **Branches must agree.** A linear value consumed in one branch of an `if` or `match`
  must be consumed in every branch that returns; the early `Err` return of `let?` is a
  branch too.
- **The count disappears.** The Memory Model puts it as "{{ x.pinned.strongest.phrase | replace: "*", "" }}":
  one owner by the type, not by inference, so the compiler drops the reference-count
  traffic where the type settles it and frees the value at its last use. Linearity is
  erased before code generation; nothing checks it again at run time.

Some types are linear without the keyword. The stdlib's `Handle` and the fixed buffer
`RingBuf` are `always_linear`: every operation consumes the value and hands it back, which
is what lets a buffer be written in place without anyone else seeing it. A session endpoint
is tracked as affine plus a rule that it must be closed once the protocol reaches `End`;
walking away from a channel mid-protocol is not refused today. [Linear
Types]({{ site.baseurl }}/docs/linear-types/) covers all of it, including linear record
fields and what a closure may capture.

## Making it stick

Reuse is something the compiler found, and a later edit can lose it: read the old value
once more, store it somewhere, add a field that changes a type's representation. A contract
turns the finding into a check.

<section class="mx-scrolly" data-figure="contract">
<div class="mx-figure"><div class="mx-stage"><img class="mx-fallback" src="{{ site.baseurl }}/assets/explainer/fallback/contract.svg" alt="An allocation ledger: one row per function with a bar for the cells it allocates, and a line at zero that a contracted function may not cross."></div></div>
<div class="mx-steps">

<div class="mx-step" data-state="candidate">
<p>The compiler already knows which functions came out allocation-free. Asked, it names
them:</p>
<p class="mx-diag">{{ c.candidate.message | escape }}</p>
<p>That is one line of <code>march --compile --report-contracts</code>, and
<code>forge fix --contracts</code> applies every such line.</p>
</div>

<div class="mx-step" data-state="pinned">
<p>With the attribute on, the check is made on the compiled form, after reuse and stack
promotion have been decided, and it is made every build:</p>
<pre><code class="language-march">{{ c.pinned.excerpt | escape }}</code></pre>
<p>Reintroduce an allocation, here or in anything <code>inc_leaves</code> calls, and the
build fails instead of the benchmark.</p>
</div>

<div class="mx-step" data-state="bare">
<p>The bare form means no allocation at all. The check runs on the compiled form, where
<code>describe</code> has been inlined into <code>width_bare</code>, so it names the
allocation where it ended up:</p>
<pre><code class="language-march">{{ c.bare.excerpt | escape }}</code></pre>
<p class="mx-diag">{{ c.bare.reason | escape }}</p>
<details><summary>What the compiler prints</summary><pre>{{ c.bare.output | escape }}</pre></details>
</div>

<div class="mx-step" data-state="transient">
<p>A tick, a frame, a request handler: code that allocates freely and frees all of it
before returning has a property the bare form cannot say. <code>transient</code> asks where
a value ends up, not whether one was made:</p>
<pre><code class="language-march">{{ c.transient.excerpt | escape }}</code></pre>
<p>This compiles. It fails if the function returns something it allocated, stores one into
an object it did not allocate, or hands one to an actor, a Vault, a task or foreign code.</p>
</div>

<div class="mx-step" data-state="boxed">
<p>Some values never reach the heap at all. A variant with one constructor of two to four
<code>Int</code>, <code>Float</code> or <code>Bool</code> fields lives in registers, so
<code>forward</code> passes. Storing it into a field boxes it, and the contract says so:</p>
<pre><code class="language-march">{{ c.boxed.excerpt | escape }}</code></pre>
<p class="mx-diag">{{ c.boxed.reason | escape }}</p>
</div>

<div class="mx-step" data-state="caller">
<p>One limit to hold on to. The contract is about the function's own code. Give
<code>inc_leaves</code> a caller that keeps the old tree and the build still passes, while
at run time the walk allocates every cell again ({{ c.caller.allocs.inc_leaves }} on the
{{ c.caller.tree_cells }}-cell tree in that program). The copy belongs to the caller, and
<code>--why-copies</code> is the tool that points at it.</p>
</div>

<div class="mx-step" data-state="bound">
<p>What the contract cannot yet say is "at most <em>N</em>". A parser that allocates a
few cells per token is not allocation-free, but its count is worth pinning.
<code>@[alloc_bound(N)]</code> and a per-activation form for recursive functions are
designed and not shipped; the design is in the repository, with its open item.</p>
</div>

</div>
</section>

## What this does not do

- **The static report is a view of the code, not of the run.** `--why-copies` found no
  copy in the Vault program, and the run copied every cell. The runtime check is what keeps
  the program correct either way.
- **Reuse needs the same shape.** A `Leaf` cannot be rewritten into a `Node`; a rebuild of a
  different size class allocates.
- **Linearity is checked, then forgotten.** No runtime cost, and no runtime protection: a
  value that crosses into foreign code is on its own.
- **A `Vault` makes a value shared by definition.** Reads need no capability, and the first
  write to the table is the second holder.
- **The counts here come from a {{ x.tree.cells }}-cell tree** compiled with the allocation
  trace on. The trace names each site; it does not change what is allocated.
- **`@[alloc_bound(N)]` is a design.** Nothing on this page measured it.

The reference chapters go further: [Memory Model]({{ site.baseurl }}/docs/memory-model/),
[Linear Types]({{ site.baseurl }}/docs/linear-types/), [Value
Representation]({{ site.baseurl }}/docs/value-representation/) and the `cap no_alloc`
section of [Capabilities]({{ site.baseurl }}/docs/capabilities/#cap-no_alloc-no-heap-allocation).

<details>
<summary>How the numbers on this page were measured</summary>
<p>Every count, excerpt and compiler message above is generated, not typed. One script
regenerates them all, and this page was last generated at commit
<code>{{ x.generated.commit }}</code> on {{ x.generated.date }}:</p>
<pre>scripts/gen-ownership-data.py</pre>
<ul>
<li><strong>Programs:</strong> every excerpt is cut from a file under
<code>docs/assets/explainer/ownership/programs/</code>; the whole file is what was compiled.</li>
<li><strong>Allocation counts:</strong> each tree program compiled with
<code>march --rc-trace --compile</code> and run with <code>MARCH_TRACE_GC=1</code>; the
count is the number of <code>march_alloc</code> events whose site is inside the named
function, folded from <code>trace/gc/gc.jsonl</code> the way
<code>scripts/gc-trace-report.py</code> folds it.</li>
<li><strong>Copy reports:</strong> <code>march --why-copies</code> on the same files.
Recursion warnings that the tree functions also raise are left out of the quoted text.</li>
<li><strong>Linear, affine and contract messages:</strong> <code>march --check</code> and
<code>march --compile</code> on each program, with the exit code recorded.</li>
<li><strong>The candidate line:</strong> <code>march --compile --report-contracts</code> on
the owned program.</li>
<li><strong>Quoted claims:</strong> that a linear value is the strongest reuse case, that
linearity is erased, and that an endpoint is tracked as affine, are phrases pinned in
<code>specs/lang/memory-model.md</code> and <code>specs/lang/linear-types.md</code>; the
generator fails if they move. The allocation-bound design is
<code>{{ x.pinned.alloc_bound.design }}</code>, with its open item at
<code>{{ x.pinned.alloc_bound.todo }}</code>.</li>
<li><strong>The heap figure:</strong> a simulation of the walk, seeded ({{ x.sim.seed }}).
Its counts are the measured ones; the order and timing of the walk are drawn, not
recorded.</li>
</ul>
</details>
