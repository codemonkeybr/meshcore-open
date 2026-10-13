/// Pure helpers for `@[Name]` mentions: finding the mention being typed,
/// filtering candidates, inserting a pick and splitting text for display.
library;

/// The `@query` token that ends at the cursor.
class MentionQuery {
  /// Index of the `@` in the text.
  final int start;

  /// Text typed after the `@`, up to the cursor (may be empty).
  final String query;

  const MentionQuery({required this.start, required this.query});
}

/// Returns the mention being typed at [cursor], or null.
///
/// The `@` must start the text or follow whitespace, and the text between it
/// and the cursor must not contain whitespace, `[` or `]` (so an already
/// inserted `@[Name]` never reopens the list).
MentionQuery? activeMentionQuery(String text, int cursor) {
  if (cursor < 1 || cursor > text.length) return null;
  var i = cursor - 1;
  while (i >= 0) {
    final c = text[i];
    if (c == '@') {
      if (i > 0 && !_isSpace(text[i - 1])) return null;
      return MentionQuery(start: i, query: text.substring(i + 1, cursor));
    }
    if (_isSpace(c) || c == '[' || c == ']') return null;
    i--;
  }
  return null;
}

bool _isSpace(String c) => c.trim().isEmpty;

/// Names to suggest for [query].
///
/// [recentFirst] lists sender names with the most recent first. Duplicates and
/// [selfName] are dropped. Names starting with the query come before names
/// that only contain it. Empty query returns everyone.
List<String> mentionCandidates(
  Iterable<String> recentFirst,
  String query, {
  String? selfName,
}) {
  final q = query.toLowerCase();
  final me = selfName?.trim().toLowerCase();
  final seen = <String>{};
  final starts = <String>[];
  final contains = <String>[];
  for (final raw in recentFirst) {
    final name = raw.trim();
    if (name.isEmpty) continue;
    final lower = name.toLowerCase();
    if (lower == me || !seen.add(lower)) continue;
    if (q.isEmpty || lower.startsWith(q)) {
      starts.add(name);
    } else if (lower.contains(q)) {
      contains.add(name);
    }
  }
  return [...starts, ...contains];
}

/// Result of inserting a mention.
class MentionInsertion {
  final String text;
  final int cursor;
  const MentionInsertion(this.text, this.cursor);
}

/// Replaces the `@query` token with `@[name] ` and places the cursor after it.
MentionInsertion insertMention(
  String text,
  MentionQuery token,
  int cursor,
  String name,
) {
  final insert = '@[$name] ';
  final before = text.substring(0, token.start);
  var after = text.substring(cursor);
  if (after.startsWith(' ')) after = after.substring(1);
  return MentionInsertion(
    '$before$insert$after',
    before.length + insert.length,
  );
}

/// Adds the `@[sender]` reply prefix unless [text] already starts with it.
String withReplyMention(String text, String sender) {
  final prefix = '@[$sender]';
  if (text.startsWith(prefix)) return text;
  return '$prefix $text';
}

/// A piece of text, either plain or a mention.
class MentionSpan {
  final String text;

  /// Name inside the brackets when this piece is a mention.
  final String? name;

  const MentionSpan(this.text, [this.name]);

  bool get isMention => name != null;
}

final RegExp _mention = RegExp(r'@\[([^\]\n]+)\]');

/// Splits [text] into plain pieces and `@[Name]` mentions, in order.
List<MentionSpan> splitMentions(String text) {
  final out = <MentionSpan>[];
  var last = 0;
  for (final m in _mention.allMatches(text)) {
    if (m.start > last) out.add(MentionSpan(text.substring(last, m.start)));
    out.add(MentionSpan(m.group(0)!, m.group(1)!));
    last = m.end;
  }
  if (last < text.length) out.add(MentionSpan(text.substring(last)));
  return out;
}

/// Whether [text] mentions [selfName] (case-insensitive).
bool mentionsName(String text, String? selfName) {
  final me = selfName?.trim().toLowerCase();
  if (me == null || me.isEmpty) return false;
  return splitMentions(
    text,
  ).any((s) => s.isMention && s.name!.trim().toLowerCase() == me);
}
