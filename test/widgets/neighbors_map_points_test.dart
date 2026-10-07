import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/widgets/neighbors_map.dart';

Contact _repeater(String name, {double? lat, double? lon, int seed = 1}) {
  return Contact(
    publicKey: Uint8List.fromList(List.generate(32, (i) => i + seed)),
    name: name,
    type: 2,
    pathLength: 0,
    path: Uint8List(0),
    latitude: lat,
    longitude: lon,
    lastSeen: DateTime(2026),
  );
}

Map<String, dynamic> _neighbor(Contact? contact, double snr, int heard) => {
  'contact': contact,
  'publicKey': Uint8List(4),
  'lastHeard': heard,
  'snr': snr,
};

void main() {
  group('buildNeighborMapPoints', () {
    test('keeps only neighbors that resolve to a contact with a position', () {
      final withGps = _repeater('Ridge', lat: 45.5, lon: -73.6);
      final noGps = _repeater('Valley', seed: 2);
      final points = buildNeighborMapPoints([
        _neighbor(withGps, 6.5, 30),
        _neighbor(noGps, -3.0, 60),
        _neighbor(null, 1.0, 90),
      ]);

      expect(points, hasLength(1));
      expect(points.single.contact.name, 'Ridge');
      expect(points.single.index, 0);
      expect(points.single.snr, 6.5);
      expect(points.single.lastHeardSeconds, 30);
    });

    test('keeps the original list index for later neighbors', () {
      final a = _repeater('A', lat: 10, lon: 10);
      final b = _repeater('B', lat: 11, lon: 11, seed: 3);
      final points = buildNeighborMapPoints([
        _neighbor(null, 0, 1),
        _neighbor(a, 1, 2),
        _neighbor(b, 2, 3),
      ]);
      expect(points.map((p) => p.index), [1, 2]);
    });

    test('returns empty for no neighbors', () {
      expect(buildNeighborMapPoints(const []), isEmpty);
    });
  });
}
