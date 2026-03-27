; Inject HTML highlighting into ~H sigil content
((sigil_expression
  prefix: (sigil_prefix) @language
  content: (string) @content)
 (#eq? @language "~H")
 (#set! language "html"))

((sigil_expression
  prefix: (sigil_prefix) @language
  content: (triple_string) @content)
 (#eq? @language "~H")
 (#set! language "html"))
