library regular_scanner;

import 'dart:math';

import 'src/regexp/ast_to_nfa.dart';
import 'src/regexp/explain_ambiguity.dart';
import 'src/regexp/parser.dart';
import 'src/regexp/state_machine_scanner.dart';
import 'state_machine.dart';

export 'src/regexp/explain_ambiguity.dart' show AmbiguousRegexException;
export 'src/regexp/state_machine_scanner.dart' show StateMachineScanner;

class Regex {
  const Regex(this.regularExpression, {this.precedence = 0})
      : assert(precedence >= 0);

  final String regularExpression;

  final int precedence;

  @override
  String toString() => '/$regularExpression/';
}

/// Returned by [Scanner.matchAsPrefix] to indicate which [regex] matched a
/// given [input].
class ScannerMatch<T> implements Match {
  ScannerMatch(this.pattern, this.regex, this.input, this.start, this.end)
      : assert(0 <= start && start <= end && end <= input.length);

  @override
  final Scanner<T> pattern;
  @override
  final String input;
  @override
  final int start;
  @override
  final int end;

  final T regex;

  /// The span in [input] that was matched by [regex].
  String get capture => input.substring(start, end);

  /// Returns the length of [capture].
  int get length => end - start;

  /// Returns [capture] if [group] is 0. Else, throws [RangeError].
  @override
  String group(int group) =>
      group == 0 ? capture : (throw RangeError.value(group));
  @override
  String operator [](int group) => this.group(group);
  @override
  List<String> groups(List<int> groupIndices) =>
      groupIndices.map(group).toList(growable: false);

  /// Always returns 0 because [Scanner] doesn't support capturing groups.
  @override
  int get groupCount => 0;
}

abstract class Scanner<T> implements Pattern {
  /// Empty constructor allows extending this class, which can be used to
  /// inherit [allMatches].
  const Scanner();

  @override
  Iterable<ScannerMatch<T>> allMatches(String string, [int start = 0]) sync* {
    while (start < string.length) {
      final match = matchAsPrefix(string, start);
      if (match != null) {
        yield match;
        start += max(match.length, 1);
      } else {
        start++;
      }
    }
  }

  @override
  ScannerMatch<T> matchAsPrefix(String string, [int start = 0]);

  ///
  static StateMachineScanner<R, Dfa<R>> unambiguous<R extends Regex>(
          Iterable<R> regexes) =>
      StateMachineScanner(
          powersetConstruction(_compile(regexes), highestPrecedenceRegex));

  static StateMachineScanner<List<R>, Dfa<List<R>>> ambiguous<R extends Regex>(
          Iterable<R> regexes) =>
      StateMachineScanner(
          powersetConstructionAmbiguous(_compile(regexes), orderByPrecedence));

  static StateMachineScanner<Set<R>, Nfa<R>> nondeterministic<R extends Regex>(
          Iterable<R> regexes) =>
      StateMachineScanner(Nfa(_compile(regexes)));
}

List<NState<T>> _compile<T extends Regex>(Iterable<T> regexes) {
  final startStates = <NState<T>>[];
  for (final regex in regexes) {
    final ast = parse(regex.regularExpression);
    startStates.add(astToNfa(ast, regex));
  }
  return startStates;
}
