module.exports = grammar({
  name: 'march',

  externals: $ => [
    $.block_comment,
    // A `(` that starts a line after a complete expression: a new statement
    // or match arm, never a call (the compiler's LPAREN_STMT, which its token
    // filter produces; see src/scanner.c).
    $._stmt_lparen,
    // Never used by a rule: valid only during error recovery, when the
    // scanner must not produce _stmt_lparen.
    $._error_sentinel,
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
    // A match arm's body runs until the next arm's pattern; the token that
    // starts that pattern can also continue the body (the compiler decides
    // with its token filter's newline lookahead), so both parses are kept
    // and the one that fails at the next `->` is dropped.
    [$.block_body],
    // `choose` branches: a branch's steps run until the next branch label.
    [$.choose_branch],
    // Lambda bodies: a call argument's lambda may hold statements (bounded
    // by `,`/`)`), any other lambda is `let`s then one expression; which one
    // applies is only known once the enclosing context closes.
    [$.lambda_expression, $.call_arg_lambda],
    [$.lambda_body, $.block_body],
    [$.lambda_body],
    [$._block_expr, $.lambda_body],
    // `init (` : a parameter list, or a parenthesised init expression.
    [$.actor_init, $.unit_expression],
    [$.actor_init, $.parenthesized_expression],
    [$.actor_init, $.tuple_expression],
    [$.actor_init, $._lparen],
  ],

  reserved: {
    keyword: $ => [
      'fn', 'let', 'do', 'end', 'type', 'mod', 'pub',
      'pfn', 'ptype', 'import', 'alias', 'needs',
      'true', 'false',
      'when', 'linear', 'affine',
      'match',
      'if', 'else',
      'spawn',
      'actor', 'interface', 'impl', 'sig', 'extern', 'protocol', 'use',
      'for', 'loop', 'doc',
      'assert',
    ],
  },

  rules: {
    // One module per file in the compiler; nested modules and bare
    // declarations (fixtures, REPL snippets) come through _declaration.
    source_file: $ => repeat1($._declaration),

    module_def: $ => seq(
      'mod', field('name', $.module_path),
      'do', repeat($._declaration), 'end',
    ),

    _declaration: $ => choice(
      $.attribute,
      $.module_def,
      $.derive_declaration,
      $.satisfy_declaration,
      $.resource_declaration,
      $.transitions_def,
      $.app_def,
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

    // @[name], @[name(arg)], @name(arg), @invariant(expr)
    attribute: $ => seq('@', choice(
      seq('[', $.identifier, optional(seq('(', commaSep($._expr), ')')), ']'),
      seq($.identifier, '(', commaSep($._expr), ')'),
    )),

    derive_declaration: $ => seq(
      'derive', commaSep1($.type_identifier), 'for', field('type', $.type_identifier),
    ),
    satisfy_declaration: $ => seq(
      'satisfy', commaSep1($.type_identifier), 'for', commaSep1($.type_identifier),
    ),
    resource_declaration: $ => seq('resource', field('name', $.type_identifier)),
    transitions_def: $ => seq(
      'transitions', field('handle', $.type_identifier), 'do',
      repeat($.transition_arm),
      'end',
    ),
    transition_arm: $ => seq(
      field('resource', $.type_identifier), ':',
      field('from', $.type_identifier), '->', field('to', $.type_identifier),
      'via', field('function', $.identifier),
    ),
    app_def: $ => seq(
      'app', field('name', $.type_identifier), 'do',
      optional($.on_start_block),
      optional($.on_stop_block),
      $.block_body,
      'end',
    ),
    on_start_block: $ => seq('on_start', 'do', $.block_body, 'end'),
    on_stop_block: $ => seq('on_stop', 'do', $.block_body, 'end'),

    doc_annotation: $ => seq(
      'doc',
      field('content', choice($.triple_string, $.string)),
      repeat($.attribute),
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
      field('name', choice($.identifier, alias('send', $.identifier))),
      optional(seq('[', commaSep1(seq($.identifier, ':', $._type)), ']')),
      '(', optional(commaSep($.fn_param)), ')',
      optional(seq(':', field('return_type', $._type))),
      optional($.when_guard),
      'do', field('body', $.block_body), 'end',
    ),

    fn_param: $ => choice(
      $.named_param,
      $._pattern,
    ),

    named_param: $ => choice(
      seq(
        optional(choice('linear', 'affine')),
        field('name', $.identifier),
        ':', field('type', $._type),
        optional(seq('\\\\', field('default', $._expr))),
      ),
      seq(field('name', $.identifier), '\\\\', field('default', $._expr)),
    ),

    when_guard: $ => seq('when', $._expr),

    block_body: $ => seq(
      $._block_expr,
      repeat($._block_expr),
    ),

    _block_expr: $ => choice(
      $.let_declaration,
      $.local_function,
      $._expr,
    ),

    local_function: $ => seq(
      'fn', field('name', $.identifier),
      '(', optional(commaSep($.fn_param)), ')',
      optional(seq(':', field('return_type', $._type))),
      'do', field('body', $.block_body), 'end',
    ),

    let_declaration: $ => seq(
      optional(choice('linear', 'affine')),
      'let', optional(choice('?', '*')), field('pattern', $._pattern), optional($.type_annotation), '=', field('value', $._expr),
    ),

    // Full pattern rules
    _pattern: $ => choice(
      $.as_pattern,
      $.or_pattern,
      $._pattern_alt,
    ),

    as_pattern: $ => seq(
      field('pattern', choice($.or_pattern, $._pattern_alt)),
      'as', field('name', $.identifier),
    ),

    or_pattern: $ => prec.left(seq(
      $._pattern_alt, repeat1(seq('|', $._pattern_alt)),
    )),

    _pattern_alt: $ => choice(
      $.wildcard_pattern,
      $.variable_pattern,
      $.constructor_pattern,
      $.atom_pattern,
      $.tuple_pattern,
      $.paren_pattern,
      $.list_pattern,
      $.record_pattern,
      $.literal_pattern,
    ),

    paren_pattern: $ => seq($._lparen, $._pattern, ')'),

    list_pattern: $ => seq('[', optional(commaSep1($._pattern)), ']'),

    record_pattern: $ => seq('{', commaSep1($.record_field_pattern), '}'),
    record_field_pattern: $ => seq(
      field('name', $.identifier),
      optional(seq(':', field('pattern', $._pattern))),
    ),

    wildcard_pattern: _ => '_',

    qualified_constructor: $ => seq($.type_identifier, '.', $.type_identifier),

    // alias() — not a new regex — to avoid duplicate-terminal conflict with identifier
    variable_pattern: $ => alias($.identifier, $.variable_pattern),

    constructor_pattern: $ => seq(
      field('name', choice($.type_identifier, $.qualified_constructor)),
      optional(seq('(', commaSep1($._pattern), ')')),
    ),

    atom_pattern: $ => seq(
      $.atom_literal,
      optional(seq('(', commaSep1($._pattern), ')')),
    ),

    tuple_pattern: $ => seq(
      $._lparen, $._pattern, ',', commaSep1($._pattern), ')',
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
      $.unit_type,
      $.parenthesized_type,
      $.record_type,
      $.type_nat,
      $.type_application,
      $.qualified_type,
      $.type_constructor,
      $.type_variable,
      $.linear_type,
      $.tuple_type,
      $.refinement_type,
      $.abstract_refinement_type,
    ),

    // `a[p]`, `Bool[p]`: an abstract refinement applied to a type
    // (parser.mly `ty_post`).
    abstract_refinement_type: $ => prec(2, seq(
      field('base', choice($.type_variable, $.type_constructor, $.type_application, $.qualified_type)),
      '[', field('predicate', $.identifier), ']',
    )),

    // { Int | _ > 0 }, { List(a) | len(_) > 0 }, { v : Int | v != 0 }
    refinement_type: $ => seq(
      '{',
      optional(seq(field('binder', $.identifier), ':')),
      field('base', $._type),
      '|',
      field('predicate', $._expr),
      '}',
    ),

    unit_type: _ => seq('(', ')'),
    parenthesized_type: $ => seq('(', $._type, ')'),
    record_type: $ => seq('{', commaSep1($.record_type_field), '}'),
    type_nat: $ => $.integer,

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

    type_def: $ => choice(
      seq('tag', field('name', $.type_identifier)),
      $._type_def,
    ),
    _type_def: $ => seq(
      optional('always_linear'),
      choice(seq(optional('opaque'), 'type'), 'ptype'),
      field('name', $.type_identifier),
      optional($.type_params),
      '=',
      choice(
        seq($.variant, repeat(seq('|', $.variant))),  // variant/sum type
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
      optional($.mailbox_clause),
      optional($.supervise_block),
      repeat(choice($.actor_handler, $.on_stop_block)),
      'end',
    ),
    actor_state: $ => seq('state', '{', commaSep($.record_type_field), '}'),
    actor_init: $ => choice(
      seq('init', '(', commaSep($.init_param), ')', $._expr),
      seq('init', $._expr),
    ),
    init_param: $ => seq(field('name', $.identifier), ':', field('type', $._type)),
    mailbox_clause: $ => seq('mailbox', $.integer, $.identifier),
    supervise_block: $ => seq(
      'supervise', 'do',
      'strategy', field('strategy', $.identifier),
      'max_restarts', $.integer, 'within', $.integer,
      optional(seq('backoff', repeat1(seq($.identifier, $.integer, optional('%'))))),
      repeat($.supervise_child),
      'end',
    ),
    supervise_child: $ => prec.right(seq(
      field('actor', $.type_identifier), field('name', $.identifier),
      optional(seq('(', commaSep($._expr), ')')),
      repeat(choice(
        seq('restart', $.identifier),
        seq('shutdown', choice($.integer, $.identifier)),
      )),
    )),
    actor_handler: $ => seq(
      'on', field('name', $.type_identifier),
      '(', optional(commaSep($.fn_param)), ')',
      'do', $.block_body, 'end',
    ),

    interface_def: $ => seq(
      'interface',
      field('name', $.type_identifier),
      '(', field('param', $.type_variable), ')',
      optional(seq(choice(':', 'requires'), commaSep1($.superclass_constraint))),
      'do',
      repeat(choice($.method_sig, $.function_def)),
      'end',
    ),
    superclass_constraint: $ => seq(
      $.module_path,
      '(', commaSep1($._type), ')',
    ),
    method_sig: $ => seq(
      'fn', field('name', $.identifier), ':', field('type', $._type),
      optional(seq('do', field('default', $._expr), 'end')),
    ),

    impl_def: $ => seq(
      'impl',
      field('interface', $.module_path),
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
      repeat(field('modifier', $.identifier)),
      'fn', field('name', $.identifier),
      '(', optional(commaSep($.ffi_param)), ')',
      ':', field('return_type', $._type),
      optional(seq('=', field('symbol', $.string))),
    ),
    ffi_param: $ => seq(
      optional(field('modifier', $.identifier)),
      field('name', $.identifier), ':', field('type', $._type),
    ),

    protocol_def: $ => seq(
      'protocol', field('name', $.type_identifier), 'do',
      repeat($.protocol_step),
      'end',
    ),
    protocol_step: $ => choice(
      $.protocol_message,
      $.protocol_loop,
      $.protocol_choose,
      $.protocol_role,
      $.protocol_may,
      $.protocol_stop,
    ),
    protocol_message: $ => prec.right(seq(
      optional(seq(field('label', $.identifier), ':')),
      field('sender', $.type_identifier), '->',
      field('receiver', $.type_identifier), ':',
      field('type', $._type),
      optional(seq('or', $.identifier, 'do', repeat($.protocol_step), 'end')),
    )),
    protocol_loop: $ => seq('loop', optional($.identifier), 'do', repeat($.protocol_step), 'end'),
    protocol_choose: $ => seq(
      'choose', 'by', field('chooser', $.type_identifier), ':',
      optional('|'), $.choose_branch, repeat(seq(optional('|'), $.choose_branch)),
      'end',
    ),
    choose_branch: $ => seq(field('label', $.identifier), '->', repeat($.protocol_step)),
    protocol_role: $ => seq('role', $.type_identifier, 'needs', commaSep1($.module_path)),
    protocol_may: $ => seq('may', $.identifier, commaSep1($.type_identifier)),
    protocol_stop: $ => $.identifier,

    // use A, use A.B, use A.b, use A.*, use A.{f, g}
    use_declaration: $ => seq(
      'use', $.type_identifier,
      repeat(seq('.', $.type_identifier)),
      optional(seq('.', choice(
        seq('{', commaSep($.identifier), '}'),
        '*',
        $.identifier,
      ))),
    ),

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
    needs_declaration: $ => seq('needs', commaSep1($.scoped_capability)),
    scoped_capability: $ => seq($.module_path, optional(seq('(', $.string, ')'))),

    // `cap no_panic` and friends lex as a single keyword in the compiler, so
    // the space between the two words is not free-form whitespace here either.
    capability_declaration: $ => choice(
      seq('proof', 'cap', field('name', $.type_identifier),
          optional(seq('with', field('dictionary', $.type_identifier)))),
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
      $.cond_expression,
      $.block_expression,
      $.record_expression,
      $.record_update,
      $.tuple_expression,
      $.parenthesized_expression,
      $.unit_expression,
      $.list_expression,
      $.list_comprehension,
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
      field('operator', choice('+', '-', '++', '+.', '-.')),
      field('right', $._expr),
    )),
    multiplicative_expression: $ => prec.left(6, seq(
      field('left', $._expr),
      field('operator', choice('*', '/', '%', '*.', '/.')),
      field('right', $._expr),
    )),
    unary_expression: $ => prec.right(7, seq(
      field('operator', choice('-', '!')),
      field('operand', $._expr),
    )),

    call_expression: $ => prec(8, seq(
      field('function', $._expr),
      '(', optional(commaSep($._call_arg)), ')',
    )),
    constructor_expression: $ => prec(8, seq(
      field('name', $.type_identifier),
      '(', optional(commaSep($._call_arg)), ')',
    )),
    // Bare constructor (nullary) used as expression, e.g. Nil, None, True
    bare_constructor: $ => field('name', $.type_identifier),
    field_expression: $ => prec.left(9, seq(
      // The field may be a type_identifier so that a qualified path such as
      // `Mgrep.Search.Matcher.contains_case` parses as nested field accesses.
      field('object', $._expr), '.',
      field('field', choice($.identifier, $.type_identifier)),
    )),

    // `fn params -> body`.  In general the body is `let`s then one
    // expression (the compiler's lambda_body); as a call argument it may be
    // any statement sequence, since `,` or `)` bounds it (call_arg).
    lambda_expression: $ => seq(
      'fn', optional($._lambda_params), '->',
      field('body', alias($.lambda_body, $.block_body)),
    ),
    _lambda_params: $ => choice(
      field('param', choice($.identifier, '_')),
      seq('(', optional(commaSep($.fn_param)), ')'),
    ),
    lambda_body: $ => seq(repeat($.let_declaration), $._expr),
    _call_arg: $ => choice(
      $._expr,
      alias($.call_arg_lambda, $.lambda_expression),
    ),
    call_arg_lambda: $ => seq(
      'fn', optional($._lambda_params), '->',
      field('body', $.block_body),
    ),
    if_expression: $ => seq(
      'if', field('condition', $._expr),
      'do', field('then', $.block_body),
      'else', field('else', $.block_body),
      'end',
    ),
    block_expression: $ => seq('do', $.block_body, 'end'),
    _lparen: $ => choice('(', $._stmt_lparen),
    unit_expression: $ => seq($._lparen, ')'),
    parenthesized_expression: $ => seq($._lparen, $._expr, ')'),
    tuple_expression: $ => seq(
      $._lparen, $._expr, ',', commaSep1($._expr), ')',
    ),
    list_expression: $ => seq('[', optional(commaSep($._expr)), ']'),
    // [body for pat in source] / [body for pat in source, guard]
    list_comprehension: $ => seq(
      '[', field('body', $._expr),
      'for', field('pattern', $._pattern), 'in', field('source', $._expr),
      optional(seq(',', field('guard', $._expr))),
      ']',
    ),
    record_expression: $ => seq(
      '{', commaSep1($.record_field), '}',
    ),
    record_update: $ => seq(
      '{', field('base', $._expr), 'with', commaSep1($.record_field), '}',
    ),
    record_field: $ => seq(field('name', $.identifier), ':', field('value', $._expr)),

    send_expression: $ => seq('send', '(', $._expr, ',', $._expr, ')'),
    spawn_expression: $ => seq('spawn', '(', commaSep1($._expr), ')'),
    assert_expression: $ => seq('assert', field('value', $._expr)),

    // Sigil expressions: ~H"...", ~H"""...""", ~yaml"...".  The content is one
    // string token; nothing tokenizes the HTML or interpolations inside it.
    sigil_expression: $ => seq(
      field('prefix', $.sigil_prefix),
      field('content', choice($.triple_string, $.string)),
    ),
    sigil_prefix: _ => token(seq('~', /[A-Za-z][A-Za-z0-9_]*/)),


    match_expression: $ => seq(
      'match', field('value', $._expr), 'do',
      optional('|'),
      $.match_arm,
      repeat(seq(optional('|'), $.match_arm)),
      'end',
    ),

    // Cond form: `match do c1 -> e1 | _ -> e2 end`, no scrutinee; each arm's
    // left side is a boolean expression (or `_`).
    cond_expression: $ => seq(
      'match', 'do',
      optional('|'),
      $.cond_arm,
      repeat(seq(optional('|'), $.cond_arm)),
      'end',
    ),
    cond_arm: $ => seq(
      field('condition', $._expr),
      '->',
      field('body', $.block_body),
    ),

    match_arm: $ => seq(
      field('pattern', $._pattern),
      optional($.when_guard),
      '->',
      field('body', $.block_body),
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
        seq('\\', /[^x]|x[0-9a-fA-F]{2}/),
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

