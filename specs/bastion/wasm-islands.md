# Bastion: WASM Islands

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Concept

Most of the page is server-rendered HTML — fast, cacheable, works without JavaScript. Specific interactive components are designated as **islands**: self-contained March modules compiled to WASM that hydrate in the browser.

This follows the islands architecture (as popularized by Astro), but with a unique advantage: island components are written in March, share types with the server, and run as actors in the WASM runtime.

---

## Declaring an Island

An island is a March module that implements the `Bastion.Island` behaviour:

```march
mod MyApp.Islands.SearchBar do
  import Bastion.Island

  # The state type for this island
  type State = {
    query: String,
    results: List(User),
    loading: Bool
  }

  # Messages this island can receive
  type Msg =
    | UpdateQuery(String)
    | SubmitSearch
    | SearchResults(List(User))
    | Reset

  # Initial state
  fn init(props: %{users: List(User)}) -> State do
    %{query: "", results: props.users, loading: false}
  end

  # State transitions — pattern matched on message type
  fn update(state: State, msg: Msg) -> {State, Cmd(Msg)} do
    case msg do
      UpdateQuery(q) ->
        {%{state | query: q}, Cmd.none()}

      SubmitSearch ->
        {%{state | loading: true}, Cmd.http_get(
          "/api/users/search?q=" <> state.query,
          fn response -> SearchResults(JSON.decode(response.body))
        )}

      SearchResults(users) ->
        {%{state | results: users, loading: false}, Cmd.none()}

      Reset ->
        {%{state | query: "", results: []}, Cmd.none()}
    end
  end

  # Render the island's DOM
  fn view(state: State) -> Fragment do
    ~H"""
    <div class="search-bar">
      <input
        type="text"
        value={state.query}
        @input={fn e -> UpdateQuery(e.target.value)}
        @keydown.enter={fn _ -> SubmitSearch}
        placeholder="Search users..."
      />
      {if state.loading do
        <div class="spinner">Loading...</div>
      else
        <ul class="results">
          {List.map(state.results, fn user ->
            <li>{user.name} — {user.email}</li>
          end)}
        </ul>
      end}
    </div>
    """
  end
end
```

---

## Embedding Islands in Server Templates

Islands are placed in server-rendered templates using the `<Island>` component:

```march
fn index(conn) do
  users = MyApp.Users.list_all(conn.assigns.db)

  conn |> html(~H"""
  <PageLayout title="Users">
    <h1>User Directory</h1>

    <!-- This part is static SSR HTML -->
    <p>We have {List.length(users)} registered users.</p>

    <!-- This part becomes a WASM island in the browser -->
    <Island module={MyApp.Islands.SearchBar} props={%{users: users}} />

    <!-- Another island, independent actor -->
    <Island module={MyApp.Islands.ChatWidget} props={%{room: "general"}} />
  </PageLayout>
  """)
end
```

The server renders the island's initial HTML (by calling `init` then `view` at SSR time), wraps it in a marker element with metadata, and the client-side Bastion runtime hydrates it into a live WASM actor.

---

## Server-Rendered Island HTML

The server outputs something like:

```html
<div data-bastion-island="MyApp.Islands.SearchBar"
     data-bastion-props="eyJ1c2VycyI6Wy4uLl19"
     data-bastion-wasm="/static/islands/search_bar.wasm">
  <!-- SSR'd initial view -->
  <div class="search-bar">
    <input type="text" value="" placeholder="Search users..." />
    <ul class="results">
      <li>Alice — alice@example.com</li>
      <li>Bob — bob@example.com</li>
    </ul>
  </div>
</div>
```

The Bastion client runtime (`bastion.js`) finds these markers, loads the WASM module, and hydrates the island — attaching event handlers and making it interactive.

---

## Island-to-Island Communication

Islands on the same page can send typed messages to each other via a client-side PubSub:

```march
# In the SearchBar island
fn update(state, SubmitSearch) do
  {%{state | loading: true},
   Cmd.batch([
     Cmd.http_get("/api/users/search?q=" <> state.query, SearchResults),
     Cmd.broadcast("search:updated", %{query: state.query})
   ])}
end

# In the Analytics island, subscribe to search events
fn init(props) do
  Bastion.Island.subscribe("search:updated")
  %{searches: []}
end
```

---

## Island-to-Server Communication

Islands communicate with the server via the WebSocket channel. Messages are typed end-to-end:

```march
# Client-side island
fn update(state, SaveDraft) do
  {state, Cmd.channel_push("drafts:save", %{content: state.editor_content})}
end

# Server-side channel handler
mod MyApp.DraftChannel do
  import Bastion.Channel

  fn handle_in(conn, "drafts:save", %{content: content}) do
    MyApp.Drafts.save(conn.assigns.current_user, content)
    conn |> push("drafts:saved", %{status: "ok"})
  end
end
```

---

## WASM Compilation Pipeline

```
March Source (.march files)
    │
    ├── Server target: OCaml 5.3.0 → native binary
    │
    └── WASM target: March → WASM (per-island .wasm files)
         │
         ▼
    /priv/static/islands/
    ├── search_bar.wasm
    ├── chat_widget.wasm
    └── notification_bell.wasm
```

Forge handles both compilation targets. `forge build` produces the server binary and all WASM island bundles. In development, `forge dev` watches for changes and recompiles affected islands incrementally.

---

## Open Questions

- **WASM compilation target**: Which WASM toolchain? Direct compilation from March AST, or via an intermediate representation?
- **WASM actor runtime**: How are March actors (green threads, mailboxes, `Pid(a)`) implemented in the WASM target? Does each island get its own WASM instance, or do they share one with cooperative scheduling?
- **Island serialization**: How are props serialized from server to client for hydration? JSON is the natural choice, but should there be a binary fast-path for large datasets?
- **Hot code reloading**: Can islands be hot-swapped in development without losing state?

See [open-questions.md](open-questions.md) for the full list.
