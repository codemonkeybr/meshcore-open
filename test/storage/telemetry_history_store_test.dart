import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/storage/telemetry_history_store.dart';
import 'package:meshcore_open/storage/telemetry_history_store_factory_io.dart';

void main() {
  group('FileTelemetryHistoryStore', () {
    late Directory dir;
    late FileTelemetryHistoryStore store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('telemetry_history_test');
      store = FileTelemetryHistoryStore(rootOverride: dir);
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('a missing history reads as empty', () async {
      expect(await store.readLines('aabbccddee', '1122334455'), isEmpty);
    });

    test('appends lines in order and reads them back', () async {
      await store.appendLine('aabbccddee', '1122334455', '{"a":1}');
      await store.appendLine('aabbccddee', '1122334455', '{"a":2}');
      expect(await store.readLines('aabbccddee', '1122334455'), [
        '{"a":1}',
        '{"a":2}',
      ]);
    });

    test('keeps each radio and node separate', () async {
      await store.appendLine('aabbccddee', '1122334455', 'one');
      await store.appendLine('ffffffffff', '1122334455', 'two');
      await store.appendLine('aabbccddee', '9999999999', 'three');
      expect(await store.readLines('aabbccddee', '1122334455'), ['one']);
      expect(await store.readLines('ffffffffff', '1122334455'), ['two']);
      expect(await store.readLines('aabbccddee', '9999999999'), ['three']);
    });

    test(
      'replaceLines swaps the whole history and leaves no temp file',
      () async {
        await store.appendLine('aabbccddee', '1122334455', 'old');
        await store.replaceLines('aabbccddee', '1122334455', ['new1', 'new2']);
        expect(await store.readLines('aabbccddee', '1122334455'), [
          'new1',
          'new2',
        ]);
        final leftovers = dir
            .listSync(recursive: true)
            .where((e) => e.path.endsWith('.tmp'));
        expect(leftovers, isEmpty);
      },
    );

    test('delete removes the history and is safe to repeat', () async {
      await store.appendLine('aabbccddee', '1122334455', 'x');
      await store.delete('aabbccddee', '1122334455');
      await store.delete('aabbccddee', '1122334455');
      expect(await store.readLines('aabbccddee', '1122334455'), isEmpty);
    });

    test(
      'keys that are not hex are refused and never touch the disk',
      () async {
        await store.appendLine('../evil', '1122334455', 'x');
        await store.appendLine('aabbccddee', '../../x', 'x');
        expect(await store.readLines('../evil', '1122334455'), isEmpty);
        expect(dir.listSync(recursive: true).whereType<File>(), isEmpty);
      },
    );
  });

  group('InMemoryTelemetryHistoryStore', () {
    test('behaves like the file store', () async {
      final store = InMemoryTelemetryHistoryStore();
      await store.appendLine('a', 'b', '1');
      await store.appendLine('a', 'b', '2');
      expect(await store.readLines('a', 'b'), ['1', '2']);
      await store.replaceLines('a', 'b', ['3']);
      expect(await store.readLines('a', 'b'), ['3']);
      await store.delete('a', 'b');
      expect(await store.readLines('a', 'b'), isEmpty);
    });
  });

  test('isValidHistoryKey accepts only short hex', () {
    expect(isValidHistoryKey('aabbccddee'), isTrue);
    expect(isValidHistoryKey(''), isFalse);
    expect(isValidHistoryKey('../x'), isFalse);
    expect(isValidHistoryKey('zz'), isFalse);
  });
}
