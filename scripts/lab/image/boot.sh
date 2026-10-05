#!/bin/sh
# The lab host's PID 1 (scripts/lab/image/Dockerfile): what systemd does when
# a machine boots, then sshd. /run/systemd/system tells `forge host init`
# that a service manager runs here, so it enables the units it writes; every
# enabled unit is started (after a `docker stop`/`docker start` too, which is
# the lab's reboot).
mkdir -p /run/systemd/system /run/sshd
rm -f /run/fake-systemd-*.pid
for u in /etc/fake-systemd/enabled/*; do
  [ -f "$u" ] && systemctl start "$(basename "$u")"
done
exec /usr/sbin/sshd -D -e
