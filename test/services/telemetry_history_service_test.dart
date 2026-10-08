import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/remote_node_stats.dart';
import 'package:meshcore_open/models/telemetry_history.dart';
import 'package:meshcore_open/services/telemetry_history_service.dart';
import 'package:meshcore_open/storage/telemetry_history_store.dart';

RemoteNodeStats _stats({int batteryMv = 4100}) => RemoteNodeStats(
  batteryMv: batteryMv,
  queueLen: 0,
  noiseFloor: -100,
  lastRssi: -50,
  packetsRecv: 1,
  packetsSent: 2,
  txAirSecs: 0,
  uptimeSecs: 0,
  floodTx: 3,
  directTx: 4,
  floodRx: 0,
  directRx: 0,
  errEvents: 0,
  lastSnr: 10,
  directDups: 1,
  floodDups: 2,
);

void main() {
  late DateTime clock;
  late InMemoryTelemetryHistoryStore store;
  late TelemetryHistoryService service;

  const device = 'aabbccddee';
  const node = '1122334455';

  setUp(() {
    clock = DateTime(2026, 10, 7, 12);
    store = InMemoryTelemetryHistoryStore();
    service = TelemetryHistoryService(store, now: () => clock);
  });

  test('records a radio sample and serves it back', () async {
    expect(await service.recordRadio(device, node, _stats()), isTrue);
    final history = service.cached(device, node);
    expect(history.radio, hasLength(1));
    expect(history.radio.single.batteryMv, 4100);
    expect(history.radio.single.time, clock);
  });

  test(
    'passive recording is throttled to one per 15 minutes per kind',
    () async {
      expect(await service.recordRadio(device, node, _stats()), isTrue);
      clock = clock.add(const Duration(minutes: 14));
      expect(await service.recordRadio(device, node, _stats()), isFalse);
      clock = clock.add(const Duration(minutes: 1));
      expect(await service.recordRadio(device, node, _stats()), isTrue);
      expect(service.cached(device, node).radio, hasLength(2));
    },
  );

  test('force bypasses the throttle', () async {
    await service.recordRadio(device, node, _stats());
    expect(
      await service.recordRadio(device, node, _stats(), force: true),
      isTrue,
    );
    expect(service.cached(device, node).radio, hasLength(2));
  });

  test('each kind is throttled independently', () async {
    await service.recordRadio(device, node, _stats());
    expect(
      await service.recordSensors(device, node, {'1/temperature': 20}),
      isTrue,
    );
    expect(
      await service.recordNeighbors(device, node, const [
        NeighborReading(prefixHex: 'aabbccdd', snr: 5),
      ]),
      isTrue,
    );
  });

  test('nothing to save is not recorded', () async {
    expect(await service.recordNeighbors(device, node, const []), isFalse);
    expect(await service.recordSensors(device, node, const {}), isFalse);
    expect(service.cached(device, node).isEmpty, isTrue);
  });

  test('history survives a restart and keeps radios separate', () async {
    await service.recordRadio(device, node, _stats());
    await service.recordRadio('ffffffffff', node, _stats(batteryMv: 3900));

    final restarted = TelemetryHistoryService(store, now: () => clock);
    final first = await restarted.load(device, node);
    final second = await restarted.load('ffffffffff', node);
    expect(first.radio.single.batteryMv, 4100);
    expect(second.radio.single.batteryMv, 3900);
  });

  test('readings older than a year are dropped on load and removed', () async {
    final old = RadioSample.fromStats(
      clock.subtract(const Duration(days: 366)),
      _stats(batteryMv: 3000),
    );
    final recent = RadioSample.fromStats(
      clock.subtract(const Duration(days: 10)),
      _stats(batteryMv: 4000),
    );
    await store.appendLine(device, node, jsonEncode(old.toJson()));
    await store.appendLine(device, node, jsonEncode(recent.toJson()));

    final history = await service.load(device, node);
    expect(history.radio.map((s) => s.batteryMv), [4000]);
    expect(await store.readLines(device, node), hasLength(1));
  });

  test('damaged lines are skipped without losing the rest', () async {
    final good = RadioSample.fromStats(clock, _stats());
    await store.appendLine(device, node, 'not json at all');
    await store.appendLine(device, node, '{"k":"r","t":"x"}');
    await store.appendLine(device, node, '{"k":"zzz","t":1}');
    await store.appendLine(device, node, jsonEncode(good.toJson()));
    final history = await service.load(device, node);
    expect(history.radio, hasLength(1));
  });

  test('clear empties the history and storage', () async {
    await service.recordRadio(device, node, _stats());
    await service.clear(device, node);
    expect(service.cached(device, node).isEmpty, isTrue);
    expect(await store.readLines(device, node), isEmpty);
  });

  test('concurrent records are all kept, in order', () async {
    await Future.wait([
      for (var i = 0; i < 5; i++)
        service.recordSensors(device, node, {
          '1/temperature': i.toDouble(),
        }, force: true),
    ]);
    final values = service
        .cached(device, node)
        .sensors
        .map((s) => s.values['1/temperature']);
    expect(values, [0, 1, 2, 3, 4]);
    expect(await store.readLines(device, node), hasLength(5));
  });

  test('notifies listeners when something is saved', () async {
    var notifications = 0;
    service.addListener(() => notifications++);
    await service.recordRadio(device, node, _stats());
    expect(notifications, greaterThan(0));
  });

  group('sensorValuesFromLpp', () {
    test('keeps numeric readings keyed by channel and skips the rest', () {
      final values = TelemetryHistoryService.sensorValuesFromLpp([
        {
          'channel': 1,
          'values': {
            'temperature': 21.5,
            'voltage': 4.12,
            'switch': true,
            'time': 1790000000,
            'gps': {'latitude': 1.0, 'longitude': 2.0},
          },
        },
        {
          'channel': 2,
          'values': {'humidity': 60},
        },
      ]);
      expect(values, {
        '1/temperature': 21.5,
        '1/voltage': 4.12,
        '2/humidity': 60.0,
      });
    });
  });

  test('keyOf shortens public keys to ten characters', () {
    expect(TelemetryHistoryService.keyOf('aabbccddeeff0011'), 'aabbccddee');
    expect(TelemetryHistoryService.keyOf('aabb'), 'aabb');
  });
}
