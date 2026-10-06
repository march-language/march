# One lab host (scripts/lab/up.sh): Debian with sshd and a stand-in
# systemctl. The recipe is forge/test/test_deploy_e2e.ml's (keep the package
# list in step with it), plus boot.sh, which starts the enabled march units
# when the container starts, as systemd would when a machine boots.
FROM debian:bookworm-slim
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends openssh-server libssl3 zlib1g procps util-linux >/dev/null \
 && rm -rf /var/lib/apt/lists/* && mkdir -p /run/sshd /root/.ssh && chmod 700 /root/.ssh
COPY systemctl /usr/local/bin/systemctl
COPY boot.sh /usr/local/sbin/lab-boot
RUN chmod 755 /usr/local/bin/systemctl /usr/local/sbin/lab-boot
CMD ["/usr/local/sbin/lab-boot"]
