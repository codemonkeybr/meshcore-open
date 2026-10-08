import '../models/remote_node_stats.dart';

/// One saved reading of a repeater's or room's radio statistics.
///
/// The packet, duplicate and error counters are cumulative since the node
/// last booted, so they drop back to a small number after a reboot.
class RadioSample {
  final DateTime time;
  final int batteryMv;
  final double snr;
  final int rssi;
  final int noiseFloor;
  final int sentDirect;
  final int sentFlood;
  final int dupDirect;
  final int dupFlood;
  final int errors;

  const RadioSample({
    required this.time,
    required this.batteryMv,
    required this.snr,
    required this.rssi,
    required this.noiseFloor,
    required this.sentDirect,
    required this.sentFlood,
    required this.dupDirect,
    required this.dupFlood,
    required this.errors,
  });

  factory RadioSample.fromStats(DateTime time, RemoteNodeStats stats) {
    return RadioSample(
      time: time,
      batteryMv: stats.batteryMv,
      snr: stats.lastSnr,
      rssi: stats.lastRssi,
      noiseFloor: stats.noiseFloor,
      sentDirect: stats.directTx,
      sentFlood: stats.floodTx,
      dupDirect: stats.directDups,
      dupFlood: stats.floodDups,
      errors: stats.recvErrors ?? stats.errEvents,
    );
  }

  Map<String, dynamic> toJson() => {
    't': time.millisecondsSinceEpoch ~/ 1000,
    'k': 'r',
    'b': batteryMv,
    's': snr,
    'r': rssi,
    'n': noiseFloor,
    'sd': sentDirect,
    'sf': sentFlood,
    'dd': dupDirect,
    'df': dupFlood,
    'e': errors,
  };

  static RadioSample? fromJson(Map<String, dynamic> json) {
    try {
      return RadioSample(
        time: DateTime.fromMillisecondsSinceEpoch((json['t'] as int) * 1000),
        batteryMv: json['b'] as int,
        snr: (json['s'] as num).toDouble(),
        rssi: json['r'] as int,
        noiseFloor: json['n'] as int,
        sentDirect: json['sd'] as int,
        sentFlood: json['sf'] as int,
        dupDirect: json['dd'] as int,
        dupFlood: json['df'] as int,
        errors: json['e'] as int,
      );
    } catch (_) {
      return null;
    }
  }
}

/// SNR a repeater reported for one neighbor, identified by its key prefix.
class NeighborReading {
  final String prefixHex;
  final double snr;

  const NeighborReading({required this.prefixHex, required this.snr});
}

/// The neighbor list a repeater reported at one moment.
class NeighborSample {
  final DateTime time;
  final List<NeighborReading> readings;

  const NeighborSample({required this.time, required this.readings});

  Map<String, dynamic> toJson() => {
    't': time.millisecondsSinceEpoch ~/ 1000,
    'k': 'n',
    'v': [
      for (final r in readings) [r.prefixHex, r.snr],
    ],
  };

  static NeighborSample? fromJson(Map<String, dynamic> json) {
    try {
      return NeighborSample(
        time: DateTime.fromMillisecondsSinceEpoch((json['t'] as int) * 1000),
        readings: [
          for (final entry in json['v'] as List)
            NeighborReading(
              prefixHex: (entry as List)[0] as String,
              snr: (entry[1] as num).toDouble(),
            ),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

/// Numeric sensor readings a node reported at one moment, keyed
/// `"<channel>/<name>"` (for example `"1/temperature"`). Temperatures are
/// stored in °C and converted when displayed.
class SensorSample {
  final DateTime time;
  final Map<String, double> values;

  const SensorSample({required this.time, required this.values});

  Map<String, dynamic> toJson() => {
    't': time.millisecondsSinceEpoch ~/ 1000,
    'k': 's',
    'v': values,
  };

  static SensorSample? fromJson(Map<String, dynamic> json) {
    try {
      return SensorSample(
        time: DateTime.fromMillisecondsSinceEpoch((json['t'] as int) * 1000),
        values: {
          for (final e in (json['v'] as Map).entries)
            e.key as String: (e.value as num).toDouble(),
        },
      );
    } catch (_) {
      return null;
    }
  }
}

/// Everything saved for one node, oldest first.
class NodeHistory {
  final List<RadioSample> radio;
  final List<NeighborSample> neighbors;
  final List<SensorSample> sensors;

  const NodeHistory({
    this.radio = const [],
    this.neighbors = const [],
    this.sensors = const [],
  });

  bool get isEmpty => radio.isEmpty && neighbors.isEmpty && sensors.isEmpty;
}
