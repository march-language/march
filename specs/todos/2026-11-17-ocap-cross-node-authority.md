# ocap: authority does not travel across nodes

Logged 2026-11-17 by ocap phase 4 (specs/plans/2026-11-15-ocap-p4-runtime-plan.md, decision 7;
design `specs/2026-11-10-object-capability-design.md` §21 "Across nodes").

A child started on another node does not carry the starting code's authority. `DistSupervisor`
starts remote children by a CAS-typed `RemoteRef` over `NodeCall`, and nothing in that message
names an authority, so the receiving node runs the child under its own launch authority. That
never widens anything on the receiving node (its launch authority is its own `main`'s request,
narrowed by its own `MARCH_GRANT`), but a worker started inside a scoped function on node A is
not limited by that function's clause on node B, while the same spawn on node A would be.

What to do: define a wire format for an authority (the layer list as scope text, each layer's
limit and text), send it with a remote start, and have the receiving node intersect it with
its own launch authority before the child's `init` runs. The intersection must never widen
the receiving node's authority. Add a two-node conformance fixture.
