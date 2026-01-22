import 'package:flutter/material.dart';
import 'dart:async';
import '../services/app_intervention_service.dart';

/// Breathing exercise intervention screen
/// Shows an animated breathing circle that user must complete before continuing
class BreathingInterventionScreen extends StatefulWidget {
  final String packageName;
  final String appName;
  final VoidCallback onCancel;
  final VoidCallback onContinue;

  const BreathingInterventionScreen({
    super.key,
    required this.packageName,
    required this.appName,
    required this.onCancel,
    required this.onContinue,
  });

  @override
  State<BreathingInterventionScreen> createState() => _BreathingInterventionScreenState();
}

class _BreathingInterventionScreenState extends State<BreathingInterventionScreen>
    with TickerProviderStateMixin {
  late AnimationController _breathController;
  late AnimationController _pulseController;
  late Animation<double> _breathAnimation;
  late Animation<double> _pulseAnimation;
  
  int _attemptCount = 0;
  bool _isLoading = true;
  
  // Breathing phases
  static const int _inhaleSeconds = 4;
  static const int _holdSeconds = 4;
  static const int _exhaleSeconds = 4;
  static const int _totalCycleSeconds = _inhaleSeconds + _holdSeconds + _exhaleSeconds;
  
  int _currentPhase = 0; // 0=inhale, 1=hold, 2=exhale
  int _phaseSecondsRemaining = _inhaleSeconds;
  int _cyclesCompleted = 0;
  static const int _requiredCycles = 1;
  
  Timer? _phaseTimer;
  bool _canContinue = false;

  @override
  void initState() {
    super.initState();
    
    // Breath animation (scale)
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _totalCycleSeconds),
    );
    
    // Pulse animation for subtle effect
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    _breathAnimation = TweenSequence<double>([
      // Inhale: grow
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.6, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: _inhaleSeconds.toDouble(),
      ),
      // Hold: stay large
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: _holdSeconds.toDouble(),
      ),
      // Exhale: shrink
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.6)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: _exhaleSeconds.toDouble(),
      ),
    ]).animate(_breathController);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _breathController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _cyclesCompleted++;
        if (_cyclesCompleted >= _requiredCycles) {
          setState(() => _canContinue = true);
        }
        _breathController.forward(from: 0);
      }
    });
    
    _pulseController.repeat(reverse: true);
    
    _loadData();
    _startBreathing();
  }

  Future<void> _loadData() async {
    final interventionService = AppInterventionService();
    _attemptCount = await interventionService.getTotalAttemptsLast24h(widget.packageName);
    
    setState(() {
      _isLoading = false;
    });
  }

  void _startBreathing() {
    _breathController.forward();
    _startPhaseTimer();
  }

  void _startPhaseTimer() {
    _phaseTimer?.cancel();
    _phaseTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _phaseSecondsRemaining--;
        
        if (_phaseSecondsRemaining <= 0) {
          // Move to next phase
          _currentPhase = (_currentPhase + 1) % 3;
          switch (_currentPhase) {
            case 0: // Inhale
              _phaseSecondsRemaining = _inhaleSeconds;
              break;
            case 1: // Hold
              _phaseSecondsRemaining = _holdSeconds;
              break;
            case 2: // Exhale
              _phaseSecondsRemaining = _exhaleSeconds;
              break;
          }
        }
      });
    });
  }

  String get _phaseText {
    switch (_currentPhase) {
      case 0:
        return 'Breathe in...';
      case 1:
        return 'Hold...';
      case 2:
        return 'Breathe out...';
      default:
        return '';
    }
  }

  Color get _phaseColor {
    switch (_currentPhase) {
      case 0:
        return const Color(0xFF7C3AED); // Purple for inhale
      case 1:
        return const Color(0xFF3B82F6); // Blue for hold
      case 2:
        return const Color(0xFF10B981); // Green for exhale
      default:
        return const Color(0xFF7C3AED);
    }
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    _breathController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : Column(
                children: [
                  // Top section with attempt count
                  Padding(
                    padding: const EdgeInsets.only(top: 40, left: 24, right: 24),
                    child: Column(
                      children: [
                        RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w400,
                            ),
                            children: [
                              const TextSpan(text: "Take a moment to "),
                              TextSpan(
                                text: "breathe",
                                style: TextStyle(
                                  color: _phaseColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const TextSpan(text: " before opening"),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.appName,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Breathing circle
                  Expanded(
                    child: Center(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_breathAnimation, _pulseAnimation]),
                        builder: (context, child) {
                          final scale = _breathAnimation.value * _pulseAnimation.value;
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Phase text
                              Text(
                                _phaseText,
                                style: TextStyle(
                                  color: _phaseColor,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '$_phaseSecondsRemaining',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 32),
                              // Breathing circle
                              Transform.scale(
                                scale: scale,
                                child: Container(
                                  width: 200,
                                  height: 200,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        _phaseColor.withOpacity(0.8),
                                        _phaseColor.withOpacity(0.4),
                                        _phaseColor.withOpacity(0.1),
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _phaseColor.withOpacity(0.3),
                                        blurRadius: 40,
                                        spreadRadius: 10,
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 100,
                                      height: 100,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _phaseColor.withOpacity(0.3),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 40),
                              // Attempt count
                              Text(
                                '$_attemptCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 48,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                              Text(
                                'attempts today',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  
                  // Bottom buttons
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        // Primary button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: widget.onCancel,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7C3AED),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              'I don\'t want to open ${widget.appName}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Continue button (only enabled after completing breathing)
                        TextButton(
                          onPressed: _canContinue ? widget.onContinue : null,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          child: Text(
                            _canContinue
                                ? 'Continue on ${widget.appName}'
                                : 'Complete one breath cycle to continue...',
                            style: TextStyle(
                              color: _canContinue
                                  ? Colors.white.withOpacity(0.8)
                                  : Colors.white.withOpacity(0.3),
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              decoration: _canContinue
                                  ? TextDecoration.underline
                                  : null,
                              decorationColor: Colors.white.withOpacity(0.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

