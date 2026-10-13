import '../models/channel_message.dart';

/// A private copy of a channel message the user starred.
///
/// Kept as a snapshot so it survives "Clear chat" and the chat window
/// trimming older messages.
class StarredMessage {
  final String messageId;
  final String senderName;
  final String text;
  final DateTime timestamp;
  final bool isOutgoing;

  /// Hops the message took, null when unknown. [isDirect] false means flood.
  final int? hops;
  final bool isDirect;

  const StarredMessage({
    required this.messageId,
    required this.senderName,
    required this.text,
    required this.timestamp,
    required this.isOutgoing,
    this.hops,
    this.isDirect = true,
  });

  factory StarredMessage.fromMessage(ChannelMessage message) {
    final length = message.pathLength ?? -1;
    return StarredMessage(
      messageId: message.messageId,
      senderName: message.senderName,
      text: message.text,
      timestamp: message.timestamp,
      isOutgoing: message.isOutgoing,
      hops: length >= 0 ? length : null,
      isDirect: length >= 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': messageId,
    'sender': senderName,
    'text': text,
    'ts': timestamp.millisecondsSinceEpoch,
    'out': isOutgoing,
    if (hops != null) 'hops': hops,
    'direct': isDirect,
  };

  static StarredMessage? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final ts = json['ts'];
    if (id is! String || ts is! int) return null;
    return StarredMessage(
      messageId: id,
      senderName: json['sender'] as String? ?? '',
      text: json['text'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
      isOutgoing: json['out'] as bool? ?? false,
      hops: json['hops'] as int?,
      isDirect: json['direct'] as bool? ?? true,
    );
  }
}
