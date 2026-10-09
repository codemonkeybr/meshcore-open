import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshcore_open/helpers/split_view_groups.dart';
import 'package:meshcore_open/helpers/split_view_handoff.dart';
import 'package:meshcore_open/services/split_view_state.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for a chat screen: hands itself off once, like the real ones.
class _Chat extends StatefulWidget {
  const _Chat();

  @override
  State<_Chat> createState() => _ChatState();
}

class _ChatState extends State<_Chat> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    if (!_done && shouldHandOffToSplitView(context)) {
      _done = true;
      handOffToSplitView(
        context,
        section: SplitSection.channels,
        channelIndex: 3,
        initialUnread: 2,
      );
    }
    return const Scaffold(body: Text('chat'));
  }
}

void _size(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.reset);
}

void main() {
  late SplitViewState split;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    split = SplitViewState(open: {});
  });

  Widget app() => ChangeNotifierProvider<SplitViewState>.value(
    value: split,
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _Chat()),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  testWidgets('a pushed chat moves into the split view on a wide screen', (
    tester,
  ) async {
    _size(tester, 900);
    await tester.pumpWidget(app());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('chat'), findsNothing);
    expect(split.selection?.isChannel(3), isTrue);
    expect(split.selection?.initialUnread, 2);
  });

  testWidgets('on a narrow screen the chat stays full screen', (tester) async {
    _size(tester, 400);
    await tester.pumpWidget(app());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('chat'), findsOneWidget);
    expect(split.selection, isNull);
  });

  testWidgets('unfolding while the chat is open hands it over', (tester) async {
    _size(tester, 400);
    await tester.pumpWidget(app());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('chat'), findsOneWidget);

    _size(tester, 900);
    await tester.pumpAndSettle();
    expect(find.text('chat'), findsNothing);
    expect(split.selection?.isChannel(3), isTrue);
  });
}
