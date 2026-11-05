# HCR deploy gate: the `--accept-unproved` override is signed and audited (2026-11-04)

The rest of phase A0 of `specs/2026-11-04-lemmas-hcr-actors-choreography-design.md` (§3.3,
item 2). PR #1100 (progress `2026-11-04-hcr-refinement-variance-check`) added the override,
but forge only printed a warning, so a law deployed unproved left no record on the node.

## What landed

- **The compiler writes the override into the image.**
  - `march --compile-so --hot-reload … --accept-unproved Tally.state,Box` gives each named
    actor's schema `"accepted_unproved"`: `["state"]`, a handler name, or `["*"]` for a bare
    actor (`bin/main.ml`, `accepted_laws`).
  - The schema is embedded in the signed image (`__march_hcr_schemas`).
  - `hr_cas_tag` adds the sorted override to the source-level cache key.
- **The reload server copies the laws into the activation's audit line.**
  - The field goes on the `"ok"` line of an actor's `_dispatch`, as `"accepted_unproved":[…]`
    on one line, whatever the whitespace in the image.
  - Code: `schema_member` and `schema_accepted_for` in `runtime/march_reload_schemas.h`;
    `g_audit_accepted` in `runtime/march_reload.c`.
- **`--check-migration`** honours an override the new schema carries, as well as one named on
  its command line.
- **forge:**
  - `forge deploy hot --accept-unproved` passes the override to the build (`build_so_for`).
  - It no longer passes it to `--check-migration`. The only override that counts is the one
    in the patch.
  - It refuses an override a pre-built `--so` patch doesn't carry
    (`Schema_diff.unembedded_overrides`).

## Tests

- **`test_refinecheck` `hcr-variance`, four new cases:**
  - an override built into the patch is accepted;
  - such an override covers only the law it names;
  - a bare actor gives `"*"`;
  - the writer, compiled twice in one cwd (without, then with the flag), so a cached
    sidecar can't stand in.
- **`test_reload_activate4`:**
  - `hcr_stub.so`'s Counter schema now carries a spaced, multi-line `accepted_unproved`, and
    its activation's audit line must contain `"accepted_unproved":["state","Bump"],"result":"ok"`;
  - a non-actor function's line has no such key.
- **`test_forge`** `schemas: --accept-unproved must be built into the patch`.
- **RED controls**, each run and reverted:
  - the server not setting `g_audit_accepted` fails the audit check;
  - `--check-migration` ignoring the schema's list fails "override built into the patch
    accepted".
  - Removing `hr_cas_tag`'s override alone leaves the writer case green: the post-TIR key
    already differs, since it sees the emitted schemas. The tag keeps the source-level key
    honest too.

## Not done

- **Reply covariance:** needs typed replies first (todo `2026-11-04-actor-call-reply-untyped`).
- **H2** (`migrate_msg` results against handler contracts): phase A.
