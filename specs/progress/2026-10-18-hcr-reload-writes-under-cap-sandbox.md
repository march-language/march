# `[P3]` `--hot-reload --cap-sandbox`: the reload server's writes need `IO.FileWrite`

Filed 2026-10-18, the part of
`specs/progress/2026-09-30-hcr-reload-listener-races-cap-sandbox-install.md` that its
fix left open.

The reload listener is now bound before `march_sandbox_install`, so a sandboxed
hot-reloadable program keeps its reload, shell and observe sockets. But what the
server DOES on a deploy still runs under the program's filter: `CAS_PUT` writes the
artifact into `~/.march/cas` (`open(... O_WRONLY | O_CREAT ...)`, `rename`, `unlink`),
`ACTIVATE*` writes the activation and release state under `hcr_state/`, and the audit
log is appended. With `IO.FileWrite` withheld (Linux `MARCH_CAP_DENY_WRITE`, macOS SBPL
file-write deny) each of those fails, so a deploy to the program answers
`ERR write_failed` (or fails later) even though the listener is up.

Options, an HCR-owner decision:

1. Scope it: the sandbox profile always allows writes under the CAS root and the
   service's state directory when the program is built with `--hot-reload`, the way
   a scoped `IO.FileWrite` already becomes a Seatbelt `subpath` / is refused on Linux
   (Linux seccomp cannot filter on paths, so it would need Landlock, or a pre-opened
   directory fd and `openat` relative to it, which seccomp can allow by fd).
2. Document it: a sandboxed hot-reloadable program must grant `IO.FileWrite`, and the
   compiler warns when `--hot-reload --cap-sandbox` is given without it.

Test either way: extend the `--hot-reload --cap-sandbox` case in
`test/test_cap_sandbox_runtime.ml` with a `CAS_PUT` of a small blob.

## Completed 2026-10-31

The owner selected option 2: require the existing effective `IO.FileWrite`
grant; do not weaken either OS filter. The compiler warns for
`--compile --hot-reload --cap-sandbox` without that capability, naming CAS
upload, activation state, and audit writes. The diagnostic uses the existing
replay log so a cached build repeats it. Read-only reload queries stay available.
As with the existing sandbox derivation, an unused `needs` declaration alone
does not add an effective capability; the granted regression fixture actually
uses `file_write`.

`test/test_cap_sandbox_runtime.ml` now exercises a real `CAS_PUT` under both
grant states, with isolated runtime HOME directories. Missing grant returns
`ERR open_failed`, leaves `CAS_CHECK` missing, and creates no artifact; a held
grant returns `OK`, makes the artifact present, and preserves its exact bytes.
Both cases retain PING and observe-socket checks, verify unchanged RELEASE_HEAD,
and compile twice to cover diagnostic replay.

Validation: the missing-warning assertion failed before the diagnostic was
added. The two focused cases subsequently passed on macOS (43.601 seconds).
Linux cases are enabled by the same test but were **not run locally**: this host
is Darwin and the installed Docker CLI has no running daemon. Seccomp validation
remains a Linux CI responsibility; the macOS result is not Linux evidence.
