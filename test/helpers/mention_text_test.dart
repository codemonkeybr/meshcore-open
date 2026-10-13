import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/link_handler.dart';
import 'package:meshcore_open/helpers/mention_text.dart';

void main() {
  group('activeMentionQuery', () {
    test('finds @ at start and after a space', () {
      expect(activeMentionQuery('@', 1)!.query, '');
      expect(activeMentionQuery('@ma', 3)!.query, 'ma');
      final q = activeMentionQuery('hi @ma', 6)!;
      expect(q.start, 3);
      expect(q.query, 'ma');
    });

    test('ignores e-mail style, finished mentions and spaces', () {
      expect(activeMentionQuery('a@b', 3), isNull);
      expect(activeMentionQuery('@[Maria T] ', 11), isNull);
      expect(activeMentionQuery('@[Mar', 5), isNull);
      expect(activeMentionQuery('@ma rest', 8), isNull);
      expect(activeMentionQuery('hello', 5), isNull);
      expect(activeMentionQuery('', 0), isNull);
    });

    test('uses the cursor, not the end of the text', () {
      final q = activeMentionQuery('@ma rest', 3)!;
      expect(q.query, 'ma');
    });
  });

  group('mentionCandidates', () {
    const recent = ['Maria T', 'Marcos', 'Joao Rep', 'Maria T', 'Tesso', ''];

    test('empty query returns everyone once, in order, minus self', () {
      expect(mentionCandidates(recent, '', selfName: 'tesso'), [
        'Maria T',
        'Marcos',
        'Joao Rep',
      ]);
    });

    test('prefix matches come before contains matches', () {
      expect(mentionCandidates(['Ana Mar', 'Marcos'], 'mar'), [
        'Marcos',
        'Ana Mar',
      ]);
    });

    test('no match gives an empty list', () {
      expect(mentionCandidates(recent, 'zzz'), isEmpty);
    });
  });

  group('insertMention', () {
    test('replaces the token and puts the cursor after it', () {
      const text = 'hi @ma';
      final token = activeMentionQuery(text, 6)!;
      final r = insertMention(text, token, 6, 'Maria T');
      expect(r.text, 'hi @[Maria T] ');
      expect(r.cursor, r.text.length);
    });

    test('keeps text after the cursor without doubling the space', () {
      const text = '@ma rest';
      final token = activeMentionQuery(text, 3)!;
      final r = insertMention(text, token, 3, 'Marcos');
      expect(r.text, '@[Marcos] rest');
      expect(r.cursor, 10);
    });
  });

  test('withReplyMention does not repeat an existing mention', () {
    expect(withReplyMention('hello', 'Ana'), '@[Ana] hello');
    expect(withReplyMention('@[Ana] hello', 'Ana'), '@[Ana] hello');
    expect(withReplyMention('@[Bob] hello', 'Ana'), '@[Ana] @[Bob] hello');
  });

  test('splitMentions finds leading and mid-message mentions', () {
    final parts = splitMentions('@[A B] see @[C] ok');
    expect(parts.map((p) => p.text), ['@[A B]', ' see ', '@[C]', ' ok']);
    expect(parts.map((p) => p.isMention), [true, false, true, false]);
    expect(splitMentions('plain @ text').single.isMention, isFalse);
  });

  test('mentionsName is case-insensitive and needs the brackets', () {
    expect(mentionsName('x @[tesso] y', 'Tesso'), isTrue);
    expect(mentionsName('hello Tesso', 'Tesso'), isFalse);
    expect(mentionsName('@[Tesso]', null), isFalse);
  });

  testWidgets('message text shows mentions as styled spans', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => LinkHandler.buildLinkifyText(
            context: context,
            text: 'hey @[Tesso] and @[Ana] see https://example.com',
            style: const TextStyle(color: Colors.black),
            highlightMentions: true,
            selfName: 'Tesso',
          ),
        ),
      ),
    );
    final root = tester.widget<SelectableText>(find.byType(SelectableText));
    final spans = <TextSpan>[];
    root.textSpan!.visitChildren((s) {
      if (s is TextSpan && s.text != null) spans.add(s);
      return true;
    });
    TextSpan byText(String t) => spans.firstWhere((s) => s.text == t);
    expect(byText('@[Tesso]').style!.backgroundColor, const Color(0xFFFFE08A));
    expect(
      byText('@[Ana]').style!.backgroundColor,
      isNot(const Color(0xFFFFE08A)),
    );
    expect(byText('@[Ana]').style!.backgroundColor, isNotNull);
    expect(byText('https://example.com').recognizer, isNotNull);
  });
}
