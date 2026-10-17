import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/recommendation_event.dart';

class RecommendationEventStorage {
  static const _key = 'recommendation_events_v1';
  static const _maxEvents = 100;

  Future<List<RecommendationEvent>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];

    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(RecommendationEvent.fromJson)
        .toList();
  }

  Future<void> record(RecommendationEvent event) async {
    final prefs = await SharedPreferences.getInstance();
    final events = (await load()).toList()
      ..removeWhere(
        (existing) =>
            existing.paper.url == event.paper.url &&
            existing.action == event.action,
      )
      ..insert(0, event);

    await prefs.setString(
      _key,
      jsonEncode(events.take(_maxEvents).map((event) => event.toJson()).toList()),
    );
  }

  Future<void> remove({
    required String paperUrl,
    required RecommendationAction action,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final events = await load();
    events.removeWhere(
      (event) => event.paper.url == paperUrl && event.action == action,
    );
    await prefs.setString(
      _key,
      jsonEncode(events.map((event) => event.toJson()).toList()),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
