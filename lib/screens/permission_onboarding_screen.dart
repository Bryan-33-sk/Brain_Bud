import 'package:flutter/material.dart';
import '../services/app_intervention_service.dart';
import '../services/usage_stats_service.dart';

/// Permission step data
class PermissionStep {
  final String title;
  final String description;
  final IconData icon;
  final String buttonText;
  final Future<bool> Function() checkPermission;
  final Future<void> Function() requestPermission;
  final String? warningText;
  final List<String>? instructions;

  PermissionStep({
    required this.title,
    required this.description,
    required this.icon,
    required this.buttonText,
    required this.checkPermission,
    required this.requestPermission,
    this.warningText,
    this.instructions,
  });
}

/// Guided permission onboarding screen
class PermissionOnboardingScreen extends StatefulWidget {
  final VoidCallback? onComplete;

  const PermissionOnboardingScreen({super.key, this.onComplete});

  @override
  State<PermissionOnboardingScreen> createState() => _PermissionOnboardingScreenState();
}

class _PermissionOnboardingScreenState extends State<PermissionOnboardingScreen> {
  final PageController _pageController = PageController();
  final _interventionService = AppInterventionService();
  
  int _currentStep = 0;
  Map<int, bool> _permissionStatus = {};
  bool _isCheckingPermission = false;

  late List<PermissionStep> _steps;

  @override
  void initState() {
    super.initState();
    _initSteps();
    _checkAllPermissions();
  }

  void _initSteps() {
    _steps = [
      // Step 0: Welcome
      PermissionStep(
        title: 'Welcome to Brain Bud',
        description: 'Brain Bud helps you be more mindful of your social media usage by gently intervening when you open distracting apps.\n\nWe need a few permissions to work effectively. Don\'t worry - we never collect or share your data.',
        icon: Icons.psychology_alt,
        buttonText: 'Get Started',
        checkPermission: () async => true,
        requestPermission: () async {},
      ),
      // Step 1: Usage Access
      PermissionStep(
        title: 'Usage Access',
        description: 'This allows Brain Bud to see which apps you open and track your screen time.\n\nWithout this, we can\'t detect when you open social media apps.',
        icon: Icons.bar_chart_rounded,
        buttonText: 'Grant Usage Access',
        checkPermission: () => UsageStatsService.hasUsagePermission(),
        requestPermission: () => UsageStatsService.openUsageSettings(),
        instructions: [
          'Find "Brain Bud" in the list',
          'Tap on it',
          'Enable "Allow usage access"',
        ],
      ),
      // Step 2: Overlay Permission
      PermissionStep(
        title: 'Display Over Apps',
        description: 'This allows Brain Bud to show the intervention screen on top of social media apps.\n\nWithout this, we can only send notifications.',
        icon: Icons.layers_rounded,
        buttonText: 'Grant Overlay Permission',
        checkPermission: () => _interventionService.hasOverlayPermission(),
        requestPermission: () => _interventionService.requestOverlayPermission(),
        instructions: [
          'Find "Brain Bud" in the list',
          'Enable "Allow display over other apps"',
        ],
      ),
      // Step 3: Accessibility Service
      PermissionStep(
        title: 'Accessibility Service',
        description: 'This enables instant detection when you open social media apps.\n\nWithout this, there may be a small delay before the intervention appears.',
        icon: Icons.accessibility_new_rounded,
        buttonText: 'Enable Accessibility',
        checkPermission: () => _interventionService.hasAccessibilityPermission(),
        requestPermission: () => _interventionService.requestAccessibilityPermission(),
        warningText: 'Android shows a security warning for all accessibility services. Brain Bud does NOT track or collect any personal data. You can disable this anytime.',
        instructions: [
          'Scroll down to find "Brain Bud"',
          'Tap on it',
          'Toggle "Use Brain Bud" ON',
          'Tap "Allow" on the confirmation dialog',
        ],
      ),
      // Step 4: Battery Optimization
      PermissionStep(
        title: 'Battery Optimization',
        description: 'Disable battery optimization so Brain Bud can run reliably in the background.\n\nWithout this, Android may stop the service to save battery.',
        icon: Icons.battery_saver_rounded,
        buttonText: 'Disable Battery Optimization',
        checkPermission: () => _interventionService.isBatteryOptimizationDisabled(),
        requestPermission: () => _interventionService.requestBatteryOptimizationExemption(),
        instructions: [
          'Tap "Allow" to let Brain Bud run in the background',
        ],
      ),
      // Step 5: Done
      PermissionStep(
        title: 'All Set!',
        description: 'Brain Bud is now ready to help you be more mindful of your social media usage.\n\nWhenever you open a social media app, you\'ll see a gentle reminder to think twice.',
        icon: Icons.check_circle_rounded,
        buttonText: 'Start Using Brain Bud',
        checkPermission: () async => true,
        requestPermission: () async {},
      ),
    ];
  }

  Future<void> _checkAllPermissions() async {
    for (int i = 0; i < _steps.length; i++) {
      final status = await _steps[i].checkPermission();
      if (mounted) {
        setState(() {
          _permissionStatus[i] = status;
        });
      }
    }
  }

  Future<void> _checkCurrentPermission() async {
    if (_isCheckingPermission) return;
    
    setState(() => _isCheckingPermission = true);
    
    final status = await _steps[_currentStep].checkPermission();
    
    if (mounted) {
      setState(() {
        _permissionStatus[_currentStep] = status;
        _isCheckingPermission = false;
      });
    }
  }

  Future<void> _handleButtonPress() async {
    final step = _steps[_currentStep];
    final isGranted = _permissionStatus[_currentStep] ?? false;
    
    if (_currentStep == 0 || _currentStep == _steps.length - 1 || isGranted) {
      // Welcome or Done step, or permission already granted - just go next
      _goToNextStep();
    } else {
      // Request permission
      await step.requestPermission();
      
      // Wait a bit for user to come back from settings
      await Future.delayed(const Duration(milliseconds: 500));
      await _checkCurrentPermission();
    }
  }

  void _goToNextStep() {
    if (_currentStep < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // Complete
      widget.onComplete?.call();
      Navigator.of(context).pop();
    }
  }

  void _skipStep() {
    if (_currentStep < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: List.generate(_steps.length, (index) {
                  final isCompleted = _permissionStatus[index] ?? false;
                  final isCurrent = index == _currentStep;
                  
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? const Color(0xFF7C3AED)
                            : isCurrent
                                ? const Color(0xFF7C3AED).withOpacity(0.5)
                                : Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            
            // Page content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  setState(() => _currentStep = index);
                  _checkCurrentPermission();
                },
                itemCount: _steps.length,
                itemBuilder: (context, index) {
                  return _buildStepPage(_steps[index], index);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepPage(PermissionStep step, int index) {
    final isGranted = _permissionStatus[index] ?? false;
    final isFirstOrLast = index == 0 || index == _steps.length - 1;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height - 120,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top section - Icon, title, description
            Column(
              children: [
                const SizedBox(height: 16),
                
                // Icon
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isGranted && !isFirstOrLast ? Icons.check_rounded : step.icon,
                    size: 48,
                    color: isGranted && !isFirstOrLast 
                        ? Colors.green 
                        : const Color(0xFF7C3AED),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Title
                Text(
                  step.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 12),
                
                // Description
                Text(
                  step.description,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 15,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            
            // Middle section - Warning and Instructions
            Column(
              children: [
                // Warning text (if any)
                if (step.warningText != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lightbulb_outline, color: Colors.amber, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            step.warningText!,
                            style: TextStyle(
                              color: Colors.amber.shade100,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                // Instructions (if any)
                if (step.instructions != null && !isGranted) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'How to enable:',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...step.instructions!.asMap().entries.map((entry) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF7C3AED).withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${entry.key + 1}',
                                      style: const TextStyle(
                                        color: Color(0xFF7C3AED),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    entry.value,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            
            // Bottom section - Buttons
            Column(
              children: [
                const SizedBox(height: 20),
                
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _handleButtonPress,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isGranted && !isFirstOrLast
                          ? Colors.green
                          : const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isGranted && !isFirstOrLast) ...[
                          const Icon(Icons.check, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Permission Granted - Continue',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ] else ...[
                          Text(
                            step.buttonText,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          if (!isFirstOrLast && index != _steps.length - 1) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.open_in_new, size: 18),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
                
                // Skip button (for non-essential permissions)
                if (!isFirstOrLast && index != _steps.length - 1 && !isGranted) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _skipStep,
                    child: Text(
                      'Skip for now',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
                
                const SizedBox(height: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}

