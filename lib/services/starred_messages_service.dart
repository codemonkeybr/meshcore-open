import 'package:flutter/foundation.dart';

import '../models/channel_message.dart';
import '../models/starred_message.dart';
import '../storage/starred_message_store.dart';

enum StarResult { starred, unstarred, starredDroppedOldest }

/// Starred channel messages, private to this phone.
///
/// Callers pass the connected radio's public key hex; only the first 10 chars
/// are used so stars stay with the radio they were made on.
class StarredMessagesService extends ChangeNotifier {
  static const int maxPerChannel = 200;

  final StarredMessageStore _store;
  final Map<String, List<StarredMessage>> _cache = {};

  StarredMessagesService({StarredMessageStore? store})
    : _store = store ?? StarredMessageStore();

  static String deviceKey(String publicKeyHex) =>
      publicKeyHex.length > 10 ? publicKeyHex.substring(0, 10) : '';

  List<StarredMessage> _list(String device, int channelIndex) {
    final key = '${deviceKey(device)}_$channelIndex';
    return _cache.putIfAbsent(
      key,
      () => deviceKey(device).isEmpty
          ? []
          : _store.load(deviceKey(device), channelIndex),
    );
  }

  /// Starred messages of a channel, oldest first.
  List<StarredMessage> forChannel(String device, int channelIndex) {
    final list = [..._list(device, channelIndex)]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return list;
  }

  int count(String device, int channelIndex) =>
      _list(device, channelIndex).length;

  bool isStarred(String device, int channelIndex, String messageId) =>
      _list(device, channelIndex).any((m) => m.messageId == messageId);

  Future<StarResult> toggle(
    String device,
    int channelIndex,
    ChannelMessage message,
  ) async {
    final list = _list(device, channelIndex);
    final existing = list.indexWhere((m) => m.messageId == message.messageId);
    if (existing >= 0) {
      list.removeAt(existing);
      await _persist(device, channelIndex);
      return StarResult.unstarred;
    }
    list.add(StarredMessage.fromMessage(message));
    var dropped = false;
    if (list.length > maxPerChannel) {
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      list.removeAt(0);
      dropped = true;
    }
    await _persist(device, channelIndex);
    return dropped ? StarResult.starredDroppedOldest : StarResult.starred;
  }

  Future<void> remove(String device, int channelIndex, String messageId) async {
    final list = _list(device, channelIndex);
    final before = list.length;
    list.removeWhere((m) => m.messageId == messageId);
    if (list.length != before) await _persist(device, channelIndex);
  }

  Future<void> _persist(String device, int channelIndex) async {
    notifyListeners();
    final key = deviceKey(device);
    if (key.isEmpty) return;
    await _store.save(key, channelIndex, _list(device, channelIndex));
  }
}
