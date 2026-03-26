# Bastion: Channels (WebSocket Integration)

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Overview

Channels are being implemented separately but integrate tightly with Bastion. They provide real-time bidirectional communication between the server and client, used by WASM islands for server communication and by the framework itself for live reload in development.

---

## Server-Side Channel

```march
mod MyApp.RoomChannel do
  import Bastion.Channel

  fn join(conn, "room:" <> room_id, params) do
    if authorized?(conn.assigns.current_user, room_id) do
      conn
      |> assign(:room_id, room_id)
      |> Ok()
    else
      Error(:unauthorized)
    end
  end

  fn handle_in(conn, "message:new", %{body: body}) do
    message = MyApp.Messages.create(conn.assigns.db, %{
      room_id: conn.assigns.room_id,
      user_id: conn.assigns.current_user.id,
      body: body
    })

    # Broadcast to all users in the room
    Bastion.PubSub.broadcast("room:" <> conn.assigns.room_id, "message:new", message)

    conn
  end

  fn handle_in(conn, "typing:start", _params) do
    Bastion.PubSub.broadcast_from(conn, "room:" <> conn.assigns.room_id, "typing:start", %{
      user: conn.assigns.current_user.name
    })
    conn
  end
end
```

---

## Client-Side Channel Usage (in WASM Islands)

```march
mod MyApp.Islands.ChatRoom do
  import Bastion.Island
  import Bastion.Channel.Client

  type State = {
    messages: List(Message),
    input: String,
    typing: List(String)
  }

  type Msg =
    | NewMessage(Message)
    | UpdateInput(String)
    | SendMessage
    | UserTyping(String)
    | ChannelJoined

  fn init(props) do
    channel = Channel.join("room:" <> props.room_id)
    Channel.on(channel, "message:new", fn msg -> NewMessage(msg) end)
    Channel.on(channel, "typing:start", fn msg -> UserTyping(msg.user) end)
    %{messages: [], input: "", typing: []}
  end

  fn update(state, msg) do
    case msg do
      NewMessage(message) ->
        {%{state | messages: List.append(state.messages, message)}, Cmd.none()}
      SendMessage ->
        {%{state | input: ""},
         Cmd.channel_push("message:new", %{body: state.input})}
      UpdateInput(text) ->
        {%{state | input: text},
         Cmd.channel_push("typing:start", %{})}
      UserTyping(name) ->
        {%{state | typing: List.append(state.typing, name)}, Cmd.none()}
      _ ->
        {state, Cmd.none()}
    end
  end

  fn view(state) do
    ~H"""
    <div class="chat-room">
      <div class="messages">
        {List.map(state.messages, fn msg ->
          <div class="message">
            <strong>{msg.user_name}:</strong> {msg.body}
          </div>
        end)}
      </div>
      {if List.length(state.typing) > 0 do
        <div class="typing">{String.join(state.typing, ", ")} typing...</div>
      else
        <span></span>
      end}
      <input
        type="text"
        value={state.input}
        @input={fn e -> UpdateInput(e.target.value)}
        @keydown.enter={fn _ -> SendMessage}
      />
    </div>
    """
  end
end
```

---

## Channel Testing

Test WebSocket channel handlers without a real WebSocket connection:

```march
mod MyApp.RoomChannelTest do
  import Bastion.Test.Channel

  fn test "joining a room succeeds for authorized users"() do
    user = TestFixtures.create_user()
    {status, conn} = join(MyApp.RoomChannel, "room:general", %{}, as: user)

    assert status == :ok
    assert conn.assigns.room_id == "general"
  end

  fn test "sending a message broadcasts to the room"() do
    user = TestFixtures.create_user()
    {_, conn} = join(MyApp.RoomChannel, "room:general", %{}, as: user)

    push(conn, "message:new", %{body: "Hello!"})

    assert_broadcast("room:general", "message:new", %{body: "Hello!"})
  end
end
```

---

## Error Handling and Reconnection

WebSocket connections are supervised. When a connection actor crashes:

1. The supervisor restarts the connection actor
2. The client-side Bastion runtime detects the dropped WebSocket and auto-reconnects (with exponential backoff)
3. On reconnect, the server creates a fresh connection actor
4. The client-side WASM islands retain their local state and re-sync with the server

During graceful shutdown (SIGTERM), Bastion sends a close frame to all WebSocket connections, giving clients time to reconnect to another node.
