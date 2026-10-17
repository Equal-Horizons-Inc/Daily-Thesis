import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_thesis/models/paper.dart';
import 'package:daily_thesis/services/local_recommendation_service.dart';

Paper _paper(String url, String title, String abstract) => Paper(
      title: title,
      abstract: abstract,
      authors: '',
      journal: '',
      url: url,
      source: 'arxiv',
      publishYear: 2026,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('uses explicit interests during cold start', () async {
    final service = LocalRecommendationService();
    final selected = await service.choose([
      _paper('1', 'Ocean currents', 'fluid dynamics'),
      _paper('2', 'Neural networks', 'machine learning'),
    ], interests: ['Machine Learning']);

    expect(selected?.url, '2');
  });

  test('learns from a liked paper without sending data remotely', () async {
    final service = LocalRecommendationService();
    final liked = _paper('1', 'Neural networks', 'machine learning');
    await service.recordLike(liked);

    final selected = await service.choose([
      _paper('2', 'Machine learning methods', 'neural network optimization'),
      _paper('3', 'Ocean currents', 'fluid dynamics'),
    ]);

    expect(selected?.url, '2');
  });

  test('learned dislikes lower similar candidates', () async {
    final service = LocalRecommendationService();
    final dismissed = _paper('1', 'Neural networks', 'machine learning');
    await service.recordDismissal(dismissed);

    final selected = await service.choose([
      _paper('2', 'Machine learning methods', 'neural network optimization'),
      _paper('3', 'Ocean currents', 'fluid dynamics'),
    ]);

    expect(selected?.url, '3');
  });

  test('reset removes learned preferences', () async {
    final service = LocalRecommendationService();
    await service.recordLike(_paper('1', 'Neural networks', 'machine learning'));
    await service.reset();

    final events = await service.rank([
      _paper('2', 'Ocean currents', 'fluid dynamics'),
      _paper('3', 'Neural networks', 'machine learning'),
    ]);

    expect(events, hasLength(2));
  });
}
