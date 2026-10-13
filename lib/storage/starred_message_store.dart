import 'dart:convert';

import '../models/starred_message.dart';
import '../utils/app_logger.dart';
import 'prefs_manager.dart';

/// Persists starred messages per radio (first 10 hex chars of its public key)
/// and channel index.
class StarredMessageStore {
  static const String _keyPrefix = 'starred_messages_';

  String _key(String deviceKey, int channelIndex) =>
      '$_keyPrefix${deviceKey}_$channelIndex';

  List<StarredMessage> load(String deviceKey, int channelIndex) {
    final raw = PrefsManager.instance.getString(_key(deviceKey, channelIndex));
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [for (final item in decoded) ?StarredMessage.tryFromJson(item)];
    } catch (e) {
      appLogger.warn('Could not read starred messages: $e');
      return [];
    }
  }

  Future<void> save(
    String deviceKey,
    int channelIndex,
    List<StarredMessage> messages,
  ) async {
    final key = _key(deviceKey, channelIndex);
    final prefs = PrefsManager.instance;
    if (messages.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(
      key,
      jsonEncode([for (final m in messages) m.toJson()]),
    );
  }
}
