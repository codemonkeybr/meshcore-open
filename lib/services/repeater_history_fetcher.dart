import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../helpers/cayenne_lpp.dart';
import '../helpers/neighbors_protocol.dart';
import '../models/contact.dart';
import '../models/path_selection.dart';
import '../models/remote_node_stats.dart';
import '../models/telemetry_history.dart';
import '../utils/app_logger.dart';
import 'repeater_login.dart';
import 'storage_service.dart';
import 'telemetry_history_service.dart';

enum HistoryFetchStep { login, radio, neighbors, sensors }

enum HistoryStepState { pending, running, done, failed }

/// Why a refresh could not get readings.
enum HistoryFetchFailure {
  /// The companion radio is not connected.
  notConnected,

  /// The repeater refused the saved password, or refused a guest login when
  /// no password was saved.
  loginRejected,

  /// The repeater did not answer.
  noAnswer,
}

class HistoryFetchResult {
  final HistoryFetchFailure? failure;

  /// True when a saved password was used for the login.
  final bool usedSavedPassword;

  final Map<HistoryFetchStep, HistoryStepState> steps;

  const HistoryFetchResult({
    this.failure,
    this.usedSavedPassword = false,
    this.steps = const {},
  });

  bool get succeeded => failure == null;
}

/// Gets fresh readings from a repeater or room and saves them to the
/// telemetry history.
///
/// Logs in first: with the saved password when there is one, otherwise as a
/// guest (empty password), which works on repeaters that allow guest access.
/// Then asks for radio statistics, neighbors (repeaters only) and sensor
/// readings, one after another. One part failing does not stop the others.
class RepeaterHistoryFetcher {
  static const int _maxNeighborPages = 20;

  final MeshCoreConnector connector;
  final TelemetryHistoryService history;
  final StorageService storage;
  final int loginAttempts;
  final Duration loginReplyGrace;

  RepeaterHistoryFetcher({
    required this.connector,
    required this.history,
    StorageService? storage,
    this.loginAttempts = 5,
    this.loginReplyGrace = const Duration(seconds: 2),
  }) : storage = storage ?? StorageService();

  Future<HistoryFetchResult> fetch(
    Contact node, {
    String? password,
    void Function(HistoryFetchStep step, HistoryStepState state)? onProgress,
  }) async {
    final steps = <HistoryFetchStep, HistoryStepState>{};
    void progress(HistoryFetchStep step, HistoryStepState state) {
      steps[step] = state;
      onProgress?.call(step, state);
    }

    if (!connector.isConnected) {
      return HistoryFetchResult(
        failure: HistoryFetchFailure.notConnected,
        steps: steps,
      );
    }

    final current = connector.contacts.firstWhere(
      (c) => c.publicKeyHex == node.publicKeyHex,
      orElse: () => node,
    );
    final saved =
        password ?? await storage.getRepeaterPassword(node.publicKeyHex);
    final usedSaved = saved != null && saved.isNotEmpty;

    progress(HistoryFetchStep.login, HistoryStepState.running);
    final login = await loginToRepeater(
      connector,
      current,
      saved ?? '',
      maxAttempts: loginAttempts,
      replyGrace: loginReplyGrace,
    );
    if (!login.succeeded) {
      progress(HistoryFetchStep.login, HistoryStepState.failed);
      return HistoryFetchResult(
        failure: login.outcome == RepeaterLoginOutcome.rejected
            ? HistoryFetchFailure.loginRejected
            : HistoryFetchFailure.noAnswer,
        usedSavedPassword: usedSaved,
        steps: steps,
      );
    }
    progress(HistoryFetchStep.login, HistoryStepState.done);

    final deviceKey = TelemetryHistoryService.keyOf(connector.selfPublicKeyHex);
    final nodeKey = TelemetryHistoryService.keyOf(current.publicKeyHex);

    var anyDone = false;
    Future<void> run(
      HistoryFetchStep step,
      Future<bool> Function() action,
    ) async {
      progress(step, HistoryStepState.running);
      var ok = false;
      try {
        ok = await action();
      } catch (e) {
        appLogger.warn(
          'History fetch step $step failed: $e',
          tag: 'TelemetryHistory',
        );
      }
      if (ok) anyDone = true;
      progress(step, ok ? HistoryStepState.done : HistoryStepState.failed);
    }

    await run(HistoryFetchStep.radio, () async {
      final stats = await _fetchRadio(current);
      if (stats == null) return false;
      await history.recordRadio(deviceKey, nodeKey, stats, force: true);
      return true;
    });

    if (current.type == advTypeRepeater) {
      await run(HistoryFetchStep.neighbors, () async {
        final readings = await _fetchNeighbors(current);
        if (readings == null) return false;
        await history.recordNeighbors(
          deviceKey,
          nodeKey,
          readings,
          force: true,
        );
        return true;
      });
    }

    await run(HistoryFetchStep.sensors, () async {
      final values = await _fetchSensors(current);
      if (values == null) return false;
      await history.recordSensors(deviceKey, nodeKey, values, force: true);
      return true;
    });

    return HistoryFetchResult(
      failure: anyDone ? null : HistoryFetchFailure.noAnswer,
      usedSavedPassword: usedSaved,
      steps: steps,
    );
  }

  Duration _timeoutFor(PathSelection selection, int frameLength) {
    final ms = connector.calculateTimeout(
      pathLength: selection.useFlood ? -1 : selection.hopCount,
      messageBytes: math.max(frameLength, maxFrameSize),
    );
    return Duration(milliseconds: ms);
  }

  Future<RemoteNodeStats?> _fetchRadio(Contact node) async {
    final selection = await connector.preparePathForContactSend(node);
    final frame = buildSendStatusRequestFrame(node.publicKey);
    final timeout = _timeoutFor(selection, frame.length);
    final prefix = node.publicKey.sublist(0, 6);
    final isRoom = node.type == advTypeRoom;

    final completer = Completer<RemoteNodeStats?>();
    final subscription = connector.receivedFrames.listen((f) {
      if (f.length < 8 || f[0] != pushCodeStatusResponse) return;
      if (!listEquals(f.sublist(2, 8), prefix)) return;
      final stats = RemoteNodeStats.tryParse(f, isRoom: isRoom);
      if (stats != null && !completer.isCompleted) completer.complete(stats);
    });
    try {
      await connector.sendFrame(frame);
      final stats = await completer.future.timeout(
        timeout,
        onTimeout: () => null,
      );
      connector.recordRepeaterPathResult(node, selection, stats != null, null);
      return stats;
    } finally {
      await subscription.cancel();
    }
  }

  /// Sends a binary request and returns the reply body after the 4-byte tag,
  /// or null when no matching reply arrives in time.
  Future<Uint8List?> _binaryRequest(Contact node, Uint8List payload) async {
    final selection = await connector.preparePathForContactSend(node);
    final frame = buildSendBinaryReq(node.publicKey, payload: payload);
    final timeout = _timeoutFor(selection, frame.length);

    final completer = Completer<Uint8List?>();
    Uint8List? tag;
    final subscription = connector.receivedFrames.listen((f) {
      if (f.isEmpty) return;
      if (f[0] == respCodeSent && tag == null && f.length >= 6) {
        tag = Uint8List.fromList(f.sublist(2, 6));
        return;
      }
      final expected = tag;
      if (f[0] == pushCodeBinaryResponse &&
          expected != null &&
          f.length >= 6 &&
          listEquals(f.sublist(2, 6), expected) &&
          !completer.isCompleted) {
        completer.complete(Uint8List.fromList(f.sublist(6)));
      }
    });
    try {
      await connector.sendFrame(frame);
      final body = await completer.future.timeout(
        timeout,
        onTimeout: () => null,
      );
      connector.recordRepeaterPathResult(node, selection, body != null, null);
      return body;
    } finally {
      await subscription.cancel();
    }
  }

  Future<List<NeighborReading>?> _fetchNeighbors(Contact node) async {
    final readings = <NeighborReading>[];
    var total = 0;
    for (var page = 0; page < _maxNeighborPages; page++) {
      final body = await _binaryRequest(
        node,
        NeighborsProtocol.requestPayload(readings.length),
      );
      if (body == null) return readings.isEmpty ? null : readings;
      final parsed = NeighborsProtocol.parsePage(body);
      total = parsed.total;
      if (parsed.page.isEmpty) break;
      for (final n in parsed.page) {
        readings.add(
          NeighborReading(
            prefixHex: pubKeyToHex(n['publicKey'] as Uint8List),
            snr: n['snr'] as double,
          ),
        );
      }
      if (readings.length >= total) break;
    }
    return readings;
  }

  Future<Map<String, double>?> _fetchSensors(Contact node) async {
    final body = await _binaryRequest(node, buildTelemetryBinaryPayload());
    if (body == null) return null;
    final values = TelemetryHistoryService.sensorValuesFromLpp(
      CayenneLpp.parseByChannel(body),
    );
    return values.isEmpty ? null : values;
  }
}
