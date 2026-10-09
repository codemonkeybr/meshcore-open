import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/split_view_state.dart';
import 'split_view_groups.dart';

/// True for a conversation that was pushed as a full screen (it has a screen
/// below it) while the window is wide enough for the split view. That is what
/// happens when the phone is unfolded with a chat open.
bool shouldHandOffToSplitView(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= splitViewMinWidth &&
    Navigator.of(context).canPop();

/// Moves a full-screen conversation into the split view's right pane: selects
/// it there and closes the full-screen copy.
void handOffToSplitView(
  BuildContext context, {
  required SplitSection section,
  int? channelIndex,
  String? contactKeyHex,
  int initialUnread = 0,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    try {
      context.read<SplitViewState>().select(
        section,
        channelIndex: channelIndex,
        contactKeyHex: contactKeyHex,
        initialUnread: initialUnread,
      );
    } catch (_) {
      // No split view in this tree: keep the full-screen chat.
      return;
    }
    Navigator.of(context).pop();
  });
}
