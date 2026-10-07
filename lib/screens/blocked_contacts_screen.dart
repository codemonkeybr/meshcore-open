import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
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
            final blocked = settingsService.settings.blockedContacts.toList()
              ..sort();
            if (blocked.isEmpty) {
              return EmptyState(
                icon: Icons.block,
                title: context.l10n.block_settingsEmpty,
              );
            }
            final namesByKey = {
              for (final c in connector.allContactsUnfiltered)
                c.publicKeyHex.toLowerCase(): c.name,
            };
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
              itemCount: blocked.length,
              itemBuilder: (context, index) {
                final keyHex = blocked[index];
                final name = namesByKey[keyHex] ?? keyHex.substring(0, 10);
                final prefix = keyHex.substring(
                  0,
                  keyHex.length < 10 ? keyHex.length : 10,
                );
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
                              context.l10n.block_settingsKey(prefix),
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
                          await settingsService.unblockContact(keyHex);
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
