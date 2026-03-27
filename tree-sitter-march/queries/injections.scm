; Inject HTML highlighting into ~H sigil content
((sigil_expression
  prefix: (sigil_prefix) @_prefix
  content: (string) @injection.content)
 (#eq? @_prefix "~H")
 (#set! injection.language "html"))

((sigil_expression
  prefix: (sigil_prefix) @_prefix
  content: (triple_string) @injection.content)
 (#eq? @_prefix "~H")
 (#set! injection.language "html"))
