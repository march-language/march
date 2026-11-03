#!/usr/bin/env bash
# Run the worktree compiler under the spike's private HOME (THROWAWAY helper).
here="$(cd "$(dirname "$0")" && pwd)"
export HOME="${HCR0_HOME:-/tmp/hcr0-home}"
mkdir -p "$HOME"
exec "${MARCH:-$here/../../../_build/default/bin/main.exe}" "$@"
