import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../l10n/l10n.dart';
import '../models/contact.dart';
import '../services/app_settings_service.dart';
import 'snack_bar_builder.dart';

/// Mutes [contact] by public key and display name. Messages still arrive; they
/// just never notify or play a sound. Shows an Undo snackbar.
Future<void> muteContactWithFeedback(
  BuildContext context,
  Contact contact,
) async {
  final settings = context.read<AppSettingsService>();
  await settings.muteContact(contact.publicKeyHex);
  if (!context.mounted) return;
  showDismissibleSnackBar(
    context,
    content: Text(context.l10n.mute_snackMuted(contact.name)),
    action: SnackBarAction(
      label: context.l10n.block_undo,
      onPressed: () => settings.unmuteContact(contact.publicKeyHex),
    ),
  );
}

/// Unmutes [contact] (key and name) and confirms with a snackbar.
Future<void> unmuteContactWithFeedback(
  BuildContext context,
  Contact contact,
) async {
  final settings = context.read<AppSettingsService>();
  await settings.unmuteContact(contact.publicKeyHex);
  await settings.unmuteName(contact.name);
  if (!context.mounted) return;
  showDismissibleSnackBar(
    context,
    content: Text(context.l10n.mute_snackUnmuted(contact.name)),
  );
}

/// Mutes the sender of a channel message. Channel messages carry only a
/// display name, so the exact name is always muted. When the name belongs to a
/// saved contact their public key is muted too, which also silences their
/// direct messages.
Future<void> muteSenderWithFeedback(
  BuildContext context,
  String senderName,
) async {
  final settings = context.read<AppSettingsService>();
  final connector = context.read<MeshCoreConnector>();
  await settings.muteName(senderName);
  for (final contact in connector.contactsMatchingSenderName(senderName)) {
    await settings.muteContact(contact.publicKeyHex);
  }
  if (!context.mounted) return;
  showDismissibleSnackBar(
    context,
    content: Text(context.l10n.mute_snackMuted(senderName)),
    action: SnackBarAction(
      label: context.l10n.block_undo,
      onPressed: () => unmuteSender(settings, connector, senderName),
    ),
  );
}

/// Clears a muted name together with the keys of contacts that share it, so
/// the sender is not left muted on one path (channel vs direct messages).
Future<void> unmuteSender(
  AppSettingsService settings,
  MeshCoreConnector connector,
  String senderName,
) async {
  await settings.unmuteName(senderName);
  for (final contact in connector.contactsMatchingSenderName(senderName)) {
    await settings.unmuteContact(contact.publicKeyHex);
  }
}

/// Unmutes a channel sender (name and any contact keys) with a snackbar.
Future<void> unmuteSenderWithFeedback(
  BuildContext context,
  String senderName,
) async {
  await unmuteSender(
    context.read<AppSettingsService>(),
    context.read<MeshCoreConnector>(),
    senderName,
  );
  if (!context.mounted) return;
  showDismissibleSnackBar(
    context,
    content: Text(context.l10n.mute_snackUnmuted(senderName)),
  );
}
