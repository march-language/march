# Shell latency on Linux: the R6 gate is met

Logged 2026-10-07 (observe plan R6 latency gate; design §6.9: p50 ≤ 300 ms,
p95 ≤ 600 ms per input).

R5.1 measured compile + `dlopen` only. This measures what an operator
waits for: from reading an input to printing its reply, including signing,
the EVAL round trip, and the node loading and running the fragment.

## Method

- **The diagnostic.** `MARCH_SHELL_TIMING=1` (new, `bin/shell_cmd.ml`)
  prints per input on stderr `compile <ms> node <ms> total <ms>`. `compile`
  is every fragment the input built (renderer attempts included); `node` is
  the EVAL round trip.
- **The setup.** Client and node both ran in the Linux arm64 container
  (`march-amdr-repro`), on a Docker network with the Postgres container,
  with this branch's compiler: session cache, identity, linking.
- **The workloads:**
  - 20 inputs (arithmetic, `let`s, `List.map`/`filter`/`zip`/`reverse` with
    lambdas and `limit:`, a record, string split and join, `to_string`,
    Json parse and print, program functions, `Actor.list` and
    `inspect_state`) against `test/native/shell_node.march`'s node;
  - a Depot connect followed by ten `simple_query` SELECTs against a
    Depot-backed node.
- **Runs:** three sessions of each, load average 5-7 in the VM.

## Results (ms per input)

| | p50 | p95 | max |
|---|---|---|---|
| 20-input workload | **110** | 166 | 208 |
| Depot query, linked | **158** (143 on an earlier run) | 244 | 343 |
| Depot query, `MARCH_SHELL_NO_LINK=1` | 259 | 341 | |
| Depot connect, linked / not linked | ~190-260 / ~410-440 | | |

At p50, compile is 61-66 ms and the node 44-96 ms. The node's share varies
with Postgres and the VM; its `dlopen` is ~0.1 ms on Linux. On macOS the
same workload's p50 is ~330 ms, ~150 ms of it the node's `dlopen` of each
new file. As R5.1 found, macOS nodes are recorded beside the gate, not
gated.

## Found and fixed while measuring

Compile was ~87 ms at p50 on Linux, but its profiled phases summed to ~56 ms.
Every input still copied the session's whole type table (~120k entries)
before merging its own spans in, a leftover from before the program was
lowered once per session. The typechecker already writes an input's types
into that same table (`tc_env`'s, which is `program_type_map`), so the
session now lowers from it directly: no copy, no merge. Non-clang compile
time per input went from ~37 ms to ~12 ms on macOS, and Linux compile p50
from 87 to 66 ms. Output is unchanged.

## What is left

- Clang is now ~46 ms of a Linux input's ~66 ms compile, and ~90 ms on macOS.
  Emitting the object in-process and only linking would remove most of it.
- A record result renders as `#<tag:0>` (R5.7 rendering).
