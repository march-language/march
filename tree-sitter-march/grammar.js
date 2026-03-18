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
  ],

  reserved: {
    keyword: $ => [
      'fn', 'let', 'do', 'end', 'type', 'mod', 'pub',
      'true', 'false',
      'when', 'linear', 'affine',
      'match', 'with',
    ],
  },

  rules: {
    source_file: $ => choice(
      $.module_def,
      repeat1($._declaration),
    ),

    module_def: $ => seq(
      'mod', field('name', $.type_identifier),
      'do', repeat($._declaration), 'end',
    ),

    _declaration: $ => choice(
      $.function_def,
      $.let_declaration,
      $.type_def,
    ),

    function_def: $ => seq(
      optional('pub'), 'fn',
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
      $.type_constructor,
      $.type_variable,
      $.linear_type,
      $.tuple_type,
    ),

    type_application: $ => seq(
      field('name', $.type_identifier),
      '(', commaSep1($._type), ')',
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

    type_def: $ => seq('type', $.type_identifier, '=', $.type_identifier),

    // Full expression rules (stub with literals + match for Task 5)
    _expr: $ => choice(
      $.match_expression,
      $.integer,
      $.float,
      $.string,
      $.boolean,
      $.atom,
      $.typed_hole,
      $.identifier,
    ),

    match_expression: $ => seq(
      'match', field('value', $._expr), 'with',
      optional('|'), pipeSep1($.match_arm),
      'end',
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

    string: _ => seq(
      '"',
      repeat(choice(
        /[^"\\]+/,
        seq('\\', choice('n', 't', '\\', '"')),
      )),
      '"',
    ),

    atom_literal: _ => seq(':', /[a-z][a-zA-Z0-9_']*/),

    typed_hole: $ => seq('?', optional($.identifier)),

    // Atom expression: :ok or :error(msg)
    atom: $ => seq(
      $.atom_literal,
      optional(seq('(', commaSep($._expr), ')')),
    ),

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
function pipeSep1(rule) {
  // Pipe-separated list: used for match arms (optional leading | handled at call site)
  return seq(rule, repeat(seq('|', rule)));
}
