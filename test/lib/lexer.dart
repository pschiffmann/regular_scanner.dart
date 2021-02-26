/// The [TokenIterator] class from this library splits a regular expression
/// string into tokens for consumption by the `parser.dart` library. Tokens are
/// not instantiated as objects, because they are not used in the AST anyways.
/// Instead, the current token is accessible through the properties of
/// [TokenIterator].
///
/// Token types are recognized by [defaultContextScanner] and
/// [characterSetScanner], which are [Scanner]s generated by package
/// regular_scanner_builder, because [bootstrapping][1] rules.
///
/// This library defines additional [TokenType]s beyond those from `token.dart`,
/// but they are only used to recognize escape sequences. All [TokenType]
/// constants defined in this library are mapped to [literal].
///
/// [1]: https://en.wikipedia.org/wiki/Bootstrapping_(compilers)
library regular_scanner.regex.lexer;

import 'package:charcode/ascii.dart';
import 'package:regular_scanner/built_scanner.dart';

import 'token.dart';

part 'lexer.g.dart';

const _controlCharacterEscape =
    TokenType(r'\\[trnvf0]', _extractConrolCharacter);
const _unicodeEscape =
    TokenType(r'\\[Uu]{[0-9A-Fa-f]+}', _extractUnicodeLiteral);
const _unrecognizedEscape = TokenType(r'\\', _rejectUnrecognizedEscape);
const _sharedContextEscapes = TokenType(r'\\[\[\]\\]', _extractEscapedOperator);
const _defaultContextEscapes =
    TokenType(r'\\[.+*?()|]', _extractEscapedOperator);
const _characterSetEscapes = TokenType(r'\\[\^\-]', _extractEscapedOperator);

@InjectScanner([
  characterSetStart,
  characterSetEnd,
  literal,
  dot,
  repetitionPlus,
  repetitionStar,
  repetitionQuestionmark,
  groupStart,
  groupEnd,
  choice,
  _controlCharacterEscape,
  _unicodeEscape,
  _sharedContextEscapes,
  _unrecognizedEscape,
  _defaultContextEscapes
])
const defaultContextScanner = _$defaultContextScanner;

@InjectScanner([
  characterSetStart,
  characterSetEnd,
  literal,
  rangeSeparator,
  negation,
  _controlCharacterEscape,
  _unicodeEscape,
  _sharedContextEscapes,
  _characterSetEscapes,
  _unrecognizedEscape
])
const characterSetScanner = _$characterSetScanner;

/// Extractor for [_controlCharacterEscape]. Returns the specified control
/// character.
int _extractConrolCharacter(ScannerMatch m) {
  switch (m.input.codeUnitAt(m.start + 1)) {
    case $t:
      return $tab;
    case $r:
      return $cr;
    case $n:
      return $lf;
    case $v:
      return $vt;
    case $f:
      return $ff;
    case $0:
      return $nul;
    default:
      throw UnimplementedError();
  }
}

/// Extractor for [_unicodeEscape]. Returns the specified hex value.
int _extractUnicodeLiteral(ScannerMatch m) => 0;

/// Extractor for [_unrecognizedEscape]. Throws [FormatException].
int _rejectUnrecognizedEscape(ScannerMatch m) =>
    throw FormatException('Unrecognized escape sequence', m.input, m.start);

/// Extractor for escaped special characters. Returns the escaped character.
int _extractEscapedOperator(ScannerMatch m) {
  assert(m.length == 2);
  assert(m.input.codeUnitAt(m.start) == $backslash);
  return m.input.codeUnitAt(m.start + 1);
}
