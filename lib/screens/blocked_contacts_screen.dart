import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/block_contact_flow.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../services/app_settings_service.dart';
import '../theme/mesh_theme.dart';
import '../widgets/adaptive_app_bar_title.dart';
import '../widgets/empty_state.dart';
import '../widgets/mesh_ui.dart';

/// Lists every blocked contact with an Unblock action.
class BlockedContactsScreen extends StatelessWidget {
  const BlockedContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AdaptiveAppBarTitle(context.l10n.block_settingsTitle),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: Consumer2<AppSettingsService, MeshCoreConnector>(
          builder: (context, settingsService, connector, _) {
            final settings = settingsService.settings;
            final namesByKey = {
              for (final c in connector.allContactsUnfiltered)
                c.publicKeyHex.toLowerCase(): c.name,
            };
            // One row per blocked contact key, plus one per blocked name that
            // is not already shown as a blocked contact.
            final entries = <_BlockedEntry>[
              for (final keyHex in (settings.blockedContacts.toList()..sort()))
                _BlockedEntry.key(keyHex, namesByKey[keyHex]),
            ];
            final shownNames = {
              for (final e in entries)
                if (e.name != null) e.name!,
            };
            for (final name in (settings.blockedNames.toList()..sort())) {
              if (!shownNames.contains(name)) {
                entries.add(_BlockedEntry.name(name));
              }
            }
            if (entries.isEmpty) {
              return EmptyState(
                icon: Icons.block,
                title: context.l10n.block_settingsEmpty,
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final name = entry.name ?? entry.keyHex!.substring(0, 10);
                final subtitle = entry.keyHex != null
                    ? context.l10n.block_settingsKey(
                        entry.keyHex!.substring(
                          0,
                          entry.keyHex!.length < 10 ? entry.keyHex!.length : 10,
                        ),
                      )
                    : context.l10n.block_settingsByName;
                return MeshCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: MeshPalette.alertBg,
                          border: Border.all(color: MeshPalette.alertLine),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.block,
                          size: 20,
                          color: MeshPalette.alert,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: MeshTheme.mono(
                                fontSize: 11,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          if (entry.keyHex != null) {
                            await settingsService.unblockContact(entry.keyHex!);
                          }
                          if (entry.name != null) {
                            await unblockSender(
                              settingsService,
                              connector,
                              entry.name!,
                            );
                          }
                          if (!context.mounted) return;
                          showDismissibleSnackBar(
                            context,
                            content: Text(
                              context.l10n.block_snackUnblocked(name),
                            ),
                          );
                        },
                        child: Text(context.l10n.block_unblock),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _BlockedEntry {
  final String? keyHex;
  final String? name;

  const _BlockedEntry.key(this.keyHex, this.name);
  const _BlockedEntry.name(this.name) : keyHex = null;
}
