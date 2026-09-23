# `[P2]` Compiler: Linearity (found during Core March widening slice 7, 2026-07-10)

**Status corrected 2026-09-22; unscheduled by decision.** The bullet below predates what
the spec records. **Cut (a) landed** (2026-07-17, `10b53ec0`): `ci_module` on every
constructor, and **L4 is fully closed**, so this is no longer L4's blocker. **Cut (b) was
attempted and reverted**: collision-conditional FQN identity worked in two of the three
places types are canonicalised but not the module-registry loader
(`load_module_into_env` / `ensure_loaded`), giving `expected Value but got Msgpack.Value`.
What remains (type soundness across all three subsystems, and Stage 4 consolidation) is,
in the spec's own words, not forced by a live bug. The repo owner has chosen to leave it
unscheduled; the four sign-off questions below only need answers when it is picked up.

- [ ] **ARCHITECTURE — Fully-qualified type & constructor identity (flat-namespace overhaul).** **SPEC'D (2026-07-17): `specs/plans/archive/2026-07-17-fqn-type-ctor-identity.md`** (moved to `archive/` by #131; the old path is dead). Types/ctors resolve by BARE name today (`surface_ty`'s `canon_name` collapses qualified→bare, `typecheck.ml:2672`; `TCon` carries a bare name; `env.types`/`env.ctors` are flat maps), so two modules' same-named types are literally one nominal type — while VALUES already resolve toward qualified identity + visibility (`qualify_module_refs`, `pub_set`). The spec finishes that inconsistency: FQN canonical identity for types/ctors, bare/aliased refs resolved to it, with a local-shadows-import + ambiguous-bare-is-an-error rule under `MARCH_LIB_PATH` auto-discovery. Staged (spike → carry-identity → resolution-rules → flip-consumers), with hot-path (unification) + mangling/CAS + per-file-typecheck risks called out. **This is the shared upstream blocker for L4, the impl-coherence orphan rule, the ctor cross-talk, and the opaque-type asymmetry — fixing it once unblocks all four.** Four open sign-off questions (behavior-rule scope, mangling re-baseline, explicit-imports, sequencing-vs-stopgap).

- **Cross-ref:** session-channel linearity's own gaps (parameter-endpoint reuse; unclosed-`SEnd` drop) are the pre-existing **F7**, filed under "Compiler: Session types" below — the generic tracker documented in §2.9 is the ONLY session-linearity enforcement, so F7's shapes are exactly the shapes this tracker cannot see.
