import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/l10n.dart';
import '../utils/platform_info.dart';
import '../helpers/snack_bar_builder.dart';
import 'mention_text.dart';

class LinkHandler {
  static TextStyle defaultLinkStyle(BuildContext context, TextStyle base) {
    final brightness = Theme.of(context).brightness;
    final orange = brightness == Brightness.dark
        ? const Color(0xFFFFB74D)
        : const Color(0xFFE65100);
    return base.copyWith(color: orange, decoration: TextDecoration.underline);
  }

  /// Returns a [SelectableLinkify] on desktop or a [Linkify] on mobile.
  static Widget buildLinkifyText({
    required BuildContext context,
    required String text,
    required TextStyle style,
    TextStyle? linkStyle,
    VoidCallback? onSecondaryTap,
    bool highlightMentions = false,
    String? selfName,
  }) {
    if (highlightMentions && text.contains('@[')) {
      return _buildMentionText(
        context: context,
        text: text,
        style: style,
        linkStyle: linkStyle,
        onSecondaryTap: onSecondaryTap,
        selfName: selfName,
      );
    }
    final effectiveLinkStyle = linkStyle ?? defaultLinkStyle(context, style);
    const options = LinkifyOptions(humanize: false, defaultToHttps: false);
    const linkifiers = [UrlLinkifier(), EmailLinkifier()];
    void onOpen(LinkableElement link) => handleLinkTap(context, link.url);

    if (PlatformInfo.isDesktop) {
      final linkify = SelectableLinkify(
        text: text,
        style: style,
        linkStyle: effectiveLinkStyle,
        options: options,
        linkifiers: linkifiers,
        onOpen: onOpen,
      );
      if (onSecondaryTap == null) return linkify;
      return Listener(
        onPointerDown: (event) {
          if (event.buttons & kSecondaryMouseButton != 0) onSecondaryTap();
        },
        behavior: HitTestBehavior.translucent,
        child: linkify,
      );
    }
    return Linkify(
      text: text,
      style: style,
      linkStyle: effectiveLinkStyle,
      options: options,
      linkifiers: linkifiers,
      onOpen: onOpen,
    );
  }

  /// Like [buildLinkifyText] but also styles `@[Name]` mentions as chips;
  /// one naming [selfName] is amber.
  static Widget _buildMentionText({
    required BuildContext context,
    required String text,
    required TextStyle style,
    required String? selfName,
    TextStyle? linkStyle,
    VoidCallback? onSecondaryTap,
  }) {
    final effectiveLinkStyle = linkStyle ?? defaultLinkStyle(context, style);
    const options = LinkifyOptions(humanize: false, defaultToHttps: false);
    var elements = <LinkifyElement>[TextElement(text)];
    for (final linkifier in const [UrlLinkifier(), EmailLinkifier()]) {
      elements = linkifier.parse(elements, options);
    }
    final linked = buildTextSpan(
      elements,
      style: style,
      linkStyle: effectiveLinkStyle,
      onOpen: (link) => handleLinkTap(context, link.url),
    );
    final base = style.color ?? Theme.of(context).colorScheme.onSurface;
    final me = selfName?.trim().toLowerCase();
    final children = <InlineSpan>[];
    for (final child in linked.children ?? const <InlineSpan>[]) {
      if (child is TextSpan && child.recognizer == null && child.text != null) {
        for (final piece in splitMentions(child.text!)) {
          if (!piece.isMention) {
            children.add(TextSpan(text: piece.text, style: child.style));
            continue;
          }
          final isMe = piece.name!.trim().toLowerCase() == me;
          children.add(
            TextSpan(
              text: piece.text,
              style: (child.style ?? style).copyWith(
                fontWeight: FontWeight.w600,
                color: isMe ? const Color(0xFF5C4300) : base,
                backgroundColor: isMe
                    ? const Color(0xFFFFE08A)
                    : base.withValues(alpha: 0.14),
              ),
            ),
          );
        }
      } else {
        children.add(child);
      }
    }
    final span = TextSpan(style: style, children: children);
    if (PlatformInfo.isDesktop) {
      final selectable = SelectableText.rich(span);
      if (onSecondaryTap == null) return selectable;
      return Listener(
        onPointerDown: (event) {
          if (event.buttons & kSecondaryMouseButton != 0) onSecondaryTap();
        },
        behavior: HitTestBehavior.translucent,
        child: selectable,
      );
    }
    return Text.rich(span);
  }

  static Future<void> handleLinkTap(BuildContext context, String url) async {
    // Show confirmation dialog
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.chat_openLink),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.chat_openLinkConfirmation,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                url,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.chat_open),
          ),
        ],
      ),
    );

    if (shouldOpen != true) return;

    // Launch URL
    try {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (context.mounted) {
          showDismissibleSnackBar(
            context,
            content: Text(context.l10n.chat_couldNotOpenLink(url)),
            backgroundColor: Colors.red,
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.chat_invalidLink),
          backgroundColor: Colors.red,
        );
      }
    }
  }
}
