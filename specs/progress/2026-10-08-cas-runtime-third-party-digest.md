# CAS runtime digest includes nested sources

The runtime identity now recursively hashes every `.c` and `.h` file below the
runtime directory, using sorted relative paths and file contents.  This makes
changes under `runtime/third_party/` invalidate both the precompiled-runtime
object cache and the compiled-binary CAS key.

The walk follows symlinked runtime files and directories, tracks visited
canonical directories to avoid cycles, and hashes the path through which each
source is compiled.  Focused CAS regressions cover edits to nested vendored
sources and to sources reached through file and directory symlinks.

Verified with:

```sh
dune build --root . test/test_cas.exe
_build/default/test/test_cas.exe test cas_store 5-7 -e
```
