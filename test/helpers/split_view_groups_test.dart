import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/split_view_groups.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/contact.dart';

Contact _c(
  String name,
  int type, {
  int seed = 1,
  int flags = 0,
  DateTime? seen,
}) => Contact(
  publicKey: Uint8List.fromList(List<int>.generate(32, (i) => seed + i)),
  name: name,
  type: type,
  flags: flags,
  pathLength: 0,
  path: Uint8List(0),
  lastSeen: seen ?? DateTime(2026, 1, 1),
);

Channel _ch(int i, String name) => Channel(
  index: i,
  name: name,
  psk: Uint8List.fromList(List.filled(16, i + 1)),
);

void main() {
  group('splitFilterChannels', () {
    test('drops empty slots and keeps slot order', () {
      final out = splitFilterChannels([
        _ch(2, 'hiking'),
        Channel.empty(1),
        _ch(0, 'Public'),
      ], '');
      expect(out.map((c) => c.index), [0, 2]);
    });

    test('filters by name, ignoring case', () {
      final out = splitFilterChannels([
        _ch(0, 'Public'),
        _ch(1, '#Hiking'),
      ], 'hik');
      expect(out.map((c) => c.index), [1]);
    });

    test('label falls back to the slot number', () {
      expect(
        splitChannelLabel(Channel(index: 3, name: '', psk: Uint8List(16))),
        'Channel 3',
      );
    });
  });

  group('splitFilterContacts', () {
    final now = DateTime(2026, 5, 1);
    final contacts = [
      _c(
        'Old',
        advTypeChat,
        seed: 1,
        seen: now.subtract(const Duration(days: 3)),
      ),
      _c('New', advTypeChat, seed: 2, seen: now),
      _c(
        'Fav',
        advTypeChat,
        seed: 3,
        flags: contactFlagFavorite,
        seen: DateTime(2020),
      ),
      _c('Zed', advTypeRepeater, seed: 4),
      _c('Alpha', advTypeRepeater, seed: 5),
      _c('Lounge', advTypeRoom, seed: 6),
    ];

    test('keeps only the requested type', () {
      final out = splitFilterContacts(
        contacts,
        type: advTypeRoom,
        query: '',
        isBlocked: (_) => false,
      );
      expect(out.map((c) => c.name), ['Lounge']);
    });

    test('favorites first, then most recent', () {
      final out = splitFilterContacts(
        contacts,
        type: advTypeChat,
        query: '',
        isBlocked: (_) => false,
      );
      expect(out.map((c) => c.name), ['Fav', 'New', 'Old']);
    });

    test('repeaters are sorted by name', () {
      final out = splitFilterContacts(
        contacts,
        type: advTypeRepeater,
        query: '',
        isBlocked: (_) => false,
      );
      expect(out.map((c) => c.name), ['Alpha', 'Zed']);
    });

    test('blocked contacts are left out', () {
      final out = splitFilterContacts(
        contacts,
        type: advTypeChat,
        query: '',
        isBlocked: (c) => c.name == 'New',
      );
      expect(out.map((c) => c.name), ['Fav', 'Old']);
    });

    test('search matches the name', () {
      final out = splitFilterContacts(
        contacts,
        type: advTypeChat,
        query: 'ol',
        isBlocked: (_) => false,
      );
      expect(out.map((c) => c.name), ['Old']);
    });
  });

  group('splitUnreadTotal', () {
    test('sums unread and skips muted items', () {
      final counts = {'a': 2, 'b': 5, 'c': 1};
      final total = splitUnreadTotal<String>(
        counts.keys,
        unreadOf: (k) => counts[k]!,
        isMuted: (k) => k == 'b',
      );
      expect(total, 3);
    });
  });

  group('splitSectionExpanded', () {
    test('follows the user when not searching', () {
      expect(
        splitSectionExpanded(userOpen: true, query: '', matches: 0),
        isTrue,
      );
      expect(
        splitSectionExpanded(userOpen: false, query: '  ', matches: 4),
        isFalse,
      );
    });

    test('searching opens sections with matches and closes the rest', () {
      expect(
        splitSectionExpanded(userOpen: false, query: 'x', matches: 2),
        isTrue,
      );
      expect(
        splitSectionExpanded(userOpen: true, query: 'x', matches: 0),
        isFalse,
      );
    });
  });
}
