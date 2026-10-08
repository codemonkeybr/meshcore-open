import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/channel_message.dart';

void main() {
  test('ChannelMessage.copyWith keeps and fills snr/rssi', () {
    final msg = ChannelMessage(
      senderName: 'A',
      text: 'hi',
      timestamp: DateTime(2026),
      isOutgoing: false,
      snr: 5.5,
      rssi: -80,
    );
    expect(msg.copyWith().snr, 5.5);
    expect(msg.copyWith().rssi, -80);

    final bare = ChannelMessage(
      senderName: 'A',
      text: 'hi',
      timestamp: DateTime(2026),
      isOutgoing: false,
    );
    expect(bare.snr, isNull);
    final filled = bare.copyWith(snr: 2.0, rssi: -70);
    expect(filled.snr, 2.0);
    expect(filled.rssi, -70);
  });
}
