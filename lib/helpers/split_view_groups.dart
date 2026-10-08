import '../connector/meshcore_protocol.dart';
import '../models/channel.dart';
import '../models/contact.dart';

/// The four accordion sections of the unfolded split view.
enum SplitSection { channels, companions, repeaters, rooms }

/// Window width from which the app shows the two-pane layout.
const double splitViewMinWidth = 600;

/// Name shown for a channel, matching the Channels screen fallback.
String splitChannelLabel(Channel channel) =>
    channel.name.isEmpty ? 'Channel ${channel.index}' : channel.name.trim();

/// Channels that hold a real channel (empty slots are left out) and match
/// [query], in slot order.
List<Channel> splitFilterChannels(List<Channel> channels, String query) {
  final q = query.trim().toLowerCase();
  final out = channels.where((c) => !c.isEmpty).where((c) {
    if (q.isEmpty) return true;
    return splitChannelLabel(c).toLowerCase().contains(q);
  }).toList();
  out.sort((a, b) => a.index.compareTo(b.index));
  return out;
}

/// Contacts of one advert type that match [query] and are not blocked.
///
/// Favorites come first, then the most recent activity. Repeaters and rooms
/// are listed by name because they have no conversation to be recent in.
List<Contact> splitFilterContacts(
  List<Contact> contacts, {
  required int type,
  required String query,
  required bool Function(Contact) isBlocked,
}) {
  final q = query.trim().toLowerCase();
  final out = contacts.where((c) => c.type == type && !isBlocked(c)).where((c) {
    if (q.isEmpty) return true;
    return c.name.toLowerCase().contains(q) ||
        c.publicKeyHex.toLowerCase().startsWith(q);
  }).toList();
  final byName = type == advTypeRepeater;
  out.sort((a, b) {
    if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
    if (byName) return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    final aAt = a.lastMessageAt.isAfter(a.lastSeen)
        ? a.lastMessageAt
        : a.lastSeen;
    final bAt = b.lastMessageAt.isAfter(b.lastSeen)
        ? b.lastMessageAt
        : b.lastSeen;
    final cmp = bAt.compareTo(aAt);
    return cmp != 0
        ? cmp
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return out;
}

/// Sum of [unreadOf] over [items], leaving out the ones [isMuted] flags.
int splitUnreadTotal<T>(
  Iterable<T> items, {
  required int Function(T) unreadOf,
  required bool Function(T) isMuted,
}) {
  var total = 0;
  for (final item in items) {
    if (isMuted(item)) continue;
    total += unreadOf(item);
  }
  return total;
}

/// Sections that should be drawn open: the ones the user opened, plus every
/// section with a match while searching.
bool splitSectionExpanded({
  required bool userOpen,
  required String query,
  required int matches,
}) {
  if (query.trim().isNotEmpty) return matches > 0;
  return userOpen;
}
