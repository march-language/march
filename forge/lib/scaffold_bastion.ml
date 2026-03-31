(** scaffold_bastion.ml — forge bastion new <name>

    Scaffolds a new Bastion web application skeleton. *)

let write_file path content =
  let oc = open_out path in
  output_string oc content;
  close_out oc

(** Convert snake_case to PascalCase: "my_app" -> "MyApp" *)
let snake_to_pascal s =
  String.split_on_char '_' s
  |> List.filter (fun p -> p <> "")
  |> List.map String.capitalize_ascii
  |> String.concat ""

(* ------------------------------------------------------------------ templates *)

let forge_toml name =
  Printf.sprintf {|[package]
name = "%s"
version = "0.1.0"
type = "app"
description = ""
author = ""

[deps]
bastion = "*"
|} name

(** lib/<name>.march — application entry point *)
let main_source _name pascal =
  Printf.sprintf {|mod %s do

fn router(conn, stats) do
  %s.Router.dispatch(conn, stats)
end

fn main() do
  let stats = BastionDev.new_stats()
  HttpServer.new(4000)
  |> HttpServer.plug(fn conn -> router(conn, stats))
  |> HttpServer.listen()
end

end
|} pascal pascal

(** lib/<name>/router.march — HTTP router *)
let router_source _name pascal =
  Printf.sprintf {|mod %s.Router do

alias HttpServer as H

fn dispatch(conn, stats) do
  let m = H.method(conn)
  let p = H.path_info(conn)
  match (m, p) do
  -- ROUTE: GET /
  (:get, Nil) ->
    %s.Controllers.PageController.index(conn)

  -- ROUTE: GET /_bastion
  (:get, Cons("_bastion", Nil)) ->
    BastionDev.dashboard_handler(conn, stats)

  _ ->
    H.send_resp(conn, 404, "Not Found")
  end
end

end
|} pascal pascal

(** lib/<name>/controllers/page_controller.march *)
let page_controller_source _name pascal =
  Printf.sprintf {|mod %s.Controllers.PageController do

alias HttpServer as H
alias %s.Templates.Layout as Layout
alias %s.Templates.Page.Index as IndexView

fn index(conn) do
  let content = IndexView.render()
  let html    = Layout.wrap(content)
  H.html(conn, 200, IOList.to_string(html))
end

end
|} pascal pascal pascal

(** lib/<name>/templates/layout.march — HTML layout using ~H sigil *)
let layout_source name pascal =
  Printf.sprintf {|mod %s.Templates.Layout do

fn wrap(inner_html) do
  let css_path = Bastion.Assets.static_path("app.css")
  let js_path  = Bastion.Assets.static_path("app.js")
  ~H"""<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>%s</title>
    <link rel="stylesheet" href="${css_path}">
  </head>
  <body>
    ${inner_html}
    <script src="${js_path}"></script>
  </body>
</html>"""
end

end
|} pascal name

(** lib/<name>/templates/page/index.march *)
let page_index_source name pascal =
  Printf.sprintf {|mod %s.Templates.Page.Index do

fn render() do
  ~H"""<div class="container">
  <h1>Welcome to %s!</h1>
  <p>Edit <code>lib/%s/templates/page/index.march</code> to get started.</p>
</div>"""
end

end
|} pascal name name

let config_main =
{|mod Config do
-- Application configuration.
-- Environment-specific settings live in config/dev.march,
-- config/test.march, and config/prod.march.
end
|}

let config_dev =
{|mod Config.Dev do
  let port = 4000
  let debug = true
end
|}

let config_test =
{|mod Config.Test do
  let port = 4001
  let debug = false
end
|}

let config_prod =
{|mod Config.Prod do
  -- Set the PORT environment variable to configure the HTTP port.
  let port = match Env.get("PORT") do
    Some(p) -> string_to_int(p)
    None    -> 4000
  end
end
|}

let app_css name =
  Printf.sprintf {|/* app.css — %s styles */

*, *::before, *::after {
  box-sizing: border-box;
}

body {
  margin: 0;
  font-family: system-ui, -apple-system, sans-serif;
  line-height: 1.5;
}

.container {
  max-width: 960px;
  margin: 0 auto;
  padding: 2rem;
}
|} name

let app_js =
{|// app.js — application JavaScript
|}

let test_helper_source pascal =
  Printf.sprintf {|mod %s.TestHelper do

fn start() do
  :ok
end

end
|} pascal

let test_page_controller_source pascal =
  Printf.sprintf {|mod %s.Controllers.TestPageController do

describe "PageController.index" do
  test "placeholder" do
    assert true
  end
end

end
|} pascal

let editorconfig =
{|root = true

[*]
indent_style = space
indent_size = 2
charset = utf-8
end_of_line = lf
trim_trailing_whitespace = true
insert_final_newline = true

[*.march]
indent_style = space
indent_size = 2
|}

let gitignore = "/.march/\n"

let readme name =
  Printf.sprintf "# %s\n" (String.capitalize_ascii name)

(* ------------------------------------------------------------------ scaffold *)

let scaffold name =
  if Sys.file_exists name then
    Error (Printf.sprintf "directory '%s' already exists" name)
  else
    let pascal = snake_to_pascal name in
    try
      Unix.mkdir name 0o755;
      let mk dir = Project.mkdir_p (Filename.concat name dir) in
      mk "lib";
      mk (Filename.concat "lib" name);
      mk (Filename.concat "lib" (Filename.concat name "controllers"));
      mk (Filename.concat "lib" (Filename.concat name "templates"));
      mk (Filename.concat "lib" (Filename.concat name (Filename.concat "templates" "page")));
      mk "config";
      mk "assets";
      mk (Filename.concat "assets" "css");
      mk (Filename.concat "assets" "js");
      mk "test";
      mk (Filename.concat "test" "controllers");
      let f rel content =
        write_file (Filename.concat name rel) content
      in
      f "forge.toml"                                           (forge_toml name);
      f ".editorconfig"                                        editorconfig;
      f ".gitignore"                                           gitignore;
      f "README.md"                                            (readme name);
      f ("lib/" ^ name ^ ".march")                             (main_source name pascal);
      f ("lib/" ^ name ^ "/router.march")                      (router_source name pascal);
      f ("lib/" ^ name ^ "/controllers/page_controller.march") (page_controller_source name pascal);
      f ("lib/" ^ name ^ "/templates/layout.march")            (layout_source name pascal);
      f ("lib/" ^ name ^ "/templates/page/index.march")        (page_index_source name pascal);
      f "config/config.march"                                  config_main;
      f "config/dev.march"                                     config_dev;
      f "config/test.march"                                    config_test;
      f "config/prod.march"                                    config_prod;
      f "assets/css/app.css"                                   (app_css name);
      f "assets/js/app.js"                                     app_js;
      f "test/test_helper.march"                               (test_helper_source pascal);
      f "test/controllers/test_page_controller.march"          (test_page_controller_source pascal);
      let _ = Sys.command
          (Printf.sprintf "git init %s > /dev/null 2>&1" (Filename.quote name)) in
      Ok ()
    with
    | Unix.Unix_error (e, fn_name, arg) ->
      Error (Printf.sprintf "%s: %s %s" fn_name (Unix.error_message e) arg)
    | Sys_error msg -> Error msg
