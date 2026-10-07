import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/contact.dart';
import '../services/app_settings_service.dart';
import 'snack_bar_builder.dart';

/// Asks for confirmation, then blocks [contact]. Shows an Undo snackbar.
Future<void> confirmAndBlockContact(
  BuildContext context,
  Contact contact,
) async {
  final settings = context.read<AppSettingsService>();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.l10n.block_confirmTitle(contact.name)),
      content: Text(dialogContext.l10n.block_confirmBody(contact.name)),
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
  if (confirmed != true) return;
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

/// Unblocks [contact] and confirms with a snackbar.
Future<void> unblockContactWithFeedback(
  BuildContext context,
  Contact contact,
) async {
  await context.read<AppSettingsService>().unblockContact(contact.publicKeyHex);
  if (!context.mounted) return;
  showDismissibleSnackBar(
    context,
    content: Text(context.l10n.block_snackUnblocked(contact.name)),
  );
}
