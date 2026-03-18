#include "tree_sitter/parser.h"
#include <string.h>

enum TokenType { BLOCK_COMMENT };

void *tree_sitter_march_external_scanner_create()   { return NULL; }
void  tree_sitter_march_external_scanner_destroy(void *p) {}
void  tree_sitter_march_external_scanner_reset(void *p) {}
unsigned tree_sitter_march_external_scanner_serialize(void *p, char *buf) { return 0; }
void tree_sitter_march_external_scanner_deserialize(void *p, const char *b, unsigned n) {}

bool tree_sitter_march_external_scanner_scan(
    void *payload, TSLexer *lexer, const bool *valid_symbols
) {
  if (!valid_symbols[BLOCK_COMMENT]) return false;

  /* Skip leading whitespace so we can be called before the internal lexer */
  while (lexer->lookahead == ' ' || lexer->lookahead == '\t' ||
         lexer->lookahead == '\n' || lexer->lookahead == '\r') {
    lexer->advance(lexer, true);
  }

  /* Must start with {- */
  if (lexer->lookahead != '{') return false;
  lexer->advance(lexer, false);
  if (lexer->lookahead != '-') return false;
  lexer->advance(lexer, false);

  int depth = 1;
  while (depth > 0) {
    if (lexer->lookahead == 0) return false; /* EOF inside comment */
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
