import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/remote_node_stats.dart';
import '../models/telemetry_history.dart';
import '../storage/telemetry_history_store.dart';

/// Saves and serves the readings charted on the telemetry history screen.
///
/// Readings are recorded whenever a repeater's Status, Neighbors or Telemetry
/// data is fetched. Passive recording is throttled to one reading per kind per
/// node every [minInterval]; an explicit refresh passes `force: true` so it
/// always saves. Readings older than [retention] are dropped.
class TelemetryHistoryService extends ChangeNotifier {
  static const Duration minInterval = Duration(minutes: 15);
  static const Duration retention = Duration(days: 365);

  final TelemetryHistoryStore _store;
  final DateTime Function() _now;

  final Map<String, NodeHistory> _cache = {};
  Future<void> _queue = Future.value();

  TelemetryHistoryService(this._store, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// The storage key for a public key: its first 10 hex characters, the same
  /// scoping the other per-radio stores use.
  static String keyOf(String publicKeyHex) =>
      publicKeyHex.length > 10 ? publicKeyHex.substring(0, 10) : publicKeyHex;

  String _id(String deviceKey, String nodeKey) => '$deviceKey/$nodeKey';

  /// Runs [action] after every earlier storage operation has finished, so
  /// concurrent records and loads cannot interleave.
  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// The saved history, or an empty one if nothing was loaded yet.
  NodeHistory cached(String deviceKey, String nodeKey) =>
      _cache[_id(deviceKey, nodeKey)] ?? const NodeHistory();

  /// Loads a node's history from storage, dropping readings older than
  /// [retention]. Safe to call repeatedly.
  Future<NodeHistory> load(String deviceKey, String nodeKey) {
    return _serialized(() async {
      final history = await _loadLocked(deviceKey, nodeKey);
      notifyListeners();
      return history;
    });
  }

  Future<NodeHistory> _loadLocked(String deviceKey, String nodeKey) async {
    final id = _id(deviceKey, nodeKey);
    final cached = _cache[id];
    if (cached != null) return cached;

    final lines = await _store.readLines(deviceKey, nodeKey);
    final cutoff = _now().subtract(retention);
    final radio = <RadioSample>[];
    final neighbors = <NeighborSample>[];
    final sensors = <SensorSample>[];
    final keptLines = <String>[];
    var dropped = false;

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        switch (json['k']) {
          case 'r':
            final s = RadioSample.fromJson(json);
            if (s == null) continue;
            if (s.time.isBefore(cutoff)) {
              dropped = true;
              continue;
            }
            radio.add(s);
          case 'n':
            final s = NeighborSample.fromJson(json);
            if (s == null) continue;
            if (s.time.isBefore(cutoff)) {
              dropped = true;
              continue;
            }
            neighbors.add(s);
          case 's':
            final s = SensorSample.fromJson(json);
            if (s == null) continue;
            if (s.time.isBefore(cutoff)) {
              dropped = true;
              continue;
            }
            sensors.add(s);
          default:
            continue;
        }
        keptLines.add(line);
      } catch (_) {
        // A damaged line is skipped, never fatal.
      }
    }

    if (dropped) {
      await _store.replaceLines(deviceKey, nodeKey, keptLines);
    }
    final history = NodeHistory(
      radio: radio,
      neighbors: neighbors,
      sensors: sensors,
    );
    _cache[id] = history;
    return history;
  }

  bool _throttled(DateTime? last, {required bool force}) {
    if (force || last == null) return false;
    return _now().difference(last) < minInterval;
  }

  /// Saves the radio statistics of a node. Returns false when throttled.
  Future<bool> recordRadio(
    String deviceKey,
    String nodeKey,
    RemoteNodeStats stats, {
    bool force = false,
  }) {
    return _serialized(() async {
      final history = await _loadLocked(deviceKey, nodeKey);
      final last = history.radio.isEmpty ? null : history.radio.last.time;
      if (_throttled(last, force: force)) return false;
      final sample = RadioSample.fromStats(_now(), stats);
      await _store.appendLine(deviceKey, nodeKey, jsonEncode(sample.toJson()));
      _cache[_id(deviceKey, nodeKey)] = NodeHistory(
        radio: [...history.radio, sample],
        neighbors: history.neighbors,
        sensors: history.sensors,
      );
      notifyListeners();
      return true;
    });
  }

  /// Saves the neighbor SNRs a repeater reported. Returns false when
  /// throttled or when there is nothing to save.
  Future<bool> recordNeighbors(
    String deviceKey,
    String nodeKey,
    List<NeighborReading> readings, {
    bool force = false,
  }) {
    return _serialized(() async {
      if (readings.isEmpty) return false;
      final history = await _loadLocked(deviceKey, nodeKey);
      final last = history.neighbors.isEmpty
          ? null
          : history.neighbors.last.time;
      if (_throttled(last, force: force)) return false;
      final sample = NeighborSample(time: _now(), readings: readings);
      await _store.appendLine(deviceKey, nodeKey, jsonEncode(sample.toJson()));
      _cache[_id(deviceKey, nodeKey)] = NodeHistory(
        radio: history.radio,
        neighbors: [...history.neighbors, sample],
        sensors: history.sensors,
      );
      notifyListeners();
      return true;
    });
  }

  /// Saves numeric sensor readings keyed `"<channel>/<name>"`. Returns false
  /// when throttled or when there is nothing to save.
  Future<bool> recordSensors(
    String deviceKey,
    String nodeKey,
    Map<String, double> values, {
    bool force = false,
  }) {
    return _serialized(() async {
      if (values.isEmpty) return false;
      final history = await _loadLocked(deviceKey, nodeKey);
      final last = history.sensors.isEmpty ? null : history.sensors.last.time;
      if (_throttled(last, force: force)) return false;
      final sample = SensorSample(time: _now(), values: values);
      await _store.appendLine(deviceKey, nodeKey, jsonEncode(sample.toJson()));
      _cache[_id(deviceKey, nodeKey)] = NodeHistory(
        radio: history.radio,
        neighbors: history.neighbors,
        sensors: [...history.sensors, sample],
      );
      notifyListeners();
      return true;
    });
  }

  /// Deletes a node's saved history.
  Future<void> clear(String deviceKey, String nodeKey) {
    return _serialized(() async {
      await _store.delete(deviceKey, nodeKey);
      _cache[_id(deviceKey, nodeKey)] = const NodeHistory();
      notifyListeners();
    });
  }

  /// Extracts the numeric readings from parsed Cayenne LPP channel data
  /// (`CayenneLpp.parseByChannel`) as `"<channel>/<name>"` -> value. Location
  /// and other non-numeric values are skipped.
  static Map<String, double> sensorValuesFromLpp(
    List<Map<String, dynamic>> channels,
  ) {
    final out = <String, double>{};
    for (final entry in channels) {
      final channel = entry['channel'];
      final values = entry['values'];
      if (channel == null || values is! Map) continue;
      for (final v in values.entries) {
        final value = v.value;
        if (v.key == 'time') continue; // a clock reading, not a sensor
        if (value is num && value.isFinite) {
          out['$channel/${v.key}'] = value.toDouble();
        }
      }
    }
    return out;
  }
}
