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
