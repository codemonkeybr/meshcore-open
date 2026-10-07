import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/mesh_theme.dart';

/// Small red pill marking a blocked contact.
class BlockedTag extends StatelessWidget {
  const BlockedTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: MeshPalette.alertBg,
        border: Border.all(color: MeshPalette.alertLine),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        context.l10n.block_tag,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: MeshPalette.alert,
        ),
      ),
    );
  }
}
