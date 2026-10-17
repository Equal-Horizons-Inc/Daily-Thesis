import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/paper.dart';
import 'clock_skew.dart';
import 'interest_matcher.dart';

class PaperService {
  static const String _workerUrl =
      'https://quiet-bread-7971.li231sdyt.workers.dev/';

  /// Wraps every outbound request. If the underlying request fails at the
  /// TLS layer (HandshakeException, CertificateException — both are
  /// TlsException subtypes), checks whether that's attributable to clock
  /// skew before surfacing it, so the UI can show an actionable message
  /// instead of a raw handshake error.
  Future<http.Response> _get(Uri uri) async {
    try {
      return await http.get(uri).timeout(const Duration(seconds: 20));
    } on TlsException {
      if (await ClockSkewDetector.isClockLikelySkewed()) {
        throw const ClockSkewException();
      }
      rethrow;
    }
  }

  /// Fetches today's paper. If the user has multiple matched subjects,
  /// rotates deterministically through them by day (see
  /// InterestMatcher.subjectForToday) so the same subject isn't hit every
  /// time. Pass [dislikeCounts] (from FeedbackStorage) to softly steer
  /// rotation away from subjects the user keeps marking "not for me".
  ///
  /// Pass [excludeUrls] (typically history + DismissedPapersStorage) to
  /// skip papers already viewed or explicitly disliked. The pick still
  /// starts from the same date-based index every time today (so a plain
  /// re-open without any new dislikes shows the same paper), but walks
  /// forward past anything in [excludeUrls] instead of blindly returning
  /// the raw indexed result — this is what previously let a dismissed
  /// paper come right back on refresh.
  Future<Paper> fetchDailyPaper({
    List<String>? matchedSubjects,
    Map<String, int>? dislikeCounts,
    Set<String> excludeUrls = const {},
  }) async {
    final subject = (matchedSubjects == null || matchedSubjects.isEmpty)
        ? null
        : InterestMatcher.subjectForToday(matchedSubjects, dislikeCounts: dislikeCounts);

    final uri = subject != null
        ? Uri.parse('$_workerUrl?subject=$subject')
        : Uri.parse(_workerUrl);

    final response = await _get(uri);

    if (response.statusCode != 200) {
      throw Exception('Server returned ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final results = switch (decoded) {
      List<dynamic> items => items,
      Map<String, dynamic> json => (json['data'] as List<dynamic>?) ?? const [],
      _ => const [],
    };

    if (results.isEmpty) {
      throw Exception('No papers found');
    }

    final today = DateTime.now();
    final baseIndex = today.year * 365 + today.month * 30 + today.day;

    for (var i = 0; i < results.length; i++) {
      final index = (baseIndex + i) % results.length;
      final candidate = Paper.fromJson(results[index] as Map<String, dynamic>);
      if (!excludeUrls.contains(candidate.url)) {
        return candidate;
      }
    }

    // Every result for this subject has already been viewed/dismissed —
    // fall back to today's base pick rather than erroring out, matching
    // fetchAnotherPaper's fallback behavior below.
    final fallbackIndex = baseIndex % results.length;
    return Paper.fromJson(results[fallbackIndex] as Map<String, dynamic>);
  }

  /// Fetches a different paper for [subject] — used by the "not for me"
  /// feedback loop. Walks forward from the day's base index (offset by
  /// [attempt]) to find a paper not already in [excludeUrls] (papers shown
  /// earlier this session), so repeated taps don't just cycle the same
  /// handful of results back and forth.
  Future<Paper> fetchAnotherPaper({
    required String subject,
    int attempt = 0,
    Set<String> excludeUrls = const {},
  }) async {
    final uri = Uri.parse('$_workerUrl?subject=$subject');
    final response = await _get(uri);

    if (response.statusCode != 200) {
      throw Exception('Server returned ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final results = switch (decoded) {
      List<dynamic> items => items,
      Map<String, dynamic> json => (json['data'] as List<dynamic>?) ?? const [],
      _ => const [],
    };

    if (results.isEmpty) {
      throw Exception('No papers found');
    }

    final today = DateTime.now();
    final baseIndex = today.year * 365 + today.month * 30 + today.day;

    for (var i = 0; i < results.length; i++) {
      final index = (baseIndex + attempt + i) % results.length;
      final candidate = Paper.fromJson(results[index] as Map<String, dynamic>);
      if (!excludeUrls.contains(candidate.url)) {
        return candidate;
      }
    }

    // Every result for this subject has already been shown today — just
    // return the next one in sequence rather than erroring out.
    final fallbackIndex = (baseIndex + attempt) % results.length;
    return Paper.fromJson(results[fallbackIndex] as Map<String, dynamic>);
  }

  /// Returns up to [count] candidates for [subject], skipping anything in
  /// [excludeUrls]. Used to top up PaperBufferStorage while online so
  /// there's something fresh to show when the connection drops. Reuses the
  /// same worker endpoint as the other two methods — the worker already
  /// returns a full candidate list per subject, so no backend changes are
  /// needed for prefetching.
  Future<List<Paper>> fetchCandidates({
    String? subject,
    int count = 20,
    Set<String> excludeUrls = const {},
  }) async {
    final uri = subject == null || subject == 'all'
        ? Uri.parse(_workerUrl)
        : Uri.parse('$_workerUrl?subject=$subject');
    final response = await _get(uri);

    if (response.statusCode != 200) {
      throw Exception('Server returned ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final results = switch (decoded) {
      List<dynamic> items => items,
      Map<String, dynamic> json => (json['data'] as List<dynamic>?) ?? const [],
      _ => const [],
    };

    final out = <Paper>[];
    for (final item in results) {
      final paper = Paper.fromJson(item as Map<String, dynamic>);
      if (paper.url.isEmpty || excludeUrls.contains(paper.url)) continue;
      out.add(paper);
      if (out.length >= count) break;
    }
    return out;
  }
}
