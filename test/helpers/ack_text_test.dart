import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/ack_text.dart';

void main() {
  group('buildAckText', () {
    test('matches the wadamesh channel format', () {
      expect(
        buildAckText(senderName: 'T3550 Base', snr: 14.0, rssi: -48, hops: 0),
        '@[T3550 Base], ack: SNR 14.0 dB, RSSI -48 dBm, 0 hops',
      );
    });

    test('direct message ack has no mention', () {
      expect(buildAckText(snr: 6.5), 'Ack: SNR 6.5 dB');
    });

    test('lists hop codes in hex and pluralizes', () {
      expect(
        buildAckText(
          senderName: 'A',
          snr: -3.25,
          rssi: -101,
          hops: 2,
          pathBytes: Uint8List.fromList([0x3a, 0xf1]),
        ),
        '@[A], ack: SNR -3.3 dB, RSSI -101 dBm, 2 hops via 3A, F1',
      );
      expect(
        buildAckText(
          senderName: 'A',
          hops: 1,
          pathBytes: Uint8List.fromList([0x0b]),
        ),
        '@[A], ack: 1 hop via 0B',
      );
    });

    test('respects the hash width when listing hops', () {
      expect(
        buildAckText(
          senderName: 'A',
          hops: 2,
          hashWidth: 2,
          pathBytes: Uint8List.fromList([0x01, 0x02, 0xab, 0xcd]),
        ),
        '@[A], ack: 2 hops via 0102, ABCD',
      );
    });

    test('caps listed hops at eight', () {
      final text = buildAckText(
        senderName: 'A',
        hops: 10,
        pathBytes: Uint8List.fromList(List.generate(10, (i) => i + 1)),
      );
      expect(text, endsWith('10 hops via 01, 02, 03, 04, 05, 06, 07, 08'));
    });

    test('negative hops means direct', () {
      expect(
        buildAckText(senderName: 'A', snr: 1.0, hops: -1),
        '@[A], ack: SNR 1.0 dB, direct',
      );
    });

    test('leaves out unknown values', () {
      expect(buildAckText(senderName: 'A'), '@[A], ack');
      expect(buildAckText(), 'Ack');
      expect(
        buildAckText(senderName: 'A', rssi: -90),
        '@[A], ack: RSSI -90 dBm',
      );
    });
  });

  group('insertAtCursor', () {
    test('inserts at the cursor and moves it after the text', () {
      final c = TextEditingController(text: 'hello world')
        ..selection = const TextSelection.collapsed(offset: 5);
      insertAtCursor(c, ' there');
      expect(c.text, 'hello there world');
      expect(c.selection.baseOffset, 11);
    });

    test('replaces a selection', () {
      final c = TextEditingController(text: 'abcdef')
        ..selection = const TextSelection(baseOffset: 1, extentOffset: 4);
      insertAtCursor(c, 'X');
      expect(c.text, 'aXef');
    });

    test('appends when there is no valid selection', () {
      final c = TextEditingController(text: 'abc');
      insertAtCursor(c, 'd');
      expect(c.text, 'abcd');
    });
  });
}
