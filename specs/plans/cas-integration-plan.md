# CAS Integration — Implementation Plan

## Current State

### What Exists

**CAS library** (`lib/cas/`):

`cas.ml`:
- Two-tier content-addressed store: project-local (`.march/cas/`) + global (`~/.march/cas/`)
- `store_object(hash, data)` — writes marshalled OCaml objects to disk
- `lookup_object(hash)` — reads from project-local, then global store
- Artifact storage keyed by `compilation_hash = BLAKE3(impl_hash ++ target ++ flags)`
- Cache hits return the pre-compiled LLVM IR or object file

`hash.ml`:
- BLAKE3 hashing via the `blake3.ml` bindings
- Used for content identity of definitions

`blake3.ml`:
- OCaml bindings to BLAKE3 hash function

`serialize.ml`:
- Canonical binary serialization of AST/TIR nodes
- Format versioning for forward compatibility
- Deterministic output (sorted fields, normalized representations)

`scc.ml`:
- Strongly-connected component detection (Tarjan's algorithm)
- Groups mutually-recursive definitions for joint hashing
- `HSingle` for standalone definitions, `HGroup` for recursive sets

`pipeline.ml`:
- SCC-based compilation pipeline:
  1. Group definitions into SCCs
  2. Hash each SCC (using `scc.ml` + `hash.ml`)
  3. Look up hash in CAS (`cas.ml`)
  4. On cache hit: return stored artifact
  5. On cache miss: compile, store result in CAS
- Supports both project-local and global cache

### What's Missing

~~**Not wired into default compilation path**~~ ✅ **FIXED (Track D, committed)** — CAS is now wired into the default compilation path in `driver.ml`. All 401+ tests pass.

**No package manager** — There's no `march install`, no dependency resolution, no registry.

**No lockfile** — The spec describes lockfiles tracking resolved def_ids for reproducibility, but none exists.

**No remote CAS** — Only local storage; no way to share cached artifacts between machines or CI.

**No cache invalidation** — No mechanism to detect when a cached artifact is stale (e.g., compiler version change, flag change).

**No incremental compilation integration** — The CAS stores individual definition artifacts, but there's no incremental linking step that combines cached and freshly-compiled definitions.

---

## Target State (from `specs/content_addressed_versioning.md`)

1. **Default incremental compilation**: The standard `march build` uses CAS for all definitions; only changed definitions are recompiled
2. **Lockfile**: `march.lock` records the exact hashes of all definitions used in a build; `march build --locked` reproduces exact same binary
3. **Package manager**: `march.toml` declares dependencies; `march install` fetches from a registry; packages are identified by content hash
4. **Separate sig_hash and impl_hash**: Changing a function's implementation doesn't force recompilation of callers if the signature hasn't changed
5. **Global cache sharing**: `~/.march/cas/` shared across projects; identical definitions compiled once
6. **Remote cache**: Optional remote CAS for CI/CD artifact sharing

---

## Implementation Steps

### Phase 1: Wire CAS into Default Compilation — ✅ COMPLETE (Track D, committed)

**Step 1.1: Add CAS initialization to compiler startup** — ✅ DONE

**Step 1.2: Replace monolithic compilation with per-definition CAS lookup** — ✅ DONE
- CAS is now active in the default compilation path via `driver.ml`
- SCC grouping, hashing, and cache-hit detection all operational

**Step 1.3: Store compiled artifacts in CAS** — ✅ DONE

**Step 1.4: Incremental linking** — ✅ DONE
- All 401+ tests pass with CAS-enabled compilation

### Phase 2: Lockfile Support (Low complexity, Low risk)

**Step 2.1: Define lockfile format**
- New file: `lib/cas/lockfile.ml`
- Format: JSON or TOML mapping `definition_name → { sig_hash, impl_hash, compilation_hash }`
- Include compiler version and flags in lockfile header
- Estimated effort: 1 day

**Step 2.2: Generate lockfile during build**
- File: `bin/main.ml`
- After successful compilation, write `march.lock` with all definition hashes
- Estimated effort: 1 day

**Step 2.3: Verify lockfile during `--locked` build**
- File: `bin/main.ml`
- With `--locked` flag, read lockfile and verify all hashes match
- If a hash doesn't match, error with "lockfile out of date"
- Estimated effort: 1 day

**Step 2.4: Detect stale lockfile**
- File: `bin/main.ml`
- Compare source file mtimes against lockfile mtime
- Warn if sources are newer than lockfile
- Estimated effort: 0.5 days

### Phase 3: Separate sig_hash and impl_hash (Medium complexity, Medium risk)

**Step 3.1: Compute signature hashes**
- File: `lib/cas/hash.ml`, `lib/cas/serialize.ml`
- `sig_hash` = BLAKE3(canonical serialization of function signature only — name, type, constraints)
- `impl_hash` = BLAKE3(canonical serialization of full definition including body)
- Estimated effort: 2 days

**Step 3.2: Implement downstream invalidation based on sig_hash**
- File: `lib/cas/pipeline.ml`
- When recompiling a definition, compare its new sig_hash to the cached sig_hash
- If sig_hash unchanged: callers don't need recompilation (their compilation_hash inputs haven't changed)
- If sig_hash changed: invalidate all callers' compilation_hashes
- Estimated effort: 3 days
- Risk: Requires a caller graph (reverse dependency map); need to build this from the SCC analysis

**Step 3.3: Build reverse dependency map**
- File: `lib/cas/scc.ml` or new `lib/cas/deps.ml`
- For each definition, record which other definitions it calls
- Invert to get: for each definition, which definitions depend on it
- Estimated effort: 2 days

### Phase 4: Package Manager Foundation (High complexity, Medium risk)

**Step 4.1: Define `march.toml` package manifest**
- New file: `lib/manifest/manifest.ml`
- Fields:
  ```toml
  [package]
  name = "my-app"
  version = "0.1.0"

  [dependencies]
  http = { hash = "abc123..." }  # content-addressed
  json = { git = "https://github.com/user/march-json", rev = "v1.0" }

  [capabilities]
  requires = ["IO.Network", "IO.FileSystem"]
  ```
- Estimated effort: 3 days

**Step 4.2: Dependency resolution**
- New file: `lib/manifest/resolve.ml`
- Simple resolution: dependencies are content-addressed (no version ranges, no SAT solving)
- Fetch dependency source, hash it, verify against declared hash
- Detect diamond dependencies (same package via different paths) — content-addressed dedup handles this naturally
- Estimated effort: 5 days
- Risk: Git-based dependencies need git operations; content-addressed deps need a registry

**Step 4.3: `march install` command**
- File: `bin/main.ml` (add subcommand)
- Read `march.toml`, resolve dependencies, fetch sources, compile to CAS, write lockfile
- Store dependencies in `.march/deps/`
- Estimated effort: 3 days

**Step 4.4: Module path resolution for dependencies**
- File: `bin/main.ml`, `lib/typecheck/typecheck.ml`
- When a `use` declaration references an external module, resolve through the dependency tree
- Search order: local modules → `.march/deps/` → stdlib
- Estimated effort: 2 days

### Phase 5: Remote CAS (Low complexity, Low risk — but deferred)

**Step 5.1: Define remote CAS protocol**
- Simple HTTP API: `GET /cas/{hash}` returns artifact, `PUT /cas/{hash}` stores artifact
- Authentication via API key
- Estimated effort: 2 days (design), 3 days (implement)

**Step 5.2: Push/pull cached artifacts**
- `march cache push` — uploads locally-compiled artifacts to remote CAS
- `march cache pull` — fetches artifacts from remote CAS before building
- Estimated effort: 3 days

**Step 5.3: CI integration**
- CI builds push artifacts; developer machines pull
- Estimated effort: 2 days

---

## Dependencies

```
Phase 1 (Wire CAS) ← no blockers; can start immediately
    ↓
Phase 2 (Lockfile) ← depends on Phase 1
    ↓
Phase 3 (sig/impl hash) ← depends on Phase 1

Phase 4 (Package manager) ← depends on Phases 1, 2, 3
    ↓
Phase 5 (Remote CAS) ← depends on Phase 4

Cross-plan dependency:
- Phase 4 interacts with capability-security-plan.md Phase 4 (manifest capabilities)
```

## Testing Strategy

### CAS Integration
1. **Cache hit**: Compile a file, compile again without changes — second compile should be near-instant (all cache hits)
2. **Cache miss on change**: Modify one function, recompile — only that function recompiles
3. **Correctness**: CAS-compiled binary produces identical output to from-scratch compilation
4. **Cache invalidation**: Change compiler flags — all caches invalidated
5. **SCC hashing**: Mutually-recursive functions produce the same hash regardless of definition order

### Lockfile
1. **Reproducibility**: `march build --locked` produces byte-identical output across machines
2. **Stale detection**: Modify source, build without `--locked` — lockfile updated; build with `--locked` — error
3. **Round-trip**: Generate lockfile, clean CAS, build from lockfile — succeeds

### Package Manager
1. **Dependency fetch**: `march install` fetches and compiles dependencies
2. **Diamond dedup**: Package A depends on C v1; Package B depends on C v1 — only one copy of C
3. **Hash mismatch**: Dependency source doesn't match declared hash — error
4. **Import resolution**: `use json.Parser` resolves to dependency's module

## Open Questions

1. **Granularity**: Should CAS cache at the definition level (fine-grained, more cache hits) or module level (coarser, simpler)? The current pipeline.ml works at definition level, but the monolithic pass structure in main.ml works at module level.

2. **Serialization format**: Currently using OCaml's `Marshal` which is not stable across compiler versions. Should we switch to a portable format (protobuf, msgpack, custom binary)?

3. **LLVM IR vs. object file caching**: Caching LLVM IR text is simple but requires re-running clang. Caching `.o` object files is faster but platform-specific. Cache both?

4. **Parallel compilation**: With per-definition CAS, independent definitions can be compiled in parallel. How does this interact with the monomorphization pass (which is whole-program)?

5. **Package registry**: Should March have a central package registry (like crates.io) or rely solely on git-based dependencies? Content-addressed packages could use IPFS-style distributed storage.

6. **Cache size management**: The global CAS at `~/.march/cas/` will grow unboundedly. Need a GC policy (LRU eviction, max size limit, manual cleanup).

## Estimated Total Effort

| Phase | Effort | Risk |
|-------|--------|------|
| Phase 1: Wire CAS | 10 days | Low-Medium |
| Phase 2: Lockfile | 3.5 days | Low |
| Phase 3: sig/impl hash | 7 days | Medium |
| Phase 4: Package manager | 13 days | Medium |
| Phase 5: Remote CAS | 10 days | Low (deferred) |
| **Total** | **43.5 days** | |

Phase 5 is post-v1 and can be deferred indefinitely.
