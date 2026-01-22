import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/usage_stats_service.dart';

/// Screen for selecting which apps to monitor
class AppSelectionScreen extends StatefulWidget {
  const AppSelectionScreen({super.key});

  @override
  State<AppSelectionScreen> createState() => _AppSelectionScreenState();
}

class _AppSelectionScreenState extends State<AppSelectionScreen> {
  List<AppUsageInfo> _allApps = [];
  Set<String> _selectedApps = {};
  bool _isLoading = true;
  String _searchQuery = '';
  
  // Default social media packages
  static const Set<String> _defaultSocialMediaPackages = {
    'com.instagram.android',
    'com.facebook.katana',
    'com.facebook.orca',
    'com.whatsapp',
    'org.telegram.messenger',
    'com.snapchat.android',
    'com.zhiliaoapp.musically',
    'com.ss.android.ugc.trill',
    'com.twitter.android',
    'com.linkedin.android',
    'com.reddit.frontpage',
    'com.discord',
    'com.pinterest',
    'com.google.android.youtube',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      // Load saved selections
      final prefs = await SharedPreferences.getInstance();
      final savedApps = prefs.getStringList('monitored_apps');
      
      if (savedApps != null) {
        _selectedApps = savedApps.toSet();
      } else {
        // Default to social media apps
        _selectedApps = Set.from(_defaultSocialMediaPackages);
      }
      
      // Load usage stats
      final usageStats = await UsageStatsService.getUsageStats(mode: UsageTimeWindow.rolling24h);
      
      // Filter to user apps with some usage or known social media
      _allApps = usageStats.where((app) {
        // Include if: not system app AND (has usage OR is social media)
        return !app.isSystemApp && (app.totalTimeInForeground > 60000 || _isSocialMediaApp(app.packageName));
      }).toList();
      
      // Sort: selected first, then by usage time
      _allApps.sort((a, b) {
        final aSelected = _selectedApps.contains(a.packageName);
        final bSelected = _selectedApps.contains(b.packageName);
        
        if (aSelected && !bSelected) return -1;
        if (!aSelected && bSelected) return 1;
        
        return b.totalTimeInForeground.compareTo(a.totalTimeInForeground);
      });
      
    } catch (e) {
      debugPrint('Error loading apps: $e');
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  bool _isSocialMediaApp(String packageName) {
    final lower = packageName.toLowerCase();
    return _defaultSocialMediaPackages.contains(packageName) ||
           lower.contains('instagram') ||
           lower.contains('facebook') ||
           lower.contains('whatsapp') ||
           lower.contains('telegram') ||
           lower.contains('snapchat') ||
           lower.contains('tiktok') ||
           lower.contains('twitter') ||
           lower.contains('linkedin') ||
           lower.contains('reddit') ||
           lower.contains('discord') ||
           lower.contains('pinterest') ||
           lower.contains('youtube') ||
           lower.contains('messenger');
  }

  Future<void> _saveSelections() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('monitored_apps', _selectedApps.toList());
    
    // Also save as JSON for native side to read
    await prefs.setString('monitored_apps_json', jsonEncode(_selectedApps.toList()));
  }

  void _toggleApp(String packageName) {
    setState(() {
      if (_selectedApps.contains(packageName)) {
        _selectedApps.remove(packageName);
      } else {
        _selectedApps.add(packageName);
      }
    });
    _saveSelections();
  }

  void _selectAllSocialMedia() {
    setState(() {
      for (final app in _allApps) {
        if (_isSocialMediaApp(app.packageName)) {
          _selectedApps.add(app.packageName);
        }
      }
    });
    _saveSelections();
  }

  void _deselectAll() {
    setState(() {
      _selectedApps.clear();
    });
    _saveSelections();
  }

  List<AppUsageInfo> get _filteredApps {
    if (_searchQuery.isEmpty) return _allApps;
    
    final query = _searchQuery.toLowerCase();
    return _allApps.where((app) {
      return app.appName.toLowerCase().contains(query) || 
             app.packageName.toLowerCase().contains(query);
    }).toList();
  }

  List<AppUsageInfo> get _socialMediaApps {
    return _filteredApps.where((app) {
      return _isSocialMediaApp(app.packageName);
    }).toList();
  }

  List<AppUsageInfo> get _otherApps {
    return _filteredApps.where((app) {
      return !_isSocialMediaApp(app.packageName);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        foregroundColor: Colors.white,
        title: const Text('Select Apps to Monitor'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            color: const Color(0xFF1A1A1A),
            onSelected: (value) {
              if (value == 'select_social') {
                _selectAllSocialMedia();
              } else if (value == 'deselect_all') {
                _deselectAll();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'select_social',
                child: Row(
                  children: [
                    Icon(Icons.check_box, color: Color(0xFF7C3AED)),
                    SizedBox(width: 12),
                    Text('Select All Social Media', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'deselect_all',
                child: Row(
                  children: [
                    Icon(Icons.check_box_outline_blank, color: Colors.grey),
                    SizedBox(width: 12),
                    Text('Deselect All', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
            )
          : Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.5)),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.white54),
                              onPressed: () {
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                    },
                  ),
                ),
                
                // Selected count
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C3AED).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_selectedApps.length} apps selected',
                          style: const TextStyle(
                            color: Color(0xFF7C3AED),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // App list
                Expanded(
                  child: ListView(
                    children: [
                      // Social Media section
                      if (_socialMediaApps.isNotEmpty) ...[
                        _buildSectionHeader('Social Media', _socialMediaApps.length),
                        ..._socialMediaApps.map((app) => _buildAppTile(app)),
                      ],
                      
                      // Other Apps section
                      if (_otherApps.isNotEmpty) ...[
                        _buildSectionHeader('Other Apps', _otherApps.length),
                        ..._otherApps.map((app) => _buildAppTile(app)),
                      ],
                      
                      const SizedBox(height: 100), // Bottom padding
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Monitoring ${_selectedApps.length} apps'),
              backgroundColor: const Color(0xFF7C3AED),
            ),
          );
        },
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.check),
        label: const Text('Done'),
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        '$title ($count)',
        style: TextStyle(
          color: Colors.white.withOpacity(0.6),
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildAppTile(AppUsageInfo app) {
    final packageName = app.packageName;
    final appName = app.appName;
    final totalTime = app.totalTimeInForeground;
    final formattedTime = app.formattedTime;
    final isSelected = _selectedApps.contains(packageName);
    
    // Calculate usage bar width (max 24 hours)
    const maxTime = 24 * 60 * 60 * 1000; // 24 hours in ms
    final barWidth = (totalTime / maxTime).clamp(0.0, 1.0);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected 
            ? const Color(0xFF7C3AED).withOpacity(0.1)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: isSelected
            ? Border.all(color: const Color(0xFF7C3AED).withOpacity(0.3))
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _buildAppIcon(packageName),
        title: Text(
          appName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            // Usage bar
            Row(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      // Background
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Fill
                      FractionallySizedBox(
                        widthFactor: barWidth,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C3AED),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  formattedTime,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Checkbox(
          value: isSelected,
          onChanged: (_) => _toggleApp(packageName),
          activeColor: const Color(0xFF7C3AED),
          checkColor: Colors.white,
          side: BorderSide(color: Colors.white.withOpacity(0.3)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        onTap: () => _toggleApp(packageName),
      ),
    );
  }

  Widget _buildAppIcon(String packageName) {
    // Map of known app icons/emojis
    final iconMap = {
      'com.instagram.android': '📷',
      'com.facebook.katana': '👥',
      'com.facebook.orca': '💬',
      'com.whatsapp': '💚',
      'org.telegram.messenger': '✈️',
      'com.snapchat.android': '👻',
      'com.zhiliaoapp.musically': '🎵',
      'com.ss.android.ugc.trill': '🎵',
      'com.twitter.android': '🐦',
      'com.linkedin.android': '💼',
      'com.reddit.frontpage': '🤖',
      'com.discord': '🎮',
      'com.pinterest': '📌',
      'com.google.android.youtube': '▶️',
    };
    
    final emoji = iconMap[packageName];
    
    if (emoji != null) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            emoji,
            style: const TextStyle(fontSize: 24),
          ),
        ),
      );
    }
    
    // Default icon
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.apps,
        color: Colors.white54,
        size: 24,
      ),
    );
  }
}

