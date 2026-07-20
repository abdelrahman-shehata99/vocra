import 'package:test/test.dart';
import 'package:vocra_core/vocra_core.dart';

TranscriptEvent user(String text, {bool isFinal = false}) => TranscriptEvent(
  source: TranscriptSource.user,
  text: text,
  isFinal: isFinal,
);
TranscriptEvent ai(String text, {bool isFinal = false}) => TranscriptEvent(
  source: TranscriptSource.assistant,
  text: text,
  isFinal: isFinal,
);

void main() {
  group('TranscriptAggregator', () {
    test('an interim replaces the trailing interim from the same source', () {
      final agg = TranscriptAggregator();
      agg.add(user('he'));
      agg.add(user('hell'));
      final result = agg.add(user('hello'));
      expect(result, [user('hello')]);
    });

    test(
      'a final replaces its own trailing interim in place, not appended after',
      () {
        final agg = TranscriptAggregator();
        agg.add(user('hello'));
        final result = agg.add(user('hello there', isFinal: true));
        // One bubble, not two — the final does not duplicate the interim.
        expect(result, [user('hello there', isFinal: true)]);
      },
    );

    test('an event from the other source appends a new bubble', () {
      final agg = TranscriptAggregator();
      agg.add(user('hi', isFinal: true));
      final result = agg.add(ai('hello'));
      expect(result, [user('hi', isFinal: true), ai('hello')]);
    });

    test('a run after a final appends instead of replacing', () {
      final agg = TranscriptAggregator();
      agg.add(ai('first', isFinal: true));
      final result = agg.add(ai('second'));
      expect(result, [ai('first', isFinal: true), ai('second')]);
    });

    test('a final with no preceding interim appends', () {
      final agg = TranscriptAggregator();
      final result = agg.add(user('typed', isFinal: true));
      expect(result, [user('typed', isFinal: true)]);
    });

    test('clear empties the aggregate', () {
      final agg = TranscriptAggregator();
      agg.add(user('hi', isFinal: true));
      agg.clear();
      expect(agg.events, isEmpty);
    });

    test('returned lists are unmodifiable snapshots', () {
      final agg = TranscriptAggregator();
      final result = agg.add(user('hi', isFinal: true));
      expect(() => result.add(ai('x')), throwsUnsupportedError);
    });
  });
}
