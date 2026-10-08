import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/telemetry_series.dart';
import 'package:meshcore_open/widgets/telemetry_chart.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

void main() {
  final end = DateTime(2026, 10, 7);
  final start = end.subtract(const Duration(days: 30));

  List<SeriesPoint> ramp(int n) => [
    for (var i = 0; i < n; i++)
      SeriesPoint(start.add(Duration(hours: i * 12)), 10 + (i % 5).toDouble()),
  ];

  testWidgets('draws a line chart for several points', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TelemetryChart(
          start: start,
          end: end,
          unit: ' dB',
          series: [
            ChartSeries(label: 'SNR', color: Colors.blue, points: ramp(40)),
          ],
        ),
      ),
    );
    expect(find.byType(LineChart), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('copes with a single point and two series', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TelemetryChart(
          start: start,
          end: end,
          series: [
            ChartSeries(
              label: 'Direct',
              color: Colors.blue,
              points: [SeriesPoint(end, 5)],
            ),
            ChartSeries(label: 'Flood', color: Colors.orange, points: ramp(10)),
          ],
        ),
      ),
    );
    expect(find.byType(LineChart), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a flat series still gets a drawable range', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TelemetryChart(
          start: start,
          end: end,
          minSpan: 0.5,
          decimals: 2,
          series: [
            ChartSeries(
              label: 'Battery',
              color: Colors.green,
              points: [
                for (var i = 0; i < 20; i++)
                  SeriesPoint(start.add(Duration(days: i)), 4.18),
              ],
            ),
          ],
        ),
      ),
    );
    expect(find.byType(LineChart), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('honors a fixed value range', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TelemetryChart(
          start: start,
          end: end,
          minY: -10,
          maxY: 20,
          series: [
            ChartSeries(label: 'SNR', color: Colors.blue, points: ramp(5)),
          ],
        ),
      ),
    );
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.minY, -10);
    expect(chart.data.maxY, 20);
  });

  group('value axis', () {
    double step(LineChartData d) =>
        d.titlesData.leftTitles.sideTitles.interval!;

    bool onTick(double value, double interval) {
      final k = value / interval;
      return (k - k.roundToDouble()).abs() < 1e-6;
    }

    testWidgets('ticks are round and the range sits on them', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TelemetryChart(
            start: start,
            end: end,
            series: [
              ChartSeries(
                label: 'Temp',
                color: Colors.orange,
                points: [
                  SeriesPoint(start.add(const Duration(days: 1)), 14.7),
                  SeriesPoint(start.add(const Duration(days: 2)), 24.7),
                ],
              ),
            ],
          ),
        ),
      );
      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      final interval = step(data);
      expect(onTick(data.minY, interval), isTrue);
      expect(onTick(data.maxY, interval), isTrue);
      expect(data.minY, lessThanOrEqualTo(14.7));
      expect(data.maxY, greaterThanOrEqualTo(24.7));
      // A nice step: 1, 2, 2.5 or 5 times a power of ten.
      expect([1.0, 2.0, 2.5, 5.0], contains(interval));
    });

    testWidgets('counters never go below zero and use whole numbers', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          TelemetryChart(
            start: start,
            end: end,
            nonNegative: true,
            integers: true,
            series: [
              ChartSeries(
                label: 'Sent',
                color: Colors.blue,
                points: [
                  SeriesPoint(start.add(const Duration(days: 1)), 3),
                  SeriesPoint(start.add(const Duration(days: 2)), 47711),
                ],
              ),
            ],
          ),
        ),
      );
      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      expect(data.minY, 0);
      expect(data.maxY, greaterThanOrEqualTo(47711));
      expect(step(data) % 1, 0);
    });

    testWidgets('tiny counts still get whole-number ticks', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TelemetryChart(
            start: start,
            end: end,
            nonNegative: true,
            integers: true,
            series: [
              ChartSeries(
                label: 'Errors',
                color: Colors.red,
                points: [SeriesPoint(end, 2)],
              ),
            ],
          ),
        ),
      );
      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      expect(data.minY, greaterThanOrEqualTo(0));
      expect(data.minY % 1, 0);
      expect(step(data), greaterThanOrEqualTo(1));
    });

    test('labels are short', () {
      expect(TelemetryChart.axisLabel(47711, 20000), '47.7k');
      expect(TelemetryChart.axisLabel(2500000, 500000), '2.5M');
      expect(TelemetryChart.axisLabel(0, 20000), '0');
      expect(TelemetryChart.axisLabel(-47, 5), '-47');
      expect(TelemetryChart.axisLabel(4.2, 0.1), '4.2');
      expect(TelemetryChart.axisLabel(4.25, 0.05), '4.25');
      expect(TelemetryChart.axisLabel(1500, 500), '1.5k');
      expect(TelemetryChart.axisLabel(850, 50), '850');
    });

    testWidgets('each tick is drawn once, with no stacked edge labels', (
      tester,
    ) async {
      Future<List<String>> yLabels(
        List<SeriesPoint> points, {
        bool counter = false,
      }) async {
        await tester.pumpWidget(
          _wrap(
            TelemetryChart(
              start: start,
              end: end,
              nonNegative: counter,
              integers: counter,
              series: [
                ChartSeries(label: 's', color: Colors.blue, points: points),
              ],
            ),
          ),
        );
        final pattern = RegExp(r'^-?[0-9]+(\.[0-9]+)?[kM]?$');
        return [
          for (final t in tester.widgetList<Text>(find.byType(Text)))
            if (t.data != null && pattern.hasMatch(t.data!)) t.data!,
        ];
      }

      for (final (points, counter) in [
        (
          [
            SeriesPoint(start.add(const Duration(days: 1)), 14.7),
            SeriesPoint(start.add(const Duration(days: 2)), 24.7),
          ],
          false,
        ),
        (
          [
            SeriesPoint(start.add(const Duration(days: 1)), 3),
            SeriesPoint(start.add(const Duration(days: 2)), 47711),
          ],
          true,
        ),
        (
          [
            SeriesPoint(start.add(const Duration(days: 1)), -53),
            SeriesPoint(start.add(const Duration(days: 2)), -40),
          ],
          false,
        ),
      ]) {
        final labels = await yLabels(points, counter: counter);
        expect(labels.toSet().length, labels.length, reason: '$labels');
        expect(labels.length, inInclusiveRange(3, 5), reason: '$labels');
      }
    });
  });
}
