# Content-Addressed Store (CAS) System

## Overview

The March Content-Addressed Store (CAS) is a two-tier caching system that eliminates redundant compilation of definitions by computing cryptographic hashes of function implementations. Objects are stored by their _impl_hash_ (BLAKE3 of the complete implementation), and compiled artifacts are cached by their _compilation_hash_ (BLAKE3 of impl_hash + target + compiler flags).

### Architecture

**Two storage layers:**
- **Project-local:** `<project_root>/.march/cas/` — mutable, project-specific cache
- **Global (read-through):** `~/.march/cas/` — shared across projects, acts as a persistent read-only cache

Objects are stored Git-style: first 2 hex chars of hash form a directory prefix, remainder forms the filename. Example: `objects/a3/b4c5d6...` for hash `a3b4c5d6...`.

## Implementation Status

**Complete.** All core components are implemented and integrated into the compilation pipeline (Phase 6).

## Source Files & Line References

### Core CAS Module: `lib/cas/cas.ml` (201 lines)

**Key types:**
- `def_id` (lines 15–18): Human-readable name + 64-char hex impl_hash
- `def_kind` (lines 20–22): `FnDef of fn_def | TypeDef of type_def`
- `hashed_def` (lines 24–28): Carries both sig_hash and impl_hash alongside the definition
- `t` (lines 32–39): Store state with local/global roots, in-memory index, and artifact map

**Public API:**
- `create ~project_root` (lines 103–115): Initialize store, creating directories if needed
- `store_def t hd` (lines 117–119): Persist a hashed definition to the local object store
- `lookup_def t impl_hash` (lines 121–137): Retrieve from local cache, or global cache with local warming
- `compilation_hash impl_hash ~target ~flags` (lines 139–141): Compute derivative hash for artifacts
- `store_artifact t ch path` (lines 143–147): Map compilation_hash → artifact path
- `lookup_artifact t ch` (lines 149–154): Find compiled artifact by compilation_hash
- `lookup_name t name` (lines 156–157): Index-based lookup by definition name
- `update_index t entries` (lines 159–160): Batch-update the in-memory name→def_id index
- `gc t ~keep_defs ~keep_artifacts` (lines 162–200): Garbage collect unreferenced objects

### Hash Module: `lib/cas/hash.ml` (22 lines)

Computes content-based hashes for function definitions.

**Type:**
- `hashed_fn` (lines 5–8): Carries `sig_hash` (signature only) and `impl_hash` (full definition)

**Public API:**
- `hash_fn_def fd` (lines 15–21):
  - Serializes function signature to compute `sig_hash`
  - Appends full implementation and hashes both to compute `impl_hash`
  - Chaining: `impl_hash = BLAKE3(sig_hash_bytes ++ full_impl_bytes)` ensures that signature changes are always detected

### BLAKE3 Module: `lib/cas/blake3.ml` (23 lines)

FFI wrapper around libblake3 C stubs.

**Public API:**
- `hash bytes` (line 9): Compute BLAKE3 digest of bytes, return as 64-char lowercase hex string
- `hash_string s` (line 12): Convenience wrapper for string input
- `hash_concat parts` (lines 15–22): Efficiently hash multiple byte sequences by concatenating and hashing

### Serialization Module: `lib/cas/serialize.ml` (310 lines)

Canonical deterministic serialization of TIR nodes suitable for hashing. **No spans, source locations, or comments—structural content only.**

**Format version:** 1

**Encoding rules:**
- All multi-byte integers: little-endian
- Record/map fields: alphabetically sorted before serialization
- Prefix-free encoding: every construct unambiguously decodable

**Type constructor tags (u8):** TInt (0x01), TFloat (0x02), TBool (0x03), TString (0x04), TUnit (0x05), TTuple (0x06), TRecord (0x07), TCon (0x08), TFn (0x09), TPtr (0x0a), TVar (0x0b)

**Buffer helpers (lines 72–90):**
- `buf_u8 buf n`: Write single byte
- `buf_u32_le buf n`: Write 32-bit little-endian
- `buf_i64_le buf n`: Write 64-bit little-endian
- `buf_f64_le buf f`: Write 64-bit float as bits
- `buf_string buf s`: Write length-prefixed string

**Recursive serializers (lines 94–264):**
- `write_ty buf ty` (lines 94–126): Serialize types recursively
- `write_atom buf a` (lines 156–167): Atoms (variables, literals, def references). **Crucially, ADefRef serializes only the hash, not the name**, allowing name-independent content addressing.
- `write_expr buf e` (lines 169–251): Expressions; notably ELetRec sorts by name for canonical order
- `write_fn_def buf fd` (lines 259–264): Full function definition
- `write_fn_sig buf fd` (lines 268–272): **Signature-only** (name, param types, return type; excludes body and variable names)

**Public API (lines 281–310):**
- `serialize_fn_sig fd`: Returns bytes for signature hashing
- `serialize_fn_def fd`: Returns bytes for full implementation hashing
- `serialize_type_def td`: Serializes variant, record, or closure types

### Pipeline Module: `lib/cas/pipeline.ml` (97 lines)

Orchestrates CAS integration with the compilation pipeline. This is **Phase 6** of the March compilation chain.

**Type:**
- `hashed_scc` (lines 20–27):
  - `HSingle { hs_hdef }`: Single non-recursive definition
  - `HGroup { hg_hash; hg_hdefs }`: Mutually-recursive group with group hash = BLAKE3(concat all member impl_hashes)

**Public API:**
- `hash_module m` (lines 38–68):
  - Computes SCCs of all functions in a TIR module
  - Hashes each definition and groups
  - Returns SCCs in topological order (dependencies before dependents)

- `compile_scc store ~target ~flags ~compile h_scc` (lines 79–97):
  - **Cache-hit fast path:** Computes `compilation_hash` from impl_hash, target, and flags; looks up artifact
  - **Cache miss:** Calls injected `compile` function and stores result
  - Stores all definitions in the CAS before returning artifact path
  - This is the key integration point: it wraps the actual compiler phases (mono → defun → llvm)

### SCC Module: `lib/cas/scc.ml` (132 lines)

Strongly-Connected Component detection for function dependency graphs using Tarjan's algorithm.

**Type:**
- `scc` (lines 15–17): `Single of string | Group of string list`

**Reference extraction (lines 24–58):**
- `refs_in_expr known e`: Collect top-level function names referenced in an expression
- Only captures EApp function variables and AVar/ADefRef atoms
- `deps_of known_names fd`: Return direct dependencies of a function definition

**Tarjan's algorithm (lines 74–132):**
- `compute_sccs fns`: Returns SCCs in topological order
- Implementation follows standard Tarjan with index counter, on-stack tracking, and SCC collection
- Result is reversed so that definitions with no dependents come first

## Compilation Integration

> **Update (March 20, 2026, Track D):** The CAS is now wired into the default compilation path in `driver.ml`. All 401+ tests pass with CAS-enabled compilation.

### Current Wiring Status

~~**In codegen:** No explicit CAS usage yet~~ → CAS is now active in the compilation pipeline.

~~**In main:** No explicit CAS invocation~~ → The driver initializes the CAS store and routes compilation through `Pipeline.compile_scc`.

The `Pipeline.compile_scc` function is now called from the driver with:
1. ✅ CAS store instantiated at compilation startup
2. ✅ Store passed to `compile_scc` along with target and flags
3. ✅ `~compile` callback defined (the actual mono → defun → llvm phases)

Cache-hit detection is active: unchanged definitions are served from the CAS without recompilation.

## Test Coverage

### `test/test_cas.ml` (589 lines)

Comprehensive test suite organized by phase:

**Phase 1: Canonical Serialization (lines 12–100)**
- `test_serialize_int_is_deterministic`: Bytes are identical across runs
- `test_serialize_distinct_types_produce_distinct_bytes`: TInt ≠ TFloat ≠ TBool
- `test_serialize_tvar_includes_name`: Type variable names affect bytes
- `test_serialize_tuple_order_matters`: (Int,Bool) ≠ (Bool,Int)
- `test_serialize_record_fields_sorted`: Fields normalized to alphabetical order
- `test_serialize_fn_def_deterministic`: Function definitions produce stable bytes
- `test_serialize_fn_def_body_changes_output`: Body changes produce different bytes
- `test_serialize_type_def_variant`: Variant types are deterministic
- `test_serialize_sig_excludes_body`: Signature bytes are identical despite body change
- `test_serialize_sig_differs_on_param_type_change`: Signature changes on type change

**Phase 2: BLAKE3 Hashing**
- Hash stability and distinctness tests for various TIR structures

**Phase 3: CAS Store**
- Object storage and retrieval
- Two-layer lookup (local, then global)
- Index management
- Artifact caching

**Phase 4: SCC Analysis**
- Tarjan algorithm correctness
- Topological ordering verification
- Self-recursive and mutually-recursive function handling

## Key Design Decisions

1. **Signature vs. Implementation Hashing:**
   - `sig_hash`: Captures interface only (name, param types, return type)
   - `impl_hash`: Chains both sig_hash and full body; changing the body always produces a new impl_hash while preserving sig_hash if only the body changes
   - This allows invalidating implementations while keeping signatures stable

2. **Two-Tier Storage:**
   - Local cache is mutable and fast
   - Global cache is a shared read-through layer for team/CI environments
   - Warming: when an object is found globally, it's copied to local cache

3. **Group Hashing:**
   - For mutually-recursive functions, the group hash is BLAKE3(concat of all member impl_hashes)
   - Preserves the invariant that changing any member invalidates the group

4. **Name-Independent Content Addressing:**
   - Serialization of ADefRef only includes the hash, not the name
   - Allows definitions to be renamed without invalidating cached artifacts
   - Names are for human readability in error messages only

5. **ANF Suitability:**
   - All TIR structures (atoms, expressions) are serializable
   - Fresh variable names (e.g., `$t42`, `$lam5`) don't affect content hashes
   - Only the structure of computation matters

## Known Limitations

1. **Type-Level Content Addressing Not Implemented:**
   - TypeDef serialization exists but is not used in hash computations
   - Type definitions are stored but not content-addressed

2. **No Automatic Artifact Eviction:**
   - The `gc` function requires explicit caller-provided lists of definitions/artifacts to keep
   - No LRU or time-based eviction strategy currently

3. **No Distributed CAS:**
   - Only file-system-based storage
   - No HTTP/REST backend for cloud caching

4. **No Incremental Compilation Hints:**
   - The CAS provides cache hits but doesn't track fine-grained dependencies
   - If a library function changes, all dependents are recompiled even if cached

5. ~~**Not Integrated with Main Compilation Loop:**~~ ✅ **FIXED** (Track D)
   - CAS is now wired into the default compilation path via `driver.ml`
   - All 401+ tests pass with CAS-enabled compilation

## Dependencies on Other Features

- **TIR Module:** CAS operands over TIR definitions (fn_def, type_def)
- **Serialization:** Requires deterministic serialization of all TIR constructs
- **SCC Analysis:** Pipeline uses SCCs to group mutually-recursive functions
- **BLAKE3 FFI:** External C bindings for cryptographic hashing
- **File I/O:** Uses Unix.mkdir, open_out_bin, open_in_bin for persistence

## Examples

### Computing a function hash

```ocaml
let fd : fn_def = {
  fn_name = "add";
  fn_params = [{ v_name = "x"; v_ty = TInt; v_lin = Unr };
               { v_name = "y"; v_ty = TInt; v_lin = Unr }];
  fn_ret_ty = TInt;
  fn_body = EAtom (AVar { v_name = "x"; v_ty = TInt; v_lin = Unr });
}

let h = Hash.hash_fn_def fd
(* h.sig_hash = BLAKE3(serialized signature)
   h.impl_hash = BLAKE3(h.sig_hash_bytes ++ serialized body) *)
```

### Storing and retrieving a definition

```ocaml
let store = Cas.create ~project_root:"/home/user/myproject"
let hdef : Cas.hashed_def = {
  hd_sig_hash = h.sig_hash;
  hd_impl_hash = h.impl_hash;
  hd_def = Cas.FnDef fd;
}
Cas.store_def store hdef
(* Stored at: /home/user/myproject/.march/cas/objects/XX/YY... *)

match Cas.lookup_def store h.impl_hash with
| Some hdef -> printf "Found: %s\n" hdef.hd_sig_hash
| None -> printf "Cache miss\n"
```

### Computing a compilation hash

```ocaml
let ch = Cas.compilation_hash h.impl_hash ~target:"native" ~flags:["-O2"; "-flto"]
(* ch = BLAKE3(h.impl_hash ++ "native" ++ "-O2" ++ "-flto") *)

Cas.store_artifact store ch "/path/to/compiled_add.o"
match Cas.lookup_artifact store ch with
| Some path -> printf "Artifact found at: %s\n" path
| None -> printf "Artifact cache miss\n"
```
