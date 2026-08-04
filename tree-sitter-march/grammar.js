module.exports = grammar({
  name: 'march',

  externals: $ => [
    $.block_comment,
  ],

  extras: $ => [
    /\s/,
    $.comment,
    $.block_comment,
  ],

  word: $ => $.identifier,

  conflicts: $ => [
    [$.typed_hole],
    // atom optional args
    [$.atom],
    // type_def: type_identifier can be variant name or type_constructor alias
    [$.type_constructor, $.variant],
    // type_def: type_application vs variant(args)
    [$.type_application, $.variant],
    // bare_constructor vs constructor_expression (resolved by lookahead on '(')
    [$.bare_constructor, $.constructor_expression],
    // `import A.B` vs `import A.{c, d}` — the choice needs the token after '.'
    [$.module_path],
  ],

  reserved: {
    keyword: $ => [
      'fn', 'let', 'do', 'end', 'type', 'mod', 'pub',
      'pfn', 'ptype', 'import', 'alias', 'needs',
      'true', 'false',
      'when', 'linear', 'affine',
      'match',
      'if', 'else',
      'send', 'spawn',
      'actor', 'interface', 'impl', 'sig', 'extern', 'protocol', 'use',
      'for', 'loop', 'doc',
      'test', 'describe', 'assert', 'setup', 'setup_all',
    ],
  },

  rules: {
    source_file: $ => choice(
      $.module_def,
      repeat1($._declaration),
    ),

    module_def: $ => seq(
      'mod', field('name', $.module_path),
      'do', repeat($._declaration), 'end',
    ),

    _declaration: $ => choice(
      $.doc_annotation,
      $.function_def,
      $.let_declaration,
      $.type_def,
      $.actor_def,
      $.interface_def,
      $.impl_def,
      $.sig_def,
      $.extern_def,
      $.protocol_def,
      $.use_declaration,
      $.import_declaration,
      $.alias_declaration,
      $.needs_declaration,
      $.capability_declaration,
      $.test_decl,
      $.describe_decl,
      $.setup_decl,
      $.setup_all_decl,
    ),

    doc_annotation: $ => seq(
      'doc',
      field('content', choice($.triple_string, $.string)),
      field('decl', choice(
        $.function_def,
        $.let_declaration,
        $.type_def,
        $.actor_def,
        $.interface_def,
        $.impl_def,
        $.sig_def,
        $.extern_def,
        $.protocol_def,
        $.use_declaration,
      )),
    ),

    function_def: $ => seq(
      // `pfn` is the private form; it never combines with `pub`.
      choice(seq(optional('pub'), 'fn'), 'pfn'),
      field('name', $.identifier),
      '(', optional(commaSep($.fn_param)), ')',
      optional(seq(':', field('return_type', $._type))),
      optional($.when_guard),
      'do', field('body', $.block_body), 'end',
    ),

    fn_param: $ => choice(
      $.named_param,
      $._pattern,
    ),

    named_param: $ => seq(
      optional(choice('linear', 'affine')),
      field('name', $.identifier),
      ':', field('type', $._type),
    ),

    when_guard: $ => seq('when', $._expr),

    block_body: $ => seq(
      $._block_expr,
      repeat($._block_expr),
    ),

    _block_expr: $ => choice(
      $.let_declaration,
      $._expr,
    ),

    let_declaration: $ => seq(
      'let', field('pattern', $._pattern), optional($.type_annotation), '=', field('value', $._expr),
    ),

    // Full pattern rules
    _pattern: $ => choice(
      $.wildcard_pattern,
      $.variable_pattern,
      $.constructor_pattern,
      $.atom_pattern,
      $.tuple_pattern,
      $.literal_pattern,
    ),

    wildcard_pattern: _ => '_',

    // alias() — not a new regex — to avoid duplicate-terminal conflict with identifier
    variable_pattern: $ => alias($.identifier, $.variable_pattern),

    constructor_pattern: $ => seq(
      field('name', $.type_identifier),
      optional(seq('(', commaSep1($._pattern), ')')),
    ),

    atom_pattern: $ => seq(
      $.atom_literal,
      optional(seq('(', commaSep1($._pattern), ')')),
    ),

    tuple_pattern: $ => seq(
      '(', $._pattern, ',', commaSep1($._pattern), ')',
    ),

    literal_pattern: $ => choice(
      $.integer,
      $.float,
      $.string,
      $.boolean,
      seq('-', $.integer),
      seq('-', $.float),
    ),

    type_annotation: $ => seq(':', $._type),

    // Full type rules
    _type: $ => choice(
      $.arrow_type,
      $._type_atom,
    ),

    arrow_type: $ => prec.right(1, seq(
      field('param', $._type_atom), '->', field('return', $._type),
    )),

    _type_atom: $ => choice(
      $.type_application,
      $.qualified_type,
      $.type_constructor,
      $.type_variable,
      $.linear_type,
      $.tuple_type,
      $.refinement_type,
    ),

    // { Int | _ > 0 }, { List(a) | len(_) > 0 }, { v : Int | v != 0 }
    refinement_type: $ => seq(
      '{',
      optional(seq(field('binder', $.identifier), ':')),
      field('base', $._type),
      '|',
      field('predicate', $._expr),
      '}',
    ),

    type_application: $ => seq(
      field('name', choice($.type_identifier, $.qualified_type)),
      '(', commaSep1($._type), ')',
    ),

    // A type named through its module: `Mgrep.Search.MatcherMode.Mode`.
    qualified_type: $ => seq(
      $.type_identifier, repeat1(seq('.', $.type_identifier)),
    ),

    // alias() — NOT new regex — to avoid duplicate-terminal conflicts
    type_constructor: $ => alias($.type_identifier, $.type_constructor),
    type_variable: $ => alias($.identifier, $.type_variable),

    linear_type: $ => seq(
      choice('linear', 'affine'),
      field('type', $._type_atom),
    ),

    tuple_type: $ => seq(
      '(', $._type, ',', commaSep1($._type), ')',
    ),

    type_def: $ => seq(
      choice('type', 'ptype'),
      field('name', $.type_identifier),
      optional($.type_params),
      '=',
      choice(
        seq($.variant, repeat(seq('|', $.variant))),  // variant/sum type
        seq('{', commaSep1($.record_type_field), '}'), // record type
        $._type,                                        // alias
      ),
    ),

    type_params: $ => seq('(', commaSep1($.type_variable), ')'),

    variant: $ => seq(
      field('name', choice($.type_identifier, $.atom_literal)),
      optional(seq('(', commaSep1($._type), ')')),
    ),

    record_type_field: $ => seq(
      optional(choice('linear', 'affine')),
      field('name', $.identifier), ':', field('type', $._type),
    ),

    // Full actor, interface, impl, sig, extern, protocol implementations
    actor_def: $ => seq(
      'actor', field('name', $.type_identifier), 'do',
      $.actor_state,
      $.actor_init,
      repeat($.actor_handler),
      'end',
    ),
    actor_state: $ => seq('state', '{', commaSep($.record_type_field), '}'),
    actor_init: $ => seq('init', $._expr),
    actor_handler: $ => seq(
      'on', field('name', $.type_identifier),
      '(', optional(commaSep($.fn_param)), ')',
      'do', $.block_body, 'end',
    ),

    interface_def: $ => seq(
      'interface',
      field('name', $.type_identifier),
      '(', field('param', $.type_variable), ')',
      optional(seq(':', commaSep1($.superclass_constraint))),
      'do',
      repeat(choice($.method_sig, $.function_def)),
      'end',
    ),
    superclass_constraint: $ => seq(
      $.type_identifier,
      '(', commaSep1($._type), ')',
    ),
    method_sig: $ => seq('fn', field('name', $.identifier), ':', field('type', $._type)),

    impl_def: $ => seq(
      'impl',
      field('interface', $.type_identifier),
      '(',
      field('type', $._type),
      ')',
      optional(seq('for', field('for_type', $._type))),
      optional(seq('when', commaSep1($.superclass_constraint))),
      'do',
      repeat($.function_def),
      'end',
    ),

    sig_def: $ => seq(
      'sig', field('name', $.type_identifier), 'do',
      repeat(choice($.method_sig, $.sig_type_decl)),
      'end',
    ),
    sig_type_decl: $ => seq('type', $.type_identifier, optional($.type_params)),

    extern_def: $ => seq(
      'extern', $.string, ':', field('cap_type', $._type), 'do',
      repeat($.extern_fn),
      'end',
    ),
    extern_fn: $ => seq(
      'fn', field('name', $.identifier),
      '(', optional(commaSep($.fn_param)), ')',
      ':', field('return_type', $._type),
    ),

    protocol_def: $ => seq(
      'protocol', field('name', $.type_identifier), 'do',
      repeat($.protocol_step),
      'end',
    ),
    protocol_step: $ => choice(
      $.protocol_message,
      $.protocol_loop,
    ),
    protocol_message: $ => seq(
      field('sender', $.type_identifier), '->',
      field('receiver', $.type_identifier), ':',
      $.type_identifier,
      optional(seq('(', commaSep1($._type), ')')),
    ),
    protocol_loop: $ => seq('loop', 'do', repeat($.protocol_step), 'end'),

    use_declaration: $ => seq('use', $.type_identifier, '.', choice(
      seq('{', commaSep1($.identifier), '}'),
      '*',
    )),

    // Elixir-style: import A, import A.B, import A.B.{C, d},
    // import A, only: [f, g], import A, except: [f, g]
    import_declaration: $ => seq(
      'import',
      field('path', $.module_path),
      optional(choice(
        seq('.', '{', commaSep1(choice($.identifier, $.type_identifier)), '}'),
        seq(',', choice('only', 'except'), ':',
            '[', commaSep($.identifier), ']'),
      )),
    ),

    // alias Long.Name  |  alias Long.Name as Short  |  alias Long.Name, as: Short
    alias_declaration: $ => seq(
      'alias',
      field('path', $.module_path),
      optional(choice(
        seq('as', field('name', $.type_identifier)),
        seq(',', 'as', ':', field('name', $.type_identifier)),
      )),
    ),

    // needs IO.Network, IO.Clock
    needs_declaration: $ => seq('needs', commaSep1($.module_path)),

    // `cap no_panic` and friends lex as a single keyword in the compiler, so
    // the space between the two words is not free-form whitespace here either.
    capability_declaration: $ => choice(
      seq('proof', 'cap', field('name', $.type_identifier)),
      seq('cap', field('name', choice(
        'no_panic', 'pure', 'no_extern', 'deterministic', 'no_alloc', 'verified',
      ))),
    ),

    module_path: $ => seq($.type_identifier, repeat(seq('.', $.type_identifier))),

    // Test declarations
    test_decl: $ => seq(
      'test', field('name', $.string),
      'do', field('body', $.block_body), 'end',
    ),

    describe_decl: $ => seq(
      'describe', field('name', $.string),
      'do', repeat($._describe_item), 'end',
    ),

    _describe_item: $ => choice(
      $.test_decl,
      $.describe_decl,
    ),

    setup_decl: $ => seq(
      'setup', 'do', field('body', $.block_body), 'end',
    ),

    setup_all_decl: $ => seq(
      'setup_all', 'do', field('body', $.block_body), 'end',
    ),

    // Full expression hierarchy
    _expr: $ => choice(
      $.assert_expression,
      $.pipe_expression,
      $.or_expression,
      $.and_expression,
      $.comparison_expression,
      $.additive_expression,
      $.multiplicative_expression,
      $.unary_expression,
      $.call_expression,
      $.constructor_expression,
      $.bare_constructor,
      $.field_expression,
      $.lambda_expression,
      $.if_expression,
      $.match_expression,
      $.block_expression,
      $.record_expression,
      $.record_update,
      $.tuple_expression,
      $.unit_expression,
      $.list_expression,
      $.send_expression,
      $.spawn_expression,
      $.sigil_expression,
      $.atom,
      $.typed_hole,
      $.refinement_placeholder,
      $.integer,
      $.float,
      $.string,
      $.boolean,
      $.identifier,
    ),

    pipe_expression: $ => prec.left(1, seq(
      field('left', $._expr), '|>', field('right', $._expr),
    )),
    or_expression: $ => prec.left(2, seq(
      field('left', $._expr), '||', field('right', $._expr),
    )),
    and_expression: $ => prec.left(3, seq(
      field('left', $._expr), '&&', field('right', $._expr),
    )),
    comparison_expression: $ => prec.left(4, seq(
      field('left', $._expr),
      field('operator', choice('==', '!=', '<', '>', '<=', '>=')),
      field('right', $._expr),
    )),
    additive_expression: $ => prec.left(5, seq(
      field('left', $._expr),
      field('operator', choice('+', '-', '++')),
      field('right', $._expr),
    )),
    multiplicative_expression: $ => prec.left(6, seq(
      field('left', $._expr),
      field('operator', choice('*', '/', '%')),
      field('right', $._expr),
    )),
    unary_expression: $ => prec.right(7, seq(
      field('operator', choice('-', '!')),
      field('operand', $._expr),
    )),

    call_expression: $ => prec(8, seq(
      field('function', $._expr),
      '(', optional(commaSep($._expr)), ')',
    )),
    constructor_expression: $ => prec(8, seq(
      field('name', $.type_identifier),
      '(', optional(commaSep($._expr)), ')',
    )),
    // Bare constructor (nullary) used as expression, e.g. Nil, None, True
    bare_constructor: $ => field('name', $.type_identifier),
    field_expression: $ => prec.left(9, seq(
      // The field may be a type_identifier so that a qualified path such as
      // `Mgrep.Search.Matcher.contains_case` parses as nested field accesses.
      field('object', $._expr), '.',
      field('field', choice($.identifier, $.type_identifier)),
    )),

    lambda_expression: $ => seq(
      'fn',
      choice(
        field('param', $.identifier),
        seq('(', optional(commaSep($.fn_param)), ')'),
      ),
      '->',
      field('body', $._expr),
    ),
    if_expression: $ => seq(
      'if', field('condition', $._expr),
      'do', field('then', $.block_body),
      'else', field('else', $.block_body),
      'end',
    ),
    block_expression: $ => seq('do', $.block_body, 'end'),
    unit_expression: _ => seq('(', ')'),
    tuple_expression: $ => seq(
      '(', $._expr, ',', commaSep1($._expr), ')',
    ),
    list_expression: $ => seq('[', optional(commaSep($._expr)), ']'),
    record_expression: $ => seq(
      '{', commaSep1($.record_field), '}',
    ),
    record_update: $ => seq(
      '{', field('base', $._expr), 'with', commaSep1($.record_field), '}',
    ),
    record_field: $ => seq(field('name', $.identifier), '=', field('value', $._expr)),

    send_expression: $ => seq('send', '(', $._expr, ',', $._expr, ')'),
    spawn_expression: $ => seq('spawn', '(', $._expr, ')'),
    assert_expression: $ => seq('assert', field('value', $._expr)),

    // Sigil expressions: ~H"...", ~H"""..."""
    // Content is tokenized by the external scanner into HTML tags,
    // interpolation expressions, and plain text for distinct highlighting.
    sigil_expression: $ => seq(
      field('prefix', $.sigil_prefix),
      field('content', choice($.triple_string, $.string)),
    ),
    sigil_prefix: _ => token(seq('~', /[A-Z]/)),


    match_expression: $ => seq(
      'match', field('value', $._expr), 'do',
      repeat1($.match_arm),
      'end',
    ),

    match_arm: $ => seq(
      field('pattern', $._pattern),
      optional($.when_guard),
      '->',
      field('body', $._expr),
    ),

    // Literals
    float: _ => /[0-9]+\.[0-9]+/,
    boolean: _ => choice('true', 'false'),

    // Wrapped in token() so the entire string is lexed as one atomic unit.
    // Without this, the tree-sitter lexer tries to match comment tokens (which
    // start with '--') inside string content.  After '--' the lexer enters a
    // comment-scanning state; when it then sees the closing '"' it advances to
    // the comment-accept state and swallows the quote, breaking the string.
    // Making the rule atomic prevents any extra-token (comment/whitespace)
    // matching from occurring mid-string.
    string: _ => token(seq(
      '"',
      repeat(choice(
        /[^"\\]+/,
        seq('\\', choice('n', 't', '\\', '"')),
      )),
      '"',
    )),

    atom_literal: _ => seq(':', /[a-z][a-zA-Z0-9_']*/),

    typed_hole: $ => seq('?', optional($.identifier)),

    // The refined value inside a refinement predicate: `{ Int | _ > 0 }`.
    // Only meaningful there; elsewhere `_` is a wildcard_pattern.
    refinement_placeholder: _ => '_',

    // Atom expression: :ok or :error(msg)
    atom: $ => seq(
      $.atom_literal,
      optional(seq('(', commaSep($._expr), ')')),
    ),

    // Triple-quoted doc string: """..."""  (content may span lines and contain " and "")
    triple_string: _ => /"""([^"]|"[^"]|""[^"])*"{0,2}"""/,

    comment: _ => token(seq('--', /.*/)),
    integer: _ => /[0-9]+/,
    identifier: _ => /[a-z_][a-zA-Z0-9_']*/,
    type_identifier: _ => /[A-Z][a-zA-Z0-9_']*/,
  },
});

// Helpers — defined outside grammar({}) so they are plain JS functions.
function commaSep(rule) {
  return optional(commaSep1(rule));
}
function commaSep1(rule) {
  return seq(rule, repeat(seq(',', rule)));
}

