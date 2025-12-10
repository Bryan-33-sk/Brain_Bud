import 'package:shared_preferences/shared_preferences.dart';
import '../models/achievement.dart';
import '../services/usage_stats_service.dart';
import '../services/debug_log_service.dart';
import '../services/notification_service.dart';
import 'dart:convert';

/// Service for managing achievements
class AchievementService {
  static final AchievementService _instance = AchievementService._internal();
  factory AchievementService() => _instance;
  AchievementService._internal();

  List<Achievement> _achievements = [];
  bool _initialized = false;

  /// Initialize achievements from storage
  Future<void> initialize() async {
    if (_initialized) return;

    _achievements = Achievements.getAllAchievements();
    await _loadAchievements();
    _initialized = true;

    debugLog.info('AchievementService', 'Initialized ${_achievements.length} achievements');
  }

  /// Get all achievements
  List<Achievement> getAllAchievements() {
    return List.unmodifiable(_achievements);
  }

  /// Get unlocked achievements
  List<Achievement> getUnlockedAchievements() {
    return _achievements.where((a) => a.unlocked).toList();
  }

  /// Get in-progress achievements
  List<Achievement> getInProgressAchievements() {
    return _achievements.where((a) => a.isInProgress).toList();
  }

  /// Get locked achievements
  List<Achievement> getLockedAchievements() {
    return _achievements.where((a) => a.isLocked).toList();
  }

  /// Get achievement by ID
  Achievement? getAchievement(String id) {
    try {
      return _achievements.firstWhere((a) => a.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Check achievements based on current usage stats
  Future<void> checkAchievements(List<AppUsageInfo> stats) async {
    if (!_initialized) await initialize();

    final socialMediaTime = stats
        .where((app) => app.isSocialMediaApp() && !app.isSystemApp)
        .fold<int>(0, (sum, app) => sum + app.totalTimeInForeground);

    final totalScreenTime = stats
        .where((app) => !app.isSystemApp)
        .fold<int>(0, (sum, app) => sum + app.totalTimeInForeground);

    final socialMinutes = socialMediaTime ~/ (1000 * 60);
    final totalMinutes = totalScreenTime ~/ (1000 * 60);

    // Determine current mood
    final isHappy = socialMinutes < 30;
    final isZero = socialMinutes == 0;

    // Check daily achievements
    await _checkDailyAchievements(isZero, isHappy, totalMinutes);
    
    // Check streak achievements
    await _checkStreakAchievements(isHappy, isZero, socialMinutes);
    
    // Check milestone achievements
    await _checkMilestoneAchievements(isHappy, isZero);
    
    // Check reduction achievements
    await _checkReductionAchievements(socialMinutes);
    
    // Check special achievements
    await _checkSpecialAchievements(stats, socialMinutes);

    // Save updated achievements
    await _saveAchievements();
  }

  /// Check daily achievements
  Future<void> _checkDailyAchievements(bool isZero, bool isHappy, int totalMinutes) async {
    // Zero Hero
    if (isZero) {
      await _tryUnlockAchievement('zero_hero');
    }

    // Happy Hour
    if (isHappy) {
      await _tryUnlockAchievement('happy_hour');
    }

    // Focus Master
    if (totalMinutes < 60) {
      await _tryUnlockAchievement('focus_master');
    }

    // Early Bird & Mindful Morning (would need time tracking)
    // These require additional time-based tracking
  }

  /// Check streak achievements
  Future<void> _checkStreakAchievements(bool isHappy, bool isZero, int socialMinutes) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    final lastCheckDate = prefs.getString('last_streak_check_date');
    
    // Don't double-count if already checked today
    if (lastCheckDate == today) return;

    // Update streak counters
    if (isHappy) {
      final happyStreak = prefs.getInt('happy_streak') ?? 0;
      if (lastCheckDate == null || _isYesterday(lastCheckDate)) {
        // Continue streak
        await prefs.setInt('happy_streak', happyStreak + 1);
      } else {
        // Reset streak
        await prefs.setInt('happy_streak', 1);
      }
      
      // Check streak achievements
      final newStreak = prefs.getInt('happy_streak') ?? 0;
      if (newStreak >= 3) await _updateProgress('consistency_champion', newStreak);
      if (newStreak >= 7) await _updateProgress('week_warrior', newStreak);
      if (newStreak >= 30) await _updateProgress('month_master', newStreak);
    } else {
      // Reset happy streak
      await prefs.setInt('happy_streak', 0);
    }

    if (isZero) {
      final zeroStreak = prefs.getInt('zero_streak') ?? 0;
      if (lastCheckDate == null || _isYesterday(lastCheckDate)) {
        await prefs.setInt('zero_streak', zeroStreak + 1);
      } else {
        await prefs.setInt('zero_streak', 1);
      }
      
      final newZeroStreak = prefs.getInt('zero_streak') ?? 0;
      if (newZeroStreak >= 7) await _updateProgress('perfect_week', newZeroStreak);
    } else {
      await prefs.setInt('zero_streak', 0);
    }

    // Social Sabbatical (< 30 min streak)
    if (socialMinutes < 30) {
      final sabbaticalStreak = prefs.getInt('sabbatical_streak') ?? 0;
      if (lastCheckDate == null || _isYesterday(lastCheckDate)) {
        await prefs.setInt('sabbatical_streak', sabbaticalStreak + 1);
      } else {
        await prefs.setInt('sabbatical_streak', 1);
      }
      
      final newSabbaticalStreak = prefs.getInt('sabbatical_streak') ?? 0;
      if (newSabbaticalStreak >= 14) await _updateProgress('social_sabbatical', newSabbaticalStreak);
    } else {
      await prefs.setInt('sabbatical_streak', 0);
    }

    await prefs.setString('last_streak_check_date', today);
  }

  /// Check milestone achievements
  Future<void> _checkMilestoneAchievements(bool isHappy, bool isZero) async {
    final prefs = await SharedPreferences.getInstance();

    // First Step
    final firstStepAchieved = prefs.getBool('first_step_achieved') ?? false;
    if (isHappy && !firstStepAchieved) {
      await _tryUnlockAchievement('first_step');
      await prefs.setBool('first_step_achieved', true);
    }

    // Half Hour Hero (count total happy days)
    if (isHappy) {
      final happyDays = prefs.getInt('total_happy_days') ?? 0;
      await prefs.setInt('total_happy_days', happyDays + 1);
      await _updateProgress('half_hour_hero', happyDays + 1);
      await _updateProgress('century_club', happyDays + 1);
    }

    // Balance Achiever (neutral streak)
    // This would need neutral mood tracking
  }

  /// Check reduction achievements
  Future<void> _checkReductionAchievements(int socialMinutes) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Track daily social media time for comparison
    final today = DateTime.now().toIso8601String().split('T')[0];
    final weekData = prefs.getStringList('social_media_week') ?? [];
    
    // Add today's data
    weekData.add('$today:$socialMinutes');
    
    // Keep only last 7 days
    if (weekData.length > 7) {
      weekData.removeAt(0);
    }
    
    await prefs.setStringList('social_media_week', weekData);
    
    // Calculate average for reduction achievements
    if (weekData.length >= 7) {
      final total = weekData.fold<int>(0, (sum, entry) {
        final minutes = int.tryParse(entry.split(':')[1]) ?? 0;
        return sum + minutes;
      });
      final average = total ~/ 7;
      
      // Social Minimalist (< 15 min average)
      if (average < 15) {
        await _updateProgress('social_minimalist', 7);
      }
    }
  }

  /// Check special achievements
  Future<void> _checkSpecialAchievements(List<AppUsageInfo> stats, int socialMinutes) async {
    final now = DateTime.now();
    final isWeekend = now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
    
    // Weekend Warrior
    if (isWeekend && socialMinutes < 30) {
      final prefs = await SharedPreferences.getInstance();
      final weekendKey = 'weekend_${now.year}_${now.month}_${now.day ~/ 7}';
      final weekendDays = prefs.getInt(weekendKey) ?? 0;
      
      if (weekendDays == 0) {
        await prefs.setInt(weekendKey, 1);
      } else if (weekendDays == 1 && now.weekday == DateTime.sunday) {
        await _tryUnlockAchievement('weekend_warrior');
      }
    }
  }

  /// Try to unlock an achievement
  Future<void> _tryUnlockAchievement(String achievementId) async {
    final achievement = getAchievement(achievementId);
    if (achievement == null || achievement.unlocked) return;

    final index = _achievements.indexWhere((a) => a.id == achievementId);
    if (index == -1) return;

    _achievements[index] = achievement.copyWith(
      unlocked: true,
      unlockedDate: DateTime.now(),
      currentProgress: achievement.targetValue,
    );

    // Show notification
    final notificationService = NotificationService();
    await notificationService.initialize();
    
    // Create achievement unlock notification
    await _showAchievementNotification(achievement);

    debugLog.success('AchievementService', 'Unlocked: ${achievement.title}');
  }

  /// Update progress for an achievement
  Future<void> _updateProgress(String achievementId, int progress) async {
    final achievement = getAchievement(achievementId);
    if (achievement == null || achievement.unlocked) return;

    final index = _achievements.indexWhere((a) => a.id == achievementId);
    if (index == -1) return;

    final newProgress = progress.clamp(0, achievement.targetValue);
    _achievements[index] = achievement.copyWith(currentProgress: newProgress);

    // Check if should unlock
    if (newProgress >= achievement.targetValue) {
      await _tryUnlockAchievement(achievementId);
    }
  }

  /// Show achievement unlock notification
  Future<void> _showAchievementNotification(Achievement achievement) async {
    final notificationService = NotificationService();
    await notificationService.initialize();

    await notificationService.showAchievementNotification(
      title: achievement.title,
      description: achievement.description,
      icon: achievement.icon,
    );
  }

  /// Check if date string is yesterday
  bool _isYesterday(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      return date.year == yesterday.year &&
          date.month == yesterday.month &&
          date.day == yesterday.day;
    } catch (e) {
      return false;
    }
  }

  /// Load achievements from storage
  Future<void> _loadAchievements() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final achievementsJson = prefs.getString('achievements');
      
      if (achievementsJson == null) return;

      final Map<String, dynamic> achievementsMap = jsonDecode(achievementsJson);
      
      for (int i = 0; i < _achievements.length; i++) {
        final achievement = _achievements[i];
        final stored = achievementsMap[achievement.id];
        
        if (stored != null) {
          _achievements[i] = Achievement.fromMap(stored, achievement);
        }
      }
    } catch (e) {
      debugLog.error('AchievementService', 'Failed to load achievements: $e');
    }
  }

  /// Save achievements to storage
  Future<void> _saveAchievements() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> achievementsMap = {};
      
      for (final achievement in _achievements) {
        achievementsMap[achievement.id] = achievement.toMap();
      }
      
      await prefs.setString('achievements', jsonEncode(achievementsMap));
    } catch (e) {
      debugLog.error('AchievementService', 'Failed to save achievements: $e');
    }
  }

  /// Get statistics
  Map<String, dynamic> getStatistics() {
    final unlocked = getUnlockedAchievements().length;
    final total = _achievements.length;
    final inProgress = getInProgressAchievements().length;
    
    return {
      'unlocked': unlocked,
      'total': total,
      'inProgress': inProgress,
      'locked': total - unlocked - inProgress,
      'completionPercentage': total > 0 ? (unlocked / total * 100) : 0.0,
    };
  }
}

