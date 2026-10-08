import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Builds the one-tap "ack" reply for a received message: who it answers,
/// how strongly it was heard and how it got here. The text is sent to other
/// people over the mesh, so it is fixed English like the rest of the mesh
/// traffic, not localized.
///
/// Channel: `@[Name], ack: SNR 14.0 dB, RSSI -48 dBm, 2 hops via 3A, F1`
/// Direct:  `Ack: SNR 6.5 dB`
///
/// Unknown values are left out. [hops] below zero means direct-routed.
String buildAckText({
  String? senderName,
  double? snr,
  int? rssi,
  int? hops,
  Uint8List? pathBytes,
  int hashWidth = 1,
}) {
  final prefix = (senderName != null && senderName.isNotEmpty)
      ? '@[$senderName], ack'
      : 'Ack';

  final parts = <String>[];
  if (snr != null) parts.add('SNR ${snr.toStringAsFixed(1)} dB');
  if (rssi != null) parts.add('RSSI $rssi dBm');
  if (hops != null) {
    if (hops < 0) {
      parts.add('direct');
    } else {
      var hopText = '$hops hop${hops == 1 ? '' : 's'}';
      final codes = _hopCodes(pathBytes, hops, hashWidth);
      if (codes.isNotEmpty) hopText += ' via ${codes.join(', ')}';
      parts.add(hopText);
    }
  }

  return parts.isEmpty ? prefix : '$prefix: ${parts.join(', ')}';
}

const int _maxListedHops = 8;

List<String> _hopCodes(Uint8List? pathBytes, int hops, int hashWidth) {
  if (pathBytes == null || pathBytes.isEmpty || hops <= 0) return const [];
  final width = hashWidth.clamp(1, 4);
  final available = pathBytes.length ~/ width;
  final count = [
    hops,
    available,
    _maxListedHops,
  ].reduce((a, b) => a < b ? a : b);
  return [
    for (var i = 0; i < count; i++)
      pathBytes
          .sublist(i * width, (i + 1) * width)
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(),
  ];
}

/// Inserts [text] into [controller] at the cursor (replacing any selection)
/// and leaves the cursor after it, so the user can edit before sending.
void insertAtCursor(TextEditingController controller, String text) {
  final value = controller.value;
  final selection = value.selection;
  final start = selection.isValid ? selection.start : value.text.length;
  final end = selection.isValid ? selection.end : value.text.length;
  controller.value = TextEditingValue(
    text: value.text.replaceRange(start, end, text),
    selection: TextSelection.collapsed(offset: start + text.length),
  );
}
