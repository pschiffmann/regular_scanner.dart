import 'dart:async';
import 'dart:io';

import 'package:regular_scanner/regular_scanner.dart';

// const word = Regex('[A-Za-z]+');
// const other = Regex('[^A-Za-z]+');
const word = Regex('[A-Za-z]+');
final scanner = Scanner.unambiguous([word]);
Stream<String> findWords(Stream<int> codePoints) async* {
  final sm = scanner.stateMachine();
  final buffer = StringBuffer();
  await for (final codePoint in codePoints) {
    sm.moveNext(codePoint);
    if (sm.inErrorState) {
      if (buffer.isNotEmpty) {
        yield buffer.toString();
        buffer.clear();
      }
    } else if (sm.accept == word) {
      buffer.writeCharCode(codePoint);
    }
    sm.reset();
  }
  if (buffer.isNotEmpty) yield buffer.toString();
}

void main() {
  // This file is UTF-8 encoded and contains only ASCII characters, so byte
  // values are equal to code point values. In a real world use case, you must
  // decode bytes to code points.
  final bytes =
      Stream.fromIterable(File('example/word_stream.dart').readAsBytesSync());
  findWords(bytes).listen(print);
}
