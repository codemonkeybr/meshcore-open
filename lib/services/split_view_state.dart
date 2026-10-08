import 'package:flutter/foundation.dart';

import '../helpers/split_view_groups.dart';
import '../storage/prefs_manager.dart';

/// What the right pane of the split view shows.
@immutable
class SplitSelection {
  final SplitSection section;
  final int? channelIndex;
  final String? contactKeyHex;

  /// Only for repeaters and rooms, after the login dialog succeeded.
  final String? password;
  final bool isAdmin;

  /// A room opened for management instead of chat.
  final bool manage;
  final int initialUnread;

  /// Changes on every selection, so choosing the same row again reopens it.
  final int serial;

  const SplitSelection({
    required this.section,
    this.channelIndex,
    this.contactKeyHex,
    this.password,
    this.isAdmin = false,
    this.manage = false,
    this.initialUnread = 0,
    this.serial = 0,
  });

  bool isChannel(int index) =>
      section == SplitSection.channels && channelIndex == index;

  bool isContact(String keyHex) => contactKeyHex == keyHex;
}

/// Selection and open sections of the split view. Lives above the screens, so
/// folding or unfolding the phone keeps both.
class SplitViewState extends ChangeNotifier {
  static const _prefsKey = 'split_view_open_sections';

  final Set<SplitSection> _open;
  SplitSelection? _selection;
  int _serial = 0;

  SplitViewState({Set<SplitSection>? open}) : _open = open ?? _loadOpen();

  static Set<SplitSection> _loadOpen() {
    try {
      final stored = PrefsManager.instance.getStringList(_prefsKey);
      if (stored == null) return {SplitSection.channels};
      return {
        for (final name in stored)
          for (final s in SplitSection.values)
            if (s.name == name) s,
      };
    } catch (_) {
      return {SplitSection.channels};
    }
  }

  SplitSelection? get selection => _selection;

  bool isOpen(SplitSection section) => _open.contains(section);

  void toggle(SplitSection section) {
    if (!_open.remove(section)) _open.add(section);
    notifyListeners();
    try {
      PrefsManager.instance.setStringList(
        _prefsKey,
        _open.map((s) => s.name).toList(),
      );
    } catch (_) {}
  }

  void select(
    SplitSection section, {
    int? channelIndex,
    String? contactKeyHex,
    String? password,
    bool isAdmin = false,
    bool manage = false,
    int initialUnread = 0,
  }) {
    _selection = SplitSelection(
      section: section,
      channelIndex: channelIndex,
      contactKeyHex: contactKeyHex,
      password: password,
      isAdmin: isAdmin,
      manage: manage,
      initialUnread: initialUnread,
      serial: ++_serial,
    );
    notifyListeners();
  }

  void clearSelection() {
    if (_selection == null) return;
    _selection = null;
    notifyListeners();
  }
}
