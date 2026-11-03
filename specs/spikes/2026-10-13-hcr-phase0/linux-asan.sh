#!/usr/bin/env bash
# Linux (glibc) ASan/LSan leg of the HCR Phase 0 spike -- THROWAWAY.
# Run INSIDE a march-ci-ubuntu-step6b container with the worktree mounted
# read-only at /mnt:
#   docker exec march-spike-hcr0 bash /mnt/specs/spikes/2026-10-13-hcr-phase0/linux-asan.sh [build|run]
set -uo pipefail
W=/tmp/work
if [ "${1:-run}" = build ]; then
  mkdir -p "$W"
  (cd /mnt && tar --exclude=./_build --exclude=./.claude --exclude=./.march -cf - . 2>/dev/null) | (cd "$W" && tar xf -)
  rm -rf "$W/.git"
  cd "$W" && opam exec -- dune build --root . bin/main.exe @warm-cache > /tmp/build.log 2>&1
  echo "build exit=$?"; tail -5 /tmp/build.log
  exit 0
fi
cd "$W"
rsync -a /mnt/specs/spikes/2026-10-13-hcr-phase0/ "$W/specs/spikes/2026-10-13-hcr-phase0/" 2>/dev/null \
  || cp -r /mnt/specs/spikes/2026-10-13-hcr-phase0/. "$W/specs/spikes/2026-10-13-hcr-phase0/"
export MARCH_RUNTIME_DIR="$W/runtime" MARCH_STDLIB="$W/stdlib"
export MARCH_SANITIZE=1 ASAN_OPTIONS="detect_leaks=1:abort_on_error=0" HCR0_HOME=/tmp/hcr0-home-asan
S="$W/specs/spikes/2026-10-13-hcr-phase0/run.sh"
O=/tmp/hcr0-out
run() { local name="$1"; shift; echo; echo "===== $name"; "$@" 2>&1 | grep -v "^    #[0-9]" | head -40; }
# The project-local CAS (cwd's .march) does not key on HCR0_PATCH_REGISTERS_DROPS:
# clear it so E1' really rebuilds its patch with the registration.
if [ "${1:-run}" = reg ]; then
  rm -rf "$W/.march" /tmp/hcr0-home-asan-reg /tmp/hcr0-out/l-e1r
  run "E1' v1->v2_newshape (patch registers closure drops)" \
      env HCR0_HOME=/tmp/hcr0-home-asan-reg HCR0_PATCH_REGISTERS_DROPS=1 "$S" $O/l-e1r v1 v2_newshape
  nm /tmp/hcr0-out/l-e1r/patch1.so | grep -c clodrop
  exit 0
fi
run "control v1->v1"                 "$S" $O/l-c v1 v1
run "E1 v1->v2_newshape (no drop reg)" "$S" $O/l-e1 v1 v2_newshape
run "E1' v1->v2_newshape (patch registers closure drops)" \
    env HCR0_HOME=/tmp/hcr0-home-asan-reg HCR0_PATCH_REGISTERS_DROPS=1 "$S" $O/l-e1r v1 v2_newshape
run "E2 borrow->owned flip"             "$S" $O/l-e2 v1 v3_owned
run "E2' owned->borrow flip"            "$S" $O/l-e2r v3_owned v1
run "E4 code unload (5 deploys)"        env HCR0_N=50000 "$S" $O/l-e4 v1 v2b_mk_only v1 v2_newshape v1
run "E4 control (never dlclose)"        env HCR0_N=50000 HCR0_NO_UNLOAD=1 "$S" $O/l-e4c v1 v2b_mk_only v1 v2_newshape v1
