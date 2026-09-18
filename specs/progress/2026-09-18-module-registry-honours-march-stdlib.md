# FIXED 2026-09-18: `Module_registry.find_stdlib_dir` ignored `MARCH_STDLIB`

Found while verifying `2026-09-18-cap-ceiling-rooted-stdlib-namesakes.md`.

## Symptom

`forge/test/test_cap_sandbox.ml` case 11 ("scaffolded app builds clean") failed
locally on macOS. `forge new` and `forge check` passed, and `forge build` exited 1
with:

    march: error: `ConsistentHash.get` is called here returning
    `TCon(Option,[TString])`, but its body could not be specialized ...

This is the `Mono.Repr_disagreement` guard from #514, raised on a stdlib module
that the scaffolded hello-world app never calls. The test sends its output to
`/dev/null`, so reproducing it by hand was the only way to see this.

The failure was identical with `origin/main`'s `bin/main.ml` and
`bin/toolchain.ml`, so it was not caused by the cap-ceiling change it surfaced
next to.

## Cause

The compiler has two stdlib resolvers.

- `Toolchain.find_stdlib_dir` (bin/toolchain.ml) consults `MARCH_STDLIB` first.
  The eager stdlib (`stdlib_file_list`) is loaded from it.
- `Module_registry.find_stdlib_dir` (lib/modules/module_registry.ml) consulted a
  `_stdlib_dir` ref, then exe-relative and CWD-relative candidates. Its doc said
  the ref was "set by the compiler entry point", but nothing set it.

They disagree whenever `MARCH_STDLIB` is the only way to find the stdlib. That
happens when `march` is invoked through a PATH symlink: on macOS,
`Sys.executable_name` is then the link's path, so every exe-relative candidate
misses. Forge's hermetic test toolchain works exactly that way: it symlinks the
built `march` into a temp `bin/` and exports `MARCH_STDLIB`. The eager stdlib
loaded, the registry found no stdlib, and the build failed.

Reduced to one command, with nothing from forge:

    MARCH_STDLIB=<repo>/stdlib MARCH_RUNTIME_DIR=<repo>/_build/default/runtime \
      <symlink to main.exe> --compile --opt 0 -o out hello.march

It exited 1 before the fix and exits 0 after it, printing `Hello from appy!`.
The same compile with the real (non-symlinked) binary passed either way.

## Fix

`Module_registry.find_stdlib_dir` consults `MARCH_STDLIB` after the explicit ref
and before its own candidates, the same precedence as `Toolchain.find_stdlib_dir`.

## Not established

CI runs `dune runtest`, including this forge suite, on both `macos-15` and
`ubuntu-24.04`, and `main` was green there. Why the macOS runner did not hit this
is unknown. On Linux, OCaml resolves `Sys.executable_name` through
`/proc/self/exe`, which follows the symlink, so the Linux leg would not be
expected to fail. The guarding test is `cap_sandbox 11`, which goes red without
the fix on this machine.
