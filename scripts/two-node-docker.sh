#!/usr/bin/env bash
# Run two-node scenarios inside a Linux container, from any host.
#
#   scripts/two-node-docker.sh <scenario>...    # e.g. partition
#   scripts/two-node-docker.sh --all            # every scenario
#
# Why: `partition` drops packets with iptables, which needs Linux and root
# (scripts/two-node.sh exits 3, "skipped", elsewhere). The container gets
# NET_ADMIN and runs as root, so the fault applies to its own loopback and
# never touches the host. Both nodes run in the one container: the scenario
# drops the scenario port, not a network.
#
# The checkout is bind-mounted; the Linux build goes to a named volume
# (MARCH_TWO_NODE_VOLUME, default march-two-node-build), never the host's
# _build (a macOS _build handed to Linux fails confusingly). Image:
# MARCH_TWO_NODE_IMAGE, default march-two-node, built from
# ci/Dockerfile.two-node when missing.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
image=${MARCH_TWO_NODE_IMAGE:-march-two-node}
volume=${MARCH_TWO_NODE_VOLUME:-march-two-node-build}

[ $# -gt 0 ] || { echo "usage: scripts/two-node-docker.sh <scenario>... | --all" >&2; exit 2; }
command -v docker > /dev/null || { echo "two-node-docker: docker not found" >&2; exit 2; }
docker info > /dev/null 2>&1 || { echo "two-node-docker: the docker daemon is not running" >&2; exit 2; }

if ! docker image inspect "$image" > /dev/null 2>&1; then
  echo "two-node-docker: building $image from ci/Dockerfile.two-node (once; slow)" >&2
  docker build -f "$root/ci/Dockerfile.two-node" -t "$image" "$root" || exit 2
fi

if [ "$1" = --all ]; then set -- $(ls "$root/test/two_node"); fi

# The runtime and stdlib reach the build dir only through a rule that depends
# on them; bin's warm-cache alias does (and pre-warms the stdlib cache).
docker run --rm --cap-add NET_ADMIN \
  -v "$root":/work -v "$volume":/lbuild -w /work \
  -e TWO_NODE_TIMEOUT="${TWO_NODE_TIMEOUT:-60}" \
  "$image" bash -c '
    export PATH=/home/opam/.opam/5.3.0/bin:$PATH
    eval "$(opam env --root /home/opam/.opam --switch 5.3.0 2> /dev/null)"
    dune build --root . --build-dir /lbuild bin/main.exe @bin/warm-cache > /tmp/build.log 2>&1 \
      || { tail -40 /tmp/build.log; exit 2; }
    status=0
    for s in "$@"; do
      MARCH_BIN=/lbuild/default/bin/main.exe HOME=/tmp/home scripts/two-node.sh "$s" || status=1
    done
    exit $status
  ' two-node-docker "$@"
