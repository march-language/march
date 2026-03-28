# Bastion: Distributed Pub/Sub on the Actor System

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Overview

`Bastion.PubSub` is a cluster-wide event bus built on March's actor and supervision primitives. Actors subscribe to named topics and receive messages when any node in the cluster publishes to that topic. It is not limited to WebSocket channels — it is the backbone for cache invalidation, background job coordination, cluster-wide feature flags, live dashboard updates, and anything else that needs broadcast between processes.

---

## Design Principles

- **Local first**: if all subscribers are on the same node, no network hop occurs.
- **At-most-once delivery**: pub/sub is fire-and-forget. For at-least-once or exactly-once, use a job queue on top of Depot.
- **No central broker**: the PubSub adapter is pluggable. The default is process-local (single node). For multi-node, plug in the Redis or native March cluster adapter.
- **Typed topics**: topic names are atoms or typed structs, not raw strings, so typos are compile-time errors.

---

## Starting PubSub

```march
mod MyApp do
  fn start() do
    children = [
      {Bastion.PubSub, name: MyApp.PubSub, adapter: Bastion.PubSub.Local},
      {Depot.Pool, MyApp.Config.db()},
      {Bastion.Endpoint, MyApp.Endpoint, port: 4000}
    ]

    Bastion.Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

---

## Core API

```march
mod Bastion.PubSub do
  # Subscribe the calling actor to a topic
  # Messages arrive as {:pubsub_message, topic, payload}
  fn subscribe(pubsub: Atom, topic: String) -> :ok

  # Unsubscribe the calling actor from a topic
  fn unsubscribe(pubsub: Atom, topic: String) -> :ok

  # Publish a message to all subscribers of a topic on all nodes
  fn broadcast(pubsub: Atom, topic: String, message: Any) -> :ok

  # Publish to all subscribers except the calling process (useful for channel mirrors)
  fn broadcast_from(pubsub: Atom, topic: String, message: Any) -> :ok

  # Synchronous local broadcast — waits for all local subscribers to receive
  # (useful in tests; not recommended in production hot paths)
  fn local_broadcast_sync(pubsub: Atom, topic: String, message: Any) -> :ok

  # List current subscribers on this node (for introspection/debugging)
  fn subscribers(pubsub: Atom, topic: String) -> List(Pid)
end
```

---

## Use Case: Cache Invalidation

When a user record is updated, all nodes invalidate their local HTML fragment caches:

```march
mod MyApp.Users do
  fn update(db: Depot.Pool, user_id: String, params: Map(String, Any)) -> Result(User, _) do
    case MyApp.User.changeset(params) |> Depot.update(db) do
      Ok(user) ->
        # Invalidate caches cluster-wide
        Bastion.PubSub.broadcast(MyApp.PubSub, "cache:invalidate:user:#{user_id}", :invalidate)
        Ok(user)
      Error(cs) ->
        Error(cs)
    end
  end
end

mod MyApp.CacheWorker do
  use Bastion.Actor

  fn init() do
    Bastion.PubSub.subscribe(MyApp.PubSub, "cache:invalidate:user:*")
    %{}
  end

  fn handle_msg({:pubsub_message, topic, :invalidate}, state) do
    user_id = String.split(topic, ":") |> List.last()
    Vault.delete(:user_fragment_cache, user_id)
    state
  end
end
```

---

## Use Case: WebSocket Channel Fanout

Channels use PubSub under the hood for multi-node fanout. When a user sends a chat message, PubSub broadcasts it to all channel processes subscribed to the room topic:

```march
mod MyApp.RoomChannel do
  use Bastion.Channel

  fn join("room:" <> room_id, _payload, socket) do
    Bastion.PubSub.subscribe(MyApp.PubSub, "room:#{room_id}")
    Ok(socket |> assign(:room_id, room_id))
  end

  fn handle_in("message", %{body: body}, socket) do
    room_id = socket.assigns.room_id
    message = %{body: body, user_id: socket.assigns.user_id, at: DateTime.now()}
    Bastion.PubSub.broadcast_from(MyApp.PubSub, "room:#{room_id}", {:new_message, message})
    {:ok, socket}
  end

  fn handle_info({:pubsub_message, _topic, {:new_message, message}}, socket) do
    push(socket, "message", message)
    {:ok, socket}
  end
end
```

---

## Use Case: Cluster-Wide Feature Flags

Feature flags stored in Depot are loaded once at startup and refreshed via PubSub when they change:

```march
mod MyApp.FeatureFlags do
  use Bastion.Actor

  fn init() do
    Bastion.PubSub.subscribe(MyApp.PubSub, "feature_flags:updated")
    flags = load_from_db()
    Vault.put(:feature_flags, :all, flags)
    %{flags: flags}
  end

  fn handle_msg({:pubsub_message, "feature_flags:updated", _}, state) do
    flags = load_from_db()
    Vault.put(:feature_flags, :all, flags)
    %{state with flags: flags}
  end

  fn enabled?(flag_name: Atom) -> Bool do
    case Vault.get(:feature_flags, :all) do
      Some(flags) -> Map.get(flags, flag_name, false)
      None -> false
    end
  end

  pfn load_from_db() do
    Depot.query(MyApp.Repo.pool(), "SELECT name, enabled FROM feature_flags")
    |> List.to_map(fn row -> {String.to_atom(row.name), row.enabled} end)
  end
end

# In a handler
fn show(conn, id) do
  if MyApp.FeatureFlags.enabled?(:new_user_profile) do
    conn |> render("show_v2.html")
  else
    conn |> render("show.html")
  end
end
```

---

## Use Case: Background Job Coordination

Workers coordinate job ownership without a central lock manager:

```march
mod MyApp.ExportWorker do
  use Bastion.Actor

  fn init() do
    Bastion.PubSub.subscribe(MyApp.PubSub, "exports:claimed")
    %{processing: Set.new()}
  end

  fn handle_msg({:pubsub_message, _, {:claimed, export_id}}, state) do
    # Another node claimed this export — remove from local queue if present
    %{state with processing: Set.delete(state.processing, export_id)}
  end

  fn handle_msg({:process, export_id}, state) do
    Bastion.PubSub.broadcast(MyApp.PubSub, "exports:claimed", {:claimed, export_id})
    # ... do the export work
    %{state with processing: Set.put(state.processing, export_id)}
  end
end
```

---

## Adapters

### Local (default — single node)

```march
{Bastion.PubSub, name: MyApp.PubSub, adapter: Bastion.PubSub.Local}
```

Uses a Vault table to track subscriptions and delivers messages directly to process mailboxes. Zero network overhead. No external dependencies.

### Redis

```march
{Bastion.PubSub, name: MyApp.PubSub,
  adapter: Bastion.PubSub.Redis,
  url: Env.fetch!("REDIS_URL")}
```

Publishes to Redis pub/sub channels. Each node runs a subscriber actor that relays incoming messages to local subscribers. Survives node restarts — new nodes pick up messages immediately on reconnect.

### Native Cluster (future)

```march
{Bastion.PubSub, name: MyApp.PubSub,
  adapter: Bastion.PubSub.Cluster,
  nodes: :auto}   # auto-discover via DNS or Kubernetes API
```

Direct process-to-process delivery across March cluster nodes using the actor system's remote messaging. No external broker. Uses a gossip protocol to propagate subscription lists.

---

## Topic Wildcards

Wildcard subscriptions let an actor receive messages from a family of topics:

```march
# Subscribe to all user cache invalidations
Bastion.PubSub.subscribe(MyApp.PubSub, "cache:invalidate:user:*")

# Subscribe to all events for room 42
Bastion.PubSub.subscribe(MyApp.PubSub, "room:42:*")
```

Wildcard matching is handled locally after delivery — the underlying adapter delivers to exact-match subscribers plus any wildcard subscribers on each node.

---

## Supervision

`Bastion.PubSub` is itself a supervised actor. If the PubSub process crashes (e.g., Redis connection drops), the supervisor restarts it. Subscribers are automatically re-subscribed on restart via a `handle_msg(:resubscribe, ...)` hook that each subscriber actor can implement:

```march
fn handle_msg(:resubscribe, state) do
  Bastion.PubSub.subscribe(MyApp.PubSub, "room:#{state.room_id}")
  state
end
```

---

## Open Questions

- How should wildcard subscriptions behave with the Redis adapter? Redis pub/sub supports pattern subscriptions (`PSUBSCRIBE`) — should the adapter use them, or should wildcards always be matched locally?
- Should there be a `Bastion.PubSub.Presence` module (like Phoenix.Presence) built on top of the PubSub system for tracking which users are online in which rooms?
- How does the native cluster adapter handle network partitions? Should it fail open (deliver to reachable nodes) or fail closed (reject broadcasts until the partition heals)?
