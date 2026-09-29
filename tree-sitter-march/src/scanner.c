#include "tree_sitter/parser.h"
#include <stdbool.h>

enum TokenType {
  BLOCK_COMMENT,
  STMT_LPAREN,
  ERROR_SENTINEL,
};

void *tree_sitter_march_external_scanner_create()   { return NULL; }
void  tree_sitter_march_external_scanner_destroy(void *p) {}
void  tree_sitter_march_external_scanner_reset(void *p) {}
unsigned tree_sitter_march_external_scanner_serialize(void *p, char *buf) { return 0; }
void tree_sitter_march_external_scanner_deserialize(void *p, const char *b, unsigned n) {}

/* Skip whitespace; report whether a newline was crossed. */
static bool skip_ws(TSLexer *lexer) {
  bool saw_newline = false;
  while (lexer->lookahead == ' ' || lexer->lookahead == '\t' ||
         lexer->lookahead == '\n' || lexer->lookahead == '\r') {
    if (lexer->lookahead == '\n') saw_newline = true;
    lexer->advance(lexer, true);
  }
  return saw_newline;
}

bool tree_sitter_march_external_scanner_scan(
    void *payload, TSLexer *lexer, const bool *valid_symbols
) {
  /* During error recovery every symbol is valid, ERROR_SENTINEL included.
     Producing STMT_LPAREN there would let recovery split a call anywhere. */
  bool recovering = valid_symbols[ERROR_SENTINEL];
  if (!valid_symbols[BLOCK_COMMENT] &&
      !(valid_symbols[STMT_LPAREN] && !recovering)) return false;
  bool saw_newline = skip_ws(lexer);

  /* The compiler's token filter retags a line-initial `(` as LPAREN_STMT:
     after a complete expression it starts a new statement or match arm (a
     tuple, a parenthesised expression, a pattern), never a call.  Only
     offered where the grammar can start one of those, so a `(` that can
     only be a call argument list stays a plain '('. */
  if (lexer->lookahead == '(') {
    if (saw_newline && valid_symbols[STMT_LPAREN] && !recovering) {
      lexer->advance(lexer, false);
      lexer->result_symbol = STMT_LPAREN;
      return true;
    }
    return false;
  }

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
