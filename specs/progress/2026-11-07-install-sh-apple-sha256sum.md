# install.sh: checksum step works with Apple's /sbin/sha256sum (2026-11-07)

GitHub #1182. On macOS 27 `/sbin/sha256sum` (text_cmds, a hard link to
`/sbin/md5`) is on the default `PATH`, so `install.sh` picked it over `shasum`.
With `-c` and no file operand Apple's tool prints usage and exits 1, where GNU
`sha256sum` reads the checklist from stdin. The installer piped the checklist
with no operand, so every macOS install failed at "Verifying checksum".

## Fix

Both `SHACHECK` commands now end in `-`, the explicit stdin operand, which GNU
`sha256sum`, Apple's `sha256sum` and Perl `shasum` all accept.

## Verification

On macOS: `/sbin/sha256sum -c --ignore-missing -` and
`shasum -a 256 -c --ignore-missing -` both exit 0 on an intact file and 1 on a
tampered one (checklist piped through `grep`, as `install.sh` does).
