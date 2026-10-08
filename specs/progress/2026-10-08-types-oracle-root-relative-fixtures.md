# Type oracle fixture paths are worktree-independent

**Fixed 2026-10-08.** `scripts/types-oracle.sh` discovered fixtures by their
absolute paths and passed those paths to `--emit-core-ast` and `--check`.
Derived declarations include their input span in a synthetic-span salt, so the
Tier 1 JSON hash changed between otherwise-identical worktrees.

The per-fixture worker now strips the repository prefix and invokes both
commands from the repository root. The compiler consequently sees the same
root-relative source path in every worktree.

**Targeted verification:** `test/native/nested_derive_json.march`, which
contains derived declarations, produced different normalized Tier 1 hashes
when invoked by absolute versus root-relative path before this change. Two
root-relative invocations now produce the same SHA-256 hash; `bash -n
scripts/types-oracle.sh` also passes.
