import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/gif_helper.dart';
import '../l10n/l10n.dart';
import '../models/channel.dart';
import '../models/starred_message.dart';
import '../services/starred_messages_service.dart';
import '../theme/mesh_theme.dart';
import '../utils/platform_info.dart';
import '../helpers/snack_bar_builder.dart';
import '../widgets/chat_day_separator.dart';
import '../widgets/empty_state.dart';
import '../widgets/mesh_ui.dart';
import '../widgets/translated_message_content.dart';

/// Messages starred in one channel. Pops with a message id when the user
/// picks "Show in chat".
class StarredMessagesScreen extends StatefulWidget {
  final Channel channel;

  const StarredMessagesScreen({super.key, required this.channel});

  @override
  State<StarredMessagesScreen> createState() => _StarredMessagesScreenState();
}

class _StarredMessagesScreenState extends State<StarredMessagesScreen> {
  bool _newestFirst = true;

  String get _channelName => widget.channel.name.isEmpty
      ? context.l10n.channels_channelIndex(widget.channel.index)
      : widget.channel.name;

  @override
  Widget build(BuildContext context) {
    final device = context.read<MeshCoreConnector>().selfPublicKeyHex;
    final service = context.watch<StarredMessagesService>();
    var items = service.forChannel(device, widget.channel.index);
    if (_newestFirst) items = items.reversed.toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.starred_title,
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              '$_channelName · ${items.length}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          if (items.length > 1)
            IconButton(
              tooltip: context.l10n.starred_reverseOrder,
              icon: const Icon(Icons.swap_vert),
              onPressed: () => setState(() => _newestFirst = !_newestFirst),
            ),
        ],
      ),
      body: items.isEmpty
          ? EmptyState(
              icon: Icons.star_border,
              title: context.l10n.starred_emptyTitle,
              subtitle: context.l10n.starred_emptyBody,
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                final startsDay =
                    i == 0 ||
                    !isSameChatDay(items[i - 1].timestamp, item.timestamp);
                return Column(
                  children: [
                    if (startsDay) ChatDaySeparator(day: item.timestamp),
                    _StarredBubble(
                      item: item,
                      onShow: () => Navigator.pop(context, item.messageId),
                      onActions: () => _showActions(item, device),
                    ),
                  ],
                );
              },
            ),
    );
  }

  void _showActions(StarredMessage item, String device) {
    showMeshSheet(
      context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BottomSheetHeader(
              title: item.text.characters.length > 40
                  ? '${item.text.characters.take(40)}…'
                  : item.text,
              subtitle: item.senderName.isNotEmpty ? item.senderName : null,
            ),
            ListTile(
              leading: const Icon(Icons.forum_outlined),
              title: Text(context.l10n.starred_showInChat),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.pop(context, item.messageId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(context.l10n.common_copy),
              onTap: () {
                Navigator.pop(sheetContext);
                Clipboard.setData(ClipboardData(text: item.text));
                showDismissibleSnackBar(
                  context,
                  content: Text(context.l10n.chat_messageCopied),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_border),
              title: Text(context.l10n.starred_unstar),
              onTap: () {
                Navigator.pop(sheetContext);
                context.read<StarredMessagesService>().remove(
                  device,
                  widget.channel.index,
                  item.messageId,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StarredBubble extends StatelessWidget {
  final StarredMessage item;
  final VoidCallback onShow;
  final VoidCallback onActions;

  const _StarredBubble({
    required this.item,
    required this.onShow,
    required this.onActions,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final out = item.isOutgoing;
    final textColor = out ? MeshPalette.meInk : scheme.onSurface;
    final metaColor = textColor.withValues(alpha: 0.65);
    final isGif = GifHelper.parseGif(item.text) != null;
    final text = isGif ? context.l10n.starred_gif : item.text;

    final bubble = Flexible(
      child: GestureDetector(
        onLongPress: onActions,
        onSecondaryTapUp: PlatformInfo.isDesktop ? (_) => onActions() : null,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.72,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: out ? MeshPalette.me : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(out ? 18 : 6),
              bottomRight: Radius.circular(out ? 6 : 18),
            ),
            border: Border.all(
              color: out ? MeshPalette.meBorder : scheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!out)
                Text(
                  item.senderName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              if (!out) const SizedBox(height: 2),
              TranslatedMessageContent(
                displayText: text,
                style: TextStyle(color: textColor, fontSize: 14),
                highlightMentions: true,
                selfName: context.read<MeshCoreConnector>().selfName,
              ),
              const SizedBox(height: 3),
              RouteChip(isDirect: item.isDirect, hops: item.hops),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatChatTime(context, item.timestamp),
                    style: MeshTheme.mono(fontSize: 12, color: metaColor),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.star_rounded,
                    size: 14,
                    color: MeshPalette.warn,
                  ),
                ],
              ),
              InkWell(
                onTap: onShow,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 2),
                  child: Text(
                    '${context.l10n.starred_showInChat.toUpperCase()} ›',
                    style: MeshTheme.mono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: out ? const Color(0xFF7DD3FC) : MeshPalette.blue,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: out
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!out) ...[
            AvatarCircle(name: item.senderName, size: 32),
            const SizedBox(width: 8),
          ],
          bubble,
        ],
      ),
    );
  }
}
