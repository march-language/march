`[P3]` - [ ] **Types declared inside a module never get their newtype, niche or unboxed layout.**

Filed 2026-10-07 while closing the qualified-vs-short spelling hole
(`specs/progress/2026-10-07-kind-canonical-spelling.md`).

Lowering registers a module-declared type under its qualified name
(`Duration.Duration`, `Main.Inner.Id`) but builds every value under the short
one (ctor key `Duration.Duration`, type part `Duration`). The kind table now
answers every representation query under that short spelling
(`Kind.canonical_name`), which is what programs actually build: the short
name misses the qualified declaration and falls back to **Boxed**. So the
Milestone-2 newtype/niche and Milestone-3 unboxed-aggregate representations
only ever apply to types registered under a bare name (the prelude's
`Option`, `Result`, top-level declarations). Nearly every user type lives in a
`mod`, so in practice they never apply to user code.

## Size

The corpus trace behind the spelling fix (oracle corpus, ~300 programs) found
73 stdlib and fixture types whose declaration says something other than
Boxed:

| Declared layout | Types |
|---|---|
| Newtype | 61 (e.g. `Map`, `Bytes`, `Duration`, `UUID`, `Members`, `VectorClock`) |
| Niche | 6 (`CsvRow`, `CtlGate`, `Verdict`, `Outcome`, `Upgrade`, `RegisterError`) |
| Unboxed aggregate | 6 (e.g. `Decimal`, `Date`, `JsCfg`, `LiveProcess`) |

Each newtype pays a heap cell and a refcount per value that its declaration
says it does not need.

## Why it was not done with the spelling fix

Switching to the declared layout changes the representation of every one of
those types at once. Three things must be settled first:

1. **C runtime ABIs.** `Bytes` and `Process.LiveProcess` are built by the C
   runtime as boxed heap cells (`compress_bytes_from_raw`,
   `process_spawn_async`: "tag=0, 2 int64 fields"). Each needs an explicit
   layout pin, and every other runtime path that builds or walks a stdlib
   value has to be audited the same way, not only the builtin signatures.
   `CsvRow` is the opposite case and is already pinned to its declaration.
2. **Cluster wire format and hot reload.** Values sent between nodes and
   migrated across hot reloads are encoded by walking heap cells. A type that
   stops being a cell changes what is on the wire, so mixed-version clusters
   and `migrate_msg` need a story.
3. **Identity.** The clean fix is one declaration identity for a type, which
   is the flat-namespace FQN work left unscheduled in
   `specs/todos/2026-07-10-p2-compiler-linearity-found-during-core-march-widening-slice-7.md`.

## Done when

Module-declared types get their declared layout, with the C-built ones pinned
and the wire format versioned, proven by the ASAN corpus sweep, the two-node
suites and the benchmarks named in `specs/benchmarks.md`.
