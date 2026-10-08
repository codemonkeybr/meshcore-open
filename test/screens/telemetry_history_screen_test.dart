import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/path_selection.dart';
import 'package:meshcore_open/models/remote_node_stats.dart';
import 'package:meshcore_open/models/telemetry_history.dart';
import 'package:meshcore_open/screens/telemetry_history_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/telemetry_history_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/storage/telemetry_history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeConnector extends MeshCoreConnector {
  final Contact node;
  _FakeConnector(this.node);

  bool connected = true;

  @override
  bool get isConnected => connected;

  @override
  String get selfPublicKeyHex => 'aabbccddeeff00112233';

  @override
  List<Contact> get contacts => [node];

  @override
  List<Contact> get allContactsUnfiltered => [node, _neighborRepeater];

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

  /// Refuses every login, so a refresh ends in the "needs a password" state.
  @override
  Future<void> sendFrame(
    Uint8List data, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {
    if (data[0] == cmdSendLogin) {
      Future.delayed(Duration.zero, () {
        handleFrameForTest([
          pushCodeLoginFail,
          0,
          ...node.publicKey.sublist(0, 6),
        ]);
      });
    }
  }
}

Contact _contact(String name, int type, int seed) => Contact(
  publicKey: Uint8List.fromList(List<int>.generate(32, (i) => seed + i)),
  name: name,
  type: type,
  pathLength: 0,
  path: Uint8List(0),
  lastSeen: DateTime.now(),
);

final Contact _repeater = _contact('Evergreen Repeater', advTypeRepeater, 0x40);
// Its key starts with 0x10 0x11 0x12 0x13, matching a stored neighbor prefix.
final Contact _neighborRepeater = _contact(
  'Hawkwood-Repeater',
  advTypeRepeater,
  0x10,
);

RemoteNodeStats _stats() => const RemoteNodeStats(
  batteryMv: 4100,
  queueLen: 0,
  noiseFloor: -100,
  lastRssi: -50,
  packetsRecv: 1,
  packetsSent: 2,
  txAirSecs: 0,
  uptimeSecs: 0,
  floodTx: 3,
  directTx: 4,
  floodRx: 0,
  directRx: 0,
  errEvents: 0,
  lastSnr: 10,
  directDups: 1,
  floodDups: 2,
);

Widget _app(_FakeConnector connector, TelemetryHistoryService history) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<MeshCoreConnector>.value(value: connector),
      ChangeNotifierProvider<TelemetryHistoryService>.value(value: history),
      ChangeNotifierProvider<AppSettingsService>(
        create: (_) => AppSettingsService(),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TelemetryHistoryScreen(contact: _repeater),
    ),
  );
}

void main() {
  late InMemoryTelemetryHistoryStore store;
  late TelemetryHistoryService history;
  late _FakeConnector connector;

  const device = 'aabbccddee';
  final node = TelemetryHistoryService.keyOf(_repeater.publicKeyHex);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    store = InMemoryTelemetryHistoryStore();
    history = TelemetryHistoryService(store);
    connector = _FakeConnector(_repeater);
  });

  Future<void> seed() async {
    final now = DateTime.now();
    for (var i = 0; i < 6; i++) {
      final at = now.subtract(Duration(days: 5 - i));
      await store.appendLine(
        device,
        node,
        jsonEncode(RadioSample.fromStats(at, _stats()).toJson()),
      );
      await store.appendLine(
        device,
        node,
        jsonEncode(
          SensorSample(time: at, values: {'1/temperature': 18.0 + i}).toJson(),
        ),
      );
    }
    for (var i = 0; i < 3; i++) {
      final at = now.subtract(Duration(days: 4 - i));
      await store.appendLine(
        device,
        node,
        jsonEncode(
          NeighborSample(
            time: at,
            readings: [
              NeighborReading(prefixHex: '10111213', snr: 3.0 + i),
              if (i == 2)
                const NeighborReading(prefixHex: 'deadbeef', snr: -6.75),
            ],
          ).toJson(),
        ),
      );
    }
  }

  testWidgets('shows an empty state with a way to get readings', (
    tester,
  ) async {
    await tester.pumpWidget(_app(connector, history));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    expect(find.text(l10n.history_emptyTitle), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, l10n.history_getReadings),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('shows radio, neighbor and sensor charts for saved data', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await seed();
    await tester.runAsync(() => history.load(device, node));

    await tester.pumpWidget(_app(connector, history));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    expect(find.text(l10n.history_sectionRadio), findsOneWidget);
    expect(find.text(l10n.history_sectionNeighborsCount(2)), findsOneWidget);
    expect(find.text(l10n.history_sectionSensors), findsOneWidget);
    expect(find.text(l10n.history_chartBattery), findsOneWidget);
    expect(find.text(l10n.history_chartSnr), findsOneWidget);
    expect(find.text('Temperature'), findsOneWidget);
    // Named neighbor has a chart, the one with a single reading a number.
    expect(find.text('Hawkwood-Repeater'), findsOneWidget);
    expect(find.text('-6.75 dB'), findsOneWidget);
    expect(find.text(l10n.history_singleReading), findsOneWidget);
    expect(find.text(l10n.history_footer), findsOneWidget);
  });

  testWidgets('the range buttons switch without errors', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await seed();
    await tester.runAsync(() => history.load(device, node));
    await tester.pumpWidget(_app(connector, history));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    for (final label in [
      l10n.history_rangeWeek,
      l10n.history_range3Months,
      l10n.history_rangeAll,
      l10n.history_rangeMonth,
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('refresh is disabled while the radio is disconnected', (
    tester,
  ) async {
    connector.connected = false;
    await tester.pumpWidget(_app(connector, history));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    final refresh = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.refresh),
    );
    expect(refresh.onPressed, isNull);
    expect(refresh.tooltip, l10n.history_refreshNeedsConnection);
  });

  testWidgets('a refused guest login offers to log in', (tester) async {
    await tester.pumpWidget(_app(connector, history));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.refresh));
    // The refresh spinner animates forever, so step time instead of settling.
    // The connector delivers frames on the real event loop, so let that run
    // between pumps.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      if (find.text('Couldn\'t get new readings').evaluate().isNotEmpty) break;
    }

    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    expect(find.text(l10n.history_failTitle), findsOneWidget);
    expect(find.text(l10n.history_failRejectedGuest), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, l10n.history_loginButton),
      findsOneWidget,
    );
  });

  testWidgets('clearing history asks first and then empties the screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await seed();
    await tester.runAsync(() => history.load(device, node));
    await tester.pumpWidget(_app(connector, history));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.history_clear));
    await tester.pumpAndSettle();
    expect(find.text(l10n.history_clearConfirmTitle), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, l10n.history_clear));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.history_emptyTitle), findsOneWidget);
    expect(await store.readLines(device, node), isEmpty);
  });
}
