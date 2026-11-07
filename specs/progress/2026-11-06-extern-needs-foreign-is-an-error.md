# `extern_needs_foreign` is an error, not a warning

**Problem.** A module with an `extern` block that did not declare `needs IO.Foreign` only got a
warning (Check 1c in `lib/typecheck/typecheck_caps.ml`), and it compiled. `forge audit` reads
`needs` declarations, so such a dependency reached C while its recorded capability set and
`forge.caps.lock` showed nothing. `docs/capability-audit.md` listed it as "Partly" covered.

**Fix.** Check 1c now reports with `Err.error_with_fix`. Message, code and the
`needs IO.Foreign` insert fix are unchanged. A module that declares `IO.Foreign` (or `IO`)
is unaffected; `IO.Foreign` covers `IO.Foreign.Blocking`.

**Blast radius, measured.** Declaring only the extern's own `Cap(X)` (`needs Ffi`, `needs LibC`)
does NOT satisfy this check: it asks for `IO.Foreign` whatever the block's cap is called. An
audit of every `.march` file with an `extern` block found 36 that already declare
`IO.Foreign`/`IO`, and 3 that did not: the JS-target `stdlib/dom.march` (`Js.Dom`),
`audio.march` and `canvas.march`, which declared `needs Ffi` only. Each now also declares
`needs IO.Foreign`. (An earlier note in this file assumed `needs Ffi` exempted them; it did not,
and `march --check stdlib/dom.march` failed until they were fixed.) Inline programs in
`test/test_refinecheck.ml` (three) and `test/test_codegen.ml` (one) had the same gap and were
fixed the same way.

**Changed.** `stdlib/{dom,audio,canvas}.march`; `test/test_compiler.ml`
(`test_cap_body_*foreign*` now assert the error, including the "no error" cases, which would
otherwise have passed vacuously); `test/errors/no_extern_violation_1.*` goldens (now two errors, the extern one
first); comments in that fixture and `specs/lang/types/reject/t44_cap_no_extern_extern_block.march`;
`specs/lang/` (threat model, `core-march-types.md` Check 1c, `capabilities.md`) with the
regenerated `docs/` chapters; hand-written `docs/ffi.md` and `docs/capability-audit.md`
(its threat-model row is now "Yes").

**Not done.** The suggested fix for a `cap no_extern` module still says to add `needs IO.Foreign`,
which `no_extern_violation` then rejects; the right fix there is to remove the `extern` block.
