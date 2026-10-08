import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';
import '../utils/app_logger.dart';

/// Wire format of the repeater "get neighbors" binary request and reply.
class NeighborsProtocol {
  NeighborsProtocol._();

  /// Neighbors are identified by a 4-byte prefix of their public key.
  static const int keyLength = 4;

  // Firmware packs results into a 130-byte buffer (simple_repeater/MyMesh.cpp).
  static const int pageSize = 130 ~/ (keyLength + 5);

  /// Binary request for one page of neighbors starting at [offset].
  ///
  /// Layout: [type][version][page size][offset 16-bit LE][order by][key len].
  static Uint8List requestPayload(int offset) {
    return Uint8List.fromList([
      reqTypeGetNeighbors,
      0x00,
      pageSize,
      offset & 0xFF,
      (offset >> 8) & 0xFF,
      0x00,
      keyLength,
    ]);
  }

  /// Parses one neighbors response body (the bytes after the request tag).
  static ({int total, List<Map<String, dynamic>> page}) parsePage(
    Uint8List body,
  ) {
    final buffer = BufferReader(body);
    final total = buffer.readUInt16LE();
    final page = parseNeighborsData(buffer, buffer.readUInt16LE());
    return (total: total, page: page);
  }

  static List<Map<String, dynamic>> parseNeighborsData(
    BufferReader buffer,
    int resultsCount,
  ) {
    final Map<int, Map<String, dynamic>> neighbors = {};
    try {
      for (var i = 0; i < resultsCount; i++) {
        final neighborData = neighbors.putIfAbsent(
          i,
          () => {
            'contact': null,
            'publicKey': <Uint8List>{},
            'lastHeard': <int>{},
            'snr': <double>{},
          },
        );
        neighborData['publicKey'] = buffer.readBytes(keyLength);
        neighborData['lastHeard'] = buffer.readUInt32LE();
        neighborData['snr'] = buffer.readInt8() / 4.0;
      }

      return neighbors.values.toList();
    } catch (e) {
      appLogger.error(
        'Error parsing neighbors data: $e',
        tag: 'NeighborsScreen',
      );
      return [];
    }
  }
}
