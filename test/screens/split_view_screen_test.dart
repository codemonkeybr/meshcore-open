import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/helpers/split_view_groups.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/screens/split_view_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/split_view_state.dart';
import 'package:meshcore_open/services/ui_view_state_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

Contact _c(String name, int type, int seed) => Contact(
  publicKey: Uint8List.fromList(List<int>.generate(32, (i) => seed + i)),
  name: name,
  type: type,
  pathLength: 0,
  path: Uint8List(0),
  lastSeen: DateTime.now(),
);

class _FakeConnector extends MeshCoreConnector {
  final List<Contact> people;
  final List<Channel> chans;
  final Map<String, int> unread;
  final Map<int, int> channelUnread;
  _FakeConnector(this.people, this.chans, this.unread, this.channelUnread);

  @override
  bool get isConnected => true;

  @override
  List<Contact> get contacts => people;

  @override
  List<Channel> get channels => chans;

  @override
  int getUnreadCountForContactKey(String key) => unread[key] ?? 0;

  @override
  int getUnreadCountForContact(Contact contact) =>
      unread[contact.publicKeyHex] ?? 0;

  @override
  int getUnreadCountForChannel(Channel channel) =>
      channelUnread[channel.index] ?? 0;

  @override
  int getUnreadCountForChannelIndex(int index) => channelUnread[index] ?? 0;

  @override
  void markChannelRead(int channelIndex) {}

  @override
  void markContactRead(String contactKeyHex) {}
}

Channel _ch(int i, String name) => Channel(
  index: i,
  name: name,
  psk: Uint8List.fromList(List.filled(16, i + 1)),
);

void main() {
  final marta = _c('Marta', advTypeChat, 10);
  final rui = _c('Rui', advTypeChat, 20);
  final repeater = _c('Evergreen Repeater', advTypeRepeater, 30);
  final room = _c('Lounge', advTypeRoom, 40);

  late SplitViewState split;
  late _FakeConnector connector;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    split = SplitViewState(open: {SplitSection.channels});
    connector = _FakeConnector(
      [marta, rui, repeater, room],
      [_ch(0, 'Public'), _ch(1, 'hiking')],
      {marta.publicKeyHex: 2, rui.publicKeyHex: 3, room.publicKeyHex: 4},
      {0: 3, 1: 12},
    );
  });

  Widget app() => MultiProvider(
    providers: [
      ChangeNotifierProvider<MeshCoreConnector>.value(value: connector),
      ChangeNotifierProvider<SplitViewState>.value(value: split),
      ChangeNotifierProvider<AppSettingsService>(
        create: (_) => AppSettingsService(),
      ),
      ChangeNotifierProvider<UiViewStateService>(
        create: (_) => UiViewStateService(),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SplitViewScreen(),
    ),
  );

  Future<void> show(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app());
    await tester.pump();
  }

  testWidgets('open section lists channels, collapsed ones show totals', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('Public'), findsOneWidget);
    expect(find.text('hiking'), findsOneWidget);
    // Companions collapsed: rows hidden, total unread (2 + 3) on the header.
    expect(find.text('Marta'), findsNothing);
    expect(find.text('5'), findsOneWidget);
    // Rooms collapsed with its own unread, repeaters with a plain count.
    expect(find.text('4'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('tapping a header expands it and remembers it', (tester) async {
    await show(tester);
    await tester.tap(find.text('COMPANIONS'));
    await tester.pump();
    expect(find.text('Marta'), findsOneWidget);
    expect(find.text('Rui'), findsOneWidget);
    expect(split.isOpen(SplitSection.companions), isTrue);
  });

  testWidgets('search opens sections with matches only', (tester) async {
    await show(tester);
    await tester.enterText(find.byType(TextField), 'rui');
    await tester.pump();
    expect(find.text('Rui'), findsOneWidget);
    expect(find.text('Public'), findsNothing);
    expect(find.text('Marta'), findsNothing);
    // Sections without a match disappear instead of sitting there empty.
    expect(find.text('CHANNELS'), findsNothing);
    expect(find.text('COMPANIONS'), findsOneWidget);
  });

  testWidgets('shows the empty pane until something is picked', (tester) async {
    await show(tester);
    expect(find.text('Pick something on the left'), findsOneWidget);
  });

  test('selection and open sections live in the shared state', () {
    split.select(SplitSection.channels, channelIndex: 1);
    expect(split.selection?.isChannel(1), isTrue);
    final first = split.selection!.serial;
    split.select(SplitSection.channels, channelIndex: 1);
    expect(split.selection!.serial, greaterThan(first));
    split.toggle(SplitSection.rooms);
    expect(split.isOpen(SplitSection.rooms), isTrue);
    split.clearSelection();
    expect(split.selection, isNull);
  });
}
