(** scaffold_bastion.ml — generate a new Bastion web application skeleton.

    Called by [cmd_bastion_new.ml].  Creates the full directory tree:

      APP/
        forge.toml
        .editorconfig  .gitignore  README.md
        config/  config.march  dev.march  test.march  prod.march
        lib/
          APP.march                          (application module + main)
          APP/
            router.march                     (pattern-dispatch router)
            controllers/page_controller.march
            templates/layout.march
            templates/page/index.march
        priv/static/css/app.css
        priv/static/js/app.js
        test/
          test_helper.march
          controllers/test_page_controller.march
*)

(* ------------------------------------------------------------------ helpers *)

let write_file path content =
  Project.mkdir_p (Filename.dirname path);
  let oc = open_out path in
  output_string oc content;
  close_out oc

(** "my_app" -> "MyApp" *)
let snake_to_pascal s =
  String.split_on_char '_' s
  |> List.filter (fun p -> p <> "")
  |> List.map String.capitalize_ascii
  |> String.concat ""

(* ---------------------------------------------------------------- templates *)

let forge_toml name =
  Printf.sprintf
{|[package]
name = "%s"
version = "0.1.0"
type = "app"
description = "A Bastion web application"
author = ""

[deps]
|}
    name

(* ---------- config/ -------------------------------------------------- *)

let config_config _name pascal =
  Printf.sprintf
{|-- config/config.march — base configuration shared across all environments.
--
-- Add values here that are the same in every environment.
-- Environment-specific overrides live in dev/test/prod.march.

mod %sConfig do

  doc "Application name atom used as the Config namespace."
  pub fn ns() do
    :%s
  end

end
|}
    pascal (String.lowercase_ascii pascal)

let config_dev name pascal =
  Printf.sprintf
{|-- config/dev.march — development environment overrides.
-- Loaded when MARCH_ENV=dev (the default for 'forge bastion server').

mod %sDevConfig do

  doc "Apply development configuration."
  pub fn configure() do
    Config.put_endpoint(4000, "localhost", "dev-secret-key-base-replace-in-prod")
    Config.put(:%s, :debug, true)
    Config.put(:%s, :code_reloader, true)
    Config.put(:%s, :app_name, "%s")
  end

end
|}
    pascal
    (String.lowercase_ascii pascal)
    (String.lowercase_ascii pascal)
    (String.lowercase_ascii pascal)
    name

let config_test name pascal =
  Printf.sprintf
{|-- config/test.march — test environment configuration.
-- Loaded when MARCH_ENV=test.

mod %sTestConfig do

  doc "Apply test configuration."
  pub fn configure() do
    Config.put_endpoint(4001, "localhost", "test-secret-key-base")
    Config.put(:%s, :debug, false)
    Config.put(:%s, :app_name, "%s")
  end

end
|}
    pascal
    (String.lowercase_ascii pascal)
    (String.lowercase_ascii pascal)
    name

let config_prod pascal =
  Printf.sprintf
{|-- config/prod.march — production environment configuration.
-- Loaded when MARCH_ENV=prod.
-- Values are read from environment variables at runtime.

mod %sProdConfig do

  doc "Apply production configuration.  Reads PORT and SECRET_KEY_BASE from env."
  pub fn configure() do
    let port   = Env.get_int("PORT", 4000)
    let secret = Env.require("SECRET_KEY_BASE")
    let host   = Env.get("PHX_HOST", "example.com")
    Config.put_endpoint(port, host, secret)
    Config.put(:%s, :debug, false)
  end

end
|}
    pascal
    (String.lowercase_ascii pascal)

(* ---------- lib/APP.march ------------------------------------------- *)

let app_source name pascal =
  Printf.sprintf
{|-- %s — Bastion web application entry point.
--
-- Start the dev server with:
--   forge bastion server
--
-- List routes with:
--   forge bastion routes

mod %s do

  -- Load the configuration for the current environment.
  pfn load_config() do
    match Config.env() do
    :dev  -> %sDevConfig.configure()
    :test -> %sTestConfig.configure()
    :prod -> %sProdConfig.configure()
    end
  end

  doc "Application entry point.  Starts the HTTP server."
  fn main() do
    load_config()
    let port  = Config.endpoint_port(4000)
    let stats = BastionDev.new_stats()

    -- Build the request pipeline:
    -- request_timer -> router -> live_reload (dev only) -> finish_timer
    let pipeline = fn conn ->
      let c0 = BastionDev.request_timer(conn)
      let c1 = %s.Router.dispatch(c0, stats)
      let c2 = if Config.is_dev() then BastionDev.inject_live_reload(c1) else c1
      BastionDev.finish_timer(c2)
    end

    println("[%s] listening on http://localhost:" ++ int_to_string(port))
    if Config.is_dev() do
      println("[%s] dev dashboard at http://localhost:" ++ int_to_string(port) ++ "/_bastion")
    else :ok end

    HttpServer.new(port)
    |> HttpServer.plug(pipeline)
    |> HttpServer.listen()
  end

end
|}
    name pascal pascal pascal pascal pascal pascal pascal

(* ---------- lib/APP/router.march ------------------------------------ *)

let router_source pascal =
  Printf.sprintf
{|-- %s.Router — request dispatcher.
--
-- Add routes here.  Each arm maps (method, path_segments) to a controller.
-- The BastionDev dashboard and live-reload routes are wired in automatically
-- when Config.is_dev() is true.
--
-- Route patterns:
--   (:get,    [])              -> root path "/"
--   (:get,    ["users"])       -> "/users"
--   (:get,    ["users", id])   -> "/users/:id" (id bound as string)
--   (:post,   ["users"])       -> "POST /users"

mod %s.Router do

  doc "Dispatch conn to the appropriate controller action."
  pub fn dispatch(conn, stats) do
    let m = HttpServer.method(conn)
    let p = HttpServer.path_info(conn)
    match (m, p) do
    -- ROUTE: GET /
    (:get, []) ->
      %s.PageController.index(conn)

    -- ROUTE: GET /_bastion  (dev dashboard)
    (:get, ["_bastion"]) ->
      BastionDev.dashboard_handler(conn, stats)

    -- ROUTE: GET /_bastion/live_reload  (SSE live-reload endpoint)
    (:get, ["_bastion", "live_reload"]) ->
      BastionDev.live_reload_handler(conn)

    _ ->
      HttpServer.send_resp(conn, 404, "Not Found")
    end
  end

end
|}
    pascal pascal pascal

(* ---------- lib/APP/controllers/page_controller.march -------------- *)

let page_controller_source pascal =
  Printf.sprintf
{|-- %s.PageController — handles page-level requests.

mod %s.PageController do

  doc "Renders the home page."
  pub fn index(conn) do
    let html = %s.Templates.Layout.wrap(%s.Templates.Page.Index.render())
    HttpServer.send_resp(conn, 200, html)
  end

end
|}
    pascal pascal pascal pascal

(* ---------- lib/APP/templates/layout.march ------------------------- *)

let layout_source name pascal =
  Printf.sprintf
{|-- %s.Templates.Layout — base HTML layout.
--
-- Wrap any page body with Layout.wrap/1.

mod %s.Templates.Layout do

  doc "Wrap inner_html in the base HTML page shell."
  pub fn wrap(inner_html) do
    "<!DOCTYPE html>" ++
    "<html lang=\"en\">" ++
    "<head>" ++
    "<meta charset=\"UTF-8\">" ++
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">" ++
    "<title>%s</title>" ++
    "<link rel=\"stylesheet\" href=\"/static/css/app.css\">" ++
    "</head>" ++
    "<body>" ++
    inner_html ++
    "<script src=\"/static/js/app.js\"></script>" ++
    "</body>" ++
    "</html>"
  end

end
|}
    pascal pascal name

(* ---------- lib/APP/templates/page/index.march --------------------- *)

let page_index_source name pascal =
  Printf.sprintf
{|-- %s.Templates.Page.Index — home page template.

mod %s.Templates.Page.Index do

  doc "Render the home page body."
  pub fn render() do
    "<main class=\"hero\">" ++
    "<h1>Welcome to %s!</h1>" ++
    "<p>Your Bastion app is running. Edit <code>lib/%s/templates/page/index.march</code> to get started.</p>" ++
    "<ul>" ++
    "<li><a href=\"/_bastion\">Dev dashboard</a></li>" ++
    "</ul>" ++
    "</main>"
  end

end
|}
    pascal pascal name name

(* ---------- priv/static -------------------------------------------- *)

let app_css name =
  Printf.sprintf
{|/* priv/static/css/app.css — %s stylesheet */

*, *::before, *::after { box-sizing: border-box; }

body {
  font-family: system-ui, sans-serif;
  margin: 0;
  padding: 0;
  background: #f9fafb;
  color: #111827;
}

.hero {
  max-width: 720px;
  margin: 80px auto;
  padding: 0 24px;
}

h1 { font-size: 2rem; margin-bottom: 0.5rem; }
p  { color: #6b7280; }
a  { color: #4f46e5; }
code { background: #e5e7eb; padding: 2px 6px; border-radius: 4px; font-size: 0.9em; }
|}
    name

let app_js _name =
  {|// priv/static/js/app.js — client-side JavaScript entry point
// BastionDev live-reload is injected automatically in dev mode.

console.log("[app.js] loaded");
|}

(* ---------- test/ -------------------------------------------------- *)

let test_helper_source pascal =
  Printf.sprintf
{|-- test/test_helper.march — shared test setup for %s.

mod %sTest.Helper do

  doc "Assert two values are equal, printing a message on failure."
  pub fn assert_equal(expected, actual, label) do
    if expected == actual do
      println("  PASS: " ++ label)
    else
      println("  FAIL: " ++ label ++ " — expected: " ++ inspect(expected) ++ ", got: " ++ inspect(actual))
    end
  end

end
|}
    pascal pascal

let test_page_controller_source pascal =
  Printf.sprintf
{|-- test/controllers/test_page_controller.march — unit tests for PageController.

mod %sTest.PageControllerTest do

  fn test_index_returns_200() do
    -- Build a minimal test conn pointing at GET /
    let conn = HttpServer.test_conn(:get, "/")
    let result = %s.PageController.index(conn)
    let status = HttpServer.status(result)
    %sTest.Helper.assert_equal(200, status, "index returns 200")
  end

  fn test_index_body_contains_welcome() do
    let conn   = HttpServer.test_conn(:get, "/")
    let result = %s.PageController.index(conn)
    let body   = HttpServer.resp_body(result)
    let found  = string_contains(body, "Welcome")
    %sTest.Helper.assert_equal(true, found, "index body contains Welcome")
  end

  fn main() do
    test_index_returns_200()
    test_index_body_contains_welcome()
    println("PageController tests done.")
  end

end
|}
    pascal pascal pascal pascal pascal

(* ---------- dotfiles ------------------------------------------------ *)

let editorconfig =
  "root = true\n\n\
   [*]\n\
   indent_style = space\n\
   indent_size = 2\n\
   charset = utf-8\n\
   end_of_line = lf\n\
   trim_trailing_whitespace = true\n\
   insert_final_newline = true\n\n\
   [*.march]\n\
   indent_style = space\n\
   indent_size = 2\n"

let gitignore = "/.march/\n/priv/static/assets/\n"

let readme name =
  Printf.sprintf
{|# %s

A [Bastion](https://march-lang.org/bastion) web application built with March.

## Getting started

```
forge bastion server          # start dev server (http://localhost:4000)
forge bastion routes          # list all routes
forge test                    # run tests
```

## Project layout

```
config/         environment-specific configuration
lib/            application source (controllers, templates, router)
priv/static/    CSS, JS, and other static assets
test/           test files
```
|}
    (String.capitalize_ascii name)

(* ------------------------------------------------------------------ scaffold *)

(** Scaffold a full Bastion application directory under [name].
    Returns [Ok ()] on success or [Error msg] on failure. *)
let scaffold name =
  if Sys.file_exists name then
    Error (Printf.sprintf "directory '%s' already exists" name)
  else
    try
      let pascal = snake_to_pascal name in
      let j p = Filename.concat name p in

      (* top-level *)
      Unix.mkdir name 0o755;
      write_file (j "forge.toml")     (forge_toml name);
      write_file (j ".editorconfig")  editorconfig;
      write_file (j ".gitignore")     gitignore;
      write_file (j "README.md")      (readme name);

      (* config/ *)
      write_file (j "config/config.march") (config_config name pascal);
      write_file (j "config/dev.march")    (config_dev name pascal);
      write_file (j "config/test.march")   (config_test name pascal);
      write_file (j "config/prod.march")   (config_prod pascal);

      (* lib/ *)
      write_file (j ("lib/" ^ name ^ ".march"))
        (app_source name pascal);
      write_file (j ("lib/" ^ name ^ "/router.march"))
        (router_source pascal);
      write_file (j ("lib/" ^ name ^ "/controllers/page_controller.march"))
        (page_controller_source pascal);
      write_file (j ("lib/" ^ name ^ "/templates/layout.march"))
        (layout_source name pascal);
      write_file (j ("lib/" ^ name ^ "/templates/page/index.march"))
        (page_index_source name pascal);

      (* priv/static/ *)
      write_file (j "priv/static/css/app.css") (app_css name);
      write_file (j "priv/static/js/app.js")   (app_js name);

      (* test/ *)
      write_file (j "test/test_helper.march")
        (test_helper_source pascal);
      write_file (j "test/controllers/test_page_controller.march")
        (test_page_controller_source pascal);

      let _ = Sys.command
          (Printf.sprintf "git init %s > /dev/null 2>&1" (Filename.quote name)) in
      Ok ()
    with
    | Unix.Unix_error (e, fn, arg) ->
      Error (Printf.sprintf "%s: %s %s" fn (Unix.error_message e) arg)
    | Sys_error msg -> Error msg
