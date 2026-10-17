import 'package:daily_thesis/models/paper.dart';

enum RecommendationAction { liked, dismissed }

class RecommendationEvent {
  final Paper paper;
  final RecommendationAction action;
  final DateTime createdAt;

  const RecommendationEvent({
    required this.paper,
    required this.action,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'paper': paper.toJson(),
        'action': action.name,
        'createdAt': createdAt.toIso8601String(),
      };

  factory RecommendationEvent.fromJson(Map<String, dynamic> json) {
    return RecommendationEvent(
      paper: Paper.fromJson(json['paper'] as Map<String, dynamic>),
      action: RecommendationAction.values.firstWhere(
        (action) => action.name == json['action'],
        orElse: () => RecommendationAction.dismissed,
      ),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
