library regular_scanner.builder;

import 'dart:async';
import 'dart:core' hide Pattern;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:regular_scanner/src/dfa.dart';
import 'package:source_gen/source_gen.dart';

import 'regular_scanner.dart';

/// The names of all top level elements (classes and variables) generated by
/// this builder start with `_$`.
const String generatedNamesPrefix = r'_$';

/// The [LibraryElement] that represents the
/// `package:regular_scanner/regular_scanner.dart` library.
LibraryElement get regularScannerLibrary =>
    Zone.current[#regularScannerLibrary];

/// The [LibraryElement] that represents the library that is currently getting
/// processed.
LibraryElement get hostLibrary => Zone.current[#hostLibrary];

/// The [BuilderFactory] that is specified in `build.yaml`.
Builder scannerBuilder(BuilderOptions options) =>
    PartBuilder([TableDrivenScannerGenerator()],
        header: options.config['header'] as String);

/// Returns the local name of [cls], as visible in [hostLibrary].
///
/// For example, if [hostLibrary] contains the import directive
/// ```dart
/// import 'package:regular_scanner/regular_scanner.dart' as rs show Scanner;
/// ```
/// then for the [cls] [Scanner], this function will return the string
/// `'rs.Scanner'`.
///
/// Throws an [InvalidGenerationSourceError] if [cls] is not visible in
/// [hostLibrary].
String resolveLocalName(ClassElement cls) {
  final className = cls.name;
  if (hostLibrary.getType(className) == cls) {
    return className;
  }
  for (final import in hostLibrary.imports) {
    final localName =
        import.prefix == null ? className : '${import.name}.$className';
    if (import.namespace.get(localName) == cls) {
      return localName;
    }
  }
  throw InvalidGenerationSourceError(
      '${cls.name} is not visible in the current source file',
      todo: "Import library `${cls.library}`, and don't hide this class");
}

/// This generator reads the [Pattern]s from an [InjectScanner] annotation and
/// generates the Dart code required to instantiate a [Scanner] for these
/// patterns.
abstract class ScannerGenerator extends GeneratorForAnnotation<InjectScanner> {
  const ScannerGenerator();

  @override
  FutureOr<String> generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) {
    final variable = validateAnnotatedElement(element);

    return runZoned(() {
      final patterns =
          resolveInjectScannerArguments(variable, annotation.objectValue);
      final patternType = resolvePatternType(variable);

      return generateScanner(Scanner<PatternWithInitializer>(patterns),
          variable.name, patternType);
    }, zoneValues: {
      #regularScannerLibrary: annotation.objectValue.type.element.library,
      #hostLibrary: variable.library
    });
  }

  /// This method is called from [generateForAnnotatedElement]   generates the
  /// actual code, once the annotation is resolved and validated.
  ///
  /// [scanner] contains a scanner that was built from the [InjectScanner]
  /// annotation values. [scannerVariableName] contains the name of the
  /// annotated variable. [patternType] contains the result of
  /// [resolvePatternType].
  String generateScanner(TableDrivenScanner<PatternWithInitializer> scanner,
      String scannerVariableName, ClassElement patternType);
}

/// Ensures that the element annotated with [InjectScanner] is a valid target
/// for the annotation.
///
/// Throws an [InvalidGenerationSourceError] if
///   * the annotated element is not a [TopLevelVariableElement],
///   * the annotated variable is not declared `const`, or
///   * the annotated variable is not initialized with a variable named
///     `'_$' + variableName`.
TopLevelVariableElement validateAnnotatedElement(Element element) {
  if (element is! TopLevelVariableElement) {
    throw InvalidGenerationSourceError(
        '@InjectScanner must annotate a top level variable',
        element: element);
  }
  final TopLevelVariableElement variable = element;
  if (!variable.isConst) {
    throw InvalidGenerationSourceError(
        '@InjectScanner must annotate a `const` variable',
        element: variable);
  }
  final expectedInitializer = generatedNamesPrefix + variable.name;
  final initializer = variable.computeNode().initializer;
  if (!(initializer is Identifier && initializer.name == expectedInitializer)) {
    throw InvalidGenerationSourceError(
        'The injection point must be initialized to `$expectedInitializer`, '
        ' the generated variable that holds the scanner',
        element: variable);
  }
  return variable;
}

/// Extracts the initializer `const` expressions of the individual [Pattern]s
/// in the [InjectScanner] annotation from the AST of [variable].
List<PatternWithInitializer> resolveInjectScannerArguments(
    TopLevelVariableElement variable, DartObject injectScanner) {
  final patterns = injectScanner.getField('patterns')?.toListValue();
  if (patterns == null || patterns.isEmpty) {
    throw InvalidGenerationSourceError(
        'The @InjectScanner pattern list must not be empty',
        element: variable);
  }

  final astNode = variable.computeNode();
  final metadata =
      (astNode.parent.parent as TopLevelVariableDeclaration).metadata;
  for (final annotation in metadata) {
    if (annotation.elementAnnotation.constantValue != injectScanner) {
      continue;
    }

    final initializerList = annotation.arguments.arguments.first;
    if (initializerList is! ListLiteral) {
      throw InvalidGenerationSourceError(
          'The patterns must be explicitly enumerated in the `@InjectScanner` '
          'annotation parameter',
          element: variable);
    }
    final initializers = (initializerList as ListLiteral).elements;

    final result = <PatternWithInitializer>[];
    for (var i = 0; i < initializers.length; i++) {
      final pattern = ConstantReader(patterns[i]);
      result.add(PatternWithInitializer(
          pattern.read('regularExpression').stringValue,
          pattern.read('precedence').intValue,
          initializers[i].toSource()));
    }
    return result;
  }
  throw UnimplementedError(
      'Reaching this line means we skipped over the relevant annotation – '
      "that's a bug");
}

/// Returns the generic type argument of the generated [Scanner], or `null` if
/// the analyzed code doesn't specify a type.
ClassElement resolvePatternType(TopLevelVariableElement variable) {
  final variableType = variable.type;
  if (variableType == null) {
    return null;
  }
  if (variableType.element != regularScannerLibrary.getType('Scanner')) {
    throw InvalidGenerationSourceError(
        'The static type of the annotated variable must be Scanner',
        element: variable);
  }
  return (variableType as ParameterizedType).typeArguments.first.element;
}

/// An instance of this class represents a pattern from an [InjectScanner]
/// annotation. It contains the [regularExpression] and [precedence] that are
/// needed for the scanner construction algorithm, and the information how to
/// reconstruct the initial annotation argument.
class PatternWithInitializer extends Pattern {
  PatternWithInitializer(
      String regularExpression, int precedence, this.initializerExpression)
      : super(regularExpression, precedence: precedence);

  final String initializerExpression;
}

/// Encodes the built scanner as a `const` [TableDrivenScanner].
class TableDrivenScannerGenerator extends ScannerGenerator {
  @override
  String generateScanner(TableDrivenScanner<PatternWithInitializer> scanner,
      String scannerVariableName, ClassElement patternType) {
    final stateTypeName =
            resolveLocalName(regularScannerLibrary.getType('State')),
        transitionTypeName =
            resolveLocalName(regularScannerLibrary.getType('Transition'));

    final result = StringBuffer()
      ..write(r'const ')
      ..write(generatedNamesPrefix)
      ..write(scannerVariableName)
      ..write(' = ')
      ..write('const ')
      ..write(resolveLocalName(regularScannerLibrary.getType('Scanner')));
    if (patternType != null) {
      result..write('<')..write(resolveLocalName(patternType))..write('>');
    }
    result.writeln('.withParseTable(const [');
    for (final state in scanner.states) {
      result
        ..write('const ')
        ..write(stateTypeName)
        ..writeln('const [');
      for (final transition in state.transitions) {
        result
          ..write('const ')
          ..write(transitionTypeName)
          ..write('(')
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
        result
          ..write(', ')
          ..write('accept: ')
          ..write(state.accept.initializerExpression);
      }
      result.writeln('),');
    }
    return (result..writeln(']);')).toString();
  }
}
