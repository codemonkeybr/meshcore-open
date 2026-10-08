import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/telemetry_series.dart';

void main() {
  final now = DateTime(2026, 10, 7, 12);

  group('HistoryRange', () {
    test('cutoff reaches back the range length, All has none', () {
      expect(
        HistoryRange.week.cutoff(now),
        now.subtract(const Duration(days: 7)),
      );
      expect(
        HistoryRange.month.cutoff(now),
        now.subtract(const Duration(days: 30)),
      );
      expect(
        HistoryRange.threeMonths.cutoff(now),
        now.subtract(const Duration(days: 90)),
      );
      expect(HistoryRange.all.cutoff(now), isNull);
    });
  });

  group('pointsSince', () {
    test('keeps points at or after the cutoff', () {
      final cutoff = DateTime(2026, 10, 1);
      final points = [
        SeriesPoint(DateTime(2026, 9, 30), 1),
        SeriesPoint(DateTime(2026, 10, 1), 2),
        SeriesPoint(DateTime(2026, 10, 5), 3),
      ];
      expect(pointsSince(points, cutoff).map((p) => p.value), [2, 3]);
      expect(pointsSince(points, null), hasLength(3));
    });
  });

  group('bucketSeries', () {
    List<SeriesPoint> ramp(int n) => [
      for (var i = 0; i < n; i++)
        SeriesPoint(
          DateTime(2026, 1, 1).add(Duration(minutes: i * 15)),
          i.toDouble(),
        ),
    ];

    test('returns short series unchanged', () {
      final points = ramp(50);
      expect(bucketSeries(points, maxPoints: 300), same(points));
      expect(bucketSeries(const []), isEmpty);
    });

    test('caps long series and keeps order and range', () {
      final points = ramp(5000);
      final bucketed = bucketSeries(points, maxPoints: 200);
      expect(bucketed.length, lessThanOrEqualTo(200));
      expect(bucketed.length, greaterThan(150));
      for (var i = 1; i < bucketed.length; i++) {
        expect(bucketed[i].time.isAfter(bucketed[i - 1].time), isTrue);
        expect(bucketed[i].value, greaterThan(bucketed[i - 1].value));
      }
      expect(bucketed.first.value, lessThan(60));
      expect(bucketed.last.value, greaterThan(4900));
    });

    test('averages values that share a bucket', () {
      final t = DateTime(2026, 1, 1);
      final points = [
        SeriesPoint(t, 10),
        SeriesPoint(t.add(const Duration(seconds: 1)), 20),
        SeriesPoint(t.add(const Duration(days: 10)), 100),
        SeriesPoint(t.add(const Duration(days: 10, seconds: 1)), 200),
      ];
      final bucketed = bucketSeries(points, maxPoints: 2);
      expect(bucketed.map((p) => p.value), [15, 150]);
    });

    test('identical timestamps collapse to one point', () {
      final t = DateTime(2026, 1, 1);
      final points = [
        for (var i = 0; i < 10; i++) SeriesPoint(t, i.toDouble()),
      ];
      expect(bucketSeries(points, maxPoints: 5), hasLength(1));
    });
  });

  group('sensor helpers', () {
    test('labels camelCase names as readable text', () {
      expect(sensorLabel('temperature'), 'Temperature');
      expect(sensorLabel('barometricPressure'), 'Barometric pressure');
      expect(sensorLabel(''), '');
    });

    test('units follow the metric or imperial setting for temperature', () {
      expect(sensorUnit('temperature'), '°C');
      expect(sensorUnit('temperature', imperial: true), '°F');
      expect(sensorUnit('voltage'), 'V');
      expect(sensorUnit('somethingNew'), '');
    });

    test('converts only temperature to Fahrenheit', () {
      expect(sensorDisplayValue('temperature', 100, imperial: true), 212);
      expect(sensorDisplayValue('temperature', 20), 20);
      expect(sensorDisplayValue('humidity', 50, imperial: true), 50);
    });
  });
}
