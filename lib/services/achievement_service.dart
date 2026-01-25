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

    debugLog.info('AchievementService',
        'Initialized ${_achievements.length} achievements');
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
  /// 
  /// IMPORTANT: Achievements are ONLY evaluated at end of day (9 PM or later)
  /// to ensure we have complete data for the day. This prevents false positives
  /// from checking at the start of the day when stats are 0.
  Future<void> checkAchievements(List<AppUsageInfo> stats) async {
    if (!_initialized) await initialize();

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = now.toIso8601String().split('T')[0];
    
    // Always store session data for time-based achievements
    await storeSocialMediaSessions(stats);

    // Calculate stats
    final socialMediaTime = stats
        .where((app) => app.isSocialMediaApp() && !app.isSystemApp)
        .fold<int>(0, (sum, app) => sum + app.totalTimeInForeground);

    final totalScreenTime = stats
        .where((app) => !app.isSystemApp)
        .fold<int>(0, (sum, app) => sum + app.totalTimeInForeground);

    final socialMinutes = socialMediaTime ~/ (1000 * 60);
    final totalMinutes = totalScreenTime ~/ (1000 * 60);

    // ============================================================
    // GATE 1: Time of day check
    // Only evaluate achievements after 9 PM when day data is complete
    // ============================================================
    final isEndOfDay = now.hour >= 21; // 9 PM or later
    
    if (!isEndOfDay) {
      debugLog.info('AchievementService', 
          'Not end of day yet (${now.hour}:00). Achievements will be evaluated after 9 PM.');
      return;
    }

    // ============================================================
    // GATE 2: Already evaluated today check
    // Prevent re-evaluation once achievements have been scored for the day
    // ============================================================
    final evaluatedToday = prefs.getString('achievements_evaluated_date') == today;
    
    if (evaluatedToday) {
      debugLog.info('AchievementService', 
          'Achievements already evaluated today, skipping');
      return;
    }

    // ============================================================
    // GATE 3: Minimum activity threshold
    // Don't evaluate if less than 10 minutes total screen time
    // (indicates the user hasn't really used their phone today)
    // ============================================================
    if (totalMinutes < 10) {
      debugLog.info('AchievementService', 
          'Total screen time too low ($totalMinutes min). Skipping achievement evaluation.');
      return;
    }

    debugLog.info('AchievementService', 
        'Evaluating achievements for $today (social: ${socialMinutes}m, total: ${totalMinutes}m)');

    // Determine current mood based on COMPLETE day data
    final isHappy = socialMinutes < 30;
    final isZero = socialMinutes == 0;
    final isNeutral = socialMinutes >= 30 && socialMinutes < 120;

    // Check all achievement categories
    await _checkDailyAchievements(isZero, isHappy, totalMinutes);
    await _checkStreakAchievements(isHappy, isZero, isNeutral, socialMinutes);
    await _checkMilestoneAchievements(isHappy, isZero, isNeutral);
    await _checkReductionAchievements(socialMinutes);
    await _checkSpecialAchievements(stats, socialMinutes);

    // Mark as evaluated for today (prevents re-evaluation)
    await prefs.setString('achievements_evaluated_date', today);

    // Save updated achievements
    await _saveAchievements();
    
    debugLog.success('AchievementService', 'Achievement evaluation complete for $today');
  }

  /// Check daily achievements
  /// Called only at end of day (9 PM+) with complete day data
  Future<void> _checkDailyAchievements(
      bool isZero, bool isHappy, int totalMinutes) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];

    debugLog.info('AchievementService', 
        'Checking daily achievements: isZero=$isZero, isHappy=$isHappy, totalMinutes=$totalMinutes');

    // ============ ZERO HERO (0 social media all day) ============
    if (isZero) {
      debugLog.info('AchievementService', '🏆 Zero Hero condition met!');
      await _tryUnlockAchievement('zero_hero');
    }

    // ============ HAPPY HOUR (< 30 min social media) ============
    if (isHappy) {
      debugLog.info('AchievementService', '😊 Happy Hour condition met!');
      await _tryUnlockAchievement('happy_hour');
    }

    // ============ FOCUS MASTER (< 60 min total screen time) ============
    if (totalMinutes < 60) {
      debugLog.info('AchievementService', '🎯 Focus Master condition met!');
      await _tryUnlockAchievement('focus_master');
    }

    // ============ EARLY BIRD (no social media before 9 AM) ============
    final hasSocialBefore9AM = await _hasSocialMediaBeforeTime(9, 0);
    if (!hasSocialBefore9AM) {
      debugLog.info('AchievementService', '🌅 Early Bird condition met!');
      await _tryUnlockAchievement('early_bird');
    }

    // ============ MINDFUL MORNING (< 10 min social media before noon) ============
    final morningMinutes = await _getSocialMediaMinutesBeforeTime(12, 0);
    if (morningMinutes < 10) {
      debugLog.info('AchievementService', '☀️ Mindful Morning condition met! (${morningMinutes}m before noon)');
      await _tryUnlockAchievement('mindful_morning');
    }
    
    // Store today's data for debugging
    await prefs.setString('daily_check_$today', 
        'isZero=$isZero, isHappy=$isHappy, total=$totalMinutes, morning=$morningMinutes, before9am=$hasSocialBefore9AM');
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
      final cutoffTime = DateTime.now()
          .copyWith(hour: hour, minute: minute, second: 0, millisecond: 0);

      for (final session in sessions) {
        final startTime =
            DateTime.fromMillisecondsSinceEpoch(session['startTime'] as int);
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
      final cutoffTime = DateTime.now()
          .copyWith(hour: hour, minute: minute, second: 0, millisecond: 0);
      int totalMinutes = 0;

      for (final session in sessions) {
        final startTime =
            DateTime.fromMillisecondsSinceEpoch(session['startTime'] as int);
        final endTime =
            DateTime.fromMillisecondsSinceEpoch(session['endTime'] as int);

        // Only count sessions that started before cutoff
        if (startTime.isBefore(cutoffTime)) {
          // Clip end time to cutoff if session extends past it
          final effectiveEndTime =
              endTime.isBefore(cutoffTime) ? endTime : cutoffTime;
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
  /// Called only at end of day (9 PM+) with complete day data
  Future<void> _checkStreakAchievements(
      bool isHappy, bool isZero, bool isNeutral, int socialMinutes) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    final lastStreakDate = prefs.getString('last_streak_check_date');

    // Determine if this is a consecutive day (yesterday was last check)
    final isConsecutive = lastStreakDate != null && _isYesterday(lastStreakDate);
    final isFirstCheck = lastStreakDate == null;

    debugLog.info('AchievementService', 
        'Checking streaks: isHappy=$isHappy, isZero=$isZero, isConsecutive=$isConsecutive');

    // ============ HAPPY STREAK (< 30 min social media) ============
    if (isHappy) {
      final currentStreak = prefs.getInt('happy_streak') ?? 0;
      int newStreak;
      
      if (isFirstCheck || isConsecutive) {
        newStreak = currentStreak + 1; // Continue or start streak
      } else {
        newStreak = 1; // Missed a day, restart at 1
      }
      
      await prefs.setInt('happy_streak', newStreak);
      debugLog.info('AchievementService', 'Happy streak: $currentStreak → $newStreak');

      // Check streak milestones
      if (newStreak >= 3) await _updateProgress('consistency_champion', newStreak);
      if (newStreak >= 7) await _updateProgress('week_warrior', newStreak);
      if (newStreak >= 30) await _updateProgress('month_master', newStreak);
    } else {
      // Not happy today - reset streak
      final oldStreak = prefs.getInt('happy_streak') ?? 0;
      if (oldStreak > 0) {
        debugLog.info('AchievementService', 'Happy streak broken (was $oldStreak)');
      }
      await prefs.setInt('happy_streak', 0);
    }

    // ============ ZERO STREAK (0 min social media) ============
    if (isZero) {
      final currentStreak = prefs.getInt('zero_streak') ?? 0;
      int newStreak;
      
      if (isFirstCheck || isConsecutive) {
        newStreak = currentStreak + 1;
      } else {
        newStreak = 1;
      }
      
      await prefs.setInt('zero_streak', newStreak);
      debugLog.info('AchievementService', 'Zero streak: $newStreak');

      if (newStreak >= 7) await _updateProgress('perfect_week', newStreak);
    } else {
      await prefs.setInt('zero_streak', 0);
    }

    // ============ SABBATICAL STREAK (< 30 min social media) ============
    if (socialMinutes < 30) {
      final currentStreak = prefs.getInt('sabbatical_streak') ?? 0;
      int newStreak;
      
      if (isFirstCheck || isConsecutive) {
        newStreak = currentStreak + 1;
      } else {
        newStreak = 1;
      }
      
      await prefs.setInt('sabbatical_streak', newStreak);

      if (newStreak >= 14) await _updateProgress('social_sabbatical', newStreak);
    } else {
      await prefs.setInt('sabbatical_streak', 0);
    }

    // ============ NEUTRAL STREAK (30-120 min social media) ============
    if (isNeutral) {
      final currentStreak = prefs.getInt('neutral_streak') ?? 0;
      int newStreak;
      
      if (isFirstCheck || isConsecutive) {
        newStreak = currentStreak + 1;
      } else {
        newStreak = 1;
      }
      
      await prefs.setInt('neutral_streak', newStreak);

      if (newStreak >= 5) await _updateProgress('balance_achiever', newStreak);
    } else {
      await prefs.setInt('neutral_streak', 0);
    }

    // Mark today as checked for streak purposes
    await prefs.setString('last_streak_check_date', today);
  }

  /// Check milestone achievements
  /// Called only at end of day (9 PM+) with complete day data
  Future<void> _checkMilestoneAchievements(
      bool isHappy, bool isZero, bool isNeutral) async {
    final prefs = await SharedPreferences.getInstance();

    debugLog.info('AchievementService', 'Checking milestone achievements');

    // ============ FIRST STEP (first happy day ever) ============
    if (isHappy) {
      final firstStepAchieved = prefs.getBool('first_step_achieved') ?? false;
      if (!firstStepAchieved) {
        debugLog.info('AchievementService', '👣 First Step - First happy day achieved!');
        await _tryUnlockAchievement('first_step');
        await prefs.setBool('first_step_achieved', true);
      }
    }

    // ============ HALF HOUR HERO & CENTURY CLUB (cumulative happy days) ============
    // These are incremented once per day when isHappy is true
    if (isHappy) {
      // Use the main evaluation date to prevent double-counting
      // (already gated by achievements_evaluated_date in parent method)
      final happyDays = (prefs.getInt('total_happy_days') ?? 0) + 1;
      await prefs.setInt('total_happy_days', happyDays);
      
      debugLog.info('AchievementService', 'Total happy days: $happyDays');
      
      await _updateProgress('half_hour_hero', happyDays);
      await _updateProgress('century_club', happyDays);
    }

    // Note: Balance Achiever is handled in streak achievements (neutral streak)
  }

  /// Check reduction achievements
  /// Called only at end of day (9 PM+) with complete day data
  Future<void> _checkReductionAchievements(int socialMinutes) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    
    debugLog.info('AchievementService', 'Checking reduction achievements (social: ${socialMinutes}m)');

    // ============ TRACK DAILY DATA ============
    // Store today's social media time for weekly analysis
    final weekData = prefs.getStringList('social_media_week') ?? [];
    
    // Remove any existing entry for today (in case of re-evaluation)
    weekData.removeWhere((entry) => entry.startsWith('$today:'));
    
    // Add today's complete data
    weekData.add('$today:$socialMinutes');

    // Keep only last 7 days (remove oldest if needed)
    while (weekData.length > 7) {
      weekData.removeAt(0);
    }

    await prefs.setStringList('social_media_week', weekData);
    debugLog.info('AchievementService', 'Week data: ${weekData.length} days tracked');

    // ============ SOCIAL MINIMALIST (< 15 min for 7 days) ============
    if (weekData.length >= 7) {
      int qualifyingDays = 0;
      for (final entry in weekData) {
        final parts = entry.split(':');
        if (parts.length >= 2) {
          final minutes = int.tryParse(parts[1]) ?? 999;
          if (minutes < 15) {
            qualifyingDays++;
          }
        }
      }

      debugLog.info('AchievementService', 'Social Minimalist: $qualifyingDays/7 days < 15min');
      if (qualifyingDays > 0) {
        await _updateProgress('social_minimalist', qualifyingDays);
      }
    }

    // ============ BASELINE CALCULATION ============
    // Set baseline from first 7 days of tracking
    final baselineSet = prefs.getBool('baseline_average_set') ?? false;
    if (!baselineSet && weekData.length >= 7) {
      int total = 0;
      for (final entry in weekData) {
        final parts = entry.split(':');
        if (parts.length >= 2) {
          total += int.tryParse(parts[1]) ?? 0;
        }
      }
      final baselineAverage = total ~/ 7;
      await prefs.setInt('baseline_average', baselineAverage);
      await prefs.setBool('baseline_average_set', true);
      debugLog.info('AchievementService', 'Baseline average set: ${baselineAverage}m/day');
    }

    // ============ CUT IN HALF & QUARTER MASTER ============
    // Compare current week average to baseline
    final baselineAverage = prefs.getInt('baseline_average') ?? 0;
    if (baselineSet && baselineAverage > 0 && weekData.length >= 7) {
      int total = 0;
      for (final entry in weekData) {
        final parts = entry.split(':');
        if (parts.length >= 2) {
          total += int.tryParse(parts[1]) ?? 0;
        }
      }
      final currentAverage = total ~/ 7;

      debugLog.info('AchievementService', 
          'Reduction check: baseline=${baselineAverage}m, current=${currentAverage}m');

      // 50% reduction check
      if (currentAverage <= baselineAverage * 0.5) {
        final reduction50Days = (prefs.getInt('reduction_50_days') ?? 0) + 1;
        await prefs.setInt('reduction_50_days', reduction50Days);
        await _updateProgress('cut_in_half', reduction50Days.clamp(0, 7));
        debugLog.info('AchievementService', 'Cut in Half progress: $reduction50Days/7');
      } else {
        await prefs.setInt('reduction_50_days', 0);
      }

      // 75% reduction check
      if (currentAverage <= baselineAverage * 0.25) {
        final reduction75Days = (prefs.getInt('reduction_75_days') ?? 0) + 1;
        await prefs.setInt('reduction_75_days', reduction75Days);
        await _updateProgress('quarter_master', reduction75Days.clamp(0, 7));
        debugLog.info('AchievementService', 'Quarter Master progress: $reduction75Days/7');
      } else {
        await prefs.setInt('reduction_75_days', 0);
      }
    }
  }

  /// Check special achievements
  /// Called only at end of day (9 PM+) with complete day data
  Future<void> _checkSpecialAchievements(
      List<AppUsageInfo> stats, int socialMinutes) async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final today = now.toIso8601String().split('T')[0];
    final isHappy = socialMinutes < 30;

    debugLog.info('AchievementService', 'Checking special achievements');

    // ============ WEEKEND WARRIOR (happy on both weekend days) ============
    final isWeekend = now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
    
    if (isWeekend && isHappy) {
      // Get the week identifier (year + week number)
      final weekNumber = _getWeekNumber(now);
      final weekendKey = 'weekend_${now.year}_$weekNumber';
      
      if (now.weekday == DateTime.saturday) {
        // Saturday - mark as happy
        await prefs.setBool('${weekendKey}_sat', true);
        debugLog.info('AchievementService', 'Weekend Warrior: Saturday happy ✓');
      } else if (now.weekday == DateTime.sunday) {
        // Sunday - check if Saturday was also happy
        final saturdayWasHappy = prefs.getBool('${weekendKey}_sat') ?? false;
        if (saturdayWasHappy) {
          debugLog.info('AchievementService', '🏖️ Weekend Warrior unlocked!');
          await _tryUnlockAchievement('weekend_warrior');
        }
      }
    } else if (isWeekend && !isHappy) {
      // Weekend but not happy - mark this weekend as failed
      final weekNumber = _getWeekNumber(now);
      final weekendKey = 'weekend_${now.year}_$weekNumber';
      await prefs.setBool('${weekendKey}_sat', false);
    }

    // ============ NIGHT OWL (no social media after 10 PM for 7 days) ============
    const nightOwlKey = 'night_owl_week';
    final nightOwlData = prefs.getStringList(nightOwlKey) ?? [];
    final hasSocialAfter10PM = await _hasSocialMediaAfterTime(22, 0);

    // Remove today if it exists (to update with latest data)
    nightOwlData.remove(today);

    if (!hasSocialAfter10PM) {
      nightOwlData.add(today);
      debugLog.info('AchievementService', 'Night Owl: Today qualifies ✓');
      
      // Check for consecutive days
      final consecutiveDays = _countConsecutiveDays(nightOwlData);
      if (consecutiveDays >= 7) {
        debugLog.info('AchievementService', '🦉 Night Owl unlocked!');
        await _updateProgress('night_owl', consecutiveDays);
      }
    } else {
      debugLog.info('AchievementService', 'Night Owl: Had social media after 10 PM, resetting');
      nightOwlData.clear(); // Reset streak
    }

    // Keep only last 14 days of data
    while (nightOwlData.length > 14) {
      nightOwlData.removeAt(0);
    }
    await prefs.setStringList(nightOwlKey, nightOwlData);

    // ============ BREAK MASTER (no 1+ hour sessions for 7 days) ============
    const breakMasterKey = 'break_master_week';
    final breakMasterData = prefs.getStringList(breakMasterKey) ?? [];
    final hasLongSession = await _hasLongSocialMediaSession(60);

    // Remove today if it exists
    breakMasterData.remove(today);

    if (!hasLongSession) {
      breakMasterData.add(today);
      debugLog.info('AchievementService', 'Break Master: Today qualifies ✓');
      
      final consecutiveDays = _countConsecutiveDays(breakMasterData);
      if (consecutiveDays >= 7) {
        debugLog.info('AchievementService', '⏸️ Break Master unlocked!');
        await _updateProgress('break_master', consecutiveDays);
      }
    } else {
      debugLog.info('AchievementService', 'Break Master: Had 1+ hour session, resetting');
      breakMasterData.clear(); // Reset streak
    }

    // Keep only last 14 days of data
    while (breakMasterData.length > 14) {
      breakMasterData.removeAt(0);
    }
    await prefs.setStringList(breakMasterKey, breakMasterData);
  }

  /// Get ISO week number for a date
  int _getWeekNumber(DateTime date) {
    final firstDayOfYear = DateTime(date.year, 1, 1);
    final dayOfYear = date.difference(firstDayOfYear).inDays;
    return ((dayOfYear - date.weekday + 10) / 7).floor();
  }

  /// Count consecutive days in a list of date strings (most recent)
  int _countConsecutiveDays(List<String> dates) {
    if (dates.isEmpty) return 0;
    
    // Sort dates in descending order (most recent first)
    final sortedDates = List<String>.from(dates)..sort((a, b) => b.compareTo(a));
    
    int consecutiveCount = 1;
    DateTime? previousDate;
    
    for (final dateStr in sortedDates) {
      try {
        final date = DateTime.parse(dateStr);
        if (previousDate == null) {
          previousDate = date;
          continue;
        }
        
        final difference = previousDate.difference(date).inDays;
        if (difference == 1) {
          consecutiveCount++;
          previousDate = date;
        } else {
          break; // Streak broken
        }
      } catch (e) {
        continue;
      }
    }
    
    return consecutiveCount;
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
      final cutoffTime = DateTime.now()
          .copyWith(hour: hour, minute: minute, second: 0, millisecond: 0);

      for (final session in sessions) {
        final startTime =
            DateTime.fromMillisecondsSinceEpoch(session['startTime'] as int);
        if (startTime.isAfter(cutoffTime) ||
            startTime.isAtSameMomentAs(cutoffTime)) {
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
        final startTime =
            DateTime.fromMillisecondsSinceEpoch(session['startTime'] as int);
        final endTime =
            DateTime.fromMillisecondsSinceEpoch(session['endTime'] as int);
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
      if (app.isSocialMediaApp() &&
          !app.isSystemApp &&
          app.totalTimeInForeground > 0) {
        // Estimate session: use lastTimeUsed as end, calculate start
        // This is approximate - real implementation would track actual RESUMED/PAUSED events
        final endTime = DateTime.fromMillisecondsSinceEpoch(app.lastTimeUsed);
        final startTime =
            endTime.subtract(Duration(milliseconds: app.totalTimeInForeground));

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
    debugLog.info('AchievementService',
        'Stored ${sessions.length} social media sessions for $today');
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
