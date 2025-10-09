import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
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
  final _goalCtrl = TextEditingController();
  final _userLevelCtrl = TextEditingController();
  final _jsonCtrl = TextEditingController();
  bool _advancedJson = false;
  late final PlansController _controller;

  @override
  void initState() {
    super.initState();
    _controller = Get.find<PlansController>();
  }

  @override
  void dispose() {
    _ageCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _goalCtrl.dispose();
    _userLevelCtrl.dispose();
    _jsonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final now = DateTime.now();
    final startStr = now.toIso8601String().split('T').first;
    
    // Calculate realistic plan duration based on user level and goal
    final goal = _goalCtrl.text.trim().toLowerCase();
    final userLevel = _userLevelCtrl.text.trim().toLowerCase();
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
      'user_level': _userLevelCtrl.text.trim(),
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
      // Decide path: if OpenAI key missing or flag enabled, use server-side requests
      final bool useRequests = AppConfig.useAiRequests || AppConfig.openAIApiKey.isEmpty;
      // If configured to send requests, include all required request fields
      if (useRequests) {
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
        await _controller.createAiRequest(reqPayload);
        // Refresh lists so newly generated plans (if synchronous) or requests reflected
        await _controller.loadData();
      } else {
        // App-side AI (or direct save) path
        await _controller.createAiGeneratedPlan(payload);
        await _controller.loadData();
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI generated plan created')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Generate AI Plan'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2E7D32),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select Plan', style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _selectedPlan,
                items: const [
                  DropdownMenuItem(value: 'Strength', child: Text('Strength')),
                  DropdownMenuItem(value: 'Muscle Building', child: Text('Muscle Building')),
                  DropdownMenuItem(value: 'Weight Gain', child: Text('Weight Gain')),
                  DropdownMenuItem(value: 'Weight Loss', child: Text('Weight Loss')),
                ],
                onChanged: (v) => setState(() => _selectedPlan = v ?? _selectedPlan),
                decoration: _decoration(),
              ),
              const SizedBox(height: 16),
              _text('Age', _ageCtrl, hint: 'Enter your age', keyboardType: TextInputType.number),
              const SizedBox(height: 16),
              _text('Height', _heightCtrl, hint: "Enter your height (e.g., 5'10\" or 178cm)"),
              const SizedBox(height: 16),
              _text('Weight', _weightCtrl, hint: 'Enter your weight (e.g., 150 lbs or 68 kg)'),
              const SizedBox(height: 16),
              const Text('Gender', style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _gender,
                items: const [
                  DropdownMenuItem(value: 'Male', child: Text('Male')),
                  DropdownMenuItem(value: 'Female', child: Text('Female')),
                ],
                onChanged: (v) => setState(() => _gender = v ?? _gender),
                decoration: _decoration(),
              ),
              const SizedBox(height: 16),
              _text('Future Goal', _goalCtrl, hint: 'e.g., build muscle, lose fat'),
              const SizedBox(height: 16),
              _text('User Level', _userLevelCtrl, hint: 'e.g., Beginner, Intermediate, Advanced'),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Submit'),
                ),
              ),
            const SizedBox(height: 24),
            SwitchListTile(
              value: _advancedJson,
              onChanged: (v) => setState(() => _advancedJson = v),
              title: const Text('Advanced: Paste full plan JSON to create now'),
              activeColor: const Color(0xFF2E7D32),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            if (_advancedJson) ...[
              const SizedBox(height: 8),
              _buildJsonEditor(),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _createFromJson,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Create Plan Now'),
                ),
              ),
            ],
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration() {
    return InputDecoration(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _text(String label, TextEditingController ctrl, {String? hint, TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          keyboardType: keyboardType,
          decoration: _decoration().copyWith(hintText: hint),
        ),
      ],
    );
  }

  Widget _buildJsonEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Plan JSON', style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 6),
        TextFormField(
          controller: _jsonCtrl,
          maxLines: 10,
          decoration: _decoration().copyWith(hintText: '{ ... }'),
        ),
      ],
    );
  }

  Future<void> _createFromJson() async {
    dynamic parsed;
    try {
      final raw = _jsonCtrl.text.trim();
      parsed = raw.isEmpty ? null : _parseJson(raw);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invalid JSON: $e')));
      return;
    }
    if (parsed is! Map<String, dynamic>) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON must be an object')));
      return;
    }
    try {
      await _controller.createAiGeneratedPlan(parsed);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI generated plan created')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Map<String, dynamic> _parseJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
    throw const FormatException('Root JSON must be an object');
  }
}


