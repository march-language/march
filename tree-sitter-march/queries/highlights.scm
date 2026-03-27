; Keywords — control flow
["fn" "let" "do" "end" "if" "else" "match" "when"] @keyword

; Keywords — declarations
["type" "mod" "actor" "protocol" "interface" "impl" "sig" "extern"] @keyword

; Keywords — modifiers
["pub" "linear" "affine"] @keyword

; Keywords — actor / concurrency
["send" "spawn" "loop" "for" "use"] @keyword

; Doc annotations
(doc_annotation "doc" @keyword.documentation)
(doc_annotation content: (string) @comment.documentation)
(doc_annotation content: (triple_string) @comment.documentation)

; Test constructs
["test" "describe" "assert" "setup" "setup_all"] @keyword
(test_decl name: (string) @string.special)
(describe_decl name: (string) @string.special)

; Literals
(integer) @number
(float) @number
(string) @string
(boolean) @boolean

; Atoms
(atom_literal) @label
(atom) @label

; Sigil expressions — ~H prefix as keyword, content as special string
(sigil_expression prefix: (sigil_prefix) @keyword)
(sigil_expression content: (string) @string.special)
(sigil_expression content: (triple_string) @string.special)

; Typed holes
(typed_hole) @string.special

; Comments
(comment) @comment
(block_comment) @comment

; Function definitions
(function_def name: (identifier) @function)

; Function calls
(call_expression function: (identifier) @function.call)

; Type names (in type position)
(type_constructor) @type
(type_application name: (type_identifier) @type)
(type_variable) @type.parameter

; Constructor expressions and patterns
(constructor_expression name: (type_identifier) @constructor)
(bare_constructor name: (type_identifier) @constructor)
(constructor_pattern name: (type_identifier) @constructor)

; Module names
(module_def name: (type_identifier) @namespace)

; Actor / interface / impl / sig / protocol names
(actor_def name: (type_identifier) @type)
(interface_def name: (type_identifier) @type)
(type_def name: (type_identifier) @type)
(impl_def interface: (type_identifier) @type)
(sig_def name: (type_identifier) @type)
(protocol_def name: (type_identifier) @type)

; Parameters
(named_param name: (identifier) @variable.parameter)

; Record fields
(record_field name: (identifier) @property)
(record_type_field name: (identifier) @property)

; Variable patterns (bound names in patterns)
(variable_pattern) @variable

; Variable references
(identifier) @variable

; Operators
["+" "-" "*" "/" "%" "++" "==" "!=" "<" ">" "<=" ">=" "&&" "||" "!" "|>" "->" "="] @operator

; Punctuation
["(" ")" "[" "]" "{" "}"] @punctuation.bracket
["," "." "|" ":"] @punctuation.delimiter
