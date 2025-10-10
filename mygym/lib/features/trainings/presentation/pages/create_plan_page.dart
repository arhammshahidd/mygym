import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/theme/app_theme.dart';
import '../../presentation/controllers/plans_controller.dart';
import '../../../profile/presentation/controllers/profile_controller.dart';

class CreatePlanPage extends StatefulWidget {
  const CreatePlanPage({super.key});

  @override
  State<CreatePlanPage> createState() => _CreatePlanPageState();
}

class _CreatePlanPageState extends State<CreatePlanPage> {
  final _formKey = GlobalKey<FormState>();
  final _planNameCtrl = TextEditingController();
  final _exerciseNameCtrl = TextEditingController();
  final _exerciseTypesCtrl = TextEditingController();
  final _minutesCtrl = TextEditingController();
  final _setsCtrl = TextEditingController();
  final _repsCtrl = TextEditingController();
  final _userLevelCtrl = TextEditingController();
  int _weight = 50;

  DateTime? _fromDate;
  DateTime? _toDate;

  final List<Map<String, dynamic>> _exercises = [];

  PlansController? _controller;
  ProfileController? _profileController;

  @override
  void initState() {
    super.initState();
    try { _controller = Get.find<PlansController>(); } catch (_) {}
    try { _profileController = Get.find<ProfileController>(); } catch (_) {}
  }

  @override
  void dispose() {
    _planNameCtrl.dispose();
    _exerciseNameCtrl.dispose();
    _exerciseTypesCtrl.dispose();
    _minutesCtrl.dispose();
    _setsCtrl.dispose();
    _repsCtrl.dispose();
    _userLevelCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = DateTime.now();
    final first = DateTime(initial.year - 1);
    final last = DateTime(initial.year + 2);
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _fromDate : _toDate) ?? initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
        } else {
          _toDate = picked;
        }
      });
    }
  }

  void _addExercise() {
    if (_planNameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter Exercise Plan Name')),
      );
      return;
    }
    if (_exerciseNameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter Exercise Name')),
      );
      return;
    }
    setState(() {
      _exercises.add({
        'plan_category': _planNameCtrl.text.trim(),
        'exercise_name': _exerciseNameCtrl.text.trim(),
        'exercise_types': int.tryParse(_exerciseTypesCtrl.text.trim()),
        'minutes': int.tryParse(_minutesCtrl.text.trim()),
        'sets': int.tryParse(_setsCtrl.text.trim()),
        'reps': int.tryParse(_repsCtrl.text.trim()),
        'weight_kg': _weight,
      });
      _exerciseNameCtrl.clear();
      _exerciseTypesCtrl.clear();
      _minutesCtrl.clear();
      _setsCtrl.clear();
      _repsCtrl.clear();
      _weight = 50;
    });
  }

  Future<void> _createPlan() async {
    if (_fromDate == null || _toDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select start and end dates')),
      );
      return;
    }
    if (_planNameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter Exercise Plan Name')),
      );
      return;
    }
    if (_exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one exercise')),
      );
      return;
    }

    // Ensure we have a user id
    if (_profileController == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile unavailable. Please relaunch app.')),
      );
      return;
    }
    if (_profileController!.user == null) {
      await _profileController!.loadUserProfileIfNeeded();
    }
    final userId = _profileController!.user?.id;
    if (userId == null || userId == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to detect user. Please re-login.')),
      );
      return;
    }

    final String startDate = _fromDate!.toIso8601String().split('T').first;
    final String endDate = _toDate!.toIso8601String().split('T').first;

    // Map exercises to database schema for app_manual_training_plan_items
    final String planCategory = _planNameCtrl.text.trim();
    final List<Map<String, dynamic>> items = _exercises.map((e) => {
      'workout_name': e['exercise_name'],
      'exercise_types': e['exercise_types'],
      'sets': e['sets'],
      'reps': e['reps'],
      'weight_kg': e['weight_kg'],
      'minutes': e['minutes'],
      'exercise_plan_category': planCategory,
      'user_level': _userLevelCtrl.text.trim(),
    }).toList();

    final int totalWorkouts = items.length;
    final int totalMinutes = items.fold<int>(0, (sum, it) => sum + (it['minutes'] as int? ?? 0));

    // Top-level payload for app_manual_training_plans
    final payload = {
      'user_id': userId,
      'exercise_plan_category': planCategory,
      'start_date': startDate,
      'end_date': endDate,
      'total_workouts': totalWorkouts,
      'training_minutes': totalMinutes,
      'items': items,
    };

    print('🔍 Create Plan - Payload: $payload');
    print('🔍 Create Plan - total_exercises: ${payload['total_exercises']}');
    
    try {
      // Persist plan via controller facade
      if (_controller == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Controller unavailable. Please relaunch app.')),
        );
        return;
      }
      final created = await _controller!.createManualPlan(payload);
      // Optionally trigger approval if desired immediately (kept as manual step per design)
      await _controller?.loadData();
      if (!mounted) return;
      Get.back();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan created. You can now Send for Approval from the list.')),
      );
      // Optionally navigate to detail with created
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.appBackgroundColor,
      appBar: AppBar(
        title: const Text('Create Fitness Plan'),
        backgroundColor: AppTheme.appBackgroundColor,
        foregroundColor: AppTheme.textColor,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Plan Duration'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFieldLabel('From Date'),
                        _dateField(
                          label: 'From',
                          value: _fromDate == null ? 'Select date' : _fromDate!.toString().split(' ').first,
                          onTap: () => _pickDate(isFrom: true),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFieldLabel('To Date'),
                        _dateField(
                          label: 'To',
                          value: _toDate == null ? 'Select date' : _toDate!.toString().split(' ').first,
                          onTap: () => _pickDate(isFrom: false),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Exercise Details'),
              const SizedBox(height: 12),
              
              // Exercise Plan Name
              _buildFieldLabel('Exercise Plan Name'),
              _input(_planNameCtrl, 'Exercise Plan Name'),
              const SizedBox(height: 16),
              
              // User Level
              _buildFieldLabel('User Level'),
              _input(_userLevelCtrl, 'User Level', hint: 'e.g., Beginner, Intermediate, Advanced'),
              const SizedBox(height: 16),
              
              // Workout Name
              _buildFieldLabel('Workout Name'),
              _input(_exerciseNameCtrl, 'Workout Name', hint: 'e.g., Squats'),
              const SizedBox(height: 16),
              
              // Exercise Types and Minutes Row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFieldLabel('Exercise Types'),
                        _input(_exerciseTypesCtrl, 'Exercise Types', hint: 'e.g., 6', keyboardType: TextInputType.number),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFieldLabel('Minutes'),
                        _input(_minutesCtrl, 'Minutes', hint: 'e.g., 60', keyboardType: TextInputType.number),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFieldLabel('Sets'),
                        _input(_setsCtrl, 'Sets', hint: 'e.g., 3', keyboardType: TextInputType.number),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFieldLabel('Reps'),
                        _input(_repsCtrl, 'Reps', hint: 'e.g., 10', keyboardType: TextInputType.number),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Weight Section
              _buildFieldLabel('Weight (kg)'),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackgroundColor,
                  border: Border.all(color: AppTheme.primaryColor),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _weightButton('-', () => setState(() => _weight = (_weight - 1).clamp(0, 1000))),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.appBackgroundColor,
                        border: Border.all(color: AppTheme.primaryColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$_weight kg',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    _weightButton('+', () => setState(() => _weight = (_weight + 1).clamp(0, 1000))),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _addExercise,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: AppTheme.textColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                  ),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Add Exercise'),
                ),
              ),
              const SizedBox(height: 16),
              if (_exercises.isNotEmpty) ...[
                _buildSectionTitle('Added Exercises'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackgroundColor,
                    border: Border.all(color: AppTheme.primaryColor),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        spreadRadius: 1,
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _exercises.asMap().entries.map((e) {
                      final idx = e.key + 1;
                      final ex = e.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.appBackgroundColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$idx',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ex['exercise_name'] ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                      color: AppTheme.textColor,
                                    ),
                                  ),
                                  Text(
                                    '${ex['sets']} sets × ${ex['reps']} reps • ${ex['weight_kg']} kg • ${ex['minutes']} min',
                                    style: const TextStyle(
                                      color: AppTheme.textColor,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => setState(() => _exercises.removeAt(e.key)),
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 24),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _createPlan,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: AppTheme.textColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                  ),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Create Plan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _input(TextEditingController ctrl, String label, {String? hint, TextInputType? keyboardType}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppTheme.textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textColor),
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.textColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primaryColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primaryColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
        ),
        filled: true,
        fillColor: AppTheme.cardBackgroundColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _dateField({required String label, required String value, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppTheme.cardBackgroundColor,
          border: Border.all(color: AppTheme.primaryColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 20, color: AppTheme.textColor),
            const SizedBox(width: 12),
            Text(
              value,
              style: const TextStyle(fontSize: 16, color: AppTheme.textColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.textColor,
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppTheme.textColor,
        ),
      ),
    );
  }

  Widget _weightButton(String text, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.primaryColor,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              spreadRadius: 1,
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textColor,
            ),
          ),
        ),
      ),
    );
  }
}


