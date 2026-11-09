# Narrower capabilities: environment, programs, listening, C, tables, console, task limits

**Date:** 2026-11-09
**Status:** approved 2026-11-09; revised the same day after a builder check (§14 lists what changed)
**Builds on:** host/method/path scopes on `IO.NetConnect` (#1213, #1216), and the
dependency-grants design and roadmap (`specs/2026-11-09-dependency-grants-and-restrict-design.md`,
`specs/plans/2026-11-09-grants-restrict-roadmap.md`, on `main` once #1216 merges).

Every capability other than network and files is all-or-nothing today. A dependency
granted `IO.Process` can read every environment variable and run any program, including
a shell, which makes every other scope bypassable. This design gives each of them the
same `needs X("...")` / `grant = ['X("...")']` shape that hosts and paths already have.

```toml
[deps]
weather   = { version = "2.0", grant = ['IO.NetConnect("api.weather.test/v1/", methods(get))',
                                        'IO.Env("WEATHER_API_KEY")'] }
grep_tool = { version = "1.0", grant = ['IO.Exec("rg", "fd", "jq")', 'IO.FileRead("/srv/data")'] }
sqlite    = { version = "3.1", grant = ['IO.Foreign("libsqlite3")', 'IO.FileWrite("/srv/db")'] }
```

---

## 1. Why

The owner's driving case: **"I don't want a dependency that does FFI reading env vars"**
(owner, 2026-11-09). Secrets live in the environment; a dependency that can reach C can
call `getenv` without the compiler ever seeing it. And dependencies routinely **shell out
to Unix tools** (owner), so running programs must be scoped in a way that stays usable,
not just refused.

## 2. Goals, non-goals, anti-goals

**Goals**

- Split `IO.Process` into finer capabilities, each scopable (§3).
- **Environment variables are a guarded store**: C code (`getenv`) and child processes see
  none of them unless allowed (§4). A dependency reads its own configuration under its
  grant (owner: better ergonomics than the app passing values in).
- **Programs are scoped by name**, with tools that run other code refused unless marked
  (§5). Under the OS sandbox, each child process is confined to the authority of the code
  that started it (owner: "confine them to the OS sandbox when we're using that").
- Scopes for listening (§6), C libraries and symbols (§7), shared tables (§8), the console
  (§9), and a task limit (§10).
- The same forms work in a module's `needs`, in a dependency `grant`, and in a `restrict`
  block, once those exist (the grants design).
- Existing programs keep compiling: an unscoped capability still means everything, and the
  old broad names still cover the new narrow ones (§3).

**Non-goals**

- Making C safe. `IO.Foreign` scopes say which C a dependency may reach; what that C does is
  out of reach without a separate process.
- Judging a child program's arguments as a security boundary (§5).
- `IO.Signal` and `IO.Database` scopes (low value; `IO.Database` has no builtins yet).

**Anti-goals**

- An environment scope that C code walks around with `getenv`.
- A program allowlist that grants everything once it lists `sh`, `env` or `python`.
- A child process that silently has more authority than the code that started it, when
  the sandbox is on.

## 3. The capability lattice

New capabilities split `IO.Process`; the old name stays their parent, so
`needs IO.Process` keeps meaning all of them:

```
IO.Process
├── IO.Env        read and set environment variables
├── IO.Exec       start child processes
└── (cwd, argv, pid, exit stay under IO.Process itself)
```

Builtin mapping: `process_env`, `process_set_env` → `IO.Env`; `process_spawn_sync`,
`process_spawn_lines`, `process_spawn_async` and the handle operations on a spawned
process → `IO.Exec`. `runtime/march_cap_lattice.{h,c}` is regenerated from
`Cap_lattice.hierarchy` (`lib/caps/emit_c_table.ml`).

Each scope argument is parsed like host scopes: stored in the `needs` scope string, checked
by the typechecker's declaration check, carried per module, and judged at compile time when
the argument at the call is a literal and at run time otherwise (the run-time authority
context, roadmap phase 4).

## 4. Environment variables (`IO.Env`)

```march
needs IO.Env("DATABASE_URL", "PORT")      -- these names only
needs IO.Env(prefix("WEATHER_"))         -- any name starting with WEATHER_
needs IO.Env                             -- all of them (today's meaning)
```

- **The guarded store.** At program start the runtime copies the environment into private
  storage, **clears the process environment, and overwrites the original environment
  block** (the strings the kernel placed on the stack), so neither `getenv` nor
  `/proc/self/environ` nor a scan of that block finds a value afterwards. From then on the
  only way to read a variable is `Process.env(name)` (and the stdlib wrappers over it),
  which checks the caller's `IO.Env` scope. `Process.set_env` writes the store, not the
  process environment.
- **The runtime's own reads.** The C runtime reads about thirty variables lazily after
  startup (`MARCH_*`, `HOME`, `TMPDIR`, `PATH`), and OpenSSL reads its certificate
  variables (`SSL_CERT_FILE`, `SSL_CERT_DIR`). These read the store through a
  runtime-internal accessor that is not checked (it is the runtime, not user code) and is
  **not callable from `extern` blocks** (§7). OpenSSL's variables are copied to the
  C-visible list when set, since OpenSSL calls `getenv` itself (my call).
- **C still needs a few.** A short, documented list stays in the real process environment
  because the C library reads them for time zones and locale: `TZ`, `LANG`, `LC_ALL` and
  the `LC_*` family (my call). The project can change the list in `forge.toml`
  (`[env] visible_to_c = [...]`); the builder picks the exact spelling.
- **Children get only what they are given.** Today the spawn builtins take no environment
  and a child inherits the whole process environment; they gain an environment parameter
  (`Process.run(cmd, args, env: [...])`, new). A child starts with the C-visible list,
  **the cleaned `PATH` (§5) and `HOME` by default** (owner, 2026-11-09: most tools break
  without them), plus the variables passed explicitly at the call, each of which the caller
  must be allowed to read.
- **Reading a variable is checked by name**: a literal name at compile time, any name at run
  time. A variable that is not set and one that is out of scope are different results,
  never a silent `None` (a dependency should not mistake "you may not" for "unset").
  `Process.env` returns `Option` today; until every capability operation returns a `Result`
  (roadmap phase 2), **an out-of-scope read panics** with a message naming the variable and
  the scope (owner, 2026-11-09). From phase 2 it is an error value.
- **Computed names.** The stdlib reads variables with computed names (`Config`, `Env`,
  `Check`, `Topology`, `SessionNode`). Those are judged against the calling module's scope at
  run time (phase 4); until then a computed name fails closed **only in a module that has an
  `IO.Env` scope** — unscoped modules are unaffected.
- **What remains.** With the original block overwritten, the values live only in the store.
  **Honest limit:** C code that finds and reads the store in the process's memory still gets
  them; only a separate process stops that. The store's accessors are hidden from `extern`
  blocks (§7), so reaching it takes deliberate memory scanning, not a declared call.
- **Every runtime.** Compiled binaries (C runtime, at startup before user code), the
  interpreter (the OCaml process environment), the JIT, and the JS target (`process.env`),
  per the owner's "the same everywhere" rule. **JS limit:** JS `extern` code can still reach
  the environment through `require('child_process')` or by starting its own processes; the
  JS target documents this, as `IO.Foreign` there is equivalent to unrestricted.

## 5. Running programs (`IO.Exec`)

```march
needs IO.Exec("rg", "fd", "jq")
needs IO.Exec("git", args("status", "log", "diff", "rev-parse"))
needs IO.Exec(unrestricted("sh"))
needs IO.Exec                             -- any program (today's meaning)
```

- **By name.** A name is resolved against the `PATH` captured at program start (it lives in
  the guarded store, so a dependency cannot change it without `IO.Env` to `PATH`). The
  captured `PATH` is **cleaned**: empty entries (which mean the current directory in
  `spawn_resolve_path`) and relative entries are dropped. The resolved absolute path is what
  runs; an absolute name in the scope (`/usr/bin/rg`) is matched exactly. A program started
  by any other name or path is refused. Limit, documented: a dependency that can write into
  a directory on `PATH` can plant a program there; file-write scopes are what stop that.
- **No shell in between.** `Process.run(command, args)` already passes arguments directly;
  that stays the only form.
- **Tools that run other code** are refused even when listed, unless marked
  `unrestricted(...)`, because granting them is granting everything: shells (`sh`, `bash`,
  `zsh`, `dash`, `ksh`, `fish`), `env`, `xargs`, `nohup`, `sudo`, `doas`, `timeout`,
  `nice`, `stdbuf`, `watch`, `parallel`, `script`, `ssh`, and interpreters (`python*`,
  `perl`, `ruby`, `node`, `deno`, `bun`, `php`, `lua`, `tclsh`). The list is documented and
  kept deliberately short; it is a guard against the obvious escapes, not a proof that
  other tools (`find -exec`, `awk`'s `system()`, `git` hooks) cannot run code. Those are
  what child confinement is for.
- **`args(...)`** is an optional first-argument allowlist for tools with subcommands. It is
  a guard against mistakes, not a security boundary: flags are too varied to judge.
- **Child confinement under the OS sandbox** (owner). "The OS sandbox" here is the
  in-binary one (`--cap-sandbox`: seccomp on Linux, `sandbox_init` on macOS); forge's
  external one (`forge cap run`) confines children the same way because it wraps the whole
  process. Both are inherited and can only narrow, so every child is already held to the
  program's sandbox.
  - **Per-child narrowing, Linux only** (owner, 2026-11-09). Spawning uses `posix_spawn`
    (`runtime/march_runtime.c`), which gives no hook in the child before `exec`, so the
    runtime starts a small helper program instead; the helper narrows itself to **the
    authority of the code that started the child**, then `exec`s the real program. On Linux
    the narrowing is a stricter seccomp filter plus Landlock path rules (Landlock is new
    work: the in-binary sandbox uses seccomp only today). So the child of a dependency
    granted `IO.Exec("rg")` and `IO.FileRead("/srv/data")` reads only under `/srv/data`
    (plus a fixed baseline: its own binary, shared libraries, `/etc` locale and resolver
    files, `/dev/null`) and has no network. On macOS a sandboxed process cannot apply a
    second, narrower profile, so children get only the program-wide sandbox; the docs say
    so.
  - **Knowing whose authority** a child gets needs the run-time authority context (the call
    goes through stdlib `Process.run`), so per-child narrowing ships **after roadmap phase 4**.
  - **A child cannot attack its parent:** the narrowed filter denies `ptrace`,
    `process_vm_readv`/`process_vm_writev` and `kcmp` against other processes, and every
    file descriptor not explicitly passed is closed before `exec` (a socket opened by C code
    would otherwise defeat "no network").
  - A child may still `exec` further programs (git hooks, pagers need it); they inherit its
    narrowed sandbox.
  - Limits: the network is all-or-nothing for a child (the OS cannot filter hosts); without
    the sandbox, children are not confined, and the docs say so.

## 6. Listening (`IO.NetListen`)

```march
needs IO.NetListen("127.0.0.1:8080")
needs IO.NetListen(port(8000..8099))
needs IO.NetListen("0.0.0.0:443")
```

An address (IPv4, bracketed IPv6, `localhost`) and port, or a port range on any address.
Today `tcp_listen` takes only a port and binds every interface (`runtime/march_http.c`), and
the HTTP servers use a global bind host; listening gains an address parameter (new
signatures, my call), and the scope checks the address and port, at compile time for
literals and at run time otherwise. At the OS layer, `--cap-sandbox` already enforces
`IO.NetListen` on Linux by denying `bind`/`listen` outright when it is withheld; the address
and port within a granted `IO.NetListen` are not OS-enforced (seccomp cannot see them).

## 7. C libraries and symbols (`IO.Foreign`)

```march
needs IO.Foreign("libsqlite3")
needs IO.Foreign("libsqlite3", symbols("sqlite3_open", "sqlite3_exec", "sqlite3_close"))
```

Checked at compile time against the module's `extern` blocks. Linking resolves names
globally, so naming the library is not enough: **every declared symbol is checked**
(`IO.Foreign("libsqlite3")` without `symbols(...)` admits any symbol the library's own
headers would, judged by a symbol list the builder generates per library or the author
supplies; my call: without a list, any symbol, and the docs say a library scope alone is
documentation, not a boundary).

Some symbols are refused under **any** `IO.Foreign` scope unless the scope names them
explicitly, because they bypass the other capabilities: the runtime's own entry points
(`march_*`, including the environment store's accessors and the spawn builtins), and C's
environment and process functions (`getenv`, `setenv`, `environ`, `execve`, `execvp`,
`posix_spawn*`, `fork`, `system`, `popen`, `dlopen`, `dlsym`). The runtime's internal symbols
are also hidden (not exported) from user `extern` blocks.

A reached `extern` outside the scope is a build error. This shrinks and documents what C is
reachable; it cannot make C safe, and C reached this way is still outside every other scope
except the environment store (§4) and the OS sandbox.

## 8. Shared tables (`IO.Mut`)

```march
needs IO.Mut("sessions", "rate_limits")
```

Vault tables by name. Creating or finding a table by name (`Vault.new`, `open`, `whereis`)
and every **write** are checked against the names: a literal at compile time, a computed
name at run time, so the runtime records each handle's table name. **Reads through a handle
you already hold stay allowed** (my call): reads are deliberately uncapped today
(`vault_get`, `vault_keys`, `vault_size`), and holding the handle is the authority someone
gave you. This closes the threat model's "handle minted from a name" gap: a module cannot
open another module's table by guessing its name.

## 9. Console (`IO.Console`)

```march
needs IO.Console(stderr)
```

`stdout` and/or `stderr`. A library limited to `stderr` cannot corrupt a command-line
program's output. Checked at compile time from the builtin called. Some output builtins carry
no capability today (`print_int`, `print_float`, `logger_write`); they are classified as
`IO.Console` writes to their stream as part of this work.

## 10. Task limit (`IO.Spawn`)

```march
needs IO.Spawn(max(16))
```

A cap on concurrent tasks **and actors** started by the module's (or dependency's) code
(my call: both are concurrent work), enforced at run time by the authority context:
spawning past the limit is an error value, never a crash.
This is the first **limit** rather than a **scope**; memory, CPU time and request rates
would follow the same shape later.

## 11. Fit with the roadmap

| Piece | Needs | Can ship |
|---|---|---|
| Lattice split (`IO.Env`, `IO.Exec`), builtin remap | — | now |
| Literal-argument checks at compile time (env names, exec names, listen addresses, foreign symbols, table names, console streams) | lattice split | now, for module `needs` |
| Guarded environment store, in every runtime (out-of-scope read panics until phase 2) | — | now (independent) |
| Exec name resolution, refusal list | lattice split | now |
| Run-time checks for computed arguments; task limit | run-time authority context (phase 4) | after phase 4 |
| Per-child sandbox narrowing (Linux) | run-time authority context (phase 4), Landlock | after phase 4 |
| `IO.Foreign` symbol refusal list, hidden runtime symbols | — | now |
| Dependency grants and `restrict` with these forms | grants (phase 7), `restrict` (phase 6) | with those |

Until phase 4, a scope whose argument the compiler cannot see is refused (fail closed),
as host scopes do.

## 12. Testing (shape)

- Environment: a C `extern` calling `getenv("SECRET")` sees nothing; a child process sees
  only passed variables; an out-of-scope read is an error value naming the variable; the
  C-visible list (`TZ`, `LANG`) still works for time formatting; the same on every backend.
- Exec: an unlisted program refused; `sh` listed without `unrestricted` refused; `PATH`
  cannot be changed by a dependency without `IO.Env("PATH")`; under the sandbox on Linux a
  child of a file-scoped grant cannot read outside it and has no network.
- Listen, Foreign, Mut, Console: literal violations are build errors; computed ones refused
  until phase 4, then checked at run time.
- Backward compatibility: every existing program compiles and behaves the same
  (`scripts/ir-oracle.sh`, `scripts/types-oracle.sh`), apart from the environment store,
  which is a deliberate behaviour change for C code (CHANGELOG `### Changed`).

## 13. Left to the builder

Option spellings inside each scope (`prefix(...)`, `port(a..b)`, `symbols(...)`); the
`forge.toml` key for the C-visible environment list; how the per-child sandbox profile is
built; the error variants each refusal returns.

## 14. Revisions after the builder check (2026-11-09)

- Owner's answers: per-child narrowing is Linux-only; a child gets the cleaned `PATH` and
  `HOME` by default; an out-of-scope environment read panics until phase 2.
- Corrected facts: the spawn builtins take no environment today (a parameter is new work);
  Landlock is not used yet; `IO.NetListen` is already OS-enforced on Linux (only address and
  port are not); some console output builtins carry no capability; overwriting the original
  environment block empties `/proc/self/environ`, so the limit is narrower than first stated.
- Escapes closed: `extern` blocks cannot reach the runtime's internal symbols or C's
  environment and process functions unless named; library scopes check every symbol;
  empty and relative `PATH` entries are dropped; a confined child cannot `ptrace` or write
  its parent's memory and inherits no stray descriptors; the JS target's limit is documented.
- My calls: the runtime's own variable reads go through the store unchecked; computed names
  fail closed only in scoped modules; listening gains an address parameter; Vault reads
  through a held handle stay allowed; the task limit counts actors.
