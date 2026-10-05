# Shared by scripts/lab/*.sh: settings, prerequisites, the hermetic forge
# environment and helpers. Sourced, never run. See docs/lab.md.
#
# Settings (environment):
#   LAB_DIR        the lab's state on this machine: the project copy, keys,
#                  ssh config, private HOME, logs (default /tmp/march-lab-<checkout>)
#   LAB_PORT_BASE  host ports: lab-N's sshd on 127.0.0.1:BASE+N, its control
#                  API on 127.0.0.1:BASE+100+N (default 22200)
#   LAB_IMAGE      the host image (default march-lab-host:1)
#   LAB_HOST_MEMORY  each host's memory limit (default 1536m)
#   LAB_NO_BUILD   1: use the compiler and forge already in _build
#   LAB_KEEP       1: run.sh leaves the containers up when it ends

lab_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
LAB_DIR=${LAB_DIR:-/tmp/march-lab-$(basename "$lab_root")}
LAB_PORT_BASE=${LAB_PORT_BASE:-22200}
LAB_IMAGE=${LAB_IMAGE:-march-lab-host:1}
LAB_HOST_MEMORY=${LAB_HOST_MEMORY:-1536m}
LAB_NET=${LAB_NET:-march-lab}
LAB_HOSTS="lab-1 lab-2 lab-3 lab-4"
LAB_PROJECT=lab_app
LAB_STATE=/var/lib/march/$LAB_PROJECT        # the service's HOME on a host
LAB_STATS=$LAB_STATE/lab-stats               # the ingress counters (lab-1)
LAB_MARCH=$lab_root/_build/default/bin/main.exe
LAB_FORGE=$lab_root/_build/default/forge/bin/main.exe
LAB_HCR=$lab_root/_build/default/test/hcr_deploy.exe

lab_say() { printf 'lab: %s\n' "$*" >&2; }
# A missing prerequisite: exit 2, loudly. Never a pass.
lab_die() {
  printf '\n%s\nlab: PREREQUISITE MISSING: %s\nlab: nothing was tested.\n%s\n' \
    "************************************************************************" "$*" \
    "************************************************************************" >&2
  exit 2
}
# A failed assertion inside a scenario: exit 1 with the reason.
fail() { printf 'lab: FAIL: %s\n' "$*" >&2; exit 1; }

lab_port_ssh() { echo $((LAB_PORT_BASE + ${1#lab-})); }
lab_port_ctl() { echo $((LAB_PORT_BASE + 100 + ${1#lab-})); }
lab_node() { case $1 in lab-1) echo "ingress-lab-1" ;; *) echo "work-$1" ;; esac; }
lab_pool() { case $1 in lab-1) echo ingress ;; *) echo work ;; esac; }

# Docker, its daemon, the cross toolchain (zig + the target's sysroot),
# ssh. Sets LAB_TARGET, LAB_SYSROOT_VAR, LAB_SYSROOT.
lab_prereqs() {
  command -v docker > /dev/null 2>&1 || lab_die "docker is not installed"
  docker info > /dev/null 2>&1 || lab_die "docker's daemon is not reachable (start Docker)"
  command -v ssh > /dev/null 2>&1 || lab_die "ssh is not installed"
  command -v ssh-keygen > /dev/null 2>&1 || lab_die "ssh-keygen is not installed"
  command -v zig > /dev/null 2>&1 || lab_die "zig (forge's cross C compiler) is not installed"
  local arch deb
  arch=$(docker info --format '{{.Architecture}}')
  case $arch in
    x86_64 | amd64) LAB_TARGET=linux/amd64; deb=amd64 ;;
    aarch64 | arm64) LAB_TARGET=linux/arm64; deb=arm64 ;;
    *) lab_die "docker runs an architecture the lab does not know: $arch" ;;
  esac
  LAB_SYSROOT_VAR=MARCH_CROSS_SYSROOT_$(echo "$deb" | tr a-z A-Z)
  LAB_SYSROOT=${!LAB_SYSROOT_VAR:-$HOME/.cache/march/cross-sysroot/linux-$deb}
  [ -f "$LAB_SYSROOT/lib/libssl.so.3" ] \
    || lab_die "no $LAB_TARGET cross sysroot at $LAB_SYSROOT (run scripts/fetch-cross-sysroot.sh $deb)"
}

# The compiler, forge and the hcr_deploy client, built from this checkout
# (`--root .`: a worktree nested in another checkout must not build that
# one). The runtime and stdlib are read from the source tree
# (MARCH_RUNTIME_DIR, MARCH_STDLIB), never a stale _build copy.
lab_build() {
  if [ "${LAB_NO_BUILD:-}" != 1 ]; then
    lab_say "building the compiler and forge"
    (cd "$lab_root" && dune build --root . bin/main.exe forge/bin/main.exe test/hcr_deploy.exe) \
      > "$LAB_DIR/logs/build.log" 2>&1 || { cat "$LAB_DIR/logs/build.log" >&2; fail "the build failed"; }
  fi
  for b in "$LAB_MARCH" "$LAB_FORGE" "$LAB_HCR"; do
    [ -x "$b" ] || lab_die "$b is not built (unset LAB_NO_BUILD)"
  done
}

# The hermetic environment every forge run gets: a private HOME (march's
# caches, forge's deploy and operator keys), wrappers for march and forge
# (the compiler finds its stdlib next to its own executable, which a
# symlink's directory is not), the lab's ssh config, the sysroot.
lab_env() {
  mkdir -p "$LAB_DIR/bin" "$LAB_DIR/home" "$LAB_DIR/mhome" "$LAB_DIR/logs"
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$LAB_MARCH" > "$LAB_DIR/bin/march"
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$LAB_FORGE" > "$LAB_DIR/bin/forge"
  chmod +x "$LAB_DIR/bin/march" "$LAB_DIR/bin/forge"
  export PATH="$LAB_DIR/bin:$PATH" HOME="$LAB_DIR/home" MARCH_HOME="$LAB_DIR/mhome"
  export MARCH_RUNTIME_DIR="$lab_root/runtime" MARCH_STDLIB="$lab_root/stdlib"
  export FORGE_SSH_CONFIG="$LAB_DIR/ssh_config"
  export "$LAB_SYSROOT_VAR=$LAB_SYSROOT"
  local eps="" h
  for h in lab-2 lab-3 lab-4; do eps="$eps,127.0.0.1:$(lab_port_ctl "$h")"; done
  export FORGE_CONTROL_ENDPOINTS="${eps#,}"
}

lab_ssh_config() {
  local h
  : > "$LAB_DIR/ssh_config"
  for h in $LAB_HOSTS; do
    printf 'Host %s\n  HostName 127.0.0.1\n  Port %s\n  User root\n  IdentityFile %s\n  IdentitiesOnly yes\n  StrictHostKeyChecking no\n  UserKnownHostsFile /dev/null\n  LogLevel ERROR\n  ConnectTimeout 5\n' \
      "$h" "$(lab_port_ssh "$h")" "$LAB_DIR/id_ed25519" >> "$LAB_DIR/ssh_config"
  done
}

lab_ssh() { local h=$1; shift; ssh -F "$LAB_DIR/ssh_config" "$h" "$@"; }
lab_exec() { local h=$1; shift; docker exec "$h" sh -c "$*"; }

# lab_forge <args...>: forge in the lab's project, output kept in
# $LAB_DIR/logs/forge-<n>.log and in $LAB_OUT; returns forge's status.
lab_forge_n=0
lab_forge() {
  lab_forge_n=$((lab_forge_n + 1))
  local log
  log="$LAB_DIR/logs/forge-$(printf %03d $lab_forge_n)-${LAB_SCENARIO:-x}.log"
  echo "\$ forge $*" > "$log"
  (cd "$LAB_DIR/app" && forge "$@") >> "$log" 2>&1
  local rc=$?
  echo "(exit $rc)" >> "$log"
  LAB_OUT=$(cat "$log")
  lab_say "forge $* (exit $rc; $log)"
  return $rc
}

# lab_forge_ok <args...>: forge, and a failure fails the scenario with what
# forge and the nodes said.
lab_forge_ok() {
  lab_forge "$@" && return 0
  echo "$LAB_OUT" >&2
  lab_node_logs 30 >&2
  fail "forge $* failed"
}

lab_expect() {   # lab_expect <what> <text> <substring>...
  local what=$1 text=$2; shift 2
  local s
  for s in "$@"; do
    case $text in *"$s"*) ;; *) echo "$text" >&2; fail "$what: expected '$s'" ;; esac
  done
}

# lab_until <seconds> <description> <command...>: poll every 0.5 s.
lab_until() {
  local limit=$1 what=$2; shift 2
  local end=$((SECONDS + limit))
  until "$@" > /dev/null 2>&1; do
    [ $SECONDS -ge $end ] && fail "timed out after ${limit}s waiting for: $what"
    sleep 0.5
  done
}

lab_running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2> /dev/null)" = true ]; }

lab_node_log() {   # lab_node_log <host> [lines]
  lab_exec "$1" "tail -n ${2:-40} /var/log/march-$(lab_pool "$1").service.log 2>/dev/null"
}
lab_node_logs() {
  local h
  for h in $LAB_HOSTS; do
    lab_running "$h" || { echo "--- $h: not running"; continue; }
    echo "--- $h ($(lab_node "$h")), last ${1:-20} lines"
    lab_node_log "$h" "${1:-20}"
  done
}

# The node's status file (offers, sessions, the topology digest it applied).
lab_status() { lab_exec "$1" "cat $LAB_STATE/run/$(lab_pool "$1").status 2>/dev/null"; }

# The ingress counters: lab_stats prints the file; lab_stat <key> one value
# (0 when absent); lab_stat_sum <prefix> the sum of the keys starting so.
lab_stats() { lab_exec lab-1 "cat $LAB_STATS 2>/dev/null"; }
lab_stat() { lab_stats | awk -v k="$1" '$1 == k { print $2; f = 1 } END { if (!f) print 0 }'; }
lab_stat_sum() { lab_stats | awk -v p="$1" 'index($1, p) == 1 && $2 ~ /^[0-9]+$/ { s += $2 } END { print s + 0 }'; }
lab_ended() { echo $(( $(lab_stat finished) + $(lab_stat drained) + $(lab_stat refused) + $(lab_stat failed) )); }

# lab_traffic_flows [n]: n more sessions finish (default 10) within 60 s.
lab_traffic_flows() {
  local want=$(( $(lab_stat finished) + ${1:-10} ))
  lab_until 60 "$want sessions finished" lab_stat_ge finished "$want"
}
lab_stat_ge() { [ "$(lab_stat "$1")" -ge "$2" ]; }

# lab_traffic <every ms> [most in flight]: how fast lab-1's hook starts
# sessions (`0` pauses). It re-reads the file before each session.
lab_traffic() {
  local f=$LAB_STATE/lab-traffic
  lab_exec lab-1 "echo '$1 ${2:-4}' > $f.tmp && chmod 644 $f.tmp && mv $f.tmp $f"
}

# A node's process: resident memory (KB) and live heap objects (the probe
# file its hook writes every 5 s).
lab_rss_kb() {
  lab_exec "$1" "p=\$(pgrep -f /opt/march/$LAB_PROJECT/ | head -1); [ -n \"\$p\" ] && ps -o rss= -p \$p" | tr -d ' '
}
lab_live() { lab_exec "$1" "sed -n 's/^live //p' $LAB_STATE/lab-probe 2>/dev/null"; }

# Which work host offers Order.Ledger now (its status file has the offer).
lab_ledger_hosts() {
  local h
  for h in lab-2 lab-3 lab-4; do
    lab_running "$h" || continue
    lab_status "$h" | grep -q '^offer Order.Ledger ' && echo "$h"
  done
}

# The control-plane leader's host, asked of each candidate's control API.
lab_leader() {
  local h
  for h in lab-2 lab-3 lab-4; do
    lab_running "$h" || continue
    if "$LAB_HCR" api "127.0.0.1:$(lab_port_ctl "$h")" LEADER 2> /dev/null | grep -q '^LEADER yes'; then echo "$h"; return 0; fi
  done
  return 1
}

# lab_snapshot <name>: the counters now, kept for a later lab_delta.
lab_snapshot() { lab_stats > "$LAB_DIR/snap-$1"; }
lab_delta() {   # lab_delta <name> <key>: how much <key> grew since the snapshot
  local before
  before=$(awk -v k="$2" '$1 == k { print $2; f = 1 } END { if (!f) print 0 }' "$LAB_DIR/snap-$1")
  echo $(( $(lab_stat "$2") - before ))
}

# What a scenario reports on success: a line kept in $LAB_DIR/results.
lab_note() { lab_say "$*"; echo "$LAB_SCENARIO: $*" >> "$LAB_DIR/notes"; }
