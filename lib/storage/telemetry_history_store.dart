/// Persistence for saved telemetry readings, one append-only list of JSON
/// lines per node per radio.
///
/// Keys are the first 10 hex characters of the connected radio's public key
/// ([deviceKey]) and of the node's public key ([nodeKey]), so each radio keeps
/// its own history, the same scoping the other per-radio stores use.
abstract class TelemetryHistoryStore {
  /// Every stored line, oldest first. A missing history reads as empty.
  Future<List<String>> readLines(String deviceKey, String nodeKey);

  /// Adds one line to the end of the history.
  Future<void> appendLine(String deviceKey, String nodeKey, String line);

  /// Replaces the whole history, for pruning old readings.
  Future<void> replaceLines(
    String deviceKey,
    String nodeKey,
    List<String> lines,
  );

  /// Deletes the history. Deleting a missing history is not an error.
  Future<void> delete(String deviceKey, String nodeKey);
}

/// Keys become file names, so only short hex strings are accepted.
bool isValidHistoryKey(String key) =>
    RegExp(r'^[0-9a-fA-F]{1,32}$').hasMatch(key);

/// History kept for the life of the process: web, and tests.
class InMemoryTelemetryHistoryStore implements TelemetryHistoryStore {
  final Map<String, List<String>> _data = {};

  String _id(String deviceKey, String nodeKey) => '$deviceKey/$nodeKey';

  @override
  Future<List<String>> readLines(String deviceKey, String nodeKey) async =>
      List<String>.of(_data[_id(deviceKey, nodeKey)] ?? const []);

  @override
  Future<void> appendLine(String deviceKey, String nodeKey, String line) async {
    _data.putIfAbsent(_id(deviceKey, nodeKey), () => []).add(line);
  }

  @override
  Future<void> replaceLines(
    String deviceKey,
    String nodeKey,
    List<String> lines,
  ) async {
    _data[_id(deviceKey, nodeKey)] = List<String>.of(lines);
  }

  @override
  Future<void> delete(String deviceKey, String nodeKey) async {
    _data.remove(_id(deviceKey, nodeKey));
  }
}
