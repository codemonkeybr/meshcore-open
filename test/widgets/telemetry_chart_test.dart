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
}
