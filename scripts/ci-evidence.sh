#!/usr/bin/env bash
# ci-evidence.sh: keep what a failed CI test job would otherwise throw away.
#
#   scripts/ci-evidence.sh setup     before the tests: create the evidence
#                                    directory, export MARCH_EVIDENCE_DIR to
#                                    later steps, and (Linux) send core files
#                                    into it
#   scripts/ci-evidence.sh collect   after a failure: backtrace the cores, copy
#                                    the binaries that dumped them, the macOS
#                                    crash reports, dune's log and the work
#                                    directories of failed two-node scenarios
#
# Several flaky-test sightings were lost because the job's log and the crashing
# binary were gone by the time anyone looked (specs/todos/, the "flake-*"
# items). The jobs that run native fixtures (ci.yml: test, two-node,
# sanitize-gate) call `setup`, tee their test step into
# $MARCH_EVIDENCE_DIR/<step>.log, and on failure call `collect` and upload the
# directory as the artifact `evidence-<job>-<shard>` (kept 7 days).
#
# What lands in $MARCH_EVIDENCE_DIR:
#   *.log               the test step's full output (written by the step)
#   cores/core.PID.EXE  Linux core files, up to $MAX_CORE_MB in total
#   cores/backtraces.txt  gdb's `thread apply all bt` for the first $MAX_BACKTRACES
#   binaries/           the executable each core came from
#   crash-reports/      macOS: ~/Library/Logs/DiagnosticReports entries written
#                       since `setup` (a crash report carries the backtrace;
#                       macOS core files are not captured, they run to GBs)
#   dune.log            _build/log: every command dune ran, with its output
#   two-node/<dir>/     the work directory scripts/two-node.sh leaves behind
#                       for a failed scenario: each node's binary, stdout,
#                       stderr and the diff against its golden
#   sanitize/           written by specs/lang/golden/sanitize.sh: the ASan
#                       binary, its output and its compile log, per failure
#
# A core needs `ulimit -c unlimited` in the step that runs the tests; the limit
# is per process, so `setup` cannot raise it for a later step. AddressSanitizer
# builds do not dump core (ASan's default disable_coredump=1); their evidence is
# the report in the log plus sanitize/.
#
# MARCH_EVIDENCE_NO_SYSCTL=1 skips the core_pattern change (needs root); used
# by scripts/test-ci-evidence.sh.
set -euo pipefail

MAX_BACKTRACES=8
MAX_CORE_MB=2048
os=$(uname -s)

case "${1:-}" in
  setup)
    dir=${MARCH_EVIDENCE_DIR:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/march-evidence}
    mkdir -p "$dir/cores"
    # The marker `collect` compares crash reports against. Hidden, so the
    # upload (which skips hidden files) leaves it out.
    : > "$dir/.setup-marker"
    if [ "$os" = Linux ] && [ -z "${MARCH_EVIDENCE_NO_SYSCTL:-}" ]; then
      # A test binary killed by a signal its own handler never saw (a bare
      # "Segmentation fault (core dumped)") leaves no trace on a stock runner:
      # the default core_pattern pipes to apport, which discards cores of
      # unpackaged binaries. %E: the executable's absolute path with '/'
      # written as '!'.
      chmod 1777 "$dir/cores"
      sudo sysctl -w kernel.core_pattern="$dir/cores/core.%p.%E"
    fi
    if [ -n "${GITHUB_ENV:-}" ]; then echo "MARCH_EVIDENCE_DIR=$dir" >> "$GITHUB_ENV"; fi
    echo "failure evidence will be collected in $dir"
    ;;

  collect)
    dir=${MARCH_EVIDENCE_DIR:?ci-evidence.sh collect: MARCH_EVIDENCE_DIR is not set (run setup first)}
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    shopt -s nullglob

    # ── Linux cores: backtrace, keep the binary ─────────────────────────────
    cores=("$dir"/cores/core.*)
    echo "${#cores[@]} core file(s) in $dir/cores"
    if [ ${#cores[@]} -gt 0 ]; then
      if ! command -v gdb > /dev/null && [ "$os" = Linux ] && [ -n "${CI:-}" ]; then
        sudo apt-get install -y gdb > /dev/null || true
      fi
      mkdir -p "$dir/binaries"
      n=0 kept_kb=0
      for c in "${cores[@]}"; do
        n=$((n + 1))
        exe=$(basename "$c" | sed 's/^core\.[0-9]*\.//; s/!/\//g')
        kb=$(du -k "$c" | cut -f1)
        echo "::group::$c ($exe, $((kb / 1024)) MB)"
        {
          echo "=== $c"
          echo "=== executable: $exe"
          if [ -f "$exe" ]; then
            # basename.PID: two fixtures can share a basename across directories.
            pid=$(basename "$c" | sed 's/^core\.\([0-9]*\)\..*/\1/')
            cp "$exe" "$dir/binaries/$(basename "$exe").$pid" || true
            if [ "$n" -gt "$MAX_BACKTRACES" ]; then
              echo "not backtraced here (more than $MAX_BACKTRACES cores); the core and the binary are in the artifact"
            elif command -v gdb > /dev/null; then
              gdb -batch -ex 'p $_siginfo' -ex 'x/6i $pc' \
                  -ex 'thread apply all bt 40' "$exe" "$c" 2>&1 | grep -v '^\[New LWP' || true
            else
              echo "gdb is not available; the core and the binary are in the artifact"
            fi
          else
            echo "the executable is gone (rebuilt or removed since the crash)"
          fi
          echo
        } 2>&1 | tee -a "$dir/cores/backtraces.txt"
        echo "::endgroup::"
        # Bound the artifact. The backtrace above is kept either way.
        kept_kb=$((kept_kb + kb))
        if [ "$kept_kb" -gt $((MAX_CORE_MB * 1024)) ]; then
          echo "dropped (cores above ${MAX_CORE_MB} MB in total): $c ($exe)" | tee -a "$dir/cores/dropped.txt"
          rm -f "$c"; kept_kb=$((kept_kb - kb))
        fi
      done
    fi

    # ── macOS crash reports ────────────────────────────────────────────────
    if [ "$os" = Darwin ]; then
      reports=${MARCH_CRASH_REPORT_DIR:-$HOME/Library/Logs/DiagnosticReports}
      # ReportCrash writes a report some seconds after the process dies.
      sleep "${MARCH_CRASH_REPORT_WAIT:-15}"
      mkdir -p "$dir/crash-reports"
      if [ -d "$reports" ]; then
        find "$reports" -type f -newer "$dir/.setup-marker" -exec cp {} "$dir/crash-reports/" \; || true
      fi
      found=("$dir"/crash-reports/*)
      echo "${#found[@]} crash report(s) since setup in $reports"
      for r in "${found[@]}"; do echo "  $(basename "$r")"; done
    fi

    # ── dune's log ─────────────────────────────────────────────────────────
    if [ -f "$root/_build/log" ]; then cp "$root/_build/log" "$dir/dune.log" || true; fi

    # ── failed two-node scenarios ──────────────────────────────────────────
    # scripts/two-node.sh removes its work directory only when the scenario
    # passes, so whatever is still there belongs to a failure.
    for w in "${TMPDIR:-/tmp}"/two-node-*.??????; do
      [ -d "$w" ] || continue
      mkdir -p "$dir/two-node"
      cp -R "$w" "$dir/two-node/" || true
      echo "kept two-node work directory $(basename "$w")"
    done

    # A node's work directory can hold sockets and fifos; an upload must not
    # try to read one.
    find "$dir" ! -type f ! -type d -exec rm -f {} + 2>/dev/null || true

    echo
    echo "evidence in $dir:"
    (cd "$dir" && du -sh . 2>/dev/null | sed 's/^/  total /' && find . -type f ! -name '.setup-marker' | sort | sed 's/^/  /' | head -200)
    ;;

  *)
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
    ;;
esac
