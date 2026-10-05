# [P3] DD step 12: the local reload socket is created without an explicit mode (owner-only only by umask)

**Review:** `specs/progress/2026-10-04-dd12-security-review.md`.

## What breaks

The reload server's Unix socket is `bind()`ed with no `fchmod`/`chmod` and no
restrictive `umask` set first (`runtime/march_reload.c:2879-2890`):

    int srv = socket(AF_UNIX, SOCK_STREAM, 0);
    ...
    unlink(g_socket_path);
    if (bind(srv, (struct sockaddr *)&addr, sizeof(addr)) < 0) { ... }

The socket's permission bits are therefore `0777 & ~umask` of whatever started
the node. Connecting to a Unix socket requires **write** permission on the socket
inode. Under the common `umask 022` the socket is `0755` (observed:
`srwxr-xr-x`), so other local users cannot connect — fine. But a node launched
under `umask 002` or `umask 000` (not unusual under some service managers,
containers or CI shells) yields `0775`/`0777`, and then **any local user can
connect** to the reload socket and reach every signed/unsigned verb — including
the CAS poisoning in the P1 todo and (pre-release) unwrapped signed `ACTIVATE`.

This is an environment-dependent latent exposure, not an unconditional one, hence
P3: it only bites when the deploying environment has a permissive umask.

## Evidence

Code: no `chmod`/`fchmod`/`umask` between `socket()` and `bind()`
(`runtime/march_reload.c:2879-2904`; grep for `chmod|fchmod|umask` in the file
returns none). In the P1 repro the socket came up `srwxr-xr-x` purely because the
reviewer's shell umask was 022.

## Suggested fix (not applied)

`fchmod(srv, 0700)` (or `chmod(g_socket_path, 0700)` immediately after `bind`), or
bracket the `bind` with `umask(0077)`, so the socket is owner-only regardless of
the inherited umask. A `SO_PEERCRED`/`LOCAL_PEERCRED` uid check on accept would be
belt-and-braces.

## Resolution (2026-10-04, fixed)

`reload_server_thread` now `chmod`s the socket to `0600` between `bind` and
`listen`. Nothing can connect before `listen`, so no connection is ever accepted
under the inherited mode, and a failed `chmod` closes the server instead of
serving. As belt-and-braces, `accept` drops a peer whose uid is neither the
process's nor root's (`getpeereid` on macOS, `SO_PEERCRED` on Linux).
`test/test_reload_activate4.c` starts the server under `umask(0)` and asserts
mode `0600`. With the `chmod` disabled it fails with `mode: 777`.
