/// Time ranges offered on the telemetry history screen.
enum HistoryRange {
  week,
  month,
  threeMonths,
  all;

  /// How far back the range reaches, or null for everything saved.
  Duration? get window {
    switch (this) {
      case HistoryRange.week:
        return const Duration(days: 7);
      case HistoryRange.month:
        return const Duration(days: 30);
      case HistoryRange.threeMonths:
        return const Duration(days: 90);
      case HistoryRange.all:
        return null;
    }
  }

  /// Oldest time included for the given [now], or null for no limit.
  DateTime? cutoff(DateTime now) {
    final w = window;
    return w == null ? null : now.subtract(w);
  }
}

/// One plotted value.
class SeriesPoint {
  final DateTime time;
  final double value;

  const SeriesPoint(this.time, this.value);
}

/// Keeps only points at or after [cutoff].
List<SeriesPoint> pointsSince(List<SeriesPoint> points, DateTime? cutoff) {
  if (cutoff == null) return points;
  return [
    for (final p in points)
      if (!p.time.isBefore(cutoff)) p,
  ];
}

/// Reduces [points] to at most [maxPoints] by averaging points that fall in
/// the same equal-width time bucket, so a year of readings stays cheap to draw
/// while still showing the shape. Series at or under the limit are returned
/// unchanged. Points must be sorted oldest first.
List<SeriesPoint> bucketSeries(
  List<SeriesPoint> points, {
  int maxPoints = 300,
}) {
  if (points.length <= maxPoints || maxPoints < 2) return points;
  final start = points.first.time.millisecondsSinceEpoch;
  final span = points.last.time.millisecondsSinceEpoch - start;
  if (span <= 0) return [points.first];

  final sums = List<double>.filled(maxPoints, 0);
  final times = List<double>.filled(maxPoints, 0);
  final counts = List<int>.filled(maxPoints, 0);
  for (final p in points) {
    final offset = p.time.millisecondsSinceEpoch - start;
    var index = (offset * maxPoints) ~/ (span + 1);
    if (index >= maxPoints) index = maxPoints - 1;
    sums[index] += p.value;
    times[index] += p.time.millisecondsSinceEpoch.toDouble();
    counts[index] += 1;
  }
  return [
    for (var i = 0; i < maxPoints; i++)
      if (counts[i] > 0)
        SeriesPoint(
          DateTime.fromMillisecondsSinceEpoch((times[i] / counts[i]).round()),
          sums[i] / counts[i],
        ),
  ];
}

/// A sensor name such as `barometricPressure` as readable text
/// (`Barometric pressure`).
String sensorLabel(String name) {
  if (name.isEmpty) return name;
  final spaced = name.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (m) => '${m[1]} ${m[2]!.toLowerCase()}',
  );
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// Display unit for a sensor reading. Temperature is stored in °C; pass
/// [imperial] to show °F.
String sensorUnit(String name, {bool imperial = false}) {
  switch (name) {
    case 'temperature':
      return imperial ? '°F' : '°C';
    case 'humidity':
    case 'percentage':
      return '%';
    case 'voltage':
      return 'V';
    case 'current':
      return 'A';
    case 'pressure':
    case 'barometricPressure':
      return 'hPa';
    case 'luminosity':
      return 'lx';
    case 'altitude':
    case 'distance':
      return 'm';
    case 'power':
      return 'W';
    case 'energy':
      return 'kWh';
    case 'frequency':
      return 'Hz';
    case 'direction':
      return '°';
    default:
      return '';
  }
}

/// Converts a stored sensor value to its display value (°C -> °F when
/// [imperial]).
double sensorDisplayValue(String name, double value, {bool imperial = false}) {
  if (imperial && name == 'temperature') return value * 9 / 5 + 32;
  return value;
}
