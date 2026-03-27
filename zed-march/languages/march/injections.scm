; Inject HTML highlighting into ~H sigil content
((sigil_expression
  prefix: (sigil_prefix) @_prefix
  content: (string) @content)
 (#eq? @_prefix "~H")
 (#set! language "html"))

((sigil_expression
  prefix: (sigil_prefix) @_prefix
  content: (triple_string) @content)
 (#eq? @_prefix "~H")
 (#set! language "html"))
