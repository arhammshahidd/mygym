import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onAnimationComplete;

  const SplashScreen({
    super.key,
    required this.onAnimationComplete,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _dumbbellController;
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late AnimationController _rotationController;

  late Animation<double> _dumbbellScale;
  late Animation<double> _dumbbellRotation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Dumbbell animation controller (scale and rotation)
    _dumbbellController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Pulse animation controller (ripple effect)
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    // Fade animation controller (text fade in)
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    // Scale animation controller (overall scale effect)
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    // Rotation animation controller (for rotating elements)
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    )..repeat();

    // Dumbbell animations
    _dumbbellScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _dumbbellController,
        curve: Curves.elasticOut,
      ),
    );

    _dumbbellRotation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _dumbbellController,
        curve: Curves.easeInOut,
      ),
    );

    // Pulse animation
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    // Fade animation
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: Curves.easeIn,
      ),
    );

    // Scale animation
    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _scaleController,
        curve: Curves.easeOut,
      ),
    );

    // Start animations
    _startAnimations();
  }

  void _startAnimations() async {
    // Start dumbbell animation
    await _dumbbellController.forward();
    
    // Start fade and scale animations
    _fadeController.forward();
    _scaleController.forward();

    // Wait for splash screen duration (3 seconds total)
    await Future.delayed(const Duration(milliseconds: 3000));

    // Call completion callback
    if (mounted) {
      widget.onAnimationComplete();
    }
  }

  @override
  void dispose() {
    _dumbbellController.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    _scaleController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.appBackgroundColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.appBackgroundColor,
              AppTheme.appBackgroundColor.withOpacity(0.8),
              AppTheme.primaryColor.withOpacity(0.1),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated pulsing circles background
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer pulse circle
                      Container(
                        width: 200 * _pulseAnimation.value,
                        height: 200 * _pulseAnimation.value,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppTheme.primaryColor.withOpacity(
                              0.3 * (1 - (_pulseAnimation.value - 0.8) / 0.4),
                            ),
                            width: 2,
                          ),
                        ),
                      ),
                      // Middle pulse circle
                      Container(
                        width: 160 * _pulseAnimation.value,
                        height: 160 * _pulseAnimation.value,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppTheme.primaryColor.withOpacity(
                              0.4 * (1 - (_pulseAnimation.value - 0.8) / 0.4),
                            ),
                            width: 2,
                          ),
                        ),
                      ),
                      // Main dumbbell container
                      AnimatedBuilder(
                        animation: _dumbbellScale,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _dumbbellScale.value,
                            child: Transform.rotate(
                              angle: _dumbbellRotation.value * 0.1,
                              child: _buildDumbbell(),
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 60),

              // App name with fade and scale animation
              AnimatedBuilder(
                animation: Listenable.merge([_fadeAnimation, _scaleAnimation]),
                builder: (context, child) {
                  return Opacity(
                    opacity: _fadeAnimation.value,
                    child: Transform.scale(
                      scale: _scaleAnimation.value,
                      child: Column(
                        children: [
                          Text(
                            'MY GYM',
                            style: TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                              letterSpacing: 4,
                              shadows: [
                                Shadow(
                                  color: AppTheme.primaryColor.withOpacity(0.5),
                                  blurRadius: 20,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Transform Your Body',
                            style: TextStyle(
                              fontSize: 18,
                              color: AppTheme.textColor.withOpacity(0.8),
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 80),

              // Loading indicator
              AnimatedBuilder(
                animation: _fadeAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: _fadeAnimation.value,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppTheme.primaryColor,
                        ),
                        strokeWidth: 3,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDumbbell() {
    return AnimatedBuilder(
      animation: _rotationController,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(120, 60),
          painter: DumbbellPainter(
            color: AppTheme.primaryColor,
            rotation: _rotationController.value * 0.1,
          ),
        );
      },
    );
  }
}

class DumbbellPainter extends CustomPainter {
  final Color color;
  final double rotation;

  DumbbellPainter({
    required this.color,
    this.rotation = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..strokeWidth = 4;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Save canvas state
    canvas.save();

    // Apply rotation around center
    canvas.translate(centerX, centerY);
    canvas.rotate(rotation);
    canvas.translate(-centerX, -centerY);

    // Draw left weight
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX - 40, centerY),
        width: 30,
        height: 30,
      ),
      paint,
    );

    // Draw right weight
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX + 40, centerY),
        width: 30,
        height: 30,
      ),
      paint,
    );

    // Draw connecting bar
    final barPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(centerX - 25, centerY),
      Offset(centerX + 25, centerY),
      barPaint,
    );

    // Add shine effect to weights
    final shinePaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    // Left weight shine
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX - 40, centerY - 8),
        width: 12,
        height: 12,
      ),
      shinePaint,
    );

    // Right weight shine
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX + 40, centerY - 8),
        width: 12,
        height: 12,
      ),
      shinePaint,
    );

    // Restore canvas state
    canvas.restore();
  }

  @override
  bool shouldRepaint(DumbbellPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.rotation != rotation;
  }
}

