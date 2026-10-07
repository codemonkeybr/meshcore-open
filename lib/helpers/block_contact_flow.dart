import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../l10n/l10n.dart';
import '../models/contact.dart';
import '../services/app_settings_service.dart';
import 'snack_bar_builder.dart';

Future<bool> _confirmBlock(BuildContext context, String name) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.l10n.block_confirmTitle(name)),
      content: Text(dialogContext.l10n.block_confirmBody(name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(dialogContext.l10n.common_cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          child: Text(dialogContext.l10n.block_tag),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Asks for confirmation, then blocks [contact] by public key. Shows an Undo
/// snackbar. Channel messages from the contact are hidden too, because they
/// are matched to the contact by name.
Future<void> confirmAndBlockContact(
  BuildContext context,
  Contact contact,
) async {
  final settings = context.read<AppSettingsService>();
  if (!await _confirmBlock(context, contact.name)) return;
  await settings.blockContact(contact.publicKeyHex);
  if (!context.mounted) return;
  showDismissibleSnackBar(
    context,
    content: Text(context.l10n.block_snackBlocked(contact.name)),
    action: SnackBarAction(
      label: context.l10n.block_undo,
      onPressed: () => settings.unblockContact(contact.publicKeyHex),
    ),
  );
}

/// Blocks the sender of a channel message. Channel messages carry only a
/// display name, so the exact name is always blocked. When the name belongs to
/// a saved contact their public key is blocked too, which also covers their
/// direct messages.
Future<void> confirmAndBlockSender(
  BuildContext context,
  String senderName,
) async {
  final settings = context.read<AppSettingsService>();
  final connector = context.read<MeshCoreConnector>();
  final contacts = connector.contactsMatchingSenderName(senderName);
  if (!await _confirmBlock(context, senderName)) return;
  await settings.blockName(senderName);
  for (final contact in contacts) {
    await settings.blockContact(contact.publicKeyHex);
  }
  if (!context.mounted) return;
  showDismissibleSnackBar(
    context,
    content: Text(context.l10n.block_snackBlocked(senderName)),
    action: SnackBarAction(
      label: context.l10n.block_undo,
      onPressed: () => unblockSender(settings, connector, senderName),
    ),
  );
}

/// Clears a blocked name together with the keys of contacts that share it, so
/// the sender is not left blocked on one path (channel vs direct messages).
Future<void> unblockSender(
  AppSettingsService settings,
  MeshCoreConnector connector,
  String senderName,
) async {
  await settings.unblockName(senderName);
  for (final contact in connector.contactsMatchingSenderName(senderName)) {
    await settings.unblockContact(contact.publicKeyHex);
  }
}

/// Unblocks [contact] (key and name) and confirms with a snackbar.
Future<void> unblockContactWithFeedback(
  BuildContext context,
  Contact contact,
) async {
  final settings = context.read<AppSettingsService>();
  await settings.unblockContact(contact.publicKeyHex);
  await settings.unblockName(contact.name);
  if (!context.mounted) return;
  showDismissibleSnackBar(
    context,
    content: Text(context.l10n.block_snackUnblocked(contact.name)),
  );
}

/// Unblocks a channel sender (name and any contact keys) with a snackbar.
Future<void> unblockSenderWithFeedback(
  BuildContext context,
  String senderName,
) async {
  await unblockSender(
    context.read<AppSettingsService>(),
    context.read<MeshCoreConnector>(),
    senderName,
  );
  if (!context.mounted) return;
  showDismissibleSnackBar(
    context,
    content: Text(context.l10n.block_snackUnblocked(senderName)),
  );
}
