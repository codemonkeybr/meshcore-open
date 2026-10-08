import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../helpers/telemetry_series.dart';

/// One line on a [TelemetryChart].
class ChartSeries {
  final String label;
  final Color color;
  final List<SeriesPoint> points;
  final bool fill;

  const ChartSeries({
    required this.label,
    required this.color,
    required this.points,
    this.fill = false,
  });
}

/// A time-series line chart: dates along the bottom, values up the side, and a
/// touch tooltip with the exact date and value.
class TelemetryChart extends StatelessWidget {
  final List<ChartSeries> series;
  final String unit;
  final int decimals;

  /// Fixed value range. When null the range follows the data, padded and at
  /// least [minSpan] tall so a flat line does not fill the whole chart.
  final double? minY;
  final double? maxY;
  final double minSpan;

  /// Left and right edges of the time axis.
  final DateTime start;
  final DateTime end;
  final double height;

  const TelemetryChart({
    super.key,
    required this.series,
    required this.start,
    required this.end,
    this.unit = '',
    this.decimals = 0,
    this.minY,
    this.maxY,
    this.minSpan = 1,
    this.height = 130,
  });

  static const int _dotLimit = 40;

  (double, double) _range() {
    if (minY != null && maxY != null) return (minY!, maxY!);
    final values = [
      for (final s in series)
        for (final p in s.points) p.value,
    ];
    if (values.isEmpty) return (0, minSpan);
    var lo = values.reduce(math.min);
    var hi = values.reduce(math.max);
    var pad = (hi - lo) * 0.1;
    if (hi - lo + 2 * pad < minSpan) pad = (minSpan - (hi - lo)) / 2;
    lo -= pad;
    hi += pad;
    return (minY ?? lo, maxY ?? hi);
  }

  double _x(DateTime t) =>
      t.difference(start).inMinutes / Duration.minutesPerDay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final dayFormat = DateFormat.MMMd(locale);
    final tooltipFormat = DateFormat.MMMd(locale).add_Hm();
    final axisStyle = TextStyle(fontSize: 10, color: scheme.onSurfaceVariant);

    final (lo, hi) = _range();
    final spanDays = math.max(_x(end), 0.01);
    final yInterval = (hi - lo) / 3;

    String fmt(double v) => v.toStringAsFixed(decimals);

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: spanDays,
          minY: lo,
          maxY: hi,
          clipData: const FlClipData.all(),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: yInterval,
            getDrawingHorizontalLine: (_) => FlLine(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
              strokeWidth: 0.7,
              dashArray: const [3, 4],
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: yInterval,
                getTitlesWidget: (value, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(fmt(value), style: axisStyle),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                interval: spanDays / 3,
                getTitlesWidget: (value, meta) {
                  final at = start.add(
                    Duration(minutes: (value * Duration.minutesPerDay).round()),
                  );
                  return SideTitleWidget(
                    meta: meta,
                    fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                    child: Text(dayFormat.format(at), style: axisStyle),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipColor: (_) => scheme.surfaceContainerHighest,
              getTooltipItems: (spots) => [
                for (final spot in spots)
                  LineTooltipItem(
                    '${tooltipFormat.format(start.add(Duration(minutes: (spot.x * Duration.minutesPerDay).round())))}\n'
                    '${series.length > 1 ? '${series[spot.barIndex].label}: ' : ''}'
                    '${fmt(spot.y)}$unit',
                    TextStyle(
                      fontSize: 11,
                      color: series[spot.barIndex].color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            for (final s in series)
              LineChartBarData(
                spots: [for (final p in s.points) FlSpot(_x(p.time), p.value)],
                isCurved: false,
                color: s.color,
                barWidth: 1.6,
                dotData: FlDotData(
                  show: s.points.length <= _dotLimit,
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                        radius: 2.2,
                        color: s.color,
                        strokeWidth: 0,
                      ),
                ),
                belowBarData: BarAreaData(
                  show: s.fill,
                  color: s.color.withValues(alpha: 0.12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
