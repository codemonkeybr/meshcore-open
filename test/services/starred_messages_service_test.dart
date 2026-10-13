import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/services/starred_messages_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _device = 'aabbccddeeff00112233';

ChannelMessage _msg(String text, int minute, {bool out = false}) =>
    ChannelMessage(
      senderName: out ? 'Me' : 'Zathras',
      text: text,
      timestamp: DateTime(2026, 10, 13, 8, minute),
      isOutgoing: out,
      channelIndex: 1,
      pathLength: 4,
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  test('toggle stars then unstars and notifies', () async {
    final service = StarredMessagesService();
    var notified = 0;
    service.addListener(() => notified++);
    final m = _msg('hello', 1);

    expect(await service.toggle(_device, 1, m), StarResult.starred);
    expect(service.isStarred(_device, 1, m.messageId), isTrue);
    expect(service.count(_device, 1), 1);

    expect(await service.toggle(_device, 1, m), StarResult.unstarred);
    expect(service.isStarred(_device, 1, m.messageId), isFalse);
    expect(notified, 2);
  });

  test('stars are kept per channel and per radio', () async {
    final service = StarredMessagesService();
    final m = _msg('hello', 1);
    await service.toggle(_device, 1, m);

    expect(service.count(_device, 2), 0);
    expect(service.count('00ffeeddccbbaa998877', 1), 0);
  });

  test('stars survive a restart and keep their snapshot', () async {
    final first = StarredMessagesService();
    await first.toggle(_device, 1, _msg('path is 3A', 5));
    await first.toggle(_device, 1, _msg('mine', 6, out: true));

    final second = StarredMessagesService();
    final list = second.forChannel(_device, 1);
    expect(list.map((s) => s.text), ['path is 3A', 'mine']);
    expect(list.first.senderName, 'Zathras');
    expect(list.first.hops, 4);
    expect(list.last.isOutgoing, isTrue);
  });

  test('forChannel is oldest first', () async {
    final service = StarredMessagesService();
    await service.toggle(_device, 1, _msg('late', 30));
    await service.toggle(_device, 1, _msg('early', 2));
    expect(service.forChannel(_device, 1).map((s) => s.text), [
      'early',
      'late',
    ]);
  });

  test('remove deletes one star', () async {
    final service = StarredMessagesService();
    final a = _msg('a', 1);
    await service.toggle(_device, 1, a);
    await service.remove(_device, 1, a.messageId);
    expect(service.count(_device, 1), 0);
    expect(StarredMessagesService().count(_device, 1), 0);
  });

  test('the oldest star is dropped past the limit', () async {
    final service = StarredMessagesService();
    for (var i = 0; i < StarredMessagesService.maxPerChannel; i++) {
      await service.toggle(_device, 1, _msg('m$i', 0).copyWithId('id$i', i));
    }
    final result = await service.toggle(
      _device,
      1,
      _msg('newest', 0).copyWithId('idN', 9999),
    );
    expect(result, StarResult.starredDroppedOldest);
    expect(service.count(_device, 1), StarredMessagesService.maxPerChannel);
    expect(service.isStarred(_device, 1, 'id0'), isFalse);
    expect(service.isStarred(_device, 1, 'idN'), isTrue);
  });

  test('no radio key keeps stars in memory only', () async {
    final service = StarredMessagesService();
    final m = _msg('x', 1);
    await service.toggle('', 1, m);
    expect(service.isStarred('', 1, m.messageId), isTrue);
    expect(StarredMessagesService().count('', 1), 0);
  });
}

extension on ChannelMessage {
  ChannelMessage copyWithId(String id, int minutes) => ChannelMessage(
    senderName: senderName,
    text: text,
    timestamp: DateTime(2026, 1, 1).add(Duration(minutes: minutes)),
    isOutgoing: isOutgoing,
    channelIndex: channelIndex,
    pathLength: pathLength,
    messageId: id,
  );
}
