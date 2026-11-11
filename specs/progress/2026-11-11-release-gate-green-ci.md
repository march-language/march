# Release only from a commit with green CI (G1)

Logged 2026-11-11. Package G1 of `specs/plans/2026-11-11-pre-1.0-execution-plan.md`.

**Before.** `release.yml`'s `publish` needed only `build`. A `v*` tag on a commit whose CI was
red, cancelled or never run built and published.

**Now.**

- `scripts/release-gate.sh SHA` exits 0 only if SHA is on `main` and `ci.yml` and `doc-lint.yml`
  each have a successful run of that exact commit. It counts `push` runs on `main` and
  `workflow_dispatch` runs; a cancelled run is no verdict; the newest run with a verdict decides;
  a run in progress is not a success. On "no verdict" it prints the commands that run CI on the
  commit.
- `scripts/release-gate.sh --newest-green` is the walk `nightly.yml`'s `gate` job used to carry
  inline (newest `main` commit whose CI push run is green, or the reason there is none). The
  nightly now calls the script, so the two gates read runs through one function.
- `release.yml` has a `gate` job that runs the script on the tag's commit; `build` needs it. On
  `workflow_dispatch` (rebuilding a shipped release's archives) the job's steps are skipped.
- `ci.yml` and `doc-lint.yml` take `workflow_dispatch`. A manual CI run does what a push to `main`
  does (full determinism corpus), and has its own concurrency group per commit so a merge cannot
  cancel it.
- `scripts/test-release-gate.sh` (a step of `doc-lint.yml`, selected by `scripts/affected.sh`)
  runs 18 cases against a fake `gh`: failed, timed out, cancelled, running, missing, pull-request
  only, not on main, dispatched run superseding a cancelled push run, and the nightly walk.
- The release ritual is written down in `.claude/skills/steward/SKILL.md` ("Cutting a release")
  and `bump-version.sh` prints the gate step between the two pushes.

**Shown to go red** on real commits (2026-11-11): `33c4d2e5f` (CI failure) exits 1, `67490d220`
(both green) exits 0, `d8d363852` (CI run cancelled in a burst) exits 1 with the dispatch
commands. Mutating the script to stop treating `failure` as red fails 6 of the 18 self-test cases.

**Left for later packages.** G6 adds "a green lab run on this commit" to the same script.
