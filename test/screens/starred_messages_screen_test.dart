import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/screens/starred_messages_screen.dart';
import 'package:meshcore_open/services/starred_messages_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _device = 'aabbccddeeff00112233';

class _FakeConnector extends MeshCoreConnector {
  @override
  String get selfPublicKeyHex => _device;
}

ChannelMessage _msg(String id, String text, int minute) => ChannelMessage(
  senderName: 'Zathras',
  text: text,
  timestamp: DateTime(2026, 10, 13, 8, minute),
  isOutgoing: false,
  channelIndex: 1,
  pathLength: 4,
  messageId: id,
);

Future<String?> _pump(
  WidgetTester tester,
  StarredMessagesService service,
) async {
  String? popped;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<MeshCoreConnector>(
          create: (_) => _FakeConnector(),
        ),
        ChangeNotifierProvider<StarredMessagesService>.value(value: service),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => StarredMessagesScreen(
                      channel: Channel(
                        index: 1,
                        name: '#test',
                        psk: Uint8List(16),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return popped;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  testWidgets('shows an empty state with no stars', (tester) async {
    await _pump(tester, StarredMessagesService());
    expect(find.text('No starred messages'), findsOneWidget);
  });

  testWidgets('lists stars newest first and can reverse the order', (
    tester,
  ) async {
    final service = StarredMessagesService();
    await service.toggle(_device, 1, _msg('a', 'older one', 10));
    await service.toggle(_device, 1, _msg('b', 'newer one', 40));
    await _pump(tester, service);

    expect(find.text('#test · 2'), findsOneWidget);
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(y('newer one'), lessThan(y('older one')));

    await tester.tap(find.byIcon(Icons.swap_vert));
    await tester.pump();
    expect(y('older one'), lessThan(y('newer one')));
  });

  testWidgets('Show in chat pops with the message id', (tester) async {
    final service = StarredMessagesService();
    await service.toggle(_device, 1, _msg('a', 'only one', 10));
    String? result;
    await tester.pumpWidget(const SizedBox());
    // Re-pump with a captured result.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MeshCoreConnector>(
            create: (_) => _FakeConnector(),
          ),
          ChangeNotifierProvider<StarredMessagesService>.value(value: service),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => StarredMessagesScreen(
                      channel: Channel(
                        index: 1,
                        name: '#test',
                        psk: Uint8List(16),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('SHOW IN CHAT'));
    await tester.pumpAndSettle();
    expect(result, 'a');
  });

  testWidgets('long-press then Remove star removes the entry', (tester) async {
    final service = StarredMessagesService();
    await service.toggle(_device, 1, _msg('a', 'remove me', 10));
    await _pump(tester, service);

    await tester.longPress(find.text('Zathras'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove star'));
    await tester.pumpAndSettle();

    expect(service.count(_device, 1), 0);
    expect(find.text('No starred messages'), findsOneWidget);
  });
}
