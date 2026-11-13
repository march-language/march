`[P4]` macOS refuses every symlink beneath a `File.Dir`, even one that stays inside (2026-11-13)

Ocap phase 2b. Linux resolves `File.open_in` / `open_write_in` / `list_in` through `openat2(RESOLVE_BENEATH | RESOLVE_NO_MAGICLINKS)` and follows a symlink whose target stays inside the directory. macOS has no equivalent, so it walks the path with `O_NOFOLLOW` on every component and reports any symlink as `Escapes(rel)`. This is documented behaviour (owner decision 2026-11-10), not a bug: a tree with in-tree symlinks works on Linux and is refused on macOS.

Reopen if macOS gains an `openat2`-equivalent (`O_RESOLVE_BENEATH` for `openat` exists in newer XNU; check before relying on it), which would let the two platforms agree.

Source: runtime/march_file_beneath.c; `File.open_in` in stdlib/file.march; CHANGELOG `File.Dir` entry.
