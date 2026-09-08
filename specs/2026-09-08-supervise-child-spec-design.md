# The `supervise` child spec: one syntax for restart, shutdown, and backoff

**Date:** 2026-09-08
**Status:** decided; grammar landed 2026-09-08, restart semantics landed 2026-09-08
**Supersedes the syntax section of:**
[`specs/2026-08-17-supervisor-restart-types-design.md`](2026-08-17-supervisor-restart-types-design.md)
(that doc's semantics tables and runtime analysis remain current and are not
restated here)

**Todos this must satisfy, all three at once:**

| Todo | Wants |
|---|---|
| [`2026-08-12-supervisor-restart-types-and-child-specs`](todos/2026-08-12-supervisor-restart-types-and-child-specs.md) `[P1]` | per-child `restart` type, and a `shutdown` field decided *at the same time* so "the child spec grows once, not twice" |
| [`2026-08-12-graceful-shutdown-and-drain`](todos/2026-08-12-graceful-shutdown-and-drain.md) | a per-child shutdown timeout, packaged the way OTP packages it — in the child spec next to the restart type |
| [`2026-08-11-supervisor-backoff-tuning-surface`](todos/2026-08-11-supervisor-backoff-tuning-surface.md) | `backoff base 25 cap 5000 jitter 25%` on the same block, defaulting to today's constants |

---

## 0. What is already true in the tree (verify before building)

The restart-type *syntax* shipped ahead of this doc, on 2026-08-17's design.
As of this doc's date the tree already has:

- `Ast.restart_type = Permanent | Transient | Temporary` and
  `supervise_field.sf_restart` (`lib/ast/ast.ml`);
- the `Worker w restart transient` grammar (`lib/parser/parser.mly`), with
  `restart` demoted to a soft keyword by `lib/parser/token_filter.ml`;
- lowering that emits a per-child restart int into
  `march_actor_register_child`, whose ABI already carries the fifth
  `int64_t restart_type` parameter (`lib/tir/lower_actor.ml`,
  `lib/tir/llvm_builtins.ml`);
- a `march_sup_child.restart_type` field, assigned at registration
  (`runtime/march_runtime.c`).

**And that value is read by nothing.** `grep -n restart_type
runtime/march_runtime.c` returns the declaration, the parameter, and the
store — no load. The policy is parsed, typed, lowered, transmitted across
the ABI, and stored in the supervisor's child table, where it is then
ignored. So the P1's user-visible defect — `kill()` on a supervised child
restarts it, with no way to retire one — is live in full despite the
syntax being present. That gap is what this doc's §4 closes.

## 1. The decision: trailing labelled modifiers, not an options record

The P1 names two candidate shapes. Both were written out in full before
choosing.

### Candidate A — trailing labelled modifiers (**chosen**)

```march
supervise do
  strategy one_for_one
  max_restarts 5 within 60
  backoff base 25 cap 5000 jitter 25%       -- block-level, optional
  Worker  wa                                 -- all defaults
  Worker  wb restart transient
  Reaper  wc restart temporary shutdown 5000
  Flusher wd shutdown infinity
end
```

### Candidate B — an options record

```march
supervise do
  strategy one_for_one
  Worker wb { restart: transient, shutdown: 5000 }
end
```

### Why A

1. **It matches the block it lives in.** `supervise`'s two existing clauses
   are `strategy one_for_one` and `max_restarts 5 within 60` — keyword,
   then values, no punctuation. A record literal inside that block reads as
   a different language than the two lines above it. Consistency inside one
   construct beats consistency with March's record syntax elsewhere,
   because the reader's immediate context is the block.
2. **A record here is a lie about what it is.** `{ restart: transient }`
   looks like a value: a thing with a type, that could be bound to a name,
   built at runtime, or shared between two children. It is none of those —
   it is compile-time-only configuration, read by `lower_actor.ml` and
   burned into a `register_supervisor_child` call as integer literals.
   Nothing constructs one at runtime and nothing ever will, because the
   child table is populated in the generated `Name_spawn` body before any
   user code runs. Giving configuration the shape of a value invites
   exactly the request the shape implies — `let opts = { ... }` reused
   across children — which cannot be honoured without a constant-folding
   pass the compiler does not have.
3. **Growth is genuinely free.** Each new field is one more
   `option(...)` in the same trailing position, no grammar rework, no
   change to any existing production. This doc adds `shutdown` to prove
   that claim rather than assert it: §2's grammar diff for it is four
   lines.
4. **It needs no new reserved words** — see §3. Candidate B needs the same
   labels anyway (as record fields), and additionally has to decide what
   `{ ... }` after a child means everywhere else it could appear.

### What A costs, honestly

- **Order-sensitivity looks arbitrary.** `restart transient shutdown 5000`
  parses; whether `shutdown 5000 restart transient` should is a real
  question. It does, in the landed grammar: the modifiers are a `list`, not
  a fixed sequence, and a repeated label is a diagnostic rather than a
  parse error (§2).
- **A long child line gets wide.** With three or four modifiers a child
  runs past 80 columns and there is no natural wrap. A record has a
  comma-and-newline story that this does not. Accepted: the realistic
  ceiling is two modifiers, since `type` and `significant` are out of scope
  (§6) and backoff is block-level.
- **Every label is a lookahead problem, not a lexing problem.** See §3.

## 2. The grammar

Block level (`backoff` is new, and optional):

```
supervise_block:
  | SUPERVISE DO
      STRATEGY strategy
      MAX_RESTARTS INT WITHIN INT
      option(backoff_clause)
      list(supervise_child)
    END

backoff_clause:
  | BACKOFF; kvs = nonempty_list(backoff_kv)   { ... }

backoff_kv:
  | k = lower_name; n = INT; pct = option(PERCENT)  { (k, n, pct <> None) }
```

`backoff`'s three labels (`base`, `cap`, `jitter`) are parsed as ordinary
lowercase identifiers and validated in the semantic action, which rejects an
unknown label naming the three that are accepted, and rejects a duplicate.
This is deliberate — see §3 — and it is why `cap`, a word March uses
constantly for capabilities, does not become a keyword.

Per child:

```
supervise_child:
  | actor_type = upper_name; field_name = lower_name;
    mods = list(child_modifier)

child_modifier:
  | RESTART; t = restart_type_tok        { CmRestart t }
  | SHUTDOWN; s = shutdown_spec          { CmShutdown s }

shutdown_spec:
  | n = INT            { ShutdownMs n }      -- milliseconds, >= 0
  | i = lower_name     { `brutal` -> ShutdownBrutal | `infinity` -> ShutdownInfinity }
```

Modifiers are accumulated into `supervise_field`'s `sf_restart` /
`sf_shutdown`; a duplicate label on one child is a parse-time error naming
the child, not a silent last-wins.

`shutdown`'s three forms mirror OTP's `brutal_kill | timeout | infinity`:

| Form | Meaning |
|---|---|
| `shutdown brutal` | today's behaviour: the child dies immediately, mailbox discarded |
| `shutdown <ms>` | drain the mailbox, then die; hard-kill at the deadline |
| `shutdown infinity` | drain to empty however long it takes (for a child that is itself a supervisor) |

**Default:** `brutal`, because that is what every existing `supervise` block
means today, and because §5's constraint forbids changing it.

## 3. Keywords: none of these are reserved

March reserves `init` and `within`, and that has surprised people
(`specs/todos/…-parser-gotchas`, and the stdlib's own
`dist_supervisor.march` broke when `restart` was first reserved outright).
The labels this design wants — `shutdown`, `backoff`, `base`, `cap`,
`jitter`, `infinity`, `brutal` — are worse than `restart`: `cap` and `base`
are ordinary words in this codebase, and `shutdown` is a plausible function
name (step 2 of this work adds a `stop`/drain API whose users will write
`shutdown(pid)`).

Two mechanisms, both already in the tree, keep all seven unreserved:

1. **Soft keywords via `token_filter.ml`'s `demote`.** It reads the *next*
   token and demotes back to `LOWER_IDENT` unless the lookahead confirms the
   keyword sense. `restart` already works this way (demoted unless followed
   by `permanent|transient|temporary`). `SHUTDOWN` demotes unless followed
   by `INT` or one of `infinity` / `brutal`, so `shutdown(pid)` — next token
   `(` — is an ordinary call, everywhere, including inside a supervise
   block.
2. **Contextual validation in the semantic action** for labels with no
   usable lookahead signal: `backoff`'s `base` / `cap` / `jitter` are parsed
   as `lower_name` and checked against the allowed set. A `supervise` block
   is the only place these appear, and a lowercase word at clause position
   cannot be a child (children begin with an uppercase actor name), so the
   position alone disambiguates without reserving anything.

`backoff` itself takes route 1 (demoted unless the next token is a
`LOWER_IDENT`).

**Consequence to keep in mind:** a *misspelled* label degrades to a parse
error at the block, not a helpful "unknown option" at the word. That is the
price of not reserving, and it is the right trade — a bad diagnostic on a
typo is recoverable; breaking `stdlib/dist_supervisor.march` again is not.

## 4. Restart semantics (the part with no syntax left to design)

Unchanged from 2026-08-17 §2, restated as the table the code must match:

| Restart type | `MARCH_DEATH_CRASH` | `MARCH_DEATH_KILLED` | `MARCH_DEATH_NORMAL` |
|---|---|---|---|
| `permanent` (default) | restart | restart | no restart |
| `transient` | restart | **no restart** | no restart |
| `temporary` | no restart | no restart | no restart |

March's `permanent` deliberately is *not* OTP's: it does not restart on a
normal exit, because `do_actor_death` already guards the notify with
`reason != MARCH_DEATH_NORMAL` and changing that would alter every
`supervise` block already written. Documented in those terms in the actors
chapter.

Four implementation points, each a way to get this wrong:

1. **Filter before the leaf lock.** `march_supervisor_notify`'s
   `g_supervise_mu` section does the `crash_streak` read-modify-write. A
   death that will not restart must return *before* it, or retiring three
   `temporary` children walks a healthy supervisor toward its
   `max_restarts` ceiling.
2. **Read the reason from `crashed_meta->terminal_reason`**, guarded by
   `terminal_set`, rather than widening the signature. When `terminal_set`
   is 0, assume `MARCH_DEATH_CRASH` — conservative: an unknown reason
   restarts a `permanent` child, preserving today's behaviour instead of
   silently retiring something.
3. **The batch respawn is a second, separate site.** `one_for_all` and
   `rest_for_one` kill live siblings with `MARCH_DEATH_KILLED` as internal
   machinery (they null `cm->supervisor` first to suppress recursive
   notify), so the *kill* must not be filtered — but the *respawn* must skip
   a `temporary` child, or it resurrects whenever a sibling crashes. No
   single-child test catches this.
4. **Interpreter parity.** `lib/eval/eval_runtime.ml`'s three restart
   strategies need the same filter against the same reason
   (`monitor_down_reason`), or `forge test` and `march file.march` disagree
   with the compiled backend on identical source.

## 5. The invariants this must not break

- Every existing `supervise` block keeps its exact behaviour: no modifier
  means `restart permanent` and `shutdown brutal`, which is what those
  blocks mean today.
- `examples/supervision_strategies.march` and the native supervision
  goldens stay **byte-identical**. Each crashes a child exactly once, which
  is `streak == 1`, which is the `delay == 0` synchronous path — untouched
  by making the curve configurable.
- The default backoff curve stays exactly `min(5000, 25 << min(streak-1,
  7))` ms with ±25% jitter. `backoff` absent ⇒ `sup_meta` carries
  `25 / 5000 / 25`, and the delay computation reads those fields instead of
  the literals. Same numbers, same goldens; configurability is a new door,
  not a moved wall.

## 6. Out of scope, and why

- **OTP's `type` (`worker`/`supervisor`) and `significant`.** Nesting
  already works untyped, and `significant` has no consumer until shutdown
  semantics exist.
- **Changing `permanent` to OTP's restart-on-normal-exit.** A breaking
  change; its own decision if ever wanted.
- **`shutdown`'s *semantics*.** This doc fixes the surface so the spec grows
  once; the draining machinery behind it is
  `2026-08-12-graceful-shutdown-and-drain`. A parsed-but-inert `shutdown`
  modifier would be exactly the trap §0 describes for `restart_type`, so
  the grammar for it lands only together with the drain that reads it.

## 7. Verdict on "can these three share one spec?"

Yes, and they want different halves of it:

- `restart` and `shutdown` are **per-child** — they describe one child's
  lifecycle, and OTP puts them in the child spec for that reason. Trailing
  modifiers, one slot each.
- `backoff` is **per-supervisor** — the todo's own sketch puts it beside
  `strategy` and `max_restarts`, and the curve it tunes is computed from
  `sup_meta`, not from a child. Making it per-child would be a bigger,
  worse feature than the one asked for.

The shared decision is the *style* — labelled words and values, no
punctuation, everything optional, defaults that reproduce today byte for
byte. Both halves follow it, so nothing here is blocked on anything else.
