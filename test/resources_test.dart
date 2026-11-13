import 'package:flutter_test/flutter_test.dart';
import 'package:octria/ai/ai.dart';
import 'package:octria/ai/sample_ai.dart';

void main() {
  group('what Ofy found on the web', () {
    const answer = '''
Here is what I found:
1. Khan Academy: Waves | https://www.khanacademy.org/science/physics/waves | course | Short lessons with practice.
- **Wave basics** | https://youtu.be/abc123 | video | A clear ten minute walk through.
OpenStax Physics, chapter 16 | https://openstax.org/books/physics/pages/16 | Free textbook chapter on waves and sound.
Made up | https://definitely-not-real.example/waves | article | Sounds plausible.
Not secure | http://old.example.com/waves | article | Old page.
Khan again | https://www.khanacademy.org/science/physics/waves | course | Twice.
No link here | article | nothing
''';

    test('keeps https links once each, confirmed ones first', () {
      final found = ResourceFind.parse(
        answer,
        grounded: ['khanacademy.org', 'youtube.com', 'openstax.org'],
      );
      expect(found.resources.map((r) => r.title), [
        'Khan Academy: Waves',
        'Wave basics',
        'OpenStax Physics, chapter 16',
        'Made up',
      ]);
      // YouTube's short links count as YouTube.
      final video = found.resources.firstWhere((r) => r.title == 'Wave basics');
      expect(video.video, isTrue);
      expect(video.confirmed, isTrue);
      expect(found.resources.first.confirmed, isTrue);
      expect(found.resources.first.why, 'Short lessons with practice.');
      expect(found.resources.last.confirmed, isFalse);
      // With no kind given, the sentence after the link is the reason.
      expect(
        found.resources[2].why,
        'Free textbook chapter on waves and sound.',
      );
    });

    test('leaves out what the step already has', () {
      final found = ResourceFind.parse(
        answer,
        have: ['https://www.khanacademy.org/science/physics/waves'],
      );
      expect(found.resources.any((r) => r.title.startsWith('Khan')), isFalse);
    });

    test('a sub-site of a returned site counts as confirmed', () {
      final found = ResourceFind.parse(
        'Docs | https://docs.flutter.dev/ui | docs | The official guide.',
        grounded: ['flutter.dev'],
      );
      expect(found.resources.single.confirmed, isTrue);
    });

    test('nothing, or NONE, gives nothing', () {
      expect(ResourceFind.parse('NONE').resources, isEmpty);
      expect(ResourceFind.parse('').resources, isEmpty);
    });

    test('never more than six', () {
      final many = [
        for (var i = 0; i < 12; i++)
          'Page $i | https://site$i.org/a | article | ok',
      ].join('\n');
      expect(ResourceFind.parse(many).resources, hasLength(6));
    });
  });

  group('Google’s suggested searches', () {
    test('are read from the chips it sends', () {
      const html = '''
<style>.chip { color: red }</style>
<div class="carousel">
  <a class="chip" href="https://vertexaisearch.cloud.google.com/grounding-api-redirect/abc">wave &amp; particle duality</a>
  <a class="chip" href="https://vertexaisearch.cloud.google.com/grounding-api-redirect/def">what is a <b>wavelength</b></a>
  <a class="chip" href="https://x">wave &amp; particle duality</a>
  <a class="logo" href="https://google.com">Google</a>
</div>''';
      expect(searchSuggestions(html), [
        'wave & particle duality',
        'what is a wavelength',
      ]);
      expect(searchSuggestions(''), isEmpty);
    });

    test('open that search on Google', () {
      final link = googleSearchLink('wave & particle');
      expect(link.host, 'www.google.com');
      expect(link.queryParameters['q'], 'wave & particle');
    });
  });

  test(
    'the sample model finds links for the step and skips ones it has',
    () async {
      final ai = SampleAi(delay: Duration.zero);
      final all = await ai.findResources(
        const ResourceBrief(subject: 'Physics', step: 'Learn waves'),
      );
      expect(all.resources, hasLength(3));
      expect(all.searches, isNotEmpty);
      final fewer = await ai.findResources(
        ResourceBrief(
          subject: 'Physics',
          step: 'Learn waves',
          have: [all.resources.first.url],
        ),
      );
      expect(fewer.resources, hasLength(2));
    },
  );
}
