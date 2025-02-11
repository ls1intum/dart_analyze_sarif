import 'dart:convert';
import 'dart:io';

import 'package:analyzer/error/error.dart';
import 'package:args/args.dart';
import 'package:parselyzer/parselyzer.dart';
import 'package:path/path.dart' as path;

const version = '0.0.1';

ArgParser buildParser() {
  return ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addFlag(
      'version',
      abbr: 'V',
      negatable: false,
      help: 'Print the tool version.',
    )
    ..addOption('srcroot',
        abbr: 's',
        help:
            'Use this directory as the SRCROOT. All paths in the report will be relative to this directory.')
    ..addOption('input',
        abbr: 'i',
        help:
            'Read the dart analyzer JSON output from this file. If not given, it is read from stdin.')
    ..addOption('output',
        abbr: 'o',
        help:
            'Write the SARIF report to this file. If not given, the report is written to stdout.');
}

void printUsage(ArgParser argParser, [IOSink? file]) {
  file ??= stdout;
  file.write('Usage: analyze_sarif <flags>\n');
  file.write('Converts the output of "dart analyze --format=json" to SARIF.\n');
  file.write('${argParser.usage}\n');
}

void main(List<String> arguments) {
  final ArgParser argParser = buildParser();
  try {
    final ArgResults results = argParser.parse(arguments);

    if (results.flag('help')) {
      printUsage(argParser);
      return;
    }
    if (results.flag('version')) {
      print('analyze_sarif version: $version');
      return;
    }

    final srcRoot = results.option('srcroot');
    final input = results.option('input');
    final output = results.option('output');

    run(srcRoot, input, output);
  } on FormatException catch (e) {
    stderr.write(e.message);
    stderr.write('');
    printUsage(argParser, stderr);
    exit(1);
  }
}

void run(String? srcRootPath, String? inputPath, String? outputPath) async {
  Stream<List<int>> inputStream;
  if (inputPath != null) {
    inputStream = File(inputPath).openRead();
  } else {
    inputStream = stdin;
  }

  final analyzerReport = await inputStream
      .transform(utf8.decoder)
      .transform(json.decoder)
      .single as Map<String, dynamic>;

  final analysis = AnalyzerResult.fromJson(analyzerReport);

  final Uri? srcRoot;
  if (srcRootPath != null) {
    srcRoot = Directory(srcRootPath).absolute.uri;
  } else {
    srcRoot = null;
  }

  Object sarifLog = createSarifLog(analysis, srcRoot);

  final IOSink outputSink;
  if (outputPath != null) {
    outputSink = File(outputPath).openWrite();
  } else {
    outputSink = stdout;
  }

  final utfSink = utf8.encoder.startChunkedConversion(outputSink);
  final jsonSink = json.encoder.startChunkedConversion(utfSink);
  jsonSink.add(sarifLog);
}

Object createSarifLog(AnalyzerResult analysis, Uri? srcRoot) {
  final rulesById = <String, Map<String, Object>>{};

  for (final diagnostic in analysis.diagnostics) {
    rulesById[diagnostic.code] = {
      'id': diagnostic.code,
      if (diagnostic.documentation != null)
        'helpUri': diagnostic.documentation!,
      'properties': {'type': diagnostic.type.name}
    };
  }

  final rules = rulesById.values.toList();

  final ruleIndexById = <String, int>{};

  for (final (i, rule) in rules.indexed) {
    ruleIndexById[rule['id'] as String] = i;
  }

  final results = analysis.diagnostics.map((diagnostic) {
    final Map<String, String> artifactLocation;
    final absolutePath = File(diagnostic.location.file).absolute.path;
    if (srcRoot != null) {
      final relativePath = path.relative(absolutePath, from: srcRoot.path);
      artifactLocation = {'uri': relativePath, 'uriBaseId': 'SRCROOT'};
    } else {
      artifactLocation = {'uri': Uri.file(absolutePath).toString()};
    }

    final region = diagnostic.location.range;

    return {
      'ruleId': diagnostic.code,
      'ruleIndex': ruleIndexById[diagnostic.code]!,
      'level': switch (diagnostic.severity) {
        ErrorSeverity.NONE => 'none',
        ErrorSeverity.INFO => 'note',
        ErrorSeverity.WARNING => 'warning',
        ErrorSeverity.ERROR => 'error',
        _ => 'warning'
      },
      'message': {'text': diagnostic.problemMessage},
      'locations': [
        {
          'physicalLocation': {
            'artifactLocation': artifactLocation,
            'region': {
              'startLine': region.start.line,
              'startColumn': region.start.column,
              'endLine': region.end.line,
              'endColumn': region.end.column,
              'charOffset': region.start.offset,
              'charLength': region.end.offset - region.start.offset,
            }
          }
        }
      ]
    };
  }).toList();

  final sarifLog = {
    'version': '2.1.0',
    '\$schema':
        'https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/schemas/sarif-schema-2.1.0.json',
    'runs': [
      {
        'tool': {
          'driver': {
            'name': 'dart analyze',
            'version': analysis.version.toString(),
            'informationUri': 'https://dart.dev/tools/dart-analyze',
            'rules': rules
          },
        },
        'conversion': {
          'tool': {
            'driver': {
              'name': 'analyze_sarif',
              'semanticVersion': version,
              'informationUri': 'https://github.com/ls1intum/dart_analyze_sarif'
            }
          }
        },
        if (srcRoot != null)
          'originalUriBaseIds': {
            'SRCROOT': {'uri': srcRoot.toString()}
          },
        'results': results
      }
    ]
  };

  return sarifLog;
}
