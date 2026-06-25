#pragma once
/*
 * march_monitor_registry — cross-node (distributed) monitor table.
 *
 * Local monitors are handled by march_runtime.c (march_monitor_node per
 * actor_meta).  This registry handles the REMOTE side: when node A calls
 * DistLink.monitor(target_pid_on_B), node B receives a MONITOR_REQ frame
 * and calls march_dist_monitor_register to record that watcher.  When the
 * target actor on B exits (or B loses its connection to a peer), B calls
 * march_dist_monitor_fire_pid / march_dist_monitor_fire_nodedown to send
 * MONITOR_FIRE frames back over the wire.
 *
 * Thread-safety: all public functions take an internal mutex.
 */

#include <stdint.h>

/* Reason tags (match DistLink.DownReason on-wire encoding). */
#define MARCH_DIST_REASON_NORMAL   0
#define MARCH_DIST_REASON_KILLED   1
#define MARCH_DIST_REASON_CRASH    2
#define MARCH_DIST_REASON_NODEDOWN 3

/*
 * Register a remote watcher on a local target pid.
 *   target_pid  - the local actor's pid (march Pid(n) integer)
 *   watcher_node - the remote node's node_id string (copied internally)
 *   watcher_pid  - the remote watcher's pid integer
 *   watcher_fd   - the TCP fd for the connection to watcher_node
 *
 * Idempotent for the same (target_pid, watcher_node, watcher_pid) triple.
 */
void march_dist_monitor_register(int64_t target_pid, const char *watcher_node,
                                  int64_t watcher_pid, int watcher_fd);

/*
 * Fire MONITOR_FIRE for all remote watchers of target_pid with the given
 * reason.  Called by actor_green_thread on actor exit (from march_runtime.c).
 *   reason_tag  - one of MARCH_DIST_REASON_*
 *   reason_msg  - extra message string (NULL for non-Crash reasons)
 */
void march_dist_monitor_fire_pid(int64_t target_pid, int reason_tag,
                                  const char *reason_msg);

/*
 * Fire MONITOR_FIRE(NodeDown) for all remote watchers of targets hosted on
 * node_id.  Called by march_reload.c on peer disconnect.
 */
void march_dist_monitor_fire_nodedown(const char *node_id);

/*
 * Remove all watcher entries associated with a specific peer fd (called on
 * connection close so stale fds don't linger).
 */
void march_dist_monitor_clear_fd(int watcher_fd);
