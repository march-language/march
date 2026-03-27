; Inject HTML highlighting into ~H sigil content
((sigil_expression
  prefix: (sigil_prefix) @_prefix
  content: (_) @injection.content)
 (#eq? @_prefix "~H")
 (#set! injection.language "html")
 (#set! injection.combined)
 (#set! injection.include-children))

; Inject JSON highlighting into ~J sigil content
((sigil_expression
  prefix: (sigil_prefix) @_prefix
  content: (_) @injection.content)
 (#eq? @_prefix "~J")
 (#set! injection.language "json")
 (#set! injection.combined))
