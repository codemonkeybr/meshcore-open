import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../helpers/block_contact_flow.dart';
import '../helpers/mute_contact_flow.dart';
import '../helpers/split_view_groups.dart';
import '../l10n/l10n.dart';
import '../models/channel.dart';
import '../models/contact.dart';
import '../services/app_settings_service.dart';
import '../services/split_view_state.dart';
import '../theme/mesh_theme.dart';
import '../utils/dialog_utils.dart';
import '../utils/disconnect_navigation_mixin.dart';
import '../widgets/app_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/mesh_ui.dart';
import '../widgets/repeater_login_dialog.dart';
import '../widgets/room_login_dialog.dart';
import '../widgets/sync_progress_overlay.dart';
import '../widgets/unread_badge.dart';
import 'channel_chat_screen.dart';
import 'chat_screen.dart';
import 'discovery_screen.dart';
import 'map_screen.dart';
import 'repeater_hub_screen.dart';
import 'settings_screen.dart';
import 'telemetry_history_screen.dart';

/// True when the window is wide enough for the two-pane layout.
bool isSplitViewWidth(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= splitViewMinWidth;

/// Unfolded layout: an accordion of channels and contacts on the left, the
/// selected conversation or repeater on the right.
class SplitViewScreen extends StatefulWidget {
  const SplitViewScreen({super.key});

  @override
  State<SplitViewScreen> createState() => _SplitViewScreenState();
}

class _SplitViewScreenState extends State<SplitViewScreen>
    with DisconnectNavigationMixin {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connector = context.watch<MeshCoreConnector>();
    if (!checkConnectionAndNavigate(connector)) {
      return const SizedBox.shrink();
    }
    final width = MediaQuery.sizeOf(context).width;
    final sidebarWidth = (width / 3).clamp(240.0, 360.0);
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              SizedBox(
                width: sidebarWidth,
                child: _Sidebar(
                  search: _search,
                  onOpenChannel: _openChannel,
                  onOpenContact: _openContact,
                  onContactMenu: _showContactMenu,
                ),
              ),
              VerticalDivider(width: 1, color: scheme.outlineVariant),
              const Expanded(child: _Pane()),
            ],
          ),
        ),
      ),
    );
  }

  void _openChannel(Channel channel) {
    final connector = context.read<MeshCoreConnector>();
    HapticFeedback.selectionClick();
    final unread = connector.getUnreadCountForChannelIndex(channel.index);
    connector.markChannelRead(channel.index);
    context.read<SplitViewState>().select(
      SplitSection.channels,
      channelIndex: channel.index,
      initialUnread: unread,
    );
  }

  void _openContact(Contact contact, {bool manage = false}) {
    final connector = context.read<MeshCoreConnector>();
    final state = context.read<SplitViewState>();
    HapticFeedback.selectionClick();
    if (contact.type == advTypeRepeater) {
      showDialog(
        context: context,
        builder: (_) => RepeaterLoginDialog(
          repeater: contact,
          onLogin: (password, isAdmin) {
            if (!mounted) return;
            state.select(
              SplitSection.repeaters,
              contactKeyHex: contact.publicKeyHex,
              password: password,
              isAdmin: isAdmin,
            );
          },
        ),
      );
    } else if (contact.type == advTypeRoom) {
      showDialog(
        context: context,
        builder: (_) => RoomLoginDialog(
          room: contact,
          onLogin: (password, isAdmin) {
            if (!mounted) return;
            final unread = connector.getUnreadCountForContactKey(
              contact.publicKeyHex,
            );
            connector.markContactRead(contact.publicKeyHex);
            state.select(
              SplitSection.rooms,
              contactKeyHex: contact.publicKeyHex,
              password: password,
              isAdmin: isAdmin,
              manage: manage,
              initialUnread: unread,
            );
          },
        ),
      );
    } else {
      final unread = connector.getUnreadCountForContactKey(
        contact.publicKeyHex,
      );
      connector.markContactRead(contact.publicKeyHex);
      state.select(
        SplitSection.companions,
        contactKeyHex: contact.publicKeyHex,
        initialUnread: unread,
      );
    }
  }

  void _showContactMenu(Contact contact) {
    final connector = context.read<MeshCoreConnector>();
    final settings = context.read<AppSettingsService>();
    final isRepeater = contact.type == advTypeRepeater;
    final isRoom = contact.type == advTypeRoom;
    final isCompanion = contact.type == advTypeChat;
    final isMuted = settings.isContactMuted(contact.publicKeyHex);
    final isFavorite = contact.isFavorite;

    showMeshSheet(
      context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BottomSheetHeader(title: contact.name),
            if (isRepeater || isRoom)
              ListTile(
                leading: Icon(
                  isRepeater ? Icons.cell_tower : Icons.room_preferences,
                  color: MeshPalette.warn,
                ),
                title: Text(
                  isRepeater
                      ? context.l10n.contacts_manageRepeater
                      : context.l10n.room_management,
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openContact(contact, manage: true);
                },
              ),
            if (isRepeater || isRoom)
              ListTile(
                leading: Icon(Icons.history, color: MeshPalette.blue),
                title: Text(context.l10n.history_contactMenu),
                onTap: () {
                  Navigator.pop(sheetContext);
                  // Saved readings need no login, so show them straight away.
                  context.read<SplitViewState>().select(
                    isRepeater ? SplitSection.repeaters : SplitSection.rooms,
                    contactKeyHex: contact.publicKeyHex,
                    manage: true,
                    isAdmin: false,
                    password: null,
                  );
                },
              ),
            ListTile(
              leading: Icon(
                isFavorite ? Icons.star : Icons.star_border,
                color: MeshPalette.warn,
              ),
              title: Text(
                isFavorite
                    ? context.l10n.listFilter_removeFromFavorites
                    : context.l10n.listFilter_addToFavorites,
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await connector.setContactFlags(
                  contact,
                  isFavorite: !isFavorite,
                );
              },
            ),
            if (isCompanion)
              ListTile(
                leading: Icon(
                  isMuted
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  color: MeshPalette.warn,
                ),
                title: Text(
                  isMuted
                      ? context.l10n.mute_unmuteContact
                      : context.l10n.mute_action,
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (isMuted) {
                    unmuteContactWithFeedback(context, contact);
                  } else {
                    muteContactWithFeedback(context, contact);
                  }
                },
              ),
            if (isCompanion)
              ListTile(
                leading: Icon(
                  Icons.block,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  context.l10n.block_action,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  confirmAndBlockContact(context, contact);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── left pane ─────────────────────────────

class _Sidebar extends StatefulWidget {
  final TextEditingController search;
  final void Function(Channel) onOpenChannel;
  final void Function(Contact) onOpenContact;
  final void Function(Contact) onContactMenu;

  const _Sidebar({
    required this.search,
    required this.onOpenChannel,
    required this.onOpenContact,
    required this.onContactMenu,
  });

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  @override
  Widget build(BuildContext context) {
    final connector = context.watch<MeshCoreConnector>();
    final settings = context.watch<AppSettingsService>();
    final split = context.watch<SplitViewState>();
    final scheme = Theme.of(context).colorScheme;
    final query = widget.search.text;

    bool blocked(Contact c) => settings.isContactBlocked(c.publicKeyHex);
    bool muted(Contact c) => settings.isContactMuted(c.publicKeyHex);
    List<Contact> contactsOf(int type) => splitFilterContacts(
      connector.contacts,
      type: type,
      query: query,
      isBlocked: blocked,
    );

    final channels = splitFilterChannels(connector.channels, query);
    final companions = contactsOf(advTypeChat);
    final repeaters = contactsOf(advTypeRepeater);
    final rooms = contactsOf(advTypeRoom);

    int contactUnread(Contact c) => connector.getUnreadCountForContact(c);
    final channelsUnread = splitUnreadTotal<Channel>(
      channels,
      unreadOf: connector.getUnreadCountForChannel,
      isMuted: (c) => settings.isChannelMuted(
        c.name.isEmpty ? 'Channel ${c.index}' : c.name,
      ),
    );
    final companionsUnread = splitUnreadTotal<Contact>(
      companions,
      unreadOf: contactUnread,
      isMuted: muted,
    );
    final roomsUnread = splitUnreadTotal<Contact>(
      rooms,
      unreadOf: contactUnread,
      isMuted: muted,
    );

    bool open(SplitSection s, int matches) => splitSectionExpanded(
      userOpen: split.isOpen(s),
      query: query,
      matches: matches,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
          child: Row(
            children: [Expanded(child: AppBarTitle(context.l10n.split_title))],
          ),
        ),
        const SyncProgressAppBarBottom(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: context.l10n.split_searchHint,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(widget.search.clear),
                          ),
                  ),
                ),
              ),
              IconButton(
                tooltip: context.l10n.split_menuMap,
                icon: const Icon(Icons.map_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MapScreen()),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: context.l10n.contacts_moreOptions,
                onSelected: (value) {
                  switch (value) {
                    case 'discover':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DiscoveryScreen(),
                        ),
                      );
                    case 'settings':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    case 'disconnect':
                      showDisconnectDialog(context, connector);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'discover',
                    child: Text(context.l10n.split_menuDiscover),
                  ),
                  PopupMenuItem(
                    value: 'settings',
                    child: Text(context.l10n.settings_title),
                  ),
                  PopupMenuItem(
                    value: 'disconnect',
                    child: Text(context.l10n.common_disconnect),
                  ),
                ],
              ),
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: ListView(
            children: [
              if (query.trim().isEmpty || channels.isNotEmpty) ...[
                _SectionHeader(
                  label: context.l10n.split_sectionChannels,
                  expanded: open(SplitSection.channels, channels.length),
                  unread: channelsUnread,
                  total: channels.length,
                  onTap: () => split.toggle(SplitSection.channels),
                ),
                if (open(SplitSection.channels, channels.length))
                  for (final channel in channels)
                    _Row(
                      selected:
                          split.selection?.isChannel(channel.index) ?? false,
                      leading: const Text('#'),
                      label: splitChannelLabel(channel).replaceFirst('#', ''),
                      unread: connector.getUnreadCountForChannel(channel),
                      muted: settings.isChannelMuted(
                        channel.name.isEmpty
                            ? 'Channel ${channel.index}'
                            : channel.name,
                      ),
                      onTap: () => widget.onOpenChannel(channel),
                    ),
              ],
              if (query.trim().isEmpty || companions.isNotEmpty) ...[
                _SectionHeader(
                  label: context.l10n.split_sectionCompanions,
                  expanded: open(SplitSection.companions, companions.length),
                  unread: companionsUnread,
                  total: companions.length,
                  onTap: () => split.toggle(SplitSection.companions),
                ),
                if (open(SplitSection.companions, companions.length))
                  for (final c in companions) _contactRow(c, split, connector),
              ],
              if (query.trim().isEmpty || repeaters.isNotEmpty) ...[
                _SectionHeader(
                  label: context.l10n.split_sectionRepeaters,
                  expanded: open(SplitSection.repeaters, repeaters.length),
                  unread: 0,
                  total: repeaters.length,
                  onTap: () => split.toggle(SplitSection.repeaters),
                ),
                if (open(SplitSection.repeaters, repeaters.length))
                  for (final c in repeaters) _contactRow(c, split, connector),
              ],
              if (query.trim().isEmpty || rooms.isNotEmpty) ...[
                _SectionHeader(
                  label: context.l10n.split_sectionRooms,
                  expanded: open(SplitSection.rooms, rooms.length),
                  unread: roomsUnread,
                  total: rooms.length,
                  onTap: () => split.toggle(SplitSection.rooms),
                ),
                if (open(SplitSection.rooms, rooms.length))
                  for (final c in rooms) _contactRow(c, split, connector),
              ],
              if (query.trim().isNotEmpty &&
                  channels.isEmpty &&
                  companions.isEmpty &&
                  repeaters.isEmpty &&
                  rooms.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text(context.l10n.split_noMatches)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _contactRow(
    Contact contact,
    SplitViewState split,
    MeshCoreConnector connector,
  ) {
    final settings = context.read<AppSettingsService>();
    final icon = switch (contact.type) {
      advTypeRepeater => Icons.cell_tower,
      advTypeRoom => Icons.meeting_room,
      _ => Icons.person,
    };
    return _Row(
      selected: split.selection?.isContact(contact.publicKeyHex) ?? false,
      leading: Icon(icon, size: 16),
      label: contact.name,
      unread: contact.type == advTypeRepeater
          ? 0
          : connector.getUnreadCountForContact(contact),
      muted: settings.isContactMuted(contact.publicKeyHex),
      onTap: () => widget.onOpenContact(contact),
      onLongPress: () => widget.onContactMenu(contact),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final bool expanded;
  final int unread;
  final int total;
  final VoidCallback onTap;

  const _SectionHeader({
    required this.label,
    required this.expanded,
    required this.unread,
    required this.total,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Icon(
                expanded ? Icons.expand_more : Icons.chevron_right,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (unread > 0)
                UnreadBadge(count: unread)
              else
                Text(
                  '$total',
                  style: MeshTheme.mono(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final bool selected;
  final Widget leading;
  final String label;
  final int unread;
  final bool muted;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _Row({
    required this.selected,
    required this.leading,
    required this.label,
    required this.unread,
    required this.muted,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary.withValues(alpha: 0.14) : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 9, 12, 9),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? scheme.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              IconTheme(
                data: IconThemeData(color: scheme.onSurfaceVariant),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: scheme.onSurfaceVariant),
                  child: SizedBox(width: 18, child: Center(child: leading)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: unread > 0 || selected
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
              if (muted)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.notifications_off_outlined,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              if (unread > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: muted
                      ? Text(
                          '$unread',
                          style: MeshTheme.mono(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        )
                      : UnreadBadge(count: unread),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────── right pane ────────────────────────────

/// Shows the selection in a navigator of its own, so anything a screen pushes
/// (path maps, details) stays inside the pane.
class _Pane extends StatefulWidget {
  const _Pane();

  @override
  State<_Pane> createState() => _PaneState();
}

class _PaneState extends State<_Pane> {
  SplitSelection? _shown;
  bool _scheduled = false;
  bool _blank = false;

  @override
  Widget build(BuildContext context) {
    final wanted = context.watch<SplitViewState>().selection;
    if (wanted?.serial != _shown?.serial && !_scheduled) {
      // Take the old conversation down for a frame first: a chat clears the
      // "currently open" marker when it goes away, which must not hit the
      // chat that replaces it.
      _scheduled = true;
      _blank = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _shown = context.read<SplitViewState>().selection;
          _blank = false;
          _scheduled = false;
        });
      });
    }
    if (_blank || _shown == null) {
      return _blank ? const SizedBox.expand() : const _EmptyPane();
    }
    return _PaneNavigator(key: ValueKey(_shown!.serial), selection: _shown!);
  }
}

class _EmptyPane extends StatelessWidget {
  const _EmptyPane();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.forum_outlined,
      title: context.l10n.split_emptyTitle,
      subtitle: context.l10n.split_emptyBody,
    );
  }
}

class _PaneNavigator extends StatefulWidget {
  final SplitSelection selection;

  const _PaneNavigator({super.key, required this.selection});

  @override
  State<_PaneNavigator> createState() => _PaneNavigatorState();
}

class _PaneNavigatorState extends State<_PaneNavigator> {
  final GlobalKey<NavigatorState> _key = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return NavigatorPopHandler(
      onPopWithResult: (_) => _key.currentState?.maybePop(),
      child: Navigator(
        key: _key,
        onGenerateRoute: (_) => MaterialPageRoute(
          builder: (_) => _content(context, widget.selection),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, SplitSelection s) {
    final connector = context.read<MeshCoreConnector>();
    if (s.section == SplitSection.channels) {
      final channel = connector.channels
          .where((c) => c.index == s.channelIndex)
          .firstOrNull;
      if (channel == null) return const _EmptyPane();
      return ChannelChatScreen(
        channel: channel,
        initialUnreadCount: s.initialUnread,
      );
    }
    final contact = connector.getContactByPubKeyHex(s.contactKeyHex ?? '');
    if (contact == null) return const _EmptyPane();
    if (contact.type == advTypeRepeater || s.manage) {
      // Saved history needs no login: with no password, open the history.
      if (s.password == null) {
        return TelemetryHistoryScreen(contact: contact);
      }
      return RepeaterHubScreen(
        repeater: contact,
        password: s.password!,
        isAdmin: s.isAdmin,
      );
    }
    return ChatScreen(contact: contact, initialUnreadCount: s.initialUnread);
  }
}
