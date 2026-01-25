import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../services/app_intervention_service.dart';
import '../services/usage_stats_service.dart';

/// Onboarding data model to store user preferences
class OnboardingData {
  int? baselineMinutes;      // Current daily usage (self-reported)
  String? nudgeStyle;         // 'gentle' or 'firm'
  int? goalMinutes;           // Target daily usage
  String? motivator;          // What matters most to user
  
  OnboardingData();
  
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    if (baselineMinutes != null) await prefs.setInt('baseline_minutes', baselineMinutes!);
    if (nudgeStyle != null) await prefs.setString('nudge_style', nudgeStyle!);
    if (goalMinutes != null) await prefs.setInt('goal_minutes', goalMinutes!);
    if (motivator != null) await prefs.setString('motivator', motivator!);
    await prefs.setBool('onboarding_completed', true);
    // Save version to track onboarding completion for this app version
    await prefs.setString('onboarding_version', '1.0.0');
  }
}

/// Main onboarding screen with psychology-based flow
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> 
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  final OnboardingData _data = OnboardingData();
  final _interventionService = AppInterventionService();
  
  int _currentPage = 0;
  static const int _totalPages = 8;
  
  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _glowController;
  
  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
  }
  
  @override
  void dispose() {
    _pageController.dispose();
    _pulseController.dispose();
    _glowController.dispose();
    super.dispose();
  }
  
  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      _completeOnboarding();
    }
  }
  
  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }
  
  Future<void> _completeOnboarding() async {
    await _data.save();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainAppShell()),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            _buildProgressIndicator(),
            
            // Page content
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                children: [
                  _buildWelcomePage(),      // A: Emotional hook
                  _buildBaselinePage(),     // B: Self-report
                  _buildNudgeStylePage(),   // C: Toggle choice
                  _buildGoalSliderPage(),   // D: Goal slider
                  _buildMotivatorPage(),    // E: What matters
                  _buildPermissionsPage(),  // F: Permissions
                  _buildDemoPage(),         // G: Try demo
                  _buildPricingPage(),      // H: Pricing
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          // Back button
          if (_currentPage > 0)
            GestureDetector(
              onTap: _previousPage,
              child: Container(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.arrow_back_ios_rounded,
                  color: Colors.white.withOpacity(0.5),
                  size: 20,
                ),
              ),
            )
          else
            const SizedBox(width: 36),
          
          const SizedBox(width: 12),
          
          // Progress dots
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_totalPages, (index) {
                final isActive = index <= _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: index == _currentPage ? 24 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFF7C3AED)
                        : Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Step indicator
          Text(
            '${_currentPage + 1}/$_totalPages',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
  
  // ============================================================
  // SCREEN A: WELCOME / EMOTIONAL HOOK
  // ============================================================
  Widget _buildWelcomePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height - 150,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(height: 20),
            
            // Middle section - Brain Bud + Text
            Column(
              children: [
                // Glowing Brain Bud
                AnimatedBuilder(
                  animation: _glowController,
                  builder: (context, child) {
                    return Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7C3AED).withOpacity(
                              0.3 + (_glowController.value * 0.2),
                            ),
                            blurRadius: 60 + (_glowController.value * 20),
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: BrainBudCharacter(
                        mood: BrainBudMood.happy,
                        size: 180,
                      ),
                    );
                  },
                ),
                
                const SizedBox(height: 40),
                
                // Headline
                const Text(
                  'You\'re not alone.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 16),
                
                // Subheadline
                Text(
                  'Millions struggle with endless scrolling.\nBrain Bud is your friendly reminder to pause.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 16,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            
            // Bottom section - Buttons
            Column(
              children: [
                const SizedBox(height: 32),
                
                // CTA Button
                _buildPrimaryButton(
                  text: 'Let\'s Go',
                  onPressed: _nextPage,
                ),
                
                const SizedBox(height: 24),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  // ============================================================
  // SCREEN B: BASELINE / SELF-REPORT
  // ============================================================
  Widget _buildBaselinePage() {
    final options = [
      {'label': 'Less than 30 min', 'value': 15, 'emoji': '😇'},
      {'label': '30 min – 1 hour', 'value': 45, 'emoji': '🙂'},
      {'label': '1 – 2 hours', 'value': 90, 'emoji': '😐'},
      {'label': '2 – 4 hours', 'value': 180, 'emoji': '😟'},
      {'label': '4+ hours', 'value': 300, 'emoji': '😵'},
    ];
    
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const SizedBox(height: 24),
          
          // Question
          const Text(
            'How much time do you\nspend on social media daily?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 12),
          
          Text(
            'Be honest — this helps us personalize your experience.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 32),
          
          // Options
          Expanded(
            child: ListView.separated(
              itemCount: options.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final option = options[index];
                final isSelected = _data.baselineMinutes == option['value'];
                
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _data.baselineMinutes = option['value'] as int;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF7C3AED).withOpacity(0.2)
                          : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF7C3AED)
                            : Colors.white.withOpacity(0.1),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          option['emoji'] as String,
                          style: const TextStyle(fontSize: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            option['label'] as String,
                            style: TextStyle(
                              color: Colors.white.withOpacity(
                                isSelected ? 1.0 : 0.7,
                              ),
                              fontSize: 17,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (isSelected)
                          const Icon(
                            Icons.check_circle,
                            color: Color(0xFF7C3AED),
                            size: 24,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          const SizedBox(height: 24),
          
          // CTA
          _buildPrimaryButton(
            text: 'Continue',
            onPressed: _data.baselineMinutes != null ? _nextPage : null,
          ),
        ],
      ),
    );
  }
  
  // ============================================================
  // SCREEN C: NUDGE STYLE
  // ============================================================
  Widget _buildNudgeStylePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height - 150,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top section
            Column(
              children: [
                const SizedBox(height: 16),
                
                const Text(
                  'How should Brain Bud\nremind you?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 8),
                
                Text(
                  'Choose the tone that works best for you.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            
            // Middle section - Brain Bud + message
            Column(
              children: [
                const SizedBox(height: 20),
                
                // Brain Bud preview (smaller)
                BrainBudCharacter(
                  mood: _data.nudgeStyle == 'firm'
                      ? BrainBudMood.neutral
                      : BrainBudMood.happy,
                  size: 130,
                ),
                
                const SizedBox(height: 16),
                
                // Sample message
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    key: ValueKey(_data.nudgeStyle),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _data.nudgeStyle == 'firm'
                          ? '"You\'ve already spent 2 hours scrolling today. Is this really how you want to spend your time?"'
                          : '"Hey! Taking a quick break? Your Brain Bud misses you 💜"',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 14,
                        height: 1.4,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
              ],
            ),
            
            // Bottom section - Toggle + Button
            Column(
              children: [
                // Toggle buttons
                Row(
                  children: [
                    Expanded(
                      child: _buildNudgeOption(
                        title: 'Gentle',
                        subtitle: 'Friendly reminders',
                        icon: Icons.favorite_rounded,
                        isSelected: _data.nudgeStyle == 'gentle',
                        onTap: () => setState(() => _data.nudgeStyle = 'gentle'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildNudgeOption(
                        title: 'Firm',
                        subtitle: 'Direct & honest',
                        icon: Icons.fitness_center_rounded,
                        isSelected: _data.nudgeStyle == 'firm',
                        onTap: () => setState(() => _data.nudgeStyle = 'firm'),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                _buildPrimaryButton(
                  text: 'Continue',
                  onPressed: _data.nudgeStyle != null ? _nextPage : null,
                ),
                
                const SizedBox(height: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildNudgeOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF7C3AED).withOpacity(0.2)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF7C3AED)
                : Colors.white.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? const Color(0xFF7C3AED)
                  : Colors.white.withOpacity(0.5),
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withOpacity(isSelected ? 1.0 : 0.7),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // ============================================================
  // SCREEN D: GOAL SLIDER
  // ============================================================
  Widget _buildGoalSliderPage() {
    final goalValue = (_data.goalMinutes ?? 30).toDouble();
    
    // Determine Brain Bud mood based on goal
    BrainBudMood mood;
    if (goalValue <= 30) {
      mood = BrainBudMood.happy;
    } else if (goalValue <= 90) {
      mood = BrainBudMood.neutral;
    } else {
      mood = BrainBudMood.sad;
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height - 150,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top section
            Column(
              children: [
                const SizedBox(height: 16),
                
                const Text(
                  'Set your daily goal',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 8),
                
                Text(
                  'How much social media time feels right?',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            
            // Middle section - Brain Bud + Slider
            Column(
              children: [
                const SizedBox(height: 16),
                
                // Brain Bud reacts to slider
                BrainBudCharacter(
                  mood: mood,
                  size: 120,
                ),
                
                const SizedBox(height: 16),
                
                // Goal display
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      goalValue.round().toString(),
                      style: const TextStyle(
                        color: Color(0xFF7C3AED),
                        fontSize: 56,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'min',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                // Slider
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF7C3AED),
                    inactiveTrackColor: Colors.white.withOpacity(0.1),
                    thumbColor: const Color(0xFF7C3AED),
                    overlayColor: const Color(0xFF7C3AED).withOpacity(0.2),
                    trackHeight: 8,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 12,
                    ),
                  ),
                  child: Slider(
                    value: goalValue,
                    min: 0,
                    max: 180,
                    divisions: 12, // 15-minute increments
                    onChanged: (value) {
                      setState(() {
                        _data.goalMinutes = value.round();
                      });
                    },
                  ),
                ),
                
                // Slider labels
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: ['0', '30', '60', '90', '120', '180'].map((label) {
                      return Text(
                        label,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 11,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Encouragement message
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    goalValue <= 30
                        ? '🎉 Ambitious! Brain Bud believes in you!'
                        : goalValue <= 60
                            ? '👍 A solid, achievable goal!'
                            : goalValue <= 120
                                ? '🤔 That\'s a lot... aim for less?'
                                : '😬 Maybe start smaller?',
                    key: ValueKey(goalValue ~/ 30),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            
            // Bottom section
            Column(
              children: [
                const SizedBox(height: 24),
                
                _buildPrimaryButton(
                  text: 'Set My Goal',
                  onPressed: _nextPage,
                ),
                
                const SizedBox(height: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  // ============================================================
  // SCREEN E: MOTIVATOR
  // ============================================================
  Widget _buildMotivatorPage() {
    final motivators = [
      {'id': 'focus', 'emoji': '🎯', 'label': 'Focus & Productivity'},
      {'id': 'sleep', 'emoji': '😴', 'label': 'Better Sleep'},
      {'id': 'mental', 'emoji': '🧠', 'label': 'Mental Health'},
      {'id': 'time', 'emoji': '⏰', 'label': 'More Free Time'},
      {'id': 'relationships', 'emoji': '❤️', 'label': 'Real Relationships'},
      {'id': 'creativity', 'emoji': '🎨', 'label': 'Creativity'},
    ];
    
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const SizedBox(height: 24),
          
          const Text(
            'What do you want\nto protect most?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 12),
          
          Text(
            'We\'ll tailor your experience to what matters.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 32),
          
          // Grid of motivators
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.3,
              children: motivators.map((m) {
                final isSelected = _data.motivator == m['id'];
                
                return GestureDetector(
                  onTap: () {
                    setState(() => _data.motivator = m['id'] as String);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF7C3AED).withOpacity(0.2)
                          : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF7C3AED)
                            : Colors.white.withOpacity(0.1),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          m['emoji'] as String,
                          style: const TextStyle(fontSize: 36),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          m['label'] as String,
                          style: TextStyle(
                            color: Colors.white.withOpacity(
                              isSelected ? 1.0 : 0.7,
                            ),
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          
          const SizedBox(height: 24),
          
          _buildPrimaryButton(
            text: 'Continue',
            onPressed: _data.motivator != null ? _nextPage : null,
          ),
        ],
      ),
    );
  }
  
  // ============================================================
  // SCREEN F: PERMISSIONS (Value-first)
  // ============================================================
  Widget _buildPermissionsPage() {
    return FutureBuilder<Map<String, bool>>(
      future: _checkPermissions(),
      builder: (context, snapshot) {
        final permissions = snapshot.data ?? {};
        final usageGranted = permissions['usage'] ?? false;
        final overlayGranted = permissions['overlay'] ?? false;
        final accessibilityGranted = permissions['accessibility'] ?? false;
        final allGranted = usageGranted && overlayGranted && accessibilityGranted;
        
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - 150,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top section
                Column(
                  children: [
                    const SizedBox(height: 12),
                    
                    const Text(
                      'Quick Setup',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    const SizedBox(height: 6),
                    
                    Text(
                      'Brain Bud needs a few permissions to work.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                
                // Middle section - Permission cards
                Column(
                  children: [
                    const SizedBox(height: 20),
                    
                    _buildPermissionCard(
                      title: 'Usage Access',
                      description: 'See which apps you open',
                      icon: Icons.bar_chart_rounded,
                      isGranted: usageGranted,
                      onTap: () async {
                        await UsageStatsService.openUsageSettings();
                        await Future.delayed(const Duration(seconds: 1));
                        setState(() {});
                      },
                    ),
                    
                    const SizedBox(height: 10),
                    
                    _buildPermissionCard(
                      title: 'Display Over Apps',
                      description: 'Show reminders on top of social apps',
                      icon: Icons.layers_rounded,
                      isGranted: overlayGranted,
                      onTap: () async {
                        await _interventionService.requestOverlayPermission();
                        await Future.delayed(const Duration(seconds: 1));
                        setState(() {});
                      },
                    ),
                    
                    const SizedBox(height: 10),
                    
                    _buildPermissionCard(
                      title: 'Accessibility Service',
                      description: 'Instant detection when opening apps',
                      icon: Icons.accessibility_new_rounded,
                      isGranted: accessibilityGranted,
                      onTap: () async {
                        await _interventionService.requestAccessibilityPermission();
                        await Future.delayed(const Duration(seconds: 1));
                        setState(() {});
                      },
                    ),
                    
                    const SizedBox(height: 16),
                  ],
                ),
                
                // Bottom section
                Column(
                  children: [
                    // Privacy note
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.green.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.lock_rounded,
                            color: Colors.green,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Your data stays on your device. We never collect or share it.',
                              style: TextStyle(
                                color: Colors.green.shade100,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    _buildPrimaryButton(
                      text: allGranted 
                          ? 'All Set! Continue' 
                          : 'Continue Anyway',
                      onPressed: _nextPage,
                    ),
                    
                    if (!allGranted) ...[
                      const SizedBox(height: 6),
                      Text(
                        'You can enable these later in Settings',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 11,
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 12),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Future<Map<String, bool>> _checkPermissions() async {
    return {
      'usage': await UsageStatsService.hasUsagePermission(),
      'overlay': await _interventionService.hasOverlayPermission(),
      'accessibility': await _interventionService.hasAccessibilityPermission(),
    };
  }
  
  Widget _buildPermissionCard({
    required String title,
    required String description,
    required IconData icon,
    required bool isGranted,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: isGranted ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isGranted
              ? Colors.green.withOpacity(0.1)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isGranted
                ? Colors.green.withOpacity(0.5)
                : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isGranted
                    ? Colors.green.withOpacity(0.2)
                    : const Color(0xFF7C3AED).withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isGranted ? Icons.check_rounded : icon,
                color: isGranted ? Colors.green : const Color(0xFF7C3AED),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white.withOpacity(isGranted ? 0.7 : 1.0),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (!isGranted)
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withOpacity(0.3),
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
  
  // ============================================================
  // SCREEN G: DEMO
  // ============================================================
  Widget _buildDemoPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height - 150,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top section
            Column(
              children: [
                const SizedBox(height: 16),
                
                const Text(
                  'See it in action',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 8),
                
                Text(
                  'Try what happens when you open a social app.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            
            // Middle section - Phone mockup
            Column(
              children: [
                const SizedBox(height: 24),
                
                // Demo phone mockup (smaller)
                Container(
                  width: 160,
                  height: 280,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7C3AED).withOpacity(0.3),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: Column(
                      children: [
                        // Status bar
                        Container(
                          height: 20,
                          color: Colors.black,
                        ),
                        // App icons
                        Expanded(
                          child: Container(
                            color: const Color(0xFF1A1A1A),
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  '📱',
                                  style: TextStyle(fontSize: 40),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap "Try Demo" below',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontSize: 11,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
              ],
            ),
            
            // Bottom section - Buttons
            Column(
              children: [
                // Try demo button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showDemoIntervention(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF7C3AED),
                      side: const BorderSide(
                        color: Color(0xFF7C3AED),
                        width: 2,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text(
                      'Try Demo',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                _buildPrimaryButton(
                  text: 'Continue',
                  onPressed: _nextPage,
                ),
                
                const SizedBox(height: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  void _showDemoIntervention(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Color(0xFF0A0A0A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // App icon being opened
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '📸',
                        style: TextStyle(fontSize: 48),
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // "Think twice" message
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'Do you really want to open\n',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 22,
                            ),
                          ),
                          const TextSpan(
                            text: 'Instagram',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextSpan(
                            text: '?',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    BrainBudCharacter(
                      mood: BrainBudMood.neutral,
                      size: 120,
                    ),
                    
                    const SizedBox(height: 24),
                    
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'This is attempt #3 today',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 48),
                    
                    // Buttons
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Don\'t open',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Continue anyway',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // ============================================================
  // SCREEN H: PRICING (Placeholder for now)
  // ============================================================
  Widget _buildPricingPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height - 150,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top section - Celebration
            Column(
              children: [
                const SizedBox(height: 16),
                
                // Celebration
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: 1.0 + (_pulseController.value * 0.05),
                      child: child,
                    );
                  },
                  child: const Text(
                    '🎉',
                    style: TextStyle(fontSize: 56),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                const Text(
                  'You\'re all set!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 8),
                
                Text(
                  'Brain Bud is ready to help you build\nhealthier digital habits.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 15,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            
            // Middle section - Summary card
            Column(
              children: [
                const SizedBox(height: 24),
                
                // Summary card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF7C3AED).withOpacity(0.3),
                        const Color(0xFF7C3AED).withOpacity(0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF7C3AED).withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Your Goal',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${_data.goalMinutes ?? 30}',
                            style: const TextStyle(
                              color: Color(0xFF7C3AED),
                              fontSize: 42,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'min/day',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildSummaryChip(
                            _data.nudgeStyle == 'firm' ? '💪 Firm' : '💜 Gentle',
                          ),
                          const SizedBox(width: 10),
                          _buildSummaryChip(
                            _getMotivatorEmoji(_data.motivator),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
              ],
            ),
            
            // Bottom section
            Column(
              children: [
                // Pro features teaser
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        color: Color(0xFFFFD700),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Pro features coming soon: Custom skins, detailed analytics, cloud backup',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                _buildPrimaryButton(
                  text: 'Start Using Brain Bud',
                  onPressed: _completeOnboarding,
                ),
                
                const SizedBox(height: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSummaryChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withOpacity(0.8),
          fontSize: 13,
        ),
      ),
    );
  }
  
  String _getMotivatorEmoji(String? motivator) {
    switch (motivator) {
      case 'focus': return '🎯 Focus';
      case 'sleep': return '😴 Sleep';
      case 'mental': return '🧠 Mental';
      case 'time': return '⏰ Time';
      case 'relationships': return '❤️ Relationships';
      case 'creativity': return '🎨 Creativity';
      default: return '✨';
    }
  }
  
  // ============================================================
  // SHARED WIDGETS
  // ============================================================
  Widget _buildPrimaryButton({
    required String text,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: onPressed != null ? 1.0 : 0.5,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7C3AED),
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFF7C3AED).withOpacity(0.3),
            disabledForegroundColor: Colors.white.withOpacity(0.5),
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

