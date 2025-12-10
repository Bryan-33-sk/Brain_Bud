/// Types of achievements
enum AchievementType {
  daily,      // One-time daily achievements
  streak,     // Consecutive days achievements
  milestone,  // Cumulative total achievements
  reduction,  // Reduction-based achievements
  special,    // Special occasion achievements
}

/// Achievement model
class Achievement {
  final String id;
  final String title;
  final String description;
  final String icon;
  final AchievementType type;
  final int targetValue;
  final int currentProgress;
  final bool unlocked;
  final DateTime? unlockedDate;
  final String? category;

  Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.type,
    required this.targetValue,
    this.currentProgress = 0,
    this.unlocked = false,
    this.unlockedDate,
    this.category,
  });

  /// Create a copy with updated progress
  Achievement copyWith({
    int? currentProgress,
    bool? unlocked,
    DateTime? unlockedDate,
  }) {
    return Achievement(
      id: id,
      title: title,
      description: description,
      icon: icon,
      type: type,
      targetValue: targetValue,
      currentProgress: currentProgress ?? this.currentProgress,
      unlocked: unlocked ?? this.unlocked,
      unlockedDate: unlockedDate ?? this.unlockedDate,
      category: category,
    );
  }

  /// Get progress percentage (0.0 to 1.0)
  double get progressPercentage {
    if (targetValue == 0) return 0.0;
    return (currentProgress / targetValue).clamp(0.0, 1.0);
  }

  /// Check if achievement is in progress (not unlocked but has progress)
  bool get isInProgress => !unlocked && currentProgress > 0;

  /// Check if achievement is locked (no progress)
  bool get isLocked => !unlocked && currentProgress == 0;

  /// Convert to map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'currentProgress': currentProgress,
      'unlocked': unlocked,
      'unlockedDate': unlockedDate?.toIso8601String(),
    };
  }

  /// Create from map
  factory Achievement.fromMap(Map<String, dynamic> map, Achievement template) {
    return template.copyWith(
      currentProgress: map['currentProgress'] ?? 0,
      unlocked: map['unlocked'] ?? false,
      unlockedDate: map['unlockedDate'] != null
          ? DateTime.parse(map['unlockedDate'])
          : null,
    );
  }
}

/// Predefined achievements list
class Achievements {
  static List<Achievement> getAllAchievements() {
    return [
      // Daily Achievements
      Achievement(
        id: 'zero_hero',
        title: 'Zero Hero',
        description: 'No social media for the entire day',
        icon: '🏆',
        type: AchievementType.daily,
        targetValue: 1,
        category: 'Daily',
      ),
      Achievement(
        id: 'happy_hour',
        title: 'Happy Hour',
        description: 'Keep Brain Bud happy all day (< 30 min social media)',
        icon: '😊',
        type: AchievementType.daily,
        targetValue: 1,
        category: 'Daily',
      ),
      Achievement(
        id: 'focus_master',
        title: 'Focus Master',
        description: 'Less than 1 hour total screen time',
        icon: '🎯',
        type: AchievementType.daily,
        targetValue: 1,
        category: 'Daily',
      ),
      Achievement(
        id: 'early_bird',
        title: 'Early Bird',
        description: 'No social media before 9 AM',
        icon: '🌅',
        type: AchievementType.daily,
        targetValue: 1,
        category: 'Daily',
      ),
      Achievement(
        id: 'mindful_morning',
        title: 'Mindful Morning',
        description: 'Less than 10 minutes social media before noon',
        icon: '☀️',
        type: AchievementType.daily,
        targetValue: 1,
        category: 'Daily',
      ),

      // Streak Achievements
      Achievement(
        id: 'consistency_champion',
        title: 'Consistency Champion',
        description: '3 days in a row with happy Brain Bud',
        icon: '⭐',
        type: AchievementType.streak,
        targetValue: 3,
        category: 'Streak',
      ),
      Achievement(
        id: 'week_warrior',
        title: 'Week Warrior',
        description: '7 days in a row with happy Brain Bud',
        icon: '💪',
        type: AchievementType.streak,
        targetValue: 7,
        category: 'Streak',
      ),
      Achievement(
        id: 'month_master',
        title: 'Month Master',
        description: '30 days in a row with happy Brain Bud',
        icon: '👑',
        type: AchievementType.streak,
        targetValue: 30,
        category: 'Streak',
      ),
      Achievement(
        id: 'perfect_week',
        title: 'Perfect Week',
        description: '7 days with zero social media',
        icon: '✨',
        type: AchievementType.streak,
        targetValue: 7,
        category: 'Streak',
      ),
      Achievement(
        id: 'social_sabbatical',
        title: 'Social Sabbatical',
        description: '14 days with < 30 min/day social media',
        icon: '🧘',
        type: AchievementType.streak,
        targetValue: 14,
        category: 'Streak',
      ),

      // Milestone Achievements
      Achievement(
        id: 'first_step',
        title: 'First Step',
        description: 'First day with < 30 min social media',
        icon: '👣',
        type: AchievementType.milestone,
        targetValue: 1,
        category: 'Milestone',
      ),
      Achievement(
        id: 'half_hour_hero',
        title: 'Half Hour Hero',
        description: '10 days total with < 30 min social media',
        icon: '⏰',
        type: AchievementType.milestone,
        targetValue: 10,
        category: 'Milestone',
      ),
      Achievement(
        id: 'century_club',
        title: 'Century Club',
        description: '100 days total with happy Brain Bud',
        icon: '💯',
        type: AchievementType.milestone,
        targetValue: 100,
        category: 'Milestone',
      ),
      Achievement(
        id: 'balance_achiever',
        title: 'Balance Achiever',
        description: 'Maintain neutral mood for 5 days straight',
        icon: '⚖️',
        type: AchievementType.milestone,
        targetValue: 5,
        category: 'Milestone',
      ),

      // Reduction Achievements
      Achievement(
        id: 'cut_in_half',
        title: 'Cut in Half',
        description: 'Reduce daily social media by 50% for a week',
        icon: '✂️',
        type: AchievementType.reduction,
        targetValue: 7,
        category: 'Reduction',
      ),
      Achievement(
        id: 'quarter_master',
        title: 'Quarter Master',
        description: 'Reduce daily social media by 75% for a week',
        icon: '📉',
        type: AchievementType.reduction,
        targetValue: 7,
        category: 'Reduction',
      ),
      Achievement(
        id: 'social_minimalist',
        title: 'Social Minimalist',
        description: 'Average < 15 min/day social media for a week',
        icon: '🌱',
        type: AchievementType.reduction,
        targetValue: 7,
        category: 'Reduction',
      ),

      // Special Achievements
      Achievement(
        id: 'weekend_warrior',
        title: 'Weekend Warrior',
        description: 'Happy Brain Bud on both weekend days',
        icon: '🏖️',
        type: AchievementType.special,
        targetValue: 1,
        category: 'Special',
      ),
      Achievement(
        id: 'night_owl',
        title: 'Night Owl',
        description: 'No social media after 10 PM for a week',
        icon: '🦉',
        type: AchievementType.special,
        targetValue: 7,
        category: 'Special',
      ),
      Achievement(
        id: 'break_master',
        title: 'Break Master',
        description: 'No 1+ hour continuous social media sessions',
        icon: '⏸️',
        type: AchievementType.special,
        targetValue: 7,
        category: 'Special',
      ),
    ];
  }
}

