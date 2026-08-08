# forge check/build test suite un-quarantined (2026-08-08)

`forge/test/test_build_check.ml` (16 cases: 11 `forge check`, 3 `forge build`,
2 `forge test`) is back on `dune runtest`. It had been quarantined (2026-07-24)
on two problems, both now fixed.

## 1. CI/local divergence — the suite now exercises the build under test

The cases shell out to a real `march check` subprocess
(`forge/lib/cmd_build.ml`'s `check_all`, via a bare `march` command with only a
`Toolchain.path_prefix ()` PATH prefix). On a fresh CI checkout there is no
`.march-version` pin, no `~/.march/current` global symlink, and no `march` on
PATH, so `march_command` resolved to a bare `march` that did not exist — **every**
subprocess failed identically ("typecheck failed"): success-expecting cases all
failed and Error-expecting cases trivially passed, which is exactly the observed
~10/15 blanket-failure pattern on both ubuntu-24.04 and macos-15. Locally the
same suite silently exercised the *installed release* through the global symlink,
never the build under test, which is why it looked green here.

Fix: the suite is now **hermetic**. The dune rule passes the just-built compiler
as `MARCH_TEST_BIN` (`%{bin:march}`, which dune also builds), and
`setup_hermetic_march` symlinks it as `march` onto a private PATH with an empty
`MARCH_HOME` (so no global toolchain resolves and `path_prefix` stays empty →
the bare `march` in the subprocess hits our symlink). Host-independent: it works
the same in CI and locally, and it actually tests the compiler being built. If
`MARCH_TEST_BIN` is unset the suite refuses to run rather than fall back to an
ambient `march`.

## 2. A real constructor-resolution bug (case 7)

`check: stdlib shadow does not corrupt an unrelated module` failed with
`Constructor \`Bar\` is ambiguous between multiple modules: Defs.Bar / Plot.Bar`.
A bare `Bar(_)` pattern matched against a value of **known** type `Defs.Thing`
(from `match Defs.make(n) do ...`) was reported ambiguous against stdlib
`Plot.SeriesKind`'s own `Bar`.

Root cause: the resolution chain in `infer_pattern`'s `PatCon` case already
prefers a unique expected-type match first (`by_expected_unique` via
`lookup_ctor_in_type_unique`), so `ci_opt` resolved to `Defs.Bar` correctly — but
the **ambiguity diagnostic** was computed independently from the bare name alone
(candidates spanning >1 declaring module, local module owns none), ignoring that
the expected type had already disambiguated it. So the value was resolved
correctly and an error was reported anyway.

Fix (`lib/typecheck/typecheck.ml`): gate the ambiguity report on
`not resolved_by_expected_unique`, using the same `lookup_ctor_in_type_unique`
predicate the resolution chain's step 1 uses, so the diagnostic mirrors the
resolution. Genuine ambiguity — an untyped scrutinee where the expected type is a
bare `TVar` — still errors.

Verified: all 16 cases pass hermetically against the just-built compiler; a
direct repro of the type-directed case checks clean while the untyped-scrutinee
negative case still errors.
