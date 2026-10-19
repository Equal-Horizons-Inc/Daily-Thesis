import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/paper.dart';

/// A locally stored paper the reader explicitly wants to keep.
class SavedPaperEntry {
  final Paper paper;
  final DateTime savedAt;

  const SavedPaperEntry({required this.paper, required this.savedAt});

  Map<String, dynamic> toJson() => {
    'paper': paper.toJson(),
    'savedAt': savedAt.toIso8601String(),
  };

  factory SavedPaperEntry.fromJson(Map<String, dynamic> json) {
    return SavedPaperEntry(
      paper: Paper.fromJson(json['paper'] as Map<String, dynamic>),
      savedAt:
          DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Owns the reader's Library. It is intentionally separate from likes: a
/// saved paper is something to revisit, while a like is a recommendation
/// signal and can be removed without losing a saved paper.
class SavedPapersStorage {
  static const _key = 'saved_papers_v1';

  Future<List<SavedPaperEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(SavedPaperEntry.fromJson)
          .toList();
    } on FormatException {
      return const [];
    }
  }

  Future<Set<String>> loadUrls() async {
    return (await load()).map((entry) => entry.paper.url).toSet();
  }

  Future<void> save(Paper paper) async {
    if (paper.url.isEmpty) return;

    final current = await load();
    final updated = List<SavedPaperEntry>.from(current)
      ..removeWhere((entry) => entry.paper.url == paper.url)
      ..insert(0, SavedPaperEntry(paper: paper, savedAt: DateTime.now()));
    await _write(updated);
  }

  Future<void> remove(String url) async {
    final updated = List<SavedPaperEntry>.from(await load())
      ..removeWhere((entry) => entry.paper.url == url);
    await _write(updated);
  }

  Future<void> _write(List<SavedPaperEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
  }
}
