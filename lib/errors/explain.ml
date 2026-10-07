(** [march --explain <slug>]: the per-code pages.

    The pages are [specs/lang/errors/<slug>.md] (canonical), embedded at build
    time as {!Explain_pages.pages} and rendered for the site as
    [docs/errors/<slug>.md] by [scripts/gen-lang-docs.py]. A code without a
    page is fine (pages accrue); a page whose slug is not in {!Code.all} fails
    doc-lint Check G. *)

let base_url = "https://march-lang.org/docs/errors/"

let find code = List.assoc_opt (Code.slug_of code) Explain_pages.pages

let has_page code = find code <> None

(** The site URL of [code]'s page, if it has one. *)
let url_of_code code =
  if has_page code then Some (base_url ^ Code.slug_of code ^ "/") else None

(** The text [march --explain code] prints. *)
let explain code =
  match find code with
  | Some page -> page
  | None -> Printf.sprintf "no page yet for %s\n" (Code.slug_of code)
