import 'package:flutter/material.dart';
import '../services/usage_stats_service.dart';

/// App category enum for grouping
enum AppCategory {
  social,
  productivity,
  games,
  other,
}

/// Category metadata
class CategoryInfo {
  final String name;
  final IconData icon;
  final Color color;

  const CategoryInfo({
    required this.name,
    required this.icon,
    required this.color,
  });
}

/// Screen that displays apps grouped by category with total time per category
class CategoryBreakdownScreen extends StatefulWidget {
  final List<AppUsageInfo> usageStats;

  const CategoryBreakdownScreen({
    super.key,
    required this.usageStats,
  });

  @override
  State<CategoryBreakdownScreen> createState() => _CategoryBreakdownScreenState();
}

class _CategoryBreakdownScreenState extends State<CategoryBreakdownScreen> {
  // Track which categories are expanded
  final Map<AppCategory, bool> _expandedCategories = {
    AppCategory.social: true,
    AppCategory.productivity: true,
    AppCategory.games: true,
    AppCategory.other: false,
  };

  // Category metadata
  static const Map<AppCategory, CategoryInfo> _categoryInfo = {
    AppCategory.social: CategoryInfo(
      name: 'Social',
      icon: Icons.people_rounded,
      color: Color(0xFFEC4899), // Pink
    ),
    AppCategory.productivity: CategoryInfo(
      name: 'Productivity',
      icon: Icons.work_rounded,
      color: Color(0xFF3B82F6), // Blue
    ),
    AppCategory.games: CategoryInfo(
      name: 'Games',
      icon: Icons.games_rounded,
      color: Color(0xFF10B981), // Green
    ),
    AppCategory.other: CategoryInfo(
      name: 'Other',
      icon: Icons.apps_rounded,
      color: Color(0xFF8B5CF6), // Purple
    ),
  };

  /// Get the category for an app
  AppCategory _getAppCategory(AppUsageInfo app) {
    if (app.isSocialMediaApp()) return AppCategory.social;
    if (app.isProductivityApp()) return AppCategory.productivity;
    if (app.isGamingApp()) return AppCategory.games;
    return AppCategory.other;
  }

  /// Group apps by category
  Map<AppCategory, List<AppUsageInfo>> _groupAppsByCategory() {
    final Map<AppCategory, List<AppUsageInfo>> grouped = {
      AppCategory.social: [],
      AppCategory.productivity: [],
      AppCategory.games: [],
      AppCategory.other: [],
    };

    for (final app in widget.usageStats) {
      if (app.isSystemApp) continue; // Skip system apps
      final category = _getAppCategory(app);
      grouped[category]!.add(app);
    }

    // Sort apps within each category by usage time (descending)
    for (final category in grouped.keys) {
      grouped[category]!.sort((a, b) => 
        b.totalTimeInForeground.compareTo(a.totalTimeInForeground)
      );
    }

    return grouped;
  }

  /// Calculate total time for a category
  int _getCategoryTotalTime(List<AppUsageInfo> apps) {
    return apps.fold(0, (sum, app) => sum + app.totalTimeInForeground);
  }

  /// Format time in milliseconds to readable string
  String _formatTime(int totalTimeMs) {
    final hours = totalTimeMs ~/ (1000 * 60 * 60);
    final minutes = (totalTimeMs % (1000 * 60 * 60)) ~/ (1000 * 60);
    final seconds = (totalTimeMs % (1000 * 60)) ~/ 1000;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  /// Get total screen time
  int _getTotalScreenTime() {
    return widget.usageStats
        .where((app) => !app.isSystemApp)
        .fold(0, (sum, app) => sum + app.totalTimeInForeground);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final groupedApps = _groupAppsByCategory();
    final totalScreenTime = _getTotalScreenTime();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Category Breakdown',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: colorScheme.primary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Header summary card
          SliverToBoxAdapter(
            child: _buildHeaderCard(totalScreenTime, groupedApps, colorScheme),
          ),

          // Category sections
          ...AppCategory.values.map((category) {
            final apps = groupedApps[category]!;
            if (apps.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
            
            return SliverToBoxAdapter(
              child: _buildCategorySection(
                category,
                apps,
                totalScreenTime,
                colorScheme,
              ),
            );
          }),

          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(
    int totalScreenTime,
    Map<AppCategory, List<AppUsageInfo>> groupedApps,
    ColorScheme colorScheme,
  ) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary,
            colorScheme.primary.withOpacity(0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.pie_chart_rounded,
                size: 20,
                color: colorScheme.onPrimary.withOpacity(0.8),
              ),
              const SizedBox(width: 8),
              Text(
                'Usage by Category',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onPrimary.withOpacity(0.9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Category breakdown bars
          ...AppCategory.values.map((category) {
            final apps = groupedApps[category]!;
            if (apps.isEmpty) return const SizedBox.shrink();
            
            final categoryTime = _getCategoryTotalTime(apps);
            final percentage = totalScreenTime > 0 
                ? (categoryTime / totalScreenTime * 100) 
                : 0.0;
            final info = _categoryInfo[category]!;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(info.icon, size: 16, color: info.color),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: Text(
                      info.name,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onPrimary.withOpacity(0.9),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percentage / 100,
                        backgroundColor: colorScheme.onPrimary.withOpacity(0.2),
                        valueColor: AlwaysStoppedAnimation<Color>(info.color),
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 55,
                    child: Text(
                      _formatTime(categoryTime),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCategorySection(
    AppCategory category,
    List<AppUsageInfo> apps,
    int totalScreenTime,
    ColorScheme colorScheme,
  ) {
    final info = _categoryInfo[category]!;
    final categoryTime = _getCategoryTotalTime(apps);
    final isExpanded = _expandedCategories[category] ?? false;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: info.color.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Category header (tappable)
          InkWell(
            onTap: () {
              setState(() {
                _expandedCategories[category] = !isExpanded;
              });
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Category icon with colored background
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: info.color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(info.icon, color: info.color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  // Category name and app count
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          info.name,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${apps.length} ${apps.length == 1 ? 'app' : 'apps'}',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Total time
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatTime(categoryTime),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: info.color,
                        ),
                      ),
                      Text(
                        '${(categoryTime / totalScreenTime * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  // Expand/collapse icon
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Expanded app list
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                Divider(
                  height: 1,
                  color: colorScheme.outline.withOpacity(0.1),
                ),
                ...apps.asMap().entries.map((entry) {
                  final index = entry.key;
                  final app = entry.value;
                  final isLast = index == apps.length - 1;
                  
                  return _buildAppTile(app, info.color, isLast, colorScheme);
                }),
              ],
            ),
            crossFadeState: isExpanded 
                ? CrossFadeState.showSecond 
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildAppTile(
    AppUsageInfo app,
    Color categoryColor,
    bool isLast,
    ColorScheme colorScheme,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast 
            ? null 
            : Border(
                bottom: BorderSide(
                  color: colorScheme.outline.withOpacity(0.05),
                ),
              ),
      ),
      child: Row(
        children: [
          // Tree connector line
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 2,
                  height: 8,
                  color: categoryColor.withOpacity(0.3),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: categoryColor.withOpacity(0.5),
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 8,
                    color: categoryColor.withOpacity(0.3),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // App icon placeholder
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: categoryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.apps_rounded,
              color: categoryColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          // App name
          Expanded(
            child: Text(
              app.appName,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Time
          Text(
            app.formattedTime,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}

