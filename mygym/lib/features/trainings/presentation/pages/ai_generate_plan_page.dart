import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import 'package:get/get.dart';
import '../controllers/plans_controller.dart';

class AiGeneratePlanPage extends StatefulWidget {
  const AiGeneratePlanPage({super.key});

  @override
  State<AiGeneratePlanPage> createState() => _AiGeneratePlanPageState();
}

class _AiGeneratePlanPageState extends State<AiGeneratePlanPage> {
  final _formKey = GlobalKey<FormState>();
  String _selectedPlan = 'Muscle Building';
  final _ageCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  String _gender = 'Male';
  String _userLevel = 'Beginner';
  final _goalCtrl = TextEditingController();
  bool _isGenerating = false;
  late final PlansController _controller;
  ScaffoldMessengerState? _scaffoldMessenger;

  @override
  void initState() {
    super.initState();
    _controller = Get.find<PlansController>();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scaffoldMessenger = ScaffoldMessenger.of(context);
  }

  @override
  void dispose() {
    _ageCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _goalCtrl.dispose();
    super.dispose();
  }

  /// Safe setState that checks if widget is still mounted
  void _safeSetState(VoidCallback fn) {
    if (mounted) {
      try {
        setState(fn);
      } catch (e) {
        print('⚠️ AI Generate Plan - setState failed (widget disposed): $e');
      }
    }
  }

  /// Safe navigation that checks if widget is still mounted
  void _safeNavigateBack() {
    if (mounted && Navigator.canPop(context)) {
      try {
        Navigator.pop(context);
      } catch (e) {
        print('⚠️ AI Generate Plan - Navigation failed (widget disposed): $e');
      }
    }
  }

  /// Safe snackbar that checks if widget is still mounted
  void _safeShowSnackBar(String message, {bool isError = false}) {
    if (mounted && _scaffoldMessenger != null) {
      try {
        _scaffoldMessenger!.showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: isError ? Colors.red : null,
          ),
        );
      } catch (e) {
        print('⚠️ AI Generate Plan - SnackBar failed (widget disposed): $e');
      }
    }
  }

  Future<void> _submit() async {
    // Prevent multiple submissions
    if (_isGenerating) {
      print('⚠️ AI Generate Plan - Already generating, ignoring duplicate request');
      return;
    }
    
    _safeSetState(() => _isGenerating = true);
    print('🔄 AI Generate Plan - Starting generation process...');
    
    final now = DateTime.now();
    final startStr = now.toIso8601String().split('T').first;
    
    // Calculate realistic plan duration based on user level and goal
    final goal = _goalCtrl.text.trim().toLowerCase();
    final userLevel = _userLevel.toLowerCase();
    int planDays = 90; // Default 3 months
    
    if (userLevel.contains('beginner')) {
      planDays = 90; // 3 months for beginners
    } else if (userLevel.contains('intermediate')) {
      planDays = 120; // 4 months for intermediate
    } else if (userLevel.contains('advanced')) {
      planDays = 150; // 5 months for advanced
    }
    
    // Adjust based on specific goals
    if (goal.contains('weight loss') || goal.contains('lose weight')) {
      planDays = (planDays * 0.8).round(); // Slightly shorter for weight loss
    } else if (goal.contains('muscle') || goal.contains('strength')) {
      planDays = (planDays * 1.2).round(); // Longer for muscle building
    }
    
    final endStr = now.add(Duration(days: planDays)).toIso8601String().split('T').first;
    
    // Build payload strictly to backend schema for AI generated plans
    final payload = <String, dynamic>{
      'exercise_plan': _selectedPlan,
      'exercise_plan_category': _selectedPlan, // Add this for consistency
      'start_date': startStr,
      'end_date': endStr,
      'plan_duration_days': planDays, // Add plan duration
      'total_workouts': 0,
      'total_training_minutes': 0,
      'items': <Map<String, dynamic>>[],
      // optional: include free-form goal for server-side generation if supported
      'goal': _goalCtrl.text.trim(),
      'user_level': _userLevel,
      // also include fields expected by /requests in case backend shares validator
      'user_id': _controller.userId,
      'age': int.tryParse(_ageCtrl.text.trim()),
      'height_cm': int.tryParse(_heightCtrl.text.trim()),
      'weight_kg': int.tryParse(_weightCtrl.text.trim()),
      'gender': _gender,
      'future_goal': _goalCtrl.text.trim(),
      'plan_duration_days': planDays, // Add plan duration
    };
    try {
      // If frontend has GEMINI key, generate client-side; otherwise, ask backend to generate from request
      final bool hasFrontendGemini = AppConfig.geminiApiKey.isNotEmpty;
      print('🤖 Frontend Gemini API Key available: $hasFrontendGemini');
      print('🤖 Gemini API Key length: ${AppConfig.geminiApiKey.length}');
      print('🤖 Gemini API Key value: "${AppConfig.geminiApiKey}"');
      print('🤖 Gemini API Key isEmpty: ${AppConfig.geminiApiKey.isEmpty}');
      
      if (hasFrontendGemini) {
        print('🤖 Using client-side Gemini generation');
        try {
          await _controller.createAiGeneratedPlan(payload);
          print('✅ Client-side generation completed successfully');
        } catch (e) {
          print('❌ Client-side generation failed: $e');
          rethrow;
        }
      } else {
        print('🤖 Using backend generation (no frontend Gemini key)');
        int? _toInt(String s) {
          final onlyDigits = RegExp(r'\d+').allMatches(s).map((m) => m.group(0)).join();
          if (onlyDigits.isEmpty) return null;
          return int.tryParse(onlyDigits);
        }
        final reqPayload = {
          'user_id': _controller.userId,
          'exercise_plan': payload['exercise_plan'],
          'age': _toInt(_ageCtrl.text.trim()),
          'height_cm': _toInt(_heightCtrl.text.trim()),
          'weight_kg': _toInt(_weightCtrl.text.trim()),
          'gender': _gender,
          'future_goal': _goalCtrl.text.trim(),
        };
        // Prefer backend generation endpoint which creates plan records immediately
        final generatePayload = {
          'user_id': _controller.userId,
          if (_controller.user != null && _controller.user!['gym_id'] != null) 'gym_id': _controller.user!['gym_id'],
          'exercise_plan_category': payload['exercise_plan_category'],
          'start_date': payload['start_date'],
          'end_date': payload['end_date'],
          if (reqPayload['age'] != null) 'age': reqPayload['age'],
          if (reqPayload['height_cm'] != null) 'height_cm': reqPayload['height_cm'],
          if (reqPayload['weight_kg'] != null) 'weight_kg': reqPayload['weight_kg'],
          'gender': _gender,
          'future_goal': _goalCtrl.text.trim(),
          'user_level': _userLevel,
          // Add these fields to help backend generate items
          'plan_duration_days': planDays,
          'total_workouts': 0, // Let backend calculate
          'training_minutes': 0, // Let backend calculate
          'items': [], // Empty array to trigger generation
          // Add a flag to tell backend to generate items
          'generate_items': true,
        };
        
        print('🤖 Backend payload being sent: $generatePayload');
        print('🤖 User Level being sent: "$_userLevel"');
        try {
          await _controller.generateViaBackendAndAwait(generatePayload);
          print('✅ Backend generation completed successfully');
        } catch (e) {
          print('❌ Backend generation failed: $e');
          rethrow;
        }
      }
      
      // For client-side generation, refresh the plans list
      if (hasFrontendGemini) {
        await _controller.loadData();
      }
      if (!mounted) return;
      
      print('✅ AI Generate Plan - Generation completed, navigating back...');
      _safeNavigateBack();
      _safeShowSnackBar('AI generated plan created');
    } catch (e) {
      if (!mounted) return;
      print('❌ AI Generate Plan - Generation failed: $e');
      _safeShowSnackBar('Failed: $e', isError: true);
    } finally {
      print('🔄 AI Generate Plan - Resetting loading state...');
      _safeSetState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.appBackgroundColor,
      appBar: AppBar(
        title: const Text('Generate AI Plan'),
        backgroundColor: AppTheme.appBackgroundColor,
        foregroundColor: AppTheme.textColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Create Your AI Workout Plan',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Fill in your details below to get a personalized workout plan generated by AI',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // Form Fields
              const Text('Select Plan', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textColor)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedPlan,
                style: const TextStyle(color: AppTheme.textColor),
                dropdownColor: AppTheme.cardBackgroundColor,
                items: const [
                  DropdownMenuItem(value: 'Strength', child: Text('Strength', style: TextStyle(color: AppTheme.textColor))),
                  DropdownMenuItem(value: 'Muscle Building', child: Text('Muscle Building', style: TextStyle(color: AppTheme.textColor))),
                  DropdownMenuItem(value: 'Weight Gain', child: Text('Weight Gain', style: TextStyle(color: AppTheme.textColor))),
                  DropdownMenuItem(value: 'Weight Loss', child: Text('Weight Loss', style: TextStyle(color: AppTheme.textColor))),
                ],
                onChanged: (v) => setState(() => _selectedPlan = v ?? _selectedPlan),
                decoration: _decoration(),
              ),
              const SizedBox(height: 20),
              _text('Age', _ageCtrl, hint: 'Enter your age', keyboardType: TextInputType.number),
              const SizedBox(height: 20),
              _text('Height', _heightCtrl, hint: "Enter your height (e.g., 5'10\" or 178cm)"),
              const SizedBox(height: 20),
              _text('Weight', _weightCtrl, hint: 'Enter your weight (e.g., 150 lbs or 68 kg)'),
              const SizedBox(height: 20),
              const Text('Gender', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textColor)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _gender,
                style: const TextStyle(color: AppTheme.textColor),
                dropdownColor: AppTheme.cardBackgroundColor,
                items: const [
                  DropdownMenuItem(value: 'Male', child: Text('Male', style: TextStyle(color: AppTheme.textColor))),
                  DropdownMenuItem(value: 'Female', child: Text('Female', style: TextStyle(color: AppTheme.textColor))),
                ],
                onChanged: (v) => setState(() => _gender = v ?? _gender),
                decoration: _decoration(),
              ),
              const SizedBox(height: 20),
              _text('Future Goal', _goalCtrl, hint: 'e.g., build muscle, lose fat'),
              const SizedBox(height: 20),
              const Text('User Level', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textColor)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _userLevel,
                style: const TextStyle(color: AppTheme.textColor),
                dropdownColor: AppTheme.cardBackgroundColor,
                items: const [
                  DropdownMenuItem(value: 'Beginner', child: Text('Beginner', style: TextStyle(color: AppTheme.textColor))),
                  DropdownMenuItem(value: 'Intermediate', child: Text('Intermediate', style: TextStyle(color: AppTheme.textColor))),
                  DropdownMenuItem(value: 'Expert', child: Text('Expert', style: TextStyle(color: AppTheme.textColor))),
                ],
                onChanged: (v) => setState(() => _userLevel = v ?? _userLevel),
                decoration: _decoration(),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isGenerating ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                  ),
                  child: _isGenerating 
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Generating Plan...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      )
                    : const Text(
                        'Submit',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration() {
    return InputDecoration(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.primaryColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.primaryColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
      ),
      filled: true,
      fillColor: AppTheme.cardBackgroundColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _text(String label, TextEditingController ctrl, {String? hint, TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textColor)),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          keyboardType: keyboardType,
          style: const TextStyle(color: AppTheme.textColor),
          decoration: _decoration().copyWith(
            hintText: hint,
            hintStyle: const TextStyle(color: AppTheme.textColor),
          ),
        ),
      ],
    );
  }


}


