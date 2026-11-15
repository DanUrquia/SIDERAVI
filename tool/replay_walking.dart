import 'dart:convert';
import 'dart:io';

import 'package:sidera_vi/sensors/walking/walking_capture.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/replay_walking.dart <walking-report.json>',
    );
    exitCode = 64;
    return;
  }
  final report =
      jsonDecode(await File(arguments.single).readAsString())
          as Map<String, Object?>;
  final replay = replayWalkingReport(report);
  final matches = jsonEncode(replay.events) == jsonEncode(report['events']);
  if (!matches) exitCode = 1;
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'scenario': report['scenario'],
      'source': (report['summary'] as Map)['device']['source'],
      'actualSteps': report['actualSteps'],
      'recordedDetectorVersion': report['detectorVersion'],
      'replayDetectorVersion': WalkingCapture.detectorVersion,
      'recordedConfirmed': (report['summary'] as Map)['confirmed'],
      'replayed': replay.summary(),
      'recordedEventsMatch': matches,
    }),
  );
}
