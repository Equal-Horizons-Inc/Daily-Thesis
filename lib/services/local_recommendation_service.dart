import 'dart:math' as math;

import '../models/paper.dart';
import '../models/recommendation_event.dart';
import 'recommendation_event_storage.dart';

/// A small, explainable on-device learner.
///
/// The model is a content-based linear ranker. It learns token weights from
/// explicit likes and dismissals, so it works with a cold start and does not
/// require a bundled ML runtime or a network request.
class LocalRecommendationService {
  final RecommendationEventStorage _eventStorage;

  LocalRecommendationService({RecommendationEventStorage? eventStorage})
      : _eventStorage = eventStorage ?? RecommendationEventStorage();

  Future<Paper?> choose(
    List<Paper> candidates, {
    List<String> interests = const [],
  }) async {
    if (candidates.isEmpty) return null;

    final events = await _eventStorage.load();
    final scores = _scores(
      candidates,
      events: events,
      interests: interests,
    );

    var bestIndex = 0;
    for (var i = 1; i < candidates.length; i++) {
      if (scores[i] > scores[bestIndex]) bestIndex = i;
    }
    return candidates[bestIndex];
  }

  /// Returns candidates in learned-score order for the offline queue.
  Future<List<Paper>> rank(
    List<Paper> candidates, {
    List<String> interests = const [],
  }) async {
    final events = await _eventStorage.load();
    final scores = _scores(
      candidates,
      events: events,
      interests: interests,
    );
    final indexed = List.generate(candidates.length, (index) => index)
      ..sort((a, b) {
        final scoreComparison = scores[b].compareTo(scores[a]);
        return scoreComparison == 0 ? a.compareTo(b) : scoreComparison;
      });
    return indexed.map((index) => candidates[index]).toList();
  }

  Future<void> recordLike(Paper paper) => _record(paper, RecommendationAction.liked);

  Future<void> removeLike(Paper paper) => _eventStorage.remove(
        paperUrl: paper.url,
        action: RecommendationAction.liked,
      );

  Future<void> recordDismissal(Paper paper) =>
      _record(paper, RecommendationAction.dismissed);

  Future<void> reset() => _eventStorage.clear();

  Future<void> _record(Paper paper, RecommendationAction action) {
    return _eventStorage.record(
      RecommendationEvent(
        paper: paper,
        action: action,
        createdAt: DateTime.now(),
      ),
    );
  }

  List<double> _scores(
    List<Paper> candidates, {
    required List<RecommendationEvent> events,
    required List<String> interests,
  }) {
    final liked = events
        .where((event) => event.action == RecommendationAction.liked)
        .toList();
    final dismissed = events
        .where((event) => event.action == RecommendationAction.dismissed)
        .toList();

    final likedTokens = _tokenCounts(liked.map((event) => event.paper));
    final dismissedTokens = _tokenCounts(dismissed.map((event) => event.paper));
    final interestTokens = _tokens(interests.join(' '));

    return candidates.map((paper) {
      final tokens = _tokens(_searchableText(paper));
      if (tokens.isEmpty) return 0.0;

      var score = 0.0;
      for (final token in tokens) {
        score += (likedTokens[token] ?? 0) * 1.0;
        score -= (dismissedTokens[token] ?? 0) * 1.25;
        if (interestTokens.contains(token)) score += 1.5;
      }

      // Keep the model from always preferring old, highly-cited papers.
      score += _recencyScore(paper);
      score += math.log((paper.citationCount ?? 0) + 1) * 0.05;
      return score / math.sqrt(tokens.length);
    }).toList();
  }

  Map<String, double> _tokenCounts(Iterable<Paper> papers) {
    final counts = <String, double>{};
    for (final paper in papers) {
      for (final token in _tokens(_searchableText(paper))) {
        counts[token] = (counts[token] ?? 0) + 1;
      }
    }
    return counts;
  }

  Set<String> _tokens(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .split(' ')
        .where((token) => token.length >= 3 && !_stopWords.contains(token))
        .toSet();
  }

  String _searchableText(Paper paper) =>
      '${paper.title} ${paper.abstract} ${paper.authors} ${paper.journal} ${paper.source}';

  double _recencyScore(Paper paper) {
    final year = paper.publishYear;
    if (year == null) return 0;
    final age = math.max(0, DateTime.now().year - year);
    return 0.5 / (1 + age);
  }

  static const _stopWords = {
    'about',
    'after',
    'also',
    'and',
    'are',
    'based',
    'been',
    'between',
    'from',
    'into',
    'more',
    'over',
    'that',
    'their',
    'these',
    'this',
    'through',
    'using',
    'were',
    'with',
  };
}
