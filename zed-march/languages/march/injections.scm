; Inject HTML highlighting into ~H sigil content
((sigil_expression
  prefix: (sigil_prefix) @_prefix
  content: (_) @injection.content)
 (#eq? @_prefix "~H")
 (#set! injection.language "html")
 (#set! injection.combined))
