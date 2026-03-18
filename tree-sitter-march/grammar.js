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
      '(', ')', 'do', 'end',
    ),

    let_declaration: $ => seq('let', $.identifier, '=', $._expr),

    type_def: $ => seq('type', $.type_identifier, '=', $.type_identifier),

    _expr: $ => $.integer,

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
