# Bastion: Forge Generator Commands

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Project Generators

```bash
# New Bastion project (with Depot)
forge new my_app

# New project without database integration
forge new my_app --no-db
```

---

## Resource Generators

```bash
# Generate a handler with standard CRUD actions
forge gen.handler Users index show create update delete

# Generate a context module with Depot queries
forge gen.context Accounts User users name:string email:string role:string

# Generate a database migration
forge gen.migration create_users

# Run migrations
forge depot.migrate
```

---

## Auth Generators

```bash
# Cookie-based session auth (traditional web app)
forge gen.auth --strategy session

# Token-based auth (API / SPA)
forge gen.auth --strategy token

# OAuth provider integration
forge gen.auth --strategy oauth --provider github

# Magic link / passwordless auth
forge gen.auth --strategy magic_link
```

Each auth generator produces:

- Migration files for the users table (via Depot)
- A `MyApp.Auth` module with login/logout/registration functions
- Typed middleware plugs (`require_auth`, `load_current_user`)
- Handler functions for login/registration pages or API endpoints
- Templates for login/registration forms (for session and magic_link strategies)

---

## WebSocket and Island Generators

```bash
# Generate a WebSocket channel handler
forge gen.channel Room

# Generate a WASM island component
forge gen.island SearchBar
```

---

## Development Commands

```bash
# Start development server with live reload
forge dev

# Build for production (server binary + WASM islands)
forge build --release

# Build with all static assets embedded in the binary
forge build --release --embed-assets

# Run tests
forge test
forge test --filter "auth"
forge test --coverage
```
