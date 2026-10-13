# Landing page: "What makes March different" leads with safety (2026-10-13)

The six-section pitch on `docs/index.md` is reordered and rewritten to lead with what is
unique to March, not with what it shares with Elixir. Decided with the repo owner:
safety first, and the `--grant-cap` refusal as the hot-deploy sample.

1. **The whole program is bounded by `main`'s signature**: the grant, with the real
   diagnostic (chain from `main`, "declaring `needs` does not raise it"), and one sentence
   on the manifest and upper limit catching a lying dependency.
2. **Three safety layers on one function**: the chunk-reader example from
   safety-by-construction, numbered (1) capability, (2) typestate, (3) refinement.
3. **Typed protocols, for two parties or twenty**: the `Fan` `@[endpoints]` protocol with
   role B's generated-typed body; failure isolation and crash branches in one sentence.
4. **Deploy to a running node, and only what it is allowed to do**: the
   `forge deploy hot` widening refusal transcript, and the node's policy as the last word.
5. **Actors with supervision trees**: unchanged sample; one sentence added on actors
   counting against the grant.
6. **Perceus reference counting + FBIP**: unchanged, with the benchmark links from the
   previous fix.

The REPL and forge sections are dropped from the pitch; their content moves into the
Tooling bullets of the feature overview (REPL line expanded; forge line now says search,
deploy, observe and links the reference). The intro paragraph foreshadows the new order.
Every link checked; `scripts/check-docs.sh` passes.
