library regular_scanner.builder;

import 'dart:async';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:regular_scanner/built_scanner.dart';
import 'package:source_gen/source_gen.dart';

/// The names of all top level elements (classes and variables) generated by
/// this builder start with `_$`.
const generatedNamesPrefix = r'_$';

/// This generator reads the [Regex]es from an [InjectScanner] annotation and
/// generates the Dart code required to instantiate a corresponding [Scanner].
abstract class ScannerGenerator extends GeneratorForAnnotation<InjectScanner> {
  const ScannerGenerator();

  @override
  FutureOr<String> generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) async {
    if (element is! TopLevelVariableElement) {
      throw InvalidGenerationSourceError(
          '@InjectScanner must annotate a top level variable',
          element: element);
    }
    final variable = element as TopLevelVariableElement;
    if (!variable.isConst) {
      log.warning(spanForElement(variable).message(
          'The generated variable is `const`, so you might as well declare '
          'this variable `const` too.'));
    }

    final variableNode =
        (await element.session.getResolvedLibraryByElement(element.library))
            .getElementDeclaration(element)
            .node as VariableDeclaration;
    print(variableNode.runtimeType);
    print(variableNode.parent.runtimeType);
    print(variableNode.parent.parent.runtimeType);
    print(variableNode.parent.parent.parent.runtimeType);

    final regexes =
        resolveAnnotationArguments(variable, null, annotation.objectValue);

    return generateScanner(Scanner.unambiguous(regexes), variable.name);
  }

  /// This method is called from [generateForAnnotatedElement]   generates the
  /// actual code, once the annotation is resolved and validated.
  ///
  /// [scanner] contains a scanner that was built from the [InjectScanner]
  /// annotation values. [scannerVariableName] contains the name of the
  /// annotated variable.
  String generateScanner(
      StateMachineScanner<RegexWithInitializer, Dfa<RegexWithInitializer>>
          scanner,
      String scannerVariableName);
}

/// Extracts the initializer `const` expressions of the individual [Regex]es
/// in the [InjectScanner] annotation from the AST of [variable].
List<RegexWithInitializer> resolveAnnotationArguments(
    TopLevelVariableElement variable,
    TopLevelVariableDeclaration variableNode,
    DartObject injectScanner) {
  final regexes = injectScanner.getField('regexes')?.toListValue();
  if (regexes == null || regexes.isEmpty) {
    throw InvalidGenerationSourceError(
        'The @InjectScanner regex list must not be empty',
        element: variable);
  }

  final metadata = ((variableNode.parent as VariableDeclarationList).parent
          as TopLevelVariableDeclaration)
      .metadata;
  for (final annotation in metadata) {
    if (annotation.elementAnnotation.constantValue != injectScanner) {
      continue;
    }

    final initializerList = annotation.arguments.arguments.first;
    if (initializerList is! ListLiteral) {
      throw InvalidGenerationSourceError(
          'The regexes must be explicitly enumerated in the `@InjectScanner` '
          'annotation parameter',
          element: variable);
    }
    final initializers = (initializerList as ListLiteral).elements;

    final result = <RegexWithInitializer>[];
    for (var i = 0; i < initializers.length; i++) {
      final regex = ConstantReader(regexes[i]);
      result.add(RegexWithInitializer(
          regex.read('regularExpression').stringValue,
          regex.read('precedence').intValue,
          initializers[i].toSource()));
    }
    return result;
  }
  throw UnimplementedError(
      'Reaching this line means we skipped over the relevant annotation – '
      "that's a bug");
}

/// An instance of this class represents a regex from an [InjectScanner]
/// annotation. It contains the [pattern] and [precedence] that are needed for
/// the scanner construction algorithm, and the information how to reconstruct
/// the initial annotation argument in the generated code.
class RegexWithInitializer extends Regex {
  RegexWithInitializer(String pattern, int precedence, this.source)
      : super(pattern, precedence: precedence);

  /// The [Regex] from the [InjectScanner] annotation. This might be a subclass
  /// of [Regex], so we need to store all information about how to reconstruct
  /// it.
  final String source;
}

/// Encodes the built scanner as a `const` [StateMachineScanner].
class StateMachineScannerGenerator extends ScannerGenerator {
  const StateMachineScannerGenerator();

  @override
  String generateScanner(
      StateMachineScanner<RegexWithInitializer, Dfa<RegexWithInitializer>>
          scanner,
      String scannerVariableName) {
    final result = StringBuffer()
      ..write(r'const ')
      ..write(generatedNamesPrefix)
      ..write(scannerVariableName)
      ..write(' = ')
      ..write('Scanner(')
      ..write('Dfa([');
    for (final state in scanner.stateMachine().states) {
      result
        ..write('DState(')
        ..writeln('[');
      for (final transition in state.transitions) {
        result
          ..write('Transition(')
          ..write(transition.min)
          ..write(', ')
          ..write(transition.max)
          ..write(', ')
          ..write(transition.successor)
          ..writeln('),');
      }
      result
        ..write('], ')
        ..write('defaultTransition: ')
        ..write(state.defaultTransition);
      if (state.accept != null) {
        result..write(', ')..write('accept: ')..write(state.accept.source);
      }
      result.writeln('),');
    }
    return (result..writeln(']));')).toString();
  }
}
