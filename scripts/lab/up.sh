#!/usr/bin/env bash
# Start the lab's hosts: four Debian containers, lab-1..lab-4, on a private
# Docker network (march-lab), each with sshd (the lab's ssh key) and a
# stand-in systemctl. Nothing March runs on them until `forge host init` and
# `forge deploy` (scripts/lab/run.sh deploy). See docs/lab.md.
#
#   scripts/lab/up.sh          (re)create the hosts: any old ones are removed
#
# On the network the hosts reach each other by name (lab-2:7946). This
# machine reaches lab-N's sshd at 127.0.0.1:$LAB_PORT_BASE+N and a control
# candidate's API at 127.0.0.1:$LAB_PORT_BASE+100+N, nothing else. Each host
# has a memory limit (LAB_HOST_MEMORY, default 2g), so a node that grows
# without bound is killed inside the lab instead of by the Docker VM's OOM
# killer, which may pick another project's container.
set -u
source "$(dirname "$0")/lib.sh"
lab_prereqs
mkdir -p "$LAB_DIR/logs"

lab_say "building the host image $LAB_IMAGE"
docker build -q -t "$LAB_IMAGE" "$lab_root/scripts/lab/image" > "$LAB_DIR/logs/image.log" 2>&1 \
  || lab_die "the host image did not build (no network for apt?): $(cat "$LAB_DIR/logs/image.log")"

"$(dirname "$0")/down.sh" --quiet
docker network create "$LAB_NET" > /dev/null || fail "docker network create $LAB_NET"

[ -f "$LAB_DIR/id_ed25519" ] || ssh-keygen -q -t ed25519 -N '' -C march-lab -f "$LAB_DIR/id_ed25519" || fail "ssh-keygen"
for h in $LAB_HOSTS; do
  docker run -d --name "$h" --hostname "$h" --network "$LAB_NET" --label march-lab=1 \
    --memory "$LAB_HOST_MEMORY" --memory-swap "$LAB_HOST_MEMORY" \
    -p "127.0.0.1:$(lab_port_ssh "$h"):22" -p "127.0.0.1:$(lab_port_ctl "$h"):7947" \
    "$LAB_IMAGE" > /dev/null || fail "docker run $h (a port in use? set LAB_PORT_BASE)"
  docker cp "$LAB_DIR/id_ed25519.pub" "$h:/root/.ssh/authorized_keys" > /dev/null \
    && docker exec "$h" chown root:root /root/.ssh/authorized_keys || fail "installing the ssh key on $h"
done
lab_ssh_config
for h in $LAB_HOSTS; do
  lab_until 30 "sshd on $h" lab_ssh "$h" true
done
lab_say "up: $LAB_HOSTS on network $LAB_NET (ssh config $LAB_DIR/ssh_config)"
