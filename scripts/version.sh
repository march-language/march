#!/usr/bin/env bash
# Print the in-tree March version, read from dune-project's (version ...) field.
#
# dune-project is the single source of truth: `generate_opam_files true` derives
# the three .opam files from it, and bin/dune turns %{version:march} into
# bin/version.ml, which is what `march --version` prints.  Everything that needs
# the version reads it through this script so the extraction exists once.
#
# The in-tree version is the LAST RELEASED version, not a next-in-development
# one -- there is no -dev suffix convention.  See
# specs/2026-09-10-release-mechanism-design.md for why.
set -euo pipefail

repo_root() { cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd; }

march_version() {
  local f v
  f="$(repo_root)/dune-project"
  [ -f "$f" ] || { echo "version.sh: no dune-project at $f" >&2; return 1; }
  v="$(sed -n 's/^(version \(.*\))$/\1/p' "$f" | head -1)"
  [ -n "$v" ] || { echo "version.sh: no (version ...) field in $f" >&2; return 1; }
  printf '%s\n' "$v"
}

# Executed directly (not sourced): print the version.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then march_version; fi
