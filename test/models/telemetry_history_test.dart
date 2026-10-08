import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/remote_node_stats.dart';
import 'package:meshcore_open/models/telemetry_history.dart';

void main() {
  final t = DateTime.fromMillisecondsSinceEpoch(1790000000 * 1000);

  test('RadioSample round-trips through json', () {
    final sample = RadioSample(
      time: t,
      batteryMv: 4180,
      snr: 12.5,
      rssi: -46,
      noiseFloor: -103,
      sentDirect: 10,
      sentFlood: 20,
      dupDirect: 3,
      dupFlood: 4,
      errors: 5,
    );
    final restored = RadioSample.fromJson(sample.toJson())!;
    expect(restored.time, t);
    expect(restored.batteryMv, 4180);
    expect(restored.snr, 12.5);
    expect(restored.rssi, -46);
    expect(restored.noiseFloor, -103);
    expect(restored.sentFlood, 20);
    expect(restored.errors, 5);
  });

  test('RadioSample.fromStats prefers receive errors over error events', () {
    const stats = RemoteNodeStats(
      batteryMv: 4000,
      queueLen: 0,
      noiseFloor: -100,
      lastRssi: -50,
      packetsRecv: 1,
      packetsSent: 2,
      txAirSecs: 0,
      uptimeSecs: 0,
      floodTx: 7,
      directTx: 8,
      floodRx: 0,
      directRx: 0,
      errEvents: 1,
      lastSnr: 3.25,
      directDups: 4,
      floodDups: 5,
      recvErrors: 99,
    );
    final sample = RadioSample.fromStats(t, stats);
    expect(sample.errors, 99);
    expect(sample.sentDirect, 8);
    expect(sample.sentFlood, 7);
    expect(sample.snr, 3.25);
  });

  test('NeighborSample and SensorSample round-trip', () {
    final neighbors = NeighborSample(
      time: t,
      readings: const [
        NeighborReading(prefixHex: '8dbc303d', snr: -6.75),
        NeighborReading(prefixHex: 'cb8ccfe7', snr: 4),
      ],
    );
    final n = NeighborSample.fromJson(neighbors.toJson())!;
    expect(n.readings.map((r) => r.prefixHex), ['8dbc303d', 'cb8ccfe7']);
    expect(n.readings.first.snr, -6.75);

    final sensors = SensorSample(
      time: t,
      values: const {'1/temperature': 21.5, '1/voltage': 4.12},
    );
    final s = SensorSample.fromJson(sensors.toJson())!;
    expect(s.values['1/temperature'], 21.5);
    expect(s.values['1/voltage'], 4.12);
  });

  test('damaged records read as null instead of throwing', () {
    expect(RadioSample.fromJson({'t': 'x'}), isNull);
    expect(NeighborSample.fromJson({'t': 1, 'v': 'bad'}), isNull);
    expect(SensorSample.fromJson(const {}), isNull);
  });
}
