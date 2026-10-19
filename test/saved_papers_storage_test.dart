import 'package:daily_thesis/models/paper.dart';
import 'package:daily_thesis/services/saved_papers_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Paper _paper(String url, {String title = 'Untitled'}) => Paper(
  title: title,
  abstract: 'abstract',
  authors: 'authors',
  journal: 'journal',
  url: url,
  source: 'arxiv',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SavedPapersStorage', () {
    test('starts empty', () async {
      final storage = SavedPapersStorage();

      expect(await storage.load(), isEmpty);
      expect(await storage.loadUrls(), isEmpty);
    });

    test('saves a complete paper and exposes its URL', () async {
      final storage = SavedPapersStorage();
      final paper = _paper('https://example.com/one', title: 'A saved paper');

      await storage.save(paper);

      final entries = await storage.load();
      expect(entries, hasLength(1));
      expect(entries.single.paper.title, 'A saved paper');
      expect(await storage.loadUrls(), {'https://example.com/one'});
    });

    test(
      'saving an existing paper replaces it instead of duplicating it',
      () async {
        final storage = SavedPapersStorage();
        const url = 'https://example.com/one';

        await storage.save(_paper(url, title: 'Original title'));
        await storage.save(_paper(url, title: 'Updated title'));

        final entries = await storage.load();
        expect(entries, hasLength(1));
        expect(entries.single.paper.title, 'Updated title');
      },
    );

    test('removes a saved paper', () async {
      final storage = SavedPapersStorage();
      await storage.save(_paper('https://example.com/one'));

      await storage.remove('https://example.com/one');

      expect(await storage.load(), isEmpty);
    });
  });
}
