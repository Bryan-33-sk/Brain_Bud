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

    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    final lastCheckDate = prefs.getString('last_achievement_check_date');
    
    // Fix #2: Prevent multiple checks per day
    if (lastCheckDate == today) {
      debugLog.info('AchievementService', 'Achievements already checked today, skipping');
      return;
    }

    // Store session data for time-based achievements (Fix #4, #6)
    await storeSocialMediaSessions(stats);

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
    final isNeutral = socialMinutes >= 30 && socialMinutes < 120;

    // Check if it's end of day (after 11 PM) or checking yesterday's data
    final now = DateTime.now();
    final isEndOfDay = now.hour >= 23 || _isCheckingYesterday(lastCheckDate, today);

    // Check daily achievements (only at end of day)
    if (isEndOfDay) {
      await _checkDailyAchievements(isZero, isHappy, totalMinutes);
    }
    
    // Check streak achievements
    await _checkStreakAchievements(isHappy, isZero, isNeutral, socialMinutes);
    
    // Check milestone achievements
    await _checkMilestoneAchievements(isHappy, isZero, isNeutral);
    
    // Check reduction achievements
    await _checkReductionAchievements(socialMinutes);
    
    // Check special achievements
    await _checkSpecialAchievements(stats, socialMinutes);

    // Mark as checked today
    await prefs.setString('last_achievement_check_date', today);

    // Save updated achievements
    await _saveAchievements();
  }

  /// Check if we're checking yesterday's data (first check of new day)
  bool _isCheckingYesterday(String? lastCheckDate, String today) {
    if (lastCheckDate == null) return false;
    try {
      final lastDate = DateTime.parse(lastCheckDate);
      final todayDate = DateTime.parse(today);
      return todayDate.difference(lastDate).inDays == 1;
    } catch (e) {
      return false;
    }
  }

  /// Check daily achievements (only called at end of day)
  Future<void> _checkDailyAchievements(bool isZero, bool isHappy, int totalMinutes) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    
    // Fix #1: Only check daily achievements once per day at end of day
    final dailyCheckKey = 'daily_achievements_checked_$today';
    if (prefs.getBool(dailyCheckKey) == true) {
      return; // Already checked today
    }

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

    // Early Bird - Check if no social media before 9 AM (Fix #4)
    final earlyBirdData = prefs.getString('early_bird_$today');
    if (earlyBirdData == null || earlyBirdData == 'true') {
      // Check if any social media usage before 9 AM
      final hasSocialBefore9AM = await _hasSocialMediaBeforeTime(9, 0);
      if (!hasSocialBefore9AM && isZero) {
        await _tryUnlockAchievement('early_bird');
      }
      await prefs.setString('early_bird_$today', hasSocialBefore9AM ? 'false' : 'true');
    }

    // Mindful Morning - Less than 10 minutes before noon (Fix #4)
    final mindfulMorningData = prefs.getString('mindful_morning_$today');
    if (mindfulMorningData == null) {
      final morningMinutes = await _getSocialMediaMinutesBeforeTime(12, 0);
      if (morningMinutes < 10) {
        await _tryUnlockAchievement('mindful_morning');
      }
      await prefs.setString('mindful_morning_$today', morningMinutes.toString());
    }

    // Mark daily achievements as checked for today
    await prefs.setBool(dailyCheckKey, true);
  }

  /// Check if social media was used before a specific time (Fix #4)
  Future<bool> _hasSocialMediaBeforeTime(int hour, int minute) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    
    // Get stored session data for today
    final sessionsJson = prefs.getString('social_sessions_$today');
    if (sessionsJson == null) {
      // No session data yet - would need to query native side
      // For now, return false (no usage before time)
      return false;
    }
    
    try {
      final List<dynamic> sessions = jsonDecode(sessionsJson);
      final cutoffTime = DateTime.now().copyWith(hour: hour, minute: minute, second: 0, millisecond: 0);
      
      for (final session in sessions) {
        final startTime = DateTime.fromMillisecondsSinceEpoch(session['startTime'] as int);
        if (startTime.isBefore(cutoffTime)) {
          return true;
        }
      }
      return false;
    } catch (e) {
      debugLog.error('AchievementService', 'Failed to parse session data: $e');
      return false;
    }
  }

  /// Get total social media minutes before a specific time (Fix #4)
  Future<int> _getSocialMediaMinutesBeforeTime(int hour, int minute) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    
    // Get stored session data for today
    final sessionsJson = prefs.getString('social_sessions_$today');
    if (sessionsJson == null) {
      return 0;
    }
    
    try {
      final List<dynamic> sessions = jsonDecode(sessionsJson);
      final cutoffTime = DateTime.now().copyWith(hour: hour, minute: minute, second: 0, millisecond: 0);
      int totalMinutes = 0;
      
      for (final session in sessions) {
        final startTime = DateTime.fromMillisecondsSinceEpoch(session['startTime'] as int);
        final endTime = DateTime.fromMillisecondsSinceEpoch(session['endTime'] as int);
        
        // Only count sessions that started before cutoff
        if (startTime.isBefore(cutoffTime)) {
          // Clip end time to cutoff if session extends past it
          final effectiveEndTime = endTime.isBefore(cutoffTime) ? endTime : cutoffTime;
          final duration = effectiveEndTime.difference(startTime);
          totalMinutes += duration.inMinutes;
        }
      }
      return totalMinutes;
    } catch (e) {
      debugLog.error('AchievementService', 'Failed to parse session data: $e');
      return 0;
    }
  }

  /// Check streak achievements
  Future<void> _checkStreakAchievements(bool isHappy, bool isZero, bool isNeutral, int socialMinutes) async {
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

    // Balance Achiever (neutral streak) - Fix #5
    if (isNeutral) {
      final neutralStreak = prefs.getInt('neutral_streak') ?? 0;
      if (lastCheckDate == null || _isYesterday(lastCheckDate)) {
        await prefs.setInt('neutral_streak', neutralStreak + 1);
      } else {
        await prefs.setInt('neutral_streak', 1);
      }
      
      final newNeutralStreak = prefs.getInt('neutral_streak') ?? 0;
      if (newNeutralStreak >= 5) await _updateProgress('balance_achiever', newNeutralStreak);
    } else {
      await prefs.setInt('neutral_streak', 0);
    }

    await prefs.setString('last_streak_check_date', today);
  }

  /// Check milestone achievements
  Future<void> _checkMilestoneAchievements(bool isHappy, bool isZero, bool isNeutral) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];

    // First Step
    final firstStepAchieved = prefs.getBool('first_step_achieved') ?? false;
    if (isHappy && !firstStepAchieved) {
      await _tryUnlockAchievement('first_step');
      await prefs.setBool('first_step_achieved', true);
    }

    // Half Hour Hero (count total happy days) - only increment once per day
    if (isHappy) {
      final lastHappyDayCheck = prefs.getString('last_happy_day_check');
      if (lastHappyDayCheck != today) {
        final happyDays = prefs.getInt('total_happy_days') ?? 0;
        await prefs.setInt('total_happy_days', happyDays + 1);
        await prefs.setString('last_happy_day_check', today);
        await _updateProgress('half_hour_hero', happyDays + 1);
        await _updateProgress('century_club', happyDays + 1);
      }
    }

    // Balance Achiever is now handled in streak achievements
  }

  /// Check reduction achievements
  Future<void> _checkReductionAchievements(int socialMinutes) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Track daily social media time for comparison
    final today = DateTime.now().toIso8601String().split('T')[0];
    final weekData = prefs.getStringList('social_media_week') ?? [];
    
    // Check if today's data already added
    final todayEntry = '$today:';
    final hasToday = weekData.any((entry) => entry.startsWith(todayEntry));
    
    if (!hasToday) {
      // Add today's data
      weekData.add('$today:$socialMinutes');
      
      // Keep only last 7 days
      if (weekData.length > 7) {
        weekData.removeAt(0);
      }
      
      await prefs.setStringList('social_media_week', weekData);
    }
    
    // Fix #3: Social Minimalist - track incremental progress (1-7 days)
    if (weekData.length >= 7) {
      // Count how many days qualify (< 15 min)
      int qualifyingDays = 0;
      for (final entry in weekData) {
        final minutes = int.tryParse(entry.split(':')[1]) ?? 0;
        if (minutes < 15) {
          qualifyingDays++;
        }
      }
      
      // Update progress incrementally
      if (qualifyingDays > 0) {
        await _updateProgress('social_minimalist', qualifyingDays);
      }
    }
    
    // Calculate baseline for reduction achievements (Fix #7)
    final baselineSet = prefs.getBool('baseline_average_set') ?? false;
    if (!baselineSet && weekData.length >= 7) {
      // Calculate baseline from first 7 days
      final total = weekData.fold<int>(0, (sum, entry) {
        final minutes = int.tryParse(entry.split(':')[1]) ?? 0;
        return sum + minutes;
      });
      final baselineAverage = total ~/ 7;
      await prefs.setInt('baseline_average', baselineAverage);
      await prefs.setBool('baseline_average_set', true);
      debugLog.info('AchievementService', 'Baseline average set: $baselineAverage minutes');
    }
    
    // Check reduction achievements (Fix #7)
    if (baselineSet && weekData.length >= 7) {
      final baselineAverage = prefs.getInt('baseline_average') ?? 0;
      if (baselineAverage > 0) {
        final total = weekData.fold<int>(0, (sum, entry) {
          final minutes = int.tryParse(entry.split(':')[1]) ?? 0;
          return sum + minutes;
        });
        final currentAverage = total ~/ 7;
        
        // Track qualifying days for reduction achievements
        int reduction50Days = prefs.getInt('reduction_50_days') ?? 0;
        int reduction75Days = prefs.getInt('reduction_75_days') ?? 0;
        
        // Check if current week qualifies
        if (currentAverage <= baselineAverage * 0.5) {
          // 50% reduction achieved this week
          if (reduction50Days < 7) {
            reduction50Days++;
            await prefs.setInt('reduction_50_days', reduction50Days);
            await _updateProgress('cut_in_half', reduction50Days);
          }
        } else {
          // Reset if week doesn't qualify
          await prefs.setInt('reduction_50_days', 0);
        }
        
        if (currentAverage <= baselineAverage * 0.25) {
          // 75% reduction achieved this week
          if (reduction75Days < 7) {
            reduction75Days++;
            await prefs.setInt('reduction_75_days', reduction75Days);
            await _updateProgress('quarter_master', reduction75Days);
          }
        } else {
          // Reset if week doesn't qualify
          await prefs.setInt('reduction_75_days', 0);
        }
      }
    }
  }

  /// Check special achievements
  Future<void> _checkSpecialAchievements(List<AppUsageInfo> stats, int socialMinutes) async {
    final now = DateTime.now();
    final isWeekend = now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    
    // Weekend Warrior
    if (isWeekend && socialMinutes < 30) {
      final weekendKey = 'weekend_${now.year}_${now.month}_${now.day ~/ 7}';
      final weekendDays = prefs.getInt(weekendKey) ?? 0;
      
      if (weekendDays == 0) {
        await prefs.setInt(weekendKey, 1);
      } else if (weekendDays == 1 && now.weekday == DateTime.sunday) {
        await _tryUnlockAchievement('weekend_warrior');
      }
    }

    // Night Owl - No social media after 10 PM for a week (Fix #4)
    final nightOwlKey = 'night_owl_week';
    final nightOwlData = prefs.getStringList(nightOwlKey) ?? [];
    
    // Check if today qualifies (no social media after 10 PM)
    final hasSocialAfter10PM = await _hasSocialMediaAfterTime(22, 0);
    if (!hasSocialAfter10PM) {
      // Add today if not already added
      if (!nightOwlData.contains(today)) {
        nightOwlData.add(today);
        // Keep only last 7 days
        if (nightOwlData.length > 7) {
          nightOwlData.removeAt(0);
        }
        await prefs.setStringList(nightOwlKey, nightOwlData);
        
        // Check if 7 consecutive days achieved
        if (nightOwlData.length >= 7) {
          await _updateProgress('night_owl', nightOwlData.length);
        }
      }
    } else {
      // Reset if today doesn't qualify
      await prefs.setStringList(nightOwlKey, []);
    }

    // Break Master - No 1+ hour continuous sessions (Fix #6)
    final breakMasterKey = 'break_master_week';
    final breakMasterData = prefs.getStringList(breakMasterKey) ?? [];
    
    // Check if today qualifies (no sessions >= 60 minutes)
    final hasLongSession = await _hasLongSocialMediaSession(60);
    if (!hasLongSession) {
      // Add today if not already added
      if (!breakMasterData.contains(today)) {
        breakMasterData.add(today);
        // Keep only last 7 days
        if (breakMasterData.length > 7) {
          breakMasterData.removeAt(0);
        }
        await prefs.setStringList(breakMasterKey, breakMasterData);
        
        // Check if 7 consecutive days achieved
        if (breakMasterData.length >= 7) {
          await _updateProgress('break_master', breakMasterData.length);
        }
      }
    } else {
      // Reset if today doesn't qualify
      await prefs.setStringList(breakMasterKey, []);
    }
  }

  /// Check if social media was used after a specific time (Fix #4)
  Future<bool> _hasSocialMediaAfterTime(int hour, int minute) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    
    // Get stored session data for today
    final sessionsJson = prefs.getString('social_sessions_$today');
    if (sessionsJson == null) {
      return false;
    }
    
    try {
      final List<dynamic> sessions = jsonDecode(sessionsJson);
      final cutoffTime = DateTime.now().copyWith(hour: hour, minute: minute, second: 0, millisecond: 0);
      
      for (final session in sessions) {
        final startTime = DateTime.fromMillisecondsSinceEpoch(session['startTime'] as int);
        if (startTime.isAfter(cutoffTime) || startTime.isAtSameMomentAs(cutoffTime)) {
          return true;
        }
      }
      return false;
    } catch (e) {
      debugLog.error('AchievementService', 'Failed to parse session data: $e');
      return false;
    }
  }

  /// Check if there's a social media session longer than specified minutes (Fix #6)
  Future<bool> _hasLongSocialMediaSession(int maxMinutes) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    
    // Get stored session data for today
    final sessionsJson = prefs.getString('social_sessions_$today');
    if (sessionsJson == null) {
      return false;
    }
    
    try {
      final List<dynamic> sessions = jsonDecode(sessionsJson);
      
      for (final session in sessions) {
        final startTime = DateTime.fromMillisecondsSinceEpoch(session['startTime'] as int);
        final endTime = DateTime.fromMillisecondsSinceEpoch(session['endTime'] as int);
        final duration = endTime.difference(startTime);
        
        if (duration.inMinutes >= maxMinutes) {
          return true;
        }
      }
      return false;
    } catch (e) {
      debugLog.error('AchievementService', 'Failed to parse session data: $e');
      return false;
    }
  }

  /// Store social media session data (to be called from usage stats service)
  /// This method should be called when processing usage stats to extract session data
  Future<void> storeSocialMediaSessions(List<AppUsageInfo> stats) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    
    // Extract session data from stats
    // Note: This is a simplified version - ideally the native side would provide session-level data
    final List<Map<String, dynamic>> sessions = [];
    
    for (final app in stats) {
      if (app.isSocialMediaApp() && !app.isSystemApp && app.totalTimeInForeground > 0) {
        // Estimate session: use lastTimeUsed as end, calculate start
        // This is approximate - real implementation would track actual RESUMED/PAUSED events
        final endTime = DateTime.fromMillisecondsSinceEpoch(app.lastTimeUsed);
        final startTime = endTime.subtract(Duration(milliseconds: app.totalTimeInForeground));
        
        sessions.add({
          'packageName': app.packageName,
          'appName': app.appName,
          'startTime': startTime.millisecondsSinceEpoch,
          'endTime': endTime.millisecondsSinceEpoch,
          'duration': app.totalTimeInForeground,
        });
      }
    }
    
    // Store sessions for today
    await prefs.setString('social_sessions_$today', jsonEncode(sessions));
    debugLog.info('AchievementService', 'Stored ${sessions.length} social media sessions for $today');
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

