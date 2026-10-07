# Scenario "hcr_reload_socket_vs_agent": the reload SOCKET of a node and the
# in-process `reload_request` builtin (the control plane's Agent) used at the
# same time, the way hcr_role_policy's deploys meet its Agent's NODE_STATE
# polls (specs/progress/2026-10-06-reload-socket-reads-the-agents-request.md).
#
# The two share one dispatch. The builtin hands it its request through a
# process-global channel (g_vio, set under g_req_lock); the socket thread
# reads each request LINE outside that lock, one byte per read, through the
# same rl_read, which consulted g_vio whatever the fd. A line read while the
# Agent's request was dispatching was read from the Agent's in-memory request
# instead of the socket: empty, so EOF, and the server closed the deploy's
# connection mid-batch (`hcr_deploy: connection closed`, or `Connection reset
# by peer` when the client was still writing). hcr_role_policy hit it about
# one run in ten; here node-a calls the builtin back to back for the whole
# run, so a socket client sending line after line hits the window within a
# few lines.
#
# Pass: every one of the client's lines is answered on one connection, and
# the node reports it ran the builtin.
socks=$(mktemp -d /tmp/hs.XXXXXX)
export MARCH_HOT_RELOAD_SOCKET="$socks/a.sock" HAMMER_STOP="$work/stop"
COMPILE_FLAGS_a="--hot-reload Hammer"
start_node a
wait_line a "hammer: started"
i=0
until [ -S "$MARCH_HOT_RELOAD_SOCKET" ]; do
  i=$((i + 1)); [ "$i" -gt $((TIMEOUT * 10)) ] && fail "no reload socket at $MARCH_HOT_RELOAD_SOCKET"
  sleep 0.1
done
lines=${HAMMER_LINES:-2000}
perl -MIO::Socket::UNIX -e '
  my ($path, $n) = @ARGV;
  my $s = IO::Socket::UNIX->new(Peer => $path) or die "connect: $!\n";
  my $h = "0" x 64;
  for my $i (1 .. $n) {
    print $s "CAS_CHECK $h\n";
    my $r = <$s>;
    defined $r or die "the reload server closed the connection after $i of $n lines\n";
    $r =~ /^(PRESENT|MISSING)$/ or die "line $i answered: $r";
  }
  print "client: $n lines answered\n";
' "$MARCH_HOT_RELOAD_SOCKET" "$lines" > "$work/client.out" 2>&1 \
  || { touch "$work/stop"; fail "$(cat "$work/client.out")"; }
touch "$work/stop"
wait_exit a
rm -rf "$socks"
