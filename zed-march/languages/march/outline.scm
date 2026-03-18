(function_def
  "fn" @context
  name: (identifier) @name) @item

(type_def
  "type" @context
  name: (type_identifier) @name) @item

(module_def
  "mod" @context
  name: (type_identifier) @name) @item

(actor_def
  "actor" @context
  name: (type_identifier) @name) @item

(interface_def
  "interface" @context
  name: (type_identifier) @name) @item

(impl_def
  "impl" @context
  interface: (type_identifier) @name) @item

(protocol_def
  "protocol" @context
  name: (type_identifier) @name) @item

(let_declaration
  "let" @context
  pattern: (variable_pattern
    (variable_pattern) @name)) @item
