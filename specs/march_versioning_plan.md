# March Versioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make March's version a single source of truth that is visible in `march`/`forge --version`, recorded in a CHANGELOG, moved by a guarded release ritual, and contractually consistent with forge's toolchain manager.

**Architecture:** `dune-project`'s `(version …)` field is canonical. A dune `(rule)` runs a small OCaml generator (`gen_version.ml`) that extracts that field and shells out to git for the short hash + commit date, emitting `lib/version/version.ml`. The `march` and `forge` binaries consume the generated `Version` module instead of hardcoded strings. Release/CI scripts enforce that the pushed git tag matches the in-tree version and that nightlies derive their semver from it.

**Tech Stack:** OCaml 5.3, dune 3.x, POSIX shell, GitHub Actions. Spec: [specs/march_versioning.md](march_versioning.md).

**Conventions for this plan:**
- Build/test without any opam env prefix: run `dune` directly (per CLAUDE.md). Binaries: `dune build bin/main.exe forge/bin/main.exe`.
- Never `git add -A`/`.`; stage files explicitly by name.
- No `Co-Authored-By` lines in commits.
- The in-tree version starts at `0.1.0-dev` ("developing toward the first real release, 0.1.0"). The spec's `0.2.0-dev` example was illustrative; `0.1.0` has not yet been cut through this new process, so the first `bump-version.sh 0.1.0` produces the real `0.1.0` and then sets main to `0.2.0-dev`.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `lib/version/gen_version.ml` | Generator: reads dune-project version + git, prints `version.ml` source | 1 |
| `lib/version/dune` | Builds the generator, the codegen rule, and the `march_version` library | 1 |
| `dune-project` | Canonical version field (`0.1.0` → `0.1.0-dev`) | 1 |
| `test/version_test.sh` | Shell test for the generated module + `--version` output + agreement + no-hardcodes | 1–4 |
| `bin/dune`, `bin/main.ml` | `march --version` / `--version --verbose` consume `Version` | 2 |
| `forge/bin/dune`, `forge/bin/main.ml` | `forge --version` consumes `Version` | 3 |
| `scripts/check-no-hardcoded-version.sh` | Guard: no stray hardcoded version literals outside dune-project | 4 |
| `CHANGELOG.md` | Keep-a-Changelog record | 5 |
| `scripts/changelog-section.sh` | Extract one version's notes from CHANGELOG (for release.yml) | 5 |
| `scripts/check-version-tag.sh` | CI guard: pushed `vX.Y.Z` tag == in-tree released version | 6 |
| `scripts/nightly-version.sh` | Derive `X.Y.Z-nightly.YYYYMMDD` from dune-project | 7 |
| `scripts/bump-version.sh` | Guarded release ritual (clean→build→test→finalize→tag→next-dev) | 8 |
| `.github/workflows/release.yml`, `nightly.yml` | Wire in tag guard, changelog notes, nightly derivation | 6,7 |
| `specs/todos.md`, `specs/progress.md` | Keep the canonical record current | 9 |

---

## Task 1: Generated `Version` module (single source of truth)

**Files:**
- Create: `lib/version/gen_version.ml`
- Create: `lib/version/dune`
- Modify: `dune-project` (line 4: `(version 0.1.0)` → `(version 0.1.0-dev)`)
- Test: `test/version_test.sh`

- [ ] **Step 1: Write the failing test**

Create `test/version_test.sh`:

```bash
#!/usr/bin/env bash
# Versioning integration test. Run from repo root: bash test/version_test.sh
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- Task 1: generated module reflects dune-project + git ---
dune build lib/version/version.ml
GEN=_build/default/lib/version/version.ml
[ -f "$GEN" ] || fail "generated $GEN missing"
WANT_SEMVER=$(sed -n 's/^(version \(.*\))/\1/p' dune-project | tr -d ' ')
grep -q "let semver = \"$WANT_SEMVER\"" "$GEN" || fail "semver in $GEN != dune-project ($WANT_SEMVER)"
grep -Eq 'let git_hash = "[0-9a-f]+"' "$GEN" || fail "git_hash not embedded in a repo build"

echo "version_test: Task 1 OK"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash test/version_test.sh`
Expected: FAIL — `dune build lib/version/version.ml` errors because `lib/version/` does not exist.

- [ ] **Step 3: Create the generator**

Create `lib/version/gen_version.ml`:

```ocaml
(* Generates lib/version/version.ml. argv.(1) = path to dune-project.
   Reads the canonical (version ...) field and stamps the git short hash +
   commit date. Degrades to bare semver when git is unavailable (release
   tarballs with no .git). *)

let read_file p =
  let ic = open_in p in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic; s

let semver_of_dune_project path =
  let lines = String.split_on_char '\n' (read_file path) in
  let pfx = "(version " in
  let rec find = function
    | [] -> "0.0.0"
    | l :: rest ->
      let l = String.trim l in
      if String.length l > String.length pfx
         && String.sub l 0 (String.length pfx) = pfx
      then
        let inner =
          String.sub l (String.length pfx) (String.length l - String.length pfx)
        in
        String.trim (String.map (fun c -> if c = ')' then ' ' else c) inner)
      else find rest
  in
  find lines

let run cmd =
  try
    let ic = Unix.open_process_in cmd in
    let line = try input_line ic with End_of_file -> "" in
    ignore (Unix.close_process_in ic);
    String.trim line
  with _ -> ""

let () =
  let semver = semver_of_dune_project Sys.argv.(1) in
  let git_hash = run "git rev-parse --short HEAD 2>/dev/null" in
  let build_date = run "git show -s --format=%cs HEAD 2>/dev/null" in
  Printf.printf "let semver = %S\n" semver;
  Printf.printf "let git_hash = %S\n" git_hash;
  Printf.printf "let build_date = %S\n" build_date;
  Printf.printf
    "let string =\n\
    \  if git_hash = \"\" then semver\n\
    \  else Printf.sprintf \"%%s (%%s %%s)\" semver git_hash build_date\n"
```

Create `lib/version/dune`:

```
(executable
 (name gen_version)
 (modules gen_version)
 (libraries unix))

(rule
 (target version.ml)
 (deps (universe) %{project_root}/dune-project)
 (action (with-stdout-to version.ml (run ./gen_version.exe %{project_root}/dune-project))))

(library
 (name march_version)
 (modules version))
```

Modify `dune-project` line 4:

```
(version 0.1.0-dev)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash test/version_test.sh`
Expected: PASS — prints `version_test: Task 1 OK`. (`(universe)` makes the rule re-run each build so the hash stays current.)

- [ ] **Step 5: Commit**

```bash
git add lib/version/gen_version.ml lib/version/dune dune-project test/version_test.sh
git commit -m "feat(version): generated Version module from dune-project + git"
```

---

## Task 2: `march --version` consumes `Version`

**Files:**
- Modify: `bin/dune` (add `march_version` to `(libraries …)`)
- Modify: `bin/main.ml:1670-1674` (the `--version` block)
- Test: `test/version_test.sh` (extend)

- [ ] **Step 1: Write the failing test**

Append to `test/version_test.sh` (before the final `echo`... add a new block):

```bash
# --- Task 2: march --version reads the generated module ---
dune build bin/main.exe
MARCH=_build/default/bin/main.exe
OUT=$("$MARCH" --version)
echo "$OUT" | grep -Eq "^march $WANT_SEMVER \([0-9a-f]+ [0-9]{4}-[0-9]{2}-[0-9]{2}\)$" \
  || fail "march --version format wrong: '$OUT'"
"$MARCH" --version --verbose | grep -q "ocaml" \
  || fail "march --version --verbose missing ocaml line"

echo "version_test: Task 2 OK"
```

(Move the original `echo "version_test: Task 1 OK"` so it stays after Task 1's checks and before this block.)

- [ ] **Step 2: Run test to verify it fails**

Run: `bash test/version_test.sh`
Expected: FAIL — output is the hardcoded `march 0.1.0`, which does not match `^march 0.1.0-dev \(<hash> <date>\)$`.

- [ ] **Step 3: Implement**

In `bin/dune`, add `march_version` to the `(libraries …)` list (append before the closing `)`):

```
(libraries march_lexer march_parser march_ast march_desugar march_typecheck march_codegen march_effects march_errors march_eval march_coverage march_tir march_repl march_debug march_jit march_cas march_format march_resolver march_dump march_dap march_version threads.posix unix))
```

Replace `bin/main.ml:1670-1674` (the `if … "--version" … print_string "march 0.1.0\n"` block) with:

```ocaml
  if Array.length argv >= 2 && (argv.(1) = "--version" || argv.(1) = "-version") then begin
    let verbose =
      Array.exists (fun a -> a = "--verbose" || a = "-V") argv
    in
    if verbose then begin
      Printf.printf "march %s\n" March_version.Version.semver;
      Printf.printf "commit: %s\n"
        (if March_version.Version.git_hash = "" then "(none)"
         else March_version.Version.git_hash);
      Printf.printf "build-date: %s\n"
        (if March_version.Version.build_date = "" then "(none)"
         else March_version.Version.build_date);
      Printf.printf "ocaml: %s\n" Sys.ocaml_version
    end else
      Printf.printf "march %s\n" March_version.Version.string;
    exit 0
  end;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash test/version_test.sh`
Expected: PASS — `version_test: Task 2 OK`. Manually: `dune exec march -- --version` → `march 0.1.0-dev (<hash> <date>)`.

- [ ] **Step 5: Commit**

```bash
git add bin/dune bin/main.ml test/version_test.sh
git commit -m "feat(version): march --version reads generated Version module"
```

---

## Task 3: `forge --version` consumes `Version` (lockstep)

**Files:**
- Modify: `forge/bin/dune` (add `march_version`)
- Modify: `forge/bin/main.ml:888` (`~version:"0.1.0"`)
- Test: `test/version_test.sh` (extend)

- [ ] **Step 1: Write the failing test**

Append a block to `test/version_test.sh` before its final success echo:

```bash
# --- Task 3: forge --version agrees with march --version ---
dune build forge/bin/main.exe
FORGE=_build/default/forge/bin/main.exe
FORGE_VER=$("$FORGE" --version)
[ "$FORGE_VER" = "$WANT_SEMVER" ] \
  || fail "forge --version ('$FORGE_VER') != dune-project semver ('$WANT_SEMVER')"

echo "version_test: Task 3 OK"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash test/version_test.sh`
Expected: FAIL — `forge --version` prints the hardcoded `0.1.0`, not `0.1.0-dev`.

- [ ] **Step 3: Implement**

In `forge/bin/dune`, add `march_version`:

```
(libraries march_forge cmdliner march_version)
```

In `forge/bin/main.ml:888`, replace `~version:"0.1.0"` with:

```ocaml
      (Cmd.info "forge" ~version:March_version.Version.semver
```

(cmdliner's `--version` prints just the semver string, so this matches `WANT_SEMVER`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `bash test/version_test.sh`
Expected: PASS — `version_test: Task 3 OK`.

- [ ] **Step 5: Commit**

```bash
git add forge/bin/dune forge/bin/main.ml test/version_test.sh
git commit -m "feat(version): forge --version reads generated Version module (lockstep)"
```

---

## Task 4: No-hardcoded-version guard

**Files:**
- Create: `scripts/check-no-hardcoded-version.sh`
- Test: `test/version_test.sh` (extend)

- [ ] **Step 1: Write the failing test**

Append to `test/version_test.sh` before its final success echo:

```bash
# --- Task 4: no stray hardcoded version literals ---
bash scripts/check-no-hardcoded-version.sh || fail "hardcoded version literal found"

echo "version_test: Task 4 OK"
echo "version_test: ALL OK"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash test/version_test.sh`
Expected: FAIL — `scripts/check-no-hardcoded-version.sh: No such file or directory`.

- [ ] **Step 3: Implement**

Create `scripts/check-no-hardcoded-version.sh`:

```bash
#!/usr/bin/env bash
# Fails if a hardcoded MAJOR.MINOR.PATCH version literal appears in source
# outside the canonical dune-project. The generated version.ml lives under
# _build and is not searched. Allows test fixtures and changelog/docs.
set -euo pipefail
cd "$(dirname "$0")/.."

# Search OCaml sources in the two binaries that previously hardcoded it.
hits=$(grep -REn '"[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.]+)?"' \
  bin/main.ml forge/bin/main.ml 2>/dev/null \
  | grep -vE 'Version\.|ocaml|nightly-YYYYMMDD|v0\.1\.0|YYYY' || true)

if [ -n "$hits" ]; then
  echo "Hardcoded version literal(s) found — use March_version.Version instead:" >&2
  echo "$hits" >&2
  exit 1
fi
echo "check-no-hardcoded-version: OK"
```

Make it executable:

```bash
chmod +x scripts/check-no-hardcoded-version.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash test/version_test.sh`
Expected: PASS — ends with `version_test: ALL OK`.

- [ ] **Step 5: Commit**

```bash
git add scripts/check-no-hardcoded-version.sh test/version_test.sh
git commit -m "test(version): guard against hardcoded version literals"
```

---

## Task 5: CHANGELOG + release-notes extractor

**Files:**
- Create: `CHANGELOG.md`
- Create: `scripts/changelog-section.sh`
- Test: `scripts/changelog-section.test.sh`

- [ ] **Step 1: Write the failing test**

Create `scripts/changelog-section.test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $1" >&2; exit 1; }

OUT=$(bash scripts/changelog-section.sh 0.1.0)
echo "$OUT" | grep -q "Initial" || fail "0.1.0 section should contain its notes"
echo "$OUT" | grep -q "Unreleased" && fail "must not bleed into the Unreleased section"
echo "changelog-section: OK"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/changelog-section.test.sh`
Expected: FAIL — `scripts/changelog-section.sh: No such file or directory`.

- [ ] **Step 3: Implement**

Create `CHANGELOG.md`:

```markdown
# Changelog

All notable changes to the March compiler and toolchain are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project aims to follow [Semantic Versioning](https://semver.org/) once
it reaches 1.0. Pre-1.0, minor versions may contain breaking changes.

## [Unreleased]

### Added
- Single source of truth for the toolchain version (`dune-project`), surfaced by
  `march --version` and `forge --version`.

## [0.1.0] - 2026-06-18

### Added
- Initial versioned release of the March compiler, `forge`, and `march-lsp`.
```

Create `scripts/changelog-section.sh`:

```bash
#!/usr/bin/env bash
# Print the CHANGELOG.md section body for a given version (no "vX" prefix).
# Usage: changelog-section.sh 0.1.0
set -euo pipefail
cd "$(dirname "$0")/.."
ver="${1:?usage: changelog-section.sh X.Y.Z}"

# Emit lines after "## [<ver>]" up to (not including) the next "## [" header.
awk -v ver="$ver" '
  $0 ~ ("^## \\[" ver "\\]") { insec=1; next }
  insec && /^## \[/ { exit }
  insec { print }
' CHANGELOG.md
```

Make executable:

```bash
chmod +x scripts/changelog-section.sh scripts/changelog-section.test.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/changelog-section.test.sh`
Expected: PASS — `changelog-section: OK`.

- [ ] **Step 5: Wire release notes into `release.yml`**

In `.github/workflows/release.yml`, replace the hardcoded `body: |` block under "Create GitHub Release" with a generated body file. Add a step BEFORE the release step:

```yaml
      - name: Generate release notes
        run: |
          VER="${GITHUB_REF_NAME#v}"
          {
            echo "## Installation"
            echo
            echo '```'
            echo "curl -fsSL https://github.com/march-language/march/releases/latest/download/install.sh | sh"
            echo '```'
            echo
            echo "## Changes"
            echo
            bash scripts/changelog-section.sh "$VER"
          } > release-notes.md
```

Then in the `softprops/action-gh-release@v2` step, replace `body: |` (and its inline content) with:

```yaml
        with:
          tag_name: ${{ github.ref_name }}
          name: March ${{ github.ref_name }}
          body_path: release-notes.md
          files: |
```

(Keep the existing `files:` entries unchanged.)

- [ ] **Step 6: Commit**

```bash
git add CHANGELOG.md scripts/changelog-section.sh scripts/changelog-section.test.sh .github/workflows/release.yml
git commit -m "feat(version): CHANGELOG + release.yml sources notes from it"
```

---

## Task 6: Tag-matches-version CI guard

**Files:**
- Create: `scripts/check-version-tag.sh`
- Create: `scripts/check-version-tag.test.sh`
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Write the failing test**

Create `scripts/check-version-tag.test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $1" >&2; exit 1; }

# The released version is the dune-project semver with any -dev/-pre stripped.
REL=$(sed -n 's/^(version \(.*\))/\1/p' dune-project | tr -d ' ' | sed 's/-.*//')

bash scripts/check-version-tag.sh "v$REL"        || fail "matching tag should pass"
bash scripts/check-version-tag.sh "v9.9.9" 2>/dev/null && fail "mismatched tag must fail"
echo "check-version-tag: OK"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/check-version-tag.test.sh`
Expected: FAIL — `scripts/check-version-tag.sh: No such file or directory`.

- [ ] **Step 3: Implement**

Create `scripts/check-version-tag.sh`:

```bash
#!/usr/bin/env bash
# Fail if the given git tag does not match the in-tree released version.
# Released version = dune-project (version ...) with any pre-release suffix
# (-dev, -rc.1, ...) stripped. Usage: check-version-tag.sh vX.Y.Z
set -euo pipefail
cd "$(dirname "$0")/.."
tag="${1:?usage: check-version-tag.sh vX.Y.Z}"

intree=$(sed -n 's/^(version \(.*\))/\1/p' dune-project | tr -d ' ' | sed 's/-.*//')
want="v$intree"
if [ "$tag" != "$want" ]; then
  echo "tag/version mismatch: pushed '$tag' but dune-project is '$want'." >&2
  echo "forge resolves 'march = ~> X.Y' against release tags; they must agree." >&2
  exit 1
fi
echo "check-version-tag: $tag matches dune-project"
```

Make executable:

```bash
chmod +x scripts/check-version-tag.sh scripts/check-version-tag.test.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/check-version-tag.test.sh`
Expected: PASS — `check-version-tag: OK`.

- [ ] **Step 5: Wire the guard into `release.yml`**

In `.github/workflows/release.yml`, add a `verify` job and make `build` depend on it so a mismatched tag never produces a release. After the `on:`/`permissions:` block, add:

```yaml
jobs:
  verify:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.ref }}
      - name: Tag matches in-tree version
        run: bash scripts/check-version-tag.sh "${{ github.ref_name }}"
```

Then add `needs: verify` to the existing `build:` job:

```yaml
  build:
    needs: verify
    uses: ./.github/workflows/build.yml
    with:
      version: ${{ github.ref_name }}
      ref: ${{ github.ref }}
```

- [ ] **Step 6: Commit**

```bash
git add scripts/check-version-tag.sh scripts/check-version-tag.test.sh .github/workflows/release.yml
git commit -m "feat(version): CI guard that release tag matches in-tree version"
```

---

## Task 7: Nightly version derivation

**Files:**
- Create: `scripts/nightly-version.sh`
- Create: `scripts/nightly-version.test.sh`
- Modify: `.github/workflows/nightly.yml`

- [ ] **Step 1: Write the failing test**

Create `scripts/nightly-version.test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $1" >&2; exit 1; }

OUT=$(bash scripts/nightly-version.sh 20260618)
echo "$OUT" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+-nightly\.20260618$' \
  || fail "unexpected nightly version: '$OUT'"
echo "$OUT" | grep -q -- '-dev' && fail "nightly version must not contain -dev"
echo "nightly-version: OK"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/nightly-version.test.sh`
Expected: FAIL — `scripts/nightly-version.sh: No such file or directory`.

- [ ] **Step 3: Implement**

Create `scripts/nightly-version.sh`:

```bash
#!/usr/bin/env bash
# Derive the nightly semver from the in-development dune-project version.
# Strips the -dev suffix and appends -nightly.<date>.
# Usage: nightly-version.sh YYYYMMDD   (default: today, UTC)
set -euo pipefail
cd "$(dirname "$0")/.."
date="${1:-$(date -u +%Y%m%d)}"
base=$(sed -n 's/^(version \(.*\))/\1/p' dune-project | tr -d ' ' | sed 's/-.*//')
echo "${base}-nightly.${date}"
```

Make executable:

```bash
chmod +x scripts/nightly-version.sh scripts/nightly-version.test.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/nightly-version.test.sh`
Expected: PASS — `nightly-version: OK`.

- [ ] **Step 5: Wire into `nightly.yml`**

In `.github/workflows/nightly.yml`, compute the semver version and pass it to the build. Add a step that exports it, e.g.:

```yaml
      - name: Compute nightly version
        id: ver
        run: echo "version=$(bash scripts/nightly-version.sh)" >> "$GITHUB_OUTPUT"
```

Then use `${{ steps.ver.outputs.version }}` wherever the workflow names the artifact/version (replacing any place that used a bare date or `nightly` literal as the semver). Keep the release *tag* as `nightly-YYYYMMDD`; only the artifact's embedded semver changes.

- [ ] **Step 6: Commit**

```bash
git add scripts/nightly-version.sh scripts/nightly-version.test.sh .github/workflows/nightly.yml
git commit -m "feat(version): nightlies derive X.Y.Z-nightly.DATE from dune-project"
```

---

## Task 8: Guarded release ritual

**Files:**
- Create: `scripts/bump-version.sh`
- Create: `scripts/bump-version.test.sh`

- [ ] **Step 1: Write the failing test**

The ritual mutates git/files, so test the planning logic via a `--dry-run` that prints the planned actions without side effects.

Create `scripts/bump-version.test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $1" >&2; exit 1; }

OUT=$(bash scripts/bump-version.sh --dry-run 0.1.0)
echo "$OUT" | grep -q "release version: 0.1.0"   || fail "should set release version 0.1.0"
echo "$OUT" | grep -q "tag: v0.1.0"              || fail "should tag v0.1.0"
echo "$OUT" | grep -q "next dev version: 0.2.0-dev" || fail "should bump to next -dev"
echo "bump-version: OK"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/bump-version.test.sh`
Expected: FAIL — `scripts/bump-version.sh: No such file or directory`.

- [ ] **Step 3: Implement**

Create `scripts/bump-version.sh`:

```bash
#!/usr/bin/env bash
# Guarded compile-and-release ritual for the March toolchain.
# Mirrors the shape of `forge release`, but targets dune-project (the compiler
# is not a forge project). Usage:
#   scripts/bump-version.sh [--dry-run] X.Y.Z
set -euo pipefail
cd "$(dirname "$0")/.."

dry=0
if [ "${1:-}" = "--dry-run" ]; then dry=1; shift; fi
rel="${1:?usage: bump-version.sh [--dry-run] X.Y.Z}"

# Compute the next in-development version: bump minor, reset patch, add -dev.
IFS=. read -r MA MI _PA <<<"$rel"
next="${MA}.$((MI + 1)).0-dev"
today=$(date -u +%Y-%m-%d)

echo "release version: $rel"
echo "tag: v$rel"
echo "next dev version: $next"

if [ "$dry" -eq 1 ]; then
  echo "(dry run — no changes made)"
  exit 0
fi

# 1. Clean tree.
git diff --quiet && git diff --cached --quiet \
  || { echo "working tree is dirty; commit or stash first" >&2; exit 1; }

# 2. Build (release) + test.
dune build @all
bash test/version_test.sh

# 3. Finalize CHANGELOG: rename [Unreleased] -> [X.Y.Z] - DATE.
sed -i.bak "s/^## \[Unreleased\]/## [Unreleased]\n\n## [$rel] - $today/" CHANGELOG.md
rm -f CHANGELOG.md.bak

# 4. Set release version, commit, tag.
sed -i.bak "s/^(version .*/(version $rel)/" dune-project && rm -f dune-project.bak
git add dune-project CHANGELOG.md
git commit -m "release: v$rel"
git tag -a "v$rel" -m "v$rel"

# 5. Open the next dev version.
sed -i.bak "s/^(version .*/(version $next)/" dune-project && rm -f dune-project.bak
git add dune-project
git commit -m "chore: begin $next"

echo "Released v$rel. Push with: git push && git push origin v$rel"
```

Make executable:

```bash
chmod +x scripts/bump-version.sh scripts/bump-version.test.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/bump-version.test.sh`
Expected: PASS — `bump-version: OK`.

- [ ] **Step 5: Commit**

```bash
git add scripts/bump-version.sh scripts/bump-version.test.sh
git commit -m "feat(version): guarded bump-version.sh release ritual"
```

---

## Task 9: Update the canonical record

**Files:**
- Modify: `specs/todos.md`
- Modify: `specs/progress.md`

- [ ] **Step 1: Move the versioning item to Done in `specs/todos.md`**

Find any versioning-related todo (or add a Done entry if none exists) and place under the "Done" section:

```markdown
- [x] Make march versions real & visible: single source of truth (dune-project),
      generated Version module, `march`/`forge --version` with git hash, CHANGELOG,
      tag↔version CI guard, nightly semver derivation, `bump-version.sh` ritual.
      (spec: specs/march_versioning.md)
```

- [ ] **Step 2: Update `specs/progress.md`**

Add to the feature bullet list:

```markdown
- **Toolchain versioning:** single canonical version in `dune-project`, surfaced by
  `march --version` / `forge --version` (lockstep) with embedded git hash + date;
  CHANGELOG-driven release notes; CI guard that the release tag matches the in-tree
  version; nightlies versioned `X.Y.Z-nightly.YYYYMMDD`.
```

- [ ] **Step 3: Run the full version test once more**

Run: `bash test/version_test.sh`
Expected: PASS — `version_test: ALL OK`.

- [ ] **Step 4: Commit**

```bash
git add specs/todos.md specs/progress.md
git commit -m "docs(version): record versioning work in todos + progress"
```

---

## Self-Review

**Spec coverage:**
- §1 Single source of truth → Task 1 (generated module), Task 4 (guard), `dune-project` canonical.
- §2 `--version` output → Tasks 2 (march), 3 (forge); `--verbose` in Task 2. (Verbose prints OCaml version rather than a full host triple — a deliberate YAGNI trim; note in spec if a triple is later wanted.)
- §3 CHANGELOG → Task 5.
- §4 Release ritual → Task 8 (`bump-version.sh`), explicitly not a forge subcommand.
- §5 forge contracts → contract (a) Task 6 (tag guard), (b) preserved by leaving `release.yml` `files:` untouched and only swapping the notes body, (c) Task 7 (nightly derivation).
- Acceptance criteria 1–7 → Tasks 1/4 (1), 2/3 (2), 5 (3), 8 (4), 6 (5), 6 (6), 9 (7).

**Placeholder scan:** none — every step has concrete code/commands and expected output.

**Type/name consistency:** module path `March_version.Version` (library `march_version`, module `Version`) used consistently in Tasks 2–3; `WANT_SEMVER`/`REL` shell vars consistent within their scripts; `check-version-tag.sh`, `changelog-section.sh`, `nightly-version.sh`, `bump-version.sh` referenced by the same names where wired into workflows.

**One open detail for the executor:** Task 7 step 5 edits `nightly.yml`, whose exact current contents weren't pinned in this plan. Read the file first and replace only the place where the semver/artifact version is named; the `nightly-YYYYMMDD` *tag* stays as-is.
