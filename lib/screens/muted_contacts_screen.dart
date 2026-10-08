import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/mute_contact_flow.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../services/app_settings_service.dart';
import '../theme/mesh_theme.dart';
import '../widgets/adaptive_app_bar_title.dart';
import '../widgets/empty_state.dart';
import '../widgets/mesh_ui.dart';

/// Lists every muted contact with an Unmute action.
class MutedContactsScreen extends StatelessWidget {
  const MutedContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AdaptiveAppBarTitle(context.l10n.mute_settingsTitle),
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
            // One row per muted contact key, plus one per muted name that
            // is not already shown as a muted contact.
            final entries = <_MutedEntry>[
              for (final keyHex in (settings.mutedContacts.toList()..sort()))
                _MutedEntry.key(keyHex, namesByKey[keyHex]),
            ];
            final shownNames = {
              for (final e in entries)
                if (e.name != null) e.name!,
            };
            for (final name in (settings.mutedNames.toList()..sort())) {
              if (!shownNames.contains(name)) {
                entries.add(_MutedEntry.name(name));
              }
            }
            if (entries.isEmpty) {
              return EmptyState(
                icon: Icons.notifications_off_outlined,
                title: context.l10n.mute_settingsEmpty,
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
                    : context.l10n.mute_settingsByName;
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
                          color: MeshPalette.warnBg,
                          border: Border.all(color: MeshPalette.warnLine),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.notifications_off_outlined,
                          size: 20,
                          color: MeshPalette.warn,
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
                            await settingsService.unmuteContact(entry.keyHex!);
                          }
                          if (entry.name != null) {
                            await unmuteSender(
                              settingsService,
                              connector,
                              entry.name!,
                            );
                          }
                          if (!context.mounted) return;
                          showDismissibleSnackBar(
                            context,
                            content: Text(context.l10n.mute_snackUnmuted(name)),
                          );
                        },
                        child: Text(context.l10n.mute_unmute),
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

class _MutedEntry {
  final String? keyHex;
  final String? name;

  const _MutedEntry.key(this.keyHex, this.name);
  const _MutedEntry.name(this.name) : keyHex = null;
}
