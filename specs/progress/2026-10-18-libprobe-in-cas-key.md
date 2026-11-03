# The host library probe is part of the CAS key (static-output design, Stage 0)

Landed 2026-10-18. Stage 0 of `specs/2026-09-23-static-compile-output-design.md`, under the
still-open `specs/todos/2026-09-02-march-compile-output-is-not-static.md`.

**The defect.** A native `march --compile` probes the build host for OpenSSL (Homebrew
prefixes, else `pkg-config`) and for the zstd and brotli headers. The result decides the
binary's dependency set and, for zstd/brotli, whether those codecs work at all
(`-DMARCH_HAVE_ZSTD` / `-DMARCH_HAVE_BROTLI`, else stubs that return `Err` at run time).
The runtime OBJECT cache keyed on it, but the whole-binary key (`build_cas_key`) did not,
and the whole-binary lookup runs first. Measured in the design (§2.4): with `zstd.h` hidden,
a rebuild printed `compiled … (cached)` and served the binary linked against libzstd; with
the artifacts cleared, the same source built a binary that prints `zstd unavailable`.

**The fix.** The two probes moved out of the link step into `openssl_probe_flags` and
`compress_probe_flags` (`bin/main.ml`, lazy, run once per invocation), which the link
command now forces, and `build_cas_key` adds a `libprobe:<digest of both>` tag. A cross build
leaves it out: it links against the sysroot, which `xsysroot:` already covers.

**Test.** `test/test_cas_b7.ml`, "Stage 0: the host library probe is part of the CAS key":
two compiles of one program in one project, the second with `MARCH_TEST_LIBPROBE_ROOT`
pointing at an empty directory (a test hook that prefixes every probed header path and
skips `pkg-config`, so the probe finds nothing without touching the host). The keys must
name the probe and differ, and the second build must not be `(cached)`. Red with the tag
dropped from `cas_flags`, green with it, macOS arm64.

Every existing CAS entry is invalidated once, by the new tag.
