# `[P2]` When March 0.8.0 ships: rebuild depot, conduit and bastion on it and release each

Filed 2026-11-05. depot 0.3.4, conduit 0.1.9 and bastion 0.4.0 are all pinned to March v0.7.0.
On 0.7.0, any compiled `--test` build of an actor with a capability-using handler crashes with
"RC underflow" (`specs/progress/2026-11-04-actor-caps-read-returns-owned-reference.md`). That
covers conduit's suite whenever Postgres is reachable. The fix is in march-language/march#1112,
so 0.8.0 is the first release that has it. Once 0.8.0 is tagged, release the three libraries
on it in dependency order:

1. **depot.** Set `.march-version` and the CI `setup-march` `march-version` to v0.8.0, run
   compiled `forge test`, bump `forge.toml`, merge, tag, and `forge publish`.
2. **conduit.** Same pin change. Move its `depot` dep to the depot release from step 1.
   Run compiled `forge test` against a live Postgres; it must pass 249/249 on plain 0.8.0,
   with no patched compiler. Then bump, tag and publish.
3. **bastion.** Same pin change, and depend on the releases from steps 1 and 2. It
   currently takes depot from git `branch = "main"`, so switch that to the registry
   version. Then test, bump, tag and publish.

conduit depends on depot from the registry, so depot has to be released before conduit
can point at it.

`forge publish` needs a FORGE_TOKEN, and the maintainer runs it. Check each version on
`https://forgepm.org/api/v1/packages/<name>` afterwards.

Done when all three are published on 0.8.0 and conduit's live-Postgres suite passes on the
released compiler.
