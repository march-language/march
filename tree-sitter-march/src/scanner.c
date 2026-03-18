#include "tree_sitter/parser.h"
#include <string.h>

enum TokenType { BLOCK_COMMENT };

void *tree_sitter_march_external_scanner_create() { return NULL; }
void tree_sitter_march_external_scanner_destroy(void *p) {}
void tree_sitter_march_external_scanner_reset(void *p) {}
unsigned tree_sitter_march_external_scanner_serialize(void *p, char *buf) { return 0; }
void tree_sitter_march_external_scanner_deserialize(void *p, const char *b, unsigned n) {}

bool tree_sitter_march_external_scanner_scan(void *payload, TSLexer *lexer,
                                              const bool *valid_symbols) {
  return false;
}
