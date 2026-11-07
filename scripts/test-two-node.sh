#!/usr/bin/env bash
# Exercise the real harness with shell nodes: no compiler or network needed.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/two-node-test.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/scripts" "$scratch/test/two_node/check" "$scratch/tmp"
cp "$root/scripts/two-node.sh" "$scratch/scripts/"
dir=$scratch/test/two_node/check
cat > "$scratch/compiler" <<'COMPILER'
#!/usr/bin/env bash
set -eu
# The harness invokes --compile -o OUTPUT SOURCE.
cp "$4" "$3"
chmod +x "$3"
COMPILER
chmod +x "$scratch/compiler"
for n in a b c; do
  printf '#!/usr/bin/env bash\necho ready\n' > "$dir/node_$n.march"
done
run_case() {
  local want=$1 status=0
  TMPDIR="$scratch/tmp" MARCH_BIN="$scratch/compiler" TWO_NODE_PREBUILT='' MARCH_SANITIZE='' \
    bash "$scratch/scripts/two-node.sh" check > "$scratch/output" 2>&1 || status=$?
  if [ "$status" -ne "$want" ]; then
    cat "$scratch/output"
    echo "expected exit $want, got $status" >&2
    exit 1
  fi
}
# Waiting clears the PID; the harness must still remember that the node ran.
for n in a b c; do
  printf 'start_node %s\nwait_exit %s\n' "$n" "$n" > "$dir/scenario.sh"
  run_case 1
  grep -q "node_$n.expected" "$scratch/output"
  printf 'ready\n' > "$dir/node_$n.expected"
  run_case 0
  rm "$dir/node_$n.expected"
done
# Nodes compiled but never started need no golden; restarts count too.
printf 'start_node a\nwait_exit a\nstart_node a\nwait_exit a\n' > "$dir/scenario.sh"
run_case 1
grep -q 'node_a.expected' "$scratch/output"
printf 'ready\nready\n' > "$dir/node_a.expected"
run_case 0
printf 'wrong\n' > "$dir/node_a.expected"
run_case 1
grep -q 'output differs' "$scratch/output"
# Killing a long-lived server also clears its PID, not its golden obligation.
rm "$dir/node_a.expected"
printf '#!/usr/bin/env bash\necho ready\nexec sleep 30\n' > "$dir/node_a.march"
printf 'start_node a\nwait_line a ready\nkill_node a\n' > "$dir/scenario.sh"
run_case 1
grep -q 'node_a.expected' "$scratch/output"
echo 'test-two-node: all cases passed'
