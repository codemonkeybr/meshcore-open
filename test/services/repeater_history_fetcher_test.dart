import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/path_selection.dart';
import 'package:meshcore_open/services/repeater_history_fetcher.dart';
import 'package:meshcore_open/services/storage_service.dart';
import 'package:meshcore_open/services/telemetry_history_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/storage/telemetry_history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A connector whose "radio" answers each request from a script, so the whole
/// login-then-fetch conversation runs without hardware.
class _ScriptedConnector extends MeshCoreConnector {
  final Contact node;
  _ScriptedConnector(this.node);

  bool connected = true;
  bool answerLogin = true;
  bool acceptLogin = true;
  bool answerStatus = true;
  bool answerNeighbors = true;
  bool answerTelemetry = true;
  final List<String> loginPasswords = [];
  int nextTag = 1;

  @override
  bool get isConnected => connected;

  @override
  String get selfPublicKeyHex => 'aabbccddeeff00112233';

  @override
  List<Contact> get contacts => [node];

  @override
  Future<PathSelection> preparePathForContactSend(Contact contact) async =>
      const PathSelection(pathBytes: [], hopCount: 0, useFlood: false);

  @override
  int calculateTimeout({
    required int pathLength,
    int messageBytes = 100,
    String? contactKey,
    int? deviceTimeoutMs,
  }) => 60;

  @override
  void recordRepeaterPathResult(
    Contact contact,
    PathSelection selection,
    bool success,
    int? tripTimeMs,
  ) {}

  @override
  Future<void> sendFrame(
    Uint8List data, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {
    Future.delayed(Duration.zero, () => _reply(data));
  }

  void _reply(Uint8List data) {
    final prefix = node.publicKey.sublist(0, 6);
    switch (data[0]) {
      case cmdSendLogin:
        final end = data.lastIndexOf(0);
        loginPasswords.add(utf8.decode(data.sublist(33, end)));
        if (!answerLogin) return;
        handleFrameForTest([
          acceptLogin ? pushCodeLoginSuccess : pushCodeLoginFail,
          1,
          ...prefix,
        ]);
      case cmdSendStatusReq:
        if (!answerStatus) return;
        handleFrameForTest(_statusFrame(prefix));
      case cmdSendBinaryReq:
        final type = data[33];
        final Uint8List? body;
        if (type == reqTypeGetNeighbors) {
          body = answerNeighbors ? _neighborsBody() : null;
        } else {
          body = answerTelemetry ? _telemetryBody() : null;
        }
        if (body == null) return;
        final tag = [nextTag++, 0, 0, 0];
        handleFrameForTest([respCodeSent, 0, ...tag, 0, 0, 0, 0]);
        handleFrameForTest([pushCodeBinaryResponse, 0, ...tag, ...body]);
    }
  }

  static Uint8List _statusFrame(Uint8List prefix) {
    final payload = ByteData(56);
    payload.setUint16(0, 4150, Endian.little); // battery mV
    payload.setInt16(4, -101, Endian.little); // noise floor
    payload.setInt16(6, -47, Endian.little); // last RSSI
    payload.setUint32(24, 30, Endian.little); // flood tx
    payload.setUint32(28, 12, Endian.little); // direct tx
    payload.setInt16(42, 52, Endian.little); // SNR 13.0 (x4)
    payload.setUint16(44, 3, Endian.little); // direct dups
    payload.setUint16(46, 9, Endian.little); // flood dups
    payload.setUint32(52, 7, Endian.little); // receive errors
    return Uint8List.fromList([
      pushCodeStatusResponse,
      0,
      ...prefix,
      ...payload.buffer.asUint8List(),
    ]);
  }

  static Uint8List _neighborsBody() {
    Uint8List neighbor(int a, int snrQ4) {
      final d = ByteData(9);
      for (var i = 0; i < 4; i++) {
        d.setUint8(i, a + i);
      }
      d.setUint32(4, 120, Endian.little);
      d.setInt8(8, snrQ4);
      return d.buffer.asUint8List();
    }

    return Uint8List.fromList([
      2, 0, // total
      2, 0, // in this page
      ...neighbor(0x10, 24), // 6.0 dB
      ...neighbor(0x20, -27), // -6.75 dB
    ]);
  }

  static Uint8List _telemetryBody() => Uint8List.fromList([
    1, 103, 0x00, 0xD7, // channel 1 temperature 21.5
    1, 116, 0x01, 0x9C, // channel 1 voltage 4.12
  ]);
}

Contact _node(int type) => Contact(
  publicKey: Uint8List.fromList(List<int>.generate(32, (i) => 0x40 + i)),
  name: 'Evergreen',
  type: type,
  pathLength: 0,
  path: Uint8List(0),
  lastSeen: DateTime.now(),
);

void main() {
  late TelemetryHistoryService history;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    history = TelemetryHistoryService(InMemoryTelemetryHistoryStore());
  });

  RepeaterHistoryFetcher fetcherFor(_ScriptedConnector c) =>
      RepeaterHistoryFetcher(
        connector: c,
        history: history,
        loginAttempts: 1,
        loginReplyGrace: Duration.zero,
      );

  const deviceKey = 'aabbccddee';

  test(
    'with a saved password it logs in with it and records everything',
    () async {
      final node = _node(advTypeRepeater);
      await StorageService().saveRepeaterPassword(node.publicKeyHex, 'hunter2');
      final connector = _ScriptedConnector(node);

      final result = await fetcherFor(connector).fetch(node);

      expect(result.succeeded, isTrue);
      expect(result.usedSavedPassword, isTrue);
      expect(connector.loginPasswords, ['hunter2']);
      final saved = history.cached(
        deviceKey,
        TelemetryHistoryService.keyOf(node.publicKeyHex),
      );
      expect(saved.radio, hasLength(1));
      expect(saved.radio.single.batteryMv, 4150);
      expect(saved.radio.single.snr, 13.0);
      expect(saved.radio.single.rssi, -47);
      expect(saved.radio.single.errors, 7);
      expect(saved.neighbors.single.readings, hasLength(2));
      expect(saved.neighbors.single.readings.last.snr, -6.75);
      expect(saved.sensors.single.values['1/temperature'], 21.5);
      expect(saved.sensors.single.values['1/voltage'], 4.12);
    },
  );

  test('without a saved password it tries a guest login', () async {
    final node = _node(advTypeRepeater);
    final connector = _ScriptedConnector(node);

    final result = await fetcherFor(connector).fetch(node);

    expect(result.succeeded, isTrue);
    expect(result.usedSavedPassword, isFalse);
    expect(connector.loginPasswords, ['']);
  });

  test('a refused guest login stops the fetch and saves nothing', () async {
    final node = _node(advTypeRepeater);
    final connector = _ScriptedConnector(node)..acceptLogin = false;

    final result = await fetcherFor(connector).fetch(node);

    expect(result.failure, HistoryFetchFailure.loginRejected);
    expect(result.usedSavedPassword, isFalse);
    expect(
      history
          .cached(deviceKey, TelemetryHistoryService.keyOf(node.publicKeyHex))
          .isEmpty,
      isTrue,
    );
  });

  test('a refused saved password is reported as such', () async {
    final node = _node(advTypeRepeater);
    await StorageService().saveRepeaterPassword(node.publicKeyHex, 'old');
    final connector = _ScriptedConnector(node)..acceptLogin = false;

    final result = await fetcherFor(connector).fetch(node);

    expect(result.failure, HistoryFetchFailure.loginRejected);
    expect(result.usedSavedPassword, isTrue);
  });

  test(
    'a repeater that never answers the login is a no-answer failure',
    () async {
      final node = _node(advTypeRepeater);
      final connector = _ScriptedConnector(node)..answerLogin = false;

      final result = await fetcherFor(connector).fetch(node);

      expect(result.failure, HistoryFetchFailure.noAnswer);
    },
  );

  test('one part failing keeps the others', () async {
    final node = _node(advTypeRepeater);
    final connector = _ScriptedConnector(node)..answerNeighbors = false;

    final result = await fetcherFor(connector).fetch(node);

    expect(result.succeeded, isTrue);
    expect(result.steps[HistoryFetchStep.neighbors], HistoryStepState.failed);
    expect(result.steps[HistoryFetchStep.radio], HistoryStepState.done);
    final saved = history.cached(
      deviceKey,
      TelemetryHistoryService.keyOf(node.publicKeyHex),
    );
    expect(saved.radio, hasLength(1));
    expect(saved.neighbors, isEmpty);
    expect(saved.sensors, hasLength(1));
  });

  test('nothing answering after login is a no-answer failure', () async {
    final node = _node(advTypeRepeater);
    final connector = _ScriptedConnector(node)
      ..answerStatus = false
      ..answerNeighbors = false
      ..answerTelemetry = false;

    final result = await fetcherFor(connector).fetch(node);

    expect(result.failure, HistoryFetchFailure.noAnswer);
  });

  test('rooms skip neighbors', () async {
    final node = _node(advTypeRoom);
    final connector = _ScriptedConnector(node);

    final result = await fetcherFor(connector).fetch(node);

    expect(result.succeeded, isTrue);
    expect(result.steps.containsKey(HistoryFetchStep.neighbors), isFalse);
    final saved = history.cached(
      deviceKey,
      TelemetryHistoryService.keyOf(node.publicKeyHex),
    );
    expect(saved.neighbors, isEmpty);
    expect(saved.radio, hasLength(1));
  });

  test('refusing to run while the radio is disconnected', () async {
    final node = _node(advTypeRepeater);
    final connector = _ScriptedConnector(node)..connected = false;

    final result = await fetcherFor(connector).fetch(node);

    expect(result.failure, HistoryFetchFailure.notConnected);
    expect(connector.loginPasswords, isEmpty);
  });

  test('an explicit refresh always saves, even right after another', () async {
    final node = _node(advTypeRepeater);
    final connector = _ScriptedConnector(node);

    await fetcherFor(connector).fetch(node);
    await fetcherFor(connector).fetch(node);

    final saved = history.cached(
      deviceKey,
      TelemetryHistoryService.keyOf(node.publicKeyHex),
    );
    expect(saved.radio, hasLength(2));
    expect(saved.neighbors, hasLength(2));
    expect(saved.sensors, hasLength(2));
  });

  test('a password passed in is used instead of the saved one', () async {
    final node = _node(advTypeRepeater);
    await StorageService().saveRepeaterPassword(node.publicKeyHex, 'saved');
    final connector = _ScriptedConnector(node);

    await fetcherFor(connector).fetch(node, password: 'typed');

    expect(connector.loginPasswords, ['typed']);
  });
}
