#include "tree_sitter/parser.h"
#include <string.h>

enum TokenType { BLOCK_COMMENT, SIGIL_PREFIX };

void *tree_sitter_march_external_scanner_create()   { return NULL; }
void  tree_sitter_march_external_scanner_destroy(void *p) {}
void  tree_sitter_march_external_scanner_reset(void *p) {}
unsigned tree_sitter_march_external_scanner_serialize(void *p, char *buf) { return 0; }
void tree_sitter_march_external_scanner_deserialize(void *p, const char *b, unsigned n) {}

bool tree_sitter_march_external_scanner_scan(
    void *payload, TSLexer *lexer, const bool *valid_symbols
) {
  /* Skip leading whitespace */
  while (lexer->lookahead == ' ' || lexer->lookahead == '\t' ||
         lexer->lookahead == '\n' || lexer->lookahead == '\r') {
    lexer->advance(lexer, true);
  }

  /* Sigil prefix: ~H, ~R, ~J, etc. (tilde followed by uppercase letter)
     Check this first - tilde is unambiguous. */
  if (valid_symbols[SIGIL_PREFIX] && lexer->lookahead == '~') {
    lexer->advance(lexer, false);
    if (lexer->lookahead >= 'A' && lexer->lookahead <= 'Z') {
      lexer->advance(lexer, false);
      lexer->result_symbol = SIGIL_PREFIX;
      return true;
    }
    return false;
  }

  /* Block comments: {- ... -} (nestable)
     In extras, so valid_symbols[BLOCK_COMMENT] is true in most states. */
  if (!valid_symbols[BLOCK_COMMENT]) return false;
  if (lexer->lookahead != '{') return false;
  lexer->advance(lexer, false);
  if (lexer->lookahead != '-') return false;
  lexer->advance(lexer, false);

  int depth = 1;
  while (depth > 0) {
    if (lexer->lookahead == 0) return false;
    if (lexer->lookahead == '{') {
      lexer->advance(lexer, false);
      if (lexer->lookahead == '-') { lexer->advance(lexer, false); depth++; }
    } else if (lexer->lookahead == '-') {
      lexer->advance(lexer, false);
      if (lexer->lookahead == '}') { lexer->advance(lexer, false); depth--; }
    } else {
      lexer->advance(lexer, false);
    }
  }
  lexer->result_symbol = BLOCK_COMMENT;
  return true;
}
