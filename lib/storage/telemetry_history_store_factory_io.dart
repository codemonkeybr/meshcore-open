/// File-backed [TelemetryHistoryStore] for every platform that has `dart:io`.
///
/// ## Layout
///
/// ```
/// <application support>/telemetry_history/<deviceKey>/<nodeKey>.jsonl
/// ```
///
/// Application *support*, not documents: this is derived data that must not
/// show up in the iOS Files app or be swept into an iCloud backup.
///
/// Appends add one line. A full rewrite (pruning old readings) goes through a
/// temporary file and a rename, so a crash cannot leave a half-written
/// history. Every method is total: I/O errors are swallowed, because losing a
/// history point must never break the screen that recorded it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../utils/app_logger.dart';
import 'telemetry_history_store.dart';

TelemetryHistoryStore createTelemetryHistoryStore() =>
    FileTelemetryHistoryStore();

class FileTelemetryHistoryStore implements TelemetryHistoryStore {
  /// Overrides the storage root, for tests.
  final Directory? rootOverride;

  FileTelemetryHistoryStore({this.rootOverride});

  Future<File?> _file(String deviceKey, String nodeKey) async {
    if (!isValidHistoryKey(deviceKey) || !isValidHistoryKey(nodeKey)) {
      return null;
    }
    final base = rootOverride ?? await getApplicationSupportDirectory();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}telemetry_history'
      '${Platform.pathSeparator}$deviceKey',
    );
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$nodeKey.jsonl');
  }

  @override
  Future<List<String>> readLines(String deviceKey, String nodeKey) async {
    try {
      final file = await _file(deviceKey, nodeKey);
      if (file == null || !await file.exists()) return const [];
      final text = await file.readAsString(encoding: utf8);
      return const LineSplitter().convert(text);
    } catch (e) {
      appLogger.warn('Could not read telemetry history: $e');
      return const [];
    }
  }

  @override
  Future<void> appendLine(String deviceKey, String nodeKey, String line) async {
    try {
      final file = await _file(deviceKey, nodeKey);
      if (file == null) return;
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (e) {
      appLogger.warn('Could not append telemetry history: $e');
    }
  }

  @override
  Future<void> replaceLines(
    String deviceKey,
    String nodeKey,
    List<String> lines,
  ) async {
    try {
      final file = await _file(deviceKey, nodeKey);
      if (file == null) return;
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        lines.isEmpty ? '' : '${lines.join('\n')}\n',
        flush: true,
      );
      await tmp.rename(file.path);
    } catch (e) {
      appLogger.warn('Could not rewrite telemetry history: $e');
    }
  }

  @override
  Future<void> delete(String deviceKey, String nodeKey) async {
    try {
      final file = await _file(deviceKey, nodeKey);
      if (file != null && await file.exists()) await file.delete();
    } catch (e) {
      appLogger.warn('Could not delete telemetry history: $e');
    }
  }
}
